/// The calendar's clock: the day it marks as today, which moves at
/// midnight unless the host gives one, and the timed grid's line, which
/// moves with it.
library;

import 'package:workspace_calendar/workspace_calendar/day_cell.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_harness.dart';

/// A size tall enough that the week grid shows every row of the day
/// without scrolling.
const Size wholeDay = Size(390.0, 2000.0);

/// Layout rounds track offsets, so geometry is compared to half a pixel.
Matcher nearOffset(Offset value) {
  return offsetMoreOrLessEquals(value, epsilon: 0.5);
}

/// Whether the month grid's cell of [day] is marked as today.
bool isToday(WidgetTester tester, DateTime day) {
  return tester.widget<DayCell>(find.byKey(dayCellKey(day))).isToday;
}

bool isSelected(WidgetTester tester, DateTime day) {
  return tester.widget<DayCell>(find.byKey(dayCellKey(day))).isSelected;
}

/// The colour of the day number in the week grid's header cell of [day].
Color? headerNumberColor(WidgetTester tester, DateTime day) {
  final number = find.descendant(
    of: find.byKey(dayHeaderKey(day)),
    matching: find.text("${day.day}"),
  );
  return tester.widget<Text>(number).style!.color;
}

/// Whether the week grid's background fills part of column [col] in the
/// primary tint.
bool isTinted(WidgetTester tester, int col) {
  final column = gridViewport(tester).rectOfCell(rowOf(12 * 60), col)!;
  return paintGridBackground(tester).fillsOf(HarborColors.primaryTint).any((
    rect,
  ) {
    return rect.left < column.right && rect.right > column.left;
  });
}

/// The lines the week grid's background draws in the colour of the line
/// marking the current time.
List<CanvasRecord> nowLines(WidgetTester tester) {
  return paintGridBackground(tester).lines.where((line) {
    return line.isIn(HarborColors.error);
  }).toList();
}

void main() {
  final tuesday = DateTime(2026, 4, 21);
  final wednesday = DateTime(2026, 4, 22);
  final thursday = DateTime(2026, 4, 23);

  testWidgets("N1 the month marks the clock's day as today, and moves the "
      "mark at midnight while the selection stays", (tester) async {
    var now = DateTime(2026, 4, 21, 23, 59);
    await pumpCalendar(
      tester,
      pinsToday: false,
      clock: () {
        return now;
      },
    );
    expect(isToday(tester, tuesday), isTrue);
    expect(isToday(tester, wednesday), isFalse);
    expect(find.text("Today, April 21"), findsOneWidget);

    now = DateTime(2026, 4, 22);
    await tester.pump(const Duration(minutes: 1));
    expect(isToday(tester, tuesday), isFalse);
    expect(isToday(tester, wednesday), isTrue);
    expect(find.text("Yesterday, April 21"), findsOneWidget);
    expect(isSelected(tester, tuesday), isTrue);
    expect(isSelected(tester, wednesday), isFalse);
  });

  testWidgets("N2 the week grid moves today's tint, its header and the "
      "line together at midnight", (tester) async {
    var now = DateTime(2026, 4, 21, 23, 59);
    await pumpCalendar(
      tester,
      size: wholeDay,
      pinsToday: false,
      clock: () {
        return now;
      },
    );
    await pickMode(tester, "Week");
    final viewport = gridViewport(tester);
    expect(isTinted(tester, colOf(1)), isTrue);
    expect(isTinted(tester, colOf(2)), isFalse);
    expect(headerNumberColor(tester, tuesday), HarborColors.primary);
    expect(headerNumberColor(tester, wednesday), HarborColors.text);
    var slot = viewport.visibleCellRect(rowOf(23 * 60 + 45), colOf(1));
    expect(nowLines(tester), hasLength(1));
    expect(
      nowLines(tester).single.from,
      nearOffset(Offset(slot.left, slot.top + 14 / 15 * slot.height)),
    );

    now = DateTime(2026, 4, 22);
    await tester.pump(const Duration(minutes: 1));
    expect(isTinted(tester, colOf(1)), isFalse);
    expect(isTinted(tester, colOf(2)), isTrue);
    expect(headerNumberColor(tester, tuesday), HarborColors.text);
    expect(headerNumberColor(tester, wednesday), HarborColors.primary);
    slot = viewport.visibleCellRect(rowOf(0), colOf(2));
    expect(nowLines(tester), hasLength(1));
    expect(nowLines(tester).single.from, nearOffset(slot.topLeft));
  });

  testWidgets("N3 a day the host gives stays today past midnight", (
    tester,
  ) async {
    var now = DateTime(2026, 4, 21, 23, 59);
    await pumpCalendar(
      tester,
      clock: () {
        return now;
      },
    );

    now = DateTime(2026, 4, 22);
    await tester.pump(const Duration(minutes: 1));
    expect(isToday(tester, tuesday), isTrue);
    expect(isToday(tester, wednesday), isFalse);
    expect(find.text("Today, April 21"), findsOneWidget);
  });

  testWidgets("N4 a new clock or a new day from the host applies at once", (
    tester,
  ) async {
    DateTime tuesdayMorning() {
      return DateTime(2026, 4, 21, 10);
    }

    DateTime wednesdayNoon() {
      return DateTime(2026, 4, 22, 12);
    }

    final api = await pumpCalendar(
      tester,
      size: wholeDay,
      pinsToday: false,
      clock: tuesdayMorning,
    );
    await pickMode(tester, "Week");
    final viewport = gridViewport(tester);
    expect(isTinted(tester, colOf(1)), isTrue);

    await tester.pumpWidget(calendarApp(api: api, clock: wednesdayNoon));
    expect(isTinted(tester, colOf(1)), isFalse);
    expect(isTinted(tester, colOf(2)), isTrue);
    expect(headerNumberColor(tester, wednesday), HarborColors.primary);
    final slot = viewport.visibleCellRect(rowOf(12 * 60), colOf(2));
    expect(nowLines(tester), hasLength(1));
    expect(nowLines(tester).single.from, nearOffset(slot.topLeft));

    await tester.pumpWidget(
      calendarApp(api: api, today: thursday, clock: wednesdayNoon),
    );
    expect(isTinted(tester, colOf(2)), isFalse);
    expect(isTinted(tester, colOf(3)), isTrue);
    expect(headerNumberColor(tester, thursday), HarborColors.primary);
    expect(nowLines(tester), hasLength(1));
    expect(nowLines(tester).single.from, nearOffset(slot.topLeft));
  });
}
