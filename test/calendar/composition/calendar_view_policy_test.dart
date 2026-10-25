/// The calendar's edit policy: what each answer limits in Week, Day, Month
/// and Agenda, a policy change and a new minute during a gesture, a create
/// range's earliest start as the minute moves, and an answer that throws.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/calendar/composition/calendar_header.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/edit_policy.dart';
import 'package:widgets_extended/calendar/policy/history_lock_policy.dart';
import 'package:widgets_extended/calendar/presentation/calendar_builders.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';

import '../edit_policies.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);
final DateTime thursday = DateTime(2026, 4, 23);
final DateTime friday = DateTime(2026, 4, 24);

/// [hour]:[minute]:[second] on [day].
DateTime at(DateTime day, int hour, [int minute = 0, int second = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute, second);
}

CalendarEntry<String> entryOf(String id, DateTime start, DateTime end) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

/// A store holding [entries] over [hours], disposed at the test's end.
MoveRecordingStore storeOf(
  List<CalendarEntry<String>> entries, {
  DayHours hours = DayHours.allDay,
}) {
  final store = MoveRecordingStore(entries: entries, hours: hours);
  addTearDown(store.dispose);
  return store;
}

/// An editable calendar on [view] over [day] and [store], in a view 800
/// wide and 2000 tall, where Week's and Day's grids show every slot of the
/// day, marking [today] as today, or with none the clock's day. Its clock
/// reads [time], its policy is [policy]'s and edit mode
/// [editable]'s, each of which builds it again when set. It records each
/// create it reports in [creates], each tap in [taps], the last details
/// each card is built with in [cards], and each add button's details in
/// [adds].
class Host {
  Host(
    this.store, {
    required this.view,
    required this.day,
    required this.time,
    CalendarEditPolicy<String>? policy,
    this.hours = DayHours.allDay,
    this.today,
  }) : policy = ValueNotifier<CalendarEditPolicy<String>?>(policy);

  final MoveRecordingStore store;
  final CalendarViewKind view;
  final DateTime day;
  final DayHours hours;
  final DateTime? today;

  /// What the calendar's clock reads.
  DateTime time;

  final ValueNotifier<CalendarEditPolicy<String>?> policy;
  final ValueNotifier<bool> editable = ValueNotifier<bool>(true);

  final List<CreateRange> creates = <CreateRange>[];
  final List<CalendarEntryTapDetails<String>> taps =
      <CalendarEntryTapDetails<String>>[];
  final Map<String, CalendarCardDetails> cards =
      <String, CalendarCardDetails>{};
  final List<CalendarAddButtonDetails> adds = <CalendarAddButtonDetails>[];

  late final CalendarController controller = CalendarController(
    view: view,
    selectedDay: day,
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800.0, 2000.0);
    addTearDown(tester.view.reset);
    addTearDown(controller.dispose);
    addTearDown(policy.dispose);
    addTearDown(editable.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[policy, editable]),
          builder: (context, child) {
            return CalendarView<String>(
              key: ObjectKey(this),
              store: store,
              controller: controller,
              clock: () {
                return time;
              },
              editable: editable.value,
              editPolicy: policy.value,
              hours: hours,
              today: today,
              cardBuilder: (context, entry, details) {
                cards[entry.entry.id!] = details;
                return Text("card ${entry.entry.id}");
              },
              cardExtentOf: (entry) {
                return 56.0;
              },
              addButtonBuilder: (context, details) {
                adds.add(details);
                return GestureDetector(
                  onTap: details.onPressed,
                  child: Text("add ${details.startMinute}"),
                );
              },
              onEntryTap: taps.add,
              onCreateRange: (range) async {
                creates.add(range);
              },
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

/// The block of [id]'s piece on [day], or with no [day] its one block.
Finder blockFinder(String id, [DateTime? day]) {
  if (day != null) {
    return find.byKey(blockKey(id, day));
  }
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith("block-$id@");
  });
}

/// The all-day strip's bar of [id].
Finder barFinder(String id) {
  return find.byKey(allDayBarKey(id));
}

/// The drag handle of what [finder] finds.
BoardDelayedDragHandle handleOf(WidgetTester tester, Finder finder) {
  return tester.widget<BoardDelayedDragHandle>(
    find.descendant(of: finder, matching: find.byType(BoardDelayedDragHandle)),
  );
}

/// The one timed grid's viewport.
RenderBoardViewport<GridKey> gridViewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<GridKey>>()
      .single;
}

