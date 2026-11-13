/// The item form's sheet and its schedule section: the sheet's container
/// and type selector, the message of each schedule problem, and the
/// section's summary, length and All day chips, End date, next free time,
/// zone, options and kept kind.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/item_form.dart';
import 'package:workspace_calendar/workspace_calendar/schedule_section.dart';

import 'form_driver.dart';

final DateTime wednesday = DateTime(2026, 4, 22);

DateTime at(int hour, [int minute = 0]) {
  return DateTime(2026, 4, 22, hour, minute);
}

/// A Task [id] titled [title] from [start] to [end].
CalendarItem task(
  String id,
  String title,
  DateTime start,
  DateTime end, {
  bool isAllDay = false,
}) {
  return calendarItem(
    id: id,
    type: CalendarItemType.task,
    title: title,
    start: start,
    end: end,
    fields: const <String, Object?>{"status": "toDo"},
    isAllDay: isAllDay,
  );
}

CalendarNow wednesdayStart() {
  return CalendarNow(time: wednesday, today: wednesday);
}

/// Pumps a host over [store] whose one button runs [open], and taps it.
Future<void> openWith(
  WidgetTester tester,
  void Function(BuildContext context) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                open(context);
              },
              child: const Text("Open"),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text("Open"));
  await tester.pumpAndSettle();
}

/// Opens the form of the stored [id].
Future<void> openEdit(
  WidgetTester tester,
  CalendarStore<ItemPayload> store, {
  String id = "item-1",
}) {
  return openWith(tester, (context) {
    showEditForm(
      context,
      store: store,
      id: id,
      policy: const UnrestrictedEditPolicy<ItemPayload>(),
      now: wednesdayStart,
    );
  });
}

/// Opens the create flow over [range].
Future<void> openCreate(
  WidgetTester tester,
  CalendarStore<ItemPayload> store,
  CalendarCreateRange range,
) {
  return openWith(tester, (context) {
    showCreateFlow(
      context,
      store: store,
      range: range,
      policy: const UnrestrictedEditPolicy<ItemPayload>(),
      now: wednesdayStart,
    );
  });
}

String summary(WidgetTester tester) {
  return tester.widget<Text>(find.byKey(scheduleSummaryKey)).data!;
}

MemoryCalendarStore<ItemPayload> storeOf(List<CalendarItem> items) {
  return MemoryCalendarStore<ItemPayload>(entries: items);
}

/// The check of [schedule] under [policy] at Wednesday's start, in the
/// calendar's whole day of 15-minute slots, for the stored [entry] or a new
/// one, with [options] or a Task's.
CalendarScheduleCheck<ItemPayload> checkOf(
  CalendarSchedule schedule, {
  CalendarEditPolicy<ItemPayload> policy =
      const UnrestrictedEditPolicy<ItemPayload>(),
  CalendarItem? entry,
  CalendarScheduleOptions? options,
}) {
  return CalendarScheduleCheck<ItemPayload>(
    schedule: schedule,
    rules: CalendarEditRules<ItemPayload>(
      policy: policy,
      hours: CalendarDayHours.allDay,
      slotMinutes: 15,
    ),
    now: wednesdayStart(),
    entry: entry,
    options: options ?? scheduleOptionsOf(CalendarItemType.task),
  );
}

