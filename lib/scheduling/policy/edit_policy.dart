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
final class CalendarNow {
  /// The time [time], a UTC time taken as its local time, the same
  /// instant, with [today] taken to its local midnight.
  factory CalendarNow({required DateTime time, required DateTime today}) {
    final local = time.toLocal();
    final day = DateTime(today.year, today.month, today.day);
    final into = Duration(
      seconds: local.second,
      milliseconds: local.millisecond,
      microseconds: local.microsecond,
    );
    var onToday = CalendarDates.dateOnly(local) == day
        ? local.subtract(into)
        : DateTime(day.year, day.month, day.day, local.hour, local.minute);
    if (onToday.hour != local.hour || onToday.minute != local.minute) {
      // The constructor rolls a time today's clock skips past the skip by
      // the clock's change. The first minute after the skip is the time
      // of day's first reading, rounded up or not.
      onToday = _firstReadingFrom(
        CalendarDates.dayNumber(day) * CalendarDates.minutesPerDay +
            CalendarDates.minuteOfDay(local),
      );
    } else if (into > Duration.zero) {
      onToday = onToday.add(const Duration(minutes: 1));
    }
    return CalendarNow._(local, day, onToday);
  }

  const CalendarNow._(this.time, this.today, this.timeOnToday);

  /// The instant of the first wall minute from [wall]
  /// ([CalendarDates.wallMinuteOf]) that the clock reads
  /// ([CalendarDates.timeAtWallMinute]): [wall]'s own, or past a stretch the
  /// clock skips, the first minute after it. Ends at the first minute after a
  /// stretch the clock skips, which it reads.
  static DateTime _firstReadingFrom(int wall) {
    var minute = wall;
    var reading = CalendarDates.timeAtWallMinute(minute);
    while (reading == null) {
      minute++;
      reading = CalendarDates.timeAtWallMinute(minute);
    }
    return reading;
  }

  /// The clock reading, a local time: one given in UTC is kept as its
  /// local time, the same instant.
  final DateTime time;

  /// The local midnight of the day the calendar marks as today, read from
  /// the given today's year, month and day, so a UTC today names the same
  /// date.
  final DateTime today;

  /// [time]'s time of day on [today], rounded up to a whole minute, since
  /// a minute any part of which has passed is past: the next day's start
  /// for a time past 23:59, and where [today]'s clock skips that time of
  /// day, the first minute after the skip. Where [today] is [time]'s date
  /// it is [time] itself, rounded, so on a day whose clock repeats a
  /// stretch it keeps [time]'s occurrence.
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
    return "CalendarNow($time, today ${CalendarDates.isoDate(today)})";
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

/// The candidates [CalendarOverlapCandidate]'s constructor has built, in a
/// debug build; tests read differences.
int debugOverlapCandidateCount = 0;

/// Adds one to [debugOverlapCandidateCount] in a debug build.
void noteOverlapCandidate() {
  assert(() {
    debugOverlapCandidateCount++;
    return true;
  }());
}

/// A change [CalendarEditPolicy.mayOverlap] is asked about: the times it
/// gives, [start] to [end], and the [entry] it changes, none for a create.
///
/// Compared and hashed by [start], [end] and [entry].
@immutable
final class CalendarOverlapCandidate<T> {
  /// The change of [entry], or with none a create, to the times [start] to
  /// [end]. It checks neither time.
  CalendarOverlapCandidate({
    required this.start,
    required this.end,
    this.entry,
  }) {
    noteOverlapCandidate();
  }

  /// The start of the times asked about: those of the change.
  final DateTime start;

  /// The end of the times asked about: those of the change.
  final DateTime end;

  /// The entry a move or a resize changes, as stored, with its payload;
  /// null for a create.
  final CalendarEntry<T>? entry;

  @override
  bool operator ==(Object other) {
    return other is CalendarOverlapCandidate<T> &&
        other.start == start &&
        other.end == end &&
        other.entry == entry;
  }

  @override
  int get hashCode {
    return Object.hash(start, end, entry);
  }

