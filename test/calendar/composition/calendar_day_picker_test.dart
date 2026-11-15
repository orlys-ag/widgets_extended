/// The inline day picker through the package barrel: what it opens on and
/// the weeks its first column starts, what its chevrons and month picks
/// report under each setting, the days its first and last day and its
/// predicate refuse, and when it asks the predicate.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

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

/// The days from [first] on, [count] of them.
List<DateTime> daysFrom(DateTime first, int count) {
  return <DateTime>[
    for (var offset = 0; offset < count; offset++)
      CalendarDates.addDays(first, offset),
  ];
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
    await tester.fling(
      find.byType(CalendarDayPicker<String>),
      const Offset(-300.0, 0.0),
      3000.0,
    );
    await tester.pumpAndSettle();
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
}
