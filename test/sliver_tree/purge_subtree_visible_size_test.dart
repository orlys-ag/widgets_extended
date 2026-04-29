/// Regression for visible-subtree-size cache going stale when a parent
/// pending-deletion node finalizes while its descendants still have their
/// own in-flight standalone exit animations.
///
/// The bug: when the parent's exit animation completed first, its
/// `_finalizeAnimation` only counted descendants that had no standalone
/// (and would be purged in the same call) toward `visibleLoss`. Descendants
/// with their own standalone were excluded, on the assumption they would
/// "finalize separately and decrement themselves." But by the time those
/// descendants actually finalized, the parent's nid was already in the
/// free pool — so `_parentKeyOfKey(desc)` returned null, the descendant's
/// own `visibleLoss` block was skipped, and the cache for the surviving
/// ancestor stayed inflated by the missed descendant count.
///
/// The fix: count every visible pending-deletion descendant in the
/// parent's `visibleLoss`, regardless of whether they have standalone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("removing a subtree with multiple visible descendants keeps "
      "_visibleSubtreeSizeByNid consistent across exit-animation finalize",
      (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 100),
    );
    addTearDown(controller.dispose);

    controller.setRoots([const TreeNode(key: "root", data: "root")]);
    controller.setChildren("root", [
      const TreeNode(key: "branch", data: "branch"),
      const TreeNode(key: "sibling", data: "sibling"),
    ]);
    controller.setChildren("branch", [
      const TreeNode(key: "leaf1", data: "leaf1"),
      const TreeNode(key: "leaf2", data: "leaf2"),
      const TreeNode(key: "leaf3", data: "leaf3"),
    ]);
    controller.expand(key: "root", animate: false);
    controller.expand(key: "branch", animate: false);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          SliverTree<String, String>(
            controller: controller,
            nodeBuilder: (_, key, _) =>
                SizedBox(height: 40, child: Text(key)),
          ),
        ]),
      ),
    ));
    await tester.pump();

    // Sanity: 6 visible (root, branch, 3 leaves, sibling).
    expect(controller.visibleNodeCount, 6);
    controller.debugAssertVisibleSubtreeSizeConsistency();

    controller.remove(key: "branch", animate: true);
    // Drive the exit animations to completion.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // After remove + finalize, only root + sibling remain.
    expect(controller.visibleNodeCount, 2);

    // The cache for root must read the actual visible subtree size
    // (= 1 self + 1 sibling = 2). Pre-fix it stayed at 5 because the
    // 3 leaf decrements never reached root.
    controller.debugAssertVisibleSubtreeSizeConsistency();

    // Downstream effect: insert under root computes
    // insertIndex = parentVisibleIndex + _visibleSubtreeSizeByNid[root].
    // With the inflated cache, insertIndex was 5 (past _order.length=2),
    // leaving "fresh" stranded in an out-of-bounds order slot and
    // corrupting the visible buffer.
    controller.insert(
      parentKey: "root",
      node: const TreeNode(key: "fresh", data: "fresh"),
      animate: false,
    );
    expect(
      controller.visibleNodes.toList(),
      equals(<String>["root", "sibling", "fresh"]),
    );
    controller.debugAssertVisibleSubtreeSizeConsistency();
  });

  testWidgets("removing a deeply nested subtree where every level has its "
      "own standalone exit animation keeps the cache consistent",
      (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 100),
    );
    addTearDown(controller.dispose);

    // root → a → b → c → d (all visible, all expanded)
    controller.setRoots([const TreeNode(key: "root", data: "root")]);
    controller.setChildren("root", [const TreeNode(key: "a", data: "a")]);
    controller.setChildren("a", [const TreeNode(key: "b", data: "b")]);
    controller.setChildren("b", [const TreeNode(key: "c", data: "c")]);
    controller.setChildren("c", [const TreeNode(key: "d", data: "d")]);
    for (final k in const ["root", "a", "b", "c"]) {
      controller.expand(key: k, animate: false);
    }

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          SliverTree<String, String>(
            controller: controller,
            nodeBuilder: (_, key, _) =>
                SizedBox(height: 40, child: Text(key)),
          ),
        ]),
      ),
    ));
    await tester.pump();

    expect(controller.visibleNodeCount, 5);
    controller.debugAssertVisibleSubtreeSizeConsistency();

    controller.remove(key: "a", animate: true);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(controller.visibleNodeCount, 1);
    controller.debugAssertVisibleSubtreeSizeConsistency();
  });
}
