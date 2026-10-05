/// The calendar's Week mode: the timed grid, its create gestures, the
/// pending writes on its blocks, the form it opens, its syncs with the
/// model and its painter.
library;

import 'package:examples/workspace_calendar/calendar_api.dart';
import 'package:examples/workspace_calendar/calendar_data.dart';
import 'package:examples/workspace_calendar/calendar_item.dart';
import 'package:examples/workspace_calendar/calendar_model.dart';
import 'package:examples/workspace_calendar/calendar_schema.dart';
import 'package:examples/workspace_calendar/day_cell.dart';
import 'package:examples/workspace_calendar/day_list.dart';
import 'package:examples/workspace_calendar/harbor_theme.dart';
import 'package:examples/workspace_calendar/item_card.dart';
import 'package:examples/workspace_calendar/mock_calendar_api.dart';
import 'package:examples/workspace_calendar/week_grid.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_harness.dart';

const Duration oneFrame = Duration(milliseconds: 16);

/// A size tall enough that every row from 08:00 to 24:00 shows once the
/// grid has jumped to 08:00.
const Size tall = Size(390.0, 1400.0);

/// Layout rounds track offsets, so geometry is compared to half a pixel.
Matcher near(double value) {
  return moreOrLessEquals(value, epsilon: 0.5);
}

Matcher nearOffset(Offset value) {
  return offsetMoreOrLessEquals(value, epsilon: 0.5);
}

Finder headerFinder(DateTime day) {
  return find.byKey(weekDayHeaderKey(day));
}

Offset centerOf(WidgetTester tester, int row, int col) {
  return cellRect(tester, row, col).center;
}

Future<void> tapCell(WidgetTester tester, int row, int col) async {
  await tester.tapAt(centerOf(tester, row, col));
  await tester.pumpAndSettle();
}

/// Taps an empty slot and picks [type] in the create flow's picker.
Future<void> createAt(
  WidgetTester tester,
  int row,
  int col,
  String type,
) async {
  await tapCell(tester, row, col);
  expect(find.text("New item"), findsOneWidget);
  await tester.tap(find.text(type).last);
  await tester.pumpAndSettle();
}

Finder fieldFinder(String label) {
  return find.widgetWithText(TextField, label);
}

String fieldText(WidgetTester tester, String label) {
  return tester.widget<TextField>(fieldFinder(label)).controller!.text;
}

/// The text a dropdown labelled [label] shows as its value.
Finder dropdownFinder(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) {
      return widget is DropdownButtonFormField;
    }),
  );
}

Finder saveFinder() {
  return find.byType(FilledButton);
}

Finder formButton(String label) {
  return find.widgetWithText(TextButton, label);
}

bool isEnabled(WidgetTester tester, Finder button) {
  return tester.widget<ButtonStyleButton>(button).onPressed != null;
}

