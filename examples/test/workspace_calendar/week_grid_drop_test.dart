/// What a drop on the week grid writes: the resize strips, Share, the day
/// count of an item the week clips, and a drop that changes nothing.
library;

import 'package:examples/workspace_calendar/calendar_data.dart';
import 'package:examples/workspace_calendar/calendar_item.dart';
import 'package:examples/workspace_calendar/calendar_model.dart';
import 'package:examples/workspace_calendar/calendar_schema.dart';
import 'package:examples/workspace_calendar/mock_calendar_api.dart';
import 'package:examples/workspace_calendar/week_grid.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

final DateTime today = DateTime(2026, 4, 21);
final DateTime monday = DateTime(2026, 4, 20);

const Duration latency = Duration(milliseconds: 100);

/// The seed's ids follow its order.
const String uxFlow = "item-1";
const String brainstorm = "item-2";
const String standup = "item-3";
const String review = "item-4";
const String fromFriday = "item-5";
const String fromSaturday = "item-6";
const String yearLong = "item-7";

Map<String, Object?> taskJson(
  String title,
  DateTime day,
  int start,
  int end, {
  int dayCount = 1,
}) {
  return <String, Object?>{
    "type": CalendarItemType.task.id,
    "title": title,
    "day": isoDate(day),
    "startMinute": start,
    "endMinute": end,
    "dayCount": dayCount,
    "fields": const <String, Object?>{"status": "toDo"},
  };
}

List<Map<String, Object?>> seed() {
  return <Map<String, Object?>>[
    taskJson("Design new UX flow for Michael", today, 600, 780),
    taskJson("Brainstorm with the team", today, 840, 900),
    taskJson("Daily standup", DateTime(2026, 4, 22), 570, 600),
    taskJson("Review onboarding copy", DateTime(2026, 4, 22), 660, 720),
    // Friday to Monday: the week shows its Monday alone.
    taskJson("Handover", DateTime(2026, 4, 17), 1080, 1140, dayCount: 4),
    // Saturday to Monday: the week shows its Saturday and Sunday.
    taskJson("Retreat", DateTime(2026, 4, 25), 1140, 1200, dayCount: 3),
    // 366 days, the most an item may cover, ending on the week's Monday.
    taskJson("Year plan", DateTime(2025, 4, 20), 1200, 1260, dayCount: 366),
  ];
}

class Harness {
  Harness(this.api, this.model);

  final MockCalendarApi api;
  final CalendarModel model;
}

