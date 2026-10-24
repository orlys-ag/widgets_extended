/// Agenda's calendar card as a month strip: one month at a time, its own
/// days alone, slid across by a drag, a fling or the chevrons without
/// selecting, folding into a week of the month it shows and unfolding on
/// the month the week strip shows.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:widgets_extended/calendar/composition/calendar_card.dart';

import 'calendar_harness.dart';

Finder gridFinder() {
  return find.byKey(const ValueKey<String>("calendar-grid"));
}

Finder dayFinder(int year, int month, int day) {
  return find.byKey(dayCellKey(DateTime(year, month, day)));
}

Finder stripDayFinder(int year, int month, int day) {
  return find.byKey(weekStripDayKey(DateTime(year, month, day)));
}

/// Every [DayCell] showing [day], keyed or not.
Finder anyCellOf(DateTime day) {
  return find.byWidgetPredicate((widget) {
    return widget is DayCell && widget.day == day;
  });
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

double rowHeight(WidgetTester tester) {
  return stripCellHeight(tester.element(gridFinder()));
}

double gridHeight(WidgetTester tester) {
  return tester.getSize(gridFinder()).height;
}

/// The top left corner of the grid's cell at [row] and [col], seven
/// columns across the grid.
Offset cellTopLeft(WidgetTester tester, int row, int col) {
  final grid = tester.getRect(gridFinder());
  return grid.topLeft +
      Offset(col * grid.width / 7, row * rowHeight(tester));
}

/// The month and year the header names, "Apr 2026".
String headerTitle(WidgetTester tester) {
  final titles = tester.widgetList<Text>(
    find.byWidgetPredicate((widget) {
      return widget is Text &&
          RegExp(r"^[A-Z][a-z]{2} \d{4}$").hasMatch(widget.data ?? "");
    }),
  );
  return titles.single.data!;
}

bool isSelected(WidgetTester tester, int year, int month, int day) {
  return tester.widget<DayCell>(dayFinder(year, month, day)).isSelected;
}

void main() {
  testWidgets("CC1 the card shows its month's days alone, on blank cells "
      "before the first and after the last, and a tap on a blank cell "
      "selects nothing", (tester) async {
    await pumpCalendar(tester);
    final row = rowHeight(tester);

    expect(find.byType(DayCell), findsNWidgets(30));
    expect(dayFinder(2026, 3, 30), findsNothing);
    expect(dayFinder(2026, 5, 3), findsNothing);
    // April 2026 starts on a Wednesday and ends on a Thursday.
    expect(
      tester.getTopLeft(dayFinder(2026, 4, 1)),
      offsetMoreOrLessEquals(cellTopLeft(tester, 0, 2)),
    );
    expect(
      tester.getTopLeft(dayFinder(2026, 4, 30)),
      offsetMoreOrLessEquals(cellTopLeft(tester, 4, 3)),
    );
    expect(gridHeight(tester), 5 * row);

    await tester.tapAt(cellTopLeft(tester, 0, 0) + Offset(4.0, row / 2));
    await tester.pumpAndSettle();
    expect(find.text("Today, April 21"), findsOneWidget);
    expect(isSelected(tester, 2026, 4, 21), isTrue);
  });

  testWidgets("CC2 a drag across the card slides the month beside it in "
      "with the finger, the card's height between the two months', and a "
      "release rests on a whole month without selecting", (tester) async {
    await pumpCalendar(tester);
    final row = rowHeight(tester);
    final grid = tester.getRect(gridFinder());
    final restLeft = tester.getTopLeft(dayFinder(2026, 4, 21)).dx;

    final gesture = await tester.startGesture(grid.center);
    await gesture.moveBy(const Offset(30.0, 0.0));
    await gesture.moveBy(const Offset(60.0, 0.0));
    await tester.pump();
    final shift = tester.getTopLeft(dayFinder(2026, 4, 21)).dx - restLeft;
    // Setup sanity: the drag moved April right, short of half the width.
    expect(shift, inExclusiveRange(1.0, grid.width / 2));
    // March, six weeks, comes in from the left of April, five.
    expect(dayFinder(2026, 3, 31), findsOneWidget);
    expect(
      gridHeight(tester),
      moreOrLessEquals((5 + shift / grid.width) * row, epsilon: 0.01),
    );
    expect(headerTitle(tester), "Apr 2026");

    await gesture.moveBy(Offset(grid.width * 0.4, 0.0));
    await tester.pump();
    expect(headerTitle(tester), "Mar 2026");
    await gesture.up();
    await tester.pumpAndSettle();

    expect(headerTitle(tester), "Mar 2026");
    expect(gridHeight(tester), 6 * row);
    // March 2026 starts on a Sunday.
    expect(
      tester.getTopLeft(dayFinder(2026, 3, 1)),
      offsetMoreOrLessEquals(cellTopLeft(tester, 0, 6)),
    );
    expect(dayFinder(2026, 4, 21), findsNothing);
    expect(find.text("Today, April 21"), findsOneWidget);
  });

  testWidgets("CC3 a fast fling carries the card past several months, and "
      "a slow drag short of half a month rests where it started", (
    tester,
  ) async {
    await pumpCalendar(tester);
    final grid = tester.getRect(gridFinder());

    await tester.timedDrag(
      gridFinder(),
      Offset(-grid.width * 0.3, 0.0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(headerTitle(tester), "Apr 2026");
    expect(
      tester.getTopLeft(dayFinder(2026, 4, 1)),
      offsetMoreOrLessEquals(cellTopLeft(tester, 0, 2)),
    );

    await tester.fling(gridFinder(), const Offset(-120.0, 0.0), 6000.0);
    await tester.pumpAndSettle();
    final title = headerTitle(tester);
    expect(title, isNot(anyOf("Apr 2026", "May 2026")));
    // Resting on a whole month: its first shown day in the top row.
    final parts = title.split(" ");
    final shown = DateTime(
      int.parse(parts[1]),
      monthShortNames.indexOf(parts[0]) + 1,
    );
    final first = tester.getTopLeft(
      dayFinder(shown.year, shown.month, 1),
    );
    expect(first.dy, moreOrLessEquals(grid.top));
    expect(
      (first.dx - grid.left) / (grid.width / 7),
      moreOrLessEquals(weekdayColumn(shown).toDouble()),
    );
    expect(find.text("Today, April 21"), findsOneWidget);
  });

  testWidgets("CC4 the chevrons slide the card a month at a time without "
      "selecting", (tester) async {
    await pumpCalendar(tester);
    final row = rowHeight(tester);

    await tapAndSettle(tester, find.byTooltip("Next month"));
    expect(headerTitle(tester), "May 2026");
    expect(find.text("Today, April 21"), findsOneWidget);
    // May 2026 starts on a Friday: five weeks.
    expect(
      tester.getTopLeft(dayFinder(2026, 5, 1)),
      offsetMoreOrLessEquals(cellTopLeft(tester, 0, 4)),
    );
    expect(gridHeight(tester), 5 * row);
    expect(
      tester.widgetList<DayCell>(find.byType(DayCell)).where((cell) {
        return cell.isSelected;
      }),
      isEmpty,
    );

    await tapAndSettle(tester, find.byTooltip("Previous month"));
    await tapAndSettle(tester, find.byTooltip("Previous month"));
    expect(headerTitle(tester), "Mar 2026");
    expect(gridHeight(tester), 6 * row);
    expect(find.text("Today, April 21"), findsOneWidget);
    // The read of the month the card rests on.
    await tester.pump(harnessLatency);
  });

  testWidgets("CC5 Today brings the card back to today's month, and a tap "
      "on a day of a month slid to selects it", (tester) async {
    await pumpCalendar(tester);

    await tapAndSettle(tester, find.byTooltip("Next month"));
    await tapAndSettle(tester, find.byTooltip("Next month"));
    expect(headerTitle(tester), "Jun 2026");
    await tapToday(tester);
    await tester.pumpAndSettle();
    expect(headerTitle(tester), "Apr 2026");
    expect(
      tester.getTopLeft(dayFinder(2026, 4, 1)),
      offsetMoreOrLessEquals(cellTopLeft(tester, 0, 2)),
    );
    expect(isSelected(tester, 2026, 4, 21), isTrue);

    await tapAndSettle(tester, find.byTooltip("Next month"));
    await tapAndSettle(tester, dayFinder(2026, 5, 7));
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    expect(find.text("Thursday, May 7"), findsOneWidget);
    expect(isSelected(tester, 2026, 5, 7), isTrue);
    expect(headerTitle(tester), "May 2026");
  });

  testWidgets("CC6 the card folds into the week of the selected day where "
      "its month holds it, of today where it holds today, and otherwise "
      "its first week, selecting nothing", (tester) async {
    await pumpCalendar(tester);
    final tab = find.byKey(calendarPullTabKey);

    // May holds neither: its first week, April 27 to May 3.
    await tapAndSettle(tester, find.byTooltip("Next month"));
    await tapAndSettle(tester, tab);
    final grid = tester.getRect(gridFinder());
    expect(gridHeight(tester), rowHeight(tester));
    expect(
      tester.getTopLeft(stripDayFinder(2026, 4, 27)),
      offsetMoreOrLessEquals(grid.topLeft),
    );
    expect(headerTitle(tester), "May 2026");
    expect(find.text("Today, April 21"), findsOneWidget);

    // Unfolded on May again, May 7 selected, then back to April, which
    // holds today but not the selected day: today's week.
    await tapAndSettle(tester, tab);
    expect(headerTitle(tester), "May 2026");
    await tapAndSettle(tester, dayFinder(2026, 5, 7));
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.byTooltip("Previous month"));
    await tester.tap(tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // Mid-fold, today's week, April's fourth, rises to the top as the
    // month shrinks.
    final t = tester.widget<DayCell>(dayFinder(2026, 4, 20)).collapse.value;
    expect(t, inExclusiveRange(0.0, 1.0));
    expect(
      tester.getTopLeft(dayFinder(2026, 4, 20)).dy,
      moreOrLessEquals(
        tester.getRect(gridFinder()).top + 3 * rowHeight(tester) * (1 - t),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(stripDayFinder(2026, 4, 20)),
      offsetMoreOrLessEquals(tester.getRect(gridFinder()).topLeft),
    );
    expect(headerTitle(tester), "Apr 2026");
    expect(find.text("Thursday, May 7"), findsOneWidget);
  });

  testWidgets("CC7 the card unfolds on the month of the day at the middle "
      "of the week strip", (tester) async {
    await pumpCalendar(tester);
    final tab = find.byKey(calendarPullTabKey);

    await tapAndSettle(tester, tab);
    final width = tester.getRect(gridFinder()).width;
    // Two weeks on: May 4 to 10, whose middle day is May 7.
    await tester.drag(
      find.byType(WeekStrip<ItemPayload>),
      Offset(-2 * width - 20.0, 0.0),
    );
    await tester.pumpAndSettle();
    // Setup sanity: the strip left April.
    expect(headerTitle(tester), "May 2026");

    await tapAndSettle(tester, tab);
    expect(headerTitle(tester), "May 2026");
    expect(
      tester.getTopLeft(dayFinder(2026, 5, 1)),
      offsetMoreOrLessEquals(cellTopLeft(tester, 0, 4)),
    );
    expect(find.text("Today, April 21"), findsOneWidget);
  });

  testWidgets("CC8 the days of the months beside it fade into the blank "
      "cells of the week the card folds into", (tester) async {
    await pumpCalendar(tester);

    await tapAndSettle(tester, find.byTooltip("Next month"));
    expect(anyCellOf(DateTime(2026, 4, 27)), findsNothing);

    await tester.tap(find.byKey(calendarPullTabKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final cell = anyCellOf(DateTime(2026, 4, 27));
    expect(cell, findsOneWidget);
    final fade = tester.widget<Opacity>(
      find.ancestor(of: cell, matching: find.byType(Opacity)).first,
    );
    expect(fade.opacity, inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
  });

  testWidgets("CC9 an arrow key past the month's edge selects the day "
      "beyond it and slides the card to that day's month", (tester) async {
    await pumpCalendar(tester);

    await tapAndSettle(tester, dayFinder(2026, 4, 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text("Thursday, March 26"), findsOneWidget);
    expect(headerTitle(tester), "Mar 2026");
    expect(isSelected(tester, 2026, 3, 26), isTrue);
    expect(
      tester.getTopLeft(dayFinder(2026, 3, 1)),
      offsetMoreOrLessEquals(cellTopLeft(tester, 0, 6)),
    );
  });

  testWidgets("CC11 a fold that starts while the card lies between two "
      "months brings it at once to the nearer one, and folds that", (
    tester,
  ) async {
    await pumpCalendar(tester);
    final grid = tester.getRect(gridFinder());
    final restLeft = tester.getTopLeft(dayFinder(2026, 4, 1)).dx;

    final drag = await tester.startGesture(grid.center);
    await drag.moveBy(const Offset(-30.0, 0.0));
    await drag.moveBy(Offset(-grid.width * 0.3, 0.0));
    await tester.pump();
    // Setup sanity: April and May both show.
    expect(dayFinder(2026, 5, 1), findsOneWidget);
    expect(tester.getTopLeft(dayFinder(2026, 4, 1)).dx, lessThan(restLeft));

    await tester.tap(find.byKey(calendarPullTabKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(dayFinder(2026, 5, 1), findsNothing);
    expect(tester.getTopLeft(dayFinder(2026, 4, 1)).dx, restLeft);

    await drag.moveBy(const Offset(-60.0, 0.0));
    await drag.up();
    await tester.pumpAndSettle();
    expect(gridHeight(tester), rowHeight(tester));
    expect(
      tester.getTopLeft(stripDayFinder(2026, 4, 20)),
      offsetMoreOrLessEquals(tester.getRect(gridFinder()).topLeft),
    );
    expect(headerTitle(tester), "Apr 2026");
  });

  testWidgets("CC10 the card reads the month it comes to rest on, so its "
      "markers show without selecting", (tester) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    await createBeforePump(
      tester,
      api,
      taskJson("Planning", DateTime(2026, 6, 10), 600, 660),
    );
    await pumpCalendar(tester, api: api);

    await tapAndSettle(tester, find.byTooltip("Next month"));
    await tapAndSettle(tester, find.byTooltip("Next month"));
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    expect(find.text("Today, April 21"), findsOneWidget);
    expect(tester.widget<DayCell>(dayFinder(2026, 6, 10)).hasEntries, isTrue);
    expect(tester.widget<DayCell>(dayFinder(2026, 6, 11)).hasEntries, isFalse);
  });
}
