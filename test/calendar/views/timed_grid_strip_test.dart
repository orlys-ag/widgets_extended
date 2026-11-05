/// The timed grid's all-day strip: its bars, rows, count and expansion, the
/// gestures on bars within the strip, the crossings of a bar into the
/// slots, of a block into the strip and of Week's end handle into a later
/// day with their live marks, the create ranges across the strip, the
/// landing label's times in the grid's hour format, and each site's asks of
/// a per-pair answer on overlaps.
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
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/entries/calendar_data_source.dart';
import 'package:widgets_extended/scheduling/entries/calendar_entry.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/policy/history_lock_policy.dart';
import 'package:widgets_extended/calendar/presentation/calendar_activity_indicator.dart';
import 'package:widgets_extended/calendar/presentation/calendar_builders.dart';
import 'package:widgets_extended/calendar/presentation/calendar_defaults.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/scheduling/store/caching_calendar_store.dart';
import 'package:widgets_extended/scheduling/store/calendar_store.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/create_details.dart';
import 'package:widgets_extended/calendar/views/entry_split.dart';
import 'package:widgets_extended/calendar/views/move_request.dart';
import 'package:widgets_extended/calendar/views/pinch_zoom.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/timed_grid_layout.dart';

import '../../scheduling/dst_days.dart';
import '../edit_policies.dart';
import '../recording_errors.dart';

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
  bool isAllDay = false,
}) {
  return CalendarEntry<String>(
    id: id,
    start: start,
    end: end,
    title: title ?? id,
    color: const Color(0xFF336699),
    payload: id,
    isAllDay: isAllDay,
  );
}

/// An all-day entry over the [days] days from [first].
CalendarEntry<String> allDayOf(
  String id,
  DateTime first, {
  int days = 1,
  String? title,
}) {
  return entryOf(
    id,
    first,
    CalendarDates.addDays(first, days),
    title: title,
    isAllDay: true,
  );
}

/// A grid the tests pump: Week over the seven days from [first], under a
/// day header, or Day over [first] alone, with none; its slots of
/// [slotMinutes] over [hours].
class Shown {
  const Shown.week(
    this.first, {
    this.hours = CalendarDayHours.allDay,
    this.slotMinutes = 15,
  }) : week = true;

  const Shown.day(
    this.first, {
    this.hours = CalendarDayHours.allDay,
    this.slotMinutes = 15,
  }) : week = false;

  final DateTime first;
  final bool week;
  final CalendarDayHours hours;
  final int slotMinutes;

  /// The row of the all-day strip's first row: under the day header in
  /// Week, the grid's top row in Day.
  int get stripStart {
    return week ? 1 : 0;
  }

  /// The row of the first slot of the grid shown now: its board's row
  /// count less its slot rows and the room below them.
  int get firstSlotRow {
    final grid = gridNow();
    return rowCountNow() - grid.hours.slotCountOf(grid.slotMinutes) - 1;
  }

  /// The row of the slot starting at [minute] of the grid shown now.
  int rowOf(int minute) {
    final grid = gridNow();
    return firstSlotRow + (minute - grid.hours.start) ~/ grid.slotMinutes;
  }

  /// The column of [day], which the grid shows.
  int colOf(DateTime day) {
    return week ? 1 + CalendarDates.daysBetween(first, day) : 1;
  }

  String get name {
    return week ? "Week" : "Day";
  }
}

/// The grid shown now, whatever its payload type.
TimedGrid<Object?> gridNow() {
  return find
          .byWidgetPredicate((widget) {
            return widget is TimedGrid<Object?>;
          })
          .evaluate()
          .single
          .widget
      as TimedGrid<Object?>;
}

/// The number of rows of the grid's board shown now, whatever its payload
/// type.
int rowCountNow() {
  final board =
      find
              .byWidgetPredicate((widget) {
                return widget is Board<GridKey, GridShape<Object?>>;
              })
              .evaluate()
              .single
              .widget
          as Board<GridKey, GridShape<Object?>>;
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
      CalendarThemeData().primaryTint;
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
  return (
    first: CalendarDates.dayNumber(first),
    last: CalendarDates.dayNumber(last),
  );
}

/// A store holding [entries], disposed at the test's end.
MoveRecordingStore storeOf(
  List<CalendarEntry<String>> entries, {
  CalendarDayHours hours = CalendarDayHours.allDay,
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
        if (CalendarDates.dayNumber(entry.start) <= to &&
            CalendarDates.lastDayNumberOf(entry.start, entry.end) >= from)
          entry,
    ];
  }

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    final from = CalendarDates.dayNumber(first);
    final to = CalendarDates.dayNumber(last);
    final holds = held.any((day) {
      final number = CalendarDates.dayNumber(day);
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
      read.complete(
        _between(CalendarDates.dayNumber(first), CalendarDates.dayNumber(last)),
      );
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
/// default [minDayWidth]; [creates] records each create range it reports,
/// unless [onCreate] takes them, and [opened] each entry it opens,
/// [onMoveRequest] takes each move and
/// resize it lands, and [onZoom] each zoom a pinch reports, which the grid
/// does not show. The grid writes times in [hourLabelFormat]. [store],
/// [editable], [first], [hours], [slotMinutes] and [editPolicy] start as
/// given, and [rebuild] builds the grid again with them and with
/// [givenNow]. The grid's policy is [editPolicy]
/// where it is given, and otherwise the one [lockPast],
/// [lockEarlierToday], [maxDayCount] and [allowsOverlaps] make
/// ([policy]). Its clock is [givenNow] where it is set, and [now]
/// otherwise.
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
    this.onCreate,
    this.onZoom,
    this.blockBuilder,
    this.hourLabelFormat = CalendarHourLabelFormat.twentyFourHour,
    DateTime? today,
    int nowHour = 9,
  }) : today = today ?? DateTime(2026, 1, 5),
       _nowHour = nowHour,
       first = shown.first,
       hours = shown.hours,
       slotMinutes = shown.slotMinutes;

  CalendarStore<String> store;
  final Shown shown;
  final int? maxDayCount;
  final bool lockPast;
  final bool lockEarlierToday;
  final bool allowsOverlaps;
  CalendarEditPolicy<String>? editPolicy;
  final double minSlotHeight;
  final double minDayWidth;
  final Size size;
  final DateTime today;
  final Future<void> Function(CalendarMoveRequest<String> request)?
  onMoveRequest;
  final Future<void> Function(CalendarCreateDetails details)? onCreate;
  final void Function(double minSlotHeight, double minDayWidth)? onZoom;
  final CalendarBlockBuilder<String>? blockBuilder;
  final CalendarHourLabelFormat hourLabelFormat;

  bool editable;
  DateTime first;
  CalendarDayHours hours;
  int slotMinutes;

  final List<CalendarCreateRange> creates = <CalendarCreateRange>[];
  final List<String> opened = <String>[];
  final int _nowHour;
  late final ValueNotifier<CalendarNow> now = ValueNotifier<CalendarNow>(
    CalendarNow(time: at(today, _nowHour), today: today),
  );

  /// The clock the grid takes in place of [now] where it is set.
  ValueListenable<CalendarNow>? givenNow;

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
      now: givenNow ?? now,
      onSelectDay: (day) {},
      onOpenEntry: opened.add,
      onCreate:
          onCreate ??
          (details) async {
            creates.add(details.range);
          },
      onMoveRequest: onMoveRequest,
      onZoom: onZoom,
      editable: editable,
      editPolicy: policy,
      hours: hours,
      slotMinutes: slotMinutes,
      minSlotHeight: minSlotHeight,
      minDayWidth: minDayWidth,
      showsDayHeader: shown.week,
      blockBuilder: blockBuilder,
      hourLabelFormat: hourLabelFormat,
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
List<Shown> bothGrids({CalendarDayHours hours = CalendarDayHours.allDay}) {
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

/// TX1's gesture: in Week, Monday's one-day bar moved two columns, under
/// [editPolicy] where it is given.
Future<MoveRecordingStore> moveBarTwoColumns(
  WidgetTester tester, {
  CalendarDayHours hours = CalendarDayHours.allDay,
  Future<void> Function(CalendarMoveRequest<String> request)? onMoveRequest,
  CalendarEditPolicy<String>? editPolicy,
}) async {
  final shown = Shown.week(monday, hours: hours);
  final store = storeOf(<CalendarEntry<String>>[
    allDayOf("off", monday),
  ], hours: hours);
  await Harness(
    store,
    shown,
    onMoveRequest: onMoveRequest,
    editPolicy: editPolicy,
  ).pump(tester);
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

/// TX4's first gesture: Tuesday's bar let go on Tuesday's 10:00 slot,
/// under [editPolicy] where it is given.
Future<MoveRecordingStore> dropBarOnSlot(
  WidgetTester tester,
  Shown shown, {
  Future<void> Function(CalendarMoveRequest<String> request)? onMoveRequest,
  CalendarEditPolicy<String>? editPolicy,
}) async {
  final store = storeOf(<CalendarEntry<String>>[allDayOf("off", tuesday)]);
  await Harness(
    store,
    shown,
    onMoveRequest: onMoveRequest,
    editPolicy: editPolicy,
  ).pump(tester);
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

/// TX8's gesture: in Week over [hours], under [limit], the selected
/// one-day bar of [id] on [day] has its edge on [side] dragged so the
/// pointer lies over [over], with [others] in the strip too; returns the
/// gesture still held and the store.
Future<(TestGesture, MoveRecordingStore)> holdBarEdge(
  WidgetTester tester, {
  required int? limit,
  required String id,
  required DateTime day,
  required AxisDirection side,
  required DateTime over,
  List<CalendarEntry<String>> others = const <CalendarEntry<String>>[],
  Future<void> Function(CalendarMoveRequest<String> request)? onMoveRequest,
  CalendarDayHours hours = CalendarDayHours.allDay,
}) async {
  final shown = Shown.week(monday, hours: hours);
  final store = storeOf(<CalendarEntry<String>>[
    allDayOf(id, day),
    ...others,
  ], hours: hours);
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
  CalendarDayHours hours = CalendarDayHours.allDay,
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
    hours: hours,
  );
  await gesture.up();
  await tester.pumpAndSettle();
  return store;
}

/// Monday 22:00 to Tuesday 02:00, whose end handle the LD tests drag.
CalendarEntry<String> nightEntry() {
  return entryOf("night", at(monday, 22), at(tuesday, 2));
}

/// The LD tests' gesture: in Week from [first], or with none from
/// [monday], over [hours], under [limit], or under [editPolicy] where it
/// is given, the entry [id] of [entries] selected and the end grip of its
/// last piece, on [day], pressed 2 px above that block's bottom, on the
/// grip's half inside the block, or with [outside] 2 px below it, on the
/// half outside; then dragged so the pointer lies over the slot starting
/// at [minute] in [over]'s column. Returns the gesture still held, the
/// store and the harness.
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
  CalendarEditPolicy<String>? editPolicy,
  CalendarDayHours hours = CalendarDayHours.allDay,
  DateTime? first,
}) async {
  final shown = Shown.week(first ?? monday, hours: hours);
  final store = storeOf(entries, hours: hours);
  final harness = Harness(
    store,
    shown,
    maxDayCount: limit,
    onMoveRequest: onMoveRequest,
    editPolicy: editPolicy,
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
  CalendarEditPolicy<String>? editPolicy,
  CalendarDayHours hours = CalendarDayHours.allDay,
  DateTime? first,
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
    editPolicy: editPolicy,
    hours: hours,
    first: first,
  );
  await gesture.up();
  await tester.pumpAndSettle();
  return store;
}

