/// The calendar's Agenda mode: the Monday-first grid, the selection, the
/// chevrons, the fold into the selected week, the placeholders and the
/// day list's counts, over the seeded mock.
library;

import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/settings_sheet.dart';
import 'package:widgets_extended/calendar/composition/calendar_card.dart';
import 'package:widgets_extended/calendar/composition/calendar_header.dart'
    show calendarViewButtonKey;
import 'package:widgets_extended/calendar/composition/calendar_view.dart'
    show CalendarView;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';

import 'workspace_calendar/calendar_harness.dart';

Finder gridFinder() {
  return find.byKey(const ValueKey<String>("calendar-grid"));
}

Finder dayFinder(int year, int month, int day) {
  return find.byKey(dayCellKey(DateTime(year, month, day)));
}

/// The cell of the strip the folded month becomes showing [month]'s [day]
/// of 2026.
Finder stripDayFinder(int month, int day) {
  return find.byKey(weekStripDayKey(DateTime(2026, month, day)));
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

/// The labels of the weekday header, left to right.
List<String> weekdayHeaderLetters(WidgetTester tester) {
  final texts = tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(const ValueKey<String>("weekday-header")),
      matching: find.byType(Text),
    ),
  );
  return <String>[for (final text in texts) text.data!];
}

/// The three-letter weekday names of the cells in the grid's top row, left to
/// right, as the folded strip shows them: those whose middles lie in the
/// grid, as the strip builds a few days past either edge as well.
List<String> topRowShortNames(WidgetTester tester) {
  final grid = tester.getRect(gridFinder());
  final cells = <({double left, String name})>[];
  for (final element in find.byType(DayCell).evaluate()) {
    final cell = find.byWidget(element.widget);
    final rect = tester.getRect(cell);
    if (rect.top != grid.top || !grid.contains(rect.center)) {
      continue;
    }
    final texts = tester.widgetList<Text>(
      find.descendant(of: cell, matching: find.byType(Text)),
    );
    // The name above the number.
    cells.add((left: rect.left, name: texts.first.data!));
  }
  cells.sort((a, b) {
    return a.left.compareTo(b.left);
  });
  return <String>[for (final cell in cells) cell.name];
}

bool hasMarker(WidgetTester tester, int month, int day) {
  return tester.widget<DayCell>(dayFinder(2026, month, day)).hasEntries;
}

