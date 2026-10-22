/// Agenda's list: the shown days one after another, each a header that
/// sticks at the list's top while its block scrolls under it: the day's
/// items beside their start times and lengths, a yellow banner counting
/// those wholly before the calendar's hours and one counting those wholly
/// after them, in edit mode a dashed row for each gap in the hours that no
/// item covers, with a button that adds an item there, and on the clock's
/// day a marker of the current time.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../sliver_tree/sliver_tree.dart';
import '../dates/calendar_dates.dart';
import '../dates/calendar_labels.dart';
import '../policy/history_lock.dart';
import '../presentation/calendar_builders.dart';
import '../presentation/calendar_defaults.dart';
import '../presentation/calendar_theme.dart';
import '../store/calendar_store.dart';

/// The style the day list animates its rows with under [theme]: every
/// family over its [CalendarThemeData.motionDuration] on its
/// [CalendarThemeData.motionCurve], and every family off at a zero
/// duration. The one site that declares the day list's motion.
TreeAnimationStyle dayListAnimationStyleOf(CalendarThemeData theme) {
  return TreeAnimationStyle.uniform(
    duration: theme.motionDuration,
    curve: theme.motionCurve,
  );
}

/// What [DayList] and the rows it builds draw and run with, made from one
/// [CalendarThemeData] by [forTheme] and never changed.
@immutable
class _ListStyles {
  _ListStyles._(this.theme)
    : treeStyle = dayListAnimationStyleOf(theme),
      time = theme.agendaTimeStyle.copyWith(color: theme.textSecondary),
      gapTime = theme.agendaTimeStyle.copyWith(color: theme.textMuted),
      title = theme.agendaHeaderTitleStyle.copyWith(color: theme.text),
      emptyTitle = theme.agendaHeaderEmptyTitleStyle.copyWith(
        color: theme.textMuted,
      ),
      count = theme.agendaHeaderCountStyle.copyWith(color: theme.textSecondary),
      emptyCount = theme.agendaHeaderEmptyCountStyle.copyWith(
        color: theme.textMuted,
      ),
      durationLabel = theme.badgeStyle.copyWith(color: theme.primary),
      durationChip = BoxDecoration(
        color: theme.primaryTint,
        borderRadius: BorderRadius.circular(10.0),
      ),
      durationIcon = Icon(theme.durationIcon, size: 12.0, color: theme.primary),
      banner = BoxDecoration(
        color: theme.notice,
        border: Border.all(color: theme.noticeOutline),
        borderRadius: BorderRadius.circular(8.0),
      ),
      bannerLabel = theme.noticeStyle.copyWith(color: theme.onNotice),
      beforeIcon = Icon(
        theme.beforeHoursIcon,
        size: 16.0,
        color: theme.onNotice,
      ),
      afterIcon = Icon(theme.afterHoursIcon, size: 16.0, color: theme.onNotice),
      dashedLine = Expanded(
        child: CustomPaint(
          painter: _DashedLinePainter(
            Paint()
              ..color = theme.outline
              ..strokeWidth = 1.0,
          ),
          child: const SizedBox.expand(),
        ),
      ),
      nowPill = BoxDecoration(
        color: theme.error,
        borderRadius: BorderRadius.circular(8.0),
      ),
      nowLabel = theme.badgeStyle.copyWith(color: theme.onPrimary),
      nowLine = Expanded(
        child: SizedBox(
          height: 2.0 * _NowLinePainter.dotRadius,
          child: CustomPaint(
            painter: _NowLinePainter(
              Paint()
                ..color = theme.error
                ..strokeWidth = 2.0,
            ),
          ),
        ),
      );

  /// The styles of [theme]: those made for it before, or for a theme `==`
  /// to it last, so an equal theme makes none.
  static _ListStyles forTheme(CalendarThemeData theme) {
    final kept = _memo[theme];
    if (kept != null) {
      return kept;
    }
    final last = _last;
    final styles = last != null && last.theme == theme
        ? last
        : _ListStyles._(theme);
    _memo[theme] = styles;
    _last = styles;
    return styles;
  }

  /// The styles of the theme above [context], which [context] then depends
  /// on.
  static _ListStyles of(BuildContext context) {
    return forTheme(CalendarTheme.of(context));
  }

  static Expando<_ListStyles> _memo = Expando<_ListStyles>();
  static _ListStyles? _last;

  /// Drops the styles made so far, which keep the code that made them
  /// across a hot reload, so the next read makes them again.
  static void _reset() {
    _memo = Expando<_ListStyles>();
    _last = null;
  }

  final CalendarThemeData theme;

  /// [dayListAnimationStyleOf] [theme].
  final TreeAnimationStyle treeStyle;

  /// An item's start, and a gap's.
  final TextStyle time;
  final TextStyle gapTime;

  /// A header's title and count, and an empty day's.
  final TextStyle title;
  final TextStyle emptyTitle;
  final TextStyle count;
  final TextStyle emptyCount;

  /// The chip of an item's length.
  final TextStyle durationLabel;
  final BoxDecoration durationChip;
  final Widget durationIcon;

  /// A banner of the items outside the hours.
  final BoxDecoration banner;
  final TextStyle bannerLabel;
  final Widget beforeIcon;
  final Widget afterIcon;

  /// The dashed line of a gap row.
  final Widget dashedLine;

  /// The marker of the current time.
  final BoxDecoration nowPill;
  final TextStyle nowLabel;
  final Widget nowLine;
}

/// The room between the list's sides and its rows' content.
const double dayListGutter = 16.0;

/// The width of the column of times left of the cards and the dashed
/// lines, whose times end [dayListTimeGap] short of them.
const double dayListTimeWidth = 64.0;

/// The room between the end of the times, which the time column aligns
/// right, and the cards or the dashed lines.
const double dayListTimeGap = 8.0;

/// The width and height of the square a gap row gives its add button.
const double dayListAddButtonSize = 24.0;

/// The key of the slot that holds the card of the item [id].
ValueKey<String> itemCardKey(String id) {
  return ValueKey<String>("card-$id");
}

/// The days the list holds on either side of the day it was built or last
/// centred on.
const int dayListWindowDays = 180;

/// How near the top day may come to either end of the list's days before
/// the list grows, or re-centres, there.
const int _edgeDays = 30;

/// The key of the start time and length beside the card of the item [id].
ValueKey<String> dayListTimeKey(String id) {
  return ValueKey<String>("day-list-time-$id");
}

/// The key of the header of [day].
ValueKey<String> dayListHeaderKey(DateTime day) {
  return ValueKey<String>("day-list-header-${isoDate(day)}");
}

/// The key of [day]'s dashed row of the gap that starts [start] minutes
/// after midnight.
ValueKey<String> dayListGapKey(DateTime day, int start) {
  return ValueKey<String>("day-list-gap-$start@${isoDate(day)}");
}

/// The key of the chip naming the length of the item [id], under its
/// start time.
ValueKey<String> dayListDurationKey(String id) {
  return ValueKey<String>("day-list-duration-$id");
}

/// The key of [day]'s banner counting its items wholly before the hours,
/// or wholly after them when [above] is false.
ValueKey<String> dayListHiddenKey(DateTime day, {required bool above}) {
  final side = above ? "above" : "below";
  return ValueKey<String>("day-list-hidden-$side-${isoDate(day)}");
}

/// The key of the marker of the current time.
const ValueKey<String> dayListNowKey = ValueKey<String>("day-list-now");

