/// A workspace calendar on the board module, over a calendar API, in four
/// views: Agenda, a month grid over a list of the days, one after another,
/// each day's items beside their times and lengths, the month folding into
/// the selected day's week as the list is scrolled;
/// Month, the month's weeks with each item as a chip on the days it
/// covers; and Week and Day, timed grids of the selected day's week and of
/// that day alone, where in edit mode items are moved, resized and
/// created.
///
/// Day shows Agenda's calendar card folded: a strip of a week's worth of
/// days, opening on the selected day's week, whose days a tap selects and
/// which a drag slides day by day, across weeks and months, without
/// selecting, the header naming the month of the day at its middle; the
/// calendar reads a selected day's whole week, and the strip the weeks of
/// the days it shows, so a step within the week, or a tap on a day the
/// strip shows, reads nothing. The card's pull tab unfolds the month, and
/// a drag up Day's grid folds it again. Day's grid has no day header, the
/// strip naming its day, and its blocks show their times and summaries.
///
/// Agenda's month grid is a [Board] with no items, under the weekdays'
/// three-letter names. Each day is a cell, its number on a circle as the strip
/// shows it, with a badge when it has items; a tap selects it through the
/// board's cell selection, and the arrow keys move that selection once the
/// board has focus. The list under it ([DayList]) runs both ways from the
/// selected day: a selected day scrolls to its top, animating, and a drag
/// or a fling of the list selects each day it brings to the top. Each
/// day's header sticks at the top while its items scroll under it. Each
/// item's card sits right of its start time, over a chip of its length. An
/// item wholly outside the calendar's hours shows only in a count on a
/// soft yellow banner, above the day's cards for those before the hours
/// and below them for those after, as Week's and Day's rows outside the
/// hours count them. A red line marks the current time over the rows of
/// the clock's day, the time on a pill at its start, crossing the card of
/// an item running then as far as the item has run. In edit mode the list
/// marks each gap in the hours that no item covers with a dashed row, a
/// day without items with one across the hours, each with a button that
/// creates an item there, and each card has a menu of Edit and Delete; out
/// of it a day without items shows its header alone. A drag of the list
/// folds the month, and the pull tab under the card folds or unfolds it as far
/// as a drag on it moves, a tap on it switching; a downward drag on the
/// folded strip unfolds it too. The board always holds
/// the whole month of the selected day; while it folds, it is clipped to
/// a shrinking window shifted so the selected week shows, and once folded,
/// Day's strip takes the window's place, opening on that week. Selecting a
/// day in another month, by a tap on a muted day, the chevrons or a key,
/// switches the board to that month.
///
/// Month's grid is a [MonthBoard], whose weeks fill the screen. Under the
/// settings' Fit to screen, the layout the calendar starts on, they keep
/// their share, and a busy day shows the chips that fit and "+N more" on a
/// soft yellow banner; under Show all items they grow with their chips.
/// Days at least 100 px wide in weeks at least 136 px tall show cards,
/// which add an item's times to its title. A tap on a chip opens its item,
/// and a tap anywhere else on a day opens that day in Day. In edit mode a
/// long press on a day creates an item there at the day's first free slot,
/// selecting the day when it is in the month; out of it a long press opens
/// the day as a tap does. Its keys and chevrons move the selected
/// day as Agenda's do.
///
/// The calendar reads the range it shows through a [CachingCalendarStore]
/// over a [CalendarApiSource], which caches the days it has read and
/// writes one change per item at a time.
///
/// The app bar's chevron opens a bar under it, and closes it again, the
/// bar sliding down from under the app bar, or back up, over
/// [harborMotionDuration]: the calendar bar ([CalendarBar]), holding
/// Today, the edit mode switch, the weekday a week starts on, which every
/// view's weeks and columns follow, and which weekdays show, the hours the
/// calendar shows and schedules in, and whether Week and Day label them
/// AM/PM. The calendar opens out of edit mode unless it is given it, and
/// with the bar closed. Out of edit mode the calendar is read-only, so
/// nothing is moved, resized or created, and a tap on an item opens its
/// form read-only. The settings sheet, which opens from the app bar's More
/// menu, chooses how Month fits its weeks, the least width of a day in
/// Week, Day and Month, and the least height of the timed grids' slots,
/// whose ratio to its default scales Month's weeks past their share of the
/// screen. A pinch of two fingers on Week's, Day's or Month's grid sets
/// those two sizes too, zooming around the point between the fingers: up
/// and down the slot height, or Month's week scale, and across, where the
/// grid has more than one day, the day width. A selected day is always on
/// a shown weekday. Every view rings today's number in a lighter blue than
/// the primary.
///
/// The sheet also chooses the history lock, which in edit mode keeps the
/// past as it is: no item before today, or with its second switch before
/// now, is moved, resized, edited or deleted, nor does an item move,
/// resize or get created there, and an item in progress changes only its
/// end. A create with no time left after the lock on its day says so.
///
/// Today, in the calendar bar, selects today, or the shown day nearest it,
/// in every view, and slides a strip a drag moved away back to it. A tap on
/// the header's month opens the month picker, a [MonthPicker], until the
/// title is tapped again: in Agenda's and Day's card it fades in over the
/// days as they fade out, the card's height moving from theirs to its, and
/// back as it closes, the days showing folded or unfolded as they were; in
/// Week and Month it fades in under the header as the header's card grows
/// to hold it, and back as it closes. While it shows, the title names its
/// year, and the chevrons or a swipe across it step a year; a month picked
/// selects its day of the selected day's day of the month, as a month step
/// does, and the picker stays open, filling that month.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'workspace_calendar/calendar_api.dart';
import 'workspace_calendar/calendar_api_source.dart';
import 'workspace_calendar/calendar_bar.dart';
import 'workspace_calendar/calendar_item.dart';
import 'workspace_calendar/calendar_schema.dart';
import 'workspace_calendar/calendar_settings.dart';
import 'workspace_calendar/day_cell.dart';
import 'workspace_calendar/day_list.dart';
import 'workspace_calendar/harbor_theme.dart';
import 'workspace_calendar/history_lock.dart';
import 'workspace_calendar/item_form.dart';
import 'workspace_calendar/mock_calendar_api.dart';
import 'workspace_calendar/month_board.dart';
import 'workspace_calendar/month_picker.dart';
import 'workspace_calendar/settings_sheet.dart';
import 'workspace_calendar/timed_grid.dart';
import 'workspace_calendar/week_strip.dart';

