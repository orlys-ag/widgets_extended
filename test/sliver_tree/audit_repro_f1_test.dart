/// Audit repro for finding f1: moveNode consumes `index` in two different
/// index spaces — the same-parent no-op check compares against the LIVE
/// index (getIndexInParent, which skips pending-deletion siblings), but the
/// actual insertion writes into the FULL sibling list, which still contains
/// pending-deletion entries while an animated remove()'s exit animation is
/// in flight.
///
/// Expected (correct) behavior asserted here: `index` is interpreted in
/// live-list space end to end — the documented contract of
/// getIndexInParent / getLiveChildren / reorderChildren, and the space the
/// shipped drag-reorder flow (TreeReorderController.endDrag) computes
/// indexInFinalList in before passing it straight to moveNode.
///
/// If the bug is real:
///   - Test 1 (cross-parent): D dropped at live index 1 of P (below A)
///     lands at FULL index 1 — before A in live order — so live order is
///     [D, A, B] instead of the requested [A, D, B].
///   - Test 2 (same-parent): moveNode(A, P, index: 1) intending live
///     [B, A] passes the live-space no-op check, but remove+insert in
///     full-list space reproduces the original order — a silent no-op,
///     live order stays [A, B].
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "cross-parent moveNode with a live-space index lands at the requested "
    "live position despite a pending-deletion sibling",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: "P", data: "P"),
        TreeNode(key: "D", data: "D"),
      ]);
      controller.setChildren("P", [
        TreeNode(key: "X", data: "X"),
        TreeNode(key: "A", data: "A"),
        TreeNode(key: "B", data: "B"),
      ]);
      controller.expand(key: "P", animate: false);

      // Animated remove: X becomes pending-deletion but stays in P's raw
      // child list until its exit animation finalizes.
      controller.remove(key: "X", animate: true);

      // Sanity: the claimed precondition holds — X is mid-exit and the
      // live list is [A, B] while the full list still leads with X.
      expect(controller.isPendingDeletion("X"), isTrue,
          reason: "Setup: X must be pending-deletion (exit in flight).");
      expect(controller.getLiveChildren("P"), ["A", "B"],
          reason: "Setup: live children of P must exclude pending X.");

      // Drop D "below A": live-space index 1 (this is exactly what
      // TreeReorderController.endDrag passes as indexInFinalList).
      controller.moveNode("D", "P", index: 1);

      expect(
        controller.getLiveChildren("P"),
        ["A", "D", "B"],
        reason: "index: 1 is live-space (the documented contract of "
            "getIndexInParent/getLiveChildren and the space the drag flow "
            "computes indexInFinalList in), so D must land between A and B. "
            "Buggy full-list insertion at raw index 1 slots D before A "
            "(raw [X, D, A, B]) yielding live [D, A, B].",
      );

      // Drain X's exit animation so the standalone ticker stops before
      // teardown verifies all tickers were disposed. Bounded loop — no
      // pumpAndSettle.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.isPendingDeletion("X"), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    "same-parent moveNode with a live-space index actually reorders "
    "despite a pending-deletion sibling",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: "P", data: "P"),
      ]);
      controller.setChildren("P", [
        TreeNode(key: "X", data: "X"),
        TreeNode(key: "A", data: "A"),
        TreeNode(key: "B", data: "B"),
      ]);
      controller.expand(key: "P", animate: false);

      controller.remove(key: "X", animate: true);

      // Sanity: X mid-exit; live list [A, B]; A's live index is 0, so the
      // live-space no-op check (index == getIndexInParent) does not trip
      // for index: 1 — the mutation path is exercised.
      expect(controller.isPendingDeletion("X"), isTrue,
          reason: "Setup: X must be pending-deletion (exit in flight).");
      expect(controller.getLiveChildren("P"), ["A", "B"],
          reason: "Setup: live children of P must exclude pending X.");
      expect(controller.getIndexInParent("A"), 0,
          reason: "Setup: A's live index must be 0 so index: 1 is not "
              "rejected by the no-op check.");

      // Move A to live index 1: requested live order [B, A].
      controller.moveNode("A", "P", index: 1);

      expect(
        controller.getLiveChildren("P"),
        ["B", "A"],
        reason: "moveNode(A, P, index: 1) with live [A, B] must produce "
            "live [B, A]. Buggy full-list insertion removes A from raw "
            "[X, A, B] -> [X, B], reinserts at raw index 1 -> [X, A, B]: "
            "a silent no-op that leaves live order [A, B].",
      );

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.isPendingDeletion("X"), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
