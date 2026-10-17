/// The calendar's timed grid: consecutive days on the board, with a frozen
/// hour gutter and, where it shows one, a frozen day header, one row per
/// 15-minute slot, and the days' items as blocks that move, and once
/// selected resize.
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

/// The height of the rows above and below the slots that count the items
/// outside the hours.
const double _noticeHeight = 24.0;

/// The time the grid opens scrolled to when it does not show the clock's
/// day, where its hours hold it.
const int _openingMinute = 8 * 60;

/// The minute the grid [tracks] lays out opens scrolled to: the hour
/// before [now]'s hour when it shows [now]'s day, [_openingMinute]
/// otherwise, or the nearer end of its hours when they do not hold that.
int _openingMinuteOf(GridTracks tracks, DateTime now) {
  final minute = tracks.columnOf(dayNumber(now)) == null
      ? _openingMinute
      : math.max(0, (now.hour - 1) * 60);
  final hours = tracks.hours;
  return minute.clamp(hours.start, hours.end - minutesPerSlot);
}

/// The minute the Add of a grid looks for a free hour on [day] from: on
/// [now]'s day the next whole hour, [now] itself when it is one, and
/// [_openingMinute] on any other day, where the grid opens.
int addFromMinute(DateTime day, DateTime now) {
  if (dayNumber(day) != dayNumber(now)) {
    return _openingMinute;
  }
  final minute = now.hour * 60 + now.minute;
  return (minute + 59) ~/ 60 * 60;
}

/// The style the grid animates its blocks with: every family over
/// [harborMotionDuration] on [harborMotionCurve].
const BoardAnimationStyle timedGridAnimationStyle = BoardAnimationStyle.uniform(
  BoardAnimationSpec(duration: harborMotionDuration, curve: harborMotionCurve),
);

/// The key of the day header cell showing [day].
ValueKey<String> dayHeaderKey(DateTime day) {
  return ValueKey<String>("grid-day-${isoDate(day)}");
}

/// The key of the block showing the item [id].
ValueKey<String> blockKey(String id) {
  return ValueKey<String>("block-$id");
}

/// The key of the outline and the resize handles over the block of the
/// item [id] while it is selected.
ValueKey<String> blockHandlesKey(String id) {
  return ValueKey<String>("block-handles-$id");
}

/// The key of the grip of the selected block of the item [id] that lies
/// across its edge on [side]: [AxisDirection.up], [AxisDirection.down] or
/// [AxisDirection.right].
ValueKey<String> blockGripKey(String id, AxisDirection side) {
  return ValueKey<String>("block-grip-$id-${side.name}");
}

/// The key of the pill counting the shown items on no day the grid has a
/// column for.
const ValueKey<String> hiddenCountKey = ValueKey<String>("grid-hidden-count");

/// What the tooltip of the pill counting [count] items on no day the grid
/// has a column for says.
String hiddenItemsLabel(int count) {
  if (count == 1) {
    return "1 item is on a day not shown";
  }
  return "$count items are on days not shown";
}

/// The key of [day]'s cell in the row above the slots that counts the
/// shown items before the hours.
ValueKey<String> hiddenAboveKey(DateTime day) {
  return ValueKey<String>("grid-hidden-above-${isoDate(day)}");
}

/// The key of [day]'s cell in the row below the slots that counts the
/// shown items after the hours.
ValueKey<String> hiddenBelowKey(DateTime day) {
  return ValueKey<String>("grid-hidden-below-${isoDate(day)}");
}

/// What a screen reader says for [day]'s cell counting [count] items
/// before [minute], or after it when [above] is false, naming the minute
/// in [format].
String hiddenRowLabel(
  DateTime day,
  int count,
  int minute, {
  required bool above,
  required HourLabelFormat format,
}) {
  final date =
      "${weekdayNames[weekdayColumn(day)]}, "
      "${monthNames[day.month - 1]} ${day.day}";
  final items = count == 1 ? "1 more item" : "$count more items";
  final side = above ? "before" : "after";
  return "$date, $items $side ${hourLabel(minute, format)}";
}

/// The shown items a grid has no block for, as the grid [tracks] lays out
/// counts them: on each day column, those wholly before its hours and
/// those wholly after them, and those on no day it has a column for.
@immutable
class _Hidden {
  _Hidden(this.tracks, this.above, this.below, this.offDays)
    : rowAbove = above.any(_isCounted),
      rowBelow = below.any(_isCounted);

  /// No item on any of [tracks]' columns.
  _Hidden.none(GridTracks tracks)
    : this(
        tracks,
        List<int>.filled(tracks.columnCount, 0),
        List<int>.filled(tracks.columnCount, 0),
        0,
      );

  /// The tracks the counts were made on, whose days and hours the cells
  /// counting them name.
  final GridTracks tracks;

  /// The items before the hours: column `c` counts `above[c - 1]`.
  final List<int> above;

  /// The items after the hours, by column as [above].
  final List<int> below;

  final int offDays;

  /// Whether a column counts items before the hours, which the grid then
  /// shows in a row above its slots.
  final bool rowAbove;

  /// Whether a column counts items after the hours, which the grid then
  /// shows in a row below its slots.
  final bool rowBelow;

  static bool _isCounted(int count) {
    return count > 0;
  }

  @override
  bool operator ==(Object other) {
    return other is _Hidden &&
        other.tracks == tracks &&
        listEquals(other.above, above) &&
        listEquals(other.below, below) &&
        other.offDays == offDays;
  }

  @override
  int get hashCode {
    return Object.hash(
      tracks,
      Object.hashAll(above),
      Object.hashAll(below),
      offDays,
    );
  }
}

/// Whether a grid lays out a row above its slots and one below them.
typedef _Notices = ({bool above, bool below});

/// The key of the label naming where a drag lands.
const ValueKey<String> landingLabelKey = ValueKey<String>("grid-landing-label");

/// What the landing label says while a move has nowhere to land.
const String noLandingLabel = "No free time near here";

/// What the landing label says for a drag that would give an item
/// [shape]: its first day, as [dayTitle] names it against [today], its
/// times, and its day count when it covers more than one day.
String landingLabel(ItemShape shape, DateTime today) {
  final day = dayTitle(dateOfDayNumber(shape.firstDay), today);
  final times = "${clockLabel(shape.start)}-${clockLabel(shape.end)}";
  if (shape.dayCount == 1) {
    return "$day, $times";
  }
  return "$day, $times, ${shape.dayCount} days";
}

/// The key of the shadow under the block a move carries.
const ValueKey<String> liftedBlockKey = ValueKey<String>("grid-lifted-block");

