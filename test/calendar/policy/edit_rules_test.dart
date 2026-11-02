/// The edit rules: where a new entry may start on a day, the first slot a
/// create takes, the times a change may take, the day limit, and what
/// making and updating the rules asks of their policy.
library;

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/edit_policy.dart';
import 'package:widgets_extended/calendar/policy/edit_rules.dart';

import '../dst_days.dart';

final DateTime monday = DateTime(2026, 4, 20);

/// A Tuesday.
final DateTime tuesday = DateTime(2026, 4, 21);

final DateTime wednesday = DateTime(2026, 4, 22);
final DateTime thursday = DateTime(2026, 4, 23);

/// 08:00 to 18:00.
final CalendarDayHours office = CalendarDayHours(8 * 60, 18 * 60);

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

/// A policy with the day limit [dayLimit] and the answer on overlaps
/// [allowsOverlaps], admitting a change where [admits] does, told whether
/// the change is all-day, that counts each ask by the member's name in
/// [asks]. Compared by identity.
final class _Asking extends CalendarEditPolicy<String> {
  _Asking({int? dayLimit, bool allowsOverlaps = true, this.admits})
    : _dayLimit = dayLimit,
      _allowsOverlaps = allowsOverlaps;

  final int? _dayLimit;
  final bool _allowsOverlaps;
  final bool Function(DateTime start, DateTime end, bool isAllDay)? admits;

  final Map<String, int> asks = <String, int>{};

  void _note(String name) {
    asks[name] = (asks[name] ?? 0) + 1;
  }

  @override
  bool admitsChange(
    CalendarEntry<String> entry,
    DateTime start,
    DateTime end,
    CalendarNow now, {
    required bool isAllDay,
  }) {
    _note("admitsChange");
    final admits = this.admits;
    return admits == null || admits(start, end, isAllDay);
  }

  @override
  int? get dayLimit {
    _note("dayLimit");
    return _dayLimit;
  }

  @override
  bool get allowsOverlaps {
    _note("allowsOverlaps");
    return _allowsOverlaps;
  }
}

/// Unrestricted rules in [hours] and slots of [slotMinutes].
CalendarEditRules<String> rulesOf({
  CalendarDayHours hours = CalendarDayHours.allDay,
  int slotMinutes = 15,
}) {
  return CalendarEditRules<String>(
    policy: const UnrestrictedEditPolicy<String>(),
    hours: hours,
    slotMinutes: slotMinutes,
  );
}

/// Throws an [ArgumentError] whose name is [name].
Matcher throwsArgumentNamed(String name) {
  return throwsA(isArgumentError.having((error) => error.name, "name", name));
}

/// The slot from [start] to [end] as a record.
({DateTime start, DateTime end}) slot(DateTime start, DateTime end) {
  return (start: start, end: end);
}

