import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Repro tests for M2: a default-flag re-add of a mid-exit node restores
/// the NODE, not its subtree, matching `remove(animate: false)` followed by
/// `insert`. Pre-fix, the descendant policy cleared every descendant's
/// pending-deletion marker (case 2), so the finalizer took its non-purge
/// branch and the old subtree survived structurally; the settled outcome of
/// the same two-call sequence depended on whether an exit happened to be in
/// flight. Descendants with a live exit still finish shrinking (they keep
/// the marker instead of losing it), which the smoothness control pins.
void main() {
  setUp(() {
    TreeController.debugFullConsistencyChecks = true;
  });
  tearDown(() {
    TreeController.debugFullConsistencyChecks = false;
  });

  TreeController<String, String> makeController(WidgetTester tester) {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: const TreeAnimationStyle(
        expandCollapse: TreeAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      ),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  testWidgets("default re-add of a mid-exit node discards its subtree", (
    tester,
  ) async {
    final controller = makeController(tester);
    controller.setRoots([const TreeNode(key: "A", data: "A")]);
    controller.setChildren("A", [const TreeNode(key: "a1", data: "A1")]);
    controller.expand(key: "A", animate: false);

    controller.remove(key: "A");
    // Tickers started outside a frame report elapsed 0 on the first pump,
    // so pump once before the timed pump.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      controller.isPendingDeletion("a1"),
      isTrue,
      reason: "setup sanity: a1 must be mid-removal when the re-add runs",
    );
    expect(
      controller.getAnimationState("a1")?.type,
      AnimationType.exiting,
      reason: "setup sanity: a1 must have a live standalone exit",
    );

    controller.insertRoot(const TreeNode(key: "A", data: "A")); // default flags
    expect(
      controller.getLiveChildren("A"),
      isEmpty,
      reason:
          "a default re-add restores the node, not its subtree; a1 must "
          "stay pending-deletion while its exit finishes",
    );
    // Deliberately NOT asserted here: getChildren("A"). It is the RAW child
    // list, unfiltered by pending-deletion, and the discard leaves a1
    // linked until its exit finalizes, so it reads ["a1"] both before and
    // after the fix and discriminates nothing.

    await tester.pumpAndSettle();
    expect(
      controller.getChildren("A"),
      isEmpty,
      reason:
          "once the exit lands, the finalizer's purge branch must remove "
          "a1 structurally, not merely drop it from the visible order",
    );
    expect(controller.hasChildren("A"), isFalse);
    controller.expand(key: "A");
    expect(
      controller.visibleNodes,
      ["A"],
      reason: "re-expanding must not resurrect the discarded child",
    );
  });

  testWidgets(
    "control: the non-animated sequence settles to the identical state",
    (tester) async {
      final controller = makeController(tester);
      controller.setRoots([const TreeNode(key: "A", data: "A")]);
      controller.setChildren("A", [const TreeNode(key: "a1", data: "A1")]);
      controller.expand(key: "A", animate: false);

      controller.remove(key: "A", animate: false);
      controller.insertRoot(const TreeNode(key: "A", data: "A"));
      await tester.pumpAndSettle();

      expect(
        controller.getChildren("A"),
        isEmpty,
        reason:
            "the animated and non-animated paths must converge to the "
            "same settled structure",
      );
      expect(controller.hasChildren("A"), isFalse);
      controller.expand(key: "A");
      expect(controller.visibleNodes, ["A"]);
    },
  );

  testWidgets("smoothness control: the discard must not yank exiting rows", (
    tester,
  ) async {
    final controller = makeController(tester);
    controller.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
      const TreeNode(key: "c", data: "C"),
    ]);
    controller.setChildren("b", [const TreeNode(key: "b1", data: "B1")]);
    controller.expand(key: "b", animate: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverTree<String, String>(
                controller: controller,
                nodeBuilder: (context, key, depth) {
                  return SizedBox(height: 100, child: Text(key));
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text("c")).dy,
      300,
      reason: "setup sanity: a (0), b (100), b1 (200), c (300)",
    );

    controller.remove(key: "b");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final cMid = tester.getTopLeft(find.text("c")).dy;

    // Re-add WITHOUT preservePendingSubtreeState (default flags).
    controller.insertRoot(const TreeNode(key: "b", data: "B"), index: 1);
    await tester.pump(Duration.zero);
    final cPost = tester.getTopLeft(find.text("c")).dy;

    expect(
      cPost,
      closeTo(cMid, 5),
      reason:
          "b1 must keep shrinking in place; discarding it from the "
          "visible order at the instant of the re-add would jump c "
          "upward by b1's current extent",
    );
    await tester.pumpAndSettle();
  });
}
