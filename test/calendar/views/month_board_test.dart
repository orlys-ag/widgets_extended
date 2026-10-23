/// The month board: what its fit-to-screen layout keeps of each week (how
/// many lanes a week holds, which chips it shows, and how many chips each
/// day hides), the height a week rests at, the days that show cards, the
/// bars an entry splits into, a chip drawn again for a new payload, and
/// when its days are ready while the store shows another range.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_data_source.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/store/caching_calendar_store.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';

typedef ShownItem = CalendarShownEntry<String>;

/// April 2026, whose weeks start on March 30 and April 6, 13, 20 and 27.
final MonthGrid grid = MonthGrid(2026, 4);

/// The Monday of April 21 2026's week.
final DateTime monday = DateTime(2026, 4, 20);

DateTime april(int day) {
  return DateTime(2026, 4, day);
}

/// An entry with the id and title [id] from [start] o'clock on [day] to
/// an hour later on its [dayCount]th day, as the calendar shows it.
ShownItem task(String id, DateTime day, int start, {int dayCount = 1}) {
  return ShownItem(
    CalendarEntry<String>(
      id: id,
      start: DateTime(day.year, day.month, day.day, start),
      end: DateTime(day.year, day.month, day.day + dayCount - 1, start + 1),
      title: id,
      color: const Color(0xFF336699),
      payload: id,
    ),
    pending: false,
  );
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

/// A data source that answers each read within the call, through a
/// [SynchronousFuture], with the entries covering its days, and once
/// [fails] is set fails each read sent.
class ReadSource implements CalendarDataSource<String> {
  ReadSource(this.entries);

  final List<CalendarEntry<String>> entries;

  bool fails = false;

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    if (fails) {
      return Future<List<CalendarEntry<String>>>.error(
        StateError("The read failed."),
      );
    }
    final from = dayNumber(first);
    final to = dayNumber(last);
    return SynchronousFuture<List<CalendarEntry<String>>>(
      <CalendarEntry<String>>[
        for (final entry in entries)
          if (dayNumber(entry.start) <= to &&
              lastDayNumberOf(entry.start, entry.end) >= from)
            entry,
      ],
    );
  }

  @override
  Future<CalendarEntry<String>> create(CalendarEntry<String> draft) {
    throw UnimplementedError();
  }

  @override
  Future<CalendarEntry<String>> replace(CalendarEntry<String> entry) {
    return SynchronousFuture<CalendarEntry<String>>(entry);
  }

  @override
  Future<void> delete(String id) {
    return SynchronousFuture<void>(null);
  }
}

/// A caching store over a [ReadSource] that counts its [isRead] calls.
class CountingStore extends CachingCalendarStore<String> {
  CountingStore(this.source) : super(dataSource: source);

  final ReadSource source;

  int isReadCalls = 0;

  @override
  bool isRead(DateTime day) {
    isReadCalls++;
    return super.isRead(day);
  }
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

  test("F7 a week rests at its share of the height times the scale, "
      "floored to 1/64, and never under the strip and one lane", () {
    expect(fittedWeekExtent(500.0, 5), 100.0);
    expect(fittedWeekExtent(500.0, 5, scale: 1.5), 150.0);
    // 200 / 3 is 66.66..., whose 1/64 floor is 4266 / 64.
    expect(fittedWeekExtent(100.0, 3, scale: 2.0), 4266 / 64);
    expect(
      fittedWeekExtent(100.0, 5, scale: 2.0),
      monthStripHeight + monthLaneExtent,
    );
    expect(
      fittedWeekExtent(double.infinity, 5, scale: 3.0),
      monthStripHeight + monthLaneExtent,
    );
  });

  test("F8 days show cards from 100 px wide in weeks from 136 px tall, "
      "which hold three card lanes", () {
    expect(monthShowsCards(100.0, 136.0), isTrue);
    expect(monthShowsCards(100.0 - 1 / 64, 136.0), isFalse);
    expect(monthShowsCards(100.0, 136.0 - 1 / 64), isFalse);
    expect(monthLanesThatFit(136.0, laneExtent: monthCardExtent), 3);
    expect(monthLanesThatFit(136.0 - 1 / 64, laneExtent: monthCardExtent), 2);
  });

  test("F9 a bar splits at the weeks' first weekday and continues across "
      "it", () {
    final fromSunday = MonthGrid(
      2026,
      4,
      weekdays: WeekdaySet.all.startingOn(6),
    );
    final placements = monthPlacementsOf(<ShownItem>[
      task("x", april(25), 9, dayCount: 2),
    ], fromSunday);
    expect(
      <String>[for (final placement in placements) placement.item.key],
      <String>["x@2026-04-19", "x@2026-04-26"],
    );
    expect(
      <(bool, bool)>[
        for (final placement in placements)
          (placement.item.continuesBefore, placement.item.continuesAfter),
      ],
      <(bool, bool)>[(false, true), (true, false)],
    );
  });

