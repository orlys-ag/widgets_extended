/// The overlap rule over instants: half-open start-to-end intervals that
/// intersect, across midnight too, and all-day entries that share time
/// with nothing.
library;

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/overlap.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);

CalendarEntry<String> entryOf(String id, DateTime start, DateTime end) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: id,
    color: const Color(0xFF336699),
    payload: id,
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
    expect(entriesShareTime(late, early), isTrue);
    expect(entriesShareTime(early, late), isTrue);
    expect(rangeSharesTime(late.start, late.end, early), isTrue);
    expect(
      timesOverlap(late.start, late.end, early.start, early.end),
      isTrue,
    );
    // The same minutes a day apart share none.
    final nextDay = entryOf(
      "next",
      DateTime(2026, 4, 22, 0, 30),
      DateTime(2026, 4, 22, 1, 30),
    );
    expect(entriesShareTime(late, nextDay), isFalse);
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
    expect(entriesShareTime(nine, ten), isFalse);
    expect(entriesShareTime(ten, nine), isFalse);
    expect(
      timesOverlap(nine.start, nine.end, ten.start, ten.end),
      isFalse,
    );
    final longer = entryOf(
      "longer",
      DateTime(2026, 4, 21, 9),
      DateTime(2026, 4, 21, 10, 1),
    );
    expect(entriesShareTime(longer, ten), isTrue);
  });

  test("OV3 an all-day entry shares time with neither a timed nor an "
      "all-day entry, in both argument orders", () {
    final allDay = entryOf("all-day", tuesday, DateTime(2026, 4, 22));
    final other = entryOf("other", monday, DateTime(2026, 4, 23));
    final timed = entryOf(
      "timed",
      DateTime(2026, 4, 21, 9),
      DateTime(2026, 4, 21, 10),
    );
    // Their instants do meet.
    expect(
      timesOverlap(allDay.start, allDay.end, timed.start, timed.end),
      isTrue,
    );
    expect(entriesShareTime(allDay, timed), isFalse);
    expect(entriesShareTime(timed, allDay), isFalse);
    expect(entriesShareTime(allDay, other), isFalse);
    expect(entriesShareTime(other, allDay), isFalse);
    expect(rangeSharesTime(timed.start, timed.end, allDay), isFalse);
    expect(rangeSharesTime(allDay.start, allDay.end, timed), isTrue);
  });
}
