/// The timed grid's layout of its entries: the tracks a grid lays out,
/// the pieces and bars its board shows of its entries, and the split that
/// makes them of the entries the store shows, with the entries it has no
/// block for, counted, and those an overlap check reads besides the
/// board's, indexed.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';
import '../entries/calendar_entry.dart';
import '../policy/overlap.dart';
import '../store/calendar_store.dart';
import 'entry_split.dart';

/// The all-day strip's rows shown collapsed before its count row.
const int collapsedStripRows = 3;

/// Which day each column of a timed grid shows and which minute each of
/// its rows starts at.
///
/// Column 0 is the hour gutter, and the rows from [firstSlotRow] are the
/// slots of [hours], one per [slotMinutes]; the rows before it are
/// whatever the grid lays out above its slots, such as a day header, the
/// all-day strip's rows or a row counting the entries before the hours.
/// The
/// columns right of the gutter are the days of the [dayCount] days from
/// [firstDay] whose weekday [weekdays] holds, in order, so a day it does
/// not hold has no column and the days either side of it are adjacent.
@immutable
class GridTracks {
  GridTracks({
    required this.firstDay,
    required this.dayCount,
    this.weekdays = CalendarWeekdaySet.all,
    this.hours = CalendarDayHours.allDay,
    this.firstSlotRow = 1,
    this.slotMinutes = defaultSlotMinutes,
  }) : assert(dayCount >= 1),
       assert(firstSlotRow >= 0),
       assert(slotMinutes > 0),
       _days = List<int>.unmodifiable(<int>[
         for (var day = firstDay; day < firstDay + dayCount; day++)
           if (weekdays.containsDay(day)) day,
       ]);

  /// The [dayNumber] of the range's first day, shown or not.
  final int firstDay;

  /// The days in the range, shown or not.
  final int dayCount;

  final CalendarWeekdaySet weekdays;
  final CalendarDayHours hours;

  /// The row of the first slot.
  final int firstSlotRow;

  /// The length of one slot, one row, in minutes; [hours] start and end on
  /// its grid ([CalendarDayHours.isOnSlotsOf]).
  final int slotMinutes;

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
    return hours.slotCountOf(slotMinutes);
  }

  /// The row of the last slot.
  int get lastSlotRow {
    return firstSlotRow + rowCount - 1;
  }

  /// The local midnights of the shown days, by column as [_days]: built at
  /// the first [dateAt] of this instance, so a later one builds no date.
  late final List<DateTime> _dates = List<DateTime>.unmodifiable(<DateTime>[
    for (final day in _days) dateOfDayNumber(day),
  ]);

  /// Whether each shown day's clock repeats a stretch, by column as
  /// [_days]: built at the first [repeatsStretchAt] of this instance.
  late final List<bool> _repeats = List<bool>.unmodifiable(<bool>[
    for (final date in _dates) repeatedStretchOf(date) > Duration.zero,
  ]);

  /// The [dayNumber] of the day [column] shows, 1 to [columnCount].
  int dayAt(int column) {
    assert(column >= 1 && column <= columnCount);
    return _days[column - 1];
  }

  /// The local midnight of the day [column] shows, 1 to [columnCount].
  DateTime dateAt(int column) {
    assert(column >= 1 && column <= columnCount);
    return _dates[column - 1];
  }

  /// Whether the clock of the day [column] shows, 1 to [columnCount],
  /// reads a stretch twice ([repeatedStretchOf]), where a piece's rows,
  /// which follow its wall minutes ([wallSpanOf]), do not order as its
  /// instants do.
  bool repeatsStretchAt(int column) {
    assert(column >= 1 && column <= columnCount);
    return _repeats[column - 1];
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
    return hours.start + (row - firstSlotRow) * slotMinutes;
  }

  /// The row of the slot starting at [minute], a slot boundary in
  /// [hours].
  int rowOf(int minute) {
    return firstSlotRow + (minute - hours.start) ~/ slotMinutes;
  }

  @override
  bool operator ==(Object other) {
    return other is GridTracks &&
        other.firstDay == firstDay &&
        other.dayCount == dayCount &&
        other.weekdays == weekdays &&
        other.hours == hours &&
        other.firstSlotRow == firstSlotRow &&
        other.slotMinutes == slotMinutes;
  }

  @override
  int get hashCode {
    return Object.hash(
      firstDay,
      dayCount,
      weekdays,
      hours,
      firstSlotRow,
      slotMinutes,
    );
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
        "${isoTime(start)}-${isoTime(end)})";
  }
}

