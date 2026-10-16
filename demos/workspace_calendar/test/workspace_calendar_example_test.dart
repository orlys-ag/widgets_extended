/// The calendar's Agenda mode: the Monday-first grid, the selection, the
/// chevrons, the fold into the selected week, the placeholders and the
/// day list's counts, over the seeded mock.
library;

import 'package:workspace_calendar/workspace_calendar/day_cell.dart';
import 'package:workspace_calendar/workspace_calendar/day_list.dart';
import 'package:workspace_calendar/workspace_calendar/item_card.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workspace_calendar/calendar_harness.dart';

Finder gridFinder() {
  return find.byKey(const ValueKey<String>("calendar-grid"));
}

Finder dayFinder(int year, int month, int day) {
  return find.byKey(dayCellKey(DateTime(year, month, day)));
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

double rowHeight(WidgetTester tester) {
  return tester.getSize(find.byType(DayCell).first).height;
}

double gridHeight(WidgetTester tester) {
  return tester.getSize(gridFinder()).height;
}

/// The letters of the weekday header, left to right.
List<String> weekdayHeaderLetters(WidgetTester tester) {
  final texts = tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(const ValueKey<String>("weekday-header")),
      matching: find.byType(Text),
    ),
  );
  return <String>[for (final text in texts) text.data!];
}

/// The short weekday names of the cells in the grid's top row, left to
/// right, as the folded strip shows them.
List<String> topRowShortNames(WidgetTester tester) {
  final top = tester.getRect(gridFinder()).top;
  final cells = <({double left, String name})>[];
  for (final element in find.byType(DayCell).evaluate()) {
    final cell = find.byWidget(element.widget);
    final rect = tester.getRect(cell);
    if (rect.top != top) {
      continue;
    }
    final texts = tester.widgetList<Text>(
      find.descendant(of: cell, matching: find.byType(Text)),
    );
    cells.add((left: rect.left, name: texts.last.data!));
  }
  cells.sort((a, b) {
    return a.left.compareTo(b.left);
  });
  return <String>[for (final cell in cells) cell.name];
}

bool hasMarker(WidgetTester tester, int month, int day) {
  return tester.widget<DayCell>(dayFinder(2026, month, day)).hasItems;
}

