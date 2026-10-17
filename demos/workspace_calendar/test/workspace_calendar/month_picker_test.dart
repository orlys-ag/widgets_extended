/// The month picker the header's title opens: in place of the folded
/// card's strip in Agenda and Day, under the header in Week and Month.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workspace_calendar/workspace_calendar/day_cell.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/month_strip.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';
import 'package:workspace_calendar/workspace_calendar/week_strip.dart';

import 'calendar_harness.dart';

Finder monthCellFinder(int year, int month) {
  return find.byKey(monthStripMonthKey(DateTime(year, month)));
}

MonthCell monthCell(WidgetTester tester, int year, int month) {
  return tester.widget<MonthCell>(
    find.descendant(
      of: monthCellFinder(year, month),
      matching: find.byType(MonthCell),
    ),
  );
}

/// [count] months from [year]'s [month], one after another.
List<DateTime> months(int year, int month, int count) {
  return <DateTime>[for (var i = 0; i < count; i++) DateTime(year, month + i)];
}

/// The months whose cells' middles the picker shows, left to right. The
/// strip builds a few months past either edge as well.
List<DateTime> pickerMonths(WidgetTester tester) {
  final strip = tester.getRect(find.byType(MonthStrip));
  final cells = <({double left, DateTime month})>[];
  final found = find.descendant(
    of: find.byType(MonthStrip),
    matching: find.byType(MonthCell),
  );
  for (final element in found.evaluate()) {
    final box = element.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (strip.contains(rect.center)) {
      cells.add((left: rect.left, month: (element.widget as MonthCell).month));
    }
  }
  cells.sort((a, b) {
    return a.left.compareTo(b.left);
  });
  return <DateTime>[for (final cell in cells) cell.month];
}

/// The title's text while the picker shows, the year.
Finder pickerTitle(String year) {
  return find.descendant(
    of: find.byTooltip("Close the months"),
    matching: find.text(year),
  );
}

Future<void> openPicker(WidgetTester tester) async {
  await tester.tap(find.byTooltip("Pick a month"));
  await tester.pumpAndSettle();
}

Future<void> pickMonth(WidgetTester tester, int year, int month) async {
  await tester.tap(monthCellFinder(year, month));
  await tester.pump(harnessLatency);
  await tester.pumpAndSettle();
}

DayCell dayCell(WidgetTester tester, DateTime day) {
  return tester.widget<DayCell>(find.byKey(dayCellKey(day)));
}

