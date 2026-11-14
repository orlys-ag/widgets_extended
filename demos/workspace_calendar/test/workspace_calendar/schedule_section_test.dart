/// The item form's sheet, its summary card and its schedule section: the
/// sheet's container and type selector, the message of each schedule
/// problem, the messages after a failed Save, the summary's lines, overlap
/// notice, next free time and zone, and the section's All day switch, End
/// date, options and kept kind, and its time fields, the pickers they open,
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

/// The panel under the time row that holds the section's one picker.
Finder pickerPanel() {
  return find.byKey(schedulePickerKey);
}

/// The height of the picker panel.
double panelHeight(WidgetTester tester) {
  return tester.getSize(pickerPanel()).height;
}

/// The height of the open picker panel at rest: its picker's, which the
/// panel lays out at full height while it grows or shrinks, and the gap
/// above it.
double settledPanelHeight(WidgetTester tester) {
  return tester.getSize(find.byType(CalendarTimePicker)).height + 12.0;
}

/// The opacity of the picker panel, the first [FadeTransition] under it.
double panelOpacity(WidgetTester tester) {
  return tester
      .widget<FadeTransition>(
        find
            .descendant(
              of: pickerPanel(),
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
    expect(summary(tester), "Wed, Apr 22, 22:00 -\nThu, Apr 23, 02:00\n4h");
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store);
    await tester.tap(find.text("All day"));
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

  testWidgets("SS5 a store on a zone names it in the summary", (tester) async {
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
    final schedule = CalendarSchedule.of(at(9), at(10), isAllDay: false);
    await pumpSection(tester, checkOf(schedule));
    expect(find.text("Ends on another day"), findsOneWidget);
    expect(allDaySwitch(), findsOneWidget);

    await pumpSection(
      tester,
      checkOf(
        schedule,
        options: const CalendarScheduleOptions(
          allowsAllDay: false,
          spansDays: false,
        ),
      ),
    );
    expect(allDaySwitch(), findsNothing);
    expect(find.text("All day"), findsNothing);
    expect(find.text("Ends on another day"), findsNothing);
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
    expect(tester.widget<SwitchListTile>(allDaySwitch()).onChanged, isNull);

    final timed = task("item-2", "Write", DateTime(2026, 4, 21, 22), at(10));
    final timedCheck = checkOf(
      CalendarSchedule.of(timed.start, timed.end, isAllDay: false),
      policy: lock,
      entry: timed,
    );
    expect(timedCheck.startFixed, isTrue);
    await pumpSection(tester, timedCheck);
    expect(formAllDayOn(), isFalse);
    expect(tester.widget<SwitchListTile>(allDaySwitch()).onChanged, isNull);
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
      "the time row, a pick there settles into the schedule, a tap on End "
      "time keeps the panel and shows the end's picker alone, and a second "
      "tap closes it; a fixed start's field opens none", (tester) async {
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

    final panel = tester.state(pickerPanel());
    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(tester.state(pickerPanel()), same(panel));
    expect(
      find.descendant(
        of: pickerPanel(),
        matching: timePickerFinder("End time"),
      ),
      findsOneWidget,
    );
    expect(timePickerFinder("Start time"), findsNothing);
    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarTimePicker), findsNothing);
    expect(panelHeight(tester), 0.0);
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
      "it as the picker opens, keeps it as the picker passes to the other "
      "field, and its field takes it as it closes", (tester) async {
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
    final hourNode = FocusManager.instance.primaryFocus;

    await tester.tap(timeFieldFinder("End time"));
    await tester.pumpAndSettle();
    expect(
      focusUnder(inPicker("End time", find.byKey(timePickerHourColumnKey))),
      isTrue,
    );
    // The one picker's Hour column keeps its node for either field.
    expect(FocusManager.instance.primaryFocus, same(hourNode));

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
    expect(tester.widget<SwitchListTile>(allDaySwitch()).onChanged, isNull);
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

  testWidgets("FP1 the panel grows and fades in over the theme's motion as "
      "Start time opens it, and shrinks and fades out as the field closes "
      "it, its picker neither rebuilt nor asked in between", (tester) async {
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
      await tester.pump(const Duration(milliseconds: 16));
      full = settledPanelHeight(tester);
      expect(panelHeight(tester), lessThan(full));
      expect(panelOpacity(tester), lessThan(1.0));
      // 240 ms after the tap's own frame, half the theme's 480 ms.
      await tester.pump(const Duration(milliseconds: 224));
      expect(panelOpacity(tester), moreOrLessEquals(0.5, epsilon: 0.01));
      expect(panelHeight(tester), moreOrLessEquals(full / 2, epsilon: 1.0));
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
      await tester.pump(const Duration(milliseconds: 16));
      expect(panelHeight(tester), lessThan(full));
      expect(panelHeight(tester), greaterThan(0.0));
      expect(panelOpacity(tester), lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 464));
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
    // Without the switch above the time row, the row and its panel are
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
    await tester.tap(find.text("Ends on another day"));
    await tester.pump();
    // Setup sanity: the section built again.
    expect(formDateFinder("End date"), findsOneWidget);
    expect(reads, 0);
  });

  testWidgets("FX1 a tap on End time while Start's picker is open keeps the "
      "panel open and its picker, whose Hour column moves over the theme's "
      "motion to the end's time, rebuilding and asking nothing as it "
      "moves", (tester) async {
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(12), isAllDay: false)),
      theme: motionTheme,
    );
    await expectPickerPassesToEnd(tester);
  });

  testWidgets("FX2 where the platform asks for no animations a tap on End "
      "time while Start's picker is open keeps the panel open and its "
      "picker, whose Hour column still moves to the end's time", (
    tester,
  ) async {
    disableAnimations(tester);
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(12), isAllDay: false)),
      theme: motionTheme,
    );
    // The picker's columns run on AnimationController.unbounded, whose
    // AnimationBehavior.preserve keeps the theme's full 480 ms under the
    // flag, so every 16 ms frame up to 464 ms lies between the rows.
    await expectPickerPassesToEnd(tester);
  });

  testWidgets("FX3 the footer the picker gains as it passes to a field on "
      "today grows the open panel at once and scrolls into view", (
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

    await tester.tap(timeFieldFinder("End time"));
    await tester.pump();
    expect(panelHeight(tester), greaterThan(height));
    expect(tester.state(timePickerFinder("End time")), same(picker));
    await tester.pumpAndSettle();
    final now = tester.getRect(
      inPicker("End time", find.byKey(timePickerNowKey)),
    );
    expect(now.top, greaterThanOrEqualTo(0.0));
    expect(now.bottom, lessThanOrEqualTo(300.0));
  });

  testWidgets("FS1 the summary card shows a one-day schedule's date above "
      "its times and its length below them, and holds the zone line and the "
      "overlap notice", (tester) async {
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
    expect(
      tester.getRect(second).bottom,
      lessThanOrEqualTo(tester.getRect(length).top),
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
      find.text("Times in Asia/Kolkata"),
      find.byKey(scheduleOverlapKey),
      find.text("Next free time"),
    ]) {
      expect(part, findsOneWidget);
      expect(card.expandToInclude(tester.getRect(part)), card, reason: "$part");
    }
  });

  testWidgets("FS2 the summary names an all-day schedule's days and All "
      "day, and a timed one that spans days its start above its end, each "
      "with its date, then its length", (tester) async {
    Future<void> expectSummary(
      CalendarSchedule schedule,
      String first,
      String second,
    ) async {
      await pumpSection(tester, checkOf(schedule));
      expect(
        tester.widget<Text>(find.byKey(scheduleSummaryFirstLineKey)).data,
        first,
      );
      expect(
        tester.widget<Text>(find.byKey(scheduleSummarySecondLineKey)).data,
        second,
      );
    }

    await expectSummary(
      CalendarSchedule.of(wednesday, DateTime(2026, 4, 25), isAllDay: true),
      "Wed, Apr 22 - Fri, Apr 24",
      "All day",
    );
    expect(find.byKey(scheduleSummaryLengthKey), findsNothing);
    await expectSummary(
      CalendarSchedule.of(wednesday, DateTime(2026, 4, 23), isAllDay: true),
      "Wed, Apr 22",
      "All day",
    );
    expect(find.byKey(scheduleSummaryLengthKey), findsNothing);

    await expectSummary(
      CalendarSchedule.of(DateTime(2026, 4, 21, 22), at(2), isAllDay: false),
      "Tue, Apr 21, 22:00 -",
      "Wed, Apr 22, 02:00",
    );
    final length = find.byKey(scheduleSummaryLengthKey);
    expect(tester.widget<Text>(length).data, "4h");
    final second = tester.getRect(find.byKey(scheduleSummarySecondLineKey));
    expect(
      tester.getRect(find.byKey(scheduleSummaryFirstLineKey)).bottom,
      lessThanOrEqualTo(second.top),
    );
    expect(second.bottom, lessThanOrEqualTo(tester.getRect(length).top));
  });
}

