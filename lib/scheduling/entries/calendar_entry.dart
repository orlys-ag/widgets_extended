/// One calendar entry, [CalendarEntry]: its id, its start and end, whether
/// it is all-day, its title, its colour and the host's payload; and the
/// range of time a create gesture picks, [CalendarCreateRange], whose times
/// an entry takes.
library;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';

/// One entry of a calendar, carrying a payload of the host's type [T].
///
/// An entry runs from [start] to [end], an exclusive end, both on whole
/// minutes: local times, or `TZDateTime`s of the zone of a store given one.
/// It is all-day where [isAllDay], which it stores: its [start] and [end]
/// are then the starts of their days, the local midnights or the first
/// instants the zone's clock reads those dates, dates rather than instants,
/// so a day of 23 or 25 hours is one whole day. Every other entry is timed,
/// whatever its times. It is immutable, and two entries are equal when
/// every field is, the payload compared by its own `==` and times compared
/// as instants where either carries a zone.
@immutable
final class CalendarEntry<T> {
  /// An entry from [start] to [end], all-day where [isAllDay].
  ///
  /// Throws an [ArgumentError], in every build, naming the first of these
  /// rules a time breaks, in this order: [start] and then [end] is a local
  /// time or a `TZDateTime`, not a plain UTC time; [start] and then [end]
  /// has no second, millisecond or microsecond on its clock; [end] is after
  /// [start]; and for an all-day entry, [start] and then [end] is the start
  /// of its day on its clock ([CalendarDates.isDayStart]).
  CalendarEntry({
    this.id,
    required this.start,
    required this.end,
    required this.title,
    required this.color,
    required this.payload,
    this.isAllDay = false,
  }) {
    if (start.isUtc && start is! TZDateTime) {
      throw ArgumentError.value(
        start,
        "start",
        "An entry starts at a local or a zoned time",
      );
    }
    if (end.isUtc && end is! TZDateTime) {
      throw ArgumentError.value(
        end,
        "end",
        "An entry ends at a local or a zoned time",
      );
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
    if (isAllDay && !CalendarDates.isDayStart(start)) {
      throw ArgumentError.value(
        start,
        "start",
        "An all-day entry starts at the start of its day on its clock",
      );
    }
    if (isAllDay && !CalendarDates.isDayStart(end)) {
      throw ArgumentError.value(
        end,
        "end",
        "An all-day entry ends at the start of its day on its clock",
      );
    }
  }

  /// The id naming this entry in a store, or null for a draft no store
  /// holds yet. Every entry a store answers has one.
  final String? id;

  /// When the entry starts, a local time or a `TZDateTime`.
  final DateTime start;

  /// When the entry ends, a local time or a `TZDateTime` after [start]; the
  /// entry holds the time up to it, not the minute it names.
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
  /// [end] are then the starts of their days on their clock, dates rather
  /// than instants, and its [end], exclusive, is the start of the day after
  /// its last day, so an entry over April 21 runs from
  /// `DateTime(2026, 4, 21)` to `DateTime(2026, 4, 22)`. False for a timed
  /// entry, whatever its times.
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
        sameTime(other.start, start) &&
        sameTime(other.end, end) &&
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
      return "CalendarEntry(${id ?? "draft"}, "
          "${CalendarDates.isoDate(start)} to "
          "${CalendarDates.isoDate(end)}, all day, \"$title\", $payload)";
    }
    return "CalendarEntry(${id ?? "draft"}, ${CalendarDates.isoDate(start)} "
        "${CalendarDates.isoTime(CalendarDates.minuteOfDay(start))} to "
        "${CalendarDates.isoDate(end)} "
        "${CalendarDates.isoTime(CalendarDates.minuteOfDay(end))}, "
        "\"$title\", $payload)";
  }
}

/// The time a create gesture picked: one continuous range from [start] to
/// [end], an exclusive end, both local times or `TZDateTime`s, all-day where
/// [isAllDay].
@immutable
final class CalendarCreateRange {
  /// The range from [start] to [end], all-day where [isAllDay], as the
  /// gesture that picked it tells it.
  ///
  /// Throws an [ArgumentError], in every build, naming the first of
  /// [CalendarEntry]'s rules its times break, in [CalendarEntry]'s order,
  /// so an entry of its times constructs: [start] and then [end] is a local
  /// time or a `TZDateTime`, not a plain UTC time; [start] and then [end]
  /// has no second, millisecond or microsecond on its clock; [end] is after
  /// [start]; and for an all-day range, [start] and then [end] is the start
  /// of its day on its clock ([CalendarDates.isDayStart]).
  CalendarCreateRange({
    required this.start,
    required this.end,
    this.isAllDay = false,
  }) {
    if (start.isUtc && start is! TZDateTime) {
      throw ArgumentError.value(
        start,
        "start",
        "A range starts at a local or a zoned time",
      );
    }
    if (end.isUtc && end is! TZDateTime) {
      throw ArgumentError.value(
        end,
        "end",
        "A range ends at a local or a zoned time",
      );
    }
    if (start.second != 0 || start.millisecond != 0 || start.microsecond != 0) {
      throw ArgumentError.value(
        start,
        "start",
        "A range starts on a whole minute",
      );
    }
    if (end.second != 0 || end.millisecond != 0 || end.microsecond != 0) {
      throw ArgumentError.value(end, "end", "A range ends on a whole minute");
    }
    if (!end.isAfter(start)) {
      throw ArgumentError.value(
        end,
        "end",
        "A range ends after its start, $start",
      );
    }
    if (isAllDay && !CalendarDates.isDayStart(start)) {
      throw ArgumentError.value(
        start,
        "start",
        "An all-day range starts at the start of its day on its clock",
      );
    }
    if (isAllDay && !CalendarDates.isDayStart(end)) {
      throw ArgumentError.value(
        end,
        "end",
        "An all-day range ends at the start of its day on its clock",
      );
    }
  }

