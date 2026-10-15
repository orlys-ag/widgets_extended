/// The calendar's timed grid: consecutive days on the board, with a frozen
/// day header and hour gutter, one row per 15-minute slot, and the days'
/// items as blocks that move and resize.
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
import 'calendar_settings.dart';
import 'harbor_theme.dart';

const double _headerHeight = 40.0;
const double _gutterWidth = 56.0;

/// The time the grid opens scrolled to, where its hours hold it.
const int _openingMinute = 8 * 60;

/// The minute the grid opens scrolled to: [_openingMinute], or the nearer
/// end of [hours] when they do not hold it.
int _openingMinuteIn(DayHours hours) {
  return _openingMinute.clamp(hours.start, hours.end - minutesPerSlot);
}

/// The style the grid animates its blocks with: the board's default.
const BoardAnimationStyle timedGridAnimationStyle = BoardAnimationStyle();

/// The key of the day header cell showing [day].
ValueKey<String> dayHeaderKey(DateTime day) {
  return ValueKey<String>("grid-day-${isoDate(day)}");
}

/// The key of the block showing the item [id].
ValueKey<String> blockKey(String id) {
  return ValueKey<String>("block-$id");
}

/// The key of the corner's count of the shown items the grid has no block
/// for.
const ValueKey<String> hiddenCountKey = ValueKey<String>("grid-hidden-count");

