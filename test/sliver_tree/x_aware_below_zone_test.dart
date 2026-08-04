/// D6 full-stack repro: dropping below the last row of a nested subtree
/// picks the target depth from the POINTER'S HORIZONTAL POSITION, VS
/// Code-style. `SliverReorderableTree` supplies the default x → depth
/// mapper (`x ~/ indentPerDepth`); this test drives it through a real
/// long-press drag.
///
/// Repro-test methodology: on pre-D6 code every below-boundary drop
/// resolves at the leaf row's own depth regardless of x — the depth-0 and
/// depth-1 expectations fail.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets(
    "pointer x selects the ancestor level when dropping below a 3-deep "
    "subtree boundary",
    (tester) async {
      final tree = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      // x first so root-level drops below a's subtree are not no-ops.
      tree.setRoots([
        const TreeNode(key: "x", data: "X"),
        const TreeNode(key: "a", data: "A"),
      ]);
      tree.setChildren("a", [const TreeNode(key: "b", data: "B")]);
      tree.setChildren("b", [const TreeNode(key: "c", data: "C")]);
      tree.expand(key: "a", animate: false);
      tree.expand(key: "b", animate: false);

      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
      );
      addTearDown(() {
        if (reorder.isDragging) {
          reorder.cancelDrag();
        }
        reorder.dispose();
        tree.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverReorderableTree<String, String>(
                  controller: tree,
                  reorderController: reorder,
                  indentPerDepth: 24.0,
                  nodeBuilder: (context, key, depth, wrap) {
                    return wrap(
                      longPressToDrag: true,
                      child: SizedBox(
                        key: ValueKey("row-$key"),
                        height: 50,
                        child: Text(key),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Rows: x(0..50), a(50..100), b(100..150), c(150..200). The bottom
      // fifth of row c (y=195) is the below zone at a 3-deep boundary.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey("row-x"))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(reorder.isDragging, isTrue,
          reason: "setup: long press must start the session");

      // Pointer x inside the ROOT indent column (0..24): root level.
      await gesture.moveTo(const Offset(5, 195));
      await tester.pump();
      expect(reorder.currentTarget?.zone, TreeDropZone.below,
          reason: "setup: bottom of row c is the below zone");
      expect(
        reorder.currentTarget?.parentKey,
        isNull,
        reason: "x=5 is the root indent column — the drop must target the "
            "root level, after a's whole subtree",
      );
      expect(reorder.currentTarget?.depth, 0);

      // Pointer x inside depth-1 column (24..48): sibling of b, inside a.
      await gesture.moveTo(const Offset(30, 195));
      await tester.pump();
      expect(
        reorder.currentTarget?.parentKey,
        "a",
        reason: "x=30 is depth-1's indent column — sibling of b",
      );
      expect(reorder.currentTarget?.depth, 1);

      // Pointer x far right (past every indent): the deepest candidate —
      // exactly the pre-D6 resolution, so handle-drag UIs (pointer at the
      // row's right edge) keep today's behavior.
      await gesture.moveTo(const Offset(400, 195));
      await tester.pump();
      expect(
        reorder.currentTarget?.parentKey,
        "b",
        reason: "far-right x clamps to the deepest level (sibling of c)",
      );
      expect(reorder.currentTarget?.depth, 2);

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );
}