/// Picks [option] in the dropdown labelled [label], scrolling its menu by
/// [delta] until the option shows.
Future<void> chooseOption(
  WidgetTester tester,
  String label,
  String option, {
  double delta = -100.0,
}) async {
  await tester.tap(dropdownFinder(label));
  await tester.pumpAndSettle();
  final menu = find.byType(Scrollable).last;
  final item = find.descendant(of: menu, matching: find.text(option));
  await tester.scrollUntilVisible(item, delta, scrollable: menu);
  // Centred, as an item scrolled to the menu's edge can sit under it.
  await Scrollable.ensureVisible(tester.element(item), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

/// The opacity the pending fade gives [finder]'s content: the first
/// [Opacity] under it, or 1.0 when there is none.
double fadeOf(WidgetTester tester, Finder finder) {
  final fades = tester.widgetList<Opacity>(
    find.descendant(of: finder, matching: find.byType(Opacity)),
  );
  return fades.isEmpty ? 1.0 : fades.first.opacity;
}

Size indicatorSizeIn(WidgetTester tester, Finder finder) {
  return tester.getSize(
    find.descendant(
      of: finder,
      matching: find.byType(CircularProgressIndicator),
    ),
  );
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

/// The id of the item titled [title] that [api] holds on [day].
Future<String> idOn(
  WidgetTester tester,
  MockCalendarApi api,
  DateTime day,
  String title,
) async {
  final items = await listAll(tester, api, day, day);
  return items.singleWhere((item) => item["title"] == title)["id"]! as String;
}

/// The model the week grid shows.
CalendarModel model(WidgetTester tester) {
  return tester.widget<WeekGrid>(find.byType(WeekGrid)).model;
}

/// The block whose title is [title].
Finder blockTitled(String title) {
  return find.ancestor(
    of: find.text(title),
    matching: find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith("block-");
    }),
  );
}

Color textColorOf(WidgetTester tester, Finder text) {
  return tester.renderObject<RenderParagraph>(text).text.style!.color!;
}

void main() {
  testWidgets("W1 Week mode shows the timed grid", (tester) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    await createBeforePump(tester, api, taskJson("Night deploy", today, 0, 60));
    await createBeforePump(tester, api, <String, Object?>{
      "type": "meeting",
      "title": "Pairing",
      "day": "2026-04-22",
      "startMinute": 8 * 60 + 15,
      "endMinute": 9 * 60,
      "dayCount": 1,
      "fields": <String, Object?>{"location": "Lab"},
    });
    final week = await listAll(tester, api, monday, addDays(monday, 6));
    await pumpCalendar(tester, api: api);
    final requests = api.requests.length;

    await tester.tap(find.byTooltip("Calendar view"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Week").last);
    var frames = 0;
    while (headerFinder(monday).evaluate().isEmpty && frames < 10) {
      await tester.pump();
      frames++;
    }
    // The first frame that shows the grid shows its blocks.
    final viewport = weekViewport(tester);
    var checked = 0;
    for (final item in week) {
      final start = item["startMinute"]! as int;
      final end = item["endMinute"]! as int;
      final first = rowOf(start);
      final last = rowOf(end) - 1;
      if (last < viewport.firstVisibleRow || first > viewport.lastVisibleRow) {
        continue;
      }
      checked++;
      expect(
        blockFinder(item["id"]! as String),
        findsOneWidget,
        reason: "${item["title"]} on the first frame",
      );
    }
    expect(checked, greaterThan(0));
    final nightDeploy = week.singleWhere(
      (item) => item["title"] == "Night deploy",
    );
    expect(blockFinder(nightDeploy["id"]! as String), findsOneWidget);

    // One frame later every block is at full width.
    await tester.pump(oneFrame);
    final widths = <String, double>{
      for (final item in week)
        if (blockFinder(item["id"]! as String).evaluate().isNotEmpty)
          item["id"]! as String: tester
              .getSize(blockFinder(item["id"]! as String))
              .width,
    };
    expect(widths, isNotEmpty);
    await tester.pump(weekGridAnimationStyle.effectiveItemEnterExit.duration);
    for (final entry in widths.entries) {
      if (blockFinder(entry.key).evaluate().isEmpty) {
        continue;
      }
      expect(
        tester.getSize(blockFinder(entry.key)).width,
        entry.value,
        reason: "${entry.key} at full width",
      );
    }

    await tester.pumpAndSettle();
    expect(headerFinder(monday), findsOneWidget);
    for (var day = 0; day < 7; day++) {
      expect(headerFinder(addDays(monday, day)), findsOneWidget);
    }
    expect(
      find.descendant(of: headerFinder(monday), matching: find.text("Mo")),
      findsOneWidget,
    );
    expect(find.byType(DayCell), findsNothing);
    expect(find.byType(DayList), findsNothing);

    // Settled, each block that shows spans its day's column from its start
    // slot to its end slot.
    var placed = 0;
    for (final item in week) {
      final id = item["id"]! as String;
      if (blockFinder(id).evaluate().isEmpty) {
        continue;
      }
      placed++;
      final day = parseIsoDate(item["day"]! as String)!;
      final col = colOf(daysBetween(monday, day));
      final first = cellRect(tester, rowOf(item["startMinute"]! as int), col);
      final last = cellRect(tester, rowOf(item["endMinute"]! as int) - 1, col);
      final rect = tester.getRect(blockFinder(id));
      expect(rect.topLeft, nearOffset(first.topLeft), reason: id);
      expect(rect.bottomRight, nearOffset(last.bottomRight), reason: id);
    }
    expect(placed, greaterThan(0));
    final pairing = week.singleWhere((item) => item["title"] == "Pairing");
    expect(
      find.descendant(
        of: blockFinder(designCritiqueId),
        matching: find.text("Studio"),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: blockFinder(pairing["id"]! as String),
        matching: find.text("Lab"),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: blockFinder(standupId), matching: find.text("To do")),
      findsNothing,
    );
    final grid = weekViewport(tester);
    expect(
      grid.rectOfCell(rowOf(8 * 60), 1)!.top,
      near(grid.scrolledRegion.top),
    );

    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    for (var day = 0; day < 7; day++) {
      final date = addDays(monday, 7 + day);
      expect(
        find.descendant(
          of: headerFinder(date),
          matching: find.text("${date.day}"),
        ),
        findsOneWidget,
      );
    }
    expect(headerFinder(monday), findsNothing);
    Color headerFill(DateTime day) {
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

    expect(headerFill(DateTime(2026, 4, 28)), HarborColors.primaryTint);
    expect(headerFill(DateTime(2026, 4, 27)), HarborColors.surface);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip("Previous week"));
      await tester.pumpAndSettle();
    }
    expect(headerFinder(DateTime(2026, 3, 30)), findsOneWidget);
    expect(headerFinder(DateTime(2026, 4, 5)), findsOneWidget);
    expect(find.text("March 2026"), findsOneWidget);
    expect(api.requests, hasLength(requests));

    await tester.tap(headerFinder(DateTime(2026, 4, 2)));
    await tester.pumpAndSettle();
    await pickMode(tester, "Month");
    expect(find.text("Thursday, April 2"), findsOneWidget);
    expect(find.text("April 2026"), findsOneWidget);
  });

  testWidgets("W2 a tap on an empty slot creates a Meeting", (tester) async {
    const latency = Duration(seconds: 1);
    final api = await pumpCalendar(
      tester,
      api: MockCalendarApi.seeded(today, latency: latency),
    );
    await pickMode(tester, "Week");

    await createAt(tester, rowOf(14 * 60), colOf(2), "Meeting");
    expect(find.text("New Meeting"), findsOneWidget);
    expect(find.text("2026-04-22"), findsOneWidget);
    expect(
      find.descendant(
        of: dropdownFinder("Start"),
        matching: find.text("14:00"),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dropdownFinder("End"), matching: find.text("15:00")),
      findsOneWidget,
    );
    expect(fieldText(tester, "Days"), "1");
    expect(formButton("Delete"), findsNothing);

    await tester.enterText(fieldFinder("Title"), "Design sync");
    final requests = api.requests.length;
    await tester.tap(saveFinder());
    await tester.pump();
    expect(api.requests, hasLength(requests + 1));
    await tester.tap(saveFinder(), warnIfMissed: false);
    await tester.pump();
    expect(api.requests, hasLength(requests + 1));
    // The form's controls stay disabled while the save runs, and the back
    // gesture leaves it open.
    expect(isEnabled(tester, formButton("Cancel")), isFalse);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text("New Meeting"), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 998));
    expect(find.text("New Meeting"), findsOneWidget);
    expect(
      find.descendant(
        of: saveFinder(),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(oneFrame);
    final dayWidth = cellRect(tester, rowOf(14 * 60), colOf(2)).width;
    expect(
      tester.getSize(blockTitled("Design sync")).width,
      lessThan(dayWidth - 1.0),
    );
    final created =
        (tester.widget(blockTitled("Design sync")).key! as ValueKey<String>)
            .value
            .substring("block-".length);
    await tester.pumpAndSettle();
    expect(find.text("New Meeting"), findsNothing);
    final slot = cellRect(tester, rowOf(14 * 60), colOf(2));
    final rect = tester.getRect(blockFinder(created));
    expect(rect.topLeft, nearOffset(slot.topLeft));
    expect(rect.width, near(slot.width));
    expect(rect.height, near(4 * slot.height));
    final listed = await listAll(
      tester,
      api,
      DateTime(2026, 4, 22),
      DateTime(2026, 4, 22),
    );
    expect(
      listed.where((item) => item["title"] == "Design sync"),
      hasLength(1),
    );

    // A tap on the last slot of the day ends the item at 24:00.
    weekViewport(tester).verticalPosition!.jumpTo(
      weekViewport(tester).verticalPosition!.maxScrollExtent,
    );
    await tester.pumpAndSettle();
    await createAt(tester, rowOf(23 * 60 + 30), colOf(2), "Task");
    expect(
      find.descendant(
        of: dropdownFinder("Start"),
        matching: find.text("23:30"),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dropdownFinder("End"), matching: find.text("24:00")),
      findsOneWidget,
    );
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();
  });

  testWidgets("W3 a range across empty cells creates its rectangle", (
    tester,
  ) async {
    final api = await pumpCalendar(tester);
    await pickMode(tester, "Week");
    final saturday = colOf(5);
    final sunday = colOf(6);
    final from = rowOf(14 * 60);
    final to = rowOf(14 * 60 + 45);

    Future<void> expectForm(
      String start,
      String end,
      String days, {
      String day = "2026-04-25",
    }) async {
      expect(find.text("New item"), findsOneWidget);
      await tester.tap(find.text("Task").last);
      await tester.pumpAndSettle();
      expect(find.text(day), findsOneWidget);
      expect(
        find.descendant(
          of: dropdownFinder("Start"),
          matching: find.text(start),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dropdownFinder("End"), matching: find.text(end)),
        findsOneWidget,
      );
      expect(fieldText(tester, "Days"), days);
      await tester.tap(formButton("Cancel"));
      await tester.pumpAndSettle();
    }

    // A mouse drags at once, the whole move in one event.
    var gesture = await tester.startGesture(
      centerOf(tester, from, saturday),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(centerOf(tester, to, sunday));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await expectForm("14:00", "15:00", "2");

    // Touch after a hold.
    gesture = await tester.startGesture(centerOf(tester, from, saturday));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(centerOf(tester, to, sunday));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await expectForm("14:00", "15:00", "2");

    // A stylus past its slop, then on.
    gesture = await tester.startGesture(
      centerOf(tester, from, saturday),
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveBy(const Offset(20.0, 0.0));
    await tester.pump();
    await gesture.moveTo(centerOf(tester, to, sunday));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await expectForm("14:00", "15:00", "2");

    // A mouse drag that stays in its cell is a tap.
    gesture = await tester.startGesture(
      centerOf(tester, from, saturday),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(2.0, 0.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await expectForm("14:00", "15:00", "1");

    // A touch drag without a hold scrolls and creates nothing.
    final vertical = weekViewport(tester).verticalPosition!;
    final before = vertical.pixels;
    await tester.dragFrom(
      centerOf(tester, from, saturday),
      const Offset(0.0, -200.0),
    );
    await tester.pumpAndSettle();
    expect(vertical.pixels, greaterThan(before));
    expect(find.text("New item"), findsNothing);
    vertical.jumpTo(before);
    await tester.pumpAndSettle();

    // A press on a flinging grid stops it and creates nothing, for a touch
    // tap and for a mouse drag alike.
    await tester.flingFrom(
      centerOf(tester, from, saturday),
      const Offset(0.0, -150.0),
      2000.0,
    );
    await tester.pump(oneFrame);
    await tester.pump(oneFrame);
    expect(vertical.isScrollingNotifier.value, isTrue);
    await tester.tapAt(centerOf(tester, from, saturday));
    await tester.pumpAndSettle();
    expect(find.text("New item"), findsNothing);
    vertical.jumpTo(before);
    await tester.pumpAndSettle();
    await tester.flingFrom(
      centerOf(tester, from, saturday),
      const Offset(0.0, -150.0),
      2000.0,
    );
    await tester.pump(oneFrame);
    await tester.pump(oneFrame);
    expect(vertical.isScrollingNotifier.value, isTrue);
    gesture = await tester.startGesture(
      centerOf(tester, from, saturday),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(centerOf(tester, from, sunday));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text("New item"), findsNothing);
    vertical.jumpTo(before);
    await tester.pumpAndSettle();

    // A held range fills its rectangle; a cancel clears it.
    gesture = await tester.startGesture(
      centerOf(tester, from, saturday),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(centerOf(tester, to, sunday));
    await tester.pump();
    final viewport = weekViewport(tester);
    final covered = viewport
        .rectOfCell(from, saturday)!
        .expandToInclude(viewport.rectOfCell(to, sunday)!);
    var canvas = paintWeekBackground(tester);
    expect(
      canvas.fillsOf(HarborColors.primaryTint).where((rect) {
        return rect.contains(covered.topLeft + const Offset(1.0, 1.0)) &&
            rect.contains(covered.bottomRight - const Offset(1.0, 1.0));
      }),
      isNotEmpty,
    );
    await gesture.cancel();
    await tester.pump();
    await tester.pump(oneFrame);
    expect(find.text("New item"), findsNothing);
    canvas = paintWeekBackground(tester);
    final saturdayColumn = viewport.rectOfCell(from, saturday)!;
    expect(
      canvas.fillsOf(HarborColors.primaryTint).where((rect) {
        return rect.left < saturdayColumn.right &&
            rect.right > saturdayColumn.left;
      }),
      isEmpty,
    );

    // A range over today's column is marked apart from that column's fill.
    final tuesday = colOf(1);
    gesture = await tester.startGesture(
      centerOf(tester, rowOf(16 * 60), tuesday),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(centerOf(tester, rowOf(16 * 60 + 45), tuesday));
    await tester.pump();
    canvas = paintWeekBackground(tester);
    final todayColumn = viewport.rectOfCell(rowOf(16 * 60), tuesday)!;
    expect(
      canvas.records
          .where((record) {
            return !record.isLine &&
                !record.isIn(HarborColors.primaryTint) &&
                record.rect!.overlaps(todayColumn);
          })
          .where((record) {
            return !record.isIn(HarborColors.surface) &&
                !record.isIn(HarborColors.background);
          }),
      isNotEmpty,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text("Task").last);
    await tester.pumpAndSettle();
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    // A scroll under a held range moves its focus with the content.
    gesture = await tester.startGesture(
      centerOf(tester, from, saturday),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(centerOf(tester, to, sunday));
    await tester.pump();
    vertical.jumpTo(vertical.pixels + 64.0);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await expectForm("14:00", "16:00", "2");
    vertical.jumpTo(before);
    await tester.pumpAndSettle();

    expect(api.requests.where((r) => r.method != CalendarMethod.list), isEmpty);
  });

  testWidgets("W3 a second press while a range runs starts nothing of its "
      "own", (tester) async {
    final api = await pumpCalendar(tester);
    await pickMode(tester, "Week");
    final saturday = colOf(5);
    final sunday = colOf(6);
    final from = rowOf(14 * 60);
    final to = rowOf(14 * 60 + 45);
    final gesture = await tester.startGesture(
      centerOf(tester, from, saturday),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(centerOf(tester, to, sunday));
    await tester.pump();
    final second = await tester.startGesture(
      centerOf(tester, rowOf(12 * 60), colOf(3)),
      kind: PointerDeviceKind.mouse,
      pointer: 7,
    );
    await second.moveTo(centerOf(tester, rowOf(12 * 60 + 15), colOf(4)));
    await tester.pump();
    // The painted range is still the first one.
    final viewport = weekViewport(tester);
    final pressed = viewport.rectOfCell(rowOf(12 * 60), colOf(3))!;
    var canvas = paintWeekBackground(tester);
    expect(
      canvas.fillsOf(HarborColors.primaryTint).where((rect) {
        return rect.overlaps(pressed.deflate(1.0));
      }),
      isEmpty,
    );
    await second.up();
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // One flow opens, the first range's.
    expect(find.text("New item"), findsOneWidget);
    await tester.tap(find.text("Task").last);
    await tester.pumpAndSettle();
    expect(find.text("2026-04-25"), findsOneWidget);
    expect(fieldText(tester, "Days"), "2");
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();
    expect(find.text("New item"), findsNothing);
    canvas = paintWeekBackground(tester);
    final saturdayColumn = viewport.rectOfCell(from, saturday)!;
    expect(
      canvas.fillsOf(HarborColors.primaryTint).where((rect) {
        return rect.left < saturdayColumn.right &&
            rect.right > saturdayColumn.left;
      }),
      isEmpty,
    );
    expect(api.requests.where((r) => r.method != CalendarMethod.list), isEmpty);
  });

  testWidgets("W4 the form validates before sending", (tester) async {
    final api = await pumpCalendar(tester);
    await pickMode(tester, "Week");
    final requests = api.requests.length;

    await createAt(tester, rowOf(14 * 60), colOf(5), "Deadline");
    await tester.enterText(fieldFinder("Title"), "Ship");
    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: fieldFinder("Project"),
        matching: find.text("Project is required."),
      ),
      findsOneWidget,
    );
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await createAt(tester, rowOf(14 * 60), colOf(5), "Meeting");
    await tester.enterText(fieldFinder("Title"), "  ");
    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: fieldFinder("Title"),
        matching: find.text("Enter a title."),
      ),
      findsOneWidget,
    );
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await createAt(tester, rowOf(14 * 60), colOf(5), "Meeting");
    await tester.enterText(fieldFinder("Title"), "Review");
    await tester.enterText(fieldFinder("Days"), "x");
    await tester.tap(saveFinder());
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: fieldFinder("Days"),
        matching: find.text("The item covers 1 to 366 days."),
      ),
      findsOneWidget,
    );
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(requests));
  });

  testWidgets("W5 a move is pending until the API answers", (tester) async {
    // Two seconds hold the first move pending through the two long presses
    // and the tap after it.
    const latency = Duration(seconds: 2);
    final api = await pumpCalendar(
      tester,
      api: MockCalendarApi.seeded(today, latency: latency),
    );
    await pickMode(tester, "Week");
    final requests = api.requests.length;

    final saturday = cellRect(tester, rowOf(14 * 60), colOf(5));
    await moveBlock(tester, blockFinder(brainstormId), saturday.topLeft);
    expect(api.requests, hasLength(requests + 1));
    expect(
      tester.getRect(blockFinder(brainstormId)).topLeft,
      nearOffset(saturday.topLeft),
    );
    expect(fadeOf(tester, blockFinder(brainstormId)), 0.5);
    expect(
      indicatorSizeIn(tester, blockFinder(brainstormId)),
      const Size(12.0, 12.0),
    );
    final scope = tester.widget<BoardItemDragScope>(
      find
          .ancestor(
            of: blockFinder(brainstormId),
            matching: find.byType(BoardItemDragScope),
          )
          .first,
    );
    expect(scope.canDrag, isFalse);

    // A second drag of the pending block moves nothing and sends nothing,
    // and a tap opens no form. The refused lift leaves the touch to the
    // grid's scrollable, so the block is compared with its slot as the
    // slot now paints.
    await moveBlock(
      tester,
      blockFinder(brainstormId),
      cellRect(tester, rowOf(16 * 60), colOf(6)).topLeft,
    );
    await tester.pump(oneFrame);
    expect(
      tester.getRect(blockFinder(brainstormId)).topLeft,
      nearOffset(cellRect(tester, rowOf(14 * 60), colOf(5)).topLeft),
    );
    expect(api.requests, hasLength(requests + 1));
    await tester.tap(blockFinder(brainstormId));
    await tester.pump();
    await tester.pump(oneFrame);
    expect(find.text("Edit Task"), findsNothing);

    // Another item moves meanwhile, and the first move's answer lands
    // while that block is held over its target: the sync it causes leaves
    // the drag running, and the drop still commits.
    final thursday = cellRect(tester, rowOf(10 * 60), colOf(3));
    final uxFlow = tester.getRect(blockFinder(uxFlowId));
    final held = await tester.startGesture(uxFlow.center);
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await held.moveBy(thursday.topLeft - uxFlow.topLeft);
    await tester.pump();
    expect(api.requests, hasLength(requests + 1));
    await tester.pump(const Duration(milliseconds: 900));
    expect(model(tester).isLocked(brainstormId), isFalse);
    await held.up();
    await tester.pump();
    await tester.pump(weekGridAnimationStyle.effectiveDropSettle.duration);
    expect(api.requests, hasLength(requests + 2));
    expect(
      tester.getRect(blockFinder(uxFlowId)).topLeft,
      nearOffset(thursday.topLeft),
    );

    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(
      (await stored(tester, api, brainstormId)).day,
      DateTime(2026, 4, 25),
    );

    // A failed move slides back to the stored slot and reports.
    api.failurePolicy = (request) {
      return request.method == CalendarMethod.update ? "Saving failed." : null;
    };
    final tuesday = cellRect(tester, rowOf(14 * 60), colOf(1));
    await moveBlock(tester, blockFinder(brainstormId), tuesday.topLeft);
    expect(tester.getRect(blockFinder(brainstormId)).left, near(tuesday.left));
    await tester.pump(latency);
    await tester.pump(oneFrame);
    final sliding = tester.getRect(blockFinder(brainstormId)).left;
    expect(sliding, greaterThan(tuesday.left + 1.0));
    expect(sliding, lessThan(saturday.left - 1.0));
    await tester.pumpAndSettle();
    expect(tester.getRect(blockFinder(brainstormId)).left, near(saturday.left));
    expect(find.text("Saving failed."), findsOneWidget);
  });

  testWidgets("W6 refused drops", (tester) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    await createBeforePump(
      tester,
      api,
      taskJson("Quick check", DateTime(2026, 4, 23), 12 * 60, 12 * 60 + 15),
    );
    await createBeforePump(
      tester,
      api,
      taskJson(
        "Handover",
        DateTime(2026, 4, 17),
        18 * 60,
        19 * 60,
        dayCount: 4,
      ),
    );
    await createBeforePump(
      tester,
      api,
      taskJson("Retreat", DateTime(2026, 4, 25), 19 * 60, 20 * 60, dayCount: 3),
    );
    await createBeforePump(
      tester,
      api,
      taskJson(
        "Late shift",
        DateTime(2026, 4, 26),
        21 * 60,
        22 * 60,
        dayCount: 3,
      ),
    );
    final quickCheck = await idOn(
      tester,
      api,
      DateTime(2026, 4, 23),
      "Quick check",
    );
    final handover = await idOn(tester, api, DateTime(2026, 4, 20), "Handover");
    final retreat = await idOn(tester, api, DateTime(2026, 4, 25), "Retreat");
    final lateShift = await idOn(
      tester,
      api,
      DateTime(2026, 4, 26),
      "Late shift",
    );
    await pumpCalendar(tester, api: api, size: tall);
    await pickMode(tester, "Week");
    final requests = api.requests.length;

    /// Drops [id] at [target] and expects it back in its slot with nothing
    /// sent. The grid's own refusals show no snackbar, where a refusal the
    /// model makes at the drop reports one.
    Future<void> refused(String id, Offset target, {bool byGrid = true}) async {
      final before = tester.getRect(blockFinder(id));
      await moveBlock(tester, blockFinder(id), target);
      if (byGrid) {
        expect(find.byType(SnackBar), findsNothing, reason: id);
      }
      await tester.pumpAndSettle();
      expect(tester.getRect(blockFinder(id)), before, reason: id);
      expect(api.requests, hasLength(requests), reason: id);
    }

    // Into "Day off".
    await refused(
      brainstormId,
      cellRect(tester, rowOf(14 * 60), colOf(0)).topLeft,
    );
    // Onto the hour gutter, from Sunday: one column there would move the
    // Sunday-to-Tuesday Task a week earlier, onto Monday and Tuesday, so
    // the gutter test alone refuses it. Then onto the header row.
    await refused(lateShift, cellRect(tester, rowOf(21 * 60), 0).topLeft);
    await refused(quickCheck, cellRect(tester, 0, colOf(3)).topLeft);
    // One column right puts the clipped Friday-to-Monday Task on Monday
    // 16:00, inside "Day off".
    await refused(handover, cellRect(tester, rowOf(16 * 60), colOf(1)).topLeft);

    // Saturday 17:00 puts the Saturday-to-Monday Task on Monday
    // 2026-04-27 over "Retro prep", which the grid does not show but the
    // model has read with April.
    await refused(
      retreat,
      cellRect(tester, rowOf(17 * 60), colOf(5)).topLeft,
      byGrid: false,
    );
    expect(
      find.text(const CalendarOverlapException(<String>[retroPrepId]).message),
      findsOneWidget,
    );
  });

  testWidgets("W7 a block opens its form, saves an edit and deletes", (
    tester,
  ) async {
    const latency = Duration(seconds: 1);
    final api = await pumpCalendar(
      tester,
      api: MockCalendarApi.seeded(today, latency: latency),
    );
    await pickMode(tester, "Week");

    await tester.tap(blockFinder(designCritiqueId));
    await tester.pumpAndSettle();
    expect(find.text("Edit Meeting"), findsOneWidget);
    expect(textColorOf(tester, find.text("Meeting")), HarborColors.text);
    expect(
      find.ancestor(
        of: find.text("Meeting"),
        matching: find.byWidgetPredicate((widget) {
          return widget is DropdownButtonFormField || widget is DropdownButton;
        }),
      ),
      findsNothing,
    );

    await tester.enterText(fieldFinder("Title"), "Design review");
    await tester.tap(saveFinder());
    await tester.pump();
    expect(isEnabled(tester, formButton("Delete")), isFalse);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      textColorOf(
        tester,
        find.descendant(
          of: formButton("Delete"),
          matching: find.text("Delete"),
        ),
      ),
      const Color(0xFF5B6677),
    );
    // While the save runs the block shows the stored item.
    expect(
      find.descendant(
        of: blockFinder(designCritiqueId),
        matching: find.text("Design critique"),
      ),
      findsOneWidget,
    );
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(find.text("Edit Meeting"), findsNothing);
    expect(
      find.descendant(
        of: blockFinder(designCritiqueId),
        matching: find.text("Design review"),
      ),
      findsOneWidget,
    );
    await pickMode(tester, "Month");
    await tester.tap(find.byKey(dayCellKey(DateTime(2026, 4, 23))));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(itemCardKey(designCritiqueId)),
        matching: find.text("Design review"),
      ),
      findsOneWidget,
    );

    await pickMode(tester, "Week");
    await tester.tap(blockFinder(designCritiqueId));
    await tester.pumpAndSettle();
    await tester.tap(formButton("Delete"));
    await tester.pumpAndSettle();
    expect(find.text("Delete item?"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, "Cancel").last);
    await tester.pumpAndSettle();
    expect(find.text("Edit Meeting"), findsOneWidget);
    await tester.tap(formButton("Delete"));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, "Delete").last);
    // Not settled: the pending block's indicator would keep it pumping
    // through the delete's latency.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Edit Meeting"), findsNothing);
    expect(fadeOf(tester, blockFinder(designCritiqueId)), 0.5);
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(blockFinder(designCritiqueId), findsNothing);
    expect(api.requests.last.method, CalendarMethod.delete);
  });

  testWidgets("W8 Add and the FAB open Week mode", (tester) async {
    await pumpCalendar(tester);

    await tester.tap(find.byTooltip("Add"));
    await tester.pumpAndSettle();
    expect(blockFinder(designCritiqueId), findsOneWidget);
    expect(find.byTooltip("Add"), findsNothing);
    expect(find.byTooltip("Add item"), findsNothing);

    await pickMode(tester, "Month");
    await tester.tap(find.byTooltip("Add item"));
    await tester.pumpAndSettle();
    expect(blockFinder(designCritiqueId), findsOneWidget);

    // From the Board tab, whatever the calendar's mode.
    await tester.tap(find.text("Board"));
    await tester.pumpAndSettle();
    expect(find.byTooltip("Add"), findsOneWidget);
    await tester.tap(find.byTooltip("Add"));
    await tester.pumpAndSettle();
    expect(blockFinder(designCritiqueId), findsOneWidget);

    await pickMode(tester, "Month");
    await tester.tap(find.text("Board"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Add"));
    await tester.pumpAndSettle();
    expect(blockFinder(designCritiqueId), findsOneWidget);
  });

  testWidgets("W9 a pending move shows in Month mode", (tester) async {
    const latency = Duration(seconds: 2);
    final api = await pumpCalendar(
      tester,
      api: MockCalendarApi.seeded(today, latency: latency),
    );
    await pickMode(tester, "Week");
    api.failurePolicy = (request) {
      return request.method == CalendarMethod.update ? "Saving failed." : null;
    };

    await moveBlock(
      tester,
      blockFinder(uxFlowId),
      cellRect(tester, rowOf(10 * 60), colOf(3)).topLeft,
    );
    await tester.tap(find.byTooltip("Calendar view"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text("Month").last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(dayCellKey(DateTime(2026, 4, 23))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final card = find.byKey(itemCardKey(uxFlowId));
    expect(fadeOf(tester, card), 0.5);
    expect(indicatorSizeIn(tester, card), const Size(12.0, 12.0));
    expect(
      tester
          .widget<PopupMenuButton<Object?>>(
            find.descendant(
              of: card,
              matching: find.byWidgetPredicate((widget) {
                return widget is PopupMenuButton;
              }),
            ),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(find.byKey(dayCellKey(today)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(card, findsNothing);

    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(find.text("Saving failed."), findsOneWidget);
    expect(card, findsOneWidget);
    expect(fadeOf(tester, card), 1.0);
    expect(
      tester
          .widget<PopupMenuButton<Object?>>(
            find.descendant(
              of: card,
              matching: find.byWidgetPredicate((widget) {
                return widget is PopupMenuButton;
              }),
            ),
          )
          .enabled,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets("W10 a press off the empty body cells never creates", (
    tester,
  ) async {
    const latency = Duration(seconds: 1);
    await pumpCalendar(
      tester,
      api: MockCalendarApi.seeded(today, latency: latency),
    );
    await pickMode(tester, "Week");

    // A mouse drag that starts on a block.
    var gesture = await tester.startGesture(
      tester.getCenter(blockFinder(brainstormId)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(centerOf(tester, rowOf(14 * 60), colOf(5)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text("New item"), findsNothing);

    // A touch press held on a pending block.
    await moveBlock(
      tester,
      blockFinder(brainstormId),
      cellRect(tester, rowOf(14 * 60), colOf(4)).topLeft,
    );
    gesture = await tester.startGesture(
      tester.getCenter(blockFinder(brainstormId)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();
    await tester.pump(oneFrame);
    expect(find.text("New item"), findsNothing);
    await tester.pump(latency);
    await tester.pumpAndSettle();

    // A mouse drag from Saturday's header down into the body.
    gesture = await tester.startGesture(
      tester.getCenter(headerFinder(DateTime(2026, 4, 25))),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(centerOf(tester, rowOf(14 * 60), colOf(5)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text("New item"), findsNothing);

    // A tap on the hour gutter beside an empty slot.
    await tapCell(tester, rowOf(14 * 60), 0);
    expect(find.text("New item"), findsNothing);
  });

  testWidgets("W11 a new week does not animate", (tester) async {
    final api = await pumpCalendar(tester);
    await pickMode(tester, "Week");
    final enterExit = weekGridAnimationStyle.effectiveItemEnterExit.duration;

    // The next week shows at once.
    final nextWeek = await listAll(
      tester,
      api,
      addDays(monday, 7),
      addDays(monday, 13),
    );
    await tester.tap(find.byTooltip("Next week"));
    await tester.pump();
    await tester.pump(oneFrame);
    final widths = <String, double>{};
    for (final item in nextWeek) {
      final id = item["id"]! as String;
      if (blockFinder(id).evaluate().isNotEmpty) {
        widths[id] = tester.getSize(blockFinder(id)).width;
      }
    }
    expect(widths, isNotEmpty);
    await tester.pump(enterExit);
    for (final entry in widths.entries) {
      expect(
        tester.getSize(blockFinder(entry.key)).width,
        entry.value,
        reason: entry.key,
      );
    }
    await tester.pumpAndSettle();

    // A new week settles an exit in flight.
    await tester.tap(find.byTooltip("Previous week"));
    await tester.pumpAndSettle();
    await tester.tap(blockFinder(designCritiqueId));
    await tester.pumpAndSettle();
    await tester.tap(formButton("Delete"));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, "Delete").last);
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pump(enterExit ~/ 3);
    final dayWidth = cellRect(tester, rowOf(15 * 60), colOf(3)).width;
    expect(
      tester.getSize(blockFinder(designCritiqueId)).width,
      lessThan(dayWidth - 1.0),
      reason: "mid-exit",
    );
    await tester.tap(find.byTooltip("Next week"));
    await tester.pump();
    await tester.pump(oneFrame);
    expect(blockFinder(designCritiqueId), findsNothing);
    await tester.pumpAndSettle();

    // A new week settles an enter in flight.
    await tester.tap(find.byTooltip("Previous week"));
    await tester.pumpAndSettle();
    await createAt(tester, rowOf(14 * 60), colOf(2), "Meeting");
    await tester.enterText(fieldFinder("Title"), "Sync");
    await tester.tap(saveFinder());
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pump(enterExit ~/ 3);
    expect(
      tester.getSize(blockTitled("Sync")).width,
      lessThan(dayWidth - 1.0),
      reason: "mid-enter",
    );
    await tester.tap(find.byTooltip("Next week"));
    await tester.pump();
    await tester.pump(oneFrame);
    expect(blockTitled("Sync"), findsNothing);
    await tester.pumpAndSettle();

    // An unread week shows nothing until its read answers.
    await tester.tap(find.byTooltip("Next week"));
    await tester.pump();
    await tester.pump(oneFrame);
    for (final item in nextWeek) {
      expect(blockFinder(item["id"]! as String), findsNothing);
    }
    expect(
      find.descendant(
        of: find.byType(WeekGrid),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
  });

  testWidgets("W12 _commit sends nothing for an unchanged drop or a locked "
      "item", (tester) async {
    final api = await pumpCalendar(
      tester,
      api: MockCalendarApi.seeded(today, latency: const Duration(seconds: 1)),
    );
    await pickMode(tester, "Week");
    final requests = api.requests.length;

    final rect = tester.getRect(blockFinder(brainstormId));
    await moveBlock(tester, blockFinder(brainstormId), rect.topLeft);
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(requests));

    final semantics = tester.ensureSemantics();
    var node = tester.getSemantics(blockFinder(brainstormId));
    final action = CustomSemanticsAction.getIdentifier(
      const CustomSemanticsAction(label: "Move right"),
    );
    // The board puts the move actions on the item host's container node,
    // which holds the block's own.
    while (!(node.getSemanticsData().customSemanticsActionIds ?? <int>[])
        .contains(action)) {
      node = node.parent!;
    }
    Object? thrown;
    try {
      for (var i = 0; i < 2; i++) {
        tester.binding.performSemanticsAction(
          SemanticsActionEvent(
            type: SemanticsAction.customAction,
            nodeId: node.id,
            viewId: tester.view.viewId,
            arguments: action,
          ),
        );
      }
    } on Object catch (error) {
      thrown = error;
    }
    expect(thrown, isNull);
    expect(api.requests, hasLength(requests + 1));
    await tester.pump();
    await tester.pump(oneFrame);
    expect(find.byType(SnackBar), findsNothing);
    semantics.dispose();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets("W13 API errors show in the form", (tester) async {
    final api = await pumpCalendar(tester, size: tall);
    await pickMode(tester, "Week");

    await createAt(tester, rowOf(18 * 60), colOf(0), "Task");
    await tester.enterText(fieldFinder("Title"), "Dentist");
    await chooseOption(tester, "Start", "10:00");
    await chooseOption(tester, "End", "11:00");
    await tester.tap(saveFinder());
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    expect(
      find.text(const CalendarOverlapException(<String>[]).message),
      findsOneWidget,
    );
    expect(find.text("New Task"), findsOneWidget);
    expect(fieldText(tester, "Title"), "Dentist");

    await chooseOption(tester, "Start", "18:00", delta: 100.0);
    await chooseOption(tester, "End", "19:00", delta: 100.0);
    api.failurePolicy = (request) {
      return "The server is down.";
    };
    await tester.tap(saveFinder());
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    expect(find.text("The server is down."), findsOneWidget);
    expect(fieldText(tester, "Title"), "Dentist");
    expect(find.byType(SnackBar), findsNothing);

    api.failurePolicy = null;
    await tester.tap(saveFinder());
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    expect(find.text("New Task"), findsNothing);
  });

  testWidgets("W14 the resize strips and Share", (tester) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    await createBeforePump(
      tester,
      api,
      taskJson("Retreat", DateTime(2026, 4, 25), 19 * 60, 20 * 60, dayCount: 3),
    );
    await createBeforePump(
      tester,
      api,
      taskJson(
        "Handover",
        DateTime(2026, 4, 17),
        18 * 60,
        19 * 60,
        dayCount: 4,
      ),
    );
    await createBeforePump(
      tester,
      api,
      taskJson(
        "Year plan",
        DateTime(2025, 4, 20),
        20 * 60,
        21 * 60,
        dayCount: maxDayCount,
      ),
    );
    final retreat = await idOn(tester, api, DateTime(2026, 4, 25), "Retreat");
    final handover = await idOn(tester, api, DateTime(2026, 4, 20), "Handover");
    final yearPlan = await idOn(
      tester,
      api,
      DateTime(2026, 4, 20),
      "Year plan",
    );
    await pumpCalendar(tester, api: api, size: tall);
    await pickMode(tester, "Week");

    final board = tester.widget<Board<String, ShownItem>>(
      find.byType(Board<String, ShownItem>),
    );
    expect(board.drag!.resizeEdges, BoardResizeEdges.trailing);
    expect(board.drag!.primaryResizeEdges, BoardResizeEdges.trailing);
    final dayWidth = cellRect(tester, rowOf(9 * 60), colOf(0)).width;
    final slot = cellRect(tester, rowOf(9 * 60), colOf(0)).height;

    /// Drags a strip of [id]'s block with a mouse, which the grid's
    /// scrollable never takes, then lets the write it causes complete.
    Future<void> dragStrip(String id, Offset strip, Offset delta) async {
      final gesture = await tester.startGesture(
        strip,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(delta);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(api.latency);
      await tester.pumpAndSettle();
    }

    Offset bottomStrip(String id) {
      final rect = tester.getRect(blockFinder(id));
      return Offset(rect.center.dx, rect.bottom - 3.0);
    }

    Offset rightStrip(String id) {
      final rect = tester.getRect(blockFinder(id));
      return Offset(rect.right - 3.0, rect.center.dy);
    }

    await dragStrip(
      brainstormId,
      bottomStrip(brainstormId),
      Offset(0.0, 2 * slot),
    );
    expect((await stored(tester, api, brainstormId)).endMinute, 15 * 60 + 30);

    // The right strip onto Wednesday, where a single-day item holds
    // 11:00 to 12:00, would make a two-day item share it.
    var requests = api.requests.length;
    final uxFlow = tester.getRect(blockFinder(uxFlowId));
    await dragStrip(uxFlowId, rightStrip(uxFlowId), Offset(dayWidth, 0.0));
    expect(api.requests, hasLength(requests));
    expect(tester.getRect(blockFinder(uxFlowId)), uxFlow);

    // Single-day items share their day.
    await moveBlock(
      tester,
      blockFinder(brainstormId),
      cellRect(tester, rowOf(11 * 60), colOf(2)).topLeft,
    );
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(blockFinder(brainstormId)).width,
      lessThan(dayWidth - 1.0),
    );
    expect(
      tester.getSize(blockFinder(reviewId)).width,
      lessThan(dayWidth - 1.0),
    );

    // The right strip of an item that ends after the week ends it on the
    // column it is dropped on.
    await dragStrip(retreat, rightStrip(retreat), Offset(-dayWidth, 0.0));
    final shortened = await stored(tester, api, retreat);
    expect(shortened.day, DateTime(2026, 4, 25));
    expect(shortened.dayCount, 1);

    // The right strip of an item that starts before the week keeps its
    // first day.
    await dragStrip(handover, rightStrip(handover), Offset(6 * dayWidth, 0.0));
    final lengthened = await stored(tester, api, handover);
    expect(lengthened.day, DateTime(2026, 4, 17));
    expect(lengthened.dayCount, 10);
    await tester.tap(blockFinder(handover));
    await tester.pumpAndSettle();
    expect(fieldText(tester, "Days"), "10");
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    // A drop that would make an item longer than the longest allowed is
    // refused.
    requests = api.requests.length;
    final year = tester.getRect(blockFinder(yearPlan));
    await dragStrip(yearPlan, rightStrip(yearPlan), Offset(dayWidth, 0.0));
    expect(api.requests, hasLength(requests));
    expect(tester.getRect(blockFinder(yearPlan)), year);
  });

  testWidgets("W15 a range drag lays nothing out", (tester) async {
    await pumpCalendar(tester, size: tall);
    await pickMode(tester, "Week");
    final viewport = weekViewport(tester);
    final row = rowOf(18 * 60);
    final col = colOf(2);

    final gesture = await tester.startGesture(
      centerOf(tester, row, col),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final layouts = viewport.debugPerformLayoutCount;
    final blocks = <Key, Widget>{
      for (final element in find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith("block-");
      }).evaluate())
        element.widget.key!: element.widget,
    };
    expect(blocks, isNotEmpty);
    final scopes = <Key, BoardItemDragScope>{
      for (final key in blocks.keys)
        key: tester.widget<BoardItemDragScope>(
          find
              .ancestor(
                of: find.byKey(key),
                matching: find.byType(BoardItemDragScope),
              )
              .first,
        ),
    };
    final steps = <({int row, int col})>[
      (row: row, col: col + 1),
      (row: row, col: col + 2),
      (row: row, col: col + 3),
      (row: row + 1, col: col + 3),
      (row: row + 2, col: col + 3),
      (row: row + 3, col: col + 3),
    ];
    for (final step in steps) {
      await gesture.moveTo(centerOf(tester, step.row, step.col));
      await tester.pump();
    }
    final painter = viewport.background;
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(2.0, 0.0));
      await tester.pump();
    }
    expect(viewport.debugPerformLayoutCount, layouts);
    for (final entry in blocks.entries) {
      expect(
        identical(tester.widget(find.byKey(entry.key)), entry.value),
        isTrue,
        reason: "${entry.key}",
      );
      final scope = tester.widget<BoardItemDragScope>(
        find
            .ancestor(
              of: find.byKey(entry.key),
              matching: find.byType(BoardItemDragScope),
            )
            .first,
      );
      expect(
        identical(scope, scopes[entry.key]),
        isTrue,
        reason: "${entry.key}",
      );
    }
    expect(identical(viewport.background, painter), isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text("Task").last);
    await tester.pumpAndSettle();
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();
  });

  testWidgets("W16 the frozen bands and the fit", (tester) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Week");
    final mondayHeader = headerFinder(monday);
    final boardTop = tester.getRect(find.byType(Board<String, ShownItem>)).top;
    expect(tester.getRect(mondayHeader).top, boardTop);
    final noonLabel = find.text("12:00");
    final noonTop = tester.getRect(noonLabel).top;
    await tester.dragFrom(
      centerOf(tester, rowOf(12 * 60), colOf(5)),
      const Offset(0.0, -200.0),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(mondayHeader).top, boardTop);
    expect(tester.getRect(noonLabel).top, lessThan(noonTop - 100.0));

    tester.view.physicalSize = const Size(320.0, 640.0);
    await tester.pumpAndSettle();
    // Back to 08:00, whose label the narrow grid shows.
    final slot = cellRect(tester, rowOf(8 * 60), colOf(0)).height;
    weekViewport(tester).verticalPosition!.jumpTo(slot * (rowOf(8 * 60) - 1));
    await tester.pumpAndSettle();
    final eightLabel = find.text("08:00");
    final eightLeft = tester.getRect(eightLabel).left;
    final headerLeft = tester.getRect(mondayHeader).left;
    final horizontal = weekViewport(tester).horizontalPosition!;
    expect(horizontal.maxScrollExtent, greaterThan(1.0));
    await tester.dragFrom(
      centerOf(tester, rowOf(9 * 60), colOf(5)),
      const Offset(-100.0, 0.0),
    );
    await tester.pumpAndSettle();
    expect(horizontal.pixels, greaterThan(0.0));
    expect(tester.getRect(eightLabel).left, eightLeft);
    expect(tester.getRect(mondayHeader).left, lessThan(headerLeft - 1.0));

    final board = find.byType(Board<String, ShownItem>);
    final columns = tester
        .widget<Board<String, ShownItem>>(board)
        .controller
        .columns;
    tester.view.physicalSize = const Size(330.0, 640.0);
    await tester.pump();
    expect(
      identical(
        tester.widget<Board<String, ShownItem>>(board).controller.columns,
        columns,
      ),
      isTrue,
    );
  });

  testWidgets("W17 the form maps each field kind", (tester) async {
    final api = await pumpCalendar(tester);
    await pickMode(tester, "Week");
    final wednesday = DateTime(2026, 4, 22);

    await createAt(tester, rowOf(14 * 60), colOf(2), "Task");
    expect(dropdownFinder("Status"), findsOneWidget);
    expect(dropdownFinder("Priority"), findsOneWidget);
    await tester.tap(dropdownFinder("Status"));
    await tester.pumpAndSettle();
    for (final label in <String>["To do", "In progress", "Done"]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    await tester.tap(find.text("In progress").last);
    await tester.pumpAndSettle();
    await tester.tap(dropdownFinder("Priority"));
    await tester.pumpAndSettle();
    for (final label in <String>["Low", "Medium", "High"]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    await tester.tap(find.text("High").last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fieldFinder("Assignee")).maxLines, 1);
    expect(tester.widget<TextField>(fieldFinder("Notes")).maxLines, isNot(1));
    await tester.enterText(fieldFinder("Title"), "Prepare");
    await tester.enterText(fieldFinder("Assignee"), "Sam");
    await tester.enterText(fieldFinder("Notes"), "a");
    await tester.tap(saveFinder());
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    final task = await stored(
      tester,
      api,
      await idOn(tester, api, wednesday, "Prepare"),
    );
    expect(task.fields["status"], "inProgress");
    expect(task.fields["priority"], "high");
    expect(task.fields["assignee"], "Sam");
    expect(task.fields["notes"], "a");

    await createAt(tester, rowOf(16 * 60), colOf(2), "Meeting");
    expect(tester.widget<TextField>(fieldFinder("Video link")).maxLines, 1);
    await tester.enterText(fieldFinder("Title"), "Huddle");
    await tester.enterText(fieldFinder("Attendees"), " Ana, Ben ,, ");
    await tester.enterText(fieldFinder("Video link"), "https://x.example");
    await tester.tap(saveFinder());
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    final huddleId = await idOn(tester, api, wednesday, "Huddle");
    final huddle = await stored(tester, api, huddleId);
    expect(huddle.fields["attendees"], <String>["Ana", "Ben"]);
    await tester.tap(blockFinder(huddleId));
    await tester.pumpAndSettle();
    expect(fieldText(tester, "Attendees"), "Ana, Ben");
    await tester.tap(formButton("Cancel"));
    await tester.pumpAndSettle();

    await createAt(tester, rowOf(12 * 60), colOf(2), "Deadline");
    expect(
      find.descendant(
        of: find.widgetWithText(SwitchListTile, "Met"),
        matching: find.byType(Switch),
      ),
      findsOneWidget,
    );
    await tester.enterText(fieldFinder("Title"), "Ship it");
    await tester.enterText(fieldFinder("Project"), "P");
    await tester.tap(find.widgetWithText(SwitchListTile, "Met"));
    await tester.pumpAndSettle();
    await tester.tap(saveFinder());
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    final deadline = await stored(
      tester,
      api,
      await idOn(tester, api, wednesday, "Ship it"),
    );
    expect(deadline.fields["met"], true);
  });

  testWidgets("W18 the painter paints only what shows, with the same paints "
      "and colours", (tester) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Week");
    final viewport = weekViewport(tester);
    final first = paintWeekBackground(tester);
    final second = paintWeekBackground(tester);
    final rows = viewport.lastVisibleRow - viewport.firstVisibleRow + 1;
    final cols = viewport.lastVisibleCol - viewport.firstVisibleCol + 1;
    expect(rows, lessThan(96));
    for (final canvas in <RecordingCanvas>[first, second]) {
      expect(canvas.lines.length, lessThanOrEqualTo(rows + cols));
    }
    for (final record in second.records) {
      expect(
        first.records.any((other) => identical(other.paint, record.paint)),
        isTrue,
      );
    }
    // The scrolled region is where the visible body cells show.
    final body = viewport.scrolledRegion;
    expect(
      first.fillsOf(HarborColors.surface).where((rect) {
        return rect.contains(body.topLeft) &&
            rect.contains(body.bottomRight - const Offset(1.0, 1.0));
      }),
      isNotEmpty,
    );
    Rect column(int col) {
      return viewport.visibleCellRect(viewport.firstVisibleRow, col);
    }

    bool covers(Rect fill, int col) {
      final rect = column(col);
      return fill.left <= rect.left + 0.5 && fill.right >= rect.right - 0.5;
    }

    bool meets(Rect fill, int col) {
      final rect = column(col);
      return fill.left < rect.right - 0.5 && fill.right > rect.left + 0.5;
    }

    final weekend = first.fillsOf(HarborColors.background).toList();
    expect(weekend.where((fill) => covers(fill, colOf(5))), isNotEmpty);
    expect(weekend.where((fill) => covers(fill, colOf(6))), isNotEmpty);
    for (var weekday = 0; weekday < 5; weekday++) {
      expect(weekend.where((fill) => meets(fill, colOf(weekday))), isEmpty);
    }
    final tinted = first.fillsOf(HarborColors.primaryTint).toList();
    expect(tinted.where((fill) => covers(fill, colOf(1))), isNotEmpty);
    for (var weekday = 0; weekday < 7; weekday++) {
      if (weekday == 1) {
        continue;
      }
      expect(tinted.where((fill) => meets(fill, colOf(weekday))), isEmpty);
    }
    for (final line in first.lines) {
      expect(line.color.toARGB32(), HarborColors.outline.toARGB32());
    }
  });

  testWidgets("W18 a narrow grid scrolled sideways draws lines for the day "
      "columns it shows alone", (tester) async {
    await pumpCalendar(tester, size: const Size(320.0, 640.0));
    await pickMode(tester, "Week");
    final horizontal = weekViewport(tester).horizontalPosition!;
    horizontal.jumpTo(horizontal.maxScrollExtent);
    await tester.pumpAndSettle();
    final viewport = weekViewport(tester);
    final canvas = paintWeekBackground(tester);
    final shown = <int>{
      for (
        var col = viewport.firstVisibleCol;
        col <= viewport.lastVisibleCol;
        col++
      )
        col,
    };
    expect(shown.length, lessThan(7));
    final verticalLines = canvas.lines.where((line) {
      return line.from!.dx == line.to!.dx;
    }).toList();
    expect(verticalLines, hasLength(shown.length));
    for (final line in verticalLines) {
      final x = line.from!.dx;
      expect(
        shown.any((col) {
          return (viewport.visibleCellRect(viewport.firstVisibleRow, col).left -
                      x)
                  .abs() <
              0.5;
        }),
        isTrue,
      );
    }
  });
}
