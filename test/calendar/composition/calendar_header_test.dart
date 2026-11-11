/// The calendar's built-in header: its one row, the chevrons and the title
/// then the Today button at its start, and the edit mode toggle and the
/// view button at its end; when the Today button shows, on the clock of the
/// store's zone and past midnight, how it fades and keeps its size, and
/// what a tap on it does; the toggle's look, what a screen reader hears of
/// it and what it reports; the view button's icon, what a screen reader
/// hears of it and its menu; and what a custom header receives of them.
library;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/composition/calendar_card.dart'
    show calendarPullTabKey;
import 'package:widgets_extended/calendar/composition/calendar_header.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

import '../../scheduling/zones.dart';

final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);

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

/// Lays the test out in a view as wide as a phone's, 390 by 844.
void usePhoneView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(390.0, 844.0);
  addTearDown(tester.view.reset);
}

/// The Today button, shown or not.
Finder get todayButton {
  return find.byKey(calendarTodayButtonKey);
}

/// The Today button's opacity as it paints now: that of the fade its
/// nearest [AnimatedOpacity] builds.
double todayOpacity(WidgetTester tester) {
  final animated = find
      .ancestor(of: todayButton, matching: find.byType(AnimatedOpacity))
      .first;
  return tester
      .widget<FadeTransition>(
        find
            .descendant(of: animated, matching: find.byType(FadeTransition))
            .first,
      )
      .opacity
      .value;
}

