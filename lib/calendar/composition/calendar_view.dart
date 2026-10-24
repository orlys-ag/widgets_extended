/// The calendar: its four views composed under a header and the folding
/// calendar card, the controller a host sets and listens to, and what a
/// tap on an entry reports.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../dates/calendar_dates.dart';
import '../dates/calendar_labels.dart';
import '../entries/calendar_entry.dart';
import '../policy/history_lock.dart';
import '../presentation/calendar_builders.dart';
import '../presentation/calendar_theme.dart';
import '../store/calendar_store.dart';
import '../views/day_list.dart';
import '../views/month_board.dart';
import '../views/month_picker.dart';
import '../views/pinch_zoom.dart';
import '../views/timed_grid.dart';
import 'calendar_card.dart';
import 'calendar_header.dart';
import 'calendar_theme_extension.dart';

part 'calendar_controller.dart';

/// A range of days, both inclusive.
typedef _Range = ({DateTime first, DateTime last});

/// The error a [CalendarView] given [views] throws from its build: for an
/// empty list, and for a list that names a view twice, the first view it
/// names twice; null for a list that names each of its views once.
ArgumentError? calendarViewsError(List<CalendarViewKind> views) {
  if (views.isEmpty) {
    return ArgumentError.value(views, "views", "lists no view");
  }
  final seen = <CalendarViewKind>{};
  for (final view in views) {
    if (!seen.add(view)) {
      return ArgumentError.value(views, "views", "lists ${view.name} twice");
    }
  }
  return null;
}

/// The view a calendar listing [views] shows for [requested]: [requested]
/// where [views] lists it, and otherwise the first view [views] lists.
CalendarViewKind calendarOpeningView(
  List<CalendarViewKind> views,
  CalendarViewKind? requested,
) {
  if (requested != null && views.contains(requested)) {
    return requested;
  }
  return views.first;
}

/// A tap on an entry: the [entry] as the store holds it, and whether it is
/// [editable], in edit mode with the history lock not holding it
/// [EntryHold.locked].
@immutable
class CalendarEntryTapDetails<T> {
  const CalendarEntryTapDetails({required this.entry, required this.editable});

  /// The stored entry, without a pending move's requested time.
  final CalendarEntry<T> entry;

  /// Whether a host's form may change the entry: the calendar is
  /// [CalendarView.editable] and the history lock does not hold the entry
  /// [EntryHold.locked].
  final bool editable;
}

