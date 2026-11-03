/// Civil dates on the local wall clock: the day steps, day numbers and
/// wall minutes of [CalendarDates], weekday sets, month grids, the hours of
/// a day, and the clock a time of day is named on.
///
/// Every date here is local midnight, built from its year, month and day
/// fields, so two dates for the same day compare equal and can key a map.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The scheduling module's civil-date helpers and constants, on the local
/// wall clock, which the calendar counts days and minutes with: the day
/// steps, day numbers and minutes that [CalendarDayHours],
/// [CalendarWeekdaySet], a `CalendarDataSource`'s reads by days and a
/// `CalendarEntry`'s times are counted in.
///
/// Its members are static, under this class's name, so they share no name
/// with a host's own helpers.
abstract final class CalendarDates {
  /// The slot length, in minutes, of a calendar given none: the step the
  /// timed grid's rows and gestures snap to.
  static const int defaultSlotMinutes = 15;

  /// The slot lengths, in minutes, a calendar takes, each a whole number of
  /// them to an hour and so to a day.
  static const List<int> slotMinuteChoices = <int>[5, 10, 15, 20, 30, 60];

  /// The minutes of a day on the wall clock, which [CalendarDayHours] and the
  /// wall minutes ([wallMinuteOf]) count in whatever the day's length.
  static const int minutesPerDay = 1440;

  /// The start of [date]'s day, built from its year, month and day.
  static DateTime dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// [date] moved by [days] calendar days. Built from the fields rather than
  /// by adding a `Duration`, so a daylight-saving change cannot move the
  /// result off midnight.
  static DateTime addDays(DateTime date, int days) {
    return DateTime(date.year, date.month, date.day + days);
  }

  /// [date] moved by [months] whole months, keeping its day of the month
  /// where the target month has it and taking the target's last day where
  /// it does not.
  static DateTime addMonths(DateTime date, int months) {
    final first = DateTime(date.year, date.month + months);
    final day = math.min(date.day, daysInMonth(first.year, first.month));
    return DateTime(first.year, first.month, day);
  }

  /// Whole days from [from] to [to], negative when [to] is earlier.
  static int daysBetween(DateTime from, DateTime to) {
    // Counted in UTC, which has no 23 or 25 hour days.
    final start = DateTime.utc(from.year, from.month, from.day);
    final end = DateTime.utc(to.year, to.month, to.day);
    return end.difference(start).inDays;
  }

  /// The column [date] falls in, in a week that starts on Monday.
  static int weekdayColumn(DateTime date) {
    return date.weekday - 1;
  }

  /// Whole days from 1970-01-01 to [date]'s day, counted in UTC from its
  /// year, month and day fields, so the time of day and daylight saving
  /// play no part.
  static int dayNumber(DateTime date) {
    final utc = DateTime.utc(date.year, date.month, date.day);
    return utc.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  }

  /// The [weekdayColumn] of the [dayNumber] [day]. Day 0, 1970-01-01, was a
  /// Thursday, and `%` never answers negative here.
  static int weekdayColumnOfDay(int day) {
    return (day + 3) % 7;
  }