  testWidgets("BM8 a write that changes only an entry's payload runs its "
      "chip builder again, which draws the new payload", (tester) async {
    final day = DateTime(2026, 4, 21);
    final note = CalendarEntry<String>(
      id: "note-1",
      start: DateTime(2026, 4, 21, 10),
      end: DateTime(2026, 4, 21, 11),
      title: "Note",
      color: const Color(0xFF336699),
      payload: "first",
    );
    // The in-memory store applies a write within the call, so the payload
    // changes with no pending state between.
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[note],
    );
    addTearDown(store.dispose);
    final todayNotifier = ValueNotifier<DateTime>(day);
    addTearDown(todayNotifier.dispose);
    final calls = <CalendarShownEntry<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MonthBoard<String>(
          store: store,
          grid: MonthGrid.of(day),
          selectedDay: day,
          today: todayNotifier,
          onSelectDay: (day) {},
          onOpenDay: (day) {},
          onCreateOnDay: null,
          onOpenEntry: (id) {},
          chipBuilder: (context, entry, details) {
            calls.add(entry);
            return Text(entry.entry.payload);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = find.byKey(monthChipKey(monthSegmentKey("note-1", monday)));
    expect(
      find.descendant(of: bar, matching: find.text("first")),
      findsOneWidget,
    );
    final before = calls.length;

    await store.update(note.copyWith(payload: "second"));
    await tester.pumpAndSettle();
    expect(calls.length, before + 1);
    expect(calls.last.pending, isFalse);
    expect(calls.last.entry.payload, "second");
    expect(
      find.descendant(of: bar, matching: find.text("second")),
      findsOneWidget,
    );
  });

  testWidgets("MB1 a month board whose grid the store does not show is "
      "ready once every day of its grid is read, covers a failed read of "
      "another range with the loading state, and reads no day in a "
      "layout", (tester) async {
    final source = ReadSource(<CalendarEntry<String>>[
      CalendarEntry<String>(
        id: "talk",
        start: DateTime(2026, 4, 21, 10),
        end: DateTime(2026, 4, 21, 11),
        title: "talk",
        color: const Color(0xFF336699),
        payload: "talk",
      ),
    ]);
    final store = CountingStore(source);
    addTearDown(store.dispose);
    store.show(grid.firstDay, grid.lastDay);
    expect(store.status, CalendarLoadStatus.ready);
    final todayNotifier = ValueNotifier<DateTime>(april(21));
    addTearDown(todayNotifier.dispose);
    final workweek = MonthGrid(2026, 4, weekdays: WeekdaySet.workweek);
    final june = MonthGrid(2026, 6);
    // The board's grid is not the one the store shows.
    expect(workweek.lastDay, isNot(grid.lastDay));

    Widget board(MonthGrid shown, {double weekScale = 1.0}) {
      return MaterialApp(
        home: MonthBoard<String>(
          store: store,
          grid: shown,
          weekScale: weekScale,
          selectedDay: shownDayNear(
            DateTime(shown.year, shown.month),
            shown.weekdays,
          ),
          today: todayNotifier,
          onSelectDay: (day) {},
          onOpenDay: (day) {},
          onCreateOnDay: null,
          onOpenEntry: (id) {},
          loadingBuilder: (context, state) {
            return const Text("loading");
          },
          failureBuilder: (context, state) {
            return const Text("failed");
          },
        ),
      );
    }

    final chip = find.byKey(monthChipKey(monthSegmentKey("talk", monday)));
    void expectShows({required bool chips, String? cover}) {
      expect(chip, chips ? findsOneWidget : findsNothing);
      expect(
        find.text("loading"),
        cover == "loading" ? findsOneWidget : findsNothing,
      );
      expect(
        find.text("failed"),
        cover == "failed" ? findsOneWidget : findsNothing,
      );
    }

    await tester.pumpWidget(board(workweek));
    await tester.pumpAndSettle();
    expectShows(chips: true);

    source.fails = true;
    final may = MonthGrid(2026, 5);
    store.show(may.firstDay, may.lastDay);
    await tester.pump();
    expect(store.status, CalendarLoadStatus.failed);
    await tester.pumpAndSettle();
    expectShows(chips: true);

    await tester.pumpWidget(board(june));
    await tester.pumpAndSettle();
    expectShows(chips: false, cover: "loading");

    await tester.pumpWidget(board(workweek));
    await tester.pumpAndSettle();
    expectShows(chips: true);
    final rows = tester
        .widget<Board<String, MonthChip<String>>>(
          find.byType(Board<String, MonthChip<String>>),
        )
        .controller
        .rows;
    store.isReadCalls = 0;
    await tester.pumpWidget(board(workweek, weekScale: 1.5));
    final scaled = tester
        .widget<Board<String, MonthChip<String>>>(
          find.byType(Board<String, MonthChip<String>>),
        )
        .controller
        .rows;
    // The new scale laid the weeks out again.
    expect(identical(scaled.axis, rows.axis), isFalse);
    expect(store.isReadCalls, 0);
  });
}
