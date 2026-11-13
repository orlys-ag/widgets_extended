/// The item form's sheet and its schedule section: the sheet's container
/// and type selector, the message of each schedule problem, and the
/// section's summary, length and All day chips, End date, next free time,
/// zone, options and kept kind, and its time fields, the pickers they open,
/// what each picker refuses, and where the focus goes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/calendar/views/time_picker.dart'
    show
        timePickerHourColumnKey,
        timePickerHourRowKey,
        timePickerMinuteRowKey,
        timePickerNowKey;
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
      hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
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
      hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
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

/// Pumps the section of [check] alone, in the calendar's whole day of
/// 15-minute slots on the 24-hour clock, on [zone]'s clock, its pickers'
/// Now reading [now] or else Wednesday's start, its edits going to
/// [onChanged] or else nowhere, and locked where [locked].
Future<void> pumpSection(
  WidgetTester tester,
  CalendarScheduleCheck<ItemPayload> check, {
  Location? zone,
  ValueGetter<CalendarNow>? now,
  ValueChanged<CalendarSchedule>? onChanged,
  bool locked = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScheduleSection(
            check: check,
            hours: CalendarDayHours.allDay,
            slotMinutes: 15,
            hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
            now: now ?? wednesdayStart,
            zone: zone,
            locked: locked,
            onChanged: onChanged ?? (schedule) {},
          ),
        ),
      ),
    ),
  );
}

/// What [finder] finds in the open picker of the form's time field
/// labelled [label].
Finder inPicker(String label, Finder finder) {
  return find.descendant(of: timePickerFinder(label), matching: finder);
}

/// Whether the row keyed [key] of the picker of the time field labelled
/// [label] takes a tap, which a row with no time the picker may pick, in a
/// picker that takes input, does not.
bool rowTakesTap(WidgetTester tester, String label, Key key) {
  return tester
          .widget<GestureDetector>(inPicker(label, find.byKey(key)))
          .onTap !=
      null;
}

/// The hours the Hour column of the picker of the time field labelled
/// [label] has rows for.
List<int> hourRows(String label) {
  return <int>[
    for (var hour = 0; hour <= 24; hour++)
      if (inPicker(
        label,
        find.byKey(timePickerHourRowKey(hour)),
      ).evaluate().isNotEmpty)
        hour,
  ];
}

/// The minutes the Minute column of the picker of the time field labelled
/// [label] has rows for.
List<int> minuteRows(String label) {
  return <int>[
    for (var minute = 0; minute < 60; minute++)
      if (inPicker(
        label,
        find.byKey(timePickerMinuteRowKey(minute)),
      ).evaluate().isNotEmpty)
        minute,
  ];
}