void main() {
  testWidgets("P1 in Agenda the title folds the card to a strip of months "
      "around the selected one, which it fills, ringing today's, and names "
      "the year, whose chevrons step a year", (tester) async {
    await pumpCalendar(tester);
    await openPicker(tester);
    expect(find.byKey(dayCellKey(today)), findsNothing);
    expect(pickerMonths(tester), months(2026, 1, 7));
    expect(pickerTitle("2026"), findsOneWidget);
    expect(monthCell(tester, 2026, 4).isSelected, isTrue);
    expect(monthCell(tester, 2026, 4).isCurrent, isTrue);
    expect(monthCell(tester, 2026, 5).isSelected, isFalse);
    expect(monthCell(tester, 2026, 5).isCurrent, isFalse);

    await tester.tap(find.byTooltip("Next year"));
    await tester.pumpAndSettle();
    expect(pickerTitle("2027"), findsOneWidget);
    expect(pickerMonths(tester), months(2027, 1, 7));
    await tester.tap(find.byTooltip("Previous year"));
    await tester.pumpAndSettle();
    expect(pickerMonths(tester), months(2026, 1, 7));
  });

  testWidgets("P2 a month picked selects the selected day's day of it and "
      "unfolds the card on its month; the title tapped again closes the "
      "picker with no pick, the card unfolding as it was", (tester) async {
    await pumpCalendar(tester);
    await openPicker(tester);
    await pickMonth(tester, 2026, 6);
    expect(find.byType(MonthStrip), findsNothing);
    expect(find.text("Jun 2026"), findsOneWidget);
    expect(dayCell(tester, DateTime(2026, 6, 21)).isSelected, isTrue);

    await openPicker(tester);
    await tester.tap(find.byTooltip("Close the months"));
    await tester.pumpAndSettle();
    expect(find.byType(MonthStrip), findsNothing);
    expect(dayCell(tester, DateTime(2026, 6, 21)).isSelected, isTrue);
  });

  testWidgets("P3 a drag slides the picker month by month, the title "
      "naming the year of the month at its middle", (tester) async {
    await pumpCalendar(tester);
    await openPicker(tester);
    final strip = tester.getRect(find.byType(MonthStrip));
    final width = strip.width / monthStripCount;
    final gesture = await tester.startGesture(strip.center);
    await gesture.moveBy(const Offset(-20.0, 0.0));
    await tester.pump();
    for (var i = 0; i < 9; i++) {
      await gesture.moveBy(Offset(-width, 0.0));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    // April's nine months on, January 2027, at the middle.
    expect(pickerMonths(tester), months(2026, 10, 7));
    expect(pickerTitle("2027"), findsOneWidget);
  });

  testWidgets("P4 in Day the picker takes the folded strip's place, and a "
      "pick unfolds the card on its month", (tester) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Day");
    await openPicker(tester);
    expect(find.byType(MonthStrip), findsOneWidget);
    expect(find.byType(WeekStrip), findsNothing);
    await pickMonth(tester, 2026, 5);
    expect(gridDay(tester), DateTime(2026, 5, 21));
    expect(dayCell(tester, DateTime(2026, 5, 21)).isSelected, isTrue);
  });

  testWidgets("P5 in Week and Month the picker opens under the header, and "
      "a pick selects the selected day's day of its month", (tester) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Week");
    await openPicker(tester);
    expect(find.byType(MonthStrip), findsOneWidget);
    await pickMonth(tester, 2026, 7);
    expect(find.byType(MonthStrip), findsNothing);
    expect(find.byKey(dayHeaderKey(DateTime(2026, 7, 21))), findsOneWidget);

    await pickMode(tester, "Month");
    await openPicker(tester);
    expect(find.byType(MonthStrip), findsOneWidget);
    // The picker opens on July, the selected day's month.
    await pickMonth(tester, 2026, 9);
    expect(find.text("Sep 2026"), findsOneWidget);
  });

  testWidgets("P6 a change of view, or Today, closes the picker", (
    tester,
  ) async {
    await pumpCalendar(tester);
    await openPicker(tester);
    await pickMode(tester, "Week");
    expect(find.byType(MonthStrip), findsNothing);
    expect(find.byTooltip("Next week"), findsOneWidget);

    await openPicker(tester);
    await tester.tap(find.byTooltip("Today"));
    await tester.pumpAndSettle();
    expect(find.byType(MonthStrip), findsNothing);
  });

  testWidgets("P7 a second year step mid-slide carries the picker on, the "
      "title never naming a month it passes", (tester) async {
    await pumpCalendar(tester);
    await openPicker(tester);
    await tester.tap(find.byTooltip("Next year"));
    await tester.pump();
    await tester.pump();
    await tester.pump(harborMotionDuration ~/ 2);
    await tester.tap(find.byTooltip("Next year"));
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(harborMotionDuration ~/ 8);
      expect(pickerTitle("2028"), findsOneWidget);
    }
    await tester.pumpAndSettle();
    expect(pickerMonths(tester), months(2028, 1, 7));
  });

  testWidgets("P8 a pick whose day of the month falls on a hidden weekday "
      "selects the next shown day of that month", (tester) async {
    await pumpCalendar(tester);
    await openSettings(tester);
    flipWeekends(tester);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195.0, 20.0));
    await tester.pumpAndSettle();
    await openPicker(tester);
    // June 21 is a Sunday.
    await pickMonth(tester, 2026, 6);
    expect(dayCell(tester, DateTime(2026, 6, 22)).isSelected, isTrue);
  });
}
