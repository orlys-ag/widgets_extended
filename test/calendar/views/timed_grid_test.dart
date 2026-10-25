/// The timed grid: where an entry's pieces sit on its tracks, over some
/// of the weekdays and part of the day, the create ranges its gestures
/// pick, the weekdays,
/// hours, hour format and least sizes it lays out from, the edit mode and
/// lock choices its drags follow, what each of those defaults to, a
/// block drawn again for a new payload, the theme's shadows, when its days
/// are ready on the range its owner asks, and its selection as the store
/// moves off that range.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';
import 'package:widgets_extended/calendar/entries/calendar_data_source.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/history_lock_policy.dart';
import 'package:widgets_extended/calendar/presentation/calendar_builders.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/calendar/store/caching_calendar_store.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/pinch_zoom.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';

/// The Monday of the week shown.
final int weekStartDay = dayNumber(DateTime(2026, 4, 20));

/// The week from [weekStartDay], every day and every minute shown.
final GridTracks week = GridTracks(firstDay: weekStartDay, dayCount: 7);

/// [minute] minutes after [day]'s midnight.
DateTime at(DateTime day, int minute) {
  return DateTime(day.year, day.month, day.day, 0, minute);
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

/// The grid's viewport: the one board keyed by [GridKey]s.
RenderBoardViewport<GridKey> viewportOf(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<GridKey>>()
      .single;
}

/// 09:00 on April 21 2026.
DateTime nineOClock() {
  return DateTime(2026, 4, 21, 9);
}

/// The block of [id]'s piece on [day], or with no [day] every block of
/// [id], which for an entry on one shown day is its one block.
Finder blockFinder(String id, [DateTime? day]) {
  if (day != null) {
    return find.byKey(blockKey(id, day));
  }
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith("block-$id@");
  });
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

