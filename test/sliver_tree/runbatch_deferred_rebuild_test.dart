/// Verifies that runBatch coalesces visible-order rebuilds: K mutations
/// inside one batch produce ONE _rebuildVisibleOrder call (observed via the
/// structureGeneration counter, which the helper bumps once per rebuild)
/// rather than K. Outside a batch, behavior is unchanged — every mutation
/// rebuilds immediately.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

TreeController<String, int> _newController(WidgetTester tester) {
  return TreeController<String, int>(
    vsync: tester,
    animationDuration: Duration.zero,
  );
}

void _populate(TreeController<String, int> controller) {
  controller.runBatch(() {
    controller.setRoots([
      for (int i = 0; i < 8; i++)
        TreeNode<String, int>(key: "parent-$i", data: i),
    ]);
    int n = 0;
    for (int p = 0; p < 8; p++) {
      controller.setChildren("parent-$p", [
        for (int i = 0; i < 30; i++)
          TreeNode<String, int>(key: "item-${n++}", data: n),
      ]);
      controller.expand(key: "parent-$p", animate: false);
    }
  });
}

void main() {
  group("runBatch deferred visible-order rebuild", () {
    testWidgets(
      "reparent ALL inside runBatch bumps structureGeneration ONCE",
      (tester) async {
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        _populate(controller);

        final allItems = <String>[];
        for (int p = 0; p < 8; p++) {
          allItems.addAll(controller.getChildren("parent-$p"));
        }
        expect(allItems.length, 240);

        final genBefore = controller.structureGeneration;

        // Move every item to parent-0 inside a single batch.
        controller.runBatch(() {
          for (final itemKey in allItems) {
            controller.moveNode(itemKey, "parent-0");
          }
        });

        // Outside the batch, the order is fresh.
        expect(controller.visibleNodes.length, greaterThan(0));

        // Exactly ONE generation bump for 240 moveNode calls.
        expect(
          controller.structureGeneration - genBefore,
          1,
          reason: "240 moveNode calls in one runBatch must coalesce into "
              "ONE structural rebuild; bumping the generation per call "
              "would defeat the batching.",
        );

        // All items are now under parent-0.
        for (final itemKey in allItems) {
          expect(controller.getParent(itemKey), "parent-0");
        }
      },
    );

    testWidgets(
      "reparent ALL outside runBatch bumps structureGeneration per call "
      "(unchanged baseline behavior)",
      (tester) async {
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        _populate(controller);

        // Skip items already under parent-0 — moveNode same-parent no-arg
        // is a no-op and skips the rebuild.
        final allItems = <String>[];
        for (int p = 1; p < 8; p++) {
          allItems.addAll(controller.getChildren("parent-$p"));
        }

        final genBefore = controller.structureGeneration;

        for (final itemKey in allItems) {
          controller.moveNode(itemKey, "parent-0");
        }

        // Each call rebuilt + bumped once.
        expect(
          controller.structureGeneration - genBefore,
          allItems.length,
          reason: "Outside a batch, every moveNode rebuilds immediately, "
              "so the generation should bump once per call.",
        );
      },
    );

    testWidgets(
      "in-batch readers see deferred state via _ensureVisibleOrder",
      (tester) async {
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        _populate(controller);

        controller.runBatch(() {
          // Mutate.
          controller.moveNode("item-0", "parent-7");
          controller.moveNode("item-1", "parent-7");
          // Reading visibleNodes inside the batch must materialize the
          // deferred rebuild and reflect post-mutation state.
          final visible = controller.visibleNodes.toList();
          expect(visible.contains("item-0"), true);
          expect(controller.getParent("item-0"), "parent-7");
        });
      },
    );

    testWidgets(
      "moveNode phantom-anchor decision uses structural visibility "
      "(survives stale _order inside batch)",
      (tester) async {
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        _populate(controller);

        // Collapse parent-3 so its children are structurally hidden.
        controller.collapse(key: "parent-3", animate: false);

        // Inside a batch: first move an item INTO collapsed parent-3
        // (becomes structurally hidden), then move it back OUT to a
        // visible parent. The second move's wasVisible check must
        // reflect the post-move-1 structural state, not the stale _order.
        controller.runBatch(() {
          controller.moveNode("item-0", "parent-3"); // hides item-0
          // After move 1, item-0 is structurally hidden under collapsed
          // parent-3. Subsequent reads must agree.
          expect(controller.isVisible("item-0"), false);
          controller.moveNode("item-0", "parent-7"); // reveals it
          expect(controller.isVisible("item-0"), true);
        });

        expect(controller.getParent("item-0"), "parent-7");
        expect(controller.isVisible("item-0"), true);
      },
    );
  });
}
