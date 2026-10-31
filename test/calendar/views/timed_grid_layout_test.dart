/// The timed grid's layout of its entries, made without a widget: the
/// pieces of timed entries, the entries it has no block for and those it
/// indexes as loose, the bars of all-day entries stacked in rows, the
/// split it keeps for the same input, and the overlap index's search.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/views/entry_split.dart';
import 'package:widgets_extended/calendar/views/timed_grid_layout.dart';

import '../dst_days.dart';

/// Monday, April 20 2026, the first day of the tracks the tests lay out.
final DateTime monday = DateTime(2026, 4, 20);

/// The [offset]th day after [monday], at local midnight.
DateTime dayAfterMonday(int offset) {
  return DateTime(monday.year, monday.month, monday.day + offset);
}

/// The [dayNumber] of the [offset]th day after [monday].
int dayFromMonday(int offset) {
  return dayNumber(dayAfterMonday(offset));
}

/// [day] at [hour] and [minute] by the wall clock.
DateTime at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

CalendarEntry<String> entryOf(
  String id,
  DateTime start,
  DateTime end, {
  String? title,
}) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: title ?? id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

CalendarShownEntry<String> shownOf(
  String id,
  DateTime start,
  DateTime end, {
  String? title,
  bool pending = false,
}) {
  return CalendarShownEntry<String>(
    entryOf(id, start, end, title: title),
    pending: pending,
  );
}

/// An all-day entry over the [days] days from [first].
CalendarShownEntry<String> allDayOf(
  String id,
  DateTime first,
  int days, {
  String? title,
}) {
  return shownOf(
    id,
    first,
    DateTime(first.year, first.month, first.day + days),
    title: title,
  );
}

/// The week from [monday] with a column for each workday, in office hours.
GridTracks workweek({
  int slotMinutes = defaultSlotMinutes,
  int firstSlotRow = 1,
  CalendarDayHours hours = const CalendarDayHours(8 * 60, 18 * 60),
  CalendarWeekdaySet weekdays = CalendarWeekdaySet.workweek,
  int firstOffset = 0,
  int dayCount = 7,
}) {
  return GridTracks(
    firstDay: dayFromMonday(firstOffset),
    dayCount: dayCount,
    weekdays: weekdays,
    hours: hours,
    firstSlotRow: firstSlotRow,
    slotMinutes: slotMinutes,
  );
}

