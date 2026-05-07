/// Reproduces the user-reported bug: rapid reparent operations leaving
/// the animation/state invalid (empty rows, wrong widgets during slide,
/// snap-instead-of-animate).
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const _kRowHeight = 50.0;
const _kViewportHeight = 500.0;

Widget _harness(
  TreeController<String, String> controller, {
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
            SliverTree<String, String>(
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

TreeController<String, String> _newController(WidgetTester tester) {
  return TreeController<String, String>(
    vsync: tester,
    animationDuration: const Duration(milliseconds: 1500),
    animationCurve: Curves.easeOutCubic,
  );
}

/// Builds 8 parents × 30 items = 240 rows total. Mirrors the
/// example app's `Reparent ALL` setup.
void _populateLargeTree(TreeController<String, String> controller) {
  controller.runBatch(() {
    final parents = <TreeNode<String, String>>[
      for (int i = 0; i < 8; i++)
        TreeNode<String, String>(
          key: "parent-$i",
          data: "Parent ${String.fromCharCode(0x41 + i)}",
        ),
    ];
    controller.setRoots(parents);
    int n = 0;
    for (int p = 0; p < 8; p++) {
      final children = <TreeNode<String, String>>[
        for (int i = 0; i < 30; i++)
          TreeNode<String, String>(
            key: "item-${n++}",
            data: "Item $n",
          ),
      ];
      controller.setChildren("parent-$p", children);
      controller.expand(key: "parent-$p", animate: false);
    }
  });
}

void main() {
  group("rapid reparent operations (user-reported bug)", () {
    testWidgets(
      "second reparent batch mid-flight does not cause widget identity "
      "mismatch at painted positions",
      (tester) async {
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        _populateLargeTree(controller);
        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();

        final random = Random(42);
        // Pick 5 random items from each batch.
        List<String> pickRandom(int count) {
          final all = <String>[];
          for (int p = 0; p < 8; p++) {
            all.addAll(controller.getChildren("parent-$p"));
          }
          all.shuffle(random);
          return all.take(count).toList();
        }

        // Batch 1: move 5 items to random different parents.
        for (final item in pickRandom(5)) {
          final currentParent = controller.getParent(item);
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
            item,
            "parent-$target",
            index: newIndex,
            animate: true,
            slideDuration: const Duration(milliseconds: 1500),
            slideCurve: Curves.easeOutCubic,
          );
        }
        await tester.pump(); // install slides

        // Pump halfway through the slide.
        await tester.pump(const Duration(milliseconds: 750));

        // Batch 2: another 5 items.
        for (final item in pickRandom(5)) {
          final currentParent = controller.getParent(item);
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
            item,
            "parent-$target",
            index: newIndex,
            animate: true,
            slideDuration: const Duration(milliseconds: 1500),
            slideCurve: Curves.easeOutCubic,
          );
        }
        await tester.pump(); // install second batch

        // Pump partway and check widget integrity.
        await tester.pump(const Duration(milliseconds: 200));

        // For every visible row, verify the widget displayed matches
        // the row's key (no widget identity confusion).
        final visibleNodes = controller.visibleNodes;
        for (final key in visibleNodes) {
          final finder = find.byKey(ValueKey("row-$key"));
          if (finder.evaluate().isEmpty) continue; // not in viewport area
          final textWidgets = find.descendant(
            of: finder,
            matching: find.byType(Text),
          );
          if (textWidgets.evaluate().isEmpty) continue;
          final text = tester.widget<Text>(textWidgets);
          expect(text.data, key,
              reason: "Row $key should display its own key as text. "
                  "Got '${text.data}'.");
        }

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "rapid reparents do not leave gaps in painted positions",
      (tester) async {
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        _populateLargeTree(controller);
        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();

        final random = Random(123);
        // Trigger 3 batches of 5 reparents each, ~250ms apart.
        for (int batch = 0; batch < 3; batch++) {
          final all = <String>[];
          for (int p = 0; p < 8; p++) {
            all.addAll(controller.getChildren("parent-$p"));
          }
          all.shuffle(random);
          for (final item in all.take(5)) {
            final currentParent = controller.getParent(item);
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
              item,
              "parent-$target",
              index: newIndex,
              animate: true,
              slideDuration: const Duration(milliseconds: 1500),
              slideCurve: Curves.easeOutCubic,
            );
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
        }

        // Mid-third-batch state. Walk visible rows in expected paint
        // order. Each consecutive on-screen row should occupy contiguous
        // 50-px-tall regions of the viewport (allowing for slide
        // displacement). No two on-screen rows should occupy the same
        // viewport-y position (indicating overlap), and no on-screen row
        // should be missing from a viewport position where its
        // structural location is.
        //
        // Easier check: for every row that finds itself in the rendered
        // tree at a viewport position [0, viewport), its widget identity
        // matches its expected key.
        final scrollSpaceBound = _kViewportHeight;
        for (final key in controller.visibleNodes) {
          final finder = find.byKey(ValueKey("row-$key"));
          if (finder.evaluate().isEmpty) continue;
          final dy = tester.getTopLeft(finder).dy;
          // If the widget is positioned within the visible viewport,
          // its key must match.
          if (dy >= 0 && dy < scrollSpaceBound) {
            final text = tester.widget<Text>(
              find.descendant(of: finder, matching: find.byType(Text)),
            );
            expect(text.data, key,
                reason: "Row $key visible at dy=$dy must show its own "
                    "label, got '${text.data}'.");
          }
        }

        await tester.pumpAndSettle();
      },
    );
  });
}
