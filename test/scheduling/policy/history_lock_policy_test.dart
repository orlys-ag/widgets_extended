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

import '../store/zone_support.dart';

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
        ended,
        ended.start,
        at(today, 1),
        now,
        isAllDay: false,
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
        running,
        running.start,
        at(today, 3),
        now,
        isAllDay: false,
      ),
      isTrue,
    );
    expect(
      policy.admitsChange(running, running.start, today, now, isAllDay: false),
      isFalse,
    );
    expect(
      policy.admitsChange(
        running,
        at(monday, 22, 15),
        running.end,
        now,
        isAllDay: false,
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
      policy.admitsChange(free, at(monday, 23), today, now, isAllDay: false),
      isFalse,
    );
    expect(
      policy.admitsChange(
        free,
        at(today, 3),
        at(today, 4),
        now,
        isAllDay: false,
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
          ended,
          at(monday, 8),
          at(monday, 9),
          now,
          isAllDay: false,
        ),
        isTrue,
      );

      final free = entryOf("free", at(today, 14), at(today, 15));
      expect(past.earliestStartOn(today, now), today);
      expect(past.earliestStartOn(monday, now), isNull);
      expect(
        past.admitsChange(free, today, at(today, 1), now, isAllDay: false),
        isTrue,
      );
      expect(
        past.admitsChange(
          free,
          at(monday, 23),
          at(today, 1),
          now,
          isAllDay: false,
        ),
        isFalse,
      );

      expect(earlier.earliestStartOn(today, now), midMorning);
      expect(
        earlier.admitsChange(
          free,
          midMorning,
          at(today, 12),
          now,
          isAllDay: false,
        ),
        isTrue,
      );
      expect(
        earlier.admitsChange(
          free,
          at(today, 11, 6),
          at(today, 12),
          now,
          isAllDay: false,
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
          later,
          at(today, 11, 15),
          at(today, 12),
          now,
          isAllDay: false,
        ),
        isTrue,
      );
      expect(
        earlier.admitsChange(
          later,
          at(today, 11),
          at(today, 12),
          now,
          isAllDay: false,
        ),
        isFalse,
      );
      expect(
        earlier.admitsChange(
          running,
          running.start,
          at(today, 11, 15),
          now,
          isAllDay: false,
        ),
        isTrue,
      );
      expect(
        earlier.admitsChange(
          running,
          running.start,
          at(today, 11),
          now,
          isAllDay: false,
        ),
        isFalse,
      );
      expect(
        earlier.admitsChange(
          running,
          at(today, 10, 15),
          running.end,
          now,
          isAllDay: false,
        ),
        isFalse,
      );
      expect(
        earlier.admitsChange(
          ended,
          ended.start,
          ended.end,
          now,
          isAllDay: false,
        ),
        isTrue,
      );
      expect(
        earlier.admitsChange(
          ended,
          ended.start,
          at(today, 9, 15),
          now,
          isAllDay: false,
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
          entry,
          entry.start,
          at(today, 3),
          now,
          isAllDay: false,
        ),
        isTrue,
      );
      expect(
        past.admitsChange(entry, entry.start, today, now, isAllDay: false),
        isFalse,
      );
      expect(
        past.admitsChange(
          entry,
          entry.start,
          at(monday, 23),
          now,
          isAllDay: false,
        ),
        isFalse,
      );
      expect(
        past.admitsChange(
          entry,
          at(monday, 22, 15),
          entry.end,
          now,
          isAllDay: false,
        ),
        isFalse,
      );
      expect(
        past.admitsChange(
          entry,
          at(today, 9),
          at(today, 10),
          now,
          isAllDay: false,
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
          entry,
          today,
          CalendarDates.addDays(today, 2),
          tenOClock,
          isAllDay: true,
        ),
        isTrue,
      );
      expect(
        earlier.admitsChange(
          entry,
          wednesday,
          CalendarDates.addDays(today, 2),
          tenOClock,
          isAllDay: true,
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
          entry,
          entry.start,
          entry.end,
          at,
          isAllDay: isAllDay,
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
          todayAllDay,
          today,
          CalendarDates.addDays(today, 2),
          tenOClock,
          isAllDay: true,
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

    test(
      "HZ1 CalendarNow for a zone marks the zone's today and time",
      skip: true,
      () {
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
      },
    );

    test("HZ2 HistoryLockPolicy locks by the zone's clock", skip: true, () {
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
          ended,
          plain(ended.start),
          plain(ended.end),
          now,
          isAllDay: false,
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
          plainEnded,
          plainEnded.start.toUtc(),
          plainEnded.end.toUtc(),
          plainNow,
          isAllDay: false,
        ),
        isFalse,
      );

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
