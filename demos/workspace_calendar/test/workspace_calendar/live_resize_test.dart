/// Widget tests for a resize strip drag on the timed grids: the block, or
/// the all-day strip's bar, takes the size the drop would give it on the
/// frame after the pointer moves, and keeps that size through the release,
/// the write and the mock's answer.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';

import 'calendar_harness.dart';

const Duration oneFrame = Duration(milliseconds: 16);

/// A size tall enough that every row from 08:00 to 24:00 shows once the
/// grid has jumped to 08:00.
const Size tall = Size(390.0, 1400.0);

/// The frames pumped after a release: past the drop-settle glide and the
/// mock's answer to the write.
const int framesAfterRelease = 30;

/// Layout rounds track offsets, so geometry is compared to half a pixel.
Matcher nearRect(Rect value) {
  return rectMoreOrLessEquals(value, epsilon: 0.5);
}

/// Selects [id]'s block, drags its strip at [strip] by [delta] with a
/// mouse, which the grid's scrollable never takes, and expects the block at
/// [expected] on the frame after the move and on every frame after the
/// release until the write has been answered.
Future<void> expectLiveResize(
  WidgetTester tester,
  String id,
  Offset strip,
  Offset delta,
  Rect expected,
) async {
  await selectBlock(tester, id);
  final gesture = await tester.startGesture(
    strip,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(delta);
  await tester.pump();
  expect(tester.getRect(blockFinder(id)), nearRect(expected));
  await gesture.up();
  await tester.pump();
  expect(tester.getRect(blockFinder(id)), nearRect(expected));
  for (var frame = 0; frame < framesAfterRelease; frame++) {
    await tester.pump(oneFrame);
    expect(tester.getRect(blockFinder(id)), nearRect(expected));
  }
  await tester.pumpAndSettle();
  expect(tester.getRect(blockFinder(id)), nearRect(expected));
}

/// The item [id] as [api] holds it, through a `get` pumped past its
/// latency.
Future<Map<String, Object?>> storedJson(
  WidgetTester tester,
  MockCalendarApi api,
  String id,
) async {
  Map<String, Object?>? json;
  api.get(id).then((value) {
    json = value;
  });
  await tester.pump(api.latency);
  return json!;
}

void main() {
  testWidgets("L1 the week grid's bottom strip sets the end as it drags", (
    tester,
  ) async {
    final api = await pumpCalendar(tester, editing: true, size: tall);
    await pickMode(tester, "Week");
    final slot = cellRect(tester, rowOf(9 * 60), colOf(0)).height;
    final before = tester.getRect(blockFinder(brainstormId));
    await expectLiveResize(
      tester,
      brainstormId,
      Offset(before.center.dx, before.bottom - 3.0),
      Offset(0.0, 2 * slot),
      Rect.fromLTRB(
        before.left,
        before.top,
        before.right,
        before.bottom + 2 * slot,
      ),
    );
    // Setup sanity: the drop was written, two slots later.
    final item = await storedJson(tester, api, brainstormId);
    expect(minuteOfDay(endOfJson(item)), 15 * 60 + 30);
  });

  testWidgets("L2 a strip bar's trailing day edge sets the days as it "
      "drags", (tester) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    final wednesday = DateTime(2026, 4, 22);
    await createBeforePump(
      tester,
      api,
      taskJson("Focus", wednesday, 0, minutesPerDay),
    );
    final focus =
        (await listAll(
              tester,
              api,
              wednesday,
              wednesday,
            )).singleWhere((item) => item["title"] == "Focus")["id"]!
            as String;
    await pumpCalendar(tester, editing: true, api: api, size: tall);
    await pickMode(tester, "Week");
    final bar = find.byKey(allDayBarKey(focus));
    final dayWidth = cellRect(tester, rowOf(9 * 60), colOf(0)).width;
    final before = tester.getRect(bar);
    // Setup sanity: the bar fills its one day.
    expect(before.width, moreOrLessEquals(dayWidth, epsilon: 0.5));
    final press = await tester.startGesture(tester.getCenter(bar));
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await press.up();
    await tester.pumpAndSettle();
    final expected = Rect.fromLTRB(
      before.left,
      before.top,
      before.right + dayWidth,
      before.bottom,
    );
    final gesture = await tester.startGesture(
      Offset(before.right - 3.0, before.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(Offset(dayWidth, 0.0));
    await tester.pump();
    expect(tester.getRect(bar), nearRect(expected));
    await gesture.up();
    await tester.pump();
    expect(tester.getRect(bar), nearRect(expected));
    for (var frame = 0; frame < framesAfterRelease; frame++) {
      await tester.pump(oneFrame);
      expect(tester.getRect(bar), nearRect(expected));
    }
    await tester.pumpAndSettle();
    expect(tester.getRect(bar), nearRect(expected));
    // Setup sanity: the drop was written, a day later.
    final item = await storedJson(tester, api, focus);
    expect(startOfJson(item), wednesday);
    expect(endOfJson(item), DateTime(2026, 4, 24));
  });

  testWidgets("L3 the day grid's bottom strip sets the end as it drags", (
    tester,
  ) async {
    final api = await pumpCalendar(tester, editing: true, size: tall);
    await pickMode(tester, "Day");
    final slot = cellRect(tester, dayRowOf(9 * 60), 1).height;
    final before = tester.getRect(blockFinder(brainstormId));
    await expectLiveResize(
      tester,
      brainstormId,
      Offset(before.center.dx, before.bottom - 3.0),
      Offset(0.0, 2 * slot),
      Rect.fromLTRB(
        before.left,
        before.top,
        before.right,
        before.bottom + 2 * slot,
      ),
    );
    // Setup sanity: the drop was written, two slots later.
    final item = await storedJson(tester, api, brainstormId);
    expect(minuteOfDay(endOfJson(item)), 15 * 60 + 30);
  });
}
