/// Regression tests for audit item 2.2: [TreeSyncController] must diff
/// against CONTROLLER truth, not a private tracking mirror.
///
/// Any structural mutation that bypasses the sync layer (the documented
/// `TreeItemView.controller` escape hatch, or `TreeReorderController`
/// committing a drop via moveNode/reorderChildren/reorderRoots) used to
/// desynchronize the mirror with no detection: subsequent syncs diffed
/// against fiction — a re-added key was judged "retained" and never
/// re-inserted, an externally-added key was never removed, and the
/// flagship "reorderable synced tree" composition silently mis-diffed
/// after every drop.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "external controller.remove() composes with a later sync that re-adds "
    "the key",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      sync.syncRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ], animate: false);
      expect(controller.visibleNodes, ["a", "b"]);

      // External mutation through the escape hatch.
      controller.remove(key: "b", animate: false);
      expect(controller.visibleNodes, ["a"]);

      // The next sync desires b again. A mirror-based diff judges b
      // "retained" (the mirror still lists it) and never re-inserts it.
      sync.syncRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ], animate: false);

      expect(controller.visibleNodes, ["a", "b"],
          reason: "b was externally removed; the sync desiring b must "
              "re-insert it (external mutations are the new baseline)");
      expect(controller.getNodeData("b"), isNotNull);
    },
  );

  testWidgets(
    "externally added root is removed by the next sync that does not "
    "desire it",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      sync.syncRoots([TreeNode(key: "a", data: "A")], animate: false);

      // External insert through the escape hatch.
      controller.insertRoot(
        const TreeNode(key: "ext", data: "EXT"),
        animate: false,
      );
      expect(controller.visibleNodes, ["a", "ext"]);

      // The next sync does not desire ext: it must be removed. A
      // mirror-based diff never sees ext (it is not in the mirror) and
      // leaves it in the tree forever.
      sync.syncRoots([TreeNode(key: "a", data: "A")], animate: false);

      expect(controller.visibleNodes, ["a"],
          reason: "ext is not desired; the sync must remove it");
      expect(controller.getNodeData("ext"), isNull);
    },
  );

  testWidgets(
    "drag-commit reorder (moveNode, as TreeReorderController.endDrag "
    "issues) followed by a sync reflecting the new order is a clean no-op",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      List<TreeNode<String, String>> childrenOf(String key) {
        return key == "p"
            ? const [
                TreeNode(key: "x", data: "X"),
                TreeNode(key: "y", data: "Y"),
                TreeNode(key: "z", data: "Z"),
              ]
            : const <TreeNode<String, String>>[];
      }

      sync.syncRoots(
        [const TreeNode(key: "p", data: "P")],
        childrenOf: childrenOf,
        animate: false,
      );
      controller.expand(key: "p", animate: false);
      expect(controller.getLiveChildren("p"), ["x", "y", "z"]);

      // Drag-commit: the user drags z above x. This is exactly what
      // TreeReorderController.endDrag issues on a same-parent drop.
      controller.moveNode("z", "p", index: 0, animate: false);
      expect(controller.getLiveChildren("p"), ["z", "x", "y"]);

      // Server state now reflects the new order; the app re-syncs.
      List<TreeNode<String, String>> newChildrenOf(String key) {
        return key == "p"
            ? const [
                TreeNode(key: "z", data: "Z"),
                TreeNode(key: "x", data: "X"),
                TreeNode(key: "y", data: "Y"),
              ]
            : const <TreeNode<String, String>>[];
      }

      sync.syncRoots(
        [const TreeNode(key: "p", data: "P")],
        childrenOf: newChildrenOf,
        animate: false,
      );

      expect(controller.getLiveChildren("p"), ["z", "x", "y"],
          reason: "the sync mirrors the committed order — no mis-diff");
      expect(controller.visibleNodes, ["p", "z", "x", "y"],
          reason: "no duplicate or lost rows after drop + re-sync");
    },
  );

  testWidgets(
    "external cross-parent moveNode composes with a later syncChildren "
    "on the old parent",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      sync.syncRoots(
        [
          const TreeNode(key: "a", data: "A"),
          const TreeNode(key: "b", data: "B"),
        ],
        childrenOf: (key) => key == "a"
            ? const [TreeNode(key: "x", data: "X")]
            : const <TreeNode<String, String>>[],
        animate: false,
      );

      // Drag-commit: x moves from a to b (an "into" drop).
      controller.moveNode("x", "b", animate: false);
      expect(controller.getParent("x"), "b");

      // A later sync wants x back under a. A mirror-based diff sees x
      // still tracked under a, judges it retained, and never moves it.
      sync.syncChildren(
        "a",
        const [TreeNode(key: "x", data: "X")],
        animate: false,
      );
      expect(controller.getParent("x"), "a",
          reason: "x must move back under a — the mirror's stale view of "
              "a's children must not mask the externally-moved child");
    },
  );
}