/// The key of the row showing [day] is being read.
ValueKey<String> dayListLoadingKey(DateTime day) {
  return ValueKey<String>("day-list-loading-${isoDate(day)}");
}

/// The key of the row saying [day] could not be read.
ValueKey<String> dayListFailedKey(DateTime day) {
  return ValueKey<String>("day-list-failed-${isoDate(day)}");
}

/// One row of the day list, under or as the header of its [day].
@immutable
sealed class DayListRow {
  const DayListRow(this.day);

  final DateTime day;

  /// The row's key in the list, unique across its days.
  String get key;
}

/// The header of [day]: a root of the list, whose one child is the day's
/// [DayListBody].
final class DayListHeader extends DayListRow {
  const DayListHeader(super.day, {required this.count});

  /// How many items [day] shows, or null while it is not read.
  final int? count;

  @override
  String get key {
    return headerKeyOf(day);
  }

  /// The [key] of [day]'s header.
  static String headerKeyOf(DateTime day) {
    return "day-${isoDate(day)}";
  }

  @override
  bool operator ==(Object other) {
    return other is DayListHeader && other.day == day && other.count == count;
  }

  @override
  int get hashCode {
    return Object.hash(day, count);
  }

  @override
  String toString() {
    return "DayListHeader(${isoDate(day)}, $count)";
  }
}

/// The block under [day]'s header, which holds the day's [rows]. One row
/// per day, so a change to the day changes this row's height and nothing
/// of the tree's structure, and the tree keeps a row above its viewport
/// that changes height from moving the rows it shows.
final class DayListBody extends DayListRow {
  const DayListBody(super.day, {required this.rows});

  /// The day's rows: [dayListRowsOf] its items, or one [DayListLoading] or
  /// [DayListFailed].
  final List<DayListRow> rows;

  @override
  String get key {
    return "body-${isoDate(day)}";
  }

  @override
  bool operator ==(Object other) {
    return other is DayListBody &&
        other.day == day &&
        listEquals(other.rows, rows);
  }

  @override
  int get hashCode {
    return Object.hash(day, Object.hashAll(rows));
  }

  @override
  String toString() {
    return "DayListBody(${isoDate(day)}, $rows)";
  }
}

/// The row of the item [entry] on [day].
final class DayListItem<T> extends DayListRow {
  const DayListItem(super.day, this.entry);

  final CalendarShownEntry<T> entry;

  @override
  String get key {
    return "item-${entry.id}@${isoDate(day)}";
  }

  @override
  bool operator ==(Object other) {
    return other is DayListItem<T> && other.day == day && other.entry == entry;
  }

  @override
  int get hashCode {
    return Object.hash(day, entry);
  }

  @override
  String toString() {
    return "DayListItem(${isoDate(day)}, $entry)";
  }
}

/// [day]'s dashed row of a gap: the minutes from [start] to [end], inside
/// the calendar's hours, that no item covers.
final class DayListGap extends DayListRow {
  const DayListGap(super.day, this.start, this.end);

  final int start;

  /// The minute the gap ends: the next item's start, or the hours' end.
  final int end;

  @override
  String get key {
    return "gap-$start@${isoDate(day)}";
  }

  @override
  bool operator ==(Object other) {
    return other is DayListGap &&
        other.day == day &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode {
    return Object.hash(day, start, end);
  }

  @override
  String toString() {
    return "DayListGap(${isoDate(day)}, ${clockLabel(start)}-"
        "${clockLabel(end)})";
  }
}

/// [day]'s banner counting the [count] items that lie wholly before the
/// calendar's hours, or wholly after them when [above] is false.
final class DayListHidden extends DayListRow {
  const DayListHidden(super.day, this.count, {required this.above});

  final int count;
  final bool above;

  @override
  String get key {
    return "hidden-${above ? "above" : "below"}@${isoDate(day)}";
  }

  @override
  bool operator ==(Object other) {
    return other is DayListHidden &&
        other.day == day &&
        other.count == count &&
        other.above == above;
  }

  @override
  int get hashCode {
    return Object.hash(day, count, above);
  }

  @override
  String toString() {
    return "DayListHidden(${isoDate(day)}, $count, above: $above)";
  }
}

/// The row of a [day] being read.
final class DayListLoading extends DayListRow {
  const DayListLoading(super.day);

  @override
  String get key {
    return "loading-${isoDate(day)}";
  }

  @override
  bool operator ==(Object other) {
    return other is DayListLoading && other.day == day;
  }

  @override
  int get hashCode {
    return day.hashCode;
  }
}

/// The row of a [day] whose read failed.
final class DayListFailed extends DayListRow {
  const DayListFailed(super.day);

  @override
  String get key {
    return "failed-${isoDate(day)}";
  }

  @override
  bool operator ==(Object other) {
    return other is DayListFailed && other.day == day;
  }

  @override
  int get hashCode {
    return day.hashCode;
  }
}

/// The rows of [day]'s block for [entries], the day's items sorted by
/// start as [CalendarStore.entriesOn] sorts them. An item with no minute
/// inside [hours] has no row: a [DayListHidden] first counts those before
/// the hours, and one last those after them, as the timed grid counts the
/// items it has no block for. Each other item has its row, and where
/// [editable], one gap row for each run of minutes in [hours] that none of
/// them covers, an item covering the minutes from its start to before its
/// end, before the item that ends the run or after the last item. So items
/// that touch have no gap between them, and a day with no item inside the
/// hours has one gap row across them.
List<DayListRow> dayListRowsOf<T>(
  DateTime day,
  List<CalendarShownEntry<T>> entries,
  DayHours hours, {
  required bool editable,
}) {
  final rows = <DayListRow>[];
  var before = 0;
  var after = 0;
  // The latest end among the items so far, or the hours' start.
  var covered = hours.start;
  for (final entry in entries) {
    final item = entry.entry;
    if (math.min(item.endMinute, hours.end) <=
        math.max(item.startMinute, hours.start)) {
      if (item.startMinute < hours.start) {
        before++;
      } else {
        after++;
      }
      continue;
    }
    if (editable && item.startMinute > covered) {
      rows.add(DayListGap(day, covered, item.startMinute));
    }
    rows.add(DayListItem<T>(day, entry));
    covered = math.max(covered, item.endMinute);
  }
  if (editable && hours.end > covered) {
    rows.add(DayListGap(day, covered, hours.end));
  }
  return <DayListRow>[
    if (before > 0) DayListHidden(day, before, above: true),
    ...rows,
    if (after > 0) DayListHidden(day, after, above: false),
  ];
}

/// The days [weekdays] shows, from [dayListWindowDays] days before
/// [selectedDay] to as many after, on a [SyncedSliverTree] whose roots are
/// the days' headers, which stick at the list's top and count all the
/// day's items, each over one block ([DayListBody]) holding the day's rows
/// ([dayListRowsOf]): each card, which [cardBuilder] draws, right of its
/// start time over a chip of its length, both aligned right; for the items
/// wholly before [hours], a soft yellow banner above the cards that counts
/// them with an arrow pointing up, and for those wholly after, one below
/// the cards pointing down; and a dashed row for each gap in [hours] that
/// no item covers, an empty day's across the hours, with a button, which
/// [addButtonBuilder] draws and a screen reader hears as adding an item at
/// its time, that reports [onCreateIn]; what [loadingBuilder] draws while
/// the day is unread; and after a failed read, what [failureBuilder] draws,
/// with a retry that reads the shown days again. Times read in [format].
/// Unless [editable], the list has no dashed rows and hands the card
/// builder no Edit or Delete, so a day without items shows its header
/// alone. Under the history [lock] a card is handed Edit only while its
/// item is not [ItemHold.locked], and Delete only while it is
/// [ItemHold.free], and a dashed row's button adds from the first time the
/// lock leaves free in its gap, and is gone where the lock leaves none. A
/// row that comes or
/// goes in a block grows in and fades in, or fades out and shrinks away,
/// so the block grows or shrinks smoothly; a block above the list's top
/// that changes height moves nothing the list shows.
///
/// While [now] lies inside [hours], the block of its day marks it over its
/// rows, which keep their places: a red line from the cards to the list's
/// right edge, with a dot
/// at its start and the time at the end of a red pill across the time
/// column, from 8 px in from the list's left edge. It crosses
/// an item that started by [now] and has not ended at the share of the
/// card, between its strips, [calendarCardStripExtent] tall, that share of
/// the item has run, and otherwise lies in the gap
/// under the last row that starts by [now], or above the first row where
/// none does. A banner of the items before the hours starts before any
/// minute, and one of those after them after every minute.
///
/// The list opens with [selectedDay]'s header at its top, and a new
/// [selectedDay] scrolls there, animating, unless it is the day a scroll
/// of the list reported; one too far from the list's days re-centres the
/// list on it at once. While a drag or a fling scrolls it, the list
/// reports through [onTopDay] each new day under its top, and reads the
/// weeks of the days it holds built once it rests. A top day near the end of
/// the list's days adds as many again after them, and one near their start
/// re-centres the list on it.
///
/// Every state stays inside one always-scrollable scroll view, so a drag
/// on it reports the scroll an ancestor's listener reads.
///
/// A reveal predicts a row it scrolls past without building it: a card
/// as [cardExtentOf] answers, and a loading or a failed row at the
/// heights the list gives their builders.
///
/// The list draws and animates in the [CalendarTheme] above it; a card,
/// an add button, the loading and the failure state are what their
/// builders draw, the module's defaults where they are null.
class DayList<T> extends StatefulWidget {
  const DayList({
    super.key,
    required this.store,
    required this.weekdays,
    required this.format,
    required this.hours,
    required this.editable,
    required this.lock,
    required this.selectedDay,
    required this.today,
    required this.now,
    required this.onTopDay,
    required this.onCreateIn,
    required this.onEdit,
    required this.onDelete,
    this.cardBuilder,
    this.cardExtentOf,
    this.addButtonBuilder,
    this.loadingBuilder,
    this.failureBuilder,
  });