/// The bar of [shown]'s all-day entry in the all-day strip: across the
/// columns from the [dayNumber] [firstDay], the first shown day it covers,
/// to [lastDay], the last, in the strip's [row] from 0, and whether the
/// entry covers days before [firstDay], [continuesBefore], or after
/// [lastDay], [continuesAfter].
final class GridBar<T> extends GridShape<T> {
  const GridBar({
    required this.shown,
    required this.firstDay,
    required this.lastDay,
    required this.row,
    required this.continuesBefore,
    required this.continuesAfter,
  });

  @override
  final CalendarShownEntry<T> shown;

  final int firstDay;
  final int lastDay;
  final int row;
  final bool continuesBefore;
  final bool continuesAfter;

  @override
  bool operator ==(Object other) {
    return other is GridBar<T> &&
        other.shown == shown &&
        other.firstDay == firstDay &&
        other.lastDay == lastDay &&
        other.row == row &&
        other.continuesBefore == continuesBefore &&
        other.continuesAfter == continuesAfter;
  }

  @override
  int get hashCode {
    return Object.hash(
      shown,
      firstDay,
      lastDay,
      row,
      continuesBefore,
      continuesAfter,
    );
  }

  @override
  String toString() {
    return "GridBar(${shown.id}, ${isoDate(dateOfDayNumber(firstDay))} to "
        "${isoDate(dateOfDayNumber(lastDay))}, row $row)";
  }
}

/// The shown items a grid has no block for, as the grid [tracks] lays out
/// counts them: on each day column, those wholly before its hours and
/// those wholly after them, and those on no day it has a column for.
@immutable
class GridHiddenCounts {
  GridHiddenCounts(this.tracks, this.above, this.below, this.offDays)
    : rowAbove = above.any(_isCounted),
      rowBelow = below.any(_isCounted);

  /// No item on any of [tracks]' columns.
  GridHiddenCounts.none(GridTracks tracks)
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
    return other is GridHiddenCounts &&
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

/// Timed entries by their instants, which [sharesTime] searches in
/// O(log n) with no allocation: their ids, and their starts and their ends
/// as [DateTime.microsecondsSinceEpoch], each list sorted ascending on its
/// own. For the index of the days outside a grid's range, [readFrom] and
/// [readTo] are the [dayNumber]s of the days it has read: from [readFrom]
/// to the day before the range, and from the day after the range to
/// [readTo], each run empty while its end is the range's own day.
class GridOverlapIndex {
  GridOverlapIndex({this.readFrom = 0, this.readTo = 0});

  final Set<String> ids = <String>{};
  final List<int> starts = <int>[];
  final List<int> ends = <int>[];
  int readFrom;
  int readTo;

  /// Adds the timed entries of [shown] whose ids it does not hold, and
  /// sorts each list again: O(n log n).
  void addAll<T>(Iterable<CalendarShownEntry<T>> shown) {
    var added = false;
    for (final item in shown) {
      final entry = item.entry;
      if (entry.isAllDay || !ids.add(item.id)) {
        continue;
      }
      starts.add(entry.start.microsecondsSinceEpoch);
      ends.add(entry.end.microsecondsSinceEpoch);
      added = true;
    }
    if (added) {
      starts.sort();
      ends.sort();
    }
  }

  /// Whether an entry it holds other than [id], whose stored entry is
  /// [own], shares time with the range from [start] to [end]. The entries
  /// sharing time with it are those starting before [end] less those
  /// ending at [start] or before, every entry ending after it starts:
  /// none answers false and two or more true, and one is [id]'s only
  /// where it holds [id] and [own] shares time with the range, so [ids]
  /// is hashed only there.
  bool sharesTime<T>(
    String id,
    CalendarEntry<T> own,
    DateTime start,
    DateTime end,
  ) {
    final count =
        _countBelow(starts, end.microsecondsSinceEpoch) -
        _countBelow(ends, start.microsecondsSinceEpoch + 1);
    if (count <= 0) {
      return false;
    }
    if (count >= 2) {
      return true;
    }
    return !ids.contains(id) || !timesOverlap(own.start, own.end, start, end);
  }

  /// How many of the ascending [values] are less than [bound], by binary
  /// search.
  static int _countBelow(List<int> values, int bound) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (values[middle] < bound) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

/// The split of the entries a timed grid shows on the tracks it lays out
/// ([TimedGridLayout.of]): the pieces of its timed entries, the bars of
/// its all-day entries stacked in the strip's rows, the entries it has
/// no block or bar for, counted, and the timed entries a change's rows
/// on the board can miss, indexed.
class TimedGridLayout<T> {
  /// The split of no entries on [tracks], which [TimedGridLayout.of]
  /// splits again rather than keeps.
  TimedGridLayout.empty(GridTracks tracks)
    : this._(
        null,
        pieces: <GridPiece<T>>[],
        bars: <GridBar<T>>[],
        barRows: 0,
        below: List<int>.filled(tracks.columnCount, 0),
        hidden: GridHiddenCounts.none(tracks),
        loose: null,
      );

