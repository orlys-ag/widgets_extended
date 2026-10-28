/// The timed grid's all-day strip: its bars, rows, count and expansion, the
/// gestures on bars within the strip, the crossings of a bar into the
/// slots, of a block into the strip and of Week's end handle into a later
/// day with their live marks, and the create ranges across the strip.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';
import 'package:widgets_extended/calendar/entries/calendar_data_source.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/edit_policy.dart';
import 'package:widgets_extended/calendar/policy/history_lock_policy.dart';
import 'package:widgets_extended/calendar/policy/overlap.dart';
import 'package:widgets_extended/calendar/presentation/calendar_activity_indicator.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/calendar/store/caching_calendar_store.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/views/entry_split.dart';
import 'package:widgets_extended/calendar/views/move_request.dart';
import 'package:widgets_extended/calendar/views/pinch_zoom.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/timed_grid_layout.dart';

import '../dst_days.dart';
import '../edit_policies.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);
final DateTime thursday = DateTime(2026, 4, 23);
final DateTime friday = DateTime(2026, 4, 24);
final DateTime saturday = DateTime(2026, 4, 25);
final DateTime sunday = DateTime(2026, 4, 26);
final DateTime nextMonday = DateTime(2026, 4, 27);

/// [day] at [hour] and [minute] by the wall clock.
DateTime at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

CalendarEntry<String> entryOf(
  String id,
  DateTime start,
  DateTime end, {
  String? title,
}) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: title ?? id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

/// An all-day entry over the [days] days from [first].
CalendarEntry<String> allDayOf(
  String id,
  DateTime first, {
  int days = 1,
  String? title,
}) {
  return entryOf(id, first, addDays(first, days), title: title);
}

/// A grid the tests pump: Week over the seven days from [first], under a
/// day header, or Day over [first] alone, with none; its slots of
/// [slotMinutes] over [hours].
class Shown {
  const Shown.week(
    this.first, {
    this.hours = DayHours.allDay,
    this.slotMinutes = 15,
  }) : week = true;

  const Shown.day(
    this.first, {
    this.hours = DayHours.allDay,
    this.slotMinutes = 15,
  }) : week = false;

  final DateTime first;
  final bool week;
  final DayHours hours;
  final int slotMinutes;

  /// The row of the all-day strip's first row: under the day header in
  /// Week, the grid's top row in Day.
  int get stripStart {
    return week ? 1 : 0;
  }

  /// The row of the first slot of the grid shown now: its board's row
  /// count less its slot rows and the room below them.
  int get firstSlotRow {
    final grid =
        find.byType(TimedGrid<String>).evaluate().single.widget
            as TimedGrid<String>;
    return rowCountNow() - grid.hours.slotCountOf(grid.slotMinutes) - 1;
  }

  /// The row of the slot starting at [minute] of the grid shown now.
  int rowOf(int minute) {
    final grid =
        find.byType(TimedGrid<String>).evaluate().single.widget
            as TimedGrid<String>;
    return firstSlotRow + (minute - grid.hours.start) ~/ grid.slotMinutes;
  }

  /// The column of [day], which the grid shows.
  int colOf(DateTime day) {
    return week ? 1 + daysBetween(first, day) : 1;
  }

  String get name {
    return week ? "Week" : "Day";
  }
}

/// The number of rows of the grid's board shown now.
int rowCountNow() {
  final board =
      find.byType(Board<GridKey, GridShape<String>>).evaluate().single.widget
          as Board<GridKey, GridShape<String>>;
  return board.controller.rows.axis.trackCount;
}

/// The grid's board widget.
Board<GridKey, GridShape<String>> boardOf(WidgetTester tester) {
  return tester.widget<Board<GridKey, GridShape<String>>>(
    find.byType(Board<GridKey, GridShape<String>>),
  );
}

/// The grid's viewport.
RenderBoardViewport<GridKey> viewportOf(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<GridKey>>()
      .single;
}

/// The global rect of the grid's cell at [row] and [col].
Rect cellRect(WidgetTester tester, int row, int col) {
  final viewport = viewportOf(tester);
  final rect = viewport.rectOfCell(row, col)!;
  return viewport.localToGlobal(rect.topLeft) & rect.size;
}

/// The global rect of [day]'s cell in the strip's row [row].
Rect stripRect(WidgetTester tester, Shown shown, DateTime day, [int row = 0]) {
  return cellRect(tester, shown.stripStart + row, shown.colOf(day));
}

/// The global rect of the slot starting at [minute] in [day]'s column.
Rect slotRect(WidgetTester tester, Shown shown, DateTime day, int minute) {
  return cellRect(tester, shown.rowOf(minute), shown.colOf(day));
}

/// The global rect of the first slot row's cell in [day]'s column.
Rect firstSlotRect(WidgetTester tester, Shown shown, DateTime day) {
  return cellRect(tester, shown.firstSlotRow, shown.colOf(day));
}

/// The global point at [local] in the viewport's paint space.
Offset globalOf(WidgetTester tester, Offset local) {
  return viewportOf(tester).localToGlobal(local);
}

/// The bar of [id].
Finder barFinder(String id) {
  return find.byKey(allDayBarKey(id));
}

/// The block of [id]'s piece on [day].
Finder blockFinder(String id, DateTime day) {
  return find.byKey(blockKey(id, day));
}

/// Every block of [id], on whichever day.
Finder blocksOf(String id) {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith("block-$id@");
  });
}

/// Every bar the grid has built.
Finder allBars() {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith("grid-all-day-bar-");
  });
}

/// Whether [day]'s cell in the strip's first row is marked.
bool isMarked(WidgetTester tester, DateTime day) {
  final box = tester.widget<DecoratedBox>(find.byKey(allDayCellKey(day)));
  return (box.decoration as BoxDecoration).color ==
      const CalendarThemeData().primaryTint;
}

/// The days of [days] whose strip cell in the first row is marked.
List<DateTime> markedOf(WidgetTester tester, List<DateTime> days) {
  return <DateTime>[
    for (final day in days)
      if (isMarked(tester, day)) day,
  ];
}

/// What the landing label says, or null where none shows.
String? landingText(WidgetTester tester) {
  final label = find.descendant(
    of: find.byKey(landingLabelKey),
    matching: find.byType(Text),
  );
  if (label.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<Text>(label).data;
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
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return null;
  }
}

/// The rects the grid's background strokes, a range of slots or a landing
/// outline, in the viewport's paint space.
List<Rect> strokedRects(WidgetTester tester) {
  final viewport = viewportOf(tester);
  final canvas = RecordingCanvas();
  viewport.background!.paint(canvas, viewport);
  return <Rect>[
    for (final record in canvas.rects)
      if (record.paint.style == PaintingStyle.stroke) record.rect,
  ];
}

/// The union, in the viewport's paint space, of the cells of the slots of
/// [day]'s column from [from] up to [to], minutes after midnight.
Rect slotsRect(
  WidgetTester tester,
  Shown shown,
  DateTime day,
  int from,
  int to,
) {
  final viewport = viewportOf(tester);
  final col = shown.colOf(day);
  final first = viewport.rectOfCell(shown.rowOf(from), col)!;
  final last = viewport.rectOfCell(shown.rowOf(to - 15), col)!;
  return first.expandToInclude(last);
}

/// Whether [a] and [b] lie within 1 px of each other on every edge.
Matcher nearRect(Rect expected) {
  return _NearRect(expected);
}

class _NearRect extends Matcher {
  const _NearRect(this.expected);

  final Rect expected;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    if (item is! Rect) {
      return false;
    }
    return (item.left - expected.left).abs() <= 1.0 &&
        (item.top - expected.top).abs() <= 1.0 &&
        (item.right - expected.right).abs() <= 1.0 &&
        (item.bottom - expected.bottom).abs() <= 1.0;
  }

  @override
  Description describe(Description description) {
    return description.add("within 1 px of $expected");
  }
}

/// The range of days, as [MoveRecordingStore.reads] records it, from [first]
/// to [last].
({int first, int last}) daysOf(DateTime first, DateTime last) {
  return (first: dayNumber(first), last: dayNumber(last));
}

/// A store holding [entries], disposed at the test's end.
MoveRecordingStore storeOf(
  List<CalendarEntry<String>> entries, {
  DayHours hours = DayHours.allDay,
}) {
  final store = MoveRecordingStore(entries: entries, hours: hours);
  addTearDown(store.dispose);
  return store;
}

/// A data source that answers each read with the entries having any part
/// in its days, at once, or for a read of a day of [held] when the test
/// completes it ([release]); and holds each replace until the test
/// completes it.
class HeldSource implements CalendarDataSource<String> {
  HeldSource(this.entries, {this.held = const <DateTime>[]});

  final List<CalendarEntry<String>> entries;
  final List<DateTime> held;

  final List<Completer<List<CalendarEntry<String>>>> reads =
      <Completer<List<CalendarEntry<String>>>>[];

  final List<Completer<CalendarEntry<String>>> replaces =
      <Completer<CalendarEntry<String>>>[];

  List<CalendarEntry<String>> _between(int from, int to) {
    return <CalendarEntry<String>>[
      for (final entry in entries)
        if (dayNumber(entry.start) <= to &&
            lastDayNumberOf(entry.start, entry.end) >= from)
          entry,
    ];
  }

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    final from = dayNumber(first);
    final to = dayNumber(last);
    final holds = held.any((day) {
      final number = dayNumber(day);
      return number >= from && number <= to;
    });
    if (!holds) {
      return SynchronousFuture<List<CalendarEntry<String>>>(_between(from, to));
    }
    final completer = Completer<List<CalendarEntry<String>>>();
    reads.add(completer);
    return completer.future;
  }

  /// Answers every held read.
  void release(DateTime first, DateTime last) {
    for (final read in reads) {
      read.complete(_between(dayNumber(first), dayNumber(last)));
    }
    reads.clear();
  }

  @override
  Future<CalendarEntry<String>> create(CalendarEntry<String> draft) {
    throw UnimplementedError();
  }

  @override
  Future<CalendarEntry<String>> replace(CalendarEntry<String> entry) {
    final completer = Completer<CalendarEntry<String>>();
    replaces.add(completer);
    return completer.future;
  }

  @override
  Future<void> delete(String id) {
    return SynchronousFuture<void>(null);
  }
}

/// What a test pumps: the grid of [shown] over [store], in a view of
/// [size], 800 wide and 2000 tall by default, where every slot of the day
/// shows at the default [minSlotHeight] and every day column at the
/// default [minDayWidth]; [creates] records each create range it reports
/// and [opened] each entry it opens, and [onMoveRequest] takes each move
/// and resize it lands. [editable], [first], [hours] and [slotMinutes]
/// start as given, and [rebuild] builds the grid again with them. The
/// grid's policy is [editPolicy] where it is given, and otherwise the one
/// [lockPast], [lockEarlierToday], [maxDayCount] and [allowsOverlaps]
/// make ([policy]).
class Harness {
  Harness(
    this.store,
    this.shown, {
    this.maxDayCount,
    this.editable = true,
    this.lockPast = false,
    this.lockEarlierToday = false,
    this.allowsOverlaps = true,
    this.editPolicy,
    this.minSlotHeight = defaultMinSlotHeight,
    this.minDayWidth = minDayWidthLow,
    this.size = const Size(800.0, 2000.0),
    this.onMoveRequest,
    DateTime? today,
    int nowHour = 9,
  }) : today = today ?? DateTime(2026, 1, 5),
       _nowHour = nowHour,
       first = shown.first,
       hours = shown.hours,
       slotMinutes = shown.slotMinutes;

  final CalendarStore<String> store;
  final Shown shown;
  final int? maxDayCount;
  final bool lockPast;
  final bool lockEarlierToday;
  final bool allowsOverlaps;
  final CalendarEditPolicy<String>? editPolicy;
  final double minSlotHeight;
  final double minDayWidth;
  final Size size;
  final DateTime today;
  final Future<void> Function(CalendarMoveRequest<String> request)?
  onMoveRequest;

  bool editable;
  DateTime first;
  DayHours hours;
  int slotMinutes;

  final List<CreateRange> creates = <CreateRange>[];
  final List<String> opened = <String>[];
  final int _nowHour;
  late final ValueNotifier<CalendarNow> now = ValueNotifier<CalendarNow>(
    CalendarNow(time: at(today, _nowHour), today: today),
  );

  /// [editPolicy], or with none the history lock under [lockPast], with
  /// [lockEarlierToday], and the unrestricted policy otherwise, each
  /// combined with a [DayLimitPolicy] of [maxDayCount] where it is given
  /// and with a [NoOverlapsPolicy] where [allowsOverlaps] is false.
  CalendarEditPolicy<String> get policy {
    final given = editPolicy;
    if (given != null) {
      return given;
    }
    final limit = maxDayCount;
    return CalendarEditPolicy<String>.all(<CalendarEditPolicy<String>>[
      if (lockPast)
        HistoryLockPolicy<String>(lockEarlierToday: lockEarlierToday)
      else
        const UnrestrictedEditPolicy<String>(),
      if (limit != null) DayLimitPolicy<String>(limit),
      if (!allowsOverlaps) const NoOverlapsPolicy<String>(),
    ]);
  }

  TimedGrid<String> grid() {
    return TimedGrid<String>(
      key: ObjectKey(this),
      store: store,
      firstDay: first,
      dayCount: shown.week ? 7 : 1,
      selectedDay: first,
      now: now,
      onSelectDay: (day) {},
      onOpenEntry: opened.add,
      onCreate: (range) async {
        creates.add(range);
      },
      onMoveRequest: onMoveRequest,
      editable: editable,
      editPolicy: policy,
      hours: hours,
      slotMinutes: slotMinutes,
      minSlotHeight: minSlotHeight,
      minDayWidth: minDayWidth,
      showsDayHeader: shown.week,
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    addTearDown(now.dispose);
    await tester.pumpWidget(MaterialApp(home: grid()));
    await tester.pumpAndSettle();
  }

  /// Builds the grid again with the fields as they are now, and pumps one
  /// frame.
  Future<void> rebuild(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: grid()));
  }
}

/// The two grids most tests run in: Week from Monday, and Day over
/// Tuesday.
List<Shown> bothGrids({DayHours hours = DayHours.allDay}) {
  return <Shown>[
    Shown.week(monday, hours: hours),
    Shown.day(tuesday, hours: hours),
  ];
}

/// Long-presses [at], lifting the block or bar there, and returns the
/// gesture.
Future<TestGesture> lift(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at);
  await tester.pump(kLongPressTimeout + kPressTimeout);
  return gesture;
}

/// Lifts what lies at [from], moves the pointer to [to] in two steps, and
/// pumps a frame after each.
Future<TestGesture> liftTo(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await lift(tester, from);
  await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  return gesture;
}