  /// [day] when [weekdays] holds its weekday; otherwise the first later day
  /// of [day]'s month it holds, or, when the month has none, the last
  /// earlier one. A weekday set holds a weekday and every month holds each
  /// weekday, so one of them is found.
  static DateTime shownDayNear(DateTime day, CalendarWeekdaySet weekdays) {
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
  ///
  /// Throws an [ArgumentError], in every build, naming `direction` for a
  /// [direction] of 0.
  static DateTime nextShownDay(
    DateTime day,
    int direction,
    CalendarWeekdaySet weekdays,
  ) {
    if (direction == 0) {
      throw ArgumentError.value(
        direction,
        "direction",
        "A direction is positive or negative",
      );
    }
    var next = addDays(day, direction.sign);
    while (!weekdays.containsDate(next)) {
      next = addDays(next, direction.sign);
    }
    return next;
  }

  /// The days of [day]'s week, which starts on [weekdays]' first weekday,
  /// whose weekday [weekdays] holds, in order.
  static List<DateTime> shownDaysOfWeek(
    DateTime day,
    CalendarWeekdaySet weekdays,
  ) {
    final start = weekdays.weekStartOf(day);
    return <DateTime>[
      for (final column in weekdays.columns)
        addDays(start, weekdays.offsetOf(column)),
    ];
  }

  /// The local midnight of [day], the inverse of [dayNumber].
  static DateTime dateOfDayNumber(int day) {
    final utc = DateTime.fromMillisecondsSinceEpoch(
      day * Duration.millisecondsPerDay,
      isUtc: true,
    );
    return DateTime(utc.year, utc.month, utc.day);
  }

  /// Whether [time] is the start of its day: the instant
  /// `DateTime(year, month, day)` gives, so a day of 23 or 25 hours, and one
  /// whose midnight the clock skips, has one.
  static bool isDayStart(DateTime time) {
    return time == DateTime(time.year, time.month, time.day);
  }

  /// The minutes after midnight [time]'s wall clock reads.
  static int minuteOfDay(DateTime time) {
    return time.hour * 60 + time.minute;
  }

  /// The minute of its last day an end at [end] lies at: [minutesPerDay] for
  /// a day start, which ends the day before, and [minuteOfDay] otherwise.
  static int endMinuteOfDay(DateTime end) {
    return isDayStart(end) ? minutesPerDay : minuteOfDay(end);
  }

  /// [time] on the wall-clock coordinate as its clock reads it: its
  /// [dayNumber] times [minutesPerDay], plus its [minuteOfDay], so the start
  /// of a day whose clock skips its midnight lies at the minute its clock
  /// starts at. A range's end reads with [endWallMinuteOf].
  static int wallMinuteOf(DateTime time) {
    return dayNumber(time) * minutesPerDay + minuteOfDay(time);
  }

  /// The wall minute a range ending at [end] ends at: its day's minute 0,
  /// the 24:00 of the day before, for a day's start, the instant
  /// `DateTime(year, month, day)` gives, the start of a day whose clock
  /// skips its midnight included, and [wallMinuteOf]'s otherwise. A day's
  /// 24:00 is the next day's minute 0.
  static int endWallMinuteOf(DateTime end) {
    return dayNumber(end) * minutesPerDay +
        (isDayStart(end) ? 0 : minuteOfDay(end));
  }

  /// The instant the wall minute [wall] names as a start or a time of day:
  /// the time its day's clock reads at that hour and minute, minute 0
  /// included, which is the day's start where its clock reads 00:00; null
  /// for a time the clock skips, minute 0 of a day whose clock skips its
  /// midnight included. A range's end converts with [endAtWallMinute].
  ///
  /// On a day whose clock repeats a stretch, a time in it has two instants:
  /// the earlier, or the later where [from] lies on the same day and is
  /// itself a later occurrence ([isLaterOccurrence]), so a gesture that
  /// began in the repeated stretch stays in the occurrence it began in.
  static DateTime? timeAtWallMinute(int wall, {DateTime? from}) {
    return _instantAtWallMinute(wall, from, end: false);
  }

  /// The instant a range ending at the wall minute [wall] ends at:
  /// [timeAtWallMinute]'s, [from] read as it reads it, except that minute 0
  /// of a day whose clock skips its midnight, the 24:00 of the day before,
  /// is the day's start. A day's 24:00 is the next day's minute 0. The
  /// minute a stretch its day's clock repeats ends at is the instant after
  /// the stretch's second pass, whichever occurrence [from] picks.
  ///
  /// [rangeEndAtWallMinute] ends a range from the stretch's first pass there
  /// with that pass.
  static DateTime? endAtWallMinute(int wall, {DateTime? from}) {
    return _instantAtWallMinute(wall, from, end: true);
  }

  /// The instant a range from [start] ending at the wall minute [wall] ends
  /// at: [endAtWallMinute]'s, [from] read as it reads it, except where
  /// [start] lies in the first pass of a stretch its day's clock repeats and
  /// [wall] is where that stretch ends. There it is the instant the first
  /// pass ends, as the clock goes back, so the range keeps to the pass it
  /// starts in and lasts its wall minutes, and [wallSpanOf] draws it to
  /// [wall].
  static DateTime? rangeEndAtWallMinute(
    DateTime start,
    int wall, {
    DateTime? from,
  }) {
    // Inside one pass, instants and wall minutes run together, up to the
    // instant the clock goes back: the only one whose offset is below the
    // minute's before it, and which reads a time not after the start's when
    // the start lies in the first pass.
    final moved = start.add(Duration(minutes: wall - wallMinuteOf(start)));
    if (moved.isAfter(start) &&
        wallMinuteOf(moved) <= wallMinuteOf(start) &&
        moved.timeZoneOffset <
            moved.subtract(const Duration(minutes: 1)).timeZoneOffset) {
      return moved;
    }
    return endAtWallMinute(wall, from: from);
  }

  /// [timeAtWallMinute]'s instant where not [end], and [endAtWallMinute]'s
  /// where [end]: one reading of the clock, the two told apart only at
  /// minute 0 of a day whose clock skips its midnight.
  static DateTime? _instantAtWallMinute(
    int wall,
    DateTime? from, {
    required bool end,
  }) {
    // Floored, so a wall minute before the epoch's day keeps its minute.
    final minute = wall % minutesPerDay;
    final day = (wall - minute) ~/ minutesPerDay;
    final date = dateOfDayNumber(day);
    final hour = minute ~/ 60;
    final ofHour = minute % 60;
    bool reads(DateTime time) {
      return time.year == date.year &&
          time.month == date.month &&
          time.day == date.day &&
          time.hour == hour &&
          time.minute == ofHour;
    }

    // The constructor's instant for hour 0 and minute 0 is the day's start.
    final time = minute == 0
        ? date
        : DateTime(date.year, date.month, date.day, hour, ofHour);
    // A time the clock skips rolls over to another hour.
    if (!reads(time)) {
      return end && minute == 0 ? date : null;
    }
    final change = repeatedStretchOf(date);
    if (change == Duration.zero) {
      return time;
    }
    // The clock repeats a stretch of [change] on this day, so the time may
    // have a second instant [change] away, whichever one the constructor
    // picked.
    DateTime? earliest;
    DateTime? latest;
    for (final candidate in <DateTime>[
      time.subtract(change),
      time,
      time.add(change),
    ]) {
      if (reads(candidate)) {
        earliest ??= candidate;
        latest = candidate;
      }
    }
    if (from != null && dayNumber(from) == day && isLaterOccurrence(from)) {
      return latest;
    }
    return earliest;
  }

  /// How long the stretch of wall time is that [day]'s clock reads twice,
  /// as a clock turned back does: how far its offset falls by the next day's
  /// start, and zero where it does not fall.
  static Duration repeatedStretchOf(DateTime day) {
    final date = dateOnly(day);
    final change = date.timeZoneOffset - addDays(date, 1).timeZoneOffset;
    return change > Duration.zero ? change : Duration.zero;
  }

  /// Whether [time] is the later instant of a wall time its day's clock
  /// reads twice, told as of its whole minute, so the seconds past it play
  /// no part.
  static bool isLaterOccurrence(DateTime time) {
    // The minute's own instant in time's occurrence: [timeAtWallMinute]
    // answers whole minutes.
    final minute = time.subtract(
      Duration(
        seconds: time.second,
        milliseconds: time.millisecond,
        microseconds: time.microsecond,
      ),
    );
    return minute != timeAtWallMinute(wallMinuteOf(time));
  }

  /// The first wall minute the clock reads whose instant in [from]'s
  /// occurrence ([timeAtWallMinute]) is not before [time], so a range from it
  /// starts at [time] or later: [time]'s own ([wallMinuteOf]) or, for a time
  /// with seconds past its minute, the next, except where its day's clock
  /// reads [time] twice and [from] picks the other instant, where it is the
  /// repeated stretch's start or the first minute after it.
  ///
  /// Those instants rise with the wall minute, whichever occurrence [from]
  /// picks, so each walk from [time]'s own minute ends at the first minute
  /// that fails its test, at most a minute past a stretch the clock repeats
  /// or skips.
  static int firstWallMinuteNotBefore(DateTime time, {DateTime? from}) {
    var wall = wallMinuteOf(time);
    while (!(timeAtWallMinute(wall - 1, from: from)?.isBefore(time) ?? true)) {
      wall--;
    }
    while (timeAtWallMinute(wall, from: from)?.isBefore(time) ?? true) {
      wall++;
    }
    return wall;
  }

  /// The last wall minute whose instant as a range's end in [from]'s
  /// occurrence ([endAtWallMinute]), or where [start] is given as the end of
  /// a range from it ([rangeEndAtWallMinute]), is not after [time], so a
  /// range to it ends at [time] or earlier: [time]'s own as an end
  /// ([endWallMinuteOf]), except where its day's clock reads [time] twice
  /// and [from] picks the other instant, where it is the last minute of the
  /// repeated stretch or the last before it, as [firstWallMinuteNotBefore]
  /// walks, or the stretch's end, where a range from [start] ends with the
  /// first pass there.
  ///
  /// A range from [start] ends as [endAtWallMinute] ends it except at the
  /// stretch's end, whose instant lies between those of the minutes beside
  /// it, so the instants still rise with the wall minute.
  static int lastWallMinuteNotAfter(
    DateTime time, {
    DateTime? from,
    DateTime? start,
  }) {
    DateTime? endAt(int wall) {
      return start == null
          ? endAtWallMinute(wall, from: from)
          : rangeEndAtWallMinute(start, wall, from: from);
    }

    var wall = endWallMinuteOf(time);
    while (!(endAt(wall + 1)?.isAfter(time) ?? true)) {
      wall++;
    }
    while (endAt(wall)?.isAfter(time) ?? true) {
      wall--;
    }
    return wall;
  }

  /// The [dayNumber] of the last day a range from [start] to [end], end
  /// exclusive, has a part in: the day before an end at a day start, and the
  /// end's own day otherwise.
  static int lastDayNumberOf(DateTime start, DateTime end) {
    return isDayStart(end) ? dayNumber(end) - 1 : dayNumber(end);
  }

  /// The range from [start] to [end] in wall minutes: from its start's wall
  /// minute ([wallMinuteOf]) to its end's ([endWallMinuteOf]), except at two
  /// ends a stretch the clock repeats gives. An end at the later 00:00
  /// ([isLaterMidnight]), which reads as the 24:00 before it, ends at its
  /// day's minute the length of the repeated stretch ([repeatedStretchOf]),
  /// 01:00 for an hour, where a clock going back to 00:00 ends the first
  /// pass, so the range has a piece on the day it ends on. And an end whose
  /// wall minute is not after the start's is the start plus the range's
  /// length in minutes, held at the 24:00 of the end's day, the last day the
  /// range has a piece on ([lastDayNumberOf]).
  static ({int start, int end}) wallSpanOf(DateTime start, DateTime end) {
    final from = wallMinuteOf(start);
    var to = endWallMinuteOf(end);
    if (isLaterMidnight(end)) {
      to += repeatedStretchOf(end).inMinutes;
    }
    if (to <= from) {
      to = math.min(
        from + end.difference(start).inMinutes,
        (dayNumber(end) + 1) * minutesPerDay,
      );
    }
    return (start: from, end: to);
  }

  /// The part of [span], in wall minutes, on the [dayNumber] [day], as
  /// minutes of that day with `0 <= start < end <= minutesPerDay`; null
  /// where it has none, as on a day an end at its start leaves.
  static ({int start, int end})? pieceOn(({int start, int end}) span, int day) {
    final base = day * minutesPerDay;
    final start = math.max(span.start, base) - base;
    final end = math.min(span.end, base + minutesPerDay) - base;
    if (end <= start) {
      return null;
    }
    return (start: start, end: end);
  }

  /// [date]'s year, month and day as "2026-04-21", ISO 8601's extended
  /// calendar form, for a [date] whose year is from 0 to 9999.
  static String isoDate(DateTime date) {
    final year = date.year.toString().padLeft(4, "0");
    final month = date.month.toString().padLeft(2, "0");
    final day = date.day.toString().padLeft(2, "0");
    return "$year-$month-$day";
  }

  /// "09:30" for [minute] minutes after midnight, and "24:00" for 1440: the
  /// time of day in ISO 8601's hours and minutes, for a [minute] from 0 to
  /// 1440.
  static String isoTime(int minute) {
    final hours = (minute ~/ 60).toString().padLeft(2, "0");
    final minutes = (minute % 60).toString().padLeft(2, "0");
    return "$hours:$minutes";
  }
}

int daysInMonth(int year, int month) {
  // Day 0 of the next month is the last day of this one.
  return DateTime(year, month + 1, 0).day;
}

/// The Monday of [date]'s week, at local midnight.
DateTime weekStartOf(DateTime date) {
  return CalendarDates.addDays(
    CalendarDates.dateOnly(date),
    -CalendarDates.weekdayColumn(date),
  );
}

/// A set of weekdays, each named by its weekday column
/// (`CalendarDates.weekdayColumn`), Monday 0 and Sunday 6, and the
/// weekday a week starts on, [firstColumn]: the shown weekdays and their
/// order, in every view of the calendar.
@immutable
final class CalendarWeekdaySet {
  const CalendarWeekdaySet._(this._bits, [this.firstColumn = 0]);

