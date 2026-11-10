/// What the store layer's zone tests share beside `../zones.dart`: stores
/// built in a zone, their zone set and read, and a write's accepted entry.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_data_source.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/store/caching_calendar_store.dart';
import 'package:widgets_extended/scheduling/store/calendar_store.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

/// A memory store in [zone], or on the device's clock with none.
MemoryCalendarStore<T> memoryStoreIn<T>(
  tz.Location? zone, {
  Iterable<CalendarEntry<T>> entries = const <Never>[],
  CalendarDayHours? hours,
  CalendarEntryChanged<T>? onChanged,
}) {
  return MemoryCalendarStore<T>(
    entries: entries,
    hours: hours ?? CalendarDayHours.allDay,
    onChanged: onChanged,
    zone: zone,
  );
}

/// A caching store in [zone], or on the device's clock with none, over
/// [dataSource].
CachingCalendarStore<T> cachingStoreIn<T>(
  tz.Location? zone, {
  required CalendarDataSource<T> dataSource,
  Stream<CalendarSourceChange<T>>? changes,
  CalendarDayHours? hours,
}) {
  return CachingCalendarStore<T>(
    dataSource: dataSource,
    changes: changes,
    hours: hours ?? CalendarDayHours.allDay,
    zone: zone,
  );
}

/// Sets [store]'s zone.
void setStoreZone<T>(CalendarStore<T> store, tz.Location? zone) {
  store.zone = zone;
}

/// [store]'s zone, null for the device's clock.
tz.Location? zoneOfStore<T>(CalendarStore<T> store) {
  return store.zone;
}

/// A write's future that completes with the entry [id] names, of [title]
/// where one is given; a write the store refuses fails it.
Matcher acceptedAs(String id, {String? title}) {
  var entry = isA<CalendarEntry<String>>().having(
    (entry) {
      return entry.id;
    },
    "id",
    id,
  );
  if (title != null) {
    entry = entry.having(
      (entry) {
        return entry.title;
      },
      "title",
      title,
    );
  }
  return completion(entry);
}
