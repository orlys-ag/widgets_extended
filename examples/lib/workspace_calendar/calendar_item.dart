/// The calendar's item value, read from and written to the API's JSON
/// envelope, and the item as a view shows it.
library;

import 'package:flutter/foundation.dart';

import 'calendar_data.dart';
import 'calendar_schema.dart';

/// One calendar item. Immutable: its payload is an unmodifiable deep copy
/// of the map it was built from, so no map the caller holds can change it
/// and no map it hands out can change the API's store.
@immutable
class CalendarItem {
  CalendarItem({
    this.id,
    required this.type,
    required this.title,
    required DateTime day,
    required this.startMinute,
    required this.endMinute,
    this.dayCount = 1,
    Map<String, Object?> fields = const <String, Object?>{},
  }) : day = dateOnly(day),
       fields = _frozenCopy(fields);

  /// Reads a valid envelope. Throws a [FormatException] when a key is
  /// missing or of the wrong kind.
  factory CalendarItem.fromJson(Map<String, Object?> json) {
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
    return CalendarItem(
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

  /// The API's id, or null for a draft the API has not stored.
  final String? id;

  final CalendarItemType type;
  final String title;

  /// The first day, at local midnight.
  final DateTime day;

  /// Minutes after midnight, on each day the item covers.
  final int startMinute;

  /// Minutes after midnight, on each day the item covers.
  final int endMinute;

  /// The consecutive days, from [day], that carry the same hours.
  final int dayCount;

  /// The type's payload. Unmodifiable, its lists too.
  final Map<String, Object?> fields;

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

  CalendarItem copyWith({
    String? title,
    DateTime? day,
    int? startMinute,
    int? endMinute,
    int? dayCount,
    Map<String, Object?>? fields,
  }) {
    return CalendarItem(
      id: id,
      type: type,
      title: title ?? this.title,
      day: day ?? this.day,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      dayCount: dayCount ?? this.dayCount,
      fields: fields ?? this.fields,
    );
  }

  ItemShape get shape {
    return (
      type: type,
      firstDay: dayNumber(day),
      dayCount: dayCount,
      start: startMinute,
      end: endMinute,
    );
  }

  /// Whether the [dayNumber] [day] is one this item covers.
  bool coversDay(int day) {
    final first = dayNumber(this.day);
    return day >= first && day < first + dayCount;
  }

  /// The [dayNumber]s of the days this item covers, in order.
  Iterable<int> get dayNumbers {
    final first = dayNumber(day);
    return Iterable<int>.generate(dayCount, (index) {
      return first + index;
    });
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarItem &&
        other.id == id &&
        other.type == type &&
        other.title == title &&
        other.day == day &&
        other.startMinute == startMinute &&
        other.endMinute == endMinute &&
        other.dayCount == dayCount &&
        _jsonEquals(other.fields, fields);
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      type,
      title,
      day,
      startMinute,
      endMinute,
      dayCount,
      _jsonHash(fields),
    );
  }

  @override
  String toString() {
    return "CalendarItem(${toJson()})";
  }
}

/// An item as a view shows it: [pending] while a write on it runs.
@immutable
class ShownItem {
  const ShownItem(this.item, {required this.pending});

  final CalendarItem item;
  final bool pending;

  /// The item's id. A shown item is always a stored one.
  String get id {
    return item.id!;
  }

  @override
  bool operator ==(Object other) {
    return other is ShownItem && other.item == item && other.pending == pending;
  }

  @override
  int get hashCode {
    return Object.hash(item, pending);
  }

  @override
  String toString() {
    return "ShownItem($id, pending: $pending)";
  }
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
