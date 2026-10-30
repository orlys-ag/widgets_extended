/// The store that holds the entries the host gives it.
library;

import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';
import '../entries/calendar_entry.dart';
import 'calendar_store.dart';

/// Receives each change a [MemoryCalendarStore] applies: the [old] entry
/// and the new [entry], [old] null for a create and [entry] null for a
/// delete.
typedef CalendarEntryChanged<T> =
    void Function(CalendarEntry<T>? old, CalendarEntry<T>? entry);

/// A [CalendarStore] holding the entries the host gives it, always loaded.
///
/// It runs the check every store runs, the hours on a create, an update
/// and a move, and refuses no write for sharing time with another entry.
/// A write that passes is applied within the call, so no write is ever
/// pending: the store notifies its listeners once, then calls [onChanged]
/// with the old and the new entry. A throw from [onChanged] is reported
/// through [FlutterError.reportError], as [ChangeNotifier.notifyListeners]
/// reports a listener's, and fails no write: the write has applied its
/// change by then, and completes as it would without the throw. A
/// refused write fails to its caller, changing nothing and notifying
/// nothing. An update, move or delete of an id no entry has fails with an
/// [ArgumentError].
///
/// Every range is shown and every day read: [status] is ready, and [show],
/// [retry] and [prefetch] do nothing. The store is its entries' source,
/// changed through its writes and [entries], so [invalidate] and [refresh]
/// do nothing either.
class MemoryCalendarStore<T> extends CalendarStore<T> {
  /// A store holding [entries], each with an id no other has. Throws an
  /// [ArgumentError] for an entry with no id or with a repeated one.
  MemoryCalendarStore({
    Iterable<CalendarEntry<T>> entries = const <Never>[],
    this.onChanged,
    super.hours,
  }) {
    _fill(_checked(entries));
  }

  /// Receives each create, update, move and delete the store applies,
  /// after its listeners. A throw from it is reported through
  /// [FlutterError.reportError] and fails no write, which has applied its
  /// change by then.
  final CalendarEntryChanged<T>? onChanged;

  final CalendarEntryIndex<T> _index = CalendarEntryIndex<T>(
    opensEveryDay: true,
  );

  /// The number of the next `entry-<n>` id [create] gives a draft with
  /// none; it only counts up.
  int _nextId = 1;

  /// Every entry the store holds, in no set order; unmodifiable.
  List<CalendarEntry<T>> get entries {
    return List<CalendarEntry<T>>.unmodifiable(_index.storedEntries);
  }

  /// Replaces every entry with [value], whose entries each have an id no
  /// other has, and notifies once; calls no [onChanged]. Throws an
  /// [ArgumentError], changing nothing, for an entry with no id or with a
  /// repeated one.
  set entries(Iterable<CalendarEntry<T>> value) {
    final checked = _checked(value);
    _index.clear();
    _fill(checked);
    notifyListeners();
  }

  /// [entries] as a list, once each id is checked to be there and unique.
  List<CalendarEntry<T>> _checked(Iterable<CalendarEntry<T>> entries) {
    final list = List<CalendarEntry<T>>.of(entries);
    final ids = <String>{};
    for (final entry in list) {
      final id = entry.id;
      if (id == null) {
        throw ArgumentError.value(entry, "entries", "An entry has no id.");
      }
      if (!ids.add(id)) {
        throw ArgumentError.value(id, "entries", "Two entries share an id.");
      }
    }
    return list;
  }

  void _fill(List<CalendarEntry<T>> entries) {
    for (final entry in entries) {
      _index.addIfAbsent(entry);
    }
    _index.open();
  }

  /// Ready: every range is read.
  @override
  CalendarLoadStatus get status {
    return CalendarLoadStatus.ready;
  }

  /// Null: no read fails.
  @override
  Object? get loadError {
    return null;
  }

  /// Does nothing: every range shows.
  @override
  void show(DateTime first, DateTime last) {}

  /// Does nothing: no read fails. Throws an [ArgumentError] where one of
  /// [first] and [last] is given without the other, as
  /// [CalendarStore.retry] does.
  @override
  void retry([DateTime? first, DateTime? last]) {
    if ((first == null) != (last == null)) {
      throw ArgumentError("A retry takes both first and last, or neither.");
    }
  }

  /// Does nothing: every day is read.
  @override
  void prefetch(DateTime first, DateTime last) {}

  /// Does nothing: the store is its entries' source.
  @override
  void invalidate(DateTime first, DateTime last) {}

  /// Completes at once: the store is its entries' source.
  @override
  Future<void> refresh() {
    return Future<void>.value();
  }

  /// True: every day is read.
  @override
  bool isRead(DateTime day) {
    return true;
  }

  /// False: no read fails.
  @override
  bool readFailed(DateTime day) {
    return false;
  }

  /// True: every range shows.
  @override
  bool isShown(DateTime first, DateTime last) {
    return true;
  }

