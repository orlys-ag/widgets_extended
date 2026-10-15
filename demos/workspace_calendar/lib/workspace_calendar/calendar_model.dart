/// The calendar's view of the API: a cache of the days it has read, the
/// range the screen shows, and the lock that keeps one write per item.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'calendar_api.dart';
import 'calendar_data.dart';
import 'calendar_item.dart';
import 'calendar_schema.dart';
import 'calendar_settings.dart';

enum CalendarLoadStatus { loading, failed, ready }

/// What a write on a locked item reports in place of sending anything.
const String _lockedMessage = "This item has a change in progress.";

/// One `list` call in flight, over the [dayNumber]s [first] to [last].
class _Read {
  _Read(this.first, this.last);

  final int first;
  final int last;

  bool covers(int first, int last) {
    return this.first <= first && this.last >= last;
  }
}

/// The days read so far and the items on them, the shown range's load
/// state, and the writes in flight.
///
/// A day once read changes only by a confirmed write: a later read fills
/// only the days not read yet. A write locks its item from the call until
/// the API answers; while locked, the item shows [ShownItem.pending], and
/// a grid move or resize shows at its requested position everywhere. A
/// write on a locked item sends nothing and reports the refusal where
/// that write reports a failure, and so does one [hoursErrorsFor] finds
/// outside [hours].
class CalendarModel extends ChangeNotifier {
  CalendarModel({
    required CalendarApi api,
    required void Function(String message) onWriteFailed,
  }) : _api = api,
       _onWriteFailed = onWriteFailed;

  final CalendarApi _api;
  final void Function(String message) _onWriteFailed;

  /// Each read day, by [dayNumber], with the count of [show] calls made
  /// when it was read.
  final Map<int, int> _readDays = <int, int>{};

  /// The [show] calls that changed the shown range.
  int _showCount = 0;

  /// Every item the cache knows, by id.
  final Map<String, CalendarItem> _items = <String, CalendarItem>{};

  /// The ids covering each read day.
  final Map<int, Set<String>> _idsByDay = <int, Set<String>>{};

  /// The lock: an entry per item a write on it runs for. The value is the
  /// item to show meanwhile, or null to show the stored one.
  final Map<String, CalendarItem?> _pending = <String, CalendarItem?>{};

  /// The reads in flight, in the order they were sent.
  final List<_Read> _reads = <_Read>[];

  int? _shownFirst;
  int? _shownLast;

  /// The read the shown range waits on.
  _Read? _awaited;

  CalendarLoadStatus _status = CalendarLoadStatus.loading;
  String? _error;
  bool _disposed = false;

  /// The hours a new item, and a write that changes an item's days or
  /// minutes, must lie in. A write that keeps the stored days and minutes
  /// is not held to them, so an item that lay outside them when they
  /// changed can still be edited. Setting it notifies nothing: what shows
  /// does not depend on it.
  DayHours hours = DayHours.allDay;

  /// The rules [item] breaks against [hours], keyed as `validateItemJson`
  /// keys them. Empty when it keeps the days and minutes of the stored
  /// item its id names.
  Map<String, String> hoursErrorsFor(CalendarItem item) {
    final id = item.id;
    final stored = id == null ? null : _items[id];
    if (stored != null &&
        stored.day == item.day &&
        stored.dayCount == item.dayCount &&
        stored.startMinute == item.startMinute &&
        stored.endMinute == item.endMinute) {
      return const <String, String>{};
    }
    return hoursErrorsOf(item.startMinute, item.endMinute, hours);
  }

  /// Whether every day of the shown range is read, or the read it waits
  /// on failed. Loading before the first [show].
  CalendarLoadStatus get status {
    return _status;
  }

  /// The failed read's message while [status] is failed.
  String? get error {
    return _error;
  }

