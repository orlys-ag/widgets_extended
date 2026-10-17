/// A workspace calendar on the board module, over a calendar API, in four
/// views: Agenda, a month grid over a list of the days, one after another,
/// each day's items beside their times and lengths, the month folding into
/// the selected day's week as the list is scrolled;
/// Month, the month's weeks with each item as a chip on the days it
/// covers; and Week and Day, timed grids of the selected day's week and of
/// that day alone, where items are created, moved, resized, edited and
/// deleted.
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
/// item's card sits right of its start time, "to" and its end time, over
/// a chip of its length; the list marks each whole hour between a day's
/// items that no item covers with a dashed row, and a day without items
/// with one reading "No items", each with a button that creates an item
/// there. A drag of the list folds the month, and the pull tab under the
/// card folds or unfolds it as far as a drag on it moves, a tap on it
/// switching; a downward drag on the folded strip unfolds it too. The
/// board always holds
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
/// which add an item's times to its title. A tap on a chip edits its item,
/// and a tap anywhere else on a day opens that day in Day. A long press on
/// a day creates an item there at the day's first free hour, selecting the
/// day when it is in the month. Its keys and chevrons move the selected
/// day as Agenda's do.
///
/// The calendar reads the range it shows through a [CalendarModel], which
/// caches the days it has read and writes one change per item at a time.
/// The settings sheet chooses the weekday a week starts on, which every
/// view's weeks and columns follow, and which weekdays show, how Month fits
/// its weeks, the hours the calendar shows and schedules in, whether Week
/// and Day label them AM/PM, the least width of a day in Week, Day and
/// Month, and the least height of the timed grids' slots, whose ratio to
/// its default scales Month's weeks past their share of the screen. A
/// selected day is always on a shown weekday. Every view rings today's
/// number in a lighter blue than the primary. More only reports that it is
/// not available.
library;

import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'workspace_calendar/calendar_api.dart';
import 'workspace_calendar/calendar_data.dart';
import 'workspace_calendar/calendar_model.dart';
import 'workspace_calendar/calendar_settings.dart';
import 'workspace_calendar/day_cell.dart';
import 'workspace_calendar/day_list.dart';
import 'workspace_calendar/harbor_theme.dart';
import 'workspace_calendar/item_form.dart';
import 'workspace_calendar/mock_calendar_api.dart';
import 'workspace_calendar/month_board.dart';
import 'workspace_calendar/settings_sheet.dart';
import 'workspace_calendar/timed_grid.dart';
import 'workspace_calendar/week_strip.dart';

enum _CalendarMode {
  agenda("Agenda"),
  month("Month"),
  week("Week"),
  day("Day");

  const _CalendarMode(this.label);

  final String label;
}

/// What the chevrons step by, which their tooltips name.
enum _StepUnit {
  day("day"),
  week("week"),
  month("month");

  const _StepUnit(this.label);

  final String label;
}

/// The calendar under its own Harbor theme, whatever the host's theme.
class WorkspaceCalendarExample extends StatelessWidget {
  const WorkspaceCalendarExample({super.key, this.today, this.api, this.clock});

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

  static final ThemeData _theme = buildHarborTheme();

  @override
  Widget build(BuildContext context) {
    // Above the calendar's state, so every dialog and menu it opens from
    // its own context captures this theme.
    return Theme(
      data: _theme,
      child: _WorkspaceCalendar(
        today: today,
        api: api,
        clock: clock ?? DateTime.now,
      ),
    );
  }
}

class _WorkspaceCalendar extends StatefulWidget {
  const _WorkspaceCalendar({
    required this.today,
    required this.api,
    required this.clock,
  });

  final DateTime? today;
  final CalendarApi? api;
  final DateTime Function() clock;

  @override
  State<_WorkspaceCalendar> createState() {
    return _WorkspaceCalendarState();
  }
}

