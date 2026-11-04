/// The timed grid's layout of its entries, made without a widget: the
/// pieces of timed entries, the entries it has no block for and those it
/// indexes as loose, the bars of all-day entries stacked in rows, the
/// split it keeps for the same input, and the overlap index's searches.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/store/calendar_store.dart';
import 'package:widgets_extended/calendar/views/entry_split.dart';
import 'package:widgets_extended/calendar/views/timed_grid_layout.dart';

import '../../scheduling/dst_days.dart';

/// Monday, April 20 2026, the first day of the tracks the tests lay out.
final DateTime monday = DateTime(2026, 4, 20);

/// The [offset]th day after [monday], at local midnight.
DateTime dayAfterMonday(int offset) {
  return DateTime(monday.year, monday.month, monday.day + offset);
}

/// The [CalendarDates.dayNumber] of the [offset]th day after [monday].
int dayFromMonday(int offset) {
  return CalendarDates.dayNumber(dayAfterMonday(offset));
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
  bool isAllDay = false,
}) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: title ?? id,
    color: const Color(0xFF336699),
    payload: id,
    isAllDay: isAllDay,
  );
}

CalendarShownEntry<String> shownOf(
  String id,
  DateTime start,
  DateTime end, {
  String? title,
  bool pending = false,
  bool isAllDay = false,
}) {
  return CalendarShownEntry<String>(
    entryOf(id, start, end, title: title, isAllDay: isAllDay),
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
    isAllDay: true,
  );
}

