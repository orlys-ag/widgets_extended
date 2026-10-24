/// The local time zone's days of 2026 whose clock skips or repeats an hour,
/// which the DST tests read, and the reason a DST group skips in a zone
/// whose changes are not the ones the tests name.
library;

import 'package:widgets_extended/calendar/dates/calendar_dates.dart';

/// A day of 2026 and the wall hour its clock skips or repeats.
typedef DstDay = ({DateTime day, int hour});

/// The hour the tests' fixtures name as skipped, Eastern's 02:00.
const int easternSkippedHour = 2;

/// The hour the tests' fixtures name as repeated, Eastern's 01:00.
const int easternRepeatedHour = 1;

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
/// a reason naming what the zone has and the zone the tests are written
/// for.
String? dstSkipReason(
  String what,
  DateTime? day,
  int? hour,
  int expectedHour,
) {
  if (day == null) {
    return "No $what in this time zone; run with TZ=America/New_York";
  }
  if (hour != expectedHour) {
    return "The $what of this time zone, ${isoDate(day)}, changes the hour "
        "from $hour, not $expectedHour; run with TZ=America/New_York";
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

/// The start of [shortDay]; only read inside a group [shortDaySkip] runs.
DateTime get shortDayStart {
  return shortDay!.day;
}

/// The start of [longDay]; only read inside a group [longDaySkip] runs.
DateTime get longDayStart {
  return longDay!.day;
}

/// The second 01:30 of [longDay], built from the unambiguous day start.
DateTime get secondHalfPastOne {
  return longDayStart
      .add(const Duration(minutes: 90))
      .add(const Duration(hours: 1));
}
