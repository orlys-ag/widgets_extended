import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';

/// The times a form edits for one entry: a civil start day and minute, a
/// civil last day and the minute the entry ends at on it, whether it is
/// all-day, the clock its times were read on, and the pass of a repeated
/// stretch each edge lies in.
///
/// The days are civil days ([CalendarDates.dayNumber]) and the minutes wall
/// minutes, as a clock reads them, so a schedule holds a time a clock
/// skips, which [timesOn] then reports as null, instead of moving it. The
/// end minute runs from 1 to [CalendarDates.minutesPerDay], 1440 ending the
/// last day at its 24:00, the next day's start.
///
/// Where a clock turned back reads a stretch of wall time twice, the
/// schedule keeps whether its start lies in the later pass, and whether its
/// end lies in the first pass, the later one or neither, so [timesOn] on
/// the clock its times were read on gives those times back. A pass only
/// picks between the two instants of one wall time, on whichever clock
/// [timesOn] is asked, and has no effect where that clock reads the time
/// once.
///
/// Immutable: each `with...` call returns a new schedule. [withStartMinute]
/// and [withLength] keep [lengthMinutes], the elapsed minutes between the
/// schedule's instants, and [withStartDay] keeps both wall times;
/// [withEndDay] and [withEndMinute] may leave the end not after the start,
/// for a check to report. An all-day schedule keeps the timed minutes and
/// passes it had, which [withAllDay] off restores.
///
/// Two compare equal where their days, kind, timed minutes, passes and
/// clock, those an all-day schedule keeps included, do.
@immutable
final class CalendarSchedule {
  const CalendarSchedule._({
    required int startDayNumber,
    required int startMinute,
    required int endDayNumber,
    required int endMinute,
    required this.isAllDay,
    required bool startLater,
    required bool? endLater,
    required Location? clock,
  }) : _startDay = startDayNumber,
       _startMinute = startMinute,
       _endDay = endDayNumber,
       _endMinute = endMinute,
       _startLater = startLater,
       _endLater = endLater,
       _clock = clock;

