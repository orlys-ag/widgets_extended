/// A pinch of two fingers on Week's, Day's and Month's grids: what it
/// zooms, around which point, within which sizes, and what the fingers
/// that pinched do not do.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_data.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_settings.dart';
import 'package:workspace_calendar/workspace_calendar/month_board.dart';
import 'package:workspace_calendar/workspace_calendar/settings_sheet.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';

import 'calendar_harness.dart';

/// Two touches [spread] apart along [axis] around [focal], each moved
/// [step] further from the other on each of [steps] frames, closer for a
/// negative step, with [eachFrame] called after each frame, then lifted.
Future<void> pinch(
  WidgetTester tester,
  Offset focal, {
  required Axis axis,
  required double step,
  double spread = 60.0,
  int steps = 6,
  void Function()? eachFrame,
}) async {
  final unit = axis == Axis.vertical
      ? const Offset(0.0, 1.0)
      : const Offset(1.0, 0.0);
  final first = await tester.startGesture(focal - unit * (spread / 2.0));
  final second = await tester.startGesture(focal + unit * (spread / 2.0));
  await tester.pump();
  for (var i = 0; i < steps; i++) {
    await first.moveBy(-unit * step);
    await second.moveBy(unit * step);
    await tester.pump();
    eachFrame?.call();
  }
  await first.up();
  await second.up();
  await tester.pumpAndSettle();
}

/// Week's slot at [minute] on [weekday]'s column.
Rect slotRect(WidgetTester tester, int minute, int weekday) {
  return cellRect(tester, rowOf(minute), colOf(weekday));
}

/// The value of the settings sheet's slider [key], with the sheet opened
/// and closed again.
Future<double> sliderValue(WidgetTester tester, Key key) async {
  await openSettings(tester);
  final value = tester.widget<Slider>(find.byKey(key)).value;
  await tester.tapAt(const Offset(195.0, 20.0));
  await tester.pumpAndSettle();
  return value;
}

/// The month board's cell of [day].
Rect monthDayRect(WidgetTester tester, DateTime day) {
  return tester.getRect(
    find.byKey(ValueKey<String>("month-day-${isoDate(day)}")),
  );
}

/// A pinch whose first finger stays on [still] while the second, landing
/// [offset] from it, moves down by 32, [hold] after, then the second
/// lifted and the first: past the pinch's slop and short of a pan's
/// ([kPanSlop]), so no pan claims the fingers, and the scrollable's pan,
/// which stops tracking with the second finger, leaves the first one's
/// tap or long press to reach the grid.
Future<void> pinchFrom(
  WidgetTester tester,
  Offset still, {
  Offset offset = const Offset(0.0, 40.0),
  Duration hold = Duration.zero,
}) async {
  final first = await tester.startGesture(still);
  final second = await tester.startGesture(still + offset);
  for (var i = 0; i < 4; i++) {
    await second.moveBy(const Offset(0.0, 8.0));
    await tester.pump();
  }
  if (hold > Duration.zero) {
    await tester.pump(hold);
  }
  await second.up();
  await first.up();
  await tester.pumpAndSettle();
}

/// That the point [fraction] of the way down (or across) [before] lies
/// on [focal]'s line in [after] as it did in [before].
void expectHeld(Rect before, Rect after, Offset focal, Axis axis) {
  if (axis == Axis.vertical) {
    final fraction = (focal.dy - before.top) / before.height;
    expect(after.top + fraction * after.height, moreOrLessEquals(focal.dy));
  } else {
    final fraction = (focal.dx - before.left) / before.width;
    expect(after.left + fraction * after.width, moreOrLessEquals(focal.dx));
  }
}