/// The week from [monday] with a column for each workday, in [hours], or
/// with none in office hours.
GridTracks workweek({
  int slotMinutes = CalendarDates.defaultSlotMinutes,
  int firstSlotRow = 1,
  CalendarDayHours? hours,
  CalendarWeekdaySet weekdays = CalendarWeekdaySet.workweek,
  int firstOffset = 0,
  int dayCount = 7,
}) {
  return GridTracks(
    firstDay: dayFromMonday(firstOffset),
    dayCount: dayCount,
    weekdays: weekdays,
    hours: hours ?? CalendarDayHours(8 * 60, 18 * 60),
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
        continuesAfter: false,
      ),
      GridPiece<String>(
        shown: b,
        day: dayFromMonday(2),
        start: 16 * 60,
        end: 24 * 60,
        first: true,
        last: false,
        continuesAfter: true,
      ),
      GridPiece<String>(
        shown: b,
        day: dayFromMonday(3),
        start: 0,
        end: 10 * 60,
        first: false,
        last: true,
        continuesAfter: false,
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
        workweek(hours: CalendarDayHours(9 * 60, 18 * 60)),
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
      ], GridTracks(firstDay: CalendarDates.dayNumber(day), dayCount: 1));
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

  test("GL10 the overlap index finds the first entry other than the one "
      "asked about, in start order, that shares a range's time and that "
      "the policy refuses, asking only about the entries sharing it, in "
      "start order up to that one, and visiting a bounded count of its "
      "nodes", () {
    // Sixty timed entries over Tuesday, the last alone from 22:00 to
    // 22:30, the others ending by 21:00, and two all-day entries over it.
    final timed = <CalendarEntry<String>>[
      for (var i = 0; i < 59; i++)
        i % 20 == 0
            ? entryOf("e$i", at(tuesday, 0, i * 10), at(tuesday, 10, i * 10))
            : entryOf(
                "e$i",
                at(tuesday, 0, i * 97 % 1080),
                at(tuesday, 0, i * 97 % 1080 + 5 + i * 61 % 175),
              ),
      entryOf("e59", at(tuesday, 22), at(tuesday, 22, 30)),
    ];
    final index = GridOverlapIndex<String>()
      ..addAll(<CalendarShownEntry<String>>[
        for (final entry in timed)
          CalendarShownEntry<String>(entry, pending: false),
        allDayOf("bar", tuesday, 1),
        allDayOf("wide", monday, 3),
      ]);
    // Setup sanity: every timed entry is held, and no all-day one.
    expect(index.ids, hasLength(60));
    final byStart = <CalendarEntry<String>>[...timed]
      ..sort((a, b) {
        final order = a.start.compareTo(b.start);
        return order != 0 ? order : a.id!.compareTo(b.id!);
      });
    // log2(60), the implicit tree's height.
    const height = 5;
    final refused = <String>{for (var i = 0; i < 60; i += 7) "e$i"};
    final elsewhere = entryOf("new", at(wednesday, 9), at(wednesday, 10));
    var asking = 0;
    for (var j = 0; j < 42; j++) {
      // Forty ranges over the entries, then one over "e59" alone and one
      // over no entry.
      final ({
        String id,
        CalendarEntry<String> own,
        DateTime start,
        DateTime end,
      })
      query;
      if (j == 40) {
        query = (
          id: "e59",
          own: timed.last,
          start: at(tuesday, 22, 5),
          end: at(tuesday, 22, 20),
        );
      } else if (j == 41) {
        query = (
          id: "new",
          own: elsewhere,
          start: at(tuesday, 23),
          end: at(tuesday, 23, 30),
        );
      } else {
        final start = at(tuesday, 0, j * 131 % 1260);
        final own = j.isEven ? timed[j] : elsewhere;
        query = (
          id: own.id!,
          own: own,
          start: start,
          end: start.add(Duration(minutes: 5 + j * 47 % 300)),
        );
      }
      final sharing = <CalendarEntry<String>>[
        for (final entry in byStart)
          if (entry.id != query.id &&
              NoOverlapsPolicy.timesOverlap(
                query.start,
                query.end,
                entry.start,
                entry.end,
              ))
            entry,
      ];
      final refusal = sharing.indexWhere((entry) {
        return refused.contains(entry.id);
      });
      final expectedAsks = <String>[
        for (final entry
            in refusal < 0 ? sharing : sharing.sublist(0, refusal + 1))
          entry.id!,
      ];
      final policy = _PairRecording(refused);
      final candidate = CalendarOverlapCandidate<String>(
        start: query.start,
        end: query.end,
      );
      final visitsBefore = debugOverlapIndexVisitCount;
      final answer = index.refusesOverlap(
        query.id,
        query.own,
        candidate,
        policy,
      );
      final visits = debugOverlapIndexVisitCount - visitsBefore;
      final reason = "${query.id} ${query.start} to ${query.end}";
      expect(answer, refusal >= 0, reason: reason);
      expect(policy.asked, expectedAsks, reason: reason);
      for (final other in policy.candidates) {
        expect(identical(other, candidate), isTrue, reason: reason);
      }
      final asks = policy.asked.length;
      expect(
        visits,
        lessThanOrEqualTo(1 + 2 * (asks + 2) * (height + 1)),
        reason: reason,
      );
      if (j >= 40) {
        expect(sharing, isEmpty, reason: reason);
        expect(visits, 0, reason: reason);
      }
      if (asks > 0) {
        asking++;
      }
    }
    // Setup sanity: the ranges ask, and some are refused partway.
    expect(asking, greaterThan(30));

    // 1024 entries back to back, five minutes each, from Monday's start.
    final packed = GridOverlapIndex<String>()
      ..addAll(<CalendarShownEntry<String>>[
        for (var k = 0; k < 1024; k++)
          shownOf(
            "b$k",
            monday.add(Duration(minutes: 5 * k)),
            monday.add(Duration(minutes: 5 * k + 5)),
          ),
      ]);
    final inside = CalendarOverlapCandidate<String>(
      start: monday.add(const Duration(minutes: 5001)),
      end: monday.add(const Duration(minutes: 5004)),
    );
    for (final refusing in <bool>[false, true]) {
      final policy = _PairRecording(
        refusing ? const <String>{"b1000"} : const <String>{},
      );
      final visitsBefore = debugOverlapIndexVisitCount;
      expect(packed.refusesOverlap("new", elsewhere, inside, policy), refusing);
      expect(policy.asked, <String>["b1000"]);
      // log2(1024) is 10: 1 + 2 * (1 + 2) * (10 + 1).
      expect(
        debugOverlapIndexVisitCount - visitsBefore,
        lessThanOrEqualTo(67),
        reason: "refusing: $refusing",
      );
    }
  });

  group(
    "on the day whose clock skips its midnight",
    skip: skippedMidnightSkip,
    () {
      test("GL8 a piece from the day's start starts at the minute its clock "
          "starts at, 01:00, and one continuing from the day before at its "
          "minute 0", () {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final early = shownOf("early", day, at(day, 2));
        final night = shownOf("night", at(before, 23), at(day, 2));
        final layout = TimedGridLayout<String>.of(<CalendarShownEntry<String>>[
          early,
          night,
        ], GridTracks(firstDay: CalendarDates.dayNumber(before), dayCount: 2));
        expect(
          <GridPiece<String>>[
            for (final piece in layout.pieces)
              if (piece.shown == early) piece,
          ],
          <GridPiece<String>>[
            GridPiece<String>(
              shown: early,
              day: CalendarDates.dayNumber(day),
              start: 60,
              end: 120,
              first: true,
              last: true,
              continuesAfter: false,
            ),
          ],
        );
        // Guard: red when a piece starts at its day's first minute the
        // clock reads.
        final nightOnDay = layout.pieces.singleWhere((piece) {
          return piece.shown == night &&
              piece.day == CalendarDates.dayNumber(day);
        });
        expect((nightOnDay.start, nightOnDay.end), (0, 120));
      });
    },
  );

  group(
    "on the day whose clock repeats its midnight",
    skip: repeatedMidnightSkip,
    () {
      test("GL9 an entry ending at the later 00:00 has a piece on the day "
          "before and its last on that day, from 00:00 to 01:00, and is "
          "loose for that day's repeated hour", () {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final late = shownOf("late", at(before, 23), laterMidnight);
        final layout = TimedGridLayout<String>.of(<CalendarShownEntry<String>>[
          late,
        ], GridTracks(firstDay: CalendarDates.dayNumber(before), dayCount: 2));
        expect(layout.pieces, <GridPiece<String>>[
          GridPiece<String>(
            shown: late,
            day: CalendarDates.dayNumber(before),
            start: 1380,
            end: 1440,
            first: true,
            last: false,
            continuesAfter: true,
          ),
          GridPiece<String>(
            shown: late,
            day: CalendarDates.dayNumber(day),
            start: 0,
            end: 60,
            first: false,
            last: true,
            continuesAfter: false,
          ),
        ]);
        expect(layout.loose?.ids, <String>{"late"});
      });
    },
  );
}

/// A policy limiting overlaps that refuses a pair where the other entry's
/// id is in [refused], recording the id of each other entry it is asked
/// about in [asked] and each candidate in [candidates]. Compared by
/// identity.
final class _PairRecording extends CalendarEditPolicy<String> {
  _PairRecording(this.refused);

  final Set<String> refused;

  final List<String> asked = <String>[];

  final List<CalendarOverlapCandidate<String>> candidates =
      <CalendarOverlapCandidate<String>>[];

  @override
  bool get allowsOverlaps {
    return false;
  }

  @override
  bool mayOverlap(
    CalendarOverlapCandidate<String> candidate,
    CalendarEntry<String> other,
  ) {
    asked.add(other.id!);
    candidates.add(candidate);
    return !refused.contains(other.id);
  }
}
