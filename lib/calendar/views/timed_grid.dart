/// The calendar's timed grid: consecutive days on the board, with a frozen
/// hour gutter and, where it shows one, a frozen day header, one row per
/// 15-minute slot, and the days' entries as blocks, one per piece, the part
/// of an entry on one day, that in edit mode move, and once selected
/// resize.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../board/board.dart';
import '../dates/calendar_dates.dart';
import '../dates/calendar_labels.dart';
import '../entries/calendar_entry.dart';
import '../policy/history_lock.dart';
import '../policy/overlap.dart';
import '../presentation/calendar_builders.dart';
import '../presentation/calendar_defaults.dart';
import '../presentation/calendar_theme.dart';
import '../store/calendar_store.dart';
import 'pinch_zoom.dart';

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

/// The style the grid animates its blocks with under [theme]: every
/// family over its [CalendarThemeData.motionDuration] on its
/// [CalendarThemeData.motionCurve], and every family off at a zero
/// duration. The one site that declares the grid's motion.
BoardAnimationStyle timedGridAnimationStyleOf(CalendarThemeData theme) {
  return BoardAnimationStyle.uniform(
    BoardAnimationSpec(
      duration: theme.motionDuration,
      curve: theme.motionCurve,
    ),
  );
}

/// What a [TimedGrid] and the cells, blocks, labels and overlays it builds
/// draw and animate with, made from one [CalendarThemeData] by [forTheme]
/// and never changed.
@immutable
class _GridStyles {
  _GridStyles._(this.theme)
    : animation = timedGridAnimationStyleOf(theme),
      surfacePaint = Paint()..color = theme.surface,
      backgroundPaint = Paint()..color = theme.background,
      tintPaint = Paint()..color = theme.primaryTint,
      linePaint = Paint()
        ..color = theme.outline
        ..strokeWidth = 1.0,
      markEdgePaint = Paint()
        ..color = theme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
      nowPaint = Paint()
        ..color = theme.error
        ..strokeWidth = 2.0,
      surfaceBox = ColoredBox(color: theme.surface),
      hourLabel = theme.hourLabelStyle.copyWith(color: theme.textSecondary),
      headerWeekday = theme.dayHeaderWeekdayStyle.copyWith(
        color: theme.textSecondary,
      ),
      headerNumber = theme.dayHeaderNumberStyle.copyWith(color: theme.text),
      headerToday = theme.dayHeaderNumberStyle.copyWith(color: theme.primary),
      headerRing = BoxDecoration(
        border: Border.all(color: theme.todayRing, width: theme.todayRingWidth),
        borderRadius: BorderRadius.circular(10.0),
      ),
      hiddenPill = BoxDecoration(
        color: theme.primaryTint,
        borderRadius: BorderRadius.circular(10.0),
      ),
      hiddenLabel = theme.badgeStyle.copyWith(color: theme.primary),
      moreLabel = theme.noticeStyle.copyWith(color: theme.onNotice),
      noticeAbove = Icon(
        theme.beforeHoursIcon,
        size: _NoticeCell._arrowSize,
        color: theme.onNotice,
      ),
      noticeBelow = Icon(
        theme.afterHoursIcon,
        size: _NoticeCell._arrowSize,
        color: theme.onNotice,
      ),
      _noticeCells = _noticeCellsOf(theme),
      landing = BoxDecoration(
        color: theme.primary,
        borderRadius: BorderRadius.circular(16.0),
      ),
      landingLabel = theme.landingLabelStyle.copyWith(color: theme.onPrimary),
      scrim = theme.background.withValues(alpha: 0.85),
      selectionOutline = Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.fromBorderSide(
                BorderSide(
                  color: theme.primary,
                  width: _BlockHandles.outlineWidth,
                ),
              ),
            ),
          ),
        ),
      ),
      grip = IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.primary,
            border: Border.fromBorderSide(
              BorderSide(color: theme.surface, width: 1.5),
            ),
            borderRadius: const BorderRadius.all(
              Radius.circular(_BlockHandles.gripThickness / 2),
            ),
            boxShadow: theme.gripShadows,
          ),
        ),
      );

  /// The styles of [theme]: those made for it before, or for a theme `==`
  /// to it last, so an equal theme makes none.
  static _GridStyles forTheme(CalendarThemeData theme) {
    final kept = _memo[theme];
    if (kept != null) {
      return kept;
    }
    final last = _last;
    final styles = last != null && last.theme == theme
        ? last
        : _GridStyles._(theme);
    _memo[theme] = styles;
    _last = styles;
    return styles;
  }

  /// The styles of the theme above [context], which [context] then depends
  /// on.
  static _GridStyles of(BuildContext context) {
    return forTheme(CalendarTheme.of(context));
  }

  static Expando<_GridStyles> _memo = Expando<_GridStyles>();
  static _GridStyles? _last;

  /// Drops the styles made so far, which keep the code that made them
  /// across a hot reload, so the next read makes them again.
  static void _reset() {
    _memo = Expando<_GridStyles>();
    _last = null;
  }

  /// A notice cell's fill and rules, above the slots or below them, in the
  /// first day column or another: the rule faces the slots, and one parts
  /// each day from the one before.
  static List<BoxDecoration> _noticeCellsOf(CalendarThemeData theme) {
    final edge = BorderSide(color: theme.noticeOutline);
    return <BoxDecoration>[
      for (final above in const <bool>[true, false])
        for (final first in const <bool>[true, false])
          BoxDecoration(
            color: theme.notice,
            border: Border(
              left: first ? BorderSide.none : edge,
              top: above ? BorderSide.none : edge,
              bottom: above ? edge : BorderSide.none,
            ),
          ),
    ];
  }

  final CalendarThemeData theme;

  /// [timedGridAnimationStyleOf] [theme].
  final BoardAnimationStyle animation;

  /// The background's body, weekends, today's column and marked slots, its
  /// lines, the marks' edge, and the foreground's current-time line.
  final Paint surfacePaint;
  final Paint backgroundPaint;
  final Paint tintPaint;
  final Paint linePaint;
  final Paint markEdgePaint;
  final Paint nowPaint;

  /// A gutter cell and the corner over it.
  final Widget surfaceBox;

  /// The hour labels' own style, which the grid merges over the inherited
  /// one.
  final TextStyle hourLabel;

  /// A day header's weekday and number, today's, and today's ring.
  final TextStyle headerWeekday;
  final TextStyle headerNumber;
  final TextStyle headerToday;
  final BoxDecoration headerRing;

  /// The pill counting the items on no shown day.
  final BoxDecoration hiddenPill;
  final TextStyle hiddenLabel;

  /// A cell of the rows counting the items outside the hours.
  final TextStyle moreLabel;
  final Widget noticeAbove;
  final Widget noticeBelow;
  final List<BoxDecoration> _noticeCells;

  /// The pill naming where a drag lands.
  final BoxDecoration landing;
  final TextStyle landingLabel;

  /// The overlay while the days are not ready.
  final Color scrim;

  /// The selected block's outline, and its grips.
  final Widget selectionOutline;
  final Widget grip;

  /// The fill and rules of a notice cell [above] the slots or below them,
  /// in the [first] day column or another.
  BoxDecoration noticeCell({required bool above, required bool first}) {
    return _noticeCells[(above ? 0 : 2) + (first ? 0 : 1)];
  }
}

/// The key of the day header cell showing [day].
ValueKey<String> dayHeaderKey(DateTime day) {
  return ValueKey<String>("grid-day-${isoDate(day)}");
}

