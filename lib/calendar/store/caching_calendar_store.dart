/// The store that reads through a data source by days and caches what it
/// read.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';
import '../entries/calendar_data_source.dart';
import '../entries/calendar_entry.dart';
import 'calendar_store.dart';

/// One `read` call in flight, over the [dayNumber]s [first] to [last].
class _Read {
  _Read(this.first, this.last);

  final int first;
  final int last;

  bool covers(int first, int last) {
    return this.first <= first && this.last >= last;
  }
}

/// A [CalendarStore] over a [CalendarDataSource]: a cache of the days it
/// has read, the range the calendar shows, and the writes in flight.
///
/// A day once read changes only by a confirmed write: a later read fills
/// only the days not read yet, and a failed read leaves its days unread,
/// so the next read that covers them reads them again.
///
/// A write takes its entry pending from the call until the data source
/// answers: a move or a resize shows the requested entry meanwhile, and an
/// update or a delete the stored one. A create shows nothing until the
/// source answers. A write on a pending entry sends nothing and fails
/// with a [CalendarWritePendingException], where that write reports a
/// failure, and so does one [hoursRefusalOf] refuses, with a
/// [CalendarHoursException]. The store refuses no write for sharing time
/// with another entry; a data source that forbids it fails the write.
///
/// The store holds the source to its contract: a read answering an entry
/// with no id fails as a read does, a create answering one with no id
/// fails to its caller, and a write answered under another id than the one
/// written fails as that write fails, each with a [StateError]. A source
/// call that throws instead of failing its future fails as its future
/// would.
class CachingCalendarStore<T> extends CalendarStore<T> {
  /// A store reading and writing through [dataSource], loading until the
  /// first [show].
  CachingCalendarStore({
    required CalendarDataSource<T> dataSource,
    super.hours,
    super.onWriteFailed,
  }) : _dataSource = dataSource;

  final CalendarDataSource<T> _dataSource;

  /// Each read day, by [dayNumber], with the count of [show] calls made
  /// when it was read.
  final Map<int, int> _readDays = <int, int>{};

  /// The [show] calls that changed the shown range.
  int _showCount = 0;

  /// The entries the cache knows, filed under the read days, and the
  /// pending writes.
  final CalendarEntryIndex<T> _index = CalendarEntryIndex<T>(
    opensEveryDay: false,
  );

  /// The reads in flight, in the order they were sent.
  final List<_Read> _reads = <_Read>[];

  /// The unread days, by [dayNumber], whose last read failed, until a read
  /// is sent for them again.
  final Set<int> _failedDays = <int>{};

  int? _shownFirst;
  int? _shownLast;

  /// The read the shown range waits on.
  _Read? _awaited;

  CalendarLoadStatus _status = CalendarLoadStatus.loading;
  Object? _loadError;
  bool _disposed = false;

  /// Whether every day of the shown range is read, or the read it waits
  /// on failed. Loading before the first [show].
  @override
  CalendarLoadStatus get status {
    return _status;
  }

  /// The error the read the shown range waited on failed with, as the
  /// data source failed it, while [status] is failed.
  @override
  Object? get loadError {
    return _loadError;
  }

  /// Shows [first] to [last], both inclusive. A range whose days are all
  /// read is ready at once and sends nothing; otherwise the range waits on
  /// the earliest-sent read in flight that covers its unread days, or
  /// sends a read for them. Showing the range already shown changes
  /// nothing.
  @override
  void show(DateTime first, DateTime last) {
    final firstDay = dayNumber(first);
    final lastDay = dayNumber(last);
    if (firstDay == _shownFirst && lastDay == _shownLast) {
      return;
    }
    _shownFirst = firstDay;
    _shownLast = lastDay;
    _showCount++;
    _loadError = null;
    final unread = _unreadSpan();
    if (unread == null) {
      _awaited = null;
      _status = CalendarLoadStatus.ready;
    } else {
      _status = CalendarLoadStatus.loading;
      final inFlight = _inFlightCovering(unread.first, unread.last);
      if (inFlight != null) {
        _awaited = inFlight;
      } else {
        _send(unread.first, unread.last, awaited: true);
      }
    }
    notifyListeners();
  }

