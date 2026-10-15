/// Dates, labels and the month layout for the workspace calendar example.
///
/// Every date here is local midnight, built from its year, month and day
/// fields, so two dates for the same day compare equal and can key a map.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

const List<String> monthNames = <String>[
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

/// Indexed by [weekdayColumn], so Monday first.
const List<String> weekdayNames = <String>[
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

/// Indexed by [weekdayColumn].
const List<String> weekdayShortNames = <String>[
  "Mo",
  "Tu",
  "We",
  "Th",
  "Fr",
  "Sa",
  "Su",
];

/// Indexed by [weekdayColumn].
const List<String> weekdayLetters = <String>["M", "T", "W", "T", "F", "S", "S"];

DateTime dateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

/// [date] moved by [days] calendar days. Built from the fields rather than
/// by adding a `Duration`, so a daylight-saving change cannot move the
/// result off midnight.
DateTime addDays(DateTime date, int days) {
  return DateTime(date.year, date.month, date.day + days);
}

/// [date] moved by [months] whole months, keeping its day of the month
/// where the target month has it and taking the target's last day where
/// it does not.
DateTime addMonths(DateTime date, int months) {
  final first = DateTime(date.year, date.month + months);
  final day = math.min(date.day, daysInMonth(first.year, first.month));
  return DateTime(first.year, first.month, day);
}

int daysInMonth(int year, int month) {
  // Day 0 of the next month is the last day of this one.
  return DateTime(year, month + 1, 0).day;
}

/// Whole days from [from] to [to], negative when [to] is earlier.
int daysBetween(DateTime from, DateTime to) {
  // Counted in UTC, which has no 23 or 25 hour days.
  final start = DateTime.utc(from.year, from.month, from.day);
  final end = DateTime.utc(to.year, to.month, to.day);
  return end.difference(start).inDays;
}

/// The column [date] falls in, in a week that starts on Monday.
int weekdayColumn(DateTime date) {
  return date.weekday - 1;
}

/// The Monday of [date]'s week, at local midnight.
DateTime weekStartOf(DateTime date) {
  return addDays(dateOnly(date), -weekdayColumn(date));
}

/// Whole days from 1970-01-01 to [date]'s day, counted in UTC from its
/// year, month and day fields, so the time of day and daylight saving
/// play no part.
int dayNumber(DateTime date) {
  final utc = DateTime.utc(date.year, date.month, date.day);
  return utc.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

/// The [weekdayColumn] of the [dayNumber] [day]. Day 0, 1970-01-01, was a
/// Thursday, and `%` never answers negative here.
int weekdayColumnOfDay(int day) {
  return (day + 3) % 7;
}

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

/// [day] when [weekdays] holds its weekday; otherwise the first later day
/// of [day]'s month it holds, or, when the month has none, the last
/// earlier one. Every month holds each weekday, so one of them is found.
DateTime shownDayNear(DateTime day, WeekdaySet weekdays) {
  assert(!weekdays.isEmpty);
  if (weekdays.containsDate(day)) {
    return day;
  }
  for (
    var later = addDays(day, 1);
    later.month == day.month;
    later = addDays(later, 1)
  ) {
    if (weekdays.containsDate(later)) {
      return later;
    }
  }
  var earlier = addDays(day, -1);
  while (!weekdays.containsDate(earlier)) {
    earlier = addDays(earlier, -1);
  }
  return earlier;
}

/// The first day after [day], or before it for a negative [direction],
/// whose weekday [weekdays] holds.
DateTime nextShownDay(DateTime day, int direction, WeekdaySet weekdays) {
  assert(direction != 0 && !weekdays.isEmpty);
  var next = addDays(day, direction.sign);
  while (!weekdays.containsDate(next)) {
    next = addDays(next, direction.sign);
  }
  return next;
}

/// The local midnight of [day], the inverse of [dayNumber].
DateTime dateOfDayNumber(int day) {
  final utc = DateTime.fromMillisecondsSinceEpoch(
    day * Duration.millisecondsPerDay,
    isUtc: true,
  );
  return DateTime(utc.year, utc.month, utc.day);
}

/// "2026-04-21".
String isoDate(DateTime date) {
  final year = date.year.toString().padLeft(4, "0");
  final month = date.month.toString().padLeft(2, "0");
  final day = date.day.toString().padLeft(2, "0");
  return "$year-$month-$day";
}

final RegExp _isoDatePattern = RegExp(r"^(\d{4})-(\d{2})-(\d{2})$");

/// The local midnight [text] names in the form [isoDate] writes, or null
/// when it is not a real date in that form.
DateTime? parseIsoDate(String text) {
  final match = _isoDatePattern.firstMatch(text);
  if (match == null) {
    return null;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  // `DateTime` rolls an out-of-range month or day over into the next
  // field, so a date that does not exist reads back different fields.
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

/// "09:30" for [minute] minutes after midnight; 1440 reads "24:00".
String clockLabel(int minute) {
  final hours = (minute ~/ 60).toString().padLeft(2, "0");
  final minutes = (minute % 60).toString().padLeft(2, "0");
  return "$hours:$minutes";
}

/// "Today, April 21", "Monday, April 27", or with the year appended when
/// [day] is not in [today]'s year.
String dayTitle(DateTime day, DateTime today) {
  var date = "${monthNames[day.month - 1]} ${day.day}";
  if (day.year != today.year) {
    date = "$date, ${day.year}";
  }
  final offset = daysBetween(today, day);
  final String name;
  if (offset == 0) {
    name = "Today";
  } else if (offset == 1) {
    name = "Tomorrow";
  } else if (offset == -1) {
    name = "Yesterday";
  } else {
    name = weekdayNames[weekdayColumn(day)];
  }
  return "$name, $date";
}

/// "No items", "1 item" or "N items".
String itemCountLabel(int count) {
  if (count == 0) {
    return "No items";
  }
  if (count == 1) {
    return "1 item";
  }
  return "$count items";
}

/// The weeks one month occupies, Monday first, with a column for each
/// weekday [weekdays] holds. Row 0 is the first week holding a shown day
/// of the month and the last row the last such week, so a month takes
/// four to six rows; the cells before the month's first day and after its
/// last belong to the adjacent months.
@immutable
class MonthGrid {
  factory MonthGrid(
    int year,
    int month, {
    WeekdaySet weekdays = WeekdaySet.all,
  }) {
    assert(!weekdays.isEmpty, "A month grid shows at least one weekday.");
    final leading = weekdayColumn(DateTime(year, month));
    final days = daysInMonth(year, month);
    final columns = <int>[
      for (var column = 0; column < DateTime.daysPerWeek; column++)
        if (weekdays.containsColumn(column)) column,
    ];
    bool holdsShownDay(int week) {
      for (final column in columns) {
        final day = week * DateTime.daysPerWeek + column - leading + 1;
        if (day >= 1 && day <= days) {
          return true;
        }
      }
      return false;
    }

    // Only the first and the last week can miss: a month of at least 28
    // days covers every weekday of each week between them.
    final weeks = (leading + days + 6) ~/ DateTime.daysPerWeek;
    final first = holdsShownDay(0) ? 0 : 1;
    final last = holdsShownDay(weeks - 1) ? weeks - 1 : weeks - 2;
    return MonthGrid._(
      year,
      month,
      weekdays,
      leading,
      List<int>.unmodifiable(columns),
      first,
      last - first + 1,
    );
  }

  const MonthGrid._(
    this.year,
    this.month,
    this.weekdays,
    this._leading,
    this._columns,
    this._firstWeek,
    this.weekCount,
  );

  factory MonthGrid.of(DateTime date, {WeekdaySet weekdays = WeekdaySet.all}) {
    return MonthGrid(date.year, date.month, weekdays: weekdays);
  }

  final int year;
  final int month;
  final WeekdaySet weekdays;

  /// Cells of the month's first week, Monday first, before its first day.
  final int _leading;

  /// The weekday column each grid column shows, ascending.
  final List<int> _columns;

  /// The week of the month, counted from its first, that row 0 shows.
  final int _firstWeek;

  final int weekCount;

  int get columnCount {
    return _columns.length;
  }

  /// The day in row 0's first cell, which may belong to the month before.
  DateTime get firstDay {
    return dateAt(0, 0);
  }

  /// The day in the last row's last cell, which may belong to the month
  /// after.
  DateTime get lastDay {
    return dateAt(weekCount - 1, columnCount - 1);
  }

  DateTime dateAt(int row, int col) {
    return DateTime(
      year,
      month,
      1 - _leading + (row + _firstWeek) * DateTime.daysPerWeek + _columns[col],
    );
  }

  bool contains(DateTime date) {
    return date.year == year && date.month == month;
  }

  /// The cell showing [date], which must be a day of this month whose
  /// weekday [weekdays] holds.
  ({int row, int col}) cellOf(DateTime date) {
    assert(contains(date), "$date is not in $year-$month");
    assert(weekdays.containsDate(date), "$date is not on a shown weekday");
    final index = _leading + date.day - 1;
    return (
      row: index ~/ DateTime.daysPerWeek - _firstWeek,
      col: _columns.indexOf(index % DateTime.daysPerWeek),
    );
  }
}
