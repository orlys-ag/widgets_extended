/// The schedule check: the problems it names from the rules' and the
/// policy's answers, the overlaps, the first minute a start may take, and
/// the next free range of a schedule's length.
library;

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/entries/calendar_schedule.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/policy/edit_rules.dart';
import 'package:widgets_extended/scheduling/policy/history_lock_policy.dart';
import 'package:widgets_extended/scheduling/policy/schedule_check.dart';

import '../zones.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);

/// 11:07 on Tuesday.
final CalendarNow elevenOhSeven = CalendarNow(
  time: DateTime(2026, 4, 21, 11, 7),
  today: tuesday,
);

/// [start] to [end] minutes after [day]'s midnight.
CalendarSchedule timed(DateTime day, int start, int end) {
  return CalendarSchedule.of(
    DateTime(day.year, day.month, day.day, 0, start),
    DateTime(day.year, day.month, day.day, 0, end),
    isAllDay: false,
  );
}

/// An entry [id] from [start] to [end] minutes after [day]'s midnight.
CalendarEntry<String> entryOf(
  String id,
  DateTime day,
  int start,
  int end, {
  bool isAllDay = false,
}) {
  return CalendarEntry<String>(
    id: id,
    start: DateTime(day.year, day.month, day.day, 0, start),
    end: DateTime(day.year, day.month, day.day, 0, end),
    title: id,
    color: const Color(0xFF336699),
    payload: id,
    isAllDay: isAllDay,
  );
}

CalendarEditRules<String> rulesOf(
  CalendarEditPolicy<String> policy, {
  CalendarDayHours hours = CalendarDayHours.allDay,
}) {
  return CalendarEditRules<String>(
    policy: policy,
    hours: hours,
    slotMinutes: 15,
  );
}

/// The problems of [schedule] under [policy] at [now], for [entry].
List<CalendarScheduleProblem> problemsOf(
  CalendarEditPolicy<String> policy,
  CalendarSchedule schedule, {
  CalendarEntry<String>? entry,
  CalendarNow? now,
}) {
  return CalendarScheduleCheck<String>(
    schedule: schedule,
    rules: rulesOf(policy),
    now: now ?? elevenOhSeven,
    entry: entry,
  ).problems;
}

/// A policy that forbids overlaps but lets a change share time with an
/// entry whose id is "soft" ([CalendarEditPolicy.mayOverlap]).
final class _SoftOverlaps extends CalendarEditPolicy<String> {
  const _SoftOverlaps();

  @override
  bool get allowsOverlaps {
    return false;
  }

  @override
  bool mayOverlap(
    CalendarOverlapCandidate<String> candidate,
    CalendarEntry<String> other,
  ) {
    return other.id == "soft";
  }
}

/// Holds every entry as one in progress, its start fixed and its end
/// resizable, and admits only a change to a timed entry.
final class _HeldTimedOnly extends CalendarEditPolicy<String> {
  const _HeldTimedOnly();

  @override
  bool mayMove(CalendarEntry<String> entry, CalendarNow now) {
    return false;
  }

  @override
  CalendarResizeEdges resizableEdges(
    CalendarEntry<String> entry,
    CalendarNow now,
  ) {
    return CalendarResizeEdges.end;
  }

  @override
  bool admitsChange(
    CalendarEntry<String> entry,
    DateTime start,
    DateTime end,
    CalendarNow now, {
    required bool isAllDay,
  }) {
    return !isAllDay;
  }
}

/// Refuses a change ending after 12:00 of its end's day, a rule no
/// problem names.
final class _EndsByNoon extends CalendarEditPolicy<String> {
  const _EndsByNoon();

  @override
  bool admitsChange(
    CalendarEntry<String> entry,
    DateTime start,
    DateTime end,
    CalendarNow now, {
    required bool isAllDay,
  }) {
    return CalendarDates.endMinuteOfDay(end) <= 12 * 60;
  }
}

/// Takes a new start on a zoned day from [hour]:00 on the day's clock,
/// given as that instant on UTC's clock, a `TZDateTime` of package
/// timezone's `UTC`, as `TZDateTime.toUtc` gives.
final class _EarliestInUtc extends CalendarEditPolicy<String> {
  const _EarliestInUtc(this.hour);

  final int hour;

  @override
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    final zoned = day as tz.TZDateTime;
    return tz.TZDateTime(
      zoned.location,
      zoned.year,
      zoned.month,
      zoned.day,
      hour,
    ).toUtc();
  }
}

/// Answers as [inner] does, recording the day of each earliest start and
/// the end of each change it is asked.
final class _Counting extends CalendarEditPolicy<String> {
  _Counting(this.inner);

  final CalendarEditPolicy<String> inner;
  final List<DateTime> earliestAsked = <DateTime>[];
  final List<DateTime> changeAsked = <DateTime>[];

  @override
  bool mayMove(CalendarEntry<String> entry, CalendarNow now) {
    return inner.mayMove(entry, now);
  }

  @override
  CalendarResizeEdges resizableEdges(
    CalendarEntry<String> entry,
    CalendarNow now,
  ) {
    return inner.resizableEdges(entry, now);
  }

  @override
  bool mayEdit(CalendarEntry<String> entry, CalendarNow now) {
    return inner.mayEdit(entry, now);
  }

  @override
  bool admitsChange(
    CalendarEntry<String> entry,
    DateTime start,
    DateTime end,
    CalendarNow now, {
    required bool isAllDay,
  }) {
    changeAsked.add(end);
    return inner.admitsChange(entry, start, end, now, isAllDay: isAllDay);
  }

  @override
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    earliestAsked.add(day);
    return inner.earliestStartOn(day, now);
  }
}

/// America/New_York, whose clock reads 01:00 to 02:00 twice on 2026-11-01,
/// going back at 06:00Z.
tz.Location get newYork {
  ensureZones();
  return tz.getLocation("America/New_York");
}

/// The instant [utc] on New York's clock.
tz.TZDateTime inNewYork(DateTime utc) {
  return tz.TZDateTime.from(utc, newYork);
}

