/// What a change of view leaves of the calendar card and the month picker:
/// the card opens on its month in every view; a change of view, a pick of
/// the view shown, a tap on a day in Month, new views and a new controller
/// included, keeps the card's fold, the month a chevron moved it to, the
/// days a drag moved its strip to and an open month picker on its year;
/// Week and Month, which show no card, show the selected day's week or
/// month and name its month, the card waiting for Agenda and Day.
library;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/composition/calendar_card.dart';
import 'package:widgets_extended/calendar/composition/calendar_header.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

final DateTime tuesday = DateTime(2026, 4, 21);

/// 11:07 on Tuesday April 21 2026.
DateTime fixedClock() {
  return DateTime(2026, 4, 21, 11, 7);
}

/// [home] under a MaterialApp with no Scaffold and no ink splash, whose
/// shader a widget test cannot load.
Widget app(Widget home) {
  return MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: home,
  );
}

const ValueKey<String> picker = ValueKey<String>("month-picker");

/// The Today button where a pointer reaches it, which is while it shows.
Finder get todayHit {
  return find.byKey(calendarTodayButtonKey).hitTestable();
}

/// [text] in the header.
Finder inHeader(String text) {
  return find.descendant(
    of: find.byType(CalendarHeader),
    matching: find.text(text),
  );
}

/// Whether the calendar card shows its week strip rather than its month:
/// folded whole with the strip built, or not folded at all without it.
bool folded(WidgetTester tester) {
  final fold = tester
      .widget<CalendarCard<String>>(find.byType(CalendarCard<String>))
      .collapse
      .value;
  final strip = find.byType(WeekStrip<String>).evaluate().isNotEmpty;
  if (fold == 1.0 && strip) {
    return true;
  }
  if (fold == 0.0 && !strip) {
    return false;
  }
  fail("The card is half folded: fold $fold, strip built $strip.");
}

/// Taps the card's pull tab, which folds or unfolds it, and lets it settle.
Future<void> tapPullTab(WidgetTester tester) async {
  await tester.tap(find.byKey(calendarPullTabKey));
  await tester.pumpAndSettle();
}

/// Picks the view [name] from the header's view menu.
Future<void> pickView(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(calendarViewButtonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(PopupMenuItem<CalendarViewKind>, name));
  await tester.pumpAndSettle();
}

/// Sets [view] through [controller] and lets the calendar settle.
Future<void> setView(
  WidgetTester tester,
  CalendarController controller,
  CalendarViewKind view,
) async {
  controller.view = view;
  await tester.pumpAndSettle();
}

/// The days of the card's week strip lying whole inside it, in order.
List<DateTime> stripDays(WidgetTester tester) {
  final strip = find.byType(WeekStrip<String>);
  final bounds = tester.getRect(strip);
  final days = <DateTime>[];
  final cells = find.descendant(of: strip, matching: find.byType(DayCell));
  for (final element in cells.evaluate()) {
    final box = element.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.left >= bounds.left - 0.01 && rect.right <= bounds.right + 0.01) {
      days.add((element.widget as DayCell).day);
    }
  }
  days.sort();
  return days;
}

