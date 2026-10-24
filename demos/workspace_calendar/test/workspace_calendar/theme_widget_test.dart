/// The demo keeps the Harbor theme under a host with its own theme, in
/// its own widgets and in the dialogs and menus it opens, and its views
/// draw Harbor's calendar theme under a host's own [CalendarTheme].
library;

import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
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

/// Pumps the editing calendar on [today] at 390x844 under a host that
/// places the built-in [CalendarTheme] above its navigator, and settles.
Future<void> pumpUnderHostTheme(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(390.0, 844.0);
  addTearDown(tester.view.reset);
  final api = MockCalendarApi.seeded(today, latency: harnessLatency);
  await tester.pumpWidget(
    MaterialApp(
      // The M3 ink sparkle shader cannot load under the test binding.
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      builder: (context, child) {
        return CalendarTheme(data: const CalendarThemeData(), child: child!);
      },
      home: WorkspaceCalendarExample(editing: true, today: today, api: api),
    ),
  );
  await tester.pump(api.latency);
  await tester.pumpAndSettle();
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
        home: WorkspaceCalendarExample(editing: true, today: today, api: api),
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
    // Another day's marker is its meeting's Harbor badge.
    final thursday = dayFinder(DateTime(2026, 4, 23));
    final badge = tester.widget<DecoratedBox>(
      find.byKey(dayBadgeKey(DateTime(2026, 4, 23))),
    );
    expect(
      (badge.decoration as BoxDecoration).color,
      harborTypeStyleOf(CalendarItemType.meeting).edge,
    );

    await tester.tap(thursday);
    await tester.pumpAndSettle();
    expect(
      textColorOf(
        tester,
        find.descendant(of: todayCell, matching: find.text("21")),
      ),
      HarborColors.primary,
    );
    final card = find.byKey(entryCardKey(designCritiqueId));
    final cardFill = decorationIn(tester, card);
    expect(cardFill.color, const Color(0xFFE0ECEB));
    expect(cardFill.borderRadius, BorderRadius.circular(16.0));
    expect(cardFill.border, isNull);
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
      find.descendant(
        of: card,
        matching: find.bySemanticsLabel("Item actions"),
      ),
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
    final board = tester.widget<Board<GridKey, GridShape<ItemPayload>>>(
      find.byType(Board<GridKey, GridShape<ItemPayload>>),
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

    await pickMode(tester, "Agenda");
    await tester.tap(dayFinder(DateTime(2026, 4, 25)));
    await tester.pumpAndSettle();
    expect(
      textColorOf(
        tester,
        find.descendant(
          of: find.byKey(dayListGapKey(DateTime(2026, 4, 25), 0)),
          matching: find.text("00:00"),
        ),
      ),
      HarborColors.textMuted,
    );
  });

  testWidgets("V2 the card menu's route reads Harbor's calendar theme under "
      "a host's own", (tester) async {
    await pumpUnderHostTheme(tester);
    await tester.tap(dayFinder(DateTime(2026, 4, 23)));
    await tester.pumpAndSettle();
    final card = find.byKey(entryCardKey(designCritiqueId));
    await tester.tap(
      find.descendant(
        of: card,
        matching: find.bySemanticsLabel("Item actions"),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      CalendarTheme.of(tester.element(find.text("Delete").last)),
      same(harborCalendarTheme),
    );
  });

  testWidgets("V3 the views draw Harbor's calendar theme under a host's "
      "own", (tester) async {
    await pumpUnderHostTheme(tester);
    expect(decorationIn(tester, dayFinder(today)).color, HarborColors.primary);
    await tester.tap(dayFinder(DateTime(2026, 4, 23)));
    await tester.pumpAndSettle();
    final card = find.byKey(entryCardKey(designCritiqueId));
    expect(
      textColorOf(
        tester,
        find.descendant(of: card, matching: find.byType(Text)).first,
      ),
      HarborColors.text,
    );

    await pickMode(tester, "Week");
    expect(
      paintGridBackground(tester).fillsOf(HarborColors.surface),
      isNotEmpty,
    );
    expect(
      textColorOf(
        tester,
        find
            .descendant(
              of: blockFinder(designCritiqueId),
              matching: find.byType(Text),
            )
            .first,
      ),
      HarborColors.text,
    );
  });
}