/// The shadow under the block a move carries once it has lifted. Spread
/// in by the 1 px margin round each block, so it falls from the block's
/// painted edge.
const List<BoxShadow> liftedBlockShadows = <BoxShadow>[
  BoxShadow(
    color: Color(0x33000000),
    offset: Offset(0.0, 4.0),
    blurRadius: 8.0,
    spreadRadius: -1.0,
  ),
  BoxShadow(
    color: Color(0x1F000000),
    offset: Offset(0.0, 1.0),
    blurRadius: 3.0,
    spreadRadius: -1.0,
  ),
];

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
/// Column 0 is the hour gutter, and the rows from [firstSlotRow] are the
/// slots of [hours], one per [minutesPerSlot]; the rows before it are
/// whatever the grid lays out above its slots, such as a day header or a
/// row counting the items before the hours. The
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
    this.firstSlotRow = 1,
  }) : assert(dayCount >= 1),
       assert(firstSlotRow >= 0),
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

  /// The row of the first slot.
  final int firstSlotRow;

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

  /// The row of the last slot.
  int get lastSlotRow {
    return firstSlotRow + rowCount - 1;
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

  /// The minute the slot [row] starts at, for a row from [firstSlotRow] to
  /// [lastSlotRow]; the row after the last gives the end of [hours].
  int minuteAt(int row) {
    return hours.start + (row - firstSlotRow) * minutesPerSlot;
  }

  /// The row of the slot starting at [minute], a slot boundary in
  /// [hours].
  int rowOf(int minute) {
    return firstSlotRow + (minute - hours.start) ~/ minutesPerSlot;
  }

  @override
  bool operator ==(Object other) {
    return other is GridTracks &&
        other.firstDay == firstDay &&
        other.dayCount == dayCount &&
        other.weekdays == weekdays &&
        other.hours == hours &&
        other.firstSlotRow == firstSlotRow;
  }

  @override
  int get hashCode {
    return Object.hash(firstDay, dayCount, weekdays, hours, firstSlotRow);
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
/// shows for them once the model's shown range holds them all, read. A
/// tap on a block that is not pending reports [onOpenItem]; a tap on a
/// day header reports [onSelectDay]. On a grid of one day column each
/// block uses the width to show its times and its summaries.
///
/// A long press on an item lifts it to move and selects its block, in edit
/// mode, which [settings] choose, and out of it; a tap anywhere but on the
/// selected block, or its item leaving the grid, clears the selection. Only
/// the selected block has resize handles, over an outline: its top drags
/// its start time, its bottom its end time, and, on more than one day, its
/// right edge its day count, each from a press on either side of the
/// edge, where a pill lies across it. A touch drag from another block's
/// edge scrolls the grid as one anywhere else does.
/// A move dropped onto another item's time lands at the nearest free time
/// that shows, on that day or the day before or after it, and goes back
/// where there is none; a resize dragged onto one stops at its
/// edge. While a drag runs, a label over the grid names the day and times a
/// release would give, or that a move has nowhere to land, and a move outlines
/// the slots it would land on. A line over the blocks marks the time [now]
/// holds in its day's column, and the grid opens scrolled to the hour before it
/// when it shows that day, at 08:00 otherwise, with that hour's label whole
/// below the top edge. Each whole hour, and the start and the end of the hours,
/// has a label centred on its line in the hour gutter, in the format [settings]
/// choose, which a room above the first slot and below the last, or the gutter
/// beside a row counting items outside the hours, keeps whole. An
/// item reaching past the hours shows the part inside them, with an arrow where
/// it is cut, and takes no move or resize: its form changes it. An item wholly
/// outside them has no block. While some are before the hours, a yellow row
/// frozen against the first slot, in place of the room above it, says "+N
/// more" in the column of each day with N of them, and while some are after
/// them, a row frozen against the last slot does; the hour gutter runs on
/// beside both. An item on no shown day has no block either,
/// and a pill in the day header's corner counts it. Empty body cells take a
/// create gesture, reported through [onCreate]: a drag picks the rectangle
/// of slots it covers, after a press and hold on touch, so a touch drag
/// without one scrolls the grid, and a hold let go where it began picks one
/// hour from its slot, or up to the end of the hours. In edit mode a mouse
/// or a stylus drags at once, and a tap picks one hour as a hold does.
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
    required this.now,
    required this.onSelectDay,
    required this.onOpenItem,
    required this.onCreate,
    this.showsDayHeader = true,
  }) : assert(dayCount >= 1);

  final CalendarModel model;

  /// Whether row 0 is a frozen header naming each column's day, whose
  /// corner over the gutter holds the pill counting the items on no shown
  /// day. Fixed for the grid's life.
  final bool showsDayHeader;

  /// Whether the grid is in edit mode, the weekdays and the hours it shows,
  /// the format of its hour labels and the least size of its cells. At
  /// least one day of the range must fall on a shown weekday.
  final CalendarSettings settings;

  /// The first day of the range the grid shows.
  final DateTime firstDay;

  /// How many days the range holds.
  final int dayCount;

  final DateTime selectedDay;

  /// The day whose column and header the grid marks as today.
  final DateTime today;

  /// The current time, which its owner sets again at the start of each
  /// minute. The grid follows it without a rebuild from above.
  final ValueListenable<DateTime> now;

  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<String> onOpenItem;

  /// Reports the slots a create gesture on empty cells picked.
  final ValueChanged<CreateRange> onCreate;

  @override
  State<TimedGrid> createState() {
    return _TimedGridState();
  }
}

typedef _HeaderState = ({
  GridTracks tracks,
  DateTime selectedDay,
  DateTime today,
});

/// The drag the board runs: its item, whether it moves or resizes which
/// edge, whether the board has reported a target yet, and the placement a
/// release would report, null where none is admitted.
typedef _GridDrag = ({
  String id,
  BoardDragKind kind,
  bool resolved,
  BoardSpan? target,
});

/// Where the line marking the current time sits: the column of its day
/// and its minute after midnight.
typedef _NowMark = ({int column, int minute});

class _TimedGridState extends State<TimedGrid> with TickerProviderStateMixin {
  late final BoardController<String, ShownItem> _board;

  /// The rows counting the items outside the hours that the grid lays out
  /// above and below its slots.
  _Notices _notices = (above: false, below: false);

  /// Where the widget's days and minutes sit on the board.
  late GridTracks _tracks = _tracksOf(widget);

  /// Held in fields because `Board` replaces its delegate, and so rebuilds
  /// every cell and item, whenever a builder it gets is not identical to
  /// the previous one.
  late final BoardCellBuilder<String, ShownItem> _cellBuilder = _buildCell;
  late final BoardItemBuilder<String, ShownItem> _itemBuilder = _buildItem;

