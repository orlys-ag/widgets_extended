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

/// One `read` call in flight, over the store's own [CalendarDates.dayNumber]s
/// [first] to [last], on the clock the store reads, whatever device days the
/// data source is asked for.
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

  /// Whether a zone change has marked this read, sent under another zone,
  /// so its answer or failure applies nothing and completes nothing.
  bool stale = false;

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

/// What last set or removed an entry, while a read or a write is in flight
/// ([CachingCalendarStore._setTime]).
@immutable
class _EntryTime {
  const _EntryTime(
    this.at, {
    this.forgottenBy,
    this.checksReadsAfter,
    this.beneath,
  });

  /// The store's clock of what last set or removed the entry: a read's
  /// send, a confirmed write or an announced change.
  final int at;

  /// The read whose answer removed the entry, where that is what [at]
  /// stamps.
  final _Read? forgottenBy;

  /// Where [at] stamps a write's answer, the store's clock after which a
  /// read sent before [at] is checked against the entry the store holds:
  /// the write's send where the store holds the answer, and otherwise the
  /// later of that and the clock of what set the entry it kept.
  final int? checksReadsAfter;

  /// Where [forgottenBy] removed the entry, the latest stamp before that
  /// removal of what else set or removed it: a read sent before it that
  /// answers the entry is still superseded by that stamp, or checked
  /// against it, as before the removal. Never itself a removal by a read,
  /// so no chain runs deeper than one.
  final _EntryTime? beneath;
}

