/// Helpers the calendar's widget tests share: the fixed day, the host the
/// calendar is pumped in, the timed grid's viewport, a block move, a read
/// of the mock, and a canvas that records what a painter draws.
library;

import 'dart:ui' as ui;

import 'package:workspace_calendar/workspace_calendar/calendar_data.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';
import 'package:workspace_calendar/workspace_calendar_example.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

/// A Tuesday. April 2026 starts on a Wednesday and has 30 days, so its
/// Monday-first grid runs from March 30 to May 3 in five weeks.
final DateTime today = DateTime(2026, 4, 21);

/// The latency of the mock [pumpCalendar] builds when given none.
const Duration harnessLatency = Duration(milliseconds: 100);

// The ids of the seed around [today]: `defaultCalendarSeed` lists the kept
// tasks first, then the week's meetings and deadlines, then "Day off" and
// "Conference trip", and the mock numbers them in that order.
const String uxFlowId = "item-5";
const String brainstormId = "item-6";
const String standupId = "item-7";
const String reviewId = "item-8";
const String retroPrepId = "item-17";
const String clientPresentationId = "item-18";
const String teamOffsiteId = "item-20";
const String releasePlanningId = "item-21";
const String designSystemSyncId = "item-22";
const String designCritiqueId = "item-25";
const String dayOffId = "item-28";

/// The Monday of [today]'s week.
final DateTime monday = DateTime(2026, 4, 20);

/// The timed grid's row of [minute]: row 0 is the day header.
int rowOf(int minute) {
  return 1 + minute ~/ 15;
}

/// The week grid's column of the day [weekday] days after [monday]:
/// column 0 is the hour gutter.
int colOf(int weekday) {
  return 1 + weekday;
}

Finder blockFinder(String id) {
  return find.byKey(blockKey(id));
}

/// The global rect of the timed grid's cell at [row] and [col].
Rect cellRect(WidgetTester tester, int row, int col) {
  final viewport = gridViewport(tester);
  final rect = viewport.rectOfCell(row, col)!;
  return viewport.localToGlobal(rect.topLeft) & rect.size;
}

/// Opens the calendar's mode menu and picks [mode], "Month" or "Week".
Future<void> pickMode(WidgetTester tester, String mode) async {
  await tester.tap(find.byTooltip("Calendar view"));
  await tester.pumpAndSettle();
  await tester.tap(find.text(mode).last);
  await tester.pumpAndSettle();
}

/// Stores [item] through [api] before the calendar is pumped, and pumps
/// the latency it answers after.
Future<void> createBeforePump(
  WidgetTester tester,
  MockCalendarApi api,
  Map<String, Object?> item,
) async {
  api.create(item);
  await tester.pump(api.latency);
}

/// A Task envelope with status to do.
Map<String, Object?> taskJson(
  String title,
  DateTime day,
  int start,
  int end, {
  int dayCount = 1,
}) {
  return <String, Object?>{
    "type": "task",
    "title": title,
    "day": isoDate(day),
    "startMinute": start,
    "endMinute": end,
    "dayCount": dayCount,
    "fields": <String, Object?>{"status": "toDo"},
  };
}

/// The app [pumpCalendar] pumps: the calendar over [api], given [today]
/// and [clock].
Widget calendarApp({
  required MockCalendarApi api,
  DateTime? today,
  DateTime Function()? clock,
}) {
  return MaterialApp(
    // The M3 ink sparkle shader cannot load under the test binding.
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: WorkspaceCalendarExample(today: today, api: api, clock: clock),
  );
}

/// Pumps the calendar on [today] over [api], by default a mock seeded
/// around [today] at [harnessLatency] with no failure policy, at [size],
/// reading the time from [clock], by default the real clock, and lets its
/// first read complete. Returns the mock. With [pinsToday] false the
/// calendar is given no day, so it opens on the day [clock] reads and
/// marks that day as today.
Future<MockCalendarApi> pumpCalendar(
  WidgetTester tester, {
  MockCalendarApi? api,
  Size size = const Size(390.0, 844.0),
  DateTime Function()? clock,
  bool pinsToday = true,
}) async {
  final mock = api ?? MockCalendarApi.seeded(today, latency: harnessLatency);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    calendarApp(api: mock, today: pinsToday ? today : null, clock: clock),
  );
  await tester.pump(mock.latency);
  await tester.pumpAndSettle();
  return mock;
}

/// The timed grid's viewport: the one board keyed by item id strings.
RenderBoardViewport<String> gridViewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

/// Long-presses [block] and drops it so its top-left corner lands on
/// [target], then pumps the frame that starts the drop-settle glide and
/// the glide itself, which ends before any mock answer a test sets at
/// 1 s or more.
Future<void> moveBlock(WidgetTester tester, Finder block, Offset target) async {
  final rect = tester.getRect(block);
  final gesture = await tester.startGesture(rect.center);
  await tester.pump(kLongPressTimeout + kPressTimeout);
  await gesture.moveBy(target - rect.topLeft);
  await tester.pump();
  await gesture.up();
  await tester.pump();
  await tester.pump(timedGridAnimationStyle.effectiveDropSettle.duration);
}

/// What [api]'s `list` returns for [first] to [last], pumped through its
/// latency.
Future<List<Map<String, Object?>>> listAll(
  WidgetTester tester,
  MockCalendarApi api,
  DateTime first,
  DateTime last,
) async {
  List<Map<String, Object?>>? items;
  api.list(first, last).then((result) {
    items = result;
  });
  await tester.pump(api.latency);
  return items!;
}

/// One draw call a [RecordingCanvas] received: a rect, or a line from
/// [from] to [to], and the paint it was drawn with.
class CanvasRecord {
  CanvasRecord.rect(Rect this.rect, this.paint) : from = null, to = null;

  CanvasRecord.line(Offset this.from, Offset this.to, this.paint) : rect = null;

  final Rect? rect;
  final Offset? from;
  final Offset? to;
  final Paint paint;

  bool get isLine {
    return from != null;
  }

  Color get color {
    return paint.color;
  }

  /// Whether the record was drawn in [other]. Compared as 32-bit ARGB: a
  /// [Paint] hands its colour back from its own storage, which need not
  /// compare equal to the [Color] it was given.
  bool isIn(Color other) {
    return paint.color.toARGB32() == other.toARGB32();
  }

  bool get isFill {
    return paint.style == PaintingStyle.fill;
  }
}

/// A canvas that records the rects and lines drawn on it, each with its
/// paint, in the coordinates they were drawn in. Every other call is
/// ignored.
class RecordingCanvas implements Canvas {
  final List<CanvasRecord> records = <CanvasRecord>[];

  /// The filled rects drawn in [color].
  Iterable<Rect> fillsOf(Color color) {
    return <Rect>[
      for (final record in records)
        if (!record.isLine && record.isFill && record.isIn(color)) record.rect!,
    ];
  }

  Iterable<CanvasRecord> get lines {
    return records.where((record) {
      return record.isLine;
    });
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    records.add(CanvasRecord.rect(rect, paint));
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    records.add(CanvasRecord.line(p1, p2, paint));
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

/// Paints the timed grid's background onto a new [RecordingCanvas], with
/// the viewport as the geometry.
RecordingCanvas paintGridBackground(WidgetTester tester) {
  final viewport = gridViewport(tester);
  final canvas = RecordingCanvas();
  viewport.background!.paint(canvas, viewport);
  return canvas;
}
