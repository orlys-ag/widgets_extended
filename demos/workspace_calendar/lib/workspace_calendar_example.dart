/// A workspace calendar on the board module, over a calendar API, in four
/// views: Agenda, a month grid that folds into the selected day's week
/// while the day list under it, the selected day's items, is scrolled;
/// Month, the month's weeks with each item as a chip on the days it
/// covers; and Week and Day, timed grids of the selected day's week and of
/// that day alone, where items are created, moved, resized, edited and
/// deleted.
///
/// Agenda's month grid is a [Board] with no items. Each day is a cell, a
/// tap selects it through the board's cell selection, and the arrow keys
/// move that selection once the board has focus. The board always holds
/// the whole month of the selected day; the folded strip is that board
/// clipped to one row and shifted so the selected week shows. Selecting a
/// day in another month, by a tap on a muted day, the chevrons or a key,
/// switches the board to that month.
///
/// Month's grid is a [MonthBoard], whose weeks fill the screen and grow
/// with their chips. A tap on a chip edits its item, on a day's number
/// opens that day in Day, and on the rest of a day creates an item there
/// at the day's first free hour, selecting the day when it is in the
/// month. Its keys and chevrons move the selected day as Agenda's do.
///
/// The calendar reads the range it shows through a [CalendarModel], which
/// caches the days it has read and writes one change per item at a time.
/// The settings sheet chooses whether the weekends show, the hours the
/// calendar shows and schedules in, and the least size of the timed grids'
/// cells. A selected day is always on a shown weekday. More only reports
/// that it is not available.
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

  /// The month of [_selected], which is the lattice the board shows.
  late MonthGrid _grid = MonthGrid.of(_selected, weekdays: _settings.weekdays);

  /// The view picked from the menu.
  _CalendarMode _mode = _CalendarMode.agenda;

  /// Whether a scroll of the day list folded the month into its week. Only
  /// meaningful in Agenda.
  bool _collapsed = false;

  /// What the settings sheet last chose.
  CalendarSettings _settings = const CalendarSettings();

  /// The width the column axis was last fitted to.
  double _columnsWidth = 0.0;

  late final AnimationController _collapseController = AnimationController(
    vsync: this,
    duration: harborMotionDuration,
  );
  late final CurvedAnimation _collapse = CurvedAnimation(
    parent: _collapseController,
    curve: harborMotionCurve,
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
    _collapse.dispose();
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

  /// The days the timed grid shows: the selected day's Monday-to-Sunday
  /// week in the week mode, the selected day alone in the day mode, and
  /// null in Agenda and Month. [_showRange] and the grid both read it.
  ({DateTime first, int count})? get _timedDays {
    switch (_mode) {
      case _CalendarMode.agenda:
      case _CalendarMode.month:
        return null;
      case _CalendarMode.week:
        return (first: weekStartOf(_selected), count: 7);
      case _CalendarMode.day:
        return (first: _selected, count: 1);
    }
  }

  /// Shows the month grid's days in Agenda and Month and [_timedDays]
  /// otherwise, which reads whatever of them is not read yet.
  void _showRange() {
    final days = _timedDays;
    if (days == null) {
      _model.show(_grid.firstDay, _grid.lastDay);
    } else {
      _model.show(days.first, addDays(days.first, days.count - 1));
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

  void _setMode(_CalendarMode mode) {
    setState(() {
      _mode = mode;
      _collapsed = false;
    });
    _animateCollapse();
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

  /// The create flow for [day] at its first free hour, selecting [day]
  /// first when it is a day of the shown month; a day of another month
  /// leaves the selection and the month as they are.
  void _createOn(DateTime day) {
    if (_grid.contains(day)) {
      _select(day);
    }
    final free = _model.firstFreeRange(day);
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

  void _setCollapsed(bool collapsed) {
    if (collapsed == _collapsed || _mode != _CalendarMode.agenda) {
      return;
    }
    setState(() {
      _collapsed = collapsed;
    });
    _animateCollapse();
  }

  void _animateCollapse() {
    if (_collapsed) {
      _collapseController.forward();
    } else {
      _collapseController.reverse();
    }
  }

  /// A drag that moves the list's content up folds the month into its
  /// week; a drag that pulls the list down at its top unfolds it. Only
  /// drags count, so a fling that coasts back to the top leaves the week
  /// showing. Overscroll counts as well, so a list too short to scroll
  /// still folds and unfolds.
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
    final metrics = notification.metrics;
    if (delta > 0.0) {
      _setCollapsed(true);
    } else if (delta < 0.0 && metrics.pixels <= metrics.minScrollExtent) {
      _setCollapsed(false);
    }
    return false;
  }

  void _openSettings() {
    showCalendarSettings(
      context,
      settings: _settings,
      onChanged: _applySettings,
    );
  }

  /// New weekdays move a selected day they hide to the nearest shown one
  /// and rebuild the month board's lattice, whose cells they change.
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
              collapse: _collapse,
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
          if (agenda || month)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: "Add",
              onPressed: month
                  ? () {
                      _createOn(_selected);
                    }
                  : _openWeekMode,
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
      title: "${monthNames[_selected.month - 1]} ${_selected.year}",
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

  /// The month grid and the day list in Agenda; the month board in Month;
  /// a timed grid of [_timedDays], across the body's full width, otherwise.
  Widget _buildCalendarView() {
    if (_mode == _CalendarMode.month) {
      return _buildMonthView();
    }
    final days = _timedDays;
    if (days != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: HarborColors.surface,
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: _buildCalendarHeader(),
              ),
            ),
          ),
          Expanded(
            child: TimedGrid(
              // Each mode builds its own grid, which opens scrolled to its
              // opening time.
              key: ValueKey<_CalendarMode>(_mode),
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
        // Only the day header and the list follow the model; the month
        // board's cells follow it through their own marker listeners.
        Expanded(
          child: ListenableBuilder(
            listenable: _model,
            builder: (context, child) {
              final ready = _model.status == CalendarLoadStatus.ready;
              final entries = _model.itemsOn(_selected);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 12.0),
                    child: _DayHeader(
                      title: dayTitle(_selected, _today.value),
                      count: ready ? entries.length : null,
                    ),
                  ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _handleListScroll,
                      // Keyed by day, so another day's list is a new tree
                      // that starts at its top and does not animate in.
                      child: DayList(
                        key: ValueKey<DateTime>(_selected),
                        status: _model.status,
                        error: _model.error,
                        onRetry: _model.retry,
                        entries: entries,
                        onEdit: (id) {
                          showEditForm(context, model: _model, id: id);
                        },
                        onDelete: _deleteFromCard,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// The header card filling the body: the header, the weekday letters
  /// and the month board under them.
  Widget _buildMonthView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 0.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: HarborColors.surface,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildCalendarHeader(),
              const SizedBox(height: 4.0),
              _WeekdayHeader(weekdays: _settings.weekdays),
              Expanded(
                child: MonthBoard(
                  key: const ValueKey<String>("month-board"),
                  model: _model,
                  grid: _grid,
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
            ],
          ),
        ),
      ),
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
        padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildCalendarHeader(),
            const SizedBox(height: 4.0),
            AnimatedBuilder(
              animation: _collapse,
              child: board,
              builder: (context, child) {
                return _buildGrid(_collapse.value, child!);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// The weekday header and the board at collapse [t]. The board keeps
  /// the height of the whole month; the window over it shrinks from the
  /// month to one row while the board moves up by the rows above the
  /// selected week, so that week slides to the top of the window.
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
              child: _WeekdayHeader(weekdays: _settings.weekdays),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            _fitColumns(constraints.maxWidth);
            return SizedBox(
              key: const ValueKey<String>("calendar-grid"),
              height: lerpDouble(monthHeight, _rowHeight, t),
              child: ClipRect(
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
    required this.title,
    required this.mode,
    required this.stepUnit,
    required this.onPrevious,
    required this.onNext,
    required this.onModeSelected,
  });

  final String title;

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
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(title, style: _titleStyle),
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

/// The letters of the shown weekdays over the month grid, one per board
/// column: both divide the same width into equal parts.
class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.weekdays});

  final WeekdaySet weekdays;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey<String>("weekday-header"),
      height: 32.0,
      child: Row(
        children: <Widget>[
          for (var column = 0; column < weekdayLetters.length; column++)
            if (weekdays.containsColumn(column))
              Expanded(
                child: Center(
                  child: Text(
                    weekdayLetters[column],
                    style: const TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.w600,
                      color: HarborColors.text,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.title, required this.count});

  final String title;

  /// The day's item count, or null while the shown range is not ready.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16.0,
              fontWeight: FontWeight.w700,
              color: HarborColors.text,
            ),
          ),
        ),
        if (count != null)
          Text(
            itemCountLabel(count),
            style: const TextStyle(
              fontSize: 15.0,
              fontWeight: FontWeight.w600,
              color: HarborColors.textSecondary,
            ),
          ),
      ],
    );
  }
}
