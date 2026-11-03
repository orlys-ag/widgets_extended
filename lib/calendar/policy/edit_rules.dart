/// The edit rules: an edit policy joined with the hours and the slot
/// length a calendar schedules in, which answer what a view's gestures
/// and creates may give an entry.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';
import '../entries/calendar_entry.dart';
import 'edit_policy.dart';

/// Where a new entry may start on [day]: [earliest], what
/// [CalendarEditPolicy.earliestStartOn] answered for it, and the times a
/// create on [day] reads from that answer.
@immutable
final class CalendarEarliestStart {
  /// The start [earliest] that a policy gave [day], a local day's start,
  /// with a UTC [earliest] taken as its local time, the same instant.
  ///
  /// Throws an [ArgumentError], in every build, naming `day` for a [day]
  /// that is not a local day's start ([CalendarDates.isDayStart]), a UTC one
  /// included.
  CalendarEarliestStart(this.day, DateTime? earliest)
    : earliest = earliest?.toLocal() {
    if (!CalendarDates.isDayStart(day)) {
      throw ArgumentError.value(
        day,
        "day",
        "An earliest start's day is a local day start",
      );
    }
  }

  /// The day the answer is for, a local day's start.
  final DateTime day;

  /// The answer, a local time: [day] or an instant before it for no limit,
  /// an instant on [day] after its start, and null or an instant on a
  /// later day where no new entry may start on [day].
  final DateTime? earliest;

  /// Whether no new entry may start on [day]: [earliest] is null or on a
  /// later day.
  bool get closesDay {
    final earliest = this.earliest;
    return earliest == null ||
        CalendarDates.dayNumber(earliest) > CalendarDates.dayNumber(day);
  }

  /// Whether a new entry may start at [day]'s start, as an all-day one
  /// does: [earliest] is [day]'s start or before it.
  bool get admitsDayStart {
    final earliest = this.earliest;
    return earliest != null && !earliest.isAfter(day);
  }

  /// The instant whose occurrence a range starting on [day] takes its
  /// times in where [day]'s clock repeats them
  /// ([CalendarDates.timeAtWallMinute]): [earliest] where it lies after
  /// [day]'s start, and null otherwise.
  DateTime? get occurrence {
    final earliest = this.earliest;
    return earliest != null && earliest.isAfter(day) ? earliest : null;
  }

  /// The first wall minute ([CalendarDates.wallMinuteOf]) a start may
  /// take: [day]'s minute 0 where [admitsDayStart], the next day's minute
  /// 0 where [closesDay], and otherwise [earliest]'s, one more where it
  /// lies inside a minute, since a minute any part of which has passed is
  /// past.
  int get firstWallMinute {
    final number = CalendarDates.dayNumber(day);
    final earliest = this.earliest;
    if (earliest == null || CalendarDates.dayNumber(earliest) > number) {
      return (number + 1) * CalendarDates.minutesPerDay;
    }
    if (!earliest.isAfter(day)) {
      return number * CalendarDates.minutesPerDay;
    }
    final passed =
        earliest.second > 0 ||
        earliest.millisecond > 0 ||
        earliest.microsecond > 0;
    return CalendarDates.wallMinuteOf(earliest) + (passed ? 1 : 0);
  }

  /// The minute of [day] from which the slots of [slotMinutes] from
  /// midnight start no earlier than [earliest]:
  /// [CalendarDates.minutesPerDay] where [closesDay], and otherwise
  /// [firstWallMinute]'s minute of the day, rounded up to the slot grid.
  int firstSlotMinute(int slotMinutes) {
    if (closesDay) {
      return CalendarDates.minutesPerDay;
    }
    final minute =
        firstWallMinute -
        CalendarDates.dayNumber(day) * CalendarDates.minutesPerDay;
    return (minute + slotMinutes - 1) ~/ slotMinutes * slotMinutes;
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarEarliestStart &&
        other.day == day &&
        other.earliest == earliest;
  }

  @override
  int get hashCode {
    return Object.hash(day, earliest);
  }

  @override
  String toString() {
    return "CalendarEarliestStart(${CalendarDates.isoDate(day)}, $earliest)";
  }
}

