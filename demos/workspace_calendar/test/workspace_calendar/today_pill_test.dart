/// The app bar's Today pill: when it shows, on the clock of the store's
/// zone and past midnight, how it fades and keeps its width, and what a
/// tap on it does.
library;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/settings_sheet.dart';

import 'calendar_harness.dart';

/// The pill's opacity as it paints now: that of the fade its nearest
/// [AnimatedOpacity] builds.
double pillOpacity(WidgetTester tester) {
  final animated = find
      .ancestor(of: todayButtonFinder(), matching: find.byType(AnimatedOpacity))
      .first;
  return tester
      .widget<FadeTransition>(
        find.descendant(of: animated, matching: find.byType(FadeTransition)).first,
      )
      .opacity
      .value;
}

/// Whether the pill shows: painted whole, taking pointers, focus and a
/// screen reader's attention as a button named Today; each of them is
/// checked against the others, so a pill half shown fails.
bool pillShows(WidgetTester tester) {
  final opacity = pillOpacity(tester);
  final hit = todayButtonFinder().hitTestable().evaluate().isNotEmpty;
  final focusable = Focus.of(
    tester.element(
      find.descendant(of: todayButtonFinder(), matching: find.text("Today")),
    ),
  ).canRequestFocus;
  // Searched in the semantics tree itself: a render object keeps the node
  // it last had after an ExcludeSemantics drops it from the tree.
  final heard = find.semantics
      .byPredicate((node) {
        return isSemantics(
          label: "Today",
          isButton: true,
        ).matches(node, <dynamic, dynamic>{});
      })
      .evaluate()
      .isNotEmpty;
  final shown = <bool>[opacity == 1.0, hit, focusable, heard];
  final hidden = <bool>[opacity == 0.0, !hit, !focusable, !heard];
  if (shown.every((value) => value)) {
    return true;
  }
  if (hidden.every((value) => value)) {
    return false;
  }
  fail(
    "The pill is half shown: opacity $opacity, hit-testable $hit, "
    "focusable $focusable, heard $heard.",
  );
}

/// The calendar's controller.
CalendarController controllerOf(WidgetTester tester) {
  return tester
      .widget<CalendarView<ItemPayload>>(find.byType(CalendarView<ItemPayload>))
      .controller!;
}

/// The calendar's store.
CalendarStore<ItemPayload> storeOf(WidgetTester tester) {
  return tester
      .widget<CalendarView<ItemPayload>>(find.byType(CalendarView<ItemPayload>))
      .store;
}

/// Whether Agenda's calendar card shows [day] selected.
bool isSelected(WidgetTester tester, DateTime day) {
  return tester.widget<DayCell>(find.byKey(dayCellKey(day))).isSelected;
}

/// Taps [day] in Agenda's calendar card and lets the pill settle.
Future<void> tapDay(WidgetTester tester, DateTime day) async {
  await tester.tap(find.byKey(dayCellKey(day)).hitTestable());
  await tester.pumpAndSettle();
}

/// A zone of one offset, the device's at [on] plus [hours].
tz.Location zoneAhead(DateTime on, int hours) {
  final name = "Test/Ahead$hours";
  return tz.Location(name, <int>[tz.minTime], <int>[0], <tz.TimeZone>[
    tz.TimeZone(
      on.timeZoneOffset + Duration(hours: hours),
      isDst: false,
      abbreviation: name,
    ),
  ]);
}

