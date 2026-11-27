/// The details the views report: a tap on an entry's block or chip, with
/// the stored entry and whether it is editable; a pinch's zoom of the timed
/// grid and of the month board; the create each view's gesture reports;
/// and the edit and delete requests of a day list's card.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/calendar/presentation/calendar_builders.dart';
import 'package:widgets_extended/calendar/views/create_details.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/pinch_zoom.dart'
    show defaultMinSlotHeight;
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/view_details.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/policy/edit_rules.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

import '../edit_policies.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime thursday = DateTime(2026, 4, 23);

/// April 2026, from March 30 to May 3.
final CalendarMonthGrid april = CalendarMonthGrid(2026, 4);

/// Entry `a`, from 10:00 to 11:00 on Tuesday.
final CalendarEntry<String> entryA = CalendarEntry<String>(
  id: "a",
  start: DateTime(2026, 4, 21, 10),
  end: DateTime(2026, 4, 21, 11),
  title: "a",
  color: const Color(0xFF336699),
  payload: "a",
);

/// A store holding [entries], [entryA] by default.
MemoryCalendarStore<String> storeOf({List<CalendarEntry<String>>? entries}) {
  final store = MemoryCalendarStore<String>(
    entries: entries ?? <CalendarEntry<String>>[entryA],
  );
  addTearDown(store.dispose);
  return store;
}

/// A clock at 09:00 on Monday.
ValueNotifier<CalendarNow> mondayClock() {
  final now = ValueNotifier<CalendarNow>(
    CalendarNow(time: DateTime(2026, 4, 20, 9), today: monday),
  );
  addTearDown(now.dispose);
  return now;
}