/// An entry with the id and title [id] from [start] minutes after [day]'s
/// midnight to [end] minutes after the midnight of its [dayCount]th day.
CalendarEntry<String> entryOf(
  String id,
  DateTime day,
  int start,
  int end, {
  int dayCount = 1,
}) {
  return CalendarEntry<String>(
    id: id,
    start: at(day, start),
    end: at(DateTime(day.year, day.month, day.day + dayCount - 1), end),
    title: id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

/// Draws a cover's loading state as "loading".
Widget loadingText(BuildContext context, CalendarLoadingState state) {
  return const Text("loading");
}

/// Draws a cover's failure state as "failed".
Widget failureText(BuildContext context, CalendarFailureState state) {
  return const Text("failed");
}

void main() {
  group("S1 pieceSpanOf", () {
    test("places a piece's minutes in its column, below the header", () {
      expect(
        pieceSpanOf(week, 2, 600, 780),
        const BoardSpan(rowStart: 41, colStart: 2, rowSpan: 12, colSpan: 1),
      );
    });

    test("places each piece of an entry from before the week in its own "
        "day's column", () {
      // Friday 18:00 to Tuesday 19:00: all of Monday, and Tuesday to 19:00.
      final span = wallSpanOf(
        DateTime(2026, 4, 17, 18),
        DateTime(2026, 4, 21, 19),
      );
      final onMonday = pieceOn(span, weekStartDay)!;
      final onTuesday = pieceOn(span, weekStartDay + 1)!;
      expect(
        pieceSpanOf(week, 1, onMonday.start, onMonday.end),
        const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 96, colSpan: 1),
      );
      expect(
        pieceSpanOf(week, 2, onTuesday.start, onTuesday.end),
        const BoardSpan(rowStart: 1, colStart: 2, rowSpan: 76, colSpan: 1),
      );
    });

    test("is null for a piece with no minute", () {
      expect(pieceSpanOf(week, 2, 600, 600), isNull);
    });

    test("lays a piece off the slot grid a fraction into its rows", () {
      expect(
        pieceSpanOf(week, 2, 550, 590),
        const BoardSpan(
          rowStart: 37,
          colStart: 2,
          rowFraction: 10 / 15,
          rowSpan: 2,
          rowSpanFraction: 10 / 15,
        ),
      );
    });
  });

  group("S2 createRangeOver", () {
    test("a drag over days is one range from the earlier slot's start to "
        "the later slot's end", () {
      final range = CreateRange(
        start: DateTime(2026, 4, 20, 10),
        end: DateTime(2026, 4, 22, 12, 15),
      );
      expect(
        createRangeOver(week, (row: 41, col: 1), (row: 49, col: 3)),
        range,
      );
      expect(
        createRangeOver(week, (row: 49, col: 3), (row: 41, col: 1)),
        range,
      );
    });

    test("a drag within a day picks the slots between its ends", () {
      expect(
        createRangeOver(week, (row: 44, col: 2), (row: 41, col: 2)),
        CreateRange(
          start: DateTime(2026, 4, 21, 10),
          end: DateTime(2026, 4, 21, 11),
        ),
      );
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

    test("a piece lies in its own day's column, after the hidden day", () {
      expect(
        pieceSpanOf(
          noWednesday,
          noWednesday.columnOf(dayNumber(thursday))!,
          600,
          660,
        ),
        const BoardSpan(rowStart: 41, colStart: 3, rowSpan: 4, colSpan: 1),
      );
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
        pieceSpanOf(
          workweek,
          workweek.columnOf(dayNumber(DateTime(2026, 4, 24)))!,
          600,
          660,
        ),
        const BoardSpan(rowStart: 41, colStart: 5, rowSpan: 4, colSpan: 1),
      );
      expect(workweek.columnOf(dayNumber(DateTime(2026, 4, 25))), isNull);
    });

    test("a create range over the hidden day covers it", () {
      expect(
        createRangeOver(noWednesday, (row: 44, col: 3), (row: 41, col: 2)),
        CreateRange(start: at(tuesday, 600), end: at(thursday, 660)),
      );
      expect(
        createRangeAt(noWednesday, (row: 41, col: 3)),
        CreateRange(start: at(thursday, 600), end: at(thursday, 615)),
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

    test("pieceSpanOf clips the minutes outside the hours", () {
      expect(
        pieceSpanOf(office, 2, 9 * 60, 10 * 60),
        const BoardSpan(rowStart: 5, colStart: 2, rowSpan: 4, colSpan: 1),
      );
      expect(
        pieceSpanOf(office, 2, 7 * 60, 9 * 60),
        const BoardSpan(rowStart: 1, colStart: 2, rowSpan: 4, colSpan: 1),
      );
      expect(
        pieceSpanOf(office, 2, 17 * 60, 19 * 60),
        const BoardSpan(rowStart: 37, colStart: 2, rowSpan: 4, colSpan: 1),
      );
      expect(pieceSpanOf(office, 2, 6 * 60, 8 * 60), isNull);
      expect(pieceSpanOf(office, 2, 18 * 60, 19 * 60), isNull);
    });

    test("create ranges start at the hours and stop at their end", () {
      expect(
        createRangeAt(office, (row: 1, col: 2)),
        CreateRange(start: at(tuesday, 8 * 60), end: at(tuesday, 8 * 60 + 15)),
      );
      expect(
        createRangeAt(office, (row: 40, col: 2)),
        CreateRange(
          start: at(tuesday, 17 * 60 + 45),
          end: at(tuesday, 18 * 60),
        ),
      );
      expect(
        createRangeOver(office, (row: 1, col: 2), (row: 4, col: 2)),
        CreateRange(start: at(tuesday, 8 * 60), end: at(tuesday, 9 * 60)),
      );
    });
  });

  testWidgets("BW12 a write that changes only an entry's payload runs its "
      "block builder again, which draws the new payload", (tester) async {
    final day = DateTime(2026, 4, 21);
    final note = CalendarEntry<String>(
      id: "note-1",
      start: at(day, 10 * 60),
      end: at(day, 11 * 60),
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
          onOpenEntry: (id) {},
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
        onOpenEntry: (id) {},
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
        start: at(day, start),
        end: at(day, end),
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
        onOpenEntry: (id) {},
        onCreate: (range) async {},
        editable: editable,
        editPolicy: lockPast
            ? HistoryLockPolicy<String>(lockEarlierToday: lockEarlierToday)
            : null,
        hours: const DayHours(8 * 60, 16 * 60),
      );
    }

    bool dragEnabled() {
      return tester
          .widget<Board<GridKey, GridShape<String>>>(
            find.byType(Board<GridKey, GridShape<String>>),
          )
          .drag!
          .enabled;
    }

    Finder handleOf(String id) {
      return find.descendant(
        of: blockFinder(id),
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
        start: at(day, start),
        end: at(day, end),
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
          .widget<Board<GridKey, GridShape<String>>>(
            find.byType(Board<GridKey, GridShape<String>>),
          )
          .drag!
          .enabled;
    }

    Finder handleOf(String id) {
      return find.descendant(
        of: blockFinder(id),
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
        onOpenEntry: (id) {},
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
          onOpenEntry: (id) {},
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
          onOpenEntry: (id) {},
          onCreate: (range) async {},
          editable: true,
          editPolicy: const HistoryLockPolicy<String>(),
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
        onOpenEntry: (id) {},
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

  testWidgets("TG5 a timed grid draws its selected block's grips and its "
      "lifted block over the theme's shadows", (tester) async {
    const size = Size(400.0, 800.0);
    const grip = <BoxShadow>[
      BoxShadow(
        color: Color(0x80102030),
        blurRadius: 5.0,
        offset: Offset(2.0, 3.0),
      ),
    ];
    const lifted = <BoxShadow>[
      BoxShadow(
        color: Color(0x80203040),
        offset: Offset(1.0, 7.0),
        blurRadius: 12.0,
        spreadRadius: 1.0,
      ),
    ];
    const theme = CalendarThemeData(
      gripShadows: grip,
      liftedBlockShadows: lifted,
    );
    // The theme's shadows are not the built-in ones, so a grid that drew
    // those would fail below.
    expect(grip, isNot(const CalendarThemeData().gripShadows));
    expect(lifted, isNot(const CalendarThemeData().liftedBlockShadows));
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entryOf("talk", tuesday, 10 * 60, 12 * 60),
      ],
    );
    addTearDown(store.dispose);
    final now = ValueNotifier<DateTime>(nineOClock());
    addTearDown(now.dispose);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CalendarTheme(
        data: theme,
        child: boxed(
          size,
          TimedGrid<String>(
            store: store,
            firstDay: monday,
            dayCount: 7,
            selectedDay: tuesday,
            today: tuesday,
            now: now,
            onSelectDay: (day) {},
            onOpenEntry: (id) {},
            onCreate: (range) async {},
            editable: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(blockFinder("talk")),
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    expect(find.byKey(liftedBlockKey), findsOneWidget);
    // Past the lift's motion, the theme's 300 ms.
    await tester.pump(const Duration(milliseconds: 400));
    final liftedBox = tester.widget<DecoratedBox>(find.byKey(liftedBlockKey));
    expect((liftedBox.decoration as BoxDecoration).boxShadow, lifted);
    await gesture.up();
    await tester.pumpAndSettle();

    final down = find.byKey(blockGripKey("talk", AxisDirection.down));
    expect(down, findsOneWidget);
    final gripBox = tester.widget<DecoratedBox>(
      find.descendant(of: down, matching: find.byType(DecoratedBox)).first,
    );
    expect((gripBox.decoration as BoxDecoration).boxShadow, grip);
  });

  testWidgets("TG6 a timed grid given the range its owner asks is ready "
      "where the store shows that range ready, or another once every day of "
      "that range is read, covers a failed read of another range with the "
      "loading state, and reads no day in a layout", (tester) async {
    const size = Size(300.0, 400.0);
    final source = ReadSource(<CalendarEntry<String>>[
      entryOf("talk", tuesday, 10 * 60, 11 * 60),
    ]);
    final store = CountingStore(source);
    addTearDown(store.dispose);
    store.show(DateTime(2026, 4, 13), DateTime(2026, 4, 26));
    store.show(monday, DateTime(2026, 4, 24));
    expect(store.status, CalendarLoadStatus.ready);
    final now = ValueNotifier<DateTime>(nineOClock());
    addTearDown(now.dispose);

    TimedGrid<String> grid(
      ({DateTime first, DateTime last})? range, {
      double minSlotHeight = defaultMinSlotHeight,
    }) {
      return TimedGrid<String>(
        store: store,
        firstDay: tuesday,
        dayCount: 1,
        selectedDay: tuesday,
        today: tuesday,
        now: now,
        onSelectDay: (day) {},
        onOpenEntry: (id) {},
        onCreate: (range) async {},
        minSlotHeight: minSlotHeight,
        storeRange: range,
        loadingBuilder: loadingText,
        failureBuilder: failureText,
      );
    }

    void expectShows({required bool block, String? cover}) {
      expect(blockFinder("talk"), block ? findsOneWidget : findsNothing);
      expect(
        find.text("loading"),
        cover == "loading" ? findsOneWidget : findsNothing,
      );
      expect(
        find.text("failed"),
        cover == "failed" ? findsOneWidget : findsNothing,
      );
    }

    final toMonday = (first: monday, last: DateTime(2026, 4, 27));
    final toFriday = (first: monday, last: DateTime(2026, 4, 24));
    final toSunday = (first: monday, last: DateTime(2026, 4, 26));

    // The shown range, April 20 to 24, holds April 21 and is ready, but
    // April 27 is not read.
    await pumpBoxed(tester, size, grid(toMonday));
    expectShows(block: false, cover: "loading");
    await tester.pumpWidget(boxed(size, grid(toFriday)));
    expectShows(block: true);
    await tester.pumpWidget(boxed(size, grid(toSunday)));
    expectShows(block: true);
    await tester.pumpWidget(boxed(size, grid(null)));
    expectShows(block: true);

    source.fails = true;
    store.show(DateTime(2026, 5, 4), DateTime(2026, 5, 10));
    await tester.pump();
    expect(store.status, CalendarLoadStatus.failed);
    await tester.pumpWidget(boxed(size, grid(toSunday)));
    expectShows(block: true);
    await tester.pumpWidget(boxed(size, grid(toMonday)));
    expectShows(block: false, cover: "loading");
    // Given none, the grid keeps the store's shown range's status, where
    // the read of its own day would draw the block.
    await tester.pumpWidget(boxed(size, grid(null)));
    expectShows(block: false, cover: "failed");

    await tester.pumpWidget(boxed(size, grid(toSunday)));
    expectShows(block: true);
    final viewport = viewportOf(tester);
    expect(viewport.rectOfCell(2, 1)!.height, defaultMinSlotHeight);
    store.isReadCalls = 0;
    await tester.pumpWidget(boxed(size, grid(toSunday, minSlotHeight: 24.0)));
    expect(viewport.rectOfCell(2, 1)!.height, 24.0);
    expect(store.isReadCalls, 0);
  });

  testWidgets("TG7 a store notify that moves the store off the grid's range "
      "clears the selection, though the selected entry covers the days the "
      "grid takes next", (tester) async {
    const size = Size(400.0, 800.0);
    final saturday = DateTime(2026, 4, 25);
    final sunday = DateTime(2026, 4, 26);
    final nextMonday = DateTime(2026, 4, 27);
    final nextSunday = DateTime(2026, 5, 3);
    final source = ReadSource(<CalendarEntry<String>>[
      entryOf("trip", saturday, 10 * 60, 11 * 60, dayCount: 4),
    ]);
    final store = CountingStore(source);
    addTearDown(store.dispose);
    // Both weeks read, the next one first.
    store.show(nextMonday, nextSunday);
    store.show(monday, sunday);
    final now = ValueNotifier<DateTime>(nineOClock());
    addTearDown(now.dispose);

    TimedGrid<String> grid(DateTime first) {
      return TimedGrid<String>(
        store: store,
        firstDay: first,
        dayCount: 7,
        selectedDay: first,
        today: tuesday,
        now: now,
        onSelectDay: (day) {},
        onOpenEntry: (id) {},
        onCreate: (range) async {},
        editable: true,
        storeRange: (first: first, last: addDays(first, 6)),
      );
    }

    await pumpBoxed(tester, size, grid(monday));
    await tester.pumpAndSettle();
    // Saturday 10:00 to Tuesday 11:00, in two blocks of each week.
    expect(blockFinder("trip"), findsNWidgets(2));
    final gesture = await tester.startGesture(
      tester.getCenter(blockFinder("trip", saturday)),
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(blockHandlesKey("trip")), findsNWidgets(2));

    // A chevron's step: the owner asks the store for the next week, which
    // notifies within the call, and builds the grid on it.
    store.show(nextMonday, nextSunday);
    await tester.pumpWidget(boxed(size, grid(nextMonday)));
    await tester.pumpAndSettle();
    expect(blockFinder("trip"), findsNWidgets(2));
    expect(find.byKey(blockHandlesKey("trip")), findsNothing);
  });

  testWidgets("TG8 a block dragged up past the grid's top paints nothing "
      "above the grid, in one day's grid and in seven days'", (tester) async {
    const size = Size(400.0, 600.0);
    const white = Color(0xFFFFFFFF);
    const screenKey = ValueKey<String>("screen");
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final now = ValueNotifier<DateTime>(nineOClock());
    addTearDown(now.dispose);

    /// The colours the last frame shows at [points].
    Future<List<Color>> pixelsAt(List<Offset> points) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(screenKey),
      );
      final colors = <Color>[];
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        for (final point in points) {
          final at = (point.dy.floor() * image.width + point.dx.floor()) * 4;
          colors.add(
            Color.fromARGB(
              bytes.getUint8(at + 3),
              bytes.getUint8(at),
              bytes.getUint8(at + 1),
              bytes.getUint8(at + 2),
            ),
          );
        }
        image.dispose();
      });
      return colors;
    }

    for (final dayCount in <int>[1, 7]) {
      final store = MemoryCalendarStore<String>(
        entries: <CalendarEntry<String>>[
          entryOf("talk", tuesday, 9 * 60, 12 * 60),
        ],
      );
      addTearDown(store.dispose);
      // The grid under a white box 150 px tall, as a view's is under its
      // header.
      await tester.pumpWidget(
        RepaintBoundary(
          key: screenKey,
          child: MaterialApp(
            home: ColoredBox(
              color: white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 150.0),
                  Expanded(
                    child: TimedGrid<String>(
                      key: ValueKey<int>(dayCount),
                      store: store,
                      firstDay: dayCount == 1 ? tuesday : monday,
                      dayCount: dayCount,
                      selectedDay: tuesday,
                      today: tuesday,
                      now: now,
                      onSelectDay: (day) {},
                      onOpenEntry: (id) {},
                      onCreate: (range) async {},
                      editable: true,
                      showsDayHeader: dayCount > 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final grid = tester.getRect(find.byType(TimedGrid<String>));
      final block = tester.getRect(blockFinder("talk"));
      final x = block.center.dx;
      final inside = Offset(x, grid.top + 5.0);
      final before = await pixelsAt(<Offset>[inside]);

      // Held 10 px above its bottom and moved up until its top is 60 px
      // above the grid's, which leaves the pointer over the hours.
      final gesture = await tester.startGesture(
        block.bottomCenter - const Offset(0.0, 10.0),
      );
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await gesture.moveBy(Offset(0.0, grid.top - 60.0 - block.top));
      await tester.pump();
      final lifted = tester.getRect(find.byKey(liftedBlockKey));
      // Setup sanity: the lifted block lies across the grid's top, and
      // paints where it lies inside the grid.
      expect(lifted.top, lessThan(grid.top - 50.0), reason: "$dayCount");
      expect(lifted.contains(inside), isTrue, reason: "$dayCount");
      final pixels = await pixelsAt(<Offset>[
        inside,
        Offset(x, grid.top - 1.0),
      ]);
      expect(pixels[0], isNot(before[0]), reason: "$dayCount");
      // TARGET. Above the grid the box stays white.
      expect(pixels[1], white, reason: "$dayCount");

      await gesture.up();
      await tester.pumpAndSettle();
    }
  });
}
