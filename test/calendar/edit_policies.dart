/// The edit policies and the store the views' policy tests share: a policy
/// that records each ask, one that gives another its own day limit, one
/// whose answers a test scripts, and a store that records each move it is
/// asked for.
library;

import 'package:flutter/scheduler.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/edit_policy.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/entry_split.dart';

/// One ask of a [CountingEditPolicy]: the member's [name], the scheduler's
/// [phase] and [debugDropGateCount] at the ask, which groups the asks of
/// one gate call.
typedef PolicyAsk = ({String name, SchedulerPhase phase, int gate});

/// Forwards each answer to [inner], recording each ask in [asked]. Compared
/// by identity.
class CountingEditPolicy<T> extends CalendarEditPolicy<T> {
  CountingEditPolicy(this.inner);

  final CalendarEditPolicy<T> inner;

  final List<PolicyAsk> asked = <PolicyAsk>[];

  void _note(String name) {
    asked.add((
      name: name,
      phase: SchedulerBinding.instance.schedulerPhase,
      gate: debugDropGateCount,
    ));
  }

  @override
  bool mayMove(CalendarEntry<T> entry, CalendarNow now) {
    _note("mayMove");
    return inner.mayMove(entry, now);
  }

  @override
  CalendarResizeEdges resizableEdges(CalendarEntry<T> entry, CalendarNow now) {
    _note("resizableEdges");
    return inner.resizableEdges(entry, now);
  }

  @override
  bool mayEdit(CalendarEntry<T> entry, CalendarNow now) {
    _note("mayEdit");
    return inner.mayEdit(entry, now);
  }

  @override
  bool mayDelete(CalendarEntry<T> entry, CalendarNow now) {
    _note("mayDelete");
    return inner.mayDelete(entry, now);
  }

  @override
  bool admitsChange(
    CalendarEntry<T> entry,
    DateTime start,
    DateTime end,
    CalendarNow now,
  ) {
    _note("admitsChange");
    return inner.admitsChange(entry, start, end, now);
  }

  @override
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    _note("earliestStartOn");
    return inner.earliestStartOn(day, now);
  }

  @override
  int? get dayLimit {
    _note("dayLimit");
    return inner.dayLimit;
  }

  @override
  bool get allowsOverlaps {
    _note("allowsOverlaps");
    return inner.allowsOverlaps;
  }
}

/// Forwards each answer to [inner] but [dayLimit], which it answers
/// itself. Two compare equal where their [inner] and [dayLimit] do.
class DayLimitPolicy<T> extends CalendarEditPolicy<T> {
  const DayLimitPolicy(this.inner, this.dayLimit);

  final CalendarEditPolicy<T> inner;

  @override
  final int? dayLimit;

  @override
  bool mayMove(CalendarEntry<T> entry, CalendarNow now) {
    return inner.mayMove(entry, now);
  }

  @override
  CalendarResizeEdges resizableEdges(CalendarEntry<T> entry, CalendarNow now) {
    return inner.resizableEdges(entry, now);
  }

  @override
  bool mayEdit(CalendarEntry<T> entry, CalendarNow now) {
    return inner.mayEdit(entry, now);
  }

  @override
  bool mayDelete(CalendarEntry<T> entry, CalendarNow now) {
    return inner.mayDelete(entry, now);
  }

  @override
  bool admitsChange(
    CalendarEntry<T> entry,
    DateTime start,
    DateTime end,
    CalendarNow now,
  ) {
    return inner.admitsChange(entry, start, end, now);
  }

  @override
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    return inner.earliestStartOn(day, now);
  }

  @override
  bool get allowsOverlaps {
    return inner.allowsOverlaps;
  }

  @override
  bool operator ==(Object other) {
    return other is DayLimitPolicy<T> &&
        other.inner == inner &&
        other.dayLimit == dayLimit;
  }

  @override
  int get hashCode {
    return Object.hash(inner, dayLimit);
  }
}

/// What a [ScriptedEditPolicy] throws, naming the answer that threw.
class ScriptedThrow implements Exception {
  const ScriptedThrow(this.answer);

