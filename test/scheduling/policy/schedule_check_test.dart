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
        timed(DateTime(2026, 3, 7), 23 * 60, 1440).withLength(90),
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
}
