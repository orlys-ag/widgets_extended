/// Regression test for audit item 1.11: `moveNode(animate: true)` must
/// populate the pending phantom-anchor maps only when at least one render
/// host is actually participating in the slide cycle.
///
/// With no participating host (controller not mounted / detached), nothing
/// drains the maps — a LATER animated mutation's baseline consumption
/// would then apply anchors recorded for a long-finished move to the
/// wrong slide cycle.
library;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "entry-phantom anchors are not staged when no render host participates",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 300), curve: Curves.easeInOut)),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "p", data: "P"),
        const TreeNode(key: "q", data: "Q"),
      ]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      // p stays collapsed — c is hidden.

      // Animated move of the HIDDEN c to root level. This is the
      // entry-phantom path: with a mounted host it records c -> p anchor
      // relationships. With no host mounted, nothing will ever consume
      // them — they must not be staged.
      controller.moveNode("c", null, animate: true);

      expect(
        controller.takePendingPhantomAnchors(),
        isNull,
        reason: "no render host participated in the slide cycle, so no "
            "phantom anchors may be left staged for a later cycle",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "exit-phantom anchors are not staged when no render host participates",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 300), curve: Curves.easeInOut)),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "p", data: "P"),
        const TreeNode(key: "q", data: "Q"),
      ]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      // p stays collapsed.

      // Animated move of the VISIBLE q under the collapsed p — the
      // exit-phantom path (visible -> hidden).
      controller.moveNode("q", "p", animate: true);

      expect(
        controller.takePendingExitPhantomAnchors(),
        isNull,
        reason: "no render host participated in the slide cycle, so no "
            "exit-phantom anchors may be left staged for a later cycle",
      );
      await tester.pumpAndSettle();
    },
  );
}