  /// True: every range shows.
  @override
  bool isWithinShown(DateTime first, DateTime last) {
    return true;
  }

  @override
  List<CalendarShownEntry<T>> entriesOn(DateTime day) {
    return _index.entriesOn(dayNumber(day));
  }

  @override
  List<CalendarShownEntry<T>> entriesBetween(DateTime first, DateTime last) {
    return _index.entriesBetween(dayNumber(first), dayNumber(last));
  }

  /// Whether an entry covers [day].
  @override
  bool dayHasShownEntries(DateTime day) {
    return _index.hasShownOn(dayNumber(day));
  }

  /// False: every write applies within its call.
  @override
  bool isPending(String id) {
    return false;
  }

  @override
  CalendarEntry<T>? storedEntry(String id) {
    return _index.stored(id);
  }

  /// Stores [draft] and completes with the stored entry: [draft] under its
  /// own id, or, when it has none, under the next `entry-<n>` no held
  /// entry has, counting from 1. Fails with a [CalendarHoursException] for
  /// a draft outside [hours], and with an [ArgumentError] for one whose
  /// own id a held entry has, changing nothing.
  @override
  Future<CalendarEntry<T>> create(CalendarEntry<T> draft) async {
    final refusal = hoursRefusalOf(draft);
    if (refusal != null) {
      throw refusal;
    }
    var id = draft.id;
    if (id != null && _index.stored(id) != null) {
      throw ArgumentError.value(id, "draft", "An entry has this id.");
    }
    while (id == null) {
      final next = "entry-$_nextId";
      _nextId++;
      if (_index.stored(next) == null) {
        id = next;
      }
    }
    final created = draft.id == id ? draft : draft.copyWith(id: id);
    _apply(null, created);
    return created;
  }

  /// Writes [entry] over the stored entry its id names and completes with
  /// it. Fails with an [ArgumentError] for an entry with no id or an id no
  /// entry has, and with a [CalendarHoursException] when [hoursRefusalOf]
  /// refuses it, changing nothing.
  @override
  Future<CalendarEntry<T>> update(CalendarEntry<T> entry) async {
    final old = _storedFor(entry.id, "entry");
    final refusal = hoursRefusalOf(entry);
    if (refusal != null) {
      throw refusal;
    }
    _apply(old, entry);
    return entry;
  }

  /// Moves or resizes the stored entry to [requested] and completes with
  /// it; a move onto another entry's time is applied. Fails with an
  /// [ArgumentError] for an entry with no id or an id no entry has, and
  /// with a [CalendarHoursException] when [hoursRefusalOf] refuses it,
  /// changing nothing.
  @override
  Future<CalendarEntry<T>> requestMove(CalendarEntry<T> requested) async {
    final id = requested.id;
    if (id == null) {
      throw ArgumentError.value(requested, "requested", "A move needs an id.");
    }
    final old = _index.stored(id);
    if (old == null) {
      throw ArgumentError.value(id, "id", "No entry.");
    }
    final refusal = hoursRefusalOf(requested);
    if (refusal != null) {
      throw refusal;
    }
    _apply(old, requested);
    return requested;
  }

  /// Deletes the entry [id], and completes. Fails with an [ArgumentError],
  /// changing nothing, when no entry has it.
  @override
  Future<void> requestDelete(String id) async {
    final old = _index.stored(id);
    if (old == null) {
      throw ArgumentError.value(id, "id", "No entry.");
    }
    _index.forget(id);
    notifyListeners();
    _reportChange(old, null);
  }

  /// The stored entry [id] names; throws an [ArgumentError], named [name],
  /// for a null id or one no entry has.
  CalendarEntry<T> _storedFor(String? id, String name) {
    if (id == null) {
      throw ArgumentError.value(id, name, "An update needs an id.");
    }
    final stored = _index.stored(id);
    if (stored == null) {
      throw ArgumentError.value(id, name, "No entry.");
    }
    return stored;
  }

  /// Stores [entry] in place of [old], notifies, then reports the change.
  void _apply(CalendarEntry<T>? old, CalendarEntry<T> entry) {
    _index.put(entry);
    notifyListeners();
    _reportChange(old, entry);
  }

  /// Calls [onChanged] with [old] and [entry], once the change is applied
  /// and the listeners notified. A throw from it is reported through
  /// [FlutterError.reportError], as [ChangeNotifier.notifyListeners]
  /// reports a listener's, rather than fail a write that applied its
  /// change.
  void _reportChange(CalendarEntry<T>? old, CalendarEntry<T>? entry) {
    final onChanged = this.onChanged;
    if (onChanged == null) {
      return;
    }
    try {
      onChanged(old, entry);
    } on Object catch (exception, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: "widgets_extended calendar",
          context: ErrorDescription(
            "while calling the onChanged of a MemoryCalendarStore",
          ),
        ),
      );
    }
  }
}
