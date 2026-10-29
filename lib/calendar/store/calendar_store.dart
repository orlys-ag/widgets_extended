/// What every calendar store answers and writes, the refusals its writes
/// fail with, and the index of entries by day both stores keep.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';
import '../entries/calendar_entry.dart';

/// Whether every day of the range a store shows is read, or the read it
/// waits on failed.
enum CalendarLoadStatus { loading, failed, ready }

/// An entry as a view shows it: [pending] while a write on it runs.
@immutable
class CalendarShownEntry<T> {
  /// The [entry] a view shows, and whether a write on it runs.
  const CalendarShownEntry(this.entry, {required this.pending});

  /// The entry to draw: a pending move's requested entry, else the stored
  /// one.
  final CalendarEntry<T> entry;

  /// Whether a write on the entry runs.
  final bool pending;

  /// The entry's id. A shown entry is always a stored one, so it has one.
  String get id {
    return entry.id!;
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarShownEntry<T> &&
        other.entry == entry &&
        other.pending == pending;
  }

  @override
  int get hashCode {
    return Object.hash(entry, pending);
  }

  @override
  String toString() {
    return "CalendarShownEntry($id, pending: $pending)";
  }
}

/// A write the store refuses itself, sending nothing to a data source.
sealed class CalendarStoreException implements Exception {
  const CalendarStoreException();
}

/// The write changes an entry's start or end, or creates one, outside the
/// store's [CalendarStore.hours] ([DayHours.holdsTimes]).
final class CalendarHoursException extends CalendarStoreException {
  /// The refusal of an entry from [start] to [end] under [hours].
  const CalendarHoursException({
    required this.hours,
    required this.start,
    required this.end,
  });

  /// The store's hours when it refused the write.
  final DayHours hours;

  /// The refused entry's start.
  final DateTime start;

  /// The refused entry's end.
  final DateTime end;

  /// Whether [hours] do not hold [start]'s minute of its day as a start
  /// ([DayHours.holdsStart]).
  bool get startOutside {
    return !hours.holdsStart(minuteOfDay(start));
  }

  /// Whether [hours] do not hold [end]'s minute of its last day as an end
  /// ([DayHours.holdsEnd], [endMinuteOfDay]).
  bool get endOutside {
    return !hours.holdsEnd(endMinuteOfDay(end));
  }

  @override
  String toString() {
    return "CalendarHoursException($start to $end outside $hours)";
  }
}

/// The entry [id] has a write in flight, so the store sends no other.
final class CalendarWritePendingException extends CalendarStoreException {
  /// The refusal of a write on [id], which has one in flight.
  const CalendarWritePendingException(this.id);

  /// The id of the entry whose write is in flight.
  final String id;

  @override
  String toString() {
    return "CalendarWritePendingException($id)";
  }
}

/// The entries a calendar shows, the load state of the range it shows, and
/// its writes.
///
/// A store notifies its listeners whenever what it answers changes. An
/// entry has one write in flight at most: while it runs the entry shows
/// [CalendarShownEntry.pending], and a write on it sends nothing and fails
/// with a [CalendarWritePendingException]. Each write returns a future
/// that completes once the write is stored, or fails to its caller with
/// the error that kept it from being stored.
abstract class CalendarStore<T> extends ChangeNotifier {
  /// A store holding writes to [hours].
  CalendarStore({DayHours hours = DayHours.allDay}) : _hours = hours;

  DayHours _hours;

  /// The hours a new entry, and a write that changes an entry's start or
  /// end, must lie in ([DayHours.holdsTimes]), which hold every all-day
  /// entry. A write that keeps the stored start and end is not held to
  /// them, so an entry that lay outside them when they changed can still
  /// be edited. A calendar shows and schedules in its store's hours.
  ///
  /// Setting hours not `==` to these notifies the listeners once, and
  /// setting equal ones notifies nothing. A calendar listening builds again
  /// at a notify, so a host sets the hours outside a build.
  DayHours get hours {
    return _hours;
  }

  set hours(DayHours value) {
    if (value == _hours) {
      return;
    }
    _hours = value;
    notifyListeners();
  }

  /// Whether every day of the shown range is read, or the read it waits
  /// on failed.
  CalendarLoadStatus get status;

