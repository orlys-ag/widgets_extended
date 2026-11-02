/// The local time zone's days of 2026 whose clock skips or repeats an hour,
/// which the DST tests read, and the reason a DST group skips in a zone
/// whose changes are not the ones the tests name: New York's, at 02:00 and
/// 01:00, or for the midnight tests Havana's, which skip and repeat the
/// hour from 00:00 ([skippedMidnightSkip], [repeatedMidnightSkip]), with
/// the checks each midnight test makes of its day first
/// ([expectSkippedMidnight], [expectRepeatedMidnight]) and the later 00:00
/// of the repeated midnight ([laterMidnight]); and a local time whose UTC
/// date is another day, which the tests of a UTC time read, with the reason
/// they skip in a zone that has none.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';

/// A day of 2026 and the wall hour its clock skips or repeats.
typedef DstDay = ({DateTime day, int hour});

/// The hour the tests' fixtures name as skipped, Eastern's 02:00.
const int easternSkippedHour = 2;

/// The hour the tests' fixtures name as repeated, Eastern's 01:00.
const int easternRepeatedHour = 1;

/// The hour the midnight tests name as skipped and as repeated, 00:00.
const int midnightHour = 0;

/// How to run the DST tests whose fixtures name Eastern's changes.
const String newYorkRun = "run with TZ=America/New_York";

/// How to run the midnight tests, whose days are Havana's.
const String havanaRun =
    "run bash tool/test_calendar_in_havana.sh, which runs them in "
    "America/Havana";

/// The first day of 2026 that lasts 23 hours here, with the first hour `h`
/// whose `DateTime(y, m, d, h, 30)` reads another hour; null where the zone
/// has none.
final DstDay? shortDay = _firstDayOf(23);

/// The first day of 2026 that lasts 25 hours here, with the first hour `h`
/// that the day's start plus `h + 1` hours reads; null where the zone has
/// none.
final DstDay? longDay = _firstDayOf(25);

DstDay? _firstDayOf(int hours) {
  // Days are built from their fields here rather than stepped with
  // [addDays], the step under test: an [addDays] that lasts 24 hours would
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

/// Why a group of DST tests of [what], such as "23-hour day", skips: null
/// where [day] was found with [hour] equal to [expectedHour], and otherwise
/// a reason naming what the zone has and ending with [run], how to run the
/// tests in the zone they are written for.
String? dstSkipReason(
  String what,
  DateTime? day,
  int? hour,
  int expectedHour, {
  String run = newYorkRun,
}) {
  if (day == null) {
    return "No $what in this time zone; $run";
  }
  if (hour != expectedHour) {
    return "The $what of this time zone, ${isoDate(day)}, changes the hour "
        "from $hour, not $expectedHour; $run";
  }
  return null;
}

/// [dstSkipReason] for the 23-hour day [shortDay].
String? get shortDaySkip {
  return dstSkipReason(
    "23-hour day",
    shortDay?.day,
    shortDay?.hour,
    easternSkippedHour,
  );
}

/// [dstSkipReason] for the 25-hour day [longDay].
String? get longDaySkip {
  return dstSkipReason(
    "25-hour day",
    longDay?.day,
    longDay?.hour,
    easternRepeatedHour,
  );
}

/// [dstSkipReason] for the 23-hour day [shortDay] of the midnight tests,
/// whose clock skips the hour from its midnight.
String? get skippedMidnightSkip {
  return dstSkipReason(
    "23-hour day",
    shortDay?.day,
    shortDay?.hour,
    midnightHour,
    run: havanaRun,
  );
}

/// [dstSkipReason] for the 25-hour day [longDay] of the midnight tests,
/// whose clock repeats the hour from its midnight.
String? get repeatedMidnightSkip {
  return dstSkipReason(
    "25-hour day",
    longDay?.day,
    longDay?.hour,
    midnightHour,
    run: havanaRun,
  );
}

/// The start of [shortDay]; only read inside a group [shortDaySkip] or
/// [skippedMidnightSkip] runs.
DateTime get shortDayStart {
  return shortDay!.day;
}

/// The start of [longDay]; only read inside a group [longDaySkip] or
/// [repeatedMidnightSkip] runs.
DateTime get longDayStart {
  return longDay!.day;
}

/// The later 00:00 of [longDay], whose clock repeats its midnight: its
/// start plus one hour. Only read inside a group [repeatedMidnightSkip]
/// runs.
DateTime get laterMidnight {
  return longDayStart.add(const Duration(hours: 1));
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

/// The second 01:30 of [longDay], built from the unambiguous day start.
DateTime get secondHalfPastOne {
  return longDayStart
      .add(const Duration(minutes: 90))
      .add(const Duration(hours: 1));
}

/// A local time on April 21 2026 whose UTC date is another day: 23:30 where
/// its UTC date is April 22, in a zone west of UTC, else 00:15 where its
/// UTC date is April 20, in a zone east of UTC; null where neither is.
final DateTime? offUtcTime = _offUtcTime();

DateTime? _offUtcTime() {
  final beforeMidnight = DateTime(2026, 4, 21, 23, 30);
  if (beforeMidnight.toUtc().day == 22) {
    return beforeMidnight;
  }
  final afterMidnight = DateTime(2026, 4, 21, 0, 15);
  if (afterMidnight.toUtc().day == 20) {
    return afterMidnight;
  }
  return null;
}

/// Why a test of a UTC time skips: null where [offUtcTime] is found.
String? get offUtcSkip {
  if (offUtcTime != null) {
    return null;
  }
  return "This time zone reads UTC's date on 2026-04-21; run with "
      "TZ=America/New_York";
}
