/// The calendar's Month mode: the selected day's month on the board, one
/// row per week and one column per shown weekday, each item a one-lane
/// chip on the days it covers in each calendar week.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../board/board.dart';
import '../../scheduling/scheduling.dart';
import '../presentation/calendar_builders.dart';
import '../presentation/calendar_defaults.dart';
import '../presentation/calendar_localizations.dart';
import '../presentation/calendar_theme.dart';
import 'answer_builder.dart';
import 'create_details.dart';
import 'day_cell.dart';
import 'entry_split.dart';
import 'pinch_zoom.dart';
import 'stale_days_ask.dart';

/// The height of a day's number strip, which the weeks' lanes start
/// below: the row axis's lane padding.
const double monthStripHeight = 28.0;

/// The size of the box holding each day's number, the selected day's on
/// its pill and today's in its ring, at no text scaling; a larger text
/// grows it, keeping the room around the numbers ([numberBoxIn]).
const double _numberBoxWidth = 30.0;
const double _numberBoxHeight = 22.0;

/// The height of one chip lane at no text scaling: the row axis's lane
/// extent while the days show chips. A larger text grows it, keeping the
/// room around a chip's line ([_MonthBoardState._measureLanes]).
const double monthLaneExtent = 18.0;

/// The height of one card lane at no text scaling: the row axis's lane
/// extent while the days show cards ([monthShowsCards]). A larger text
/// grows it, keeping the room around a card's two lines
/// ([_MonthBoardState._measureLanes]).
const double monthCardExtent = 36.0;

/// The text one line of a style is measured with, the space
/// [TextPainter.preferredLineHeight] lays out, whose height is any line's
/// in the style's font.
const List<String> _lineSample = <String>[" "];

/// The room a bar keeps inside its lane on each side, which
/// [_MonthChipBox] insets it by.
const double _barInset = 1.0;

/// The height of a day's banner counting its items wholly before the
/// calendar's hours, under its number strip, and of the one counting those
/// wholly after them, under its last chip.
const double monthHoursBannerExtent = 18.0;

/// The least width of a day that shows its items as cards.
const double monthCardMinWidth = 100.0;

/// The least height a week must rest at for its days to show their items
/// as cards at no text scaling: the number strip and three card lanes.
const double monthCardMinHeight = monthStripHeight + 3 * monthCardExtent;

/// Whether days [width] wide, in weeks resting at [extent], show their
/// items as cards, one [cardExtent] lane tall, which the chip builder
/// draws in its card form, rather than as chips one chip lane tall: when
/// the days reach [monthCardMinWidth] and the weeks the number strip and
/// three card lanes, [monthCardMinHeight] at no text scaling.
bool monthShowsCards(
  double width,
  double extent, {
  double cardExtent = monthCardExtent,
}) {
  return width >= monthCardMinWidth &&
      extent >= monthStripHeight + 3 * cardExtent;
}

/// The height a week of the month board rests at: [height] shared by
/// [weekCount] weeks and times [scale], floored to a multiple of 1/64 so
/// at a [scale] of 1 the weeks never add up past [height], and never less
/// than the strip and one lane [laneExtent] tall. A non-finite [height]
/// gives that least.
double fittedWeekExtent(
  double height,
  int weekCount, {
  double scale = 1.0,
  double laneExtent = monthLaneExtent,
}) {
  assert(scale >= 1.0);
  final least = monthStripHeight + laneExtent;
  if (!height.isFinite || weekCount <= 0) {
    return least;
  }
  final share = (height / weekCount * scale * 64.0).floorToDouble() / 64.0;
  return math.max(share, least);
}

/// The lanes [laneExtent] tall that a week resting at [extent] holds beside
/// the [reserved] height its number strip and its banners outside the
/// hours take: the whole lanes that fit, and at least one.
int monthLanesThatFit(
  double extent, {
  double laneExtent = monthLaneExtent,
  double reserved = monthStripHeight,
}) {
  assert(extent.isFinite);
  final lanes = ((extent - reserved) / laneExtent).floor();
  return math.max(lanes, 1);
}

/// The style the month board animates with under [theme]: every family
/// over its [CalendarThemeData.motionDuration] on its
/// [CalendarThemeData.motionCurve], and every family off at a zero
/// duration. The one site that declares the month board's motion.
BoardAnimationStyle monthBoardAnimationStyleOf(CalendarThemeData theme) {
  return BoardAnimationStyle.uniform(
    BoardAnimationSpec(
      duration: theme.motionDuration,
      curve: theme.motionCurve,
    ),
  );
}

/// What a [MonthBoard] and the days and overlay it builds draw and animate
/// with, made from one [CalendarThemeData] by [forTheme] and never changed.
@immutable
class _MonthStyles {
  _MonthStyles._(this.theme)
    : animation = monthBoardAnimationStyleOf(theme),
      outsidePaint = Paint()..color = theme.background,
      linePaint = Paint()
        ..color = theme.outline
        ..strokeWidth = 1.0,
      number = theme.monthDayNumberStyle.copyWith(color: theme.text),
      mutedNumber = theme.monthDayNumberStyle.copyWith(color: theme.textMuted),
      selectedNumber = theme.monthDayNumberMarkedStyle.copyWith(
        color: theme.onPrimary,
      ),
      todayNumber = theme.monthDayNumberMarkedStyle.copyWith(
        color: theme.primary,
      ),
      selectedPill = BoxDecoration(
        color: theme.primary,
        borderRadius: BorderRadius.circular(_numberBoxHeight / 2.0),
      ),
      ring = BoxDecoration(
        border: Border.all(color: theme.todayRing, width: theme.todayRingWidth),
        borderRadius: BorderRadius.circular(_numberBoxHeight / 2.0),
      ),
      more = BoxDecoration(
        color: theme.notice,
        borderRadius: BorderRadius.circular(4.0),
      ),
      moreLabel = theme.monthMoreStyle.copyWith(color: theme.onNotice),
      createMark = BoxDecoration(
        color: theme.primaryTint,
        border: Border.all(color: theme.primary, width: 2.0),
      ),
      scrim = theme.background.withValues(alpha: 0.85);

  /// The styles of [theme]: those made for it before, or for a theme `==`
  /// to it last, so an equal theme makes none.
  static _MonthStyles forTheme(CalendarThemeData theme) {
    final kept = _memo[theme];
    if (kept != null) {
      return kept;
    }
    final last = _last;
    final styles = last != null && last.theme == theme
        ? last
        : _MonthStyles._(theme);
    _memo[theme] = styles;
    _last = styles;
    return styles;
  }

  /// The styles of the theme above [context], which [context] then depends
  /// on.
  static _MonthStyles of(BuildContext context) {
    return forTheme(CalendarTheme.of(context));
  }

  static Expando<_MonthStyles> _memo = Expando<_MonthStyles>();
  static _MonthStyles? _last;

  /// Drops the styles made so far, which keep the code that made them
  /// across a hot reload, so the next read makes them again.
  static void _reset() {
    _memo = Expando<_MonthStyles>();
    _last = null;
  }

  final CalendarThemeData theme;

  /// [monthBoardAnimationStyleOf] [theme].
  final BoardAnimationStyle animation;

  /// The background's days of another month, and its lines.
  final Paint outsidePaint;
  final Paint linePaint;

  /// A day's number, in the shown month and in another, selected and
  /// today's.
  final TextStyle number;
  final TextStyle mutedNumber;
  final TextStyle selectedNumber;
  final TextStyle todayNumber;
  final BoxDecoration selectedPill;
  final BoxDecoration ring;

  /// [decoration], [selectedPill] or [ring], around a number box of
  /// [box], its ends round.
  static BoxDecoration around(BoxDecoration decoration, Size box) {
    if (box.height == _numberBoxHeight) {
      return decoration;
    }
    return decoration.copyWith(
      borderRadius: BorderRadius.circular(box.height / 2.0),
    );
  }

  /// A day's "+N more".
  final BoxDecoration more;
  final TextStyle moreLabel;

  /// A day whose create is open, drawn as the timed grid draws a strip
  /// cell it marks.
  final BoxDecoration createMark;

  /// The scrim over the board while its days are not ready.
  final Color scrim;
}

/// The key of the item [id]'s bar in the calendar week starting on
/// [weekStart]: `"<id>@<yyyy-mm-dd>"`.
String monthSegmentKey(String id, DateTime weekStart) {
  return "$id@${CalendarDates.isoDate(weekStart)}";
}

/// The key of the chip of the bar [segmentKey] names.
ValueKey<String> monthChipKey(String segmentKey) {
  return ValueKey<String>("month-chip-$segmentKey");
}

/// The key of the month board's cell showing [day].
ValueKey<String> monthDayKey(DateTime day) {
  return ValueKey<String>("month-day-${CalendarDates.isoDate(day)}");
}

/// The key of the number strip of the cell showing [day].
ValueKey<String> monthStripKey(DateTime day) {
  return ValueKey<String>("month-strip-${CalendarDates.isoDate(day)}");
}

/// The key of the banner saying how many chips the cell showing [day]
/// hides.
ValueKey<String> monthMoreKey(DateTime day) {
  return ValueKey<String>("month-more-${CalendarDates.isoDate(day)}");
}

/// The key of the banner counting the items of the cell showing [day]
/// that lie wholly before the calendar's hours.
ValueKey<String> monthEarlierKey(DateTime day) {
  return ValueKey<String>("month-earlier-${CalendarDates.isoDate(day)}");
}

/// The key of the banner counting the items of the cell showing [day]
/// that lie wholly after the calendar's hours.
ValueKey<String> monthLaterKey(DateTime day) {
  return ValueKey<String>("month-later-${CalendarDates.isoDate(day)}");
}

/// One item's bar in one calendar week: the month board's payload.
@immutable
class MonthChip<T> {
  const MonthChip({
    required this.key,
    required this.entry,
    required this.continuesBefore,
    required this.continuesAfter,
  });

  /// [monthSegmentKey] of the item's id and the week's first day.
  final String key;

  final CalendarShownEntry<T> entry;

  /// Whether the item's first day precedes the week's first day, whatever
  /// weekdays show.
  final bool continuesBefore;

  /// Whether the item's last day follows the week's last day, whatever
  /// weekdays show.
  final bool continuesAfter;

  @override
  bool operator ==(Object other) {
    return other is MonthChip<T> &&
        other.key == key &&
        other.entry == entry &&
        other.continuesBefore == continuesBefore &&
        other.continuesAfter == continuesAfter;
  }

  @override
  int get hashCode {
    return Object.hash(key, entry, continuesBefore, continuesAfter);
  }

  @override
  String toString() {
    return "MonthChip($key, $entry)";
  }
}

/// Where each of [shown] sits on the month board of [grid]: one placement
/// per week of the grid whose shown days the entry covers, from the day of
/// its start to the last day it has a part in
/// ([CalendarDates.lastDayNumberOf]), on that week's row and on the columns
/// from the first shown day on or after its first day to the last shown day on
/// or before its last. So an entry covering more than one day, timed or
/// all-day, is a bar across them, and a one-day timed entry a chip. A week
/// whose shown days the entry misses has none, as the timed grid shows no piece
/// on a day it has no column for.
List<BoardPlacement<MonthChip<T>>> monthPlacementsOf<T>(
  Iterable<CalendarShownEntry<T>> shown,
  CalendarMonthGrid grid,
) {
  final weeks = grid.weekCount;
  final columns = grid.columnCount;
  // The dayNumber of each cell, read once per call.
  final days = Int32List(weeks * columns);
  for (var row = 0; row < weeks; row++) {
    for (var col = 0; col < columns; col++) {
      days[row * columns + col] = CalendarDates.dayNumber(
        grid.dateAt(row, col),
      );
    }
  }
  final placements = <BoardPlacement<MonthChip<T>>>[];
  for (final entry in shown) {
    final calendarEntry = entry.entry;
    final first = CalendarDates.dayNumber(calendarEntry.start);
    final last = CalendarDates.lastDayNumberOf(
      calendarEntry.start,
      calendarEntry.end,
    );
    for (var row = 0; row < weeks; row++) {
      final weekFirst = grid.weekdays.weekStartOfDay(days[row * columns]);
      final weekLast = weekFirst + DateTime.daysPerWeek - 1;
      if (last < weekFirst || first > weekLast) {
        continue;
      }
      var from = -1;
      var to = -1;
      for (var col = 0; col < columns; col++) {
        final day = days[row * columns + col];
        if (day >= first && day <= last) {
          if (from < 0) {
            from = col;
          }
          to = col;
        }
      }
      if (from < 0) {
        continue;
      }
      placements.add(
        BoardPlacement<MonthChip<T>>(
          MonthChip<T>(
            key: monthSegmentKey(
              entry.id,
              CalendarDates.dateOfDayNumber(weekFirst),
            ),
            entry: entry,
            continuesBefore: first < weekFirst,
            continuesAfter: last > weekLast,
          ),
          BoardSpan(rowStart: row, colStart: from, colSpan: to - from + 1),
        ),
      );
    }
  }
  return placements;
}

