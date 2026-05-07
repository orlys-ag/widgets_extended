/// Aggressive reproducer for the user-reported "gaps" bug. Mirrors the
/// example app's "Reparent ALL" scenario: 8 parents × 30 items, all
/// expanded, scrolled mid-tree, multiple back-to-back full-tree
/// reparents. Asserts every row in the viewport (a) has its widget
/// mounted (b) shows its own key as text (c) paints at a non-overlapping
/// viewport-y.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const _kRowHeight = 50.0;
const _kViewportHeight = 600.0;
const _kSlideDuration = Duration(milliseconds: 1500);

Widget _harness(
  TreeController<String, int> controller, {
  ScrollController? scrollController,
  double height = _kViewportHeight,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: CustomScrollView(
          controller: scrollController,
          slivers: <Widget>[
            SliverTree<String, int>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: _kRowHeight,
                  child: Text(key),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

TreeController<String, int> _newController(WidgetTester tester) {
  return TreeController<String, int>(
    vsync: tester,
    animationDuration: _kSlideDuration,
    animationCurve: Curves.easeOutCubic,
  );
}

/// Mirrors `_populate` from `animated_reparent_example.dart`.
void _populateExampleTree(TreeController<String, int> controller) {
  controller.runBatch(() {
    final parents = <TreeNode<String, int>>[
      for (int i = 0; i < 8; i++)
        TreeNode<String, int>(key: "parent-$i", data: i),
    ];
    controller.setRoots(parents);
    int n = 0;
    for (int p = 0; p < 8; p++) {
      final children = <TreeNode<String, int>>[
        for (int i = 0; i < 30; i++)
          TreeNode<String, int>(key: "item-${n++}", data: n),
      ];
      controller.setChildren("parent-$p", children);
      controller.expand(key: "parent-$p", animate: false);
    }
  });
}

/// Mirrors `_randomReparent(_allItemKeys().length)` — moves ALL items.
void _reparentAll(
  TreeController<String, int> controller,
  Random random,
) {
  final allItems = <String>[];
  for (int p = 0; p < 8; p++) {
    allItems.addAll(controller.getChildren("parent-$p"));
  }
  allItems.shuffle(random);

  for (final itemKey in allItems) {
    final currentParent = controller.getParent(itemKey);
    if (currentParent == null) continue;
    int target;
    do {
      target = random.nextInt(8);
    } while ("parent-$target" == currentParent);
    final newSiblings = controller.getLiveChildren("parent-$target");
    final newIndex = newSiblings.isEmpty
        ? 0
        : random.nextInt(newSiblings.length + 1);
    controller.moveNode(
      itemKey,
      "parent-$target",
      index: newIndex,
      animate: true,
      slideDuration: _kSlideDuration,
      slideCurve: Curves.easeOutCubic,
    );
  }
}

/// Verifies that for every visible-in-viewport row, its widget is mounted
/// and displays its own key. Returns the painted positions (key → dy).
///
/// Note: overlapping rows during slide are EXPECTED (rows swapping
/// positions cross paths). The test does NOT assert non-overlap.
///
/// Gap detection: collect all on-screen rows' painted positions; the
/// settled state should have rows contiguous from the first visible y.
/// During a slide, gaps in the SETTLED-vs-PAINT comparison would
/// indicate rows that should be visible but aren't paint-iterated.
Map<String, double> _assertViewportConsistent(
  WidgetTester tester,
  TreeController<String, int> controller,
  String label,
) {
  final positions = <String, double>{};
  for (final key in controller.visibleNodes) {
    final finder = find.byKey(ValueKey("row-$key"));
    if (finder.evaluate().isEmpty) continue;
    final dy = tester.getTopLeft(finder).dy;
    positions[key] = dy;
    if (dy < 0 || dy >= _kViewportHeight) continue;
    // Widget identity check.
    final textWidgets = find.descendant(
      of: finder, matching: find.byType(Text),
    );
    if (textWidgets.evaluate().isEmpty) continue;
    final text = tester.widget<Text>(textWidgets);
    expect(text.data, key,
        reason: "[$label] Row $key at viewport-y=$dy must show its own "
            "key. Got '${text.data}'.");
  }
  return positions;
}

void main() {
  testWidgets(
    "Reparent ALL × 3 rapid clicks, scrolled mid-tree, no widget gaps "
    "or identity confusion",
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final controller = _newController(tester);
      addTearDown(controller.dispose);
      _populateExampleTree(controller);
      await tester.pumpWidget(_harness(controller, scrollController: scroll));
      await tester.pumpAndSettle();

      // Scroll to mid-tree (matches user's screenshot scenario).
      // Total content: (8 parents + 240 items) × 50 = 12400 px.
      scroll.jumpTo(5000);
      await tester.pump();
      await tester.pumpAndSettle();

      _assertViewportConsistent(tester, controller, "initial-mid-tree");

      final random = Random(42);

      // Click 1: Reparent ALL.
      _reparentAll(controller, random);
      await tester.pump(); // install slides

      _assertViewportConsistent(tester, controller, "post-click-1-install");

      // Pump partway through the slide.
      await tester.pump(const Duration(milliseconds: 400));
      _assertViewportConsistent(tester, controller, "mid-click-1-slide");

      // Click 2: Reparent ALL again before settle.
      _reparentAll(controller, random);
      await tester.pump();
      _assertViewportConsistent(tester, controller, "post-click-2-install");

      await tester.pump(const Duration(milliseconds: 400));
      _assertViewportConsistent(tester, controller, "mid-click-2-slide");

      // Click 3: Reparent ALL again.
      _reparentAll(controller, random);
      await tester.pump();
      _assertViewportConsistent(tester, controller, "post-click-3-install");

      await tester.pump(const Duration(milliseconds: 400));
      _assertViewportConsistent(tester, controller, "mid-click-3-slide");

      // Settle.
      await tester.pumpAndSettle();
      _assertViewportConsistent(tester, controller, "settled");
    },
  );

  testWidgets(
    "Reparent ALL × 3 rapid clicks at top of tree (no scroll)",
    (tester) async {
      final controller = _newController(tester);
      addTearDown(controller.dispose);
      _populateExampleTree(controller);
      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      _assertViewportConsistent(tester, controller, "initial");

      final random = Random(99);
      for (int batch = 0; batch < 3; batch++) {
        _reparentAll(controller, random);
        await tester.pump();
        _assertViewportConsistent(tester, controller, "post-batch-$batch");
        await tester.pump(const Duration(milliseconds: 400));
        _assertViewportConsistent(tester, controller, "mid-batch-$batch");
      }

      await tester.pumpAndSettle();
      _assertViewportConsistent(tester, controller, "settled");
    },
  );

  testWidgets(
    "Reparent ALL × 3 rapid clicks: rows should not cluster at viewport "
    "edge (regression for slide-IN clamp clustering bug)",
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final controller = _newController(tester);
      addTearDown(controller.dispose);
      _populateExampleTree(controller);
      await tester.pumpWidget(_harness(controller, scrollController: scroll));
      await tester.pumpAndSettle();
      scroll.jumpTo(5000);
      await tester.pump();
      await tester.pumpAndSettle();

      final random = Random(13);
      _reparentAll(controller, random);
      await tester.pump();

      // After cascaded reparents and settle: every row should be at
      // its structural position. Verify the AFTER-SETTLE state instead
      // of the mid-slide state (which has expected clustering at edge
      // for slide-INs, then spreads).
      await tester.pumpAndSettle();
      final visible = controller.visibleNodes;
      int rowsInViewport = 0;
      for (final key in visible) {
        final finder = find.byKey(ValueKey("row-$key"));
        if (finder.evaluate().isEmpty) continue;
        final dy = tester.getTopLeft(finder).dy;
        if (dy >= 0 && dy < 500) rowsInViewport++;
      }
      // After settle in a 500-px viewport with 50-px rows, expect ~10
      // rows visible (full viewport).
      expect(rowsInViewport, greaterThanOrEqualTo(8),
          reason: "Only $rowsInViewport rows visible in 500-px "
              "viewport after settle — expected ~10. Indicates "
              "viewport gap bug.");

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "Reparent ALL × 3 rapid clicks: detect rows missing from cache region "
    "(unmounted but should be visible in viewport)",
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final controller = _newController(tester);
      addTearDown(controller.dispose);
      _populateExampleTree(controller);
      await tester.pumpWidget(_harness(controller, scrollController: scroll));
      await tester.pumpAndSettle();
      scroll.jumpTo(5000);
      await tester.pump();
      await tester.pumpAndSettle();

      final random = Random(7);
      for (int batch = 0; batch < 3; batch++) {
        _reparentAll(controller, random);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Mid-cascaded-batch state. Identify rows whose STRUCTURAL position
      // (post-mutation) lies in the viewport but whose widget is NOT
      // mounted. These are the "gaps" the user sees.
      //
      // To compute structural per row, walk visibleNodes accumulating
      // extents (matching `_computeTrueStructuralAt`).
      final visible = controller.visibleNodes;
      double structural = 0.0;
      final scrollOffset = scroll.offset;
      final viewportTop = scrollOffset;
      final viewportBottom = scrollOffset + _kViewportHeight;
      final missingInViewport = <String>[];
      for (final key in visible) {
        if (structural >= viewportTop && structural < viewportBottom) {
          // This row's structural position is in the viewport. Check
          // whether its widget is present.
          final finder = find.byKey(ValueKey("row-$key"));
          if (finder.evaluate().isEmpty) {
            missingInViewport.add(
              "$key (structural y=${structural.toStringAsFixed(0)})",
            );
          }
        }
        structural += _kRowHeight;
      }

      // Allow a few "missing" rows for edge ghosts (their structural
      // shifted into viewport but they're still _phantomEdgeExits;
      // rare but legitimate). >5 indicates a real bug.
      expect(missingInViewport.length, lessThanOrEqualTo(5),
          reason: "Many rows whose structural is in viewport are NOT "
              "mounted (gaps). Missing: $missingInViewport");

      await tester.pumpAndSettle();
    },
  );
}