  /// One instance, so a rebuild of this state hands the board the config
  /// it already has. The board builds no handles of its own: each block
  /// carries the handle that moves it after a long press, and the selected
  /// block the resize handles the config's edges admit ([_Block]). A single
  /// day column has no right strip: there is no column to drag its edge
  /// onto. Whether the grid has more than one column is fixed for its
  /// life, which [didUpdateWidget] asserts.
  ///
  /// A move [_canDropAt] refuses for meeting another item slides to the
  /// placement nearest on screen that holds it clear, at any time that
  /// shows of the day it was dropped on or of the day before or after it,
  /// however busy the time around it is. A resize it refuses for meeting
  /// another item stops its dragged edge at that item. The drag reports
  /// keep [_drag], which the landing label and outline show. A drag's
  /// start plays a haptic, and the block a move carries casts a shadow.
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
    primaryResizeEdges: BoardResizeEdges.both,
    buildDefaultDragHandles: false,
    draggedItemOpacity: harborDraggedItemOpacity,
    dragProxyBuilder: _buildLiftedBlock,
    hapticsOnDrag: true,
    onDragStart: _handleDragStart,
    onDragTargetChanged: _handleDragTarget,
    onDragEnd: _handleDragEnd,
  );

  /// The id of the item whose block a long press last lifted, which shows
  /// its resize handles, or null. The blocks listen to it, as the item
  /// builder runs only when the board rebuilds an item.
  final ValueNotifier<String?> _selectedBlock = ValueNotifier<String?>(null);

  /// The selected block's handles, while it is built.
  final _HandlesSlot _handles = _HandlesSlot();

  /// The cursor over the strips outside the selected block that resize it,
  /// [MouseCursor.defer] anywhere else.
  final ValueNotifier<MouseCursor> _besideCursor = ValueNotifier<MouseCursor>(
    MouseCursor.defer,
  );

  /// The presses that went down off the selected block, by pointer: where
  /// each went down, and the block selected then. One let go within its
  /// slop of there, with that block still selected, is a tap elsewhere,
  /// which clears the selection.
  final Map<int, ({Offset at, String id})> _pressesOff =
      <int, ({Offset at, String id})>{};

  /// The drag the board runs, or null.
  _GridDrag? _drag;

  /// Where the line marking [TimedGrid.now] sits, or null where the grid
  /// does not show it.
  late _NowMark? _nowMark = _nowMarkOf(widget.now.value);

  /// What the header cells show. The cell builder runs only when the board
  /// rebuilds a cell, so the header cells listen to this instead.
  late final ValueNotifier<_HeaderState> _header = ValueNotifier<_HeaderState>((
    tracks: _tracks,
    selectedDay: widget.selectedDay,
    today: widget.today,
  ));

  /// The extents the axes were last given and the tracks they were given
  /// for. [_fitAxes] replaces an axis only when one of these changes.
  late double _dayWidth = widget.settings.minDayWidth;
  late double _slotHeight = widget.settings.minSlotHeight;
  late int _columnCount = _tracks.columnCount;
  late DayHours _rowHours = _tracks.hours;
  double _rowRoom = _initialLabelRoom;
  late _Notices _rowNotices = _notices;
  late HourLabelFormat _rowFormat = widget.settings.hourLabelFormat;

  /// The room above the first slot and below the last: half an hour label
  /// and the gap beside it, so the labels centred on the first and the
  /// last line show whole. Each build sets it from the labels' height.
  double _labelRoom = _initialLabelRoom;

  /// [_labelRoom] before the first build measures the labels, which the
  /// rows [initState] makes are laid out with.
  static const double _initialLabelRoom = 8.0;

  /// The size the board was last laid out at; null before the first
  /// layout.
  Size? _size;

  /// The shown items with no block, as the last [_sync] counted them. The
  /// pill counting those on no shown day and the cells of the rows
  /// counting those outside the hours listen to it, as the cell builder
  /// runs only when the board rebuilds a cell.
  late final ValueNotifier<_Hidden> _hiddenCount = ValueNotifier<_Hidden>(
    _Hidden.none(_tracks),
  );

  /// The hour labels the foreground paints, laid out for the style and
  /// text scale the last build found.
  final _HourLabels _hourLabels = _HourLabels();

  /// The hour labels' own style, over the inherited text style.
  static const TextStyle _hourLabelStyle = TextStyle(
    fontSize: 11.0,
    height: 1.0,
    color: HarborColors.textSecondary,
  );

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
    widget.now.addListener(_handleNow);
    _sync();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _board.jumpToCell(
        _tracks.rowOf(_openingMinuteOf(_tracks, widget.now.value)),
        1,
      );
      // The jump put the opening line on the top edge; the label centred
      // on it needs the room above it that the first line has.
      final vertical = _findViewport()?.verticalPosition;
      if (vertical != null) {
        vertical.jumpTo(
          math.max(vertical.minScrollExtent, vertical.pixels - _labelRoom),
        );
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
    final nowChanged = widget.now != oldWidget.now;
    if (nowChanged) {
      oldWidget.now.removeListener(_handleNow);
      widget.now.addListener(_handleNow);
    }
    final tracks = _tracksOf(widget);
    final tracksChanged = tracks != _tracks;
    assert(
      (tracks.columnCount > 1) == (_tracks.columnCount > 1),
      "A TimedGrid keeps one day column or more than one; give a grid that "
      "changes between them its own key.",
    );
    assert(
      widget.showsDayHeader == oldWidget.showsDayHeader,
      "A TimedGrid keeps its day header or its lack of one; give a grid "
      "that changes it its own key.",
    );
    _tracks = tracks;
    if (tracksChanged || nowChanged) {
      _nowMark = _nowMarkOf(widget.now.value);
    }
    if (tracksChanged ||
        widget.selectedDay != oldWidget.selectedDay ||
        widget.today != oldWidget.today) {
      _header.value = (
        tracks: tracks,
        selectedDay: widget.selectedDay,
        today: widget.today,
      );
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
      // The day header, then the room above the first slot or the row
      // counting the items before the hours.
      firstSlotRow: (widget.showsDayHeader ? 1 : 0) + 1,
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
    widget.now.removeListener(_handleNow);
    _tap.dispose();
    _immediateRange.dispose();
    _delayedRange.dispose();
    _range?.detach();
    widget.model.removeListener(_handleModel);
    _header.dispose();
    _hiddenCount.dispose();
    _selectedBlock.dispose();
    _besideCursor.dispose();
    _hourLabels.dispose();
    // The board has unmounted by now, so nothing still listens to the
    // controller.
    _board.dispose();
    super.dispose();
  }

  /// The slots of the hours, [_slotHeight] each, under the frozen day
  /// header where the grid shows one. Above the slots a row of
  /// [_labelRoom], or the frozen row counting the items before the hours
  /// where [_notices] has one, and below them a row of [_labelRoom] or the
  /// frozen row counting those after.
  BoardAxisConfig _rowsConfig() {
    return BoardAxisConfig(
      axis: ExplicitAxis(<double>[
        if (widget.showsDayHeader) _headerHeight,
        _edgeAbove,
        ...List<double>.filled(_tracks.rowCount, _slotHeight),
        _edgeBelow,
      ]),
      frozenStart: (widget.showsDayHeader ? 1 : 0) + (_notices.above ? 1 : 0),
      frozenEnd: _notices.below ? 1 : 0,
    );
  }

  /// The height of the row above the slots.
  double get _edgeAbove {
    return _notices.above ? _noticeHeight : _labelRoom;
  }

  /// The height of the row below the slots.
  double get _edgeBelow {
    return _notices.below ? _noticeHeight : _labelRoom;
  }

  /// Gives the board the rows [_rowsConfig] makes, and notes what they
  /// were made for.
  void _replaceRows() {
    _rowHours = _tracks.hours;
    _rowRoom = _labelRoom;
    _rowNotices = _notices;
    _rowFormat = widget.settings.hourLabelFormat;
    _board.rows = _rowsConfig();
  }

  /// The day header's height, or 0 where the grid shows none.
  double get _headerExtent {
    return widget.showsDayHeader ? _headerHeight : 0.0;
  }

  /// The height of the frozen rows above the slots.
  double get _leadingExtent {
    return _headerExtent + (_notices.above ? _noticeHeight : 0.0);
  }

  /// The row counting the items before the hours, or null where [_notices]
  /// has none.
  int? get _rowAbove {
    return _notices.above ? _tracks.firstSlotRow - 1 : null;
  }

  /// The row counting the items after the hours, or null where [_notices]
  /// has none.
  int? get _rowBelow {
    return _notices.below ? _tracks.lastSlotRow + 1 : null;
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
  /// rows are replaced for new hours even at the same count, for new
  /// [_notices], and for a new [_labelRoom] or hour format, which also
  /// rebuilds the gutter cells and so what they tell a screen reader.
  void _fitAxes(Size size) {
    _size = size;
    final settings = widget.settings;
    final dayWidth = math.max(
      settings.minDayWidth,
      _share(size.width - _gutterWidth, _tracks.columnCount),
    );
    final slotHeight = math.max(
      settings.minSlotHeight,
      _share(
        size.height - _headerExtent - _edgeAbove - _edgeBelow,
        _tracks.rowCount,
      ),
    );
    if (dayWidth != _dayWidth || _tracks.columnCount != _columnCount) {
      _dayWidth = dayWidth;
      _columnCount = _tracks.columnCount;
      _board.columns = _columnsConfig();
    }
    if (slotHeight != _slotHeight ||
        _tracks.hours != _rowHours ||
        _labelRoom != _rowRoom ||
        _notices != _rowNotices ||
        settings.hourLabelFormat != _rowFormat) {
      _slotHeight = slotHeight;
      _replaceRows();
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

  /// Whether the model's shown range holds every one of this grid's days,
  /// all of them read. The range may be wider than the grid, as a range
  /// holding the grid's whole week is. False for a sync that runs between
  /// the model taking a range without this grid's days and this grid
  /// getting new ones.
  bool get _daysReady {
    return widget.model.status == CalendarLoadStatus.ready &&
        widget.model.isWithinShown(widget.firstDay, _lastDay);
  }

  /// Sets the board's items to the days' shown items when the days are
  /// ready, and to none otherwise, counts the shown items with no block,
  /// and lays out the rows counting those outside the hours, before the
  /// items, so they fit the lattice they land on. A sync animates
  /// only when [animate] holds, its days are ready, the last sync found its
  /// own days ready and the rows stay as they were; any other runs under
  /// [BoardAnimationStyle.disabled], and so does every sync until a frame
  /// callback restores [timedGridAnimationStyle]. New days reach this grid
  /// through [didUpdateWidget], whose sync does not animate, and a sync
  /// that finds them not read yet leaves [_syncedReady] false, so the sync
  /// the read's completion runs does not animate either.
  void _sync({bool animate = true}) {
    final ready = _daysReady;
    final shown = ready
        ? widget.model.itemsBetween(widget.firstDay, _lastDay)
        : const <ShownItem>[];
    final hidden = _hiddenOf(shown);
    final relaid = _layOutNotices((
      above: hidden.rowAbove,
      below: hidden.rowBelow,
    ));
    final placements = <BoardPlacement<ShownItem>>[];
    for (final entry in shown) {
      final span = gridSpanOf(entry.item.shape, _tracks);
      if (span != null) {
        placements.add(BoardPlacement<ShownItem>(entry, span));
      }
    }
    final animated = animate && ready && _syncedReady && !relaid;
    if (!animated) {
      _board.animationStyle = BoardAnimationStyle.disabled;
    }
    _board.setItems(placements);
    if (!animated) {
      _scheduleStyleRestore();
    }
    final selected = _selectedBlock.value;
    if (selected != null &&
        !placements.any((placement) {
          return placement.item.id == selected;
        })) {
      _selectedBlock.value = null;
    }
    _syncedReady = ready;
    _hiddenCount.value = hidden;
  }

  /// The items of [shown] that [_tracks] has no block for, counted.
  _Hidden _hiddenOf(List<ShownItem> shown) {
    final above = List<int>.filled(_tracks.columnCount, 0);
    final below = List<int>.filled(_tracks.columnCount, 0);
    var offDays = 0;
    for (final entry in shown) {
      final shape = entry.item.shape;
      if (gridSpanOf(shape, _tracks) != null) {
        continue;
      }
      final first = _tracks.firstColumnFrom(shape.firstDay);
      final last = _tracks.lastColumnUpTo(shape.firstDay + shape.dayCount - 1);
      if (last < first) {
        offDays++;
        continue;
      }
      // On a shown day, so wholly outside the hours, on each of its days
      // alike: an item's minutes are the same on each, as itemsConflict
      // reads them.
      final counts = shape.start < _tracks.hours.start ? above : below;
      for (var column = first; column <= last; column++) {
        counts[column - 1]++;
      }
    }
    return _Hidden(_tracks, above, below, offDays);
  }

  /// Lays out the rows [notices] asks for, above and below the slots, in
  /// place of the ones the grid has, and returns whether they differ. Each
  /// takes the place of the room on its side, so no slot changes row, and
  /// the axes are fitted again at the last size, or replaced before the
  /// first layout.
  bool _layOutNotices(_Notices notices) {
    if (notices == _notices) {
      return false;
    }
    _notices = notices;
    final size = _size;
    if (size != null) {
      _fitAxes(size);
    } else {
      _replaceRows();
    }
    return true;
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
    if (span.rowStart < _tracks.firstSlotRow ||
        span.rowStart + span.rowSpan > _tracks.lastSlotRow + 1 ||
        span.colStart < 1) {
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

  void _handleDragStart(String id, BoardDragKind kind) {
    if (!mounted) {
      return;
    }
    if (kind == BoardDragKind.move) {
      _selectedBlock.value = id;
    }
    setState(() {
      _drag = (id: id, kind: kind, resolved: false, target: null);
    });
  }

  void _handleDragTarget(String id, BoardDropTarget? target) {
    final drag = _drag;
    if (!mounted || drag == null || drag.id != id) {
      return;
    }
    setState(() {
      _drag = (id: id, kind: drag.kind, resolved: true, target: target?.span);
    });
  }

  /// Delivered after the drop's report, and possibly after the board has
  /// left the tree.
  void _handleDragEnd(String id, bool committed) {
    if (!mounted || _drag == null) {
      return;
    }
    setState(() {
      _drag = null;
    });
  }

  /// The block a move carries, [proxy], over [liftedBlockShadows], which
  /// ease in from none over the lift. The board calls this on every
  /// pointer move with a tree of the same shape, so the lift runs once a
  /// drag, from the frame the block lifts.
  Widget _buildLiftedBlock(BuildContext context, String id, Widget proxy) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: harborMotionDuration,
      curve: harborMotionCurve,
      child: proxy,
      builder: (context, lift, child) {
        return DecoratedBox(
          key: liftedBlockKey,
          decoration: BoxDecoration(
            boxShadow: <BoxShadow>[
              for (final shadow in liftedBlockShadows)
                shadow.copyWith(
                  color: shadow.color.withValues(alpha: shadow.color.a * lift),
                ),
            ],
          ),
          child: child,
        );
      },
    );
  }

  /// What the landing label says for [_drag]: the day and times a release
  /// would give, or [noLandingLabel] for a move with no target. Null with
  /// no drag, before its first target, and for a resize with no target.
  String? _landingText() {
    final drag = _drag;
    if (drag == null || !drag.resolved) {
      return null;
    }
    final target = drag.target;
    if (target == null) {
      return drag.kind == BoardDragKind.move ? noLandingLabel : null;
    }
    final from = _board.spanOf(drag.id);
    final entry = _board.itemOf(drag.id);
    if (from == null || entry == null) {
      return null;
    }
    return landingLabel(
      shapeFromSpan(entry.item.shape, from, target, _tracks),
      widget.today,
    );
  }

  /// Where the line marking [now] sits: null when no column shows its day
  /// or the hours do not hold its minute.
  _NowMark? _nowMarkOf(DateTime now) {
    final column = _tracks.columnOf(dayNumber(now));
    final minute = now.hour * 60 + now.minute;
    final hours = _tracks.hours;
    if (column == null || minute < hours.start || minute > hours.end) {
      return null;
    }
    return (column: column, minute: minute);
  }

  /// Follows [TimedGrid.now], rebuilding only when the line moves, shows
  /// or goes.
  void _handleNow() {
    final mark = _nowMarkOf(widget.now.value);
    if (mark != _nowMark) {
      setState(() {
        _nowMark = mark;
      });
    }
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
    if (cell == null ||
        cell.row < _tracks.firstSlotRow ||
        cell.row > _tracks.lastSlotRow ||
        cell.col < 1) {
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

  /// Starts a resize for a press beside the selected block, keeps any
  /// other press off it for [_handlePointerUp], and arms the create
  /// gestures for an admitted press: out of edit mode only the range that
  /// starts after a press and hold. A listener's pointer down runs before
  /// the arena closes, so they join it beside the scrollable's pan; each
  /// recognizer ignores the pointer kinds it does not support.
  void _handlePointerDown(PointerDownEvent event) {
    final selected = _selectedBlock.value;
    if (selected != null) {
      final under = _itemAt(event.position);
      if (under == null && _startBeside(event)) {
        return;
      }
      if (under != selected) {
        _pressesOff[event.pointer] = (at: event.position, id: selected);
      }
    }
    if (!_admits(event.position)) {
      return;
    }
    if (widget.settings.editing) {
      _tap.addPointer(event);
      _immediateRange.addPointer(event);
    }
    _delayedRange.addPointer(event);
  }

  /// Clears the selection for a tap off the selected block, which a press
  /// lifting another block, and so selecting it, is not.
  void _handlePointerUp(PointerUpEvent event) {
    final press = _pressesOff.remove(event.pointer);
    if (press == null || _selectedBlock.value != press.id) {
      return;
    }
    final slop = computeHitSlop(
      event.kind,
      MediaQuery.maybeGestureSettingsOf(context),
    );
    if ((event.position - press.at).distance <= slop) {
      _selectedBlock.value = null;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _pressesOff.remove(event.pointer);
  }

  /// Starts a resize of the selected block for a press over a body cell,
  /// and over no block, on a strip outside the selected block beside one
  /// of its edges, which the board, hit-testing a block only within its
  /// bounds, gives no handle; reports whether it did.
  bool _startBeside(PointerDownEvent event) {
    final handles = _handles.current;
    return handles != null &&
        _bodyCellAt(event.position) != null &&
        handles.startOutside(event);
  }

  /// Shows the resize cursor over the strips [_startBeside] starts from.
  void _handleHover(PointerHoverEvent event) {
    final handles = _handles.current;
    var cursor = MouseCursor.defer;
    if (handles != null &&
        _selectedBlock.value != null &&
        _itemAt(event.position) == null &&
        _bodyCellAt(event.position) != null) {
      cursor = handles.cursorOutside(event.position);
    }
    _besideCursor.value = cursor;
  }

  /// The id of the item whose block lies under [global], or null.
  String? _itemAt(Offset global) {
    final viewport = _findViewport();
    if (viewport == null) {
      return null;
    }
    return viewport.itemAt(viewport.globalToLocal(global));
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
    if (widget.showsDayHeader && cell.row == 0) {
      if (cell.col == 0) {
        return ColoredBox(
          color: HarborColors.surface,
          child: Center(child: _HiddenCount(count: _hiddenCount)),
        );
      }
      return _DayHeaderCell(
        header: _header,
        column: cell.col,
        onSelectDay: _selectDay,
      );
    }
    final above = cell.row == _rowAbove;
    if (above || cell.row == _rowBelow) {
      // The gutter runs on beside the rows, with no label.
      if (cell.col == 0) {
        return const ColoredBox(color: HarborColors.surface);
      }
      return _NoticeCell(
        hidden: _hiddenCount,
        column: cell.col,
        above: above,
        format: widget.settings.hourLabelFormat,
      );
    }
    if (cell.col == 0) {
      // Every gutter row is opaque so nothing scrolled beneath the band
      // shows through. The foreground paints the hour labels over it; a
      // row whose top or bottom line is labelled names it to a screen
      // reader.
      const gutter = ColoredBox(color: HarborColors.surface);
      final label = _gutterLabelOf(cell.row);
      if (label == null) {
        return gutter;
      }
      return Semantics(container: true, label: label, child: gutter);
    }
    // Body cells build nothing: the background painter draws the grid.
    return null;
  }

  /// What a screen reader hears for the gutter cell of [row]: the labels
  /// the foreground paints on its top and bottom lines, or null where it
  /// paints none.
  String? _gutterLabelOf(int row) {
    final format = widget.settings.hourLabelFormat;
    final labels = <String>[
      if (_GridForegroundPainter.labelsRow(_tracks, row))
        hourLabel(_tracks.minuteAt(row), format),
      if (row == _tracks.lastSlotRow) hourLabel(_tracks.hours.end, format),
    ];
    return labels.isEmpty ? null : labels.join(", ");
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
      detailed: _tracks.columnCount == 1,
      showsSummary: view.span.rowSpan >= 3,
      cutAtStart: entry.item.startMinute < hours.start,
      cutAtEnd: entry.item.endMinute > hours.end,
      selection: _selectedBlock,
      handles: _handles,
      resizesDays: _tracks.columnCount > 1,
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
    final drag = _drag;
    var labelStyle = DefaultTextStyle.of(context).style.merge(_hourLabelStyle);
    if (MediaQuery.boldTextOf(context)) {
      labelStyle = labelStyle.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    _hourLabels.update(
      labelStyle,
      MediaQuery.textScalerOf(context),
      widget.settings.hourLabelFormat,
    );
    _labelRoom = _hourLabels.height / 2 + _HourLabels.gap;
    final landingText = _landingText();
    final listener = Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
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
            landing: drag != null && drag.kind == BoardDragKind.move
                ? drag.target
                : null,
          ),
          foreground: _GridForegroundPainter(
            tracks: _tracks,
            labels: _hourLabels,
            labelsVersion: _hourLabels.version,
            now: _nowMark,
            reachAbove: _notices.above ? _noticeHeight : 0.0,
            reachBelow: _notices.below ? _noticeHeight : 0.0,
          ),
          drag: _dragConfig,
          // The grid scrolls on its own, not with the screen's primary
          // scroll controller.
          primary: false,
        ),
      ),
    );
    final board = ValueListenableBuilder<MouseCursor>(
      valueListenable: _besideCursor,
      child: listener,
      builder: (context, cursor, child) {
        return MouseRegion(cursor: cursor, onHover: _handleHover, child: child);
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        _fitAxes(constraints.biggest);
        return Stack(
          children: <Widget>[
            Positioned.fill(child: board),
            if (landingText != null)
              Positioned(
                top: _leadingExtent + 8.0,
                left: _gutterWidth + 8.0,
                right: 8.0,
                child: _LandingLabel(text: landingText),
              ),
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
    required this.onSelectDay,
  });

  final ValueListenable<_HeaderState> header;

  /// The board column of the cell, which [GridTracks.dateAt] reads.
  final int column;
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
        final isToday = day == value.today;
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
                  Container(
                    width: 30.0,
                    height: 20.0,
                    alignment: Alignment.center,
                    foregroundDecoration: isToday
                        ? harborTodayRing(10.0)
                        : null,
                    child: Text(
                      "${day.day}",
                      style: TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.w700,
                        color: isToday
                            ? HarborColors.primary
                            : HarborColors.text,
                      ),
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

/// One item on the grid: its type's tint with a 4 px edge, its text, and
/// an arrow at each end the grid's hours cut. Dimmed with a progress
/// indicator while [ShownItem.pending]. A long press on it moves it, and
/// while [selection] names its item, an outline and the resize handles
/// lie over it ([_BlockHandles]).
///
/// A [detailed] block, which a grid of one day column shows, has its title
/// and its times on its first line, the times wrapping under a title too
/// long for both, and a line for each of its type's summaries under them;
/// it shows the lines that fit whole below the first. Any other block
/// shows its title, and its first summary when [showsSummary].
class _Block extends StatelessWidget {
  const _Block({
    super.key,
    required this.entry,
    required this.detailed,
    required this.showsSummary,
    required this.cutAtStart,
    required this.cutAtEnd,
    required this.selection,
    required this.handles,
    required this.resizesDays,
    required this.onOpen,
  });

  final ShownItem entry;

  /// The id of the item whose block is selected, or null.
  final ValueListenable<String?> selection;

  /// Where the handles register while this block is selected.
  final _HandlesSlot handles;

  /// Whether the selected block has a handle on its right edge, which
  /// drags its day count: on a grid of more than one day column.
  final bool resizesDays;

  final bool detailed;

  /// Whether the block's span covers enough rows for a second line, on a
  /// block that is not [detailed]. Read from the span rather than
  /// measured, so a block laid out at a new extent on each animation frame
  /// does not rebuild for it.
  final bool showsSummary;

  /// Whether the item starts before the grid's hours, which an arrow at
  /// the block's top marks.
  final bool cutAtStart;

  /// Whether the item ends after the grid's hours, which an arrow at the
  /// block's bottom marks.
  final bool cutAtEnd;

  /// Null while the item is pending, so a tap opens nothing.
  final VoidCallback? onOpen;

  static const TextStyle _detailStyle = TextStyle(
    fontSize: 12.0,
    color: HarborColors.textSecondary,
  );

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final style = harborTypeStyleOf(item.type);
    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: style.tint,
        border: Border(left: BorderSide(color: style.edge, width: 4.0)),
      ),
      child: detailed ? _buildLines(item) : _buildCompact(item),
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
    final block = BoardDelayedDragHandle(
      child: Padding(
        padding: const EdgeInsets.all(1.0),
        child: GestureDetector(onTap: onOpen, child: content),
      ),
    );
    // One shape selected or not, so a selection keeps the block's State.
    return ValueListenableBuilder<String?>(
      valueListenable: selection,
      child: block,
      builder: (context, selected, child) {
        return Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            child!,
            if (selected == entry.id)
              Positioned.fill(
                child: _BlockHandles(
                  key: blockHandlesKey(entry.id),
                  id: entry.id,
                  slot: handles,
                  resizesDays: resizesDays,
                ),
              ),
          ],
        );
      },
    );
  }

  /// The title and, when [showsSummary], the first summary, laid out at
  /// their natural height and clipped to the block, so a block shorter
  /// than its text does not overflow.
  Widget _buildCompact(CalendarItem item) {
    final schema = schemaOf(item.type);
    String? summary;
    if (showsSummary && schema.summaryKeys.isNotEmpty) {
      final key = schema.summaryKeys.first;
      summary = schema.fieldOf(key)?.summaryOf(item.fields[key]);
    }
    return ClipRect(
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
    );
  }

  /// The title and the times, then each summary the item has, one per
  /// line, as [_BlockLinesDelegate] paints them.
  Widget _buildLines(CalendarItem item) {
    final schema = schemaOf(item.type);
    final summaries = <String>[];
    for (final key in schema.summaryKeys) {
      final summary = schema.fieldOf(key)?.summaryOf(item.fields[key]);
      if (summary != null) {
        summaries.add(summary);
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(6.0, 3.0, 6.0, 3.0),
      child: Flow(
        delegate: const _BlockLinesDelegate(),
        children: <Widget>[
          Wrap(
            spacing: 8.0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                  color: HarborColors.text,
                ),
              ),
              Text(
                "${clockLabel(item.startMinute)}-${clockLabel(item.endMinute)}",
                maxLines: 1,
                style: _detailStyle,
              ),
            ],
          ),
          for (final summary in summaries)
            Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _detailStyle,
            ),
        ],
      ),
    );
  }
}

/// Lays a detailed block's lines out down its width, each at its natural
/// height, and paints the first line, clipped to the block when it is
/// taller, and each line after it while the lines down to its bottom fit,
/// so no line shows cut in half. The lines are laid out with the block,
/// so a block resized on each animation frame keeps the lines that fit
/// without a rebuild.
class _BlockLinesDelegate extends FlowDelegate {
  const _BlockLinesDelegate();

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) {
    return BoxConstraints(maxWidth: constraints.maxWidth);
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    var top = 0.0;
    for (var i = 0; i < context.childCount; i++) {
      final height = context.getChildSize(i)!.height;
      if (i > 0 && top + height > context.size.height) {
        return;
      }
      context.paintChild(
        i,
        transform: Matrix4.translationValues(0.0, top, 0.0),
      );
      top += height;
    }
  }

  @override
  bool shouldRepaint(_BlockLinesDelegate oldDelegate) {
    return false;
  }
}

