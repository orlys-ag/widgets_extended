/// The history lock in the app: its switches in the settings sheet, the
/// item form's errors, and what it keeps as it is in Week, Agenda and Month
/// and in the item form.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/policy/history_lock.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_settings.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/settings_sheet.dart';

import 'calendar_harness.dart';

const Size tall = Size(390.0, 1400.0);

final DateTime sunday = DateTime(2026, 4, 19);
final DateTime monday = DateTime(2026, 4, 20);
final DateTime wednesday = DateTime(2026, 4, 22);
final DateTime thursday = DateTime(2026, 4, 23);

/// 11:07 on [today]: after [endedId] ends, while [runningId] runs and
/// before [laterId] starts.
final DateTime midMorning = DateTime(2026, 4, 21, 11, 7);

const String pastId = "item-1";
const String endedId = "item-2";
const String runningId = "item-3";
const String laterId = "item-4";

/// [pastId] on Monday, before today, and today's [endedId], [runningId]
/// and [laterId], in this order.
final List<Map<String, Object?>> seed = <Map<String, Object?>>[
  taskJson("Past", monday, 9 * 60, 10 * 60),
  taskJson("Ended", today, 8 * 60, 9 * 60),
  taskJson("Running", today, 10 * 60, 12 * 60),
  taskJson("Later", today, 14 * 60, 15 * 60),
];

CalendarEntryTime shape(DateTime day, int start, int end, {int dayCount = 1}) {
  return (firstDay: dayNumber(day), dayCount: dayCount, start: start, end: end);
}

/// The calendar over [seed] in edit mode, its clock reading [clock], or
/// [midMorning] without one, with the history lock on, to now unless
/// [earlierToday] is false.
Future<MockCalendarApi> pumpLocked(
  WidgetTester tester, {
  DateTime Function()? clock,
  bool earlierToday = true,
}) async {
  final api = MockCalendarApi(seed: seed, latency: harnessLatency);
  await pumpCalendar(
    tester,
    api: api,
    size: tall,
    editing: true,
    clock:
        clock ??
        () {
          return midMorning;
        },
  );
  await openSettings(tester);
  await tester.tap(find.byKey(lockPastKey));
  await tester.pumpAndSettle();
  if (earlierToday) {
    await tester.tap(find.byKey(lockEarlierTodayKey));
    await tester.pumpAndSettle();
  }
  await tester.tapAt(const Offset(195.0, 20.0));
  await tester.pumpAndSettle();
  return api;
}

Offset centerOf(WidgetTester tester, int minute, int weekday) {
  return cellRect(tester, rowOf(minute), colOf(weekday)).center;
}

Finder formButton(String label) {
  return find.widgetWithText(TextButton, label);
}

Finder dropdownFinder(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byType(DropdownButtonFormField<int>),
  );
}

/// The time the form's [label] dropdown shows.
Finder dropdownShows(String label, String time) {
  return find.descendant(of: dropdownFinder(label), matching: find.text(time));
}