/// [time]'s instant as a plain UTC time, which compares by instant with a
/// [DateTime.utc].
DateTime utcOf(DateTime time) {
  return DateTime.fromMicrosecondsSinceEpoch(
    time.microsecondsSinceEpoch,
    isUtc: true,
  );
}

/// The schedule of the instants [start] to [end], given in UTC, read on New
/// York's clock.
CalendarSchedule inNewYorkFrom(DateTime start, DateTime end) {
  return CalendarSchedule.of(inNewYork(start), inNewYork(end), isAllDay: false);
}

/// An entry [id] from the instants [start] to [end], given in UTC, on New
/// York's clock.
CalendarEntry<String> entryInNewYork(String id, DateTime start, DateTime end) {
  return CalendarEntry<String>(
    id: id,
    start: inNewYork(start),
    end: inNewYork(end),
    title: id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

/// 09:00 on 2026-10-30 in New York, days before its clock goes back.
CalendarNow get beforeTheChange {
  return CalendarNow(
    time: tz.TZDateTime(newYork, 2026, 10, 30, 9),
    today: tz.TZDateTime(newYork, 2026, 10, 30),
  );
}

/// The instant [utc] on 2026-11-01 in New York, as the time now.
CalendarNow nowOnTheChange(DateTime utc) {
  return CalendarNow(
    time: inNewYork(utc),
    today: tz.TZDateTime(newYork, 2026, 11, 1),
  );
}

/// Expects [times] to be exactly the instants [start] and [end].
void expectTimes(
  ({DateTime start, DateTime end})? times,
  DateTime start,
  DateTime end,
) {
  expect(times, isNotNull);
  expect((utcOf(times!.start), utcOf(times.end)), (utcOf(start), utcOf(end)));
}

/// Matches the plain local date of [date], a local midnight: that instant,
/// not a UTC time and not a zone's `TZDateTime`.
Matcher plainDate(DateTime date) {
  return predicate<DateTime?>((day) {
    return day is DateTime && day is! tz.TZDateTime && day == date;
  }, "the plain local date $date");
}

void main() {
  const lock = HistoryLockPolicy<String>(lockEarlierToday: true);
  const unrestricted = UnrestrictedEditPolicy<String>();

  test("SC1 a schedule the rules admit has no problems, no overlaps, and "
      "takes a start from its day's first minute", () {
    final check = CalendarScheduleCheck<String>(
      schedule: timed(wednesday, 540, 600),
      rules: rulesOf(unrestricted),
      now: elevenOhSeven,
      others: <CalendarEntry<String>>[entryOf("later", wednesday, 600, 660)],
    );
    expect(check.problems, isEmpty);
    expect(check.admitted, isTrue);
    expect(check.overlaps, isEmpty);
    expect(check.firstStartMinute, 0);
    expect(check.startFixed, isFalse);
    expect(check.nextFree, timed(wednesday, 540, 600));
    expect(
      () => check.problems.add(const CalendarScheduleLocked()),
      throwsUnsupportedError,
    );
  });

  test("SC2 the history lock's problems: a past day, a start before now, "
      "a past item, and an item in progress keeping its start, its kind "
      "and an end after now", () {
    final running = entryOf("running", tuesday, 600, 720);
    expect(problemsOf(lock, timed(monday, 540, 600)), <CalendarScheduleProblem>[
      const CalendarSchedulePastDay(),
    ]);
    expect(
      problemsOf(lock, timed(tuesday, 540, 600)),
      <CalendarScheduleProblem>[const CalendarScheduleBeforeEarliest()],
    );
    expect(
      problemsOf(
        lock,
        timed(tuesday, 480, 555),
        entry: entryOf("past", tuesday, 480, 540),
      ),
      <CalendarScheduleProblem>[const CalendarScheduleLocked()],
    );
    expect(
      problemsOf(lock, timed(tuesday, 615, 660), entry: running),
      <CalendarScheduleProblem>[
        const CalendarScheduleStartKept(),
        const CalendarScheduleEndInPast(),
      ],
    );
    expect(problemsOf(lock, timed(tuesday, 600, 780), entry: running), isEmpty);
    expect(problemsOf(unrestricted, timed(monday, 540, 600)), isEmpty);

    // At Tuesday 23:59:30 the lock's boundary is Wednesday's start.
    expect(
      problemsOf(
        lock,
        timed(tuesday, 22 * 60, 23 * 60),
        now: CalendarNow(
          time: DateTime(2026, 4, 21, 23, 59, 30),
          today: tuesday,
        ),
      ),
      <CalendarScheduleProblem>[const CalendarSchedulePastDay()],
    );

    // The end is asked with the stored kind.
    const held = _HeldTimedOnly();
    final wholeDay = entryOf("whole", tuesday, 0, 1440);
    expect(problemsOf(held, timed(tuesday, 0, 1440), entry: wholeDay), isEmpty);
    expect(
      problemsOf(
        held,
        timed(tuesday, 0, 1440).withAllDay(true),
        entry: wholeDay,
      ),
      <CalendarScheduleProblem>[const CalendarScheduleKindKept()],
    );
    expect(
      problemsOf(
        held,
        timed(tuesday, 0, 1440).withAllDay(true).withEndDay(wednesday),
        entry: wholeDay,
      ),
      <CalendarScheduleProblem>[const CalendarScheduleKindKept()],
    );
  });

  test("SC3 the day limit, the kind's options, the hours, the order of "
      "the ends and the clock's skipped times", () {
    final threeDays = timed(
      wednesday,
      540,
      600,
    ).withEndDay(DateTime(2026, 4, 24));
    expect(
      problemsOf(DayLimitPolicy<String>(2), threeDays),
      contains(const CalendarScheduleTooManyDays()),
    );
    expect(problemsOf(DayLimitPolicy<String>(3), threeDays), isEmpty);

    final narrow = CalendarScheduleOptions(
      allowsAllDay: false,
      spansDays: false,
    );
    expect(
      CalendarScheduleCheck<String>(
        schedule: threeDays.withAllDay(true),
        rules: rulesOf(unrestricted),
        now: elevenOhSeven,
        options: narrow,
      ).problems,
      <CalendarScheduleProblem>[
        const CalendarScheduleSpansDays(),
        const CalendarScheduleAllDayNotAllowed(),
      ],
    );

    final office = CalendarDayHours(8 * 60, 18 * 60);
    CalendarScheduleCheck<String> inOffice(CalendarSchedule schedule) {
      return CalendarScheduleCheck<String>(
        schedule: schedule,
        rules: rulesOf(unrestricted, hours: office),
        now: elevenOhSeven,
      );
    }

    expect(
      inOffice(timed(wednesday, 7 * 60, 9 * 60)).problems,
      <CalendarScheduleProblem>[
        const CalendarScheduleOutsideHours(atEnd: false),
      ],
    );
    expect(
      inOffice(timed(wednesday, 17 * 60, 19 * 60)).problems,
      <CalendarScheduleProblem>[
        const CalendarScheduleOutsideHours(atEnd: true),
      ],
    );
    expect(
      inOffice(timed(wednesday, 9 * 60, 10 * 60).withAllDay(true)).problems,
      isEmpty,
    );
    // A stored entry the hours no longer hold keeps its times.
    final early = entryOf("early", wednesday, 7 * 60, 9 * 60);
    CalendarScheduleCheck<String> editOf(CalendarSchedule schedule) {
      return CalendarScheduleCheck<String>(
        schedule: schedule,
        rules: rulesOf(unrestricted, hours: office),
        now: elevenOhSeven,
        entry: early,
      );
    }

    expect(editOf(timed(wednesday, 7 * 60, 9 * 60)).problems, isEmpty);
    expect(
      editOf(timed(wednesday, 7 * 60, 10 * 60)).problems,
      <CalendarScheduleProblem>[
        const CalendarScheduleOutsideHours(atEnd: false),
      ],
    );

    expect(
      problemsOf(unrestricted, timed(wednesday, 540, 600).withEndMinute(540)),
      <CalendarScheduleProblem>[const CalendarScheduleEndNotAfterStart()],
    );

    ensureZones();
    final havana = tz.getLocation("America/Havana");
    final inHavana = CalendarNow(
      time: tz.TZDateTime(havana, 2026, 3, 1, 9),
      today: tz.TZDateTime(havana, 2026, 3, 1),
    );
    // Havana's clock skips 00:00 to 01:00 on 2026-03-08.
    final eighth = DateTime(2026, 3, 8);
    expect(
      problemsOf(
        unrestricted,
        // A plain DateTime of 00:30 on the eighth would read 01:30 under a
        // device clock that skips it, so the start is set as a minute.
        timed(eighth, 600, 690).withStartMinute(30),
        now: inHavana,
      ),
      <CalendarScheduleProblem>[const CalendarScheduleStartSkipped()],
    );
    expect(
      problemsOf(
        unrestricted,
        timed(
          DateTime(2026, 3, 7),
          23 * 60,
          1440,
        ).withEndDay(DateTime(2026, 3, 8)).withEndMinute(30),
        now: inHavana,
      ),
      <CalendarScheduleProblem>[const CalendarScheduleEndSkipped()],
    );
  });

  test("SC4 the overlaps are the timed others sharing the timed schedule's "
      "time, the stored entry left out; a policy that refuses them names "
      "each", () {
    final shared = entryOf("shared", wednesday, 570, 630);
    final others = <CalendarEntry<String>>[
      shared,
      entryOf("touching", wednesday, 600, 660),
      entryOf("allDay", wednesday, 0, 1440, isAllDay: true),
      entryOf("self", wednesday, 540, 600),
    ];
    final self = entryOf("self", wednesday, 540, 600);
    CalendarScheduleCheck<String> checkOf(
      CalendarEditPolicy<String> policy,
      CalendarSchedule schedule,
    ) {
      return CalendarScheduleCheck<String>(
        schedule: schedule,
        rules: rulesOf(policy),
        now: elevenOhSeven,
        others: others,
        entry: self,
      );
    }

    final allowed = checkOf(unrestricted, timed(wednesday, 540, 600));
    expect(allowed.overlaps, <CalendarEntry<String>>[shared]);
    expect(allowed.problems, isEmpty);

    final refused = checkOf(
      const NoOverlapsPolicy<String>(),
      timed(wednesday, 540, 600),
    );
    expect(refused.problems, <CalendarScheduleProblem>[
      CalendarScheduleOverlapRefused<String>(shared),
    ]);
    expect(
      (refused.problems.single as CalendarScheduleOverlapRefused<String>).other,
      same(shared),
    );

    final allDay = checkOf(
      const NoOverlapsPolicy<String>(),
      timed(wednesday, 540, 600).withAllDay(true),
    );
    expect(allDay.overlaps, isEmpty);
    expect(allDay.problems, isEmpty);
  });

  test("SC5 the next free range keeps the schedule's length and starts "
      "after what it overlaps; none for a multi-day or all-day schedule", () {
    CalendarScheduleCheck<String> checkOf(CalendarSchedule schedule) {
      return CalendarScheduleCheck<String>(
        schedule: schedule,
        rules: rulesOf(unrestricted),
        now: elevenOhSeven,
        others: <CalendarEntry<String>>[entryOf("shared", wednesday, 570, 630)],
      );
    }

    expect(
      checkOf(timed(wednesday, 540, 600)).nextFree,
      timed(wednesday, 630, 690),
    );
    expect(
      checkOf(
        timed(wednesday, 540, 600).withEndDay(DateTime(2026, 4, 23)),
      ).nextFree,
      isNull,
    );
    expect(
      checkOf(timed(wednesday, 540, 600).withAllDay(true)).nextFree,
      isNull,
    );
    expect(
      checkOf(timed(wednesday, 23 * 60, 1440)).nextFree,
      timed(wednesday, 23 * 60, 1440),
    );
    expect(
      checkOf(timed(wednesday, 600, 1380)).nextFree,
      timed(wednesday, 630, 1410),
    );
    expect(checkOf(timed(wednesday, 600, 1440)).nextFree, isNull);
  });

  test("SC6 under the history lock a start takes today's minutes from now "
      "on, and none of a past day", () {
    CalendarScheduleCheck<String> checkOf(CalendarSchedule schedule) {
      return CalendarScheduleCheck<String>(
        schedule: schedule,
        rules: rulesOf(lock),
        now: elevenOhSeven,
      );
    }

    expect(checkOf(timed(tuesday, 720, 780)).firstStartMinute, 11 * 60 + 7);
    // A minute part of which has passed is past.
    expect(
      CalendarScheduleCheck<String>(
        schedule: timed(tuesday, 720, 780),
        rules: rulesOf(lock),
        now: CalendarNow(time: DateTime(2026, 4, 21, 11, 7, 1), today: tuesday),
      ).firstStartMinute,
      11 * 60 + 8,
    );
    expect(checkOf(timed(monday, 720, 780)).firstStartMinute, isNull);
    expect(checkOf(timed(wednesday, 720, 780)).firstStartMinute, 0);
  });

  test("SC7 a refusal no problem names is reported alone, and none where "
      "a named problem explains it", () {
    const noon = _EndsByNoon();
    final stored = entryOf("stored", wednesday, 540, 600);
    expect(
      problemsOf(noon, timed(wednesday, 540, 780), entry: stored),
      <CalendarScheduleProblem>[const CalendarScheduleRefused()],
    );
    expect(
      problemsOf(noon, timed(wednesday, 540, 720), entry: stored),
      isEmpty,
    );
    // A new entry is asked only where it may start.
    expect(problemsOf(noon, timed(wednesday, 540, 780)), isEmpty);
    final limited = CalendarEditPolicy<String>.all(<CalendarEditPolicy<String>>[
      noon,
      DayLimitPolicy<String>(1),
    ]);
    expect(
      problemsOf(
        limited,
        timed(wednesday, 540, 780).withEndDay(DateTime(2026, 4, 23)),
        entry: stored,
      ),
      <CalendarScheduleProblem>[const CalendarScheduleTooManyDays()],
    );
  });

  test("SC8 the times are checked where the end is after the start and the "
      "clock reads both", () {
    CalendarScheduleCheck<String> checkOf(
      CalendarSchedule schedule, {
      CalendarNow? now,
    }) {
      return CalendarScheduleCheck<String>(
        schedule: schedule,
        rules: rulesOf(unrestricted),
        now: now ?? elevenOhSeven,
      );
    }

    expect(checkOf(timed(wednesday, 540, 600)).timesChecked, isTrue);
    expect(
      checkOf(timed(wednesday, 540, 600).withEndMinute(540)).timesChecked,
      isFalse,
    );

    ensureZones();
    final havana = tz.getLocation("America/Havana");
    final inHavana = CalendarNow(
      time: tz.TZDateTime(havana, 2026, 3, 1, 9),
      today: tz.TZDateTime(havana, 2026, 3, 1),
    );
    // Havana's clock skips 00:00 to 01:00 on 2026-03-08, so this end, 00:30
    // of the eighth, is no time on it.
    final skippedEnd = checkOf(
      timed(
        DateTime(2026, 3, 7),
        23 * 60,
        1440,
      ).withEndDay(DateTime(2026, 3, 8)).withEndMinute(30),
      now: inHavana,
    );
    // Setup sanity: the clock skips the end, which is after the start.
    expect(skippedEnd.problems, <CalendarScheduleProblem>[
      const CalendarScheduleEndSkipped(),
    ]);
    expect(skippedEnd.timesChecked, isFalse);
  });

  test("SC9 a check of another schedule made from a check answers as a new "
      "check of that schedule with the same inputs", () {
    final policy = CalendarEditPolicy<String>.all(<CalendarEditPolicy<String>>[
      lock,
      const NoOverlapsPolicy<String>(),
    ]);
    final running = entryOf("running", tuesday, 600, 720);
    final others = <CalendarEntry<String>>[
      running,
      entryOf("shared", tuesday, 750, 810),
    ];
    final options = CalendarScheduleOptions(spansDays: false);
    final rules = rulesOf(policy);
    final from = CalendarScheduleCheck<String>(
      schedule: timed(tuesday, 600, 720),
      rules: rules,
      now: elevenOhSeven,
      others: others,
      entry: running,
      options: options,
    );
    for (final schedule in <CalendarSchedule>[
      timed(tuesday, 600, 780),
      timed(tuesday, 600, 780).withEndDay(wednesday),
      timed(tuesday, 700, 760),
    ]) {
      final made = from.withSchedule(schedule);
      final fresh = CalendarScheduleCheck<String>(
        schedule: schedule,
        rules: rules,
        now: elevenOhSeven,
        others: others,
        entry: running,
        options: options,
      );
      expect(made.schedule, schedule);
      expect(made.problems, fresh.problems, reason: "$schedule");
      expect(made.overlaps, fresh.overlaps, reason: "$schedule");
      expect(
        made.firstStartMinute,
        fresh.firstStartMinute,
        reason: "$schedule",
      );
      expect(made.nextFree, fresh.nextFree, reason: "$schedule");
      expect(made.startFixed, fresh.startFixed, reason: "$schedule");
    }
  });

  test("SC10 the first start day is none where yesterday takes a start, "
      "today where only today does, and tomorrow where neither does", () {
    CalendarScheduleCheck<String> checkOf(
      CalendarEditPolicy<String> policy, {
      CalendarNow? now,
    }) {
      return CalendarScheduleCheck<String>(
        schedule: timed(wednesday, 540, 600),
        rules: rulesOf(policy),
        now: now ?? elevenOhSeven,
      );
    }

    expect(checkOf(unrestricted).firstStartDay, isNull);
    expect(
      checkOf(const HistoryLockPolicy<String>()).firstStartDay,
      plainDate(tuesday),
    );
    // Past 23:59 the lock at the current minute closes today too.
    final lastMinute = CalendarNow(
      time: DateTime(2026, 4, 21, 23, 59, 30),
      today: tuesday,
    );
    expect(checkOf(lock, now: lastMinute).firstStartDay, plainDate(wednesday));

    // Today on the clock of a zone 12 hours behind the device's, which at
    // 13:00 reads Tuesday while the device reads Wednesday.
    ensureZones();
    final behind = zoneApartFromDevice(DateTime(2026, 4, 21, 13), -12);
    expect(
      checkOf(
        const HistoryLockPolicy<String>(),
        now: CalendarNow(
          time: tz.TZDateTime(behind, 2026, 4, 21, 13),
          today: tz.TZDateTime(behind, 2026, 4, 21),
        ),
      ).firstStartDay,
      plainDate(tuesday),
    );

    final counting = _Counting(lock);
    final check = checkOf(counting, now: lastMinute);
    final before = counting.earliestAsked.length;
    final first = check.firstStartDay;
    check.firstStartDay;
    // Setup sanity: the counting policy answers as the lock.
    expect(first, plainDate(wednesday));
    expect(counting.earliestAsked.length - before, lessThanOrEqualTo(2));
  });

  test("SC11 the end days run from the start day, or a fixed start's first "
      "day whose 24:00 the policy admits, to the start day without spanning "
      "days or the day limit's last day", () {
    CalendarScheduleCheck<String> checkOf(
      CalendarEditPolicy<String> policy,
      CalendarSchedule schedule, {
      CalendarEntry<String>? entry,
      CalendarScheduleOptions? options,
      CalendarNow? now,
    }) {
      return CalendarScheduleCheck<String>(
        schedule: schedule,
        rules: rulesOf(policy),
        now: now ?? elevenOhSeven,
        entry: entry,
        options: options,
      );
    }

    /// Expects [check]'s end days to be the plain local dates [first] and
    /// [last], or no last day where [last] is null.
    void expectEndDays(
      CalendarScheduleCheck<String> check,
      DateTime first,
      DateTime? last,
    ) {
      final days = check.endDays;
      expect(days.first, plainDate(first), reason: "$days");
      expect(
        days.last,
        last == null ? isNull : plainDate(last),
        reason: "$days",
      );
    }

    final noSpanning = CalendarScheduleOptions(spansDays: false);
    final friday = DateTime(2026, 4, 24);
    final wednesdayMorning = timed(wednesday, 540, 600);
    expectEndDays(checkOf(unrestricted, wednesdayMorning), wednesday, null);
    expectEndDays(
      checkOf(DayLimitPolicy<String>(3), wednesdayMorning),
      wednesday,
      friday,
    );
    expectEndDays(
      checkOf(unrestricted, wednesdayMorning, options: noSpanning),
      wednesday,
      wednesday,
    );
    // On a zone's clock the answers are still the plain local dates.
    ensureZones();
    final zone = zoneFarFromDevice(DateTime(2026, 4, 21, 11, 7));
    expectEndDays(
      checkOf(
        DayLimitPolicy<String>(3),
        wednesdayMorning,
        now: CalendarNow(
          time: tz.TZDateTime(zone, 2026, 4, 21, 11, 7),
          today: tz.TZDateTime(zone, 2026, 4, 21),
        ),
      ),
      wednesday,
      friday,
    );

    const atToday = HistoryLockPolicy<String>();
    final running = CalendarEntry<String>(
      id: "running",
      start: DateTime(2026, 4, 20, 9),
      end: DateTime(2026, 4, 22, 10),
      title: "running",
      color: const Color(0xFF336699),
      payload: "running",
    );
    final runningSchedule = CalendarSchedule.of(
      running.start,
      running.end,
      isAllDay: false,
    );
    final fixed = checkOf(atToday, runningSchedule, entry: running);
    // Setup sanity: the lock holds the running entry's start.
    expect(fixed.startFixed, isTrue);
    // Monday's 24:00 is the lock's boundary, the start of today, which an
    // end must lie after.
    expectEndDays(fixed, tuesday, null);
    // With no spanning days no day is: the first lies after the last.
    expectEndDays(
      checkOf(atToday, runningSchedule, entry: running, options: noSpanning),
      tuesday,
      monday,
    );

    final counting = _Counting(atToday);
    final counted = checkOf(counting, runningSchedule, entry: running);
    final before = counting.changeAsked.length;
    final days = counted.endDays;
    counted.endDays;
    // Setup sanity: the counting policy answers as the lock.
    expect(days.first, plainDate(tuesday));
    expect(counting.changeAsked.length - before, lessThanOrEqualTo(3));
  });

  group("the passes of a repeated stretch", () {
    const lockNow = HistoryLockPolicy<String>(lockEarlierToday: true);

    /// The check of [schedule] for a new entry under [policy] at [now],
    /// against [others].
    CalendarScheduleCheck<String> newCheck(
      CalendarEditPolicy<String> policy,
      CalendarSchedule schedule,
      CalendarNow now, {
      Iterable<CalendarEntry<String>> others = const <Never>[],
    }) {
      return CalendarScheduleCheck<String>(
        schedule: schedule,
        rules: rulesOf(policy),
        now: now,
        others: others,
      );
    }

    test("SC12 01:15 EDT to 01:10 EST is admitted", () {
      expect(
        newCheck(
          unrestricted,
          inNewYorkFrom(
            DateTime.utc(2026, 11, 1, 5, 15),
            DateTime.utc(2026, 11, 1, 6, 10),
          ),
          beforeTheChange,
        ).problems,
        isEmpty,
      );
    });

    test("SC13 an unchanged in-progress entry that started in the later "
        "pass is admitted under the lock of earlier today", () {
      final entry = entryInNewYork(
        "running",
        DateTime.utc(2026, 11, 1, 6, 30),
        DateTime.utc(2026, 11, 1, 8),
      );
      final check = CalendarScheduleCheck<String>(
        schedule: CalendarSchedule.of(entry.start, entry.end, isAllDay: false),
        rules: rulesOf(lockNow),
        now: nowOnTheChange(DateTime.utc(2026, 11, 1, 6, 45)),
        entry: entry,
      );
      expect(check.problems, isEmpty);
    });

    test("SC14 a first-pass start before a later-pass now is before the "
        "earliest start", () {
      final schedule = CalendarSchedule.of(
        tz.TZDateTime(newYork, 2026, 11, 1, 1, 50),
        tz.TZDateTime(newYork, 2026, 11, 1, 2, 20),
        isAllDay: false,
      );
      // Setup sanity: the start is the first 01:50.
      expect(
        utcOf(schedule.timesOn(newYork)!.start),
        DateTime.utc(2026, 11, 1, 5, 50),
      );
      expect(
        newCheck(
          lockNow,
          schedule,
          nowOnTheChange(DateTime.utc(2026, 11, 1, 6, 45)),
        ).problems,
        <CalendarScheduleProblem>[const CalendarScheduleBeforeEarliest()],
      );
    });

    test("SC15 the next free range under the lock never starts before now", () {
      final check = newCheck(
        lockNow,
        inNewYorkFrom(
          DateTime.utc(2026, 11, 1, 5, 30),
          DateTime.utc(2026, 11, 1, 7, 30),
        ),
        nowOnTheChange(DateTime.utc(2026, 11, 1, 6, 45)),
      );
      final free = check.nextFree!;
      expect(
        utcOf(
          free.timesOn(newYork)!.start,
        ).isBefore(DateTime.utc(2026, 11, 1, 6, 45)),
        isFalse,
      );
      expect(check.withSchedule(free).admitted, isTrue);
    });

    test("SC16 the next free range of 01:30 to 02:00 in the first pass "
        "lasts 30 minutes and is admitted", () {
      final check = newCheck(
        unrestricted,
        inNewYorkFrom(
          DateTime.utc(2026, 11, 1, 5, 30),
          DateTime.utc(2026, 11, 1, 5, 45),
        ).withEndMinute(120),
        beforeTheChange,
      );
      final free = check.nextFree!;
      expect(free.lengthMinutes, 30);
      expect(check.withSchedule(free).admitted, isTrue);
    });

    test("SC17 the next free range of a later-pass schedule lies in that "
        "pass", () {
      final shared = entryInNewYork(
        "shared",
        DateTime.utc(2026, 11, 1, 6, 30),
        DateTime.utc(2026, 11, 1, 6, 45),
      );
      final check = newCheck(
        unrestricted,
        inNewYorkFrom(
          DateTime.utc(2026, 11, 1, 6, 30),
          DateTime.utc(2026, 11, 1, 7),
        ),
        beforeTheChange,
        others: <CalendarEntry<String>>[shared],
      );
      // Setup sanity: the schedule shares time with the entry.
      expect(check.overlaps, <CalendarEntry<String>>[shared]);
      expect(
        utcOf(check.nextFree!.timesOn(newYork)!.start),
        DateTime.utc(2026, 11, 1, 6, 45),
      );
    });

    test("SC18 a free later-pass schedule is its own next free range", () {
      final free = newCheck(
        unrestricted,
        inNewYorkFrom(
          DateTime.utc(2026, 11, 1, 6, 30),
          DateTime.utc(2026, 11, 1, 7),
        ),
        beforeTheChange,
      ).nextFree!;
      expect(free.lengthMinutes, 30);
      expectTimes(
        free.timesOn(newYork),
        DateTime.utc(2026, 11, 1, 6, 30),
        DateTime.utc(2026, 11, 1, 7),
      );
    });

    test("SC19 an end after the start on the schedule's clock but before it "
        "on now's is not after the start", () {
      ensureZones();
      final havana = tz.getLocation("America/Havana");
      // 01:15 EDT to 01:10 EST, 55 minutes on New York's clock.
      final schedule = inNewYorkFrom(
        DateTime.utc(2026, 11, 1, 5, 15),
        DateTime.utc(2026, 11, 1, 6, 10),
      );
      // Setup sanity: the schedule's own clock puts its end after its start.
      expect(schedule.lengthMinutes, 55);
      // Havana's clock repeats 00:00 to 01:00 on 2026-11-01, so it reads
      // 01:15 once, at 06:15Z, and 01:10 at 06:10Z.
      final check = newCheck(
        unrestricted,
        schedule,
        CalendarNow(
          time: tz.TZDateTime(havana, 2026, 10, 30, 9),
          today: tz.TZDateTime(havana, 2026, 10, 30),
        ),
      );
      expect(
        (
          check.problems.contains(const CalendarScheduleEndNotAfterStart()),
          check.timesChecked,
        ),
        (true, false),
      );
    });

    test("SC20 making the check asks the zone as often for a schedule two "
        "years long as for one a year long", () {
      final zone = CountingLocation(newYork);
      final now = CalendarNow(
        time: tz.TZDateTime(zone, 2026, 10, 30, 9),
        today: tz.TZDateTime(zone, 2026, 10, 30),
      );
      // From the later 01:30 of 2026-11-01 to that of 2027-11-07 and of
      // 2028-11-05.
      final start = tz.TZDateTime.from(DateTime.utc(2026, 11, 1, 6, 30), zone);
      int lookupsTo(DateTime end) {
        final schedule = CalendarSchedule.of(
          start,
          tz.TZDateTime.from(end, zone),
          isAllDay: false,
        );
        zone.lookups = 0;
        newCheck(unrestricted, schedule, now);
        return zone.lookups;
      }

      final yearLong = lookupsTo(DateTime.utc(2027, 11, 7, 6, 30));
      // Setup sanity: making the check reads the counting zone.
      expect(yearLong, greaterThan(0));
      expect(lookupsTo(DateTime.utc(2028, 11, 5, 6, 30)), yearLong);
    });

    test("SC21 a later-pass start after a first-pass now is admitted, and "
        "its next free range lies in its pass", () {
      final now = nowOnTheChange(DateTime.utc(2026, 11, 1, 5, 45));
      final start = inNewYork(DateTime.utc(2026, 11, 1, 6));
      // Setup sanity: 06:00Z reads 01:00 at -5h.
      expect(
        (start.hour, start.minute, start.timeZoneOffset),
        (1, 0, const Duration(hours: -5)),
      );
      final schedule = inNewYorkFrom(
        DateTime.utc(2026, 11, 1, 6),
        DateTime.utc(2026, 11, 1, 6, 30),
      );
      final check = newCheck(lockNow, schedule, now);
      final shared = newCheck(
        lockNow,
        schedule,
        now,
        others: <CalendarEntry<String>>[
          entryInNewYork(
            "shared",
            DateTime.utc(2026, 11, 1, 6),
            DateTime.utc(2026, 11, 1, 6, 15),
          ),
        ],
      );
      final free = check.nextFree?.timesOn(newYork);
      final sharedFree = shared.nextFree?.timesOn(newYork);
      expect(
        (
          check.admitted,
          free == null ? null : (utcOf(free.start), utcOf(free.end)),
          sharedFree == null ? null : utcOf(sharedFree.start),
        ),
        (
          true,
          (DateTime.utc(2026, 11, 1, 6), DateTime.utc(2026, 11, 1, 6, 30)),
          DateTime.utc(2026, 11, 1, 6, 15),
        ),
      );
    });

    test("SC22 the next free range starts at the earliest start in its "
        "pass, after a first-pass start", () {
      final check = newCheck(
        lockNow,
        CalendarSchedule.of(
          tz.TZDateTime(newYork, 2026, 11, 1, 1, 50),
          tz.TZDateTime(newYork, 2026, 11, 1, 2, 20),
          isAllDay: false,
        ),
        nowOnTheChange(DateTime.utc(2026, 11, 1, 6, 45)),
      );
      expect(check.nextFree!.startMinute, 105);
    });

    test("SC23 the next free range lasts the schedule's elapsed length, so "
        "it fits between entries across the clock going back", () {
      final free = newCheck(
        unrestricted,
        inNewYorkFrom(
          DateTime.utc(2026, 11, 1, 5, 15),
          DateTime.utc(2026, 11, 1, 6, 10),
        ),
        beforeTheChange,
        others: <CalendarEntry<String>>[
          entryInNewYork(
            "early",
            DateTime.utc(2026, 11, 1, 5),
            DateTime.utc(2026, 11, 1, 5, 20),
          ),
          entryInNewYork(
            "late",
            DateTime.utc(2026, 11, 1, 6, 30),
            DateTime.utc(2026, 11, 1, 7),
          ),
        ],
      ).nextFree;
      expect(free, isNotNull);
      expectTimes(
        free!.timesOn(newYork),
        DateTime.utc(2026, 11, 1, 5, 30),
        DateTime.utc(2026, 11, 1, 6, 25),
      );
      expect(free.lengthMinutes, 55);
    });

    test("SC25 the next free range of a schedule before a stretch the clock "
        "repeats is the stretch's free second pass, before the free time "
        "after it", () {
      final check = newCheck(
        unrestricted,
        // 00:30 EDT to 01:00 EDT.
        inNewYorkFrom(
          DateTime.utc(2026, 11, 1, 4, 30),
          DateTime.utc(2026, 11, 1, 5),
        ),
        beforeTheChange,
        others: <CalendarEntry<String>>[
          // 00:00 EDT to the instant the clock goes back.
          entryInNewYork(
            "a",
            DateTime.utc(2026, 11, 1, 4),
            DateTime.utc(2026, 11, 1, 6),
          ),
          // 02:00 EST to 04:00 EST.
          entryInNewYork(
            "b",
            DateTime.utc(2026, 11, 1, 7),
            DateTime.utc(2026, 11, 1, 9),
          ),
        ],
      );
      // Setup sanity: the schedule shares the first pass's entry's time.
      expect(check.overlaps.map((entry) => entry.id), <String>["a"]);
      final free = check.nextFree;
      expect(free, isNotNull);
      expectTimes(
        free!.timesOn(newYork),
        DateTime.utc(2026, 11, 1, 6),
        DateTime.utc(2026, 11, 1, 6, 30),
      );
    });

    test("SC29 the next free range under the lock at a time after the first "
        "pass's last slot is the stretch's free second pass", () {
      final check = newCheck(
        lockNow,
        // 00:30 EDT to 01:00 EDT.
        inNewYorkFrom(
          DateTime.utc(2026, 11, 1, 4, 30),
          DateTime.utc(2026, 11, 1, 5),
        ),
        // 01:50 EDT, after the first pass's last slot, 01:45 EDT.
        nowOnTheChange(DateTime.utc(2026, 11, 1, 5, 50)),
      );
      final free = check.nextFree;
      expect(free, isNotNull);
      expectTimes(
        free!.timesOn(newYork),
        DateTime.utc(2026, 11, 1, 6),
        DateTime.utc(2026, 11, 1, 6, 30),
      );
    });

    test("SC26 the next free range in hours that end with a stretch the "
        "clock repeats at the day's end is its second pass where the first "
        "is taken (Santiago, 2026-04-04)", () {
      final santiago = tz.getLocation("America/Santiago");
      tz.TZDateTime inSantiago(DateTime utc) {
        return tz.TZDateTime.from(utc, santiago);
      }

      final first = CalendarEntry<String>(
        id: "first",
        // 23:00 -03 to 24:00 -03.
        start: inSantiago(DateTime.utc(2026, 4, 5, 2)),
        end: inSantiago(DateTime.utc(2026, 4, 5, 3)),
        title: "first",
        color: const Color(0xFF336699),
        payload: "first",
      );
      final check = CalendarScheduleCheck<String>(
        schedule: CalendarSchedule.of(
          inSantiago(DateTime.utc(2026, 4, 5, 2)),
          inSantiago(DateTime.utc(2026, 4, 5, 2, 30)),
          isAllDay: false,
        ),
        rules: rulesOf(unrestricted, hours: CalendarDayHours(23 * 60, 24 * 60)),
        now: CalendarNow(
          time: tz.TZDateTime(santiago, 2026, 4, 1, 9),
          today: tz.TZDateTime(santiago, 2026, 4, 1),
        ),
        others: <CalendarEntry<String>>[first],
      );
      // Setup sanity: the schedule lies in the first pass, which it shares.
      expect(check.overlaps.map((entry) => entry.id), <String>["first"]);
      final free = check.nextFree;
      expect(free, isNotNull);
      expectTimes(
        free!.timesOn(santiago),
        DateTime.utc(2026, 4, 5, 3),
        DateTime.utc(2026, 4, 5, 3, 30),
      );
    });
  });

  test("SC27 the next free range of a stored entry whose start the policy "
      "keeps is none, as the check admits no other start; one whose start "
      "the policy lets move gets the free range after the overlap", () {
    final stored = entryOf("s", tuesday, 9 * 60, 11 * 60);
    final other = entryOf("o", tuesday, 10 * 60 + 30, 11 * 60);
    final rules = rulesOf(
      CalendarEditPolicy<String>.all(<CalendarEditPolicy<String>>[
        const HistoryLockPolicy<String>(lockEarlierToday: true),
        const NoOverlapsPolicy<String>(),
      ]),
    );
    CalendarScheduleCheck<String> checkAt(int hour) {
      return CalendarScheduleCheck<String>(
        schedule: timed(tuesday, 9 * 60, 11 * 60),
        rules: rules,
        now: CalendarNow(time: DateTime(2026, 4, 21, hour), today: tuesday),
        others: <CalendarEntry<String>>[stored, other],
        entry: stored,
      );
    }

    final kept = checkAt(10);
    // Setup sanity: at 10:00 the policy keeps the start, and the overlap is
    // refused.
    expect(kept.startFixed, isTrue);
    expect(kept.problems, <CalendarScheduleProblem>[
      CalendarScheduleOverlapRefused<String>(other),
    ]);
    expect(kept.nextFree, isNull);
    final moving = checkAt(8);
    expect(moving.startFixed, isFalse);
    expect(moving.nextFree, timed(tuesday, 11 * 60, 13 * 60));
  });

  test("SC28 the next free range shares time with no other entry, under a "
      "policy that lets some overlaps be: none where the day has no free "
      "range, and otherwise the first free one", () {
    CalendarScheduleCheck<String> checkWith(int softEnd) {
      return CalendarScheduleCheck<String>(
        schedule: timed(tuesday, 10 * 60, 11 * 60),
        rules: rulesOf(
          const _SoftOverlaps(),
          hours: CalendarDayHours(9 * 60, 17 * 60),
        ),
        now: CalendarNow(time: DateTime(2026, 4, 21, 8), today: tuesday),
        others: <CalendarEntry<String>>[entryOf("soft", tuesday, 0, softEnd)],
      );
    }

    final allDaySoft = checkWith(23 * 60);
    // Setup sanity: the policy lets the schedule share the soft entry.
    expect(allDaySoft.admitted, isTrue);
    expect(allDaySoft.overlaps.map((entry) => entry.id), <String>["soft"]);
    expect(allDaySoft.nextFree, isNull);
    final morningSoft = checkWith(12 * 60);
    expect(morningSoft.nextFree, timed(tuesday, 12 * 60, 13 * 60));
  });

  test("SC24 the next free range of a stored entry kept before the hours "
      "lies in the hours, so the check admits it", () {
    final stored = entryOf("stored", tuesday, 7 * 60, 8 * 60);
    final check = CalendarScheduleCheck<String>(
      schedule: timed(tuesday, 7 * 60, 8 * 60),
      rules: rulesOf(unrestricted, hours: CalendarDayHours(9 * 60, 17 * 60)),
      now: CalendarNow(time: DateTime(2026, 4, 20, 12), today: monday),
      others: <CalendarEntry<String>>[
        stored,
        entryOf("other", tuesday, 7 * 60, 7 * 60 + 30),
      ],
      entry: stored,
    );
    expect(check.admitted, isTrue);
    expect(check.overlaps.map((entry) => entry.id), <String>["other"]);
    final free = check.nextFree;
    expect(free, timed(tuesday, 9 * 60, 10 * 60));
    expect(check.withSchedule(free!).problems, isEmpty);
  });

  test("SC30 an earliest start the policy gives on another clock is read on "
      "the schedule's: the first start minute and the next free range agree "
      "with the problems", () {
    ensureZones();
    final newYork = tz.getLocation("America/New_York");
    final now = CalendarNow(
      time: tz.TZDateTime(newYork, 2026, 4, 20, 12),
      today: tz.TZDateTime(newYork, 2026, 4, 20),
    );
    // 09:00 EDT is 13:00 on UTC's clock, and 21:00 EDT 01:00 of the next
    // day.
    for (final earliest in <int>[9, 21]) {
      CalendarScheduleCheck<String> checkAt(int hour) {
        return CalendarScheduleCheck<String>(
          schedule: CalendarSchedule.of(
            tz.TZDateTime(newYork, 2026, 4, 21, hour),
            tz.TZDateTime(newYork, 2026, 4, 21, hour + 1),
            isAllDay: false,
          ),
          rules: rulesOf(_EarliestInUtc(earliest)),
          now: now,
        );
      }

      final reason = "from $earliest:00 EDT";
      expect(checkAt(earliest - 1).problems, <CalendarScheduleProblem>[
        const CalendarScheduleBeforeEarliest(),
      ], reason: reason);
      final check = checkAt(earliest + 1);
      expect(check.problems, isEmpty, reason: reason);
      expect(check.firstStartMinute, earliest * 60, reason: reason);
      expect(check.nextFree, check.schedule, reason: reason);
    }
  });
}
