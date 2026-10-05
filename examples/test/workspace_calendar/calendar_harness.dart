/// Helpers the calendar's widget tests share: the fixed day, the host the
/// calendar is pumped in, the week grid's viewport, a block move, a read
/// of the mock, and a canvas that records what a painter draws.
library;

import 'dart:ui' as ui;

import 'package:examples/workspace_calendar/mock_calendar_api.dart';
import 'package:examples/workspace_calendar/week_grid.dart';
import 'package:examples/workspace_calendar_example.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

/// A Tuesday. April 2026 starts on a Wednesday and has 30 days, so its
/// Monday-first grid runs from March 30 to May 3 in five weeks.
final DateTime today = DateTime(2026, 4, 21);

/// The latency of the mock [pumpCalendar] builds when given none.
const Duration harnessLatency = Duration(milliseconds: 100);

/// Pumps the calendar on [today] over [api], by default a mock seeded
/// around [today] at [harnessLatency] with no failure policy, at [size],
/// and lets its first read complete. Returns the mock.
Future<MockCalendarApi> pumpCalendar(
  WidgetTester tester, {
  MockCalendarApi? api,
  Size size = const Size(390.0, 844.0),
}) async {
  final mock = api ?? MockCalendarApi.seeded(today, latency: harnessLatency);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      // The M3 ink sparkle shader cannot load under the test binding.
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: WorkspaceCalendarExample(today: today, api: mock),
    ),
  );
  await tester.pump(mock.latency);
  await tester.pumpAndSettle();
  return mock;
}

/// The week grid's viewport: the one board keyed by item id strings.
RenderBoardViewport<String> weekViewport(WidgetTester tester) {
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
  await tester.pump(weekGridAnimationStyle.effectiveDropSettle.duration);
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
        if (!record.isLine && record.isFill && record.color == color)
          record.rect!,
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

/// Paints the week grid's background onto a new [RecordingCanvas], with
/// the viewport as the geometry.
RecordingCanvas paintWeekBackground(WidgetTester tester) {
  final viewport = weekViewport(tester);
  final canvas = RecordingCanvas();
  viewport.background!.paint(canvas, viewport);
  return canvas;
}
