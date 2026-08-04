/// Regression tests for audit item 1.5: `expandAll` / `collapseAll` must
/// flush the deferred in-batch visible-order rebuild on entry (like every
/// other mutator) before making animation-membership decisions.
///
/// Inside `runBatch(() { moveNode(...); expandAll(); })` the order buffer
/// still reflects state at batch entry. Without an entry flush:
///   - `expandAll` reads `!_order.contains(child)` while collecting
///     `nodesToShow`, so a child whose visibility was changed by the
///     earlier in-batch mutation is misclassified (omitted from the bulk
///     group -> pops in at full extent).
///   - `collapseAll` collects `_getVisibleDescendants(root)` from the
///     stale order, so a node made visible by the earlier in-batch
///     mutation is missed (never joins the bulk group -> pops out).
library;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "expandAll inside runBatch after moveNode classifies moved-in children "
    "against the fresh visible order (bulk membership)",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 300), curve: Curves.linear)),
      );
      addTearDown(controller.dispose);

      // p is a collapsed parent with child c; x is a visible root.
      controller.setRoots([
        TreeNode(key: "p", data: "P"),
        TreeNode(key: "x", data: "X"),
      ]);
      controller.setChildren("p", [TreeNode(key: "c", data: "C")]);

      expect(controller.visibleNodes.contains("x"), isTrue,
          reason: "setup: x starts visible as a root");

      controller.runBatch(() {
        // x moves under the (still collapsed) p — structurally invisible
        // now, but the stale in-batch order still contains it.
        controller.moveNode("x", "p", index: 0, animate: false);
        // expandAll must see the POST-move order: x is not visible, so it
        // belongs in nodesToShow and must join the bulk enter animation
        // alongside c.
        controller.expandAll();
      });

      expect(controller.isBulkMember("c"), isTrue,
          reason: "c was hidden under collapsed p and must animate in");
      expect(
        controller.isBulkMember("x"),
        isTrue,
        reason: "x became hidden by the in-batch moveNode; expandAll must "
            "classify it against the fresh order and add it to the bulk "
            "group instead of letting it pop in at full extent",
      );

      await tester.pumpAndSettle();
      expect(controller.visibleNodes, containsAll(["p", "x", "c"]));
    },
  );

  testWidgets(
    "collapseAll inside runBatch after moveNode collects moved-in "
    "descendants against the fresh visible order (bulk membership)",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 300), curve: Curves.linear)),
      );
      addTearDown(controller.dispose);

      // p is an expanded parent with child c; q is a collapsed parent
      // hiding x.
      controller.setRoots([
        TreeNode(key: "p", data: "P"),
        TreeNode(key: "q", data: "Q"),
      ]);
      controller.setChildren("p", [TreeNode(key: "c", data: "C")]);
      controller.setChildren("q", [TreeNode(key: "x", data: "X")]);
      controller.expand(key: "p", animate: false);

      expect(controller.visibleNodes.contains("x"), isFalse,
          reason: "setup: x starts hidden under collapsed q");

      controller.runBatch(() {
        // x moves under the expanded p — structurally visible now, but
        // the stale in-batch order does not contain it yet.
        controller.moveNode("x", "p", index: 0, animate: false);
        // collapseAll must see the POST-move order: x is a visible
        // descendant of p and must join the bulk exit animation.
        controller.collapseAll();
      });

      expect(controller.isBulkMember("c"), isTrue,
          reason: "c was visible under p and must animate out");
      expect(
        controller.isBulkMember("x"),
        isTrue,
        reason: "x became visible by the in-batch moveNode; collapseAll "
            "must collect it from the fresh order and animate it out "
            "instead of letting it pop out in one frame",
      );

      await tester.pumpAndSettle();
      expect(controller.visibleNodes, ["p", "q"]);
    },
  );
}
