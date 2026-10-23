/// The calendar's Day mode: the timed grid over the selected day alone,
/// its steps, its gestures, its reads and its painter.
library;

import 'dart:ui' as ui;

import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_bar.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_api_source.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_settings.dart';
import 'package:widgets_extended/calendar/composition/calendar_card.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/settings_sheet.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';
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
/// prefilled with [day], [start] to [end], ending on [day]; then cancels
/// it.
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
  expectFormDays(day, 1);
  expect(
    find.descendant(
      of: dropdownFinder("Start time"),
      matching: find.text(start),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(of: dropdownFinder("End time"), matching: find.text(end)),
    findsOneWidget,
  );
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
  return itemFromJson(json!);
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

/// Opens the calendar bar, sets the hours to [start] to [end] o'clock and
/// closes it.
Future<void> setHours(WidgetTester tester, int start, int end) async {
  await openBar(tester);
  tester.widget<RangeSlider>(find.byKey(hoursSliderKey)).onChanged!(
    RangeValues(start.toDouble(), end.toDouble()),
  );
  await tester.pumpAndSettle();
  await closeBar(tester);
}

/// The line the timed grid's foreground marks the current time with.
CanvasRecord nowLine(WidgetTester tester) {
  return paintGridForeground(tester).lines.where((line) {
    return line.isIn(HarborColors.error);
  }).single;
}

/// The colour of the screen's pixel at [point], as 32-bit ARGB.
Future<int> pixelAt(WidgetTester tester, Offset point) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  var argb = 0;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final index = (point.dy.floor() * image.width + point.dx.floor()) * 4;
    image.dispose();
    final bytes = data!.buffer.asUint8List();
    argb =
        bytes[index + 3] << 24 |
        bytes[index] << 16 |
        bytes[index + 1] << 8 |
        bytes[index + 2];
  });
  return argb;
}

