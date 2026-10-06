/// The day list: deleting from a card's menu, the animations of the writes
/// the list can see, and a failed delete.
library;

import 'package:examples/workspace_calendar/calendar_api.dart';
import 'package:examples/workspace_calendar/calendar_item.dart';
import 'package:examples/workspace_calendar/day_cell.dart';
import 'package:examples/workspace_calendar/item_card.dart';
import 'package:examples/workspace_calendar/mock_calendar_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_harness.dart';

const Duration oneFrame = Duration(milliseconds: 16);

Finder cardFinder(String id) {
  return find.byKey(itemCardKey(id));
}

Finder dayFinder(DateTime day) {
  return find.byKey(dayCellKey(day));
}

/// Opens [id]'s card menu and picks [action], "Edit" or "Delete".
Future<void> cardAction(WidgetTester tester, String id, String action) async {
  await tester.tap(
    find.descendant(
      of: cardFinder(id),
      matching: find.byTooltip("Item actions"),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(action).last);
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

/// The month board's viewport: the one board keyed by plain objects.
RenderBoardViewport<Object> monthViewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<Object>>()
      .singleWhere((viewport) {
        return viewport is! RenderBoardViewport<String>;
      });
}

/// Picks [option] in the dropdown labelled [label], scrolling its menu by
/// [delta] until the option shows.
Future<void> chooseOption(
  WidgetTester tester,
  String label,
  String option, {
  double delta = 100.0,
}) async {
  await tester.tap(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) {
        return widget is DropdownButtonFormField;
      }),
    ),
  );
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

void main() {
  testWidgets("L1 delete from the card menu", (tester) async {
    const latency = Duration(seconds: 1);
    final api = await pumpCalendar(
      tester,
      api: MockCalendarApi.seeded(today, latency: latency),
    );
    final requests = api.requests.length;

    await cardAction(tester, brainstormId, "Delete");
    expect(find.text("Delete item?"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, "Cancel"));
    await tester.pumpAndSettle();
    expect(cardFinder(brainstormId), findsOneWidget);
    expect(api.requests, hasLength(requests));

    await cardAction(tester, brainstormId, "Delete");
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    // Not settled: the pending card's indicator would keep it pumping
    // through the delete's latency.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fadeOf(tester, cardFinder(brainstormId)), 0.5);
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(cardFinder(brainstormId), findsNothing);
    await pickMode(tester, "Week");
    expect(blockFinder(brainstormId), findsNothing);
    await pickMode(tester, "Month");

    // The last item of a day takes its marker with it, and the change
    // rebuilds no other cell and lays the month board out again nowhere.
    await tester.tap(dayFinder(DateTime(2026, 4, 23)));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DayCell>(dayFinder(DateTime(2026, 4, 23))).hasItems,
      isTrue,
    );
    await cardAction(tester, designCritiqueId, "Delete");
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final neighbour = tester.widget(dayFinder(DateTime(2026, 4, 22)));
    final layouts = monthViewport(tester).debugPerformLayoutCount;
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DayCell>(dayFinder(DateTime(2026, 4, 23))).hasItems,
      isFalse,
    );
    expect(
      identical(tester.widget(dayFinder(DateTime(2026, 4, 22))), neighbour),
      isTrue,
    );
    expect(monthViewport(tester).debugPerformLayoutCount, layouts);
  });

  testWidgets("L2 the list animates confirmed writes", (tester) async {
    for (final edit in <bool>[false, true]) {
      final api = await pumpCalendar(tester);
      await tester.tap(dayFinder(DateTime(2026, 4, 22)));
      await tester.pumpAndSettle();
      final standupTop = tester.getRect(cardFinder(standupId)).top;
      final reviewTop = tester.getRect(cardFinder(reviewId)).top;
      expect(reviewTop, greaterThan(standupTop));
      expect(find.byType(SyncedSliverTree<String, ShownItem>), findsOneWidget);
      if (!edit) {
        // A confirmed delete animates the card out: one frame after the
        // answer it is still there, and the card below is on its way up.
        await cardAction(tester, standupId, "Delete");
        await tester.tap(find.widgetWithText(TextButton, "Delete"));
        await tester.pump();
        await tester.pump(api.latency);
        // The list shows no motion in the first frame after the answer;
        // the check is made in the frame after that.
        await tester.pump(oneFrame);
        await tester.pump(oneFrame);
        expect(cardFinder(standupId), findsOneWidget);
        final moving = tester.getRect(cardFinder(reviewId)).top;
        expect(moving, lessThan(reviewTop));
        expect(moving, greaterThan(standupTop));
      } else {
        // A confirmed edit that moves the item past the next one slides
        // both cards.
        await cardAction(tester, standupId, "Edit");
        await chooseOption(tester, "Start", "12:00");
        await chooseOption(tester, "End", "12:30");
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        await tester.pump(api.latency);
        await tester.pump(oneFrame);
        await tester.pump(oneFrame);
        final standupMid = tester.getRect(cardFinder(standupId)).top;
        final reviewMid = tester.getRect(cardFinder(reviewId)).top;
        await tester.pumpAndSettle();
        final standupEnd = tester.getRect(cardFinder(standupId)).top;
        final reviewEnd = tester.getRect(cardFinder(reviewId)).top;
        expect(standupEnd, greaterThan(reviewEnd));
        expect(standupMid, greaterThan(standupTop));
        expect(standupMid, lessThan(standupEnd));
        expect(reviewMid, lessThan(reviewTop));
        expect(reviewMid, greaterThan(reviewEnd));
      }
      expect(find.byType(SyncedSliverTree<String, ShownItem>), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets("L3 another day's list does not animate", (tester) async {
    await pumpCalendar(tester);
    expect(cardFinder(uxFlowId), findsOneWidget);
    await tester.tap(dayFinder(DateTime(2026, 4, 22)));
    await tester.pump();
    await tester.pump(oneFrame);
    expect(cardFinder(uxFlowId), findsNothing);
    expect(cardFinder(brainstormId), findsNothing);
  });

  testWidgets("L4 a failed delete returns the card", (tester) async {
    final api = await pumpCalendar(tester);
    api.failurePolicy = (request) {
      return request.method == CalendarMethod.delete
          ? "Deleting failed."
          : null;
    };
    await cardAction(tester, brainstormId, "Delete");
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    expect(cardFinder(brainstormId), findsOneWidget);
    expect(fadeOf(tester, cardFinder(brainstormId)), 1.0);
    expect(find.text("Deleting failed."), findsOneWidget);
  });
}