/// Lifts the block of "meet" on Tuesday in [shown], drops it with its top
/// on Tuesday's 14:00 slot, and pumps a second of frames: a pending block's
/// indicator runs while its entry is pending, so the frames do not settle.
///
/// An error left uncaught in the test's own zone ends the test as failed
/// ([TestWidgetsFlutterBinding] runs the test body in a zone whose handler
/// reports it), before [WidgetTester.takeException] can take it. So the
/// drop's move and release run in a zone of their own, which adds to
/// [uncaught] each error the futures they start leave uncaught.
Future<void> dropMeetInZone(
  WidgetTester tester,
  Shown shown,
  List<Object> uncaught,
) async {
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

/// A [MoveRecordingStore] whose [requestMove] records the move and throws
/// [thrown] within the call.
final class ThrowingMoveStore extends MoveRecordingStore {
  ThrowingMoveStore(List<CalendarEntry<String>> entries, this.thrown)
    : super(entries: entries);

  final Object thrown;

  @override
  Future<CalendarEntry<String>> requestMove(CalendarEntry<String> requested) {
    moves.add(requested);
    throw thrown;
  }
}

/// What [TimedGrid.onCreate] throws within the call in CR1.
class CreateFailure implements Exception {}

/// What [MemoryCalendarStore.onChanged] throws in MR6.
class HostFailure implements Exception {
  const HostFailure();
}

/// What a [Brittle] payload's `==` throws.
class BrittleFailure implements Exception {
  const BrittleFailure();
}

/// A payload whose `==` throws a [BrittleFailure] while [brittle] is set,
/// as a host's payload's `==` can, and counts each such call in
/// [compared]; otherwise any two are equal.
class Brittle {
  bool brittle = false;
  int compared = 0;

  @override
  bool operator ==(Object other) {
    if (brittle) {
      compared++;
      throw const BrittleFailure();
    }
    return other is Brittle;
  }

  @override
  int get hashCode {
    return 0;
  }
}

/// An entry from [start] to [end] carrying [payload].
CalendarEntry<Brittle> brittleEntryOf(
  String id,
  DateTime start,
  DateTime end,
  Brittle payload,
) {
  return CalendarEntry<Brittle>(
    id: id,
    start: start,
    end: end,
    title: id,
    color: const Color(0xFF336699),
    payload: payload,
  );
}

/// Pumps Week from Monday, in edit mode, over an in-memory store of
/// [entries], under a day limit of [maxDayCount] where it is given, and
/// returns the list its onMoveRequest adds each request to.
Future<List<CalendarMoveRequest<Brittle>>> pumpBrittleWeek(
  WidgetTester tester,
  List<CalendarEntry<Brittle>> entries, {
  int? maxDayCount,
}) async {
  final store = MemoryCalendarStore<Brittle>(entries: entries);
  addTearDown(store.dispose);
  final today = DateTime(2026, 1, 5);
  final now = ValueNotifier<CalendarNow>(
    CalendarNow(time: at(today, 9), today: today),
  );
  addTearDown(now.dispose);
  final requests = <CalendarMoveRequest<Brittle>>[];
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800.0, 2000.0);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: TimedGrid<Brittle>(
        key: UniqueKey(),
        store: store,
        firstDay: monday,
        dayCount: 7,
        selectedDay: monday,
        now: now,
        onSelectDay: (day) {},
        onOpenEntry: (id) {},
        onCreate: (range) async {},
        onMoveRequest: (request) async {
          requests.add(request);
        },
        editable: true,
        editPolicy: maxDayCount == null
            ? null
            : DayLimitPolicy<Brittle>(maxDayCount),
        slotMinutes: 15,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return requests;
}

/// Lets [gesture] go with [payload]'s `==` throwing during the release
/// alone: the blocks the frames after it build compare the entries they
/// show, a payload's `==` included.
Future<void> releaseBrittle(TestGesture gesture, Brittle payload) async {
  payload.brittle = true;
  try {
    await gesture.up();
  } finally {
    payload.brittle = false;
  }
}

/// Selects "late", Monday 22:00 to Wednesday 00:00, with a long press let
/// go in place, presses the end grip of its Tuesday block, drags it over
/// Wednesday's 12:00 slot, and returns the gesture still held.
Future<TestGesture> holdLateEndOverWednesday(WidgetTester tester) async {
  final shown = Shown.week(monday);
  final selecting = await lift(
    tester,
    tester.getCenter(blocksOf("late").first),
  );
  await selecting.up();
  await tester.pumpAndSettle();
  // Setup sanity: the entry is selected, and its Tuesday block holds its
  // end grip.
  expect(
    find.descendant(
      of: blockFinder("late", tuesday),
      matching: find.byKey(blockGripKey("late", AxisDirection.down)),
    ),
    findsOneWidget,
  );
  final block = tester.getRect(blockFinder("late", tuesday));
  final from = Offset(block.center.dx, block.bottom - 2.0);
  final to = slotRect(tester, shown, wednesday, 12 * 60).center;
  final gesture = await tester.startGesture(from);
  await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  return gesture;
}

const DefaultCalendarLocalizations english = DefaultCalendarLocalizations();

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
          label: english.allDayMore(2),
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
          label: english.allDayLess,
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
          Shown.week(CalendarDates.addDays(day, -6)),
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
          Shown.week(CalendarDates.addDays(day, -6)),
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

    store.show(nextMonday, CalendarDates.addDays(nextMonday, 6));
    harness.first = nextMonday;
    await harness.rebuild(tester);
    for (var frame = 0; frame < 5; frame++) {
      expect(cellRect(tester, week.firstSlotRow, 1).top, top, reason: "$frame");
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Setup sanity: the read has not landed.
    expect(source.reads, isNotEmpty);
    source.release(nextMonday, CalendarDates.addDays(nextMonday, 6));
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
      writes["TX8 $limit $id ${side.name} ${CalendarDates.isoDate(over)}"] =
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
        "cell is marked and the landing label reads english.noLanding", (
      tester,
    ) async {
      final shown = Shown.week(monday);
      final days = <DateTime>[
        for (var i = 0; i < 7; i++) CalendarDates.addDays(monday, i),
      ];
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
      expect(landingText(tester), english.noLanding, reason: "bar into a slot");
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
        expect(landingText(tester), english.noLanding, reason: "$others");
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
      expect(landingText(tester), english.noLanding);
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
          for (var i = 0; i < 7; i++) CalendarDates.addDays(monday, i),
        ]),
        <DateTime>[monday, tuesday, wednesday],
      );
      expect(
        landingText(tester),
        english.landing(
          monday,
          thursday,
          DateTime(2026, 1, 5),
          CalendarHourLabelFormat.twentyFourHour,
          isAllDay: true,
        ),
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
        final reason = "$id over ${CalendarDates.isoDate(over)}";
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
    final late = CalendarDayHours(8 * 60, CalendarDates.minutesPerDay);
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
    final office = CalendarDayHours(8 * 60, 18 * 60);
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
        Shown.week(CalendarDates.addDays(day, -6)),
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

  testWidgets("TX23 a block dropped on the strip stores an all-day entry and "
      "a bar dropped on a slot a timed one, and the block of a timed entry "
      "from Tuesday's start to Wednesday's let go on Tuesday's empty strip "
      "cell requests the same times all-day", (tester) async {
    for (final shown in bothGrids()) {
      var store = await dropBlockOnStrip(tester, shown);
      expect(storedOf(store, "meet").isAllDay, isTrue, reason: shown.name);
      store = await dropBarOnSlot(tester, shown);
      expect(storedOf(store, "off").isAllDay, isFalse, reason: shown.name);

      store = storeOf(<CalendarEntry<String>>[
        entryOf("whole", tuesday, wednesday),
      ]);
      await Harness(store, shown).pump(tester);
      await dragTo(
        tester,
        tester.getCenter(blockFinder("whole", tuesday)),
        tester.getCenter(find.byKey(allDayCellKey(tuesday))),
      );
      expect(store.moves, hasLength(1), reason: shown.name);
      final moved = store.moves.single;
      expect(
        (moved.start, moved.end, moved.isAllDay),
        (tuesday, wednesday, true),
        reason: shown.name,
      );
      expect(barFinder("whole"), findsOneWidget, reason: shown.name);
      expect(blocksOf("whole"), findsNothing, reason: shown.name);
    }
  });

  testWidgets("TX24 in Week the landing label names the kind the release "
      "gives: a timed entry's block over another day's column, timed; a "
      "block over a strip cell, all-day; and a bar over a slot, timed", (
    tester,
  ) async {
    final shown = Shown.week(monday);
    const format = CalendarHourLabelFormat.twentyFourHour;

    final whole = entryOf("whole", tuesday, wednesday);
    var harness = Harness(storeOf(<CalendarEntry<String>>[whole]), shown);
    await harness.pump(tester);
    final from = tester.getCenter(blockFinder("whole", tuesday));
    var gesture = await liftTo(
      tester,
      from,
      from + Offset(stripRect(tester, shown, tuesday).width, 0.0),
    );
    final timed = english.landing(
      wednesday,
      thursday,
      harness.today,
      format,
      isAllDay: false,
    );
    // Setup sanity: the kind changes the text.
    expect(
      timed,
      isNot(
        english.landing(
          wednesday,
          thursday,
          harness.today,
          format,
          isAllDay: true,
        ),
      ),
    );
    expect(landingText(tester), timed);
    await gesture.up();
    await tester.pumpAndSettle();

    harness = Harness(
      storeOf(<CalendarEntry<String>>[
        entryOf("meet", at(tuesday, 10), at(tuesday, 11)),
        allDayOf("other", tuesday),
      ]),
      shown,
    );
    await harness.pump(tester);
    gesture = await liftTo(
      tester,
      tester.getCenter(blockFinder("meet", tuesday)),
      stripRect(tester, shown, tuesday).center,
    );
    expect(
      landingText(tester),
      english.landing(
        tuesday,
        wednesday,
        harness.today,
        format,
        isAllDay: true,
      ),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    harness = Harness(
      storeOf(<CalendarEntry<String>>[allDayOf("off", tuesday)]),
      shown,
    );
    await harness.pump(tester);
    gesture = await liftTo(
      tester,
      tester.getCenter(barFinder("off")),
      slotRect(tester, shown, tuesday, 10 * 60).center,
    );
    expect(
      landingText(tester),
      english.landing(
        at(tuesday, 10),
        at(tuesday, 11),
        harness.today,
        format,
        isAllDay: false,
      ),
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("TX25 in Week a policy refusing every all-day change keeps a "
      "timed entry's block off the strip, and lets it move to another day's "
      "slots", (tester) async {
    final shown = Shown.week(monday);
    final whole = entryOf("whole", tuesday, wednesday);
    final timedOnly = ScriptedEditPolicy<String>(
      admits: (entry, start, end, isAllDay) {
        return !isAllDay;
      },
    );

    Future<MoveRecordingStore> releaseOnStrip(
      CalendarEditPolicy<String> policy,
    ) async {
      final store = storeOf(<CalendarEntry<String>>[whole]);
      await Harness(store, shown, editPolicy: policy).pump(tester);
      await dragTo(
        tester,
        tester.getCenter(blockFinder("whole", tuesday)),
        tester.getCenter(find.byKey(allDayCellKey(tuesday))),
      );
      return store;
    }

    // Setup sanity: a policy admitting every change lets the release write
    // the entry all-day.
    final admitted = await releaseOnStrip(const ScriptedEditPolicy<String>());
    expect(admitted.moves, hasLength(1));
    expect(admitted.moves.single.isAllDay, isTrue);

    final store = await releaseOnStrip(timedOnly);
    expect(store.moves, isEmpty);
    expect(blockFinder("whole", tuesday), findsOneWidget);

    final block = tester.getRect(blockFinder("whole", tuesday));
    await dragTo(
      tester,
      block.center,
      block.center +
          (slotRect(tester, shown, wednesday, 0).topLeft - block.topLeft) +
          const Offset(0.0, 2.0),
    );
    expect(store.moves, hasLength(1));
    final moved = store.moves.single;
    expect(
      (moved.start, moved.end, moved.isAllDay),
      (wednesday, thursday, false),
    );
  });

  testWidgets("TX26 in Week each gate of a bar's landing on a slot, an end "
      "handle's on a later day and a bar's move or held day-edge resize asks "
      "with the kind of what it lands", (tester) async {
    final timedOnly = ScriptedEditPolicy<String>(
      admits: (entry, start, end, isAllDay) {
        return !isAllDay;
      },
    );
    final allDayOnly = ScriptedEditPolicy<String>(
      admits: (entry, start, end, isAllDay) {
        return isAllDay;
      },
    );
    final shown = Shown.week(monday);

    Future<MoveRecordingStore> laterDayEnd(CalendarEditPolicy<String> policy) {
      return releaseEndOver(
        tester,
        entries: <CalendarEntry<String>>[nightEntry()],
        id: "night",
        day: tuesday,
        over: wednesday,
        minute: 12 * 60,
        editPolicy: policy,
      );
    }

    // Under a policy refusing every all-day change: the bar's landing on a
    // slot and the end on a later day are timed and written, and the bar's
    // move within the strip is refused.
    var store = await dropBarOnSlot(tester, shown, editPolicy: timedOnly);
    expect(store.moves, hasLength(1));
    expect(
      (storedOf(store, "off").start, storedOf(store, "off").isAllDay),
      (at(tuesday, 10), false),
    );
    store = await laterDayEnd(timedOnly);
    expect(store.moves, hasLength(1));
    expect(storedOf(store, "night").end, at(wednesday, 12, 15));
    store = await moveBarTwoColumns(tester, editPolicy: timedOnly);
    expect(store.moves, isEmpty);

    // Under one refusing every timed change, the other way round.
    store = await dropBarOnSlot(tester, shown, editPolicy: allDayOnly);
    expect(store.moves, isEmpty);
    store = await laterDayEnd(allDayOnly);
    expect(store.moves, isEmpty);
    store = await moveBarTwoColumns(tester, editPolicy: allDayOnly);
    expect(store.moves, hasLength(1));
    expectTimes(store, "off", wednesday, thursday);
    expect(storedOf(store, "off").isAllDay, isTrue);

    // Under hours to 18:00, an end handle let go on a later day past the
    // day limit is held at the hours' end, timed.
    final toSix = CalendarDayHours(0, 18 * 60);
    store = await releaseEndOver(
      tester,
      entries: <CalendarEntry<String>>[
        entryOf("ten", at(tuesday, 10), at(tuesday, 11)),
      ],
      id: "ten",
      day: tuesday,
      over: wednesday,
      minute: 12 * 60,
      limit: 1,
      hours: toSix,
    );
    expectTimes(store, "ten", at(tuesday, 10), at(tuesday, 18));

    // And a bar's day edge let go past the day limit is held at a day's
    // start, all-day.
    store = await releaseBarEdge(
      tester,
      limit: 3,
      id: "m",
      day: monday,
      side: AxisDirection.right,
      over: thursday,
      hours: toSix,
    );
    expectTimes(store, "m", monday, thursday);
    expect(storedOf(store, "m").isAllDay, isTrue);
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
          ? <DateTime>[
              for (var i = 0; i < 7; i++) CalendarDates.addDays(monday, i),
            ]
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
            at(CalendarDates.addDays(monday, i % 7), 5 + (i ~/ 7) * 2),
            at(CalendarDates.addDays(monday, i % 7), 6 + (i ~/ 7) * 2),
          ),
      ]);
      // Setup sanity: the 20 blocks are mounted.
      for (var i = 0; i < 20; i++) {
        expect(
          blockFinder("b$i", CalendarDates.addDays(monday, i % 7)),
          findsOneWidget,
        );
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

    testWidgets("with a block's move held still in the middle of the slots, "
        "ten jumps of 1 px of a scrollable inside another block read no "
        "cell, and ten of the grid's vertical position read it ten times", (
      tester,
    ) async {
      final shown = Shown.week(monday);
      final inner = ScrollController();
      addTearDown(inner.dispose);
      final harness = Harness(
        storeOf(<CalendarEntry<String>>[
          entryOf("meet", at(tuesday, 5), at(tuesday, 6)),
          entryOf("talk", at(wednesday, 5), at(wednesday, 6)),
        ]),
        shown,
        minSlotHeight: 40.0,
        minDayWidth: 200.0,
        blockBuilder: (context, entry, details) {
          if (entry.id != "talk") {
            return defaultCalendarBlockBuilder<String>(context, entry, details);
          }
          return SingleChildScrollView(
            controller: inner,
            child: const SizedBox(height: 1000.0),
          );
        },
      );
      await harness.pump(tester);
      viewportOf(tester).verticalPosition!.jumpTo(0.0);
      await tester.pump();
      final viewport = viewportOf(tester);
      final middle = viewport
          .localToGlobal(Offset(0.0, viewport.size.height / 2))
          .dy;
      final gesture = await liftTo(
        tester,
        tester.getCenter(blockFinder("meet", tuesday)),
        Offset(slotRect(tester, shown, tuesday, 0).center.dx, middle),
      );
      // Setup sanity: the drag runs, and the block's scrollable scrolls.
      expect(find.byKey(liftedBlockKey), findsOneWidget);
      expect(inner.position.maxScrollExtent, greaterThan(10.0));
      debugCellReadCount = 0;
      for (var i = 0; i < 10; i++) {
        inner.jumpTo(inner.offset + 1.0);
        await tester.pump();
      }
      expect(debugCellReadCount, 0, reason: "the block's scrollable");
      final vertical = viewportOf(tester).verticalPosition!;
      for (var i = 0; i < 10; i++) {
        vertical.jumpTo(vertical.pixels + 1.0);
        await tester.pump();
      }
      expect(debugCellReadCount, 10, reason: "the grid's vertical position");
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets("with a start-handle resize held still, ten jumps of 1 px of "
        "the vertical position read no cell", (tester) async {
      await pumpGrid(tester, <CalendarEntry<String>>[
        entryOf("meet", at(tuesday, 5), at(tuesday, 6)),
      ]);
      final block = blockFinder("meet", tuesday);
      final selecting = await lift(tester, tester.getCenter(block));
      await selecting.up();
      await tester.pumpAndSettle();
      final top = tester.getRect(block);
      final start = await tester.startGesture(
        Offset(top.center.dx, top.top + 2.0),
      );
      await start.moveBy(const Offset(0.0, -30.0));
      await tester.pump();
      final vertical = viewportOf(tester).verticalPosition!;
      // Setup sanity: the resize runs, and the hours scroll.
      expect(landingText(tester), isNotNull);
      expect(vertical.maxScrollExtent, greaterThan(10.0));
      debugCellReadCount = 0;
      for (var i = 0; i < 10; i++) {
        vertical.jumpTo(vertical.pixels + 1.0);
        await tester.pump();
      }
      expect(debugCellReadCount, 0);
      await start.up();
      await tester.pumpAndSettle();
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
        english.landing(
          at(monday, 5),
          at(monday, 6),
          DateTime(2026, 1, 5),
          CalendarHourLabelFormat.twentyFourHour,
          isAllDay: false,
        ),
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
          for (var i = 0; i < 7; i++) CalendarDates.addDays(monday, i),
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
      "a slot an entry holds the label reads english.noLanding and no outline "
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
        english.landing(
          at(tuesday, 10),
          at(tuesday, 11),
          today,
          CalendarHourLabelFormat.twentyFourHour,
          isAllDay: false,
        ),
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
        english.landing(
          at(tuesday, 14),
          at(tuesday, 15),
          today,
          CalendarHourLabelFormat.twentyFourHour,
          isAllDay: false,
        ),
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
      expect(landingText(tester), english.noLanding, reason: shown.name);
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
            english.landing(
              under.start,
              under.end,
              harness.today,
              CalendarHourLabelFormat.twentyFourHour,
              isAllDay: false,
            ),
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
              english.landing(
                under.start,
                under.end,
                harness.today,
                CalendarHourLabelFormat.twentyFourHour,
                isAllDay: false,
              ),
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
    final hours = CalendarDayHours(0, 18 * 60);
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
            ? CalendarDayHours(8 * 60, CalendarDates.minutesPerDay)
            : CalendarDayHours.allDay;
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
            english.landing(
              under.start,
              under.end,
              harness.today,
              CalendarHourLabelFormat.twentyFourHour,
              isAllDay: false,
            ),
            reason: shown.name,
          );
          final minute = CalendarDates.minuteOfDay(under.start);
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
        english.landing(
          at(tuesday, 10),
          at(tuesday, 11),
          harness.today,
          CalendarHourLabelFormat.twentyFourHour,
          isAllDay: false,
        ),
        reason: shown.name,
      );
      const key = GridKey.bar("long");
      final span = boardOf(tester).controller.spanOf(key);

      final next = CalendarDates.addDays(shown.first, shown.week ? 7 : 1);
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
            english.landing(
              written.start,
              written.end,
              DateTime(2026, 1, 5),
              CalendarHourLabelFormat.twentyFourHour,
              isAllDay: false,
            ),
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
    expect(harness.creates, <CalendarCreateRange>[
      CalendarCreateRange(start: monday, end: thursday, isAllDay: true),
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
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(start: monday, end: end, isAllDay: true),
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
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(start: at(monday, 10), end: at(monday, 12, 15)),
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
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(
          start: at(monday, 0, low),
          end: at(monday, 0, high + 15),
        ),
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
      ], reason: "$limit over ${CalendarDates.isoDate(over)}");
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
      english.landing(
        at(monday, 22),
        at(wednesday, 12, 15),
        harness.today,
        CalendarHourLabelFormat.twentyFourHour,
        isAllDay: false,
      ),
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
          bar.copyWith(
            start: at(sunday, 23, 30),
            end: at(nextMonday, 0, 30),
            isAllDay: false,
          ),
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
    final shown = Shown.week(monday, hours: CalendarDayHours(6 * 60, 22 * 60));
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
    expect(landingText(tester), english.noLanding);
    store.requestDelete("N");
    await tester.pump();
    await tester.pump();
    expect(
      landingText(tester),
      english.landing(
        at(sunday, 23, 30),
        at(nextMonday, 0, 30),
        DateTime(2026, 1, 5),
        CalendarHourLabelFormat.twentyFourHour,
        isAllDay: false,
      ),
    );
    await crossed.up();
    await tester.pumpAndSettle();
    expect(store.moves, <CalendarEntry<String>>[
      bar.copyWith(
        start: at(sunday, 23, 30),
        end: at(nextMonday, 0, 30),
        isAllDay: false,
      ),
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
      admits: (entry, start, end, isAllDay) {
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
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(
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
      "most twice per gate call besides mayOverlap, three times in a bar's "
      "landing on the slots, and mayOverlap at most once per gate call "
      "where overlaps are forbidden and never where they are allowed, with "
      "2 entries packed beside the moved one and with 200, and no ask reads "
      "allowsOverlaps or dayLimit", (tester) async {
    final shown = Shown.week(monday);

    /// The asks of [asks] that [counts] names, made outside a build,
    /// grouped by the gate call each falls in: the size of each group.
    List<int> groupSizes(
      List<PolicyAsk> asks,
      bool Function(String name) counts,
    ) {
      final groups = <int, int>{};
      for (final ask in asks) {
        if (counts(ask.name) &&
            ask.phase != SchedulerPhase.persistentCallbacks) {
          groups[ask.gate] = (groups[ask.gate] ?? 0) + 1;
        }
      }
      return groups.values.toList();
    }

    bool others(String name) {
      return name != "mayOverlap";
    }

    bool pairs(String name) {
      return name == "mayOverlap";
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
          final sizes = groupSizes(asked, others);
          // Setup sanity: the pointer path reached a gate.
          expect(sizes, isNotEmpty, reason: reason);
          expect(
            sizes.reduce(math.max),
            lessThanOrEqualTo(name == "bar" ? 3 : 2),
            reason: reason,
          );
          final pairSizes = groupSizes(asked, pairs);
          if (allowsOverlaps) {
            expect(
              asked.where((ask) {
                return pairs(ask.name);
              }),
              isEmpty,
              reason: reason,
            );
          } else {
            if (count == 200 && name != "end") {
              // Setup sanity: the gesture ends over the packed entries,
              // whose time it shares, and asks about them.
              expect(pairSizes, isNotEmpty, reason: reason);
            }
            for (final size in pairSizes) {
              expect(size, lessThanOrEqualTo(1), reason: reason);
            }
          }
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

  group("OP under a per-pair policy", () {
    testWidgets("OP1 in Week a move onto another entry's time lands there "
        "where the policy lets the two share it, and where it does not "
        "lands at a time no entry shares or goes back", (tester) async {
      final shown = Shown.week(monday);
      final busy = entryOf("busy", at(tuesday, 10), at(tuesday, 11));
      for (final id in const <String>["tentative-a", "busy-a"]) {
        final policy = pairPolicy();
        final store = storeOf(<CalendarEntry<String>>[
          busy,
          entryOf(id, at(tuesday, 14), at(tuesday, 15)),
        ]);
        await Harness(store, shown, editPolicy: policy).pump(tester);
        await moveBlockOnto(
          tester,
          blockFinder(id, tuesday),
          slotRect(tester, shown, tuesday, 10 * 60),
        );
        expectSitePairs(policy, changed: id);
        // Setup sanity: the drop asked the policy about "busy".
        expect(askedIds(policy), contains("busy"), reason: id);
        if (id == "tentative-a") {
          expect(store.moves, <CalendarEntry<String>>[
            entryOf(id, at(tuesday, 10), at(tuesday, 11)),
          ]);
        } else {
          expect(store.moves, hasLength(lessThanOrEqualTo(1)));
          expect(movesSharingTime(store, busy), isEmpty);
        }
      }
    });

    testWidgets("OP2 in Week a resize of either edge onto another entry's "
        "time lands there where the policy lets the two share it, and stops "
        "at that entry where it does not", (tester) async {
      final shown = Shown.week(monday);
      final busy = entryOf("busy", at(tuesday, 10), at(tuesday, 11));
      for (final start in const <bool>[false, true]) {
        for (final id in const <String>["tentative-a", "busy-a"]) {
          final policy = pairPolicy();
          final store = storeOf(<CalendarEntry<String>>[
            busy,
            if (start)
              entryOf(id, at(tuesday, 12), at(tuesday, 13))
            else
              entryOf(id, at(tuesday, 8), at(tuesday, 9)),
          ]);
          await Harness(store, shown, editPolicy: policy).pump(tester);
          await resizeTo(
            tester,
            shown,
            id,
            tuesday,
            10 * 60 + 30,
            start: start,
          );
          final reason = "$id, start edge: $start";
          expectSitePairs(policy, changed: id);
          // Setup sanity: the resize asked the policy about "busy".
          expect(askedIds(policy), contains("busy"), reason: reason);
          final allowed = id == "tentative-a";
          expect(store.moves, <CalendarEntry<String>>[
            if (start)
              entryOf(
                id,
                allowed ? at(tuesday, 10, 30) : at(tuesday, 11),
                at(tuesday, 13),
              )
            else
              entryOf(
                id,
                at(tuesday, 8),
                allowed ? at(tuesday, 10, 30) : at(tuesday, 10),
              ),
          ], reason: reason);
        }
      }
    });

    testWidgets("OP3 in Week an end handle let go over a later day lands "
        "over another entry's time on the day between where the policy lets "
        "the two share it, and requests nothing where it does not", (
      tester,
    ) async {
      final busy = entryOf("busy", at(wednesday, 10), at(wednesday, 11));
      for (final id in const <String>["tentative-a", "busy-a"]) {
        final policy = pairPolicy();
        final store = await releaseEndOver(
          tester,
          entries: <CalendarEntry<String>>[
            entryOf(id, at(tuesday, 20), at(tuesday, 22)),
            busy,
          ],
          id: id,
          day: tuesday,
          over: thursday,
          minute: 12 * 60,
          editPolicy: policy,
        );
        expectSitePairs(policy, changed: id);
        // Setup sanity: the later day asked the policy about "busy".
        expect(askedIds(policy), contains("busy"), reason: id);
        expect(store.moves, <CalendarEntry<String>>[
          if (id == "tentative-a")
            entryOf(id, at(tuesday, 20), at(thursday, 12, 15)),
        ], reason: id);
      }
    });

    testWidgets("OP4 in Week a bar let go on a slot over another entry's "
        "time lands there where the policy lets the two share it, and goes "
        "back where it does not", (tester) async {
      final shown = Shown.week(monday);
      for (final other in const <String>["busy", "tentative"]) {
        final policy = pairPolicy();
        final store = storeOf(<CalendarEntry<String>>[
          allDayOf("off", tuesday),
          entryOf(other, at(tuesday, 10), at(tuesday, 11)),
        ]);
        await Harness(store, shown, editPolicy: policy).pump(tester);
        await dragTo(
          tester,
          tester.getCenter(barFinder("off")),
          slotRect(tester, shown, tuesday, 10 * 60).center,
        );
        expectSitePairs(policy, changed: "off");
        // Setup sanity: the landing asked the policy about the entry.
        expect(askedIds(policy), contains(other), reason: other);
        expect(store.moves, <CalendarEntry<String>>[
          if (other == "tentative")
            entryOf("off", at(tuesday, 10), at(tuesday, 11)),
        ], reason: other);
      }
    });

    testWidgets("OP5 in Day a move whose times reach into the day before, "
        "which the grid does not show, is asked about an entry the store "
        "shows there, and lands over it only where the policy lets the two "
        "share it", (tester) async {
      final shown = Shown.day(tuesday);
      for (final other in const <String>["busy-m", "tentative-m"]) {
        final policy = pairPolicy();
        final occupant = entryOf(other, at(monday, 23, 30), at(monday, 23, 45));
        final store = storeOf(<CalendarEntry<String>>[
          entryOf("busy-a", at(monday, 22), at(tuesday, 2)),
          occupant,
        ]);
        await Harness(store, shown, editPolicy: policy).pump(tester);
        await moveBlockOnto(
          tester,
          blockFinder("busy-a", tuesday),
          slotRect(tester, shown, tuesday, 60),
        );
        expectSitePairs(policy, changed: "busy-a");
        expect(
          policy.asked.where((ask) {
            return ask.other.id == other &&
                ask.candidate.start == at(monday, 23) &&
                ask.candidate.end == at(tuesday, 3);
          }),
          isNotEmpty,
          reason: other,
        );
        if (other == "tentative-m") {
          expect(store.moves, <CalendarEntry<String>>[
            entryOf("busy-a", at(monday, 23), at(tuesday, 3)),
          ]);
        } else {
          expect(movesSharingTime(store, occupant), isEmpty);
        }
      }
    });

    testWidgets("OP6 in Week a press on the free top of the 09:00 slot "
        "above an entry from 09:10 creates where the policy lets a create of "
        "the slot share the entry's time, and does not where it does not", (
      tester,
    ) async {
      final shown = Shown.week(monday);
      for (final id in const <String>["tentative-t", "busy-t"]) {
        final policy = pairPolicy();
        final harness = Harness(
          storeOf(<CalendarEntry<String>>[
            entryOf(id, at(tuesday, 9, 10), at(tuesday, 9, 50)),
          ]),
          shown,
          editPolicy: policy,
        );
        await harness.pump(tester);
        final nine = slotRect(tester, shown, tuesday, 9 * 60);
        final free = Offset(nine.center.dx, nine.top + 2.0);
        // Setup sanity: the press lies above the block, over no item.
        expect(free.dy, lessThan(tester.getRect(blockFinder(id, tuesday)).top));
        await tester.tapAt(free);
        await tester.pumpAndSettle();
        expectSitePairs(policy);
        expect(
          policy.asked.where((ask) {
            return ask.other.id == id &&
                ask.candidate.entry == null &&
                ask.candidate.start == at(tuesday, 9) &&
                ask.candidate.end == at(tuesday, 9, 15);
          }),
          isNotEmpty,
          reason: id,
        );
        expect(harness.creates, <CalendarCreateRange>[
          if (id == "tentative-t")
            CalendarCreateRange(start: at(tuesday, 9), end: at(tuesday, 9, 15)),
        ], reason: id);
      }
    });

    testWidgets("OP7 in Week a create range is held at an entry beside its "
        "anchor only where the policy does not let the range a release "
        "would report share its time, asking about the entries that range "
        "shares, and a store notify asks about that range again", (
      tester,
    ) async {
      final shown = Shown.week(monday);
      for (final id in const <String>["tentative", "busy"]) {
        final policy = pairPolicy();
        final harness = Harness(
          storeOf(<CalendarEntry<String>>[
            entryOf(id, at(tuesday, 10), at(tuesday, 11)),
            if (id == "busy")
              entryOf("busy-late", at(tuesday, 11, 30), at(tuesday, 11, 45)),
          ]),
          shown,
          editPolicy: policy,
        );
        await harness.pump(tester);
        await createDrag(
          tester,
          slotRect(tester, shown, tuesday, 8 * 60).center,
          slotRect(tester, shown, tuesday, 12 * 60).center,
        );
        expect(harness.creates, <CalendarCreateRange>[
          CalendarCreateRange(
            start: at(tuesday, 8),
            end: id == "tentative" ? at(tuesday, 12, 15) : at(tuesday, 10),
          ),
        ], reason: id);
        expect(askedIds(policy), isNotEmpty, reason: id);
        for (final ask in policy.asked) {
          expect(<String>[id, "busy-late"], contains(ask.other.id), reason: id);
          expect(
            (ask.candidate.start, ask.candidate.end, ask.candidate.entry),
            anyOf(
              (at(tuesday, 8), at(tuesday, 10, 15), null),
              (at(tuesday, 8), at(tuesday, 12, 15), null),
            ),
            reason: id,
          );
        }
      }

      // A store notify while the range is held at "busy".
      final policy = pairPolicy();
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("busy", at(tuesday, 10), at(tuesday, 11)),
      ]);
      final harness = Harness(store, shown, editPolicy: policy);
      await harness.pump(tester);
      final from = slotRect(tester, shown, tuesday, 8 * 60).center;
      final twelve = slotRect(tester, shown, tuesday, 12 * 60);
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(Offset.lerp(from, twelve.center, 0.5)!);
      await tester.pump();
      await gesture.moveTo(twelve.center);
      await tester.pump();
      // Setup sanity: the range is held at "busy", which it asked about.
      expect(strokedRects(tester), <Matcher>[
        nearRect(
          slotsRect(tester, shown, tuesday, 8 * 60, 10 * 60).deflate(1.0),
        ),
      ]);
      final asked = policy.asked.length;
      expect(askedIds(policy), everyElement("busy"));
      expect(asked, greaterThan(0));
      await store.requestDelete("busy");
      await store.create(
        entryOf("tentative-n", at(tuesday, 10, 30), at(tuesday, 11)),
      );
      await tester.pump();
      expect(
        policy.asked.sublist(asked).map((ask) {
          return (
            ask.other.id,
            ask.candidate.entry,
            ask.candidate.start,
            ask.candidate.end,
          );
        }),
        <(String?, CalendarEntry<String>?, DateTime, DateTime)>[
          ("tentative-n", null, at(tuesday, 8), at(tuesday, 12, 15)),
        ],
      );
      await gesture.moveTo(twelve.center + const Offset(0.0, 2.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(start: at(tuesday, 8), end: at(tuesday, 12, 15)),
      ]);
    });

    testWidgets("OP9 where the policy allows overlaps, no move, resize, "
        "bar landing or create range asks mayOverlap or builds a candidate, "
        "among 200 packed entries", (tester) async {
      final shown = Shown.week(monday);
      for (final name in const <String>[
        "move",
        "start",
        "end",
        "bar",
        "create",
      ]) {
        final policy = pairPolicy(overlaps: true);
        final harness = Harness(packedStore(200), shown, editPolicy: policy);
        await harness.pump(tester);
        final built = debugOverlapCandidateCount;
        final gates = debugDropGateCount;
        if (name == "create") {
          await packedCreateDrag(tester, shown);
          // Setup sanity: the range was let go and reported.
          expect(harness.creates, hasLength(1), reason: name);
        } else {
          await packedGestures(tester, shown)[name]!();
          // Setup sanity: the pointer path reached a gate.
          expect(debugDropGateCount, greaterThan(gates), reason: name);
        }
        expect(policy.asked, isEmpty, reason: name);
        expect(debugOverlapCandidateCount, built, reason: name);
      }
    });

    testWidgets("OP10 where overlaps are forbidden, among 200 packed "
        "entries each gate call that asks builds one candidate, and one that "
        "asks nothing builds none, the pairs one gate call asks about carry "
        "that one candidate, and a create range asks nothing at its start "
        "and builds at each move the candidates it asks with, each asking "
        "about an entry once", (tester) async {
      final shown = Shown.week(monday);
      for (final allowsAll in const <bool>[false, true]) {
        for (final name in const <String>["move", "start", "end", "bar"]) {
          final policy = allowsAll
              ? PairRecordingPolicy<String>(
                  allows: (candidate, other) {
                    return true;
                  },
                )
              : pairPolicy();
          await Harness(
            packedStore(200),
            shown,
            editPolicy: policy,
          ).pump(tester);
          final built = debugOverlapCandidateCount;
          final gates = debugDropGateCount;
          final asks = policy.asked.length;
          await packedGestures(tester, shown)[name]!();
          final reason = "$name, allows every pair: $allowsAll";
          final candidates = debugOverlapCandidateCount - built;
          // The gate calls that asked, each told apart by its gate count.
          final asking = policy.asked.skip(asks).map((ask) {
            return ask.gate;
          }).toSet();
          expect(candidates, asking.length, reason: reason);
          expect(
            candidates,
            lessThanOrEqualTo(debugDropGateCount - gates),
            reason: reason,
          );
          expectSitePairs(policy, changed: name == "bar" ? "bar" : "free");
          if (allowsAll) {
            if (name != "end") {
              // Setup sanity: the gesture ends over the packed entries,
              // whose time it shares, and asks about them.
              expect(policy.asked, isNotEmpty, reason: reason);
            }
            final byGate = <int, CalendarOverlapCandidate<String>>{};
            for (final ask in policy.asked) {
              final first = byGate.putIfAbsent(ask.gate, () {
                return ask.candidate;
              });
              expect(identical(ask.candidate, first), isTrue, reason: reason);
            }
          }
        }
      }

      final policy = pairPolicy();
      final harness = Harness(packedStore(200), shown, editPolicy: policy);
      await harness.pump(tester);
      var asked = policy.asked.length;
      var built = debugOverlapCandidateCount;
      var moves = 0;
      void expectBuiltAsAsked(String reason) {
        final asks = policy.asked.sublist(asked);
        final candidates = Set<CalendarOverlapCandidate<String>>.identity();
        for (final ask in asks) {
          candidates.add(ask.candidate);
        }
        expect(
          debugOverlapCandidateCount - built,
          candidates.length,
          reason: reason,
        );
        for (final candidate in candidates) {
          final others = <String?>[
            for (final ask in asks)
              if (identical(ask.candidate, candidate)) ask.other.id,
          ];
          expect(others.toSet(), hasLength(others.length), reason: reason);
        }
        asked = policy.asked.length;
        built = debugOverlapCandidateCount;
      }

      await packedCreateDrag(
        tester,
        shown,
        begun: () {
          expect(
            policy.asked.sublist(asked).where((ask) {
              return ask.candidate.entry == null;
            }),
            isEmpty,
            reason: "the start",
          );
          asked = policy.asked.length;
          built = debugOverlapCandidateCount;
        },
        moved: () {
          moves++;
          expectBuiltAsAsked("move $moves");
        },
      );
      // Setup sanity: every move was checked, and the range was let go.
      expect(moves, 10);
      expect(harness.creates, hasLength(1));
    });

    testWidgets("OP11 a per-pair answer that throws is reported: a bar's "
        "landing on the slots and an end handle's later day refuse, and a "
        "create range whose entries a store notify or a new minute reads "
        "again ends, creating nothing", (tester) async {
      final shown = Shown.week(monday);
      PairRecordingPolicy<String> throwing() {
        return PairRecordingPolicy<String>(
          allows: (candidate, other) {
            throw const PairFailure();
          },
        );
      }

      /// Checks that [errors] hold a throw of the policy the grid reported
      /// itself, and nothing but throws of the policy that the grid or the
      /// board reported ([BoardDragConfig.canDropAt]).
      void expectReported(List<FlutterErrorDetails> errors, String reason) {
        expect(
          errors.where((error) {
            return error.library == "widgets_extended calendar";
          }),
          isNotEmpty,
          reason: reason,
        );
        for (final error in errors) {
          expect(error.exception, isA<PairFailure>(), reason: reason);
          expect(
            error.library,
            anyOf("widgets_extended calendar", "widgets_extended board"),
            reason: reason,
          );
        }
      }

      await recordingErrors((errors) async {
        final policy = throwing();
        final store = storeOf(<CalendarEntry<String>>[
          allDayOf("off", tuesday),
          entryOf("busy", at(tuesday, 10), at(tuesday, 11)),
        ]);
        await Harness(store, shown, editPolicy: policy).pump(tester);
        await dragTo(
          tester,
          tester.getCenter(barFinder("off")),
          slotRect(tester, shown, tuesday, 10 * 60).center,
        );
        // Setup sanity: the landing asked the policy.
        expect(askedIds(policy), contains("busy"));
        expectReported(errors, "bar");
        expect(store.moves, isEmpty);
      });

      await recordingErrors((errors) async {
        final policy = throwing();
        final store = await releaseEndOver(
          tester,
          entries: <CalendarEntry<String>>[
            entryOf("busy-a", at(tuesday, 20), at(tuesday, 22)),
            entryOf("busy", at(wednesday, 10), at(wednesday, 11)),
          ],
          id: "busy-a",
          day: tuesday,
          over: thursday,
          minute: 12 * 60,
          editPolicy: policy,
        );
        // Setup sanity: the later day asked the policy.
        expect(askedIds(policy), contains("busy"));
        expectReported(errors, "end handle");
        expect(store.moves, isEmpty);
      });

      for (final notify in const <bool>[true, false]) {
        await recordingErrors((errors) async {
          final reason = notify ? "store notify" : "new minute";
          var armed = false;
          final policy = PairRecordingPolicy<String>(
            allows: (candidate, other) {
              if (armed) {
                throw const PairFailure();
              }
              return tentativePair(candidate, other);
            },
          );
          final busy = entryOf("busy-n", at(tuesday, 10), at(tuesday, 11));
          final store = storeOf(<CalendarEntry<String>>[if (!notify) busy]);
          final harness = Harness(store, shown, editPolicy: policy);
          await harness.pump(tester);
          final from = slotRect(tester, shown, tuesday, 8 * 60).center;
          final to = slotRect(tester, shown, tuesday, 12 * 60).center;
          final gesture = await tester.startGesture(
            from,
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
          await tester.pump();
          await gesture.moveTo(to);
          await tester.pump();
          // Setup sanity: the range is marked while it is held.
          expect(strokedRects(tester), isNotEmpty, reason: reason);
          final asked = policy.asked.length;
          armed = true;
          if (notify) {
            await store.create(busy);
          } else {
            harness.now.value = CalendarNow(
              time: at(harness.today, 9, 1),
              today: harness.today,
            );
          }
          await tester.pump();
          // Setup sanity: the refresh asked the policy about the entry.
          expect(askedIds(policy).sublist(asked), <String>[
            "busy-n",
          ], reason: reason);
          expectReported(errors, reason);
          expect(errors, hasLength(1), reason: reason);
          expect(strokedRects(tester), isEmpty, reason: reason);
          expect(find.byType(ErrorWidget), findsNothing, reason: reason);
          await gesture.up();
          await tester.pumpAndSettle();
          expect(harness.creates, isEmpty, reason: reason);
        });
      }
    });

    testWidgets("OP12 in Day a resize the policy refuses stops at the first "
        "entry in its way that the policy refuses, past one it lets the "
        "resize share, and a move it refuses lands at the nearest time whose "
        "sharing entries it allows", (tester) async {
      final shown = Shown.day(tuesday);
      var policy = pairPolicy();
      var store = storeOf(<CalendarEntry<String>>[
        entryOf("busy-a", at(tuesday, 8), at(tuesday, 9)),
        entryOf("tentative-t", at(tuesday, 9, 30), at(tuesday, 10)),
        entryOf("busy-b", at(tuesday, 10, 30), at(tuesday, 11)),
      ]);
      await Harness(store, shown, editPolicy: policy).pump(tester);
      await resizeTo(tester, shown, "busy-a", tuesday, 10 * 60 + 45);
      // Setup sanity: the policy refused "busy-b", so the refusal is its.
      expect(refusedAsk(policy, "busy-b"), isTrue);
      expectSitePairs(policy, changed: "busy-a");
      expect(store.moves, <CalendarEntry<String>>[
        entryOf("busy-a", at(tuesday, 8), at(tuesday, 10, 30)),
      ], reason: "resize");

      policy = pairPolicy();
      store = storeOf(<CalendarEntry<String>>[
        entryOf("busy-a", at(tuesday, 8), at(tuesday, 9)),
        entryOf("busy-b", at(tuesday, 10, 30), at(tuesday, 11)),
        entryOf("tentative-t", at(tuesday, 11), at(tuesday, 12, 30)),
      ]);
      await Harness(store, shown, editPolicy: policy).pump(tester);
      await moveBlockOnto(
        tester,
        blockFinder("busy-a", tuesday),
        slotRect(tester, shown, tuesday, 10 * 60 + 30),
      );
      // Setup sanity: the policy refused "busy-b", so the refusal is its.
      expect(refusedAsk(policy, "busy-b"), isTrue);
      expectSitePairs(policy, changed: "busy-a");
      expect(store.moves, <CalendarEntry<String>>[
        entryOf("busy-a", at(tuesday, 11), at(tuesday, 12)),
      ], reason: "move");
    });

    testWidgets("OP13 in Week with hours to 18:00 an end handle let go over "
        "the next day is asked about an entry after the hours, which has no "
        "block, and lands only where the policy lets the two share it", (
      tester,
    ) async {
      final hours = CalendarDayHours(8 * 60, 18 * 60);
      for (final other in const <String>["busy-n", "tentative-n"]) {
        final policy = pairPolicy();
        final store = await releaseEndOver(
          tester,
          entries: <CalendarEntry<String>>[
            entryOf("busy-a", at(tuesday, 16), at(tuesday, 17)),
            entryOf(other, at(tuesday, 19), at(tuesday, 20)),
          ],
          id: "busy-a",
          day: tuesday,
          over: wednesday,
          minute: 9 * 60,
          editPolicy: policy,
          hours: hours,
        );
        // Setup sanity: the entry after the hours has no block.
        expect(blocksOf(other), findsNothing, reason: other);
        expectSitePairs(policy, changed: "busy-a");
        expect(askedIds(policy), contains(other), reason: other);
        expect(store.moves, <CalendarEntry<String>>[
          if (other == "tentative-n")
            entryOf("busy-a", at(tuesday, 16), at(wednesday, 9, 15)),
        ], reason: other);
      }
    });

    testWidgets("OP21 under NoOverlapsPolicy a move, a resize of either "
        "edge, a bar landing and a press over times no entry shares build no "
        "candidate", (tester) async {
      final shown = Shown.week(monday);
      for (final name in const <String>["move", "start", "end", "bar", "tap"]) {
        final harness = Harness(
          packedStore(0),
          shown,
          editPolicy: CountingEditPolicy<String>(
            const NoOverlapsPolicy<String>(),
          ),
        );
        await harness.pump(tester);
        final built = debugOverlapCandidateCount;
        final gates = debugDropGateCount;
        if (name == "tap") {
          await tester.tapAt(slotRect(tester, shown, tuesday, 10 * 60).center);
          await tester.pumpAndSettle();
          // Setup sanity: the press created.
          expect(harness.creates, hasLength(1), reason: name);
        } else {
          await packedGestures(tester, shown)[name]!();
          // Setup sanity: the pointer path reached a gate.
          expect(debugDropGateCount, greaterThan(gates), reason: name);
        }
        expect(debugOverlapCandidateCount, built, reason: name);
      }
    });

    testWidgets("OP22 the overlap index of the entries outside the hours "
        "sorts them at its first search after a split: under a policy that "
        "allows overlaps a store notify and a move sort nothing, and under "
        "one that forbids them the pump sorts them once, a move then "
        "nothing, and a store notify that adds an entry, with the move after "
        "it, once", (tester) async {
      final shown = Shown.week(
        monday,
        hours: CalendarDayHours(8 * 60, 18 * 60),
      );

      /// "free" lifted and moved toward Tuesday's slot at [hour] in ten
      /// pointer moves, a frame after each, still held.
      Future<TestGesture> moveFree(int hour) async {
        final from = tester.getCenter(blockFinder("free", tuesday));
        final to = slotRect(tester, shown, tuesday, hour * 60).center;
        final gesture = await lift(tester, from);
        for (var i = 1; i <= 10; i++) {
          await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
          await tester.pump();
        }
        return gesture;
      }

      MoveRecordingStore storeOfTuesday() {
        return storeOf(<CalendarEntry<String>>[
          entryOf("late", at(tuesday, 19), at(tuesday, 20)),
          entryOf("free", at(tuesday, 14), at(tuesday, 15)),
        ]);
      }

      var store = storeOfTuesday();
      final builds = debugOverlapIndexBuildCount;
      await Harness(
        store,
        shown,
        editPolicy: const UnrestrictedEditPolicy<String>(),
      ).pump(tester);
      await store.create(entryOf("night", at(tuesday, 21), at(tuesday, 22)));
      await tester.pumpAndSettle();
      var gates = debugDropGateCount;
      var gesture = await moveFree(10);
      await gesture.up();
      await tester.pumpAndSettle();
      // Setup sanity: the move reached the gate.
      expect(debugDropGateCount, greaterThan(gates));
      expect(debugOverlapIndexBuildCount, builds, reason: "overlaps allowed");

      // What the pump, a move, and a store notify with the move after it
      // each add to the build count.
      final added = <int>[];
      store = storeOfTuesday();
      gates = debugDropGateCount;
      var before = debugOverlapIndexBuildCount;
      await Harness(
        store,
        shown,
        editPolicy: const NoOverlapsPolicy<String>(),
      ).pump(tester);
      // Setup sanity: "free"'s semantics moves asked the gate.
      expect(debugDropGateCount, greaterThan(gates), reason: "the pump");
      added.add(debugOverlapIndexBuildCount - before);

      gates = debugDropGateCount;
      before = debugOverlapIndexBuildCount;
      gesture = await moveFree(10);
      // Setup sanity: the move asked the gate at least twice.
      expect(
        debugDropGateCount,
        greaterThanOrEqualTo(gates + 2),
        reason: "the move",
      );
      added.add(debugOverlapIndexBuildCount - before);
      await gesture.up();
      await tester.pumpAndSettle();

      gates = debugDropGateCount;
      before = debugOverlapIndexBuildCount;
      await store.create(entryOf("night", at(tuesday, 21), at(tuesday, 22)));
      await tester.pumpAndSettle();
      gesture = await moveFree(16);
      // Setup sanity: the move after the notify asked the gate at least
      // twice.
      expect(
        debugDropGateCount,
        greaterThanOrEqualTo(gates + 2),
        reason: "the move after a notify",
      );
      added.add(debugOverlapIndexBuildCount - before);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(added, <int>[1, 0, 1]);
    });

    testWidgets("OP23 the grid asks whether a policy that forbids overlaps "
        "refuses every one once, when it takes the policy, and not during a "
        "drag, and never asks a policy that allows overlaps", (tester) async {
      final shown = Shown.week(monday);
      int asksOf(CountingEditPolicy<String> policy) {
        return policy.asked.where((ask) {
          return ask.name == "refusesEveryOverlap";
        }).length;
      }

      final store = storeOf(<CalendarEntry<String>>[
        entryOf("busy", at(tuesday, 10), at(tuesday, 11)),
        entryOf("free", at(tuesday, 14), at(tuesday, 15)),
      ]);
      final first = CountingEditPolicy<String>(
        const NoOverlapsPolicy<String>(),
      );
      final harness = Harness(store, shown, editPolicy: first);
      await harness.pump(tester);
      expect(asksOf(first), 1, reason: "the pump");

      final gates = debugDropGateCount;
      final from = tester.getRect(blockFinder("free", tuesday));
      final slot = slotRect(tester, shown, tuesday, 10 * 60);
      final onto =
          from.center + (slot.topLeft - from.topLeft) + const Offset(0.0, 6.0);
      final gesture = await lift(tester, from.center);
      await gesture.moveTo(onto);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await gesture.moveTo(onto + Offset(0.0, i.isEven ? -3.0 : 0.0));
        await tester.pump();
      }
      // Setup sanity: the move reached the gate.
      expect(debugDropGateCount, greaterThan(gates));
      await store.create(entryOf("wed", at(wednesday, 9), at(wednesday, 10)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(asksOf(first), 1, reason: "the drag");

      final second = CountingEditPolicy<String>(
        const NoOverlapsPolicy<String>(),
      );
      harness.editPolicy = second;
      await harness.rebuild(tester);
      await tester.pumpAndSettle();
      expect((asksOf(first), asksOf(second)), (1, 1), reason: "a new policy");

      final unrestricted = CountingEditPolicy<String>(
        const UnrestrictedEditPolicy<String>(),
      );
      await Harness(store, shown, editPolicy: unrestricted).pump(tester);
      expect(asksOf(unrestricted), 0, reason: "overlaps allowed");
    });

    testWidgets("OP24 in Day under a per-pair policy a new minute, from "
        "either clock, a reload and a store notify each give a drag's board a "
        "new config, which drops the gate's kept answers, and under "
        "NoOverlapsPolicy a new minute, from either clock, and a reload give "
        "it none, nor do they under the per-pair policy for a bar's "
        "drag", (tester) async {
      final shown = Shown.day(tuesday);
      for (final name in const <String>["per-pair", "NoOverlapsPolicy"]) {
        final perPair = name == "per-pair";
        final store = storeOf(<CalendarEntry<String>>[
          entryOf("busy", at(tuesday, 10), at(tuesday, 11)),
          entryOf("m", at(tuesday, 14), at(tuesday, 15)),
        ]);
        final harness = Harness(
          store,
          shown,
          editPolicy: perPair ? pairPolicy() : const NoOverlapsPolicy<String>(),
        );
        await harness.pump(tester);
        var gates = debugDropGateCount;
        final reassembled = tester.binding.reassembleApplication();
        await tester.pump();
        await reassembled;
        // What the block hosts' semantics moves ask when they all build.
        final rebuilt = debugDropGateCount - gates;
        // Setup sanity: the hosts' semantics moves asked the gate.
        expect(rebuilt, greaterThan(0), reason: name);

        gates = debugDropGateCount;
        final from = tester.getRect(blockFinder("m", tuesday));
        final slot = slotRect(tester, shown, tuesday, 10 * 60);
        final onto =
            from.center +
            (slot.topLeft - from.topLeft) +
            const Offset(0.0, 6.0);
        final gesture = await lift(tester, from.center);
        final lifted = debugDropGateCount;
        await gesture.moveTo(onto);
        await tester.pump();
        // Setup sanity: the refusal asked the gate.
        expect(debugDropGateCount, greaterThan(lifted), reason: name);
        // What the lift and the refusal asked.
        final refused = debugDropGateCount - gates;

        gates = debugDropGateCount;
        // Two new leans over the refused placement, inside it, on the side
        // of its middle the lift leaned to.
        await gesture.moveTo(onto - const Offset(0.0, 3.0));
        await tester.pump();
        await gesture.moveTo(onto);
        await tester.pump();
        if (perPair) {
          expect(debugDropGateCount, gates, reason: "$name, the moves");
        } else {
          // Setup sanity: with no kept answers the fit ran at each lean.
          expect(debugDropGateCount, greaterThan(gates), reason: name);
        }

        var minutes = 0;
        CalendarNow later(int minute) {
          final time = harness.now.value.time.add(Duration(minutes: minute));
          return CalendarNow(time: time, today: tuesday);
        }

        final changes = <String, Future<void> Function()>{
          "a new minute": () async {
            harness.now.value = later(++minutes);
            await tester.pump();
          },
          "a new clock": () async {
            final given = ValueNotifier<CalendarNow>(later(++minutes));
            addTearDown(given.dispose);
            harness.givenNow = given;
            await harness.rebuild(tester);
          },
          "a reload": () async {
            final reassembled = tester.binding.reassembleApplication();
            await tester.pump();
            await reassembled;
          },
          if (perPair)
            "a store notify": () async {
              await store.create(
                entryOf("wed", at(wednesday, 9), at(wednesday, 10)),
              );
              await tester.pump();
            },
        };
        for (final MapEntry(key: change, value: run) in changes.entries) {
          final reason = "$name, $change";
          final config = boardOf(tester).drag;
          gates = debugDropGateCount;
          await run();
          final added = debugDropGateCount - gates;
          if (perPair) {
            expect(
              identical(boardOf(tester).drag, config),
              isFalse,
              reason: reason,
            );
            expect(added, greaterThan(rebuilt), reason: reason);
            expect(added, lessThanOrEqualTo(rebuilt + refused), reason: reason);
          } else {
            expect(
              identical(boardOf(tester).drag, config),
              isTrue,
              reason: reason,
            );
            if (change == "a new minute") {
              expect(added, 0, reason: reason);
            }
          }
        }
        await gesture.up();
        await tester.pumpAndSettle();
        // Setup sanity: the release requested a move.
        expect(
          store.moves.map((entry) {
            return entry.id;
          }),
          <String>["m"],
          reason: name,
        );
      }

      // A bar's drag, whose board keeps no answer under any policy.
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("busy", at(tuesday, 10), at(tuesday, 11)),
        allDayOf("bar", tuesday),
      ]);
      final harness = Harness(store, shown, editPolicy: pairPolicy());
      await harness.pump(tester);
      final gesture = await lift(tester, tester.getCenter(barFinder("bar")));
      await tester.pump();
      // Setup sanity: the bar lifted, and its board holds a config with no
      // drop fit.
      expect(find.byKey(liftedBlockKey), findsOneWidget);
      expect(boardOf(tester).drag!.dropFit, isNull);
      final config = boardOf(tester).drag;
      CalendarNow later() {
        final time = harness.now.value.time.add(const Duration(minutes: 1));
        return CalendarNow(time: time, today: tuesday);
      }

      harness.now.value = later();
      await tester.pump();
      expect(
        identical(boardOf(tester).drag, config),
        isTrue,
        reason: "bar, a new minute",
      );
      final given = ValueNotifier<CalendarNow>(later());
      addTearDown(given.dispose);
      harness.givenNow = given;
      await harness.rebuild(tester);
      expect(
        identical(boardOf(tester).drag, config),
        isTrue,
        reason: "bar, a new clock",
      );
      final reassembled = tester.binding.reassembleApplication();
      await tester.pump();
      await reassembled;
      expect(
        identical(boardOf(tester).drag, config),
        isTrue,
        reason: "bar, a reload",
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets("OP26 in Day under a per-pair policy a refused move's fit "
        "asks the gate about each placement nearer than the first it admits, "
        "meeting entries or not, and each later refused placement only about "
        "the placements the drag has not asked about", (tester) async {
      final shown = Shown.day(tuesday);
      final policy = pairPolicy();
      final store = storeOf(<CalendarEntry<String>>[
        for (var i = 0; i < 8; i++)
          entryOf("b$i", at(tuesday, 8 + i), at(tuesday, 9 + i)),
        entryOf("m", at(tuesday, 17), at(tuesday, 18)),
      ]);
      await Harness(store, shown, editPolicy: policy).pump(tester);

      /// The gate calls about "m" among [asks], by the drop-gate count at
      /// each, with the times of each one's candidate.
      Map<int, (DateTime, DateTime)> callsOf(Iterable<PairAsk<String>> asks) {
        return <int, (DateTime, DateTime)>{
          for (final ask in asks)
            if (ask.candidate.entry?.id == "m")
              ask.gate: (ask.candidate.start, ask.candidate.end),
        };
      }

      final from = tester.getRect(blockFinder("m", tuesday));
      final slot = slotRect(tester, shown, tuesday, 13 * 60);
      final gesture = await lift(tester, from.center);
      final lifted = policy.asked.length;
      var point =
          from.center + (slot.topLeft - from.topLeft) + const Offset(0.0, 6.0);
      final added = <int>[];
      for (var i = 0; i <= 8; i++) {
        final asked = policy.asked.length;
        await gesture.moveTo(point);
        await tester.pump();
        added.add(callsOf(policy.asked.sublist(asked)).length);
        point += Offset(0.0, slot.height);
      }
      final calls = callsOf(policy.asked.sublist(lifted));
      await gesture.up();
      await tester.pumpAndSettle();
      // Setup sanity: each placement from 13:00 to 15:00 was asked about
      // and refused, and the move landed after "b7".
      for (var minute = 13 * 60; minute <= 15 * 60; minute += 15) {
        final start = at(tuesday, minute ~/ 60, minute % 60);
        final end = start.add(const Duration(hours: 1));
        expect(
          policy.asked.any((ask) {
            return ask.candidate.entry?.id == "m" &&
                ask.candidate.start == start &&
                ask.candidate.end == end &&
                !policy.allows(ask.candidate, ask.other);
          }),
          isTrue,
          reason: "$start",
        );
      }
      expect(store.moves, <CalendarEntry<String>>[
        entryOf("m", at(tuesday, 16), at(tuesday, 17)),
      ]);
      expect(added.first, greaterThanOrEqualTo(10), reason: "13:00");
      expect(
        added.skip(1),
        everyElement(lessThanOrEqualTo(2)),
        reason: "$added",
      );
      expect(
        calls.values.toSet(),
        hasLength(calls.length),
        reason: "${calls.values}",
      );
    });

    testWidgets("OP17 in Week a create range tests the range a release "
        "would report at each cell it reaches, holds it short of the entry "
        "nearest its anchor that the policy refuses, toward later or earlier "
        "slots and across days, asks about the held range again, and asks "
        "nothing on a move inside a cell it reached", (tester) async {
      final shown = Shown.week(monday);
      final cases =
          <
            String,
            ({
              List<CalendarEntry<String>> entries,
              List<(DateTime, DateTime)> path,
              CalendarCreateRange created,
              List<(DateTime, DateTime)> tested,
            })
          >{
            "later, held": (
              entries: <CalendarEntry<String>>[
                entryOf("busy", at(tuesday, 10), at(tuesday, 11)),
              ],
              path: <(DateTime, DateTime)>[
                (tuesday, at(tuesday, 8)),
                (tuesday, at(tuesday, 12)),
              ],
              created: CalendarCreateRange(
                start: at(tuesday, 8),
                end: at(tuesday, 10),
              ),
              tested: <(DateTime, DateTime)>[
                (at(tuesday, 8), at(tuesday, 10, 15)),
                (at(tuesday, 8), at(tuesday, 12, 15)),
                (at(tuesday, 8), at(tuesday, 10)),
              ],
            ),
            "later, not held": (
              entries: <CalendarEntry<String>>[
                entryOf("tentative", at(tuesday, 10), at(tuesday, 11)),
              ],
              path: <(DateTime, DateTime)>[
                (tuesday, at(tuesday, 8)),
                (tuesday, at(tuesday, 12)),
              ],
              created: CalendarCreateRange(
                start: at(tuesday, 8),
                end: at(tuesday, 12, 15),
              ),
              tested: <(DateTime, DateTime)>[
                (at(tuesday, 8), at(tuesday, 10, 15)),
                (at(tuesday, 8), at(tuesday, 12, 15)),
              ],
            ),
            "earlier, held": (
              entries: <CalendarEntry<String>>[
                entryOf("busy", at(tuesday, 9), at(tuesday, 10)),
              ],
              path: <(DateTime, DateTime)>[
                (tuesday, at(tuesday, 12)),
                (tuesday, at(tuesday, 8)),
              ],
              created: CalendarCreateRange(
                start: at(tuesday, 10),
                end: at(tuesday, 12, 15),
              ),
              tested: <(DateTime, DateTime)>[
                (at(tuesday, 10), at(tuesday, 12, 15)),
                (at(tuesday, 8), at(tuesday, 12, 15)),
              ],
            ),
            "earlier, not held": (
              entries: <CalendarEntry<String>>[
                entryOf("tentative", at(tuesday, 9), at(tuesday, 10)),
              ],
              path: <(DateTime, DateTime)>[
                (tuesday, at(tuesday, 12)),
                (tuesday, at(tuesday, 8)),
              ],
              created: CalendarCreateRange(
                start: at(tuesday, 8),
                end: at(tuesday, 12, 15),
              ),
              tested: <(DateTime, DateTime)>[
                (at(tuesday, 10), at(tuesday, 12, 15)),
                (at(tuesday, 8), at(tuesday, 12, 15)),
              ],
            ),
            "across days": (
              entries: <CalendarEntry<String>>[
                entryOf("tentative", at(monday, 10), at(monday, 10, 30)),
                entryOf("busy", at(monday, 20), at(monday, 21)),
              ],
              path: <(DateTime, DateTime)>[
                (monday, at(monday, 9)),
                (monday, at(monday, 12)),
                (monday, at(monday, 15)),
                (tuesday, at(tuesday, 12)),
              ],
              created: CalendarCreateRange(
                start: at(monday, 9),
                end: at(monday, 20),
              ),
              tested: <(DateTime, DateTime)>[
                (at(monday, 9), at(monday, 12, 15)),
                (at(monday, 9), at(monday, 15, 15)),
                (at(monday, 9), at(tuesday, 12, 15)),
                (at(monday, 9), at(monday, 20)),
              ],
            ),
          };
      for (final MapEntry(key: name, value: run) in cases.entries) {
        final policy = pairPolicy();
        final harness = Harness(
          storeOf(run.entries),
          shown,
          editPolicy: policy,
        );
        await harness.pump(tester);
        Offset pointOf((DateTime, DateTime) cell) {
          final (day, time) = cell;
          return slotRect(
            tester,
            shown,
            day,
            CalendarDates.minuteOfDay(time),
          ).center;
        }

        final gesture = await tester.startGesture(
          pointOf(run.path.first),
          kind: PointerDeviceKind.mouse,
        );
        if (run.path.length == 2) {
          final middle = Offset.lerp(
            pointOf(run.path.first),
            pointOf(run.path.last),
            0.5,
          )!;
          await gesture.moveTo(middle);
          await tester.pump();
          await expectNothingAskedInsideCell(
            tester,
            gesture,
            middle,
            policy,
            reason: name,
          );
        }
        for (final cell in run.path.skip(1)) {
          final point = pointOf(cell);
          await gesture.moveTo(point);
          await tester.pump();
          await expectNothingAskedInsideCell(
            tester,
            gesture,
            point,
            policy,
            reason: name,
          );
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(harness.creates, <CalendarCreateRange>[
          run.created,
        ], reason: name);
        for (final ask in policy.asked) {
          expect(ask.candidate.entry, isNull, reason: name);
          expect(
            run.tested,
            contains((ask.candidate.start, ask.candidate.end)),
            reason: name,
          );
          expect(
            (ask.candidate.start, ask.candidate.end),
            isNot((monday, nextMonday)),
            reason: name,
          );
        }
        expectSitePairs(policy);
        expectRangeAsked(policy, run.entries, run.created);
      }
    });

    testWidgets("OP18 in Day a create range is held short of the refused "
        "entry nearest its anchor, past an entry the policy allows, and to "
        "its anchor's slot where the refused entry shares that slot, asking "
        "about each range it tests and nothing on a move inside a cell it "
        "reached", (tester) async {
      final shown = Shown.day(tuesday);
      final cases =
          <
            String,
            ({
              PairRecordingPolicy<String> Function() policy,
              List<CalendarEntry<String>> entries,
              int from,
              int to,
              CalendarCreateRange created,
              List<(DateTime, DateTime)> tested,
              List<(String, DateTime, DateTime)> asked,
            })
          >{
            "later, held": (
              policy: pairPolicy,
              entries: <CalendarEntry<String>>[
                entryOf("busy", at(tuesday, 10), at(tuesday, 11)),
              ],
              from: 8 * 60,
              to: 12 * 60,
              created: CalendarCreateRange(
                start: at(tuesday, 8),
                end: at(tuesday, 10),
              ),
              tested: <(DateTime, DateTime)>[
                (at(tuesday, 8), at(tuesday, 10, 15)),
                (at(tuesday, 8), at(tuesday, 12, 15)),
                (at(tuesday, 8), at(tuesday, 10)),
              ],
              asked: <(String, DateTime, DateTime)>[],
            ),
            "earlier, held past an allowed entry": (
              policy: pairPolicy,
              entries: <CalendarEntry<String>>[
                entryOf("busy", at(tuesday, 8, 30), at(tuesday, 9)),
                entryOf("tentative", at(tuesday, 10), at(tuesday, 10, 30)),
              ],
              from: 12 * 60,
              to: 8 * 60,
              created: CalendarCreateRange(
                start: at(tuesday, 9),
                end: at(tuesday, 12, 15),
              ),
              tested: <(DateTime, DateTime)>[
                (at(tuesday, 10), at(tuesday, 12, 15)),
                (at(tuesday, 8), at(tuesday, 12, 15)),
                (at(tuesday, 9), at(tuesday, 12, 15)),
              ],
              asked: <(String, DateTime, DateTime)>[
                ("tentative", at(tuesday, 9), at(tuesday, 12, 15)),
              ],
            ),
            "later, not held": (
              policy: pairPolicy,
              entries: <CalendarEntry<String>>[
                entryOf("tentative", at(tuesday, 10), at(tuesday, 11)),
              ],
              from: 8 * 60,
              to: 12 * 60,
              created: CalendarCreateRange(
                start: at(tuesday, 8),
                end: at(tuesday, 12, 15),
              ),
              tested: <(DateTime, DateTime)>[
                (at(tuesday, 8), at(tuesday, 10, 15)),
                (at(tuesday, 8), at(tuesday, 12, 15)),
              ],
              asked: <(String, DateTime, DateTime)>[],
            ),
            "earlier, not held": (
              policy: pairPolicy,
              entries: <CalendarEntry<String>>[
                entryOf("tentative", at(tuesday, 9), at(tuesday, 10)),
              ],
              from: 12 * 60,
              to: 8 * 60,
              created: CalendarCreateRange(
                start: at(tuesday, 8),
                end: at(tuesday, 12, 15),
              ),
              tested: <(DateTime, DateTime)>[
                (at(tuesday, 10), at(tuesday, 12, 15)),
                (at(tuesday, 8), at(tuesday, 12, 15)),
              ],
              asked: <(String, DateTime, DateTime)>[
                ("tentative", at(tuesday, 8), at(tuesday, 12, 15)),
              ],
            ),
            "held at the anchor, later": (
              policy: longPolicy,
              entries: <CalendarEntry<String>>[
                entryOf("long", at(tuesday, 7), at(tuesday, 13)),
                entryOf("side", at(tuesday, 11), at(tuesday, 11, 30)),
              ],
              from: 8 * 60,
              to: 10 * 60,
              created: CalendarCreateRange(
                start: at(tuesday, 8),
                end: at(tuesday, 8, 15),
              ),
              tested: <(DateTime, DateTime)>[
                (at(tuesday, 8), at(tuesday, 9, 15)),
                (at(tuesday, 8), at(tuesday, 10, 15)),
                (at(tuesday, 8), at(tuesday, 8, 15)),
              ],
              asked: <(String, DateTime, DateTime)>[
                ("long", at(tuesday, 8), at(tuesday, 10, 15)),
                ("long", at(tuesday, 8), at(tuesday, 8, 15)),
              ],
            ),
            "held at the anchor, earlier": (
              policy: longPolicy,
              entries: <CalendarEntry<String>>[
                entryOf("long", at(tuesday, 7), at(tuesday, 13)),
                entryOf("side", at(tuesday, 11), at(tuesday, 11, 30)),
              ],
              from: 12 * 60,
              to: 10 * 60,
              created: CalendarCreateRange(
                start: at(tuesday, 12),
                end: at(tuesday, 12, 15),
              ),
              tested: <(DateTime, DateTime)>[
                (at(tuesday, 11), at(tuesday, 12, 15)),
                (at(tuesday, 10), at(tuesday, 12, 15)),
                (at(tuesday, 12), at(tuesday, 12, 15)),
              ],
              asked: <(String, DateTime, DateTime)>[
                ("long", at(tuesday, 10), at(tuesday, 12, 15)),
                ("long", at(tuesday, 12), at(tuesday, 12, 15)),
              ],
            ),
          };
      for (final MapEntry(key: name, value: run) in cases.entries) {
        final policy = run.policy();
        final harness = Harness(
          storeOf(run.entries),
          shown,
          editPolicy: policy,
        );
        await harness.pump(tester);
        // "side" shares time with "long", which so takes the left half of
        // the column: a press on the right half of a slot it covers lies on
        // no block.
        final beside = identical(run.policy, longPolicy);
        Offset pointAt(int minute) {
          final slot = slotRect(tester, shown, tuesday, minute);
          return beside
              ? Offset(slot.left + slot.width * 0.75, slot.center.dy)
              : slot.center;
        }

        final from = pointAt(run.from);
        final gesture = await tester.startGesture(
          from,
          kind: PointerDeviceKind.mouse,
        );
        final to = pointAt(run.to);
        for (final point in <Offset>[Offset.lerp(from, to, 0.5)!, to]) {
          await gesture.moveTo(point);
          await tester.pump();
          await expectNothingAskedInsideCell(
            tester,
            gesture,
            point,
            policy,
            reason: name,
          );
        }
        await gesture.up();
        await tester.pumpAndSettle();
        if (beside) {
          // Setup sanity: the press, which asks first of the asks with no
          // entry, was admitted, the slot's candidate allowed.
          final first = policy.asked.firstWhere((ask) {
            return ask.candidate.entry == null;
          });
          expect(
            (first.candidate.start, first.candidate.end),
            (at(tuesday, 0, run.from), at(tuesday, 0, run.from + 15)),
            reason: name,
          );
          expect(policy.allows(first.candidate, first.other), isTrue);
        }
        expect(harness.creates, <CalendarCreateRange>[
          run.created,
        ], reason: name);
        for (final ask in policy.asked) {
          if (ask.candidate.entry != null) {
            // The semantic moves of "long" and "side", which share time,
            // ask about each other.
            expect(beside, isTrue, reason: name);
            continue;
          }
          expect(
            run.tested,
            contains((ask.candidate.start, ask.candidate.end)),
            reason: name,
          );
        }
        for (final (id, start, end) in run.asked) {
          expect(
            policy.asked.any((ask) {
              return ask.other.id == id &&
                  ask.candidate.start == start &&
                  ask.candidate.end == end;
            }),
            isTrue,
            reason: "$name: $id with $start to $end",
          );
        }
        expectSitePairs(policy);
        expectRangeAsked(policy, run.entries, run.created);
      }
    });

    testWidgets("OP19 in Week a create range dragged up past 61 refused "
        "entries tests two ranges per cell change, asking each entry it "
        "shares once and working out one bound, in four searches, asks "
        "nothing on a move inside the cell it tested toward, and reads no "
        "store entries", (tester) async {
      final shown = Shown.week(
        monday,
        hours: CalendarDayHours(8 * 60, 18 * 60),
      );
      final policy = pairPolicy();
      final shared = <CalendarEntry<String>>[
        for (var i = 0; i < 4; i++)
          entryOf("s$i", at(monday, 20), at(tuesday, 12, 30)),
        entryOf("s4", at(monday, 20), at(tuesday, 16, 45)),
      ];
      final store = storeOf(<CalendarEntry<String>>[
        for (var i = 0; i < 200; i++)
          entryOf("p$i", at(tuesday, 0, 5 * i), at(tuesday, 0, 5 * i + 5)),
        entryOf("free", at(tuesday, 18), at(tuesday, 19)),
        allDayOf("bar", monday),
        ...shared,
      ]);
      final harness = Harness(store, shown, editPolicy: policy);
      await harness.pump(tester);
      final reads = store.reads.length;
      final from = slotRect(tester, shown, tuesday, 17 * 60).center;
      final start = slotRect(tester, shown, tuesday, 16 * 60 + 45).center;
      final to = slotRect(tester, shown, tuesday, 12 * 60).center;
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(start);
      await tester.pump();
      final controller = boardOf(tester).controller;
      for (var step = 1; step <= 10; step++) {
        final reason = "step $step";
        final asked = policy.asked.length;
        final built = debugOverlapCandidateCount;
        final queries = debugOverlapQueryCount;
        final visits = debugOverlapIndexVisitCount;
        final bounds = debugRangeBoundCount;
        final point = Offset.lerp(start, to, step / 10)!;
        await gesture.moveTo(point);
        await tester.pump();
        final asks = policy.asked.sublist(asked);
        final candidates = Set<CalendarOverlapCandidate<String>>.identity();
        for (final ask in asks) {
          candidates.add(ask.candidate);
        }
        // Setup sanity: the step asked, and about "s4".
        expect(asks, isNotEmpty, reason: reason);
        expect(
          asks.map((ask) {
            return ask.other.id;
          }),
          contains("s4"),
          reason: reason,
        );
        expect(
          debugOverlapCandidateCount - built,
          lessThanOrEqualTo(2),
          reason: reason,
        );
        expect(debugRangeBoundCount - bounds, 1, reason: reason);
        expect(
          candidates,
          hasLength(debugOverlapCandidateCount - built),
          reason: reason,
        );
        DateTime? previous;
        for (final candidate in candidates) {
          final others = <String>[
            for (final ask in asks)
              if (identical(ask.candidate, candidate)) ask.other.id!,
          ];
          expect(others.toSet(), hasLength(others.length), reason: reason);
          for (final ask in asks) {
            if (identical(ask.candidate, candidate)) {
              expect(
                NoOverlapsPolicy.rangeSharesTime(
                  candidate.start,
                  candidate.end,
                  ask.other,
                ),
                isTrue,
                reason: reason,
              );
            }
          }
          expect(candidate.entry, isNull, reason: reason);
          expect(candidate.end, at(tuesday, 17, 15), reason: reason);
          expect(
            CalendarDates.minuteOfDay(candidate.start) % 15,
            0,
            reason: reason,
          );
          expect(
            candidate.start.isBefore(at(tuesday, 12)) ||
                candidate.start.isAfter(at(tuesday, 16, 45)),
            isFalse,
            reason: reason,
          );
          if (previous != null) {
            expect(candidate.start.isAfter(previous), isTrue, reason: reason);
          }
          previous = candidate.start;
        }
        expect(debugOverlapQueryCount - queries, 4, reason: reason);
        final stepVisits = debugOverlapIndexVisitCount - visits;
        // log2(102) is 6: 1 + 2 * (5 + 1) * (6 + 1).
        expect(stepVisits, lessThanOrEqualTo(85), reason: reason);
        if (step == 10) {
          // Setup sanity: the last step's range shares every indexed
          // "s" entry, and its index search visited nodes.
          for (final entry in shared) {
            expect(
              NoOverlapsPolicy.rangeSharesTime(
                candidates.first.start,
                candidates.first.end,
                entry,
              ),
              isTrue,
              reason: entry.id,
            );
          }
          expect(stepVisits, greaterThan(0));
        }

        // A move inside the cell the step reached.
        final cell = controller.cellAt(point);
        final nudge = controller.cellAt(point + const Offset(0.0, 1.0)) == cell
            ? const Offset(0.0, 1.0)
            : const Offset(0.0, -1.0);
        final counts = (
          policy.asked.length,
          debugOverlapCandidateCount,
          debugOverlapQueryCount,
          debugOverlapIndexVisitCount,
          debugRangeBoundCount,
        );
        await gesture.moveTo(point + nudge);
        await tester.pump();
        // Setup sanity: the move stayed in that cell.
        expect(controller.cellAt(point + nudge), cell, reason: reason);
        expect(
          (
            policy.asked.length,
            debugOverlapCandidateCount,
            debugOverlapQueryCount,
            debugOverlapIndexVisitCount,
            debugRangeBoundCount,
          ),
          counts,
          reason: "a move inside $reason's cell",
        );
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.reads, hasLength(reads));
      // Setup sanity: the release created once.
      expect(harness.creates, hasLength(1));
    });

    testWidgets("OP20 a per-pair answer that throws while a create range "
        "tests its range at a pointer move is reported and ends the range, "
        "which creates nothing", (tester) async {
      final shown = Shown.week(monday);
      await recordingErrors((errors) async {
        var armed = false;
        final policy = PairRecordingPolicy<String>(
          allows: (candidate, other) {
            if (armed) {
              throw const PairFailure();
            }
            return tentativePair(candidate, other);
          },
        );
        final harness = Harness(
          storeOf(<CalendarEntry<String>>[
            entryOf("busy", at(tuesday, 10), at(tuesday, 11)),
          ]),
          shown,
          editPolicy: policy,
        );
        await harness.pump(tester);
        final from = slotRect(tester, shown, tuesday, 8 * 60).center;
        final gesture = await tester.startGesture(
          from,
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveTo(slotRect(tester, shown, tuesday, 9 * 60).center);
        await tester.pump();
        // Setup sanity: the range is marked.
        expect(strokedRects(tester), isNotEmpty);
        armed = true;
        await gesture.moveTo(slotRect(tester, shown, tuesday, 12 * 60).center);
        await tester.pump();
        expect(
          errors.map((error) {
            return (error.library, error.exception is PairFailure);
          }),
          <(String?, bool)>[("widgets_extended calendar", true)],
        );
        expect(strokedRects(tester), isEmpty);
        expect(find.byType(ErrorWidget), findsNothing);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(harness.creates, isEmpty);
      });
    });

    testWidgets("OP25 a new minute tests a held create range's range again "
        "with no pointer move: the range a release there would report", (
      tester,
    ) async {
      final shown = Shown.week(monday);
      var armed = false;
      final policy = PairRecordingPolicy<String>(
        allows: (candidate, other) {
          return !armed;
        },
      );
      final harness = Harness(
        storeOf(<CalendarEntry<String>>[
          entryOf("tentative", at(tuesday, 10), at(tuesday, 11)),
        ]),
        shown,
        editPolicy: policy,
      );
      await harness.pump(tester);
      final from = slotRect(tester, shown, tuesday, 8 * 60).center;
      final twelve = slotRect(tester, shown, tuesday, 12 * 60).center;
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(Offset.lerp(from, twelve, 0.5)!);
      await tester.pump();
      await gesture.moveTo(twelve);
      await tester.pump();
      // Setup sanity: the range runs to 12:15.
      expect(strokedRects(tester), <Matcher>[
        nearRect(
          slotsRect(tester, shown, tuesday, 8 * 60, 12 * 60 + 15).deflate(1.0),
        ),
      ]);
      final asked = policy.asked.length;
      armed = true;
      harness.now.value = CalendarNow(
        time: at(harness.today, 9, 1),
        today: harness.today,
      );
      await tester.pump();
      expect(
        policy.asked.sublist(asked).map((ask) {
          return (
            ask.other.id,
            ask.candidate.entry,
            ask.candidate.start,
            ask.candidate.end,
          );
        }),
        <(String?, CalendarEntry<String>?, DateTime, DateTime)>[
          ("tentative", null, at(tuesday, 8), at(tuesday, 12, 15)),
        ],
      );
      expect(strokedRects(tester), <Matcher>[
        nearRect(
          slotsRect(tester, shown, tuesday, 8 * 60, 10 * 60).deflate(1.0),
        ),
      ]);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(start: at(tuesday, 8), end: at(tuesday, 10)),
      ]);
    });

    testWidgets("OP27 a reload during a create range that changes whether "
        "the policy allows overlaps places the range again by the answer it "
        "reads: from allowed, it is held at the entry the policy refuses; "
        "to allowed, it is released and a later cell asks nothing", (
      tester,
    ) async {
      final shown = Shown.week(monday);
      for (final allowedFirst in const <bool>[true, false]) {
        final reason = "allowed first: $allowedFirst";
        switchedOverlaps = allowedFirst;
        final policy = SwitchedOverlapsPolicy();
        final harness = Harness(
          storeOf(<CalendarEntry<String>>[
            entryOf("busy", at(tuesday, 10), at(tuesday, 11)),
          ]),
          shown,
          editPolicy: policy,
        );
        await harness.pump(tester);
        final from = slotRect(tester, shown, tuesday, 8 * 60).center;
        final twelve = slotRect(tester, shown, tuesday, 12 * 60).center;
        final gesture = await tester.startGesture(
          from,
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveTo(Offset.lerp(from, twelve, 0.5)!);
        await tester.pump();
        await gesture.moveTo(twelve);
        await tester.pump();
        final full = nearRect(
          slotsRect(tester, shown, tuesday, 8 * 60, 12 * 60 + 15).deflate(1.0),
        );
        final held = nearRect(
          slotsRect(tester, shown, tuesday, 8 * 60, 10 * 60).deflate(1.0),
        );
        // Setup sanity: the range runs as the policy first answers.
        expect(strokedRects(tester), <Matcher>[
          allowedFirst ? full : held,
        ], reason: reason);
        switchedOverlaps = !allowedFirst;
        final asked = policy.asked.length;
        final reassembled = tester.binding.reassembleApplication();
        await tester.pump();
        await reassembled;
        if (allowedFirst) {
          expect(
            policy.asked.sublist(asked).map((candidate) {
              return (candidate.entry, candidate.start, candidate.end);
            }),
            contains((null, at(tuesday, 8), at(tuesday, 12, 15))),
            reason: reason,
          );
          expect(strokedRects(tester), <Matcher>[held], reason: reason);
        } else {
          expect(strokedRects(tester), <Matcher>[full], reason: reason);
          await gesture.moveTo(
            slotRect(tester, shown, tuesday, 13 * 60).center,
          );
          await tester.pump();
          expect(policy.asked, hasLength(asked), reason: reason);
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(harness.creates, <CalendarCreateRange>[
          CalendarCreateRange(
            start: at(tuesday, 8),
            end: allowedFirst ? at(tuesday, 10) : at(tuesday, 13, 15),
          ),
        ], reason: reason);
      }
    });

    testWidgets("OP28 a new store a build gives during a create range "
        "places the range again on that store's entries", (tester) async {
      final shown = Shown.week(monday);
      final policy = pairPolicy();
      final harness = Harness(
        storeOf(<CalendarEntry<String>>[
          entryOf("tentative", at(tuesday, 10), at(tuesday, 11)),
        ]),
        shown,
        editPolicy: policy,
      );
      await harness.pump(tester);
      final from = slotRect(tester, shown, tuesday, 8 * 60).center;
      final twelve = slotRect(tester, shown, tuesday, 12 * 60).center;
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(Offset.lerp(from, twelve, 0.5)!);
      await tester.pump();
      await gesture.moveTo(twelve);
      await tester.pump();
      // Setup sanity: the range runs to 12:15.
      expect(strokedRects(tester), <Matcher>[
        nearRect(
          slotsRect(tester, shown, tuesday, 8 * 60, 12 * 60 + 15).deflate(1.0),
        ),
      ]);
      final busy = entryOf("busy", at(tuesday, 10), at(tuesday, 11));
      harness.store = storeOf(<CalendarEntry<String>>[busy]);
      await harness.rebuild(tester);
      await tester.pump();
      expectRangeAsked(policy, <CalendarEntry<String>>[
        busy,
      ], CalendarCreateRange(start: at(tuesday, 8), end: at(tuesday, 12, 15)));
      expect(strokedRects(tester), <Matcher>[
        nearRect(
          slotsRect(tester, shown, tuesday, 8 * 60, 10 * 60).deflate(1.0),
        ),
      ]);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.creates, <CalendarCreateRange>[
        CalendarCreateRange(start: at(tuesday, 8), end: at(tuesday, 10)),
      ]);
    });
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
      CalendarMoveKind kind, {
      bool? isAllDay,
    }) {
      return CalendarMoveRequest<String>(
        entry: entry,
        requested: entry.copyWith(start: start, end: end, isAllDay: isAllDay),
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
          isAllDay: false,
        ),
      ],
      "block on strip": <CalendarMoveRequest<String>>[
        request(meet, tuesday, wednesday, move, isAllDay: true),
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

  testWidgets("MR3 a request whose future fails after the call, and one "
      "whose function throws within it, each show the block at its stored "
      "times again, and their errors are not caught", (tester) async {
    final shown = Shown.week(monday);
    final meet = entryOf("meet", at(tuesday, 10), at(tuesday, 11));
    final thrown = StateError("Refused.");
    final uncaught = <Object>[];
    final answers = <Completer<void>>[];
    await Harness(
      storeOf(<CalendarEntry<String>>[meet]),
      shown,
      onMoveRequest: (request) {
        // Made in the drop's zone, where the grid listens to it: a
        // future's error reaches no listener in another error zone
        // ([Zone.inSameErrorZone]).
        final answer = Completer<void>();
        answers.add(answer);
        return answer.future;
      },
    ).pump(tester);
    final stored = tester.getRect(blockFinder("meet", tuesday));
    final requested = stored.translate(
      0.0,
      slotRect(tester, shown, tuesday, 14 * 60).top -
          slotRect(tester, shown, tuesday, 10 * 60).top,
    );
    await dropMeetInZone(tester, shown, uncaught);
    // Setup sanity: the drop's request runs, its block held at the
    // requested times.
    expect(answers, hasLength(1));
    expect(tester.getRect(blockFinder("meet", tuesday)), nearRect(requested));
    answers.single.completeError(thrown);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(uncaught, <Object>[same(thrown)]);
    expect(tester.getRect(blockFinder("meet", tuesday)), nearRect(stored));

    uncaught.clear();
    await Harness(
      storeOf(<CalendarEntry<String>>[meet]),
      shown,
      onMoveRequest: (request) {
        throw thrown;
      },
    ).pump(tester);
    await dropMeetInZone(tester, shown, uncaught);
    expect(uncaught, <Object>[same(thrown)]);
    expect(tester.getRect(blockFinder("meet", tuesday)), nearRect(stored));
  });

  testWidgets("MR4 with no onMoveRequest, a move whose write the caching "
      "store fails leaves no error uncaught, and its block shows the stored "
      "entry again, at its stored times and not pending", (tester) async {
    final shown = Shown.week(monday);
    final source = HeldSource(<CalendarEntry<String>>[
      entryOf("meet", at(tuesday, 10), at(tuesday, 11)),
    ]);
    final store = CachingCalendarStore<String>(dataSource: source);
    addTearDown(store.dispose);
    store.show(monday, sunday);
    await Harness(store, shown).pump(tester);
    final stored = tester.getRect(blockFinder("meet", tuesday));
    final requested = stored.translate(
      0.0,
      slotRect(tester, shown, tuesday, 14 * 60).top -
          slotRect(tester, shown, tuesday, 10 * 60).top,
    );
    final uncaught = <Object>[];
    await dropMeetInZone(tester, shown, uncaught);
    // Setup sanity: the drop's move shows at the requested times, and the
    // grid wrote it through the store.
    expect(tester.getRect(blockFinder("meet", tuesday)), nearRect(requested));
    expect(source.replaces, hasLength(1));
    source.replaces.single.completeError(StateError("Offline."));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(uncaught, isEmpty);
    expect(tester.getRect(blockFinder("meet", tuesday)), nearRect(stored));
    expect(
      find.descendant(
        of: blockFinder("meet", tuesday),
        matching: find.byType(CalendarActivityIndicator),
      ),
      findsNothing,
    );
  });

  testWidgets("MR5 with no onMoveRequest, a move whose write the store "
      "throws within the call leaves no error uncaught, and its block shows "
      "at its stored times again", (tester) async {
    final shown = Shown.week(monday);
    final meet = entryOf("meet", at(tuesday, 10), at(tuesday, 11));
    final store = ThrowingMoveStore(<CalendarEntry<String>>[
      meet,
    ], StateError("Refused."));
    addTearDown(store.dispose);
    await Harness(store, shown).pump(tester);
    final stored = tester.getRect(blockFinder("meet", tuesday));
    final uncaught = <Object>[];
    await dropMeetInZone(tester, shown, uncaught);
    // Setup sanity: the grid wrote the drop's move through the store.
    expect(store.moves, <CalendarEntry<String>>[
      meet.copyWith(start: at(tuesday, 14), end: at(tuesday, 15)),
    ]);
    expect(uncaught, isEmpty);
    expect(tester.getRect(blockFinder("meet", tuesday)), nearRect(stored));
  });

  testWidgets("MR6 with no onMoveRequest, a move the in-memory store "
      "stores, whose onChanged then throws, leaves no error uncaught and "
      "reports the throw", (tester) async {
    final shown = Shown.week(monday);
    final meet = entryOf("meet", at(tuesday, 10), at(tuesday, 11));
    const thrown = HostFailure();
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[meet],
      onChanged: (old, entry) {
        throw thrown;
      },
    );
    addTearDown(store.dispose);
    await Harness(store, shown).pump(tester);
    final uncaught = <Object>[];
    await dropMeetInZone(tester, shown, uncaught);
    // Setup sanity: the store stored the drop's move.
    expect(
      store.storedEntry("meet"),
      meet.copyWith(start: at(tuesday, 14), end: at(tuesday, 15)),
    );
    expect(uncaught, isEmpty);
    expect(tester.takeException(), same(thrown));
  });

  testWidgets("MR7 a block dropped back where it was requests nothing, and "
      "with a payload whose == throws during the release throws nothing and "
      "compares no payload; dropped on another slot with that payload, it "
      "requests the move", (tester) async {
    final shown = Shown.week(monday);
    final payload = Brittle();
    final meet = brittleEntryOf(
      "meet",
      at(tuesday, 10),
      at(tuesday, 11),
      payload,
    );
    final requests = await pumpBrittleWeek(tester, <CalendarEntry<Brittle>>[
      meet,
    ]);
    final from = tester.getRect(blockFinder("meet", tuesday));
    final away =
        slotRect(tester, shown, tuesday, 12 * 60).top -
        slotRect(tester, shown, tuesday, 10 * 60).top;
    // Lifts the block, carries it two hours down and back, and returns the
    // gesture still held.
    Future<TestGesture> carryBack() async {
      final gesture = await lift(tester, from.center);
      await gesture.moveBy(Offset(0.0, away));
      await tester.pump();
      await gesture.moveBy(Offset(0.0, -away));
      await tester.pump();
      return gesture;
    }

    // With the payload's == answering, so a request would reach the
    // grid's onMoveRequest: where it throws, the grid's sync of a request
    // keeping the times compares the payloads before that.
    var gesture = await carryBack();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requests, isEmpty);

    gesture = await carryBack();
    await releaseBrittle(gesture, payload);
    expect(tester.takeException(), isNull);
    expect(payload.compared, 0);
    await tester.pumpAndSettle();

    final slot = slotRect(tester, shown, tuesday, 14 * 60);
    gesture = await lift(tester, from.center);
    await gesture.moveBy(slot.topLeft - from.topLeft + const Offset(0.0, 2.0));
    await tester.pump();
    await releaseBrittle(gesture, payload);
    await tester.pumpAndSettle();
    expect(
      <(DateTime, DateTime, CalendarMoveKind)>[
        for (final request in requests)
          (request.requested.start, request.requested.end, request.kind),
      ],
      <(DateTime, DateTime, CalendarMoveKind)>[
        (at(tuesday, 14), at(tuesday, 15), CalendarMoveKind.move),
      ],
    );
  });

  testWidgets("MR8 an end handle dragged into a later day and held at the "
      "day limit at the end its entry has requests nothing, and with a "
      "payload whose == throws during the release throws nothing and "
      "compares no payload; with no limit, it requests the later end", (
    tester,
  ) async {
    final payload = Brittle();
    final late = brittleEntryOf("late", at(monday, 22), wednesday, payload);
    var requests = await pumpBrittleWeek(tester, <CalendarEntry<Brittle>>[
      late,
    ], maxDayCount: 2);
    // With the payload's == answering first, as in MR7.
    var gesture = await holdLateEndOverWednesday(tester);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(requests, isEmpty);

    gesture = await holdLateEndOverWednesday(tester);
    await releaseBrittle(gesture, payload);
    expect(tester.takeException(), isNull);
    expect(payload.compared, 0);
    await tester.pumpAndSettle();

    requests = await pumpBrittleWeek(tester, <CalendarEntry<Brittle>>[late]);
    gesture = await holdLateEndOverWednesday(tester);
    await releaseBrittle(gesture, payload);
    await tester.pumpAndSettle();
    expect(
      <(DateTime, DateTime, CalendarMoveKind)>[
        for (final request in requests)
          (request.requested.start, request.requested.end, request.kind),
      ],
      <(DateTime, DateTime, CalendarMoveKind)>[
        (at(monday, 22), at(wednesday, 12, 15), CalendarMoveKind.resize),
      ],
    );
  });

  testWidgets("CR1 a create whose onCreate throws within the call clears "
      "its marked range, and the throw is left uncaught in the zone, as a "
      "failure of its future is", (tester) async {
    for (final shown in bothGrids()) {
      final created = <CalendarCreateRange>[];
      final failure = CreateFailure();
      final harness = Harness(
        storeOf(<CalendarEntry<String>>[]),
        shown,
        onCreate: (details) {
          created.add(details.range);
          throw failure;
        },
      );
      await harness.pump(tester);
      final from = slotRect(tester, shown, tuesday, 10 * 60).center;
      final to = slotRect(tester, shown, tuesday, 12 * 60).center;
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      // The release runs in a zone of its own, as in [dropMeetInZone].
      final uncaught = <Object>[];
      await runZonedGuarded(
        () async {
          await gesture.up();
        },
        (error, stackTrace) {
          uncaught.add(error);
        },
      );
      await tester.pumpAndSettle();
      expect(created, hasLength(1), reason: shown.name);
      expect(strokedRects(tester), isEmpty, reason: shown.name);
      expect(tester.takeException(), isNull, reason: shown.name);
      expect(uncaught, <Matcher>[same(failure)], reason: shown.name);
    }
  });

  testWidgets("CM1 the range a create flow marks stays on its own days: "
      "while the flow is open, a step to the next week marks no slot and no "
      "strip cell there, and a step back marks the range again", (
    tester,
  ) async {
    List<DateTime> weekOf(DateTime first) {
      return <DateTime>[
        for (var i = 0; i < 7; i++) CalendarDates.addDays(first, i),
      ];
    }

    final shown = Shown.week(monday);
    for (final strip in const <bool>[false, true]) {
      final reason = strip ? "strip" : "slots";
      final answer = Completer<void>();
      final harness = Harness(
        storeOf(<CalendarEntry<String>>[]),
        shown,
        onCreate: (range) {
          return answer.future;
        },
      );
      await harness.pump(tester);
      final from = strip
          ? stripRect(tester, shown, thursday).center
          : slotRect(tester, shown, thursday, 14 * 60).center;
      final to = strip
          ? stripRect(tester, shown, friday).center
          : slotRect(tester, shown, thursday, 16 * 60).center;
      await createDrag(tester, from, to);
      void expectMarked() {
        if (strip) {
          expect(markedOf(tester, weekOf(monday)), <DateTime>[
            thursday,
            friday,
          ], reason: reason);
        } else {
          expect(strokedRects(tester), <Matcher>[
            nearRect(
              slotsRect(
                tester,
                shown,
                thursday,
                14 * 60,
                16 * 60 + 15,
              ).deflate(1.0),
            ),
          ], reason: reason);
        }
      }

      // Setup sanity: the open flow marks its range.
      expectMarked();

      harness.first = nextMonday;
      await harness.rebuild(tester);
      await tester.pumpAndSettle();
      if (strip) {
        expect(markedOf(tester, weekOf(nextMonday)), isEmpty, reason: reason);
      } else {
        expect(strokedRects(tester), isEmpty, reason: reason);
      }

      harness.first = monday;
      await harness.rebuild(tester);
      await tester.pumpAndSettle();
      expectMarked();
      answer.complete();
      await tester.pumpAndSettle();
    }
  });

  testWidgets("GM1 while a block is lifted nothing creates: no drag or tap "
      "pressed during the lift, and none pressed before it whose drag or "
      "release comes during it; once the block is let go the same drag and "
      "the same tap create", (tester) async {
    final shown = Shown.week(monday);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("meet", at(tuesday, 10), at(tuesday, 11)),
    ]);
    final harness = Harness(store, shown);
    await harness.pump(tester);
    final block = tester.getCenter(blockFinder("meet", tuesday));
    final from = slotRect(tester, shown, thursday, 14 * 60).center;
    final to = slotRect(tester, shown, thursday, 16 * 60).center;
    for (final (drags, before) in const <(bool, bool)>[
      (true, false),
      (true, true),
      (false, false),
      (false, true),
    ]) {
      final reason =
          "${drags ? "drag" : "tap"} pressed "
          "${before ? "before" : "during"} the lift";
      TestGesture? creating;
      if (before) {
        creating = await tester.startGesture(
          from,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
      }
      final lifting = await lift(tester, block);
      // Setup sanity: the block is lifted.
      expect(find.byKey(liftedBlockKey), findsOneWidget, reason: reason);
      creating ??= await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      if (drags) {
        await creating.moveTo(Offset.lerp(from, to, 0.5)!);
        await tester.pump();
        await creating.moveTo(to);
        await tester.pump();
      }
      await creating.up();
      await tester.pump();
      expect(harness.creates, isEmpty, reason: reason);
      await lifting.up();
      await tester.pumpAndSettle();
    }

    await createDrag(tester, from, to);
    await tester.tapAt(from);
    await tester.pumpAndSettle();
    expect(harness.creates, <CalendarCreateRange>[
      CalendarCreateRange(start: at(thursday, 14), end: at(thursday, 16, 15)),
      CalendarCreateRange(start: at(thursday, 14), end: at(thursday, 14, 15)),
    ]);
  });

  testWidgets("GM2 a block lifted while a create range runs ends the range: "
      "the slots and the strip cells it marked clear, and its release "
      "creates nothing", (tester) async {
    final shown = Shown.week(monday);
    for (final strip in const <bool>[false, true]) {
      final reason = strip ? "strip" : "slots";
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("meet", at(tuesday, 10), at(tuesday, 11)),
      ]);
      final harness = Harness(store, shown);
      await harness.pump(tester);
      final from = strip
          ? stripRect(tester, shown, thursday).center
          : slotRect(tester, shown, thursday, 14 * 60).center;
      final to = strip
          ? stripRect(tester, shown, friday).center
          : slotRect(tester, shown, thursday, 16 * 60).center;
      final creating = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await creating.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await creating.moveTo(to);
      await tester.pump();
      // Setup sanity: the range runs and is marked.
      final ranged = strokedRects(tester);
      if (strip) {
        expect(markedOf(tester, <DateTime>[thursday, friday]), <DateTime>[
          thursday,
          friday,
        ], reason: reason);
      } else {
        expect(ranged, hasLength(1), reason: reason);
      }

      final lifting = await lift(
        tester,
        tester.getCenter(blockFinder("meet", tuesday)),
      );
      // Setup sanity: the block is lifted.
      expect(find.byKey(liftedBlockKey), findsOneWidget, reason: reason);
      if (strip) {
        expect(
          markedOf(tester, <DateTime>[thursday, friday]),
          isEmpty,
          reason: reason,
        );
      } else {
        // The lifted block's own landing outline is stroked in its place.
        expect(
          strokedRects(tester),
          isNot(contains(ranged.single)),
          reason: reason,
        );
      }
      await creating.up();
      await tester.pump();
      expect(harness.creates, isEmpty, reason: reason);
      await lifting.up();
      await tester.pumpAndSettle();
    }
  });

  testWidgets("GM3 a block lifted while a pinch zooms ends the pinch: the "
      "fingers spreading on zoom nothing more", (tester) async {
    final shown = Shown.week(monday);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("meet", at(tuesday, 10), at(tuesday, 11)),
    ]);
    final zooms = <double>[];
    final harness = Harness(
      store,
      shown,
      onZoom: (minSlotHeight, minDayWidth) {
        zooms.add(minSlotHeight);
      },
    );
    await harness.pump(tester);
    final focal = slotRect(tester, shown, thursday, 15 * 60).center;
    final first = await tester.startGesture(focal - const Offset(0.0, 30.0));
    final second = await tester.startGesture(focal + const Offset(0.0, 30.0));
    Future<void> spread() async {
      for (var i = 0; i < 3; i++) {
        await first.moveBy(const Offset(0.0, -6.0));
        await second.moveBy(const Offset(0.0, 6.0));
        await tester.pump();
      }
    }

    await spread();
    // Setup sanity: the pinch zooms.
    expect(zooms, isNotEmpty);
    final lifting = await lift(
      tester,
      tester.getCenter(blockFinder("meet", tuesday)),
    );
    // Setup sanity: the block is lifted.
    expect(find.byKey(liftedBlockKey), findsOneWidget);
    zooms.clear();
    await spread();
    expect(zooms, isEmpty);
    await lifting.up();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
  });

  testWidgets("GM4 while a create range runs or a pinch zooms no create "
      "range or tap creates, pressed during it or, for the pinch, before it; "
      "while either runs or a block is lifted no pinch zooms; and the "
      "running gesture goes on", (tester) async {
    final shown = Shown.week(monday);
    for (final (running, other) in const <(String, String)>[
      ("range", "range"),
      ("range", "tap"),
      ("range", "pinch"),
      ("pinch", "range"),
      ("pinch", "range pressed before it"),
      ("pinch", "tap"),
      ("pinch", "tap pressed before it"),
      ("lift", "pinch"),
    ]) {
      final reason = "$other during a $running";
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("meet", at(tuesday, 10), at(tuesday, 11)),
      ]);
      final zooms = <double>[];
      final harness = Harness(
        store,
        shown,
        onZoom: (minSlotHeight, minDayWidth) {
          zooms.add(minSlotHeight);
        },
      );
      await harness.pump(tester);
      final rangeFrom = slotRect(tester, shown, thursday, 14 * 60).center;
      final rangeTo = slotRect(tester, shown, thursday, 16 * 60).center;
      final otherFrom = slotRect(tester, shown, friday, 10 * 60).center;
      final otherTo = slotRect(tester, shown, friday, 11 * 60).center;
      // The hour gutter, where no press creates, so the pinch's touches
      // leave the create tap free for the mouse.
      final focal = cellRect(tester, shown.rowOf(18 * 60), 0).center;
      final held = <TestGesture>[];
      Future<TestGesture> press(Offset at) async {
        final gesture = await tester.startGesture(
          at,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        return gesture;
      }

      Future<void> spread() async {
        for (var i = 0; i < 3; i++) {
          await held[held.length - 2].moveBy(const Offset(0.0, -6.0));
          await held.last.moveBy(const Offset(0.0, 6.0));
          await tester.pump();
        }
      }

      Future<void> pinch() async {
        held.add(await tester.startGesture(focal - const Offset(0.0, 30.0)));
        held.add(await tester.startGesture(focal + const Offset(0.0, 30.0)));
        await spread();
      }

      final before = other.endsWith("before it")
          ? await press(otherFrom)
          : null;
      TestGesture? ranging;
      switch (running) {
        case "range":
          ranging = await press(rangeFrom);
          await ranging.moveTo(Offset.lerp(rangeFrom, rangeTo, 0.5)!);
          await tester.pump();
          await ranging.moveTo(rangeTo);
          await tester.pump();
          // Setup sanity: the range runs.
          expect(strokedRects(tester), hasLength(1), reason: reason);
        case "pinch":
          await pinch();
          // Setup sanity: the pinch zooms.
          expect(zooms, isNotEmpty, reason: reason);
        case "lift":
          held.add(await press(tester.getCenter(blockFinder("meet", tuesday))));
          await tester.pump(kLongPressTimeout + kPressTimeout);
          // Setup sanity: the block is lifted.
          expect(find.byKey(liftedBlockKey), findsOneWidget, reason: reason);
      }

      zooms.clear();
      if (other == "pinch") {
        await pinch();
        expect(zooms, isEmpty, reason: reason);
      } else {
        final creating = before ?? await press(otherFrom);
        if (other.startsWith("range")) {
          await creating.moveTo(otherTo);
          await tester.pump();
        }
        await creating.up();
        await tester.pump();
        expect(harness.creates, isEmpty, reason: reason);
      }

      switch (running) {
        case "range":
          await ranging!.up();
          await tester.pump();
          expect(
            <DateTime>[for (final range in harness.creates) range.start],
            <DateTime>[at(thursday, 14)],
            reason: reason,
          );
        case "pinch":
          await spread();
          expect(zooms, isNotEmpty, reason: reason);
        case "lift":
          expect(find.byKey(liftedBlockKey), findsOneWidget, reason: reason);
      }
      for (final gesture in held) {
        await gesture.up();
      }
      await tester.pumpAndSettle();
    }
  });

  testWidgets("GM5 a tap or a drag pressed before a create range and let go "
      "while it runs creates nothing, and nor does a tap while a block lifted "
      "during a pinch is held after the pinch's fingers lift; and the range "
      "or the lift goes on", (tester) async {
    final shown = Shown.week(monday);
    for (final other in const <String>["tap", "range", "pinch"]) {
      final reason = switch (other) {
        "tap" => "tap pressed before a range",
        "range" => "range pressed before a range",
        _ => "tap during a lift, after the pinch it ended lets go",
      };
      final store = storeOf(<CalendarEntry<String>>[
        entryOf("meet", at(tuesday, 10), at(tuesday, 11)),
      ]);
      final zooms = <double>[];
      final harness = Harness(
        store,
        shown,
        onZoom: (minSlotHeight, minDayWidth) {
          zooms.add(minSlotHeight);
        },
      );
      await harness.pump(tester);
      final rangeFrom = slotRect(tester, shown, thursday, 14 * 60).center;
      final rangeTo = slotRect(tester, shown, thursday, 16 * 60).center;
      final otherFrom = slotRect(tester, shown, friday, 10 * 60).center;
      final otherTo = slotRect(tester, shown, friday, 11 * 60).center;
      // The hour gutter, where no press creates.
      final focal = cellRect(tester, shown.rowOf(18 * 60), 0).center;
      Future<TestGesture> press(Offset at) async {
        final gesture = await tester.startGesture(
          at,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        return gesture;
      }

      if (other == "pinch") {
        final first = await tester.startGesture(
          focal - const Offset(0.0, 30.0),
        );
        final second = await tester.startGesture(
          focal + const Offset(0.0, 30.0),
        );
        for (var i = 0; i < 3; i++) {
          await first.moveBy(const Offset(0.0, -6.0));
          await second.moveBy(const Offset(0.0, 6.0));
          await tester.pump();
        }
        // Setup sanity: the pinch zooms.
        expect(zooms, isNotEmpty, reason: reason);
        final lifting = await press(
          tester.getCenter(blockFinder("meet", tuesday)),
        );
        await tester.pump(kLongPressTimeout + kPressTimeout);
        // Setup sanity: the block is lifted.
        expect(find.byKey(liftedBlockKey), findsOneWidget, reason: reason);
        await first.up();
        await second.up();
        await tester.pump();
        final tapping = await press(otherFrom);
        await tapping.up();
        await tester.pump();
        expect(harness.creates, isEmpty, reason: reason);
        expect(find.byKey(liftedBlockKey), findsOneWidget, reason: reason);
        await lifting.up();
      } else {
        final creating = await press(otherFrom);
        final ranging = await press(rangeFrom);
        await ranging.moveTo(Offset.lerp(rangeFrom, rangeTo, 0.5)!);
        await tester.pump();
        await ranging.moveTo(rangeTo);
        await tester.pump();
        // Setup sanity: the range runs.
        expect(strokedRects(tester), hasLength(1), reason: reason);
        if (other == "range") {
          await creating.moveTo(otherTo);
          await tester.pump();
        }
        await creating.up();
        await tester.pump();
        expect(harness.creates, isEmpty, reason: reason);
        await ranging.up();
        await tester.pump();
        expect(
          <DateTime>[for (final range in harness.creates) range.start],
          <DateTime>[at(thursday, 14)],
          reason: reason,
        );
      }
      await tester.pumpAndSettle();
    }
  });

  testWidgets("GM6 a grid taken out of the tree while two fingers pinch it "
      "takes no more of their events: their lift and their cancel report no "
      "error", (tester) async {
    for (final cancel in <bool>[false, true]) {
      final reason = cancel ? "cancel" : "lift";
      final shown = Shown.week(monday);
      final zooms = <double>[];
      await Harness(
        storeOf(<CalendarEntry<String>>[]),
        shown,
        onZoom: (minSlotHeight, minDayWidth) {
          zooms.add(minSlotHeight);
        },
      ).pump(tester);
      final focal = slotRect(tester, shown, thursday, 15 * 60).center;
      final first = await tester.startGesture(focal - const Offset(0.0, 30.0));
      final second = await tester.startGesture(focal + const Offset(0.0, 30.0));
      for (var i = 0; i < 3; i++) {
        await first.moveBy(const Offset(0.0, -6.0));
        await second.moveBy(const Offset(0.0, 6.0));
        await tester.pump();
      }
      // Setup sanity: the pinch zooms.
      expect(zooms, isNotEmpty, reason: reason);

      await tester.pumpWidget(const SizedBox());
      await recordingErrors((errors) async {
        if (cancel) {
          await first.cancel();
          await second.cancel();
        } else {
          await first.up();
          await second.up();
        }
        await tester.pump();
        expect(errors, isEmpty, reason: reason);
      });
    }
  });

  testWidgets("GM7 a grid taken out of the tree while a bar's day-edge "
      "resize is held at the day limit takes no more of the drag's events: "
      "its lift writes nothing, and its lift and its cancel report no "
      "error", (tester) async {
    for (final cancel in <bool>[false, true]) {
      final reason = cancel ? "cancel" : "lift";
      final (gesture, store) = await holdBarEdge(
        tester,
        limit: 3,
        id: "m",
        day: monday,
        side: AxisDirection.right,
        over: thursday,
      );
      await tester.pumpAndSettle();
      // Setup sanity: the limit holds the bar at Monday to Wednesday, which
      // a release on the grid writes (TX8).
      expect(
        markedOf(tester, <DateTime>[
          for (var i = 0; i < 7; i++) CalendarDates.addDays(monday, i),
        ]),
        <DateTime>[monday, tuesday, wednesday],
        reason: reason,
      );

      await tester.pumpWidget(const SizedBox());
      await recordingErrors((errors) async {
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pump();
        expect(errors, isEmpty, reason: reason);
      });
      if (!cancel) {
        expect(store.moves, isEmpty);
      }
    }
  });

  testWidgets("HF2 the landing label writes its times in the grid's hour "
      "format, for a block moved in the slots and for a bar carried onto "
      "them", (tester) async {
    final shown = Shown.week(monday);
    final store = storeOf(<CalendarEntry<String>>[
      entryOf("task", at(wednesday, 9), at(wednesday, 10)),
      allDayOf("off", tuesday),
    ]);
    await Harness(
      store,
      shown,
      hourLabelFormat: CalendarHourLabelFormat.twelveHour,
    ).pump(tester);
    final slot = slotRect(tester, shown, wednesday, 9 * 60).height;
    final block = await lift(
      tester,
      tester.getCenter(blockFinder("task", wednesday)),
    );
    await block.moveBy(Offset(0.0, slot * 2 + 2.0));
    await tester.pump();
    expect(landingText(tester), "Wednesday, April 22, 9:30 AM-10:30 AM");
    await block.up();
    await tester.pumpAndSettle();

    final bar = await liftTo(
      tester,
      tester.getCenter(barFinder("off")),
      slotRect(tester, shown, tuesday, 10 * 60).center,
    );
    expect(landingText(tester), "Tuesday, April 21, 10 AM-11 AM");
    await bar.up();
    await tester.pumpAndSettle();
  });

  group(
    "on the day whose clock skips its midnight",
    skip: skippedMidnightSkip,
    () {
      testWidgets("TX27 in Week, a bar dropped on the day's 00:00 slot "
          "requests nothing, and one dropped on its 01:00 slot an hour from "
          "the day's start", (tester) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final shown = Shown.week(CalendarDates.addDays(day, -6));
        final store = storeOf(<CalendarEntry<String>>[allDayOf("off", day)]);
        await Harness(store, shown).pump(tester);
        await dragTo(
          tester,
          tester.getCenter(barFinder("off")),
          slotRect(tester, shown, day, 0).center,
        );
        expect(store.moves, isEmpty);
        // Setup sanity: the same drop on the 01:00 slot lands.
        await dragTo(
          tester,
          tester.getCenter(barFinder("off")),
          slotRect(tester, shown, day, 60).center,
        );
        expect(store.moves, <CalendarEntry<String>>[
          entryOf("off", day, at(day, 2)),
        ]);
      });

      testWidgets("TX34 in Week under a one-day limit, a create drag from the "
          "next day back onto the day's 00:00 slot is not held and reports "
          "nothing", (tester) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final next = CalendarDates.addDays(day, 1);
        final shown = Shown.week(CalendarDates.addDays(day, -5));
        final harness = Harness(
          storeOf(const <CalendarEntry<String>>[]),
          shown,
          maxDayCount: 1,
        );
        await harness.pump(tester);
        await createDrag(
          tester,
          slotRect(tester, shown, next, 5 * 60).center,
          slotRect(tester, shown, day, 0).center,
        );
        expect(harness.creates, isEmpty);
      });

      testWidgets("TX28 in Week, an end handle let go over the last slot of "
          "a later day, the day before, ends the entry at the day's start", (
        tester,
      ) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final earlier = CalendarDates.addDays(before, -1);
        final evening = entryOf("evening", at(earlier, 22), at(earlier, 23));
        // Guard: red when the slot's end converts by the clock.
        final store = await releaseEndOver(
          tester,
          entries: <CalendarEntry<String>>[evening],
          id: "evening",
          day: earlier,
          over: before,
          minute: 23 * 60 + 45,
          first: CalendarDates.addDays(day, -6),
        );
        expect(store.moves, <CalendarEntry<String>>[
          evening.copyWith(end: day),
        ]);
      });

      testWidgets("TX29 in Week where overlaps are forbidden, a create range "
          "from the day before's last slot toward an entry from the day's "
          "start is held at that slot and ends at the day's start", (
        tester,
      ) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final shown = Shown.week(CalendarDates.addDays(day, -6));
        final harness = Harness(
          storeOf(<CalendarEntry<String>>[entryOf("talk", day, at(day, 2))]),
          shown,
          allowsOverlaps: false,
        );
        await harness.pump(tester);
        final from = slotRect(tester, shown, before, 23 * 60 + 45).center;
        final to = slotRect(tester, shown, day, 3 * 60).center;
        final gesture = await tester.startGesture(
          from,
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
        await tester.pump();
        await gesture.moveTo(to);
        await tester.pump();
        // Guard: red when the bound before the entry reads by the clock,
        // at 01:00, which marks the day's 00:00 to 01:00 rows too.
        expect(strokedRects(tester), <Matcher>[
          nearRect(
            slotsRect(
              tester,
              shown,
              before,
              23 * 60 + 45,
              24 * 60,
            ).deflate(1.0),
          ),
        ]);
        await gesture.up();
        await tester.pumpAndSettle();
        // Guard: red when the anchor slot's end converts by the clock, which
        // reads no entry next to it.
        expect(harness.creates, <CalendarCreateRange>[
          CalendarCreateRange(start: at(before, 23, 45), end: day),
        ]);
      });

      testWidgets("TX30 in Week under a one-day limit, create ranges held at "
          "the limit end at the day's start and start at the day's start", (
        tester,
      ) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final earlier = CalendarDates.addDays(before, -1);
        final shown = Shown.week(CalendarDates.addDays(day, -6));
        final harness = Harness(
          storeOf(const <CalendarEntry<String>>[]),
          shown,
          maxDayCount: 1,
        );
        await harness.pump(tester);
        // Guard: red when the forward end converts by the clock, which
        // holds nothing, so the range covers two days.
        await createDrag(
          tester,
          slotRect(tester, shown, earlier, 22 * 60).center,
          slotRect(tester, shown, before, 23 * 60 + 45).center,
        );
        // Guard: red when the backward end converts by the clock.
        await createDrag(
          tester,
          slotRect(tester, shown, before, 23 * 60 + 45).center,
          slotRect(tester, shown, earlier, 22 * 60).center,
        );
        // Guard: red when the held start's wall minute reads as an end,
        // which holds the range at the 00:00 slot, whose start the clock
        // skips.
        await createDrag(
          tester,
          slotRect(tester, shown, day, 5 * 60).center,
          slotRect(tester, shown, before, 22 * 60).center,
        );
        expect(harness.creates, <CalendarCreateRange>[
          CalendarCreateRange(start: at(earlier, 22), end: before),
          CalendarCreateRange(start: before, end: day),
          CalendarCreateRange(start: day, end: at(day, 5, 15)),
        ]);
      });

      testWidgets("TX31 in Week under a two-day limit, a create range held at "
          "the limit marks the slots to the day before's end and ends at the "
          "day's start", (tester) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final earlier = CalendarDates.addDays(before, -1);
        final shown = Shown.week(CalendarDates.addDays(day, -6));
        final harness = Harness(
          storeOf(const <CalendarEntry<String>>[]),
          shown,
          maxDayCount: 2,
        );
        await harness.pump(tester);
        final from = slotRect(tester, shown, earlier, 22 * 60).center;
        final to = slotRect(tester, shown, day, 3 * 60).center;
        final gesture = await tester.startGesture(
          from,
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
        await tester.pump();
        await gesture.moveTo(to);
        await tester.pump();
        // Guard: red when the held end's wall minute reads by the clock,
        // which marks the day's 00:00 to 01:00 rows too.
        expect(strokedRects(tester), <Matcher>[
          nearRect(
            slotsRect(tester, shown, earlier, 22 * 60, 24 * 60).deflate(1.0),
          ),
          nearRect(slotsRect(tester, shown, before, 0, 24 * 60).deflate(1.0)),
        ]);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(harness.creates, <CalendarCreateRange>[
          CalendarCreateRange(start: at(earlier, 22), end: day),
        ]);
      });

      testWidgets("TX33 in Week under lockPast with today the day, a create "
          "drag back into the day before, which the lock closes, starts at "
          "the day's start", (tester) async {
        final day = shortDayStart;
        expectSkippedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final shown = Shown.week(CalendarDates.addDays(day, -6));
        final harness = Harness(
          storeOf(const <CalendarEntry<String>>[]),
          shown,
          lockPast: true,
          today: day,
        );
        await harness.pump(tester);
        // Guard: red when the closed day's bound stays the day's minute 0,
        // which holds the range at the 00:00 slot, whose start the clock
        // skips.
        await createDrag(
          tester,
          slotRect(tester, shown, day, 5 * 60).center,
          slotRect(tester, shown, before, 3 * 60).center,
        );
        expect(harness.creates, <CalendarCreateRange>[
          CalendarCreateRange(start: day, end: at(day, 5, 15)),
        ]);
      });
    },
  );

  group(
    "on the day whose clock repeats its midnight",
    skip: repeatedMidnightSkip,
    () {
      testWidgets("TX32 in Week, the block of an entry ending at the later "
          "00:00 continues after the day before, and its block on that day "
          "continues from it and ends it", (tester) async {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final before = DateTime(day.year, day.month, day.day - 1);
        final details = <String, List<CalendarBlockDetails>>{};
        await Harness(
          storeOf(<CalendarEntry<String>>[
            entryOf("late", at(before, 23), laterMidnight),
          ]),
          Shown.week(CalendarDates.addDays(day, -6)),
          blockBuilder: (context, entry, given) {
            (details[entry.id] ??= <CalendarBlockDetails>[]).add(given);
            return defaultCalendarBlockBuilder<String>(context, entry, given);
          },
        ).pump(tester);
        expect(
          <(bool, bool)>{
            for (final built in details["late"]!)
              (built.continuesBefore, built.continuesAfter),
          },
          <(bool, bool)>{(false, true), (true, false)},
        );
      });

      testWidgets("OP8 in Day under the lock of earlier today at the second "
          "00:20, a tap on the 00:30 row, in the second pass, beside an "
          "entry whose block lies off that row, asks the policy about it and "
          "creates only where the policy lets a create of the slot share its "
          "time", (tester) async {
        final day = longDayStart;
        expectRepeatedMidnight(day);
        final shown = Shown.day(day);
        final slotStart = day.add(const Duration(minutes: 90));
        final slotEnd = day.add(const Duration(minutes: 105));
        for (final id in const <String>["tentative-f", "busy-f"]) {
          final policy = pairPolicy();
          final harness = Harness(
            storeOf(<CalendarEntry<String>>[
              entryOf(
                id,
                day.add(const Duration(minutes: 50)),
                day.add(const Duration(minutes: 95)),
              ),
            ]),
            shown,
            editPolicy: CalendarEditPolicy<String>.all(
              <CalendarEditPolicy<String>>[
                const HistoryLockPolicy<String>(lockEarlierToday: true),
                policy,
              ],
            ),
            today: day,
          );
          harness.now.value = CalendarNow(
            time: day.add(const Duration(minutes: 80)),
            today: day,
          );
          await harness.pump(tester);
          final row = slotRect(tester, shown, day, 30);
          // Setup sanity: the entry's block lies off the 00:30 row.
          expect(
            tester.getRect(blockFinder(id, day)).top,
            greaterThanOrEqualTo(row.bottom),
            reason: id,
          );
          await tester.tapAt(row.center);
          await tester.pumpAndSettle();
          expectSitePairs(policy);
          expect(
            policy.asked.where((ask) {
              return ask.other.id == id &&
                  ask.candidate.entry == null &&
                  ask.candidate.start == slotStart &&
                  ask.candidate.end == slotEnd;
            }),
            isNotEmpty,
            reason: id,
          );
          expect(harness.creates, <CalendarCreateRange>[
            if (id == "tentative-f")
              CalendarCreateRange(start: slotStart, end: slotEnd),
          ], reason: id);
        }
      });
    },
  );

  group(
    "on the day whose clock repeats its last hour",
    skip: repeatedLastHourSkip,
    () {
      testWidgets("OP14 in Day under a one-day limit and the lock of "
          "earlier today at the second 23:05, a create range from the 23:15 "
          "row to the 23:30 row passes an entry of the second pass where the "
          "policy lets the range to the 23:30 row share its time", (
        tester,
      ) async {
        final day = longDayStart;
        expectRepeatedLastHour(day);
        final hours = CalendarDayHours(8 * 60, 23 * 60 + 45);
        final shown = Shown.day(day, hours: hours);
        for (final id in const <String>["tentative-s", "busy-s"]) {
          final policy = pairPolicy();
          final harness = Harness(
            storeOf(<CalendarEntry<String>>[
              entryOf(
                id,
                laterLastHour.add(const Duration(minutes: 35)),
                laterLastHour.add(const Duration(minutes: 40)),
              ),
            ], hours: hours),
            shown,
            editPolicy:
                CalendarEditPolicy<String>.all(<CalendarEditPolicy<String>>[
                  const HistoryLockPolicy<String>(lockEarlierToday: true),
                  DayLimitPolicy<String>(1),
                  policy,
                ]),
            today: day,
          );
          harness.now.value = CalendarNow(
            time: laterLastHour.add(const Duration(minutes: 5)),
            today: day,
          );
          await harness.pump(tester);
          await createDrag(
            tester,
            slotRect(tester, shown, day, 23 * 60 + 15).center,
            slotRect(tester, shown, day, 23 * 60 + 30).center,
          );
          expectSitePairs(policy);
          expect(
            policy.asked.where((ask) {
              return ask.other.id == id &&
                  ask.candidate.entry == null &&
                  ask.candidate.start ==
                      laterLastHour.add(const Duration(minutes: 15)) &&
                  ask.candidate.end ==
                      laterLastHour.add(const Duration(minutes: 45));
            }),
            isNotEmpty,
            reason: id,
          );
          expect(harness.creates, <CalendarCreateRange>[
            CalendarCreateRange(
              start: laterLastHour.add(const Duration(minutes: 15)),
              end: laterLastHour.add(
                Duration(minutes: id == "tentative-s" ? 45 : 30),
              ),
            ),
          ], reason: id);
        }
      });

      testWidgets("OP15 in Day a create range from the 23:45 row up to the "
          "22:00 row passes an entry of the second pass where the policy "
          "lets the create share its time, and where it does not is held at "
          "the 23:00 row", (tester) async {
        final day = longDayStart;
        expectRepeatedLastHour(day);
        final shown = Shown.day(day);
        for (final id in const <String>["tentative-x", "busy-x"]) {
          final policy = pairPolicy();
          final harness = Harness(
            storeOf(<CalendarEntry<String>>[
              entryOf(
                id,
                laterLastHour.add(const Duration(minutes: 15)),
                laterLastHour.add(const Duration(minutes: 30)),
              ),
            ]),
            shown,
            editPolicy: policy,
          );
          await harness.pump(tester);
          await createDrag(
            tester,
            slotRect(tester, shown, day, 23 * 60 + 45).center,
            slotRect(tester, shown, day, 22 * 60).center,
          );
          expectSitePairs(policy);
          expect(askedIds(policy), contains(id), reason: id);
          expect(harness.creates, <CalendarCreateRange>[
            if (id == "tentative-x")
              CalendarCreateRange(
                start: at(day, 22),
                end: CalendarDates.addDays(day, 1),
              )
            else
              CalendarCreateRange(
                start: day.add(const Duration(hours: 23)),
                end: laterLastHour,
              ),
          ], reason: id);
        }
      });

      testWidgets("OP16 in Week under the lock of earlier today at the "
          "second 23:05, a create range from the next day's 10:00 row back to "
          "the day's 23:15 row runs from the second pass, so it passes an "
          "entry of the first pass whatever the policy answers, asking "
          "nothing about it", (tester) async {
        final day = longDayStart;
        expectRepeatedLastHour(day);
        final hours = CalendarDayHours(8 * 60, 23 * 60 + 45);
        final shown = Shown.week(day, hours: hours);
        final next = CalendarDates.addDays(day, 1);
        for (final id in const <String>["tentative-x", "busy-x"]) {
          final policy = pairPolicy();
          final harness = Harness(
            storeOf(<CalendarEntry<String>>[
              entryOf(
                id,
                day.add(const Duration(hours: 23, minutes: 20)),
                day.add(const Duration(hours: 23, minutes: 40)),
              ),
            ], hours: hours),
            shown,
            editPolicy: CalendarEditPolicy<String>.all(
              <CalendarEditPolicy<String>>[
                const HistoryLockPolicy<String>(lockEarlierToday: true),
                policy,
              ],
            ),
            today: day,
          );
          harness.now.value = CalendarNow(
            time: laterLastHour.add(const Duration(minutes: 5)),
            today: day,
          );
          await harness.pump(tester);
          await createDrag(
            tester,
            slotRect(tester, shown, next, 10 * 60).center,
            slotRect(tester, shown, day, 23 * 60 + 15).center,
          );
          expect(askedIds(policy), isEmpty, reason: id);
          expect(harness.creates, <CalendarCreateRange>[
            CalendarCreateRange(
              start: laterLastHour.add(const Duration(minutes: 15)),
              end: at(next, 10, 15),
            ),
          ], reason: id);
        }
      });
    },
  );
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
      if (NoOverlapsPolicy.rangeSharesTime(move.start, move.end, other)) move,
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

/// A [PairRecordingPolicy] of [tentativePair], whose answer on overlaps is
/// [overlaps].
PairRecordingPolicy<String> pairPolicy({bool overlaps = false}) {
  return PairRecordingPolicy<String>(allows: tentativePair, overlaps: overlaps);
}

/// A [PairRecordingPolicy] that refuses "long" only for a candidate longer
/// than a 15-minute slot, and allows every other pair.
PairRecordingPolicy<String> longPolicy() {
  return PairRecordingPolicy<String>(
    allows: (candidate, other) {
      return other.id != "long" ||
          candidate.end.difference(candidate.start) <=
              const Duration(minutes: 15);
    },
  );
}

/// What [SwitchedOverlapsPolicy.allowsOverlaps] answers, which a test sets
/// to stand for a reload that changes what the getter answers.
bool switchedOverlaps = false;

/// Refuses every pair it is asked about, recording each candidate in
/// [asked], and answers [allowsOverlaps] with [switchedOverlaps].
final class SwitchedOverlapsPolicy extends CalendarEditPolicy<String> {
  final List<CalendarOverlapCandidate<String>> asked =
      <CalendarOverlapCandidate<String>>[];

  @override
  bool get allowsOverlaps {
    return switchedOverlaps;
  }

  @override
  bool mayOverlap(
    CalendarOverlapCandidate<String> candidate,
    CalendarEntry<String> other,
  ) {
    asked.add(candidate);
    return false;
  }
}

/// Checks that [policy] asked about each timed entry of [entries] that
/// shares [range]'s time with a candidate of [range]'s start and end and
/// no entry.
void expectRangeAsked(
  PairRecordingPolicy<String> policy,
  List<CalendarEntry<String>> entries,
  CalendarCreateRange range,
) {
  for (final entry in entries) {
    if (entry.isAllDay ||
        !NoOverlapsPolicy.rangeSharesTime(range.start, range.end, entry)) {
      continue;
    }
    expect(
      policy.asked.any((ask) {
        return ask.other.id == entry.id &&
            ask.candidate.entry == null &&
            ask.candidate.start == range.start &&
            ask.candidate.end == range.end;
      }),
      isTrue,
      reason: "${entry.id} with ${range.start} to ${range.end}",
    );
  }
}

/// Moves [gesture]'s pointer, which lies at [point], 1 px up or down
/// inside the board cell under [point], a frame after it, and checks that
/// the move asked [policy] nothing and built no candidate
/// ([debugOverlapCandidateCount]), [reason] naming the case.
Future<void> expectNothingAskedInsideCell(
  WidgetTester tester,
  TestGesture gesture,
  Offset point,
  PairRecordingPolicy<String> policy, {
  required String reason,
}) async {
  final controller = boardOf(tester).controller;
  final cell = controller.cellAt(point);
  // Setup sanity: a cell lies under the pointer, and the move stays in it.
  expect(cell, isNotNull, reason: reason);
  final nudge = controller.cellAt(point + const Offset(0.0, 1.0)) == cell
      ? const Offset(0.0, 1.0)
      : const Offset(0.0, -1.0);
  final asked = policy.asked.length;
  final built = debugOverlapCandidateCount;
  await gesture.moveTo(point + nudge);
  await tester.pump();
  expect(controller.cellAt(point + nudge), cell, reason: reason);
  expect(
    policy.asked.length,
    asked,
    reason: "$reason: a move inside $cell asked",
  );
  expect(
    debugOverlapCandidateCount,
    built,
    reason: "$reason: a move inside $cell built a candidate",
  );
}

/// The ids of the other entries [policy] was asked about, in order.
List<String> askedIds(PairRecordingPolicy<String> policy) {
  return <String>[for (final ask in policy.asked) ask.other.id!];
}

/// Whether [policy] was asked about the entry [id] and refused it.
bool refusedAsk(PairRecordingPolicy<String> policy, String id) {
  return policy.asked.any((ask) {
    return ask.other.id == id && !policy.allows(ask.candidate, ask.other);
  });
}

/// Checks each pair [policy] recorded: its other entry shares time with
/// its candidate and is not the entry the candidate changes; and where
/// [changed] is given, a pair's candidate carries that entry, as the
/// asks of the gesture changing it do. The blocks' semantic move actions
/// ask the drop gate too ([BoardDragConfig.canDropAt]), with candidates
/// carrying their own entries.
void expectSitePairs(PairRecordingPolicy<String> policy, {String? changed}) {
  for (final ask in policy.asked) {
    final reason = "${ask.candidate}, ${ask.other.id}";
    expect(
      NoOverlapsPolicy.rangeSharesTime(
        ask.candidate.start,
        ask.candidate.end,
        ask.other,
      ),
      isTrue,
      reason: reason,
    );
    final entry = ask.candidate.entry;
    if (entry != null) {
      expect(ask.other.id, isNot(entry.id), reason: reason);
    }
  }
  if (changed != null) {
    expect(
      policy.asked.where((ask) {
        return ask.candidate.entry?.id == changed;
      }),
      isNotEmpty,
      reason: changed,
    );
  }
}

/// Selects the block of [id] on [day] with a long press let go in place,
/// presses its end edge, or with [start] its start edge, 2 px inside it,
/// drags that edge onto the minute [minute] of [day] in two steps, a frame
/// after each, lets go and lets the drop settle.
Future<void> resizeTo(
  WidgetTester tester,
  Shown shown,
  String id,
  DateTime day,
  int minute, {
  bool start = false,
}) async {
  final selecting = await lift(tester, tester.getCenter(blockFinder(id, day)));
  await selecting.up();
  await tester.pumpAndSettle();
  final block = tester.getRect(blockFinder(id, day));
  final from = start
      ? Offset(block.center.dx, block.top + 2.0)
      : Offset(block.center.dx, block.bottom - 2.0);
  final to = start
      ? Offset(from.dx, slotRect(tester, shown, day, minute).top + 2.0)
      : Offset(
          from.dx,
          slotRect(tester, shown, day, minute - shown.slotMinutes).bottom - 2.0,
        );
  final gesture = await tester.startGesture(from);
  await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// PG4's store: [count] five-minute entries packed from Tuesday's start,
/// "free" on Tuesday from 18:00 to 19:00, and the bar "bar" on Monday.
MoveRecordingStore packedStore(int count) {
  return storeOf(<CalendarEntry<String>>[
    for (var i = 0; i < count; i++)
      entryOf("p$i", at(tuesday, 0, 5 * i), at(tuesday, 0, 5 * i + 5)),
    entryOf("free", at(tuesday, 18), at(tuesday, 19)),
    allDayOf("bar", monday),
  ]);
}

/// PG4's gestures in Week from Monday over [packedStore]'s entries, by
/// name: "free" moved toward Tuesday's 02:00 slot, its start edge dragged
/// up toward 02:00 and its end edge into Thursday's 12:00 slot, each
/// resize selecting it first, and "bar" dropped on Tuesday's 10:00 slot;
/// each in ten pointer moves a frame apart, then let go and settled.
Map<String, Future<void> Function()> packedGestures(
  WidgetTester tester,
  Shown shown,
) {
  Future<void> tenMoves(TestGesture gesture, Offset from, Offset to) async {
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump();
    }
  }

  Future<void> selectFree() async {
    final selecting = await lift(
      tester,
      tester.getCenter(blockFinder("free", tuesday)),
    );
    await selecting.up();
    await tester.pumpAndSettle();
  }

  return <String, Future<void> Function()>{
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
      await selectFree();
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
      await selectFree();
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
}

/// A mouse press on Tuesday's 17:00 slot, below [packedStore]'s packed
/// entries, moved to the 16:45 slot, which begins the range, then dragged
/// up toward the 12:00 slot in ten pointer moves, a frame after each move,
/// let go and settled; [begun] runs after the range begins, [moved] after
/// each of the ten moves' frames, and [held] after the ten moves, before
/// the release.
Future<void> packedCreateDrag(
  WidgetTester tester,
  Shown shown, {
  void Function()? begun,
  void Function()? moved,
  void Function()? held,
}) async {
  final from = slotRect(tester, shown, tuesday, 17 * 60).center;
  final start = slotRect(tester, shown, tuesday, 16 * 60 + 45).center;
  final to = slotRect(tester, shown, tuesday, 12 * 60).center;
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(start);
  await tester.pump();
  begun?.call();
  for (var i = 1; i <= 10; i++) {
    await gesture.moveTo(Offset.lerp(start, to, i / 10)!);
    await tester.pump();
    moved?.call();
  }
  held?.call();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// What a throwing per-pair answer throws in OP11.
class PairFailure implements Exception {
  const PairFailure();
}
