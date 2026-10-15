/// What the calendar's settings choose: the weekdays it shows, the hours
/// it shows and schedules in, and the size of the timed grid's cells.
library;

import 'package:flutter/foundation.dart';

import 'calendar_data.dart';
import 'calendar_schema.dart';

/// A set of weekdays, each named by its [weekdayColumn]: Monday is 0 and
/// Sunday 6.
@immutable
class WeekdaySet {
  const WeekdaySet._(this._bits);

  /// The weekdays [columns] names, each 0 to 6.
  factory WeekdaySet.of(Iterable<int> columns) {
    var bits = 0;
    for (final column in columns) {
      assert(
        column >= 0 && column < DateTime.daysPerWeek,
        "A weekday column is 0 to 6, not $column.",
      );
      bits |= 1 << column;
    }
    return WeekdaySet._(bits);
  }

  /// Every day of the week.
  static const WeekdaySet all = WeekdaySet._(0x7F);

  /// Monday to Friday.
  static const WeekdaySet workweek = WeekdaySet._(0x1F);

  /// Bit `n` is set when the set holds the column `n`.
  final int _bits;

  bool get isEmpty {
    return _bits == 0;
  }

  /// Whether the set holds the weekday column [column].
  bool containsColumn(int column) {
    return _bits & (1 << column) != 0;
  }

  /// Whether the set holds the weekday of the [dayNumber] [day].
  bool containsDay(int day) {
    return containsColumn(weekdayColumnOfDay(day));
  }

  /// Whether the set holds the weekday of [date].
  bool containsDate(DateTime date) {
    return containsColumn(weekdayColumn(date));
  }

  @override
  bool operator ==(Object other) {
    return other is WeekdaySet && other._bits == _bits;
  }

  @override
  int get hashCode {
    return _bits.hashCode;
  }

  @override
  String toString() {
    final names = <String>[
      for (var column = 0; column < DateTime.daysPerWeek; column++)
        if (containsColumn(column)) weekdayShortNames[column],
    ];
    return "WeekdaySet(${names.join(", ")})";
  }
}

/// The part of each day the calendar shows and schedules in: from [start]
/// to [end] minutes after midnight, in whole slots.
@immutable
class DayHours {
  const DayHours(this.start, this.end)
    : assert(start >= 0 && start % minutesPerSlot == 0),
      assert(end <= minutesPerDay && end % minutesPerSlot == 0),
      assert(start < end);

  /// The whole day, 00:00 to 24:00.
  static const DayHours allDay = DayHours(0, minutesPerDay);

  final int start;
  final int end;

  /// The slots from [start] to [end].
  int get slotCount {
    return (end - start) ~/ minutesPerSlot;
  }

  /// Whether the minutes [from] to [to] lie inside these hours.
  bool contains(int from, int to) {
    return from >= start && to <= end;
  }

  @override
  bool operator ==(Object other) {
    return other is DayHours && other.start == start && other.end == end;
  }

  @override
  int get hashCode {
    return Object.hash(start, end);
  }

  @override
  String toString() {
    return "DayHours(${clockLabel(start)}-${clockLabel(end)})";
  }
}

/// The field errors of an item from [start] to [end] minutes that does not
/// lie in [hours], keyed as `validateItemJson` keys them: the start when it
/// does not begin a slot inside them, the end when it does not end one.
Map<String, String> hoursErrorsOf(int start, int end, DayHours hours) {
  return <String, String>{
    if (start < hours.start || start > hours.end - minutesPerSlot)
      "startMinute":
          "The start is ${clockLabel(hours.start)} to "
          "${clockLabel(hours.end - minutesPerSlot)}, inside the calendar's "
          "hours.",
    if (end < hours.start + minutesPerSlot || end > hours.end)
      "endMinute":
          "The end is ${clockLabel(hours.start + minutesPerSlot)} to "
          "${clockLabel(hours.end)}, inside the calendar's hours.",
  };
}

/// The least day width the settings offer, which is the grid's default.
const double minDayWidthLow = 44.0;

/// The most day width the settings offer.
const double minDayWidthHigh = 240.0;

/// The least slot height the settings offer.
const double minSlotHeightLow = 8.0;

/// The most slot height the settings offer.
const double minSlotHeightHigh = 48.0;

/// The slot height the grid has before the settings change it.
const double defaultMinSlotHeight = 16.0;

/// What the settings sheet chooses: the [hours] the calendar shows and
/// schedules in, and the least size of the timed grid's cells, which
/// stretch past it to fill the grid.
@immutable
class CalendarSettings {
  const CalendarSettings({
    this.hours = DayHours.allDay,
    this.minDayWidth = minDayWidthLow,
    this.minSlotHeight = defaultMinSlotHeight,
  });

  final DayHours hours;

  /// The least width of a day column, in logical pixels.
  final double minDayWidth;

  /// The least height of one slot, in logical pixels.
  final double minSlotHeight;

  CalendarSettings copyWith({
    DayHours? hours,
    double? minDayWidth,
    double? minSlotHeight,
  }) {
    return CalendarSettings(
      hours: hours ?? this.hours,
      minDayWidth: minDayWidth ?? this.minDayWidth,
      minSlotHeight: minSlotHeight ?? this.minSlotHeight,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarSettings &&
        other.hours == hours &&
        other.minDayWidth == minDayWidth &&
        other.minSlotHeight == minSlotHeight;
  }

  @override
  int get hashCode {
    return Object.hash(hours, minDayWidth, minSlotHeight);
  }

  @override
  String toString() {
    return "CalendarSettings($hours, day width $minDayWidth, slot height "
        "$minSlotHeight)";
  }
}
