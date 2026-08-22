/// Regression test for issue 13 of the 2026-08-21 review:
/// `syncMultipleChildren` destroyed a mover's subtree when `animate` was
/// false.
///
/// Step 1 of the children sync defers removing a child that is desired
/// under a DIFFERENT parent in the same call, but it checked only the
/// removed key itself, never its descendants. So a parent that is being
/// removed while one of its children is desired elsewhere was removed
/// first, and `remove(animate: false)` purges the whole subtree
/// immediately: the mover was re-created as a fresh leaf at its
/// destination, with its own children gone.
///
/// With `animate: true` the same sequence survived by accident, because
/// the pending-deletion subtree is revived when `moveNode` reparents it.
/// That is why the defect is animate-dependent, and why both values are
/// pinned here.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

TreeNode<String, String> _n(String key) => TreeNode(key: key, data: key);

void main() {
  for (final animate in [false, true]) {
    testWidgets("a cross-parent mover keeps its subtree (animate: $animate)", (
      tester,
    ) async {
      final controller = TreeController<String, String>(vsync: tester);
      addTearDown(controller.dispose);
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(sync.dispose);

      // A > [B, C], B > [x], x > [y], plus an empty destination Q.
      sync.syncRoots([_n("A"), _n("Q")], animate: false);
      sync.syncChildren("A", [_n("B"), _n("C")], animate: false);
      sync.syncChildren("B", [_n("x")], animate: false);
      sync.syncChildren("x", [_n("y")], animate: false);
      controller.expandAll(animate: false);
      expect(controller.getChildren("x"), ["y"], reason: "setup");

      // B is dropped from A while x, its child, is desired under Q.
      sync.syncMultipleChildren({
        "A": [_n("C")],
        "Q": [_n("x")],
      }, animate: animate);
      await tester.pumpAndSettle();

      expect(controller.getParent("x"), "Q");
      expect(
        controller.getChildren("x"),
        ["y"],
        reason: "the mover's own subtree must survive its old parent's "
            "removal",
      );
      expect(controller.getNodeData("y"), isNotNull);
      expect(controller.getNodeData("B"), isNull, reason: "B was dropped");
      expect(controller.getChildren("A"), ["C"]);
    });
  }

  testWidgets("a removed parent with no desired descendant is still removed "
      "immediately", (tester) async {
    // Control: the deferral is scoped to subtrees that contain a mover,
    // so an ordinary removal keeps its existing timing and does not
    // linger past the call.
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    final sync = TreeSyncController<String, String>(
      treeController: controller,
    );
    addTearDown(sync.dispose);

    sync.syncRoots([_n("A"), _n("Q")], animate: false);
    sync.syncChildren("A", [_n("B"), _n("C")], animate: false);
    sync.syncChildren("B", [_n("x")], animate: false);

    sync.syncMultipleChildren({
      "A": [_n("C")],
      "Q": [_n("q1")],
    }, animate: false);

    expect(controller.getNodeData("B"), isNull);
    expect(controller.getNodeData("x"), isNull, reason: "purged with B");
    expect(controller.getChildren("A"), ["C"]);
    expect(controller.getChildren("Q"), ["q1"]);
  });

  testWidgets("a mover that stays under a removed parent's sibling is "
      "unaffected", (tester) async {
    // Control: only the parent whose subtree contains a globally desired
    // key is deferred; the rest of the batch behaves as before.
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    final sync = TreeSyncController<String, String>(
      treeController: controller,
    );
    addTearDown(sync.dispose);

    sync.syncRoots([_n("A"), _n("Q")], animate: false);
    sync.syncChildren("A", [_n("B"), _n("C")], animate: false);
    sync.syncChildren("B", [_n("x")], animate: false);
    sync.syncChildren("C", [_n("z")], animate: false);

    sync.syncMultipleChildren({
      "A": [_n("C")],
      "Q": [_n("x")],
    }, animate: false);

    expect(controller.getParent("x"), "Q");
    expect(controller.getParent("z"), "C", reason: "C was never removed");
    expect(controller.getChildren("C"), ["z"]);
  });
}
