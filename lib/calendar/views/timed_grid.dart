/// The calendar's timed grid: consecutive days on the board, with a frozen
/// hour gutter and, where it shows one, a frozen day header, a frozen strip
/// of the days' all-day entries as bars, one row per slot, and the days'
/// timed entries as blocks, one per piece, the part of an entry on one
/// day, that in edit mode move, and once selected resize.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../board/board.dart';
import '../dates/calendar_dates.dart';
import '../entries/calendar_entry.dart';
import '../policy/edit_policy.dart';
import '../policy/edit_rules.dart';
import '../policy/overlap.dart';
import '../presentation/calendar_builders.dart';
import '../presentation/calendar_defaults.dart';
import '../presentation/calendar_localizations.dart';
import '../presentation/calendar_theme.dart';
import '../store/calendar_store.dart';
import 'answer_builder.dart';
import 'entry_split.dart';
import 'move_request.dart';
import 'pinch_zoom.dart';
import 'timed_grid_layout.dart';

const double _headerHeight = 40.0;

/// The height of the rows above and below the slots that count the items
/// outside the hours.
const double _noticeHeight = 24.0;

/// The height of one row of the all-day strip.
const double _allDayRowHeight = 22.0;

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
  return minute.clamp(hours.start, hours.end - tracks.slotMinutes);
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
      _stripCells = _stripCellsOf(theme),
      stripMarked = BoxDecoration(
        color: theme.primaryTint,
        border: Border.all(color: theme.primary, width: 2.0),
      ),
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

  /// A strip cell's fill and rules, in the first day column or another,
  /// and in the strip's last row or another: one rule parts each day from
  /// the one before, and one parts the last row from the hours.
  static List<BoxDecoration> _stripCellsOf(CalendarThemeData theme) {
    final edge = BorderSide(color: theme.outline);
    return <BoxDecoration>[
      for (final first in const <bool>[true, false])
        for (final last in const <bool>[true, false])
          BoxDecoration(
            color: theme.surface,
            border: Border(
              left: first ? BorderSide.none : edge,
              bottom: last ? edge : BorderSide.none,
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

  /// A strip cell, and one marked as a drop's or a create's days.
  final List<BoxDecoration> _stripCells;
  final BoxDecoration stripMarked;

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

  /// The fill and rules of a strip cell in the [first] day column or
  /// another, in the strip's [last] row or another.
  BoxDecoration stripCell({required bool first, required bool last}) {
    return _stripCells[(first ? 0 : 2) + (last ? 0 : 1)];
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

/// The key of the outline and the resize handles over the block, or the
/// bar of the all-day strip, of the entry [id] while it is selected.
ValueKey<String> blockHandlesKey(String id) {
  return ValueKey<String>("block-handles-$id");
}

/// The key of the grip of the selected block or bar of the entry [id] that
/// lies across its edge on [side]: [AxisDirection.up] or
/// [AxisDirection.down] for a block, [AxisDirection.left] or
/// [AxisDirection.right] for a bar of the all-day strip.
ValueKey<String> blockGripKey(String id, AxisDirection side) {
  return ValueKey<String>("block-grip-$id-${side.name}");
}

/// The key of the all-day strip's bar of the entry [id].
ValueKey<String> allDayBarKey(String id) {
  return ValueKey<String>("grid-all-day-bar-$id");
}

/// The key of [day]'s cell in the all-day strip's first row.
ValueKey<String> allDayCellKey(DateTime day) {
  return ValueKey<String>("grid-all-day-${isoDate(day)}");
}

/// The key of the pill counting the bars the collapsed all-day strip hides
/// on [day], a tap on which expands the strip.
ValueKey<String> allDayMoreKey(DateTime day) {
  return ValueKey<String>("grid-all-day-more-${isoDate(day)}");
}

/// The key of the pill that collapses the expanded all-day strip.
const ValueKey<String> allDayLessKey = ValueKey<String>("grid-all-day-less");

/// The key of the pill counting the shown items on no day the grid has a
/// column for.
const ValueKey<String> hiddenCountKey = ValueKey<String>("grid-hidden-count");

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

/// Whether a grid lays out a row above its slots and one below them.
typedef _Notices = ({bool above, bool below});

/// The key of the label naming where a drag lands.
const ValueKey<String> landingLabelKey = ValueKey<String>("grid-landing-label");

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
    return "CreateRange(${isoDate(start)} ${isoTime(minuteOfDay(start))} "
        "to ${isoDate(end)} ${isoTime(minuteOfDay(end))})";
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
  final slot = tracks.slotMinutes;
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
/// repeats a stretch, each end is the earlier instant of its time, or the
/// later where [occurrence] is a later instant on that day
/// ([timeAtWallMinute]), as an earliest start in the stretch's second pass
/// is ([CalendarEditPolicy.earliestStartOn]).
CreateRange? createRangeAt(
  GridTracks tracks,
  ({int row, int col}) cell, {
  DateTime? occurrence,
}) {
  final start = slotWallMinuteOf(tracks, cell);
  return _createRangeOf(start, start + tracks.slotMinutes, occurrence);
}

/// What a drag from the body cell [anchor] to [focus] creates: one
/// continuous range from the start of the earlier cell's slot, in
/// wall-minute order, to the end of the later one's, so Monday 10:00 to
/// Wednesday 12:00 gives Monday 10:00 to Wednesday 12:15, over every day
/// between, shown or not. Null where an end is a time the clock skips; on
/// a day whose clock repeats a stretch, each end is the earlier instant of
/// its time, or the later where [occurrence] is a later instant on that
/// day, as [createRangeAt] takes it.
CreateRange? createRangeOver(
  GridTracks tracks,
  ({int row, int col}) anchor,
  ({int row, int col}) focus, {
  DateTime? occurrence,
}) {
  final from = slotWallMinuteOf(tracks, anchor);
  final to = slotWallMinuteOf(tracks, focus);
  return _createRangeOf(
    math.min(from, to),
    math.max(from, to) + tracks.slotMinutes,
    occurrence,
  );
}

CreateRange? _createRangeOf(int startWall, int endWall, DateTime? occurrence) {
  final start = timeAtWallMinute(startWall, from: occurrence);
  final end = timeAtWallMinute(endWall, from: occurrence);
  if (start == null || end == null || !end.isAfter(start)) {
    return null;
  }
  return CreateRange(start: start, end: end);
}

/// The days of the [dayCount] from [firstDay] whose weekday [weekdays]
/// holds, on the board, over its [hours], one row per slot of
/// [slotMinutes], showing what [store] shows for them once they are
/// ready. An entry shows as one block per piece, its
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
/// All-day entries ([CalendarEntry.isAllDay]) show as bars in a strip
/// frozen under the day header, or at the grid's top where it shows none,
/// above the hours: each bar across the columns of the shown days it
/// covers, and the bars sharing a day in rows of their own. Past three
/// rows the strip shows three and, in a fourth, a "+N" pill on each day
/// counting its bars below the third, a tap on which shows every row; a
/// [CalendarLocalizations.showLess] pill in the strip's first row over the
/// gutter then collapses it again, and new days collapse it. With no
/// all-day entry on a shown day the strip has no rows, and one empty row
/// in edit mode. Each bar's content is what [chipBuilder] draws, told
/// which of its ends continue past the shown days. A tap on a bar that
/// is not pending reports [onOpenEntry] with its entry's id, in edit
/// mode and out of it.
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
/// time the clock skips requests and reports nothing; one on a time it
/// repeats keeps the occurrence the gesture began in. Every other move or
/// resize that lands is a [CalendarMoveRequest], which [onMoveRequest]
/// receives and the grid shows at its requested times, pending, until its
/// future completes. Out of edit mode the grid is read-only and asks
/// [editPolicy] nothing: no block moves or
/// resizes, and an empty slot creates nothing. In it [editPolicy] limits
/// the gestures: a block or a bar whose entry it lets not move
/// ([CalendarEditPolicy.mayMove]) takes no drag, a long press selecting it
/// where it lets an edge of it resize, and a selected one has the handles
/// of the edges it lets resize ([CalendarEditPolicy.resizableEdges]); no
/// move or resize lands an entry on times it refuses
/// ([CalendarEditPolicy.admitsChange]); and no create gesture starts or
/// reaches before the earliest start it gives the day the range starts on
/// ([CalendarEditPolicy.earliestStartOn]).
/// A block dragged above the first slot or below the last stops there, and
/// so does a handle dragged past either. Where [editPolicy] allows overlaps
/// ([CalendarEditPolicy.allowsOverlaps]), a move, a resize and a create go
/// over other entries' times as over free ones, the blocks sharing a day's
/// time laid side by side, and a move or a resize another answer refuses
/// goes back rather than sliding to free time. Where it forbids them, a
/// move dropped onto another entry's time lands at the nearest free time
/// that shows, on that day or the day before or after it, and goes back
/// where there is none; a resize dragged onto one stops at its edge, and
/// so does a create's range. While a drag runs, a label over the grid
/// names the days and times a release would give, or that a move has
/// nowhere to land, and a move outlines the times it would land on.
///
/// In edit mode a bar takes a long press as a block does. On a grid of more
/// than one day column it moves by days, and once selected its left grip drags
/// its first day and its right grip its last, where it does not continue past
/// them; on one column it takes neither. Dropped with the pointer over a slot,
/// or over the row above the first slot, a bar's entry becomes a timed one an
/// hour long from that slot's start, in the occurrence of the earliest start
/// [editPolicy] gives the day where its clock repeats that time, marked by the
/// landing outline while the pointer is there; and a block dropped with the
/// pointer over a day's strip cell makes its entry all-day on that day, the
/// strip marking that day while the pointer is there. A drag across empty strip
/// cells creates an all-day range of their days, as a tap on one creates its
/// day. A line over the blocks marks the time [now] holds in its day's column,
/// and the grid opens scrolled to the hour before it when it shows that day, at
/// 08:00 otherwise, with that hour's label whole below the top edge. Each whole
/// hour, and the start and the end of the hours, has a label centred on its
/// line in the hour gutter, in [hourLabelFormat], which a room above the first
/// slot and below the last, or the gutter beside a row counting entries outside
/// the hours, keeps whole. A piece reaching past the hours shows its part
/// inside them, and an entry whose start or end the hours do not hold
/// ([DayHours.holdsTimes]) takes no move or resize: only an edit outside the
/// grid changes it. A piece wholly outside them has no block. While some are
/// before the hours, a yellow row frozen against the first slot, in place of
/// the room above it, says [CalendarLocalizations.moreCount] in the column of
/// each day with N of them, and while some are after them, a row frozen against
/// the last slot does; the hour gutter runs on beside both. An entry on no
/// shown day has no block either, and a pill in the day header's corner counts
/// it. In edit mode empty body cells take a create gesture, reported through
/// [onCreate]: a drag picks one continuous range from the earlier of its two
/// slots to the later, across days too, at once with a mouse or a stylus and
/// after a press and hold on touch, so a touch drag without one scrolls the
/// grid, and a tap, or a hold let go where it began, picks its one slot. Where
/// [editPolicy] forbids overlaps, a slot that shares time with an entry takes
/// no create gesture. The range picked stays marked, as a range being dragged
/// is, until the create flow [onCreate] opens closes.
///
/// The day columns and the slot rows stretch to fill the grid, never
/// smaller than [minDayWidth] and [minSlotHeight]; past those, it scrolls.
/// The hour gutter is 56 px wide where the labels fit it on one line, or on
/// two broken between words where the closest labelled lines hold them at
/// the least slot height: [minSlotHeightLow] where a pinch zooms the grid,
/// and [minSlotHeight] where none does, so a pinch leaves the gutter as it
/// is. Otherwise it is as wide as the widest label and 6 px on each side,
/// up to 96 px, past which the labels shrink to fit it.
/// A pinch of two fingers zooms the grid around the point between them,
/// reporting through [onZoom] the least sizes it zooms to, from the sizes
/// the grid shows: a pinch up and down the slot height, from
/// [minSlotHeightLow] to [minSlotHeightHigh], and one across, on more than
/// one day column, the day width, from [minDayWidthLow] to
/// [minDayWidthHigh]. While two fingers are down the grid does not scroll,
/// and a finger that pinched clears no selection when it lifts off the
/// selected block. The grid runs one gesture at a time: while a block or a bar
/// moves or resizes, a create range runs or a pinch zooms, no pinch starts and
/// no create range or tap creates, and a block or a bar lifted meanwhile ends a
/// create range, which then creates nothing, or a pinch, which then zooms
/// nothing more. New days, which a new [firstDay], [dayCount] or [weekdays]
/// gives, cancel a move or a resize in flight, which then requests nothing, and
/// end a create range in flight, which then creates nothing. A new
/// [slotMinutes] or [hours] cancels a move or a resize in flight, which then
/// requests nothing, and ends a create range in flight and clears the range a
/// create flow marks. A new [editPolicy] cancels a move or a resize in flight,
/// which then requests nothing, and ends a create range in flight, which then
/// creates nothing; the range a create flow marks stays.
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
    required this.now,
    required this.onSelectDay,
    required this.onOpenEntry,
    required this.onCreate,
    this.onMoveRequest,
    this.editable = false,
    this.editPolicy,
    this.weekdays = WeekdaySet.all,
    this.hours = DayHours.allDay,
    this.slotMinutes = defaultSlotMinutes,
    this.hourLabelFormat = HourLabelFormat.twentyFourHour,
    this.minDayWidth = minDayWidthLow,
    this.minSlotHeight = defaultMinSlotHeight,
    this.onZoom,
    this.storeRange,
    this.showsDayHeader = true,
    this.blockBuilder,
    this.chipBuilder,
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

  /// The current time and the day marked as today, which its owner sets
  /// again at the start of each minute and where today changes. The grid
  /// follows it without a rebuild from above: the line marking the time,
  /// the column and the header marking today, and the answers it asks
  /// [editPolicy] at it.
  final ValueListenable<CalendarNow> now;

  final ValueChanged<DateTime> onSelectDay;

  /// Reports a tap on a block that is not pending, with its entry's id.
  final ValueChanged<String> onOpenEntry;

  /// Opens the create flow for the range a create gesture on empty cells
  /// picked, and completes when it closes.
  final Future<void> Function(CreateRange range) onCreate;

  /// Takes each move or resize a gesture lands, and completes once the
  /// host has written it or let it go. Until then the grid shows the
  /// entry at its requested times and pending, as a pending write shows
  /// it: a tap on it opens nothing, and no drag lifts it. Then the grid
  /// shows the store's entry again. Null writes the request through the
  /// store ([CalendarStore.requestMove]). A failure of the future, the
  /// store's included, is not caught: a host that handles one passes a
  /// function that does.
  final Future<void> Function(CalendarMoveRequest<T> request)? onMoveRequest;

  /// Whether the grid is in edit mode: its blocks move and resize, and its
  /// empty slots take a create gesture, as [editPolicy] lets them. Out of
  /// it the grid is read-only, and asks [editPolicy] nothing.
  final bool editable;

  /// What the gestures may change in edit mode ([CalendarEditPolicy]);
  /// null for an [UnrestrictedEditPolicy].
  ///
  /// The grid takes it when first built, in a build that gives a policy
  /// not `==` to the one it holds, and at a hot reload, and reads its
  /// [CalendarEditPolicy.dayLimit] then: the most days, counting each day
  /// it has any part of, that a create drag across days, over the slots
  /// or across the all-day strip, a bar's day-edge resize and, on more
  /// than one day column, an end handle dragged into a later day may give
  /// a range. One dragged past them is held at the latest range they
  /// admit, which a release requests or reports. A move keeps the days an
  /// entry covers, except where it crosses a midnight, and no limit
  /// applies to it. It reads [CalendarEditPolicy.allowsOverlaps] then
  /// too: where it is false, no move or resize gives an entry times that
  /// share time with another timed entry the store shows on the days they
  /// cover, whether the grid shows those days or not, and a create range
  /// stops at the entries beside the slot it starts on. A new policy
  /// cancels a move or a resize in flight and ends a create range in
  /// flight.
  ///
  /// An answer that throws in a crossing's landing or an end handle's
  /// later day, which the grid asks inside its pointer handlers, is
  /// reported and refuses, as the board's drop gate does
  /// ([BoardDragConfig.canDropAt]); one that throws in a build, a press or
  /// a tap goes through.
  final CalendarEditPolicy<T>? editPolicy;

  /// The weekdays whose days the grid shows. At least one day of the range
  /// must fall on a shown weekday. With [dayCount] it decides whether the
  /// grid shows one day column or more than one, which is fixed for the
  /// grid's life: give a grid that changes between them its own key.
  final WeekdaySet weekdays;

  /// The hours the grid shows and its gestures schedule in, one row per
  /// slot; they start and end on the grid of [slotMinutes]
  /// ([DayHours.isOnSlotsOf]).
  final DayHours hours;

  /// The length of one slot, one row, in minutes: the step the rows, a
  /// move's landing, a resize's edge and a create range snap to. One of
  /// [slotMinuteChoices], which the grid's state asserts.
  final int slotMinutes;

  /// The format the grid writes times of day in: the hour gutter's
  /// labels, the landing label, and the times its block and chip builders
  /// write ([CalendarBlockDetails.hourLabelFormat],
  /// [CalendarChipDetails.hourLabelFormat]).
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

  /// Draws each all-day bar's content inside the lane the strip gives it,
  /// in the chip form ([CalendarChipDetails.card] false); null for
  /// [defaultCalendarChipBuilder]. A new one, not `==` to the last, draws
  /// every bar again.
  final CalendarChipBuilder<T>? chipBuilder;

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

/// The gesture a grid runs, one at a time: none ([_Idle]), a pinch
/// ([_Pinching]), a create range ([_Ranging]), or the board's drag of a
/// block or a bar ([_Dragging]). A pinch and a create range start only
/// from [_Idle]; the board starts its drag on its own, which ends a pinch
/// or a create range running then. A mode ends at [_Idle], or at
/// [_Dragging] where the board's drag ends it.
sealed class _GridMode {
  const _GridMode();
}

/// No gesture runs.
final class _Idle extends _GridMode {
  const _Idle();
}

/// A pinch zooming from the slot height and the day width the grid showed
/// when it started.
final class _Pinching extends _GridMode {
  const _Pinching({required this.slot, required this.day});

  final double slot;
  final double day;
}

/// A create range being dragged, which the background paints.
final class _Ranging<T> extends _GridMode {
  const _Ranging(this.range);

  final _RangeDrag<T> range;
}

/// The drag the board runs on [key], from the board's report of its start
/// to the report of its end, and what the grid reads of it meanwhile: the
/// pointer that drives it, and for a crossing drag the cell under that
/// pointer and what a release there gives.
final class _Dragging extends _GridMode {
  _Dragging(this.key, this.kind);

  final GridKey key;

  /// Whether it moves, or resizes which edge.
  final BoardDragKind kind;

  /// Whether the board has reported a target yet.
  bool resolved = false;

  /// The placement a release would report, null where none is admitted.
  BoardSpan? target;

  /// The entry a move lifted, with the start and end it was lifted with,
  /// while it shows more than one piece: the placement step leaves out its
  /// pieces other than the dragged one while the shown entry keeps those
  /// times.
  ({String id, DateTime start, DateTime end})? lifted;

  /// The pointer of the press that started the drag, the first in
  /// `_pressKeys` naming [key]; null where none names it, and once the
  /// crossing is cleared ([clearCrossing]).
  int? pointer;

  /// Where [pointer] last moved during a crossing drag, in the board
  /// viewport's paint space; null from the lift to its first move.
  Offset? at;

  /// The cell a crossing drag's pointer is over, as the crossing reads it:
  /// a block's strip column, a bar's day column and slot row, an end
  /// handle's later day column and slot row; -1 for none.
  int column = -1;
  int row = -1;

  /// The day column of the piece whose end a crossing resize drags, read
  /// once at the drag's start so no pointer move looks the piece up; -1
  /// for any other drag.
  int resizedColumn = -1;

  /// What a release over [column] gives the entry: a block's all-day day,
  /// a bar's hour; null where the pointer is over no such cell or the
  /// landing is refused.
  ({DateTime start, DateTime end})? stripLanding;
  ({DateTime start, DateTime end})? barLanding;

  /// The end a release of an end handle over [column]'s later day gives
  /// the entry; null where the pointer is over no later day's slot or the
  /// end is refused.
  DateTime? laterDayEnd;

  /// The range a bar's day-edge resize past [CalendarEditRules.dayLimit] is
  /// held at ([CalendarEditRules.heldToLimit]), which its release writes.
  ({DateTime start, DateTime end})? heldBar;

  /// Set once a crossing's release wrote or refused its landing, so the
  /// drop gate refuses the board's own report of that release.
  bool spent = false;

  /// Whether the crossing names a cell, whose landing the label and the
  /// marks show in place of the board target's.
  bool get crosses {
    return column >= 1;
  }

  /// Forgets the crossing: the pointer, the cell, the landings and the
  /// held range. [spent] stays until the drag ends.
  void clearCrossing() {
    pointer = null;
    at = null;
    column = -1;
    row = -1;
    resizedColumn = -1;
    stripLanding = null;
    barLanding = null;
    laterDayEnd = null;
    heldBar = null;
  }
}

/// What the all-day strip's cells show: the days of [tracks]; whether the
/// strip is collapsed with a count row, [counted]; the bars each day column
/// hides below the third row, `below[c - 1]` for column `c`; and whether
/// the strip is expanded past three rows, so its first row's gutter cell
/// holds the pill collapsing it, [collapsible].
typedef _StripState = ({
  GridTracks tracks,
  bool counted,
  List<int> below,
  bool collapsible,
});

/// The shown day columns, from [first] to [last], whose all-day strip
/// cells are marked.
typedef _StripMark = ({int first, int last});

/// Where the line marking the current time sits: the column of its day
/// and its minute after midnight.
typedef _NowMark = ({int column, int minute});

/// What the blocks and bars ask in edit mode: [policy], at [now].
@immutable
class _EditLimits<T> {
  const _EditLimits(this.policy, this.now);

  final CalendarEditPolicy<T> policy;
  final CalendarNow now;

  @override
  bool operator ==(Object other) {
    return other is _EditLimits<T> &&
        other.policy == policy &&
        other.now == now;
  }

  @override
  int get hashCode {
    return Object.hash(policy, now);
  }
}

class _TimedGridState<T> extends State<TimedGrid<T>>
    with TickerProviderStateMixin {
  late final BoardController<GridKey, GridShape<T>> _board;

  late final PinchTracker _pinch = PinchTracker(
    onStart: _startPinch,
    onUpdate: _pinchTo,
    onEnd: _endPinch,
  );

  /// Where the fingers of the pinch that last reported a zoom met, in the
  /// board viewport's coordinates, until the next fit of the axes holds
  /// the lattice there ([_holdPinchFocal]).
  Offset? _pinchFocal;

  final ScrollHolder _scrollHold = ScrollHolder();

  /// The rows counting the entries outside the hours that the grid lays
  /// out above and below its slots.
  _Notices _notices = (above: false, below: false);

  /// The all-day strip's rows the grid lays out: the kept split's bar rows,
  /// three and a count row where those are more than three and the strip
  /// is not expanded, and with no bar none, or one empty row in edit mode.
  /// Kept while the days are not ready ([_sync]).
  late int _stripRows = widget.editable ? 1 : 0;

  /// Whether a "+N" pill expanded the all-day strip to every bar row. New
  /// days collapse it.
  bool _stripExpanded = false;

  /// Where the widget's days and minutes sit on the board.
  late GridTracks _tracks = _tracksOf(widget, _stripRows);

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

  /// [TimedGrid.chipBuilder], or the module's default where it is null.
  late CalendarChipBuilder<T> _chipBuilder = _chipBuilderOf(widget);

  static CalendarChipBuilder<T> _chipBuilderOf<T>(TimedGrid<T> widget) {
    return widget.chipBuilder ?? defaultCalendarChipBuilder<T>;
  }

  /// One instance in edit mode and one out of it, so a rebuild of this
  /// state hands the board the config it already has. Out of edit mode the
  /// config is disabled, so no handle starts a drag, and turning it off
  /// cancels a drag that runs. The board builds no handles of its own:
  /// each block carries the handle that moves it after a long press, and
  /// the selected block the resize handles the config's edges admit
  /// ([_Block], [_Bar]). No block resizes its column edges: a piece's days
  /// are its entry's. On more than one column a selected bar's grips resize
  /// its column edges, its days; on one it has none. Whether the grid has
  /// more than one column is fixed for its life, which [didUpdateWidget]
  /// asserts.
  ///
  /// A block's move and resize stay inside the slot rows ([_boundsOf]), so
  /// one dragged past the first or the last slot stops there. Where the
  /// policy forbids overlaps, a move [_canDropAt] refuses for meeting
  /// another entry slides to the placement nearest on screen that holds it
  /// clear, at any time that shows of the day it was dropped on or of the
  /// day before or after it, however busy the time around it is, and a
  /// resize it refuses for meeting another entry stops its dragged edge at
  /// that entry. The drag reports
  /// keep [_drag], which the landing label and outline show. A drag's
  /// start plays a haptic, and the block a move carries casts a shadow.
  /// [_applyTheme] makes the three again for a theme with another
  /// dragged-block opacity, which the board hands its live drag.
  ///
  /// [_fitlessConfig] is [_editConfig] with no drop fit, which the board
  /// holds while a bar drags, from [_handleDragStart] to [_handleDragEnd],
  /// so a target [_canDropAt] refuses, as every bar target over the slots
  /// is, costs one gate call and tries no candidate; and for every drag
  /// where the policy allows overlaps, so a move or a resize another
  /// answer refuses, such as the policy's or the hours', neither slides to
  /// free time nor stops at another entry.
  late BoardDragConfig<GridKey> _editConfig;
  late BoardDragConfig<GridKey> _fitlessConfig;
  late BoardDragConfig<GridKey> _viewConfig;

  BoardDragConfig<GridKey> _dragConfigOf({
    required bool enabled,
    bool fits = true,
  }) {
    return BoardDragConfig<GridKey>(
      enabled: enabled,
      canDrag: _canDrag,
      canDropAt: _canDropAt,
      boundsOf: _boundsOf,
      dropFit: fits
          ? const BoardDropFit(
              minFreeFraction: 0.0,
              rowRadius: double.infinity,
              colRadius: 1.0,
              clampResizes: true,
            )
          : null,
      onItemMoved: _commitMove,
      onItemResized: _commitResize,
      resizeEdges: _tracks.columnCount > 1
          ? BoardResizeEdges.both
          : BoardResizeEdges.none,
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

  /// The id of the entry whose block or bar a long press last lifted, whose
  /// blocks all show selected and whose first and last blocks, or whose
  /// bar, show its resize handles, or null. The blocks and bars listen to
  /// it, as the item builder runs only when the board rebuilds an item.
  final ValueNotifier<String?> _selectedBlock = ValueNotifier<String?>(null);

  /// The selected entry's handles, while they are built.
  final _HandlesSlot _handles = _HandlesSlot();

  /// Each move or resize the grid requested ([_requestMove]), by its
  /// entry's id, until the request's future completes. The grid's reads
  /// of the store show the requested entry in place of the stored one,
  /// pending ([_shownBetween], [_isPending]).
  final Map<String, CalendarMoveRequest<T>> _held =
      <String, CalendarMoveRequest<T>>{};

  /// What the last placement ([_placeLayout]) read: the split, the tracks,
  /// the drag's [_Dragging.lifted] and the strip rows it placed bars in;
  /// null before the first.
  /// While they are the same the board holds that placement's items, so a
  /// sync places nothing ([_placementCurrent]).
  ({
    TimedGridLayout<T> layout,
    GridTracks tracks,
    ({String id, DateTime start, DateTime end})? lifted,
    int shownRows,
  })?
  _placed;

  /// The last split [TimedGridLayout.of] made, which [_placeLayout] places.
  late TimedGridLayout<T> _layout = TimedGridLayout<T>.empty(_tracks);

  /// The timed entries the store shows on the days outside the tracks'
  /// range, which the split does not read, as far as the overlap checks
  /// since it was last cleared have needed them ([_offRangeOver]); null
  /// before the first. Cleared by a store notify, a new store and new
  /// tracks' first day or day count, and kept across builds, layouts and
  /// drags.
  GridOverlapIndex? _offRange;

  /// What the all-day strip's cells show. The cell builder runs only when
  /// the board rebuilds a cell, so the strip cells listen to this.
  late final ValueNotifier<_StripState> _strip = ValueNotifier<_StripState>(
    _stripStateOf(),
  );

  /// The day columns whose strip cells are marked ([_updateStripMark]), or
  /// null. The strip cells and the landing label listen to it.
  final ValueNotifier<_StripMark?> _stripMark = ValueNotifier<_StripMark?>(
    null,
  );

  /// The board's two scroll controllers, through which the grid reads the
  /// offsets of whichever positions the board's scrollables attach.
  final ScrollController _verticalScroll = ScrollController();
  final ScrollController _horizontalScroll = ScrollController();

  /// The policy the grid takes where [TimedGrid.editPolicy] is null.
  late final UnrestrictedEditPolicy<T> _unrestricted =
      UnrestrictedEditPolicy<T>();

  /// The rules of the policy the grid last took ([_takePolicy]), in the
  /// grid's hours and slots ([CalendarEditRules.updated]), which the gates
  /// ask. They read the policy's day limit and its answer on overlaps when
  /// the grid took it, so no gesture asks them.
  late CalendarEditRules<T> _rules;

  /// The policy the grid last took, which the gates ask.
  CalendarEditPolicy<T> get _policy {
    return _rules.policy;
  }

  /// [_policy]'s [CalendarEditPolicy.allowsOverlaps], as the grid read it
  /// when it took the policy. Where it is true the grid runs none of its
  /// overlap tests and the board holds [_fitlessConfig] for every drag.
  bool get _allowsOverlaps {
    return _rules.allowsOverlaps;
  }

  /// The time the gates and the gestures ask [_policy] at: [TimedGrid.now]
  /// as the grid last took it, at its notify ([_handleNow]) or in a build
  /// that gives the grid another clock.
  late CalendarNow _calendarNow;

  /// [_policy] at [_calendarNow] in edit mode, and null out of it, where
  /// every answer reads as permissive and none is asked. Written only
  /// where one of the three changes. The blocks and bars listen to it, each
  /// asking again and building again only where its own answers change.
  late final ValueNotifier<_EditLimits<T>?> _limits;

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

  /// The gesture the grid runs: [_Idle] until a pinch ([_startPinch]), a
  /// create range ([_beginRange]) or the board's drag ([_handleDragStart])
  /// starts, and again once it ends.
  _GridMode _mode = const _Idle();

  /// The drag the board runs, or null.
  _Dragging? get _drag {
    final mode = _mode;
    return mode is _Dragging ? mode : null;
  }

  /// The range being dragged, which the background paints, or null.
  _RangeDrag<T>? get _range {
    final mode = _mode;
    return mode is _Ranging<T> ? mode.range : null;
  }

  /// The block or bar each pointer down on the grid pressed, or whose
  /// handles a press beside a selected block started a resize of, until
  /// that pointer's up or cancel.
  final Map<int, GridKey> _pressKeys = <int, GridKey>{};

  /// Whether a post-frame read of the crossing's cell is scheduled
  /// ([_scheduleCrossRead]).
  bool _crossReadPending = false;

  /// The day columns of the all-day range whose create flow is open, which
  /// the strip marks; null while none is.
  _StripMark? _stripCreating;

  /// The first and the last slot of the range whose create flow is open,
  /// which the background marks; null while none is.
  ({({int row, int col}) anchor, ({int row, int col}) focus})? _creating;

  /// Counts the create flows opened, so only the last one's close clears
  /// [_creating].
  int _creates = 0;

  /// Where the line marking [TimedGrid.now] sits, or null where the grid
  /// does not show it.
  late _NowMark? _nowMark = _nowMarkOf(widget.now.value.time);

  /// What the header cells show. The cell builder runs only when the board
  /// rebuilds a cell, so the header cells listen to this instead.
  late final ValueNotifier<_HeaderState> _header = ValueNotifier<_HeaderState>((
    tracks: _tracks,
    selectedDay: widget.selectedDay,
    today: widget.now.value.today,
  ));

  /// The extents the axes were last given and the tracks they were given
  /// for. [_fitAxes] replaces an axis only when one of these changes.
  double _gutterWidth = _HourLabels.minGutter;
  late double _dayWidth = widget.minDayWidth;
  late double _slotHeight = widget.minSlotHeight;
  late int _columnCount = _tracks.columnCount;
  late DayHours _rowHours = _tracks.hours;
  late int _rowSlotMinutes = _tracks.slotMinutes;
  double _rowRoom = _initialLabelRoom;
  late _Notices _rowNotices = _notices;
  late int _rowStripRows = _stripRows;
  late HourLabelFormat _rowFormat = widget.hourLabelFormat;

  /// The room above the first slot and below the last: half the tallest
  /// hour label and the gap beside it, so the labels centred on the first
  /// and the last line show whole. Each build sets it from the labels'
  /// height.
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
  late final ValueNotifier<GridHiddenCounts> _hiddenCount =
      ValueNotifier<GridHiddenCounts>(GridHiddenCounts.none(_tracks));

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
    assert(
      slotMinuteChoices.contains(widget.slotMinutes),
      "A TimedGrid's slotMinutes, ${widget.slotMinutes}, is not one of "
      "$slotMinuteChoices.",
    );
    _takePolicy();
    _calendarNow = widget.now.value;
    _limits = ValueNotifier<_EditLimits<T>?>(_limitsOf());
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
        _tracks.rowOf(_openingMinuteOf(_tracks, widget.now.value.time)),
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
    assert(
      slotMinuteChoices.contains(widget.slotMinutes),
      "A TimedGrid's slotMinutes, ${widget.slotMinutes}, is not one of "
      "$slotMinuteChoices.",
    );
    final slotsChanged =
        widget.slotMinutes != oldWidget.slotMinutes ||
        widget.hours != oldWidget.hours;
    if (slotsChanged) {
      _cancelForNewSlots();
    }
    final policy = widget.editPolicy ?? _unrestricted;
    final policyChanged = policy != _policy;
    if (policyChanged) {
      _cancelForNewPolicy();
    }
    _rules = _rules.updated(
      policy: policy,
      hours: widget.hours,
      slotMinutes: widget.slotMinutes,
    );
    final blockBuilderChanged = widget.blockBuilder != oldWidget.blockBuilder;
    final chipBuilderChanged = widget.chipBuilder != oldWidget.chipBuilder;
    if (blockBuilderChanged) {
      _blockBuilder = _blockBuilderOf(widget);
    }
    if (chipBuilderChanged) {
      _chipBuilder = _chipBuilderOf(widget);
    }
    if (blockBuilderChanged || chipBuilderChanged) {
      _placementBuilder = (context, view) {
        return _buildPlacement(context, view);
      };
    }
    final storeChanged = widget.store != oldWidget.store;
    if (storeChanged) {
      oldWidget.store.removeListener(_handleStore);
      widget.store.addListener(_handleStore);
      _offRange = null;
    }
    final nowChanged = widget.now != oldWidget.now;
    if (nowChanged) {
      oldWidget.now.removeListener(_handleNow);
      widget.now.addListener(_handleNow);
    }
    final tracks = _tracksOf(widget, _stripRows);
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
    if (tracks.firstDay != _tracks.firstDay ||
        tracks.dayCount != _tracks.dayCount ||
        tracks.weekdays != _tracks.weekdays) {
      _stripExpanded = false;
      // The dragged key and its span can be the same on the new days, as a
      // bar's over both are, where no placement cancels its drag.
      _cancelDrag();
    }
    if (tracks.firstDay != _tracks.firstDay ||
        tracks.dayCount != _tracks.dayCount) {
      // Its runs of read days border the old range.
      _offRange = null;
    }
    // Equal tracks are kept, so the lists they build at their first read
    // are not built again.
    if (tracksChanged) {
      _tracks = tracks;
    }
    if (tracksChanged && _range != null) {
      // Its cells are rows and columns of the tracks it began on.
      _detachRange();
      _updateStripMark();
    }
    if (!widget.editable) {
      _selectedBlock.value = null;
    }
    final now = widget.now.value;
    final nowTaken = now != _calendarNow;
    if (nowTaken) {
      _calendarNow = now;
    }
    // Compared first, so a build that changes none of them, as each pinch
    // update's is, makes no limits.
    if (nowTaken || policyChanged || widget.editable != oldWidget.editable) {
      _limits.value = _limitsOf();
    }
    if (tracksChanged || nowChanged) {
      _nowMark = _nowMarkOf(now.time);
    }
    if (tracksChanged ||
        widget.selectedDay != oldWidget.selectedDay ||
        now.today != _header.value.today) {
      _header.value = (
        tracks: _tracks,
        selectedDay: widget.selectedDay,
        today: now.today,
      );
    }
    // The axes first, so the items the sync places fit the lattice they
    // land on.
    final size = _size;
    if (size != null &&
        (tracksChanged ||
            widget.editable != oldWidget.editable ||
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
      if (storeChanged) {
        _askDragAgain();
      }
    } else if (widget.editable != oldWidget.editable &&
        _syncedReady &&
        _applyStripRows(_stripRowsOf(_layout.barRows))) {
      // Edit mode gives an empty strip its row, or takes it away: the kept
      // split, placed again on the moved slot rows.
      _placeLayout(disable: true);
    }
    // After the sync, so the slot test of the range's anchor reads the
    // pieces of the store this build gives.
    if (nowTaken) {
      _refillRange();
    }
  }

  /// Takes [TimedGrid.editPolicy], or [_unrestricted] where it is null, in
  /// the grid's hours and slots, reading its day limit and whether it
  /// allows overlaps ([CalendarEditRules]).
  void _takePolicy() {
    _rules = CalendarEditRules<T>(
      policy: widget.editPolicy ?? _unrestricted,
      hours: widget.hours,
      slotMinutes: widget.slotMinutes,
    );
  }

  /// [_limits]' value as the widget and the fields stand.
  _EditLimits<T>? _limitsOf() {
    return widget.editable ? _EditLimits<T>(_policy, _calendarNow) : null;
  }

  /// Ends the gestures that new slots or hours leave on rows they no
  /// longer have, writing nothing: cancels the board's drag
  /// ([_cancelDrag]), and detaches a create range and clears the range a
  /// create flow marks. Runs before [_tracks] is replaced.
  void _cancelForNewSlots() {
    _cancelDrag();
    _detachRange();
    _creating = null;
    _stripCreating = null;
    _updateStripMark();
  }

  /// Ends the gestures a new policy would answer otherwise, writing
  /// nothing: cancels the board's drag ([_cancelBoardDrag]), keeping its
  /// [_Dragging.lifted], so the [_handleDragEnd] the cancel queues puts a
  /// lifted entry's other pieces back, and detaches a create range. The
  /// range a create flow marks stays, as its range is reported already.
  /// Runs before [_tracks] is replaced.
  void _cancelForNewPolicy() {
    _cancelBoardDrag();
    _detachRange();
    _updateStripMark();
  }

  /// Detaches the create range in flight, which then reports nothing, and
  /// leaves [_Ranging]; the caller updates the strip's marks.
  void _detachRange() {
    if (_range != null) {
      _mode = const _Idle();
    }
  }

  /// Cancels the board's drag on tracks about to be replaced, writing
  /// nothing ([_cancelBoardDrag]), and forgets its [_Dragging.lifted], so
  /// the sync on the new tracks puts a lifted entry's pieces back. Runs
  /// before [_tracks] is replaced and so before any placement on the new
  /// tracks, which may drop the dragged key.
  void _cancelDrag() {
    _cancelBoardDrag();
    final drag = _drag;
    if (drag != null) {
      drag.lifted = null;
    }
  }

  /// Cancels the board's drag, requesting nothing: a span write of its key to
  /// the span it holds, whose mutation cancel runs before the write and
  /// queues [_handleDragEnd]; and forgets the drag's crossing state, so its
  /// release requests nothing.
  void _cancelBoardDrag() {
    final dragged = _drag?.key;
    if (dragged != null && _board.isDragging(dragged)) {
      final span = _board.spanOf(dragged);
      if (span != null) {
        _board.moveItem(dragged, span);
      }
    }
    _clearCross();
  }

  /// The tracks [widget] lays out under [stripRows] all-day strip rows.
  static GridTracks _tracksOf<T>(TimedGrid<T> widget, int stripRows) {
    final tracks = GridTracks(
      firstDay: dayNumber(widget.firstDay),
      dayCount: widget.dayCount,
      weekdays: widget.weekdays,
      hours: widget.hours,
      // The day header, the all-day strip's rows, then the room above the
      // first slot or the row counting the entries before the hours.
      firstSlotRow: (widget.showsDayHeader ? 1 : 0) + stripRows + 1,
      slotMinutes: widget.slotMinutes,
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
    // A reload can change what a getter of the policy held answers, which
    // stays `==` to itself and so is not taken again by an update.
    _takePolicy();
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
      _fitlessConfig = _dragConfigOf(enabled: true, fits: false);
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
    widget.store.removeListener(_handleStore);
    _header.dispose();
    _hiddenCount.dispose();
    _strip.dispose();
    _stripMark.dispose();
    _selectedBlock.dispose();
    _limits.dispose();
    _besideCursor.dispose();
    _hourLabels.dispose();
    // The board has unmounted by now, so nothing still listens to the
    // controllers.
    _board.dispose();
    _verticalScroll.dispose();
    _horizontalScroll.dispose();
    super.dispose();
  }

  /// The board key of [shape]: a piece's is its entry's id and its day's
  /// offset from the entry's first day, and a bar's its entry's id.
  static GridKey _keyOf<T>(GridShape<T> shape) {
    switch (shape) {
      case GridPiece<T>(:final shown, :final day):
        return GridKey.piece(shown.id, day - dayNumber(shown.entry.start));
      case GridBar<T>(:final shown):
        return GridKey.bar(shown.id);
    }
  }

  /// The slots of the hours, [_slotHeight] each, under the frozen day
  /// header where the grid shows one and the all-day strip's
  /// [_stripRows], [_allDayRowHeight] each, frozen with it. Above the slots
  /// a row of [_labelRoom], or the frozen row counting the entries before
  /// the hours where [_notices] has one, and below them a row of
  /// [_labelRoom] or the frozen row counting those after.
  BoardAxisConfig _rowsConfig() {
    return BoardAxisConfig(
      axis: ExplicitAxis(<double>[
        if (widget.showsDayHeader) _headerHeight,
        ...List<double>.filled(_stripRows, _allDayRowHeight),
        _edgeAbove,
        ...List<double>.filled(_tracks.rowCount, _slotHeight),
        _edgeBelow,
      ]),
      frozenStart: _stripStart + _stripRows + (_notices.above ? 1 : 0),
      frozenEnd: _notices.below ? 1 : 0,
    );
  }

  /// The all-day strip's first row: under the day header where the grid
  /// shows one.
  int get _stripStart {
    return widget.showsDayHeader ? 1 : 0;
  }

  /// Whether [row] is one of the all-day strip's rows.
  bool _isStripRow(int row) {
    return row >= _stripStart && row < _stripStart + _stripRows;
  }

  /// Whether the collapsed strip shows its count row, its fourth.
  bool get _stripCounted {
    return !_stripExpanded && _layout.barRows > collapsedStripRows;
  }

  /// The strip rows the placement puts bars in: a collapsed strip's first
  /// three, and otherwise every one.
  int get _shownStripRows {
    return _stripCounted ? collapsedStripRows : _stripRows;
  }

  /// Whether the board holds the placement of the kept split as it stands
  /// ([_placed]): the same split on the same tracks, with the same lift
  /// and the same strip rows.
  bool get _placementCurrent {
    final placed = _placed;
    return placed != null &&
        identical(placed.layout, _layout) &&
        placed.tracks == _tracks &&
        placed.lifted == _drag?.lifted &&
        placed.shownRows == _shownStripRows;
  }

  /// The strip rows [barRows] bar rows lay out: none with no bar, or one
  /// empty row in edit mode; three and a count row where they are more
  /// than three and the strip is not expanded; and otherwise each.
  int _stripRowsOf(int barRows) {
    if (barRows == 0) {
      return widget.editable ? 1 : 0;
    }
    if (barRows > collapsedStripRows && !_stripExpanded) {
      return collapsedStripRows + 1;
    }
    return barRows;
  }

  _StripState _stripStateOf() {
    return (
      tracks: _tracks,
      counted: _stripCounted,
      below: _layout.below,
      collapsible: _stripExpanded && _layout.barRows > collapsedStripRows,
    );
  }

  /// Lays out [rows] strip rows in place of the ones the grid has, and
  /// returns whether they differ. A change moves every slot row by it: the
  /// tracks and the rows follow, a create range in flight, whose cells
  /// name rows it no longer has, detaches and reports nothing, an open
  /// create flow's marks move with their slots, and a crossing drag reads
  /// its cell again once the board has laid the new rows out. The caller
  /// places the kept split on the new rows.
  bool _applyStripRows(int rows) {
    if (rows == _stripRows) {
      _strip.value = _stripStateOf();
      return false;
    }
    final shift = rows - _stripRows;
    _stripRows = rows;
    _tracks = _tracksOf(widget, rows);
    if (_range != null) {
      _detachRange();
      _updateStripMark();
    }
    final creating = _creating;
    if (creating != null) {
      _creating = (
        anchor: (row: creating.anchor.row + shift, col: creating.anchor.col),
        focus: (row: creating.focus.row + shift, col: creating.focus.col),
      );
    }
    final size = _size;
    if (size != null) {
      _fitAxes(size);
    } else {
      _replaceRows();
    }
    _strip.value = _stripStateOf();
    _scheduleCrossRead();
    return true;
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
    _rowSlotMinutes = _tracks.slotMinutes;
    _rowRoom = _labelRoom;
    _rowNotices = _notices;
    _rowStripRows = _stripRows;
    _rowFormat = widget.hourLabelFormat;
    _board.rows = _rowsConfig();
  }

  /// The day header's height, or 0 where the grid shows none.
  double get _headerExtent {
    return widget.showsDayHeader ? _headerHeight : 0.0;
  }

  /// The all-day strip's height.
  double get _stripExtent {
    return _stripRows * _allDayRowHeight;
  }

  /// The height of the frozen rows above the slots: the day header, the
  /// all-day strip and the row counting the entries before the hours,
  /// each where the grid shows it.
  double get _leadingExtent {
    return _headerExtent +
        _stripExtent +
        (_notices.above ? _noticeHeight : 0.0);
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
  /// [_tracks] shows. The `laneExtent` makes the day axis the lane axis,
  /// so pieces sharing a day's time sit side by side: those of entries a
  /// policy allowing overlaps let share it, and those a failed move
  /// returns under another entry's pending move.
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

  /// The hour gutter as wide as [_HourLabels.gutter], the day columns
  /// across the rest of [size]'s width and the slot rows down its height,
  /// each stretched to fill it and never smaller than
  /// [TimedGrid.minDayWidth] and [TimedGrid.minSlotHeight]. Called from the
  /// layout callback, so the
  /// first frame lays the board out at its size, and from
  /// [didUpdateWidget] at the last size, so new tracks reach the board in
  /// the build that places items on them.
  ///
  /// An axis is replaced only when its extent or its tracks change. The
  /// rows are replaced for new hours or a new slot length even at the same
  /// count, for new [_notices] or strip rows, and for a new [_labelRoom] or
  /// hour format, which also rebuilds the gutter cells and so what they
  /// tell a screen reader, and the blocks and bars, whose details carry
  /// the format.
  void _fitAxes(Size size) {
    _size = size;
    final oldRows = _board.rows;
    final oldColumns = _board.columns;
    final gutter = _hourLabels.gutter;
    final dayWidth = math.max(
      widget.minDayWidth,
      _share(size.width - gutter, _tracks.columnCount),
    );
    final slotHeight = math.max(
      widget.minSlotHeight,
      _share(
        size.height - _headerExtent - _stripExtent - _edgeAbove - _edgeBelow,
        _tracks.rowCount,
      ),
    );
    if (gutter != _gutterWidth ||
        dayWidth != _dayWidth ||
        _tracks.columnCount != _columnCount) {
      _gutterWidth = gutter;
      _dayWidth = dayWidth;
      _columnCount = _tracks.columnCount;
      _board.columns = _columnsConfig();
    }
    if (slotHeight != _slotHeight ||
        _tracks.hours != _rowHours ||
        _tracks.slotMinutes != _rowSlotMinutes ||
        _labelRoom != _rowRoom ||
        _notices != _rowNotices ||
        _stripRows != _rowStripRows ||
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

  /// Starts a pinch from the sizes the grid shows, unless another gesture
  /// runs: a block or a bar moving or resizing, a create range, or another
  /// pinch.
  bool _startPinch(PinchAxis axis, Offset focal) {
    if (_mode is! _Idle) {
      return false;
    }
    _mode = _Pinching(slot: _slotHeight, day: _dayWidth);
    return true;
  }

  /// Reports through [TimedGrid.onZoom] the least size the pinch zooms its
  /// axis to, its scale times the size shown at its start, from
  /// [minSlotHeightLow] to [minSlotHeightHigh] or from [minDayWidthLow] to
  /// [minDayWidthHigh], and notes where its fingers meet for the fit that
  /// follows. On one day column a pinch across zooms nothing, and nor does
  /// one a drag of the board ended.
  void _pinchTo(PinchUpdate update) {
    final from = _mode;
    final onZoom = widget.onZoom;
    final viewport = _findViewport();
    if (from is! _Pinching || onZoom == null || viewport == null) {
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
    if (_mode is _Pinching) {
      _mode = const _Idle();
    }
  }

  /// Holds the board's scrolling while two fingers are down, unless a
  /// block drag or a create range runs, which no pinch starts beside, and
  /// lets it go after.
  void _handleHolding() {
    final viewport = _findViewport();
    if (_pinch.holding.value && (_mode is _Idle || _mode is _Pinching)) {
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
  /// builds the grid on the days of its new range next. The entries of
  /// the days outside the range are read again when a check next needs
  /// them ([_offRange]), a create range in flight reads the entries it is
  /// held by again, a refused one places its anchor again on the entries
  /// the sync placed ([_placeRangeAnchor]), and where the policy forbids
  /// overlaps a drag the board runs asks its gates again
  /// ([_askDragAgain]).
  void _handleStore() {
    final showedRange = _showsRange;
    _noteRange();
    if (showedRange && !_showsRange) {
      _selectedBlock.value = null;
    }
    _offRange = null;
    _sync();
    final range = _range;
    if (range != null && range.refused) {
      _placeRangeAnchor(range);
    } else {
      range?.readConflicts();
    }
    _askDragAgain();
    setState(() {});
  }

  /// Hands [request] to [TimedGrid.onMoveRequest], or with none writes it
  /// ([CalendarStore.requestMove]), holding it in [_held] until the future
  /// completes, or fails, a throw within the call included. The hold syncs
  /// within the call ([_handleStore]), as a store write's notify does.
  void _requestMove(CalendarMoveRequest<T> request) {
    final id = request.entry.id!;
    _held[id] = request;
    _handleStore();
    final onMoveRequest = widget.onMoveRequest;
    final store = widget.store;
    final moving = Future<void>.sync(() {
      return onMoveRequest == null
          ? store.requestMove(request.requested)
          : onMoveRequest(request);
    });
    moving.whenComplete(() {
      if (!identical(_held[id], request)) {
        return;
      }
      _held.remove(id);
      if (mounted) {
        _handleStore();
      }
    });
  }

  /// Whether a write on the entry [id] runs in the store, or a request of
  /// the grid's holds it ([_held]).
  bool _isPending(String id) {
    return _held.containsKey(id) || widget.store.isPending(id);
  }

  /// The entries the store shows on any day from [first] to [last], with
  /// each move [_held] holds in place of its stored entry: its requested
  /// entry, pending, where it covers one of those days and the store still
  /// holds the entry. In the store's order ([compareCalendarEntries]).
  List<CalendarShownEntry<T>> _shownBetween(DateTime first, DateTime last) {
    final shown = widget.store.entriesBetween(first, last);
    if (_held.isEmpty) {
      return shown;
    }
    shown.removeWhere((entry) {
      return _held.containsKey(entry.id);
    });
    final from = dayNumber(first);
    final to = dayNumber(last);
    for (final MapEntry(key: id, value: request) in _held.entries) {
      final entry = request.requested;
      if (widget.store.storedEntry(id) != null &&
          dayNumber(entry.start) <= to &&
          lastDayNumberOf(entry.start, entry.end) >= from) {
        shown.add(CalendarShownEntry<T>(entry, pending: true));
      }
    }
    shown.sort((a, b) {
      return compareCalendarEntries(a.entry, b.entry);
    });
    return shown;
  }

  /// Where the board's drag session runs and the policy forbids overlaps,
  /// makes [_editConfig] and [_fitlessConfig] again, which the next build
  /// hands the board, and reads a crossing's cell again after the frame
  /// ([_scheduleCrossRead]): the overlap tests read entries a store change
  /// may have changed, and a change only on days the grid does not show
  /// places nothing, so the board's structural channel does not ask the
  /// drop gate again. A new config on a live session asks it again for
  /// the placement the pointer rests on ([BoardDragConfig.canDropAt]). The
  /// board tears its session down before it reports the drop, so a drop's
  /// own request makes no config.
  void _askDragAgain() {
    final drag = _drag;
    if (_allowsOverlaps || drag == null || !_board.isDragging(drag.key)) {
      return;
    }
    _editConfig = _dragConfigOf(enabled: true);
    _fitlessConfig = _dragConfigOf(enabled: true, fits: false);
    _scheduleCrossRead();
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
  /// otherwise ([TimedGridLayout.of]), lays out the all-day strip's rows and
  /// the rows counting those outside the hours before the pieces, so they
  /// fit the lattice they land on, and places the split once
  /// ([_placeLayout]), whatever rows it changed, unless the board holds
  /// its placement already ([_placementCurrent]): a store notify that
  /// keeps the split on the same tracks places nothing. A sync animates only when
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
        ? _shownBetween(widget.firstDay, _lastDay)
        : <CalendarShownEntry<T>>[];
    final layout = TimedGridLayout<T>.of(shown, _tracks, previous: _layout);
    _layout = layout;
    final hidden = layout.hidden;
    // While the days are not ready the strip keeps the rows it showed, so
    // no slot moves until they are.
    final restripped = ready
        ? _applyStripRows(_stripRowsOf(layout.barRows))
        : _applyStripRows(_stripRows);
    final relaid = _layOutNotices((
      above: hidden.rowAbove,
      below: hidden.rowBelow,
    ));
    if (!_placementCurrent) {
      _placeLayout(
        disable: !(animate && ready && _syncedReady && !relaid && !restripped),
      );
    }
    final selected = _selectedBlock.value;
    if (selected != null &&
        !layout.pieces.any((piece) {
          return piece.shown.id == selected;
        }) &&
        !layout.bars.any((bar) {
          return bar.shown.id == selected;
        })) {
      _selectedBlock.value = null;
    }
    _syncedReady = ready;
    _hiddenCount.value = hidden;
  }

  /// Turns the kept split into the board's items on the current tracks:
  /// its pieces, leaving out, while the drag's [_Dragging.lifted] names an
  /// entry the split still shows with the times it was lifted with, that
  /// entry's pieces other than the dragged one, and its bars in the strip
  /// rows it shows. Under [BoardAnimationStyle.disabled] where [disable]
  /// holds and where the placements drop the key a drag holds, so that key
  /// leaves with no exit and what replaces it shows at once, until a frame
  /// callback restores the styles' animation; otherwise under the board's
  /// style as it stands, so a drop's glide runs on.
  void _placeLayout({required bool disable}) {
    noteEntryPlace();
    final lifted = _drag?.lifted;
    _placed = (
      layout: _layout,
      tracks: _tracks,
      lifted: lifted,
      shownRows: _shownStripRows,
    );
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
    final shownRows = _shownStripRows;
    for (final bar in _layout.bars) {
      final first = _tracks.columnOf(bar.firstDay);
      final last = _tracks.columnOf(bar.lastDay);
      if (bar.row >= shownRows || first == null || last == null) {
        continue;
      }
      if (dragged != null && !keepsDragged && _keyOf(bar) == dragged) {
        keepsDragged = true;
      }
      placements.add(
        BoardPlacement<GridShape<T>>(
          bar,
          BoardSpan(
            rowStart: _stripStart + bar.row,
            colStart: first,
            colSpan: last - first + 1,
          ),
        ),
      );
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
  /// first layout. A row of another height moves the slots under a still
  /// pointer, so a crossing drag reads its cell again.
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
    _scheduleCrossRead();
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

  /// Whether the board may lift [key]: not while its entry is pending
  /// ([_isPending]), and not when the hours do not hold the entry's start
  /// or end ([DayHours.holdsTimes]), as for an entry an hours change left
  /// outside them, whose cut-off minutes a drop would lose.
  bool _canDrag(GridKey key) {
    if (_isPending(key.id)) {
      return false;
    }
    final shape = _board.itemOf(key);
    if (shape == null) {
      return false;
    }
    final entry = shape.shown.entry;
    return _tracks.hours.holdsTimes(entry.start, entry.end);
  }

  /// The rows a drag stays inside: the slot rows of [_tracks]. They bind a
  /// block's drag; a bar lies in
  /// the strip's rows, which they do not hold, so they bind nothing for it
  /// ([BoardDragConfig.boundsOf]).
  BoardDragBounds _boundsOf(GridKey key) {
    return BoardDragBounds(
      rows: (start: _tracks.firstSlotRow, end: _tracks.lastSlotRow + 1),
    );
  }

  /// Whether the board may land [key] on [span]. No crossing between the
  /// strip and the slots is a board drop: a piece stays inside its day's
  /// rows and a bar inside the strip's, and the grid writes a crossing
  /// itself at its pointer's release ([_handlePointerUp]), after which
  /// every target is refused ([_Dragging.spent]). A piece's move needs
  /// [_policy]'s [CalendarEditPolicy.mayMove], and its resize the edge it
  /// changes in [CalendarEditPolicy.resizableEdges]; then [_rules] must
  /// admit the times ([CalendarEditRules.admitsTimes]): two asks of the
  /// policy at most, and none per neighbouring entry. Where it forbids
  /// overlaps the times must also share none with another entry
  /// ([_meetsOtherEntry]).
  bool _canDropAt(GridKey key, BoardSpan span) {
    noteDropGate();
    if (_drag?.spent ?? false) {
      return false;
    }
    if (key.isBar) {
      return _canDropBar(key, span);
    }
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
    final move = _isMove(key);
    final now = _calendarNow;
    final edges = move ? null : _policy.resizableEdges(entry, now);
    if (move
        ? !_policy.mayMove(entry, now)
        : edges == CalendarResizeEdges.none) {
      return false;
    }
    final times = _timesOf(shape, entry, from, span, move: move);
    if (times == null ||
        (edges != null &&
            !_edgesChange(edges, entry, times.start, times.end)) ||
        !_rules.admitsTimes(entry, times.start, times.end, now)) {
      return false;
    }
    return _allowsOverlaps ||
        !_meetsOtherEntry(key.id, entry, times.start, times.end);
  }

  /// Whether [edges] let [entry] take [start] and [end]: each of its times
  /// that changes on an edge they hold.
  static bool _edgesChange<T>(
    CalendarResizeEdges edges,
    CalendarEntry<T> entry,
    DateTime start,
    DateTime end,
  ) {
    return (start == entry.start || edges.hasStart) &&
        (end == entry.end || edges.hasEnd);
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

  /// Whether the board may land the bar [key] on [span]: inside the
  /// strip's rows, not at its stored columns in another strip row, so a
  /// bar moves only by days, and to times [_policy] admits, a move where
  /// it lets the entry move and a day-edge resize where it lets that edge
  /// resize: two asks of it at most. A bar
  /// shares time with no entry ([rangeSharesTime]), so it lands over
  /// another bar's cells too. Over them a day-edge resize previews the
  /// resized bar's new extent across that bar, which keeps its rect: the
  /// two lie laned in one column by their stored spans and paint in the
  /// board's own item order, which the grid does not set, until the
  /// release stacks them in rows ([TimedGridLayout.bars]). A span of a running
  /// day-edge resize of the bar ([_barResizeOf]) past
  /// [CalendarEditRules.dayLimit]'s days is refused, and holds the drag's
  /// [_Dragging.heldBar] at the range the limit admits, which the release
  /// writes; every other span of that resize clears it.
  bool _canDropBar(GridKey key, BoardSpan span) {
    if (span.rowStart < _stripStart ||
        span.endTrackOn(Axis.vertical) >
            _stripStart + _stripRows + precisionErrorTolerance ||
        span.colStart < 1) {
      return false;
    }
    final from = _board.spanOf(key);
    final shape = _board.itemOf(key);
    if (from == null || shape is! GridBar<T>) {
      return false;
    }
    final edge = _barResizeOf(key, from, span);
    if (from == span) {
      if (edge != null) {
        _holdBar(null);
      }
      return true;
    }
    final entry = shape.shown.entry;
    final now = _calendarNow;
    final times = _barTimesOf(entry, from, span, move: edge == null);
    if (edge != null) {
      final edges = _policy.resizableEdges(entry, now);
      if (edge == BoardResizeEdges.leading ? !edges.hasStart : !edges.hasEnd) {
        _holdBar(null);
        return false;
      }
      if (times != null && !_rules.coversAtMost(times.start, times.end)) {
        final held = _rules.heldToLimit(
          times.start,
          times.end,
          atEnd: edge == BoardResizeEdges.trailing,
        );
        _holdBar(
          held != null &&
                  (held.start != entry.start || held.end != entry.end) &&
                  _rules.admitsTimes(entry, held.start, held.end, now)
              ? held
              : null,
        );
        return false;
      }
      _holdBar(null);
    } else if (span.colStart == from.colStart && span.colSpan == from.colSpan) {
      // Another strip row at the stored columns moves no day.
      return false;
    } else if (!_policy.mayMove(entry, now)) {
      return false;
    }
    return times != null &&
        _rules.admitsTimes(entry, times.start, times.end, now);
  }

  /// The edge a running day-edge resize of the bar [key] drags, where
  /// [span] is one it resolves: the stored span [from]'s rows, and the
  /// edge it does not drag where [from] has it; null for any other span,
  /// which is a move's.
  BoardResizeEdges? _barResizeOf(GridKey key, BoardSpan from, BoardSpan span) {
    final drag = _drag;
    if (drag == null ||
        drag.key != key ||
        span.rowStart != from.rowStart ||
        span.rowSpan != from.rowSpan) {
      return null;
    }
    switch (drag.kind) {
      case BoardDragKind.resizeColStart:
        return _columnEndOf(span) == _columnEndOf(from)
            ? BoardResizeEdges.leading
            : null;
      case BoardDragKind.resizeColEnd:
        return span.colStart == from.colStart
            ? BoardResizeEdges.trailing
            : null;
      case BoardDragKind.move:
      case BoardDragKind.resizeRowStart:
      case BoardDragKind.resizeRowEnd:
        return null;
    }
  }

  /// The last column [span] covers.
  static int _columnEndOf(BoardSpan span) {
    return (span.endTrackOn(Axis.horizontal) - precisionErrorTolerance).ceil() -
        1;
  }

  /// Sets the drag's [_Dragging.heldBar] and the strip's marks for it.
  void _holdBar(({DateTime start, DateTime end})? held) {
    final drag = _drag;
    if (drag == null || held == drag.heldBar) {
      return;
    }
    drag.heldBar = held;
    _updateStripMark();
  }

  /// The start and end a drag of the bar of [entry] from [from] to [to]
  /// gives the entry, or null where the end would not be after the start.
  /// A [move] moves both by the days between the two spans' first columns'
  /// days; a resize sets the start to its first column's day start where
  /// [to] moved that edge, and the end to the start of the day after its
  /// last column's where it moved that one.
  ({DateTime start, DateTime end})? _barTimesOf(
    CalendarEntry<T> entry,
    BoardSpan from,
    BoardSpan to, {
    required bool move,
  }) {
    if (move) {
      final shift = _tracks.dayAt(to.colStart) - _tracks.dayAt(from.colStart);
      return (
        start: dateOfDayNumber(dayNumber(entry.start) + shift),
        end: dateOfDayNumber(dayNumber(entry.end) + shift),
      );
    }
    var start = entry.start;
    var end = entry.end;
    if (to.colStart != from.colStart) {
      start = _tracks.dateAt(to.colStart);
    }
    final last = _columnEndOf(to);
    if (last != _columnEndOf(from)) {
      end = dateOfDayNumber(_tracks.dayAt(last) + 1);
    }
    if (!end.isAfter(start)) {
      return null;
    }
    return (start: start, end: end);
  }

  /// Whether a range from [start] to [end] shares time with a timed entry
  /// other than [id], whose entry is [own], that the store shows on the
  /// days the range covers, shown or not ([rangeSharesTime]): a board
  /// piece in the rows the range covers on the shown columns, one of the
  /// entries those rows can miss that the split indexes
  /// ([TimedGridLayout.loose]), and, for a range with a day outside the
  /// tracks' range, one the store shows there ([_offRangeOver]). An
  /// all-day range shares time with none ([entriesShareTime]). The walk,
  /// as many columns as the range covers, and at most two O(log n)
  /// searches; a store read only for days outside the range no check
  /// since the last clearing of [_offRange] covered.
  bool _meetsOtherEntry(
    String id,
    CalendarEntry<T> own,
    DateTime start,
    DateTime end,
  ) {
    if (isDayStart(start) && isDayStart(end)) {
      return false;
    }
    final firstDay = dayNumber(start);
    final lastDay = lastDayNumberOf(start, end);
    final tracks = _tracks;
    if (_meetsPiece(id, start, end, firstDay, lastDay)) {
      return true;
    }
    if (_layout.loose?.sharesTime(id, own, start, end) ?? false) {
      return true;
    }
    if (firstDay >= tracks.firstDay && lastDay <= tracks.lastDay) {
      return false;
    }
    return _offRangeOver(firstDay, lastDay).sharesTime(id, own, start, end);
  }

  /// The index of the timed entries the store shows on the days outside
  /// the tracks' range that the [dayNumber]s [firstDay] to [lastDay] cover,
  /// [_offRange], having read first the days among them it has not: one
  /// [CalendarStore.entriesBetween] before the range and one after it at
  /// most, each wholly outside the range.
  GridOverlapIndex _offRangeOver(int firstDay, int lastDay) {
    final tracks = _tracks;
    final index = _offRange ??= GridOverlapIndex(
      readFrom: tracks.firstDay,
      readTo: tracks.lastDay,
    );
    if (firstDay < index.readFrom) {
      index.addAll(
        _shownBetween(
          dateOfDayNumber(firstDay),
          dateOfDayNumber(index.readFrom - 1),
        ),
      );
      index.readFrom = firstDay;
    }
    if (lastDay > index.readTo) {
      index.addAll(
        _shownBetween(
          dateOfDayNumber(index.readTo + 1),
          dateOfDayNumber(lastDay),
        ),
      );
      index.readTo = lastDay;
    }
    return index;
  }

  /// Whether a board piece of an entry other than [id] in the rows the
  /// range from [start] to [end] covers on the shown columns of its days,
  /// the [dayNumber]s [firstDay] to [lastDay], shares time with it.
  bool _meetsPiece(
    String id,
    DateTime start,
    DateTime end,
    int firstDay,
    int lastDay,
  ) {
    final first = _tracks.firstColumnFrom(firstDay);
    final last = _tracks.lastColumnUpTo(lastDay);
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
          ((track - _tracks.firstSlotRow) * _tracks.slotMinutes).round();
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

  /// Requests the drop of [key] at [to] ([_requestMove]). Requests nothing
  /// for a pending entry, for one whose start or end the hours do not
  /// hold, for a drop [_timesOf] has no times for, and when the entry would
  /// not change. The board asks [_canDropAt], and so [_policy], before it
  /// reports a drop, a semantics move's at its activation too.
  void _commit(GridKey key, BoardSpan to, {required bool move}) {
    if (_isPending(key.id)) {
      return;
    }
    final from = _board.spanOf(key);
    final shape = _board.itemOf(key);
    final stored = widget.store.storedEntry(key.id);
    if (from == null ||
        shape == null ||
        stored == null ||
        !_tracks.hours.holdsTimes(stored.start, stored.end)) {
      return;
    }
    final times = switch (shape) {
      GridPiece<T>() => _timesOf(shape, stored, from, to, move: move),
      GridBar<T>() => _barTimesOf(stored, from, to, move: move),
    };
    if (times == null) {
      return;
    }
    final requested = stored.copyWith(start: times.start, end: times.end);
    if (requested == stored) {
      return;
    }
    _requestMove(
      CalendarMoveRequest<T>(
        entry: stored,
        requested: requested,
        kind: move ? CalendarMoveKind.move : CalendarMoveKind.resize,
      ),
    );
  }

  /// Notes the board's new drag, which ends a pinch or a create range
  /// running then, the range reporting nothing: selects a move's entry,
  /// hands the board [_fitlessConfig] for a bar's drag, takes as the drag's
  /// [_Dragging.pointer] the first press of the grid on the dragged key,
  /// and for a crossing resize of an end handle ([_isCrossingDrag]) notes
  /// the column it starts in ([_Dragging.resizedColumn]). The lift of a
  /// move of an entry with more than one piece takes its other pieces off
  /// the board.
  void _handleDragStart(GridKey key, BoardDragKind kind) {
    if (!mounted) {
      return;
    }
    if (kind == BoardDragKind.move) {
      _selectedBlock.value = key.id;
    }
    final drag = _Dragging(key, kind);
    final ranging = _range != null;
    setState(() {
      _detachRange();
      _mode = drag;
    });
    if (ranging) {
      _updateStripMark();
    }
    for (final MapEntry(key: pointer, value: pressed) in _pressKeys.entries) {
      if (pressed == key) {
        drag.pointer = pointer;
        break;
      }
    }
    if (drag.pointer != null && _isCrossingDrag(drag)) {
      if (kind == BoardDragKind.resizeRowEnd) {
        drag.resizedColumn = _board.spanOf(key)?.colStart ?? -1;
      }
    }
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
    drag.lifted = (id: id, start: entry.start, end: entry.end);
    _placeLayout(disable: true);
  }

  void _handleDragTarget(GridKey key, BoardDropTarget? target) {
    final drag = _drag;
    if (!mounted || drag == null || drag.key != key) {
      return;
    }
    setState(() {
      drag.resolved = true;
      drag.target = target?.span;
    });
  }

  /// Delivered after the drop's report, and possibly after the board has
  /// left the tree. Puts back a lifted entry's pieces the drop's request
  /// did not, under the board's style as it stands, so a drop's glide runs
  /// on and they enter as added blocks do.
  void _handleDragEnd(GridKey key, bool committed) {
    final drag = _drag;
    if (!mounted || drag == null) {
      return;
    }
    setState(() {
      _mode = const _Idle();
      _clearCross();
    });
    if (drag.lifted != null) {
      _placeLayout(disable: false);
    }
  }

  /// Whether [drag] reads the cell under its pointer as it moves, to cross
  /// where the board's own drag does not: a block's move, into the strip;
  /// a bar's, into the slots; and on more than one day column a piece's
  /// end-handle resize, into a later day.
  bool _isCrossingDrag(_Dragging? drag) {
    if (drag == null) {
      return false;
    }
    return drag.kind == BoardDragKind.move ||
        (drag.kind == BoardDragKind.resizeRowEnd && _tracks.columnCount > 1);
  }

  /// Forgets the drag's crossing ([_Dragging.clearCrossing]) and the marks
  /// it read. The drag's [_Dragging.spent] stays until the drag ends.
  void _clearCross() {
    _drag?.clearCrossing();
    _updateStripMark();
  }

  /// Reads the crossing's cell under the drag's [_Dragging.at], doing
  /// nothing before the drag pointer's first move. Counted as it begins
  /// ([noteCellRead]), so a read that finds no drag counts too.
  void _readCross() {
    noteCellRead();
    final drag = _drag;
    final at = drag?.at;
    if (drag == null || at == null || !mounted) {
      return;
    }
    _crossTo(drag, _rowAt(at.dy), _columnAt(at.dx));
  }

  /// Moves the crossing of [drag] to the cell at [row] and [col], -1 for
  /// none, writing state only where the cell it reads changes: for a
  /// block's move the strip column under it, and the all-day day a release
  /// there gives ([_stripLandingOf]); for a bar's the day column and slot
  /// row under it, the first slot's over the row above the slots, and the
  /// hour a release there gives ([_barLandingOf]); for an end handle's
  /// resize the slot under it on a day later than the piece's, and the end
  /// a release there gives ([_laterDayEndOf]).
  void _crossTo(_Dragging drag, int row, int col) {
    if (drag.kind == BoardDragKind.resizeRowEnd) {
      final later = _isLaterDaySlot(drag, row, col);
      final column = later ? col : -1;
      final slotRow = later ? row : -1;
      if (column == drag.column && slotRow == drag.row) {
        return;
      }
      setState(() {
        drag.column = column;
        drag.row = slotRow;
        drag.laterDayEnd = column == -1
            ? null
            : _laterDayEndOf(drag.key, column, slotRow);
      });
      return;
    }
    if (drag.kind != BoardDragKind.move) {
      return;
    }
    if (!drag.key.isBar) {
      final column = col >= 1 && _isStripRow(row) ? col : -1;
      if (column == drag.column) {
        return;
      }
      setState(() {
        drag.column = column;
        drag.stripLanding = column == -1
            ? null
            : _stripLandingOf(drag.key, column);
      });
      _updateStripMark();
      return;
    }
    var slotRow = -1;
    if (col >= 1) {
      if (row >= _tracks.firstSlotRow && row <= _tracks.lastSlotRow) {
        slotRow = row;
      } else if (row == _tracks.firstSlotRow - 1) {
        slotRow = _tracks.firstSlotRow;
      }
    }
    final column = slotRow == -1 ? -1 : col;
    if (column == drag.column && slotRow == drag.row) {
      return;
    }
    setState(() {
      drag.column = column;
      drag.row = slotRow;
      drag.barLanding = column == -1
          ? null
          : _barLandingOf(drag.key, column, slotRow);
    });
  }

  /// Whether [row] and [col] name a slot in a day column later than the
  /// one of the piece whose end [drag], a crossing resize, drags
  /// ([_Dragging.resizedColumn]): the columns show their days in order, so
  /// a later column is a later day.
  bool _isLaterDaySlot(_Dragging drag, int row, int col) {
    return drag.resizedColumn >= 1 &&
        col > drag.resizedColumn &&
        row >= _tracks.firstSlotRow &&
        row <= _tracks.lastSlotRow;
  }

  /// The all-day day the block [key]'s entry takes when released over the
  /// strip cell of [column]: from that day's start to the next day's, or
  /// null where [_policy] does not let the entry move or refuses those
  /// times, or its answer throws ([_reportPolicyThrow]).
  ({DateTime start, DateTime end})? _stripLandingOf(GridKey key, int column) {
    noteDropGate();
    final shape = _board.itemOf(key);
    if (shape == null) {
      return null;
    }
    final entry = shape.shown.entry;
    final day = _tracks.dayAt(column);
    final start = dateOfDayNumber(day);
    final end = dateOfDayNumber(day + 1);
    final now = _calendarNow;
    try {
      if (!_policy.mayMove(entry, now) ||
          !_rules.admitsTimes(entry, start, end, now)) {
        return null;
      }
    } catch (exception, stack) {
      _reportPolicyThrow(exception, stack);
      return null;
    }
    return (start: start, end: end);
  }

  /// The hour the bar [key]'s entry takes when released over the slot
  /// [row] of [column]: from that slot's start on that column's day to an
  /// hour after it. A start the day's clock repeats takes the occurrence of
  /// the earliest start [_policy] gives the day
  /// ([CalendarEarliestStart.occurrence]), as a create's times do
  /// ([timeAtWallMinute]). Null where the start is a time the clock skips,
  /// where [_policy] does not let the entry move or [_rules] refuse the
  /// range, by the day limit or by the hours and the policy
  /// ([CalendarEditRules.admitsTimes]), or the policy's answer throws
  /// ([_reportPolicyThrow]), or where the policy forbids overlaps and the
  /// range shares time with another timed entry the store shows
  /// ([_meetsOtherEntry]). Three asks of the policy at most, the day's
  /// date read from [_tracks], which holds it.
  ({DateTime start, DateTime end})? _barLandingOf(
    GridKey key,
    int column,
    int row,
  ) {
    noteDropGate();
    final shape = _board.itemOf(key);
    if (shape == null) {
      return null;
    }
    final entry = shape.shown.entry;
    final now = _calendarNow;
    final DateTime? start;
    try {
      if (!_policy.mayMove(entry, now)) {
        return null;
      }
      start = timeAtWallMinute(
        _tracks.dayAt(column) * minutesPerDay + _tracks.minuteAt(row),
        from: _rules.earliestStartOn(_tracks.dateAt(column), now).occurrence,
      );
    } catch (exception, stack) {
      _reportPolicyThrow(exception, stack);
      return null;
    }
    if (start == null) {
      return null;
    }
    final end = start.add(const Duration(hours: 1));
    if (!_rules.coversAtMost(start, end)) {
      return null;
    }
    try {
      if (!_rules.admitsTimes(entry, start, end, now)) {
        return null;
      }
    } catch (exception, stack) {
      _reportPolicyThrow(exception, stack);
      return null;
    }
    if (!_allowsOverlaps && _meetsOtherEntry(key.id, entry, start, end)) {
      return null;
    }
    return (start: start, end: end);
  }

  /// The end the piece [key]'s entry takes when its end handle is let go
  /// over the slot [row] of [column], a later day than the piece's: that
  /// slot's end on that column's day, the earlier instant of a time the
  /// clock repeats, held at [CalendarEditRules.dayLimit]'s days
  /// ([CalendarEditRules.heldToLimit]); null where that end is a time the
  /// clock skips, where [_policy] does not let the entry's end resize or
  /// refuses the range from the entry's start to it, or its answer throws
  /// ([_reportPolicyThrow]), where the hours ([DayHours.holdsTimes])
  /// refuse that range, or where the policy forbids overlaps and it shares
  /// time with another timed entry the store shows ([_meetsOtherEntry]).
  DateTime? _laterDayEndOf(GridKey key, int column, int row) {
    noteDropGate();
    final shape = _board.itemOf(key);
    var end = timeAtWallMinute(
      _tracks.dayAt(column) * minutesPerDay + _tracks.minuteAt(row + 1),
    );
    if (shape == null || end == null) {
      return null;
    }
    final entry = shape.shown.entry;
    final start = entry.start;
    if (!_rules.coversAtMost(start, end)) {
      final held = _rules.heldToLimit(start, end, atEnd: true);
      if (held == null) {
        return null;
      }
      end = held.end;
    }
    if (!_tracks.hours.holdsTimes(start, end)) {
      return null;
    }
    final now = _calendarNow;
    try {
      if (!_policy.resizableEdges(entry, now).hasEnd ||
          !_policy.admitsChange(entry, start, end, now)) {
        return null;
      }
    } catch (exception, stack) {
      _reportPolicyThrow(exception, stack);
      return null;
    }
    if (!_allowsOverlaps && _meetsOtherEntry(key.id, entry, start, end)) {
      return null;
    }
    return end;
  }

  /// Reports a throw of [_policy]'s answer in a gate the grid asks inside
  /// its pointer handlers, which then refuses, as the board answers a
  /// throw of its drop gate ([BoardDragConfig.canDropAt]).
  static void _reportPolicyThrow(Object exception, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: exception,
        stack: stack,
        library: "widgets_extended calendar",
        context: ErrorDescription("while asking a calendar's edit policy"),
      ),
    );
  }

  /// Whether the range from [start] to [end] shares time with a timed
  /// entry other than [id], or with any where [id] is null, that the store
  /// shows on the days the range covers, shown columns or not
  /// ([rangeSharesTime]).
  bool _sharesShownTime(String? id, DateTime start, DateTime end) {
    final shown = _shownBetween(
      dateOfDayNumber(dayNumber(start)),
      dateOfDayNumber(lastDayNumberOf(start, end)),
    );
    for (final other in shown) {
      if (other.id != id && rangeSharesTime(start, end, other.entry)) {
        return true;
      }
    }
    return false;
  }

  /// Reads the crossing's cell again once the board has laid out the rows
  /// a strip row change or a notice change gave, which move the slots
  /// under a still pointer, or after a store change, which can change
  /// what a release there gives ([_askDragAgain]): first as a move off
  /// every cell, then at the drag's [_Dragging.at]. At most one is
  /// pending, and it does nothing once the drag has no [_Dragging.pointer].
  void _scheduleCrossRead() {
    final drag = _drag;
    if (drag == null ||
        drag.pointer == null ||
        _crossReadPending ||
        !_isCrossingDrag(drag)) {
      return;
    }
    _crossReadPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _crossReadPending = false;
      final drag = _drag;
      if (!mounted || drag == null || drag.pointer == null) {
        return;
      }
      _crossTo(drag, -1, -1);
      _readCross();
    });
  }

  /// Marks the strip cells of the day columns that a block over the strip
  /// would land on, that a bar's day-edge resize past the limit is held
  /// at, or that a create range across the strip, being dragged and not
  /// refused, or with its create flow open, covers.
  void _updateStripMark() {
    _StripMark? mark;
    final drag = _drag;
    final held = drag?.heldBar;
    final range = _range;
    if (drag != null && drag.stripLanding != null && drag.column >= 1) {
      mark = (first: drag.column, last: drag.column);
    } else if (held != null) {
      mark = _columnsOf(held.start, held.end);
    } else if (range != null && range.strip && !range.refused) {
      mark = (
        first: math.min(range.anchor.col, range.focus.col),
        last: math.max(range.anchor.col, range.focus.col),
      );
    } else {
      mark = _stripCreating;
    }
    _stripMark.value = mark;
  }

  /// The shown day columns the range from [start] to [end] covers, or null
  /// where it covers none.
  _StripMark? _columnsOf(DateTime start, DateTime end) {
    final first = _tracks.firstColumnFrom(dayNumber(start));
    final last = _tracks.lastColumnUpTo(lastDayNumberOf(start, end));
    return last < first ? null : (first: first, last: last);
  }

  /// The row of the board under [y], a coordinate in the viewport's paint
  /// space, or -1 for none: outside the viewport, and where [y] plus the
  /// vertical scroll offset lies outside the scrolled rows, as an
  /// overscroll can leave it. The grid's own arithmetic over the tracks
  /// [_rowsConfig] builds, allocating nothing: in the leading frozen band
  /// its rows by their settled offsets, over a frozen after-hours row that
  /// row, and between them the scrolled row of [y] plus the offset.
  int _rowAt(double y) {
    final size = _size;
    if (size == null || y < 0.0 || y >= size.height) {
      return -1;
    }
    final int row;
    if (y < _leadingExtent) {
      var top = y;
      if (widget.showsDayHeader && top < _headerHeight) {
        row = 0;
      } else {
        top -= _headerExtent;
        final strip = (top / _allDayRowHeight).floor();
        row = strip < _stripRows
            ? _stripStart + strip
            : _tracks.firstSlotRow - 1;
      }
    } else if (_notices.below && y >= size.height - _noticeHeight) {
      row = _tracks.lastSlotRow + 1;
    } else if (!_verticalScroll.hasClients) {
      return -1;
    } else {
      var content = y + _verticalScroll.position.pixels - _leadingExtent;
      if (!_notices.above) {
        content -= _rowRoom;
      }
      if (content < (_notices.above ? 0.0 : -_rowRoom)) {
        row = -1;
      } else if (content < 0.0) {
        row = _tracks.firstSlotRow - 1;
      } else {
        final slot = (content / _slotHeight).floor();
        if (slot < _tracks.rowCount) {
          row = _tracks.firstSlotRow + slot;
        } else if (!_notices.below &&
            content - _tracks.rowCount * _slotHeight < _rowRoom) {
          row = _tracks.lastSlotRow + 1;
        } else {
          row = -1;
        }
      }
    }
    assert(_debugAgrees(row, y, vertical: true));
    return row;
  }

  /// The column of the board under [x], a coordinate in the viewport's
  /// paint space, or -1 for none: 0 over the gutter, and between it and the
  /// viewport's edge the day column of [x] plus the horizontal scroll
  /// offset, as [_columnsConfig] lays them out.
  int _columnAt(double x) {
    final size = _size;
    if (size == null || x < 0.0 || x >= size.width) {
      return -1;
    }
    final int col;
    if (x < _gutterWidth) {
      col = 0;
    } else if (!_horizontalScroll.hasClients) {
      return -1;
    } else {
      final day =
          1 +
          ((x - _gutterWidth + _horizontalScroll.position.pixels) / _dayWidth)
              .floor();
      col = day >= 1 && day <= _tracks.columnCount ? day : -1;
    }
    assert(_debugAgrees(col, x, vertical: false));
    return col;
  }

  /// Whether [answer], [_rowAt] or [_columnAt] of [at], agrees with the
  /// board viewport's own [RenderBoardViewport.cellAt] there, read in the
  /// gutter for a row and in the first row for a column, or a point a hair
  /// either side, where the two may round a track edge apart.
  bool _debugAgrees(int answer, double at, {required bool vertical}) {
    final viewport = _findViewport();
    if (viewport == null || !viewport.hasSize) {
      return true;
    }
    int probe(double value) {
      final cell = viewport.cellAt(
        vertical ? Offset(0.0, value) : Offset(value, 0.0),
      );
      if (cell == null) {
        return -1;
      }
      return vertical ? cell.row : cell.col;
    }

    const hair = 1e-6;
    return answer == probe(at) ||
        answer == probe(at - hair) ||
        answer == probe(at + hair);
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

  /// The times a release of [_drag] would give its entry: a crossing's
  /// landing while it names a cell, the range a bar's day-edge resize is
  /// held at, and otherwise the board target's; null with no drag, before
  /// its first target, and with no target.
  ({DateTime start, DateTime end})? _landingTimes() {
    final drag = _drag;
    if (drag == null) {
      return null;
    }
    if (drag.crosses) {
      if (drag.kind == BoardDragKind.resizeRowEnd) {
        final end = drag.laterDayEnd;
        final shape = _board.itemOf(drag.key);
        if (end == null || shape == null) {
          return null;
        }
        return (start: shape.shown.entry.start, end: end);
      }
      return drag.key.isBar ? drag.barLanding : drag.stripLanding;
    }
    final held = drag.heldBar;
    if (held != null) {
      return held;
    }
    final target = drag.target;
    if (!drag.resolved || target == null) {
      return null;
    }
    final from = _board.spanOf(drag.key);
    final shape = _board.itemOf(drag.key);
    if (from == null || shape == null) {
      return null;
    }
    final move = drag.kind == BoardDragKind.move;
    return switch (shape) {
      GridPiece<T>() => _timesOf(
        shape,
        shape.shown.entry,
        from,
        target,
        move: move,
      ),
      GridBar<T>() => _barTimesOf(shape.shown.entry, from, target, move: move),
    };
  }

  /// What the landing label says for [_drag] in [strings]: the days and
  /// times a release would give, the times in [TimedGrid.hourLabelFormat]
  /// ([CalendarLocalizations.landing]), or [CalendarLocalizations.noLanding]
  /// for a crossing whose landing is refused and for a move with no
  /// target. Null with no drag, before its first target, and for a resize
  /// with no target.
  String? _landingText(
    CalendarLocalizations strings,
    ({DateTime start, DateTime end})? times,
  ) {
    final drag = _drag;
    if (drag == null) {
      return null;
    }
    if (drag.crosses || drag.heldBar != null) {
      return times == null
          ? strings.noLanding
          : strings.landing(
              times.start,
              times.end,
              _calendarNow.today,
              widget.hourLabelFormat,
            );
    }
    if (!drag.resolved) {
      return null;
    }
    if (drag.target == null) {
      return drag.kind == BoardDragKind.move ? strings.noLanding : null;
    }
    if (times == null) {
      return null;
    }
    return strings.landing(
      times.start,
      times.end,
      _calendarNow.today,
      widget.hourLabelFormat,
    );
  }

  /// The wall minutes the landing outline paints for [times], what
  /// [_landingTimes] gives: a block's move while it names no strip cell,
  /// and a bar's crossing into the slots; none for any other drag, such as
  /// a bar within the strip, whose days the strip shows.
  ({int start, int end})? _outlineOf(({DateTime start, DateTime end})? times) {
    final drag = _drag;
    if (drag == null || times == null || drag.kind != BoardDragKind.move) {
      return null;
    }
    if (drag.key.isBar != drag.crosses) {
      return null;
    }
    return wallSpanOf(times.start, times.end);
  }

  /// The wall minutes the background marks for [times], what
  /// [_landingTimes] gives, while an end handle's resize names a later
  /// day's slot: the range from the entry's start to the end a release
  /// there gives, as a create range's slots are marked; null otherwise.
  ({int start, int end})? _laterDayRangeOf(
    ({DateTime start, DateTime end})? times,
  ) {
    final drag = _drag;
    if (drag == null ||
        times == null ||
        drag.kind != BoardDragKind.resizeRowEnd ||
        !drag.crosses) {
      return null;
    }
    return wallSpanOf(times.start, times.end);
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

  /// Follows [TimedGrid.now], rebuilding only when the line marking the
  /// time moves, shows or goes, or today moves; takes the new value as
  /// [_calendarNow], writing [_limits] in edit mode and refilling a create
  /// range's limits ([_refillRange]); and hands a new today to the header
  /// cells.
  void _handleNow() {
    final now = widget.now.value;
    final mark = _nowMarkOf(now.time);
    final todayMoved = now.today != _calendarNow.today;
    if (mark != _nowMark || todayMoved) {
      setState(() {
        _nowMark = mark;
      });
    }
    if (now == _calendarNow) {
      return;
    }
    _calendarNow = now;
    if (todayMoved) {
      _header.value = (
        tracks: _tracks,
        selectedDay: widget.selectedDay,
        today: now.today,
      );
    }
    if (widget.editable) {
      _limits.value = _limitsOf();
    }
    _refillRange();
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

  /// The all-day strip's cell painting under [local], a point in the
  /// viewport's paint space, in a row that holds bars, or null elsewhere,
  /// the collapsed strip's count row included.
  ({int row, int col})? _stripCellAtLocal(
    RenderBoardViewport<GridKey> viewport,
    Offset local,
  ) {
    final cell = viewport.cellAt(local);
    if (cell == null ||
        !_isStripRow(cell.row) ||
        (_stripCounted && cell.row >= _stripStart + collapsedStripRows) ||
        cell.col < 1) {
      return null;
    }
    return cell;
  }

  /// Whether a press at [global] may create: no gesture runs ([_Idle]),
  /// the grid is neither scrolling nor just stopped by this press, and
  /// either it lies over a body cell whose slot is a time the clock reads,
  /// starting no earlier than the earliest start [_policy] gives its day,
  /// in that start's occurrence ([CalendarEarliestStart.occurrence]), no
  /// block paints under it, and its slot is free ([_slotIsFree]); or over
  /// a strip cell no bar paints over, of a day [_policy] lets an entry
  /// start at its start. Asks the policy once, for the pressed column's
  /// day.
  bool _admits(Offset global) {
    final viewport = _findViewport();
    if (viewport == null || _scrollJustStopped || _mode is! _Idle) {
      return false;
    }
    final vertical = viewport.verticalPosition;
    final horizontal = viewport.horizontalPosition;
    if ((vertical?.isScrollingNotifier.value ?? false) ||
        (horizontal?.isScrollingNotifier.value ?? false)) {
      return false;
    }
    final local = viewport.globalToLocal(global);
    final strip = _stripCellAtLocal(viewport, local);
    if (strip != null) {
      if (viewport.itemAt(local) != null) {
        return false;
      }
      final day = _tracks.dateAt(strip.col);
      return _rules.earliestStartOn(day, _calendarNow).admitsDayStart;
    }
    final cell = _bodyCellAtLocal(viewport, local);
    // A press on a block asks the policy nothing.
    if (cell == null || viewport.itemAt(local) != null) {
      return false;
    }
    final day = _tracks.dateAt(cell.col);
    final start = _rules.earliestStartOn(day, _calendarNow);
    final earliest = start.earliest;
    if (earliest == null) {
      return false;
    }
    final slot = createRangeAt(_tracks, cell, occurrence: start.occurrence);
    return slot != null &&
        !slot.start.isBefore(earliest) &&
        _slotIsFree(cell, slot);
  }

  /// Whether a create range may start on [cell]'s [slot] by the entries
  /// the grid shows: any slot where the policy allows overlaps, and
  /// otherwise one no board piece in [cell]'s row and column shares time
  /// with, as one from 09:10 does with the 09:00 slot, and on a day whose
  /// clock reads a stretch twice, no entry the store shows does, whose
  /// block may lie on other rows ([_sharesShownTime]). A press and a
  /// create range's anchor placement ([_placeRangeAnchor]) both test it.
  bool _slotIsFree(({int row, int col}) cell, CreateRange slot) {
    if (_allowsOverlaps) {
      return true;
    }
    return !_slotMeetsEntry(cell, slot) &&
        // A block lies on the rows of its wall minutes ([wallSpanOf]),
        // which order as its instants do except where the clock reads a
        // stretch twice; only there can it hold the slot from other rows.
        (!_tracks.repeatsStretchAt(cell.col) ||
            !_sharesShownTime(null, slot.start, slot.end));
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
    } else if (notification is ScrollUpdateNotification &&
        notification.depth == 0) {
      _followScroll();
    }
    return false;
  }

  /// Reads the running gesture again as the board's scroll moves the cells
  /// under its pointer: a create range's focus ([_RangeDrag.refocus]), and
  /// a crossing drag's cell ([_readCross]). The board reports both axes'
  /// scroll at depth 0; a scrollable inside a block reports deeper, under
  /// the board's viewport, and moves no cell.
  void _followScroll() {
    switch (_mode) {
      case _Ranging(:final range):
        range.refocus();
      case _Dragging drag:
        if (drag.pointer != null && _isCrossingDrag(drag)) {
          _readCross();
        }
      case _Idle():
      case _Pinching():
        break;
    }
  }

  /// Notes the block or bar a press lies over in [_pressKeys], starts a
  /// resize for a press beside the selected block, noting the piece whose
  /// handles took it, keeps any other press off the selection for
  /// [_handlePointerUp], and in edit mode arms the create gestures for an
  /// admitted press. A listener's pointer down runs before the arena
  /// closes, so they join it beside the scrollable's pan; each recognizer
  /// ignores the pointer kinds it does not support.
  void _handlePointerDown(PointerDownEvent event) {
    _pinch.handleEvent(event);
    final under = _keyAt(event.position);
    if (under != null) {
      _pressKeys[event.pointer] = under;
    }
    final selected = _selectedBlock.value;
    if (selected != null) {
      if (under == null) {
        final beside = _startBeside(event);
        if (beside != null) {
          _pressKeys[event.pointer] = beside;
          return;
        }
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

  /// Feeds the pinch, and for a crossing drag reads the cell under its
  /// pointer's move. The listener sees the move before the board's drag
  /// does: a render object handles a pointer event before the gesture
  /// binding routes it to the recognizers.
  void _handlePointerMove(PointerMoveEvent event) {
    _pinch.handleEvent(event);
    final drag = _drag;
    if (drag == null ||
        event.pointer != drag.pointer ||
        !_isCrossingDrag(drag)) {
      return;
    }
    drag.at = event.localPosition;
    _readCross();
  }

  /// Writes a crossing or a held bar at its drag pointer's release
  /// ([_releaseCross]), and clears the selection for a tap off the
  /// selected entry's blocks, which a press lifting another block, and so
  /// selecting it, is not.
  void _handlePointerUp(PointerUpEvent event) {
    _pinch.handleEvent(event);
    _pressKeys.remove(event.pointer);
    if (event.pointer == _drag?.pointer) {
      _releaseCross(event.localPosition);
    }
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
    _pressKeys.remove(event.pointer);
    if (event.pointer == _drag?.pointer) {
      setState(_clearCross);
    }
  }

  /// The release of the drag pointer at [local], in the viewport's paint
  /// space, before the board's drag hears it. A crossing drag writes from
  /// the cell under [local], so the pointer, not the proxy's centre,
  /// decides where the entry lands: a block over a strip cell becomes
  /// all-day on its day ([_stripLandingOf]), a bar over a slot or the row
  /// above the slots an hour from that slot ([_barLandingOf]), and an end
  /// handle over a later day's slot ends there ([_laterDayEndOf]), each
  /// through one request ([_requestMove]), or none where the landing is
  /// refused; either way [_Dragging.spent] then refuses the board's own
  /// report. A bar's day-edge resize held at [CalendarEditRules.dayLimit]
  /// requests the range it is held at. The request's hold syncs within the
  /// call ([_requestMove]).
  void _releaseCross(Offset local) {
    final drag = _drag;
    if (drag == null) {
      return;
    }
    ({DateTime start, DateTime end})? write;
    if (_isCrossingDrag(drag)) {
      noteCellRead();
      final row = _rowAt(local.dy);
      final col = _columnAt(local.dx);
      if (drag.kind == BoardDragKind.resizeRowEnd) {
        if (!_isLaterDaySlot(drag, row, col)) {
          return;
        }
        final end = _laterDayEndOf(drag.key, col, row);
        final shape = _board.itemOf(drag.key);
        write = end == null || shape == null
            ? null
            : (start: shape.shown.entry.start, end: end);
      } else if (!drag.key.isBar) {
        if (col < 1 || !_isStripRow(row)) {
          return;
        }
        write = _stripLandingOf(drag.key, col);
      } else {
        if (col < 1 ||
            row < _tracks.firstSlotRow - 1 ||
            row > _tracks.lastSlotRow) {
          return;
        }
        write = _barLandingOf(
          drag.key,
          col,
          math.max(row, _tracks.firstSlotRow),
        );
      }
      drag.spent = true;
    } else {
      write = drag.heldBar;
    }
    if (write == null) {
      return;
    }
    final id = drag.key.id;
    final stored = widget.store.storedEntry(id);
    if (stored == null || _isPending(id)) {
      return;
    }
    final requested = stored.copyWith(start: write.start, end: write.end);
    if (requested != stored) {
      _requestMove(
        CalendarMoveRequest<T>(
          entry: stored,
          requested: requested,
          kind: drag.kind == BoardDragKind.move
              ? CalendarMoveKind.move
              : CalendarMoveKind.resize,
        ),
      );
    }
  }

  /// Starts a resize of a selected block for a press over a body cell,
  /// and over no block, on a strip outside a selected block holding a
  /// handle beside one of its edges, which the board, hit-testing a block
  /// only within its bounds, gives no handle; returns the key of the piece
  /// whose handles took it, or null where none did.
  GridKey? _startBeside(PointerDownEvent event) {
    if (_handles.isEmpty || _bodyCellAt(event.position) == null) {
      return null;
    }
    return _handles.startOutside(event);
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

  /// Creates at the slot or the strip cell a tap let go over, unless
  /// another gesture runs by then.
  void _handleTapUp(TapUpDetails details) {
    final viewport = _findViewport();
    if (viewport == null || _mode is! _Idle) {
      return;
    }
    final local = viewport.globalToLocal(details.globalPosition);
    final strip = _stripCellAtLocal(viewport, local);
    if (strip != null) {
      _create(strip, strip, _stripRangeOver(strip.col, strip.col), strip: true);
      return;
    }
    final cell = _bodyCellAtLocal(viewport, local);
    if (cell == null) {
      return;
    }
    // The press was admitted ([_admits]); the slot's times take the
    // occurrence of its day's earliest start.
    final day = _tracks.dateAt(cell.col);
    final range = createRangeAt(
      _tracks,
      cell,
      occurrence: _rules.earliestStartOn(day, _calendarNow).occurrence,
    );
    if (range == null) {
      return;
    }
    _create(cell, cell, range);
  }

  /// Reports [range] through [TimedGrid.onCreate], marking until the
  /// create flow closes the range from the slot of [anchor] to that of
  /// [focus], or for a range across the strip, [strip], the strip cells of
  /// their columns and those between.
  void _create(
    ({int row, int col}) anchor,
    ({int row, int col}) focus,
    CreateRange range, {
    bool strip = false,
  }) {
    final create = ++_creates;
    setState(() {
      if (strip) {
        _creating = null;
        _stripCreating = (
          first: math.min(anchor.col, focus.col),
          last: math.max(anchor.col, focus.col),
        );
      } else {
        _creating = (anchor: anchor, focus: focus);
        _stripCreating = null;
      }
    });
    _updateStripMark();
    widget.onCreate(range).whenComplete(() {
      if (mounted && create == _creates) {
        setState(() {
          _creating = null;
          _stripCreating = null;
        });
        _updateStripMark();
      }
    });
  }

  /// The all-day range a create across the strip from the column [anchor]
  /// to [focus] picks: the earlier column's day start to the start of the
  /// day after the later one's, over every day between, shown or not.
  CreateRange _stripRangeOver(int anchor, int focus) {
    return CreateRange(
      start: _tracks.dateAt(math.min(anchor, focus)),
      end: dateOfDayNumber(_tracks.dayAt(math.max(anchor, focus)) + 1),
    );
  }

  /// Begins a create range at [position], unless another gesture runs.
  Drag? _beginRange(Offset position) {
    final viewport = _findViewport();
    if (viewport == null || _mode is! _Idle) {
      return null;
    }
    final point = viewport.globalToLocal(position);
    final strip = _stripCellAtLocal(viewport, point);
    final anchor = strip ?? _bodyCellAtLocal(viewport, point);
    if (anchor == null) {
      return null;
    }
    final range = _RangeDrag<T>(this, anchor, point, strip: strip != null);
    setState(() {
      _mode = _Ranging<T>(range);
    });
    _updateStripMark();
    return range;
  }

  /// Moves [range]'s focus toward [focus], as far as [_reach] takes it, or
  /// for a range across the strip [_reachStrip].
  void _moveRange(_RangeDrag<T> range, ({int row, int col}) focus) {
    if (!mounted || !identical(_range, range)) {
      return;
    }
    final reached = range.strip
        ? _reachStrip(range, focus)
        : _reach(range, focus);
    if (reached == range.focus) {
      return;
    }
    setState(() {
      range.focus = reached;
    });
    _updateStripMark();
  }

  /// The focus a range across the strip from [range]'s anchor reaches
  /// toward [focus]'s column: held, toward earlier days, at the first
  /// column from it whose day [range]'s limits let an entry start at its
  /// start ([_RangeDrag.stripFrom]), and at [CalendarEditRules.dayLimit]'s
  /// days ([CalendarEditRules.heldToLimit]), however far past them [focus]
  /// lies. Constant work per call.
  ({int row, int col}) _reachStrip(
    _RangeDrag<T> range,
    ({int row, int col}) focus,
  ) {
    final anchor = range.anchor;
    var col = focus.col;
    if (col < anchor.col) {
      col = range.stripFrom[col - 1];
    }
    final picked = _stripRangeOver(anchor.col, col);
    if (!_rules.coversAtMost(picked.start, picked.end)) {
      final held = _rules.heldToLimit(
        picked.start,
        picked.end,
        atEnd: col >= anchor.col,
      );
      if (held != null) {
        col = col >= anchor.col
            ? math.max(
                anchor.col,
                _tracks.lastColumnUpTo(lastDayNumberOf(held.start, held.end)),
              )
            : math.min(
                anchor.col,
                _tracks.firstColumnFrom(dayNumber(held.start)),
              );
      }
    }
    return (row: anchor.row, col: col);
  }

  /// The focus [range] reaches toward [focus], in wall-minute order of the
  /// cells' slots: held at the last slot that does not pass the nearest
  /// entry [range] read on either side of its anchor, for its start at the
  /// earliest start its limits give the focus's column
  /// ([_RangeDrag.firstFrom]), and at [CalendarEditRules.dayLimit]'s days
  /// ([CalendarEditRules.heldToLimit]), however far past them [focus] lies.
  /// Constant work per call: the entries and the limits were read before.
  ({int row, int col}) _reach(_RangeDrag<T> range, ({int row, int col}) focus) {
    final anchor = range.anchor;
    final anchorWall = slotWallMinuteOf(_tracks, anchor);
    final focusWall = slotWallMinuteOf(_tracks, focus);
    if (focusWall >= anchorWall) {
      // A create's times keep the occurrence of the earliest start of the
      // day it starts on, as [createRangeOver] reads them.
      final occurrence = range.occurrences[anchor.col - 1];
      final limit = range.nextStart;
      if (limit != null && focusWall + _tracks.slotMinutes > limit) {
        focus = _lastCellEndingBy(limit, anchor);
      }
      final end = timeAtWallMinute(
        slotWallMinuteOf(_tracks, focus) + _tracks.slotMinutes,
        from: occurrence,
      );
      final start = timeAtWallMinute(anchorWall, from: occurrence);
      if (start != null && end != null && !_rules.coversAtMost(start, end)) {
        final held = _rules.heldToLimit(start, end, atEnd: true);
        if (held != null) {
          focus = _lastCellEndingBy(wallMinuteOf(held.end), anchor);
        }
      }
      return focus;
    }
    final from = range.firstFrom[focus.col - 1];
    final previous = range.previousEnd;
    final earliest = previous == null ? from : math.max(previous, from);
    if (focusWall < earliest) {
      focus = _firstCellStartingFrom(earliest, anchor);
    }
    final occurrence = range.occurrences[focus.col - 1];
    final start = timeAtWallMinute(
      slotWallMinuteOf(_tracks, focus),
      from: occurrence,
    );
    final end = timeAtWallMinute(
      anchorWall + _tracks.slotMinutes,
      from: occurrence,
    );
    if (start != null && end != null && !_rules.coversAtMost(start, end)) {
      final held = _rules.heldToLimit(start, end, atEnd: false);
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
        final slots = (into - hours.start) ~/ tracks.slotMinutes;
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
            (into - hours.start + tracks.slotMinutes - 1) ~/ tracks.slotMinutes;
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

  /// Reports the range [range] was let go at: its anchor's slot where its
  /// focus never left it, and otherwise the range to its focus, each in
  /// the occurrence of the earliest start of the day it starts on
  /// ([_RangeDrag.occurrences]); nothing where that range has an end the
  /// clock skips, or while [range] is refused. A range across the strip
  /// reports the days of its columns ([_stripRangeOver]).
  void _endRange(_RangeDrag<T> range) {
    if (!mounted || !identical(_range, range)) {
      return;
    }
    final anchor = range.anchor;
    final focus = range.focus;
    final CreateRange? created;
    if (range.refused) {
      created = null;
    } else if (range.strip) {
      created = _stripRangeOver(anchor.col, focus.col);
    } else if (focus == anchor) {
      created = createRangeAt(
        _tracks,
        anchor,
        occurrence: range.occurrences[anchor.col - 1],
      );
    } else {
      final first =
          slotWallMinuteOf(_tracks, focus) < slotWallMinuteOf(_tracks, anchor)
          ? focus
          : anchor;
      created = createRangeOver(
        _tracks,
        anchor,
        focus,
        occurrence: range.occurrences[first.col - 1],
      );
    }
    _clearRange(range);
    if (created == null) {
      return;
    }
    _create(anchor, focus, created, strip: range.strip);
  }

  /// Refills the running create range's limits at a new [_calendarNow]
  /// ([_RangeDrag.readLimit]) and places its anchor by them
  /// ([_placeRangeAnchor]). A throw of the policy is reported, and the
  /// range is detached and cleared, so it creates nothing and no release
  /// reads limits two minutes gave. Runs after the now mark and [_limits]
  /// are written.
  void _refillRange() {
    final range = _range;
    if (range == null) {
      return;
    }
    try {
      range.readLimit();
    } catch (exception, stack) {
      _reportPolicyThrow(exception, stack);
      setState(_detachRange);
      _updateStripMark();
      return;
    }
    _placeRangeAnchor(range);
  }

  /// Places [range]'s anchor by its limits and the entries as they stand.
  /// It stays, admitted, where its column's earliest start is on its day
  /// and not after the anchor's slot, or for a range across the strip at
  /// the day's start. Otherwise a range over the slots takes the first
  /// slot of that column from that earliest start that a press there would
  /// start a range on ([_slotIsFree]); and where the column takes no
  /// start, where no slot of it from there is free, and for a range across
  /// the strip, the anchor stays and [_RangeDrag.refused] holds, so the
  /// grid marks no range and the release creates nothing, until a later
  /// placement admits it. A range over the slots then reads its conflicts
  /// again, and the focus is held again from the cell under the pointer,
  /// so a release with no move after it reports the range held. The grid
  /// builds again where the anchor, the focus or the refusal changed.
  void _placeRangeAnchor(_RangeDrag<T> range) {
    final was = (
      anchor: range.anchor,
      focus: range.focus,
      refused: range.refused,
    );
    final col = range.anchor.col;
    final from = range.firstFrom[col - 1];
    final dayStart = _tracks.dayAt(col) * minutesPerDay;
    if (range.strip) {
      range.refused = from != dayStart;
    } else if (from >= dayStart + minutesPerDay) {
      // Its day takes no start.
      range.refused = true;
    } else if (from <= slotWallMinuteOf(_tracks, range.anchor)) {
      range.refused = false;
    } else {
      final free = _firstFreeSlotFrom(col, from, range.occurrences[col - 1]);
      range.refused = free == null;
      if (free != null) {
        range.anchor = free;
      }
    }
    if (!range.strip) {
      range.readConflicts();
    }
    final viewport = _findViewport();
    var target = range.focus;
    if (viewport != null) {
      if (range.strip) {
        final over = _stripCellAtLocal(viewport, range._point);
        if (over != null) {
          target = (row: range.anchor.row, col: over.col);
        }
      } else {
        target = _bodyCellAtLocal(viewport, range._point) ?? target;
      }
    }
    range.focus = range.strip
        ? _reachStrip(range, target)
        : _reach(range, target);
    if (range.anchor != was.anchor ||
        range.focus != was.focus ||
        range.refused != was.refused) {
      setState(() {});
      _updateStripMark();
    }
  }

  /// The first slot of the day column [col], starting at the wall minute
  /// [from] or after it in [occurrence]'s occurrence, that a press there
  /// would start a create range on ([_slotIsFree]); null where none is.
  /// Tests at most the column's slots.
  ({int row, int col})? _firstFreeSlotFrom(
    int col,
    int from,
    DateTime? occurrence,
  ) {
    final tracks = _tracks;
    final into = from - tracks.dayAt(col) * minutesPerDay - tracks.hours.start;
    final first =
        tracks.firstSlotRow +
        math.max<int>(0, (into + tracks.slotMinutes - 1) ~/ tracks.slotMinutes);
    for (var row = first; row <= tracks.lastSlotRow; row++) {
      final cell = (row: row, col: col);
      final slot = createRangeAt(tracks, cell, occurrence: occurrence);
      if (slot != null && _slotIsFree(cell, slot)) {
        return cell;
      }
    }
    return null;
  }

  void _clearRange(_RangeDrag<T> range) {
    if (!mounted || !identical(_range, range)) {
      return;
    }
    setState(() {
      _mode = const _Idle();
    });
    _updateStripMark();
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
    if (_isStripRow(cell.row)) {
      final row = cell.row - _stripStart;
      if (cell.col == 0) {
        if (row == 0) {
          return _StripCorner(strip: _strip, onCollapse: _collapseStrip);
        }
        return const _GutterCell();
      }
      return _StripCell(
        strip: _strip,
        mark: _stripMark,
        column: cell.col,
        row: row,
        last: row == _stripRows - 1,
        onExpand: _expandStrip,
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
      final minutes = _gutterMinutesOf(cell.row);
      if (minutes.isEmpty) {
        return const _GutterCell();
      }
      return _GutterLabel(minutes: minutes, format: widget.hourLabelFormat);
    }
    // Body cells build nothing: the background painter draws the grid.
    return null;
  }

  /// The minutes the foreground labels on the top and bottom lines of the
  /// gutter cell of [row], which a screen reader hears it name.
  List<int> _gutterMinutesOf(int row) {
    return <int>[
      if (_GridForegroundPainter.labelsRow(_tracks, row)) _tracks.minuteAt(row),
      if (row == _tracks.lastSlotRow) _tracks.hours.end,
    ];
  }

  Widget _buildPlacement(
    BuildContext context,
    BoardItemView<GridKey, GridShape<T>> view,
  ) {
    final shape = view.item;
    switch (shape) {
      case GridPiece<T>():
        return _buildPiece(shape, view.span);
      case GridBar<T>():
        return _buildBar(shape);
    }
  }

  Widget _buildBar(GridBar<T> bar) {
    final entry = bar.shown;
    final days = _tracks.columnCount > 1;
    return _Bar<T>(
      key: allDayBarKey(entry.id),
      entry: entry,
      details: CalendarChipDetails(
        card: false,
        continuesBefore: bar.continuesBefore,
        continuesAfter: bar.continuesAfter,
        hourLabelFormat: widget.hourLabelFormat,
      ),
      builder: _chipBuilder,
      selection: _selectedBlock,
      limits: _limits,
      onSelect: () {
        _selectedBlock.value = entry.id;
      },
      startHandle: days && !bar.continuesBefore,
      endHandle: days && !bar.continuesAfter,
      onOpen: entry.pending
          ? null
          : () {
              widget.onOpenEntry(entry.id);
            },
    );
  }

  /// Shows every bar row of the collapsed strip, from a tap on a "+N"
  /// pill: the kept split, placed again on the moved slot rows.
  void _expandStrip() {
    if (_stripExpanded) {
      return;
    }
    setState(() {
      _stripExpanded = true;
    });
    if (_applyStripRows(_stripRowsOf(_layout.barRows))) {
      _placeLayout(disable: true);
    }
  }

  /// Collapses the expanded strip to three rows and its count row, from a
  /// tap on the "Less" pill.
  void _collapseStrip() {
    if (!_stripExpanded) {
      return;
    }
    setState(() {
      _stripExpanded = false;
    });
    if (_applyStripRows(_stripRowsOf(_layout.barRows))) {
      _placeLayout(disable: true);
    }
  }

  Widget _buildPiece(GridPiece<T> piece, BoardSpan span) {
    final entry = piece.shown;
    final hours = _tracks.hours;
    final cutAtStart = piece.start < hours.start;
    final cutAtEnd = piece.end > hours.end;
    return _Block<T>(
      key: blockKey(entry.id, dateOfDayNumber(piece.day)),
      pieceKey: _keyOf(piece),
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
        hourLabelFormat: widget.hourLabelFormat,
      ),
      builder: _blockBuilder,
      selection: _selectedBlock,
      limits: _limits,
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
      end: math.max(from, to) + _tracks.slotMinutes,
    );
  }

  /// The wall minutes next to [anchor]'s slot that a create range from it
  /// may not pass, in [occurrence]'s occurrence, which its times take
  /// ([_reach]): the last not after the earliest start after the slot's
  /// start ([lastWallMinuteNotAfter]), and the first not before the latest
  /// end before its end ([firstWallMinuteNotBefore]), among the timed
  /// entries the store shows on the grid's days; each null where there is
  /// none.
  ({int? next, int? previous}) _conflictsAround(
    ({int row, int col}) anchor,
    DateTime? occurrence,
  ) {
    final wall = slotWallMinuteOf(_tracks, anchor);
    final start = timeAtWallMinute(wall, from: occurrence);
    final end = timeAtWallMinute(wall + _tracks.slotMinutes, from: occurrence);
    int? next;
    int? previous;
    if (start == null || end == null) {
      return (next: next, previous: previous);
    }
    for (final shown in _shownBetween(widget.firstDay, _lastDay)) {
      final entry = shown.entry;
      if (entry.isAllDay) {
        continue;
      }
      if (entry.start.isAfter(start)) {
        final at = lastWallMinuteNotAfter(entry.start, from: occurrence);
        next = next == null ? at : math.min(next, at);
      }
      if (entry.end.isBefore(end)) {
        final at = firstWallMinuteNotBefore(entry.end, from: occurrence);
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
    final strings = CalendarLocalizations.of(context);
    _hourLabels.update(
      labelStyle,
      MediaQuery.textScalerOf(context),
      widget.hourLabelFormat,
      strings,
      _tracks,
      widget.onZoom == null ? widget.minSlotHeight : minSlotHeightLow,
    );
    _labelRoom = _hourLabels.height / 2 + _HourLabels.gap;
    final slotRange = range == null || range.strip || range.refused
        ? null
        : range;
    final rangeAnchor = slotRange?.anchor ?? _creating?.anchor;
    final rangeFocus = slotRange?.focus ?? _creating?.focus;
    final landing = _landingTimes();
    final listener = Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
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
            today: _calendarNow.today,
            range:
                _laterDayRangeOf(landing) ??
                (rangeAnchor == null || rangeFocus == null
                    ? null
                    : _wallSpanOfCells(rangeAnchor, rangeFocus)),
            landing: _outlineOf(landing),
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
          drag: widget.editable
              ? ((drag?.key.isBar ?? false) || _allowsOverlaps
                    ? _fitlessConfig
                    : _editConfig)
              : _viewConfig,
          verticalDetails: ScrollableDetails.vertical(
            controller: _verticalScroll,
          ),
          horizontalDetails: ScrollableDetails.horizontal(
            controller: _horizontalScroll,
          ),
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
            if (drag != null)
              Positioned(
                top: _leadingExtent + 8.0,
                left: _gutterWidth + 8.0,
                right: 8.0,
                // The range a bar's day-edge resize is held at changes
                // with the strip's marks, which the drop gate writes.
                child: ValueListenableBuilder<_StripMark?>(
                  valueListenable: _stripMark,
                  builder: (context, mark, child) {
                    final text = _landingText(strings, _landingTimes());
                    if (text == null) {
                      return const SizedBox.shrink();
                    }
                    return _LandingLabel(text: text);
                  },
                ),
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
/// pointer, or for a range across the all-day strip, [strip], to the strip
/// cell under it.
///
/// The pointer is tracked in the viewport's paint space, as the press
/// converted plus the sum of every update's delta: a multi-drag recognizer
/// reports the move that accepted it as a delta from the press, with the
/// press's own position. The grid refocuses the range ([refocus]) on
/// each scroll of its own scrollables ([_TimedGridState._followScroll]),
/// so the focus stays the cell under the pointer while content scrolls
/// beneath it; and it reads that cell through the viewport the grid finds
/// then, so a board built anew under it is read. Where the
/// grid's policy forbids overlaps, a range over the slots reads the
/// entries that hold it once, when it begins, and again on a store notify
/// ([readConflicts]).
class _RangeDrag<T> extends Drag {
  _RangeDrag(this._grid, this.anchor, this._point, {required this.strip})
    : focus = anchor,
      occurrences = List<DateTime?>.filled(anchor.col, null),
      firstFrom = List<int>.filled(anchor.col, 0),
      stripFrom = List<int>.filled(anchor.col, 0) {
    readLimit();
    readConflicts();
  }

  final _TimedGridState<T> _grid;

  /// The cell the range runs from: the pressed one, or one a refill moved
  /// it to ([_TimedGridState._placeRangeAnchor]).
  ({int row, int col}) anchor;

  /// Whether the range runs over the all-day strip's cells, picking whole
  /// days, rather than over the slots.
  final bool strip;

  /// The cell last under the pointer, as far as the range reaches: for a
  /// range over the slots a body cell, unchanged while the pointer is over
  /// the header, the gutter or past the lattice; for one across the strip
  /// the anchor's row in the column of the strip cell last under it.
  ({int row, int col}) focus;

  /// Whether a refill left [anchor] on a day or a slot the range may not
  /// start on, so the grid marks no range and the release creates nothing.
  bool refused = false;

  /// By column, `[c - 1]` for column `c`, from the first to [anchor]'s:
  /// the earliest start the policy gives the column's day where it lies
  /// after the day's start, the occurrence a range starting on that day
  /// takes its times in, and null otherwise.
  final List<DateTime?> occurrences;

  /// By column as [occurrences]: the first wall minute a range starting on
  /// the column's day may start at, the earliest start's own, one more
  /// where it lies inside a minute, and the day's start for one at it or
  /// before it; for a column before [anchor]'s whose day takes no start,
  /// the next column's value, and for [anchor]'s own the next day's start.
  final List<int> firstFrom;

  /// By column as [occurrences]: the first column from it to [anchor]'s
  /// whose day takes a start at the day's start, which a range across the
  /// strip reaching earlier stops at, and [anchor]'s where none before it
  /// does.
  final List<int> stripFrom;

  /// The wall minute of the earliest start after [anchor]'s slot, which a
  /// range reaching later may not pass, or null.
  int? nextStart;

  /// The wall minute of the latest end before [anchor]'s slot, which a
  /// range reaching earlier may not pass, or null.
  int? previousEnd;

  Offset _point;

  /// Asks the grid's policy once for the earliest start on each column's
  /// day, from [anchor]'s back to the first, at the grid's [CalendarNow],
  /// and fills [occurrences], [firstFrom] and [stripFrom] in place.
  void readLimit() {
    final grid = _grid;
    final tracks = grid._tracks;
    final rules = grid._rules;
    final now = grid._calendarNow;
    for (var col = anchor.col; col >= 1; col--) {
      final index = col - 1;
      final last = col == anchor.col;
      final start = rules.earliestStartOn(tracks.dateAt(col), now);
      occurrences[index] = start.occurrence;
      firstFrom[index] = start.closesDay && !last
          ? firstFrom[index + 1]
          : start.firstWallMinute;
      stripFrom[index] = start.admitsDayStart || last
          ? col
          : stripFrom[index + 1];
    }
  }

  /// Reads the entries next to [anchor]'s slot that hold the range, in
  /// the occurrence of its column's earliest start. A range across the
  /// strip, of all-day days, is held by none, and so is any range where
  /// the grid's policy allows overlaps.
  void readConflicts() {
    if (strip || _grid._allowsOverlaps) {
      nextStart = null;
      previousEnd = null;
      return;
    }
    final conflicts = _grid._conflictsAround(
      anchor,
      occurrences[anchor.col - 1],
    );
    nextStart = conflicts.next;
    previousEnd = conflicts.previous;
  }

  @override
  void update(DragUpdateDetails details) {
    _point += details.delta;
    refocus();
  }

  /// Moves the focus toward the cell under the pointer, read at the
  /// grid's scroll offsets as they stand.
  void refocus() {
    final viewport = _grid._findViewport();
    if (viewport == null) {
      return;
    }
    final ({int row, int col})? cell;
    if (strip) {
      final over = _grid._stripCellAtLocal(viewport, _point);
      cell = over == null ? null : (row: anchor.row, col: over.col);
    } else {
      cell = _grid._bodyCellAtLocal(viewport, _point);
    }
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
                    CalendarLocalizations.of(
                      context,
                    ).weekdayShortName(day.weekday),
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
/// which [_EntryContent] fills with what [builder] draws for [entry] and
/// [details]; the block draws nothing of the entry itself. A long press on
/// it moves its entry where the policy [limits] hold lets it move
/// ([_movesOf]), and otherwise reports [onSelect] where it lets an edge of
/// it resize, and while [selection] names its entry, an outline lies over
/// it, with the top resize handle where [startHandle] holds and the
/// policy lets the start's edge resize, and the bottom one where
/// [endHandle] holds and it lets the end's ([_BlockHandles]). Its tap,
/// long press and move take a press anywhere in the box, whatever the
/// builder paints there.
class _Block<T> extends StatelessWidget {
  const _Block({
    super.key,
    required this.pieceKey,
    required this.entry,
    required this.details,
    required this.builder,
    required this.selection,
    required this.limits,
    required this.onSelect,
    required this.handles,
    required this.startHandle,
    required this.endHandle,
    required this.onOpen,
  });

  /// The board key of the block's piece, which its handles report for a
  /// press outside it.
  final GridKey pieceKey;

  final CalendarShownEntry<T> entry;

  /// What the grid decides about the block's appearance, which [builder]
  /// draws from.
  final CalendarBlockDetails details;

  final CalendarBlockBuilder<T> builder;

  /// The id of the entry whose blocks are selected, or null.
  final ValueListenable<String?> selection;

  /// The policy and its time in edit mode, or null out of it.
  final ValueListenable<_EditLimits<T>?> limits;

  /// A long press on a block of an entry that does not move but resizes
  /// asks to select it.
  final VoidCallback onSelect;

  /// Where the handles register while this block is selected.
  final _HandlesSlot handles;

  /// Whether the block, selected, has a handle on its top edge where the
  /// policy lets the start resize: the piece holds the entry's start, and
  /// the hours do not cut it.
  final bool startHandle;

  /// Whether the block, selected, has a handle on its bottom edge where
  /// the policy lets the end resize: the piece holds the entry's end, and
  /// the hours do not cut it.
  final bool endHandle;

  /// Null while the entry is pending, so a tap opens nothing.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final content = _EntryContent<T, CalendarBlockDetails>(
      entry: entry,
      details: details,
      builder: builder,
    );
    // One shape selected or not, and limited or not, so neither change
    // drops the block's State.
    return _buildEditAnswers<T>(
      selection: selection,
      limits: limits,
      entry: entry,
      child: content,
      builder: (context, answers, child) {
        final (:selected, :moves, :edges) = answers;
        return Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            BoardDelayedDragHandle(
              enabled: moves,
              child: Padding(
                padding: const EdgeInsets.all(1.0),
                child: GestureDetector(
                  // Opaque, so the box takes a press wherever the builder
                  // paints nothing, and the drag handle deferring to it
                  // does too.
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  onLongPress: !moves && edges != CalendarResizeEdges.none
                      ? onSelect
                      : null,
                  child: child,
                ),
              ),
            ),
            if (selected)
              Positioned.fill(
                child: _BlockHandles(
                  key: blockHandlesKey(entry.id),
                  id: entry.id,
                  pieceKey: pieceKey,
                  slot: handles,
                  resizesStart: startHandle && edges.hasStart,
                  resizesEnd: endHandle && edges.hasEnd,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// What a block or a bar shows of the selection and the policy: whether
/// the selection names its entry, whether the entry moves, and the edges
/// that resize it.
typedef _EditAnswers = ({bool selected, bool moves, CalendarResizeEdges edges});

/// Builds [builder] from [entry]'s [_EditAnswers] under [selection] and
/// [limits], with [child], and builds it again only where they change.
/// The selection is compared first, so a new selection asks the policy
/// again only of the entries it selects or deselects, while a new value of
/// [limits], as at a new minute, asks it of every entry.
Widget _buildEditAnswers<T>({
  required ValueListenable<String?> selection,
  required ValueListenable<_EditLimits<T>?> limits,
  required CalendarShownEntry<T> entry,
  required Widget child,
  required Widget Function(
    BuildContext context,
    _EditAnswers answers,
    Widget? child,
  )
  builder,
}) {
  return AnswerBuilder<bool>(
    listenables: <Listenable>[selection],
    answer: () {
      return selection.value == entry.id;
    },
    child: child,
    builder: (context, selected, child) {
      return AnswerBuilder<_EditAnswers>(
        listenables: <Listenable>[limits],
        answer: () {
          return _editAnswersOf(limits, entry, selected: selected);
        },
        builder: builder,
        child: child,
      );
    },
  );
}

/// [entry]'s [_EditAnswers] under [limits], [selected] or not. The edges
/// are asked only of an entry that is selected or does not move, the only
/// ones whose block or bar shows them; any other shows both.
_EditAnswers _editAnswersOf<T>(
  ValueListenable<_EditLimits<T>?> limits,
  CalendarShownEntry<T> entry, {
  required bool selected,
}) {
  final limited = limits.value;
  final moves = _movesOf(limited, entry.entry);
  final edges = moves && !selected
      ? CalendarResizeEdges.both
      : _edgesOf(limited, entry.entry);
  return (selected: selected, moves: moves, edges: edges);
}

/// Whether [limits] let [entry] move ([CalendarEditPolicy.mayMove]); out
/// of edit mode, where [limits] is null, it asks nothing and answers true.
bool _movesOf<T>(_EditLimits<T>? limits, CalendarEntry<T> entry) {
  return limits == null || limits.policy.mayMove(entry, limits.now);
}

/// The edges [limits] let [entry] resize
/// ([CalendarEditPolicy.resizableEdges]); out of edit mode, where [limits]
/// is null, it asks nothing and answers both.
CalendarResizeEdges _edgesOf<T>(
  _EditLimits<T>? limits,
  CalendarEntry<T> entry,
) {
  return limits == null
      ? CalendarResizeEdges.both
      : limits.policy.resizableEdges(entry, limits.now);
}

/// One bar of the all-day strip: the lane the board places it in, inset
/// 1 px, which what [builder] draws for [entry] and [details] fills. It
/// takes presses as a [_Block] does: a tap reports [onOpen], which is null
/// while the entry is pending; a long press moves its entry where the
/// policy [limits] hold lets it move ([_movesOf]), and otherwise reports
/// [onSelect] where it lets an edge of it resize; and while [selection]
/// names its entry an outline lies over it, with the left grip where
/// [startHandle] holds and the policy lets the start's edge resize, and
/// the right one where [endHandle] holds and it lets the end's
/// ([_BarHandles]).
class _Bar<T> extends StatelessWidget {
  const _Bar({
    super.key,
    required this.entry,
    required this.details,
    required this.builder,
    required this.selection,
    required this.limits,
    required this.onSelect,
    required this.startHandle,
    required this.endHandle,
    required this.onOpen,
  });

  final CalendarShownEntry<T> entry;

  /// The bar's chip form and its continued ends, which [builder] draws
  /// from.
  final CalendarChipDetails details;

  final CalendarChipBuilder<T> builder;

  /// The id of the entry whose blocks or bar are selected, or null.
  final ValueListenable<String?> selection;

  /// The policy and its time in edit mode, or null out of it.
  final ValueListenable<_EditLimits<T>?> limits;

  /// A long press on the bar of an entry that does not move but resizes
  /// asks to select it.
  final VoidCallback onSelect;

  /// Whether the bar, selected, has a grip on its left edge where the
  /// policy lets the start resize, which drags its first day: on a grid of
  /// more than one day column, where the entry does not continue before
  /// the bar.
  final bool startHandle;

  /// Whether the bar, selected, has a grip on its right edge where the
  /// policy lets the end resize, which drags its last day: on a grid of
  /// more than one day column, where the entry does not continue after the
  /// bar.
  final bool endHandle;

  /// Null while the entry is pending, so a tap opens nothing.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final content = _EntryContent<T, CalendarChipDetails>(
      entry: entry,
      details: details,
      builder: builder,
    );
    // One shape selected or not, and limited or not, so neither change
    // drops the bar's State.
    return _buildEditAnswers<T>(
      selection: selection,
      limits: limits,
      entry: entry,
      child: content,
      builder: (context, answers, child) {
        final (:selected, :moves, :edges) = answers;
        return Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            BoardDelayedDragHandle(
              enabled: moves,
              child: Padding(
                padding: const EdgeInsets.all(1.0),
                child: GestureDetector(
                  // Opaque, so the lane takes a press wherever the builder
                  // paints nothing, and the drag handle deferring to it
                  // does too.
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  onLongPress: !moves && edges != CalendarResizeEdges.none
                      ? onSelect
                      : null,
                  child: child,
                ),
              ),
            ),
            if (selected)
              Positioned.fill(
                child: _BarHandles(
                  key: blockHandlesKey(entry.id),
                  id: entry.id,
                  resizesStart: startHandle && edges.hasStart,
                  resizesEnd: endHandle && edges.hasEnd,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A selected bar's outline and day-edge handles, over the bar: each edge
/// that resizes, the left where [resizesStart] and the right where
/// [resizesEnd], has a pill-shaped grip lying across its middle on the
/// outline, and a strip inside the bar, [_BlockHandles.depth] wide and
/// never more than a third of the bar, that starts a resize of that edge
/// at once.
class _BarHandles extends StatelessWidget {
  const _BarHandles({
    super.key,
    required this.id,
    required this.resizesStart,
    required this.resizesEnd,
  });

  /// The bar's entry, which names the grips' keys.
  final String id;

  final bool resizesStart;
  final bool resizesEnd;

  @override
  Widget build(BuildContext context) {
    final styles = _GridStyles.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final columns = math.min(_BlockHandles.depth, width / 3);
        final across = math.min(_BlockHandles.gripLength, height * 0.6);
        // From the bar's edge to a grip's near side, which centres the grip
        // on the outline's middle.
        const lead =
            _BlockHandles.outlineWidth / 2 - _BlockHandles.gripThickness / 2;
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            styles.selectionOutline,
            if (resizesStart)
              Positioned(
                top: 0.0,
                bottom: 0.0,
                left: 0.0,
                width: columns,
                child: const _ResizeHandle(
                  edge: BoardResizeEdges.leading,
                  axis: Axis.horizontal,
                ),
              ),
            if (resizesEnd)
              Positioned(
                top: 0.0,
                bottom: 0.0,
                right: 0.0,
                width: columns,
                child: const _ResizeHandle(
                  edge: BoardResizeEdges.trailing,
                  axis: Axis.horizontal,
                ),
              ),
            if (resizesStart)
              Positioned(
                left: lead,
                top: (height - across) / 2,
                width: _BlockHandles.gripThickness,
                height: across,
                child: _Grip(key: blockGripKey(id, AxisDirection.left)),
              ),
            if (resizesEnd)
              Positioned(
                right: lead,
                top: (height - across) / 2,
                width: _BlockHandles.gripThickness,
                height: across,
                child: _Grip(key: blockGripKey(id, AxisDirection.right)),
              ),
          ],
        );
      },
    );
  }
}

/// A block's or a bar's content: what [builder] last returned for [entry]
/// and [details], called again only once one of the three is not `==` to
/// the last, an inherited widget the builder read through this widget's
/// context notifies, or a hot reload reassembles it. The board rebuilds
/// every block and bar it has built on each pinch move and each write,
/// with the identical entry and an equal details value for one neither
/// changes, so such a rebuild calls no builder.
class _EntryContent<T, D extends Object> extends StatefulWidget {
  const _EntryContent({
    required this.entry,
    required this.details,
    required this.builder,
  });

  final CalendarShownEntry<T> entry;
  final D details;
  final Widget Function(
    BuildContext context,
    CalendarShownEntry<T> entry,
    D details,
  )
  builder;

  @override
  State<_EntryContent<T, D>> createState() {
    return _EntryContentState<T, D>();
  }
}

class _EntryContentState<T, D extends Object>
    extends State<_EntryContent<T, D>> {
  /// What the builder last returned, which the element under this one then
  /// neither updates nor rebuilds; null until the next build calls it.
  Widget? _built;

  @override
  void didUpdateWidget(_EntryContent<T, D> oldWidget) {
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

/// A [_GutterCell] whose lines the foreground labels with [minutes], which
/// a screen reader hears it name in [format].
class _GutterLabel extends StatelessWidget {
  const _GutterLabel({required this.minutes, required this.format});

  final List<int> minutes;
  final HourLabelFormat format;

  @override
  Widget build(BuildContext context) {
    final strings = CalendarLocalizations.of(context);
    return Semantics(
      container: true,
      label: <String>[
        for (final minute in minutes) strings.formatTime(minute, format),
      ].join(", "),
      child: const _GutterCell(),
    );
  }
}

/// The day header's corner over the gutter, on the surface colour: nothing,
/// or a pill counting the shown entries on no day the grid has a column
/// for, which a screen reader hears with
/// [CalendarLocalizations.hiddenEntries] before the count.
class _HiddenCount extends StatelessWidget {
  const _HiddenCount({required this.count});

  final ValueListenable<GridHiddenCounts> count;

  @override
  Widget build(BuildContext context) {
    final styles = _GridStyles.of(context);
    return ColoredBox(
      color: styles.theme.surface,
      child: Center(
        child: ValueListenableBuilder<GridHiddenCounts>(
          valueListenable: count,
          builder: (context, hidden, child) {
            final value = hidden.offDays;
            if (value == 0) {
              return const SizedBox.shrink();
            }
            return Semantics(
              label: CalendarLocalizations.of(context).hiddenEntries(value),
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
/// some, an arrow pointing their way and [CalendarLocalizations.moreCount],
/// or "+N" in a column too narrow for that.
class _NoticeCell extends StatelessWidget {
  const _NoticeCell({
    required this.hidden,
    required this.column,
    required this.above,
    required this.format,
  });

  final ValueListenable<GridHiddenCounts> hidden;

  /// The board column of the cell, which [GridTracks.dateAt] reads.
  final int column;

  final bool above;

  /// The format the cell names the hours in to a screen reader.
  final HourLabelFormat format;

  @override
  Widget build(BuildContext context) {
    final styles = _GridStyles.of(context);
    return ValueListenableBuilder<GridHiddenCounts>(
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
        final strings = CalendarLocalizations.of(context);
        return Semantics(
          container: true,
          label: strings.hiddenRow(
            day,
            count,
            strings.formatTime(above ? hours.start : hours.end, format),
            above: above,
          ),
          excludeSemantics: true,
          child: cell,
        );
      },
    );
  }

  static const double _arrowSize = 16.0;
  static const double _arrowGap = 2.0;

  /// The arrow and [CalendarLocalizations.moreCount], or "+N" in a cell too
  /// narrow for that at its own size, scaled down in one too narrow for
  /// that.
  Widget _buildMore(int count, _GridStyles styles) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final more = CalendarLocalizations.of(context).moreCount(count);
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

/// A day column's cell in a row of the all-day strip: the surface, with a
/// rule between days and one under the strip's last row, [last], tinted and
/// edged in the primary colour while [mark] covers its column. The first
/// row's cell carries [allDayCellKey]. In the collapsed strip's count row,
/// while the day hides bars, a "+N" pill counting them ([allDayMoreKey]),
/// which a screen reader hears as [CalendarLocalizations.allDayMore] and a
/// tap on which reports [onExpand].
class _StripCell extends StatelessWidget {
  const _StripCell({
    required this.strip,
    required this.mark,
    required this.column,
    required this.row,
    required this.last,
    required this.onExpand,
  });

  final ValueListenable<_StripState> strip;
  final ValueListenable<_StripMark?> mark;

  /// The board column of the cell, which [GridTracks.dateAt] reads.
  final int column;

  /// The cell's strip row, from 0.
  final int row;

  final bool last;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final styles = _GridStyles.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[strip, mark]),
      builder: (context, child) {
        final state = strip.value;
        // New tracks reach the strip in the sync that places items on
        // them, so the cell of a column they no longer have rebuilds once
        // before the board's next layout drops it.
        final tracks = state.tracks;
        if (column > tracks.columnCount) {
          return const SizedBox.shrink();
        }
        final day = tracks.dateAt(column);
        final marked = mark.value;
        final decoration =
            marked != null && column >= marked.first && column <= marked.last
            ? styles.stripMarked
            : styles.stripCell(first: column == 1, last: last);
        final count = state.counted && row == collapsedStripRows
            ? state.below[column - 1]
            : 0;
        return DecoratedBox(
          key: row == 0 ? allDayCellKey(day) : null,
          decoration: decoration,
          child: count == 0
              ? const SizedBox.expand()
              : Semantics(
                  container: true,
                  button: true,
                  label: CalendarLocalizations.of(context).allDayMore(count),
                  onTap: onExpand,
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: allDayMoreKey(day),
                    behavior: HitTestBehavior.opaque,
                    onTap: onExpand,
                    child: Center(
                      child: _StripPill(text: "+$count", styles: styles),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// The all-day strip's first row over the gutter: the surface, holding
/// while the strip is expanded past three rows a
/// [CalendarLocalizations.showLess] pill ([allDayLessKey]), which a screen
/// reader hears as [CalendarLocalizations.allDayLess] and a tap on which
/// reports [onCollapse].
class _StripCorner extends StatelessWidget {
  const _StripCorner({required this.strip, required this.onCollapse});

  final ValueListenable<_StripState> strip;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final styles = _GridStyles.of(context);
    return ColoredBox(
      color: styles.theme.surface,
      child: ValueListenableBuilder<_StripState>(
        valueListenable: strip,
        builder: (context, state, child) {
          if (!state.collapsible) {
            return const SizedBox.expand();
          }
          final strings = CalendarLocalizations.of(context);
          return Semantics(
            container: true,
            button: true,
            label: strings.allDayLess,
            onTap: onCollapse,
            excludeSemantics: true,
            child: GestureDetector(
              key: allDayLessKey,
              behavior: HitTestBehavior.opaque,
              onTap: onCollapse,
              child: Center(
                child: _StripPill(text: strings.showLess, styles: styles),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A pill of the all-day strip, in the look of the one counting the
/// entries on no shown day.
class _StripPill extends StatelessWidget {
  const _StripPill({required this.text, required this.styles});

  final String text;
  final _GridStyles styles;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: styles.hiddenPill,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.0),
        child: Text(text, maxLines: 1, style: styles.hiddenLabel),
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

  /// The wall minutes ([wallMinuteOf]) of the create range, or of the range
  /// an end handle dragged into a later day gives, or null.
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
      var row = tracks.firstSlotRow + into ~/ tracks.slotMinutes;
      var fraction = (into % tracks.slotMinutes) / tracks.slotMinutes;
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

  /// [_HourLabels.version] when this painter was made, so labels laid out
  /// anew repaint.
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
    // its top edge by half its height less how far its line lies above
    // that edge, up to [reachAbove], and past its bottom edge likewise. So
    // it shows whole beside a frozen row while its line shows, and sinks
    // into the row's edge as its line scrolls beneath the row.
    void paintOn(int minute, double line) {
      final label = labels.of(minute);
      final own = label.height / 2;
      final above = (own - math.max(0.0, region.top - line)).clamp(
        0.0,
        reachAbove,
      );
      final below = (own - math.max(0.0, line - region.bottom)).clamp(
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
      _paintLabel(canvas, label, first.right, line - own);
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

  /// Paints [label] with its top at [top] and its right edge
  /// [_HourLabels.inset] inside [right].
  void _paintLabel(Canvas canvas, TextPainter label, double right, double top) {
    label.paint(canvas, Offset(right - _HourLabels.inset - label.width, top));
  }

  void _paintNow(Canvas canvas, BoardGeometryView geometry, _NowMark now) {
    final col = now.column;
    if (col < geometry.firstVisibleCol || col > geometry.lastVisibleCol) {
      return;
    }
    final intoHours = now.minute - tracks.hours.start;
    var row = tracks.firstSlotRow + intoHours ~/ tracks.slotMinutes;
    var fraction = (intoHours % tracks.slotMinutes) / tracks.slotMinutes;
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

/// The hour labels a [_GridForegroundPainter] paints and the width of the
/// hour gutter they fit, laid out once for one style, text scale,
/// [HourLabelFormat], [CalendarLocalizations], hours, slot length and
/// least slot height.
///
/// The labels take the first of these that fits them: one line each in a
/// gutter [minGutter] wide, [inset] inside its right edge; up to two lines
/// each in that room, broken only between words, where the closest
/// labelled lines lie the tallest label apart at the least slot height;
/// one line each in a gutter as wide as the widest label and [inset] on
/// each side, up to [maxGutter]; and one line each in a gutter [maxGutter]
/// wide, at a smaller text scale at which the widest fits it.
class _HourLabels {
  /// The space between a label's half and the end of the grid's room for
  /// it.
  static const double gap = 2.0;

  /// The hour gutter's least width.
  static const double minGutter = 56.0;

  /// The hour gutter's greatest width.
  static const double maxGutter = 96.0;

  /// The spaces between a label's words.
  static final RegExp _spaces = RegExp(r"\s+");

  /// The space between a label and the gutter's right edge, and in a
  /// gutter wider than [minGutter], between the widest label and its left
  /// edge.
  static const double inset = 6.0;

  TextStyle _style = const TextStyle();
  TextScaler _scaler = TextScaler.noScaling;
  HourLabelFormat _format = HourLabelFormat.twentyFourHour;
  CalendarLocalizations _strings = const DefaultCalendarLocalizations();
  DayHours? _hours;
  int _slotMinutes = defaultSlotMinutes;
  double _leastSlot = 0.0;

  /// The minutes of the labelled lines, from the top: the first slot's,
  /// each whole hour's after it, and the end of the hours.
  List<int> _minutes = const <int>[];

  /// The text scaler [of] lays the labels out at.
  TextScaler _layoutScaler = TextScaler.noScaling;

  /// The width [of] lays the labels out on up to two lines in, or null
  /// for one line each.
  double? _wrapWidth;

  final Map<int, TextPainter> _labels = <int, TextPainter>{};

  /// The width of the hour gutter the labels fit.
  double gutter = minGutter;

  /// The height of the tallest label.
  double height = 0.0;

  /// Moves on each time [update] lays the labels out anew.
  int version = 0;

  /// Fits the labels anew when [style], [scaler], [format], [strings],
  /// [tracks]' hours or slot length, or [leastSlot], the least height a
  /// slot lays out at, differs from the last.
  void update(
    TextStyle style,
    TextScaler scaler,
    HourLabelFormat format,
    CalendarLocalizations strings,
    GridTracks tracks,
    double leastSlot,
  ) {
    if (style == _style &&
        scaler == _scaler &&
        format == _format &&
        strings == _strings &&
        tracks.hours == _hours &&
        tracks.slotMinutes == _slotMinutes &&
        leastSlot == _leastSlot) {
      return;
    }
    _style = style;
    _scaler = scaler;
    _format = format;
    _strings = strings;
    _hours = tracks.hours;
    _slotMinutes = tracks.slotMinutes;
    _leastSlot = leastSlot;
    _minutes = <int>[
      for (var row = tracks.firstSlotRow; row <= tracks.lastSlotRow; row++)
        if (_GridForegroundPainter.labelsRow(tracks, row)) tracks.minuteAt(row),
      tracks.hours.end,
    ];
    _fit();
    version++;
  }

  /// The label naming [minute], laid out.
  TextPainter of(int minute) {
    return _labels.putIfAbsent(minute, () {
      final wrapWidth = _wrapWidth;
      return TextPainter(
        text: TextSpan(
          text: _strings.formatTime(minute, _format),
          style: _style,
        ),
        textAlign: TextAlign.right,
        textDirection: TextDirection.ltr,
        textScaler: _layoutScaler,
        maxLines: wrapWidth == null ? 1 : 2,
        textWidthBasis: TextWidthBasis.longestLine,
      )..layout(maxWidth: wrapWidth ?? double.infinity);
    });
  }

  /// Lays the labels out the first way that fits them ([_HourLabels]),
  /// and sets [gutter] and [height] from them.
  void _fit() {
    _layOut(_scaler, null);
    gutter = minGutter;
    final widest = _widest();
    const room = minGutter - inset;
    if (widest > room) {
      _layOut(_scaler, room);
      if (!_wrapsWithin(room)) {
        _layOut(_scaler, null);
        if (widest + 2 * inset <= maxGutter) {
          gutter = widest + 2 * inset;
        } else {
          gutter = maxGutter;
          _shrink(maxGutter - 2 * inset, widest);
        }
      }
    }
    height = 0.0;
    for (final minute in _minutes) {
      height = math.max(height, of(minute).height);
    }
  }

  /// Drops the labels laid out, so [of] lays them out at [scaler], on up
  /// to two lines [wrapWidth] wide, or where it is null on one line each.
  void _layOut(TextScaler scaler, double? wrapWidth) {
    _clear();
    _layoutScaler = scaler;
    _wrapWidth = wrapWidth;
  }

  /// The width of the widest label.
  double _widest() {
    var widest = 0.0;
    for (final minute in _minutes) {
      widest = math.max(widest, of(minute).width);
    }
    return widest;
  }

  /// Whether the labels, laid out on up to two lines [room] wide, fit
  /// them, each broken only between words, and the closest labelled lines
  /// lie the tallest apart at the least slot height.
  bool _wrapsWithin(double room) {
    // A word wider than the room is broken inside, so each word between
    // the spaces is measured on its own line.
    final word = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: _layoutScaler,
      maxLines: 1,
    );
    var tallest = 0.0;
    try {
      for (final minute in _minutes) {
        final label = of(minute);
        if (label.didExceedMaxLines) {
          return false;
        }
        final text = _strings.formatTime(minute, _format);
        for (final part in text.split(_spaces)) {
          word
            ..text = TextSpan(text: part, style: _style)
            ..layout();
          if (word.width > room) {
            return false;
          }
        }
        tallest = math.max(tallest, label.height);
      }
    } finally {
      word.dispose();
    }
    var closest = double.infinity;
    for (var i = 1; i < _minutes.length; i++) {
      closest = math.min(closest, (_minutes[i] - _minutes[i - 1]).toDouble());
    }
    return tallest <= closest * _leastSlot / _slotMinutes;
  }

  /// Lays the labels out on one line each at a smaller text scale at which
  /// [widest], their width at the one they are laid out at, fits [room].
  void _shrink(double room, double widest) {
    final fontSize = _style.fontSize ?? kDefaultFontSize;
    var scaler = _scaler;
    // A label's width does not quite follow its font size, so a smaller
    // scaler aims half a pixel inside the room and is measured again,
    // until the widest fits.
    for (var tries = 0; tries < 4 && widest > room; tries++) {
      final size = scaler.scale(fontSize) * (room - 0.5) / widest;
      scaler = TextScaler.linear(math.max(0.0, size) / fontSize);
      _layOut(scaler, null);
      widest = _widest();
    }
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
  /// strip outside its block holds it, and returns the key of that block's
  /// piece, or null where none did.
  GridKey? startOutside(PointerDownEvent event) {
    for (final state in _states) {
      if (state.startOutside(event)) {
        return state.widget.pieceKey;
      }
    }
    return null;
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
    required this.pieceKey,
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

  /// The board key of the block's piece.
  final GridKey pieceKey;

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
