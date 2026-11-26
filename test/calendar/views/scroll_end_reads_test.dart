/// The day list, the week strip and the month strip read the days they
/// show once a scroll of theirs ends: after the frame, never during the
/// layout a scroll can end in, and with a frame asked for where the
/// scroll ends outside one. Given another store, each reads the days it
/// shows from that store, after the frame.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_data_source.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/store/caching_calendar_store.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/month_strip.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';

import '../view_doubles.dart';

final DateTime tuesday = DateTime(2026, 4, 21);

/// A data source whose reads never answer, which records the scheduler's
/// phase at each read, and the days it reads, so every day a store over it
/// shows stays loading.
final class UnansweredReads implements CalendarDataSource<String> {
  final List<SchedulerPhase> phases = <SchedulerPhase>[];
  final List<(DateTime, DateTime)> reads = <(DateTime, DateTime)>[];

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    phases.add(SchedulerBinding.instance.schedulerPhase);
    reads.add((first, last));
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

/// A scroll that runs until its scroll view takes new dimensions and then
/// goes idle, as a [BallisticScrollActivity] does in
/// [BallisticScrollActivity.applyNewDimensions] where the physics gives
/// it no new simulation, so it ends within the layout of those
/// dimensions.
class EndsOnNewDimensions extends ScrollActivity {
  EndsOnNewDimensions(super.delegate);

  @override
  bool get isScrolling {
    return true;
  }

  @override
  bool get shouldIgnorePointer {
    return false;
  }

  @override
  double get velocity {
    return 0.0;
  }