/// Whether the Today button shows: painted whole, taking pointers, focus
/// and a screen reader's attention as a button whose tooltip is Today;
/// each of them is checked against the others, so a button half shown
/// fails.
bool todayShows(WidgetTester tester) {
  final opacity = todayOpacity(tester);
  final hit = todayButton.hitTestable().evaluate().isNotEmpty;
  final focusable = Focus.of(
    tester.element(
      find.descendant(of: todayButton, matching: find.byType(Icon)),
    ),
  ).canRequestFocus;
  // Searched in the semantics tree itself: a render object keeps the node
  // it last had after an ExcludeSemantics drops it from the tree.
  final heard = find.semantics
      .byPredicate((node) {
        return isSemantics(
          tooltip: "Today",
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
    "The Today button is half shown: opacity $opacity, hit-testable $hit, "
    "focusable $focusable, heard $heard.",
  );
}

/// Whether the calendar card shows [day] selected.
bool isSelected(WidgetTester tester, DateTime day) {
  return tester.widget<DayCell>(find.byKey(dayCellKey(day))).isSelected;
}

/// Taps [day] in the calendar card and lets the header settle.
Future<void> tapDay(WidgetTester tester, DateTime day) async {
  await tester.tap(find.byKey(dayCellKey(day)).hitTestable());
  await tester.pumpAndSettle();
}

/// Taps the Today button, which must show, and lets the calendar settle.
Future<void> tapToday(WidgetTester tester) async {
  await tester.tap(todayButton.hitTestable());
  await tester.pumpAndSettle();
}

/// The icon the button [button] shows.
IconData? iconIn(WidgetTester tester, Finder button) {
  return tester
      .widget<Icon>(find.descendant(of: button, matching: find.byType(Icon)))
      .icon;
}

/// The colour the glyph of the one [Icon] in [button] paints in.
Color? glyphColorIn(WidgetTester tester, Finder button) {
  final glyph = find.descendant(
    of: find.descendant(of: button, matching: find.byType(Icon)),
    matching: find.byType(RichText),
  );
  return tester.widget<RichText>(glyph).text.style!.color;
}

/// The fill of the button [button]: its [Material]'s colour.
Color? fillOf(WidgetTester tester, Finder button) {
  return tester
      .widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first,
      )
      .color;
}

/// The theme the header draws in.
CalendarThemeData headerTheme(WidgetTester tester) {
  return CalendarTheme.of(tester.element(find.byType(CalendarHeader)));
}

void main() {
  late MemoryCalendarStore<String> store;

  setUp(() {
    store = MemoryCalendarStore<String>();
  });

  tearDown(() {
    store.dispose();
  });

  testWidgets("HD1 the header is one row: the Today button, a calendar icon "
      "in the colour of the header's other icons, right after the next "
      "chevron, and at the "
      "row's end the edit mode toggle, then 4 px on the view button, with "
      "the row's free width between them and the Today button, which keeps "
      "its size while hidden", (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          clock: fixedClock,
          onEditableChanged: (editable) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final header = tester.getRect(find.byType(CalendarHeader));
    final next = tester.getRect(
      find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      ),
    );
    final hidden = tester.getRect(todayButton);
    final edit = tester.getRect(find.byKey(calendarEditToggleKey));
    final view = tester.getRect(find.byKey(calendarViewButtonKey));
    // Setup sanity: the calendar opened on today, so Today is hidden.
    expect(isSelected(tester, tuesday), isTrue);
    expect(todayShows(tester), isFalse);
    expect(hidden.left, next.right);
    expect(view.right, header.right);
    expect(view.left - edit.right, 4.0);
    expect(edit.left, greaterThan(hidden.right));
    for (final rect in <Rect>[hidden, edit, view]) {
      expect(rect.center.dy, next.center.dy);
    }

    await tapDay(tester, wednesday);
    expect(todayShows(tester), isTrue);
    expect(tester.getRect(todayButton), hidden);
    expect(iconIn(tester, todayButton), Icons.today_outlined);
    expect(glyphColorIn(tester, todayButton), headerTheme(tester).text);
    // Edit mode is off, so the toggle draws in its unselected colour.
    for (final other in <Finder>[
      find.ancestor(
        of: find.byIcon(Icons.chevron_left),
        matching: find.byType(IconButton),
      ),
      find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      ),
      find.byKey(calendarEditToggleKey),
      find.byKey(calendarViewButtonKey),
    ]) {
      expect(
        glyphColorIn(tester, todayButton),
        glyphColorIn(tester, other),
        reason: "$other",
      );
    }
  });

  testWidgets("HD2 another day fades the Today button in over the theme's "
      "motion, and a tap on it selects today and fades it out, taking no "
      "pointer from the tap on", (tester) async {
    final semantics = tester.ensureSemantics();
    const motion = Duration(milliseconds: 900);
    await tester.pumpWidget(
      app(
        CalendarTheme(
          data: CalendarThemeData.builtIn.copyWith(motionDuration: motion),
          child: CalendarView<String>(store: store, clock: fixedClock),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(todayShows(tester), isFalse);
    final half = motion ~/ 2;

    await tester.tap(find.byKey(dayCellKey(wednesday)).hitTestable());
    await tester.pump();
    await tester.pump(half);
    expect(todayOpacity(tester), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(isSelected(tester, wednesday), isTrue);
    expect(todayShows(tester), isTrue);

    await tester.tap(todayButton.hitTestable());
    await tester.pump();
    expect(todayButton.hitTestable(), findsNothing);
    await tester.pump(half);
    expect(todayOpacity(tester), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();
    expect(isSelected(tester, tuesday), isTrue);
    expect(todayShows(tester), isFalse);
    semantics.dispose();
  });

  testWidgets("HD3 selecting today in the calendar hides the Today button", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(CalendarView<String>(store: store, clock: fixedClock)),
    );
    await tester.pumpAndSettle();
    await tapDay(tester, wednesday);
    // Setup sanity: another day is selected, and Today shows.
    expect(isSelected(tester, wednesday), isTrue);
    expect(todayShows(tester), isTrue);

    await tapDay(tester, tuesday);
    expect(isSelected(tester, tuesday), isTrue);
    expect(todayShows(tester), isFalse);
    semantics.dispose();
  });

  testWidgets("HD4 with today selected, the Today button shows while the "
      "card shows another month or a drag has moved the strip off today, and "
      "a tap brings each back; the month picker alone, on any year, leaves "
      "it hidden", (tester) async {
    final semantics = tester.ensureSemantics();
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
    expect(todayShows(tester), isFalse);

    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    // Setup sanity: the card left today's month, today still selected.
    expect(find.text("May 2026"), findsOneWidget);
    expect(controller.selectedDay, tuesday);
    expect(todayShows(tester), isTrue);
    await tapToday(tester);
    expect(find.text("Apr 2026"), findsOneWidget);
    expect(todayShows(tester), isFalse);

    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    const picker = ValueKey<String>("month-picker");
    expect(find.byKey(picker), findsOneWidget);
    expect(todayShows(tester), isFalse);
    await tester.tap(find.byTooltip("Next year"));
    await tester.pumpAndSettle();
    // Setup sanity: the picker shows the next year.
    expect(find.text("2027"), findsOneWidget);
    expect(todayShows(tester), isFalse);
    await tester.tap(find.byTooltip("Close the months"));
    await tester.pumpAndSettle();
    expect(find.byKey(picker), findsNothing);
    expect(todayShows(tester), isFalse);

    controller.view = CalendarViewKind.day;
    await tester.pumpAndSettle();
    // Day's card opens on its month, which the pull tab folds.
    await tester.tap(find.byKey(calendarPullTabKey));
    await tester.pumpAndSettle();
    final strip = find.byType(WeekStrip<String>);
    final todayInStrip = find.byKey(weekStripDayKey(tuesday)).hitTestable();
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
    expect(controller.selectedDay, tuesday);
    expect(todayShows(tester), isTrue);
    await tapToday(tester);
    expect(todayInStrip, findsOneWidget);
    expect(todayShows(tester), isFalse);
    semantics.dispose();
  });

  testWidgets("HD5 the Today button reads today on the clock of the store's "
      "zone, and a tap selects that zone's today", (tester) async {
    final semantics = tester.ensureSemantics();
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
    final zone = zoneApartFromDevice(fixedClock(), 13);
    // Setup sanity: the zone reads the next day at the clock's time, and
    // the calendar opened on the device's today.
    expect(
      CalendarDates.dayNumber(CalendarDates.inZone(fixedClock(), zone: zone)),
      CalendarDates.dayNumber(wednesday),
    );
    expect(isSelected(tester, tuesday), isTrue);
    expect(todayShows(tester), isFalse);

    store.zone = zone;
    await tester.pumpAndSettle();
    // Setup sanity: the selected day keeps its date on the zone's clock.
    expect(
      CalendarDates.dayNumber(controller.selectedDay),
      CalendarDates.dayNumber(tuesday),
    );
    expect(todayShows(tester), isTrue);

    await tapToday(tester);
    expect(
      CalendarDates.dayNumber(controller.selectedDay),
      CalendarDates.dayNumber(wednesday),
    );
    expect(todayShows(tester), isFalse);
    semantics.dispose();
  });

  testWidgets("HD6 the Today button shows once midnight leaves the selected "
      "day behind", (tester) async {
    final semantics = tester.ensureSemantics();
    var now = DateTime(2026, 4, 21, 23, 59, 30);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          clock: () {
            return now;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Setup sanity: the calendar opened on the clock's day.
    expect(isSelected(tester, tuesday), isTrue);
    expect(todayShows(tester), isFalse);

    now = DateTime(2026, 4, 22, 0, 0, 30);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    // Setup sanity: the selection stayed on the day before.
    expect(isSelected(tester, tuesday), isTrue);
    expect(todayShows(tester), isTrue);
    semantics.dispose();
  });

  testWidgets("HD7 where today's weekday is hidden, the Today button hides "
      "on the shown day nearest today, which a tap on it would select", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    Widget calendar(CalendarWeekdaySet weekdays) {
      return app(
        CalendarView<String>(
          store: store,
          clock: fixedClock,
          weekdays: weekdays,
        ),
      );
    }

    await tester.pumpWidget(calendar(CalendarWeekdaySet.all));
    await tester.pumpAndSettle();
    await tapDay(tester, wednesday);
    // Setup sanity: Wednesday is selected, so Today shows.
    expect(isSelected(tester, wednesday), isTrue);
    expect(todayShows(tester), isTrue);

    final noTuesday = CalendarWeekdaySet.of(const <int>[0, 2, 3, 4, 5, 6]);
    await tester.pumpWidget(calendar(noTuesday));
    await tester.pumpAndSettle();
    // Setup sanity: Tuesday, today's weekday, is hidden, Wednesday is the
    // shown day nearest it, and Wednesday is still selected.
    expect(find.byKey(dayCellKey(tuesday)), findsNothing);
    expect(CalendarDates.shownDayNear(tuesday, noTuesday), wednesday);
    expect(isSelected(tester, wednesday), isTrue);
    expect(todayShows(tester), isFalse);
    semantics.dispose();
  });

  testWidgets("HD8 the edit mode toggle: none without onEditableChanged; "
      "with it an outlined pencil in the text colour out of edit mode and a "
      "filled one in the primary colour on the primary tint in it, which a "
      "screen reader hears as a button selected or not; a tap reports the "
      "opposite mode", (tester) async {
    final semantics = tester.ensureSemantics();
    final toggle = find.byKey(calendarEditToggleKey);
    final reported = <bool>[];
    Widget calendar({required bool editable, required bool reports}) {
      return app(
        CalendarView<String>(
          store: store,
          clock: fixedClock,
          editable: editable,
          onEditableChanged: reports ? reported.add : null,
        ),
      );
    }

    await tester.pumpWidget(calendar(editable: false, reports: false));
    await tester.pumpAndSettle();
    expect(toggle, findsNothing);
    expect(find.byTooltip("Edit mode"), findsNothing);

    await tester.pumpWidget(calendar(editable: false, reports: true));
    await tester.pumpAndSettle();
    final theme = headerTheme(tester);
    expect(iconIn(tester, toggle), Icons.edit_outlined);
    expect(glyphColorIn(tester, toggle), theme.text);
    expect(fillOf(tester, toggle), Colors.transparent);
    expect(
      tester.getSemantics(toggle),
      isSemantics(
        tooltip: "Edit mode",
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(reported, <bool>[true]);
    // The host set nothing, so the mode stands.
    expect(iconIn(tester, toggle), Icons.edit_outlined);

    await tester.pumpWidget(calendar(editable: true, reports: true));
    await tester.pumpAndSettle();
    expect(iconIn(tester, toggle), Icons.edit);
    expect(glyphColorIn(tester, toggle), theme.primary);
    expect(fillOf(tester, toggle), theme.primaryTint);
    expect(
      tester.getSemantics(toggle),
      isSemantics(
        tooltip: "Edit mode",
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(reported, <bool>[true, false]);
    semantics.dispose();
  });

  testWidgets("HD9 the view button shows the icon of the view shown, which a "
      "screen reader hears named after the button's tooltip, and its menu "
      "lists each view with its icon and name; a pick changes the icon", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final button = find.byKey(calendarViewButtonKey);
    await tester.pumpWidget(
      app(CalendarView<String>(store: store, clock: fixedClock)),
    );
    await tester.pumpAndSettle();
    expect(iconIn(tester, button), Icons.view_agenda_outlined);
    expect(
      tester.getSemantics(button),
      isSemantics(tooltip: "Calendar view", value: "Agenda", isButton: true),
    );

    await tester.tap(button);
    await tester.pumpAndSettle();
    final items = find.byType(PopupMenuItem<CalendarViewKind>);
    expect(
      <IconData?>[
        for (final icon in tester.widgetList<Icon>(
          find.descendant(of: items, matching: find.byType(Icon)),
        ))
          icon.icon,
      ],
      <IconData>[
        Icons.view_agenda_outlined,
        Icons.calendar_view_day_outlined,
        Icons.calendar_view_week_outlined,
        Icons.calendar_view_month_outlined,
      ],
    );
    expect(
      <String?>[
        for (final text in tester.widgetList<Text>(
          find.descendant(of: items, matching: find.byType(Text)),
        ))
          text.data,
      ],
      <String>["Agenda", "Day", "Week", "Month"],
    );

    await tester.tap(find.text("Week").last);
    await tester.pumpAndSettle();
    expect(iconIn(tester, button), Icons.calendar_view_week_outlined);
    expect(
      tester.getSemantics(button),
      isSemantics(tooltip: "Calendar view", value: "Week", isButton: true),
    );
    semantics.dispose();
  });

  testWidgets("HD10 a custom header receives the Today action and whether it "
      "would change anything, edit mode and its report; its Today action "
      "brings the calendar to today", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    void report(bool editable) {}
    late CalendarHeaderDetails details;
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
          editable: true,
          onEditableChanged: report,
          headerBuilder: (context, given) {
            details = given;
            return const SizedBox(height: 40.0);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(details.onToday, isNotNull);
    expect(details.canGoToToday, isFalse);
    expect(details.editable, isTrue);
    expect(details.onEditableChanged, same(report));

    await tapDay(tester, wednesday);
    expect(details.canGoToToday, isTrue);
    details.onToday!();
    await tester.pumpAndSettle();
    expect(controller.selectedDay, tuesday);
    expect(details.canGoToToday, isFalse);
  });

  testWidgets("HD11 over the month picker, the Today button shows while "
      "another day is selected or the card shows another month, and a tap "
      "closes the picker and brings the calendar to today", (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(CalendarView<String>(store: store, clock: fixedClock)),
    );
    await tester.pumpAndSettle();
    const picker = ValueKey<String>("month-picker");

    await tapDay(tester, wednesday);
    // Setup sanity: another day is selected.
    expect(isSelected(tester, wednesday), isTrue);
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    expect(find.byKey(picker), findsOneWidget);
    expect(todayShows(tester), isTrue);
    await tapToday(tester);
    expect(find.byKey(picker), findsNothing);
    expect(isSelected(tester, tuesday), isTrue);

    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    // Setup sanity: the card shows May, with today still selected.
    expect(find.text("May 2026"), findsOneWidget);
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    expect(find.byKey(picker), findsOneWidget);
    expect(todayShows(tester), isTrue);
    await tapToday(tester);
    expect(find.byKey(picker), findsNothing);
    expect(find.text("Apr 2026"), findsOneWidget);
    semantics.dispose();
  });

  testWidgets("HD12 the Today button, the edit mode toggle and the view "
      "button are 32 px circles around 22 px icons, the toggle's fill a "
      "circle too, and the chevrons keep their 24 px icons", (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          clock: fixedClock,
          editable: true,
          onEditableChanged: (editable) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapDay(tester, wednesday);
    // Setup sanity: Today shows, and the toggle is selected.
    expect(todayShows(tester), isTrue);
    expect(
      tester.widget<IconButton>(find.byKey(calendarEditToggleKey)).isSelected,
      isTrue,
    );
    for (final button in <Finder>[
      todayButton,
      find.byKey(calendarEditToggleKey),
      find.byKey(calendarViewButtonKey),
    ]) {
      final ink = find
          .descendant(of: button, matching: find.byType(Material))
          .first;
      expect(tester.getSize(ink), const Size.square(32.0), reason: "$button");
      expect(
        tester.widget<Material>(ink).shape,
        isA<CircleBorder>(),
        reason: "$button",
      );
      expect(
        tester.getSize(
          find.descendant(of: button, matching: find.byType(Icon)),
        ),
        const Size.square(22.0),
        reason: "$button",
      );
    }
    expect(
      tester.getSize(find.byIcon(Icons.chevron_right)),
      const Size.square(24.0),
    );
  });
}