/// Nothing, or a pill counting the shown items on no day the grid has a
/// column for, whose tooltip says why.
class _HiddenCount extends StatelessWidget {
  const _HiddenCount({required this.count});

  final ValueListenable<_Hidden> count;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_Hidden>(
      valueListenable: count,
      builder: (context, hidden, child) {
        final value = hidden.offDays;
        if (value == 0) {
          return const SizedBox.shrink();
        }
        return Tooltip(
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
        );
      },
    );
  }
}

/// A day column's cell in a row counting the shown items with no block:
/// those before the hours in the row above the slots, or those after them
/// in the row below when [above] is false. A soft yellow, with a rule on
/// the side facing the slots and one between days, and while the day has
/// some, an arrow pointing their way and "+N more", or "+N" in a column too
/// narrow for that.
class _NoticeCell extends StatelessWidget {
  const _NoticeCell({
    required this.hidden,
    required this.column,
    required this.above,
    required this.format,
  });

  final ValueListenable<_Hidden> hidden;

  /// The board column of the cell, which [GridTracks.dateAt] reads.
  final int column;

  final bool above;

  /// The format the cell names the hours in to a screen reader.
  final HourLabelFormat format;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_Hidden>(
      valueListenable: hidden,
      builder: (context, value, child) {
        // New tracks reach the counts in the sync that places items on
        // them, so the cell of a column they no longer have rebuilds once
        // before the board's next layout drops it.
        final tracks = value.tracks;
        if (column > tracks.columnCount) {
          return const SizedBox.shrink();
        }
        final day = tracks.dateAt(column);
        final count = (above ? value.above : value.below)[column - 1];
        const edge = BorderSide(color: HarborColors.noticeEdge);
        final cell = DecoratedBox(
          key: above ? hiddenAboveKey(day) : hiddenBelowKey(day),
          decoration: BoxDecoration(
            color: HarborColors.notice,
            border: Border(
              left: column > 1 ? edge : BorderSide.none,
              top: above ? BorderSide.none : edge,
              bottom: above ? edge : BorderSide.none,
            ),
          ),
          child: count == 0 ? const SizedBox.expand() : _buildMore(count),
        );
        if (count == 0) {
          return cell;
        }
        final hours = tracks.hours;
        return Semantics(
          container: true,
          label: hiddenRowLabel(
            day,
            count,
            above ? hours.start : hours.end,
            above: above,
            format: format,
          ),
          excludeSemantics: true,
          child: cell,
        );
      },
    );
  }

  static const TextStyle _moreStyle = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w600,
    color: HarborColors.onNotice,
  );

  static const double _arrowSize = 16.0;
  static const double _arrowGap = 2.0;

  /// The arrow and "+N more", or "+N" in a cell too narrow for "+N more"
  /// at its own size, scaled down in one too narrow for that.
  Widget _buildMore(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final more = "+$count more";
          final painter = TextPainter(
            text: TextSpan(
              text: more,
              style: DefaultTextStyle.of(context).style.merge(_moreStyle),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final fits =
              _arrowSize + _arrowGap + painter.width <= constraints.maxWidth;
          painter.dispose();
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    above ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: _arrowSize,
                    color: HarborColors.onNotice,
                  ),
                  const SizedBox(width: _arrowGap),
                  Text(fits ? more : "+$count", maxLines: 1, style: _moreStyle),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The pill over the grid naming where a drag lands. It takes no press, so
/// the pointer under it keeps driving the drag.
class _LandingLabel extends StatelessWidget {
  const _LandingLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: DecoratedBox(
          key: landingLabelKey,
          decoration: BoxDecoration(
            color: HarborColors.primary,
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 6.0,
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
                color: HarborColors.onPrimary,
              ),
            ),
          ),
        ),
      ),
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