  /// The schedule of an entry or a range from [start] to [end], all-day
  /// where [isAllDay], each edge read on its own clock: the start's day and
  /// minute, and the last day the range has a part in
  /// ([CalendarDates.lastDayNumberOf]) with the minute it ends at there
  /// ([CalendarDates.endMinuteOfDay]). An end at the instant its clock goes
  /// back, which ends a repeated stretch's first pass, reads as the
  /// stretch's end in that pass, its 02:00 where the clock goes back from
  /// 02:00 to 01:00, so the end minute stays from 1 to 1440. The schedule's
  /// clock is [start]'s.
  ///
  /// A timed start in the later pass of a stretch its clock reads twice
  /// holds that pass; the end holds the pass of the minute before it, the
  /// later one or the first where its clock reads that minute twice, and
  /// otherwise the start's later pass, or none, except that beside a later
  /// start an end at the first instant of a repeated stretch's start holds
  /// the first pass. A plain UTC time's clock reads every time once, so a
  /// plain UTC start holds no pass. An all-day schedule runs from its first
  /// day's 00:00 to its last day's 24:00, keeps those minutes as its timed
  /// ones, and holds no pass.
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
    final clock = clockOf(start);
    if (isAllDay) {
      return CalendarSchedule._(
        startDayNumber: CalendarDates.dayNumber(start),
        startMinute: 0,
        endDayNumber: CalendarDates.lastDayNumberOf(start, end),
        endMinute: CalendarDates.minutesPerDay,
        isAllDay: true,
        startLater: false,
        endLater: null,
        clock: clock,
      );
    }
    final startLater = _readsLater(start);
    final reading = _endReading(end, startLater);
    return CalendarSchedule._(
      startDayNumber: CalendarDates.dayNumber(start),
      startMinute: CalendarDates.minuteOfDay(start),
      endDayNumber: reading.day,
      endMinute: reading.minute,
      isAllDay: false,
      startLater: startLater,
      endLater: reading.later,
      clock: clock,
    );
  }

  /// Whether [time] is the later instant of a time its clock reads twice;
  /// false for a plain UTC time, whose clock repeats nothing.
  static bool _readsLater(DateTime time) {
    return (time is TZDateTime || !time.isUtc) &&
        CalendarDates.isLaterOccurrence(time);
  }

  /// The day, the minute and the pass an end at [end] reads, beside a start
  /// holding the later pass where [startLater]: at the instant the clock
  /// goes back, the minute after the one before it, the stretch's end, on
  /// the day that minute ends; otherwise [end]'s last day and its minute
  /// there. The pass is the minute before [end]'s: later where that is the
  /// later instant of a time read twice, first where it is the first, and
  /// otherwise the start's, later where [startLater] and none where not,
  /// except that beside a later start an end at the first instant of a
  /// time read twice, a repeated stretch's start, holds the first pass.
  static ({int day, int minute, bool? later}) _endReading(
    DateTime end,
    bool startLater,
  ) {
    final whole = end.subtract(
      Duration(
        seconds: end.second,
        milliseconds: end.millisecond,
        microseconds: end.microsecond,
      ),
    );
    final before = whole.subtract(const Duration(minutes: 1));
    final bool? later;
    if (_readsLater(before)) {
      later = true;
    } else if (isRepeatedTime(before)) {
      later = false;
    } else if (startLater) {
      // An end at the first instant of a repeated stretch's start reads the
      // minute before it once but its own minute twice: it holds the first
      // pass its instant reads, which a later pass would move an hour on.
      later = !isRepeatedTime(whole);
    } else {
      later = null;
    }
    if (isClockGoingBackAt(whole)) {
      return _endingAt(CalendarDates.wallMinuteOf(before) + 1, later);
    }
    final minute = CalendarDates.endMinuteOfDay(end);
    final day = minute == CalendarDates.minutesPerDay
        ? CalendarDates.dayNumber(end) - 1
        : CalendarDates.dayNumber(end);
    return (day: day, minute: minute, later: later);
  }

  /// An end at the wall minute [wall] in the pass [endLater] names, split
  /// into the day that minute ends and its minute there: its 24:00 ends the
  /// day before. The day is floored, so an end before the epoch's day keeps
  /// its minute from 1 to 1440.
  static ({int day, int minute, bool? later}) _endingAt(
    int wall,
    bool? endLater,
  ) {
    final before = wall - 1;
    final day =
        (before - before % CalendarDates.minutesPerDay) ~/
        CalendarDates.minutesPerDay;
    return (
      day: day,
      minute: wall - day * CalendarDates.minutesPerDay,
      later: endLater,
    );
  }

  final int _startDay;
  final int _endDay;

  /// The timed start's minute of [startDay], which an all-day schedule
  /// keeps.
  final int _startMinute;

  /// The timed end's minute of [endDay], which an all-day schedule keeps.
  final int _endMinute;

  /// Whether the start lies in the later pass of a stretch its clock reads
  /// twice.
  final bool _startLater;

  /// The pass the end lies in: true for the later one, false for the
  /// first, and null for none, which [timesOn] reads as a range's end
  /// ([CalendarDates.rangeEndAtWallMinute]).
  final bool? _endLater;

  /// The clock the schedule's times were read on, its start's
  /// ([clockOf]): null for the device's.
  final Location? _clock;

  /// The start's minute of [startDay], 0 for an all-day schedule.
  int get startMinute {
    return isAllDay ? 0 : _startMinute;
  }

  /// The end's minute of [endDay], from 1 to 1440; 1440 for an all-day
  /// schedule. An end at the instant a clock goes back reads the repeated
  /// stretch's end.
  int get endMinute {
    return isAllDay ? CalendarDates.minutesPerDay : _endMinute;
  }

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

  /// The length in minutes: for a timed schedule, the elapsed minutes from
  /// its start to its end as [timesOn] gives them on the clock its times
  /// were read on, and the wall minutes from its start to its end where
  /// that clock skips either; not above 0 where the end is not after the
  /// start. Whole days times 1440 for an all-day schedule.
  int get lengthMinutes {
    if (!isAllDay) {
      final times = timesOn(_clock);
      if (times != null) {
        return times.end.difference(times.start).inMinutes;
      }
    }
    return _wallEnd - _wallStart;
  }

  CalendarSchedule _copy({
    int? startDayNumber,
    int? startMinute,
    int? endDayNumber,
    int? endMinute,
    bool? isAllDay,
    ({bool? later})? end,
  }) {
    return CalendarSchedule._(
      startDayNumber: startDayNumber ?? _startDay,
      startMinute: startMinute ?? _startMinute,
      endDayNumber: endDayNumber ?? _endDay,
      endMinute: endMinute ?? _endMinute,
      isAllDay: isAllDay ?? this.isAllDay,
      startLater: _startLater,
      endLater: end == null ? _endLater : end.later,
      clock: _clock,
    );
  }

  /// This schedule with its end [length] minutes after its start: the
  /// start's instant in its pass on the schedule's clock plus [length]
  /// minutes of elapsed time, read as [CalendarSchedule.of] reads an end;
  /// and where that clock skips the start, [length] wall minutes after it,
  /// holding the start's later pass or none.
  CalendarSchedule _endingAfter(int length) {
    final start = timeAtWallMinuteInPass(
      _wallStart,
      later: _startLater,
      zone: _clock,
    );
    final end = start == null
        ? _endingAt(_wallStart + length, _startLater ? true : null)
        : _endReading(start.add(Duration(minutes: length)), _startLater);
    return _copy(
      endDayNumber: end.day,
      endMinute: end.minute,
      end: (later: end.later),
    );
  }

  /// This schedule starting on [day]'s civil day, its end moved by as many
  /// days, so it keeps both wall times, its passes and its clock. A pass
  /// has an effect only on a day whose clock reads its edge's time twice.
  CalendarSchedule withStartDay(DateTime day) {
    final shift = CalendarDates.dayNumber(day) - _startDay;
    return _copy(
      startDayNumber: _startDay + shift,
      endDayNumber: _endDay + shift,
    );
  }

  /// This timed schedule starting at [minute] of its start day in its
  /// start's pass, its end placed to keep [lengthMinutes]: at the new
  /// start's instant plus that many elapsed minutes, in the pass that
  /// instant reads, or where the clock skips the new start, that many wall
  /// minutes after it.
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
    return _copy(startMinute: minute)._endingAfter(length);
  }

  /// This schedule ending on [day]'s civil day at its end minute, in its
  /// end's pass.
  CalendarSchedule withEndDay(DateTime day) {
    return _copy(endDayNumber: CalendarDates.dayNumber(day));
  }

  /// This timed schedule ending at [minute] of its end day, in its end's
  /// pass.
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

  /// This timed schedule whose [lengthMinutes] is [minutes]: its end at its
  /// start's instant plus [minutes] elapsed minutes, in the pass that
  /// instant reads, on a later day where they run past its start day's
  /// 24:00, or where the clock skips the start, [minutes] wall minutes
  /// after it.
  ///
  /// Throws a [StateError] for an all-day schedule, and an [ArgumentError]
  /// for [minutes] under 1.
  CalendarSchedule withLength(int minutes) {
    _checkTimed("withLength");
    if (minutes < 1) {
      throw ArgumentError.value(minutes, "minutes", "is under 1");
    }
    return _endingAfter(minutes);
  }

  /// This schedule all-day where [on], over the same days, keeping its
  /// timed minutes, passes and clock; and timed otherwise, at the timed
  /// minutes and passes it kept.
  CalendarSchedule withAllDay(bool on) {
    if (on == isAllDay) {
      return this;
    }
    return _copy(isAllDay: on);
  }

  void _checkTimed(String method) {
    if (isAllDay) {
      throw StateError("$method takes a timed schedule, not an all-day one");
    }
  }

  /// The start and end on [zone]'s clock, the device's where it is null: an
  /// all-day schedule's day starts ([CalendarDates.dateOfDayNumber]), and a
  /// timed one's start at its wall minute in its pass, the earlier instant
  /// of a time the clock reads twice or the later one for the later pass
  /// ([CalendarDates.timeAtWallMinute]). The end is at its wall minute in
  /// its pass ([CalendarDates.endAtWallMinute]), a first pass ending at the
  /// instant the clock goes back where it ends as the repeated stretch
  /// does; an end holding no pass ends as a range from the start does
  /// ([CalendarDates.rangeEndAtWallMinute]). Null where the clock skips the
  /// start or the end.
  ({DateTime start, DateTime end})? timesOn(Location? zone) {
    if (isAllDay) {
      return (
        start: CalendarDates.dateOfDayNumber(_startDay, zone: zone),
        end: CalendarDates.dateOfDayNumber(_endDay + 1, zone: zone),
      );
    }
    final start = timeAtWallMinuteInPass(
      _wallStart,
      later: _startLater,
      zone: zone,
    );
    if (start == null) {
      return null;
    }
    final endLater = _endLater;
    final end = endLater == null
        ? CalendarDates.rangeEndAtWallMinute(start, _wallEnd)
        : endAtWallMinuteInPass(_wallEnd, later: endLater, zone: zone);
    if (end == null) {
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
        other._startMinute == _startMinute &&
        other._endDay == _endDay &&
        other._endMinute == _endMinute &&
        other.isAllDay == isAllDay &&
        other._startLater == _startLater &&
        other._endLater == _endLater &&
        other._clock == _clock;
  }

  @override
  int get hashCode {
    return Object.hash(
      _startDay,
      _startMinute,
      _endDay,
      _endMinute,
      isAllDay,
      _startLater,
      _endLater,
      _clock,
    );
  }

  @override
  String toString() {
    final start = CalendarDates.isoDate(startDay);
    final end = CalendarDates.isoDate(endDay);
    if (isAllDay) {
      return "CalendarSchedule($start to $end, all-day)";
    }
    final startPass = _startLater ? " (later pass)" : "";
    final endPass = switch (_endLater) {
      true => " (later pass)",
      false => " (first pass)",
      null => "",
    };
    return "CalendarSchedule($start ${CalendarDates.isoTime(startMinute)}"
        "$startPass to $end ${CalendarDates.isoTime(endMinute)}$endPass)";
  }
}