void main() {
  final now = CalendarNow(time: at(tuesday, 11, 7), today: tuesday);

  test("ER1 an earliest start closes its day for none and for one on a "
      "later day, admits the day's start from it and before it, takes the "
      "occurrence of one after it, and gives its first minutes, one more "
      "inside a minute, rounded up to the slot grid", () {
    final number = dayNumber(tuesday);
    CalendarEarliestStart startAt(DateTime? earliest) {
      return CalendarEarliestStart(tuesday, earliest);
    }

    for (final earliest in <DateTime?>[null, wednesday, at(wednesday, 9)]) {
      final start = startAt(earliest);
      expect(start.closesDay, isTrue, reason: "$earliest");
      expect(start.admitsDayStart, isFalse, reason: "$earliest");
      expect(start.occurrence, earliest, reason: "$earliest");
      expect(start.firstWallMinute, (number + 1) * minutesPerDay);
      expect(start.firstSlotMinute(15), minutesPerDay, reason: "$earliest");
    }
    for (final earliest in <DateTime>[tuesday, at(monday, 22)]) {
      final start = startAt(earliest);
      expect(start.closesDay, isFalse, reason: "$earliest");
      expect(start.admitsDayStart, isTrue, reason: "$earliest");
      expect(start.occurrence, isNull, reason: "$earliest");
      expect(start.firstWallMinute, number * minutesPerDay);
      expect(start.firstSlotMinute(15), 0, reason: "$earliest");
    }
    final later = startAt(at(tuesday, 11, 7));
    expect(later.closesDay, isFalse);
    expect(later.admitsDayStart, isFalse);
    expect(later.occurrence, at(tuesday, 11, 7));
    expect(later.firstWallMinute, number * minutesPerDay + 667);
    expect(later.firstSlotMinute(15), 675);
    expect(later.firstSlotMinute(30), 690);
    expect(startAt(at(tuesday, 11, 15)).firstSlotMinute(15), 675);
    final inside = startAt(at(tuesday, 11, 15, 30));
    expect(inside.firstWallMinute, number * minutesPerDay + 676);
    expect(inside.firstSlotMinute(15), 690);
  });

  test("ER2 the first slot is the earliest of the hours clear of the given "
      "entries, the hours' first with none given, and none where every "
      "slot meets one", () {
    final rules = rulesOf();
    final start = CalendarEarliestStart(tuesday, tuesday);
    expect(
      rules.firstSlot(
        start,
        clearOf: <CalendarEntry<String>>[
          entryOf("one", tuesday, at(tuesday, 1)),
          entryOf("two", at(tuesday, 1, 15), at(tuesday, 2)),
        ],
      ),
      slot(at(tuesday, 1), at(tuesday, 1, 15)),
    );
    final busy = <CalendarEntry<String>>[
      entryOf("day", tuesday, at(tuesday, 23, 59)),
    ];
    expect(rules.firstSlot(start, clearOf: busy), isNull);
    expect(rules.firstSlot(start), slot(tuesday, at(tuesday, 0, 15)));
  });

  test("ER3 a day free only in the hours' last slot gets that slot", () {
    final rules = rulesOf(hours: CalendarDayHours(540, 720));
    expect(
      rules.firstSlot(
        CalendarEarliestStart(tuesday, tuesday),
        clearOf: <CalendarEntry<String>>[
          entryOf("one", at(tuesday, 9), at(tuesday, 11, 45)),
        ],
      ),
      slot(at(tuesday, 11, 45), at(tuesday, 12)),
    );
  });

  test("ER4 the first slot from an earliest start starts there, rounded up "
      "to the slots and no earlier than the hours, steps by the slot "
      "length, and keeps inside the minutes it is given", () {
    final rules = rulesOf(hours: CalendarDayHours(480, 1200));
    final entries = <CalendarEntry<String>>[
      entryOf("one", at(tuesday, 8), at(tuesday, 9)),
      entryOf("two", at(tuesday, 15), at(tuesday, 16)),
    ];
    ({DateTime start, DateTime end})? from(DateTime earliest) {
      return rules.firstSlot(
        CalendarEarliestStart(tuesday, earliest),
        clearOf: entries,
      );
    }

    expect(from(at(tuesday, 14)), slot(at(tuesday, 14), at(tuesday, 14, 15)));
    // 14:10 rounds up to 14:15.
    expect(
      from(at(tuesday, 14, 10)),
      slot(at(tuesday, 14, 15), at(tuesday, 14, 30)),
    );
    // Each slot from 15:00 meets "two" until it ends.
    expect(from(at(tuesday, 15)), slot(at(tuesday, 16), at(tuesday, 16, 15)));
    expect(from(at(tuesday, 5)), slot(at(tuesday, 9), at(tuesday, 9, 15)));
    expect(from(at(tuesday, 20)), isNull);

    final halfHours = rulesOf(slotMinutes: 30);
    final early = <CalendarEntry<String>>[
      entryOf("early", at(tuesday, 0, 10), at(tuesday, 0, 40)),
    ];
    final dayStart = CalendarEarliestStart(tuesday, tuesday);
    // 00:00 to 00:30 and 00:30 to 01:00 meet "early"; in slots of 15,
    // 00:45 is free.
    expect(
      halfHours.firstSlot(dayStart, clearOf: early),
      slot(at(tuesday, 1), at(tuesday, 1, 30)),
    );
    expect(
      rulesOf().firstSlot(dayStart, clearOf: early),
      slot(at(tuesday, 0, 45), at(tuesday, 1)),
    );
    // A start from 10:05 rounds up to 10:30, and so does one from
    // 10:00:30, part of whose minute has passed.
    for (final earliest in <DateTime>[
      at(tuesday, 10, 5),
      at(tuesday, 10, 0, 30),
    ]) {
      expect(
        halfHours.firstSlot(CalendarEarliestStart(tuesday, earliest)),
        slot(at(tuesday, 10, 30), at(tuesday, 11)),
        reason: "$earliest",
      );
    }

    // Inside the minutes 600 to 660, from the day's start.
    expect(
      rulesOf().firstSlot(dayStart, from: 600, until: 660),
      slot(at(tuesday, 10), at(tuesday, 10, 15)),
    );
    expect(rulesOf().firstSlot(dayStart, from: 600, until: 610), isNull);
  });

  test("ER5 times outside the hours are refused without asking the "
      "policy; any other, and every all-day range, takes the policy's "
      "answer, asked once", () {
    final policy = _Asking(
      admits: (start, end, isAllDay) {
        return start != at(tuesday, 10);
      },
    );
    final rules = CalendarEditRules<String>(
      policy: policy,
      hours: office,
      slotMinutes: 15,
    );
    final entry = entryOf("entry", at(tuesday, 9), at(tuesday, 10));
    expect(
      rules.admitsTimes(
        entry,
        at(tuesday, 7),
        at(tuesday, 8),
        now,
        isAllDay: false,
      ),
      isFalse,
    );
    expect(policy.asks["admitsChange"], isNull);
    expect(
      rules.admitsTimes(
        entry,
        at(tuesday, 9),
        at(tuesday, 10),
        now,
        isAllDay: false,
      ),
      isTrue,
    );
    expect(policy.asks["admitsChange"], 1);
    expect(
      rules.admitsTimes(
        entry,
        at(tuesday, 10),
        at(tuesday, 11),
        now,
        isAllDay: false,
      ),
      isFalse,
    );
    expect(policy.asks["admitsChange"], 2);
    expect(
      rules.admitsTimes(entry, tuesday, wednesday, now, isAllDay: true),
      isTrue,
    );
    expect(policy.asks["admitsChange"], 3);
  });

  test("ER6 rules read the day limit and the answer on overlaps once, when "
      "made; an update to new hours or slots, or to an equal policy, asks "
      "nothing, and one to another policy reads them of it", () {
    final policy = _Asking(dayLimit: 2, allowsOverlaps: false);
    final rules = CalendarEditRules<String>(
      policy: policy,
      hours: office,
      slotMinutes: 15,
    );
    expect(policy.asks, <String, int>{"dayLimit": 1, "allowsOverlaps": 1});
    expect(rules.dayLimit, 2);
    expect(rules.allowsOverlaps, isFalse);
    expect(
      identical(
        rules.updated(policy: policy, hours: office, slotMinutes: 15),
        rules,
      ),
      isTrue,
    );
    final moved = rules.updated(
      policy: policy,
      hours: CalendarDayHours.allDay,
      slotMinutes: 30,
    );
    expect(policy.asks, <String, int>{"dayLimit": 1, "allowsOverlaps": 1});
    expect(identical(moved.policy, policy), isTrue);
    expect(moved.hours, CalendarDayHours.allDay);
    expect(moved.slotMinutes, 30);
    expect(moved.dayLimit, 2);
    expect(moved.allowsOverlaps, isFalse);

    final other = _Asking(dayLimit: 3);
    final retaken = rules.updated(
      policy: other,
      hours: office,
      slotMinutes: 15,
    );
    expect(identical(retaken.policy, other), isTrue);
    expect(other.asks, <String, int>{"dayLimit": 1, "allowsOverlaps": 1});
    expect(retaken.dayLimit, 3);
    expect(retaken.allowsOverlaps, isTrue);

    // Equal policies, not identical: the rules keep the one they hold.
    // ignore: prefer_const_constructors
    final first = UnrestrictedEditPolicy<String>();
    final unrestricted = CalendarEditRules<String>(
      policy: first,
      hours: office,
      slotMinutes: 15,
    );
    // ignore: prefer_const_constructors
    final equal = UnrestrictedEditPolicy<String>();
    expect(identical(equal, first), isFalse);
    expect(
      identical(
        unrestricted.updated(policy: equal, hours: office, slotMinutes: 15),
        unrestricted,
      ),
      isTrue,
    );
    final same = CalendarEditRules<String>(
      policy: equal,
      hours: office,
      slotMinutes: 15,
    );
    expect(same, unrestricted);
    expect(same.hashCode, unrestricted.hashCode);
    expect(
      CalendarEditRules<String>(policy: equal, hours: office, slotMinutes: 30),
      isNot(unrestricted),
    );
    expect(
      CalendarEditRules<String>(
        policy: equal,
        hours: CalendarDayHours.allDay,
        slotMinutes: 15,
      ),
      isNot(unrestricted),
    );
  });

  test("ER7 the day limit admits a range covering at most its days, and "
      "holds a longer one at them: a timed one at the hours, an all-day "
      "one at a day's start", () {
    final rules = CalendarEditRules<String>(
      policy: _Asking(dayLimit: 2),
      hours: office,
      slotMinutes: 15,
    );
    expect(rules.coversAtMost(at(tuesday, 9), at(wednesday, 10)), isTrue);
    expect(rules.coversAtMost(at(tuesday, 9), at(thursday, 10)), isFalse);
    expect(rules.coversAtMost(monday, wednesday), isTrue);
    expect(rules.coversAtMost(monday, thursday), isFalse);
    expect(
      rules.heldToLimit(
        at(tuesday, 9),
        at(thursday, 10),
        atEnd: true,
        isAllDay: false,
      ),
      slot(at(tuesday, 9), at(wednesday, 18)),
    );
    expect(
      rules.heldToLimit(
        at(tuesday, 9),
        at(thursday, 10),
        atEnd: false,
        isAllDay: false,
      ),
      slot(at(wednesday, 8), at(thursday, 10)),
    );
    expect(
      rules.heldToLimit(monday, thursday, atEnd: true, isAllDay: true),
      slot(monday, wednesday),
    );
    expect(
      rules.heldToLimit(monday, thursday, atEnd: false, isAllDay: true),
      slot(tuesday, thursday),
    );

    final unlimited = rulesOf(hours: office);
    expect(unlimited.coversAtMost(monday, thursday), isTrue);
    expect(
      unlimited.heldToLimit(
        at(tuesday, 9),
        at(thursday, 10),
        atEnd: true,
        isAllDay: false,
      ),
      slot(at(tuesday, 9), at(thursday, 10)),
    );
  });

  test("ER10 rules of the same policy, hours and slots under other type "
      "arguments are unequal either way round", () {
    const policy = UnrestrictedEditPolicy<String>();
    final ofObjects = CalendarEditRules<Object>(
      policy: policy,
      hours: office,
      slotMinutes: 15,
    );
    final ofStrings = CalendarEditRules<String>(
      policy: policy,
      hours: office,
      slotMinutes: 15,
    );
    expect(ofObjects, isNot(ofStrings));
    expect(ofStrings, isNot(ofObjects));
  });

  test("ER11 an earliest start's day is a local day's start, or it throws "
      "an ArgumentError", () {
    expect(() {
      return CalendarEarliestStart(at(tuesday, 12), at(tuesday, 9));
    }, throwsArgumentNamed("day"));
    expect(() {
      return CalendarEarliestStart(DateTime.utc(2026, 4, 21), at(tuesday, 9));
    }, throwsArgumentNamed("day"));
    expect(CalendarEarliestStart(tuesday, at(tuesday, 9)).day, tuesday);
  });

  test(
    "RC7 an earliest start takes a UTC earliest as its local time, the "
    "same instant, and answers for it as for the local one",
    skip: offUtcSkip,
    () {
      final dayStart = CalendarEarliestStart(tuesday, tuesday);
      final dayStartUtc = CalendarEarliestStart(tuesday, tuesday.toUtc());
      expect(dayStartUtc.earliest, dayStart.earliest);
      expect(dayStartUtc.earliest!.isUtc, isFalse);

      final time = offUtcTime!;
      final utc = time.toUtc();
      final utcDate = DateTime(utc.year, utc.month, utc.day);
      // The earlier of time's local and UTC dates: time's local date
      // closes it in a zone east of UTC, and its UTC date in one west.
      final day = utcDate.isBefore(tuesday) ? utcDate : tuesday;
      final later = CalendarEarliestStart(day, time);
      final laterUtc = CalendarEarliestStart(day, utc);
      expect(laterUtc.earliest, later.earliest);
      expect(laterUtc.earliest!.isUtc, isFalse);
      expect(laterUtc.closesDay, later.closesDay);
      expect(laterUtc.occurrence, later.occurrence);
      expect(laterUtc.occurrence!.isUtc, isFalse);
      expect(laterUtc.firstWallMinute, later.firstWallMinute);
      expect(laterUtc.firstSlotMinute(15), later.firstSlotMinute(15));
    },
  );

  test("RC4 rules throw an ArgumentError for a policy whose day limit is "
      "under 1, a combined one included", () {
    expect(() {
      return CalendarEditRules<String>(
        policy: _Asking(dayLimit: 0),
        hours: office,
        slotMinutes: 15,
      );
    }, throwsArgumentNamed("policy"));
    expect(() {
      return CalendarEditRules<String>(
        policy: _Asking(dayLimit: -1),
        hours: office,
        slotMinutes: 15,
      );
    }, throwsArgumentNamed("policy"));
    final combined = CalendarEditPolicy<String>.all(
      <CalendarEditPolicy<String>>[
        DayLimitPolicy<String>(2),
        _Asking(dayLimit: 0),
      ],
    );
    expect(combined.dayLimit, 0);
    expect(() {
      return CalendarEditRules<String>(
        policy: combined,
        hours: office,
        slotMinutes: 15,
      );
    }, throwsArgumentNamed("policy"));
    expect(
      CalendarEditRules<String>(
        policy: _Asking(dayLimit: 1),
        hours: office,
        slotMinutes: 15,
      ).dayLimit,
      1,
    );
  });

  test("RC6 rules throw an ArgumentError for a slot length that is not a "
      "choice and for hours off its grid, the slot length first, as do "
      "updates to them", () {
    final offGrid = CalendarDayHours(8 * 60 + 10, 17 * 60 + 50);
    for (final slotMinutes in <int>[7, 0]) {
      expect(() {
        return rulesOf(hours: office, slotMinutes: slotMinutes);
      }, throwsArgumentNamed("slotMinutes"));
    }
    expect(() {
      return rulesOf(hours: offGrid);
    }, throwsArgumentNamed("hours"));
    expect(() {
      return CalendarEditRules<String>(
        policy: _Asking(dayLimit: 0),
        hours: offGrid,
        slotMinutes: 15,
      );
    }, throwsArgumentNamed("hours"));
    expect(rulesOf(hours: offGrid, slotMinutes: 10).hours, offGrid);

    final rules = rulesOf(hours: office);
    expect(() {
      return rules.updated(
        policy: rules.policy,
        hours: offGrid,
        slotMinutes: 15,
      );
    }, throwsArgumentNamed("hours"));
    expect(() {
      return rules.updated(
        policy: rules.policy,
        hours: office,
        slotMinutes: 45,
      );
    }, throwsArgumentNamed("slotMinutes"));
    expect(() {
      return rules.updated(policy: _Asking(), hours: offGrid, slotMinutes: 15);
    }, throwsArgumentNamed("hours"));
    expect(
      rules
          .updated(policy: rules.policy, hours: office, slotMinutes: 30)
          .slotMinutes,
      30,
    );
  });

  group("on the 23-hour day", skip: shortDaySkip, () {
    test("ER8 hours wholly inside the skipped hour hold no slot", () {
      final day = shortDayStart;
      final rules = rulesOf(
        hours: CalendarDayHours(
          easternSkippedHour * 60,
          (easternSkippedHour + 1) * 60,
        ),
        slotMinutes: 60,
      );
      expect(rules.firstSlot(CalendarEarliestStart(day, day)), isNull);
    });
  });

  group("on the 25-hour day", skip: longDaySkip, () {
    test("ER9 the first slot from the second 01:30 is the one from the "
        "second 01:30", () {
      final day = longDayStart;
      final start = CalendarEarliestStart(day, secondHalfPastOne);
      expect(start.occurrence, secondHalfPastOne);
      expect(
        rulesOf().firstSlot(start),
        slot(
          secondHalfPastOne,
          secondHalfPastOne.add(const Duration(minutes: 15)),
        ),
      );
    });
  });

  test("ER12 the hold, the hours and the policy read the kind each ask is "
      "told", () {
    final limited = CalendarEditRules<String>(
      policy: _Asking(dayLimit: 1),
      hours: CalendarDayHours(0, 18 * 60),
      slotMinutes: 15,
    );
    expect(
      limited.heldToLimit(tuesday, thursday, atEnd: true, isAllDay: false),
      slot(tuesday, at(tuesday, 18)),
    );
    expect(
      limited.heldToLimit(tuesday, thursday, atEnd: true, isAllDay: true),
      slot(tuesday, wednesday),
    );

    final entry = entryOf("entry", at(tuesday, 9), at(tuesday, 10));
    final policy = _Asking();
    final inOffice = CalendarEditRules<String>(
      policy: policy,
      hours: office,
      slotMinutes: 15,
    );
    expect(
      inOffice.admitsTimes(entry, tuesday, wednesday, now, isAllDay: false),
      isFalse,
    );
    expect(policy.asks["admitsChange"], isNull);
    expect(
      inOffice.admitsTimes(entry, tuesday, wednesday, now, isAllDay: true),
      isTrue,
    );
    expect(policy.asks["admitsChange"], 1);

    final timedOnly = CalendarEditRules<String>(
      policy: _Asking(
        admits: (start, end, isAllDay) {
          return !isAllDay;
        },
      ),
      hours: CalendarDayHours.allDay,
      slotMinutes: 15,
    );
    expect(
      timedOnly.admitsTimes(entry, tuesday, wednesday, now, isAllDay: true),
      isFalse,
    );
    expect(
      timedOnly.admitsTimes(entry, tuesday, wednesday, now, isAllDay: false),
      isTrue,
    );
  });

  group(
    "on the day whose clock repeats its midnight",
    skip: repeatedMidnightSkip,
    () {
      test("ER13 the first slot from an earliest start at the later 00:00 "
          "starts at the later 00:00", () {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        expect(
          rulesOf().firstSlot(CalendarEarliestStart(day, laterMidnight)),
          slot(laterMidnight, laterMidnight.add(const Duration(minutes: 15))),
        );
      });
    },
  );

  group(
    "on the day whose clock skips its midnight",
    skip: skippedMidnightSkip,
    () {
      test("ER14 a one-day limit holds a timed range's end at the day's "
          "start, the 24:00 before, and its start at the day's start", () {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final rules = CalendarEditRules<String>(
          policy: DayLimitPolicy<String>(1),
          hours: CalendarDayHours.allDay,
          slotMinutes: 15,
        );
        // Guard: red when the held end converts by the clock.
        expect(
          rules
              .heldToLimit(
                at(before, 22),
                at(addDays(day, 1), 2),
                atEnd: true,
                isAllDay: false,
              )
              ?.end,
          day,
        );
        // Guard: red when the held start converts by the clock.
        expect(
          rules
              .heldToLimit(
                at(addDays(before, -1), 22),
                at(day, 2),
                atEnd: false,
                isAllDay: false,
              )
              ?.start,
          day,
        );
      });
    },
  );
}
