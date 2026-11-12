import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';
import '../entries/calendar_entry.dart';
import '../entries/calendar_schedule.dart';
import 'edit_policy.dart';
import 'edit_rules.dart';

/// What a form offers one kind of entry for its schedule: whether it takes
/// all-day, whether it may span days, and the lengths, in minutes, it
/// offers to pick directly.
///
/// Compared by value.
@immutable
final class CalendarScheduleOptions {
  /// Options that take all-day where [allowsAllDay], span days where
  /// [spansDays], and offer [lengthChoices].
  ///
  /// Throws an [ArgumentError], in every build, for a length choice under
  /// 1.
  CalendarScheduleOptions({
    this.allowsAllDay = true,
    this.spansDays = true,
    List<int> lengthChoices = defaultLengthChoices,
  }) : lengthChoices = List<int>.unmodifiable(lengthChoices) {
    for (final minutes in lengthChoices) {
      if (minutes < 1) {
        throw ArgumentError.value(
          lengthChoices,
          "lengthChoices",
          "holds $minutes, under 1",
        );
      }
    }
  }

  /// The options every kind takes unless it is given others: all-day,
  /// spanning days, and [defaultLengthChoices].
  static final CalendarScheduleOptions standard = CalendarScheduleOptions();

  /// 15 minutes, 30, an hour and two.
  static const List<int> defaultLengthChoices = <int>[15, 30, 60, 120];

  /// Whether the kind may be all-day.
  final bool allowsAllDay;

  /// Whether the kind may have a part in more than one day.
  final bool spansDays;

  /// The lengths a form offers to pick, in minutes. Unmodifiable.
  final List<int> lengthChoices;

  @override
  bool operator ==(Object other) {
    return other is CalendarScheduleOptions &&
        other.allowsAllDay == allowsAllDay &&
        other.spansDays == spansDays &&
        listEquals(other.lengthChoices, lengthChoices);
  }

  @override
  int get hashCode {
    return Object.hash(allowsAllDay, spansDays, Object.hashAll(lengthChoices));
  }

  @override
  String toString() {
    return "CalendarScheduleOptions(allowsAllDay: $allowsAllDay, "
        "spansDays: $spansDays, lengthChoices: $lengthChoices)";
  }
}

/// Why a [CalendarScheduleCheck] does not admit a schedule. The library
/// adds subclasses as it learns new reasons, so a host's `switch` over a
/// problem keeps a default case. A host names each in its own words.
///
/// Compared by type, and by the data a subclass carries.
@immutable
abstract base class CalendarScheduleProblem {
  /// Const, so a subclass can be const.
  const CalendarScheduleProblem();

  /// Whether the problem concerns the schedule's end; its start otherwise.
  bool get atEnd;

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
    return "$runtimeType";
  }
}

/// The end is not after the start.
final class CalendarScheduleEndNotAfterStart extends CalendarScheduleProblem {
  const CalendarScheduleEndNotAfterStart();

  @override
  bool get atEnd {
    return true;
  }
}

/// The schedule covers more days than the rules' day limit
/// ([CalendarEditRules.coversAtMost]).
final class CalendarScheduleTooManyDays extends CalendarScheduleProblem {
  const CalendarScheduleTooManyDays();

  @override
  bool get atEnd {
    return true;
  }
}

/// The schedule spans days, which its options do not take
/// ([CalendarScheduleOptions.spansDays]).
final class CalendarScheduleSpansDays extends CalendarScheduleProblem {
  const CalendarScheduleSpansDays();

  @override
  bool get atEnd {
    return true;
  }
}

/// The schedule is all-day, which its options do not take
/// ([CalendarScheduleOptions.allowsAllDay]).
final class CalendarScheduleAllDayNotAllowed extends CalendarScheduleProblem {
  const CalendarScheduleAllDayNotAllowed();

  @override
  bool get atEnd {
    return false;
  }
}

/// The clock skips the schedule's start.
final class CalendarScheduleStartSkipped extends CalendarScheduleProblem {
  const CalendarScheduleStartSkipped();

  @override
  bool get atEnd {
    return false;
  }
}

