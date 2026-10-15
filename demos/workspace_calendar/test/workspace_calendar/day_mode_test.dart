/// The calendar's Day mode: the timed grid over the selected day alone,
/// its steps, its gestures, its reads and its painter.
library;

import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/day_cell.dart';
import 'package:workspace_calendar/workspace_calendar/day_list.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_harness.dart';

/// A size tall enough that every row from 08:00 to 24:00 shows once the
/// grid has jumped to 08:00.
const Size tall = Size(390.0, 1400.0);

/// The one day column.
const int dayColumn = 1;

/// Layout rounds track offsets, so geometry is compared to half a pixel.
Matcher near(double value) {
  return moreOrLessEquals(value, epsilon: 0.5);
}

Matcher nearOffset(Offset value) {
  return offsetMoreOrLessEquals(value, epsilon: 0.5);
}

Finder headerFinder(DateTime day) {
  return find.byKey(dayHeaderKey(day));
}

Color headerFill(WidgetTester tester, DateTime day) {
  return tester
      .widget<ColoredBox>(
        find
            .descendant(
              of: headerFinder(day),
              matching: find.byType(ColoredBox),
            )
            .first,
      )
      .color;
}

Offset centerOf(WidgetTester tester, int row) {
  return cellRect(tester, row, dayColumn).center;
}

Finder dropdownFinder(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) {
      return widget is DropdownButtonFormField;
    }),
  );
}

String fieldText(WidgetTester tester, String label) {
  return tester
      .widget<TextField>(find.widgetWithText(TextField, label))
      .controller!
      .text;
}

/// Expects the create flow's picker, picks [type], and expects its form
/// prefilled with [day], [start] to [end] and one day; then cancels it.
Future<void> expectCreateForm(
  WidgetTester tester, {
  required String type,
  required String day,
  required String start,
  required String end,
}) async {
  expect(find.text("New item"), findsOneWidget);
  await tester.tap(find.text(type).last);
  await tester.pumpAndSettle();
  expect(find.text(day), findsOneWidget);
  expect(
    find.descendant(of: dropdownFinder("Start"), matching: find.text(start)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: dropdownFinder("End"), matching: find.text(end)),
    findsOneWidget,
  );
  expect(fieldText(tester, "Days"), "1");
  await tester.tap(find.widgetWithText(TextButton, "Cancel"));
  await tester.pumpAndSettle();
}

/// The item [id] as [api] holds it, through a `get` pumped past its
/// latency.
Future<CalendarItem> stored(
  WidgetTester tester,
  MockCalendarApi api,
  String id,
) async {
  Map<String, Object?>? json;
  api.get(id).then((value) {
    json = value;
  });
  await tester.pump(api.latency);
  return CalendarItem.fromJson(json!);
}

int listCalls(MockCalendarApi api) {
  return api.requests.where((request) {
    return request.method == CalendarMethod.list;
  }).length;
}