/// Pumps the section of [check] alone.
Future<void> pumpSection(
  WidgetTester tester,
  CalendarScheduleCheck<ItemPayload> check,
) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScheduleSection(
            check: check,
            hours: CalendarDayHours.allDay,
            slotMinutes: 15,
            onChanged: (schedule) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(tz_data.initializeTimeZones);

  testWidgets("SF1 the form is a bottom sheet that neither a drag nor the "
      "barrier closes, and the back gesture does", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    await tester.drag(find.text("Edit Task"), const Offset(0.0, 600.0));
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsOneWidget);
    await tester.tapAt(const Offset(10.0, 10.0));
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsNothing);
  });

  testWidgets("SF2 a create picks its type in the sheet, Task first, and a "
      "new type keeps the title and the schedule and shows its own fields", (
    tester,
  ) async {
    final store = storeOf(<CalendarItem>[]);
    addTearDown(store.dispose);
    await openCreate(
      tester,
      store,
      CalendarCreateRange(start: at(9), end: at(10)),
    );
    expect(find.text("New item"), findsOneWidget);
    final selector = tester.widget<SegmentedButton<CalendarItemType>>(
      find.byType(SegmentedButton<CalendarItemType>),
    );
    expect(selector.selected, <CalendarItemType>{CalendarItemType.task});
    expect(dropdownFinder("Status"), findsOneWidget);

    await tester.enterText(fieldFinder("Title"), "Launch");
    await chooseOption(tester, "Start time", "11:00");
    await tester.tap(find.text("Risk").last);
    await tester.pumpAndSettle();
    expect(fieldText(tester, "Title"), "Launch");
    expect(dropdownShows("Start time", "11:00"), findsOneWidget);
    expect(dropdownShows("End time", "12:00"), findsOneWidget);
    expect(fieldFinder("Project"), findsOneWidget);
    expect(dropdownFinder("Status"), findsNothing);
    expect(dropdownShows("Severity", "Medium"), findsOneWidget);
  });

  testWidgets("SF3 an edit shows no type selector, and a read-only item its "
      "summary and Close alone", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(find.text("Edit Task"), findsOneWidget);
    expect(find.byType(SegmentedButton<CalendarItemType>), findsNothing);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openWith(tester, (context) {
      showItemDetails(context, store: store, id: "item-1");
    });
    expect(find.byType(SegmentedButton<CalendarItemType>), findsNothing);
    expect(summary(tester), "Wed, Apr 22, 09:00 - 10:00 (1h)");
    expect(formButton("Close"), findsOneWidget);
    expect(formButton("Cancel"), findsNothing);
    expect(saveFinder(), findsNothing);
    expect(find.text("Ends on another day"), findsNothing);
  });

  test("SF4 every schedule problem has its own message in the form", () {
    final other = task("item-2", "Standup", at(9), at(10));
    final problems = <CalendarScheduleProblem>[
      const CalendarScheduleEndNotAfterStart(),
      const CalendarScheduleTooManyDays(),
      const CalendarScheduleSpansDays(),
      const CalendarScheduleAllDayNotAllowed(),
      const CalendarScheduleStartSkipped(),
      const CalendarScheduleEndSkipped(),
      const CalendarScheduleOutsideHours(atEnd: false),
      const CalendarSchedulePastDay(),
      const CalendarScheduleBeforeEarliest(),
      const CalendarScheduleLocked(),
      const CalendarScheduleStartKept(),
      const CalendarScheduleKindKept(),
      const CalendarScheduleEndInPast(),
      CalendarScheduleOverlapRefused<ItemPayload>(other),
      const CalendarScheduleRefused(),
    ];
    final fallback = scheduleProblemMessage(const _Unnamed());
    for (final problem in problems) {
      expect(
        scheduleProblemMessage(problem),
        isNot(fallback),
        reason: "$problem",
      );
    }
    expect(scheduleProblemMessage(problems[13]), "Overlaps Standup.");
    expect(
      scheduleErrorsOf(<CalendarScheduleProblem>[
        const CalendarScheduleBeforeEarliest(),
        const CalendarSchedulePastDay(),
        const CalendarScheduleEndInPast(),
      ]),
      <String, String>{
        "start": "The start can't be in the past.",
        "end": "The end can't be in the past.",
      },
    );
  });

  testWidgets("SS1 SS2 the summary reads the schedule, the chips are 15m, "
      "30m, 1h and All day, and a length chip sets the end", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10, 30)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(summary(tester), "Wed, Apr 22, 09:00 - 10:30 (1h 30m)");
    expect(chipLabels(tester), <String>["15m", "30m", "1h", "All day"]);

    await tester.tap(find.widgetWithText(ChoiceChip, "30m"));
    await tester.pumpAndSettle();
    expect(dropdownShows("End time", "09:30"), findsOneWidget);
    expect(summary(tester), "Wed, Apr 22, 09:00 - 09:30 (30m)");
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, "30m"))
          .selected,
      isTrue,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, "1h"));
    await tester.pumpAndSettle();
    expect(dropdownShows("End time", "10:00"), findsOneWidget);
  });

  testWidgets("SS3 End date shows for a multi-day or all-day item, or after "
      "Ends on another day", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Trip", at(22), DateTime(2026, 4, 23, 2)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(find.text("End date"), findsNothing);
    await tester.tap(find.text("Ends on another day"));
    await tester.pumpAndSettle();
    expect(formDateShows("End date", "2026-04-22"), findsOneWidget);
    expect(find.text("Ends on another day"), findsNothing);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store, id: "item-2");
    expect(formDateShows("End date", "2026-04-23"), findsOneWidget);
    expect(summary(tester), "Wed, Apr 22 22:00 - Thu, Apr 23 02:00 (4h)");
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store);
    await tester.tap(find.text("All day"));
    await tester.pumpAndSettle();
    expect(formDateShows("End date", "2026-04-22"), findsOneWidget);
    expect(dropdownFinder("Start time"), findsNothing);
    expect(summary(tester), "Wed, Apr 22, all day");
  });

  testWidgets("SS4 an overlap shows before Save, and Next free time moves "
      "the item to the first free range of its length", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Standup", at(9, 30), at(10, 30)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(
      find.descendant(
        of: find.byKey(scheduleOverlapKey),
        matching: find.text("Overlaps Standup"),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text("Next free time"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Next free time"));
    await tester.pumpAndSettle();
    expect(dropdownShows("Start time", "10:30"), findsOneWidget);
    expect(dropdownShows("End time", "11:30"), findsOneWidget);
    expect(find.byKey(scheduleOverlapKey), findsNothing);
  });

  testWidgets("SS5 a store on a zone names it in the section", (tester) async {
    final havana = tz.getLocation("America/Havana");
    final zoned = MemoryCalendarStore<ItemPayload>(
      zone: havana,
      entries: <CalendarItem>[
        task(
          "item-1",
          "Write",
          tz.TZDateTime(havana, 2026, 4, 22, 9),
          tz.TZDateTime(havana, 2026, 4, 22, 10),
        ),
      ],
    );
    addTearDown(zoned.dispose);
    await openEdit(tester, zoned);
    expect(find.text("Times in America/Havana"), findsOneWidget);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    final plain = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(plain.dispose);
    await openEdit(tester, plain);
    expect(find.textContaining("Times in"), findsNothing);
  });

  testWidgets("SS6 options that refuse all-day and spanning days show no All "
      "day chip and no Ends on another day, and options with neither "
      "lengths nor all-day no chip row", (tester) async {
    final schedule = CalendarSchedule.of(at(9), at(10), isAllDay: false);
    await pumpSection(tester, checkOf(schedule));
    expect(find.text("Ends on another day"), findsOneWidget);
    expect(chipLabels(tester), <String>["15m", "30m", "1h", "All day"]);

    await pumpSection(
      tester,
      checkOf(
        schedule,
        options: CalendarScheduleOptions(
          allowsAllDay: false,
          spansDays: false,
          lengthChoices: const <int>[45],
        ),
      ),
    );
    expect(find.text("All day"), findsNothing);
    expect(find.text("Ends on another day"), findsNothing);
    expect(chipLabels(tester), <String>["45m"]);

    await pumpSection(
      tester,
      checkOf(
        schedule,
        options: CalendarScheduleOptions(
          allowsAllDay: false,
          lengthChoices: const <int>[],
        ),
      ),
    );
    expect(find.byType(ChoiceChip), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ScheduleSection),
        matching: find.byType(Wrap),
      ),
      findsNothing,
    );
  });

  testWidgets("SS7 All day is the last chip: it hides the times and selects "
      "no length, tapped again it restores the times, and a length chip "
      "makes the item timed at that length", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10, 30)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(formAllDayOn(), isFalse);

    await tester.tap(allDayChip());
    await tester.pumpAndSettle();
    expect(summary(tester), "Wed, Apr 22, all day");
    expect(dropdownFinder("Start time"), findsNothing);
    expect(chipLabels(tester), <String>["15m", "30m", "1h", "All day"]);
    expect(chipLabels(tester, selectedOnly: true), <String>["All day"]);

    await tester.tap(allDayChip());
    await tester.pumpAndSettle();
    expect(summary(tester), "Wed, Apr 22, 09:00 - 10:30 (1h 30m)");
    expect(formAllDayOn(), isFalse);

    await tester.tap(allDayChip());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, "30m"));
    await tester.pumpAndSettle();
    expect(summary(tester), "Wed, Apr 22, 09:00 - 09:30 (30m)");
    expect(dropdownShows("Start time", "09:00"), findsOneWidget);
    expect(chipLabels(tester, selectedOnly: true), <String>["30m"]);
  });

  testWidgets("SS8 an item in progress keeps its kind: All day takes no "
      "tap, nor do an all-day item's lengths, and a timed item's do", (
    tester,
  ) async {
    const lock = HistoryLockPolicy<ItemPayload>();
    final allDay = task(
      "item-1",
      "Trip",
      DateTime(2026, 4, 21),
      DateTime(2026, 4, 24),
      isAllDay: true,
    );
    final allDayCheck = checkOf(
      CalendarSchedule.of(allDay.start, allDay.end, isAllDay: true),
      policy: lock,
      entry: allDay,
    );
    expect(allDayCheck.startFixed, isTrue);
    await pumpSection(tester, allDayCheck);
    expect(chipLabels(tester), <String>["15m", "30m", "1h", "All day"]);
    expect(chipsEnabled(tester), <bool>[false, false, false, false]);

    final timed = task("item-2", "Write", DateTime(2026, 4, 21, 22), at(10));
    final timedCheck = checkOf(
      CalendarSchedule.of(timed.start, timed.end, isAllDay: false),
      policy: lock,
      entry: timed,
    );
    expect(timedCheck.startFixed, isTrue);
    await pumpSection(tester, timedCheck);
    expect(chipLabels(tester), <String>["15m", "30m", "1h", "All day"]);
    expect(chipsEnabled(tester), <bool>[true, true, true, false]);
  });

  testWidgets("SS9 an all-day item made timed starts at the first free hour "
      "of the store's hours on its start day: All day off gives that hour, "
      "and a length chip that start", (tester) async {
    final store = MemoryCalendarStore<ItemPayload>(
      hours: CalendarDayHours(8 * 60, 18 * 60),
      entries: <CalendarItem>[
        task(
          "item-1",
          "Trip",
          wednesday,
          DateTime(2026, 4, 23),
          isAllDay: true,
        ),
        task("item-2", "Standup", at(8), at(9, 30)),
      ],
    );
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(summary(tester), "Wed, Apr 22, all day");
    await tester.tap(allDayChip());
    await tester.pumpAndSettle();
    expect(summary(tester), "Wed, Apr 22, 09:30 - 10:30 (1h)");
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openCreate(
      tester,
      store,
      CalendarCreateRange(
        start: wednesday,
        end: DateTime(2026, 4, 23),
        isAllDay: true,
      ),
    );
    expect(summary(tester), "Wed, Apr 22, all day");
    await tester.tap(find.widgetWithText(ChoiceChip, "30m"));
    await tester.pumpAndSettle();
    expect(summary(tester), "Wed, Apr 22, 09:30 - 10:00 (30m)");
  });
}

/// A problem the form has no message of its own for.
final class _Unnamed extends CalendarScheduleProblem {
  const _Unnamed();

  @override
  bool get atEnd {
    return false;
  }
}
