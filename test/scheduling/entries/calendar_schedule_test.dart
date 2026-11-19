/// The schedule a form edits: read from an entry's times, the pass of a
/// repeated stretch each edge lies in included, edited by day, minute and
/// length, a new start time keeping its elapsed length and a new start day
/// both wall times, turned all-day and back, and made into times on a
/// zone's clock.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_schedule.dart';

import '../dst_days.dart';
import '../zones.dart';

final DateTime wednesday = DateTime(2026, 4, 22);

DateTime at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

/// America/New_York, whose clock reads 01:00 to 02:00 twice on 2026-11-01,
/// going back at 06:00Z, and skips 02:00 to 03:00 on 2027-03-14.
tz.Location get newYork {
  ensureZones();
  return tz.getLocation("America/New_York");
}

/// America/Havana, whose clock reads 00:00 to 01:00 twice on 2026-11-01,
/// going back at 05:00Z.
tz.Location get havana {
  ensureZones();
  return tz.getLocation("America/Havana");
}

/// America/Santiago, whose clock reads 23:00 to 24:00 twice on 2026-04-04,
/// going back at 2026-04-05T03:00Z.
tz.Location get santiago {
  ensureZones();
  return tz.getLocation("America/Santiago");
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

/// [times] as plain UTC times, which compare by instant; null where it is
/// null.
(DateTime, DateTime)? utcTimes(({DateTime start, DateTime end})? times) {
  if (times == null) {
    return null;
  }
  return (utcOf(times.start), utcOf(times.end));
}

/// Expects [times] to be exactly the instants [start] and [end].
void expectTimes(
  ({DateTime start, DateTime end})? times,
  DateTime start,
  DateTime end, {
  String? reason,
}) {
  expect(times, isNotNull, reason: reason);
  expect(
    (utcOf(times!.start), utcOf(times.end)),
    (utcOf(start), utcOf(end)),
    reason: reason,
  );
}

/// Why the tests of the device's day whose clock repeats an hour skip:
/// where the zone has no 25-hour day, and where the dates layer reads no
/// stretch its clock repeats on it ([CalendarDates.repeatedStretchOf]), as
/// on a clock whose offset falls by the day's end but not by the next
/// day's start; null otherwise.
String? get repeatedHourSkip {
  final day = longDay?.day;
  if (day == null) {
    return "No 25-hour day in this time zone; $havanaRun";
  }
  if (CalendarDates.repeatedStretchOf(day) == Duration.zero) {
    return "The 25-hour day of this time zone, ${CalendarDates.isoDate(day)}, "
        "repeats no stretch by the next day's start; $havanaRun";
  }
  return null;
}

/// The instants every quarter hour from [from] for [hours] hours on
/// [zone]'s clock, both ends included.
List<tz.TZDateTime> quarterHoursFrom(
  DateTime from,
  int hours,
  tz.Location zone,
) {
  return <tz.TZDateTime>[
    for (var quarter = 0; quarter <= hours * 4; quarter++)
      tz.TZDateTime.from(from.add(Duration(minutes: 15 * quarter)), zone),
  ];
}

void main() {
  test("CS1 of reads a timed, an all-day and a midnight-ending range back "
      "to the same times", () {
    final timed = CalendarSchedule.of(
      at(wednesday, 9),
      at(wednesday, 10, 30),
      isAllDay: false,
    );
    expect(timed.startDay, wednesday);
    expect(timed.startMinute, 540);
    expect(timed.endDay, wednesday);
    expect(timed.endMinute, 630);
    expect(timed.lengthMinutes, 90);
    expect(timed.spansDays, isFalse);
    expect(timed.timesOn(null), (
      start: at(wednesday, 9),
      end: at(wednesday, 10, 30),
    ));

    final thursday = DateTime(2026, 4, 23);
    final toMidnight = CalendarSchedule.of(
      at(wednesday, 22),
      thursday,
      isAllDay: false,
    );
    expect(toMidnight.endDay, wednesday);
    expect(toMidnight.endMinute, 1440);
    expect(toMidnight.spansDays, isFalse);
    expect(toMidnight.timesOn(null), (start: at(wednesday, 22), end: thursday));

    final allDay = CalendarSchedule.of(
      wednesday,
      DateTime(2026, 4, 25),
      isAllDay: true,
    );
    expect(allDay.isAllDay, isTrue);
    expect(allDay.endDay, DateTime(2026, 4, 24));
    expect(allDay.lengthMinutes, 3 * 1440);
    expect(allDay.spansDays, isTrue);
    expect(allDay.timesOn(null), (
      start: wednesday,
      end: DateTime(2026, 4, 25),
    ));

    expect(
      () => CalendarSchedule.of(
        at(wednesday, 9),
        at(wednesday, 9),
        isAllDay: false,
      ),
      throwsArgumentError,
    );
  });

  test("CS2 timesOn is null for a time the clock skips, and gives the "
      "earlier pass of a time it repeats", () {
    ensureZones();
    final havana = tz.getLocation("America/Havana");
    // Havana's clock skips 00:00 to 01:00 on 2026-03-08 and repeats it on
    // 2026-11-01.
    final skipped = CalendarSchedule.of(
      DateTime(2026, 3, 7, 9),
      DateTime(2026, 3, 7, 10),
      isAllDay: false,
    ).withStartDay(DateTime(2026, 3, 8)).withStartMinute(30);
    expect(skipped.startSkippedOn(havana), isTrue);
    expect(skipped.endSkippedOn(havana), isFalse);
    expect(skipped.timesOn(havana), isNull);

    final repeated = CalendarSchedule.of(
      tz.TZDateTime(havana, 2026, 11, 1, 9),
      tz.TZDateTime(havana, 2026, 11, 1, 10),
      isAllDay: false,
    ).withStartMinute(30);
    final times = repeated.timesOn(havana)!;
    final earlier = tz.TZDateTime(havana, 2026, 11, 1, 0, 30);
    expect(times.start, earlier);
    expect(times.start.timeZoneOffset, const Duration(hours: -4));
    // The hour's elapsed length ends at the later 00:30.
    expect(times.end.difference(times.start), const Duration(hours: 1));
  });

  test("CS3 a new start minute keeps the length and a new start day both "
      "wall times, across a skipped hour too", () {
    ensureZones();
    final havana = tz.getLocation("America/Havana");
    final morning = CalendarSchedule.of(
      DateTime(2026, 3, 8, 9),
      DateTime(2026, 3, 8, 10),
      isAllDay: false,
    );
    final early = morning.withStartMinute(0);
    expect(early.startMinute, 0);
    expect(early.endMinute, 60);
    expect(early.lengthMinutes, 60);
    // The wall hour 00:00 to 01:00 does not exist on that day.
    expect(early.timesOn(havana), isNull);
    final late = morning.withStartMinute(23 * 60 + 30);
    expect(late.endDay, DateTime(2026, 3, 9));
    expect(late.endMinute, 30);
    expect(late.lengthMinutes, 60);

    final moved = morning.withStartDay(DateTime(2026, 3, 10));
    expect(moved.startDay, DateTime(2026, 3, 10));
    expect(moved.endDay, DateTime(2026, 3, 10));
    expect(moved.lengthMinutes, 60);
    expect(() => moved.withStartMinute(1440), throwsArgumentError);
  });

  test("CS4 a length sets the end, on a later day past the start day's "
      "24:00; an end set alone may leave it not after the start", () {
    final nine = CalendarSchedule.of(
      at(wednesday, 9),
      at(wednesday, 10),
      isAllDay: false,
    );
    expect(nine.withLength(30).endMinute, 570);
    final long = nine.withLength(16 * 60);
    expect(long.endDay, DateTime(2026, 4, 23));
    expect(long.endMinute, 60);
    expect(nine.withLength(15 * 60).endMinute, 1440);
    expect(nine.withLength(15 * 60).endDay, wednesday);
    expect(() => nine.withLength(0), throwsArgumentError);

    final backwards = nine.withEndMinute(8 * 60);
    expect(backwards.lengthMinutes, -60);
    expect(nine.withEndDay(DateTime(2026, 4, 24)).spansDays, isTrue);
  });

  test("CS5 all-day keeps the timed minutes, which off restores; the "
      "timed edits refuse an all-day schedule", () {
    final nine = CalendarSchedule.of(
      at(wednesday, 9),
      at(wednesday, 10),
      isAllDay: false,
    );
    final allDay = nine.withAllDay(true);
    expect(allDay.isAllDay, isTrue);
    expect(allDay.lengthMinutes, 1440);
    expect(allDay.timesOn(null), (
      start: wednesday,
      end: DateTime(2026, 4, 23),
    ));
    expect(() => allDay.withStartMinute(600), throwsStateError);
    expect(() => allDay.withEndMinute(600), throwsStateError);
    expect(() => allDay.withLength(60), throwsStateError);
    final back = allDay.withAllDay(false);
    expect(back, nine);
    expect(nine.withAllDay(false), same(nine));

    final fromAllDay = CalendarSchedule.of(
      wednesday,
      DateTime(2026, 4, 23),
      isAllDay: true,
    ).withAllDay(false);
    expect(fromAllDay.startMinute, 0);
    expect(fromAllDay.endMinute, 1440);
  });

  test("CS6 equality and hash by value, the kept timed minutes included", () {
    CalendarSchedule nine() {
      return CalendarSchedule.of(
        at(wednesday, 9),
        at(wednesday, 10),
        isAllDay: false,
      );
    }

    expect(nine(), nine());
    expect(nine().hashCode, nine().hashCode);
    expect(nine(), isNot(nine().withStartMinute(600)));
    final keptNine = nine().withAllDay(true);
    final keptTen = nine().withStartMinute(600).withAllDay(true);
    expect(keptNine, isNot(keptTen));
    expect(keptNine.withStartDay(wednesday), keptNine);
    expect(CalendarDates.isoDate(keptNine.startDay), "2026-04-22");
  });

  group("the passes of a repeated stretch", () {
    test("CS7 of keeps a later start's pass, so timesOn gives back 01:30 "
        "EST to 03:00 EST", () {
      final start = inNewYork(DateTime.utc(2026, 11, 1, 6, 30));
      final end = inNewYork(DateTime.utc(2026, 11, 1, 8));
      // Setup sanity: 05:30Z and 06:30Z both read 01:30, at -4h and -5h.
      final first = inNewYork(DateTime.utc(2026, 11, 1, 5, 30));
      expect(
        (first.hour, first.minute, first.timeZoneOffset),
        (1, 30, const Duration(hours: -4)),
      );
      expect(
        (start.hour, start.minute, start.timeZoneOffset),
        (1, 30, const Duration(hours: -5)),
      );
      expectTimes(
        CalendarSchedule.of(start, end, isAllDay: false).timesOn(newYork),
        start,
        end,
      );
    });

    test("CS8 01:15 EDT to 01:10 EST lasts 55 minutes, ends at minute 70 "
        "and gives back its instants", () {
      final start = inNewYork(DateTime.utc(2026, 11, 1, 5, 15));
      final end = inNewYork(DateTime.utc(2026, 11, 1, 6, 10));
      final schedule = CalendarSchedule.of(start, end, isAllDay: false);
      expect(
        (
          schedule.lengthMinutes,
          schedule.endMinute,
          utcTimes(schedule.timesOn(newYork)),
        ),
        (55, 70, (utcOf(start), utcOf(end))),
      );
    });

    test("CS9 an end at Havana's later 00:00, where the clock goes back, "
        "reads the stretch's end, 01:00", () {
      final start = tz.TZDateTime.from(DateTime.utc(2026, 11, 1, 3), havana);
      final end = tz.TZDateTime.from(DateTime.utc(2026, 11, 1, 5), havana);
      // Setup sanity: the end reads 00:00 and is not its day's start.
      expect((end.day, end.hour, end.minute), (1, 0, 0));
      expect(CalendarDates.isDayStart(end), isFalse);
      final schedule = CalendarSchedule.of(start, end, isAllDay: false);
      expect(
        (
          schedule.endDay,
          schedule.endMinute,
          schedule.lengthMinutes,
          utcTimes(schedule.timesOn(havana)),
        ),
        (DateTime(2026, 11, 1), 60, 120, (utcOf(start), utcOf(end))),
      );
    });

    test("CS10 an end at the stretch's end from a first-pass start ends "
        "with the first pass, 30 minutes on", () {
      final moved = CalendarSchedule.of(
        inNewYork(DateTime.utc(2026, 11, 1, 5, 30)),
        inNewYork(DateTime.utc(2026, 11, 1, 5, 45)),
        isAllDay: false,
      ).withEndMinute(120);
      expect(
        (moved.lengthMinutes, utcTimes(moved.timesOn(newYork))),
        (30, (DateTime.utc(2026, 11, 1, 5, 30), DateTime.utc(2026, 11, 1, 6))),
      );

      // The end of 01:30 to 02:00 on a day whose clock repeats nothing
      // holds no pass.
      final noPass = CalendarSchedule.of(
        tz.TZDateTime(newYork, 2026, 10, 31, 1, 30),
        tz.TZDateTime(newYork, 2026, 10, 31, 2),
        isAllDay: false,
      ).withStartDay(DateTime(2026, 11, 1));
      expect(
        (noPass.lengthMinutes, utcTimes(noPass.timesOn(newYork))),
        (30, (DateTime.utc(2026, 11, 1, 5, 30), DateTime.utc(2026, 11, 1, 6))),
      );
    });

    test("CS11 a new start minute keeps the start's later pass", () {
      final moved = CalendarSchedule.of(
        inNewYork(DateTime.utc(2026, 11, 1, 6, 30)),
        inNewYork(DateTime.utc(2026, 11, 1, 8)),
        isAllDay: false,
      ).withStartMinute(105);
      expect(utcTimes(moved.timesOn(newYork)), (
        DateTime.utc(2026, 11, 1, 6, 45),
        DateTime.utc(2026, 11, 1, 8, 15),
      ));
    });

    test("CS12 a length before 1970 ends on the day it runs to", () {
      final schedule = CalendarSchedule.of(
        DateTime(1969, 12, 31, 10),
        DateTime(1969, 12, 31, 11),
        isAllDay: false,
      ).withLength(60);
      expect(schedule.endDay, DateTime(1969, 12, 31));
      expect(schedule.endMinute, 660);
      expect(schedule.spansDays, isFalse);
    });

    test("CS13 two timed schedules of the same days and minutes compare "
        "equal however they were reached", () {
      final made = CalendarSchedule.of(
        DateTime(2026, 4, 21, 10),
        DateTime(2026, 4, 21, 11),
        isAllDay: false,
      );
      final moved = CalendarSchedule.of(
        DateTime(2026, 4, 21, 9),
        DateTime(2026, 4, 21, 10),
        isAllDay: false,
      ).withStartMinute(600);
      expect(made == moved, isTrue);
      expect(made.hashCode, moved.hashCode);
    });

    test("CS14 every quarter-hour range around a clock going back gives "
        "back its instants and its elapsed length", () {
      for (final (zone, from) in <(tz.Location, DateTime)>[
        (newYork, DateTime.utc(2026, 11, 1, 3)),
        (havana, DateTime.utc(2026, 11, 1, 2)),
        (santiago, DateTime.utc(2026, 4, 5)),
      ]) {
        final instants = quarterHoursFrom(from, 6, zone);
        // Setup sanity: the window holds two instants of one wall minute.
        expect(
          instants.map(CalendarDates.wallMinuteOf).toSet().length,
          lessThan(instants.length),
          reason: zone.name,
        );
        for (var i = 0; i < instants.length; i++) {
          for (var j = i + 1; j < instants.length; j++) {
            final start = instants[i];
            final end = instants[j];
            final reason = "${zone.name}: ${utcOf(start)} to ${utcOf(end)}";
            final schedule = CalendarSchedule.of(start, end, isAllDay: false);
            expectTimes(schedule.timesOn(zone), start, end, reason: reason);
            expect(
              schedule.lengthMinutes,
              end.difference(start).inMinutes,
              reason: reason,
            );
            expect(
              schedule.endMinute,
              inInclusiveRange(1, CalendarDates.minutesPerDay),
              reason: reason,
            );
            expect(
              schedule.withStartMinute(schedule.startMinute),
              schedule,
              reason: reason,
            );
          }
        }
      }
    });

    test("CS15 a new start minute or length keeps the elapsed length "
        "across the clock going back", () {
      final instants = quarterHoursFrom(
        DateTime.utc(2026, 11, 1, 3),
        6,
        newYork,
      );
      // Each edit that does not keep its length, with what it gave.
      final unkept = <String>[];
      for (var i = 0; i < instants.length; i++) {
        for (var j = i + 1; j < instants.length; j++) {
          final schedule = CalendarSchedule.of(
            instants[i],
            instants[j],
            isAllDay: false,
          );
          final length = schedule.lengthMinutes;
          void check(String edit, CalendarSchedule edited, int expected) {
            final times = edited.timesOn(newYork);
            final elapsed = times?.end.difference(times.start).inMinutes;
            if (edited.lengthMinutes != expected ||
                (elapsed != null && elapsed != expected)) {
              unkept.add(
                "$schedule.$edit: lengthMinutes ${edited.lengthMinutes}, "
                "times $elapsed minutes apart, not $expected",
              );
            }
          }

          for (var minute = 0; minute <= 300; minute += 15) {
            check(
              "withStartMinute($minute)",
              schedule.withStartMinute(minute),
              length,
            );
          }
          for (final minutes in const <int>[15, 30, 45, 60, 90]) {
            final sized = schedule.withLength(minutes);
            check("withLength($minutes)", sized, minutes);
            if (sized.timesOn(newYork) == null) {
              unkept.add("$schedule.withLength($minutes): no times");
            }
          }
        }
      }

      // 01:58 EDT to 01:03 EST, 5 minutes, moved to 01:50, ends at 01:55
      // EDT.
      final moved = CalendarSchedule.of(
        inNewYork(DateTime.utc(2026, 11, 1, 5, 58)),
        inNewYork(DateTime.utc(2026, 11, 1, 6, 3)),
        isAllDay: false,
      ).withStartMinute(110);
      // An end in the later pass moved to 02:15 keeps that pass.
      final endMoved = CalendarSchedule.of(
        inNewYork(DateTime.utc(2026, 11, 1, 5, 15)),
        inNewYork(DateTime.utc(2026, 11, 1, 6, 45)),
        isAllDay: false,
      ).withEndMinute(135);
      final saved = CalendarSchedule.of(
        inNewYork(DateTime.utc(2026, 11, 1, 5, 15)),
        inNewYork(DateTime.utc(2026, 11, 1, 7, 15)),
        isAllDay: false,
      );
      // A far end moves by the elapsed length, which the clock change
      // between leaves an hour off the wall times.
      final far = CalendarSchedule.of(
        inNewYork(DateTime.utc(2026, 11, 1, 6, 30)),
        inNewYork(DateTime.utc(2027, 1, 15, 6, 30)),
        isAllDay: false,
      ).withStartMinute(30);
      expect(
        (
          unkept.take(3).join("; "),
          utcTimes(moved.timesOn(newYork)),
          utcTimes(endMoved.timesOn(newYork)),
          endMoved.lengthMinutes,
          saved.lengthMinutes,
          utcTimes(far.timesOn(newYork)),
        ),
        (
          "",
          (DateTime.utc(2026, 11, 1, 5, 50), DateTime.utc(2026, 11, 1, 5, 55)),
          (DateTime.utc(2026, 11, 1, 5, 15), DateTime.utc(2026, 11, 1, 7, 15)),
          120,
          120,
          (DateTime.utc(2026, 11, 1, 4, 30), DateTime.utc(2027, 1, 15, 4, 30)),
        ),
      );
    });

    group(
      "on the device's day whose clock repeats an hour",
      skip: repeatedHourSkip,
      () {
        test("CS16 every quarter-hour range of plain local times around the "
            "repeated hour gives back its instants and its elapsed "
            "length", () {
          final repeated = longDayStart.add(Duration(hours: longDay!.hour));
          final instants = <DateTime>[
            for (var minutes = -120; minutes <= 180; minutes += 15)
              repeated.add(Duration(minutes: minutes)),
          ];
          for (var i = 0; i < instants.length; i++) {
            for (var j = i + 1; j < instants.length; j++) {
              final start = instants[i];
              final end = instants[j];
              final reason = "${utcOf(start)} to ${utcOf(end)}";
              final schedule = CalendarSchedule.of(start, end, isAllDay: false);
              expectTimes(schedule.timesOn(null), start, end, reason: reason);
              expect(
                schedule.lengthMinutes,
                end.difference(start).inMinutes,
                reason: reason,
              );
            }
          }
        });
      },
    );

    test("CS18 an end its clock reads once takes a later start's pass, and "
        "beside a first-pass start none", () {
      final later = CalendarSchedule.of(
        inNewYork(DateTime.utc(2026, 11, 1, 6, 30)),
        inNewYork(DateTime.utc(2026, 11, 1, 8)),
        isAllDay: false,
      ).withEndMinute(105);
      expect(
        (utcTimes(later.timesOn(newYork)), later.lengthMinutes),
        (
          (DateTime.utc(2026, 11, 1, 6, 30), DateTime.utc(2026, 11, 1, 6, 45)),
          15,
        ),
      );

      final first = CalendarSchedule.of(
        inNewYork(DateTime.utc(2026, 11, 1, 4, 30)),
        inNewYork(DateTime.utc(2026, 11, 1, 5)),
        isAllDay: false,
      ).withEndMinute(120);
      expect(
        (utcOf(first.timesOn(newYork)!.end), first.lengthMinutes),
        (DateTime.utc(2026, 11, 1, 7), 150),
      );

      // A later start moved onto a time the clock skips lends the end it
      // places its later pass, whatever pass the end held: here the first,
      // of 01:30 EDT on 2027-11-07.
      final firstEnd = CalendarSchedule.of(
        inNewYork(DateTime.utc(2026, 11, 1, 6, 30)),
        inNewYork(DateTime.utc(2027, 11, 7, 5, 30)),
        isAllDay: false,
      );
      // Setup sanity: the end gives back its first-pass instant.
      expect(
        utcOf(firstEnd.timesOn(newYork)!.end),
        DateTime.utc(2027, 11, 7, 5, 30),
      );
      final skipped = firstEnd
          .withStartDay(DateTime(2027, 3, 14))
          .withStartMinute(150);
      // Setup sanity: the clock skips 02:30 of 2027-03-14.
      expect(skipped.startSkippedOn(newYork), isTrue);
      // Moved so the end lies on 2028-11-05, whose clock reads 01:30
      // twice, the end reads in the later pass.
      expect(
        utcOf(
          skipped.withStartDay(DateTime(2027, 10, 31)).timesOn(newYork)!.end,
        ),
        DateTime.utc(2028, 11, 5, 6, 30),
      );
    });

    test("CS17 each member reads the clock as often for a schedule two years "
        "long as for one a year long", () {
      final zone = CountingLocation(newYork);
      int count(void Function() call) {
        zone.lookups = 0;
        call();
        return zone.lookups;
      }

      tz.TZDateTime of(DateTime utc) {
        return tz.TZDateTime.from(utc, zone);
      }

      // The later 01:30 of 2026-11-01, 2027-11-07 and 2028-11-05.
      final start = of(DateTime.utc(2026, 11, 1, 6, 30));
      List<int> countsTo(DateTime end) {
        late CalendarSchedule schedule;
        return <int>[
          count(() {
            schedule = CalendarSchedule.of(start, end, isAllDay: false);
          }),
          count(() {
            schedule.timesOn(zone);
          }),
          count(() {
            schedule.lengthMinutes;
          }),
          count(() {
            schedule.withStartMinute(105);
          }),
          count(() {
            schedule.withLength(60);
          }),
          count(() {
            schedule.withStartDay(DateTime(2026, 11, 2));
          }),
          count(() {
            schedule.withEndMinute(105);
          }),
          count(() {
            schedule.startSkippedOn(zone);
          }),
          count(() {
            schedule.endSkippedOn(zone);
          }),
        ];
      }

      final yearLong = countsTo(of(DateTime.utc(2027, 11, 7, 6, 30)));
      // Setup sanity: the members read the counting zone.
      expect(yearLong.reduce((a, b) => a + b), greaterThan(0));
      expect(countsTo(of(DateTime.utc(2028, 11, 5, 6, 30))), yearLong);
    });

    test("CS19 00:30 EDT to 03:00 EST lasts 210 minutes", () {
      expect(
        CalendarSchedule.of(
          inNewYork(DateTime.utc(2026, 11, 1, 4, 30)),
          inNewYork(DateTime.utc(2026, 11, 1, 8)),
          isAllDay: false,
        ).lengthMinutes,
        210,
      );
    });

    test("CS20 01:00 EST to 04:00 EDT lasts 120 minutes", () {
      expect(
        CalendarSchedule.of(
          inNewYork(DateTime.utc(2027, 3, 14, 6)),
          inNewYork(DateTime.utc(2027, 3, 14, 8)),
          isAllDay: false,
        ).lengthMinutes,
        120,
      );
    });

    test("CS21 a new start minute keeps the elapsed length, ending in the "
        "later pass", () {
      final moved = CalendarSchedule.of(
        inNewYork(DateTime.utc(2026, 11, 1, 4, 30)),
        inNewYork(DateTime.utc(2026, 11, 1, 5, 30)),
        isAllDay: false,
      ).withStartMinute(90);
      expect(
        (moved.lengthMinutes, utcTimes(moved.timesOn(newYork))),
        (
          60,
          (DateTime.utc(2026, 11, 1, 5, 30), DateTime.utc(2026, 11, 1, 6, 30)),
        ),
      );
    });

    test("CS22 a new start minute keeps the elapsed length, ending after a "
        "skipped hour", () {
      final moved = CalendarSchedule.of(
        inNewYork(DateTime.utc(2027, 3, 14, 5, 30)),
        inNewYork(DateTime.utc(2027, 3, 14, 6, 30)),
        isAllDay: false,
      ).withStartMinute(90);
      expect(
        (moved.lengthMinutes, utcTimes(moved.timesOn(newYork))),
        (
          60,
          (DateTime.utc(2027, 3, 14, 6, 30), DateTime.utc(2027, 3, 14, 7, 30)),
        ),
      );
    });

    test("CS23 a new start day keeps both wall times, the passes having no "
        "effect on a day whose clock repeats nothing", () {
      expectTimes(
        CalendarSchedule.of(
          inNewYork(DateTime.utc(2026, 11, 1, 6, 30)),
          inNewYork(DateTime.utc(2026, 11, 1, 8)),
          isAllDay: false,
        ).withStartDay(DateTime(2027, 3, 14)).timesOn(newYork),
        DateTime.utc(2027, 3, 14, 6, 30),
        DateTime.utc(2027, 3, 14, 7),
      );
      final days = CalendarSchedule.of(
        inNewYork(DateTime.utc(2026, 11, 1, 6, 30)),
        inNewYork(DateTime.utc(2026, 11, 4, 6, 30)),
        isAllDay: false,
      ).withStartDay(DateTime(2027, 3, 13));
      expect(
        (utcTimes(days.timesOn(newYork)), days.lengthMinutes),
        (
          (DateTime.utc(2027, 3, 13, 6, 30), DateTime.utc(2027, 3, 16, 5, 30)),
          4260,
        ),
      );
    });

    test("CS24 a plain UTC schedule is measured on UTC's clock and holds no "
        "pass, and an end at a UTC midnight reads as minute 0 of its "
        "day", () {
      final plain = CalendarSchedule.of(
        DateTime.utc(2026, 11, 1, 1, 30),
        DateTime.utc(2026, 11, 1, 3),
        isAllDay: false,
      );
      // The same instants on package timezone's UTC, whose pass reads by
      // its own clock.
      final zoned = CalendarSchedule.of(
        tz.TZDateTime(tz.UTC, 2026, 11, 1, 1, 30),
        tz.TZDateTime(tz.UTC, 2026, 11, 1, 3),
        isAllDay: false,
      );
      expect((plain.lengthMinutes, plain), (90, zoned));
      final toMidnight = CalendarSchedule.of(
        DateTime.utc(2026, 4, 22, 22),
        DateTime.utc(2026, 4, 23),
        isAllDay: false,
      );
      expect(
        (toMidnight.endDay, toMidnight.endMinute),
        (DateTime(2026, 4, 23), 0),
      );
    });

    test("CS25 a new start minute the clock skips keeps the length in wall "
        "minutes, and moving it back gives the schedule back", () {
      final schedule = CalendarSchedule.of(
        inNewYork(DateTime.utc(2027, 3, 14, 6)),
        inNewYork(DateTime.utc(2027, 3, 14, 8)),
        isAllDay: false,
      );
      final skipped = schedule.withStartMinute(150);
      // Setup sanity: the clock skips 02:30.
      expect(skipped.startSkippedOn(newYork), isTrue);
      final back = skipped.withStartMinute(60);
      expect(
        (
          skipped.endMinute,
          skipped.lengthMinutes,
          back,
          utcTimes(back.timesOn(newYork)),
        ),
        (
          270,
          120,
          schedule,
          (DateTime.utc(2027, 3, 14, 6), DateTime.utc(2027, 3, 14, 8)),
        ),
      );
    });

    test("CS26 an end at the first instant of a repeated stretch's start "
        "beside a later start gives that instant back, and a length "
        "ending there keeps it", () {
      final start = inNewYork(DateTime.utc(2026, 11, 1, 6, 30));
      // New York's clock goes back from 02:00 to 01:00 at 2027-11-07T06:00Z,
      // so 05:00Z is the first 01:00, and the minute before is read once.
      final end = inNewYork(DateTime.utc(2027, 11, 7, 5));
      final schedule = CalendarSchedule.of(start, end, isAllDay: false);
      final length = end.difference(start).inMinutes;
      expectTimes(schedule.timesOn(newYork), start, end);
      expect(schedule.lengthMinutes, length);
      // The end holds the first pass: moved to 02:00, it ends as that pass
      // does, at the instant the clock goes back.
      expect(
        utcOf(schedule.withEndMinute(120).timesOn(newYork)!.end),
        DateTime.utc(2027, 11, 7, 6),
      );

      // Havana's clock goes back from 01:00 to 00:00 at 2027-11-07T05:00Z,
      // so 04:00Z is the day's first 00:00.
      final havanaStart = tz.TZDateTime.from(
        DateTime.utc(2026, 11, 1, 5, 30),
        havana,
      );
      final havanaEnd = tz.TZDateTime.from(
        DateTime.utc(2027, 11, 7, 4),
        havana,
      );
      expectTimes(
        CalendarSchedule.of(
          havanaStart,
          havanaEnd,
          isAllDay: false,
        ).timesOn(havana),
        havanaStart,
        havanaEnd,
      );

      final sized = CalendarSchedule.of(
        start,
        inNewYork(DateTime.utc(2026, 11, 1, 8)),
        isAllDay: false,
      ).withLength(length);
      expect(sized.lengthMinutes, length);
      expectTimes(sized.timesOn(newYork), start, end);
    });
  });
}
