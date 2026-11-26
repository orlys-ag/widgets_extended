/// The history lock as an edit policy: what may change of the entries
/// before its boundary, the start of today or the current minute of it.
library;

import '../dates/calendar_dates.dart';
import '../entries/calendar_entry.dart';
import 'edit_policy.dart';
import 'schedule_problem.dart';

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
/// day count and allows overlaps; combined with a [DayLimitPolicy] or a
/// [NoOverlapsPolicy] ([CalendarEditPolicy.all]), it limits those too.
///
/// Two compare equal where their runtime types and [lockEarlierToday]
/// are the same. Each answer compares instants and kinds and reads
/// [CalendarNow]'s fields, so none allocates, except that
/// [earliestStartOn] builds the zone's day start of a plain day under a
/// zoned [CalendarNow].
final class HistoryLockPolicy<T> extends CalendarEditPolicy<T> {
  /// The lock at the start of today, or with [lockEarlierToday] at the
  /// current minute of it.
  const HistoryLockPolicy({this.lockEarlierToday = false});

  /// Whether the lock holds today up to the current minute too.
  final bool lockEarlierToday;

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

  /// For an entry starting at the boundary or after it: none where
  /// [CalendarChange.start] is not before the boundary; otherwise
  /// [CalendarSchedulePastDay] where the start is before today, or the
  /// boundary lies on a later day than today, as it does past 23:59 under
  /// [lockEarlierToday], and [CalendarScheduleBeforeEarliest] where it is
  /// on today before the boundary. For one in progress:
  /// [CalendarScheduleStartKept] where the change moves its start, or else
  /// [CalendarScheduleKindKept] where it changes its kind, each followed by
  /// [CalendarScheduleEndInPast] where the change's end is at the boundary
  /// or before it, which alone is the answer for a change that keeps both.
  /// For one that has ended: none where the change keeps both its times and
  /// its kind, and [CalendarScheduleLocked] otherwise. Each answer is a
  /// const list, so two refusals for one reason answer the identical list.
  @override
  List<CalendarScheduleProblem> refusalsOf(
    CalendarChange<T> change,
    CalendarNow now,
  ) {
    final boundary = _boundaryOf(now);
    final entry = change.entry;
    switch (_holdOf(entry, now)) {
      case _Hold.free:
        if (!change.start.isBefore(boundary)) {
          return const <CalendarScheduleProblem>[];
        }
        if (change.start.isBefore(now.today) || timeOnTodayOnLaterDay(now)) {
          return const <CalendarScheduleProblem>[CalendarSchedulePastDay()];
        }
        return const <CalendarScheduleProblem>[
          CalendarScheduleBeforeEarliest(),
        ];
      case _Hold.started:
        final endInPast = !change.end.isAfter(boundary);
        if (!sameTime(change.start, entry.start)) {
          return endInPast
              ? const <CalendarScheduleProblem>[
                  CalendarScheduleStartKept(),
                  CalendarScheduleEndInPast(),
                ]
              : const <CalendarScheduleProblem>[CalendarScheduleStartKept()];
        }
        if (change.isAllDay != entry.isAllDay) {
          return endInPast
              ? const <CalendarScheduleProblem>[
                  CalendarScheduleKindKept(),
                  CalendarScheduleEndInPast(),
                ]
              : const <CalendarScheduleProblem>[CalendarScheduleKindKept()];
        }
        return endInPast
            ? const <CalendarScheduleProblem>[CalendarScheduleEndInPast()]
            : const <CalendarScheduleProblem>[];
      case _Hold.locked:
        if (sameTime(change.start, entry.start) &&
            sameTime(change.end, entry.end) &&
            change.isAllDay == entry.isAllDay) {
          return const <CalendarScheduleProblem>[];
        }
        return const <CalendarScheduleProblem>[CalendarScheduleLocked()];
    }
  }

  /// [day] where it does not start before the boundary; the boundary on
  /// today's day, an instant on it or, past 23:59 under
  /// [lockEarlierToday], the next day's start; and null on an earlier day.
  /// A plain [day] under a zoned [now] is read as that date's day start in
  /// the zone.
  @override
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    final boundary = _boundaryOf(now);
    final zoned = zonedDayOf(day, zoneOf(boundary));
    if (!zoned.isBefore(boundary)) {
      return zoned;
    }
    return sameTime(zoned, now.today) ? boundary : null;
  }

  @override
  bool operator ==(Object other) {
    return other.runtimeType == runtimeType &&
        other is HistoryLockPolicy<T> &&
        other.lockEarlierToday == lockEarlierToday;
  }

  @override
  int get hashCode {
    return Object.hash(runtimeType, lockEarlierToday);
  }

  @override
  String toString() {
    return "HistoryLockPolicy(lockEarlierToday: $lockEarlierToday)";
  }
}