/// Which of [shown] a month board of [grid] shows as chips under [hours],
/// and how many of the others each cell counts, at
/// `row * columnCount + col`. An all-day entry is inside the hours, and so
/// is a timed one any piece of which ([CalendarDates.pieceOn]) on a day of the
/// grid has a minute inside them; every other entry has no chip, and each of
/// its pieces counts on its own day where the grid shows that day, in
/// `earlier` where it ends at or before the hours' start and in `later`
/// otherwise, as Agenda's `dayListRowsOf` counts it. A piece starts no
/// earlier than the minute its day's clock starts at, on [zone]'s clock or
/// the device's where it is null, so on a day whose clock skips its
/// midnight a piece carried from the day before starts where that clock
/// does.
({List<CalendarShownEntry<T>> inside, Int32List earlier, Int32List later})
splitMonthHours<T>(
  Iterable<CalendarShownEntry<T>> shown,
  CalendarMonthGrid grid,
  CalendarDayHours hours, {
  Location? zone,
}) {
  final columns = grid.columnCount;
  final inside = <CalendarShownEntry<T>>[];
  final earlier = Int32List(grid.weekCount * columns);
  final later = Int32List(grid.weekCount * columns);
  // The cell of each day the grid shows, by dayNumber, made once per call.
  final cells = <int, int>{
    for (var row = 0; row < grid.weekCount; row++)
      for (var col = 0; col < columns; col++)
        CalendarDates.dayNumber(grid.dateAt(row, col)): row * columns + col,
  };
  // The minute each shown day's clock starts at, read once per call.
  final dayStarts = <int, int>{
    for (final day in cells.keys)
      day: CalendarDates.minuteOfDay(
        CalendarDates.dateOfDayNumber(day, zone: zone),
      ),
  };
  ({int start, int end})? pieceOn(({int start, int end}) span, int day) {
    final piece = CalendarDates.pieceOn(span, day);
    final start = dayStarts[day] ?? 0;
    if (piece == null || piece.end <= start) {
      return null;
    }
    return (start: math.max(piece.start, start), end: piece.end);
  }

  // A day outside the grid's first and last has no cell, so each entry's
  // days are walked only inside them; a grid of no weekdays has none.
  final days = cells.keys;
  final gridFirst = days.isEmpty ? 0 : days.reduce(math.min);
  final gridLast = days.isEmpty ? -1 : days.reduce(math.max);
  for (final entry in shown) {
    final calendarEntry = entry.entry;
    if (calendarEntry.isAllDay) {
      inside.add(entry);
      continue;
    }
    final span = CalendarDates.wallSpanOf(
      calendarEntry.start,
      calendarEntry.end,
    );
    final first = math.max(
      CalendarDates.dayNumber(calendarEntry.start),
      gridFirst,
    );
    final last = math.min(
      CalendarDates.lastDayNumberOf(calendarEntry.start, calendarEntry.end),
      gridLast,
    );
    var holds = false;
    for (var day = first; day <= last && !holds; day++) {
      final piece = pieceOn(span, day);
      holds =
          cells.containsKey(day) &&
          piece != null &&
          math.min(piece.end, hours.end) > math.max(piece.start, hours.start);
    }
    if (holds) {
      inside.add(entry);
      continue;
    }
    for (var day = first; day <= last; day++) {
      final cell = cells[day];
      final piece = pieceOn(span, day);
      if (cell == null || piece == null) {
        continue;
      }
      (piece.end <= hours.start ? earlier : later)[cell]++;
    }
  }
  return (inside: inside, earlier: earlier, later: later);
}

/// The month board's lane order among bars whose columns in a week are
/// the same: the entry that starts on an earlier day first, then the one
/// covering more days, then an all-day entry before a timed one, then the
/// earlier start, the title and the id. The board orders bars by their
/// first and their last column before it, so a week's chips stack by the
/// day each starts in the week, the longer first, and a bar continuing
/// from the week before stacks above a chip starting on its first shown
/// day.
int compareMonthChips<T>(MonthChip<T> a, MonthChip<T> b) {
  final x = a.entry.entry;
  final y = b.entry.entry;
  final xFirst = CalendarDates.dayNumber(x.start);
  final yFirst = CalendarDates.dayNumber(y.start);
  final byDay = xFirst.compareTo(yFirst);
  if (byDay != 0) {
    return byDay;
  }
  final xDays = CalendarDates.lastDayNumberOf(x.start, x.end) - xFirst;
  final yDays = CalendarDates.lastDayNumberOf(y.start, y.end) - yFirst;
  final byLength = yDays.compareTo(xDays);
  if (byLength != 0) {
    return byLength;
  }
  if (x.isAllDay != y.isAllDay) {
    return x.isAllDay ? -1 : 1;
  }
  final byStart = x.start.compareTo(y.start);
  if (byStart != 0) {
    return byStart;
  }
  final byTitle = x.title.compareTo(y.title);
  if (byTitle != 0) {
    return byTitle;
  }
  return a.entry.id.compareTo(b.entry.id);
}

/// What a month board of [grid] shows of [placements] when each week holds
/// at most [lanes] lanes: the placements it keeps, in their order, and how
/// many chips each cell hides, at `row * columnCount + col`.
///
/// The lanes are the board's own: in each week, the chips ordered by their
/// first column, then by their last, later first, then by
/// [compareMonthChips], each in the lowest lane that no earlier chip holds
/// on its first column. A week whose chips need no more than [lanes] lanes
/// keeps them all. In any other, a day under a chip past the last lane
/// hides that chip and the chip in its last lane, which leaves the last
/// lane free there to say how many chips the day hides, and a chip hidden
/// on one of its days hides on all of them. A kept chip keeps its lane on
/// the board, since the chips that push it there hold the lanes below the
/// last, and those always show.
({List<BoardPlacement<MonthChip<T>>> shown, Int32List hidden})
fitMonthPlacements<T>(
  List<BoardPlacement<MonthChip<T>>> placements,
  CalendarMonthGrid grid,
  int lanes,
) {
  assert(lanes >= 1);
  final columns = grid.columnCount;
  final hidden = Int32List(grid.weekCount * columns);
  final laned = _laneMonthPlacements(placements, grid);
  final weeks = laned.weeks;
  final laneOfChip = laned.lanes;
  final hides = List<bool>.filled(placements.length, false);
  var hidesAny = false;
  for (var row = 0; row < weeks.length; row++) {
    final week = weeks[row];
    if (laned.weekLanes[row] <= lanes) {
      continue;
    }
    final overflowing = List<bool>.filled(columns, false);
    for (final i in week) {
      if (laneOfChip[i] >= lanes) {
        final span = placements[i].span;
        for (
          var col = span.colStart;
          col < span.colStart + span.colSpan;
          col++
        ) {
          overflowing[col] = true;
        }
      }
    }
    for (final i in week) {
      final span = placements[i].span;
      final end = span.colStart + span.colSpan;
      var hide = laneOfChip[i] >= lanes;
      if (!hide && laneOfChip[i] == lanes - 1) {
        for (var col = span.colStart; col < end && !hide; col++) {
          hide = overflowing[col];
        }
      }
      if (!hide) {
        continue;
      }
      hides[i] = true;
      hidesAny = true;
      for (var col = span.colStart; col < end; col++) {
        hidden[row * columns + col]++;
      }
    }
  }
  if (!hidesAny) {
    return (shown: placements, hidden: hidden);
  }
  return (
    shown: <BoardPlacement<MonthChip<T>>>[
      for (var i = 0; i < placements.length; i++)
        if (!hides[i]) placements[i],
    ],
    hidden: hidden,
  );
}

/// The board's lanes for [placements] on a month board of [grid], as
/// [fitMonthPlacements] gives them: each week's placement indices in lane
/// order, the lane of each placement, and how many lanes each week's
/// placements take.
({List<List<int>> weeks, Int32List lanes, Int32List weekLanes})
_laneMonthPlacements<T>(
  List<BoardPlacement<MonthChip<T>>> placements,
  CalendarMonthGrid grid,
) {
  final weeks = <List<int>>[
    for (var row = 0; row < grid.weekCount; row++) <int>[],
  ];
  for (var i = 0; i < placements.length; i++) {
    weeks[placements[i].span.rowStart].add(i);
  }
  final laneOfChip = Int32List(placements.length);
  final weekLanes = Int32List(grid.weekCount);
  for (var row = 0; row < weeks.length; row++) {
    final week = weeks[row];
    week.sort((a, b) {
      final x = placements[a].span;
      final y = placements[b].span;
      final byFirst = x.colStart.compareTo(y.colStart);
      if (byFirst != 0) {
        return byFirst;
      }
      final byLast = (y.colStart + y.colSpan).compareTo(x.colStart + x.colSpan);
      if (byLast != 0) {
        return byLast;
      }
      return compareMonthChips(placements[a].item, placements[b].item);
    });
    // The column after the last chip in each lane so far.
    final laneEnds = <int>[];
    for (final i in week) {
      final span = placements[i].span;
      var lane = 0;
      while (lane < laneEnds.length && laneEnds[lane] > span.colStart) {
        lane++;
      }
      if (lane == laneEnds.length) {
        laneEnds.add(0);
      }
      laneEnds[lane] = span.colStart + span.colSpan;
      laneOfChip[i] = lane;
    }
    weekLanes[row] = laneEnds.length;
  }
  return (weeks: weeks, lanes: laneOfChip, weekLanes: weekLanes);
}

/// How many lanes each day of [grid] takes on the board when it holds
/// [placements], at `row * columnCount + col`: one past the lane of its
/// deepest chip, and 0 for a day no chip covers.
Int32List monthDayLanesOf<T>(
  List<BoardPlacement<MonthChip<T>>> placements,
  CalendarMonthGrid grid,
) {
  final columns = grid.columnCount;
  final days = Int32List(grid.weekCount * columns);
  final lanes = _laneMonthPlacements(placements, grid).lanes;
  for (var i = 0; i < placements.length; i++) {
    final span = placements[i].span;
    final first = span.rowStart * columns + span.colStart;
    for (var cell = first; cell < first + span.colSpan; cell++) {
      days[cell] = math.max(days[cell], lanes[i] + 1);
    }
  }
  return days;
}

/// How Month lays out a week whose chips need more lanes than its share
/// of the board's height holds.
enum CalendarMonthLayout {
  /// The week grows to hold every chip, and the month scrolls.
  showAll,

  /// Every week keeps its share of the board's height, so the month fits
  /// on the screen; a day shows the chips that fit and how many it hides.
  fitScreen,
}

