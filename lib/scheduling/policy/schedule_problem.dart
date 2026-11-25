/// The reasons a change or a schedule is refused: [CalendarScheduleProblem]
/// and its subclasses, which the schedule check reports and a host names in
/// its own words.
library;

import 'package:flutter/foundation.dart';

import '../entries/calendar_entry.dart';

/// Why a `CalendarScheduleCheck` does not admit a schedule. The library
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
/// (`CalendarEditRules.coversAtMost`).
final class CalendarScheduleTooManyDays extends CalendarScheduleProblem {
  const CalendarScheduleTooManyDays();

  @override
  bool get atEnd {
    return true;
  }
}

/// The schedule spans days, which its options do not take
/// (`CalendarScheduleOptions.spansDays`).
final class CalendarScheduleSpansDays extends CalendarScheduleProblem {
  const CalendarScheduleSpansDays();

  @override
  bool get atEnd {
    return true;
  }
}

/// The schedule is all-day, which its options do not take
/// (`CalendarScheduleOptions.allowsAllDay`).
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
/// (`CalendarDayHours.holdsTimes`): its start where [atEnd] is false, and
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
/// (`CalendarEarliestStart.closesDay`).
final class CalendarSchedulePastDay extends CalendarScheduleProblem {
  const CalendarSchedulePastDay();

  @override
  bool get atEnd {
    return false;
  }
}

/// The start lies before the earliest start its day takes
/// (`CalendarEditRules.earliestStartOn`).
final class CalendarScheduleBeforeEarliest extends CalendarScheduleProblem {
  const CalendarScheduleBeforeEarliest();

  @override
  bool get atEnd {
    return false;
  }
}

/// The policy lets the stored entry not be edited
/// (`CalendarEditPolicy.mayEdit`).
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
/// (`CalendarEditPolicy.mayOverlap`).
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
/// (`CalendarEditPolicy.admitsChange`) for a reason no other problem names.
final class CalendarScheduleRefused extends CalendarScheduleProblem {
  const CalendarScheduleRefused();

  @override
  bool get atEnd {
    return false;
  }
}
