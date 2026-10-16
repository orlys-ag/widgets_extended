/// What Month's Fit to screen layout keeps of each week: how many lanes a
/// week holds, which chips it shows, and how many chips each day hides.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_data.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/month_board.dart';

import 'calendar_harness.dart';

/// April 2026, whose weeks start on March 30 and April 6, 13, 20 and 27.
final MonthGrid grid = MonthGrid(2026, 4);

DateTime april(int day) {
  return DateTime(2026, 4, day);
}

/// A task with the id [id] from [day] for [dayCount] days, an hour from
/// [start] o'clock, as the calendar shows it.
ShownItem task(String id, DateTime day, int start, {int dayCount = 1}) {
  final json = <String, Object?>{
    ...taskJson(id, day, start * 60, (start + 1) * 60, dayCount: dayCount),
    "id": id,
  };
  return ShownItem(CalendarItem.fromJson(json), pending: false);
}

/// The index of [day]'s cell in [grid], as the hidden counts are indexed.
int cellIndex(DateTime day) {
  final cell = grid.cellOf(day);
  return cell.row * grid.columnCount + cell.col;
}

/// The item ids of [placements], one per placement.
List<String> idsOf(List<BoardPlacement<MonthChip>> placements) {
  return <String>[for (final placement in placements) placement.item.entry.id];
}

/// The hidden counts [hidden] holds other than zero, by day.
Map<DateTime, int> hiddenDays(List<int> hidden) {
  return <DateTime, int>{
    for (var row = 0; row < grid.weekCount; row++)
      for (var col = 0; col < grid.columnCount; col++)
        if (hidden[row * grid.columnCount + col] != 0)
          grid.dateAt(row, col): hidden[row * grid.columnCount + col],
  };
}

