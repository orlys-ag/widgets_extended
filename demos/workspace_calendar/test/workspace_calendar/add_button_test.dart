/// The add button floating over the calendar: in every view, in edit mode
/// and out of it, it opens the create flow on today in Agenda and on the
/// selected day in Day, Week and Month, after the current time on today,
/// and the calendar keeps its last week clear of it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/composition/calendar_header.dart'
    show calendarEditToggleKey;
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';

import 'calendar_harness.dart';

/// 11:07 on [today].
DateTime elevenOhSeven() {
  return DateTime(2026, 4, 21, 11, 7);
}

Finder addButton() {
  return find.byType(FloatingActionButton);
}

/// Picks Task in the create flow's type picker.
Future<void> pickTask(WidgetTester tester) async {
  expect(find.text("New item"), findsOneWidget);
  await tester.tap(find.text("Task").last);
  await tester.pumpAndSettle();
}

/// Taps the add button, picks Task and expects the form to open on [day]
/// from [start] to [end].
Future<void> expectCreateOn(
  WidgetTester tester,
  String day,
  String start,
  String end,
) async {
  await tester.tap(addButton());
  await tester.pumpAndSettle();
  await pickTask(tester);
  expectFormDays(day, 1);
  expect(dropdownShows("Start time", start), findsOneWidget);
  expect(dropdownShows("End time", end), findsOneWidget);
}

void main() {
  testWidgets("A1 the add button shows in every view, out of edit mode and "
      "in it", (tester) async {
    await pumpCalendar(tester, clock: elevenOhSeven);
    for (final mode in <String>["Agenda", "Day", "Week", "Month"]) {
      await pickMode(tester, mode);
      expect(addButton(), findsOneWidget, reason: mode);
    }
    await tester.tap(find.byKey(calendarEditToggleKey));
    await tester.pumpAndSettle();
    expect(addButton(), findsOneWidget);
  });

  testWidgets("A2 in Agenda, out of edit mode, the button creates on today "
      "at the first free slot after the current time, whatever day is "
      "selected", (tester) async {
    await pumpCalendar(tester, clock: elevenOhSeven);
    await tester.tap(find.byKey(dayCellKey(DateTime(2026, 4, 23))));
    await tester.pumpAndSettle();
    expect(calendarControllerOf(tester).selectedDay, DateTime(2026, 4, 23));
    // "Design new UX flow for Michael" holds today from 10:00 to 13:00.
    await expectCreateOn(tester, "2026-04-21", "13:00", "13:15");
  });

  testWidgets("A3 in Week the button creates on the selected day, from the "
      "start of its hours on a later day", (tester) async {
    await pumpCalendar(tester, clock: elevenOhSeven, editing: true);
    await pickMode(tester, "Week");
    await tester.tap(find.byKey(dayHeaderKey(DateTime(2026, 4, 24))));
    await tester.pumpAndSettle();
    await expectCreateOn(tester, "2026-04-24", "00:00", "00:15");
  });

  testWidgets("A4 in Month the button creates on the selected day a "
      "chevron moved to", (tester) async {
    await pumpCalendar(tester, clock: elevenOhSeven);
    await pickMode(tester, "Month");
    await tester.tap(find.byTooltip("Next month"));
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    expect(calendarControllerOf(tester).selectedDay, DateTime(2026, 5, 21));
    await expectCreateOn(tester, "2026-05-21", "00:00", "00:15");
  });

  testWidgets("A5 in Day on today the button creates after the current "
      "time", (tester) async {
    await pumpCalendar(tester, clock: elevenOhSeven);
    await pickMode(tester, "Day");
    await expectCreateOn(tester, "2026-04-21", "13:00", "13:15");
  });

  testWidgets("A6 Month's last week ends above the button, under a screen "
      "inset too", (tester) async {
    // A phone's home indicator, which the view reports in both.
    tester.view.padding = const FakeViewPadding(bottom: 34.0);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34.0);
    await pumpCalendar(tester, clock: elevenOhSeven);
    await pickMode(tester, "Month");
    final lastDay = CalendarMonthGrid.of(today).lastDay;
    final button = tester.getRect(addButton());
    final lastWeek = tester.getRect(find.byKey(monthDayKey(lastDay)));
    expect(lastWeek.bottom, lessThanOrEqualTo(button.top));
    expect(lastWeek.bottom, greaterThan(button.top - 16.0));
  });
}