void main() {
  final april22 = DateTime(2026, 4, 22);
  final april23 = DateTime(2026, 4, 23);

  testWidgets("TP1 on today, the pill is hidden: unpainted, and taking no "
      "pointer, focus or screen reader, while it keeps its width in the "
      "app bar", (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCalendar(tester);
    // The app bar lines its actions up from its end, so the zone button,
    // before the pill, moves with the pill's width.
    final zone = find.widgetWithIcon(TextButton, Icons.public);
    final hiddenRight = tester.getRect(zone).right;
    // Setup sanity: the calendar opened on today, its card on today's month.
    expect(isSelected(tester, today), isTrue);
    expect(controllerOf(tester).showsSelectedDay, isTrue);
    expect(pillShows(tester), isFalse);

    await tapDay(tester, april23);
    expect(pillShows(tester), isTrue);
    expect(tester.getRect(zone).right, hiddenRight);
    semantics.dispose();
  });

  testWidgets("TP2 another day fades the pill in over the Harbor motion, "
      "and a tap on it fades it out, taking no pointer from the tap on", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpCalendar(tester);
    final half = harborMotionDuration ~/ 2;

    await tester.tap(find.byKey(dayCellKey(april23)).hitTestable());
    await tester.pump();
    await tester.pump(half);
    expect(pillOpacity(tester), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(pillShows(tester), isTrue);

    await tapToday(tester);
    await tester.pump();
    expect(todayButtonFinder().hitTestable(), findsNothing);
    await tester.pump(half);
    expect(pillOpacity(tester), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(pillShows(tester), isFalse);
    semantics.dispose();
  });

  testWidgets("TP3 selecting today in the calendar hides the pill", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpCalendar(tester);
    await tapDay(tester, april23);
    // Setup sanity: another day is selected, and the pill shows.
    expect(isSelected(tester, april23), isTrue);
    expect(pillShows(tester), isTrue);

    await tapDay(tester, today);
    expect(isSelected(tester, today), isTrue);
    expect(pillShows(tester), isFalse);
    semantics.dispose();
  });

  testWidgets("TP4 with today selected, the pill shows while the card shows "
      "another month, the month picker shows, or a drag has moved the "
      "strip off today, and a tap brings each back", (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpCalendar(tester);

    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    // Setup sanity: the card left today's month, today still selected.
    expect(find.text("May 2026"), findsOneWidget);
    expect(controllerOf(tester).selectedDay, today);
    expect(pillShows(tester), isTrue);
    await tester.tap(find.byTooltip("Previous month"));
    await tester.pumpAndSettle();
    expect(find.text("Apr 2026"), findsOneWidget);
    expect(pillShows(tester), isFalse);

    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    const picker = ValueKey<String>("month-picker");
    expect(find.byKey(picker), findsOneWidget);
    expect(pillShows(tester), isTrue);
    await tapToday(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(picker), findsNothing);
    expect(pillShows(tester), isFalse);

    await pickMode(tester, "Day");
    final strip = find.byType(WeekStrip<ItemPayload>);
    final todayInStrip = find.byKey(weekStripDayKey(today)).hitTestable();
    expect(todayInStrip, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(strip));
    await gesture.moveBy(const Offset(-(kTouchSlop + 1.0), 0.0));
    await tester.pump();
    await gesture.moveBy(Offset(-tester.getSize(strip).width, 0.0));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    // Setup sanity: the drag moved the strip off today, still selected.
    expect(todayInStrip, findsNothing);
    expect(controllerOf(tester).selectedDay, today);
    expect(pillShows(tester), isTrue);
    await tapToday(tester);
    await tester.pumpAndSettle();
    expect(todayInStrip, findsOneWidget);
    expect(pillShows(tester), isFalse);
    semantics.dispose();
  });

  testWidgets("TP5 the pill reads today on the clock of the store's zone, "
      "and a tap selects that zone's today", (tester) async {
    final semantics = tester.ensureSemantics();
    final noon = DateTime(2026, 4, 21, 12);
    final api = await pumpCalendar(
      tester,
      pinsToday: false,
      clock: () {
        return noon;
      },
    );
    final zone = zoneAhead(noon, 13);
    // Setup sanity: the zone reads the next day at the clock's noon, and
    // the calendar opened on the device's today.
    expect(
      CalendarDates.dayNumber(CalendarDates.inZone(noon, zone: zone)),
      CalendarDates.dayNumber(april22),
    );
    expect(isSelected(tester, today), isTrue);
    expect(pillShows(tester), isFalse);

    storeOf(tester).zone = zone;
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    // Setup sanity: the selected day keeps its date on the zone's clock.
    expect(
      CalendarDates.dayNumber(controllerOf(tester).selectedDay),
      CalendarDates.dayNumber(today),
    );
    expect(pillShows(tester), isTrue);

    await tapToday(tester);
    await tester.pumpAndSettle();
    expect(
      CalendarDates.dayNumber(controllerOf(tester).selectedDay),
      CalendarDates.dayNumber(april22),
    );
    expect(pillShows(tester), isFalse);
    semantics.dispose();
  });

  testWidgets("TP6 the pill shows once midnight leaves the selected day "
      "behind", (tester) async {
    final semantics = tester.ensureSemantics();
    var now = DateTime(2026, 4, 21, 23, 59, 30);
    await pumpCalendar(
      tester,
      pinsToday: false,
      clock: () {
        return now;
      },
    );
    // Setup sanity: the calendar opened on the clock's day.
    expect(isSelected(tester, today), isTrue);
    expect(pillShows(tester), isFalse);

    now = DateTime(2026, 4, 22, 0, 0, 30);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    // Setup sanity: the selection stayed on the day before.
    expect(isSelected(tester, today), isTrue);
    expect(pillShows(tester), isTrue);
    semantics.dispose();
  });

  testWidgets("TP7 where today's weekday is hidden, the pill hides on the "
      "shown day nearest today, which a tap on it would select", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpCalendar(tester);
    await tapDay(tester, april22);
    // Setup sanity: Wednesday is selected, so the pill shows.
    expect(isSelected(tester, april22), isTrue);
    expect(pillShows(tester), isTrue);

    await openSettings(tester);
    final days = tester.widget<SegmentedButton<int>>(find.byKey(shownDaysKey));
    days.onSelectionChanged!(days.selected.difference(const <int>{1}));
    await tester.pumpAndSettle();
    await closeSettings(tester);
    // Setup sanity: Tuesday, today's weekday, is hidden, and Wednesday is
    // still selected.
    expect(find.byKey(dayCellKey(today)), findsNothing);
    expect(isSelected(tester, april22), isTrue);
    expect(pillShows(tester), isFalse);
    semantics.dispose();
  });
}
