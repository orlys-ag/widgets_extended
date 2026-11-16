/// The controller's create on a day, [CalendarController.createOn]: the
/// slot it reports, the start after the current time on today, a refusal,
/// what it leaves alone: edit mode, the selection and an unbound
/// controller, and a create on a day the store has not read, which waits
/// for the day's read, and what ends the wait.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:widgets_extended/calendar/composition/calendar_header.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/views/create_details.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_data_source.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/policy/history_lock_policy.dart';
import 'package:widgets_extended/scheduling/store/caching_calendar_store.dart';
import 'package:widgets_extended/scheduling/store/calendar_store.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

import '../../scheduling/zones.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime thursday = DateTime(2026, 4, 23);
final DateTime friday = DateTime(2026, 4, 24);

/// Days outside April's Monday-first month grid, March 30 to May 3, which
/// a calendar on [thursday] asks its store to show.
final DateTime may14 = DateTime(2026, 5, 14);
final DateTime may15 = DateTime(2026, 5, 15);

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

  /// Whether a held read covers [day].
  bool reads(DateTime day) {
    return held.any((read) {
      return !read.first.isAfter(day) && !read.last.isBefore(day);
    });
  }

  /// Fails with [error] every held read covering [day] not yet answered.
  void failReadsOf(DateTime day, Object error) {
    for (final read in held) {
      if (!read.answer.isCompleted &&
          !read.first.isAfter(day) &&
          !read.last.isBefore(day)) {
        read.answer.completeError(error);
      }
    }
  }

  /// Answers every held read not yet answered with [entries].
  void answerAll([List<CalendarEntry<String>> entries = const []]) {
    for (final read in held) {
      if (!read.answer.isCompleted) {
        read.answer.complete(entries);
      }
    }
  }

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

/// 11:07 on Tuesday April 21 2026.
DateTime fixedClock() {
  return DateTime(2026, 4, 21, 11, 7);
}

/// [hour]:[minute] on [day].
DateTime at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

