/// The store that reads through a data source by days and caches what it
/// read.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';
import '../entries/calendar_data_source.dart';
import '../entries/calendar_entry.dart';
import 'calendar_store.dart';

/// One `read` call in flight, over the [dayNumber]s [first] to [last].
class _Read {
  _Read(this.first, this.last, this.sentAt, this.done);

  final int first;
  final int last;

  /// The store's clock when the read was sent.
  final int sentAt;

  /// The refresh that waits on the read, if any.
  final Completer<void>? done;

  /// The span of the read's days announced changed while it was in flight,
  /// and the clock of the latest such change; [changedAt] is 0 while none
  /// is.
  int changedFirst = 0;
  int changedLast = 0;
  int changedAt = 0;

  /// Whether the read covers [first] to [last] and was sent after the
  /// clock [since].
  bool covers(int first, int last, int since) {
    return this.first <= first && this.last >= last && sentAt > since;
  }

  /// Records a change announced at the clock [at] on its days [first] to
  /// [last].
  void markChanged(int first, int last, int at) {
    if (changedAt == 0) {
      changedFirst = first;
      changedLast = last;
    } else {
      changedFirst = math.min(changedFirst, first);
      changedLast = math.max(changedLast, last);
    }
    changedAt = at;
  }
}

/// A read day.
class _Day {
  _Day(this.shownAt, this.filledAt);

  /// The count of [CachingCalendarStore.show] calls made when the day was
  /// first read.
  final int shownAt;

  /// The store's clock when the read that last filled the day was sent.
  int filledAt;

  /// The store's clock when a change on the day was last announced; 0
  /// while none is.
  int changedAt = 0;
}

/// A [CalendarStore] over a [CalendarDataSource]: a copy of the entries on
/// the days it has read, the range the calendar shows, and the writes in
/// flight.
///
/// A read's answer is what the source stored on the read's days when it
/// was sent. It replaces what the store holds there: each entry it answers
/// takes the place of the held one, and each held entry it does not answer
/// is forgotten, except where a later read, a write confirmed since or a
/// change announced since told the store otherwise. A failed read leaves
/// its unread days unread, so the next read that covers them reads them
/// again.
///
/// A day once read stays read. [invalidate], [refresh] and the changes the
/// source announces take a read day's entries to have changed: the day
/// still shows what the store holds, and is read again in the background,
/// at once where the shown range holds it and otherwise once a [show] or a
/// [prefetch] covers it.
///
/// A write takes its entry pending from the call until the data source
/// answers: a move or a resize shows the requested entry meanwhile, and an
/// update or a delete the stored one. A create shows nothing until the
/// source answers. A write on a pending entry sends nothing and fails
/// with a [CalendarWritePendingException], and so does one
/// [hoursRefusalOf] refuses, with a [CalendarHoursException]. The store
/// refuses no write for sharing time with another entry; a data source
/// that forbids it fails the write.
///
/// The store holds the source to its contract: a read answering an entry
/// with no id fails as a read does, a create answering one with no id
/// fails to its caller, and a write answered under another id than the one
/// written fails as that write fails, each with a [StateError]. A source
/// call that throws instead of failing its future fails as its future
/// would.
class CachingCalendarStore<T> extends CalendarStore<T> {
  /// A store reading and writing through [dataSource], loading until the
  /// first [show], and applying each change [changes] announces, if given,
  /// until it is disposed: a [CalendarEntryPut] or a [CalendarEntryRemoved]
  /// is applied without a read, a [CalendarDaysChanged] is an [invalidate]
  /// of its days, and a [CalendarAllChanged], or an error on the stream,
  /// takes every entry to have changed, as [refresh] does.
  CachingCalendarStore({
    required CalendarDataSource<T> dataSource,
    Stream<CalendarSourceChange<T>>? changes,
    super.hours,
  }) : _dataSource = dataSource {
    _changes = changes?.listen(_applyChange, onError: _changesFailed);
  }

  final CalendarDataSource<T> _dataSource;

  /// The subscription to the changes the source announces, if any.
  StreamSubscription<CalendarSourceChange<T>>? _changes;

  /// The store's clock, counted up by each read sent, write confirmed and
  /// change announced, which orders what each tells of the source.
  int _clock = 0;

