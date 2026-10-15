/// A workspace calendar on the board module, over a calendar API: a month
/// grid that folds into the selected day's week while the day list is
/// scrolled, the selected day's items under it, and timed grids of the
/// selected day's week and of that day alone, where items are created,
/// moved, resized, edited and deleted.
///
/// The month grid is a [Board] with no items. Each day is a cell, a tap
/// selects it through the board's cell selection, and the arrow keys move
/// that selection once the board has focus. The board always holds the
/// whole month of the selected day; the folded strip is that board clipped
/// to one row and shifted so the selected week shows. Selecting a day in
/// another month, by a tap on a muted day, the chevrons or a key, switches
/// the board to that month.
///
/// The calendar reads the range it shows through a [CalendarModel], which
/// caches the days it has read and writes one change per item at a time.
/// The settings sheet chooses the hours the calendar shows and schedules
/// in and the least size of the timed grids' cells. The Board and Table
/// views are placeholders, and More only reports that it is not
/// available.
library;

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
import 'workspace_calendar/settings_sheet.dart';
import 'workspace_calendar/timed_grid.dart';

enum _WorkspaceView {
  calendar("Calendar"),
  board("Board"),
  table("Table");

  const _WorkspaceView(this.label);

  final String label;
}

enum _CalendarMode {
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
  const WorkspaceCalendarExample({super.key, this.today, this.api});

  /// The day the calendar opens on and marks as today. Null reads the
  /// clock.
  final DateTime? today;

  /// The store the calendar reads and writes, read once when the calendar
  /// is first built. Null uses a [MockCalendarApi] seeded around [today],
  /// at [defaultCalendarLatency] and with no failures.
  final CalendarApi? api;

  static final ThemeData _theme = buildHarborTheme();

  @override
  Widget build(BuildContext context) {
    // Above the calendar's state, so every dialog and menu it opens from
    // its own context captures this theme.
    return Theme(
      data: _theme,
      child: _WorkspaceCalendar(today: today, api: api),
    );
  }
}

class _WorkspaceCalendar extends StatefulWidget {
  const _WorkspaceCalendar({required this.today, required this.api});

  final DateTime? today;
  final CalendarApi? api;

  @override
  State<_WorkspaceCalendar> createState() {
    return _WorkspaceCalendarState();
  }
}

