/// The calendar's settings, in the calendar bar and the settings sheet,
/// and what they change: the hours the timed grids show and the store
/// schedules in, the weekdays, the slot length, and the least size of the
/// grids' cells.
library;

import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_bar.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_settings.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';

import 'calendar_harness.dart';

/// A size tall enough that the grid shows every row from 08:00 to 24:00.
const Size tall = Size(390.0, 1400.0);

/// Layout rounds track offsets, so geometry is compared to half a pixel.
Matcher near(double value) {
  return moreOrLessEquals(value, epsilon: 0.5);
}

/// Week's grid row of [minute] under hours that start at 08:00
/// ([gridRowOf]).
int officeRow(int minute) {
  return gridRowOf(minute);
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

/// Closes the sheet with a tap on the barrier above it.
Future<void> closeSettings(WidgetTester tester) async {
  await tester.tapAt(const Offset(195.0, 20.0));
  await tester.pumpAndSettle();
}

/// Moves the open calendar bar's hours slider to [start] to [end] o'clock
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

/// The open sheet's slot length buttons.
SegmentedButton<int> slotLengthButtons(WidgetTester tester) {
  return tester.widget<SegmentedButton<int>>(find.byKey(slotLengthKey));
}

/// Taps the open sheet's slot length button of [minutes].
Future<void> chooseSlotLength(WidgetTester tester, int minutes) async {
  final button = find.descendant(
    of: find.byKey(slotLengthKey),
    matching: find.text("$minutes"),
  );
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// Opens the calendar bar, sets the hours to [start] to [end] o'clock and
/// closes it.
Future<void> pickHours(WidgetTester tester, int start, int end) async {
  await openBar(tester);
  await setHours(tester, start, end);
  await closeBar(tester);
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

/// Picks [minute] in the form's [label] time field through the field's own
/// callback, as a pick in its menu does.
Future<void> chooseMinute(WidgetTester tester, String label, int minute) async {
  final button = tester.widget<DropdownButton<int>>(
    find.descendant(
      of: dropdownFinder(label),
      matching: find.byType(DropdownButton<int>),
    ),
  );
  button.onChanged!(minute);
  await tester.pumpAndSettle();
}

Finder arrowIn(String id, IconData icon) {
  return find.descendant(of: blockFinder(id), matching: find.byIcon(icon));
}

/// The labels of the open calendar bar's days shown buttons, in order.
List<String> shownDayLabels(WidgetTester tester) {
  final days = tester.widget<SegmentedButton<int>>(find.byKey(shownDaysKey));
  return <String>[
    for (final segment in days.segments) (segment.label! as Text).data!,
  ];
}

/// Opens the calendar bar, shows or hides Saturday and Sunday together and
/// closes it.
Future<void> toggleWeekends(WidgetTester tester) async {
  await openBar(tester);
  flipWeekends(tester);
  await tester.pumpAndSettle();
  await closeBar(tester);
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

/// The labels of the month's weekday header, left to right.
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
  testWidgets("H1 the bar names the hours in force and the sheet the "
      "least sizes, and the bar opens again on new hours", (tester) async {
    await pumpCalendar(tester);
    await openBar(tester);
    expect(find.textContaining("00:00 - 24:00"), findsOneWidget);
    await setHours(tester, 8, 18);
    expect(find.textContaining("08:00 - 18:00"), findsOneWidget);
    await closeBar(tester);
    expect(find.textContaining("08:00 - 18:00"), findsNothing);
    await openBar(tester);
    expect(find.textContaining("08:00 - 18:00"), findsOneWidget);

    await openSettings(tester);
    expect(find.text("Calendar settings"), findsOneWidget);
    expect(find.text("At least 44 px"), findsOneWidget);
    expect(find.text("At least 16 px per 15 minutes"), findsOneWidget);
    await closeSettings(tester);
    expect(find.text("Calendar settings"), findsNothing);
  });

  testWidgets("L1 the sheet offers the month layouts and opens on the one "
      "in force", (tester) async {
    await pumpCalendar(tester);
    await openSettings(tester);
    Set<CalendarMonthLayout> chosen() {
      return tester
          .widget<SegmentedButton<CalendarMonthLayout>>(
            find.byKey(monthLayoutKey),
          )
          .selected;
    }

    expect(chosen(), <CalendarMonthLayout>{CalendarMonthLayout.fitScreen});
    expect(find.text("Show all items"), findsOneWidget);
    expect(find.text("Fit to screen"), findsOneWidget);
    await tester.tap(find.text("Show all items"));
    await tester.pumpAndSettle();
    expect(chosen(), <CalendarMonthLayout>{CalendarMonthLayout.showAll});
    await closeSettings(tester);
    await openSettings(tester);
    expect(chosen(), <CalendarMonthLayout>{CalendarMonthLayout.showAll});
  });

  testWidgets("H2 the hours trim the week grid to their slots", (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCalendar(tester, size: tall);
    await pickMode(tester, "Week");
    final grid = gridViewport(tester);
    expect(grid.rectOfCell(96, 1), isNotNull);

    await pickHours(tester, 8, 18);
    // 40 slots, then the room below them.
    expect(grid.rectOfCell(officeRow(18 * 60), 1), isNotNull);
    expect(grid.rectOfCell(officeRow(18 * 60) + 1, 1), isNull);
    // The start and the end of the hours are labelled, and the hours
    // between them.
    expect(gutterLabelFinder("08:00"), findsOneWidget);
    expect(gutterLabelFinder("09:00"), findsOneWidget);
    expect(gutterLabelFinder("17:00"), findsOneWidget);
    expect(gutterLabelFinder("18:00"), findsOneWidget);
    expect(gutterLabelFinder("07:00"), findsNothing);
    expect(gutterLabelFinder("19:00"), findsNothing);
    final block = tester.getRect(blockFinder(uxFlowId));
    final col = colOf(1);
    expect(block.top, near(cellRect(tester, officeRow(10 * 60), col).top));
    expect(
      block.bottom,
      near(cellRect(tester, officeRow(13 * 60) - 1, col).bottom),
    );
    semantics.dispose();
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
    expect(block.top, near(cellRect(tester, officeRow(8 * 60), col).top));
    expect(
      block.bottom,
      near(cellRect(tester, officeRow(8 * 60 + 45), col).bottom),
    );
    expect(
      tester.getRect(blockFinder(evening)).bottom,
      near(cellRect(tester, officeRow(17 * 60 + 45), col).bottom),
    );
    expect(arrowIn(early, Icons.keyboard_arrow_up), findsOneWidget);
    expect(arrowIn(early, Icons.keyboard_arrow_down), findsNothing);
    expect(arrowIn(evening, Icons.keyboard_arrow_down), findsOneWidget);
    expect(arrowIn(evening, Icons.keyboard_arrow_up), findsNothing);
    expect(arrowIn(uxFlowId, Icons.keyboard_arrow_up), findsNothing);

    // Onto Wednesday's free 10:00 to 11:00, a drop the grid would admit.
    final updates = updateCount(api);
    await moveBlock(
      tester,
      blockFinder(early),
      cellRect(tester, officeRow(10 * 60), 3).topLeft,
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(blockFinder(early)), block);
    expect(updateCount(api), updates);
  });

  testWidgets("H4 an item wholly outside the hours has no block, and "
      "yellow rows frozen above and below the slots count each day's in its "
      "column", (tester) async {
    final semantics = tester.ensureSemantics();
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    final wednesday = DateTime(2026, 4, 22);
    final thursday = DateTime(2026, 4, 23);
    final lateId = await store(
      tester,
      api,
      taskJson("Late", today, 19 * 60, 20 * 60),
    );
    await store(tester, api, taskJson("Run", thursday, 6 * 60, 7 * 60));
    // 05:00 to 06:00 on Wednesday and on Thursday.
    await store(tester, api, taskJson("Trip", wednesday, 5 * 60, 6 * 60));
    await store(tester, api, taskJson("Trip", thursday, 5 * 60, 6 * 60));
    await pumpCalendar(tester, api: api);
    await pickMode(tester, "Week");
    expect(blockFinder(lateId), findsOneWidget);
    expect(find.byKey(hiddenAboveKey(thursday)), findsNothing);
    expect(find.byKey(hiddenBelowKey(today)), findsNothing);

    await pickHours(tester, 8, 18);
    expect(blockFinder(lateId), findsNothing);
    // A week's column is too narrow for "+N more", so it says "+N".
    List<String> textsIn(Finder cell) {
      return <String>[
        for (final text in tester.widgetList<Text>(
          find.descendant(of: cell, matching: find.byType(Text)),
        ))
          text.data!,
      ];
    }

    expect(textsIn(find.byKey(hiddenAboveKey(today))), isEmpty);
    expect(textsIn(find.byKey(hiddenAboveKey(wednesday))), <String>["+1"]);
    expect(textsIn(find.byKey(hiddenAboveKey(thursday))), <String>["+2"]);
    expect(textsIn(find.byKey(hiddenBelowKey(today))), <String>["+1"]);
    expect(textsIn(find.byKey(hiddenBelowKey(wednesday))), isEmpty);
    expect(
      find.bySemanticsLabel("Thursday, April 23, 2 more items before 08:00"),
      findsOneWidget,
    );
    expect(find.byKey(hiddenCountKey), findsNothing);

    // The rows lie in the days' columns, under the header and on the
    // grid's bottom edge.
    final grid = gridViewport(tester);
    final box = grid.localToGlobal(Offset.zero) & grid.size;
    final header = tester.getRect(headerFinder(wednesday));
    final top = tester.getRect(find.byKey(hiddenAboveKey(wednesday)));
    final bottom = tester.getRect(find.byKey(hiddenBelowKey(wednesday)));
    expect(top.top, near(header.bottom));
    expect(top.left, near(header.left));
    expect(top.width, near(header.width));
    expect(bottom.bottom, near(box.bottom));
    expect(bottom.left, near(header.left));

    // Slots too tall to fit scroll beneath the rows, which stay put.
    await openSettings(tester);
    await setSlider(tester, slotHeightSliderKey, 32.0);
    await closeSettings(tester);
    final block = tester.getRect(blockFinder(uxFlowId));
    // From the middle of Saturday's column, which holds no item.
    await tester.dragFrom(
      Offset(
        tester.getCenter(headerFinder(DateTime(2026, 4, 25))).dx,
        box.center.dy,
      ),
      const Offset(0.0, -200.0),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(blockFinder(uxFlowId)).top, lessThan(block.top));
    expect(tester.getRect(find.byKey(hiddenAboveKey(wednesday))), top);
    expect(tester.getRect(find.byKey(hiddenBelowKey(wednesday))), bottom);
    semantics.dispose();
  });

  testWidgets("H5 a tap on the last slot creates up to the end of the "
      "hours", (tester) async {
    await pumpCalendar(tester, editing: true, size: tall);
    await pickMode(tester, "Week");
    await pickHours(tester, 8, 18);

    await tester.tapAt(
      cellRect(tester, officeRow(17 * 60 + 45), colOf(3)).center,
    );
    await tester.pumpAndSettle();
    expect(find.text("New item"), findsOneWidget);
    await tester.tap(find.text("Task").last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: dropdownFinder("Start time"),
        matching: find.text("17:45"),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dropdownFinder("End time"),
        matching: find.text("18:00"),
      ),
      findsOneWidget,
    );
  });

  testWidgets("H6 the form offers the hours' times and holds a change of "
      "its times to them", (tester) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    final early = await store(
      tester,
      api,
      taskJson("Early", today, 7 * 60, 9 * 60),
    );
    await pumpCalendar(tester, editing: true, api: api, size: tall);
    await pickMode(tester, "Week");
    await pickHours(tester, 8, 18);
    await tester.tap(blockFinder(early));
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsOneWidget);

    expect(offeredMinutes(tester, "Start time"), <int>[
      7 * 60,
      for (var minute = 8 * 60; minute < 18 * 60; minute += 15) minute,
    ]);
    expect(offeredMinutes(tester, "End time"), <int>[
      for (var minute = 8 * 60 + 15; minute <= 18 * 60; minute += 15) minute,
    ]);

    final updates = updateCount(api);
    await chooseMinute(tester, "End time", 10 * 60);
    await tester.tap(find.widgetWithText(FilledButton, "Save"));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "The start is from 08:00 to before 18:00, inside the calendar's "
        "hours.",
      ),
      findsOneWidget,
    );
    expect(updateCount(api), updates);

    // Keeping the stored times, a new title saves.
    await chooseMinute(tester, "End time", 9 * 60);
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
    final gutter = grid.frozenInsetOf(Axis.horizontal);
    expect(cell.width, near((grid.size.width - gutter) / 7));
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
    final room = labelRoom(tester);
    final bottom = grid.localToGlobal(Offset(0.0, grid.size.height)).dy;
    expect(
      cellRect(tester, officeRow(8 * 60), 1).height,
      near((grid.size.height - 40.0 - 2 * room) / 40),
    );
    expect(
      cellRect(tester, officeRow(17 * 60 + 45), 1).bottom,
      near(bottom - room),
    );
  });

  testWidgets("Z3 a new slot height keeps the time at the top in place", (
    tester,
  ) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Week");
    final header = cellRect(tester, 0, 1).bottom;
    final room = labelRoom(tester);
    final slot = cellRect(tester, rowOf(8 * 60), 1).height;
    expect(cellRect(tester, rowOf(8 * 60), 1).top, near(header + room));

    // The time at the top edge, the room's share of a slot before 08:00,
    // stays there, so the room above 08:00's line grows with the slots.
    await openSettings(tester);
    await setSlider(tester, slotHeightSliderKey, 32.0);
    await closeSettings(tester);
    expect(cellRect(tester, rowOf(8 * 60), 1).height, near(32.0));
    expect(
      cellRect(tester, rowOf(8 * 60), 1).top,
      near(header + room * 32.0 / slot),
    );
  });

  testWidgets("Z4 a grid opens at the hours' start when they begin after "
      "08:00", (tester) async {
    await pumpCalendar(tester);
    await pickHours(tester, 12, 24);
    await openSettings(tester);
    await setSlider(tester, slotHeightSliderKey, 32.0);
    await closeSettings(tester);
    await pickMode(tester, "Week");

    // The seed's items before 12:00 put the 24 px row counting them in
    // the place of the room above the first slot.
    final header = cellRect(tester, 0, 1).bottom;
    expect(cellRect(tester, 2, 1).height, near(32.0));
    expect(cellRect(tester, 2, 1).top, near(header + 24.0));
  });

  testWidgets("H7 hours as long as the last relabel the gutter of a week "
      "with no items", (tester) async {
    // No item moves, so no item change rebuilds the board's cells.
    await pumpCalendar(
      tester,
      api: MockCalendarApi(latency: harnessLatency),
      size: tall,
    );
    final semantics = tester.ensureSemantics();
    await pickMode(tester, "Week");
    await pickHours(tester, 8, 18);
    expect(gutterLabelFinder("08:00"), findsOneWidget);

    await pickHours(tester, 9, 19);
    final grid = gridViewport(tester);
    expect(grid.rectOfCell(42, 1), isNotNull);
    expect(grid.rectOfCell(43, 1), isNull);
    expect(gutterLabelFinder("19:00"), findsOneWidget);
    expect(gutterLabelFinder("08:00"), findsNothing);
    semantics.dispose();
  });

  testWidgets("H8 the AM/PM switch relabels the hours of a week with no "
      "items, painted and to a screen reader, and the bar opens on it", (
    tester,
  ) async {
    // No item moves, so no item change rebuilds the board's cells.
    await pumpCalendar(
      tester,
      api: MockCalendarApi(latency: harnessLatency),
      size: tall,
    );
    final semantics = tester.ensureSemantics();
    await pickMode(tester, "Week");
    await pickHours(tester, 8, 18);
    expect(gutterLabelFinder("13:00"), findsOneWidget);
    // The test font gives every character one width, which "08:00" holds
    // five of.
    List<List<double>> lineWidths() {
      return <List<double>>[
        for (final label in paintGridForeground(tester).paragraphs)
          <double>[
            for (final line in label.paragraph.computeLineMetrics()) line.width,
          ],
      ];
    }

    final character = lineWidths().first.single / 5;

    await openBar(tester);
    Finder twelveHour() {
      return find.byKey(hourLabelFormatKey);
    }

    expect(tester.widget<Switch>(twelveHour()).value, isFalse);
    await tester.tap(twelveHour());
    await tester.pumpAndSettle();
    await closeBar(tester);
    expect(gutterLabelFinder("8 AM"), findsOneWidget);
    expect(gutterLabelFinder("12 PM"), findsOneWidget);
    expect(gutterLabelFinder("1 PM"), findsOneWidget);
    expect(gutterLabelFinder("6 PM"), findsOneWidget);
    // A label wider than the gutter's 50 px room, five characters, breaks
    // between its words.
    const labels = <List<String>>[
      <String>["8 AM"],
      <String>["9 AM"],
      <String>["10", "AM"],
      <String>["11", "AM"],
      <String>["12", "PM"],
      <String>["1 PM"],
      <String>["2 PM"],
      <String>["3 PM"],
      <String>["4 PM"],
      <String>["5 PM"],
      <String>["6 PM"],
    ];
    expect(lineWidths(), <List<double>>[
      for (final lines in labels)
        <double>[for (final line in lines) line.length * character],
    ]);

    await openBar(tester);
    expect(tester.widget<Switch>(twelveHour()).value, isTrue);
    semantics.dispose();
  });

  testWidgets("H9 the bar's hours read as the AM/PM switch says, the "
      "whole day as 12 AM - 12 AM, and its slider has no labels over its "
      "thumbs, which a screen reader hears in that format", (tester) async {
    await pumpCalendar(tester);
    await openBar(tester);
    RangeSlider slider() {
      return tester.widget<RangeSlider>(find.byKey(hoursSliderKey));
    }

    expect(slider().labels, isNull);
    expect(slider().semanticFormatterCallback!(8.0), "08:00");
    await tester.tap(find.byKey(hourLabelFormatKey));
    await tester.pumpAndSettle();
    expect(find.textContaining("12 AM - 12 AM"), findsOneWidget);
    expect(slider().semanticFormatterCallback!(8.0), "8 AM");
    await setHours(tester, 8, 18);
    expect(find.textContaining("8 AM - 6 PM"), findsOneWidget);
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
      near((grid.size.width - grid.frozenInsetOf(Axis.horizontal)) / 5),
    );
    expect(blockFinder(weekendId), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(hiddenCountKey),
        matching: find.text("+1"),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel("1 item is on a day not shown\n+1"),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.byKey(hiddenCountKey)).center.dy,
      near(grid.localToGlobal(Offset.zero).dy + 20.0),
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

    expect(weekdayHeaderLetters(tester), <String>[
      "Mon",
      "Tue",
      "Wed",
      "Thu",
      "Fri",
    ]);
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
    expect(find.text("Aug 2026"), findsOneWidget);
    expect(dayFinder(2026, 7, 31), findsNothing);
    expect(dayFinder(2026, 8, 3), findsOneWidget);
    expect(tester.getRect(monthGridFinder()).height, near(5 * 48.0));
    // The read of the month the card rests on.
    await tester.pump(harnessLatency);
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
    expect(gridDay(tester), DateTime(2026, 4, 24));

    await tester.tap(find.byTooltip("Next day"));
    await tester.pumpAndSettle();
    expect(gridDay(tester), DateTime(2026, 4, 27));
    await tester.tap(find.byTooltip("Previous day"));
    await tester.pumpAndSettle();
    expect(gridDay(tester), DateTime(2026, 4, 24));
  });

  testWidgets("W5 a month step onto a hidden day takes the nearest shown "
      "day of that month", (tester) async {
    await pumpCalendar(tester);
    await toggleWeekends(tester);
    await tester.tap(dayFinder(2026, 4, 30));
    await tester.pumpAndSettle();

    // May 30 2026 is a Saturday, and June 1 is in the next month. Month's
    // chevrons step the selected day; Agenda's list names it.
    await pickMode(tester, "Month");
    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    await pickMode(tester, "Agenda");
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    expect(find.text("Friday, May 29"), findsOneWidget);
  });

  testWidgets("W6 the week starts on the weekday the bar picks, in the "
      "bar's days and in every view", (tester) async {
    await pumpCalendar(tester);
    await openBar(tester);
    await tester.tap(find.byKey(weekStartKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Sunday").last);
    await tester.pumpAndSettle();
    expect(shownDayLabels(tester), <String>[
      "Sun",
      "Mon",
      "Tue",
      "Wed",
      "Thu",
      "Fri",
      "Sat",
    ]);
    await closeBar(tester);

    expect(weekdayHeaderLetters(tester), <String>[
      "Sun",
      "Mon",
      "Tue",
      "Wed",
      "Thu",
      "Fri",
      "Sat",
    ]);
    expect(
      tester.getRect(dayFinder(2026, 4, 5)).left,
      near(tester.getRect(monthGridFinder()).left),
    );

    await pickMode(tester, "Day");
    expect(
      tester.getRect(find.byKey(weekStripDayKey(DateTime(2026, 4, 19)))).left,
      near(tester.getRect(find.byType(WeekStrip<ItemPayload>)).left),
    );

    await pickMode(tester, "Week");
    expect(headerFinder(DateTime(2026, 4, 19)), findsOneWidget);

    await pickMode(tester, "Month");
    expect(weekdayHeaderLetters(tester), <String>[
      "S",
      "M",
      "T",
      "W",
      "T",
      "F",
      "S",
    ]);
  });

  testWidgets("W7 the bar hides any weekday from the views, and keeps the "
      "last one shown", (tester) async {
    await pumpCalendar(tester);
    await openBar(tester);
    await tester.tap(
      find.descendant(of: find.byKey(shownDaysKey), matching: find.text("Wed")),
    );
    await tester.pumpAndSettle();
    await closeBar(tester);
    expect(weekdayHeaderLetters(tester), <String>[
      "Mon",
      "Tue",
      "Thu",
      "Fri",
      "Sat",
      "Sun",
    ]);
    await pickMode(tester, "Week");
    expect(headerFinder(DateTime(2026, 4, 22)), findsNothing);

    await openBar(tester);
    tester
        .widget<SegmentedButton<int>>(find.byKey(shownDaysKey))
        .onSelectionChanged!(const <int>{0});
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byKey(shownDaysKey), matching: find.text("Mon")),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SegmentedButton<int>>(find.byKey(shownDaysKey)).selected,
      const <int>{0},
    );
  });

  testWidgets("E1 the calendar opens out of edit mode, and the settings "
      "sheet holds the lock, Month's layout and the least sizes, and none of "
      "the bar's settings", (tester) async {
    await pumpCalendar(tester);
    await openBar(tester);
    expect(tester.widget<Switch>(find.byKey(editModeKey)).value, isFalse);
    await closeBar(tester);
    await openSettings(tester);
    expect(find.text("Lock past days"), findsOneWidget);
    expect(find.text("Month layout"), findsOneWidget);
    expect(find.text("Day width"), findsOneWidget);
    expect(find.text("Slot height"), findsOneWidget);
    expect(find.text("Edit mode"), findsNothing);
    expect(find.text("Week starts on"), findsNothing);
    expect(find.text("Days shown"), findsNothing);
    expect(find.text("Hours"), findsNothing);
    expect(find.text("AM/PM hour labels"), findsNothing);
  });
  testWidgets("SL1 the sheet offers the six slot lengths and opens on the "
      "one in force", (tester) async {
    await pumpCalendar(tester);
    await openSettings(tester);
    expect(find.text("Slot length"), findsOneWidget);
    expect(<int>[
      for (final segment in slotLengthButtons(tester).segments) segment.value,
    ], CalendarDates.slotMinuteChoices);
    expect(CalendarDates.slotMinuteChoices, <int>[5, 10, 15, 20, 30, 60]);
    expect(slotLengthButtons(tester).selected, <int>{15});
  });

  testWidgets("SL2 choosing 30 minutes gives the grid 48 slot rows, and the "
      "slot height names them", (tester) async {
    await pumpCalendar(tester, size: tall);
    await pickMode(tester, "Week");
    final grid = gridViewport(tester);
    expect(grid.rectOfCell(2 + 96, 1), isNotNull);
    await openSettings(tester);
    await chooseSlotLength(tester, 30);
    expect(slotLengthButtons(tester).selected, <int>{30});
    expect(find.text("At least 16 px per 30 minutes"), findsOneWidget);
    await closeSettings(tester);
    // The day header, the room above the slots, 48 slots and the room
    // below them.
    expect(grid.rectOfCell(2 + 47, 1), isNotNull);
    expect(grid.rectOfCell(2 + 48, 1), isNotNull);
    expect(grid.rectOfCell(2 + 49, 1), isNull);
    expect(
      tester
          .widget<TimedGrid<ItemPayload>>(find.byType(TimedGrid<ItemPayload>))
          .slotMinutes,
      30,
    );
  });

  testWidgets("SL3 from 08:10-17:50 at slot 10, choosing 30 minutes gives "
      "08:00-18:00", (tester) async {
    const off = CalendarDayHours(8 * 60 + 10, 17 * 60 + 50);
    const office = CalendarDayHours(8 * 60, 18 * 60);
    final start = const CalendarSettings(hours: off, slotMinutes: 10);
    expect(
      start.withSlotMinutes(30),
      start.copyWith(hours: office, slotMinutes: 30),
    );
    expect(start.withSlotMinutes(5), start.copyWith(slotMinutes: 5));

    final controller = CalendarController();
    addTearDown(controller.dispose);
    final chosen = <CalendarSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: CalendarSettingsSheet(
            settings: start,
            controller: controller,
            onChanged: chosen.add,
          ),
        ),
      ),
    );
    expect(slotLengthButtons(tester).selected, <int>{10});
    await chooseSlotLength(tester, 30);
    expect(chosen, hasLength(1));
    expect(chosen.single.slotMinutes, 30);
    expect(chosen.single.hours, office);
  });

  testWidgets("OS1 the sheet's overlap switch is off by default, and a tap "
      "reports settings that allow overlaps", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    final chosen = <CalendarSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: CalendarSettingsSheet(
            settings: const CalendarSettings(),
            controller: controller,
            onChanged: chosen.add,
          ),
        ),
      ),
    );
    final overlaps = find.byKey(allowsOverlapsKey);
    expect(find.text("Allow overlapping items"), findsOneWidget);
    expect(tester.widget<SwitchListTile>(overlaps).value, isFalse);
    await tester.ensureVisible(overlaps);
    await tester.pumpAndSettle();
    await tester.tap(overlaps);
    await tester.pumpAndSettle();
    expect(chosen, <CalendarSettings>[
      const CalendarSettings(allowsOverlaps: true),
    ]);
    expect(tester.widget<SwitchListTile>(overlaps).value, isTrue);
  });

  testWidgets("OS4 after each switch of the sheet the calendar's edit "
      "policy is the one its settings give", (tester) async {
    await pumpCalendar(tester, editing: true);
    await pickMode(tester, "Week");
    CalendarEditPolicy<ItemPayload>? shownPolicy() {
      return tester
          .widget<CalendarView<ItemPayload>>(
            find.byType(CalendarView<ItemPayload>),
          )
          .editPolicy;
    }

    var settings = const CalendarSettings(editing: true);
    expect(shownPolicy(), settings.editPolicy);
    await openSettings(tester);
    Future<void> flip(Key key, CalendarSettings next) async {
      await tester.ensureVisible(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      settings = next;
      expect(shownPolicy(), settings.editPolicy, reason: "$settings");
    }

    await flip(lockPastKey, settings.copyWith(lockPast: true));
    await flip(lockEarlierTodayKey, settings.copyWith(lockEarlierToday: true));
    await flip(allowsOverlapsKey, settings.copyWith(allowsOverlaps: true));
    await flip(lockPastKey, settings.copyWith(lockPast: false));
    await flip(allowsOverlapsKey, settings.copyWith(allowsOverlaps: false));
    await closeSettings(tester);
  });
}