  /// Whether [day] is read.
  @override
  bool isRead(DateTime day) {
    return _readDays.containsKey(dayNumber(day));
  }

  /// Whether the last read of [day], which is unread, failed, and no read
  /// has been sent for it since.
  @override
  bool readFailed(DateTime day) {
    return _failedDays.contains(dayNumber(day));
  }

  /// Whether the shown range is exactly [first] to [last].
  @override
  bool isShown(DateTime first, DateTime last) {
    return _shownFirst == dayNumber(first) && _shownLast == dayNumber(last);
  }

  /// Whether the shown range holds every day from [first] to [last]. False
  /// before the first [show].
  @override
  bool isWithinShown(DateTime first, DateTime last) {
    final shownFirst = _shownFirst;
    final shownLast = _shownLast;
    return shownFirst != null &&
        shownLast != null &&
        shownFirst <= dayNumber(first) &&
        dayNumber(last) <= shownLast;
  }

  /// Sends a new read for the shown range's unread days; with none unread
  /// it sends nothing and the range is ready.
  @override
  void retry() {
    if (_shownFirst == null) {
      return;
    }
    _loadError = null;
    final unread = _unreadSpan();
    if (unread == null) {
      _awaited = null;
      _status = CalendarLoadStatus.ready;
    } else {
      _status = CalendarLoadStatus.loading;
      _send(unread.first, unread.last, awaited: true);
    }
    notifyListeners();
  }

  /// Reads the unread days from [first] to [last], both inclusive, without
  /// showing them, so the markers of days about to show appear once read.
  /// Sends nothing when every day is read or a read in flight covers the
  /// unread ones. Changes neither the shown range nor [status], and a
  /// failed read leaves its days unread and marks them [readFailed].
  @override
  void prefetch(DateTime first, DateTime last) {
    final unread = _unreadSpanOf(dayNumber(first), dayNumber(last));
    if (unread == null ||
        _inFlightCovering(unread.first, unread.last) != null) {
      return;
    }
    _send(unread.first, unread.last, awaited: false);
  }

  /// The first to the last unread day of the shown range, or null when
  /// every day of it is read.
  ({int first, int last})? _unreadSpan() {
    return _unreadSpanOf(_shownFirst!, _shownLast!);
  }

  /// The first to the last unread day from [firstDay] to [lastDay], or
  /// null when every day of them is read.
  ({int first, int last})? _unreadSpanOf(int firstDay, int lastDay) {
    int? first;
    int? last;
    for (var day = firstDay; day <= lastDay; day++) {
      if (!_readDays.containsKey(day)) {
        first ??= day;
        last = day;
      }
    }
    if (first == null) {
      return null;
    }
    return (first: first, last: last!);
  }

  /// The earliest-sent read in flight covering [first] to [last].
  _Read? _inFlightCovering(int first, int last) {
    for (final read in _reads) {
      if (read.covers(first, last)) {
        return read;
      }
    }
    return null;
  }

  /// Sends a read of [first] to [last], which the shown range waits on
  /// when [awaited]. The shown range waits on it before the source is
  /// called, so an answer that arrives within the call, as a
  /// [SynchronousFuture]'s does, settles the range.
  void _send(int first, int last, {required bool awaited}) {
    final read = _Read(first, last);
    _reads.add(read);
    if (awaited) {
      _awaited = read;
    }
    _failedDays.removeWhere((day) {
      return day >= first && day <= last;
    });
    Future<List<CalendarEntry<T>>>.sync(() {
      return _dataSource.read(dateOfDayNumber(first), dateOfDayNumber(last));
    }).then(
      (entries) {
        _finishRead(read, entries: entries);
      },
      onError: (Object error) {
        _finishRead(read, error: error);
      },
    );
  }