/// Whether the primary focus lies on or under the one element [finder]
/// finds.
bool focusUnder(Finder finder) {
  final target = finder.evaluate().single;
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) {
    return false;
  }
  var under = identical(focused, target);
  focused.visitAncestorElements((ancestor) {
    under = under || identical(ancestor, target);
    return !under;
  });
  return under;
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
    await pickTime(tester, "Start time", "11:00");
    // The open picker scrolled the form to reveal it.
    await tester.ensureVisible(find.text("Risk").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Risk").last);
    await tester.pumpAndSettle();
    expect(fieldText(tester, "Title"), "Launch");
    expect(timeFieldShows("Start time", "11:00"), findsOneWidget);
    expect(timeFieldShows("End time", "12:00"), findsOneWidget);
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
      showItemDetails(
        context,
        store: store,
        id: "item-1",
        hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
      );
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
    expect(timeFieldShows("End time", "09:30"), findsOneWidget);
    expect(summary(tester), "Wed, Apr 22, 09:00 - 09:30 (30m)");
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, "30m"))
          .selected,
      isTrue,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, "1h"));
    await tester.pumpAndSettle();
    expect(timeFieldShows("End time", "10:00"), findsOneWidget);
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
    expect(timeFieldFinder("Start time"), findsNothing);
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
    expect(timeFieldShows("Start time", "10:30"), findsOneWidget);
    expect(timeFieldShows("End time", "11:30"), findsOneWidget);
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
    expect(timeFieldFinder("Start time"), findsNothing);
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
    expect(timeFieldShows("Start time", "09:00"), findsOneWidget);
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

  testWidgets("TF1 a tap on Start time opens its picker under the time row, "
      "a pick there settles into the schedule, a tap on End time opens the "
      "end's picker alone and a second tap closes it; a fixed start's field "
      "opens none", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(find.byKey(scheduleStartPickerKey), findsNothing);

    await tester.tap(timeFieldFinder("Start time"));
    await tester.pumpAndSettle();
    expect(find.byKey(scheduleStartPickerKey), findsOneWidget);
    expect(
      tester.getRect(find.byKey(scheduleStartPickerKey)).top,
      greaterThan(tester.getRect(timeFieldFinder("Start time")).bottom),
    );
    await tester.tap(
      inPicker("Start time", find.byKey(timePickerMinuteRowKey(30))),
    );
    await tester.pumpAndSettle();
    expect(summary(tester), "Wed, Apr 22, 09:30 - 10:30 (1h)");

    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(find.byKey(scheduleEndPickerKey), findsOneWidget);
    expect(find.byKey(scheduleStartPickerKey), findsNothing);
    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(find.byKey(scheduleEndPickerKey), findsNothing);
    expect(find.byKey(scheduleStartPickerKey), findsNothing);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    const lock = HistoryLockPolicy<ItemPayload>();
    final timed = task("item-2", "Write", DateTime(2026, 4, 21, 22), at(10));
    final fixed = checkOf(
      CalendarSchedule.of(timed.start, timed.end, isAllDay: false),
      policy: lock,
      entry: timed,
    );
    expect(fixed.startFixed, isTrue);
    await pumpSection(tester, fixed);
    await tester.tap(timeFieldFinder("Start time"));
    await tester.pumpAndSettle();
    expect(find.byKey(scheduleStartPickerKey), findsNothing);
  });

  testWidgets("TF2 the pickers offer the hours' times: the start's to the "
      "hours' last slot, its own time shown besides, the end's after the "
      "hours' first slot, and of an end on its start's day past the hours' "
      "end only its own", (tester) async {
    final store = MemoryCalendarStore<ItemPayload>(
      hours: CalendarDayHours(8 * 60, 18 * 60),
      entries: <CalendarItem>[
        task("item-1", "Early", at(7), at(9)),
        task("item-2", "Late", at(19), at(20)),
      ],
    );
    addTearDown(store.dispose);
    await openEdit(tester, store);
    await openTimePicker(tester, "Start time");
    expect(offeredTimes(tester, "Start time"), <int>[
      for (var minute = 8 * 60; minute <= 17 * 60 + 45; minute += 15) minute,
    ]);
    // The start, 07:00, lies before the hours: shown, not offered.
    expect(hourRows("Start time"), contains(7));
    await openTimePicker(tester, "End time");
    expect(offeredTimes(tester, "End time"), <int>[
      for (var minute = 8 * 60 + 15; minute <= 18 * 60; minute += 15) minute,
    ]);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store, id: "item-2");
    await openTimePicker(tester, "End time");
    expect(hourRows("End time"), <int>[20]);
    expect(minuteRows("End time"), <int>[0]);
    final end = tester.widget<CalendarTimePicker>(timePickerFinder("End time"));
    expect(end.min, 20 * 60);
    expect(end.max, 20 * 60);
    expect(rowTakesTap(tester, "End time", timePickerHourRowKey(20)), isTrue);
    expect(rowTakesTap(tester, "End time", timePickerMinuteRowKey(0)), isTrue);
  });

  testWidgets("TF3 the pickers refuse what the schedule check refuses: a "
      "start before now under the history lock, and on a clock that skips "
      "its midnight hour a start or an end in that hour, but not the 24:00 "
      "before it", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Later", at(12), at(13)),
    ]);
    addTearDown(store.dispose);
    await openWith(tester, (context) {
      showEditForm(
        context,
        store: store,
        id: "item-1",
        policy: const HistoryLockPolicy<ItemPayload>(lockEarlierToday: true),
        now: () {
          return CalendarNow(time: at(10, 20), today: wednesday);
        },
        hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
      );
    });
    await openTimePicker(tester, "Start time");
    expect(timeEnabled(tester, "Start time", "10:00"), isFalse);
    expect(timeEnabled(tester, "Start time", "11:15"), isTrue);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    final havana = tz.getLocation("America/Havana");
    // Setup sanity: Havana's clock never reads 00:30 on 2026-03-08.
    expect(tz.TZDateTime(havana, 2026, 3, 8, 0, 30).hour, isNot(0));
    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(
          DateTime(2026, 3, 8, 1),
          DateTime(2026, 3, 8, 2),
          isAllDay: false,
        ),
      ),
      zone: havana,
    );
    await openTimePicker(tester, "Start time");
    for (final time in <String>["00:00", "00:15", "00:30", "00:45"]) {
      expect(timeEnabled(tester, "Start time", time), isFalse, reason: time);
    }
    expect(rowTakesTap(tester, "Start time", timePickerHourRowKey(0)), isFalse);
    expect(timeEnabled(tester, "Start time", "01:00"), isTrue);
    await closeTimePicker(tester, "Start time");

    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(
          DateTime(2026, 3, 7, 22),
          DateTime(2026, 3, 8, 2),
          isAllDay: false,
        ),
      ),
      zone: havana,
    );
    await openTimePicker(tester, "End time");
    for (final time in <String>["00:15", "00:30", "00:45"]) {
      expect(timeEnabled(tester, "End time", time), isFalse, reason: time);
    }
    expect(rowTakesTap(tester, "End time", timePickerHourRowKey(0)), isFalse);
    expect(timeEnabled(tester, "End time", "01:00"), isTrue);
    await closeTimePicker(tester, "End time");

    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(
          DateTime(2026, 3, 7, 22),
          DateTime(2026, 3, 7, 23),
          isAllDay: false,
        ).withEndMinute(CalendarDates.minutesPerDay),
      ),
      zone: havana,
    );
    await openTimePicker(tester, "End time");
    expect(rowTakesTap(tester, "End time", timePickerHourRowKey(24)), isTrue);
    expect(timeEnabled(tester, "End time", "24:00"), isTrue);
  });

  testWidgets("TF4 the form's Now picks the minute the form's now reads on "
      "the store's clock, rounded down to the slot", (tester) async {
    final kolkata = tz.getLocation("Asia/Kolkata");
    final store = MemoryCalendarStore<ItemPayload>(
      zone: kolkata,
      entries: <CalendarItem>[
        task(
          "item-1",
          "Write",
          tz.TZDateTime(kolkata, 2026, 4, 22, 11),
          tz.TZDateTime(kolkata, 2026, 4, 22, 12),
        ),
      ],
    );
    addTearDown(store.dispose);
    await openWith(tester, (context) {
      showEditForm(
        context,
        store: store,
        id: "item-1",
        policy: const UnrestrictedEditPolicy<ItemPayload>(),
        now: () {
          // 09:13 in Kolkata.
          return CalendarNow(
            time: DateTime.utc(2026, 4, 22, 3, 43),
            today: wednesday,
          );
        },
        hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
      );
    });
    expect(summary(tester), "Wed, Apr 22, 11:00 - 12:00 (1h)");
    await openTimePicker(tester, "Start time");
    await tester.tap(inPicker("Start time", find.byKey(timePickerNowKey)));
    await tester.pumpAndSettle();
    // The nearest slot would be 09:15.
    expect(summary(tester), "Wed, Apr 22, 09:00 - 10:00 (1h)");
  });

  testWidgets("TF5 the start's picker stays open across Next free time, a "
      "length chip and a new start date, and All day closes it and focuses "
      "the chip", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Standup", at(9, 30), at(10, 30)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    await openTimePicker(tester, "Start time");

    await tester.ensureVisible(find.text("Next free time"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Next free time"));
    await tester.pumpAndSettle();
    expect(summary(tester), "Wed, Apr 22, 10:30 - 11:30 (1h)");
    expect(find.byKey(scheduleStartPickerKey), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, "30m"));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, "30m"));
    await tester.pumpAndSettle();
    expect(summary(tester), "Wed, Apr 22, 10:30 - 11:00 (30m)");
    expect(find.byKey(scheduleStartPickerKey), findsOneWidget);

    await tester.ensureVisible(formDateFinder("Start date"));
    await tester.pumpAndSettle();
    await tester.tap(formDateFinder("Start date"));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text("23"),
      ),
    );
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    expect(summary(tester), "Thu, Apr 23, 10:30 - 11:00 (30m)");
    expect(find.byKey(scheduleStartPickerKey), findsOneWidget);

    await tester.ensureVisible(allDayChip());
    await tester.pumpAndSettle();
    await tester.tap(allDayChip());
    await tester.pumpAndSettle();
    expect(summary(tester), "Thu, Apr 23, all day");
    expect(find.byKey(scheduleStartPickerKey), findsNothing);
    expect(focusUnder(allDayChip()), isTrue);
  });

  testWidgets("TF8 the focus follows the open picker: its Hour column takes "
      "it as the picker opens, from the other picker too, and its field as "
      "it closes", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    await tester.tap(timeFieldFinder("Start time"));
    await tester.pumpAndSettle();
    expect(
      focusUnder(inPicker("Start time", find.byKey(timePickerHourColumnKey))),
      isTrue,
    );

    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(
      focusUnder(inPicker("End time", find.byKey(timePickerHourColumnKey))),
      isTrue,
    );

    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(timePickerFinder("End time"), findsNothing);
    expect(focusUnder(timeFieldFinder("End time")), isTrue);
  });

  testWidgets("TF9 a picker opened past the bottom of the view scrolls into "
      "it in the next frame", (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390.0, 300.0);
    addTearDown(tester.view.reset);
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(10), isAllDay: false)),
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, 0.0);

    await tester.tap(timeFieldFinder("Start time"));
    await tester.pump();
    // Setup sanity: the picker opened past the view's bottom, so the view
    // scrolled to reveal it.
    expect(position.pixels, greaterThan(0.0));
    final picker = tester.getRect(find.byKey(scheduleStartPickerKey));
    expect(picker.top, greaterThanOrEqualTo(0.0));
    expect(picker.bottom, lessThanOrEqualTo(300.0));
  });

  testWidgets("TF11 an open picker stays open as its field locks and takes "
      "no pick, and closed from its field gives the field the focus", (
    tester,
  ) async {
    final timed = task("item-2", "Write", DateTime(2026, 4, 21, 22), at(10));
    final schedule = CalendarSchedule.of(
      timed.start,
      timed.end,
      isAllDay: false,
    );
    final changes = <CalendarSchedule>[];
    await pumpSection(
      tester,
      checkOf(schedule, entry: timed),
      onChanged: changes.add,
    );
    await openTimePicker(tester, "Start time");
    expect(timePickerFinder("Start time"), findsOneWidget);

    final fixed = checkOf(
      schedule,
      policy: const HistoryLockPolicy<ItemPayload>(),
      entry: timed,
    );
    expect(fixed.startFixed, isTrue);
    await pumpSection(tester, fixed, onChanged: changes.add);
    await tester.pumpAndSettle();
    expect(timePickerFinder("Start time"), findsOneWidget);
    await tester.tap(
      inPicker("Start time", find.byKey(timePickerHourRowKey(23))),
    );
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(
      focusUnder(inPicker("Start time", find.byKey(timePickerHourColumnKey))),
      isTrue,
    );

    await tester.tap(timeFieldFinder("Start time"));
    await tester.pumpAndSettle();
    expect(timePickerFinder("Start time"), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.context,
      same(tester.element(timeFieldFinder("Start time"))),
    );

    await openTimePicker(tester, "End time");
    expect(timePickerFinder("End time"), findsOneWidget);
    await pumpSection(tester, fixed, onChanged: changes.add, locked: true);
    await tester.pumpAndSettle();
    expect(timePickerFinder("End time"), findsOneWidget);
    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(timePickerFinder("End time"), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.context,
      same(tester.element(timeFieldFinder("End time"))),
    );
  });

  testWidgets("TF12 a keyboard sliding in under the form does not rebuild "
      "its open picker", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    addTearDown(tester.view.resetViewInsets);
    await openEdit(tester, store);
    await openTimePicker(tester, "Start time");
    final picker = tester.element(timePickerFinder("Start time"));
    final save = tester.getRect(saveFinder()).bottom;
    final ratio = tester.view.devicePixelRatio;
    final rebuilt = <Element>[];
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (identical(element, picker)) {
        rebuilt.add(element);
      }
    };
    try {
      for (var frame = 1; frame <= 5; frame++) {
        tester.view.viewInsets = FakeViewPadding(
          bottom: 300.0 * ratio * frame / 5,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    // Setup sanity: the inset reached the form, which it lifted.
    expect(tester.getRect(saveFinder()).bottom, moreOrLessEquals(save - 300.0));
    expect(rebuilt, isEmpty);
  });

  testWidgets("TF13 a picker closed while its column still moves drops "
      "that motion's pick, and its field keeps its time", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    final hourColumn = inPicker(
      "Start time",
      find.byKey(timePickerHourColumnKey),
    );
    await openEdit(tester, store);
    await openTimePicker(tester, "Start time");
    // Setup sanity: left to settle, the fling picks another start.
    await tester.fling(hourColumn, const Offset(0.0, -120.0), 1000.0);
    await tester.pumpAndSettle();
    expect(timeFieldShows("Start time", "09:00"), findsNothing);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store);
    await openTimePicker(tester, "Start time");
    await tester.fling(hourColumn, const Offset(0.0, -120.0), 1000.0);
    await tester.pump();
    await tester.pump();
    // Setup sanity: the motion still runs, its pick not yet reported.
    expect(timeFieldShows("Start time", "09:00"), findsOneWidget);
    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(timePickerFinder("End time"), findsOneWidget);
    expect(timePickerFinder("Start time"), findsNothing);
    expect(timeFieldShows("Start time", "09:00"), findsOneWidget);
  });

  testWidgets("TF14 the start's picker refuses each start before the first "
      "the check allows, and takes the stored item's own start", (
    tester,
  ) async {
    final item = task("item-1", "Write", at(9), at(10));
    final check = checkOf(
      CalendarSchedule.of(item.start, item.end, isAllDay: false),
      policy: const _StartsFromTen(),
      entry: item,
    );
    // Setup sanity: the check's first start lies after the item's start.
    expect(check.firstStartMinute, 10 * 60);
    await pumpSection(tester, check);
    await openTimePicker(tester, "Start time");
    expect(
      rowTakesTap(tester, "Start time", timePickerMinuteRowKey(0)),
      isTrue,
    );
    expect(rowTakesTap(tester, "Start time", timePickerHourRowKey(9)), isTrue);
    for (var hour = 0; hour <= 8; hour++) {
      expect(
        rowTakesTap(tester, "Start time", timePickerHourRowKey(hour)),
        isFalse,
        reason: "hour $hour",
      );
    }
    for (final minute in <int>[15, 30, 45]) {
      expect(
        rowTakesTap(tester, "Start time", timePickerMinuteRowKey(minute)),
        isFalse,
        reason: "minute $minute",
      );
    }
  });
}

/// A policy whose earliest start on a day is 10:00 of it.
final class _StartsFromTen extends CalendarEditPolicy<ItemPayload> {
  const _StartsFromTen();

  @override
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    return DateTime(day.year, day.month, day.day, 10);
  }
}

/// A problem the form has no message of its own for.
final class _Unnamed extends CalendarScheduleProblem {
  const _Unnamed();

  @override
  bool get atEnd {
    return false;
  }
}