  /// Shows [first] to [last], both inclusive. A range whose days are all
  /// read is ready at once and sends nothing; otherwise the range waits on
  /// the earliest-sent read in flight that covers its unread days, or
  /// sends a `list` for them. Showing the range already shown changes
  /// nothing.
  void show(DateTime first, DateTime last) {
    final firstDay = dayNumber(first);
    final lastDay = dayNumber(last);
    if (firstDay == _shownFirst && lastDay == _shownLast) {
      return;
    }
    _shownFirst = firstDay;
    _shownLast = lastDay;
    _showCount++;
    _error = null;
    final unread = _unreadSpan();
    if (unread == null) {
      _awaited = null;
      _status = CalendarLoadStatus.ready;
    } else {
      _status = CalendarLoadStatus.loading;
      _awaited =
          _inFlightCovering(unread.first, unread.last) ??
          _send(unread.first, unread.last);
    }
    notifyListeners();
  }

  /// Whether the shown range is exactly [first] to [last].
  bool isShown(DateTime first, DateTime last) {
    return _shownFirst == dayNumber(first) && _shownLast == dayNumber(last);
  }

  /// Sends a new read for the shown range's unread days; with none unread
  /// it sends nothing and the range is ready.
  void retry() {
    if (_shownFirst == null) {
      return;
    }
    _error = null;
    final unread = _unreadSpan();
    if (unread == null) {
      _awaited = null;
      _status = CalendarLoadStatus.ready;
    } else {
      _status = CalendarLoadStatus.loading;
      _awaited = _send(unread.first, unread.last);
    }
    notifyListeners();
  }

