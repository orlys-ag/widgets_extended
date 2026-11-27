/// The data sources, stores, readers and functions the view tests share:
/// a data source whose reads wait for the test to answer them, a store
/// that records the scheduler's phase at each prefetch, a reader that
/// forwards to a store, filtering its entries and recording its asks, and
/// the write of a timed grid's move request a test hands it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:widgets_extended/calendar/views/move_request.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_data_source.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/store/calendar_store.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

/// A timed grid's move request handler that writes each request to [store]
/// ([CalendarStore.requestMove]) and catches the write's failure, whether
/// it throws within the call or its future fails, as `CalendarView` writes
/// one its host takes no move for.
Future<void> Function(CalendarMoveRequest<T> request) writeMoveTo<T>(
  CalendarStore<T> store,
) {
  return (request) {
    return Future<CalendarEntry<T>>.sync(() {
      return store.requestMove(request.requested);
    }).then<void>((_) {}, onError: (Object error) {});
  };
}

/// A reader that is no store: it forwards to [source] its listeners, both
/// kinds, its zone, and whether a day is read, failed or stale and an
/// entry pending; answers the entries of [source] that [keep] admits,
/// every one where it is null; and records in [asks] each [prefetch] and
/// [retry], with the scheduler's phase, before it forwards it. It keeps
/// the reader's own [statusOf] and [loadErrorOf].
final class ForwardingReader<T> extends CalendarEntryReader<T> {
  ForwardingReader(this.source, {this.keep});

  final CalendarStore<T> source;

  final bool Function(CalendarEntry<T> entry)? keep;

  final List<
    ({String member, DateTime? first, DateTime? last, SchedulerPhase phase})
  >
  asks =
      <
        ({String member, DateTime? first, DateTime? last, SchedulerPhase phase})
      >[];

  List<CalendarShownEntry<T>> _kept(List<CalendarShownEntry<T>> shown) {
    final admits = keep;
    if (admits == null) {
      return shown;
    }
    return <CalendarShownEntry<T>>[
      for (final entry in shown)
        if (admits(entry.entry)) entry,
    ];
  }

  @override
  void addListener(VoidCallback listener) {
    source.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    source.removeListener(listener);
  }

  @override
  void addStaleDaysListener(ValueChanged<CalendarStaleDays> listener) {
    source.addStaleDaysListener(listener);
  }

  @override
  void removeStaleDaysListener(ValueChanged<CalendarStaleDays> listener) {
    source.removeStaleDaysListener(listener);
  }

  @override
  Location? get zone {
    return source.zone;
  }

  @override
  List<CalendarShownEntry<T>> entriesOn(DateTime day) {
    return _kept(source.entriesOn(day));
  }

  @override
  List<CalendarShownEntry<T>> entriesBetween(DateTime first, DateTime last) {
    return _kept(source.entriesBetween(first, last));
  }

  @override
  bool dayHasShownEntries(DateTime day) {
    if (keep == null) {
      return source.dayHasShownEntries(day);
    }
    return entriesOn(day).isNotEmpty;
  }

  @override
  bool isPending(String id) {
    return source.isPending(id);
  }

  @override
  CalendarEntry<T>? storedEntry(String id) {
    final entry = source.storedEntry(id);
    final admits = keep;
    if (entry == null || admits == null || admits(entry)) {
      return entry;
    }
    return null;
  }

  @override
  bool isRead(DateTime day) {
    return source.isRead(day);
  }

  @override
  bool readFailed(DateTime day) {
    return source.readFailed(day);
  }

  @override
  bool isStale(DateTime day) {
    return source.isStale(day);
  }

  @override
  void prefetch(DateTime first, DateTime last) {
    asks.add((
      member: "prefetch",
      first: first,
      last: last,
      phase: SchedulerBinding.instance.schedulerPhase,
    ));
    source.prefetch(first, last);
  }

  @override
  void retry([DateTime? first, DateTime? last]) {
    asks.add((
      member: "retry",
      first: first,
      last: last,
      phase: SchedulerBinding.instance.schedulerPhase,
    ));
    source.retry(first, last);
  }
}

/// A data source whose reads wait in [held] for the test to answer them.
class HeldReads implements CalendarDataSource<String> {
  final List<
    ({
      DateTime first,
      DateTime last,
      Completer<List<CalendarEntry<String>>> answer,
    })
  >
  held =
      <
        ({
          DateTime first,
          DateTime last,
          Completer<List<CalendarEntry<String>>> answer,
        })
      >[];

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    final answer = Completer<List<CalendarEntry<String>>>();
    held.add((first: first, last: last, answer: answer));
    return answer.future;
  }

  @override
  Future<CalendarEntry<String>> create(CalendarEntry<String> draft) {
    throw UnimplementedError();
  }

  @override
  Future<CalendarEntry<String>> replace(CalendarEntry<String> entry) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }
}

/// A store with no entries that records the scheduler's phase at each
/// prefetch, and the days it reads.
final class PhaseStore extends MemoryCalendarStore<String> {
  final List<SchedulerPhase> prefetches = <SchedulerPhase>[];
  final List<(DateTime, DateTime)> reads = <(DateTime, DateTime)>[];

  @override
  void prefetch(DateTime first, DateTime last) {
    prefetches.add(SchedulerBinding.instance.schedulerPhase);
    reads.add((first, last));
  }
}
