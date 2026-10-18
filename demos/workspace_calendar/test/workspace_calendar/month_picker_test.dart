/// The month picker the header's title opens: in place of the card's days
/// in Agenda and Day, under the header in Week and Month.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_data.dart';
import 'package:workspace_calendar/workspace_calendar/day_cell.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/month_picker.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';
import 'package:workspace_calendar/workspace_calendar/week_strip.dart';
import 'package:workspace_calendar/workspace_calendar_example.dart';

import 'calendar_harness.dart';

Finder monthCellFinder(int year, int month) {
  return find.byKey(monthPickerMonthKey(DateTime(year, month)));
}

MonthCell monthCell(WidgetTester tester, int year, int month) {
  return tester.widget<MonthCell>(
    find.descendant(
      of: monthCellFinder(year, month),
      matching: find.byType(MonthCell),
    ),
  );
}

/// The name on [year]'s [month] in the picker.
Finder monthName(int year, int month) {
  return find.descendant(
    of: monthCellFinder(year, month),
    matching: find.text(monthNames[month - 1]),
  );
}

/// [year]'s months in rows of three, January first.
List<List<DateTime>> yearRows(int year) {
  return <List<DateTime>>[
    for (var row = 0; row < 4; row++)
      <DateTime>[
        for (var column = 1; column <= 3; column++)
          DateTime(year, row * 3 + column),
      ],
  ];
}

/// The months whose cells' middles the picker shows, in rows from the top,
/// each row's from the left.
List<List<DateTime>> pickerRows(WidgetTester tester) {
  final picker = tester.getRect(find.byType(MonthPicker));
  final cells = <({Rect rect, DateTime month})>[];
  final found = find.descendant(
    of: find.byType(MonthPicker),
    matching: find.byType(MonthCell),
  );
  for (final element in found.evaluate()) {
    final box = element.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (picker.contains(rect.center)) {
      cells.add((rect: rect, month: (element.widget as MonthCell).month));
    }
  }
  cells.sort((a, b) {
    final byTop = a.rect.top.compareTo(b.rect.top);
    return byTop != 0 ? byTop : a.rect.left.compareTo(b.rect.left);
  });
  final rows = <List<DateTime>>[];
  double? top;
  for (final cell in cells) {
    if (cell.rect.top != top) {
      rows.add(<DateTime>[]);
      top = cell.rect.top;
    }
    rows.last.add(cell.month);
  }
  return rows;
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

/// The window of Agenda's and Day's card over the month board.
final Finder calendarGrid = find.byKey(const ValueKey<String>("calendar-grid"));

/// The height of Agenda's and Day's card under its header, frame by frame,
/// over the frames after a tap that opens or closes the picker, until it
/// settles, calling [atMiddle] half the way through.
Future<List<double>> areaHeights(
  WidgetTester tester, {
  void Function()? atMiddle,
}) async {
  final heights = <double>[];
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    heights.add(tester.getSize(find.byKey(calendarDaysAreaKey)).height);
    if (i == 9) {
      atMiddle?.call();
    }
  }
  await tester.pumpAndSettle();
  return heights;
}

/// That [heights] move from [from] to [to] smoothly: always the same way,
/// through at least five frames between them, none more than a quarter of
/// the way at once, and end on [to].
void expectSmooth(List<double> heights, double from, double to) {
  var last = from;
  var between = 0;
  for (final height in heights) {
    expect((height - last) * (to - from), greaterThanOrEqualTo(0.0));
    expect((height - last).abs(), lessThanOrEqualTo((to - from).abs() / 4));
    if (height != from && height != to) {
      between++;
    }
    last = height;
  }
  expect(between, greaterThanOrEqualTo(5));
  expect(heights.last, moreOrLessEquals(to));
}