  /// The first to the last unread day of the shown range, or null when
  /// every day of it is read.
  ({int first, int last})? _unreadSpan() {
    int? first;
    int? last;
    for (var day = _shownFirst!; day <= _shownLast!; day++) {
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

  _Read _send(int first, int last) {
    final read = _Read(first, last);
    _reads.add(read);
    _api
        .list(dateOfDayNumber(first), dateOfDayNumber(last))
        .then(
          (items) {
            _finishRead(read, items: items);
          },
          onError: (Object error) {
            _finishRead(read, error: error);
          },
        );
    return read;
  }

  /// A read's answer. A read the shown range does not wait on changes no
  /// shown state, so it notifies nothing.
  void _finishRead(
    _Read read, {
    List<Map<String, Object?>>? items,
    Object? error,
  }) {
    if (_disposed) {
      return;
    }
    _reads.remove(read);
    if (items != null) {
      _applyRead(read, items);
    }
    if (!identical(_awaited, read)) {
      return;
    }
    _awaited = null;
    // A failed read leaves the range ready when another read has filled
    // its days since.
    if (items != null || _unreadSpan() == null) {
      _status = CalendarLoadStatus.ready;
      _error = null;
    } else {
      _status = CalendarLoadStatus.failed;
      _error = _messageOf(error);
    }
    notifyListeners();
  }

  /// Adds the items the cache does not know, marks the read's unread days
  /// read, and indexes every cached item under those of them its cached
  /// shape covers, so a known item lies where the cache holds it whether
  /// or not the answer returned it there. A day already read keeps what it
  /// holds.
  void _applyRead(_Read read, List<Map<String, Object?>> items) {
    final fresh = <int>{};
    for (var day = read.first; day <= read.last; day++) {
      if (!_readDays.containsKey(day)) {
        _readDays[day] = _showCount;
        _idsByDay[day] = <String>{};
        fresh.add(day);
      }
    }
    for (final json in items) {
      final returned = CalendarItem.fromJson(json);
      _items.putIfAbsent(returned.id!, () {
        return returned;
      });
    }
    if (fresh.isEmpty) {
      return;
    }
    for (final item in _items.values) {
      final first = math.max(dayNumber(item.day), read.first);
      final last = math.min(dayNumber(item.day) + item.dayCount - 1, read.last);
      for (var day = first; day <= last; day++) {
        if (fresh.contains(day)) {
          _idsByDay[day]!.add(item.id!);
        }
      }
    }
  }

  /// The items shown on [day], sorted by start, end, title and id.
  List<ShownItem> itemsOn(DateTime day) {
    final number = dayNumber(day);
    final shown = <ShownItem>[];
    for (final id in _candidatesOn(number, number)) {
      final entry = _shownOf(id);
      if (entry != null && entry.item.coversDay(number)) {
        shown.add(entry);
      }
    }
    shown.sort(_compareShown);
    return shown;
  }

  /// The items shown on any day from [first] to [last], each once.
  List<ShownItem> itemsBetween(DateTime first, DateTime last) {
    final firstDay = dayNumber(first);
    final lastDay = dayNumber(last);
    final shown = <ShownItem>[];
    for (final id in _candidatesOn(firstDay, lastDay)) {
      final entry = _shownOf(id);
      if (entry == null) {
        continue;
      }
      final itemFirst = dayNumber(entry.item.day);
      final itemLast = itemFirst + entry.item.dayCount - 1;
      if (itemFirst <= lastDay && itemLast >= firstDay) {
        shown.add(entry);
      }
    }
    shown.sort(_compareShown);
    return shown;
  }

  /// Whether [day] shows a marker: it has shown items, and, while the
  /// shown range is not ready, it was read under an earlier [show] call.
  bool dayHasShownItems(DateTime day) {
    final number = dayNumber(day);
    final readAt = _readDays[number];
    if (readAt == null) {
      return false;
    }
    if (_status != CalendarLoadStatus.ready && readAt >= _showCount) {
      return false;
    }
    for (final id in _candidatesOn(number, number)) {
      final entry = _shownOf(id);
      if (entry != null && entry.item.coversDay(number)) {
        return true;
      }
    }
    return false;
  }

  /// Whether a write on [id] runs.
  bool isLocked(String id) {
    return _pending.containsKey(id);
  }

  /// The item as the API last confirmed it.
  CalendarItem? storedItem(String id) {
    return _items[id];
  }

  /// The ids indexed under the read days from [first] to [last], and every
  /// locked id, whose shown item may lie elsewhere.
  Set<String> _candidatesOn(int first, int last) {
    final ids = <String>{..._pending.keys};
    for (var day = first; day <= last; day++) {
      ids.addAll(_idsByDay[day] ?? const <String>{});
    }
    return ids;
  }

  ShownItem? _shownOf(String id) {
    final locked = _pending.containsKey(id);
    final item = _pending[id] ?? _items[id];
    if (item == null) {
      return null;
    }
    return ShownItem(item, pending: locked);
  }

  /// Stores [draft]; completes with the stored item, or fails with the
  /// API's error. Nothing is shown before the API answers. A draft outside
  /// [hours] sends nothing and fails with a [CalendarValidationException].
  Future<CalendarItem> create(CalendarItem draft) async {
    final errors = hoursErrorsFor(draft);
    if (errors.isNotEmpty) {
      throw CalendarValidationException(errors);
    }
    final json = await _api.create(draft.toJson());
    final created = CalendarItem.fromJson(json);
    if (!_disposed) {
      _applyConfirmed(created);
      notifyListeners();
    }
    return created;
  }

  /// Writes [item], whose id names a stored item; the item shows pending,
  /// as stored, until the API answers. Completes with the stored item, or
  /// fails with the API's error, which the caller reports: a failure does
  /// not reach `onWriteFailed`. It sends nothing and fails with a
  /// [CalendarValidationException] when [hoursErrorsFor] finds the item
  /// outside [hours], and with a [CalendarFailureException] on a locked
  /// item.
  Future<CalendarItem> update(CalendarItem item) async {
    final id = item.id!;
    final errors = hoursErrorsFor(item);
    if (errors.isNotEmpty) {
      throw CalendarValidationException(errors);
    }
    if (!_lock(id, null)) {
      throw const CalendarFailureException(_lockedMessage);
    }
    try {
      final json = await _api.update(id, item.toJson());
      final updated = CalendarItem.fromJson(json);
      if (!_disposed) {
        _applyConfirmed(updated);
        notifyListeners();
      }
      return updated;
    } on Object {
      if (!_disposed) {
        _pending.remove(id);
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Writes a grid move or resize: [requested] shows, pending, until the
  /// API answers. A failure shows the stored item again and reports
  /// through `onWriteFailed`. Sends nothing and reports through
  /// `onWriteFailed` instead for a move [hoursErrorsFor] finds outside
  /// [hours], for a locked item, and for one that would share time, under
  /// [itemsConflict], with another item on a read day it covers; a
  /// conflict on a day not read yet is left to the API.
  void requestMove(CalendarItem requested) {
    final id = requested.id!;
    final errors = hoursErrorsFor(requested);
    if (errors.isNotEmpty) {
      _onWriteFailed(CalendarValidationException(errors).message);
      return;
    }
    if (!isLocked(id)) {
      final conflicts = _conflictsOf(requested);
      if (conflicts.isNotEmpty) {
        _onWriteFailed(CalendarOverlapException(conflicts).message);
        return;
      }
    }
    if (!_lock(id, requested)) {
      _onWriteFailed(_lockedMessage);
      return;
    }
    _api
        .update(id, requested.toJson())
        .then(
          (json) {
            if (_disposed) {
              return;
            }
            _applyConfirmed(CalendarItem.fromJson(json));
            notifyListeners();
          },
          onError: (Object error) {
            _failWrite(id, error);
          },
        );
  }

  /// The ids of the shown items on [requested]'s read days, other than
  /// [requested] itself, that it may not share time with.
  List<String> _conflictsOf(CalendarItem requested) {
    final shape = requested.shape;
    final conflicts = <String>[];
    final last = addDays(requested.day, requested.dayCount - 1);
    for (final other in itemsBetween(requested.day, last)) {
      if (other.id != requested.id && itemsConflict(shape, other.item.shape)) {
        conflicts.add(other.id);
      }
    }
    return conflicts;
  }

  /// Deletes [id]: the stored item shows pending until the API answers,
  /// and leaves on success. A failure reports through `onWriteFailed`,
  /// and so does a call on a locked item, which sends nothing.
  void requestDelete(String id) {
    if (!_lock(id, null)) {
      _onWriteFailed(_lockedMessage);
      return;
    }
    _api
        .delete(id)
        .then(
          (_) {
            if (_disposed) {
              return;
            }
            _pending.remove(id);
            _forget(id);
            notifyListeners();
          },
          onError: (Object error) {
            _failWrite(id, error);
          },
        );
  }

  /// Locks [id], showing [shown] or, when null, the stored item. False,
  /// changing nothing, when [id] is locked already: every write on an id
  /// passes here, so an id has one write in flight at most.
  bool _lock(String id, CalendarItem? shown) {
    if (_pending.containsKey(id)) {
      return false;
    }
    _pending[id] = shown;
    notifyListeners();
    return true;
  }

  void _failWrite(String id, Object error) {
    if (_disposed) {
      return;
    }
    _pending.remove(id);
    notifyListeners();
    _onWriteFailed(_messageOf(error));
  }

  /// Releases the lock on [item]'s id, replaces the cached item and
  /// re-indexes it under the read days it covers.
  void _applyConfirmed(CalendarItem item) {
    final id = item.id!;
    _pending.remove(id);
    _forget(id);
    _items[id] = item;
    for (final day in item.dayNumbers) {
      _idsByDay[day]?.add(id);
    }
  }

  void _forget(String id) {
    final old = _items.remove(id);
    if (old == null) {
      return;
    }
    for (final day in old.dayNumbers) {
      _idsByDay[day]?.remove(id);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String _messageOf(Object? error) {
  if (error is CalendarApiException) {
    return error.message;
  }
  return "$error";
}

int _compareShown(ShownItem a, ShownItem b) {
  final x = a.item;
  final y = b.item;
  final byStart = x.startMinute.compareTo(y.startMinute);
  if (byStart != 0) {
    return byStart;
  }
  final byEnd = x.endMinute.compareTo(y.endMinute);
  if (byEnd != 0) {
    return byEnd;
  }
  final byTitle = x.title.compareTo(y.title);
  if (byTitle != 0) {
    return byTitle;
  }
  return a.id.compareTo(b.id);
}