enum _CalendarMode {
  agenda("Agenda"),
  day("Day"),
  week("Week"),
  month("Month");

  const _CalendarMode(this.label);

  final String label;
}

/// The entries of the app bar's More menu.
enum _MoreAction { settings }

/// What the chevrons step by, which their tooltips name.
enum _StepUnit {
  day("day"),
  week("week"),
  month("month"),
  year("year");

  const _StepUnit(this.label);

  final String label;
}

/// The calendar under its own Harbor theme, whatever the host's theme.
class WorkspaceCalendarExample extends StatelessWidget {
  const WorkspaceCalendarExample({
    super.key,
    this.today,
    this.api,
    this.clock,
    this.editing = false,
    this.calendarTheme = harborCalendarTheme,
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
  });

  final DateTime? today;
  final CalendarApi? api;
  final DateTime Function() clock;
  final bool editing;

  @override
  State<_WorkspaceCalendar> createState() {
    return _WorkspaceCalendarState();
  }
}

class _WorkspaceCalendarState extends State<_WorkspaceCalendar>
    with TickerProviderStateMixin {
  /// The height of a row of the month grid: a strip cell's
  /// ([stripCellHeight]) at the text size [didChangeDependencies] reads,
  /// so a week folds into the strip with the weekday names its cells grow
  /// fitting.
  double _rowHeight = 48.0;

  /// The clock's time, read again at the start of each minute.
  late final ValueNotifier<DateTime> _now = ValueNotifier<DateTime>(
    widget.clock(),
  );

  /// The day marked as today. The month board's cells listen to it,
  /// because its cell builder re-runs only when an axis or a cell's
  /// selection changes.
  late final ValueNotifier<DateTime> _today = ValueNotifier<DateTime>(
    _todayAt(_now.value),
  );

  /// Fires at the start of the next minute, to read the clock again.
  Timer? _minuteTimer;

  /// The history lock the settings choose, at the minute [_now] holds.
  late HistoryLock _lock = _lockAt(_now.value);

  late final CachingCalendarStore<ItemPayload> _store;

  late DateTime _selected = _today.value;

  /// The day at the middle of the strip since it was last moved other than
  /// to follow the selection, whose month the header names; null until it
  /// is.
  DateTime? _stripDay;

  /// The month of [_selected], which is the lattice the board shows.
  late MonthGrid _grid = MonthGrid.of(_selected, weekdays: _settings.weekdays);

  /// The view picked from the menu.
  _CalendarMode _mode = _CalendarMode.agenda;

  /// Whether the calendar card shows the selected day's week rather than
  /// its month. Only meaningful in Agenda and Day, which start unfolded
  /// and folded.
  bool _collapsed = false;

  /// Counts the calls that bring the strip back to the selected day, which
  /// [WeekStrip.recalls] passes on.
  int _stripRecalls = 0;

  /// Whether the month picker shows.
  bool _picksMonth = false;

  /// The year the month picker shows, which the title names while it
  /// shows.
  int _pickerYear = 0;

  /// How far the month picker has come in, 0 for out and 1 for in: in
  /// place of Agenda's and Day's days in the card, and under the header in
  /// Week and Month. Animated on [harborMotionCurve].
  late final AnimationController _pickerShown = AnimationController(
    vsync: this,
    duration: harborMotionDuration,
  );

  /// What the calendar bar and the settings sheet last chose, and before
  /// they choose, the defaults with the edit mode the calendar was given.
  late CalendarSettings _settings = CalendarSettings(editing: widget.editing);

  /// The width the column axis was last fitted to.
  double _columnsWidth = 0.0;

  /// Whether the calendar bar is open, or opening.
  bool _barOpen = false;

  /// How far the calendar bar shows, 0 closed and 1 open, animated on
  /// [harborMotionCurve] by [_toggleBar].
  late final AnimationController _barController = AnimationController(
    vsync: this,
    duration: harborMotionDuration,
  );

  /// How far the calendar card has folded, 0 for the month and 1 for its
  /// week: linear, so a drag on the pull tab moves it with the finger, and
  /// animated on [harborMotionCurve] by [_animateCollapse].
  late final AnimationController _collapseController = AnimationController(
    vsync: this,
    duration: harborMotionDuration,
  );

  late final BoardController<Object, Object> _board;

  /// Held in a field because `Board` replaces its delegate, and so
  /// rebuilds every cell, whenever the builder it gets is not identical
  /// to the previous one.
  late final BoardCellBuilder<Object, Object> _cellBuilder = _buildDay;

  @override
  void initState() {
    super.initState();
    _store = CachingCalendarStore<ItemPayload>(
      dataSource: CalendarApiSource(
        widget.api ?? MockCalendarApi.seeded(_today.value),
      ),
      onWriteFailed: _handleWriteFailed,
    );
    // The month board holds no items, so its key and payload types are
    // unused.
    _board = BoardController<Object, Object>(
      vsync: this,
      rows: _rowsFor(_grid),
      // Replaced by the first layout, which knows the width.
      columns: BoardAxisConfig(
        axis: UniformAxis(_grid.columnCount, _rowHeight),
      ),
      keyOf: (item) {
        return item;
      },
    );
    _board.setSelection(_selectionOf(_selected));
    _showRange();
    _scheduleMinute(_now.value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final height = stripCellHeight(context);
    if (height != _rowHeight) {
      _rowHeight = height;
      _board.rows = _rowsFor(_grid);
    }
  }

  @override
  void didUpdateWidget(_WorkspaceCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clockChanged = widget.clock != oldWidget.clock;
    if (clockChanged) {
      _minuteTimer?.cancel();
      _now.value = widget.clock();
      _scheduleMinute(_now.value);
    }
    if (clockChanged || widget.today != oldWidget.today) {
      // The build that follows shows it.
      _today.value = _todayAt(_now.value);
      _lock = _lockAt(_now.value);
    }
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    _store.dispose();
    _board.dispose();
    _collapseController.dispose();
    _pickerShown.dispose();
    _barController.dispose();
    // The cells and the timed grid listening to these have unmounted by
    // now: an element's children unmount before it does.
    _today.dispose();
    _now.dispose();
    super.dispose();
  }

  /// The day marked as today when the clock reads [now].
  DateTime _todayAt(DateTime now) {
    return dateOnly(widget.today ?? now);
  }

  /// The history lock the settings choose when the clock reads [now].
  HistoryLock _lockAt(DateTime now) {
    return HistoryLock.of(_settings, today: _todayAt(now), now: now);
  }

  /// The history lock as it holds when called, which a form reads at Save.
  HistoryLock _currentLock() {
    return _lock;
  }

  /// Reads the clock again at the start of the minute after [now], and
  /// from then on at the start of each. A new day rebuilds this state for
  /// the day title and the timed grid, and so does a new history lock,
  /// which a lock to now has each minute.
  void _scheduleMinute(DateTime now) {
    final intoMinute = Duration(
      seconds: now.second,
      milliseconds: now.millisecond,
      microseconds: now.microsecond,
    );
    _minuteTimer = Timer(const Duration(minutes: 1) - intoMinute, () {
      final next = widget.clock();
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

  BoardAxisConfig _rowsFor(MonthGrid grid) {
    return BoardAxisConfig(axis: UniformAxis(grid.weekCount, _rowHeight));
  }

  BoardSelection _selectionOf(DateTime day) {
    final cell = _grid.cellOf(day);
    return BoardSelection(anchor: cell, focus: cell);
  }

  /// The days the timed grid shows: the selected day's week, from the
  /// settings' first weekday, in the week mode, the selected day alone in
  /// the day mode, and null in Agenda and Month.
  ({DateTime first, int count})? get _timedDays {
    switch (_mode) {
      case _CalendarMode.agenda:
      case _CalendarMode.month:
        return null;
      case _CalendarMode.week:
        return (first: _settings.weekdays.weekStartOf(_selected), count: 7);
      case _CalendarMode.day:
        return (first: _selected, count: 1);
    }
  }

  /// Shows the month grid's days in Agenda and Month, the timed grid's week
  /// in the week mode, and in the day mode the shown days of the selected
  /// day's week, so a step within that week reads nothing. Reads whatever
  /// of them is not read yet.
  void _showRange() {
    switch (_mode) {
      case _CalendarMode.agenda:
      case _CalendarMode.month:
        _store.show(_grid.firstDay, _grid.lastDay);
      case _CalendarMode.week:
        final days = _timedDays!;
        _store.show(days.first, addDays(days.first, days.count - 1));
      case _CalendarMode.day:
        final days = shownDaysOfWeek(_selected, _settings.weekdays);
        _store.show(days.first, days.last);
    }
  }

  /// The month grid's columns, equal, across [width]. Called from the
  /// grid's layout callback, so the first frame already lays the board out
  /// at its width, and when the shown weekdays change.
  void _fitColumns(double width) {
    final count = _grid.columnCount;
    if (width == _columnsWidth && count == _board.columns.axis.trackCount) {
      return;
    }
    _columnsWidth = width;
    _board.columns = BoardAxisConfig(axis: UniformAxis(count, width / count));
  }

  void _select(DateTime day) {
    if (day == _selected) {
      return;
    }
    final monthChanged = !_grid.contains(day);
    setState(() {
      _selected = day;
      _stripDay = null;
      if (monthChanged) {
        _grid = MonthGrid.of(day, weekdays: _settings.weekdays);
      }
    });
    if (monthChanged) {
      // A new axis instance refreshes every cell, which is what re-dates
      // them, even when the new month has as many weeks as the old one.
      _board.rows = _rowsFor(_grid);
    }
    // Reports back through [_handleBoardSelection], which finds the day
    // already selected.
    _board.setSelection(_selectionOf(day));
    _showRange();
  }

  void _handleBoardSelection(BoardSelection selection) {
    final focus = selection.focus;
    if (focus == null) {
      return;
    }
    _select(_grid.dateAt(focus.row, focus.col));
  }

  /// A year while the month picker shows; otherwise a day in the day
  /// mode, a week in the week mode and the folded month, a month
  /// otherwise.
  _StepUnit get _stepUnit {
    if (_picksMonth) {
      return _StepUnit.year;
    }
    switch (_mode) {
      case _CalendarMode.agenda:
        return _collapsed ? _StepUnit.week : _StepUnit.month;
      case _CalendarMode.month:
        return _StepUnit.month;
      case _CalendarMode.week:
        return _StepUnit.week;
      case _CalendarMode.day:
        return _StepUnit.day;
    }
  }

  /// Steps by [_stepUnit] over the shown weekdays: a day step skips the
  /// hidden ones, and a month step keeps the day of the month where it can
  /// and takes the nearest shown day of that month where it lands on a
  /// hidden one. A year step moves the month picker alone.
  void _step(int direction) {
    final weekdays = _settings.weekdays;
    switch (_stepUnit) {
      case _StepUnit.year:
        setState(() {
          _pickerYear += direction;
        });
      case _StepUnit.day:
        _select(nextShownDay(_selected, direction, weekdays));
      case _StepUnit.week:
        _select(addDays(_selected, 7 * direction));
      case _StepUnit.month:
        _select(shownDayNear(addMonths(_selected, direction), weekdays));
    }
  }

  /// Switches to [mode], whose calendar card, in Agenda and Day, opens
  /// at once on the month and on the selected day's week.
  void _setMode(_CalendarMode mode) {
    setState(() {
      _mode = mode;
      _collapsed = mode == _CalendarMode.day;
      _stripDay = null;
      _picksMonth = false;
    });
    _collapseController.value = _collapsed ? 1.0 : 0.0;
    _pickerShown.value = 0.0;
    _showRange();
  }

  /// The day mode, on [day].
  void _openDayMode(DateTime day) {
    _select(day);
    _setMode(_CalendarMode.day);
  }

  /// The create flow for [day] at its first free slot, selecting [day]
  /// first when it is a day of the shown month; a day of another month
  /// leaves the selection and the month as they are.
  void _createOn(DateTime day) {
    if (_grid.contains(day)) {
      _select(day);
    }
    _openCreateFlow(day);
  }

  /// The create flow on [day] at its first free slot from the first time
  /// the history lock leaves free on [day], or the slot at that time where
  /// none after it is free; where the lock leaves no time in the hours, a
  /// message instead.
  void _openCreateFlow(DateTime day) {
    final hours = _settings.hours;
    final earliest = _lock.earliestStartOn(day);
    if (earliest > hours.end - minutesPerSlot) {
      _showMessage("Past times are locked.");
      return;
    }
    final free = _store.firstFreeRange(
      day,
      from: earliest == 0 ? null : earliest,
    );
    final start = math.max(free.start, earliest);
    showCreateFlow(
      context,
      store: _store,
      range: CreateRange(
        day: day,
        startMinute: start,
        endMinute: start + minutesPerSlot,
        dayCount: 1,
      ),
      lock: _currentLock,
    );
  }

  /// Folds or unfolds Agenda's month. The month that unfolds is the
  /// selected day's, so the header names it again.
  void _setCollapsed(bool collapsed) {
    if (collapsed == _collapsed || !_showsCalendarCard) {
      return;
    }
    _settleCollapse(collapsed);
  }

  /// Whether the mode shows the calendar card that folds: Agenda and Day.
  bool get _showsCalendarCard {
    return _mode == _CalendarMode.agenda || _mode == _CalendarMode.day;
  }

  /// Folds or unfolds the calendar card from however far it has folded,
  /// a drag on the pull tab having moved it, and names the selected day's
  /// month again once it changes. Unfolding closes the month picker.
  void _settleCollapse(bool collapsed) {
    if (collapsed != _collapsed || (!collapsed && _picksMonth)) {
      setState(() {
        _collapsed = collapsed;
        _stripDay = null;
        if (!collapsed) {
          _picksMonth = false;
        }
      });
    }
    _animateCollapse();
  }

  void _animateCollapse() {
    _collapseController.animateTo(
      _collapsed ? 1.0 : 0.0,
      curve: harborMotionCurve,
    );
  }

  /// The height the calendar card loses as the month folds into its week:
  /// every week but the selected one, and the weekday header.
  double get _foldDistance {
    return (_grid.weekCount - 1) * _rowHeight + weekdayHeaderHeight;
  }

  /// The speed, in logical pixels per second, past which a release of the
  /// pull tab folds or unfolds the way it moves, wherever it is.
  static const double _foldFlingVelocity = 365.0;

  /// A drag on the pull tab folds the card as far as the finger moves.
  void _dragFold(DragUpdateDetails details) {
    _collapseController.value -= details.primaryDelta! / _foldDistance;
  }

  /// A release of the pull tab folds or unfolds the card the way a fast
  /// one moves, and otherwise to whichever it is nearer.
  void _endFoldDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    _settleCollapse(
      velocity.abs() >= _foldFlingVelocity
          ? velocity < 0.0
          : _collapseController.value >= 0.5,
    );
  }

  /// In Day, a drag that scrolls the board's content up folds the month
  /// into its week, as a scroll of Agenda's list does.
  bool _handleBoardScroll(ScrollNotification notification) {
    if (_mode == _CalendarMode.day &&
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
  /// strip unfolds it ([_buildGrid]). Only drags count, so the scroll that
  /// brings a selected day to the list's top folds nothing. Overscroll
  /// counts as well.
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

  /// The distance down a drag on the folded strip goes before it unfolds
  /// the month.
  static const double _unfoldDistance = 16.0;

  /// How far down the drag on the folded strip has gone.
  double _unfoldDrag = 0.0;

  /// Selects [day], a shown day, which brings Agenda's list and Day's
  /// strip to it; when it is selected already, the strip slides back to it
  /// from where a drag moved it.
  void _goTo(DateTime day) {
    if (day == _selected) {
      if (_stripDay != null) {
        setState(() {
          _stripDay = null;
          _stripRecalls++;
        });
      }
      return;
    }
    _select(day);
  }

  /// Closes the month picker, then selects today, or the shown day nearest
  /// it.
  void _goToToday() {
    if (_picksMonth) {
      _closeMonthPicker();
    }
    _goTo(shownDayNear(_today.value, _settings.weekdays));
  }

  /// Opens the month picker on the selected day's year, in Agenda's and
  /// Day's card in place of the days, folded or not.
  void _openMonthPicker() {
    setState(() {
      _picksMonth = true;
      _pickerYear = _selected.year;
    });
    _pickerShown.animateTo(1.0, curve: harborMotionCurve);
  }

  /// Closes the month picker, Agenda's or Day's card showing its days,
  /// folded or unfolded as it did before.
  void _closeMonthPicker() {
    setState(() {
      _picksMonth = false;
    });
    _pickerShown.animateTo(0.0, curve: harborMotionCurve);
  }

  /// Selects the day of [month] a month step from the selected day would.
  /// The month picker stays open, filling [month].
  void _pickMonth(DateTime month) {
    final months =
        (month.year - _selected.year) * 12 + month.month - _selected.month;
    _select(shownDayNear(addMonths(_selected, months), _settings.weekdays));
  }

  /// The month picker, on [_pickerYear], filling the selected day's month
  /// and ringing today's.
  Widget _buildMonthPicker() {
    return MonthPicker(
      key: const ValueKey<String>("month-picker"),
      year: _pickerYear,
      selectedMonth: DateTime(_selected.year, _selected.month),
      currentMonth: DateTime(_today.value.year, _today.value.month),
      onSelectMonth: _pickMonth,
      onBrowse: (year) {
        setState(() {
          _pickerYear = year;
        });
      },
    );
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
      onChanged: _applySettings,
    );
  }

  /// New weekdays, or a new first weekday, move a selected day they hide
  /// to the nearest shown one and rebuild the month board's lattice, whose
  /// cells they change.
  void _applySettings(CalendarSettings settings) {
    final weekdaysChanged = settings.weekdays != _settings.weekdays;
    setState(() {
      _settings = settings;
      _lock = _lockAt(_now.value);
      if (weekdaysChanged) {
        _selected = shownDayNear(_selected, settings.weekdays);
        _grid = MonthGrid.of(_selected, weekdays: settings.weekdays);
      }
    });
    _store.hours = settings.hours;
    if (weekdaysChanged) {
      _board.rows = _rowsFor(_grid);
      _fitColumns(_columnsWidth);
      _board.setSelection(_selectionOf(_selected));
      _showRange();
    }
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

  /// The form of the item [id]: editable in edit mode, unless the history
  /// lock holds the item [ItemHold.locked], and read-only otherwise.
  void _openItem(String id) {
    final item = _store.storedEntry(id);
    if (_settings.editing &&
        item != null &&
        _lock.holdOf(item.time) != ItemHold.locked) {
      showEditForm(context, store: _store, id: id, lock: _currentLock);
    } else {
      showItemDetails(context, store: _store, id: id);
    }
  }

  Future<void> _deleteFromCard(String id) async {
    final confirmed = await confirmDelete(context);
    if (confirmed && mounted) {
      _store.requestDelete(id);
    }
  }

  Widget _buildDay(BuildContext context, BoardCellView<Object, Object> cell) {
    // A new grid reaches the board in the build that moves the selection,
    // so the cell of a row or column the grid no longer has rebuilds once
    // for it before the board's next layout drops that cell.
    if (cell.row >= _grid.weekCount || cell.col >= _grid.columnCount) {
      return const SizedBox.shrink();
    }
    final day = _grid.dateAt(cell.row, cell.col);
    final inMonth = _grid.contains(day);
    final isSelected = cell.isSelected;
    return DayMarkerListener(
      store: _store,
      day: day,
      builder: (context, hasItems) {
        return ValueListenableBuilder<DateTime>(
          valueListenable: _today,
          builder: (context, today, child) {
            return DayCell(
              key: dayCellKey(day),
              day: day,
              inMonth: inMonth,
              isSelected: isSelected,
              isToday: day == today,
              hasItems: hasItems,
              collapse: _collapseController,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final month = _mode == _CalendarMode.month;
    return Scaffold(
      // A form's keyboard leaves the month board's height, and so its
      // weeks, as they are; the form's dialog pads itself by the keyboard.
      resizeToAvoidBottomInset: !month,
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
              child: const Icon(Icons.keyboard_arrow_down),
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
          Expanded(child: _buildCalendarView()),
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

  _CalendarHeader _buildCalendarHeader() {
    return _CalendarHeader(
      day: _stripDay ?? _selected,
      mode: _mode,
      stepUnit: _stepUnit,
      onPrevious: () {
        _step(-1);
      },
      onNext: () {
        _step(1);
      },
      onModeSelected: _setMode,
      year: _picksMonth ? _pickerYear : null,
      onTitle: _picksMonth ? _closeMonthPicker : _openMonthPicker,
    );
  }

  /// The header on a card of its own, above the grids of Month and Week,
  /// with the month picker coming in under it ([_buildPickerArea]).
  Widget _buildHeaderCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: HarborColors.surface,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildCalendarHeader(),
              AnimatedBuilder(
                animation: _pickerShown,
                builder: (context, child) {
                  return _buildPickerArea(
                    _pickerShown.value,
                    const SizedBox.shrink(),
                    const EdgeInsets.only(top: 4.0),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The month grid and the day list in Agenda; the month board in Month;
  /// a timed grid of [_timedDays], across the body's full width, otherwise,
  /// under the week strip in the day mode.
  Widget _buildCalendarView() {
    if (_mode == _CalendarMode.month) {
      return _buildMonthView();
    }
    final days = _timedDays;
    if (days != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_mode == _CalendarMode.day)
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
              child: _buildCalendarCard(),
            )
          else
            _buildHeaderCard(),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleBoardScroll,
              child: TimedGrid(
                // Each mode builds its own grid, which opens scrolled to its
                // opening time, and so does a week of one shown weekday, as a
                // grid keeps one day column or more than one.
                key: ValueKey<(_CalendarMode, bool)>((
                  _mode,
                  days.count > 1 && _settings.weekdays.columns.length > 1,
                )),
                store: _store,
                settings: _settings,
                firstDay: days.first,
                dayCount: days.count,
                selectedDay: _selected,
                today: _today.value,
                now: _now,
                onSelectDay: _select,
                onOpenItem: _openItem,
                onCreate: (range) {
                  return showCreateFlow(
                    context,
                    store: _store,
                    range: range,
                    lock: _currentLock,
                  );
                },
                onZoom: (minSlotHeight, minDayWidth) {
                  _applySettings(
                    _settings.copyWith(
                      minSlotHeight: minSlotHeight,
                      minDayWidth: minDayWidth,
                    ),
                  );
                },
                maxDayCount: maxDayCount,
                // The week strip names Day's one day.
                showsDayHeader: _mode != _CalendarMode.day,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 0.0),
          child: _buildCalendarCard(),
        ),
        // A list of its own: it follows the store itself, and the month
        // board's cells follow it through their own marker listeners.
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleListScroll,
            child: DayList(
              key: const ValueKey<String>("day-list"),
              store: _store,
              weekdays: _settings.weekdays,
              format: _settings.hourLabelFormat,
              hours: _settings.hours,
              editable: _settings.editing,
              lock: _lock,
              selectedDay: _selected,
              today: _today.value,
              now: _now,
              onTopDay: _select,
              onCreateIn: (day, startMinute, endMinute) {
                showCreateFlow(
                  context,
                  store: _store,
                  range: CreateRange(
                    day: day,
                    startMinute: startMinute,
                    endMinute: endMinute,
                    dayCount: 1,
                  ),
                  lock: _currentLock,
                );
              },
              onEdit: (id) {
                showEditForm(
                  context,
                  store: _store,
                  id: id,
                  lock: _currentLock,
                );
              },
              onDelete: _deleteFromCard,
            ),
          ),
        ),
      ],
    );
  }

  /// The header card, and under it, on the surface colour across the
  /// body's full width and down to its bottom as the timed grids are, the
  /// weekday letters and the month board.
  Widget _buildMonthView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeaderCard(),
        Expanded(
          child: ColoredBox(
            color: HarborColors.surface,
            child: MonthBoard(
              key: const ValueKey<String>("month-board"),
              store: _store,
              grid: _grid,
              layout: _settings.monthLayout,
              minDayWidth: _settings.minDayWidth,
              weekScale: _settings.monthWeekScale,
              selectedDay: _selected,
              today: _today,
              onSelectDay: _select,
              onOpenDay: _openDayMode,
              onCreateOnDay: _settings.editing ? _createOn : null,
              onOpenItem: _openItem,
              onZoom: (weekScale, minDayWidth) {
                _applySettings(
                  _settings
                      .withMonthWeekScale(weekScale)
                      .copyWith(minDayWidth: minDayWidth),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarCard() {
    // Built once per build of this state and handed to the collapse
    // builder as its child, so the animation does not rebuild the board.
    final board = Board<Object, Object>(
      controller: _board,
      cellBuilder: _cellBuilder,
      selection: BoardSelectionConfig(
        mode: BoardSelectionMode.cell,
        onChanged: _handleBoardSelection,
      ),
      // The board is exactly as large as its lattice, so it never
      // scrolls, and it must not attach to the primary scroll controller
      // the day list uses.
      primary: false,
      verticalDetails: const ScrollableDetails.vertical(
        physics: NeverScrollableScrollPhysics(),
      ),
      horizontalDetails: const ScrollableDetails.horizontal(
        physics: NeverScrollableScrollPhysics(),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HarborColors.surface,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildCalendarHeader(),
            const SizedBox(height: 4.0),
            AnimatedBuilder(
              animation: _pickerShown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AnimatedBuilder(
                    animation: _collapseController,
                    child: board,
                    builder: (context, child) {
                      return _buildGrid(_collapseController.value, child!);
                    },
                  ),
                  _PullTab(
                    folded: _collapsed,
                    onDragStart: (details) {
                      _collapseController.stop();
                    },
                    onDragUpdate: _dragFold,
                    onDragEnd: _endFoldDrag,
                    onTap: () {
                      _settleCollapse(!_collapsed);
                    },
                  ),
                ],
              ),
              builder: (context, days) {
                // The picker does not fold, so it has no pull tab; under it
                // the card pads its bottom as the header card does in Week
                // and Month.
                return _buildPickerArea(
                  _pickerShown.value,
                  days!,
                  const EdgeInsets.only(bottom: 8.0),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// [days] under the header and the month picker, padded by
  /// [pickerPadding], in their place, the picker [shown] of the way in:
  /// each fades by how far the other is in, only the one coming in or in
  /// takes pointers, and the area is as tall as [days], [shown] of the way
  /// to the padded picker's height. [days] are built until the picker is
  /// all the way in, and the picker from when it starts in.
  Widget _buildPickerArea(
    double shown,
    Widget days,
    EdgeInsetsGeometry pickerPadding,
  ) {
    return ClipRect(
      clipBehavior: shown > 0.0 && shown < 1.0 ? Clip.hardEdge : Clip.none,
      child: _HeightLerp(
        key: calendarDaysAreaKey,
        t: shown,
        first: shown < 1.0
            ? IgnorePointer(
                ignoring: _picksMonth,
                child: Opacity(opacity: 1.0 - shown, child: days),
              )
            : const SizedBox.shrink(),
        second: shown > 0.0
            ? IgnorePointer(
                ignoring: !_picksMonth,
                child: Opacity(
                  opacity: shown,
                  child: Padding(
                    padding: pickerPadding,
                    child: _buildMonthPicker(),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  /// The strip of days the calendar card's folded month becomes, in Agenda
  /// and Day. Its weekdays are fixed for its life, so new ones build a new
  /// strip.
  Widget _buildStrip() {
    return WeekStrip(
      key: ValueKey<WeekdaySet>(_settings.weekdays),
      store: _store,
      selectedDay: _selected,
      today: _today.value,
      weekdays: _settings.weekdays,
      recalls: _stripRecalls,
      onSelectDay: _select,
      onBrowse: (day) {
        setState(() {
          _stripDay = day;
        });
      },
    );
  }

  /// The weekday header and the board at collapse [t]. The board keeps
  /// the height of the whole month; the window over it shrinks from the
  /// month to one row while the board moves up by the rows above the
  /// selected week, so that week slides to the top of the window. Once
  /// folded, at a [t] of 1, Day's strip takes the window's place, as tall
  /// as a row, opening on the selected week as the window shows it.
  Widget _buildGrid(double t, Widget board) {
    final weeks = _grid.weekCount;
    final monthHeight = weeks * _rowHeight;
    final selectedRow = _grid.cellOf(_selected).row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1.0 - t,
            child: Opacity(
              opacity: 1.0 - t,
              child: WeekdayHeader(
                weekdays: _settings.weekdays,
                abbreviated: true,
              ),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            _fitColumns(constraints.maxWidth);
            return SizedBox(
              key: const ValueKey<String>("calendar-grid"),
              height: lerpDouble(monthHeight, _rowHeight, t),
              child: t == 1.0
                  ? GestureDetector(
                      onVerticalDragStart: (details) {
                        _unfoldDrag = 0.0;
                      },
                      onVerticalDragUpdate: (details) {
                        _unfoldDrag += details.delta.dy;
                        if (_unfoldDrag >= _unfoldDistance) {
                          _setCollapsed(false);
                        }
                      },
                      child: _buildStrip(),
                    )
                  : ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: monthHeight,
                        maxHeight: monthHeight,
                        child: Transform.translate(
                          offset: Offset(0.0, -t * selectedRow * _rowHeight),
                          child: board,
                        ),
                      ),
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.day,
    required this.mode,
    required this.stepUnit,
    required this.onPrevious,
    required this.onNext,
    required this.onModeSelected,
    required this.year,
    required this.onTitle,
  });

  /// The day whose month, in three letters, and year the title names: the
  /// selected day, or the day at the middle of the strip once it is moved
  /// other than to follow the selection.
  final DateTime day;

  /// The mode picked from the menu, which the label names.
  final _CalendarMode mode;

  final _StepUnit stepUnit;

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<_CalendarMode> onModeSelected;

  /// The year the title names alone while the month picker shows; null
  /// while it does not.
  final int? year;

  /// The title was tapped, which opens the month picker, or closes it
  /// while [year] is given.
  final VoidCallback onTitle;

  static const TextStyle _titleStyle = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w600,
    color: HarborColors.text,
  );

  /// The width of the widest of [year]'s titles as the title's [Text] lays
  /// it out: its style merged over the default one, bold where the
  /// platform asks for bold text, at the platform's text scale. The title
  /// takes that width whatever the month, so the next chevron after it
  /// stays put.
  static double _titleWidth(BuildContext context, int year) {
    var style = DefaultTextStyle.of(context).style.merge(_titleStyle);
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    var widest = 0.0;
    for (final name in monthShortNames) {
      painter.text = TextSpan(text: "$name $year", style: style);
      painter.layout();
      if (painter.width > widest) {
        widest = painter.width;
      }
    }
    painter.dispose();
    return widest.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final unit = stepUnit.label;
    return Row(
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: "Previous $unit",
                color: HarborColors.text,
                visualDensity: VisualDensity.compact,
                onPressed: onPrevious,
              ),
              // Shrinks, and the title in it, only where the row is too
              // narrow for it.
              Flexible(
                child: Tooltip(
                  message: year == null ? "Pick a month" : "Close the months",
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8.0),
                    onTap: onTitle,
                    child: SizedBox(
                      width: _titleWidth(context, year ?? day.year),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          year == null
                              ? "${monthShortNames[day.month - 1]} ${day.year}"
                              : "$year",
                          style: _titleStyle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: "Next $unit",
                color: HarborColors.text,
                visualDensity: VisualDensity.compact,
                onPressed: onNext,
              ),
            ],
          ),
        ),
        PopupMenuButton<_CalendarMode>(
          tooltip: "Calendar view",
          initialValue: mode,
          color: HarborColors.surface,
          onSelected: onModeSelected,
          itemBuilder: (context) {
            return <PopupMenuEntry<_CalendarMode>>[
              for (final value in _CalendarMode.values)
                PopupMenuItem<_CalendarMode>(
                  value: value,
                  child: Text(value.label),
                ),
            ];
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(mode.label, style: _titleStyle),
                const SizedBox(width: 4.0),
                const Icon(Icons.keyboard_arrow_down, color: HarborColors.text),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The key of the calendar bar the app bar's chevron opens.
const ValueKey<String> calendarBarKey = ValueKey<String>("calendar-bar");

/// The key of the calendar card's pull tab.
const ValueKey<String> calendarPullTabKey = ValueKey<String>(
  "calendar-pull-tab",
);

/// The key of the area under the calendar header that the month picker
/// comes into: in Agenda's and Day's card in place of the days, and under
/// the header in Week's and Month's.
const ValueKey<String> calendarDaysAreaKey = ValueKey<String>(
  "calendar-days-area",
);

/// [first] and [second] across its width at their own heights, both from
/// its top, [second] painted over [first], in an area as tall as [first],
/// [t] of the way to [second]'s height.
class _HeightLerp extends MultiChildRenderObjectWidget {
  _HeightLerp({
    super.key,
    required this.t,
    required Widget first,
    required Widget second,
  }) : super(children: <Widget>[first, second]);

  final double t;

  @override
  _RenderHeightLerp createRenderObject(BuildContext context) {
    return _RenderHeightLerp(t);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightLerp renderObject,
  ) {
    renderObject.t = t;
  }
}

class _HeightLerpParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderHeightLerp extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeightLerpParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeightLerpParentData> {
  _RenderHeightLerp(this._t);

  double _t;

  set t(double value) {
    if (value == _t) {
      return;
    }
    _t = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeightLerpParentData) {
      child.parentData = _HeightLerpParentData();
    }
  }

  Size _sizeFor(BoxConstraints constraints, double first, double second) {
    return constraints.constrain(
      Size(constraints.maxWidth, lerpDouble(first, second, _t)!),
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final childConstraints = BoxConstraints.tightFor(
      width: constraints.maxWidth,
    );
    return _sizeFor(
      constraints,
      firstChild!.getDryLayout(childConstraints).height,
      lastChild!.getDryLayout(childConstraints).height,
    );
  }

  @override
  void performLayout() {
    final childConstraints = BoxConstraints.tightFor(
      width: constraints.maxWidth,
    );
    var child = firstChild;
    while (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      child = childAfter(child);
    }
    size = _sizeFor(
      constraints,
      firstChild!.size.height,
      lastChild!.size.height,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

/// A short bar under the calendar card's days that a vertical drag moves
/// with the finger, folding the month into its week or unfolding it, and
/// a tap switches.
class _PullTab extends StatelessWidget {
  const _PullTab({
    required this.folded,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onTap,
  });

  /// Whether the card shows the week, which names what a tap shows.
  final bool folded;

  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: folded ? "Show the month" : "Show the week",
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: calendarPullTabKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onVerticalDragStart: onDragStart,
        onVerticalDragUpdate: onDragUpdate,
        onVerticalDragEnd: onDragEnd,
        child: SizedBox(
          height: 20.0,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: HarborColors.outline,
                borderRadius: BorderRadius.circular(2.0),
              ),
              child: const SizedBox(width: 36.0, height: 4.0),
            ),
          ),
        ),
      ),
    );
  }
}
