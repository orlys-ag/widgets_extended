/// The contract of the host's asynchronous reads and writes under the
/// caching store, and of the changes a source announces to it.
library;

import 'calendar_entry.dart';

/// The host's store of entries, which a `CachingCalendarStore` reads by days
/// and writes one entry at a time.
///
/// A data source reads and writes on the device's clock: [read] is asked for
/// device days, and every [CalendarEntry] it takes or answers holds plain
/// local times, the local midnights of its dates where it is all-day,
/// whatever zone the store above it reads in.
///
/// Each call completes with what the source stored, or fails with the
/// source's own error. A write's error reaches the caller of the store's
/// write unchanged. A read's error reaches the store's `loadError`
/// unchanged where its failure marks a day of the shown range
/// `readFailed`, a day the store had not read or had taken to have
/// changed, and while that mark is the latest standing there: a failure on
/// a day marked already leaves the mark's error, and one off the shown
/// range reaches no `loadError`. The error of the read a `refresh` waits
/// on fails the refresh too.
abstract interface class CalendarDataSource<T> {
  /// Every entry with any part in the device days from [first] to [last],
  /// both inclusive, each once, each with its id, in plain local times: an
  /// entry ending at the start of [first] has none there.
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
/// of them applies to the entries it holds. Its days and times are on the
/// device's clock, as the source's are.
///
/// A stream of changes delivers them in the order the source made them, and
/// sends a [CalendarAllChanged] after any stretch in which it may have
/// missed one, such as a lost connection. Its end tells that the source
/// announces nothing more: a `CachingCalendarStore` keeps the stream it is
/// built with for its life, and once the stream ends hears of no change,
/// so a source whose changes go on keeps the stream open across a lost
/// connection rather than end it.
///
/// A host may announce a kind of change of its own, a subclass it declares
/// `final` or `base`, which a `CachingCalendarStore` takes as a
/// [CalendarAllChanged]. The module adds kinds as it learns them, so a
/// `switch` over a source change keeps a default case.
abstract base class CalendarSourceChange<T> {
  /// Const, so a subclass can be const.
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

/// Any entry with a part in the device days from [first] to [last], both
/// inclusive, may have changed.
final class CalendarDaysChanged<T> extends CalendarSourceChange<T> {
  /// The change of the days from [first] to [last].
  ///
  /// Throws an [ArgumentError], in every build, naming `last` for a [last]
  /// whose day comes before [first]'s. The days compare by their year,
  /// month and day, so a [last] earlier on [first]'s day is taken.
  CalendarDaysChanged(this.first, this.last) {
    final before = last.year != first.year
        ? last.year < first.year
        : last.month != first.month
        ? last.month < first.month
        : last.day < first.day;
    if (before) {
      throw ArgumentError.value(
        last,
        "last",
        "A change of days ends on its first day or a later one, $first",
      );
    }
  }

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
