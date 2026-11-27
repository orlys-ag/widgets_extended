/// The month board: what its fit-to-screen layout keeps of each week (how
/// many lanes a week holds, which chips it shows, and how many chips each
/// day hides), the height a week rests at, the days that show cards, the
/// bars an entry splits into, a chip drawn again for a new payload, the
/// hour format its chips are handed and heard in, when its days are ready
/// while the store shows another range, and its today, create mark and
/// cover over a zoned store.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_data_source.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/calendar/presentation/calendar_builders.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/scheduling/store/caching_calendar_store.dart';
import 'package:widgets_extended/scheduling/store/calendar_store.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart'
    show weekdayHeaderHeight;
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/pinch_zoom.dart'
    show minDayWidthHigh, minDayWidthLow;

import '../../scheduling/store/zone_support.dart';
import '../../scheduling/zones.dart';
import '../recording_errors.dart';

typedef ShownItem = CalendarShownEntry<String>;

/// April 2026, whose weeks start on March 30 and April 6, 13, 20 and 27.
final CalendarMonthGrid grid = CalendarMonthGrid(2026, 4);

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
    final from = CalendarDates.dayNumber(first);
    final to = CalendarDates.dayNumber(last);
    return SynchronousFuture<List<CalendarEntry<String>>>(
      <CalendarEntry<String>>[
        for (final entry in entries)
          if (CalendarDates.dayNumber(entry.start) <= to &&
              CalendarDates.lastDayNumberOf(entry.start, entry.end) >= from)
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

/// A caching store over a [ReadSource] that counts the queries of the
/// load state of a range it answers, [statusOf] and [loadErrorOf].
final class CountingStore extends CachingCalendarStore<String> {
  CountingStore(this.source) : super(dataSource: source);

  final ReadSource source;

  int loadQueries = 0;

  @override
  CalendarLoadStatus statusOf(DateTime first, DateTime last) {
    loadQueries++;
    return super.statusOf(first, last);
  }

  @override
  Object? loadErrorOf(DateTime first, DateTime last) {
    loadQueries++;
    return super.loadErrorOf(first, last);
  }
}

/// A data source whose reads never answer.
class SilentSource implements CalendarDataSource<String> {
  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    return Completer<List<CalendarEntry<String>>>().future;
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

/// The decoration of Month's create mark under the theme above [view]: the
/// theme's primary tint, edged in its primary colour.
BoxDecoration createMarkIn(WidgetTester tester, Finder view) {
  final theme = CalendarTheme.of(tester.element(view));
  return BoxDecoration(
    color: theme.primaryTint,
    border: Border.all(color: theme.primary, width: 2.0),
  );
}

/// The create marks, boxes drawing [mark], under [of].
Finder createMarksUnder(Finder of, BoxDecoration mark) {
  return find.descendant(
    of: of,
    matching: find.byWidgetPredicate((widget) {
      return widget is DecoratedBox && widget.decoration == mark;
    }),
  );
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
          CalendarDates.addDays(grid.firstDay, random.nextInt(35)),
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
    final fromSunday = CalendarMonthGrid(
      2026,
      4,
      weekdays: CalendarWeekdaySet.all.startingOn(6),
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
    final now = ValueNotifier<CalendarNow>(CalendarNow(time: day, today: day));
    addTearDown(now.dispose);
    final calls = <CalendarShownEntry<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MonthBoard<String>(
          store: store,
          grid: CalendarMonthGrid.of(day),
          selectedDay: day,
          now: now,
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

  testWidgets("MB4 a long press on a day asks for the long-press feedback "
      "once and creates on that day", (tester) async {
    final vibrations = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == "HapticFeedback.vibrate") {
        vibrations.add(call);
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final store = MemoryCalendarStore<String>();
    addTearDown(store.dispose);
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: DateTime(2026, 4, 21, 9), today: april(21)),
    );
    addTearDown(now.dispose);
    final pressed = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MonthBoard<String>(
          store: store,
          grid: grid,
          selectedDay: april(20),
          now: now,
          onSelectDay: (day) {},
          onOpenDay: (day) {},
          onCreateOnDay: (day, globalRect) {
            pressed.add(day);
            return (
              start: DateTime(2026, 4, 21, 9),
              done: Future<void>.value(),
            );
          },
          onOpenEntry: (id) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(vibrations, isEmpty);
    await tester.longPress(find.byKey(monthStripKey(april(21))));
    await tester.pumpAndSettle();
    expect(pressed, <DateTime>[april(21)]);
    expect(vibrations, hasLength(1));
  });

  testWidgets("MB1 a month board whose grid the store does not show is "
      "ready once every day of its grid is read, which a failed read of "
      "another range leaves so, shows the failure state once its own read "
      "fails, and asks the store nothing in a layout", (tester) async {
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
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: april(21), today: april(21)),
    );
    addTearDown(now.dispose);
    final workweek = CalendarMonthGrid(
      2026,
      4,
      weekdays: CalendarWeekdaySet.workweek,
    );
    final june = CalendarMonthGrid(2026, 6);
    // The board's grid is not the one the store shows.
    expect(workweek.lastDay, isNot(grid.lastDay));

    Widget board(CalendarMonthGrid shown, {double weekScale = 1.0}) {
      return MaterialApp(
        home: MonthBoard<String>(
          store: store,
          grid: shown,
          weekScale: weekScale,
          selectedDay: CalendarDates.shownDayNear(
            DateTime(shown.year, shown.month),
            shown.weekdays,
          ),
          now: now,
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
    final may = CalendarMonthGrid(2026, 5);
    store.show(may.firstDay, may.lastDay);
    await tester.pump();
    expect(store.status, CalendarLoadStatus.failed);
    await tester.pumpAndSettle();
    expectShows(chips: true);

    // June's own read, which the board asks for after the frame, fails.
    await tester.pumpWidget(board(june));
    await tester.pumpAndSettle();
    expectShows(chips: false, cover: "failed");

    await tester.pumpWidget(board(workweek));
    await tester.pumpAndSettle();
    expectShows(chips: true);
    final rows = tester
        .widget<Board<String, MonthChip<String>>>(
          find.byType(Board<String, MonthChip<String>>),
        )
        .controller
        .rows;
    store.loadQueries = 0;
    await tester.pumpWidget(board(workweek, weekScale: 1.5));
    final scaled = tester
        .widget<Board<String, MonthChip<String>>>(
          find.byType(Board<String, MonthChip<String>>),
        )
        .controller
        .rows;
    // The new scale laid the weeks out again.
    expect(identical(scaled.axis, rows.axis), isFalse);
    expect(store.loadQueries, 0);
  });

  testWidgets("MB10 a month board built with no layout lays out as "
      "fitScreen", (tester) async {
    tester.view.physicalSize = const Size(400.0, 600.0);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        for (var hour = 8; hour < 20; hour++)
          CalendarEntry<String>(
            id: "task$hour",
            start: DateTime(2026, 4, 21, hour),
            end: DateTime(2026, 4, 21, hour + 1),
            title: "task$hour",
            color: const Color(0xFF336699),
            payload: "task$hour",
          ),
      ],
    );
    addTearDown(store.dispose);
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: DateTime(2026, 4, 21, 9), today: april(21)),
    );
    addTearDown(now.dispose);

    /// The height of the 21st's cell on a board built with [layout], or
    /// with none where it is null.
    Future<double> heightUnder(CalendarMonthLayout? layout) async {
      final key = ValueKey<Object?>(layout);
      await tester.pumpWidget(
        MaterialApp(
          home: layout == null
              ? MonthBoard<String>(
                  key: key,
                  store: store,
                  grid: grid,
                  selectedDay: april(20),
                  now: now,
                  onSelectDay: (day) {},
                  onOpenDay: (day) {},
                  onCreateOnDay: null,
                  onOpenEntry: (id) {},
                )
              : MonthBoard<String>(
                  key: key,
                  store: store,
                  grid: grid,
                  layout: layout,
                  selectedDay: april(20),
                  now: now,
                  onSelectDay: (day) {},
                  onOpenDay: (day) {},
                  onCreateOnDay: null,
                  onOpenEntry: (id) {},
                ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getRect(find.byKey(monthDayKey(april(21)))).height;
    }

    final byDefault = await heightUnder(null);
    final fitted = await heightUnder(CalendarMonthLayout.fitScreen);
    final grown = await heightUnder(CalendarMonthLayout.showAll);
    // Setup sanity: the two layouts give the 21st's week other heights.
    expect(grown, isNot(fitted));
    expect(byDefault, fitted);
  }, skip: true);

  testWidgets("MB2 the clock alone, with no build from above, builds no day "
      "cell again at a new minute of the same today, and moves the today "
      "mark to the day a new today marks", (tester) async {
    final store = MemoryCalendarStore<String>();
    addTearDown(store.dispose);
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: DateTime(2026, 4, 21, 9), today: april(21)),
    );
    addTearDown(now.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthBoard<String>(
          store: store,
          grid: grid,
          selectedDay: april(21),
          now: now,
          onSelectDay: (day) {},
          onOpenDay: (day) {},
          onCreateOnDay: null,
          onOpenEntry: (id) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    /// The semantics [day]'s cell builds, again at each change it follows.
    Semantics cellOf(DateTime day) {
      return tester.widget<Semantics>(
        find
            .descendant(
              of: find.byKey(monthDayKey(day)),
              matching: find.byType(Semantics),
            )
            .first,
      );
    }

    bool marked(DateTime day) {
      return cellOf(day).properties.label!.split(", ").contains("today");
    }

    // Setup sanity: April 21 is marked today, and April 22 is not.
    expect(marked(april(21)), isTrue);
    expect(marked(april(22)), isFalse);
    final built = cellOf(april(21));

    now.value = CalendarNow(
      time: DateTime(2026, 4, 21, 9, 1),
      today: april(21),
    );
    await tester.pump();
    expect(identical(cellOf(april(21)), built), isTrue);

    now.value = CalendarNow(
      time: DateTime(2026, 4, 22, 0, 0, 30),
      today: april(22),
    );
    await tester.pump();
    expect(marked(april(22)), isTrue);
    expect(marked(april(21)), isFalse);
  });

  testWidgets("HF4 a month board hands its chips its hour format and names "
      "their times in it to a screen reader, and builds them again for a "
      "new one", (tester) async {
    final semantics = tester.ensureSemantics();
    final day = DateTime(2026, 4, 21);
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        CalendarEntry<String>(
          id: "note-1",
          start: DateTime(2026, 4, 21, 10),
          end: DateTime(2026, 4, 21, 11),
          title: "Note",
          color: const Color(0xFF336699),
          payload: "note",
        ),
      ],
    );
    addTearDown(store.dispose);
    final now = ValueNotifier<CalendarNow>(CalendarNow(time: day, today: day));
    addTearDown(now.dispose);
    final formats = <CalendarHourLabelFormat>[];
    // The same builder in both builds, so only the format changes.
    Widget recordChip(
      BuildContext context,
      ShownItem entry,
      CalendarChipDetails details,
    ) {
      formats.add(details.hourLabelFormat);
      return Text(entry.entry.title);
    }

    Widget board(CalendarHourLabelFormat format) {
      return MaterialApp(
        home: MonthBoard<String>(
          store: store,
          grid: CalendarMonthGrid.of(day),
          selectedDay: day,
          now: now,
          onSelectDay: (day) {},
          onOpenDay: (day) {},
          onCreateOnDay: null,
          onOpenEntry: (id) {},
          hourLabelFormat: format,
          chipBuilder: recordChip,
        ),
      );
    }

    await tester.pumpWidget(board(CalendarHourLabelFormat.twelveHour));
    await tester.pumpAndSettle();
    expect(formats.toSet(), <CalendarHourLabelFormat>{
      CalendarHourLabelFormat.twelveHour,
    });
    expect(
      find.bySemanticsLabel("Note, Tuesday, April 21, 10 AM to 11 AM"),
      findsOneWidget,
    );

    formats.clear();
    await tester.pumpWidget(board(CalendarHourLabelFormat.twentyFourHour));
    await tester.pumpAndSettle();
    expect(formats.toSet(), <CalendarHourLabelFormat>{
      CalendarHourLabelFormat.twentyFourHour,
    });
    expect(
      find.bySemanticsLabel("Note, Tuesday, April 21, 10:00 to 11:00"),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets("MB3 a month board taken out of the tree while two fingers "
      "pinch it takes no more of their events: their lift and their cancel "
      "report no error", (tester) async {
    for (final cancel in <bool>[false, true]) {
      final reason = cancel ? "cancel" : "lift";
      final store = MemoryCalendarStore<String>();
      addTearDown(store.dispose);
      final now = ValueNotifier<CalendarNow>(
        CalendarNow(time: DateTime(2026, 4, 21, 9), today: april(21)),
      );
      addTearDown(now.dispose);
      final zooms = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MonthBoard<String>(
            store: store,
            grid: grid,
            selectedDay: april(21),
            now: now,
            onSelectDay: (day) {},
            onOpenDay: (day) {},
            onCreateOnDay: null,
            onOpenEntry: (id) {},
            onZoom: (weekScale, minDayWidth) {
              zooms.add(weekScale);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final focal = tester.getCenter(find.byKey(monthDayKey(april(15))));
      final first = await tester.startGesture(focal - const Offset(0.0, 30.0));
      final second = await tester.startGesture(focal + const Offset(0.0, 30.0));
      for (var i = 0; i < 3; i++) {
        await first.moveBy(const Offset(0.0, -6.0));
        await second.moveBy(const Offset(0.0, 6.0));
        await tester.pump();
      }
      // Setup sanity: the pinch zooms.
      expect(zooms, isNotEmpty, reason: reason);

      await tester.pumpWidget(const SizedBox());
      await recordingErrors((errors) async {
        if (cancel) {
          await first.cancel();
          await second.cancel();
        } else {
          await first.up();
          await second.up();
        }
        await tester.pump();
        expect(errors, isEmpty, reason: reason);
      });
    }
  });
  testWidgets("MB5 under right-to-left each weekday letter sits over the "
      "column of its weekday, whether the days share the width or the board "
      "scrolls across, before and after a scroll", (tester) async {
    final store = MemoryCalendarStore<String>();
    addTearDown(store.dispose);
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: DateTime(2026, 4, 21, 9), today: april(21)),
    );
    addTearDown(now.dispose);
    // Column 0 is Monday, and April 20 2026 is a Monday.
    DateTime dayOfColumn(int column) {
      return april(20 + column);
    }

    final letters = find.descendant(
      of: find.byKey(const ValueKey<String>("weekday-header")),
      matching: find.byType(Text),
    );

    /// The columns whose cell the board built, after checking that each
    /// letter's centre lies over its weekday's cell.
    int expectLettersOverColumns(String reason) {
      final columns = grid.weekdays.columns.toList();
      expect(letters, findsNWidgets(columns.length), reason: reason);
      var compared = 0;
      for (var i = 0; i < columns.length; i++) {
        final cell = find.byKey(monthDayKey(dayOfColumn(columns[i])));
        if (cell.evaluate().isEmpty) {
          continue;
        }
        compared++;
        expect(
          tester.getCenter(letters.at(i)).dx,
          moreOrLessEquals(tester.getCenter(cell).dx, epsilon: 0.5),
          reason: "$reason: column ${columns[i]}",
        );
      }
      return compared;
    }

    for (final minDayWidth in <double>[minDayWidthLow, minDayWidthHigh]) {
      final reason = "minDayWidth $minDayWidth";
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MonthBoard<String>(
              store: store,
              grid: grid,
              selectedDay: april(20),
              now: now,
              minDayWidth: minDayWidth,
              onSelectDay: (day) {},
              onOpenDay: (day) {},
              onCreateOnDay: null,
              onOpenEntry: (id) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrolls =
          minDayWidth * 7 >
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      // Setup sanity: the low width shares the view, the high one does not.
      expect(scrolls, minDayWidth == minDayWidthHigh, reason: reason);
      final shown = expectLettersOverColumns(reason);
      // The letters keep the ambient direction as text.
      expect(
        tester.renderObject<RenderParagraph>(letters.first).textDirection,
        TextDirection.rtl,
        reason: reason,
      );
      // Setup sanity: the shared width builds every column.
      if (!scrolls) {
        expect(shown, 7, reason: reason);
        continue;
      }
      final monday = tester.getCenter(find.byKey(monthDayKey(april(20))));
      await tester.drag(
        find.byKey(monthDayKey(april(21))),
        const Offset(-300.0, 0.0),
      );
      await tester.pumpAndSettle();
      // Setup sanity: the drag scrolls the board across.
      expect(
        tester.getCenter(find.byKey(monthDayKey(april(20)))).dx,
        lessThan(monday.dx - 100.0),
        reason: reason,
      );
      expectLettersOverColumns("$reason, scrolled");
    }
  });

  testWidgets("MB6 the arrow keys step to the shown day before or after on "
      "the screen and to the day a week before or after, past a row's end "
      "and into the month before or after, and reveal the day", (tester) async {
    final store = MemoryCalendarStore<String>();
    addTearDown(store.dispose);
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: DateTime(2026, 6, 1, 9), today: DateTime(2026, 6, 1)),
    );
    addTearDown(now.dispose);
    DateTime june(int day) {
      return DateTime(2026, 6, day);
    }

    final reported = <DateTime>[];
    var selected = june(1);
    var shows = 0;

    /// Shows [day]'s month as its owner would, moving to the month of each
    /// day a key reports unless [takes] is false, and focuses the board
    /// with a tap on [day].
    Future<void> show(
      DateTime day, {
      CalendarWeekdaySet weekdays = CalendarWeekdaySet.all,
      double minDayWidth = minDayWidthLow,
      TextDirection direction = TextDirection.ltr,
      bool takes = true,
    }) async {
      selected = day;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            // A new board each time, scrolled to [day].
            key: ValueKey<int>(shows++),
            textDirection: direction,
            child: StatefulBuilder(
              builder: (context, setState) {
                return MonthBoard<String>(
                  store: store,
                  grid: CalendarMonthGrid.of(selected, weekdays: weekdays),
                  selectedDay: selected,
                  now: now,
                  minDayWidth: minDayWidth,
                  onSelectDay: (day) {
                    reported.add(day);
                    if (takes) {
                      setState(() {
                        selected = day;
                      });
                    }
                  },
                  onOpenDay: (day) {},
                  onCreateOnDay: null,
                  onOpenEntry: (id) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.byKey(monthStripKey(day)));
      await tester.pumpAndSettle();
      // Setup sanity: the tap focuses the board.
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<MonthBoard<String>>(),
        isNotNull,
      );
      reported.clear();
    }

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    // The grid of June 2026 starts on Monday June 1: no day of May before it.
    await show(june(1));
    await press(LogicalKeyboardKey.arrowLeft);
    expect(selected, DateTime(2026, 5, 31));
    await show(june(1));
    await press(LogicalKeyboardKey.arrowUp);
    expect(selected, DateTime(2026, 5, 25));
    // Sunday June 7 ends the grid's first row.
    await show(june(7));
    await press(LogicalKeyboardKey.arrowRight);
    expect(selected, june(8));
    // Tuesday June 30 lies in the grid's last row.
    await show(june(30));
    await press(LogicalKeyboardKey.arrowDown);
    expect(selected, DateTime(2026, 7, 7));
    // August 2026 starts on a Saturday, so Monday to Friday its grid starts
    // on Monday August 3.
    await show(DateTime(2026, 8, 3), weekdays: CalendarWeekdaySet.workweek);
    await press(LogicalKeyboardKey.arrowLeft);
    expect(selected, DateTime(2026, 7, 31));
    await show(DateTime(2026, 8, 3), weekdays: CalendarWeekdaySet.workweek);
    await press(LogicalKeyboardKey.arrowUp);
    expect(selected, DateTime(2026, 7, 27));
    await show(DateTime(2026, 8, 7), weekdays: CalendarWeekdaySet.workweek);
    await press(LogicalKeyboardKey.arrowRight);
    expect(selected, DateTime(2026, 8, 10));
    // The board's columns run left to right under right-to-left too.
    await show(june(10), direction: TextDirection.rtl);
    await press(LogicalKeyboardKey.arrowLeft);
    expect(selected, june(9));

    // Two keys before a frame: the second steps from the first's day.
    await show(june(10));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(reported, <DateTime>[june(11), june(12)]);

    // Home is the board's: the first cell of the row.
    await show(june(10));
    await press(LogicalKeyboardKey.home);
    expect(selected, june(8));

    // An arrow and a key of the board's before a frame, either way round:
    // each steps from the day the other selected.
    await show(june(7));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(selected, june(8));
    await show(june(3));
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(selected, june(2));
    await show(june(10));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(selected, june(9));
    // A key of the board's before the frame that shows an arrow's day of
    // another month does nothing: from June 3, Home would select June 1.
    await show(june(3));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(reported, <DateTime>[DateTime(2026, 5, 27)]);

    // Days wider than the view: a day a key selects is scrolled into view.
    await show(june(1), minDayWidth: minDayWidthHigh);
    final view = tester.getRect(find.byType(MonthBoard<String>));
    // Setup sanity: Friday June 5 lies past the view's right edge.
    expect(
      tester.getRect(find.byKey(monthDayKey(june(5)))).right,
      greaterThan(view.right),
    );
    for (var i = 0; i < 4; i++) {
      await press(LogicalKeyboardKey.arrowRight);
    }
    expect(selected, june(5));
    final shown = tester.getRect(find.byKey(monthDayKey(june(5))));
    expect(
      shown.left >= view.left - 0.5 && shown.right <= view.right + 0.5,
      isTrue,
      reason: "$shown in $view",
    );

    // An owner that takes no day: the keys still select and reveal on the
    // board, each stepping from the day the one before selected.
    await show(june(1), minDayWidth: minDayWidthHigh, takes: false);
    for (var i = 0; i < 4; i++) {
      await press(LogicalKeyboardKey.arrowRight);
    }
    expect(reported, <DateTime>[june(2), june(3), june(4), june(5)]);
    final kept = tester.getRect(find.byKey(monthDayKey(june(5))));
    expect(
      kept.left >= view.left - 0.5 && kept.right <= view.right + 0.5,
      isTrue,
      reason: "$kept in $view",
    );
  });

  testWidgets("MBZ1 a month board over a zoned store marks the zone's today, "
      "moves a running create's mark to the day holding its start on a new "
      "zone's clock, and names its cover's days on the zone's clock", (
    tester,
  ) async {
    final on = DateTime(2026, 4, 21, 12);
    final behind = zoneApartFromDevice(on, -6);
    final ahead = zoneApartFromDevice(on, 6);
    DateTime dayIn(tz.Location zone, int day) {
      return dayOfNumberIn(CalendarDates.dayNumber(april(day)), zone);
    }

    final store = memoryStoreIn<String>(behind);
    addTearDown(store.dispose);
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(
        time: tz.TZDateTime(behind, 2026, 4, 21, 20),
        today: dayIn(behind, 21),
      ),
    );
    addTearDown(now.dispose);
    final done = Completer<void>();
    final pressed = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MonthBoard<String>(
          store: store,
          grid: grid,
          selectedDay: april(20),
          now: now,
          onSelectDay: (day) {},
          onOpenDay: (day) {},
          onCreateOnDay: (day, globalRect) {
            pressed.add(day);
            return (
              start: tz.TZDateTime(behind, 2026, 4, 21, 22),
              done: done.future,
            );
          },
          onOpenEntry: (id) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    bool markedToday(DateTime day) {
      final cell = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byKey(monthDayKey(day)),
              matching: find.byType(Semantics),
            )
            .first,
      );
      return cell.properties.label!.split(", ").contains("today");
    }

    expect(markedToday(april(21)), isTrue);
    expect(markedToday(april(20)), isFalse);
    expect(markedToday(april(22)), isFalse);

    await tester.longPress(find.byKey(monthStripKey(april(21))));
    await tester.pump();
    expect(pressed, <DateTime>[april(21)]);
    final mark = createMarkIn(tester, find.byType(MonthBoard<String>));
    final on21 = createMarksUnder(find.byKey(monthDayKey(april(21))), mark);
    final on22 = createMarksUnder(find.byKey(monthDayKey(april(22))), mark);
    expect(on21, findsOneWidget);
    expect(on22, findsNothing);

    // The start, 22:00 on the 21st six hours behind, is 10:00 on the 22nd
    // six hours ahead.
    setStoreZone(store, ahead);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(on21, findsNothing);
    expect(on22, findsOneWidget);
    done.complete();
    await tester.pumpAndSettle();
    expect(
      createMarksUnder(find.byType(MonthBoard<String>), mark),
      findsNothing,
    );

    final loading = <CalendarLoadingState>[];
    final caching = cachingStoreIn<String>(behind, dataSource: SilentSource());
    addTearDown(caching.dispose);
    caching.show(grid.firstDay, grid.lastDay);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthBoard<String>(
          store: caching,
          grid: grid,
          selectedDay: april(20),
          now: now,
          onSelectDay: (day) {},
          onOpenDay: (day) {},
          onCreateOnDay: null,
          onOpenEntry: (id) {},
          loadingBuilder: (context, state) {
            loading.add(state);
            return const SizedBox.expand();
          },
        ),
      ),
    );
    await tester.pump();
    expect(caching.status, CalendarLoadStatus.loading);
    final state = loading.last;
    expect(state.site, CalendarStateSite.cover);
    expect(state.first, isA<tz.TZDateTime>());
    expect((state.first as tz.TZDateTime).location, behind);
    expect(
      state.first,
      dayOfNumberIn(CalendarDates.dayNumber(grid.firstDay), behind),
    );
    expect(state.last, isA<tz.TZDateTime>());
    expect(
      state.last,
      dayOfNumberIn(CalendarDates.dayNumber(grid.lastDay), behind),
    );
  });

  group("a new selected day of the shown month", () {
    late ValueNotifier<CalendarNow> now;

    setUp(() {
      now = ValueNotifier<CalendarNow>(
        CalendarNow(time: DateTime(2026, 4, 1, 9), today: april(1)),
      );
    });

    tearDown(() {
      now.dispose();
    });

    /// A board of [grid] over [store] at [weekScale], 400 by 600 px, with
    /// [selected] selected.
    Widget boardOf(
      WidgetTester tester,
      CalendarStore<String> store,
      DateTime selected, {
      double weekScale = 3.0,
    }) {
      tester.view.physicalSize = const Size(400.0, 600.0);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      return MaterialApp(
        home: MonthBoard<String>(
          store: store,
          grid: grid,
          weekScale: weekScale,
          selectedDay: selected,
          now: now,
          onSelectDay: (day) {},
          onOpenDay: (day) {},
          onCreateOnDay: null,
          onOpenEntry: (id) {},
        ),
      );
    }

    /// The rect of [day]'s cell.
    Rect cellRect(WidgetTester tester, DateTime day) {
      return tester.getRect(find.byKey(monthDayKey(day)));
    }

    /// The board's vertical scroll offset.
    double scrolledOf(WidgetTester tester) {
      return tester
          .stateList<ScrollableState>(
            // The board's two dimensions are subtypes of Scrollable.
            find.descendant(
              of: find.byType(MonthBoard<String>),
              matching: find.byWidgetPredicate((widget) {
                return widget is Scrollable;
              }),
            ),
          )
          .singleWhere((scrollable) {
            return scrollable.position.axis == Axis.vertical;
          })
          .position
          .pixels;
    }

    /// Whether the board shows [day]'s cell whole, under the letters.
    bool shows(WidgetTester tester, DateTime day) {
      final cell = find.byKey(monthDayKey(day));
      if (cell.evaluate().isEmpty) {
        return false;
      }
      final rect = tester.getRect(cell);
      final area = tester.getRect(find.byType(MonthBoard<String>));
      return rect.top >= area.top + weekdayHeaderHeight - 0.5 &&
          rect.bottom <= area.bottom + 0.5;
    }

    testWidgets("MB7 out of view scrolls the least that shows it whole, and "
        "one the board shows whole moves nothing", (tester) async {
      // At a week scale of 2 the board shows two weeks whole.
      final store = MemoryCalendarStore<String>();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        boardOf(tester, store, april(28), weekScale: 2.0),
      );
      await tester.pumpAndSettle();
      // Setup sanity: the board opened on April 28's week, the last, and
      // April 1's lies out of view.
      expect(shows(tester, april(28)), isTrue);
      expect(shows(tester, april(1)), isFalse);

      await tester.pumpWidget(boardOf(tester, store, april(1), weekScale: 2.0));
      await tester.pumpAndSettle();
      expect(shows(tester, april(1)), isTrue);

      // April 8's week lies whole in view, under April 1's.
      final shown = cellRect(tester, april(8));
      // Setup sanity: a scroll that brought April 8's week to the top
      // would move it.
      expect(shown.top, greaterThan(weekdayHeaderHeight + 1.0));
      await tester.pumpWidget(boardOf(tester, store, april(8), weekScale: 2.0));
      await tester.pumpAndSettle();
      expect(cellRect(tester, april(8)), shown);

      // April 15's week lies partly below the view: the least scroll ends
      // it at the board's bottom.
      await tester.pumpWidget(
        boardOf(tester, store, april(15), weekScale: 2.0),
      );
      await tester.pumpAndSettle();
      expect(
        cellRect(tester, april(15)).bottom,
        moreOrLessEquals(
          tester.getRect(find.byType(MonthBoard<String>)).bottom,
        ),
      );
    });

    testWidgets("MB8 does not move the board while a drag scrolls it, which "
        "follows the finger after, nor while two fingers hold it", (
      tester,
    ) async {
      final store = MemoryCalendarStore<String>();
      addTearDown(store.dispose);
      await tester.pumpWidget(boardOf(tester, store, april(1)));
      await tester.pumpAndSettle();
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(monthDayKey(april(8)))),
      );
      await drag.moveBy(const Offset(0.0, -30.0));
      await drag.moveBy(const Offset(0.0, -30.0));
      await tester.pump();
      final dragged = scrolledOf(tester);
      // Setup sanity: the drag scrolled the board, and April 28 lies out
      // of view.
      expect(dragged, greaterThan(10.0));
      expect(shows(tester, april(28)), isFalse);
      await tester.pumpWidget(boardOf(tester, store, april(28)));
      await tester.pump();
      await drag.moveBy(const Offset(0.0, -20.0));
      await tester.pump();
      expect(scrolledOf(tester), moreOrLessEquals(dragged + 20.0));
      await drag.up();
      await tester.pumpAndSettle();

      // A board taken out of the tree and opened again on April 1.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(boardOf(tester, store, april(1)));
      await tester.pumpAndSettle();
      final opened = scrolledOf(tester);
      final centre = tester.getCenter(find.byKey(monthDayKey(april(8))));
      final first = await tester.startGesture(centre - const Offset(30.0, 0.0));
      final second = await tester.startGesture(
        centre + const Offset(30.0, 0.0),
      );
      await tester.pump();
      await tester.pumpWidget(boardOf(tester, store, april(28)));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(scrolledOf(tester), opened);
    });

    testWidgets("MB9 given while its days are read scrolls to it again once "
        "they are, the weeks above it grown", (tester) async {
      final memory = MemoryCalendarStore<String>();
      addTearDown(memory.dispose);
      await tester.pumpWidget(
        boardOf(tester, memory, april(1), weekScale: 1.0),
      );
      await tester.pumpAndSettle();
      final source = HeldSource();
      final caching = CachingCalendarStore<String>(dataSource: source);
      addTearDown(caching.dispose);
      caching.show(grid.firstDay, grid.lastDay);
      await tester.pumpWidget(
        boardOf(tester, caching, april(28), weekScale: 1.0),
      );
      await tester.pump();
      // Setup sanity: the days are being read.
      expect(caching.status, CalendarLoadStatus.loading);
      // Eight items on each day of the first four weeks grow them past the
      // board's height.
      source.answerAll(<CalendarEntry<String>>[
        for (var day = 0; day < 4 * DateTime.daysPerWeek; day++)
          for (var hour = 8; hour < 16; hour++)
            CalendarEntry<String>(
              id: "e$day-$hour",
              start: CalendarDates.addDays(
                grid.firstDay,
                day,
              ).add(Duration(hours: hour)),
              end: CalendarDates.addDays(
                grid.firstDay,
                day,
              ).add(Duration(hours: hour + 1)),
              title: "e$day-$hour",
              color: const Color(0xFF336699),
              payload: "e$day-$hour",
            ),
      ]);
      await tester.pumpAndSettle();
      expect(caching.status, CalendarLoadStatus.ready);
      expect(
        cellRect(tester, april(6)).top -
            cellRect(tester, DateTime(2026, 3, 30)).top,
        greaterThan(150.0),
      );
      expect(shows(tester, april(28)), isTrue);
    });
  });
}

/// A data source whose reads wait until [answerAll] answers them.
class HeldSource implements CalendarDataSource<String> {
  final List<
    ({
      DateTime first,
      DateTime last,
      Completer<List<CalendarEntry<String>>> answer,
    })
  >
  _held =
      <
        ({
          DateTime first,
          DateTime last,
          Completer<List<CalendarEntry<String>>> answer,
        })
      >[];

  /// Answers every read held with those of [entries] that cover its days.
  void answerAll(List<CalendarEntry<String>> entries) {
    final held = List.of(_held);
    _held.clear();
    for (final read in held) {
      final from = CalendarDates.dayNumber(read.first);
      final to = CalendarDates.dayNumber(read.last);
      read.answer.complete(<CalendarEntry<String>>[
        for (final entry in entries)
          if (CalendarDates.dayNumber(entry.start) <= to &&
              CalendarDates.lastDayNumberOf(entry.start, entry.end) >= from)
            entry,
      ]);
    }
  }

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    final answer = Completer<List<CalendarEntry<String>>>();
    _held.add((first: first, last: last, answer: answer));
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
