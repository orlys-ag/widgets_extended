/// The calendar's Month mode: the selected day's month on the board, one
/// row per week and one column per shown weekday, each item a one-lane
/// chip on the days it covers in each calendar week.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../board/board.dart';
import '../dates/calendar_dates.dart';
import '../dates/calendar_labels.dart';
import '../entries/calendar_entry.dart';
import '../presentation/calendar_builders.dart';
import '../presentation/calendar_defaults.dart';
import '../presentation/calendar_theme.dart';
import '../store/calendar_store.dart';
import 'day_cell.dart';
import 'pinch_zoom.dart';

/// The height of a day's number strip, which the weeks' lanes start
/// below: the row axis's lane padding.
const double monthStripHeight = 28.0;

/// The height of one chip lane: the row axis's lane extent while the days
/// show chips.
const double monthLaneExtent = 18.0;

/// The height of one card lane: the row axis's lane extent while the days
/// show cards ([monthShowsCards]).
const double monthCardExtent = 36.0;

/// The height of a day's banner counting its items wholly before the
/// calendar's hours, under its number strip, and of the one counting those
/// wholly after them, under its last chip.
const double monthHoursBannerExtent = 18.0;

/// The least width of a day that shows its items as cards.
const double monthCardMinWidth = 100.0;

/// The least height a week must rest at for its days to show their items
/// as cards: the number strip and three card lanes.
const double monthCardMinHeight = monthStripHeight + 3 * monthCardExtent;

/// Whether days [width] wide, in weeks resting at [extent], show their
/// items as cards, one [monthCardExtent] lane tall, which the chip builder
/// draws in its card form, rather than as chips one [monthLaneExtent] lane
/// tall: when both reach [monthCardMinWidth] and [monthCardMinHeight].
bool monthShowsCards(double width, double extent) {
  return width >= monthCardMinWidth && extent >= monthCardMinHeight;
}

/// The height a week of the month board rests at: [height] shared by
/// [weekCount] weeks and times [scale], floored to a multiple of 1/64 so
/// at a [scale] of 1 the weeks never add up past [height], and never less
/// than the strip and one lane. A non-finite [height] gives that least.
double fittedWeekExtent(double height, int weekCount, {double scale = 1.0}) {
  assert(scale >= 1.0);
  const least = monthStripHeight + monthLaneExtent;
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
        borderRadius: BorderRadius.circular(11.0),
      ),
      ring = BoxDecoration(
        border: Border.all(color: theme.todayRing, width: theme.todayRingWidth),
        borderRadius: BorderRadius.circular(11.0),
      ),
      more = BoxDecoration(
        color: theme.notice,
        borderRadius: BorderRadius.circular(4.0),
      ),
      moreLabel = theme.monthMoreStyle.copyWith(color: theme.onNotice),
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

  /// A day's "+N more".
  final BoxDecoration more;
  final TextStyle moreLabel;

  /// The scrim over the board while its days are not ready.
  final Color scrim;
}

/// The key of the item [id]'s bar in the calendar week starting on
/// [weekStart]: `"<id>@<yyyy-mm-dd>"`.
String monthSegmentKey(String id, DateTime weekStart) {
  return "$id@${isoDate(weekStart)}";
}

/// The key of the chip of the bar [segmentKey] names.
ValueKey<String> monthChipKey(String segmentKey) {
  return ValueKey<String>("month-chip-$segmentKey");
}

/// The key of the month board's cell showing [day].
ValueKey<String> monthDayKey(DateTime day) {
  return ValueKey<String>("month-day-${isoDate(day)}");
}

/// The key of the number strip of the cell showing [day].
ValueKey<String> monthStripKey(DateTime day) {
  return ValueKey<String>("month-strip-${isoDate(day)}");
}

/// The key of the banner saying how many chips the cell showing [day]
/// hides.
ValueKey<String> monthMoreKey(DateTime day) {
  return ValueKey<String>("month-more-${isoDate(day)}");
}

