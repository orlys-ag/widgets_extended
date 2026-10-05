/// A workspace calendar on the board module: a month grid that folds into
/// the selected day's week while the task list is scrolled, and the
/// selected day's tasks under it.
///
/// The grid is a [Board] with no items. Each day is a cell, a tap selects
/// it through the board's cell selection, and the arrow keys move that
/// selection once the board has focus. The board always holds the whole
/// month of the selected day; the week view is that board clipped to one
/// row and shifted so the selected week shows. Selecting a day in another
/// month, by a tap on a muted day, the chevrons or a key, switches the
/// board to that month.
///
/// The Board and Table views are placeholders, and the add, more and task
/// menu buttons only report that they are not available.
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'workspace_calendar/calendar_data.dart';
import 'workspace_calendar/day_cell.dart';
import 'workspace_calendar/palette.dart';
import 'workspace_calendar/task_card.dart';

enum _WorkspaceView {
  calendar("Calendar"),
  board("Board"),
  table("Table");

  const _WorkspaceView(this.label);

  final String label;
}

enum _CalendarMode {
  month("Month"),
  week("Week");

  const _CalendarMode(this.label);

  final String label;
}

class WorkspaceCalendarExample extends StatefulWidget {
  const WorkspaceCalendarExample({super.key, this.today});

  /// The day the calendar opens on and marks as today. Null reads the
  /// clock. The mock tasks are laid out around it.
  final DateTime? today;

  @override
  State<WorkspaceCalendarExample> createState() {
    return _WorkspaceCalendarExampleState();
  }
}