/// Reads April's grid and mounts the grid on the week of [monday], tall
/// enough that every row from 08:00 to 24:00 shows.
Future<Harness> pumpGrid(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(390.0, 1400.0);
  addTearDown(tester.view.reset);
  final api = MockCalendarApi(seed: seed(), latency: latency);
  final model = CalendarModel(api: api, onWriteFailed: (message) {});
  model.show(DateTime(2026, 3, 30), DateTime(2026, 5, 3));
  await tester.pump(latency);
  model.show(monday, addDays(monday, 6));
  await tester.pumpWidget(
    MaterialApp(
      // The M3 ink sparkle shader cannot load under the test binding.
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: WeekGrid(
          model: model,
          weekStart: monday,
          selectedDay: today,
          today: today,
          onSelectDay: (day) {},
          onOpenItem: (id) {},
          onCreate: (range) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return Harness(api, model);
}

RenderBoardViewport<String> weekViewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

Finder block(String id) {
  return find.byKey(blockKey(id));
}

/// The global rect of the cell at [row] and [col].
Rect cellRect(WidgetTester tester, int row, int col) {
  final viewport = weekViewport(tester);
  final rect = viewport.rectOfCell(row, col)!;
  return viewport.localToGlobal(rect.topLeft) & rect.size;
}

double dayWidth(WidgetTester tester) {
  return cellRect(tester, 1, 1).width;
}

/// The item [id] as the API holds it, read with a `get` that the test
/// pumps through.
Future<CalendarItem> stored(
  WidgetTester tester,
  Harness harness,
  String id,
) async {
  final answer = harness.api.get(id);
  await tester.pump(latency);
  return CalendarItem.fromJson(await answer);
}

/// Drags a strip of [id]'s block with a mouse, which the grid's scrollable
/// never takes, by [delta], then lets the write it causes complete.
Future<void> dragStrip(
  WidgetTester tester,
  String id,
  Offset Function(Rect rect) press,
  Offset delta,
) async {
  final rect = tester.getRect(block(id));
  final gesture = await tester.startGesture(
    press(rect),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(delta);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
  await tester.pump(latency);
  await tester.pumpAndSettle();
}

Offset rightStrip(Rect rect) {
  return Offset(rect.right - 3.0, rect.center.dy);
}

Offset bottomStrip(Rect rect) {
  return Offset(rect.center.dx, rect.bottom - 3.0);
}

/// Long-presses [id]'s block and drops it so its top-left corner moves by
/// [delta], then lets the write it causes complete.
Future<void> moveBlock(WidgetTester tester, String id, Offset delta) async {
  final rect = tester.getRect(block(id));
  final gesture = await tester.startGesture(rect.center);
  await tester.pump(kLongPressTimeout + kPressTimeout);
  if (delta != Offset.zero) {
    await gesture.moveBy(delta);
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
  await tester.pump(latency);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("the drag config resizes trailing edges alone", (tester) async {
    await pumpGrid(tester);
    final board = tester.widget<Board<String, ShownItem>>(
      find.byType(Board<String, ShownItem>),
    );
    expect(board.drag!.resizeEdges, BoardResizeEdges.trailing);
    expect(board.drag!.primaryResizeEdges, BoardResizeEdges.trailing);
  });

  testWidgets("the bottom strip moves the end by whole slots", (tester) async {
    final harness = await pumpGrid(tester);
    await dragStrip(
      tester,
      brainstorm,
      bottomStrip,
      const Offset(0.0, 2 * 16.0),
    );
    final item = await stored(tester, harness, brainstorm);
    expect(item.day, today);
    expect(item.dayCount, 1);
    expect(item.startMinute, 840);
    expect(item.endMinute, 930);
  });

  testWidgets("a right strip that would make an item cover a single-day "
      "item's time is refused", (tester) async {
    final harness = await pumpGrid(tester);
    final before = tester.getRect(block(uxFlow));
    final requests = harness.api.requests.length;
    await dragStrip(
      tester,
      uxFlow,
      rightStrip,
      Offset(dayWidth(tester), 0.0),
    );
    expect(harness.api.requests, hasLength(requests));
    expect(tester.getRect(block(uxFlow)), before);
  });

  testWidgets("a single-day item moved beside another shares the day", (
    tester,
  ) async {
    final harness = await pumpGrid(tester);
    final width = dayWidth(tester);
    expect(
      tester.getSize(block(review)).width,
      moreOrLessEquals(width),
      reason: "alone in its time before the move",
    );
    final target = cellRect(tester, 1 + 660 ~/ 15, 3).topLeft;
    await moveBlock(
      tester,
      brainstorm,
      target - tester.getRect(block(brainstorm)).topLeft,
    );
    final item = await stored(tester, harness, brainstorm);
    expect(item.day, DateTime(2026, 4, 22));
    expect(item.startMinute, 660);
    expect(tester.getSize(block(brainstorm)).width, lessThan(width - 1.0));
    expect(tester.getSize(block(review)).width, lessThan(width - 1.0));
  });

  testWidgets("the right strip of an item that ends after the week ends it "
      "on the column it is dropped on", (tester) async {
    final harness = await pumpGrid(tester);
    final rect = tester.getRect(block(fromSaturday));
    expect(
      rect.left,
      moreOrLessEquals(cellRect(tester, 1, 6).left, epsilon: 2.0),
      reason: "shown from Saturday",
    );
    expect(rect.width, greaterThan(dayWidth(tester) * 1.5));
    await dragStrip(
      tester,
      fromSaturday,
      rightStrip,
      Offset(-dayWidth(tester), 0.0),
    );
    final item = await stored(tester, harness, fromSaturday);
    expect(item.day, DateTime(2026, 4, 25));
    expect(item.dayCount, 1);
  });

  testWidgets("the right strip of an item that starts before the week keeps "
      "its first day", (tester) async {
    final harness = await pumpGrid(tester);
    final rect = tester.getRect(block(fromFriday));
    expect(
      rect.left,
      moreOrLessEquals(cellRect(tester, 1, 1).left, epsilon: 2.0),
      reason: "shown on Monday alone",
    );
    await dragStrip(
      tester,
      fromFriday,
      rightStrip,
      Offset(6 * dayWidth(tester), 0.0),
    );
    final item = await stored(tester, harness, fromFriday);
    expect(item.day, DateTime(2026, 4, 17));
    expect(item.dayCount, 10);
  });

  testWidgets("a right strip past the longest item is refused", (
    tester,
  ) async {
    final harness = await pumpGrid(tester);
    final before = tester.getRect(block(yearLong));
    final requests = harness.api.requests.length;
    await dragStrip(
      tester,
      yearLong,
      rightStrip,
      Offset(dayWidth(tester), 0.0),
    );
    expect(harness.api.requests, hasLength(requests));
    expect(tester.getRect(block(yearLong)), before);
    expect(harness.model.storedItem(yearLong)!.dayCount, maxDayCount);
  });

  testWidgets("a block lifted and released in place sends nothing", (
    tester,
  ) async {
    final harness = await pumpGrid(tester);
    final requests = harness.api.requests.length;
    await moveBlock(tester, brainstorm, Offset.zero);
    expect(harness.api.requests, hasLength(requests));
  });
}