/// The grid behind the cells, drawn for the visible body tracks alone: the
/// body, and across the slots the weekend and today's columns; the create range
/// being dragged and the slots a move would land on, each filled like today's
/// column and edged in the primary colour so it shows over that column too; and
/// a line at the top of each slot row, under the last one and at the left of
/// each day column, across the slots. The room above and below the slots shows
/// the body alone. Every paint it draws with is built once.
class _TimedGridPainter extends BoardBackgroundPainter {
  const _TimedGridPainter({
    required this.tracks,
    required this.today,
    required this.rangeAnchor,
    required this.rangeFocus,
    required this.landing,
  });

  static final Paint _surfacePaint = Paint()..color = HarborColors.surface;
  static final Paint _backgroundPaint = Paint()
    ..color = HarborColors.background;
  static final Paint _tintPaint = Paint()..color = HarborColors.primaryTint;
  static final Paint _linePaint = Paint()
    ..color = HarborColors.outline
    ..strokeWidth = 1.0;
  static final Paint _markEdgePaint = Paint()
    ..color = HarborColors.primary
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  final GridTracks tracks;
  final DateTime today;
  final ({int row, int col})? rangeAnchor;
  final ({int row, int col})? rangeFocus;

  /// The span a move would land on, or null.
  final BoardSpan? landing;

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
    canvas.save();
    canvas.clipRect(region);
    canvas.drawRect(region, _surfacePaint);
    final slotFirst = math.max(firstRow, tracks.firstSlotRow);
    final slotLast = math.min(lastRow, tracks.lastSlotRow);
    if (slotFirst > slotLast) {
      canvas.restore();
      return;
    }
    final first = geometry.visibleCellRect(slotFirst, firstCol);
    final last = geometry.visibleCellRect(slotLast, lastCol);
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
      final rect = geometry.visibleCellRect(slotFirst, col);
      canvas.drawRect(
        Rect.fromLTRB(rect.left, first.top, rect.right, last.bottom),
        fill,
      );
    }
    final anchor = rangeAnchor;
    final focus = rangeFocus;
    if (anchor != null && focus != null) {
      _paintMarked(
        canvas,
        geometry,
        top: math.min(anchor.row, focus.row),
        bottom: math.max(anchor.row, focus.row),
        left: math.min(anchor.col, focus.col),
        right: math.max(anchor.col, focus.col),
      );
    }
    final landing = this.landing;
    if (landing != null) {
      _paintMarked(
        canvas,
        geometry,
        top: landing.rowStart,
        bottom: landing.rowStart + landing.rowSpan - 1,
        left: landing.colStart,
        right: landing.colStart + landing.colSpan - 1,
      );
    }
    // The top line of each slot that shows, and the bottom line of the
    // last slot where the room below it shows.
    for (var row = slotFirst; row <= math.min(lastRow, slotLast + 1); row++) {
      final y = geometry.visibleCellRect(row, firstCol).top;
      canvas.drawLine(Offset(first.left, y), Offset(last.right, y), _linePaint);
    }
    for (var col = firstCol; col <= lastCol; col++) {
      final x = geometry.visibleCellRect(slotFirst, col).left;
      canvas.drawLine(Offset(x, first.top), Offset(x, last.bottom), _linePaint);
    }
    canvas.restore();
  }

  /// Fills the cells that show of the body rows [top] to [bottom] and
  /// columns [left] to [right], and edges them.
  void _paintMarked(
    Canvas canvas,
    BoardGeometryView geometry, {
    required int top,
    required int bottom,
    required int left,
    required int right,
  }) {
    final firstRow = math.max(top, geometry.firstVisibleRow);
    final lastRow = math.min(bottom, geometry.lastVisibleRow);
    final firstCol = math.max(left, geometry.firstVisibleCol);
    final lastCol = math.min(right, geometry.lastVisibleCol);
    if (firstRow > lastRow || firstCol > lastCol) {
      return;
    }
    final rect = geometry
        .visibleCellRect(firstRow, firstCol)
        .expandToInclude(geometry.visibleCellRect(lastRow, lastCol));
    canvas.drawRect(rect, _tintPaint);
    canvas.drawRect(rect.deflate(1.0), _markEdgePaint);
  }

  @override
  bool shouldRepaint(covariant _TimedGridPainter old) {
    return old.tracks != tracks ||
        old.today != today ||
        old.rangeAnchor != rangeAnchor ||
        old.rangeFocus != rangeFocus ||
        old.landing != landing;
  }
}

