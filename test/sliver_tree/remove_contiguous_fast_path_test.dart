/// Regression tests for audit item 5.4: `_purgeAndRemoveFromOrder`
/// (every non-animated `remove()`) must use the contiguous range-removal
/// fast path instead of always paying an O(N + nidCapacity) full-order
/// sweep + reverse-index memset.
///
/// The purge used to release nids BEFORE compacting, so by compaction
/// time every key reported "not visible" and the removal always took the
/// non-contiguous branch (`removeWhereKeyIn` scan + `resetIndexAll`).
/// Capturing indices before the purge restores the O(range + suffix)
/// path for the dominant case (a subtree is contiguous in the visible
/// order by construction).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "single-leaf non-animated remove does not trigger a full "
    "reverse-index reset",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        for (int i = 0; i < 50; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);

      final before = controller.debugOrderResetIndexAllCount;
      controller.remove(key: "r25", animate: false);
      expect(
        controller.debugOrderResetIndexAllCount,
        before,
        reason: "a single visible leaf is trivially contiguous — its "
            "removal must use the range fast path, not the full sweep "
            "with an O(nidCapacity) reverse-index memset",
      );
      expect(controller.visibleNodes.length, 49);
      expect(controller.getNodeData("r25"), isNull);
      controller.debugAssertVisibleSubtreeSizeConsistency();
    },
  );

  testWidgets(
    "expanded-subtree non-animated remove uses the contiguous fast path "
    "and stays consistent",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "p", data: "P"),
        const TreeNode(key: "z", data: "Z"),
      ]);
      controller.setChildren("p", [
        for (int i = 0; i < 10; i++) TreeNode(key: "c$i", data: "C$i"),
      ]);
      controller.setChildren("c3", [
        const TreeNode(key: "g", data: "G"),
      ]);
      controller.expand(key: "p", animate: false);
      controller.expand(key: "c3", animate: false);
      expect(controller.visibleNodes.length, 14);

      // p + its expanded subtree occupy a contiguous run of the visible
      // order by construction.
      final before = controller.debugOrderResetIndexAllCount;
      controller.remove(key: "p", animate: false);
      expect(
        controller.debugOrderResetIndexAllCount,
        before,
        reason: "an expanded subtree is contiguous in the visible order — "
            "its removal must use the range fast path",
      );
      expect(controller.visibleNodes, ["a", "z"]);
      expect(controller.getNodeData("p"), isNull);
      expect(controller.getNodeData("g"), isNull);
      controller.debugAssertVisibleSubtreeSizeConsistency();
    },
  );

  testWidgets(
    "collapsed-parent remove (hidden descendants in the batch) keeps the "
    "safe sweep and stays consistent",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "p", data: "P"),
        const TreeNode(key: "z", data: "Z"),
      ]);
      controller.setChildren("p", [
        const TreeNode(key: "c0", data: "C0"),
        const TreeNode(key: "c1", data: "C1"),
      ]);
      // p stays collapsed: its children are in the batch but hold no
      // visible-order slots — the conservative sweep handles this shape.
      controller.remove(key: "p", animate: false);
      expect(controller.visibleNodes, ["a", "z"]);
      expect(controller.getNodeData("c0"), isNull);
      controller.debugAssertVisibleSubtreeSizeConsistency();
    },
  );
}
