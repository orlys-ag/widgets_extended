import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

/// Regression tests for the M9 fix: sibling-list mutations inside
/// [TreeController.runBatch] must not build the O(siblings) refresh set
/// once per mutation. Dirty parents are recorded as tokens and the set is
/// built once per distinct parent at batch exit, so K mutations under one
/// parent cost O(K + S) set work instead of O(K * S).
///
/// The budgets pin [TreeController.debugSiblingRefreshSetBuilds], which
/// counts every O(siblings) build, so they are exact and independent of
/// wall-clock noise.
void main() {
  TreeController<String, String> makeController(WidgetTester tester) {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  // Roots [p, q, other]; p expanded with children c0..c9; q collapsed
  // with children d0..d2.
  void buildTree(TreeController<String, String> controller) {
    controller.setRoots([
      TreeNode(key: "p", data: "P"),
      TreeNode(key: "q", data: "Q"),
      TreeNode(key: "other", data: "OTHER"),
    ]);
    controller.setChildren("p", [
      for (int i = 0; i < 10; i++) TreeNode(key: "c$i", data: "C$i"),
    ]);
    controller.setChildren("q", [
      for (int i = 0; i < 3; i++) TreeNode(key: "d$i", data: "D$i"),
    ]);
    controller.expand(key: "p");
  }

  testWidgets(
    "batched inserts fire once with the union of the per-call refresh sets",
    (tester) async {
      final controller = makeController(tester);
      buildTree(controller);
      expect(
        controller.isExpanded("p"),
        isTrue,
        reason:
            "setup sanity: the inserts below must target an expanded "
            "parent so the batch exercises the visible-order insert path",
      );
      expect(
        controller.getLiveChildren("p"),
        [for (int i = 0; i < 10; i++) "c$i"],
        reason: "setup sanity: p starts with exactly c0..c9",
      );

      final captured = <Set<String>?>[];
      controller.addStructuralListener(captured.add);

      controller.runBatch(() {
        for (int i = 0; i < 5; i++) {
          controller.insert(
            parentKey: "p",
            node: TreeNode(key: "n$i", data: "N$i"),
          );
        }
      });

      expect(
        captured.length,
        1,
        reason: "the batch coalesces to exactly one structural fire",
      );
      expect(
        captured.single,
        unorderedEquals(<String>{
          "p",
          for (int i = 0; i < 10; i++) "c$i",
          for (int i = 0; i < 5; i++) "n$i",
        }),
        reason:
            "the exit-time set is the parent plus every sibling, the "
            "same union the per-call sets produce",
      );
      expect(
        captured.single,
        isNot(contains("other")),
        reason: "rows outside the mutated sibling list are untouched",
      );
    },
  );

  testWidgets(
    "a batch of inserts under two parents builds one refresh set per parent",
    (tester) async {
      final controller = makeController(tester);
      buildTree(controller);

      controller.debugSiblingRefreshSetBuilds = 0;
      controller.runBatch(() {
        for (int i = 0; i < 20; i++) {
          controller.insert(
            parentKey: "p",
            node: TreeNode(key: "np$i", data: "NP$i"),
          );
        }
        for (int i = 0; i < 5; i++) {
          controller.insert(
            parentKey: "q",
            node: TreeNode(key: "nq$i", data: "NQ$i"),
          );
        }
      });

      expect(
        controller.getLiveChildren("p").length,
        30,
        reason: "setup sanity: all 20 inserts under p landed",
      );
      expect(
        controller.getLiveChildren("q").length,
        8,
        reason: "setup sanity: all 5 inserts under q landed",
      );
      expect(
        controller.debugSiblingRefreshSetBuilds,
        2,
        reason:
            "one O(siblings) build per distinct dirty parent at batch "
            "exit, not one per insert",
      );
    },
  );

  testWidgets(
    "moveNode within one parent builds the refresh set once per batch",
    (tester) async {
      final controller = makeController(tester);
      buildTree(controller);

      controller.debugSiblingRefreshSetBuilds = 0;
      controller.runBatch(() {
        for (int i = 0; i < 10; i++) {
          final moved = controller.getLiveChildren("p").first;
          controller.moveNode(moved, "p", index: 9);
          expect(
            controller.getIndexInParent(moved),
            9,
            reason:
                "setup sanity: the move must really run; a same-position "
                "call would take the no-op early return and never touch "
                "the refresh-set path",
          );
        }
      });

      expect(
        controller.debugSiblingRefreshSetBuilds,
        1,
        reason:
            "moveNode records a token for the old and the new parent; "
            "both are p, so the batch exit builds exactly one refresh set",
      );
    },
  );

  testWidgets(
    "an unbatched insert still builds and fires its refresh set immediately",
    (tester) async {
      final controller = makeController(tester);
      buildTree(controller);

      final captured = <Set<String>?>[];
      controller.addStructuralListener(captured.add);
      controller.debugSiblingRefreshSetBuilds = 0;

      controller.insert(parentKey: "p", node: TreeNode(key: "n0", data: "N0"));

      expect(
        controller.debugSiblingRefreshSetBuilds,
        1,
        reason:
            "an immediate notification must carry its keys now; the "
            "batch deferral must not leak outside runBatch",
      );
      expect(
        captured.length,
        1,
        reason: "an unbatched insert fires exactly one structural fire",
      );
      expect(
        captured.single,
        unorderedEquals(<String>{
          "p",
          for (int i = 0; i < 10; i++) "c$i",
          "n0",
        }),
        reason:
            "the immediate fire carries the parent plus every sibling, "
            "including the inserted key",
      );
    },
  );
}
