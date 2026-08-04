/// Regression tests for Tier 1 partial-fix items:
///
/// C031: `moveNode(key, sameParent, index: currentIndex)` should be a
/// no-op. The prior no-op check only triggered when `index == null`;
/// an explicit-but-matching index fell through and staged a baseline
/// for layout work that produced zero visual change. Tightening the
/// check avoids the wasted work.
///
/// S014: `syncMultipleChildren` should reject (in debug mode) a
/// `desiredByParent` map where the same child key appears under more
/// than one parent. Without this check, the second `syncChildren` call
/// reparents the key from the first parent's tree (last-write-wins),
/// silently discarding the user's intent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  group("C031 — moveNode no-op for explicit matching index", () {
    testWidgets("moveNode with explicit-current index does not notify", (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);

      int structuralNotifyCount = 0;
      controller.addListener(() => structuralNotifyCount++);

      final before = structuralNotifyCount;

      // "b" is at root-index 1. moveNode("b", parentKey: null, index: 1)
      // should be a no-op now (post-C031).
      controller.moveNode("b", null, index: 1, animate: true);

      expect(
        structuralNotifyCount,
        before,
        reason: "Explicit-but-matching-index moveNode must be a no-op "
            "(no notification, no baseline staging, no layout churn)",
      );
    });

    testWidgets(
      "moveNode with explicit DIFFERENT index still fires structural",
      (tester) async {
        // Sanity: the no-op tightening must not over-prune. A different
        // explicit index should still trigger the move.
        final controller = TreeController<String, String>(
          vsync: tester,
          animationStyle: TreeAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);

        controller.setRoots([
          const TreeNode(key: "a", data: "A"),
          const TreeNode(key: "b", data: "B"),
          const TreeNode(key: "c", data: "C"),
        ]);

        int structuralNotifyCount = 0;
        controller.addListener(() => structuralNotifyCount++);

        final before = structuralNotifyCount;

        // Move "c" (currently at index 2) to index 0.
        controller.moveNode("c", null, index: 0, animate: false);

        expect(
          structuralNotifyCount,
          greaterThan(before),
          reason: "Move to a different index must fire structural notify",
        );
        expect(
          controller.liveRootKeys.first,
          "c",
          reason: "After move, 'c' should be at index 0",
        );
      },
    );
  });

  group("S014 — syncMultipleChildren cross-parent uniqueness", () {
    testWidgets("debug-mode assert when same key under two parents", (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);

      final sync = TreeSyncController<String, String>(treeController: controller);
      addTearDown(sync.dispose);

      controller.setRoots([
        const TreeNode(key: "p1", data: "P1"),
        const TreeNode(key: "p2", data: "P2"),
      ]);

      // Same child key "x" under both parents — illegal.
      expect(
        () => sync.syncMultipleChildren({
          "p1": [const TreeNode(key: "x", data: "X")],
          "p2": [const TreeNode(key: "x", data: "X")],
        }),
        throwsA(isA<FlutterError>()),
        reason: "Debug assert must reject same key under two parents",
      );
    });

    testWidgets(
      "different keys under different parents work normally",
      (tester) async {
        // Sanity: the assert must not over-trigger. Distinct keys per
        // parent should sync without complaint.
        final controller = TreeController<String, String>(
          vsync: tester,
          animationStyle: TreeAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);

        final sync = TreeSyncController<String, String>(treeController: controller);
        addTearDown(sync.dispose);

        controller.setRoots([
          const TreeNode(key: "p1", data: "P1"),
          const TreeNode(key: "p2", data: "P2"),
        ]);

        expect(
          () => sync.syncMultipleChildren({
            "p1": [const TreeNode(key: "x1", data: "X1")],
            "p2": [const TreeNode(key: "x2", data: "X2")],
          }),
          returnsNormally,
        );
      },
    );
  });
}
