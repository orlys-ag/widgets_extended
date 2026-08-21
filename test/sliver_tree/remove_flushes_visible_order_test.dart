import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Regression tests: `remove()` must flush a deferred visible-order rebuild
/// before deciding between its animated and immediate paths.
///
/// `remove()` picks its path with `animate && _order.contains(key)`. Every
/// sibling mutator calls `_ensureVisibleOrder()` on entry so positional and
/// membership reads see fresh state (`insertRoot`, `insert`, `expand`,
/// `collapse`, `expandAll`, `moveNode`, `collapseAll`), and `runBatch`
/// flushes on exit. `remove()` was the one mutator that did not, so inside a
/// batch a prior mutation that marks the order dirty left that containment
/// read stale and the path choice wrong in both directions:
///
///   - a row made VISIBLE earlier in the batch reads as absent, so an
///     animated remove degrades to an immediate purge and the row vanishes
///     with no exit animation;
///   - a row HIDDEN earlier in the batch reads as present, so an immediate
///     remove is deferred into an animation nothing can see.
///
/// Outside a batch the mark rebuilds synchronously, so only the batched case
/// can diverge. The reads inside `runBatch` below deliberately avoid every
/// public visible-order accessor (`isVisible`, `visibleNodes`,
/// `getVisibleIndex`, ...), because those flush and would mask the bug.
void main() {
  TreeController<String, String> makeController(WidgetTester tester) {
    return TreeController<String, String>(
      vsync: tester,
      animationStyle: const TreeAnimationStyle(
        enterExit: TreeAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      ),
    );
  }

  testWidgets(
    "batched remove of a row made visible earlier in the batch animates out",
    (tester) async {
      final controller = makeController(tester);
      addTearDown(controller.dispose);

      // Setup: "a" is collapsed and owns "a1", so "a1" is NOT in the visible
      // order. "b" is expanded, so anything reparented under it becomes
      // visible. "b" needs a child of its own for the expand to stick:
      // `expand` returns early on a childless node.
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
      controller.setChildren("b", [TreeNode(key: "b0", data: "B0")]);
      controller.expand(key: "b", animate: false);

      expect(
        controller.isVisible("a1"),
        isFalse,
        reason: "setup error: a1 must start hidden under collapsed a, so the "
            "stale containment read is the one that differs",
      );
      expect(
        controller.isExpanded("b"),
        isTrue,
        reason: "setup error: b must be expanded so the move makes a1 visible",
      );

      controller.runBatch(() {
        // Marks the visible order dirty; inside a batch the rebuild is
        // deferred, so `_order` still describes the pre-move world.
        controller.moveNode("a1", "b", animate: false);
        // Reads containment for "a1": stale says absent, fresh says present.
        controller.remove(key: "a1");
      });

      // Expected: a1 was visible when remove() ran, so it takes the animated
      // path and is still present, mid-exit. On unfixed code the stale read
      // sends it down the immediate path and it is already purged.
      expect(
        controller.getNodeData("a1"),
        isNotNull,
        reason: "a1 was visible at remove() time and must animate out, not "
            "purge immediately",
      );
      expect(controller.isExiting("a1"), isTrue);

      // And the animation still finalizes normally.
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(controller.getNodeData("a1"), isNull);
      expect(controller.getChildren("b"), ["b0"]);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    "batched remove of a row hidden earlier in the batch purges immediately",
    (tester) async {
      final controller = makeController(tester);
      addTearDown(controller.dispose);

      // Setup: "b" expanded with child "b1" visible, plus a collapsed "a"
      // (with a child of its own, so it is a real collapsed parent) to
      // reparent into.
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("a", [TreeNode(key: "a0", data: "A0")]);
      controller.setChildren("b", [TreeNode(key: "b1", data: "B1")]);
      controller.expand(key: "b", animate: false);

      expect(
        controller.isVisible("b1"),
        isTrue,
        reason: "setup error: b1 must start visible so the stale read differs",
      );
      expect(
        controller.isExpanded("a"),
        isFalse,
        reason: "setup error: a must be collapsed so the move hides b1",
      );

      controller.runBatch(() {
        // b1 becomes structurally hidden under collapsed "a"; the rebuild
        // that would drop it from the order is deferred.
        controller.moveNode("b1", "a", animate: false);
        controller.remove(key: "b1");
      });

      // Expected: b1 was hidden when remove() ran, so it purges at once.
      // On unfixed code the stale read reports it visible and it lingers as
      // a pending-deletion row animating out where nobody can see it.
      expect(
        controller.getNodeData("b1"),
        isNull,
        reason: "b1 was hidden at remove() time and must purge immediately, "
            "not animate out invisibly",
      );
      expect(controller.getChildren("a"), ["a0"]);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    "control: unbatched remove is unaffected (the mark rebuilds eagerly)",
    (tester) async {
      final controller = makeController(tester);
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
      controller.setChildren("b", [TreeNode(key: "b0", data: "B0")]);
      controller.expand(key: "b", animate: false);

      controller.moveNode("a1", "b", animate: false);
      expect(controller.isVisible("a1"), isTrue);
      controller.remove(key: "a1");

      expect(controller.getNodeData("a1"), isNotNull);
      expect(controller.isExiting("a1"), isTrue);

      // Drain the exit so no ticker outlives the test body.
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(controller.getNodeData("a1"), isNull);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
