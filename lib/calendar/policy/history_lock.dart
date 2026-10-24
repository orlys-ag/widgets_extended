/// The history lock: what may change of the entries before its boundary,
/// the start of today, or the current minute of it.
library;

import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';

/// How the history lock holds an entry.
enum EntryHold {
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
/// ones, before a boundary instant.
@immutable
class HistoryLock {
  const HistoryLock._(this.boundary);

  /// No lock: every entry is free.
  static const HistoryLock none = HistoryLock._(null);

  /// The lock on [today] at [now]: none without [lockPast]; with it, the
  /// start of [today], or with [lockEarlierToday] too, [now]'s time of day
  /// on [today], rounded up to a whole minute, since a minute any part of
  /// which has passed is past. Where [today] is [now]'s date the boundary
  /// is [now] itself, so on a day whose clock repeats a stretch it keeps
  /// [now]'s occurrence; a host that pins [today] to another day keeps the
  /// boundary on that day.
  factory HistoryLock.of({
    required bool lockPast,
    required bool lockEarlierToday,
    required DateTime today,
    required DateTime now,
  }) {
    if (!lockPast) {
      return none;
    }
    final day = DateTime(today.year, today.month, today.day);
    if (!lockEarlierToday) {
      return HistoryLock._(day);
    }
    final into = Duration(
      seconds: now.second,
      milliseconds: now.millisecond,
      microseconds: now.microsecond,
    );
    var boundary = dateOnly(now) == day
        ? now.subtract(into)
        : DateTime(today.year, today.month, today.day, now.hour, now.minute);
    if (into > Duration.zero) {
      boundary = boundary.add(const Duration(minutes: 1));
    }
    return HistoryLock._(boundary);
  }

  /// The instant before which entries are held, or null without a lock.
  final DateTime? boundary;

  /// How the lock holds an entry from [start] to [end]: free where it
  /// starts at the boundary or after it, started where it ends after it,
  /// and locked otherwise.
  EntryHold holdOf(DateTime start, DateTime end) {
    final boundary = this.boundary;
    if (boundary == null || !start.isBefore(boundary)) {
      return EntryHold.free;
    }
    return end.isAfter(boundary) ? EntryHold.started : EntryHold.locked;
  }

  /// Whether the entry from [fromStart] to [fromEnd] may become one from
  /// [toStart] to [toEnd]: a free one may not start before the boundary, a
  /// started one keeps its start and ends after the boundary, and a locked
  /// one keeps its times.
  bool admits(
    DateTime fromStart,
    DateTime fromEnd,
    DateTime toStart,
    DateTime toEnd,
  ) {
    final boundary = this.boundary;
    if (boundary == null) {
      return true;
    }
    switch (holdOf(fromStart, fromEnd)) {
      case EntryHold.free:
        return !toStart.isBefore(boundary);
      case EntryHold.started:
        return toStart == fromStart && toEnd.isAfter(boundary);
      case EntryHold.locked:
        return toStart == fromStart && toEnd == fromEnd;
    }
  }

  /// Whether a new entry may start at [start].
  bool admitsStart(DateTime start) {
    final boundary = this.boundary;
    return boundary == null || !start.isBefore(boundary);
  }

  /// The first minute of [day] on the grid of [slotMinutes]-minute slots
  /// from midnight a new entry may start at: 0 on a day after the
  /// boundary's, [minutesPerDay] on one before it, where none may, and on
  /// the boundary's day its [minuteOfDay] rounded up to the grid. On a day
  /// whose clock repeats a stretch, a minute in it is a time in
  /// [boundary]'s occurrence, which `timeAtWallMinute` given [boundary] as
  /// its `from` picks: in the stretch's second pass, the later instant.
  int earliestStartOn(DateTime day, {required int slotMinutes}) {
    final boundary = this.boundary;
    if (boundary == null) {
      return 0;
    }
    final on = dayNumber(day);
    final boundaryDay = dayNumber(boundary);
    if (on > boundaryDay) {
      return 0;
    }
    if (on < boundaryDay) {
      return minutesPerDay;
    }
    final into = isDayStart(boundary) ? 0 : minuteOfDay(boundary);
    return (into + slotMinutes - 1) ~/ slotMinutes * slotMinutes;
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
