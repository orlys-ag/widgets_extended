/// What the calendar shows while the range it shows is read: the list's
/// progress indicator and error, the markers meanwhile, and the week
/// grid's overlay.
library;

import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/day_cell.dart';
import 'package:workspace_calendar/workspace_calendar/day_list.dart';
import 'package:workspace_calendar/workspace_calendar/item_card.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';
import 'package:workspace_calendar/workspace_calendar/week_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_harness.dart';

const Duration latency = Duration(seconds: 1);
const Duration oneFrame = Duration(milliseconds: 16);

/// The loading row of May 21, the day a step to May from April 21
/// selects.
final Finder loading = find.byKey(dayListLoadingKey(DateTime(2026, 5, 21)));

Finder dayFinder(DateTime day) {
  return find.byKey(dayCellKey(day));
}

Finder gridFinder() {
  return find.byKey(const ValueKey<String>("calendar-grid"));
}

double rowHeight(WidgetTester tester) {
  return tester.getSize(find.byType(DayCell).first).height;
}

bool hasMarker(WidgetTester tester, DateTime day) {
  return tester.widget<DayCell>(dayFinder(day)).hasItems;
}

/// The week grid's overlay: what covers the grid while its week is not
/// ready.
Finder overlayShowing(Finder content) {
  return find.descendant(of: find.byType(TimedGrid), matching: content);
}