  TimedGridLayout._(
    this._read, {
    required this.pieces,
    required this.bars,
    required this.barRows,
    required this.below,
    required this.hidden,
    required this.loose,
  });

  /// The split of [shown] on [tracks]: for each timed entry its piece on
  /// each shown day it covers ([pieceOn]) that has a minute inside the
  /// hours, walking only the columns from its first day's to its last
  /// day's, so it yields at most one piece per shown day ([pieces]); each
  /// all-day entry's bar across the shown days it covers, stacked
  /// ([bars]); the entries with no block or bar, counted ([hidden]): on
  /// each day column the pieces wholly before its hours and those wholly
  /// after them, and the entries on no day it has a column for; and,
  /// indexed ([loose]), the timed entries a change's rows on the board
  /// can miss: those with a piece wholly before or after the hours, those
  /// covering a day of the range with no column, and those with a piece
  /// on a day whose clock repeats a stretch, where a piece's rows do not
  /// order as its instants do ([GridTracks.repeatsStretchAt]).
  ///
  /// Where [previous] split the identical entries, with the same pending
  /// flags in the same order, on the same days, weekdays and hours, the
  /// split is [previous], and runs nothing: a store notify that changes
  /// nothing the grid shows splits nothing; and a store that notifies as
  /// it is asked for new days, before the grid has them, syncs on the
  /// days shown before, whose split it keeps, so the step splits once.
  /// Each split it runs counts one ([noteEntrySplit]).
  factory TimedGridLayout.of(
    List<CalendarShownEntry<T>> shown,
    GridTracks tracks, {
    TimedGridLayout<T>? previous,
  }) {
    if (previous != null) {
      final read = previous._read;
      if (read != null &&
          read.firstDay == tracks.firstDay &&
          read.dayCount == tracks.dayCount &&
          read.weekdays == tracks.weekdays &&
          read.hours == tracks.hours &&
          _sameShown(read.shown, shown)) {
        return previous;
      }
    }
    noteEntrySplit();
    final hours = tracks.hours;
    final pieces = <GridPiece<T>>[];
    final allDay = <({CalendarShownEntry<T> shown, int first, int last})>[];
    final above = List<int>.filled(tracks.columnCount, 0);
    final below = List<int>.filled(tracks.columnCount, 0);
    var offDays = 0;
    final loose = <CalendarShownEntry<T>>[];
    for (final entry in shown) {
      final start = entry.entry.start;
      final end = entry.entry.end;
      final firstDay = dayNumber(start);
      final lastDay = lastDayNumberOf(start, end);
      final first = tracks.firstColumnFrom(firstDay);
      final last = tracks.lastColumnUpTo(lastDay);
      if (last < first) {
        offDays++;
        if (!entry.entry.isAllDay) {
          loose.add(entry);
        }
        continue;
      }
      if (entry.entry.isAllDay) {
        allDay.add((shown: entry, first: first, last: last));
        continue;
      }
      // Fewer columns than days of the range covered: a day with none.
      var missed =
          last - first + 1 <
          math.min(lastDay, tracks.lastDay) -
              math.max(firstDay, tracks.firstDay) +
              1;
      final span = wallSpanOf(start, end);
      for (var column = first; column <= last; column++) {
        final day = tracks.dayAt(column);
        final piece = pieceOn(span, day);
        if (piece == null) {
          continue;
        }
        if (piece.end <= hours.start) {
          above[column - 1]++;
          missed = true;
        } else if (piece.start >= hours.end) {
          below[column - 1]++;
          missed = true;
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
          if (tracks.repeatsStretchAt(column)) {
            missed = true;
          }
        }
      }
      if (missed) {
        loose.add(entry);
      }
    }
    final stacked = _stackBars(tracks, allDay);
    return TimedGridLayout<T>._(
      (
        shown: shown,
        firstDay: tracks.firstDay,
        dayCount: tracks.dayCount,
        weekdays: tracks.weekdays,
        hours: tracks.hours,
      ),
      pieces: pieces,
      bars: stacked.bars,
      barRows: stacked.rows,
      below: stacked.below,
      hidden: GridHiddenCounts(tracks, above, below, offDays),
      loose: loose.isEmpty ? null : (GridOverlapIndex()..addAll(loose)),
    );
  }

  /// The entry list the split read, with the days, weekdays and hours it
  /// split them for, never the slot length or the rows, which it does not
  /// read; null for [TimedGridLayout.empty].
  final ({
    List<CalendarShownEntry<T>> shown,
    int firstDay,
    int dayCount,
    CalendarWeekdaySet weekdays,
    CalendarDayHours hours,
  })?
  _read;

