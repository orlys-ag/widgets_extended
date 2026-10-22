/// The week strip of Day mode and of Agenda's folded month: the days it
/// shows and marks, a tap on it and a drag and a fling through it, the
/// reads it and Day mode make for it, how it follows the selected day, and
/// the month the header names for it.
library;

import 'dart:ui' show Tristate;

import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_api_source.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/day_list.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';
import 'package:workspace_calendar/workspace_calendar_example.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';

import 'calendar_harness.dart';

DateTime april(int day) {
  return DateTime(2026, 4, day);
}

DateTime may(int day) {
  return DateTime(2026, 5, day);
}

/// item-1 to item-4, in this order.
final List<Map<String, Object?>> seed = <Map<String, Object?>>[
  taskJson("Alpha", april(21), 9 * 60, 10 * 60),
  taskJson("Bravo", april(23), 14 * 60, 15 * 60),
  taskJson("Charlie", april(28), 9 * 60, 10 * 60),
  taskJson("Delta", may(5), 9 * 60, 10 * 60),
];

Finder stripDay(DateTime day) {
  return find.byKey(weekStripDayKey(day));
}

/// [count] days from [first], one after another.
List<DateTime> run(DateTime first, int count) {
  return <DateTime>[for (var i = 0; i < count; i++) addDays(first, i)];
}

/// The days whose cells' middles the strip shows, left to right. The strip
/// builds a few days past either edge as well.
List<DateTime> stripDays(WidgetTester tester) {
  final strip = tester.getRect(find.byType(WeekStrip<ItemPayload>));
  final cells = <({double left, DateTime day})>[];
  final found = find.descendant(
    of: find.byType(WeekStrip<ItemPayload>),
    matching: find.byType(DayCell),
  );
  for (final element in found.evaluate()) {
    final box = element.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (strip.contains(rect.center)) {
      cells.add((left: rect.left, day: (element.widget as DayCell).day));
    }
  }
  cells.sort((a, b) {
    return a.left.compareTo(b.left);
  });
  return <DateTime>[for (final cell in cells) cell.day];
}

/// The progress indicator the timed grid shows while its days load.
final Finder loadOverlay = find.descendant(
  of: find.byType(TimedGrid<ItemPayload>),
  matching: find.byType(CircularProgressIndicator),
);

DayCell stripCell(WidgetTester tester, DateTime day) {
  return tester.widget<DayCell>(
    find.descendant(of: stripDay(day), matching: find.byType(DayCell)),
  );
}

int listCalls(MockCalendarApi api) {
  return api.requests.where((request) {
    return request.method == CalendarMethod.list;
  }).length;
}

/// The calendar over [seed] in Day mode on [today].
Future<MockCalendarApi> pumpDay(WidgetTester tester) async {
  final api = MockCalendarApi(seed: seed, latency: harnessLatency);
  await pumpCalendar(tester, api: api);
  await pickMode(tester, "Day");
  return api;
}

/// Moves [gesture], down on the strip, [days] days' width towards later
/// days, or earlier ones for a negative [days], over four frames, after a
/// move just past the touch slop, which only starts the drag.
Future<void> moveStrip(
  WidgetTester tester,
  TestGesture gesture,
  int days,
) async {
  final strip = tester.getRect(find.byType(WeekStrip<ItemPayload>));
  final width = strip.width / stripDays(tester).length;
  await gesture.moveBy(Offset(-days.sign * (kTouchSlop + 1.0), 0.0));
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await gesture.moveBy(Offset(-days * width / 4, 0.0));
    await tester.pump();
  }
}

