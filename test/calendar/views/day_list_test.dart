/// The day list: the rows it lays out for a day's entries, its gaps and
/// its banners outside the hours, a card drawn again for a new payload,
/// and a failed row's retry.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_data_source.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/edit_policy.dart';
import 'package:widgets_extended/calendar/presentation/calendar_builders.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';
import 'package:widgets_extended/calendar/store/caching_calendar_store.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';

typedef ShownItem = CalendarShownEntry<String>;

/// 09:00 on April 21 2026.
DateTime nineOClock() {
  return DateTime(2026, 4, 21, 9);
}

/// An entry with the id and title [id] on April 22 from [start] to [end]
/// minutes after midnight, as the calendar shows it.
ShownItem entryAt(String id, int start, int end) {
  return ShownItem(
    CalendarEntry<String>(
      id: id,
      start: DateTime(2026, 4, 22, 0, start),
      end: DateTime(2026, 4, 22, 0, end),
      title: id,
      color: const Color(0xFF336699),
      payload: id,
    ),
    pending: false,
  );
}

/// [dayListRowsOf] of [entries] on April 22 in [hours], in edit mode
/// unless not [editable], each item as its id, each gap as its start and
/// end, and each banner as "before" or "after" and its count.
List<Object> rowsOf(
  List<ShownItem> entries, {
  CalendarDayHours hours = CalendarDayHours.allDay,
  bool editable = true,
}) {
  return <Object>[
    for (final row in dayListRowsOf(
      DateTime(2026, 4, 22),
      entries,
      hours,
      editable: editable,
    ))
      switch (row) {
        DayListEntry(:final entry) => entry.id,
        DayListGap(:final start, :final end) => (start, end),
        DayListHidden(:final count, :final above) => (
          above ? "before" : "after",
          count,
        ),
        _ => throw StateError("$row is not an item, a gap or a banner."),
      },
  ];
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

void main() {
  test("L6 the rows put one gap row for each run of the calendar's hours "
      "that no item covers, before the item that ends it or last", () {
    expect(
      rowsOf(<ShownItem>[
        entryAt("a", 8 * 60, 9 * 60),
        entryAt("b", 10 * 60, 11 * 60),
        entryAt("c", 13 * 60, 14 * 60),
      ]),
      <Object>[
        (0, 8 * 60),
        "a",
        (9 * 60, 10 * 60),
        "b",
        (11 * 60, 13 * 60),
        "c",
        (14 * 60, 24 * 60),
      ],
    );
    // Minutes an item covers have no row, though a later item ends first.
    expect(
      rowsOf(<ShownItem>[
        entryAt("a", 8 * 60, 11 * 60),
        entryAt("b", 9 * 60, 10 * 60),
        entryAt("c", 12 * 60, 13 * 60),
      ]),
      <Object>[
        (0, 8 * 60),
        "a",
        "b",
        (11 * 60, 12 * 60),
        "c",
        (13 * 60, 24 * 60),
      ],
    );
    // A gap starts where an item ends, between whole hours too, and items
    // that touch or start together have none between them.
    expect(
      rowsOf(<ShownItem>[
        entryAt("a", 8 * 60, 9 * 60 + 15),
        entryAt("b", 11 * 60, 12 * 60),
        entryAt("c", 11 * 60, 11 * 60 + 30),
        entryAt("d", 12 * 60, 13 * 60),
      ]),
      <Object>[
        (0, 8 * 60),
        "a",
        (9 * 60 + 15, 11 * 60),
        "b",
        "c",
        "d",
        (13 * 60, 24 * 60),
      ],
    );
    // Only the calendar's hours have gaps, so an item reaching past them
    // makes none past them, and one wholly outside them none at all.
    const office = CalendarDayHours(8 * 60, 18 * 60);
    expect(
      rowsOf(<ShownItem>[
        entryAt("a", 7 * 60, 9 * 60),
        entryAt("b", 17 * 60, 19 * 60),
      ], hours: office),
      <Object>["a", (9 * 60, 17 * 60), "b"],
    );
    expect(
      rowsOf(<ShownItem>[
        entryAt("a", 6 * 60, 7 * 60),
        entryAt("b", 19 * 60, 20 * 60),
      ], hours: office),
      <Object>[("before", 1), (8 * 60, 18 * 60), ("after", 1)],
    );
  });

  test("L18 an item wholly outside the hours has no row: a banner first "
      "counts those before them and one last those after them, in edit "
      "mode and out of it, and in edit mode a day with no item inside the "
      "hours has one gap row across them", () {
    const office = CalendarDayHours(8 * 60, 18 * 60);
    final entries = <ShownItem>[
      entryAt("a", 6 * 60, 7 * 60),
      entryAt("b", 7 * 60, 8 * 60),
      entryAt("c", 7 * 60, 9 * 60),
      entryAt("e", 12 * 60, 13 * 60),
      entryAt("d", 18 * 60, 19 * 60),
    ];
    expect(rowsOf(entries, hours: office, editable: false), <Object>[
      ("before", 2),
      "c",
      "e",
      ("after", 1),
    ]);
    expect(rowsOf(entries, hours: office), <Object>[
      ("before", 2),
      "c",
      (9 * 60, 12 * 60),
      "e",
      (13 * 60, 18 * 60),
      ("after", 1),
    ]);
    expect(rowsOf(const <ShownItem>[], hours: office), <Object>[
      (8 * 60, 18 * 60),
    ]);
    expect(rowsOf(const <ShownItem>[], editable: false), isEmpty);
  });

  testWidgets("BA10 a write that changes only an entry's payload runs its "
      "card builder again, which draws the new payload", (tester) async {
    final day = DateTime(2026, 4, 21);
    final note = CalendarEntry<String>(
      id: "note-1",
      start: DateTime(2026, 4, 21, 10),
      end: DateTime(2026, 4, 21, 11),
      title: "Note",
      color: const Color(0xFF336699),
      payload: "first",
    );
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[note],
    );
    addTearDown(store.dispose);
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: nineOClock(), today: day),
    );
    addTearDown(now.dispose);
    final calls = <CalendarShownEntry<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DayList<String>(
          store: store,
          weekdays: CalendarWeekdaySet.all,
          format: CalendarHourLabelFormat.twentyFourHour,
          hours: CalendarDayHours.allDay,
          editable: false,
          selectedDay: day,
          now: now,
          onTopDay: (day) {},
          onCreateRange: (range) {},
          onEdit: (id) {},
          onDelete: (id) {},
          cardBuilder: (context, entry, details) {
            calls.add(entry);
            return Text(entry.entry.payload);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(entryCardKey("note-1"));
    expect(
      find.descendant(of: card, matching: find.text("first")),
      findsOneWidget,
    );
    final before = calls.length;

    await store.update(note.copyWith(payload: "second"));
    await tester.pumpAndSettle();
    expect(calls.length, greaterThan(before));
    expect(calls.last.pending, isFalse);
    expect(calls.last.entry.payload, "second");
    expect(
      find.descendant(of: card, matching: find.text("second")),
      findsOneWidget,
    );
  });

  testWidgets("BA11 a failed row's retry ends the failed marks of the weeks "
      "of the mounted rows in one read, so their rows show loading at "
      "once", (tester) async {
    final day = DateTime(2026, 4, 21);
    final source = HeldReads();
    final store = CachingCalendarStore<String>(dataSource: source);
    addTearDown(store.dispose);
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: nineOClock(), today: day),
    );
    addTearDown(now.dispose);
    final failures = <CalendarFailureState>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DayList<String>(
          store: store,
          weekdays: CalendarWeekdaySet.all,
          format: CalendarHourLabelFormat.twentyFourHour,
          hours: CalendarDayHours.allDay,
          editable: false,
          selectedDay: day,
          now: now,
          onTopDay: (day) {},
          onCreateRange: (range) {},
          onEdit: (id) {},
          onDelete: (id) {},
          loadingBuilder: (context, state) {
            return const SizedBox(height: 24.0);
          },
          failureBuilder: (context, state) {
            failures.add(state);
            return const SizedBox(height: 48.0);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The list reads the weeks of the rows it builds, and again once the
    // failed rows it builds then mount; each of those reads fails.
    for (var answered = 0; answered < source.held.length; answered++) {
      source.held[answered].answer.completeError(StateError("Offline."));
      await tester.pumpAndSettle();
    }
    final failed = <DateTime>[
      for (
        var d = addDays(day, -14);
        !d.isAfter(addDays(day, 28));
        d = addDays(d, 1)
      )
        if (find.byKey(dayListFailedKey(d)).evaluate().isNotEmpty) d,
    ];
    expect(failed, contains(day));
    final reads = source.held.length;

    failures.last.retry();
    expect(source.held, hasLength(reads + 1));
    expect(
      (source.held.last.first, source.held.last.last),
      (
        CalendarWeekdaySet.all.weekStartOf(failed.first),
        addDays(CalendarWeekdaySet.all.weekStartOf(failed.last), 6),
      ),
    );
    await tester.pump();
    expect(<DateTime>[
      for (final d in failed)
        if (find.byKey(dayListLoadingKey(d)).evaluate().isNotEmpty) d,
    ], failed);
  });

  testWidgets("BA12 a failed row's retry, while the store shows a failed "
      "range of its own, the week before the mounted rows, ends the marks "
      "of both in one read, so the status and every failed row show "
      "loading", (tester) async {
    final day = DateTime(2026, 5, 5);
    final weekStart = CalendarWeekdaySet.all.weekStartOf(day);
    final shownFirst = addDays(weekStart, -7);
    final shownLast = addDays(weekStart, -1);
    final source = HeldReads();
    final store = CachingCalendarStore<String>(dataSource: source);
    addTearDown(store.dispose);
    store.show(shownFirst, shownLast);
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: DateTime(2026, 5, 5, 9), today: day),
    );
    addTearDown(now.dispose);
    final failures = <CalendarFailureState>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DayList<String>(
          store: store,
          weekdays: CalendarWeekdaySet.all,
          format: CalendarHourLabelFormat.twentyFourHour,
          hours: CalendarDayHours.allDay,
          editable: false,
          selectedDay: day,
          now: now,
          onTopDay: (day) {},
          onCreateRange: (range) {},
          onEdit: (id) {},
          onDelete: (id) {},
          loadingBuilder: (context, state) {
            return const SizedBox(height: 24.0);
          },
          failureBuilder: (context, state) {
            failures.add(state);
            return const SizedBox(height: 48.0);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var answered = 0; answered < source.held.length; answered++) {
      source.held[answered].answer.completeError(StateError("Offline."));
      await tester.pumpAndSettle();
    }
    // Setup sanity: the shown range failed, and the list shows failed rows
    // of days after it.
    expect(store.status, CalendarLoadStatus.failed);
    final failed = <DateTime>[
      for (
        var d = addDays(day, -14);
        !d.isAfter(addDays(day, 28));
        d = addDays(d, 1)
      )
        if (find.byKey(dayListFailedKey(d)).evaluate().isNotEmpty) d,
    ];
    expect(failed, contains(day));
    final reads = source.held.length;

    failures.last.retry();
    expect(store.status, CalendarLoadStatus.loading);
    expect(source.held, hasLength(reads + 1));
    expect(
      (source.held.last.first, source.held.last.last),
      (shownFirst, addDays(CalendarWeekdaySet.all.weekStartOf(failed.last), 6)),
    );
    await tester.pump();
    expect(<DateTime>[
      for (final d in failed)
        if (find.byKey(dayListLoadingKey(d)).evaluate().isNotEmpty) d,
    ], failed);
  });
}