/// The grid row of the slot holding [minute] in the one timed grid shown
/// now: its board's row count less its slot rows and the room below them,
/// plus the slots from its hours' start.
int rowOf(int minute) {
  final grid =
      find.byType(TimedGrid<String>).evaluate().single.widget
          as TimedGrid<String>;
  final board =
      find.byType(Board<GridKey, GridShape<String>>).evaluate().single.widget
          as Board<GridKey, GridShape<String>>;
  final hours = grid.hours;
  final firstSlotRow =
      board.controller.rows.axis.trackCount -
      hours.slotCountOf(grid.slotMinutes) -
      1;
  return firstSlotRow + (minute - hours.start) ~/ grid.slotMinutes;
}

/// Week's grid column of [day], Monday's being 1; Day's one column is 1.
int colOf(DateTime day, {bool week = true}) {
  return week ? 1 + weekdayColumnOfDay(dayNumber(day)) : 1;
}

/// The global centre of the grid's slot holding [minute] in [day]'s
/// column.
Offset slotCenter(
  WidgetTester tester,
  DateTime day,
  int minute, {
  bool week = true,
}) {
  final viewport = gridViewport(tester);
  return viewport.localToGlobal(
    viewport.rectOfCell(rowOf(minute), colOf(day, week: week))!.center,
  );
}

/// A canvas that records the rects drawn on it with their paints. Every
/// other call is ignored.
class RecordingCanvas implements Canvas {
  final List<({Rect rect, Paint paint})> rects = <({Rect rect, Paint paint})>[];

  @override
  void drawRect(Rect rect, Paint paint) {
    rects.add((rect: rect, paint: paint));
  }

  @override
  void save() {}

  @override
  void restore() {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return null;
  }
}

/// Whether the timed grid's background marks a range of slots, which it
/// edges with a stroke.
bool marksRange(WidgetTester tester) {
  final viewport = gridViewport(tester);
  final canvas = RecordingCanvas();
  viewport.background!.paint(canvas, viewport);
  return canvas.rects.any((record) {
    return record.paint.style == PaintingStyle.stroke;
  });
}

/// Long-presses [at], lifting the block or bar there, and returns the
/// gesture.
Future<TestGesture> lift(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at);
  await tester.pump(kLongPressTimeout + kPressTimeout);
  return gesture;
}

/// Lifts what lies at [from] and moves the pointer to [to] in two steps,
/// a frame after each; returns the gesture still held.
Future<TestGesture> liftTo(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await lift(tester, from);
  await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  return gesture;
}

/// Selects the block found by [finder] with a long press let go in place.
Future<void> select(WidgetTester tester, Finder finder) async {
  final gesture = await lift(tester, tester.getCenter(finder));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// A mouse press at [from] dragged to [to] in two steps, a frame after
/// each; returns the gesture still held.
Future<TestGesture> holdRange(
  WidgetTester tester,
  Offset from,
  Offset to,
) async {
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  return gesture;
}

/// Presses [at] with a touch, holds it past a long press and lets go.
Future<void> hold(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at);
  await tester.pump(kLongPressTimeout + kPressTimeout);
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The custom semantics action ids of the nearest node at or above the
/// node of [finder] that holds any, or none where no node does.
List<int> nearestActions(WidgetTester tester, Finder finder) {
  SemanticsNode? node = tester.getSemantics(finder);
  while (node != null) {
    final ids = node.getSemanticsData().customSemanticsActionIds;
    if (ids != null && ids.isNotEmpty) {
      return ids;
    }
    node = node.parent;
  }
  return const <int>[];
}

/// The ids of the board's four move actions, by their default labels.
final Set<int> moveActionIds = <int>{
  for (final label in const <String>[
    "Move up",
    "Move down",
    "Move left",
    "Move right",
  ])
    CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: label)),
};

/// Whether [a] and [b] lie within 1 px of each other on every edge.
bool near(Rect a, Rect b) {
  return (a.left - b.left).abs() <= 1.0 &&
      (a.top - b.top).abs() <= 1.0 &&
      (a.right - b.right).abs() <= 1.0 &&
      (a.bottom - b.bottom).abs() <= 1.0;
}

