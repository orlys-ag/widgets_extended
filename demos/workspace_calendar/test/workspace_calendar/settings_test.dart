/// The calendar's settings sheet and what it changes: the hours the timed
/// grids show and the model schedules in, and the least size of the
/// grids' cells.
library;

import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/day_cell.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/settings_sheet.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_harness.dart';

/// A size tall enough that the grid shows every row from 08:00 to 24:00.
const Size tall = Size(390.0, 1400.0);

/// Layout rounds track offsets, so geometry is compared to half a pixel.
Matcher near(double value) {
  return moreOrLessEquals(value, epsilon: 0.5);
}

/// The grid's row of [minute] under hours that start at 08:00.
int officeRow(int minute) {
  return 1 + (minute - 8 * 60) ~/ 15;
}

/// Stores [item] through [api] before the calendar is pumped and returns
/// its id.
Future<String> store(
  WidgetTester tester,
  MockCalendarApi api,
  Map<String, Object?> item,
) async {
  String? id;
  api.create(item).then((json) {
    id = json["id"]! as String;
  });
  await tester.pump(api.latency);
  return id!;
}

int updateCount(MockCalendarApi api) {
  return api.requests.where((request) {
    return request.method == CalendarMethod.update;
  }).length;
}

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip("Calendar settings"));
  await tester.pumpAndSettle();
}

/// Closes the sheet with a tap on the barrier above it.
Future<void> closeSettings(WidgetTester tester) async {
  await tester.tapAt(const Offset(195.0, 20.0));
  await tester.pumpAndSettle();
}

/// Moves the open sheet's hours slider to [start] to [end] o'clock
/// through its own callback.
Future<void> setHours(WidgetTester tester, int start, int end) async {
  tester.widget<RangeSlider>(find.byKey(hoursSliderKey)).onChanged!(
    RangeValues(start.toDouble(), end.toDouble()),
  );
  await tester.pumpAndSettle();
}

/// Moves the open sheet's slider [key] to [value] through its own
/// callback.
Future<void> setSlider(WidgetTester tester, Key key, double value) async {
  tester.widget<Slider>(find.byKey(key)).onChanged!(value);
  await tester.pumpAndSettle();
}

/// Opens the sheet, sets the hours to [start] to [end] o'clock and closes
/// it.
Future<void> pickHours(WidgetTester tester, int start, int end) async {
  await openSettings(tester);
  await setHours(tester, start, end);
  await closeSettings(tester);
}

Finder dropdownFinder(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) {
      return widget is DropdownButtonFormField;
    }),
  );
}

/// The minutes the form's [label] time field offers, in order.
List<int?> offeredMinutes(WidgetTester tester, String label) {
  final button = tester.widget<DropdownButton<int>>(
    find.descendant(
      of: dropdownFinder(label),
      matching: find.byType(DropdownButton<int>),
    ),
  );
  return <int?>[for (final item in button.items!) item.value];
}

Finder arrowIn(String id, IconData icon) {
  return find.descendant(of: blockFinder(id), matching: find.byIcon(icon));
}

/// Opens the sheet, flips the weekends switch with a tap and closes it.
Future<void> toggleWeekends(WidgetTester tester) async {
  await openSettings(tester);
  await tester.tap(find.byKey(weekendsSwitchKey));
  await tester.pumpAndSettle();
  await closeSettings(tester);
}

Finder dayFinder(int year, int month, int day) {
  return find.byKey(dayCellKey(DateTime(year, month, day)));
}

Finder headerFinder(DateTime day) {
  return find.byKey(dayHeaderKey(day));
}

Finder monthGridFinder() {
  return find.byKey(const ValueKey<String>("calendar-grid"));
}

/// The letters of the month's weekday header, left to right.
List<String> weekdayHeaderLetters(WidgetTester tester) {
  final texts = tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(const ValueKey<String>("weekday-header")),
      matching: find.byType(Text),
    ),
  );
  return <String>[for (final text in texts) text.data!];
}