void main() {
  testWidgets("P1 in Agenda the title shows the selected day's year's "
      "months in four rows of three in the card's days' place, filling the "
      "selected month and ringing today's, and names the year, whose "
      "chevrons step a year", (tester) async {
    await pumpCalendar(tester);
    await openPicker(tester);
    expect(pickerRows(tester), yearRows(2026));
    expect(find.byKey(dayCellKey(today)), findsNothing);
    expect(find.byKey(const ValueKey<String>("weekday-header")), findsNothing);
    expect(find.byKey(calendarPullTabKey), findsNothing);
    expect(pickerTitle("2026"), findsOneWidget);
    expect(monthCell(tester, 2026, 4).isSelected, isTrue);
    expect(monthCell(tester, 2026, 4).isCurrent, isTrue);
    expect(monthCell(tester, 2026, 5).isSelected, isFalse);
    expect(monthCell(tester, 2026, 5).isCurrent, isFalse);

    await tester.tap(find.byTooltip("Next year"));
    await tester.pumpAndSettle();
    expect(pickerTitle("2027"), findsOneWidget);
    expect(pickerRows(tester), yearRows(2027));
    await tester.tap(find.byTooltip("Previous year"));
    await tester.pumpAndSettle();
    expect(pickerRows(tester), yearRows(2026));
  });

  testWidgets("P2 a month picked selects the selected day's day of it and "
      "shows its month; the title tapped again closes the picker with no "
      "pick, the card showing its days as they were, unfolded or folded", (
    tester,
  ) async {
    await pumpCalendar(tester);
    // April and June 2026 are five weeks each.
    final month = tester.getSize(calendarGrid).height;
    await openPicker(tester);
    await pickMonth(tester, 2026, 6);
    expect(find.byType(MonthPicker), findsNothing);
    expect(find.text("Jun 2026"), findsOneWidget);
    expect(dayCell(tester, DateTime(2026, 6, 21)).isSelected, isTrue);
    expect(tester.getSize(calendarGrid).height, month);

    await openPicker(tester);
    await tester.tap(find.byTooltip("Close the months"));
    await tester.pumpAndSettle();
    expect(find.byType(MonthPicker), findsNothing);
    expect(tester.getSize(calendarGrid).height, month);
    expect(dayCell(tester, DateTime(2026, 6, 21)).isSelected, isTrue);

    await tester.tap(find.byKey(calendarPullTabKey));
    await tester.pumpAndSettle();
    await openPicker(tester);
    expect(find.byType(WeekStrip), findsNothing);
    await tester.tap(find.byTooltip("Close the months"));
    await tester.pumpAndSettle();
    expect(find.byType(MonthPicker), findsNothing);
    expect(find.byType(WeekStrip), findsOneWidget);
  });

  testWidgets("P3 a drag slides the picker with the finger, the next year "
      "coming in from the right, the title naming the nearest year, and a "
      "release that is no fling comes to rest on the nearest", (tester) async {
    await pumpCalendar(tester);
    await openPicker(tester);
    final picker = tester.getRect(find.byType(MonthPicker));
    final gesture = await tester.startGesture(picker.center);
    await gesture.moveBy(const Offset(-20.0, 0.0));
    await tester.pump();
    final start = tester.getRect(monthCellFinder(2026, 1)).left;
    await gesture.moveBy(Offset(-0.4 * picker.width, 0.0));
    await tester.pump();
    final january = tester.getRect(monthCellFinder(2026, 1)).left;
    expect(january, moreOrLessEquals(start - 0.4 * picker.width));
    expect(
      tester.getRect(monthCellFinder(2027, 1)).left,
      moreOrLessEquals(january + picker.width),
    );
    expect(pickerTitle("2026"), findsOneWidget);
    await gesture.moveBy(Offset(-0.2 * picker.width, 0.0));
    await tester.pump();
    expect(pickerTitle("2027"), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(pickerRows(tester), yearRows(2027));
    expect(pickerTitle("2027"), findsOneWidget);

    await tester.drag(find.byType(MonthPicker), const Offset(60.0, 0.0));
    await tester.pumpAndSettle();
    expect(pickerRows(tester), yearRows(2027));
  });

  testWidgets("P4 a fling over the picker slides it to the next year the way "
      "it moves", (tester) async {
    await pumpCalendar(tester);
    await openPicker(tester);
    await tester.fling(
      find.byType(MonthPicker),
      const Offset(-60.0, 0.0),
      1000.0,
    );
    await tester.pumpAndSettle();
    expect(pickerRows(tester), yearRows(2027));
    expect(pickerTitle("2027"), findsOneWidget);
    await tester.fling(
      find.byType(MonthPicker),
      const Offset(60.0, 0.0),
      1000.0,
    );
    await tester.pumpAndSettle();
    expect(pickerRows(tester), yearRows(2026));
    expect(pickerTitle("2026"), findsOneWidget);
  });

  testWidgets("P5 in Day the picker takes the folded strip's place, and a "
      "pick brings back its month unfolded, the strip never showing", (
    tester,
  ) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Day");
    await openPicker(tester);
    expect(find.byType(MonthPicker), findsOneWidget);
    expect(find.byType(WeekStrip), findsNothing);
    await tester.tap(monthCellFinder(2026, 5));
    final may21 = find.byKey(dayCellKey(DateTime(2026, 5, 21)));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(WeekStrip), findsNothing);
      // May 2026 is five weeks, which the card shows whole whenever it
      // shows the days.
      if (may21.evaluate().isNotEmpty) {
        expect(
          tester.getSize(calendarGrid).height,
          moreOrLessEquals(5 * tester.getSize(may21).height),
        );
      }
    }
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    expect(dayCell(tester, DateTime(2026, 5, 21)).isSelected, isTrue);
    expect(gridDay(tester), DateTime(2026, 5, 21));
  });

  testWidgets("P6 in Week and Month the picker opens under the header, its "
      "chevrons stepping its year, and a pick selects the selected day's day "
      "of its month", (tester) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Week");
    await openPicker(tester);
    expect(find.byType(MonthPicker), findsOneWidget);
    await tester.tap(find.byTooltip("Next year"));
    await tester.pumpAndSettle();
    expect(pickerRows(tester), yearRows(2027));
    await tester.tap(find.byTooltip("Previous year"));
    await tester.pumpAndSettle();
    expect(pickerRows(tester), yearRows(2026));
    await pickMonth(tester, 2026, 7);
    expect(find.byType(MonthPicker), findsNothing);
    expect(find.byKey(dayHeaderKey(DateTime(2026, 7, 21))), findsOneWidget);

    await pickMode(tester, "Month");
    await openPicker(tester);
    expect(find.byType(MonthPicker), findsOneWidget);
    await pickMonth(tester, 2026, 9);
    expect(find.text("Sep 2026"), findsOneWidget);
  });

  testWidgets("P7 a change of view, or Today, closes the picker", (
    tester,
  ) async {
    await pumpCalendar(tester);
    await openPicker(tester);
    await pickMode(tester, "Week");
    expect(find.byType(MonthPicker), findsNothing);
    expect(find.byTooltip("Next week"), findsOneWidget);

    await openPicker(tester);
    await tapToday(tester);
    await tester.pumpAndSettle();
    expect(find.byType(MonthPicker), findsNothing);
  });

  testWidgets("P8 a second year step mid-slide carries the picker on, the "
      "title never naming a year it passes", (tester) async {
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
    expect(pickerRows(tester), yearRows(2028));
  });

  testWidgets("P9 a pick whose day of the month falls on a hidden weekday "
      "selects the next shown day of that month", (tester) async {
    await pumpCalendar(tester);
    await openBar(tester);
    flipWeekends(tester);
    await tester.pumpAndSettle();
    await closeBar(tester);
    await openPicker(tester);
    // June 21 is a Sunday.
    await pickMonth(tester, 2026, 6);
    expect(dayCell(tester, DateTime(2026, 6, 22)).isSelected, isTrue);
  });

  testWidgets("P10 every month reads its full name and no year, on a cell "
      "as large as January's, and a screen reader hears every month with "
      "its year", (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCalendar(tester);
    await openPicker(tester);
    final january = tester.getSize(monthCellFinder(2026, 1));
    for (var month = 1; month <= 12; month++) {
      expect(monthName(2026, month), findsOneWidget);
      expect(
        find.descendant(
          of: monthCellFinder(2026, month),
          matching: find.text("2026"),
        ),
        findsNothing,
      );
      expect(tester.getSize(monthCellFinder(2026, month)), january);
      expect(
        tester.getSemantics(monthCellFinder(2026, month)),
        isSemantics(label: "${monthNames[month - 1]} 2026"),
      );
    }
    semantics.dispose();
  });

  testWidgets("P11 at 1.3 times the text size, every name reads at it "
      "where September fits its pill at it, and on the phone, where it does "
      "not, at the one smaller size that fits September", (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpCalendar(tester, size: const Size(1100.0, 900.0));
    await openPicker(tester);
    for (var month = 1; month <= 12; month++) {
      expect(
        tester
            .renderObject<RenderParagraph>(monthName(2026, month))
            .textScaler
            .scale(1.0),
        1.3,
      );
    }

    tester.view.physicalSize = const Size(390.0, 844.0);
    await tester.pumpAndSettle();
    final september = tester.renderObject<RenderParagraph>(monthName(2026, 9));
    final scaler = september.textScaler;
    expect(scaler.scale(1.0), lessThan(1.3));
    final room =
        tester.getSize(monthCellFinder(2026, 9)).width -
        MonthCell.pillMargin.horizontal -
        MonthCell.pillPadding.horizontal;
    final width = september.getMaxIntrinsicWidth(double.infinity);
    expect(width, lessThanOrEqualTo(room));
    expect(width, greaterThan(room - 2.0));
    for (var month = 1; month <= 12; month++) {
      expect(
        tester.renderObject<RenderParagraph>(monthName(2026, month)).textScaler,
        scaler,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets("P12 at twice the text size on a wide screen each pill is as "
      "tall as its name, every cell as large as January's", (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpCalendar(tester, size: const Size(1100.0, 900.0));
    await openPicker(tester);
    final january = tester.getSize(monthCellFinder(2026, 1));
    // Setup sanity: the name is taller than a day's circle.
    expect(
      tester.getSize(monthName(2026, 1)).height,
      greaterThan(dayCircleSize),
    );
    for (var month = 1; month <= 12; month++) {
      final cell = tester.getSize(monthCellFinder(2026, month));
      expect(cell, january);
      expect(
        cell.height,
        moreOrLessEquals(
          tester.getSize(monthName(2026, month)).height +
              MonthCell.pillMargin.vertical,
        ),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets("P13 the picker and Agenda's month, or Day's strip, fade "
      "into each other as the card's height moves smoothly from one's to "
      "the other's, opening, closing and picking", (tester) async {
    await pumpCalendar(tester);
    final area = find.byKey(calendarDaysAreaKey);
    final month = tester.getSize(area).height;
    await tester.tap(find.byTooltip("Pick a month"));
    var both = false;
    final opening = await areaHeights(
      tester,
      atMiddle: () {
        both =
            find.byType(MonthPicker).evaluate().length == 1 &&
            find.byKey(dayCellKey(today)).evaluate().length == 1;
      },
    );
    final picker = tester.getSize(area).height;
    // Setup sanity: the picker is shorter than the month.
    expect(picker, lessThan(month));
    expect(both, isTrue);
    expectSmooth(opening, month, picker);
    await tester.tap(find.byTooltip("Close the months"));
    expectSmooth(await areaHeights(tester), picker, month);

    await pickMode(tester, "Day");
    final strip = tester.getSize(area).height;
    // Setup sanity: the picker is taller than the strip.
    expect(picker, greaterThan(strip));
    await tester.tap(find.byTooltip("Pick a month"));
    expectSmooth(await areaHeights(tester), strip, picker);
    await tester.tap(monthCellFinder(2026, 4));
    expectSmooth(await areaHeights(tester), picker, month);
  });

  testWidgets("P14 while the picker comes in only it takes taps, and while "
      "it goes out only the days do", (tester) async {
    await pumpCalendar(tester);
    final april27 = tester.getRect(
      find.byKey(dayCellKey(DateTime(2026, 4, 27))),
    );
    final onApril27 = Offset(april27.center.dx, april27.top + 4.0);
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pump();
    await tester.pump(harborMotionDuration ~/ 4);
    // Setup sanity: the card still shows the top of April 27, under the
    // picker's bottom.
    expect(
      tester.getRect(find.byKey(calendarDaysAreaKey)).bottom,
      greaterThan(onApril27.dy),
    );
    expect(
      tester.getRect(find.byType(MonthPicker)).bottom,
      lessThan(onApril27.dy),
    );
    await tester.tapAt(onApril27);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Close the months"));
    await tester.pumpAndSettle();
    expect(dayCell(tester, DateTime(2026, 4, 27)).isSelected, isFalse);

    await openPicker(tester);
    await tester.tap(find.byTooltip("Close the months"));
    await tester.pump();
    await tester.pump(harborMotionDuration ~/ 2);
    await tester.tapAt(tester.getCenter(monthCellFinder(2026, 5)));
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    expect(find.text("May 2026"), findsNothing);
  });
}
