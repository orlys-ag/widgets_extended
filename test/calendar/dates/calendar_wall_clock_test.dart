/// The wall-clock coordinate of the dates layer: a time's wall minute and
/// back, the wall minutes nearest a time in an occurrence, the last day a
/// range has a part in, a range's piece on a day, the hours rule on starts,
/// ends and ranges, the hours on the grid of a slot length, and the skipped
/// and repeated times of the local zone's DST days.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';

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
    final day = dayNumber(tuesday) * minutesPerDay;
    expect(wallMinuteOf(tuesday), day);
    expect(timeAtWallMinute(day), tuesday);
    for (var minute = 0; minute < minutesPerDay; minute += 15) {
      final time = at(tuesday, minute ~/ 60, minute % 60);
      expect(wallMinuteOf(time), day + minute, reason: "$minute");
      expect(timeAtWallMinute(day + minute), time, reason: "$minute");
    }
    // A day's 24:00 is the next day's minute 0.
    expect(timeAtWallMinute(day + minutesPerDay), wednesday);
    expect(wallMinuteOf(wednesday), day + minutesPerDay);
  });

  test("DT9 firstWallMinuteNotBefore and lastWallMinuteNotAfter of a whole "
      "minute are its own wall minute, and of a time with seconds the next "
      "and its own", () {
    final nine = at(tuesday, 9);
    final wall = wallMinuteOf(nine);
    expect(firstWallMinuteNotBefore(nine), wall);
    expect(lastWallMinuteNotAfter(nine), wall);
    final past = nine.add(const Duration(seconds: 30));
    expect(firstWallMinuteNotBefore(past), wall + 1);
    expect(lastWallMinuteNotAfter(past), wall);
  });

  test("DT3 lastDayNumberOf is the day before an end at a day start, and "
      "the end's own day otherwise", () {
    expect(lastDayNumberOf(at(monday, 22), wednesday), dayNumber(tuesday));
    expect(
      lastDayNumberOf(at(monday, 22), at(wednesday, 0, 15)),
      dayNumber(wednesday),
    );
    expect(lastDayNumberOf(monday, tuesday), dayNumber(monday));
    expect(lastDayNumberOf(at(monday, 9), at(monday, 10)), dayNumber(monday));
  });

  test("DT4 pieceOn gives each day's part of a span in its minutes, and "
      "none on a day an end at its start leaves", () {
    final night = wallSpanOf(at(monday, 22), at(tuesday, 2));
    expect(pieceOn(night, dayNumber(monday)), (start: 1320, end: 1440));
    expect(pieceOn(night, dayNumber(tuesday)), (start: 0, end: 120));
    expect(pieceOn(night, dayNumber(wednesday)), isNull);
    expect(pieceOn(night, dayNumber(monday) - 1), isNull);

    final long = wallSpanOf(at(monday, 10), at(wednesday, 12));
    expect(pieceOn(long, dayNumber(monday)), (start: 600, end: 1440));
    expect(pieceOn(long, dayNumber(tuesday)), (start: 0, end: 1440));
    expect(pieceOn(long, dayNumber(wednesday)), (start: 0, end: 720));

    final toMidnight = wallSpanOf(at(monday, 22), tuesday);
    expect(pieceOn(toMidnight, dayNumber(monday)), (start: 1320, end: 1440));
    expect(pieceOn(toMidnight, dayNumber(tuesday)), isNull);
  });

  test("DT5 under 08:00-18:00 the hours hold a start from 08:00 to before "
      "18:00 and an end from after 08:00 to 18:00, a range whose start and "
      "last day's end they hold, and any all-day range", () {
    const office = CalendarDayHours(8 * 60, 18 * 60);
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
    expect(office.holdsTimes(at(monday, 17), at(tuesday, 9)), isTrue);
    expect(office.holdsTimes(at(monday, 17), at(monday, 19)), isFalse);
    expect(office.holdsTimes(at(monday, 7), at(monday, 9)), isFalse);
    expect(office.holdsTimes(at(monday, 9, 10), at(monday, 9, 50)), isTrue);
    // An end at a day start reads as minute 1440 of the day before.
    expect(office.holdsTimes(at(monday, 17), tuesday), isFalse);
    expect(CalendarDayHours.allDay.holdsTimes(at(monday, 17), tuesday), isTrue);
    expect(office.holdsTimes(monday, tuesday), isTrue);
    expect(office.holdsTimes(monday, addDays(monday, 3)), isTrue);
  });

  test("DT6 roundedOutTo(30) of 08:10-17:50 is 08:00-18:00, and "
      "isOnSlotsOf(30) holds of 08:00-18:00 and not of 08:10-17:50", () {
    const off = CalendarDayHours(8 * 60 + 10, 17 * 60 + 50);
    const office = CalendarDayHours(8 * 60, 18 * 60);
    expect(off.roundedOutTo(30), office);
    expect(office.roundedOutTo(30), office);
    expect(off.isOnSlotsOf(30), isFalse);
    expect(
      const CalendarDayHours(8 * 60, 17 * 60 + 50).isOnSlotsOf(30),
      isFalse,
    );
    expect(office.isOnSlotsOf(30), isTrue);
    expect(off.isOnSlotsOf(10), isTrue);
    // Rounded out, the end stays inside the day.
    expect(
      const CalendarDayHours(0, minutesPerDay - 5).roundedOutTo(60),
      CalendarDayHours.allDay,
    );
  });

  test("DT7 slotCountOf(30) of the whole day is 48", () {
    expect(CalendarDayHours.allDay.slotCountOf(30), 48);
    expect(CalendarDayHours.allDay.slotCountOf(defaultSlotMinutes), 96);
    expect(const CalendarDayHours(8 * 60, 18 * 60).slotCountOf(30), 20);
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
      expect(addDays(day, 1).difference(day), const Duration(hours: 23));
      expect(shortDay!.hour, 2);
      expect(DateTime(day.year, day.month, day.day, 2, 30).hour, isNot(2));
      expect(DateTime(day.year, day.month, day.day, 1, 30).hour, 1);
    });

    test("DT2 timeAtWallMinute of 02:30 is null, the clock skipping it", () {
      final day = dayNumber(shortDayStart) * minutesPerDay;
      expect(timeAtWallMinute(day + 2 * 60 + 30), isNull);
      expect(timeAtWallMinute(day + 2 * 60), isNull);
      expect(timeAtWallMinute(day + 3 * 60), isNotNull);
      expect(timeAtWallMinute(day + 60 + 30)!.hour, 1);
    });

    test("DT11 firstWallMinuteNotBefore of 01:59:30 is 03:00, past the "
        "minutes the clock skips", () {
      final day = dayNumber(shortDayStart) * minutesPerDay;
      final time = at(shortDayStart, 1, 59).add(const Duration(seconds: 30));
      expect(firstWallMinuteNotBefore(time), day + 3 * 60);
    });
  });

  group("on the 25-hour day", skip: longDaySkip, () {
    test("DST2 the 25-hour day lasts 25 hours and repeats 01:00", () {
      final day = longDayStart;
      expect(addDays(day, 1).difference(day), const Duration(hours: 25));
      expect(longDay!.hour, 1);
      // The day start plus two hours reads 01:00 again.
      expect(day.add(const Duration(hours: 1)).hour, 1);
      expect(day.add(const Duration(hours: 2)).hour, 1);
      expect(day.add(const Duration(hours: 3)).hour, 2);
    });

    test("DT8 timeAtWallMinute of 01:30 is the first 01:30, the second "
        "with from: in the day's later stretch, and isLaterOccurrence tells "
        "the two apart", () {
      final day = dayNumber(longDayStart) * minutesPerDay;
      final first = longDayStart.add(const Duration(minutes: 90));
      final second = secondHalfPastOne;
      // Both read 01:30, an hour apart.
      expect(first.hour, 1);
      expect(second.hour, 1);
      expect(second.difference(first), const Duration(hours: 1));

      expect(timeAtWallMinute(day + 90), first);
      final secondOne = longDayStart
          .add(const Duration(hours: 1))
          .add(const Duration(hours: 1));
      expect(secondOne.hour, 1);
      expect(timeAtWallMinute(day + 90, from: secondOne), second);
      final firstOne = longDayStart.add(const Duration(hours: 1));
      expect(timeAtWallMinute(day + 90, from: firstOne), first);
      expect(timeAtWallMinute(day + 90, from: at(monday, 1, 30)), first);
      // A later instant of another day is no occurrence of this one's.
      expect(
        timeAtWallMinute(
          day + 90,
          from: addDays(longDayStart, 1).add(const Duration(hours: 1)),
        ),
        first,
      );

      expect(isLaterOccurrence(second), isTrue);
      expect(isLaterOccurrence(first), isFalse);
      expect(isLaterOccurrence(at(monday, 1, 30)), isFalse);
    });

    test("DT10 firstWallMinuteNotBefore and lastWallMinuteNotAfter of a time "
        "in the repeated hour are its own wall minute in the occurrence from: "
        "picks, and in the other the edge of the repeated hour", () {
      final day = dayNumber(longDayStart) * minutesPerDay;
      final firstOne = longDayStart.add(const Duration(hours: 1));
      final secondOne = firstOne.add(const Duration(hours: 1));
      final firstQuarter = firstOne.add(const Duration(minutes: 15));
      final secondQuarter = secondOne.add(const Duration(minutes: 15));
      // The first 01:00 to 02:00, which timeAtWallMinute picks without from:.
      expect(firstWallMinuteNotBefore(firstQuarter), day + 75);
      expect(lastWallMinuteNotAfter(firstQuarter), day + 75);
      expect(firstWallMinuteNotBefore(secondQuarter), day + 120);
      expect(lastWallMinuteNotAfter(secondQuarter), day + 119);
      // The second, which from: at the second 01:00 picks.
      expect(
        firstWallMinuteNotBefore(secondQuarter, from: secondOne),
        day + 75,
      );
      expect(lastWallMinuteNotAfter(secondQuarter, from: secondOne), day + 75);
      expect(firstWallMinuteNotBefore(firstQuarter, from: secondOne), day + 60);
      expect(lastWallMinuteNotAfter(firstQuarter, from: secondOne), day + 59);
    });

    test("DT12 timeAtWallMinute's instants rise with the wall minute through "
        "the 25-hour day in either occurrence", () {
      final day = dayNumber(longDayStart) * minutesPerDay;
      final secondOne = longDayStart.add(const Duration(hours: 2));
      for (final from in <DateTime?>[null, secondOne]) {
        for (var wall = day; wall < day + minutesPerDay; wall++) {
          final time = timeAtWallMinute(wall, from: from)!;
          final next = timeAtWallMinute(wall + 1, from: from)!;
          expect(next.isAfter(time), isTrue, reason: "$wall from $from");
        }
      }
    });
  });
}
