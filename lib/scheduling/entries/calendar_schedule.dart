import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';

/// The times a form edits for one entry: a civil start day and minute, a
/// civil last day and the minute the entry ends at on it, and whether it is
/// all-day.
///
/// The days are civil days ([CalendarDates.dayNumber]) and the minutes wall
/// minutes, as a clock reads them, so a schedule holds a time a clock
/// skips, which [timesOn] then reports as null, instead of moving it. The
/// end minute runs from 1 to [CalendarDates.minutesPerDay], 1440 ending the
/// last day at its 24:00, the next day's start.
///
/// Immutable: each `with...` call returns a new schedule. [withStartDay]
/// and [withStartMinute] move the end by the same wall minutes, so the
/// schedule keeps its length; [withEndDay] and [withEndMinute] may leave
/// the end not after the start, for a check to report. An all-day schedule
/// keeps the timed minutes it had, which [withAllDay] off restores.
///
/// Two compare equal where their days, minutes, kind and kept timed
/// minutes do.
@immutable
final class CalendarSchedule {
  const CalendarSchedule._({
    required int startDayNumber,
    required this.startMinute,
    required int endDayNumber,
    required this.endMinute,
    required this.isAllDay,
    required int timedStartMinute,
    required int timedEndMinute,
  }) : _startDay = startDayNumber,
       _endDay = endDayNumber,
       _timedStart = timedStartMinute,
       _timedEnd = timedEndMinute;

  /// The schedule of an entry or a range from [start] to [end], all-day
  /// where [isAllDay], each read on its own clock: the start's day and
  /// minute, and the last day the range has a part in
  /// ([CalendarDates.lastDayNumberOf]) with the minute it ends at there
  /// ([CalendarDates.endMinuteOfDay]). An all-day schedule runs from its
  /// first day's 00:00 to its last day's 24:00, and keeps those minutes as
  /// its timed ones.
  ///
  /// Throws an [ArgumentError], in every build, where [end] is not after
  /// [start].
  factory CalendarSchedule.of(
    DateTime start,
    DateTime end, {
    required bool isAllDay,
  }) {
    if (!end.isAfter(start)) {
      throw ArgumentError.value(end, "end", "is not after start, $start");
    }
    final startMinute = isAllDay ? 0 : CalendarDates.minuteOfDay(start);
    final endMinute = isAllDay
        ? CalendarDates.minutesPerDay
        : CalendarDates.endMinuteOfDay(end);
    return CalendarSchedule._(
      startDayNumber: CalendarDates.dayNumber(start),
      startMinute: startMinute,
      endDayNumber: CalendarDates.lastDayNumberOf(start, end),
      endMinute: endMinute,
      isAllDay: isAllDay,
      timedStartMinute: startMinute,
      timedEndMinute: endMinute,
    );
  }

  final int _startDay;
  final int _endDay;
  final int _timedStart;
  final int _timedEnd;

  /// The start's minute of [startDay], 0 for an all-day schedule.
  final int startMinute;

  /// The end's minute of [endDay], from 1 to 1440; 1440 for an all-day
  /// schedule.
  final int endMinute;

  /// Whether the schedule covers whole days, from [startDay]'s start to
  /// the start of the day after [endDay].
  final bool isAllDay;

  /// The start's civil day, as a plain local date.
  DateTime get startDay {
    return CalendarDates.dateOfDayNumber(_startDay);
  }

  /// The last civil day the schedule has a part in, as a plain local date.
  DateTime get endDay {
    return CalendarDates.dateOfDayNumber(_endDay);
  }

  /// Whether the schedule has a part in more than one day.
  bool get spansDays {
    return _endDay > _startDay;
  }

  int get _wallStart {
    return _startDay * CalendarDates.minutesPerDay + startMinute;
  }

  int get _wallEnd {
    return _endDay * CalendarDates.minutesPerDay + endMinute;
  }

  /// The wall minutes from the start to the end, not above 0 where the end
  /// is not after the start; whole days times 1440 for an all-day schedule.
  int get lengthMinutes {
    return _wallEnd - _wallStart;
  }

  CalendarSchedule _copy({
    int? startDayNumber,
    int? startMinute,
    int? endDayNumber,
    int? endMinute,
    bool? isAllDay,
    int? timedStartMinute,
    int? timedEndMinute,
  }) {
    return CalendarSchedule._(
      startDayNumber: startDayNumber ?? _startDay,
      startMinute: startMinute ?? this.startMinute,
      endDayNumber: endDayNumber ?? _endDay,
      endMinute: endMinute ?? this.endMinute,
      isAllDay: isAllDay ?? this.isAllDay,
      timedStartMinute: timedStartMinute ?? _timedStart,
      timedEndMinute: timedEndMinute ?? _timedEnd,
    );
  }

  /// This schedule with its end at the wall minute [wallEnd], on the day
  /// that minute ends: its 24:00 ends the day before.
  CalendarSchedule _endingAt(int wallEnd) {
    final day = (wallEnd - 1) ~/ CalendarDates.minutesPerDay;
    return _copy(
      endDayNumber: day,
      endMinute: wallEnd - day * CalendarDates.minutesPerDay,
    );
  }