void main() {
  final tuesday = dayAfterMonday(1);
  final wednesday = dayAfterMonday(2);
  final thursday = dayAfterMonday(3);
  final friday = dayAfterMonday(4);
  final saturday = dayAfterMonday(5);
  final sunday = dayAfterMonday(6);

  test("GL1 a timed entry has one piece on each shown day it covers inside "
      "the hours, marking its first and last days, in the store's order", () {
    final a = shownOf("a", at(tuesday, 10), at(tuesday, 11));
    final b = shownOf("b", at(wednesday, 16), at(thursday, 10));
    final layout = TimedGridLayout<String>.of(<CalendarShownEntry<String>>[
      a,
      b,
    ], workweek());
    expect(layout.pieces, <GridPiece<String>>[
      GridPiece<String>(
        shown: a,
        day: dayFromMonday(1),
        start: 10 * 60,
        end: 11 * 60,
        first: true,
        last: true,
      ),
      GridPiece<String>(
        shown: b,
        day: dayFromMonday(2),
        start: 16 * 60,
        end: 24 * 60,
        first: true,
        last: false,
      ),
      GridPiece<String>(
        shown: b,
        day: dayFromMonday(3),
        start: 0,
        end: 10 * 60,
        first: false,
        last: true,
      ),
    ]);
    expect(layout.loose, isNull);
    expect(layout.hidden, GridHiddenCounts.none(workweek()));
  });

  test("GL2 a piece wholly before or after the hours is counted on its "
      "column, an entry on no shown day is counted once, and each such timed "
      "entry, and one covering a day with no column, is loose", () {
    final tracks = workweek();
    final layout = TimedGridLayout<String>.of(<CalendarShownEntry<String>>[
      shownOf("early", at(tuesday, 6), at(tuesday, 7)),
      shownOf("late", at(wednesday, 19), at(wednesday, 20)),
      shownOf("weekend", at(saturday, 10), at(saturday, 11)),
      allDayOf("saturday", saturday, 1),
      shownOf("across", at(friday, 16), at(sunday, 10)),
      shownOf("inside", at(thursday, 10), at(thursday, 11)),
    ], tracks);
    expect(
      layout.hidden,
      GridHiddenCounts(tracks, <int>[0, 1, 0, 0, 0], <int>[0, 0, 1, 0, 0], 2),
    );
    expect((layout.hidden.rowAbove, layout.hidden.rowBelow), (true, true));
    expect(layout.loose?.ids, <String>{"early", "late", "weekend", "across"});
    expect(
      <String>[for (final piece in layout.pieces) piece.shown.id],
      <String>["across", "inside"],
    );
  });

  test("GL3 a bar takes the lowest row free at its first column, the bars "
      "taken by first column and then the wider first", () {
    final layout = TimedGridLayout<String>.of(<CalendarShownEntry<String>>[
      allDayOf("mon", monday, 1),
      allDayOf("wide", monday, 3),
      allDayOf("tue", tuesday, 1),
      allDayOf("thu", thursday, 1),
    ], workweek());
    expect(
      <(String, int)>[for (final bar in layout.bars) (bar.shown.id, bar.row)],
      <(String, int)>[("wide", 0), ("mon", 1), ("tue", 1), ("thu", 0)],
    );
    expect(layout.barRows, 2);
  });

  test("GL4 bars on the same columns are taken by start, then title, then "
      "id; a bar continues past the days the tracks show; and the bars below "
      "the strip's collapsed rows are counted on each column", () {
    final layout = TimedGridLayout<String>.of(<CalendarShownEntry<String>>[
      allDayOf("mon", monday, 1, title: "c"),
      allDayOf("t2", monday, 1, title: "b"),
      allDayOf("t1", monday, 1, title: "b"),
      allDayOf("early", dayAfterMonday(-1), 2, title: "z"),
      allDayOf("fri", friday, 3),
    ], workweek());
    expect(
      <(String, int)>[for (final bar in layout.bars) (bar.shown.id, bar.row)],
      <(String, int)>[
        ("early", 0),
        ("t1", 1),
        ("t2", 2),
        ("mon", 3),
        ("fri", 0),
      ],
    );
    expect(collapsedStripRows, 3);
    expect(layout.below, <int>[1, 0, 0, 0, 0]);
    expect(layout.barRows, 4);
    final early = layout.bars.first;
    expect(
      (early.firstDay, early.lastDay, early.continuesBefore),
      (dayFromMonday(0), dayFromMonday(0), true),
    );
    expect(early.continuesAfter, isFalse);
    final fri = layout.bars.last;
    expect(
      (fri.firstDay, fri.lastDay, fri.continuesAfter),
      (dayFromMonday(4), dayFromMonday(4), true),
    );
    expect(fri.continuesBefore, isFalse);
  });

  test("GL5 the split of the identical entries on the same days, weekdays "
      "and hours is the previous one and counts no split, whatever the slots "
      "and rows; any other input splits again", () {
    final a = shownOf("a", at(tuesday, 10), at(tuesday, 11));
    final b = shownOf("b", at(wednesday, 10), at(wednesday, 11));
    final shown = <CalendarShownEntry<String>>[a, b];
    debugEntrySplitCount = 0;
    final previous = TimedGridLayout<String>.of(shown, workweek());
    expect(debugEntrySplitCount, 1);
    final kept = TimedGridLayout<String>.of(
      <CalendarShownEntry<String>>[a, b],
      workweek(slotMinutes: 30, firstSlotRow: 4),
      previous: previous,
    );
    expect(identical(kept, previous), isTrue);
    expect(debugEntrySplitCount, 1);

    final others = <String, (List<CalendarShownEntry<String>>, GridTracks)>{
      "a pending flag": (
        <CalendarShownEntry<String>>[
          a,
          CalendarShownEntry<String>(b.entry, pending: true),
        ],
        workweek(),
      ),
      "an equal entry not identical": (
        <CalendarShownEntry<String>>[
          a,
          shownOf("b", at(wednesday, 10), at(wednesday, 11)),
        ],
        workweek(),
      ),
      "another order": (<CalendarShownEntry<String>>[b, a], workweek()),
      "fewer entries": (<CalendarShownEntry<String>>[a], workweek()),
      "other hours": (
        shown,
        workweek(hours: const CalendarDayHours(9 * 60, 18 * 60)),
      ),
      "other weekdays": (shown, workweek(weekdays: CalendarWeekdaySet.all)),
      "another first day": (shown, workweek(firstOffset: -7)),
      "another day count": (shown, workweek(dayCount: 5)),
    };
    for (final MapEntry(key: name, value: (entries, tracks))
        in others.entries) {
      final before = debugEntrySplitCount;
      final next = TimedGridLayout<String>.of(
        entries,
        tracks,
        previous: previous,
      );
      expect(identical(next, previous), isFalse, reason: name);
      expect(debugEntrySplitCount, before + 1, reason: name);
    }

    final empty = TimedGridLayout<String>.empty(workweek());
    final first = TimedGridLayout<String>.of(
      <CalendarShownEntry<String>>[],
      workweek(),
      previous: empty,
    );
    expect(identical(first, empty), isFalse);
  });

  group("on the 25-hour day", skip: longDaySkip, () {
    test("GL6 a piece on a day whose clock repeats a stretch is loose, its "
        "rows not ordering as its instants do", () {
      final day = longDayStart;
      final layout = TimedGridLayout<String>.of(<CalendarShownEntry<String>>[
        shownOf("repeated", at(day, 10), at(day, 11)),
      ], GridTracks(firstDay: dayNumber(day), dayCount: 1));
      expect(layout.pieces, hasLength(1));
      expect(layout.loose?.ids, <String>{"repeated"});
    });
  });

  test("GL7 the overlap index finds an entry other than the one asked "
      "about that shares time with a range, and none where only that one "
      "does", () {
    final own = entryOf("own", at(tuesday, 10), at(tuesday, 11));
    final index = GridOverlapIndex()
      ..addAll(<CalendarShownEntry<String>>[
        CalendarShownEntry<String>(own, pending: false),
        shownOf("other", at(tuesday, 12), at(tuesday, 13)),
        allDayOf("bar", tuesday, 1),
      ]);
    expect(index.ids, <String>{"own", "other"});
    expect(
      index.sharesTime("own", own, at(tuesday, 10, 30), at(tuesday, 11, 30)),
      isFalse,
    );
    expect(
      index.sharesTime("own", own, at(tuesday, 11, 30), at(tuesday, 12, 30)),
      isTrue,
    );
    expect(
      index.sharesTime("new", own, at(tuesday, 10, 30), at(tuesday, 10, 45)),
      isTrue,
    );
    expect(
      index.sharesTime("own", own, at(tuesday, 11), at(tuesday, 12)),
      isFalse,
    );
    expect(
      index.sharesTime("own", own, at(tuesday, 9), at(tuesday, 12, 15)),
      isTrue,
    );
  });
}