/// A board holding [placements] as the month board holds its chips, whose
/// lanes are the board's own.
BoardController<String, MonthChip> laneBoard(
  TickerProvider vsync,
  List<BoardPlacement<MonthChip>> placements,
) {
  final board = BoardController<String, MonthChip>(
    vsync: vsync,
    rows: BoardAxisConfig(
      axis: UniformAxis(grid.weekCount, 400.0),
      laneExtent: monthLaneExtent,
      lanePadding: monthStripHeight,
    ),
    columns: BoardAxisConfig(axis: UniformAxis(grid.columnCount, 50.0)),
    keyOf: (chip) {
      return chip.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
    laneOrder: compareMonthChips,
  );
  board.setItems(placements);
  return board;
}

/// Whether [placement] covers the cell at [row] and [col].
bool covers(BoardPlacement<MonthChip> placement, int row, int col) {
  final span = placement.span;
  return span.rowStart == row &&
      col >= span.colStart &&
      col < span.colStart + span.colSpan;
}

void main() {
  test("F1 a week holds the lanes that fit below its strip, at least one", () {
    expect(monthLanesThatFit(monthStripHeight + monthLaneExtent), 1);
    expect(
      monthLanesThatFit(monthStripHeight + 2 * monthLaneExtent - 1 / 64),
      1,
    );
    expect(monthLanesThatFit(monthStripHeight + 2 * monthLaneExtent), 2);
    expect(monthLanesThatFit(monthStripHeight + 5 * monthLaneExtent + 17.0), 5);
    expect(monthLanesThatFit(10.0), 1);
  });

  test("F2 a week whose chips fit its lanes shows them all", () {
    final placements = monthPlacementsOf(<ShownItem>[
      task("a", april(22), 8),
      task("b", april(22), 9),
      task("c", april(22), 10),
      task("d", april(20), 8, dayCount: 3),
    ], grid);
    // Sanity: the four chips need four lanes on April 22, so one fewer
    // hides some.
    expect(
      hiddenDays(fitMonthPlacements(placements, grid, 3).hidden),
      isNotEmpty,
    );
    final fit = fitMonthPlacements(placements, grid, 4);
    expect(idsOf(fit.shown), idsOf(placements));
    expect(hiddenDays(fit.hidden), isEmpty);
    expect(fit.hidden, hasLength(grid.weekCount * grid.columnCount));
  });

  test("F3 a day past the last lane hides its chips from the last lane on "
      "and counts them", () {
    final placements = monthPlacementsOf(<ShownItem>[
      for (var hour = 8; hour < 13; hour++) task("t$hour", april(22), hour),
      task("other", april(23), 8),
    ], grid);
    final fit = fitMonthPlacements(placements, grid, 3);
    expect(idsOf(fit.shown), <String>["t8", "t9", "other"]);
    expect(hiddenDays(fit.hidden), <DateTime, int>{april(22): 3});
  });

  test("F4 a chip in the last lane hides on every day it covers when one of "
      "them is past the last lane", () {
    // Lanes, Monday to Thursday: a 0; b 1 to Tuesday, then d; c 2 from
    // Tuesday; e 3 on Wednesday.
    final placements = monthPlacementsOf(<ShownItem>[
      task("a", april(20), 8, dayCount: 5),
      task("b", april(20), 9, dayCount: 2),
      task("c", april(21), 10, dayCount: 3),
      task("d", april(22), 11),
      task("e", april(22), 12),
    ], grid);
    final fit = fitMonthPlacements(placements, grid, 3);
    expect(idsOf(fit.shown), <String>["a", "b", "d"]);
    expect(hiddenDays(fit.hidden), <DateTime, int>{
      april(21): 1,
      april(22): 2,
      april(23): 1,
    });
  });

  testWidgets("F5 every chip shown keeps the board's lane for it, below the "
      "last, and every day hides what it no longer shows", (tester) async {
    final random = math.Random(7);
    final items = <ShownItem>[
      for (var i = 0; i < 70; i++)
        task(
          "i$i",
          addDays(grid.firstDay, random.nextInt(35)),
          8 + random.nextInt(10),
          dayCount: random.nextInt(4) == 0 ? 2 + random.nextInt(5) : 1,
        ),
    ];
    final placements = monthPlacementsOf(items, grid);
    final all = laneBoard(tester, placements);
    for (var lanes = 1; lanes <= 4; lanes++) {
      final fit = fitMonthPlacements(placements, grid, lanes);
      final shown = laneBoard(tester, fit.shown);
      var lastLaneKept = 0;
      for (final placement in fit.shown) {
        final key = placement.item.key;
        expect(shown.laneOf(key), all.laneOf(key), reason: key);
        expect(shown.laneOf(key), lessThan(lanes), reason: key);
        if (shown.laneOf(key) == lanes - 1) {
          lastLaneKept++;
        }
      }
      var hiding = 0;
      for (var row = 0; row < grid.weekCount; row++) {
        for (var col = 0; col < grid.columnCount; col++) {
          final before = placements.where((placement) {
            return covers(placement, row, col);
          }).length;
          final kept = fit.shown.where((placement) {
            return covers(placement, row, col);
          });
          final hidden = fit.hidden[row * grid.columnCount + col];
          expect(hidden, before - kept.length, reason: "$row, $col");
          if (hidden > 0) {
            hiding++;
            for (final placement in kept) {
              expect(
                shown.laneOf(placement.item.key),
                lessThan(lanes - 1),
                reason: "$row, $col",
              );
            }
          }
        }
      }
      // Sanity: some days hide chips and some last lanes keep theirs.
      expect(hiding, greaterThan(0), reason: "$lanes lanes");
      expect(lastLaneKept, greaterThan(0), reason: "$lanes lanes");
      shown.dispose();
    }
    all.dispose();
  });

  test("F6 with one lane a day past it hides all its chips", () {
    final placements = monthPlacementsOf(<ShownItem>[
      task("x", april(9), 8),
      task("y", april(9), 9),
    ], grid);
    final fit = fitMonthPlacements(placements, grid, 1);
    expect(fit.hidden[cellIndex(april(9))], 2);
    expect(idsOf(fit.shown), isEmpty);
  });
}
