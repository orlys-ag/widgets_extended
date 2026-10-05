/// The calendar's Week mode: one Monday-to-Sunday week as a timed grid on
/// the board, with a frozen day header and hour gutter, one row per
/// 15-minute slot, and the week's items as blocks that move, resize and
/// share their day by the board's own lanes.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_data.dart';
import 'calendar_item.dart';
import 'calendar_model.dart';
import 'calendar_schema.dart';
import 'harbor_theme.dart';

const double _headerHeight = 40.0;
const double _slotHeight = 16.0;
const double _gutterWidth = 56.0;
const double _minDayWidth = 44.0;

/// The row of 08:00, which the grid opens scrolled to.
const int _openingRow = 1 + 8 * 60 ~/ minutesPerSlot;

/// The style the grid animates its blocks with: the board's default.
const BoardAnimationStyle weekGridAnimationStyle = BoardAnimationStyle();

/// The key of the day header cell showing [day].
ValueKey<String> weekDayHeaderKey(DateTime day) {
  return ValueKey<String>("week-day-${isoDate(day)}");
}

/// The key of the block showing the item [id].
ValueKey<String> blockKey(String id) {
  return ValueKey<String>("block-$id");
}

/// The slots a create gesture picked: [dayCount] days from [day], each
/// from [startMinute] to [endMinute].
@immutable
class CreateRange {
  const CreateRange({
    required this.day,
    required this.startMinute,
    required this.endMinute,
    required this.dayCount,
  });

  final DateTime day;
  final int startMinute;
  final int endMinute;
  final int dayCount;

  @override
  bool operator ==(Object other) {
    return other is CreateRange &&
        other.day == day &&
        other.startMinute == startMinute &&
        other.endMinute == endMinute &&
        other.dayCount == dayCount;
  }

  @override
  int get hashCode {
    return Object.hash(day, startMinute, endMinute, dayCount);
  }

  @override
  String toString() {
    return "CreateRange(${isoDate(day)}, ${clockLabel(startMinute)}-"
        "${clockLabel(endMinute)}, $dayCount days)";
  }
}

/// Where [shape] sits in the week whose Monday is the [dayNumber]
/// [weekStartDay], in track space: row 0 is the header and column 0 the
/// gutter, so a slot's row and a day's column count from 1. Days outside
/// the week are clipped off; null when no day of the item lies in it.
BoardSpan? weekSpanOf(ItemShape shape, int weekStartDay) {
  final offset = shape.firstDay - weekStartDay;
  final firstColumn = math.max(0, offset);
  final colSpan = math.min(7, offset + shape.dayCount) - firstColumn;
  if (colSpan <= 0) {
    return null;
  }
  return BoardSpan(
    rowStart: 1 + shape.start ~/ minutesPerSlot,
    rowSpan: (shape.end - shape.start) ~/ minutesPerSlot,
    colStart: 1 + firstColumn,
    colSpan: colSpan,
  );
}

/// [shape] after a drag took its block from [from] to [to], both track
/// space, in the week whose Monday is the [dayNumber] [weekStartDay]. Its
/// times are read from [to]'s rows.
///
/// A drop that keeps the column count moves the first day by the change
/// in the columns and keeps the day count, so the days a clipped item has
/// outside the week keep their distance. A drop that changes the column
/// count is a resize of the trailing column edge, the only column edge
/// the grid resizes, which keeps the start: the item keeps its first day
/// and ends on the day of [to]'s last column, whatever the week clipped
/// of it.
ItemShape shapeFromSpan(
  ItemShape shape,
  BoardSpan from,
  BoardSpan to,
  int weekStartDay,
) {
  final start = (to.rowStart - 1) * minutesPerSlot;
  final end = start + to.rowSpan * minutesPerSlot;
  if (to.colSpan == from.colSpan) {
    return (
      type: shape.type,
      firstDay: shape.firstDay + (to.colStart - from.colStart),
      dayCount: shape.dayCount,
      start: start,
      end: end,
    );
  }
  return (
    type: shape.type,
    firstDay: shape.firstDay,
    dayCount: weekStartDay + to.colStart + to.colSpan - 1 - shape.firstDay,
    start: start,
    end: end,
  );
}

