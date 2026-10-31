/// The day list, the week strip and the month strip read the days they
/// show once a scroll of theirs ends: after the frame, never during the
/// layout a scroll can end in, and with a frame asked for where the
/// scroll ends outside one.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/policy/edit_policy.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/month_strip.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';

final DateTime tuesday = DateTime(2026, 4, 21);

/// A store with no entries that records the scheduler's phase at each
/// prefetch, and the days it reads.
final class PhaseStore extends MemoryCalendarStore<String> {
  final List<SchedulerPhase> prefetches = <SchedulerPhase>[];
  final List<(DateTime, DateTime)> reads = <(DateTime, DateTime)>[];

  @override
  void prefetch(DateTime first, DateTime last) {
    prefetches.add(SchedulerBinding.instance.schedulerPhase);
    reads.add((first, last));
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
      onCreateRange: (range) {},
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
}