/// What the corner's count of [count] items with no block says.
String hiddenItemsLabel(int count) {
  if (count == 1) {
    return "1 item is outside the days or hours shown";
  }
  return "$count items are outside the days or hours shown";
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

/// Which day each column of a timed grid shows and which minute each of
/// its rows starts at.
///
/// Row 0 is the day header and column 0 the hour gutter. The rows below
/// the header are the slots of [hours], one per [minutesPerSlot]; the
/// columns right of the gutter are the days of the [dayCount] days from
/// [firstDay] whose weekday [weekdays] holds, in order, so a day it does
/// not hold has no column and the days either side of it are adjacent.
@immutable
class GridTracks {
  GridTracks({
    required this.firstDay,
    required this.dayCount,
    this.weekdays = WeekdaySet.all,
    this.hours = DayHours.allDay,
  }) : assert(dayCount >= 1),
       _days = List<int>.unmodifiable(<int>[
         for (var day = firstDay; day < firstDay + dayCount; day++)
           if (weekdays.containsDay(day)) day,
       ]);

  /// The [dayNumber] of the range's first day, shown or not.
  final int firstDay;

  /// The days in the range, shown or not.
  final int dayCount;

  final WeekdaySet weekdays;
  final DayHours hours;

  /// The [dayNumber]s of the shown days, ascending: column `c` shows
  /// `_days[c - 1]`.
  final List<int> _days;

  /// The [dayNumber] of the range's last day, shown or not.
  int get lastDay {
    return firstDay + dayCount - 1;
  }

  /// The day columns, the gutter not counted.
  int get columnCount {
    return _days.length;
  }

  /// The slot rows, the header not counted.
  int get rowCount {
    return hours.slotCount;
  }

  /// The [dayNumber] of the day [column] shows, 1 to [columnCount].
  int dayAt(int column) {
    assert(column >= 1 && column <= columnCount);
    return _days[column - 1];
  }

  /// The local midnight of the day [column] shows.
  DateTime dateAt(int column) {
    return dateOfDayNumber(dayAt(column));
  }

  /// The column showing the [dayNumber] [day], or null when none does.
  int? columnOf(int day) {
    final column = firstColumnFrom(day);
    if (column <= columnCount && dayAt(column) == day) {
      return column;
    }
    return null;
  }

  /// The first column showing [day] or a later day, or one past the last
  /// column when none does.
  int firstColumnFrom(int day) {
    return 1 + _firstIndexAtLeast(day);
  }

  /// The last column showing [day] or an earlier day, or 0 when none does.
  int lastColumnUpTo(int day) {
    return _firstIndexAtLeast(day + 1);
  }

  /// The index of the first shown day at or after [day], by binary search
  /// over the ascending [_days]; [columnCount] when there is none.
  int _firstIndexAtLeast(int day) {
    var low = 0;
    var high = _days.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_days[middle] < day) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// The minute the slot [row] starts at, for a row from 1 to [rowCount];
  /// the row after the last gives the end of [hours].
  int minuteAt(int row) {
    return hours.start + (row - 1) * minutesPerSlot;
  }

  /// The row of the slot starting at [minute], a slot boundary in
  /// [hours].
  int rowOf(int minute) {
    return 1 + (minute - hours.start) ~/ minutesPerSlot;
  }

  @override
  bool operator ==(Object other) {
    return other is GridTracks &&
        other.firstDay == firstDay &&
        other.dayCount == dayCount &&
        other.weekdays == weekdays &&
        other.hours == hours;
  }

  @override
  int get hashCode {
    return Object.hash(firstDay, dayCount, weekdays, hours);
  }
}

/// Where [shape] sits on the grid [tracks] lays out, in track space. The
/// days of it the grid has no column for and its minutes outside the
/// grid's hours are clipped off; null when no shown day or no minute of it
/// is left.
BoardSpan? gridSpanOf(ItemShape shape, GridTracks tracks) {
  final firstColumn = tracks.firstColumnFrom(shape.firstDay);
  final lastColumn = tracks.lastColumnUpTo(shape.firstDay + shape.dayCount - 1);
  final hours = tracks.hours;
  final start = math.max(shape.start, hours.start);
  final end = math.min(shape.end, hours.end);
  if (lastColumn < firstColumn || end <= start) {
    return null;
  }
  return BoardSpan(
    rowStart: tracks.rowOf(start),
    rowSpan: (end - start) ~/ minutesPerSlot,
    colStart: firstColumn,
    colSpan: lastColumn - firstColumn + 1,
  );
}

/// [shape] after a drag took its block from [from] to [to], both track
/// space, on the grid [tracks] lays out. Its times are read from [to]'s
/// rows, so a shape whose minutes the grid clips has no business here.
///
/// A drop that keeps the column count moves the first day by the days
/// between the two spans' first columns and keeps the day count, so the
/// days a clipped item has outside the grid keep their distance. A drop
/// that changes the column count is a resize of the trailing column edge,
/// the only column edge the grid resizes, which keeps the start: the item
/// keeps its first day and ends on the day of [to]'s last column, whatever
/// the grid clipped of it.
ItemShape shapeFromSpan(
  ItemShape shape,
  BoardSpan from,
  BoardSpan to,
  GridTracks tracks,
) {
  final start = tracks.minuteAt(to.rowStart);
  final end = start + to.rowSpan * minutesPerSlot;
  if (to.colSpan == from.colSpan) {
    final shift = tracks.dayAt(to.colStart) - tracks.dayAt(from.colStart);
    return (
      type: shape.type,
      firstDay: shape.firstDay + shift,
      dayCount: shape.dayCount,
      start: start,
      end: end,
    );
  }
  final lastDay = tracks.dayAt(to.colStart + to.colSpan - 1);
  return (
    type: shape.type,
    firstDay: shape.firstDay,
    dayCount: lastDay - shape.firstDay + 1,
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
  GridTracks tracks,
) {
  final shape = shapeFromSpan(item.shape, from, to, tracks);
  return item.copyWith(
    day: dateOfDayNumber(shape.firstDay),
    dayCount: shape.dayCount,
    startMinute: shape.start,
    endMinute: shape.end,
  );
}

/// What a tap on the body [cell] creates: one hour from its slot, or up to
/// the end of the grid's hours when that comes first.
CreateRange createRangeAt(GridTracks tracks, ({int row, int col}) cell) {
  final start = tracks.minuteAt(cell.row);
  return CreateRange(
    day: tracks.dateAt(cell.col),
    startMinute: start,
    endMinute: math.min(start + 60, tracks.hours.end),
    dayCount: 1,
  );
}

/// What a drag from the body cell [anchor] to [focus] creates: the slots of
/// the rectangle between them, on every day from its left column's to its
/// right column's, shown or not.
CreateRange createRangeOver(
  GridTracks tracks,
  ({int row, int col}) anchor,
  ({int row, int col}) focus,
) {
  final top = math.min(anchor.row, focus.row);
  final bottom = math.max(anchor.row, focus.row);
  final left = math.min(anchor.col, focus.col);
  final right = math.max(anchor.col, focus.col);
  return CreateRange(
    day: tracks.dateAt(left),
    startMinute: tracks.minuteAt(top),
    endMinute: tracks.minuteAt(bottom + 1),
    dayCount: tracks.dayAt(right) - tracks.dayAt(left) + 1,
  );
}

/// The days of the [dayCount] from [firstDay] whose weekday [settings]
/// show, on the board, over the hours they choose, showing what [model]
/// shows for them. A tap on a block that is not pending reports
/// [onOpenItem]; a tap on a day header reports [onSelectDay].
///
/// Items keep every board gesture: a long press moves, the bottom band
/// drags the end time, and, on more than one day, the right band the day
/// count. A move dropped onto another item's time lands at the nearest
/// free time that shows, on that day or the day before or after it, and
/// goes back where there is none; a resize dragged onto one stops at its
/// edge. An item reaching past the hours shows the part inside them, with
/// an arrow where it is cut, and takes no move or resize: its form changes
/// it. An item wholly outside them, or on no shown day, has no block, and
/// the corner over the gutter counts it. Empty body cells take a create
/// gesture, reported through [onCreate]: a tap picks one hour from its
/// slot, or up to the end of the hours; a drag picks the rectangle of
/// slots it covers, at once for a mouse or a stylus and after a press and
/// hold on touch, so a touch drag without one scrolls the grid.
///
/// The day columns and the slot rows stretch to fill the grid, never
/// smaller than the least sizes [settings] choose; past those, it scrolls.
class TimedGrid extends StatefulWidget {
  const TimedGrid({
    super.key,
    required this.model,
    required this.settings,
    required this.firstDay,
    required this.dayCount,
    required this.selectedDay,
    required this.today,
    required this.onSelectDay,
    required this.onOpenItem,
    required this.onCreate,
  }) : assert(dayCount >= 1);

  final CalendarModel model;

  /// The weekdays and the hours the grid shows and the least size of its
  /// cells. At least one day of the range must fall on a shown weekday.
  final CalendarSettings settings;

  /// The first day of the range the grid shows.
  final DateTime firstDay;

  /// How many days the range holds.
  final int dayCount;

  final DateTime selectedDay;
  final DateTime today;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<String> onOpenItem;

  /// Reports the slots a create gesture on empty cells picked.
  final ValueChanged<CreateRange> onCreate;

  @override
  State<TimedGrid> createState() {
    return _TimedGridState();
  }
}

typedef _HeaderState = ({GridTracks tracks, DateTime selectedDay});

class _TimedGridState extends State<TimedGrid> with TickerProviderStateMixin {
  late final BoardController<String, ShownItem> _board;

  /// Where the widget's days and minutes sit on the board.
  late GridTracks _tracks = _tracksOf(widget);

  /// Held in fields because `Board` replaces its delegate, and so rebuilds
  /// every cell and item, whenever a builder it gets is not identical to
  /// the previous one.
  late final BoardCellBuilder<String, ShownItem> _cellBuilder = _buildCell;
  late final BoardItemBuilder<String, ShownItem> _itemBuilder = _buildItem;

  /// One instance, so a rebuild of this state hands the board the config
  /// it already has. A single day column has no right strip: there is no
  /// column to drag its edge onto. Whether the grid has more than one
  /// column is fixed for its life, which [didUpdateWidget] asserts.
  ///
  /// A move [_canDropAt] refuses for meeting another item slides to the
  /// placement nearest on screen that holds it clear, at any time that
  /// shows of the day it was dropped on or of the day before or after it,
  /// however busy the time around it is. A resize it refuses for meeting
  /// another item stops its dragged edge at that item.
  late final BoardDragConfig<String> _dragConfig = BoardDragConfig<String>(
    canDrag: _canDrag,
    canDropAt: _canDropAt,
    dropFit: const BoardDropFit(
      minFreeFraction: 0.0,
      rowRadius: double.infinity,
      colRadius: 1.0,
      clampResizes: true,
    ),
    onItemMoved: _commit,
    onItemResized: _commit,
    resizeEdges: _tracks.columnCount > 1
        ? BoardResizeEdges.trailing
        : BoardResizeEdges.none,
    primaryResizeEdges: BoardResizeEdges.trailing,
    draggedItemOpacity: harborDraggedItemOpacity,
  );

  /// What the header cells show. The cell builder runs only when the board
  /// rebuilds a cell, so the header cells listen to this instead.
  late final ValueNotifier<_HeaderState> _header = ValueNotifier<_HeaderState>((
    tracks: _tracks,
    selectedDay: widget.selectedDay,
  ));

  /// The extents the axes were last given and the tracks they were given
  /// for. [_fitAxes] replaces an axis only when one of these changes.
  late double _dayWidth = widget.settings.minDayWidth;
  late double _slotHeight = widget.settings.minSlotHeight;
  late int _columnCount = _tracks.columnCount;
  late DayHours _rowHours = _tracks.hours;

  /// The size the board was last laid out at; null before the first
  /// layout.
  Size? _size;

  /// How many of the shown items have no block: on a day with no column,
  /// or wholly outside the hours. The corner cell listens to it.
  final ValueNotifier<int> _hiddenCount = ValueNotifier<int>(0);

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

  /// Whether the last [_sync] found its days ready.
  bool _syncedReady = false;

  /// Whether a frame callback will put [timedGridAnimationStyle] back.
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
      columns: _columnsConfig(),
      keyOf: (entry) {
        return entry.id;
      },
      animationStyle: timedGridAnimationStyle,
    );
    widget.model.addListener(_handleModel);
    _sync();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _board.jumpToCell(_tracks.rowOf(_openingMinuteIn(_tracks.hours)), 1);
      }
    });
  }

  @override
  void didUpdateWidget(TimedGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final modelChanged = widget.model != oldWidget.model;
    if (modelChanged) {
      oldWidget.model.removeListener(_handleModel);
      widget.model.addListener(_handleModel);
    }
    final tracks = _tracksOf(widget);
    final tracksChanged = tracks != _tracks;
    assert(
      (tracks.columnCount > 1) == (_tracks.columnCount > 1),
      "A TimedGrid keeps one day column or more than one; give a grid that "
      "changes between them its own key.",
    );
    _tracks = tracks;
    if (tracksChanged || widget.selectedDay != oldWidget.selectedDay) {
      _header.value = (tracks: tracks, selectedDay: widget.selectedDay);
    }
    // The axes first, so the items the sync places fit the lattice they
    // land on.
    final size = _size;
    if (size != null &&
        (tracksChanged || widget.settings != oldWidget.settings)) {
      _fitAxes(size);
    }
    if (modelChanged || tracksChanged) {
      // New days are not ready yet, so they do not animate in either way;
      // new hours move every block at once.
      _sync(animate: !tracksChanged);
    }
  }

  static GridTracks _tracksOf(TimedGrid widget) {
    final tracks = GridTracks(
      firstDay: dayNumber(widget.firstDay),
      dayCount: widget.dayCount,
      weekdays: widget.settings.weekdays,
      hours: widget.settings.hours,
    );
    assert(
      tracks.columnCount > 0,
      "No day of the range is on a shown weekday.",
    );
    return tracks;
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
    _range?.detach();
    widget.model.removeListener(_handleModel);
    _header.dispose();
    _hiddenCount.dispose();
    // The board has unmounted by now, so nothing still listens to the
    // controller.
    _board.dispose();
    super.dispose();
  }

  /// Row 0 is the frozen day header; rows 1 onward are the slots of the
  /// hours, [_slotHeight] each.
  BoardAxisConfig _rowsConfig() {
    return BoardAxisConfig(
      axis: ExplicitAxis(<double>[
        _headerHeight,
        ...List<double>.filled(_tracks.rowCount, _slotHeight),
      ]),
      frozenStart: 1,
    );
  }

  /// Column 0 is the frozen hour gutter; columns 1 onward are the days
  /// [_tracks] shows. The `laneExtent` makes the day axis the
  /// lane axis, so items sharing a day's time sit side by side. No two
  /// stored items do, but a failed move can return an item under another
  /// item's pending move until the API refuses that one.
  BoardAxisConfig _columnsConfig() {
    return BoardAxisConfig(
      axis: ExplicitAxis(<double>[
        _gutterWidth,
        ...List<double>.filled(_tracks.columnCount, _dayWidth),
      ]),
      frozenStart: 1,
      laneExtent: _dayWidth,
    );
  }

  /// The day columns across [size]'s width and the slot rows down its
  /// height, each stretched to fill it and never smaller than the least
  /// size the settings choose. Called from the layout callback, so the
  /// first frame lays the board out at its size, and from
  /// [didUpdateWidget] at the last size, so new tracks reach the board in
  /// the build that places items on them.
  ///
  /// An axis is replaced only when its extent or its tracks change. The
  /// rows are replaced for new hours even at the same count, which also
  /// rebuilds the gutter's labels: the board builds them as cells.
  void _fitAxes(Size size) {
    _size = size;
    final settings = widget.settings;
    final dayWidth = math.max(
      settings.minDayWidth,
      _share(size.width - _gutterWidth, _tracks.columnCount),
    );
    final slotHeight = math.max(
      settings.minSlotHeight,
      _share(size.height - _headerHeight, _tracks.rowCount),
    );
    if (dayWidth != _dayWidth || _tracks.columnCount != _columnCount) {
      _dayWidth = dayWidth;
      _columnCount = _tracks.columnCount;
      _board.columns = _columnsConfig();
    }
    if (slotHeight != _slotHeight || _tracks.hours != _rowHours) {
      _slotHeight = slotHeight;
      _rowHours = _tracks.hours;
      _board.rows = _rowsConfig();
    }
  }

  /// One of [count] equal shares of [extent], or 0 when it is unbounded.
  static double _share(double extent, int count) {
    if (!extent.isFinite) {
      return 0.0;
    }
    return extent / count;
  }

  void _handleModel() {
    _sync();
    setState(() {});
  }

  DateTime get _lastDay {
    return dateOfDayNumber(_tracks.lastDay);
  }

  /// Whether the model shows exactly this grid's days, every one of them
  /// read. False for a sync that runs between the model taking new days
  /// and this grid getting them.
  bool get _daysReady {
    return widget.model.status == CalendarLoadStatus.ready &&
        widget.model.isShown(widget.firstDay, _lastDay);
  }

  /// Sets the board's items to the days' shown items when the days are
  /// ready, and to none otherwise, and counts the shown items with no
  /// block. A sync animates only when [animate] holds, its days are ready
  /// and the last sync found its own days ready; any other runs
  /// under [BoardAnimationStyle.disabled], and so does every sync until a
  /// frame callback restores [timedGridAnimationStyle]. New days reach
  /// this grid only after the model has notified that it shows them, and
  /// the sync that notification runs finds the old days not ready, so the
  /// first sync of new days does not animate.
  void _sync({bool animate = true}) {
    final ready = _daysReady;
    final placements = <BoardPlacement<ShownItem>>[];
    var hidden = 0;
    if (ready) {
      final shown = widget.model.itemsBetween(widget.firstDay, _lastDay);
      for (final entry in shown) {
        final span = gridSpanOf(entry.item.shape, _tracks);
        if (span == null) {
          hidden++;
        } else {
          placements.add(BoardPlacement<ShownItem>(entry, span));
        }
      }
    }
    final animated = animate && ready && _syncedReady;
    if (!animated) {
      _board.animationStyle = BoardAnimationStyle.disabled;
    }
    _board.setItems(placements);
    if (!animated) {
      _scheduleStyleRestore();
    }
    _syncedReady = ready;
    _hiddenCount.value = hidden;
  }

  /// Puts [timedGridAnimationStyle] back in a frame callback scheduled
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
        _board.animationStyle = timedGridAnimationStyle;
      }
    });
  }

  /// Whether the board may lift [id]: not while a write on it runs, and
  /// not when it reaches past the hours, whose cut-off minutes a drop
  /// would lose.
  bool _canDrag(String id) {
    if (widget.model.isLocked(id)) {
      return false;
    }
    final entry = _board.itemOf(id);
    return entry != null && !_reachesPastHours(entry.item);
  }

  /// Whether [item] starts before the grid's hours or ends after them.
  bool _reachesPastHours(CalendarItem item) {
    final hours = _tracks.hours;
    return item.startMinute < hours.start || item.endMinute > hours.end;
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
    final converted = shapeFromSpan(entry.item.shape, from, span, _tracks);
    if (!isAllowedDayCount(converted.dayCount)) {
      return false;
    }
    // The converted shape's own span, not the candidate's: an item clipped
    // at the grid's first day shows more days once moved right.
    final shownSpan = gridSpanOf(converted, _tracks);
    if (shownSpan == null) {
      return false;
    }
    final others = _board.itemsIn(
      shownSpan.rowStart,
      shownSpan.rowStart + shownSpan.rowSpan,
      shownSpan.colStart,
      shownSpan.colStart + shownSpan.colSpan,
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
  /// the item locked after its host last built, for one reaching past the
  /// hours, and when the item would not change.
  void _commit(String id, BoardSpan to) {
    if (widget.model.isLocked(id)) {
      return;
    }
    final from = _board.spanOf(id);
    final stored = widget.model.storedItem(id);
    if (from == null || stored == null || _reachesPastHours(stored)) {
      return;
    }
    final requested = itemFromSpan(stored, from, to, _tracks);
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

  /// The body cell painting under [local], a point in the viewport's paint
  /// space, or null over the header, the gutter or past the lattice.
  ({int row, int col})? _bodyCellAtLocal(
    RenderBoardViewport<String> viewport,
    Offset local,
  ) {
    final cell = viewport.cellAt(local);
    if (cell == null || cell.row < 1 || cell.col < 1) {
      return null;
    }
    return cell;
  }

  /// [_bodyCellAtLocal] for a global point.
  ({int row, int col})? _bodyCellAt(Offset global) {
    final viewport = _findViewport();
    if (viewport == null) {
      return null;
    }
    return _bodyCellAtLocal(viewport, viewport.globalToLocal(global));
  }

  /// Whether a press at [global] may create: no range runs, it lies over a
  /// body cell, no item paints under it, and the grid is neither scrolling
  /// nor just stopped by this press.
  bool _admits(Offset global) {
    final viewport = _findViewport();
    if (viewport == null || _scrollJustStopped || _range != null) {
      return false;
    }
    final vertical = viewport.verticalPosition;
    final horizontal = viewport.horizontalPosition;
    if ((vertical?.isScrollingNotifier.value ?? false) ||
        (horizontal?.isScrollingNotifier.value ?? false)) {
      return false;
    }
    final local = viewport.globalToLocal(global);
    if (_bodyCellAtLocal(viewport, local) == null) {
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
    widget.onCreate(createRangeAt(_tracks, cell));
  }

  Drag? _beginRange(Offset position) {
    final viewport = _findViewport();
    if (viewport == null || _range != null) {
      return null;
    }
    final point = viewport.globalToLocal(position);
    final anchor = _bodyCellAtLocal(viewport, point);
    if (anchor == null) {
      return null;
    }
    final range = _RangeDrag(this, viewport, anchor, point);
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
        ? createRangeAt(_tracks, range.anchor)
        : createRangeOver(_tracks, range.anchor, range.focus);
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
        return _HiddenCountCell(count: _hiddenCount);
      }
      return _DayHeaderCell(
        header: _header,
        column: cell.col,
        today: widget.today,
        onSelectDay: _selectDay,
      );
    }
    if (cell.col == 0) {
      // Every gutter row is opaque so nothing scrolled beneath the band
      // shows through; the label sits on the hour line.
      final minute = _tracks.minuteAt(cell.row);
      final onHour = minute % 60 == 0 && cell.row > 1;
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
    final hours = _tracks.hours;
    return _Block(
      key: blockKey(entry.id),
      entry: entry,
      showsSummary: view.span.rowSpan >= 3,
      cutAtStart: entry.item.startMinute < hours.start,
      cutAtEnd: entry.item.endMinute > hours.end,
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
          background: _TimedGridPainter(
            tracks: _tracks,
            today: widget.today,
            rangeAnchor: range?.anchor,
            rangeFocus: range?.focus,
          ),
          drag: _dragConfig,
          // The grid scrolls on its own, not with the screen's primary
          // scroll controller.
          primary: false,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        _fitAxes(constraints.biggest);
        return Stack(
          children: <Widget>[
            Positioned.fill(child: board),
            if (!_daysReady)
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
/// pointer.
///
/// The pointer is tracked in the viewport's paint space, as the press
/// converted plus the sum of every update's delta: a multi-drag recognizer
/// reports the move that accepted it as a delta from the press, with the
/// press's own position. The range listens to both scroll positions for
/// its length, so the focus stays the cell under the pointer while content
/// scrolls beneath it.
class _RangeDrag extends Drag {
  _RangeDrag(this._grid, this._viewport, this.anchor, this._point)
    : focus = anchor,
      _vertical = _viewport.verticalPosition,
      _horizontal = _viewport.horizontalPosition {
    _vertical?.addListener(_refocus);
    _horizontal?.addListener(_refocus);
  }

  final _TimedGridState _grid;
  final RenderBoardViewport<String> _viewport;
  final ScrollPosition? _vertical;
  final ScrollPosition? _horizontal;
  final ({int row, int col}) anchor;

  /// The body cell last under the pointer: unchanged while the pointer is
  /// over the header, the gutter or past the lattice.
  ({int row, int col}) focus;

  Offset _point;

  @override
  void update(DragUpdateDetails details) {
    _point += details.delta;
    _refocus();
  }

  void _refocus() {
    final cell = _grid._bodyCellAtLocal(_viewport, _point);
    if (cell == null || cell == focus) {
      return;
    }
    _grid._moveRange(this, cell);
  }

  @override
  void end(DragEndDetails details) {
    detach();
    _grid._endRange(this);
  }

  @override
  void cancel() {
    detach();
    _grid._clearRange(this);
  }

  /// Stops listening to the scroll positions.
  void detach() {
    _vertical?.removeListener(_refocus);
    _horizontal?.removeListener(_refocus);
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

  /// The board column of the cell, which [GridTracks.dateAt] reads.
  final int column;
  final DateTime today;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_HeaderState>(
      valueListenable: header,
      builder: (context, value, child) {
        // New tracks reach the header in the build that replaces the
        // columns, so the cell of a column they no longer have rebuilds
        // once before the board's next layout drops it.
        if (column > value.tracks.columnCount) {
          return const SizedBox.shrink();
        }
        final day = value.tracks.dateAt(column);
        final isToday = day == today;
        final isSelected = day == value.selectedDay;
        return GestureDetector(
          key: dayHeaderKey(day),
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

/// One item on the grid: its type's tint with a 4 px edge, its title, its
/// first summary when [showsSummary], and an arrow at each end the grid's
/// hours cut. Dimmed with a progress indicator while [ShownItem.pending].
class _Block extends StatelessWidget {
  const _Block({
    super.key,
    required this.entry,
    required this.showsSummary,
    required this.cutAtStart,
    required this.cutAtEnd,
    required this.onOpen,
  });

  final ShownItem entry;

  /// Whether the block's span covers enough rows for a second line. Read
  /// from the span rather than measured, so a block laid out at a new
  /// extent on each animation frame does not rebuild for it.
  final bool showsSummary;

  /// Whether the item starts before the grid's hours, which an arrow at
  /// the block's top marks.
  final bool cutAtStart;

  /// Whether the item ends after the grid's hours, which an arrow at the
  /// block's bottom marks.
  final bool cutAtEnd;

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
    if (cutAtStart || cutAtEnd) {
      content = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          content,
          if (cutAtStart)
            const Positioned(
              top: 0.0,
              right: 0.0,
              child: Icon(
                Icons.keyboard_arrow_up,
                size: 14.0,
                color: HarborColors.textSecondary,
              ),
            ),
          if (cutAtEnd)
            const Positioned(
              bottom: 0.0,
              right: 0.0,
              child: Icon(
                Icons.keyboard_arrow_down,
                size: 14.0,
                color: HarborColors.textSecondary,
              ),
            ),
        ],
      );
    }
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

/// The corner over the gutter: blank, or a count of the shown items the
/// grid has no block for, whose tooltip says why.
class _HiddenCountCell extends StatelessWidget {
  const _HiddenCountCell({required this.count});

  final ValueListenable<int> count;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: count,
      builder: (context, value, child) {
        return ColoredBox(
          color: HarborColors.surface,
          child: value == 0
              ? null
              : Center(
                  child: Tooltip(
                    message: hiddenItemsLabel(value),
                    child: DecoratedBox(
                      key: hiddenCountKey,
                      decoration: BoxDecoration(
                        color: HarborColors.primaryTint,
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6.0,
                          vertical: 2.0,
                        ),
                        child: Text(
                          "+$value",
                          style: const TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.w600,
                            color: HarborColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Covers the grid while its days are not ready, taking every press: a
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
/// dragged, filled like today's column and edged in the primary colour so
/// it shows over that column too. Every paint it draws with is built once.
class _TimedGridPainter extends BoardBackgroundPainter {
  const _TimedGridPainter({
    required this.tracks,
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
  static final Paint _rangeEdgePaint = Paint()
    ..color = HarborColors.primary
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  final GridTracks tracks;
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
    final todayColumn = tracks.columnOf(dayNumber(today));
    for (var col = firstCol; col <= lastCol; col++) {
      final Paint fill;
      if (col == todayColumn) {
        fill = _tintPaint;
      } else if (weekdayColumnOfDay(tracks.dayAt(col)) >= 5) {
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
        final rect = geometry
            .visibleCellRect(top, left)
            .expandToInclude(geometry.visibleCellRect(bottom, right));
        canvas.drawRect(rect, _tintPaint);
        canvas.drawRect(rect.deflate(1.0), _rangeEdgePaint);
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
  bool shouldRepaint(covariant _TimedGridPainter old) {
    return old.tracks != tracks ||
        old.today != today ||
        old.rangeAnchor != rangeAnchor ||
        old.rangeFocus != rangeFocus;
  }
}