/// What the grid paints over its cells and blocks: the hour labels in the
/// gutter, and the line marking the current time.
///
/// A label names the start of the hours, each whole hour after it, and
/// the end of the hours, centred on its line and right-aligned in the
/// gutter. The grid's room above its first slot and below its last holds
/// the halves of the first and the last label past those lines, or where
/// a frozen row counting items outside the hours takes a room's place, the
/// gutter beside that row, which [reachAbove] and [reachBelow] measure: a
/// label shows whole there while its line shows, and sinks into the row's
/// edge as its line scrolls beneath the row. The labels are clipped to the
/// gutter below the day header, and a label taller than a slot still shows
/// whole, because no gutter cell paints over the foreground. The line
/// runs across [now]'s column at its minute, with a dot at its left end,
/// where that column and the row holding the minute show; the end of the
/// hours lies on the last row's bottom edge. It is clipped to the scrolled
/// region, so the frozen header and gutter cover it as they cover the
/// blocks.
class _GridForegroundPainter extends BoardForegroundPainter {
  const _GridForegroundPainter({
    required this.tracks,
    required this.labels,
    required this.labelsVersion,
    required this.now,
    required this.reachAbove,
    required this.reachBelow,
  });

  /// The space between a label and the gutter's right edge.
  static const double _labelEnd = 6.0;

