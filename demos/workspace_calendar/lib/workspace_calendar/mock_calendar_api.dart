/// An in-memory [CalendarApi] that answers each call after a latency, as
/// a server would, and fails the calls a policy names.
library;

import 'dart:async';

import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/policy/overlap.dart';

import 'calendar_api.dart';
import 'calendar_item.dart';
import 'calendar_schema.dart';
import 'calendar_seed.dart';

/// How long a [MockCalendarApi] takes to answer a call unless told
/// otherwise.
const Duration defaultCalendarLatency = Duration(milliseconds: 600);

class MockCalendarApi implements CalendarApi {
  /// A store holding [seed], checked entry by entry, in order, as a create
  /// is: an entry that breaks a rule of its type, or overlaps an earlier
  /// entry the overlap rule keeps apart, throws an [ArgumentError].
  ///
  /// Every call completes [latency] after it arrives, and only then
  /// changes the store. [failurePolicy] is asked once per call, when it
  /// arrives; a message it returns fails the call, which then changes
  /// nothing.
  MockCalendarApi({
    Iterable<Map<String, Object?>> seed = const <Map<String, Object?>>[],
    this.latency = defaultCalendarLatency,
    this.failurePolicy,
  }) {
    for (final entry in seed) {
      final body = _prepared(_copyMap(entry));
      final errors = validateItemJson(body);
      if (errors.isNotEmpty) {
        throw ArgumentError.value(entry, "seed", "Invalid entry: $errors");
      }
      final conflicts = _conflictsOf(body, null);
      if (conflicts.isNotEmpty) {
        throw ArgumentError.value(entry, "seed", "Overlaps $conflicts");
      }
      _store(_nextId(), body);
    }
  }

  /// A store holding [defaultCalendarSeed] around [today].
  factory MockCalendarApi.seeded(
    DateTime today, {
    Duration latency = defaultCalendarLatency,
    CalendarFailurePolicy? failurePolicy,
  }) {
    return MockCalendarApi(
      seed: defaultCalendarSeed(today),
      latency: latency,
      failurePolicy: failurePolicy,
    );
  }

  final Duration latency;

  /// Read on every call, so a test may replace it between calls.
  CalendarFailurePolicy? failurePolicy;

  final List<CalendarRequest> _requests = <CalendarRequest>[];

  /// The stored envelopes by id.
  final Map<String, Map<String, Object?>> _items =
      <String, Map<String, Object?>>{};

  /// The ids covering each day, by [dayNumber]. A day no item covers has
  /// no entry.
  final Map<int, Set<String>> _idsByDay = <int, Set<String>>{};

  int _createdCount = 0;

  /// Every call received, in arrival order.
  List<CalendarRequest> get requests {
    return List<CalendarRequest>.unmodifiable(_requests);
  }

  @override
  Future<List<Map<String, Object?>>> list(DateTime first, DateTime last) {
    return _call(
      CalendarRequest(
        method: CalendarMethod.list,
        first: dateOnly(first),
        last: dateOnly(last),
      ),
      () {
        final ids = <String>{};
        for (var day = dayNumber(first); day <= dayNumber(last); day++) {
          ids.addAll(_idsByDay[day] ?? const <String>{});
        }
        final items = <Map<String, Object?>>[for (final id in ids) _items[id]!];
        items.sort(_compareStored);
        return <Map<String, Object?>>[for (final item in items) _copyMap(item)];
      },
    );
  }

  @override
  Future<Map<String, Object?>> get(String id) {
    return _call(CalendarRequest(method: CalendarMethod.get, id: id), () {
      return _copyMap(_storedOrThrow(id));
    });
  }

  @override
  Future<Map<String, Object?>> create(Map<String, Object?> item) {
    final body = _copyMap(item);
    return _call(
      CalendarRequest(method: CalendarMethod.create, body: _copyMap(body)),
      () {
        final prepared = _prepared(body);
        final errors = validateItemJson(prepared);
        if (errors.isNotEmpty) {
          throw CalendarValidationException(errors);
        }
        final conflicts = _conflictsOf(prepared, null);
        if (conflicts.isNotEmpty) {
          throw CalendarOverlapException(conflicts);
        }
        return _copyMap(_store(_nextId(), prepared));
      },
    );
  }

  @override
  Future<Map<String, Object?>> update(String id, Map<String, Object?> item) {
    final body = _copyMap(item);
    return _call(
      CalendarRequest(
        method: CalendarMethod.update,
        id: id,
        body: _copyMap(body),
      ),
      () {
        final stored = _storedOrThrow(id);
        final prepared = _prepared(body);
        final errors = validateItemJson(prepared);
        if (prepared["type"] != stored["type"]) {
          errors["type"] = "An item's type cannot change.";
        }
        if (errors.isNotEmpty) {
          throw CalendarValidationException(errors);
        }
        final conflicts = _conflictsOf(prepared, id);
        if (conflicts.isNotEmpty) {
          throw CalendarOverlapException(conflicts);
        }
        _unstore(id);
        return _copyMap(_store(id, prepared));
      },
    );
  }

