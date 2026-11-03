/// The wall-clock coordinate of the dates layer: a time's wall minute and
/// back, the wall minutes nearest a time in an occurrence, the last day a
/// range has a part in, a range's piece on a day, the hours rule on starts,
/// ends and ranges, the hours on the grid of a slot length, and the skipped
/// and repeated times of the local zone's DST days, those whose clock skips
/// or repeats its midnight included.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';

import '../dst_days.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);

/// [day] at [hour] and [minute].
DateTime at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

void main() {
  test("DT1 wallMinuteOf and timeAtWallMinute round-trip every quarter hour "
      "of a day, and minute 0 is the day start", () {
    final day = CalendarDates.dayNumber(tuesday) * CalendarDates.minutesPerDay;
    expect(CalendarDates.wallMinuteOf(tuesday), day);
    expect(CalendarDates.timeAtWallMinute(day), tuesday);
    for (var minute = 0; minute < CalendarDates.minutesPerDay; minute += 15) {
      final time = at(tuesday, minute ~/ 60, minute % 60);
      expect(CalendarDates.wallMinuteOf(time), day + minute, reason: "$minute");
      expect(
        CalendarDates.timeAtWallMinute(day + minute),
        time,
        reason: "$minute",
      );
    }
    // A day's 24:00 is the next day's minute 0.
    expect(
      CalendarDates.timeAtWallMinute(day + CalendarDates.minutesPerDay),
      wednesday,
    );
    expect(
      CalendarDates.wallMinuteOf(wednesday),
      day + CalendarDates.minutesPerDay,
    );
  });

  test("DT9 firstWallMinuteNotBefore and lastWallMinuteNotAfter of a whole "
      "minute are its own wall minute, and of a time with seconds the next "
      "and its own", () {
    final nine = at(tuesday, 9);
    final wall = CalendarDates.wallMinuteOf(nine);
    expect(CalendarDates.firstWallMinuteNotBefore(nine), wall);
    expect(CalendarDates.lastWallMinuteNotAfter(nine), wall);
    final past = nine.add(const Duration(seconds: 30));
    expect(CalendarDates.firstWallMinuteNotBefore(past), wall + 1);
    expect(CalendarDates.lastWallMinuteNotAfter(past), wall);
  });

  test("DT13 isLaterOccurrence of a time past its minute, on a day whose "
      "clock reads each time once, is false", () {
    final nine = at(tuesday, 9);
    expect(
      CalendarDates.isLaterOccurrence(nine.add(const Duration(seconds: 30))),
      isFalse,
    );
    expect(
      CalendarDates.isLaterOccurrence(
        nine.add(const Duration(milliseconds: 1)),
      ),
      isFalse,
    );
    expect(
      CalendarDates.isLaterOccurrence(
        nine.add(const Duration(microseconds: 1)),
      ),
      isFalse,
    );
  });

  test("DT3 lastDayNumberOf is the day before an end at a day start, and "
      "the end's own day otherwise", () {
    expect(
      CalendarDates.lastDayNumberOf(at(monday, 22), wednesday),
      CalendarDates.dayNumber(tuesday),
    );
    expect(
      CalendarDates.lastDayNumberOf(at(monday, 22), at(wednesday, 0, 15)),
      CalendarDates.dayNumber(wednesday),
    );
    expect(
      CalendarDates.lastDayNumberOf(monday, tuesday),
      CalendarDates.dayNumber(monday),
    );
    expect(
      CalendarDates.lastDayNumberOf(at(monday, 9), at(monday, 10)),
      CalendarDates.dayNumber(monday),
    );
  });

  test("DT4 pieceOn gives each day's part of a span in its minutes, and "
      "none on a day an end at its start leaves", () {
    final night = CalendarDates.wallSpanOf(at(monday, 22), at(tuesday, 2));
    expect(CalendarDates.pieceOn(night, CalendarDates.dayNumber(monday)), (
      start: 1320,
      end: 1440,
    ));
    expect(CalendarDates.pieceOn(night, CalendarDates.dayNumber(tuesday)), (
      start: 0,
      end: 120,
    ));
    expect(
      CalendarDates.pieceOn(night, CalendarDates.dayNumber(wednesday)),
      isNull,
    );
    expect(
      CalendarDates.pieceOn(night, CalendarDates.dayNumber(monday) - 1),
      isNull,
    );

    final long = CalendarDates.wallSpanOf(at(monday, 10), at(wednesday, 12));
    expect(CalendarDates.pieceOn(long, CalendarDates.dayNumber(monday)), (
      start: 600,
      end: 1440,
    ));
    expect(CalendarDates.pieceOn(long, CalendarDates.dayNumber(tuesday)), (
      start: 0,
      end: 1440,
    ));
    expect(CalendarDates.pieceOn(long, CalendarDates.dayNumber(wednesday)), (
      start: 0,
      end: 720,
    ));

    final toMidnight = CalendarDates.wallSpanOf(at(monday, 22), tuesday);
    expect(CalendarDates.pieceOn(toMidnight, CalendarDates.dayNumber(monday)), (
      start: 1320,
      end: 1440,
    ));
    expect(
      CalendarDates.pieceOn(toMidnight, CalendarDates.dayNumber(tuesday)),
      isNull,
    );
  });

  test("DT5 under 08:00-18:00 the hours hold a start from 08:00 to before "
      "18:00 and an end from after 08:00 to 18:00, a range whose start and "
      "last day's end they hold, and any all-day range", () {
    final office = CalendarDayHours(8 * 60, 18 * 60);
    expect(office.holdsStart(8 * 60), isTrue);
    expect(office.holdsStart(9 * 60 + 10), isTrue);
    expect(office.holdsStart(18 * 60 - 1), isTrue);
    expect(office.holdsStart(18 * 60), isFalse);
    expect(office.holdsStart(8 * 60 - 1), isFalse);
    expect(office.holdsEnd(8 * 60), isFalse);
    expect(office.holdsEnd(8 * 60 + 1), isTrue);
    expect(office.holdsEnd(18 * 60), isTrue);
    expect(office.holdsEnd(18 * 60 + 1), isFalse);

    // An overnight entry starting and ending inside the hours, and one
    // ending after them on its own day.
    expect(
      office.holdsTimes(at(monday, 17), at(tuesday, 9), isAllDay: false),
      isTrue,
    );
    expect(
      office.holdsTimes(at(monday, 17), at(monday, 19), isAllDay: false),
      isFalse,
    );
    expect(
      office.holdsTimes(at(monday, 7), at(monday, 9), isAllDay: false),
      isFalse,
    );
    expect(
      office.holdsTimes(at(monday, 9, 10), at(monday, 9, 50), isAllDay: false),
      isTrue,
    );
    // An end at a day start reads as minute 1440 of the day before.
    expect(
      office.holdsTimes(at(monday, 17), tuesday, isAllDay: false),
      isFalse,
    );
    expect(
      CalendarDayHours.allDay.holdsTimes(
        at(monday, 17),
        tuesday,
        isAllDay: false,
      ),
      isTrue,
    );
    expect(office.holdsTimes(monday, tuesday, isAllDay: true), isTrue);
    expect(
      office.holdsTimes(
        monday,
        CalendarDates.addDays(monday, 3),
        isAllDay: true,
      ),
      isTrue,
    );
  });

  test("DT6 roundedOutTo(30) of 08:10-17:50 is 08:00-18:00, and "
      "isOnSlotsOf(30) holds of 08:00-18:00 and not of 08:10-17:50", () {
    final off = CalendarDayHours(8 * 60 + 10, 17 * 60 + 50);
    final office = CalendarDayHours(8 * 60, 18 * 60);
    expect(off.roundedOutTo(30), office);
    expect(office.roundedOutTo(30), office);
    expect(off.isOnSlotsOf(30), isFalse);
    expect(CalendarDayHours(8 * 60, 17 * 60 + 50).isOnSlotsOf(30), isFalse);
    expect(office.isOnSlotsOf(30), isTrue);
    expect(off.isOnSlotsOf(10), isTrue);
    // Rounded out, the end stays inside the day.
    expect(
      CalendarDayHours(0, CalendarDates.minutesPerDay - 5).roundedOutTo(60),
      CalendarDayHours.allDay,
    );
  });

  test("DT7 slotCountOf(30) of the whole day is 48", () {
    expect(CalendarDayHours.allDay.slotCountOf(30), 48);
    expect(
      CalendarDayHours.allDay.slotCountOf(CalendarDates.defaultSlotMinutes),
      96,
    );
    expect(CalendarDayHours(8 * 60, 18 * 60).slotCountOf(30), 20);
  });

  test("DST1 dstSkipReason answers null for a day found with the expected "
      "hour, and a reason naming the zone the tests are written for "
      "otherwise", () {
    expect(dstSkipReason("23-hour day", tuesday, 2, 2), isNull);
    expect(
      dstSkipReason("23-hour day", null, null, 2),
      allOf(contains("23-hour day"), contains("TZ=America/New_York")),
    );
    expect(
      dstSkipReason("25-hour day", tuesday, 3, 1),
      allOf(
        contains("2026-04-21"),
        contains("from 3, not 1"),
        contains("TZ=America/New_York"),
      ),
    );
  });

  group("on the 23-hour day", skip: shortDaySkip, () {
    test("DST2 the 23-hour day lasts 23 hours and skips 02:00", () {
      final day = shortDayStart;
      expect(
        CalendarDates.addDays(day, 1).difference(day),
        const Duration(hours: 23),
      );
      expect(shortDay!.hour, 2);
      expect(DateTime(day.year, day.month, day.day, 2, 30).hour, isNot(2));
      expect(DateTime(day.year, day.month, day.day, 1, 30).hour, 1);
    });

    test("DT2 timeAtWallMinute of 02:30 is null, the clock skipping it", () {
      final day =
          CalendarDates.dayNumber(shortDayStart) * CalendarDates.minutesPerDay;
      expect(CalendarDates.timeAtWallMinute(day + 2 * 60 + 30), isNull);
      expect(CalendarDates.timeAtWallMinute(day + 2 * 60), isNull);
      expect(CalendarDates.timeAtWallMinute(day + 3 * 60), isNotNull);
      expect(CalendarDates.timeAtWallMinute(day + 60 + 30)!.hour, 1);
    });

    test("DT11 firstWallMinuteNotBefore of 01:59:30 is 03:00, past the "
        "minutes the clock skips", () {
      final day =
          CalendarDates.dayNumber(shortDayStart) * CalendarDates.minutesPerDay;
      final time = at(shortDayStart, 1, 59).add(const Duration(seconds: 30));
      expect(CalendarDates.firstWallMinuteNotBefore(time), day + 3 * 60);
    });
  });

  group("on the 25-hour day", skip: longDaySkip, () {
    test("DST2 the 25-hour day lasts 25 hours and repeats 01:00", () {
      final day = longDayStart;
      expect(
        CalendarDates.addDays(day, 1).difference(day),
        const Duration(hours: 25),
      );
      expect(longDay!.hour, 1);
      // The day start plus two hours reads 01:00 again.
      expect(day.add(const Duration(hours: 1)).hour, 1);
      expect(day.add(const Duration(hours: 2)).hour, 1);
      expect(day.add(const Duration(hours: 3)).hour, 2);
    });

    test("DT8 timeAtWallMinute of 01:30 is the first 01:30, the second "
        "with from: in the day's later stretch, and isLaterOccurrence tells "
        "the two apart", () {
      final day =
          CalendarDates.dayNumber(longDayStart) * CalendarDates.minutesPerDay;
      final first = longDayStart.add(const Duration(minutes: 90));
      final second = secondHalfPastOne;
      // Both read 01:30, an hour apart.
      expect(first.hour, 1);
      expect(second.hour, 1);
      expect(second.difference(first), const Duration(hours: 1));

      expect(CalendarDates.timeAtWallMinute(day + 90), first);
      final secondOne = longDayStart
          .add(const Duration(hours: 1))
          .add(const Duration(hours: 1));
      expect(secondOne.hour, 1);
      expect(CalendarDates.timeAtWallMinute(day + 90, from: secondOne), second);
      final firstOne = longDayStart.add(const Duration(hours: 1));
      expect(CalendarDates.timeAtWallMinute(day + 90, from: firstOne), first);
      expect(
        CalendarDates.timeAtWallMinute(day + 90, from: at(monday, 1, 30)),
        first,
      );
      // A later instant of another day is no occurrence of this one's.
      expect(
        CalendarDates.timeAtWallMinute(
          day + 90,
          from: CalendarDates.addDays(
            longDayStart,
            1,
          ).add(const Duration(hours: 1)),
        ),
        first,
      );

      expect(CalendarDates.isLaterOccurrence(second), isTrue);
      expect(CalendarDates.isLaterOccurrence(first), isFalse);
      expect(CalendarDates.isLaterOccurrence(at(monday, 1, 30)), isFalse);
    });

    test("DT14 isLaterOccurrence of a time past its minute in the repeated "
        "hour tells the occurrences apart as its minute does, and "
        "timeAtWallMinute keeps the first occurrence of from: there", () {
      final day =
          CalendarDates.dayNumber(longDayStart) * CalendarDates.minutesPerDay;
      const past = Duration(seconds: 30);
      final first = longDayStart.add(const Duration(minutes: 90)).add(past);
      final second = secondHalfPastOne.add(past);
      expect(CalendarDates.isLaterOccurrence(first), isFalse);
      expect(CalendarDates.isLaterOccurrence(second), isTrue);
      expect(
        CalendarDates.timeAtWallMinute(day + 105, from: first),
        longDayStart.add(const Duration(minutes: 105)),
      );
    });

    test("DT10 firstWallMinuteNotBefore and lastWallMinuteNotAfter of a time "
        "in the repeated hour are its own wall minute in the occurrence from: "
        "picks, and in the other the edge of the repeated hour", () {
      final day =
          CalendarDates.dayNumber(longDayStart) * CalendarDates.minutesPerDay;
      final firstOne = longDayStart.add(const Duration(hours: 1));
      final secondOne = firstOne.add(const Duration(hours: 1));
      final firstQuarter = firstOne.add(const Duration(minutes: 15));
      final secondQuarter = secondOne.add(const Duration(minutes: 15));
      // The first 01:00 to 02:00, which timeAtWallMinute picks without from:.
      expect(CalendarDates.firstWallMinuteNotBefore(firstQuarter), day + 75);
      expect(CalendarDates.lastWallMinuteNotAfter(firstQuarter), day + 75);
      expect(CalendarDates.firstWallMinuteNotBefore(secondQuarter), day + 120);
      expect(CalendarDates.lastWallMinuteNotAfter(secondQuarter), day + 119);
      // The second, which from: at the second 01:00 picks.
      expect(
        CalendarDates.firstWallMinuteNotBefore(secondQuarter, from: secondOne),
        day + 75,
      );
      expect(
        CalendarDates.lastWallMinuteNotAfter(secondQuarter, from: secondOne),
        day + 75,
      );
      expect(
        CalendarDates.firstWallMinuteNotBefore(firstQuarter, from: secondOne),
        day + 60,
      );
      expect(
        CalendarDates.lastWallMinuteNotAfter(firstQuarter, from: secondOne),
        day + 59,
      );
    });

    test("DT12 timeAtWallMinute's instants rise with the wall minute through "
        "the 25-hour day in either occurrence", () {
      final day =
          CalendarDates.dayNumber(longDayStart) * CalendarDates.minutesPerDay;
      final secondOne = longDayStart.add(const Duration(hours: 2));
      for (final from in <DateTime?>[null, secondOne]) {
        for (var wall = day; wall < day + CalendarDates.minutesPerDay; wall++) {
          final time = CalendarDates.timeAtWallMinute(wall, from: from)!;
          final next = CalendarDates.timeAtWallMinute(wall + 1, from: from)!;
          expect(next.isAfter(time), isTrue, reason: "$wall from $from");
        }
      }
    });

    test("DT23 a range from the first pass ends at 02:00 where the first pass "
        "ends, the second 01:00, and a range from any other start where "
        "endAtWallMinute ends it", () {
      final day =
          CalendarDates.dayNumber(longDayStart) * CalendarDates.minutesPerDay;
      final firstOne = longDayStart.add(const Duration(hours: 1));
      final secondOne = firstOne.add(const Duration(hours: 1));
      final first15 = firstOne.add(const Duration(minutes: 15));
      final first45 = firstOne.add(const Duration(minutes: 45));
      expect(CalendarDates.rangeEndAtWallMinute(first45, day + 120), secondOne);
      expect(
        CalendarDates.rangeEndAtWallMinute(first15, day + 120, from: first15),
        secondOne,
      );
      expect(
        firstReadableSlot(longDayStart, 105, CalendarDates.minutesPerDay, 15),
        (start: first45, end: secondOne),
      );
      expect(
        CalendarDates.lastWallMinuteNotAfter(secondOne, start: first15),
        day + 120,
      );
      // Guard: red when every range to 02:00 ends with the first pass.
      expect(
        CalendarDates.rangeEndAtWallMinute(at(longDayStart, 0, 45), day + 120),
        at(longDayStart, 2),
      );
      // Guard: red when an end past 02:00 stays in the first pass.
      expect(
        CalendarDates.rangeEndAtWallMinute(
          firstOne.add(const Duration(minutes: 30)),
          day + 135,
        ),
        at(longDayStart, 2, 15),
      );
    });

    test("DT24 the hours read an end in the second pass, not after the "
        "start's time, where its span ends", () {
      final firstHalf = longDayStart.add(const Duration(minutes: 90));
      final secondOne = longDayStart.add(const Duration(hours: 2));
      // Drawn from 01:30 to 02:00, the start plus its 30 minutes.
      expect(hoursEndMinuteOf(firstHalf, secondOne), 120);
      expect(
        CalendarDayHours(
          90,
          CalendarDates.minutesPerDay,
        ).holdsTimes(firstHalf, secondOne, isAllDay: false),
        isTrue,
      );
      // Red when the hours read the end at its own 01:00.
      expect(
        CalendarDayHours(
          30,
          100,
        ).holdsTimes(firstHalf, secondOne, isAllDay: false),
        isFalse,
      );
    });
  });

  group(
    "on the day whose clock skips its midnight",
    skip: skippedMidnightSkip,
    () {
      test("DT15 the day's start reads the minute its clock starts at, 01:00, "
          "its minute 0 names no time, and a range ending at the day's start "
          "ends at the 24:00 before", () {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final wall = CalendarDates.dayNumber(day) * CalendarDates.minutesPerDay;
        expect(CalendarDates.wallMinuteOf(day), wall + 60);
        expect(CalendarDates.timeAtWallMinute(wall), isNull);
        // Guard: red when a wall minute converts at its elapsed minutes from
        // the day's start.
        expect(CalendarDates.timeAtWallMinute(wall + 60), day);
        expect(CalendarDates.wallSpanOf(day, at(day, 2)), (
          start: wall + 60,
          end: wall + 120,
        ));
        // Guard: red when a range's end reads by the clock, at +60.
        expect(CalendarDates.wallSpanOf(at(before, 23), day), (
          start: wall - 60,
          end: wall,
        ));
        expect(CalendarDates.firstWallMinuteNotBefore(day), wall + 60);
        expect(firstReadableSlot(day, 0, CalendarDates.minutesPerDay, 60), (
          start: day,
          end: at(day, 2),
        ));
        // Guard: red when only the wall minute reads by the clock, and the
        // instant of minute 0 is the day's start.
        expect(CalendarDates.isLaterOccurrence(day), isFalse);
        // Guard: red when the walk reads by the clock, at +60.
        expect(CalendarDates.lastWallMinuteNotAfter(day), wall);
      });
    },
  );

  group(
    "on the day whose clock repeats its midnight",
    skip: repeatedMidnightSkip,
    () {
      test("DT16 minute 0 names the later 00:00 for a time in the later pass, "
          "and the walks from a time in one pass reach the other's edge", () {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final wall = CalendarDates.dayNumber(day) * CalendarDates.minutesPerDay;
        final later15 = laterMidnight.add(const Duration(minutes: 15));
        final later30 = laterMidnight.add(const Duration(minutes: 30));
        expect(
          CalendarDates.timeAtWallMinute(wall, from: later15),
          laterMidnight,
        );
        // Guards: red when minute 0 names the later 00:00 without from:.
        expect(CalendarDates.timeAtWallMinute(wall), day);
        expect(CalendarDates.isLaterOccurrence(laterMidnight), isTrue);
        final early15 = day.add(const Duration(minutes: 15));
        expect(
          CalendarDates.firstWallMinuteNotBefore(early15, from: later30),
          wall,
        );
        expect(
          CalendarDates.lastWallMinuteNotAfter(early15, from: later30),
          wall - 1,
        );
        expect(
          CalendarDates.firstWallMinuteNotBefore(
            laterMidnight,
            from: laterMidnight,
          ),
          wall,
        );
      });

      test("DT17 the hours hold an end at the later 00:00 where its span ends, "
          "and its days are the clock's", () {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final early15 = day.add(const Duration(minutes: 15));
        expect(
          CalendarDayHours.allDay.holdsTimes(
            at(before, 23),
            laterMidnight,
            isAllDay: false,
          ),
          isTrue,
        );
        expect(
          CalendarDayHours.allDay.holdsTimes(
            early15,
            laterMidnight,
            isAllDay: false,
          ),
          isTrue,
        );
        expect(
          CalendarDayHours(
            0,
            1080,
          ).holdsTimes(day, laterMidnight, isAllDay: false),
          isTrue,
        );
        // From the day before too, the hours read the end at 01:00, where
        // the first pass ends: red when it reads at the 24:00 before it.
        expect(
          CalendarDayHours(
            0,
            1425,
          ).holdsTimes(at(before, 23), laterMidnight, isAllDay: false),
          isTrue,
        );
        expect(
          CalendarDayHours(
            60,
            1440,
          ).holdsTimes(at(before, 23), laterMidnight, isAllDay: false),
          isFalse,
        );
        // Guard: red when it reads before 01:00.
        expect(
          CalendarDayHours(
            59,
            1440,
          ).holdsTimes(at(before, 23), laterMidnight, isAllDay: false),
          isTrue,
        );
        // Guards: red when its last day is the day before, at 24:00.
        expect(
          CalendarDates.lastDayNumberOf(at(before, 23), laterMidnight),
          CalendarDates.dayNumber(day),
        );
        expect(CalendarDates.endMinuteOfDay(laterMidnight), 0);
        // Its last day holds the first pass, 00:00 to 01:00.
        final span = CalendarDates.wallSpanOf(at(before, 23), laterMidnight);
        expect(CalendarDates.pieceOn(span, CalendarDates.dayNumber(day)), (
          start: 0,
          end: 60,
        ));
      });

      test("DT25 a range from the first pass ends at 01:00 where the first "
          "pass ends, the later 00:00, and one from the day before at the "
          "01:00 after the second pass", () {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final wall = CalendarDates.dayNumber(day) * CalendarDates.minutesPerDay;
        final first45 = day.add(const Duration(minutes: 45));
        expect(
          CalendarDates.rangeEndAtWallMinute(first45, wall + 60),
          laterMidnight,
        );
        expect(firstReadableSlot(day, 45, CalendarDates.minutesPerDay, 15), (
          start: first45,
          end: laterMidnight,
        ));
        // Guard: red when every range to 01:00 ends with the first pass.
        expect(
          CalendarDates.rangeEndAtWallMinute(at(before, 23, 45), wall + 60),
          at(day, 1),
        );
      });
    },
  );

  group(
    "on the day whose clock repeats its last hour",
    skip: repeatedLastHourSkip,
    () {
      test("DT26 the first 23:30 to the second 23:30 spans to the day's "
          "24:00, the end of its last day, where the hours read its end", () {
        final day = longDayStart;
        expectRepeatedLastHour(day);
        final wall = CalendarDates.dayNumber(day) * CalendarDates.minutesPerDay;
        final first = day.add(const Duration(minutes: 23 * 60 + 30));
        final second = laterLastHour.add(const Duration(minutes: 30));
        // Setup sanity: the second reads 23:30 of the day, an hour on.
        expect(
          (second.difference(first), second.day, second.hour, second.minute),
          (const Duration(hours: 1), day.day, 23, 30),
        );
        expect(CalendarDates.wallSpanOf(first, second), (
          start: wall + 1410,
          end: wall + CalendarDates.minutesPerDay,
        ));
        expect(hoursEndMinuteOf(first, second), CalendarDates.minutesPerDay);
        expect(
          CalendarDayHours.allDay.holdsTimes(first, second, isAllDay: false),
          isTrue,
        );
      });

      test("DT27 a range from the first pass ends at 24:00 where the first "
          "pass ends, the later 23:00, and one from 22:45 at the next day's "
          "start", () {
        final day = longDayStart;
        expectRepeatedLastHour(day);
        final next =
            CalendarDates.dayNumber(day) * CalendarDates.minutesPerDay +
            CalendarDates.minutesPerDay;
        final first45 = day.add(const Duration(minutes: 23 * 60 + 45));
        expect(
          CalendarDates.rangeEndAtWallMinute(first45, next),
          laterLastHour,
        );
        expect(firstReadableSlot(day, 1425, CalendarDates.minutesPerDay, 15), (
          start: first45,
          end: laterLastHour,
        ));
        // Guard: red when every range to 24:00 ends with the first pass.
        expect(
          CalendarDates.rangeEndAtWallMinute(at(day, 22, 45), next),
          DateTime(day.year, day.month, day.day + 1),
        );
      });
    },
  );

  test("DST3 the midnight tests' reasons name the Havana script, and skip "
      "exactly where the zone's DST days do not change the hour from "
      "00:00", () {
    expect(
      dstSkipReason("23-hour day", tuesday, 0, midnightHour, run: havanaRun),
      isNull,
    );
    expect(
      dstSkipReason("23-hour day", null, null, midnightHour, run: havanaRun),
      allOf(
        contains("America/Havana"),
        contains("tool/test_calendar_in_havana.sh"),
      ),
    );
    expect(
      dstSkipReason("23-hour day", tuesday, 2, midnightHour, run: havanaRun),
      allOf(
        contains("from 2, not 0"),
        contains("America/Havana"),
        contains("tool/test_calendar_in_havana.sh"),
      ),
    );
    // In the zone the tests run in: the null branch in America/Havana and
    // the other in America/New_York.
    for (final (reason, found) in <(String?, DstDay?)>[
      (skippedMidnightSkip, shortDay),
      (repeatedMidnightSkip, longDay),
    ]) {
      expect(reason == null, found?.hour == midnightHour, reason: "$found");
      if (reason != null) {
        expect(
          reason,
          allOf(
            contains("America/Havana"),
            contains("tool/test_calendar_in_havana.sh"),
          ),
        );
      }
    }
  });

  test("DST4 the last-hour tests' reasons name the Santiago script, and skip "
      "exactly where the zone's 25-hour day does not change the hour from "
      "23:00", () {
    expect(
      dstSkipReason("25-hour day", tuesday, 23, lastHour, run: santiagoRun),
      isNull,
    );
    expect(
      dstSkipReason("25-hour day", tuesday, 1, lastHour, run: santiagoRun),
      allOf(
        contains("from 1, not 23"),
        contains("America/Santiago"),
        contains("tool/test_calendar_in_santiago.sh"),
      ),
    );
    // In the zone the tests run in: the null branch in America/Santiago and
    // the other in America/New_York.
    final reason = repeatedLastHourSkip;
    expect(reason == null, longDay?.hour == lastHour, reason: "$longDay");
    if (reason != null) {
      expect(
        reason,
        allOf(
          contains("America/Santiago"),
          contains("tool/test_calendar_in_santiago.sh"),
        ),
      );
    }
  });

  test("DT19 on a day whose clock reads every time once, the end readings "
      "are the clock readings, and a day's start ends the day before", () {
    final day = CalendarDates.dayNumber(tuesday) * CalendarDates.minutesPerDay;
    for (var minute = 0; minute < CalendarDates.minutesPerDay; minute += 15) {
      final time = at(tuesday, minute ~/ 60, minute % 60);
      expect(
        CalendarDates.endWallMinuteOf(time),
        CalendarDates.wallMinuteOf(time),
        reason: "$minute",
      );
      expect(
        CalendarDates.endAtWallMinute(day + minute),
        CalendarDates.timeAtWallMinute(day + minute),
        reason: "$minute",
      );
    }
    expect(
      CalendarDates.endWallMinuteOf(wednesday),
      day + CalendarDates.minutesPerDay,
    );
    expect(
      CalendarDates.endAtWallMinute(day + CalendarDates.minutesPerDay),
      wednesday,
    );
  });

  test("DT22 on a day whose clock reads every time once, the hours read an "
      "end at 00:00 past a day start, or at a UTC midnight, at minute 0", () {
    final past = DateTime(2026, 4, 21, 0, 0, 30);
    for (final hours in <CalendarDayHours>[
      CalendarDayHours.allDay,
      CalendarDayHours(60, 1440),
    ]) {
      expect(
        hours.holdsTimes(DateTime(2026, 4, 20, 23), past, isAllDay: false),
        isFalse,
        reason: "$hours",
      );
    }
    expect(
      CalendarDayHours.allDay.holdsTimes(
        DateTime.utc(2026, 4, 20, 23),
        DateTime.utc(2026, 4, 21),
        isAllDay: false,
      ),
      isFalse,
    );
  });

  group(
    "on the day whose clock skips its midnight, the end readings",
    skip: skippedMidnightSkip,
    () {
      test("DT18 the last slot of the day before ends at the day's start", () {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        expect(firstReadableSlot(before, 1425, 1440, 15), (
          start: at(before, 23, 45),
          end: day,
        ));
      });

      test("DT20 the day's start ends at its minute 0, the 24:00 before, and "
          "minute 0 converts back to it, while a skipped minute after it "
          "names no time", () {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final wall = CalendarDates.dayNumber(day) * CalendarDates.minutesPerDay;
        expect(CalendarDates.endWallMinuteOf(day), wall);
        expect(CalendarDates.endAtWallMinute(wall), day);
        expect(CalendarDates.endAtWallMinute(wall, from: day), day);
        expect(CalendarDates.endAtWallMinute(wall + 30), isNull);
      });
    },
  );

  group(
    "on the day whose clock repeats its midnight, the end readings",
    skip: repeatedMidnightSkip,
    () {
      test("DT21 minute 0 ends at the earlier 00:00, or at the later one for "
          "a time in the later pass, and the later 00:00 ends at minute 0", () {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final wall = CalendarDates.dayNumber(day) * CalendarDates.minutesPerDay;
        expect(CalendarDates.endAtWallMinute(wall), day);
        expect(
          CalendarDates.endAtWallMinute(
            wall,
            from: laterMidnight.add(const Duration(minutes: 15)),
          ),
          laterMidnight,
        );
        expect(CalendarDates.endWallMinuteOf(laterMidnight), wall);
      });
    },
  );
}