  final CalendarStore<T> store;

  /// The days the list shows.
  final WeekdaySet weekdays;

  /// How the times beside the cards and on the gap rows read, as
  /// [hourLabel] writes them.
  final HourLabelFormat format;

  /// The calendar's hours, which the gap rows cover; an item wholly
  /// outside them shows only in a banner's count.
  final DayHours hours;

  /// Whether the calendar is in edit mode, where the list has its dashed
  /// rows and hands each card its Edit and Delete.
  final bool editable;

  final HistoryLock lock;

  /// The day the list brings to its top; a shown day.
  final DateTime selectedDay;

  /// The day the headers name as today.
  final DateTime today;

  /// The current time, which its owner sets again at the start of each
  /// minute, and whose day's block marks it.
  final ValueListenable<DateTime> now;

  /// A drag or a fling brought a new day under the list's top.
  final ValueChanged<DateTime> onTopDay;

  /// The add button of a gap was pressed: an item in the gap's first slot
  /// the history lock leaves free.
  final void Function(DateTime day, int startMinute, int endMinute) onCreateIn;

  final void Function(String id) onEdit;
  final void Function(String id) onDelete;

  /// Draws each card inside the slot the list gives it, keyed
  /// [itemCardKey]; null for [defaultCalendarCardBuilder].
  final CalendarCardBuilder<T>? cardBuilder;

  /// The height of [cardBuilder]'s card of an entry, its strips left out,
  /// which a reveal predicts a card it does not build by; null for the
  /// default card's, [defaultCalendarCardExtent].
  final double Function(CalendarShownEntry<T> entry)? cardExtentOf;

  /// Draws a gap row's add button inside the [dayListAddButtonSize] square
  /// the list gives it; null for [defaultCalendarAddButtonBuilder].
  final CalendarAddButtonBuilder? addButtonBuilder;

  /// Draws an unread day's row, 24 tall; null for
  /// [defaultCalendarLoadingBuilder].
  final CalendarLoadingBuilder? loadingBuilder;

  /// Draws a failed day's row, at least 48 tall; null for
  /// [defaultCalendarFailureBuilder].
  final CalendarFailureBuilder? failureBuilder;

  @override
  State<DayList<T>> createState() {
    return _DayListState<T>();
  }
}

class _DayListState<T> extends State<DayList<T>> {
  /// How far below the list's top a row must reach to make its day the
  /// top day.
  static const double _probe = 1.0;

  /// What the rows draw with, the tree animates with and a reveal runs on.
  late _ListStyles _styles;

  /// The [dayNumber]s of the first and the last day the list holds.
  late int _first;
  late int _last;

  /// Counts the list's re-centrings, each of which builds a new scroll
  /// view and a new tree.
  int _generation = 0;

  late ScrollController _scroll;

  /// The tree's controller, once the tree of [_generation] made it.
  TreeController<String, DayListRow>? _tree;

  late List<DayListRow> _rows;

  /// [_rows] by key.
  Map<String, DayListRow> _rowsByKey = <String, DayListRow>{};

  /// Whether a frame will read the weeks of the days the list holds built.
  bool _prefetchScheduled = false;

  /// The day at the list's top as last reported or revealed.
  late DateTime _topDay = widget.selectedDay;

  /// Whether the scroll under way began with a drag, a fling after it
  /// included: only such a scroll reports top days.
  bool _dragScrolling = false;

  /// Whether a frame will look for a new top day.
  bool _topDayCheckScheduled = false;

  /// Counts the reveals started, so a top day check scheduled before one
  /// reports nothing.
  int _reveals = 0;

  /// Whether the list waits to land on the day it opened or re-centred on.
  /// It lays out first at an offset that takes each row before that day
  /// as [TreeController.defaultExtent] tall, which the rows it measures
  /// above the top make wrong, and stays invisible until [_land] scrolls
  /// to the day by the tree's own measure.
  bool _landing = true;

  /// The rows mounted, which [_dayAtTop] and [_prefetchShown] read.
  final Set<_DayMarkerState> _markers = <_DayMarkerState>{};

  /// The day [DayList.now] reads, whose block marks the current time.
  late DateTime _nowDay = dateOnly(widget.now.value);

  @override
  void initState() {
    super.initState();
    _centreOn(widget.selectedDay);
    _scroll = ScrollController(initialScrollOffset: _offsetOf(_topDay));
    widget.store.addListener(_handleStore);
    widget.now.addListener(_handleNow);
    _scheduleLanding();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _styles = _ListStyles.of(context);
  }

  @override
  void reassemble() {
    _ListStyles._reset();
    super.reassemble();
    _styles = _ListStyles.of(context);
  }

