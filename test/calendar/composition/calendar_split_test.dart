/// When the views split the shown entries and place them: a calendar over
/// a month of 5,000 entries, 200 of them on one day, splits once per store
/// write and per step, and a scroll, a pinch, a drag's moves, a pill and an
/// edit-mode change split nothing.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/composition/calendar_header.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/entry_split.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);
final DateTime thursday = DateTime(2026, 4, 23);
final DateTime friday = DateTime(2026, 4, 24);
final DateTime saturday = DateTime(2026, 4, 25);

/// 11:07 on Tuesday April 21 2026.
DateTime fixedClock() {
  return DateTime(2026, 4, 21, 11, 7);
}

/// [hour]:[minute] on [day].
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

/// 5,000 entries in April 2026: 200 on Tuesday April 21, from 13:00 on;
/// across the month's other days timed entries from 13:00 on, overnight
/// ones from 22:00 to 01:00 and entries over three days from 20:00 to
/// 02:00, none of which reaches Wednesday to Friday of the week of April
/// 20; and the all-day entries of that week alone: five on Wednesday,
/// which need two strip rows more than the collapsed strip's three, and
/// one on Friday, "free". Thursday holds "solo", from 10:00 to 10:45, which
/// shares time with nothing.
List<CalendarEntry<String>> monthOfEntries() {
  final entries = <CalendarEntry<String>>[
    for (var i = 0; i < 200; i++)
      entryOf("t$i", at(tuesday, 13, i * 2), at(tuesday, 13, i * 2 + 30)),
    for (var i = 0; i < 5; i++) entryOf("w$i", wednesday, thursday),
    entryOf("free", friday, saturday),
    entryOf("solo", at(thursday, 10), at(thursday, 10, 45)),
  ];
  var k = 0;
  while (entries.length < 5000) {
    final day = DateTime(2026, 4, 1 + k % 30);
    final number = day.day;
    final kind = k % 10;
    if (kind == 0 && number < 30) {
      entries.add(entryOf("n$k", at(day, 22), at(addDays(day, 1), 1)));
    } else if (kind == 1 && number <= 18) {
      entries.add(entryOf("m$k", at(day, 20), at(addDays(day, 2), 2)));
    } else if (number < 21 || number > 24) {
      final start = 13 * 60 + (k * 7) % 480;
      entries.add(
        entryOf("e$k", at(day, 0, start), at(day, 0, start + 20 + k % 25)),
      );
    }
    k++;
  }
  return entries;
}

/// The two counters as they stand.
(int, int) counts() {
  return (debugEntrySplitCount, debugEntryPlaceCount);
}

void resetCounts() {
  debugEntrySplitCount = 0;
  debugEntryPlaceCount = 0;
}