/// The month of [grid] on the board, under the letters of its weekdays,
/// showing what [store] shows for its days.
///
/// The days share the board's width, and are never narrower than
/// [minDayWidth]: past the width, the board scrolls across, the letters
/// with it. The weeks share the board's height above [bottomPadding],
/// which stays empty, each resting at [weekScale] times its share: past 1,
/// the board scrolls down, its last week ending above the padding. The board
/// opens scrolled to show the selected day, and does again for a new
/// month, a new [minDayWidth] and a new [weekScale]. A new [selectedDay]
/// of the same month scrolls the least that shows its day whole, after the
/// frame that selects it, and again once the days are ready where they are
/// not: a board that shows the day whole does not move, and none moves
/// while two fingers hold the board or a drag or its fling scrolls it.
///
/// Under [CalendarMonthLayout.showAll] the weeks grow past their resting
/// height to hold their chips, and the board then scrolls; under
/// [CalendarMonthLayout.fitScreen] each holds the lanes that fit at its
/// resting height ([monthLanesThatFit]), [fitMonthPlacements] chooses the
/// chips it shows, and a day that hides some says "+N more" on a soft
/// yellow banner in its last lane. An item with no minute inside [hours] has no
/// chip ([splitMonthHours]): each day it covers counts it on a soft yellow
/// banner, "+N earlier" under the day's number strip for those before the hours
/// and "+N later" for those after them in the lane under the day's last chip,
/// or under its "+N more", naming the hours in [hourLabelFormat] to a screen
/// reader. While any day of the grid counts one before the hours, every week's
/// lanes start under that banner's band; a week grows to hold each day's banner
/// after the hours, and while any day counts one, under
/// [CalendarMonthLayout.fitScreen] a week holds the lanes that fit beside both
/// bands. Each day shows its number in a strip across its top, today's in the
/// primary colour inside the today ring and the selected day's on the primary
/// pill, in the [CalendarTheme] above the board. Each item shows as one bar per
/// calendar week it covers, whose content is what [chipBuilder] draws, told
/// whether the item continues into the week before or after: a chip one lane
/// tall, or, in days large enough ([monthShowsCards]), a card one card lane
/// tall, the builder told it draws a card. A chip lane is 18 px and a card
/// lane 36, or where the theme's lines need more at the text scale, a line
/// of its [CalendarThemeData.chipTitleStyle] or
/// [CalendarThemeData.monthMoreStyle] in a chip lane and one of its
/// [CalendarThemeData.monthCardTitleStyle] over one of its
/// [CalendarThemeData.monthCardTimeStyle] in a card lane, as much taller as
/// holds them whole with the room the lane leaves around them at no
/// scaling, so a week at its resting height holds fewer lanes at a larger
/// text. A pending item's bar takes no tap, and the board names each bar to
/// a screen reader, its kind as [entryKindOf] answers it. Lines part the
/// weeks and the days, and each day of another month lies on the background
/// colour.
///
/// A tap on a chip reports [onOpenEntry], a tap anywhere else on a day
/// [onOpenDay], and a long press on a day outside its chips
/// [onCreateOnDay], or where there is none [onOpenDay] as a tap does; the
/// last two give the board the keyboard. Its arrow keys report through
/// [onSelectDay] the shown day before or after the selected one on the
/// screen, or the day a week before or after it, in whatever month that
/// day lies: a day the grid shows is selected on the board and scrolled
/// into view at once, and a day of another month once the owner shows its
/// month. Home, End and the page keys move the board's selection within
/// [grid] and report its day. The
/// board loads [grid]'s days: it asks [store] for them after the frame
/// that brings it its grid, a new store or a new zone of the store
/// ([CalendarEntryReader.prefetch]), unless their read failed, and they
/// are ready while the store answers them ready
/// ([CalendarEntryReader.statusOf]). After the frame that the store
/// reports stale days of them ([CalendarEntryReader.addStaleDaysListener]),
/// it reads again each run of them the store answers
/// [CalendarEntryReader.isStale] for. While they are not ready a cover over
/// the board takes every press, centring what [loadingBuilder] draws while
/// they are read, and what [failureBuilder] draws when their read failed,
/// with the store's error for them ([CalendarEntryReader.loadErrorOf]) and
/// a retry of them ([CalendarEntryReader.retry]). A change of the
/// store animates over the theme's motion; a new month or a new set of
/// weekdays does not, and
/// settles at once whatever chip was still growing in or shrinking out. A
/// new size alone refits the weeks at once and leaves the chips' motion
/// running, unless it turns chips into cards or back, or under
/// [CalendarMonthLayout.fitScreen] changes the lanes a week holds, which
/// settles them as a new month does. New [hours] settle the chips as a new
/// month does.
///
/// A pinch of two fingers zooms the board around the point between them,
/// reporting through [onZoom] the week scale and the least day width it
/// zooms to, from the scale and the width the board shows: a pinch up and
/// down the week scale, from 1 to [maxMonthWeekScale], and one across the
/// day width, from [minDayWidthLow] to [minDayWidthHigh]. A new scale or
/// width a pinch brings does not scroll to the selected day. While two
/// fingers are down the board does not scroll, and a tap or a long press
/// of fingers that pinched does nothing.
///
/// A bar's content, the loading and the failure state are what their
/// builders draw, the module's defaults where they are null.
class MonthBoard<T> extends StatefulWidget {
  const MonthBoard({
    super.key,
    required this.store,
    required this.grid,
    this.layout = CalendarMonthLayout.showAll,
    this.minDayWidth = minDayWidthLow,
    this.weekScale = 1.0,
    this.hours = CalendarDayHours.allDay,
    this.hourLabelFormat = CalendarHourLabelFormat.twentyFourHour,
    required this.selectedDay,
    required this.now,
    required this.onSelectDay,
    required this.onOpenDay,
    required this.onCreateOnDay,
    required this.onOpenEntry,
    this.onZoom,
    this.chipBuilder,
    this.loadingBuilder,
    this.failureBuilder,
    this.entryKindOf,
    this.bottomPadding = 0.0,
  }) : assert(
         bottomPadding >= 0.0 && bottomPadding < double.infinity,
         "A MonthBoard's bottomPadding must be non-negative and finite.",
       );

  final CalendarStore<T> store;

  /// The month the board shows.
  final CalendarMonthGrid grid;

  /// Whether a week grows to hold its chips or keeps its share of the
  /// height and hides the chips that do not fit.
  final CalendarMonthLayout layout;

  /// The least width of a day, in logical pixels.
  final double minDayWidth;

  /// How many times its share of the board's height a week rests at, at
  /// least 1.
  final double weekScale;

  /// The hours the calendar shows: an item with no minute inside them has
  /// no chip, and its days count it on their banners.
  final CalendarDayHours hours;

  /// The format the days' banners name [hours] in to a screen reader, and
  /// the chips write their entries' times in: to a screen reader, and
  /// through [chipBuilder] ([CalendarChipDetails.hourLabelFormat]).
  final CalendarHourLabelFormat hourLabelFormat;

  /// A shown day of [grid]'s month.
  final DateTime selectedDay;

  /// The current time and the day marked as today, which its owner sets
  /// again at the start of each minute and where today changes. The
  /// board marks [CalendarNow.today]; a new minute of the same today
  /// builds no cell.
  final ValueListenable<CalendarNow> now;

  /// A key moved the selection onto this day, which an arrow key can find
  /// in the month before or after [grid]'s: the owner then shows that
  /// day's month, as [selectedDay] is a day of [grid]'s month.
  final ValueChanged<DateTime> onSelectDay;

  /// This day was tapped outside its chips.
  final ValueChanged<DateTime> onOpenDay;

  /// This day was long-pressed outside its chips, its cell lying at the
  /// rect, in global logical pixels, the function is given: it returns the
  /// start of the range it reports and the future of that create, or null
  /// where it reports none, as where the create is refused. The board
  /// marks the day while that future runs, until it completes or fails,
  /// unless a later long press's create has moved the mark to its own day;
  /// a new zone of the store moves the mark to the day holding the start
  /// on the new clock. A failure is left uncaught in the zone the long
  /// press ran in. Null where a long press creates nothing, as out of edit
  /// mode, and opens the day as a tap does.
  final ({DateTime start, Future<void> done})? Function(
    DateTime day,
    Rect globalRect,
  )?
  onCreateOnDay;

  /// The chip of this item, which is not pending, was tapped.
  final ValueChanged<String> onOpenEntry;

  /// Reports the week scale and the least day width a pinch zooms to,
  /// which the board shows once [weekScale] and [minDayWidth] bring them;
  /// null for a board no pinch zooms.
  final void Function(double weekScale, double minDayWidth)? onZoom;

  /// Draws each bar's content inside the lane the board gives it, in its
  /// chip or card form; null for [defaultCalendarChipBuilder]. A new one,
  /// not `==` to the last, draws every bar again.
  final CalendarChipBuilder<T>? chipBuilder;

  /// Draws the cover's content while the board's days are read; null for
  /// [defaultCalendarLoadingBuilder].
  final CalendarLoadingBuilder? loadingBuilder;

  /// Draws the cover's content when the read of the board's days failed;
  /// null for [defaultCalendarFailureBuilder].
  final CalendarFailureBuilder? failureBuilder;

  /// The word that names [CalendarEntry]'s kind in the label a screen
  /// reader hears for its bar, after its title; null, or a null answer,
  /// leaves the kind out. A new one, not `==` to the last, names every bar
  /// again.
  final String? Function(CalendarEntry<T> entry)? entryKindOf;

  /// The room under the board, in logical pixels, which it leaves empty:
  /// the weeks share the height above it, and a board that scrolls down
  /// ends its last week there.
  final double bottomPadding;

  @override
  State<MonthBoard<T>> createState() {
    return _MonthBoardState<T>();
  }
}

/// A chip the item builder built, and the payload it built it for.
typedef _KeptChip<T> = ({MonthChip<T> chip, Widget widget});

/// A day cell the cell builder built, and the day and selection it built
/// it for.
typedef _KeptDay = ({DateTime day, bool selected, Widget widget});

/// What a day shows besides its chips: how many chips it hides, the lane
/// its "+N more" takes, the height of a lane and the room above the lanes;
/// how many of its items lie wholly before the hours and after them, and
/// the lane its banner after the hours takes; and the least height the day
/// measures, which holds that banner.
typedef _Hidden = ({
  int count,
  int lane,
  double laneExtent,
  double lanePadding,
  int earlier,
  int later,
  int laterLane,
  double extent,
});

const _Hidden _noneHidden = (
  count: 0,
  lane: 0,
  laneExtent: monthLaneExtent,
  lanePadding: monthStripHeight,
  earlier: 0,
  later: 0,
  laterLane: 0,
  extent: monthStripHeight,
);

/// The hours the days' banners name to a screen reader, and their format.
typedef _BannerHours = ({
  CalendarDayHours hours,
  CalendarHourLabelFormat format,
});

/// A split of the entries the store shows on a month's days: the entries
/// it [read], for [grid] and [hours]; those [inside] the hours, and on each
/// day the counts wholly before them, [earlier], and after them, [later]
/// ([splitMonthHours]); and the bars of those inside ([monthPlacementsOf]).
typedef _MonthSplit<T> = ({
  List<CalendarShownEntry<T>> read,
  CalendarMonthGrid grid,
  CalendarDayHours hours,
  List<CalendarShownEntry<T>> inside,
  Int32List earlier,
  Int32List later,
  List<BoardPlacement<MonthChip<T>>> placements,
});

