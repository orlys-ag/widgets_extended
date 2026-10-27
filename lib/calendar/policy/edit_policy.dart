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

  /// A policy that allows only what each of [policies] allows, each answer
  /// the strictest of theirs: [mayMove], [mayEdit], [mayDelete],
  /// [admitsChange] and [allowsOverlaps] are true where every one's is;
  /// [resizableEdges] are the edges every one gives; [earliestStartOn] is
  /// the latest instant they give, and null where any gives null; and
  /// [dayLimit] is the least limit they give, and null where none gives
  /// one. With no policies it limits nothing.
  ///
  /// It asks [policies] in their order and stops once an answer settles
  /// its own: at a refusal, at no edge left that every policy asked gives,
  /// or at a null earliest start; so a later policy is not asked. An
  /// answer that throws throws out of it. It holds a copy of [policies], and
  /// compares equal to another of the same type argument and of equal
  /// policies in the same order.
  factory CalendarEditPolicy.all(Iterable<CalendarEditPolicy<T>> policies) {
    return _AllEditPolicies<T>(
      List<CalendarEditPolicy<T>>.unmodifiable(policies),
    );
  }

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
  /// A [DayLimitPolicy] combined with other policies
  /// ([CalendarEditPolicy.all]) gives them one. Null here.
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

/// A policy that limits only the days a range a gesture gives may cover,
/// to [dayLimit], and allows everything else: combined with other policies
/// ([CalendarEditPolicy.all]), it gives them that limit.
///
/// Two compare equal where their runtime types and [dayLimit] are the
/// same.
class DayLimitPolicy<T> extends CalendarEditPolicy<T> {
  /// Limits a range to [dayLimit] days; a [dayLimit] under 1 fails an
  /// assertion in a debug build.
  const DayLimitPolicy(this.dayLimit)
    : assert(
        dayLimit >= 1,
        "A DayLimitPolicy's dayLimit, $dayLimit, is under 1.",
      );

  @override
  final int dayLimit;

  @override
  bool operator ==(Object other) {
    return other.runtimeType == runtimeType &&
        other is DayLimitPolicy<T> &&
        other.dayLimit == dayLimit;
  }

  @override
  int get hashCode {
    return Object.hash(runtimeType, dayLimit);
  }

  @override
  String toString() {
    return "DayLimitPolicy($dayLimit)";
  }
}

/// The policy [CalendarEditPolicy.all] makes of [policies].
class _AllEditPolicies<T> extends CalendarEditPolicy<T> {
  const _AllEditPolicies(this.policies);

  /// The policies each answer asks, in order; unmodifiable.
  final List<CalendarEditPolicy<T>> policies;

  @override
  bool mayMove(CalendarEntry<T> entry, CalendarNow now) {
    for (final policy in policies) {
      if (!policy.mayMove(entry, now)) {
        return false;
      }
    }
    return true;
  }

  @override
  CalendarResizeEdges resizableEdges(CalendarEntry<T> entry, CalendarNow now) {
    var start = true;
    var end = true;
    for (final policy in policies) {
      final edges = policy.resizableEdges(entry, now);
      start = start && edges.hasStart;
      end = end && edges.hasEnd;
      if (!start && !end) {
        return CalendarResizeEdges.none;
      }
    }
    if (start) {
      return end ? CalendarResizeEdges.both : CalendarResizeEdges.start;
    }
    return CalendarResizeEdges.end;
  }

  @override
  bool mayEdit(CalendarEntry<T> entry, CalendarNow now) {
    for (final policy in policies) {
      if (!policy.mayEdit(entry, now)) {
        return false;
      }
    }
    return true;
  }

  @override
  bool mayDelete(CalendarEntry<T> entry, CalendarNow now) {
    for (final policy in policies) {
      if (!policy.mayDelete(entry, now)) {
        return false;
      }
    }
    return true;
  }

  @override
  bool admitsChange(
    CalendarEntry<T> entry,
    DateTime start,
    DateTime end,
    CalendarNow now,
  ) {
    for (final policy in policies) {
      if (!policy.admitsChange(entry, start, end, now)) {
        return false;
      }
    }
    return true;
  }

  @override
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    DateTime? latest;
    for (final policy in policies) {
      final earliest = policy.earliestStartOn(day, now);
      if (earliest == null) {
        return null;
      }
      if (latest == null || earliest.isAfter(latest)) {
        latest = earliest;
      }
    }
    return latest ?? day;
  }

  @override
  int? get dayLimit {
    int? least;
    for (final policy in policies) {
      final limit = policy.dayLimit;
      if (limit != null && (least == null || limit < least)) {
        least = limit;
      }
    }
    return least;
  }

  @override
  bool get allowsOverlaps {
    for (final policy in policies) {
      if (!policy.allowsOverlaps) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    return other.runtimeType == runtimeType &&
        other is _AllEditPolicies<T> &&
        listEquals(other.policies, policies);
  }

  @override
  int get hashCode {
    return Object.hashAll(policies);
  }

  @override
  String toString() {
    return "CalendarEditPolicy.all($policies)";
  }
}
