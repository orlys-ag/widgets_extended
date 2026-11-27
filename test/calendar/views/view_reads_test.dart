/// The views read their own days: a timed grid and a month board mounted
/// alone load the days they show after the frame, judge their loading and
/// failure states from those days, retry them, read them again on a new
/// zone's clock, and read again after the frame the days a change at the
/// source leaves stale.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/calendar/presentation/calendar_builders.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_data_source.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/store/caching_calendar_store.dart';
import 'package:widgets_extended/scheduling/store/calendar_store.dart';

import '../../scheduling/zones.dart';
import '../view_doubles.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);

/// April 2026, from March 30 to May 3.
final CalendarMonthGrid april = CalendarMonthGrid(2026, 4);

/// November 2026, from October 26 to December 6.
final CalendarMonthGrid november = CalendarMonthGrid(2026, 11);

/// An entry with the id [id], titled [title] or else [id], from [hour]
/// o'clock on [day] for an hour.
CalendarEntry<String> entryOn(
  String id,
  DateTime day,
  int hour, {
  String? title,
}) {
  return CalendarEntry<String>(
    id: id,
    start: DateTime(day.year, day.month, day.day, hour),
    end: DateTime(day.year, day.month, day.day, hour + 1),
    title: title ?? id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

/// The days of [read] as day numbers.
({int first, int last}) daysOf(({DateTime first, DateTime last}) read) {
  return (
    first: CalendarDates.dayNumber(read.first),
    last: CalendarDates.dayNumber(read.last),
  );
}

/// The day numbers of [first] to [last].
({int first, int last}) dayNumbers(DateTime first, DateTime last) {
  return (
    first: CalendarDates.dayNumber(first),
    last: CalendarDates.dayNumber(last),
  );
}

/// The days of each read [source] holds, as day numbers.
List<({int first, int last})> heldDays(HeldReads source) {
  return <({int first, int last})>[
    for (final read in source.held) dayNumbers(read.first, read.last),
  ];
}

/// Answers the reads [source] holds, in the order held, with those of
/// [entries] that have a part in each read's days, and takes them out.
void answerHeld(HeldReads source, List<CalendarEntry<String>> entries) {
  final held = List.of(source.held);
  source.held.clear();
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

/// Answers the reads [source] holds, and those their answers send, until
/// it holds none, as [answerHeld] does, settling after each.
Future<void> answerAll(
  WidgetTester tester,
  HeldReads source,
  List<CalendarEntry<String>> entries,
) async {
  while (source.held.isNotEmpty) {
    answerHeld(source, entries);
    await tester.pumpAndSettle();
  }
}

/// Lays the test out in a view 800 wide and 2000 tall, in which a grid
/// shows every slot of the day.
void useTallView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800.0, 2000.0);
  addTearDown(tester.view.reset);
}

/// [child] under a MaterialApp, with no calendar theme.
Widget app(Widget child) {
  return MaterialApp(home: child);
}

/// A clock at 09:00 on [today].
ValueNotifier<CalendarNow> clockOn(DateTime today) {
  return ValueNotifier<CalendarNow>(
    CalendarNow(
      time: DateTime(today.year, today.month, today.day, 9),
      today: today,
    ),
  );
}

/// A month board of [grid] over [store], its cover drawing [name]'s
/// "loading" and "failed", and handing its failure's retry to [onFailure].
MonthBoard<String> boardOf(
  CalendarStore<String> store,
  CalendarMonthGrid grid,
  ValueListenable<CalendarNow> now, {
  String name = "board",
  ValueChanged<CalendarFailureState>? onFailure,
}) {
  return MonthBoard<String>(
    store: store,
    grid: grid,
    layout: CalendarMonthLayout.showAll,
    selectedDay: CalendarDates.shownDayNear(
      DateTime(grid.year, grid.month),
      grid.weekdays,
    ),
    now: now,
    onSelectDay: (day) {},
    onOpenDay: (day) {},
    onCreateOnDay: null,
    onOpenEntry: (id) {},
    loadingBuilder: (context, state) {
      return Text("$name loading");
    },
    failureBuilder: (context, state) {
      onFailure?.call(state);
      return Text("$name failed");
    },
  );
}

/// A timed grid of the week from [firstDay] over [store], its cover
/// drawing [name]'s "loading" and "failed", and handing its failure's
/// retry to [onFailure].
TimedGrid<String> gridOf(
  CalendarStore<String> store,
  DateTime firstDay,
  ValueListenable<CalendarNow> now, {
  String name = "grid",
  ValueChanged<CalendarFailureState>? onFailure,
}) {
  return TimedGrid<String>(
    store: store,
    firstDay: firstDay,
    dayCount: DateTime.daysPerWeek,
    selectedDay: firstDay,
    now: now,
    onSelectDay: (day) {},
    onOpenEntry: (id) {},
    onCreate: (details) async {},
    loadingBuilder: (context, state) {
      return Text("$name loading");
    },
    failureBuilder: (context, state) {
      onFailure?.call(state);
      return Text("$name failed");
    },
  );
}

/// The chip of [id] in the week from [weekStart].
Finder chipOf(String id, DateTime weekStart) {
  return find.byKey(monthChipKey(monthSegmentKey(id, weekStart)));
}

/// The block of [id]'s piece on [day].
Finder blockOf(String id, DateTime day) {
  return find.byKey(blockKey(id, day));
}

void main() {
  testWidgets("VR2 a month board and a timed grid, each mounted alone over "
      "a caching store nothing has shown, read their own days after the "
      "first frame, and leave the loading cover for the entries its read "
      "answers", (tester) async {
    useTallView(tester);
    final now = clockOn(tuesday);
    addTearDown(now.dispose);
    final entries = <CalendarEntry<String>>[entryOn("a", tuesday, 10)];
    for (final board in <bool>[true, false]) {
      final source = HeldReads();
      final store = CachingCalendarStore<String>(dataSource: source);
      final days = board
          ? dayNumbers(april.firstDay, april.lastDay)
          : dayNumbers(monday, DateTime(2026, 4, 26));
      final shown = board ? chipOf("a", monday) : blockOf("a", tuesday);
      final name = board ? "board" : "grid";
      await tester.pumpWidget(
        app(board ? boardOf(store, april, now) : gridOf(store, monday, now)),
      );
      expect(find.text("$name loading"), findsOneWidget, reason: name);
      expect(heldDays(source), <({int first, int last})>[days], reason: name);
      await answerAll(tester, source, entries);
      expect(find.text("$name loading"), findsNothing, reason: name);
      expect(shown, findsOneWidget, reason: name);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    }
  });

  testWidgets("VR3 a month board and a timed grid over one store each "
      "leave their loading cover once their days answer, and a failed read "
      "of the grid's days fails its cover alone, whose retry reads them "
      "again", (tester) async {
    useTallView(tester);
    final now = clockOn(DateTime(2026, 11, 18));
    addTearDown(now.dispose);
    final december = DateTime(2026, 12, 7);
    final entries = <CalendarEntry<String>>[
      entryOn("a", DateTime(2026, 11, 18), 10),
      entryOn("b", DateTime(2026, 12, 8), 10),
    ];
    // Setup sanity: the board's grid ends the day before the grid's week.
    expect(
      dayNumbers(november.firstDay, november.lastDay),
      dayNumbers(DateTime(2026, 10, 26), DateTime(2026, 12, 6)),
    );
    CalendarFailureState? failure;
    Widget both(CalendarStore<String> store) {
      return app(
        Column(
          children: <Widget>[
            Expanded(child: boardOf(store, november, now)),
            Expanded(
              child: gridOf(
                store,
                december,
                now,
                onFailure: (state) {
                  failure = state;
                },
              ),
            ),
          ],
        ),
      );
    }

    final gridDays = dayNumbers(december, DateTime(2026, 12, 13));
    final source = HeldReads();
    final store = CachingCalendarStore<String>(dataSource: source);
    addTearDown(store.dispose);
    await tester.pumpWidget(both(store));
    expect(
      heldDays(source),
      unorderedEquals(<({int first, int last})>[
        dayNumbers(november.firstDay, november.lastDay),
        gridDays,
      ]),
    );
    await answerAll(tester, source, entries);
    expect(find.text("board loading"), findsNothing);
    expect(find.text("grid loading"), findsNothing);
    expect(chipOf("a", DateTime(2026, 11, 16)), findsOneWidget);
    expect(blockOf("b", DateTime(2026, 12, 8)), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    final failing = HeldReads();
    final second = CachingCalendarStore<String>(dataSource: failing);
    addTearDown(second.dispose);
    await tester.pumpWidget(both(second));
    expect(heldDays(failing), hasLength(2));
    final held = List.of(failing.held);
    failing.held.clear();
    for (final read in held) {
      if (daysOf((first: read.first, last: read.last)) == gridDays) {
        read.answer.completeError(StateError("The read failed."));
      } else {
        failing.held.add(read);
      }
    }
    await answerAll(tester, failing, entries);
    expect(find.text("grid failed"), findsOneWidget);
    expect(find.text("board failed"), findsNothing);
    expect(find.text("board loading"), findsNothing);
    expect(chipOf("a", DateTime(2026, 11, 16)), findsOneWidget);
    failure!.retry();
    expect(heldDays(failing), <({int first, int last})>[gridDays]);
    await answerAll(tester, failing, entries);
    expect(find.text("grid failed"), findsNothing);
    expect(find.text("grid loading"), findsNothing);
    expect(blockOf("b", DateTime(2026, 12, 8)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("VR5 a month board alone over a caching store shows its days' "
      "entries on a new zone's clock once the store's reads under it "
      "answer", (tester) async {
    useTallView(tester);
    final on = DateTime(2026, 4, 21);
    final behind = zoneApartFromDevice(on, -6);
    final ahead = zoneApartFromDevice(on, 6);
    final start = tz.TZDateTime(behind, 2026, 4, 21, 22);
    // The instants on the device's clock, as a data source gives them.
    final entry = CalendarEntry<String>(
      id: "a",
      start: DateTime.fromMillisecondsSinceEpoch(start.millisecondsSinceEpoch),
      end: DateTime.fromMillisecondsSinceEpoch(
        start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      ),
      title: "a",
      color: const Color(0xFF336699),
      payload: "a",
    );
    final source = HeldReads();
    final store = CachingCalendarStore<String>(
      dataSource: source,
      zone: behind,
    );
    addTearDown(store.dispose);
    final now = clockOn(on);
    addTearDown(now.dispose);
    await tester.pumpWidget(app(boardOf(store, april, now)));

    /// Answers every read held with the entry, which the store keeps on
    /// the reads whose days it has a part in.
    Future<void> answerEntry() async {
      while (source.held.isNotEmpty) {
        final held = List.of(source.held);
        source.held.clear();
        for (final read in held) {
          read.answer.complete(<CalendarEntry<String>>[entry]);
        }
        await tester.pumpAndSettle();
      }
    }

    bool chipOnDay(int day) {
      final chip = tester.getRect(chipOf("a", monday));
      final cell = tester.getRect(
        find.byKey(monthDayKey(DateTime(2026, 4, day))),
      );
      return chip.center.dx > cell.left && chip.center.dx < cell.right;
    }

    await answerEntry();
    expect(chipOf("a", monday), findsOneWidget);
    expect(chipOnDay(21), isTrue);
    store.zone = ahead;
    await answerEntry();
    expect(chipOf("a", monday), findsOneWidget);
    expect(chipOnDay(22), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("VR6 a month board and a timed grid each mounted alone ask "
      "for their days after the first frame, and again after the frame of "
      "a new zone that reads nothing", (tester) async {
    useTallView(tester);
    final now = clockOn(tuesday);
    addTearDown(now.dispose);
    for (final board in <bool>[true, false]) {
      final store = PhaseStore();
      final days = board
          ? dayNumbers(april.firstDay, april.lastDay)
          : dayNumbers(monday, DateTime(2026, 4, 26));
      await tester.pumpWidget(
        app(board ? boardOf(store, april, now) : gridOf(store, monday, now)),
      );
      expect(
        <({int first, int last})>[
          for (final read in store.reads) dayNumbers(read.$1, read.$2),
        ],
        <({int first, int last})>[days],
      );
      store.zone = zoneApartFromDevice(DateTime(2026, 4, 21), 6);
      expect(store.reads, hasLength(1));
      await tester.pump();
      expect(
        <({int first, int last})>[
          for (final read in store.reads) dayNumbers(read.$1, read.$2),
        ],
        <({int first, int last})>[days, days],
      );
      expect(store.prefetches.last, SchedulerPhase.postFrameCallbacks);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    }
  });

  testWidgets("VR7 a month board and a timed grid each mounted alone over a "
      "caching store showing other days read again after the frame a day "
      "they show that an invalidate, a change of days or a refresh "
      "changed", (tester) async {
    useTallView(tester);
    final now = clockOn(DateTime(2026, 11, 18));
    addTearDown(now.dispose);
    final day = DateTime(2026, 11, 18);
    final weekStart = DateTime(2026, 11, 16);
    for (final board in <bool>[true, false]) {
      final name = board ? "board" : "grid";
      final entries = <CalendarEntry<String>>[
        entryOn("a", day, 10, title: "first"),
      ];
      final source = HeldReads();
      final changes = StreamController<CalendarSourceChange<String>>(
        sync: true,
      );
      final store = CachingCalendarStore<String>(
        dataSource: source,
        changes: changes.stream,
      );
      store.show(DateTime(2026, 12, 7), DateTime(2026, 12, 13));
      answerHeld(source, entries);
      await tester.pumpWidget(
        app(
          board ? boardOf(store, november, now) : gridOf(store, weekStart, now),
        ),
      );
      await answerAll(tester, source, entries);
      final shown = board ? chipOf("a", weekStart) : blockOf("a", day);
      // Setup sanity: the view shows the entry and its title.
      expect(
        find.descendant(of: shown, matching: find.text("first")),
        findsOneWidget,
        reason: name,
      );
      final steps = <(String, void Function())>[
        (
          "second",
          () {
            store.invalidate(day, day);
          },
        ),
        (
          "third",
          () {
            changes.add(CalendarDaysChanged<String>(day, day));
          },
        ),
        (
          "fourth",
          () {
            unawaited(store.refresh());
          },
        ),
      ];
      for (final (title, change) in steps) {
        entries[0] = entryOn("a", day, 10, title: title);
        change();
        await tester.pump();
        expect(
          source.held.any((read) {
            return CalendarDates.dayNumber(read.first) <=
                    CalendarDates.dayNumber(day) &&
                CalendarDates.dayNumber(read.last) >=
                    CalendarDates.dayNumber(day);
          }),
          isTrue,
          reason: "$name, $title",
        );
        await answerAll(tester, source, entries);
        expect(
          find.descendant(of: shown, matching: find.text(title)),
          findsOneWidget,
          reason: "$name, $title",
        );
      }
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      unawaited(changes.close());
    }
  }, skip: true);
}