  /// The error the read the shown range waited on failed with, while
  /// [status] is [CalendarLoadStatus.failed]; null otherwise.
  Object? get loadError;

  /// Shows [first] to [last], both inclusive, reading the days not read
  /// yet.
  void show(DateTime first, DateTime last);

  /// Reads again the shown range's unread days after its read failed.
  void retry();

  /// Reads the unread days from [first] to [last], both inclusive,
  /// without showing them.
  void prefetch(DateTime first, DateTime last);

  /// Takes every entry with a part in the days from [first] to [last],
  /// both inclusive, to have changed at its source, so the store answers
  /// those days anew.
  void invalidate(DateTime first, DateTime last);

  /// Takes every entry to have changed at its source, so the store answers
  /// every day anew. Completes once the shown range is answered anew, or
  /// fails with the error that kept it from being read.
  Future<void> refresh();

  /// Whether [day] is read.
  bool isRead(DateTime day);

  /// Whether the last read of [day], which is unread, failed.
  bool readFailed(DateTime day);

  /// Whether the shown range is exactly [first] to [last].
  bool isShown(DateTime first, DateTime last);

  /// Whether the shown range holds every day from [first] to [last].
  bool isWithinShown(DateTime first, DateTime last);

  /// The entries shown on [day], sorted by start, end, title and id; a new
  /// list.
  List<CalendarShownEntry<T>> entriesOn(DateTime day);

  /// The entries shown on any day from [first] to [last], each once,
  /// sorted as [entriesOn] sorts; a new list.
  List<CalendarShownEntry<T>> entriesBetween(DateTime first, DateTime last);

  /// Whether [day] shows a marker for the entries on it.
  bool dayHasShownEntries(DateTime day);

  /// Whether a write on the entry [id] runs.
  bool isPending(String id);

  /// The entry [id] as stored, without a pending move's requested time.
  CalendarEntry<T>? storedEntry(String id);

  /// Stores [draft]; completes with the stored entry, which has an id, or
  /// fails with the error that kept it from being stored. A draft outside
  /// [hours] fails with a [CalendarHoursException].
  Future<CalendarEntry<T>> create(CalendarEntry<T> draft);

  /// Writes [entry] over the stored entry its id names; completes with the
  /// stored entry, or fails with the error that kept it from being
  /// stored. An entry with no id fails with an [ArgumentError], and one
  /// [hoursRefusalOf] refuses with a [CalendarHoursException].
  Future<CalendarEntry<T>> update(CalendarEntry<T> entry);

  /// Writes a grid move or resize to [requested], whose id names a stored
  /// entry, whether or not it shares time with another entry; completes
  /// with the stored entry, or fails with the error that kept it from
  /// being stored, the stored entry showing again. An entry with no id
  /// fails with an [ArgumentError], and one [hoursRefusalOf] refuses with
  /// a [CalendarHoursException].
  Future<CalendarEntry<T>> requestMove(CalendarEntry<T> requested);

  /// Deletes the entry [id]; completes once it is deleted, or fails with
  /// the error that kept it from being deleted, the entry staying stored.
  Future<void> requestDelete(String id);

  /// The refusal of [entry] for [hours], or null when the hours hold its
  /// start and its end ([DayHours.holdsTimes]), or when it keeps the start
  /// and end of the stored entry its id names.
  @protected
  CalendarHoursException? hoursRefusalOf(CalendarEntry<T> entry) {
    final id = entry.id;
    final stored = id == null ? null : storedEntry(id);
    if (stored != null &&
        stored.start == entry.start &&
        stored.end == entry.end) {
      return null;
    }
    if (hours.holdsTimes(entry.start, entry.end)) {
      return null;
    }
    return CalendarHoursException(
      hours: hours,
      start: entry.start,
      end: entry.end,
    );
  }
}

