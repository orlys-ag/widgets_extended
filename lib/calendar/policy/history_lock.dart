/// The history lock: what may change of the entries before its boundary,
/// the start of today, or the current minute of it.
library;

import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';
import '../entries/calendar_entry.dart';

/// How the history lock holds an entry.
enum ItemHold {
  /// The entry starts at the boundary or after it: it changes freely, but
  /// never to start before the boundary.
  free,

  /// The entry starts before the boundary and ends after it: only its end
  /// changes, never to the boundary or before it, and it is not deleted.
  started,

  /// The entry ends at the boundary or before it: nothing of it changes,
  /// and it is not deleted.
  locked,
}

/// What a history lock keeps as it is: the entries, and the time for new
/// ones, before a boundary counted in minutes, a [dayNumber] times
/// [minutesPerDay] plus the minutes into that day.
@immutable
class HistoryLock {
  const HistoryLock._(this.boundary);

  /// No lock: every entry is free.
  static const HistoryLock none = HistoryLock._(null);

  /// The lock on [today] at [now]: none without [lockPast]; with it, the
  /// start of [today], or with [lockEarlierToday] too, [now]'s time of day
  /// on [today], rounded up to a whole minute, since a minute any part of
  /// which has passed is past.
  factory HistoryLock.of({
    required bool lockPast,
    required bool lockEarlierToday,
    required DateTime today,
    required DateTime now,
  }) {
    if (!lockPast) {
      return none;
    }
    var minute = 0;
    if (lockEarlierToday) {
      final into = Duration(
        seconds: now.second,
        milliseconds: now.millisecond,
        microseconds: now.microsecond,
      );
      minute = now.hour * 60 + now.minute + (into > Duration.zero ? 1 : 0);
    }
    return HistoryLock._(dayNumber(today) * minutesPerDay + minute);
  }

  /// The minute before which entries are held, or null without a lock.
  final int? boundary;

  /// The minute [time] starts at, counted as [boundary] is.
  static int startOf(CalendarEntryTime time) {
    return time.firstDay * minutesPerDay + time.start;
  }

  /// The minute [time] ends at, counted as [boundary] is.
  static int endOf(CalendarEntryTime time) {
    return (time.firstDay + time.dayCount - 1) * minutesPerDay + time.end;
  }

  ItemHold holdOf(CalendarEntryTime shape) {
    final boundary = this.boundary;
    if (boundary == null || startOf(shape) >= boundary) {
      return ItemHold.free;
    }
    return endOf(shape) > boundary ? ItemHold.started : ItemHold.locked;
  }

  /// Whether the entry [from] may become [to]: a free one may not start
  /// before the boundary, a started one keeps its start and ends after the
  /// boundary, and a locked one keeps its times.
  bool admits(CalendarEntryTime from, CalendarEntryTime to) {
    final boundary = this.boundary;
    if (boundary == null) {
      return true;
    }
    switch (holdOf(from)) {
      case ItemHold.free:
        return startOf(to) >= boundary;
      case ItemHold.started:
        return startOf(to) == startOf(from) && endOf(to) > boundary;
      case ItemHold.locked:
        return startOf(to) == startOf(from) && endOf(to) == endOf(from);
    }
  }

  /// Whether a new entry may start on [day] at [minute].
  bool admitsStart(DateTime day, int minute) {
    final boundary = this.boundary;
    return boundary == null ||
        dayNumber(day) * minutesPerDay + minute >= boundary;
  }

  /// The first minute of [day] on the [minutesPerSlot] grid a new entry may
  /// start at: 0 on a day after the boundary's, and [minutesPerDay] on one
  /// before it, where none may.
  int earliestStartOn(DateTime day) {
    final boundary = this.boundary;
    if (boundary == null) {
      return 0;
    }
    final into = boundary - dayNumber(day) * minutesPerDay;
    if (into <= 0) {
      return 0;
    }
    if (into >= minutesPerDay) {
      return minutesPerDay;
    }
    return (into + minutesPerSlot - 1) ~/ minutesPerSlot * minutesPerSlot;
  }

  @override
  bool operator ==(Object other) {
    return other is HistoryLock && other.boundary == boundary;
  }

  @override
  int get hashCode {
    return boundary.hashCode;
  }

  @override
  String toString() {
    return "HistoryLock($boundary)";
  }
}
