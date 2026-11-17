/// The item form's sheet, its heading and its schedule section: the sheet's
/// container, what closes it, where its actions lie and its type selector,
/// the message of each schedule problem, the messages before and after a
/// failed Save and the field a failed Save reveals, the heading's length
/// pill and zone box, the overlap notice and next free time, and the
/// section's All day switch, its Start and End rows, End date, options and
/// kept kind, and its time fields, the pickers they open under their rows,
/// what each picker refuses, and where the focus goes.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:widgets_extended/calendar/composition/calendar_card.dart'
    show CalendarCard, calendarPullTabKey;
import 'package:widgets_extended/calendar/views/day_cell.dart'
    show DayCell, dayCellKey;
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
import 'package:workspace_calendar/workspace_calendar/calendar_api.dart'
    show CalendarValidationException;
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart'
    show HarborColors;
import 'package:workspace_calendar/workspace_calendar/item_builders.dart'
    show harborDayBadges;
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
/// Under [theme], where given, the host's button lies under a
/// [CalendarTheme] of it, which the sheet the button opens captures.
Future<void> openWith(
  WidgetTester tester,
  void Function(BuildContext context) open, {
  CalendarThemeData? theme,
}) async {
  Widget button = Builder(
    builder: (context) {
      return TextButton(
        onPressed: () {
          open(context);
        },
        child: const Text("Open"),
      );
    },
  );
  if (theme != null) {
    button = CalendarTheme(data: theme, child: button);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(body: button),
    ),
  );
  await tester.tap(find.text("Open"));
  await tester.pumpAndSettle();
}