class _WorkspaceCalendarExampleState extends State<WorkspaceCalendarExample>
    with TickerProviderStateMixin {
  static const double _rowHeight = 48.0;

  late final DateTime _today = dateOnly(widget.today ?? DateTime.now());
  late final Map<DateTime, List<CalendarTask>> _tasksByDay = mockTasksByDay(
    _today,
  );

  late DateTime _selected = _today;

  /// The month of [_selected], which is the lattice the board shows.
  late MonthGrid _grid = MonthGrid.of(_selected);

  _WorkspaceView _view = _WorkspaceView.calendar;

  /// The view picked from the menu.
  _CalendarMode _mode = _CalendarMode.month;

  /// Whether a scroll of the task list folded the month view into its
  /// week. Only meaningful in the month mode.
  bool _collapsed = false;

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

  bool get _showsWeek {
    return _mode == _CalendarMode.week || _collapsed;
  }

  @override
  void initState() {
    super.initState();
    // The board holds no items, so its key and payload types are unused.
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
  }

  @override
  void dispose() {
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
  }

  void _handleBoardSelection(BoardSelection selection) {
    final focus = selection.focus;
    if (focus == null) {
      return;
    }
    _select(_grid.dateAt(focus.row, focus.col));
  }

  /// A week in the week view and a month in the month view; a month step
  /// keeps the day of the month where it can.
  void _step(int direction) {
    if (_showsWeek) {
      _select(addDays(_selected, 7 * direction));
    } else {
      _select(addMonths(_selected, direction));
    }
  }

  void _setMode(_CalendarMode mode) {
    setState(() {
      _mode = mode;
      _collapsed = false;
    });
    _animateCollapse();
  }

  void _setCollapsed(bool collapsed) {
    if (collapsed == _collapsed || _mode == _CalendarMode.week) {
      return;
    }
    setState(() {
      _collapsed = collapsed;
    });
    _animateCollapse();
  }

  void _animateCollapse() {
    if (_showsWeek) {
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

  void _showUnavailable(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildDay(BuildContext context, BoardCellView<Object, Object> cell) {
    final day = _grid.dateAt(cell.row, cell.col);
    return DayCell(
      key: dayCellKey(day),
      day: day,
      inMonth: _grid.contains(day),
      isSelected: cell.isSelected,
      isToday: day == _today,
      hasTasks: _tasksByDay.containsKey(day),
      collapse: _collapse,
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
    return Scaffold(
      backgroundColor: WorkspacePalette.background,
      appBar: AppBar(
        backgroundColor: WorkspacePalette.appBar,
        foregroundColor: WorkspacePalette.surface,
        surfaceTintColor: Colors.transparent,
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
            onPressed: () {
              _showUnavailable("Adding items is not available yet.");
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: "More",
            onPressed: () {
              _showUnavailable("More options are not available yet.");
            },
          ),
        ],
      ),
      floatingActionButton: _view == _WorkspaceView.calendar
          ? FloatingActionButton(
              tooltip: "Add task",
              backgroundColor: WorkspacePalette.accent,
              foregroundColor: WorkspacePalette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              onPressed: () {
                _showUnavailable("Adding tasks is not available yet.");
              },
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

  Widget _buildCalendarView() {
    final tasks = _tasksByDay[_selected] ?? const <CalendarTask>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 0.0),
          child: _buildCalendarCard(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 12.0),
          child: _DayHeader(
            title: dayTitle(_selected, _today),
            count: tasks.length,
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleListScroll,
            // Keyed by day, so another day's list starts at its top.
            child: _TaskList(
              key: ValueKey<DateTime>(_selected),
              tasks: tasks,
              onMore: () {
                _showUnavailable("Task actions are not available yet.");
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
      // the task list uses.
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
        color: WorkspacePalette.surface,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _CalendarHeader(
              title: "${monthNames[_selected.month - 1]} ${_selected.year}",
              mode: _showsWeek ? _CalendarMode.week : _CalendarMode.month,
              onPrevious: () {
                _step(-1);
              },
              onNext: () {
                _step(1);
              },
              onModeSelected: _setMode,
            ),
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
            color: WorkspacePalette.border,
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
                  ? WorkspacePalette.segmentSelected
                  : WorkspacePalette.surface,
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
                          ? WorkspacePalette.segmentSelectedText
                          : WorkspacePalette.textSecondary,
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
        border: Border.all(color: WorkspacePalette.border),
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
    required this.onPrevious,
    required this.onNext,
    required this.onModeSelected,
  });

  final String title;

  /// The view showing, which names the step the chevrons take.
  final _CalendarMode mode;

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<_CalendarMode> onModeSelected;

  static const TextStyle _titleStyle = TextStyle(
    fontSize: 20.0,
    fontWeight: FontWeight.w600,
    color: WorkspacePalette.textPrimary,
  );

  @override
  Widget build(BuildContext context) {
    final unit = mode == _CalendarMode.week ? "week" : "month";
    return Row(
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: "Previous $unit",
                color: WorkspacePalette.textPrimary,
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
                color: WorkspacePalette.textPrimary,
                visualDensity: VisualDensity.compact,
                onPressed: onNext,
              ),
            ],
          ),
        ),
        PopupMenuButton<_CalendarMode>(
          tooltip: "Calendar view",
          initialValue: mode,
          color: WorkspacePalette.surface,
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
                const Icon(
                  Icons.keyboard_arrow_down,
                  color: WorkspacePalette.textPrimary,
                ),
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
                    color: WorkspacePalette.textPrimary,
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
  final int count;

  @override
  Widget build(BuildContext context) {
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
              color: WorkspacePalette.textPrimary,
            ),
          ),
        ),
        Text(
          taskCountLabel(count),
          style: const TextStyle(
            fontSize: 15.0,
            fontWeight: FontWeight.w600,
            color: WorkspacePalette.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({super.key, required this.tasks, required this.onMore});

  final List<CalendarTask> tasks;
  final VoidCallback onMore;

  /// Room under the last card for the floating action button.
  static const EdgeInsets _padding = EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 88.0);

  @override
  Widget build(BuildContext context) {
    // Always scrollable, so a drag on a short list still reports the
    // overscroll the collapse listens for.
    const physics = AlwaysScrollableScrollPhysics();
    if (tasks.isEmpty) {
      return ListView(
        physics: physics,
        padding: _padding,
        children: const <Widget>[
          Padding(
            padding: EdgeInsets.only(top: 32.0),
            child: Text(
              "No tasks on this day.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.0,
                color: WorkspacePalette.textMuted,
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: physics,
      padding: _padding,
      itemCount: tasks.length,
      separatorBuilder: (context, index) {
        return const SizedBox(height: 12.0);
      },
      itemBuilder: (context, index) {
        return TaskCard(task: tasks[index], onMore: onMore);
      },
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
          color: WorkspacePalette.textSecondary,
        ),
      ),
    );
  }
}
