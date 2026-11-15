/// The item form's sheet, its summary card and its schedule section: the
/// sheet's container and type selector, the message of each schedule
/// problem, the messages after a failed Save, the summary's lines, overlap
/// notice, next free time and zone, and the section's All day switch, its
/// Start and End rows, End date, options and kept kind, and its time
/// fields, the pickers they open under their rows, what each picker
/// refuses, and where the focus goes.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/calendar/composition/calendar_card.dart'
    show CalendarCard;
import 'package:widgets_extended/calendar/views/day_cell.dart' show DayCell;
import 'package:widgets_extended/calendar/views/month_strip.dart'
    show MonthStrip;
import 'package:widgets_extended/calendar/views/time_picker.dart'
    show
        timePickerHourColumnKey,
        timePickerHourRowKey,
        timePickerMinuteRowKey,
        timePickerNowKey;
import 'package:widgets_extended/calendar/views/week_strip.dart'
    show WeekStrip, weekStripDayKey;
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

/// The summary's lines: its first, its second and, where it shows, its
/// length, joined by "\n".
String summary(WidgetTester tester) {
  return <String>[
    for (final key in <Key>[
      scheduleSummaryFirstLineKey,
      scheduleSummarySecondLineKey,
      scheduleSummaryLengthKey,
    ])
      if (find.byKey(key).evaluate().isNotEmpty)
        tester.widget<Text>(find.byKey(key)).data!,
  ].join("\n");
}

MemoryCalendarStore<ItemPayload> storeOf(List<CalendarItem> items) {
  return MemoryCalendarStore<ItemPayload>(entries: items);
}

/// The check of [schedule] under [policy] at [now] or else Wednesday's
/// start, in the calendar's whole day of 15-minute slots, for the stored
/// [entry] or a new one, with [options] or a Task's. The check reads its
/// times on the clock of [now]'s time.
CalendarScheduleCheck<ItemPayload> checkOf(
  CalendarSchedule schedule, {
  CalendarEditPolicy<ItemPayload> policy =
      const UnrestrictedEditPolicy<ItemPayload>(),
  CalendarItem? entry,
  CalendarScheduleOptions? options,
  CalendarNow? now,
}) {
  return CalendarScheduleCheck<ItemPayload>(
    schedule: schedule,
    rules: CalendarEditRules<ItemPayload>(
      policy: policy,
      hours: CalendarDayHours.allDay,
      slotMinutes: 15,
    ),
    now: now ?? wednesdayStart(),
    entry: entry,
    options: options ?? scheduleOptionsOf(CalendarItemType.task),
  );
}

/// Pumps the [ScheduleSummary] of [check] above its section, without the
/// form, in the calendar's whole day of 15-minute slots on the 24-hour
/// clock, on [zone]'s clock, the pickers' Now reading [now] or else
/// Wednesday's start, the edits of both going to [onChanged] or else
/// nowhere, and locked where [locked]. Where [follows], each edit also makes
/// their check that of the edited schedule
/// ([CalendarScheduleCheck.withSchedule]) before it goes to [onChanged], so
/// the next frame builds the summary and the section of the edit, as the
/// form's does; otherwise they keep [check]. Under [theme], where given,
/// they draw and move as that [CalendarTheme] says.
Future<void> pumpSection(
  WidgetTester tester,
  CalendarScheduleCheck<ItemPayload> check, {
  Location? zone,
  ValueGetter<CalendarNow>? now,
  ValueChanged<CalendarSchedule>? onChanged,
  bool locked = false,
  bool follows = false,
  CalendarThemeData? theme,
}) {
  Widget sectionOf(
    CalendarScheduleCheck<ItemPayload> check,
    ValueChanged<CalendarSchedule> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ScheduleSummary(
          check: check,
          hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
          zone: zone,
          locked: locked,
          onChanged: onChanged,
        ),
        ScheduleSection(
          check: check,
          hours: CalendarDayHours.allDay,
          slotMinutes: 15,
          hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
          now: now ?? wednesdayStart,
          zone: zone,
          locked: locked,
          onChanged: onChanged,
        ),
      ],
    );
  }

  final report = onChanged ?? (schedule) {};
  Widget home = Scaffold(
    body: SingleChildScrollView(
      child: follows
          ? _FollowingSection(
              check: check,
              onChanged: report,
              builder: sectionOf,
            )
          : sectionOf(check, report),
    ),
  );
  if (theme != null) {
    home = CalendarTheme(data: theme, child: home);
  }
  return tester.pumpWidget(MaterialApp(home: home));
}

/// The theme the motion tests give [pumpSection]: a motion of 480 ms on
/// [Curves.linear], so a panel half way through its motion is half open.
final CalendarThemeData motionTheme = CalendarThemeData.builtIn.copyWith(
  motionDuration: const Duration(milliseconds: 480),
  motionCurve: Curves.linear,
);

/// The panel under the row of the time field labelled [label], "Start
/// time" or "End time", that holds that field's picker.
Finder pickerPanel([String label = "Start time"]) {
  return find.byKey(
    label == "Start time" ? scheduleStartPanelKey : scheduleEndPanelKey,
  );
}

/// The height of the picker panel of the time field labelled [label].
double panelHeight(WidgetTester tester, [String label = "Start time"]) {
  return tester.getSize(pickerPanel(label)).height;
}

/// The height of the open picker panel of the time field labelled [label]
/// at rest: its picker's, which the panel lays out at full height while it
/// grows or shrinks, and the gap above it.
double settledPanelHeight(WidgetTester tester, [String label = "Start time"]) {
  return tester.getSize(timePickerFinder(label)).height + 12.0;
}

/// The opacity of the picker panel of the time field labelled [label], the
/// first [FadeTransition] under it.
double panelOpacity(WidgetTester tester, [String label = "Start time"]) {
  return tester
      .widget<FadeTransition>(
        find
            .descendant(
              of: pickerPanel(label),
              matching: find.byType(FadeTransition),
            )
            .first,
      )
      .opacity
      .value;
}

/// The vertical distance from the pill of the Hour column of the picker of
/// the time field labelled [label] to the centre of its row of [hour],
/// positive below the pill.
double hourRowFromPill(WidgetTester tester, String label, int hour) {
  final pill = tester
      .getCenter(inPicker(label, find.byKey(timePickerHourColumnKey)))
      .dy;
  return tester
          .getCenter(inPicker(label, find.byKey(timePickerHourRowKey(hour))))
          .dy -
      pill;
}

/// Runs [body], then returns the [CalendarTimePicker] elements rebuilt
/// during it.
Future<List<Element>> pickerRebuildsDuring(Future<void> Function() body) async {
  final rebuilt = <Element>[];
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    if (element.widget is CalendarTimePicker) {
      rebuilt.add(element);
    }
  };
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return rebuilt;
}

