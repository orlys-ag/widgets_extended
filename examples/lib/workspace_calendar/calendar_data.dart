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

/// The weeks one month occupies, Monday first. Row 0 holds the month's
/// first day and the last row its last day, so a month takes four to six
/// rows; the cells before the first day and after the last belong to the
/// adjacent months.
@immutable
class MonthGrid {
  MonthGrid(this.year, this.month)
    : _leading = weekdayColumn(DateTime(year, month));

  factory MonthGrid.of(DateTime date) {
    return MonthGrid(date.year, date.month);
  }

  final int year;
  final int month;

  /// Cells in row 0 before the month's first day.
  final int _leading;

  int get weekCount {
    return (_leading + daysInMonth(year, month) + 6) ~/ 7;
  }

  /// The day in row 0's first cell, which may belong to the month before.
  DateTime get firstDay {
    return dateAt(0, 0);
  }

  /// The day in the last row's last cell, which may belong to the month
  /// after.
  DateTime get lastDay {
    return dateAt(weekCount - 1, 6);
  }

  DateTime dateAt(int row, int col) {
    return DateTime(year, month, 1 - _leading + row * 7 + col);
  }

  bool contains(DateTime date) {
    return date.year == year && date.month == month;
  }

  /// The cell showing [date], which must be a day of this month.
  ({int row, int col}) cellOf(DateTime date) {
    assert(contains(date), "$date is not in $year-$month");
    final index = _leading + date.day - 1;
    return (row: index ~/ 7, col: index % 7);
  }
}
