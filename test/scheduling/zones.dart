/// What the zone tests of every layer share: the zone data, a
/// [CountingLocation], zones chosen against the device's clock, and the
/// wall-minute helpers on a zone's clock.
library;

import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';

var _zonesLoaded = false;

/// Loads the zone database once.
void ensureZones() {
  if (!_zonesLoaded) {
    tz_data.initializeTimeZones();
    _zonesLoaded = true;
  }
}

/// A [tz.Location] that counts [lookups] of its offsets, through which
/// `TZDateTime.from` and `Location.timeZone` route.
class CountingLocation extends tz.Location {
  CountingLocation(tz.Location source)
    : super(
        source.name,
        source.transitionAt,
        source.transitionZone,
        source.zones,
      );

  int lookups = 0;

  @override
  tz.TzInstant lookupTimeZone(int millisecondsSinceEpoch) {
    lookups++;
    return super.lookupTimeZone(millisecondsSinceEpoch);
  }
}

/// The `Etc/GMT` zone of [offset] whole hours east of UTC.
tz.Location _gmtZone(int offset) {
  if (offset == 0) {
    return tz.getLocation("Etc/GMT");
  }
  // The names' signs are POSIX's: Etc/GMT-3 lies three hours east.
  return tz.getLocation(offset > 0 ? "Etc/GMT-$offset" : "Etc/GMT+${-offset}");
}

/// An `Etc/GMT` zone 12 or more hours from the device's offset at [on],
/// reading another civil day than the device does at [on].
tz.Location zoneFarFromDevice(DateTime on) {
  final device = on.timeZoneOffset.inHours;
  final deviceDay = CalendarDates.dayNumber(on);
  for (var offset = 14; offset >= -12; offset--) {
    if ((offset - device).abs() < 12) {
      continue;
    }
    final zone = _gmtZone(offset);
    if (CalendarDates.dayNumber(tz.TZDateTime.from(on, zone)) != deviceDay) {
      return zone;
    }
  }
  throw StateError("No Etc/GMT zone is 12 hours from the device at $on");
}

/// A zone of the data whose offset is the device's on the days around
/// [on].
tz.Location zoneAtDeviceOffset(DateTime on) {
  final offset = on.timeZoneOffset;
  for (final zone in tz.timeZoneDatabase.locations.values) {
    if (<int>[-3, -1, 0, 1, 3].every((days) {
      return tz.TZDateTime.from(
            on.add(Duration(days: days)),
            zone,
          ).timeZoneOffset ==
          offset;
    })) {
      return zone;
    }
  }
  throw StateError("No zone keeps the device's offset around $on");
}

/// A zone built as package timezone builds its UTC, named for [hours], whose
/// one offset is the device's at [on] plus [hours].
tz.Location zoneApartFromDevice(DateTime on, int hours) {
  final name = "Test/Apart$hours";
  return tz.Location(name, <int>[tz.minTime], <int>[0], <tz.TimeZone>[
    tz.TimeZone(
      on.timeZoneOffset + Duration(hours: hours),
      isDst: false,
      abbreviation: name,
    ),
  ]);
}

/// The first instant [zone]'s clock reads the day numbered [day].
DateTime dayOfNumberIn(int day, tz.Location zone) {
  return CalendarDates.dateOfDayNumber(day, zone: zone);
}

/// [CalendarDates.timeAtWallMinute] on [zone]'s clock.
DateTime? timeAtWallIn(int wall, tz.Location zone, {DateTime? from}) {
  return CalendarDates.timeAtWallMinute(wall, from: from, zone: zone);
}

/// [CalendarDates.endAtWallMinute] on [zone]'s clock.
DateTime? endAtWallIn(int wall, tz.Location zone, {DateTime? from}) {
  return CalendarDates.endAtWallMinute(wall, from: from, zone: zone);
}