  final String answer;

  @override
  String toString() {
    return "ScriptedThrow($answer)";
  }
}

/// A policy whose answers a test scripts: no move for the ids [unmovable]
/// holds, the edges [edges] gives an id, no edit for [uneditable], no
/// delete for [undeletable], the earliest start [earliestStarts] gives a
/// day's start, and the change [admits] decides. Its earliest start throws
/// a [ScriptedThrow] for the day [throwsOn], and at a [CalendarNow.time]
/// of [throwsFrom] or later; its move answer throws one at a
/// [CalendarNow.time] of [movesThrowFrom] or later. Compared by identity.
class ScriptedEditPolicy<T> extends CalendarEditPolicy<T> {
  const ScriptedEditPolicy({
    this.unmovable = const <String>{},
    this.edges = const <String, CalendarResizeEdges>{},
    this.uneditable = const <String>{},
    this.undeletable = const <String>{},
    this.earliestStarts = const <DateTime, DateTime?>{},
    this.throwsOn,
    this.throwsFrom,
    this.movesThrowFrom,
    this.admits,
  });

  final Set<String> unmovable;
  final Map<String, CalendarResizeEdges> edges;
  final Set<String> uneditable;
  final Set<String> undeletable;

  /// By a day's start, the earliest start on it; a day it does not hold
  /// takes its own start.
  final Map<DateTime, DateTime?> earliestStarts;

  final DateTime? throwsOn;
  final DateTime? throwsFrom;
  final DateTime? movesThrowFrom;

  /// Whether an entry may take the times a change gives it; null admits
  /// every change. It may throw.
  final bool Function(CalendarEntry<T> entry, DateTime start, DateTime end)?
  admits;

  @override
  bool mayMove(CalendarEntry<T> entry, CalendarNow now) {
    final from = movesThrowFrom;
    if (from != null && !now.time.isBefore(from)) {
      throw const ScriptedThrow("mayMove");
    }
    return !unmovable.contains(entry.id);
  }

  @override
  CalendarResizeEdges resizableEdges(CalendarEntry<T> entry, CalendarNow now) {
    return edges[entry.id] ?? CalendarResizeEdges.both;
  }

  @override
  bool mayEdit(CalendarEntry<T> entry, CalendarNow now) {
    return !uneditable.contains(entry.id);
  }

  @override
  bool mayDelete(CalendarEntry<T> entry, CalendarNow now) {
    return !undeletable.contains(entry.id);
  }

  @override
  bool admitsChange(
    CalendarEntry<T> entry,
    DateTime start,
    DateTime end,
    CalendarNow now,
  ) {
    final admits = this.admits;
    return admits == null || admits(entry, start, end);
  }

  @override
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    final from = throwsFrom;
    if (day == throwsOn || (from != null && !now.time.isBefore(from))) {
      throw const ScriptedThrow("earliestStartOn");
    }
    return earliestStarts.containsKey(day) ? earliestStarts[day] : day;
  }
}

/// An in-memory store that records every move it is asked for, and the
/// range of days, as [dayNumber]s, of each [entriesBetween] it is asked
/// while no move of its own runs: the reads of its own overlap refusal
/// and of the split its write's notify runs within the call are left out.
class MoveRecordingStore extends MemoryCalendarStore<String> {
  MoveRecordingStore({super.entries, super.hours}) : super();

  final List<CalendarEntry<String>> moves = <CalendarEntry<String>>[];

  final List<({int first, int last})> reads = <({int first, int last})>[];

  bool _moving = false;

  @override
  void requestMove(CalendarEntry<String> requested) {
    moves.add(requested);
    _moving = true;
    try {
      super.requestMove(requested);
    } finally {
      _moving = false;
    }
  }

  @override
  List<CalendarShownEntry<String>> entriesBetween(
    DateTime first,
    DateTime last,
  ) {
    if (!_moving) {
      reads.add((first: dayNumber(first), last: dayNumber(last)));
    }
    return super.entriesBetween(first, last);
  }
}
