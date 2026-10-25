/// The history lock as an edit policy: its settings and equality, and the
/// answers it gives an entry ended, in progress or to come, and a new
/// entry's day.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/edit_policy.dart';
import 'package:widgets_extended/calendar/policy/history_lock_policy.dart';

/// A Tuesday.
final DateTime today = DateTime(2026, 4, 21);

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

/// The answers [policy] gives [entry] at [now] that take no change: may it
/// move, which edges, may it be edited, may it be deleted.
(bool, CalendarResizeEdges, bool, bool) answersOf(
  CalendarEditPolicy<String> policy,
  CalendarEntry<String> entry,
  CalendarNow now,
) {
  return (
    policy.mayMove(entry, now),
    policy.resizableEdges(entry, now),
    policy.mayEdit(entry, now),
    policy.mayDelete(entry, now),
  );
}

void main() {
  test("HP1 two default history locks are equal with equal hash codes, each "
      "setting makes one unequal, none equals the unrestricted policy, and "
      "the defaults lock no earlier time of today, allow overlaps and limit "
      "no day count", () {
    const constant = HistoryLockPolicy<String>();
    // ignore: prefer_const_constructors
    final built = HistoryLockPolicy<String>();
    expect(built, constant);
    expect(built.hashCode, constant.hashCode);
    expect(
      const HistoryLockPolicy<String>(lockEarlierToday: true),
      isNot(constant),
    );
    expect(
      const HistoryLockPolicy<String>(allowsOverlaps: false),
      isNot(constant),
    );
    expect(constant, isNot(const UnrestrictedEditPolicy<String>()));
    expect(const UnrestrictedEditPolicy<String>(), isNot(constant));
    expect((constant.lockEarlierToday, constant.allowsOverlaps), (false, true));
    expect(constant.dayLimit, isNull);
  });

  test("HP2 at Tuesday 11:07 an entry ended at today's start is locked, one "
      "in progress changes only its end, one from today's start is free, and "
      "with lockEarlierToday at 11:07:30 the boundary is 11:08, and at "
      "23:59:30 the next day's start", () {
    const policy = HistoryLockPolicy<String>();
    final now = CalendarNow(time: at(today, 11, 7), today: today);

    final ended = entryOf("ended", at(monday, 22), today);
    expect(answersOf(policy, ended, now), (
      false,
      CalendarResizeEdges.none,
      false,
      false,
    ));
    expect(policy.admitsChange(ended, ended.start, at(today, 1), now), isFalse);

    final running = entryOf("running", at(monday, 22), at(today, 2));
    expect(answersOf(policy, running, now), (
      false,
      CalendarResizeEdges.end,
      true,
      false,
    ));
    expect(
      policy.admitsChange(running, running.start, at(today, 3), now),
      isTrue,
    );
    expect(policy.admitsChange(running, running.start, today, now), isFalse);
    expect(
      policy.admitsChange(running, at(monday, 22, 15), running.end, now),
      isFalse,
    );

    final free = entryOf("free", today, at(today, 1));
    expect(answersOf(policy, free, now), (
      true,
      CalendarResizeEdges.both,
      true,
      true,
    ));
    expect(policy.admitsChange(free, at(monday, 23), today, now), isFalse);
    expect(policy.admitsChange(free, at(today, 3), at(today, 4), now), isTrue);

    const earlier = HistoryLockPolicy<String>(lockEarlierToday: true);
    final halfPast = CalendarNow(time: at(today, 11, 7, 30), today: today);
    expect(
      earlier.mayMove(
        entryOf("next", at(today, 11, 8), at(today, 12)),
        halfPast,
      ),
      isTrue,
    );
    expect(
      earlier.mayEdit(
        entryOf("done", at(today, 10), at(today, 11, 8)),
        halfPast,
      ),
      isFalse,
    );
    expect(earlier.earliestStartOn(today, halfPast), at(today, 11, 8));
    expect(
      earlier.earliestStartOn(
        today,
        CalendarNow(time: at(today, 23, 59, 30), today: today),
      ),
      wednesday,
    );
  });
}