void main() {
  testWidgets("H1 the settings button opens the sheet on the settings in "
      "force", (tester) async {
    await pumpCalendar(tester);
    await openSettings(tester);

    expect(find.text("Calendar settings"), findsOneWidget);
    expect(find.text("00:00 - 24:00"), findsOneWidget);
    expect(find.text("At least 44 px"), findsOneWidget);
    expect(find.text("At least 16 px per 15 minutes"), findsOneWidget);

    await setHours(tester, 8, 18);
    expect(find.text("08:00 - 18:00"), findsOneWidget);
    await closeSettings(tester);
    expect(find.text("Calendar settings"), findsNothing);
    await openSettings(tester);
    expect(find.text("08:00 - 18:00"), findsOneWidget);
  });

  testWidgets("H2 the hours trim the week grid to their slots", (tester) async {
    await pumpCalendar(tester, size: tall);
    await pickMode(tester, "Week");
    final grid = gridViewport(tester);
    expect(grid.rectOfCell(96, 1), isNotNull);

    await pickHours(tester, 8, 18);
    expect(grid.rectOfCell(40, 1), isNotNull);
    expect(grid.rectOfCell(41, 1), isNull);
    expect(find.text("09:00"), findsOneWidget);
    expect(find.text("17:00"), findsOneWidget);
    expect(find.text("07:00"), findsNothing);
    expect(find.text("18:00"), findsNothing);
    final block = tester.getRect(blockFinder(uxFlowId));
    final col = colOf(1);
    expect(block.top, near(cellRect(tester, officeRow(10 * 60), col).top));
    expect(
      block.bottom,
      near(cellRect(tester, officeRow(13 * 60) - 1, col).bottom),
    );
  });

  testWidgets("H3 an item reaching past the hours shows cut off, marked, "
      "and does not drag", (tester) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    final early = await store(
      tester,
      api,
      taskJson("Early", today, 7 * 60, 9 * 60),
    );
    final evening = await store(
      tester,
      api,
      taskJson("Evening", today, 17 * 60, 19 * 60),
    );
    await pumpCalendar(tester, api: api, size: tall);
    await pickMode(tester, "Week");
    await pickHours(tester, 8, 18);

    final col = colOf(1);
    final block = tester.getRect(blockFinder(early));
    expect(block.top, near(cellRect(tester, 1, col).top));
    expect(block.bottom, near(cellRect(tester, 4, col).bottom));
    expect(
      tester.getRect(blockFinder(evening)).bottom,
      near(cellRect(tester, 40, col).bottom),
    );
    expect(arrowIn(early, Icons.keyboard_arrow_up), findsOneWidget);
    expect(arrowIn(early, Icons.keyboard_arrow_down), findsNothing);
    expect(arrowIn(evening, Icons.keyboard_arrow_down), findsOneWidget);
    expect(arrowIn(evening, Icons.keyboard_arrow_up), findsNothing);
    expect(arrowIn(uxFlowId, Icons.keyboard_arrow_up), findsNothing);

    // Onto Wednesday's free 10:00 to 11:00, a drop the grid would admit.
    final updates = updateCount(api);
    await moveBlock(tester, blockFinder(early), cellRect(tester, 9, 3).topLeft);
    await tester.pumpAndSettle();
    expect(tester.getRect(blockFinder(early)), block);
    expect(updateCount(api), updates);
  });

  testWidgets("H4 an item wholly outside the hours has no block and the "
      "corner counts it", (tester) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    final lateId = await store(
      tester,
      api,
      taskJson("Late", today, 19 * 60, 20 * 60),
    );
    await pumpCalendar(tester, api: api, size: tall);
    await pickMode(tester, "Week");
    expect(blockFinder(lateId), findsOneWidget);
    expect(find.byKey(hiddenCountKey), findsNothing);

    await pickHours(tester, 8, 18);
    expect(blockFinder(lateId), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(hiddenCountKey),
        matching: find.text("+1"),
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip("1 item is outside the days or hours shown"),
      findsOneWidget,
    );
  });

  testWidgets("H5 a tap on the last slot creates up to the end of the "
      "hours", (tester) async {
    await pumpCalendar(tester, size: tall);
    await pickMode(tester, "Week");
    await pickHours(tester, 8, 18);

    await tester.tapAt(cellRect(tester, 40, colOf(3)).center);
    await tester.pumpAndSettle();
    expect(find.text("New item"), findsOneWidget);
    await tester.tap(find.text("Task").last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: dropdownFinder("Start"),
        matching: find.text("17:45"),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dropdownFinder("End"), matching: find.text("18:00")),
      findsOneWidget,
    );
  });

  testWidgets("H6 the form offers the hours' times and holds a change of "
      "days or times to them", (tester) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    final early = await store(
      tester,
      api,
      taskJson("Early", today, 7 * 60, 9 * 60),
    );
    await pumpCalendar(tester, api: api, size: tall);
    await pickMode(tester, "Week");
    await pickHours(tester, 8, 18);
    await tester.tap(blockFinder(early));
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsOneWidget);

    expect(offeredMinutes(tester, "Start"), <int>[
      7 * 60,
      for (var minute = 8 * 60; minute < 18 * 60; minute += 15) minute,
    ]);
    expect(offeredMinutes(tester, "End"), <int>[
      for (var minute = 8 * 60 + 15; minute <= 18 * 60; minute += 15) minute,
    ]);

    final updates = updateCount(api);
    await tester.enterText(find.widgetWithText(TextField, "Days"), "2");
    await tester.tap(find.widgetWithText(FilledButton, "Save"));
    await tester.pumpAndSettle();
    expect(
      find.text("The start is 08:00 to 17:45, inside the calendar's hours."),
      findsOneWidget,
    );
    expect(updateCount(api), updates);

    // Keeping the stored days and times, a new title saves.
    await tester.enterText(find.widgetWithText(TextField, "Days"), "1");
    await tester.enterText(find.widgetWithText(TextField, "Title"), "Earlier");
    await tester.tap(find.widgetWithText(FilledButton, "Save"));
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsNothing);
    expect(updateCount(api), updates + 1);
    expect(api.requests.last.body!["title"], "Earlier");
  });

  testWidgets("Z1 the day width and the slot height are least sizes", (
    tester,
  ) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Week");
    final grid = gridViewport(tester);
    final cell = cellRect(tester, rowOf(9 * 60), colOf(0));
    expect(cell.width, near((grid.size.width - 56.0) / 7));
    expect(cell.height, near(16.0));

    await openSettings(tester);
    await setSlider(tester, dayWidthSliderKey, 120.0);
    expect(find.text("At least 120 px"), findsOneWidget);
    await setSlider(tester, slotHeightSliderKey, 24.0);
    expect(find.text("At least 24 px per 15 minutes"), findsOneWidget);
    await closeSettings(tester);
    final larger = cellRect(tester, rowOf(9 * 60), colOf(0));
    expect(larger.width, near(120.0));
    expect(larger.height, near(24.0));
  });

  testWidgets("Z2 short hours stretch the slots to fill the grid", (
    tester,
  ) async {
    await pumpCalendar(tester, size: tall);
    await pickMode(tester, "Week");
    await pickHours(tester, 8, 18);

    final grid = gridViewport(tester);
    final bottom = grid.localToGlobal(Offset(0.0, grid.size.height)).dy;
    expect(cellRect(tester, 1, 1).height, near((grid.size.height - 40.0) / 40));
    expect(cellRect(tester, 40, 1).bottom, near(bottom));
  });

  testWidgets("Z3 a new slot height keeps the time at the top in place", (
    tester,
  ) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Week");
    final header = cellRect(tester, 0, 1).bottom;
    expect(cellRect(tester, rowOf(8 * 60), 1).top, near(header));

    await openSettings(tester);
    await setSlider(tester, slotHeightSliderKey, 32.0);
    await closeSettings(tester);
    expect(cellRect(tester, rowOf(8 * 60), 1).height, near(32.0));
    expect(cellRect(tester, rowOf(8 * 60), 1).top, near(header));
  });

  testWidgets("Z4 a grid opens at the hours' start when they begin after "
      "08:00", (tester) async {
    await pumpCalendar(tester);
    await openSettings(tester);
    await setHours(tester, 12, 24);
    await setSlider(tester, slotHeightSliderKey, 32.0);
    await closeSettings(tester);
    await pickMode(tester, "Week");

    final header = cellRect(tester, 0, 1).bottom;
    expect(cellRect(tester, 1, 1).height, near(32.0));
    expect(cellRect(tester, 1, 1).top, near(header));
  });

  testWidgets("H7 hours as long as the last relabel the gutter of a week "
      "with no items", (tester) async {
    // No item moves, so no item change rebuilds the board's cells.
    await pumpCalendar(
      tester,
      api: MockCalendarApi(latency: harnessLatency),
      size: tall,
    );
    await pickMode(tester, "Week");
    await pickHours(tester, 8, 18);
    expect(find.text("09:00"), findsOneWidget);

    await pickHours(tester, 9, 19);
    final grid = gridViewport(tester);
    expect(grid.rectOfCell(40, 1), isNotNull);
    expect(grid.rectOfCell(41, 1), isNull);
    expect(find.text("18:00"), findsOneWidget);
    expect(find.text("09:00"), findsNothing);
  });

  testWidgets("W1 hiding the weekends leaves the week's five weekdays", (
    tester,
  ) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    final saturday = DateTime(2026, 4, 25);
    final weekendId = await store(
      tester,
      api,
      taskJson("Weekend", saturday, 10 * 60, 11 * 60),
    );
    await pumpCalendar(tester, api: api);
    await pickMode(tester, "Week");
    expect(blockFinder(weekendId), findsOneWidget);

    await toggleWeekends(tester);
    final grid = gridViewport(tester);
    expect(headerFinder(DateTime(2026, 4, 24)), findsOneWidget);
    expect(headerFinder(saturday), findsNothing);
    expect(grid.rectOfCell(0, 5), isNotNull);
    expect(grid.rectOfCell(0, 6), isNull);
    expect(
      cellRect(tester, rowOf(9 * 60), 5).width,
      near((grid.size.width - 56.0) / 5),
    );
    expect(blockFinder(weekendId), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(hiddenCountKey),
        matching: find.text("+1"),
      ),
      findsOneWidget,
    );

    await toggleWeekends(tester);
    expect(headerFinder(saturday), findsOneWidget);
    expect(blockFinder(weekendId), findsOneWidget);
    expect(find.byKey(hiddenCountKey), findsNothing);
  });

  testWidgets("W2 hiding the weekends leaves the month's weekdays and the "
      "weeks holding them", (tester) async {
    await pumpCalendar(tester);
    await toggleWeekends(tester);

    expect(weekdayHeaderLetters(tester), <String>["M", "T", "W", "T", "F"]);
    expect(dayFinder(2026, 4, 25), findsNothing);
    final grid = tester.getRect(monthGridFinder());
    final friday = tester.getRect(dayFinder(2026, 4, 24));
    expect(friday.width, near(grid.width / 5));
    expect(friday.right, near(grid.right));

    // August 2026 starts on a Saturday, so its first week holds no
    // weekday of the month.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip("Next month"));
      await tester.pumpAndSettle();
    }
    expect(find.text("August 2026"), findsOneWidget);
    expect(dayFinder(2026, 7, 31), findsNothing);
    expect(dayFinder(2026, 8, 3), findsOneWidget);
    expect(tester.getRect(monthGridFinder()).height, near(5 * 48.0));
  });

  testWidgets("W3 hiding the weekends moves a selected Saturday to Monday", (
    tester,
  ) async {
    await pumpCalendar(tester);
    await tester.tap(dayFinder(2026, 4, 25));
    await tester.pumpAndSettle();
    expect(find.text("Saturday, April 25"), findsOneWidget);

    await toggleWeekends(tester);
    expect(find.text("Monday, April 27"), findsOneWidget);
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 27)).isSelected, isTrue);
  });

  testWidgets("W4 Day mode steps over the hidden weekend", (tester) async {
    await pumpCalendar(tester);
    await tester.tap(dayFinder(2026, 4, 24));
    await tester.pumpAndSettle();
    await toggleWeekends(tester);
    await pickMode(tester, "Day");
    expect(headerFinder(DateTime(2026, 4, 24)), findsOneWidget);

    await tester.tap(find.byTooltip("Next day"));
    await tester.pumpAndSettle();
    expect(headerFinder(DateTime(2026, 4, 27)), findsOneWidget);
    await tester.tap(find.byTooltip("Previous day"));
    await tester.pumpAndSettle();
    expect(headerFinder(DateTime(2026, 4, 24)), findsOneWidget);
  });

  testWidgets("W5 a month step onto a hidden day takes the nearest shown "
      "day of that month", (tester) async {
    await pumpCalendar(tester);
    await toggleWeekends(tester);
    await tester.tap(dayFinder(2026, 4, 30));
    await tester.pumpAndSettle();

    // May 30 2026 is a Saturday, and June 1 is in the next month.
    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    expect(find.text("Friday, May 29"), findsOneWidget);
  });
}