/// An entry from [start] to [end] minutes after [day]'s midnight.
CalendarEntry<String> entryOf(String id, DateTime day, int start, int end) {
  return CalendarEntry<String>(
    id: id,
    start: DateTime(day.year, day.month, day.day, 0, start),
    end: DateTime(day.year, day.month, day.day, 0, end),
    title: id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

const Rect fabRect = Rect.fromLTWH(700.0, 500.0, 56.0, 56.0);

/// A policy whose new entries start at 14:00 on each day at the earliest.
final class AfternoonPolicy extends CalendarEditPolicy<String> {
  const AfternoonPolicy();

  @override
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    return DateTime(day.year, day.month, day.day, 14);
  }
}

void main() {
  late List<CalendarCreateDetails> creates;
  late List<DateTime> refused;
  late List<DateTime> readFailed;

  setUp(() {
    creates = <CalendarCreateDetails>[];
    refused = <DateTime>[];
    readFailed = <DateTime>[];
  });

  /// Pumps a calendar on [store] under [controller], or a new one on
  /// [view] and [thursday], whose loading state is still, so a held read
  /// lets it settle.
  Future<CalendarController> pumpCalendar(
    WidgetTester tester, {
    required CalendarStore<String> store,
    CalendarController? controller,
    CalendarViewKind view = CalendarViewKind.week,
    bool editable = true,
    CalendarEditPolicy<String>? policy,
    bool reportsCreates = true,
    Future<void> Function(CalendarCreateDetails details)? onCreateRange,
  }) async {
    final shown =
        controller ?? CalendarController(view: view, selectedDay: thursday);
    if (controller == null) {
      addTearDown(shown.dispose);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: CalendarView<String>(
          store: store,
          controller: shown,
          clock: fixedClock,
          editable: editable,
          editPolicy: policy,
          onCreateRange: !reportsCreates
              ? null
              : onCreateRange ??
                    (details) async {
                      creates.add(details);
                    },
          onCreateRefused: refused.add,
          onCreateReadFailed: readFailed.add,
          loadingBuilder: (context, state) {
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return shown;
  }

  /// A caching store over [source], disposed at the test's end.
  CachingCalendarStore<String> cachingOf(HeldReads source) {
    final store = CachingCalendarStore<String>(dataSource: source);
    addTearDown(store.dispose);
    return store;
  }

  /// A Month calendar on [thursday] over [source], whose read of April's
  /// grid has answered with no entries.
  Future<(CachingCalendarStore<String>, CalendarController)> pumpRead(
    WidgetTester tester,
    HeldReads source, {
    Future<void> Function(CalendarCreateDetails details)? onCreateRange,
  }) async {
    final store = cachingOf(source);
    final controller = await pumpCalendar(
      tester,
      store: store,
      view: CalendarViewKind.month,
      onCreateRange: onCreateRange,
    );
    source.answerAll();
    await tester.pumpAndSettle();
    // Setup sanity: the grid is read, and May 14 is not.
    expect(store.isRead(thursday), isTrue);
    expect(store.isRead(may14), isFalse);
    return (store, controller);
  }

  /// The one slot at [start] to [end] minutes after [day]'s midnight, at
  /// [fabRect], with no length chosen.
  CalendarCreateDetails slotOn(DateTime day, int start, int end) {
    return CalendarCreateDetails(
      range: CalendarCreateRange(
        start: DateTime(day.year, day.month, day.day, 0, start),
        end: DateTime(day.year, day.month, day.day, 0, end),
      ),
      globalRect: fabRect,
      userChoseLength: false,
    );
  }

  MemoryCalendarStore<String> storeOf(
    List<CalendarEntry<String>> entries, {
    CalendarDayHours? hours,
  }) {
    final store = hours == null
        ? MemoryCalendarStore<String>(entries: entries)
        : MemoryCalendarStore<String>(entries: entries, hours: hours);
    addTearDown(store.dispose);
    return store;
  }

  testWidgets("CR1 a create on a later day reports its first slot no entry "
      "shares, at the rect given, with no length chosen, and selects "
      "nothing", (tester) async {
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("early", friday, 0, 30),
    ]);
    final controller = await pumpCalendar(
      tester,
      store: store,
      view: CalendarViewKind.month,
    );
    final done = controller.createOn(friday, globalRect: fabRect);
    expect(done, isNotNull);
    await tester.pumpAndSettle();
    expect(creates, <CalendarCreateDetails>[
      CalendarCreateDetails(
        range: CalendarCreateRange(
          start: at(friday, 0, 30),
          end: at(friday, 0, 45),
        ),
        globalRect: fabRect,
        userChoseLength: false,
      ),
    ]);
    expect(controller.selectedDay, thursday);
    expect(controller.view, CalendarViewKind.month);
  });

  testWidgets("CR2 a create on today starts at the first slot after the "
      "current time that no entry shares", (tester) async {
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("standup", tuesday, 11 * 60 + 15, 11 * 60 + 30),
    ]);
    final controller = await pumpCalendar(tester, store: store);
    controller.createOn(tuesday, globalRect: fabRect);
    await tester.pumpAndSettle();
    expect(creates.map((details) => details.range), <CalendarCreateRange>[
      CalendarCreateRange(start: at(tuesday, 11, 30), end: at(tuesday, 11, 45)),
    ]);
  });

  testWidgets("CR3 a create on today starts at the policy's earliest start "
      "where it is later than the current time", (tester) async {
    final store = storeOf(<CalendarEntry<String>>[]);
    final controller = await pumpCalendar(
      tester,
      store: store,
      policy: const AfternoonPolicy(),
    );
    controller.createOn(tuesday, globalRect: fabRect);
    await tester.pumpAndSettle();
    expect(creates.single.range.start, at(tuesday, 14));
  });

  testWidgets("CR4 a create on today with no slot left after the current "
      "time in the hours reports a refusal and returns null", (tester) async {
    final store = storeOf(
      <CalendarEntry<String>>[],
      hours: CalendarDayHours(8 * 60, 11 * 60),
    );
    final controller = await pumpCalendar(tester, store: store);
    expect(controller.createOn(tuesday, globalRect: fabRect), isNull);
    await tester.pumpAndSettle();
    expect(refused, <DateTime>[tuesday]);
    expect(creates, isEmpty);
  });

  testWidgets("CR5 a create on a day before today starts where the policy "
      "lets it: the hours' start with no policy, and a refusal under the "
      "history lock", (tester) async {
    final store = storeOf(<CalendarEntry<String>>[]);
    final controller = await pumpCalendar(tester, store: store);
    controller.createOn(monday, globalRect: fabRect);
    await tester.pumpAndSettle();
    expect(creates.single.range.start, at(monday, 0));

    final locked = await pumpCalendar(
      tester,
      store: store,
      policy: const HistoryLockPolicy<String>(),
    );
    expect(locked.createOn(monday, globalRect: fabRect), isNull);
    await tester.pumpAndSettle();
    expect(refused, <DateTime>[monday]);
    expect(creates, hasLength(1));
  });

  testWidgets("CR6 out of edit mode, and in every view, a create reports "
      "as it does in edit mode", (tester) async {
    final store = storeOf(<CalendarEntry<String>>[]);
    for (final view in CalendarViewKind.values) {
      creates.clear();
      final controller = await pumpCalendar(
        tester,
        store: store,
        view: view,
        editable: false,
      );
      controller.createOn(thursday, globalRect: fabRect);
      await tester.pumpAndSettle();
      expect(creates.map((details) => details.range), <CalendarCreateRange>[
        CalendarCreateRange(start: at(thursday, 0), end: at(thursday, 0, 15)),
      ], reason: "$view");
    }
  });

  testWidgets("CR7 the future returned completes when the host's does, and "
      "with no onCreateRange at once", (tester) async {
    final store = storeOf(<CalendarEntry<String>>[]);
    final host = Completer<void>();
    final controller = await pumpCalendar(
      tester,
      store: store,
      onCreateRange: (details) {
        return host.future;
      },
    );
    var completed = false;
    controller.createOn(thursday, globalRect: fabRect)!.then((_) {
      completed = true;
    });
    await tester.pump();
    expect(completed, isFalse);
    host.complete();
    await tester.pump();
    expect(completed, isTrue);

    final quiet = await pumpCalendar(
      tester,
      store: store,
      reportsCreates: false,
    );
    var quietCompleted = false;
    quiet.createOn(thursday, globalRect: fabRect)!.then((_) {
      quietCompleted = true;
    });
    await tester.pump();
    expect(quietCompleted, isTrue);
  });

  test("CR8 an unbound controller reports nothing and returns null", () {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    expect(controller.createOn(thursday, globalRect: fabRect), isNull);
  });

  testWidgets("CR9 a create on a day the store has not read reads it and "
      "reports nothing until the read answers, then the first slot no entry "
      "it read shares", (tester) async {
    final source = HeldReads();
    final (_, controller) = await pumpRead(tester, source);
    controller.createOn(may14, globalRect: fabRect);
    await tester.pump();
    expect(creates, isEmpty);
    expect(source.reads(may14), isTrue);
    source.answerAll(<CalendarEntry<String>>[entryOf("early", may14, 0, 30)]);
    await tester.pump();
    expect(creates, <CalendarCreateDetails>[slotOn(may14, 30, 45)]);
  });

  testWidgets("CR10 a create on a shown day under the read in flight waits "
      "for that read", (tester) async {
    final source = HeldReads();
    final controller = await pumpCalendar(
      tester,
      store: cachingOf(source),
      view: CalendarViewKind.month,
    );
    controller.createOn(thursday, globalRect: fabRect);
    await tester.pump();
    expect(creates, isEmpty);
    source.answerAll(<CalendarEntry<String>>[
      entryOf("early", thursday, 0, 30),
    ]);
    await tester.pump();
    expect(creates, <CalendarCreateDetails>[slotOn(thursday, 30, 45)]);
  });

  testWidgets("CR11 a create on a day whose read fails reports the failure "
      "with the day and no create", (tester) async {
    final source = HeldReads();
    final (_, controller) = await pumpRead(tester, source);
    controller.createOn(may14, globalRect: fabRect);
    await tester.pump();
    expect(source.reads(may14), isTrue);
    source.failReadsOf(may14, StateError("offline"));
    await tester.pump();
    expect(readFailed, <DateTime>[may14]);
    expect(creates, isEmpty);
  });

  testWidgets("CR12 a create on a day whose last read failed reads it again "
      "and reports once that read answers", (tester) async {
    final source = HeldReads();
    final (store, controller) = await pumpRead(tester, source);
    store.prefetch(may14, may14);
    source.failReadsOf(may14, StateError("offline"));
    await tester.pump();
    // Setup sanity: the day's read failed.
    expect(store.readFailed(may14), isTrue);
    final reads = source.held.length;
    controller.createOn(may14, globalRect: fabRect);
    await tester.pump();
    expect(readFailed, isEmpty);
    expect(source.held.length, reads + 1);
    source.answerAll(<CalendarEntry<String>>[entryOf("early", may14, 0, 30)]);
    await tester.pump();
    expect(creates, <CalendarCreateDetails>[slotOn(may14, 30, 45)]);
  });

  testWidgets("CR13 the future of a create that waited completes when the "
      "host's does", (tester) async {
    final source = HeldReads();
    final host = Completer<void>();
    final (_, controller) = await pumpRead(
      tester,
      source,
      onCreateRange: (details) {
        creates.add(details);
        return host.future;
      },
    );
    var completed = false;
    controller.createOn(may14, globalRect: fabRect)!.then((_) {
      completed = true;
    });
    await tester.pump();
    expect(completed, isFalse);
    source.answerAll();
    await tester.pump();
    // Setup sanity: the create was reported.
    expect(creates, hasLength(1));
    expect(completed, isFalse);
    host.complete();
    await tester.pump();
    expect(completed, isTrue);
  });

  testWidgets("CR14 a later create ends the wait of an earlier one, which "
      "reports nothing and completes", (tester) async {
    final source = HeldReads();
    final (_, controller) = await pumpRead(tester, source);
    var completed = false;
    controller.createOn(may14, globalRect: fabRect)!.then((_) {
      completed = true;
    });
    controller.createOn(may15, globalRect: fabRect);
    await tester.pump();
    expect(completed, isTrue);
    source.answerAll();
    await tester.pump();
    expect(creates, <CalendarCreateDetails>[slotOn(may15, 0, 15)]);
  });

  testWidgets("CR15 a new zone of the store ends the wait, which reports "
      "nothing and completes", (tester) async {
    ensureZones();
    final source = HeldReads();
    final store = cachingOf(source);
    final controller = await pumpCalendar(
      tester,
      store: store,
      view: CalendarViewKind.month,
    );
    var completed = false;
    controller.createOn(thursday, globalRect: fabRect)!.then((_) {
      completed = true;
    });
    await tester.pump();
    store.zone = tz.getLocation("Etc/GMT-3");
    await tester.pump();
    expect(completed, isTrue);
    source.answerAll();
    await tester.pumpAndSettle();
    // Setup sanity: the day is read on the new clock.
    expect(store.isRead(thursday), isTrue);
    expect(creates, isEmpty);
  });

  testWidgets("CR16 another store ends the wait, which reports nothing and "
      "completes", (tester) async {
    final source = HeldReads();
    final (_, controller) = await pumpRead(tester, source);
    var completed = false;
    controller.createOn(may14, globalRect: fabRect)!.then((_) {
      completed = true;
    });
    await tester.pump();
    final other = storeOf(<CalendarEntry<String>>[]);
    await pumpCalendar(tester, store: other, controller: controller);
    expect(completed, isTrue);
    source.answerAll();
    // A notify of the new store, which has read every day.
    other.hours = CalendarDayHours(8 * 60, 18 * 60);
    await tester.pumpAndSettle();
    expect(creates, isEmpty);
  });

  testWidgets("CR17 another controller ends the wait, which reports nothing "
      "and completes", (tester) async {
    final source = HeldReads();
    final (store, controller) = await pumpRead(tester, source);
    var completed = false;
    controller.createOn(may14, globalRect: fabRect)!.then((_) {
      completed = true;
    });
    await tester.pump();
    await pumpCalendar(tester, store: store, view: CalendarViewKind.month);
    expect(completed, isTrue);
    source.answerAll();
    await tester.pumpAndSettle();
    expect(creates, isEmpty);
  });

  testWidgets("CR18 a calendar leaving the tree ends the wait, which "
      "reports nothing and completes", (tester) async {
    final source = HeldReads();
    final (_, controller) = await pumpRead(tester, source);
    var completed = false;
    controller.createOn(may14, globalRect: fabRect)!.then((_) {
      completed = true;
    });
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(completed, isTrue);
    source.answerAll();
    await tester.pump();
    expect(creates, isEmpty);
  });
}