/// A [policy] joined with the [hours] a calendar schedules in and the
/// length of its slots, [slotMinutes]: the answers a view asks of a change
/// to an entry and of a create, each asking [policy] what it needs and
/// nothing more.
///
/// It reads [CalendarEditPolicy.dayLimit] and
/// [CalendarEditPolicy.allowsOverlaps] once, when it is made, so no answer
/// asks them. It holds no entries: an answer that tests entries takes
/// them, and whether a change shares time with another entry is the
/// view's to test, from what it shows, where [allowsOverlaps] is false.
///
/// A `CalendarView` and its views make their rules of its `editPolicy`,
/// or an [UnrestrictedEditPolicy] where that is null, its store's hours,
/// which its build requires on the grid of its slots, and its
/// `slotMinutes`; a host that makes rules of the same three gets the
/// answers the calendar gives.
///
/// Two compare equal where their type arguments, policies, hours and slot
/// lengths do.
@immutable
final class CalendarEditRules<T> {
  /// The rules of [policy] in [hours] and slots of [slotMinutes], reading
  /// the policy's day limit and its answer on overlaps now.
  ///
  /// Throws an [ArgumentError], in every build, naming the first of these
  /// that it does not take: `slotMinutes`, one that
  /// `CalendarDates.slotMinuteChoices` does not hold; `hours`, hours off
  /// the grid of its slots ([CalendarDayHours.isOnSlotsOf]); and `policy`,
  /// a policy whose [CalendarEditPolicy.dayLimit] is under 1.
  CalendarEditRules({
    required CalendarEditPolicy<T> policy,
    required CalendarDayHours hours,
    required int slotMinutes,
  }) : this._(
         policy,
         hours,
         slotMinutes,
         policy.dayLimit,
         policy.allowsOverlaps,
       );

  CalendarEditRules._(
    this.policy,
    this.hours,
    this.slotMinutes,
    this.dayLimit,
    this.allowsOverlaps,
  ) {
    if (!CalendarDates.slotMinuteChoices.contains(slotMinutes)) {
      throw ArgumentError.value(
        slotMinutes,
        "slotMinutes",
        "is not one of $CalendarDates.slotMinuteChoices",
      );
    }
    if (!hours.isOnSlotsOf(slotMinutes)) {
      throw ArgumentError.value(
        hours,
        "hours",
        "do not start and end on the grid of $slotMinutes-minute slots",
      );
    }
    final limit = dayLimit;
    if (limit != null && limit < 1) {
      throw ArgumentError.value(
        policy,
        "policy",
        "gives a dayLimit, $limit, under 1",
      );
    }
  }

  /// The policy these rules ask.
  final CalendarEditPolicy<T> policy;

  /// The hours a timed change must lie in ([CalendarDayHours.holdsTimes]).
  final CalendarDayHours hours;

  /// The length of one slot, in minutes, which a create's search steps by.
  final int slotMinutes;

  /// [policy]'s [CalendarEditPolicy.dayLimit], as it answered when these
  /// rules were made: null or at least 1.
  final int? dayLimit;

  /// [policy]'s [CalendarEditPolicy.allowsOverlaps], as it answered when
  /// these rules were made.
  final bool allowsOverlaps;

  /// The rules of [policy] in [hours] and slots of [slotMinutes]: these
  /// rules where all three equal theirs; where only [policy] does, these
  /// rules' policy in the new hours and slots, with the day limit and the
  /// answer on overlaps these rules read, so asking nothing; and otherwise
  /// new rules, which read them of [policy].
  ///
  /// Throws an [ArgumentError], in every build, as the constructor does,
  /// for the [slotMinutes], the [hours] or the [policy] of the rules it
  /// makes.
  CalendarEditRules<T> updated({
    required CalendarEditPolicy<T> policy,
    required CalendarDayHours hours,
    required int slotMinutes,
  }) {
    if (policy != this.policy) {
      return CalendarEditRules<T>(
        policy: policy,
        hours: hours,
        slotMinutes: slotMinutes,
      );
    }
    if (hours == this.hours && slotMinutes == this.slotMinutes) {
      return this;
    }
    return CalendarEditRules<T>._(
      this.policy,
      hours,
      slotMinutes,
      dayLimit,
      allowsOverlaps,
    );
  }

  /// Whether [entry] may take the times [start] to [end] at [now], all-day
  /// where [isAllDay] and timed otherwise, as the caller tells it: the
  /// [hours] hold them ([CalendarDayHours.holdsTimes]), as they hold every
  /// all-day range and a timed one only within them, and [policy] admits
  /// the change of that kind ([CalendarEditPolicy.admitsChange]). Asks the
  /// policy once at most, and not where the hours refuse. It tests neither
  /// the day limit ([coversAtMost]) nor whether the times share time with
  /// another entry ([allowsOverlaps]).
  bool admitsTimes(
    CalendarEntry<T> entry,
    DateTime start,
    DateTime end,
    CalendarNow now, {
    required bool isAllDay,
  }) {
    return hours.holdsTimes(start, end, isAllDay: isAllDay) &&
        policy.admitsChange(entry, start, end, now, isAllDay: isAllDay);
  }

