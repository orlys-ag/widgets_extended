/// The schedule a form edits: read from an entry's times, edited by day,
/// minute and length with its length kept as its start moves, turned
/// all-day and back, and made into times on a zone's clock.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_schedule.dart';

import '../zones.dart';

final DateTime wednesday = DateTime(2026, 4, 22);

DateTime at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
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
}
