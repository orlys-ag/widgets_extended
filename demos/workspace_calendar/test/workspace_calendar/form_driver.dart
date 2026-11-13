/// Finders and actions on the item form, the one place the demo's tests
/// read the form's structure from; `calendar_harness.dart` exports it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart'
    show parseIsoDate;
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/item_form.dart';

/// The form's text field labelled [label].
Finder fieldFinder(String label) {
  return find.widgetWithText(TextField, label);
}

/// The text of the form's text field labelled [label].
String fieldText(WidgetTester tester, String label) {
  return tester.widget<TextField>(fieldFinder(label)).controller!.text;
}

/// The form's dropdown labelled [label].
Finder dropdownFinder(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) {
      return widget is DropdownButtonFormField;
    }),
  );
}

/// The text [time] in the form's dropdown labelled [label].
Finder dropdownShows(String label, String time) {
  return find.descendant(of: dropdownFinder(label), matching: find.text(time));
}

/// The form's Save button.
Finder saveFinder() {
  return find.byType(FilledButton);
}

/// The form's text button labelled [label]: Cancel, Delete or Close.
Finder formButton(String label) {
  return find.widgetWithText(TextButton, label);
}

/// Whether [button] takes a press.
bool isEnabled(WidgetTester tester, Finder button) {
  return tester.widget<ButtonStyleButton>(button).onPressed != null;
}

/// Whether the dropdown labelled [label] offers [option] enabled, as the
/// schedule section offers a start time the policy refuses disabled.
bool optionEnabled(WidgetTester tester, String label, String option) {
  final button =
      find
              .descendant(
                of: dropdownFinder(label),
                matching: find.byWidgetPredicate((widget) {
                  return widget is DropdownButton;
                }),
              )
              .evaluate()
              .single
              .widget
          as DropdownButton;
  final item = button.items!.singleWhere((item) {
    final child = item.child;
    return child is Text && child.data == option;
  });
  return item.enabled;
}

/// Picks [option] in the form's dropdown labelled [label]: opens its menu,
/// which opens scrolled to the value it shows, jumps the menu to its top
/// and scrolls down until the option shows.
Future<void> chooseOption(
  WidgetTester tester,
  String label,
  String option,
) async {
  await tester.tap(dropdownFinder(label));
  await tester.pumpAndSettle();
  final menu = find.byType(Scrollable).last;
  final position = tester.state<ScrollableState>(menu).position;
  position.jumpTo(position.minScrollExtent);
  await tester.pump();
  final item = find.descendant(of: menu, matching: find.text(option));
  await tester.scrollUntilVisible(item, 100.0, scrollable: menu);
  // Centred, as an item scrolled to the menu's edge can sit under it.
  await Scrollable.ensureVisible(tester.element(item), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

/// The form's date field labelled [label], "Start date" or "End date".
Finder formDateFinder(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byType(InputDecorator),
  );
}

/// The form's date field labelled [label] showing [date], as
/// [CalendarDates.isoDate] writes it.
Finder formDateShows(String label, String date) {
  return find.descendant(of: formDateFinder(label), matching: find.text(date));
}

/// Expects the form's Start date to name [day], and its End date the day
/// [days] - 1 days after it, both as [CalendarDates.isoDate] writes them;
/// a timed item on one day shows no End date, which the schedule section
/// shows only for an all-day or a multi-day item.
void expectFormDays(String day, int days) {
  expect(formDateShows("Start date", day), findsOneWidget);
  final end = formDateShows(
    "End date",
    CalendarDates.isoDate(CalendarDates.addDays(parseIsoDate(day)!, days - 1)),
  );
  final allDay = formAllDayOn();
  if (days == 1 && !allDay) {
    expect(find.text("End date"), findsNothing);
  } else {
    expect(end, findsOneWidget);
  }
}

/// The form's All day chip, the last of its length chips.
Finder allDayChip() {
  return find.widgetWithText(ChoiceChip, "All day");
}

/// Whether the form's All day chip is selected.
bool formAllDayOn() {
  final chips = allDayChip().evaluate();
  return chips.isNotEmpty && (chips.single.widget as ChoiceChip).selected;
}

/// The labels of the form's length chips, All day among them, in order;
/// only the selected ones where [selectedOnly].
List<String> chipLabels(WidgetTester tester, {bool selectedOnly = false}) {
  return tester
      .widgetList<ChoiceChip>(find.byType(ChoiceChip))
      .where((chip) {
        return !selectedOnly || chip.selected;
      })
      .map((chip) {
        return (chip.label as Text).data!;
      })
      .toList();
}

/// Whether each of the form's length chips, All day among them, takes a
/// tap, in order.
List<bool> chipsEnabled(WidgetTester tester) {
  return tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).map((chip) {
    return chip.onSelected != null;
  }).toList();
}

/// Expects the create flow, picks [type], and expects its form prefilled
/// with [day], [start] to [end], ending on [day]; then cancels it.
Future<void> expectCreateForm(
  WidgetTester tester, {
  required String type,
  required String day,
  required String start,
  required String end,
}) async {
  expect(find.text("New item"), findsOneWidget);
  await tester.tap(find.text(type).last);
  await tester.pumpAndSettle();
  expectFormDays(day, 1);
  expect(dropdownShows("Start time", start), findsOneWidget);
  expect(dropdownShows("End time", end), findsOneWidget);
  await tester.tap(formButton("Cancel"));
  await tester.pumpAndSettle();
}

/// The form's errors, keyed `start` and `end`, for a change of the stored
/// [from], or of a new entry where it is null, to the times [to] under
/// [policy] at [now], in the calendar's whole day of 15-minute slots: what
/// [scheduleErrorsOf] makes of the check's problems.
Map<String, String> formErrorsOf<T>(
  CalendarEditPolicy<T> policy,
  CalendarNow now,
  CalendarEntry<T>? from,
  ({DateTime start, DateTime end}) to, {
  required bool isAllDay,
}) {
  return scheduleErrorsOf(
    CalendarScheduleCheck<T>(
      schedule: CalendarSchedule.of(to.start, to.end, isAllDay: isAllDay),
      rules: CalendarEditRules<T>(
        policy: policy,
        hours: CalendarDayHours.allDay,
        slotMinutes: CalendarDates.defaultSlotMinutes,
      ),
      now: now,
      entry: from,
    ).problems,
  );
}
