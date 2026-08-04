/// Regression test for C026: `setChildren(parent, identicalList)` must
/// be a no-op that preserves in-flight animation state on the children.
///
/// Before the fix, `setChildren` unconditionally purged the old children
/// (releasing nids, calling `_purgeNodeData` which destroys standalone /
/// op-group / bulk animation state) and re-adopted them. Reactive sync
/// code that re-sends the same child list (e.g. a `setState`-driven
/// rebuild) would visibly reset mid-flight expand animations.
///
/// The fix adds an early-return when the new list exactly matches the
/// existing list (same keys in order, same data values, no
/// pending-deletion children).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets(
    "setChildren with identical list preserves in-flight expand animation",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 400), curve: Curves.linear)),
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [
        const TreeNode(key: "c1", data: "C1"),
        const TreeNode(key: "c2", data: "C2"),
      ]);
      controller.setFullExtent("c1", 48.0);
      controller.setFullExtent("c2", 48.0);

      // Start an animated expand. Children animate from 0 → 48.
      controller.expand(key: "p", animate: true);
      await tester.pump();
      // Mid-flight: pump halfway through the 400ms animation.
      await tester.pump(const Duration(milliseconds: 200));

      final c1MidFlight = controller.getCurrentExtent("c1");
      // Should be somewhere between 0 and 48 (linear curve → ~24 at 50%).
      expect(
        c1MidFlight,
        greaterThan(0.0),
        reason: "c1 should be mid-animation (extent > 0)",
      );
      expect(
        c1MidFlight,
        lessThan(48.0),
        reason: "c1 should be mid-animation (extent < full 48)",
      );

      // Now call setChildren with the IDENTICAL list. Without the C026
      // fast path, this would purge c1/c2 (destroying animation state)
      // and re-adopt them with extents reset to 0.
      controller.setChildren("p", [
        const TreeNode(key: "c1", data: "C1"),
        const TreeNode(key: "c2", data: "C2"),
      ]);

      final c1AfterSetChildren = controller.getCurrentExtent("c1");
      expect(
        c1AfterSetChildren,
        c1MidFlight,
        reason: "setChildren with identical input must preserve c1's "
            "in-flight animation state. Got "
            "${c1AfterSetChildren.toStringAsFixed(2)} (before: "
            "${c1MidFlight.toStringAsFixed(2)}). A difference indicates "
            "the slow path purged + re-adopted, resetting the animation.",
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "setChildren with different list still purges + re-adopts (slow path)",
    (tester) async {
      // Sanity check: the fast path must NOT over-prune. A genuinely
      // different child list still triggers the slow path's full
      // purge + re-adopt.
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [
        const TreeNode(key: "c1", data: "C1"),
      ]);

      expect(controller.getChildren("p"), ["c1"]);

      // Replace with a different child. Slow path runs.
      controller.setChildren("p", [
        const TreeNode(key: "c2", data: "C2"),
      ]);

      expect(controller.getChildren("p"), ["c2"]);
    },
  );

  testWidgets(
    "setChildren with same keys but different data triggers slow path",
    (tester) async {
      // If the keys match but data differs, the fast path should reject
      // the match and fall through to the slow path (which updates data
      // via the normal re-adopt flow).
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [
        const TreeNode(key: "c1", data: "original"),
      ]);

      expect(controller.getNodeData("c1")?.data, "original");

      // Same key, different data. Slow path runs and the data is
      // updated via the normal _store.setData call in the re-adopt loop.
      controller.setChildren("p", [
        const TreeNode(key: "c1", data: "updated"),
      ]);

      expect(controller.getNodeData("c1")?.data, "updated");
    },
  );
}