/// PV1's policy: no move of A and the all-day A2, the end's edge alone of
/// B, no edit of C, no delete of D, and on Thursday an earliest start of
/// 10:00.
ScriptedEditPolicy<String> pv1Policy() {
  return ScriptedEditPolicy<String>(
    unmovable: const <String>{"A", "A2"},
    edges: const <String, CalendarResizeEdges>{"B": CalendarResizeEdges.end},
    uneditable: const <String>{"C"},
    undeletable: const <String>{"D"},
    earliestStarts: <DateTime, DateTime?>{thursday: at(thursday, 10)},
  );
}

/// Runs [body] with [FlutterError.onError] recording each reported error
/// in the list it is given, and restores it after.
Future<void> recordingErrors(
  Future<void> Function(List<FlutterErrorDetails> errors) body,
) async {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await body(errors);
  } finally {
    FlutterError.onError = previous;
  }
}

void main() {
  testWidgets("PV1 each answer limits its gestures in Week, Month and "
      "Agenda, and out of edit mode nothing moves", (tester) async {
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("A", at(wednesday, 14), at(wednesday, 15)),
      entryOf("A2", wednesday, thursday),
      entryOf("B", at(tuesday, 10), at(tuesday, 11)),
      entryOf("C", at(tuesday, 13), at(tuesday, 14)),
      entryOf("D", at(tuesday, 16), at(tuesday, 17)),
    ]);
    final host = Host(
      store,
      view: CalendarViewKind.week,
      day: tuesday,
      time: at(monday, 8),
      policy: pv1Policy(),
    );
    await host.pump(tester);

    // Week: A and A2 do not move.
    expect(handleOf(tester, blockFinder("A")).enabled, isFalse);
    expect(handleOf(tester, barFinder("A2")).enabled, isFalse);
    expect(handleOf(tester, blockFinder("B")).enabled, isTrue);
    var gesture = await liftTo(
      tester,
      tester.getCenter(blockFinder("A")),
      slotCenter(tester, wednesday, 18 * 60),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    gesture = await liftTo(
      tester,
      tester.getCenter(barFinder("A2")),
      tester.getCenter(find.byKey(allDayCellKey(friday))),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.moves, isEmpty);

    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(
      nearestActions(
        tester,
        blockFinder("A"),
      ).toSet().intersection(moveActionIds),
      isEmpty,
    );
    expect(
      nearestActions(
        tester,
        blockFinder("B"),
      ).toSet().intersection(moveActionIds),
      isNotEmpty,
    );
    semantics.dispose();
    await tester.pump();

    // B resizes by its end alone.
    await select(tester, blockFinder("B"));
    expect(find.byKey(blockGripKey("B", AxisDirection.down)), findsOneWidget);
    expect(find.byKey(blockGripKey("B", AxisDirection.up)), findsNothing);
    expect(store.moves, isEmpty);

    // A tap on C reports it read-only, and on B editable.
    await tester.tap(blockFinder("C"));
    await tester.pumpAndSettle();
    expect(host.taps.last.entry.id, "C");
    expect(host.taps.last.editable, isFalse);
    await tester.tap(blockFinder("B"));
    await tester.pumpAndSettle();
    expect(host.taps.last.entry.id, "B");
    expect(host.taps.last.editable, isTrue);

    // Thursday's creates start at 10:00 or later.
    await hold(tester, slotCenter(tester, thursday, 9 * 60));
    expect(host.creates, isEmpty);
    await hold(tester, slotCenter(tester, thursday, 10 * 60));
    // Setup sanity: a hold on a slot the policy admits creates.
    expect(host.creates, <CreateRange>[
      CreateRange(start: at(thursday, 10), end: at(thursday, 10, 15)),
    ]);

    // Month.
    host.controller.view = CalendarViewKind.month;
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(monthStripKey(thursday)));
    await tester.pumpAndSettle();
    expect(host.creates, hasLength(2));
    expect(dayNumber(host.creates.last.start), dayNumber(thursday));
    expect(host.creates.last.start.isBefore(at(thursday, 10)), isFalse);

    // Agenda.
    host.controller.selectedDay = tuesday;
    host.controller.view = CalendarViewKind.agenda;
    await tester.pumpAndSettle();
    expect(host.cards["C"]!.onEdit, isNull);
    expect(host.cards["B"]!.onEdit, isNotNull);
    expect(host.cards["D"]!.onDelete, isNull);
    expect(host.cards["B"]!.onDelete, isNotNull);
    host.adds.clear();
    host.controller.selectedDay = thursday;
    await tester.pumpAndSettle();
    final thursdayAdds = <int>[
      for (final add in host.adds)
        if (dayNumber(add.day) == dayNumber(thursday)) add.startMinute,
    ];
    // Setup sanity: Thursday's gap rows built their buttons.
    expect(thursdayAdds, isNotEmpty);
    expect(thursdayAdds, everyElement(greaterThanOrEqualTo(600)));

    // Setup sanity: in edit mode B moves.
    host.controller.selectedDay = tuesday;
    host.controller.view = CalendarViewKind.week;
    await tester.pumpAndSettle();
    gesture = await liftTo(
      tester,
      tester.getCenter(blockFinder("B")),
      slotCenter(tester, friday, 10 * 60 + 30),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.moves, hasLength(1));

    // Out of edit mode nothing moves.
    host.editable.value = false;
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Board<GridKey, GridShape<String>>>(
            find.byType(Board<GridKey, GridShape<String>>),
          )
          .drag!
          .enabled,
      isFalse,
    );
    gesture = await liftTo(
      tester,
      tester.getCenter(blockFinder("B")),
      slotCenter(tester, friday, 14 * 60),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.moves, hasLength(1));
  });

  group("PV3", () {
    final changed = UnrestrictedEditPolicy<String>(allowsOverlaps: false);

    /// Entries after Monday, the clock's day: M and R to move and resize,
    /// and N across Tuesday's midnight.
    List<CalendarEntry<String>> entries() {
      return <CalendarEntry<String>>[
        entryOf("M", at(tuesday, 10), at(tuesday, 11)),
        entryOf("R", at(wednesday, 10), at(wednesday, 11)),
        entryOf("N", at(tuesday, 22), at(wednesday, 2)),
      ];
    }

    Future<Host> pumpWeek(
      WidgetTester tester, {
      CalendarEditPolicy<String>? policy,
    }) async {
      final host = Host(
        storeOf(entries()),
        view: CalendarViewKind.week,
        day: tuesday,
        time: at(monday, 8),
        policy: policy,
      );
      await host.pump(tester);
      return host;
    }

    testWidgets("a new policy cancels a move, a resize, a create range and "
        "a move of a two-day entry's piece in flight, each leaving the "
        "blocks at their stored rects", (tester) async {
      // A move.
      var host = await pumpWeek(tester);
      final moved = tester.getRect(blockFinder("M"));
      var gesture = await liftTo(
        tester,
        moved.center,
        slotCenter(tester, tuesday, 14 * 60),
      );
      host.policy.value = changed;
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(host.store.moves, isEmpty);
      expect(near(tester.getRect(blockFinder("M")), moved), isTrue);

      // A resize.
      host = await pumpWeek(tester);
      await select(tester, blockFinder("R"));
      final resized = tester.getRect(blockFinder("R"));
      final from = Offset(resized.center.dx, resized.bottom - 2.0);
      gesture = await tester.startGesture(from);
      final to = slotCenter(tester, wednesday, 12 * 60);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      // Setup sanity: the resize runs.
      expect(
        tester.getRect(blockFinder("R")).bottom,
        greaterThan(resized.bottom),
      );
      host.policy.value = changed;
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(host.store.moves, isEmpty);
      expect(near(tester.getRect(blockFinder("R")), resized), isTrue);

      // A create range.
      host = await pumpWeek(tester);
      gesture = await holdRange(
        tester,
        slotCenter(tester, thursday, 9 * 60),
        slotCenter(tester, thursday, 11 * 60),
      );
      // Setup sanity: the range runs.
      expect(marksRange(tester), isTrue);
      host.policy.value = changed;
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(host.creates, isEmpty);

      // The Tuesday piece of Tuesday 22:00 to Wednesday 02:00.
      host = await pumpWeek(tester);
      final first = tester.getRect(blockFinder("N", tuesday));
      final second = tester.getRect(blockFinder("N", wednesday));
      gesture = await liftTo(
        tester,
        first.center,
        slotCenter(tester, tuesday, 18 * 60),
      );
      // Setup sanity: the lift takes the Wednesday piece away.
      expect(blockFinder("N", wednesday), findsNothing);
      host.policy.value = changed;
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(host.store.moves, isEmpty);
      expect(near(tester.getRect(blockFinder("N", tuesday)), first), isTrue);
      expect(near(tester.getRect(blockFinder("N", wednesday)), second), isTrue);
    });

    testWidgets("an equal policy, a second history lock equal to the first, "
        "and a new minute cancel no move and no create range", (tester) async {
      for (final (from, to) in <(CalendarEditPolicy<String>?, Object?)>[
        (null, const UnrestrictedEditPolicy<String>()),
        // ignore: prefer_const_constructors
        (HistoryLockPolicy<String>(), HistoryLockPolicy<String>()),
        (const HistoryLockPolicy<String>(lockEarlierToday: true), "minute"),
      ]) {
        final reason = "from $from to $to";
        Future<void> midGesture(Host host) async {
          if (to is CalendarEditPolicy<String>) {
            host.policy.value = to;
            await tester.pump();
          } else {
            host.time = host.time.add(const Duration(minutes: 1));
            await tester.pump(const Duration(minutes: 1));
          }
        }

        var host = await pumpWeek(tester, policy: from);
        final gesture = await liftTo(
          tester,
          tester.getCenter(blockFinder("M")),
          slotCenter(tester, tuesday, 14 * 60),
        );
        await midGesture(host);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(host.store.moves, hasLength(1), reason: reason);

        host = await pumpWeek(tester, policy: from);
        final range = await holdRange(
          tester,
          slotCenter(tester, thursday, 9 * 60),
          slotCenter(tester, thursday, 11 * 60),
        );
        await midGesture(host);
        await range.up();
        await tester.pumpAndSettle();
        expect(host.creates, <CreateRange>[
          CreateRange(start: at(thursday, 9), end: at(thursday, 11, 15)),
        ], reason: reason);
      }
    });
  });

  testWidgets("PV4 under the lock of earlier today, a minute that passes an "
      "entry's start takes its top grip in Week and its Delete in Agenda", (
    tester,
  ) async {
    const policy = HistoryLockPolicy<String>(lockEarlierToday: true);
    final entry = entryOf("L", at(tuesday, 14), at(tuesday, 15));
    var host = Host(
      storeOf(<CalendarEntry<String>>[entry]),
      view: CalendarViewKind.week,
      day: tuesday,
      time: at(tuesday, 13, 59),
      policy: policy,
    );
    await host.pump(tester);
    await select(tester, blockFinder("L"));
    expect(find.byKey(blockGripKey("L", AxisDirection.up)), findsOneWidget);
    host.time = at(tuesday, 14, 0, 30);
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(find.byKey(blockGripKey("L", AxisDirection.up)), findsNothing);
    // Setup sanity: the entry is still selected.
    expect(find.byKey(blockGripKey("L", AxisDirection.down)), findsOneWidget);

    host = Host(
      storeOf(<CalendarEntry<String>>[entry]),
      view: CalendarViewKind.agenda,
      day: tuesday,
      time: at(tuesday, 13, 59),
      policy: policy,
    );
    await host.pump(tester);
    expect(host.cards["L"]!.onDelete, isNotNull);
    host.time = at(tuesday, 14, 0, 30);
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(host.cards["L"]!.onDelete, isNull);
  });

  group("PV5", () {
    const lock = HistoryLockPolicy<String>(lockEarlierToday: true);

    Future<Host> pumpDay(
      WidgetTester tester, {
      required DateTime time,
      CalendarEditPolicy<String> policy = lock,
      DayHours hours = DayHours.allDay,
      List<CalendarEntry<String>> entries = const <CalendarEntry<String>>[],
    }) async {
      final host = Host(
        storeOf(entries, hours: hours),
        view: CalendarViewKind.day,
        day: tuesday,
        time: time,
        policy: policy,
        hours: hours,
      );
      await host.pump(tester);
      return host;
    }

    Offset slot(WidgetTester tester, int minute) {
      return slotCenter(tester, tuesday, minute, week: false);
    }

    testWidgets("a range held at the lock's boundary takes its new start "
        "at a minute that moves it, and one whose anchor the boundary "
        "passes moves its anchor", (tester) async {
      for (final minutePasses in const <bool>[false, true]) {
        // Pressed on 15:00 and dragged up to 13:00.
        var host = await pumpDay(tester, time: at(tuesday, 13, 59, 30));
        var gesture = await holdRange(
          tester,
          slot(tester, 15 * 60),
          slot(tester, 13 * 60),
        );
        if (minutePasses) {
          host.time = at(tuesday, 14, 0, 30);
          await tester.pump(const Duration(minutes: 1));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(host.creates, <CreateRange>[
          CreateRange(
            start: minutePasses ? at(tuesday, 14, 15) : at(tuesday, 14),
            end: at(tuesday, 15, 15),
          ),
        ], reason: "upward, minute passes: $minutePasses");

        // Pressed on 14:00 and dragged down to 15:00.
        host = await pumpDay(tester, time: at(tuesday, 13, 59, 30));
        gesture = await holdRange(
          tester,
          slot(tester, 14 * 60),
          slot(tester, 15 * 60),
        );
        if (minutePasses) {
          host.time = at(tuesday, 14, 0, 30);
          await tester.pump(const Duration(minutes: 1));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(host.creates, <CreateRange>[
          CreateRange(
            start: minutePasses ? at(tuesday, 14, 15) : at(tuesday, 14),
            end: at(tuesday, 15, 15),
          ),
        ], reason: "downward, minute passes: $minutePasses");
      }
    });

    testWidgets("with hours to 15:00 a range held at the 14:45 slot is "
        "refused once the boundary passes the hours' last slot, marking no "
        "range and creating nothing", (tester) async {
      const hours = DayHours(8 * 60, 15 * 60);
      for (final minutePasses in const <bool>[false, true]) {
        final host = await pumpDay(
          tester,
          time: at(tuesday, 14, 44, 30),
          hours: hours,
        );
        final gesture = await holdRange(
          tester,
          slot(tester, 14 * 60 + 45),
          slot(tester, 14 * 60 + 30),
        );
        if (minutePasses) {
          host.time = at(tuesday, 14, 45, 30);
          await tester.pump(const Duration(minutes: 1));
          await tester.pump();
          expect(marksRange(tester), isFalse);
        } else {
          // Setup sanity: the range is marked while it is held.
          expect(marksRange(tester), isTrue);
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          host.creates,
          minutePasses
              ? isEmpty
              : <CreateRange>[
                  CreateRange(start: at(tuesday, 14, 45), end: at(tuesday, 15)),
                ],
          reason: "minute passes: $minutePasses",
        );
      }
    });

    testWidgets("with overlaps refused, an anchor the boundary passes moves "
        "past an entry's slot and reads the next entry as its limit", (
      tester,
    ) async {
      for (final minutePasses in const <bool>[false, true]) {
        final host = await pumpDay(
          tester,
          time: at(tuesday, 13, 59, 30),
          policy: const HistoryLockPolicy<String>(
            lockEarlierToday: true,
            allowsOverlaps: false,
          ),
          entries: <CalendarEntry<String>>[
            entryOf("E", at(tuesday, 14, 15), at(tuesday, 14, 30)),
            entryOf("F", at(tuesday, 15, 30), at(tuesday, 16)),
          ],
        );
        final gesture = await holdRange(
          tester,
          slot(tester, 14 * 60),
          slot(tester, 16 * 60),
        );
        if (minutePasses) {
          host.time = at(tuesday, 14, 0, 30);
          await tester.pump(const Duration(minutes: 1));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(host.creates, <CreateRange>[
          minutePasses
              ? CreateRange(
                  start: at(tuesday, 14, 30),
                  end: at(tuesday, 15, 30),
                )
              : CreateRange(start: at(tuesday, 14), end: at(tuesday, 14, 15)),
        ], reason: "minute passes: $minutePasses");
      }
    });

    testWidgets("a refill that refuses the range shows at once, though the "
        "minute moves no now mark: with today pinned to Tuesday and the "
        "clock on Monday, Day's range at 14:45 stops being marked", (
      tester,
    ) async {
      const hours = DayHours(8 * 60, 15 * 60);
      final host = Host(
        storeOf(const <CalendarEntry<String>>[], hours: hours),
        view: CalendarViewKind.day,
        day: tuesday,
        time: at(monday, 14, 44, 30),
        policy: lock,
        hours: hours,
        today: tuesday,
      );
      await host.pump(tester);
      final gesture = await holdRange(
        tester,
        slot(tester, 14 * 60 + 45),
        slot(tester, 14 * 60 + 30),
      );
      // Setup sanity: the range is admitted and marked, and the grid shows
      // no line of the current time, whose day it does not show.
      expect(marksRange(tester), isTrue);
      host.time = at(monday, 14, 45, 30);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(marksRange(tester), isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(host.creates, isEmpty);
    });

    testWidgets("a refill that refuses a range across the strip clears its "
        "marked days: with today pinned to Tuesday and the clock at Monday "
        "00:00, Tuesday's day start is locked a minute later", (tester) async {
      final host = Host(
        storeOf(const <CalendarEntry<String>>[]),
        view: CalendarViewKind.week,
        day: tuesday,
        time: monday,
        policy: lock,
        today: tuesday,
      );
      await host.pump(tester);
      Color? fillOf(DateTime day) {
        final box = tester.widget<DecoratedBox>(find.byKey(allDayCellKey(day)));
        return (box.decoration as BoxDecoration).color;
      }

      final unmarked = fillOf(wednesday);
      final gesture = await holdRange(
        tester,
        tester.getCenter(find.byKey(allDayCellKey(tuesday))),
        tester.getCenter(find.byKey(allDayCellKey(thursday))),
      );
      // Setup sanity: the range marks the days it covers.
      expect(fillOf(wednesday), isNot(unmarked));
      host.time = at(monday, 0, 1);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(fillOf(wednesday), unmarked);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(host.creates, isEmpty);
    });

    testWidgets("a range a refill refused for the entries its column holds "
        "is admitted again once a store write frees a slot", (tester) async {
      const hours = DayHours(8 * 60, 15 * 60);
      for (final frees in const <bool>[false, true]) {
        final host = await pumpDay(
          tester,
          time: at(tuesday, 13, 59, 30),
          hours: hours,
          entries: <CalendarEntry<String>>[
            entryOf("X", at(tuesday, 14, 15), at(tuesday, 15)),
          ],
        );
        final from = slot(tester, 14 * 60);
        final gesture = await holdRange(
          tester,
          from,
          from + const Offset(2.0, 0.0),
        );
        host.time = at(tuesday, 14, 0, 30);
        await tester.pump(const Duration(minutes: 1));
        await tester.pump();
        // Setup sanity: no slot from 14:01 is free, so the range is
        // refused.
        expect(marksRange(tester), isFalse);
        if (frees) {
          host.store.requestDelete("X");
          await tester.pump();
          expect(marksRange(tester), isTrue);
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          host.creates,
          frees
              ? <CreateRange>[
                  CreateRange(
                    start: at(tuesday, 14, 15),
                    end: at(tuesday, 14, 30),
                  ),
                ]
              : isEmpty,
          reason: "frees: $frees",
        );
      }
    });
  });

  group("PV7", () {
    testWidgets("a change predicate that throws in a bar's landing on the "
        "slots is reported and refuses the landing", (tester) async {
      final bar = entryOf("G", tuesday, wednesday);
      final throwing = ScriptedEditPolicy<String>(
        admits: (entry, start, end) {
          if (entry.id == "G" && !(isDayStart(start) && isDayStart(end))) {
            throw const ScriptedThrow("admitsChange");
          }
          return true;
        },
      );
      for (final policy in <CalendarEditPolicy<String>?>[null, throwing]) {
        final host = Host(
          storeOf(<CalendarEntry<String>>[bar]),
          view: CalendarViewKind.week,
          day: tuesday,
          time: at(monday, 8),
          policy: policy,
        );
        await host.pump(tester);
        final rect = tester.getRect(barFinder("G"));
        await recordingErrors((errors) async {
          final gesture = await liftTo(
            tester,
            rect.center,
            slotCenter(tester, tuesday, 10 * 60),
          );
          await gesture.up();
          await tester.pumpAndSettle();
          if (policy == null) {
            // Setup sanity: the unrestricted policy lets the bar land.
            expect(host.store.moves, <CalendarEntry<String>>[
              bar.copyWith(start: at(tuesday, 10), end: at(tuesday, 11)),
            ]);
            expect(errors, isEmpty);
            return;
          }
          expect(host.store.moves, isEmpty);
          expect(near(tester.getRect(barFinder("G")), rect), isTrue);
          expect(errors, isNotEmpty);
          for (final error in errors) {
            expect(error.exception, const ScriptedThrow("admitsChange"));
          }
        });
      }
    });

    testWidgets("an earliest start that throws for a day before the "
        "anchor's, at the range's begin, is reported and the release "
        "creates nothing", (tester) async {
      for (final throwsOn in <DateTime?>[null, monday]) {
        final host = Host(
          storeOf(const <CalendarEntry<String>>[]),
          view: CalendarViewKind.week,
          day: tuesday,
          time: at(monday, 8),
          policy: ScriptedEditPolicy<String>(throwsOn: throwsOn),
        );
        await host.pump(tester);
        await recordingErrors((errors) async {
          final gesture = await holdRange(
            tester,
            slotCenter(tester, tuesday, 10 * 60),
            slotCenter(tester, tuesday, 11 * 60),
          );
          await gesture.up();
          await tester.pumpAndSettle();
          if (throwsOn == null) {
            // Setup sanity: with no throw the range creates.
            expect(host.creates, <CreateRange>[
              CreateRange(start: at(tuesday, 10), end: at(tuesday, 11, 15)),
            ]);
            expect(errors, isEmpty);
            return;
          }
          expect(host.creates, isEmpty);
          expect(errors, isNotEmpty);
          for (final error in errors) {
            expect(error.exception, const ScriptedThrow("earliestStartOn"));
          }
        });
      }
    });

    testWidgets("an earliest start that throws from a new minute on, at the "
        "range's refill, is reported and the release creates nothing", (
      tester,
    ) async {
      for (final minutePasses in const <bool>[false, true]) {
        final host = Host(
          storeOf(const <CalendarEntry<String>>[]),
          view: CalendarViewKind.day,
          day: tuesday,
          time: at(tuesday, 13, 59, 30),
          policy: ScriptedEditPolicy<String>(throwsFrom: at(tuesday, 14)),
        );
        await host.pump(tester);
        await recordingErrors((errors) async {
          final from = slotCenter(tester, tuesday, 15 * 60, week: false);
          final gesture = await holdRange(
            tester,
            from,
            from + const Offset(2.0, 0.0),
          );
          if (minutePasses) {
            host.time = at(tuesday, 14, 0, 30);
            await tester.pump(const Duration(minutes: 1));
          }
          await gesture.up();
          await tester.pumpAndSettle();
          if (!minutePasses) {
            // Setup sanity: released before the minute the range creates.
            expect(host.creates, <CreateRange>[
              CreateRange(start: at(tuesday, 15), end: at(tuesday, 15, 15)),
            ]);
            expect(errors, isEmpty);
            return;
          }
          expect(host.creates, isEmpty);
          expect(errors, isNotEmpty);
          for (final error in errors) {
            expect(error.exception, const ScriptedThrow("earliestStartOn"));
          }
        });
      }
    });
  });

  testWidgets("PV8 a create range reaching back across Thursday, whose "
      "earliest start is 10:00, starts on Wednesday where Wednesday's day "
      "allows it, and at Thursday 10:00 when it reaches back to Thursday", (
    tester,
  ) async {
    for (final (back, start) in <(DateTime, DateTime)>[
      (wednesday, at(wednesday, 9)),
      (thursday, at(thursday, 10)),
    ]) {
      final host = Host(
        storeOf(const <CalendarEntry<String>>[]),
        view: CalendarViewKind.week,
        day: tuesday,
        time: at(monday, 8),
        policy: pv1Policy(),
      );
      await host.pump(tester);
      final gesture = await holdRange(
        tester,
        slotCenter(tester, friday, 11 * 60),
        slotCenter(tester, back, 9 * 60),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(host.creates, <CreateRange>[
        CreateRange(start: start, end: at(friday, 11, 15)),
      ], reason: "back to $back");
    }
  });
}