/// The entries a store holds, by id and by day, and its pending writes,
/// answering the reads of [CalendarStore].
///
/// Each open day keeps the stored entries covering it in one list, sorted
/// by start, end, title and id, which is a total order since ids are
/// distinct. Each pending write keeps the entry its id shows, the
/// requested entry of a move or else the stored one, in one more list in
/// that order. A read takes each open day's list less its pending ids as
/// one sorted run and the pending list as another, and merges them, so it
/// costs the entries it answers and a log of the runs, with no sort.
///
/// Days are [dayNumber]s.
class CalendarEntryIndex<T> {
  /// An empty index. With [opensEveryDay], [put] opens every day an entry
  /// covers, and a day [put] or [forget] empties closes; otherwise only
  /// [open] opens a day, and an open day stays open until [clear].
  CalendarEntryIndex({required this.opensEveryDay});

  /// Whether every day a stored entry covers is open, and only those.
  final bool opensEveryDay;

  final Map<String, CalendarEntry<T>> _stored = <String, CalendarEntry<T>>{};

  /// Each open day's stored entries, in [compareCalendarEntries]'s order.
  final Map<int, List<CalendarEntry<T>>> _byDay =
      <int, List<CalendarEntry<T>>>{};

  /// An entry per pending id: the entry it files in [_pendingList], or
  /// null when it files none.
  final Map<String, CalendarEntry<T>?> _pending = <String, CalendarEntry<T>?>{};

  /// The entries the pending ids show, in [compareCalendarEntries]'s order.
  final List<CalendarEntry<T>> _pendingList = <CalendarEntry<T>>[];

  /// The entry [id] as stored.
  CalendarEntry<T>? stored(String id) {
    return _stored[id];
  }

  /// Every stored entry, in no set order.
  Iterable<CalendarEntry<T>> get storedEntries {
    return _stored.values;
  }

  /// The stored entries filed under [day], in order; a new list, empty
  /// when [day] is not open.
  List<CalendarEntry<T>> storedOn(int day) {
    return List<CalendarEntry<T>>.of(_byDay[day] ?? const <Never>[]);
  }

  /// Whether [day] is open.
  bool isOpen(int day) {
    return _byDay.containsKey(day);
  }

  /// Stores [entry], whose id no stored entry has, without filing it under
  /// any day; false, changing nothing, when one has. A pending id that
  /// shows no entry shows this one.
  bool addIfAbsent(CalendarEntry<T> entry) {
    final id = entry.id!;
    if (_stored.containsKey(id)) {
      return false;
    }
    _stored[id] = entry;
    if (_pending.containsKey(id) && _pending[id] == null) {
      _pending[id] = entry;
      _insert(_pendingList, entry);
    }
    return true;
  }

  /// Opens each of [days] that is not open, or, given none, every day a
  /// stored entry covers that is not open, and files under the days it
  /// opens every stored entry covering them.
  ///
  /// One pass over the stored entries files each under the opened days it
  /// covers, and one sort per opened day orders its list.
  void open([Iterable<int>? days]) {
    final opened = <int, List<CalendarEntry<T>>>{};
    if (days == null) {
      for (final entry in _stored.values) {
        for (var day = _firstDayOf(entry); day <= _lastDayOf(entry); day++) {
          if (_byDay.containsKey(day)) {
            continue;
          }
          (opened[day] ??= <CalendarEntry<T>>[]).add(entry);
        }
      }
    } else {
      int? first;
      int? last;
      for (final day in days) {
        if (!_byDay.containsKey(day) && !opened.containsKey(day)) {
          opened[day] = <CalendarEntry<T>>[];
          first = first == null ? day : math.min(first, day);
          last = last == null ? day : math.max(last, day);
        }
      }
      if (first == null || last == null) {
        return;
      }
      for (final entry in _stored.values) {
        final from = math.max(_firstDayOf(entry), first);
        final to = math.min(_lastDayOf(entry), last);
        for (var day = from; day <= to; day++) {
          opened[day]?.add(entry);
        }
      }
    }
    for (final MapEntry(key: day, value: list) in opened.entries) {
      list.sort(compareCalendarEntries);
      _byDay[day] = list;
    }
  }

  /// Stores [entry] in place of the entry its id names, if any: unfiles
  /// the old one and files the new one under the days it covers, every one
  /// with [opensEveryDay], otherwise the open ones. A pending id that
  /// shows no entry shows this one.
  void put(CalendarEntry<T> entry) {
    final id = entry.id!;
    forget(id);
    _stored[id] = entry;
    if (_pending.containsKey(id) && _pending[id] == null) {
      _pending[id] = entry;
      _insert(_pendingList, entry);
    }
    final last = _lastDayOf(entry);
    for (var day = _firstDayOf(entry); day <= last; day++) {
      var list = _byDay[day];
      if (list == null) {
        if (!opensEveryDay) {
          continue;
        }
        list = _byDay[day] = <CalendarEntry<T>>[];
      }
      _insert(list, entry);
    }
  }