/// The failure that marked a day [CachingCalendarStore.readFailed]: the
/// [error] the read failed with, and the [order] of that failure among the
/// store's failed reads.
typedef _Mark = ({Object error, int order});

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
/// flight. A zone change can leave a day open and unread: its entries are
/// answered, it reports [isRead] and [dayHasShownEntries] false, and an
/// announced put on it is filed, until a read fills it.
///
/// A read's answer is what the source stored on the read's days when it
/// was sent. It replaces what the store holds there: each entry it answers
/// takes the place of the held one, and each held entry it does not answer
/// is forgotten, except where a later read, a write confirmed since or a
/// change announced since told the store otherwise. A forgotten entry that
/// also lay on read days outside the read leaves those days changed, since
/// what the source holds there is unknown. A failed read leaves its unread
/// days unread, so the next read that covers them reads them again, and
/// marks [readFailed] each of them, and each of its read days taken to
/// have changed since the read that last filled it, that no read a
/// [show], a [retry] or a [refresh] asked for since it was sent covers in
/// flight; the read a refresh waits on marks only its unread days, since
/// its failure fails the refresh. A mark ends
/// once a read fills the day or a [show], a [retry] or a [refresh] reads
/// it, which each does with a read of its own though a read in flight
/// covers the day, since that read may fail as the last one did, and at
/// a zone change, which ends every mark; a read
/// the store sends in the background, such as a [prefetch], ends a mark
/// only by filling the day, and keeps no failed read from making one. The
/// shown range's [status] and [loadError] follow from its days and their
/// marks alone: a mark keeps the error of the failure that made it, and
/// [loadError] is the latest such error on the range's days.
///
/// A day once read stays read, except that a zone change re-keys the read
/// days to those its earlier reads fully cover under the new zone, each read
/// again in the background. Given a [readAhead], a [show] and a [retry]
/// also read the unread days that many days before the shown range and
/// after it, in the same read, while [status] and [loadError] follow the
/// shown range alone. A host whose users switch zones sets a [readAhead] of
/// 2, which keeps the shown days read across a change between any two
/// zones once the store's reads have answered, the last zone change's
/// re-reads included. [invalidate], [refresh], a zone change and the
/// changes the source announces take a read day's entries to have
/// changed: the day still shows what the store holds, and is read again in
/// the background, at once where the shown range holds it and otherwise
/// once a [show] or a [prefetch] covers it. Where that read fails, the day
/// is marked [readFailed] as above, so a shown range holding it is failed
/// rather than ready with what the source may no longer hold, until a
/// read fills the day or a [show], a [retry] or a [refresh] reads it. So
/// that whoever shows such a day outside the shown range can ask for it
/// again, the store reports stale ([notifyStaleDays]), as each call into
/// it ends, the read days the call left changed, a zone change's
/// excepted, as it reads again every day it keeps, and the read days a
/// [show] or a refresh's failed read leaves stale outside the shown
/// range; [isStale] answers which of them a [prefetch] alone reads again,
/// none of the shown range, whose changed days the store reads again
/// itself. A background read of the shown range's changed days runs from
/// the first to the last of them that no read in flight covers; a shown
/// day changed since the read covering it was sent is read once more when
/// that read answers, so a burst of changes on a shown day being read
/// costs one more read.
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
/// sent since contradicts it, by answering the entry otherwise or a day
/// the answer covers without it, whether that read answers before the
/// write's answer or after it: which of the two the source holds is then
/// unknown, so the store keeps what it holds and reads the days of both
/// again. A read whose answer removed the entry from days the write's
/// answer does not cover leaves that answer standing, unless a change
/// announced or a read sent since the write was sent set or removed the
/// entry before that read. A write completes
/// with the data source's answer once the source answers, whether or not
/// the store keeps it.
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
/// written fails as that write fails, each with a [StateError]; and a read
/// answering a time the zone cannot represent, as a date its clock skips,
/// fails as a read does, with an [ArgumentError]. A source
/// call that throws instead of answering a future fails within the call,
/// with the error it threw. Only the first answer or failure of a source
/// call's future is heard: a future whose `then` throws once it answered
/// is taken at its answer.
///
/// An entry a read, an announced change or a write's answer brings is
/// compared with the one the store holds only to tell whether it
/// changes anything: a comparison that throws, as a payload's `==` can,
/// is reported through [FlutterError.reportError] and counts as a
/// change.
base class CachingCalendarStore<T> extends CalendarStore<T> {
  /// A store reading and writing through [dataSource], loading until the
  /// first [show], and applying each change [changes] announces, if given,
  /// until it is disposed: a [CalendarEntryPut] or a [CalendarEntryRemoved]
  /// is applied without a read, a [CalendarDaysChanged] is an [invalidate]
  /// of its days, or with a zone of the zone days its device days touch,
  /// and a [CalendarAllChanged], a change of a kind it does not know, or an
  /// error on the stream, is an [invalidate] of every day. The end of
  /// [changes] ends the announcements, and reads nothing: the store then
  /// hears of no change at the source, as a store given no stream, so a
  /// change made there shows once the store reads its day again, as at an
  /// [invalidate] or a [refresh]. [changes] is the store's for its life, so
  /// a source whose announcements can stop for a while, as across a lost
  /// connection, keeps the stream open ([CalendarSourceChange]). A [show]
  /// and a [retry] also read the [readAhead] days on each side of the shown
  /// range.
  ///
  /// Throws an [ArgumentError] naming `readAhead`, in every build, for a
  /// negative [readAhead].
  CachingCalendarStore({
    required CalendarDataSource<T> dataSource,
    Stream<CalendarSourceChange<T>>? changes,
    super.hours,
    super.zone,
    this.readAhead = 0,
  }) : _dataSource = dataSource {
    if (readAhead < 0) {
      throw ArgumentError.value(
        readAhead,
        "readAhead",
        "A read-ahead is a count of days, 0 or more.",
      );
    }
    _changes = changes?.listen(_applyChange, onError: _changesFailed);
  }

  /// The days a [show] and a [retry] also read before the shown range's
  /// first day and after its last, in the read each sends for the range,
  /// so a range's neighbours are read before a move of the range or a zone
  /// change brings them into it. 0 reads the shown range alone.
  ///
  /// The read-ahead's days take no part in [status] and [loadError], which
  /// follow the shown range alone. A host whose users switch zones sets 2,
  /// which keeps the shown days read across a change between any two zones
  /// once the store's reads have answered, the last zone change's re-reads
  /// included.
  final int readAhead;

  final CalendarDataSource<T> _dataSource;

  /// The subscription to the changes the source announces, if any.
  StreamSubscription<CalendarSourceChange<T>>? _changes;

  /// The store's clock, counted up by each read and write sent, write
  /// confirmed and change announced, which orders what each tells of the
  /// source, and by each read a [show] or a [retry] takes over
  /// ([_takeOver]).
  int _clock = 0;

  /// Each read day, by [CalendarDates.dayNumber].
  final Map<int, _Day> _days = <int, _Day>{};

  /// The clock when every entry was last taken to have changed.
  int _allChangedAt = 0;

  /// The clock of the latest-sent read that has filled a day, so a read
  /// sent before it is the only kind that checks for days filled later.
  int _newestFillAt = 0;

  /// By id, what last set or removed the entry. Kept only while a read or
  /// a write is in flight, since whatever is sent later is newer than all
  /// of them.
  final Map<String, _EntryTime> _entryTimes = <String, _EntryTime>{};

  /// By id, the clock when the write in flight on the entry was sent.
  final Map<String, int> _writesSentAt = <String, int>{};

  /// The creates in flight.
  int _creating = 0;

  /// The [show] calls that changed the shown range.
  int _showCount = 0;

  /// The entries the cache knows, filed under the read days and any day a
  /// zone change left open and unread, and the pending writes.
  CalendarEntryIndex<T> _index = CalendarEntryIndex<T>(opensEveryDay: false);

  /// The reads in flight, in the order they were sent.
  final List<_Read> _reads = <_Read>[];

  /// The days, by [CalendarDates.dayNumber], whose read failed while they
  /// were unread or changed ([readFailed]), each with the failure that
  /// marked it, until a read fills them, a [show], a [retry] or a [refresh]
  /// reads them, or a zone change, which ends every mark. Each is unread or
  /// changed: a mark is made only on such a day, and a read day stays
  /// changed until a read fills it, which ends its mark.
  final Map<int, _Mark> _failedDays = <int, _Mark>{};

  /// The count of failed reads, which orders their marks in [_failedDays].
  int _failures = 0;

  /// The days whose marks the [retry] or [refresh] under way ended, while
  /// it sends its reads ([_sendEnded]); null otherwise. A read that fails
  /// within the call and marks one of them again leaves the notification
  /// to that call.
  Set<int>? _endedMarks;

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

  /// The span of the days, by [CalendarDates.dayNumber], that the call
  /// under way has left stale ([isStale]) or may have, which the outermost
  /// [_batch] call reports as it ends; null while it has noted none.
  int? _staleFirst;
  int? _staleLast;

  /// Whether the call under way took every entry to have changed, which the
  /// outermost [_batch] call reports as every day stale.
  bool _staleAll = false;

  /// Follows from the shown range's days alone: ready once none of them is
  /// unread or [readFailed], failed while one is [readFailed], whether or
  /// not another read of it is in flight, and otherwise loading, as before
  /// the first [show]. A failed range stays failed while a read it did not
  /// ask for, such as a [prefetch], reads its failed days, until a [show], a
  /// [retry] or a [refresh] reads them, reads fill them, or a zone change,
  /// which ends every mark. A read day changed at its source stays ready
  /// while it is read again, and makes the range failed once that read
  /// fails, unless a refresh waited on it.
  @override
  CalendarLoadStatus get status {
    return _status;
  }

  /// While [status] is failed, the error of the latest failed read among
  /// those whose marks stand on the shown range's days ([readFailed]): the
  /// data source's error, a [StateError] where the read answered an entry
  /// with no id, or an [ArgumentError] where it answered a time the zone
  /// cannot represent. A mark keeps the error of the failure that made it,
  /// which a later failure on its day does not replace. Null otherwise.
  @override
  Object? get loadError {
    return _loadError;
  }

  /// The load state of the days from [first] to [last]: [status] where
  /// they are the shown range, and otherwise from their days and their
  /// marks alone, as [status] follows from the shown range's: ready once
  /// none is unread or [readFailed], failed once one is [readFailed], and
  /// otherwise loading. Ready for a [first] after [last].
  @override
  CalendarLoadStatus statusOf(DateTime first, DateTime last) {
    if (isShown(first, last)) {
      return super.statusOf(first, last);
    }
    return _loadOf(
      CalendarDates.dayNumber(first),
      CalendarDates.dayNumber(last),
    ).status;
  }

  /// The error of the failed read of the days from [first] to [last]:
  /// [loadError] where they are the shown range, and otherwise, while
  /// [statusOf] answers failed for them, the error of the latest failure
  /// among the [readFailed] marks on their days, as [loadError] is the
  /// shown range's; null otherwise.
  @override
  Object? loadErrorOf(DateTime first, DateTime last) {
    if (isShown(first, last)) {
      return super.loadErrorOf(first, last);
    }
    return _loadOf(
      CalendarDates.dayNumber(first),
      CalendarDates.dayNumber(last),
    ).error;
  }

  /// Whether [day] lies outside the shown range, as every day does before
  /// the first [show], and is read, taken to have changed at its source
  /// since the read that last filled it, not marked [readFailed], and
  /// under no read in flight. The store reads such a day again only once a
  /// [show] or a [prefetch] covers it, and reads the shown range's changed
  /// days again itself, so it answers false for every shown day.
  @override
  bool isStale(DateTime day) {
    return _isStaleDay(CalendarDates.dayNumber(day));
  }

  /// Shows [first] to [last], both inclusive. A range whose days are all
  /// read is ready at once; otherwise it is loading. Where no read in
  /// flight covers its unread days, the show sends one read of them, of its
  /// changed days and of its [readFailed] days. Where one does, or none is
  /// unread, the show takes that read, if any, over as its own, and reads
  /// the range's [readFailed] days again with a read of its own, as [retry]
  /// does, since a read in flight may fail as the last one did. Changed
  /// days of the range that no read in flight covers are read again too, in
  /// one read with those [readFailed] days, and the range does not wait on
  /// them. The show ends the [readFailed] mark of each day it reads, so it
  /// leaves no day of the range marked.
  /// A read the source answers within the call, as a [SynchronousFuture]'s
  /// does, is applied within it, so the call can leave the range ready, or
  /// failed where such a read failed and marked a day of it with no read
  /// asked for since in flight. Showing the range already shown changes
  /// nothing, and so does a show after [dispose]. As the call ends, the
  /// show reports stale ([notifyStaleDays]) the read days of the range it
  /// leaves that it leaves stale ([isStale]): changed, unmarked and under
  /// no read, as a refresh whose read failed leaves them. Throws an
  /// [ArgumentError]
  /// naming `last`, in every build, for a [last] whose day comes before
  /// [first]'s, also after [dispose].
  ///
  /// The unread and [readFailed] days the [readAhead] adds on each side of
  /// the range are read as the range's own: in the read the show sends,
  /// which a read in flight replaces only where it covers them too, and
  /// their [readFailed] marks end with the range's. [status] follows the
  /// range alone.
  @override
  void show(DateTime first, DateTime last) {
    checkShownRange(first, last);
    final firstDay = CalendarDates.dayNumber(first);
    final lastDay = CalendarDates.dayNumber(last);
    if (_disposed || (firstDay == _shownFirst && lastDay == _shownLast)) {
      return;
    }
    _batch(() {
      final leftFirst = _shownFirst;
      final leftLast = _shownLast;
      _shownFirst = firstDay;
      _shownLast = lastDay;
      _showCount++;
      var failed = _failedSpanOf(firstDay - readAhead, lastDay + readAhead);
      final unread = _unreadSpan();
      final covering = unread == null
          ? null
          : _inFlightCovering(unread.first, unread.last);
      if (unread != null && covering == null) {
        _readShown(_joined(unread, failed)!);
        failed = null;
      } else if (covering != null) {
        _takeOver(covering);
      }
      _readChangedShown(requested: true, failed: failed);
      _settleStatus();
      _notify();
      if (leftFirst != null && leftLast != null) {
        _noteStaleIn(leftFirst, leftLast);
      }
    });
  }

  /// Whether [day] is read. A changed day stays read.
  @override
  bool isRead(DateTime day) {
    return _days.containsKey(CalendarDates.dayNumber(day));
  }

  /// Whether a read of [day] failed while [day] was unread, or read and
  /// changed since the read that last filled it, and while no read a
  /// [show], a [retry] or a [refresh] asked for since it was sent was in
  /// flight over it, and neither a read has filled it nor a [show], a
  /// [retry] or a [refresh] has read it since, nor a zone change, which ends
  /// every mark, has come since. The read a refresh waits on marks no read
  /// day, its failure failing the refresh. A read the store sends in the
  /// background, as a [prefetch] or the read of changed days does, leaves
  /// the mark until it fills the day.
  @override
  bool readFailed(DateTime day) {
    return _failedDays.containsKey(CalendarDates.dayNumber(day));
  }

  /// Whether the shown range is exactly [first] to [last].
  @override
  bool isShown(DateTime first, DateTime last) {
    return _shownFirst == CalendarDates.dayNumber(first) &&
        _shownLast == CalendarDates.dayNumber(last);
  }

  /// Whether the shown range holds every day from [first] to [last]. False
  /// before the first [show].
  @override
  bool isWithinShown(DateTime first, DateTime last) {
    final shownFirst = _shownFirst;
    final shownLast = _shownLast;
    return shownFirst != null &&
        shownLast != null &&
        shownFirst <= CalendarDates.dayNumber(first) &&
        CalendarDates.dayNumber(last) <= shownLast;
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
  /// once no day of it is left [readFailed]. Notifies once at most, as the
  /// call ends, and only where [status], [loadError] or what the store
  /// answers changed, or a mark it ended is still ended, counting what the
  /// source answers within the call, as a [SynchronousFuture]'s does: a
  /// read that fails within the call and marks again the days whose marks
  /// it ended, leaving [status] and [loadError] as they were, notifies
  /// nothing. Throws an [ArgumentError] where one of [first] and [last] is
  /// given without the other. Does nothing after [dispose].
  ///
  /// The shown range's part takes in the [readAhead] days on each side of
  /// it: their marks end, and they are read, with the range's; the given
  /// days take none.
  @override
  void retry([DateTime? first, DateTime? last]) {
    if ((first == null) != (last == null)) {
      throw ArgumentError("A retry takes both first and last, or neither.");
    }
    if (_disposed) {
      return;
    }
    _batch(() {
      final ended = <int>{};
      final shownFirst = _shownFirst;
      final shownLast = _shownLast;
      ({int first, int last})? shownSpan;
      if (shownFirst != null && shownLast != null) {
        final aheadFirst = shownFirst - readAhead;
        final aheadLast = shownLast + readAhead;
        shownSpan = _retrySpan(aheadFirst, aheadLast);
        _endFailed(aheadFirst, aheadLast, ended);
      }
      ({int first, int last})? givenSpan;
      if (first != null && last != null) {
        final firstDay = CalendarDates.dayNumber(first);
        final lastDay = CalendarDates.dayNumber(last);
        givenSpan = _retrySpan(firstDay, lastDay);
        _endFailed(firstDay, lastDay, ended);
      }
      _sendEnded(ended, () {
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
      });
    });
  }

  /// Runs [send], the reads of a [retry] or a [refresh] that ended the
  /// marks of [ended], with [ended] as [_endedMarks], then notifies where
  /// [status] or [loadError] changed, or a mark of [ended] is still ended,
  /// counting what the source answers within the call: a read that fails
  /// within it and marks those days again, leaving [status] and
  /// [loadError] as they were, changes nothing.
  void _sendEnded(Set<int> ended, void Function() send) {
    final outer = _endedMarks;
    _endedMarks = ended;
    try {
      send();
    } finally {
      _endedMarks = outer;
    }
    if (_settleStatus() ||
        ended.any((day) {
          return !_failedDays.containsKey(day);
        })) {
      _notify();
    }
  }

  /// Reads the unread and the changed days from [first] to [last], both
  /// inclusive, without showing them, so the markers of days about to show
  /// appear once read. Sends nothing where a read in flight covers them,
  /// and nothing after [dispose]. Changes no shown range. It reads the days
  /// in the background: it leaves each [readFailed] mark until its read
  /// fills the day, and notifies nothing itself, so a failed shown range
  /// stays failed while it reads the range's failed days. Its read counts
  /// toward [status] once it answers, as any read does: one leaving the
  /// shown range with no unread or [readFailed] day makes it ready, and a
  /// failed one leaves its unread days unread and marks [readFailed] those
  /// and its changed days that no read a [show], a [retry] or a [refresh]
  /// asked for since covers in flight, which makes a shown range holding
  /// one failed. [first] after [last] gives no day.
  @override
  void prefetch(DateTime first, DateTime last) {
    if (_disposed) {
      return;
    }
    final span = _spanToRead(
      CalendarDates.dayNumber(first),
      CalendarDates.dayNumber(last),
    );
    if (span != null) {
      _send(span.first, span.last);
    }
  }

  /// Takes the entries on the days from [first] to [last], both inclusive,
  /// to have changed. Each read day of them still shows what the store
  /// holds, and is read again: at once where the shown range holds it, and
  /// otherwise once a [show] or a [prefetch] covers it. A read in flight
  /// over them leaves them changed once it answers. Where the read of a
  /// changed day fails, the day is marked [readFailed], which makes a shown
  /// range holding it failed. It notifies nothing itself: a read it sends
  /// notifies once it changes what the store answers or marks a day,
  /// within the call where the source answers within it. [first] after
  /// [last] gives no day. Does nothing after [dispose]. As the call ends,
  /// after any read it sends, it reports the read days it leaves changed
  /// as stale ([notifyStaleDays]), of which [isStale] answers true for
  /// those outside the shown range that no read in flight covers; a read
  /// in flight over them reports them as it answers.
  @override
  void invalidate(DateTime first, DateTime last) {
    final firstDay = CalendarDates.dayNumber(first);
    final lastDay = CalendarDates.dayNumber(last);
    if (_disposed || firstDay > lastDay) {
      return;
    }
    _batch(() {
      _markChanged(firstDay, lastDay, ++_clock);
      _readChangedShown();
    });
  }

  /// Takes every entry to have changed, as [invalidate] does for every
  /// day, and reads the whole shown range again at once, ending the
  /// [readFailed] mark of each of its days, so a failed shown range is
  /// loading again, as after [retry], unless the source answers that read
  /// within the call, as for [show]. A range whose days are all read
  /// stays ready, also once the read fails: its failure fails the refresh,
  /// whose caller hears it, and marks [readFailed] the range's unread days
  /// alone, leaving its read days changed. Notifies as a
  /// [retry] does, only where it changes something: a read that fails
  /// within the call with the error the range's marks hold notifies
  /// nothing. Completes once that read answers, or fails with the error it
  /// failed with; a zone change before it answers passes the wait to the
  /// read of the shown range that change sends. Completes at once before the
  /// first [show] and after [dispose], and when the store is disposed before
  /// the read answers. As the call ends, after the read it sends, it
  /// reports every day stale ([notifyStaleDays]), at once before the first
  /// [show]; [isStale] answers true for the read days outside the shown
  /// range that no read in flight covers. A read in flight when it is
  /// called reports the days it fills as it answers. Where the read fails,
  /// it leaves the shown range's read days changed and unmarked, which the
  /// next read's answer reads again, and reports them stale as it fails or
  /// as a [show] leaves them, once they lie outside the shown range.
  @override
  Future<void> refresh() {
    if (_disposed) {
      return Future<void>.value();
    }
    return _batch(() {
      _markAllChanged();
      final first = _shownFirst;
      final last = _shownLast;
      if (first == null || last == null) {
        return Future<void>.value();
      }
      final done = Completer<void>();
      final ended = <int>{};
      _endFailed(first, last, ended);
      _sendEnded(ended, () {
        _send(first, last, done: done, requested: true);
      });
      return done.future;
    });
  }

  /// The first to the last unread day of the shown range and of the
  /// [readAhead] days on each side of it, or null when every day of them
  /// is read.
  ({int first, int last})? _unreadSpan() {
    return _unreadSpanOf(_shownFirst! - readAhead, _shownLast! + readAhead);
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
      if (_isChanged(record) &&
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

  /// Whether [record], a read day, is changed: a change on it, or on every
  /// day, was announced since the read that last filled it was sent.
  bool _isChanged(_Day record) {
    return math.max(record.changedAt, _allChangedAt) > record.filledAt;
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
        if (_failedDays.containsKey(day)) {
          take(day);
        }
      }
    } else {
      _failedDays.keys.forEach(take);
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

  /// Takes [read] over as the own read of a [show] or a [retry] asked now,
  /// at a new tick of the clock, so a read sent before now that fails marks
  /// no day [read] covers ([_requestedSince]). A [refresh] takes over no
  /// read: it sends its own.
  void _takeOver(_Read read) {
    read.requestedAt = ++_clock;
  }

  /// Ends the [readFailed] mark of each day from [first] to [last], adds
  /// those days to [ended], if given, and returns whether one had a mark.
  bool _endFailed(int first, int last, [Set<int>? ended]) {
    if (_failedDays.isEmpty || first > last) {
      return false;
    }
    final before = _failedDays.length;
    _failedDays.removeWhere((day, mark) {
      final ends = day >= first && day <= last;
      if (ends) {
        ended?.add(day);
      }
      return ends;
    });
    return _failedDays.length != before;
  }

  /// The [CalendarDates.dayNumber]s of the read days from [first] to [last],
  /// walking the shorter of the span and the read days.
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
    final first = CalendarDates.dayNumber(entry.start);
    final last = CalendarDates.lastDayNumberOf(entry.start, entry.end);
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
      _markDayChanged(day, _days[day]!, at);
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

  /// Sends a read of [days], the span of the unread and [readFailed] days
  /// of the shown range and its [readAhead], and of the range's changed
  /// days, as one span, which a [show] asked for, so it ends the
  /// [readFailed] marks over that span.
  void _readShown(({int first, int last}) days) {
    final changed = _changedSpanOf(_shownFirst!, _shownLast!);
    final first = changed == null
        ? days.first
        : math.min(days.first, changed.first);
    final last = changed == null
        ? days.last
        : math.max(days.last, changed.last);
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

  /// Sets [status] and [loadError] from the shown range's days and their
  /// marks alone, and returns whether either changed: ready once none is
  /// unread or [readFailed]; failed once one is [readFailed], with the
  /// error of the latest failure among the marks on its days; and
  /// otherwise loading.
  bool _settleStatus() {
    final first = _shownFirst;
    final last = _shownLast;
    if (first == null || last == null) {
      return false;
    }
    final (:status, :error) = _loadOf(first, last);
    if (status == _status && identical(error, _loadError)) {
      return false;
    }
    _status = status;
    _loadError = error;
    return true;
  }

  /// The load state of the days from [first] to [last], by
  /// [CalendarDates.dayNumber], and its error, from their days and their
  /// marks alone: ready once none is unread or [readFailed]; failed once
  /// one is [readFailed], with the error of the latest failure among the
  /// marks on its days; and otherwise loading. Ready, with no error, for a
  /// [first] after [last].
  ({CalendarLoadStatus status, Object? error}) _loadOf(int first, int last) {
    var unread = false;
    _Mark? latest;
    for (var day = first; day <= last; day++) {
      if (!_days.containsKey(day)) {
        unread = true;
      }
      final mark = _failedDays[day];
      if (mark != null && (latest == null || mark.order > latest.order)) {
        latest = mark;
      }
    }
    return (
      status: latest != null
          ? CalendarLoadStatus.failed
          : unread
          ? CalendarLoadStatus.loading
          : CalendarLoadStatus.ready,
      error: latest?.error,
    );
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
      if (_depth == 0) {
        if (_notifyPending) {
          _notifyPending = false;
          // [body] can dispose the store, as a data source's write can from
          // within its call, after which [notifyListeners] throws in debug
          // builds.
          if (!_disposed) {
            notifyListeners();
          }
        }
        _reportStale();
      }
    }
  }

  /// Clears the stale days the call noted and, unless the store is
  /// disposed, reports them ([notifyStaleDays]): every day where it took
  /// every entry to have changed, and otherwise the span it noted, as day
  /// starts on the store's clock.
  void _reportStale() {
    final all = _staleAll;
    final first = _staleFirst;
    final last = _staleLast;
    _staleAll = false;
    _staleFirst = null;
    _staleLast = null;
    if (_disposed) {
      return;
    }
    if (all) {
      notifyStaleDays(const CalendarStaleDays.all());
    } else if (first != null && last != null) {
      notifyStaleDays(
        CalendarStaleDays(
          CalendarDates.dateOfDayNumber(first, zone: zone),
          CalendarDates.dateOfDayNumber(last, zone: zone),
        ),
      );
    }
  }

  /// Widens the stale span the call under way reports to take [day].
  void _noteStale(int day) {
    final first = _staleFirst;
    final last = _staleLast;
    _staleFirst = first == null ? day : math.min(first, day);
    _staleLast = last == null ? day : math.max(last, day);
  }

  /// Widens the stale span to take each day from [first] to [last] that
  /// [_isStaleDay] answers true for.
  void _noteStaleIn(int first, int last) {
    for (var day = first; day <= last; day++) {
      if (_isStaleDay(day)) {
        _noteStale(day);
      }
    }
  }

  /// Takes [record], the read day [day], to have changed at the clock
  /// [at], and notes it stale.
  void _markDayChanged(int day, _Day record, int at) {
    record.changedAt = math.max(record.changedAt, at);
    _noteStale(day);
  }

  /// Takes every entry to have changed, and notes every day stale.
  void _markAllChanged() {
    _allChangedAt = ++_clock;
    _staleAll = true;
  }

  /// Whether [day] lies outside the shown range, as every day does before
  /// the first [show], and is read, changed, not marked [readFailed], and
  /// under no read in flight: a day that only a [prefetch] reads again
  /// ([isStale]).
  bool _isStaleDay(int day) {
    final shownFirst = _shownFirst;
    final shownLast = _shownLast;
    if (shownFirst != null &&
        shownLast != null &&
        day >= shownFirst &&
        day <= shownLast) {
      return false;
    }
    final record = _days[day];
    return record != null &&
        _isChanged(record) &&
        !_failedDays.containsKey(day) &&
        _inFlightCovering(day, day) == null;
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

  /// Sends a read of the store's days [first] to [last], which [done], if
  /// given, waits on, and which a [show], a [retry] or a [refresh] asked for
  /// where [requested]. The data source is asked for the device days
  /// covering them: their own numbers with no zone, and with one the device
  /// days holding those days' instants, widened to hold their numbers too,
  /// so an all-day entry on those dates is read wherever the zone lies. It
  /// ends no [readFailed] mark: a [show], a [retry] or a [refresh] ends the
  /// marks of the days it reads itself. The read is in flight before the
  /// source is called, so an answer that arrives within the call, as a
  /// [SynchronousFuture]'s does, finishes it. After [dispose], as when a
  /// source call disposed the store, it sends nothing and completes [done],
  /// as [dispose] completes a refresh's.
  void _send(
    int first,
    int last, {
    Completer<void>? done,
    bool requested = false,
  }) {
    if (_disposed) {
      done?.complete();
      return;
    }
    final read = _Read(first, last, ++_clock, done);
    if (requested) {
      read.requestedAt = read.sentAt;
    }
    _reads.add(read);
    final zone = this.zone;
    var deviceFirst = first;
    var deviceLast = last;
    if (zone != null) {
      deviceFirst = math.min(_dayAt(dayStartMillis(first, zone), null), first);
      deviceLast = math.max(
        _dayAt(dayStartMillis(last + 1, zone) - 1, null),
        last,
      );
    }
    _callSource<List<CalendarEntry<T>>>(
      () {
        return _dataSource.read(
          CalendarDates.dateOfDayNumber(deviceFirst),
          CalendarDates.dateOfDayNumber(deviceLast),
        );
      },
      (entries) {
        _finishRead(read, entries: entries);
      },
      (error, stackTrace) {
        _finishRead(read, error: error);
      },
    );
  }

  /// Calls the data source through [call], and hears only the first answer
  /// or failure of the future it returns, whatever that future does:
  /// [answered] or [failed] runs once at most. A throw within [call] is
  /// its failure, heard within the call. A throw from the future's `then`
  /// before an answer or a failure is heard is its failure too; one after
  /// is dropped, as [answered] or [failed] has run. A throw from [answered]
  /// or [failed] is the store's own, never the source's failure: it
  /// escapes the call where the future answers within it, as a
  /// [SynchronousFuture]'s does, and otherwise fails the future `then`
  /// returns, as any callback's throw does.
  void _callSource<A>(
    Future<A> Function() call,
    void Function(A answer) answered,
    void Function(Object error, StackTrace stackTrace) failed,
  ) {
    var heard = false;
    Object? own;

    void answer(A value) {
      if (heard) {
        return;
      }
      heard = true;
      try {
        answered(value);
      } on Object catch (error) {
        own = error;
        rethrow;
      }
    }

    void fail(Object error, StackTrace stackTrace) {
      if (heard) {
        return;
      }
      heard = true;
      try {
        failed(error, stackTrace);
      } on Object catch (error) {
        own = error;
        rethrow;
      }
    }

    try {
      call().then<void>(answer, onError: fail);
    } on Object catch (error, stackTrace) {
      if (identical(error, own)) {
        rethrow;
      }
      fail(error, stackTrace);
    }
  }

  /// A read's answer. A read sent before a zone change applies nothing,
  /// answered or failed, and completes nothing, its wait having passed to
  /// the read of the shown range that zone change sent. One that answers
  /// ends the [readFailed] mark of each day it fills, and sends the read
  /// again of the shown range's changed days, a day announced changed
  /// meanwhile or marked [readFailed] among them. A failed one marks
  /// [readFailed] each of its days that is unread or changed, the read
  /// days only where no refresh waits on it ([_Read.done]), and that no
  /// read a [show], a [retry] or a [refresh] asked for since it was sent
  /// covers in flight ([_requestedSince]), whatever a read in flight in the
  /// background will answer; a day marked already keeps its mark and the
  /// mark's error. It
  /// notifies when it changed [status], [loadError], what the store
  /// answers, or [readFailed], except that it leaves to a [retry] or a
  /// [refresh] under way the marks it makes again on the days that call
  /// ended ([_endedMarks]).
  void _finishRead(
    _Read read, {
    List<CalendarEntry<T>>? entries,
    Object? error,
  }) {
    if (_disposed || read.stale) {
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
    if (answered != null) {
      try {
        answered = _zonedAnswer(read, answered);
      } on ArgumentError catch (conversion) {
        failure = conversion;
        answered = null;
      }
    }
    final changed = answered != null && _applyRead(read, answered);
    _pruneEntryTimes();
    final endedMarks = _endedMarks;
    var failed = false;
    if (answered == null) {
      final mark = (error: failure!, order: ++_failures);
      // The failure of a read a refresh waits on reaches the refresh's
      // caller, so of the read days it marks none.
      final heard = read.done != null;
      for (var day = read.first; day <= read.last; day++) {
        final record = _days[day];
        if ((record == null || (!heard && _isChanged(record))) &&
            !_requestedSince(read, day) &&
            !_failedDays.containsKey(day)) {
          _failedDays[day] = mark;
          failed = failed || endedMarks == null || !endedMarks.contains(day);
        }
      }
    }
    if (answered == null && read.done != null) {
      // The read days a refresh's failed read leaves changed and unmarked
      // that a show has moved the shown range off are stale.
      _noteStaleIn(read.first, read.last);
    }
    final settled = _settleStatus();
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

  /// [entries], the answer of [read], in the store's form ([zonedEntryOf]),
  /// less, with a zone, each entry with no part in the read's days: the
  /// device days the read asked for hold entries of other zone days.
  ///
  /// Throws an [ArgumentError] for a time the zone cannot represent.
  List<CalendarEntry<T>> _zonedAnswer(
    _Read read,
    List<CalendarEntry<T>> entries,
  ) {
    final zone = this.zone;
    final zoned = <CalendarEntry<T>>[];
    for (final entry in entries) {
      final converted = zonedEntryOf(entry, zone);
      if (zone == null ||
          (CalendarDates.dayNumber(converted.start) <= read.last &&
              CalendarDates.lastDayNumberOf(converted.start, converted.end) >=
                  read.first)) {
        zoned.add(converted);
      }
    }
    return zoned;
  }

  /// Applies [entries], the answer of [read], and returns whether what the
  /// store answers, or a day's [readFailed] mark, changed.
  ///
  /// The read fills its unread days, and its read ones that no read sent later
  /// filled, ending the mark of each day it fills. Each entry it answers
  /// replaces the held one, and each held entry
  /// on a day it fills that it does not answer is forgotten, except an entry a
  /// write confirmed, a change announced or a read sent since set or removed. A
  /// read sent later that removed an entry told nothing of the days it did not
  /// cover, so the entry is answered still, at this read's clock, which a read
  /// sent before this one does not override; unless a write confirmed, a change
  /// announced or a read sent since this one set or removed the entry before
  /// that removal ([_EntryTime.beneath]), which supersedes this read's answer
  /// as it did before the removal, or, for a write's answer it is checked
  /// against, leaves the days of the answered entry changed, to be read again,
  /// where no read sent later filled one of them. A forgotten entry leaves
  /// changed the read days it covers outside the read. An answered entry
  /// covering a day a read sent later filled without it is out of date there,
  /// so the days it covers here are left changed, to be read again; so are
  /// those with a change announced while the read was in flight.
  ///
  /// The answer of a write sent before the read and stored since it was
  /// sent stays, though the read may contradict it, as it can whichever of
  /// the two answers first: where the read answers the entry otherwise, or
  /// fills a day the answer covers without it, the days of both entries
  /// are left changed ([_markBoth]), and the shown ones are read again once
  /// the read answers.
  bool _applyRead(_Read read, List<CalendarEntry<T>> entries) {
    final at = read.sentAt;
    final opened = <int>[];
    final filled = <int>[];
    var unmarked = false;
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
        unmarked = _failedDays.remove(day) != null || unmarked;
      }
    }
    if (filled.isNotEmpty) {
      _newestFillAt = math.max(_newestFillAt, at);
      // A read sent before every entry was taken to have changed leaves the
      // days it fills changed.
      if (at < _allChangedAt) {
        _noteStale(filled.first);
        _noteStale(filled.last);
      }
    }
    if (read.changedAt != 0) {
      for (var day = read.changedFirst; day <= read.changedLast; day++) {
        _markDayChanged(day, _days[day]!, read.changedAt);
      }
    }
    _index.open(opened);
    var changed = opened.isNotEmpty || unmarked;
    final answered = <String>{};
    final updated = <CalendarEntry<T>>[];
    for (final entry in entries) {
      final id = entry.id!;
      answered.add(id);
      final time = _entryTimes[id];
      if (time != null && time.at > at) {
        if (_checksRead(time, at)) {
          final held = _index.stored(id);
          if (_differs(held, entry)) {
            _markBoth(held, entry);
          }
          continue;
        }
        if (time.forgottenBy == null) {
          continue;
        }
        final beneath = time.beneath;
        if (beneath != null && beneath.at > at) {
          if (!_checksRead(beneath, at)) {
            continue;
          }
          // The entry held under the write's stamp is forgotten, by a read
          // that filled its days, so only this read's entry is read again.
          if (!(_newestFillAt > at && _filledAfter(entry, at))) {
            _markBoth(null, entry);
            continue;
          }
        }
      }
      if (_newestFillAt > at && _filledAfter(entry, at)) {
        final first = math.max(
          CalendarDates.dayNumber(entry.start),
          read.first,
        );
        final last = math.min(
          CalendarDates.lastDayNumberOf(entry.start, entry.end),
          read.last,
        );
        for (var day = first; day <= last; day++) {
          final record = _days[day]!;
          if (record.filledAt == at) {
            _markDayChanged(day, record, _clock);
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
    Set<String>? contradicted;
    for (final day in filled) {
      for (final entry in _index.storedOn(day)) {
        final id = entry.id!;
        if (answered.contains(id)) {
          continue;
        }
        final time = _entryTimes[id];
        if (time != null && time.at > at) {
          if (_checksRead(time, at) && (contradicted ??= <String>{}).add(id)) {
            _markBoth(entry, null);
          }
          continue;
        }
        _index.forget(id);
        _setTime(
          id,
          at,
          forgottenBy: read,
          beneath: time == null || time.forgottenBy == null
              ? time
              : time.beneath,
        );
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
    final first = CalendarDates.dayNumber(entry.start);
    final last = CalendarDates.lastDayNumberOf(entry.start, entry.end);
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
  /// [forgottenBy], if given, removed it, over the stamp [beneath] of what
  /// else last set or removed it; and where [checksReadsAfter] is given, a
  /// write's answer was stamped, against which a read sent after that
  /// clock and before [at] is checked.
  void _setTime(
    String id,
    int at, {
    _Read? forgottenBy,
    int? checksReadsAfter,
    _EntryTime? beneath,
  }) {
    if (!_inFlight) {
      return;
    }
    _entryTimes[id] = _EntryTime(
      at,
      forgottenBy: forgottenBy,
      checksReadsAfter: checksReadsAfter,
      beneath: beneath,
    );
  }

  /// Drops [_entryTimes] once no read or write is in flight.
  void _pruneEntryTimes() {
    if (!_inFlight) {
      _entryTimes.clear();
    }
  }

  /// Whether [time] stamps a write's answer against which a read sent at
  /// the clock [at], before the answer was stamped, is checked: one sent
  /// after its [_EntryTime.checksReadsAfter], which the source may have
  /// served before it applied the write, and which nothing set since it
  /// was sent supersedes.
  bool _checksRead(_EntryTime time, int at) {
    final after = time.checksReadsAfter;
    return after != null && after < at;
  }

  /// Leaves changed, at a new tick of the clock, the days of [held], the
  /// entry the store holds, and of [other], an entry that contradicts it,
  /// either of which may be null; which of the two the source holds is
  /// unknown, so both are read again.
  void _markBoth(CalendarEntry<T>? held, CalendarEntry<T>? other) {
    final at = ++_clock;
    if (held != null) {
      _markDaysOf(held, at);
    }
    if (other != null) {
      _markDaysOf(other, at);
    }
  }

  /// Applies [change], which the source announced.
  void _applyChange(CalendarSourceChange<T> change) {
    if (_disposed) {
      return;
    }
    _batch(() {
      switch (change) {
        case CalendarEntryPut<T>(:final entry):
          _applyPut(entry);
        case CalendarEntryRemoved<T>(:final id):
          _applyRemoved(id);
        case CalendarDaysChanged<T>(:final first, :final last):
          _invalidateDeviceDays(first, last);
        case CalendarAllChanged<T>():
          _changeAll();
        default:
          // A kind of change the store does not know, which may have
          // changed any entry.
          _changeAll();
      }
    });
  }

  /// Takes the entries on the device days from [first] to [last] to have
  /// changed, as [invalidate] does: with no zone its own days, and with one
  /// the zone days those device days touch, from the zone's day of the
  /// start of [first]'s device day to its day of the instant before the
  /// device day after [last], widened to hold their numbers too.
  void _invalidateDeviceDays(DateTime first, DateTime last) {
    final zone = this.zone;
    if (zone == null) {
      invalidate(first, last);
      return;
    }
    final firstNumber = CalendarDates.dayNumber(first);
    final lastNumber = CalendarDates.dayNumber(last);
    final firstDay = math.min(
      _dayAt(
        CalendarDates.dateOfDayNumber(firstNumber).millisecondsSinceEpoch,
        zone,
      ),
      firstNumber,
    );
    final lastDay = math.max(
      _dayAt(
        CalendarDates.dateOfDayNumber(lastNumber + 1).millisecondsSinceEpoch -
            1,
        zone,
      ),
      lastNumber,
    );
    _markChanged(firstDay, lastDay, ++_clock);
    _readChangedShown();
  }

  /// The [CalendarDates.dayNumber] of the instant [instant], in milliseconds
  /// since the epoch, on [zone]'s clock, the device's where it is null.
  static int _dayAt(int instant, Location? zone) {
    return CalendarDates.dayNumber(
      zone == null
          ? DateTime.fromMillisecondsSinceEpoch(instant)
          : TZDateTime.fromMillisecondsSinceEpoch(zone, instant),
    );
  }

  /// An error on the stream of changes: the store cannot tell what it
  /// missed, so every entry is taken to have changed.
  void _changesFailed(Object error) {
    if (_disposed) {
      return;
    }
    _batch(_changeAll);
  }

  /// Takes every entry to have changed, and reads the shown range's read
  /// days again.
  void _changeAll() {
    _markAllChanged();
    _readChangedShown();
  }

  /// Stores [entry], which the source announced stored, in the store's
  /// form, where it covers a read day, a day a zone change left open or a
  /// day a read in flight covers; otherwise forgets the entry its id names,
  /// which left the days the store holds. A time the zone cannot represent
  /// stores nothing and takes
  /// every entry to have changed, so what the source holds is read anew,
  /// since no caller waits on an announced change to fail to.
  void _applyPut(CalendarEntry<T> entry) {
    final CalendarEntry<T> zoned;
    try {
      zoned = zonedEntryOf(entry, zone);
    } on ArgumentError {
      _changeAll();
      return;
    }
    final id = zoned.id!;
    _setTime(id, ++_clock);
    if (_coversHeldDay(zoned)) {
      if (_differs(_index.stored(id), zoned)) {
        _index.put(zoned);
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

  /// Whether [entry] covers an open day, read or left open by a zone
  /// change, or a day a read in flight covers.
  bool _coversHeldDay(CalendarEntry<T> entry) {
    final first = CalendarDates.dayNumber(entry.start);
    final last = CalendarDates.lastDayNumberOf(entry.start, entry.end);
    for (final read in _reads) {
      if (read.first <= last && read.last >= first) {
        return true;
      }
    }
    return _openDayIn(first, last);
  }

  /// Whether a day from [first] to [last] is open in the index, walking the
  /// shorter of the span and the open days.
  bool _openDayIn(int first, int last) {
    final openDays = _index.openDays;
    if (last - first < openDays.length) {
      for (var day = first; day <= last; day++) {
        if (_index.isOpen(day)) {
          return true;
        }
      }
      return false;
    }
    return openDays.any((day) {
      return day >= first && day <= last;
    });
  }

  /// The entries shown on [day], sorted by start, end, title and id: those
  /// filed under it when it is read or left open and unread by a zone
  /// change, and the pending entries covering it.
  @override
  List<CalendarShownEntry<T>> entriesOn(DateTime day) {
    return _index.entriesOn(CalendarDates.dayNumber(day));
  }

  /// The entries shown on any day from [first] to [last], each once,
  /// sorted as [entriesOn] sorts.
  @override
  List<CalendarShownEntry<T>> entriesBetween(DateTime first, DateTime last) {
    return _index.entriesBetween(
      CalendarDates.dayNumber(first),
      CalendarDates.dayNumber(last),
    );
  }

  /// Whether [day] shows a marker: it has shown entries, and, while the
  /// shown range is not ready, it was read under an earlier [show] call. A
  /// day a zone change left open and unread shows none, until a read fills
  /// it.
  @override
  bool dayHasShownEntries(DateTime day) {
    final number = CalendarDates.dayNumber(day);
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

  /// Stores [draft] through the data source; completes with the source's
  /// answer, the entry it stored, or fails with the source's error. The
  /// store keeps that answer unless a change announced or a read sent
  /// since contradicts it, as for every write ([CachingCalendarStore]).
  /// Nothing is shown before the source answers, and an answer that
  /// arrives within the call, as a [SynchronousFuture]'s does, is stored
  /// within it. It sends nothing and fails with a [StateError] after
  /// [dispose], with a [CalendarHoursException] for a draft outside
  /// [hours], and with an [ArgumentError] for a time the zone cannot
  /// represent. An answer with no id fails with a [StateError] and stores
  /// nothing; one whose id has a write in flight, as after a read that
  /// brought the entry and a move of it, completes and changes nothing. The
  /// data source receives device form ([deviceEntryOf]), and the answer is
  /// taken to the store's form as it arrives.
  @override
  Future<CalendarEntry<T>> create(CalendarEntry<T> draft) {
    if (_disposed) {
      return _refuse(_disposedError());
    }
    final CalendarEntry<T> zoned;
    try {
      zoned = zonedEntryOf(draft, zone);
    } on ArgumentError catch (error) {
      return _refuse(error);
    }
    // Held to the hours whatever stored entry its id names: the exemption
    // [hoursRefusalOf] makes for a write keeping a stored entry's times is
    // for a write on that entry.
    if (!hours.holdsTimes(zoned.start, zoned.end, isAllDay: zoned.isAllDay)) {
      return _refuse(
        CalendarHoursException(
          hours: hours,
          start: zoned.start,
          end: zoned.end,
        ),
      );
    }
    return _write<CalendarEntry<T>, CalendarEntry<T>>(
      send: () {
        return _dataSource.create(deviceEntryOf(zoned));
      },
      store: (created, sentAt) {
        final id = created.id;
        if (id == null) {
          throw StateError("The data source created an entry with no id.");
        }
        final answer = zonedEntryOf(created, zone);
        if (!_disposed && !_index.isPending(id)) {
          _storeAnswer(id, answer, sentAt);
          _notify();
        }
        return answer;
      },
    );
  }

  /// Writes [entry], whose id names a stored entry; the entry shows
  /// pending, as stored, until the data source answers. Completes with the
  /// source's answer, the entry it stored, which the store keeps unless a
  /// change announced or a read sent since contradicts it
  /// ([CachingCalendarStore]), or fails with the source's error. It sends
  /// nothing and fails with a [StateError] after [dispose], with an
  /// [ArgumentError] for an entry with no id or a time the zone cannot
  /// represent, with a [CalendarHoursException] when [hoursRefusalOf]
  /// refuses it, and with a [CalendarWritePendingException] on a pending
  /// entry. An answer under another id fails with a [StateError], the entry
  /// showing as stored again. An answer that arrives within the call, as a
  /// [SynchronousFuture]'s does, is stored within it. The data source
  /// receives device form ([deviceEntryOf]), and the answer is taken to the
  /// store's form as it arrives.
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
    final CalendarEntry<T> zoned;
    try {
      zoned = zonedEntryOf(entry, zone);
    } on ArgumentError catch (error) {
      return _refuse(error);
    }
    final refusal = hoursRefusalOf(zoned);
    if (refusal != null) {
      return _refuse(refusal);
    }
    return _write<CalendarEntry<T>, CalendarEntry<T>>(
      lock: id,
      send: () {
        return _dataSource.replace(deviceEntryOf(zoned));
      },
      store: (updated, sentAt) {
        return _storeReplaced(id, updated, sentAt);
      },
    );
  }

  /// Writes a grid move or resize: [requested] shows, pending, until the
  /// data source answers. Completes with the source's answer, the entry it
  /// stored, which the store keeps unless a change announced or a read
  /// sent since contradicts it ([CachingCalendarStore]), or fails with the
  /// source's error, the stored entry showing again. It sends nothing
  /// and fails with a [StateError] after [dispose], with an
  /// [ArgumentError] for an entry with no id or a time the zone cannot
  /// represent, with a [CalendarHoursException] when [hoursRefusalOf]
  /// refuses it, and with a [CalendarWritePendingException] on a pending
  /// entry; a move onto another entry's time is sent. An answer under
  /// another id fails with a [StateError]. An answer that arrives within
  /// the call, as a [SynchronousFuture]'s does, is stored within it. The
  /// data source receives device form ([deviceEntryOf]), and the answer is
  /// taken to the store's form as it arrives.
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
    final CalendarEntry<T> zoned;
    try {
      zoned = zonedEntryOf(requested, zone);
    } on ArgumentError catch (error) {
      return _refuse(error);
    }
    final refusal = hoursRefusalOf(zoned);
    if (refusal != null) {
      return _refuse(refusal);
    }
    return _write<CalendarEntry<T>, CalendarEntry<T>>(
      lock: id,
      shown: zoned,
      send: () {
        return _dataSource.replace(deviceEntryOf(zoned));
      },
      store: (moved, sentAt) {
        return _storeReplaced(id, moved, sentAt);
      },
    );
  }

  /// Deletes [id]: the stored entry shows pending until the data source
  /// answers, and leaves once it confirms, unless a change announced or a
  /// read sent since contradicts that ([CachingCalendarStore]). Completes
  /// then, or fails with the source's error, the entry showing as stored
  /// again. It sends nothing and fails with a [StateError] after
  /// [dispose], and with a [CalendarWritePendingException] on a pending
  /// entry. An answer that arrives within the call, as a
  /// [SynchronousFuture]'s does, is stored within it.
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

      // [_callSource] hears one answer or failure, so the write ends once,
      // even where [send]'s future answers again from within [store].
      _callSource<A>(
        send,
        (answer) {
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
        },
        (error, stackTrace) {
          _batch(() {
            fail(error, stackTrace);
          });
        },
      );
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
  /// sent at the clock [sentAt] ([_storeAnswer]), in the store's form,
  /// unless the store is disposed, and returns it, what the write completes
  /// with, whether or not it is stored; throws a [StateError] for an answer
  /// under another id, and an [ArgumentError] for a time the zone cannot
  /// represent.
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
    final zoned = zonedEntryOf(answer, zone);
    if (!_disposed) {
      _storeAnswer(id, zoned, sentAt);
    }
    return zoned;
  }

  /// Stores [answer], what a write sent at the clock [sentAt] left under
  /// [id], or forgets the entry for a null [answer], a delete's; unless it
  /// differs from the entry held and a change announced or a read sent
  /// since contradicts it ([_contradicted]). Which of the two the source
  /// holds is then unknown, so the store keeps what it holds and reads the
  /// days of both again.
  ///
  /// Either way the answer is stamped at a new tick of the clock, so a
  /// read sent since that answers after it is checked against the entry
  /// held ([_applyRead]): one sent since [sentAt] where the store holds
  /// the answer. Where it keeps what it holds, over a contradicted answer
  /// or over one that changes nothing because a change announced or a
  /// read sent since set the entry as the answer does, one sent since
  /// what set the entry it keeps, which supersedes a read sent before it.
  void _storeAnswer(String id, CalendarEntry<T>? answer, int sentAt) {
    final held = _index.stored(id);
    final differs = _differs(held, answer);
    final time = _entryTimes[id];
    if (differs && _contradicted(id, answer, sentAt)) {
      _markBoth(held, answer);
      _stampKept(id, time, sentAt);
      _readChangedShown();
      return;
    }
    if (!differs &&
        time != null &&
        time.at > sentAt &&
        time.forgottenBy == null) {
      _stampKept(id, time, sentAt);
      return;
    }
    if (answer == null) {
      _index.forget(id);
    } else {
      _index.put(answer);
    }
    _setTime(id, ++_clock, checksReadsAfter: sentAt);
  }

  /// Stamps the answer of a write sent at the clock [sentAt] under [id],
  /// over which the store keeps what it holds, as [time], if given, last
  /// set or removed it: a read sent after the later of [sentAt] and the
  /// clock of the read's answer or the change that set what [time] stamps
  /// is checked against the entry held. A read whose answer removed the
  /// entry supersedes no read that answers it elsewhere, so then the check
  /// runs from [sentAt].
  void _stampKept(String id, _EntryTime? time, int sentAt) {
    final setAt = time != null && time.forgottenBy == null ? time.at : sentAt;
    _setTime(id, ++_clock, checksReadsAfter: math.max(sentAt, setAt));
  }

  /// Whether a change announced since the clock [sentAt], or a read sent
  /// since, contradicts [answer], a write's answer under [id] other than
  /// the entry held: the change or the read's answer set or removed the
  /// entry, unless the latest to do so was a read whose answer removed it
  /// from days [answer] does not cover and nothing else set or removed it
  /// since [sentAt] before that read ([_EntryTime.beneath]); or the read
  /// filled a day [answer] covers, and so left the entry other than
  /// [answer] there.
  bool _contradicted(String id, CalendarEntry<T>? answer, int sentAt) {
    final time = _entryTimes[id];
    if (time != null && time.at > sentAt) {
      final beneath = time.beneath;
      if (!_removedElsewhere(time, answer) ||
          (beneath != null && beneath.at > sentAt)) {
        return true;
      }
    }
    return answer != null && _filledAfter(answer, sentAt);
  }

  /// Whether [time] stamps a read whose answer removed the entry, over days
  /// [answer] does not cover.
  bool _removedElsewhere(_EntryTime time, CalendarEntry<T>? answer) {
    final read = time.forgottenBy;
    if (read == null || answer == null) {
      return false;
    }
    final first = CalendarDates.dayNumber(answer.start);
    final last = CalendarDates.lastDayNumberOf(answer.start, answer.end);
    return last < read.first || first > read.last;
  }

  /// Under a zone [next] to come, builds the entries filed under [next],
  /// the days read and open under it and the spans to read again, changing
  /// nothing, and answers the function that puts them in place: every read
  /// in flight goes stale and hands its wait to the read of the shown range,
  /// which is sent first, and then each other re-read span goes out, all in
  /// the background, and the listeners are notified once. Coverage comes
  /// from runs of consecutive days under the old zone: a day [next]'s clock
  /// reads wholly inside the instants a run of read days covers, whose date
  /// lies in that run, stays read; every other day of a run of open days,
  /// widened to the instants and dates the run holds under [next], stays
  /// open and unread, so its entries stay answered through a second zone
  /// change or a failed re-read. After [dispose] it builds nothing.
  @override
  VoidCallback prepareZone(Location? next) {
    if (_disposed) {
      return () {};
    }
    final old = zone;
    final opened = <int>{};
    final spans = <({int first, int last})>[];
    for (final (:first, :last) in _runsOf(_index.openDays)) {
      final startMs = dayStartMillis(first, old);
      final endMs = dayStartMillis(last + 1, old);
      final from = math.min(_dayAt(startMs, next), first);
      final to = math.max(_dayAt(endMs - 1, next), last);
      opened.addAll(<int>[for (var day = from; day <= to; day++) day]);
      spans.add((first: from, last: to));
    }
    final read = <int>{};
    for (final (:first, :last) in _runsOf(_days.keys)) {
      final startMs = dayStartMillis(first, old);
      final endMs = dayStartMillis(last + 1, old);
      final firstIn = _dayAt(startMs, next);
      final lastIn = _dayAt(endMs - 1, next);
      final readFrom = dayStartMillis(firstIn, next) >= startMs
          ? firstIn
          : firstIn + 1;
      final readTo = dayStartMillis(lastIn + 1, next) <= endMs
          ? lastIn
          : lastIn - 1;
      final lastRead = math.min(readTo, last);
      for (var day = math.max(readFrom, first); day <= lastRead; day++) {
        read.add(day);
      }
    }
    final index = _index.refiled((entry) {
      return zonedEntryOf(entry, next);
    }, days: opened);
    final others = _rereadSpans(spans);
    return () {
      _batch(() {
        final waiters = <Completer<void>>[];
        for (final stale in _reads) {
          stale.stale = true;
          final done = stale.done;
          if (done != null) {
            waiters.add(done);
          }
        }
        _reads.clear();
        _index = index;
        _days.clear();
        for (final day in read) {
          _days[day] = _Day(0, 0);
        }
        _failedDays.clear();
        _allChangedAt = ++_clock;
        _newestFillAt = 0;
        final shownFirst = _shownFirst;
        final shownLast = _shownLast;
        if (shownFirst != null && shownLast != null) {
          _send(shownFirst, shownLast, done: _waitingOn(waiters));
        }
        for (final span in others) {
          _send(span.first, span.last);
        }
        _pruneEntryTimes();
        _settleStatus();
        _notify();
      });
    };
  }

  /// The maximal runs of consecutive days of [days], ascending.
  static List<({int first, int last})> _runsOf(Iterable<int> days) {
    final sorted = days.toList()..sort();
    final runs = <({int first, int last})>[];
    for (final day in sorted) {
      if (runs.isNotEmpty && runs.last.last == day - 1) {
        runs[runs.length - 1] = (first: runs.last.first, last: day);
      } else {
        runs.add((first: day, last: day));
      }
    }
    return runs;
  }

  /// [spans] merged where they overlap or touch, less the shown range, which
  /// is read as a span of its own.
  List<({int first, int last})> _rereadSpans(
    List<({int first, int last})> spans,
  ) {
    spans.sort((a, b) {
      return a.first.compareTo(b.first);
    });
    final merged = <({int first, int last})>[];
    for (final span in spans) {
      if (merged.isNotEmpty && span.first <= merged.last.last + 1) {
        merged[merged.length - 1] = (
          first: merged.last.first,
          last: math.max(merged.last.last, span.last),
        );
      } else {
        merged.add(span);
      }
    }
    final shownFirst = _shownFirst;
    final shownLast = _shownLast;
    if (shownFirst == null || shownLast == null) {
      return merged;
    }
    final others = <({int first, int last})>[];
    for (final span in merged) {
      if (span.last < shownFirst || span.first > shownLast) {
        others.add(span);
        continue;
      }
      if (span.first < shownFirst) {
        others.add((first: span.first, last: shownFirst - 1));
      }
      if (span.last > shownLast) {
        others.add((first: shownLast + 1, last: span.last));
      }
    }
    return others;
  }

  /// A completer that passes its outcome to every one of [waiters], or null
  /// where none waits.
  Completer<void>? _waitingOn(List<Completer<void>> waiters) {
    if (waiters.isEmpty) {
      return null;
    }
    final passing = Completer<void>();
    unawaited(
      passing.future.then(
        (_) {
          for (final waiter in waiters) {
            waiter.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          for (final waiter in waiters) {
            waiter.completeError(error, stackTrace);
          }
        },
      ),
    );
    return passing;
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
