import 'package:flutter/foundation.dart';

import '../dates/calendar_dates.dart';
import '../entries/calendar_entry.dart';
import '../entries/calendar_schedule.dart';
import 'edit_policy.dart';
import 'edit_rules.dart';
import 'schedule_problem.dart';

/// What a form offers one kind of entry for its schedule: whether it takes
/// all-day and whether it may span days.
///
/// Compared by value.
@immutable
final class CalendarScheduleOptions {
  /// Options that take all-day where [allowsAllDay] and span days where
  /// [spansDays].
  const CalendarScheduleOptions({
    this.allowsAllDay = true,
    this.spansDays = true,
  });

  /// The options every kind takes unless it is given others: all-day and
  /// spanning days.
  static const CalendarScheduleOptions standard = CalendarScheduleOptions();

  /// Whether the kind may be all-day.
  final bool allowsAllDay;

  /// Whether the kind may have a part in more than one day.
  final bool spansDays;

  @override
  bool operator ==(Object other) {
    return other is CalendarScheduleOptions &&
        other.allowsAllDay == allowsAllDay &&
        other.spansDays == spansDays;
  }

  @override
  int get hashCode {
    return Object.hash(allowsAllDay, spansDays);
  }

  @override
  String toString() {
    return "CalendarScheduleOptions(allowsAllDay: $allowsAllDay, "
        "spansDays: $spansDays)";
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
/// [firstStartMinute], [nextFree], [startFixed], [firstStartDay] and
/// [endDays] on their first read, each once.
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

  /// Where a new entry may start on the schedule's start day
  /// ([CalendarEditRules.earliestStartOn]), which [firstStartMinute],
  /// [nextFree] and [problems] read: the policy is asked once.
  late final CalendarEarliestStart _startEarliest = rules.earliestStartOn(
    schedule.startDay,
    now,
  );

  /// Whether the schedule's end is after its start: as instants on [now]'s
  /// clock where it reads both times, and otherwise where its
  /// [CalendarSchedule.lengthMinutes] is positive. [timesChecked] and the
  /// end-not-after-start problem read it.
  late final bool _endAfterStart = _findEndAfterStart();

  bool _findEndAfterStart() {
    final times = _times;
    if (times != null) {
      return times.end.isAfter(times.start);
    }
    return schedule.lengthMinutes > 0;
  }

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

  /// Whether [now]'s clock reads both the schedule's times and its end is
  /// after its start there, as instants, so that [problems] holds every
  /// rule's answer. Where false, [problems] holds at most end not after
  /// start, spanning days, all-day not allowed, start skipped and end
  /// skipped.
  bool get timesChecked {
    return _times != null && _endAfterStart;
  }

  /// The check of [schedule] under this check's [rules] at its [now], for
  /// its [entry], against its others and with its [options].
  CalendarScheduleCheck<T> withSchedule(CalendarSchedule schedule) {
    return CalendarScheduleCheck<T>(
      schedule: schedule,
      rules: rules,
      now: now,
      others: _others,
      entry: entry,
      options: options,
    );
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

  /// The first minute of the schedule's start day a start may take, the
  /// first wall minute in the earliest start's occurrence
  /// ([CalendarEarliestStart.firstWallMinute]), 0 where the whole day
  /// may; null where none may ([CalendarEarliestStart.closesDay]).
  late final int? firstStartMinute = _findFirstStartMinute();

  int? _findFirstStartMinute() {
    final start = _startEarliest;
    if (start.closesDay) {
      return null;
    }
    return start.firstWallMinute -
        CalendarDates.dayNumber(schedule.startDay) *
            CalendarDates.minutesPerDay;
  }

  /// The first timed schedule of this one's length on its start day, in
  /// the rules' hours, from the later of its start and the day's earliest
  /// start, that no other entry shares time with and that the policy lets
  /// the stored [entry] take ([CalendarEditPolicy.admitsChange]), so this
  /// check admits it, as [CalendarEditRules.firstSlot] finds it with that
  /// length in elapsed minutes ([CalendarSchedule.lengthMinutes]); null for
  /// an all-day schedule, one that spans days or has no length, and where
  /// the day leaves no such range, as for a stored entry whose start the
  /// policy keeps ([startFixed]) wherever the search starts after it.
  ///
  /// Where [now]'s clock gives the schedule times, the search reads the
  /// day's clock in the occurrence of the later instant of its start and
  /// the earliest start's [CalendarEarliestStart.occurrence], from the
  /// first wall minute in that occurrence not before its start
  /// ([CalendarDates.firstWallMinuteNotBefore]), so a range in a repeated
  /// stretch's second pass is searched for in that pass; and a search from
  /// the first pass reads the second after it, before the time after the
  /// stretch, as the instants come.
  late final CalendarSchedule? nextFree = _findNextFree();

  CalendarSchedule? _findNextFree() {
    if (schedule.isAllDay || schedule.spansDays || schedule.lengthMinutes < 1) {
      return null;
    }
    final id = entry?.id;
    final earliest = _startEarliest;
    final times = _times;
    var from = schedule.startMinute;
    DateTime? occurrence;
    if (times != null) {
      final earliestOccurrence = earliest.occurrence;
      final searched =
          earliestOccurrence != null && earliestOccurrence.isAfter(times.start)
          ? earliestOccurrence
          : times.start;
      occurrence = searched;
      from =
          CalendarDates.firstWallMinuteNotBefore(times.start, from: searched) -
          CalendarDates.dayNumber(schedule.startDay) *
              CalendarDates.minutesPerDay;
    }
    final clear = _others.where((other) {
      return id == null || other.id != id;
    });
    final stored = entry;
    final slot = rules.firstSlot(
      earliest,
      clearOf: clear,
      from: from,
      occurrence: occurrence,
      elapsedMinutes: schedule.lengthMinutes,
      admits: stored == null
          ? null
          : (start, end) {
              return rules.policy.admitsChange(
                stored,
                start,
                end,
                now,
                isAllDay: false,
              );
            },
      throughSecondPass: true,
    );
    if (slot == null) {
      return null;
    }
    // [CalendarEditRules.firstSlot] takes a slot whose sharing entries the
    // policy all allows only where no slot is free.
    for (final other in clear) {
      if (NoOverlapsPolicy.rangeSharesTime(slot.start, slot.end, other)) {
        return null;
      }
    }
    return CalendarSchedule.of(slot.start, slot.end, isAllDay: false);
  }

  /// The first day a new start may lie on, as a plain local date, as the
  /// earliest starts of the day before [now]'s today and of today say
  /// ([CalendarEditRules.earliestStartOn]): null where the day before
  /// today is open to a start ([CalendarEarliestStart.closesDay] is false);
  /// otherwise today where today is open to one, and the day after it where
  /// it is not. Asks at most those two earliest starts.
  ///
  /// Under a policy that closes to a new start every day before the first
  /// it opens, as `HistoryLockPolicy` does, a new entry, or a stored one the
  /// policy lets move, started on a day before this one is admitted at no
  /// time.
  late final DateTime? firstStartDay = _findFirstStartDay();

  DateTime? _findFirstStartDay() {
    final today = CalendarDates.dayNumber(now.today);
    final yesterday = rules.earliestStartOn(
      CalendarDates.dateOfDayNumber(today - 1),
      now,
    );
    if (!yesterday.closesDay) {
      return null;
    }
    final opensToday = !rules
        .earliestStartOn(CalendarDates.dateOfDayNumber(today), now)
        .closesDay;
    return CalendarDates.dateOfDayNumber(opensToday ? today : today + 1);
  }

  /// The days the schedule's end may lie on, as plain local dates: from
  /// `first` to `last`, where a null `last` sets no last day.
  ///
  /// `first` is the schedule's start day ([CalendarSchedule.startDay]);
  /// where [startFixed], the first day from it whose 24:00, the start of the
  /// next day on [now]'s clock, the policy admits as the stored entry's end
  /// with its start and kind ([CalendarEditPolicy.admitsChange]), each day
  /// asked in turn up to the entry's last day; where none is, the day after
  /// the entry's last day, or the start day where that lies later. `last`
  /// is the start day where [options] take no spanning days
  /// ([CalendarScheduleOptions.spansDays]); otherwise the last of the
  /// [CalendarEditRules.dayLimit] days from the start day, where the rules
  /// have a limit; otherwise null. `first` lies after `last` where no day
  /// is.
  ///
  /// Under a policy that admits an in-progress entry's end wherever it
  /// admits an earlier one, as `HistoryLockPolicy` does, an end on a day
  /// before `first` or after `last` is admitted at no minute.
  late final ({DateTime first, DateTime? last}) endDays = _findEndDays();

  ({DateTime first, DateTime? last}) _findEndDays() {
    final startDay = CalendarDates.dayNumber(schedule.startDay);
    var first = startDay;
    final entry = this.entry;
    if (entry != null && startFixed) {
      final zone = zoneOf(now.time);
      final entryLastDay = CalendarDates.lastDayNumberOf(
        entry.start,
        entry.end,
      );
      first = entryLastDay + 1 > startDay ? entryLastDay + 1 : startDay;
      for (var day = startDay; day <= entryLastDay; day++) {
        final end = CalendarDates.dateOfDayNumber(day + 1, zone: zone);
        if (rules.policy.admitsChange(
          entry,
          entry.start,
          end,
          now,
          isAllDay: entry.isAllDay,
        )) {
          first = day;
          break;
        }
      }
    }
    int? last;
    if (!options.spansDays) {
      last = startDay;
    } else {
      final limit = rules.dayLimit;
      if (limit != null) {
        last = startDay + limit - 1;
      }
    }
    return (
      first: CalendarDates.dateOfDayNumber(first),
      last: last == null ? null : CalendarDates.dateOfDayNumber(last),
    );
  }

  List<CalendarScheduleProblem> _findProblems() {
    final found = <CalendarScheduleProblem>[];
    if (!_endAfterStart) {
      found.add(const CalendarScheduleEndNotAfterStart());
    }
    final zone = zoneOf(now.time);
    // Null where timesChecked is false, which ends the checks here.
    final times = timesChecked ? _times : null;
    if (times != null && !rules.coversAtMost(times.start, times.end)) {
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
    if (times == null) {
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
      final earliest = _startEarliest;
      if (earliest.closesDay) {
        found.add(const CalendarSchedulePastDay());
      } else if (!earliest.admitsDayStart &&
          times.start.isBefore(earliest.earliest!)) {
        // A start inside a minute that has begun is before it, as
        // CalendarEarliestStart.firstWallMinute rounds that minute up.
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
