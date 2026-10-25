/// The history lock as an edit policy: what may change of the entries
/// before its boundary, the start of today or the current minute of it.
library;

import '../entries/calendar_entry.dart';
import 'edit_policy.dart';

/// How the history lock holds an entry: free where it starts at the
/// boundary or after it, started where it starts before it and ends after
/// it, and locked where it ends at the boundary or before it.
enum _Hold { free, started, locked }

/// The history lock: before its boundary no entry moves, resizes or is
/// created. The boundary is [CalendarNow.today], or with
/// [lockEarlierToday] [CalendarNow.timeOnToday], the time of day on today
/// rounded up to a whole minute.
///
/// An entry starting at the boundary or after it moves, resizes, is
/// edited and is deleted, but never to start before the boundary. Of one
/// that starts before it and ends after it only the end changes, never to
/// the boundary or before it, by its end's edge; it is edited and not
/// deleted. One that ends at the boundary or before it neither changes
/// nor is deleted. A new entry starts on today's day from the boundary,
/// on a later day anywhere, and on an earlier day nowhere. It limits no
/// day count, and allows overlaps unless [allowsOverlaps] is false.
///
/// Two compare equal where their runtime types, [lockEarlierToday] and
/// [allowsOverlaps] are the same. Each answer compares instants and reads
/// [CalendarNow]'s fields, so none allocates.
class HistoryLockPolicy<T> extends CalendarEditPolicy<T> {
  /// The lock at the start of today, or with [lockEarlierToday] at the
  /// current minute of it; allows overlaps unless [allowsOverlaps] is
  /// false.
  const HistoryLockPolicy({
    this.lockEarlierToday = false,
    this.allowsOverlaps = true,
  });

  /// Whether the lock holds today up to the current minute too.
  final bool lockEarlierToday;

  @override
  final bool allowsOverlaps;

  /// The instant before which entries are held at [now].
  DateTime _boundaryOf(CalendarNow now) {
    return lockEarlierToday ? now.timeOnToday : now.today;
  }

  _Hold _holdOf(CalendarEntry<T> entry, CalendarNow now) {
    final boundary = _boundaryOf(now);
    if (!entry.start.isBefore(boundary)) {
      return _Hold.free;
    }
    return entry.end.isAfter(boundary) ? _Hold.started : _Hold.locked;
  }

  /// Whether [entry] starts at the boundary or after it.
  @override
  bool mayMove(CalendarEntry<T> entry, CalendarNow now) {
    return _holdOf(entry, now) == _Hold.free;
  }

  /// Both edges for an entry starting at the boundary or after it, its
  /// end's for one in progress, and none for one that has ended.
  @override
  CalendarResizeEdges resizableEdges(CalendarEntry<T> entry, CalendarNow now) {
    switch (_holdOf(entry, now)) {
      case _Hold.free:
        return CalendarResizeEdges.both;
      case _Hold.started:
        return CalendarResizeEdges.end;
      case _Hold.locked:
        return CalendarResizeEdges.none;
    }
  }

  /// Whether [entry] ends after the boundary.
  @override
  bool mayEdit(CalendarEntry<T> entry, CalendarNow now) {
    return _holdOf(entry, now) != _Hold.locked;
  }

  /// Whether [entry] starts at the boundary or after it.
  @override
  bool mayDelete(CalendarEntry<T> entry, CalendarNow now) {
    return _holdOf(entry, now) == _Hold.free;
  }

  /// For an entry starting at the boundary or after it, whether [start]
  /// is not before the boundary; for one in progress, whether it keeps its
  /// start and [end] is after the boundary; and for one that has ended,
  /// whether it keeps both its times.
  @override
  bool admitsChange(
    CalendarEntry<T> entry,
    DateTime start,
    DateTime end,
    CalendarNow now,
  ) {
    final boundary = _boundaryOf(now);
    switch (_holdOf(entry, now)) {
      case _Hold.free:
        return !start.isBefore(boundary);
      case _Hold.started:
        return start == entry.start && end.isAfter(boundary);
      case _Hold.locked:
        return start == entry.start && end == entry.end;
    }
  }

  /// [day] where it does not start before the boundary; the boundary on
  /// today's day, an instant on it or, past 23:59 under
  /// [lockEarlierToday], the next day's start; and null on an earlier day.
  @override
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    final boundary = _boundaryOf(now);
    if (!day.isBefore(boundary)) {
      return day;
    }
    return day == now.today ? boundary : null;
  }

  @override
  bool operator ==(Object other) {
    return other.runtimeType == runtimeType &&
        other is HistoryLockPolicy<T> &&
        other.lockEarlierToday == lockEarlierToday &&
        other.allowsOverlaps == allowsOverlaps;
  }

  @override
  int get hashCode {
    return Object.hash(runtimeType, lockEarlierToday, allowsOverlaps);
  }

  @override
  String toString() {
    return "HistoryLockPolicy(lockEarlierToday: $lockEarlierToday, "
        "allowsOverlaps: $allowsOverlaps)";
  }
}