/// The clock skips the schedule's end.
final class CalendarScheduleEndSkipped extends CalendarScheduleProblem {
  const CalendarScheduleEndSkipped();

  @override
  bool get atEnd {
    return true;
  }
}

/// The rules' hours do not hold the timed schedule
/// ([CalendarDayHours.holdsTimes]): its start where [atEnd] is false, and
/// otherwise its end. Not reported of a stored entry whose start, end and
/// kind the schedule keeps, which a store writes outside its hours too.
final class CalendarScheduleOutsideHours extends CalendarScheduleProblem {
  /// Outside the hours at the end where [atEnd], and at the start
  /// otherwise.
  const CalendarScheduleOutsideHours({required this.atEnd});

  @override
  final bool atEnd;

  @override
  bool operator ==(Object other) {
    return other is CalendarScheduleOutsideHours && other.atEnd == atEnd;
  }

  @override
  int get hashCode {
    return Object.hash(runtimeType, atEnd);
  }

  @override
  String toString() {
    return "CalendarScheduleOutsideHours(atEnd: $atEnd)";
  }
}

/// No new entry may start on the start's day
/// ([CalendarEarliestStart.closesDay]).
final class CalendarSchedulePastDay extends CalendarScheduleProblem {
  const CalendarSchedulePastDay();

  @override
  bool get atEnd {
    return false;
  }
}

/// The start lies before the earliest start its day takes
/// ([CalendarEditRules.earliestStartOn]).
final class CalendarScheduleBeforeEarliest extends CalendarScheduleProblem {
  const CalendarScheduleBeforeEarliest();

  @override
  bool get atEnd {
    return false;
  }
}

/// The policy lets the stored entry not be edited
/// ([CalendarEditPolicy.mayEdit]).
final class CalendarScheduleLocked extends CalendarScheduleProblem {
  const CalendarScheduleLocked();

  @override
  bool get atEnd {
    return false;
  }
}

/// The stored entry may neither move nor resize at its start, and the
/// schedule moves its start.
final class CalendarScheduleStartKept extends CalendarScheduleProblem {
  const CalendarScheduleStartKept();

  @override
  bool get atEnd {
    return false;
  }
}

/// The stored entry may neither move nor resize at its start, and the
/// schedule changes whether it is all-day.
final class CalendarScheduleKindKept extends CalendarScheduleProblem {
  const CalendarScheduleKindKept();

  @override
  bool get atEnd {
    return false;
  }
}

/// The stored entry may neither move nor resize at its start, and the
/// policy refuses the schedule's end with the entry's start and kind.
final class CalendarScheduleEndInPast extends CalendarScheduleProblem {
  const CalendarScheduleEndInPast();

  @override
  bool get atEnd {
    return true;
  }
}

/// The schedule shares time with [other], which the policy refuses
/// ([CalendarEditPolicy.mayOverlap]).
final class CalendarScheduleOverlapRefused<T> extends CalendarScheduleProblem {
  /// The refused overlap with [other].
  const CalendarScheduleOverlapRefused(this.other);

  /// The entry the schedule may not share time with.
  final CalendarEntry<T> other;

  @override
  bool get atEnd {
    return false;
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarScheduleOverlapRefused<T> &&
        other.other == this.other;
  }

  @override
  int get hashCode {
    return Object.hash(runtimeType, other);
  }

  @override
  String toString() {
    return "CalendarScheduleOverlapRefused(${other.id})";
  }
}

/// The policy refuses the change to the stored entry
/// ([CalendarEditPolicy.admitsChange]) for a reason no other problem names.
final class CalendarScheduleRefused extends CalendarScheduleProblem {
  const CalendarScheduleRefused();

  @override
  bool get atEnd {
    return false;
  }
}