/// Picks [option] in the form's dropdown labelled [label], scrolling its
/// menu by [delta], forward for a positive one, until the option shows.
Future<void> chooseOption(
  WidgetTester tester,
  String label,
  String option,
  double delta,
) async {
  await tester.tap(dropdownFinder(label));
  await tester.pumpAndSettle();
  final menu = find.byType(Scrollable).last;
  final item = find.descendant(of: menu, matching: find.text(option));
  await tester.scrollUntilVisible(item, delta, scrollable: menu);
  await Scrollable.ensureVisible(tester.element(item), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

/// Drags from [from] by [delta] with a mouse, and lets the write it causes
/// complete.
Future<void> mouseDrag(
  WidgetTester tester,
  MockCalendarApi api,
  Offset from,
  Offset delta,
) async {
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(delta);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
  await tester.pump(api.latency);
  await tester.pumpAndSettle();
}

/// The menu button of [id]'s card in Agenda.
Finder menuOf(String id) {
  return find.descendant(
    of: find.byKey(itemCardKey(id)),
    matching: find.bySemanticsLabel("Item actions"),
  );
}

/// The entries of [id]'s card menu, opened and closed again.
Future<List<String>> menuEntriesOf(WidgetTester tester, String id) async {
  await tester.tap(menuOf(id));
  await tester.pumpAndSettle();
  final entries = <String>[
    for (final label in <String>["Edit", "Delete"])
      if (find.text(label).evaluate().isNotEmpty) label,
  ];
  await tester.tapAt(const Offset(10.0, 10.0));
  await tester.pumpAndSettle();
  return entries;
}

/// The add buttons of the Agenda row [key] names.
Finder addButtonsOf(Key key) {
  return find.descendant(
    of: find.byKey(key),
    matching: find.bySemanticsLabel(RegExp("^Add an item at ")),
  );
}

void main() {
  group("HistoryLock", () {
    test("K5 the form's errors name the day of a new item on a past day, "
        "the start of one before now, a started item's moved start and "
        "past end, and nothing the lock admits", () {
      final lock = HistoryLock.of(
        lockPast: true,
        lockEarlierToday: true,
        today: today,
        now: midMorning,
      );
      final running = shape(today, 10 * 60, 12 * 60);
      expect(
        lockErrorsOf(lock, null, shape(monday, 9 * 60, 10 * 60)).keys,
        <String>["day"],
      );
      expect(
        lockErrorsOf(lock, null, shape(today, 9 * 60, 10 * 60)).keys,
        <String>["startMinute"],
      );
      expect(
        lockErrorsOf(lock, running, shape(today, 10 * 60 + 15, 11 * 60)).keys,
        <String>["startMinute", "endMinute"],
      );
      expect(
        lockErrorsOf(lock, running, shape(today, 10 * 60, 13 * 60)),
        isEmpty,
      );
      expect(
        lockErrorsOf(
          lock,
          shape(today, 8 * 60, 9 * 60),
          shape(today, 8 * 60, 9 * 60 + 15),
        ).keys,
        <String>["day"],
      );
    });

    test("K6 CalendarSettings starts unlocked, and its two lock switches "
        "take part in copyWith and ==", () {
      const settings = CalendarSettings();
      expect(settings.lockPast, isFalse);
      expect(settings.lockEarlierToday, isFalse);
      final locked = settings.copyWith(lockPast: true, lockEarlierToday: true);
      final kept = locked.copyWith(minSlotHeight: 20.0);
      expect(kept.lockPast, isTrue);
      expect(kept.lockEarlierToday, isTrue);
      final pastOnly = settings.copyWith(lockPast: true);
      expect(pastOnly == settings, isFalse);
      expect(pastOnly.hashCode == settings.hashCode, isFalse);
      expect(locked == pastOnly, isFalse);
      expect(locked.hashCode == pastOnly.hashCode, isFalse);
    });
  });

  testWidgets("K7 the sheet's Lock earlier today takes input only while "
      "Lock past days is on, and each switch sets its setting", (tester) async {
    CalendarSettings? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarSettingsSheet(
            settings: const CalendarSettings(),
            onChanged: (settings) {
              reported = settings;
            },
          ),
        ),
      ),
    );
    SwitchListTile earlierToday() {
      return tester.widget<SwitchListTile>(find.byKey(lockEarlierTodayKey));
    }

    expect(earlierToday().onChanged, isNull);
    await tester.tap(find.byKey(lockPastKey));
    await tester.pump();
    expect(reported?.lockPast, isTrue);
    expect(earlierToday().onChanged, isNotNull);
    await tester.tap(find.byKey(lockEarlierTodayKey));
    await tester.pump();
    expect(reported?.lockEarlierToday, isTrue);
  });

  testWidgets("K8 in Week a past block does not lift, and a later one "
      "moves after now but not before it", (tester) async {
    await pumpLocked(tester);
    await pickMode(tester, "Week");
    final past = tester.getRect(blockFinder(pastId));
    await moveBlock(
      tester,
      blockFinder(pastId),
      cellRect(tester, rowOf(9 * 60), colOf(2)).topLeft,
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(blockFinder(pastId)), past);
    expect(find.byKey(blockHandlesKey(pastId)), findsNothing);

    final later = tester.getRect(blockFinder(laterId));
    await moveBlock(
      tester,
      blockFinder(laterId),
      cellRect(tester, rowOf(14 * 60), colOf(0)).topLeft,
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(blockFinder(laterId)), later);

    final thursdayCell = cellRect(tester, rowOf(14 * 60), colOf(3));
    await moveBlock(tester, blockFinder(laterId), thursdayCell.topLeft);
    await tester.pump(harnessLatency);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(blockFinder(laterId)).topLeft,
      offsetMoreOrLessEquals(thursdayCell.topLeft, epsilon: 0.5),
    );
  });

  testWidgets("K9 in Week a long press selects a running block without "
      "lifting it, which has no top handle, and its bottom handle extends "
      "it, or shortens it to a slot after now but not before it", (
    tester,
  ) async {
    final api = await pumpLocked(tester);
    await pickMode(tester, "Week");
    final block = blockFinder(runningId);
    final cell = cellRect(tester, rowOf(10 * 60), colOf(1));

    final rect = tester.getRect(block);
    final gesture = await tester.startGesture(rect.center);
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveBy(Offset(cell.width, 0.0));
    await tester.pump();
    expect(find.byKey(liftedBlockKey), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(blockHandlesKey(runningId)), findsOneWidget);
    expect(find.byKey(blockGripKey(runningId, AxisDirection.up)), findsNothing);
    expect(
      find.byKey(blockGripKey(runningId, AxisDirection.down)),
      findsOneWidget,
    );

    await mouseDrag(
      tester,
      api,
      Offset(rect.center.dx, rect.bottom - 3.0),
      Offset(0.0, 2 * cell.height),
    );
    final longer = tester.getRect(block);
    expect(
      longer.bottom,
      moreOrLessEquals(rect.bottom + 2 * cell.height, epsilon: 0.5),
    );
    // 12:30 to 11:15, the first slot after 11:07.
    await mouseDrag(
      tester,
      api,
      Offset(longer.center.dx, longer.bottom - 3.0),
      Offset(0.0, -5 * cell.height),
    );
    final shortest = tester.getRect(block);
    expect(
      shortest.bottom,
      moreOrLessEquals(
        cellRect(tester, rowOf(11 * 60 + 15), colOf(1)).top,
        epsilon: 0.5,
      ),
    );
    await mouseDrag(
      tester,
      api,
      Offset(shortest.center.dx, shortest.bottom - 3.0),
      Offset(0.0, -cell.height),
    );
    expect(tester.getRect(block), shortest);
  });

  testWidgets("K10 in Week a press and hold before now creates nothing, and "
      "a range dragged up from after now, slot by slot or in one jump, stops "
      "at the first slot after it", (tester) async {
    // After Running ends, so the lock, not Running, stops the range.
    await pumpLocked(
      tester,
      clock: () {
        return DateTime(2026, 4, 21, 12, 37);
      },
    );
    await pickMode(tester, "Week");
    var gesture = await tester.startGesture(centerOf(tester, 9 * 60, 1));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text("New item"), findsNothing);

    gesture = await tester.startGesture(centerOf(tester, 13 * 60 + 30, 1));
    await tester.pump(const Duration(milliseconds: 600));
    for (var minute = 13 * 60 + 15; minute >= 9 * 60; minute -= 15) {
      await gesture.moveTo(centerOf(tester, minute, 1));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text("Task").last);
    await tester.pumpAndSettle();
    expect(dropdownShows("Start", "12:45"), findsOneWidget);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    gesture = await tester.startGesture(centerOf(tester, 13 * 60 + 30, 1));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(centerOf(tester, 9 * 60, 1));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text("Task").last);
    await tester.pumpAndSettle();
    expect(dropdownShows("Start", "12:45"), findsOneWidget);
  });

  testWidgets("K11 a past item's form is read-only; a running one's keeps "
      "its day and start, has no Delete and refuses an end before now; a "
      "later one's refuses a start before now", (tester) async {
    await pumpLocked(tester);
    await pickMode(tester, "Week");
    await tester.tap(blockFinder(pastId));
    await tester.pumpAndSettle();
    expect(formButton("Close"), findsOneWidget);
    await tester.tap(formButton("Close"));
    await tester.pumpAndSettle();

    await tester.tap(blockFinder(runningId));
    await tester.pumpAndSettle();
    expect(formButton("Delete"), findsNothing);
    final start = tester.widget<DropdownButtonFormField<int>>(
      dropdownFinder("Start"),
    );
    expect(start.onChanged, isNull);
    final day = tester.widget<InkWell>(
      find.ancestor(of: find.text("Day"), matching: find.byType(InkWell)),
    );
    expect(day.onTap, isNull);
    await chooseOption(tester, "End", "11:00", -100.0);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text("The end can't be in the past."), findsOneWidget);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await tester.tap(blockFinder(laterId));
    await tester.pumpAndSettle();
    expect(formButton("Delete"), findsOneWidget);
    await chooseOption(tester, "Start", "10:00", -100.0);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text("The start can't be in the past."), findsOneWidget);
  });

  testWidgets("K12 in Agenda an ended item's card has no menu, a running "
      "one's has Edit alone and a later one's both, and no dashed row "
      "before now, nor a past day's, has an add button", (tester) async {
    await pumpLocked(tester);
    expect(menuOf(endedId), findsNothing);
    expect(await menuEntriesOf(tester, runningId), <String>["Edit"]);
    expect(await menuEntriesOf(tester, laterId), <String>["Edit", "Delete"]);
    expect(addButtonsOf(dayListGapKey(today, 9 * 60)), findsNothing);
    expect(addButtonsOf(dayListGapKey(today, 12 * 60)), findsOneWidget);

    await tester.tap(find.byKey(dayCellKey(sunday)));
    await tester.pumpAndSettle();
    expect(addButtonsOf(dayListGapKey(sunday, 0)), findsNothing);
    await tester.tap(find.byKey(dayCellKey(thursday)));
    await tester.pumpAndSettle();
    expect(addButtonsOf(dayListGapKey(thursday, 0)), findsOneWidget);
  });

  testWidgets("K13 in Agenda the add button of a gap now falls in adds from "
      "the first slot after now", (tester) async {
    await pumpLocked(
      tester,
      clock: () {
        return DateTime(2026, 4, 21, 9, 37);
      },
    );
    await tester.tap(find.bySemanticsLabel("Add an item at 09:45"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Task").last);
    await tester.pumpAndSettle();
    expect(dropdownShows("Start", "09:45"), findsOneWidget);
  });

  testWidgets("K14 as now passes an item's start, its Agenda card loses "
      "Delete", (tester) async {
    var now = DateTime(2026, 4, 21, 13, 59);
    await pumpLocked(
      tester,
      clock: () {
        return now;
      },
    );
    expect(await menuEntriesOf(tester, laterId), <String>["Edit", "Delete"]);
    now = DateTime(2026, 4, 21, 14, 0, 30);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(await menuEntriesOf(tester, laterId), <String>["Edit"]);
  });

  testWidgets("K15 as now passes an item's start, its selected Week block "
      "loses its top handle", (tester) async {
    var now = DateTime(2026, 4, 21, 13, 59);
    await pumpLocked(
      tester,
      clock: () {
        return now;
      },
    );
    await pickMode(tester, "Week");
    await selectBlock(tester, laterId);
    final top = find.byKey(blockGripKey(laterId, AxisDirection.up));
    expect(top, findsOneWidget);
    now = DateTime(2026, 4, 21, 14, 0, 30);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(top, findsNothing);
  });

  testWidgets("K16 in Month a long press on a past day says it is locked "
      "and creates nothing, and on a later day creates", (tester) async {
    await pumpLocked(tester);
    await pickMode(tester, "Month");
    Future<void> longPress(DateTime day) async {
      final cell = tester.getRect(
        find.byKey(ValueKey<String>("month-day-${isoDate(day)}")),
      );
      await tester.longPressAt(Offset(cell.center.dx, cell.bottom - 4.0));
      await tester.pumpAndSettle();
    }

    await longPress(monday);
    expect(find.text("Past times are locked."), findsOneWidget);
    expect(find.text("New item"), findsNothing);
    await longPress(wednesday);
    expect(find.text("New item"), findsOneWidget);
  });

  testWidgets("K17 without Lock earlier today, today's ended item stays "
      "editable while a past day's is read-only", (tester) async {
    await pumpLocked(tester, earlierToday: false);
    await pickMode(tester, "Week");
    await tester.tap(blockFinder(endedId));
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();
    await tester.tap(blockFinder(pastId));
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsNothing);
  });
}