/// Opens the form of the stored [id] under [policy], or else one that
/// refuses nothing, drawn and moving as [theme] says, where given.
Future<void> openEdit(
  WidgetTester tester,
  CalendarStore<ItemPayload> store, {
  String id = "item-1",
  CalendarEditPolicy<ItemPayload> policy =
      const UnrestrictedEditPolicy<ItemPayload>(),
  CalendarThemeData? theme,
}) {
  return openWith(tester, (context) {
    showEditForm(
      context,
      store: store,
      id: id,
      policy: policy,
      now: wednesdayStart,
      hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
    );
  }, theme: theme);
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

MemoryCalendarStore<ItemPayload> storeOf(List<CalendarItem> items) {
  return MemoryCalendarStore<ItemPayload>(entries: items);
}

/// The check of [schedule] under [policy] at [now] or else Wednesday's
/// start, in the calendar's whole day of 15-minute slots, for the stored
/// [entry] or a new one, with [options] or a Task's, against [others]. The
/// check reads its times on the clock of [now]'s time.
CalendarScheduleCheck<ItemPayload> checkOf(
  CalendarSchedule schedule, {
  CalendarEditPolicy<ItemPayload> policy =
      const UnrestrictedEditPolicy<ItemPayload>(),
  CalendarItem? entry,
  CalendarScheduleOptions? options,
  CalendarNow? now,
  List<CalendarItem> others = const <CalendarItem>[],
}) {
  return CalendarScheduleCheck<ItemPayload>(
    schedule: schedule,
    rules: CalendarEditRules<ItemPayload>(
      policy: policy,
      hours: CalendarDayHours.allDay,
      slotMinutes: 15,
    ),
    now: now ?? wednesdayStart(),
    others: others,
    entry: entry,
    options: options ?? scheduleOptionsOf(CalendarItemType.task),
  );
}

/// Pumps the section of [check] under its [ScheduleHeading], titled
/// "Schedule", and over its [ScheduleOverlapNotice], which shows while the
/// check names overlaps, in the form's order, without the form, in the
/// calendar's whole day of 15-minute slots on the 24-hour clock, on
/// [zone]'s clock, the pickers' Now reading [now] or else Wednesday's
/// start, the edits of the section and the notice going to [onChanged] or
/// else nowhere, and locked where [locked]. Where [follows], each edit also
/// makes their check that of the edited schedule
/// ([CalendarScheduleCheck.withSchedule]) before it goes to [onChanged], so
/// the next frame builds the parts of the edit, as the form's does;
/// otherwise they keep [check]. Under [theme], where given,
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
        ScheduleHeading(title: "Schedule", check: check, zone: zone),
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
        ScheduleOverlapNotice(
          check: check,
          hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
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

/// An ease-out curve, Cubic(0.2, 0.0, 0.0, 1.0): played backwards, a
/// motion on it would start slowly.
const Curve easeOut = Cubic(0.2, 0.0, 0.0, 1.0);

/// [motionTheme] on [easeOut].
final CalendarThemeData easedTheme = motionTheme.copyWith(motionCurve: easeOut);

/// The opacity of the nearest [FadeTransition] above what [finder] finds.
double fadeAbove(WidgetTester tester, Finder finder) {
  return tester
      .widget<FadeTransition>(
        find.ancestor(of: finder, matching: find.byType(FadeTransition)).first,
      )
      .opacity
      .value;
}

/// The panel under the row of the field labelled [label], "Start date",
/// "Start time", "End date" or "End time", that holds the picker of the
/// row's open field.
Finder pickerPanel([String label = "Start time"]) {
  switch (label) {
    case "Start date":
    case "Start time":
      return find.byKey(scheduleStartPanelKey);
    case "End date":
    case "End time":
      return find.byKey(scheduleEndPanelKey);
  }
  throw ArgumentError.value(label, "label", "names no field");
}

/// The height of the picker panel of the row of the field labelled
/// [label].
double panelHeight(WidgetTester tester, [String label = "Start time"]) {
  return tester.getSize(pickerPanel(label)).height;
}

/// The height of the open picker panel of the time field labelled [label]
/// at rest: its picker's, which the panel lays out at full height while it
/// grows or shrinks, and the gap above it.
double settledPanelHeight(WidgetTester tester, [String label = "Start time"]) {
  return tester.getSize(timePickerFinder(label)).height + 12.0;
}

/// The height of the panel of the date field labelled [label] at rest with
/// its day picker open: the day picker's, and the gap above it.
double settledDayPanelHeight(WidgetTester tester, String label) {
  return tester.getSize(dayPickerFinder(label)).height + 12.0;
}

/// The opacity of the picker panel of the row of the field labelled
/// [label], the first [FadeTransition] under it.
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

/// The form's page, the scroll view of its cards.
Finder formPage() {
  return find
      .ancestor(
        of: find.byKey(formItemCardKey),
        matching: find.byType(Scrollable),
      )
      .first;
}

/// The pill around the heading's length: the nearest [DecoratedBox] around
/// its text.
Finder lengthPill() {
  return find
      .ancestor(
        of: find.byKey(scheduleLengthKey),
        matching: find.byType(DecoratedBox),
      )
      .first;
}

/// The open sheet's [Material].
Finder sheetFinder() {
  return find
      .descendant(of: find.byType(BottomSheet), matching: find.byType(Material))
      .first;
}

/// The scroll position of the form's page.
ScrollPosition pagePosition(WidgetTester tester) {
  return tester.state<ScrollableState>(formPage()).position;
}

/// Whether the form's text field labelled [label] has the focus.
bool fieldHasFocus(WidgetTester tester, String label) {
  return tester
      .widget<EditableText>(
        find.descendant(
          of: fieldFinder(label),
          matching: find.byType(EditableText),
        ),
      )
      .focusNode
      .hasFocus;
}

/// The messages of the form's scheduling part's fields, in the page's
/// order: Start date, Start time, End date and End time for a timed
/// schedule.
List<String?> scheduleFieldErrors(WidgetTester tester) {
  return tester
      .widgetList<InputDecorator>(
        find.descendant(
          of: find.byKey(formSchedulingCardKey),
          matching: find.byType(InputDecorator),
        ),
      )
      .map((decorator) {
        return decorator.decoration.errorText;
      })
      .toList();
}

/// The texts of [elements], [Text] widgets, in their order.
List<String> _textsOf(Iterable<Element> elements) {
  return elements.map((element) {
    final text = element.widget as Text;
    return text.data ?? text.textSpan!.toPlainText();
  }).toList();
}

/// The texts of the overlap notice's card of the item [id], in the order
/// they are laid out, its bar's left out.
List<String> overlapCardTexts(WidgetTester tester, String id) {
  final bar = find
      .descendant(
        of: find.byKey(scheduleOverlapBarKey(id)),
        matching: find.byType(Text),
      )
      .evaluate()
      .toSet();
  return _textsOf(
    find
        .descendant(
          of: find.byKey(scheduleOverlapCardKey(id)),
          matching: find.byType(Text),
        )
        .evaluate()
        .where((element) {
          return !bar.contains(element);
        }),
  );
}

/// The texts of the bar of the overlap notice's card of the item [id], in
/// the order they are laid out.
List<String> overlapBarTexts(WidgetTester tester, String id) {
  return _textsOf(
    find
        .descendant(
          of: find.byKey(scheduleOverlapBarKey(id)),
          matching: find.byType(Text),
        )
        .evaluate(),
  );
}

/// The fill of the box decoration of the widget [finder] finds.
Color? decorationColor(WidgetTester tester, Finder finder) {
  final decoration = tester.widget<DecoratedBox>(finder).decoration;
  return (decoration as BoxDecoration).color;
}

/// The fill of the chip of the time the overlap notice's card of [id]
/// shares, the nearest [DecoratedBox] around its text, and the colour of
/// the card's border.
(Color?, Color?) overlapCardColors(WidgetTester tester, String id) {
  final card = find.byKey(scheduleOverlapCardKey(id));
  final chip = find
      .ancestor(
        of: find.descendant(
          of: card,
          matching: find.textContaining(RegExp(r"^(Shares|Covers)")),
        ),
        matching: find.byType(DecoratedBox),
      )
      .first;
  final shape = tester.widget<DecoratedBox>(chip).decoration;
  final box = tester.widget<DecoratedBox>(card).decoration as BoxDecoration;
  return ((shape as ShapeDecoration).color, (box.border! as Border).top.color);
}

/// The corners of the box decoration of the widget [finder] finds.
BorderRadiusGeometry? decorationRadius(WidgetTester tester, Finder finder) {
  final decoration = tester.widget<DecoratedBox>(finder).decoration;
  return (decoration as BoxDecoration).borderRadius;
}

/// The left and right of the part of the bar of the overlap notice's card
/// of [id] that [key] names, as fractions of the bar's axis, each to three
/// decimals.
(double, double) overlapSpan(
  WidgetTester tester,
  String id,
  ValueKey<String> Function(String id) key,
) {
  final axis = tester.getRect(find.byKey(scheduleOverlapAxisKey(id)));
  final span = tester.getRect(find.byKey(key(id)));
  double fraction(double x) {
    return ((x - axis.left) / axis.width * 1000).round() / 1000;
  }

  return (fraction(span.left), fraction(span.right));
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

  testWidgets("SF1 the form is a bottom sheet that a drag down and the back "
      "gesture close, and the barrier does not", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    await tester.tapAt(const Offset(10.0, 10.0));
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsOneWidget);
    await tester.drag(find.text("Edit Task"), const Offset(0.0, 600.0));
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsNothing);

    await tester.tap(find.text("Open"));
    await tester.pumpAndSettle();
    // Setup sanity: the form is open again.
    expect(find.text("Edit Task"), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsNothing);
  });

  testWidgets("SF5 while a save is in flight a drag leaves the sheet where "
      "it is, and the save then closes it", (tester) async {
    final store = _HeldUpdates(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    final sheet = tester.getRect(find.byType(BottomSheet));
    await tester.tap(saveFinder());
    await tester.pump();
    // Setup sanity: the save is in flight.
    expect(
      find.descendant(
        of: saveFinder(),
        matching: find.byType(CalendarActivityIndicator),
      ),
      findsOneWidget,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text("Edit Task")),
    );
    // The first move takes the pointer past the slop; a sheet that took the
    // drag would follow the next.
    await gesture.moveBy(const Offset(0.0, 20.0));
    await gesture.moveBy(const Offset(0.0, 300.0));
    await tester.pump();
    expect(tester.getRect(find.byType(BottomSheet)), sheet);
    await gesture.moveBy(const Offset(0.0, 300.0));
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("Edit Task"), findsOneWidget);

    store.release.complete();
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsNothing);
  });

  testWidgets("SF6 Delete lies at the actions' start and Cancel and Save "
      "at their end, as do Cancel and Save with no Delete; where the sheet "
      "cannot fit them in a row, Delete stacks above Cancel and Save", (
    tester,
  ) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    // Expects Save at the item card's end and Cancel beside it.
    void expectEndActions(String step) {
      final save = tester.getRect(saveFinder());
      final cancel = tester.getRect(formButton("Cancel"));
      expect(
        save.right,
        tester.getRect(find.byKey(formItemCardKey)).right,
        reason: step,
      );
      expect(cancel.right, save.left - 8.0, reason: step);
      expect(cancel.top, save.top, reason: step);
    }

    await openEdit(tester, store);
    expectEndActions("row");
    final delete = tester.getRect(formButton("Delete"));
    expect(delete.left, tester.getRect(find.byKey(formItemCardKey)).left);
    expect(delete.top, tester.getRect(saveFinder()).top);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openCreate(
      tester,
      store,
      CalendarCreateRange(start: at(11), end: at(12)),
    );
    // Setup sanity: a new item has no Delete.
    expect(formButton("Delete"), findsNothing);
    expectEndActions("no Delete");
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(360.0, 800.0);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await openEdit(tester, store);
    expectEndActions("stacked");
    final stacked = tester.getRect(formButton("Delete"));
    expect(stacked.right, tester.getRect(find.byKey(formItemCardKey)).right);
    expect(stacked.bottom, lessThanOrEqualTo(tester.getRect(saveFinder()).top));
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
      "card, and a read-only item its schedule and Close alone", (
    tester,
  ) async {
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
    expect(formSchedule(tester), "Wed, Apr 22, 09:00\nWed, Apr 22, 10:00\n1h");
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
    // A refused overlap names no field: the overlap notice states it, and
    // the start's message is the first other problem's.
    expect(
      scheduleErrorsOf(<CalendarScheduleProblem>[
        CalendarScheduleOverlapRefused<ItemPayload>(other),
      ]),
      isEmpty,
    );
    expect(
      scheduleErrorsOf(<CalendarScheduleProblem>[
        CalendarScheduleOverlapRefused<ItemPayload>(other),
        const CalendarScheduleBeforeEarliest(),
      ]),
      <String, String>{"start": "The start can't be in the past."},
    );
  });

  testWidgets("SS1 SS2 the form shows the schedule and its length, "
      "which a new end changes, and the section offers no length chips", (
    tester,
  ) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10, 30)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(
      formSchedule(tester),
      "Wed, Apr 22, 09:00\nWed, Apr 22, 10:30\n1h 30m",
    );
    expect(find.byType(ChoiceChip), findsNothing);

    await pickTime(tester, "End time", "09:30");
    expect(formSchedule(tester), "Wed, Apr 22, 09:00\nWed, Apr 22, 09:30\n30m");
    await pickTime(tester, "End time", "10:00");
    expect(formSchedule(tester), "Wed, Apr 22, 09:00\nWed, Apr 22, 10:00\n1h");
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
    await pickFormDay(tester, "End date", DateTime(2026, 4, 23));
    expect(formDateShows("End date", "2026-04-23"), findsOneWidget);
    expect(
      formSchedule(tester),
      "Wed, Apr 22, 09:00\nThu, Apr 23, 10:00\n1d 1h",
    );
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store, id: "item-2");
    expect(formDateShows("End date", "2026-04-23"), findsOneWidget);
    expect(formSchedule(tester), "Wed, Apr 22, 22:00\nThu, Apr 23, 02:00\n4h");
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store);
    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(formDateShows("End date", "2026-04-22"), findsOneWidget);
    expect(timeFieldFinder("Start time"), findsNothing);
    expect(formSchedule(tester), "Wed, Apr 22\nWed, Apr 22\nAll day");
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
        matching: find.text("Overlaps 1 item"),
      ),
      findsOneWidget,
    );
    expect(find.byKey(scheduleOverlapCardKey("item-2")), findsOneWidget);
    await tester.ensureVisible(find.text("Next free time"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Next free time"));
    await tester.pumpAndSettle();
    expect(timeFieldShows("Start time", "10:30"), findsOneWidget);
    expect(timeFieldShows("End time", "11:30"), findsOneWidget);
    expect(find.byKey(scheduleOverlapKey), findsNothing);
  });

  testWidgets("SS5 the heading names a store's zone by its city, and the "
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
    expect(formSchedule(tester), "Wed, Apr 22\nWed, Apr 22\nAll day");
    expect(timeFieldFinder("Start time"), findsNothing);
    expect(formAllDayOn(), isTrue);

    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(
      formSchedule(tester),
      "Wed, Apr 22, 09:00\nWed, Apr 22, 10:30\n1h 30m",
    );
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
    expect(formSchedule(tester), "Wed, Apr 22\nWed, Apr 22\nAll day");
    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(formSchedule(tester), "Wed, Apr 22, 09:30\nWed, Apr 22, 10:30\n1h");
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
    expect(formSchedule(tester), "Wed, Apr 22\nWed, Apr 22\nAll day");
    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(formSchedule(tester), "Wed, Apr 22, 09:30\nWed, Apr 22, 10:30\n1h");
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
    expect(formSchedule(tester), "Wed, Apr 22, 09:30\nWed, Apr 22, 10:30\n1h");

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
    expect(formSchedule(tester), "Wed, Apr 22, 11:00\nWed, Apr 22, 12:00\n1h");
    await openTimePicker(tester, "Start time");
    await tester.tap(inPicker("Start time", find.byKey(timePickerNowKey)));
    await tester.pumpAndSettle();
    // The nearest slot would be 09:15.
    expect(formSchedule(tester), "Wed, Apr 22, 09:00\nWed, Apr 22, 10:00\n1h");
  });

  testWidgets("TF5 the start's picker stays open across Next free time, a "
      "day picked in Start date's picker replaces it, and the All day switch "
      "closes it and takes the focus", (tester) async {
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
    expect(formSchedule(tester), "Wed, Apr 22, 10:30\nWed, Apr 22, 11:30\n1h");
    expect(timePickerFinder("Start time"), findsOneWidget);

    await pickFormDay(tester, "Start date", DateTime(2026, 4, 23));
    expect(formSchedule(tester), "Thu, Apr 23, 10:30\nThu, Apr 23, 11:30\n1h");
    expect(timePickerFinder("Start time"), findsNothing);
    await openTimePicker(tester, "Start time");
    expect(timePickerFinder("Start time"), findsOneWidget);

    await tester.ensureVisible(allDaySwitch());
    await tester.pumpAndSettle();
    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    expect(formSchedule(tester), "Thu, Apr 23\nThu, Apr 23\nAll day");
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

  testWidgets("FA1 the times' messages follow the check from the form's "
      "opening, and the title's shows after a failed Save: the end's hours "
      "message before Save, the title's after it, a start picked in the "
      "hours clears the end's, and a title clears its own", (tester) async {
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
    final onEnd = find.descendant(
      of: timeFieldFinder("End time"),
      matching: find.text(endMessage),
    );
    expect(onEnd, findsOneWidget);
    expect(find.text("Enter a title."), findsNothing);

    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    expect(find.text("Enter a title."), findsOneWidget);
    expect(onEnd, findsOneWidget);

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

  testWidgets("FA2 after a failed Save a type field's message follows its "
      "value: Project's as it is typed and cleared; and a type change shows "
      "the new type's at once, Link's following its text and Kind's its "
      "choice", (tester) async {
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
    expect(find.text("Project is required."), findsNothing);
    await tester.enterText(fieldFinder("Project"), "");
    await tester.pump();
    expect(find.text("Project is required."), findsOneWidget);

    await tester.ensureVisible(find.text("Request").last);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Request").last);
    await tester.pumpAndSettle();
    expect(find.text("Kind is required."), findsOneWidget);
    expect(find.text("Enter an http or https link."), findsNothing);
    await tester.enterText(fieldFinder("Link"), "ftp://example.org");
    await tester.pump();
    expect(find.text("Enter an http or https link."), findsOneWidget);
    await tester.enterText(fieldFinder("Link"), "https://example.org");
    await tester.pump();
    expect(find.text("Enter an http or https link."), findsNothing);
    await tester.ensureVisible(dropdownFinder("Kind"));
    await tester.pumpAndSettle();
    await chooseOption(tester, "Kind", "Travel");
    expect(find.text("Kind is required."), findsNothing);
  });

  testWidgets("FA5 a refused send's message of a type field stays through "
      "other edits and a move of its field's selection until its own value "
      "changes, and a type change drops it", (tester) async {
    final store = _RefusedCreates(const <String, String>{
      "fields.severity": "Severity is under review.",
      "fields.project": "Apollo is closed.",
    });
    addTearDown(store.dispose);
    await openCreate(
      tester,
      store,
      CalendarCreateRange(start: at(9), end: at(10)),
    );
    await tester.tap(find.text("Risk").last);
    await tester.pumpAndSettle();
    await tester.enterText(fieldFinder("Title"), "Plan");
    await tester.enterText(fieldFinder("Project"), "Apollo");
    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    expect(find.text("Severity is under review."), findsOneWidget);
    expect(find.text("Apollo is closed."), findsOneWidget);

    await tester.enterText(fieldFinder("Owner"), "Kim");
    tester.widget<TextField>(fieldFinder("Project")).controller!.selection =
        const TextSelection.collapsed(offset: 0);
    await tester.pump();
    expect(find.text("Severity is under review."), findsOneWidget);
    expect(find.text("Apollo is closed."), findsOneWidget);
    await tester.ensureVisible(dropdownFinder("Severity"));
    await tester.pumpAndSettle();
    await chooseOption(tester, "Severity", "High");
    expect(find.text("Severity is under review."), findsNothing);
    expect(find.text("Apollo is closed."), findsOneWidget);
    await tester.enterText(fieldFinder("Project"), "Gemini");
    await tester.pump();
    expect(find.text("Apollo is closed."), findsNothing);

    await tester.enterText(fieldFinder("Project"), "Apollo");
    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    // Setup sanity: the send is refused again.
    expect(find.text("Apollo is closed."), findsOneWidget);
    for (final type in <String>["Task", "Risk"]) {
      await tester.ensureVisible(find.text(type).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(type).last);
      await tester.pumpAndSettle();
    }
    expect(find.text("Apollo is closed."), findsNothing);
  });

  testWidgets("FL1 the schedule's refusals show with no Save as the clock "
      "and the store make the schedule fail: the start's message as the "
      "minute passes a new item's start under the lock of earlier today, "
      "and the refusing overlap notice, with no message on the times, as "
      "another write puts an item over the item's times under a policy that "
      "refuses overlaps", (tester) async {
    var clock = at(9, 50);
    final store = storeOf(<CalendarItem>[]);
    addTearDown(store.dispose);
    await openWith(tester, (context) {
      showCreateFlow(
        context,
        store: store,
        range: CalendarCreateRange(start: at(10), end: at(11)),
        policy: const HistoryLockPolicy<ItemPayload>(lockEarlierToday: true),
        now: () {
          return CalendarNow(time: clock, today: wednesday);
        },
        hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
      );
    });
    final past = find.descendant(
      of: timeFieldFinder("Start time"),
      matching: find.text("The start can't be in the past."),
    );
    expect(past, findsNothing);
    clock = at(10, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(past, findsOneWidget);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    final shared = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(shared.dispose);
    await openEdit(
      tester,
      shared,
      policy: const NoOverlapsPolicy<ItemPayload>(),
    );
    final refusing = find.descendant(
      of: find.byKey(scheduleOverlapKey),
      matching: find.text("Can't overlap 1 item"),
    );
    expect(refusing, findsNothing);
    unawaited(shared.create(task("item-2", "Review", at(9, 30), at(10, 30))));
    await tester.pump();
    expect(refusing, findsOneWidget);
    // The notice states the refusal, so no message shows on the times.
    expect(scheduleFieldErrors(tester), <String?>[null, null, null, null]);
  });

  testWidgets("FV1 a failed Save brings its first message, the title's, "
      "down from above the page's view, and gives the title the focus", (
    tester,
  ) async {
    // A view short enough that the page scrolls the field out of it.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800.0, 450.0);
    addTearDown(tester.view.reset);
    final store = storeOf(<CalendarItem>[]);
    addTearDown(store.dispose);
    await openCreate(
      tester,
      store,
      CalendarCreateRange(start: at(9), end: at(10)),
    );
    await tester.tap(find.text("Risk").last);
    await tester.pumpAndSettle();
    final page = pagePosition(tester);
    final view = tester.getRect(formPage());
    page.jumpTo(page.maxScrollExtent);
    await tester.pump();
    // Setup sanity: the title lies above the view, and has no focus.
    expect(
      tester.getRect(fieldFinder("Title")).bottom,
      lessThanOrEqualTo(view.top),
    );
    expect(fieldHasFocus(tester, "Title"), isFalse);

    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: fieldFinder("Title"),
        matching: find.text("Enter a title."),
      ),
      findsOneWidget,
    );
    final title = tester.getRect(fieldFinder("Title"));
    final shown = tester.getRect(formPage());
    expect(title.top, greaterThanOrEqualTo(shown.top));
    expect(title.bottom, lessThanOrEqualTo(shown.bottom));
    expect(fieldHasFocus(tester, "Title"), isTrue);
  });

  testWidgets("FV2 a failed Save brings its first message, Project's, up "
      "from below the page's view, and gives Project the focus", (
    tester,
  ) async {
    // A view short enough that the page scrolls the field out of it.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800.0, 450.0);
    addTearDown(tester.view.reset);
    final store = storeOf(<CalendarItem>[]);
    addTearDown(store.dispose);
    await openCreate(
      tester,
      store,
      CalendarCreateRange(start: at(9), end: at(10)),
    );
    await tester.tap(find.text("Risk").last);
    await tester.pumpAndSettle();
    await tester.enterText(fieldFinder("Title"), "Plan");
    final page = pagePosition(tester);
    page.jumpTo(0.0);
    await tester.pump();
    final view = tester.getRect(formPage());
    // Setup sanity: Project lies below the view, and the title has the
    // focus.
    expect(
      tester.getRect(fieldFinder("Project")).top,
      greaterThanOrEqualTo(view.bottom),
    );
    expect(fieldHasFocus(tester, "Title"), isTrue);

    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    final message = find.descendant(
      of: fieldFinder("Project"),
      matching: find.text("Project is required."),
    );
    expect(message, findsOneWidget);
    expect(tester.getRect(message).bottom, lessThanOrEqualTo(view.bottom));
    expect(fieldHasFocus(tester, "Project"), isTrue);
  });

  testWidgets("FV3 a failed Save brings the first message in the page's "
      "order into view, the overlap notice of a refused overlap before the "
      "title's", (tester) async {
    // A view short enough that the page scrolls the notice out of it.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800.0, 450.0);
    addTearDown(tester.view.reset);
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(
      tester,
      store,
      policy: const NoOverlapsPolicy<ItemPayload>(),
    );
    await tester.enterText(fieldFinder("Title"), "");
    unawaited(store.create(task("item-2", "Review", at(9, 30), at(10, 30))));
    // The notice grows in.
    await tester.pumpAndSettle();
    final page = pagePosition(tester);
    page.jumpTo(page.maxScrollExtent);
    await tester.pump();
    final view = tester.getRect(formPage());
    final notice = find.byKey(scheduleOverlapKey);
    // Setup sanity: the notice refuses the overlap, and lies above the
    // view.
    expect(
      find.descendant(of: notice, matching: find.text("Can't overlap 1 item")),
      findsOneWidget,
    );
    expect(tester.getRect(notice).bottom, lessThanOrEqualTo(view.top));

    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    // Setup sanity: the title's message shows.
    expect(find.text("Enter a title."), findsOneWidget);
    expect(scheduleFieldErrors(tester), <String?>[null, null, null, null]);
    expect(tester.getRect(notice).top, greaterThanOrEqualTo(view.top));
  });

  testWidgets("FV5 a Save whose one problem is an overlap the policy refuses "
      "sends nothing and keeps the form open", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Review", at(9, 30), at(10, 30)),
    ]);
    addTearDown(store.dispose);
    await openEdit(
      tester,
      store,
      policy: const NoOverlapsPolicy<ItemPayload>(),
    );
    await tester.enterText(fieldFinder("Title"), "Rewrite");
    // Setup sanity: the notice refuses the overlap, and no field has a
    // message.
    expect(
      find.descendant(
        of: find.byKey(scheduleOverlapKey),
        matching: find.text("Can't overlap 1 item"),
      ),
      findsOneWidget,
    );
    expect(scheduleFieldErrors(tester), <String?>[null, null, null, null]);

    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    expect(find.text("Edit Task"), findsOneWidget);
    expect(
      store.entriesOn(wednesday).map((shown) {
        return shown.entry.title;
      }),
      <String>["Write", "Review"],
    );
  });

  testWidgets("FV4 a failed Save's reveal moves over the theme's motion, and "
      "at once where the platform asks for no animations", (tester) async {
    final store = storeOf(<CalendarItem>[]);
    addTearDown(store.dispose);
    // Opens a new Risk under the motion theme, titled, its page at its top.
    Future<ScrollPosition> open() async {
      await openWith(tester, (context) {
        showCreateFlow(
          context,
          store: store,
          range: CalendarCreateRange(start: at(9), end: at(10)),
          policy: const UnrestrictedEditPolicy<ItemPayload>(),
          now: wednesdayStart,
          hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
        );
      }, theme: motionTheme);
      await tester.tap(find.text("Risk").last);
      await tester.pumpAndSettle();
      await tester.enterText(fieldFinder("Title"), "Plan");
      final page = pagePosition(tester);
      page.jumpTo(0.0);
      await tester.pump();
      return page;
    }

    var page = await open();
    await tester.tap(saveFinder());
    // The frame that shows the messages, after which the reveal starts,
    // and the frame its motion starts on.
    await tester.pump();
    await tester.pump();
    final start = page.pixels;
    await tester.pump(motionTheme.motionDuration ~/ 2);
    final half = page.pixels;
    await tester.pumpAndSettle();
    final end = page.pixels;
    // Setup sanity: the reveal scrolls.
    expect(end, greaterThan(start));
    expect(half, closeTo((start + end) / 2, 1.0));
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    disableAnimations(tester);
    page = await open();
    await tester.tap(saveFinder());
    await tester.pump();
    expect(page.pixels, end);
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
    expect(panelHeight(tester), 0.0);
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

    // Turned on while the panel still grows, the switch closes the panel at
    // once, its motion running, and its time picker leaves the tree.
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
    expect(panelHeight(tester), 0.0);
    expect(find.byType(CalendarTimePicker), findsNothing);
    for (var elapsed = 16; elapsed <= 480; elapsed += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull, reason: "at $elapsed ms");
      expect(panelHeight(tester), 0.0, reason: "at $elapsed ms");
      expect(
        find.byType(CalendarTimePicker),
        findsNothing,
        reason: "at $elapsed ms",
      );
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

  testWidgets("FW3 the scheduling part's controls reach its edges: All "
      "day's switch, its touch target whole, at the top, its label at the "
      "side, the switch 8 pixels after the label, and at the bottom the End "
      "row's fields, or an all-day item's End date", (tester) async {
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
    final label = tester.getRect(find.text("All day"));
    expect(tester.getRect(allDaySwitch()).top, card.top);
    expect(label.left, card.left);
    expect(tester.getRect(allDaySwitch()).left, label.right + 8.0);
    expect(
      math.max(
        tester.getRect(formDateFinder("End date")).bottom,
        tester.getRect(timeFieldFinder("End time")).bottom,
      ),
      card.bottom,
    );
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store, id: "item-2");
    // Setup sanity: the item is all-day.
    expect(formAllDayOn(), isTrue);
    card = tester.getRect(find.byKey(formSchedulingCardKey));
    expect(tester.getRect(formDateFinder("End date")).bottom, card.bottom);
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
      tester.getRect(find.byType(ScheduleSection)).top,
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
      expect(date.left, card.left, reason: "row $row");
      expect(time.right, card.right, reason: "row $row");
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
      "row of their own across the section", (tester) async {
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
      expect(date.left, section.left);
      expect(date.right, section.right);
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
    // A view short enough that the page scrolls End's row to its top, and
    // tall enough to hold End's field and its open panel.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800.0, 560.0);
    addTearDown(tester.view.reset);
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

  testWidgets("FP3 the Start row keeps its open panel and picker as the All "
      "day switch above it goes, the panel at full height, and as the switch "
      "comes back; and one tap on the field closes it", (tester) async {
    final schedule = CalendarSchedule.of(at(9), at(10), isAllDay: false);
    await pumpSection(tester, checkOf(schedule), theme: motionTheme);
    await openTimePicker(tester, "Start time");
    final before = tester.state(timePickerFinder("Start time"));
    await pumpSection(
      tester,
      checkOf(
        schedule,
        options: const CalendarScheduleOptions(allowsAllDay: false),
      ),
      theme: motionTheme,
    );
    // Setup sanity: the switch goes.
    expect(allDaySwitch(), findsNothing);
    expect(tester.state(timePickerFinder("Start time")), same(before));
    expect(panelHeight(tester), settledPanelHeight(tester));
    final gone = tester.state(timePickerFinder("Start time"));

    await pumpSection(tester, checkOf(schedule), theme: motionTheme);
    // Setup sanity: the switch comes back.
    expect(allDaySwitch(), findsOneWidget);
    expect(tester.state(timePickerFinder("Start time")), same(gone));

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

  testWidgets("FP6 on an ease-out curve the panel closes easing out, as it "
      "opens: a quarter of the way through the motion it has shrunk by the "
      "curve at a quarter, and three quarters through, its picker has "
      "faded by the curve at a half", (tester) async {
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(10), isAllDay: false)),
      theme: easedTheme,
    );
    await openTimePicker(tester, "Start time");
    final full = settledPanelHeight(tester);
    await tester.tap(timeFieldFinder("Start time"));
    await tester.pump();
    // 120 ms after the tap's own frame, a quarter of the theme's 480 ms.
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      panelHeight(tester),
      moreOrLessEquals(full * (1.0 - easeOut.transform(0.25)), epsilon: 1.0),
    );
    expect(panelOpacity(tester), 1.0);
    // Three quarters of the motion: half of the picker's fade.
    await tester.pump(const Duration(milliseconds: 240));
    expect(
      panelOpacity(tester),
      moreOrLessEquals(1.0 - easeOut.transform(0.5), epsilon: 0.01),
    );
  });

  testWidgets("FP7 on an ease-out curve the panel swaps back from its time "
      "picker to its day picker easing out: a quarter of the way through, "
      "its height has moved by the curve at a quarter and the time picker "
      "has faded by the curve at a half; three quarters through, the day "
      "picker has come in by the curve at a half", (tester) async {
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(10), isAllDay: false)),
      theme: easedTheme,
    );
    await openTimePicker(tester, "Start time");
    final timeFull = settledPanelHeight(tester, "Start time");
    await tester.tap(formDateFinder("Start date"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final dayFull = settledDayPanelHeight(tester, "Start date");
    // Setup sanity: the two pickers differ in height.
    expect((dayFull - timeFull).abs(), greaterThan(40.0));
    expect(
      panelHeight(tester, "Start date"),
      moreOrLessEquals(
        timeFull + (dayFull - timeFull) * easeOut.transform(0.25),
        epsilon: 1.0,
      ),
    );
    expect(
      fadeAbove(tester, timePickerFinder("Start time")),
      moreOrLessEquals(1.0 - easeOut.transform(0.5), epsilon: 0.01),
    );
    await tester.pump(const Duration(milliseconds: 240));
    expect(
      fadeAbove(tester, dayPickerFinder("Start date")),
      moreOrLessEquals(easeOut.transform(0.5), epsilon: 0.01),
    );
  });

  testWidgets("FP8 a panel opened past the view's bottom scrolls into view "
      "over the theme's motion once it has opened, not at once", (
    tester,
  ) async {
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
    final start = position.pixels;
    await tester.tap(timeFieldFinder("Start time"));
    await tester.pump();
    // Each frame's scroll offset, through the panel's own 480 ms motion and
    // the reveal's after it.
    final seen = <double>[];
    for (var elapsed = 0; elapsed < 1440; elapsed += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(position.pixels);
    }
    // Setup sanity: the panel is open.
    expect(panelHeight(tester), settledPanelHeight(tester));
    final end = seen.last;
    expect(end, greaterThan(start));
    final between = seen.where((pixels) {
      return pixels > start + 1.0 && pixels < end - 1.0;
    });
    // Most of the theme's 480 ms, frame by frame, lies between the two.
    expect(between.length, greaterThanOrEqualTo(20));
    final picker = tester.getRect(timePickerFinder("Start time"));
    expect(picker.bottom, lessThanOrEqualTo(300.0));
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

  testWidgets("FS1 the sheet's heading writes the schedule's length in a "
      "pill 8 pixels after the title, and the zone in a box at the sheet's "
      "top right, above the page, the title centred on the box, on a new "
      "item and on an edit", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10, 30)),
    ]);
    addTearDown(store.dispose);
    for (final (title, length) in <(String, String)>[
      ("New item", "1h"),
      ("Edit Task", "1h 30m"),
    ]) {
      if (title == "New item") {
        await openCreate(
          tester,
          store,
          CalendarCreateRange(start: at(11), end: at(12)),
        );
      } else {
        await openEdit(tester, store);
      }
      expect(
        tester.widget<Text>(find.byKey(scheduleLengthKey)).data,
        length,
        reason: title,
      );
      final heading = tester.getRect(find.text(title));
      final pill = tester.getRect(lengthPill());
      expect(pill.left, heading.right + 8.0, reason: title);
      final sheet = tester.getRect(sheetFinder());
      final zone = tester.getRect(find.byKey(scheduleZoneKey));
      expect(zone.right, sheet.right - 24.0, reason: title);
      expect(zone.top, sheet.top + 20.0, reason: title);
      expect(
        zone.bottom,
        lessThanOrEqualTo(tester.getRect(formPage()).top),
        reason: title,
      );
      // Setup sanity: the box is taller than the title.
      expect(zone.height, greaterThan(heading.height), reason: title);
      expect(
        heading.center.dy,
        moreOrLessEquals(zone.center.dy),
        reason: title,
      );
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
    }
  });

  testWidgets("FS2 the pill writes a timed schedule's days, hours and "
      "minutes, each that is not none, a day being 24 hours of the wall "
      "clock, and an all-day one's All day for one day or All day and its "
      "count of days in parentheses for more, across a change of the clock "
      "included", (tester) async {
    for (final (schedule, pill) in <(CalendarSchedule, String)>[
      (CalendarSchedule.of(at(9), at(9, 45), isAllDay: false), "45m"),
      (CalendarSchedule.of(at(9), at(10), isAllDay: false), "1h"),
      (CalendarSchedule.of(at(9), at(10, 30), isAllDay: false), "1h 30m"),
      (
        CalendarSchedule.of(DateTime(2026, 4, 21, 22), at(2), isAllDay: false),
        "4h",
      ),
      (
        CalendarSchedule.of(at(9), DateTime(2026, 4, 23, 9), isAllDay: false),
        "1d",
      ),
      (
        CalendarSchedule.of(
          at(9),
          DateTime(2026, 4, 23, 9, 30),
          isAllDay: false,
        ),
        "1d 30m",
      ),
      (
        CalendarSchedule.of(at(9), DateTime(2026, 4, 23, 11), isAllDay: false),
        "1d 2h",
      ),
      (
        CalendarSchedule.of(
          at(9),
          DateTime(2026, 4, 24, 11, 30),
          isAllDay: false,
        ),
        "2d 2h 30m",
      ),
      (
        CalendarSchedule.of(at(9), DateTime(2026, 4, 24, 9), isAllDay: false),
        "2d",
      ),
      // Havana's clock skips its midnight on March 8, and Santiago's repeats
      // an hour on April 4; across each, the same time the next day is one
      // day on.
      for (final day in <DateTime>[DateTime(2026, 3, 7), DateTime(2026, 4, 4)])
        (
          CalendarSchedule.of(
            DateTime(day.year, day.month, day.day, 9),
            DateTime(day.year, day.month, day.day + 1, 9),
            isAllDay: false,
          ),
          "1d",
        ),
      (
        CalendarSchedule.of(wednesday, DateTime(2026, 4, 23), isAllDay: true),
        "All day",
      ),
      (
        CalendarSchedule.of(wednesday, DateTime(2026, 4, 24), isAllDay: true),
        "All day (2 days)",
      ),
      (
        CalendarSchedule.of(wednesday, DateTime(2026, 4, 25), isAllDay: true),
        "All day (3 days)",
      ),
      // Havana's clock skips its midnight on March 8 and repeats an hour on
      // November 1; each is one day of the count.
      (
        CalendarSchedule.of(
          DateTime(2026, 3, 7),
          DateTime(2026, 3, 10),
          isAllDay: true,
        ),
        "All day (3 days)",
      ),
      (
        CalendarSchedule.of(
          DateTime(2026, 10, 31),
          DateTime(2026, 11, 3),
          isAllDay: true,
        ),
        "All day (3 days)",
      ),
    ]) {
      await pumpSection(tester, checkOf(schedule));
      expect(
        tester.widget<Text>(find.byKey(scheduleLengthKey)).data,
        pill,
        reason: "$schedule",
      );
    }
  });

  testWidgets("FS3 the heading's zone box names the zone, its city or "
      "Device time zone, above its offset from UTC at the start, in the "
      "same place for a schedule on one day and one that spans "
      "days", (tester) async {
    final zone = find.byKey(scheduleZoneKey);
    Rect zoneOnSheet() {
      return tester.getRect(zone).shift(-tester.getRect(sheetFinder()).topLeft);
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
    final oneDay = zoneOnSheet();
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, local, id: "item-2");
    // Setup sanity: the schedule spans days.
    expect(formSchedule(tester), "Wed, Apr 22, 22:00\nThu, Apr 23, 02:00\n4h");
    expect(zoneOnSheet(), oneDay);
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
      expect(zoneOnSheet().topRight, oneDay.topRight);
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
    }
  });

  testWidgets("FS4 the heading shows the zone in a light grey rounded box, "
      "padded around its name and offset, and the length in a pill, in "
      "14 px text after a timer icon, or for an all-day schedule All day", (
    tester,
  ) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10, 30)),
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
    final zoneBox = find.byKey(scheduleZoneKey);
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
    final length = find.byKey(scheduleLengthKey);
    expect(tester.widget<Text>(length).data, "1h 30m");
    expect(tester.widget<Text>(length).style?.fontSize, 14.0);
    expect(
      tester.widget<DecoratedBox>(lengthPill()).decoration,
      isA<ShapeDecoration>().having(
        (decoration) {
          return decoration.shape;
        },
        "shape",
        isA<StadiumBorder>(),
      ),
    );
    final icon = find.descendant(
      of: lengthPill(),
      matching: find.byIcon(Icons.timer_outlined),
    );
    expect(icon, findsOneWidget);
    expect(
      tester.getRect(icon).right,
      lessThanOrEqualTo(tester.getRect(length).left),
    );
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store, id: "item-3");
    // Setup sanity: the schedule is all-day.
    expect(formAllDayOn(), isTrue);
    expect(tester.widget<Text>(length).data, "All day");
  });

  testWidgets("FS5 the overlap notice and its Next free time lie on the "
      "page between the scheduling part and the item's part, 12 pixels "
      "from each", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Standup", at(9, 30), at(10, 30)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    final notice = tester.getRect(find.byKey(scheduleOverlapKey));
    final scheduling = tester.getRect(find.byKey(formSchedulingCardKey));
    expect(notice.top, scheduling.bottom + 12.0);
    expect(notice.left, scheduling.left);
    expect(notice.right, scheduling.right);
    expect(
      tester.getRect(find.byKey(formItemCardKey)).top,
      notice.bottom + 12.0,
    );
    final next = find.text("Next free time");
    expect(next, findsOneWidget);
    expect(notice.expandToInclude(tester.getRect(next)), notice);
  });

  testWidgets("FS6 a heading whose title and pill do not fit on one line "
      "before the zone box wraps the title and keeps the pill's width 8 "
      "pixels after it, centred on the title, one that holds them exactly "
      "keeps the title on one line, and one that cannot hold the pill "
      "shrinks the pill to fit, overflowing nothing", (tester) async {
    final check = checkOf(
      CalendarSchedule.of(at(9), at(10, 30), isAllDay: false),
    );
    Future<void> pumpHeading(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: ScheduleHeading(title: "Edit Request", check: check),
              ),
            ),
          ),
        ),
      );
    }

    final title = find.text("Edit Request");
    await pumpHeading(780.0);
    final oneLine = tester.getSize(title);
    final pillSize = tester.getRect(lengthPill()).size;
    final zoneWidth = tester.getSize(find.byKey(scheduleZoneKey)).width;
    // The room the title and the pill share before the zone box.
    double widthFor(double room) {
      return room + 12.0 + zoneWidth;
    }

    await pumpHeading(widthFor(oneLine.width + 8.0 + pillSize.width));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(title).height, oneLine.height);
    expect(tester.getRect(lengthPill()).size, pillSize);

    await pumpHeading(widthFor(oneLine.width / 2.0 + 8.0 + pillSize.width));
    expect(tester.takeException(), isNull);
    final wrapped = tester.getRect(title);
    expect(wrapped.height, greaterThanOrEqualTo(2.0 * oneLine.height));
    final pill = tester.getRect(lengthPill());
    expect(pill.size, pillSize);
    expect(pill.left, wrapped.right + 8.0);
    expect(pill.center.dy, moreOrLessEquals(wrapped.center.dy));

    final narrow = pillSize.width / 2.0;
    await pumpHeading(widthFor(narrow));
    expect(tester.takeException(), isNull);
    final shrunk = tester.getRect(lengthPill());
    expect(shrunk.width, lessThanOrEqualTo(narrow - 8.0));
    expect(
      shrunk.right,
      lessThanOrEqualTo(tester.getRect(find.byKey(scheduleZoneKey)).left),
    );
  });

  testWidgets("FS7 the overlap notice counts the overlaps and names the "
      "next free time, over a card per overlapped item in the order of their "
      "starts: its type's icon and its title across the card, its times "
      "under the title, and the time it shares with the item", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Standup", at(9, 30), at(10, 30)),
      calendarItem(
        id: "item-3",
        type: CalendarItemType.risk,
        title: "Review",
        start: at(8, 30),
        end: at(11),
        fields: const <String, Object?>{
          "severity": "high",
          "project": "Apollo",
          "mitigated": false,
        },
      ),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    final notice = find.byKey(scheduleOverlapKey);
    expect(
      find.descendant(of: notice, matching: find.text("Overlaps 2 items")),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: notice,
        matching: find.text("Next free: 11:00-12:00"),
      ),
      findsOneWidget,
    );
    expect(overlapCardTexts(tester, "item-3"), <String>[
      "Review",
      "08:30-11:00",
      "Covers all of this item",
    ]);
    expect(overlapCardTexts(tester, "item-2"), <String>[
      "Standup",
      "09:30-10:30",
      "Shares 09:30-10:00, 30m",
    ]);
    final review = find.byKey(scheduleOverlapCardKey("item-3"));
    final standup = find.byKey(scheduleOverlapCardKey("item-2"));
    expect(
      tester.getRect(review).bottom,
      lessThanOrEqualTo(tester.getRect(standup).top),
    );
    // The times lie under the title, and the title takes the row after the
    // icon to the card's padding, where the line of the times ends too.
    Rect inStandup(String text) {
      return tester.getRect(
        find.descendant(of: standup, matching: find.text(text)),
      );
    }

    final title = inStandup("Standup");
    final times = inStandup("09:30-10:30");
    expect(times.top, greaterThanOrEqualTo(title.bottom));
    expect(times.left, title.left);
    expect(title.right, times.right);
    expect(
      find.descendant(of: review, matching: find.byIcon(Icons.warning_amber)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: standup, matching: find.byIcon(Icons.task_alt)),
      findsOneWidget,
    );
  });

  testWidgets("FS8 the overlap notice's warning icon lies at its top left, "
      "before its heading and level with the heading's top", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Standup", at(9, 30), at(10, 30)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    final notice = find.byKey(scheduleOverlapKey);
    final icon = tester.getRect(
      find.descendant(of: notice, matching: find.byIcon(Icons.warning_amber)),
    );
    final heading = tester.getRect(
      find.descendant(of: notice, matching: find.text("Overlaps 1 item")),
    );
    final card = tester.getRect(find.byKey(scheduleOverlapCardKey("item-2")));
    expect(icon.top, heading.top);
    expect(icon.right, lessThanOrEqualTo(heading.left));
    expect(icon.bottom, lessThanOrEqualTo(card.top));
    expect(icon.left, lessThan(card.left + 1.0));
  });

  testWidgets("FS9 a card's bar zooms on the shared time: its axis runs "
      "from that time's length before it to that length after it, within "
      "the two items' times, under a lane for the item and one for the "
      "overlapped item in that item's colour, each lane rounded at both "
      "ends, as the track is, also where its item runs on past the axis, "
      "over a tinted column of the shared time, the axis's first and last "
      "times under its ends", (tester) async {
    final standup = task("item-3", "Standup", at(9, 30), at(10, 30));
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Early", at(8), at(9, 15)),
      standup,
      task("item-4", "Review", at(8, 30), at(11)),
      task("item-5", "Workshop", at(12), at(17)),
      task("item-6", "Call", at(13), at(13, 15)),
      task("item-7", "Close", at(16, 45), at(17)),
    ]);
    addTearDown(store.dispose);
    (double, double) spanOf(
      String id,
      ValueKey<String> Function(String id) key,
    ) {
      return overlapSpan(tester, id, key);
    }

    await openEdit(tester, store);
    // Write from 09:00 to 10:00 shares 09:00 to 09:15 with Early, from
    // 08:00: the axis runs from 08:45 to 09:30.
    expect(spanOf("item-2", scheduleOverlapShareKey), (0.333, 0.667));
    expect(spanOf("item-2", scheduleOverlapThisLaneKey), (0.333, 1.0));
    expect(spanOf("item-2", scheduleOverlapOtherLaneKey), (0.0, 0.667));
    expect(overlapBarTexts(tester, "item-2"), <String>[
      "This",
      "Other",
      "08:45",
      "09:30",
    ]);
    // It shares 09:30 to 10:00 with Standup, to 10:30.
    expect(spanOf("item-3", scheduleOverlapShareKey), (0.333, 0.667));
    expect(spanOf("item-3", scheduleOverlapThisLaneKey), (0.0, 0.667));
    expect(spanOf("item-3", scheduleOverlapOtherLaneKey), (0.333, 1.0));
    expect(overlapBarTexts(tester, "item-3").sublist(2), <String>[
      "09:00",
      "10:30",
    ]);
    // Review, from 08:30 to 11:00, covers it: the axis runs from 08:30,
    // the two items' first time, to 11:00.
    expect(spanOf("item-4", scheduleOverlapShareKey), (0.2, 0.6));
    expect(spanOf("item-4", scheduleOverlapThisLaneKey), (0.2, 0.6));
    expect(spanOf("item-4", scheduleOverlapOtherLaneKey), (0.0, 1.0));
    expect(overlapBarTexts(tester, "item-4").sublist(2), <String>[
      "08:30",
      "11:00",
    ]);

    // Write's lane runs on past the axis's end, and Early's past its start.
    const pill = BorderRadius.all(Radius.circular(3.0));
    expect(
      decorationRadius(
        tester,
        find.byKey(scheduleOverlapThisLaneKey("item-2")),
      ),
      pill,
    );
    expect(
      decorationRadius(
        tester,
        find.byKey(scheduleOverlapOtherLaneKey("item-2")),
      ),
      pill,
    );
    expect(
      decorationColor(
        tester,
        find.byKey(scheduleOverlapOtherLaneKey("item-3")),
      ),
      standup.color,
    );
    expect(
      decorationColor(tester, find.byKey(scheduleOverlapShareKey("item-3"))),
      HarborColors.notice,
    );
    final card = tester.getRect(find.byKey(scheduleOverlapCardKey("item-3")));
    final axis = tester.getRect(find.byKey(scheduleOverlapAxisKey("item-3")));
    expect(card.expandToInclude(axis), card);
    expect(axis.width, greaterThan(card.width / 2.0));
    // The item's lane lies beside "This", above the other's, beside
    // "Other".
    Rect labelOf(String text) {
      return tester.getRect(
        find.descendant(
          of: find.byKey(scheduleOverlapBarKey("item-3")),
          matching: find.text(text),
        ),
      );
    }

    final mine = tester.getRect(
      find.byKey(scheduleOverlapThisLaneKey("item-3")),
    );
    final theirs = tester.getRect(
      find.byKey(scheduleOverlapOtherLaneKey("item-3")),
    );
    expect(mine.bottom, lessThan(theirs.top));
    expect(mine.center.dy, moreOrLessEquals(labelOf("This").center.dy));
    expect(theirs.center.dy, moreOrLessEquals(labelOf("Other").center.dy));
    expect(labelOf("This").right, lessThanOrEqualTo(axis.left));
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    // Workshop, from 12:00 to 17:00, shares 13:00 to 13:15 with Call: the
    // axis runs from 12:45 to 13:30, and Workshop's lane runs on past both
    // its ends.
    await openEdit(tester, store, id: "item-5");
    expect(spanOf("item-6", scheduleOverlapShareKey), (0.333, 0.667));
    expect(spanOf("item-6", scheduleOverlapThisLaneKey), (0.0, 1.0));
    expect(spanOf("item-6", scheduleOverlapOtherLaneKey), (0.333, 0.667));
    expect(
      decorationRadius(
        tester,
        find.byKey(scheduleOverlapThisLaneKey("item-6")),
      ),
      pill,
    );
    expect(overlapBarTexts(tester, "item-6").sublist(2), <String>[
      "12:45",
      "13:30",
    ]);
    // It shares 16:45 to 17:00 with Close: the axis runs from 16:30 to
    // 17:00, where both items end.
    expect(spanOf("item-7", scheduleOverlapShareKey), (0.5, 1.0));
    expect(spanOf("item-7", scheduleOverlapThisLaneKey), (0.0, 1.0));
    expect(spanOf("item-7", scheduleOverlapOtherLaneKey), (0.5, 1.0));
    expect(
      decorationRadius(
        tester,
        find.byKey(scheduleOverlapThisLaneKey("item-7")),
      ),
      pill,
    );
    expect(overlapBarTexts(tester, "item-7").sublist(2), <String>[
      "16:30",
      "17:00",
    ]);
  });

  testWidgets("FS10 the overlap notice shows three cards and a button that "
      "shows the rest, which then shows fewer again", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      for (var index = 0; index < 5; index++)
        task(
          "item-${index + 2}",
          "Meeting $index",
          at(9, 10 * index),
          at(10, 10 * index),
        ),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    final notice = find.byKey(scheduleOverlapKey);
    List<bool> shown() {
      return <bool>[
        for (var index = 2; index <= 6; index++)
          find
              .byKey(scheduleOverlapCardKey("item-$index"))
              .evaluate()
              .isNotEmpty,
      ];
    }

    Future<void> tapInNotice(String label) async {
      final button = find.descendant(of: notice, matching: find.text(label));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    expect(
      find.descendant(of: notice, matching: find.text("Overlaps 5 items")),
      findsOneWidget,
    );
    expect(shown(), <bool>[true, true, true, false, false]);
    await tapInNotice("Show 2 more");
    expect(shown(), <bool>[true, true, true, true, true]);
    await tapInNotice("Show fewer");
    expect(shown(), <bool>[true, true, true, false, false]);
  });

  testWidgets("FS11 the overlap notice turns red where the policy refuses an "
      "overlap, saying how many it refuses, and draws each refused card's "
      "chip and bar's shared column red, with no label of its own; each "
      "card's outline is its item's colour, refused or not", (tester) async {
    final standup = task("item-2", "Standup", at(9, 30), at(10, 30));
    final review = calendarItem(
      id: "item-3",
      type: CalendarItemType.risk,
      title: "Review",
      start: at(8, 30),
      end: at(11),
    );
    // Setup sanity: the two items differ in colour.
    expect(review.color, isNot(standup.color));
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      standup,
      review,
    ]);
    addTearDown(store.dispose);
    final notice = find.byKey(scheduleOverlapKey);
    Finder inNotice(String text) {
      return find.descendant(of: notice, matching: find.text(text));
    }

    final allowed = <(Color?, Color?)>[
      (HarborColors.notice, standup.color),
      (HarborColors.notice, review.color),
    ];
    List<(Color?, Color?)> marked() {
      return <(Color?, Color?)>[
        for (final id in <String>["item-2", "item-3"])
          overlapCardColors(tester, id),
      ];
    }

    await openEdit(tester, store);
    expect(inNotice("Overlaps 2 items"), findsOneWidget);
    expect(decorationColor(tester, notice), HarborColors.notice);
    expect(marked(), allowed);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(tester, store, policy: const _RefusesOverlapWith("item-3"));
    expect(inNotice("Overlaps 2 items, 1 not allowed"), findsOneWidget);
    expect(decorationColor(tester, notice), HarborColors.errorNotice);
    expect(marked(), <(Color?, Color?)>[
      (HarborColors.notice, standup.color),
      (HarborColors.errorNotice, review.color),
    ]);
    expect(overlapCardTexts(tester, "item-3"), <String>[
      "Review",
      "08:30-11:00",
      "Covers all of this item",
    ]);
    expect(
      <Color?>[
        for (final id in <String>["item-2", "item-3"])
          decorationColor(tester, find.byKey(scheduleOverlapShareKey(id))),
      ],
      <Color?>[HarborColors.notice, HarborColors.errorNotice],
    );
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await openEdit(
      tester,
      store,
      policy: const NoOverlapsPolicy<ItemPayload>(),
    );
    expect(inNotice("Can't overlap 2 items"), findsOneWidget);
    expect(decorationColor(tester, notice), HarborColors.errorNotice);
    expect(marked(), <(Color?, Color?)>[
      (HarborColors.errorNotice, standup.color),
      (HarborColors.errorNotice, review.color),
    ]);
  });

  testWidgets("FS12 a card writes the weekday at each end of an item that "
      "runs past the item's day, and an end at the next midnight as 24:00 "
      "of the day; its bar writes the weekday of an end of its axis on "
      "another day, and an axis's end at the next midnight as 24:00", (
    tester,
  ) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task("item-2", "Overnight", DateTime(2026, 4, 21, 22), at(9, 30)),
      task("item-3", "Late", at(9, 45), DateTime(2026, 4, 23)),
      task("item-4", "Shift", at(9, 50), DateTime(2026, 4, 23, 1)),
      task("item-5", "Deploy", at(23), DateTime(2026, 4, 23)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    expect(overlapCardTexts(tester, "item-2"), <String>[
      "Overnight",
      "Tue 22:00-Wed 09:30",
      "Shares 09:00-09:30, 30m",
    ]);
    expect(overlapCardTexts(tester, "item-3"), <String>[
      "Late",
      "09:45-24:00",
      "Shares 09:45-10:00, 15m",
    ]);
    expect(overlapCardTexts(tester, "item-4"), <String>[
      "Shift",
      "Wed 09:50-Thu 01:00",
      "Shares 09:50-10:00, 10m",
    ]);
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    // Deploy, from 23:00 to 24:00, shares all of it with Late, to 24:00:
    // the axis runs from 22:00 to 24:00, where both items end.
    await openEdit(tester, store, id: "item-5");
    expect(overlapCardTexts(tester, "item-3"), <String>[
      "Late",
      "09:45-24:00",
      "Covers all of this item",
    ]);
    expect(overlapBarTexts(tester, "item-3").sublist(2), <String>[
      "22:00",
      "24:00",
    ]);
    // Shift covers Deploy and ends at Thursday's 01:00, the axis's end.
    expect(overlapCardTexts(tester, "item-4"), <String>[
      "Shift",
      "Wed 09:50-Thu 01:00",
      "Covers all of this item",
    ]);
    expect(overlapBarTexts(tester, "item-4").sublist(2), <String>[
      "22:00",
      "Thu 01:00",
    ]);
  });

  /// The store of FS10: Write, from 09:00 to 10:00, which overlaps the five
  /// meetings item-2 to item-6, each an hour from ten minutes after the
  /// one before.
  MemoryCalendarStore<ItemPayload> meetingsStore() {
    return storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      for (var index = 0; index < 5; index++)
        task(
          "item-${index + 2}",
          "Meeting $index",
          at(9, 10 * index),
          at(10, 10 * index),
        ),
    ]);
  }

  /// Brings the button of the overlap notice that reads [label] into view.
  Future<Finder> revealNoticeButton(WidgetTester tester, String label) async {
    final button = find.descendant(
      of: find.byKey(scheduleOverlapKey),
      matching: find.text(label),
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    return button;
  }

  /// Whether the cards of the meetings item-2 to item-6 are built.
  List<bool> meetingCards() {
    return <bool>[
      for (var index = 2; index <= 6; index++)
        find.byKey(scheduleOverlapCardKey("item-$index")).evaluate().isNotEmpty,
    ];
  }

  testWidgets("FS13 Show more grows the cards it shows in, and Show fewer "
      "shrinks those it hides out, over the theme's motion", (tester) async {
    final store = meetingsStore();
    addTearDown(store.dispose);
    await openEdit(tester, store, theme: motionTheme);
    final notice = find.byKey(scheduleOverlapKey);
    final fewer = tester.getSize(notice).height;

    await tester.tap(await revealNoticeButton(tester, "Show 2 more"));
    await tester.pump();
    // A row's first tick in or out moves it by nothing, so the motion
    // runs from the frame after the tap's.
    await tester.pump();
    await tester.pump(motionTheme.motionDuration ~/ 2);
    final growing = tester.getSize(notice).height;
    await tester.pumpAndSettle();
    final all = tester.getSize(notice).height;
    // Setup sanity: the two cards make the notice taller.
    expect(all, greaterThan(fewer + 100.0));
    // Half way through the motion on a linear curve, half grown.
    expect(growing, moreOrLessEquals((fewer + all) / 2, epsilon: 0.01));

    await tester.tap(await revealNoticeButton(tester, "Show fewer"));
    await tester.pump();
    await tester.pump();
    await tester.pump(motionTheme.motionDuration ~/ 2);
    // The cards it hides stay while they shrink.
    expect(meetingCards(), <bool>[true, true, true, true, true]);
    expect(
      tester.getSize(notice).height,
      moreOrLessEquals((fewer + all) / 2, epsilon: 0.01),
    );
    await tester.pumpAndSettle();
  });

  testWidgets("FS14 as the schedule changes, a card that comes to overlap "
      "grows in and one that stops shrinks out over the theme's motion, "
      "writing the time it shared until it has gone", (tester) async {
    final others = <CalendarItem>[
      task("item-2", "Plan", at(8), at(12)),
      task("item-3", "Early", at(9), at(9, 30)),
      task("item-4", "Late", at(10, 30), at(11)),
    ];
    final notice = find.byKey(scheduleOverlapKey);
    Future<void> pumpFrom(int startHour, int endHour) async {
      await pumpSection(
        tester,
        checkOf(
          CalendarSchedule.of(at(startHour), at(endHour), isAllDay: false),
          others: others,
        ),
        theme: motionTheme,
      );
      // A row's first tick in or out moves it by nothing.
      await tester.pump();
    }

    await pumpFrom(9, 10);
    await tester.pumpAndSettle();
    final early = overlapCardTexts(tester, "item-3");
    // Setup sanity: Early shares its half hour with 09:00 to 10:00, and
    // Late shares nothing with it.
    expect(early, <String>["Early", "09:00-09:30", "Shares 09:00-09:30, 30m"]);
    expect(find.byKey(scheduleOverlapCardKey("item-4")), findsNothing);
    final two = tester.getSize(notice).height;

    // From 09:00 to 11:00 overlaps Late too.
    await pumpFrom(9, 11);
    await tester.pump(motionTheme.motionDuration ~/ 2);
    final growing = tester.getSize(notice).height;
    await tester.pumpAndSettle();
    final three = tester.getSize(notice).height;
    // Setup sanity: Late's card makes the notice taller.
    expect(three, greaterThan(two + 50.0));
    expect(growing, moreOrLessEquals((two + three) / 2, epsilon: 0.01));

    // From 10:00 to 11:00 no longer overlaps Early.
    await pumpFrom(10, 11);
    await tester.pump(motionTheme.motionDuration ~/ 2);
    expect(overlapCardTexts(tester, "item-3"), early);
    final shrinking = tester.getSize(notice).height;
    await tester.pumpAndSettle();
    expect(
      shrinking,
      moreOrLessEquals(
        (three + tester.getSize(notice).height) / 2,
        epsilon: 0.01,
      ),
    );
  });

  testWidgets("FS15 a card whose item comes to start after another's slides "
      "to its place over the theme's motion", (tester) async {
    Future<void> pumpWith(DateTime firstStart) {
      return pumpSection(
        tester,
        checkOf(
          CalendarSchedule.of(at(9), at(10), isAllDay: false),
          others: <CalendarItem>[
            task("item-2", "First", firstStart, at(9, 55)),
            task("item-3", "Second", at(9, 15), at(9, 45)),
          ],
        ),
        theme: motionTheme,
      );
    }

    final first = find.byKey(scheduleOverlapCardKey("item-2"));
    await pumpWith(at(9));
    await tester.pumpAndSettle();
    final from = tester.getTopLeft(first).dy;

    await pumpWith(at(9, 30));
    await tester.pump(motionTheme.motionDuration ~/ 2);
    final sliding = tester.getTopLeft(first).dy;
    await tester.pumpAndSettle();
    final to = tester.getTopLeft(first).dy;
    // Setup sanity: First now lies under Second.
    expect(to, greaterThan(from + 50.0));
    expect(sliding, moreOrLessEquals((from + to) / 2, epsilon: 0.01));
  });

  testWidgets("FS16 where the platform asks for no animations, Show more and "
      "Show fewer show and hide their cards in the tap's frame", (
    tester,
  ) async {
    disableAnimations(tester);
    final store = meetingsStore();
    addTearDown(store.dispose);
    await openEdit(tester, store, theme: motionTheme);
    final notice = find.byKey(scheduleOverlapKey);
    final fewer = tester.getSize(notice).height;

    await tester.tap(await revealNoticeButton(tester, "Show 2 more"));
    await tester.pump();
    final shown = tester.getSize(notice).height;
    await tester.pumpAndSettle();
    expect(tester.getSize(notice).height, shown);
    // Setup sanity: the two cards make the notice taller.
    expect(shown, greaterThan(fewer + 100.0));

    await tester.tap(await revealNoticeButton(tester, "Show fewer"));
    await tester.pump();
    expect(meetingCards(), <bool>[true, true, true, false, false]);
  });

  /// Write, from 09:00 to 10:00, the item the reveal tests open.
  CalendarItem write() {
    return task("item-1", "Write", at(9), at(10));
  }

  /// Standup, from 09:30 to 10:30, which Write overlaps.
  CalendarItem standup() {
    return task("item-2", "Standup", at(9, 30), at(10, 30));
  }

  /// The room between the form's scheduling card and its item card.
  double betweenCards(WidgetTester tester) {
    return tester.getTopLeft(find.byKey(formItemCardKey)).dy -
        tester.getBottomLeft(find.byKey(formSchedulingCardKey)).dy;
  }

  /// The alphas the overlap notice's box draws its fill and its outline at,
  /// each opaque at rest.
  List<double> noticeBoxAlphas(WidgetTester tester) {
    final box =
        tester.widget<DecoratedBox>(find.byKey(scheduleOverlapKey)).decoration
            as BoxDecoration;
    return <double>[box.color!.a, (box.border! as Border).top.color.a];
  }

  testWidgets("FS17 the notice and the gap above it grow in over the theme's "
      "motion as the store comes to hold an entry the schedule overlaps, the "
      "notice's box fading in over the motion's first half and what it holds "
      "from a fifth in to seven tenths, and shrink out as the entry goes, "
      "the notice still showing it and taking no pointer, what it holds "
      "fading out first and then its box", (tester) async {
    final store = storeOf(<CalendarItem>[write()]);
    addTearDown(store.dispose);
    await openEdit(tester, store, theme: motionTheme);
    final notice = find.byKey(scheduleOverlapKey);
    final heading = find.descendant(
      of: notice,
      matching: find.text("Overlaps 1 item"),
    );
    final motion = motionTheme.motionDuration;
    // Setup sanity: nothing overlaps Write, so no notice shows.
    expect(notice, findsNothing);
    final apart = betweenCards(tester);

    store.entries = <CalendarItem>[write(), standup()];
    await tester.pump();
    await tester.pump(motion * 0.15);
    expect(noticeBoxAlphas(tester), everyElement(moreOrLessEquals(0.3)));
    expect(fadeAbove(tester, heading), 0.0);
    await tester.pump(motion * 0.35);
    expect(noticeBoxAlphas(tester), <double>[1.0, 1.0]);
    expect(fadeAbove(tester, heading), moreOrLessEquals(0.6));
    final growing = betweenCards(tester);
    await tester.pumpAndSettle();
    final open = betweenCards(tester);
    // The gap lies above the notice.
    expect(open, apart + 12.0 + tester.getSize(notice).height);
    expect(growing, moreOrLessEquals((apart + open) / 2, epsilon: 0.01));
    expect(heading.hitTestable(), findsOneWidget);

    store.entries = <CalendarItem>[write()];
    await tester.pump();
    await tester.pump(motion * 0.5);
    expect(heading, findsOneWidget);
    expect(heading.hitTestable(), findsNothing);
    expect(
      betweenCards(tester),
      moreOrLessEquals((apart + open) / 2, epsilon: 0.01),
    );
    expect(noticeBoxAlphas(tester), <double>[1.0, 1.0]);
    expect(fadeAbove(tester, heading), moreOrLessEquals(0.6));
    await tester.pump(motion * 0.4);
    expect(fadeAbove(tester, heading), 0.0);
    expect(noticeBoxAlphas(tester), everyElement(moreOrLessEquals(0.2)));
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
  });

  testWidgets("FS18 a notice shrinking out that the schedule comes to "
      "overlap again grows back from where it is, keeping its cards as they "
      "were", (tester) async {
    final others = <CalendarItem>[
      for (var index = 0; index < 5; index++)
        task(
          "item-${index + 2}",
          "Meeting $index",
          at(9, 10 * index),
          at(10, 10 * index),
        ),
    ];
    Future<void> pumpOver(List<CalendarItem> others) {
      return pumpSection(
        tester,
        checkOf(
          CalendarSchedule.of(at(9), at(10), isAllDay: false),
          others: others,
        ),
        theme: motionTheme,
      );
    }

    final notice = find.byKey(scheduleOverlapKey);
    await pumpOver(others);
    await tester.tap(await revealNoticeButton(tester, "Show 2 more"));
    await tester.pumpAndSettle();
    final open = tester.getSize(find.byType(ScheduleOverlapNotice)).height;

    await pumpOver(const <CalendarItem>[]);
    await tester.pump(motionTheme.motionDuration ~/ 2);
    final half = tester.getSize(find.byType(ScheduleOverlapNotice)).height;
    // Setup sanity: half way out, the notice is about half its height.
    expect(half, moreOrLessEquals(open / 2, epsilon: 0.01));

    await pumpOver(others);
    expect(
      find.descendant(of: notice, matching: find.text("Show fewer")),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(ScheduleOverlapNotice)).height,
      moreOrLessEquals(half, epsilon: 0.01),
    );
    await tester.pump(motionTheme.motionDuration ~/ 4);
    expect(
      tester.getSize(find.byType(ScheduleOverlapNotice)).height,
      moreOrLessEquals(open * 3 / 4, epsilon: 0.01),
    );
    await tester.pumpAndSettle();
  });

  testWidgets("FS19 where the platform asks for no animations, the notice "
      "shows and goes in one frame", (tester) async {
    disableAnimations(tester);
    final store = storeOf(<CalendarItem>[write()]);
    addTearDown(store.dispose);
    await openEdit(tester, store, theme: motionTheme);
    final notice = find.byKey(scheduleOverlapKey);
    final apart = betweenCards(tester);

    store.entries = <CalendarItem>[write(), standup()];
    await tester.pump();
    final shown = betweenCards(tester);
    await tester.pumpAndSettle();
    expect(betweenCards(tester), shown);
    // Setup sanity: the notice shows, and pushes the item card down.
    expect(shown, greaterThan(apart + 100.0));

    store.entries = <CalendarItem>[write()];
    await tester.pump();
    expect(notice, findsNothing);
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
        under(find.byType(CalendarDayPicker<ItemPayload>)),
        findsOneWidget,
        reason: label,
      );
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
  });

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
    expect(formSchedule(tester), "Fri, Apr 24, 09:00\nFri, Apr 24, 10:00\n1h");
    expect(formDateShows("Start date", "2026-04-24"), findsOneWidget);
    expect(formDateShows("End date", "2026-04-24"), findsOneWidget);
    expect(dayPickerFinder("Start date"), findsOneWidget);
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
    expect(
      formSchedule(tester),
      "Fri, Apr 24, 09:00\nSat, Apr 25, 10:00\n1d 1h",
    );
  });

  testWidgets("IP3 Start date's panel grows and fades in over the theme's "
      "motion as the field opens it, and where the platform asks for no "
      "animations is open in the tap's own frame", (tester) async {
    final check = checkOf(CalendarSchedule.of(at(9), at(10), isAllDay: false));
    await pumpSection(tester, check, theme: motionTheme);
    await tester.tap(formDateFinder("Start date"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final full = settledDayPanelHeight(tester, "Start date");
    expect(panelHeight(tester, "Start date"), greaterThan(0.0));
    expect(panelHeight(tester, "Start date"), lessThan(full));
    expect(panelOpacity(tester, "Start date"), lessThan(1.0));
    await tester.pump(const Duration(milliseconds: 480));
    expect(panelHeight(tester, "Start date"), full);
    expect(panelOpacity(tester, "Start date"), 1.0);

    await tester.tap(formDateFinder("Start date"));
    await tester.pumpAndSettle();
    // Setup sanity: the panel has closed.
    expect(panelHeight(tester, "Start date"), 0.0);
    disableAnimations(tester);
    await tester.pump();
    await tester.tap(formDateFinder("Start date"));
    await tester.pump();
    expect(
      panelHeight(tester, "Start date"),
      settledDayPanelHeight(tester, "Start date"),
    );
    expect(panelOpacity(tester, "Start date"), 1.0);
  });

  testWidgets("IP4 a tap on Start date while Start time's picker is open "
      "swaps the panel's pickers in place over the theme's motion, rebuilding "
      "under the panel only the time picker's focus scopes, once, in the "
      "frame after the tap's; a tap on End date then closes it, and its day "
      "picker takes no tap as it shrinks", (tester) async {
    final reports = <CalendarSchedule>[];
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(10), isAllDay: false)),
      onChanged: reports.add,
      follows: true,
      theme: motionTheme,
    );
    await openTimePicker(tester, "Start time");
    final timeFull = settledPanelHeight(tester, "Start time");
    // Setup sanity: the panel rests at the time picker's height.
    expect(panelHeight(tester, "Start date"), timeFull);

    await tester.tap(formDateFinder("Start date"));
    await tester.pump();
    // Each element rebuilt at or under the Start panel, with the frame after
    // the tap's own it rebuilt in, counted from 1, and whether it lies under
    // the CalendarTimePicker.
    final rebuilt = <({int frame, Element element, bool underTimePicker})>[];
    var frame = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      var underPanel = element.widget.key == scheduleStartPanelKey;
      var underTimePicker = false;
      element.visitAncestorElements((ancestor) {
        underTimePicker =
            underTimePicker || ancestor.widget is CalendarTimePicker;
        underPanel = underPanel || ancestor.widget.key == scheduleStartPanelKey;
        return !underPanel;
      });
      if (underPanel) {
        rebuilt.add((
          frame: frame,
          element: element,
          underTimePicker: underTimePicker,
        ));
      }
    };
    try {
      for (var elapsed = 20; elapsed < 480; elapsed += 20) {
        frame++;
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          panelHeight(tester, "Start date"),
          greaterThan(0.0),
          reason: "at $elapsed ms",
        );
        if (elapsed == 120) {
          // A quarter of the theme's linear 480 ms, from the time picker's
          // height toward the day picker's.
          final dayFull = settledDayPanelHeight(tester, "Start date");
          expect(
            panelHeight(tester, "Start date"),
            moreOrLessEquals(timeFull + (dayFull - timeFull) / 4, epsilon: 1.0),
          );
        }
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    // The tap's frame gives the time picker a null onChanged, which flips the
    // skipTraversal of its Focus nodes; FocusManager notifies those nodes in
    // a microtask after that frame, so their scopes rebuild in the next one.
    expect([
      for (final r in rebuilt)
        if (r.frame == 1 && !r.underTimePicker) r.element,
    ], isEmpty);
    expect([
      for (final r in rebuilt)
        if (r.frame > 1) r.element,
    ], isEmpty);
    await tester.pumpAndSettle();
    expect(panelHeight(tester, "Start date"), greaterThan(0.0));
    expect(dayPickerFinder("Start date"), findsOneWidget);
    expect(
      find.descendant(
        of: pickerPanel("Start date"),
        matching: find.byType(CalendarTimePicker),
      ),
      findsNothing,
    );
    expect(
      panelHeight(tester, "Start date"),
      settledDayPanelHeight(tester, "Start date"),
    );

    await tester.ensureVisible(formDateFinder("End date"));
    await tester.pumpAndSettle();
    reports.clear();
    await tester.tap(formDateFinder("End date"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final friday = find.descendant(
      of: dayPickerFinder("Start date"),
      matching: find.byKey(weekStripDayKey(DateTime(2026, 4, 24))),
    );
    // Setup sanity: the Start panel shrinks with Friday in reach.
    expect(friday.hitTestable(), findsOneWidget);
    await tester.tap(friday);
    await tester.pump();
    expect(reports, isEmpty);
    expect(formDateShows("Start date", "2026-04-22"), findsOneWidget);
    expect(formDateShows("End date", "2026-04-22"), findsOneWidget);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: pickerPanel("Start date"),
        matching: find.byWidgetPredicate((widget) {
          return widget is CalendarDayPicker || widget is CalendarTimePicker;
        }),
      ),
      findsNothing,
    );
    expect(panelHeight(tester, "Start date"), 0.0);
    expect(dayPickerFinder("End date"), findsOneWidget);
  });

  testWidgets("IP5 a day picker draws disabled a day on which no time is "
      "admitted, and enabled one some time is admitted on", (tester) async {
    final thursday = DateTime(2026, 4, 23);
    Finder cell(String label, DateTime day) {
      return find.descendant(
        of: dayPickerFinder(label),
        matching: find.byKey(weekStripDayKey(day)),
      );
    }

    // FW1's running item under the lock: Tuesday's 24:00 lies at the lock's
    // boundary, the start of today, and an end in the past.
    final running = task("item-2", "Write", DateTime(2026, 4, 21, 22), at(10));
    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(running.start, running.end, isAllDay: false),
        policy: const HistoryLockPolicy<ItemPayload>(),
        entry: running,
      ),
    );
    await openDayPicker(tester, "End date");
    expect(dayEnabled(tester, "End date", DateTime(2026, 4, 21)), isFalse);
    expect(dayEnabled(tester, "End date", wednesday), isTrue);

    // Two days at most: an end on Friday covers three.
    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(at(9), at(10), isAllDay: false),
        policy: DayLimitPolicy<ItemPayload>(2),
      ),
    );
    await openDayPicker(tester, "End date");
    expect(dayEnabled(tester, "End date", DateTime(2026, 4, 24)), isFalse);
    expect(dayEnabled(tester, "End date", thursday), isTrue);

    // No spanning days: an end on Thursday spans two.
    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(at(22), DateTime(2026, 4, 23, 2), isAllDay: false),
        options: const CalendarScheduleOptions(spansDays: false),
      ),
    );
    await openDayPicker(tester, "End date");
    expect(dayEnabled(tester, "End date", thursday), isFalse);
    expect(dayEnabled(tester, "End date", wednesday), isTrue);

    // An overlap depends on the times, so its day stays enabled, and the
    // form names the overlap once the day is picked.
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task(
        "item-2",
        "Review",
        DateTime(2026, 4, 23, 9),
        DateTime(2026, 4, 23, 10),
      ),
    ]);
    addTearDown(store.dispose);
    await openEdit(
      tester,
      store,
      policy: const NoOverlapsPolicy<ItemPayload>(),
    );
    await openDayPicker(tester, "Start date");
    expect(dayEnabled(tester, "Start date", thursday), isTrue);
    await tester.tap(cell("Start date", thursday));
    await tester.pumpAndSettle();
    expect(formDateShows("Start date", "2026-04-23"), findsOneWidget);
    expect(find.byKey(scheduleOverlapKey), findsOneWidget);
  });

  testWidgets("IP6 browsing Start date's picker, by its chevrons, a fling and "
      "a drag of its week row and its month picker, changes no date", (
    tester,
  ) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    await openDayPicker(tester, "Start date");
    final picker = dayPickerFinder("Start date");
    Finder inDayPicker(Finder finder) {
      return find.descendant(of: picker, matching: finder);
    }

    String title() {
      return tester
          .widget<Text>(
            inDayPicker(
              find.descendant(
                of: find.byTooltip("Pick a month"),
                matching: find.byType(Text),
              ),
            ),
          )
          .data!;
    }

    final before = formSchedule(tester);
    void expectUnchanged(String step) {
      expect(formSchedule(tester), before, reason: step);
      expect(
        formDateShows("Start date", "2026-04-22"),
        findsOneWidget,
        reason: step,
      );
      expect(
        formDateShows("End date", "2026-04-22"),
        findsOneWidget,
        reason: step,
      );
    }

    await tester.tap(inDayPicker(find.byTooltip("Next week")));
    await tester.pumpAndSettle();
    expect(
      inDayPicker(
        find.byKey(weekStripDayKey(DateTime(2026, 4, 27))),
      ).hitTestable(),
      findsOneWidget,
    );
    expect(
      inDayPicker(find.byKey(weekStripDayKey(wednesday))).hitTestable(),
      findsNothing,
    );
    expectUnchanged("Next week");

    final weekRow = inDayPicker(find.byType(WeekStrip<ItemPayload>));
    await tester.fling(weekRow, const Offset(-200.0, 0.0), 1000.0);
    await tester.pumpAndSettle();
    expectUnchanged("the fling");

    await tester.drag(weekRow, const Offset(0.0, 40.0));
    await tester.pumpAndSettle();
    expect(inDayPicker(find.byType(MonthStrip<ItemPayload>)), findsOneWidget);
    final shown = title();
    expectUnchanged("the drag");

    await tester.tap(inDayPicker(find.byTooltip("Next month")));
    await tester.pumpAndSettle();
    const strings = DefaultCalendarLocalizations();
    final month =
        <DateTime>[
          for (var offset = -12; offset <= 12; offset++)
            DateTime(2026, 4 + offset),
        ].singleWhere((month) {
          return strings.shortMonthYear(month) == shown;
        });
    final next = DateTime(month.year, month.month + 1);
    expect(title(), strings.shortMonthYear(next));
    expect(
      inDayPicker(
        find.byKey(dayCellKey(DateTime(next.year, next.month, 15))),
      ).hitTestable(),
      findsOneWidget,
    );
    expectUnchanged("Next month");

    await tester.tap(inDayPicker(find.byTooltip("Pick a month")));
    await tester.pumpAndSettle();
    await tester.tap(inDayPicker(find.text("July")));
    await tester.pumpAndSettle();
    expect(inDayPicker(find.text("July")), findsNothing);
    expect(
      inDayPicker(find.byKey(dayCellKey(DateTime(2026, 7, 15)))).hitTestable(),
      findsOneWidget,
    );
    expectUnchanged("the month picker");
  });

  testWidgets("IP7 a tap on Start date gives its field the focus, where an "
      "arrow key changes no date, and once the unfolded month has the focus "
      "an arrow moves the start a day", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    await tester.tap(formDateFinder("Start date"));
    await tester.pumpAndSettle();
    expect(focusUnder(find.byKey(scheduleStartDateKey)), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(formDateShows("Start date", "2026-04-22"), findsOneWidget);
    expect(formDateShows("End date", "2026-04-22"), findsOneWidget);

    final picker = dayPickerFinder("Start date");
    await tester.tap(
      find.descendant(of: picker, matching: find.byKey(calendarPullTabKey)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: picker,
        matching: find.byKey(dayCellKey(DateTime(2026, 4, 23))),
      ),
    );
    await tester.pumpAndSettle();
    // Setup sanity: the tap picked the 23rd.
    expect(formDateShows("Start date", "2026-04-23"), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(formDateShows("Start date", "2026-04-24"), findsOneWidget);
  });

  testWidgets("IP8 an all-day item's Start date opens its day picker, which "
      "stays with its height and its field's focus as All day turns off; "
      "All day turned on closes a time picker at once, and keeps an open "
      "End date's picker and focus", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Trip", wednesday, DateTime(2026, 4, 23), isAllDay: true),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store, theme: motionTheme);
    // Setup sanity: the item is all-day.
    expect(formAllDayOn(), isTrue);
    await tester.tap(formDateFinder("Start date"));
    await tester.pumpAndSettle();
    expect(dayPickerFinder("Start date"), findsOneWidget);
    final full = settledDayPanelHeight(tester, "Start date");
    expect(panelHeight(tester, "Start date"), full);

    final picker = tester.state(dayPickerFinder("Start date"));
    await tester.ensureVisible(allDaySwitch());
    await tester.pumpAndSettle();
    await tester.tap(allDaySwitch());
    await tester.pump();
    // Setup sanity: the item turned timed.
    expect(timeFieldFinder("Start time"), findsOneWidget);
    for (var elapsed = 0; elapsed <= 480; elapsed += 16) {
      expect(panelHeight(tester, "Start date"), full, reason: "at $elapsed ms");
      expect(
        tester.state(dayPickerFinder("Start date")),
        same(picker),
        reason: "at $elapsed ms",
      );
      expect(
        focusUnder(find.byKey(scheduleStartDateKey)),
        isTrue,
        reason: "at $elapsed ms",
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    await tester.tap(timeFieldFinder("Start time"));
    await tester.pumpAndSettle();
    // Setup sanity: the time picker swapped in.
    expect(timePickerFinder("Start time"), findsOneWidget);
    await tester.ensureVisible(allDaySwitch());
    await tester.pumpAndSettle();
    await tester.tap(allDaySwitch());
    await tester.pump();
    expect(panelHeight(tester, "Start date"), 0.0);
    expect(find.byType(CalendarTimePicker), findsNothing);
    await tester.pumpAndSettle();

    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    // Setup sanity: the item is timed again.
    expect(formAllDayOn(), isFalse);
    await openDayPicker(tester, "End date");
    expect(focusUnder(find.byKey(scheduleEndDateKey)), isTrue);
    final endPicker = tester.state(dayPickerFinder("End date"));
    await tester.ensureVisible(allDaySwitch());
    await tester.pumpAndSettle();
    await tester.tap(allDaySwitch());
    await tester.pumpAndSettle();
    // Setup sanity: the item turned all-day.
    expect(formAllDayOn(), isTrue);
    expect(tester.state(dayPickerFinder("End date")), same(endPicker));
    expect(
      panelHeight(tester, "End date"),
      settledDayPanelHeight(tester, "End date"),
    );
    expect(focusUnder(find.byKey(scheduleEndDateKey)), isTrue);
  });

  testWidgets("IP9 each opening of Start date's picker shows it folded, a "
      "reopening while the panel closes or swaps out the day picker "
      "included", (tester) async {
    await pumpSection(
      tester,
      checkOf(CalendarSchedule.of(at(9), at(10), isAllDay: false)),
      theme: motionTheme,
    );
    final picker = dayPickerFinder("Start date");
    Future<void> unfold() async {
      await tester.tap(
        find.descendant(of: picker, matching: find.byKey(calendarPullTabKey)),
      );
      await tester.pumpAndSettle();
      // Setup sanity: the picker shows its month.
      expect(
        find.descendant(
          of: picker,
          matching: find.byType(MonthStrip<ItemPayload>),
        ),
        findsOneWidget,
      );
    }

    void expectFolded(String step) {
      expect(
        find.descendant(
          of: pickerPanel("Start date"),
          matching: find.byType(WeekStrip<ItemPayload>),
        ),
        findsOneWidget,
        reason: step,
      );
      expect(
        find.descendant(
          of: pickerPanel("Start date"),
          matching: find.byType(MonthStrip<ItemPayload>),
        ),
        findsNothing,
        reason: step,
      );
    }

    await tester.tap(formDateFinder("Start date"));
    await tester.pumpAndSettle();
    await unfold();
    await tester.tap(formDateFinder("Start date"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // Setup sanity: the panel still closes.
    expect(panelHeight(tester, "Start date"), greaterThan(0.0));
    await tester.tap(formDateFinder("Start date"));
    await tester.pumpAndSettle();
    expectFolded("reopened while it closed");

    await unfold();
    await tester.tap(timeFieldFinder("Start time"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // Setup sanity: the day picker still swaps out.
    expect(picker, findsOneWidget);
    await tester.tap(formDateFinder("Start date"));
    await tester.pumpAndSettle();
    expectFolded("reopened while it swapped out");
  });

  testWidgets("IP10 the section reads its check's day ranges once per "
      "check, and no frame of the panel's motion or of the day picker's "
      "unfold, slide, fold or fling checks the schedule", (tester) async {
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
    }, theme: motionTheme);
    final picker = dayPickerFinder("Start date");
    Finder inDayPicker(Finder finder) {
      return find.descendant(of: picker, matching: finder);
    }

    debugScheduleDayRangeAsks = 0;
    await tester.tap(formDateFinder("Start date"));
    await tester.pump();
    expect(debugScheduleDayRangeAsks, 1);
    final checks = asked.length;
    // Pumps the frames of what [step] started, from the frame after the
    // gesture's own, expecting after each pump no range read and no check
    // made since the panel opened. Both counts only grow, so the first
    // pump's reading covers the gesture's own frame too.
    Future<void> expectNoCheckThrough(String step) async {
      var frames = 0;
      do {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
        expect(debugScheduleDayRangeAsks, 1, reason: "$step, frame $frames");
        expect(asked, hasLength(checks), reason: "$step, frame $frames");
      } while (tester.binding.hasScheduledFrame && frames < 300);
      // Setup sanity: a motion ran over several frames, and ended.
      expect(frames, greaterThan(2), reason: step);
      expect(tester.binding.hasScheduledFrame, isFalse, reason: step);
    }

    await expectNoCheckThrough("the panel's motion");

    Future<void> tapThrough(Finder finder, String step) async {
      await tester.tap(finder);
      await tester.pump();
      await expectNoCheckThrough(step);
    }

    await tapThrough(inDayPicker(find.byKey(calendarPullTabKey)), "unfold");
    // Setup sanity: the picker shows its month.
    expect(inDayPicker(find.byType(MonthStrip<ItemPayload>)), findsOneWidget);
    await tapThrough(inDayPicker(find.byTooltip("Next month")), "slide");
    await tapThrough(inDayPicker(find.byKey(calendarPullTabKey)), "fold");
    // Setup sanity: the picker shows its week row.
    expect(inDayPicker(find.byType(MonthStrip<ItemPayload>)), findsNothing);
    await tester.fling(
      inDayPicker(find.byType(WeekStrip<ItemPayload>)),
      const Offset(-200.0, 0.0),
      1000.0,
    );
    await tester.pump();
    await expectNoCheckThrough("fling");

    // A new day picker under the same check reads no range.
    await openTimePicker(tester, "Start time");
    expect(debugScheduleDayRangeAsks, 1);
    await openDayPicker(tester, "Start date");
    expect(debugScheduleDayRangeAsks, 1);

    // A pick makes a new check, whose ranges the picker reads once.
    final thursday = DateTime(2026, 4, 23);
    await tester.tap(inDayPicker(find.byKey(weekStripDayKey(thursday))));
    await tester.pumpAndSettle();
    // Setup sanity: the tap picked Thursday.
    expect(formDateShows("Start date", "2026-04-23"), findsOneWidget);
    expect(debugScheduleDayRangeAsks, 2);
    final reads = debugScheduleDayRangeAsks;
    final picked = asked.length;
    for (final (step, finder) in <(String, Finder)>[
      ("unfold", inDayPicker(find.byKey(calendarPullTabKey))),
      ("Next month", inDayPicker(find.byTooltip("Next month"))),
      ("Next month again", inDayPicker(find.byTooltip("Next month"))),
      ("fold", inDayPicker(find.byKey(calendarPullTabKey))),
    ]) {
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(debugScheduleDayRangeAsks, reads, reason: step);
      expect(asked, hasLength(picked), reason: step);
    }
  });

  testWidgets("IP11 a swipe of the week row of Start date's picker released "
      "with no speed comes to rest on any day, and changes no date", (
    tester,
  ) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    await openDayPicker(tester, "Start date");
    final before = formSchedule(tester);
    final weekRow = find.descendant(
      of: dayPickerFinder("Start date"),
      matching: find.byType(WeekStrip<ItemPayload>),
    );
    final row = tester.getRect(weekRow);
    Finder cell(DateTime day) {
      return find.descendant(
        of: weekRow,
        matching: find.byKey(weekStripDayKey(day)),
      );
    }

    // Setup sanity: the week row runs Monday 20 to Sunday 26.
    expect(tester.getRect(cell(DateTime(2026, 4, 20))).left, row.left);
    final cellWidth = row.width / 7.0;
    final gesture = await tester.startGesture(row.center);
    var left = 3.0 * cellWidth;
    while (left > 0.0) {
      final step = math.min(left, 10.0);
      await gesture.moveBy(Offset(-step, 0.0));
      await tester.pump(const Duration(milliseconds: 16));
      left -= step;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.getRect(cell(DateTime(2026, 4, 23))).left,
      moreOrLessEquals(row.left, epsilon: 0.5),
    );
    expect(formSchedule(tester), before);
    expect(formDateShows("Start date", "2026-04-22"), findsOneWidget);
    expect(formDateShows("End date", "2026-04-22"), findsOneWidget);
  });

  testWidgets("IP12 a store change checks the form again only where it moves "
      "the entries over the item's days", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task(
        "item-2",
        "Review",
        DateTime(2026, 4, 27, 9),
        DateTime(2026, 4, 27, 10),
      ),
    ]);
    addTearDown(store.dispose);
    await openEdit(
      tester,
      store,
      policy: const NoOverlapsPolicy<ItemPayload>(),
    );
    await openDayPicker(tester, "Start date");
    debugScheduleDayRangeAsks = 0;
    await store.update(
      task(
        "item-2",
        "Review",
        DateTime(2026, 5, 4, 9),
        DateTime(2026, 5, 4, 10),
      ),
    );
    await tester.pump();
    expect(debugScheduleDayRangeAsks, 0);
    await store.update(task("item-2", "Review", at(9), at(10)));
    await tester.pump();
    expect(debugScheduleDayRangeAsks, 1);
    expect(find.byKey(scheduleOverlapKey), findsOneWidget);
  });

  testWidgets("IP13 End date's picker unfolded at the bottom of the form's "
      "view scrolls into it once the month has unfolded", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    await openDayPicker(tester, "End date");
    final scrollable = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    final page = tester.getRect(scrollable);
    // Setup sanity: the form's page is taller than its view, so the view
    // does not grow with the panel.
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      greaterThan(0.0),
    );
    final opened = tester.getRect(pickerPanel("End date"));
    expect(opened.bottom, lessThanOrEqualTo(page.bottom + 0.5));

    await tester.tap(
      find.descendant(
        of: dayPickerFinder("End date"),
        matching: find.byKey(calendarPullTabKey),
      ),
    );
    await tester.pumpAndSettle();
    // Setup sanity: the picker unfolded into its month, and the panel grew.
    expect(
      find.descendant(
        of: dayPickerFinder("End date"),
        matching: find.byType(MonthStrip<ItemPayload>),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(pickerPanel("End date")).height,
      greaterThan(opened.height),
    );
    expect(
      tester.getRect(pickerPanel("End date")).bottom,
      lessThanOrEqualTo(page.bottom + 0.5),
    );
  });

  testWidgets("IP14 End date's picker unfolded at the bottom of the form's "
      "view scrolls into it while an unrelated animation runs", (tester) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
    ]);
    addTearDown(store.dispose);
    await openEdit(tester, store);
    await openDayPicker(tester, "End date");
    final scrollable = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    final page = tester.getRect(scrollable);
    final opened = tester.getRect(pickerPanel("End date"));
    final unrelated = AnimationController(
      vsync: tester,
      duration: const Duration(seconds: 1),
    )..repeat();
    try {
      await tester.tap(
        find.descendant(
          of: dayPickerFinder("End date"),
          matching: find.byKey(calendarPullTabKey),
        ),
      );
      for (var frame = 0; frame < 50; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      // Setup sanity: the unrelated animation still runs, the picker
      // unfolded into its month, and the panel grew.
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      expect(
        find.descendant(
          of: dayPickerFinder("End date"),
          matching: find.byType(MonthStrip<ItemPayload>),
        ),
        findsOneWidget,
      );
      expect(
        tester.getRect(pickerPanel("End date")).height,
        greaterThan(opened.height),
      );
      expect(
        tester.getRect(pickerPanel("End date")).bottom,
        lessThanOrEqualTo(page.bottom + 0.5),
      );
    } finally {
      unrelated.dispose();
    }
  });

  testWidgets("IP15 the day picker under Start date or End date lies on its "
      "row's sides, folded and unfolded: the circles of its first and last "
      "columns reach the date field's left edge and the time field's right "
      "edge; and the badges of a day in its last column draw whole", (
    tester,
  ) async {
    final sunday = DateTime(2026, 4, 26);
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), at(10)),
      task(
        "item-2",
        "Plan",
        DateTime(2026, 4, 26, 9),
        DateTime(2026, 4, 26, 10),
      ),
      calendarItem(
        id: "item-3",
        type: CalendarItemType.risk,
        title: "Slip",
        start: DateTime(2026, 4, 26, 11),
        end: DateTime(2026, 4, 26, 12),
      ),
    ]);
    addTearDown(store.dispose);
    await openWith(tester, (context) {
      showEditForm(
        context,
        store: store,
        id: "item-1",
        policy: const UnrestrictedEditPolicy<ItemPayload>(),
        now: wednesdayStart,
        hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
        dayBadges: harborDayBadges,
      );
    });
    for (final (date, time) in <(String, String)>[
      ("Start date", "Start time"),
      ("End date", "End time"),
    ]) {
      final picker = dayPickerFinder(date);
      Rect circleOf(Key cell) {
        return tester.getRect(
          circleIn(find.descendant(of: picker, matching: find.byKey(cell))),
        );
      }

      await openDayPicker(tester, date);
      final left = tester.getRect(formDateFinder(date)).left;
      final right = tester.getRect(timeFieldFinder(time)).right;
      expect(
        circleOf(weekStripDayKey(DateTime(2026, 4, 20))).left,
        moreOrLessEquals(left),
        reason: date,
      );
      expect(
        circleOf(weekStripDayKey(sunday)).right,
        moreOrLessEquals(right),
        reason: date,
      );
      final badges = find
          .descendant(
            of: find.descendant(
              of: picker,
              matching: find.byKey(weekStripDayKey(sunday)),
            ),
            matching: find.byType(DecoratedBox),
          )
          .evaluate()
          .map((element) {
            return element.renderObject! as RenderBox;
          })
          .where((box) {
            return box.size.width < 10.0;
          })
          .toList();
      // Setup sanity: Sunday carries two badges, one of them past the
      // field's right edge.
      expect(badges, hasLength(2), reason: date);
      expect(
        badges.any((box) {
          return box.localToGlobal(Offset(box.size.width, 0.0)).dx > right;
        }),
        isTrue,
        reason: date,
      );
      for (final box in badges) {
        expect(
          paintedRectOf(box),
          MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          ),
          reason: date,
        );
      }

      await tester.tap(
        find.descendant(of: picker, matching: find.byKey(calendarPullTabKey)),
      );
      await tester.pumpAndSettle();
      expect(
        circleOf(dayCellKey(DateTime(2026, 4, 6))).left,
        moreOrLessEquals(left),
        reason: date,
      );
      expect(
        circleOf(dayCellKey(DateTime(2026, 4, 12))).right,
        moreOrLessEquals(right),
        reason: date,
      );
      await closeDayPicker(tester, date);
    }
  });

  testWidgets("IP16 Start date and End date show their date and no icon, "
      "on a timed item and on an all-day one", (tester) async {
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
    for (final id in <String>["item-1", "item-2"]) {
      await openEdit(tester, store, id: id);
      for (final label in <String>["Start date", "End date"]) {
        expect(
          find.descendant(
            of: formDateFinder(label),
            matching: find.byType(Icon),
          ),
          findsNothing,
          reason: "$id $label",
        );
      }
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
    }
  });

  testWidgets("IP17 Start date and End date write their days with the "
      "weekday, on a timed item that spans days and on an all-day one", (
    tester,
  ) async {
    final store = storeOf(<CalendarItem>[
      task("item-1", "Write", at(9), DateTime(2026, 4, 23, 10)),
      task(
        "item-2",
        "Off",
        DateTime(2026, 4, 24),
        DateTime(2026, 4, 25),
        isAllDay: true,
      ),
    ]);
    addTearDown(store.dispose);
    for (final (id, start, end) in <(String, String, String)>[
      ("item-1", "Wed, Apr 22", "Thu, Apr 23"),
      ("item-2", "Fri, Apr 24", "Fri, Apr 24"),
    ]) {
      await openEdit(tester, store, id: id);
      for (final (label, day) in <(String, String)>[
        ("Start date", start),
        ("End date", end),
      ]) {
        expect(
          find.descendant(of: formDateFinder(label), matching: find.text(day)),
          findsOneWidget,
          reason: "$id $label",
        );
      }
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
    }
  });

  testWidgets("IP18 End date's picker browses back, by its previous chevron "
      "or a fling of its week row, to no week before the start day's, the "
      "chevron drawn disabled there, while Start date's browses past its "
      "first day", (tester) async {
    await pumpSection(
      tester,
      checkOf(
        CalendarSchedule.of(at(9), at(10), isAllDay: false),
        policy: const HistoryLockPolicy<ItemPayload>(),
      ),
    );
    Finder inPicker(String label, Finder finder) {
      return find.descendant(of: dayPickerFinder(label), matching: finder);
    }

    bool shows(String label, DateTime day) {
      return inPicker(
        label,
        find.byKey(weekStripDayKey(day)),
      ).hitTestable().evaluate().isNotEmpty;
    }

    bool previousEnabled(String label) {
      return tester
              .widget<IconButton>(
                inPicker(
                  label,
                  find.widgetWithIcon(IconButton, Icons.chevron_left),
                ),
              )
              .onPressed !=
          null;
    }

    // The start day, Wednesday April 22, lies in the week from Monday
    // April 20.
    final monday = DateTime(2026, 4, 20);
    await openDayPicker(tester, "End date");
    expect(previousEnabled("End date"), isFalse);
    await tester.tap(inPicker("End date", find.byTooltip("Previous week")));
    await tester.pumpAndSettle();
    expect(shows("End date", monday), isTrue);
    await tester.fling(
      inPicker("End date", find.byType(WeekStrip<ItemPayload>)),
      const Offset(300.0, 0.0),
      3000.0,
    );
    await tester.pumpAndSettle();
    expect(shows("End date", monday), isTrue);
    expect(shows("End date", DateTime(2026, 4, 19)), isFalse);

    await openDayPicker(tester, "Start date");
    // Setup sanity: the lock refuses starts before today, Wednesday.
    expect(dayEnabled(tester, "Start date", DateTime(2026, 4, 21)), isFalse);
    expect(previousEnabled("Start date"), isTrue);
    await tester.tap(inPicker("Start date", find.byTooltip("Previous week")));
    await tester.pumpAndSettle();
    expect(shows("Start date", DateTime(2026, 4, 13)), isTrue);
  });
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

/// A policy that refuses an overlap with the item [id] alone.
final class _RefusesOverlapWith extends CalendarEditPolicy<ItemPayload> {
  const _RefusesOverlapWith(this.id);

  final String id;

  @override
  bool get allowsOverlaps {
    return false;
  }

  @override
  bool mayOverlap(
    CalendarOverlapCandidate<ItemPayload> candidate,
    CalendarEntry<ItemPayload> other,
  ) {
    return other.id != id;
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

/// A store each of whose updates waits until the test completes [release].
final class _HeldUpdates extends MemoryCalendarStore<ItemPayload> {
  _HeldUpdates(List<CalendarItem> items) : super(entries: items);

  final Completer<void> release = Completer<void>();

  @override
  Future<CalendarItem> update(CalendarItem entry) async {
    await release.future;
    return super.update(entry);
  }
}

/// A store that refuses each create with [fieldErrors], as the API's
/// validation refuses an item.
final class _RefusedCreates extends MemoryCalendarStore<ItemPayload> {
  _RefusedCreates(this.fieldErrors);

  final Map<String, String> fieldErrors;

  @override
  Future<CalendarItem> create(CalendarItem draft) async {
    throw CalendarValidationException(fieldErrors);
  }
}