  /// The columns' names in [toString], which is for developers and so is
  /// not localized.
  static const List<String> _columnNames = <String>[
    "Mo",
    "Tu",
    "We",
    "Th",
    "Fr",
    "Sa",
    "Su",
  ];

  /// The weekdays [columns] names, each 0 to 6, in weeks that start on
  /// the weekday [firstColumn] names.
  ///
  /// Throws an [ArgumentError], in every build, naming `firstColumn` for a
  /// [firstColumn] outside 0 to 6, and then `columns` for a column outside
  /// 0 to 6 and for [columns] that name no weekday, so every set holds a
  /// weekday.
  factory CalendarWeekdaySet.of(Iterable<int> columns, {int firstColumn = 0}) {
    if (firstColumn < 0 || firstColumn >= DateTime.daysPerWeek) {
      throw ArgumentError.value(
        firstColumn,
        "firstColumn",
        "A weekday column is 0 to 6",
      );
    }
    var bits = 0;
    for (final column in columns) {
      if (column < 0 || column >= DateTime.daysPerWeek) {
        throw ArgumentError.value(
          columns,
          "columns",
          "A weekday column is 0 to 6, not $column",
        );
      }
      bits |= 1 << column;
    }
    if (bits == 0) {
      throw ArgumentError.value(
        columns,
        "columns",
        "A weekday set holds a weekday",
      );
    }
    return CalendarWeekdaySet._(bits, firstColumn);
  }

