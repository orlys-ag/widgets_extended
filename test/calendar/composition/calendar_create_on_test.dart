/// The controller's create on a day, [CalendarController.createOn]: the
/// slot it reports, the start after the current time on today, a refusal,
/// and what it leaves alone: edit mode, the selection and an unbound
/// controller.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:widgets_extended/calendar/composition/calendar_header.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/views/create_details.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/policy/history_lock_policy.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime thursday = DateTime(2026, 4, 23);
final DateTime friday = DateTime(2026, 4, 24);

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

  setUp(() {
    creates = <CalendarCreateDetails>[];
    refused = <DateTime>[];
  });

  Future<CalendarController> pumpCalendar(
    WidgetTester tester, {
    required MemoryCalendarStore<String> store,
    CalendarViewKind view = CalendarViewKind.week,
    bool editable = true,
    CalendarEditPolicy<String>? policy,
    bool reportsCreates = true,
    Future<void> Function(CalendarCreateDetails details)? onCreateRange,
  }) async {
    final controller = CalendarController(view: view, selectedDay: thursday);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: CalendarView<String>(
          store: store,
          controller: controller,
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
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
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
}
