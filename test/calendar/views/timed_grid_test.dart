/// The timed grid: where an entry's days and minutes sit on its tracks
/// and back from the span a drop reports, over some of the weekdays and
/// part of the day, the create ranges its gestures pick, the weekdays,
/// hours, hour format and least sizes it lays out from, the edit mode and
/// lock choices its drags follow, what each of those defaults to, and a
/// block drawn again for a new payload.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/pinch_zoom.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';

/// The Monday of the week shown.
final int weekStartDay = dayNumber(DateTime(2026, 4, 20));

/// The week from [weekStartDay], every day and every minute shown.
final GridTracks week = GridTracks(firstDay: weekStartDay, dayCount: 7);

CalendarEntryTime shapeOf(DateTime firstDay, int dayCount, int start, int end) {
  return (
    firstDay: dayNumber(firstDay),
    dayCount: dayCount,
    start: start,
    end: end,
  );
}

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);

/// [grid] in a box of [size] at the top left, under no calendar theme.
Widget boxed(Size size, TimedGrid<String> grid) {
  return MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: size.width, height: size.height, child: grid),
    ),
  );
}

/// Pumps [grid] [boxed] at [size], in a view of that size.
Future<void> pumpBoxed(
  WidgetTester tester,
  Size size,
  TimedGrid<String> grid,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(boxed(size, grid));
}

