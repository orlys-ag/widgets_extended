/// One calendar entry: its id, its start and end, whether it is all-day,
/// its title, its colour and the host's payload.
library;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';

/// One entry of a calendar, carrying a payload of the host's type [T].
///
/// An entry runs from [start] to [end], an exclusive end, both local times
/// on whole minutes. It is all-day where [isAllDay], which it stores: its
/// [start] and [end] are then local midnights, dates rather than instants,
/// so a day of 23 or 25 hours is one whole day. Every other entry is timed,
/// whatever its times. It is immutable, and two entries are equal when
/// every field is, the payload compared by its own `==`.
@immutable
final class CalendarEntry<T> {
  /// An entry from [start] to [end], all-day where [isAllDay].
  ///
  /// Throws an [ArgumentError], in every build, naming the first of these
  /// rules a time breaks, in this order: [start] and then [end] is a local
  /// time, not UTC; [start] and then [end] has no second, millisecond or
  /// microsecond; [end] is after [start]; and for an all-day entry, [start]
  /// and then [end] is a local day start ([isDayStart]).
  CalendarEntry({
    this.id,
    required this.start,
    required this.end,
    required this.title,
    required this.color,
    required this.payload,
    this.isAllDay = false,
  }) {
    if (start.isUtc) {
      throw ArgumentError.value(
        start,
        "start",
        "An entry starts at a local time",
      );
    }
    if (end.isUtc) {
      throw ArgumentError.value(end, "end", "An entry ends at a local time");
    }
    if (start.second != 0 || start.millisecond != 0 || start.microsecond != 0) {
      throw ArgumentError.value(
        start,
        "start",
        "An entry starts on a whole minute",
      );
    }
    if (end.second != 0 || end.millisecond != 0 || end.microsecond != 0) {
      throw ArgumentError.value(end, "end", "An entry ends on a whole minute");
    }
    if (!end.isAfter(start)) {
      throw ArgumentError.value(
        end,
        "end",
        "An entry ends after its start, $start",
      );
    }
    if (isAllDay && !isDayStart(start)) {
      throw ArgumentError.value(
        start,
        "start",
        "An all-day entry starts at a local day start",
      );
    }
    if (isAllDay && !isDayStart(end)) {
      throw ArgumentError.value(
        end,
        "end",
        "An all-day entry ends at a local day start",
      );
    }
  }

  /// The id naming this entry in a store, or null for a draft no store
  /// holds yet. Every entry a store answers has one.
  final String? id;

  /// When the entry starts, a local time.
  final DateTime start;

  /// When the entry ends, a local time after [start]; the entry holds the
  /// time up to it, not the minute it names.
  final DateTime end;

  /// The entry's name, which the default builders draw and Month's chips
  /// give a screen reader; a store orders entries of the same start and
  /// end by it.
  final String title;

  /// The entry's colour, which the default builders fill its box with a
  /// tint of and draw its edge in.
  final Color color;

  /// The host's value, compared by its own `==`.
  final T payload;

  /// Whether the entry is all-day, stored as constructed: its [start] and
  /// [end] are then local midnights, dates rather than instants, and its
  /// [end], exclusive, is the midnight after its last day, so an entry over
  /// April 21 runs from `DateTime(2026, 4, 21)` to `DateTime(2026, 4, 22)`.
  /// False for a timed entry, whatever its times.
  final bool isAllDay;

  /// This entry with each field given replaced. A null argument keeps the
  /// field, so a nullable [T] payload cannot be cleared through it. It
  /// constructs the copy, so it throws the constructor's [ArgumentError]s.
  CalendarEntry<T> copyWith({
    String? id,
    DateTime? start,
    DateTime? end,
    String? title,
    Color? color,
    T? payload,
    bool? isAllDay,
  }) {
    return CalendarEntry<T>(
      id: id ?? this.id,
      start: start ?? this.start,
      end: end ?? this.end,
      title: title ?? this.title,
      color: color ?? this.color,
      payload: payload ?? this.payload,
      isAllDay: isAllDay ?? this.isAllDay,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarEntry<T> &&
        other.id == id &&
        other.start == start &&
        other.end == end &&
        other.isAllDay == isAllDay &&
        other.title == title &&
        other.color == color &&
        other.payload == payload;
  }

  @override
  int get hashCode {
    return Object.hash(id, start, end, isAllDay, title, color, payload);
  }

  @override
  String toString() {
    if (isAllDay) {
      return "CalendarEntry(${id ?? "draft"}, ${isoDate(start)} to "
          "${isoDate(end)}, all day, \"$title\", $payload)";
    }
    return "CalendarEntry(${id ?? "draft"}, ${isoDate(start)} "
        "${isoTime(minuteOfDay(start))} to ${isoDate(end)} "
        "${isoTime(minuteOfDay(end))}, \"$title\", $payload)";
  }
}