class _WorkspaceCalendarState extends State<_WorkspaceCalendar>
    with TickerProviderStateMixin {
  static const double _rowHeight = 48.0;

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

  late final CalendarModel _model;

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

  /// What the settings sheet last chose.
  CalendarSettings _settings = const CalendarSettings();

  /// The width the column axis was last fitted to.
  double _columnsWidth = 0.0;

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
    _model = CalendarModel(
      api: widget.api ?? MockCalendarApi.seeded(_today.value),
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
    }
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    _model.dispose();
    _board.dispose();
    _collapseController.dispose();
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

  /// Reads the clock again at the start of the minute after [now], and
  /// from then on at the start of each. A new day rebuilds this state for
  /// the day title and the timed grid.
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
      if (today != _today.value) {
        setState(() {
          _today.value = today;
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
        _model.show(_grid.firstDay, _grid.lastDay);
      case _CalendarMode.week:
        final days = _timedDays!;
        _model.show(days.first, addDays(days.first, days.count - 1));
      case _CalendarMode.day:
        final days = shownDaysOfWeek(_selected, _settings.weekdays);
        _model.show(days.first, days.last);
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

  /// A day in the day mode, a week in the week mode and the folded month,
  /// a month otherwise.
  _StepUnit get _stepUnit {
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
  /// hidden one.
  void _step(int direction) {
    final weekdays = _settings.weekdays;
    switch (_stepUnit) {
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
    });
    _collapseController.value = _collapsed ? 1.0 : 0.0;
    _showRange();
  }

  /// The week mode, on the selected day's week.
  void _openWeekMode() {
    _setMode(_CalendarMode.week);
  }

  /// The day mode, on [day].
  void _openDayMode(DateTime day) {
    _select(day);
    _setMode(_CalendarMode.day);
  }

  /// The create flow for [day] at its first free hour, from [from] when
  /// given, selecting [day] first when it is a day of the shown month; a
  /// day of another month leaves the selection and the month as they are.
  void _createOn(DateTime day, {int? from}) {
    if (_grid.contains(day)) {
      _select(day);
    }
    _openCreateFlow(day, from: from);
  }

  /// The create flow on [day] at its first free hour from [from].
  void _openCreateFlow(DateTime day, {int? from}) {
    final free = _model.firstFreeRange(day, from: from);
    showCreateFlow(
      context,
      model: _model,
      range: CreateRange(
        day: day,
        startMinute: free.start,
        endMinute: free.end,
        dayCount: 1,
      ),
    );
  }

  /// The app bar's Add outside Agenda: the create flow on the selected
  /// day, in Month at its first free hour, and in Week and Day at its first
  /// free hour from [addFromMinute], near the time the grid opens at.
  void _add() {
    if (_mode == _CalendarMode.month) {
      _createOn(_selected);
    } else {
      _createOn(_selected, from: addFromMinute(_selected, _now.value));
    }
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
  /// month again once it changes.
  void _settleCollapse(bool collapsed) {
    if (collapsed != _collapsed) {
      setState(() {
        _collapsed = collapsed;
        _stripDay = null;
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
      if (weekdaysChanged) {
        _selected = shownDayNear(_selected, settings.weekdays);
        _grid = MonthGrid.of(_selected, weekdays: settings.weekdays);
      }
    });
    _model.hours = settings.hours;
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
  void _handleWriteFailed(String message) {
    if (mounted) {
      _showMessage(message);
    }
  }

  Future<void> _deleteFromCard(String id) async {
    final confirmed = await confirmDelete(context);
    if (confirmed && mounted) {
      _model.requestDelete(id);
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
      model: _model,
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
    final agenda = _mode == _CalendarMode.agenda;
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
            icon: const Icon(Icons.add_circle_outline),
            tooltip: "Add",
            onPressed: agenda ? _openWeekMode : _add,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: "Calendar settings",
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: "More",
            onPressed: () {
              _showMessage("More options are not available yet.");
            },
          ),
        ],
      ),
      floatingActionButton: !agenda
          ? null
          : FloatingActionButton(
              tooltip: "Add item",
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              onPressed: _openWeekMode,
              child: const Icon(Icons.add),
            ),
      body: _buildCalendarView(),
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
    );
  }

  /// The header on a card of its own, above the grids of Month, Week and
  /// Day, with [below] under it on the card.
  Widget _buildHeaderCard({Widget? below}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: HarborColors.surface,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: below == null
              ? _buildCalendarHeader()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildCalendarHeader(),
                    const SizedBox(height: 4.0),
                    below,
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
                model: _model,
                settings: _settings,
                firstDay: days.first,
                dayCount: days.count,
                selectedDay: _selected,
                today: _today.value,
                now: _now,
                onSelectDay: _select,
                onOpenItem: (id) {
                  showEditForm(context, model: _model, id: id);
                },
                onCreate: (range) {
                  showCreateFlow(context, model: _model, range: range);
                },
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
        // A list of its own: it follows the model itself, and the month
        // board's cells follow it through their own marker listeners.
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleListScroll,
            child: DayList(
              key: const ValueKey<String>("day-list"),
              model: _model,
              weekdays: _settings.weekdays,
              format: _settings.hourLabelFormat,
              selectedDay: _selected,
              today: _today.value,
              onTopDay: _select,
              onCreateIn: (day, startMinute, endMinute) {
                showCreateFlow(
                  context,
                  model: _model,
                  range: CreateRange(
                    day: day,
                    startMinute: startMinute,
                    endMinute: endMinute,
                    dayCount: 1,
                  ),
                );
              },
              onCreateOn: _openCreateFlow,
              onEdit: (id) {
                showEditForm(context, model: _model, id: id);
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
              model: _model,
              grid: _grid,
              layout: _settings.monthLayout,
              minDayWidth: _settings.minDayWidth,
              weekScale: _settings.monthWeekScale,
              selectedDay: _selected,
              today: _today,
              onSelectDay: _select,
              onOpenDay: _openDayMode,
              onCreateOnDay: _createOn,
              onOpenItem: (id) {
                showEditForm(context, model: _model, id: id);
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
      ),
    );
  }

  /// The strip of days the calendar card's folded month becomes, in Agenda
  /// and Day. Its weekdays are fixed for its life, so new ones build a new
  /// strip.
  Widget _buildStrip() {
    return WeekStrip(
      key: ValueKey<WeekdaySet>(_settings.weekdays),
      model: _model,
      selectedDay: _selected,
      today: _today.value,
      weekdays: _settings.weekdays,
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
  /// folded, at a [t] of 1, Day's strip takes the window's place, opening
  /// on the selected week as the window shows it.
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

  static const TextStyle _titleStyle = TextStyle(
    fontSize: 20.0,
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
                child: SizedBox(
                  width: _titleWidth(context, day.year),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      "${monthShortNames[day.month - 1]} ${day.year}",
                      style: _titleStyle,
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

/// The key of the calendar card's pull tab.
const ValueKey<String> calendarPullTabKey = ValueKey<String>(
  "calendar-pull-tab",
);

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