  /// The pieces of the shown timed entries, in the store's order.
  final List<GridPiece<T>> pieces;

  /// The bars of the shown all-day entries, in [barRows] rows.
  final List<GridBar<T>> bars;

  /// The strip rows [bars] are stacked in.
  final int barRows;

  /// On each day column, `below[c - 1]` for column `c`, the bars below the
  /// strip's first [collapsedStripRows] rows.
  final List<int> below;

  /// The shown entries with no block or bar, counted.
  final GridHiddenCounts hidden;

  /// The shown timed entries whose time the board's pieces in the rows a
  /// change covers can miss, or null where there are none.
  final GridOverlapIndex? loose;

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

  /// The bars of [allDay], each an all-day entry over the shown columns
  /// from `first` to `last`, stacked in the strip's rows: taken by first
  /// column, then more columns first, then start, title and id, each takes
  /// the lowest row free at its first column, a row freeing once the sweep
  /// passes the last column of the bar in it. The rows in use are kept in
  /// a min-heap by last column and the free ones in a min-heap by row, so
  /// the stack is O(n log n). Also counts, per column, the bars below the
  /// third row.
  static ({List<GridBar<T>> bars, int rows, List<int> below}) _stackBars<T>(
    GridTracks tracks,
    List<({CalendarShownEntry<T> shown, int first, int last})> allDay,
  ) {
    final below = List<int>.filled(tracks.columnCount, 0);
    if (allDay.isEmpty) {
      return (bars: <GridBar<T>>[], rows: 0, below: below);
    }
    allDay.sort((a, b) {
      final byFirst = a.first.compareTo(b.first);
      if (byFirst != 0) {
        return byFirst;
      }
      final byWidth = (b.last - b.first).compareTo(a.last - a.first);
      if (byWidth != 0) {
        return byWidth;
      }
      final byStart = a.shown.entry.start.compareTo(b.shown.entry.start);
      if (byStart != 0) {
        return byStart;
      }
      final byTitle = a.shown.entry.title.compareTo(b.shown.entry.title);
      if (byTitle != 0) {
        return byTitle;
      }
      return a.shown.id.compareTo(b.shown.id);
    });
    // A row in use is held as `last * stride + row`, so the heap's least is
    // the row whose bar ends at the earliest column.
    final stride = allDay.length;
    final used = _IntHeap();
    final free = _IntHeap();
    var rows = 0;
    final bars = <GridBar<T>>[];
    for (final bar in allDay) {
      while (used.isNotEmpty && used.peek ~/ stride < bar.first) {
        free.push(used.pop() % stride);
      }
      final row = free.isNotEmpty ? free.pop() : rows++;
      used.push(bar.last * stride + row);
      final entry = bar.shown.entry;
      final firstDay = tracks.dayAt(bar.first);
      final lastDay = tracks.dayAt(bar.last);
      bars.add(
        GridBar<T>(
          shown: bar.shown,
          firstDay: firstDay,
          lastDay: lastDay,
          row: row,
          continuesBefore: dayNumber(entry.start) < firstDay,
          continuesAfter: lastDayNumberOf(entry.start, entry.end) > lastDay,
        ),
      );
      if (row >= collapsedStripRows) {
        for (var column = bar.first; column <= bar.last; column++) {
          below[column - 1]++;
        }
      }
    }
    return (bars: bars, rows: rows, below: below);
  }
}

/// A binary min-heap of integers.
class _IntHeap {
  final List<int> _values = <int>[];

  bool get isNotEmpty {
    return _values.isNotEmpty;
  }

  /// The least value; the heap is not empty.
  int get peek {
    return _values.first;
  }

  void push(int value) {
    _values.add(value);
    var at = _values.length - 1;
    while (at > 0) {
      final parent = (at - 1) >> 1;
      if (_values[parent] <= value) {
        break;
      }
      _values[at] = _values[parent];
      at = parent;
    }
    _values[at] = value;
  }

  /// Removes and returns the least value; the heap is not empty.
  int pop() {
    final least = _values.first;
    final last = _values.removeLast();
    if (_values.isNotEmpty) {
      var at = 0;
      final count = _values.length;
      while (true) {
        final left = 2 * at + 1;
        if (left >= count) {
          break;
        }
        final right = left + 1;
        final child = right < count && _values[right] < _values[left]
            ? right
            : left;
        if (_values[child] >= last) {
          break;
        }
        _values[at] = _values[child];
        at = child;
      }
      _values[at] = last;
    }
    return least;
  }
}