  /// Where the range starts.
  final DateTime start;

  /// Where the range ends, after [start].
  final DateTime end;

  /// Whether the range is all-day, stored as constructed: true for a range
  /// a create across the all-day strip picks, whose [start] and [end] are
  /// day starts, and false for every other, a range of slots from a day
  /// start to a day start included.
  final bool isAllDay;

  @override
  bool operator ==(Object other) {
    return other is CalendarCreateRange &&
        sameTime(other.start, start) &&
        sameTime(other.end, end) &&
        other.isAllDay == isAllDay;
  }

  @override
  int get hashCode {
    return Object.hash(start, end, isAllDay);
  }

  @override
  String toString() {
    return "CalendarCreateRange("
        "${CalendarDates.isoDate(start)} "
        "${CalendarDates.isoTime(CalendarDates.minuteOfDay(start))} "
        "to ${CalendarDates.isoDate(end)} "
        "${CalendarDates.isoTime(CalendarDates.minuteOfDay(end))}"
        "${isAllDay ? ", all day" : ""})";
  }
}

/// [entry] as a store given [zone] holds it: each time of a timed entry a
/// `TZDateTime` of [zone] at its instant, and an all-day entry at [zone]'s
/// day starts of the same dates. With no [zone], [deviceEntryOf]'s answer.
/// A time already in that form is kept, and an entry none of whose times
/// changes is answered itself.
///
/// Throws an [ArgumentError], naming `start` or `end` and the time, for a
/// time of [zone] whose offset is not a whole number of minutes, and for
/// an all-day date [zone]'s clock skips altogether.
CalendarEntry<T> zonedEntryOf<T>(CalendarEntry<T> entry, Location? zone) {
  if (zone == null) {
    return deviceEntryOf(entry);
  }
  final start = _zonedTimeIn(entry.start, "start", zone, entry.isAllDay);
  final end = _zonedTimeIn(entry.end, "end", zone, entry.isAllDay);
  if (identical(start, entry.start) && identical(end, entry.end)) {
    return entry;
  }
  return entry.copyWith(start: start, end: end);
}

/// [entry] in the form a data source takes: each time of a timed entry a
/// plain local time at its instant, and an all-day entry's times the plain
/// local midnights of the same dates. [entry] itself where neither time is
/// a `TZDateTime`.
CalendarEntry<T> deviceEntryOf<T>(CalendarEntry<T> entry) {
  if (entry.start is! TZDateTime && entry.end is! TZDateTime) {
    return entry;
  }
  if (entry.isAllDay) {
    return entry.copyWith(
      start: DateTime(entry.start.year, entry.start.month, entry.start.day),
      end: DateTime(entry.end.year, entry.end.month, entry.end.day),
    );
  }
  return entry.copyWith(
    start: DateTime.fromMillisecondsSinceEpoch(
      entry.start.millisecondsSinceEpoch,
    ),
    end: DateTime.fromMillisecondsSinceEpoch(entry.end.millisecondsSinceEpoch),
  );
}

/// [time], named [name], as [zonedEntryOf] holds it: of an all-day entry,
/// [zone]'s day start of its date, unless it is a `TZDateTime` of [zone],
/// which the entry's constructor took as such a day start; of a timed one,
/// [zonedTimeOf]'s.
DateTime _zonedTimeIn(
  DateTime time,
  String name,
  Location zone,
  bool isAllDay,
) {
  final DateTime zoned;
  if (time is TZDateTime && time.location == zone) {
    zoned = time;
  } else if (isAllDay) {
    final number = CalendarDates.dayNumber(time);
    zoned = CalendarDates.dateOfDayNumber(number, zone: zone);
    // Where the clock skips the date whole, the day's start reads a later
    // one.
    if (CalendarDates.dayNumber(zoned) != number) {
      throw ArgumentError.value(
        time,
        name,
        "${zone.name}'s clock skips the date of this all-day time",
      );
    }
  } else {
    zoned = TZDateTime.from(time, zone);
  }
  if (zoned.timeZoneOffset.inMicroseconds % Duration.microsecondsPerMinute !=
      0) {
    throw ArgumentError.value(
      time,
      name,
      "${zone.name}'s offset at this time is not a whole number of minutes",
    );
  }
  return zoned;
}