/// What the edit rules answer of one schedule for one entry at one time:
/// its [problems], the entries it [overlaps], the first minute its start
/// may take, and the [nextFree] range of its length.
///
/// The check decides nothing itself: every rule it reports is an answer of
/// [rules] or of their policy, and it only names which answer refused. The
/// schedule's times are made on [now]'s clock, as
/// [CalendarEditRules.earliestStartOn] reads a plain day
/// ([CalendarSchedule.timesOn]).
///
/// [problems] is answered when the check is made; [overlaps],
/// [firstStartMinute], [nextFree] and [startFixed] on their first read, each
/// once.
final class CalendarScheduleCheck<T> {
  /// The check of [schedule] under [rules] at [now], for the stored
  /// [entry], or for a new entry where it is null, with [others] the
  /// entries to test for overlaps and [options], or
  /// [CalendarScheduleOptions.standard] where it is null, the kind's.
  CalendarScheduleCheck({
    required this.schedule,
    required this.rules,
    required this.now,
    Iterable<CalendarEntry<T>> others = const <Never>[],
    this.entry,
    CalendarScheduleOptions? options,
  }) : _others = others,
       options = options ?? CalendarScheduleOptions.standard {
    _times = schedule.timesOn(zoneOf(now.time));
    problems = List<CalendarScheduleProblem>.unmodifiable(_findProblems());
  }

  /// The schedule checked.
  final CalendarSchedule schedule;

  /// The rules it is checked under.
  final CalendarEditRules<T> rules;

  /// The time it is checked at.
  final CalendarNow now;

  /// The stored entry the schedule changes, or null for a new entry.
  final CalendarEntry<T>? entry;

  /// The kind's options.
  final CalendarScheduleOptions options;

  final Iterable<CalendarEntry<T>> _others;

  /// The schedule's times on [now]'s clock, where they are times: null
  /// where the clock skips either end.
  late final ({DateTime start, DateTime end})? _times;

  /// Why the schedule is not admitted, in this order: end not after
  /// start, too many days, spanning days, all-day not allowed, start
  /// skipped, end skipped, outside the hours, past day, before the earliest
  /// start, locked, start kept, kind kept, end in the past, each refused
  /// overlap, and refused; empty where it is admitted. Unmodifiable.
  late final List<CalendarScheduleProblem> problems;

  /// Whether the schedule has no problems.
  bool get admitted {
    return problems.isEmpty;
  }

  /// Whether the stored entry may neither move nor resize at its start,
  /// so a form keeps its start and its kind; false for a new entry.
  late final bool startFixed = _fixesStart();

  bool _fixesStart() {
    final entry = this.entry;
    return entry != null &&
        !rules.policy.mayMove(entry, now) &&
        !rules.policy.resizableEdges(entry, now).hasStart;
  }

  /// The timed entries of the others, the stored entry left out, that
  /// share the timed schedule's time ([NoOverlapsPolicy.rangeSharesTime]);
  /// none for an all-day schedule, which shares time with nothing, or one
  /// whose times are not times. Unmodifiable.
  late final List<CalendarEntry<T>> overlaps = _findOverlaps();

  List<CalendarEntry<T>> _findOverlaps() {
    final times = _times;
    if (schedule.isAllDay || times == null || !times.end.isAfter(times.start)) {
      return const <Never>[];
    }
    final id = entry?.id;
    return List<CalendarEntry<T>>.unmodifiable(
      _others.where((other) {
        return (id == null || other.id != id) &&
            NoOverlapsPolicy.rangeSharesTime(times.start, times.end, other);
      }),
    );
  }

  /// The first minute of the schedule's start day a start may take
  /// ([CalendarEarliestStart.firstWallMinute]), 0 where the whole day
  /// may; null where none may ([CalendarEarliestStart.closesDay]).
  late final int? firstStartMinute = _findFirstStartMinute();

  int? _findFirstStartMinute() {
    final start = rules.earliestStartOn(schedule.startDay, now);
    if (start.closesDay) {
      return null;
    }
    return start.firstWallMinute -
        CalendarDates.dayNumber(schedule.startDay) *
            CalendarDates.minutesPerDay;
  }

  /// The first timed schedule of this one's length on its start day, from
  /// the later of its start and the day's earliest start, that no other
  /// entry shares time with, as [CalendarEditRules.firstSlot] finds it with
  /// that length; null for an all-day schedule, one that spans days or has
  /// no length, and where the day leaves no such range.
  late final CalendarSchedule? nextFree = _findNextFree();

