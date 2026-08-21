/// Regression test for issue 1 of the 2026-08-21 review: a downward drag
/// that resolves "into" a leaf committed the node as a SIBLING instead.
///
/// The drag probe resolves against PAINTED positions, which include the
/// held make-room offsets, and both scans in `findRowAtPaintedY` use a
/// single-sided hit predicate (`scrollY < painted + extent`, no lower
/// bound). For a gap at or after the hovered row, the preview shifts that
/// row UP by the dragged extent, so on a downward drag the hovered row
/// slides out from under the probe and the probe sits in the gap. The scan
/// then answered with the row BELOW the gap and the resolver classified it
/// as `above` that row. `endDrag` re-resolves before committing, so even a
/// stationary release committed the hole's answer rather than the slot the
/// preview was showing.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets("a downward drag into a leaf commits INTO it, and the target "
      "does not flip while the pointer sits in the make-room gap", (
    tester,
  ) async {
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
      const TreeNode(key: "c", data: "C"),
      const TreeNode(key: "d", data: "D"),
    ]);
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
                showDragProxy: true,
                nodeBuilder: (context, key, depth) {
                  return TreeDelayedDragHandle(
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

    // Long-press "b" (rows are 50px: a=0..50, b=50..100, c=100..150) and
    // drag DOWN into the middle third of "c", which is the `into` zone.
    final gesture = await tester.startGesture(const Offset(400, 75));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(const Offset(400, 125));
    await tester.pump();

    // Setup sanity: the resolved target really is "into c", so the path
    // this test exercises is the one described above.
    expect(
      reorder.currentTarget?.zone,
      TreeDropZone.into,
      reason: "setup: the middle third of c is the into zone",
    );
    expect(reorder.currentTarget?.parentKey, "c");

    // A 1px move keeps the pointer inside the gap the preview just opened.
    // The target must HOLD: re-classifying against the row below the gap
    // is what produced the wrong commit.
    await gesture.moveTo(const Offset(400, 126));
    await tester.pump();
    expect(reorder.currentTarget?.zone, TreeDropZone.into);
    expect(reorder.currentTarget?.parentKey, "c");

    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      tree.getParent("b"),
      "c",
      reason: "the release must commit the previewed slot, not the gap's "
          "re-resolution against the row below it",
    );
    expect(tree.rootKeys, ["a", "c", "d"]);
  });

  testWidgets("an upward drag into a leaf still commits INTO it", (
    tester,
  ) async {
    // Control: the upward direction never puts the probe in the gap (the
    // gap opens BELOW the hovered row's new position), so it worked before
    // this fix and must keep working after it.
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
      const TreeNode(key: "c", data: "C"),
      const TreeNode(key: "d", data: "D"),
    ]);
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
                showDragProxy: true,
                nodeBuilder: (context, key, depth) {
                  return TreeDelayedDragHandle(
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

    // Drag "d" (150..200) UP into the middle third of "c" (100..150).
    final gesture = await tester.startGesture(const Offset(400, 175));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(const Offset(400, 125));
    await tester.pump();
    expect(reorder.currentTarget?.zone, TreeDropZone.into);
    expect(reorder.currentTarget?.parentKey, "c");

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tree.getParent("d"), "c");
  });

  testWidgets("a probe above the FIRST row still resolves to the top slot", (
    tester,
  ) async {
    // Degradation control for the gap guard (found by the 2026-08-21
    // audit of this fix): at the top of the list the probe is legitimately
    // above row 0's band, which satisfies the guard's first condition. The
    // index equality is what keeps that case honest, the guard only holds
    // when the hovered row is the one directly below the PREVIEWED gap, so
    // a pointer arriving at the top from a different slot re-resolves.
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
      const TreeNode(key: "c", data: "C"),
      const TreeNode(key: "d", data: "D"),
    ]);
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
                showDragProxy: true,
                nodeBuilder: (context, key, depth) {
                  return TreeDelayedDragHandle(
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

    // Grab "d" near its bottom edge so the midpoint probe shifts upward,
    // hover a mid-list slot, then travel to the very top.
    final gesture = await tester.startGesture(const Offset(400, 195));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(const Offset(400, 60));
    await tester.pump();
    expect(
      reorder.currentTarget?.gapVisibleIndex,
      1,
      reason: "setup: the previewed gap is NOT the top slot",
    );

    await gesture.moveTo(const Offset(400, 2));
    await tester.pump();
    expect(reorder.currentTarget?.zone, TreeDropZone.above);
    expect(reorder.currentTarget?.gapVisibleIndex, 0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tree.rootKeys, ["d", "a", "b", "c"]);
  });
}