/// The grid's viewport: the one board keyed by entry id strings.
RenderBoardViewport<String> viewportOf(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

/// 09:00 on April 21 2026.
DateTime nineOClock() {
  return DateTime(2026, 4, 21, 9);
}

Finder blockFinder(String id) {
  return find.byKey(blockKey(id));
}

void main() {
  group("S1 gridSpanOf", () {
    test("places a day's slots in its column, below the header", () {
      final tuesday = shapeOf(DateTime(2026, 4, 21), 1, 600, 780);
      expect(
        gridSpanOf(tuesday, week),
        const BoardSpan(rowStart: 41, colStart: 2, rowSpan: 12, colSpan: 1),
      );
    });

    test("clips the days outside the week", () {
      final fromFriday = shapeOf(DateTime(2026, 4, 17), 4, 1080, 1140);
      expect(
        gridSpanOf(fromFriday, week),
        const BoardSpan(rowStart: 73, colStart: 1, rowSpan: 4, colSpan: 1),
      );
      final fromSaturday = shapeOf(DateTime(2026, 4, 25), 4, 1080, 1140);
      expect(
        gridSpanOf(fromSaturday, week),
        const BoardSpan(rowStart: 73, colStart: 6, rowSpan: 4, colSpan: 2),
      );
    });

    test("is null for an item with no day in the week", () {
      final later = shapeOf(DateTime(2026, 5, 4), 1, 600, 660);
      expect(gridSpanOf(later, week), isNull);
    });

    test("clips to a one-day grid on both sides", () {
      final wednesday = GridTracks(
        firstDay: dayNumber(DateTime(2026, 4, 22)),
        dayCount: 1,
      );
      final threeDays = shapeOf(DateTime(2026, 4, 21), 3, 1080, 1140);
      expect(
        gridSpanOf(threeDays, wednesday),
        const BoardSpan(rowStart: 73, colStart: 1, rowSpan: 4, colSpan: 1),
      );
      final thursday = shapeOf(DateTime(2026, 4, 23), 1, 1080, 1140);
      expect(gridSpanOf(thursday, wednesday), isNull);
    });
  });

  group("S2 shapeFromSpan", () {
    test("a move shifts the first day by the column change and the minutes "
        "by the row change", () {
      final tuesday = shapeOf(DateTime(2026, 4, 21), 1, 600, 780);
      final from = gridSpanOf(tuesday, week)!;
      final moved = shapeFromSpan(
        tuesday,
        from,
        const BoardSpan(rowStart: 45, colStart: 3, rowSpan: 12, colSpan: 1),
        week,
      );
      expect(moved, shapeOf(DateTime(2026, 4, 22), 1, 660, 840));
    });

    test("a right-edge resize of one column adds a day", () {
      final tuesday = shapeOf(DateTime(2026, 4, 21), 1, 600, 780);
      final from = gridSpanOf(tuesday, week)!;
      final resized = shapeFromSpan(
        tuesday,
        from,
        const BoardSpan(rowStart: 41, colStart: 2, rowSpan: 12, colSpan: 2),
        week,
      );
      expect(resized, shapeOf(DateTime(2026, 4, 21), 2, 600, 780));
    });

    test("an item clipped at the week's start keeps its hidden days", () {
      final fromFriday = shapeOf(DateTime(2026, 4, 17), 4, 1080, 1140);
      final from = gridSpanOf(fromFriday, week)!;
      final moved = shapeFromSpan(
        fromFriday,
        from,
        const BoardSpan(rowStart: 73, colStart: 2, rowSpan: 4, colSpan: 1),
        week,
      );
      expect(moved, shapeOf(DateTime(2026, 4, 18), 4, 1080, 1140));
      final toSunday = shapeFromSpan(
        fromFriday,
        from,
        const BoardSpan(rowStart: 73, colStart: 1, rowSpan: 4, colSpan: 7),
        week,
      );
      expect(toSunday, shapeOf(DateTime(2026, 4, 17), 10, 1080, 1140));
    });

    test("an item clipped at the week's end ends on the column its right "
        "edge is dropped on", () {
      final fromSaturday = shapeOf(DateTime(2026, 4, 25), 4, 1080, 1140);
      final from = gridSpanOf(fromSaturday, week)!;
      final shortened = shapeFromSpan(
        fromSaturday,
        from,
        const BoardSpan(rowStart: 73, colStart: 6, rowSpan: 4, colSpan: 1),
        week,
      );
      expect(shortened, shapeOf(DateTime(2026, 4, 25), 1, 1080, 1140));
      final movedLeft = shapeFromSpan(
        fromSaturday,
        from,
        const BoardSpan(rowStart: 73, colStart: 5, rowSpan: 4, colSpan: 2),
        week,
      );
      expect(movedLeft, shapeOf(DateTime(2026, 4, 24), 4, 1080, 1140));
      final longer = shapeFromSpan(
        fromSaturday,
        from,
        const BoardSpan(rowStart: 73, colStart: 6, rowSpan: 6, colSpan: 2),
        week,
      );
      expect(longer, shapeOf(DateTime(2026, 4, 25), 4, 1080, 1170));
    });
  });

  group("S3 a grid over some of the weekdays", () {
    final tuesday = DateTime(2026, 4, 21);
    final wednesday = DateTime(2026, 4, 22);
    final thursday = DateTime(2026, 4, 23);

    /// The week without its Wednesday: Monday, Tuesday, Thursday to
    /// Sunday in columns 1 to 6.
    final noWednesday = GridTracks(
      firstDay: weekStartDay,
      dayCount: 7,
      weekdays: WeekdaySet.of(const <int>[0, 1, 3, 4, 5, 6]),
    );

    test("lays the held days out in order, the others with no column", () {
      expect(noWednesday.columnCount, 6);
      expect(noWednesday.dayAt(2), dayNumber(tuesday));
      expect(noWednesday.dayAt(3), dayNumber(thursday));
      expect(noWednesday.dateAt(6), DateTime(2026, 4, 26));
      expect(noWednesday.columnOf(dayNumber(thursday)), 3);
      expect(noWednesday.columnOf(dayNumber(wednesday)), isNull);
      expect(noWednesday.firstColumnFrom(dayNumber(wednesday)), 3);
      expect(noWednesday.lastColumnUpTo(dayNumber(wednesday)), 2);
      expect(noWednesday.firstColumnFrom(weekStartDay + 7), 7);
      expect(noWednesday.lastColumnUpTo(weekStartDay - 1), 0);
    });

    test("gridSpanOf joins the columns either side of a hidden day", () {
      expect(
        gridSpanOf(shapeOf(tuesday, 3, 600, 660), noWednesday),
        const BoardSpan(rowStart: 41, colStart: 2, rowSpan: 4, colSpan: 2),
      );
      expect(
        gridSpanOf(shapeOf(wednesday, 2, 600, 660), noWednesday),
        const BoardSpan(rowStart: 41, colStart: 3, rowSpan: 4, colSpan: 1),
      );
      expect(gridSpanOf(shapeOf(wednesday, 1, 600, 660), noWednesday), isNull);
    });

    test("the weekend leaves a workweek grid", () {
      final workweek = GridTracks(
        firstDay: weekStartDay,
        dayCount: 7,
        weekdays: WeekdaySet.workweek,
      );
      expect(workweek.columnCount, 5);
      expect(workweek.dateAt(5), DateTime(2026, 4, 24));
      expect(
        gridSpanOf(shapeOf(DateTime(2026, 4, 24), 3, 600, 660), workweek),
        const BoardSpan(rowStart: 41, colStart: 5, rowSpan: 4, colSpan: 1),
      );
      expect(
        gridSpanOf(shapeOf(DateTime(2026, 4, 25), 2, 600, 660), workweek),
        isNull,
      );
    });

    test("a move shifts the days by the days between the columns", () {
      final one = shapeOf(tuesday, 1, 600, 660);
      expect(
        shapeFromSpan(
          one,
          gridSpanOf(one, noWednesday)!,
          const BoardSpan(rowStart: 41, colStart: 3, rowSpan: 4, colSpan: 1),
          noWednesday,
        ),
        shapeOf(thursday, 1, 600, 660),
      );
      final three = shapeOf(tuesday, 3, 600, 660);
      expect(
        shapeFromSpan(
          three,
          gridSpanOf(three, noWednesday)!,
          const BoardSpan(rowStart: 41, colStart: 3, rowSpan: 4, colSpan: 2),
          noWednesday,
        ),
        shapeOf(thursday, 3, 600, 660),
      );
    });

    test("a right-edge resize ends on its last column's day", () {
      final one = shapeOf(tuesday, 1, 600, 660);
      expect(
        shapeFromSpan(
          one,
          gridSpanOf(one, noWednesday)!,
          const BoardSpan(rowStart: 41, colStart: 2, rowSpan: 4, colSpan: 2),
          noWednesday,
        ),
        shapeOf(tuesday, 3, 600, 660),
      );
    });

    test("a create range over the hidden day covers it", () {
      expect(
        createRangeOver(noWednesday, (row: 44, col: 3), (row: 41, col: 2)),
        CreateRange(
          day: tuesday,
          startMinute: 600,
          endMinute: 660,
          dayCount: 3,
        ),
      );
      expect(
        createRangeAt(noWednesday, (row: 41, col: 3)),
        CreateRange(
          day: thursday,
          startMinute: 600,
          endMinute: 615,
          dayCount: 1,
        ),
      );
    });
  });

  group("S4 a grid over part of the day", () {
    final tuesday = DateTime(2026, 4, 21);

    /// The week from 08:00 to 18:00: rows 1 to 40.
    final office = GridTracks(
      firstDay: weekStartDay,
      dayCount: 7,
      hours: const DayHours(8 * 60, 18 * 60),
    );

    test("rows count from the first hour", () {
      expect(office.rowCount, 40);
      expect(office.minuteAt(1), 8 * 60);
      expect(office.minuteAt(41), 18 * 60);
      expect(office.rowOf(9 * 60), 5);
    });

    test("gridSpanOf clips the minutes outside the hours", () {
      expect(
        gridSpanOf(shapeOf(tuesday, 1, 9 * 60, 10 * 60), office),
        const BoardSpan(rowStart: 5, colStart: 2, rowSpan: 4, colSpan: 1),
      );
      expect(
        gridSpanOf(shapeOf(tuesday, 1, 7 * 60, 9 * 60), office),
        const BoardSpan(rowStart: 1, colStart: 2, rowSpan: 4, colSpan: 1),
      );
      expect(
        gridSpanOf(shapeOf(tuesday, 1, 17 * 60, 19 * 60), office),
        const BoardSpan(rowStart: 37, colStart: 2, rowSpan: 4, colSpan: 1),
      );
      expect(gridSpanOf(shapeOf(tuesday, 1, 6 * 60, 8 * 60), office), isNull);
      expect(gridSpanOf(shapeOf(tuesday, 1, 18 * 60, 19 * 60), office), isNull);
    });

    test("a move reads the minutes from the rows below the first hour", () {
      final shape = shapeOf(tuesday, 1, 9 * 60, 10 * 60);
      expect(
        shapeFromSpan(
          shape,
          gridSpanOf(shape, office)!,
          const BoardSpan(rowStart: 9, colStart: 2, rowSpan: 4, colSpan: 1),
          office,
        ),
        shapeOf(tuesday, 1, 10 * 60, 11 * 60),
      );
    });

    test("create ranges start at the hours and stop at their end", () {
      expect(
        createRangeAt(office, (row: 1, col: 2)),
        CreateRange(
          day: tuesday,
          startMinute: 8 * 60,
          endMinute: 8 * 60 + 15,
          dayCount: 1,
        ),
      );
      expect(
        createRangeAt(office, (row: 40, col: 2)),
        CreateRange(
          day: tuesday,
          startMinute: 17 * 60 + 45,
          endMinute: 18 * 60,
          dayCount: 1,
        ),
      );
      expect(
        createRangeOver(office, (row: 1, col: 2), (row: 4, col: 2)),
        CreateRange(
          day: tuesday,
          startMinute: 8 * 60,
          endMinute: 9 * 60,
          dayCount: 1,
        ),
      );
    });
  });

  testWidgets("BW12 a write that changes only an entry's payload runs its "
      "block builder again, which draws the new payload", (tester) async {
    final day = DateTime(2026, 4, 21);
    final note = CalendarEntry<String>(
      id: "note-1",
      day: day,
      startMinute: 10 * 60,
      endMinute: 11 * 60,
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
    final now = ValueNotifier<DateTime>(nineOClock());
    addTearDown(now.dispose);
    final calls = <CalendarShownEntry<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TimedGrid<String>(
          store: store,
          firstDay: day,
          dayCount: 1,
          selectedDay: day,
          today: day,
          now: now,
          onSelectDay: (day) {},
          onOpenItem: (id) {},
          onCreate: (range) async {},
          blockBuilder: (context, entry, details) {
            calls.add(entry);
            return Text(entry.entry.payload);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final block = blockFinder("note-1");
    expect(
      find.descendant(of: block, matching: find.text("first")),
      findsOneWidget,
    );
    final before = calls.length;
    expect(calls.last.pending, isFalse);

    await store.update(note.copyWith(payload: "second"));
    await tester.pumpAndSettle();
    expect(calls.length, before + 1);
    expect(calls.last.pending, isFalse);
    expect(calls.last.entry.payload, "second");
    expect(
      find.descendant(of: block, matching: find.text("second")),
      findsOneWidget,
    );
  });

  testWidgets("TG1 a timed grid shows the weekdays and hours, labels the "
      "hours in the format and sizes its cells from the least sizes its "
      "parameters give it, and fits again when they change", (tester) async {
    const size = Size(300.0, 400.0);
    final store = MemoryCalendarStore<String>();
    addTearDown(store.dispose);
    final now = ValueNotifier<DateTime>(DateTime(2026, 4, 21, 9));
    addTearDown(now.dispose);
    TimedGrid<String> grid({
      required HourLabelFormat format,
      required double minSlotHeight,
    }) {
      return TimedGrid<String>(
        store: store,
        firstDay: monday,
        dayCount: 7,
        selectedDay: tuesday,
        today: tuesday,
        now: now,
        onSelectDay: (day) {},
        onOpenItem: (id) {},
        onCreate: (range) async {},
        weekdays: WeekdaySet.workweek,
        hours: const DayHours(8 * 60, 18 * 60),
        hourLabelFormat: format,
        minDayWidth: 100.0,
        minSlotHeight: minSlotHeight,
      );
    }

    await pumpBoxed(
      tester,
      size,
      grid(format: HourLabelFormat.twelveHour, minSlotHeight: 20.0),
    );
    await tester.pumpAndSettle();
    final viewport = viewportOf(tester);
    // The gutter and the five weekdays of the seven days.
    expect(viewport.rectOfCell(2, 5), isNotNull);
    expect(viewport.rectOfCell(2, 6), isNull);
    // The day header, the room above, the 40 slots from 08:00 to 18:00 and
    // the room below.
    expect(viewport.rectOfCell(42, 1), isNotNull);
    expect(viewport.rectOfCell(43, 1), isNull);
    // The box's shares, 244 / 5 px across and under 10 px down, are below
    // both least sizes.
    expect(viewport.rectOfCell(2, 1)!.size, const Size(100.0, 20.0));
    expect(find.bySemanticsLabel("8 AM"), findsOneWidget);
    expect(find.bySemanticsLabel("08:00"), findsNothing);

    await tester.pumpWidget(
      boxed(
        size,
        grid(format: HourLabelFormat.twentyFourHour, minSlotHeight: 20.0),
      ),
    );
    expect(find.bySemanticsLabel("08:00"), findsOneWidget);
    expect(find.bySemanticsLabel("8 AM"), findsNothing);
    expect(viewport.rectOfCell(2, 1)!.size, const Size(100.0, 20.0));

    await tester.pumpWidget(
      boxed(
        size,
        grid(format: HourLabelFormat.twentyFourHour, minSlotHeight: 24.0),
      ),
    );
    expect(viewport.rectOfCell(2, 1)!.size, const Size(100.0, 24.0));
  });

  testWidgets("TG2 a timed grid takes drags only when editable, and holds "
      "the blocks its lock choices hold", (tester) async {
    const size = Size(400.0, 800.0);
    CalendarEntry<String> entry(String id, DateTime day, int start, int end) {
      return CalendarEntry<String>(
        id: id,
        day: day,
        startMinute: start,
        endMinute: end,
        title: id,
        color: const Color(0xFF336699),
        payload: id,
      );
    }

    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entry("past", monday, 9 * 60, 10 * 60),
        entry("ended", tuesday, 8 * 60, 9 * 60),
        entry("running", tuesday, 10 * 60, 12 * 60),
        entry("later", tuesday, 14 * 60, 15 * 60),
      ],
    );
    addTearDown(store.dispose);
    // After ended ends, while running runs and before later starts.
    final now = ValueNotifier<DateTime>(DateTime(2026, 4, 21, 11, 7));
    addTearDown(now.dispose);
    TimedGrid<String> grid({
      required bool editable,
      required bool lockPast,
      required bool lockEarlierToday,
    }) {
      return TimedGrid<String>(
        store: store,
        firstDay: monday,
        dayCount: 2,
        selectedDay: tuesday,
        today: tuesday,
        now: now,
        onSelectDay: (day) {},
        onOpenItem: (id) {},
        onCreate: (range) async {},
        editable: editable,
        lockPast: lockPast,
        lockEarlierToday: lockEarlierToday,
        hours: const DayHours(8 * 60, 16 * 60),
      );
    }

    bool dragEnabled() {
      return tester
          .widget<Board<String, CalendarShownEntry<String>>>(
            find.byType(Board<String, CalendarShownEntry<String>>),
          )
          .drag!
          .enabled;
    }

    Finder handleOf(String id) {
      return find.descendant(
        of: find.byKey(blockKey(id)),
        matching: find.byType(BoardDelayedDragHandle),
      );
    }

    const ids = <String>["past", "ended", "running", "later"];
    Map<String, bool> handlesEnabled() {
      return <String, bool>{
        for (final id in ids)
          id: tester.widget<BoardDelayedDragHandle>(handleOf(id)).enabled,
      };
    }

    await pumpBoxed(
      tester,
      size,
      grid(editable: true, lockPast: true, lockEarlierToday: true),
    );
    await tester.pumpAndSettle();
    for (final id in ids) {
      expect(handleOf(id), findsOneWidget, reason: id);
    }
    expect(dragEnabled(), isTrue);
    expect(handlesEnabled(), <String, bool>{
      "past": false,
      "ended": false,
      "running": false,
      "later": true,
    });

    await tester.pumpWidget(
      boxed(
        size,
        grid(editable: true, lockPast: true, lockEarlierToday: false),
      ),
    );
    expect(dragEnabled(), isTrue);
    expect(handlesEnabled(), <String, bool>{
      "past": false,
      "ended": true,
      "running": true,
      "later": true,
    });

    await tester.pumpWidget(
      boxed(
        size,
        grid(editable: true, lockPast: false, lockEarlierToday: true),
      ),
    );
    expect(dragEnabled(), isTrue);
    expect(handlesEnabled(), <String, bool>{
      "past": true,
      "ended": true,
      "running": true,
      "later": true,
    });

    await tester.pumpWidget(
      boxed(
        size,
        grid(editable: false, lockPast: true, lockEarlierToday: true),
      ),
    );
    expect(dragEnabled(), isFalse);
    expect(handlesEnabled(), <String, bool>{
      "past": true,
      "ended": true,
      "running": true,
      "later": true,
    });
  });

  testWidgets("TG3 a timed grid given none of its eight layout and edit "
      "parameters shows every weekday and hour, labels the hours in 24-hour "
      "time, sizes its cells from minDayWidthLow and defaultMinSlotHeight, "
      "takes no drag, and made editable holds nothing until lockPast and "
      "then only the days before today", (tester) async {
    // Seven day columns' shares of 244 px across, and 96 slots' of the
    // height, are below both default least sizes.
    const size = Size(300.0, 800.0);
    CalendarEntry<String> entry(String id, DateTime day, int start, int end) {
      return CalendarEntry<String>(
        id: id,
        day: day,
        startMinute: start,
        endMinute: end,
        title: id,
        color: const Color(0xFF336699),
        payload: id,
      );
    }

    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entry("past", monday, 9 * 60, 10 * 60),
        entry("ended", tuesday, 8 * 60, 9 * 60),
      ],
    );
    addTearDown(store.dispose);
    // After ended ends, so a lock to now holds it; the grid opens scrolled
    // to 08:00, the hour before.
    final now = ValueNotifier<DateTime>(DateTime(2026, 4, 21, 9, 7));
    addTearDown(now.dispose);

    bool dragEnabled() {
      return tester
          .widget<Board<String, CalendarShownEntry<String>>>(
            find.byType(Board<String, CalendarShownEntry<String>>),
          )
          .drag!
          .enabled;
    }

    Finder handleOf(String id) {
      return find.descendant(
        of: find.byKey(blockKey(id)),
        matching: find.byType(BoardDelayedDragHandle),
      );
    }

    const ids = <String>["past", "ended"];
    Map<String, bool> handlesEnabled() {
      return <String, bool>{
        for (final id in ids)
          id: tester.widget<BoardDelayedDragHandle>(handleOf(id)).enabled,
      };
    }

    await pumpBoxed(
      tester,
      size,
      TimedGrid<String>(
        store: store,
        firstDay: monday,
        dayCount: 7,
        selectedDay: tuesday,
        today: tuesday,
        now: now,
        onSelectDay: (day) {},
        onOpenItem: (id) {},
        onCreate: (range) async {},
      ),
    );
    await tester.pumpAndSettle();
    final viewport = viewportOf(tester);
    for (final id in ids) {
      expect(handleOf(id), findsOneWidget, reason: id);
    }
    // The gutter and all seven days.
    expect(viewport.rectOfCell(2, 7), isNotNull);
    // The day header, the room above, the 96 slots of the whole day and the
    // room below.
    expect(viewport.rectOfCell(98, 1), isNotNull);
    expect(
      viewport.rectOfCell(2, 1)!.size,
      const Size(minDayWidthLow, defaultMinSlotHeight),
    );
    expect(find.bySemanticsLabel("08:00"), findsOneWidget);
    expect(find.bySemanticsLabel("8 AM"), findsNothing);
    expect(dragEnabled(), isFalse);

    await tester.pumpWidget(
      boxed(
        size,
        TimedGrid<String>(
          store: store,
          firstDay: monday,
          dayCount: 7,
          selectedDay: tuesday,
          today: tuesday,
          now: now,
          onSelectDay: (day) {},
          onOpenItem: (id) {},
          onCreate: (range) async {},
          editable: true,
        ),
      ),
    );
    expect(dragEnabled(), isTrue);
    expect(handlesEnabled(), <String, bool>{"past": true, "ended": true});

    await tester.pumpWidget(
      boxed(
        size,
        TimedGrid<String>(
          store: store,
          firstDay: monday,
          dayCount: 7,
          selectedDay: tuesday,
          today: tuesday,
          now: now,
          onSelectDay: (day) {},
          onOpenItem: (id) {},
          onCreate: (range) async {},
          editable: true,
          lockPast: true,
        ),
      ),
    );
    expect(handlesEnabled(), <String, bool>{"past": false, "ended": true});
  });

  test("TG4 a timed grid asserts that its least day width and least slot "
      "height are positive and finite", () {
    final store = MemoryCalendarStore<String>();
    addTearDown(store.dispose);
    final now = ValueNotifier<DateTime>(DateTime(2026, 4, 21, 9));
    addTearDown(now.dispose);
    TimedGrid<String> grid({
      double minDayWidth = minDayWidthLow,
      double minSlotHeight = defaultMinSlotHeight,
    }) {
      return TimedGrid<String>(
        store: store,
        firstDay: monday,
        dayCount: 7,
        selectedDay: tuesday,
        today: tuesday,
        now: now,
        onSelectDay: (day) {},
        onOpenItem: (id) {},
        onCreate: (range) async {},
        minDayWidth: minDayWidth,
        minSlotHeight: minSlotHeight,
      );
    }

    // The other arguments pass the constructor's asserts, so each failure
    // below is the size's own.
    expect(grid, returnsNormally);
    expect(() => grid(minDayWidth: 0.0), throwsAssertionError);
    expect(() => grid(minDayWidth: double.infinity), throwsAssertionError);
    expect(() => grid(minSlotHeight: 0.0), throwsAssertionError);
    expect(() => grid(minSlotHeight: double.infinity), throwsAssertionError);
  });
}
