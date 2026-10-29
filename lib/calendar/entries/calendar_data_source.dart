/// The contract of the host's asynchronous reads and writes under the
/// caching store, and of the changes a source announces to it.
library;

import 'calendar_entry.dart';

/// The host's store of entries, which a `CachingCalendarStore` reads by days
/// and writes one entry at a time.
///
/// Each call completes with what the source stored, or fails with the
/// source's own error, which reaches unchanged the caller of the store's
/// write, or for a read the store's `loadError`.
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

/// A change at a data source, which a `CachingCalendarStore` given a stream
/// of them applies to the entries it holds.
///
/// A stream of changes delivers them in the order the source made them, and
/// sends a [CalendarAllChanged] after any stretch in which it may have
/// missed one, such as a lost connection.
sealed class CalendarSourceChange<T> {
  const CalendarSourceChange();
}

/// The source stores [entry] under its id, created or replaced.
final class CalendarEntryPut<T> extends CalendarSourceChange<T> {
  /// The change storing [entry]. Throws an [ArgumentError] for an entry
  /// with no id.
  CalendarEntryPut(this.entry) {
    if (entry.id == null) {
      throw ArgumentError.value(entry, "entry", "A stored entry has an id.");
    }
  }

  /// The entry as the source stores it.
  final CalendarEntry<T> entry;
}

/// The source no longer stores an entry under [id].
final class CalendarEntryRemoved<T> extends CalendarSourceChange<T> {
  /// The change removing the entry [id].
  const CalendarEntryRemoved(this.id);

  /// The removed entry's id.
  final String id;
}

/// Any entry with a part in the days from [first] to [last], both
/// inclusive, may have changed.
final class CalendarDaysChanged<T> extends CalendarSourceChange<T> {
  /// The change of the days from [first] to [last].
  const CalendarDaysChanged(this.first, this.last);

  /// The first changed day.
  final DateTime first;

  /// The last changed day.
  final DateTime last;
}

/// Any entry may have changed.
final class CalendarAllChanged<T> extends CalendarSourceChange<T> {
  /// The change of every entry.
  const CalendarAllChanged();
}
