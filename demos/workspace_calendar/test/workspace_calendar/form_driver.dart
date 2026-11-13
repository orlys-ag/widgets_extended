/// Finders and actions on the item form, the one place the demo's tests
/// read the form's structure from; `calendar_harness.dart` exports it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/views/time_picker.dart'
    show
        TimePickerRules,
        timePickerAmKey,
        timePickerAmPmColumnKey,
        timePickerHourColumnKey,
        timePickerHourRowKey,
        timePickerMinuteColumnKey,
        timePickerMinuteRowKey,
        timePickerPmKey;
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart'
    show parseIsoDate;
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/item_form.dart';
import 'package:workspace_calendar/workspace_calendar/schedule_section.dart';

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

/// The text [option] in the form's dropdown labelled [label].
Finder dropdownShows(String label, String option) {
  return find.descendant(
    of: dropdownFinder(label),
    matching: find.text(option),
  );
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

/// The key of the form's time field labelled [label].
ValueKey<String> _timeFieldKey(String label) {
  switch (label) {
    case "Start time":
      return scheduleStartTimeKey;
    case "End time":
      return scheduleEndTimeKey;
  }
  throw ArgumentError.value(label, "label", "names no time field");
}

/// The key of the picker the form's time field labelled [label] opens.
ValueKey<String> _timePickerKey(String label) {
  switch (label) {
    case "Start time":
      return scheduleStartPickerKey;
    case "End time":
      return scheduleEndPickerKey;
  }
  throw ArgumentError.value(label, "label", "names no time field");
}

/// The form's time field labelled [label], "Start time" or "End time".
Finder timeFieldFinder(String label) {
  return find.byKey(_timeFieldKey(label));
}

/// The text [time] in the form's time field labelled [label].
Finder timeFieldShows(String label, String time) {
  return find.descendant(of: timeFieldFinder(label), matching: find.text(time));
}

/// Whether the [InkWell] of the form's time field labelled [label] has a
/// tap, which a field whose picker is closed has where it takes input.
bool timeFieldTakesInput(WidgetTester tester, String label) {
  return tester
          .widget<InkWell>(
            find.descendant(
              of: timeFieldFinder(label),
              matching: find.byType(InkWell),
            ),
          )
          .onTap !=
      null;
}

/// The picker open under the form's time field labelled [label].
Finder timePickerFinder(String label) {
  return find.descendant(
    of: find.byKey(_timePickerKey(label)),
    matching: find.byType(CalendarTimePicker),
  );
}

/// The minute after midnight [time] names, written "HH:MM" on the 24-hour
/// clock: "09:30" is 570, and "24:00" is 1440.
int clockMinute(String time) {
  final match = RegExp(r"^(\d{2}):(\d{2})$").firstMatch(time);
  if (match == null) {
    throw ArgumentError.value(time, "time", "is not HH:MM");
  }
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

/// Opens the picker of the form's time field labelled [label] with a tap
/// on the field where it is closed, and lets it settle.
Future<void> openTimePicker(WidgetTester tester, String label) async {
  if (timePickerFinder(label).evaluate().isNotEmpty) {
    return;
  }
  await tester.tap(timeFieldFinder(label));
  await tester.pumpAndSettle();
}

/// Closes the picker of the form's time field labelled [label] with a tap
/// on the field where it is open, and lets it settle.
Future<void> closeTimePicker(WidgetTester tester, String label) async {
  if (timePickerFinder(label).evaluate().isEmpty) {
    return;
  }
  await tester.tap(timeFieldFinder(label));
  await tester.pumpAndSettle();
}

/// The open picker of the form's time field labelled [label].
CalendarTimePicker _openPicker(WidgetTester tester, String label) {
  return tester.widget<CalendarTimePicker>(timePickerFinder(label));
}

/// Whether the open picker of the form's time field labelled [label]
/// offers [time], as the [TimePickerRules] it builds its rows from give it:
/// in its range, on its steps, and accepted by its own check. The read
/// builds nothing and leaves the form as it is.
bool timeEnabled(WidgetTester tester, String label, String time) {
  return TimePickerRules.of(
    _openPicker(tester, label),
  ).offers(clockMinute(time));
}

/// The minutes the open picker of the form's time field labelled [label]
/// offers, ascending, as the [TimePickerRules] it builds its rows from give
/// them: neither a value it shows out of range or off its steps nor a time
/// it refuses is among them. The read builds nothing and leaves the form as
/// it is.
List<int> offeredTimes(WidgetTester tester, String label) {
  return TimePickerRules.of(_openPicker(tester, label)).offeredTimes().toList();
}

/// Picks [time] in the form's time field labelled [label] as a user does:
/// opens its picker, expects it to offer [time], brings it into view, and
/// drags onto its pill each of its rows of [time] that lies off it, the
/// AM/PM column's on the 12-hour clock, then the Hour column's and the
/// Minute column's, each column's pick settling before the next drag. It
/// expects the picker's value to be [time] after the last, brings the field
/// back into view, and closes the picker.
///
/// Each drag is a pick the form takes, so the form passes through the
/// times between, and a time the picker offers only while the form holds
/// it cannot be picked back once a drag has left it.
Future<void> pickTime(WidgetTester tester, String label, String time) async {
  await openTimePicker(tester, label);
  expect(
    timeEnabled(tester, label, time),
    isTrue,
    reason: "$label takes $time",
  );
  await tester.ensureVisible(timePickerFinder(label));
  await tester.pumpAndSettle();
  final minute = clockMinute(time);
  final rules = TimePickerRules.of(_openPicker(tester, label));
  if (rules.twelveHour) {
    await _dragToPill(
      tester,
      label,
      timePickerAmPmColumnKey,
      TimePickerRules.isPm(minute) ? timePickerPmKey : timePickerAmKey,
    );
  }
  await _dragToPill(
    tester,
    label,
    timePickerHourColumnKey,
    timePickerHourRowKey(rules.hourOf(minute)),
  );
  await _dragToPill(
    tester,
    label,
    timePickerMinuteColumnKey,
    timePickerMinuteRowKey(minute % 60),
  );
  expect(
    _openPicker(tester, label).value,
    minute,
    reason: "$label shows $time",
  );
  // Bringing the picker into view can scroll its field out of the form's
  // view, where the tap that closes the picker would miss it.
  await tester.ensureVisible(timeFieldFinder(label));
  await tester.pumpAndSettle();
  await closeTimePicker(tester, label);
}

/// Drags the column keyed [columnKey] of the open picker of the form's
/// time field labelled [label] until its row keyed [rowKey] lies on the
/// column's centre, where its pill is, and lets the pick settle; a row
/// within 0.5 px of the centre is left.
///
/// The finger goes down on the column's centre row and moves 20 px up and
/// back, past the touch slop, so the column takes the drag. It then moves
/// by the row's distance to the centre, read as the row lies then, in
/// steps of at most 8 px 50 ms apart, and rests 200 ms before its lift, so
/// it lifts with no speed and the column lands on the row. A row the
/// column does not paint has a centre too, through the column's paint
/// transform.
Future<void> _dragToPill(
  WidgetTester tester,
  String label,
  Key columnKey,
  Key rowKey,
) async {
  final column = find.descendant(
    of: timePickerFinder(label),
    matching: find.byKey(columnKey),
  );
  final row = find.descendant(
    of: timePickerFinder(label),
    matching: find.byKey(rowKey),
  );
  final centre = tester.getCenter(column).dy;
  if ((tester.getCenter(row).dy - centre).abs() < 0.5) {
    return;
  }
  final gesture = await tester.startGesture(tester.getCenter(column));
  await gesture.moveBy(const Offset(0.0, -20.0));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.moveBy(const Offset(0.0, 20.0));
  await tester.pump(const Duration(milliseconds: 50));
  var left = centre - tester.getCenter(row).dy;
  while (left.abs() > 0.0) {
    final step = left.abs() > 8.0 ? 8.0 * left.sign : left;
    await gesture.moveBy(Offset(0.0, step));
    await tester.pump(const Duration(milliseconds: 50));
    left -= step;
  }
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await tester.pumpAndSettle();
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
  expect(timeFieldShows("Start time", start), findsOneWidget);
  expect(timeFieldShows("End time", end), findsOneWidget);
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
