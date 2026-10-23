/// The history lock: the boundary its two choices set on a day at a time,
/// how it holds an entry's start and end, the changes it admits, and where
/// a new entry may start.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/policy/history_lock.dart';

/// A Tuesday.
final DateTime today = DateTime(2026, 4, 21);

final DateTime monday = DateTime(2026, 4, 20);
final DateTime wednesday = DateTime(2026, 4, 22);

/// 11:07 on [today].
final DateTime midMorning = DateTime(2026, 4, 21, 11, 7);

/// [day] at [minute] minutes after its start, by the wall clock.
DateTime at(DateTime day, int minute) {
  return DateTime(day.year, day.month, day.day, minute ~/ 60, minute % 60);
}

void main() {
  group("HistoryLock", () {
    test("K1 holds nothing without lockPast, even with lockEarlierToday; the "
        "start of today with it; and with both today's time, rounded up to "
        "a whole minute", () {
      expect(
        HistoryLock.of(
          lockPast: false,
          lockEarlierToday: true,
          today: today,
          now: midMorning,
        ),
        HistoryLock.none,
      );
      expect(HistoryLock.none.boundary, isNull);
      expect(
        HistoryLock.of(
          lockPast: true,
          lockEarlierToday: false,
          today: today,
          now: midMorning,
        ).boundary,
        today,
      );
      expect(
        HistoryLock.of(
          lockPast: true,
          lockEarlierToday: true,
          today: today,
          now: midMorning,
        ).boundary,
        midMorning,
      );
      // A minute part of which has passed is past.
      expect(
        HistoryLock.of(
          lockPast: true,
          lockEarlierToday: true,
          today: today,
          now: DateTime(2026, 4, 21, 11, 7, 30),
        ).boundary,
        DateTime(2026, 4, 21, 11, 8),
      );
      expect(
        HistoryLock.of(
          lockPast: true,
          lockEarlierToday: true,
          today: today,
          now: DateTime(2026, 4, 21, 11, 7, 0, 0, 1),
        ).boundary,
        DateTime(2026, 4, 21, 11, 8),
      );
    });

    test("K2 an entry starting at the boundary is free, one ending after it "
        "started, and one ending at it locked, across days too", () {
      final lock = HistoryLock.of(
        lockPast: true,
        lockEarlierToday: true,
        today: today,
        now: midMorning,
      );
      expect(
        lock.holdOf(at(today, 11 * 60 + 7), at(today, 12 * 60)),
        EntryHold.free,
      );
      expect(
        lock.holdOf(at(today, 10 * 60), at(today, 11 * 60 + 8)),
        EntryHold.started,
      );
      expect(
        lock.holdOf(at(today, 10 * 60), at(today, 11 * 60 + 7)),
        EntryHold.locked,
      );
      expect(
        lock.holdOf(at(monday, 9 * 60), at(wednesday, 10 * 60)),
        EntryHold.started,
      );
      expect(
        HistoryLock.none.holdOf(monday, at(monday, 60)),
        EntryHold.free,
      );
    });

    test("K3 a free entry may not start before the boundary, a started one "
        "keeps its start and ends after it, a locked one keeps its "
        "times", () {
      final lock = HistoryLock.of(
        lockPast: true,
        lockEarlierToday: true,
        today: today,
        now: midMorning,
      );
      final laterStart = at(today, 14 * 60);
      final laterEnd = at(today, 15 * 60);
      final runningStart = at(today, 10 * 60);
      final runningEnd = at(today, 12 * 60);
      final endedStart = at(today, 8 * 60);
      final endedEnd = at(today, 9 * 60);
      expect(
        lock.admits(
          laterStart,
          laterEnd,
          at(today, 11 * 60 + 15),
          at(today, 12 * 60),
        ),
        isTrue,
      );
      expect(
        lock.admits(laterStart, laterEnd, at(today, 11 * 60), at(today, 12 * 60)),
        isFalse,
      );
      expect(
        lock.admits(
          runningStart,
          runningEnd,
          runningStart,
          at(today, 11 * 60 + 15),
        ),
        isTrue,
      );
      expect(
        lock.admits(runningStart, runningEnd, runningStart, at(today, 11 * 60)),
        isFalse,
      );
      expect(
        lock.admits(
          runningStart,
          runningEnd,
          at(today, 10 * 60 + 15),
          runningEnd,
        ),
        isFalse,
      );
      expect(lock.admits(endedStart, endedEnd, endedStart, endedEnd), isTrue);
      expect(
        lock.admits(endedStart, endedEnd, endedStart, at(today, 9 * 60 + 15)),
        isFalse,
      );
    });

    test("K4 a new entry starts on the slot grid from the boundary on its "
        "day, anywhere on a later day and nowhere on an earlier one", () {
      final lock = HistoryLock.of(
        lockPast: true,
        lockEarlierToday: true,
        today: today,
        now: midMorning,
      );
      expect(lock.earliestStartOn(today), 11 * 60 + 15);
      expect(lock.earliestStartOn(wednesday), 0);
      expect(lock.earliestStartOn(monday), minutesPerDay);
      expect(lock.admitsStart(at(today, 11 * 60 + 7)), isTrue);
      expect(lock.admitsStart(at(today, 11 * 60)), isFalse);
      expect(
        HistoryLock.of(
          lockPast: true,
          lockEarlierToday: false,
          today: today,
          now: midMorning,
        ).earliestStartOn(today),
        0,
      );
    });

    test("HL1 under lockPast, yesterday 22:00 to today 02:00 is started: it "
        "may end at 03:00, but not at the boundary or before it, and keeps "
        "its start", () {
      final lock = HistoryLock.of(
        lockPast: true,
        lockEarlierToday: false,
        today: today,
        now: midMorning,
      );
      final start = at(monday, 22 * 60);
      final end = at(today, 2 * 60);
      expect(lock.holdOf(start, end), EntryHold.started);
      expect(lock.admits(start, end, start, at(today, 3 * 60)), isTrue);
      expect(lock.admits(start, end, start, today), isFalse);
      expect(lock.admits(start, end, start, at(monday, 23 * 60)), isFalse);
      expect(
        lock.admits(start, end, at(monday, 22 * 60 + 15), end),
        isFalse,
      );
      expect(
        lock.admits(start, end, at(today, 9 * 60), at(today, 10 * 60)),
        isFalse,
      );
    });

    test("HL2 under lockEarlierToday at 10:00, today's all-day entry is "
        "started", () {
      final lock = HistoryLock.of(
        lockPast: true,
        lockEarlierToday: true,
        today: today,
        now: at(today, 10 * 60),
      );
      expect(lock.holdOf(today, wednesday), EntryHold.started);
      // Its end may move to a later day start, and its start not at all.
      expect(lock.admits(today, wednesday, today, addDays(today, 2)), isTrue);
      expect(lock.admits(today, wednesday, wednesday, addDays(today, 2)), isFalse);
      // Under lockPast alone the day is free.
      expect(
        HistoryLock.of(
          lockPast: true,
          lockEarlierToday: false,
          today: today,
          now: at(today, 10 * 60),
        ).holdOf(today, wednesday),
        EntryHold.free,
      );
    });

    test("HL3 earliestStartOn is 0 after the boundary's day and "
        "minutesPerDay before it, and a today other than now's date takes "
        "now's time of day", () {
      final lock = HistoryLock.of(
        lockPast: true,
        lockEarlierToday: true,
        today: today,
        now: midMorning,
      );
      expect(lock.earliestStartOn(wednesday), 0);
      expect(lock.earliestStartOn(addDays(today, 10)), 0);
      expect(lock.earliestStartOn(monday), minutesPerDay);
      expect(lock.earliestStartOn(addDays(today, -10)), minutesPerDay);

      // The host pins today to Wednesday while the clock reads Tuesday.
      final pinned = HistoryLock.of(
        lockPast: true,
        lockEarlierToday: true,
        today: wednesday,
        now: DateTime(2026, 4, 21, 11, 7, 30),
      );
      expect(pinned.boundary, DateTime(2026, 4, 22, 11, 8));
      expect(pinned.earliestStartOn(wednesday), 11 * 60 + 15);
      expect(pinned.earliestStartOn(today), minutesPerDay);
    });
  });
}