/// [item] with the day, minutes and day count [shapeFromSpan] gives for
/// its shape.
CalendarItem itemFromSpan(
  CalendarItem item,
  BoardSpan from,
  BoardSpan to,
  int weekStartDay,
) {
  final shape = shapeFromSpan(item.shape, from, to, weekStartDay);
  return item.copyWith(
    day: dateOfDayNumber(shape.firstDay),
    dayCount: shape.dayCount,
    startMinute: shape.start,
    endMinute: shape.end,
  );
}

/// The week from [weekStart] on the board, showing what [model] shows for
/// it. A tap on a block that is not pending reports [onOpenItem]; a tap
/// on a day header reports [onSelectDay].
///
/// Items keep every board gesture: a long press moves, the bottom band
/// drags the end time, the right band the day count. Empty body cells
/// take a create gesture, reported through [onCreate]: a tap picks one
/// hour from its slot, or up to 24:00; a drag picks the rectangle of
/// slots it covers, at once for a mouse or a stylus and after a press and
/// hold on touch, so a touch drag without one scrolls the week.
class WeekGrid extends StatefulWidget {
  const WeekGrid({
    super.key,
    required this.model,
    required this.weekStart,
    required this.selectedDay,
    required this.today,
    required this.onSelectDay,
    required this.onOpenItem,
    required this.onCreate,
  });

  final CalendarModel model;

  /// The Monday the grid shows the week of.
  final DateTime weekStart;

  final DateTime selectedDay;
  final DateTime today;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<String> onOpenItem;

  /// Reports the slots a create gesture on empty cells picked.
  final ValueChanged<CreateRange> onCreate;

  @override
  State<WeekGrid> createState() {
    return _WeekGridState();
  }
}

typedef _HeaderState = ({DateTime weekStart, DateTime selectedDay});

class _WeekGridState extends State<WeekGrid> with TickerProviderStateMixin {
  late final BoardController<String, ShownItem> _board;

  /// Held in fields because `Board` replaces its delegate, and so rebuilds
  /// every cell and item, whenever a builder it gets is not identical to
  /// the previous one.
  late final BoardCellBuilder<String, ShownItem> _cellBuilder = _buildCell;
  late final BoardItemBuilder<String, ShownItem> _itemBuilder = _buildItem;

  /// One instance, so a rebuild of this state hands the board the config
  /// it already has.
  late final BoardDragConfig<String> _dragConfig = BoardDragConfig<String>(
    canDrag: _canDrag,
    canDropAt: _canDropAt,
    onItemMoved: _commit,
    onItemResized: _commit,
    resizeEdges: BoardResizeEdges.trailing,
    primaryResizeEdges: BoardResizeEdges.trailing,
    draggedItemOpacity: harborDraggedItemOpacity,
  );

  /// What the header cells show. The cell builder runs only when the board
  /// rebuilds a cell, so the header cells listen to this instead.
  late final ValueNotifier<_HeaderState> _header = ValueNotifier<_HeaderState>((
    weekStart: widget.weekStart,
    selectedDay: widget.selectedDay,
  ));

  double _dayWidth = _minDayWidth;

  final GlobalKey _boardKey = GlobalKey();

  /// The board's viewport, found under [_boardKey] and kept while it is
  /// attached.
  RenderBoardViewport<String>? _viewport;

  /// The create gestures. They live here rather than in the board, and are
  /// armed only for a press on an empty body cell, so a press on an item
  /// leaves the arena to the item's own move and resize gestures.
  late final TapGestureRecognizer _tap;
  late final ImmediateMultiDragGestureRecognizer _immediateRange;
  late final DelayedMultiDragGestureRecognizer _delayedRange;

  /// The range being dragged, which the background paints.
  _RangeDrag? _range;

  /// Set when the grid's scroll ends and cleared by the next microtask. A
  /// touch down on a flinging grid ends the fling before the listener
  /// above the board sees that down, in the same dispatch, so the press
  /// that stopped the grid finds this set.
  bool _scrollJustStopped = false;

  /// The week the last [_sync] placed, and whether it was ready then.
  DateTime? _syncedWeek;
  bool _syncedReady = false;

  /// Whether a frame callback will put [weekGridAnimationStyle] back.
  bool _restoreScheduled = false;

