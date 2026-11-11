/// A workspace calendar over a calendar API: the module's [CalendarView], in
/// Agenda, Day, Week and Month, under the workspace's app bar, with its
/// Today pill, and the settings sheet.
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
/// The calendar's header holds, beside the month's title, the Today button,
/// which shows while a tap on it would change what the calendar shows and
/// brings it to today on the clock of the chosen zone, the edit mode
/// toggle, the view button, and at the row's end the settings button. The
/// calendar opens on Agenda, out of edit mode unless it is given it. Out of
/// edit mode the calendar is read-only, so nothing is moved, resized or
/// created, and a tap on an item opens its form read-only.
///
/// The settings sheet, which opens from the header's settings button,
/// holds the time zone, the weekday a week starts on, which every view's
/// weeks and columns follow, and which weekdays show, the length of the
/// calendar's slots, which the item form's times step by too, and the
/// hours the calendar shows and schedules in, with whether Week and Day
/// label them AM/PM, and under them whether items may overlap. A pinch on
/// a grid sets the least width of a day in Week, Day and Month and the
/// least height of the timed grids' slots, on the calendar's
/// [CalendarController].
///
/// The settings the calendar opens on ([WorkspaceCalendarExample.settings])
/// hold the history lock and Month's layout, which the sheet does not
/// offer. The lock, off unless they turn it on, in edit mode keeps the
/// past as it is: no item before today, or with
/// [CalendarSettings.lockEarlierToday] before now, is moved, resized,
/// edited or deleted, nor does an item move, resize or get created there,
/// and an item in progress changes only its end. A create with no time
/// left after the lock on its day says so.
///
/// The sheet's overlap switch lets items overlap: in edit mode Week's and
/// Day's moves, resizes and creates then go over other items' times, the
/// items sharing a time side by side, and a [MockCalendarApi] stores them.
/// Off, the gestures keep to free time and the mock API refuses an item
/// whose new times share time with another.
///
/// The sheet's time zone part picks the zone among the device's and those
/// the user added in the sheet's manage mode, which its Manage chip turns
/// on. The zone picked is the store's, which every view then draws on, the
/// item form writes and reads its times on, and the history lock judges
/// on. The store reads [WorkspaceCalendarExample.readAhead] days on each
/// side of the range it shows, so a change of zone finds the shown days
/// read.
///
/// A tap on an item opens its form, which edits it in edit mode unless the
/// history lock holds it locked, and otherwise shows it read-only; a create
/// the calendar's gestures pick opens the create flow over the range
/// picked; Agenda's Edit opens the form, and its Delete asks before it
/// deletes. A write that fails says why.
library;

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'workspace_calendar/calendar_api.dart';
import 'workspace_calendar/calendar_api_source.dart';
import 'workspace_calendar/calendar_item.dart';
import 'workspace_calendar/calendar_settings.dart';
import 'workspace_calendar/harbor_theme.dart';
import 'workspace_calendar/item_builders.dart';
import 'workspace_calendar/item_form.dart';
import 'workspace_calendar/mock_calendar_api.dart';
import 'workspace_calendar/settings_sheet.dart';

