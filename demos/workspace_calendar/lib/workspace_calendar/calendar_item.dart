/// The calendar's item: a [CalendarEntry] whose payload is the item's
/// type and fields, read from and written to the API's JSON envelope, and
/// the item as a view shows it.
library;

import 'package:flutter/foundation.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_schema.dart';
import 'harbor_theme.dart';

/// One calendar item: an entry whose payload is its [ItemPayload].
typedef CalendarItem = CalendarEntry<ItemPayload>;

/// An item as a view shows it: [CalendarShownEntry.pending] while a write
/// on it runs.
typedef ShownItem = CalendarShownEntry<ItemPayload>;

/// An item's type and the type's fields. Immutable: [fields] is an
/// unmodifiable deep copy of the map it was built from, so no map the
/// caller holds can change it and no map it hands out can change the API's
/// store. Two payloads are equal when their types are and their fields are
/// deeply.
@immutable
class ItemPayload {
  ItemPayload(
    this.type, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) : fields = _frozenCopy(fields);

  final CalendarItemType type;

  /// The type's payload. Unmodifiable, its lists too.
  final Map<String, Object?> fields;

  @override
  bool operator ==(Object other) {
    return other is ItemPayload &&
        other.type == type &&
        _jsonEquals(other.fields, fields);
  }

  @override
  int get hashCode {
    return Object.hash(type, _jsonHash(fields));
  }

  @override
  String toString() {
    return "ItemPayload(${type.id}, $fields)";
  }
}

/// An item's payload read as the item's own: its type, its fields and its
/// envelope.
extension CalendarItemFields on CalendarEntry<ItemPayload> {
  CalendarItemType get type {
    return payload.type;
  }

  /// The type's payload. Unmodifiable, its lists too.
  Map<String, Object?> get fields {
    return payload.fields;
  }

  /// The envelope, a new map each call. A draft carries no `id` key. Its
  /// `start` and `end` are the item's times as [itemTimeText] writes them:
  /// dates for an all-day item and instants in UTC for a timed one.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (id != null) "id": id,
      "type": type.id,
      "title": title,
      "start": itemTimeText(start, allDay: isAllDay),
      "end": itemTimeText(end, allDay: isAllDay),
      "fields": _modifiableCopy(fields),
    };
  }
}

/// An item of [type] with [fields], coloured by its type's Harbor edge;
/// [id] null for a draft the API has not stored. It runs from [start] to
/// [end], an exclusive end, and is all-day where [isAllDay], its [start]
/// and [end] then local midnights.
CalendarItem calendarItem({
  String? id,
  required CalendarItemType type,
  required String title,
  required DateTime start,
  required DateTime end,
  Map<String, Object?> fields = const <String, Object?>{},
  bool isAllDay = false,
}) {
  return CalendarItem(
    id: id,
    start: start,
    end: end,
    title: title,
    color: harborTypeStyleOf(type).edge,
    payload: ItemPayload(type, fields),
    isAllDay: isAllDay,
  );
}

/// Reads a valid envelope, its start and end as [parseItemTime] reads
/// them: an all-day item where they are dates, and a timed one where they
/// are date-times, whatever their times. Throws a [FormatException] when a
/// key is missing or of the wrong kind, the start and the end are of two
/// forms, or the end is not after the start.
CalendarItem itemFromJson(Map<String, Object?> json) {
  final typeId = json["type"];
  final type = typeId is String ? CalendarItemType.fromId(typeId) : null;
  final title = json["title"];
  final startText = json["start"];
  final start = startText is String ? parseItemTime(startText) : null;
  final endText = json["end"];
  final end = endText is String ? parseItemTime(endText) : null;
  final fields = json["fields"];
  final id = json["id"];
  if (type == null ||
      title is! String ||
      start == null ||
      end == null ||
      end.date != start.date ||
      !end.time.isAfter(start.time) ||
      fields is! Map<String, Object?> ||
      (id != null && id is! String)) {
    throw FormatException("Not a calendar item envelope: $json");
  }
  return calendarItem(
    id: id as String?,
    type: type,
    title: title,
    start: start.time,
    end: end.time,
    fields: fields,
    isAllDay: start.date,
  );
}

Map<String, Object?> _frozenCopy(Map<String, Object?> map) {
  return Map<String, Object?>.unmodifiable(
    map.map((key, value) {
      return MapEntry<String, Object?>(key, _frozenValue(value));
    }),
  );
}

Object? _frozenValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _frozenCopy(value);
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_frozenValue));
  }
  return value;
}

Map<String, Object?> _modifiableCopy(Map<String, Object?> map) {
  return map.map((key, value) {
    return MapEntry<String, Object?>(key, _modifiableValue(value));
  });
}

Object? _modifiableValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _modifiableCopy(value);
  }
  if (value is List) {
    return value.map(_modifiableValue).toList();
  }
  return value;
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) ||
          !_jsonEquals(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

int _jsonHash(Object? value) {
  if (value is Map<String, Object?>) {
    // Order-independent, as map equality is.
    var hash = 0;
    for (final entry in value.entries) {
      hash ^= Object.hash(entry.key, _jsonHash(entry.value));
    }
    return hash;
  }
  if (value is List) {
    return Object.hashAll(value.map(_jsonHash));
  }
  return value.hashCode;
}