/// Makes the platform ask for no animations until the test ends.
void disableAnimations(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
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

  testWidgets("SF3 an edit shows no type selector but its type in the item "
      "card, and a read-only item its summary and Close alone", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(find.text("Edit Task"), findsOneWidget);
    expect(find.byType(SegmentedButton<CalendarItemType>), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(formItemCardKey),
        matching: find.text("Task"),
      ),
      findsOneWidget,
    );
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
    expect(summary(tester), "Wed, Apr 22\n09:00 - 10:00\n1h");
    expect(formButton("Close"), findsOneWidget);
    expect(formButton("Cancel"), findsNothing);
    expect(saveFinder(), findsNothing);
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

  testWidgets("SS1 SS2 the summary reads the schedule and its length, "
      "which a new end changes, and the section offers no length chips", (
    tester,
  ) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10, 30)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(summary(tester), "Wed, Apr 22\n09:00 - 10:30\n1h 30m");
    expect(find.byType(ChoiceChip), findsNothing);

    await pickTime(tester, "End time", "09:30");
    expect(summary(tester), "Wed, Apr 22\n09:00 - 09:30\n30m");
    await pickTime(tester, "End time", "10:00");
    expect(summary(tester), "Wed, Apr 22\n09:00 - 10:00\n1h");
  });

  testWidgets("SS3 End date names the item's last day, and a later day "
      "picked there makes a one-day item span days", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Trip", at(22), DateTime(2026, 4, 23, 2)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(formDateShows("End date", "2026-04-22"), findsOneWidget);
    await tester.tap(formDateFinder("End date"));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text("23"),
      ),
    );
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    expect(formDateShows("End date", "2026-04-23"), findsOneWidget);
    expect(summary(tester), "Wed, Apr 22, 09:00\nThu, Apr 23, 10:00\n25h");
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store, id: "item-2");
    expect(formDateShows("End date", "2026-04-23"), findsOneWidget);
    expect(summary(tester), "Wed, Apr 22, 22:00\nThu, Apr 23, 02:00\n4h");
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store);
    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(formDateShows("End date", "2026-04-22"), findsOneWidget);
    expect(timeFieldFinder("Start time"), findsNothing);
    expect(summary(tester), "Wed, Apr 22\nAll day");
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

  testWidgets("SS5 the summary names a store's zone by its city, and the "
      "device's zone where the store has none", (tester) async {
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
    expect(find.text("Havana"), findsOneWidget);
    expect(find.text("Device time zone"), findsNothing);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    final plain = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(plain.dispose);
    await openEdit(tester, plain);
    expect(find.text("Device time zone"), findsOneWidget);
  });

  testWidgets("SS6 options that refuse all-day and spanning days show no All "
      "day switch, and their End date takes no tap while the item ends on "
      "its start's day", (tester) async {
    bool endDateTakesTap() {
      return tester
              .widget<InkWell>(
                find
                    .ancestor(
                      of: formDateFinder("End date"),
                      matching: find.byType(InkWell),
                    )
                    .first,
              )
              .onTap !=
          null;
    }

    final schedule = CalendarSchedule.of(at(9), at(10), isAllDay: false);
    await pumpSection(tester, checkOf(schedule));
    expect(allDaySwitch(), findsOneWidget);
    // Setup sanity: under the standard options End date takes a tap.
    expect(endDateTakesTap(), isTrue);

    const options = CalendarScheduleOptions(
      allowsAllDay: false,
      spansDays: false,
    );
    await pumpSection(tester, checkOf(schedule, options: options));
    expect(allDaySwitch(), findsNothing);
    expect(find.text("All day"), findsNothing);
    expect(endDateTakesTap(), isFalse);

    // An item that spans days still takes its End date, which can bring it
    // back onto one day.
    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(at(22), DateTime(2026, 4, 23, 2), isAllDay: false),
        options: options,
      ),
    );
    expect(endDateTakesTap(), isTrue);
  });

  testWidgets("SS7 the All day switch turned on hides the times, and turned "
      "off restores them", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10, 30)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(allDaySwitch(), findsOneWidget);
    expect(formAllDayOn(), isFalse);

    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(summary(tester), "Wed, Apr 22\nAll day");
    expect(timeFieldFinder("Start time"), findsNothing);
    expect(formAllDayOn(), isTrue);

    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(summary(tester), "Wed, Apr 22\n09:00 - 10:30\n1h 30m");
    expect(timeFieldShows("Start time", "09:00"), findsOneWidget);
    expect(formAllDayOn(), isFalse);
  });

  testWidgets("SS8 an item in progress keeps its kind: the All day switch "
      "takes no tap, of an all-day item or a timed one", (tester) async {
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
    expect(formAllDayOn(), isTrue);
    expect(tester.widget<Switch>(allDaySwitch()).onChanged, isNull);

    final timed = task("item-2", "Write", DateTime(2026, 4, 21, 22), at(10));
    final timedCheck = checkOf(
      CalendarSchedule.of(timed.start, timed.end, isAllDay: false),
      policy: lock,
      entry: timed,
    );
    expect(timedCheck.startFixed, isTrue);
    await pumpSection(tester, timedCheck);
    expect(formAllDayOn(), isFalse);
    expect(tester.widget<Switch>(allDaySwitch()).onChanged, isNull);
  });

  testWidgets("SS9 an all-day item made timed starts at the first free hour "
      "of the store's hours on its start day: All day off gives that hour, "
      "of a stored item and of a new one", (tester) async {
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
    expect(summary(tester), "Wed, Apr 22\nAll day");
    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(summary(tester), "Wed, Apr 22\n09:30 - 10:30\n1h");
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
    expect(summary(tester), "Wed, Apr 22\nAll day");
    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(summary(tester), "Wed, Apr 22\n09:30 - 10:30\n1h");
  });

  testWidgets("TF1 a tap on Start time opens its picker in the panel under "
      "the Start row, a pick there settles into the schedule, a tap on End "
      "time closes it and opens the end's picker alone in the panel under "
      "the End row, and a second tap closes that; a fixed start's field "
      "opens none", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(find.byType(CalendarTimePicker), findsNothing);

    await tester.tap(timeFieldFinder("Start time"));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: pickerPanel(),
        matching: timePickerFinder("Start time"),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(timePickerFinder("Start time")).top,
      greaterThan(tester.getRect(timeFieldFinder("Start time")).bottom),
    );
    await tester.tap(
      inPicker("Start time", find.byKey(timePickerMinuteRowKey(30))),
    );
    await tester.pumpAndSettle();
    expect(summary(tester), "Wed, Apr 22\n09:30 - 10:30\n1h");

    await tester.ensureVisible(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: pickerPanel("End time"),
        matching: timePickerFinder("End time"),
      ),
      findsOneWidget,
    );
    expect(timePickerFinder("Start time"), findsNothing);
    expect(panelHeight(tester), 0.0);
    // The reveal of End's picker leaves its field where a tap misses it.
    await tester.ensureVisible(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarTimePicker), findsNothing);
    expect(panelHeight(tester, "End time"), 0.0);
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
    expect(find.byType(CalendarTimePicker), findsNothing);
  });

  testWidgets("TF2 the pickers offer the hours' times the check takes: the "
      "start's those from which the hours hold the item's length, its own "
      "time shown besides, the end's only the stored one where the start lies "
      "outside the hours, and of an end on its start's day past the hours' "
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
      for (var minute = 8 * 60; minute <= 16 * 60; minute += 15) minute,
    ]);
    // The start, 07:00, lies before the hours: shown, not offered.
    expect(hourRows("Start time"), contains(7));
    // A stored item keeps its times outside the hours; any other end with
    // its start, 07:00, is refused.
    await openTimePicker(tester, "End time");
    expect(offeredTimes(tester, "End time"), <int>[9 * 60]);
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
    // The check reads the times on the clock of its now's time.
    final inHavana = CalendarNow(
      time: tz.TZDateTime(havana, 2026, 3, 1, 9),
      today: tz.TZDateTime(havana, 2026, 3, 1),
    );
    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(
          DateTime(2026, 3, 8, 1),
          DateTime(2026, 3, 8, 2),
          isAllDay: false,
        ),
        now: inHavana,
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
        now: inHavana,
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
        now: inHavana,
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
    expect(summary(tester), "Wed, Apr 22\n11:00 - 12:00\n1h");
    await openTimePicker(tester, "Start time");
    await tester.tap(inPicker("Start time", find.byKey(timePickerNowKey)));
    await tester.pumpAndSettle();
    // The nearest slot would be 09:15.
    expect(summary(tester), "Wed, Apr 22\n09:00 - 10:00\n1h");
  });

  testWidgets("TF5 the start's picker stays open across Next free time and a "
      "new start date, and the All day switch closes it and takes the "
      "focus", (tester) async {
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
    expect(summary(tester), "Wed, Apr 22\n10:30 - 11:30\n1h");
    expect(timePickerFinder("Start time"), findsOneWidget);

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
    expect(summary(tester), "Thu, Apr 23\n10:30 - 11:30\n1h");
    expect(timePickerFinder("Start time"), findsOneWidget);

    await tester.ensureVisible(allDaySwitch());
    await tester.pumpAndSettle();
    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(summary(tester), "Thu, Apr 23\nAll day");
    expect(timePickerFinder("Start time"), findsNothing);
    expect(focusUnder(allDaySwitch()), isTrue);
  });

  testWidgets("TF8 the focus follows the open picker: its Hour column takes "
      "it as the picker opens, the other picker's as a tap on the other "
      "field opens that one, and the field takes it as its picker closes", (
    tester,
  ) async {
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

    await tester.ensureVisible(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(
      focusUnder(inPicker("End time", find.byKey(timePickerHourColumnKey))),
      isTrue,
    );

    await tester.ensureVisible(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(timePickerFinder("End time"), findsNothing);
    expect(focusUnder(timeFieldFinder("End time")), isTrue);
  });

  testWidgets("TF9 a picker opened past the bottom of the view scrolls into "
      "it once its panel has opened", (tester) async {
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
    await tester.pumpAndSettle();
    // Setup sanity: the picker opened past the view's bottom, so the view
    // scrolled to reveal it.
    expect(position.pixels, greaterThan(0.0));
    final picker = tester.getRect(timePickerFinder("Start time"));
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

  testWidgets("TF13 a spin of the start's picker cut off by a tap on End "
      "time, moving or held, picks nothing: the end's picker shows, and both "
      "fields keep their times, also where they share a minute", (
    tester,
  ) async {
    final oneDay = task("item-1", "Write", at(9), at(10));
    // Tue 09:00 to Wed 09:00: Start time and End time both read 09:00.
    final twoDays = task("item-1", "Write", DateTime(2026, 4, 21, 9), at(9));
    final hourColumn = inPicker(
      "Start time",
      find.byKey(timePickerHourColumnKey),
    );

    Future<void> openStart(CalendarItem item) async {
      final store = storeOf(<CalendarItem>[item]);
      addTearDown(store.dispose);
      await openEdit(tester, store);
      await openTimePicker(tester, "Start time");
    }

    // Holds Start's Hour column still with its row of 11 on the pill, where
    // a release picks 11:00, neither field's time.
    Future<TestGesture> holdOnEleven() async {
      final hold = await tester.startGesture(tester.getCenter(hourColumn));
      await hold.moveBy(const Offset(0.0, -20.0));
      await tester.pump(const Duration(milliseconds: 50));
      await hold.moveBy(const Offset(0.0, 20.0));
      await tester.pump(const Duration(milliseconds: 50));
      var left = -hourRowFromPill(tester, "Start time", 11);
      while (left.abs() > 0.0) {
        final step = left.abs() > 8.0 ? 8.0 * left.sign : left;
        await hold.moveBy(Offset(0.0, step));
        await tester.pump(const Duration(milliseconds: 50));
        left -= step;
      }
      await tester.pump(const Duration(milliseconds: 200));
      return hold;
    }

    // Opens [item]'s Start time, spins its Hour column, a fling still
    // moving or a hold resting on 11, cuts the spin off with a tap on End
    // time, releases a held column and lets the form settle.
    Future<void> cutOffSpin(CalendarItem item, {required bool held}) async {
      await openStart(item);
      TestGesture? hold;
      if (held) {
        hold = await holdOnEleven();
        // Setup sanity: the held column rests on 11 and has picked nothing.
        expect(hourRowFromPill(tester, "Start time", 11).abs(), lessThan(0.5));
      } else {
        await tester.fling(hourColumn, const Offset(0.0, -120.0), 1000.0);
        await tester.pump();
        await tester.pump();
        // Setup sanity: the motion still runs, its pick not yet reported.
        expect(
          hourRowFromPill(tester, "Start time", 9).abs(),
          greaterThan(0.5),
        );
      }
      expect(timeFieldShows("Start time", "09:00"), findsOneWidget);
      await tester.tap(timeFieldFinder("End time"));
      await tester.pump();
      await hold?.up();
      await tester.pumpAndSettle();
    }

    // Expects Start 09:00, End [end] and the end's picker alone, then
    // cancels the form.
    Future<void> expectDropped(String end) async {
      expect(timeFieldShows("Start time", "09:00"), findsOneWidget);
      expect(timeFieldShows("End time", end), findsOneWidget);
      expect(timePickerFinder("End time"), findsOneWidget);
      expect(timePickerFinder("Start time"), findsNothing);
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
    }

    // Setup sanity: left to settle, the fling lands on neither field's
    // time, so a spin reported to either would change it.
    await openStart(oneDay);
    await tester.fling(hourColumn, const Offset(0.0, -120.0), 1000.0);
    await tester.pumpAndSettle();
    expect(timeFieldShows("Start time", "09:00"), findsNothing);
    expect(timeFieldShows("Start time", "10:00"), findsNothing);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await cutOffSpin(oneDay, held: false);
    await expectDropped("10:00");
    await cutOffSpin(oneDay, held: true);
    await expectDropped("10:00");
    await cutOffSpin(twoDays, held: false);
    await expectDropped("09:00");
    await cutOffSpin(twoDays, held: true);
    await expectDropped("09:00");
  });

  testWidgets("TF14 a stored item's start picker offers every start its "
      "policy admits a change to, and a new entry's refuses each start "
      "before the first the check allows, its own included, which still "
      "shows selected", (tester) async {
    final item = task("item-1", "Write", at(9), at(10));
    final schedule = CalendarSchedule.of(item.start, item.end, isAllDay: false);
    final stored = checkOf(
      schedule,
      policy: const _StartsFromTen(),
      entry: item,
    );
    // Setup sanity: the check's first start lies after the item's start.
    expect(stored.firstStartMinute, 10 * 60);
    await pumpSection(tester, stored);
    await openTimePicker(tester, "Start time");
    // The policy keeps the default admitsChange, which takes every change
    // of a stored item.
    expect(offeredTimes(tester, "Start time"), <int>[
      for (var minute = 0; minute <= 23 * 60 + 45; minute += 15) minute,
    ]);

    await pumpSection(
      tester,
      checkOf(schedule, policy: const _StartsFromTen()),
    );
    await tester.pumpAndSettle();
    expect(offeredTimes(tester, "Start time"), <int>[
      for (var minute = 10 * 60; minute <= 23 * 60 + 45; minute += 15) minute,
    ]);
    // The start, 09:00, still shows, refused.
    expect(rowTakesTap(tester, "Start time", timePickerHourRowKey(9)), isFalse);
  });

  testWidgets("TF15 the start's and the end's pickers play haptic "
      "feedback", (tester) async {
    final schedule = CalendarSchedule.of(at(9), at(10), isAllDay: false);
    await pumpSection(tester, checkOf(schedule));
    for (final label in <String>["Start time", "End time"]) {
      await openTimePicker(tester, label);
      expect(
        tester
            .widget<CalendarTimePicker>(timePickerFinder(label))
            .hapticFeedback,
        isTrue,
        reason: label,
      );
    }
  });

  testWidgets("FA1 after a failed Save the title's and the times' messages "
      "follow the edits: none before Save, a start picked in the hours "
      "clears the end's hours message, and a title clears its own", (
    tester,
  ) async {
    final store = MemoryCalendarStore<ItemPayload>(
      hours: CalendarDayHours(8 * 60, 18 * 60),
    );
    addTearDown(store.dispose);
    await openCreate(
      tester,
      store,
      CalendarCreateRange(start: at(17, 30), end: at(18, 30)),
    );
    const endMessage =
        "The end is from after 08:00 to 18:00, inside the calendar's hours.";
    expect(find.text("Enter a title."), findsNothing);
    expect(find.text(endMessage), findsNothing);

    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    expect(find.text("Enter a title."), findsOneWidget);
    expect(
      find.descendant(
        of: timeFieldFinder("End time"),
        matching: find.text(endMessage),
      ),
      findsOneWidget,
    );

    await pickTime(tester, "Start time", "09:00");
    expect(find.text(endMessage), findsNothing);
    await tester.enterText(fieldFinder("Title"), "Plan");
    await tester.pump();
    expect(find.text("Enter a title."), findsNothing);
  });

  testWidgets("FA3 a type change keeps the title's message, and the start "
      "message of a store's refusal stays through a title or an end edit "
      "until the start changes", (tester) async {
    final empty = storeOf(<CalendarItem>[]);
    addTearDown(empty.dispose);
    await openCreate(
      tester,
      empty,
      CalendarCreateRange(start: at(9), end: at(10)),
    );
    await tester.tap(find.text("Risk").last);
    await tester.pumpAndSettle();
    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    expect(find.text("Enter a title."), findsOneWidget);
    await tester.tap(find.text("Task").last);
    await tester.pumpAndSettle();
    expect(find.text("Enter a title."), findsOneWidget);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    await pickTime(tester, "Start time", "09:15");
    store.hours = CalendarDayHours(10 * 60, 18 * 60);
    await tester.pump();
    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    const startMessage =
        "The start is from 10:00 to before 18:00, inside the calendar's "
        "hours.";
    final onStart = find.descendant(
      of: timeFieldFinder("Start time"),
      matching: find.text(startMessage),
    );
    expect(onStart, findsOneWidget);
    await tester.enterText(fieldFinder("Title"), "Write more");
    await tester.pumpAndSettle();
    expect(onStart, findsOneWidget);
    await pickTime(tester, "End time", "11:00");
    expect(onStart, findsOneWidget);
    await pickTime(tester, "Start time", "10:00");
    expect(find.text(startMessage), findsNothing);
  });

  testWidgets("FA2 a type field's message shows from one Save to the next, "
      "whatever is typed meanwhile", (tester) async {
    final store = storeOf(<CalendarItem>[]);
    addTearDown(store.dispose);
    await openCreate(
      tester,
      store,
      CalendarCreateRange(start: at(9), end: at(10)),
    );
    await tester.tap(find.text("Risk").last);
    await tester.pumpAndSettle();
    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    expect(find.text("Project is required."), findsOneWidget);
    await tester.enterText(fieldFinder("Project"), "Apollo");
    await tester.pump();
    expect(find.text("Project is required."), findsOneWidget);

    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    // Setup sanity: the Save is refused for the title alone.
    expect(find.text("Enter a title."), findsOneWidget);
    expect(find.text("Project is required."), findsNothing);
  });

  testWidgets("FA4 a Save after a failed one shows no message of the item it "
      "writes while the sheet closes", (tester) async {
    final store = storeOf(<CalendarItem>[]);
    addTearDown(store.dispose);
    await openWith(tester, (context) {
      showCreateFlow(
        context,
        store: store,
        range: CalendarCreateRange(start: at(9), end: at(10)),
        policy: const NoOverlapsPolicy<ItemPayload>(),
        now: wednesdayStart,
        hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
      );
    });
    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    expect(find.text("Enter a title."), findsOneWidget);

    await tester.enterText(fieldFinder("Title"), "Plan");
    await tester.tap(saveFinder());
    var frame = 0;
    do {
      await tester.pump(const Duration(milliseconds: 16));
      frame++;
      expect(find.byKey(scheduleOverlapKey), findsNothing, reason: "$frame");
      expect(
        find.textContaining("Overlaps Plan"),
        findsNothing,
        reason: "$frame",
      );
      expect(frame, lessThan(200));
    } while (find.text("New item").evaluate().isNotEmpty);
    // Setup sanity: the second Save wrote the item.
    expect(
      store.entriesOn(wednesday).map((shown) {
        return shown.entry.title;
      }),
      <String>["Plan"],
    );
  });

  testWidgets("FB1 the start's picker refuses a start whose range would end "
      "past the hours", (tester) async {
    final store = MemoryCalendarStore<ItemPayload>(
      hours: CalendarDayHours(8 * 60, 18 * 60),
      entries: <CalendarItem>[task("item-1", "Write", at(17), at(18))],
    );
    addTearDown(store.dispose);
    await openEdit(tester, store);
    await openTimePicker(tester, "Start time");
    expect(offeredTimes(tester, "Start time"), <int>[
      for (var minute = 8 * 60; minute <= 17 * 60; minute += 15) minute,
    ]);
    expect(
      rowTakesTap(tester, "Start time", timePickerMinuteRowKey(30)),
      isFalse,
    );
    await tester.tap(
      inPicker("Start time", find.byKey(timePickerMinuteRowKey(30))),
    );
    await tester.pumpAndSettle();
    expect(timeFieldShows("Start time", "17:00"), findsOneWidget);
  });

  testWidgets("FB2 under a policy that refuses overlaps the end's picker "
      "refuses an end that overlaps another item and takes one that touches "
      "it", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Standup", at(11), at(12)),
    ]);
    addTearDown(store.dispose);
    await openWith(tester, (context) {
      showEditForm(
        context,
        store: store,
        id: "item-1",
        policy: const NoOverlapsPolicy<ItemPayload>(),
        now: wednesdayStart,
        hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
      );
    });
    await openTimePicker(tester, "End time");
    expect(timeEnabled(tester, "End time", "11:00"), isTrue);
    expect(timeEnabled(tester, "End time", "11:15"), isFalse);
    expect(timeEnabled(tester, "End time", "12:30"), isFalse);
  });

  testWidgets("FN1 Now picks the first start offered after now where the "
      "time before it is refused: under the lock of earlier today, with "
      "today pinned to another day than now's time, and before the hours; "
      "and as the clock's minute turns with the picker open, the picker "
      "refuses a start the lock has passed, and Now picks one Save "
      "takes", (tester) async {
    Future<void> openAt(
      CalendarStore<ItemPayload> store,
      CalendarEditPolicy<ItemPayload> policy,
      CalendarNow now,
    ) {
      return openWith(tester, (context) {
        showEditForm(
          context,
          store: store,
          id: "item-1",
          policy: policy,
          now: () {
            return now;
          },
          hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
        );
      });
    }

    Future<void> tapNow() async {
      await openTimePicker(tester, "Start time");
      final now = inPicker("Start time", find.byKey(timePickerNowKey));
      await tester.ensureVisible(now);
      await tester.pumpAndSettle();
      await tester.tap(now);
      await tester.pumpAndSettle();
    }

    const lock = HistoryLockPolicy<ItemPayload>(lockEarlierToday: true);
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(10), at(11)),
    ]);
    addTearDown(store.dispose);
    await openAt(store, lock, CalendarNow(time: at(9, 7), today: wednesday));
    await tapNow();
    expect(timeFieldShows("Start time", "09:15"), findsOneWidget);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    // The app pins today, so the clock's date can differ from it.
    await openAt(
      store,
      lock,
      CalendarNow(time: DateTime(2026, 4, 23, 9, 7), today: wednesday),
    );
    await tapNow();
    expect(timeFieldShows("Start time", "09:15"), findsOneWidget);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    final office = MemoryCalendarStore<ItemPayload>(
      hours: CalendarDayHours(8 * 60, 18 * 60),
      entries: <CalendarItem>[task("item-1", "Write", at(10), at(11))],
    );
    addTearDown(office.dispose);
    await openAt(
      office,
      const UnrestrictedEditPolicy<ItemPayload>(),
      CalendarNow(time: at(7, 30), today: wednesday),
    );
    await tapNow();
    expect(timeFieldShows("Start time", "08:00"), findsOneWidget);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    var clock = at(9, 7);
    await openWith(tester, (context) {
      showEditForm(
        context,
        store: store,
        id: "item-1",
        policy: lock,
        now: () {
          return CalendarNow(time: clock, today: wednesday);
        },
        hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
      );
    });
    await openTimePicker(tester, "Start time");
    // Setup sanity: at 09:07 the lock takes 09:15.
    expect(timeEnabled(tester, "Start time", "09:15"), isTrue);
    clock = at(9, 16);
    await tester.pump(const Duration(minutes: 1));
    expect(timeEnabled(tester, "Start time", "09:15"), isFalse);
    await tapNow();
    expect(timeFieldShows("Start time", "09:30"), findsOneWidget);
    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    expect(store.storedEntry("item-1")!.start, at(9, 30));
  });

  testWidgets("FD1 Now shows only in the picker of a field whose day is "
      "today", (tester) async {
    final store = storeOf(<CalendarItem>[
      task(
        "item-1",
        "Write",
        DateTime(2026, 4, 23, 9),
        DateTime(2026, 4, 23, 10),
      ),
      task("item-2", "Trip", DateTime(2026, 4, 21, 22), at(2)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    await openTimePicker(tester, "Start time");
    expect(inPicker("Start time", find.byKey(timePickerNowKey)), findsNothing);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store, id: "item-2");
    await openTimePicker(tester, "End time");
    expect(inPicker("End time", find.byKey(timePickerNowKey)), findsOneWidget);
    await openTimePicker(tester, "Start time");
    expect(inPicker("Start time", find.byKey(timePickerNowKey)), findsNothing);
  });

  testWidgets("FB3 a picker refuses no time for a problem every checked time "
      "of it shares, and takes as witnesses only the times whose check "
      "reads both times", (tester) async {
    const lock = HistoryLockPolicy<ItemPayload>(lockEarlierToday: true);
    final store = storeOf(<CalendarItem>[]);
    addTearDown(store.dispose);
    await openWith(tester, (context) {
      showCreateFlow(
        context,
        store: store,
        range: CalendarCreateRange(start: at(9), end: at(10)),
        policy: lock,
        now: () {
          return CalendarNow(time: at(10, 20), today: wednesday);
        },
        hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
      );
    });
    await openTimePicker(tester, "Start time");
    // Setup sanity: the start lies before now, which the lock refuses.
    expect(timeEnabled(tester, "Start time", "09:00"), isFalse);
    // Every end keeps that start, so no end avoids its problem.
    await openTimePicker(tester, "End time");
    expect(offeredTimes(tester, "End time"), <int>[
      for (var minute = 9 * 60 + 15; minute <= 24 * 60; minute += 15) minute,
    ]);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    final havana = tz.getLocation("America/Havana");
    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(
          DateTime(2026, 3, 7, 22),
          DateTime(2026, 3, 8, 2),
          isAllDay: false,
        ),
        policy: lock,
        now: CalendarNow(
          time: tz.TZDateTime(havana, 2026, 3, 7, 23),
          today: tz.TZDateTime(havana, 2026, 3, 7),
        ),
      ),
      zone: havana,
    );
    await openTimePicker(tester, "End time");
    // Havana's clock skips 00:00 to 01:00 on 2026-03-08: an end there is
    // refused, though its check stops before the lock's problem.
    for (final time in <String>["00:15", "00:30", "00:45"]) {
      expect(timeEnabled(tester, "End time", time), isFalse, reason: time);
    }
    for (final time in <String>["01:00", "02:00"]) {
      expect(timeEnabled(tester, "End time", time), isTrue, reason: time);
    }
  });

  testWidgets("FK1 typing in the form's text fields after a failed Save "
      "checks the schedule nowhere and asks the open picker nothing", (
    tester,
  ) async {
    final store = storeOf(<CalendarItem>[]);
    addTearDown(store.dispose);
    final asked = <DateTime>[];
    await openWith(tester, (context) {
      showCreateFlow(
        context,
        store: store,
        range: CalendarCreateRange(start: at(9), end: at(10)),
        policy: _CountingPolicy(asked),
        now: wednesdayStart,
        hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
      );
    });
    await openTimePicker(tester, "Start time");
    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    // Setup sanity: the Save failed.
    expect(find.text("Enter a title."), findsOneWidget);
    final checks = asked.length;
    final asks = debugSchedulePickerAsks;
    for (final (label, text) in <(String, String)>[
      ("Title", "P"),
      ("Title", "Pl"),
      ("Assignee", "Sam"),
    ]) {
      await tester.enterText(fieldFinder(label), text);
      await tester.pump();
    }
    expect(asked, hasLength(checks));
    expect(debugSchedulePickerAsks, asks);

    // Setup sanity: a pick checks the schedule again.
    final row = inPicker("Start time", find.byKey(timePickerMinuteRowKey(30)));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(asked.length, greaterThan(checks));
  });

  testWidgets("FW1 All day is a switch, no chip, above Start date: turned "
      "on it closes an open picker and takes the focus, turned off it "
      "restores the times; it takes no tap for a kept kind, and shows where "
      "the kind takes all-day or the schedule is all-day", (tester) async {
    final schedule = CalendarSchedule.of(at(9), at(10), isAllDay: false);
    await pumpSection(tester, checkOf(schedule), follows: true);
    expect(
      find.descendant(
        of: find.byType(ScheduleSection),
        matching: find.byType(ChoiceChip),
      ),
      findsNothing,
    );
    expect(
      tester.getRect(allDaySwitch()).bottom,
      lessThanOrEqualTo(tester.getRect(formDateFinder("Start date")).top),
    );

    await openTimePicker(tester, "Start time");
    // Setup sanity: Start's picker is open.
    expect(timePickerFinder("Start time"), findsOneWidget);
    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(timeFieldFinder("Start time"), findsNothing);
    expect(timeFieldFinder("End time"), findsNothing);
    expect(find.byType(CalendarTimePicker), findsNothing);
    expect(focusUnder(allDaySwitch()), isTrue);
    expect(pickerPanel(), findsNothing);
    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(timeFieldShows("Start time", "09:00"), findsOneWidget);
    expect(timeFieldShows("End time", "10:00"), findsOneWidget);

    // TF1's running item under the lock keeps its kind.
    final running = task("item-2", "Write", DateTime(2026, 4, 21, 22), at(10));
    final fixed = checkOf(
      CalendarSchedule.of(running.start, running.end, isAllDay: false),
      policy: const HistoryLockPolicy<ItemPayload>(),
      entry: running,
    );
    expect(fixed.startFixed, isTrue);
    final reports = <CalendarSchedule>[];
    await pumpSection(tester, fixed, onChanged: reports.add, follows: true);
    expect(tester.widget<Switch>(allDaySwitch()).onChanged, isNull);
    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(reports, isEmpty);

    const noAllDay = CalendarScheduleOptions(allowsAllDay: false);
    await pumpSection(
      tester,
      checkOf(schedule, options: noAllDay),
      follows: true,
    );
    expect(allDaySwitch(), findsNothing);
    await pumpSection(
      tester,
      checkOf(schedule.withAllDay(true), options: noAllDay),
      follows: true,
    );
    expect(allDaySwitch(), findsOneWidget);

    // Turned on while the panel still grows, the switch takes the panel
    // out of the tree with its motion running.
    await pumpSection(
      tester,
      checkOf(schedule),
      follows: true,
      theme: motionTheme,
    );
    await tester.tap(timeFieldFinder("Start time"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // Setup sanity: the panel is growing.
    expect(panelHeight(tester), greaterThan(0.0));
    expect(panelHeight(tester), lessThan(settledPanelHeight(tester)));
    await tester.tap(allDaySwitch());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(pickerPanel(), findsNothing);
    for (var elapsed = 16; elapsed <= 480; elapsed += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull, reason: "at $elapsed ms");
      expect(pickerPanel(), findsNothing, reason: "at $elapsed ms");
    }

    // In the form, the switch lies in the scheduling card.
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    final card = tester.getRect(find.byKey(formSchedulingCardKey));
    expect(card.expandToInclude(tester.getRect(allDaySwitch())), card);
  });

  testWidgets("FW2 the All day switch is three quarters of a padded "
      "Switch's size, and a tap on its label leaves it", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: Switch(
              value: false,
              onChanged: (on) {},
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
          ),
        ),
      ),
    );
    final full = tester.getRect(find.byType(Switch)).size;
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    final shown = find.descendant(
      of: allDaySwitch(),
      matching: find.byType(Switch),
      matchRoot: true,
    );
    expect(tester.getRect(shown).size, full * 0.75);

    await tester.tap(find.text("All day"));
    await tester.pumpAndSettle();
    expect(formAllDayOn(), isFalse);
    // Setup sanity: the switch takes a tap.
    await tester.tap(shown);
    await tester.pumpAndSettle();
    expect(formAllDayOn(), isTrue);
  });

  testWidgets("FW3 what the scheduling card's controls show lies 16 pixels "
      "from its edges: All day's label and switch track at the top and "
      "side, and at the bottom the End row's fields, or an all-day item's "
      "End date", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task(
        "item-2",
        "Off",
        DateTime(2026, 4, 24),
        DateTime(2026, 4, 25),
        isAllDay: true,
      ),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    var card = tester.getRect(find.byKey(formSchedulingCardKey));
    expect(tester.getRect(find.text("All day")).top, card.top + 16.0);
    // A padded Switch pads its track 4 pixels at each side
    // (SwitchThemeData.padding), 3 at three quarters of its size.
    expect(tester.getRect(allDaySwitch()).right - 3.0, card.right - 16.0);
    expect(
      math.max(
        tester.getRect(formDateFinder("End date")).bottom,
        tester.getRect(timeFieldFinder("End time")).bottom,
      ),
      card.bottom - 16.0,
    );
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store, id: "item-2");
    // Setup sanity: the item is all-day.
    expect(formAllDayOn(), isTrue);
    card = tester.getRect(find.byKey(formSchedulingCardKey));
    expect(
      tester.getRect(formDateFinder("End date")).bottom,
      card.bottom - 16.0,
    );
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    // Without All day, Start date's field lies at the top.
    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(at(9), at(10), isAllDay: false),
        options: const CalendarScheduleOptions(allowsAllDay: false),
      ),
    );
    // Setup sanity: All day does not show.
    expect(allDaySwitch(), findsNothing);
    expect(
      tester.getRect(formDateFinder("Start date")).top,
      tester.getRect(find.byType(ScheduleSection)).top + 16.0,
    );
  });

  testWidgets("FR1 the scheduling card shows a Start row, Start date then "
      "Start time, above an End row, End date then End time, each date "
      "three fifths of its row and 12 pixels from its time, and no Ends on "
      "another day: a one-day item's End date names its start's day", (
    tester,
  ) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(formDateShows("End date", "2026-04-22"), findsOneWidget);
    expect(find.text("Ends on another day"), findsNothing);
    final card = tester.getRect(find.byKey(formSchedulingCardKey));
    final dates = <Rect>[
      tester.getRect(formDateFinder("Start date")),
      tester.getRect(formDateFinder("End date")),
    ];
    final times = <Rect>[
      tester.getRect(timeFieldFinder("Start time")),
      tester.getRect(timeFieldFinder("End time")),
    ];
    for (var row = 0; row < 2; row++) {
      final date = dates[row];
      final time = times[row];
      expect(date.top, time.top, reason: "row $row");
      expect(date.left, card.left + 16.0, reason: "row $row");
      expect(time.right, card.right - 16.0, reason: "row $row");
      expect(time.left - date.right, 12.0, reason: "row $row");
      expect(
        date.width / (date.width + time.width),
        moreOrLessEquals(0.6),
        reason: "row $row",
      );
    }
    expect(dates[0].bottom, lessThanOrEqualTo(dates[1].top));
  });

  testWidgets("FR2 an all-day item's Start date and End date each take a "
      "row of their own across the card", (tester) async {
    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(wednesday, DateTime(2026, 4, 24), isAllDay: true),
      ),
    );
    final section = tester.getRect(find.byType(ScheduleSection));
    final start = tester.getRect(formDateFinder("Start date"));
    final end = tester.getRect(formDateFinder("End date"));
    for (final date in <Rect>[start, end]) {
      expect(date.left, section.left + 16.0);
      expect(date.right, section.right - 16.0);
    }
    expect(start.bottom, lessThanOrEqualTo(end.top));
  });

  testWidgets("FR3 Start time's picker opens in a panel between the Start "
      "row and the End row, and End time's in a panel under the End row", (
    tester,
  ) async {
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(10), isAllDay: false)),
    );
    await openTimePicker(tester, "Start time");
    final start = tester.getRect(timePickerFinder("Start time"));
    expect(
      start.top,
      greaterThan(tester.getRect(timeFieldFinder("Start time")).bottom),
    );
    expect(
      start.bottom,
      lessThan(tester.getRect(timeFieldFinder("End time")).top),
    );
    expect(
      find.descendant(
        of: pickerPanel("Start time"),
        matching: timePickerFinder("Start time"),
      ),
      findsOneWidget,
    );
    await closeTimePicker(tester, "Start time");

    await openTimePicker(tester, "End time");
    final end = tester.getRect(timePickerFinder("End time"));
    expect(
      end.top,
      greaterThan(tester.getRect(timeFieldFinder("End time")).bottom),
    );
    expect(
      find.descendant(
        of: pickerPanel("End time"),
        matching: timePickerFinder("End time"),
      ),
      findsOneWidget,
    );
  });

  testWidgets("FR4 a tap on End time while Start's picker is open shrinks "
      "Start's panel while End's grows, over the theme's motion, Start's "
      "picker fading out over the motion's last half as End's fades in over "
      "its first, the closing picker taking no pick; then End's picker "
      "alone shows, its Hour column holding the focus", (tester) async {
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(12), isAllDay: false)),
      theme: motionTheme,
    );
    await openTimePicker(tester, "Start time");
    final startFull = settledPanelHeight(tester, "Start time");
    // Setup sanity: Start's panel is open at rest.
    expect(panelHeight(tester, "Start time"), startFull);
    await tester.ensureVisible(timeFieldFinder("End time"));
    await tester.pumpAndSettle();

    await tester.tap(timeFieldFinder("End time"));
    await tester.pump();
    // 120 ms after the tap's own frame, a quarter of the theme's linear
    // 480 ms.
    await tester.pump(const Duration(milliseconds: 120));
    final endFull = settledPanelHeight(tester, "End time");
    expect(
      panelHeight(tester, "Start time"),
      moreOrLessEquals(startFull * 3 / 4, epsilon: 1.0),
    );
    expect(panelOpacity(tester, "Start time"), 1.0);
    expect(
      panelHeight(tester, "End time"),
      moreOrLessEquals(endFull / 4, epsilon: 1.0),
    );
    expect(
      panelOpacity(tester, "End time"),
      moreOrLessEquals(0.5, epsilon: 0.01),
    );
    expect(
      tester
          .widget<CalendarTimePicker>(timePickerFinder("Start time"))
          .onChanged,
      isNull,
    );
    // Three quarters of the motion.
    await tester.pump(const Duration(milliseconds: 240));
    expect(
      panelHeight(tester, "Start time"),
      moreOrLessEquals(startFull / 4, epsilon: 1.0),
    );
    expect(
      panelOpacity(tester, "Start time"),
      moreOrLessEquals(0.5, epsilon: 0.01),
    );
    expect(
      panelHeight(tester, "End time"),
      moreOrLessEquals(endFull * 3 / 4, epsilon: 1.0),
    );
    expect(panelOpacity(tester, "End time"), 1.0);

    await tester.pumpAndSettle();
    expect(timePickerFinder("Start time"), findsNothing);
    expect(panelHeight(tester, "Start time"), 0.0);
    expect(
      panelHeight(tester, "End time"),
      settledPanelHeight(tester, "End time"),
    );
    expect(
      focusUnder(inPicker("End time", find.byKey(timePickerHourColumnKey))),
      isTrue,
    );
  });

  testWidgets("FR5 where the platform asks for no animations a tap on End "
      "time while Start's picker is open closes Start's panel and opens "
      "End's at full height in the tap's own frame", (tester) async {
    disableAnimations(tester);
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(12), isAllDay: false)),
      theme: motionTheme,
    );
    await openTimePicker(tester, "Start time");
    await tester.ensureVisible(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    await tester.tap(timeFieldFinder("End time"));
    await tester.pump();
    expect(timePickerFinder("Start time"), findsNothing);
    expect(panelHeight(tester, "Start time"), 0.0);
    expect(
      panelHeight(tester, "End time"),
      settledPanelHeight(tester, "End time"),
    );
  });

  testWidgets("FR6 after a failed Save, the end's message of a timed item "
      "that spans days shows on End time, not on End date", (tester) async {
    final store = MemoryCalendarStore<ItemPayload>(
      hours: CalendarDayHours(8 * 60, 18 * 60),
    );
    addTearDown(store.dispose);
    await openCreate(
      tester,
      store,
      CalendarCreateRange(start: at(17), end: DateTime(2026, 4, 23, 19)),
    );
    const endMessage =
        "The end is from after 08:00 to 18:00, inside the calendar's hours.";
    // Setup sanity: the item spans days.
    expect(formDateShows("End date", "2026-04-23"), findsOneWidget);
    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: timeFieldFinder("End time"),
        matching: find.text(endMessage),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: formDateFinder("End date"),
        matching: find.text(endMessage),
      ),
      findsNothing,
    );
  });

  testWidgets("FR7 a tap on End time while Start's picker is open, with the "
      "End row at the top of the form's view, brings End's field back into "
      "view once End's panel has opened, as Start's panel above it closed", (
    tester,
  ) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    await openTimePicker(tester, "Start time");
    final page = tester.getRect(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(timeFieldFinder("End time")));
    await tester.pumpAndSettle();
    // Setup sanity: End's field lies at the top of the view, below Start's
    // open panel.
    expect(tester.getRect(timeFieldFinder("End time")).top, page.top);
    expect(timePickerFinder("Start time"), findsOneWidget);

    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(timeFieldFinder("End time")).top,
      greaterThanOrEqualTo(page.top),
    );
  });

  testWidgets("FP1 the panel grows over the theme's motion as Start time "
      "opens it, its picker fading in over the motion's first half, and "
      "shrinks over it as the field closes it, the picker fading out over "
      "the motion's last half, the picker neither rebuilt nor asked in "
      "between", (tester) async {
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(10), isAllDay: false)),
      theme: motionTheme,
    );
    await tester.tap(timeFieldFinder("Start time"));
    await tester.pump();
    var full = 0.0;
    var asks = debugSchedulePickerAsks;
    final opening = await pickerRebuildsDuring(() async {
      // 120 ms after the tap's own frame, a quarter of the theme's linear
      // 480 ms.
      await tester.pump(const Duration(milliseconds: 120));
      full = settledPanelHeight(tester);
      expect(panelHeight(tester), moreOrLessEquals(full / 4, epsilon: 1.0));
      expect(panelOpacity(tester), moreOrLessEquals(0.5, epsilon: 0.01));
      // Half the motion.
      await tester.pump(const Duration(milliseconds: 120));
      expect(panelHeight(tester), moreOrLessEquals(full / 2, epsilon: 1.0));
      expect(panelOpacity(tester), 1.0);
      await tester.pump(const Duration(milliseconds: 240));
      expect(panelHeight(tester), full);
      expect(panelOpacity(tester), 1.0);
    });
    expect(opening, isEmpty);
    expect(debugSchedulePickerAsks, asks);

    await tester.tap(timeFieldFinder("Start time"));
    await tester.pump();
    asks = debugSchedulePickerAsks;
    final closing = await pickerRebuildsDuring(() async {
      // Half the motion.
      await tester.pump(const Duration(milliseconds: 240));
      expect(panelHeight(tester), moreOrLessEquals(full / 2, epsilon: 1.0));
      expect(panelOpacity(tester), 1.0);
      // Three quarters of the motion.
      await tester.pump(const Duration(milliseconds: 120));
      expect(panelHeight(tester), moreOrLessEquals(full / 4, epsilon: 1.0));
      expect(panelOpacity(tester), moreOrLessEquals(0.5, epsilon: 0.01));
      await tester.pump(const Duration(milliseconds: 120));
      expect(panelHeight(tester), 0.0);
      // The motion is done, and drops the picker, in its first frame past
      // its duration: AnimationController's simulation is done only past it.
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(CalendarTimePicker), findsNothing);
      expect(panelHeight(tester), 0.0);
    });
    expect(closing, isEmpty);
    expect(debugSchedulePickerAsks, asks);
  });

  testWidgets("FP2 where the platform asks for no animations the panel is at "
      "full height in the opening tap's own frame and in view in the next, "
      "and gone in the closing tap's own frame", (tester) async {
    disableAnimations(tester);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390.0, 300.0);
    addTearDown(tester.view.reset);
    final thursday = DateTime(2026, 4, 23);
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(10), isAllDay: false)),
      // Today is Thursday, so the picker shows no Now: the panel's opening
      // alone scrolls it into view.
      now: () {
        return CalendarNow(time: thursday, today: thursday);
      },
      theme: motionTheme,
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    await tester.tap(timeFieldFinder("Start time"));
    await tester.pump();
    expect(panelHeight(tester), settledPanelHeight(tester));
    await tester.pump();
    // The panel completed inside the tap's own frame, and the frame after
    // it scrolled the picker, opened past the view's bottom, into view.
    expect(position.pixels, greaterThan(0.0));
    final picker = tester.getRect(timePickerFinder("Start time"));
    expect(picker.top, greaterThanOrEqualTo(0.0));
    expect(picker.bottom, lessThanOrEqualTo(300.0));

    // Revealing the picker scrolled its field out of the view.
    await tester.ensureVisible(timeFieldFinder("Start time"));
    await tester.pump();
    // Setup sanity: the panel stays open.
    expect(panelHeight(tester), settledPanelHeight(tester));
    await tester.tap(timeFieldFinder("Start time"));
    await tester.pump();
    expect(find.byType(CalendarTimePicker), findsNothing);
    expect(panelHeight(tester), 0.0);
  });

  testWidgets("FP3 a panel made while its field is open shows the field's "
      "picker at once, and one tap on the field closes it", (tester) async {
    final schedule = CalendarSchedule.of(at(9), at(10), isAllDay: false);
    await pumpSection(tester, checkOf(schedule), theme: motionTheme);
    await openTimePicker(tester, "Start time");
    final before = tester.state(timePickerFinder("Start time"));
    // Without the switch above the Start row, the row and its panel are
    // made anew.
    await pumpSection(
      tester,
      checkOf(
        schedule,
        options: const CalendarScheduleOptions(allowsAllDay: false),
      ),
      theme: motionTheme,
    );
    // Setup sanity: the panel's picker is a new one.
    expect(tester.state(timePickerFinder("Start time")), isNot(same(before)));
    expect(panelHeight(tester), settledPanelHeight(tester));

    await tester.tap(timeFieldFinder("Start time"));
    await tester.pump();
    // The first frame past the theme's 480 ms, where the motion is done.
    await tester.pump(const Duration(milliseconds: 480));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(CalendarTimePicker), findsNothing);
  });

  testWidgets("FP4 where the platform asks for no animations while the panel "
      "grows or shrinks, the panel ends its motion in the next frame", (
    tester,
  ) async {
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(10), isAllDay: false)),
      theme: motionTheme,
    );
    await tester.tap(timeFieldFinder("Start time"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // Setup sanity: the panel is growing.
    expect(panelHeight(tester), lessThan(settledPanelHeight(tester)));
    disableAnimations(tester);
    await tester.pump();
    expect(panelHeight(tester), settledPanelHeight(tester));
    expect(panelOpacity(tester), 1.0);

    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pump();
    await tester.tap(timeFieldFinder("Start time"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // Setup sanity: the panel is shrinking.
    expect(panelHeight(tester), greaterThan(0.0));
    expect(panelHeight(tester), lessThan(settledPanelHeight(tester)));
    disableAnimations(tester);
    await tester.pump();
    expect(find.byType(CalendarTimePicker), findsNothing);
    expect(panelHeight(tester), 0.0);
  });

  testWidgets("FP5 once the panel has closed, a build of the section makes no "
      "picker: it reads no clock", (tester) async {
    var reads = 0;
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(10), isAllDay: false)),
      now: () {
        reads++;
        return wednesdayStart();
      },
    );
    reads = 0;
    await openTimePicker(tester, "Start time");
    // Setup sanity: a build of the section with the panel open reads the
    // clock, for the picker's Now.
    expect(reads, greaterThan(0));

    await closeTimePicker(tester, "Start time");
    // Setup sanity: the panel has closed.
    expect(find.byType(CalendarTimePicker), findsNothing);
    reads = 0;
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(11), isAllDay: false)),
      now: () {
        reads++;
        return wednesdayStart();
      },
    );
    // Setup sanity: the section built again.
    expect(timeFieldShows("End time", "11:00"), findsOneWidget);
    expect(reads, 0);
  });

  testWidgets("FX3 the footer an open picker gains as its field's day "
      "becomes today grows its panel at once and scrolls into view", (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390.0, 300.0);
    addTearDown(tester.view.reset);
    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(DateTime(2026, 4, 21, 22), at(2), isAllDay: false),
      ),
      theme: motionTheme,
    );
    await openTimePicker(tester, "Start time");
    expect(inPicker("Start time", find.byKey(timePickerNowKey)), findsNothing);
    final height = panelHeight(tester);
    final picker = tester.state(timePickerFinder("Start time"));

    // The start moves onto Wednesday, today.
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(1), at(2), isAllDay: false)),
      theme: motionTheme,
    );
    expect(panelHeight(tester), greaterThan(height));
    // Setup sanity: the panel kept its picker.
    expect(tester.state(timePickerFinder("Start time")), same(picker));
    await tester.pumpAndSettle();
    final now = tester.getRect(
      inPicker("Start time", find.byKey(timePickerNowKey)),
    );
    expect(now.top, greaterThanOrEqualTo(0.0));
    expect(now.bottom, lessThanOrEqualTo(300.0));
  });

  testWidgets("FS1 the summary card shows a one-day schedule's date above "
      "its times, and holds its length, its zone and the overlap notice", (
    tester,
  ) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10, 30)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    final first = find.byKey(scheduleSummaryFirstLineKey);
    final second = find.byKey(scheduleSummarySecondLineKey);
    final length = find.byKey(scheduleSummaryLengthKey);
    expect(tester.widget<Text>(first).data, "Wed, Apr 22");
    expect(tester.widget<Text>(second).data, "09:00 - 10:30");
    expect(tester.widget<Text>(length).data, "1h 30m");
    expect(
      tester.getRect(first).bottom,
      lessThanOrEqualTo(tester.getRect(second).top),
    );
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    final kolkata = tz.getLocation("Asia/Kolkata");
    final zoned = MemoryCalendarStore<ItemPayload>(
      zone: kolkata,
      entries: <CalendarItem>[
        task(
          "item-1",
          "Write",
          tz.TZDateTime(kolkata, 2026, 4, 22, 9),
          tz.TZDateTime(kolkata, 2026, 4, 22, 10, 30),
        ),
        task(
          "item-2",
          "Standup",
          tz.TZDateTime(kolkata, 2026, 4, 22, 10),
          tz.TZDateTime(kolkata, 2026, 4, 22, 11),
        ),
      ],
    );
    addTearDown(zoned.dispose);
    // The form's check reads the times on the clock of its now's time, so
    // its now is on Kolkata's, as the app's is on the store's zone.
    await openWith(tester, (context) {
      showEditForm(
        context,
        store: zoned,
        id: "item-1",
        policy: const UnrestrictedEditPolicy<ItemPayload>(),
        now: () {
          return CalendarNow(
            time: tz.TZDateTime(kolkata, 2026, 4, 22),
            today: wednesday,
          );
        },
        hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
      );
    });
    final card = tester.getRect(find.byKey(formSummaryCardKey));
    for (final part in <Finder>[
      find.text("Kolkata"),
      find.text("UTC+05:30"),
      find.byKey(scheduleOverlapKey),
      find.text("Next free time"),
    ]) {
      expect(part, findsOneWidget);
      expect(card.expandToInclude(tester.getRect(part)), card, reason: "$part");
    }
  });

  testWidgets("FS2 the summary names an all-day schedule's days, its pill "
      "All day for one day or its count of days for more, across a change "
      "of the clock included, and a timed one that spans days its start "
      "above its end, each with its date, and its length", (tester) async {
    Future<void> expectSummary(
      CalendarSchedule schedule,
      String first,
      String? second,
    ) async {
      await pumpSection(tester, checkOf(schedule));
      expect(
        tester.widget<Text>(find.byKey(scheduleSummaryFirstLineKey)).data,
        first,
      );
      final secondLine = find.byKey(scheduleSummarySecondLineKey);
      if (second == null) {
        expect(secondLine, findsNothing);
      } else {
        expect(tester.widget<Text>(secondLine).data, second);
      }
    }

    for (final (from, to, first, second, pill)
        in <(DateTime, DateTime, String, String, String)>[
          (
            wednesday,
            DateTime(2026, 4, 25),
            "Wed, Apr 22",
            "Fri, Apr 24",
            "3 days",
          ),
          (
            wednesday,
            DateTime(2026, 4, 24),
            "Wed, Apr 22",
            "Thu, Apr 23",
            "2 days",
          ),
          // Havana's clock skips its midnight on March 8 and repeats an hour
          // on November 1; each is one day of the count.
          (
            DateTime(2026, 3, 7),
            DateTime(2026, 3, 10),
            "Sat, Mar 7",
            "Mon, Mar 9",
            "3 days",
          ),
          (
            DateTime(2026, 10, 31),
            DateTime(2026, 11, 3),
            "Sat, Oct 31",
            "Mon, Nov 2",
            "3 days",
          ),
        ]) {
      await expectSummary(
        CalendarSchedule.of(from, to, isAllDay: true),
        first,
        second,
      );
      expect(
        tester.widget<Text>(find.byKey(scheduleSummaryLengthKey)).data,
        pill,
      );
    }
    await expectSummary(
      CalendarSchedule.of(wednesday, DateTime(2026, 4, 23), isAllDay: true),
      "Wed, Apr 22",
      null,
    );
    expect(
      tester.widget<Text>(find.byKey(scheduleSummaryLengthKey)).data,
      "All day",
    );

    await expectSummary(
      CalendarSchedule.of(DateTime(2026, 4, 21, 22), at(2), isAllDay: false),
      "Tue, Apr 21, 22:00",
      "Wed, Apr 22, 02:00",
    );
    final length = find.byKey(scheduleSummaryLengthKey);
    expect(tester.widget<Text>(length).data, "4h");
    expect(
      tester.getRect(find.byKey(scheduleSummaryFirstLineKey)).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(scheduleSummarySecondLineKey)).top,
      ),
    );
  });

  testWidgets("FS3 the summary card's top right corner names the zone, its "
      "city or Device time zone, above its offset from UTC at the start, "
      "in the same place for a schedule on one day and one that spans "
      "days", (tester) async {
    final zone = find.byKey(scheduleSummaryZoneKey);
    Rect zoneInCard() {
      final card = tester.getRect(find.byKey(formSummaryCardKey));
      final rect = tester.getRect(zone);
      // Setup sanity: the zone lies in the summary's card.
      expect(card.expandToInclude(rect), card);
      return rect.shift(-card.topLeft);
    }

    void expectZone(String name, DateTime start) {
      expect(zone, findsOneWidget);
      final texts = tester.widgetList<Text>(
        find.descendant(of: zone, matching: find.byType(Text)),
      );
      expect(
        <String?>[for (final text in texts) text.data],
        <String>[name, utcText(start.timeZoneOffset)],
      );
    }

    final local = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Trip", at(22), DateTime(2026, 4, 23, 2)),
    ]);
    addTearDown(local.dispose);
    await openEdit(tester, local);
    expectZone("Device time zone", at(9));
    final card = tester.getRect(find.byKey(formSummaryCardKey));
    final oneDay = zoneInCard();
    expect(oneDay.right, card.width - 16.0);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, local, id: "item-2");
    // Setup sanity: the summary writes the start and the end on lines of
    // their own.
    expect(summary(tester), "Wed, Apr 22, 22:00\nThu, Apr 23, 02:00\n4h");
    expect(zoneInCard(), oneDay);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    // The offset is that of the start, whatever the offset now: New York's
    // clock is at UTC-05:00 in January and at UTC-04:00 in July.
    final newYork = tz.getLocation("America/New_York");
    final january = tz.TZDateTime(newYork, 2026, 1, 14, 9);
    final july = tz.TZDateTime(newYork, 2026, 7, 15, 9);
    final zoned = MemoryCalendarStore<ItemPayload>(
      zone: newYork,
      entries: <CalendarItem>[
        task("item-1", "Write", january, january.add(const Duration(hours: 1))),
        task("item-2", "Plan", july, july.add(const Duration(hours: 1))),
      ],
    );
    addTearDown(zoned.dispose);
    for (final (id, start, offset) in <(String, DateTime, String)>[
      ("item-1", january, "UTC-05:00"),
      ("item-2", july, "UTC-04:00"),
    ]) {
      await openWith(tester, (context) {
        showEditForm(
          context,
          store: zoned,
          id: id,
          policy: const UnrestrictedEditPolicy<ItemPayload>(),
          now: () {
            return CalendarNow(
              time: tz.TZDateTime(newYork, 2026, 4, 22),
              today: wednesday,
            );
          },
          hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
        );
      });
      expect(utcText(start.timeZoneOffset), offset);
      expectZone("New York", start);
      expect(zoneInCard().topRight, oneDay.topRight);
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
    }
  });

  testWidgets("FS4 the summary card's top right corner shows the length in "
      "a pill, a timer icon before it, or for an all-day schedule All day, "
      "and under it the zone in a light grey rounded box, padded around its "
      "name and offset; an all-day schedule's date on one day is as large "
      "as a timed schedule's times; and the lines of a timed schedule that "
      "spans days are written at 14 pixels", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10, 30)),
      task("item-2", "Trip", at(22), DateTime(2026, 4, 23, 2)),
      task(
        "item-3",
        "Off",
        DateTime(2026, 4, 24),
        DateTime(2026, 4, 25),
        isAllDay: true,
      ),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    var card = tester.getRect(find.byKey(formSummaryCardKey));
    final zoneBox = find.byKey(scheduleSummaryZoneKey);
    expect(
      tester.widget<Container>(zoneBox).decoration,
      isA<BoxDecoration>()
          .having(
            (decoration) {
              return decoration.color;
            },
            "color",
            Colors.grey.shade100,
          )
          .having(
            (decoration) {
              return decoration.borderRadius;
            },
            "borderRadius",
            isNotNull,
          ),
    );
    final zone = tester.getRect(zoneBox);
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: zoneBox, matching: find.byType(Text)),
        )
        .map((text) {
          return tester.getRect(find.byWidget(text));
        })
        .reduce((all, rect) {
          return all.expandToInclude(rect);
        });
    // The box pads its texts on every side.
    final inner = zone.deflate(4.0);
    expect(inner.expandToInclude(texts), inner);
    final length = find.byKey(scheduleSummaryLengthKey);
    expect(tester.widget<Text>(length).data, "1h 30m");
    final timesSize = tester
        .widget<Text>(find.byKey(scheduleSummarySecondLineKey))
        .style
        ?.fontSize;
    final pill = find
        .ancestor(of: length, matching: find.byType(DecoratedBox))
        .first;
    expect(
      tester.widget<DecoratedBox>(pill).decoration,
      isA<ShapeDecoration>().having(
        (decoration) {
          return decoration.shape;
        },
        "shape",
        isA<StadiumBorder>(),
      ),
    );
    final pillRect = tester.getRect(pill);
    expect(pillRect.topRight, card.topRight + const Offset(-16.0, 16.0));
    expect(zone.top, greaterThanOrEqualTo(pillRect.bottom));
    expect(zone.right, pillRect.right);
    final icon = find.descendant(
      of: pill,
      matching: find.byIcon(Icons.timer_outlined),
    );
    expect(icon, findsOneWidget);
    expect(
      tester.getRect(icon).right,
      lessThanOrEqualTo(tester.getRect(length).left),
    );
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store, id: "item-2");
    for (final key in <Key>[
      scheduleSummaryFirstLineKey,
      scheduleSummarySecondLineKey,
    ]) {
      expect(tester.widget<Text>(find.byKey(key)).style?.fontSize, 14.0);
    }
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store, id: "item-3");
    // Setup sanity: the schedule is all-day.
    expect(formAllDayOn(), isTrue);
    expect(tester.widget<Text>(length).data, "All day");
    expect(find.byKey(scheduleSummarySecondLineKey), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(scheduleSummaryFirstLineKey)).style,
      isA<TextStyle>().having(
        (style) {
          return style.fontSize;
        },
        "fontSize",
        timesSize,
      ),
    );
    card = tester.getRect(find.byKey(formSummaryCardKey));
    final zoneRect = tester.getRect(find.byKey(scheduleSummaryZoneKey));
    final allDayPill = tester.getRect(
      find.ancestor(of: length, matching: find.byType(DecoratedBox)).first,
    );
    expect(allDayPill.topRight, card.topRight + const Offset(-16.0, 16.0));
    expect(zoneRect.top, greaterThanOrEqualTo(allDayPill.bottom));
    expect(zoneRect.right, allDayPill.right);
  });

  testWidgets("FS5 a line of a timed schedule that spans days, too wide for "
      "the room beside the corner, shrinks onto one line", (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400.0, 900.0);
    addTearDown(tester.view.reset);
    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(at(22), DateTime(2026, 4, 23, 2), isAllDay: false),
      ),
    );
    final zone = tester.getRect(find.byKey(scheduleSummaryZoneKey));
    for (final key in <Key>[
      scheduleSummaryFirstLineKey,
      scheduleSummarySecondLineKey,
    ]) {
      final line = tester.getRect(find.byKey(key));
      // The height of one line of the text's style, unscaled.
      final style = DefaultTextStyle.of(
        tester.element(find.byKey(key)),
      ).style.merge(tester.widget<Text>(find.byKey(key)).style);
      final oneLine = TextPainter(
        text: TextSpan(text: "x", style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      addTearDown(oneLine.dispose);
      expect(line.height, lessThanOrEqualTo(oneLine.height), reason: "$key");
      expect(line.right, lessThanOrEqualTo(zone.left), reason: "$key");
    }
  });

  testWidgets("FS6 a schedule that spans days shows its start and its end "
      "each under its label, Start and End, and no dash: a timed one's "
      "dates and times, an all-day one's first and last day, its pill "
      "counting its days; a schedule on one day shows no labels", (
    tester,
  ) async {
    Finder inSummary(Finder finder) {
      return find.descendant(
        of: find.byType(ScheduleSummary),
        matching: finder,
      );
    }

    for (final (schedule, from, to, pill)
        in <(CalendarSchedule, String, String, String)>[
          (
            CalendarSchedule.of(
              at(22),
              DateTime(2026, 4, 23, 2),
              isAllDay: false,
            ),
            "Wed, Apr 22, 22:00",
            "Thu, Apr 23, 02:00",
            "4h",
          ),
          (
            CalendarSchedule.of(
              wednesday,
              DateTime(2026, 4, 25),
              isAllDay: true,
            ),
            "Wed, Apr 22",
            "Fri, Apr 24",
            "3 days",
          ),
        ]) {
      await pumpSection(tester, checkOf(schedule));
      final first = find.byKey(scheduleSummaryFirstLineKey);
      final second = find.byKey(scheduleSummarySecondLineKey);
      expect(tester.widget<Text>(first).data, from);
      expect(tester.widget<Text>(second).data, to);
      final start = inSummary(find.text("Start"));
      final end = inSummary(find.text("End"));
      expect(start, findsOneWidget, reason: "$schedule");
      expect(end, findsOneWidget, reason: "$schedule");
      final length = find.byKey(scheduleSummaryLengthKey);
      expect(tester.widget<Text>(length).data, pill);
      // The pill of an all-day schedule that spans days counts its days.
      expect(inSummary(find.text("All day")), findsNothing);
      final parts = <Finder>[start, first, end, second];
      final top = <Rect>[for (final part in parts) tester.getRect(part)];
      for (var index = 1; index < top.length; index++) {
        expect(
          top[index - 1].bottom,
          lessThanOrEqualTo(top[index].top),
          reason: "$schedule: ${parts[index]}",
        );
      }
      expect(top[0].left, top[1].left, reason: "$schedule");
      expect(top[2].left, top[3].left, reason: "$schedule");
    }

    for (final schedule in <CalendarSchedule>[
      CalendarSchedule.of(at(9), at(10), isAllDay: false),
      CalendarSchedule.of(wednesday, DateTime(2026, 4, 23), isAllDay: true),
    ]) {
      await pumpSection(tester, checkOf(schedule));
      expect(inSummary(find.text("Start")), findsNothing, reason: "$schedule");
      expect(inSummary(find.text("End")), findsNothing, reason: "$schedule");
    }
  });

  testWidgets("FS7 the overlap notice writes each overlapped item's title "
      "in bold, and its other words not in bold", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Standup", at(9, 30), at(10, 30)),
      task("item-3", "Review", at(9, 45), at(10, 15)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    final notice = tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byKey(scheduleOverlapKey),
            matching: find.byType(RichText),
          ),
        )
        .singleWhere((text) {
          return text.text.toPlainText().startsWith("Overlaps");
        });
    // Each run of the notice's text, and whether its style, merged down
    // the spans from the root's, is bold.
    final runs = <(String, bool)>[];
    void collect(InlineSpan span, TextStyle inherited) {
      final style = inherited.merge(span.style);
      if (span is! TextSpan) {
        return;
      }
      final text = span.text;
      if (text != null && text.isNotEmpty) {
        runs.add((text, style.fontWeight == FontWeight.bold));
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        collect(child, style);
      }
    }

    collect(notice.text, const TextStyle());
    expect(runs, <(String, bool)>[
      ("Overlaps ", false),
      ("Standup", true),
      (", ", false),
      ("Review", true),
    ]);
  });

  testWidgets("FS8 the overlap notice's warning icon lies at its top left: "
      "before its text and level with the text's top, whether the text "
      "takes one line or more", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Standup", at(9, 30), at(10, 30)),
      task("item-3", "Draft", at(14), at(15)),
      task(
        "item-4",
        "Quarterly planning review with the whole team",
        at(14, 30),
        at(15, 30),
      ),
    ]);
    addTearDown(store.dispose);
    final notice = find.byKey(scheduleOverlapKey);
    final icon = find.descendant(
      of: notice,
      matching: find.byIcon(Icons.warning_amber),
    );
    final text = find.descendant(
      of: notice,
      matching: find.textContaining("Overlaps"),
    );
    final heights = <double>[];
    for (final id in <String>["item-1", "item-3"]) {
      await openEdit(tester, store, id: id);
      final iconRect = tester.getRect(icon);
      final textRect = tester.getRect(text);
      expect(iconRect.top, textRect.top, reason: id);
      expect(iconRect.right, lessThanOrEqualTo(textRect.left), reason: id);
      heights.add(textRect.height);
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
    }
    // Setup sanity: the second notice's text takes more lines than the
    // first's.
    expect(heights[1], greaterThanOrEqualTo(2 * heights[0]));
  });

  testWidgets("IP1 a tap on Start date or End date opens no dialog but the "
      "calendar card under its row, folded on the field's week, its day "
      "selected and the form's today ringed", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    for (final (label, panel) in <(String, Key)>[
      ("Start date", scheduleStartPanelKey),
      ("End date", scheduleEndPanelKey),
    ]) {
      Finder under(Finder finder) {
        return find.descendant(of: find.byKey(panel), matching: finder);
      }

      await tester.tap(formDateFinder(label));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing, reason: label);
      expect(
        under(find.byType(CalendarCard<ItemPayload>)),
        findsOneWidget,
        reason: label,
      );
      expect(
        under(find.byType(WeekStrip<ItemPayload>)),
        findsOneWidget,
        reason: label,
      );
      expect(
        under(find.byType(MonthStrip<ItemPayload>)),
        findsNothing,
        reason: label,
      );
      final cell = under(find.byKey(weekStripDayKey(wednesday)));
      expect(cell.hitTestable(), findsOneWidget, reason: label);
      final day = tester.widget<DayCell>(
        find.descendant(of: cell, matching: find.byType(DayCell)),
      );
      expect(day.isSelected, isTrue, reason: label);
      // The form's clock reads Wednesday, not the device's today.
      expect(day.isToday, isTrue, reason: label);
      expect(
        tester.widgetList<DayCell>(under(find.byType(DayCell))).where((cell) {
          return cell.isToday;
        }),
        hasLength(1),
        reason: label,
      );
    }
  }, skip: true);

  testWidgets("IP2 a day picked in Start date's picker moves the item there "
      "and leaves the picker open, and one picked in End date's moves the "
      "end alone", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    Finder cellUnder(Key panel, DateTime day) {
      return find.descendant(
        of: find.byKey(panel),
        matching: find.byKey(weekStripDayKey(day)),
      );
    }

    final friday = DateTime(2026, 4, 24);
    await tester.tap(formDateFinder("Start date"));
    await tester.pumpAndSettle();
    await tester.tap(cellUnder(scheduleStartPanelKey, friday));
    await tester.pumpAndSettle();
    expect(summary(tester), "Fri, Apr 24\n09:00 - 10:00\n1h");
    expect(formDateShows("Start date", "2026-04-24"), findsOneWidget);
    expect(formDateShows("End date", "2026-04-24"), findsOneWidget);
    expect(
      tester
          .widget<DayCell>(
            find.descendant(
              of: cellUnder(scheduleStartPanelKey, friday),
              matching: find.byType(DayCell),
            ),
          )
          .isSelected,
      isTrue,
    );

    final saturday = DateTime(2026, 4, 25);
    await tester.tap(formDateFinder("End date"));
    await tester.pumpAndSettle();
    await tester.tap(cellUnder(scheduleEndPanelKey, saturday));
    await tester.pumpAndSettle();
    expect(formDateShows("Start date", "2026-04-24"), findsOneWidget);
    expect(formDateShows("End date", "2026-04-25"), findsOneWidget);
    expect(summary(tester), "Fri, Apr 24, 09:00\nSat, Apr 25, 10:00\n25h");
  }, skip: true);
}

