/// The edit policy: the permissive answers a policy overriding nothing
/// gives, the unrestricted policy's equality, the time a policy answers at,
/// and the rounding of an earliest start to the slot grid.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/edit_policy.dart';

/// A Tuesday.
final DateTime tuesday = DateTime(2026, 4, 21);

final DateTime monday = DateTime(2026, 4, 20);
final DateTime wednesday = DateTime(2026, 4, 22);

/// [day] at [hour], [minute] and [second] by the wall clock.
DateTime at(DateTime day, int hour, [int minute = 0, int second = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute, second);
}

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

/// A policy that overrides nothing.
class _Plain extends CalendarEditPolicy<String> {
  const _Plain();
}

void main() {
  test("EP1 a const policy overriding nothing moves, resizes both edges, "
      "edits, deletes and admits every change, lets a new entry start from "
      "a day's start, limits no day count and allows overlaps", () {
    const policy = _Plain();
    final now = CalendarNow(time: at(tuesday, 11, 7), today: tuesday);
    final past = entryOf("past", at(monday, 9), at(monday, 10));
    expect(policy.mayMove(past, now), isTrue);
    expect(policy.mayEdit(past, now), isTrue);
    expect(policy.mayDelete(past, now), isTrue);
    final edges = policy.resizableEdges(past, now);
    expect(edges, CalendarResizeEdges.both);
    expect((edges.hasStart, edges.hasEnd), (true, true));
    // A move into the past, and a resize of the start.
    expect(
      policy.admitsChange(past, at(monday, 7), at(monday, 8), now),
      isTrue,
    );
    expect(
      policy.admitsChange(past, at(monday, 8), at(monday, 10), now),
      isTrue,
    );
    expect(policy.earliestStartOn(monday, now), monday);
    expect(policy.dayLimit, isNull);
    expect(policy.allowsOverlaps, isTrue);
  });

  test("EP2 two unrestricted policies are equal with equal hash codes, one "
      "forbidding overlaps is not, and the default allows overlaps and "
      "limits no day count", () {
    const constant = UnrestrictedEditPolicy<String>();
    // ignore: prefer_const_constructors
    final built = UnrestrictedEditPolicy<String>();
    expect(built, constant);
    expect(built.hashCode, constant.hashCode);
    const forbidding = UnrestrictedEditPolicy<String>(allowsOverlaps: false);
    expect(forbidding, isNot(constant));
    expect(constant, isNot(forbidding));
    expect(constant.allowsOverlaps, isTrue);
    expect(forbidding.allowsOverlaps, isFalse);
    expect(constant.dayLimit, isNull);
  });

  test("EP3 a CalendarNow takes today to its midnight, rounds the time of "
      "day on today up to a whole minute, and compares by its time and "
      "today", () {
    CalendarNow nowAt(DateTime time, [DateTime? today]) {
      return CalendarNow(time: time, today: today ?? tuesday);
    }

    expect(nowAt(at(tuesday, 11, 7), at(tuesday, 15)).today, tuesday);
    expect(nowAt(at(tuesday, 11, 7)).timeOnToday, at(tuesday, 11, 7));
    expect(nowAt(at(tuesday, 11, 7, 30)).timeOnToday, at(tuesday, 11, 8));
    expect(
      nowAt(DateTime(2026, 4, 21, 11, 7, 0, 0, 1)).timeOnToday,
      at(tuesday, 11, 8),
    );
    expect(nowAt(at(tuesday, 23, 59, 30)).timeOnToday, wednesday);
    // The host pins today to Wednesday while the clock reads Tuesday.
    expect(
      nowAt(at(tuesday, 11, 7, 30), wednesday).timeOnToday,
      at(wednesday, 11, 8),
    );
    final now = nowAt(at(tuesday, 11, 7, 30));
    final same = nowAt(at(tuesday, 11, 7, 30), at(tuesday, 9));
    expect(same, now);
    expect(same.hashCode, now.hashCode);
    expect(nowAt(at(tuesday, 11, 7, 31)), isNot(now));
    expect(nowAt(at(tuesday, 11, 7, 30), wednesday), isNot(now));
  });

  test("EP4 earliestSlotMinuteOf answers none for no start and for one on a "
      "later day, 0 from the day's start and before it, and a later start's "
      "minute, one more inside a minute, rounded up to the slot grid", () {
    int minuteOf(DateTime? earliest) {
      return earliestSlotMinuteOf(tuesday, earliest, slotMinutes: 15);
    }

    expect(minuteOf(null), minutesPerDay);
    expect(minuteOf(wednesday), minutesPerDay);
    expect(minuteOf(at(wednesday, 9)), minutesPerDay);
    expect(minuteOf(tuesday), 0);
    expect(minuteOf(at(monday, 22)), 0);
    expect(minuteOf(at(tuesday, 11, 7)), 675);
    expect(minuteOf(at(tuesday, 11, 15)), 675);
    expect(minuteOf(at(tuesday, 11, 15, 30)), 690);
  });
}
