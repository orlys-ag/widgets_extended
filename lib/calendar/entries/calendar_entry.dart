/// One calendar entry: its id, its time, its title, its colour and the
/// host's payload.
library;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';
import '../dates/calendar_labels.dart';

/// The time of an entry as the overlap rule reads it: [firstDay] is a
/// [dayNumber], [dayCount] the consecutive days from it, and [start] and
/// [end] minutes after midnight on each of those days.
typedef CalendarEntryTime = ({int firstDay, int dayCount, int start, int end});

/// One entry of a calendar, carrying a payload of the host's type [T].
///
/// An entry covers [dayCount] consecutive days from [day], from
/// [startMinute] to [endMinute] on each of them. It is immutable, and two
/// entries are equal when every field is, the payload compared by its own
/// `==`.
@immutable
class CalendarEntry<T> {
  /// An entry from [startMinute] to [endMinute] on each of the [dayCount]
  /// days from [day], whose time of day is dropped.
  ///
  /// [dayCount] is at least 1, and `0 <= startMinute < endMinute <= 1440`.
  CalendarEntry({
    this.id,
    required DateTime day,
    required this.startMinute,
    required this.endMinute,
    this.dayCount = 1,
    required this.title,
    required this.color,
    required this.payload,
  }) : assert(dayCount >= 1, "An entry covers a day at least, not $dayCount."),
       assert(
         0 <= startMinute && startMinute < endMinute,
         "An entry starts at 0 or later and ends after its start, not "
         "$startMinute to $endMinute.",
       ),
       assert(
         endMinute <= minutesPerDay,
         "An entry ends at $minutesPerDay at the latest, not $endMinute.",
       ),
       day = dateOnly(day);

  /// The id naming this entry in a store, or null for a draft no store
  /// holds yet. Every entry a store answers has one.
  final String? id;

  /// The first day, at local midnight.
  final DateTime day;

  /// Minutes after midnight, on each day the entry covers.
  final int startMinute;

  /// Minutes after midnight, on each day the entry covers.
  final int endMinute;

  /// The consecutive days, from [day], that carry the same minutes.
  final int dayCount;

  final String title;

  final Color color;

  /// The host's value, compared by its own `==`.
  final T payload;

  /// The entry's days and minutes.
  CalendarEntryTime get time {
    return (
      firstDay: dayNumber(day),
      dayCount: dayCount,
      start: startMinute,
      end: endMinute,
    );
  }

  /// Whether the [dayNumber] [day] is one this entry covers.
  bool coversDay(int day) {
    final first = dayNumber(this.day);
    return day >= first && day < first + dayCount;
  }

  /// The [dayNumber]s of the days this entry covers, in order.
  Iterable<int> get dayNumbers {
    final first = dayNumber(day);
    return Iterable<int>.generate(dayCount, (index) {
      return first + index;
    });
  }

  /// This entry with each field given replaced. A null argument keeps the
  /// field, so a nullable [T] payload cannot be cleared through it.
  CalendarEntry<T> copyWith({
    String? id,
    DateTime? day,
    int? startMinute,
    int? endMinute,
    int? dayCount,
    String? title,
    Color? color,
    T? payload,
  }) {
    return CalendarEntry<T>(
      id: id ?? this.id,
      day: day ?? this.day,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      dayCount: dayCount ?? this.dayCount,
      title: title ?? this.title,
      color: color ?? this.color,
      payload: payload ?? this.payload,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarEntry<T> &&
        other.id == id &&
        other.day == day &&
        other.startMinute == startMinute &&
        other.endMinute == endMinute &&
        other.dayCount == dayCount &&
        other.title == title &&
        other.color == color &&
        other.payload == payload;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      day,
      startMinute,
      endMinute,
      dayCount,
      title,
      color,
      payload,
    );
  }

  @override
  String toString() {
    final days = dayCount == 1 ? "" : " x$dayCount";
    return "CalendarEntry(${id ?? "draft"}, ${isoDate(day)}$days "
        "${clockLabel(startMinute)}-${clockLabel(endMinute)}, \"$title\", "
        "$payload)";
  }
}