  /// Every day of the week, from Monday.
  static const CalendarWeekdaySet all = CalendarWeekdaySet._(0x7F);

  /// Monday to Friday, from Monday.
  static const CalendarWeekdaySet workweek = CalendarWeekdaySet._(0x1F);

  /// Bit `n` is set when the set holds the column `n`.
  final int _bits;

  /// The weekday column (`CalendarDates.weekdayColumn`) of the weekday a
  /// week starts on.
  final int firstColumn;

  /// These weekdays in weeks that start on the weekday [column] names.
  ///
  /// Throws an [ArgumentError], in every build, naming `column` for a
  /// [column] outside 0 to 6.
  CalendarWeekdaySet startingOn(int column) {
    if (column < 0 || column >= DateTime.daysPerWeek) {
      throw ArgumentError.value(column, "column", "A weekday column is 0 to 6");
    }
    return CalendarWeekdaySet._(_bits, column);
  }

  /// The weekday columns the set holds, in week order: from [firstColumn]
  /// on, wrapping past Sunday.
  List<int> get columns {
    return <int>[
      for (var offset = 0; offset < DateTime.daysPerWeek; offset++)
        if (containsColumn(columnAt(offset))) columnAt(offset),
    ];
  }

  /// The weekday column [offset] days after the week's first day.
  int columnAt(int offset) {
    return (firstColumn + offset) % DateTime.daysPerWeek;
  }