void main() {
  testWidgets("E1 opens on today's month with today's items", (tester) async {
    await pumpCalendar(tester);

    expect(find.text("April 2026"), findsOneWidget);
    expect(find.text("Agenda"), findsOneWidget);
    expect(find.text("Today, April 21"), findsOneWidget);
    expect(find.text("2 items"), findsOneWidget);
    expect(find.text("Design new UX flow for Michael"), findsOneWidget);
    expect(find.text("Brainstorm with the team"), findsOneWidget);

    expect(weekdayHeaderLetters(tester), <String>[
      "M",
      "T",
      "W",
      "T",
      "F",
      "S",
      "S",
    ]);
    expect(find.byType(DayCell), findsNWidgets(35));
    final grid = tester.getRect(gridFinder());
    expect(tester.getRect(dayFinder(2026, 3, 30)).topLeft, grid.topLeft);
    expect(dayFinder(2026, 3, 29), findsNothing);
    expect(
      tester.getRect(dayFinder(2026, 5, 3)).bottomRight,
      offsetMoreOrLessEquals(grid.bottomRight),
    );
    expect(gridHeight(tester), 5 * rowHeight(tester));

    final selected = tester.widget<DayCell>(dayFinder(2026, 4, 21));
    expect(selected.isSelected, isTrue);
    expect(selected.isToday, isTrue);
    expect(tester.widget<DayCell>(dayFinder(2026, 3, 31)).inMonth, isFalse);
    // Kept tasks sit at today + 6 and + 7, "Design critique" on Thursday,
    // and nothing on Saturday.
    expect(hasMarker(tester, 4, 27), isTrue);
    expect(hasMarker(tester, 4, 28), isTrue);
    expect(hasMarker(tester, 4, 23), isTrue);
    expect(hasMarker(tester, 4, 25), isFalse);
  });

  testWidgets("E2 tapping a day selects it and lists its items", (
    tester,
  ) async {
    await pumpCalendar(tester);

    await tapAndSettle(tester, dayFinder(2026, 4, 27));
    expect(find.text("Monday, April 27"), findsOneWidget);
    expect(find.text("8 items"), findsOneWidget);
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 27)).isSelected, isTrue);
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 21)).isSelected, isFalse);

    final semantics = tester.ensureSemantics();
    await tapAndSettle(tester, dayFinder(2026, 4, 25));
    expect(find.text("Saturday, April 25"), findsOneWidget);
    expect(find.text("No items"), findsOneWidget);
    expect(find.text("No items on this day."), findsOneWidget);
    expect(find.byType(ItemCard), findsNothing);
    expect(
      tester.getSemantics(dayFinder(2026, 4, 25)).label,
      startsWith("Saturday, April 25"),
    );
    semantics.dispose();
  });

  testWidgets("E3 tapping a muted day switches the grid to its month", (
    tester,
  ) async {
    await pumpCalendar(tester);

    await tapAndSettle(tester, dayFinder(2026, 3, 31));
    expect(find.text("March 2026"), findsOneWidget);
    expect(find.text("Tuesday, March 31"), findsOneWidget);
    // March 2026 starts on a Sunday and has 31 days: February 23 to
    // April 5, six weeks.
    expect(find.byType(DayCell), findsNWidgets(42));
    final grid = tester.getRect(gridFinder());
    expect(tester.getRect(dayFinder(2026, 2, 23)).topLeft, grid.topLeft);
    expect(
      tester.getRect(dayFinder(2026, 4, 5)).bottomRight,
      offsetMoreOrLessEquals(grid.bottomRight),
    );
    expect(dayFinder(2026, 4, 21), findsNothing);
    final cell = tester.widget<DayCell>(dayFinder(2026, 3, 31));
    expect(cell.isSelected, isTrue);
    expect(cell.inMonth, isTrue);
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 1)).inMonth, isFalse);
  });

  testWidgets("E4 the chevrons step by month and keep the day of the month", (
    tester,
  ) async {
    await pumpCalendar(tester);

    await tapAndSettle(tester, find.byTooltip("Next month"));
    expect(find.text("May 2026"), findsOneWidget);
    expect(find.text("Thursday, May 21"), findsOneWidget);
    // May 2026 starts on a Friday and has 31 days: April 27 to May 31,
    // five weeks.
    expect(find.byType(DayCell), findsNWidgets(35));
    expect(gridHeight(tester), 5 * rowHeight(tester));

    for (var i = 0; i < 3; i++) {
      await tapAndSettle(tester, find.byTooltip("Previous month"));
    }
    expect(find.text("February 2026"), findsOneWidget);
    expect(find.text("Saturday, February 21"), findsOneWidget);
    // February 2026 starts on a Sunday and has 28 days: January 26 to
    // March 1, five weeks.
    expect(find.byType(DayCell), findsNWidgets(35));
    expect(gridHeight(tester), 5 * rowHeight(tester));

    // March 31 steps to April 30, the last day April has.
    await tapAndSettle(tester, find.byTooltip("Next month"));
    await tapAndSettle(tester, dayFinder(2026, 3, 31));
    await tapAndSettle(tester, find.byTooltip("Next month"));
    expect(find.text("Thursday, April 30"), findsOneWidget);
  });

  testWidgets("E5 scrolling the list folds the month into the selected week "
      "and pulling it down unfolds it", (tester) async {
    const latency = Duration(seconds: 1);
    await pumpCalendar(
      tester,
      api: MockCalendarApi.seeded(today, latency: latency),
    );
    final row = rowHeight(tester);

    await tester.drag(find.byType(DayList), const Offset(0.0, -120.0));
    await tester.pumpAndSettle();
    expect(gridHeight(tester), row);
    expect(find.text("Agenda"), findsOneWidget);
    expect(find.text("Week"), findsNothing);
    final grid = tester.getRect(gridFinder());
    // The row shows April 20 to 26.
    expect(tester.getRect(dayFinder(2026, 4, 20)).topLeft, grid.topLeft);
    expect(
      tester.getRect(dayFinder(2026, 4, 26)).topRight,
      offsetMoreOrLessEquals(grid.topRight),
    );
    expect(tester.getRect(dayFinder(2026, 4, 19)).bottom, grid.top);
    expect(topRowShortNames(tester), <String>[
      "Mo",
      "Tu",
      "We",
      "Th",
      "Fr",
      "Sa",
      "Su",
    ]);

    // The chevrons now step by week.
    await tapAndSettle(tester, find.byTooltip("Next week"));
    expect(find.text("Tuesday, April 28"), findsOneWidget);
    expect(tester.getRect(dayFinder(2026, 4, 27)).topLeft, grid.topLeft);
    expect(
      tester.getRect(dayFinder(2026, 5, 3)).topRight,
      offsetMoreOrLessEquals(grid.topRight),
    );

    await tester.drag(find.byType(DayList), const Offset(0.0, 120.0));
    await tester.pumpAndSettle();
    expect(gridHeight(tester), 5 * row);
    expect(find.text("Agenda"), findsOneWidget);
    // The weekday header is back above the grid, so its top moved down.
    expect(
      tester.getRect(dayFinder(2026, 3, 30)).topLeft,
      tester.getRect(gridFinder()).topLeft,
    );

    // Folded again, the next week is May's, whose grid is not read: the
    // list shows its progress indicator, and pulling it still unfolds.
    await tester.drag(find.byType(DayList), const Offset(0.0, -120.0));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next week"));
    await tester.pump();
    expect(find.text("Tuesday, May 5"), findsOneWidget);
    final loading = find.byKey(const ValueKey<String>("day-list-loading"));
    expect(loading, findsOneWidget);
    await tester.drag(loading, const Offset(0.0, 120.0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(loading, findsOneWidget);
    expect(gridHeight(tester), 5 * row);
    expect(
      tester.getRect(dayFinder(2026, 4, 27)).topLeft,
      tester.getRect(gridFinder()).topLeft,
    );
    await tester.pump(latency);
    await tester.pumpAndSettle();
  });

  testWidgets("E6 a long list folds the month as it scrolls", (tester) async {
    await pumpCalendar(tester);
    await tapAndSettle(tester, dayFinder(2026, 4, 27));

    await tester.drag(find.byType(DayList), const Offset(0.0, -60.0));
    await tester.pumpAndSettle();
    expect(gridHeight(tester), rowHeight(tester));
    // A pull that only scrolls back toward the top leaves the week; the
    // one that reaches past the top unfolds the month.
    await tester.drag(find.byType(DayList), const Offset(0.0, 20.0));
    await tester.pumpAndSettle();
    expect(gridHeight(tester), rowHeight(tester));
    await tester.drag(find.byType(DayList), const Offset(0.0, 200.0));
    await tester.pumpAndSettle();
    expect(gridHeight(tester), 5 * rowHeight(tester));
  });

  testWidgets("E7 the arrow keys move the selection once the board has "
      "focus", (tester) async {
    await pumpCalendar(tester);

    await tapAndSettle(tester, dayFinder(2026, 4, 21));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text("Tomorrow, April 22"), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text("Wednesday, April 29"), findsOneWidget);
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 29)).isSelected, isTrue);
  });

  testWidgets("E8 the calendar has no Board or Table tabs", (tester) async {
    await pumpCalendar(tester);

    expect(find.text("Calendar"), findsNothing);
    expect(find.text("Board"), findsNothing);
    expect(find.text("Table"), findsNothing);
  });

  testWidgets("E9 the columns fit the width, before and after it changes", (
    tester,
  ) async {
    await pumpCalendar(tester);
    var grid = tester.getRect(gridFinder());
    expect(
      tester.getRect(dayFinder(2026, 4, 21)).width,
      moreOrLessEquals(grid.width / 7),
    );
    expect(
      tester.getRect(dayFinder(2026, 5, 3)).right,
      moreOrLessEquals(grid.right),
    );

    tester.view.physicalSize = const Size(600.0, 844.0);
    await tester.pumpAndSettle();
    grid = tester.getRect(gridFinder());
    expect(grid.width, greaterThan(500.0));
    expect(
      tester.getRect(dayFinder(2026, 4, 21)).width,
      moreOrLessEquals(grid.width / 7),
    );
    expect(
      tester.getRect(dayFinder(2026, 5, 3)).right,
      moreOrLessEquals(grid.right),
    );
  });

  testWidgets("E10 the longest month name fits a narrow phone", (tester) async {
    await pumpCalendar(tester, size: const Size(320.0, 640.0));

    for (var i = 0; i < 5; i++) {
      await tapAndSettle(tester, find.byTooltip("Next month"));
    }
    expect(find.text("September 2026"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("E11 More is not available", (tester) async {
    await pumpCalendar(tester);

    await tapAndSettle(tester, find.byTooltip("More"));
    expect(find.text("More options are not available yet."), findsOneWidget);
  });

  testWidgets("E12 the month folds and unfolds over 300 ms on "
      "fastOutSlowIn", (tester) async {
    await pumpCalendar(tester);
    final row = rowHeight(tester);
    final month = gridHeight(tester);

    /// The grid's height [elapsed] into a fold.
    double foldedAt(Duration elapsed) {
      final t = Curves.fastOutSlowIn.transform(elapsed.inMicroseconds / 300000);
      return month + (row - month) * t;
    }

    await tester.drag(find.byType(DayList), const Offset(0.0, -120.0));
    // The fold's clock starts on the first frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      gridHeight(tester),
      moreOrLessEquals(foldedAt(const Duration(milliseconds: 100))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      gridHeight(tester),
      moreOrLessEquals(foldedAt(const Duration(milliseconds: 200))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(gridHeight(tester), row);

    // Once the fold settles, the unfold runs the same curve back.
    await tester.pumpAndSettle();
    await tester.drag(find.byType(DayList), const Offset(0.0, 120.0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      gridHeight(tester),
      moreOrLessEquals(foldedAt(const Duration(milliseconds: 200))),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(gridHeight(tester), month);
  });
}