/// The calendar under its own Harbor theme, whatever the host's theme.
class WorkspaceCalendarExample extends StatelessWidget {
  const WorkspaceCalendarExample({
    super.key,
    this.today,
    this.api,
    this.clock,
    this.editing = false,
    this.settings = const CalendarSettings(),
    this.calendarTheme,
    this.builders = harborItemBuilders,
    this.readAhead = 2,
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

  /// Whether the calendar opens in edit mode, which the header's edit mode
  /// toggle then turns on and off.
  final bool editing;

  /// The settings the calendar opens on, but for edit mode, which
  /// [editing] gives; the settings sheet then changes those it offers. The
  /// history lock and Month's layout, which it does not offer, keep the
  /// values these give.
  final CalendarSettings settings;

  /// The theme the calendar's views draw with; null gives
  /// [harborCalendarTheme]. It shadows any [CalendarTheme] of the host's.
  final CalendarThemeData? calendarTheme;

  /// What the views draw their items and states with, [harborItemBuilders]
  /// unless given; a null field gives the view's default.
  final ItemBuilders builders;

  /// The days the store reads on each side of the range it shows
  /// ([CachingCalendarStore.readAhead]), 2 unless given, which keeps the
  /// shown days read across a change between any two zones once the
  /// store's reads have answered.
  final int readAhead;

  static final ThemeData _theme = buildHarborTheme();

  @override
  Widget build(BuildContext context) {
    // Above the calendar's state, so every dialog and menu it opens from
    // its own context captures both themes.
    return Theme(
      data: _theme,
      child: CalendarTheme(
        data: calendarTheme ?? harborCalendarTheme,
        child: _WorkspaceCalendar(
          today: today,
          api: api,
          clock: clock ?? DateTime.now,
          editing: editing,
          settings: settings,
          builders: builders,
          readAhead: readAhead,
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
    required this.settings,
    required this.builders,
    required this.readAhead,
  });

  final DateTime? today;
  final CalendarApi? api;
  final DateTime Function() clock;
  final bool editing;
  final CalendarSettings settings;
  final ItemBuilders builders;
  final int readAhead;

  @override
  State<_WorkspaceCalendar> createState() {
    return _WorkspaceCalendarState();
  }
}

class _WorkspaceCalendarState extends State<_WorkspaceCalendar> {
  late final CachingCalendarStore<ItemPayload> _store;

  /// The API [_store] reads and writes through, kept so a
  /// [MockCalendarApi]'s overlap rule follows [_settings]
  /// ([_setApiOverlaps]). A mock is seeded around the device's today, as
  /// [initState] reads it before [_store] is made.
  late final CalendarApi _api =
      widget.api ??
      MockCalendarApi.seeded(
        CalendarDates.dateOnly(widget.today ?? widget.clock().toLocal()),
      );

  /// The zones the user added in the settings sheet's manage mode.
  final CalendarZoneController _zones = CalendarZoneController();

  /// The calendar's view, selected day and zoom sizes, which a pinch on a
  /// grid sets. The calendar opens on Agenda and today. Made
  /// where [initState] first reads it, after [_store], whose zone [_today]
  /// reads.
  late final CalendarController _controller = CalendarController(
    view: CalendarViewKind.agenda,
    selectedDay: _today(),
  );

  /// Whether the calendar shows Month, which the Scaffold's keyboard inset
  /// follows. Only a change of it builds this state again, so a pinch's
  /// zoom builds nothing here.
  bool _showsMonth = false;

  /// What the settings sheet last chose, and before it chooses, the
  /// defaults with the edit mode the calendar was given.
  late CalendarSettings _settings = widget.settings.copyWith(
    editing: widget.editing,
  );

  @override
  void initState() {
    super.initState();
    _setApiOverlaps(_settings);
    _store = CachingCalendarStore<ItemPayload>(
      dataSource: CalendarApiSource(_api),
      hours: _settings.hours,
      readAhead: widget.readAhead,
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
    _zones.dispose();
    super.dispose();
  }

  /// The day the calendar marks as today when called: the widget's today,
  /// or the day of the clock's reading on the clock of the store's zone,
  /// the device's with none, as [CalendarView] takes a UTC one.
  DateTime _today() {
    return CalendarDates.dateOnly(
      widget.today ?? CalendarDates.inZone(widget.clock(), zone: _store.zone),
    );
  }

  /// The time the calendar's edit policy answers at when called, which a
  /// form reads when it opens and at Save: the clock's reading on the
  /// clock of the store's zone, the device's with none, with the day the
  /// calendar marks as today.
  CalendarNow _currentNow() {
    final now = CalendarDates.inZone(widget.clock(), zone: _store.zone);
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

  /// The style of the header's settings button, as the built-in header's
  /// view button: a 32 px circle around a 22 px icon.
  static const ButtonStyle _headerButton = ButtonStyle(
    visualDensity: VisualDensity.compact,
    fixedSize: WidgetStatePropertyAll<Size>(Size.square(32.0)),
    padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.zero),
    iconSize: WidgetStatePropertyAll<double>(22.0),
    shape: WidgetStatePropertyAll<OutlinedBorder>(CircleBorder()),
  );

  /// The calendar's built-in header, then 4 px on, at the row's end, the
  /// settings button, drawn as the header's view button is.
  Widget _buildHeader(BuildContext context, CalendarHeaderDetails details) {
    return Row(
      children: <Widget>[
        Expanded(child: defaultCalendarHeaderBuilder(context, details)),
        const SizedBox(width: 4.0),
        IconButton(
          icon: const Icon(Icons.tune),
          tooltip: "Calendar settings",
          color: CalendarTheme.of(context).text,
          style: _headerButton,
          onPressed: _openSettings,
        ),
      ],
    );
  }

  void _openSettings() {
    showCalendarSettings(
      context,
      settings: _settings,
      zone: _store.zone,
      zones: _zones,
      clock: widget.clock,
      onChanged: _applySettings,
      onZoneChanged: (zone) {
        _store.zone = zone;
      },
    );
  }

  /// Applies what the settings sheet or the header's edit mode toggle
  /// chose; the calendar itself moves a selected day new weekdays hide to
  /// the nearest shown one.
  void _applySettings(CalendarSettings settings) {
    setState(() {
      _settings = settings;
    });
    _setApiOverlaps(settings);
    _store.hours = settings.hours;
  }

  /// The header's edit mode toggle.
  void _setEditing(bool editing) {
    _applySettings(_settings.copyWith(editing: editing));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Writes a grid move or resize, and says why where it fails.
  Future<void> _move(CalendarMoveRequest<ItemPayload> request) async {
    try {
      await _store.requestMove(request.requested);
    } on Object catch (error) {
      _showWriteFailure(error);
    }
  }

  /// A grid write or a delete failed with [error], whatever shows now.
  void _showWriteFailure(Object error) {
    if (mounted) {
      _showMessage(writeFailureMessage(error));
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

  Future<void> _openCreateFlow(CalendarCreateDetails details) {
    return showCreateFlow(
      context,
      store: _store,
      range: details.range,
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
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await _store.requestDelete(item.id!);
    } on Object catch (error) {
      _showWriteFailure(error);
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
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: CalendarView<ItemPayload>(
              store: _store,
              controller: _controller,
              editable: _settings.editing,
              onEditableChanged: _setEditing,
              headerBuilder: _buildHeader,
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
              onMoveRequest: _move,
              onEditRequest: _openEditForm,
              onDeleteRequest: _deleteFromCard,
              onCreateRefused: (day) {
                _showMessage("No new item can start on this day.");
              },
            ),
          ),
        ],
      ),
    );
  }
}