  @override
  void applyNewDimensions() {
    delegate.goIdle();
  }
}

/// The position of the one scroll view of [view].
ScrollPositionWithSingleContext positionOf(WidgetTester tester, Finder view) {
  final scrollable = tester.state<ScrollableState>(
    find.descendant(of: view, matching: find.byType(Scrollable)),
  );
  return scrollable.position as ScrollPositionWithSingleContext;
}

/// Pumps [view] at the top left, as wide as [width] holds and, where
/// given, as tall as [height] holds, and lets it settle.
Future<void> pumpSized(
  WidgetTester tester,
  Widget view, {
  required ValueNotifier<double> width,
  ValueNotifier<double>? height,
}) async {
  final sizes = Listenable.merge(<Listenable>[width, ?height]);
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: ListenableBuilder(
          listenable: sizes,
          builder: (context, child) {
            return SizedBox(
              width: width.value,
              height: height?.value,
              child: child,
            );
          },
          child: view,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Ends a scroll of [view] in the layout of a frame, that of [resize]'s
/// new size, and then outside any frame, and returns the phases of
/// [store]'s prefetches after the first and the days they read, and
/// whether a frame was asked for after the second.
Future<(List<SchedulerPhase>, List<(DateTime, DateTime)>, bool)> endScrolls(
  WidgetTester tester,
  PhaseStore store,
  Finder view,
  void Function() resize,
) async {
  store.prefetches.clear();
  store.reads.clear();
  final position = positionOf(tester, view);
  position.beginActivity(EndsOnNewDimensions(position));
  resize();
  await tester.pump();
  final inLayout = List<SchedulerPhase>.of(store.prefetches);
  final read = List<(DateTime, DateTime)>.of(store.reads);

  await tester.pumpAndSettle();
  position.beginActivity(EndsOnNewDimensions(position));
  position.goIdle();
  return (inLayout, read, tester.binding.hasScheduledFrame);
}

void main() {
  testWidgets("SE1 the day list reads the weeks of its rows after the frame "
      "whose layout ends its scroll, and asks for a frame for a scroll that "
      "ends outside one", (tester) async {
    final store = PhaseStore();
    addTearDown(store.dispose);
    final width = ValueNotifier<double>(400.0);
    addTearDown(width.dispose);
    final height = ValueNotifier<double>(600.0);
    addTearDown(height.dispose);
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: DateTime(2026, 4, 21, 9), today: tuesday),
    );
    addTearDown(now.dispose);
    final view = DayList<String>(
      store: store,
      weekdays: CalendarWeekdaySet.all,
      format: CalendarHourLabelFormat.twentyFourHour,
      hours: CalendarDayHours.allDay,
      editable: false,
      selectedDay: tuesday,
      now: now,
      onTopDay: (day) {},
      onCreateRange: (range) async {},
      onEdit: (id) {},
      onDelete: (id) {},
    );
    await pumpSized(tester, view, width: width, height: height);

    final (inLayout, _, asked) = await endScrolls(
      tester,
      store,
      find.byType(DayList<String>),
      () {
        height.value = 500.0;
      },
    );
    expect(inLayout, <SchedulerPhase>[SchedulerPhase.postFrameCallbacks]);
    expect(asked, isTrue);
  });

  testWidgets("SE2 the week strip reads the week it shows after the frame "
      "whose layout ends its scroll, and asks for a frame for a scroll that "
      "ends outside one", (tester) async {
    final store = PhaseStore();
    addTearDown(store.dispose);
    final width = ValueNotifier<double>(350.0);
    addTearDown(width.dispose);
    final view = WeekStrip<String>(
      store: store,
      selectedDay: tuesday,
      today: tuesday,
      weekdays: CalendarWeekdaySet.all,
      onSelectDay: (day) {},
      onBrowse: (day) {},
    );
    await pumpSized(tester, view, width: width);

    final (inLayout, read, asked) = await endScrolls(
      tester,
      store,
      find.byType(WeekStrip<String>),
      () {
        width.value = 420.0;
      },
    );
    expect(inLayout, <SchedulerPhase>[SchedulerPhase.postFrameCallbacks]);
    // Tuesday's week, from Monday.
    expect(read, <(DateTime, DateTime)>[
      (DateTime(2026, 4, 20), DateTime(2026, 4, 26)),
    ]);
    expect(asked, isTrue);
  });

  testWidgets("SE3 the month strip reads the month it rests on after the "
      "frame whose layout ends its scroll, and asks for a frame for a "
      "scroll that ends outside one", (tester) async {
    final store = PhaseStore();
    addTearDown(store.dispose);
    final width = ValueNotifier<double>(350.0);
    addTearDown(width.dispose);
    final view = MonthStrip<String>(
      store: store,
      month: DateTime(2026, 4),
      selectedDay: tuesday,
      today: tuesday,
      weekdays: CalendarWeekdaySet.all,
      rowHeight: 48.0,
      collapse: kAlwaysDismissedAnimation,
      onSelectDay: (day) {},
      onBrowse: (month) {},
    );
    await pumpSized(tester, view, width: width);

    final (inLayout, read, asked) = await endScrolls(
      tester,
      store,
      find.byType(MonthStrip<String>),
      () {
        width.value = 420.0;
      },
    );
    expect(inLayout, <SchedulerPhase>[SchedulerPhase.postFrameCallbacks]);
    // April's grid, from the Monday before its first day to the Sunday
    // after its last.
    expect(read, <(DateTime, DateTime)>[
      (DateTime(2026, 3, 30), DateTime(2026, 5, 3)),
    ]);
    expect(asked, isTrue);
  });

  testWidgets("SE4 given another store, the day list, the week strip and "
      "the month strip each read the days they show from it once, after the "
      "frame, though no row changes, every day loading on both stores", (
    tester,
  ) async {
    final now = ValueNotifier<CalendarNow>(
      CalendarNow(time: DateTime(2026, 4, 21, 9), today: tuesday),
    );
    addTearDown(now.dispose);
    final width = ValueNotifier<double>(400.0);
    addTearDown(width.dispose);
    final height = ValueNotifier<double>(600.0);
    addTearDown(height.dispose);
    final views = <String, Widget Function(CachingCalendarStore<String> store)>{
      "day list": (store) {
        return DayList<String>(
          store: store,
          weekdays: CalendarWeekdaySet.all,
          format: CalendarHourLabelFormat.twentyFourHour,
          hours: CalendarDayHours.allDay,
          editable: false,
          selectedDay: tuesday,
          now: now,
          onTopDay: (day) {},
          onCreateRange: (range) async {},
          onEdit: (id) {},
          onDelete: (id) {},
          loadingBuilder: (context, state) {
            return const SizedBox(height: 24.0);
          },
        );
      },
      "week strip": (store) {
        return WeekStrip<String>(
          store: store,
          selectedDay: tuesday,
          today: tuesday,
          weekdays: CalendarWeekdaySet.all,
          onSelectDay: (day) {},
          onBrowse: (day) {},
        );
      },
      "month strip": (store) {
        return MonthStrip<String>(
          store: store,
          month: DateTime(2026, 4),
          selectedDay: tuesday,
          today: tuesday,
          weekdays: CalendarWeekdaySet.all,
          rowHeight: 48.0,
          collapse: kAlwaysDismissedAnimation,
          onSelectDay: (day) {},
          onBrowse: (month) {},
        );
      },
    };
    final shows = <String, (DateTime, DateTime)>{
      // The weeks of the rows mounted.
      "day list": (DateTime(2026, 4, 13), DateTime(2026, 5, 3)),
      // Tuesday's week, from Monday.
      "week strip": (DateTime(2026, 4, 20), DateTime(2026, 4, 26)),
      // April's grid, from the Monday before its first day to the Sunday
      // after its last.
      "month strip": (DateTime(2026, 3, 30), DateTime(2026, 5, 3)),
    };
    for (final MapEntry(key: name, value: viewOf) in views.entries) {
      final store = CachingCalendarStore<String>(dataSource: UnansweredReads());
      addTearDown(store.dispose);
      final given = UnansweredReads();
      final next = CachingCalendarStore<String>(dataSource: given);
      addTearDown(next.dispose);
      await pumpSized(tester, viewOf(store), width: width, height: height);

      await pumpSized(tester, viewOf(next), width: width, height: height);
      expect(given.phases, <SchedulerPhase>[
        SchedulerPhase.postFrameCallbacks,
      ], reason: name);
      expect(given.reads, <(DateTime, DateTime)>[shows[name]!], reason: name);
      // Each view leaves the tree before the next is pumped.
      await tester.pumpWidget(const SizedBox());
    }
  });
}
