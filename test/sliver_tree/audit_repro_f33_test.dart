import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Audit repro for finding f33:
///
/// `TreeSyncController._syncChildrenImpl` computes `targetIndex` for newly
/// inserted children in "live" (post-removal) space, but
/// `TreeController.insert` applies that index to the raw sibling list, which
/// still contains pending-deletion siblings while their exit animation runs.
/// The step-5 reorder repair compares the sync layer's own tracked list
/// against the desired list (instead of the controller's actual children), so
/// it never fires, and the resulting misorder is permanent.
///
/// Expected (correct) behavior: syncing children [x, b] -> [b, c] with
/// animation enabled must end with the parent's children in desired order
/// [b, c] once animations settle. The finding predicts the buggy code yields
/// [c, b] instead.
void main() {
  testWidgets(
    "animated syncChildren remove+insert preserves desired child order",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      final sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      // Setup: r1 with children [x, b], all visible.
      sync.syncRoots(
        [TreeNode(key: "r1", data: "R1")],
        childrenOf: (key) {
          if (key == "r1") {
            return [TreeNode(key: "x", data: "X"), TreeNode(key: "b", data: "B")];
          }
          return [];
        },
        animate: false,
      );
      controller.expand(key: "r1", animate: false);
      expect(controller.getChildren("r1"), ["x", "b"]);

      // Action: sync to [b, c] with animation enabled (the default path for
      // every SyncedSliverTree.didUpdateWidget rebuild). x gets an animated
      // remove; c is a new insert whose index is computed in live space.
      sync.syncChildren("r1", [
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ], animate: true);

      // Sanity: the animated-removal path is actually exercised — x must be
      // mid-exit (still present as a pending-deletion sibling).
      expect(
        controller.isExiting("x"),
        isTrue,
        reason: "setup error: x should be exit-animating after animated sync",
      );

      // Let the 300ms exit/entry animations finish with a bounded pump loop.
      for (int i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Sanity: the exit finalized — x is gone from the tree.
      expect(
        controller.getNodeData("x"),
        isNull,
        reason: "setup error: x's exit animation should have finalized",
      );

      // Expected behavior: children match the desired order [b, c].
      // Finding f33 predicts the buggy code permanently yields [c, b].
      expect(controller.getChildren("r1"), ["b", "c"]);

      // The misorder is claimed to be permanent: a second identical sync
      // compares tracked == desired and becomes a no-op instead of repairing.
      sync.syncChildren("r1", [
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ], animate: true);
      for (int i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(controller.getChildren("r1"), ["b", "c"]);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    "control: non-animated syncChildren remove+insert orders correctly",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      final sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      sync.syncRoots(
        [TreeNode(key: "r1", data: "R1")],
        childrenOf: (key) {
          if (key == "r1") {
            return [TreeNode(key: "x", data: "X"), TreeNode(key: "b", data: "B")];
          }
          return [];
        },
        animate: false,
      );
      controller.expand(key: "r1", animate: false);
      expect(controller.getChildren("r1"), ["x", "b"]);

      sync.syncChildren("r1", [
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ], animate: false);

      expect(controller.getChildren("r1"), ["b", "c"]);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