class _WorkspaceCalendarState extends State<_WorkspaceCalendar>
    with TickerProviderStateMixin {
  static const double _rowHeight = 48.0;

  late final DateTime _today = dateOnly(widget.today ?? DateTime.now());

  late final CalendarModel _model;

  late DateTime _selected = _today;

  /// The month of [_selected], which is the lattice the board shows.
  late MonthGrid _grid = MonthGrid.of(_selected);

  _WorkspaceView _view = _WorkspaceView.calendar;

  /// The view picked from the menu.
  _CalendarMode _mode = _CalendarMode.month;

  /// Whether a scroll of the day list folded the month into its week. Only
  /// meaningful in the month mode.
  bool _collapsed = false;

  /// What the settings sheet last chose.
  CalendarSettings _settings = const CalendarSettings();

  /// The width the column axis was last fitted to.
  double _columnsWidth = 0.0;

  late final AnimationController _collapseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final CurvedAnimation _collapse = CurvedAnimation(
    parent: _collapseController,
    curve: Curves.easeInOut,
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
      api: widget.api ?? MockCalendarApi.seeded(_today),
      onWriteFailed: _handleWriteFailed,
    );
    // The month board holds no items, so its key and payload types are
    // unused.
    _board = BoardController<Object, Object>(
      vsync: this,
      rows: _rowsFor(_grid),
      // Replaced by the first layout, which knows the width.
      columns: BoardAxisConfig(axis: UniformAxis(7, _rowHeight)),
      keyOf: (item) {
        return item;
      },
    );
    _board.setSelection(_selectionOf(_selected));
    _showRange();
  }

  @override
  void dispose() {
    _model.dispose();
    _board.dispose();
    _collapse.dispose();
    _collapseController.dispose();
    super.dispose();
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
  /// null in the month mode. [_showRange] and the grid both read it.
  ({DateTime first, int count})? get _timedDays {
    switch (_mode) {
      case _CalendarMode.month:
        return null;
      case _CalendarMode.week:
        return (first: weekStartOf(_selected), count: 7);
      case _CalendarMode.day:
        return (first: _selected, count: 1);
    }
  }

  /// Shows the month grid's days in the month mode and [_timedDays]
  /// otherwise, which reads whatever of them is not read yet.
  void _showRange() {
    final days = _timedDays;
    if (days == null) {
      _model.show(_grid.firstDay, _grid.lastDay);
    } else {
      _model.show(days.first, addDays(days.first, days.count - 1));
    }
  }

  /// Seven equal columns across [width]. Called from the grid's layout
  /// callback, so the first frame already lays the board out at its
  /// width.
  void _fitColumns(double width) {
    if (width == _columnsWidth) {
      return;
    }
    _columnsWidth = width;
    _board.columns = BoardAxisConfig(axis: UniformAxis(7, width / 7));
  }

  void _select(DateTime day) {
    if (day == _selected) {
      return;
    }
    final monthChanged = !_grid.contains(day);
    setState(() {
      _selected = day;
      if (monthChanged) {
        _grid = MonthGrid.of(day);
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
      case _CalendarMode.month:
        return _collapsed ? _StepUnit.week : _StepUnit.month;
      case _CalendarMode.week:
        return _StepUnit.week;
      case _CalendarMode.day:
        return _StepUnit.day;
    }
  }

  /// Steps by [_stepUnit]; a month step keeps the day of the month where it
  /// can.
  void _step(int direction) {
    switch (_stepUnit) {
      case _StepUnit.day:
        _select(addDays(_selected, direction));
      case _StepUnit.week:
        _select(addDays(_selected, 7 * direction));
      case _StepUnit.month:
        _select(addMonths(_selected, direction));
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

  /// The calendar tab's week mode, on the selected day's week.
  void _openWeekMode() {
    setState(() {
      _view = _WorkspaceView.calendar;
    });
    _setMode(_CalendarMode.week);
  }

  void _setCollapsed(bool collapsed) {
    if (collapsed == _collapsed || _mode != _CalendarMode.month) {
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

  void _applySettings(CalendarSettings settings) {
    setState(() {
      _settings = settings;
    });
    _model.hours = settings.hours;
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
    final day = _grid.dateAt(cell.row, cell.col);
    final inMonth = _grid.contains(day);
    final isSelected = cell.isSelected;
    return DayMarkerListener(
      model: _model,
      day: day,
      builder: (context, hasItems) {
        return DayCell(
          key: dayCellKey(day),
          day: day,
          inMonth: inMonth,
          isSelected: isSelected,
          isToday: day == _today,
          hasItems: hasItems,
          collapse: _collapse,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    switch (_view) {
      case _WorkspaceView.calendar:
        body = _buildCalendarView();
      case _WorkspaceView.board:
      case _WorkspaceView.table:
        body = _PlaceholderView(name: _view.label);
    }
    final showsTimedGrid =
        _view == _WorkspaceView.calendar && _mode != _CalendarMode.month;
    return Scaffold(
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
          if (!showsTimedGrid)
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: "Add",
              onPressed: _openWeekMode,
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
      floatingActionButton:
          _view == _WorkspaceView.calendar && _mode == _CalendarMode.month
          ? FloatingActionButton(
              tooltip: "Add item",
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              onPressed: _openWeekMode,
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0.0),
            child: _ViewSwitcher(
              selected: _view,
              onSelected: (view) {
                setState(() {
                  _view = view;
                });
              },
            ),
          ),
          Expanded(child: body),
        ],
      ),
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

  /// The month grid and the day list in the month mode; a timed grid of
  /// [_timedDays], across the body's full width, otherwise.
  Widget _buildCalendarView() {
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
              today: _today,
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
                      title: dayTitle(_selected, _today),
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
            child: Opacity(opacity: 1.0 - t, child: const _WeekdayHeader()),
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

class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({required this.selected, required this.onSelected});

  final _WorkspaceView selected;
  final ValueChanged<_WorkspaceView> onSelected;

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];
    for (final view in _WorkspaceView.values) {
      if (segments.isNotEmpty) {
        segments.add(
          const VerticalDivider(
            width: 1.0,
            thickness: 1.0,
            color: HarborColors.outline,
          ),
        );
      }
      final isSelected = view == selected;
      segments.add(
        Expanded(
          child: Semantics(
            selected: isSelected,
            child: Material(
              color: isSelected
                  ? HarborColors.primaryTint
                  : HarborColors.surface,
              child: InkWell(
                onTap: () {
                  onSelected(view);
                },
                child: Center(
                  child: Text(
                    view.label,
                    style: TextStyle(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? HarborColors.primary
                          : HarborColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      height: 40.0,
      decoration: BoxDecoration(
        border: Border.all(color: HarborColors.outline),
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: segments,
        ),
      ),
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

/// The weekday letters over the month grid, one per board column: both
/// divide the same width into seven equal parts.
class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey<String>("weekday-header"),
      height: 32.0,
      child: Row(
        children: <Widget>[
          for (final letter in weekdayLetters)
            Expanded(
              child: Center(
                child: Text(
                  letter,
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

class _PlaceholderView extends StatelessWidget {
  const _PlaceholderView({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        "$name view is not available yet.",
        style: const TextStyle(
          fontSize: 15.0,
          color: HarborColors.textSecondary,
        ),
      ),
    );
  }
}