/// An offset from UTC as the zone panel writes it: "UTC-04:00".
String utcText(Duration offset) {
  final minutes = offset.inMinutes;
  final sign = minutes < 0 ? "-" : "+";
  final hours = (minutes.abs() ~/ 60).toString().padLeft(2, "0");
  final rest = (minutes.abs() % 60).toString().padLeft(2, "0");
  return "UTC$sign$hours:$rest";
}

/// A [ScheduleSection], built by [builder], whose check follows its edits:
/// each report makes the check that of the reported schedule
/// ([CalendarScheduleCheck.withSchedule]) and then goes to [onChanged]. A
/// new [check] replaces the one it holds.
class _FollowingSection extends StatefulWidget {
  const _FollowingSection({
    required this.check,
    required this.onChanged,
    required this.builder,
  });

  final CalendarScheduleCheck<ItemPayload> check;
  final ValueChanged<CalendarSchedule> onChanged;
  final Widget Function(
    CalendarScheduleCheck<ItemPayload> check,
    ValueChanged<CalendarSchedule> onChanged,
  )
  builder;

  @override
  State<_FollowingSection> createState() {
    return _FollowingSectionState();
  }
}

class _FollowingSectionState extends State<_FollowingSection> {
  late CalendarScheduleCheck<ItemPayload> _check = widget.check;

  @override
  void didUpdateWidget(_FollowingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.check, widget.check)) {
      _check = widget.check;
    }
  }

  void _report(CalendarSchedule schedule) {
    setState(() {
      _check = _check.withSchedule(schedule);
    });
    widget.onChanged(schedule);
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_check, _report);
  }
}

/// A policy that records each day it is asked the earliest start of in
/// [asked], and answers the day's start.
final class _CountingPolicy extends CalendarEditPolicy<ItemPayload> {
  const _CountingPolicy(this.asked);

  final List<DateTime> asked;

  @override
  DateTime? earliestStartOn(DateTime day, CalendarNow now) {
    asked.add(day);
    return day;
  }
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
