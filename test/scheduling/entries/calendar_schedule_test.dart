/// The schedule a form edits: read from an entry's times, edited by day,
/// minute and length with its length kept as its start moves, turned
/// all-day and back, and made into times on a zone's clock.
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
      DateTime(2026, 11, 1, 9),
      DateTime(2026, 11, 1, 10),
      isAllDay: false,
    ).withStartMinute(30);
    final times = repeated.timesOn(havana)!;
    final earlier = tz.TZDateTime(havana, 2026, 11, 1, 0, 30);
    expect(times.start, earlier);
    expect(times.start.timeZoneOffset, const Duration(hours: -4));
    expect(times.end.difference(times.start), const Duration(hours: 2));
  });

  test("CS3 a new start minute or day keeps the wall length, across a "
      "skipped hour too", () {
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
    test(
      "CS7 of keeps a later start's pass, so timesOn gives back 01:30 "
      "EST to 03:00 EST",
      skip: true,
      () {
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
      },
    );

    test(
      "CS8 01:15 EDT to 01:10 EST lasts 55 minutes, ends at minute 70 "
      "and gives back its instants",
      skip: true,
      () {
        final start = inNewYork(DateTime.utc(2026, 11, 1, 5, 15));
        final end = inNewYork(DateTime.utc(2026, 11, 1, 6, 10));
        final schedule = CalendarSchedule.of(start, end, isAllDay: false);
        expect(schedule.lengthMinutes, 55);
        expect(schedule.endMinute, 70);
        expectTimes(schedule.timesOn(newYork), start, end);
      },
    );

    test(
      "CS9 an end at Havana's later 00:00, where the clock goes back, "
      "reads the stretch's end, 01:00",
      skip: true,
      () {
        final start = tz.TZDateTime.from(DateTime.utc(2026, 11, 1, 3), havana);
        final end = tz.TZDateTime.from(DateTime.utc(2026, 11, 1, 5), havana);
        // Setup sanity: the end reads 00:00 and is not its day's start.
        expect((end.day, end.hour, end.minute), (1, 0, 0));
        expect(CalendarDates.isDayStart(end), isFalse);
        final schedule = CalendarSchedule.of(start, end, isAllDay: false);
        expect(schedule.endDay, DateTime(2026, 11, 1));
        expect(schedule.endMinute, 60);
        expect(schedule.lengthMinutes, 120);
        expectTimes(schedule.timesOn(havana), start, end);
      },
    );

    test(
      "CS10 an end at the stretch's end from a first-pass start ends "
      "with the first pass, 30 minutes on",
      skip: true,
      () {
        final moved = CalendarSchedule.of(
          inNewYork(DateTime.utc(2026, 11, 1, 5, 30)),
          inNewYork(DateTime.utc(2026, 11, 1, 5, 45)),
          isAllDay: false,
        ).withEndMinute(120);
        expect(moved.lengthMinutes, 30);
        expectTimes(
          moved.timesOn(newYork),
          DateTime.utc(2026, 11, 1, 5, 30),
          DateTime.utc(2026, 11, 1, 6),
        );

        // The end of 01:30 to 02:00 on a day whose clock repeats nothing
        // holds no pass.
        final noPass = CalendarSchedule.of(
          tz.TZDateTime(newYork, 2026, 10, 31, 1, 30),
          tz.TZDateTime(newYork, 2026, 10, 31, 2),
          isAllDay: false,
        ).withStartDay(DateTime(2026, 11, 1));
        expectTimes(
          noPass.timesOn(newYork),
          DateTime.utc(2026, 11, 1, 5, 30),
          DateTime.utc(2026, 11, 1, 6),
        );
        expect(noPass.lengthMinutes, 30);
      },
    );

    test(
      "CS11 a new start minute keeps the start's later pass",
      skip: true,
      () {
        final moved = CalendarSchedule.of(
          inNewYork(DateTime.utc(2026, 11, 1, 6, 30)),
          inNewYork(DateTime.utc(2026, 11, 1, 8)),
          isAllDay: false,
        ).withStartMinute(105);
        final times = moved.timesOn(newYork)!;
        expect(utcOf(times.start), DateTime.utc(2026, 11, 1, 6, 45));
        expect(utcOf(times.end), DateTime.utc(2026, 11, 1, 8, 15));
      },
    );

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

    test(
      "CS14 every quarter-hour range around a clock going back gives "
      "back its instants and its elapsed length",
      skip: true,
      () {
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
      },
    );

    test(
      "CS15 a new start minute or length keeps the elapsed length "
      "across the clock going back",
      skip: true,
      () {
        final instants = quarterHoursFrom(
          DateTime.utc(2026, 11, 1, 3),
          6,
          newYork,
        );
        for (var i = 0; i < instants.length; i++) {
          for (var j = i + 1; j < instants.length; j++) {
            final schedule = CalendarSchedule.of(
              instants[i],
              instants[j],
              isAllDay: false,
            );
            final length = schedule.lengthMinutes;
            for (var minute = 0; minute <= 300; minute += 15) {
              final moved = schedule.withStartMinute(minute);
              final reason = "$schedule.withStartMinute($minute)";
              expect(moved.lengthMinutes, length, reason: reason);
              final times = moved.timesOn(newYork);
              if (times != null) {
                expect(
                  times.end.difference(times.start).inMinutes,
                  length,
                  reason: reason,
                );
              }
            }
            for (final minutes in const <int>[15, 30, 45, 60, 90]) {
              final sized = schedule.withLength(minutes);
              final reason = "$schedule.withLength($minutes)";
              expect(sized.lengthMinutes, minutes, reason: reason);
              final times = sized.timesOn(newYork)!;
              expect(
                times.end.difference(times.start).inMinutes,
                minutes,
                reason: reason,
              );
            }
          }
        }

        // 01:58 EDT to 01:03 EST, 5 minutes, moved to 01:50 ends at 01:55
        // EDT.
        expectTimes(
          CalendarSchedule.of(
            inNewYork(DateTime.utc(2026, 11, 1, 5, 58)),
            inNewYork(DateTime.utc(2026, 11, 1, 6, 3)),
            isAllDay: false,
          ).withStartMinute(110).timesOn(newYork),
          DateTime.utc(2026, 11, 1, 5, 50),
          DateTime.utc(2026, 11, 1, 5, 55),
        );

        // An end in the later pass moved to 02:15 keeps that pass.
        final endMoved = CalendarSchedule.of(
          inNewYork(DateTime.utc(2026, 11, 1, 5, 15)),
          inNewYork(DateTime.utc(2026, 11, 1, 6, 45)),
          isAllDay: false,
        ).withEndMinute(135);
        expectTimes(
          endMoved.timesOn(newYork),
          DateTime.utc(2026, 11, 1, 5, 15),
          DateTime.utc(2026, 11, 1, 7, 15),
        );
        expect(endMoved.lengthMinutes, 120);
        expect(
          CalendarSchedule.of(
            inNewYork(DateTime.utc(2026, 11, 1, 5, 15)),
            inNewYork(DateTime.utc(2026, 11, 1, 7, 15)),
            isAllDay: false,
          ).lengthMinutes,
          120,
        );

        // A far end moves by the elapsed length, which the clock change
        // between leaves an hour off the wall times.
        expectTimes(
          CalendarSchedule.of(
            inNewYork(DateTime.utc(2026, 11, 1, 6, 30)),
            inNewYork(DateTime.utc(2027, 1, 15, 6, 30)),
            isAllDay: false,
          ).withStartMinute(30).timesOn(newYork),
          DateTime.utc(2026, 11, 1, 4, 30),
          DateTime.utc(2027, 1, 15, 4, 30),
        );
      },
    );

    group(
      "on the device's day whose clock repeats an hour",
      skip: longDay == null
          ? "No 25-hour day in this time zone; $havanaRun"
          : null,
      () {
        test(
          "CS16 every quarter-hour range of plain local times around the "
          "repeated hour gives back its instants and its elapsed "
          "length",
          skip: true,
          () {
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
                final schedule = CalendarSchedule.of(
                  start,
                  end,
                  isAllDay: false,
                );
                expectTimes(schedule.timesOn(null), start, end, reason: reason);
                expect(
                  schedule.lengthMinutes,
                  end.difference(start).inMinutes,
                  reason: reason,
                );
              }
            }
          },
        );
      },
    );

    test(
      "CS18 an end its clock reads once takes a later start's pass, and "
      "beside a first-pass start none",
      skip: true,
      () {
        final later = CalendarSchedule.of(
          inNewYork(DateTime.utc(2026, 11, 1, 6, 30)),
          inNewYork(DateTime.utc(2026, 11, 1, 8)),
          isAllDay: false,
        ).withEndMinute(105);
        expectTimes(
          later.timesOn(newYork),
          DateTime.utc(2026, 11, 1, 6, 30),
          DateTime.utc(2026, 11, 1, 6, 45),
        );
        expect(later.lengthMinutes, 15);

        final first = CalendarSchedule.of(
          inNewYork(DateTime.utc(2026, 11, 1, 4, 30)),
          inNewYork(DateTime.utc(2026, 11, 1, 5)),
          isAllDay: false,
        ).withEndMinute(120);
        expect(
          utcOf(first.timesOn(newYork)!.end),
          DateTime.utc(2026, 11, 1, 7),
        );
        expect(first.lengthMinutes, 150);
      },
    );

    test("CS19 00:30 EDT to 03:00 EST lasts 210 minutes", skip: true, () {
      expect(
        CalendarSchedule.of(
          inNewYork(DateTime.utc(2026, 11, 1, 4, 30)),
          inNewYork(DateTime.utc(2026, 11, 1, 8)),
          isAllDay: false,
        ).lengthMinutes,
        210,
      );
    });

    test("CS20 01:00 EST to 04:00 EDT lasts 120 minutes", skip: true, () {
      expect(
        CalendarSchedule.of(
          inNewYork(DateTime.utc(2027, 3, 14, 6)),
          inNewYork(DateTime.utc(2027, 3, 14, 8)),
          isAllDay: false,
        ).lengthMinutes,
        120,
      );
    });

    test(
      "CS21 a new start minute keeps the elapsed length, ending in the "
      "later pass",
      skip: true,
      () {
        final moved = CalendarSchedule.of(
          inNewYork(DateTime.utc(2026, 11, 1, 4, 30)),
          inNewYork(DateTime.utc(2026, 11, 1, 5, 30)),
          isAllDay: false,
        ).withStartMinute(90);
        expect(moved.lengthMinutes, 60);
        expectTimes(
          moved.timesOn(newYork),
          DateTime.utc(2026, 11, 1, 5, 30),
          DateTime.utc(2026, 11, 1, 6, 30),
        );
      },
    );

    test(
      "CS22 a new start minute keeps the elapsed length, ending after a "
      "skipped hour",
      skip: true,
      () {
        final moved = CalendarSchedule.of(
          inNewYork(DateTime.utc(2027, 3, 14, 5, 30)),
          inNewYork(DateTime.utc(2027, 3, 14, 6, 30)),
          isAllDay: false,
        ).withStartMinute(90);
        expect(moved.lengthMinutes, 60);
        expectTimes(
          moved.timesOn(newYork),
          DateTime.utc(2027, 3, 14, 6, 30),
          DateTime.utc(2027, 3, 14, 7, 30),
        );
      },
    );

    test(
      "CS23 a new start day keeps both wall times, the passes having no "
      "effect on a day whose clock repeats nothing",
      skip: true,
      () {
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
        expectTimes(
          days.timesOn(newYork),
          DateTime.utc(2027, 3, 13, 6, 30),
          DateTime.utc(2027, 3, 16, 5, 30),
        );
        expect(days.lengthMinutes, 4260);
      },
    );

    test(
      "CS25 a new start minute the clock skips keeps the length in wall "
      "minutes, and moving it back gives the schedule back",
      skip: true,
      () {
        final schedule = CalendarSchedule.of(
          inNewYork(DateTime.utc(2027, 3, 14, 6)),
          inNewYork(DateTime.utc(2027, 3, 14, 8)),
          isAllDay: false,
        );
        final skipped = schedule.withStartMinute(150);
        // Setup sanity: the clock skips 02:30.
        expect(skipped.startSkippedOn(newYork), isTrue);
        expect(skipped.endMinute, 270);
        expect(skipped.lengthMinutes, 120);
        final back = skipped.withStartMinute(60);
        expect(back, schedule);
        expectTimes(
          back.timesOn(newYork),
          DateTime.utc(2027, 3, 14, 6),
          DateTime.utc(2027, 3, 14, 8),
        );
      },
    );
  });
}
