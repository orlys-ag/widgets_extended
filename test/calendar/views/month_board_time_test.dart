/// The month board on start and end: an entry covering more than one day,
/// timed or all-day, as a bar across its days and a one-day timed entry as
/// a chip, the hours split per piece, and the local zone's DST days shown
/// once with their entries.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/edit_policy.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';

import '../dst_days.dart';

typedef Shown = CalendarShownEntry<String>;

/// April 2026, whose weeks start on March 30 and April 6, 13, 20 and 27.
final MonthGrid april = MonthGrid(2026, 4);

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);
final DateTime thursday = DateTime(2026, 4, 23);

/// [day] at [hour] and [minute] by the wall clock.
DateTime at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

CalendarEntry<String> entryOf(String id, DateTime start, DateTime end) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

Shown shownOf(String id, DateTime start, DateTime end) {
  return Shown(entryOf(id, start, end), pending: false);
}

/// The placements of [shown] on [grid], by id: each one's week row, first
/// column and column span.
Map<String, List<(int, int, int)>> spansOf(List<Shown> shown, MonthGrid grid) {
  final spans = <String, List<(int, int, int)>>{};
  for (final placement in monthPlacementsOf(shown, grid)) {
    final span = placement.span;
    (spans[placement.item.entry.id] ??= <(int, int, int)>[]).add((
      span.rowStart,
      span.colStart,
      span.colSpan,
    ));
  }
  return spans;
}

/// The counts of [counts] other than zero on [grid], by day.
Map<DateTime, int> countsByDay(Int32List counts, MonthGrid grid) {
  return <DateTime, int>{
    for (var row = 0; row < grid.weekCount; row++)
      for (var col = 0; col < grid.columnCount; col++)
        if (counts[row * grid.columnCount + col] != 0)
          grid.dateAt(row, col): counts[row * grid.columnCount + col],
  };
}

