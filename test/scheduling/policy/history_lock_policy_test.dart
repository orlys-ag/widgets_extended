/// The history lock as an edit policy: its settings and equality, the
/// boundary each setting sets on a day at a time, how it holds an entry's
/// start and end, the changes it admits, and where a new entry may start.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/policy/edit_rules.dart';
import 'package:widgets_extended/scheduling/policy/history_lock_policy.dart';
import 'package:widgets_extended/scheduling/policy/schedule_problem.dart';

import '../zones.dart';

/// A Tuesday.
final DateTime today = DateTime(2026, 4, 21);

final DateTime monday = DateTime(2026, 4, 20);
final DateTime wednesday = DateTime(2026, 4, 22);

/// 11:07 on [today].
final DateTime midMorning = DateTime(2026, 4, 21, 11, 7);

/// [day] at [hour], [minute] and [second] by the wall clock.
DateTime at(DateTime day, int hour, [int minute = 0, int second = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute, second);
}

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
  test("HP1 two default history locks are equal with equal hash codes, "
      "lockEarlierToday makes one unequal, none equals the unrestricted "
      "policy, and "
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
    expect(
      policy.admitsChange(
        CalendarChange<String>(
          entry: ended,
          start: ended.start,
          end: at(today, 1),
          isAllDay: false,
        ),
        now,
      ),
      isFalse,
    );

    final running = entryOf("running", at(monday, 22), at(today, 2));
    expect(answersOf(policy, running, now), (
      false,
      CalendarResizeEdges.end,
      true,
      false,
    ));
    expect(
      policy.admitsChange(
        CalendarChange<String>(
          entry: running,
          start: running.start,
          end: at(today, 3),
          isAllDay: false,
        ),
        now,
      ),
      isTrue,
    );
    expect(
      policy.admitsChange(
        CalendarChange<String>(
          entry: running,
          start: running.start,
          end: today,
          isAllDay: false,
        ),
        now,
      ),
      isFalse,
    );
    expect(
      policy.admitsChange(
        CalendarChange<String>(
          entry: running,
          start: at(monday, 22, 15),
          end: running.end,
          isAllDay: false,
        ),
        now,
      ),
      isFalse,
    );

    final free = entryOf("free", today, at(today, 1));
    expect(answersOf(policy, free, now), (
      true,
      CalendarResizeEdges.both,
      true,
      true,
    ));
    expect(
      policy.admitsChange(
        CalendarChange<String>(
          entry: free,
          start: at(monday, 23),
          end: today,
          isAllDay: false,
        ),
        now,
      ),
      isFalse,
    );
    expect(
      policy.admitsChange(
        CalendarChange<String>(
          entry: free,
          start: at(today, 3),
          end: at(today, 4),
          isAllDay: false,
        ),
        now,
      ),
      isTrue,
    );

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

  test("HP3 the lock's refusals of a change are its reasons, as const "
      "lists: for a free entry a past day or a start before the earliest, "
      "for one in progress a kept start or kind, then an end in the past, "
      "and for an ended one the lock", () {
    const lock = HistoryLockPolicy<String>();
    const earlier = HistoryLockPolicy<String>(lockEarlierToday: true);
    final elevenOhSeven = CalendarNow(time: at(today, 11, 7), today: today);
    final lateNight = CalendarNow(time: at(today, 23, 59, 30), today: today);

    CalendarChange<String> change(
      CalendarEntry<String> entry,
      DateTime start,
      DateTime end, {
      bool? isAllDay,
    }) {
      return CalendarChange<String>(
        entry: entry,
        start: start,
        end: end,
        isAllDay: isAllDay ?? entry.isAllDay,
      );
    }

    final running = entryOf("running", at(monday, 22), at(today, 2));
    expect(
      lock.refusalsOf(
        change(running, at(monday, 23), at(monday, 23, 30)),
        elevenOhSeven,
      ),
      <CalendarScheduleProblem>[
        const CalendarScheduleStartKept(),
        const CalendarScheduleEndInPast(),
      ],
    );

    // Each row of the lock's answers under each setting that reaches it:
    // the lock at today's start at 11:07, and the lock at the current
    // minute at 11:07 and at 23:59:30, whose boundary is the next day's
    // start.
    final rows =
        <
          (
            String,
            HistoryLockPolicy<String>,
            CalendarNow,
            CalendarChange<String>,
            List<CalendarScheduleProblem>,
          )
        >[];
    void row(
      String name,
      HistoryLockPolicy<String> policy,
      CalendarNow now,
      CalendarChange<String> asked,
      List<CalendarScheduleProblem> expected,
    ) {
      rows.add((name, policy, now, asked, expected));
    }

    // The lock at today's start, at 11:07.
    final freeToday = entryOf("free", at(today, 10), at(today, 12));
    final ended = entryOf("ended", at(monday, 9), at(monday, 10));
    row(
      "today: free, start not before the boundary",
      lock,
      elevenOhSeven,
      change(freeToday, today, at(today, 2)),
      <CalendarScheduleProblem>[],
    );
    row(
      "today: free, start before today",
      lock,
      elevenOhSeven,
      change(freeToday, at(monday, 23), at(today, 1)),
      <CalendarScheduleProblem>[const CalendarSchedulePastDay()],
    );
    row(
      "today: started, start moved",
      lock,
      elevenOhSeven,
      change(running, at(monday, 23), at(today, 3)),
      <CalendarScheduleProblem>[const CalendarScheduleStartKept()],
    );
    row(
      "today: started, kind changed",
      lock,
      elevenOhSeven,
      change(running, running.start, wednesday, isAllDay: true),
      <CalendarScheduleProblem>[const CalendarScheduleKindKept()],
    );
    row(
      "today: started, kind changed, end at the boundary",
      lock,
      elevenOhSeven,
      change(running, running.start, today, isAllDay: true),
      <CalendarScheduleProblem>[
        const CalendarScheduleKindKept(),
        const CalendarScheduleEndInPast(),
      ],
    );
    row(
      "today: started, end after the boundary",
      lock,
      elevenOhSeven,
      change(running, running.start, at(today, 3)),
      <CalendarScheduleProblem>[],
    );
    row(
      "today: started, end at the boundary",
      lock,
      elevenOhSeven,
      change(running, running.start, today),
      <CalendarScheduleProblem>[const CalendarScheduleEndInPast()],
    );
    row(
      "today: ended, kept",
      lock,
      elevenOhSeven,
      change(ended, ended.start, ended.end),
      <CalendarScheduleProblem>[],
    );
    row(
      "today: ended, moved",
      lock,
      elevenOhSeven,
      change(ended, at(monday, 10), at(monday, 11)),
      <CalendarScheduleProblem>[const CalendarScheduleLocked()],
    );
    row(
      "today: ended, kind changed",
      lock,
      elevenOhSeven,
      change(ended, ended.start, ended.end, isAllDay: true),
      <CalendarScheduleProblem>[const CalendarScheduleLocked()],
    );

    // The lock at the current minute, at 11:07.
    final freeLater = entryOf("free", at(today, 12), at(today, 13));
    final runningNow = entryOf("running", at(today, 10), at(today, 12));
    final endedNow = entryOf("ended", at(today, 9), at(today, 10));
    row(
      "11:07: free, start at the boundary",
      earlier,
      elevenOhSeven,
      change(freeLater, at(today, 11, 7), at(today, 12, 7)),
      <CalendarScheduleProblem>[],
    );
    row(
      "11:07: free, start before today",
      earlier,
      elevenOhSeven,
      change(freeLater, at(monday, 12), at(monday, 13)),
      <CalendarScheduleProblem>[const CalendarSchedulePastDay()],
    );
    row(
      "11:07: free, start on today before the boundary",
      earlier,
      elevenOhSeven,
      change(freeLater, at(today, 10), at(today, 11)),
      <CalendarScheduleProblem>[const CalendarScheduleBeforeEarliest()],
    );
    row(
      "11:07: started, start moved",
      earlier,
      elevenOhSeven,
      change(runningNow, at(today, 10, 30), at(today, 12)),
      <CalendarScheduleProblem>[const CalendarScheduleStartKept()],
    );
    row(
      "11:07: started, start moved, end before the boundary",
      earlier,
      elevenOhSeven,
      change(runningNow, at(today, 10, 30), at(today, 11)),
      <CalendarScheduleProblem>[
        const CalendarScheduleStartKept(),
        const CalendarScheduleEndInPast(),
      ],
    );
    row(
      "11:07: started, kind changed",
      earlier,
      elevenOhSeven,
      change(runningNow, runningNow.start, wednesday, isAllDay: true),
      <CalendarScheduleProblem>[const CalendarScheduleKindKept()],
    );
    row(
      "11:07: started, end after the boundary",
      earlier,
      elevenOhSeven,
      change(runningNow, runningNow.start, at(today, 13)),
      <CalendarScheduleProblem>[],
    );
    row(
      "11:07: started, end at the boundary",
      earlier,
      elevenOhSeven,
      change(runningNow, runningNow.start, at(today, 11, 7)),
      <CalendarScheduleProblem>[const CalendarScheduleEndInPast()],
    );
    row(
      "11:07: ended, kept",
      earlier,
      elevenOhSeven,
      change(endedNow, endedNow.start, endedNow.end),
      <CalendarScheduleProblem>[],
    );
    row(
      "11:07: ended, end moved",
      earlier,
      elevenOhSeven,
      change(endedNow, endedNow.start, at(today, 10, 30)),
      <CalendarScheduleProblem>[const CalendarScheduleLocked()],
    );

    // The lock at the current minute, at 23:59:30: the boundary is
    // Wednesday's start.
    final freeTomorrow = entryOf("free", at(wednesday, 9), at(wednesday, 10));
    final runningLate = entryOf("running", at(today, 23), at(wednesday, 1));
    final endedLate = entryOf("ended", at(today, 22), at(today, 23));
    row(
      "23:59:30: free, start at the boundary",
      earlier,
      lateNight,
      change(freeTomorrow, wednesday, at(wednesday, 1)),
      <CalendarScheduleProblem>[],
    );
    row(
      "23:59:30: free, start before today",
      earlier,
      lateNight,
      change(freeTomorrow, at(monday, 9), at(monday, 10)),
      <CalendarScheduleProblem>[const CalendarSchedulePastDay()],
    );
    row(
      "23:59:30: free, start on today, the boundary on a later day",
      earlier,
      lateNight,
      change(freeTomorrow, at(today, 23), at(wednesday, 1)),
      <CalendarScheduleProblem>[const CalendarSchedulePastDay()],
    );
    row(
      "23:59:30: started, start moved, end at the boundary",
      earlier,
      lateNight,
      change(runningLate, at(today, 23, 30), wednesday),
      <CalendarScheduleProblem>[
        const CalendarScheduleStartKept(),
        const CalendarScheduleEndInPast(),
      ],
    );
    row(
      "23:59:30: started, kind changed",
      earlier,
      lateNight,
      change(
        runningLate,
        runningLate.start,
        CalendarDates.addDays(wednesday, 1),
        isAllDay: true,
      ),
      <CalendarScheduleProblem>[const CalendarScheduleKindKept()],
    );
    row(
      "23:59:30: started, end after the boundary",
      earlier,
      lateNight,
      change(runningLate, runningLate.start, at(wednesday, 2)),
      <CalendarScheduleProblem>[],
    );
    row(
      "23:59:30: started, end at the boundary",
      earlier,
      lateNight,
      change(runningLate, runningLate.start, wednesday),
      <CalendarScheduleProblem>[const CalendarScheduleEndInPast()],
    );
    row(
      "23:59:30: ended, kept",
      earlier,
      lateNight,
      change(endedLate, endedLate.start, endedLate.end),
      <CalendarScheduleProblem>[],
    );
    row(
      "23:59:30: ended, moved",
      earlier,
      lateNight,
      change(endedLate, at(today, 21), at(today, 22)),
      <CalendarScheduleProblem>[const CalendarScheduleLocked()],
    );

    for (final (name, policy, now, asked, expected) in rows) {
      expect(policy.refusalsOf(asked, now), expected, reason: name);
    }

    // Two refusals for one reason answer the identical list.
    expect(
      identical(
        lock.refusalsOf(
          change(running, at(monday, 23), at(today, 3)),
          elevenOhSeven,
        ),
        lock.refusalsOf(
          change(running, at(monday, 21), at(today, 4)),
          elevenOhSeven,
        ),
      ),
      isTrue,
    );
    expect(
      identical(
        lock.refusalsOf(
          change(ended, at(monday, 10), at(monday, 11)),
          elevenOhSeven,
        ),
        lock.refusalsOf(
          change(ended, ended.start, ended.end, isAllDay: true),
          elevenOhSeven,
        ),
      ),
      isTrue,
    );
  });

  group("HistoryLockPolicy's boundary and holds", () {
    final now = CalendarNow(time: midMorning, today: today);
    const past = HistoryLockPolicy<String>();
    const earlier = HistoryLockPolicy<String>(lockEarlierToday: true);

    test("K1 the unrestricted policy holds nothing; the lock's boundary is "
        "the start of today, and with lockEarlierToday today's time, rounded "
        "up to a whole minute", () {
      const unrestricted = UnrestrictedEditPolicy<String>();
      final ended = entryOf("ended", at(monday, 9), at(monday, 10));
      expect(unrestricted.earliestStartOn(monday, now), monday);
      expect(
        unrestricted.admitsChange(
          CalendarChange<String>(
            entry: ended,
            start: at(monday, 8),
            end: at(monday, 9),
            isAllDay: false,
          ),
          now,
        ),
        isTrue,
      );

      final free = entryOf("free", at(today, 14), at(today, 15));
      expect(past.earliestStartOn(today, now), today);
      expect(past.earliestStartOn(monday, now), isNull);
      expect(
        past.admitsChange(
          CalendarChange<String>(
            entry: free,
            start: today,
            end: at(today, 1),
            isAllDay: false,
          ),
          now,
        ),
        isTrue,
      );
      expect(
        past.admitsChange(
          CalendarChange<String>(
            entry: free,
            start: at(monday, 23),
            end: at(today, 1),
            isAllDay: false,
          ),
          now,
        ),
        isFalse,
      );

      expect(earlier.earliestStartOn(today, now), midMorning);
      expect(
        earlier.admitsChange(
          CalendarChange<String>(
            entry: free,
            start: midMorning,
            end: at(today, 12),
            isAllDay: false,
          ),
          now,
        ),
        isTrue,
      );
      expect(
        earlier.admitsChange(
          CalendarChange<String>(
            entry: free,
            start: at(today, 11, 6),
            end: at(today, 12),
            isAllDay: false,
          ),
          now,
        ),
        isFalse,
      );
      // A minute part of which has passed is past.
      expect(
        earlier.earliestStartOn(
          today,
          CalendarNow(time: at(today, 11, 7, 30), today: today),
        ),
        at(today, 11, 8),
      );
      expect(
        earlier.earliestStartOn(
          today,
          CalendarNow(
            time: DateTime(2026, 4, 21, 11, 7, 0, 0, 1),
            today: today,
          ),
        ),
        at(today, 11, 8),
      );
    });

    test("K2 an entry starting at the boundary is free, one ending after it "
        "started, and one ending at it locked, across days too", () {
      expect(
        answersOf(
          earlier,
          entryOf("free", at(today, 11, 7), at(today, 12)),
          now,
        ),
        (true, CalendarResizeEdges.both, true, true),
      );
      expect(
        answersOf(
          earlier,
          entryOf("started", at(today, 10), at(today, 11, 8)),
          now,
        ),
        (false, CalendarResizeEdges.end, true, false),
      );
      expect(
        answersOf(
          earlier,
          entryOf("locked", at(today, 10), at(today, 11, 7)),
          now,
        ),
        (false, CalendarResizeEdges.none, false, false),
      );
      expect(
        answersOf(
          earlier,
          entryOf("across", at(monday, 9), at(wednesday, 10)),
          now,
        ),
        (false, CalendarResizeEdges.end, true, false),
      );
      expect(
        answersOf(
          const UnrestrictedEditPolicy<String>(),
          entryOf("monday", monday, at(monday, 1)),
          now,
        ),
        (true, CalendarResizeEdges.both, true, true),
      );
    });

    test("K3 a free entry may not start before the boundary, a started one "
        "keeps its start and ends after it, a locked one keeps its "
        "times", () {
      final later = entryOf("later", at(today, 14), at(today, 15));
      final running = entryOf("running", at(today, 10), at(today, 12));
      final ended = entryOf("ended", at(today, 8), at(today, 9));
      expect(
        earlier.admitsChange(
          CalendarChange<String>(
            entry: later,
            start: at(today, 11, 15),
            end: at(today, 12),
            isAllDay: false,
          ),
          now,
        ),
        isTrue,
      );
      expect(
        earlier.admitsChange(
          CalendarChange<String>(
            entry: later,
            start: at(today, 11),
            end: at(today, 12),
            isAllDay: false,
          ),
          now,
        ),
        isFalse,
      );
      expect(
        earlier.admitsChange(
          CalendarChange<String>(
            entry: running,
            start: running.start,
            end: at(today, 11, 15),
            isAllDay: false,
          ),
          now,
        ),
        isTrue,
      );
      expect(
        earlier.admitsChange(
          CalendarChange<String>(
            entry: running,
            start: running.start,
            end: at(today, 11),
            isAllDay: false,
          ),
          now,
        ),
        isFalse,
      );
      expect(
        earlier.admitsChange(
          CalendarChange<String>(
            entry: running,
            start: at(today, 10, 15),
            end: running.end,
            isAllDay: false,
          ),
          now,
        ),
        isFalse,
      );
      expect(
        earlier.admitsChange(
          CalendarChange<String>(
            entry: ended,
            start: ended.start,
            end: ended.end,
            isAllDay: false,
          ),
          now,
        ),
        isTrue,
      );
      expect(
        earlier.admitsChange(
          CalendarChange<String>(
            entry: ended,
            start: ended.start,
            end: at(today, 9, 15),
            isAllDay: false,
          ),
          now,
        ),
        isFalse,
      );
    });

    test("K4 a new entry starts on the slot grid from the boundary on its "
        "day, anywhere on a later day and nowhere on an earlier one", () {
      int slotMinuteOn(HistoryLockPolicy<String> policy, DateTime day) {
        return CalendarEarliestStart(
          day,
          policy.earliestStartOn(day, now),
        ).firstSlotMinute(15);
      }

      expect(slotMinuteOn(earlier, today), 11 * 60 + 15);
      expect(slotMinuteOn(earlier, wednesday), 0);
      expect(slotMinuteOn(earlier, monday), CalendarDates.minutesPerDay);
      final earliest = earlier.earliestStartOn(today, now)!;
      expect(at(today, 11, 7).isBefore(earliest), isFalse);
      expect(at(today, 11).isBefore(earliest), isTrue);
      expect(slotMinuteOn(past, today), 0);
    });

    test("HL1 under the lock at today's start, yesterday 22:00 to today "
        "02:00 is started: it may end at 03:00, but not at the boundary or "
        "before it, and keeps its start", () {
      final entry = entryOf("entry", at(monday, 22), at(today, 2));
      expect(past.mayMove(entry, now), isFalse);
      expect(past.resizableEdges(entry, now), CalendarResizeEdges.end);
      expect(
        past.admitsChange(
          CalendarChange<String>(
            entry: entry,
            start: entry.start,
            end: at(today, 3),
            isAllDay: false,
          ),
          now,
        ),
        isTrue,
      );
      expect(
        past.admitsChange(
          CalendarChange<String>(
            entry: entry,
            start: entry.start,
            end: today,
            isAllDay: false,
          ),
          now,
        ),
        isFalse,
      );
      expect(
        past.admitsChange(
          CalendarChange<String>(
            entry: entry,
            start: entry.start,
            end: at(monday, 23),
            isAllDay: false,
          ),
          now,
        ),
        isFalse,
      );
      expect(
        past.admitsChange(
          CalendarChange<String>(
            entry: entry,
            start: at(monday, 22, 15),
            end: entry.end,
            isAllDay: false,
          ),
          now,
        ),
        isFalse,
      );
      expect(
        past.admitsChange(
          CalendarChange<String>(
            entry: entry,
            start: at(today, 9),
            end: at(today, 10),
            isAllDay: false,
          ),
          now,
        ),
        isFalse,
      );
    });

    test("HL2 under lockEarlierToday at 10:00, today's all-day entry is "
        "started", () {
      final tenOClock = CalendarNow(time: at(today, 10), today: today);
      final entry = entryOf("all day", today, wednesday, isAllDay: true);
      expect(earlier.mayMove(entry, tenOClock), isFalse);
      expect(earlier.resizableEdges(entry, tenOClock), CalendarResizeEdges.end);
      // Its end may move to a later day start, and its start not at all.
      expect(
        earlier.admitsChange(
          CalendarChange<String>(
            entry: entry,
            start: today,
            end: CalendarDates.addDays(today, 2),
            isAllDay: true,
          ),
          tenOClock,
        ),
        isTrue,
      );
      expect(
        earlier.admitsChange(
          CalendarChange<String>(
            entry: entry,
            start: wednesday,
            end: CalendarDates.addDays(today, 2),
            isAllDay: true,
          ),
          tenOClock,
        ),
        isFalse,
      );
      // Under the lock at today's start the day is free.
      expect(past.mayMove(entry, tenOClock), isTrue);
      expect(past.resizableEdges(entry, tenOClock), CalendarResizeEdges.both);
    });

    test("HL3 the earliest start's slot minute is 0 after the boundary's day "
        "and minutesPerDay before it, and a today other than now's date "
        "takes now's time of day", () {
      int slotMinuteOn(DateTime day, CalendarNow at) {
        return CalendarEarliestStart(
          day,
          earlier.earliestStartOn(day, at),
        ).firstSlotMinute(15);
      }

      expect(slotMinuteOn(wednesday, now), 0);
      expect(slotMinuteOn(CalendarDates.addDays(today, 10), now), 0);
      expect(slotMinuteOn(monday, now), CalendarDates.minutesPerDay);
      expect(
        slotMinuteOn(CalendarDates.addDays(today, -10), now),
        CalendarDates.minutesPerDay,
      );

      // The host pins today to Wednesday while the clock reads Tuesday.
      final pinned = CalendarNow(
        time: DateTime(2026, 4, 21, 11, 7, 30),
        today: wednesday,
      );
      expect(
        earlier.earliestStartOn(wednesday, pinned),
        DateTime(2026, 4, 22, 11, 8),
      );
      expect(slotMinuteOn(wednesday, pinned), 11 * 60 + 15);
      expect(slotMinuteOn(today, pinned), CalendarDates.minutesPerDay);
    });

    test("HL4 an ended entry and one in progress keep their kind, and a free "
        "one may change it", () {
      bool admitsOwn(
        HistoryLockPolicy<String> policy,
        CalendarEntry<String> entry,
        CalendarNow at, {
        required bool isAllDay,
      }) {
        return policy.admitsChange(
          CalendarChange<String>(
            entry: entry,
            start: entry.start,
            end: entry.end,
            isAllDay: isAllDay,
          ),
          at,
        );
      }

      // Under the lock at today's start, Monday has ended.
      final mondayAllDay = entryOf("monday", monday, today, isAllDay: true);
      expect(admitsOwn(past, mondayAllDay, now, isAllDay: true), isTrue);
      expect(admitsOwn(past, mondayAllDay, now, isAllDay: false), isFalse);
      final mondayTimed = entryOf("monday", monday, today);
      expect(admitsOwn(past, mondayTimed, now, isAllDay: false), isTrue);
      expect(admitsOwn(past, mondayTimed, now, isAllDay: true), isFalse);

      // Under lockEarlierToday at 10:00, today is in progress.
      final tenOClock = CalendarNow(time: at(today, 10), today: today);
      final todayAllDay = entryOf("today", today, wednesday, isAllDay: true);
      final todayTimed = entryOf("today", today, wednesday);
      expect(
        admitsOwn(earlier, todayAllDay, tenOClock, isAllDay: true),
        isTrue,
      );
      expect(
        earlier.admitsChange(
          CalendarChange<String>(
            entry: todayAllDay,
            start: today,
            end: CalendarDates.addDays(today, 2),
            isAllDay: true,
          ),
          tenOClock,
        ),
        isTrue,
      );
      expect(
        admitsOwn(earlier, todayAllDay, tenOClock, isAllDay: false),
        isFalse,
      );
      expect(
        admitsOwn(earlier, todayTimed, tenOClock, isAllDay: false),
        isTrue,
      );
      expect(
        admitsOwn(earlier, todayTimed, tenOClock, isAllDay: true),
        isFalse,
      );

      // Under the lock at today's start, an entry from today's start is
      // free.
      expect(admitsOwn(past, todayAllDay, now, isAllDay: false), isTrue);
      expect(admitsOwn(past, todayTimed, now, isAllDay: true), isTrue);
    });
  });

  group("time zones", () {
    setUpAll(ensureZones);

    test("HZ1 CalendarNow for a zone marks the zone's today and time", () {
      void expectIn(DateTime? time, tz.Location zone, int wall) {
        expect(time, isA<tz.TZDateTime>());
        expect((time as tz.TZDateTime).location, zone);
        expect(CalendarDates.wallMinuteOf(time), wall);
      }

      const perDay = CalendarDates.minutesPerDay;
      final on = DateTime(2025, 7, 16, 10, 7, 30);
      final zone = zoneFarFromDevice(on);
      final time = tz.TZDateTime.from(on, zone);
      final number = CalendarDates.dayNumber(time);
      final now = CalendarNow(
        time: time,
        today: tz.TZDateTime(zone, time.year, time.month, time.day, 15),
      );
      expectIn(now.today, zone, number * perDay);
      // Rounded up: 30 seconds past the minute reads the next.
      expectIn(
        now.timeOnToday,
        zone,
        number * perDay + time.hour * 60 + time.minute + 1,
      );
      expect(now.time, isA<tz.TZDateTime>());

      // A plain today names the zone's date, and marks the zone's day.
      final plainToday = CalendarNow(
        time: time,
        today: DateTime(time.year, time.month, time.day),
      );
      expectIn(plainToday.today, zone, number * perDay);
      expectIn(
        plainToday.timeOnToday,
        zone,
        number * perDay + time.hour * 60 + time.minute + 1,
      );

      // A today whose clock skips the time's minute: the first minute after
      // the skip, on the zone's clock.
      final havana = tz.getLocation("America/Havana");
      final skipNumber = CalendarDates.dayNumber(DateTime.utc(2025, 3, 9));
      final skipped = CalendarNow(
        time: tz.TZDateTime(havana, 2025, 3, 10, 0, 30),
        today: tz.TZDateTime(havana, 2025, 3, 9),
      );
      expectIn(skipped.today, havana, skipNumber * perDay + 60);
      expectIn(skipped.timeOnToday, havana, skipNumber * perDay + 60);

      // A today other than the time's date: the time of day on it.
      final otherNumber = CalendarDates.dayNumber(DateTime.utc(2025, 7, 20));
      final other = CalendarNow(
        time: tz.TZDateTime(havana, 2025, 7, 16, 14, 7, 20),
        today: tz.TZDateTime(havana, 2025, 7, 20),
      );
      expectIn(other.today, havana, otherNumber * perDay);
      expectIn(other.timeOnToday, havana, otherNumber * perDay + 14 * 60 + 8);

      // On today's own date a time in a repeated stretch keeps its
      // occurrence.
      final november = CalendarDates.dayNumber(DateTime.utc(2025, 11, 2));
      final secondPass = tz.TZDateTime.fromMillisecondsSinceEpoch(
        havana,
        tz.TZDateTime(havana, 2025, 11, 2, 0, 30).millisecondsSinceEpoch +
            const Duration(hours: 1).inMilliseconds,
      );
      final kept = CalendarNow(
        time: secondPass,
        today: tz.TZDateTime(havana, 2025, 11, 2),
      );
      expectIn(kept.timeOnToday, havana, november * perDay + 30);
      expect(kept.timeOnToday.isAtSameMomentAs(secondPass), isTrue);
    });

    test("HZ2 HistoryLockPolicy locks by the zone's clock", () {
      final on = DateTime(2025, 7, 16, 10, 7);
      final zone = zoneFarFromDevice(on);
      final time = tz.TZDateTime.from(on, zone);
      final today = tz.TZDateTime(zone, time.year, time.month, time.day);
      final now = CalendarNow(time: time, today: today);
      const lock = HistoryLockPolicy<String>();
      final ended = entryOf(
        "ended",
        today.subtract(const Duration(hours: 3)),
        today.subtract(const Duration(hours: 1)),
      );
      final free = entryOf(
        "free",
        today.add(const Duration(hours: 1)),
        today.add(const Duration(hours: 2)),
      );
      expect(lock.mayMove(ended, now), isFalse);
      expect(lock.mayMove(free, now), isTrue);
      expect(lock.mayDelete(ended, now), isFalse);

      // The same instants as plain times keep the entry's times.
      DateTime plain(DateTime time) {
        return DateTime.fromMillisecondsSinceEpoch(time.millisecondsSinceEpoch);
      }

      expect(
        lock.admitsChange(
          CalendarChange<String>(
            entry: ended,
            start: plain(ended.start),
            end: plain(ended.end),
            isAllDay: false,
          ),
          now,
        ),
        isTrue,
      );

      // A plain lock given plain UTC times at its instants refuses them.
      final plainNow = CalendarNow(
        time: DateTime(2026, 4, 21, 11),
        today: DateTime(2026, 4, 21),
      );
      final plainEnded = entryOf(
        "plainEnded",
        DateTime(2026, 4, 20, 9),
        DateTime(2026, 4, 20, 10),
      );
      expect(
        lock.admitsChange(
          CalendarChange<String>(
            entry: plainEnded,
            start: plainEnded.start.toUtc(),
            end: plainEnded.end.toUtc(),
            isAllDay: false,
          ),
          plainNow,
        ),
        isFalse,
      );

      // Zoned times at the instants of a plain entry keep them, whichever
      // of the two carries the zone, for an entry ended and one in progress.
      final atDevice = zoneAtDeviceOffset(DateTime(2026, 4, 20, 9));
      tz.TZDateTime zonedOf(DateTime time) {
        return tz.TZDateTime.from(time, atDevice);
      }

      final plainStarted = entryOf(
        "plainStarted",
        DateTime(2026, 4, 20, 9),
        DateTime(2026, 4, 21, 12),
      );
      expect(
        lock.admitsChange(
          CalendarChange<String>(
            entry: plainEnded,
            start: zonedOf(plainEnded.start),
            end: zonedOf(plainEnded.end),
            isAllDay: false,
          ),
          plainNow,
        ),
        isTrue,
      );
      expect(
        lock.admitsChange(
          CalendarChange<String>(
            entry: plainStarted,
            start: zonedOf(plainStarted.start),
            end: zonedOf(plainStarted.end),
            isAllDay: false,
          ),
          plainNow,
        ),
        isTrue,
      );
      // A zoned day at the instant of a plain today is today.
      const plainMinuteLock = HistoryLockPolicy<String>(lockEarlierToday: true);
      final onPlainToday = plainMinuteLock.earliestStartOn(
        zonedOf(plainNow.today),
        plainNow,
      );
      expect(onPlainToday, isNotNull);
      expect(onPlainToday!.isAtSameMomentAs(plainNow.timeOnToday), isTrue);

      // The boundary on the zone's today, its day start on a later date,
      // and none on an earlier one; a plain day names the date in the zone.
      const midnightLock = HistoryLockPolicy<String>();
      final combined = CalendarEditPolicy<String>.all(
        <CalendarEditPolicy<String>>[midnightLock, NoOverlapsPolicy<String>()],
      );
      final later = DateTime(time.year, time.month, time.day + 2);
      final laterStart = tz.TZDateTime(
        zone,
        later.year,
        later.month,
        later.day,
      );
      final earlier = DateTime(time.year, time.month, time.day - 1);
      for (final policy in <CalendarEditPolicy<String>>[
        midnightLock,
        combined,
      ]) {
        final onToday = policy.earliestStartOn(
          DateTime(time.year, time.month, time.day),
          now,
        );
        expect(onToday, isA<tz.TZDateTime>());
        expect(onToday!.isAtSameMomentAs(today), isTrue);
        final onLater = policy.earliestStartOn(later, now);
        expect(onLater, isA<tz.TZDateTime>());
        expect(onLater!.isAtSameMomentAs(laterStart), isTrue);
        expect(policy.earliestStartOn(earlier, now), isNull);
      }

      // Under a lock to the minute, the zone's today answers the boundary.
      const minuteLock = HistoryLockPolicy<String>(lockEarlierToday: true);
      final minuteAll = CalendarEditPolicy<String>.all(
        <CalendarEditPolicy<String>>[minuteLock, NoOverlapsPolicy<String>()],
      );
      for (final policy in <CalendarEditPolicy<String>>[
        minuteLock,
        minuteAll,
      ]) {
        final boundary = policy.earliestStartOn(
          DateTime(time.year, time.month, time.day),
          now,
        );
        expect(boundary, isA<tz.TZDateTime>());
        expect(boundary!.isAtSameMomentAs(now.timeOnToday), isTrue);
        final onLater = policy.earliestStartOn(later, now);
        expect(onLater!.isAtSameMomentAs(laterStart), isTrue);
      }
    });
  });
}
