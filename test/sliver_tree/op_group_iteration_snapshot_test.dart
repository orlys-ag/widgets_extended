/// Regression tests for C037 and C041: `expandAll` and `collapseAll`
/// iterate `_opGroupEntries` and call `forward()` / `reverse()` on each
/// group's controller. If the controller is already at a terminal value
/// (1.0 for forward, 0.0 for reverse), Flutter's `AnimationController`
/// fires the status callback synchronously. The status callback removes
/// the group from `_groups`, mutating the underlying map mid-iteration
/// of `_opGroupEntries` and throwing `ConcurrentModificationError`.
///
/// The fix snapshots `_opGroupEntries` into a reusable scratch list
/// before iterating, so mid-loop `removeGroup` calls only affect the
/// underlying map, not the snapshot the loop is walking.
///
/// Trigger: rapid `collapse` → `expandAll` (or `expand` → `collapseAll`)
/// in the same microtask, before any frame ticks. The new group's
/// controller is at its initial terminal value, so the cross-call to
/// `forward()` / `reverse()` synchronously fires `completed` / `dismissed`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets(
    "expandAll does not throw ConcurrentModificationError when a "
    "collapsing op-group's controller is at upperBound",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // Two independent subtrees so we get two operation groups.
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("a", [const TreeNode(key: "a1", data: "a1")]);
      controller.setChildren("b", [const TreeNode(key: "b1", data: "b1")]);

      // Expand both first (sync, no animation), so collapse(animate:true)
      // installs a fresh op-group with controller starting at value=1.0.
      controller.expand(key: "a", animate: false);
      controller.expand(key: "b", animate: false);

      // Collapse both with animation. Each installs an op-group whose
      // controller is at value=1.0 (the starting state before reverse()
      // ticks). The animation duration hasn't elapsed yet so the
      // controllers are still at upperBound when expandAll fires next.
      controller.collapse(key: "a", animate: true);
      controller.collapse(key: "b", animate: true);

      // expandAll(animate:true) iterates op-groups and calls forward()
      // on each. forward() on a controller at value=1.0 has
      // simulationDuration=0 → synchronously fires `completed` status
      // → status listener removes the group from _groups, mutating the
      // map. Without the snapshot, this would throw
      // ConcurrentModificationError on the iteration.
      expect(
        () => controller.expandAll(animate: true),
        returnsNormally,
        reason: "expandAll must snapshot _opGroupEntries before iterating",
      );

      // Settle so the test's ticker-disposal verification passes.
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "collapseAll does not throw ConcurrentModificationError when an "
    "expanding op-group's controller is at lowerBound",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("a", [const TreeNode(key: "a1", data: "a1")]);
      controller.setChildren("b", [const TreeNode(key: "b1", data: "b1")]);

      // Expand both with animation. Each installs an op-group whose
      // controller is at value=0.0 (the starting state before forward()
      // ticks).
      controller.expand(key: "a", animate: true);
      controller.expand(key: "b", animate: true);

      // collapseAll(animate:true) iterates op-groups and calls reverse()
      // on each. reverse() on a controller at value=0.0 has
      // simulationDuration=0 → synchronously fires `dismissed` status
      // → status listener removes the group, mutating the map. Without
      // the snapshot, this throws ConcurrentModificationError.
      expect(
        () => controller.collapseAll(animate: true),
        returnsNormally,
        reason: "collapseAll must snapshot _opGroupEntries before iterating",
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "expandAll completes correctly when multiple collapsing op-groups "
    "would terminate synchronously",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // Four independent subtrees to stress the snapshot pattern.
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
        const TreeNode(key: "d", data: "D"),
      ]);
      for (final root in ["a", "b", "c", "d"]) {
        controller.setChildren(
          root,
          [TreeNode(key: "${root}1", data: "${root}1")],
        );
        controller.expand(key: root, animate: false);
      }

      // All four collapse → four op-groups at value=1.0.
      for (final root in ["a", "b", "c", "d"]) {
        controller.collapse(key: root, animate: true);
      }

      // All four would sync-fire `completed` on forward().
      controller.expandAll(animate: true);

      // After expandAll, all four should be expanded again.
      await tester.pumpAndSettle();
      for (final root in ["a", "b", "c", "d"]) {
        expect(
          controller.isExpanded(root),
          isTrue,
          reason: "$root should be expanded after expandAll",
        );
      }
    },
  );
}