/// Pumps a timed grid of [today] alone under [settings] and the Harbor
/// calendar theme, with no day header, its slots at least [minSlotHeight]
/// tall, over [store], or a caching store over an empty mock API, at
/// [size], its clock at 09:00 on [today], and lets its read complete.
Future<void> pumpGrid(
  WidgetTester tester,
  CalendarSettings settings, {
  double minSlotHeight = defaultMinSlotHeight,
  Size size = const Size(390.0, 844.0),
  CalendarStore<ItemPayload>? store,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final shown =
      store ??
      CachingCalendarStore<ItemPayload>(
        dataSource: CalendarApiSource(MockCalendarApi(latency: harnessLatency)),
      );
  addTearDown(shown.dispose);
  final now = ValueNotifier<DateTime>(DateTime(2026, 4, 21, 9));
  addTearDown(now.dispose);
  shown.show(today, today);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CalendarTheme(
          data: harborCalendarTheme,
          child: TimedGrid(
            store: shown,
            firstDay: today,
            dayCount: 1,
            selectedDay: today,
            today: today,
            now: now,
            onSelectDay: (day) {},
            onOpenEntry: (id) {},
            onCreate: (range) async {},
            editable: settings.editing,
            lockPast: settings.lockPast,
            lockEarlierToday: settings.lockEarlierToday,
            weekdays: settings.weekdays,
            hours: settings.hours,
            hourLabelFormat: settings.hourLabelFormat,
            minDayWidth: minDayWidthLow,
            minSlotHeight: minSlotHeight,
            showsDayHeader: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump(harnessLatency);
  await tester.pump();
}

void main() {
  testWidgets("D1 Day mode shows the selected day's timed grid", (
    tester,
  ) async {
    // The default phone size, which scrolls far enough to show 08:00 at
    // the top.
    final api = await pumpCalendar(tester, editing: true);
    final requests = api.requests.length;
    await pickMode(tester, "Day");

    expect(find.text("Day"), findsOneWidget);
    expect(gridDay(tester), today);
    expect(find.byKey(dayCellKey(today)), findsNothing);
    expect(find.byType(DayList<ItemPayload>), findsNothing);
    expect(find.byTooltip("Add item"), findsNothing);
    expect(find.byTooltip("Previous day"), findsOneWidget);
    expect(find.byTooltip("Next day"), findsOneWidget);

    // 08:00's line sits the room for its label below the grid's top.
    final grid = gridViewport(tester);
    expect(
      grid.rectOfCell(dayRowOf(8 * 60), dayColumn)!.top,
      near(grid.scrolledRegion.top + labelRoom(tester)),
    );
    // One day column, from the gutter to the body's right edge.
    expect(cellRect(tester, dayRowOf(9 * 60), dayColumn).right, near(390.0));
    expect(grid.rectOfCell(dayRowOf(9 * 60), dayColumn + 1), isNull);

    final todays = <(String, int, int)>[
      (uxFlowId, 10 * 60, 13 * 60),
      (brainstormId, 14 * 60, 15 * 60),
    ];
    for (final (id, start, end) in todays) {
      final first = cellRect(tester, dayRowOf(start), dayColumn);
      final last = cellRect(tester, dayRowOf(end) - 1, dayColumn);
      final rect = tester.getRect(blockFinder(id));
      expect(rect.topLeft, nearOffset(first.topLeft), reason: id);
      expect(rect.bottomRight, nearOffset(last.bottomRight), reason: id);
    }
    expect(blockFinder(standupId), findsNothing);
    expect(api.requests, hasLength(requests));

    await step(tester, "Next day");
    expect(gridDay(tester), DateTime(2026, 4, 22));
    expect(blockFinder(standupId), findsOneWidget);
    expect(blockFinder(reviewId), findsOneWidget);
    expect(blockFinder(uxFlowId), findsNothing);

    await step(tester, "Previous day");
    expect(gridDay(tester), today);
    expect(blockFinder(uxFlowId), findsOneWidget);
    expect(blockFinder(standupId), findsNothing);
  });

  testWidgets("D2 a tap and a range drag create on the shown day", (
    tester,
  ) async {
    await pumpCalendar(tester, editing: true, size: tall);
    await pickMode(tester, "Day");

    await tester.tapAt(centerOf(tester, dayRowOf(16 * 60)));
    await tester.pumpAndSettle();
    await expectCreateForm(
      tester,
      type: "Meeting",
      day: "2026-04-21",
      start: "16:00",
      end: "16:15",
    );

    // A mouse drags at once, the whole move in one event.
    final gesture = await tester.startGesture(
      centerOf(tester, dayRowOf(18 * 60)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(centerOf(tester, dayRowOf(18 * 60 + 45)));
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

  testWidgets("D3 a move in Day moves a multi-day entry's start and end "
      "alike", (tester) async {
    // Monday 19:00 to Tuesday 20:00: on Tuesday from the day's start.
    final api = MockCalendarApi(
      seed: <Map<String, Object?>>[
        taskJson(
          "Retreat",
          DateTime(2026, 4, 20),
          19 * 60,
          20 * 60,
          dayCount: 2,
        ),
      ],
      latency: harnessLatency,
    );
    final retreat =
        (await listAll(tester, api, today, today)).single["id"]! as String;
    await pumpCalendar(tester, editing: true, api: api, size: tall);
    await pickMode(tester, "Day");

    // The item shows its Tuesday piece across the day's column, from the
    // day's start.
    final column = cellRect(tester, dayRowOf(0), dayColumn);
    final block = tester.getRect(blockFinder(retreat, today));
    expect(block.left, near(column.left));
    expect(block.right, near(column.right));
    expect(block.top, near(column.top));

    final board = tester.widget<Board<GridKey, GridShape<ItemPayload>>>(
      find.byType(Board<GridKey, GridShape<ItemPayload>>),
    );
    expect(board.drag!.resizeEdges, BoardResizeEdges.none);
    expect(board.drag!.primaryResizeEdges, BoardResizeEdges.both);

    // The piece's top, the day's start, lands an hour down, and the start
    // and the end move by that hour alike.
    await moveBlock(
      tester,
      blockFinder(retreat, today),
      cellRect(tester, dayRowOf(60), dayColumn).topLeft,
    );
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    final moved = await stored(tester, api, retreat);
    expect(moved.start, DateTime(2026, 4, 20, 20));
    expect(moved.end, DateTime(2026, 4, 21, 21));
  });

  testWidgets("D4 a drop onto another item's time lands at the nearest "
      "free time", (tester) async {
    final api = await pumpCalendar(tester, editing: true, size: tall);
    await pickMode(tester, "Day");

    // 12:00 to 13:00 lies inside "Design new UX flow for Michael", which
    // ends at 13:00.
    await moveBlock(
      tester,
      blockFinder(brainstormId),
      cellRect(tester, dayRowOf(12 * 60), dayColumn).topLeft,
    );
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    final landed = await stored(tester, api, brainstormId);
    expect(minutesOf(landed), (13 * 60, 14 * 60));
  });

  testWidgets("D5 Day mode reads the selected day's week, so a step within "
      "it shows its day at once", (tester) async {
    final api = await pumpCalendar(tester, size: tall);
    // Agenda read April's grid and its list the weeks of the days it built:
    // the last day read ends a week.
    var readTo = today;
    for (final request in api.requests) {
      final last = request.last;
      if (last != null && last.isAfter(readTo)) {
        readTo = last;
      }
    }
    expect(readTo.weekday, DateTime.sunday);
    final lists = listCalls(api);
    await pickMode(tester, "Day");
    expect(listCalls(api), lists);

    await step(tester, "Next day", times: daysBetween(today, readTo));
    expect(gridDay(tester), readTo);
    expect(listCalls(api), lists);

    await tester.tap(find.byTooltip("Next day"));
    await tester.pump();
    expect(listCalls(api), lists + 1);
    final read = api.requests.last;
    final monday = addDays(readTo, 1);
    expect(read.first, monday);
    expect(read.last, addDays(monday, 6));
    final overlay = find.descendant(
      of: find.byType(TimedGrid<ItemPayload>),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(overlay, findsOneWidget);
    await tester.pump(api.latency);
    await tester.pump();
    expect(overlay, findsNothing);
    expect(gridDay(tester), monday);

    for (var day = 1; day <= 6; day++) {
      await tester.tap(find.byTooltip("Next day"));
      await tester.pump();
      expect(gridDay(tester), addDays(monday, day));
      expect(overlay, findsNothing, reason: "${addDays(monday, day)}");
    }
    expect(listCalls(api), lists + 1);
    await tester.pumpAndSettle();
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
    expect(gridDay(tester), DateTime(2026, 4, 23));
    expect(
      gridViewport(tester).rectOfCell(dayRowOf(9 * 60), dayColumn + 1),
      isNull,
    );

    await pickMode(tester, "Agenda");
    expect(find.text("Thursday, April 23"), findsOneWidget);
  });

  testWidgets("D7 Day's grid has no day header and no corner count: its "
      "slots start at its top; Week keeps its header", (tester) async {
    await pumpCalendar(tester, size: tall);
    await pickMode(tester, "Day");
    var grid = gridViewport(tester);
    expect(grid.scrolledRegion.top, 0.0);
    expect(find.byKey(hiddenCountKey), findsNothing);

    // Hours of 08:00 to 14:00 leave "Brainstorm with the team", 14:00 to
    // 15:00, with no block, which a 24 px row below the slots counts in
    // place of the room there, and give 24 slots, which fit the grid, so
    // its first row shows.
    await setHours(tester, 8, 14);
    expect(blockFinder(brainstormId), findsNothing);
    expect(find.byKey(dayHeaderKey(today)), findsNothing);
    expect(find.byKey(hiddenCountKey), findsNothing);
    // The slots share the grid's height less the room above and the row
    // below.
    expect(
      grid.rectOfCell(24, dayColumn)!.bottom,
      near(grid.size.height - 24.0),
    );
    expect(grid.rectOfCell(1, dayColumn)!.top, near(labelRoom(tester)));

    await pickMode(tester, "Week");
    grid = gridViewport(tester);
    expect(headerFinder(today), findsOneWidget);
    expect(grid.scrolledRegion.top, 40.0);
  });

  testWidgets("D9 Day's first slot takes a tap and a drop, a drag's label "
      "sits at the grid's top, and the time line sits at its minute", (
    tester,
  ) async {
    final api = await pumpCalendar(
      tester,
      editing: true,
      size: tall,
      clock: () {
        return DateTime(2026, 4, 21, 10, 30);
      },
    );
    await pickMode(tester, "Day");
    // Row 0 is the room above the slots, row 1 is 08:00, and row 11 is
    // 10:30.
    await setHours(tester, 8, 14);
    final grid = gridViewport(tester);
    expect(nowLine(tester).from!.dy, near(grid.rectOfCell(11, dayColumn)!.top));
    // Clipped out of the frozen hour gutter.
    expect(
      (Canvas canvas) {
        grid.foreground!.paint(canvas, grid);
      },
      paints
        // The line's clip, after each hour label's own.
        ..something((method, arguments) {
          return method == #clipRect && arguments.first == grid.scrolledRegion;
        })
        ..line(),
    );

    await tester.tapAt(cellRect(tester, 1, dayColumn).center);
    await tester.pumpAndSettle();
    await expectCreateForm(
      tester,
      type: "Meeting",
      day: "2026-04-21",
      start: "08:00",
      end: "08:15",
    );

    final block = tester.getRect(blockFinder(uxFlowId));
    final gesture = await tester.startGesture(block.center);
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveBy(
      cellRect(tester, 1, dayColumn).topLeft - block.topLeft,
    );
    await tester.pump();
    expect(
      tester.getRect(find.byKey(landingLabelKey)).top,
      near(grid.localToGlobal(Offset.zero).dy + 8.0),
    );
    await gesture.up();
    await tester.pump();
    await tester.pump(gridAnimationStyle(tester).effectiveDropSettle.duration);
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    final moved = await stored(tester, api, uxFlowId);
    expect(minutesOf(moved), (8 * 60, 11 * 60));
  });

  testWidgets("D11 the time line shows over the block it crosses and moves "
      "with the clock", (tester) async {
    var now = DateTime(2026, 4, 21, 10, 30);
    await pumpCalendar(
      tester,
      size: tall,
      clock: () {
        return now;
      },
    );
    await pickMode(tester, "Day");
    final grid = gridViewport(tester);
    final error = HarborColors.error.toARGB32();
    double lineY() {
      return grid.localToGlobal(Offset(0.0, nowLine(tester).from!.dy)).dy;
    }

    // "Design new UX flow for Michael" runs from 10:00 to 13:00.
    final block = tester.getRect(blockFinder(uxFlowId));
    final x = block.center.dx;
    final before = lineY();
    expect(before, inExclusiveRange(block.top, block.bottom));
    expect(await pixelAt(tester, Offset(x, before)), error);

    now = DateTime(2026, 4, 21, 11, 30);
    await tester.pump(const Duration(minutes: 1));
    final after = lineY();
    expect(after, inExclusiveRange(before + 10.0, block.bottom));
    expect(await pixelAt(tester, Offset(x, after)), error);
    expect(await pixelAt(tester, Offset(x, before)), isNot(error));
  });

  testWidgets("D12 the hour labels sit centred on their lines, and the room "
      "above the first slot and below the last shows those two whole", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpCalendar(tester, size: tall);
    await pickMode(tester, "Day");
    await setHours(tester, 8, 20);
    final grid = gridViewport(tester);
    // The room, the 48 slots and the room fit the grid, so every row shows.
    expect(grid.firstVisibleRow, 0);
    expect(grid.lastVisibleRow, 49);
    final gutterRight = grid.visibleCellRect(1, 0).right;

    // 08:00 to 19:00 on the top lines of rows 1 to 45, then 20:00 on the
    // last slot's bottom line.
    final labels = paintGridForeground(tester).paragraphs;
    expect(labels, hasLength(13));
    for (var hour = 0; hour < 12; hour++) {
      final label = labels[hour];
      final line = grid.rectOfCell(1 + hour * 4, dayColumn)!.top;
      expect(
        label.offset.dy + label.paragraph.height / 2,
        near(line),
        reason: "label $hour",
      );
      expect(
        label.offset.dx + label.paragraph.maxIntrinsicWidth,
        near(gutterRight - 6.0),
        reason: "label $hour",
      );
    }
    final end = labels.last;
    expect(
      end.offset.dy + end.paragraph.height / 2,
      near(grid.rectOfCell(48, dayColumn)!.bottom),
    );
    expect(
      end.offset.dx + end.paragraph.maxIntrinsicWidth,
      near(gutterRight - 6.0),
    );
    // The first and the last lie inside the grid, 2 px from its edges.
    expect(labels.first.offset.dy, near(2.0));
    expect(end.offset.dy + end.paragraph.height, near(grid.size.height - 2.0));
    // Clipped to the gutter, from the top of the scrolled region to its
    // bottom.
    final region = grid.scrolledRegion;
    expect(
      (Canvas canvas) {
        grid.foreground!.paint(canvas, grid);
      },
      paints..clipRect(
        rect: Rect.fromLTRB(0.0, region.top, gutterRight, region.bottom),
      ),
    );

    // A screen reader hears the same times on the gutter.
    for (final time in <String>["08:00", "12:00", "19:00", "20:00"]) {
      expect(gutterLabelFinder(time), findsOneWidget, reason: time);
    }
    expect(gutterLabelFinder("07:00"), findsNothing);
    expect(gutterLabelFinder("21:00"), findsNothing);
    semantics.dispose();
  });

  testWidgets("D13 at twice the text size a label taller than two slots "
      "shows whole, and the half of a label whose row has scrolled away "
      "still shows", (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // The rooms and 96 slots of 8 px overflow a 600 px grid, which scrolls.
    await pumpGrid(
      tester,
      const CalendarSettings(),
      minSlotHeight: 8.0,
      size: const Size(390.0, 600.0),
    );
    final grid = gridViewport(tester);
    final position = grid.verticalPosition!;
    // The room above the first slot holds half a label at this size,
    // though the slots keep their least height.
    position.jumpTo(0.0);
    await tester.pump();
    final first = paintGridForeground(tester).paragraphs.first.paragraph;
    expect(grid.rectOfCell(0, 1)!.height, near(first.height / 2 + 2.0));
    final nineRow = dayRowOf(9 * 60);
    final nine = grid.rectOfCell(nineRow, 1)!;
    expect(nine.height, near(8.0));
    final label = paintGridForeground(tester).paragraphs.singleWhere((label) {
      return (label.offset.dy + label.paragraph.height / 2 - nine.top).abs() <
          0.5;
    });
    final half = label.paragraph.height / 2;
    // The test font draws each digit as a solid square of the font size,
    // 22 px here, so the label's lower half reaches past 09:00's slot into
    // the next. The pixel is inside the last digit, which ends at the
    // label's right edge.
    final ink = grid.localToGlobal(
      label.offset +
          Offset(
            label.paragraph.maxIntrinsicWidth - 2.0,
            label.paragraph.height - 2.0,
          ),
    );
    expect(ink.dy, greaterThan(grid.localToGlobal(nine.bottomLeft).dy));
    expect(await pixelAt(tester, ink), HarborColors.textSecondary.toARGB32());

    // With 09:00's slot scrolled to 1 px above the grid, its row does not
    // show, and the lower half of its label still does.
    position.jumpTo(position.pixels + nine.top + 9.0);
    await tester.pump();
    expect(grid.firstVisibleRow, nineRow + 1);
    expect(
      paintGridForeground(tester).paragraphs.where((label) {
        return (label.offset.dy - (-9.0 - half)).abs() < 0.5;
      }),
      hasLength(1),
    );

    // With 12:00's line 3 px below the grid, its row does not show, and
    // the upper half of its label still does.
    final noonRow = dayRowOf(12 * 60);
    final height = grid.size.height;
    final noonTop = -9.0 + (noonRow - nineRow) * nine.height;
    position.jumpTo(position.pixels + noonTop - (height + 3.0));
    await tester.pump();
    expect(grid.lastVisibleRow, noonRow - 1);
    expect(
      paintGridForeground(tester).paragraphs.where((label) {
        return (label.offset.dy - (height + 3.0 - half)).abs() < 0.5;
      }),
      hasLength(1),
    );
  });

  testWidgets("D14 a start off the hour is labelled, then each whole hour", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    // 08:30 to 12:00: 14 slots.
    await pumpGrid(tester, const CalendarSettings(hours: DayHours(510, 720)));
    final grid = gridViewport(tester);
    expect(grid.lastVisibleRow, 15);
    final labels = paintGridForeground(tester).paragraphs;
    // 08:30 on row 1, 09:00, 10:00 and 11:00 on rows 3, 7 and 11, then
    // 12:00 on the last slot's bottom line.
    expect(labels, hasLength(5));
    for (final (index, row) in <int>[1, 3, 7, 11].indexed) {
      final label = labels[index];
      expect(
        label.offset.dy + label.paragraph.height / 2,
        near(grid.rectOfCell(row, 1)!.top),
        reason: "row $row",
      );
    }
    expect(gutterLabelFinder("08:30"), findsOneWidget);
    expect(gutterLabelFinder("09:00"), findsOneWidget);
    expect(gutterLabelFinder("12:00"), findsOneWidget);

    // A larger text scale lays the labels out again.
    final height = labels.first.paragraph.height;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    final scaled = paintGridForeground(tester).paragraphs.first.paragraph;
    expect(scaled.height, near(2 * height));
    // The room above the first slot grows with them.
    expect(grid.rectOfCell(0, 1)!.height, near(scaled.height / 2 + 2.0));
    semantics.dispose();
  });

  testWidgets("D15 the room above and below the slots takes no create and "
      "no drop, and shows the plain body", (tester) async {
    final api = MockCalendarApi(
      seed: <Map<String, Object?>>[taskJson("Late", today, 13 * 60, 14 * 60)],
      latency: harnessLatency,
    );
    await pumpCalendar(tester, api: api, size: tall);
    await pickMode(tester, "Day");
    // Row 0 is the room above 08:00, rows 1 to 24 the slots, and row 25
    // the room below 14:00.
    await setHours(tester, 8, 14);
    final grid = gridViewport(tester);

    await tester.tapAt(cellRect(tester, 0, dayColumn).center);
    await tester.pumpAndSettle();
    expect(find.text("New item"), findsNothing);
    await tester.tapAt(cellRect(tester, 25, dayColumn).center);
    await tester.pumpAndSettle();
    expect(find.text("New item"), findsNothing);

    // The bottom strip of "Late", 13:00 to 14:00, dragged into the room
    // below stops at 14:00 and writes nothing, so nothing is refused.
    final late = tester.getRect(blockFinder("item-1"));
    final updates = api.requests.where((request) {
      return request.method == CalendarMethod.update;
    }).length;
    final gesture = await tester.startGesture(
      Offset(late.center.dx, late.bottom - 3.0),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(Offset(0.0, cellRect(tester, 25, dayColumn).height));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(blockFinder("item-1")), late);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      api.requests.where((request) {
        return request.method == CalendarMethod.update;
      }),
      hasLength(updates),
    );

    // The body's fills and lines run across the slots alone.
    final firstTop = grid.rectOfCell(1, dayColumn)!.top;
    final lastBottom = grid.rectOfCell(24, dayColumn)!.bottom;
    final canvas = paintGridBackground(tester);
    final tint = canvas.fillsOf(HarborColors.primaryTint).single;
    expect(tint.top, near(firstTop));
    expect(tint.bottom, near(lastBottom));
    final rows = <double>[
      for (final line in canvas.lines)
        if (line.from!.dy == line.to!.dy) line.from!.dy,
    ];
    expect(rows, hasLength(25));
    expect(rows.first, near(firstTop));
    expect(rows.last, near(lastBottom));
    for (final line in canvas.lines) {
      if (line.from!.dx == line.to!.dx) {
        expect(line.from!.dy, near(firstTop));
        expect(line.to!.dy, near(lastBottom));
      }
    }
  });

  testWidgets("D10 at the end of the hours the time line sits on the bottom "
      "of Day's last slot", (tester) async {
    await pumpCalendar(
      tester,
      size: tall,
      clock: () {
        return DateTime(2026, 4, 21, 14);
      },
    );
    await pickMode(tester, "Day");
    await setHours(tester, 8, 14);
    expect(
      nowLine(tester).from!.dy,
      near(gridViewport(tester).rectOfCell(24, dayColumn)!.bottom),
    );
  });

  testWidgets("D8 a Day block shows its times and the summary lines that "
      "fit whole; a Week block shows no times", (tester) async {
    final api = MockCalendarApi(
      seed: <Map<String, Object?>>[
        taskJson("Half", today, 15 * 60, 15 * 60 + 30),
        taskJson("Hour", today, 16 * 60, 17 * 60),
        taskJson("Ninety", today, 17 * 60, 18 * 60 + 30),
        taskJson(
          "A title too long for its times to follow on its line",
          today,
          19 * 60,
          20 * 60,
        ),
      ],
      latency: harnessLatency,
    );
    const half = "item-1";
    const hour = "item-2";
    const ninety = "item-3";
    const long = "item-4";
    await pumpCalendar(tester, api: api);
    // Slots of 12 px, so a block's lines get its rows times 12, less its
    // 1 px margins and 3 px paddings.
    await openSettings(tester);
    tester.widget<Slider>(find.byKey(slotHeightSliderKey)).onChanged!(12.0);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195.0, 20.0));
    await tester.pumpAndSettle();
    await pickMode(tester, "Day");

    Finder lineOf(String id, String text) {
      return find.descendant(of: blockFinder(id), matching: find.text(text));
    }

    Finder flowOf(String id) {
      return find.descendant(of: blockFinder(id), matching: find.byType(Flow));
    }

    // Under the theme's body style the first line lays out 19 px tall and
    // each summary line 17 px.
    expect(tester.getSize(blockFinder(hour)).height, near(4 * 12.0));
    expect(
      tester
          .getSize(
            find.descendant(of: blockFinder(hour), matching: find.byType(Wrap)),
          )
          .height,
      19.0,
    );
    expect(tester.getSize(lineOf(hour, "To do")).height, 17.0);

    expect(lineOf(half, "15:00-15:30"), findsOneWidget);
    // 16 px of lines hold the first line alone, 40 px one summary under
    // it, and 64 px both. Each paragraph painted is one line's text, and
    // the first line holds two: the title and the times.
    expect(
      tester.renderObject(flowOf(half)),
      paintsExactlyCountTimes(#drawParagraph, 2),
    );
    expect(
      tester.renderObject(flowOf(hour)),
      paintsExactlyCountTimes(#drawParagraph, 3),
    );
    expect(
      tester.renderObject(flowOf(ninety)),
      paintsExactlyCountTimes(#drawParagraph, 4),
    );

    // The times wrap under a title too long for both.
    final title = tester.getRect(
      lineOf(long, "A title too long for its times to follow on its line"),
    );
    final times = tester.getRect(lineOf(long, "19:00-20:00"));
    expect(times.top, greaterThanOrEqualTo(title.bottom));
    expect(times.left, near(title.left));

    await pickMode(tester, "Week");
    expect(blockFinder(ninety), findsOneWidget);
    expect(lineOf(ninety, "17:00-18:30"), findsNothing);
  });

  testWidgets("D17 Day counts the items before its hours in a yellow row "
      "frozen above its slots, and those after them in one below, the hour "
      "gutter beside both", (tester) async {
    final semantics = tester.ensureSemantics();
    final api = MockCalendarApi(
      seed: <Map<String, Object?>>[
        taskJson("Early", today, 6 * 60, 7 * 60),
        taskJson("Dawn", today, 7 * 60, 7 * 60 + 30),
        // Cut by the hours' start, so it has a block and no count.
        taskJson("Cut", today, 7 * 60 + 30, 9 * 60),
        taskJson("Late", today, 15 * 60, 16 * 60),
        // 05:00 to 06:00 on each of April 20 to 22.
        taskJson("Trip", DateTime(2026, 4, 20), 5 * 60, 6 * 60),
        taskJson("Trip", today, 5 * 60, 6 * 60),
        taskJson("Trip", DateTime(2026, 4, 22), 5 * 60, 6 * 60),
      ],
      latency: harnessLatency,
    );
    await pumpCalendar(tester, api: api, size: tall);
    await pickMode(tester, "Day");
    final above = find.byKey(hiddenAboveKey(today));
    final below = find.byKey(hiddenBelowKey(today));
    expect(above, findsNothing);
    expect(below, findsNothing);

    await setHours(tester, 8, 14);
    expect(
      find.descendant(of: above, matching: find.text("+3 more")),
      findsOneWidget,
    );
    expect(
      find.descendant(of: below, matching: find.text("+1 more")),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel("Tuesday, April 21, 3 more items before 08:00"),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel("Tuesday, April 21, 1 more item after 14:00"),
      findsOneWidget,
    );
    final fill = tester.widget<DecoratedBox>(above).decoration;
    expect((fill as BoxDecoration).color, HarborColors.notice);

    // The rows are the grid's first and last, right of the hour gutter,
    // in the place of the room above and below the slots, so they meet
    // the slots: row 1 is 08:00's slot and row 24 13:45's.
    final grid = gridViewport(tester);
    final box = grid.localToGlobal(Offset.zero) & grid.size;
    final top = tester.getRect(above);
    final bottom = tester.getRect(below);
    expect(top.top, near(box.top));
    expect(top.left, near(box.left + 56.0));
    expect(top.right, near(box.right));
    expect(bottom.bottom, near(box.bottom));
    expect(bottom.left, near(box.left + 56.0));
    expect(cellRect(tester, 1, dayColumn).top, near(top.bottom));
    expect(cellRect(tester, 24, dayColumn).bottom, near(bottom.top));

    // AM/PM names the hours to a screen reader as the gutter does.
    await openBar(tester);
    await tester.tap(find.byKey(hourLabelFormatKey));
    await tester.pumpAndSettle();
    await closeBar(tester);
    expect(
      find.bySemanticsLabel("Tuesday, April 21, 3 more items before 8 AM"),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel("Tuesday, April 21, 1 more item after 2 PM"),
      findsOneWidget,
    );

    // Hours holding every item take both rows away.
    await setHours(tester, 0, 24);
    expect(above, findsNothing);
    expect(below, findsNothing);
    semantics.dispose();
  });

  testWidgets("D18 an hour label beside a row counting items outside the "
      "hours shows whole while its line shows, and sinks into the row's edge "
      "as its line scrolls beneath it", (tester) async {
    final api = MockCalendarApi(
      seed: <Map<String, Object?>>[
        taskJson("Early", today, 6 * 60, 7 * 60),
        taskJson("Late", today, 15 * 60, 16 * 60),
      ],
      latency: harnessLatency,
    );
    await pumpCalendar(tester, api: api);
    await pickMode(tester, "Day");
    await setHours(tester, 8, 14);
    await openSettings(tester);
    // 24 slots of 48 px, taller than the grid, so it scrolls.
    tester.widget<Slider>(find.byKey(slotHeightSliderKey)).onChanged!(48.0);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195.0, 20.0));
    await tester.pumpAndSettle();

    final grid = gridViewport(tester);
    final region = grid.scrolledRegion;
    final half = labelRoom(tester) - 2.0;
    // Each label's clip, in the order the labels paint, the first slot's
    // first.
    List<Rect> clips() {
      return paintGridForeground(tester).clips;
    }

    // At the top 08:00's line is the region's top edge, so its label may
    // reach half its height above it, beside the row there, and as far
    // below the bottom edge, past which the end's label reaches.
    expect(region.top, 24.0);
    expect(region.bottom, grid.size.height - 24.0);
    expect(clips().first.top, near(region.top - half));
    expect(clips().first.bottom, near(region.bottom + half));
    expect(clips().first.left, 0.0);
    expect(clips().first.right, 56.0);

    // Scrolled 3 px, 08:00's line lies 3 px beneath the row, and its label
    // reaches 3 px less above the edge.
    final vertical = grid.verticalPosition!;
    vertical.jumpTo(3.0);
    await tester.pump();
    expect(clips().first.top, near(region.top - half + 3.0));

    // Past half a label, it reaches nothing past the edge.
    vertical.jumpTo(half + 1.0);
    await tester.pump();
    expect(clips().first.top, near(region.top));

    // At the bottom the end's label, 14:00's, reaches below the bottom
    // edge as 08:00's did above the top.
    vertical.jumpTo(vertical.maxScrollExtent);
    await tester.pump();
    expect(clips().last.bottom, near(region.bottom + half));
  });

  testWidgets("D19 Day opens with its days folded into the strip; the pull "
      "tab unfolds the month, where a tap shows that day, and a drag up "
      "the board folds it again", (tester) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Day");
    expect(find.byType(WeekStrip<ItemPayload>), findsOneWidget);

    await tester.drag(find.byKey(calendarPullTabKey), const Offset(0.0, 300.0));
    await tester.pumpAndSettle();
    expect(find.byType(WeekStrip<ItemPayload>), findsNothing);
    final thursday = DateTime(2026, 4, 23);
    await tester.tap(find.byKey(dayCellKey(thursday)));
    await tester.pumpAndSettle();
    expect(gridDay(tester), thursday);

    await tester.drag(
      find.byType(TimedGrid<ItemPayload>),
      const Offset(0.0, -200.0),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WeekStrip<ItemPayload>), findsOneWidget);
  });

  testWidgets("D20 over an in-memory store a drop applies within the drop, "
      "the block landing where it was dropped", (tester) async {
    final item = calendarItem(
      id: "item-1",
      type: CalendarItemType.task,
      title: "Write",
      start: atMinute(today, 10 * 60),
      end: atMinute(today, 11 * 60),
      fields: const <String, Object?>{"status": "toDo"},
    );
    final changes = <(CalendarItem?, CalendarItem?)>[];
    final store = MemoryCalendarStore<ItemPayload>(
      entries: <CalendarItem>[item],
      onChanged: (old, entry) {
        changes.add((old, entry));
      },
    );
    final heard = <(CalendarItem?, bool)>[];
    store.addListener(() {
      heard.add((store.storedEntry("item-1"), store.isPending("item-1")));
    });
    await pumpGrid(
      tester,
      const CalendarSettings(editing: true),
      size: tall,
      store: store,
    );

    final noon = cellRect(tester, dayRowOf(12 * 60), dayColumn);
    await moveBlock(tester, blockFinder("item-1"), noon.topLeft);
    final moved = item.copyWith(
      start: atMinute(today, 12 * 60),
      end: atMinute(today, 13 * 60),
    );
    expect(heard, <(CalendarItem?, bool)>[(moved, false)]);
    expect(changes, <(CalendarItem?, CalendarItem?)>[(item, moved)]);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(blockFinder("item-1")).top,
      near(cellRect(tester, dayRowOf(12 * 60), dayColumn).top),
    );
  });
}
