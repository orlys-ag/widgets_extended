/// Regression test for the 2026-07-29 review, item 2 (part 2b):
/// [TreeController.setReorderPreview]'s target loop must iterate the
/// VALID prefix of the visible-order buffer (`visibleNodeCount` slots),
/// not the buffer's grow-only capacity. The buffer never shrinks
/// (`orderNidsView` documents "only the first N entries are valid"), so
/// after any visible high-water mark an unbounded loop scans the stale
/// capacity tail on every drop-slot retarget — a 100x multiplier on a
/// gesture-latency path for a tree that was once expanded and later
/// collapsed. The stale tail happens to produce no wrong output only
/// because the ±lift shift terms cancel to exactly zero there; this test
/// pins the iteration contract via
/// [TreeController.debugLastPreviewTargetIterationCount] so the loop
/// never rides that coincidence.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "setReorderPreview scans visibleNodeCount slots, not the order "
    "buffer's high-water capacity",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);

      // Five roots; the first carries a large collapsed subtree used only
      // to push the order buffer's high-water mark far above the final
      // visible count.
      controller.setRoots([
        for (int r = 0; r < 5; r++) TreeNode(key: "r$r", data: "R$r"),
      ]);
      controller.setChildren("r0", [
        for (int i = 0; i < 400; i++) TreeNode(key: "c$i", data: "C$i"),
      ]);

      controller.expandAll();
      expect(
        controller.visibleNodeCount,
        405,
        reason: "setup: expandAll must have grown the order buffer's "
            "high-water mark to 405",
      );

      controller.collapseAll();
      expect(
        controller.visibleNodeCount,
        5,
        reason: "setup: collapseAll must have shrunk the VISIBLE count "
            "while the buffer capacity stays at the high-water mark",
      );

      controller.setReorderPreview(
        draggedKey: "r1",
        targetKey: "r3",
        gapBelowTarget: true,
      );

      expect(
        controller.hasActiveSlides,
        isTrue,
        reason: "setup: the preview must actually have installed held "
            "offsets (proves the target loop ran)",
      );
      expect(
        controller.debugLastPreviewTargetIterationCount,
        controller.visibleNodeCount,
        reason: "the target loop must examine exactly the valid prefix of "
            "the order buffer; anything larger means it is scanning the "
            "stale capacity tail beyond visibleNodeCount",
      );

      controller.clearReorderPreview(animate: false);
    },
  );
}
