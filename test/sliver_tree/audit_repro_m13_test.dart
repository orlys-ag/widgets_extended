/// Repro for M13: `_syncRootsImpl` never publishes the mover-subtree
/// deferral context (`_deferredSubtreeRemovals` and `_moverAncestors`),
/// which only `syncMultipleChildren` sets. Inside a root sync, an
/// intermediate node that is removed while its SUBTREE holds a mover falls
/// through to an eager `remove`, which under `animate: false` purges the
/// mover before the later `moveNode`; the mover is then re-created as a
/// fresh node at its destination instead of being moved.
///
/// The nid is the discriminating assertion: a purge-and-recreate registers
/// a fresh node. Expansion and children do NOT discriminate (the removal
/// remembers the subtree's expansion and the recursive sync restores it,
/// and `childrenOf` re-creates the children), so they are post-conditions
/// only.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

TreeNode<String, String> _n(String key) => TreeNode(key: key, data: key);

void main() {
  testWidgets(
    "a mover under a removed intermediate node keeps its identity across a "
    "root sync",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      final sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      // A > [B > [x > [y]], C], plus root Q.
      List<TreeNode<String, String>> before(String key) {
        switch (key) {
          case "A":
            return [_n("B"), _n("C")];
          case "B":
            return [_n("x")];
          case "x":
            return [_n("y")];
        }
        return const [];
      }

      sync.syncRoots([_n("A"), _n("Q")], childrenOf: before, animate: false);
      final xNid = controller.nidOf("x");
      final yNid = controller.nidOf("y");
      expect(controller.getParent("x"), "B", reason: "setup");
      expect(controller.getChildren("x"), ["y"], reason: "setup");
      expect(controller.getChildren("Q"), isEmpty, reason: "setup");

      // A > [C], Q > [x > [y]]: B goes away, x moves out of B's subtree.
      List<TreeNode<String, String>> after(String key) {
        switch (key) {
          case "A":
            return [_n("C")];
          case "Q":
            return [_n("x")];
          case "x":
            return [_n("y")];
        }
        return const [];
      }

      sync.syncRoots([_n("A"), _n("Q")], childrenOf: after, animate: false);

      expect(
        controller.nidOf("x"),
        xNid,
        reason: "x must be MOVED out of B, not purged with B and re-created "
            "as a fresh node at Q",
      );
      expect(
        controller.nidOf("y"),
        yNid,
        reason: "y rides along with x; a purge-and-recreate re-registers "
            "the whole subtree",
      );
      expect(controller.getParent("x"), "Q");
      expect(controller.getChildren("x"), ["y"]);
      expect(
        controller.getNodeData("B"),
        isNull,
        reason: "the deferred removal of B must still happen at the drain",
      );
      expect(controller.getChildren("A"), ["C"]);
    },
  );
}