Future<void> step(WidgetTester tester, String tooltip, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets("D1 Day mode shows the selected day's timed grid", (
    tester,
  ) async {
    // The default phone size, which scrolls far enough to show 08:00 at
    // the top.
    final api = await pumpCalendar(tester);
    final requests = api.requests.length;
    await pickMode(tester, "Day");

    expect(find.text("Day"), findsOneWidget);
    expect(headerFinder(today), findsOneWidget);
    expect(headerFinder(DateTime(2026, 4, 20)), findsNothing);
    expect(headerFinder(DateTime(2026, 4, 22)), findsNothing);
    expect(find.byType(DayCell), findsNothing);
    expect(find.byType(DayList), findsNothing);
    expect(find.byTooltip("Add"), findsNothing);
    expect(find.byTooltip("Add item"), findsNothing);
    expect(find.byTooltip("Previous day"), findsOneWidget);
    expect(find.byTooltip("Next day"), findsOneWidget);

    final grid = gridViewport(tester);
    expect(
      grid.rectOfCell(rowOf(8 * 60), dayColumn)!.top,
      near(grid.scrolledRegion.top),
    );
    // One day column, from the gutter to the body's right edge.
    expect(cellRect(tester, rowOf(9 * 60), dayColumn).right, near(390.0));
    expect(grid.rectOfCell(rowOf(9 * 60), dayColumn + 1), isNull);

    final todays = <(String, int, int)>[
      (uxFlowId, 10 * 60, 13 * 60),
      (brainstormId, 14 * 60, 15 * 60),
    ];
    for (final (id, start, end) in todays) {
      final first = cellRect(tester, rowOf(start), dayColumn);
      final last = cellRect(tester, rowOf(end) - 1, dayColumn);
      final rect = tester.getRect(blockFinder(id));
      expect(rect.topLeft, nearOffset(first.topLeft), reason: id);
      expect(rect.bottomRight, nearOffset(last.bottomRight), reason: id);
    }
    expect(blockFinder(standupId), findsNothing);
    expect(api.requests, hasLength(requests));

    await step(tester, "Next day");
    expect(headerFinder(DateTime(2026, 4, 22)), findsOneWidget);
    expect(headerFinder(today), findsNothing);
    expect(blockFinder(standupId), findsOneWidget);
    expect(blockFinder(reviewId), findsOneWidget);
    expect(blockFinder(uxFlowId), findsNothing);

    await step(tester, "Previous day");
    expect(headerFinder(today), findsOneWidget);
    expect(blockFinder(uxFlowId), findsOneWidget);
    expect(blockFinder(standupId), findsNothing);
  });

  testWidgets("D2 a tap and a range drag create on the shown day", (
    tester,
  ) async {
    await pumpCalendar(tester, size: tall);
    await pickMode(tester, "Day");

    await tester.tapAt(centerOf(tester, rowOf(16 * 60)));
    await tester.pumpAndSettle();
    await expectCreateForm(
      tester,
      type: "Meeting",
      day: "2026-04-21",
      start: "16:00",
      end: "17:00",
    );

    // A mouse drags at once, the whole move in one event.
    final gesture = await tester.startGesture(
      centerOf(tester, rowOf(18 * 60)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(centerOf(tester, rowOf(18 * 60 + 45)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await expectCreateForm(
      tester,
      type: "Task",
      day: "2026-04-21",
      start: "18:00",
      end: "19:00",
    );
  });

  testWidgets("D3 a move and the bottom strip change the hours, not the days", (
    tester,
  ) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    await createBeforePump(
      tester,
      api,
      taskJson("Retreat", DateTime(2026, 4, 20), 19 * 60, 20 * 60, dayCount: 3),
    );
    final retreat =
        (await listAll(
              tester,
              api,
              today,
              today,
            )).singleWhere((item) => item["title"] == "Retreat")["id"]!
            as String;
    await pumpCalendar(tester, api: api, size: tall);
    await pickMode(tester, "Day");

    // The three-day item shows its one day here.
    final column = cellRect(tester, rowOf(19 * 60), dayColumn);
    final block = tester.getRect(blockFinder(retreat));
    expect(block.left, near(column.left));
    expect(block.right, near(column.right));

    final board = tester.widget<Board<String, ShownItem>>(
      find.byType(Board<String, ShownItem>),
    );
    expect(board.drag!.resizeEdges, BoardResizeEdges.none);
    expect(board.drag!.primaryResizeEdges, BoardResizeEdges.trailing);

    // A long press moves the block four rows down.
    await moveBlock(
      tester,
      blockFinder(brainstormId),
      cellRect(tester, rowOf(15 * 60), dayColumn).topLeft,
    );
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    var item = await stored(tester, api, brainstormId);
    expect(item.day, today);
    expect(item.dayCount, 1);
    expect(item.startMinute, 15 * 60);
    expect(item.endMinute, 16 * 60);

    // The bottom strip drags the end, with a mouse.
    final rect = tester.getRect(blockFinder(brainstormId));
    final slot = cellRect(tester, rowOf(9 * 60), dayColumn).height;
    final gesture = await tester.startGesture(
      Offset(rect.center.dx, rect.bottom - 3.0),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(Offset(0.0, 2 * slot));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    item = await stored(tester, api, brainstormId);
    expect(item.day, today);
    expect(item.startMinute, 15 * 60);
    expect(item.endMinute, 16 * 60 + 30);

    // A multi-day item keeps its first day and its day count.
    await moveBlock(
      tester,
      blockFinder(retreat),
      cellRect(tester, rowOf(20 * 60), dayColumn).topLeft,
    );
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    final moved = await stored(tester, api, retreat);
    expect(moved.day, DateTime(2026, 4, 20));
    expect(moved.dayCount, 3);
    expect(moved.startMinute, 20 * 60);
    expect(moved.endMinute, 21 * 60);
  });

  testWidgets("D4 a drop onto another item's time lands at the nearest "
      "free time", (tester) async {
    final api = await pumpCalendar(tester, size: tall);
    await pickMode(tester, "Day");

    // 12:00 to 13:00 lies inside "Design new UX flow for Michael", which
    // ends at 13:00.
    await moveBlock(
      tester,
      blockFinder(brainstormId),
      cellRect(tester, rowOf(12 * 60), dayColumn).topLeft,
    );
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    final landed = await stored(tester, api, brainstormId);
    expect((landed.startMinute, landed.endMinute), (13 * 60, 14 * 60));
  });

  testWidgets("D5 Day mode reads the shown day alone", (tester) async {
    final api = await pumpCalendar(tester, size: tall);
    final lists = listCalls(api);
    await pickMode(tester, "Day");
    expect(listCalls(api), lists);

    // April's grid runs to May 3, which the first read covered.
    await step(tester, "Next day", times: 12);
    expect(headerFinder(DateTime(2026, 5, 3)), findsOneWidget);
    expect(listCalls(api), lists);

    await tester.tap(find.byTooltip("Next day"));
    await tester.pump();
    expect(listCalls(api), lists + 1);
    final read = api.requests.last;
    expect(read.first, DateTime(2026, 5, 4));
    expect(read.last, DateTime(2026, 5, 4));
    final overlay = find.descendant(
      of: find.byType(TimedGrid),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(overlay, findsOneWidget);
    await tester.pump(api.latency);
    await tester.pump();
    expect(overlay, findsNothing);
    expect(headerFinder(DateTime(2026, 5, 4)), findsOneWidget);
  });

  testWidgets("D6 switches keep the selected day; the painter's fills", (
    tester,
  ) async {
    await pumpCalendar(tester, size: tall);
    await pickMode(tester, "Day");

    var canvas = paintGridBackground(tester);
    expect(canvas.fillsOf(HarborColors.primaryTint), isNotEmpty);
    expect(canvas.fillsOf(HarborColors.background), isEmpty);
    await step(tester, "Next day");
    canvas = paintGridBackground(tester);
    expect(canvas.fillsOf(HarborColors.primaryTint), isEmpty);
    expect(canvas.fillsOf(HarborColors.background), isEmpty);
    // Saturday 2026-04-25.
    await step(tester, "Next day", times: 3);
    canvas = paintGridBackground(tester);
    expect(canvas.fillsOf(HarborColors.background), isNotEmpty);

    await pickMode(tester, "Week");
    expect(headerFinder(DateTime(2026, 4, 20)), findsOneWidget);
    expect(headerFill(tester, DateTime(2026, 4, 25)), HarborColors.primaryTint);

    await tester.tap(headerFinder(DateTime(2026, 4, 23)));
    await tester.pumpAndSettle();
    await pickMode(tester, "Day");
    expect(headerFinder(DateTime(2026, 4, 23)), findsOneWidget);
    expect(headerFinder(DateTime(2026, 4, 20)), findsNothing);
    expect(
      gridViewport(tester).rectOfCell(rowOf(9 * 60), dayColumn + 1),
      isNull,
    );

    await pickMode(tester, "Month");
    expect(find.text("Thursday, April 23"), findsOneWidget);
  });
}