/// A calendar of [store]'s entries in the views [views] lists, under a
/// header that names the month and switches between them.
///
/// The views:
///
/// - Agenda: the calendar card's month over a list of the days, one after
///   another, each day's entries beside their times and lengths. The month
///   is a `MonthStrip` under the weekdays' three-letter names, one month at
///   a time, each day a cell with its number on a circle and a badge when
///   it has entries. A tap selects a day, and the arrow keys move the
///   selection once a tap has given the month focus. A horizontal drag
///   slides the next or the previous month in, the card's height
///   following, a fling carrying it past several months; the chevrons
///   slide it a month at a time. None of them selects: the header names
///   the month the card shows, and [CalendarController.goTo] of the
///   selected day brings it back. The list runs both ways from the
///   selected day: a selected day scrolls to its top, and a drag or a
///   fling of the list selects each day it brings to the top, its header
///   sticking while its entries scroll under it. An entry wholly outside
///   [hours] shows only in a count on a notice banner. A line marks the
///   current time over the rows of the clock's day. In edit mode the list
///   marks each gap in [hours] with a dashed row whose button reports a
///   create through [onCreateRange], and each card's builder receives the
///   [CalendarCardDetails.onEdit] and [CalendarCardDetails.onDelete] the
///   history lock allows, which report through [onEditRequest] and
///   [onDeleteRequest]; the default card offers neither. A
///   drag of the list folds the month into the week of the selected day,
///   and the pull tab under the card folds or unfolds it as far as a drag
///   on it moves, a tap on it switching; a downward drag on the folded
///   strip unfolds it too. Once folded the week strip takes its place,
///   opening on that week.
/// - Day: the calendar card folded, its week strip a week's worth of days
///   whose days a tap selects and which a drag slides day by day without
///   selecting, the header naming the month of the day at its middle; and
///   under it a timed grid of the selected day, with no day header, whose
///   blocks show their times and summaries. The pull tab unfolds the
///   month, and a drag up the grid folds it again.
/// - Week: a timed grid of the selected day's week under the header's
///   card, its days in columns under a day header whose tap selects a day.
/// - Month: the month's weeks under the header's card, each entry a chip
///   on the days it covers, from its start's day to the last day it has a
///   part in, the weeks laid out as [monthLayout] says. A
///   tap on a chip reports the entry, and a tap anywhere else on a day
///   opens that day in Day where [views] lists Day, and otherwise selects
///   it. In edit mode a long press on a day reports a create through
///   [onCreateRange] at the day's first free slot the history lock leaves
///   free, selecting the day when it is in the month, or, where the lock
///   leaves no slot of [hours] that day, [onCreateRefused].
///
/// An entry runs from its start to its end ([CalendarEntry]): Week and Day
/// draw a timed entry as one block per shown day it covers, at its exact
/// minutes, and an all-day entry as a bar across those days in a strip
/// above the hours, and Agenda lists it under each day it covers with that
/// day's part of it. In Week and Day a tap on a block or a bar, and in
/// Month on a chip, reports the stored entry through [onEntryTap]. In edit
/// mode, which [editable] turns on, Week's and Day's blocks move, keeping
/// the entry's length, and resize, a bar dropped on a slot makes its entry
/// an hour long there, and a block dropped on a day of the strip makes its
/// entry all-day on that day; in Week bars move and resize by days. A drag
/// over empty slots reports one continuous range through [onCreateRange],
/// across days too, and one over the strip's empty days an all-day range
/// of them, which stays marked until its future completes. Out of edit mode the calendar is read-only. In
/// edit mode the history lock, which [lockPast] and [lockEarlierToday]
/// choose ([HistoryLock.of]), keeps the past as it is. A pinch of two
/// fingers on Week's, Day's or Month's grid sets the controller's zoom
/// sizes. A selected day is always on a weekday [weekdays] shows. Every
/// view rings today's number.
///
/// The header's chevrons step a day in Day, a week in Week and in folded
/// Agenda, and a month in unfolded Agenda and in Month. A tap on the
/// title opens the month picker, a [MonthPicker], until the title is
/// tapped again: in Agenda's and Day's card it fades in over the days, the
/// card's height moving from theirs to its; in Week and Month it fades in
/// under the header as the header's card grows to hold it. While it shows,
/// the title names its year, and the chevrons or a swipe across it step a
/// year; a month picked selects its day of the selected day's day of the
/// month, as a month step does. [headerBuilder] builds the header in
/// place of the built-in one, and [showsHeader] false builds none, nor in
/// Week and Month the header's card. The built-in header's view menu needs
/// [MaterialLocalizations] above the calendar.
///
/// [controller] holds the view and the selected day, which the host sets
/// and listens to, the range of days the calendar asks [store] to show,
/// and the zoom sizes; with none the calendar makes its own. A store shows
/// one range at a time, so it serves one calendar: two calendars on one
/// store each move it off the other's range when they ask, and the one
/// whose range it does not show draws its views ready only where the
/// store has read their days, until its own next ask.
///
/// The calendar opens no route, dialog or form but the built-in header's
/// view menu, builds no `Scaffold` or app bar, and never writes [store]'s
/// settings: the host sets the store's hours to [hours], which a debug
/// build asserts. It disposes no store. It draws in the [CalendarTheme]
/// above it; with none, under a Material [Theme], in a
/// [CalendarThemeExtension] of the [ThemeData], or with none the theme
/// [CalendarThemeExtension.fromColorScheme] gives the [ColorScheme]; and
/// with no [Theme] either, in the built-in theme. Under a [Theme] with no
/// [Material] above, it builds a transparent one under it, which sets the
/// theme's `bodyMedium` as the text style the views draw over. The card's
/// fold and the month picker move over the theme's motion.
///
/// [views] lists the views the header's menu offers, in its order; a list
/// that is empty or names a view twice throws an [ArgumentError] from the
/// build, in a release build as in a debug one.
///
/// [slotMinutes] is the slot of Week's and Day's grids, one row each, the
/// step their gestures snap to, the length of the slot Agenda's add button
/// and Month's long press create, and the grid those round the history
/// lock's first free time up to. A value [slotMinuteChoices] does not hold
/// throws an [ArgumentError] from the build, in a release build as in a
/// debug one, and [hours] off its grid ([DayHours.isOnSlotsOf]) fail an
/// assertion in a debug build; the views show and schedule in [hours]
/// rounded out to it ([DayHours.roundedOutTo]), which are [hours]
/// themselves on the grid.
class CalendarView<T> extends StatefulWidget {
  const CalendarView({
    super.key,
    required this.store,
    this.controller,
    this.views = CalendarViewKind.values,
    this.editable = false,
    this.lockPast = false,
    this.lockEarlierToday = false,
    this.weekdays = WeekdaySet.all,
    this.hours = DayHours.allDay,
    this.slotMinutes = defaultSlotMinutes,
    this.hourLabelFormat = HourLabelFormat.twentyFourHour,
    this.monthLayout = MonthLayout.fitScreen,
    this.maxDayCount,
    this.clock,
    this.today,
    this.blockBuilder,
    this.chipBuilder,
    this.cardBuilder,
    this.cardExtentOf,
    this.addButtonBuilder,
    this.loadingBuilder,
    this.failureBuilder,
    this.entryKindOf,
    this.onEntryTap,
    this.onCreateRange,
    this.onEditRequest,
    this.onDeleteRequest,
    this.onCreateRefused,
    this.showsHeader = true,
    this.headerBuilder,
  });

  /// The entries the calendar shows and its views write; its hours must be
  /// [hours]. The calendar asks it to show the range of days its view
  /// shows, and never disposes it.
  final CalendarStore<T> store;

  /// Holds the view, the selected day, the visible range and the zoom
  /// sizes; null for a controller of the calendar's own. A controller
  /// serves one calendar at a time. One whose view [views] does not list
  /// fails an assertion in a debug build, and shows the first view [views]
  /// lists.
  final CalendarController? controller;

  /// The views the header's menu offers, in its order, each once; the
  /// calendar opens on the first unless [controller] names another. With
  /// one, the header names it with no menu.
  final List<CalendarViewKind> views;

  /// Whether the calendar is in edit mode: Week's and Day's blocks move
  /// and resize, a create gesture reports through [onCreateRange], and
  /// Agenda's card builder receives the edit and delete requests the
  /// history lock allows.
  final bool editable;

  /// Whether, in edit mode, the history lock holds the days before today.
  final bool lockPast;

  /// Whether, in edit mode and under [lockPast], the history lock holds
  /// today up to the current minute too.
  final bool lockEarlierToday;

  /// The weekdays the calendar shows, and the one its weeks start on. A
  /// change moves a selected day it hides to the nearest shown one.
  final WeekdaySet weekdays;

  /// The hours the calendar shows and schedules in; the store's hours must
  /// be these, and they start and end on the grid of [slotMinutes], both of
  /// which a debug build asserts.
  final DayHours hours;

  /// The length of one slot, in minutes: one of [slotMinuteChoices], or the
  /// build throws an [ArgumentError].
  final int slotMinutes;

  /// The format Week's and Day's grids and Agenda's times label the hours
  /// in.
  final HourLabelFormat hourLabelFormat;

  /// How Month lays out a week whose chips its share of the height does
  /// not hold.
  final MonthLayout monthLayout;

  /// The most days, counting each day it has any part of, that a create
  /// drag across days in Week, over the slots or across the all-day strip,
  /// a strip bar's day-edge resize, and Week's end handle dragged into a
  /// later day may give a range: one dragged past them is held at the
  /// latest range they admit, which a release writes or reports. A move
  /// keeps the days an entry covers, except where it crosses a midnight,
  /// and no limit applies to it. Null for no limit.
  final int? maxDayCount;

  /// Reads the current time, which the calendar reads when first built and
  /// again at the start of each minute; null reads [DateTime.now].
  final DateTime Function()? clock;

