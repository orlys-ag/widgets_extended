/// The calendar's clock: the day it marks as today, which moves at
/// midnight unless the host gives one, and the timed grid's line, which
/// moves with it.
library;

import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';

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

/// The foreground decoration of the one [Container] under [finder] that
/// has one, the ring around today's number; null when none has one.
BoxDecoration? ringIn(WidgetTester tester, Finder finder) {
  final rings = tester
      .widgetList<Container>(
        find.descendant(of: finder, matching: find.byType(Container)),
      )
      .map((container) => container.foregroundDecoration)
      .whereType<BoxDecoration>()
      .toList();
  return rings.isEmpty ? null : rings.single;
}

/// A 2 px ring in [HarborColors.todayRing] on every side.
final Matcher isTodayRing = predicate<BoxDecoration?>((decoration) {
  final border = decoration?.border;
  return border is Border &&
      border.isUniform &&
      border.top.color == HarborColors.todayRing &&
      border.top.width == 2.0;
}, "a 2 px ring in the today ring colour");

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

/// The lines the week grid's foreground draws in the colour of the line
/// marking the current time.
List<CanvasRecord> nowLines(WidgetTester tester) {
  return paintGridForeground(tester).lines.where((line) {
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

  testWidgets("N5 every view rings today's number in the lighter blue, and "
      "Month rings it over the selected day's fill", (tester) async {
    await pumpCalendar(tester);
    await tester.tap(find.byKey(dayCellKey(thursday)));
    await tester.pumpAndSettle();
    expect(ringIn(tester, find.byKey(dayCellKey(tuesday))), isTodayRing);
    expect(ringIn(tester, find.byKey(dayCellKey(thursday))), isNull);

    await pickMode(tester, "Week");
    expect(ringIn(tester, find.byKey(dayHeaderKey(tuesday))), isTodayRing);
    expect(ringIn(tester, find.byKey(dayHeaderKey(thursday))), isNull);

    await pickMode(tester, "Day");
    expect(ringIn(tester, find.byKey(weekStripDayKey(tuesday))), isTodayRing);
    expect(ringIn(tester, find.byKey(weekStripDayKey(thursday))), isNull);

    await pickMode(tester, "Month");
    expect(ringIn(tester, find.byKey(monthStripKey(tuesday))), isTodayRing);
    expect(ringIn(tester, find.byKey(monthStripKey(thursday))), isNull);

    // Today selected: the pill's fill, and the ring over it.
    await pickMode(tester, "Day");
    await tester.tap(find.byKey(weekStripDayKey(tuesday)));
    await tester.pumpAndSettle();
    await pickMode(tester, "Month");
    final number = find.descendant(
      of: find.byKey(monthStripKey(tuesday)),
      matching: find.byType(Container),
    );
    final fill = tester.widget<Container>(number).decoration as BoxDecoration?;
    expect(fill?.color, HarborColors.primary);
    expect(ringIn(tester, find.byKey(monthStripKey(tuesday))), isTodayRing);
  });
}
