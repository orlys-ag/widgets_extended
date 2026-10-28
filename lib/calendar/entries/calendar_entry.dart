/// One calendar entry: its id, its start and end, its title, its colour
/// and the host's payload.
library;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';

/// One entry of a calendar, carrying a payload of the host's type [T].
///
/// An entry runs from [start] to [end], an exclusive end, both local
/// times on whole minutes. One from a day start to a day start covers
/// whole days and is all-day ([isAllDay]); any other is timed. It is
/// immutable, and two entries are equal when every field is, the payload
/// compared by its own `==`.
@immutable
class CalendarEntry<T> {
  /// An entry from [start] to [end].
  ///
  /// In a debug build each of these is asserted on its own: [start] and
  /// [end] are local times with no second, millisecond or microsecond, and
  /// [end] is after [start]. A release build stores what it is given.
  CalendarEntry({
    this.id,
    required this.start,
    required this.end,
    required this.title,
    required this.color,
    required this.payload,
  }) : assert(!start.isUtc, "An entry starts at a local time, not $start."),
       assert(!end.isUtc, "An entry ends at a local time, not $end."),
       assert(start.second == 0, "An entry starts on a whole minute."),
       assert(start.millisecond == 0, "An entry starts on a whole minute."),
       assert(start.microsecond == 0, "An entry starts on a whole minute."),
       assert(end.second == 0, "An entry ends on a whole minute."),
       assert(end.millisecond == 0, "An entry ends on a whole minute."),
       assert(end.microsecond == 0, "An entry ends on a whole minute."),
       assert(
         end.isAfter(start),
         "An entry ends after its start, not $start to $end.",
       );

  /// The id naming this entry in a store, or null for a draft no store
  /// holds yet. Every entry a store answers has one.
  final String? id;

  /// When the entry starts, a local time.
  final DateTime start;

  /// When the entry ends, a local time after [start]; the entry holds the
  /// time up to it, not the minute it names.
  final DateTime end;

  final String title;

  final Color color;

  /// The host's value, compared by its own `==`.
  final T payload;

  /// Whether the entry covers whole days: [start] and [end] are each the
  /// start of a day ([isDayStart]), so a day of 23 or 25 hours is one
  /// whole day.
  bool get isAllDay {
    return isDayStart(start) && isDayStart(end);
  }

  /// This entry with each field given replaced. A null argument keeps the
  /// field, so a nullable [T] payload cannot be cleared through it.
  CalendarEntry<T> copyWith({
    String? id,
    DateTime? start,
    DateTime? end,
    String? title,
    Color? color,
    T? payload,
  }) {
    return CalendarEntry<T>(
      id: id ?? this.id,
      start: start ?? this.start,
      end: end ?? this.end,
      title: title ?? this.title,
      color: color ?? this.color,
      payload: payload ?? this.payload,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarEntry<T> &&
        other.id == id &&
        other.start == start &&
        other.end == end &&
        other.title == title &&
        other.color == color &&
        other.payload == payload;
  }

  @override
  int get hashCode {
    return Object.hash(id, start, end, title, color, payload);
  }

  @override
  String toString() {
    return "CalendarEntry(${id ?? "draft"}, ${isoDate(start)} "
        "${isoTime(minuteOfDay(start))} to ${isoDate(end)} "
        "${isoTime(minuteOfDay(end))}, \"$title\", $payload)";
  }
}
