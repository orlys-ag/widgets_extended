/// Civil dates on the local wall clock: day steps, day numbers, weekday
/// sets, month grids and the hours of a day.
///
/// Every date here is local midnight, built from its year, month and day
/// fields, so two dates for the same day compare equal and can key a map.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The slot length, in minutes, of a calendar given none: the step the
/// timed grid's rows and gestures snap to.
const int defaultSlotMinutes = 15;

/// The slot lengths, in minutes, a calendar takes, each a whole number of
/// them to an hour and so to a day.
const List<int> slotMinuteChoices = <int>[5, 10, 15, 20, 30, 60];

/// The minutes of a day on the wall clock, which [DayHours] and the wall
/// minutes ([wallMinuteOf]) count in whatever the day's length.
const int minutesPerDay = 1440;

/// The local midnight of [date]'s day.
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

/// A set of weekdays, each named by its [weekdayColumn], Monday 0 and
/// Sunday 6, and the weekday a week starts on, [firstColumn]: the shown
/// weekdays and their order, in every view of the calendar.
@immutable
final class WeekdaySet {
  const WeekdaySet._(this._bits, [this.firstColumn = 0]);

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
  factory WeekdaySet.of(Iterable<int> columns, {int firstColumn = 0}) {
    assert(
      firstColumn >= 0 && firstColumn < DateTime.daysPerWeek,
      "A weekday column is 0 to 6, not $firstColumn.",
    );
    var bits = 0;
    for (final column in columns) {
      assert(
        column >= 0 && column < DateTime.daysPerWeek,
        "A weekday column is 0 to 6, not $column.",
      );
      bits |= 1 << column;
    }
    return WeekdaySet._(bits, firstColumn);
  }

  /// Every day of the week, from Monday.
  static const WeekdaySet all = WeekdaySet._(0x7F);

  /// Monday to Friday, from Monday.
  static const WeekdaySet workweek = WeekdaySet._(0x1F);

  /// Bit `n` is set when the set holds the column `n`.
  final int _bits;

  /// The [weekdayColumn] of the weekday a week starts on.
  final int firstColumn;

  /// Whether the set holds no weekday.
  bool get isEmpty {
    return _bits == 0;
  }

  /// These weekdays in weeks that start on the weekday [column] names.
  WeekdaySet startingOn(int column) {
    return WeekdaySet.of(columns, firstColumn: column);
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
    return addDays(dateOnly(date), -offsetOf(weekdayColumn(date)));
  }