  static final Paint _nowPaint = Paint()
    ..color = HarborColors.error
    ..strokeWidth = 2.0;

  /// Whether a label names the top line of the slot [row]: the first slot,
  /// and every slot starting a whole hour. False for a row that is no
  /// slot.
  static bool labelsRow(GridTracks tracks, int row) {
    if (row < tracks.firstSlotRow || row > tracks.lastSlotRow) {
      return false;
    }
    return row == tracks.firstSlotRow || tracks.minuteAt(row) % 60 == 0;
  }

  final GridTracks tracks;
  final _HourLabels labels;

  /// [_HourLabels.version] when this painter was made, so a new style or
  /// text scale repaints.
  final int labelsVersion;

  /// Where the line marking the current time sits, or null.
  final _NowMark? now;

  /// How far above the scrolled region the labels may paint: the height
  /// of the frozen row there, beside which the gutter is free, or 0.
  final double reachAbove;

  /// How far below the scrolled region the labels may paint, as
  /// [reachAbove].
  final double reachBelow;

  @override
  void paint(Canvas canvas, BoardGeometryView geometry) {
    _paintLabels(canvas, geometry);
    final now = this.now;
    if (now != null) {
      _paintNow(canvas, geometry, now);
    }
  }

  void _paintLabels(Canvas canvas, BoardGeometryView geometry) {
    final firstRow = math.max(geometry.firstVisibleRow, tracks.firstSlotRow);
    final lastRow = math.min(geometry.lastVisibleRow, tracks.lastSlotRow);
    if (firstRow > lastRow) {
      return;
    }
    final region = geometry.scrolledRegion;
    final first = geometry.visibleCellRect(firstRow, 0);
    // Every slot has the first visible one's height, so a line past the
    // visible slots sits a whole number of those from it.
    final slot = first.height;
    double lineOf(int row) {
      return first.top + (row - firstRow) * slot;
    }

    final half = labels.height / 2;
    // A label is clipped to the gutter of the scrolled region, and past
    // its top edge by half a label less how far its line lies above that
    // edge, up to [reachAbove], and past its bottom edge likewise. So it
    // shows whole beside a frozen row while its line shows, and sinks into
    // the row's edge as its line scrolls beneath the row.
    void paintOn(int minute, double line) {
      final above = (half - math.max(0.0, region.top - line)).clamp(
        0.0,
        reachAbove,
      );
      final below = (half - math.max(0.0, line - region.bottom)).clamp(
        0.0,
        reachBelow,
      );
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(
          first.left,
          region.top - above,
          first.right,
          region.bottom + below,
        ),
      );
      _paintLabel(canvas, minute, first.right, line - half);
      canvas.restore();
    }

    // A line just past the visible slots still shows the half of its
    // label on this side of it.
    final reach = slot > 0.0 ? (half / slot).ceil() : 0;
    final from = math.max(tracks.firstSlotRow, firstRow - reach);
    final to = math.min(tracks.lastSlotRow, lastRow + reach);
    for (var row = from; row <= to; row++) {
      if (labelsRow(tracks, row)) {
        paintOn(tracks.minuteAt(row), lineOf(row));
      }
    }
    final end = lineOf(tracks.lastSlotRow + 1);
    if (end - half < region.bottom && end + half > region.top) {
      paintOn(tracks.hours.end, end);
    }
  }

  /// Paints the label of [minute] with its top at [top] and its right
  /// edge [_labelEnd] inside [right].
  void _paintLabel(Canvas canvas, int minute, double right, double top) {
    final label = labels.of(minute);
    label.paint(canvas, Offset(right - _labelEnd - label.width, top));
  }

  void _paintNow(Canvas canvas, BoardGeometryView geometry, _NowMark now) {
    final col = now.column;
    if (col < geometry.firstVisibleCol || col > geometry.lastVisibleCol) {
      return;
    }
    final intoHours = now.minute - tracks.hours.start;
    var row = tracks.firstSlotRow + intoHours ~/ minutesPerSlot;
    var fraction = (intoHours % minutesPerSlot) / minutesPerSlot;
    if (row > tracks.lastSlotRow) {
      row = tracks.lastSlotRow;
      fraction = 1.0;
    }
    if (row < geometry.firstVisibleRow || row > geometry.lastVisibleRow) {
      return;
    }
    final rect = geometry.visibleCellRect(row, col);
    final y = rect.top + fraction * rect.height;
    canvas.save();
    canvas.clipRect(geometry.scrolledRegion);
    canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), _nowPaint);
    canvas.drawCircle(Offset(rect.left, y), 4.0, _nowPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GridForegroundPainter old) {
    return old.tracks != tracks ||
        old.now != now ||
        !identical(old.labels, labels) ||
        old.labelsVersion != labelsVersion ||
        old.reachAbove != reachAbove ||
        old.reachBelow != reachBelow;
  }
}

/// The hour labels a [_GridForegroundPainter] paints, each laid out once
/// for one style, text scale and [HourLabelFormat].
class _HourLabels {
  /// The space between a label's half and the end of the grid's room for
  /// it.
  static const double gap = 2.0;

  TextStyle _style = const TextStyle();
  TextScaler _scaler = TextScaler.noScaling;
  HourLabelFormat _format = HourLabelFormat.twentyFourHour;
  final Map<int, TextPainter> _labels = <int, TextPainter>{};

  /// Moves on each time [update] drops the laid-out labels.
  int version = 0;

  /// Lays the labels out anew from here on when [style], [scaler] or
  /// [format] differs from the last.
  void update(TextStyle style, TextScaler scaler, HourLabelFormat format) {
    if (style == _style && scaler == _scaler && format == _format) {
      return;
    }
    _style = style;
    _scaler = scaler;
    _format = format;
    _clear();
    version++;
  }

  /// The label naming [minute], laid out.
  TextPainter of(int minute) {
    return _labels.putIfAbsent(minute, () {
      return TextPainter(
        text: TextSpan(text: hourLabel(minute, _format), style: _style),
        textDirection: TextDirection.ltr,
        textScaler: _scaler,
        maxLines: 1,
      )..layout();
    });
  }

  /// The height every label lays out at.
  double get height {
    return of(0).height;
  }

  void dispose() {
    _clear();
  }

  void _clear() {
    for (final label in _labels.values) {
      label.dispose();
    }
    _labels.clear();
  }
}

/// Where the selected block's [_BlockHandles] register while they are
/// built, so a press outside the block reaches them from [TimedGrid]'s
/// listener.
class _HandlesSlot {
  _BlockHandlesState? current;
}