/// Lays the test out in a view of [size].
void useView(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

/// The edit modes and policies a tap is reported under, with whether each
/// reports the entry editable: in edit mode under the unrestricted policy,
/// in edit mode under a policy that lets [entryA] not be edited, and out
/// of edit mode.
const List<({String name, bool editable, bool refuses, bool expected})>
tapCases = <({String name, bool editable, bool refuses, bool expected})>[
  (name: "edit mode", editable: true, refuses: false, expected: true),
  (name: "refusing policy", editable: true, refuses: true, expected: false),
  (name: "out of edit mode", editable: false, refuses: false, expected: false),
];

/// The policy of a tap case: one whose [CalendarEditPolicy.mayEdit] refuses
/// [entryA] where [refuses], and otherwise the unrestricted one.
CalendarEditPolicy<String> policyOf(bool refuses) {
  return refuses
      ? const ScriptedEditPolicy<String>(uneditable: <String>{"a"})
      : const UnrestrictedEditPolicy<String>();
}

/// The global rect of the slot row holding [minute] in [column] of the
/// one timed grid [tester] holds over every hour at the default slot: the
/// board's row count less the slot rows and the room below them, plus the
/// slots to [minute]. Column 0 is the hour gutter.
Rect slotRect(WidgetTester tester, int minute, {required int column}) {
  final viewport = tester.allRenderObjects
      .whereType<RenderBoardViewport<GridKey>>()
      .single;
  final board =
      find
              .byWidgetPredicate((widget) {
                return widget is Board<GridKey, Object?>;
              })
              .evaluate()
              .single
              .widget
          as Board<GridKey, Object?>;
  final firstSlotRow =
      board.controller.rows.axis.trackCount -
      CalendarDayHours.allDay.slotCountOf(CalendarDates.defaultSlotMinutes) -
      1;
  final rect = viewport.rectOfCell(
    firstSlotRow + minute ~/ CalendarDates.defaultSlotMinutes,
    column,
  )!;
  return Rect.fromPoints(
    viewport.localToGlobal(rect.topLeft),
    viewport.localToGlobal(rect.bottomRight),
  );
}

/// Pinches up and down about [focal]: two fingers 60 logical pixels apart
/// spread 6 pixels each way three times, with a frame after each, then
/// lifted.
Future<void> pinchAbout(WidgetTester tester, Offset focal) async {
  final first = await tester.startGesture(focal - const Offset(0.0, 30.0));
  final second = await tester.startGesture(focal + const Offset(0.0, 30.0));
  for (var i = 0; i < 3; i++) {
    await first.moveBy(const Offset(0.0, -6.0));
    await second.moveBy(const Offset(0.0, 6.0));
    await tester.pump();
  }
  await first.up();
  await second.up();
  await tester.pumpAndSettle();
}

/// A timed grid of the week from Monday over [store], in twelve-hour
/// labels.
TimedGrid<String> gridOf(
  MemoryCalendarStore<String> store,
  ValueListenable<CalendarNow> now, {
  bool editable = false,
  CalendarEditPolicy<String>? editPolicy,
  ValueChanged<CalendarEntryTapDetails<String>>? onEntryTap,
  ValueChanged<CalendarGridZoomDetails>? onZoom,
  Future<void> Function(CalendarCreateDetails details)? onCreateRange,
}) {
  return TimedGrid<String>(
    store: store,
    firstDay: monday,
    dayCount: DateTime.daysPerWeek,
    selectedDay: tuesday,
    now: now,
    onSelectDay: (day) {},
    onEntryTap: onEntryTap,
    onCreateRange: onCreateRange ?? (details) async {},
    onMoveRequest: (request) async {},
    editable: editable,
    editPolicy: editPolicy,
    hourLabelFormat: CalendarHourLabelFormat.twelveHour,
    onZoom: onZoom,
  );
}

/// A month board of April over [store].
MonthBoard<String> boardOf(
  MemoryCalendarStore<String> store,
  ValueListenable<CalendarNow> now, {
  bool editable = false,
  CalendarEditPolicy<String>? editPolicy,
  CalendarEditRules<String> Function()? takeRules,
  ValueChanged<CalendarEntryTapDetails<String>>? onEntryTap,
  ValueChanged<CalendarMonthZoomDetails>? onZoom,
  Future<void> Function(CalendarCreateDetails details)? onCreateRange,
}) {
  return MonthBoard<String>(
    store: store,
    grid: april,
    layout: CalendarMonthLayout.showAll,
    selectedDay: tuesday,
    now: now,
    onSelectDay: (day) {},
    onOpenDay: (day) {},
    editable: editable,
    editPolicy: editPolicy,
    takeRules: takeRules,
    onCreateRange: onCreateRange ?? (details) async {},
    onEntryTap: onEntryTap,
    onZoom: onZoom,
  );
}

/// A day list opening on Tuesday over [store], in edit mode.
DayList<String> listOf(
  MemoryCalendarStore<String> store,
  ValueListenable<CalendarNow> now, {
  ValueChanged<CalendarEditRequestDetails<String>>? onEditRequest,
  ValueChanged<CalendarDeleteRequestDetails<String>>? onDeleteRequest,
  Future<void> Function(CalendarCreateDetails details)? onCreateRange,
  CalendarCardBuilder<String>? cardBuilder,
}) {
  return DayList<String>(
    store: store,
    weekdays: CalendarWeekdaySet.all,
    hourLabelFormat: CalendarHourLabelFormat.twentyFourHour,
    hours: CalendarDayHours.allDay,
    editable: true,
    selectedDay: tuesday,
    now: now,
    onTopDay: (day) {},
    onCreateRange: onCreateRange ?? (details) async {},
    onEditRequest: onEditRequest ?? (details) {},
    onDeleteRequest: onDeleteRequest ?? (details) {},
    cardBuilder: cardBuilder,
    addButtonBuilder: (context, details) {
      return GestureDetector(
        onTap: details.onPressed,
        child: const Text("add"),
      );
    },
  );
}

void main() {
  testWidgets("VD1 a timed grid reports a tap on a block with the stored "
      "entry, editable in edit mode where its policy lets the entry be "
      "edited, and a pinch with the least slot height it zooms to", (
    tester,
  ) async {
    useView(tester, const Size(800.0, 600.0));
    for (final tap in tapCases) {
      final store = storeOf();
      final now = mondayClock();
      final taps = <CalendarEntryTapDetails<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: gridOf(
            store,
            now,
            editable: tap.editable,
            editPolicy: policyOf(tap.refuses),
            onEntryTap: taps.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(blockKey("a", tuesday)));
      await tester.pumpAndSettle();
      expect(taps, hasLength(1), reason: tap.name);
      expect(taps.single.entry, store.storedEntry("a"), reason: tap.name);
      expect(taps.single.editable, tap.expected, reason: tap.name);
    }

    final zooms = <CalendarGridZoomDetails>[];
    await tester.pumpWidget(
      MaterialApp(home: gridOf(storeOf(), mondayClock(), onZoom: zooms.add)),
    );
    await tester.pumpAndSettle();
    await pinchAbout(tester, slotRect(tester, 15 * 60, column: 4).center);
    expect(zooms, isNotEmpty);
    expect(zooms.last.minSlotHeight, greaterThan(defaultMinSlotHeight));
  });

  testWidgets("VD2 a month board reports a tap on a chip with the stored "
      "entry, editable in edit mode where its policy lets the entry be "
      "edited, and a pinch with the week scale it zooms to", (tester) async {
    useView(tester, const Size(800.0, 600.0));
    final chip = find.byKey(monthChipKey(monthSegmentKey("a", monday)));
    for (final tap in tapCases) {
      final store = storeOf();
      final now = mondayClock();
      final taps = <CalendarEntryTapDetails<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: boardOf(
            store,
            now,
            editable: tap.editable,
            editPolicy: policyOf(tap.refuses),
            onEntryTap: taps.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(taps, hasLength(1), reason: tap.name);
      expect(taps.single.entry, store.storedEntry("a"), reason: tap.name);
      expect(taps.single.editable, tap.expected, reason: tap.name);
    }

    final zooms = <CalendarMonthZoomDetails>[];
    await tester.pumpWidget(
      MaterialApp(home: boardOf(storeOf(), mondayClock(), onZoom: zooms.add)),
    );
    await tester.pumpAndSettle();
    await pinchAbout(
      tester,
      tester.getCenter(find.byKey(monthDayKey(DateTime(2026, 4, 15)))),
    );
    expect(zooms, isNotEmpty);
    expect(zooms.last.weekScale, greaterThan(1.0));
  });

  testWidgets("VD3 the timed grid, the day list and the month board report "
      "a create through onCreateRange from the slot or the day its gesture "
      "picked, the board's with a length the user did not choose", (
    tester,
  ) async {
    useView(tester, const Size(800.0, 2000.0));
    final now = mondayClock();
    final creates = <(String, CalendarCreateDetails)>[];

    await tester.pumpWidget(
      MaterialApp(
        home: gridOf(
          storeOf(),
          now,
          editable: true,
          onCreateRange: (details) async {
            creates.add(("grid", details));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final hold = await tester.startGesture(
      slotRect(tester, 14 * 60, column: 4).center,
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await hold.up();
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        home: listOf(
          storeOf(entries: const <CalendarEntry<String>>[]),
          now,
          onCreateRange: (details) async {
            creates.add(("list", details));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(dayListGapKey(tuesday, 0)),
        matching: find.text("add"),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        home: boardOf(
          storeOf(),
          now,
          editable: true,
          takeRules: () {
            return CalendarEditRules<String>(
              policy: const UnrestrictedEditPolicy<String>(),
              hours: CalendarDayHours.allDay,
              slotMinutes: CalendarDates.defaultSlotMinutes,
            );
          },
          onCreateRange: (details) async {
            creates.add(("board", details));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(monthStripKey(DateTime(2026, 4, 22))));
    await tester.pumpAndSettle();

    expect(
      <(String, DateTime)>[
        for (final (view, details) in creates) (view, details.range.start),
      ],
      <(String, DateTime)>[
        ("grid", DateTime(2026, 4, 23, 14)),
        ("list", tuesday),
        ("board", DateTime(2026, 4, 22)),
      ],
    );
    expect(creates.last.$2.userChoseLength, isFalse);
  });

  testWidgets("VD4 a day list's card reports its edit and its delete "
      "requests with the stored entry", (tester) async {
    useView(tester, const Size(800.0, 2000.0));
    final store = storeOf();
    final edits = <CalendarEditRequestDetails<String>>[];
    final deletes = <CalendarDeleteRequestDetails<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: listOf(
          store,
          mondayClock(),
          onEditRequest: edits.add,
          onDeleteRequest: deletes.add,
          cardBuilder: (context, entry, details) {
            return Row(
              children: <Widget>[
                GestureDetector(
                  onTap: details.onEdit,
                  child: Text("edit ${entry.entry.id}"),
                ),
                GestureDetector(
                  onTap: details.onDelete,
                  child: Text("delete ${entry.entry.id}"),
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text("edit a"));
    await tester.pumpAndSettle();
    expect(edits, hasLength(1));
    expect(edits.single.entry, store.storedEntry("a"));
    expect(deletes, isEmpty);
    await tester.tap(find.text("delete a"));
    await tester.pumpAndSettle();
    expect(deletes, hasLength(1));
    expect(deletes.single.entry, store.storedEntry("a"));
    expect(edits, hasLength(1));
  });
}