  CalendarSchedule? _findNextFree() {
    if (schedule.isAllDay || schedule.spansDays || schedule.lengthMinutes < 1) {
      return null;
    }
    final id = entry?.id;
    final slot = rules.firstSlot(
      rules.earliestStartOn(schedule.startDay, now),
      clearOf: _others.where((other) {
        return id == null || other.id != id;
      }),
      from: schedule.startMinute,
      lengthMinutes: schedule.lengthMinutes,
    );
    if (slot == null) {
      return null;
    }
    return CalendarSchedule.of(slot.start, slot.end, isAllDay: false);
  }

  List<CalendarScheduleProblem> _findProblems() {
    final found = <CalendarScheduleProblem>[];
    final ordered = schedule.lengthMinutes > 0;
    if (!ordered) {
      found.add(const CalendarScheduleEndNotAfterStart());
    }
    final zone = zoneOf(now.time);
    final times = _times;
    final checkable = ordered && times != null;
    if (checkable && !rules.coversAtMost(times.start, times.end)) {
      found.add(const CalendarScheduleTooManyDays());
    }
    if (schedule.spansDays && !options.spansDays) {
      found.add(const CalendarScheduleSpansDays());
    }
    if (schedule.isAllDay && !options.allowsAllDay) {
      found.add(const CalendarScheduleAllDayNotAllowed());
    }
    if (schedule.startSkippedOn(zone)) {
      found.add(const CalendarScheduleStartSkipped());
    }
    if (schedule.endSkippedOn(zone)) {
      found.add(const CalendarScheduleEndSkipped());
    }
    if (!checkable) {
      return found;
    }
    final isAllDay = schedule.isAllDay;
    final entry = this.entry;
    // A store refuses only a new entry, or a change of an entry's start,
    // end or kind, outside its hours (CalendarHoursException), so a stored
    // entry the hours no longer hold keeps its times.
    final keepsTimes =
        entry != null &&
        times.start.isAtSameMomentAs(entry.start) &&
        times.end.isAtSameMomentAs(entry.end) &&
        isAllDay == entry.isAllDay;
    if (!keepsTimes &&
        !rules.hours.holdsTimes(times.start, times.end, isAllDay: isAllDay)) {
      found.add(
        CalendarScheduleOutsideHours(
          atEnd: rules.hours.holdsStart(CalendarDates.minuteOfDay(times.start)),
        ),
      );
    }
    final policy = rules.policy;
    var admitsChange = true;
    var asksEarliest = entry == null;
    if (entry != null) {
      admitsChange = policy.admitsChange(
        entry,
        times.start,
        times.end,
        now,
        isAllDay: isAllDay,
      );
      if (!admitsChange) {
        if (!policy.mayEdit(entry, now)) {
          found.add(const CalendarScheduleLocked());
        } else if (startFixed) {
          if (!times.start.isAtSameMomentAs(entry.start)) {
            found.add(const CalendarScheduleStartKept());
          } else if (isAllDay != entry.isAllDay) {
            found.add(const CalendarScheduleKindKept());
          }
          if (!policy.admitsChange(
            entry,
            entry.start,
            times.end,
            now,
            isAllDay: entry.isAllDay,
          )) {
            found.add(const CalendarScheduleEndInPast());
          }
        } else {
          asksEarliest = true;
        }
      }
    }
    if (asksEarliest) {
      final first = firstStartMinute;
      if (first == null) {
        found.add(const CalendarSchedulePastDay());
      } else if (schedule.startMinute < first) {
        found.add(const CalendarScheduleBeforeEarliest());
      }
    }
    if (!rules.allowsOverlaps && overlaps.isNotEmpty) {
      final candidate = CalendarOverlapCandidate<T>(
        start: times.start,
        end: times.end,
        entry: entry,
      );
      for (final other in overlaps) {
        if (!policy.mayOverlap(candidate, other)) {
          found.add(CalendarScheduleOverlapRefused<T>(other));
        }
      }
    }
    if (!admitsChange && found.isEmpty) {
      found.add(const CalendarScheduleRefused());
    }
    return found;
  }
}