  /// The day the calendar marks as today and opens on; null marks the day
  /// [clock] reads, moving at midnight.
  final DateTime? today;

  /// Draws Week's and Day's blocks; null for the module's default.
  final CalendarBlockBuilder<T>? blockBuilder;

  /// Draws Month's chips and cards, and the bars of Week's and Day's
  /// all-day strip; null for the module's default.
  final CalendarChipBuilder<T>? chipBuilder;

  /// Draws Agenda's cards; null for the module's default.
  final CalendarCardBuilder<T>? cardBuilder;

  /// The height of [cardBuilder]'s card of an entry; null for the default
  /// card's.
  final double Function(CalendarShownEntry<T> entry)? cardExtentOf;

  /// Draws Agenda's add buttons; null for the module's default.
  final CalendarAddButtonBuilder? addButtonBuilder;

  /// Draws the views' loading states; null for the module's default.
  final CalendarLoadingBuilder? loadingBuilder;

  /// Draws the views' failure states; null for the module's default.
  final CalendarFailureBuilder? failureBuilder;

  /// The word naming an entry's kind in what a screen reader hears for its
  /// chip in Month; null leaves it out.
  final String? Function(CalendarEntry<T> entry)? entryKindOf;

  /// A tap on a block or a bar in Week or Day, or on a chip in Month, of an
  /// entry that is not pending and that the store holds; null reports
  /// nothing.
  final ValueChanged<CalendarEntryTapDetails<T>>? onEntryTap;

  /// A create the calendar's gestures picked, in edit mode: the range a
  /// gesture picked in Week or Day, which stays marked until the future
  /// completes; a gap's first free slot in Agenda, the add button's; and a
  /// day's first free slot in Month, a long press's. Null reports nothing,
  /// and the marked range clears at once.
  final Future<void> Function(CreateRange range)? onCreateRange;

  /// An edit request from an Agenda card, with the stored entry: a
  /// [cardBuilder] calling [CalendarCardDetails.onEdit] makes it; null
  /// reports nothing.
  final ValueChanged<CalendarEntry<T>>? onEditRequest;

  /// A delete request from an Agenda card, with the stored entry: a
  /// [cardBuilder] calling [CalendarCardDetails.onDelete] makes it; null
  /// reports nothing. The calendar deletes nothing itself.
  final ValueChanged<CalendarEntry<T>>? onDeleteRequest;

  /// Month's long press, in edit mode, on a day the history lock leaves no
  /// slot of [hours] on; null reports nothing.
  final ValueChanged<DateTime>? onCreateRefused;

  /// Whether the calendar builds a header; false builds none, whatever
  /// [headerBuilder], and in Week and Month no header card.
  final bool showsHeader;

  /// Builds the header in the built-in one's place, from what it shows and
  /// the actions it calls; null for [defaultCalendarHeaderBuilder]. A throw
  /// in it costs the header alone.
  final CalendarHeaderBuilder? headerBuilder;

  @override
  State<CalendarView<T>> createState() {
    return _CalendarViewState<T>();
  }
}