/// The key of the banner counting the items of the cell showing [day]
/// that lie wholly before the calendar's hours.
ValueKey<String> monthEarlierKey(DateTime day) {
  return ValueKey<String>("month-earlier-${isoDate(day)}");
}

/// The key of the banner counting the items of the cell showing [day]
/// that lie wholly after the calendar's hours.
ValueKey<String> monthLaterKey(DateTime day) {
  return ValueKey<String>("month-later-${isoDate(day)}");
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
/// per week of the grid whose shown days the item covers, on that week's
/// row and on the columns from the first shown day on or after the item's
/// first day to the last shown day on or before its last. A week whose
/// shown days the item misses has none, which is the clipping
/// `gridSpanOf` applies to the timed grid's columns.
List<BoardPlacement<MonthChip<T>>> monthPlacementsOf<T>(
  Iterable<CalendarShownEntry<T>> shown,
  MonthGrid grid,
) {
  final weeks = grid.weekCount;
  final columns = grid.columnCount;
  // The dayNumber of each cell, read once per call.
  final days = Int32List(weeks * columns);
  for (var row = 0; row < weeks; row++) {
    for (var col = 0; col < columns; col++) {
      days[row * columns + col] = dayNumber(grid.dateAt(row, col));
    }
  }
  final placements = <BoardPlacement<MonthChip<T>>>[];
  for (final entry in shown) {
    final item = entry.entry;
    final first = dayNumber(item.day);
    final last = first + item.dayCount - 1;
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
            key: monthSegmentKey(entry.id, dateOfDayNumber(weekFirst)),
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
/// `row * columnCount + col`. An item with no minute inside the hours has
/// no chip, and counts on each shown day of the grid it covers, in
/// `earlier` when it starts before the hours and in `later` otherwise,
/// as Agenda's `dayListRowsOf` counts it; every other item is `inside`.
({List<CalendarShownEntry<T>> inside, Int32List earlier, Int32List later})
splitMonthHours<T>(
  Iterable<CalendarShownEntry<T>> shown,
  MonthGrid grid,
  DayHours hours,
) {
  final inside = <CalendarShownEntry<T>>[];
  final before = <CalendarShownEntry<T>>[];
  final after = <CalendarShownEntry<T>>[];
  for (final entry in shown) {
    final item = entry.entry;
    if (math.min(item.endMinute, hours.end) >
        math.max(item.startMinute, hours.start)) {
      inside.add(entry);
    } else if (item.startMinute < hours.start) {
      before.add(entry);
    } else {
      after.add(entry);
    }
  }
  final columns = grid.columnCount;
  Int32List countsOf(List<CalendarShownEntry<T>> outside) {
    final counts = Int32List(grid.weekCount * columns);
    // A placement covers the shown days of its week the item covers.
    for (final placement in monthPlacementsOf(outside, grid)) {
      final span = placement.span;
      final first = span.rowStart * columns + span.colStart;
      for (var cell = first; cell < first + span.colSpan; cell++) {
        counts[cell]++;
      }
    }
    return counts;
  }

  return (inside: inside, earlier: countsOf(before), later: countsOf(after));
}

/// The month board's lane order among bars whose columns in a week are
/// the same: the item that starts on an earlier day first, then the one
/// covering more days, then the earlier start time, the title and the id.
/// The board orders bars by their first and their last column before it,
/// so a week's chips stack by the day each starts in the week, the longer
/// first, and a bar continuing from the week before stacks above a chip
/// starting on its first shown day.
int compareMonthChips<T>(MonthChip<T> a, MonthChip<T> b) {
  final x = a.entry.entry;
  final y = b.entry.entry;
  // `day` is the first day at local midnight, so this compares days and
  // allocates nothing.
  final byDay = x.day.compareTo(y.day);
  if (byDay != 0) {
    return byDay;
  }
  final byLength = y.dayCount.compareTo(x.dayCount);
  if (byLength != 0) {
    return byLength;
  }
  final byStart = x.startMinute.compareTo(y.startMinute);
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
  MonthGrid grid,
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
  MonthGrid grid,
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
  MonthGrid grid,
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
enum MonthLayout {
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
/// with it. The weeks share the board's height, each resting at
/// [weekScale] times its share: past 1, the board scrolls down. The board
/// opens scrolled to show the selected day, and does again for a new
/// month, a new [minDayWidth] and a new [weekScale].
///
/// Under [MonthLayout.showAll] the weeks grow past their resting height to
/// hold their chips, and the board then scrolls; under
/// [MonthLayout.fitScreen] each holds the lanes that fit at its resting
/// height ([monthLanesThatFit]), [fitMonthPlacements] chooses the chips it
/// shows, and a day that hides some says "+N more" on a soft yellow banner
/// in its last lane. An item with no minute inside [hours] has no chip
/// ([splitMonthHours]): each day it covers counts it on a soft yellow
/// banner, "+N earlier" under the day's number strip for those before the
/// hours and "+N later" for those after them in the lane under the day's
/// last chip, or under its "+N more", naming the hours in
/// [hourLabelFormat] to a screen reader. While any day of the grid counts
/// one before the hours, every week's lanes start under that banner's
/// band; a week grows to hold each day's banner after the hours, and
/// while any day counts one, under [MonthLayout.fitScreen] a week holds
/// the lanes that fit beside both bands. Each day shows its number in a strip across its top,
/// today's in the primary colour inside the today ring and the selected
/// day's on the primary pill, in the [CalendarTheme] above the board. Each
/// item shows as one bar per calendar week it covers, whose content is what
/// [chipBuilder] draws, told whether the item continues into the week
/// before or after: a chip one lane tall, or, in days large enough
/// ([monthShowsCards]), a card two chips tall, the builder told it draws a
/// card. A pending item's bar takes no tap, and the board names each bar to
/// a screen reader, its kind as [entryKindOf] answers it. Lines part the
/// weeks and the days, and each day of another month lies on the
/// background colour.
///
/// A tap on a chip reports [onOpenItem], a tap anywhere else on a day
/// [onOpenDay], and a long press on a day outside its chips
/// [onCreateOnDay], or where there is none [onOpenDay] as a tap does; the
/// last two give the board the keyboard, whose arrow
/// keys move the selected day and report it through [onSelectDay]. While
/// the days are not ready a cover over the board takes every press,
/// centring what [loadingBuilder] draws while they are read, and what
/// [failureBuilder] draws when the read failed. A change of the
/// store animates over the theme's motion; a new month or a new set of
/// weekdays does not, and
/// settles at once whatever chip was still growing in or shrinking out. A
/// new size alone refits the weeks at once and leaves the chips' motion
/// running, unless it turns chips into cards or back, or under
/// [MonthLayout.fitScreen] changes the lanes a week holds, which settles
/// them as a new month does. New [hours] settle the chips as a new month
/// does.
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
    this.layout = MonthLayout.showAll,
    this.minDayWidth = minDayWidthLow,
    this.weekScale = 1.0,
    this.hours = DayHours.allDay,
    this.hourLabelFormat = HourLabelFormat.twentyFourHour,
    required this.selectedDay,
    required this.today,
    required this.onSelectDay,
    required this.onOpenDay,
    required this.onCreateOnDay,
    required this.onOpenItem,
    this.onZoom,
    this.chipBuilder,
    this.loadingBuilder,
    this.failureBuilder,
    this.entryKindOf,
  });

  final CalendarStore<T> store;

  /// The month the board shows.
  final MonthGrid grid;

  /// Whether a week grows to hold its chips or keeps its share of the
  /// height and hides the chips that do not fit.
  final MonthLayout layout;

  /// The least width of a day, in logical pixels.
  final double minDayWidth;

  /// How many times its share of the board's height a week rests at, at
  /// least 1.
  final double weekScale;

  /// The hours the calendar shows: an item with no minute inside them has
  /// no chip, and its days count it on their banners.
  final DayHours hours;

  /// The format the days' banners name [hours] in to a screen reader.
  final HourLabelFormat hourLabelFormat;

  /// A shown day of [grid]'s month.
  final DateTime selectedDay;

  /// The day marked as today.
  final ValueListenable<DateTime> today;

  /// A key moved the selection onto this day.
  final ValueChanged<DateTime> onSelectDay;

  /// This day was tapped outside its chips.
  final ValueChanged<DateTime> onOpenDay;

  /// This day was long-pressed outside its chips. Null where a long press
  /// creates nothing, as out of edit mode, and opens the day as a tap
  /// does.
  final ValueChanged<DateTime>? onCreateOnDay;

  /// The chip of this item, which is not pending, was tapped.
  final ValueChanged<String> onOpenItem;

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
typedef _BannerHours = ({DayHours hours, HourLabelFormat format});

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

  /// [MonthBoard.today], which the kept day cells listen to, so a new
  /// listenable reaches the cells this state keeps.
  late final ValueNotifier<DateTime> _today = ValueNotifier<DateTime>(
    widget.today.value,
  );

  /// Whether [MonthBoard.onCreateOnDay] is given, which the kept day cells
  /// listen to, so a long press on them creates only while it is.
  late final ValueNotifier<bool> _creates = ValueNotifier<bool>(
    widget.onCreateOnDay != null,
  );

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
  /// lanes and the column width the axes were last given; null and zero
  /// before the first layout.
  MonthGrid? _fittedGrid;
  MonthLayout? _fittedLayout;
  DayHours? _fittedHours;
  double _fitted = 0.0;
  double _fittedPadding = 0.0;
  double _columnWidth = 0.0;

  /// Whether the last sync found a day of the grid counting an item before
  /// the hours, and one counting an item after them, which decide the
  /// bands above and below the lanes.
  bool _earlierBand = false;
  bool _laterBand = false;

  /// Whether the axes were last given card lanes ([monthShowsCards]), and
  /// the bars are cards.
  bool _cards = false;

  /// The lanes a week held at the last sync, under
  /// [MonthLayout.fitScreen]; null under [MonthLayout.showAll], where the
  /// weeks grow.
  int? _syncedLanes;

  /// Whether the next layout sets the board's items: set at the start, by
  /// the store and by a new grid.
  bool _syncPending = true;

  /// Whether the last sync found its days ready.
  bool _syncedReady = false;

  /// Whether a layout still owes a reveal of the selected day: set at the
  /// start, by a new grid and by a new [MonthBoard.minDayWidth] or
  /// [MonthBoard.weekScale], cleared by the first layout after it that
  /// finds the days ready.
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
    widget.today.addListener(_handleToday);
    _pinch.holding.addListener(_handleHolding);
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
        widget.entryKindOf != oldWidget.entryKindOf) {
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
    if (widget.today != oldWidget.today) {
      oldWidget.today.removeListener(_handleToday);
      widget.today.addListener(_handleToday);
      _today.value = widget.today.value;
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
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStore);
    widget.today.removeListener(_handleToday);
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
    _bannerHours.dispose();
    for (final hidden in _hidden) {
      hidden.dispose();
    }
    super.dispose();
  }

  static List<_KeptDay?> _emptyDays(MonthGrid grid) {
    return List<_KeptDay?>.filled(grid.weekCount * grid.columnCount, null);
  }

  static bool _sameGrid(MonthGrid a, MonthGrid b) {
    return a.year == b.year && a.month == b.month && a.weekdays == b.weekdays;
  }

  /// [weekCount] weeks resting at [fitted], each growing past it to the
  /// [padding] above its lanes plus its lanes, each [laneExtent] tall.
  static BoardAxisConfig _rowsConfig(
    MonthGrid grid,
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

  void _handleStore() {
    setState(() {
      _syncPending = true;
    });
  }

  void _handleToday() {
    _today.value = widget.today.value;
  }

  /// Whether the store shows exactly this grid's days, every one of them
  /// read. False for a build between the calendar taking a new month and
  /// the store showing it.
  bool get _daysReady {
    final store = widget.store;
    final grid = widget.grid;
    return store.status == CalendarLoadStatus.ready &&
        store.isShown(grid.firstDay, grid.lastDay);
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

  /// A key moved the board's selection: reports the day of its focus cell
  /// when the cell lies in the grid. Two keys before a frame both report,
  /// the second stepping from the cell the first selected.
  void _handleBoardSelection(BoardSelection selection) {
    if (_writingSelection) {
      return;
    }
    final focus = selection.focus;
    final grid = widget.grid;
    if (focus == null ||
        focus.row >= grid.weekCount ||
        focus.col >= grid.columnCount) {
      return;
    }
    widget.onSelectDay(grid.dateAt(focus.row, focus.col));
  }

  void _openDay(DateTime day) {
    if (_pinch.pinched.value) {
      return;
    }
    _focusNode.requestFocus();
    widget.onOpenDay(day);
  }

  void _createOnDay(DateTime day) {
    final create = widget.onCreateOnDay;
    if (create == null || _pinch.pinched.value) {
      return;
    }
    _focusNode.requestFocus();
    create(day);
  }

  void _openItem(String id) {
    if (!_pinch.pinched.value) {
      widget.onOpenItem(id);
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
  /// or the lanes a week holds under [MonthLayout.fitScreen] changed, the
  /// bars of the items the store shows on the grid's days inside the hours
  /// ([splitMonthHours]), none while they are not ready, all in one batch
  /// and so one structural notification; the sync also tells each day what
  /// it hides ([_writeHidden]). A sync the store, the grid or the hours owe
  /// reads the store before the axes, since the banners it counts decide
  /// the room above and below the lanes. Called from the layout callback,
  /// so the first frame lays the board out at its size.
  ///
  /// A sync animates only when it follows the store alone, its days are
  /// ready and the last sync's were. Any other sync runs under
  /// [BoardAnimationStyle.disabled], which [_scheduleStyleRestore] lifts,
  /// and settles in its batch every enter and exit in flight
  /// ([_setItemsSettled]). A refit alone leaves the style as it is, so the
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
    );
    final width = size.width.isFinite && size.width > 0.0
        ? math.max(widget.minDayWidth, size.width / grid.columnCount)
        : _columnWidth;
    final cards = monthShowsCards(width, fitted);
    final laneExtent = cards ? monthCardExtent : monthLaneExtent;
    final ready = _daysReady;
    var split = _syncPending ? _splitShown(grid, hours, ready) : null;
    if (split != null) {
      _earlierBand = split.earlier.any(_isCounted);
      _laterBand = split.later.any(_isCounted);
    }
    final padding =
        monthStripHeight + (_earlierBand ? monthHoursBannerExtent : 0.0);
    final lanes = layout == MonthLayout.fitScreen
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
        cards != _cards;
    final columnsChanged =
        width > 0.0 &&
        (width != _columnWidth ||
            _board.columns.axis.trackCount != grid.columnCount);
    final sync = _syncPending || lanes != _syncedLanes || cards != _cards;
    if (!rowsChanged && !columnsChanged && !sync) {
      return;
    }
    List<BoardPlacement<MonthChip<T>>>? placements;
    Int32List? hidden;
    if (sync) {
      split ??= _splitShown(grid, hours, ready);
    }
    if (sync && !ready) {
      placements = <BoardPlacement<MonthChip<T>>>[];
    } else if (sync) {
      final all = monthPlacementsOf(split!.inside, grid);
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
        _setItemsSettled(placements, next);
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
    if (cards != _cards) {
      // The build that follows hands the board the other builder, which
      // asks for every bar again.
      _chips.clear();
      _cards = cards;
    }
    if (columnsChanged) {
      _columnWidth = width;
    }
    // Owed by a new grid, which syncs, or a new least day width, which may
    // only refit the columns.
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
      split!,
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
  /// ([splitMonthHours]); none, and no day counting any, while they are not
  /// [ready].
  ({List<CalendarShownEntry<T>> inside, Int32List earlier, Int32List later})
  _splitShown(MonthGrid grid, DayHours hours, bool ready) {
    if (!ready) {
      final cells = grid.weekCount * grid.columnCount;
      return (
        inside: <CalendarShownEntry<T>>[],
        earlier: Int32List(cells),
        later: Int32List(cells),
      );
    }
    return splitMonthHours(
      widget.store.entriesBetween(grid.firstDay, grid.lastDay),
      grid,
      hours,
    );
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
    MonthGrid grid,
    Int32List? hidden,
    int? lanes,
    double laneExtent,
    double padding,
    ({List<CalendarShownEntry<T>> inside, Int32List earlier, Int32List later})
    split,
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
  void _setItemsSettled(
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
  /// left nothing in flight ([_setItemsSettled]), so a sync the next frame
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
  /// is still the grid. The first reveal of a new grid can read a week at
  /// its estimate, and the layout it causes measures that week, so a
  /// reveal that moved asks once more after it.
  void _revealSelected(MonthGrid scheduledFor, {required bool again}) {
    if (!mounted ||
        !_sameGrid(widget.grid, scheduledFor) ||
        !_scroll.hasClients) {
      return;
    }
    final before = _scroll.position.pixels;
    final cell = widget.grid.cellOf(widget.selectedDay);
    _board.revealCell(cell.row, cell.col);
    if (again && _scroll.position.pixels != before) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _revealSelected(scheduledFor, again: false);
      });
    }
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
        builder: _barBuilder,
        kindOf: widget.entryKindOf,
        onOpen: _openItem,
      ),
    );
    _chips[chip.key] = (chip: chip, widget: built);
    return built;
  }

  /// The cover's content: what the failure builder draws for the grid's
  /// days when the read the store waits on failed, with the store's load
  /// error as it holds it, and what the loading builder draws otherwise.
  Widget _buildCover(BuildContext context, CalendarStore<T> store) {
    final grid = widget.grid;
    if (store.status == CalendarLoadStatus.failed) {
      final failure = widget.failureBuilder ?? defaultCalendarFailureBuilder;
      return failure(
        context,
        CalendarFailureState(
          site: CalendarStateSite.cover,
          first: grid.firstDay,
          last: grid.lastDay,
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
        first: grid.firstDay,
        last: grid.lastDay,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // The board takes the height under the letters, whose columns the
        // layout sizes first.
        _layoutBoard(
          Size(size.width, math.max(0.0, size.height - weekdayHeaderHeight)),
        );
        final store = widget.store;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WeekdayHeader(
              weekdays: widget.grid.weekdays,
              columnWidth: _columnWidth,
              horizontal: _horizontal,
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: Listener(
                      key: _boardAreaKey,
                      onPointerDown: _pinch.handleEvent,
                      onPointerMove: _pinch.handleEvent,
                      onPointerUp: _pinch.handleEvent,
                      onPointerCancel: _pinch.handleEvent,
                      child: Board<String, MonthChip<T>>(
                        controller: _board,
                        cellBuilder: _cellBuilder,
                        itemBuilder: _cards ? _cardBuilder : _chipBuilder,
                        background: _background,
                        selection: _selectionConfig,
                        focusNode: _focusNode,
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
                            return _buildCover(context, store);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
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

  final MonthGrid grid;
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

/// "Tuesday, April 21": [day] as the month board names it to a screen
/// reader.
String _dayLabel(DateTime day) {
  return "${weekdayNames[weekdayColumn(day)]}, "
      "${monthNames[day.month - 1]} ${day.day}";
}

/// What a screen reader says for [entry]'s chip: its title, the [kind]
/// where there is one, its days and times, and that it is pending while it
/// is.
String _chipLabel<T>(CalendarShownEntry<T> entry, String? kind) {
  final item = entry.entry;
  final times =
      "${clockLabel(item.startMinute)} to ${clockLabel(item.endMinute)}";
  final String when;
  if (item.dayCount == 1) {
    when = "${_dayLabel(item.day)}, $times";
  } else {
    final last = addDays(item.day, item.dayCount - 1);
    when = "${_dayLabel(item.day)} to ${_dayLabel(last)}, $times each day";
  }
  final label = kind == null
      ? "${item.title}, $when"
      : "${item.title}, $kind, $when";
  return entry.pending ? "$label, pending" : label;
}

/// "1 more item" or "N more items", for a screen reader.
String _hiddenLabel(int count) {
  return count == 1 ? "1 more item" : "$count more items";
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
  final ValueChanged<DateTime> onOpen;
  final ValueChanged<DateTime> onCreate;

  @override
  Widget build(BuildContext context) {
    final label = _dayLabel(day);
    final styles = _MonthStyles.of(context);
    void open() {
      onOpen(day);
    }

    void createOn() {
      onCreate(day);
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
            if (isToday) "today",
            if (hides.earlier > 0)
              "${moreItemsLabel(hides.earlier)} before "
                  "${hourLabel(hours.hours.start, hours.format)}",
            if (hides.count > 0) _hiddenLabel(hides.count),
            if (hides.later > 0)
              "${moreItemsLabel(hides.later)} after "
                  "${hourLabel(hours.hours.end, hours.format)}",
          ].join(", "),
          hint: "Opens the day",
          onTap: open,
          onLongPress: create,
          onLongPressHint: create == null ? null : "create an item",
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
                SizedBox(height: hides.extent),
                SizedBox(
                  key: monthStripKey(day),
                  height: monthStripHeight,
                  child: Center(child: _buildNumber(isToday, styles)),
                ),
                if (hides.earlier > 0)
                  Positioned(
                    left: 0.0,
                    right: 0.0,
                    top: monthStripHeight,
                    height: monthHoursBannerExtent,
                    child: _buildBanner(
                      monthEarlierKey(day),
                      "+${hides.earlier} earlier",
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
                      "+${hides.count} more",
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
                      "+${hides.later} later",
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

  Widget _buildNumber(bool isToday, _MonthStyles styles) {
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
    final number = Text("${day.day}", style: style);
    if (!isSelected && !isToday) {
      return number;
    }
    return Container(
      width: 30.0,
      height: 22.0,
      alignment: Alignment.center,
      decoration: isSelected ? styles.selectedPill : null,
      foregroundDecoration: isToday ? styles.ring : null,
      child: number,
    );
  }
}

/// One item's bar in one week: a lane-tall box over its lane band's top,
/// holding, inside a 1 px inset and at its lane's height while the board
/// grows or shrinks the band, what [builder] draws for the chip: a chip one
/// [monthLaneExtent] lane tall, or a [card] one [monthCardExtent] lane
/// tall. The box is one semantics node of the chip's label, the kind
/// [kindOf] answers, and its tap, and takes a tap anywhere in it, which
/// does nothing while the chip is pending.
class _MonthChipBox<T> extends StatelessWidget {
  const _MonthChipBox({
    super.key,
    required this.chip,
    required this.card,
    required this.builder,
    required this.kindOf,
    required this.onOpen,
  });

  final MonthChip<T> chip;
  final bool card;
  final CalendarChipBuilder<T> builder;
  final String? Function(CalendarEntry<T> entry)? kindOf;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final entry = chip.entry;
    final pending = entry.pending;
    final extent = card ? monthCardExtent : monthLaneExtent;
    void open() {
      onOpen(entry.id);
    }

    return Semantics(
      container: true,
      button: !pending,
      label: _chipLabel(entry, kindOf?.call(entry.entry)),
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
            padding: const EdgeInsets.all(1.0),
            // The bar keeps its height while the board grows or shrinks
            // the chip's band, and is clipped to it.
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minHeight: extent - 2.0,
                maxHeight: extent - 2.0,
                child: _ChipContent<T>(
                  entry: entry,
                  details: CalendarChipDetails(
                    card: card,
                    continuesBefore: chip.continuesBefore,
                    continuesAfter: chip.continuesAfter,
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
