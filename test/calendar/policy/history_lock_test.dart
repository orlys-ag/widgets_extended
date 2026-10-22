/// The history lock: the boundary its two choices set on a day at a time,
/// how it holds an entry time, the changes it admits, and where a new
/// entry may start.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/history_lock.dart';

/// A Tuesday.
final DateTime today = DateTime(2026, 4, 21);

final DateTime monday = DateTime(2026, 4, 20);
final DateTime wednesday = DateTime(2026, 4, 22);

/// 11:07 on [today].
final DateTime midMorning = DateTime(2026, 4, 21, 11, 7);

CalendarEntryTime shape(DateTime day, int start, int end, {int dayCount = 1}) {
  return (firstDay: dayNumber(day), dayCount: dayCount, start: start, end: end);
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
      expect(
        HistoryLock.of(
          lockPast: true,
          lockEarlierToday: false,
          today: today,
          now: midMorning,
        ).boundary,
        dayNumber(today) * minutesPerDay,
      );
      expect(
        HistoryLock.of(
          lockPast: true,
          lockEarlierToday: true,
          today: today,
          now: midMorning,
        ).boundary,
        dayNumber(today) * minutesPerDay + 11 * 60 + 7,
      );
      // A minute part of which has passed is past.
      expect(
        HistoryLock.of(
          lockPast: true,
          lockEarlierToday: true,
          today: today,
          now: DateTime(2026, 4, 21, 11, 7, 30),
        ).boundary,
        dayNumber(today) * minutesPerDay + 11 * 60 + 8,
      );
    });

    test("K2 an item starting at the boundary is free, one ending after it "
        "started, and one ending at it locked, across days too", () {
      final lock = HistoryLock.of(
        lockPast: true,
        lockEarlierToday: true,
        today: today,
        now: midMorning,
      );
      expect(lock.holdOf(shape(today, 11 * 60 + 7, 12 * 60)), ItemHold.free);
      expect(lock.holdOf(shape(today, 10 * 60, 11 * 60 + 8)), ItemHold.started);
      expect(lock.holdOf(shape(today, 10 * 60, 11 * 60 + 7)), ItemHold.locked);
      expect(
        lock.holdOf(shape(monday, 9 * 60, 10 * 60, dayCount: 3)),
        ItemHold.started,
      );
      expect(HistoryLock.none.holdOf(shape(monday, 0, 60)), ItemHold.free);
    });

    test("K3 a free item may not start before the boundary, a started one "
        "keeps its start and ends after it, a locked one keeps its "
        "times", () {
      final lock = HistoryLock.of(
        lockPast: true,
        lockEarlierToday: true,
        today: today,
        now: midMorning,
      );
      final later = shape(today, 14 * 60, 15 * 60);
      final running = shape(today, 10 * 60, 12 * 60);
      final ended = shape(today, 8 * 60, 9 * 60);
      expect(lock.admits(later, shape(today, 11 * 60 + 15, 12 * 60)), isTrue);
      expect(lock.admits(later, shape(today, 11 * 60, 12 * 60)), isFalse);
      expect(lock.admits(running, shape(today, 10 * 60, 11 * 60 + 15)), isTrue);
      expect(lock.admits(running, shape(today, 10 * 60, 11 * 60)), isFalse);
      expect(
        lock.admits(running, shape(today, 10 * 60 + 15, 12 * 60)),
        isFalse,
      );
      expect(lock.admits(ended, ended), isTrue);
      expect(lock.admits(ended, shape(today, 8 * 60, 9 * 60 + 15)), isFalse);
    });

    test("K4 a new item starts on the slot grid from the boundary on its "
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
      expect(lock.admitsStart(today, 11 * 60 + 7), isTrue);
      expect(lock.admitsStart(today, 11 * 60), isFalse);
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
  });
}