  /// Whether the range from [start] to [end] covers at most [dayLimit]
  /// days, counting each day it has any part of; every range does with no
  /// limit.
  bool coversAtMost(DateTime start, DateTime end) {
    final limit = dayLimit;
    return limit == null ||
        CalendarDates.lastDayNumberOf(start, end) -
                CalendarDates.dayNumber(start) +
                1 <=
            limit;
  }

  /// The range from [start] to [end], all-day where [isAllDay] and timed
  /// otherwise, as the caller tells it, held at [dayLimit]'s days: with
  /// [atEnd] its end moved, and otherwise its start. An all-day range ends
  /// at the start of the day after the limit's last day, or starts at the
  /// start of its first; a timed one ends at the hours' end on the limit's
  /// last day, the next day's start where they end at 24:00, or starts at
  /// the hours' start on its first, the day's start where they start at
  /// 00:00, so a held slot range ends or starts on a slot the hours hold.
  /// Null where that is a time the clock skips; the range itself with no
  /// limit.
  ({DateTime start, DateTime end})? heldToLimit(
    DateTime start,
    DateTime end, {
    required bool atEnd,
    required bool isAllDay,
  }) {
    final limit = dayLimit;
    if (limit == null) {
      return (start: start, end: end);
    }
    if (atEnd) {
      final lastDay = CalendarDates.dayNumber(start) + limit - 1;
      final held = isAllDay
          ? CalendarDates.dateOfDayNumber(lastDay + 1)
          : CalendarDates.endAtWallMinute(
              lastDay * CalendarDates.minutesPerDay + hours.end,
            );
      return held == null ? null : (start: start, end: held);
    }
    final firstDay = CalendarDates.lastDayNumberOf(start, end) - limit + 1;
    final held = isAllDay || hours.start == 0
        ? CalendarDates.dateOfDayNumber(firstDay)
        : CalendarDates.timeAtWallMinute(
            firstDay * CalendarDates.minutesPerDay + hours.start,
          );
    return held == null ? null : (start: held, end: end);
  }

  /// Where a new entry may start on [day], a day's start, at [now]: asks
  /// [policy] once ([CalendarEditPolicy.earliestStartOn]).
  CalendarEarliestStart earliestStartOn(DateTime day, CalendarNow now) {
    return CalendarEarliestStart(day, policy.earliestStartOn(day, now));
  }

  /// The first slot of [slotMinutes] on [start]'s day that a new entry may
  /// take: from the later of [from], or with none the [hours]' start, and
  /// [start]'s first slot minute ([CalendarEarliestStart.firstSlotMinute]),
  /// the first slot ending by [until], or with none the hours' end, whose
  /// start and end the day's clock reads, each in [start]'s occurrence
  /// ([CalendarEarliestStart.occurrence]), and that shares no time
  /// ([NoOverlapsPolicy.rangeSharesTime]) with any of [clearOf]; null where
  /// none does, as on a day [start] closes. [from] and [until] are minutes of
  /// the day.
  ///
  /// A slot is [slotMinutes] of wall-clock time
  /// ([CalendarDates.timeAtWallMinute]), so on a day whose clock repeats a
  /// stretch, one from the stretch's first pass to a time after the
  /// stretch's end lasts that stretch longer, and one from the first pass
  /// to the stretch's end ends with that pass, as the clock goes back.
  ({DateTime start, DateTime end})? firstSlot(
    CalendarEarliestStart start, {
    Iterable<CalendarEntry<T>> clearOf = const <Never>[],
    int? from,
    int? until,
  }) {
    return firstReadableSlot(
      start.day,
      math.max(from ?? hours.start, start.firstSlotMinute(slotMinutes)),
      until ?? hours.end,
      slotMinutes,
      occurrence: start.occurrence,
      isFree: (slotStart, slotEnd) {
        for (final other in clearOf) {
          if (NoOverlapsPolicy.rangeSharesTime(slotStart, slotEnd, other)) {
            return false;
          }
        }
        return true;
      },
    );
  }

  @override
  bool operator ==(Object other) {
    return other.runtimeType == runtimeType &&
        other is CalendarEditRules<T> &&
        other.policy == policy &&
        other.hours == hours &&
        other.slotMinutes == slotMinutes;
  }

  @override
  int get hashCode {
    return Object.hash(policy, hours, slotMinutes);
  }

  @override
  String toString() {
    return "CalendarEditRules($policy, $hours, $slotMinutes-minute slots)";
  }
}