void main() {
  testWidgets("E1 opens on today's month with today's items", (tester) async {
    await pumpCalendar(tester);

    expect(find.text("Apr 2026"), findsOneWidget);
    expect(viewButtonShowing("Agenda"), findsOneWidget);
    expect(find.text("Today, April 21"), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(dayListHeaderKey(today)),
        matching: find.text("2 items"),
      ),
      findsOneWidget,
    );
    expect(find.text("Design new UX flow for Michael"), findsOneWidget);
    expect(find.text("Brainstorm with the team"), findsOneWidget);

    expect(weekdayHeaderLetters(tester), <String>[
      "Mon",
      "Tue",
      "Wed",
      "Thu",
      "Fri",
      "Sat",
      "Sun",
    ]);
    expect(find.byType(DayCell), findsNWidgets(30));
    final grid = tester.getRect(gridFinder());
    // April 2026 runs from a Wednesday to a Thursday in five weeks.
    expect(
      tester.getRect(dayFinder(2026, 4, 1)).topLeft,
      offsetMoreOrLessEquals(grid.topLeft + Offset(2 * grid.width / 7, 0.0)),
    );
    expect(
      tester.getRect(dayFinder(2026, 4, 5)).topRight,
      offsetMoreOrLessEquals(grid.topRight),
    );
    expect(
      tester.getRect(dayFinder(2026, 4, 30)).bottom,
      moreOrLessEquals(grid.bottom),
    );
    expect(dayFinder(2026, 3, 30), findsNothing);
    expect(dayFinder(2026, 5, 3), findsNothing);
    expect(gridHeight(tester), 5 * rowHeight(tester));

    final selected = tester.widget<DayCell>(dayFinder(2026, 4, 21));
    expect(selected.isSelected, isTrue);
    expect(selected.isToday, isTrue);
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
    await pumpCalendar(tester, editing: true);

    await tapAndSettle(tester, dayFinder(2026, 4, 27));
    expect(find.text("Monday, April 27"), findsOneWidget);
    expect(find.text("8 items"), findsOneWidget);
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 27)).isSelected, isTrue);
    expect(tester.widget<DayCell>(dayFinder(2026, 4, 21)).isSelected, isFalse);

    final semantics = tester.ensureSemantics();
    await tapAndSettle(tester, dayFinder(2026, 4, 25));
    expect(find.text("Saturday, April 25"), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(dayListHeaderKey(DateTime(2026, 4, 25))),
        matching: find.text("No items"),
      ),
      findsOneWidget,
    );
    expect(find.byKey(dayListGapKey(DateTime(2026, 4, 25), 0)), findsOneWidget);
    expect(
      tester.getSemantics(dayFinder(2026, 4, 25)).label,
      startsWith("Saturday, April 25"),
    );
    semantics.dispose();
  });

  testWidgets("E4 Month's chevrons step the selected day by month and keep "
      "its day of the month, which Agenda's list then names", (tester) async {
    await pumpCalendar(tester);

    await pickMode(tester, "Month");
    await tapAndSettle(tester, find.byTooltip("Next month"));
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    expect(find.text("May 2026"), findsOneWidget);
    await pickMode(tester, "Agenda");
    expect(find.text("Thursday, May 21"), findsOneWidget);

    // March 31 steps to April 30, the last day April has.
    await tapAndSettle(tester, find.byTooltip("Previous month"));
    await tapAndSettle(tester, find.byTooltip("Previous month"));
    await tapAndSettle(tester, dayFinder(2026, 3, 31));
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    await pickMode(tester, "Month");
    await tapAndSettle(tester, find.byTooltip("Next month"));
    await pickMode(tester, "Agenda");
    expect(find.text("Thursday, April 30"), findsOneWidget);
  });

  testWidgets("E5 scrolling the list folds the month into the selected week "
      "and a pull down on the folded strip unfolds it", (tester) async {
    const latency = Duration(seconds: 1);
    await pumpCalendar(
      tester,
      api: MockCalendarApi.seeded(today, latency: latency),
    );
    final row = rowHeight(tester);

    await tester.drag(
      find.byType(DayList<ItemPayload>),
      const Offset(0.0, -120.0),
    );
    await tester.pumpAndSettle();
    expect(gridHeight(tester), row);
    expect(viewButtonShowing("Agenda"), findsOneWidget);
    expect(viewButtonShowing("Week"), findsNothing);
    final grid = tester.getRect(gridFinder());
    // The strip that takes the row's place shows April 20 to 26.
    expect(tester.getRect(stripDayFinder(4, 20)).topLeft, grid.topLeft);
    expect(
      tester.getRect(stripDayFinder(4, 26)).topRight,
      offsetMoreOrLessEquals(grid.topRight),
    );
    expect(topRowShortNames(tester), <String>[
      "Mon",
      "Tue",
      "Wed",
      "Thu",
      "Fri",
      "Sat",
      "Sun",
    ]);

    // The chevrons now step by week, and the strip follows.
    await tapAndSettle(tester, find.byTooltip("Next week"));
    expect(find.text("Tuesday, April 28"), findsOneWidget);
    expect(tester.getRect(stripDayFinder(4, 27)).topLeft, grid.topLeft);

    await tester.drag(
      find.byType(WeekStrip<ItemPayload>),
      const Offset(0.0, 120.0),
    );
    await tester.pumpAndSettle();
    expect(gridHeight(tester), 5 * row);
    expect(viewButtonShowing("Agenda"), findsOneWidget);
    // The weekday header is back above the grid, so its top moved down.
    var unfolded = tester.getRect(gridFinder());
    expect(
      tester.getRect(dayFinder(2026, 4, 1)).topLeft,
      offsetMoreOrLessEquals(
        unfolded.topLeft + Offset(2 * unfolded.width / 7, 0.0),
      ),
    );

    // Folded again, the next week is May's, whose grid the calendar reads
    // as it shows it, and a pull on the strip unfolds the month while that
    // read runs.
    await tester.drag(
      find.byType(DayList<ItemPayload>),
      const Offset(0.0, -120.0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next week"));
    await tester.pump();
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text("Tuesday, May 5"), findsOneWidget);
    await tester.drag(
      find.byType(WeekStrip<ItemPayload>),
      const Offset(0.0, 120.0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(gridHeight(tester), 5 * row);
    unfolded = tester.getRect(gridFinder());
    expect(
      tester.getRect(dayFinder(2026, 5, 1)).topLeft,
      offsetMoreOrLessEquals(
        unfolded.topLeft + Offset(4 * unfolded.width / 7, 0.0),
      ),
    );
    await tester.pump(latency);
    await tester.pumpAndSettle();
  });

  testWidgets("E6 a drag down the list scrolls back to earlier days and "
      "leaves the month folded; a pull down on the strip unfolds it", (
    tester,
  ) async {
    await pumpCalendar(tester);
    await tapAndSettle(tester, dayFinder(2026, 4, 27));

    await tester.drag(
      find.byType(DayList<ItemPayload>),
      const Offset(0.0, -60.0),
    );
    await tester.pumpAndSettle();
    expect(gridHeight(tester), rowHeight(tester));
    await tester.drag(
      find.byType(DayList<ItemPayload>),
      const Offset(0.0, 600.0),
    );
    await tester.pumpAndSettle();
    expect(gridHeight(tester), rowHeight(tester));
    await tester.drag(
      find.byType(WeekStrip<ItemPayload>),
      const Offset(0.0, 40.0),
    );
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
      tester.getRect(dayFinder(2026, 4, 26)).right,
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
      tester.getRect(dayFinder(2026, 4, 26)).right,
      moreOrLessEquals(grid.right),
    );
  });

  testWidgets("E10 the longest month name fits a narrow phone", (tester) async {
    await pumpCalendar(tester, size: const Size(320.0, 640.0));

    for (var i = 0; i < 5; i++) {
      await tapAndSettle(tester, find.byTooltip("Next month"));
    }
    expect(find.text("Sep 2026"), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(harnessLatency);
  });

  testWidgets("E11 the settings sheet opens from the header's settings "
      "button, the row's last, 4 px after the view button and in its "
      "colour, circle and icon size", (tester) async {
    await pumpCalendar(tester);
    final settings = find.descendant(
      of: find.byType(CalendarView<ItemPayload>),
      matching: find.byTooltip("Calendar settings"),
    );
    final view = find.byKey(calendarViewButtonKey);
    expect(settings, findsOneWidget);
    expect(
      find.descendant(of: settings, matching: find.byIcon(Icons.tune)),
      findsOneWidget,
    );
    // The button's tap target, as the view button's rect is.
    final settingsButton = find.ancestor(
      of: find.descendant(of: settings, matching: find.byIcon(Icons.tune)),
      matching: find.byType(IconButton),
    );
    final rect = tester.getRect(settingsButton);
    expect(rect.left - tester.getRect(view).right, 4.0);
    expect(rect.center.dy, tester.getRect(view).center.dy);

    Color? glyph(Finder button) {
      return tester
          .widget<RichText>(
            find.descendant(
              of: find.descendant(of: button, matching: find.byType(Icon)),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style!
          .color;
    }

    expect(glyph(settings), glyph(view));

    // The same circle around the same icon as the view button.
    Finder inkOf(Finder button) {
      return find.descendant(of: button, matching: find.byType(Material)).first;
    }

    Finder iconOf(Finder button) {
      return find.descendant(of: button, matching: find.byType(Icon));
    }

    expect(tester.getSize(inkOf(settingsButton)), tester.getSize(inkOf(view)));
    expect(
      tester.widget<Material>(inkOf(settingsButton)).shape,
      tester.widget<Material>(inkOf(view)).shape,
    );
    expect(
      tester.getSize(iconOf(settingsButton)),
      tester.getSize(iconOf(view)),
    );

    await tapAndSettle(tester, settings);
    expect(find.byType(CalendarSettingsSheet), findsOneWidget);
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

    await tester.drag(
      find.byType(DayList<ItemPayload>),
      const Offset(0.0, -120.0),
    );
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

    // Once the fold settles, the unfold eases out on the same curve.
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(WeekStrip<ItemPayload>),
      const Offset(0.0, 120.0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final t = Curves.fastOutSlowIn.transform(1.0 / 3.0);
    expect(gridHeight(tester), moreOrLessEquals(row + (month - row) * t));
    await tester.pump(const Duration(milliseconds: 200));
    expect(gridHeight(tester), month);
  });

  testWidgets("E13 Agenda's month puts its days on grey circles and shows "
      "no days of other months", (tester) async {
    await pumpCalendar(tester);
    Color? fillOf(int month, int day) {
      final circle = tester.widget<Container>(
        find
            .descendant(
              of: dayFinder(2026, month, day),
              matching: find.byType(Container),
            )
            .first,
      );
      return (circle.decoration as BoxDecoration?)?.color;
    }

    expect(fillOf(4, 22), HarborColors.background);
    expect(dayFinder(2026, 3, 30), findsNothing);
  });

  testWidgets("E14 the pull tab folds the month as far as a drag moves it; "
      "a slow release settles on whichever is nearer and a fast one the "
      "way it moves, and a tap switches", (tester) async {
    await pumpCalendar(tester);
    final row = rowHeight(tester);
    final month = gridHeight(tester);
    final tab = find.byKey(calendarPullTabKey);

    final gesture = await tester.startGesture(tester.getCenter(tab));
    await gesture.moveBy(const Offset(0.0, -20.0));
    await gesture.moveBy(const Offset(0.0, -60.0));
    await tester.pump();
    expect(gridHeight(tester), inExclusiveRange(row, month));
    await gesture.cancel();
    await tester.pumpAndSettle();

    // A quarter of the way, slowly: back to the month.
    await tester.timedDrag(
      tab,
      const Offset(0.0, -60.0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(gridHeight(tester), month);
    // Two thirds of the way, slowly: on to the week.
    await tester.timedDrag(
      tab,
      const Offset(0.0, -150.0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(gridHeight(tester), row);
    // A quarter of the way back, fast: the month.
    await tester.fling(tab, const Offset(0.0, 60.0), 1000.0);
    await tester.pumpAndSettle();
    expect(gridHeight(tester), month);

    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(gridHeight(tester), row);
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(gridHeight(tester), month);
  });

  testWidgets("E15 the app bar's Today pill selects today from another "
      "month or week", (tester) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Month");
    await tapAndSettle(tester, find.byTooltip("Next month"));
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    // Setup sanity: the step left today's month.
    expect(find.text("May 2026"), findsOneWidget);
    await tapToday(tester);
    await tester.pumpAndSettle();
    expect(find.text("Apr 2026"), findsOneWidget);

    await pickMode(tester, "Week");
    await tapAndSettle(tester, find.byTooltip("Next week"));
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    await tapToday(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(dayHeaderKey(today)), findsOneWidget);
  });

  testWidgets("E17 the header names the month in 16 px type", (tester) async {
    await pumpCalendar(tester);
    final title = tester.renderObject<RenderParagraph>(find.text("Apr 2026"));
    expect(title.text.style!.fontSize, 16.0);
  });

  testWidgets("E18 the app bar has no actions, so no More menu, zone "
      "button, Today button or Add, and the calendar's header holds the "
      "Today button, the edit mode toggle and the settings button", (
    tester,
  ) async {
    await pumpCalendar(tester);
    final bar = find.byType(AppBar);
    final calendar = find.byType(CalendarView<ItemPayload>);
    expect(tester.widget<AppBar>(bar).actions, isNull);
    expect(find.byTooltip("More"), findsNothing);
    expect(find.byIcon(Icons.public), findsNothing);
    expect(
      find.descendant(of: bar, matching: todayButtonFinder()),
      findsNothing,
    );
    expect(
      find.descendant(of: calendar, matching: todayButtonFinder()),
      findsOneWidget,
    );
    expect(
      find.descendant(of: calendar, matching: editToggleFinder()),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: calendar,
        matching: find.byTooltip("Calendar settings"),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip("Calendar settings bar"), findsNothing);
    expect(find.byIcon(Icons.settings), findsNothing);
    expect(find.byTooltip("Add"), findsNothing);
  });

  testWidgets("E19 the header's edit mode toggle turns edit mode on and "
      "off, which a screen reader hears as its selected state", (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCalendar(tester);
    bool editing() {
      return tester
          .widget<CalendarView<ItemPayload>>(
            find.byType(CalendarView<ItemPayload>),
          )
          .editable;
    }

    final gap = find.byKey(dayListGapKey(today, 0));
    expect(editing(), isFalse);
    expect(gap, findsNothing);
    expect(
      tester.getSemantics(editToggleFinder()),
      isSemantics(
        tooltip: "Edit mode",
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );
    await toggleEditMode(tester);
    expect(editing(), isTrue);
    expect(gap, findsOneWidget);
    expect(
      tester.getSemantics(editToggleFinder()),
      isSemantics(
        tooltip: "Edit mode",
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    await toggleEditMode(tester);
    expect(editing(), isFalse);
    expect(gap, findsNothing);
    semantics.dispose();
  });

  for (final width in <double>[390.0, 320.0]) {
    testWidgets("E21 at $width px the sheet lines its compact rows' titles, "
        "its zone chips, its days, its slot lengths and its hours slider up "
        "with the start of its content, 24 px in, and their switches, its "
        "week start menu, its days, its slot lengths and its slider with the "
        "end, overflowing nothing", (tester) async {
      await pumpCalendar(tester, size: Size(width, 844.0));
      await openSettings(tester);
      final sheet = tester.getRect(find.byType(CalendarSettingsSheet));
      double left(Finder finder) {
        return tester.getRect(finder).left;
      }

      double right(Finder finder) {
        return tester.getRect(finder).right;
      }

      final start = sheet.left + 24.0;
      final end = sheet.right - 24.0;
      expect(left(find.textContaining("Time zone")), start);
      expect(left(find.byKey(zoneChoicesKey)), start);
      expect(left(find.text("Days shown")), start);
      expect(left(find.text("Slot length")), start);
      expect(left(find.textContaining("Hours")), start);
      expect(left(find.byKey(shownDaysKey)), start);
      expect(right(find.byKey(shownDaysKey)), end);
      expect(left(find.byKey(slotLengthKey)), start);
      expect(right(find.byKey(slotLengthKey)), end);
      expect(left(find.byKey(hoursSliderKey)), start);
      expect(right(find.byKey(hoursSliderKey)), end);
      expect(right(find.byKey(weekStartKey)), end);
      expect(right(find.byKey(hourLabelFormatKey)), end);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("E22 the sheet's compact AM/PM switch shows at three quarters "
      "of its Material size, 39 by 30 px", (tester) async {
    await pumpCalendar(tester);
    await openSettings(tester);
    final twelveHour = tester.getRect(find.byKey(hourLabelFormatKey));
    expect(twelveHour.size, const Size(39.0, 30.0));
  });

  testWidgets("E23 the sheet lists the time zone, the days, the slot length, "
      "the hours and the overlap switch, offering the slot length once", (
    tester,
  ) async {
    await pumpCalendar(tester);
    await openSettings(tester);
    const order = <ValueKey<String>>[
      zoneChoicesKey,
      shownDaysKey,
      slotLengthKey,
      hoursSliderKey,
      allowsOverlapsKey,
    ];
    for (var index = 1; index < order.length; index++) {
      expect(
        tester.getRect(find.byKey(order[index])).top,
        greaterThan(tester.getRect(find.byKey(order[index - 1])).top),
        reason: "${order[index].value} under ${order[index - 1].value}",
      );
    }
    expect(find.text("Slot length"), findsOneWidget);
  });
}
