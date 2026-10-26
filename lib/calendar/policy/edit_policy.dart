/// The edit policy: the limits on what may change of a calendar's entries
/// and where new ones may start, and the time it answers at.
library;

import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';
import '../entries/calendar_entry.dart';

/// The time a [CalendarEditPolicy] answers at: the clock reading [time],
/// and [today], the day the calendar marks as today, which a host may pin
/// to another day than [time]'s.
///
/// Compared and hashed by [time] and [today]. [timeOnToday] is computed
/// once, when the value is made.
@immutable
class CalendarNow {
  /// The time [time], with [today] taken to its local midnight.
  factory CalendarNow({required DateTime time, required DateTime today}) {
    final day = DateTime(today.year, today.month, today.day);
    final into = Duration(
      seconds: time.second,
      milliseconds: time.millisecond,
      microseconds: time.microsecond,
    );
    var onToday = dateOnly(time) == day
        ? time.subtract(into)
        : DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (into > Duration.zero) {
      onToday = onToday.add(const Duration(minutes: 1));
    }
    return CalendarNow._(time, day, onToday);
  }

  const CalendarNow._(this.time, this.today, this.timeOnToday);

  /// The clock reading.
  final DateTime time;

  /// The local midnight of the day the calendar marks as today.
  final DateTime today;

  /// [time]'s time of day on [today], rounded up to a whole minute, since
  /// a minute any part of which has passed is past: the next day's start
  /// for a time past 23:59. Where [today] is [time]'s date it is [time]
  /// itself, rounded, so on a day whose clock repeats a stretch it keeps
  /// [time]'s occurrence.
  final DateTime timeOnToday;

  @override
  bool operator ==(Object other) {
    return other is CalendarNow && other.time == time && other.today == today;
  }

  @override
  int get hashCode {
    return Object.hash(time, today);
  }

  @override
  String toString() {
    return "CalendarNow($time, today ${isoDate(today)})";
  }
}

/// Which edges of an entry may be dragged to resize it: its start's, its
/// end's, both or neither.
enum CalendarResizeEdges {
  /// Neither edge.
  none,

  /// The start's edge alone.
  start,

  /// The end's edge alone.
  end,

  /// Both edges.
  both;

  /// Whether the start's edge may be dragged.
  bool get hasStart {
    return this == CalendarResizeEdges.start ||
        this == CalendarResizeEdges.both;
  }

  /// Whether the end's edge may be dragged.
  bool get hasEnd {
    return this == CalendarResizeEdges.end || this == CalendarResizeEdges.both;
  }
}

/// The limits on what may change of a calendar's entries, and where a new
/// entry may start: each answer asked of an entry, a change or a day, at
/// the time [CalendarNow] gives.
///
/// A host extends or implements it, overriding what it limits: every
/// member answers permissively here, so a subclass overriding nothing
/// limits nothing. The answers are questions: they must not mutate, and
/// answer from what they are given and the policy's own final fields
/// alone. An answer that throws is the host's error. A subclass with
/// fields compares them in `==` and `hashCode`.
///
/// The views ask it in edit mode only, and read [dayLimit] and
/// [allowsOverlaps] each time they take a policy. An answer that throws in
/// a drag's gates, which the views ask during a drag and inside their
/// pointer handlers, is reported through [FlutterError.reportError] and
/// refuses; one that throws in a build, a press or a tap goes through; and
/// one that throws where a new minute asks again what a view shows is
/// reported through [FlutterError.reportError], the view showing what the
/// last answer gave. A view given a policy not `==` to the last cancels a
/// move, a resize or a create range in flight, so a host's policy defines
/// value equality, or is kept as one instance across builds.
@immutable
abstract class CalendarEditPolicy<T> {
  /// Const, so a subclass can be const.
  const CalendarEditPolicy();

  /// Whether [entry] may move as a whole, to other times or days. True
  /// here.
  bool mayMove(CalendarEntry<T> entry, CalendarNow now) {
    return true;
  }

  /// Which of [entry]'s edges may be dragged to resize it. Both here.
  CalendarResizeEdges resizableEdges(CalendarEntry<T> entry, CalendarNow now) {
    return CalendarResizeEdges.both;
  }

  /// Whether [entry] may be edited outside a move or a resize, as a form
  /// edits its title or times. True here.
  bool mayEdit(CalendarEntry<T> entry, CalendarNow now) {
    return true;
  }

  /// Whether [entry] may be deleted. True here.
  bool mayDelete(CalendarEntry<T> entry, CalendarNow now) {
    return true;
  }

  /// Whether [entry] may take the times [start] to [end], which a move or
  /// a resize of it gives. True here.
  bool admitsChange(
    CalendarEntry<T> entry,
    DateTime start,
    DateTime end,
    CalendarNow now,
  ) {
    return true;
  }

  /// The earliest instant a new entry may start at on [day], a day's start:
  /// [day] itself for no limit; an instant on it, which carries the
  /// occurrence of a time [day]'s clock repeats; and null, or an instant on
  /// a later day, where none may start on it. [day] here.
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    return day;
  }

  /// The most days, counting each day it has any part of, that a range a
  /// gesture gives may cover; null for no limit, and otherwise at least 1.
  /// Null here.
  int? get dayLimit {
    return null;
  }

  /// Whether two entries may share time, which the views read for Week's
  /// and Day's moves, resizes and creates. Where it is true they go over
  /// other entries' times as over free ones; where it is false no move or
  /// resize gives a timed entry times another timed entry shares, and a
  /// move dropped onto one lands at the nearest free time or goes back.
  /// An all-day entry shares time with none, so neither answer limits a
  /// bar within the all-day strip. True here.
  bool get allowsOverlaps {
    return true;
  }
}

/// A policy that limits nothing, other than overlaps where
/// [allowsOverlaps] is false: the one a `CalendarView` given no
/// `editPolicy` takes.
///
/// Two compare equal where their runtime types and [allowsOverlaps] are
/// the same.
class UnrestrictedEditPolicy<T> extends CalendarEditPolicy<T> {
  /// Allows overlaps unless [allowsOverlaps] is false.
  const UnrestrictedEditPolicy({this.allowsOverlaps = true});

  @override
  final bool allowsOverlaps;

  @override
  bool operator ==(Object other) {
    return other.runtimeType == runtimeType &&
        other is UnrestrictedEditPolicy<T> &&
        other.allowsOverlaps == allowsOverlaps;
  }

  @override
  int get hashCode {
    return Object.hash(runtimeType, allowsOverlaps);
  }

  @override
  String toString() {
    return "UnrestrictedEditPolicy(allowsOverlaps: $allowsOverlaps)";
  }
}