  @override
  void initState() {
    super.initState();
    _tap = TapGestureRecognizer(debugOwner: this)..onTapUp = _handleTapUp;
    // Each pointer kind goes to one range recognizer. A precise pointer
    // starts a range once it passes its hit slop, before the scrollable's
    // pan reaches its own, and the pan never takes a mouse. Touch starts
    // one only after a hold: the delayed recognizer rejects a pointer that
    // moves first, leaving the drag to the scrollable.
    _immediateRange = ImmediateMultiDragGestureRecognizer(
      debugOwner: this,
      supportedDevices: const <PointerDeviceKind>{
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
      },
    )..onStart = _beginRange;
    _delayedRange = DelayedMultiDragGestureRecognizer(
      debugOwner: this,
      supportedDevices: const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.unknown,
      },
    )..onStart = _beginRange;
    _board = BoardController<String, ShownItem>(
      vsync: this,
      rows: _rowsConfig(),
      columns: _columnsConfig(_dayWidth),
      keyOf: (entry) {
        return entry.id;
      },
      animationStyle: weekGridAnimationStyle,
    );
    widget.model.addListener(_handleModel);
    _sync();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _board.jumpToCell(_openingRow, 1);
      }
    });
  }

  @override
  void didUpdateWidget(WeekGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final modelChanged = widget.model != oldWidget.model;
    if (modelChanged) {
      oldWidget.model.removeListener(_handleModel);
      widget.model.addListener(_handleModel);
    }
    _header.value = (
      weekStart: widget.weekStart,
      selectedDay: widget.selectedDay,
    );
    if (modelChanged || widget.weekStart != oldWidget.weekStart) {
      _sync();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = MediaQuery.maybeGestureSettingsOf(context);
    _tap.gestureSettings = settings;
    _immediateRange.gestureSettings = settings;
    _delayedRange.gestureSettings = settings;
  }

  @override
  void dispose() {
    _tap.dispose();
    _immediateRange.dispose();
    _delayedRange.dispose();
    widget.model.removeListener(_handleModel);
    _header.dispose();
    // The board has unmounted by now, so nothing still listens to the
    // controller.
    _board.dispose();
    super.dispose();
  }

  /// Row 0 is the frozen day header; rows 1 onward are one slot each.
  BoardAxisConfig _rowsConfig() {
    return BoardAxisConfig(
      axis: ExplicitAxis(<double>[
        _headerHeight,
        ...List<double>.filled(minutesPerDay ~/ minutesPerSlot, _slotHeight),
      ]),
      frozenStart: 1,
    );
  }

  /// Column 0 is the frozen hour gutter; columns 1 to 7 are Monday to
  /// Sunday. The `laneExtent` makes the day axis the lane axis, so items
  /// sharing a day's time sit side by side.
  BoardAxisConfig _columnsConfig(double dayWidth) {
    return BoardAxisConfig(
      axis: ExplicitAxis(<double>[
        _gutterWidth,
        ...List<double>.filled(7, dayWidth),
      ]),
      frozenStart: 1,
      laneExtent: dayWidth,
    );
  }

  /// Seven days across [width], never narrower than the minimum. Called
  /// from the layout callback, so the first frame lays the board out at
  /// its width.
  void _fitColumns(double width) {
    final dayWidth = math.max(_minDayWidth, (width - _gutterWidth) / 7);
    if (dayWidth == _dayWidth) {
      return;
    }
    _dayWidth = dayWidth;
    _board.columns = _columnsConfig(dayWidth);
  }

  void _handleModel() {
    _sync();
    setState(() {});
  }

  /// Whether the model shows exactly this grid's week, every day of it
  /// read. False for a sync that runs between the model taking a new week
  /// and this grid getting it.
  bool get _weekReady {
    final weekStart = widget.weekStart;
    return widget.model.status == CalendarLoadStatus.ready &&
        widget.model.isShown(weekStart, addDays(weekStart, 6));
  }

  /// Sets the board's items to the week's shown items when the week is
  /// ready, and to none otherwise. Only a sync that follows one showing the
  /// same week ready animates; any other runs under
  /// [BoardAnimationStyle.disabled], and so does every sync until a frame
  /// callback restores [weekGridAnimationStyle].
  void _sync() {
    final weekStart = widget.weekStart;
    final ready = _weekReady;
    final placements = <BoardPlacement<ShownItem>>[];
    if (ready) {
      final weekStartDay = dayNumber(weekStart);
      final shown = widget.model.itemsBetween(weekStart, addDays(weekStart, 6));
      for (final entry in shown) {
        final span = weekSpanOf(entry.item.shape, weekStartDay);
        if (span != null) {
          placements.add(BoardPlacement<ShownItem>(entry, span));
        }
      }
    }
    final animate = ready && _syncedReady && _syncedWeek == weekStart;
    if (!animate) {
      _board.animationStyle = BoardAnimationStyle.disabled;
    }
    _board.setItems(placements);
    if (!animate) {
      _scheduleStyleRestore();
    }
    _syncedWeek = weekStart;
    _syncedReady = ready;
  }

  /// Puts [weekGridAnimationStyle] back in a frame callback scheduled
  /// after the diff of the sync that first disabled it. The style setter
  /// stops slides at once but leaves an enter or exit in flight to its
  /// next tick, which reads the style then, and transient callbacks run in
  /// the order they were scheduled. A ticker running before that sync
  /// scheduled its tick already, and one its diff stopped and started
  /// again, which removing an item mid-enter does, scheduled its tick
  /// inside the diff, so each of those ticks runs before the restore and
  /// settles its enters and exits under the disabled style.
  void _scheduleStyleRestore() {
    if (_restoreScheduled) {
      return;
    }
    _restoreScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _restoreScheduled = false;
      if (mounted) {
        _board.animationStyle = weekGridAnimationStyle;
      }
    });
  }

  bool _canDrag(String id) {
    return !widget.model.isLocked(id);
  }

  bool _canDropAt(String id, BoardSpan span) {
    if (span.rowStart < 1 || span.colStart < 1) {
      return false;
    }
    final from = _board.spanOf(id);
    final entry = _board.itemOf(id);
    if (from == null || entry == null) {
      return false;
    }
    // The span the drag started from: an unchanged drop is admitted even
    // where the item already shares its time.
    if (from == span) {
      return true;
    }
    final shape = entry.item.shape;
    final weekStartDay = dayNumber(widget.weekStart);
    final converted = shapeFromSpan(shape, from, span, weekStartDay);
    if (!isAllowedDayCount(converted.dayCount)) {
      return false;
    }
    // The converted shape's own week span, not the candidate's: an item
    // clipped at the week's start shows more days once moved right.
    final weekSpan = weekSpanOf(converted, weekStartDay);
    if (weekSpan == null) {
      return false;
    }
    final others = _board.itemsIn(
      weekSpan.rowStart,
      weekSpan.rowStart + weekSpan.rowSpan,
      weekSpan.colStart,
      weekSpan.colStart + weekSpan.colSpan,
    );
    for (final other in others) {
      if (other == id) {
        continue;
      }
      final occupant = _board.itemOf(other);
      if (occupant != null && itemsConflict(converted, occupant.item.shape)) {
        return false;
      }
    }
    return true;
  }

  /// A drop the board reports, a move or a resize. Sends nothing for a
  /// locked item, which the board's semantics move action can report when
  /// the item locked after its host last built, or when the item would
  /// not change.
  void _commit(String id, BoardSpan to) {
    if (widget.model.isLocked(id)) {
      return;
    }
    final from = _board.spanOf(id);
    final stored = widget.model.storedItem(id);
    if (from == null || stored == null) {
      return;
    }
    final requested = itemFromSpan(
      stored,
      from,
      to,
      dayNumber(widget.weekStart),
    );
    if (requested == stored) {
      return;
    }
    widget.model.requestMove(requested);
  }

  void _selectDay(DateTime day) {
    widget.onSelectDay(day);
  }

  RenderBoardViewport<String>? _findViewport() {
    final cached = _viewport;
    if (cached != null && cached.attached) {
      return cached;
    }
    _viewport = null;
    final root = _boardKey.currentContext?.findRenderObject();
    if (root == null) {
      return null;
    }
    RenderBoardViewport<String>? found;
    void visit(RenderObject node) {
      if (found != null) {
        return;
      }
      if (node is RenderBoardViewport<String>) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    visit(root);
    _viewport = found;
    return found;
  }

  /// The body cell painting under [global], or null over the header, the
  /// gutter or past the lattice.
  ({int row, int col})? _bodyCellAt(Offset global) {
    final viewport = _findViewport();
    if (viewport == null) {
      return null;
    }
    final cell = viewport.cellAt(viewport.globalToLocal(global));
    if (cell == null || cell.row < 1 || cell.col < 1) {
      return null;
    }
    return cell;
  }

  /// Whether a press at [global] may create: it lies over a body cell, no
  /// item paints under it, and the grid is neither scrolling nor just
  /// stopped by this press.
  bool _admits(Offset global) {
    final viewport = _findViewport();
    if (viewport == null || _scrollJustStopped) {
      return false;
    }
    final vertical = viewport.verticalPosition;
    final horizontal = viewport.horizontalPosition;
    if ((vertical?.isScrollingNotifier.value ?? false) ||
        (horizontal?.isScrollingNotifier.value ?? false)) {
      return false;
    }
    final local = viewport.globalToLocal(global);
    final cell = viewport.cellAt(local);
    if (cell == null || cell.row < 1 || cell.col < 1) {
      return false;
    }
    return viewport.itemAt(local) == null;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      _scrollJustStopped = true;
      scheduleMicrotask(() {
        _scrollJustStopped = false;
      });
    }
    return false;
  }

  /// Arms the create gestures for an admitted press. A listener's pointer
  /// down runs before the arena closes, so they join it beside the
  /// scrollable's pan; each recognizer ignores the pointer kinds it does
  /// not support.
  void _handlePointerDown(PointerDownEvent event) {
    if (!_admits(event.position)) {
      return;
    }
    _tap.addPointer(event);
    _immediateRange.addPointer(event);
    _delayedRange.addPointer(event);
  }

  void _handleTapUp(TapUpDetails details) {
    final cell = _bodyCellAt(details.globalPosition);
    if (cell == null) {
      return;
    }
    widget.onCreate(_tapRangeOf(cell));
  }

  /// One hour from [cell]'s slot, or to 24:00 when that comes first.
  CreateRange _tapRangeOf(({int row, int col}) cell) {
    final start = (cell.row - 1) * minutesPerSlot;
    return CreateRange(
      day: addDays(widget.weekStart, cell.col - 1),
      startMinute: start,
      endMinute: math.min(start + 60, minutesPerDay),
      dayCount: 1,
    );
  }

  /// The slots of the rectangle from [anchor] to [focus].
  CreateRange _rectRangeOf(
    ({int row, int col}) anchor,
    ({int row, int col}) focus,
  ) {
    final top = math.min(anchor.row, focus.row);
    final bottom = math.max(anchor.row, focus.row);
    final left = math.min(anchor.col, focus.col);
    final right = math.max(anchor.col, focus.col);
    return CreateRange(
      day: addDays(widget.weekStart, left - 1),
      startMinute: (top - 1) * minutesPerSlot,
      endMinute: bottom * minutesPerSlot,
      dayCount: right - left + 1,
    );
  }

  Drag? _beginRange(Offset position) {
    final anchor = _bodyCellAt(position);
    if (anchor == null) {
      return null;
    }
    final range = _RangeDrag(this, anchor, position);
    setState(() {
      _range = range;
    });
    return range;
  }

  void _moveRange(_RangeDrag range, ({int row, int col}) focus) {
    if (!mounted || !identical(_range, range)) {
      return;
    }
    setState(() {
      range.focus = focus;
    });
  }

  void _endRange(_RangeDrag range) {
    if (!mounted || !identical(_range, range)) {
      return;
    }
    final created = range.focus == range.anchor
        ? _tapRangeOf(range.anchor)
        : _rectRangeOf(range.anchor, range.focus);
    _clearRange(range);
    widget.onCreate(created);
  }

  void _clearRange(_RangeDrag range) {
    if (!mounted || !identical(_range, range)) {
      return;
    }
    setState(() {
      _range = null;
    });
  }

  Widget? _buildCell(
    BuildContext context,
    BoardCellView<String, ShownItem> cell,
  ) {
    if (cell.row == 0) {
      if (cell.col == 0) {
        return const ColoredBox(color: HarborColors.surface);
      }
      return _DayHeaderCell(
        header: _header,
        column: cell.col - 1,
        today: widget.today,
        onSelectDay: _selectDay,
      );
    }
    if (cell.col == 0) {
      // Every gutter row is opaque so nothing scrolled beneath the band
      // shows through; the label sits on the hour line.
      final minute = (cell.row - 1) * minutesPerSlot;
      final onHour = minute % 60 == 0 && minute > 0;
      return ColoredBox(
        color: HarborColors.surface,
        child: onHour
            ? Align(
                alignment: Alignment.topRight,
                child: Transform.translate(
                  offset: const Offset(-6.0, -7.0),
                  child: Text(
                    clockLabel(minute),
                    style: const TextStyle(
                      fontSize: 11.0,
                      color: HarborColors.textSecondary,
                    ),
                  ),
                ),
              )
            : null,
      );
    }
    // Body cells build nothing: the background painter draws the grid.
    return null;
  }

  Widget _buildItem(
    BuildContext context,
    BoardItemView<String, ShownItem> view,
  ) {
    final entry = view.item;
    return _Block(
      key: blockKey(entry.id),
      entry: entry,
      showsSummary: view.span.rowSpan >= 3,
      onOpen: entry.pending
          ? null
          : () {
              widget.onOpenItem(entry.id);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final range = _range;
    final board = Listener(
      onPointerDown: _handlePointerDown,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: Board<String, ShownItem>(
          key: _boardKey,
          controller: _board,
          cellBuilder: _cellBuilder,
          itemBuilder: _itemBuilder,
          background: _WeekGridPainter(
            weekStart: widget.weekStart,
            today: widget.today,
            rangeAnchor: range?.anchor,
            rangeFocus: range?.focus,
          ),
          drag: _dragConfig,
          // The week scrolls on its own, not with the screen's primary
          // scroll controller.
          primary: false,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        _fitColumns(constraints.maxWidth);
        return Stack(
          children: <Widget>[
            Positioned.fill(child: board),
            if (!_weekReady)
              Positioned.fill(
                child: _LoadOverlay(
                  error: model.status == CalendarLoadStatus.failed
                      ? model.error
                      : null,
                  onRetry: model.retry,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A create range from the press at [anchor] to the body cell under the
/// pointer. The pointer is tracked by delta: a multi-drag recognizer
/// reports the move that accepted it as a delta from the press, with the
/// press's own position.
class _RangeDrag extends Drag {
  _RangeDrag(this._grid, this.anchor, this._position) : focus = anchor;

  final _WeekGridState _grid;
  final ({int row, int col}) anchor;

  /// The body cell last under the pointer: unchanged while the pointer is
  /// over the header, the gutter or past the lattice.
  ({int row, int col}) focus;

  Offset _position;

  @override
  void update(DragUpdateDetails details) {
    _position += details.delta;
    final cell = _grid._bodyCellAt(_position);
    if (cell == null || cell == focus) {
      return;
    }
    _grid._moveRange(this, cell);
  }

  @override
  void end(DragEndDetails details) {
    _grid._endRange(this);
  }

  @override
  void cancel() {
    _grid._clearRange(this);
  }
}

class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({
    required this.header,
    required this.column,
    required this.today,
    required this.onSelectDay,
  });

  final ValueListenable<_HeaderState> header;
  final int column;
  final DateTime today;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_HeaderState>(
      valueListenable: header,
      builder: (context, value, child) {
        final day = addDays(value.weekStart, column);
        final isToday = day == today;
        final isSelected = day == value.selectedDay;
        return GestureDetector(
          key: weekDayHeaderKey(day),
          onTap: () {
            onSelectDay(day);
          },
          child: ColoredBox(
            color: isSelected ? HarborColors.primaryTint : HarborColors.surface,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    weekdayShortNames[weekdayColumn(day)],
                    style: const TextStyle(
                      fontSize: 11.0,
                      color: HarborColors.textSecondary,
                    ),
                  ),
                  Text(
                    "${day.day}",
                    style: TextStyle(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w700,
                      color: isToday ? HarborColors.primary : HarborColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One item on the grid: its type's tint with a 4 px edge, its title, and
/// its first summary when [showsSummary]. Dimmed with a progress indicator
/// while [ShownItem.pending].
class _Block extends StatelessWidget {
  const _Block({
    super.key,
    required this.entry,
    required this.showsSummary,
    required this.onOpen,
  });

  final ShownItem entry;

  /// Whether the block's span covers enough rows for a second line. Read
  /// from the span rather than measured, so a block laid out at a new
  /// extent on each animation frame does not rebuild for it.
  final bool showsSummary;

  /// Null while the item is pending, so a tap opens nothing.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final style = harborTypeStyleOf(item.type);
    final schema = schemaOf(item.type);
    String? summary;
    if (showsSummary && schema.summaryKeys.isNotEmpty) {
      final key = schema.summaryKeys.first;
      summary = schema.fieldOf(key)?.summaryOf(item.fields[key]);
    }
    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: style.tint,
        border: Border(left: BorderSide(color: style.edge, width: 4.0)),
      ),
      // Laid out at its natural height and clipped to the block, so a
      // block shorter than its text does not overflow.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minHeight: 0.0,
          maxHeight: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4.0, 2.0, 4.0, 2.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.0,
                    fontWeight: FontWeight.w600,
                    color: HarborColors.text,
                  ),
                ),
                if (summary != null)
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.0,
                      color: HarborColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (entry.pending) {
      content = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          Opacity(opacity: 0.5, child: content),
          const Positioned(
            top: 2.0,
            right: 2.0,
            child: SizedBox.square(
              dimension: 12.0,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(1.0),
      child: GestureDetector(onTap: onOpen, child: content),
    );
  }
}

/// Covers the grid while its week is not ready, taking every press: a
/// progress indicator while it loads, the error and Retry when the read
/// failed.
class _LoadOverlay extends StatelessWidget {
  const _LoadOverlay({required this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error;
    // A ColoredBox hit-tests as opaque, so no press reaches the board.
    return ColoredBox(
      color: HarborColors.background.withValues(alpha: 0.85),
      child: Center(
        child: message == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: HarborColors.error),
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  TextButton(onPressed: onRetry, child: const Text("Retry")),
                ],
              ),
      ),
    );
  }
}

/// The grid behind the cells, drawn for the visible body tracks alone:
/// the body, the weekend and today's columns, a line at the top of each
/// slot row and at the left of each day column, and the create range being
/// dragged. Every paint it draws with is built once.
class _WeekGridPainter extends BoardBackgroundPainter {
  const _WeekGridPainter({
    required this.weekStart,
    required this.today,
    required this.rangeAnchor,
    required this.rangeFocus,
  });

  static final Paint _surfacePaint = Paint()..color = HarborColors.surface;
  static final Paint _backgroundPaint = Paint()
    ..color = HarborColors.background;
  static final Paint _tintPaint = Paint()..color = HarborColors.primaryTint;
  static final Paint _linePaint = Paint()
    ..color = HarborColors.outline
    ..strokeWidth = 1.0;

  final DateTime weekStart;
  final DateTime today;
  final ({int row, int col})? rangeAnchor;
  final ({int row, int col})? rangeFocus;

  @override
  void paint(Canvas canvas, BoardGeometryView geometry) {
    final firstRow = geometry.firstVisibleRow;
    final lastRow = geometry.lastVisibleRow;
    final firstCol = geometry.firstVisibleCol;
    final lastCol = geometry.lastVisibleCol;
    if (firstRow > lastRow || firstCol > lastCol) {
      return;
    }
    final region = geometry.scrolledRegion;
    final first = geometry.visibleCellRect(firstRow, firstCol);
    final last = geometry.visibleCellRect(lastRow, lastCol);
    canvas.save();
    canvas.clipRect(region);
    canvas.drawRect(region, _surfacePaint);
    final todayColumn = 1 + daysBetween(weekStart, today);
    for (var col = firstCol; col <= lastCol; col++) {
      final Paint fill;
      if (col == todayColumn) {
        fill = _tintPaint;
      } else if (col >= 6) {
        fill = _backgroundPaint;
      } else {
        continue;
      }
      final rect = geometry.visibleCellRect(firstRow, col);
      canvas.drawRect(
        Rect.fromLTRB(rect.left, first.top, rect.right, last.bottom),
        fill,
      );
    }
    final anchor = rangeAnchor;
    final focus = rangeFocus;
    if (anchor != null && focus != null) {
      final top = math.max(math.min(anchor.row, focus.row), firstRow);
      final bottom = math.min(math.max(anchor.row, focus.row), lastRow);
      final left = math.max(math.min(anchor.col, focus.col), firstCol);
      final right = math.min(math.max(anchor.col, focus.col), lastCol);
      if (top <= bottom && left <= right) {
        canvas.drawRect(
          geometry
              .visibleCellRect(top, left)
              .expandToInclude(geometry.visibleCellRect(bottom, right)),
          _tintPaint,
        );
      }
    }
    for (var row = firstRow; row <= lastRow; row++) {
      final y = geometry.visibleCellRect(row, firstCol).top;
      canvas.drawLine(Offset(first.left, y), Offset(last.right, y), _linePaint);
    }
    for (var col = firstCol; col <= lastCol; col++) {
      final x = geometry.visibleCellRect(firstRow, col).left;
      canvas.drawLine(Offset(x, first.top), Offset(x, last.bottom), _linePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WeekGridPainter old) {
    return old.weekStart != weekStart ||
        old.today != today ||
        old.rangeAnchor != rangeAnchor ||
        old.rangeFocus != rangeFocus;
  }
}
