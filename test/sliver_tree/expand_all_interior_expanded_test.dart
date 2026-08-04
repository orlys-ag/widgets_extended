/// Regression tests for audit item 1.7: `expandAll` must animate every
/// node that becomes visible, including descendants revealed through
/// interior nodes that are ALREADY expanded (whose expansion flag was
/// deliberately preserved by a prior `collapse()`), and descendants past
/// the `maxDepth` boundary that are visible through their own expansion.
///
/// Buggy behavior: `expandAll` harvests only the direct children of nodes
/// whose expansion flag flips. A hidden interior node B that is already
/// `expanded == true` becomes visible together with its children when
/// ancestor A expands, but B's children never enter the bulk group and
/// render at full extent from frame one — while `expand(key: A)` on the
/// identical structure animates the whole revealed subtree.
library;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "expandAll animates descendants revealed through an already-expanded "
    "interior node",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 300), curve: Curves.linear)),
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
      controller.setChildren("b", [TreeNode(key: "c", data: "C")]);
      controller.expand(key: "a", animate: false);
      controller.expand(key: "b", animate: false);

      // Collapse A — B keeps expanded == true (state deliberately
      // preserved by collapse()).
      controller.collapse(key: "a", animate: false);
      expect(controller.isExpanded("b"), isTrue,
          reason: "setup: collapse(a) must preserve b's expansion flag");
      expect(controller.visibleNodes, ["a"],
          reason: "setup: only the collapsed root is visible");

      controller.expandAll();

      // B and C become visible together (B was already expanded); both
      // must join the bulk enter animation on frame 1.
      expect(controller.visibleNodes, containsAll(["a", "b", "c"]));
      expect(controller.isBulkMember("b"), isTrue,
          reason: "b is a direct child of the flipped node a");
      expect(
        controller.isBulkMember("c"),
        isTrue,
        reason: "c is revealed through the already-expanded b and must "
            "animate in with the rest of the revealed subtree — "
            "expand(key: a) on the identical structure animates it",
      );

      await tester.pumpAndSettle();
      expect(controller.visibleNodes, ["a", "b", "c"]);
    },
  );

  testWidgets(
    "expandAll(maxDepth:) animates descendants visible through their own "
    "expansion beyond the depth boundary",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 300), curve: Curves.linear)),
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
      controller.setChildren("b", [TreeNode(key: "c", data: "C")]);
      // b (depth 1) is expanded; a is collapsed.
      controller.expand(key: "a", animate: false);
      controller.expand(key: "b", animate: false);
      controller.collapse(key: "a", animate: false);
      expect(controller.isExpanded("b"), isTrue);

      // maxDepth: 1 flips only depth-0 nodes (a). b sits at the boundary
      // and is not descended into — but it is already expanded, so c
      // becomes visible anyway and must animate.
      controller.expandAll(maxDepth: 1);

      expect(controller.visibleNodes, containsAll(["a", "b", "c"]));
      expect(controller.isBulkMember("b"), isTrue);
      expect(
        controller.isBulkMember("c"),
        isTrue,
        reason: "c is visible through b's own (preserved) expansion even "
            "though the DFS stops descending at the maxDepth boundary",
      );

      await tester.pumpAndSettle();
      expect(controller.visibleNodes, ["a", "b", "c"]);
    },
  );
}
