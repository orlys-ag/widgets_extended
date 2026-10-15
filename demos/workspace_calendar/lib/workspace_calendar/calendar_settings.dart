/// What the calendar's settings choose: the weekdays it shows and the
/// hours it shows and schedules in.
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
