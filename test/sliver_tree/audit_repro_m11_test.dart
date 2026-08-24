/// Repro for M11: the hidden dragged row shadows rows the make-room
/// preview shifted into its band.
///
/// A held preview lifts the dragged row (plus its visible subtree) out of
/// the painted surface: the reorderable widget hides it so its slot can
/// close, and rows after it paint over its band. The lifted rows stay laid
/// out at their structural offsets, and every `findRowAtPaintedY` scan
/// walked visible-index order skipping only pending-deletion rows, so the
/// lower-index hidden row won over the shifted row painted at the same y.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

TreeController<String, String> _tree(WidgetTester tester) {
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
  return tree;
}

Widget _plainHarness(TreeController<String, String> tree) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverTree<String, String>(
            controller: tree,
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
  );
}

RenderSliverTree<String, String> _render(WidgetTester tester) {
  return tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
}

void main() {
  group("controller-level preview, render lookups", () {
    testWidgets("bounded scan: the row shifted into the lifted band wins", (
      tester,
    ) async {
      final tree = _tree(tester);
      addTearDown(tree.dispose);
      await tester.pumpWidget(_plainHarness(tree));
      await tester.pumpAndSettle();
      final render = _render(tester);

      // Drag a, gap below c: b and c close the vacated slot (-50).
      tree.setReorderPreviewAtIndex(draggedKey: "a", gapVisibleIndex: 3);
      expect(
        tree.hasActiveSlides,
        isTrue,
        reason: "setup: the held preview must route to the slide-aware scan",
      );
      expect(
        render.paintedRowBounds("b")!.paintedOffset,
        0.0,
        reason: "setup: b is painted in a's band",
      );

      final hit = render.findRowAtPaintedY(40.0);
      expect(
        render.debugLastFindRowUsedFullScan,
        isFalse,
        reason: "setup: the bounded scan must have answered",
      );
      expect(
        hit!.key,
        "b",
        reason: "the row PAINTED at y 40 is b; the lifted a is laid out "
            "there but hidden, and must be skipped like a pending-deletion "
            "row",
      );
      expect(hit.paintedOffset, 0.0);
    });

    testWidgets("full scan: same answer through the exact oracle", (
      tester,
    ) async {
      final tree = _tree(tester);
      addTearDown(tree.dispose);
      await tester.pumpWidget(_plainHarness(tree));
      await tester.pumpAndSettle();
      final render = _render(tester);

      tree.setReorderPreviewAtIndex(draggedKey: "a", gapVisibleIndex: 3);
      expect(tree.hasActiveSlides, isTrue, reason: "setup");

      // The lifted row's extent still counts toward structural offsets:
      // c sits at structural 100 shifted by -50.
      final below = render.debugFindRowFullScan(60.0);
      expect(
        below!.key,
        "c",
        reason: "the lifted row's extent must keep accumulating into the "
            "structural offsets of the rows after it",
      );
      expect(below.paintedOffset, 50.0);
      final hit = render.debugFindRowFullScan(40.0);
      expect(
        hit!.key,
        "b",
        reason: "the full scan must skip the lifted range on its inclusion "
            "test",
      );
    });

    testWidgets("fast path: an own-slot hover still hides the lifted row", (
      tester,
    ) async {
      final tree = _tree(tester);
      addTearDown(tree.dispose);
      await tester.pumpWidget(_plainHarness(tree));
      await tester.pumpAndSettle();
      final render = _render(tester);

      // Own slot: every shift cancels, the engine holds no entries, and
      // the routing takes the no-delta fast path while a is still hidden.
      tree.setReorderPreviewAtIndex(draggedKey: "a", gapVisibleIndex: 0);
      expect(
        tree.hasActiveSlides,
        isFalse,
        reason: "setup: an own-slot preview installs no offsets",
      );

      final hit = render.findRowAtPaintedY(25.0);
      expect(
        render.debugLastFindRowUsedFullScan,
        isFalse,
        reason: "setup: the fast path must have answered",
      );
      expect(
        hit!.key,
        "b",
        reason: "with nothing shifted, the first painted row below the "
            "lifted block is b, so a parked pointer resolves above it "
            "(the own-slot gap), never to the hidden a",
      );
      expect(hit.paintedOffset, 50.0);

      tree.clearReorderPreview(animate: false);
      expect(
        render.findRowAtPaintedY(25.0)!.key,
        "a",
        reason: "clearing the preview releases the lifted range",
      );
    });
  });

  testWidgets("end to end: moving the pointer over the closed slot targets "
      "the row painted there and commits [b, a, c, d]", (tester) async {
    final tree = _tree(tester);
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
    final render = tester.renderObject<RenderSliverTree<String, String>>(
      find.byType(SliverTree<String, String>),
    );

    // Rows: a(0..50), b(50..100), c(100..150), d(150..200). Long-press a
    // at its center so the probe sits on the pointer.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("row-a"))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(reorder.isDragging, isTrue, reason: "setup: the drag started");

    // Bottom of c: gap below c, so b and c close a's slot.
    await gesture.moveTo(const Offset(20, 145));
    await tester.pump();
    expect(reorder.currentTarget?.targetKey, "c", reason: "setup");
    expect(reorder.currentTarget?.zone, TreeDropZone.below, reason: "setup");
    expect(
      render.paintedRowBounds("b")!.paintedOffset,
      0.0,
      reason: "setup: b has slid into a's band",
    );

    // Back over the closed slot: the row painted there is b.
    await gesture.moveTo(const Offset(20, 40));
    await tester.pump();
    expect(
      reorder.currentTarget?.targetKey,
      "b",
      reason: "the pointer is over b as painted; the hidden a must not "
          "shadow it",
    );
    expect(reorder.currentTarget?.gapVisibleIndex, 2);
    expect(
      render.paintedRowBounds("b")!.paintedOffset,
      0.0,
      reason: "the gap moved below b, so b keeps its shifted position",
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tree.rootKeys, ["b", "a", "c", "d"]);
  });
}
