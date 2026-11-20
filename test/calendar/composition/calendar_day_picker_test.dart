/// The inline day picker through the package barrel: what it opens on and
/// the weeks its first column starts, what its chevrons and month picks
/// report under each setting, the days its first and last day and its
/// predicate refuse, when it asks the predicate, what a store given in a
/// later build reads, where its days and its previous chevron lie with
/// daysToEdges, the weeks, months and years it browses back to with
/// browsesBeforeFirstDay false, the view it opens on and reports, and the
/// days onDayTap reports.
library;

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/widgets_extended.dart';

import '../../scheduling/zones.dart';

/// The day cell of [day], as a screen reader names a day with no badge.
Finder dayCell(DateTime day) {
  return find.bySemanticsLabel(
    const DefaultCalendarLocalizations().dayWithBadges(day, const <String?>[]),
  );
}

/// The enabled state a screen reader hears of the cell of [day].
Tristate enabledOf(WidgetTester tester, DateTime day) {
  return tester.getSemantics(dayCell(day)).flagsCollection.isEnabled;
}

/// Whether the cell of [day] lies where a pointer reaches it.
bool shows(DateTime day) {
  return dayCell(day).hitTestable().evaluate().isNotEmpty;
}

/// Whether the header's previous chevron takes a press.
bool previousEnabled(WidgetTester tester) {
  return tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_left),
          )
          .onPressed !=
      null;
}

/// Expects the week row, seven days wide, to show the seven days from
/// [monday], at [step].
void expectWeekFrom(DateTime monday, String step) {
  for (final day in daysFrom(monday, 7)) {
    expect(shows(day), isTrue, reason: "$step: $day");
  }
}

/// The enabled state a screen reader hears of the month picker's month
/// named [label].
Tristate monthEnabledOf(WidgetTester tester, String label) {
  return tester
      .getSemantics(find.bySemanticsLabel(label))
      .flagsCollection
      .isEnabled;
}

/// The days from [first] on, [count] of them.
List<DateTime> daysFrom(DateTime first, int count) {
  return <DateTime>[
    for (var offset = 0; offset < count; offset++)
      CalendarDates.addDays(first, offset),
  ];
}

/// Whether every [Opacity] above what [finder] finds paints it whole.
bool opaque(WidgetTester tester, Finder finder) {
  return tester
      .widgetList<Opacity>(
        find.ancestor(of: finder, matching: find.byType(Opacity)),
      )
      .every((opacity) {
        return opacity.opacity == 1.0;
      });
}

/// [picker] under a MaterialApp, at the top of a 400-pixel-wide column.
Widget app(Widget picker) {
  return MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 400.0, child: picker),
      ),
    ),
  );
}

/// The circle of the day cell [cell] finds.
Finder circleIn(Finder cell) {
  return find.descendant(
    of: cell,
    matching: find.byWidgetPredicate((widget) {
      return widget is Container &&
          widget.constraints ==
              const BoxConstraints.tightFor(width: 32.0, height: 32.0);
    }),
  );
}

/// The part of [box] that the clips above it leave painted, in global
/// coordinates.
Rect paintedRectOf(RenderBox box) {
  var painted = MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
  RenderObject child = box;
  var parent = box.parent;
  while (parent != null) {
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null) {
      painted = painted.intersect(
        MatrixUtils.transformRect(parent.getTransformTo(null), clip),
      );
    }
    child = parent;
    parent = parent.parent;
  }
  return painted;
}

/// Counts and records the days it is asked.
class CountingPredicate {
  CountingPredicate(this.refused);

  final DateTime refused;
  final List<DateTime> asked = <DateTime>[];

  bool isEnabled(DateTime day) {
    asked.add(day);
    return CalendarDates.dayNumber(day) != CalendarDates.dayNumber(refused);
  }
}