  @override
  Future<void> delete(String id) {
    return _call(CalendarRequest(method: CalendarMethod.delete, id: id), () {
      _storedOrThrow(id);
      _unstore(id);
    });
  }

  /// Records [request], asks the policy, and completes after [latency]
  /// through [_complete].
  Future<T> _call<T>(CalendarRequest request, T Function() apply) {
    _requests.add(request);
    final failure = failurePolicy?.call(request);
    final completer = Completer<T>();
    Timer(latency, () {
      _complete(completer, failure, apply);
    });
    return completer.future;
  }

  /// Completes [completer] with the policy's [failure], changing nothing,
  /// or with what [apply] returns or throws.
  void _complete<T>(
    Completer<T> completer,
    String? failure,
    T Function() apply,
  ) {
    if (failure != null) {
      completer.completeError(CalendarFailureException(failure));
      return;
    }
    try {
      completer.complete(apply());
    } on CalendarApiException catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }

  String _nextId() {
    _createdCount++;
    return "item-$_createdCount";
  }

  Map<String, Object?> _storedOrThrow(String id) {
    final stored = _items[id];
    if (stored == null) {
      throw CalendarNotFoundException(id);
    }
    return stored;
  }

  /// [body] without an `id`, its payload completed with the type's
  /// defaults where the type is known and the payload is a map; the
  /// validator reports anything else.
  Map<String, Object?> _prepared(Map<String, Object?> body) {
    final prepared = Map<String, Object?>.of(body)..remove("id");
    final typeId = prepared["type"];
    final type = typeId is String ? CalendarItemType.fromId(typeId) : null;
    final fields = prepared["fields"];
    if (type != null && fields is Map<String, Object?>) {
      prepared["fields"] = withFieldDefaults(type, fields);
    }
    return prepared;
  }

  /// The stored ids, other than [ownId], that the valid [body] may not
  /// share time with ([entriesShareTime]), read from the index of the days
  /// it covers.
  List<String> _conflictsOf(Map<String, Object?> body, String? ownId) {
    final item = itemFromJson(body);
    final seen = <String>{};
    final conflicts = <String>[];
    final last = lastDayNumberOf(item.start, item.end);
    for (var day = dayNumber(item.start); day <= last; day++) {
      for (final id in _idsByDay[day] ?? const <String>{}) {
        if (id == ownId || !seen.add(id)) {
          continue;
        }
        if (entriesShareTime(item, itemFromJson(_items[id]!))) {
          conflicts.add(id);
        }
      }
    }
    conflicts.sort(_compareIds);
    return conflicts;
  }

  /// Stores the valid [body] as [id], its start and end written as
  /// [isoDateTime] writes them, whichever form they came in, so the stored
  /// texts sort as their instants do ([_compareStored]).
  Map<String, Object?> _store(String id, Map<String, Object?> body) {
    final stored = <String, Object?>{
      ...body,
      "id": id,
      "start": isoDateTime(parseIsoDateTime(body["start"]! as String)!),
      "end": isoDateTime(parseIsoDateTime(body["end"]! as String)!),
    };
    _items[id] = stored;
    for (final day in _coveredDaysOf(stored)) {
      _idsByDay
          .putIfAbsent(day, () {
            return <String>{};
          })
          .add(id);
    }
    return stored;
  }

  void _unstore(String id) {
    final stored = _items.remove(id);
    if (stored == null) {
      return;
    }
    for (final day in _coveredDaysOf(stored)) {
      final ids = _idsByDay[day];
      if (ids == null) {
        continue;
      }
      ids.remove(id);
      if (ids.isEmpty) {
        _idsByDay.remove(day);
      }
    }
  }
}

/// The [dayNumber]s of the days the stored envelope [stored] has a part
/// in, from its start's day to [lastDayNumberOf].
Iterable<int> _coveredDaysOf(Map<String, Object?> stored) sync* {
  final item = itemFromJson(stored);
  final last = lastDayNumberOf(item.start, item.end);
  for (var day = dayNumber(item.start); day <= last; day++) {
    yield day;
  }
}

/// By start, then creation order. A stored start text sorts as its
/// instant does: [MockCalendarApi._store] keeps it in UTC as
/// [isoDateTime] writes it, its fields in order, each zero-padded, on a
/// whole minute.
int _compareStored(Map<String, Object?> a, Map<String, Object?> b) {
  final byStart = (a["start"] as String).compareTo(b["start"] as String);
  if (byStart != 0) {
    return byStart;
  }
  return _compareIds(a["id"] as String, b["id"] as String);
}

/// Creation order: the number after `item-`.
int _compareIds(String a, String b) {
  final byNumber = _idNumber(a).compareTo(_idNumber(b));
  return byNumber != 0 ? byNumber : a.compareTo(b);
}

int _idNumber(String id) {
  return int.tryParse(id.substring(id.indexOf("-") + 1)) ?? 0;
}

Map<String, Object?> _copyMap(Map<String, Object?> map) {
  return map.map((key, value) {
    return MapEntry<String, Object?>(key, _copyValue(value));
  });
}

Object? _copyValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _copyMap(value);
  }
  if (value is List) {
    return value.map(_copyValue).toList();
  }
  return value;
}
