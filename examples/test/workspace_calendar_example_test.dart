import 'package:examples/workspace_calendar/day_cell.dart';
import 'package:examples/workspace_calendar/task_card.dart';
import 'package:examples/workspace_calendar_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Tuesday. April 2026 starts on a Wednesday and has 30 days, so its
/// grid runs from March 29 to May 2 in five weeks.
final DateTime today = DateTime(2026, 4, 21);

Finder gridFinder() {
  return find.byKey(const ValueKey<String>("calendar-grid"));
}

Finder dayFinder(int year, int month, int day) {
  return find.byKey(dayCellKey(DateTime(year, month, day)));
}

Future<void> pumpCalendar(
  WidgetTester tester, {
  Size size = const Size(390.0, 844.0),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      // The M3 ink sparkle shader cannot load under the test binding.
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: WorkspaceCalendarExample(today: today),
    ),
  );
  await tester.pumpAndSettle();
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

void main() {
  testWidgets("opens on today's month with today's tasks", (tester) async {
    await pumpCalendar(tester);

    expect(find.text("April 2026"), findsOneWidget);
    expect(find.text("Month"), findsOneWidget);
    expect(find.text("Today, April 21"), findsOneWidget);
    expect(find.text("2 tasks"), findsOneWidget);
    expect(find.text("Design new UX flow for Michael"), findsOneWidget);
    expect(find.text("Brainstorm with the team"), findsOneWidget);

    expect(find.byType(DayCell), findsNWidgets(35));
    expect(dayFinder(2026, 3, 29), findsOneWidget);
    expect(dayFinder(2026, 5, 2), findsOneWidget);
    expect(gridHeight(tester), 5 * rowHeight(tester));

    final selected = tester.widget<DayCell>(dayFinder(2026, 4, 21));
    expect(selected.isSelected, isTrue);
    expect(selected.isToday, isTrue);
    expect(tester.widget<DayCell>(dayFinder(2026, 3, 31)).inMonth, isFalse);
    // Mock tasks sit at today + 6 and + 7, and none at today + 2.
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 27)).hasTasks, isTrue);
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 28)).hasTasks, isTrue);
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 23)).hasTasks, isFalse);
  });

  testWidgets("tapping a day selects it and lists its tasks", (tester) async {
    await pumpCalendar(tester);

    await tapAndSettle(tester, dayFinder(2026, 4, 27));
    expect(find.text("Monday, April 27"), findsOneWidget);
    expect(find.text("8 tasks"), findsOneWidget);
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 27)).isSelected, isTrue);
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 21)).isSelected, isFalse);

    await tapAndSettle(tester, dayFinder(2026, 4, 23));
    expect(find.text("Thursday, April 23"), findsOneWidget);
    expect(find.text("No tasks"), findsOneWidget);
    expect(find.text("No tasks on this day."), findsOneWidget);
    expect(find.byType(TaskCard), findsNothing);
  });

  testWidgets("tapping a muted day switches the grid to its month", (
    tester,
  ) async {
    await pumpCalendar(tester);

    await tapAndSettle(tester, dayFinder(2026, 3, 31));
    expect(find.text("March 2026"), findsOneWidget);
    expect(find.text("Tuesday, March 31"), findsOneWidget);
    // March 2026 starts on a Sunday and has 31 days: March 1 to April 4.
    expect(find.byType(DayCell), findsNWidgets(35));
    expect(dayFinder(2026, 3, 1), findsOneWidget);
    expect(dayFinder(2026, 4, 4), findsOneWidget);
    expect(dayFinder(2026, 4, 21), findsNothing);
    final cell = tester.widget<DayCell>(dayFinder(2026, 3, 31));
    expect(cell.isSelected, isTrue);
    expect(cell.inMonth, isTrue);
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 1)).inMonth, isFalse);
  });

  testWidgets("the chevrons step by month and keep the day of the month", (
    tester,
  ) async {
    await pumpCalendar(tester);

    await tapAndSettle(tester, find.byTooltip("Next month"));
    expect(find.text("May 2026"), findsOneWidget);
    expect(find.text("Thursday, May 21"), findsOneWidget);
    // May 2026 starts on a Friday and has 31 days: six weeks.
    expect(find.byType(DayCell), findsNWidgets(42));
    expect(gridHeight(tester), 6 * rowHeight(tester));

    for (var i = 0; i < 3; i++) {
      await tapAndSettle(tester, find.byTooltip("Previous month"));
    }
    expect(find.text("February 2026"), findsOneWidget);
    expect(find.text("Saturday, February 21"), findsOneWidget);
    // February 2026 starts on a Sunday and has 28 days: four weeks.
    expect(find.byType(DayCell), findsNWidgets(28));
    expect(gridHeight(tester), 4 * rowHeight(tester));

    // March 31 steps to April 30, the last day April has.
    await tapAndSettle(tester, find.byTooltip("Next month"));
    await tapAndSettle(tester, dayFinder(2026, 3, 31));
    await tapAndSettle(tester, find.byTooltip("Next month"));
    expect(find.text("Thursday, April 30"), findsOneWidget);
  });

  testWidgets(
    "scrolling the task list folds the month into the selected week and "
    "pulling it down unfolds it",
    (tester) async {
      await pumpCalendar(tester);
      final row = rowHeight(tester);

      await tester.drag(find.byType(TaskCard).first, const Offset(0.0, -120.0));
      await tester.pumpAndSettle();
      expect(gridHeight(tester), row);
      expect(find.text("Week"), findsOneWidget);
      expect(find.text("Month"), findsNothing);
      final grid = tester.getRect(gridFinder());
      expect(tester.getRect(dayFinder(2026, 4, 19)).top, grid.top);
      expect(tester.getRect(dayFinder(2026, 4, 25)).top, grid.top);
      expect(tester.getRect(dayFinder(2026, 4, 12)).bottom, grid.top);

      // The chevrons now step by week.
      await tapAndSettle(tester, find.byTooltip("Next week"));
      expect(find.text("Tuesday, April 28"), findsOneWidget);
      expect(tester.getRect(dayFinder(2026, 4, 26)).top, grid.top);

      await tester.drag(find.byType(TaskCard).first, const Offset(0.0, 120.0));
      await tester.pumpAndSettle();
      expect(gridHeight(tester), 5 * row);
      expect(find.text("Month"), findsOneWidget);
      // The weekday header is back above the grid, so its top moved down.
      expect(
        tester.getRect(dayFinder(2026, 3, 29)).top,
        tester.getRect(gridFinder()).top,
      );
    },
  );

  testWidgets("a long list folds the month as it scrolls", (tester) async {
    await pumpCalendar(tester);
    await tapAndSettle(tester, dayFinder(2026, 4, 27));

    await tester.drag(find.byType(TaskCard).first, const Offset(0.0, -60.0));
    await tester.pumpAndSettle();
    expect(gridHeight(tester), rowHeight(tester));
    // A pull that only scrolls back toward the top leaves the week; the
    // one that reaches past the top unfolds the month.
    await tester.drag(find.byType(TaskCard).first, const Offset(0.0, 20.0));
    await tester.pumpAndSettle();
    expect(gridHeight(tester), rowHeight(tester));
    await tester.drag(find.byType(TaskCard).first, const Offset(0.0, 200.0));
    await tester.pumpAndSettle();
    expect(gridHeight(tester), 5 * rowHeight(tester));
  });

  testWidgets(
    "the week view steps by week across months and stays folded when the "
    "list is pulled",
    (tester) async {
      await pumpCalendar(tester);
      final row = rowHeight(tester);

      await tapAndSettle(tester, find.text("Month"));
      await tapAndSettle(tester, find.text("Week").last);
      expect(gridHeight(tester), row);
      final grid = tester.getRect(gridFinder());

      for (var i = 0; i < 3; i++) {
        await tapAndSettle(tester, find.byTooltip("Previous week"));
      }
      // April 21 back three weeks is March 31, whose week starts on
      // March 29 and ends on April 4.
      expect(find.text("March 2026"), findsOneWidget);
      expect(find.text("Tuesday, March 31"), findsOneWidget);
      expect(tester.getRect(dayFinder(2026, 3, 29)).top, grid.top);
      expect(tester.getRect(dayFinder(2026, 4, 4)).top, grid.top);

      // A day of the next month in the same week keeps the week showing.
      await tapAndSettle(tester, dayFinder(2026, 4, 2));
      expect(find.text("April 2026"), findsOneWidget);
      expect(find.text("Thursday, April 2"), findsOneWidget);
      expect(tester.getRect(dayFinder(2026, 3, 29)).top, grid.top);
      expect(gridHeight(tester), row);

      await tester.drag(find.byType(ListView), const Offset(0.0, 120.0));
      await tester.pumpAndSettle();
      expect(gridHeight(tester), row);
      expect(find.text("Week"), findsOneWidget);

      await tapAndSettle(tester, find.text("Week"));
      await tapAndSettle(tester, find.text("Month").last);
      expect(gridHeight(tester), 5 * row);
    },
  );

  testWidgets("the arrow keys move the selection once the board has focus", (
    tester,
  ) async {
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

  testWidgets("the Board and Table views are placeholders", (tester) async {
    await pumpCalendar(tester);
    await tapAndSettle(tester, dayFinder(2026, 4, 27));

    await tapAndSettle(tester, find.text("Board"));
    expect(find.text("Board view is not available yet."), findsOneWidget);
    expect(find.byType(DayCell), findsNothing);
    expect(find.byTooltip("Add task"), findsNothing);

    await tapAndSettle(tester, find.text("Table"));
    expect(find.text("Table view is not available yet."), findsOneWidget);

    await tapAndSettle(tester, find.text("Calendar"));
    expect(find.text("Monday, April 27"), findsOneWidget);
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 27)).isSelected, isTrue);
  });

  testWidgets("the columns fit the width, before and after it changes", (
    tester,
  ) async {
    await pumpCalendar(tester);
    var grid = tester.getRect(gridFinder());
    expect(
      tester.getRect(dayFinder(2026, 4, 21)).width,
      moreOrLessEquals(grid.width / 7),
    );
    expect(
      tester.getRect(dayFinder(2026, 5, 2)).right,
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
      tester.getRect(dayFinder(2026, 5, 2)).right,
      moreOrLessEquals(grid.right),
    );
  });

  testWidgets("the longest month name fits a narrow phone", (tester) async {
    await pumpCalendar(tester, size: const Size(320.0, 640.0));

    for (var i = 0; i < 5; i++) {
      await tapAndSettle(tester, find.byTooltip("Next month"));
    }
    expect(find.text("September 2026"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("the unavailable actions say so", (tester) async {
    await pumpCalendar(tester);

    await tapAndSettle(tester, find.byTooltip("Add task"));
    expect(find.text("Adding tasks is not available yet."), findsOneWidget);
    await tapAndSettle(tester, find.byTooltip("Task actions").first);
    expect(find.text("Task actions are not available yet."), findsOneWidget);
  });
}
