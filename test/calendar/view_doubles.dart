/// The data sources, stores and functions the view tests share: a data
/// source whose reads wait for the test to answer them, a store that
/// records the scheduler's phase at each prefetch, and the write of a
/// timed grid's move request a test hands it.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:widgets_extended/calendar/views/move_request.dart';
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