  @override
  String toString() {
    return "CalendarOverlapCandidate("
        "${CalendarDates.isoDate(start)} "
        "${CalendarDates.isoTime(CalendarDates.minuteOfDay(start))} "
        "to ${CalendarDates.isoDate(end)} "
        "${CalendarDates.isoTime(CalendarDates.minuteOfDay(end))}, "
        "${entry ?? "a create"})";
  }
}

/// The limits on what may change of a calendar's entries, and where a new
/// entry may start: each answer asked of an entry, a change or a day, at
/// the time [CalendarNow] gives.
///
/// A host extends it, in a class it declares `final` or `base`, and
/// overrides what it limits: every member answers permissively here, so a
/// subclass overriding nothing limits nothing. The answers are questions:
/// they must not mutate, and answer from what they are given and the
/// policy's own final fields alone. An answer that throws is the host's
/// error. A subclass with fields compares them in `==` and `hashCode`.
///
/// The views ask it in edit mode only, and read [dayLimit] and
/// [allowsOverlaps] each time they take a policy. They ask [mayOverlap]
/// only where [allowsOverlaps] is false, and a per-pair ask through
/// [mayOverlap]'s default, or through [CalendarEditPolicy.all], reads
/// [allowsOverlaps] again. An answer that throws in
/// a drag's gates, which the views ask during a drag and inside their
/// pointer handlers, is reported through [FlutterError.reportError] and
/// refuses; one that throws in a build, a press or a tap goes through; and
/// one that throws where a new minute asks again what a view shows is
/// reported through [FlutterError.reportError], the view showing what the
/// last answer gave. A view given a policy not `==` to the last cancels a
/// move, a resize or a create range in flight, so a host's policy defines
/// value equality, or is kept as one instance across builds.
@immutable
abstract base class CalendarEditPolicy<T> {
  /// Const, so a subclass can be const.
  const CalendarEditPolicy();

  /// A policy that allows only what each of [policies] allows, each answer
  /// the strictest of theirs: [mayMove], [mayEdit], [mayDelete],
  /// [admitsChange] and [allowsOverlaps] are true where every one's is;
  /// [mayOverlap] is true where every one's is, a policy whose
  /// [allowsOverlaps] is true allowing every pair and not being asked;
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

  /// Whether [entry] may take the times [start] to [end], all-day where
  /// [isAllDay] and timed otherwise, which a move or a resize of it gives;
  /// a move between the all-day strip and the slots changes the kind,
  /// possibly with the times unchanged. True here.
  bool admitsChange(
    CalendarEntry<T> entry,
    DateTime start,
    DateTime end,
    CalendarNow now, {
    required bool isAllDay,
  }) {
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
  /// bar within the all-day strip. A [NoOverlapsPolicy] combined with
  /// other policies ([CalendarEditPolicy.all]) makes it false for them.
  /// True here.
  ///
  /// It is the fast path of [mayOverlap]: where it is true nothing asks
  /// [mayOverlap], and where it is false `CalendarEditRules.firstSlot`
  /// asks [mayOverlap] about each entry it is given that shares a slot's
  /// time.
  bool get allowsOverlaps {
    return true;
  }

  /// Whether the change [candidate] gives may share time with [other]:
  /// true lets the two share it. Here it answers [allowsOverlaps], so a
  /// policy that overrides only [allowsOverlaps], to false, refuses every
  /// pair it is asked about.
  ///
  /// It is asked only where [allowsOverlaps] is false, and only about a
  /// timed [other] that shares time with the candidate's times
  /// ([NoOverlapsPolicy.rangeSharesTime] of [CalendarOverlapCandidate.start]
  /// and [CalendarOverlapCandidate.end]) and that is not the entry the
  /// candidate changes ([CalendarOverlapCandidate.entry]).
  /// `CalendarEditRules.firstSlot` asks it about each entry it is given
  /// that shares a slot's time, with a candidate of the slot's times and no
  /// entry, and takes no slot that shares time with one it refuses. One
  /// test of a change can ask about one pair more than once, so the answer
  /// is a question, as every answer of the policy is.
  bool mayOverlap(
    CalendarOverlapCandidate<T> candidate,
    CalendarEntry<T> other,
  ) {
    return allowsOverlaps;
  }
}

/// A policy that limits nothing: the one a `CalendarView` given no
/// `editPolicy` takes.
///
/// Two compare equal where their runtime types are the same.
final class UnrestrictedEditPolicy<T> extends CalendarEditPolicy<T> {
  /// Limits nothing.
  const UnrestrictedEditPolicy();

  @override
  bool operator ==(Object other) {
    return other.runtimeType == runtimeType;
  }

  @override
  int get hashCode {
    return runtimeType.hashCode;
  }

  @override
  String toString() {
    return "UnrestrictedEditPolicy()";
  }
}

/// A policy that limits only the days a range a gesture gives may cover,
/// to [dayLimit], and allows everything else: combined with other policies
/// ([CalendarEditPolicy.all]), it gives them that limit.
///
/// Two compare equal where their runtime types and [dayLimit] are the
/// same.
final class DayLimitPolicy<T> extends CalendarEditPolicy<T> {
  /// Limits a range to [dayLimit] days.
  ///
  /// Throws an [ArgumentError], in every build, naming `dayLimit` for a
  /// [dayLimit] under 1.
  DayLimitPolicy(this.dayLimit) {
    if (dayLimit < 1) {
      throw ArgumentError.value(
        dayLimit,
        "dayLimit",
        "A day limit is at least 1",
      );
    }
  }

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

/// A policy that forbids only overlaps, answering false to
/// [allowsOverlaps], and allows everything else: combined with other
/// policies ([CalendarEditPolicy.all]), it forbids overlaps under them.
///
/// Two compare equal where their runtime types are the same.
final class NoOverlapsPolicy<T> extends CalendarEditPolicy<T> {
  /// Forbids overlaps.
  const NoOverlapsPolicy();

  /// Whether the half-open ranges `[aStart, aEnd)` and `[bStart, bEnd)` of
  /// instants meet.
  static bool timesOverlap(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }

  /// Whether the timed range from [start] to [end] shares time with [other]:
  /// never for an all-day [other] ([CalendarEntry.isAllDay]), which shares
  /// time with nothing, and otherwise where their instants meet
  /// ([timesOverlap]). The range is read as timed whatever its times, from a
  /// day start to a day start too, so a caller passes only a timed range: an
  /// all-day one shares time with nothing ([entriesShareTime]).
  static bool rangeSharesTime(
    DateTime start,
    DateTime end,
    CalendarEntry<Object?> other,
  ) {
    if (other.isAllDay) {
      return false;
    }
    return timesOverlap(start, end, other.start, other.end);
  }

  /// Whether [a] and [b] share time, as this policy reads it: never where
  /// either is all-day, and otherwise where their instants meet. A data
  /// source that refuses the writes this policy refuses tests each write's
  /// entry against the stored ones with it.
  static bool entriesShareTime(
    CalendarEntry<Object?> a,
    CalendarEntry<Object?> b,
  ) {
    if (a.isAllDay) {
      return false;
    }
    return rangeSharesTime(a.start, a.end, b);
  }

  @override
  bool get allowsOverlaps {
    return false;
  }

  @override
  bool operator ==(Object other) {
    return other.runtimeType == runtimeType;
  }

  @override
  int get hashCode {
    return runtimeType.hashCode;
  }

  @override
  String toString() {
    return "NoOverlapsPolicy()";
  }
}

/// The policy [CalendarEditPolicy.all] makes of [policies].
final class _AllEditPolicies<T> extends CalendarEditPolicy<T> {
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
    CalendarNow now, {
    required bool isAllDay,
  }) {
    for (final policy in policies) {
      if (!policy.admitsChange(entry, start, end, now, isAllDay: isAllDay)) {
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
  bool mayOverlap(
    CalendarOverlapCandidate<T> candidate,
    CalendarEntry<T> other,
  ) {
    for (final policy in policies) {
      if (!policy.allowsOverlaps && !policy.mayOverlap(candidate, other)) {
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