/// Drags the card's week strip on by [days] days' widths, then lets it
/// rest, with no fling.
Future<void> dragStrip(WidgetTester tester, int days) async {
  final strip = find.byType(WeekStrip<String>);
  final day = tester.getSize(strip).width / DateTime.daysPerWeek;
  final gesture = await tester.startGesture(tester.getCenter(strip));
  await gesture.moveBy(const Offset(-(kTouchSlop + 1.0), 0.0));
  await tester.pump();
  await gesture.moveBy(Offset(-day * days, 0.0));
  await tester.pump(const Duration(milliseconds: 500));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  late MemoryCalendarStore<String> store;

  setUp(() {
    store = MemoryCalendarStore<String>();
  });

  tearDown(() {
    store.dispose();
  });

  testWidgets("VS1 the card opens on its month in Day, as in Agenda, and "
      "shows it on a first switch to Day from Week", (tester) async {
    final controller = CalendarController(view: CalendarViewKind.day);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Setup sanity: Day shows.
    expect(find.byType(TimedGrid<String>), findsOneWidget);
    expect(folded(tester), isFalse);

    await tester.pumpWidget(const SizedBox());
    final fromWeek = CalendarController(view: CalendarViewKind.week);
    addTearDown(fromWeek.dispose);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: fromWeek,
          clock: fixedClock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Setup sanity: Week shows no card.
    expect(find.byType(CalendarCard<String>), findsNothing);
    await pickView(tester, "Day");
    expect(folded(tester), isFalse);
  });

  testWidgets("VS2 a pick of the view shown changes nothing: Agenda's "
      "folded card, the month a chevron moved it to, an open month picker "
      "and Day's unfolded card stay, and the controller does not "
      "notify", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    var notified = 0;
    controller.addListener(() {
      notified++;
    });
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapPullTab(tester);
    // Setup sanity: Agenda's card folded.
    expect(controller.view, CalendarViewKind.agenda);
    expect(folded(tester), isTrue);
    notified = 0;
    await pickView(tester, "Agenda");
    expect(folded(tester), isTrue);
    expect(notified, 0);

    await tapPullTab(tester);
    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    // Setup sanity: the card moved to May, April 21 still selected.
    expect(inHeader("May 2026"), findsOneWidget);
    expect(controller.selectedDay, tuesday);
    notified = 0;
    await pickView(tester, "Agenda");
    expect(inHeader("May 2026"), findsOneWidget);
    expect(controller.showsSelectedDay, isFalse);
    expect(notified, 0);

    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    // Setup sanity: the picker shows.
    expect(find.byKey(picker), findsOneWidget);
    notified = 0;
    await pickView(tester, "Agenda");
    expect(find.byKey(picker), findsOneWidget);
    expect(notified, 0);

    await tester.tap(find.byTooltip("Close the months"));
    await tester.pumpAndSettle();
    await setView(tester, controller, CalendarViewKind.day);
    if (folded(tester)) {
      await tapPullTab(tester);
    }
    // Setup sanity: Day's card unfolded.
    expect(find.byType(TimedGrid<String>), findsOneWidget);
    expect(folded(tester), isFalse);
    notified = 0;
    await pickView(tester, "Day");
    expect(folded(tester), isFalse);
    expect(notified, 0);
  });

  testWidgets("VS3 Agenda and Day keep each other's fold, the month a "
      "chevron moved the card to and the days a drag moved its strip to, "
      "switched by the menu or by the controller", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Setup sanity: Agenda's card on its month.
    expect(find.byType(DayList<String>), findsOneWidget);
    expect(folded(tester), isFalse);
    await pickView(tester, "Day");
    expect(find.byType(TimedGrid<String>), findsOneWidget);
    expect(folded(tester), isFalse);

    await tapPullTab(tester);
    // Setup sanity: Day's card folded.
    expect(folded(tester), isTrue);
    await setView(tester, controller, CalendarViewKind.agenda);
    expect(find.byType(DayList<String>), findsOneWidget);
    expect(folded(tester), isTrue);

    await tapPullTab(tester);
    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    // Setup sanity: Agenda's card on May, April 21 still selected.
    expect(inHeader("May 2026"), findsOneWidget);
    expect(controller.selectedDay, tuesday);
    await pickView(tester, "Day");
    expect(inHeader("May 2026"), findsOneWidget);
    expect(controller.showsSelectedDay, isFalse);

    await tapPullTab(tester);
    await dragStrip(tester, 3);
    final dragged = stripDays(tester);
    // Setup sanity: the drag left a week's count of days, starting on no
    // week's first day, which no strip opens on.
    expect(dragged, hasLength(DateTime.daysPerWeek));
    expect(
      CalendarWeekdaySet.all.weekStartOf(dragged.first),
      isNot(dragged.first),
    );
    await pickView(tester, "Agenda");
    expect(folded(tester), isTrue);
    expect(stripDays(tester), dragged);
    await setView(tester, controller, CalendarViewKind.day);
    expect(folded(tester), isTrue);
    expect(stripDays(tester), dragged);
  });

  testWidgets("VS4 Week and Month show the selected day's week or month, "
      "name its month and hide Today, the card waiting: its moved month and "
      "the days a drag moved its strip to come back in Agenda and "
      "Day", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    // Setup sanity: the card on June, today selected, so Today shows.
    expect(inHeader("Jun 2026"), findsOneWidget);
    expect(controller.selectedDay, tuesday);
    expect(todayHit, findsOneWidget);

    await pickView(tester, "Month");
    // Setup sanity: Month shows the selected day's month.
    expect(find.byKey(monthDayKey(tuesday)), findsOneWidget);
    expect(inHeader("Apr 2026"), findsOneWidget);
    expect(controller.showsSelectedDay, isTrue);
    expect(todayHit, findsNothing);
    await setView(tester, controller, CalendarViewKind.agenda);
    expect(inHeader("Jun 2026"), findsOneWidget);
    expect(controller.showsSelectedDay, isFalse);
    expect(todayHit, findsOneWidget);

    await tapPullTab(tester);
    await dragStrip(tester, 3);
    final dragged = stripDays(tester);
    // Setup sanity: the drag left a week's count of June days, starting
    // on no week's first day.
    expect(dragged, hasLength(DateTime.daysPerWeek));
    expect(dragged[DateTime.daysPerWeek ~/ 2].month, DateTime.june);
    expect(
      CalendarWeekdaySet.all.weekStartOf(dragged.first),
      isNot(dragged.first),
    );
    await setView(tester, controller, CalendarViewKind.week);
    // Setup sanity: Week shows no card.
    expect(find.byType(CalendarCard<String>), findsNothing);
    expect(inHeader("Apr 2026"), findsOneWidget);
    expect(controller.showsSelectedDay, isTrue);
    expect(todayHit, findsNothing);
    await pickView(tester, "Day");
    expect(folded(tester), isTrue);
    expect(stripDays(tester), dragged);
    expect(inHeader("Jun 2026"), findsOneWidget);
    expect(controller.showsSelectedDay, isFalse);
    expect(todayHit, findsOneWidget);
  });

  testWidgets("VS5 an open month picker stays open on its year through "
      "every change of view, and Today closes it", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next year"));
    await tester.pumpAndSettle();
    // Setup sanity: the picker shows 2027.
    expect(find.byKey(picker), findsOneWidget);
    expect(inHeader("2027"), findsOneWidget);

    await pickView(tester, "Day");
    expect(find.byKey(picker), findsOneWidget);
    expect(inHeader("2027"), findsOneWidget);
    await setView(tester, controller, CalendarViewKind.week);
    expect(find.byKey(picker), findsOneWidget);
    expect(inHeader("2027"), findsOneWidget);
    await pickView(tester, "Month");
    expect(find.byKey(picker), findsOneWidget);
    expect(inHeader("2027"), findsOneWidget);
    await setView(tester, controller, CalendarViewKind.agenda);
    expect(find.byKey(picker), findsOneWidget);
    expect(inHeader("2027"), findsOneWidget);

    await tester.tap(todayHit);
    await tester.pumpAndSettle();
    expect(find.byKey(picker), findsNothing);
    expect(inHeader("Apr 2026"), findsOneWidget);
  });

  testWidgets("VS6 a tap on a day in Month opens it in Day on the fold the "
      "card was in", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final thursday = DateTime(2026, 4, 23);
    final friday = DateTime(2026, 4, 24);
    await pickView(tester, "Month");
    await tester.tap(find.byKey(monthStripKey(thursday)));
    await tester.pumpAndSettle();
    // Setup sanity: the tap opened Thursday in Day.
    expect(controller.view, CalendarViewKind.day);
    expect(controller.selectedDay, thursday);
    expect(folded(tester), isFalse);

    await tapPullTab(tester);
    await pickView(tester, "Month");
    await tester.tap(find.byKey(monthStripKey(friday)));
    await tester.pumpAndSettle();
    // Setup sanity: the tap opened Friday in Day.
    expect(controller.view, CalendarViewKind.day);
    expect(controller.selectedDay, friday);
    expect(folded(tester), isTrue);
  });

  testWidgets("VS7 new views without the view shown, and a new controller "
      "naming another view, keep the card's fold", (tester) async {
    Widget calendar(
      List<CalendarViewKind> views, [
      CalendarController? controller,
    ]) {
      return app(
        CalendarView<String>(
          store: store,
          clock: fixedClock,
          views: views,
          controller: controller,
        ),
      );
    }

    await tester.pumpWidget(calendar(CalendarViewKind.values));
    await tester.pumpAndSettle();
    // Setup sanity: Agenda's card on its month.
    expect(find.byType(DayList<String>), findsOneWidget);
    expect(folded(tester), isFalse);
    await tester.pumpWidget(
      calendar(const <CalendarViewKind>[
        CalendarViewKind.day,
        CalendarViewKind.week,
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TimedGrid<String>), findsOneWidget);
    expect(folded(tester), isFalse);

    await tester.pumpWidget(calendar(CalendarViewKind.values));
    await tester.pumpAndSettle();
    final swapped = CalendarController(view: CalendarViewKind.agenda);
    addTearDown(swapped.dispose);
    await tapPullTab(tester);
    // Setup sanity: Day's card folded.
    expect(find.byType(TimedGrid<String>), findsOneWidget);
    expect(folded(tester), isTrue);
    await tester.pumpWidget(calendar(CalendarViewKind.values, swapped));
    await tester.pumpAndSettle();
    expect(find.byType(DayList<String>), findsOneWidget);
    expect(folded(tester), isTrue);
  });
}