  /// Each read day, by [dayNumber].
  final Map<int, _Day> _days = <int, _Day>{};

  /// The clock when every entry was last taken to have changed.
  int _allChangedAt = 0;

  /// By id, the clock of what last set or removed the entry: a read's
  /// send, a confirmed write or an announced change. Kept only while a read
  /// is in flight, since every read sent later is newer than all of them.
  final Map<String, int> _entryTimes = <String, int>{};

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
  /// read is ready at once; otherwise the range waits on the earliest-sent
  /// read in flight that covers its unread days, or sends a read for them
  /// and its changed days. Changed days of the range that no read sent
  /// since they changed covers are read again in the background. Showing
  /// the range already shown changes nothing.
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
      final inFlight = _inFlightCovering(unread.first, unread.last, 0);
      if (inFlight != null) {
        _awaited = inFlight;
      } else {
        _sendAwaited(unread);
      }
    }
    _readChangedShown();
    notifyListeners();
  }

  /// Whether [day] is read. A changed day stays read.
  @override
  bool isRead(DateTime day) {
    return _days.containsKey(dayNumber(day));
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

  /// Sends a new read for the shown range's unread days and its changed
  /// days; with none unread it sends nothing and the range is ready.
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
      _sendAwaited(unread);
    }
    notifyListeners();
  }

  /// Reads the unread and the changed days from [first] to [last], both
  /// inclusive, without showing them, so the markers of days about to show
  /// appear once read. Sends nothing where reads in flight cover them: for
  /// the unread days any read, and for the changed ones a read sent since
  /// they changed. Changes neither the shown range nor [status], and a
  /// failed read leaves its unread days unread and marks them [readFailed].
  @override
  void prefetch(DateTime first, DateTime last) {
    final firstDay = dayNumber(first);
    final lastDay = dayNumber(last);
    int? from;
    int? to;
    final unread = _unreadSpanOf(firstDay, lastDay);
    if (unread != null &&
        _inFlightCovering(unread.first, unread.last, 0) == null) {
      from = unread.first;
      to = unread.last;
    }
    final changed = _changedSpanOf(firstDay, lastDay);
    if (changed != null &&
        _inFlightCovering(changed.first, changed.last, changed.since) == null) {
      from = math.min(from ?? changed.first, changed.first);
      to = math.max(to ?? changed.last, changed.last);
    }
    if (from == null || to == null) {
      return;
    }
    _send(from, to, awaited: false);
  }

  /// Takes the entries on the days from [first] to [last], both inclusive,
  /// to have changed. Each read day of them still shows what the store
  /// holds, and is read again: at once where the shown range holds it, and
  /// otherwise once a [show] or a [prefetch] covers it. A read in flight
  /// over them leaves them changed once it answers. Notifies nothing.
  @override
  void invalidate(DateTime first, DateTime last) {
    final firstDay = dayNumber(first);
    final lastDay = dayNumber(last);
    if (firstDay > lastDay) {
      return;
    }
    final at = ++_clock;
    for (final record in _readDaysIn(firstDay, lastDay)) {
      record.changedAt = at;
    }
    for (final read in _reads) {
      if (read.first <= lastDay && read.last >= firstDay) {
        read.markChanged(
          math.max(firstDay, read.first),
          math.min(lastDay, read.last),
          at,
        );
      }
    }
    _readChangedShown();
  }

  /// Takes every entry to have changed, as [invalidate] does for every
  /// day, and reads the whole shown range again at once. Where the shown
  /// range has unread days it waits on that read, as after [retry];
  /// otherwise its status stays ready, and a failed read leaves its days
  /// changed. Completes once that read answers, or fails with the error it
  /// failed with; completes at once before the first [show], and when the
  /// store is disposed before the read answers.
  @override
  Future<void> refresh() {
    final done = Completer<void>();
    _changeAll(done);
    return done.future;
  }

  /// Takes every entry to have changed and reads the whole shown range
  /// again, completing [done], if given, once that read answers.
  void _changeAll([Completer<void>? done]) {
    _allChangedAt = ++_clock;
    final first = _shownFirst;
    final last = _shownLast;
    if (first == null || last == null) {
      done?.complete();
      return;
    }
    if (_unreadSpan() == null) {
      _send(first, last, awaited: false, done: done);
      return;
    }
    _status = CalendarLoadStatus.loading;
    _loadError = null;
    _send(first, last, awaited: true, done: done);
    notifyListeners();
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
      if (!_days.containsKey(day)) {
        first ??= day;
        last = day;
      }
    }
    if (first == null) {
      return null;
    }
    return (first: first, last: last!);
  }

  /// The first to the last changed day from [firstDay] to [lastDay], and
  /// the clock of the latest change among them, or null when none is. A
  /// changed day is a read day with a change announced on it since the
  /// read that last filled it was sent.
  ({int first, int last, int since})? _changedSpanOf(
    int firstDay,
    int lastDay,
  ) {
    int? first;
    int? last;
    var since = 0;
    for (var day = firstDay; day <= lastDay; day++) {
      final record = _days[day];
      if (record == null) {
        continue;
      }
      final changedAt = math.max(record.changedAt, _allChangedAt);
      if (changedAt > record.filledAt) {
        first ??= day;
        last = day;
        since = math.max(since, changedAt);
      }
    }
    if (first == null) {
      return null;
    }
    return (first: first, last: last!, since: since);
  }

  /// The read days from [first] to [last], walking the shorter of the span
  /// and the read days.
  Iterable<_Day> _readDaysIn(int first, int last) sync* {
    if (last - first < _days.length) {
      for (var day = first; day <= last; day++) {
        final record = _days[day];
        if (record != null) {
          yield record;
        }
      }
    } else {
      for (final MapEntry(key: day, value: record) in _days.entries) {
        if (day >= first && day <= last) {
          yield record;
        }
      }
    }
  }

  /// The earliest-sent read in flight covering [first] to [last] that was
  /// sent after the clock [since].
  _Read? _inFlightCovering(int first, int last, int since) {
    for (final read in _reads) {
      if (read.covers(first, last, since)) {
        return read;
      }
    }
    return null;
  }

  /// Sends the read the shown range waits on: of its [unread] days and its
  /// changed days, as one span.
  void _sendAwaited(({int first, int last}) unread) {
    final changed = _changedSpanOf(_shownFirst!, _shownLast!);
    _send(
      changed == null ? unread.first : math.min(unread.first, changed.first),
      changed == null ? unread.last : math.max(unread.last, changed.last),
      awaited: true,
    );
  }

  /// Sends a read in the background of the shown range's changed days,
  /// unless a read in flight sent since they changed covers them.
  void _readChangedShown() {
    final first = _shownFirst;
    final last = _shownLast;
    if (first == null || last == null) {
      return;
    }
    final changed = _changedSpanOf(first, last);
    if (changed == null ||
        _inFlightCovering(changed.first, changed.last, changed.since) != null) {
      return;
    }
    _send(changed.first, changed.last, awaited: false);
  }

  /// Sends a read of [first] to [last], which the shown range waits on
  /// when [awaited], and [done], if given, waits on. The shown range waits
  /// on it before the source is called, so an answer that arrives within
  /// the call, as a [SynchronousFuture]'s does, settles the range.
  void _send(
    int first,
    int last, {
    required bool awaited,
    Completer<void>? done,
  }) {
    final read = _Read(first, last, ++_clock, done);
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
  /// when it changed what the store answers, or failed. A read that
  /// answers sends the read again of the shown range's days announced
  /// changed meanwhile.
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
    final changed = answered != null && _applyRead(read, answered);
    if (_reads.isEmpty) {
      _entryTimes.clear();
    }
    var failed = false;
    if (answered == null) {
      for (var day = read.first; day <= read.last; day++) {
        if (!_days.containsKey(day) &&
            _inFlightCovering(day, day, 0) == null &&
            _failedDays.add(day)) {
          failed = true;
        }
      }
    }
    if (!identical(_awaited, read)) {
      if (changed || failed) {
        notifyListeners();
      }
    } else {
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
    if (answered != null) {
      _readChangedShown();
    }
    final done = read.done;
    if (done != null) {
      if (answered != null) {
        done.complete();
      } else {
        done.completeError(failure!);
      }
    }
  }

  /// Applies [entries], the answer of [read], and returns whether what the
  /// store answers changed.
  ///
  /// The read fills its unread days, and its read ones that no read sent
  /// later filled. Each entry it answers replaces the held one, and each
  /// held entry on a day it fills that it does not answer is forgotten,
  /// except an entry a write confirmed or a change announced since set or
  /// removed. An answered entry covering a day a read sent later filled
  /// without it is out of date there, so the days it covers here are left
  /// changed, to be read again; so are those with a change announced while
  /// the read was in flight.
  bool _applyRead(_Read read, List<CalendarEntry<T>> entries) {
    final at = read.sentAt;
    final opened = <int>[];
    final filled = <int>[];
    for (var day = read.first; day <= read.last; day++) {
      final record = _days[day];
      if (record == null) {
        _days[day] = _Day(_showCount, at);
        opened.add(day);
        filled.add(day);
      } else if (record.filledAt < at) {
        record.filledAt = at;
        filled.add(day);
      }
    }
    if (read.changedAt != 0) {
      for (var day = read.changedFirst; day <= read.changedLast; day++) {
        final record = _days[day]!;
        record.changedAt = math.max(record.changedAt, read.changedAt);
      }
    }
    _index.open(opened);
    var changed = opened.isNotEmpty;
    final answered = <String>{};
    for (final entry in entries) {
      final id = entry.id!;
      answered.add(id);
      if ((_entryTimes[id] ?? 0) > at) {
        continue;
      }
      if (_filledAfter(entry, at)) {
        final first = math.max(dayNumber(entry.start), read.first);
        final last = math.min(
          lastDayNumberOf(entry.start, entry.end),
          read.last,
        );
        for (var day = first; day <= last; day++) {
          final record = _days[day]!;
          if (record.filledAt == at) {
            record.changedAt = math.max(record.changedAt, _clock);
          }
        }
        continue;
      }
      _setTime(id, at);
      if (_index.stored(id) != entry) {
        _index.put(entry);
        changed = true;
      }
    }
    for (final day in filled) {
      for (final entry in _index.storedOn(day)) {
        final id = entry.id!;
        if (answered.contains(id) || (_entryTimes[id] ?? 0) > at) {
          continue;
        }
        _index.forget(id);
        _setTime(id, at);
        changed = true;
      }
    }
    return changed;
  }

  /// Whether a read sent after the clock [at] filled a day [entry] covers.
  bool _filledAfter(CalendarEntry<T> entry, int at) {
    final first = dayNumber(entry.start);
    final last = lastDayNumberOf(entry.start, entry.end);
    for (final record in _readDaysIn(first, last)) {
      if (record.filledAt > at) {
        return true;
      }
    }
    return false;
  }

  /// Records that what happened at the clock [at] set or removed the entry
  /// [id], while a read is in flight.
  void _setTime(String id, int at) {
    if (_reads.isNotEmpty) {
      _entryTimes[id] = at;
    }
  }

  /// Applies [change], which the source announced.
  void _applyChange(CalendarSourceChange<T> change) {
    if (_disposed) {
      return;
    }
    switch (change) {
      case CalendarEntryPut<T>(:final entry):
        _applyPut(entry);
      case CalendarEntryRemoved<T>(:final id):
        _applyRemoved(id);
      case CalendarDaysChanged<T>(:final first, :final last):
        invalidate(first, last);
      case CalendarAllChanged<T>():
        _changeAll();
    }
  }

  /// An error on the stream of changes: the store cannot tell what it
  /// missed, so every entry is taken to have changed.
  void _changesFailed(Object error) {
    if (_disposed) {
      return;
    }
    _changeAll();
  }

  /// Stores [entry], which the source announced stored, where it covers a
  /// read day or a day a read in flight covers; otherwise forgets the
  /// entry its id names, which left the days the store holds.
  void _applyPut(CalendarEntry<T> entry) {
    final id = entry.id!;
    _setTime(id, ++_clock);
    if (_coversHeldDay(entry)) {
      if (_index.stored(id) != entry) {
        _index.put(entry);
        notifyListeners();
      }
    } else if (_index.forget(id) != null) {
      notifyListeners();
    }
  }

  /// Forgets the entry [id], which the source announced removed.
  void _applyRemoved(String id) {
    _setTime(id, ++_clock);
    if (_index.forget(id) != null) {
      notifyListeners();
    }
  }

  /// Whether [entry] covers a read day or a day a read in flight covers.
  bool _coversHeldDay(CalendarEntry<T> entry) {
    final first = dayNumber(entry.start);
    final last = lastDayNumberOf(entry.start, entry.end);
    for (final read in _reads) {
      if (read.first <= last && read.last >= first) {
        return true;
      }
    }
    return _readDaysIn(first, last).isNotEmpty;
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
    final record = _days[number];
    if (record == null) {
      return false;
    }
    if (_status != CalendarLoadStatus.ready && record.shownAt >= _showCount) {
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
      _setTime(id, ++_clock);
      notifyListeners();
    }
    return created;
  }

  /// Writes [entry], whose id names a stored entry; the entry shows
  /// pending, as stored, until the data source answers. Completes with the
  /// stored entry, or fails with the source's error. It sends nothing
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
  /// data source answers. Completes with the stored entry, or fails with
  /// the source's error, the stored entry showing again. It sends nothing
  /// and fails with an [ArgumentError] for an entry with no id, with a
  /// [CalendarHoursException] when [hoursRefusalOf] refuses it, and with
  /// a [CalendarWritePendingException] on a pending entry; a move onto
  /// another entry's time is sent. An answer under another id fails with
  /// a [StateError]. An answer that arrives within the call, as a
  /// [SynchronousFuture]'s does, is stored within it.
  @override
  Future<CalendarEntry<T>> requestMove(CalendarEntry<T> requested) {
    final id = requested.id;
    if (id == null) {
      return Future<CalendarEntry<T>>.error(
        ArgumentError.value(requested, "requested", "A move needs an id."),
      );
    }
    final refusal = hoursRefusalOf(requested);
    if (refusal != null) {
      return Future<CalendarEntry<T>>.error(refusal);
    }
    if (!_lock(id, requested)) {
      return Future<CalendarEntry<T>>.error(CalendarWritePendingException(id));
    }
    return Future<CalendarEntry<T>>.sync(() {
      return _dataSource.replace(requested);
    }).then<CalendarEntry<T>>(
      (moved) {
        if (moved.id != id) {
          return _failWrite<CalendarEntry<T>>(
            id,
            StateError(
              "The data source replaced $id with an entry under ${moved.id}.",
            ),
            StackTrace.current,
          );
        }
        if (!_disposed) {
          _applyConfirmed(moved);
          notifyListeners();
        }
        return moved;
      },
      onError: (Object error, StackTrace stackTrace) {
        return _failWrite<CalendarEntry<T>>(id, error, stackTrace);
      },
    );
  }

  /// Deletes [id]: the stored entry shows pending until the data source
  /// answers, and leaves once it confirms. Completes then, or fails with
  /// the source's error, the entry showing as stored again. It sends
  /// nothing and fails with a [CalendarWritePendingException] on a
  /// pending entry.
  @override
  Future<void> requestDelete(String id) {
    if (!_lock(id, null)) {
      return Future<void>.error(CalendarWritePendingException(id));
    }
    return Future<void>.sync(() {
      return _dataSource.delete(id);
    }).then<void>(
      (_) {
        if (!_disposed) {
          _index.release(id);
          _index.forget(id);
          _setTime(id, ++_clock);
          notifyListeners();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        return _failWrite<void>(id, error, stackTrace);
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

  /// Ends the pending write on [id], which failed with [error], showing the
  /// stored entry again; returns a future that fails with [error].
  Future<R> _failWrite<R>(String id, Object error, StackTrace stackTrace) {
    if (!_disposed) {
      _index.release(id);
      notifyListeners();
    }
    return Future<R>.error(error, stackTrace);
  }

  /// Ends the pending write on [entry]'s id and stores [entry], filed
  /// under the read days it covers.
  void _applyConfirmed(CalendarEntry<T> entry) {
    _index.release(entry.id!);
    _index.put(entry);
    _setTime(entry.id!, ++_clock);
  }

  /// Stops listening to the source's changes, and completes each refresh
  /// still waiting on a read.
  @override
  void dispose() {
    _disposed = true;
    _changes?.cancel();
    for (final read in _reads) {
      read.done?.complete();
    }
    super.dispose();
  }
}
