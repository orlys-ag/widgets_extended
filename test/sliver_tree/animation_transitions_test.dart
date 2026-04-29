/// Comprehensive verification of animation state transitions:
///   1. remove → re-insert mid-exit reverses the animation (extent and
///      direction).
///   2. collapse → re-expand mid-collapse reverses the operation group.
///   3. expand → re-collapse mid-expand reverses the operation group.
///   4. expandAll → collapseAll mid-bulk reverses the bulk group.
///   5. collapseAll → expandAll mid-bulk reverses the bulk group.
///   6. moveNode of a mid-exit subtree cancels the exit and re-anchors.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  group("remove → re-insert reversal", () {
    testWidgets("removed root, re-inserted via insertRoot mid-exit, "
        "preserves visual continuity (no jump) and ends entering",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);

      // Set a measured extent so the animation has a meaningful range.
      controller.setFullExtent("b", 40.0);

      // Start removing 'b'.
      controller.remove(key: "b", animate: true);
      expect(controller.isPendingDeletion("b"), isTrue);
      expect(controller.isExiting("b"), isTrue);
      final exitState = controller.getAnimationState("b");
      expect(exitState?.type, AnimationType.exiting);

      // Pump partway through the animation. With the dt-based ticker,
      // the first tick has dt=0 so we need multiple frames for progress
      // to accumulate.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final extentMidExit = controller.getCurrentExtent("b");
      expect(extentMidExit, lessThan(40.0),
          reason: "Sanity: extent should have shrunk during exit");
      expect(extentMidExit, greaterThan(0.0),
          reason: "Sanity: extent should not be fully zero yet");

      // Re-insert via insertRoot — this must cancel the deletion and
      // reverse the exit into an enter.
      controller.insertRoot(const TreeNode(key: "b", data: "B"));

      expect(controller.isPendingDeletion("b"), isFalse,
          reason: "Re-insert must clear pending-deletion");
      expect(controller.isExiting("b"), isFalse,
          reason: "Re-insert must NOT leave the node in exiting state");
      final enterState = controller.getAnimationState("b");
      expect(enterState?.type, AnimationType.entering,
          reason: "Re-insert must transition to entering");

      // The startExtent of the new entering animation should equal the
      // extent we observed mid-exit — visual continuity, no jump back
      // to 0 or to full.
      expect(enterState!.startExtent, closeTo(extentMidExit, 0.5),
          reason: "Entering animation must start from the exit's "
              "current visual extent for smooth reversal. "
              "Expected ~$extentMidExit, got ${enterState.startExtent}");

      // Drain the rest of the animation. 'b' should remain alive.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.getNodeData("b"), isNotNull,
          reason: "'b' must survive the original exit duration");
      expect(controller.getCurrentExtent("b"), closeTo(40.0, 0.5),
          reason: "After enter completes, extent should be back to full");
    });

    testWidgets("removed child, re-inserted via insert mid-exit, reverses",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.expand(key: "p", animate: false);
      controller.setFullExtent("c", 30.0);

      controller.remove(key: "c", animate: true);
      expect(controller.isExiting("c"), isTrue);

      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final mid = controller.getCurrentExtent("c");
      expect(mid, lessThan(30.0));

      controller.insert(parentKey: "p", node: const TreeNode(key: "c", data: "C"));
      expect(controller.isPendingDeletion("c"), isFalse);
      expect(controller.getAnimationState("c")?.type, AnimationType.entering);

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.getNodeData("c"), isNotNull);
    });
  });

  group("collapse ↔ expand reversal", () {
    testWidgets("expand → collapse mid-expand reverses the operation group",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [
        const TreeNode(key: "c1", data: "C1"),
        const TreeNode(key: "c2", data: "C2"),
      ]);

      // Start expanding 'p'.
      controller.expand(key: "p", animate: true);
      expect(controller.isExpanded("p"), isTrue);
      expect(controller.isAnimating("c1"), isTrue);
      expect(controller.isAnimating("c2"), isTrue);

      // Pump partway.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Reverse: collapse mid-expand.
      controller.collapse(key: "p", animate: true);
      expect(controller.isExpanded("p"), isFalse);
      // Children should now be exiting (in op-group's pendingRemoval).
      expect(controller.isExiting("c1"), isTrue);
      expect(controller.isExiting("c2"), isTrue);

      // Drain past the original duration.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // After collapse settles, children leave the visible order (still
      // structurally present, just collapsed).
      expect(controller.visibleNodes.toList(), equals(["p"]));
      expect(controller.getNodeData("c1"), isNotNull,
          reason: "Collapse must NOT purge structural data — "
              "children remain registered, just hidden.");
    });

    testWidgets("collapse → expand mid-collapse reverses the operation group",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [
        const TreeNode(key: "c1", data: "C1"),
        const TreeNode(key: "c2", data: "C2"),
      ]);
      controller.expand(key: "p", animate: false);

      controller.collapse(key: "p", animate: true);
      expect(controller.isExpanded("p"), isFalse);
      expect(controller.isExiting("c1"), isTrue);

      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      controller.expand(key: "p", animate: true);
      expect(controller.isExpanded("p"), isTrue);
      // After re-expand, children should not be exiting anymore.
      expect(controller.isExiting("c1"), isFalse);
      expect(controller.isExiting("c2"), isFalse);

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.visibleNodes.toList(), equals(["p", "c1", "c2"]));
    });
  });

  group("expandAll ↔ collapseAll reversal", () {
    testWidgets("expandAll → collapseAll mid-bulk reverses the bulk group",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("a", [const TreeNode(key: "a1", data: "A1")]);
      controller.setChildren("b", [const TreeNode(key: "b1", data: "B1")]);

      controller.expandAll(animate: true);
      expect(controller.isExpanded("a"), isTrue);
      expect(controller.isExpanded("b"), isTrue);
      expect(controller.isBulkAnimating, isTrue);

      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      controller.collapseAll(animate: true);
      expect(controller.isExpanded("a"), isFalse);
      expect(controller.isExpanded("b"), isFalse);

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.visibleNodes.toList(), equals(["a", "b"]),
          reason: "After full collapse, only roots remain visible");
    });

    testWidgets("collapseAll → expandAll mid-bulk reverses the bulk group",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("a", [const TreeNode(key: "a1", data: "A1")]);
      controller.setChildren("b", [const TreeNode(key: "b1", data: "B1")]);
      controller.expandAll(animate: false);

      controller.collapseAll(animate: true);

      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      controller.expandAll(animate: true);
      expect(controller.isExpanded("a"), isTrue);
      expect(controller.isExpanded("b"), isTrue);

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // After full expand, all children visible.
      expect(controller.visibleNodes.toList(),
          equals(["a", "a1", "b", "b1"]));
    });
  });

  group("moveNode of mid-exit subtree", () {
    testWidgets("moveNode of a pending-deletion subtree cancels the "
        "exit and re-anchors at new position", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "p1", data: "P1"),
        const TreeNode(key: "p2", data: "P2"),
      ]);
      controller.setChildren("p1", [const TreeNode(key: "x", data: "X")]);
      controller.expand(key: "p1", animate: false);

      controller.remove(key: "x", animate: true);
      expect(controller.isExiting("x"), isTrue);

      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // moveNode should cancel exit animation per its documented contract:
      // "Any in-flight enter/exit animations on the moved subtree are
      // cancelled".
      controller.moveNode("x", "p2");
      controller.expand(key: "p2", animate: false);

      expect(controller.isPendingDeletion("x"), isFalse,
          reason: "moveNode must clear pending-deletion on the moved subtree");
      expect(controller.isExiting("x"), isFalse,
          reason: "moveNode must clear exit animation on the moved subtree");
      expect(controller.getParent("x"), "p2",
          reason: "Move took effect");

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.getNodeData("x"), isNotNull);
    });
  });

  group("repeated reversal", () {
    testWidgets("expand → collapse → expand → collapse rapidly does not "
        "leak op-groups or corrupt state", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);

      for (var i = 0; i < 5; i++) {
        controller.expand(key: "p", animate: true);
        await tester.pump(const Duration(milliseconds: 16));
        controller.collapse(key: "p", animate: true);
        await tester.pump(const Duration(milliseconds: 16));
      }

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Ends in collapsed state (last call was collapse).
      expect(controller.isExpanded("p"), isFalse);
      // Structure intact.
      expect(controller.getChildren("p"), equals(["c"]));
    });

    testWidgets("remove → re-insert → remove → re-insert rapidly stays "
        "consistent", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);

      for (var i = 0; i < 5; i++) {
        controller.remove(key: "b", animate: true);
        await tester.pump(const Duration(milliseconds: 16));
        controller.insertRoot(const TreeNode(key: "b", data: "B"));
        await tester.pump(const Duration(milliseconds: 16));
      }

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // After last insertRoot + drain, 'b' is alive.
      expect(controller.getNodeData("b"), isNotNull);
      expect(controller.rootKeys, contains("b"));
    });
  });
}