/// Pumps 400 ms of frames, in which the list scrolls to a newly
/// selected day.
Future<void> revealFrames(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

int listCalls(MockCalendarApi api) {
  return api.requests.where((request) {
    return request.method == CalendarMethod.list;
  }).length;
}

void main() {
  testWidgets("F1 reads cover the visible range", (tester) async {
    final api = await pumpCalendar(
      tester,
      editing: true,
      api: MockCalendarApi.seeded(today, latency: latency),
    );

    await tester.tap(find.byTooltip("Next month"));
    await revealFrames(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(loading, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(loading, findsNothing);
    expect(
      find.descendant(
        of: find.byKey(itemCardKey(releasePlanningId)),
        matching: find.text("Release planning"),
      ),
      findsOneWidget,
    );

    // A failed read shows its error and Retry in each day it left
    // unread, and the month still folds and unfolds.
    api.failurePolicy = (request) {
      return request.method == CalendarMethod.list ? "Reading failed." : null;
    };
    await tester.tap(find.byTooltip("Next month"));
    await tester.pump();
    await tester.pump(latency);
    await tester.pumpAndSettle();
    final failed = find.byKey(dayListFailedKey(DateTime(2026, 6, 21)));
    final retry = find.descendant(
      of: failed,
      matching: find.widgetWithText(TextButton, "Retry"),
    );
    expect(
      find.descendant(of: failed, matching: find.text("Reading failed.")),
      findsOneWidget,
    );
    expect(retry, findsOneWidget);
    final row = rowHeight(tester);
    await tester.drag(find.byType(DayList), const Offset(0.0, -120.0));
    await tester.pumpAndSettle();
    expect(tester.getSize(gridFinder()).height, row);
    await tester.drag(find.byType(WeekStrip), const Offset(0.0, 120.0));
    await tester.pumpAndSettle();
    expect(tester.getSize(gridFinder()).height, 5 * row);
    expect(
      tester.getRect(dayFinder(DateTime(2026, 6, 1))).topLeft,
      tester.getRect(gridFinder()).topLeft,
    );
    await tester.tap(dayFinder(DateTime(2026, 6, 21)));
    await tester.pumpAndSettle();

    api.failurePolicy = null;
    final reads = listCalls(api);
    await tester.tap(retry);
    await tester.pump();
    expect(listCalls(api), reads + 1);
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(find.text("Sunday, June 21"), findsOneWidget);
    expect(find.byKey(dayListGapKey(DateTime(2026, 6, 21), 0)), findsOneWidget);
    await tester.tap(dayFinder(DateTime(2026, 6, 4)));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(itemCardKey(designSystemSyncId)),
        matching: find.text("Design system sync"),
      ),
      findsOneWidget,
    );

    // Months and weeks already read send nothing.
    final requests = api.requests.length;
    await tester.tap(find.byTooltip("Previous month"));
    await tester.pumpAndSettle();
    expect(find.text("May 2026"), findsOneWidget);
    await tester.tap(find.byTooltip("Previous month"));
    await tester.pumpAndSettle();
    expect(find.text("Apr 2026"), findsOneWidget);
    await tester.tap(dayFinder(today));
    await tester.pumpAndSettle();
    await pickMode(tester, "Week");
    expect(find.byKey(dayHeaderKey(monday)), findsOneWidget);
    expect(api.requests, hasLength(requests));
  });

  testWidgets("F2 markers while the shown range loads", (tester) async {
    await pumpCalendar(
      tester,
      editing: true,
      api: MockCalendarApi.seeded(today, latency: latency),
    );

    await tester.tap(find.byTooltip("Next month"));
    await revealFrames(tester);
    expect(loading, findsOneWidget);
    // Read with April before May showed.
    expect(hasMarker(tester, DateTime(2026, 4, 27)), isTrue);
    // Read with May, which the shown range waits on.
    expect(hasMarker(tester, DateTime(2026, 5, 21)), isFalse);
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(hasMarker(tester, DateTime(2026, 4, 27)), isTrue);
    expect(hasMarker(tester, DateTime(2026, 5, 21)), isTrue);
  });

  testWidgets("F3 an unread week shows the overlay", (tester) async {
    await pumpCalendar(
      tester,
      api: MockCalendarApi.seeded(today, latency: latency),
    );
    await pickMode(tester, "Week");
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next week"));
    await tester.pump();
    await tester.pump(oneFrame);
    expect(
      overlayShowing(find.byType(CircularProgressIndicator)),
      findsOneWidget,
    );
    await tester.tapAt(cellRect(tester, rowOf(14 * 60), colOf(2)).center);
    await tester.pump();
    await tester.pump(oneFrame);
    expect(find.text("New item"), findsNothing);

    // One frame after the read's answer the overlay is gone and the week's
    // blocks show at full width.
    await tester.pump(latency);
    await tester.pump(oneFrame);
    expect(
      overlayShowing(find.byType(CircularProgressIndicator)),
      findsNothing,
    );
    expect(blockFinder(teamOffsiteId), findsOneWidget);
    final widths = <String, double>{};
    for (final element in find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith("block-");
    }).evaluate()) {
      final key = element.widget.key! as ValueKey<String>;
      widths[key.value] = tester.getSize(find.byKey(key)).width;
    }
    expect(widths, contains("block-$teamOffsiteId"));
    await tester.pump(
      gridAnimationStyle(tester).effectiveItemEnterExit.duration,
    );
    for (final entry in widths.entries) {
      expect(
        tester.getSize(find.byKey(ValueKey<String>(entry.key))).width,
        entry.value,
        reason: entry.key,
      );
    }
    await tester.pumpAndSettle();
  });

  testWidgets("F3 a failed read of an unread week shows its error and Retry "
      "in the overlay", (tester) async {
    final api = await pumpCalendar(
      tester,
      api: MockCalendarApi.seeded(today, latency: latency),
    );
    await pickMode(tester, "Week");
    api.failurePolicy = (request) {
      return request.method == CalendarMethod.list ? "Reading failed." : null;
    };
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next week"));
    await tester.pump();
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(overlayShowing(find.text("Reading failed.")), findsOneWidget);
    final retry = overlayShowing(find.widgetWithText(TextButton, "Retry"));
    expect(retry, findsOneWidget);

    api.failurePolicy = null;
    await tester.tap(retry);
    await tester.pump();
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(overlayShowing(find.text("Reading failed.")), findsNothing);
    expect(blockFinder(teamOffsiteId), findsOneWidget);
  });
}
