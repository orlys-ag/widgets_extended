/// A workspace calendar over a calendar API: the module's [CalendarView], in
/// Agenda, Day, Week and Month, under the workspace's app bar, the calendar
/// bar the app bar opens, and the settings sheet.
///
/// The calendar reads the range it shows through a [CachingCalendarStore]
/// over a [CalendarApiSource], which caches the days it has read and
/// writes one change per item at a time, over a [MockCalendarApi] seeded
/// around today where no API is given. It draws its items with
/// [harborItemBuilders], unless given others, in the Harbor theme,
/// [harborCalendarTheme], and a screen reader hears each of Month's chips
/// name its item's type. The days of Agenda's and Day's calendar card
/// carry a dot for each type of item they have, in the type's Harbor
/// colour ([harborDayBadges]).
///
/// The app bar's chevron opens a bar under it, and closes it again, the
/// bar sliding down from under the app bar, or back up, over
/// [harborMotionDuration]: the calendar bar ([CalendarBar]), holding
/// Today, the edit mode switch, the weekday a week starts on, which every
/// view's weeks and columns follow, and which weekdays show, the hours the
/// calendar shows and schedules in, and whether Week and Day label them
/// AM/PM. The calendar opens on Agenda, out of edit mode unless it is
/// given it, and with the bar closed. Out of edit mode the calendar is
/// read-only, so nothing is moved, resized or created, and a tap on an
/// item opens its form read-only. The settings sheet, which opens from the
/// app bar's More menu, chooses how Month fits its weeks, the length of the
/// calendar's slots, which the item form's times step by too, and on the
/// calendar's [CalendarController] the least width of a day in Week, Day
/// and Month and the least height of the timed grids' slots, which a pinch
/// on a grid sets too.
///
/// The sheet also chooses the history lock, which in edit mode keeps the
/// past as it is: no item before today, or with its second switch before
/// now, is moved, resized, edited or deleted, nor does an item move,
/// resize or get created there, and an item in progress changes only its
/// end. A create with no time left after the lock on its day says so.
///
/// Its last switch lets items overlap: in edit mode Week's and Day's
/// moves, resizes and creates then go over other items' times, the items
/// sharing a time side by side, and a [MockCalendarApi] stores them. Off,
/// the gestures keep to free time and the mock API refuses an item whose
/// new times share time with another.
///
/// Today, in the calendar bar, selects today, or the shown day nearest it,
/// in every view, and slides a strip a drag moved away back to it.
///
/// A tap on an item opens its form, which edits it in edit mode unless the
/// history lock holds it locked, and otherwise shows it read-only; a create
/// the calendar's gestures pick opens the create flow over the range
/// picked; Agenda's Edit opens the form, and its Delete asks before it
/// deletes. A write that fails says why.
library;

import 'package:flutter/material.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';

import 'workspace_calendar/calendar_api.dart';
import 'workspace_calendar/calendar_api_source.dart';
import 'workspace_calendar/calendar_bar.dart';
import 'workspace_calendar/calendar_item.dart';
import 'workspace_calendar/calendar_settings.dart';
import 'workspace_calendar/harbor_theme.dart';
import 'workspace_calendar/item_builders.dart';
import 'workspace_calendar/item_form.dart';
import 'workspace_calendar/mock_calendar_api.dart';
import 'workspace_calendar/settings_sheet.dart';

/// The entries of the app bar's More menu.
enum _MoreAction { settings }

/// The calendar under its own Harbor theme, whatever the host's theme.
class WorkspaceCalendarExample extends StatelessWidget {
  const WorkspaceCalendarExample({
    super.key,
    this.today,
    this.api,
    this.clock,
    this.editing = false,
    this.calendarTheme = harborCalendarTheme,
    this.builders = harborItemBuilders,
  });

  /// The day the calendar opens on and marks as today. Null opens on the
  /// day [clock] reads and marks the day it reads from then on, so the
  /// mark moves at midnight.
  final DateTime? today;

  /// The store the calendar reads and writes, read once when the calendar
  /// is first built. Null uses a [MockCalendarApi] seeded around [today],
  /// at [defaultCalendarLatency] and with no failures.
  final CalendarApi? api;

  /// Reads the current time, which the timed grids mark with a line. The
  /// calendar reads it when first built and again at the start of each
  /// minute. Null reads [DateTime.now].
  final DateTime Function()? clock;

  /// Whether the calendar opens in edit mode, which the calendar bar's
  /// edit mode switch then turns on and off.
  final bool editing;

  /// The theme the calendar's views draw with, [harborCalendarTheme] unless
  /// given. It shadows any [CalendarTheme] of the host's.
  final CalendarThemeData calendarTheme;