/// [liftTo], then lets go and lets the drop settle.
Future<void> dragTo(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await liftTo(tester, from, to);
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Selects the bar of [id] with a long press let go in place.
Future<void> selectBar(WidgetTester tester, String id) async {
  final gesture = await lift(tester, tester.getCenter(barFinder(id)));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// A mouse press at [from] dragged to [to] and let go: a create drag.
Future<void> createDrag(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The point 4 px inside the bar of [id]'s edge on [side], at its middle:
/// over the strip inside the selected bar that resizes that edge.
Offset edgeOf(WidgetTester tester, String id, AxisDirection side) {
  final rect = tester.getRect(barFinder(id));
  return side == AxisDirection.left
      ? Offset(rect.left + 4.0, rect.center.dy)
      : Offset(rect.right - 4.0, rect.center.dy);
}

/// Drags the selected bar of [id]'s edge on [side] from [edgeOf] so the
/// pointer lies over [to], and returns the gesture still held.
Future<TestGesture> holdEdge(
  WidgetTester tester,
  String id,
  AxisDirection side,
  Offset to,
) async {
  final from = edgeOf(tester, id, side);
  final gesture = await tester.startGesture(from);
  await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  return gesture;
}

/// The entry [id] as [store] holds it.
CalendarEntry<String> storedOf(CalendarStore<String> store, String id) {
  return store.storedEntry(id)!;
}

/// Expects [store] to hold [id] from [start] to [end].
void expectTimes(
  CalendarStore<String> store,
  String id,
  DateTime start,
  DateTime end, {
  String? reason,
}) {
  final entry = storedOf(store, id);
  expect((entry.start, entry.end), (start, end), reason: reason);
}

/// TX1's gesture: in Week, Monday's one-day bar moved two columns.
Future<MoveRecordingStore> moveBarTwoColumns(
  WidgetTester tester, {
  DayHours hours = DayHours.allDay,
  Future<void> Function(CalendarMoveRequest<String> request)? onMoveRequest,
}) async {
  final shown = Shown.week(monday, hours: hours);
  final store = storeOf(<CalendarEntry<String>>[
    allDayOf("off", monday),
  ], hours: hours);
  await Harness(store, shown, onMoveRequest: onMoveRequest).pump(tester);
  final gesture = await liftTo(
    tester,
    tester.getCenter(barFinder("off")),
    stripRect(tester, shown, wednesday).center,
  );
  // Setup sanity: the bar lifted.
  expect(find.byKey(liftedBlockKey), findsOneWidget);
  await gesture.up();
  await tester.pumpAndSettle();
  return store;
}

/// TX2's gesture: in Week, the leading edge of Tuesday and Wednesday's bar
/// let go over Monday.
Future<MoveRecordingStore> resizeBarStart(
  WidgetTester tester, {
  Future<void> Function(CalendarMoveRequest<String> request)? onMoveRequest,
}) async {
  final shown = Shown.week(monday);
  final store = storeOf(<CalendarEntry<String>>[
    allDayOf("trip", tuesday, days: 2),
  ]);
  await Harness(store, shown, onMoveRequest: onMoveRequest).pump(tester);
  await selectBar(tester, "trip");
  final gesture = await holdEdge(
    tester,
    "trip",
    AxisDirection.left,
    Offset(
      stripRect(tester, shown, monday).left + 4.0,
      tester.getCenter(barFinder("trip")).dy,
    ),
  );
  await gesture.up();
  await tester.pumpAndSettle();
  return store;
}

/// TX3's gesture: in Week, the trailing edge of Tuesday and Wednesday's bar
/// let go over Thursday.
Future<MoveRecordingStore> resizeBarEnd(
  WidgetTester tester, {
  Future<void> Function(CalendarMoveRequest<String> request)? onMoveRequest,
}) async {
  final shown = Shown.week(monday);
  final store = storeOf(<CalendarEntry<String>>[
    allDayOf("trip", tuesday, days: 2),
  ]);
  await Harness(store, shown, onMoveRequest: onMoveRequest).pump(tester);
  await selectBar(tester, "trip");
  final gesture = await holdEdge(
    tester,
    "trip",
    AxisDirection.right,
    Offset(
      stripRect(tester, shown, thursday).right - 4.0,
      tester.getCenter(barFinder("trip")).dy,
    ),
  );
  await gesture.up();
  await tester.pumpAndSettle();
  return store;
}

/// TX4's first gesture: Tuesday's bar let go on Tuesday's 10:00 slot.
Future<MoveRecordingStore> dropBarOnSlot(
  WidgetTester tester,
  Shown shown, {
  Future<void> Function(CalendarMoveRequest<String> request)? onMoveRequest,
}) async {
  final store = storeOf(<CalendarEntry<String>>[allDayOf("off", tuesday)]);
  await Harness(store, shown, onMoveRequest: onMoveRequest).pump(tester);
  await dragTo(
    tester,
    tester.getCenter(barFinder("off")),
    slotRect(tester, shown, tuesday, 10 * 60).center,
  );
  return store;
}

/// TX4's second gesture: Monday to Wednesday's bar, grabbed at its last
/// day in Week and near its right end in Day, let go with the finger on
/// Tuesday's 10:00 slot.
Future<MoveRecordingStore> dropWideBarOnSlot(
  WidgetTester tester,
  Shown shown,
) async {
  final store = storeOf(<CalendarEntry<String>>[
    allDayOf("trip", monday, days: 3),
  ]);
  await Harness(store, shown).pump(tester);
  final bar = tester.getRect(barFinder("trip"));
  final grab = shown.week
      ? stripRect(tester, shown, wednesday).center
      : Offset(bar.right - 20.0, bar.center.dy);
  await dragTo(tester, grab, slotRect(tester, shown, tuesday, 10 * 60).center);
  return store;
}

/// TX5's gesture: Tuesday's 10:00 to 11:00 block let go on Tuesday's strip
/// cell, which a bar of another all-day entry covers.
Future<MoveRecordingStore> dropBlockOnStrip(
  WidgetTester tester,
  Shown shown, {
  Future<void> Function(CalendarMoveRequest<String> request)? onMoveRequest,
}) async {
  final store = storeOf(<CalendarEntry<String>>[
    entryOf("meet", at(tuesday, 10), at(tuesday, 11)),
    allDayOf("other", tuesday),
  ]);
  await Harness(store, shown, onMoveRequest: onMoveRequest).pump(tester);
  await dragTo(
    tester,
    tester.getCenter(blockFinder("meet", tuesday)),
    stripRect(tester, shown, tuesday).center,
  );
  return store;
}

/// TX11's gesture: with no all-day entry in range, Tuesday's 10:00 to
/// 11:00 block let go on the edit mode's empty strip cell of Tuesday.
Future<MoveRecordingStore> dropBlockOnEmptyRow(
  WidgetTester tester,
  Shown shown,
) async {
  final store = storeOf(<CalendarEntry<String>>[
    entryOf("meet", at(tuesday, 10), at(tuesday, 11)),
  ]);
  await Harness(store, shown).pump(tester);
  await dragTo(
    tester,
    tester.getCenter(blockFinder("meet", tuesday)),
    tester.getCenter(find.byKey(allDayCellKey(tuesday))),
  );
  return store;
}

/// TX8's gesture: in Week, under [limit], the selected one-day bar of [id]
/// on [day] has its edge on [side] dragged so the pointer lies over
/// [over], with [others] in the strip too; returns the gesture still held
/// and the store.
Future<(TestGesture, MoveRecordingStore)> holdBarEdge(
  WidgetTester tester, {
  required int? limit,
  required String id,
  required DateTime day,
  required AxisDirection side,
  required DateTime over,
  List<CalendarEntry<String>> others = const <CalendarEntry<String>>[],
  Future<void> Function(CalendarMoveRequest<String> request)? onMoveRequest,
}) async {
  final shown = Shown.week(monday);
  final store = storeOf(<CalendarEntry<String>>[allDayOf(id, day), ...others]);
  await Harness(
    store,
    shown,
    maxDayCount: limit,
    onMoveRequest: onMoveRequest,
  ).pump(tester);
  await selectBar(tester, id);
  final cell = stripRect(tester, shown, over);
  final gesture = await holdEdge(
    tester,
    id,
    side,
    Offset(
      side == AxisDirection.left ? cell.left + 4.0 : cell.right - 4.0,
      tester.getCenter(barFinder(id)).dy,
    ),
  );
  return (gesture, store);
}

/// TX8's releases: the limit, the bar, its day, the edge dragged and the
/// day the pointer is let go over.
final List<(int?, String, DateTime, AxisDirection, DateTime)> tx8Releases =
    <(int?, String, DateTime, AxisDirection, DateTime)>[
      (3, "m", monday, AxisDirection.right, thursday),
      (3, "m", monday, AxisDirection.right, saturday),
      (3, "m", monday, AxisDirection.right, wednesday),
      (3, "f", friday, AxisDirection.left, tuesday),
      (null, "m", monday, AxisDirection.right, saturday),
      (null, "f", friday, AxisDirection.left, monday),
    ];

/// [holdBarEdge], let go.
Future<MoveRecordingStore> releaseBarEdge(
  WidgetTester tester, {
  required int? limit,
  required String id,
  required DateTime day,
  required AxisDirection side,
  required DateTime over,
  List<CalendarEntry<String>> others = const <CalendarEntry<String>>[],
  Future<void> Function(CalendarMoveRequest<String> request)? onMoveRequest,
}) async {
  final (gesture, store) = await holdBarEdge(
    tester,
    limit: limit,
    id: id,
    day: day,
    side: side,
    over: over,
    others: others,
    onMoveRequest: onMoveRequest,
  );
  await gesture.up();
  await tester.pumpAndSettle();
  return store;
}

/// Monday 22:00 to Tuesday 02:00, whose end handle the LD tests drag.
CalendarEntry<String> nightEntry() {
  return entryOf("night", at(monday, 22), at(tuesday, 2));
}

/// The LD tests' gesture: in Week, under [limit], the entry [id] of
/// [entries] selected and the end grip of its last piece, on [day],
/// pressed 2 px above that block's bottom, on the grip's half inside the
/// block, or with [outside] 2 px below it, on the half outside; then
/// dragged so the pointer lies over the slot starting at [minute] in
/// [over]'s column. Returns the gesture still held, the store and the
/// harness.
Future<(TestGesture, MoveRecordingStore, Harness)> holdEndOver(
  WidgetTester tester, {
  required List<CalendarEntry<String>> entries,
  required String id,
  required DateTime day,
  required DateTime over,
  required int minute,
  int? limit,
  bool outside = false,
  Future<void> Function(CalendarMoveRequest<String> request)? onMoveRequest,
}) async {
  final shown = Shown.week(monday);
  final store = storeOf(entries);
  final harness = Harness(
    store,
    shown,
    maxDayCount: limit,
    onMoveRequest: onMoveRequest,
  );
  await harness.pump(tester);
  final selecting = await lift(tester, tester.getCenter(blocksOf(id).first));
  await selecting.up();
  await tester.pumpAndSettle();
  // Setup sanity: the entry is selected, and the block on [day] holds its
  // end grip.
  expect(
    find.descendant(
      of: blockFinder(id, day),
      matching: find.byKey(blockGripKey(id, AxisDirection.down)),
    ),
    findsOneWidget,
  );
  final block = tester.getRect(blockFinder(id, day));
  final from = Offset(block.center.dx, block.bottom + (outside ? 2.0 : -2.0));
  final viewport = viewportOf(tester);
  // Setup sanity: the press lies over the block, or with [outside] over
  // no block, where only the grid's listener hands it to the handles.
  expect(
    viewport.itemAt(viewport.globalToLocal(from)),
    outside ? isNull : isNotNull,
  );
  final to = slotRect(tester, shown, over, minute).center;
  final gesture = await tester.startGesture(from);
  await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  return (gesture, store, harness);
}

/// [holdEndOver], let go.
Future<MoveRecordingStore> releaseEndOver(
  WidgetTester tester, {
  required List<CalendarEntry<String>> entries,
  required String id,
  required DateTime day,
  required DateTime over,
  required int minute,
  int? limit,
  bool outside = false,
  Future<void> Function(CalendarMoveRequest<String> request)? onMoveRequest,
}) async {
  final (gesture, store, _) = await holdEndOver(
    tester,
    entries: entries,
    id: id,
    day: day,
    over: over,
    minute: minute,
    limit: limit,
    outside: outside,
    onMoveRequest: onMoveRequest,
  );
  await gesture.up();
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets("TS1 the strip lies under the header, or at the grid's top in "
      "Day, and above the first slot, and its bars keep their rects while "
      "the hours scroll", (tester) async {
    for (final shown in bothGrids()) {
      final store = storeOf(<CalendarEntry<String>>[allDayOf("off", tuesday)]);
      await Harness(store, shown, size: const Size(800.0, 600.0)).pump(tester);
      final cell = tester.getRect(find.byKey(allDayCellKey(tuesday)));
      final top = shown.week
          ? tester.getRect(find.byKey(dayHeaderKey(tuesday))).bottom
          : tester.getTopLeft(find.byType(TimedGrid<String>)).dy;
      expect(cell.top, moreOrLessEquals(top), reason: shown.name);
      final bar = tester.getRect(barFinder("off"));
      expect(bar, nearRect(cell), reason: shown.name);
      final viewport = viewportOf(tester);
      final vertical = viewport.verticalPosition!;
      vertical.jumpTo(0.0);
      await tester.pump();
      expect(
        firstSlotRect(tester, shown, tuesday).top,
        greaterThanOrEqualTo(cell.bottom),
        reason: shown.name,
      );
      // Setup sanity: the hours scroll.
      expect(vertical.maxScrollExtent, greaterThan(300.0), reason: shown.name);
      vertical.jumpTo(300.0);
      await tester.pump();
      expect(vertical.pixels, 300.0, reason: shown.name);
      expect(tester.getRect(barFinder("off")), bar, reason: shown.name);
      expect(
        tester.getRect(find.byKey(allDayCellKey(tuesday))),
        cell,
        reason: shown.name,
      );
    }
  });

  testWidgets("TS2 a bar spans its shown days' columns", (tester) async {
    const shown = Shown.week;
    final week = shown(monday);
    final store = storeOf(<CalendarEntry<String>>[
      allDayOf("trip", monday, days: 3),
    ]);
    await Harness(store, week).pump(tester);
    final bar = tester.getRect(barFinder("trip"));
    final first = stripRect(tester, week, monday);
    final last = stripRect(tester, week, wednesday);
    expect(bar, nearRect(first.expandToInclude(last)));
  });

  testWidgets("TS3 bars sharing a day take separate rows", (tester) async {
    for (final shown in bothGrids()) {
      final store = storeOf(<CalendarEntry<String>>[
        allDayOf("a", tuesday),
        allDayOf("b", tuesday),
      ]);
      await Harness(store, shown).pump(tester);
      expect(
        tester.getRect(barFinder("a")),
        nearRect(stripRect(tester, shown, tuesday)),
        reason: shown.name,
      );
      expect(
        tester.getRect(barFinder("b")),
        nearRect(stripRect(tester, shown, tuesday, 1)),
        reason: shown.name,
      );
    }
  });

  testWidgets("TS4 a day needing five rows shows 3 and a \"+2\" pill", (
    tester,
  ) async {
    for (final shown in bothGrids()) {
      final store = storeOf(<CalendarEntry<String>>[
        for (final id in const <String>["a", "b", "c", "d", "e"])
          allDayOf(id, tuesday),
      ]);
      await Harness(store, shown).pump(tester);
      for (final (index, id) in const <String>["a", "b", "c"].indexed) {
        expect(
          tester.getRect(barFinder(id)),
          nearRect(stripRect(tester, shown, tuesday, index)),
          reason: "${shown.name} $id",
        );
      }
      expect(barFinder("d"), findsNothing, reason: shown.name);
      expect(barFinder("e"), findsNothing, reason: shown.name);
      final more = find.byKey(allDayMoreKey(tuesday));
      expect(
        find.descendant(of: more, matching: find.text("+2")),
        findsOneWidget,
        reason: shown.name,
      );
      expect(
        tester.getRect(more).center.dy,
        moreOrLessEquals(stripRect(tester, shown, tuesday, 3).center.dy),
        reason: shown.name,
      );
      // Three rows and the count row lie above the slots.
      expect(shown.firstSlotRow, shown.stripStart + 4 + 1, reason: shown.name);
    }
  });

  testWidgets("TS5 a tap on the pill shows every row", (tester) async {
    final semantics = tester.ensureSemantics();
    for (final shown in bothGrids()) {
      final store = storeOf(<CalendarEntry<String>>[
        for (final id in const <String>["a", "b", "c", "d", "e"])
          allDayOf(id, tuesday),
      ]);
      await Harness(store, shown).pump(tester);
      expect(
        tester.getSemantics(find.byKey(allDayMoreKey(tuesday))),
        matchesSemantics(
          label: allDayMoreLabel(2),
          isButton: true,
          hasTapAction: true,
        ),
        reason: shown.name,
      );
      expect(find.byKey(allDayLessKey), findsNothing, reason: shown.name);
      await tester.tap(find.byKey(allDayMoreKey(tuesday)));
      await tester.pumpAndSettle();
      for (final (index, id) in const <String>[
        "a",
        "b",
        "c",
        "d",
        "e",
      ].indexed) {
        expect(
          tester.getRect(barFinder(id)),
          nearRect(stripRect(tester, shown, tuesday, index)),
          reason: "${shown.name} $id",
        );
      }
      expect(find.byKey(allDayMoreKey(tuesday)), findsNothing);
      expect(shown.firstSlotRow, shown.stripStart + 5 + 1, reason: shown.name);
    }
    semantics.dispose();
  });

  testWidgets("TS6 a tap on Less shows 3", (tester) async {
    final semantics = tester.ensureSemantics();
    for (final shown in bothGrids()) {
      final store = storeOf(<CalendarEntry<String>>[
        for (final id in const <String>["a", "b", "c", "d", "e"])
          allDayOf(id, tuesday),
      ]);
      await Harness(store, shown).pump(tester);
      await tester.tap(find.byKey(allDayMoreKey(tuesday)));
      await tester.pumpAndSettle();
      final less = find.byKey(allDayLessKey);
      // In the first strip row's gutter cell.
      expect(
        tester.getRect(less).center.dy,
        moreOrLessEquals(stripRect(tester, shown, tuesday).center.dy),
        reason: shown.name,
      );
      expect(
        tester.getRect(less).center.dx,
        lessThan(stripRect(tester, shown, tuesday).left),
        reason: shown.name,
      );
      expect(
        tester.getSemantics(less),
        matchesSemantics(
          label: allDayLessLabel,
          isButton: true,
          hasTapAction: true,
        ),
        reason: shown.name,
      );

      await tester.tap(less);
      await tester.pumpAndSettle();
      expect(allBars(), findsNWidgets(3), reason: shown.name);
      expect(barFinder("d"), findsNothing, reason: shown.name);
      expect(find.byKey(allDayMoreKey(tuesday)), findsOneWidget);
      expect(find.byKey(allDayLessKey), findsNothing, reason: shown.name);
      expect(shown.firstSlotRow, shown.stripStart + 4 + 1, reason: shown.name);
    }
    semantics.dispose();
  });

  testWidgets("TS7 with no all-day entry in range, outside edit mode no "
      "strip cell is built and the slots start under the header and the "
      "room, and in edit mode the strip's one row lies there, the slots "
      "lower by its height", (tester) async {
    for (final shown in bothGrids()) {
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("timed", at(tuesday, 10), at(tuesday, 11)),
      ]);
      final harness = Harness(store, shown, editable: false);
      await harness.pump(tester);
      final top = shown.week
          ? tester.getRect(find.byKey(dayHeaderKey(tuesday))).bottom
          : tester.getTopLeft(find.byType(TimedGrid<String>)).dy;
      expect(find.byKey(allDayCellKey(tuesday)), findsNothing);
      final room = cellRect(tester, shown.firstSlotRow - 1, 1);
      expect(room.top, moreOrLessEquals(top), reason: shown.name);
      final viewing = firstSlotRect(tester, shown, tuesday).top;
      expect(viewing, moreOrLessEquals(top + room.height), reason: shown.name);

      harness.editable = true;
      await harness.rebuild(tester);
      await tester.pumpAndSettle();
      final cell = tester.getRect(find.byKey(allDayCellKey(tuesday)));
      expect(cell.top, moreOrLessEquals(top), reason: shown.name);
      expect(
        firstSlotRect(tester, shown, tuesday).top,
        moreOrLessEquals(viewing + cell.height),
        reason: shown.name,
      );
      // The block moved with its slot.
      expect(
        tester.getRect(blockFinder("timed", tuesday)).top,
        moreOrLessEquals(slotRect(tester, shown, tuesday, 10 * 60).top),
        reason: shown.name,
      );
    }
  });

  testWidgets("TS8 an entry from a day start to the next is a bar and no "
      "block", (tester) async {
    for (final shown in bothGrids()) {
      final store = storeOf(<CalendarEntry<String>>[allDayOf("off", tuesday)]);
      await Harness(store, shown).pump(tester);
      expect(barFinder("off"), findsOneWidget, reason: shown.name);
      expect(blocksOf("off"), findsNothing, reason: shown.name);
    }
  });

  group("on the DST days", () {
    testWidgets(
      "TS9 an all-day entry on the 23-hour day is a bar",
      skip: shortDaySkip != null,
      (tester) async {
        final day = shortDayStart;
        for (final shown in <Shown>[
          Shown.week(addDays(day, -6)),
          Shown.day(day),
        ]) {
          final store = storeOf(<CalendarEntry<String>>[allDayOf("dst", day)]);
          await Harness(store, shown).pump(tester);
          expect(blocksOf("dst"), findsNothing, reason: shown.name);
          expect(
            tester.getRect(barFinder("dst")),
            nearRect(stripRect(tester, shown, day)),
            reason: shown.name,
          );
        }
      },
    );

    testWidgets(
      "TS9 an all-day entry on the 25-hour day is a bar",
      skip: longDaySkip != null,
      (tester) async {
        final day = longDayStart;
        for (final shown in <Shown>[
          Shown.week(addDays(day, -6)),
          Shown.day(day),
        ]) {
          final store = storeOf(<CalendarEntry<String>>[allDayOf("dst", day)]);
          await Harness(store, shown).pump(tester);
          expect(blocksOf("dst"), findsNothing, reason: shown.name);
          expect(
            tester.getRect(barFinder("dst")),
            nearRect(stripRect(tester, shown, day)),
            reason: shown.name,
          );
        }
      },
    );
  });

  testWidgets("TS10 a store notify that adds a strip row during a create "
      "drag detaches it, and its release reports nothing", (tester) async {
    for (final shown in bothGrids()) {
      final store = storeOf(<CalendarEntry<String>>[allDayOf("a", tuesday)]);
      final harness = Harness(store, shown);
      await harness.pump(tester);
      final from = slotRect(tester, shown, tuesday, 10 * 60).center;
      final to = slotRect(tester, shown, tuesday, 12 * 60).center;
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      // Setup sanity: the range runs and is marked.
      expect(strokedRects(tester), isNotEmpty, reason: shown.name);
      final rows = rowCountNow();
      store.entries = <CalendarEntry<String>>[
        ...store.entries,
        allDayOf("b", tuesday),
      ];
      await tester.pump();
      expect(rowCountNow(), rows + 1, reason: shown.name);
      expect(strokedRects(tester), isEmpty, reason: shown.name);
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.creates, isEmpty, reason: shown.name);
    }
  });

  testWidgets("TS11 over a caching store, a step to an unread week keeps the "
      "first slot's top through the frames before the read lands", (
    tester,
  ) async {
    final source = HeldSource(
      <CalendarEntry<String>>[allDayOf("a", tuesday), allDayOf("b", tuesday)],
      held: <DateTime>[nextMonday],
    );
    final store = CachingCalendarStore<String>(dataSource: source);
    addTearDown(store.dispose);
    store.show(monday, sunday);
    const shown = Shown.week;
    final harness = Harness(store, shown(monday));
    await harness.pump(tester);
    final week = shown(monday);
    // Setup sanity: two bar rows lie above the slots.
    expect(week.firstSlotRow, week.stripStart + 2 + 1);
    final top = cellRect(tester, week.firstSlotRow, 1).top;

    store.show(nextMonday, addDays(nextMonday, 6));
    harness.first = nextMonday;
    await harness.rebuild(tester);
    for (var frame = 0; frame < 5; frame++) {
      expect(cellRect(tester, week.firstSlotRow, 1).top, top, reason: "$frame");
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Setup sanity: the read has not landed.
    expect(source.reads, isNotEmpty);
    source.release(nextMonday, addDays(nextMonday, 6));
    await tester.pumpAndSettle();
    // The new week's empty strip has the edit mode's one row.
    expect(week.firstSlotRow, week.stripStart + 1 + 1);
    expect(cellRect(tester, week.firstSlotRow, 1).top, lessThan(top));
  });

  testWidgets("TS12 with more strip rows than the grid's height holds, "
      "expanded, the Less pill in the first strip row's gutter is hit and "
      "collapses the strip to 3 rows", (tester) async {
    for (final shown in bothGrids()) {
      final store = storeOf(<CalendarEntry<String>>[
        for (var i = 0; i < 20; i++) allDayOf("e${i + 10}", tuesday),
      ]);
      await Harness(store, shown, size: const Size(800.0, 300.0)).pump(tester);
      await tester.tap(find.byKey(allDayMoreKey(tuesday)));
      await tester.pumpAndSettle();
      // Setup sanity: the strip is taller than the grid.
      expect(shown.stripStart + 20, shown.firstSlotRow - 1, reason: shown.name);
      expect(
        20 * stripRect(tester, shown, tuesday).height,
        greaterThan(300.0),
        reason: shown.name,
      );
      final less = find.byKey(allDayLessKey);
      expect(
        tester.getRect(less).center.dx,
        lessThan(cellRect(tester, shown.stripStart, 1).left),
        reason: shown.name,
      );
      await tester.tap(less);
      await tester.pumpAndSettle();
      expect(allBars(), findsNWidgets(3), reason: shown.name);
      expect(shown.firstSlotRow, shown.stripStart + 4 + 1, reason: shown.name);
    }
  });

  group("TS13", () {
    testWidgets("a tap on a bar reports its entry, in and out of edit mode", (
      tester,
    ) async {
      for (final shown in bothGrids()) {
        for (final editable in const <bool>[true, false]) {
          final store = storeOf(<CalendarEntry<String>>[
            allDayOf("off", tuesday),
          ]);
          final harness = Harness(store, shown, editable: editable);
          await harness.pump(tester);
          await tester.tap(barFinder("off"));
          await tester.pumpAndSettle();
          expect(harness.opened, <String>[
            "off",
          ], reason: "${shown.name} $editable");
        }
      }
    });

    testWidgets("over a caching store a tap reports nothing while the "
        "entry's write is pending", (tester) async {
      for (final shown in bothGrids()) {
        final off = allDayOf("off", tuesday);
        final source = HeldSource(<CalendarEntry<String>>[off]);
        final store = CachingCalendarStore<String>(dataSource: source);
        addTearDown(store.dispose);
        store.show(monday, sunday);
        final harness = Harness(store, shown);
        await harness.pump(tester);
        store.requestMove(off.copyWith(title: "renamed"));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        // Setup sanity: the write is pending.
        expect(store.isPending("off"), isTrue, reason: shown.name);
        await tester.tap(barFinder("off"));
        await tester.pump(const Duration(milliseconds: 500));
        expect(harness.opened, isEmpty, reason: shown.name);
        source.replaces.single.complete(off.copyWith(title: "renamed"));
        await tester.pumpAndSettle();
        await tester.tap(barFinder("off"));
        await tester.pumpAndSettle();
        expect(harness.opened, <String>["off"], reason: shown.name);
      }
    });

    testWidgets("in edit mode under lockPast a long press on a bar of an "
        "entry from yesterday's start to tomorrow's selects it, which in Week "
        "shows its right grip and no left one, and a tap on the gutter then "
        "clears the selection", (tester) async {
      for (final shown in <Shown>[Shown.week(monday), Shown.day(wednesday)]) {
        final store = storeOf(<CalendarEntry<String>>[
          allDayOf("trip", tuesday, days: 2),
        ]);
        await Harness(
          store,
          shown,
          lockPast: true,
          today: wednesday,
        ).pump(tester);
        final gesture = await lift(tester, tester.getCenter(barFinder("trip")));
        await tester.pump();
        // A started entry does not lift.
        expect(find.byKey(liftedBlockKey), findsNothing, reason: shown.name);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          find.byKey(blockHandlesKey("trip")),
          findsOneWidget,
          reason: shown.name,
        );
        expect(
          find.byKey(blockGripKey("trip", AxisDirection.right)),
          shown.week ? findsOneWidget : findsNothing,
          reason: shown.name,
        );
        expect(
          find.byKey(blockGripKey("trip", AxisDirection.left)),
          findsNothing,
          reason: shown.name,
        );
        await tester.tapAt(cellRect(tester, shown.rowOf(12 * 60), 0).center);
        await tester.pumpAndSettle();
        expect(
          find.byKey(blockHandlesKey("trip")),
          findsNothing,
          reason: shown.name,
        );
        expect(store.moves, isEmpty, reason: shown.name);
      }
    });
  });

  testWidgets("TX1 a bar moved two columns writes days two later", (
    tester,
  ) async {
    final store = await moveBarTwoColumns(tester);
    expectTimes(store, "off", wednesday, thursday);
  });

  testWidgets("TX2 a bar's leading day edge writes a new start", (
    tester,
  ) async {
    final store = await resizeBarStart(tester);
    expectTimes(store, "trip", monday, thursday);
  });

  testWidgets("TX3 a bar's trailing day edge writes a new end", (tester) async {
    final store = await resizeBarEnd(tester);
    expectTimes(store, "trip", tuesday, friday);
  });

  testWidgets("TX4 a bar dropped on the 10:00 slot writes 10:00 to 11:00, "
      "and a three-day bar grabbed at its last day and released with the "
      "finger on Tuesday's 10:00 slot writes Tuesday 10:00 to 11:00", (
    tester,
  ) async {
    for (final shown in bothGrids()) {
      var store = await dropBarOnSlot(tester, shown);
      expectTimes(
        store,
        "off",
        at(tuesday, 10),
        at(tuesday, 11),
        reason: shown.name,
      );
      expect(barFinder("off"), findsNothing, reason: shown.name);
      expect(blockFinder("off", tuesday), findsOneWidget, reason: shown.name);
      store = await dropWideBarOnSlot(tester, shown);
      expectTimes(
        store,
        "trip",
        at(tuesday, 10),
        at(tuesday, 11),
        reason: shown.name,
      );
    }
  });

  testWidgets("TX5 a block dropped on Tuesday's strip cell writes Tuesday's "
      "start to Wednesday's", (tester) async {
    for (final shown in bothGrids()) {
      final store = await dropBlockOnStrip(tester, shown);
      expectTimes(store, "meet", tuesday, wednesday, reason: shown.name);
      expect(barFinder("meet"), findsOneWidget, reason: shown.name);
      expect(blocksOf("meet"), findsNothing, reason: shown.name);
    }
  });

  testWidgets("TX6 each of TX1 to TX5, TX8's releases and TX11 writes once", (
    tester,
  ) async {
    final writes = <String, int>{};
    writes["TX1"] = (await moveBarTwoColumns(tester)).moves.length;
    writes["TX2"] = (await resizeBarStart(tester)).moves.length;
    writes["TX3"] = (await resizeBarEnd(tester)).moves.length;
    for (final shown in bothGrids()) {
      writes["TX4 ${shown.name}"] = (await dropBarOnSlot(
        tester,
        shown,
      )).moves.length;
      writes["TX4 wide ${shown.name}"] = (await dropWideBarOnSlot(
        tester,
        shown,
      )).moves.length;
      writes["TX5 ${shown.name}"] = (await dropBlockOnStrip(
        tester,
        shown,
      )).moves.length;
      writes["TX11 ${shown.name}"] = (await dropBlockOnEmptyRow(
        tester,
        shown,
      )).moves.length;
    }
    for (final (limit, id, day, side, over) in tx8Releases) {
      writes["TX8 $limit $id ${side.name} ${isoDate(over)}"] =
          (await releaseBarEdge(
            tester,
            limit: limit,
            id: id,
            day: day,
            side: side,
            over: over,
            others: <CalendarEntry<String>>[allDayOf("w", wednesday)],
          )).moves.length;
    }
    expect(writes.values.toSet(), <int>{1}, reason: "$writes");
  });

  group("TX7 under lockPast", () {
    testWidgets("in Week each gesture onto a past day writes nothing, and "
        "while a block's pointer is over a past day's strip cell no strip "
        "cell is marked and the landing label reads noLandingLabel", (
      tester,
    ) async {
      final shown = Shown.week(monday);
      final days = <DateTime>[for (var i = 0; i < 7; i++) addDays(monday, i)];
      Future<MoveRecordingStore> pumpLocked(
        List<CalendarEntry<String>> entries,
      ) async {
        final store = storeOf(entries);
        await Harness(
          store,
          shown,
          lockPast: true,
          today: wednesday,
        ).pump(tester);
        return store;
      }

      // A bar moved onto Tuesday.
      var store = await pumpLocked(<CalendarEntry<String>>[
        allDayOf("thu", thursday),
      ]);
      await dragTo(
        tester,
        tester.getCenter(barFinder("thu")),
        stripRect(tester, shown, tuesday).center,
      );
      expect(store.moves, isEmpty, reason: "move");

      // A leading edge onto Tuesday.
      store = await pumpLocked(<CalendarEntry<String>>[
        allDayOf("thu", thursday),
      ]);
      await selectBar(tester, "thu");
      var gesture = await holdEdge(
        tester,
        "thu",
        AxisDirection.left,
        Offset(
          stripRect(tester, shown, tuesday).left + 4.0,
          tester.getCenter(barFinder("thu")).dy,
        ),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.moves, isEmpty, reason: "leading edge");

      // A started bar's trailing edge onto Tuesday, its end then the
      // boundary.
      store = await pumpLocked(<CalendarEntry<String>>[
        allDayOf("trip", tuesday, days: 2),
      ]);
      await selectBar(tester, "trip");
      gesture = await holdEdge(
        tester,
        "trip",
        AxisDirection.right,
        Offset(
          stripRect(tester, shown, tuesday).right - 4.0,
          tester.getCenter(barFinder("trip")).dy,
        ),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.moves, isEmpty, reason: "trailing edge");

      // A bar onto Tuesday's 10:00 slot.
      store = await pumpLocked(<CalendarEntry<String>>[
        allDayOf("thu", thursday),
      ]);
      gesture = await liftTo(
        tester,
        tester.getCenter(barFinder("thu")),
        slotRect(tester, shown, tuesday, 10 * 60).center,
      );
      expect(landingText(tester), noLandingLabel, reason: "bar into a slot");
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.moves, isEmpty, reason: "bar into a slot");

      // A block onto Tuesday's strip cell, over a bar and over the empty
      // row.
      for (final others in <List<CalendarEntry<String>>>[
        <CalendarEntry<String>>[allDayOf("other", tuesday)],
        const <CalendarEntry<String>>[],
      ]) {
        store = await pumpLocked(<CalendarEntry<String>>[
          entryOf("meet", at(thursday, 10), at(thursday, 11)),
          ...others,
        ]);
        gesture = await liftTo(
          tester,
          tester.getCenter(blockFinder("meet", thursday)),
          stripRect(tester, shown, tuesday).center,
        );
        expect(markedOf(tester, days), isEmpty, reason: "$others");
        expect(landingText(tester), noLandingLabel, reason: "$others");
        await gesture.up();
        await tester.pumpAndSettle();
        expect(store.moves, isEmpty, reason: "block into the strip $others");
      }
    });

    testWidgets("in Day with lockEarlierToday, a block onto today's strip "
        "cell, a start before the boundary, writes nothing and marks "
        "nothing", (tester) async {
      final shown = Shown.day(tuesday);
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("meet", at(tuesday, 14), at(tuesday, 15)),
      ]);
      await Harness(
        store,
        shown,
        lockPast: true,
        lockEarlierToday: true,
        today: tuesday,
        nowHour: 12,
      ).pump(tester);
      final gesture = await liftTo(
        tester,
        tester.getCenter(blockFinder("meet", tuesday)),
        stripRect(tester, shown, tuesday).center,
      );
      // Setup sanity: the block lifted.
      expect(find.byKey(liftedBlockKey), findsOneWidget);
      expect(isMarked(tester, tuesday), isFalse);
      expect(landingText(tester), noLandingLabel);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.moves, isEmpty);
    });
  });

  group("TX8", () {
    testWidgets("with maxDayCount 3, a one-day Monday bar's trailing edge "
        "over Thursday keeps its stored rect, marks Monday to Wednesday and "
        "names them, and its release writes an end at Thursday's start", (
      tester,
    ) async {
      final (gesture, store) = await holdBarEdge(
        tester,
        limit: 3,
        id: "m",
        day: monday,
        side: AxisDirection.right,
        over: thursday,
      );
      final shown = Shown.week(monday);
      // Once the preview of the admitted extent the pointer passed on its
      // way has slid back.
      await tester.pumpAndSettle();
      expect(
        tester.getRect(barFinder("m")),
        nearRect(stripRect(tester, shown, monday)),
      );
      expect(
        markedOf(tester, <DateTime>[
          for (var i = 0; i < 7; i++) addDays(monday, i),
        ]),
        <DateTime>[monday, tuesday, wednesday],
      );
      expect(
        landingText(tester),
        landingLabel(monday, thursday, DateTime(2026, 1, 5)),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expectTimes(store, "m", monday, thursday);
    });

    testWidgets("with maxDayCount 3, the releases over Saturday, past "
        "Wednesday's bar, and over Wednesday write an end at Thursday's "
        "start, and a Friday bar's leading edge over Tuesday a start at "
        "Wednesday's", (tester) async {
      for (final (limit, id, day, side, over) in tx8Releases) {
        if (limit == null) {
          continue;
        }
        final store = await releaseBarEdge(
          tester,
          limit: limit,
          id: id,
          day: day,
          side: side,
          over: over,
          others: <CalendarEntry<String>>[allDayOf("w", wednesday)],
        );
        final reason = "$id over ${isoDate(over)}";
        if (side == AxisDirection.right) {
          expectTimes(store, id, day, thursday, reason: reason);
        } else {
          expectTimes(store, id, wednesday, saturday, reason: reason);
        }
      }
    });

    testWidgets("with no limit, the Monday bar's trailing edge over Saturday "
        "grows under Wednesday's bar, which keeps its rect and paints above "
        "it, and writes an end at Sunday's start; the Friday bar's leading "
        "edge over Monday writes a start at Monday's start", (tester) async {
      final shown = Shown.week(monday);
      final (gesture, store) = await holdBarEdge(
        tester,
        limit: null,
        id: "m",
        day: monday,
        side: AxisDirection.right,
        over: saturday,
        others: <CalendarEntry<String>>[allDayOf("w", wednesday)],
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(barFinder("m")),
        nearRect(
          stripRect(
            tester,
            shown,
            monday,
          ).expandToInclude(stripRect(tester, shown, saturday)),
        ),
      );
      expect(
        tester.getRect(barFinder("w")),
        nearRect(stripRect(tester, shown, wednesday)),
      );
      // The two share Wednesday's cell, each laned there by its stored
      // span, and the board paints them in its own item order: on this
      // strip, placed at once in the split's order, Wednesday's bar over
      // the resized one.
      final order = paintOrderOf(tester);
      expect(
        order.indexOf(itemBoxOf(tester, barFinder("w"))),
        greaterThan(order.indexOf(itemBoxOf(tester, barFinder("m")))),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expectTimes(store, "m", monday, sunday);

      final fridayStore = await releaseBarEdge(
        tester,
        limit: null,
        id: "f",
        day: friday,
        side: AxisDirection.left,
        over: monday,
      );
      expectTimes(fridayStore, "f", monday, saturday);
    });
  });

  testWidgets("TX9 under hours from 08:00 a bar dropped on the before-hours "
      "row writes 08:00 to 09:00, and under hours 08:00-18:00 a bar lifts "
      "and, in Week, a bar moved two columns writes days two later", (
    tester,
  ) async {
    const late = DayHours(8 * 60, minutesPerDay);
    for (final shown in bothGrids(hours: late)) {
      final store = storeOf(<CalendarEntry<String>>[
        allDayOf("off", tuesday),
      ], hours: late);
      await Harness(store, shown).pump(tester);
      final room = cellRect(
        tester,
        shown.firstSlotRow - 1,
        shown.colOf(tuesday),
      );
      await dragTo(tester, tester.getCenter(barFinder("off")), room.center);
      expectTimes(
        store,
        "off",
        at(tuesday, 8),
        at(tuesday, 9),
        reason: shown.name,
      );
    }
    const office = DayHours(8 * 60, 18 * 60);
    for (final shown in bothGrids(hours: office)) {
      final store = storeOf(<CalendarEntry<String>>[
        allDayOf("off", tuesday),
      ], hours: office);
      await Harness(store, shown).pump(tester);
      final gesture = await lift(tester, tester.getCenter(barFinder("off")));
      await tester.pump();
      expect(find.byKey(liftedBlockKey), findsOneWidget, reason: shown.name);
      await gesture.up();
      await tester.pumpAndSettle();
    }
    final store = await moveBarTwoColumns(tester, hours: office);
    expectTimes(store, "off", wednesday, thursday);
  });

  testWidgets(
    "TX10 on the 23-hour day a bar dropped on the 01:30 row writes 01:30 to "
    "03:30",
    skip: shortDaySkip != null,
    (tester) async {
      final day = shortDayStart;
      for (final shown in <Shown>[
        Shown.week(addDays(day, -6)),
        Shown.day(day),
      ]) {
        final store = storeOf(<CalendarEntry<String>>[allDayOf("dst", day)]);
        await Harness(store, shown).pump(tester);
        await dragTo(
          tester,
          tester.getCenter(barFinder("dst")),
          slotRect(tester, shown, day, 90).center,
        );
        final entry = storedOf(store, "dst");
        expect(entry.start, at(day, 1, 30), reason: shown.name);
        expect(entry.end, at(day, 3, 30), reason: shown.name);
        expect(
          entry.end.difference(entry.start),
          const Duration(hours: 1),
          reason: shown.name,
        );
      }
    },
  );

  testWidgets("TX11 with no all-day entry in range, a block dropped on the "
      "edit-mode row's cell writes that day's start to the next day's "
      "start", (tester) async {
    for (final shown in bothGrids()) {
      final store = await dropBlockOnEmptyRow(tester, shown);
      expectTimes(store, "meet", tuesday, wednesday, reason: shown.name);
    }
  });

  testWidgets("TX12 a bar in the last strip row offers no \"Move down\" "
      "semantics action and a block in the first slot row no \"Move up\"", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final store = storeOf(<CalendarEntry<String>>[
      allDayOf("a", tuesday),
      allDayOf("b", tuesday),
      entryOf("early", at(tuesday, 0), at(tuesday, 1)),
    ]);
    await Harness(store, Shown.week(monday)).pump(tester);
    final bar = actionsOf(tester, barFinder("b"));
    // Setup sanity: the bar offers moves, in its last row.
    expect(bar, contains(actionId("Move right")));
    expect(bar, isNot(contains(actionId("Move down"))));
    final block = actionsOf(tester, blockFinder("early", tuesday));
    expect(block, contains(actionId("Move down")));
    expect(block, isNot(contains(actionId("Move up"))));
    semantics.dispose();
  });

  testWidgets("TX13 one frame after a block is released over Tuesday's strip "
      "cell, no block of its id is built and its bar is, and nothing paints "
      "at the block's old rect", (tester) async {
    for (final shown in bothGrids()) {
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("meet", at(tuesday, 10), at(tuesday, 11)),
      ]);
      await Harness(store, shown).pump(tester);
      final old = tester.getRect(blockFinder("meet", tuesday));
      final gesture = await liftTo(
        tester,
        old.center,
        stripRect(tester, shown, tuesday).center,
      );
      await gesture.up();
      await tester.pump();
      expect(blocksOf("meet"), findsNothing, reason: shown.name);
      expect(barFinder("meet"), findsOneWidget, reason: shown.name);
      expect(find.byKey(liftedBlockKey), findsNothing, reason: shown.name);
      final viewport = viewportOf(tester);
      expect(
        viewport.itemAt(viewport.globalToLocal(old.center)),
        isNull,
        reason: shown.name,
      );
      await tester.pumpAndSettle();
    }
  });

  testWidgets("TX14 while a block move's pointer is over Tuesday's strip "
      "cell, Tuesday's strip cells are marked, the landing label names "
      "Tuesday all day and no landing outline is drawn, and once the pointer "
      "is back over a slot no strip cell is marked", (tester) async {
    for (final shown in bothGrids()) {
      final days = shown.week
          ? <DateTime>[for (var i = 0; i < 7; i++) addDays(monday, i)]
          : <DateTime>[tuesday];
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("meet", at(tuesday, 10), at(tuesday, 11)),
      ]);
      await Harness(store, shown).pump(tester);
      final block = tester.getRect(blockFinder("meet", tuesday));
      final gesture = await liftTo(
        tester,
        block.center,
        stripRect(tester, shown, tuesday).center,
      );
      expect(markedOf(tester, days), <DateTime>[tuesday], reason: shown.name);
      expect(
        landingText(tester),
        "Tuesday, April 21, all day",
        reason: shown.name,
      );
      expect(strokedRects(tester), isEmpty, reason: shown.name);
      await gesture.moveTo(slotRect(tester, shown, tuesday, 12 * 60).center);
      await tester.pump();
      expect(markedOf(tester, days), isEmpty, reason: shown.name);
      // Setup sanity: back over the slots, the board's landing shows.
      expect(strokedRects(tester), isNotEmpty, reason: shown.name);
      await gesture.up();
      await tester.pumpAndSettle();
    }
  });

  group("TX15", () {
    setUp(() {
      debugDropGateCount = 0;
      debugCellReadCount = 0;
    });

    /// Pumps the grid of [shown], Week from Monday by default, over
    /// [entries] in a view of [size], with slots at least 40 px tall and the
    /// hours scrolled to their start, and returns the harness.
    Future<Harness> pumpGrid(
      WidgetTester tester,
      List<CalendarEntry<String>> entries, {
      Shown? shown,
      int? maxDayCount,
      double minDayWidth = minDayWidthLow,
      Size size = const Size(800.0, 2000.0),
    }) async {
      final harness = Harness(
        storeOf(entries),
        shown ?? Shown.week(monday),
        minSlotHeight: 40.0,
        minDayWidth: minDayWidth,
        maxDayCount: maxDayCount,
        size: size,
      );
      await harness.pump(tester);
      viewportOf(tester).verticalPosition!.jumpTo(0.0);
      await tester.pump();
      return harness;
    }

    /// Moves [gesture] by [step] ten times, a frame after each.
    Future<void> moveTenTimes(
      WidgetTester tester,
      TestGesture gesture,
      Offset step,
    ) async {
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(step);
        await tester.pump();
      }
    }

    testWidgets("with 20 blocks mounted, a block's move asks at most two "
        "gates on the move that enters the strip and on the one that "
        "leaves it", (tester) async {
      final shown = Shown.week(monday);
      await pumpGrid(tester, <CalendarEntry<String>>[
        entryOf("meet", at(tuesday, 3), at(tuesday, 4)),
        for (var i = 0; i < 20; i++)
          entryOf(
            "b$i",
            at(addDays(monday, i % 7), 5 + (i ~/ 7) * 2),
            at(addDays(monday, i % 7), 6 + (i ~/ 7) * 2),
          ),
      ]);
      // Setup sanity: the 20 blocks are mounted.
      for (var i = 0; i < 20; i++) {
        expect(blockFinder("b$i", addDays(monday, i % 7)), findsOneWidget);
      }
      final over = slotRect(tester, shown, tuesday, 2 * 60).center;
      final gesture = await liftTo(
        tester,
        tester.getCenter(blockFinder("meet", tuesday)),
        over,
      );
      debugDropGateCount = 0;
      await gesture.moveTo(stripRect(tester, shown, tuesday).center);
      await tester.pump();
      // Setup sanity: the crossing reads the strip cell.
      expect(markedOf(tester, <DateTime>[tuesday]), <DateTime>[tuesday]);
      expect(debugDropGateCount, lessThanOrEqualTo(2), reason: "entering");
      debugDropGateCount = 0;
      await gesture.moveTo(over);
      await tester.pump();
      expect(markedOf(tester, <DateTime>[tuesday]), isEmpty);
      expect(debugDropGateCount, lessThanOrEqualTo(2), reason: "leaving");
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets("a one-slot block's proxy over Tuesday's strip cell asks at "
        "most 10 * 3 * (B + 4) gates over ten moves of 1 px, on a strip of "
        "one row and on an expanded one", (tester) async {
      final shown = Shown.week(monday);
      for (final perDay in const <int>[1, 5]) {
        await pumpGrid(tester, <CalendarEntry<String>>[
          entryOf("q", at(tuesday, 2), at(tuesday, 2, 15)),
          for (final day in <DateTime>[monday, tuesday, wednesday])
            for (var i = 0; i < perDay; i++) allDayOf("a${day.day}-$i", day),
        ]);
        if (perDay > 1) {
          await tester.tap(find.byKey(allDayMoreKey(tuesday)));
          await tester.pumpAndSettle();
          viewportOf(tester).verticalPosition!.jumpTo(0.0);
          await tester.pump();
        }
        final band = boardOf(tester).controller.rows.frozenStart;
        // Setup sanity: the band holds the header and every strip row.
        expect(band, 1 + perDay, reason: "$perDay a day");
        final gesture = await liftTo(
          tester,
          tester.getCenter(blockFinder("q", tuesday)),
          stripRect(tester, shown, tuesday).center,
        );
        debugDropGateCount = 0;
        await moveTenTimes(tester, gesture, const Offset(0.0, 1.0));
        // Setup sanity: the pointer stayed over Tuesday's strip cell.
        expect(markedOf(tester, <DateTime>[tuesday]), <DateTime>[tuesday]);
        expect(
          debugDropGateCount,
          lessThanOrEqualTo(10 * 3 * (band + 4)),
          reason: "$perDay a day",
        );
        await gesture.up();
        await tester.pumpAndSettle();
      }
    });

    testWidgets("ten moves of 1 px of a block's move read the cell ten "
        "times, and ten of a start-handle resize, of a bar's day-edge resize "
        "and, in Day, of an end-handle resize read none", (tester) async {
      final week = Shown.week(monday);
      await pumpGrid(tester, <CalendarEntry<String>>[
        entryOf("meet", at(tuesday, 5), at(tuesday, 6)),
        allDayOf("off", monday),
      ]);
      final block = blockFinder("meet", tuesday);
      final move = await liftTo(
        tester,
        tester.getCenter(block),
        tester.getCenter(block) + const Offset(0.0, 8.0),
      );
      debugCellReadCount = 0;
      await moveTenTimes(tester, move, const Offset(0.0, 1.0));
      expect(debugCellReadCount, 10, reason: "a block's move");
      await move.up();
      await tester.pumpAndSettle();

      // The drop left the entry selected, its start grip on the block.
      final top = tester.getRect(block);
      final start = await tester.startGesture(
        Offset(top.center.dx, top.top + 2.0),
      );
      await start.moveBy(const Offset(0.0, -30.0));
      await tester.pump();
      // Setup sanity: the resize runs.
      expect(landingText(tester), isNotNull, reason: "a start-handle resize");
      debugCellReadCount = 0;
      await moveTenTimes(tester, start, const Offset(0.0, -1.0));
      expect(debugCellReadCount, 0, reason: "a start-handle resize");
      await start.up();
      await tester.pumpAndSettle();

      await selectBar(tester, "off");
      final edge = await holdEdge(
        tester,
        "off",
        AxisDirection.right,
        Offset(
          stripRect(tester, week, wednesday).right - 20.0,
          tester.getCenter(barFinder("off")).dy,
        ),
      );
      expect(landingText(tester), isNotNull, reason: "a bar's day-edge resize");
      debugCellReadCount = 0;
      await moveTenTimes(tester, edge, const Offset(1.0, 0.0));
      expect(debugCellReadCount, 0, reason: "a bar's day-edge resize");
      await edge.up();
      await tester.pumpAndSettle();

      await pumpGrid(tester, <CalendarEntry<String>>[
        entryOf("meet", at(tuesday, 5), at(tuesday, 6)),
      ], shown: Shown.day(tuesday));
      final dayBlock = blockFinder("meet", tuesday);
      final selecting = await lift(tester, tester.getCenter(dayBlock));
      await selecting.up();
      await tester.pumpAndSettle();
      final bottom = tester.getRect(dayBlock);
      final end = await tester.startGesture(
        Offset(bottom.center.dx, bottom.bottom - 2.0),
      );
      await end.moveBy(const Offset(0.0, 30.0));
      await tester.pump();
      expect(landingText(tester), isNotNull, reason: "Day's end-handle resize");
      debugCellReadCount = 0;
      await moveTenTimes(tester, end, const Offset(0.0, 1.0));
      expect(debugCellReadCount, 0, reason: "Day's end-handle resize");
      await end.up();
      await tester.pumpAndSettle();
    });

    testWidgets("with a block's move, and then a bar's, held still in the "
        "middle of the slots, ten jumps of 1 px of the vertical position "
        "read the cell ten times, and so do ten of the horizontal one", (
      tester,
    ) async {
      final shown = Shown.week(monday);
      await pumpGrid(tester, <CalendarEntry<String>>[
        entryOf("meet", at(tuesday, 5), at(tuesday, 6)),
        allDayOf("off", monday),
      ], minDayWidth: 200.0);
      final viewport = viewportOf(tester);
      final middle = viewport
          .localToGlobal(Offset(0.0, viewport.size.height / 2))
          .dy;
      for (final (name, from, column) in <(String, Finder, DateTime)>[
        ("a block's move", blockFinder("meet", tuesday), tuesday),
        ("a bar's move", barFinder("off"), monday),
      ]) {
        final gesture = await liftTo(
          tester,
          tester.getCenter(from),
          Offset(slotRect(tester, shown, column, 0).center.dx, middle),
        );
        // Setup sanity: the drag runs.
        expect(find.byKey(liftedBlockKey), findsOneWidget, reason: name);
        final vertical = viewportOf(tester).verticalPosition!;
        debugCellReadCount = 0;
        for (var i = 0; i < 10; i++) {
          vertical.jumpTo(vertical.pixels + 1.0);
          await tester.pump();
        }
        expect(debugCellReadCount, 10, reason: "$name, vertical");
        final horizontal = viewportOf(tester).horizontalPosition!;
        // Setup sanity: the days scroll across.
        expect(horizontal.maxScrollExtent, greaterThan(10.0), reason: name);
        debugCellReadCount = 0;
        for (var i = 0; i < 10; i++) {
          horizontal.jumpTo(horizontal.pixels + 1.0);
          await tester.pump();
        }
        expect(debugCellReadCount, 10, reason: "$name, horizontal");
        await gesture.up();
        await tester.pumpAndSettle();
      }
    });

    testWidgets("once a block's move has been released, and once a "
        "slotMinutes change has cancelled another's, ten frames of a "
        "vertical scroll and ten jumps of either position read no cell", (
      tester,
    ) async {
      final harness = await pumpGrid(
        tester,
        <CalendarEntry<String>>[
          entryOf("meet", at(tuesday, 5), at(tuesday, 6)),
          entryOf("talk", at(thursday, 5), at(thursday, 6)),
        ],
        minDayWidth: 200.0,
        size: const Size(800.0, 1000.0),
      );

      Future<void> expectNoReads(String name) async {
        debugCellReadCount = 0;
        final vertical = viewportOf(tester).verticalPosition!;
        final from = vertical.pixels;
        unawaited(
          vertical.animateTo(
            from + 200.0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.linear,
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        // Setup sanity: the hours scrolled.
        expect(vertical.pixels, greaterThan(from), reason: name);
        for (final position in <ScrollPosition>[
          viewportOf(tester).verticalPosition!,
          viewportOf(tester).horizontalPosition!,
        ]) {
          for (var i = 0; i < 10; i++) {
            position.jumpTo(position.pixels + 1.0);
            await tester.pump();
          }
        }
        expect(debugCellReadCount, 0, reason: name);
        viewportOf(tester).verticalPosition!.jumpTo(0.0);
        viewportOf(tester).horizontalPosition!.jumpTo(0.0);
        await tester.pump();
      }

      final block = blockFinder("meet", tuesday);
      final released = await liftTo(
        tester,
        tester.getCenter(block),
        tester.getCenter(block) + const Offset(0.0, 80.0),
      );
      await released.up();
      await tester.pump();
      await expectNoReads("after a release");
      await tester.pumpAndSettle();

      final talk = blockFinder("talk", thursday);
      final cancelled = await liftTo(
        tester,
        tester.getCenter(talk),
        tester.getCenter(talk) + const Offset(0.0, 80.0),
      );
      harness.slotMinutes = 30;
      await harness.rebuild(tester);
      await tester.pump();
      // Setup sanity: the change ended the drag.
      expect(find.byKey(liftedBlockKey), findsNothing);
      await expectNoReads("after a slotMinutes change");
      await cancelled.up();
      await tester.pumpAndSettle();
    });

    testWidgets("ten moves of 1 px of a bar's move over one slot ask no "
        "gate, and with maxDayCount 3 neither do ten of a bar's trailing "
        "edge within one column past the limit", (tester) async {
      final shown = Shown.week(monday);
      await pumpGrid(tester, <CalendarEntry<String>>[allDayOf("off", monday)]);
      final move = await liftTo(
        tester,
        tester.getCenter(barFinder("off")),
        slotRect(tester, shown, monday, 5 * 60).center,
      );
      // Setup sanity: the crossing names the slot's hour.
      expect(
        landingText(tester),
        landingLabel(at(monday, 5), at(monday, 6), DateTime(2026, 1, 5)),
      );
      debugDropGateCount = 0;
      await moveTenTimes(tester, move, const Offset(1.0, 0.0));
      expect(debugDropGateCount, 0, reason: "a bar over one slot");
      await move.up();
      await tester.pumpAndSettle();

      await pumpGrid(tester, <CalendarEntry<String>>[
        allDayOf("m", monday),
      ], maxDayCount: 3);
      await selectBar(tester, "m");
      final edge = await holdEdge(
        tester,
        "m",
        AxisDirection.right,
        Offset(
          stripRect(tester, shown, thursday).right - 20.0,
          tester.getCenter(barFinder("m")).dy,
        ),
      );
      await tester.pumpAndSettle();
      // Setup sanity: the edge is held at Wednesday.
      expect(
        markedOf(tester, <DateTime>[
          for (var i = 0; i < 7; i++) addDays(monday, i),
        ]),
        <DateTime>[monday, tuesday, wednesday],
      );
      debugDropGateCount = 0;
      await moveTenTimes(tester, edge, const Offset(-1.0, 0.0));
      expect(debugDropGateCount, 0, reason: "a bar's edge past the limit");
      await edge.up();
      await tester.pumpAndSettle();
    });
  });

  testWidgets("TX16 in Day a selected bar has no day-edge grip and the "
      "board resizes no column edge, a bar dragged onto the other strip row "
      "writes nothing, and a bar offers no semantics move", (tester) async {
    final semantics = tester.ensureSemantics();
    final shown = Shown.day(tuesday);
    final store = storeOf(<CalendarEntry<String>>[
      allDayOf("a", tuesday),
      allDayOf("b", tuesday),
    ]);
    await Harness(store, shown).pump(tester);
    expect(boardOf(tester).drag!.resizeEdges, BoardResizeEdges.none);
    for (final id in const <String>["a", "b"]) {
      final actions = actionsOf(tester, barFinder(id));
      for (final label in const <String>[
        "Move up",
        "Move down",
        "Move left",
        "Move right",
      ]) {
        expect(actions, isNot(contains(actionId(label))), reason: "$id $label");
      }
    }
    await selectBar(tester, "a");
    // Setup sanity: the bar is selected.
    expect(find.byKey(blockHandlesKey("a")), findsOneWidget);
    expect(find.byKey(blockGripKey("a", AxisDirection.left)), findsNothing);
    expect(find.byKey(blockGripKey("a", AxisDirection.right)), findsNothing);
    await dragTo(
      tester,
      tester.getCenter(barFinder("a")),
      stripRect(tester, shown, tuesday, 1).center,
    );
    expect(store.moves, isEmpty);
    semantics.dispose();
  });

  testWidgets("TX17 while a bar's drag pointer is over a day's 10:00 slot the "
      "landing label names that day's 10:00 to 11:00 and the background "
      "outlines those slots, both following the pointer onto 14:00, and over "
      "a slot an entry holds the label reads noLandingLabel and no outline "
      "is drawn", (tester) async {
    final today = DateTime(2026, 1, 5);
    for (final shown in bothGrids()) {
      final store = storeOf(<CalendarEntry<String>>[allDayOf("off", tuesday)]);
      await Harness(store, shown, allowsOverlaps: false).pump(tester);
      final gesture = await liftTo(
        tester,
        tester.getCenter(barFinder("off")),
        slotRect(tester, shown, tuesday, 10 * 60).center,
      );
      expect(
        landingText(tester),
        landingLabel(at(tuesday, 10), at(tuesday, 11), today),
        reason: shown.name,
      );
      expect(strokedRects(tester), <Matcher>[
        nearRect(
          slotsRect(tester, shown, tuesday, 10 * 60, 11 * 60).deflate(1.0),
        ),
      ], reason: shown.name);
      await gesture.moveTo(slotRect(tester, shown, tuesday, 14 * 60).center);
      await tester.pump();
      expect(
        landingText(tester),
        landingLabel(at(tuesday, 14), at(tuesday, 15), today),
        reason: shown.name,
      );
      expect(strokedRects(tester), <Matcher>[
        nearRect(
          slotsRect(tester, shown, tuesday, 14 * 60, 15 * 60).deflate(1.0),
        ),
      ], reason: shown.name);
      await gesture.up();
      await tester.pumpAndSettle();

      final busy = storeOf(<CalendarEntry<String>>[
        allDayOf("off", tuesday),
        entryOf("meet", at(tuesday, 10), at(tuesday, 11)),
      ]);
      await Harness(busy, shown, allowsOverlaps: false).pump(tester);
      final over = await liftTo(
        tester,
        tester.getCenter(barFinder("off")),
        slotRect(tester, shown, tuesday, 10 * 60).center,
      );
      expect(landingText(tester), noLandingLabel, reason: shown.name);
      expect(strokedRects(tester), isEmpty, reason: shown.name);
      await over.up();
      await tester.pumpAndSettle();
      expect(busy.moves, isEmpty, reason: shown.name);
    }
  });

  group("TX18", () {
    for (final changesRatio in const <bool>[false, true]) {
      final name = changesRatio
          ? "TX18b with the device pixel ratio changed while the pointer is "
                "held, which replaces each scrollable's position, the label "
                "and the release still follow the slot under the pointer"
          : "TX18 with a bar's drag pointer held still in the autoscroll zone "
                "at the top of the slots, after the hours have scrolled by "
                "four slots the landing label names the slot then under the "
                "pointer, and the release writes that slot";
      testWidgets(name, (tester) async {
        for (final shown in bothGrids()) {
          final store = storeOf(<CalendarEntry<String>>[
            allDayOf("off", tuesday),
          ]);
          final harness = Harness(store, shown, size: const Size(800.0, 600.0));
          await harness.pump(tester);
          final viewport = viewportOf(tester);
          final band = viewport.scrolledRegion.top;
          final pointer = globalOf(
            tester,
            Offset(
              viewport
                  .rectOfCell(shown.firstSlotRow, shown.colOf(tuesday))!
                  .center
                  .dx,
              band + 12.0,
            ),
          );
          final gesture = await liftTo(
            tester,
            tester.getCenter(barFinder("off")),
            pointer,
          );
          var start = viewportOf(tester).verticalPosition!.pixels;
          // Setup sanity: the hours are scrolled well into the day.
          expect(start, greaterThan(200.0), reason: shown.name);
          final slot = viewportOf(tester).rectOfCell(shown.firstSlotRow, 1)!;
          Future<void> scrollFourSlots() async {
            var frames = 0;
            while (viewportOf(tester).verticalPosition!.pixels >
                start - 4 * slot.height) {
              await tester.pump(const Duration(milliseconds: 16));
              expect(frames++, lessThan(200), reason: shown.name);
            }
          }

          await scrollFourSlots();
          var under = hourUnder(tester, shown, tuesday, pointer);
          expect(
            landingText(tester),
            landingLabel(under.start, under.end, harness.today),
            reason: shown.name,
          );
          if (changesRatio) {
            final before = viewportOf(tester).verticalPosition;
            tester.view.devicePixelRatio = 2.0;
            tester.view.physicalSize = const Size(1600.0, 1200.0);
            await tester.pump();
            // Setup sanity: the scrollable replaced its position.
            expect(
              identical(viewportOf(tester).verticalPosition, before),
              isFalse,
              reason: shown.name,
            );
            start = viewportOf(tester).verticalPosition!.pixels;
            await scrollFourSlots();
            under = hourUnder(tester, shown, tuesday, pointer);
            expect(
              landingText(tester),
              landingLabel(under.start, under.end, harness.today),
              reason: shown.name,
            );
          }
          await gesture.up();
          await tester.pumpAndSettle();
          expectTimes(store, "off", under.start, under.end, reason: shown.name);
          tester.view.reset();
        }
      });
    }
  });

  testWidgets("TX19 under hours that leave an entry after them, a bar "
      "released over the frozen after-hours notice writes nothing", (
    tester,
  ) async {
    const hours = DayHours(0, 18 * 60);
    for (final shown in bothGrids(hours: hours)) {
      final store = storeOf(<CalendarEntry<String>>[
        allDayOf("off", tuesday),
        entryOf("late", at(tuesday, 19), at(tuesday, 20)),
      ]);
      await Harness(store, shown).pump(tester);
      final notice = cellRect(
        tester,
        shown.firstSlotRow + hours.slotCountOf(15),
        shown.colOf(tuesday),
      );
      // Setup sanity: the notice is frozen at the grid's bottom.
      expect(
        notice.bottom,
        moreOrLessEquals(
          tester.getBottomLeft(find.byType(TimedGrid<String>)).dy,
        ),
        reason: shown.name,
      );
      await dragTo(tester, tester.getCenter(barFinder("off")), notice.center);
      expect(store.moves, isEmpty, reason: shown.name);
    }
  });

  group("TX20", () {
    for (final notice in const <bool>[false, true]) {
      final name = notice
          ? "a store notify that adds an entry before the hours during a "
                "bar's drag, which freezes the before-hours notice in place "
                "of the room row, leaves the drag running and the landing on "
                "the slot then under the pointer"
          : "a store notify that adds a strip row during a bar's drag, its "
                "pointer held still over Tuesday's 10:00 slot, leaves the "
                "drag running, and two frames later the label and the outline "
                "name the hour from the slot then under the pointer, which "
                "its release writes";
      testWidgets(name, (tester) async {
        final hours = notice
            ? const DayHours(8 * 60, minutesPerDay)
            : DayHours.allDay;
        for (final shown in bothGrids(hours: hours)) {
          final day = shown.week ? monday : tuesday;
          final store = storeOf(<CalendarEntry<String>>[allDayOf("a", day)]);
          // Slots of 40 px, which the rows do not stretch, so a row added
          // above them moves them by its height.
          final harness = Harness(store, shown, minSlotHeight: 40.0);
          await harness.pump(tester);
          final slot = slotRect(tester, shown, tuesday, 10 * 60);
          final pointer = Offset(slot.center.dx, slot.top + 4.0);
          final gesture = await liftTo(
            tester,
            tester.getCenter(barFinder("a")),
            pointer,
          );
          final rows = rowCountNow();
          final firstTop = firstSlotRect(tester, shown, tuesday).top;
          store.entries = <CalendarEntry<String>>[
            ...store.entries,
            if (notice)
              entryOf("early", at(tuesday, 6), at(tuesday, 7))
            else
              allDayOf("b", day),
          ];
          await tester.pump();
          await tester.pump();
          // Setup sanity: the slots moved under the still pointer.
          expect(
            firstSlotRect(tester, shown, tuesday).top,
            greaterThan(firstTop),
            reason: shown.name,
          );
          expect(rowCountNow(), notice ? rows : rows + 1, reason: shown.name);
          expect(
            find.byKey(liftedBlockKey),
            findsOneWidget,
            reason: shown.name,
          );
          final under = hourUnder(tester, shown, tuesday, pointer);
          // Setup sanity: another slot lies under the pointer now.
          expect(under.start, isNot(at(tuesday, 10)), reason: shown.name);
          expect(
            landingText(tester),
            landingLabel(under.start, under.end, harness.today),
            reason: shown.name,
          );
          final minute = minuteOfDay(under.start);
          expect(strokedRects(tester), <Matcher>[
            nearRect(
              slotsRect(
                tester,
                shown,
                tuesday,
                minute,
                minute + 60,
              ).deflate(1.0),
            ),
          ], reason: shown.name);
          await gesture.up();
          await tester.pumpAndSettle();
          expectTimes(store, "a", under.start, under.end, reason: shown.name);
        }
      });
    }
  });

  testWidgets("new days during a bar's drag over a slot, which leave the bar "
      "its key and its span, cancel the drag: the proxy and the landing go, "
      "a move over another slot shows none, and the release writes nothing", (
    tester,
  ) async {
    for (final shown in bothGrids()) {
      // Two weeks from Monday: in Week a bar over every column of this week
      // and of the next, and in Day over Tuesday and over Wednesday.
      final long = allDayOf("long", monday, days: 14);
      final store = storeOf(<CalendarEntry<String>>[long]);
      final harness = Harness(store, shown);
      await harness.pump(tester);
      final gesture = await liftTo(
        tester,
        tester.getCenter(barFinder("long")),
        slotRect(tester, shown, tuesday, 10 * 60).center,
      );
      // Setup sanity: the bar lifted, and its landing shows on the slot.
      expect(find.byKey(liftedBlockKey), findsOneWidget, reason: shown.name);
      expect(
        landingText(tester),
        landingLabel(at(tuesday, 10), at(tuesday, 11), harness.today),
        reason: shown.name,
      );
      const key = GridKey.bar("long");
      final span = boardOf(tester).controller.spanOf(key);

      final next = addDays(shown.first, shown.week ? 7 : 1);
      harness.first = next;
      await harness.rebuild(tester);
      await tester.pump();
      // Setup sanity: the grid shows the new days, and its board holds the
      // bar's key at the span it had, so no placement moved the dragged key.
      expect(
        find.byKey(allDayCellKey(next)),
        findsOneWidget,
        reason: shown.name,
      );
      expect(span, isNotNull, reason: shown.name);
      expect(boardOf(tester).controller.spanOf(key), span, reason: shown.name);
      expect(find.byKey(liftedBlockKey), findsNothing, reason: shown.name);
      expect(landingText(tester), isNull, reason: shown.name);

      // The 14:00 slot of the column under the pointer, a day of the new
      // days.
      await gesture.moveTo(
        cellRect(tester, shown.rowOf(14 * 60), shown.colOf(tuesday)).center,
      );
      await tester.pump();
      expect(landingText(tester), isNull, reason: shown.name);
      expect(strokedRects(tester), isEmpty, reason: shown.name);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.moves, isEmpty, reason: shown.name);
      expect(storedOf(store, "long"), long, reason: shown.name);
    }
  });

  group("TX22", () {
    testWidgets("Monday's one-day bar over Tuesday's, in the strip's one "
        "row, halves Tuesday's bar while it hovers, and its release writes "
        "it on Tuesday, the two then in rows 0 and 1 at the column's full "
        "width; a three-day bar over Thursday's leaves that bar's rect", (
      tester,
    ) async {
      final shown = Shown.week(monday);
      final store = storeOf(<CalendarEntry<String>>[
        allDayOf("mon", monday),
        allDayOf("tue", tuesday),
      ]);
      await Harness(store, shown).pump(tester);
      final cell = stripRect(tester, shown, tuesday);
      final gesture = await liftTo(
        tester,
        tester.getCenter(barFinder("mon")),
        cell.center,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(barFinder("tue")).width,
        moreOrLessEquals(cell.width / 2, epsilon: 1.0),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expectTimes(store, "mon", tuesday, wednesday);
      expect(
        tester.getRect(barFinder("mon")),
        nearRect(stripRect(tester, shown, tuesday)),
      );
      expect(
        tester.getRect(barFinder("tue")),
        nearRect(stripRect(tester, shown, tuesday, 1)),
      );

      final wide = storeOf(<CalendarEntry<String>>[
        allDayOf("trip", monday, days: 3),
        allDayOf("thu", thursday),
      ]);
      await Harness(wide, shown).pump(tester);
      final thu = tester.getRect(barFinder("thu"));
      final over = await liftTo(
        tester,
        tester.getCenter(barFinder("trip")),
        tester.getCenter(barFinder("trip")) + Offset(2 * cell.width, 0.0),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(barFinder("thu")), thu);
      await over.up();
      await tester.pumpAndSettle();
      expectTimes(wide, "trip", wednesday, saturday);
    });

    testWidgets("a one-day bar dropped on a day whose three shown strip rows "
        "hold bars lands under that day's \"+1\" pill", (tester) async {
      final shown = Shown.week(monday);
      final store = storeOf(<CalendarEntry<String>>[
        allDayOf("z", monday),
        for (final id in const <String>["b", "c", "d"]) allDayOf(id, tuesday),
      ]);
      await Harness(store, shown).pump(tester);
      // Setup sanity: three rows and no count.
      expect(shown.firstSlotRow, shown.stripStart + 3 + 1);
      await dragTo(
        tester,
        tester.getCenter(barFinder("z")),
        stripRect(tester, shown, tuesday).center,
      );
      expectTimes(store, "z", tuesday, wednesday);
      expect(barFinder("z"), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(allDayMoreKey(tuesday)),
          matching: find.text("+1"),
        ),
        findsOneWidget,
      );
      expect(shown.firstSlotRow, shown.stripStart + 4 + 1);
    });
  });

  testWidgets("TX21 in edit mode with no all-day entry, a block of as many "
      "slots as the leading band's tracks shows the first slots that show "
      "whether its proxy's centre is over the band or just below it, and "
      "one whose centre is over the band, and one of a slot more, drop on "
      "the landing's last one", (tester) async {
    for (final shown in bothGrids()) {
      // The day header in Week, and the strip's one empty row.
      final band = shown.week ? 2 : 1;
      for (final (slots, centreOver) in <(int, bool)>[
        (band, true),
        (band, false),
        (band + 1, true),
      ]) {
        final reason = "${shown.name} $slots slots, centre over: $centreOver";
        final store = storeOf(<CalendarEntry<String>>[
          entryOf("meet", at(tuesday, 11), at(tuesday, 11, slots * 15)),
        ]);
        await Harness(
          store,
          shown,
          minSlotHeight: 40.0,
          size: const Size(800.0, 600.0),
        ).pump(tester);
        var viewport = viewportOf(tester);
        final position = viewport.verticalPosition!;
        final col = shown.colOf(tuesday);
        final edge = viewport.scrolledRegion.top;
        position.jumpTo(
          position.pixels +
              viewport.rectOfCell(shown.rowOf(10 * 60), col)!.top -
              edge,
        );
        await tester.pump();
        // Setup sanity: 10:00's row top lies at the band's edge, 1,600 px
        // below 00:00's.
        expect(
          viewport.rectOfCell(shown.rowOf(10 * 60), col)!.top,
          moreOrLessEquals(edge),
          reason: reason,
        );
        expect(
          viewport.rectOfCell(shown.rowOf(10 * 60), col)!.top -
              viewport.rectOfCell(shown.rowOf(0), col)!.top,
          moreOrLessEquals(1600.0),
          reason: reason,
        );
        final block = tester.getRect(blockFinder("meet", tuesday));
        final grab = Offset(block.center.dx, block.bottom - 4.0);
        // The proxy's centre lies above the pointer by half the block less
        // the 4 px it was grabbed at above its bottom.
        final above = block.height / 2 - 4.0;
        final to = centreOver
            ? globalOf(tester, Offset(0.0, edge + 8.0)).dy
            : globalOf(tester, Offset(0.0, edge + 4.0 + above)).dy;
        final gesture = await liftTo(tester, grab, Offset(grab.dx, to));
        final start = position.pixels;
        Rect? last;
        String? lastLabel;
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final strokes = strokedRects(tester);
          expect(strokes, hasLength(1), reason: "$reason, frame $frame");
          last = strokes.single;
          lastLabel = landingText(tester);
        }
        viewport = viewportOf(tester);
        final region = viewport.scrolledRegion;
        if (slots == band) {
          // The first slot rows that show, the first of them in part
          // under the band; the outline's stroke lies 1 px inside them.
          final slot = viewport.rectOfCell(shown.firstSlotRow, col)!.height;
          expect(
            last!.top - 1.0,
            inInclusiveRange(region.top - slot - 0.5, region.top + 0.5),
            reason: reason,
          );
        }
        final fell = start - viewport.verticalPosition!.pixels;
        expect(fell, greaterThan(40.0), reason: reason);
        expect(fell, lessThanOrEqualTo(576.0), reason: reason);
        // The slot row whose bottom the outline's, a stroke 1 px inside
        // the slots' rects, lies on: the outline marks the part of the
        // landing that shows, which may start in rows scrolled past.
        int? lastRow;
        if (last != null) {
          for (var row = shown.firstSlotRow; row < rowCountNow() - 1; row++) {
            final bottom = viewport.rectOfCell(row, col)?.bottom;
            if (bottom != null && (bottom - (last.bottom + 1.0)).abs() < 1.0) {
              lastRow = row;
            }
          }
        }
        await gesture.up();
        await tester.pumpAndSettle();
        if (centreOver) {
          final end = (lastRow! - shown.firstSlotRow + 1) * 15;
          expectTimes(
            store,
            "meet",
            at(tuesday, 0, end - slots * 15),
            at(tuesday, 0, end),
            reason: reason,
          );
          final written = storedOf(store, "meet");
          expect(
            landingLabel(written.start, written.end, DateTime(2026, 1, 5)),
            lastLabel,
            reason: reason,
          );
        }
      }
    }
  });

  testWidgets("TR4 a create drag across the strip from Monday to Wednesday "
      "reports Monday's start to Thursday's", (tester) async {
    final shown = Shown.week(monday);
    final harness = Harness(storeOf(const <CalendarEntry<String>>[]), shown);
    await harness.pump(tester);
    await createDrag(
      tester,
      stripRect(tester, shown, monday).center,
      stripRect(tester, shown, wednesday).center,
    );
    expect(harness.creates, <CreateRange>[
      CreateRange(start: monday, end: thursday),
    ]);
  });

  testWidgets("TR7 with maxDayCount 3 a create drag across the strip from "
      "Monday is held at Thursday's start past Wednesday, and with none it "
      "reaches the day it is let go over", (tester) async {
    final shown = Shown.week(monday);
    for (final (limit, day, end) in <(int?, DateTime, DateTime)>[
      (3, thursday, thursday),
      (3, saturday, thursday),
      (3, wednesday, thursday),
      (null, saturday, sunday),
    ]) {
      final harness = Harness(
        storeOf(const <CalendarEntry<String>>[]),
        shown,
        maxDayCount: limit,
      );
      await harness.pump(tester);
      await createDrag(
        tester,
        stripRect(tester, shown, monday).center,
        stripRect(tester, shown, day).center,
      );
      expect(harness.creates, <CreateRange>[
        CreateRange(start: monday, end: end),
      ], reason: "$limit over $day");
    }
  });

  group("TR9", () {
    testWidgets("a create drag held still over the 11:00 slot, across a "
        "device pixel ratio change that replaces each scrollable's position "
        "and a jump of the new one by four slots, reports 10:00 to 12:15", (
      tester,
    ) async {
      final shown = Shown.week(monday);
      final harness = Harness(
        storeOf(const <CalendarEntry<String>>[]),
        shown,
        minSlotHeight: 40.0,
      );
      await harness.pump(tester);
      final from = slotRect(tester, shown, monday, 10 * 60).center;
      final to = slotRect(tester, shown, monday, 11 * 60).center;
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(to);
      await tester.pump();
      final before = viewportOf(tester).verticalPosition;
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(1600.0, 4000.0);
      await tester.pump();
      final position = viewportOf(tester).verticalPosition!;
      // Setup sanity: the scrollable replaced its position.
      expect(identical(position, before), isFalse);
      position.jumpTo(position.pixels + 160.0);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.creates, <CreateRange>[
        CreateRange(start: at(monday, 10), end: at(monday, 12, 15)),
      ]);
    });

    testWidgets("a create drag across a build of the grid that throws, after "
        "which the grid builds a new board, refocuses through the new board "
        "as its scroll moves", (tester) async {
      final shown = Shown.week(monday);
      final harness = Harness(
        storeOf(const <CalendarEntry<String>>[]),
        shown,
        minSlotHeight: 40.0,
      );
      final scaler = ValueNotifier<TextScaler>(TextScaler.noScaling);
      addTearDown(scaler.dispose);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = harness.size;
      addTearDown(tester.view.reset);
      addTearDown(harness.now.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<TextScaler>(
            valueListenable: scaler,
            builder: (context, value, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: value),
                child: child!,
              );
            },
            child: harness.grid(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final from = slotRect(tester, shown, monday, 10 * 60).center;
      final to = slotRect(tester, shown, monday, 11 * 60).center;
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(to);
      await tester.pump();
      final old = viewportOf(tester);
      scaler.value = const _ThrowingScaler();
      await tester.pump();
      // Setup sanity: the grid's build threw, and its board went.
      expect(tester.takeException(), isA<StateError>());
      expect(find.byType(Board<GridKey, GridShape<String>>), findsNothing);
      scaler.value = TextScaler.noScaling;
      await tester.pump();
      final viewport = viewportOf(tester);
      expect(identical(viewport, old), isFalse);
      final position = viewport.verticalPosition!;
      position.jumpTo(position.pixels + 160.0);
      await tester.pump();
      final cell = viewport.cellAt(viewport.globalToLocal(to))!;
      // Setup sanity: the slot under the pointer is not the one the old
      // board showed there.
      expect(cell.row, isNot(shown.rowOf(11 * 60)));
      // The new board starts at its own scroll offset, so the range runs
      // from wherever that slot is to the anchor's.
      final focus = (cell.row - shown.firstSlotRow) * 15;
      final low = math.min(focus, 10 * 60);
      final high = math.max(focus, 10 * 60);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.creates, <CreateRange>[
        CreateRange(start: at(monday, 0, low), end: at(monday, 0, high + 15)),
      ]);
    });
  });

  group("LD1", () {
    testWidgets("in Week the end handle of Monday 22:00 to Tuesday 02:00 "
        "released on Wednesday's 12:00 slot writes an end of Wednesday "
        "12:15, and the board reports no resize of its own", (tester) async {
      final store = await releaseEndOver(
        tester,
        entries: <CalendarEntry<String>>[nightEntry()],
        id: "night",
        day: tuesday,
        over: wednesday,
        minute: 12 * 60,
      );
      expect(store.moves, <CalendarEntry<String>>[
        entryOf("night", at(monday, 22), at(wednesday, 12, 15)),
      ]);
      expectTimes(store, "night", at(monday, 22), at(wednesday, 12, 15));
    });

    testWidgets("the end handle of a last piece ending at the day's end, "
        "whose span the write leaves as it was, released on Wednesday's "
        "12:00 slot, writes once too", (tester) async {
      final store = await releaseEndOver(
        tester,
        entries: <CalendarEntry<String>>[
          entryOf("late", at(monday, 22), wednesday),
        ],
        id: "late",
        day: tuesday,
        over: wednesday,
        minute: 12 * 60,
      );
      expect(store.moves, <CalendarEntry<String>>[
        entryOf("late", at(monday, 22), at(wednesday, 12, 15)),
      ]);
    });
  });

  testWidgets("LD2 with maxDayCount 3, released over Thursday's 12:00 slot "
      "the end handle writes an end at Thursday's start, over Wednesday's "
      "an end of Wednesday 12:15, and with no limit over Thursday's 12:00 "
      "slot an end of Thursday 12:15", (tester) async {
    for (final (limit, over, end) in <(int?, DateTime, DateTime)>[
      (3, thursday, thursday),
      (3, wednesday, at(wednesday, 12, 15)),
      (null, thursday, at(thursday, 12, 15)),
    ]) {
      final store = await releaseEndOver(
        tester,
        entries: <CalendarEntry<String>>[nightEntry()],
        id: "night",
        day: tuesday,
        over: over,
        minute: 12 * 60,
        limit: limit,
      );
      expect(store.moves, <CalendarEntry<String>>[
        entryOf("night", at(monday, 22), end),
      ], reason: "$limit over ${isoDate(over)}");
    }
  });

  testWidgets("LD3 while the end handle's pointer is over Wednesday's 12:00 "
      "slot the slots up to Wednesday 12:15 are marked and the landing "
      "label names the range", (tester) async {
    final (gesture, _, harness) = await holdEndOver(
      tester,
      entries: <CalendarEntry<String>>[nightEntry()],
      id: "night",
      day: tuesday,
      over: wednesday,
      minute: 12 * 60,
    );
    final shown = harness.shown;
    expect(
      landingText(tester),
      landingLabel(at(monday, 22), at(wednesday, 12, 15), harness.today),
    );
    expect(strokedRects(tester), <Matcher>[
      nearRect(slotsRect(tester, shown, monday, 22 * 60, 24 * 60).deflate(1.0)),
      nearRect(slotsRect(tester, shown, tuesday, 0, 24 * 60).deflate(1.0)),
      nearRect(
        slotsRect(tester, shown, wednesday, 0, 12 * 60 + 15).deflate(1.0),
      ),
    ]);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("LD4 the end handle dragged from a press on its grip's half "
      "outside the block, released on Wednesday's 12:00 slot, writes an end "
      "of Wednesday 12:15 once", (tester) async {
    final store = await releaseEndOver(
      tester,
      entries: <CalendarEntry<String>>[nightEntry()],
      id: "night",
      day: tuesday,
      over: wednesday,
      minute: 12 * 60,
      outside: true,
    );
    expect(store.moves, <CalendarEntry<String>>[
      entryOf("night", at(monday, 22), at(wednesday, 12, 15)),
    ]);
  });

  testWidgets("PG3 in Week, the Saturday piece of Saturday 23:30 to Sunday "
      "00:30 and a Saturday bar, each released on Sunday's 23:30 slot, "
      "record no move sharing time with an entry on the unshown next "
      "Monday", (tester) async {
    final shown = Shown.week(monday);
    final next = entryOf("N", nextMonday, at(nextMonday, 1));
    final crossing = entryOf("X", at(saturday, 23, 30), at(sunday, 0, 30));
    final bar = allDayOf("A", saturday);
    final shared = <String, List<CalendarEntry<String>>>{};
    for (final withNext in const <bool>[false, true]) {
      final pieceStore = storeOf(<CalendarEntry<String>>[
        crossing,
        if (withNext) next,
      ]);
      await Harness(pieceStore, shown, allowsOverlaps: false).pump(tester);
      await moveBlockOnto(
        tester,
        blockFinder("X", saturday),
        slotRect(tester, shown, sunday, 23 * 60 + 30),
      );
      final barStore = storeOf(<CalendarEntry<String>>[
        bar,
        if (withNext) next,
      ]);
      await Harness(barStore, shown, allowsOverlaps: false).pump(tester);
      await dragTo(
        tester,
        tester.getCenter(barFinder("A")),
        slotRect(tester, shown, sunday, 23 * 60 + 30).center,
      );
      if (!withNext) {
        // Setup sanity: each gesture asks for Sunday 23:30 to Monday 00:30.
        expect(pieceStore.moves, <CalendarEntry<String>>[
          crossing.copyWith(
            start: at(sunday, 23, 30),
            end: at(nextMonday, 0, 30),
          ),
        ]);
        expect(barStore.moves, <CalendarEntry<String>>[
          bar.copyWith(start: at(sunday, 23, 30), end: at(nextMonday, 0, 30)),
        ]);
        continue;
      }
      shared["piece"] = movesSharingTime(pieceStore, next);
      shared["bar"] = movesSharingTime(barStore, next);
    }
    expect(shared, <String, List<CalendarEntry<String>>>{
      "piece": <CalendarEntry<String>>[],
      "bar": <CalendarEntry<String>>[],
    });
  });

  testWidgets("PG6 in Week under hours from 06:00 to 22:00, Tuesday 21:00 to "
      "Wednesday 07:00 released on Monday's 21:00 slot records no move "
      "sharing time with Monday 23:00 to 23:30, which the hours hide", (
    tester,
  ) async {
    final shown = Shown.week(monday, hours: const DayHours(6 * 60, 22 * 60));
    final hidden = entryOf("H", at(monday, 23), at(monday, 23, 30));
    final overnight = entryOf("O", at(tuesday, 21), at(wednesday, 7));
    for (final withHidden in const <bool>[false, true]) {
      final store = storeOf(<CalendarEntry<String>>[
        overnight,
        if (withHidden) hidden,
      ]);
      await Harness(store, shown, allowsOverlaps: false).pump(tester);
      if (withHidden) {
        // Setup sanity: the hours leave the hidden entry no block.
        expect(blocksOf("H"), findsNothing);
      }
      await moveBlockOnto(
        tester,
        blockFinder("O", tuesday),
        slotRect(tester, shown, monday, 21 * 60),
      );
      if (!withHidden) {
        // Setup sanity: the drop asks for Monday 21:00 to Tuesday 07:00.
        expect(store.moves, <CalendarEntry<String>>[
          overnight.copyWith(start: at(monday, 21), end: at(tuesday, 7)),
        ]);
        continue;
      }
      expect(movesSharingTime(store, hidden), isEmpty);
      // The store holding the hidden entry, from before the grid's first
      // frame: every change the gates and the hosts' semantics actions
      // ask for covers days of the range alone, which the split reads.
      expect(store.reads.toSet(), <({int first, int last})>{
        daysOf(monday, sunday),
      });
    }
  });

  testWidgets("PG5 in Week the overlap check reads each day outside the "
      "range once between store notifies, a store notify during a drag asks "
      "the drop gate and a crossing's landing again, and a drop's own write "
      "gives the board no new drag config", (tester) async {
    final shown = Shown.week(monday);
    final own = daysOf(monday, sunday);
    bool isAfter(({int first, int last}) range) {
      return range.first > own.last;
    }

    final ownOrAfter = predicate<({int first, int last})>((range) {
      return range == own || isAfter(range);
    }, "the grid's own range or one wholly after it");
    final next = entryOf("N", nextMonday, at(nextMonday, 1));
    final crossing = entryOf("X", at(saturday, 23, 30), at(sunday, 0, 30));

    // A block held over Sunday's late slots, whose moves reach the next
    // Monday.
    var store = storeOf(<CalendarEntry<String>>[crossing, next]);
    await Harness(store, shown, allowsOverlaps: false).pump(tester);
    final block = tester.getRect(blockFinder("X", saturday));
    final gesture = await lift(tester, block.center);
    Future<void> holdOver(int minute) async {
      final slot = slotRect(tester, shown, sunday, minute);
      await gesture.moveTo(
        block.center + slot.topLeft - block.topLeft + const Offset(0.0, 2.0),
      );
      await tester.pump();
    }

    await holdOver(20 * 60);
    for (var i = 0; i < 2; i++) {
      await holdOver(23 * 60 + 15);
      await holdOver(23 * 60 + 30);
    }
    final beforeDelete = store.reads.where(isAfter).length;
    final config = boardOf(tester).drag;
    store.requestDelete("N");
    await tester.pump();
    await tester.pump();
    final renewed = boardOf(tester).drag;
    expect(renewed, isNot(same(config)));
    expect(
      (beforeDelete, store.reads.where(isAfter).length - beforeDelete),
      (1, 1),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.moves, <CalendarEntry<String>>[
      crossing.copyWith(start: at(sunday, 23, 30), end: at(nextMonday, 0, 30)),
    ]);
    expect(boardOf(tester).drag, same(renewed));
    expect(store.reads, everyElement(ownOrAfter));

    // A block whose moves stay inside the range.
    final meet = entryOf("T", at(tuesday, 10), at(tuesday, 11));
    store = storeOf(<CalendarEntry<String>>[meet]);
    await Harness(store, shown, allowsOverlaps: false).pump(tester);
    final from = tester.getRect(blockFinder("T", tuesday));
    final held = await lift(tester, from.center);
    for (final (day, minute) in <(DateTime, int)>[
      (tuesday, 14 * 60),
      (wednesday, 10 * 60),
    ]) {
      final slot = slotRect(tester, shown, day, minute);
      await held.moveTo(
        from.center + slot.topLeft - from.topLeft + const Offset(0.0, 2.0),
      );
      await tester.pump();
    }
    await held.up();
    await tester.pumpAndSettle();
    // Setup sanity: the drop landed.
    expect(store.moves, <CalendarEntry<String>>[
      meet.copyWith(start: at(wednesday, 10), end: at(wednesday, 11)),
    ]);
    expect(store.reads.toSet(), <({int first, int last})>{own});

    // A bar held over Sunday's 23:30 slot, whose hour reaches the next
    // Monday.
    final bar = allDayOf("A", saturday);
    store = storeOf(<CalendarEntry<String>>[bar, next]);
    await Harness(store, shown, allowsOverlaps: false).pump(tester);
    final crossed = await liftTo(
      tester,
      tester.getCenter(barFinder("A")),
      slotRect(tester, shown, sunday, 23 * 60 + 30).center,
    );
    expect(landingText(tester), noLandingLabel);
    store.requestDelete("N");
    await tester.pump();
    await tester.pump();
    expect(
      landingText(tester),
      landingLabel(
        at(sunday, 23, 30),
        at(nextMonday, 0, 30),
        DateTime(2026, 1, 5),
      ),
    );
    await crossed.up();
    await tester.pumpAndSettle();
    expect(store.moves, <CalendarEntry<String>>[
      bar.copyWith(start: at(sunday, 23, 30), end: at(nextMonday, 0, 30)),
    ]);
    expect(store.reads, everyElement(ownOrAfter));
  });

  group("on the 25-hour day", skip: longDaySkip, () {
    testWidgets("PG7 in Day, the second 01:40 to 02:10 released on the 01:00 "
        "row records no move sharing time with the first 01:30 to the "
        "second 01:30, whose block lies on the rows from 01:30", (
      tester,
    ) async {
      final day = longDayStart;
      final shown = Shown.day(day);
      final repeated = entryOf(
        "E1",
        day.add(const Duration(minutes: 90)),
        secondHalfPastOne,
      );
      final moved = entryOf(
        "M",
        secondHalfPastOne.add(const Duration(minutes: 10)),
        at(day, 2, 10),
      );
      for (final withRepeated in const <bool>[false, true]) {
        final store = storeOf(<CalendarEntry<String>>[
          moved,
          if (withRepeated) repeated,
        ]);
        await Harness(store, shown, allowsOverlaps: false).pump(tester);
        final settled = store.reads.length;
        final block = tester.getRect(blockFinder("M", day));
        final row = slotRect(tester, shown, day, 60);
        final gesture = await lift(tester, block.center);
        await gesture.moveBy(Offset(0.0, row.top - block.top + 2.0));
        await tester.pump();
        final held = store.reads.length;
        await gesture.up();
        await tester.pumpAndSettle();
        if (!withRepeated) {
          // Setup sanity: the drop asks for the second 01:00 to the second
          // 01:30.
          expect(store.moves, <CalendarEntry<String>>[
            moved.copyWith(
              start: secondHalfPastOne.subtract(const Duration(minutes: 30)),
              end: secondHalfPastOne,
            ),
          ]);
          continue;
        }
        expect(movesSharingTime(store, repeated), isEmpty);
        // The store holding the repeated entry: the split's read of the
        // day alone, and none from the grid's first settled frame to the
        // release, the gates searching what the split indexed.
        expect(store.reads.toSet(), <({int first, int last})>{
          daysOf(day, day),
        });
        expect(held - settled, 0);
      }
    });
  });

  testWidgets("PG1 in Week under a policy refusing any change of F that "
      "ends after 12:00, a move of F onto the 12:00 slot and a drag of its "
      "end handle to 12:30 record no move of F ending after 12:00", (
    tester,
  ) async {
    final shown = Shown.week(monday);
    final f = entryOf("F", at(tuesday, 10), at(tuesday, 11));
    final refusing = ScriptedEditPolicy<String>(
      admits: (entry, start, end) {
        return entry.id != "F" || !end.isAfter(at(tuesday, 12));
      },
    );
    List<CalendarEntry<String>> endingAfterNoon(MoveRecordingStore store) {
      return <CalendarEntry<String>>[
        for (final move in store.moves)
          if (move.id == "F" && move.end.isAfter(at(tuesday, 12))) move,
      ];
    }

    for (final policy in <CalendarEditPolicy<String>?>[null, refusing]) {
      final moved = storeOf(<CalendarEntry<String>>[f]);
      await Harness(moved, shown, editPolicy: policy).pump(tester);
      await moveBlockOnto(
        tester,
        blockFinder("F", tuesday),
        slotRect(tester, shown, tuesday, 12 * 60),
      );

      final resized = storeOf(<CalendarEntry<String>>[f]);
      await Harness(resized, shown, editPolicy: policy).pump(tester);
      final selecting = await lift(
        tester,
        tester.getCenter(blockFinder("F", tuesday)),
      );
      await selecting.up();
      await tester.pumpAndSettle();
      final block = tester.getRect(blockFinder("F", tuesday));
      final from = Offset(block.center.dx, block.bottom - 2.0);
      final to = Offset(
        from.dx,
        slotRect(tester, shown, tuesday, 12 * 60 + 15).bottom - 2.0,
      );
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      if (policy == null) {
        // Setup sanity: the unrestricted policy lets both gestures end F
        // after 12:00.
        expect(moved.moves, <CalendarEntry<String>>[
          f.copyWith(start: at(tuesday, 12), end: at(tuesday, 13)),
        ]);
        expect(resized.moves, <CalendarEntry<String>>[
          f.copyWith(end: at(tuesday, 12, 30)),
        ]);
        continue;
      }
      expect(endingAfterNoon(moved), isEmpty);
      expect(endingAfterNoon(resized), isEmpty);
    }
  });

  testWidgets("PG2 under a day limit of 2 a create drag from Monday 10:00 "
      "to Thursday 12:00, a Monday bar's right grip dragged to Thursday and "
      "Monday's end handle dragged into Thursday's 12:00 slot each end at "
      "Wednesday's start, and with no limit they reach Thursday", (
    tester,
  ) async {
    final shown = Shown.week(monday);
    for (final limit in <int?>[2, null]) {
      final harness = Harness(
        storeOf(const <CalendarEntry<String>>[]),
        shown,
        maxDayCount: limit,
      );
      await harness.pump(tester);
      // Setup sanity: the harness gives the grid the limit's policy.
      expect(harness.policy.dayLimit, limit);
      await createDrag(
        tester,
        slotRect(tester, shown, monday, 10 * 60).center,
        slotRect(tester, shown, thursday, 12 * 60).center,
      );
      expect(harness.creates, <CreateRange>[
        CreateRange(
          start: at(monday, 10),
          end: limit == null ? at(thursday, 12, 15) : wednesday,
        ),
      ], reason: "create under $limit");

      final bar = await releaseBarEdge(
        tester,
        limit: limit,
        id: "m",
        day: monday,
        side: AxisDirection.right,
        over: thursday,
      );
      expect(
        bar.moves.single.end,
        limit == null ? friday : wednesday,
        reason: "bar under $limit",
      );

      final end = await releaseEndOver(
        tester,
        entries: <CalendarEntry<String>>[
          entryOf("e", at(monday, 10), at(monday, 11)),
        ],
        id: "e",
        day: monday,
        over: thursday,
        minute: 12 * 60,
        limit: limit,
      );
      expect(
        end.moves.single.end,
        limit == null ? at(thursday, 12, 15) : wednesday,
        reason: "end handle under $limit",
      );
    }
  });

  testWidgets("PG4 in Week each gesture's pointer moves ask the policy at "
      "most twice per gate call, three times in a bar's landing on the "
      "slots, with 2 entries packed beside the moved one and with 200, and "
      "no ask reads allowsOverlaps or dayLimit", (tester) async {
    final shown = Shown.week(monday);

    /// The asks of [asks] made outside a build, grouped by the gate call
    /// each falls in: the size of each group.
    List<int> groupSizes(List<PolicyAsk> asks) {
      final groups = <int, int>{};
      for (final ask in asks) {
        if (ask.phase != SchedulerPhase.persistentCallbacks) {
          groups[ask.gate] = (groups[ask.gate] ?? 0) + 1;
        }
      }
      return groups.values.toList();
    }

    /// Ten pointer moves of [gesture] from [from] to [to], a frame after
    /// each.
    Future<void> tenMoves(TestGesture gesture, Offset from, Offset to) async {
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
        await tester.pump();
      }
    }

    /// Selects the free entry with a long press let go in place.
    Future<void> selectFree() async {
      final selecting = await lift(
        tester,
        tester.getCenter(blockFinder("free", tuesday)),
      );
      await selecting.up();
      await tester.pumpAndSettle();
    }

    final gestures = <String, Future<void> Function()>{
      "move": () async {
        final from = tester.getCenter(blockFinder("free", tuesday));
        final gesture = await lift(tester, from);
        await tenMoves(
          gesture,
          from,
          slotRect(tester, shown, tuesday, 2 * 60).center,
        );
        await gesture.up();
        await tester.pumpAndSettle();
      },
      "start": () async {
        final block = tester.getRect(blockFinder("free", tuesday));
        final from = Offset(block.center.dx, block.top + 2.0);
        final gesture = await tester.startGesture(from);
        await tenMoves(
          gesture,
          from,
          Offset(from.dx, slotRect(tester, shown, tuesday, 2 * 60).top + 2.0),
        );
        await gesture.up();
        await tester.pumpAndSettle();
      },
      "end": () async {
        final block = tester.getRect(blockFinder("free", tuesday));
        final from = Offset(block.center.dx, block.bottom - 2.0);
        final gesture = await tester.startGesture(from);
        await tenMoves(
          gesture,
          from,
          slotRect(tester, shown, thursday, 12 * 60).center,
        );
        await gesture.up();
        await tester.pumpAndSettle();
      },
      "bar": () async {
        final from = tester.getCenter(barFinder("bar"));
        final gesture = await lift(tester, from);
        await tenMoves(
          gesture,
          from,
          slotRect(tester, shown, tuesday, 10 * 60).center,
        );
        await gesture.up();
        await tester.pumpAndSettle();
      },
    };

    for (final count in const <int>[2, 200]) {
      for (final allowsOverlaps in const <bool>[false, true]) {
        for (final MapEntry(key: name, value: run) in gestures.entries) {
          final policy = CountingEditPolicy<String>(
            allowsOverlaps
                ? const UnrestrictedEditPolicy<String>()
                : const NoOverlapsPolicy<String>(),
          );
          final store = storeOf(<CalendarEntry<String>>[
            for (var i = 0; i < count; i++)
              entryOf("p$i", at(tuesday, 0, 5 * i), at(tuesday, 0, 5 * i + 5)),
            entryOf("free", at(tuesday, 18), at(tuesday, 19)),
            allDayOf("bar", monday),
          ]);
          await Harness(store, shown, editPolicy: policy).pump(tester);
          if (name == "start" || name == "end") {
            await selectFree();
          }
          final mark = policy.asked.length;
          await run();
          final asked = policy.asked.sublist(mark);
          final reason = "$name with $count, allowsOverlaps $allowsOverlaps";
          final sizes = groupSizes(asked);
          // Setup sanity: the pointer path reached a gate.
          expect(sizes, isNotEmpty, reason: reason);
          expect(
            sizes.reduce(math.max),
            lessThanOrEqualTo(name == "bar" ? 3 : 2),
            reason: reason,
          );
          expect(
            asked.where((ask) {
              return ask.name == "allowsOverlaps" || ask.name == "dayLimit";
            }),
            isEmpty,
            reason: reason,
          );
        }
      }
    }
  });

  testWidgets("MR1 with onMoveRequest each move and resize a gesture lands "
      "reaches it once, as the stored entry, that entry at the times the "
      "gesture gave it and the gesture's kind, and the store is asked for "
      "no write", (tester) async {
    final shown = Shown.week(monday);
    final requests = <String, List<CalendarMoveRequest<String>>>{};
    final stores = <String, MoveRecordingStore>{};
    Future<void> Function(CalendarMoveRequest<String> request) recordAs(
      String name,
    ) {
      final into = requests[name] = <CalendarMoveRequest<String>>[];
      return (request) async {
        into.add(request);
      };
    }

    stores["bar move"] = await moveBarTwoColumns(
      tester,
      onMoveRequest: recordAs("bar move"),
    );
    stores["bar start"] = await resizeBarStart(
      tester,
      onMoveRequest: recordAs("bar start"),
    );
    stores["bar end"] = await resizeBarEnd(
      tester,
      onMoveRequest: recordAs("bar end"),
    );
    stores["bar on slot"] = await dropBarOnSlot(
      tester,
      shown,
      onMoveRequest: recordAs("bar on slot"),
    );
    stores["block on strip"] = await dropBlockOnStrip(
      tester,
      shown,
      onMoveRequest: recordAs("block on strip"),
    );
    stores["end on a later day"] = await releaseEndOver(
      tester,
      entries: <CalendarEntry<String>>[nightEntry()],
      id: "night",
      day: tuesday,
      over: wednesday,
      minute: 12 * 60,
      onMoveRequest: recordAs("end on a later day"),
    );
    stores["bar end held"] = await releaseBarEdge(
      tester,
      limit: 3,
      id: "m",
      day: monday,
      side: AxisDirection.right,
      over: saturday,
      onMoveRequest: recordAs("bar end held"),
    );
    final meet = entryOf("meet", at(tuesday, 10), at(tuesday, 11));
    final blockStore = storeOf(<CalendarEntry<String>>[meet]);
    await Harness(
      blockStore,
      shown,
      onMoveRequest: recordAs("block move"),
    ).pump(tester);
    await moveBlockOnto(
      tester,
      blockFinder("meet", tuesday),
      slotRect(tester, shown, tuesday, 14 * 60),
    );
    stores["block move"] = blockStore;

    CalendarMoveRequest<String> request(
      CalendarEntry<String> entry,
      DateTime start,
      DateTime end,
      CalendarMoveKind kind,
    ) {
      return CalendarMoveRequest<String>(
        entry: entry,
        requested: entry.copyWith(start: start, end: end),
        kind: kind,
      );
    }

    const move = CalendarMoveKind.move;
    const resize = CalendarMoveKind.resize;
    final trip = allDayOf("trip", tuesday, days: 2);
    final night = nightEntry();
    expect(requests, <String, List<CalendarMoveRequest<String>>>{
      "bar move": <CalendarMoveRequest<String>>[
        request(allDayOf("off", monday), wednesday, thursday, move),
      ],
      "bar start": <CalendarMoveRequest<String>>[
        request(trip, monday, thursday, resize),
      ],
      "bar end": <CalendarMoveRequest<String>>[
        request(trip, tuesday, friday, resize),
      ],
      "bar on slot": <CalendarMoveRequest<String>>[
        request(
          allDayOf("off", tuesday),
          at(tuesday, 10),
          at(tuesday, 11),
          move,
        ),
      ],
      "block on strip": <CalendarMoveRequest<String>>[
        request(meet, tuesday, wednesday, move),
      ],
      "end on a later day": <CalendarMoveRequest<String>>[
        request(night, night.start, at(wednesday, 12, 15), resize),
      ],
      "bar end held": <CalendarMoveRequest<String>>[
        request(allDayOf("m", monday), monday, thursday, resize),
      ],
      "block move": <CalendarMoveRequest<String>>[
        request(meet, at(tuesday, 14), at(tuesday, 15), move),
      ],
    });
    for (final MapEntry(key: name, value: store) in stores.entries) {
      expect(store.moves, isEmpty, reason: name);
    }
  });

  testWidgets("MR2 while a request's future runs, its block shows at the "
      "requested times and pending, opening nothing on a tap and lifting "
      "for no long press; once it completes the block shows the store's "
      "entry, at its stored times where the host wrote nothing and at the "
      "requested ones where it wrote the request", (tester) async {
    final shown = Shown.week(monday);
    final meet = entryOf("meet", at(tuesday, 10), at(tuesday, 11));
    Finder spinner() {
      return find.descendant(
        of: blockFinder("meet", tuesday),
        matching: find.byType(CalendarActivityIndicator),
      );
    }

    for (final writes in const <bool>[false, true]) {
      final reason = writes ? "written" : "let go";
      final store = storeOf(<CalendarEntry<String>>[meet]);
      final requests = <CalendarMoveRequest<String>>[];
      final answer = Completer<void>();
      final harness = Harness(
        store,
        shown,
        onMoveRequest: (request) {
          requests.add(request);
          return answer.future;
        },
      );
      await harness.pump(tester);
      final stored = tester.getRect(blockFinder("meet", tuesday));
      final inset = stored.top - slotRect(tester, shown, tuesday, 10 * 60).top;
      final slot = slotRect(tester, shown, tuesday, 14 * 60);
      // A pending block's indicator runs while the entry is pending, so
      // the frames are pumped for a time rather than settled.
      final gesture = await lift(tester, stored.center);
      await gesture.moveBy(
        slot.topLeft - stored.topLeft + const Offset(0.0, 2.0),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Setup sanity: the drop made its one request, which runs.
      expect(requests, hasLength(1), reason: reason);
      final held = tester.getRect(blockFinder("meet", tuesday));
      expect(held.top, closeTo(slot.top + inset, 0.01), reason: reason);
      expect(held.height, closeTo(stored.height, 0.01), reason: reason);
      expect(spinner(), findsOneWidget, reason: reason);

      await tester.tap(blockFinder("meet", tuesday));
      await tester.pump(const Duration(milliseconds: 500));
      expect(harness.opened, isEmpty, reason: reason);
      final pressing = await lift(tester, held.center);
      expect(find.byKey(liftedBlockKey), findsNothing, reason: reason);
      await pressing.up();
      await tester.pump(const Duration(milliseconds: 500));

      if (writes) {
        await store.requestMove(requests.single.requested);
      }
      answer.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(spinner(), findsNothing, reason: reason);
      expect(
        tester.getRect(blockFinder("meet", tuesday)),
        nearRect(writes ? held : stored),
        reason: reason,
      );
      await tester.tap(blockFinder("meet", tuesday));
      await tester.pump(const Duration(milliseconds: 500));
      expect(harness.opened, <String>["meet"], reason: reason);
    }
  });

  testWidgets("MR3 a request whose function throws within the call, and one "
      "with none whose write the caching store fails, each show the block "
      "at its stored times again, and their errors are not caught", (
    tester,
  ) async {
    final shown = Shown.week(monday);
    final meet = entryOf("meet", at(tuesday, 10), at(tuesday, 11));
    final thrown = StateError("Refused.");
    final uncaught = <Object>[];
    // The drop runs in a zone of its own, which receives the errors the
    // futures it starts leave uncaught. A pending block's indicator runs
    // while the entry is pending, so the frames after it are pumped for
    // a time rather than settled.
    Future<void> dropInZone() async {
      final from = tester.getRect(blockFinder("meet", tuesday));
      final slot = slotRect(tester, shown, tuesday, 14 * 60);
      final gesture = await lift(tester, from.center);
      await runZonedGuarded(
        () async {
          await gesture.moveBy(
            slot.topLeft - from.topLeft + const Offset(0.0, 2.0),
          );
          await tester.pump();
          await gesture.up();
        },
        (error, stackTrace) {
          uncaught.add(error);
        },
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    final memory = storeOf(<CalendarEntry<String>>[meet]);
    await Harness(
      memory,
      shown,
      onMoveRequest: (request) {
        throw thrown;
      },
    ).pump(tester);
    final stored = tester.getRect(blockFinder("meet", tuesday));
    await dropInZone();
    expect(uncaught, <Object>[same(thrown)]);
    expect(tester.getRect(blockFinder("meet", tuesday)), nearRect(stored));

    uncaught.clear();
    final source = HeldSource(<CalendarEntry<String>>[meet]);
    final caching = CachingCalendarStore<String>(dataSource: source);
    addTearDown(caching.dispose);
    caching.show(monday, sunday);
    await Harness(caching, shown).pump(tester);
    await dropInZone();
    // Setup sanity: with no onMoveRequest the drop wrote to the store.
    expect(source.replaces, hasLength(1));
    source.replaces.single.completeError(thrown);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(uncaught, <Object>[same(thrown)]);
    expect(tester.getRect(blockFinder("meet", tuesday)), nearRect(stored));
  });
}

/// Lifts [block] at its centre, moves it so its top lies 2 px below
/// [slot]'s, which the drop snaps to, lets go and lets the drop settle.
Future<void> moveBlockOnto(WidgetTester tester, Finder block, Rect slot) async {
  final from = tester.getRect(block);
  final gesture = await lift(tester, from.center);
  await gesture.moveBy(slot.topLeft - from.topLeft + const Offset(0.0, 2.0));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The moves [store] was asked for that share time with [other].
List<CalendarEntry<String>> movesSharingTime(
  MoveRecordingStore store,
  CalendarEntry<String> other,
) {
  return <CalendarEntry<String>>[
    for (final move in store.moves)
      if (rangeSharesTime(move.start, move.end, other)) move,
  ];
}

/// A text scaler whose every scale throws, so a build that lays text out
/// under it throws. Its factor, which [MediaQueryData]'s equality reads,
/// is 2.
class _ThrowingScaler extends TextScaler {
  const _ThrowingScaler();

  @override
  double scale(double fontSize) {
    throw StateError("No scale.");
  }

  @override
  double get textScaleFactor {
    return 2.0;
  }

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) {
    return this;
  }
}

/// The ids of the custom semantics actions the node of [finder] offers.
List<int> actionsOf(WidgetTester tester, Finder finder) {
  return tester
          .getSemantics(finder)
          .getSemanticsData()
          .customSemanticsActionIds ??
      const <int>[];
}

/// The id of the custom semantics action labelled [label].
int actionId(String label) {
  return CustomSemanticsAction.getIdentifier(
    CustomSemanticsAction(label: label),
  );
}

/// The hour a bar released at [global] over [day]'s column would take:
/// from the start of the slot under it, read from the board's own cell
/// lookup, to an hour after.
({DateTime start, DateTime end}) hourUnder(
  WidgetTester tester,
  Shown shown,
  DateTime day,
  Offset global,
) {
  final viewport = viewportOf(tester);
  final cell = viewport.cellAt(viewport.globalToLocal(global))!;
  final grid =
      find.byType(TimedGrid<String>).evaluate().single.widget
          as TimedGrid<String>;
  final row = math.max(cell.row, shown.firstSlotRow);
  final minute =
      grid.hours.start + (row - shown.firstSlotRow) * grid.slotMinutes;
  final start = at(day, 0, minute);
  return (start: start, end: start.add(const Duration(hours: 1)));
}

/// The grid viewport's children, in the order it paints them.
List<RenderObject> paintOrderOf(WidgetTester tester) {
  final order = <RenderObject>[];
  viewportOf(tester).visitChildrenForSemantics(order.add);
  return order;
}

/// The viewport's child that holds what [finder] finds.
RenderObject itemBoxOf(WidgetTester tester, Finder finder) {
  final viewport = viewportOf(tester);
  RenderObject box = tester.renderObject(finder);
  while (box.parent != viewport) {
    box = box.parent!;
  }
  return box;
}