  /// The [dayNumber] of the first day of the week holding the [dayNumber]
  /// [day].
  int weekStartOfDay(int day) {
    return day - offsetOf(weekdayColumnOfDay(day));
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
    return other is WeekdaySet &&
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
    return "WeekdaySet(${names.join(", ")}; "
        "from ${_columnNames[firstColumn]})";
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

/// The days of [day]'s week, which starts on [weekdays]' first weekday,
/// whose weekday [weekdays] holds, in order.
List<DateTime> shownDaysOfWeek(DateTime day, WeekdaySet weekdays) {
  assert(!weekdays.isEmpty);
  final start = weekdays.weekStartOf(day);
  return <DateTime>[
    for (final column in weekdays.columns)
      addDays(start, weekdays.offsetOf(column)),
  ];
}

/// The local midnight of [day], the inverse of [dayNumber].
DateTime dateOfDayNumber(int day) {
  final utc = DateTime.fromMillisecondsSinceEpoch(
    day * Duration.millisecondsPerDay,
    isUtc: true,
  );
  return DateTime(utc.year, utc.month, utc.day);
}

/// Whether [time] is the start of its day: the instant
/// `DateTime(year, month, day)` gives, so a day of 23 or 25 hours, and one
/// whose midnight the clock skips, has one.
bool isDayStart(DateTime time) {
  return time == DateTime(time.year, time.month, time.day);
}

/// The minutes after midnight [time]'s wall clock reads.
int minuteOfDay(DateTime time) {
  return time.hour * 60 + time.minute;
}

/// The minute of its last day an end at [end] lies at: [minutesPerDay] for
/// a day start, which ends the day before, and [minuteOfDay] otherwise.
int endMinuteOfDay(DateTime end) {
  return isDayStart(end) ? minutesPerDay : minuteOfDay(end);
}

/// [time] on the wall-clock coordinate: its [dayNumber] times
/// [minutesPerDay], plus 0 for a day start and its [minuteOfDay]
/// otherwise. A day's 24:00 is the next day's minute 0.
int wallMinuteOf(DateTime time) {
  return dayNumber(time) * minutesPerDay +
      (isDayStart(time) ? 0 : minuteOfDay(time));
}

/// The instant the wall minute [wall] names: for minute 0 of a day its
/// start, and otherwise the time its day's clock reads at that hour and
/// minute; null for a time the clock skips.
///
/// On a day whose clock repeats a stretch, a time in it has two instants:
/// the earlier, or the later where [from] lies on the same day and is
/// itself a later occurrence ([isLaterOccurrence]), so a gesture that
/// began in the repeated stretch stays in the occurrence it began in.
DateTime? timeAtWallMinute(int wall, {DateTime? from}) {
  // Floored, so a wall minute before the epoch's day keeps its minute.
  final minute = wall % minutesPerDay;
  final day = (wall - minute) ~/ minutesPerDay;
  final date = dateOfDayNumber(day);
  if (minute == 0) {
    return date;
  }
  final hour = minute ~/ 60;
  final ofHour = minute % 60;
  bool reads(DateTime time) {
    return time.year == date.year &&
        time.month == date.month &&
        time.day == date.day &&
        time.hour == hour &&
        time.minute == ofHour;
  }

  final time = DateTime(date.year, date.month, date.day, hour, ofHour);
  // A time the clock skips rolls over to another hour.
  if (!reads(time)) {
    return null;
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
Duration repeatedStretchOf(DateTime day) {
  final date = dateOnly(day);
  final change = date.timeZoneOffset - addDays(date, 1).timeZoneOffset;
  return change > Duration.zero ? change : Duration.zero;
}

/// Whether [time] is the later instant of a wall time its day's clock
/// reads twice.
bool isLaterOccurrence(DateTime time) {
  return time != timeAtWallMinute(wallMinuteOf(time));
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
int firstWallMinuteNotBefore(DateTime time, {DateTime? from}) {
  var wall = wallMinuteOf(time);
  while (!(timeAtWallMinute(wall - 1, from: from)?.isBefore(time) ?? true)) {
    wall--;
  }
  while (timeAtWallMinute(wall, from: from)?.isBefore(time) ?? true) {
    wall++;
  }
  return wall;
}

/// The last wall minute the clock reads whose instant in [from]'s
/// occurrence ([timeAtWallMinute]) is not after [time], so a range to it
/// ends at [time] or earlier: [time]'s own ([wallMinuteOf]), except where
/// its day's clock reads [time] twice and [from] picks the other instant,
/// where it is the last minute of the repeated stretch or the last before
/// it, as [firstWallMinuteNotBefore] walks.
int lastWallMinuteNotAfter(DateTime time, {DateTime? from}) {
  var wall = wallMinuteOf(time);
  while (!(timeAtWallMinute(wall + 1, from: from)?.isAfter(time) ?? true)) {
    wall++;
  }
  while (timeAtWallMinute(wall, from: from)?.isAfter(time) ?? true) {
    wall--;
  }
  return wall;
}

/// The first slot of [slotMinutes] on [day] whose start and end its clock
/// reads ([timeAtWallMinute]), that [isFree] takes where it is given, and
/// that ends by its minute [until]: the one from its minute [from], or
/// where that one is not, the first from a later minute on the grid of
/// [slotMinutes] from midnight; null where none is. Each time is in
/// [occurrence]'s occurrence where [day]'s clock repeats it, as
/// [timeAtWallMinute]'s `from` picks.
({DateTime start, DateTime end})? firstReadableSlot(
  DateTime day,
  int from,
  int until,
  int slotMinutes, {
  DateTime? occurrence,
  bool Function(DateTime start, DateTime end)? isFree,
}) {
  final base = dayNumber(day) * minutesPerDay;
  var minute = from;
  while (minute + slotMinutes <= until) {
    final start = timeAtWallMinute(base + minute, from: occurrence);
    final end = timeAtWallMinute(base + minute + slotMinutes, from: occurrence);
    if (start != null && end != null && (isFree?.call(start, end) ?? true)) {
      return (start: start, end: end);
    }
    minute = (minute ~/ slotMinutes + 1) * slotMinutes;
  }
  return null;
}

/// The [dayNumber] of the last day a range from [start] to [end], end
/// exclusive, has a part in: the day before an end at a day start, and the
/// end's own day otherwise.
int lastDayNumberOf(DateTime start, DateTime end) {
  return isDayStart(end) ? dayNumber(end) - 1 : dayNumber(end);
}

/// The range from [start] to [end] in wall minutes ([wallMinuteOf]). An
/// end whose wall minute is not after the start's, which only a stretch
/// the clock repeats gives, is the start plus the range's length in
/// minutes.
({int start, int end}) wallSpanOf(DateTime start, DateTime end) {
  final from = wallMinuteOf(start);
  var to = wallMinuteOf(end);
  if (to <= from) {
    to = from + end.difference(start).inMinutes;
  }
  return (start: from, end: to);
}

/// The part of [span], in wall minutes, on the [dayNumber] [day], as
/// minutes of that day with `0 <= start < end <= minutesPerDay`; null
/// where it has none, as on a day an end at its start leaves.
({int start, int end})? pieceOn(({int start, int end}) span, int day) {
  final base = day * minutesPerDay;
  final start = math.max(span.start, base) - base;
  final end = math.min(span.end, base + minutesPerDay) - base;
  if (end <= start) {
    return null;
  }
  return (start: start, end: end);
}

/// "2026-04-21".
String isoDate(DateTime date) {
  final year = date.year.toString().padLeft(4, "0");
  final month = date.month.toString().padLeft(2, "0");
  final day = date.day.toString().padLeft(2, "0");
  return "$year-$month-$day";
}

/// "09:30" for [minute] minutes after midnight, and "24:00" for 1440: the
/// time of day in ISO 8601's hours and minutes.
String isoTime(int minute) {
  final hours = (minute ~/ 60).toString().padLeft(2, "0");
  final minutes = (minute % 60).toString().padLeft(2, "0");
  return "$hours:$minutes";
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

/// The weeks one month occupies, each starting on [weekdays]' first
/// weekday, with a column for each weekday [weekdays] holds, in its
/// order. Row 0 is the first week holding a shown day
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
    final leading = weekdays.offsetOf(weekdayColumn(DateTime(year, month)));
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

  /// Cells of the month's first week, from its first weekday, before its
  /// first day.
  final int _leading;

  /// The days from a week's first day to the weekday each grid column
  /// shows, ascending.
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

/// The part of each day a calendar shows and schedules in: from [start]
/// to [end] minutes after midnight.
@immutable
final class DayHours {
  /// The hours from [start] to [end] minutes after midnight, with [start]
  /// before [end], inside one day.
  const DayHours(this.start, this.end)
    : assert(start >= 0),
      assert(end <= minutesPerDay),
      assert(start < end);

  /// The whole day, 00:00 to 24:00.
  static const DayHours allDay = DayHours(0, minutesPerDay);

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
  /// of [slotMinuteChoices] does, so the end stays inside the day.
  DayHours roundedOutTo(int slotMinutes) {
    if (isOnSlotsOf(slotMinutes)) {
      return this;
    }
    return DayHours(
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

  /// Whether these hours hold the range from [from] to [to]: every range
  /// from a day start to a day start, an all-day range, which no hours
  /// limit; and any other whose start's [minuteOfDay] they hold as a start
  /// and whose end's minute on its last day ([endMinuteOfDay]) they hold
  /// as an end, so an overnight range may cross the hours' end and start.
  bool holdsTimes(DateTime from, DateTime to) {
    if (isDayStart(from) && isDayStart(to)) {
      return true;
    }
    return holdsStart(minuteOfDay(from)) && holdsEnd(endMinuteOfDay(to));
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
    return "DayHours(${isoTime(start)}-${isoTime(end)})";
  }
}
