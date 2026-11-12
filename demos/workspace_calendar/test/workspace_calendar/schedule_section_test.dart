/// The item form's sheet and its schedule section: the sheet's container
/// and type selector, the message of each schedule problem, and the
/// section's summary, lengths, End date, next free time, zone and options.
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

  testWidgets("SS1 SS2 the summary reads the schedule, and a length chip "
      "sets the end", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10, 30)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(summary(tester), "Wed, Apr 22, 09:00 - 10:30 (1h 30m)");

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

    await tester.tap(find.widgetWithText(ChoiceChip, "2h"));
    await tester.pumpAndSettle();
    expect(dropdownShows("End time", "11:00"), findsOneWidget);
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
    expect(find.byType(ChoiceChip), findsNothing);
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
      "day switch and no Ends on another day", (tester) async {
    final rules = CalendarEditRules<ItemPayload>(
      policy: const UnrestrictedEditPolicy<ItemPayload>(),
      hours: CalendarDayHours.allDay,
      slotMinutes: 15,
    );
    Future<void> pumpSection(CalendarScheduleOptions options) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScheduleSection(
                check: CalendarScheduleCheck<ItemPayload>(
                  schedule: CalendarSchedule.of(at(9), at(10), isAllDay: false),
                  rules: rules,
                  now: wednesdayStart(),
                  options: options,
                ),
                hours: CalendarDayHours.allDay,
                slotMinutes: 15,
                onChanged: (schedule) {},
              ),
            ),
          ),
        ),
      );
    }

    await pumpSection(CalendarScheduleOptions.standard);
    expect(find.text("All day"), findsOneWidget);
    expect(find.text("Ends on another day"), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(4));

    await pumpSection(
      CalendarScheduleOptions(
        allowsAllDay: false,
        spansDays: false,
        lengthChoices: const <int>[45],
      ),
    );
    expect(find.text("All day"), findsNothing);
    expect(find.text("Ends on another day"), findsNothing);
    expect(find.widgetWithText(ChoiceChip, "45m"), findsOneWidget);
    expect(find.byType(ChoiceChip), findsOneWidget);
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
