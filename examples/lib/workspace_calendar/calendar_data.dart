/// Dates, tasks and mock data for the workspace calendar example.
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

/// Indexed by [weekdayColumn], so Sunday first.
const List<String> weekdayNames = <String>[
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];

/// Indexed by [weekdayColumn].
const List<String> weekdayShortNames = <String>[
  "Su",
  "Mo",
  "Tu",
  "We",
  "Th",
  "Fr",
  "Sa",
];

/// Indexed by [weekdayColumn].
const List<String> weekdayLetters = <String>["S", "M", "T", "W", "T", "F", "S"];

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

/// The column [date] falls in, in a week that starts on Sunday.
int weekdayColumn(DateTime date) {
  return date.weekday % 7;
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

String taskCountLabel(int count) {
  if (count == 0) {
    return "No tasks";
  }
  if (count == 1) {
    return "1 task";
  }
  return "$count tasks";
}

/// The weeks one month occupies, Sunday first. Row 0 holds the month's
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

enum TaskStatus {
  toDo("To do"),
  inProgress("In progress"),
  done("Done");

  const TaskStatus(this.label);

  final String label;
}

@immutable
class CalendarTask {
  const CalendarTask({
    required this.id,
    required this.title,
    required this.day,
    required this.startMinute,
    required this.endMinute,
    required this.status,
  });

  final String id;
  final String title;
  final DateTime day;

  /// Minutes after midnight.
  final int startMinute;

  /// Minutes after midnight.
  final int endMinute;

  final TaskStatus status;

  /// "10:00-13:00".
  String get timeRange {
    return "${_clock(startMinute)}-${_clock(endMinute)}";
  }
}

String _clock(int minute) {
  final hours = (minute ~/ 60).toString().padLeft(2, "0");
  final minutes = (minute % 60).toString().padLeft(2, "0");
  return "$hours:$minutes";
}

/// A mock task: `day` counts whole days from today, and `start` and `end`
/// are minutes after midnight.
typedef _Seed = ({
  int day,
  int start,
  int end,
  String title,
  TaskStatus status,
});

/// Tasks laid out in whole days from today, so the example has populated
/// days around whatever date it opens on. Today carries two tasks, and
/// today + 6 carries enough to scroll the list.
const List<_Seed> _seed = <_Seed>[
  (
    day: -35,
    start: 11 * 60,
    end: 12 * 60,
    title: "Kickoff: mobile app",
    status: TaskStatus.done,
  ),
  (
    day: -9,
    start: 14 * 60,
    end: 15 * 60,
    title: "Quarterly review",
    status: TaskStatus.done,
  ),
  (
    day: -5,
    start: 9 * 60,
    end: 12 * 60,
    title: "Workshop: journey mapping",
    status: TaskStatus.done,
  ),
  (
    day: -2,
    start: 15 * 60,
    end: 16 * 60,
    title: "Stakeholder check-in",
    status: TaskStatus.done,
  ),
  (
    day: 0,
    start: 10 * 60,
    end: 13 * 60,
    title: "Design new UX flow for Michael",
    status: TaskStatus.inProgress,
  ),
  (
    day: 0,
    start: 14 * 60,
    end: 15 * 60,
    title: "Brainstorm with the team",
    status: TaskStatus.done,
  ),
  (
    day: 1,
    start: 9 * 60 + 30,
    end: 10 * 60,
    title: "Daily standup",
    status: TaskStatus.toDo,
  ),
  (
    day: 1,
    start: 11 * 60,
    end: 12 * 60,
    title: "Review onboarding copy",
    status: TaskStatus.toDo,
  ),
  (
    day: 3,
    start: 13 * 60,
    end: 14 * 60 + 30,
    title: "Interview: product designer",
    status: TaskStatus.toDo,
  ),
  (
    day: 6,
    start: 8 * 60 + 30,
    end: 9 * 60,
    title: "Plan the sprint goals",
    status: TaskStatus.toDo,
  ),
  (
    day: 6,
    start: 9 * 60,
    end: 10 * 60,
    title: "Sprint planning",
    status: TaskStatus.toDo,
  ),
  (
    day: 6,
    start: 10 * 60 + 30,
    end: 11 * 60 + 30,
    title: "Accessibility audit",
    status: TaskStatus.inProgress,
  ),
  (
    day: 6,
    start: 11 * 60 + 30,
    end: 12 * 60,
    title: "Sync with marketing",
    status: TaskStatus.toDo,
  ),
  (
    day: 6,
    start: 13 * 60,
    end: 14 * 60,
    title: "Prototype review",
    status: TaskStatus.toDo,
  ),
  (
    day: 6,
    start: 14 * 60,
    end: 15 * 60 + 30,
    title: "Usability test session",
    status: TaskStatus.toDo,
  ),
  (
    day: 6,
    start: 16 * 60,
    end: 16 * 60 + 30,
    title: "Update the roadmap",
    status: TaskStatus.toDo,
  ),
  (
    day: 6,
    start: 17 * 60,
    end: 18 * 60,
    title: "Retro prep",
    status: TaskStatus.toDo,
  ),
  (
    day: 7,
    start: 10 * 60,
    end: 11 * 60,
    title: "Client presentation",
    status: TaskStatus.toDo,
  ),
  (
    day: 12,
    start: 10 * 60,
    end: 10 * 60 + 30,
    title: "Vendor call",
    status: TaskStatus.toDo,
  ),
  (
    day: 18,
    start: 13 * 60,
    end: 17 * 60,
    title: "Team offsite",
    status: TaskStatus.toDo,
  ),
  (
    day: 30,
    start: 9 * 60,
    end: 10 * 60,
    title: "Release planning",
    status: TaskStatus.toDo,
  ),
  (
    day: 44,
    start: 15 * 60,
    end: 16 * 60,
    title: "Design system sync",
    status: TaskStatus.toDo,
  ),
];

/// The mock tasks around [today], grouped by day and sorted by start time
/// within each day.
Map<DateTime, List<CalendarTask>> mockTasksByDay(DateTime today) {
  final byDay = <DateTime, List<CalendarTask>>{};
  for (var i = 0; i < _seed.length; i++) {
    final seed = _seed[i];
    final day = addDays(today, seed.day);
    final task = CalendarTask(
      id: "task-$i",
      title: seed.title,
      day: day,
      startMinute: seed.start,
      endMinute: seed.end,
      status: seed.status,
    );
    byDay
        .putIfAbsent(day, () {
          return <CalendarTask>[];
        })
        .add(task);
  }
  for (final tasks in byDay.values) {
    tasks.sort((a, b) {
      return a.startMinute.compareTo(b.startMinute);
    });
  }
  return byDay;
}