class _CalendarViewState<T> extends State<CalendarView<T>>
    with TickerProviderStateMixin {
  /// The host's controller, or one of this state's own, which [dispose]
  /// disposes. The view and the selected day live on it alone.
  late CalendarController _controller;
  late bool _ownsController;

  /// The views the state works from: [CalendarView.views], unmodifiable,
  /// or every view while [_viewsError] stands.
  List<CalendarViewKind> _views = CalendarViewKind.values;

  /// What [calendarViewsError] answers for [CalendarView.views], which the
  /// build throws.
  ArgumentError? _viewsError;

  /// The error the build throws for a [CalendarView.slotMinutes] that
  /// [slotMinuteChoices] does not hold, or null.
  ArgumentError? get _slotMinutesError {
    final slotMinutes = widget.slotMinutes;
    if (slotMinuteChoices.contains(slotMinutes)) {
      return null;
    }
    return ArgumentError.value(
      slotMinutes,
      "slotMinutes",
      "is not one of $slotMinuteChoices",
    );
  }

  /// The hours the views show and schedule in: [CalendarView.hours]
  /// rounded out to the grid of [CalendarView.slotMinutes].
  DayHours get _hours {
    return widget.hours.roundedOutTo(widget.slotMinutes);
  }

  /// The clock's time, read again at the start of each minute.
  late final ValueNotifier<DateTime> _now;

  /// The day marked as today. The month board's cells listen to it,
  /// because its cell builder re-runs only when an axis or a cell's
  /// selection changes.
  late final ValueNotifier<DateTime> _today;

  /// Fires at the start of the next minute, to read the clock again.
  Timer? _minuteTimer;

  /// The history lock the lock choices give at the minute [_now] holds.
  late HistoryLock _lock;

  /// A day of the month the calendar card shows and the header names
  /// since a slide of the month strip, a chevron or a drag of the week
  /// strip moved the card off the selected day's month or week: the first
  /// day of the month the month strip rests on, or the day at the middle
  /// of the week strip. Null while the card shows the selected day.
  DateTime? _browsedDay;

  /// The month grid of the selected day.
  late MonthGrid _grid;

  /// Whether the calendar card settles on the selected day's week rather
  /// than its month. Only meaningful in Agenda and Day, which open
  /// unfolded and folded.
  bool _collapsed = false;

  /// Whether the month picker shows, and the year it shows.
  bool _picksMonth = false;
  int _pickerYear = 0;

  /// Counts the calls that bring the week strip back to the selected day,
  /// which `WeekStrip.recalls` passes on.
  int _stripRecalls = 0;

  /// How far the calendar card has folded, 0 for the month and 1 for its
  /// week: linear, so a drag on the pull tab moves it with the finger.
  late final AnimationController _collapseController = AnimationController(
    vsync: this,
  );

  /// How far the month picker has come in, 0 for out and 1 for in.
  late final AnimationController _pickerShown = AnimationController(
    vsync: this,
  );

  /// The theme [_resolveTheme] resolved, which the state draws and
  /// animates its own parts with, and the one it puts above the views,
  /// null where it puts none.
  CalendarThemeData _theme = const CalendarThemeData();
  CalendarThemeData? _insertedTheme;

  /// The last [ColorScheme] a theme was derived from, and that theme.
  ColorScheme? _derivedScheme;
  CalendarThemeData? _derivedTheme;

  /// Whether the build puts a transparent [Material] above everything it
  /// builds.
  bool _insertsMaterial = false;

  /// The key of the header, the cards and the views, under the optional
  /// [Material] and [CalendarTheme], so a resolve that adds or drops one
  /// keeps the views' state.
  final GlobalKey _contentKey = GlobalKey();

  /// The range this state last asked a store to show, and that store.
  _Range? _askedRange;
  CalendarStore<T>? _askedStore;

  /// Whether a lifecycle change left the store's range to ask after the
  /// frame.
  bool _askPending = false;

  CalendarViewKind get _view {
    return _controller._view!;
  }

  DateTime get _day {
    return _controller._selectedDay!;
  }

  DateTime Function() get _clock {
    return widget.clock ?? DateTime.now;
  }

  @override
  void initState() {
    super.initState();
    _takeViews();
    _now = ValueNotifier<DateTime>(_clock());
    _today = ValueNotifier<DateTime>(_todayAt(_now.value));
    _lock = _lockAt(_now.value);
    final host = widget.controller;
    _ownsController = host == null;
    _bind(host ?? CalendarController(), shown: null);
    _scheduleMinute(_now.value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveTheme();
  }

  @override
  void reassemble() {
    _derivedScheme = null;
    _derivedTheme = null;
    super.reassemble();
    _resolveTheme();
  }

  @override
  void didUpdateWidget(CalendarView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clockChanged = widget.clock != oldWidget.clock;
    if (clockChanged) {
      _minuteTimer?.cancel();
      _now.value = _clock();
      _scheduleMinute(_now.value);
    }
    if (clockChanged ||
        widget.today != oldWidget.today ||
        widget.lockPast != oldWidget.lockPast ||
        widget.lockEarlierToday != oldWidget.lockEarlierToday) {
      // The build that follows shows them.
      _today.value = _todayAt(_now.value);
      _lock = _lockAt(_now.value);
    }
    final viewsChanged = !listEquals(widget.views, oldWidget.views);
    if (viewsChanged) {
      _takeViews();
    }
    if (widget.controller != oldWidget.controller) {
      _swapController();
    }
    if (viewsChanged && !_views.contains(_view)) {
      _noteLifecycle();
      _writeView(
        _ownsController
            ? calendarOpeningView(_views, _view)
            : _listedView(_view),
      );
    }
    final weekdaysChanged = widget.weekdays != oldWidget.weekdays;
    if (weekdaysChanged) {
      _noteLifecycle();
      final day = shownDayNear(_day, widget.weekdays);
      _controller._selectedDay = day;
      _grid = MonthGrid.of(day, weekdays: widget.weekdays);
    }
    if (viewsChanged || weekdaysChanged || widget.store != oldWidget.store) {
      _scheduleAsk();
    }
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    _noteLifecycle();
    _controller._detach(this);
    if (_ownsController) {
      _controller.dispose();
    }
    _collapseController.dispose();
    _pickerShown.dispose();
    // The views listening to these have unmounted by now: an element's
    // children unmount before it does.
    _today.dispose();
    _now.dispose();
    super.dispose();
  }

  /// Takes [CalendarView.views]: its error, and the list the state works
  /// from, the default list while the error stands, so the controller, the
  /// clock and the store's range stay those of the default list.
  void _takeViews() {
    final error = calendarViewsError(widget.views);
    _viewsError = error;
    if (error != null) {
      _views = CalendarViewKind.values;
    } else if (!listEquals(_views, widget.views)) {
      _views = List<CalendarViewKind>.unmodifiable(widget.views);
    }
  }

  /// Binds [controller] and applies its view and day, or where it names
  /// none, the view and day [shown] holds, and with nothing shown yet,
  /// the first listed view and today's nearest shown day. Writes the range
  /// this state last asked, which a controller swapped in reads at once,
  /// and asks the store for the range after the frame.
  void _bind(
    CalendarController controller, {
    required ({CalendarViewKind view, DateTime day})? shown,
  }) {
    if (!_ownsController) {
      controller._noteLifecycle();
    }
    controller._attach(this);
    _controller = controller;
    final named = controller._view;
    final CalendarViewKind view;
    if (named == null) {
      view = calendarOpeningView(_views, shown?.view);
    } else if (_ownsController) {
      view = calendarOpeningView(_views, named);
    } else {
      view = _listedView(named);
    }
    final day = shownDayNear(
      dateOnly(controller._selectedDay ?? shown?.day ?? _today.value),
      widget.weekdays,
    );
    controller._visibleRange = _askedRange;
    if (shown == null) {
      controller._view = view;
      controller._selectedDay = day;
      _grid = MonthGrid.of(day, weekdays: widget.weekdays);
      _resetForView(view);
    } else {
      controller._view = shown.view;
      controller._selectedDay = shown.day;
      _writeDay(day);
      if (view != shown.view) {
        _writeView(view);
      }
    }
    _scheduleAsk();
  }

  /// Takes [CalendarView.controller] in place of the one bound: a new
  /// host's, or, where the host's went, one of this state's own holding
  /// what the host's held. Disposes a controller of this state's own that
  /// it replaces.
  void _swapController() {
    final old = _controller;
    final shown = (view: _view, day: _day);
    _noteLifecycle();
    old._detach(this);
    final host = widget.controller;
    final next = host ?? CalendarController._copyOf(old);
    if (_ownsController) {
      old.dispose();
    }
    _ownsController = host == null;
    _bind(next, shown: shown);
  }

  /// Switches to an own copy of [shared], which another state's bind took,
  /// holding what it holds; after the frame, where this state is still
  /// mounted, reports the shared controller in a debug build and builds
  /// again on the copy.
  void _takeCopyOf(CalendarController shared) {
    final copy = CalendarController._copyOf(shared);
    copy._binding = this;
    _controller = copy;
    _ownsController = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      assert(() {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: FlutterError.fromParts(<DiagnosticsNode>[
              ErrorSummary(
                "A CalendarController was given to two "
                "CalendarViews.",
              ),
              ErrorDescription(
                "A controller serves one CalendarView at a time. It now "
                "serves the CalendarView built last, and the other one goes "
                "on with a copy of it that its host cannot reach.",
              ),
              ErrorHint("Give each CalendarView its own controller."),
            ]),
            library: "widgets_extended calendar",
          ),
        );
        return true;
      }());
      setState(() {});
    });
  }

  /// Notes, before a lifecycle change writes the host's controller, what
  /// its getters read, so it notifies once after the frame where they then
  /// read otherwise. A controller of this state's own has no listener
  /// outside it.
  void _noteLifecycle() {
    if (!_ownsController) {
      _controller._noteLifecycle();
    }
  }

  /// [view], where [_views] lists it; otherwise the first view [_views]
  /// lists, after a debug build reports a [FlutterError] naming both.
  /// Nothing is thrown, so a debug build goes on as a release build does.
  CalendarViewKind _listedView(CalendarViewKind view) {
    assert(() {
      if (!_views.contains(view)) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: FlutterError.fromParts(<DiagnosticsNode>[
              ErrorSummary(
                "A CalendarView's controller holds a view that "
                "its views do not list.",
              ),
              ErrorDescription(
                "The controller holds ${view.name}, and views lists "
                "${_views.map((kind) => kind.name).join(", ")}.",
              ),
              ErrorHint(
                "The CalendarView shows ${_views.first.name}, the first view "
                "views lists. Set the controller to a listed view before "
                "building the CalendarView with views that drop its view.",
              ),
            ]),
            library: "widgets_extended calendar",
          ),
        );
      }
      return true;
    }());
    return calendarOpeningView(_views, view);
  }

  DateTime _todayAt(DateTime now) {
    return dateOnly(widget.today ?? now);
  }

  HistoryLock _lockAt(DateTime now) {
    return HistoryLock.of(
      lockPast: widget.lockPast,
      lockEarlierToday: widget.lockEarlierToday,
      today: _todayAt(now),
      now: now,
    );
  }

  /// Reads the clock again at the start of the minute after [now], and
  /// from then on at the start of each. A new day or a new history lock
  /// builds this state again.
  void _scheduleMinute(DateTime now) {
    final intoMinute = Duration(
      seconds: now.second,
      milliseconds: now.millisecond,
      microseconds: now.microsecond,
    );
    _minuteTimer = Timer(const Duration(minutes: 1) - intoMinute, () {
      final next = _clock();
      _now.value = next;
      final today = _todayAt(next);
      final lock = _lockAt(next);
      if (today != _today.value || lock != _lock) {
        setState(() {
          _today.value = today;
          _lock = lock;
        });
      }
      _scheduleMinute(next);
    });
  }

  /// Resolves the theme the views draw with, and whether a [Material] goes
  /// above them. A [CalendarTheme] above wins; with none, the theme comes
  /// from the [ThemeData] where a [Theme] is above, and is the built-in
  /// one where none is. Sets the fold's and the picker's durations to the
  /// theme's.
  void _resolveTheme() {
    final hasTheme = context.findAncestorWidgetOfExactType<Theme>() != null;
    final hasMaterial =
        LookupBoundary.findAncestorWidgetOfExactType<Material>(context) != null;
    _insertsMaterial = hasTheme && !hasMaterial;
    final ambient = context.dependOnInheritedWidgetOfExactType<CalendarTheme>();
    if (ambient != null) {
      _theme = ambient.data;
      _insertedTheme = null;
    } else if (!hasTheme) {
      _theme = const CalendarThemeData();
      _insertedTheme = null;
    } else {
      final themeData = Theme.of(context);
      final extension = themeData.extension<CalendarThemeExtension>();
      if (extension != null) {
        _theme = extension.data;
      } else {
        final scheme = themeData.colorScheme;
        var derived = _derivedTheme;
        if (derived == null || scheme != _derivedScheme) {
          derived = CalendarThemeExtension.fromColorScheme(scheme).data;
          _derivedScheme = scheme;
          _derivedTheme = derived;
        }
        _theme = derived;
      }
      _insertedTheme = _theme;
    }
    _collapseController.duration = _theme.motionDuration;
    _pickerShown.duration = _theme.motionDuration;
  }

  /// The range of days the calendar asks the store to show: the month
  /// grid's in Agenda and Month, the selected day's week in Week, and the
  /// shown days of that week in Day, so a step within it reads nothing.
  _Range _rangeOf() {
    final weekdays = widget.weekdays;
    switch (_view) {
      case CalendarViewKind.agenda:
      case CalendarViewKind.month:
        return (first: _grid.firstDay, last: _grid.lastDay);
      case CalendarViewKind.week:
        final first = weekdays.weekStartOf(_day);
        return (first: first, last: addDays(first, DateTime.daysPerWeek - 1));
      case CalendarViewKind.day:
        final days = shownDaysOfWeek(_day, weekdays);
        return (first: days.first, last: days.last);
    }
  }

  /// Asks the store to show [_rangeOf], where the range moved or the
  /// store is new, writing the range to the controller first, so a store
  /// listener that moves the selection from inside the store's `show`
  /// writes the later range last.
  void _showRange() {
    final range = _rangeOf();
    final store = widget.store;
    if (range == _askedRange && identical(store, _askedStore)) {
      return;
    }
    _askedRange = range;
    _askedStore = store;
    _controller._visibleRange = range;
    store.show(range.first, range.last);
  }

  /// Asks the store for the range after the frame, when no build runs: a
  /// store notifies inside `show`, where a listener outside the element
  /// being built may not mark itself to build.
  void _scheduleAsk() {
    if (_askPending) {
      return;
    }
    _askPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _askPendingRange();
    });
  }

  /// The ask a lifecycle change left pending, which the controller's
  /// after-the-frame notify runs first, so its listeners read the range.
  /// A state unmounted meanwhile asks nothing.
  void _askPendingRange() {
    if (!_askPending || !mounted) {
      return;
    }
    _askPending = false;
    _showRange();
  }

  /// Runs an event's [change], asks the store for the range at once, and
  /// notifies the controller once where its view, selected day or range
  /// changed.
  void _event(VoidCallback change) {
    final controller = _controller;
    final before = controller._observed;
    setState(change);
    _showRange();
    if (_controller._observed != before) {
      _controller._notifyEvent();
    }
  }

  /// Selects [day], a shown day, leaving the card's browse and moving the
  /// month grid to its month.
  void _writeDay(DateTime day) {
    if (day == _day) {
      return;
    }
    _controller._selectedDay = day;
    _browsedDay = null;
    if (!_grid.contains(day)) {
      _grid = MonthGrid.of(day, weekdays: widget.weekdays);
    }
  }

  /// Shows [view], whose calendar card, in Agenda and Day, opens at once on
  /// the month and on the selected day's week, the month picker closed.
  void _writeView(CalendarViewKind view) {
    _controller._view = view;
    _resetForView(view);
  }

  void _resetForView(CalendarViewKind view) {
    _collapsed = view == CalendarViewKind.day;
    _browsedDay = null;
    _picksMonth = false;
    _collapseController.value = _collapsed ? 1.0 : 0.0;
    _pickerShown.value = 0.0;
  }

  void _select(DateTime day) {
    if (day == _day) {
      return;
    }
    _event(() {
      _writeDay(day);
    });
  }

  /// A host's set of the selected day.
  void _selectDay(DateTime day) {
    _select(shownDayNear(dateOnly(day), widget.weekdays));
  }

  /// A menu pick, a header's [CalendarHeaderDetails.onSelectView] or a
  /// host's set of the view: [view] must be listed. A pick of the view
  /// shown runs the view switch's resets too.
  void _selectView(CalendarViewKind view) {
    assert(
      _views.contains(view),
      "CalendarView lists ${_views.map((kind) => kind.name).join(", ")}, "
      "not ${view.name}.",
    );
    _event(() {
      _writeView(calendarOpeningView(_views, view));
    });
  }

  /// A host's goTo: closes the month picker; then where [day]'s nearest
  /// shown day is selected, brings the card or the strip a drag or a
  /// chevron moved back to it, and otherwise selects it.
  void _goTo(DateTime day) {
    if (_picksMonth) {
      _closeMonthPicker();
    }
    final target = shownDayNear(dateOnly(day), widget.weekdays);
    if (target != _day) {
      _select(target);
      return;
    }
    if (_browsedDay != null) {
      setState(() {
        _browsedDay = null;
        _stripRecalls++;
      });
    }
  }

  /// Month's tap on [day]: opens it in Day where [_views] lists Day, with
  /// one notify, and otherwise selects it.
  void _openDay(DateTime day) {
    if (!_views.contains(CalendarViewKind.day)) {
      _select(day);
      return;
    }
    _event(() {
      _writeDay(day);
      _writeView(CalendarViewKind.day);
    });
  }

  /// The first day of the month the calendar card shows.
  DateTime get _cardMonth {
    final day = _browsedDay ?? _day;
    return DateTime(day.year, day.month);
  }

  /// Moves the calendar card to the month of [day], selecting nothing.
  void _browse(DateTime day) {
    setState(() {
      _browsedDay = DateTime(day.year, day.month);
    });
  }

  void _browseStrip(DateTime day) {
    setState(() {
      _browsedDay = day;
    });
  }

  CalendarStepUnit get _stepUnit {
    if (_picksMonth) {
      return CalendarStepUnit.year;
    }
    switch (_view) {
      case CalendarViewKind.agenda:
        return _collapsed ? CalendarStepUnit.week : CalendarStepUnit.month;
      case CalendarViewKind.month:
        return CalendarStepUnit.month;
      case CalendarViewKind.week:
        return CalendarStepUnit.week;
      case CalendarViewKind.day:
        return CalendarStepUnit.day;
    }
  }

  /// Steps by [_stepUnit] over the shown weekdays: a day step skips the
  /// hidden ones, and a month step keeps the day of the month where it can
  /// and takes the nearest shown day of that month where it lands on a
  /// hidden one. A year step moves the month picker alone, and a month step
  /// in Agenda the calendar card alone.
  void _step(int direction) {
    final weekdays = widget.weekdays;
    switch (_stepUnit) {
      case CalendarStepUnit.year:
        setState(() {
          _pickerYear += direction;
        });
      case CalendarStepUnit.day:
        _select(nextShownDay(_day, direction, weekdays));
      case CalendarStepUnit.week:
        _select(addDays(_day, DateTime.daysPerWeek * direction));
      case CalendarStepUnit.month:
        if (_view == CalendarViewKind.agenda) {
          _browse(addMonths(_cardMonth, direction));
        } else {
          _select(shownDayNear(addMonths(_day, direction), weekdays));
        }
    }
  }

  void _stepBack() {
    _step(-1);
  }

  void _stepOn() {
    _step(1);
  }

  void _openMonthPicker() {
    setState(() {
      _picksMonth = true;
      _pickerYear = _day.year;
    });
    _pickerShown.animateTo(1.0, curve: _theme.motionCurve);
  }

  void _closeMonthPicker() {
    setState(() {
      _picksMonth = false;
    });
    _pickerShown.animateTo(0.0, curve: _theme.motionCurve);
  }

  /// Selects the day of [month] a month step from the selected day would.
  /// The month picker stays open, filling [month].
  void _pickMonth(DateTime month) {
    final months = (month.year - _day.year) * 12 + month.month - _day.month;
    _select(shownDayNear(addMonths(_day, months), widget.weekdays));
  }

  bool get _showsCalendarCard {
    return _view == CalendarViewKind.agenda || _view == CalendarViewKind.day;
  }

  void _setCollapsed(bool collapsed) {
    if (collapsed == _collapsed || !_showsCalendarCard) {
      return;
    }
    _settleCollapse(collapsed);
  }

  /// Folds or unfolds the calendar card from however far it has folded, a
  /// drag on the pull tab having moved it. Unfolding closes the month
  /// picker.
  void _settleCollapse(bool collapsed) {
    if (collapsed != _collapsed || (!collapsed && _picksMonth)) {
      setState(() {
        _collapsed = collapsed;
        if (!collapsed) {
          _picksMonth = false;
        }
      });
    }
    _collapseController.animateTo(
      _collapsed ? 1.0 : 0.0,
      curve: _theme.motionCurve,
    );
  }

  void _unfold() {
    _setCollapsed(false);
  }

  /// In Day, a drag that scrolls the grid's content up folds the month
  /// into its week, as a scroll of Agenda's list does.
  bool _handleGridScroll(ScrollNotification notification) {
    if (_view == CalendarViewKind.day &&
        notification.metrics.axis == Axis.vertical &&
        notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        (notification.scrollDelta ?? 0.0) > 0.0) {
      _setCollapsed(true);
    }
    return false;
  }

  /// A drag that moves the list's content up folds the month into its
  /// week; the list runs on both ways, so a downward drag on the folded
  /// strip unfolds it. Only drags count, so the scroll that brings a
  /// selected day to the list's top folds nothing. Overscroll counts as
  /// well.
  bool _handleListScroll(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    final double delta;
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      delta = notification.scrollDelta ?? 0.0;
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      delta = notification.overscroll;
    } else {
      return false;
    }
    if (delta > 0.0) {
      _setCollapsed(true);
    }
    return false;
  }

  /// A tap on the block or chip of [id]: reports the stored entry, and
  /// whether a form may change it, the choice between a form that edits
  /// and one that shows.
  void _openEntry(String id) {
    final onEntryTap = widget.onEntryTap;
    final entry = widget.store.storedEntry(id);
    if (onEntryTap == null || entry == null) {
      return;
    }
    onEntryTap(
      CalendarEntryTapDetails<T>(
        entry: entry,
        editable:
            widget.editable &&
            _lock.holdOf(entry.start, entry.end) != EntryHold.locked,
      ),
    );
  }

  Future<void> _createRange(CreateRange range) {
    final onCreateRange = widget.onCreateRange;
    if (onCreateRange == null) {
      return Future<void>.value();
    }
    return onCreateRange(range);
  }

  void _requestEdit(String id) {
    final onEditRequest = widget.onEditRequest;
    final entry = widget.store.storedEntry(id);
    if (onEditRequest != null && entry != null) {
      onEditRequest(entry);
    }
  }

  void _requestDelete(String id) {
    final onDeleteRequest = widget.onDeleteRequest;
    final entry = widget.store.storedEntry(id);
    if (onDeleteRequest != null && entry != null) {
      onDeleteRequest(entry);
    }
  }

  /// Month's long press on [day], selecting it first when it is a day of
  /// the shown month; a day of another month leaves the selection and the
  /// month as they are.
  void _createOn(DateTime day) {
    if (_grid.contains(day)) {
      _select(day);
    }
    _openCreateFlow(day);
  }

  /// Reports a create on [day] at its first free slot from the history
  /// lock's boundary, or where none after it is free, at the first slot
  /// from the first time the lock leaves free whose times the clock reads
  /// ([firstReadableSlot]); each in the boundary's occurrence where [day]'s
  /// clock repeats its time, so none starts before the boundary. Where the
  /// lock leaves no such slot in the hours, reports
  /// [CalendarView.onCreateRefused] instead.
  void _openCreateFlow(DateTime day) {
    final hours = _hours;
    final slot = widget.slotMinutes;
    final earliest = _lock.earliestStartOn(day, slotMinutes: slot);
    if (earliest > hours.end - slot) {
      widget.onCreateRefused?.call(day);
      return;
    }
    // A boundary on [day] after its start leaves earliest past 0.
    final from = earliest > 0 ? _lock.boundary : null;
    final free = widget.store.firstFreeRange(
      day,
      slotMinutes: slot,
      from: from,
    );
    if (from == null || !free.start.isBefore(from)) {
      _createRange(CreateRange(start: free.start, end: free.end));
      return;
    }
    final held = firstReadableSlot(
      day,
      earliest,
      hours.end,
      slot,
      occurrence: from,
    );
    if (held == null) {
      widget.onCreateRefused?.call(day);
      return;
    }
    _createRange(CreateRange(start: held.start, end: held.end));
  }

  CalendarHeaderDetails _headerDetails() {
    return CalendarHeaderDetails(
      view: _view,
      views: _views,
      day: _browsedDay ?? _day,
      pickerYear: _picksMonth ? _pickerYear : null,
      stepUnit: _stepUnit,
      onPrevious: _stepBack,
      onNext: _stepOn,
      onSelectView: _selectView,
      onOpenPicker: _openMonthPicker,
      onClosePicker: _closeMonthPicker,
    );
  }

  /// The header in its place, built in a [Builder] there, so a throw in
  /// [CalendarView.headerBuilder] builds an error widget in the header's
  /// place alone; null where [CalendarView.showsHeader] is false.
  Widget? _buildHeader() {
    if (!widget.showsHeader) {
      return null;
    }
    final details = _headerDetails();
    final builder = widget.headerBuilder ?? defaultCalendarHeaderBuilder;
    return Builder(
      builder: (context) {
        return builder(context, details);
      },
    );
  }

  /// The month picker, on [_pickerYear], filling the selected day's month
  /// and ringing today's.
  Widget _buildMonthPicker() {
    final today = _today.value;
    return MonthPicker(
      key: const ValueKey<String>("month-picker"),
      year: _pickerYear,
      selectedMonth: DateTime(_day.year, _day.month),
      currentMonth: DateTime(today.year, today.month),
      onSelectMonth: _pickMonth,
      onBrowse: (year) {
        setState(() {
          _pickerYear = year;
        });
      },
    );
  }

  Widget _buildCard(Widget? header) {
    return CalendarCard<T>(
      store: widget.store,
      month: _cardMonth,
      selectedDay: _day,
      today: _today.value,
      weekdays: widget.weekdays,
      stripRecalls: _stripRecalls,
      collapse: _collapseController,
      collapsed: _collapsed,
      pickerShown: _pickerShown,
      picksMonth: _picksMonth,
      header: header,
      buildPicker: _buildMonthPicker,
      onSelectDay: _select,
      onBrowseMonth: _browse,
      onBrowseStrip: _browseStrip,
      onSettle: _settleCollapse,
      onUnfold: _unfold,
    );
  }

  Widget _buildHeaderCard(Widget? header) {
    if (header == null) {
      return const SizedBox.shrink();
    }
    return CalendarHeaderCard(
      header: header,
      pickerShown: _pickerShown,
      picksMonth: _picksMonth,
      buildPicker: _buildMonthPicker,
    );
  }

  /// The calendar card over the day list.
  Widget _buildAgenda(Widget? header) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 0.0),
          child: _buildCard(header),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleListScroll,
            child: DayList<T>(
              key: const ValueKey<String>("day-list"),
              store: widget.store,
              weekdays: widget.weekdays,
              format: widget.hourLabelFormat,
              hours: _hours,
              slotMinutes: widget.slotMinutes,
              editable: widget.editable,
              lock: _lock,
              selectedDay: _day,
              today: _today.value,
              now: _now,
              onTopDay: _select,
              onCreateRange: _createRange,
              onEdit: _requestEdit,
              onDelete: _requestDelete,
              cardBuilder: widget.cardBuilder,
              cardExtentOf: widget.cardExtentOf,
              addButtonBuilder: widget.addButtonBuilder,
              loadingBuilder: widget.loadingBuilder,
              failureBuilder: widget.failureBuilder,
            ),
          ),
        ),
      ],
    );
  }

  /// The timed grid of the selected day's week in Week, under the header
  /// card, and of the selected day in Day, under the calendar card. The
  /// grid builds in a builder on the controller, which a pinch's zoom
  /// rebuilds alone.
  Widget _buildTimed(Widget? header) {
    final view = _view;
    final range = _rangeOf();
    final week = view == CalendarViewKind.week;
    final firstDay = week ? range.first : _day;
    final dayCount = week ? DateTime.daysPerWeek : 1;
    final controller = _controller;
    final key = ValueKey<(CalendarViewKind, bool)>((
      view,
      dayCount > 1 && widget.weekdays.columns.length > 1,
    ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (week)
          _buildHeaderCard(header)
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
            child: _buildCard(header),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleGridScroll,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, child) {
                return TimedGrid<T>(
                  // Each view builds its own grid, which opens scrolled to
                  // its opening time, and so does a week of one shown
                  // weekday, as a grid keeps one day column or more than
                  // one.
                  key: key,
                  store: widget.store,
                  firstDay: firstDay,
                  dayCount: dayCount,
                  selectedDay: _day,
                  today: _today.value,
                  now: _now,
                  onSelectDay: _select,
                  onOpenEntry: _openEntry,
                  onCreate: _createRange,
                  onZoom: (minSlotHeight, minDayWidth) {
                    controller.setZoom(
                      minSlotHeight: minSlotHeight,
                      minDayWidth: minDayWidth,
                    );
                  },
                  editable: widget.editable,
                  lockPast: widget.lockPast,
                  lockEarlierToday: widget.lockEarlierToday,
                  weekdays: widget.weekdays,
                  hours: _hours,
                  slotMinutes: widget.slotMinutes,
                  hourLabelFormat: widget.hourLabelFormat,
                  minDayWidth: controller.minDayWidth,
                  minSlotHeight: controller.minSlotHeight,
                  maxDayCount: widget.maxDayCount,
                  storeRange: range,
                  // The week strip names Day's one day.
                  showsDayHeader: week,
                  blockBuilder: widget.blockBuilder,
                  chipBuilder: widget.chipBuilder,
                  loadingBuilder: widget.loadingBuilder,
                  failureBuilder: widget.failureBuilder,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// The header card, and under it, on the surface colour across the full
  /// width and down to the bottom, the weekday letters and the month
  /// board, which builds in a builder on the controller, which a pinch's
  /// zoom rebuilds alone.
  Widget _buildMonth(Widget? header) {
    final controller = _controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeaderCard(header),
        Expanded(
          child: ColoredBox(
            color: _theme.surface,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, child) {
                return MonthBoard<T>(
                  key: const ValueKey<String>("month-board"),
                  store: widget.store,
                  grid: _grid,
                  layout: widget.monthLayout,
                  minDayWidth: controller.minDayWidth,
                  weekScale: controller.monthWeekScale,
                  hours: _hours,
                  hourLabelFormat: widget.hourLabelFormat,
                  selectedDay: _day,
                  today: _today,
                  onSelectDay: _select,
                  onOpenDay: _openDay,
                  onCreateOnDay: widget.editable ? _createOn : null,
                  onOpenEntry: _openEntry,
                  onZoom: (weekScale, minDayWidth) {
                    controller.setZoom(
                      monthWeekScale: weekScale,
                      minDayWidth: minDayWidth,
                    );
                  },
                  chipBuilder: widget.chipBuilder,
                  loadingBuilder: widget.loadingBuilder,
                  failureBuilder: widget.failureBuilder,
                  entryKindOf: widget.entryKindOf,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _viewsError;
    if (error != null) {
      throw error;
    }
    final slotError = _slotMinutesError;
    if (slotError != null) {
      throw slotError;
    }
    assert(
      widget.store.hours == widget.hours,
      "A CalendarView's hours, ${widget.hours}, must be its store's, "
      "${widget.store.hours}: set the store's hours with them.",
    );
    assert(
      widget.hours.isOnSlotsOf(widget.slotMinutes),
      "A CalendarView's hours, ${widget.hours}, must start and end on the "
      "grid of its ${widget.slotMinutes}-minute slots.",
    );
    final header = _buildHeader();
    final Widget view;
    switch (_view) {
      case CalendarViewKind.agenda:
        view = _buildAgenda(header);
      case CalendarViewKind.day:
      case CalendarViewKind.week:
        view = _buildTimed(header);
      case CalendarViewKind.month:
        view = _buildMonth(header);
    }
    Widget content = KeyedSubtree(key: _contentKey, child: view);
    final inserted = _insertedTheme;
    if (inserted != null) {
      content = CalendarTheme(data: inserted, child: content);
    }
    if (_insertsMaterial) {
      content = Material(type: MaterialType.transparency, child: content);
    }
    return content;
  }
}