void main() {
  testWidgets("Z1 in Week a pinch up and down zooms the slots around the "
      "point between the fingers, from the height shown up to the most the "
      "settings offer and down to the least, which the settings then hold", (
    tester,
  ) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Week");
    final before = slotRect(tester, 12 * 60, 2);
    final focal = before.center;
    await pinch(
      tester,
      focal,
      axis: Axis.vertical,
      step: 6.0,
      eachFrame: () {
        expectHeld(before, slotRect(tester, 12 * 60, 2), focal, Axis.vertical);
      },
    );
    expect(
      slotRect(tester, 12 * 60, 2).height,
      greaterThan(before.height * 1.3),
    );

    await pinch(tester, focal, axis: Axis.vertical, step: 8.0, steps: 20);
    expect(
      slotRect(tester, 12 * 60, 2).height,
      moreOrLessEquals(minSlotHeightHigh),
    );

    await pinch(
      tester,
      focal,
      axis: Axis.vertical,
      step: -7.0,
      steps: 20,
      spread: 300.0,
    );
    expect(await sliderValue(tester, slotHeightSliderKey), minSlotHeightLow);
  });

  testWidgets("Z2 in Week a pinch across zooms the days around the point "
      "between the fingers up to the most width the settings offer; in Day, "
      "one column wide, it zooms nothing", (tester) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Week");
    final before = slotRect(tester, 12 * 60, 2);
    final focal = before.center;
    await pinch(
      tester,
      focal,
      axis: Axis.horizontal,
      step: 6.0,
      eachFrame: () {
        expectHeld(
          before,
          slotRect(tester, 12 * 60, 2),
          focal,
          Axis.horizontal,
        );
      },
    );
    expect(slotRect(tester, 12 * 60, 2).width, greaterThan(before.width * 1.3));
    await pinch(tester, focal, axis: Axis.horizontal, step: 8.0, steps: 20);
    expect(
      slotRect(tester, 12 * 60, 2).width,
      moreOrLessEquals(minDayWidthHigh),
    );

    await pickMode(tester, "Day");
    final day = cellRect(tester, dayRowOf(12 * 60), 1);
    await pinch(tester, day.center, axis: Axis.horizontal, step: -4.0);
    expect(await sliderValue(tester, dayWidthSliderKey), minDayWidthHigh);
  });

  testWidgets("Z3 two fingers dragged together do not scroll Week, and one "
      "finger scrolls it again after", (tester) async {
    await pumpCalendar(tester, editing: true);
    await pickMode(tester, "Week");
    final vertical = gridViewport(tester).verticalPosition!;
    final pixels = vertical.pixels;
    // Saturday is empty from 12:00 to 15:00.
    final focal = slotRect(tester, 13 * 60, 5).center;
    final first = await tester.startGesture(focal);
    final second = await tester.startGesture(focal + const Offset(0.0, 60.0));
    for (var i = 0; i < 6; i++) {
      await first.moveBy(const Offset(0.0, -10.0));
      await second.moveBy(const Offset(0.0, -10.0));
      await tester.pump();
    }
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(gridViewport(tester).verticalPosition!.pixels, pixels);

    await tester.drag(find.byType(TimedGrid), const Offset(0.0, -100.0));
    await tester.pumpAndSettle();
    expect(
      gridViewport(tester).verticalPosition!.pixels,
      greaterThan(pixels + 50.0),
    );
  });

  testWidgets("Z4 in Month a pinch up and down zooms the weeks around the "
      "point between the fingers, from their share of the board up to three "
      "times it, and a pinch across the days", (tester) async {
    await pumpCalendar(tester);
    await pickMode(tester, "Month");
    final day = DateTime(2026, 4, 15);
    final before = monthDayRect(tester, day);
    final focal = before.center;
    await pinch(
      tester,
      focal,
      axis: Axis.vertical,
      step: 6.0,
      eachFrame: () {
        expectHeld(before, monthDayRect(tester, day), focal, Axis.vertical);
      },
    );
    expect(monthDayRect(tester, day).height, greaterThan(before.height * 1.3));

    await pinch(tester, focal, axis: Axis.vertical, step: 8.0, steps: 20);
    expect(
      monthDayRect(tester, day).height,
      moreOrLessEquals(maxMonthWeekScale * before.height, epsilon: 0.1),
    );

    await pinch(
      tester,
      focal,
      axis: Axis.vertical,
      step: -7.0,
      steps: 20,
      spread: 300.0,
    );
    expect(monthDayRect(tester, day).height, before.height);
    expect(
      await sliderValue(tester, slotHeightSliderKey),
      defaultMinSlotHeight,
    );

    final narrow = monthDayRect(tester, day);
    await pinch(
      tester,
      narrow.center,
      axis: Axis.horizontal,
      step: 6.0,
      eachFrame: () {
        expectHeld(
          narrow,
          monthDayRect(tester, day),
          narrow.center,
          Axis.horizontal,
        );
      },
    );
    expect(monthDayRect(tester, day).width, greaterThan(narrow.width * 1.3));
  });

  testWidgets("Z5 in Month a finger that pinched opens no item from a chip "
      "or day when it lifts, and creates nothing when it is held", (
    tester,
  ) async {
    await pumpCalendar(tester, editing: true);
    await pickMode(tester, "Month");
    final day = DateTime(2026, 4, 15);
    final before = monthDayRect(tester, day);
    final chip = find.byKey(
      monthChipKey(monthSegmentKey(uxFlowId, DateTime(2026, 4, 20))),
    );
    await pinchFrom(tester, tester.getCenter(chip));
    // Setup sanity: the fingers pinched.
    expect(monthDayRect(tester, day).height, greaterThan(before.height));
    expect(find.text("Edit Task"), findsNothing);

    await pinchFrom(tester, monthDayRect(tester, day).center);
    expect(find.byType(TimedGrid), findsNothing);

    await pinchFrom(
      tester,
      monthDayRect(tester, day).bottomCenter - const Offset(0.0, 4.0),
      offset: const Offset(0.0, -40.0),
      hold: const Duration(milliseconds: 600),
    );
    expect(find.text("New item"), findsNothing);
  });

  testWidgets("Z6 in Week no pinch starts while a block is lifted", (
    tester,
  ) async {
    await pumpCalendar(tester, editing: true);
    await pickMode(tester, "Week");
    final slot = slotRect(tester, 11 * 60, 1).height;
    final block = tester.getRect(blockFinder(uxFlowId)).center;
    final first = await tester.startGesture(block);
    await tester.pump(const Duration(milliseconds: 600));
    final second = await tester.startGesture(block + const Offset(0.0, 40.0));
    for (var i = 0; i < 6; i++) {
      await second.moveBy(const Offset(0.0, 10.0));
      await tester.pump();
    }
    expect(slotRect(tester, 11 * 60, 1).height, slot);
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
  });

  testWidgets("Z7 in Week a finger that pinched keeps a selected block "
      "selected when it lifts off it", (tester) async {
    await pumpCalendar(tester, editing: true);
    await pickMode(tester, "Week");
    await selectBlock(tester, brainstormId);
    // Setup sanity: the long press selected the block.
    expect(find.byKey(blockHandlesKey(brainstormId)), findsOneWidget);
    await pinchFrom(tester, slotRect(tester, 13 * 60, 5).center);
    expect(find.byKey(blockHandlesKey(brainstormId)), findsOneWidget);
  });
}