  /// The days from the week's first day to the weekday [column]: 0 to 6.
  int offsetOf(int column) {
    return (column - firstColumn) % DateTime.daysPerWeek;
  }

  /// The first day of the week holding [date], at local midnight.
  DateTime weekStartOf(DateTime date) {
    return CalendarDates.addDays(
      CalendarDates.dateOnly(date),
      -offsetOf(CalendarDates.weekdayColumn(date)),
    );
  }

  /// The day number (`CalendarDates.dayNumber`) of the first day of the
  /// week holding the day numbered [day].
  int weekStartOfDay(int day) {
    return day - offsetOf(CalendarDates.weekdayColumnOfDay(day));
  }

  /// Whether the set holds the weekday column [column].
  bool containsColumn(int column) {
    return _bits & (1 << column) != 0;
  }

  /// Whether the set holds the weekday of the day numbered [day]
  /// (`CalendarDates.dayNumber`).
  bool containsDay(int day) {
    return containsColumn(CalendarDates.weekdayColumnOfDay(day));
  }

  /// Whether the set holds the weekday of [date].
  bool containsDate(DateTime date) {
    return containsColumn(CalendarDates.weekdayColumn(date));
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarWeekdaySet &&
        other._bits == _bits &&
        other.firstColumn == firstColumn;
  }

