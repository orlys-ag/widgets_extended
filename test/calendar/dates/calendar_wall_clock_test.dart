/// The wall-clock coordinate of the dates layer: a time's wall minute and
/// back, the last day a range has a part in, a range's piece on a day, the
/// hours rule on starts, ends and ranges, and the skipped and repeated
/// times of the local zone's DST days.
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
    const office = DayHours(8 * 60, 18 * 60);
    expect(office.holdsStart(8 * 60), isTrue);
    expect(office.holdsStart(9 * 60 + 10), isTrue);
    expect(office.holdsStart(18 * 60 - 1), isTrue);
    expect(office.holdsStart(18 * 60), isFalse);
    expect(office.holdsStart(8 * 60 - 1), isFalse);
    expect(office.holdsEnd(8 * 60), isFalse);
    expect(office.holdsEnd(8 * 60 + 1), isTrue);
    expect(office.holdsEnd(18 * 60), isTrue);
    expect(office.holdsEnd(18 * 60 + 1), isFalse);

    // AC13's shapes: an overnight entry starting and ending inside the
    // hours, and one ending after them on its own day.
    expect(office.holdsTimes(at(monday, 17), at(tuesday, 9)), isTrue);
    expect(office.holdsTimes(at(monday, 17), at(monday, 19)), isFalse);
    expect(office.holdsTimes(at(monday, 7), at(monday, 9)), isFalse);
    expect(office.holdsTimes(at(monday, 9, 10), at(monday, 9, 50)), isTrue);
    // An end at a day start reads as minute 1440 of the day before.
    expect(office.holdsTimes(at(monday, 17), tuesday), isFalse);
    expect(DayHours.allDay.holdsTimes(at(monday, 17), tuesday), isTrue);
    expect(office.holdsTimes(monday, tuesday), isTrue);
    expect(office.holdsTimes(monday, addDays(monday, 3)), isTrue);
  });

  group("on the 23-hour day", skip: shortDaySkip, () {
    test("DT2 timeAtWallMinute of 02:30 is null, the clock skipping it", () {
      final day = dayNumber(shortDayStart) * minutesPerDay;
      expect(timeAtWallMinute(day + 2 * 60 + 30), isNull);
      expect(timeAtWallMinute(day + 2 * 60), isNull);
      expect(timeAtWallMinute(day + 3 * 60), isNotNull);
      expect(timeAtWallMinute(day + 60 + 30)!.hour, 1);
    });
  });

  group("on the 25-hour day", skip: longDaySkip, () {
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
  });
}
