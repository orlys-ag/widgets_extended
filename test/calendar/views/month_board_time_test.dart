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
Map<String, List<(int, int, int)>> spansOf(
  List<Shown> shown,
  MonthGrid grid,
) {
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
    final today = ValueNotifier<DateTime>(tuesday);
    addTearDown(today.dispose);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(700.0, 900.0);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthBoard<String>(
          store: store,
          grid: april,
          selectedDay: tuesday,
          today: today,
          onSelectDay: (day) {},
          onOpenDay: (day) {},
          onCreateOnDay: null,
          onOpenItem: (id) {},
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
    const office = DayHours(8 * 60, 18 * 60);
    final split = splitMonthHours(
      <Shown>[
        shownOf("night", at(monday, 22), at(tuesday, 2)),
        shownOf("inside", at(monday, 22), at(tuesday, 9)),
        shownOf("all-day", monday, wednesday),
      ],
      april,
      office,
    );
    expect(<String>[for (final entry in split.inside) entry.id], <String>[
      "inside",
      "all-day",
    ]);
    expect(countsByDay(split.later, april), <DateTime, int>{monday: 1});
    expect(countsByDay(split.earlier, april), <DateTime, int>{tuesday: 1});
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
  });
}
