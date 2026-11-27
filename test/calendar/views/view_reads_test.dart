/// The views read their own days through a reader: they show the entries
/// a reader that is no store keeps; a timed grid and a month board mounted
/// alone load the days they show after the frame, judge their loading and
/// failure states from those days, retry them, read them again on a new
/// zone's clock or a new reader; and every view that asks for its days
/// reads again after the frame the days a change at the source leaves
/// stale.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/calendar/presentation/calendar_builders.dart';
import 'package:widgets_extended/calendar/presentation/calendar_day_badges.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/month_strip.dart';
import 'package:widgets_extended/calendar/views/pinch_zoom.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_data_source.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/store/caching_calendar_store.dart';
import 'package:widgets_extended/scheduling/store/calendar_store.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

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
  CalendarEntryReader<String> store,
  CalendarMonthGrid grid,
  ValueListenable<CalendarNow> now, {
  String name = "board",
  ValueChanged<CalendarFailureState>? onFailure,
  double weekScale = 1.0,
}) {
  return MonthBoard<String>(
    store: store,
    grid: grid,
    layout: CalendarMonthLayout.showAll,
    weekScale: weekScale,
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
  CalendarEntryReader<String> store,
  DateTime firstDay,
  ValueListenable<CalendarNow> now, {
  String name = "grid",
  ValueChanged<CalendarFailureState>? onFailure,
  double minSlotHeight = defaultMinSlotHeight,
}) {
  return TimedGrid<String>(
    store: store,
    onMoveRequest: (request) async {},
    minSlotHeight: minSlotHeight,
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

/// A day list opening on [day] over [store], out of edit mode, its
/// loading rows saying "loading".
DayList<String> listOf(
  CalendarEntryReader<String> store,
  DateTime day,
  ValueListenable<CalendarNow> now,
) {
  return DayList<String>(
    store: store,
    weekdays: CalendarWeekdaySet.all,
    format: CalendarHourLabelFormat.twentyFourHour,
    hours: CalendarDayHours.allDay,
    editable: false,
    selectedDay: day,
    now: now,
    onTopDay: (day) {},
    onCreateRange: (details) async {},
    onEdit: (id) {},
    onDelete: (id) {},
    loadingBuilder: (context, state) {
      return const Text("loading");
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

/// A caching store that counts the stale-days listeners registered with
/// it.
final class CountingStaleStore extends CachingCalendarStore<String> {
  CountingStaleStore(HeldReads source) : super(dataSource: source);

  int staleListeners = 0;

  @override
  void addStaleDaysListener(ValueChanged<CalendarStaleDays> listener) {
    staleListeners++;
    super.addStaleDaysListener(listener);
  }

  @override
  void removeStaleDaysListener(ValueChanged<CalendarStaleDays> listener) {
    staleListeners--;
    super.removeStaleDaysListener(listener);
  }
}

/// A [CountingStaleStore] over [source] showing 2026-12-07 to 2026-12-13,
/// whose read is answered with [entries].
CountingStaleStore staleStore(
  HeldReads source,
  List<CalendarEntry<String>> entries,
) {
  final store = CountingStaleStore(source);
  store.show(DateTime(2026, 12, 7), DateTime(2026, 12, 13));
  answerHeld(source, entries);
  return store;
}

void main() {
  testWidgets("VR1 the timed grid, the month board, the day list, the "
      "strips and a day cell read through a reader that is no store, and "
      "show the entries it keeps alone", (tester) async {
    useTallView(tester);
    final now = clockOn(tuesday);
    addTearDown(now.dispose);
    final wednesday = DateTime(2026, 4, 22);
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entryOn("a", tuesday, 10),
        entryOn("b", wednesday, 10),
      ],
    );
    addTearDown(store.dispose);
    final reader = ForwardingReader<String>(
      store,
      keep: (entry) {
        return entry.id == "a";
      },
    );

    await tester.pumpWidget(app(gridOf(reader, monday, now)));
    await tester.pumpAndSettle();
    expect(blockOf("a", tuesday), findsOneWidget);
    expect(blockOf("b", wednesday), findsNothing);

    await tester.pumpWidget(app(boardOf(reader, april, now)));
    await tester.pumpAndSettle();
    expect(chipOf("a", monday), findsOneWidget);
    expect(chipOf("b", monday), findsNothing);

    await tester.pumpWidget(app(listOf(reader, tuesday, now)));
    await tester.pumpAndSettle();
    // Setup sanity: the list builds Wednesday's rows.
    expect(
      find.byKey(dayListHeaderKey(wednesday), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(entryCardKey("a")), findsOneWidget);
    expect(find.byKey(entryCardKey("b"), skipOffstage: false), findsNothing);

    List<CalendarBadgeKind?> badgesOf(DateTime day) {
      return tester
          .widget<DayCell>(
            find.byWidgetPredicate((widget) {
              return widget is DayCell && widget.day == day && widget.inMonth;
            }),
          )
          .badges;
    }

    void expectBadges(String name) {
      expect(badgesOf(tuesday), <CalendarBadgeKind?>[null], reason: name);
      expect(badgesOf(wednesday), isEmpty, reason: name);
    }

    await tester.pumpWidget(
      app(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 350.0,
            child: WeekStrip<String>(
              store: reader,
              selectedDay: tuesday,
              today: tuesday,
              weekdays: CalendarWeekdaySet.all,
              onSelectDay: (day) {},
              onBrowse: (day) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectBadges("week strip");

    await tester.pumpWidget(
      app(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 350.0,
            child: MonthStrip<String>(
              store: reader,
              month: DateTime(2026, 4),
              selectedDay: tuesday,
              today: tuesday,
              weekdays: CalendarWeekdaySet.all,
              rowHeight: 48.0,
              collapse: kAlwaysDismissedAnimation,
              onSelectDay: (day) {},
              onBrowse: (day) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectBadges("month strip");

    await tester.pumpWidget(
      app(
        Row(
          children: <Widget>[
            for (final day in <DateTime>[tuesday, wednesday])
              SizedBox(
                width: 48.0,
                height: 48.0,
                child: DayMarkerListener<String>(
                  store: reader,
                  day: day,
                  builder: (context, badges) {
                    return DayCell(
                      day: day,
                      inMonth: true,
                      isSelected: false,
                      isToday: false,
                      badges: badges,
                      collapse: kAlwaysCompleteAnimation,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectBadges("day marker listener");
    await tester.pumpWidget(const SizedBox());
  });

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

  testWidgets("VR4 a month board and a timed grid over a reader that is no "
      "store ask it for their days after the frame of a new range or a new "
      "reader alone", (tester) async {
    useTallView(tester);
    final now = clockOn(tuesday);
    addTearDown(now.dispose);
    for (final board in <bool>[true, false]) {
      final name = board ? "board" : "grid";
      final store = CachingCalendarStore<String>(dataSource: HeldReads());
      final first = ForwardingReader<String>(store);
      final days = board
          ? dayNumbers(april.firstDay, april.lastDay)
          : dayNumbers(monday, DateTime(2026, 4, 26));
      final may = CalendarMonthGrid(2026, 5);
      final nextWeek = DateTime(2026, 4, 27);
      final next = board
          ? dayNumbers(may.firstDay, may.lastDay)
          : dayNumbers(nextWeek, DateTime(2026, 5, 3));
      Widget view(
        CalendarEntryReader<String> reader, {
        bool later = false,
        bool zoomed = false,
      }) {
        return app(
          board
              ? boardOf(
                  reader,
                  later ? may : april,
                  now,
                  weekScale: zoomed ? 1.5 : 1.0,
                )
              : gridOf(
                  reader,
                  later ? nextWeek : monday,
                  now,
                  minSlotHeight: zoomed ? 24.0 : defaultMinSlotHeight,
                ),
        );
      }

      List<({int first, int last})> prefetchesOf(
        ForwardingReader<String> reader,
      ) {
        return <({int first, int last})>[
          for (final ask in reader.asks)
            if (ask.member == "prefetch") dayNumbers(ask.first!, ask.last!),
        ];
      }

      await tester.pumpWidget(view(first));
      expect(prefetchesOf(first), <({int first, int last})>[
        days,
      ], reason: name);
      await tester.pumpWidget(view(first, zoomed: true));
      await tester.pump();
      expect(prefetchesOf(first), <({int first, int last})>[
        days,
      ], reason: "$name, zoomed");
      await tester.pumpWidget(view(first, later: true, zoomed: true));
      await tester.pump();
      expect(prefetchesOf(first), <({int first, int last})>[
        days,
        next,
      ], reason: "$name, later");
      final second = ForwardingReader<String>(store);
      await tester.pumpWidget(view(second, later: true, zoomed: true));
      await tester.pump();
      expect(prefetchesOf(second), <({int first, int last})>[
        next,
      ], reason: "$name, a new reader");
      expect(first.asks, hasLength(2), reason: "$name, the old reader");
      for (final ask
          in <
            ({
              String member,
              DateTime? first,
              DateTime? last,
              SchedulerPhase phase,
            })
          >[...first.asks, ...second.asks]) {
        expect(ask.member, "prefetch", reason: name);
        expect(ask.phase, SchedulerPhase.postFrameCallbacks, reason: name);
      }
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    }
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
  });

  testWidgets("VR8 a week strip mounted alone over a caching store showing "
      "other days reads again after the frame a day it shows that an "
      "invalidate changed, and badges its new entry", (tester) async {
    final day = DateTime(2026, 11, 18);
    final entries = <CalendarEntry<String>>[];
    final source = HeldReads();
    final store = staleStore(source, entries);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      app(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 350.0,
            child: WeekStrip<String>(
              store: store,
              selectedDay: day,
              today: day,
              weekdays: CalendarWeekdaySet.all,
              onSelectDay: (day) {},
              onBrowse: (day) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    store.prefetch(DateTime(2026, 11, 16), DateTime(2026, 11, 22));
    await answerAll(tester, source, entries);
    List<CalendarBadgeKind?> badgesOf(DateTime day) {
      return tester
          .widget<DayCell>(
            find.descendant(
              of: find.byKey(weekStripDayKey(day)),
              matching: find.byType(DayCell),
            ),
          )
          .badges;
    }

    // Setup sanity: the 18th is read and holds nothing.
    expect(store.isRead(day), isTrue);
    expect(badgesOf(day), isEmpty);
    entries.add(entryOn("a", day, 10));
    store.invalidate(day, day);
    expect(source.held, isEmpty);
    await tester.pump();
    expect(heldDays(source), <({int first, int last})>[dayNumbers(day, day)]);
    await answerAll(tester, source, entries);
    expect(badgesOf(day), <CalendarBadgeKind?>[null]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("VR9 a timed grid and a month board sharing stale days read "
      "each of them once after the frame, the grid, mounted first, asking "
      "first", (tester) async {
    useTallView(tester);
    final now = clockOn(DateTime(2026, 11, 18));
    addTearDown(now.dispose);
    final day = DateTime(2026, 11, 18);
    final weekStart = DateTime(2026, 11, 16);
    final entries = <CalendarEntry<String>>[entryOn("a", day, 10)];
    final source = HeldReads();
    final store = staleStore(source, entries);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      app(
        Column(
          children: <Widget>[
            Expanded(child: gridOf(store, weekStart, now)),
            Expanded(child: boardOf(store, november, now)),
          ],
        ),
      ),
    );
    await answerAll(tester, source, entries);

    store.invalidate(day, day);
    await tester.pump();
    expect(heldDays(source), <({int first, int last})>[dayNumbers(day, day)]);
    await answerAll(tester, source, entries);

    unawaited(store.refresh());
    // The refresh's own read, of the shown range.
    expect(heldDays(source), <({int first, int last})>[
      dayNumbers(DateTime(2026, 12, 7), DateTime(2026, 12, 13)),
    ]);
    await tester.pump();
    final asked = heldDays(source).skip(1).toList();
    // Setup sanity: the grid asked first.
    expect(asked.first, dayNumbers(weekStart, DateTime(2026, 11, 22)));
    final sorted = List.of(asked)
      ..sort((a, b) {
        return a.first.compareTo(b.first);
      });
    for (var index = 1; index < sorted.length; index++) {
      expect(
        sorted[index].first,
        sorted[index - 1].last + 1,
        reason: "the reads after the frame are disjoint and leave no gap",
      );
    }
    expect(sorted.first.first, CalendarDates.dayNumber(november.firstDay));
    expect(sorted.last.last, CalendarDates.dayNumber(november.lastDay));
    await answerAll(tester, source, entries);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("VR10 a day list's own read of its weeks at a scroll's end "
      "reads again the stale days its stale ask sent for", (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400.0, 800.0);
    addTearDown(tester.view.reset);
    final now = clockOn(tuesday);
    addTearDown(now.dispose);
    final thursday = DateTime(2026, 4, 23);
    final entries = <CalendarEntry<String>>[
      entryOn("a", tuesday, 10),
      entryOn("b", thursday, 10),
    ];
    final source = HeldReads();
    final store = CachingCalendarStore<String>(dataSource: source);
    addTearDown(store.dispose);
    await tester.pumpWidget(app(listOf(store, tuesday, now)));
    await answerAll(tester, source, entries);
    // Setup sanity: the list read the days, and nothing shows a range.
    expect(store.isRead(tuesday), isTrue);
    expect(store.isRead(thursday), isTrue);
    expect(store.isShown(tuesday, tuesday), isFalse);
    store.invalidate(tuesday, tuesday);
    store.invalidate(thursday, thursday);
    expect(source.held, isEmpty);
    await tester.drag(find.byType(DayList<String>), const Offset(0.0, -40.0));
    await tester.pumpAndSettle();
    final held = heldDays(source);
    expect(held, hasLength(3));
    expect(held[0], dayNumbers(tuesday, tuesday));
    expect(held[1], dayNumbers(thursday, thursday));
    expect(held[2].first, lessThanOrEqualTo(CalendarDates.dayNumber(tuesday)));
    expect(
      held[2].last,
      greaterThanOrEqualTo(CalendarDates.dayNumber(thursday)),
    );
    await answerAll(tester, source, entries);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("VR11 a view keeps the stale days it heard through a rebuild "
      "with the same store, hears only the store it is given, and hears "
      "none once unmounted", (tester) async {
    useTallView(tester);
    final now = clockOn(DateTime(2026, 11, 18));
    addTearDown(now.dispose);
    final day = DateTime(2026, 11, 18);
    final entries = <CalendarEntry<String>>[entryOn("a", day, 10)];
    final firstSource = HeldReads();
    final first = staleStore(firstSource, entries);
    addTearDown(first.dispose);
    final secondSource = HeldReads();
    final second = staleStore(secondSource, entries);
    addTearDown(second.dispose);
    Widget board(CountingStaleStore store, {double weekScale = 1.0}) {
      return app(boardOf(store, november, now, weekScale: weekScale));
    }

    await tester.pumpWidget(board(first));
    await answerAll(tester, firstSource, entries);
    expect(first.staleListeners, 1);

    // A rebuild with the same store between the report and its frame.
    first.invalidate(day, day);
    await tester.pumpWidget(board(first, weekScale: 1.5));
    expect(heldDays(firstSource), <({int first, int last})>[
      dayNumbers(day, day),
    ]);
    await answerAll(tester, firstSource, entries);

    // Another store: only its reports are heard.
    await tester.pumpWidget(board(second));
    await answerAll(tester, secondSource, entries);
    first.invalidate(day, day);
    await tester.pump();
    expect(firstSource.held, isEmpty);
    second.invalidate(day, day);
    await tester.pump();
    expect(heldDays(secondSource), <({int first, int last})>[
      dayNumbers(day, day),
    ]);
    await answerAll(tester, secondSource, entries);
    expect(first.staleListeners, 0);
    expect(second.staleListeners, 1);

    // Unmounted in the frame after a report: that frame reads nothing, a
    // later report schedules no frame, and no listener stays.
    second.invalidate(day, day);
    await tester.pumpWidget(const SizedBox());
    expect(secondSource.held, isEmpty);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    second.invalidate(day, day);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(second.staleListeners, 0);
  });
}