void main() {
  late MemoryCalendarStore<String> store;

  setUp(() {
    store = MemoryCalendarStore<String>(entries: monthOfEntries());
    resetCounts();
  });

  tearDown(() {
    store.dispose();
  });

  /// Pumps the calendar on [view], 800 wide and 600 tall, in edit mode
  /// while [editable] holds.
  Future<CalendarController> pumpCalendar(
    WidgetTester tester,
    CalendarViewKind view,
    ValueNotifier<bool> editable, {
    MonthLayout monthLayout = MonthLayout.fitScreen,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800.0, 600.0);
    addTearDown(tester.view.reset);
    final controller = CalendarController(view: view);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: ValueListenableBuilder<bool>(
          valueListenable: editable,
          builder: (context, value, child) {
            return CalendarView<String>(
              store: store,
              controller: controller,
              clock: fixedClock,
              editable: value,
              monthLayout: monthLayout,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// Drags a touch from [from] by [step] ten times, a frame after each.
  Future<void> dragTenFrames(
    WidgetTester tester,
    Offset from,
    Offset step,
  ) async {
    final gesture = await tester.startGesture(from);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(step);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
  }

  testWidgets("SP1 in Week a store write and a next-week step each split and "
      "place once, ten frames of a scroll, a pinch and a block's drag split "
      "and place nothing, and a \"+N\" pill and an edit-mode change place "
      "once and split nothing", (tester) async {
    final editable = ValueNotifier<bool>(true);
    addTearDown(editable.dispose);
    await pumpCalendar(tester, CalendarViewKind.week, editable);
    // Setup sanity: Week shows the week of April 20, its entries split.
    expect(find.byKey(blockKey("solo", thursday)), findsOneWidget);
    expect(find.byKey(allDayMoreKey(wednesday)), findsOneWidget);
    expect(debugEntrySplitCount, greaterThan(0));

    resetCounts();
    final free = store.storedEntry("free")!;
    store.requestMove(
      free.copyWith(start: saturday, end: addDays(saturday, 1)),
    );
    await tester.pumpAndSettle();
    expect(counts(), (1, 1), reason: "a store write");

    final grid = tester.getRect(find.byType(TimedGrid<String>));
    resetCounts();
    await dragTenFrames(
      tester,
      Offset(grid.left + 20.0, grid.center.dy),
      const Offset(0.0, -20.0),
    );
    expect(counts(), (0, 0), reason: "a scroll");
    await tester.pumpAndSettle();

    resetCounts();
    final first = await tester.startGesture(grid.center - const Offset(0, 30));
    final second = await tester.startGesture(grid.center + const Offset(0, 30));
    for (var i = 0; i < 10; i++) {
      await first.moveBy(const Offset(0.0, -4.0));
      await second.moveBy(const Offset(0.0, 4.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up();
    await second.up();
    expect(counts(), (0, 0), reason: "a pinch");
    await tester.pumpAndSettle();

    final solo = find.byKey(blockKey("solo", thursday));
    await tester.ensureVisible(solo);
    await tester.pumpAndSettle();
    final lift = await tester.startGesture(tester.getCenter(solo));
    await tester.pump(kLongPressTimeout + kPressTimeout);
    // Setup sanity: the block lifted.
    expect(find.byKey(liftedBlockKey), findsOneWidget);
    resetCounts();
    for (var i = 0; i < 10; i++) {
      await lift.moveBy(const Offset(0.0, 3.0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(counts(), (0, 0), reason: "a block's drag");
    await lift.up();
    await tester.pumpAndSettle();

    resetCounts();
    await tester.tap(find.byKey(allDayMoreKey(wednesday)));
    await tester.pumpAndSettle();
    // Setup sanity: the strip expanded.
    expect(find.byKey(allDayLessKey), findsOneWidget);
    expect(counts(), (0, 1), reason: "a pill");

    resetCounts();
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    // Setup sanity: Week shows the week of April 27, which holds no
    // all-day entry.
    expect(find.byKey(allDayCellKey(DateTime(2026, 4, 27))), findsOneWidget);
    expect(counts(), (1, 1), reason: "a next-week step");

    resetCounts();
    editable.value = false;
    await tester.pumpAndSettle();
    // Setup sanity: out of edit mode the empty strip's row went.
    expect(find.byKey(allDayCellKey(DateTime(2026, 4, 27))), findsNothing);
    expect(counts(), (0, 1), reason: "an edit-mode change");
  });

  testWidgets("SP2 in Month ten frames of a scroll split nothing, and a store "
      "write and a next-month step each split once", (tester) async {
    final editable = ValueNotifier<bool>(true);
    addTearDown(editable.dispose);
    await pumpCalendar(
      tester,
      CalendarViewKind.month,
      editable,
      monthLayout: MonthLayout.showAll,
    );
    // Setup sanity: Month split the store's entries.
    expect(debugEntrySplitCount, greaterThan(0));

    final board = tester.getRect(find.byType(MonthBoard<String>));
    resetCounts();
    await dragTenFrames(tester, board.center, const Offset(0.0, -20.0));
    expect(debugEntrySplitCount, 0, reason: "a scroll");
    await tester.pumpAndSettle();

    resetCounts();
    final free = store.storedEntry("free")!;
    store.requestMove(
      free.copyWith(start: saturday, end: addDays(saturday, 1)),
    );
    await tester.pumpAndSettle();
    expect(debugEntrySplitCount, 1, reason: "a store write");

    resetCounts();
    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    expect(debugEntrySplitCount, 1, reason: "a next-month step");
  });
}