  /// Removes the entry [id] and unfiles it; answers it, or null when none
  /// is stored.
  CalendarEntry<T>? forget(String id) {
    final old = _stored.remove(id);
    if (old == null) {
      return null;
    }
    final last = _lastDayOf(old);
    for (var day = _firstDayOf(old); day <= last; day++) {
      final list = _byDay[day];
      if (list == null) {
        continue;
      }
      _remove(list, old);
      if (opensEveryDay && list.isEmpty) {
        _byDay.remove(day);
      }
    }
    return old;
  }

  /// Removes every entry, day and pending write.
  void clear() {
    _stored.clear();
    _byDay.clear();
    _pending.clear();
    _pendingList.clear();
  }

  /// Whether a write on [id] runs.
  bool isPending(String id) {
    return _pending.containsKey(id);
  }

  /// Marks [id] pending, showing [shown] or, when null, the stored entry
  /// if there is one. False, changing nothing, when [id] is pending
  /// already.
  bool lock(String id, CalendarEntry<T>? shown) {
    if (_pending.containsKey(id)) {
      return false;
    }
    final filed = shown ?? _stored[id];
    _pending[id] = filed;
    if (filed != null) {
      _insert(_pendingList, filed);
    }
    return true;
  }

  /// Ends the pending write on [id], if any.
  void release(String id) {
    if (!_pending.containsKey(id)) {
      return;
    }
    final filed = _pending.remove(id);
    if (filed != null) {
      _remove(_pendingList, filed);
    }
  }

  /// The entries shown on [day]: its stored entries whose ids are not
  /// pending, and the pending entries covering it, merged in order.
  List<CalendarShownEntry<T>> entriesOn(int day) {
    final stored = _byDay[day] ?? const <Never>[];
    final anyPending = _pending.isNotEmpty;
    final shown = <CalendarShownEntry<T>>[];
    var i = 0;
    var j = 0;
    while (true) {
      while (anyPending &&
          i < stored.length &&
          _pending.containsKey(stored[i].id)) {
        i++;
      }
      while (j < _pendingList.length && !_covers(_pendingList[j], day)) {
        j++;
      }
      if (i == stored.length && j == _pendingList.length) {
        return shown;
      }
      if (j == _pendingList.length ||
          (i < stored.length &&
              compareCalendarEntries(stored[i], _pendingList[j]) < 0)) {
        shown.add(CalendarShownEntry<T>(stored[i], pending: false));
        i++;
      } else {
        shown.add(CalendarShownEntry<T>(_pendingList[j], pending: true));
        j++;
      }
    }
  }

  /// The entries shown on any day from [first] to [last], each once.
  ///
  /// Each open day of the range adds its stored entries whose ids are not
  /// pending as one run, and the pending entries meeting the range add one
  /// more. The runs are merged in rounds through one scratch list; two
  /// entries comparing equal are one entry filed under two days, and the
  /// merge keeps one of them.
  List<CalendarShownEntry<T>> entriesBetween(int first, int last) {
    final anyPending = _pending.isNotEmpty;
    var runs = <CalendarShownEntry<T>>[];
    for (var day = first; day <= last; day++) {
      final list = _byDay[day];
      if (list == null) {
        continue;
      }
      for (final entry in list) {
        if (!anyPending || !_pending.containsKey(entry.id)) {
          runs.add(CalendarShownEntry<T>(entry, pending: false));
        }
      }
    }
    for (final entry in _pendingList) {
      if (_firstDayOf(entry) <= last && _lastDayOf(entry) >= first) {
        runs.add(CalendarShownEntry<T>(entry, pending: true));
      }
    }
    // A run is a stretch in strictly ascending order, so every day's list
    // and the pending list are each one, or part of one.
    List<CalendarShownEntry<T>>? scratch;
    while (_runEnd(runs, 0) < runs.length) {
      final merged = scratch ?? <CalendarShownEntry<T>>[];
      merged.clear();
      var start = 0;
      while (start < runs.length) {
        final middle = _runEnd(runs, start);
        final end = middle == runs.length ? middle : _runEnd(runs, middle);
        _mergeRuns(runs, start, middle, end, merged);
        start = end;
      }
      scratch = runs;
      runs = merged;
    }
    return runs;
  }