/// Opens Start's picker on a section of 09:00 to 12:00 and taps End time:
/// expects the panel to stay at full height with the same picker, whose
/// Hour column shows the end's row of 12 three rows below its pill in the
/// tap's own frame, between them in a later frame, and on the pill at rest,
/// the picker rebuilt and asked nothing after the tap's own frame.
Future<void> expectPickerPassesToEnd(WidgetTester tester) async {
  await openTimePicker(tester, "Start time");
  final full = panelHeight(tester);
  // Setup sanity: the panel is open at rest.
  expect(full, settledPanelHeight(tester));
  final picker = tester.state(timePickerFinder("Start time"));
  final row = hourRowFromPill(tester, "Start time", 10);
  // Setup sanity: 09:00 lies on the pill.
  expect(hourRowFromPill(tester, "Start time", 9).abs(), lessThan(0.5));

  await tester.tap(timeFieldFinder("End time"));
  await tester.pump();
  expect(panelHeight(tester), full);
  expect(tester.state(timePickerFinder("End time")), same(picker));
  expect(
    hourRowFromPill(tester, "End time", 12),
    moreOrLessEquals(3 * row, epsilon: 0.5),
  );
  final asks = debugSchedulePickerAsks;
  var between = false;
  final rebuilt = await pickerRebuildsDuring(() async {
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final offset = hourRowFromPill(tester, "End time", 12);
      between = between || (offset > 0.5 && offset < 3 * row - 0.5);
      expect(panelHeight(tester), full);
    }
  });
  expect(between, isTrue);
  expect(hourRowFromPill(tester, "End time", 12).abs(), lessThan(0.5));
  expect(rebuilt, isEmpty);
  expect(debugSchedulePickerAsks, asks);
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