  /// What the views draw their items and states with, [harborItemBuilders]
  /// unless given; a null field gives the view's default.
  final ItemBuilders builders;

  static final ThemeData _theme = buildHarborTheme();

  @override
  Widget build(BuildContext context) {
    // Above the calendar's state, so every dialog and menu it opens from
    // its own context captures both themes.
    return Theme(
      data: _theme,
      child: CalendarTheme(
        data: calendarTheme,
        child: _WorkspaceCalendar(
          today: today,
          api: api,
          clock: clock ?? DateTime.now,
          editing: editing,
          builders: builders,
        ),
      ),
    );
  }
}

class _WorkspaceCalendar extends StatefulWidget {
  const _WorkspaceCalendar({
    required this.today,
    required this.api,
    required this.clock,
    required this.editing,
    required this.builders,
  });

  final DateTime? today;
  final CalendarApi? api;
  final DateTime Function() clock;
  final bool editing;
  final ItemBuilders builders;

  @override
  State<_WorkspaceCalendar> createState() {
    return _WorkspaceCalendarState();
  }
}

class _WorkspaceCalendarState extends State<_WorkspaceCalendar>
    with SingleTickerProviderStateMixin {
  late final CachingCalendarStore<ItemPayload> _store;

  /// The API [_store] reads and writes through, kept so a
  /// [MockCalendarApi]'s overlap rule follows [_settings]
  /// ([_setApiOverlaps]).
  late final CalendarApi _api = widget.api ?? MockCalendarApi.seeded(_today());

  /// The calendar's view, selected day and zoom sizes, which Today and the
  /// settings sheet's sliders set; the calendar opens on Agenda.
  final CalendarController _controller = CalendarController(
    view: CalendarViewKind.agenda,
  );

  /// Whether the calendar shows Month, which the Scaffold's keyboard inset
  /// follows. Only a change of it builds this state again, so a pinch's
  /// zoom builds nothing here.
  bool _showsMonth = false;

  /// What the calendar bar and the settings sheet last chose, and before
  /// they choose, the defaults with the edit mode the calendar was given.
  late CalendarSettings _settings = CalendarSettings(editing: widget.editing);

  /// Whether the calendar bar is open, or opening.
  bool _barOpen = false;

  /// How far the calendar bar shows, 0 closed and 1 open, animated on
  /// [harborMotionCurve] by [_toggleBar].
  late final AnimationController _barController = AnimationController(
    vsync: this,
    duration: harborMotionDuration,
  );

  @override
  void initState() {
    super.initState();
    _setApiOverlaps(_settings);
    _store = CachingCalendarStore<ItemPayload>(
      dataSource: CalendarApiSource(_api),
      hours: _settings.hours,
      onWriteFailed: _handleWriteFailed,
    );
    _controller.addListener(_handleControllerChange);
  }

  /// Has a [MockCalendarApi] refuse overlapping items where [settings]
  /// forbid them, as their edit policy does, so the API and the calendar
  /// agree.
  void _setApiOverlaps(CalendarSettings settings) {
    final api = _api;
    if (api is MockCalendarApi) {
      api.allowsOverlaps = settings.allowsOverlaps;
    }
  }

  @override
  void dispose() {
    // The calendar has let go of both by now: an element's children
    // unmount before it does.
    _controller.dispose();
    _store.dispose();
    _barController.dispose();
    super.dispose();
  }

  /// The day the calendar marks as today when called.
  DateTime _today() {
    return dateOnly(widget.today ?? widget.clock());
  }

  /// The time the calendar's edit policy answers at when called, which a
  /// form reads when it opens and at Save: the clock's, with the day the
  /// calendar marks as today.
  CalendarNow _currentNow() {
    final now = widget.clock();
    return CalendarNow(time: now, today: widget.today ?? now);
  }

  void _handleControllerChange() {
    final month = _controller.view == CalendarViewKind.month;
    if (month != _showsMonth) {
      setState(() {
        _showsMonth = month;
      });
    }
  }

  /// Closes the month picker, then selects today, or the shown day nearest
  /// it.
  void _goToToday() {
    _controller.goTo(_today());
  }

  /// Opens the calendar bar, or closes it.
  void _toggleBar() {
    setState(() {
      _barOpen = !_barOpen;
    });
    _barController.animateTo(_barOpen ? 1.0 : 0.0, curve: harborMotionCurve);
  }

  void _openSettings() {
    showCalendarSettings(
      context,
      settings: _settings,
      controller: _controller,
      onChanged: _applySettings,
    );
  }

  /// Applies what the calendar bar or the settings sheet chose; the
  /// calendar itself moves a selected day new weekdays hide to the nearest
  /// shown one.
  void _applySettings(CalendarSettings settings) {
    setState(() {
      _settings = settings;
    });
    _setApiOverlaps(settings);
    _store.hours = settings.hours;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// A grid write or a delete failed, whatever shows now.
  void _handleWriteFailed(CalendarWriteFailure failure) {
    if (mounted) {
      _showMessage(writeFailureMessage(failure.error));
    }
  }

  /// The form of the tapped item: editable where the calendar reports it
  /// so, in edit mode with the settings' edit policy letting the item be
  /// edited, and read-only otherwise.
  void _openEntry(CalendarEntryTapDetails<ItemPayload> details) {
    final id = details.entry.id!;
    if (details.editable) {
      showEditForm(
        context,
        store: _store,
        id: id,
        policy: _settings.editPolicy,
        now: _currentNow,
        slotMinutes: _settings.slotMinutes,
      );
    } else {
      showItemDetails(context, store: _store, id: id);
    }
  }

  Future<void> _openCreateFlow(CreateRange range) {
    return showCreateFlow(
      context,
      store: _store,
      range: range,
      policy: _settings.editPolicy,
      now: _currentNow,
      slotMinutes: _settings.slotMinutes,
    );
  }

  void _openEditForm(CalendarItem item) {
    showEditForm(
      context,
      store: _store,
      id: item.id!,
      policy: _settings.editPolicy,
      now: _currentNow,
      slotMinutes: _settings.slotMinutes,
    );
  }

  Future<void> _deleteFromCard(CalendarItem item) async {
    final confirmed = await confirmDelete(context);
    if (confirmed && mounted) {
      _store.requestDelete(item.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A form's keyboard leaves the month board's height, and so its
      // weeks, as they are; the form's dialog pads itself by the keyboard.
      resizeToAvoidBottomInset: !_showsMonth,
      appBar: AppBar(
        scrolledUnderElevation: 0.0,
        titleSpacing: 0.0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: "Back",
          onPressed: () {
            Navigator.maybePop(context);
          },
        ),
        title: const Text(
          "Lu Test Workspace",
          style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.w600),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: "Calendar settings bar",
            onPressed: _toggleBar,
            icon: AnimatedRotation(
              turns: _barOpen ? 0.5 : 0.0,
              duration: harborMotionDuration,
              curve: harborMotionCurve,
              child: const Icon(Icons.settings),
            ),
          ),
          PopupMenuButton<_MoreAction>(
            tooltip: "More",
            icon: const Icon(Icons.more_vert),
            color: HarborColors.surface,
            onSelected: (action) {
              switch (action) {
                case _MoreAction.settings:
                  _openSettings();
              }
            },
            itemBuilder: (context) {
              return const <PopupMenuEntry<_MoreAction>>[
                PopupMenuItem<_MoreAction>(
                  value: _MoreAction.settings,
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.tune, color: HarborColors.text),
                      SizedBox(width: 12.0),
                      Flexible(child: Text("Calendar settings")),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildBar(),
          Expanded(
            child: CalendarView<ItemPayload>(
              store: _store,
              controller: _controller,
              editable: _settings.editing,
              editPolicy: _settings.editPolicy,
              weekdays: _settings.weekdays,
              slotMinutes: _settings.slotMinutes,
              hourLabelFormat: _settings.hourLabelFormat,
              monthLayout: _settings.monthLayout,
              clock: widget.clock,
              today: widget.today,
              blockBuilder: widget.builders.block,
              chipBuilder: widget.builders.chip,
              cardBuilder: widget.builders.card,
              cardExtentOf: widget.builders.cardExtent,
              addButtonBuilder: widget.builders.addButton,
              loadingBuilder: widget.builders.loading,
              failureBuilder: widget.builders.failure,
              // Whatever the builders, a chip names its item's type, and a
              // day of the calendar card marks each type it has.
              entryKindOf: harborEntryKind,
              dayBadges: harborDayBadges,
              onEntryTap: _openEntry,
              onCreateRange: _openCreateFlow,
              onEditRequest: _openEditForm,
              onDeleteRequest: _deleteFromCard,
              onCreateRefused: (day) {
                _showMessage("Past times are locked.");
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The calendar bar, at the height [_barController] gives it, its bottom
  /// part showing first so it slides down from under the app bar; nothing
  /// while it is closed.
  Widget _buildBar() {
    return AnimatedBuilder(
      animation: _barController,
      child: CalendarBar(
        key: calendarBarKey,
        settings: _settings,
        onChanged: _applySettings,
        onToday: _goToToday,
      ),
      builder: (context, child) {
        final shown = _barController.value;
        if (shown == 0.0) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: shown,
            child: child,
          ),
        );
      },
    );
  }
}

/// The key of the calendar bar the app bar's chevron opens.
const ValueKey<String> calendarBarKey = ValueKey<String>("calendar-bar");