  /// Whether [day] shows an entry: a stored one whose id is not pending, or
  /// a pending one covering it.
  bool hasShownOn(int day) {
    final stored = _byDay[day];
    if (stored != null) {
      if (stored.isNotEmpty && _pending.isEmpty) {
        return true;
      }
      for (final entry in stored) {
        if (!_pending.containsKey(entry.id)) {
          return true;
        }
      }
    }
    for (final entry in _pendingList) {
      if (_covers(entry, day)) {
        return true;
      }
    }
    return false;
  }

  /// The [dayNumber] of the first day [entry] has a part in.
  static int _firstDayOf<T>(CalendarEntry<T> entry) {
    return dayNumber(entry.start);
  }

  /// The [dayNumber] of the last day [entry] has a part in
  /// ([lastDayNumberOf]), never a day its end is the start of.
  static int _lastDayOf<T>(CalendarEntry<T> entry) {
    return lastDayNumberOf(entry.start, entry.end);
  }

  /// Whether [entry] has a part in the [dayNumber] [day].
  static bool _covers<T>(CalendarEntry<T> entry, int day) {
    return day >= _firstDayOf(entry) && day <= _lastDayOf(entry);
  }

  /// The end of the strictly ascending run of [shown] that starts at
  /// [start]: [shown]'s length when [start] is past its last entry.
  int _runEnd(List<CalendarShownEntry<T>> shown, int start) {
    if (start >= shown.length) {
      return shown.length;
    }
    var end = start + 1;
    while (end < shown.length &&
        compareCalendarEntries(shown[end - 1].entry, shown[end].entry) < 0) {
      end++;
    }
    return end;
  }

  /// Appends to [into] the runs of [from] from [start] to [middle] and from
  /// [middle] to [end], merged, keeping one of two entries that compare
  /// equal.
  void _mergeRuns(
    List<CalendarShownEntry<T>> from,
    int start,
    int middle,
    int end,
    List<CalendarShownEntry<T>> into,
  ) {
    var i = start;
    var j = middle;
    while (i < middle && j < end) {
      final order = compareCalendarEntries(from[i].entry, from[j].entry);
      if (order < 0) {
        into.add(from[i]);
        i++;
      } else if (order > 0) {
        into.add(from[j]);
        j++;
      } else {
        into.add(from[i]);
        i++;
        j++;
      }
    }
    while (i < middle) {
      into.add(from[i]);
      i++;
    }
    while (j < end) {
      into.add(from[j]);
      j++;
    }
  }

  /// Files [entry] in [list] at its place in [compareCalendarEntries]'s order.
  void _insert(List<CalendarEntry<T>> list, CalendarEntry<T> entry) {
    list.insert(_lowerBound(list, entry), entry);
  }

  /// Takes [entry], which [list] holds, out of [list].
  void _remove(List<CalendarEntry<T>> list, CalendarEntry<T> entry) {
    final index = _lowerBound(list, entry);
    if (index < list.length && list[index].id == entry.id) {
      list.removeAt(index);
    }
  }

  /// The first index of [list] whose entry does not sort before [entry].
  int _lowerBound(List<CalendarEntry<T>> list, CalendarEntry<T> entry) {
    var low = 0;
    var high = list.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (compareCalendarEntries(list[middle], entry) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

/// The order a store answers entries in: by start, end, title and id, a
/// total order over entries with distinct ids.
int compareCalendarEntries<T>(CalendarEntry<T> a, CalendarEntry<T> b) {
  final byStart = a.start.compareTo(b.start);
  if (byStart != 0) {
    return byStart;
  }
  final byEnd = a.end.compareTo(b.end);
  if (byEnd != 0) {
    return byEnd;
  }
  final byTitle = a.title.compareTo(b.title);
  if (byTitle != 0) {
    return byTitle;
  }
  return a.id!.compareTo(b.id!);
}
