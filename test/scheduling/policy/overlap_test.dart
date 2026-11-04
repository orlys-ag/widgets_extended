/// The overlap rule over instants: half-open start-to-end intervals that
/// intersect, across midnight too, and all-day entries that share time
/// with nothing; and the policy forbidding overlaps refusing each pair.
library;

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);

CalendarEntry<String> entryOf(
  String id,
  DateTime start,
  DateTime end, {
  bool isAllDay = false,
}) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: id,
    color: const Color(0xFF336699),
    payload: id,
    isAllDay: isAllDay,
  );
}

void main() {
  test("OV1 Monday 23:00 to Tuesday 01:00 shares time with Tuesday 00:30 "
      "to 01:30", () {
    final late = entryOf(
      "late",
      DateTime(2026, 4, 20, 23),
      DateTime(2026, 4, 21, 1),
    );
    final early = entryOf(
      "early",
      DateTime(2026, 4, 21, 0, 30),
      DateTime(2026, 4, 21, 1, 30),
    );
    expect(NoOverlapsPolicy.entriesShareTime(late, early), isTrue);
    expect(NoOverlapsPolicy.entriesShareTime(early, late), isTrue);
    expect(
      NoOverlapsPolicy.rangeSharesTime(late.start, late.end, early),
      isTrue,
    );
    expect(
      NoOverlapsPolicy.timesOverlap(
        late.start,
        late.end,
        early.start,
        early.end,
      ),
      isTrue,
    );
    // The same minutes a day apart share none.
    final nextDay = entryOf(
      "next",
      DateTime(2026, 4, 22, 0, 30),
      DateTime(2026, 4, 22, 1, 30),
    );
    expect(NoOverlapsPolicy.entriesShareTime(late, nextDay), isFalse);
  });

  test("OV2 09:00-10:00 and 10:00-11:00 do not share time, the intervals "
      "being half-open", () {
    final nine = entryOf(
      "nine",
      DateTime(2026, 4, 21, 9),
      DateTime(2026, 4, 21, 10),
    );
    final ten = entryOf(
      "ten",
      DateTime(2026, 4, 21, 10),
      DateTime(2026, 4, 21, 11),
    );
    expect(NoOverlapsPolicy.entriesShareTime(nine, ten), isFalse);
    expect(NoOverlapsPolicy.entriesShareTime(ten, nine), isFalse);
    expect(
      NoOverlapsPolicy.timesOverlap(nine.start, nine.end, ten.start, ten.end),
      isFalse,
    );
    final longer = entryOf(
      "longer",
      DateTime(2026, 4, 21, 9),
      DateTime(2026, 4, 21, 10, 1),
    );
    expect(NoOverlapsPolicy.entriesShareTime(longer, ten), isTrue);
  });

  test("OV3 an all-day entry shares time with neither a timed nor an "
      "all-day entry, in both argument orders", () {
    final allDay = entryOf(
      "all-day",
      tuesday,
      DateTime(2026, 4, 22),
      isAllDay: true,
    );
    final other = entryOf(
      "other",
      monday,
      DateTime(2026, 4, 23),
      isAllDay: true,
    );
    final timed = entryOf(
      "timed",
      DateTime(2026, 4, 21, 9),
      DateTime(2026, 4, 21, 10),
    );
    // Their instants do meet.
    expect(
      NoOverlapsPolicy.timesOverlap(
        allDay.start,
        allDay.end,
        timed.start,
        timed.end,
      ),
      isTrue,
    );
    expect(NoOverlapsPolicy.entriesShareTime(allDay, timed), isFalse);
    expect(NoOverlapsPolicy.entriesShareTime(timed, allDay), isFalse);
    expect(NoOverlapsPolicy.entriesShareTime(allDay, other), isFalse);
    expect(NoOverlapsPolicy.entriesShareTime(other, allDay), isFalse);
    expect(
      NoOverlapsPolicy.rangeSharesTime(timed.start, timed.end, allDay),
      isFalse,
    );
    expect(
      NoOverlapsPolicy.rangeSharesTime(allDay.start, allDay.end, timed),
      isTrue,
    );
  });

  test("OV4 a timed entry from Tuesday's start to Wednesday's shares time "
      "with Tuesday 10:00 to 11:00, in both argument orders", () {
    final whole = entryOf("whole", tuesday, wednesday);
    final ten = entryOf(
      "ten",
      DateTime(2026, 4, 21, 10),
      DateTime(2026, 4, 21, 11),
    );
    expect(NoOverlapsPolicy.entriesShareTime(whole, ten), isTrue);
    expect(NoOverlapsPolicy.entriesShareTime(ten, whole), isTrue);
  });

  test("OV5 an all-day entry over Tuesday shares no time with a timed entry "
      "over the same day or with Tuesday 10:00 to 11:00, in both argument "
      "orders", () {
    final allDay = entryOf("all-day", tuesday, wednesday, isAllDay: true);
    final whole = entryOf("whole", tuesday, wednesday);
    final ten = entryOf(
      "ten",
      DateTime(2026, 4, 21, 10),
      DateTime(2026, 4, 21, 11),
    );
    for (final timed in <CalendarEntry<String>>[whole, ten]) {
      // Their instants do meet.
      expect(
        NoOverlapsPolicy.timesOverlap(
          allDay.start,
          allDay.end,
          timed.start,
          timed.end,
        ),
        isTrue,
        reason: timed.id,
      );
      expect(
        NoOverlapsPolicy.entriesShareTime(allDay, timed),
        isFalse,
        reason: timed.id,
      );
      expect(
        NoOverlapsPolicy.entriesShareTime(timed, allDay),
        isFalse,
        reason: timed.id,
      );
    }
  });

  test("OV6 the policy forbidding overlaps refuses each pair that shares "
      "time: timed with timed, across midnight, a move's candidate and a "
      "create's", () {
    const policy = NoOverlapsPolicy<String>();
    final late = entryOf(
      "late",
      DateTime(2026, 4, 20, 23),
      DateTime(2026, 4, 21, 1),
    );
    final early = entryOf(
      "early",
      DateTime(2026, 4, 21, 0, 30),
      DateTime(2026, 4, 21, 1, 30),
    );
    final nine = entryOf(
      "nine",
      DateTime(2026, 4, 21, 9),
      DateTime(2026, 4, 21, 10),
    );
    final half = entryOf(
      "half",
      DateTime(2026, 4, 21, 9, 30),
      DateTime(2026, 4, 21, 10, 30),
    );
    final pairs = <(CalendarOverlapCandidate<String>, CalendarEntry<String>)>[
      (
        CalendarOverlapCandidate<String>(
          start: nine.start,
          end: nine.end,
          entry: nine,
        ),
        half,
      ),
      (
        CalendarOverlapCandidate<String>(
          start: late.start,
          end: late.end,
          entry: late,
        ),
        early,
      ),
      (
        CalendarOverlapCandidate<String>(
          start: DateTime(2026, 4, 21),
          end: DateTime(2026, 4, 21, 0, 15),
        ),
        late,
      ),
    ];
    for (final (candidate, other) in pairs) {
      // Setup sanity: the pair shares time.
      expect(
        NoOverlapsPolicy.rangeSharesTime(candidate.start, candidate.end, other),
        isTrue,
        reason: "$candidate, ${other.id}",
      );
      expect(
        policy.mayOverlap(candidate, other),
        isFalse,
        reason: "$candidate, ${other.id}",
      );
    }
  });
}
