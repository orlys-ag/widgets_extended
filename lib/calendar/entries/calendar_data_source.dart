/// The contract of the host's asynchronous reads and writes under the
/// caching store.
library;

import 'calendar_entry.dart';

/// The host's store of entries, which a `CachingCalendarStore` reads by days
/// and writes one entry at a time.
///
/// Each call completes with what the source stored, or fails with the
/// source's own error, which reaches the store's caller or its
/// write-failure callback unchanged.
abstract interface class CalendarDataSource<T> {
  /// Every entry with any part in the days from [first] to [last], both
  /// inclusive, each once, each with its id: an entry ending at the start
  /// of [first] has none there.
  Future<List<CalendarEntry<T>>> read(DateTime first, DateTime last);

  /// Stores [draft] and completes with the entry stored, under the id the
  /// source gives it.
  Future<CalendarEntry<T>> create(CalendarEntry<T> draft);

  /// Replaces the entry stored under `entry.id` with [entry] and completes
  /// with the entry stored, under the same id.
  Future<CalendarEntry<T>> replace(CalendarEntry<T> entry);

  /// Removes the entry stored under [id].
  Future<void> delete(String id);
}