  @override
  int get hashCode {
    return Object.hash(_bits, firstColumn);
  }

  @override
  String toString() {
    final names = <String>[for (final column in columns) _columnNames[column]];
    return "CalendarWeekdaySet(${names.join(", ")}; "
        "from ${_columnNames[firstColumn]})";
  }
}

/// Whether [time] is the later 00:00 of a day whose clock repeats its
/// midnight, or a time inside its minute: a local time reading 00:00 that
/// [CalendarDates.isLaterOccurrence] names. Where the clock goes back to
/// 00:00, it is the instant the stretch's first pass ends.
bool isLaterMidnight(DateTime time) {
  // A day's start is the earlier 00:00, and the cheaper test.
  return !time.isUtc &&
      time.hour == 0 &&
      time.minute == 0 &&
      !CalendarDates.isDayStart(time) &&
      CalendarDates.isLaterOccurrence(time);
}

/// The first slot of [slotMinutes] on [day] whose start its clock reads
/// ([CalendarDates.timeAtWallMinute]) and whose end converts
/// ([CalendarDates.rangeEndAtWallMinute]), that [isFree] takes where it is
/// given, and that ends by its minute [until]: the one from its minute
/// [from], or where that one is not, the first from a later minute on the
/// grid of [slotMinutes] from midnight; null where none is. Each time is in
/// [occurrence]'s occurrence where [day]'s clock repeats it, as
/// [CalendarDates.timeAtWallMinute]'s `from` picks.
({DateTime start, DateTime end})? firstReadableSlot(
  DateTime day,
  int from,
  int until,
  int slotMinutes, {
  DateTime? occurrence,
  bool Function(DateTime start, DateTime end)? isFree,
}) {
  final base = CalendarDates.dayNumber(day) * CalendarDates.minutesPerDay;
  var minute = from;
  while (minute + slotMinutes <= until) {
    final start = CalendarDates.timeAtWallMinute(
      base + minute,
      from: occurrence,
    );
    final end = start == null
        ? null
        : CalendarDates.rangeEndAtWallMinute(
            start,
            base + minute + slotMinutes,
            from: occurrence,
          );
    if (start != null && end != null && (isFree?.call(start, end) ?? true)) {
      return (start: start, end: end);
    }
    minute = (minute ~/ slotMinutes + 1) * slotMinutes;
  }
  return null;
}

/// The minute of its last day at which the hours read a range from
/// [start] to [end] to end ([CalendarDayHours.holdsTimes]): the minute of
/// the end's day at which the range's wall span
/// ([CalendarDates.wallSpanOf]) ends, as Week and Day draw it, which is
/// [CalendarDates.endMinuteOfDay]'s except for an end at the later 00:00
/// ([isLaterMidnight]) and one in a repeated stretch's second pass whose
/// time is not after the start's; and [CalendarDates.endMinuteOfDay]'s for
/// an end at a day start, or one not after [start].
int hoursEndMinuteOf(DateTime start, DateTime end) {
  if (CalendarDates.isDayStart(end) || !end.isAfter(start)) {
    return CalendarDates.endMinuteOfDay(end);
  }
  return CalendarDates.wallSpanOf(start, end).end -
      CalendarDates.dayNumber(end) * CalendarDates.minutesPerDay;
}

final RegExp _isoDatePattern = RegExp(r"^(\d{4})-(\d{2})-(\d{2})$");

/// The local midnight [text] names in the form [CalendarDates.isoDate]
/// writes, or null when it is not a real date in that form.
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

/// The weeks one month occupies, each starting on [weekdays]' first
/// weekday, with a column for each weekday [weekdays] holds, in its
/// order. Row 0 is the first week holding a shown day
/// of the month and the last row the last such week, so a month takes
/// four to six rows; the cells before the month's first day and after its
/// last belong to the adjacent months.
@immutable
final class CalendarMonthGrid {
  /// The grid of [month] of [year], for a [month] from 1 to 12.
  factory CalendarMonthGrid(
    int year,
    int month, {
    CalendarWeekdaySet weekdays = CalendarWeekdaySet.all,
  }) {
    final leading = weekdays.offsetOf(
      CalendarDates.weekdayColumn(DateTime(year, month)),
    );
    final days = daysInMonth(year, month);
    final columns = <int>[
      for (final column in weekdays.columns) weekdays.offsetOf(column),
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
    return CalendarMonthGrid._(
      year,
      month,
      weekdays,
      leading,
      List<int>.unmodifiable(columns),
      first,
      last - first + 1,
    );
  }

  const CalendarMonthGrid._(
    this.year,
    this.month,
    this.weekdays,
    this._leading,
    this._columns,
    this._firstWeek,
    this.weekCount,
  );

  /// The grid of [date]'s month.
  factory CalendarMonthGrid.of(
    DateTime date, {
    CalendarWeekdaySet weekdays = CalendarWeekdaySet.all,
  }) {
    return CalendarMonthGrid(date.year, date.month, weekdays: weekdays);
  }

  /// The month's year.
  final int year;

  /// The month, 1 to 12.
  final int month;

  /// The weekdays the grid's columns show, in their order, and the weekday
  /// its weeks start on.
  final CalendarWeekdaySet weekdays;

  /// Cells of the month's first week, from its first weekday, before its
  /// first day.
  final int _leading;

  /// The days from a week's first day to the weekday each grid column
  /// shows, ascending.
  final List<int> _columns;

  /// The week of the month, counted from its first, that row 0 shows.
  final int _firstWeek;

  /// The grid's rows, four to six.
  final int weekCount;

  /// The grid's columns, one per weekday [weekdays] holds.
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

  /// The day in the cell at [row] and [col], for a [row] from 0 to
  /// [weekCount] - 1 and a [col] from 0 to [columnCount] - 1, which may
  /// belong to the month before or after.
  DateTime dateAt(int row, int col) {
    return DateTime(
      year,
      month,
      1 - _leading + (row + _firstWeek) * DateTime.daysPerWeek + _columns[col],
    );
  }

  /// Whether [date] is a day of this month.
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

/// The part of each day a calendar shows and schedules in: from [start]
/// to [end] minutes after midnight.
@immutable
final class CalendarDayHours {
  /// The hours from [start] to [end] minutes after midnight, with [start]
  /// before [end], inside one day.
  ///
  /// Throws an [ArgumentError], in every build, naming `start` for a
  /// [start] under 0, and `end` for an [end] past
  /// `CalendarDates.minutesPerDay` or not after [start].
  CalendarDayHours(this.start, this.end) {
    if (start < 0) {
      throw ArgumentError.value(
        start,
        "start",
        "Day hours start at 00:00 or later",
      );
    }
    if (end > CalendarDates.minutesPerDay) {
      throw ArgumentError.value(
        end,
        "end",
        "Day hours end at 24:00 or earlier",
      );
    }
    if (end <= start) {
      throw ArgumentError.value(
        end,
        "end",
        "Day hours end after their start, $start",
      );
    }
  }

  const CalendarDayHours._(this.start, this.end);

  /// The whole day, 00:00 to 24:00.
  static const CalendarDayHours allDay = CalendarDayHours._(
    0,
    CalendarDates.minutesPerDay,
  );

  /// Minutes after midnight.
  final int start;

  /// Minutes after midnight.
  final int end;

  /// The slots of [slotMinutes] from [start] to [end], which must both lie
  /// on that slot grid ([isOnSlotsOf]).
  int slotCountOf(int slotMinutes) {
    assert(
      isOnSlotsOf(slotMinutes),
      "$this does not start and end on the grid of $slotMinutes-minute "
      "slots.",
    );
    return (end - start) ~/ slotMinutes;
  }

  /// Whether [start] and [end] both lie on the grid of [slotMinutes]-minute
  /// slots from midnight.
  bool isOnSlotsOf(int slotMinutes) {
    return start % slotMinutes == 0 && end % slotMinutes == 0;
  }

  /// These hours widened to the grid of [slotMinutes]-minute slots from
  /// midnight: [start] rounded down and [end] up to it, so the hours
  /// themselves where they lie on it. [slotMinutes] divides a day, as each
  /// of `CalendarDates.slotMinuteChoices` does, so the end stays inside
  /// the day. It constructs the hours it answers, so for a slot length
  /// that takes the end past 24:00 it throws the constructor's
  /// [ArgumentError].
  CalendarDayHours roundedOutTo(int slotMinutes) {
    if (isOnSlotsOf(slotMinutes)) {
      return this;
    }
    return CalendarDayHours(
      start - start % slotMinutes,
      (end + slotMinutes - 1) ~/ slotMinutes * slotMinutes,
    );
  }

  /// Whether the minutes [from] to [to] lie inside these hours.
  bool contains(int from, int to) {
    return from >= start && to <= end;
  }

  /// Whether a range may start at [minute] after midnight inside these
  /// hours: from [start] to before [end].
  bool holdsStart(int minute) {
    return start <= minute && minute < end;
  }

  /// Whether a range may end at [minute] after midnight inside these
  /// hours: from after [start] to [end].
  bool holdsEnd(int minute) {
    return start < minute && minute <= end;
  }

  /// Whether these hours hold the range from [from] to [to], all-day where
  /// [isAllDay] and timed otherwise, as the caller tells it: every all-day
  /// range, which no hours limit; and a timed one whose start's minute of
  /// its day (`CalendarDates.minuteOfDay`) they hold as a start and whose
  /// end's minute on its last day (`CalendarDates.endMinuteOfDay`) they
  /// hold as an end, except an end at the later 00:00 of a day whose clock
  /// repeats its midnight, a local time reading 00:00 that
  /// `CalendarDates.isLaterOccurrence` names, which they hold where Week
  /// and Day draw it: at the minute the repeated stretch's first pass ends,
  /// 01:00 for an hour, whatever day the range starts on; and an end in a
  /// repeated stretch's second pass whose time is not after the start's,
  /// which they also hold where Week and Day draw it: at the start's minute
  /// plus the range's length, or the day's 24:00 where that is later. So
  /// an overnight range may cross the hours' end and start, and a timed
  /// range from a day start to a day start lies inside them only where they
  /// run from 00:00 to 24:00.
  bool holdsTimes(DateTime from, DateTime to, {required bool isAllDay}) {
    if (isAllDay) {
      return true;
    }
    return holdsStart(CalendarDates.minuteOfDay(from)) &&
        holdsEnd(hoursEndMinuteOf(from, to));
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarDayHours &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode {
    return Object.hash(start, end);
  }

  @override
  String toString() {
    return "CalendarDayHours("
        "${CalendarDates.isoTime(start)}-${CalendarDates.isoTime(end)})";
  }
}

/// How the calendar names a time of day (`CalendarLocalizations.formatTime`).
enum CalendarHourLabelFormat {
  /// The 24-hour clock: "13:00" in English.
  twentyFourHour,

  /// The 12-hour clock: "1 PM" in English.
  twelveHour,
}