/// The month board over [grid] with [entries] in [hours].
Future<void> pumpMonth(
  WidgetTester tester,
  MonthGrid grid,
  DateTime selectedDay,
  List<CalendarEntry<String>> entries, {
  CalendarDayHours hours = CalendarDayHours.allDay,
}) async {
  final store = MemoryCalendarStore<String>(entries: entries);
  addTearDown(store.dispose);
  final now = ValueNotifier<CalendarNow>(
    CalendarNow(time: selectedDay, today: selectedDay),
  );
  addTearDown(now.dispose);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(700.0, 900.0);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MonthBoard<String>(
        store: store,
        grid: grid,
        hours: hours,
        selectedDay: selectedDay,
        now: now,
        onSelectDay: (day) {},
        onOpenDay: (day) {},
        onCreateOnDay: null,
        onOpenEntry: (id) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Whether the board draws [id]'s chip in its week of [day] inside the
/// cell of [day].
bool chipInCell(WidgetTester tester, MonthGrid grid, String id, DateTime day) {
  final weekStart = grid.dateAt(grid.cellOf(day).row, 0);
  final chip = find.byKey(monthChipKey(monthSegmentKey(id, weekStart)));
  if (chip.evaluate().length != 1) {
    return false;
  }
  final rect = tester.getRect(chip);
  final cell = tester.getRect(find.byKey(monthDayKey(day)));
  return cell.contains(rect.centerLeft.translate(1.0, 0.0)) &&
      cell.contains(rect.centerRight.translate(-1.0, 0.0));
}

void main() {
  test("MT1 a timed and an all-day entry over three days are bars across "
      "them, an overnight entry one across its two days, and a one-day "
      "timed entry a chip", () {
    final week = april.cellOf(monday).row;
    expect(
      spansOf(<Shown>[
        shownOf("timed", at(monday, 10), at(wednesday, 12)),
        shownOf("all-day", monday, thursday),
        shownOf("night", at(monday, 22), at(tuesday, 2)),
        shownOf("to-midnight", at(monday, 22), wednesday),
        shownOf("chip", at(tuesday, 9), at(tuesday, 10)),
      ], april),
      <String, List<(int, int, int)>>{
        "timed": <(int, int, int)>[(week, 0, 3)],
        "all-day": <(int, int, int)>[(week, 0, 3)],
        "night": <(int, int, int)>[(week, 0, 2)],
        "to-midnight": <(int, int, int)>[(week, 0, 2)],
        "chip": <(int, int, int)>[(week, 1, 1)],
      },
    );
  });

  testWidgets("MT1 a bar across three days is as wide as the three days' "
      "cells on the board", (tester) async {
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entryOf("timed", at(monday, 10), at(wednesday, 12)),
        entryOf("chip", at(thursday, 9), at(thursday, 10)),
      ],
    );
    addTearDown(store.dispose);
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: tuesday, today: tuesday),
    );
    addTearDown(now.dispose);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(700.0, 900.0);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthBoard<String>(
          store: store,
          grid: april,
          selectedDay: tuesday,
          now: now,
          onSelectDay: (day) {},
          onOpenDay: (day) {},
          onCreateOnDay: null,
          onOpenEntry: (id) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = tester.getRect(
      find.byKey(monthChipKey(monthSegmentKey("timed", monday))),
    );
    final chip = tester.getRect(
      find.byKey(monthChipKey(monthSegmentKey("chip", monday))),
    );
    final mondayCell = tester.getRect(find.byKey(monthDayKey(monday)));
    final wednesdayCell = tester.getRect(find.byKey(monthDayKey(wednesday)));
    final thursdayCell = tester.getRect(find.byKey(monthDayKey(thursday)));
    // Each starts in its first day's cell and ends in its last day's.
    expect(mondayCell.contains(bar.centerLeft.translate(1.0, 0.0)), isTrue);
    expect(
      wednesdayCell.contains(bar.centerRight.translate(-1.0, 0.0)),
      isTrue,
    );
    expect(thursdayCell.contains(chip.centerLeft.translate(1.0, 0.0)), isTrue);
    expect(
      thursdayCell.contains(chip.centerRight.translate(-1.0, 0.0)),
      isTrue,
    );
  });

  test("MT3 under 08:00-18:00, Monday 22:00 to Tuesday 02:00 has no bar, and "
      "counts later on Monday and earlier on Tuesday", () {
    const office = CalendarDayHours(8 * 60, 18 * 60);
    final split = splitMonthHours(
      <Shown>[
        shownOf("night", at(monday, 22), at(tuesday, 2)),
        shownOf("inside", at(monday, 22), at(tuesday, 9)),
        shownOf("all-day", monday, wednesday),
      ],
      april,
      office,
    );
    expect(
      <String>[for (final entry in split.inside) entry.id],
      <String>["inside", "all-day"],
    );
    expect(countsByDay(split.later, april), <DateTime, int>{monday: 1});
    expect(countsByDay(split.earlier, april), <DateTime, int>{tuesday: 1});
  });

  test("MT6 under 08:00-18:00, an entry from a year before the grid to its "
      "first day at 07:00 counts earlier on that day, and one from its last "
      "day at 19:00 to a year after counts later on that day", () {
    const office = CalendarDayHours(8 * 60, 18 * 60);
    final gridFirst = april.dateAt(0, 0);
    final gridLast = april.dateAt(april.weekCount - 1, april.columnCount - 1);
    final split = splitMonthHours(
      <Shown>[
        shownOf("into", DateTime(2025, 3, 1, 20), at(gridFirst, 7)),
        shownOf("out of", at(gridLast, 19), DateTime(2027, 6, 1, 7)),
      ],
      april,
      office,
    );
    expect(countsByDay(split.earlier, april), <DateTime, int>{gridFirst: 1});
    expect(countsByDay(split.later, april), <DateTime, int>{gridLast: 1});
  });

  group("on the 23-hour day", skip: shortDaySkip, () {
    test("MT2 the day shows once with its entries", () {
      final day = shortDayStart;
      final grid = MonthGrid.of(day);
      final cell = grid.cellOf(day);
      final spans = spansOf(<Shown>[
        shownOf("all-day", day, addDays(day, 1)),
        shownOf("early", at(day, 1, 30), at(day, 3, 30)),
      ], grid);
      expect(spans, <String, List<(int, int, int)>>{
        "all-day": <(int, int, int)>[(cell.row, cell.col, 1)],
        "early": <(int, int, int)>[(cell.row, cell.col, 1)],
      });
      // The grid has the day in one cell.
      var cells = 0;
      for (var row = 0; row < grid.weekCount; row++) {
        for (var col = 0; col < grid.columnCount; col++) {
          if (grid.dateAt(row, col) == day) {
            cells++;
          }
        }
      }
      expect(cells, 1);
    });

    testWidgets("MT4 the board draws the day's entries in its cell, and an "
        "entry at 00:30 the next day in that day's cell", (tester) async {
      final day = shortDayStart;
      final next = DateTime(day.year, day.month, day.day + 1);
      final grid = MonthGrid.of(day);
      await pumpMonth(tester, grid, day, <CalendarEntry<String>>[
        entryOf("all-day", day, next),
        entryOf("early", at(day, 1, 30), at(day, 3, 30)),
        entryOf("next", at(next, 0, 30), at(next, 1)),
      ]);
      expect(
        <String, bool>{
          "all-day": chipInCell(tester, grid, "all-day", day),
          "early": chipInCell(tester, grid, "early", day),
          "next": chipInCell(tester, grid, "next", next),
        },
        <String, bool>{"all-day": true, "early": true, "next": true},
      );
    });
  });

  group("on the 25-hour day", skip: longDaySkip, () {
    test("MT2 the day shows once with its entries", () {
      final day = longDayStart;
      final grid = MonthGrid.of(day);
      final cell = grid.cellOf(day);
      final spans = spansOf(<Shown>[
        shownOf("all-day", day, addDays(day, 1)),
        shownOf(
          "repeated",
          secondHalfPastOne,
          secondHalfPastOne.add(const Duration(minutes: 30)),
        ),
      ], grid);
      expect(spans, <String, List<(int, int, int)>>{
        "all-day": <(int, int, int)>[(cell.row, cell.col, 1)],
        "repeated": <(int, int, int)>[(cell.row, cell.col, 1)],
      });
    });

    testWidgets("MT4 the board draws the day's entries in its cell, before "
        "and after the repeated hour", (tester) async {
      final day = longDayStart;
      final grid = MonthGrid.of(day);
      await pumpMonth(tester, grid, day, <CalendarEntry<String>>[
        entryOf("all-day", day, DateTime(day.year, day.month, day.day + 1)),
        entryOf("early", at(day, 0, 30), at(day, 1)),
        entryOf(
          "repeated",
          secondHalfPastOne,
          secondHalfPastOne.add(const Duration(minutes: 30)),
        ),
      ]);
      expect(
        <String, bool>{
          "all-day": chipInCell(tester, grid, "all-day", day),
          "early": chipInCell(tester, grid, "early", day),
          "repeated": chipInCell(tester, grid, "repeated", day),
        },
        <String, bool>{"all-day": true, "early": true, "repeated": true},
      );
    });

    testWidgets("MT5 under hours from 02:30, 00:30 to the second 02:30 and "
        "the first 01:30 to the second 01:15 count as earlier", (tester) async {
      final day = longDayStart;
      final grid = MonthGrid.of(day);
      await pumpMonth(tester, grid, day, <CalendarEntry<String>>[
        // 180 minutes, over the repeated hour.
        entryOf("spans", at(day, 0, 30), at(day, 2, 30)),
        // 45 minutes, whose end's wall time is before its start's.
        entryOf(
          "folds",
          day.add(const Duration(minutes: 90)),
          secondHalfPastOne.subtract(const Duration(minutes: 15)),
        ),
      ], hours: const CalendarDayHours(150, minutesPerDay));
      expect(
        find.descendant(
          of: find.byKey(monthEarlierKey(day)),
          matching: find.text("+2 earlier"),
        ),
        findsOneWidget,
      );
    });
  });
}