/// Drags the strip [days] days' width, as [moveStrip] does, and holds
/// still before the release, so it carries no fling; then lets the strip
/// rest.
Future<void> slideStrip(WidgetTester tester, int days) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(WeekStrip<ItemPayload>)),
  );
  await moveStrip(tester, gesture, days);
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("WS1 the strip shows the selected day's week and marks the "
      "selected day, today and the days with items", (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpDay(tester);

    expect(stripDays(tester), run(april(20), 7));
    expect(stripCell(tester, april(21)).isSelected, isTrue);
    expect(stripCell(tester, april(22)).isSelected, isFalse);
    expect(stripCell(tester, april(21)).isToday, isTrue);
    expect(stripCell(tester, april(23)).isToday, isFalse);
    expect(stripCell(tester, april(21)).hasItems, isTrue);
    expect(stripCell(tester, april(23)).hasItems, isTrue);
    expect(stripCell(tester, april(22)).hasItems, isFalse);

    final node = tester.getSemantics(stripDay(april(23)));
    expect(node.label, "Thursday, April 23, has items");
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.flagsCollection.isSelected, Tristate.isFalse);
    tester.semantics.tap(
      find.semantics.byLabel("Thursday, April 23, has items"),
    );
    await tester.pumpAndSettle();
    expect(gridDay(tester), april(23));
    semantics.dispose();
  });

  testWidgets("WS2 a tap on a strip day shows that day in the same frame", (
    tester,
  ) async {
    await pumpDay(tester);

    await tester.tap(stripDay(april(23)));
    await tester.pump();
    expect(gridDay(tester), april(23));
    expect(loadOverlay, findsNothing);
    expect(blockFinder("item-1"), findsNothing);
    expect(blockFinder("item-2"), findsOneWidget);
    expect(stripCell(tester, april(23)).isSelected, isTrue);
    expect(stripCell(tester, april(21)).isSelected, isFalse);
  });

  testWidgets("WS3 a drag slides the strip day by day, across weeks, and "
      "selects nothing; at rest the strip reads the weeks of the days it "
      "shows, and a tap on one of them shows that day at once", (tester) async {
    final api = await pumpDay(tester);
    final lists = listCalls(api);

    await slideStrip(tester, 3);
    expect(stripDays(tester), run(april(23), 7));
    expect(gridDay(tester), today);
    expect(stripCell(tester, april(28)).isSelected, isFalse);
    // April's grid, which the first read covered, runs to May 3, so the
    // marker shows with no read.
    expect(stripCell(tester, april(28)).hasItems, isTrue);
    expect(listCalls(api), lists);

    // April 30 to May 6: the week of May 4 is not read yet, and is read
    // whole, and its markers show once it answers.
    await slideStrip(tester, 7);
    expect(stripDays(tester), run(april(30), 7));
    expect(listCalls(api), lists + 1);
    final read = api.requests.last;
    expect((read.first, read.last), (may(4), may(10)));
    await tester.pump(harnessLatency);
    expect(stripCell(tester, may(5)).hasItems, isTrue);
    expect(stripCell(tester, may(6)).hasItems, isFalse);

    // Day reads May 5's whole week, which the strip has read, so a tap on
    // May 5 shows it at once, and the strip stays where it is.
    await tester.tap(stripDay(may(5)));
    await tester.pump();
    expect(gridDay(tester), may(5));
    expect(loadOverlay, findsNothing);
    expect(listCalls(api), lists + 1);
    await tester.pumpAndSettle();
    expect(stripCell(tester, may(5)).isSelected, isTrue);
    expect(stripDays(tester), run(april(30), 7));
  });

  testWidgets("WS4 a step past the days the strip shows slides it to the "
      "next week", (tester) async {
    await pumpDay(tester);
    await tester.tap(stripDay(april(26)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip("Next day"));
    await tester.pumpAndSettle();
    expect(stripDays(tester), run(april(27), 7));
    expect(stripCell(tester, april(27)).isSelected, isTrue);

    await tester.tap(find.byTooltip("Previous day"));
    // The frame that rebuilds the strip starts the slide after it; the
    // slide's first tick is the next frame.
    await tester.pump();
    await tester.pump();
    await tester.pump(harborMotionDuration ~/ 2);
    // Halfway through the slide both weeks show.
    expect(stripDays(tester), containsAll(<DateTime>[april(26), april(27)]));
    await tester.pumpAndSettle();
    expect(stripDays(tester), run(april(20), 7));
    expect(stripCell(tester, april(26)).isSelected, isTrue);
  });

  testWidgets("WS5 a selected day weeks away slides the strip there from a "
      "week short of it, and reports nothing, nor does a slide a new "
      "selected day stops", (tester) async {
    final store = CachingCalendarStore<ItemPayload>(
      dataSource: CalendarApiSource(MockCalendarApi(latency: harnessLatency)),
    );
    addTearDown(store.dispose);
    final reported = <DateTime>[];
    final browsed = <DateTime>[];
    var selected = today;
    late StateSetter setHost;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setHost = setState;
              return CalendarTheme(
                data: harborCalendarTheme,
                child: WeekStrip(
                  store: store,
                  selectedDay: selected,
                  today: today,
                  weekdays: WeekdaySet.all,
                  onSelectDay: (day) {
                    reported.add(day);
                    setState(() {
                      selected = day;
                    });
                  },
                  onBrowse: browsed.add,
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(stripDays(tester), run(april(20), 7));

    setHost(() {
      selected = may(19);
    });
    // The frame that rebuilds the strip, which jumps after it, then the
    // slide's first tick.
    await tester.pump();
    await tester.pump();
    expect(stripDays(tester), run(may(11), 7));
    await tester.pump(harborMotionDuration ~/ 2);
    expect(stripDays(tester), containsAll(<DateTime>[may(17), may(18)]));
    await tester.pumpAndSettle();
    expect(stripDays(tester), run(may(18), 7));
    expect(stripCell(tester, may(19)).isSelected, isTrue);

    setHost(() {
      selected = april(21);
    });
    await tester.pump();
    await tester.pump();
    await tester.pump(harborMotionDuration ~/ 2);
    setHost(() {
      selected = may(26);
    });
    await tester.pumpAndSettle();
    expect(stripDays(tester), run(may(25), 7));
    expect(reported, isEmpty);
    expect(browsed, isEmpty);
    // The read the strip asks for at rest.
    await tester.pump(harnessLatency);
  });

  testWidgets("WS6 with the weekends hidden the strip shows five weekdays "
      "and slides through the weekdays alone, and it and Day read only "
      "them", (tester) async {
    final api = await pumpDay(tester);
    await openBar(tester);
    flipWeekends(tester);
    await tester.pumpAndSettle();
    await closeBar(tester);
    expect(stripDays(tester), run(april(20), 5));

    final lists = listCalls(api);
    await slideStrip(tester, 2);
    expect(stripDays(tester), <DateTime>[
      april(22),
      april(23),
      april(24),
      april(27),
      april(28),
    ]);
    expect(listCalls(api), lists);

    await slideStrip(tester, 5);
    expect(stripDays(tester), <DateTime>[
      april(29),
      april(30),
      may(1),
      may(4),
      may(5),
    ]);
    expect(listCalls(api), lists + 1);
    final read = api.requests.last;
    expect((read.first, read.last), (may(4), may(8)));
    await tester.pump(harnessLatency);

    await tester.tap(stripDay(may(5)));
    await tester.pump();
    expect(gridDay(tester), may(5));
    expect(listCalls(api), lists + 1);
  });

  testWidgets("WS7 a step from the header brings a strip a drag moved back "
      "to the selected day's week", (tester) async {
    await pumpDay(tester);
    await slideStrip(tester, 7);
    expect(stripDays(tester), run(april(27), 7));

    await tester.tap(find.byTooltip("Next day"));
    await tester.pumpAndSettle();
    expect(gridDay(tester), april(22));
    expect(stripDays(tester), run(april(20), 7));
    expect(stripCell(tester, april(22)).isSelected, isTrue);
  });

  testWidgets("WS8 the header names the month of the day at the strip's "
      "middle from the moment a drag brings it there", (tester) async {
    await pumpDay(tester);

    // April 27 to May 3, whose middle is April 30.
    await slideStrip(tester, 7);
    expect(find.text("Apr 2026"), findsOneWidget);

    // Held a day further, before it rests, May 1 is at the middle.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(WeekStrip<ItemPayload>)),
    );
    await moveStrip(tester, gesture, 1);
    expect(find.text("May 2026"), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    // A step from the header to April 22 names its month again, and the
    // strip that follows it names nothing.
    await tester.tap(find.byTooltip("Next day"));
    await tester.pumpAndSettle();
    expect(find.text("Apr 2026"), findsOneWidget);

    // A tap on May 1, which a drag brings into view, selects it, and the
    // title follows.
    await slideStrip(tester, 7);
    await tester.tap(stripDay(may(1)));
    await tester.pumpAndSettle();
    expect(find.text("May 2026"), findsOneWidget);
  });

  testWidgets("WS9 a change of mode names the selected day's month again", (
    tester,
  ) async {
    await pumpDay(tester);
    await slideStrip(tester, 14);
    expect(find.text("May 2026"), findsOneWidget);

    await pickMode(tester, "Week");
    expect(find.text("Apr 2026"), findsOneWidget);
  });

  testWidgets("WS10 a fling carries the strip on past the drag and rests "
      "on a whole day", (tester) async {
    await pumpDay(tester);
    final strip = tester.getRect(find.byType(WeekStrip<ItemPayload>));
    final width = strip.width / 7;

    await tester.fling(
      find.byType(WeekStrip<ItemPayload>),
      Offset(-2 * width, 0.0),
      1500.0,
    );
    await tester.pumpAndSettle();
    final days = stripDays(tester);
    expect(daysBetween(april(20), days.first), greaterThan(2));
    expect(
      tester.getRect(stripDay(days.first)).left,
      moreOrLessEquals(strip.left),
    );
    // The read of the weeks it rests on.
    await tester.pump(harnessLatency);
  });

  testWidgets("WS11 a new width keeps the day at the strip's start", (
    tester,
  ) async {
    await pumpDay(tester);
    await slideStrip(tester, 3);
    expect(stripDays(tester), run(april(23), 7));

    tester.view.physicalSize = const Size(600.0, 844.0);
    await tester.pumpAndSettle();
    final strip = tester.getRect(find.byType(WeekStrip<ItemPayload>));
    expect(stripDays(tester), run(april(23), 7));
    expect(
      tester.getRect(stripDay(april(23))).left,
      moreOrLessEquals(strip.left),
    );
  });

  testWidgets("WS12 Agenda's folded month becomes the strip, which slides "
      "and selects as Day's does; unfolding shows the strip's month, and "
      "folding it again opens the strip on that month's first week", (
    tester,
  ) async {
    final api = MockCalendarApi(seed: seed, latency: harnessLatency);
    await pumpCalendar(tester, api: api);
    expect(find.byType(WeekStrip<ItemPayload>), findsNothing);

    await tester.drag(
      find.byType(DayList<ItemPayload>),
      const Offset(0.0, -120.0),
    );
    await tester.pumpAndSettle();
    final grid = tester.getRect(
      find.byKey(const ValueKey<String>("calendar-grid")),
    );
    expect(tester.getRect(find.byType(WeekStrip<ItemPayload>)), grid);
    expect(stripDays(tester), run(april(20), 7));

    // May 1 to May 7, whose middle is May 4.
    await slideStrip(tester, 11);
    expect(stripDays(tester), run(may(1), 7));
    expect(find.text("Today, April 21"), findsOneWidget);
    expect(find.text("May 2026"), findsOneWidget);

    await tester.drag(
      find.byType(WeekStrip<ItemPayload>),
      const Offset(0.0, 120.0),
    );
    await tester.pumpAndSettle();
    expect(find.text("May 2026"), findsOneWidget);
    expect(find.text("Today, April 21"), findsOneWidget);

    // Folded again by the pull tab, which selects nothing, May holding
    // neither the selected day nor today, the strip opens on May's first
    // week, and a tap on one of its days selects it.
    await tester.tap(find.byKey(calendarPullTabKey));
    await tester.pumpAndSettle();
    expect(stripDays(tester), run(april(27), 7));
    await tester.tap(stripDay(may(1)));
    await tester.pumpAndSettle();
    expect(find.text("Friday, May 1"), findsOneWidget);
    expect(stripCell(tester, may(1)).isSelected, isTrue);
  });

  testWidgets("WS13 a day's name sits above its number on a circle, the "
      "selected one's in the primary colour and the others' in the "
      "background grey, and a day with items wears a badge on the "
      "circle's top right corner", (tester) async {
    await pumpDay(tester);
    Finder inDay(DateTime day, Finder finder) {
      return find.descendant(of: stripDay(day), matching: finder);
    }

    Finder circleOf(DateTime day) {
      return inDay(day, find.byType(Container)).first;
    }

    Color? fillOf(DateTime day) {
      final circle = tester.widget<Container>(circleOf(day));
      return (circle.decoration as BoxDecoration?)?.color;
    }

    expect(
      tester.getRect(inDay(april(23), find.text("Thu"))).bottom,
      lessThanOrEqualTo(tester.getRect(inDay(april(23), find.text("23"))).top),
    );
    expect(fillOf(april(21)), HarborColors.primary);
    expect(fillOf(april(22)), HarborColors.background);
    expect(
      tester.getRect(find.byKey(dayBadgeKey(april(23)))).topRight,
      tester.getRect(circleOf(april(23))).topRight,
    );
    expect(find.byKey(dayBadgeKey(april(22))), findsNothing);
  });

  testWidgets("WS14 Today slides the strip back to the selected today from "
      "where a drag moved it, and to today from a day weeks away", (
    tester,
  ) async {
    await pumpDay(tester);
    await slideStrip(tester, 7);
    // Setup sanity: the strip shows the next week, today still selected.
    expect(stripDays(tester), run(april(27), 7));

    /// Taps Today, and checks halfway through the slide that the strip
    /// shows the last day of today's week and the first of the next.
    Future<void> slideToToday() async {
      await tapToday(tester);
      await tester.pump();
      await tester.pump();
      await tester.pump(harborMotionDuration ~/ 2);
      expect(stripDays(tester), containsAll(<DateTime>[april(26), april(27)]));
      await tester.pumpAndSettle();
      expect(stripDays(tester), run(april(20), 7));
    }

    await slideToToday();

    await slideStrip(tester, 21);
    await tester.tap(stripDay(may(13)));
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    // Setup sanity: May 13, three weeks on, is selected where it shows.
    expect(stripDays(tester), run(may(11), 7));
    expect(gridDay(tester), may(13));
    await slideToToday();
  });

  testWidgets("WS15 at 1.3 times the text size the strip is as tall as a "
      "day's name over its circle, and nothing overflows", (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = CachingCalendarStore<ItemPayload>(
      dataSource: CalendarApiSource(MockCalendarApi(latency: harnessLatency)),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              CalendarTheme(
                data: harborCalendarTheme,
                child: WeekStrip(
                  store: store,
                  selectedDay: april(21),
                  today: april(21),
                  weekdays: WeekdaySet.all,
                  onSelectDay: (day) {},
                  onBrowse: (day) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final name = find.descendant(
      of: stripDay(april(21)),
      matching: find.text("Tue"),
    );
    expect(
      tester.getSize(find.byType(WeekStrip<ItemPayload>)).height,
      moreOrLessEquals(
        tester.getSize(name).height + stripLabelGap + dayCircleSize,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets("WS16 at 1.3 times the text size Agenda's month folds, with "
      "nothing overflowing, to a row as tall as a strip day, which the "
      "strip fills", (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpCalendar(tester);
    await tester.tap(find.byKey(calendarPullTabKey));
    await tester.pumpAndSettle();
    // Setup sanity: the month folded into the strip.
    expect(find.byType(WeekStrip<ItemPayload>), findsOneWidget);
    final name = find.descendant(
      of: stripDay(april(21)),
      matching: find.text("Tue"),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>("calendar-grid")))
          .height,
      moreOrLessEquals(
        tester.getSize(name).height + stripLabelGap + dayCircleSize,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
