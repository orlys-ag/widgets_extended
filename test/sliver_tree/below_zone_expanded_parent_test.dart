/// Regression test for audit item 3.5: a `below`-zone drop on an
/// EXPANDED parent with visible children must commit to the slot the
/// indicator shows.
///
/// The indicator for `below` is drawn directly under the target row —
/// visually the first child's slot — but the commit used to deliver
/// "next sibling of target", potentially many rows lower (after the
/// whole expanded subtree). Resolving `below` on an expanded target as
/// first-child (identical to `into`) makes indicator and commit agree by
/// construction; collapsed/leaf targets keep sibling semantics.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets(
    "below-zone drop on an expanded parent lands as its first child, at "
    "the indicator's slot",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "p", data: "P"),
        const TreeNode(key: "x", data: "X"),
      ]);
      controller.setChildren("p", [
        const TreeNode(key: "c1", data: "C1"),
        const TreeNode(key: "c2", data: "C2"),
      ]);
      controller.expand(key: "p", animate: false);

      final reorder = TreeReorderController<String>(
        treeController: controller,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return SizedBox(
                      key: ValueKey("row-$key"),
                      height: 50,
                      child: Text(key),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );

      // Hover the bottom fifth of row "p" — squarely the below zone.
      final pTop = tester.getTopLeft(find.byKey(const ValueKey("row-p"))).dy;
      final pointer = Offset(200, pTop + 45.0);

      reorder.startDrag(
        key: "x",
        renderPort: render,
        scrollable: scrollable,
        pointerGlobal: pointer,
      );
      addTearDown(() {
        if (reorder.isDragging) {
          reorder.cancelDrag();
        }
      });

      final target = reorder.currentTarget;
      expect(target, isNotNull);
      expect(target!.targetKey, "p",
          reason: "setup: the pointer hovers row p");
      expect(target.zone, TreeDropZone.below,
          reason: "setup: the bottom of the row is the below zone");

      // The indicator sits directly under row p — the first child's slot.
      // (Since D2 the target is semantic: the widget layer derives the
      // below/into indicator edge as targetPaintedY + targetExtent.)
      expect(
        target.targetPaintedY + target.targetExtent,
        50.0,
        reason: "the below indicator edge is row p's bottom edge",
      );
      expect(
        target.parentKey,
        "p",
        reason: "below an EXPANDED parent, the slot under the row is the "
            "first-child position — commit must match the indicator",
      );
      expect(target.indexInFinalList, 0);

      reorder.endDrag();
      await tester.pumpAndSettle();

      expect(controller.getParent("x"), "p",
          reason: "x must land as a child of p (where the indicator "
              "pointed), not as p's next sibling below the whole subtree");
      expect(controller.getLiveChildren("p"), ["x", "c1", "c2"]);
    },
  );

  testWidgets(
    "below-zone drop on a collapsed parent keeps next-sibling semantics",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "p", data: "P"),
        const TreeNode(key: "q", data: "Q"),
        const TreeNode(key: "x", data: "X"),
      ]);
      controller.setChildren("p", [
        const TreeNode(key: "c1", data: "C1"),
      ]);
      // p stays collapsed.

      final reorder = TreeReorderController<String>(
        treeController: controller,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return SizedBox(
                      key: ValueKey("row-$key"),
                      height: 50,
                      child: Text(key),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );

      final pTop = tester.getTopLeft(find.byKey(const ValueKey("row-p"))).dy;
      reorder.startDrag(
        key: "x",
        renderPort: render,
        scrollable: scrollable,
        pointerGlobal: Offset(200, pTop + 45.0),
      );
      addTearDown(() {
        if (reorder.isDragging) {
          reorder.cancelDrag();
        }
      });

      final target = reorder.currentTarget;
      expect(target, isNotNull);
      expect(target!.zone, TreeDropZone.below);
      expect(target.parentKey, isNull,
          reason: "below a COLLAPSED parent stays a sibling slot");

      reorder.endDrag();
      await tester.pumpAndSettle();

      expect(controller.getParent("x"), isNull);
      expect(controller.liveRootKeys, ["p", "x", "q"],
          reason: "x lands as p's next sibling");
    },
  );
}