/// The key of the block showing the piece of the entry [id] on [day].
ValueKey<String> blockKey(String id, DateTime day) {
  return ValueKey<String>("block-$id@${isoDate(day)}");
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

/// What a screen reader hears for the pill counting [count] items on no
/// day the grid has a column for, before the pill's own "+N".
String hiddenEntriesLabel(int count) {
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

/// What the landing label says for a drag that would give an entry the
/// times [start] to [end]: its first day, as [dayTitle] names it against
/// [today], and its times ([entryTimesLabel]), as "Today, April 21,
/// 14:00-15:00"; for a range over more than one day its last day too, as
/// "Monday, April 20, 22:00 to Tuesday, April 21, 02:00"; and for an
/// all-day range its days and "all day".
String landingLabel(DateTime start, DateTime end, DateTime today) {
  final first = dayNumber(start);
  final last = lastDayNumberOf(start, end);
  final from = dayTitle(dateOfDayNumber(first), today);
  final to = dayTitle(dateOfDayNumber(last), today);
  if (isDayStart(start) && isDayStart(end)) {
    return first == last ? "$from, all day" : "$from to $to, all day";
  }
  if (first == last) {
    return "$from, ${entryTimesLabel(start, end)}";
  }
  return "$from, ${clockLabel(minuteOfDay(start))} to $to, "
      "${clockLabel(endMinuteOfDay(end))}";
}

/// The key of the shadow under the block a move carries.
const ValueKey<String> liftedBlockKey = ValueKey<String>("grid-lifted-block");

/// The time a create gesture picked: one continuous range from [start] to
/// [end], an exclusive end, both local times.
@immutable
class CreateRange {
  const CreateRange({required this.start, required this.end});

  /// Where the range starts.
  final DateTime start;

  /// Where the range ends, after [start].
  final DateTime end;

  /// Whether the range runs from a day start to a day start
  /// ([isDayStart]), covering whole days.
  bool get isAllDay {
    return isDayStart(start) && isDayStart(end);
  }

  @override
  bool operator ==(Object other) {
    return other is CreateRange && other.start == start && other.end == end;
  }

  @override
  int get hashCode {
    return Object.hash(start, end);
  }

  @override
  String toString() {
    return "CreateRange(${isoDate(start)} ${clockLabel(minuteOfDay(start))} "
        "to ${isoDate(end)} ${clockLabel(minuteOfDay(end))})";
  }
}

/// The key of a timed grid's board item: the entry [id] it shows, and for
/// a piece its day's offset from the entry's first day, so a one-day
/// entry's piece keeps its key on whatever day it moves to. Compared and
/// hashed by all three fields.
@immutable
class GridKey {
  /// The piece of the entry [id] [dayOffset] days after its first day.
  const GridKey.piece(this.id, this.dayOffset) : isBar = false;

  /// The bar of the all-day entry [id].
  const GridKey.bar(this.id) : isBar = true, dayOffset = 0;

  /// The entry the item shows.
  final String id;

  /// Whether the item is a bar rather than a piece.
  final bool isBar;

  /// The days from the entry's first day to the piece's; 0 for a bar.
  final int dayOffset;

  @override
  bool operator ==(Object other) {
    return other is GridKey &&
        other.id == id &&
        other.isBar == isBar &&
        other.dayOffset == dayOffset;
  }

  @override
  int get hashCode {
    return Object.hash(id, isBar, dayOffset);
  }

  @override
  String toString() {
    return isBar ? "GridKey.bar($id)" : "GridKey.piece($id, $dayOffset)";
  }
}

/// What a timed grid's board item shows of one shown entry.
@immutable
sealed class GridShape<T> {
  const GridShape();

  /// The entry the item shows.
  CalendarShownEntry<T> get shown;
}

/// The piece of [shown]'s entry on the [dayNumber] [day]: from [start] to
/// [end] minutes after that day's midnight ([pieceOn]), and whether it
/// holds the entry's start, [first], or its end, [last].
final class GridPiece<T> extends GridShape<T> {
  const GridPiece({
    required this.shown,
    required this.day,
    required this.start,
    required this.end,
    required this.first,
    required this.last,
  });

  @override
  final CalendarShownEntry<T> shown;

  /// The [dayNumber] of the piece's day.
  final int day;

  /// Minutes after the day's midnight, on the wall clock.
  final int start;

  /// Minutes after the day's midnight, on the wall clock, after [start].
  final int end;

  /// Whether the piece holds the entry's start.
  final bool first;

  /// Whether the piece holds the entry's end.
  final bool last;

  @override
  bool operator ==(Object other) {
    return other is GridPiece<T> &&
        other.shown == shown &&
        other.day == day &&
        other.start == start &&
        other.end == end &&
        other.first == first &&
        other.last == last;
  }

  @override
  int get hashCode {
    return Object.hash(shown, day, start, end, first, last);
  }

  @override
  String toString() {
    return "GridPiece(${shown.id}, ${isoDate(dateOfDayNumber(day))} "
        "${clockRangeLabel(start, end)})";
  }
}

/// Which day each column of a timed grid shows and which minute each of
/// its rows starts at.
///
/// Column 0 is the hour gutter, and the rows from [firstSlotRow] are the
/// slots of [hours], one per [minutesPerSlot]; the rows before it are
/// whatever the grid lays out above its slots, such as a day header or a
/// row counting the entries before the hours. The
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

/// Where the piece from [start] to [end] minutes of the day [column] shows
/// sits on the grid [tracks] lays out, in track space: its minutes clipped
/// to the grid's hours, one row per slot, a minute off the slot grid lying
/// as far into its slot's row as it lies into the slot, so 09:10 to 09:50
/// at 15-minute slots runs from 10/15 into the 09:00 row to 50/15 past its
/// top. Null where no minute of it is left.
BoardSpan? pieceSpanOf(GridTracks tracks, int column, int start, int end) {
  final hours = tracks.hours;
  final from = math.max(start, hours.start);
  final to = math.min(end, hours.end);
  if (to <= from) {
    return null;
  }
  const slot = minutesPerSlot;
  final into = from - hours.start;
  final length = to - from;
  return BoardSpan(
    rowStart: tracks.firstSlotRow + into ~/ slot,
    rowFraction: (into % slot) / slot,
    rowSpan: length ~/ slot,
    rowSpanFraction: (length % slot) / slot,
    colStart: column,
  );
}

/// The wall minute ([wallMinuteOf]) the slot of the body [cell] starts at
/// on the grid [tracks] lays out.
int slotWallMinuteOf(GridTracks tracks, ({int row, int col}) cell) {
  return tracks.dayAt(cell.col) * minutesPerDay + tracks.minuteAt(cell.row);
}

/// What a tap on the body [cell] creates: its one slot, or null where its
/// start or its end is a time the clock skips. On a day whose clock
/// repeats a stretch, each end is the earlier instant of its time.
CreateRange? createRangeAt(GridTracks tracks, ({int row, int col}) cell) {
  final start = slotWallMinuteOf(tracks, cell);
  return _createRangeOf(start, start + minutesPerSlot);
}

/// What a drag from the body cell [anchor] to [focus] creates: one
/// continuous range from the start of the earlier cell's slot, in
/// wall-minute order, to the end of the later one's, so Monday 10:00 to
/// Wednesday 12:00 gives Monday 10:00 to Wednesday 12:15, over every day
/// between, shown or not. Null where an end is a time the clock skips; on
/// a day whose clock repeats a stretch, each end is the earlier instant of
/// its time.
CreateRange? createRangeOver(
  GridTracks tracks,
  ({int row, int col}) anchor,
  ({int row, int col}) focus,
) {
  final from = slotWallMinuteOf(tracks, anchor);
  final to = slotWallMinuteOf(tracks, focus);
  return _createRangeOf(
    math.min(from, to),
    math.max(from, to) + minutesPerSlot,
  );
}

CreateRange? _createRangeOf(int startWall, int endWall) {
  final start = timeAtWallMinute(startWall);
  final end = timeAtWallMinute(endWall);
  if (start == null || end == null || !end.isAfter(start)) {
    return null;
  }
  return CreateRange(start: start, end: end);
}

/// The days of the [dayCount] from [firstDay] whose weekday [weekdays]
/// holds, on the board, over its [hours], showing what [store] shows for
/// them once they are ready. An entry shows as one block per piece, its
/// part on each shown day it covers, at its exact minutes, so an entry
/// from Monday 22:00 to Tuesday 02:00 shows one block at the end of
/// Monday and one at the start of Tuesday. Rows follow the wall clock: on
/// a day of 23 or 25 hours every column still has the same rows. A tap on
/// a block that is not pending reports [onOpenEntry] with its entry's id; a
/// tap on a day header reports [onSelectDay]. Each block's content is what
/// [blockBuilder] draws, told on a grid of one day column that the block
/// is detailed, and which of its ends the hours cut or continue on
/// another day.
///
/// In edit mode, which [editable] turns on, a long press on any block of
/// an entry lifts the entry to move and selects its blocks; a tap anywhere
/// but on a selected block, its entry leaving the grid, or edit mode
/// ending clears the selection. A move lands the lifted block's top on the
/// slot it is dropped on and moves the whole entry by the same elapsed
/// time, so it keeps its length; while it is lifted the entry's other
/// blocks leave the grid. Only the selected entry's blocks have resize
/// handles, over an outline: the top of the block holding its start drags
/// its start time, and the bottom of the block holding its end its end
/// time, each from a press on either side of the edge, where a pill lies
/// across it. A touch drag from another block's edge scrolls the grid as
/// one anywhere else does. A move, a resize or a create that lands on a
/// time the clock skips writes and reports nothing; one on a time it
/// repeats keeps the occurrence the gesture began in. Out of edit mode the
/// grid is read-only: no block moves or resizes, and an empty slot creates
/// nothing. In it the history lock [lockPast] and [lockEarlierToday]
/// choose holds too ([HistoryLock]): a block whose entry ended before the
/// lock's boundary takes no drag, one in progress neither moves nor has a
/// top handle, a long press selecting it, no move or resize lands an
/// entry, and no create gesture starts or reaches, before the boundary.
/// A move dropped onto another entry's time lands at the nearest free time
/// that shows, on that day or the day before or after it, and goes back
/// where there is none; a resize dragged onto one stops at its edge, and
/// so does a create's range. While a drag runs, a label over the grid
/// names the days and times a release would give, or that a move has
/// nowhere to land, and a move outlines the times it would land on. A line
/// over the blocks marks the time [now] holds in its day's column, and the
/// grid opens scrolled to the hour before it when it shows that day, at
/// 08:00 otherwise, with that hour's label whole below the top edge. Each
/// whole hour, and the start and the end of the hours, has a label centred
/// on its line in the hour gutter, in [hourLabelFormat], which a room above
/// the first slot and below the last, or the gutter beside a row counting
/// entries outside the hours, keeps whole. A piece reaching past the hours
/// shows its part inside them, and an entry whose start or end the hours
/// do not hold ([DayHours.holdsTimes]) takes no move or resize: only an
/// edit outside the grid changes it. A piece wholly outside them has no
/// block. While some are before the hours, a yellow row frozen against the
/// first slot, in place of the room above it, says "+N more" in the column
/// of each day with N of them, and while some are after them, a row frozen
/// against the last slot does; the hour gutter runs on beside both. An
/// entry on no shown day has no block either, and a pill in the day
/// header's corner counts it. In edit mode empty body cells take a create
/// gesture, reported through [onCreate]: a drag picks one continuous range
/// from the earlier of its two slots to the later, across days too, at
/// once with a mouse or a stylus and after a press and hold on touch, so a
/// touch drag without one scrolls the grid, and a tap, or a hold let go
/// where it began, picks its one slot. A slot that shares time with an
/// entry takes no create gesture. The range picked stays marked, as a
/// range being dragged is, until the create flow [onCreate] opens closes.
///
/// The day columns and the slot rows stretch to fill the grid, never
/// smaller than [minDayWidth] and [minSlotHeight]; past those, it scrolls.
/// A pinch of two fingers zooms the grid around the point between them,
/// reporting through [onZoom] the least sizes it zooms to, from the sizes
/// the grid shows: a pinch up and down the slot height, from
/// [minSlotHeightLow] to [minSlotHeightHigh], and one across, on more than
/// one day column, the day width, from [minDayWidthLow] to
/// [minDayWidthHigh]. While two fingers are down the grid does not scroll,
/// and a finger that pinched clears no selection when it lifts off the
/// selected block. No pinch starts while a block moves or resizes or a
/// create range runs. New days, which a new [firstDay], [dayCount] or
/// [weekdays] gives, end a create range in flight, which then creates
/// nothing.
///
/// With no [storeRange], the days are ready while the store's shown range
/// holds every one of them and its status is ready. With one, they are
/// ready while the store shows exactly [storeRange] and its status is
/// ready, or, while it shows another range, once it has read every day of
/// [storeRange]; a store notify that moves the store off [storeRange]
/// clears the selection. While its days are not ready a cover over the
/// grid takes every press, centring what [loadingBuilder] draws while they
/// are read, and what [failureBuilder] draws when the read the store waits
/// on failed, where that read is of the grid's own range: [storeRange],
/// or with none the store's shown range.
///
/// The grid draws in the [CalendarTheme] above it and animates on the
/// theme's motion; a block's content, the loading and the failure state
/// are what their builders draw, the module's defaults where they are
/// null.
class TimedGrid<T> extends StatefulWidget {
  const TimedGrid({
    super.key,
    required this.store,
    required this.firstDay,
    required this.dayCount,
    required this.selectedDay,
    required this.today,
    required this.now,
    required this.onSelectDay,
    required this.onOpenEntry,
    required this.onCreate,
    this.editable = false,
    this.lockPast = false,
    this.lockEarlierToday = false,
    this.weekdays = WeekdaySet.all,
    this.hours = DayHours.allDay,
    this.hourLabelFormat = HourLabelFormat.twentyFourHour,
    this.minDayWidth = minDayWidthLow,
    this.minSlotHeight = defaultMinSlotHeight,
    this.onZoom,
    this.maxDayCount,
    this.storeRange,
    this.showsDayHeader = true,
    this.blockBuilder,
    this.loadingBuilder,
    this.failureBuilder,
  }) : assert(dayCount >= 1),
       assert(
         minDayWidth > 0.0 && minDayWidth < double.infinity,
         "A TimedGrid's minDayWidth must be positive and finite.",
       ),
       assert(
         minSlotHeight > 0.0 && minSlotHeight < double.infinity,
         "A TimedGrid's minSlotHeight must be positive and finite.",
       );

  final CalendarStore<T> store;

  /// Whether row 0 is a frozen header naming each column's day, whose
  /// corner over the gutter holds the pill counting the items on no shown
  /// day. Fixed for the grid's life.
  final bool showsDayHeader;

  /// The first day of the range the grid shows.
  final DateTime firstDay;

  /// How many days the range holds. With [weekdays] it decides whether the
  /// grid shows one day column or more than one, which is fixed for the
  /// grid's life: give a grid that changes between them its own key.
  final int dayCount;

  final DateTime selectedDay;

  /// The day whose column and header the grid marks as today.
  final DateTime today;

  /// The current time, which its owner sets again at the start of each
  /// minute. The line marking it follows it without a rebuild from above;
  /// the history lock does not ([lockEarlierToday]).
  final ValueListenable<DateTime> now;

  final ValueChanged<DateTime> onSelectDay;

  /// Reports a tap on a block that is not pending, with its entry's id.
  final ValueChanged<String> onOpenEntry;

  /// Opens the create flow for the range a create gesture on empty cells
  /// picked, and completes when it closes.
  final Future<void> Function(CreateRange range) onCreate;

  /// Whether the grid is in edit mode: its blocks move and resize, and its
  /// empty slots take a create gesture. Out of it the grid is read-only,
  /// and no history lock holds.
  final bool editable;

  /// Whether, in edit mode, the history lock holds the days before
  /// [today] ([HistoryLock.of]).
  final bool lockPast;

  /// Whether, in edit mode and under [lockPast], the history lock holds
  /// [today] up to the minute [now] holds too ([HistoryLock.of]). The grid
  /// makes its lock only when it is built, so the lock's boundary moves
  /// with [now] only when the grid is built again: its owner builds it
  /// again each minute the boundary moves.
  final bool lockEarlierToday;

  /// The weekdays whose days the grid shows. At least one day of the range
  /// must fall on a shown weekday. With [dayCount] it decides whether the
  /// grid shows one day column or more than one, which is fixed for the
  /// grid's life: give a grid that changes between them its own key.
  final WeekdaySet weekdays;

  /// The hours the grid shows and its gestures schedule in, one row per
  /// slot.
  final DayHours hours;

  /// The format the hour gutter labels the times in.
  final HourLabelFormat hourLabelFormat;

  /// The least width of a day column, in logical pixels, positive and
  /// finite; the columns stretch past it to fill the grid. A pinch across
  /// reports through [onZoom] a width from [minDayWidthLow] to
  /// [minDayWidthHigh], so it moves a value outside them into them at its
  /// first report.
  final double minDayWidth;

  /// The least height of one slot, in logical pixels, positive and finite;
  /// the slots stretch past it to fill the grid. A pinch up and down
  /// reports through [onZoom] a height from [minSlotHeightLow] to
  /// [minSlotHeightHigh], so it moves a value outside them into them at
  /// its first report.
  final double minSlotHeight;

  /// Reports the least slot height and day width a pinch zooms to, which
  /// the grid shows once its owner builds it with them as [minSlotHeight]
  /// and [minDayWidth]; null for a grid no pinch zooms.
  final void Function(double minSlotHeight, double minDayWidth)? onZoom;

  /// The most days, counting each day it has any part of, that a create
  /// drag across days may give a range: one dragged past them is held at
  /// the latest range they admit. A move keeps the days an entry covers,
  /// except where it crosses a midnight, and no limit applies to it. Null
  /// for no limit.
  final int? maxDayCount;

  /// The range, both days inclusive, that the grid's owner asks [store] to
  /// show for it, which holds the grid's days; null where the grid reads
  /// the store's shown range alone. Where the store shows another range,
  /// as it does in the frame before the owner's ask reaches it, the grid
  /// is ready once the store has read every day of this one.
  final ({DateTime first, DateTime last})? storeRange;

  /// Draws each block's content inside the box the grid gives it; null
  /// for [defaultCalendarBlockBuilder]. A new one, not `==` to the last,
  /// draws every block again.
  final CalendarBlockBuilder<T>? blockBuilder;

  /// Draws the cover's content while the grid's days are read; null for
  /// [defaultCalendarLoadingBuilder].
  final CalendarLoadingBuilder? loadingBuilder;

  /// Draws the cover's content when the read of the grid's days failed;
  /// null for [defaultCalendarFailureBuilder].
  final CalendarFailureBuilder? failureBuilder;

  @override
  State<TimedGrid<T>> createState() {
    return _TimedGridState<T>();
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
  GridKey key,
  BoardDragKind kind,
  bool resolved,
  BoardSpan? target,
});

/// The pieces of the shown entries a sync split, in the store's order,
/// and the shown entries with no block, counted: the split [_TimedGridState]
/// keeps and places.
typedef _GridLayout<T> = ({List<GridPiece<T>> pieces, _Hidden hidden});

/// Where the line marking the current time sits: the column of its day
/// and its minute after midnight.
typedef _NowMark = ({int column, int minute});

class _TimedGridState<T> extends State<TimedGrid<T>>
    with TickerProviderStateMixin {
  late final BoardController<GridKey, GridShape<T>> _board;

  late final PinchTracker _pinch = PinchTracker(
    onStart: _startPinch,
    onUpdate: _pinchTo,
    onEnd: _endPinch,
  );

  /// The slot height and day width the grid showed when the running pinch
  /// started; null while none runs.
  ({double slot, double day})? _pinchFrom;

  /// Where the fingers of the pinch that last reported a zoom met, in the
  /// board viewport's coordinates, until the next fit of the axes holds
  /// the lattice there ([_holdPinchFocal]).
  Offset? _pinchFocal;

  final ScrollHolder _scrollHold = ScrollHolder();

  /// The rows counting the entries outside the hours that the grid lays
  /// out above and below its slots.
  _Notices _notices = (above: false, below: false);

  /// Where the widget's days and minutes sit on the board.
  late GridTracks _tracks = _tracksOf(widget);

  /// Held in fields because `Board` replaces its delegate, and so rebuilds
  /// every cell and item, whenever a builder it gets is not identical to
  /// the previous one. [didUpdateWidget] gives the board a new item
  /// builder for a new [TimedGrid.blockBuilder], so every block finds it.
  late final BoardCellBuilder<GridKey, GridShape<T>> _cellBuilder = _buildCell;
  late BoardItemBuilder<GridKey, GridShape<T>> _placementBuilder =
      _buildPlacement;

  /// [TimedGrid.blockBuilder], or the module's default where it is null.
  late CalendarBlockBuilder<T> _blockBuilder = _blockBuilderOf(widget);

  static CalendarBlockBuilder<T> _blockBuilderOf<T>(TimedGrid<T> widget) {
    return widget.blockBuilder ?? defaultCalendarBlockBuilder<T>;
  }

  /// One instance in edit mode and one out of it, so a rebuild of this
  /// state hands the board the config it already has. Out of edit mode the
  /// config is disabled, so no handle starts a drag, and turning it off
  /// cancels a drag that runs. The board builds no handles of its own:
  /// each block carries the handle that moves it after a long press, and
  /// the selected block the resize handles the config's edges admit
  /// ([_Block]). No block resizes its column edges: a piece's days are its
  /// entry's. Whether the grid has more than one column is fixed for its
  /// life, which [didUpdateWidget] asserts.
  ///
  /// A move [_canDropAt] refuses for meeting another entry slides to the
  /// placement nearest on screen that holds it clear, at any time that
  /// shows of the day it was dropped on or of the day before or after it,
  /// however busy the time around it is. A resize it refuses for meeting
  /// another entry stops its dragged edge at that entry. The drag reports
  /// keep [_drag], which the landing label and outline show. A drag's
  /// start plays a haptic, and the block a move carries casts a shadow.
  /// [_applyTheme] makes both again for a theme with another dragged-block
  /// opacity, which the board hands its live drag.
  late BoardDragConfig<GridKey> _editConfig;
  late BoardDragConfig<GridKey> _viewConfig;

  BoardDragConfig<GridKey> _dragConfigOf({required bool enabled}) {
    return BoardDragConfig<GridKey>(
      enabled: enabled,
      canDrag: _canDrag,
      canDropAt: _canDropAt,
      dropFit: const BoardDropFit(
        minFreeFraction: 0.0,
        rowRadius: double.infinity,
        colRadius: 1.0,
        clampResizes: true,
      ),
      onItemMoved: _commitMove,
      onItemResized: _commitResize,
      resizeEdges: BoardResizeEdges.none,
      primaryResizeEdges: BoardResizeEdges.both,
      buildDefaultDragHandles: false,
      draggedItemOpacity: _styles.theme.draggedBlockOpacity,
      dragProxyBuilder: _buildLiftedBlock,
      hapticsOnDrag: true,
      onDragStart: _handleDragStart,
      onDragTargetChanged: _handleDragTarget,
      onDragEnd: _handleDragEnd,
    );
  }

  /// The id of the entry whose block a long press last lifted, whose
  /// blocks all show selected and whose first and last blocks show its
  /// resize handles, or null. The blocks listen to it, as the item builder
  /// runs only when the board rebuilds an item.
  final ValueNotifier<String?> _selectedBlock = ValueNotifier<String?>(null);

  /// The selected entry's handles, while they are built.
  final _HandlesSlot _handles = _HandlesSlot();

  /// The entry a running move lifted, with the start and end it was
  /// lifted with, while it shows more than one piece: the placement step
  /// leaves out its pieces other than the dragged one while the shown
  /// entry keeps those times. Set by [_handleDragStart], cleared by
  /// [_handleDragEnd].
  ({String id, DateTime start, DateTime end})? _lifted;

  /// The last split [_layOutEntries] made, which [_placeLayout] places.
  late _GridLayout<T> _layout = (
    pieces: <GridPiece<T>>[],
    hidden: _Hidden.none(_tracks),
  );

  /// The history lock in edit mode, at the minute [TimedGrid.now] holds
  /// when the grid last built, and none out of it, where nothing changes.
  /// Its owner builds the grid again each minute a lock to now moves. The
  /// blocks listen to it.
  late final ValueNotifier<HistoryLock> _lock = ValueNotifier<HistoryLock>(
    _lockOf(widget),
  );

  static HistoryLock _lockOf<T>(TimedGrid<T> widget) {
    if (!widget.editable) {
      return HistoryLock.none;
    }
    return HistoryLock.of(
      lockPast: widget.lockPast,
      lockEarlierToday: widget.lockEarlierToday,
      today: widget.today,
      now: widget.now.value,
    );
  }

  /// The cursor over the strips outside the selected block that resize it,
  /// [MouseCursor.defer] anywhere else.
  final ValueNotifier<MouseCursor> _besideCursor = ValueNotifier<MouseCursor>(
    MouseCursor.defer,
  );

  /// The presses that went down off the selected entry's blocks, by
  /// pointer: where each went down, and the entry selected then. One let
  /// go within its slop of there, with that entry still selected, is a tap
  /// elsewhere, which clears the selection.
  final Map<int, ({Offset at, String id})> _pressesOff =
      <int, ({Offset at, String id})>{};

  /// The drag the board runs, or null.
  _GridDrag? _drag;

  /// The first and the last slot of the range whose create flow is open,
  /// which the background marks; null while none is.
  ({({int row, int col}) anchor, ({int row, int col}) focus})? _creating;

  /// Counts the create flows opened, so only the last one's close clears
  /// [_creating].
  int _creates = 0;

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
  late double _dayWidth = widget.minDayWidth;
  late double _slotHeight = widget.minSlotHeight;
  late int _columnCount = _tracks.columnCount;
  late DayHours _rowHours = _tracks.hours;
  double _rowRoom = _initialLabelRoom;
  late _Notices _rowNotices = _notices;
  late HourLabelFormat _rowFormat = widget.hourLabelFormat;

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

  /// The shown entries with no block, as the last [_sync] counted them.
  /// The pill counting those on no shown day and the cells of the rows
  /// counting those outside the hours listen to it, as the cell builder
  /// runs only when the board rebuilds a cell.
  late final ValueNotifier<_Hidden> _hiddenCount = ValueNotifier<_Hidden>(
    _Hidden.none(_tracks),
  );

  /// The hour labels the foreground paints, laid out for the style and
  /// text scale the last build found.
  final _HourLabels _hourLabels = _HourLabels();

  final GlobalKey _boardKey = GlobalKey();

  /// The board's viewport, found under [_boardKey] and kept while it is
  /// attached.
  RenderBoardViewport<GridKey>? _viewport;

  /// The create gestures. They live here rather than in the board, and are
  /// armed only for a press on an empty body cell, so a press on a block
  /// leaves the arena to the block's own move and resize gestures.
  late final TapGestureRecognizer _tap;
  late final ImmediateMultiDragGestureRecognizer _immediateRange;
  late final DelayedMultiDragGestureRecognizer _delayedRange;

  /// The range being dragged, which the background paints.
  _RangeDrag<T>? _range;

  /// Set when the grid's scroll ends and cleared by the next microtask. A
  /// touch down on a flinging grid ends the fling before the listener
  /// above the board sees that down, in the same dispatch, so the press
  /// that stopped the grid finds this set.
  bool _scrollJustStopped = false;

  /// Whether the last [_sync] found its days ready.
  bool _syncedReady = false;

  /// Whether the store has read every day of [TimedGrid.storeRange], and
  /// whether it shows exactly that range, as [_noteRange] last found them;
  /// both false with no range.
  bool _rangeRead = false;
  bool _showsRange = false;

  /// Whether a frame callback will put the styles' animation back.
  bool _restoreScheduled = false;

  /// What the grid draws and animates with; set by [_applyTheme].
  _GridStyles? _themed;

  _GridStyles get _styles {
    return _themed!;
  }

  @override
  void initState() {
    super.initState();
    _pinch.holding.addListener(_handleHolding);
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
    _board = BoardController<GridKey, GridShape<T>>(
      vsync: this,
      rows: _rowsConfig(),
      columns: _columnsConfig(),
      keyOf: _keyOf,
      // The first sync disables it and schedules the theme's.
      animationStyle: BoardAnimationStyle.disabled,
    );
    widget.store.addListener(_handleStore);
    widget.now.addListener(_handleNow);
    _noteRange();
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
  void didUpdateWidget(TimedGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.blockBuilder != oldWidget.blockBuilder) {
      _blockBuilder = _blockBuilderOf(widget);
      _placementBuilder = (context, view) {
        return _buildPlacement(context, view);
      };
    }
    final storeChanged = widget.store != oldWidget.store;
    if (storeChanged) {
      oldWidget.store.removeListener(_handleStore);
      widget.store.addListener(_handleStore);
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
    final range = _range;
    if (tracksChanged && range != null) {
      // Its cells are rows and columns of the tracks it began on.
      range.detach();
      _range = null;
    }
    if (!widget.editable) {
      _selectedBlock.value = null;
    }
    _lock.value = _lockOf(widget);
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
        (tracksChanged ||
            widget.editable != oldWidget.editable ||
            widget.lockPast != oldWidget.lockPast ||
            widget.lockEarlierToday != oldWidget.lockEarlierToday ||
            widget.weekdays != oldWidget.weekdays ||
            widget.hours != oldWidget.hours ||
            widget.hourLabelFormat != oldWidget.hourLabelFormat ||
            widget.minDayWidth != oldWidget.minDayWidth ||
            widget.minSlotHeight != oldWidget.minSlotHeight)) {
      _fitAxes(size);
    }
    final rangeChanged = widget.storeRange != oldWidget.storeRange;
    if (storeChanged || rangeChanged) {
      _noteRange();
    }
    if (storeChanged || tracksChanged || rangeChanged) {
      // New days are not ready yet, so they do not animate in either way;
      // new hours move every block at once.
      _sync(animate: !tracksChanged);
    }
  }

  static GridTracks _tracksOf<T>(TimedGrid<T> widget) {
    final tracks = GridTracks(
      firstDay: dayNumber(widget.firstDay),
      dayCount: widget.dayCount,
      weekdays: widget.weekdays,
      hours: widget.hours,
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
    _applyTheme();
  }

  @override
  void reassemble() {
    _GridStyles._reset();
    super.reassemble();
    _applyTheme();
  }

  /// Reads the styles of the theme above the grid; on new ones, makes both
  /// drag configs again where the dragged block's opacity changed, and
  /// gives the board their animation, unless a frame will put it back
  /// after a sync that disabled it, so that sync's motion stays off.
  void _applyTheme() {
    final styles = _GridStyles.of(context);
    final old = _themed;
    if (identical(styles, old)) {
      return;
    }
    _themed = styles;
    if (old == null ||
        old.theme.draggedBlockOpacity != styles.theme.draggedBlockOpacity) {
      _editConfig = _dragConfigOf(enabled: true);
      _viewConfig = _dragConfigOf(enabled: false);
    }
    if (!_restoreScheduled) {
      _board.animationStyle = styles.animation;
    }
  }

  @override
  void dispose() {
    widget.now.removeListener(_handleNow);
    _pinch.dispose();
    _scrollHold.release();
    _tap.dispose();
    _immediateRange.dispose();
    _delayedRange.dispose();
    _range?.detach();
    widget.store.removeListener(_handleStore);
    _header.dispose();
    _hiddenCount.dispose();
    _selectedBlock.dispose();
    _lock.dispose();
    _besideCursor.dispose();
    _hourLabels.dispose();
    // The board has unmounted by now, so nothing still listens to the
    // controller.
    _board.dispose();
    super.dispose();
  }

  /// The board key of [shape]: a piece's is its entry's id and its day's
  /// offset from the entry's first day.
  static GridKey _keyOf<T>(GridShape<T> shape) {
    switch (shape) {
      case GridPiece<T>(:final shown, :final day):
        return GridKey.piece(shown.id, day - dayNumber(shown.entry.start));
    }
  }

  /// The slots of the hours, [_slotHeight] each, under the frozen day
  /// header where the grid shows one. Above the slots a row of
  /// [_labelRoom], or the frozen row counting the entries before the hours
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
    _rowFormat = widget.hourLabelFormat;
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

  /// The row counting the entries before the hours, or null where
  /// [_notices] has none.
  int? get _rowAbove {
    return _notices.above ? _tracks.firstSlotRow - 1 : null;
  }

  /// The row counting the entries after the hours, or null where
  /// [_notices] has none.
  int? get _rowBelow {
    return _notices.below ? _tracks.lastSlotRow + 1 : null;
  }

  /// Column 0 is the frozen hour gutter; columns 1 onward are the days
  /// [_tracks] shows. The `laneExtent` makes the day axis the
  /// lane axis, so pieces sharing a day's time sit side by side. No two
  /// stored entries do, but a failed move can return an entry under
  /// another entry's pending move until the store refuses that one.
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
  /// height, each stretched to fill it and never smaller than
  /// [TimedGrid.minDayWidth] and [TimedGrid.minSlotHeight]. Called from the
  /// layout callback, so the
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
    final oldRows = _board.rows;
    final oldColumns = _board.columns;
    final dayWidth = math.max(
      widget.minDayWidth,
      _share(size.width - _gutterWidth, _tracks.columnCount),
    );
    final slotHeight = math.max(
      widget.minSlotHeight,
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
        widget.hourLabelFormat != _rowFormat) {
      _slotHeight = slotHeight;
      _replaceRows();
    }
    _holdPinchFocal(oldRows, oldColumns);
  }

  /// Keeps the lattice point under [_pinchFocal] there across the axes
  /// that replaced [oldRows] and [oldColumns] ([holdFocalAcrossAxisSwap]),
  /// and clears it.
  void _holdPinchFocal(BoardAxisConfig oldRows, BoardAxisConfig oldColumns) {
    final focal = _pinchFocal;
    final viewport = _findViewport();
    if (focal == null || viewport == null) {
      return;
    }
    _pinchFocal = null;
    final vertical = viewport.verticalPosition;
    if (vertical != null && !identical(oldRows.axis, _board.rows.axis)) {
      holdFocalAcrossAxisSwap(
        vertical,
        old: oldRows.axis,
        next: _board.rows.axis,
        band: _leadingExtent,
        focal: focal.dy,
      );
    }
    final horizontal = viewport.horizontalPosition;
    if (horizontal != null &&
        !identical(oldColumns.axis, _board.columns.axis)) {
      holdFocalAcrossAxisSwap(
        horizontal,
        old: oldColumns.axis,
        next: _board.columns.axis,
        band: _gutterWidth,
        focal: focal.dx,
      );
    }
  }

  /// Starts a pinch from the sizes the grid shows, unless a block moves
  /// or resizes or a create range runs.
  bool _startPinch(PinchAxis axis, Offset focal) {
    if (_range != null || _drag != null) {
      return false;
    }
    _pinchFrom = (slot: _slotHeight, day: _dayWidth);
    return true;
  }

  /// Reports through [TimedGrid.onZoom] the least size the pinch zooms its
  /// axis to, its scale times the size shown at its start, from
  /// [minSlotHeightLow] to [minSlotHeightHigh] or from [minDayWidthLow] to
  /// [minDayWidthHigh], and notes where its fingers meet for the fit that
  /// follows. On one day column a pinch across zooms nothing.
  void _pinchTo(PinchUpdate update) {
    final from = _pinchFrom;
    final onZoom = widget.onZoom;
    final viewport = _findViewport();
    if (from == null || onZoom == null || viewport == null) {
      return;
    }
    var slot = widget.minSlotHeight;
    var day = widget.minDayWidth;
    switch (update.axis) {
      case PinchAxis.vertical:
        slot = (from.slot * update.scale).clamp(
          minSlotHeightLow,
          minSlotHeightHigh,
        );
      case PinchAxis.horizontal:
        if (_tracks.columnCount == 1) {
          return;
        }
        day = (from.day * update.scale).clamp(minDayWidthLow, minDayWidthHigh);
    }
    if (slot == widget.minSlotHeight && day == widget.minDayWidth) {
      return;
    }
    _pinchFocal = viewport.globalToLocal(update.focal);
    onZoom(slot, day);
  }

  void _endPinch() {
    _pinchFrom = null;
  }

  /// Holds the board's scrolling while two fingers are down, unless a
  /// block drag or a create range runs, which no pinch starts beside, and
  /// lets it go after.
  void _handleHolding() {
    final viewport = _findViewport();
    if (_pinch.holding.value && _range == null && _drag == null) {
      _scrollHold.hold(<ScrollPosition?>[
        viewport?.verticalPosition,
        viewport?.horizontalPosition,
      ]);
    } else {
      _scrollHold.release();
    }
  }

  /// One of [count] equal shares of [extent], or 0 when it is unbounded.
  static double _share(double extent, int count) {
    if (!extent.isFinite) {
      return 0.0;
    }
    return extent / count;
  }

  /// Follows the store. A notify that moves it off the range it showed
  /// for this grid clears the selection: the grid's owner, which moved it,
  /// builds the grid on the days of its new range next. A create range in
  /// flight reads the entries it is held by again.
  void _handleStore() {
    final showedRange = _showsRange;
    _noteRange();
    if (showedRange && !_showsRange) {
      _selectedBlock.value = null;
    }
    _sync();
    _range?.readConflicts();
    setState(() {});
  }

  /// Notes whether the store has read every day of [TimedGrid.storeRange]
  /// and whether it shows exactly that range, which [_daysReady] and
  /// [_handleStore] read, so a layout reads fields rather than the store's
  /// days.
  void _noteRange() {
    final range = widget.storeRange;
    final store = widget.store;
    if (range == null) {
      _rangeRead = false;
      _showsRange = false;
      return;
    }
    _showsRange = store.isShown(range.first, range.last);
    _rangeRead = _everyDayRead(store, range.first, range.last);
  }

  static bool _everyDayRead<T>(
    CalendarStore<T> store,
    DateTime first,
    DateTime last,
  ) {
    for (var day = first; !day.isAfter(last); day = addDays(day, 1)) {
      if (!store.isRead(day)) {
        return false;
      }
    }
    return true;
  }

  DateTime get _lastDay {
    return dateOfDayNumber(_tracks.lastDay);
  }

  /// Whether this grid's days are ready. With no [TimedGrid.storeRange],
  /// while the store's shown range holds every one of them, all read: the
  /// range may be wider than the grid, as a range holding the grid's whole
  /// week is, and a sync that runs between the store taking a range
  /// without this grid's days and this grid getting new ones finds them
  /// not ready. With one, while the store shows exactly that range, ready,
  /// and while it shows another, once every day of that range is read,
  /// which is the status the store takes when it shows it.
  bool get _daysReady {
    final store = widget.store;
    final range = widget.storeRange;
    if (range == null) {
      return store.status == CalendarLoadStatus.ready &&
          store.isWithinShown(widget.firstDay, _lastDay);
    }
    if (store.isShown(range.first, range.last)) {
      return store.status == CalendarLoadStatus.ready;
    }
    return _rangeRead;
  }

  /// Splits the days' shown entries when the days are ready, and none
  /// otherwise ([_layOutEntries]), lays out the rows counting those
  /// outside the hours before the pieces, so they fit the lattice they land
  /// on, and places the split ([_placeLayout]). A sync animates only when
  /// [animate] holds, its days are ready, the last sync found its own days
  /// ready and the rows stay as they were; any other runs under
  /// [BoardAnimationStyle.disabled], and so does every sync until a frame
  /// callback restores the styles' animation. New days reach this grid
  /// through [didUpdateWidget], whose sync does not animate, and a sync
  /// that finds them not read yet leaves [_syncedReady] false, so the sync
  /// the read's completion runs does not animate either.
  void _sync({bool animate = true}) {
    final ready = _daysReady;
    final shown = ready
        ? widget.store.entriesBetween(widget.firstDay, _lastDay)
        : <CalendarShownEntry<T>>[];
    final layout = _layOutEntries(shown);
    _layout = layout;
    final hidden = layout.hidden;
    final relaid = _layOutNotices((
      above: hidden.rowAbove,
      below: hidden.rowBelow,
    ));
    _placeLayout(disable: !(animate && ready && _syncedReady && !relaid));
    final selected = _selectedBlock.value;
    if (selected != null &&
        !layout.pieces.any((piece) {
          return piece.shown.id == selected;
        })) {
      _selectedBlock.value = null;
    }
    _syncedReady = ready;
    _hiddenCount.value = hidden;
  }

  /// The split of [shown] on [_tracks]: for each timed entry, and in this
  /// grid each all-day one too, its piece on each shown day it covers
  /// ([pieceOn]) that has a minute inside the hours, walking only the
  /// columns from its first day's to its last day's, so it yields at most
  /// one piece per shown day; and the entries with no block, counted: on
  /// each day column the pieces wholly before its hours and those wholly
  /// after them, and the entries on no day it has a column for.
  _GridLayout<T> _layOutEntries(List<CalendarShownEntry<T>> shown) {
    final tracks = _tracks;
    final hours = tracks.hours;
    final pieces = <GridPiece<T>>[];
    final above = List<int>.filled(tracks.columnCount, 0);
    final below = List<int>.filled(tracks.columnCount, 0);
    var offDays = 0;
    for (final entry in shown) {
      final start = entry.entry.start;
      final end = entry.entry.end;
      final firstDay = dayNumber(start);
      final lastDay = lastDayNumberOf(start, end);
      final first = tracks.firstColumnFrom(firstDay);
      final last = tracks.lastColumnUpTo(lastDay);
      if (last < first) {
        offDays++;
        continue;
      }
      final span = wallSpanOf(start, end);
      for (var column = first; column <= last; column++) {
        final day = tracks.dayAt(column);
        final piece = pieceOn(span, day);
        if (piece == null) {
          continue;
        }
        if (piece.end <= hours.start) {
          above[column - 1]++;
        } else if (piece.start >= hours.end) {
          below[column - 1]++;
        } else {
          pieces.add(
            GridPiece<T>(
              shown: entry,
              day: day,
              start: piece.start,
              end: piece.end,
              first: day == firstDay,
              last: day == lastDay,
            ),
          );
        }
      }
    }
    return (pieces: pieces, hidden: _Hidden(tracks, above, below, offDays));
  }

  /// Turns the kept split into the board's items on the current tracks,
  /// leaving out, while [_lifted] names an entry the split still shows
  /// with the times it was lifted with, that entry's pieces other than the
  /// dragged one. Under [BoardAnimationStyle.disabled] where [disable]
  /// holds and where the placements drop the key a drag holds, so that key
  /// leaves with no exit and what replaces it shows at once, until a frame
  /// callback restores the styles' animation; otherwise under the board's
  /// style as it stands, so a drop's glide runs on.
  void _placeLayout({required bool disable}) {
    final lifted = _lifted;
    final dragged = _drag?.key;
    final placements = <BoardPlacement<GridShape<T>>>[];
    var keepsDragged = false;
    for (final piece in _layout.pieces) {
      final column = _tracks.columnOf(piece.day);
      if (column == null) {
        continue;
      }
      final span = pieceSpanOf(_tracks, column, piece.start, piece.end);
      if (span == null) {
        continue;
      }
      final entry = piece.shown.entry;
      if (lifted != null &&
          piece.shown.id == lifted.id &&
          entry.start == lifted.start &&
          entry.end == lifted.end &&
          _keyOf(piece) != dragged) {
        continue;
      }
      if (dragged != null && !keepsDragged && _keyOf(piece) == dragged) {
        keepsDragged = true;
      }
      placements.add(BoardPlacement<GridShape<T>>(piece, span));
    }
    final dropsDragged =
        dragged != null && !keepsDragged && _board.contains(dragged);
    final disabled = disable || dropsDragged;
    if (disabled) {
      _board.animationStyle = BoardAnimationStyle.disabled;
    }
    _board.setItems(placements);
    if (disabled) {
      _scheduleStyleRestore();
    }
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

  /// Puts the styles' animation back in a frame callback scheduled
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
        _board.animationStyle = _styles.animation;
      }
    });
  }

  /// Whether the board may lift [key]: not while a write on its entry
  /// runs, and not when the hours do not hold the entry's start or end
  /// ([DayHours.holdsTimes]), as for an entry an hours change left outside
  /// them, whose cut-off minutes a drop would lose.
  bool _canDrag(GridKey key) {
    if (widget.store.isPending(key.id)) {
      return false;
    }
    final shape = _board.itemOf(key);
    if (shape == null) {
      return false;
    }
    final entry = shape.shown.entry;
    return _tracks.hours.holdsTimes(entry.start, entry.end);
  }

  bool _canDropAt(GridKey key, BoardSpan span) {
    // A piece stays inside its day's rows.
    if (span.rowStart < _tracks.firstSlotRow ||
        span.endTrackOn(Axis.vertical) >
            _tracks.lastSlotRow + 1 + precisionErrorTolerance ||
        span.colStart < 1) {
      return false;
    }
    final from = _board.spanOf(key);
    final shape = _board.itemOf(key);
    if (from == null || shape is! GridPiece<T>) {
      return false;
    }
    // The span the drag started from: an unchanged drop is admitted even
    // where the entry already shares its time.
    if (from == span) {
      return true;
    }
    final entry = shape.shown.entry;
    final times = _timesOf(shape, entry, from, span, move: _isMove(key));
    if (times == null ||
        !_lock.value.admits(entry.start, entry.end, times.start, times.end) ||
        !_tracks.hours.holdsTimes(times.start, times.end)) {
      return false;
    }
    return !_meetsOtherEntry(key.id, times.start, times.end);
  }

  /// Whether the running drag of [key], or with none a semantics action's
  /// report, moves it rather than resizing it.
  bool _isMove(GridKey key) {
    final drag = _drag;
    if (drag == null || drag.key != key) {
      return true;
    }
    return drag.kind == BoardDragKind.move;
  }

  /// Whether a range from [start] to [end] shares time with a board piece
  /// of an entry other than [id] in the shown columns it covers. An
  /// all-day range shares time with none ([entriesShareTime]).
  bool _meetsOtherEntry(String id, DateTime start, DateTime end) {
    if (isDayStart(start) && isDayStart(end)) {
      return false;
    }
    final first = _tracks.firstColumnFrom(dayNumber(start));
    final last = _tracks.lastColumnUpTo(lastDayNumberOf(start, end));
    final span = wallSpanOf(start, end);
    for (var column = first; column <= last; column++) {
      final piece = pieceOn(span, _tracks.dayAt(column));
      if (piece == null) {
        continue;
      }
      final shown = pieceSpanOf(_tracks, column, piece.start, piece.end);
      if (shown == null) {
        continue;
      }
      final others = _board.itemsIn(
        shown.rowStart,
        (shown.endTrackOn(Axis.vertical) - precisionErrorTolerance).ceil(),
        column,
        column + 1,
      );
      for (final other in others) {
        if (other.id == id) {
          continue;
        }
        final occupant = _board.itemOf(other);
        if (occupant != null &&
            rangeSharesTime(start, end, occupant.shown.entry)) {
          return true;
        }
      }
    }
    return false;
  }

  /// The start and end a drag of [piece] of [entry] from [from] to [to],
  /// both track space, gives the entry, or null where the drag lands on a
  /// time the clock skips or leaves the end not after the start.
  ///
  /// A [move] lands the piece's shown top, its anchor, on the slot [to]
  /// starts on: the anchor is the entry's start for a piece holding it and
  /// not cut by the hours, and otherwise the time the piece's top shows,
  /// its day's start or the hours' start. The landing is the time of
  /// [to]'s start on its column's day, the occurrence of the anchor's kept
  /// on a day whose clock repeats a stretch ([timeAtWallMinute]), and the
  /// entry's start and end each move by the elapsed time from the anchor
  /// to the landing, so the entry keeps its length. A resize sets the end
  /// whose edge [to] moved off [from]'s to the time of that edge on the
  /// piece's day, the occurrence of the old end's kept likewise.
  ({DateTime start, DateTime end})? _timesOf(
    GridPiece<T> piece,
    CalendarEntry<T> entry,
    BoardSpan from,
    BoardSpan to, {
    required bool move,
  }) {
    final hours = _tracks.hours;
    int wallAt(int column, double track) {
      return _tracks.dayAt(column) * minutesPerDay +
          hours.start +
          ((track - _tracks.firstSlotRow) * minutesPerSlot).round();
    }

    if (move) {
      final cut = piece.start < hours.start;
      final anchor = piece.first && !cut
          ? entry.start
          : timeAtWallMinute(
              piece.day * minutesPerDay + math.max(piece.start, hours.start),
            );
      if (anchor == null) {
        return null;
      }
      final landing = timeAtWallMinute(
        wallAt(to.colStart, to.startTrackOn(Axis.vertical)),
        from: anchor,
      );
      if (landing == null) {
        return null;
      }
      final shift = landing.difference(anchor);
      return (start: entry.start.add(shift), end: entry.end.add(shift));
    }
    var start = entry.start;
    var end = entry.end;
    final column = from.colStart;
    final top = to.startTrackOn(Axis.vertical);
    if ((top - from.startTrackOn(Axis.vertical)).abs() >
        precisionErrorTolerance) {
      final edge = timeAtWallMinute(wallAt(column, top), from: entry.start);
      if (edge == null) {
        return null;
      }
      start = edge;
    }
    final bottom = to.endTrackOn(Axis.vertical);
    if ((bottom - from.endTrackOn(Axis.vertical)).abs() >
        precisionErrorTolerance) {
      final edge = timeAtWallMinute(wallAt(column, bottom), from: entry.end);
      if (edge == null) {
        return null;
      }
      end = edge;
    }
    if (!end.isAfter(start)) {
      return null;
    }
    return (start: start, end: end);
  }

  /// A move the board reports, from a drag or a semantics action.
  void _commitMove(GridKey key, BoardSpan to) {
    _commit(key, to, move: true);
  }

  /// A resize the board reports.
  void _commitResize(GridKey key, BoardSpan to) {
    _commit(key, to, move: false);
  }

  /// Writes the drop of [key] at [to]. Sends nothing for a pending entry,
  /// for one whose start or end the hours do not hold, for a drop
  /// [_timesOf] has no times for, and when the entry would not change; a
  /// locked entry the board's semantics move action can report, when it
  /// locked after its host last built, the store's own lock refuses.
  void _commit(GridKey key, BoardSpan to, {required bool move}) {
    if (widget.store.isPending(key.id)) {
      return;
    }
    final from = _board.spanOf(key);
    final shape = _board.itemOf(key);
    final stored = widget.store.storedEntry(key.id);
    if (from == null ||
        shape is! GridPiece<T> ||
        stored == null ||
        !_tracks.hours.holdsTimes(stored.start, stored.end)) {
      return;
    }
    final times = _timesOf(shape, stored, from, to, move: move);
    if (times == null) {
      return;
    }
    final requested = stored.copyWith(start: times.start, end: times.end);
    if (requested == stored) {
      return;
    }
    widget.store.requestMove(requested);
  }

  void _handleDragStart(GridKey key, BoardDragKind kind) {
    if (!mounted) {
      return;
    }
    if (kind == BoardDragKind.move) {
      _selectedBlock.value = key.id;
    }
    setState(() {
      _drag = (key: key, kind: kind, resolved: false, target: null);
    });
    final shape = _board.itemOf(key);
    if (kind != BoardDragKind.move || shape == null) {
      return;
    }
    final id = key.id;
    final pieced = _layout.pieces.any((piece) {
      return piece.shown.id == id && _keyOf(piece) != key;
    });
    if (!pieced) {
      return;
    }
    // Off the board, the entry's other pieces are no occupant the
    // make-room preview or the drop fit reads, and they leave at once.
    final entry = shape.shown.entry;
    _lifted = (id: id, start: entry.start, end: entry.end);
    _placeLayout(disable: true);
  }

  void _handleDragTarget(GridKey key, BoardDropTarget? target) {
    final drag = _drag;
    if (!mounted || drag == null || drag.key != key) {
      return;
    }
    setState(() {
      _drag = (key: key, kind: drag.kind, resolved: true, target: target?.span);
    });
  }

  /// Delivered after the drop's report, and possibly after the board has
  /// left the tree. Puts back a lifted entry's pieces the drop's write
  /// did not, under the board's style as it stands, so a drop's glide runs
  /// on and they enter as added blocks do.
  void _handleDragEnd(GridKey key, bool committed) {
    if (!mounted || _drag == null) {
      return;
    }
    setState(() {
      _drag = null;
    });
    if (_lifted != null) {
      _lifted = null;
      _placeLayout(disable: false);
    }
  }

  /// The block a move carries, [proxy], over the theme's
  /// [CalendarThemeData.liftedBlockShadows], which ease in from none over
  /// the theme's motion. The board calls this on every pointer move with a
  /// tree of the same shape, so the lift runs once a drag, from the frame
  /// the block lifts.
  Widget _buildLiftedBlock(BuildContext context, GridKey key, Widget proxy) {
    final theme = _styles.theme;
    final shadows = theme.liftedBlockShadows;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: theme.motionDuration,
      curve: theme.motionCurve,
      child: proxy,
      builder: (context, lift, child) {
        return DecoratedBox(
          key: liftedBlockKey,
          decoration: BoxDecoration(
            boxShadow: <BoxShadow>[
              for (final shadow in shadows)
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

  /// The times a release of [_drag] would give its entry: null with no
  /// drag, before its first target, and with no target.
  ({DateTime start, DateTime end})? _landingTimes() {
    final drag = _drag;
    final target = drag?.target;
    if (drag == null || !drag.resolved || target == null) {
      return null;
    }
    final from = _board.spanOf(drag.key);
    final shape = _board.itemOf(drag.key);
    if (from == null || shape is! GridPiece<T>) {
      return null;
    }
    return _timesOf(
      shape,
      shape.shown.entry,
      from,
      target,
      move: drag.kind == BoardDragKind.move,
    );
  }

  /// What the landing label says for [_drag]: the days and times a release
  /// would give, or [noLandingLabel] for a move with no target. Null with
  /// no drag, before its first target, and for a resize with no target.
  String? _landingText(({DateTime start, DateTime end})? times) {
    final drag = _drag;
    if (drag == null || !drag.resolved) {
      return null;
    }
    if (drag.target == null) {
      return drag.kind == BoardDragKind.move ? noLandingLabel : null;
    }
    if (times == null) {
      return null;
    }
    return landingLabel(times.start, times.end, widget.today);
  }

  /// Where the line marking [now] sits: null when no column shows its day
  /// or the hours do not hold its minute.
  _NowMark? _nowMarkOf(DateTime now) {
    final column = _tracks.columnOf(dayNumber(now));
    final minute = minuteOfDay(now);
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

  RenderBoardViewport<GridKey>? _findViewport() {
    final cached = _viewport;
    if (cached != null && cached.attached) {
      return cached;
    }
    _viewport = null;
    final root = _boardKey.currentContext?.findRenderObject();
    if (root == null) {
      return null;
    }
    RenderBoardViewport<GridKey>? found;
    void visit(RenderObject node) {
      if (found != null) {
        return;
      }
      if (node is RenderBoardViewport<GridKey>) {
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
    RenderBoardViewport<GridKey> viewport,
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
  /// body cell whose slot is a time the clock reads and the history lock
  /// leaves free, no block paints under it, no shown entry shares time
  /// with its slot, as one from 09:10 does with the 09:00 slot whose free
  /// part the press lies in, and the grid is neither scrolling nor just
  /// stopped by this press.
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
    final cell = _bodyCellAtLocal(viewport, local);
    if (cell == null) {
      return false;
    }
    final slot = createRangeAt(_tracks, cell);
    return slot != null &&
        _lock.value.admitsStart(slot.start) &&
        viewport.itemAt(local) == null &&
        !_slotMeetsEntry(cell, slot);
  }

  /// Whether a board piece in [cell]'s row and column shares time with
  /// [slot], the cell's slot.
  bool _slotMeetsEntry(({int row, int col}) cell, CreateRange slot) {
    final keys = _board.itemsIn(cell.row, cell.row + 1, cell.col, cell.col + 1);
    for (final key in keys) {
      final shape = _board.itemOf(key);
      if (shape != null &&
          rangeSharesTime(slot.start, slot.end, shape.shown.entry)) {
        return true;
      }
    }
    return false;
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
  /// other press off it for [_handlePointerUp], and in edit mode arms the
  /// create gestures for an admitted press. A listener's pointer down runs
  /// before the arena closes, so they join it beside the scrollable's pan;
  /// each recognizer ignores the pointer kinds it does not support.
  void _handlePointerDown(PointerDownEvent event) {
    _pinch.handleEvent(event);
    final selected = _selectedBlock.value;
    if (selected != null) {
      final under = _keyAt(event.position);
      if (under == null && _startBeside(event)) {
        return;
      }
      if (under?.id != selected) {
        _pressesOff[event.pointer] = (at: event.position, id: selected);
      }
    }
    if (!widget.editable || !_admits(event.position)) {
      return;
    }
    _tap.addPointer(event);
    _immediateRange.addPointer(event);
    _delayedRange.addPointer(event);
  }

  /// Clears the selection for a tap off the selected entry's blocks, which
  /// a press lifting another block, and so selecting it, is not.
  void _handlePointerUp(PointerUpEvent event) {
    _pinch.handleEvent(event);
    final press = _pressesOff.remove(event.pointer);
    if (press == null ||
        _pinch.pinched.value ||
        _selectedBlock.value != press.id) {
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
    _pinch.handleEvent(event);
    _pressesOff.remove(event.pointer);
  }

  /// Starts a resize of a selected block for a press over a body cell,
  /// and over no block, on a strip outside a selected block holding a
  /// handle beside one of its edges, which the board, hit-testing a block
  /// only within its bounds, gives no handle; reports whether it did.
  bool _startBeside(PointerDownEvent event) {
    return !_handles.isEmpty &&
        _bodyCellAt(event.position) != null &&
        _handles.startOutside(event);
  }

  /// Shows the resize cursor over the strips [_startBeside] starts from.
  void _handleHover(PointerHoverEvent event) {
    var cursor = MouseCursor.defer;
    if (!_handles.isEmpty &&
        _selectedBlock.value != null &&
        _keyAt(event.position) == null &&
        _bodyCellAt(event.position) != null) {
      cursor = _handles.cursorOutside(event.position);
    }
    _besideCursor.value = cursor;
  }

  /// The key of the block that lies under [global], or null.
  GridKey? _keyAt(Offset global) {
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
    final range = createRangeAt(_tracks, cell);
    if (range == null) {
      return;
    }
    _create(cell, cell, range);
  }

  /// Reports [range] through [TimedGrid.onCreate], marking the range from
  /// the slot of [anchor] to that of [focus] until the create flow
  /// closes.
  void _create(
    ({int row, int col}) anchor,
    ({int row, int col}) focus,
    CreateRange range,
  ) {
    final create = ++_creates;
    setState(() {
      _creating = (anchor: anchor, focus: focus);
    });
    widget.onCreate(range).whenComplete(() {
      if (mounted && create == _creates) {
        setState(() {
          _creating = null;
        });
      }
    });
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
    final range = _RangeDrag<T>(this, viewport, anchor, point);
    setState(() {
      _range = range;
    });
    return range;
  }

  /// Moves [range]'s focus toward [focus], as far as [_reach] takes it.
  void _moveRange(_RangeDrag<T> range, ({int row, int col}) focus) {
    if (!mounted || !identical(_range, range)) {
      return;
    }
    final reached = _reach(range, focus);
    if (reached == range.focus) {
      return;
    }
    setState(() {
      range.focus = reached;
    });
  }

  /// The focus [range] reaches toward [focus], in wall-minute order of the
  /// cells' slots: held at the last slot that does not pass the nearest
  /// entry [range] read on either side of its anchor, at the history
  /// lock's boundary for its start, and at [TimedGrid.maxDayCount]'s days
  /// ([_heldToLimit]), however far past them [focus] lies. Constant work
  /// per call: the entries were read when the range began.
  ({int row, int col}) _reach(_RangeDrag<T> range, ({int row, int col}) focus) {
    final anchor = range.anchor;
    final anchorWall = slotWallMinuteOf(_tracks, anchor);
    final focusWall = slotWallMinuteOf(_tracks, focus);
    if (focusWall >= anchorWall) {
      final limit = range.nextStart;
      if (limit != null && focusWall + minutesPerSlot > limit) {
        focus = _lastCellEndingBy(limit, anchor);
      }
      final end = timeAtWallMinute(
        slotWallMinuteOf(_tracks, focus) + minutesPerSlot,
      );
      final start = timeAtWallMinute(anchorWall);
      if (start != null && end != null && !_coversAtMost(start, end)) {
        final held = _heldToLimit(start, end, atEnd: true);
        if (held != null) {
          focus = _lastCellEndingBy(wallMinuteOf(held.end), anchor);
        }
      }
      return focus;
    }
    var earliest = range.previousEnd;
    final boundary = _lock.value.boundary;
    if (boundary != null) {
      final wall = wallMinuteOf(boundary);
      earliest = earliest == null ? wall : math.max(earliest, wall);
    }
    if (earliest != null && focusWall < earliest) {
      focus = _firstCellStartingFrom(earliest, anchor);
    }
    final start = timeAtWallMinute(slotWallMinuteOf(_tracks, focus));
    final end = timeAtWallMinute(anchorWall + minutesPerSlot);
    if (start != null && end != null && !_coversAtMost(start, end)) {
      final held = _heldToLimit(start, end, atEnd: false);
      if (held != null) {
        focus = _firstCellStartingFrom(wallMinuteOf(held.start), anchor);
      }
    }
    return focus;
  }

  /// The latest body cell, in wall-minute order, whose slot ends at the
  /// wall minute [wall] or before it, and [anchor] where that is not after
  /// [anchor].
  ({int row, int col}) _lastCellEndingBy(
    int wall,
    ({int row, int col}) anchor,
  ) {
    final tracks = _tracks;
    final hours = tracks.hours;
    final into = wall % minutesPerDay;
    final day = (wall - into) ~/ minutesPerDay;
    var column = tracks.lastColumnUpTo(day);
    ({int row, int col})? cell;
    if (column >= 1) {
      if (tracks.dayAt(column) == day && into < hours.end) {
        final slots = (into - hours.start) ~/ minutesPerSlot;
        if (into >= hours.start && slots >= 1) {
          cell = (row: tracks.firstSlotRow + slots - 1, col: column);
        } else {
          column--;
        }
      }
      if (cell == null && column >= 1) {
        cell = (row: tracks.lastSlotRow, col: column);
      }
    }
    if (cell == null ||
        slotWallMinuteOf(tracks, cell) <= slotWallMinuteOf(tracks, anchor)) {
      return anchor;
    }
    return cell;
  }

  /// The earliest body cell, in wall-minute order, whose slot starts at the
  /// wall minute [wall] or after it, and [anchor] where that is not before
  /// [anchor].
  ({int row, int col}) _firstCellStartingFrom(
    int wall,
    ({int row, int col}) anchor,
  ) {
    final tracks = _tracks;
    final hours = tracks.hours;
    final into = wall % minutesPerDay;
    final day = (wall - into) ~/ minutesPerDay;
    var column = tracks.firstColumnFrom(day);
    ({int row, int col})? cell;
    if (column <= tracks.columnCount) {
      if (tracks.dayAt(column) == day && into > hours.start) {
        final slots =
            (into - hours.start + minutesPerSlot - 1) ~/ minutesPerSlot;
        if (slots < tracks.rowCount) {
          cell = (row: tracks.firstSlotRow + slots, col: column);
        } else {
          column++;
        }
      }
      if (cell == null && column <= tracks.columnCount) {
        cell = (row: tracks.firstSlotRow, col: column);
      }
    }
    if (cell == null ||
        slotWallMinuteOf(tracks, cell) >= slotWallMinuteOf(tracks, anchor)) {
      return anchor;
    }
    return cell;
  }

  /// Whether the range from [start] to [end] covers at most
  /// [TimedGrid.maxDayCount] days, counting each day it has any part of;
  /// every range does with no limit.
  bool _coversAtMost(DateTime start, DateTime end) {
    final limit = widget.maxDayCount;
    return limit == null ||
        lastDayNumberOf(start, end) - dayNumber(start) + 1 <= limit;
  }

  /// The range from [start] to [end] held at [TimedGrid.maxDayCount]'s
  /// days: with [atEnd] its end moved, and otherwise its start. An all-day
  /// range ends at the start of the day after the limit's last day, or
  /// starts at the start of its first; any other ends at the hours' end on
  /// the limit's last day, or starts at the hours' start on its first, so
  /// a held slot range ends or starts on a slot the hours hold. Null where
  /// that is a time the clock skips; the range itself with no limit.
  ({DateTime start, DateTime end})? _heldToLimit(
    DateTime start,
    DateTime end, {
    required bool atEnd,
  }) {
    final limit = widget.maxDayCount;
    if (limit == null) {
      return (start: start, end: end);
    }
    final hours = _tracks.hours;
    final allDay = isDayStart(start) && isDayStart(end);
    if (atEnd) {
      final lastDay = dayNumber(start) + limit - 1;
      final held = allDay
          ? dateOfDayNumber(lastDay + 1)
          : timeAtWallMinute(lastDay * minutesPerDay + hours.end);
      return held == null ? null : (start: start, end: held);
    }
    final firstDay = lastDayNumberOf(start, end) - limit + 1;
    final held = allDay
        ? dateOfDayNumber(firstDay)
        : timeAtWallMinute(firstDay * minutesPerDay + hours.start);
    return held == null ? null : (start: held, end: end);
  }

  /// Reports the range [range] was let go at: its anchor's slot where its
  /// focus never left it, and otherwise the range to its focus; nothing
  /// where that range has an end the clock skips.
  void _endRange(_RangeDrag<T> range) {
    if (!mounted || !identical(_range, range)) {
      return;
    }
    final hold = range.focus == range.anchor;
    final created = hold
        ? createRangeAt(_tracks, range.anchor)
        : createRangeOver(_tracks, range.anchor, range.focus);
    _clearRange(range);
    if (created == null) {
      return;
    }
    _create(range.anchor, range.focus, created);
  }

  void _clearRange(_RangeDrag<T> range) {
    if (!mounted || !identical(_range, range)) {
      return;
    }
    setState(() {
      _range = null;
    });
  }

  Widget? _buildCell(
    BuildContext context,
    BoardCellView<GridKey, GridShape<T>> cell,
  ) {
    if (widget.showsDayHeader && cell.row == 0) {
      if (cell.col == 0) {
        return _HiddenCount(count: _hiddenCount);
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
        return const _GutterCell();
      }
      return _NoticeCell(
        hidden: _hiddenCount,
        column: cell.col,
        above: above,
        format: widget.hourLabelFormat,
      );
    }
    if (cell.col == 0) {
      // Every gutter row is opaque so nothing scrolled beneath the band
      // shows through. The foreground paints the hour labels over it; a
      // row whose top or bottom line is labelled names it to a screen
      // reader.
      final label = _gutterLabelOf(cell.row);
      if (label == null) {
        return const _GutterCell();
      }
      return Semantics(
        container: true,
        label: label,
        child: const _GutterCell(),
      );
    }
    // Body cells build nothing: the background painter draws the grid.
    return null;
  }

  /// What a screen reader hears for the gutter cell of [row]: the labels
  /// the foreground paints on its top and bottom lines, or null where it
  /// paints none.
  String? _gutterLabelOf(int row) {
    final format = widget.hourLabelFormat;
    final labels = <String>[
      if (_GridForegroundPainter.labelsRow(_tracks, row))
        hourLabel(_tracks.minuteAt(row), format),
      if (row == _tracks.lastSlotRow) hourLabel(_tracks.hours.end, format),
    ];
    return labels.isEmpty ? null : labels.join(", ");
  }

  Widget _buildPlacement(
    BuildContext context,
    BoardItemView<GridKey, GridShape<T>> view,
  ) {
    final shape = view.item;
    switch (shape) {
      case GridPiece<T>():
        return _buildPiece(shape, view.span);
    }
  }

  Widget _buildPiece(GridPiece<T> piece, BoardSpan span) {
    final entry = piece.shown;
    final hours = _tracks.hours;
    final cutAtStart = piece.start < hours.start;
    final cutAtEnd = piece.end > hours.end;
    return _Block<T>(
      key: blockKey(entry.id, dateOfDayNumber(piece.day)),
      entry: entry,
      details: CalendarBlockDetails(
        detailed: _tracks.columnCount == 1,
        tall:
            span.endTrackOn(Axis.vertical) - span.startTrackOn(Axis.vertical) >=
            3.0 - precisionErrorTolerance,
        cutAtStart: cutAtStart,
        cutAtEnd: cutAtEnd,
        continuesBefore: !piece.first,
        continuesAfter: !piece.last,
      ),
      builder: _blockBuilder,
      selection: _selectedBlock,
      lock: _lock,
      onSelect: () {
        _selectedBlock.value = entry.id;
      },
      handles: _handles,
      startHandle: piece.first && !cutAtStart,
      endHandle: piece.last && !cutAtEnd,
      onOpen: entry.pending
          ? null
          : () {
              widget.onOpenEntry(entry.id);
            },
    );
  }

  /// The wall minutes from the start of the earlier of [anchor] and
  /// [focus]'s slots to the end of the later one's.
  ({int start, int end}) _wallSpanOfCells(
    ({int row, int col}) anchor,
    ({int row, int col}) focus,
  ) {
    final from = slotWallMinuteOf(_tracks, anchor);
    final to = slotWallMinuteOf(_tracks, focus);
    return (
      start: math.min(from, to),
      end: math.max(from, to) + minutesPerSlot,
    );
  }

  /// The wall minutes ([wallMinuteOf]) next to [anchor]'s slot that a
  /// create range from it may not pass: the earliest start after the
  /// slot's start, and the latest end before its end, among the timed
  /// entries the store shows on the grid's days; each null where there is
  /// none.
  ({int? next, int? previous}) _conflictsAround(({int row, int col}) anchor) {
    final wall = slotWallMinuteOf(_tracks, anchor);
    final start = timeAtWallMinute(wall);
    final end = timeAtWallMinute(wall + minutesPerSlot);
    int? next;
    int? previous;
    if (start == null || end == null) {
      return (next: next, previous: previous);
    }
    for (final shown in widget.store.entriesBetween(
      widget.firstDay,
      _lastDay,
    )) {
      final entry = shown.entry;
      if (entry.isAllDay) {
        continue;
      }
      if (entry.start.isAfter(start)) {
        final at = wallMinuteOf(entry.start);
        next = next == null ? at : math.min(next, at);
      }
      if (entry.end.isBefore(end)) {
        final at = wallMinuteOf(entry.end);
        previous = previous == null ? at : math.max(previous, at);
      }
    }
    return (next: next, previous: previous);
  }

  /// The cover's content: what the failure builder draws for the grid's
  /// days when the read the store waits on for [TimedGrid.storeRange], or
  /// with none for its shown range, failed, with the store's load error as
  /// it holds it, and what the loading builder draws otherwise.
  Widget _buildCover(BuildContext context, CalendarStore<T> store) {
    final first = dateOfDayNumber(_tracks.firstDay);
    final last = _lastDay;
    final range = widget.storeRange;
    if (store.status == CalendarLoadStatus.failed &&
        (range == null || store.isShown(range.first, range.last))) {
      final failure = widget.failureBuilder ?? defaultCalendarFailureBuilder;
      return failure(
        context,
        CalendarFailureState(
          site: CalendarStateSite.cover,
          first: first,
          last: last,
          error: store.loadError,
          retry: store.retry,
        ),
      );
    }
    final loading = widget.loadingBuilder ?? defaultCalendarLoadingBuilder;
    return loading(
      context,
      CalendarLoadingState(
        site: CalendarStateSite.cover,
        first: first,
        last: last,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final range = _range;
    final drag = _drag;
    final styles = _styles;
    var labelStyle = DefaultTextStyle.of(context).style.merge(styles.hourLabel);
    if (MediaQuery.boldTextOf(context)) {
      labelStyle = labelStyle.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    _hourLabels.update(
      labelStyle,
      MediaQuery.textScalerOf(context),
      widget.hourLabelFormat,
    );
    _labelRoom = _hourLabels.height / 2 + _HourLabels.gap;
    final landingTimes = _landingTimes();
    final landingText = _landingText(landingTimes);
    final rangeAnchor = range?.anchor ?? _creating?.anchor;
    final rangeFocus = range?.focus ?? _creating?.focus;
    final listener = Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _pinch.handleEvent,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: Board<GridKey, GridShape<T>>(
          key: _boardKey,
          controller: _board,
          cellBuilder: _cellBuilder,
          itemBuilder: _placementBuilder,
          background: _TimedGridPainter(
            styles: styles,
            tracks: _tracks,
            today: widget.today,
            range: rangeAnchor == null || rangeFocus == null
                ? null
                : _wallSpanOfCells(rangeAnchor, rangeFocus),
            landing:
                drag != null &&
                    drag.kind == BoardDragKind.move &&
                    landingTimes != null
                ? wallSpanOf(landingTimes.start, landingTimes.end)
                : null,
          ),
          foreground: _GridForegroundPainter(
            styles: styles,
            tracks: _tracks,
            labels: _hourLabels,
            labelsVersion: _hourLabels.version,
            now: _nowMark,
            reachAbove: _notices.above ? _noticeHeight : 0.0,
            reachBelow: _notices.below ? _noticeHeight : 0.0,
          ),
          drag: widget.editable ? _editConfig : _viewConfig,
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
                  child: Builder(
                    builder: (context) {
                      return _buildCover(context, store);
                    },
                  ),
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
/// scrolls beneath it. It reads the entries that hold it once, when it
/// begins, and again on a store notify ([readConflicts]).
class _RangeDrag<T> extends Drag {
  _RangeDrag(this._grid, this._viewport, this.anchor, this._point)
    : focus = anchor,
      _vertical = _viewport.verticalPosition,
      _horizontal = _viewport.horizontalPosition {
    _vertical?.addListener(_refocus);
    _horizontal?.addListener(_refocus);
    readConflicts();
  }

  final _TimedGridState<T> _grid;
  final RenderBoardViewport<GridKey> _viewport;
  final ScrollPosition? _vertical;
  final ScrollPosition? _horizontal;
  final ({int row, int col}) anchor;

  /// The body cell last under the pointer, as far as the range reaches:
  /// unchanged while the pointer is over the header, the gutter or past
  /// the lattice.
  ({int row, int col}) focus;

  /// The wall minute of the earliest start after [anchor]'s slot, which a
  /// range reaching later may not pass, or null.
  int? nextStart;

  /// The wall minute of the latest end before [anchor]'s slot, which a
  /// range reaching earlier may not pass, or null.
  int? previousEnd;

  Offset _point;

  /// Reads the entries next to [anchor]'s slot that hold the range.
  void readConflicts() {
    final conflicts = _grid._conflictsAround(anchor);
    nextStart = conflicts.next;
    previousEnd = conflicts.previous;
  }

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
    final styles = _GridStyles.of(context);
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
            color: isSelected ? styles.theme.primaryTint : styles.theme.surface,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    weekdayShortNames[weekdayColumn(day)],
                    style: styles.headerWeekday,
                  ),
                  Container(
                    width: 30.0,
                    height: 20.0,
                    alignment: Alignment.center,
                    foregroundDecoration: isToday ? styles.headerRing : null,
                    child: Text(
                      "${day.day}",
                      style: isToday ? styles.headerToday : styles.headerNumber,
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

/// One piece on the grid: the box the board places it in, inset 1 px,
/// which [_BlockContent] fills with what [builder] draws for [entry] and
/// [details]; the block draws nothing of the entry itself. A long press on
/// it moves its entry while the history [lock] holds the entry
/// [EntryHold.free], and reports [onSelect] while it holds it
/// [EntryHold.started], and while [selection] names its entry, an outline
/// lies over it, with the top resize handle where [startHandle] holds and
/// the entry is free, and the bottom one where [endHandle] holds
/// ([_BlockHandles]). Its tap, long press and move take a press anywhere in
/// the box, whatever the builder paints there.
class _Block<T> extends StatelessWidget {
  const _Block({
    super.key,
    required this.entry,
    required this.details,
    required this.builder,
    required this.selection,
    required this.lock,
    required this.onSelect,
    required this.handles,
    required this.startHandle,
    required this.endHandle,
    required this.onOpen,
  });

  final CalendarShownEntry<T> entry;

  /// What the grid decides about the block's appearance, which [builder]
  /// draws from.
  final CalendarBlockDetails details;

  final CalendarBlockBuilder<T> builder;

  /// The id of the entry whose blocks are selected, or null.
  final ValueListenable<String?> selection;

  final ValueListenable<HistoryLock> lock;

  /// A long press on a block of a started entry asks to select it.
  final VoidCallback onSelect;

  /// Where the handles register while this block is selected.
  final _HandlesSlot handles;

  /// Whether the block, selected, has a handle on its top edge while its
  /// entry is free: the piece holds the entry's start, and the hours do
  /// not cut it.
  final bool startHandle;

  /// Whether the block, selected, has a handle on its bottom edge: the
  /// piece holds the entry's end, and the hours do not cut it.
  final bool endHandle;

  /// Null while the entry is pending, so a tap opens nothing.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final content = _BlockContent<T>(
      entry: entry,
      details: details,
      builder: builder,
    );
    // One shape selected or not, and held or not, so neither change drops
    // the block's State.
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[selection, lock]),
      child: content,
      builder: (context, child) {
        final hold = lock.value.holdOf(entry.entry.start, entry.entry.end);
        return Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            BoardDelayedDragHandle(
              enabled: hold == EntryHold.free,
              child: Padding(
                padding: const EdgeInsets.all(1.0),
                child: GestureDetector(
                  // Opaque, so the box takes a press wherever the builder
                  // paints nothing, and the drag handle deferring to it
                  // does too.
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  onLongPress: hold == EntryHold.started ? onSelect : null,
                  child: child,
                ),
              ),
            ),
            if (selection.value == entry.id)
              Positioned.fill(
                child: _BlockHandles(
                  key: blockHandlesKey(entry.id),
                  id: entry.id,
                  slot: handles,
                  resizesStart: startHandle && hold == EntryHold.free,
                  resizesEnd: endHandle,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A block's content: what [builder] last returned for [entry] and
/// [details], called again only once one of the three is not `==` to the
/// last, an inherited widget the builder read through this widget's
/// context notifies, or a hot reload reassembles it. The board rebuilds
/// every block it has built on each pinch move and each write, with the
/// identical entry and an equal details value for a block neither
/// changes, so such a rebuild calls no builder.
class _BlockContent<T> extends StatefulWidget {
  const _BlockContent({
    required this.entry,
    required this.details,
    required this.builder,
  });

  final CalendarShownEntry<T> entry;
  final CalendarBlockDetails details;
  final CalendarBlockBuilder<T> builder;

  @override
  State<_BlockContent<T>> createState() {
    return _BlockContentState<T>();
  }
}

class _BlockContentState<T> extends State<_BlockContent<T>> {
  /// What the builder last returned, which the element under this one then
  /// neither updates nor rebuilds; null until the next build calls it.
  Widget? _built;

  @override
  void didUpdateWidget(_BlockContent<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Identity first: an unchanged block's entry is the board's stored
    // instance, and its builder the grid's one field, so the deep
    // comparison of the payload runs only for an entry that was replaced.
    if (!_same(widget.entry, oldWidget.entry) ||
        !_same(widget.details, oldWidget.details) ||
        !_same(widget.builder, oldWidget.builder)) {
      _built = null;
    }
  }

  static bool _same(Object a, Object b) {
    return identical(a, b) || a == b;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
  }

  @override
  void reassemble() {
    super.reassemble();
    _built = null;
  }

  @override
  Widget build(BuildContext context) {
    return _built ??= widget.builder(context, widget.entry, widget.details);
  }
}

/// A gutter cell: the surface of the theme above it, so nothing scrolled
/// beneath the gutter shows through.
class _GutterCell extends StatelessWidget {
  const _GutterCell();

  @override
  Widget build(BuildContext context) {
    return _GridStyles.of(context).surfaceBox;
  }
}

/// The day header's corner over the gutter, on the surface colour: nothing,
/// or a pill counting the shown entries on no day the grid has a column
/// for, which a screen reader hears with [hiddenEntriesLabel] before the
/// count.
class _HiddenCount extends StatelessWidget {
  const _HiddenCount({required this.count});

  final ValueListenable<_Hidden> count;

  @override
  Widget build(BuildContext context) {
    final styles = _GridStyles.of(context);
    return ColoredBox(
      color: styles.theme.surface,
      child: Center(
        child: ValueListenableBuilder<_Hidden>(
          valueListenable: count,
          builder: (context, hidden, child) {
            final value = hidden.offDays;
            if (value == 0) {
              return const SizedBox.shrink();
            }
            return Semantics(
              label: hiddenEntriesLabel(value),
              child: DecoratedBox(
                key: hiddenCountKey,
                decoration: styles.hiddenPill,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6.0,
                    vertical: 2.0,
                  ),
                  child: Text("+$value", style: styles.hiddenLabel),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A day column's cell in a row counting the shown pieces with no block:
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
    final styles = _GridStyles.of(context);
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
        final cell = DecoratedBox(
          key: above ? hiddenAboveKey(day) : hiddenBelowKey(day),
          decoration: styles.noticeCell(above: above, first: column == 1),
          child: count == 0
              ? const SizedBox.expand()
              : _buildMore(count, styles),
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

  static const double _arrowSize = 16.0;
  static const double _arrowGap = 2.0;

  /// The arrow and "+N more", or "+N" in a cell too narrow for "+N more"
  /// at its own size, scaled down in one too narrow for that.
  Widget _buildMore(int count, _GridStyles styles) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final more = "+$count more";
          final painter = TextPainter(
            text: TextSpan(
              text: more,
              style: DefaultTextStyle.of(context).style.merge(styles.moreLabel),
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
                  above ? styles.noticeAbove : styles.noticeBelow,
                  const SizedBox(width: _arrowGap),
                  Text(
                    fits ? more : "+$count",
                    maxLines: 1,
                    style: styles.moreLabel,
                  ),
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
    final styles = _GridStyles.of(context);
    return IgnorePointer(
      child: Center(
        child: DecoratedBox(
          key: landingLabelKey,
          decoration: styles.landing,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 6.0,
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: styles.landingLabel,
            ),
          ),
        ),
      ),
    );
  }
}

/// Covers the grid while its days are not ready, taking every press,
/// whatever [child] paints: the scrim, with [child], the loading or the
/// failure builder's content, centred on it.
class _LoadOverlay extends StatelessWidget {
  const _LoadOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final styles = _GridStyles.of(context);
    // A ColoredBox hit-tests as opaque, so no press reaches the board.
    return ColoredBox(
      color: styles.scrim,
      child: Center(child: child),
    );
  }
}

/// The grid behind the cells, drawn for the visible body tracks alone: the
/// body, and across the slots the weekend and today's columns; the create
/// range being dragged, or whose create flow is open, and the times a move
/// would land on, each filled like today's column and edged in the primary
/// colour so it shows over that column too, one rect per day column it
/// covers; and a line at the top of each slot row, under the last one and
/// at the left of each day column, across the slots. The room above and
/// below the slots shows the body alone. Every paint it draws with is
/// [styles]', made once per theme.
class _TimedGridPainter extends BoardBackgroundPainter {
  const _TimedGridPainter({
    required this.styles,
    required this.tracks,
    required this.today,
    required this.range,
    required this.landing,
  });

  final _GridStyles styles;
  final GridTracks tracks;
  final DateTime today;

  /// The create range's wall minutes ([wallMinuteOf]), or null.
  final ({int start, int end})? range;

  /// The wall minutes a move would land on, or null.
  final ({int start, int end})? landing;

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
    canvas.drawRect(region, styles.surfacePaint);
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
        fill = styles.tintPaint;
      } else if (weekdayColumnOfDay(tracks.dayAt(col)) >= 5) {
        fill = styles.backgroundPaint;
      } else {
        continue;
      }
      final rect = geometry.visibleCellRect(slotFirst, col);
      canvas.drawRect(
        Rect.fromLTRB(rect.left, first.top, rect.right, last.bottom),
        fill,
      );
    }
    final range = this.range;
    if (range != null) {
      _paintMarked(canvas, geometry, range, slotFirst, slotLast);
    }
    final landing = this.landing;
    if (landing != null) {
      _paintMarked(canvas, geometry, landing, slotFirst, slotLast);
    }
    // The top line of each slot that shows, and the bottom line of the
    // last slot where the room below it shows.
    final linePaint = styles.linePaint;
    for (var row = slotFirst; row <= math.min(lastRow, slotLast + 1); row++) {
      final y = geometry.visibleCellRect(row, firstCol).top;
      canvas.drawLine(Offset(first.left, y), Offset(last.right, y), linePaint);
    }
    for (var col = firstCol; col <= lastCol; col++) {
      final x = geometry.visibleCellRect(slotFirst, col).left;
      canvas.drawLine(Offset(x, first.top), Offset(x, last.bottom), linePaint);
    }
    canvas.restore();
  }

  /// Fills, in each visible day column, the part of [marked], wall
  /// minutes, on that column's day that shows in the visible slot rows
  /// [slotFirst] to [slotLast], each minute as far into its slot's row as
  /// it lies into the slot, and edges it.
  void _paintMarked(
    Canvas canvas,
    BoardGeometryView geometry,
    ({int start, int end}) marked,
    int slotFirst,
    int slotLast,
  ) {
    final hours = tracks.hours;
    final from = tracks.minuteAt(slotFirst);
    final to = tracks.minuteAt(slotLast + 1);
    double yOf(int minute, int col) {
      final into = minute - hours.start;
      var row = tracks.firstSlotRow + into ~/ minutesPerSlot;
      var fraction = (into % minutesPerSlot) / minutesPerSlot;
      if (row > slotLast) {
        row = slotLast;
        fraction = 1.0;
      }
      final rect = geometry.visibleCellRect(row, col);
      return rect.top + fraction * rect.height;
    }

    for (
      var col = math.max(1, geometry.firstVisibleCol);
      col <= geometry.lastVisibleCol;
      col++
    ) {
      final piece = pieceOn(marked, tracks.dayAt(col));
      if (piece == null) {
        continue;
      }
      final start = math.max(piece.start, from);
      final end = math.min(piece.end, to);
      if (end <= start) {
        continue;
      }
      final cell = geometry.visibleCellRect(slotFirst, col);
      final rect = Rect.fromLTRB(
        cell.left,
        yOf(start, col),
        cell.right,
        yOf(end, col),
      );
      canvas.drawRect(rect, styles.tintPaint);
      canvas.drawRect(rect.deflate(1.0), styles.markEdgePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimedGridPainter old) {
    return !identical(old.styles, styles) ||
        old.tracks != tracks ||
        old.today != today ||
        old.range != range ||
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
    required this.styles,
    required this.tracks,
    required this.labels,
    required this.labelsVersion,
    required this.now,
    required this.reachAbove,
    required this.reachBelow,
  });

  /// The space between a label and the gutter's right edge.
  static const double _labelEnd = 6.0;

  /// Holds the paint of the line marking the current time.
  final _GridStyles styles;

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
    final nowPaint = styles.nowPaint;
    canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), nowPaint);
    canvas.drawCircle(Offset(rect.left, y), 4.0, nowPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GridForegroundPainter old) {
    return !identical(old.styles, styles) ||
        old.tracks != tracks ||
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

/// Where the selected entry's [_BlockHandles] register while they are
/// built, up to two: its first block's and its last block's, so a press
/// outside a block reaches them from [TimedGrid]'s listener.
class _HandlesSlot {
  final List<_BlockHandlesState> _states = <_BlockHandlesState>[];

  bool get isEmpty {
    return _states.isEmpty;
  }

  void add(_BlockHandlesState state) {
    _states.add(state);
  }

  void remove(_BlockHandlesState state) {
    _states.remove(state);
  }

  /// Starts a resize for [event] on the first registered handles whose
  /// strip outside its block holds it, and reports whether one did.
  bool startOutside(PointerDownEvent event) {
    for (final state in _states) {
      if (state.startOutside(event)) {
        return true;
      }
    }
    return false;
  }

  /// The resize cursor of the strip outside a registered block that holds
  /// [global], or [MouseCursor.defer] off them.
  MouseCursor cursorOutside(Offset global) {
    for (final state in _states) {
      final cursor = state.cursorOutside(global);
      if (cursor != MouseCursor.defer) {
        return cursor;
      }
    }
    return MouseCursor.defer;
  }
}

/// The cursor of a resize on [axis].
MouseCursor _resizeCursorOf(Axis axis) {
  return axis == Axis.vertical
      ? SystemMouseCursors.resizeUpDown
      : SystemMouseCursors.resizeLeftRight;
}

/// A selected block's outline and resize handles, over the block. Each
/// edge that resizes, the top where [resizesStart] and the bottom where
/// [resizesEnd], has a pill-shaped grip lying across its middle on the
/// outline, half outside the block, and takes a press on either side of
/// it: inside
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
    required this.resizesStart,
    required this.resizesEnd,
  });

  /// How far a resize press reaches from an edge into the block at most,
  /// and out of it.
  static const double depth = 12.0;

  /// The outline's width, on whose middle the grips lie.
  static const double outlineWidth = 2.0;

  /// A grip's length along its edge, at most three fifths of the edge.
  static const double gripLength = 24.0;

  static const double gripThickness = 8.0;

  /// The block's entry, which names the grips' keys.
  final String id;

  final _HandlesSlot slot;
  final bool resizesStart;
  final bool resizesEnd;

  @override
  State<_BlockHandles> createState() {
    return _BlockHandlesState();
  }
}

class _BlockHandlesState extends State<_BlockHandles> {
  @override
  void initState() {
    super.initState();
    widget.slot.add(this);
  }

  @override
  void dispose() {
    widget.slot.remove(this);
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
      if (widget.resizesStart && local.dy < 0.0 && local.dy >= -depth) {
        return (edge: BoardResizeEdges.leading, axis: Axis.vertical);
      }
      if (widget.resizesEnd &&
          local.dy >= size.height &&
          local.dy <= size.height + depth) {
        return (edge: BoardResizeEdges.trailing, axis: Axis.vertical);
      }
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
    final styles = _GridStyles.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final rows = math.min(_BlockHandles.depth, height / 3);
        final across = math.min(_BlockHandles.gripLength, width * 0.6);
        // From the block's edge to a grip's near side, which centres the
        // grip on the outline's middle.
        const lead =
            _BlockHandles.outlineWidth / 2 - _BlockHandles.gripThickness / 2;
        final id = widget.id;
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            styles.selectionOutline,
            if (widget.resizesStart)
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
            if (widget.resizesEnd)
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
            if (widget.resizesStart)
              Positioned(
                top: lead,
                left: (width - across) / 2,
                width: across,
                height: _BlockHandles.gripThickness,
                child: _Grip(key: blockGripKey(id, AxisDirection.up)),
              ),
            if (widget.resizesEnd)
              Positioned(
                bottom: lead,
                left: (width - across) / 2,
                width: across,
                height: _BlockHandles.gripThickness,
                child: _Grip(key: blockGripKey(id, AxisDirection.down)),
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
/// from the outline and the block's content, over a soft shadow. Takes no
/// press: the strip under it and the grid's listener take them.
class _Grip extends StatelessWidget {
  const _Grip({super.key});

  @override
  Widget build(BuildContext context) {
    return _GridStyles.of(context).grip;
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