  /// A read's answer. A failed one marks [readFailed] each of its days that
  /// no read has filled and no read in flight covers. A read the shown
  /// range does not wait on changes no load state, so it notifies only
  /// when it marked days read, whose markers [dayHasShownEntries] may now
  /// show, or failed.
  void _finishRead(
    _Read read, {
    List<CalendarEntry<T>>? entries,
    Object? error,
  }) {
    if (_disposed) {
      return;
    }
    _reads.remove(read);
    var answered = entries;
    var failure = error;
    if (answered != null) {
      for (final entry in answered) {
        if (entry.id == null) {
          failure = StateError("The data source read an entry with no id.");
          answered = null;
          break;
        }
      }
    }
    final marked = answered != null && _applyRead(read, answered);
    var failed = false;
    if (answered == null) {
      for (var day = read.first; day <= read.last; day++) {
        if (!_readDays.containsKey(day) &&
            _inFlightCovering(day, day) == null &&
            _failedDays.add(day)) {
          failed = true;
        }
      }
    }
    if (!identical(_awaited, read)) {
      if (marked || failed) {
        notifyListeners();
      }
      return;
    }
    _awaited = null;
    // A failed read leaves the range ready when another read has filled
    // its days since.
    if (answered != null || _unreadSpan() == null) {
      _status = CalendarLoadStatus.ready;
      _loadError = null;
    } else {
      _status = CalendarLoadStatus.failed;
      _loadError = failure;
    }
    notifyListeners();
  }

  /// Adds the entries the cache does not know, marks the read's unread
  /// days read, and files every cached entry under those of them its
  /// cached time covers, so a known entry lies where the cache holds it
  /// whether or not the answer returned it there. A day already read keeps
  /// what it holds. Returns whether it marked any day read.
  bool _applyRead(_Read read, List<CalendarEntry<T>> entries) {
    final fresh = <int>[];
    for (var day = read.first; day <= read.last; day++) {
      if (!_readDays.containsKey(day)) {
        _readDays[day] = _showCount;
        fresh.add(day);
      }
    }
    for (final entry in entries) {
      _index.addIfAbsent(entry);
    }
    if (fresh.isEmpty) {
      return false;
    }
    _index.open(fresh);
    return true;
  }

  /// The entries shown on [day], sorted by start, end, title and id: those
  /// filed under it when it is read, and the pending entries covering it.
  @override
  List<CalendarShownEntry<T>> entriesOn(DateTime day) {
    return _index.entriesOn(dayNumber(day));
  }

  /// The entries shown on any day from [first] to [last], each once,
  /// sorted as [entriesOn] sorts.
  @override
  List<CalendarShownEntry<T>> entriesBetween(DateTime first, DateTime last) {
    return _index.entriesBetween(dayNumber(first), dayNumber(last));
  }

  /// Whether [day] shows a marker: it has shown entries, and, while the
  /// shown range is not ready, it was read under an earlier [show] call.
  @override
  bool dayHasShownEntries(DateTime day) {
    final number = dayNumber(day);
    final readAt = _readDays[number];
    if (readAt == null) {
      return false;
    }
    if (_status != CalendarLoadStatus.ready && readAt >= _showCount) {
      return false;
    }
    return _index.hasShownOn(number);
  }

  /// Whether a write on [id] runs.
  @override
  bool isPending(String id) {
    return _index.isPending(id);
  }

  /// The entry as the data source last confirmed it.
  @override
  CalendarEntry<T>? storedEntry(String id) {
    return _index.stored(id);
  }

  /// Stores [draft] through the data source; completes with the stored
  /// entry, or fails with the source's error. Nothing is shown before the
  /// source answers. A draft outside [hours] sends nothing and fails with
  /// a [CalendarHoursException]. An answer with no id fails with a
  /// [StateError] and stores nothing; one whose id has a write in flight,
  /// as after a read that brought the entry and a move of it, completes
  /// and changes nothing.
  @override
  Future<CalendarEntry<T>> create(CalendarEntry<T> draft) async {
    final refusal = hoursRefusalOf(draft);
    if (refusal != null) {
      throw refusal;
    }
    final created = await _dataSource.create(draft);
    final id = created.id;
    if (id == null) {
      throw StateError("The data source created an entry with no id.");
    }
    if (!_disposed && !_index.isPending(id)) {
      _index.put(created);
      notifyListeners();
    }
    return created;
  }

