/// The local time zone's days of 2026 whose clock skips or repeats its
/// midnight, which the demo's midnight tests read, the reason their groups
/// skip in a zone whose changes are at another hour, and the checks each
/// test makes of its day first. The same scan, reasons and checks as the
/// package's `test/calendar/dst_days.dart`, whose midnight tests these
/// mirror.
library;

import 'package:flutter_test/flutter_test.dart';

/// The first day of 2026 that lasts 23 hours here, with the first hour `h`
/// whose `DateTime(y, m, d, h, 30)` reads another hour; null where the zone
/// has none.
final ({DateTime day, int hour})? shortDay = _firstDayOf(23);

/// The first day of 2026 that lasts 25 hours here, with the first hour `h`
/// that the day's start plus `h + 1` hours reads; null where the zone has
/// none.
final ({DateTime day, int hour})? longDay = _firstDayOf(25);

({DateTime day, int hour})? _firstDayOf(int hours) {
  // Days are built from their fields here rather than stepped with
  // `CalendarDates.addDays`: an `addDays` that lasts 24 hours would
  // otherwise find no DST day and skip the tests that would catch it.
  for (var index = 0; DateTime(2026, 1, 1 + index).year == 2026; index++) {
    final day = DateTime(2026, 1, 1 + index);
    if (DateTime(2026, 1, 2 + index).difference(day).inHours != hours) {
      continue;
    }
    for (var hour = 0; hour < 24; hour++) {
      final changed = hours == 23
          ? DateTime(day.year, day.month, day.day, hour, 30).hour != hour
          : day.add(Duration(hours: hour + 1)).hour == hour;
      if (changed) {
        return (day: day, hour: hour);
      }
    }
    return (day: day, hour: -1);
  }
  return null;
}

/// How to run the midnight tests, whose days are Havana's.
const String havanaRun =
    "from demos/workspace_calendar, run bash "
    "../../tool/test_calendar_in_havana.sh with this file's path, which "
    "runs it in America/Havana";

/// Why the tests of the day whose clock skips its midnight skip: null where
/// [shortDay] skips the hour from 00:00.
String? get skippedMidnightSkip {
  if (shortDay?.hour == 0) {
    return null;
  }
  return "No 23-hour day whose clock skips its midnight in this time zone; "
      "$havanaRun";
}

/// Why the tests of the day whose clock repeats its midnight skip: null
/// where [longDay] repeats the hour from 00:00.
String? get repeatedMidnightSkip {
  if (longDay?.hour == 0) {
    return null;
  }
  return "No 25-hour day whose clock repeats its midnight in this time "
      "zone; $havanaRun";
}

/// Checks that [day] starts a civil day of 23 hours whose clock skips its
/// midnight, so it reads 01:00.
void expectSkippedMidnight(DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  expect(
    DateTime(day.year, day.month, day.day + 1).difference(start),
    const Duration(hours: 23),
    reason: "$day's day lasts 23 hours",
  );
  expect(day.hour, 1, reason: "$day reads 01:00");
}

/// Checks that [day] starts a civil day of 25 hours whose clock repeats its
/// midnight, so it reads 00:00 and so does the instant an hour after it.
void expectRepeatedMidnight(DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  expect(
    DateTime(day.year, day.month, day.day + 1).difference(start),
    const Duration(hours: 25),
    reason: "$day's day lasts 25 hours",
  );
  expect(day.hour, 0, reason: "$day reads 00:00");
  expect(
    day.add(const Duration(hours: 1)).hour,
    0,
    reason: "$day plus an hour reads 00:00",
  );
}