void main() {
  final tuesday = DateTime(2026, 4, 21);

  testWidgets("DP1 the barrel shows CalendarDayPicker, which opens with no "
      "store folded on the value's week from its first column, and refuses "
      "a first column outside 0 to 6", (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(CalendarDayPicker<String>(value: tuesday, onChanged: (day) {})),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text("Apr 2026"), findsOneWidget);
    expect(find.byTooltip("Previous week"), findsOneWidget);
    expect(find.byTooltip("Next week"), findsOneWidget);
    for (final day in daysFrom(DateTime(2026, 4, 20), 7)) {
      expect(shows(day), isTrue, reason: "$day");
    }
    expect(shows(DateTime(2026, 4, 19)), isFalse);
    expect(shows(DateTime(2026, 4, 27)), isFalse);

    await tester.pumpWidget(
      app(
        CalendarDayPicker<String>(
          key: const ValueKey<String>("from-sunday"),
          value: tuesday,
          onChanged: (day) {},
          firstColumn: 6,
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final day in daysFrom(DateTime(2026, 4, 19), 7)) {
      expect(shows(day), isTrue, reason: "$day");
    }
    expect(shows(DateTime(2026, 4, 18)), isFalse);
    expect(shows(DateTime(2026, 4, 26)), isFalse);

    expect(
      () {
        return CalendarDayPicker<String>(
          value: tuesday,
          onChanged: null,
          firstColumn: 7,
        );
      },
      throwsA(
        isA<ArgumentError>().having(
          (error) {
            return error.name;
          },
          "name",
          "firstColumn",
        ),
      ),
    );
    semantics.dispose();
  });

  testWidgets("DP2 with headerSelects a folded chevron and a month pick "
      "report a day; by default they move the card and report nothing; and "
      "a chevron onto a day the picker refuses moves the card", (tester) async {
    final semantics = tester.ensureSemantics();
    final reported = <DateTime>[];
    Widget picker({required bool headerSelects, DateTime? lastDay, Key? key}) {
      return app(
        CalendarDayPicker<String>(
          key: key,
          value: tuesday,
          onChanged: reported.add,
          headerSelects: headerSelects,
          lastDay: lastDay,
        ),
      );
    }

    await tester.pumpWidget(picker(headerSelects: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    expect(reported, <DateTime>[DateTime(2026, 4, 28)]);
    reported.clear();
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("June"));
    await tester.pumpAndSettle();
    expect(reported, <DateTime>[DateTime(2026, 6, 21)]);
    // The month picker stays open.
    expect(find.text("June"), findsOneWidget);

    reported.clear();
    await tester.pumpWidget(
      picker(headerSelects: false, key: const ValueKey<String>("browses")),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    expect(reported, isEmpty);
    for (final day in daysFrom(DateTime(2026, 4, 27), 7)) {
      expect(shows(day), isTrue, reason: "$day");
    }
    expect(shows(tuesday), isFalse);
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("June"));
    await tester.pumpAndSettle();
    expect(reported, isEmpty);
    expect(find.text("Jun 2026"), findsOneWidget);
    expect(find.text("June"), findsNothing);
    expect(shows(DateTime(2026, 6, 1)), isTrue);

    await tester.pumpWidget(
      picker(
        headerSelects: true,
        lastDay: DateTime(2026, 4, 25),
        key: const ValueKey<String>("refuses"),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    expect(reported, isEmpty);
    for (final day in daysFrom(DateTime(2026, 4, 27), 7)) {
      expect(shows(day), isTrue, reason: "$day");
    }
    expect(shows(tuesday), isFalse);
    semantics.dispose();
  });

  testWidgets("DP3 a day outside the first and last day, or one the "
      "predicate refuses, draws disabled and takes no tap, and the predicate "
      "is asked once a day, of days from the first to the last alone", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final predicate = CountingPredicate(DateTime(2026, 4, 23));
    final reported = <DateTime>[];
    Widget picker() {
      return app(
        CalendarDayPicker<String>(
          value: tuesday,
          onChanged: reported.add,
          firstDay: DateTime(2026, 4, 15),
          lastDay: DateTime(2026, 5, 10),
          isEnabled: predicate.isEnabled,
        ),
      );
    }

    await tester.pumpWidget(picker());
    await tester.pumpAndSettle();
    final thursday = DateTime(2026, 4, 23);
    expect(enabledOf(tester, thursday), Tristate.isFalse);
    await tester.tap(dayCell(thursday));
    await tester.pumpAndSettle();
    expect(reported, isEmpty);
    final wednesday = DateTime(2026, 4, 22);
    // Setup sanity: a day the picker takes reads enabled and reports.
    expect(enabledOf(tester, wednesday), Tristate.isTrue);
    await tester.tap(dayCell(wednesday));
    await tester.pumpAndSettle();
    expect(reported, <DateTime>[wednesday]);
    reported.clear();

    await tester.tap(find.byTooltip("Previous week"));
    await tester.pumpAndSettle();
    final before = DateTime(2026, 4, 14);
    expect(shows(before), isTrue);
    expect(enabledOf(tester, before), Tristate.isFalse);
    await tester.tap(dayCell(before));
    await tester.pumpAndSettle();
    expect(reported, isEmpty);

    await tester.tap(find.bySemanticsLabel("Show the month"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    final after = DateTime(2026, 5, 11);
    expect(shows(after), isTrue);
    expect(enabledOf(tester, after), Tristate.isFalse);
    await tester.tap(dayCell(after));
    await tester.pumpAndSettle();
    expect(reported, isEmpty);

    await tester.tap(find.bySemanticsLabel("Show the week"));
    await tester.pumpAndSettle();
    final around = daysFrom(DateTime(2026, 4, 1), 91);
    final shownBefore = around.where(shows).toSet();
    // Setup sanity: the week row shows one week.
    expect(shownBefore, hasLength(7));
    await tester.fling(
      find.byType(CalendarDayPicker<String>),
      const Offset(-300.0, 0.0),
      3000.0,
    );
    await tester.pumpAndSettle();
    // Setup sanity: the fling moved the week row.
    expect(around.where(shows).toSet().difference(shownBefore), isNotEmpty);
    await tester.pumpWidget(picker());
    await tester.pumpAndSettle();

    final numbers = predicate.asked.map(CalendarDates.dayNumber).toList();
    // Setup sanity: the motions asked of days from April and May.
    expect(numbers, contains(CalendarDates.dayNumber(DateTime(2026, 5, 4))));
    expect(numbers.toSet(), hasLength(numbers.length));
    expect(
      numbers.where((day) {
        return day < CalendarDates.dayNumber(DateTime(2026, 4, 15)) ||
            day > CalendarDates.dayNumber(DateTime(2026, 5, 10));
      }),
      isEmpty,
    );
    semantics.dispose();
  });

  testWidgets("DP8 with browsesBeforeFirstDay false the week row browses "
      "back, by the previous chevron or a fling, no further than the first "
      "day's week, where the chevron draws disabled, and a step or a fling "
      "on enables it", (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        CalendarDayPicker<String>(
          value: DateTime(2026, 4, 23),
          onChanged: (day) {},
          firstDay: DateTime(2026, 4, 22),
          today: DateTime(2026, 6, 10),
          browsesBeforeFirstDay: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final monday = DateTime(2026, 4, 20);
    // Setup sanity: the row opens on the value's week, the first day's.
    expectWeekFrom(monday, "opening");
    expect(previousEnabled(tester), isFalse);
    await tester.tap(find.byTooltip("Previous week"));
    await tester.pumpAndSettle();
    expectWeekFrom(monday, "Previous week");
    await tester.fling(
      find.byType(CalendarDayPicker<String>),
      const Offset(300.0, 0.0),
      3000.0,
    );
    await tester.pumpAndSettle();
    expectWeekFrom(monday, "a fling back");

    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    // Setup sanity: Next week moves the row.
    expectWeekFrom(DateTime(2026, 4, 27), "Next week");
    expect(previousEnabled(tester), isTrue);
    await tester.tap(find.byTooltip("Previous week"));
    await tester.pumpAndSettle();
    expectWeekFrom(monday, "Previous week from the next week");
    expect(previousEnabled(tester), isFalse);

    await tester.fling(
      find.byType(CalendarDayPicker<String>),
      const Offset(-300.0, 0.0),
      1000.0,
    );
    await tester.pumpAndSettle();
    // Setup sanity: the fling moved the row on.
    expect(shows(monday), isFalse);
    expect(previousEnabled(tester), isTrue);
    await tester.fling(
      find.byType(CalendarDayPicker<String>),
      const Offset(300.0, 0.0),
      3000.0,
    );
    await tester.pumpAndSettle();
    expect(previousEnabled(tester), isFalse);
    semantics.dispose();
  });

  testWidgets("DP9 with browsesBeforeFirstDay false the month browses back, "
      "by the previous chevron or a fling, no further than the first day's "
      "month, where the chevron draws disabled; by default the chevron "
      "browses past the first day's week", (tester) async {
    final semantics = tester.ensureSemantics();
    final thursday = DateTime(2026, 4, 23);
    final wednesday = DateTime(2026, 4, 22);
    await tester.pumpWidget(
      app(
        CalendarDayPicker<String>(
          value: thursday,
          onChanged: (day) {},
          firstDay: wednesday,
          today: DateTime(2026, 6, 10),
          browsesBeforeFirstDay: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel("Show the month"));
    await tester.pumpAndSettle();
    // Setup sanity: the card shows the value's month.
    expect(find.text("Apr 2026"), findsOneWidget);
    expect(previousEnabled(tester), isFalse);
    await tester.tap(find.byTooltip("Previous month"));
    await tester.pumpAndSettle();
    expect(find.text("Apr 2026"), findsOneWidget);
    await tester.fling(
      find.byType(CalendarDayPicker<String>),
      const Offset(300.0, 0.0),
      3000.0,
    );
    await tester.pumpAndSettle();
    expect(find.text("Apr 2026"), findsOneWidget);
    await tester.tap(find.byTooltip("Next month"));
    await tester.pumpAndSettle();
    // Setup sanity: Next month moves the card.
    expect(find.text("May 2026"), findsOneWidget);
    expect(previousEnabled(tester), isTrue);
    await tester.tap(find.byTooltip("Previous month"));
    await tester.pumpAndSettle();
    expect(find.text("Apr 2026"), findsOneWidget);

    await tester.pumpWidget(
      app(
        CalendarDayPicker<String>(
          key: const ValueKey<String>("browses"),
          value: thursday,
          onChanged: (day) {},
          firstDay: wednesday,
          today: DateTime(2026, 6, 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(previousEnabled(tester), isTrue);
    await tester.tap(find.byTooltip("Previous week"));
    await tester.pumpAndSettle();
    expectWeekFrom(DateTime(2026, 4, 13), "by default");
    semantics.dispose();
  });

  testWidgets("DP10 with browsesBeforeFirstDay false the month picker draws "
      "the months before the first day's disabled and takes no tap on them, "
      "and its chevron, a drag and a fling go back to no year before the "
      "first day's; by default its months have no enabled state and a drag "
      "goes back a year", (tester) async {
    final semantics = tester.ensureSemantics();
    final thursday = DateTime(2026, 4, 23);
    final wednesday = DateTime(2026, 4, 22);
    // Today in March, so March is the current month.
    final today = DateTime(2026, 3, 10);
    await tester.pumpWidget(
      app(
        CalendarDayPicker<String>(
          value: thursday,
          onChanged: (day) {},
          firstDay: wednesday,
          today: today,
          browsesBeforeFirstDay: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    expect(monthEnabledOf(tester, "February 2026"), Tristate.isFalse);
    expect(monthEnabledOf(tester, "April 2026"), Tristate.isTrue);
    final theme = CalendarTheme.of(tester.element(find.text("March")));
    Color? colourOf(String name) {
      return tester.widget<Text>(find.text(name)).style?.color;
    }

    Color disabled(Color colour) {
      return colour.withValues(alpha: colour.a * theme.disabledOpacity);
    }

    expect(colourOf("February"), disabled(theme.text));
    expect(colourOf("March"), disabled(theme.primary));
    await tester.tap(find.text("February"));
    await tester.pumpAndSettle();
    expect(find.text("February"), findsOneWidget);

    expect(previousEnabled(tester), isFalse);
    await tester.tap(find.byTooltip("Previous year"));
    await tester.pumpAndSettle();
    expect(find.text("2026"), findsOneWidget);
    final drag = await tester.startGesture(tester.getCenter(find.text("June")));
    await drag.moveBy(const Offset(20.0, 0.0));
    await tester.pump();
    await drag.moveBy(const Offset(280.0, 0.0));
    await tester.pump();
    // While the finger holds the picker.
    expect(find.text("2026"), findsOneWidget);
    expect(find.bySemanticsLabel("June 2025"), findsNothing);
    await drag.up();
    await tester.pumpAndSettle();
    await tester.fling(find.text("June"), const Offset(300.0, 0.0), 3000.0);
    await tester.pumpAndSettle();
    expect(find.text("2026"), findsOneWidget);
    expect(find.bySemanticsLabel("June 2026"), findsOneWidget);

    await tester.tap(find.byTooltip("Next year"));
    await tester.pumpAndSettle();
    // Setup sanity: Next year moves the picker.
    expect(find.text("2027"), findsOneWidget);
    expect(previousEnabled(tester), isTrue);
    expect(monthEnabledOf(tester, "March 2027"), Tristate.isTrue);
    await tester.tap(find.byTooltip("Previous year"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("May"));
    await tester.pumpAndSettle();
    // Setup sanity: a month the picker takes moves the card there.
    expect(find.text("May 2026"), findsOneWidget);

    await tester.pumpWidget(
      app(
        CalendarDayPicker<String>(
          key: const ValueKey<String>("browses"),
          value: thursday,
          onChanged: (day) {},
          firstDay: wednesday,
          today: today,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    expect(monthEnabledOf(tester, "February 2026"), Tristate.none);
    await tester.drag(find.text("June"), const Offset(300.0, 0.0));
    await tester.pumpAndSettle();
    expect(find.text("2025"), findsOneWidget);
    semantics.dispose();
  });

  testWidgets("DP11 with browsesBeforeFirstDay false a month before the "
      "value's folds, and a month pick brings the week row, into no week "
      "before the first day's, from which the chevrons step", (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        CalendarDayPicker<String>(
          value: DateTime(2026, 5, 5),
          onChanged: (day) {},
          firstDay: DateTime(2026, 4, 22),
          today: DateTime(2026, 6, 10),
          browsesBeforeFirstDay: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final limitWeek = DateTime(2026, 4, 20);
    // Setup sanity: the picker opens on the value's week.
    expectWeekFrom(DateTime(2026, 5, 4), "opening");
    await tester.tap(find.bySemanticsLabel("Show the month"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Previous month"));
    await tester.pumpAndSettle();
    // Setup sanity: the card shows April, whose first day's week starts
    // before the first day's.
    expect(find.text("Apr 2026"), findsOneWidget);
    await tester.tap(find.bySemanticsLabel("Show the week"));
    await tester.pumpAndSettle();
    expectWeekFrom(limitWeek, "the fold");
    expect(previousEnabled(tester), isFalse);
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    expectWeekFrom(DateTime(2026, 4, 27), "Next week");

    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("April"));
    await tester.pumpAndSettle();
    expectWeekFrom(limitWeek, "a month pick");
    semantics.dispose();
  });

  testWidgets("DP12 with browsesBeforeFirstDay false a value before the first "
      "day lets the week row browse back to the value's week, and a new "
      "first day brings the card back to the value", (tester) async {
    final semantics = tester.ensureSemantics();
    Widget picker(DateTime value, DateTime firstDay, {Key? key}) {
      return app(
        CalendarDayPicker<String>(
          key: key,
          value: value,
          onChanged: (day) {},
          firstDay: firstDay,
          today: DateTime(2026, 6, 10),
          browsesBeforeFirstDay: false,
        ),
      );
    }

    final wednesday = DateTime(2026, 4, 22);
    await tester.pumpWidget(picker(DateTime(2026, 4, 14), wednesday));
    await tester.pumpAndSettle();
    expectWeekFrom(DateTime(2026, 4, 13), "a value before the first day");
    expect(previousEnabled(tester), isFalse);
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    expect(previousEnabled(tester), isTrue);
    await tester.tap(find.byTooltip("Previous week"));
    await tester.pumpAndSettle();
    expectWeekFrom(DateTime(2026, 4, 13), "back to the value's week");

    const moves = ValueKey<String>("moves");
    final tuesday = DateTime(2026, 5, 5);
    await tester.pumpWidget(picker(tuesday, wednesday, key: moves));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Previous week"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Previous week"));
    await tester.pumpAndSettle();
    // Setup sanity: the row shows a week before May 1's.
    expectWeekFrom(DateTime(2026, 4, 20), "two weeks back");
    await tester.pumpWidget(picker(tuesday, DateTime(2026, 5, 1), key: moves));
    await tester.pumpAndSettle();
    expectWeekFrom(DateTime(2026, 5, 4), "a new first day");
    semantics.dispose();
  });

  testWidgets("DP4 a new predicate, a value on another date and a reassemble "
      "ask the shown days again, a new last day disables the days after it "
      "at once, no limit gives no enabled state, and a store dropped builds", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final first = CountingPredicate(DateTime(2026, 4, 23));
    final second = CountingPredicate(DateTime(2026, 4, 23));
    Widget picker({
      required CountingPredicate predicate,
      DateTime? value,
      DateTime? lastDay,
    }) {
      return app(
        CalendarDayPicker<String>(
          value: value ?? tuesday,
          onChanged: (day) {},
          lastDay: lastDay,
          isEnabled: predicate.isEnabled,
        ),
      );
    }

    int askedOf(CountingPredicate predicate, DateTime day) {
      return predicate.asked.where((asked) {
        return CalendarDates.dayNumber(asked) == CalendarDates.dayNumber(day);
      }).length;
    }

    final wednesday = DateTime(2026, 4, 22);
    await tester.pumpWidget(picker(predicate: first));
    await tester.pumpAndSettle();
    // Setup sanity: the first predicate was asked of a shown day once.
    expect(askedOf(first, wednesday), 1);

    await tester.pumpWidget(picker(predicate: second));
    await tester.pumpAndSettle();
    expect(askedOf(second, wednesday), 1);
    expect(askedOf(first, wednesday), 1);

    await tester.pumpWidget(
      picker(predicate: second, value: DateTime(2026, 4, 20)),
    );
    await tester.pumpAndSettle();
    expect(askedOf(second, wednesday), 2);

    final reassembled = tester.binding.reassembleApplication();
    await tester.pump();
    await reassembled;
    await tester.pumpAndSettle();
    expect(askedOf(second, wednesday), 3);

    final saturday = DateTime(2026, 4, 25);
    // Setup sanity: Saturday is enabled before the new last day.
    expect(enabledOf(tester, saturday), Tristate.isTrue);
    await tester.pumpWidget(
      picker(
        predicate: second,
        value: DateTime(2026, 4, 20),
        lastDay: DateTime(2026, 4, 24),
      ),
    );
    expect(enabledOf(tester, saturday), Tristate.isFalse);
    expect(enabledOf(tester, DateTime(2026, 4, 24)), Tristate.isTrue);

    await tester.pumpWidget(
      app(
        CalendarDayPicker<String>(
          key: const ValueKey<String>("no limits"),
          value: tuesday,
          onChanged: (day) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final day in daysFrom(DateTime(2026, 4, 20), 7)) {
      expect(enabledOf(tester, day), Tristate.none, reason: "$day");
    }

    final store = MemoryCalendarStore<String>();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      app(
        CalendarDayPicker<String>(
          key: const ValueKey<String>("stored"),
          value: tuesday,
          onChanged: (day) {},
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      app(
        CalendarDayPicker<String>(
          key: const ValueKey<String>("stored"),
          value: tuesday,
          onChanged: (day) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(shows(tuesday), isTrue);
    semantics.dispose();
  });

  testWidgets("DP5 a store given in a later build reads the shown month, and "
      "its entries badge their days", (tester) async {
    final semantics = tester.ensureSemantics();
    final wednesday = DateTime(2026, 4, 22);
    final source = HeldReads(<CalendarEntry<String>>[
      CalendarEntry<String>(
        id: "write",
        start: DateTime(2026, 4, 22, 9),
        end: DateTime(2026, 4, 22, 10),
        title: "Write",
        color: const Color(0xFF3366CC),
        payload: "write",
      ),
    ]);
    final caching = CachingCalendarStore<String>(dataSource: source);
    addTearDown(caching.dispose);
    // A calendar shows June from the store, which a store shows entries of
    // only once its shown range is ready.
    caching.show(DateTime(2026, 6, 1), DateTime(2026, 6, 30));
    source.reads.single.answer();
    source.reads.clear();
    await tester.pump();
    // Setup sanity: the shown range is ready.
    expect(caching.status, CalendarLoadStatus.ready);
    final memory = MemoryCalendarStore<String>();
    addTearDown(memory.dispose);
    Widget picker(CalendarStore<String> store) {
      return app(
        CalendarDayPicker<String>(
          value: tuesday,
          onChanged: (day) {},
          store: store,
        ),
      );
    }

    await tester.pumpWidget(picker(memory));
    await tester.pumpAndSettle();
    // Setup sanity: with the empty store, Wednesday shows no badge.
    expect(dayCell(wednesday), findsOneWidget);

    await tester.pumpWidget(picker(caching));
    await tester.pumpAndSettle();
    expect(
      source.reads.where((read) {
        return CalendarDates.dayNumber(read.first) <=
                CalendarDates.dayNumber(wednesday) &&
            CalendarDates.dayNumber(read.last) >=
                CalendarDates.dayNumber(wednesday);
      }),
      isNotEmpty,
    );
    for (final read in List.of(source.reads)) {
      read.answer();
    }
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        const DefaultCalendarLocalizations().dayWithBadges(
          wednesday,
          const <String?>[null],
        ),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets("DP6 with daysToEdges the circles of the first and last "
      "columns reach the picker's sides, folded and unfolded, an edge "
      "column's badges draw whole past its side, and a tap at the edge picks "
      "the day; by default the circles lie inside the picker's padding", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const write = CalendarBadgeKind(color: Color(0xFF3366CC), label: "Write");
    const meet = CalendarBadgeKind(color: Color(0xFFCC6633), label: "Meet");
    final badges = CalendarDayBadges<String>(
      kinds: const <CalendarBadgeKind>[write, meet],
      kindOf: (entry) {
        return entry.payload == "write" ? write : meet;
      },
    );
    final sunday = DateTime(2026, 4, 26);
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        for (final (id, hour) in <(String, int)>[("write", 9), ("meet", 11)])
          CalendarEntry<String>(
            id: id,
            start: DateTime(2026, 4, 26, hour),
            end: DateTime(2026, 4, 26, hour + 1),
            title: id,
            color: const Color(0xFF3366CC),
            payload: id,
          ),
      ],
    );
    addTearDown(store.dispose);
    final reported = <DateTime>[];
    Widget picker({required bool daysToEdges}) {
      return app(
        CalendarDayPicker<String>(
          key: ValueKey<bool>(daysToEdges),
          value: tuesday,
          onChanged: reported.add,
          store: store,
          dayBadges: badges,
          daysToEdges: daysToEdges,
        ),
      );
    }

    await tester.pumpWidget(picker(daysToEdges: true));
    await tester.pumpAndSettle();
    final side = tester.getRect(find.byType(CalendarDayPicker<String>));
    // Found by its date alone, whatever badges its label names.
    final sundayCell = find.bySemanticsLabel(RegExp(r"^Sunday, April 26(,|$)"));
    expect(
      tester.getRect(circleIn(dayCell(DateTime(2026, 4, 20)))).left,
      moreOrLessEquals(side.left),
    );
    final sundayCircle = tester.getRect(circleIn(sundayCell));
    expect(sundayCircle.right, moreOrLessEquals(side.right));
    final drawn = find
        .descendant(of: sundayCell, matching: find.byType(DecoratedBox))
        .evaluate()
        .map((element) {
          return element.renderObject! as RenderBox;
        })
        .where((box) {
          return box.size.width < 10.0;
        })
        .toList();
    // Setup sanity: Sunday carries two badges, one of them past the side.
    expect(drawn, hasLength(2));
    expect(
      drawn.any((box) {
        return box.localToGlobal(Offset(box.size.width, 0.0)).dx > side.right;
      }),
      isTrue,
    );
    for (final box in drawn) {
      final rect = MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
      expect(paintedRectOf(box), rect);
    }
    await tester.tapAt(sundayCircle.centerRight - const Offset(2.0, 0.0));
    await tester.pumpAndSettle();
    expect(reported, <DateTime>[sunday]);

    await tester.tap(find.bySemanticsLabel("Show the month"));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(circleIn(dayCell(DateTime(2026, 4, 6)))).left,
      moreOrLessEquals(side.left),
    );
    expect(
      tester.getRect(circleIn(dayCell(DateTime(2026, 4, 12)))).right,
      moreOrLessEquals(side.right),
    );

    await tester.pumpWidget(picker(daysToEdges: false));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(circleIn(dayCell(DateTime(2026, 4, 20)))).left,
      greaterThan(side.left + 8.0),
    );
    semantics.dispose();
  });

  testWidgets("DP7 with daysToEdges the previous chevron's circle spans the "
      "first column's circles", (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        CalendarDayPicker<String>(
          value: tuesday,
          onChanged: (day) {},
          daysToEdges: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final previous = tester.getRect(
      find
          .descendant(
            of: find.ancestor(
              of: find.byIcon(Icons.chevron_left),
              matching: find.byType(IconButton),
            ),
            matching: find.byType(Material),
          )
          .first,
    );
    final monday = tester.getRect(circleIn(dayCell(DateTime(2026, 4, 20))));
    expect(previous.left, moreOrLessEquals(monday.left));
    expect(previous.right, moreOrLessEquals(monday.right));
    semantics.dispose();
  });

  testWidgets("DP13 an unfold, a fold, and the month picker opening and "
      "closing, by a tap or a month pick, report the view they turn to "
      "through onViewChanged as they start; opening and a chevron report "
      "nothing", (tester) async {
    final semantics = tester.ensureSemantics();
    final reported = <CalendarDayPickerView>[];
    await tester.pumpWidget(
      app(
        CalendarDayPicker<String>(
          value: tuesday,
          onChanged: (day) {},
          onViewChanged: reported.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reported, isEmpty);
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    // Setup sanity: the chevron moved the card.
    expect(shows(DateTime(2026, 4, 28)), isTrue);
    expect(reported, isEmpty);

    await tester.tap(find.bySemanticsLabel("Show the month"));
    await tester.pump();
    expect(reported, <CalendarDayPickerView>[
      const CalendarDayPickerView(folded: false),
    ]);
    await tester.pumpAndSettle();
    reported.clear();
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pump();
    expect(reported, <CalendarDayPickerView>[
      const CalendarDayPickerView(folded: false, picksMonth: true),
    ]);
    await tester.pumpAndSettle();
    reported.clear();
    await tester.tap(find.text("June"));
    await tester.pump();
    expect(reported, <CalendarDayPickerView>[
      const CalendarDayPickerView(folded: false),
    ]);
    await tester.pumpAndSettle();

    reported.clear();
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Close the months"));
    await tester.pumpAndSettle();
    expect(reported, <CalendarDayPickerView>[
      const CalendarDayPickerView(folded: false, picksMonth: true),
      const CalendarDayPickerView(folded: false),
    ]);
    reported.clear();
    await tester.tap(find.bySemanticsLabel("Show the week"));
    await tester.pump();
    expect(reported, <CalendarDayPickerView>[const CalendarDayPickerView()]);
    semantics.dispose();
  });

  testWidgets("DP14 the picker opens on initialView at once: unfolded on the "
      "value's month, or on the month picker of the value's year over the "
      "week row or the month, which closing it shows; a later build's "
      "initialView leaves the view", (tester) async {
    final semantics = tester.ensureSemantics();
    // A Tuesday in a year after today's.
    final value = DateTime(2027, 6, 15);
    Widget picker(CalendarDayPickerView view, {Key? key}) {
      return app(
        CalendarDayPicker<String>(
          key: key,
          value: value,
          today: tuesday,
          onChanged: (day) {},
          initialView: view,
        ),
      );
    }

    Size pickerSize() {
      return tester.getSize(find.byType(CalendarDayPicker<String>));
    }

    await tester.pumpWidget(picker(const CalendarDayPickerView(folded: false)));
    final unfolded = pickerSize();
    expect(find.byTooltip("Next month"), findsOneWidget);
    expect(shows(DateTime(2027, 6, 1)), isTrue);
    await tester.pumpAndSettle();
    expect(pickerSize(), unfolded);

    await tester.pumpWidget(
      picker(
        const CalendarDayPickerView(picksMonth: true),
        key: const ValueKey<String>("over-week"),
      ),
    );
    final picking = pickerSize();
    expect(find.text("2027"), findsOneWidget);
    expect(find.text("June").hitTestable(), findsOneWidget);
    expect(opaque(tester, find.text("June")), isTrue);
    await tester.pumpAndSettle();
    expect(pickerSize(), picking);
    await tester.tap(find.byTooltip("Close the months"));
    await tester.pumpAndSettle();
    expect(find.byTooltip("Next week"), findsOneWidget);

    const overMonth = ValueKey<String>("over-month");
    await tester.pumpWidget(
      picker(
        const CalendarDayPickerView(folded: false, picksMonth: true),
        key: overMonth,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Close the months"));
    await tester.pumpAndSettle();
    expect(find.byTooltip("Next month"), findsOneWidget);
    await tester.pumpWidget(
      picker(const CalendarDayPickerView(), key: overMonth),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip("Next month"), findsOneWidget);
    semantics.dispose();
  });

  test("DP15 a CalendarDayPickerView equals one of the same fields, with "
      "the same hash code, and names its fields", () {
    expect(const CalendarDayPickerView().folded, isTrue);
    expect(const CalendarDayPickerView().picksMonth, isFalse);
    // Views made at run time, as two equal constants are one object.
    final fields = <bool>[false, true];
    final view = CalendarDayPickerView(
      folded: fields[0],
      picksMonth: fields[1],
    );
    final same = CalendarDayPickerView(
      folded: fields[0],
      picksMonth: fields[1],
    );
    expect(view, same);
    expect(view, isNot(const CalendarDayPickerView(picksMonth: true)));
    expect(view, isNot(const CalendarDayPickerView(folded: false)));
    expect(view.hashCode, same.hashCode);
    expect(
      view.toString(),
      "CalendarDayPickerView(folded: false, picksMonth: true)",
    );
  });

  testWidgets("DP16 headerTrailing lies at the end of the header's row, "
      "centred on the row, folded, unfolded and over the month picker", (
    tester,
  ) async {
    const trailing = SizedBox(
      key: ValueKey<String>("trailing"),
      width: 60.0,
      height: 20.0,
    );
    final finder = find.byKey(const ValueKey<String>("trailing"));
    for (final (step, view) in <(String, CalendarDayPickerView)>[
      ("folded", const CalendarDayPickerView()),
      ("unfolded", const CalendarDayPickerView(folded: false)),
      ("month picker", const CalendarDayPickerView(picksMonth: true)),
    ]) {
      await tester.pumpWidget(
        app(
          CalendarDayPicker<String>(
            key: ValueKey<String>(step),
            value: DateTime(2026, 4, 22),
            today: tuesday,
            onChanged: (day) {},
            initialView: view,
            headerTrailing: trailing,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final header = tester.getRect(
        find
            .descendant(
              of: find.byType(CalendarDayPicker<String>),
              matching: find.byType(Row),
            )
            .first,
      );
      final box = tester.getRect(finder);
      expect(box.right, header.right, reason: step);
      expect(box.center.dy, header.center.dy, reason: step);
    }
  });

  testWidgets("DP17 onDayTap reports a day tapped in the week row or the "
      "month, or activated by a screen reader, right after onChanged, and "
      "the value's day too, as the start of its date on the clock of the "
      "store's zone; a day an arrow key reaches, a day the picker refuses "
      "and a picker with no onChanged report nothing", (tester) async {
    ensureZones();
    final semantics = tester.ensureSemantics();
    final havana = tz.getLocation("America/Havana");
    final store = MemoryCalendarStore<String>(zone: havana);
    addTearDown(store.dispose);
    final wednesday = DateTime(2026, 4, 22);
    final thursday = DateTime(2026, 4, 23);
    final friday = DateTime(2026, 4, 24);
    final events = <(String, DateTime)>[];
    Widget picker(
      CalendarDayPickerView view, {
      bool takesDays = true,
      bool reportsTaps = true,
    }) {
      return app(
        CalendarDayPicker<String>(
          key: ValueKey<(CalendarDayPickerView, bool)>((view, takesDays)),
          value: wednesday,
          today: tuesday,
          store: store,
          initialView: view,
          isEnabled: (day) {
            return CalendarDates.dayNumber(day) !=
                CalendarDates.dayNumber(friday);
          },
          onChanged: takesDays
              ? (day) {
                  events.add(("changed", day));
                }
              : null,
          onDayTap: reportsTaps
              ? (day) {
                  events.add(("tap", day));
                }
              : null,
        ),
      );
    }

    final thursdayInHavana = tz.TZDateTime(havana, 2026, 4, 23);
    for (final view in <CalendarDayPickerView>[
      const CalendarDayPickerView(),
      const CalendarDayPickerView(folded: false),
    ]) {
      final step = view.folded ? "week row" : "month";
      await tester.pumpWidget(picker(view));
      await tester.pumpAndSettle();
      events.clear();
      await tester.tap(dayCell(thursday));
      await tester.pump();
      expect(events, <(String, DateTime)>[
        ("changed", thursdayInHavana),
        ("tap", thursdayInHavana),
      ], reason: step);
      final (_, reported) = events.last;
      expect(reported, isA<tz.TZDateTime>(), reason: step);

      events.clear();
      await tester.tap(dayCell(wednesday));
      await tester.pump();
      expect(events, <(String, DateTime)>[
        ("tap", tz.TZDateTime(havana, 2026, 4, 22)),
      ], reason: step);

      events.clear();
      await tester.tap(dayCell(friday));
      await tester.pump();
      expect(events, isEmpty, reason: step);

      events.clear();
      tester.semantics.tap(
        find.semantics.byLabel(
          const DefaultCalendarLocalizations().dayWithBadges(
            thursday,
            const <String?>[],
          ),
        ),
      );
      await tester.pump();
      expect(events, <(String, DateTime)>[
        ("changed", thursdayInHavana),
        ("tap", thursdayInHavana),
      ], reason: step);
    }

    // The month took the focus with the taps above, so the arrow keys
    // select.
    events.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(events, <(String, DateTime)>[("changed", thursdayInHavana)]);

    await tester.pumpWidget(
      picker(const CalendarDayPickerView(), takesDays: false),
    );
    events.clear();
    await tester.tap(dayCell(thursday));
    await tester.pump();
    expect(events, isEmpty);

    // Setup sanity: with no onDayTap a tap still reports through
    // onChanged.
    await tester.pumpWidget(
      picker(const CalendarDayPickerView(), reportsTaps: false),
    );
    events.clear();
    await tester.tap(dayCell(thursday));
    await tester.pump();
    expect(events, <(String, DateTime)>[("changed", thursdayInHavana)]);
    semantics.dispose();
  });
}

/// A data source each of whose reads waits until the test answers it, with
/// the entries that start on its days.
class HeldReads implements CalendarDataSource<String> {
  HeldReads(this.entries);

  final List<CalendarEntry<String>> entries;

  final List<({DateTime first, DateTime last, VoidCallback answer})> reads =
      <({DateTime first, DateTime last, VoidCallback answer})>[];

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    final from = CalendarDates.dayNumber(first);
    final to = CalendarDates.dayNumber(last);
    final completer = Completer<List<CalendarEntry<String>>>();
    reads.add((
      first: first,
      last: last,
      answer: () {
        completer.complete(<CalendarEntry<String>>[
          for (final entry in entries)
            if (CalendarDates.dayNumber(entry.start) >= from &&
                CalendarDates.dayNumber(entry.start) <= to)
              entry,
        ]);
      },
    ));
    return completer.future;
  }

  @override
  Future<CalendarEntry<String>> create(CalendarEntry<String> draft) {
    throw UnimplementedError();
  }

  @override
  Future<CalendarEntry<String>> replace(CalendarEntry<String> entry) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }
}
