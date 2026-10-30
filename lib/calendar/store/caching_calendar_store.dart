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

  /// The store's clock when a [CachingCalendarStore.show], a
  /// [CachingCalendarStore.retry] or a [CachingCalendarStore.refresh] last
  /// sent the read or took it over as its own; 0 while none has.
  int requestedAt = 0;

  /// The span of the read's days announced changed while it was in flight,
  /// and the clock of the latest such change; [changedAt] is 0 while none
  /// is.
  int changedFirst = 0;
  int changedLast = 0;
  int changedAt = 0;

  /// Whether the read covers [first] to [last].
  bool covers(int first, int last) {
    return this.first <= first && this.last >= last;
  }

  /// Records a change at the clock [at] on its days [first] to [last].
  void markChanged(int first, int last, int at) {
    if (changedAt == 0) {
      changedFirst = first;
      changedLast = last;
    } else {
      changedFirst = math.min(changedFirst, first);
      changedLast = math.max(changedLast, last);
    }
    changedAt = math.max(changedAt, at);
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
/// change announced since told the store otherwise. A forgotten entry that
/// also lay on read days outside the read leaves those days changed, since
/// what the source holds there is unknown. A failed read leaves its unread
/// days unread, so the next read that covers them reads them again, and
/// marks [readFailed] each of them that no read a [show], a [retry] or a
/// [refresh] asked for since it was sent covers in flight. A mark ends
/// once a read fills the day or a [show], a [retry] or a [refresh] reads
/// it, which each does with a read of its own though a read in flight
/// covers the day, since that read may fail as the last one did; a read
/// the store sends in the background, such as a [prefetch], ends a mark
/// only by filling the day, and keeps no failed read from making one. The
/// shown range's [status] follows from its days and their marks alone.
///
/// A day once read stays read. [invalidate], [refresh] and the changes the
/// source announces take a read day's entries to have changed: the day
/// still shows what the store holds, and is read again in the background,
/// at once where the shown range holds it and otherwise once a [show] or a
/// [prefetch] covers it. A background read of the shown range's changed
/// days runs from the first to the last of them that no read in flight
/// covers; a shown day changed since the read covering it was sent is
/// read once more when that read answers, so a burst of changes on a
/// shown day being read costs one more read.
///
/// A write takes its entry pending from the call until the data source
/// answers: a move or a resize shows the requested entry meanwhile, and an
/// update or a delete the stored one. A create shows nothing until the
/// source answers. A write on a pending entry sends nothing and fails
/// with a [CalendarWritePendingException], and so does one
/// [hoursRefusalOf] refuses, with a [CalendarHoursException]. The store
/// refuses no write for sharing time with another entry; a data source
/// that forbids it fails the write. A write's answer takes the entry's
/// place unless a change announced since the write was sent set or
/// removed the entry and left it other than the write's answer, or a read
/// sent since did so or answered a day the write's answer covers without
/// it: which of the two the source holds is then unknown, so the store
/// keeps what it holds and reads the days of both again. A read whose
/// answer removed the entry from days the write's answer does not cover
/// leaves that answer standing.
///
/// A call into the store, a public one or an answer that arrives later,
/// notifies its listeners once at most. A read or a write that answers
/// within the call, as a [SynchronousFuture]'s does, is applied within
/// it and notified with it, so the listeners see the call's final state.
/// A write returns a future of its own, never the data source's, whose
/// callbacks run in a later microtask than the call that ends the write,
/// so after that call has notified. A write after [dispose] sends nothing
/// and fails with a [StateError].
///
/// The store holds the source to its contract: a read answering an entry
/// with no id fails as a read does, a create answering one with no id
/// fails to its caller, and a write answered under another id than the one
/// written fails as that write fails, each with a [StateError]. A source
/// call that throws instead of failing its future fails as its future
/// would.
///
/// An entry a read, an announced change or a write's answer brings is
/// compared with the one the store holds only to tell whether it
/// changes anything: a comparison that throws, as a payload's `==` can,
/// is reported through [FlutterError.reportError] and counts as a
/// change.
class CachingCalendarStore<T> extends CalendarStore<T> {
  /// A store reading and writing through [dataSource], loading until the
  /// first [show], and applying each change [changes] announces, if given,
  /// until it is disposed: a [CalendarEntryPut] or a [CalendarEntryRemoved]
  /// is applied without a read, a [CalendarDaysChanged] is an [invalidate]
  /// of its days, and a [CalendarAllChanged], or an error on the stream, is
  /// an [invalidate] of every day.
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

  /// The store's clock, counted up by each read and write sent, write
  /// confirmed and change announced, which orders what each tells of the
  /// source, and by each read a show, a retry or a refresh takes over
  /// ([_takeOver]).
  int _clock = 0;

  /// Each read day, by [dayNumber].
  final Map<int, _Day> _days = <int, _Day>{};

  /// The clock when every entry was last taken to have changed.
  int _allChangedAt = 0;

  /// The clock of the latest-sent read that has filled a day, so a read
  /// sent before it is the only kind that checks for days filled later.
  int _newestFillAt = 0;

  /// By id, the clock of what last set or removed the entry: a read's
  /// send, a confirmed write or an announced change. Kept only while a read
  /// or a write is in flight, since whatever is sent later is newer than
  /// all of them.
  final Map<String, int> _entryTimes = <String, int>{};

  /// By id, the read whose answer removed the entry, while that is what
  /// [_entryTimes] holds for it.
  final Map<String, _Read> _forgottenBy = <String, _Read>{};

  /// By id, the clock when the write in flight on the entry was sent.
  final Map<String, int> _writesSentAt = <String, int>{};

  /// The creates in flight.
  int _creating = 0;

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
  /// fills them or a [show], a [retry] or a [refresh] reads them.
  final Set<int> _failedDays = <int>{};

  int? _shownFirst;
  int? _shownLast;

  CalendarLoadStatus _status = CalendarLoadStatus.loading;
  Object? _loadError;
  bool _disposed = false;

  /// How many [_batch] calls are under way, nested ones included.
  int _depth = 0;

  /// Whether a [_notify] came while a [_batch] call was under way, which
  /// the outermost one has yet to notify.
  bool _notifyPending = false;

  /// Follows from the shown range's days alone: ready once none of them is
  /// unread, failed while an unread one is [readFailed], and otherwise
  /// loading, as before the first [show]. A failed range stays failed
  /// while a read it did not ask for, such as a [prefetch], reads its
  /// failed days, until a [show], a [retry] or a [refresh] reads them or
  /// reads fill them.
  @override
  CalendarLoadStatus get status {
    return _status;
  }

  /// The error of the latest read whose failure marked a day of the shown
  /// range [readFailed], as the data source failed it, while [status] is
  /// failed; null otherwise.
  @override
  Object? get loadError {
    return _loadError;
  }

  /// Shows [first] to [last], both inclusive. A range whose days are all
  /// read is ready at once; otherwise it is loading. Where no read in
  /// flight covers its unread days, the show sends one read of them and of
  /// its changed days. Where one does, the show takes that read over as
  /// its own, and reads the range's [readFailed] days again with a read of
  /// its own, as [retry] does, since the read in flight may fail as the
  /// last one did. Changed days of the range that no read in flight covers
  /// are read again too, in one read with those [readFailed] days, and the
  /// range does not wait on them. The show ends the [readFailed] mark of
  /// each day it reads.
  /// A read the source answers within the call, as a [SynchronousFuture]'s
  /// does, is applied within it, so the call can leave the range ready, or
  /// failed where such a read failed and left a day of it unread with no
  /// read asked for since in flight. Showing the range already shown
  /// changes nothing, and so does a show after [dispose].
  @override
  void show(DateTime first, DateTime last) {
    final firstDay = dayNumber(first);
    final lastDay = dayNumber(last);
    if (_disposed || (firstDay == _shownFirst && lastDay == _shownLast)) {
      return;
    }
    _batch(() {
      _shownFirst = firstDay;
      _shownLast = lastDay;
      _showCount++;
      ({int first, int last})? failed;
      final unread = _unreadSpan();
      if (unread != null) {
        final covering = _inFlightCovering(unread.first, unread.last);
        if (covering == null) {
          _readShown(unread);
        } else {
          _takeOver(covering);
          failed = _failedSpanOf(unread.first, unread.last);
        }
      }
      _readChangedShown(requested: true, failed: failed);
      _settleStatus();
      _notify();
    });
  }

  /// Whether [day] is read. A changed day stays read.
  @override
  bool isRead(DateTime day) {
    return _days.containsKey(dayNumber(day));
  }

  /// Whether a read of [day], which is unread, failed while no read a
  /// [show], a [retry] or a [refresh] asked for since it was sent was in
  /// flight over it, and neither a read has filled it nor a [show], a
  /// [retry] or a [refresh] has read it since. A read the store sends in
  /// the background, as a [prefetch] or the read of changed days does,
  /// leaves the mark until it fills the day.
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

  /// Ends the [readFailed] mark of each day of the shown range and, where
  /// given, of each day from [first] to [last], both inclusive, and reads
  /// each of the two ranges again: the days whose marks it ends, though a
  /// read in flight covers them, since that read may fail as the last one
  /// did; and the rest of their unread and changed days as [prefetch] does,
  /// except that a read in flight that covers the unread ones is taken over
  /// as the retry's own, with no second read sent. Where the spans the two
  /// ranges leave to read overlap or touch, they are sent as one read, and
  /// otherwise as one each. [first] after [last] gives no day, as for
  /// [prefetch]. With no shown range it covers the given days alone, and
  /// with neither it does nothing. A failed shown range is failed no longer
  /// once no day of it is left [readFailed]. Notifies once where it ends a
  /// mark or changes [status], and once in all where the source answers
  /// within the call, as a [SynchronousFuture]'s does. Throws an
  /// [ArgumentError] where one of [first] and [last] is given without the
  /// other. Does nothing after [dispose].
  @override
  void retry([DateTime? first, DateTime? last]) {
    if ((first == null) != (last == null)) {
      throw ArgumentError("A retry takes both first and last, or neither.");
    }
    if (_disposed) {
      return;
    }
    _batch(() {
      final shownFirst = _shownFirst;
      final shownLast = _shownLast;
      var ended = false;
      ({int first, int last})? shownSpan;
      if (shownFirst != null && shownLast != null) {
        shownSpan = _retrySpan(shownFirst, shownLast);
        ended = _endFailed(shownFirst, shownLast);
      }
      ({int first, int last})? givenSpan;
      if (first != null && last != null) {
        final firstDay = dayNumber(first);
        final lastDay = dayNumber(last);
        givenSpan = _retrySpan(firstDay, lastDay);
        ended = _endFailed(firstDay, lastDay) || ended;
      }
      if (shownSpan != null &&
          givenSpan != null &&
          shownSpan.first <= givenSpan.last + 1 &&
          givenSpan.first <= shownSpan.last + 1) {
        _send(
          math.min(shownSpan.first, givenSpan.first),
          math.max(shownSpan.last, givenSpan.last),
          requested: true,
        );
      } else {
        if (shownSpan != null) {
          _send(shownSpan.first, shownSpan.last, requested: true);
        }
        if (givenSpan != null) {
          _send(givenSpan.first, givenSpan.last, requested: true);
        }
      }
      if (_settleStatus() || ended) {
        _notify();
      }
    });
  }

  /// Reads the unread and the changed days from [first] to [last], both
  /// inclusive, without showing them, so the markers of days about to show
  /// appear once read. Sends nothing where a read in flight covers them,
  /// and nothing after [dispose]. Changes no shown range. It reads the days
  /// in the background: it leaves each [readFailed] mark until its read
  /// fills the day, and notifies nothing itself, so a failed shown range
  /// stays failed while it reads the range's failed days. Its read counts
  /// toward [status] once it answers, as any read does: one leaving the
  /// shown range with no unread day makes it ready, and a failed one leaves
  /// its unread days unread and marks [readFailed] those that no read a
  /// [show], a [retry] or a [refresh] asked for since covers in flight,
  /// which makes a shown range holding one failed.
  @override
  void prefetch(DateTime first, DateTime last) {
    if (_disposed) {
      return;
    }
    final span = _spanToRead(dayNumber(first), dayNumber(last));
    if (span != null) {
      _send(span.first, span.last);
    }
  }

  /// Takes the entries on the days from [first] to [last], both inclusive,
  /// to have changed. Each read day of them still shows what the store
  /// holds, and is read again: at once where the shown range holds it, and
  /// otherwise once a [show] or a [prefetch] covers it. A read in flight
  /// over them leaves them changed once it answers. It notifies nothing
  /// itself: a read it sends notifies once it changes what the store
  /// answers, within the call where the source answers within it. Does
  /// nothing after [dispose].
  @override
  void invalidate(DateTime first, DateTime last) {
    final firstDay = dayNumber(first);
    final lastDay = dayNumber(last);
    if (_disposed || firstDay > lastDay) {
      return;
    }
    _markChanged(firstDay, lastDay, ++_clock);
    _readChangedShown();
  }

  /// Takes every entry to have changed, as [invalidate] does for every
  /// day, and reads the whole shown range again at once, ending the
  /// [readFailed] mark of each of its days, so a failed shown range is
  /// loading again, as after [retry], unless the source answers that read
  /// within the call, as for [show]. A range whose days are all read
  /// stays ready, and a failed read leaves its days changed. Completes
  /// once that read answers, or fails with the error it failed with;
  /// completes at once before the first [show] and after [dispose], and
  /// when the store is disposed before the read answers.
  @override
  Future<void> refresh() {
    if (_disposed) {
      return Future<void>.value();
    }
    _allChangedAt = ++_clock;
    final first = _shownFirst;
    final last = _shownLast;
    if (first == null || last == null) {
      return Future<void>.value();
    }
    final done = Completer<void>();
    _batch(() {
      final ended = _endFailed(first, last);
      _send(first, last, done: done, requested: true);
      if (_settleStatus() || ended) {
        _notify();
      }
    });
    return done.future;
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

  /// The first to the last changed day from [firstDay] to [lastDay], or
  /// null when none is; with [uncovered], of those that no read in flight
  /// covers. A changed day is a read day with a change announced on it
  /// since the read that last filled it was sent.
  ({int first, int last})? _changedSpanOf(
    int firstDay,
    int lastDay, {
    bool uncovered = false,
  }) {
    int? first;
    int? last;
    for (var day = firstDay; day <= lastDay; day++) {
      final record = _days[day];
      if (record == null) {
        continue;
      }
      if (math.max(record.changedAt, _allChangedAt) > record.filledAt &&
          !(uncovered && _inFlightCovering(day, day) != null)) {
        first ??= day;
        last = day;
      }
    }
    if (first == null) {
      return null;
    }
    return (first: first, last: last!);
  }

  /// The span a [prefetch] of [firstDay] to [lastDay] reads: from the
  /// first to the last of their unread days and their changed days,
  /// leaving out the unread ones, or the changed ones, where a read in
  /// flight covers all of them; null when that leaves nothing to read.
  /// Where [takeOver], the read in flight that covers the unread ones is
  /// taken over as the caller's own ([_takeOver]).
  ({int first, int last})? _spanToRead(
    int firstDay,
    int lastDay, {
    bool takeOver = false,
  }) {
    int? from;
    int? to;
    final unread = _unreadSpanOf(firstDay, lastDay);
    if (unread != null) {
      final covering = _inFlightCovering(unread.first, unread.last);
      if (covering == null) {
        from = unread.first;
        to = unread.last;
      } else if (takeOver) {
        _takeOver(covering);
      }
    }
    final changed = _changedSpanOf(firstDay, lastDay);
    if (changed != null &&
        _inFlightCovering(changed.first, changed.last) == null) {
      from = math.min(from ?? changed.first, changed.first);
      to = math.max(to ?? changed.last, changed.last);
    }
    if (from == null || to == null) {
      return null;
    }
    return (first: from, last: to);
  }

  /// The span a [retry] of [firstDay] to [lastDay] reads: from the first
  /// to the last of their [readFailed] days, which it reads though a read
  /// in flight covers them ([_failedSpanOf]), and of the days
  /// [_spanToRead] leaves to read, taking over the read in flight that
  /// covers the unread days it leaves out; null when that leaves nothing
  /// to read. Called before the retry ends the marks.
  ({int first, int last})? _retrySpan(int firstDay, int lastDay) {
    return _joined(
      _failedSpanOf(firstDay, lastDay),
      _spanToRead(firstDay, lastDay, takeOver: true),
    );
  }

  /// The first to the last [readFailed] day from [firstDay] to [lastDay],
  /// or null when none is, walking the shorter of the span and the marked
  /// days.
  ({int first, int last})? _failedSpanOf(int firstDay, int lastDay) {
    int? from;
    int? to;
    void take(int day) {
      if (day >= firstDay && day <= lastDay) {
        from = math.min(from ?? day, day);
        to = math.max(to ?? day, day);
      }
    }

    if (lastDay - firstDay < _failedDays.length) {
      for (var day = firstDay; day <= lastDay; day++) {
        if (_failedDays.contains(day)) {
          take(day);
        }
      }
    } else {
      _failedDays.forEach(take);
    }
    final spanFirst = from;
    final spanLast = to;
    if (spanFirst == null || spanLast == null) {
      return null;
    }
    return (first: spanFirst, last: spanLast);
  }

  /// The span from the first to the last day of [a] and [b], either of
  /// which may be null; null when both are.
  ({int first, int last})? _joined(
    ({int first, int last})? a,
    ({int first, int last})? b,
  ) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return (first: math.min(a.first, b.first), last: math.max(a.last, b.last));
  }

  /// Takes [read] over as the own read of a [show], a [retry] or a
  /// [refresh] asked now, at a new tick of the clock, so a read sent
  /// before now that fails marks no day [read] covers ([_requestedSince]).
  void _takeOver(_Read read) {
    read.requestedAt = ++_clock;
  }

  /// Ends the [readFailed] mark of each day from [first] to [last], and
  /// returns whether one had it.
  bool _endFailed(int first, int last) {
    if (_failedDays.isEmpty || first > last) {
      return false;
    }
    final before = _failedDays.length;
    _failedDays.removeWhere((day) {
      return day >= first && day <= last;
    });
    return _failedDays.length != before;
  }

  /// The [dayNumber]s of the read days from [first] to [last], walking the
  /// shorter of the span and the read days.
  Iterable<int> _readDaysIn(int first, int last) sync* {
    if (last - first < _days.length) {
      for (var day = first; day <= last; day++) {
        if (_days.containsKey(day)) {
          yield day;
        }
      }
    } else {
      for (final day in _days.keys) {
        if (day >= first && day <= last) {
          yield day;
        }
      }
    }
  }

  /// Marks changed at the clock [at] the days [entry] covers
  /// ([_markChanged]), except those of [except], if given.
  void _markDaysOf(CalendarEntry<T> entry, int at, {_Read? except}) {
    final first = dayNumber(entry.start);
    final last = lastDayNumberOf(entry.start, entry.end);
    if (except == null) {
      _markChanged(first, last, at);
      return;
    }
    if (first < except.first) {
      _markChanged(first, math.min(last, except.first - 1), at);
    }
    if (last > except.last) {
      _markChanged(math.max(first, except.last + 1), last, at);
    }
  }

  /// Marks changed at the clock [at] the read days from [first] to [last],
  /// and those days of each read in flight, so a read sent before [at]
  /// leaves the days it fills changed.
  void _markChanged(int first, int last, int at) {
    for (final day in _readDaysIn(first, last)) {
      final record = _days[day]!;
      record.changedAt = math.max(record.changedAt, at);
    }
    for (final read in _reads) {
      if (read.first <= last && read.last >= first) {
        read.markChanged(
          math.max(first, read.first),
          math.min(last, read.last),
          at,
        );
      }
    }
  }

  /// Whether the shown range holds [day], a [dayNumber].
  bool _shows(int day) {
    final first = _shownFirst;
    final last = _shownLast;
    return first != null && last != null && first <= day && day <= last;
  }

  /// Whether a read in flight over [day] was sent or taken over by a
  /// [show], a [retry] or a [refresh] after [read] was sent.
  bool _requestedSince(_Read read, int day) {
    for (final other in _reads) {
      if (other.requestedAt > read.sentAt &&
          other.first <= day &&
          day <= other.last) {
        return true;
      }
    }
    return false;
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

  /// Sends a read of the shown range's [unread] days and its changed days,
  /// as one span, which a [show] asked for, so it ends the [readFailed]
  /// marks over that span.
  void _readShown(({int first, int last}) unread) {
    final changed = _changedSpanOf(_shownFirst!, _shownLast!);
    final first = changed == null
        ? unread.first
        : math.min(unread.first, changed.first);
    final last = changed == null
        ? unread.last
        : math.max(unread.last, changed.last);
    _endFailed(first, last);
    _send(first, last, requested: true);
  }

  /// Sends a read from the first to the last of the shown range's changed
  /// days that no read in flight covers and, where given, of [failed], the
  /// span of the shown range's [readFailed] days a [show] reads though a
  /// read in flight covers them: in the background, or where [requested],
  /// as a [show]'s own read, which ends the [readFailed] marks over its
  /// span.
  void _readChangedShown({
    bool requested = false,
    ({int first, int last})? failed,
  }) {
    final first = _shownFirst;
    final last = _shownLast;
    if (first == null || last == null) {
      return;
    }
    final span = _joined(_changedSpanOf(first, last, uncovered: true), failed);
    if (span == null) {
      return;
    }
    if (requested) {
      _endFailed(span.first, span.last);
    }
    _send(span.first, span.last, requested: requested);
  }

  /// Sets [status] from the shown range's days, and returns whether it or
  /// [loadError] changed: ready once none is unread; failed once an
  /// unread one is [readFailed]; and otherwise loading. [failure], the
  /// error of a read that just marked a day of the range [readFailed], is
  /// [loadError] while the range is failed, which otherwise keeps the
  /// latest such error.
  bool _settleStatus({Object? failure}) {
    final first = _shownFirst;
    final last = _shownLast;
    if (first == null || last == null) {
      return false;
    }
    var status = CalendarLoadStatus.ready;
    for (var day = first; day <= last; day++) {
      if (!_days.containsKey(day)) {
        if (_failedDays.contains(day)) {
          status = CalendarLoadStatus.failed;
          break;
        }
        status = CalendarLoadStatus.loading;
      }
    }
    final error = status == CalendarLoadStatus.failed
        ? failure ?? _loadError
        : null;
    if (status == _status && identical(error, _loadError)) {
      return false;
    }
    _status = status;
    _loadError = error;
    return true;
  }

  /// Runs [body] as one call into the store. A [_notify] while a [_batch]
  /// call is under way is left to the outermost one, which notifies once
  /// as it ends if any came.
  R _batch<R>(R Function() body) {
    _depth++;
    try {
      return body();
    } finally {
      _depth--;
      if (_depth == 0 && _notifyPending) {
        _notifyPending = false;
        // [body] can dispose the store, as a data source's write can from
        // within its call, after which [notifyListeners] throws in debug
        // builds.
        if (!_disposed) {
          notifyListeners();
        }
      }
    }
  }

  /// Notes that what the store answers changed: the outermost [_batch]
  /// call under way notifies as it ends, and with none under way this
  /// notifies at once.
  void _notify() {
    if (_depth > 0) {
      _notifyPending = true;
    } else {
      notifyListeners();
    }
  }

  /// Sends a read of [first] to [last], which [done], if given, waits on,
  /// and which a [show], a [retry] or a [refresh] asked for where
  /// [requested]. It ends no [readFailed] mark: a [show], a [retry] or a
  /// [refresh] ends the marks of the days it reads itself. The read is in
  /// flight before the source is called, so an answer that arrives within
  /// the call, as a [SynchronousFuture]'s does, finishes it.
  void _send(
    int first,
    int last, {
    Completer<void>? done,
    bool requested = false,
  }) {
    final read = _Read(first, last, ++_clock, done);
    if (requested) {
      read.requestedAt = read.sentAt;
    }
    _reads.add(read);
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

  /// A read's answer. One that answers ends the [readFailed] mark of each
  /// day it fills, and sends the read again of the shown range's days
  /// announced changed meanwhile. A failed one marks [readFailed] each of
  /// its days that no read has filled and that no read a [show], a [retry]
  /// or a [refresh] asked for since it was sent covers in flight
  /// ([_requestedSince]), whatever a read in flight in the background will
  /// answer; a day marked already stays as it was. It notifies when it
  /// changed [status], what the store answers, or [readFailed].
  void _finishRead(
    _Read read, {
    List<CalendarEntry<T>>? entries,
    Object? error,
  }) {
    if (_disposed) {
      return;
    }
    _batch(() {
      _applyAnswer(read, entries: entries, error: error);
    });
  }

  /// The body of [_finishRead], in one call into the store.
  void _applyAnswer(
    _Read read, {
    List<CalendarEntry<T>>? entries,
    Object? error,
  }) {
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
    _pruneEntryTimes();
    var failed = false;
    var failedShown = false;
    if (answered == null) {
      for (var day = read.first; day <= read.last; day++) {
        if (!_days.containsKey(day) &&
            !_requestedSince(read, day) &&
            _failedDays.add(day)) {
          failed = true;
          failedShown = failedShown || _shows(day);
        }
      }
    }
    final settled = _settleStatus(failure: failedShown ? failure : null);
    if (settled || changed || failed) {
      _notify();
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
  /// removed. A forgotten entry leaves changed the read days it covers
  /// outside the read. An answered entry covering a day a read sent later
  /// filled without it is out of date there, so the days it covers here are
  /// left changed, to be read again; so are those with a change announced
  /// while the read was in flight.
  bool _applyRead(_Read read, List<CalendarEntry<T>> entries) {
    final at = read.sentAt;
    final opened = <int>[];
    final filled = <int>[];
    for (var day = read.first; day <= read.last; day++) {
      final record = _days[day];
      if (record == null) {
        _days[day] = _Day(_showCount, at);
        _failedDays.remove(day);
        opened.add(day);
        filled.add(day);
      } else if (record.filledAt < at) {
        record.filledAt = at;
        filled.add(day);
      }
    }
    if (filled.isNotEmpty) {
      _newestFillAt = math.max(_newestFillAt, at);
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
    final updated = <CalendarEntry<T>>[];
    for (final entry in entries) {
      final id = entry.id!;
      answered.add(id);
      if ((_entryTimes[id] ?? 0) > at) {
        continue;
      }
      if (_newestFillAt > at && _filledAfter(entry, at)) {
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
      if (_differs(_index.stored(id), entry)) {
        updated.add(entry);
      }
    }
    if (updated.isNotEmpty) {
      _index.putAll(updated);
      changed = true;
    }
    for (final day in filled) {
      for (final entry in _index.storedOn(day)) {
        final id = entry.id!;
        if (answered.contains(id) || (_entryTimes[id] ?? 0) > at) {
          continue;
        }
        _index.forget(id);
        _setTime(id, at, forgottenBy: read);
        _markDaysOf(entry, at, except: read);
        changed = true;
      }
    }
    return changed;
  }

  /// Whether [entry] differs from [held], the entry the store holds under
  /// its id, as `!=` answers. The store compares the two only to tell
  /// whether [entry] changes what it holds, so where comparing them
  /// throws, as a payload's `==` can, the throw is reported through
  /// [FlutterError.reportError] and [entry] counts as a change, rather
  /// than leave a read, an announced change or a write half applied.
  bool _differs(CalendarEntry<T>? held, CalendarEntry<T>? entry) {
    try {
      return held != entry;
    } on Object catch (exception, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: "widgets_extended calendar",
          context: ErrorDescription("while comparing calendar entries"),
        ),
      );
      return true;
    }
  }

  /// Whether a read sent after the clock [at] filled a day [entry] covers.
  bool _filledAfter(CalendarEntry<T> entry, int at) {
    final first = dayNumber(entry.start);
    final last = lastDayNumberOf(entry.start, entry.end);
    for (final day in _readDaysIn(first, last)) {
      if (_days[day]!.filledAt > at) {
        return true;
      }
    }
    return false;
  }

  /// Whether a read or a write is in flight, which [_entryTimes] is kept
  /// for.
  bool get _inFlight {
    return _reads.isNotEmpty || _writesSentAt.isNotEmpty || _creating > 0;
  }

  /// Records that what happened at the clock [at] set or removed the entry
  /// [id], while a read or a write is in flight: the answer of the read
  /// [forgottenBy], if given, removed it.
  void _setTime(String id, int at, {_Read? forgottenBy}) {
    if (!_inFlight) {
      return;
    }
    _entryTimes[id] = at;
    if (forgottenBy == null) {
      _forgottenBy.remove(id);
    } else {
      _forgottenBy[id] = forgottenBy;
    }
  }

  /// Drops [_entryTimes] once no read or write is in flight.
  void _pruneEntryTimes() {
    if (!_inFlight) {
      _entryTimes.clear();
      _forgottenBy.clear();
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

  /// Takes every entry to have changed, and reads the shown range's read
  /// days again.
  void _changeAll() {
    _allChangedAt = ++_clock;
    _readChangedShown();
  }

  /// Stores [entry], which the source announced stored, where it covers a
  /// read day or a day a read in flight covers; otherwise forgets the
  /// entry its id names, which left the days the store holds.
  void _applyPut(CalendarEntry<T> entry) {
    final id = entry.id!;
    _setTime(id, ++_clock);
    if (_coversHeldDay(entry)) {
      if (_differs(_index.stored(id), entry)) {
        _index.put(entry);
        _notify();
      }
    } else if (_index.forget(id) != null) {
      _notify();
    }
  }

  /// Forgets the entry [id], which the source announced removed.
  void _applyRemoved(String id) {
    _setTime(id, ++_clock);
    if (_index.forget(id) != null) {
      _notify();
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
  /// source answers, and an answer that arrives within the call, as a
  /// [SynchronousFuture]'s does, is stored within it. It sends nothing
  /// and fails with a [StateError] after [dispose], and with a
  /// [CalendarHoursException] for a draft outside [hours]. An answer with
  /// no id fails with a [StateError] and stores nothing; one whose id has
  /// a write in flight, as after a read that brought the entry and a move
  /// of it, completes and changes nothing.
  @override
  Future<CalendarEntry<T>> create(CalendarEntry<T> draft) {
    if (_disposed) {
      return _refuse(_disposedError());
    }
    final refusal = hoursRefusalOf(draft);
    if (refusal != null) {
      return _refuse(refusal);
    }
    return _write<CalendarEntry<T>, CalendarEntry<T>>(
      send: () {
        return _dataSource.create(draft);
      },
      store: (created, sentAt) {
        final id = created.id;
        if (id == null) {
          throw StateError("The data source created an entry with no id.");
        }
        if (!_disposed && !_index.isPending(id)) {
          _storeAnswer(id, created, sentAt);
          _notify();
        }
        return created;
      },
    );
  }

  /// Writes [entry], whose id names a stored entry; the entry shows
  /// pending, as stored, until the data source answers. Completes with the
  /// stored entry, or fails with the source's error. It sends nothing
  /// and fails with a [StateError] after [dispose], with an
  /// [ArgumentError] for an entry with no id, with a
  /// [CalendarHoursException] when [hoursRefusalOf] refuses it, and with
  /// a [CalendarWritePendingException] on a pending entry. An answer under
  /// another id fails with a [StateError], the entry showing as stored
  /// again. An answer that arrives within the call, as a
  /// [SynchronousFuture]'s does, is stored within it.
  @override
  Future<CalendarEntry<T>> update(CalendarEntry<T> entry) {
    final id = entry.id;
    if (_disposed) {
      return _refuse(_disposedError());
    }
    if (id == null) {
      return _refuse(
        ArgumentError.value(entry, "entry", "An update needs an id."),
      );
    }
    final refusal = hoursRefusalOf(entry);
    if (refusal != null) {
      return _refuse(refusal);
    }
    return _write<CalendarEntry<T>, CalendarEntry<T>>(
      lock: id,
      send: () {
        return _dataSource.replace(entry);
      },
      store: (updated, sentAt) {
        return _storeReplaced(id, updated, sentAt);
      },
    );
  }

  /// Writes a grid move or resize: [requested] shows, pending, until the
  /// data source answers. Completes with the stored entry, or fails with
  /// the source's error, the stored entry showing again. It sends nothing
  /// and fails with a [StateError] after [dispose], with an
  /// [ArgumentError] for an entry with no id, with a
  /// [CalendarHoursException] when [hoursRefusalOf] refuses it, and with
  /// a [CalendarWritePendingException] on a pending entry; a move onto
  /// another entry's time is sent. An answer under another id fails with
  /// a [StateError]. An answer that arrives within the call, as a
  /// [SynchronousFuture]'s does, is stored within it.
  @override
  Future<CalendarEntry<T>> requestMove(CalendarEntry<T> requested) {
    final id = requested.id;
    if (_disposed) {
      return _refuse(_disposedError());
    }
    if (id == null) {
      return _refuse(
        ArgumentError.value(requested, "requested", "A move needs an id."),
      );
    }
    final refusal = hoursRefusalOf(requested);
    if (refusal != null) {
      return _refuse(refusal);
    }
    return _write<CalendarEntry<T>, CalendarEntry<T>>(
      lock: id,
      shown: requested,
      send: () {
        return _dataSource.replace(requested);
      },
      store: (moved, sentAt) {
        return _storeReplaced(id, moved, sentAt);
      },
    );
  }

  /// Deletes [id]: the stored entry shows pending until the data source
  /// answers, and leaves once it confirms. Completes then, or fails with
  /// the source's error, the entry showing as stored again. It sends
  /// nothing and fails with a [StateError] after [dispose], and with a
  /// [CalendarWritePendingException] on a pending entry. An answer that
  /// arrives within the call, as a [SynchronousFuture]'s does, is stored
  /// within it.
  @override
  Future<void> requestDelete(String id) {
    if (_disposed) {
      return _refuse(_disposedError());
    }
    return _write<void, void>(
      lock: id,
      send: () {
        return _dataSource.delete(id);
      },
      store: (_, sentAt) {
        if (!_disposed) {
          _storeAnswer(id, null, sentAt);
        }
      },
    );
  }

  /// Runs a write in one call into the store ([_batch]), and returns a
  /// [Completer]'s future, never the data source's own, whose callbacks
  /// run in a later microtask than the call that ends the write.
  ///
  /// The write marks [lock] pending, showing [shown] ([_lock]), or
  /// counts toward [_creating] for a create, which locks nothing. [send]
  /// then calls the data source, and [store] takes its answer and the
  /// clock the write was sent at, stores the answer unless the store is
  /// disposed, and gives what the future completes with. [send]'s future
  /// is listened to within the call, so an answer that arrives within it,
  /// as a [SynchronousFuture]'s does, is stored within it. Where [send]
  /// throws, its future fails or [store] throws, the write ends and the
  /// future fails with that error, a throw within the call ending the
  /// write within it. A write ends, releasing [lock] and notifying,
  /// before its future's callbacks run. A write on a pending [lock] sends
  /// nothing and fails with a [CalendarWritePendingException].
  Future<R> _write<A, R>({
    String? lock,
    CalendarEntry<T>? shown,
    required Future<A> Function() send,
    required R Function(A answer, int sentAt) store,
  }) {
    final done = Completer<R>();
    _batch(() {
      final int sentAt;
      if (lock == null) {
        sentAt = ++_clock;
        _creating++;
      } else if (_lock(lock, shown)) {
        sentAt = _writesSentAt[lock]!;
      } else {
        done.completeError(
          CalendarWritePendingException(lock),
          StackTrace.current,
        );
        return;
      }

      void fail(Object error, StackTrace stackTrace) {
        _endWrite(lock);
        done.completeError(error, stackTrace);
      }

      // Only the first answer or failure of [send]'s future is heard, so
      // the write ends once, whatever that future does, even where it
      // answers again from within [store].
      var heard = false;

      void answered(A answer) {
        if (heard) {
          return;
        }
        heard = true;
        _batch(() {
          final R value;
          try {
            value = store(answer, sentAt);
          } on Object catch (error, stackTrace) {
            fail(error, stackTrace);
            return;
          }
          _endWrite(lock);
          done.complete(value);
        });
      }

      void failed(Object error, StackTrace stackTrace) {
        if (heard) {
          return;
        }
        heard = true;
        _batch(() {
          fail(error, stackTrace);
        });
      }

      try {
        send().then<void>(answered, onError: failed);
      } on Object catch (error, stackTrace) {
        failed(error, stackTrace);
      }
    });
    return done.future;
  }

  /// Ends the write on [lock], showing the stored entry again and
  /// notifying, or for a null [lock], a create's, ends its count in
  /// [_creating].
  void _endWrite(String? lock) {
    if (lock == null) {
      _creating--;
      _pruneEntryTimes();
    } else {
      _release(lock);
      _notify();
    }
  }

  /// A future failing with [error], a refused write's, with the stack
  /// trace of the call that refused it.
  Future<R> _refuse<R>(Object error) {
    return Future<R>.error(error, StackTrace.current);
  }

  /// The error of a write after [dispose].
  StateError _disposedError() {
    return StateError("A disposed store sends no write.");
  }

  /// Marks [id] pending, showing [shown] or, when null, the stored entry.
  /// False, changing nothing, when [id] is pending already: every update,
  /// move and delete passes here ([_write]), so an id has one write in
  /// flight at most.
  bool _lock(String id, CalendarEntry<T>? shown) {
    if (!_index.lock(id, shown)) {
      return false;
    }
    _writesSentAt[id] = ++_clock;
    _notify();
    return true;
  }

  /// Ends the pending write on [id].
  void _release(String id) {
    _index.release(id);
    _writesSentAt.remove(id);
    _pruneEntryTimes();
  }

  /// Stores [answer], what the data source replaced [id] with for a write
  /// sent at the clock [sentAt] ([_storeAnswer]), unless the store is
  /// disposed, and returns it; throws a [StateError] for an answer under
  /// another id.
  CalendarEntry<T> _storeReplaced(
    String id,
    CalendarEntry<T> answer,
    int sentAt,
  ) {
    if (answer.id != id) {
      throw StateError(
        "The data source replaced $id with an entry under ${answer.id}.",
      );
    }
    if (!_disposed) {
      _storeAnswer(id, answer, sentAt);
    }
    return answer;
  }

  /// Stores [answer], what a write sent at the clock [sentAt] left under
  /// [id], or forgets the entry for a null [answer], a delete's; unless it
  /// differs from the entry held and a change announced or a read sent
  /// since contradicts it ([_contradicted]). Which of the two the source
  /// holds is then unknown, so the store keeps what it holds and reads the
  /// days of both again.
  void _storeAnswer(String id, CalendarEntry<T>? answer, int sentAt) {
    final held = _index.stored(id);
    if (_differs(held, answer) && _contradicted(id, answer, sentAt)) {
      final at = ++_clock;
      if (held != null) {
        _markDaysOf(held, at);
      }
      if (answer != null) {
        _markDaysOf(answer, at);
      }
      _readChangedShown();
      return;
    }
    if (answer == null) {
      _index.forget(id);
    } else {
      _index.put(answer);
    }
    _setTime(id, ++_clock);
  }

  /// Whether a change announced since the clock [sentAt], or a read sent
  /// since, contradicts [answer], a write's answer under [id] other than
  /// the entry held: the change or the read's answer set or removed the
  /// entry, unless the latest to do so was a read whose answer removed it
  /// from days [answer] does not cover; or the read filled a day [answer]
  /// covers, and so left the entry other than [answer] there.
  bool _contradicted(String id, CalendarEntry<T>? answer, int sentAt) {
    if ((_entryTimes[id] ?? 0) > sentAt && !_removedElsewhere(id, answer)) {
      return true;
    }
    return answer != null && _filledAfter(answer, sentAt);
  }

  /// Whether the latest to set or remove the entry [id] was a read whose
  /// answer removed it, over days [answer] does not cover.
  bool _removedElsewhere(String id, CalendarEntry<T>? answer) {
    final read = _forgottenBy[id];
    if (read == null || answer == null) {
      return false;
    }
    final first = dayNumber(answer.start);
    final last = lastDayNumberOf(answer.start, answer.end);
    return last < read.first || first > read.last;
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