  /// Writes [entry], whose id names a stored entry; the entry shows
  /// pending, as stored, until the data source answers. Completes with the
  /// stored entry, or fails with the source's error, which the caller
  /// reports: a failure does not reach [onWriteFailed]. It sends nothing
  /// and fails with an [ArgumentError] for an entry with no id, with a
  /// [CalendarHoursException] when [hoursRefusalOf] refuses it, and with
  /// a [CalendarWritePendingException] on a pending entry. An answer under
  /// another id fails with a [StateError].
  @override
  Future<CalendarEntry<T>> update(CalendarEntry<T> entry) async {
    final id = entry.id;
    if (id == null) {
      throw ArgumentError.value(entry, "entry", "An update needs an id.");
    }
    final refusal = hoursRefusalOf(entry);
    if (refusal != null) {
      throw refusal;
    }
    if (!_lock(id, null)) {
      throw CalendarWritePendingException(id);
    }
    try {
      final updated = await _dataSource.replace(entry);
      if (updated.id != id) {
        throw StateError(
          "The data source replaced $id with an entry under ${updated.id}.",
        );
      }
      if (!_disposed) {
        _applyConfirmed(updated);
        notifyListeners();
      }
      return updated;
    } on Object {
      if (!_disposed) {
        _index.release(id);
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Writes a grid move or resize: [requested] shows, pending, until the
  /// data source answers. A failure shows the stored entry again and
  /// reports through [onWriteFailed]. Sends nothing and reports through
  /// [onWriteFailed] instead a [CalendarHoursException] for a move
  /// [hoursRefusalOf] refuses, and a [CalendarWritePendingException] for
  /// a pending entry; a move onto another entry's time is sent. Throws an
  /// [ArgumentError] for an entry with no id.
  @override
  void requestMove(CalendarEntry<T> requested) {
    final id = requested.id;
    if (id == null) {
      throw ArgumentError.value(requested, "requested", "A move needs an id.");
    }
    final refusal = hoursRefusalOf(requested);
    if (refusal != null) {
      reportWriteFailure(id, refusal);
      return;
    }
    if (!_lock(id, requested)) {
      reportWriteFailure(id, CalendarWritePendingException(id));
      return;
    }
    Future<CalendarEntry<T>>.sync(() {
      return _dataSource.replace(requested);
    }).then(
      (moved) {
        if (_disposed) {
          return;
        }
        if (moved.id != id) {
          _failWrite(
            id,
            StateError(
              "The data source replaced $id with an entry under ${moved.id}.",
            ),
            StackTrace.current,
          );
          return;
        }
        _applyConfirmed(moved);
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        _failWrite(id, error, stackTrace);
      },
    );
  }

  /// Deletes [id]: the stored entry shows pending until the data source
  /// answers, and leaves on success. A failure reports through
  /// [onWriteFailed], and so does a [CalendarWritePendingException] for a
  /// pending entry, which sends nothing.
  @override
  void requestDelete(String id) {
    if (!_lock(id, null)) {
      reportWriteFailure(id, CalendarWritePendingException(id));
      return;
    }
    Future<void>.sync(() {
      return _dataSource.delete(id);
    }).then(
      (_) {
        if (_disposed) {
          return;
        }
        _index.release(id);
        _index.forget(id);
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        _failWrite(id, error, stackTrace);
      },
    );
  }

  /// Marks [id] pending, showing [shown] or, when null, the stored entry.
  /// False, changing nothing, when [id] is pending already: every update,
  /// move and delete passes here, so an id has one write in flight at
  /// most.
  bool _lock(String id, CalendarEntry<T>? shown) {
    if (!_index.lock(id, shown)) {
      return false;
    }
    notifyListeners();
    return true;
  }

  void _failWrite(String id, Object error, StackTrace stackTrace) {
    if (_disposed) {
      return;
    }
    _index.release(id);
    notifyListeners();
    reportWriteFailure(id, error, stackTrace);
  }

  /// Ends the pending write on [entry]'s id and stores [entry], filed
  /// under the read days it covers.
  void _applyConfirmed(CalendarEntry<T> entry) {
    _index.release(entry.id!);
    _index.put(entry);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
