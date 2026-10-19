/// The calendar's item: a [CalendarEntry] whose payload is the item's
/// type and fields, read from and written to the API's JSON envelope, and
/// the item as a view shows it.
library;

import 'package:flutter/foundation.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';

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

  /// The envelope, a new map each call. A draft carries no `id` key.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (id != null) "id": id,
      "type": type.id,
      "title": title,
      "day": isoDate(day),
      "startMinute": startMinute,
      "endMinute": endMinute,
      "dayCount": dayCount,
      "fields": _modifiableCopy(fields),
    };
  }
}

/// An item of [type] with [fields], coloured by its type's Harbor edge;
/// [id] null for a draft the API has not stored.
CalendarItem calendarItem({
  String? id,
  required CalendarItemType type,
  required String title,
  required DateTime day,
  required int startMinute,
  required int endMinute,
  int dayCount = 1,
  Map<String, Object?> fields = const <String, Object?>{},
}) {
  return CalendarItem(
    id: id,
    day: day,
    startMinute: startMinute,
    endMinute: endMinute,
    dayCount: dayCount,
    title: title,
    color: harborTypeStyleOf(type).edge,
    payload: ItemPayload(type, fields),
  );
}

/// Reads a valid envelope. Throws a [FormatException] when a key is
/// missing or of the wrong kind.
CalendarItem itemFromJson(Map<String, Object?> json) {
  final typeId = json["type"];
  final type = typeId is String ? CalendarItemType.fromId(typeId) : null;
  final dayText = json["day"];
  final day = dayText is String ? parseIsoDate(dayText) : null;
  final title = json["title"];
  final start = json["startMinute"];
  final end = json["endMinute"];
  final dayCount = json["dayCount"];
  final fields = json["fields"];
  final id = json["id"];
  if (type == null ||
      day == null ||
      title is! String ||
      start is! int ||
      end is! int ||
      dayCount is! int ||
      fields is! Map<String, Object?> ||
      (id != null && id is! String)) {
    throw FormatException("Not a calendar item envelope: $json");
  }
  return calendarItem(
    id: id as String?,
    type: type,
    title: title,
    day: day,
    startMinute: start,
    endMinute: end,
    dayCount: dayCount,
    fields: fields,
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