  @override
  void didUpdateWidget(DayList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.store != oldWidget.store) {
      oldWidget.store.removeListener(_handleStore);
      widget.store.addListener(_handleStore);
    }
    if (widget.now != oldWidget.now) {
      oldWidget.now.removeListener(_handleNow);
      widget.now.addListener(_handleNow);
      _nowDay = dateOnly(widget.now.value);
    }
    if (widget.weekdays != oldWidget.weekdays) {
      _rebuildOn(widget.selectedDay);
      return;
    }
    if (widget.store != oldWidget.store ||
        widget.hours != oldWidget.hours ||
        widget.editable != oldWidget.editable) {
      _rows = _rowsOf();
    }
    final day = widget.selectedDay;
    if (day != oldWidget.selectedDay && day != _topDay) {
      // After the frame, once the tree has laid out what this build gives
      // it.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.selectedDay == day) {
          _reveal(day);
        }
      });
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStore);
    widget.now.removeListener(_handleNow);
    _scroll.dispose();
    super.dispose();
  }

  void _handleStore() {
    setState(() {
      _rows = _rowsOf();
    });
  }

  /// Moves the marker of the current time to the block of a new day; the
  /// markers follow the minutes themselves.
  void _handleNow() {
    final day = dateOnly(widget.now.value);
    if (day != _nowDay) {
      setState(() {
        _nowDay = day;
      });
    }
  }

  /// Holds the days around [day] and builds their rows.
  void _centreOn(DateTime day) {
    final number = dayNumber(day);
    _first = number - dayListWindowDays;
    _last = number + dayListWindowDays;
    _rows = _rowsOf();
    _topDay = day;
  }

  /// Centres the list on [day] in a new scroll view and a new tree, which
  /// open with [day]'s header at the top. Mutates the state only, for the
  /// caller's build or setState.
  void _rebuildOn(DateTime day) {
    _centreOn(day);
    _generation++;
    _tree = null;
    final old = _scroll;
    _scroll = ScrollController(initialScrollOffset: _offsetOf(day));
    // The old scroll view lets go of it in the build that replaces it.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      old.dispose();
    });
    _landing = true;
    _scheduleLanding();
  }

  /// Lands on [_topDay] after the next frame, which lays the list out. Not
  /// at that frame's start: a callback scheduled for it can run before any
  /// layout, as the first frame's does, which runs the callbacks the first
  /// build scheduled before it lays anything out. A post-frame callback
  /// schedules no frame, so this asks for one, which [_land]'s wait for a
  /// layout needs.
  void _scheduleLanding() {
    final generation = _generation;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) {
        _land(generation);
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Jumps [_topDay]'s header to the list's top, by the tree's own measure
  /// of the rows before it, in which a row it has not laid out takes
  /// [TreeController.defaultExtent] as it does in the tree's layout; shows
  /// the list; and after the frame that lays the jump out, reads the weeks
  /// of the days it holds built. While the list is not laid out yet, it
  /// waits for a frame that lays it out.
  void _land(int generation) {
    final tree = _tree;
    if (tree == null ||
        !_scroll.hasClients ||
        !_scroll.position.hasContentDimensions) {
      _scheduleLanding();
      return;
    }
    final offset = tree.scrollOffsetOf(DayListHeader.headerKeyOf(_topDay));
    if (offset != null) {
      final position = _scroll.position;
      _scroll.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }
    setState(() {
      _landing = false;
    });
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) {
        _prefetchShown();
      }
    });
  }

  /// The scroll offset of [day]'s header in a tree that has measured no
  /// row, where each row before it takes [TreeController.defaultExtent].
  double _offsetOf(DateTime day) {
    final index = _rows.indexWhere((row) {
      return row is DayListHeader && row.day == day;
    });
    return math.max(index, 0) * TreeController.defaultExtent;
  }

  List<DayListRow> _rowsOf() {
    final rows = _buildRows();
    _rowsByKey = <String, DayListRow>{for (final row in rows) row.key: row};
    return rows;
  }

  List<DayListRow> _buildRows() {
    final store = widget.store;
    final rows = <DayListRow>[];
    for (var number = _first; number <= _last; number++) {
      if (!widget.weekdays.containsDay(number)) {
        continue;
      }
      final day = dateOfDayNumber(number);
      if (!store.isRead(day)) {
        rows.add(DayListHeader(day, count: null));
        rows.add(
          DayListBody(
            day,
            rows: <DayListRow>[
              store.readFailed(day) ? DayListFailed(day) : DayListLoading(day),
            ],
          ),
        );
        continue;
      }
      final entries = store.entriesOn(day);
      rows.add(DayListHeader(day, count: entries.length));
      rows.add(
        DayListBody(
          day,
          rows: dayListRowsOf(
            day,
            entries,
            widget.hours,
            editable: widget.editable,
          ),
        ),
      );
    }
    return rows;
  }

  /// Scrolls [day]'s header to the list's top, animating over the theme's
  /// motion, or at once where its duration is zero, or re-centres the list
  /// on it when it is too near or past either end of the days.
  Future<void> _reveal(DateTime day) async {
    final number = dayNumber(day);
    final tree = _tree;
    if (tree == null ||
        !_scroll.hasClients ||
        !_scroll.position.hasContentDimensions ||
        number < _first + _edgeDays ||
        number > _last - _edgeDays) {
      setState(() {
        _rebuildOn(day);
      });
      return;
    }
    final from = dayNumber(_topDay);
    _topDay = day;
    final reveals = ++_reveals;
    final key = DayListHeader.headerKeyOf(day);
    final theme = _styles.theme;
    final landed = await tree.animateScrollToKey(
      key,
      scrollController: _scroll,
      duration: theme.motionDuration,
      curve: theme.motionCurve,
      extentEstimator: (key) {
        return _estimatedExtentOf(key, from);
      },
    );
    if (!landed || !mounted) {
      return;
    }
    // The tree's own landing re-derives the target from the estimates,
    // which differ from the layout for a row the scroll passed without
    // building. After that landing's post-frame callback, which the call
    // above schedules before it returns, this lands by the layout's own
    // measure, unless a drag or another reveal took over.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || reveals != _reveals || !_scroll.hasClients) {
        return;
      }
      final position = _scroll.position;
      final offset = tree.scrollOffsetOf(key);
      if (offset == null ||
          !position.hasContentDimensions ||
          position.userScrollDirection != ScrollDirection.idle) {
        return;
      }
      final target = offset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((target - position.pixels).abs() > 0.5) {
        position.jumpTo(target);
      }
    });
  }

  /// The height the row [key] names will take once laid out, for a reveal
  /// from the day [from], a [dayNumber], whose target the tree sums from
  /// the rows' heights. A row the tree has not laid out it takes as this.
  /// The tree lays out a row before [from], above the list's top, at
  /// [TreeController.defaultExtent] until it builds it, so that stays its
  /// height here; a row from [from] on the reveal scrolls through, and the
  /// tree lays it out at its own height, which this predicts from what the
  /// row shows.
  double _estimatedExtentOf(String key, int from) {
    final row = _rowsByKey[key];
    if (row == null || dayNumber(row.day) < from) {
      return TreeController.defaultExtent;
    }
    switch (row) {
      case DayListHeader():
        return _headerExtent;
      case DayListBody(:final rows):
        var extent = 0.0;
        for (final shown in rows) {
          extent += _blockRowExtent(shown);
        }
        return extent;
      default:
        return TreeController.defaultExtent;
    }
  }

  /// The height of a header: its padding and one line of its title.
  static const double _headerExtent = 16.0 + 19.0 + 12.0;

  /// The predicted height of [row] in a day's block, its padding included:
  /// for an item, the taller of its card (as [DayList.cardExtentOf]
  /// answers, or [defaultCalendarCardExtent] where it is null, and a strip
  /// [calendarCardStripExtent] tall for each end it has outside the
  /// hours) and its time column (a line and the duration chip); a banner's
  /// padding and arrow; a failed row, 48 tall, the least the list gives
  /// its builder; or a dashed or loading row, 24 tall.
  double _blockRowExtent(DayListRow row) {
    const padding = _rowGap;
    final hours = widget.hours;
    switch (row) {
      case DayListItem<T>(:final entry):
        final item = entry.entry;
        final cardExtentOf = widget.cardExtentOf;
        final strips =
            (item.startMinute < hours.start ? calendarCardStripExtent : 0.0) +
            (item.endMinute > hours.end ? calendarCardStripExtent : 0.0);
        final card =
            (cardExtentOf == null
                ? defaultCalendarCardExtent(_styles.theme)
                : cardExtentOf(entry)) +
            strips;
        const times = 16.0 + 6.0 + 17.0;
        return math.max(card, times) + padding;
      case DayListHidden():
        return 5.0 + 16.0 + 5.0 + padding;
      case DayListFailed():
        return _failedRowExtent + padding;
      default:
        return _lineRowExtent + padding;
    }
  }

  /// The height of a loading row and of a dashed row.
  static const double _lineRowExtent = 24.0;

  /// The least height of a failed row, which its builder may fill.
  static const double _failedRowExtent = 48.0;

  /// Reports a new top day while a drag, or the fling after it, scrolls
  /// the list, and reads the days near those it shows once it rests. A
  /// scroll that reveals a day reports none.
  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _dragScrolling = notification.dragDetails != null;
    } else if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails != null) {
        _dragScrolling = true;
      }
      if (_dragScrolling) {
        _scheduleTopDayCheck();
      }
    } else if (notification is ScrollEndNotification) {
      if (_dragScrolling) {
        _scheduleTopDayCheck();
      }
      _dragScrolling = false;
      _prefetchShown();
    }
    return false;
  }

  /// Looks for a new top day after the frame that lays the rows out at
  /// the scroll's new offset, unless a reveal starts first, and reports
  /// one it finds.
  void _scheduleTopDayCheck() {
    if (_topDayCheckScheduled) {
      return;
    }
    _topDayCheckScheduled = true;
    final reveals = _reveals;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _topDayCheckScheduled = false;
      if (!mounted || reveals != _reveals) {
        return;
      }
      final day = _dayAtTop();
      if (day == null || day == _topDay) {
        return;
      }
      _topDay = day;
      _reportTopDay(day);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Reports [day] as the new top day, and grows or re-centres the list
  /// when it lies near either end of the list's days.
  void _reportTopDay(DateTime day) {
    widget.onTopDay(day);
    final number = dayNumber(day);
    if (number > _last - _edgeDays) {
      setState(() {
        _last += dayListWindowDays;
        _rows = _rowsOf();
      });
    } else if (number < _first + _edgeDays) {
      setState(() {
        _rebuildOn(day);
      });
    }
  }

  /// The day of the row that reaches [_probe] below the list's top, or
  /// null when no mounted row does.
  DateTime? _dayAtTop() {
    final list = context.findRenderObject();
    if (list is! RenderBox || !list.hasSize) {
      return null;
    }
    for (final marker in _markers) {
      final box = marker.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) {
        continue;
      }
      final top = box.localToGlobal(Offset.zero, ancestor: list).dy;
      if (top <= _probe && top + box.size.height > _probe) {
        return marker.widget.day;
      }
    }
    return null;
  }

  /// After the frame, reads the weeks of the days the list holds built,
  /// once however many rows mount in it: a row can mount with no scroll
  /// to end, as when the tree corrects its offset for a height it
  /// measured.
  void _schedulePrefetch() {
    if (_prefetchScheduled) {
      return;
    }
    _prefetchScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _prefetchScheduled = false;
      if (mounted) {
        _prefetchShown();
      }
    });
  }

  /// Reads the unread days of the weeks of the mounted rows' days, as the
  /// week strip reads the weeks of the days it shows.
  void _prefetchShown() {
    int? first;
    int? last;
    for (final marker in _markers) {
      final number = dayNumber(marker.widget.day);
      first = first == null ? number : math.min(first, number);
      last = last == null ? number : math.max(last, number);
    }
    if (first == null || last == null) {
      return;
    }
    final weekdays = widget.weekdays;
    widget.store.prefetch(
      dateOfDayNumber(weekdays.weekStartOfDay(first)),
      dateOfDayNumber(weekdays.weekStartOfDay(last) + DateTime.daysPerWeek - 1),
    );
  }

  /// Reads the shown range again when its read failed, and the days near
  /// the mounted rows.
  void _retry() {
    if (widget.store.status == CalendarLoadStatus.failed) {
      widget.store.retry();
    }
    _prefetchShown();
  }

  @override
  Widget build(BuildContext context) {
    final Widget list = NotificationListener<ScrollNotification>(
      onNotification: _handleScroll,
      child: CustomScrollView(
        key: ValueKey<int>(_generation),
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          // Each row takes the list's whole width and keeps its content
          // [dayListGutter] in from either side, so a header's background
          // and the marker of the current time reach the list's edges.
          SyncedSliverTree<String, DayListRow>.flat(
            items: _rows,
            keyOf: (row) {
              return row.key;
            },
            parentOf: (row) {
              return row is DayListHeader
                  ? null
                  : DayListHeader.headerKeyOf(row.day);
            },
            maxStickyDepth: 1,
            animationStyle: _styles.treeStyle,
            onControllerCreated: (controller) {
              _tree = controller;
            },
            itemBuilder: (context, node) {
              final row = node.item;
              return _DayMarker(
                day: row.day,
                markers: _markers,
                onMount: _schedulePrefetch,
                child: _buildRow(row),
              );
            },
          ),
        ],
      ),
    );
    return Opacity(opacity: _landing ? 0.0 : 1.0, child: list);
  }

  Widget _buildRow(DayListRow row) {
    switch (row) {
      case DayListHeader():
        return _buildHeader(row);
      case DayListBody(:final day, :final rows):
        if (day != _nowDay) {
          return _AnimatedRows(rows: rows, builder: _buildDayRow);
        }
        final spans = _NowSpan.spansOf(rows, widget.hours);
        return _AnimatedRows(
          rows: rows,
          builder: _buildDayRow,
          overlayOf: (row) {
            final span = spans[row.key];
            if (span == null) {
              return null;
            }
            return _NowMarker(
              now: widget.now,
              span: span,
              hours: widget.hours,
              format: widget.format,
            );
          },
        );
      default:
        return _buildDayRow(row);
    }
  }

  /// One row of a day's block.
  Widget _buildDayRow(DayListRow row) {
    switch (row) {
      case DayListHeader():
      case DayListBody():
        throw ArgumentError.value(row, "row", "not a row of a block");
      case DayListItem<T>(:final entry):
        return _padded(_buildItem(entry));
      case DayListItem():
        throw ArgumentError.value(row, "row", "an item of another payload");
      case DayListGap(:final day, :final start, :final end):
        final from = math.max(start, widget.lock.earliestStartOn(day));
        return _padded(
          _buildDashed(
            key: dayListGapKey(day, start),
            label: hourLabel(start, widget.format),
            day: day,
            addMinute: from,
            addLabel: "Add an item at ${hourLabel(from, widget.format)}",
            onAdd: from < end
                ? () {
                    widget.onCreateIn(day, from, from + minutesPerSlot);
                  }
                : null,
          ),
        );
      case DayListHidden(:final day, :final count, :final above):
        return _padded(_buildHidden(day, count, above: above));
      case DayListLoading(:final day):
        final loading = widget.loadingBuilder ?? defaultCalendarLoadingBuilder;
        return _padded(
          SizedBox(
            key: dayListLoadingKey(day),
            height: _lineRowExtent,
            child: Builder(
              builder: (context) {
                return loading(
                  context,
                  CalendarLoadingState(
                    site: CalendarStateSite.dayRow,
                    first: day,
                    last: day,
                  ),
                );
              },
            ),
          ),
        );
      case DayListFailed(:final day):
        final failure = widget.failureBuilder ?? defaultCalendarFailureBuilder;
        return _padded(
          ConstrainedBox(
            key: dayListFailedKey(day),
            constraints: const BoxConstraints(minHeight: _failedRowExtent),
            child: Builder(
              builder: (context) {
                // A day a prefetch failed to read, while the shown range is
                // ready, has no load error.
                return failure(
                  context,
                  CalendarFailureState(
                    site: CalendarStateSite.dayRow,
                    first: day,
                    last: day,
                    error: widget.store.loadError,
                    retry: _retry,
                  ),
                );
              },
            ),
          ),
        );
    }
  }

  Widget _padded(Widget child) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        dayListGutter,
        0.0,
        dayListGutter,
        _rowGap,
      ),
      child: child,
    );
  }

  /// The day's title and how many items it shows, on the background
  /// colour, so the rows scrolling under it while it sticks stay hidden. A
  /// day read to hold no items has both in their own styles, muted, on a
  /// line as tall as a busy day's title takes, so its header is as tall.
  Widget _buildHeader(DayListHeader row) {
    final count = row.count;
    final empty = count == 0;
    final styles = _styles;
    return ColoredBox(
      key: dayListHeaderKey(row.day),
      color: styles.theme.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          dayListGutter,
          16.0,
          dayListGutter,
          12.0,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                dayTitle(row.day, widget.today),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                strutStyle: empty
                    ? StrutStyle.fromTextStyle(
                        DefaultTextStyle.of(context).style.merge(styles.title),
                        forceStrutHeight: true,
                      )
                    : null,
                style: empty ? styles.emptyTitle : styles.title,
              ),
            ),
            if (count != null)
              Text(
                itemCountLabel(count),
                style: empty ? styles.emptyCount : styles.count,
              ),
          ],
        ),
      ),
    );
  }

  /// The later of the item's start and the hours', its whole length on a
  /// chip under that behind an hourglass, scaled down where the chip would
  /// not fit the time column, and its card's slot. The card of an item that
  /// starts before the hours is handed its own start, for a strip across
  /// its top, and that of one that ends after them its own end, for a strip
  /// across its bottom. A row leaving for a banner, whose item has no
  /// minute inside the hours, shows the item's own start and is handed
  /// neither.
  Widget _buildItem(CalendarShownEntry<T> entry) {
    final item = entry.entry;
    final hours = widget.hours;
    var start = math.max(item.startMinute, hours.start);
    final inside = math.min(item.endMinute, hours.end) > start;
    if (!inside) {
      start = item.startMinute;
    }
    final hold = widget.lock.holdOf(item.time);
    final styles = _styles;
    return Row(
      children: <Widget>[
        Container(
          key: dayListTimeKey(entry.id),
          width: dayListTimeWidth,
          padding: const EdgeInsets.only(right: dayListTimeGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                hourLabel(start, widget.format),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.time,
              ),
              const SizedBox(height: 6.0),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: DecoratedBox(
                  key: dayListDurationKey(entry.id),
                  decoration: styles.durationChip,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7.0,
                      vertical: 2.0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        styles.durationIcon,
                        const SizedBox(width: 2.0),
                        Text(
                          durationLabel(item.endMinute - item.startMinute),
                          style: styles.durationLabel,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _CardSlot<T>(
            key: itemCardKey(entry.id),
            entry: entry,
            builder: widget.cardBuilder ?? defaultCalendarCardBuilder<T>,
            startsAt: inside && item.startMinute < hours.start
                ? hourLabel(item.startMinute, widget.format)
                : null,
            endsAt: inside && item.endMinute > hours.end
                ? hourLabel(item.endMinute, widget.format)
                : null,
            onEdit: widget.editable && hold != ItemHold.locked
                ? () {
                    widget.onEdit(entry.id);
                  }
                : null,
            onDelete: widget.editable && hold == ItemHold.free
                ? () {
                    widget.onDelete(entry.id);
                  }
                : null,
          ),
        ),
      ],
    );
  }

  /// A soft yellow banner across the row's width that counts the [count]
  /// items of [day] wholly before the hours, under an arrow pointing up,
  /// or wholly after them when [above] is false, under one pointing down,
  /// in the timed grid's style for its rows outside the hours.
  Widget _buildHidden(DateTime day, int count, {required bool above}) {
    final minute = above ? widget.hours.start : widget.hours.end;
    final side = above ? "before" : "after";
    final styles = _styles;
    return Semantics(
      container: true,
      label: hiddenRowLabel(
        day,
        count,
        minute,
        above: above,
        format: widget.format,
      ),
      excludeSemantics: true,
      child: Row(
        key: dayListHiddenKey(day, above: above),
        children: <Widget>[
          Expanded(
            child: DecoratedBox(
              decoration: styles.banner,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 5.0,
                ),
                child: Row(
                  children: <Widget>[
                    above ? styles.beforeIcon : styles.afterIcon,
                    const SizedBox(width: 4.0),
                    Expanded(
                      child: Text(
                        "${moreItemsLabel(count)} $side "
                        "${hourLabel(minute, widget.format)}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.bannerLabel,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [label] at the end of the time column, a dashed line across the
  /// cards' width, and at its end a [dayListAddButtonSize] square, which a
  /// screen reader hears as [addLabel], holding what the add button builder
  /// draws for a press that adds an item at [addMinute] on [day] through
  /// [onAdd], or the square's room where [onAdd] is null.
  Widget _buildDashed({
    required Key key,
    required String label,
    required DateTime day,
    required int addMinute,
    required String addLabel,
    required VoidCallback? onAdd,
  }) {
    return SizedBox(
      key: key,
      height: _lineRowExtent,
      child: Row(
        children: <Widget>[
          Container(
            width: dayListTimeWidth,
            padding: const EdgeInsets.only(right: dayListTimeGap),
            alignment: Alignment.centerRight,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _styles.gapTime,
            ),
          ),
          _styles.dashedLine,
          const SizedBox(width: 8.0),
          if (onAdd == null)
            const SizedBox(width: dayListAddButtonSize)
          else
            Semantics(
              container: true,
              label: addLabel,
              child: SizedBox.square(
                dimension: dayListAddButtonSize,
                child: Builder(
                  builder: (context) {
                    final add =
                        widget.addButtonBuilder ??
                        defaultCalendarAddButtonBuilder;
                    return add(
                      context,
                      CalendarAddButtonDetails(
                        day: day,
                        startMinute: addMinute,
                        onPressed: onAdd,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// [rows] one under another, each built by [builder]: a row the first
/// build holds shows at once, and a row a later build adds grows in and
/// fades in, while one it drops fades out and shrinks away where it was,
/// each over the [CalendarTheme]'s motion as it is when the row starts to
/// move, or at once where its duration is zero. A row a later build moves
/// does both: it leaves where it was and comes in where it goes. The rows that stay in place are the most that keep their order,
/// so a move of one row moves that row alone. Where [overlayOf] is given,
/// what it builds for a row that is not leaving lies over the row, at its
/// size and free to paint past it.
class _AnimatedRows extends StatefulWidget {
  const _AnimatedRows({
    required this.rows,
    required this.builder,
    this.overlayOf,
  });

  final List<DayListRow> rows;
  final Widget Function(DayListRow row) builder;
  final Widget? Function(DayListRow row)? overlayOf;

  @override
  State<_AnimatedRows> createState() {
    return _AnimatedRowsState();
  }
}

/// A row [_AnimatedRows] shows, and the animation that grows it in or
/// shrinks it away.
class _Shown {
  _Shown(this.row, this.controller, Curve motion)
    : curve = CurvedAnimation(parent: controller, curve: motion);

  DayListRow row;
  final AnimationController controller;
  final CurvedAnimation curve;

  /// Whether the row is leaving, shrinking to nothing.
  bool leaving = false;

  void dispose() {
    curve.dispose();
    controller.dispose();
  }
}

class _AnimatedRowsState extends State<_AnimatedRows>
    with TickerProviderStateMixin {
  /// The rows shown, leaving ones included, in the order they show.
  final List<_Shown> _shown = <_Shown>[];

  /// What a row's motion is read from when it starts.
  late _ListStyles _styles;

  /// Whether the first rows are made, which [_styles] must be read for
  /// first.
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _styles = _ListStyles.of(context);
    if (!_started) {
      _started = true;
      for (final row in widget.rows) {
        _shown.add(_shownOf(row, from: 1.0));
      }
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _styles = _ListStyles.of(context);
  }

  @override
  void didUpdateWidget(_AnimatedRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A frame that brings a new theme with new rows calls this before the
    // rebuild that calls didChangeDependencies, so the rows started below
    // read the theme here.
    _styles = _ListStyles.of(context);
    if (identical(widget.rows, oldWidget.rows)) {
      return;
    }
    // Where each row not leaving shows now, by key.
    final present = <String, int>{};
    for (var i = 0; i < _shown.length; i++) {
      if (!_shown[i].leaving) {
        present[_shown[i].row.key] = i;
      }
    }
    final staying = _longestIncreasing(<int>[
      for (final row in widget.rows) ?present[row.key],
    ]);
    final next = <_Shown>[];
    final kept = <_Shown>{};
    for (final row in widget.rows) {
      final index = present[row.key];
      if (index != null && staying.contains(index)) {
        final shown = _shown[index]..row = row;
        kept.add(shown);
        next.add(shown);
      } else {
        final shown = _shownOf(row, from: 0.0);
        _run(shown, forward: true);
        next.add(shown);
      }
    }
    // Every other row leaves where it was, after the row it followed, or
    // first.
    for (var i = 0; i < _shown.length; i++) {
      final shown = _shown[i];
      if (kept.contains(shown)) {
        continue;
      }
      if (!shown.leaving) {
        shown.leaving = true;
        _run(shown, forward: false).whenComplete(() {
          _dropLeft(shown);
        });
      }
      var at = 0;
      for (var j = i - 1; j >= 0; j--) {
        final index = next.indexOf(_shown[j]);
        if (index >= 0) {
          at = index + 1;
          break;
        }
      }
      next.insert(at, shown);
    }
    _shown
      ..clear()
      ..addAll(next);
  }

  /// The values of the longest run of [values], in their order, that
  /// rises throughout.
  static Set<int> _longestIncreasing(List<int> values) {
    if (values.isEmpty) {
      return <int>{};
    }
    final length = List<int>.filled(values.length, 1);
    final previous = List<int>.filled(values.length, -1);
    var best = 0;
    for (var i = 0; i < values.length; i++) {
      for (var j = 0; j < i; j++) {
        if (values[j] < values[i] && length[j] + 1 > length[i]) {
          length[i] = length[j] + 1;
          previous[i] = j;
        }
      }
      if (length[i] > length[best]) {
        best = i;
      }
    }
    final run = <int>{};
    for (var i = best; i >= 0; i = previous[i]) {
      run.add(values[i]);
    }
    return run;
  }

  _Shown _shownOf(DayListRow row, {required double from}) {
    final theme = _styles.theme;
    return _Shown(
      row,
      AnimationController(
        vsync: this,
        duration: theme.motionDuration,
        value: from,
      ),
      theme.motionCurve,
    );
  }

  /// Grows [shown] in, or shrinks it away where not [forward], on the
  /// theme's motion as it is now.
  TickerFuture _run(_Shown shown, {required bool forward}) {
    final theme = _styles.theme;
    shown.controller.duration = theme.motionDuration;
    shown.curve.curve = theme.motionCurve;
    return forward ? shown.controller.forward() : shown.controller.reverse();
  }

  /// Drops [shown] once it has shrunk away.
  void _dropLeft(_Shown shown) {
    if (!mounted || !_shown.contains(shown)) {
      return;
    }
    setState(() {
      _shown.remove(shown);
    });
    shown.dispose();
  }

  @override
  void dispose() {
    for (final shown in _shown) {
      shown.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overlayOf = widget.overlayOf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final shown in _shown)
          if (overlayOf == null)
            _buildShown(shown)
          else
            // Over every row alike, an overlay or none, so a row the
            // overlay moves to or from keeps its subtree.
            Stack(
              key: ObjectKey(shown),
              clipBehavior: Clip.none,
              children: <Widget>[
                _buildShown(shown),
                if (!shown.leaving)
                  if (overlayOf(shown.row) case final overlay?)
                    Positioned.fill(child: overlay),
              ],
            ),
      ],
    );
  }

  Widget _buildShown(_Shown shown) {
    return SizeTransition(
      // By instance: a row that moves shows twice while it leaves one
      // place and comes in at the other.
      key: ObjectKey(shown),
      sizeFactor: shown.curve,
      alignment: Alignment.topLeft,
      child: FadeTransition(
        opacity: shown.curve,
        child: widget.builder(shown.row),
      ),
    );
  }
}

/// The space under each row of a day's block, in whose middle the marker
/// of the current time lies between two rows.
const double _rowGap = 12.0;

/// Where on its row the marker of the current time lies.
enum _NowSide {
  /// Across the row's content, which is an item running at the time.
  across,

  /// In the gap under the row.
  below,

  /// In the gap above the row, the block's first.
  above,
}

/// The minutes, from [from] up to [until], for which a row of a day's
/// block holds the marker of the current time, the [item]'s minutes inside
/// the hours where the row is one, with whether it runs on [before] or
/// [after] them, and whether the row is the block's [first], which also
/// holds the marker for the minutes before [from].
@immutable
class _NowSpan {
  const _NowSpan({
    required this.from,
    required this.until,
    required this.first,
    required this.item,
  });

  final int from;
  final int until;
  final bool first;
  final ({int start, int end, bool before, bool after})? item;

  /// The span of each of a day's [rows] in [hours] by key: each row holds
  /// the marker from its start to the next row's, the last one on past the
  /// end of the day. A banner of the items before the hours starts before
  /// any minute, and one of those after them after every minute. Only rows
  /// with a start take part.
  static Map<String, _NowSpan> spansOf(List<DayListRow> rows, DayHours hours) {
    final starts = <(DayListRow, int)>[];
    for (final row in rows) {
      final start = switch (row) {
        DayListHidden(above: true) => -1,
        DayListHidden(above: false) => minutesPerDay + 1,
        DayListItem(:final entry) => entry.entry.startMinute,
        DayListGap(:final start) => start,
        _ => null,
      };
      if (start != null) {
        starts.add((row, start));
      }
    }
    return <String, _NowSpan>{
      for (var i = 0; i < starts.length; i++)
        starts[i].$1.key: _NowSpan(
          from: starts[i].$2,
          until: i + 1 < starts.length ? starts[i + 1].$2 : minutesPerDay + 1,
          first: i == 0,
          item: switch (starts[i].$1) {
            DayListItem(:final entry) => (
              start: math.max(entry.entry.startMinute, hours.start),
              end: math.min(entry.entry.endMinute, hours.end),
              before: entry.entry.startMinute < hours.start,
              after: entry.entry.endMinute > hours.end,
            ),
            _ => null,
          },
        ),
    };
  }

  /// Where on its row the marker of [minute] lies, and for [_NowSide.across]
  /// the share of the item's minutes inside the hours that has run, all of
  /// it at their end for an item that runs on after them; null where
  /// another row holds it.
  ({_NowSide side, double fraction})? placeOf(int minute) {
    if (minute < from) {
      return first ? (side: _NowSide.above, fraction: 0.0) : null;
    }
    if (minute >= until) {
      return null;
    }
    final item = this.item;
    if (item != null &&
        (minute < item.end || (item.after && minute == item.end))) {
      return (
        side: _NowSide.across,
        fraction: (minute - item.start) / (item.end - item.start),
      );
    }
    return (side: _NowSide.below, fraction: 0.0);
  }

  @override
  bool operator ==(Object other) {
    return other is _NowSpan &&
        other.from == from &&
        other.until == until &&
        other.first == first &&
        other.item == item;
  }

  @override
  int get hashCode {
    return Object.hash(from, until, first, item);
  }
}

/// The marker of [now] over a row of its day's block, where the row's
/// [span] holds it and the [hours] hold its minute, the end of the hours
/// included as the timed grid includes it; nothing otherwise. It follows
/// [now] itself, takes no pointer and is not heard.
class _NowMarker extends StatelessWidget {
  const _NowMarker({
    required this.now,
    required this.span,
    required this.hours,
    required this.format,
  });

  final ValueListenable<DateTime> now;
  final _NowSpan span;
  final DayHours hours;
  final HourLabelFormat format;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: now,
      builder: (context, now, child) {
        final minute = now.hour * 60 + now.minute;
        if (minute < hours.start || minute > hours.end) {
          return const SizedBox.shrink();
        }
        final place = span.placeOf(minute);
        if (place == null) {
          return const SizedBox.shrink();
        }
        final item = span.item;
        return IgnorePointer(
          child: ExcludeSemantics(
            child: CustomSingleChildLayout(
              delegate: _NowLayout(
                place.side,
                place.fraction,
                top: item != null && item.before
                    ? calendarCardStripExtent
                    : 0.0,
                bottom: item != null && item.after
                    ? calendarCardStripExtent
                    : 0.0,
              ),
              child: _NowLine(label: hourLabel(minute, format)),
            ),
          ),
        );
      },
    );
  }
}

/// Lays the marker of the current time out across its row's width, its
/// middle on the line: for [_NowSide.across] [fraction] of the way down
/// the row's content between its [top] and [bottom] strips, or in the
/// middle of the gap under or above the row.
class _NowLayout extends SingleChildLayoutDelegate {
  const _NowLayout(
    this.side,
    this.fraction, {
    required this.top,
    required this.bottom,
  });

  final _NowSide side;
  final double fraction;
  final double top;
  final double bottom;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.tightFor(width: constraints.maxWidth);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final content = size.height - _rowGap;
    final line = switch (side) {
      _NowSide.across => top + (content - top - bottom) * fraction,
      _NowSide.below => content + _rowGap / 2.0,
      _NowSide.above => -_rowGap / 2.0,
    };
    return Offset(0.0, line - childSize.height / 2.0);
  }

  @override
  bool shouldRelayout(_NowLayout oldDelegate) {
    return oldDelegate.side != side ||
        oldDelegate.fraction != fraction ||
        oldDelegate.top != top ||
        oldDelegate.bottom != bottom;
  }
}

/// The current time, [label], at the end of a pill across the time
/// column, and a line from the cards to the row's right edge with a dot at
/// its start, in the theme's error colour, as the timed grid marks the
/// current time.
class _NowLine extends StatelessWidget {
  const _NowLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final styles = _ListStyles.of(context);
    return Row(
      key: dayListNowKey,
      children: <Widget>[
        SizedBox(
          // width: dayListGutter + dayListTimeWidth,
          child: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: DecoratedBox(
              decoration: styles.nowPill,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6.0,
                  vertical: 2.0,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: styles.nowLabel,
                ),
              ),
            ),
          ),
        ),
        styles.nowLine,
      ],
    );
  }
}

/// A line across the middle of its box in [_paint], with a dot at its
/// start.
class _NowLinePainter extends CustomPainter {
  const _NowLinePainter(this._paint);

  static const double dotRadius = 4.0;

  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2.0;
    canvas.drawLine(Offset(0.0, y), Offset(size.width, y), _paint);
    canvas.drawCircle(Offset(0.0, y), dotRadius, _paint);
  }

  @override
  bool shouldRepaint(_NowLinePainter oldDelegate) {
    return !identical(oldDelegate._paint, _paint);
  }
}

/// The slot of an entry's card in its row, keyed [itemCardKey]: what
/// [builder] draws for [entry] and the details this slot makes of
/// [startsAt], [endsAt], [onEdit] and [onDelete] on each of its builds,
/// called below the row, so a builder that throws loses its own output
/// alone.
class _CardSlot<T> extends StatelessWidget {
  const _CardSlot({
    super.key,
    required this.entry,
    required this.builder,
    required this.startsAt,
    required this.endsAt,
    required this.onEdit,
    required this.onDelete,
  });

  final CalendarShownEntry<T> entry;
  final CalendarCardBuilder<T> builder;
  final String? startsAt;
  final String? endsAt;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return builder(
      context,
      entry,
      CalendarCardDetails(
        startsAt: startsAt,
        endsAt: endsAt,
        onEdit: onEdit,
        onDelete: onDelete,
      ),
    );
  }
}

/// Registers its [day]'s row in [markers] while mounted, and reports
/// through [onMount] that it mounted.
class _DayMarker extends StatefulWidget {
  const _DayMarker({
    required this.day,
    required this.markers,
    required this.onMount,
    required this.child,
  });

  final DateTime day;
  final Set<_DayMarkerState> markers;
  final VoidCallback onMount;
  final Widget child;

  @override
  State<_DayMarker> createState() {
    return _DayMarkerState();
  }
}

class _DayMarkerState extends State<_DayMarker> {
  @override
  void initState() {
    super.initState();
    widget.markers.add(this);
    widget.onMount();
  }

  @override
  void didUpdateWidget(_DayMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.markers, oldWidget.markers)) {
      oldWidget.markers.remove(this);
      widget.markers.add(this);
    }
  }

  @override
  void dispose() {
    widget.markers.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// A dashed line in [_paint] across the middle of its box.
class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter(this._paint);

  static const double _dash = 4.0;
  static const double _gap = 4.0;

  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    final y = (size.height / 2.0).floorToDouble() + 0.5;
    for (var x = 0.0; x < size.width; x += _dash + _gap) {
      final end = x + _dash < size.width ? x + _dash : size.width;
      canvas.drawLine(Offset(x, y), Offset(end, y), _paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) {
    return !identical(oldDelegate._paint, _paint);
  }
}