/// The cursor of a resize on [axis].
MouseCursor _resizeCursorOf(Axis axis) {
  return axis == Axis.vertical
      ? SystemMouseCursors.resizeUpDown
      : SystemMouseCursors.resizeLeftRight;
}

/// The selected block's outline and resize handles, over the block. Each
/// edge that resizes, the top, the bottom and, where [resizesDays], the
/// right, has a pill-shaped grip lying across its middle on the outline,
/// half outside the block, and takes a press on either side of it: inside
/// the block, a strip [depth] deep and never more than a third of the
/// block, so a short block keeps room to move by, takes the press
/// outright, the top and the bottom taking a corner, as the board's own
/// bands do; outside it, where the board hit-tests no part of the block,
/// [TimedGrid]'s listener hands a press up to [depth] away to
/// [_BlockHandlesState.startOutside] through [slot].
class _BlockHandles extends StatefulWidget {
  const _BlockHandles({
    super.key,
    required this.id,
    required this.slot,
    required this.resizesDays,
  });

  /// How far a resize press reaches from an edge into the block at most,
  /// and out of it.
  static const double depth = 12.0;

  /// The outline's width, on whose middle the grips lie.
  static const double outlineWidth = 2.0;

  /// A grip's length along its edge, at most three fifths of the edge.
  static const double gripLength = 24.0;

  static const double gripThickness = 8.0;

  /// The block's item, which names the grips' keys.
  final String id;

  final _HandlesSlot slot;
  final bool resizesDays;

  @override
  State<_BlockHandles> createState() {
    return _BlockHandlesState();
  }
}

class _BlockHandlesState extends State<_BlockHandles> {
  @override
  void initState() {
    super.initState();
    widget.slot.current = this;
  }

  @override
  void dispose() {
    // The block selected next may have registered first.
    if (identical(widget.slot.current, this)) {
      widget.slot.current = null;
    }
    super.dispose();
  }

  /// The edge, and its axis, whose strip outside the block, [depth] deep
  /// and as long as the edge, holds [global], or null.
  ({BoardResizeEdges edge, Axis axis})? _edgeOutsideAt(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return null;
    }
    final local = box.globalToLocal(global);
    final size = box.size;
    const depth = _BlockHandles.depth;
    if (local.dx >= 0.0 && local.dx <= size.width) {
      if (local.dy < 0.0 && local.dy >= -depth) {
        return (edge: BoardResizeEdges.leading, axis: Axis.vertical);
      }
      if (local.dy >= size.height && local.dy <= size.height + depth) {
        return (edge: BoardResizeEdges.trailing, axis: Axis.vertical);
      }
    }
    if (widget.resizesDays &&
        local.dy >= 0.0 &&
        local.dy <= size.height &&
        local.dx >= size.width &&
        local.dx <= size.width + depth) {
      return (edge: BoardResizeEdges.trailing, axis: Axis.horizontal);
    }
    return null;
  }

  /// Starts a resize for [event] where it lies on a strip outside the
  /// block, and reports whether it did.
  bool startOutside(PointerDownEvent event) {
    final strip = _edgeOutsideAt(event.position);
    final scope = context.getInheritedWidgetOfExactType<BoardItemDragScope>();
    if (strip == null || scope == null || !scope.canDrag) {
      return false;
    }
    scope.startDrag(
      event,
      _PromptMultiDragGestureRecognizer()
        ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context),
      strip.edge,
      strip.axis,
    );
    return true;
  }

  /// The resize cursor of the strip outside the block that holds
  /// [global], or [MouseCursor.defer] off them.
  MouseCursor cursorOutside(Offset global) {
    final strip = _edgeOutsideAt(global);
    return strip == null ? MouseCursor.defer : _resizeCursorOf(strip.axis);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final rows = math.min(_BlockHandles.depth, height / 3);
        final columns = math.min(_BlockHandles.depth, width / 3);
        final across = math.min(_BlockHandles.gripLength, width * 0.6);
        final down = math.min(_BlockHandles.gripLength, height * 0.6);
        // From the block's edge to a grip's near side, which centres the
        // grip on the outline's middle.
        const lead =
            _BlockHandles.outlineWidth / 2 - _BlockHandles.gripThickness / 2;
        final id = widget.id;
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.fromBorderSide(
                      BorderSide(
                        color: HarborColors.primary,
                        width: _BlockHandles.outlineWidth,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.resizesDays)
              Positioned(
                top: 0.0,
                right: 0.0,
                bottom: 0.0,
                width: columns,
                child: const _ResizeHandle(
                  edge: BoardResizeEdges.trailing,
                  axis: Axis.horizontal,
                ),
              ),
            Positioned(
              top: 0.0,
              left: 0.0,
              right: 0.0,
              height: rows,
              child: const _ResizeHandle(
                edge: BoardResizeEdges.leading,
                axis: Axis.vertical,
              ),
            ),
            Positioned(
              left: 0.0,
              right: 0.0,
              bottom: 0.0,
              height: rows,
              child: const _ResizeHandle(
                edge: BoardResizeEdges.trailing,
                axis: Axis.vertical,
              ),
            ),
            Positioned(
              top: lead,
              left: (width - across) / 2,
              width: across,
              height: _BlockHandles.gripThickness,
              child: _Grip(key: blockGripKey(id, AxisDirection.up)),
            ),
            Positioned(
              bottom: lead,
              left: (width - across) / 2,
              width: across,
              height: _BlockHandles.gripThickness,
              child: _Grip(key: blockGripKey(id, AxisDirection.down)),
            ),
            if (widget.resizesDays)
              Positioned(
                top: (height - down) / 2,
                right: lead,
                width: _BlockHandles.gripThickness,
                height: down,
                child: _Grip(key: blockGripKey(id, AxisDirection.right)),
              ),
          ],
        );
      },
    );
  }
}

/// A strip over the selected block that starts a resize of its [edge] on
/// [axis] at once, under its axis's resize cursor.
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.edge, required this.axis});

  final BoardResizeEdges edge;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _resizeCursorOf(axis),
      child: BoardDragHandle(
        edge: edge,
        axis: axis,
        behavior: HitTestBehavior.opaque,
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// A resize handle's grip: a pill filled with the primary colour, as the
/// outline it lies across is, ringed in the surface colour, which parts it
/// from the outline and the block's tint, over a soft shadow. Takes no
/// press: the strip under it and the grid's listener take them.
class _Grip extends StatelessWidget {
  const _Grip({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: HarborColors.primary,
          border: Border.fromBorderSide(
            BorderSide(color: HarborColors.surface, width: 1.5),
          ),
          borderRadius: BorderRadius.all(
            Radius.circular(_BlockHandles.gripThickness / 2),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 2.0,
              offset: Offset(0.0, 1.0),
            ),
          ],
        ),
      ),
    );
  }
}

/// A multi-drag recognizer for a press on a strip outside the selected
/// block, which lies over no handle: it wins the press's arena when the
/// arena closes, before the scrollable's drag can reach its slop, and
/// starts the drag at the pointer's first move, so a tap starts none.
class _PromptMultiDragGestureRecognizer extends MultiDragGestureRecognizer {
  _PromptMultiDragGestureRecognizer() : super(debugOwner: null);

  /// The state [addAllowedPointer] has just created, which it accepts.
  _PromptPointerState? _created;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    final state = _PromptPointerState(
      event.position,
      event.kind,
      gestureSettings,
    );
    _created = state;
    return state;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _created!.acceptNow();
    _created = null;
  }

  @override
  String get debugDescription {
    return "prompt multidrag";
  }
}

class _PromptPointerState extends MultiDragPointerState {
  _PromptPointerState(super.initialPosition, super.kind, super.gestureSettings);

  /// Starts the drag, once the arena has accepted the pointer; null until
  /// then and once the drag has started.
  GestureMultiDragStartCallback? _starter;

  /// Accepts the pointer while its arena is open, which makes this the
  /// arena's winner when it closes.
  void acceptNow() {
    resolve(GestureDisposition.accepted);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    _starter = starter;
  }

  @override
  void checkForResolutionAfterMove() {
    final starter = _starter;
    if (starter != null && pendingDelta != Offset.zero) {
      _starter = null;
      starter(initialPosition);
    }
  }
}
