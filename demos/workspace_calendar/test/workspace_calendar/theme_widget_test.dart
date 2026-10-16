/// The demo keeps the Harbor theme under a host with its own theme, in
/// its own widgets and in the dialogs it opens.
library;

import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/day_cell.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/item_card.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_harness.dart';

Finder dayFinder(DateTime day) {
  return find.byKey(dayCellKey(day));
}

Color textColorOf(WidgetTester tester, Finder text) {
  return tester.renderObject<RenderParagraph>(text).text.style!.color!;
}

/// The fill of the [BoxDecoration] of the first [DecoratedBox] or
/// [Container] under [finder] that has one with a colour.
BoxDecoration decorationIn(WidgetTester tester, Finder finder) {
  for (final element
      in find
          .descendant(
            of: finder,
            matching: find.byWidgetPredicate((widget) {
              return widget is DecoratedBox || widget is Container;
            }),
          )
          .evaluate()) {
    final widget = element.widget;
    final decoration = widget is DecoratedBox
        ? widget.decoration
        : (widget as Container).decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      return decoration;
    }
  }
  throw StateError("No coloured box under $finder.");
}

void main() {
  testWidgets("V1 the demo keeps its theme under a deepPurple host", (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390.0, 844.0);
    addTearDown(tester.view.reset);
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: WorkspaceCalendarExample(today: today, api: api),
      ),
    );
    await tester.pump(api.latency);
    await tester.pumpAndSettle();

    final appBarMaterial = tester.widget<Material>(
      find
          .descendant(of: find.byType(AppBar), matching: find.byType(Material))
          .first,
    );
    expect(appBarMaterial.color, HarborColors.primary);
    final scaffoldMaterial = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(Scaffold),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(scaffoldMaterial.color, HarborColors.background);

    // Today is selected: its pill is primary with a white number.
    final todayCell = dayFinder(today);
    expect(decorationIn(tester, todayCell).color, HarborColors.primary);
    expect(
      textColorOf(
        tester,
        find.descendant(of: todayCell, matching: find.text("21")),
      ),
      HarborColors.onPrimary,
    );
    // Another day's marker is a primary ring.
    final thursday = dayFinder(DateTime(2026, 4, 23));
    final ring = tester
        .widgetList<Container>(
          find.descendant(of: thursday, matching: find.byType(Container)),
        )
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .singleWhere((decoration) => decoration.shape == BoxShape.circle);
    expect((ring.border! as Border).top.color, HarborColors.primary);

    await tester.tap(thursday);
    await tester.pumpAndSettle();
    expect(
      textColorOf(
        tester,
        find.descendant(of: todayCell, matching: find.text("21")),
      ),
      HarborColors.primary,
    );
    final card = find.byKey(itemCardKey(designCritiqueId));
    final cardFill = decorationIn(tester, card);
    expect(cardFill.color, const Color(0xFFE0ECEB));
    expect((cardFill.border! as Border).left.width, 4.0);
    expect((cardFill.border! as Border).left.color, const Color(0xFF1F7A72));
    final icons = tester
        .widgetList<Icon>(
          find.descendant(of: card, matching: find.byType(Icon)),
        )
        .toList();
    expect(
      icons.singleWhere((icon) => icon.icon == Icons.groups).color,
      const Color(0xFF1F7A72),
    );
    expect(
      icons.singleWhere((icon) => icon.icon == Icons.more_horiz).color,
      const Color(0xFF5B6677),
    );

    // The card's menu opens the delete prompt under the demo's theme.
    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip("Item actions")),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text("Delete").last);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text("Delete item?"))).colorScheme.primary,
      HarborColors.primary,
    );
    await tester.tap(find.widgetWithText(TextButton, "Cancel"));
    await tester.pumpAndSettle();

    // The block and the drag config.
    await pickMode(tester, "Week");
    final block = blockFinder(designCritiqueId);
    final blockFill = decorationIn(tester, block);
    expect(blockFill.color, const Color(0xFFE0ECEB));
    expect((blockFill.border! as Border).left.width, 4.0);
    expect((blockFill.border! as Border).left.color, const Color(0xFF1F7A72));
    final board = tester.widget<Board<String, ShownItem>>(
      find.byType(Board<String, ShownItem>),
    );
    expect(board.drag!.draggedItemOpacity, harborDraggedItemOpacity);

    // The block opens its form under the demo's theme.
    await tester.tap(block);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text("Edit Meeting"))).colorScheme.primary,
      HarborColors.primary,
    );
    await tester.tap(find.widgetWithText(TextButton, "Cancel"));
    await tester.pumpAndSettle();

    await pickMode(tester, "Month");
    await tester.tap(dayFinder(DateTime(2026, 4, 25)));
    await tester.pumpAndSettle();
    expect(
      textColorOf(tester, find.text("No items on this day.")),
      HarborColors.textMuted,
    );
  });
}