class _MonthBoardState<T> extends State<MonthBoard<T>>
    with TickerProviderStateMixin {
  /// The columns' width before the first layout, which replaces it.
  static const double _placeholderColumnWidth = 48.0;

  /// What the cell builder answers for a cell outside [MonthBoard.grid].
  static const Widget _outsideGrid = SizedBox.shrink();

  /// The most cells a month grid has: six weeks of seven days.
  static const int _mostCells = 6 * DateTime.daysPerWeek;

  late final BoardController<String, MonthChip<T>> _board;

  /// The vertical scroll, which [_revealSelected] reads.
  final ScrollController _scroll = ScrollController();

  /// The horizontal scroll, which the weekday letters follow.
  final ScrollController _horizontal = ScrollController();

  late final PinchTracker _pinch = PinchTracker(
    onStart: _startPinch,
    onUpdate: _pinchTo,
    onEnd: _endPinch,
  );

  final ScrollHolder _scrollHold = ScrollHolder();

  /// The week scale and the day width the board showed when the running
  /// pinch started; null while none runs.
  ({double weekScale, double day})? _pinchFrom;

  /// Where the fingers of the pinch that last reported a zoom met, in the
  /// board's coordinates, until the next layout holds the lattice there
  /// ([_holdPinchFocal]).
  Offset? _pinchFocal;

  /// The area the board fills, whose coordinates are the board's.
  final GlobalKey _boardAreaKey = GlobalKey();

  /// The board's focus, which a tap or a long press on a day asks for, so
  /// the arrow keys reach the board.
  final FocusNode _focusNode = FocusNode(debugLabel: "MonthBoard");

  /// Held in fields because `Board` replaces its delegate, and so rebuilds
  /// every cell and chip, whenever a builder it gets is not identical to
  /// the previous one; the selection config likewise. The board gets the
  /// card builder while [_cards] holds, so a turn from chips to cards or
  /// back rebuilds every bar. [didUpdateWidget] gives the board new bar
  /// builders, and drops the kept bars, for a new
  /// [MonthBoard.chipBuilder] or [MonthBoard.entryKindOf].
  late final BoardCellBuilder<String, MonthChip<T>> _cellBuilder = _buildDay;
  late BoardItemBuilder<String, MonthChip<T>> _chipBuilder = _buildChip;
  late BoardItemBuilder<String, MonthChip<T>> _cardBuilder = _buildCard;

  /// [MonthBoard.chipBuilder], or the module's default where it is null.
  late CalendarChipBuilder<T> _barBuilder = _barBuilderOf(widget);

  static CalendarChipBuilder<T> _barBuilderOf<T>(MonthBoard<T> widget) {
    return widget.chipBuilder ?? defaultCalendarChipBuilder<T>;
  }

  late final BoardSelectionConfig _selectionConfig = BoardSelectionConfig(
    mode: BoardSelectionMode.cell,
    onChanged: _handleBoardSelection,
  );

  /// The store's zone as the board last took it ([_takeZone]); null for
  /// the device's.
  Location? _zone;

  /// The plain twin ([_plainTwinOf]) of the today of [MonthBoard.now],
  /// which the kept day cells, the plain days of the grid, listen to and
  /// compare with by `==`, so a new listenable reaches the cells this state
  /// keeps and a new minute of the same today notifies none, while another
  /// date always does, however the todays given are zoned.
  late final ValueNotifier<DateTime> _today = ValueNotifier<DateTime>(
    _plainTwinOf(widget.now.value.today),
  );

  /// The local midnight of [day]'s date, which the grid's plain days
  /// compare with by `==`.
  static DateTime _plainTwinOf(DateTime day) {
    return CalendarDates.dateOfDayNumber(CalendarDates.dayNumber(day));
  }

  /// Whether [MonthBoard.onCreateOnDay] is given, which the kept day cells
  /// listen to, so a long press on them creates only while it is.
  late final ValueNotifier<bool> _creates = ValueNotifier<bool>(
    widget.onCreateOnDay != null,
  );

  /// The day whose long press reported the latest create, while that
  /// create's future runs, which the kept day cells listen to and mark: a
  /// plain day of the grid.
  final ValueNotifier<DateTime?> _createMark = ValueNotifier<DateTime?>(null);

  /// The start of the range the create [_createMark] marks reported, so a
  /// new zone ([_takeZone]) marks the day holding it on the new clock; null
  /// while [_createMark] is.
  DateTime? _createAt;

  /// Counts the creates the long presses reported, so only the latest
  /// one's completion clears [_createMark].
  int _createCount = 0;

  /// [MonthBoard.hours] and [MonthBoard.hourLabelFormat], which the kept
  /// day cells listen to for their banners' labels.
  late final ValueNotifier<_BannerHours> _bannerHours =
      ValueNotifier<_BannerHours>(_bannerHoursOf(widget));

  static _BannerHours _bannerHoursOf<T>(MonthBoard<T> widget) {
    return (hours: widget.hours, format: widget.hourLabelFormat);
  }

  /// What each cell of [MonthBoard.grid] hides, at
  /// `row * columnCount + col`, which the kept day cells listen to, since
  /// the cell builder re-runs only when an axis or a cell's selection
  /// changes. Every sync writes them.
  final List<ValueNotifier<_Hidden>> _hidden = <ValueNotifier<_Hidden>>[
    for (var i = 0; i < _mostCells; i++) ValueNotifier<_Hidden>(_noneHidden),
  ];

  /// The grid, the layout, the hours, the week extent, the room above the
  /// lanes, the lane extent and the column width the axes were last given;
  /// null and zero before the first layout.
  CalendarMonthGrid? _fittedGrid;
  CalendarMonthLayout? _fittedLayout;
  CalendarDayHours? _fittedHours;
  double _fitted = 0.0;
  double _fittedPadding = 0.0;
  double _fittedLaneExtent = 0.0;
  double _columnWidth = 0.0;

  /// The heights of a chip lane and of a card lane as the last build
  /// measured them ([_measureLanes]), which the next layout gives the axes
  /// and the bars.
  double _chipLane = monthLaneExtent;
  double _cardLane = monthCardExtent;

  /// Whether the last sync found a day of the grid counting an item before
  /// the hours, and one counting an item after them, which decide the
  /// bands above and below the lanes.
  bool _earlierBand = false;
  bool _laterBand = false;

  /// Whether the axes were last given card lanes ([monthShowsCards]), and
  /// the bars are cards.
  bool _cards = false;

  /// The lanes a week held at the last sync, under
  /// [CalendarMonthLayout.fitScreen]; null under [CalendarMonthLayout.showAll],
  /// where the weeks grow.
  int? _syncedLanes;

  /// Whether the next layout sets the board's items: set at the start, by
  /// the store and by a new grid.
  bool _syncPending = true;

  /// Whether the last sync found its days ready.
  bool _syncedReady = false;

  /// What the store answers for the status of [MonthBoard.grid]'s days
  /// and, where it is failed, their error, as [_noteLoad] last found them,
  /// which [_daysReady] and the cover read, so a layout reads fields
  /// rather than the store.
  CalendarLoadStatus _loadStatus = CalendarLoadStatus.loading;
  Object? _loadError;

  /// Whether an ask for the grid's days waits for the end of the frame
  /// ([_scheduleAsk]).
  bool _askPending = false;

  /// The store's zone at the last ask ([_askDays]), which the ask alone
  /// writes, so a zone the board took earlier, at its clock's notify
  /// ([_handleNow]), still asks.
  Location? _askedZone;

  /// Reads again, after the frame, the days of [MonthBoard.grid] the store
  /// reports stale ([StaleDaysAsk]).
  late final StaleDaysAsk<T> _staleAsk;

  /// Whether a layout still owes a reveal of the selected day: set at the
  /// start, by a new grid, by a new [MonthBoard.minDayWidth] or
  /// [MonthBoard.weekScale], and by a new selected day while the days are
  /// not ready ([_revealNewSelection]), cleared by the first layout after it
  /// that finds the days ready.
  bool _revealPending = true;

  /// Whether a frame will put the styles' animation back.
  bool _restoreScheduled = false;

  /// What the board's background and builders draw with and the board
  /// animates with; set by [_applyTheme].
  _MonthStyles? _themed;

  _MonthStyles get _styles {
    return _themed!;
  }

  /// True only while this state writes the board's selection itself, so
  /// the write reports nothing to [MonthBoard.onSelectDay].
  bool _writingSelection = false;

  /// The day the last move of the selection reported, by an arrow key of
  /// this state's or a key or tap of the board's, until the frame after it:
  /// an arrow steps from it, so keys before a frame each step from the one
  /// before whichever of the two took it.
  DateTime? _movedDay;

  /// The bars the item builders returned, by chip key, kept so a payload
  /// that did not change returns the same instance and builds nothing.
  /// Holds no key but those the latest sync placed and those in [_dropped],
  /// and no bar but those of the kind [_cards] names.
  final Map<String, _KeptChip<T>> _chips = <String, _KeptChip<T>>{};

  /// The day cells the cell builder returned, one entry per cell of the
  /// grid at `row * columnCount + col`, refilled with nulls for each new
  /// grid.
  late List<_KeptDay?> _days = _emptyDays(widget.grid);

  /// The board's background for [MonthBoard.grid], made once per grid and
  /// styles, so a build that keeps both hands the board the same painter.
  late _MonthGridPainter _background;

  /// The last split of the entries the store shows on the grid's days
  /// ([_splitOf]), with the bars [monthPlacementsOf] made of it, the entry
  /// list it read, and the grid and hours it split for; null before the
  /// first layout. A new grid, new hours and the store's notify set
  /// [_syncPending], so while none is pending it is the split of what the
  /// board shows, which a change of the lanes or of the cards fits again.
  _MonthSplit<T>? _split;

  /// The latest sync's placements, by chip key.
  Map<String, BoardPlacement<MonthChip<T>>> _placed =
      <String, BoardPlacement<MonthChip<T>>>{};

  /// Over the animated syncs since the last sync that did not animate: the
  /// placements they stopped placing, by chip key, and the chip keys they
  /// started placing. Every exit and enter in flight is among them, since
  /// only an animated sync starts one; the controller's key reads cannot
  /// tell an exiting key from a retired one.
  final Map<String, BoardPlacement<MonthChip<T>>> _dropped =
      <String, BoardPlacement<MonthChip<T>>>{};
  final Set<String> _added = <String>{};

  @override
  void initState() {
    super.initState();
    _zone = widget.store.zone;
    final grid = widget.grid;
    _board = BoardController<String, MonthChip<T>>(
      vsync: this,
      // Both replaced by the first layout, which knows the size.
      rows: _rowsConfig(
        grid,
        fittedWeekExtent(double.infinity, 1),
        monthLaneExtent,
        monthStripHeight,
      ),
      columns: BoardAxisConfig(
        axis: UniformAxis(grid.columnCount, _placeholderColumnWidth),
      ),
      keyOf: (chip) {
        return chip.key;
      },
      // Until the first didChangeDependencies assigns the theme's.
      animationStyle: BoardAnimationStyle.disabled,
      laneOrder: compareMonthChips<T>,
    );
    // Before the board subscribes, so it starts on the selected day and a
    // key moves from there.
    _writeSelection();
    widget.store.addListener(_handleStore);
    widget.now.addListener(_handleNow);
    _pinch.holding.addListener(_handleHolding);
    _staleAsk = StaleDaysAsk<T>(_gridDays)..listen(widget.store);
    _noteLoad();
    _scheduleAsk();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyTheme();
  }

  @override
  void reassemble() {
    _MonthStyles._reset();
    super.reassemble();
    _applyTheme();
  }

  /// Reads the styles of the theme above the board; on new ones, makes the
  /// background again and gives the board their animation, unless a frame
  /// will put it back after a sync that disabled it.
  void _applyTheme() {
    final styles = _MonthStyles.of(context);
    if (identical(styles, _themed)) {
      return;
    }
    _themed = styles;
    _background = _MonthGridPainter(widget.grid, styles);
    if (!_restoreScheduled) {
      _board.animationStyle = styles.animation;
    }
  }

  @override
  void didUpdateWidget(MonthBoard<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chipBuilder != oldWidget.chipBuilder ||
        widget.entryKindOf != oldWidget.entryKindOf ||
        widget.hourLabelFormat != oldWidget.hourLabelFormat) {
      _barBuilder = _barBuilderOf(widget);
      _chips.clear();
      _chipBuilder = (context, view) {
        return _buildChip(context, view);
      };
      _cardBuilder = (context, view) {
        return _buildCard(context, view);
      };
    }
    if (widget.store != oldWidget.store) {
      oldWidget.store.removeListener(_handleStore);
      widget.store.addListener(_handleStore);
      _syncPending = true;
    }
    _staleAsk.listen(widget.store);
    if (widget.store.zone != _zone) {
      _takeZone();
    }
    if (widget.now != oldWidget.now) {
      oldWidget.now.removeListener(_handleNow);
      widget.now.addListener(_handleNow);
      _today.value = _plainTwinOf(widget.now.value.today);
    }
    _creates.value = widget.onCreateOnDay != null;
    _bannerHours.value = _bannerHoursOf(widget);
    if (widget.hours != oldWidget.hours) {
      _syncPending = true;
    }
    final gridChanged = !_sameGrid(widget.grid, oldWidget.grid);
    if (gridChanged) {
      _syncPending = true;
      _revealPending = true;
      _days = _emptyDays(widget.grid);
      _background = _MonthGridPainter(widget.grid, _styles);
    }
    if (gridChanged || widget.store != oldWidget.store) {
      _noteLoad();
    }
    if (gridChanged ||
        widget.store != oldWidget.store ||
        widget.store.zone != _askedZone) {
      _scheduleAsk();
    }
    if ((widget.minDayWidth != oldWidget.minDayWidth ||
            widget.weekScale != oldWidget.weekScale) &&
        _pinchFocal == null) {
      // Larger days may push the selected one out of view. A pinch keeps
      // the point between its fingers in view instead.
      _revealPending = true;
    }
    if (gridChanged || widget.selectedDay != oldWidget.selectedDay) {
      // Reaches the cells through the board's post-frame relay, since this
      // runs in the build.
      _writeSelection();
    }
    // A new grid owes its reveal already.
    if (!gridChanged &&
        CalendarDates.dayNumber(widget.selectedDay) !=
            CalendarDates.dayNumber(oldWidget.selectedDay)) {
      _revealNewSelection();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStore);
    _staleAsk.dispose();
    widget.now.removeListener(_handleNow);
    _pinch.dispose();
    _scrollHold.release();
    // The board has unmounted by now: an element's children unmount
    // before its state disposes.
    _scroll.dispose();
    _horizontal.dispose();
    _focusNode.dispose();
    _board.dispose();
    _today.dispose();
    _creates.dispose();
    _createMark.dispose();
    _bannerHours.dispose();
    for (final hidden in _hidden) {
      hidden.dispose();
    }
    super.dispose();
  }

  static List<_KeptDay?> _emptyDays(CalendarMonthGrid grid) {
    return List<_KeptDay?>.filled(grid.weekCount * grid.columnCount, null);
  }

  static bool _sameGrid(CalendarMonthGrid a, CalendarMonthGrid b) {
    return a.year == b.year && a.month == b.month && a.weekdays == b.weekdays;
  }

  /// [weekCount] weeks resting at [fitted], each growing past it to the
  /// [padding] above its lanes plus its lanes, each [laneExtent] tall.
  static BoardAxisConfig _rowsConfig(
    CalendarMonthGrid grid,
    double fitted,
    double laneExtent,
    double padding,
  ) {
    return BoardAxisConfig(
      axis: LazyContentAxis(grid.weekCount, fitted, minTrackExtent: fitted),
      laneExtent: laneExtent,
      lanePadding: padding,
    );
  }

  /// Follows the store, taking a new zone first ([_takeZone]): the layout
  /// it asks for lays the refiled entries out as it does any change of
  /// them. It notes the grid's days' state again ([_noteLoad]), and where
  /// the store's zone is not the one the last ask asked on, asks for them
  /// after the frame ([_scheduleAsk]).
  void _handleStore() {
    if (widget.store.zone != _zone) {
      _takeZone();
    }
    _noteLoad();
    if (widget.store.zone != _askedZone) {
      _scheduleAsk();
    }
    setState(() {
      _syncPending = true;
    });
  }

  void _handleNow() {
    if (widget.store.zone != _zone) {
      _takeZone();
      return;
    }
    _today.value = _plainTwinOf(widget.now.value.today);
  }

  /// Takes the store's zone: today as [MonthBoard.now] gives it, and the
  /// create mark on the day holding the create's start on the new clock
  /// ([_createAt]). Lays nothing out and installs no animation: the store
  /// notify that brought the zone, or a new store's build, lays out the
  /// refiled entries.
  void _takeZone() {
    _zone = widget.store.zone;
    _today.value = _plainTwinOf(widget.now.value.today);
    final createAt = _createAt;
    if (createAt != null) {
      _createMark.value = _plainTwinOf(
        CalendarDates.inZone(createAt, zone: _zone),
      );
    }
  }

  /// Notes the store's status of [MonthBoard.grid]'s days, and their error
  /// where that is failed ([CalendarEntryReader.statusOf],
  /// [CalendarEntryReader.loadErrorOf]), which [_daysReady] and the cover
  /// read. Runs in [initState], in [didUpdateWidget] for a new store or a
  /// new grid, and at each store notify ([_handleStore]).
  void _noteLoad() {
    final store = widget.store;
    final grid = widget.grid;
    final status = store.statusOf(grid.firstDay, grid.lastDay);
    _loadStatus = status;
    _loadError = status == CalendarLoadStatus.failed
        ? store.loadErrorOf(grid.firstDay, grid.lastDay)
        : null;
  }

  /// Asks for the grid's days after the frame ([_askDays]), once however
  /// many new grids, stores and zones a frame brings, and asks for that
  /// frame where none is under way, since a store's ask can notify and a
  /// build or a layout must not.
  void _scheduleAsk() {
    if (_askPending) {
      return;
    }
    _askPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _askPending = false;
      if (mounted) {
        _askDays();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Reads the grid's unread days ([CalendarEntryReader.prefetch]), unless
  /// their read failed: a failed read leaves its days unread, and the
  /// cover's retry reads them again ([_retryLoad]). Takes the store's zone
  /// as the one asked on ([_askedZone]).
  void _askDays() {
    final store = widget.store;
    final grid = widget.grid;
    _askedZone = store.zone;
    if (store.statusOf(grid.firstDay, grid.lastDay) !=
        CalendarLoadStatus.failed) {
      store.prefetch(grid.firstDay, grid.lastDay);
    }
  }

  /// The day numbers of [MonthBoard.grid]'s days, whose stale days the
  /// board reads again ([_staleAsk]).
  ({int first, int last}) _gridDays() {
    final grid = widget.grid;
    return (
      first: CalendarDates.dayNumber(grid.firstDay),
      last: CalendarDates.dayNumber(grid.lastDay),
    );
  }

  /// The failure state's retry: a retry of the grid's days
  /// ([CalendarEntryReader.retry]).
  void _retryLoad() {
    final grid = widget.grid;
    widget.store.retry(grid.firstDay, grid.lastDay);
  }

  /// Whether this grid's days are ready: whether the store answered them
  /// ready when [_noteLoad] last asked.
  bool get _daysReady {
    return _loadStatus == CalendarLoadStatus.ready;
  }

  /// Selects the selected day's cell on the board. The board reports the
  /// write at once, which [_handleBoardSelection] ignores while
  /// [_writingSelection] holds.
  void _writeSelection() {
    final cell = widget.grid.cellOf(widget.selectedDay);
    _writingSelection = true;
    try {
      _board.setSelection(BoardSelection(anchor: cell, focus: cell));
    } finally {
      _writingSelection = false;
    }
  }

  /// A key, which the board hands this state before its own keys. An
  /// arrow reports the shown day before or after the day the selection is
  /// on, as the board's columns run left to right whatever the ambient
  /// [Directionality], or the day a week before or after it, in whatever
  /// month that day lies, and selects it on the board and scrolls it into
  /// view at once where the grid shows it, as the board does for its own
  /// keys. Home, End and the page keys are the board's, which moves from
  /// its selection; until the frame after a move that reported a day
  /// outside the grid, which the selection is not on, they do nothing.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final grid = widget.grid;
    final moved = _movedDay;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.end ||
        key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.pageDown) {
      if (moved != null && _cellShowing(grid, moved) == null) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final from = moved ?? _selectedCellDay(grid) ?? widget.selectedDay;
    final DateTime day;
    if (key == LogicalKeyboardKey.arrowLeft) {
      day = CalendarDates.nextShownDay(from, -1, grid.weekdays);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      day = CalendarDates.nextShownDay(from, 1, grid.weekdays);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      day = CalendarDates.addDays(from, -DateTime.daysPerWeek);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      day = CalendarDates.addDays(from, DateTime.daysPerWeek);
    } else {
      return KeyEventResult.ignored;
    }
    _noteMoved(day);
    final cell = _cellShowing(grid, day);
    if (cell != null) {
      _writingSelection = true;
      try {
        _board.setSelection(BoardSelection(anchor: cell, focus: cell));
      } finally {
        _writingSelection = false;
      }
      _board.revealCell(cell.row, cell.col);
    }
    widget.onSelectDay(day);
    return KeyEventResult.handled;
  }

  /// Notes [day] as the day the last move of the selection reported, until
  /// the frame after it.
  void _noteMoved(DateTime day) {
    if (_movedDay == null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _movedDay = null;
      });
      SchedulerBinding.instance.ensureVisualUpdate();
    }
    _movedDay = day;
  }

  /// The day of the board's selected cell, or null where the selection is
  /// on no cell of [grid].
  DateTime? _selectedCellDay(CalendarMonthGrid grid) {
    final focus = _board.selection.value.focus;
    if (focus == null ||
        focus.row >= grid.weekCount ||
        focus.col >= grid.columnCount) {
      return null;
    }
    return grid.dateAt(focus.row, focus.col);
  }

  /// The cell of [grid] that shows [day], a day of its month or another,
  /// or null where no cell does. A shown day lies less than seven days
  /// after the first cell of its row, the earliest day the row shows.
  static ({int row, int col})? _cellShowing(
    CalendarMonthGrid grid,
    DateTime day,
  ) {
    final number = CalendarDates.dayNumber(day);
    final offset = number - CalendarDates.dayNumber(grid.firstDay);
    if (offset < 0) {
      return null;
    }
    final row = offset ~/ DateTime.daysPerWeek;
    if (row >= grid.weekCount) {
      return null;
    }
    for (var col = 0; col < grid.columnCount; col++) {
      if (CalendarDates.dayNumber(grid.dateAt(row, col)) == number) {
        return (row: row, col: col);
      }
    }
    return null;
  }

  /// The board's keys or a tap moved its selection: reports the day of its
  /// focus cell when the cell lies in the grid. Keys before a frame each
  /// report, each stepping from the day the one before selected.
  void _handleBoardSelection(BoardSelection selection) {
    if (_writingSelection) {
      return;
    }
    final day = _selectedCellDay(widget.grid);
    if (day == null) {
      return;
    }
    _noteMoved(day);
    widget.onSelectDay(day);
  }

  void _openDay(DateTime day) {
    if (_pinch.pinched.value) {
      return;
    }
    _focusNode.requestFocus();
    widget.onOpenDay(day);
  }

  /// Reports a create on [day] for a long press on its cell, or for a
  /// screen reader's long press, with the platform's long-press feedback
  /// ([Feedback.forLongPress]) for both, as Material's `InkWell` gives.
  void _createOnDay(DateTime day, Rect globalRect) {
    final create = widget.onCreateOnDay;
    if (create == null || _pinch.pinched.value) {
      return;
    }
    Feedback.forLongPress(context);
    _focusNode.requestFocus();
    final created = create(day, globalRect);
    if (created == null) {
      return;
    }
    final count = ++_createCount;
    _createMark.value = day;
    _createAt = created.start;
    created.done.whenComplete(() {
      // After dispose the notifier takes no write.
      if (mounted && count == _createCount) {
        _createMark.value = null;
        _createAt = null;
      }
    });
  }

  void _openEntry(String id) {
    if (!_pinch.pinched.value) {
      widget.onOpenEntry(id);
    }
  }

  bool _startPinch(PinchAxis axis, Offset focal) {
    _pinchFrom = (weekScale: widget.weekScale, day: _columnWidth);
    return true;
  }

  /// Reports through [MonthBoard.onZoom] the week scale or the least day
  /// width the pinch zooms to, its scale times the one shown at its start,
  /// within the ones offered, and notes where its fingers meet for the
  /// layout that follows.
  void _pinchTo(PinchUpdate update) {
    final from = _pinchFrom;
    final onZoom = widget.onZoom;
    final area = _boardAreaKey.currentContext?.findRenderObject();
    if (from == null || onZoom == null || area is! RenderBox) {
      return;
    }
    var weekScale = widget.weekScale;
    var day = widget.minDayWidth;
    switch (update.axis) {
      case PinchAxis.vertical:
        weekScale = (from.weekScale * update.scale).clamp(
          1.0,
          maxMonthWeekScale,
        );
      case PinchAxis.horizontal:
        day = (from.day * update.scale).clamp(minDayWidthLow, minDayWidthHigh);
    }
    if (weekScale == widget.weekScale && day == widget.minDayWidth) {
      return;
    }
    _pinchFocal = area.globalToLocal(update.focal);
    onZoom(weekScale, day);
  }

  void _endPinch() {
    _pinchFrom = null;
  }

  /// Hands [event] to the pinch while the board is mounted.
  /// `GestureBinding` sends a pointer's moves, lift and cancel along the
  /// path its down hit, which still holds the board's listener once the
  /// board has left the tree.
  void _handlePointer(PointerEvent event) {
    if (mounted) {
      _pinch.handleEvent(event);
    }
  }

  /// Holds the board's scrolling while two fingers are down, and lets it
  /// go after.
  void _handleHolding() {
    if (_pinch.holding.value) {
      _scrollHold.hold(<ScrollPosition?>[
        _scroll.hasClients ? _scroll.position : null,
        _horizontal.hasClients ? _horizontal.position : null,
      ]);
    } else {
      _scrollHold.release();
    }
  }

  /// Keeps the lattice point under [focal] there across the axes that
  /// replaced [oldRows] and [oldColumns] ([holdFocalAcrossAxisSwap]). The
  /// board has no frozen tracks.
  void _holdPinchFocal(
    Offset focal,
    BoardAxisConfig oldRows,
    BoardAxisConfig oldColumns,
  ) {
    if (_scroll.hasClients && !identical(oldRows.axis, _board.rows.axis)) {
      holdFocalAcrossAxisSwap(
        _scroll.position,
        old: oldRows.axis,
        next: _board.rows.axis,
        band: 0.0,
        focal: focal.dy,
      );
    }
    if (_horizontal.hasClients &&
        !identical(oldColumns.axis, _board.columns.axis)) {
      holdFocalAcrossAxisSwap(
        _horizontal.position,
        old: oldColumns.axis,
        next: _board.columns.axis,
        band: 0.0,
        focal: focal.dx,
      );
    }
  }

  /// Gives the board the axes [size], the grid, the layout, the least day
  /// width and the week scale ask for, with card lanes where the days are
  /// large enough for cards ([monthShowsCards]) and,
  /// when a sync is pending, the days turned from chips to cards or back,
  /// or the lanes a week holds under [CalendarMonthLayout.fitScreen] changed,
  /// the bars of the items the store shows on the grid's days inside the hours
  /// ([splitMonthHours]), none while they are not ready, all in one batch and
  /// so one structural notification; the sync also tells each day what it hides
  /// ([_writeHidden]). A sync the store, the grid or the hours owe reads the
  /// store before the axes, since the banners it counts decide the room above
  /// and below the lanes, and splits only what the store answers anew
  /// ([_splitOf]); one the lanes or the cards alone owe fits the kept split's
  /// bars again ([_split]). Called from the layout callback, so the first frame
  /// lays the board out at its size.
  ///
  /// A sync animates only when it follows the store alone, its days are
  /// ready and the last sync's were. Any other sync runs under
  /// [BoardAnimationStyle.disabled], which [_scheduleStyleRestore] lifts,
  /// and settles in its batch every enter and exit in flight
  /// ([_placeSettled]). A refit alone leaves the style as it is, so the
  /// motion in flight runs on: the replaced axis lands its own track
  /// resizes, and a new row axis takes each week's first measurement
  /// without animating it.
  void _layoutBoard(Size size) {
    final focal = _pinchFocal;
    _pinchFocal = null;
    final oldRows = _board.rows;
    final oldColumns = _board.columns;
    final grid = widget.grid;
    final layout = widget.layout;
    final hours = widget.hours;
    final fitted = fittedWeekExtent(
      size.height,
      grid.weekCount,
      scale: widget.weekScale,
      laneExtent: _chipLane,
    );
    final width = size.width.isFinite && size.width > 0.0
        ? math.max(widget.minDayWidth, size.width / grid.columnCount)
        : _columnWidth;
    final cards = monthShowsCards(width, fitted, cardExtent: _cardLane);
    final laneExtent = cards ? _cardLane : _chipLane;
    final ready = _daysReady;
    if (_syncPending) {
      final split = _splitOf(grid, hours, ready);
      _split = split;
      _earlierBand = split.earlier.any(_isCounted);
      _laterBand = split.later.any(_isCounted);
    }
    final split = _split!;
    final padding =
        monthStripHeight + (_earlierBand ? monthHoursBannerExtent : 0.0);
    final lanes = layout == CalendarMonthLayout.fitScreen
        ? monthLanesThatFit(
            fitted,
            laneExtent: laneExtent,
            reserved: padding + (_laterBand ? monthHoursBannerExtent : 0.0),
          )
        : null;
    final fittedGrid = _fittedGrid;
    final rowsChanged =
        fittedGrid == null ||
        !_sameGrid(grid, fittedGrid) ||
        layout != _fittedLayout ||
        hours != _fittedHours ||
        fitted != _fitted ||
        padding != _fittedPadding ||
        laneExtent != _fittedLaneExtent ||
        cards != _cards;
    final columnsChanged =
        width > 0.0 &&
        (width != _columnWidth ||
            _board.columns.axis.trackCount != grid.columnCount);
    // New lanes place the bars again, and tell each day where its banners
    // lie, under either layout.
    final sync =
        _syncPending ||
        lanes != _syncedLanes ||
        cards != _cards ||
        laneExtent != _fittedLaneExtent;
    if (!rowsChanged && !columnsChanged && !sync) {
      return;
    }
    List<BoardPlacement<MonthChip<T>>>? placements;
    Int32List? hidden;
    if (sync && !ready) {
      placements = <BoardPlacement<MonthChip<T>>>[];
    } else if (sync) {
      final all = split.placements;
      if (lanes == null) {
        placements = all;
      } else {
        final fit = fitMonthPlacements(all, grid, lanes);
        placements = fit.shown;
        hidden = fit.hidden;
      }
    }
    final next = <String, BoardPlacement<MonthChip<T>>>{
      if (placements != null)
        for (final placement in placements) placement.item.key: placement,
    };
    final animated = !rowsChanged && !columnsChanged && ready && _syncedReady;
    final settles = placements != null && !animated;
    _board.runBatch(() {
      if (settles) {
        _board.animationStyle = BoardAnimationStyle.disabled;
      }
      if (rowsChanged) {
        // A new axis instance each time, so no measurement outlives its
        // month or its fit.
        _board.rows = _rowsConfig(grid, fitted, laneExtent, padding);
      }
      if (columnsChanged) {
        _board.columns = BoardAxisConfig(
          axis: UniformAxis(grid.columnCount, width),
        );
      }
      if (placements == null) {
        return;
      }
      if (settles) {
        _placeSettled(placements, next);
      } else {
        _board.setItems(placements);
      }
    });
    if (focal != null) {
      _holdPinchFocal(focal, oldRows, oldColumns);
    }
    if (settles) {
      _scheduleStyleRestore();
    }
    _fittedGrid = grid;
    _fittedLayout = layout;
    _fittedHours = hours;
    _fitted = fitted;
    _fittedPadding = padding;
    final relaned = laneExtent != _fittedLaneExtent;
    _fittedLaneExtent = laneExtent;
    if (cards != _cards) {
      // The build that follows hands the board the other builder, which
      // asks for every bar again.
      _chips.clear();
      _cards = cards;
    } else if (relaned) {
      // A bar is as tall as its lane: a new builder of the same kind has
      // the board ask for every bar again, built at the new height.
      _chips.clear();
      if (cards) {
        _cardBuilder = (context, view) {
          return _buildCard(context, view);
        };
      } else {
        _chipBuilder = (context, view) {
          return _buildChip(context, view);
        };
      }
    }
    if (columnsChanged) {
      _columnWidth = width;
    }
    // Owed by a new grid, which syncs, by a new least day width, which may
    // only refit the columns, or by a new selected day given while the days
    // were not ready.
    if (_revealPending) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _revealSelected(grid, again: true);
      });
      if (ready) {
        _revealPending = false;
      }
    }
    if (placements == null) {
      return;
    }
    if (animated) {
      _recordMotion(next);
    }
    _syncPending = false;
    _syncedReady = ready;
    _syncedLanes = lanes;
    _placed = next;
    final remeasure = _writeHidden(
      grid,
      hidden,
      lanes,
      laneExtent,
      padding,
      split,
      _laterBand ? monthDayLanesOf(placements, grid) : null,
    );
    if (remeasure) {
      // A cell's own rebuild does not re-measure it on the board, and its
      // least height holds its banner after the hours under its chips.
      _board.invalidateCellMeasurements();
    }
    // A key in `_dropped` may still be exiting: the board keeps its child
    // and calls the item builder for it on every delegate rebuild, which
    // must hand back the kept instance.
    _chips.removeWhere((key, kept) {
      return !next.containsKey(key) && !_dropped.containsKey(key);
    });
  }

  /// The items the store shows on [grid]'s days split by [hours]
  /// ([splitMonthHours]), with their bars ([monthPlacementsOf]); none, and
  /// no day counting any, while they are not [ready]. Where the store
  /// answers the entries the last split read, the identical instances with
  /// the same pending flags in the same order, for the same grid and hours,
  /// the split is that one, [_split], and runs nothing.
  _MonthSplit<T> _splitOf(
    CalendarMonthGrid grid,
    CalendarDayHours hours,
    bool ready,
  ) {
    final read = ready
        ? widget.store.entriesBetween(grid.firstDay, grid.lastDay)
        : <CalendarShownEntry<T>>[];
    final kept = _split;
    if (kept != null &&
        _sameGrid(kept.grid, grid) &&
        kept.hours == hours &&
        _sameShown(kept.read, read)) {
      return kept;
    }
    noteEntrySplit();
    if (!ready) {
      final cells = grid.weekCount * grid.columnCount;
      return (
        read: read,
        grid: grid,
        hours: hours,
        inside: <CalendarShownEntry<T>>[],
        earlier: Int32List(cells),
        later: Int32List(cells),
        placements: <BoardPlacement<MonthChip<T>>>[],
      );
    }
    final split = splitMonthHours(read, grid, hours, zone: _zone);
    return (
      read: read,
      grid: grid,
      hours: hours,
      inside: split.inside,
      earlier: split.earlier,
      later: split.later,
      placements: monthPlacementsOf(split.inside, grid),
    );
  }

  /// Whether [a] and [b] hold the identical entries with the same pending
  /// flags, in the same order.
  static bool _sameShown<T>(
    List<CalendarShownEntry<T>> a,
    List<CalendarShownEntry<T>> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i].entry, b[i].entry) || a[i].pending != b[i].pending) {
        return false;
      }
    }
    return true;
  }

  static bool _isCounted(int count) {
    return count > 0;
  }

  /// Tells each cell of [grid] how many chips it hides by [hidden], and
  /// that its "+N more" takes the last of [lanes], each [laneExtent] tall,
  /// under [padding]; every cell hides none when [hidden] is null. Tells
  /// each how many items [split] counts on it before and after the hours,
  /// and that its banner after the hours takes the lane under its deepest
  /// chip by [dayLanes] and under its "+N more", which it measures at least
  /// down to. Runs in the layout callback's build scope, so the cells that
  /// listen rebuild in it. Returns whether any cell's least height changed.
  bool _writeHidden(
    CalendarMonthGrid grid,
    Int32List? hidden,
    int? lanes,
    double laneExtent,
    double padding,
    _MonthSplit<T> split,
    Int32List? dayLanes,
  ) {
    final cells = grid.weekCount * grid.columnCount;
    var remeasure = false;
    for (var i = 0; i < _hidden.length; i++) {
      final inGrid = i < cells;
      final count = hidden != null && inGrid ? hidden[i] : 0;
      final later = inGrid ? split.later[i] : 0;
      // Only a day that counts some has the lanes [dayLanes] gives.
      final laterLane = later == 0
          ? 0
          : math.max(dayLanes![i], count == 0 ? 0 : lanes!);
      final laned = count > 0 || later > 0;
      final extent = later == 0
          ? monthStripHeight
          : padding + laterLane * laneExtent + monthHoursBannerExtent;
      final _Hidden value = (
        count: count,
        lane: count == 0 ? 0 : lanes! - 1,
        laneExtent: laned ? laneExtent : monthLaneExtent,
        lanePadding: laned ? padding : monthStripHeight,
        earlier: inGrid ? split.earlier[i] : 0,
        later: later,
        laterLane: laterLane,
        extent: extent,
      );
      if (_hidden[i].value.extent != extent) {
        remeasure = true;
      }
      _hidden[i].value = value;
    }
    return remeasure;
  }

  /// Records what the animated sync placing [next] starts: each key
  /// [_placed] holds and [next] lacks exits, each key [next] holds and
  /// [_placed] lacks enters.
  void _recordMotion(Map<String, BoardPlacement<MonthChip<T>>> next) {
    for (final entry in _placed.entries) {
      if (!next.containsKey(entry.key)) {
        _dropped[entry.key] = entry.value;
        _added.remove(entry.key);
      }
    }
    for (final key in next.keys) {
      if (!_placed.containsKey(key)) {
        _added.add(key);
        _dropped.remove(key);
      }
    }
  }

  /// Sets [placements], whose placements by key are [next], under the
  /// disabled style, so that no enter or exit is in flight afterwards.
  ///
  /// With the item enter and exit family off, `setItems` brings back whole
  /// a key whose exit runs, adds whole a key the board holds no item for,
  /// and retires at once a key it leaves out, an entering one included.
  /// So the first call carries every dropped key [next] lacks, bringing
  /// back an exiting one, and leaves out every added key [next] holds,
  /// retiring an entering one; the second retires the carried keys and
  /// adds the left-out ones whole, under new ids. Inside the sync's batch
  /// the two calls make one notification.
  void _placeSettled(
    List<BoardPlacement<MonthChip<T>>> placements,
    Map<String, BoardPlacement<MonthChip<T>>> next,
  ) {
    final carry = <BoardPlacement<MonthChip<T>>>[
      for (final entry in _dropped.entries)
        if (!next.containsKey(entry.key)) entry.value,
    ];
    final renew = <String>{
      for (final key in _added)
        if (next.containsKey(key)) key,
    };
    _dropped.clear();
    _added.clear();
    if (carry.isEmpty && renew.isEmpty) {
      _board.setItems(placements);
      return;
    }
    _board.setItems(<BoardPlacement<MonthChip<T>>>[
      for (final placement in placements)
        if (!renew.contains(placement.item.key)) placement,
      ...carry,
    ]);
    _board.setItems(placements);
  }

  /// Puts the styles' animation back in a frame callback scheduled
  /// after the batch of the sync that disabled it, so it runs at the next
  /// frame's start, before that frame's layout and after the sync's own
  /// layout has measured the weeks under the disabled style. That sync
  /// left nothing in flight ([_placeSettled]), so a sync the next frame
  /// lays out animates.
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

  /// Scrolls the least that shows the selected day, while [scheduledFor]
  /// is still the grid, and where [yields], while the user does not hold or
  /// scroll the board ([_userScrolls]). The first reveal of a new grid can
  /// read a week at its estimate, and the layout it causes measures that
  /// week, so a reveal that moved asks once more after it.
  void _revealSelected(
    CalendarMonthGrid scheduledFor, {
    required bool again,
    bool yields = false,
  }) {
    if (!mounted ||
        !_sameGrid(widget.grid, scheduledFor) ||
        !_scroll.hasClients ||
        (yields && _userScrolls)) {
      return;
    }
    final before = _scroll.position.pixels;
    final cell = widget.grid.cellOf(widget.selectedDay);
    _board.revealCell(cell.row, cell.col);
    if (again && _scroll.position.pixels != before) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _revealSelected(scheduledFor, again: false, yields: yields);
      });
    }
  }

  /// Reveals a new selected day of the same grid after the frame that
  /// selects it ([_revealSelected]), yielding to the user, and where the
  /// days are not ready, owes the layout that finds them ready a reveal
  /// too ([_revealPending]), as their weeks may grow then; the cover over
  /// the board takes every press until then.
  void _revealNewSelection() {
    if (!_daysReady) {
      _revealPending = true;
    }
    final grid = widget.grid;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _revealSelected(grid, again: true, yields: true);
    });
  }

  /// Whether the user holds or scrolls the board: two fingers are down
  /// ([PinchTracker.holding]), or a drag, or the fling after it, scrolls
  /// either axis ([ScrollPosition.userScrollDirection]).
  bool get _userScrolls {
    return _pinch.holding.value ||
        _scrolledByUser(_scroll) ||
        _scrolledByUser(_horizontal);
  }

  static bool _scrolledByUser(ScrollController controller) {
    return controller.hasClients &&
        controller.position.userScrollDirection != ScrollDirection.idle;
  }

  Widget? _buildDay(
    BuildContext context,
    BoardCellView<String, MonthChip<T>> cell,
  ) {
    final grid = widget.grid;
    // A key moving the selection rebuilds the cells whose answer changed in
    // the layout callback's build scope, after the callback hands the board
    // a new grid and before its layout drops the cells the grid lacks.
    if (cell.row >= grid.weekCount || cell.col >= grid.columnCount) {
      return _outsideGrid;
    }
    final index = cell.row * grid.columnCount + cell.col;
    final selected = cell.isSelected;
    final kept = _days[index];
    if (kept != null && kept.selected == selected) {
      return kept.widget;
    }
    final day = kept?.day ?? grid.dateAt(cell.row, cell.col);
    final built = _MonthDayCell(
      key: monthDayKey(day),
      day: day,
      inMonth: grid.contains(day),
      isSelected: selected,
      today: _today,
      hidden: _hidden[index],
      bannerHours: _bannerHours,
      creates: _creates,
      createMark: _createMark,
      onOpen: _openDay,
      onCreate: _createOnDay,
    );
    _days[index] = (day: day, selected: selected, widget: built);
    return built;
  }

  Widget _buildChip(
    BuildContext context,
    BoardItemView<String, MonthChip<T>> view,
  ) {
    return _buildBar(view.item, card: false);
  }

  Widget _buildCard(
    BuildContext context,
    BoardItemView<String, MonthChip<T>> view,
  ) {
    return _buildBar(view.item, card: true);
  }

  /// The kept bar of [chip] where it was built for an equal chip, which the
  /// board then neither updates nor rebuilds, so no bar's builder runs for
  /// a sync that leaves its chip as it was; a new one otherwise.
  Widget _buildBar(MonthChip<T> chip, {required bool card}) {
    final kept = _chips[chip.key];
    if (kept != null && kept.chip == chip) {
      return kept.widget;
    }
    final built = Align(
      alignment: Alignment.topLeft,
      child: _MonthChipBox<T>(
        key: monthChipKey(chip.key),
        chip: chip,
        card: card,
        extent: card ? _cardLane : _chipLane,
        builder: _barBuilder,
        kindOf: widget.entryKindOf,
        format: widget.hourLabelFormat,
        onOpen: _openEntry,
      ),
    );
    _chips[chip.key] = (chip: chip, widget: built);
    return built;
  }

  /// The cover's content: what the failure builder draws for the grid's
  /// days when their read failed, with the store's error for them and a
  /// retry of them ([_retryLoad]), and what the loading builder draws
  /// otherwise.
  Widget _buildCover(BuildContext context) {
    final grid = widget.grid;
    // The grid's days are plain; a host is told them on the store's clock.
    final first = CalendarDates.dateOfDayNumber(
      CalendarDates.dayNumber(grid.firstDay),
      zone: _zone,
    );
    final last = CalendarDates.dateOfDayNumber(
      CalendarDates.dayNumber(grid.lastDay),
      zone: _zone,
    );
    if (_loadStatus == CalendarLoadStatus.failed) {
      final failure = widget.failureBuilder ?? defaultCalendarFailureBuilder;
      return failure(
        context,
        CalendarFailureState(
          site: CalendarStateSite.cover,
          first: first,
          last: last,
          error: _loadError,
          retry: _retryLoad,
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

  /// Measures [_chipLane] and [_cardLane] in [context]: a chip's lane
  /// [monthLaneExtent] tall at no text scaling, and at a larger text a
  /// line of a chip's title in the default chip's style and of the "+N
  /// more" banner's, with the room the chip leaves around that line at no
  /// scaling, as [numberBoxIn] keeps the room around a number; and a
  /// card's lane [monthCardExtent] tall at no text scaling, and at a
  /// larger text a line of a card's title over one of its times, with the
  /// room the card leaves around them at none. Each holds its bar inside
  /// [_barInset]. The default chip's line is the theme's
  /// [CalendarThemeData.chipTitleStyle], and a card's are its
  /// [CalendarThemeData.monthCardTitleStyle] and
  /// [CalendarThemeData.monthCardTimeStyle], which a
  /// [MonthBoard.chipBuilder] draws in too where its bars are to fit.
  void _measureLanes(BuildContext context) {
    final styles = _styles;
    final theme = styles.theme;
    const inset = 2 * _barInset;
    _chipLane =
        inset +
        math.max(
          _linesBoxIn(context, <TextStyle>[
            theme.chipTitleStyle,
          ], monthLaneExtent - inset),
          _linesBoxIn(context, <TextStyle>[
            styles.moreLabel,
          ], monthLaneExtent - inset),
        );
    _cardLane =
        inset +
        _linesBoxIn(context, <TextStyle>[
          theme.monthCardTitleStyle,
          theme.monthCardTimeStyle,
        ], monthCardExtent - inset);
  }

  /// The height of a box holding a line of each of [styles], one over the
  /// next, in [context] ([labelSizeIn]): [least] at no text scaling where
  /// the lines fit it, and otherwise the lines' height with the room
  /// [least] leaves around them at no scaling.
  static double _linesBoxIn(
    BuildContext context,
    List<TextStyle> styles,
    double least,
  ) {
    var scaled = 0.0;
    var unscaled = 0.0;
    for (final style in styles) {
      scaled += labelSizeIn(context, style, _lineSample).height;
      unscaled += labelSizeIn(
        context,
        style,
        _lineSample,
        scaler: TextScaler.noScaling,
      ).height;
    }
    return math.max(least, scaled + math.max(0.0, least - unscaled));
  }

  @override
  Widget build(BuildContext context) {
    _measureLanes(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final below = math.max(0.0, size.height - weekdayHeaderHeight);
        final padding = math.min(widget.bottomPadding, below);
        // The board takes the height between the letters, whose columns
        // the layout sizes first, and the padding.
        _layoutBoard(Size(size.width, below - padding));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WeekdayHeader(
              weekdays: widget.grid.weekdays,
              columnWidth: _columnWidth,
              horizontal: _horizontal,
              // The board reads no Directionality: its columns run left to
              // right.
              columnDirection: TextDirection.ltr,
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: Listener(
                      key: _boardAreaKey,
                      onPointerDown: _handlePointer,
                      onPointerMove: _handlePointer,
                      onPointerUp: _handlePointer,
                      onPointerCancel: _handlePointer,
                      child: Board<String, MonthChip<T>>(
                        controller: _board,
                        cellBuilder: _cellBuilder,
                        itemBuilder: _cards ? _cardBuilder : _chipBuilder,
                        background: _background,
                        selection: _selectionConfig,
                        focusNode: _focusNode,
                        onKeyEvent: _handleKey,
                        // The board scrolls on its own, not with the screen's
                        // primary scroll controller.
                        primary: false,
                        verticalDetails: ScrollableDetails.vertical(
                          controller: _scroll,
                        ),
                        horizontalDetails: ScrollableDetails.horizontal(
                          controller: _horizontal,
                        ),
                      ),
                    ),
                  ),
                  if (!_daysReady)
                    Positioned.fill(
                      child: _MonthLoadOverlay(
                        child: Builder(
                          builder: (context) {
                            return _buildCover(context);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (padding > 0.0) SizedBox(height: padding),
          ],
        );
      },
    );
  }
}

/// The month board's background: each day of another month on the
/// background colour, and a line in the outline colour between every two
/// weeks and every two shown weekdays, none around the board's edge, in
/// [styles]' paints.
class _MonthGridPainter extends BoardBackgroundPainter {
  _MonthGridPainter(this.grid, this.styles)
    : _outside = <bool>[
        for (var row = 0; row < grid.weekCount; row++)
          for (var col = 0; col < grid.columnCount; col++)
            !grid.contains(grid.dateAt(row, col)),
      ];

  final CalendarMonthGrid grid;
  final _MonthStyles styles;

  /// Whether each cell of [grid], at `row * columnCount + col`, shows a day
  /// of another month.
  final List<bool> _outside;

  @override
  void paint(Canvas canvas, BoardGeometryView geometry) {
    final firstRow = geometry.firstVisibleRow;
    final lastRow = geometry.lastVisibleRow;
    final firstCol = geometry.firstVisibleCol;
    final lastCol = geometry.lastVisibleCol;
    if (firstRow > lastRow || firstCol > lastCol) {
      return;
    }
    final columns = grid.columnCount;
    final outsidePaint = styles.outsidePaint;
    final linePaint = styles.linePaint;
    for (var row = firstRow; row <= lastRow; row++) {
      for (var col = firstCol; col <= lastCol; col++) {
        if (_outside[row * columns + col]) {
          canvas.drawRect(geometry.visibleCellRect(row, col), outsidePaint);
        }
      }
    }
    final first = geometry.visibleCellRect(firstRow, firstCol);
    final last = geometry.visibleCellRect(lastRow, lastCol);
    for (var row = math.max(firstRow, 1); row <= lastRow; row++) {
      final y = geometry.visibleCellRect(row, firstCol).top;
      canvas.drawLine(Offset(first.left, y), Offset(last.right, y), linePaint);
    }
    for (var col = math.max(firstCol, 1); col <= lastCol; col++) {
      final x = geometry.visibleCellRect(firstRow, col).left;
      canvas.drawLine(Offset(x, first.top), Offset(x, last.bottom), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MonthGridPainter old) {
    return !_MonthBoardState._sameGrid(old.grid, grid) ||
        !identical(old.styles, styles);
  }
}

/// One day of the month board: a tap anywhere on it outside its chips
/// opens the day, and a long press creates on it while [creates] holds and
/// otherwise opens it as a tap does. Its number sits in the
/// strip across its top, and while it hides chips, "+N more" on a soft
/// yellow banner in its lane. While it counts items wholly before the
/// hours, "+N earlier" on one under its strip, and while it counts items
/// wholly after them, "+N later" on one in the lane under its last chip.
class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    super.key,
    required this.day,
    required this.inMonth,
    required this.isSelected,
    required this.today,
    required this.hidden,
    required this.bannerHours,
    required this.creates,
    required this.createMark,
    required this.onOpen,
    required this.onCreate,
  });

  final DateTime day;

  /// Whether [day] is a day of the grid's month; another's number is
  /// muted.
  final bool inMonth;

  final bool isSelected;
  final ValueListenable<DateTime> today;
  final ValueListenable<_Hidden> hidden;
  final ValueListenable<_BannerHours> bannerHours;
  final ValueListenable<bool> creates;

  /// The day whose create is open, which the cell marks while it is [day].
  final ValueListenable<DateTime?> createMark;

  final ValueChanged<DateTime> onOpen;

  /// Takes a long press's create on [day], with the cell's rect in global
  /// logical pixels.
  final void Function(DateTime day, Rect globalRect) onCreate;

  @override
  Widget build(BuildContext context) {
    final strings = CalendarLocalizations.of(context);
    final label = strings.dayLabel(day);
    final styles = _MonthStyles.of(context);
    void open() {
      onOpen(day);
    }

    void createOn() {
      // The cell's render object is its root box, which the board lays
      // out over the cell.
      final box = context.findRenderObject()! as RenderBox;
      onCreate(day, globalRectOf(box, Offset.zero & box.size));
    }

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        today,
        hidden,
        bannerHours,
        creates,
      ]),
      builder: (context, child) {
        final isToday = day == today.value;
        final hides = hidden.value;
        final hours = bannerHours.value;
        final create = creates.value ? createOn : null;
        return Semantics(
          container: true,
          button: true,
          selected: isSelected,
          label: <String>[
            label,
            if (isToday) strings.today,
            if (hides.earlier > 0)
              strings.moreEntriesBefore(
                hides.earlier,
                strings.formatTime(hours.hours.start, hours.format),
              ),
            if (hides.count > 0) strings.moreEntries(hides.count),
            if (hides.later > 0)
              strings.moreEntriesAfter(
                hides.later,
                strings.formatTime(hours.hours.end, hours.format),
              ),
          ].join(", "),
          hint: strings.openDayHint,
          onTap: open,
          onLongPress: create,
          onLongPressHint: create == null ? null : strings.createEntryHint,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: open,
            onLongPress: create,
            // A stack sized by the strip and the least extent alone, as the
            // banners are positioned, so a cell measures that and a week
            // with no chips rests at its fitted extent, while a cell laid
            // out at its extent takes the whole cell.
            child: Stack(
              children: <Widget>[
                // Positioned, the mark leaves the stack's size to the
                // children below, and only its own answer builds it again.
                Positioned.fill(
                  child: AnswerBuilder<bool>(
                    listenables: <Listenable>[createMark],
                    answer: () {
                      return createMark.value == day;
                    },
                    builder: (context, marked, child) {
                      return DecoratedBox(
                        decoration: marked
                            ? styles.createMark
                            : const BoxDecoration(),
                      );
                    },
                  ),
                ),
                SizedBox(height: hides.extent),
                SizedBox(
                  key: monthStripKey(day),
                  height: monthStripHeight,
                  child: Center(child: _buildNumber(context, isToday, styles)),
                ),
                if (hides.earlier > 0)
                  Positioned(
                    left: 0.0,
                    right: 0.0,
                    top: monthStripHeight,
                    height: monthHoursBannerExtent,
                    child: _buildBanner(
                      monthEarlierKey(day),
                      strings.earlierCount(hides.earlier),
                      styles,
                    ),
                  ),
                if (hides.count > 0)
                  Positioned(
                    left: 0.0,
                    right: 0.0,
                    top: hides.lanePadding + hides.lane * hides.laneExtent,
                    height: hides.laneExtent,
                    child: _buildBanner(
                      monthMoreKey(day),
                      strings.moreCount(hides.count),
                      styles,
                    ),
                  ),
                if (hides.later > 0)
                  Positioned(
                    left: 0.0,
                    right: 0.0,
                    top: hides.lanePadding + hides.laterLane * hides.laneExtent,
                    height: monthHoursBannerExtent,
                    child: _buildBanner(
                      monthLaterKey(day),
                      strings.laterCount(hides.later),
                      styles,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// [text] on a soft yellow banner keyed [key], inset in its band as a
  /// chip is in its lane, so the gap between two chips parts it from a chip
  /// beside it.
  Widget _buildBanner(Key key, String text, _MonthStyles styles) {
    return Padding(
      padding: const EdgeInsets.all(1.0),
      child: DecoratedBox(
        key: key,
        decoration: styles.more,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          // Scaled down, rather than cut off, in a day too narrow for it.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(text, maxLines: 1, style: styles.moreLabel),
          ),
        ),
      ),
    );
  }

  Widget _buildNumber(BuildContext context, bool isToday, _MonthStyles styles) {
    final TextStyle style;
    if (isSelected) {
      style = styles.selectedNumber;
    } else if (isToday) {
      style = styles.todayNumber;
    } else if (inMonth) {
      style = styles.number;
    } else {
      style = styles.mutedNumber;
    }
    final number = Text("${day.day}", maxLines: 1, style: style);
    // Every day's number lies in a box of one size, so each scales down
    // alike, rather than being cut off, in a number strip too small for it.
    final box = numberBoxIn(context, <TextStyle>[
      styles.number,
      styles.selectedNumber,
    ], const Size(_numberBoxWidth, _numberBoxHeight));
    if (!isSelected && !isToday) {
      return fittedLabel(box, number);
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        constraints: BoxConstraints(minWidth: box.width, minHeight: box.height),
        alignment: Alignment.center,
        decoration: isSelected
            ? _MonthStyles.around(styles.selectedPill, box)
            : null,
        foregroundDecoration: isToday
            ? _MonthStyles.around(styles.ring, box)
            : null,
        child: number,
      ),
    );
  }
}

/// One item's bar in one week: a box [extent] tall, its lane's height,
/// over its lane band's top, holding, inside [_barInset] and at that height
/// while the board grows or shrinks the band, what [builder] draws for the
/// chip: a chip one chip lane tall, or a [card] one card lane tall. The box
/// is one semantics node of the chip's label, the kind [kindOf] answers and
/// its times in [format], and its tap, and takes a tap anywhere in it, which
/// does nothing while the chip is pending.
class _MonthChipBox<T> extends StatelessWidget {
  const _MonthChipBox({
    super.key,
    required this.chip,
    required this.card,
    required this.extent,
    required this.builder,
    required this.kindOf,
    required this.format,
    required this.onOpen,
  });

  final MonthChip<T> chip;
  final bool card;

  /// The height of the bar's lane.
  final double extent;
  final CalendarChipBuilder<T> builder;
  final String? Function(CalendarEntry<T> entry)? kindOf;
  final CalendarHourLabelFormat format;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final entry = chip.entry;
    final pending = entry.pending;
    void open() {
      onOpen(entry.id);
    }

    return Semantics(
      container: true,
      button: !pending,
      label: CalendarLocalizations.of(context).entryLabel(
        title: entry.entry.title,
        kind: kindOf?.call(entry.entry),
        start: entry.entry.start,
        end: entry.entry.end,
        format: format,
        pending: pending,
        isAllDay: entry.entry.isAllDay,
      ),
      onTap: pending ? null : open,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        height: extent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Takes a tap while pending too, doing nothing, so neither the
          // day under the chip nor the board's own tap gets it.
          onTap: pending ? () {} : open,
          child: Padding(
            padding: const EdgeInsets.all(_barInset),
            // The bar keeps its height while the board grows or shrinks
            // the chip's band, and is clipped to it.
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minHeight: extent - 2 * _barInset,
                maxHeight: extent - 2 * _barInset,
                child: _ChipContent<T>(
                  entry: entry,
                  details: CalendarChipDetails(
                    card: card,
                    continuesBefore: chip.continuesBefore,
                    continuesAfter: chip.continuesAfter,
                    hourLabelFormat: format,
                  ),
                  builder: builder,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bar's content: what [builder] draws for [entry] and [details], called
/// in this widget's build, below the bar's semantics node and gesture, so a
/// builder that throws loses its own output alone. The month board keeps
/// each bar for an equal chip ([_MonthBoardState._buildBar]), so a sync
/// that leaves a chip as it was builds none of it again.
class _ChipContent<T> extends StatelessWidget {
  const _ChipContent({
    required this.entry,
    required this.details,
    required this.builder,
  });

  final CalendarShownEntry<T> entry;
  final CalendarChipDetails details;
  final CalendarChipBuilder<T> builder;

  @override
  Widget build(BuildContext context) {
    return builder(context, entry, details);
  }
}

/// Covers the board while its days are not ready, taking every press,
/// whatever [child] paints: the scrim, with [child], the loading or the
/// failure builder's content, centred on it. The timed grid's overlay acts
/// the same.
class _MonthLoadOverlay extends StatelessWidget {
  const _MonthLoadOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final styles = _MonthStyles.of(context);
    // A ColoredBox hit-tests as opaque, so no press reaches the board.
    return ColoredBox(
      color: styles.scrim,
      child: Center(child: child),
    );
  }
}
