/// Week's and Day's blocks take the shape of the all-day strip's chips:
/// corners of the same radius, square at an end the item continues past
/// or the grid's hours cut, and the text the same distance past the edge.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/item_builders.dart';

const String title = "Review";

ShownItem shownTask() {
  return CalendarShownEntry<ItemPayload>(
    calendarItem(
      id: "item-1",
      type: CalendarItemType.task,
      title: title,
      start: DateTime(2026, 4, 21, 9),
      end: DateTime(2026, 4, 21, 10),
      fields: const <String, Object?>{"status": "toDo"},
    ),
    pending: false,
  );
}

CalendarBlockDetails blockDetails({
  bool detailed = false,
  bool cutAtStart = false,
  bool cutAtEnd = false,
  bool continuesBefore = false,
  bool continuesAfter = false,
}) {
  return CalendarBlockDetails(
    detailed: detailed,
    tall: true,
    cutAtStart: cutAtStart,
    cutAtEnd: cutAtEnd,
    continuesBefore: continuesBefore,
    continuesAfter: continuesAfter,
  );
}

Future<void> pumpEntry(WidgetTester tester, Widget entry) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CalendarTheme(
        data: harborCalendarTheme,
        child: Center(
          child: SizedBox(width: 160.0, height: 60.0, child: entry),
        ),
      ),
    ),
  );
}

BorderRadiusGeometry? radiusIn(WidgetTester tester, Finder entry) {
  return tester
      .widget<ClipRRect>(
        find.descendant(of: entry, matching: find.byType(ClipRRect)),
      )
      .borderRadius;
}

/// How far the title's left edge lies from [entry]'s.
double insetIn(WidgetTester tester, Finder entry) {
  return tester
          .getRect(find.descendant(of: entry, matching: find.text(title)))
          .left -
      tester.getRect(entry).left;
}

void main() {
  const radius = Radius.circular(4.0);

  testWidgets("ES1 a block is rounded as a chip is, square at each end the "
      "item continues past or the hours cut", (tester) async {
    final cases = <(CalendarBlockDetails, BorderRadius)>[
      (blockDetails(), const BorderRadius.all(radius)),
      (
        blockDetails(continuesBefore: true),
        const BorderRadius.vertical(bottom: radius),
      ),
      (
        blockDetails(continuesAfter: true),
        const BorderRadius.vertical(top: radius),
      ),
      (
        blockDetails(cutAtStart: true),
        const BorderRadius.vertical(bottom: radius),
      ),
      (blockDetails(cutAtEnd: true), const BorderRadius.vertical(top: radius)),
      (
        blockDetails(continuesBefore: true, continuesAfter: true),
        BorderRadius.zero,
      ),
      (
        blockDetails(detailed: true, cutAtStart: true, continuesAfter: true),
        BorderRadius.zero,
      ),
    ];
    for (final (details, expected) in cases) {
      await pumpEntry(
        tester,
        HarborBlock(entry: shownTask(), details: details),
      );
      expect(
        radiusIn(tester, find.byType(HarborBlock)),
        expected,
        reason: "$details",
      );
    }

    await pumpEntry(
      tester,
      HarborChip(
        entry: shownTask(),
        details: const CalendarChipDetails(
          card: false,
          continuesBefore: false,
          continuesAfter: false,
        ),
      ),
    );
    expect(
      radiusIn(tester, find.byType(HarborChip)),
      const BorderRadius.horizontal(left: radius, right: radius),
    );
  });

  testWidgets("ES2 a block's title sits as far past its edge as a chip's", (
    tester,
  ) async {
    await pumpEntry(
      tester,
      HarborChip(
        entry: shownTask(),
        details: const CalendarChipDetails(
          card: false,
          continuesBefore: false,
          continuesAfter: false,
        ),
      ),
    );
    final chipInset = insetIn(tester, find.byType(HarborChip));
    expect(chipInset, 8.0);

    for (final detailed in <bool>[false, true]) {
      await pumpEntry(
        tester,
        HarborBlock(
          entry: shownTask(),
          details: blockDetails(detailed: detailed),
        ),
      );
      expect(
        insetIn(tester, find.byType(HarborBlock)),
        chipInset,
        reason: detailed ? "detailed" : "compact",
      );
    }
  });
}