  /// This schedule starting on [day]'s civil day, its end moved by as many
  /// days, so its length is kept.
  CalendarSchedule withStartDay(DateTime day) {
    final shift = CalendarDates.dayNumber(day) - _startDay;
    return _copy(
      startDayNumber: _startDay + shift,
      endDayNumber: _endDay + shift,
    );
  }

  /// This timed schedule starting at [minute] of its start day, its end
  /// moved by as many wall minutes, so its length is kept.
  ///
  /// Throws a [StateError] for an all-day schedule, and an [ArgumentError]
  /// for a [minute] outside 0 to 1439.
  CalendarSchedule withStartMinute(int minute) {
    _checkTimed("withStartMinute");
    RangeError.checkValueInInterval(
      minute,
      0,
      CalendarDates.minutesPerDay - 1,
      "minute",
    );
    final length = lengthMinutes;
    final moved = _copy(startMinute: minute);
    return moved._endingAt(moved._wallStart + length);
  }

  /// This schedule ending on [day]'s civil day at its end minute.
  CalendarSchedule withEndDay(DateTime day) {
    return _copy(endDayNumber: CalendarDates.dayNumber(day));
  }

  /// This timed schedule ending at [minute] of its end day.
  ///
  /// Throws a [StateError] for an all-day schedule, and an [ArgumentError]
  /// for a [minute] outside 1 to 1440.
  CalendarSchedule withEndMinute(int minute) {
    _checkTimed("withEndMinute");
    RangeError.checkValueInInterval(
      minute,
      1,
      CalendarDates.minutesPerDay,
      "minute",
    );
    return _copy(endMinute: minute);
  }

  /// This timed schedule ending [minutes] wall minutes after its start,
  /// on a later day where they run past its start day's 24:00.
  ///
  /// Throws a [StateError] for an all-day schedule, and an [ArgumentError]
  /// for [minutes] under 1.
  CalendarSchedule withLength(int minutes) {
    _checkTimed("withLength");
    if (minutes < 1) {
      throw ArgumentError.value(minutes, "minutes", "is under 1");
    }
    return _endingAt(_wallStart + minutes);
  }

  /// This schedule all-day where [on], over the same days, keeping its
  /// timed minutes; and timed otherwise, at the timed minutes it kept.
  CalendarSchedule withAllDay(bool on) {
    if (on == isAllDay) {
      return this;
    }
    if (on) {
      return _copy(
        startMinute: 0,
        endMinute: CalendarDates.minutesPerDay,
        isAllDay: true,
        timedStartMinute: startMinute,
        timedEndMinute: endMinute,
      );
    }
    return _copy(
      startMinute: _timedStart,
      endMinute: _timedEnd,
      isAllDay: false,
    );
  }

  void _checkTimed(String method) {
    if (isAllDay) {
      throw StateError("$method takes a timed schedule, not an all-day one");
    }
  }

  /// The start and end on [zone]'s clock, the device's where it is null: an
  /// all-day schedule's day starts ([CalendarDates.dateOfDayNumber]), and a
  /// timed one's start at its wall minute
  /// ([CalendarDates.timeAtWallMinute]) and end at its
  /// ([CalendarDates.endAtWallMinute]), each the earlier instant of a time
  /// the clock repeats. Null where the clock skips the start or the end.
  ({DateTime start, DateTime end})? timesOn(Location? zone) {
    if (isAllDay) {
      return (
        start: CalendarDates.dateOfDayNumber(_startDay, zone: zone),
        end: CalendarDates.dateOfDayNumber(_endDay + 1, zone: zone),
      );
    }
    final start = CalendarDates.timeAtWallMinute(_wallStart, zone: zone);
    final end = CalendarDates.endAtWallMinute(_wallEnd, zone: zone);
    if (start == null || end == null) {
      return null;
    }
    return (start: start, end: end);
  }

  /// Whether [timesOn] gives no start for [zone]'s clock.
  bool startSkippedOn(Location? zone) {
    return !isAllDay &&
        CalendarDates.timeAtWallMinute(_wallStart, zone: zone) == null;
  }

  /// Whether [timesOn] gives no end for [zone]'s clock.
  bool endSkippedOn(Location? zone) {
    return !isAllDay &&
        CalendarDates.endAtWallMinute(_wallEnd, zone: zone) == null;
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarSchedule &&
        other._startDay == _startDay &&
        other.startMinute == startMinute &&
        other._endDay == _endDay &&
        other.endMinute == endMinute &&
        other.isAllDay == isAllDay &&
        other._timedStart == _timedStart &&
        other._timedEnd == _timedEnd;
  }

  @override
  int get hashCode {
    return Object.hash(
      _startDay,
      startMinute,
      _endDay,
      endMinute,
      isAllDay,
      _timedStart,
      _timedEnd,
    );
  }

  @override
  String toString() {
    final start = CalendarDates.isoDate(startDay);
    final end = CalendarDates.isoDate(endDay);
    if (isAllDay) {
      return "CalendarSchedule($start to $end, all-day)";
    }
    return "CalendarSchedule($start ${CalendarDates.isoTime(startMinute)} to "
        "$end ${CalendarDates.isoTime(endMinute)})";
  }
}
