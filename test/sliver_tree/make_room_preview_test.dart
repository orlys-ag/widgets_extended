/// D14 tests: the make-room preview parts rows to open a live gap at the
/// prospective drop slot — paint-only, structure untouched, seamless
/// commit handoff.
///
/// Plan verification contract: mid-drag over a new slot, rows below the
/// slot paint shifted by the dragged extent; NO structural listener fires
/// from the preview; on commit, painted positions are continuous across
/// the mutation frame (no jump). Everything here fails on pre-D14 code
/// (the APIs and the flag do not exist).
///
/// The trees use `animationDuration: Duration.zero`, which snaps preview
/// offsets (global animations-disabled convention) — painted positions
/// are deterministic per frame.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets(
    "setReorderPreview shifts exactly the span between old slot and gap "
    "(controller-level, no widget)",
    (tester) async {
      final tree = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(tree.dispose);
      tree.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
        const TreeNode(key: "d", data: "D"),
      ]);

      var structuralNotifications = 0;
      tree.addListener(() {
        structuralNotifications++;
      });

      // Drag "a", gap below "c": b and c close the vacated slot (−extent);
      // d sits past both slot and gap (net 0). No widget is mounted, so
      // rows are unmeasured and the lift is the controller's
      // defaultExtent — read it rather than assuming a magic number.
      final ext = TreeController.defaultExtent;
      tree.setReorderPreview(
        draggedKey: "a",
        targetKey: "c",
        gapBelowTarget: true,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );

      expect(tree.hasActiveSlides, isTrue,
          reason: "held preview offsets ride the composed slide read — "
              "the render layer's painted-space paths must engage");
      expect(tree.getSlideDelta("b"), -ext);
      expect(tree.getSlideDelta("c"), -ext);
      expect(tree.getSlideDelta("d"), 0.0,
          reason: "past both the vacated slot and the gap the shifts "
              "cancel");
      expect(tree.getSlideDelta("a"), 0.0,
          reason: "the dragged row itself is never shifted");
      expect(tree.maxActiveSlideAbsDelta, ext,
          reason: "preview magnitude must feed the overreach bound");

      // Re-target: gap above "b" (drop between a and b → a no-op slot for
      // a itself, but the controller-level API is policy-free): only the
      // vacated-slot closing applies below, and b/c/d all sit past both
      // edges... gap at b's top = index 1 == vacated slot → all cancel.
      tree.setReorderPreview(
        draggedKey: "a",
        targetKey: "b",
        gapBelowTarget: false,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
      expect(tree.getSlideDelta("b"), 0.0,
          reason: "gap coinciding with the vacated slot cancels to zero");
      expect(tree.hasActiveSlides, isFalse,
          reason: "all-zero targets release every entry");

      // Structure was never touched.
      expect(structuralNotifications, 0,
          reason: "the preview is paint-only — no structural channel "
              "traffic");
      expect(tree.liveRootKeys, ["a", "b", "c", "d"]);

      tree.clearReorderPreview(animate: false);
      expect(tree.hasActiveSlides, isFalse);
    },
  );

  testWidgets(
    "make-room drag opens a painted gap, stays structurally silent, and "
    "commits without a painted jump",
    (tester) async {
      final tree = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
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
                  makeRoomOnDrag: true,
                  showDragProxy: true,
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

      var structuralNotifications = 0;
      tree.addListener(() {
        structuralNotifications++;
      });

      // Long-press "a" and hover the bottom of "c" (y=145 → the slot
      // below c).
      final gesture = await tester.startGesture(const Offset(400, 25));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(const Offset(400, 145));
      await tester.pump();

      expect(reorder.currentTarget?.indexInFinalList, 2,
          reason: "setup: the slot below c is final index 2 for dragged a");

      // The gap is open in PAINT: b and c closed a's vacated slot (up
      // 50), d holds — the 100..150 band is the visible gap.
      expect(tester.getTopLeft(find.byKey(const ValueKey("row-b"))).dy, 0.0,
          reason: "b shifts up into a's vacated slot");
      expect(tester.getTopLeft(find.byKey(const ValueKey("row-c"))).dy, 50.0);
      expect(tester.getTopLeft(find.byKey(const ValueKey("row-d"))).dy, 150.0,
          reason: "d stays put — the gap opens above it");

      // ...and ONLY in paint.
      expect(structuralNotifications, 0,
          reason: "no structural listener may fire while previewing");
      expect(tree.liveRootKeys, ["a", "b", "c", "d"],
          reason: "structure is untouched mid-drag");

      // Drop. Structure commits to what the gap promised, and the rows
      // that were previewing at their destination DO NOT MOVE on the
      // commit frame — the painted world and the structural world meet.
      await gesture.up();
      await tester.pump();

      expect(tree.liveRootKeys, ["b", "c", "a", "d"],
          reason: "the drop commits the previewed slot");
      expect(structuralNotifications, greaterThan(0),
          reason: "the commit itself IS structural");
      expect(tester.getTopLeft(find.byKey(const ValueKey("row-b"))).dy, 0.0,
          reason: "no jump: b previewed at 0 and lands at structural 0");
      expect(tester.getTopLeft(find.byKey(const ValueKey("row-c"))).dy, 50.0);
      expect(tester.getTopLeft(find.byKey(const ValueKey("row-a"))).dy, 100.0,
          reason: "a materializes in the gap that was held for it");
      expect(tester.getTopLeft(find.byKey(const ValueKey("row-d"))).dy, 150.0);

      await tester.pumpAndSettle();
      expect(tree.hasActiveSlides, isFalse,
          reason: "nothing left animating after the commit settles");
    },
  );

  testWidgets(
    "the gap HOLDS across transient null targets instead of flapping "
    "under the pointer",
    (tester) async {
      final tree = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
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
        // Root drops allowed only in the first two slots — the tail of
        // the list is a genuinely dead region with no chain fallback.
        canAcceptDrop: ({required movingKey, newParent, index}) {
          return newParent == null && (index == null || index <= 1);
        },
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
                  makeRoomOnDrag: true,
                  showDragProxy: true,
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

      // Open the gap at a VALID slot: drag a to below-b (root index 1).
      final gesture = await tester.startGesture(const Offset(400, 25));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(const Offset(400, 80));
      await tester.pump();
      expect(reorder.currentTarget?.indexInFinalList, 1,
          reason: "setup: below-b is a policy-legal slot");
      expect(tree.getSlideDelta("b"), -50.0,
          reason: "setup: the gap is open after b");

      // Move into the DEAD region (below-d → index 3, vetoed, no chain).
      await gesture.moveTo(const Offset(400, 190));
      await tester.pump();
      expect(reorder.currentTarget, isNull,
          reason: "setup: the tail region is genuinely vetoed");
      expect(tree.getSlideDelta("b"), -50.0,
          reason: "a transient null target must HOLD the last gap — "
              "releasing it shifts rows under the stationary pointer and "
              "flaps the resolution forever");

      // Only session end releases it.
      reorder.cancelDrag();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tree.getSlideDelta("b"), 0.0,
          reason: "cancel releases the held gap");

      await gesture.up();
      await tester.pump();
    },
  );

  testWidgets(
    "cancelling a make-room drag closes the gap and restores painted "
    "positions",
    (tester) async {
      final tree = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
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
                  makeRoomOnDrag: true,
                  showDragProxy: true,
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

      final gesture = await tester.startGesture(const Offset(400, 25));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(const Offset(400, 145));
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const ValueKey("row-b"))).dy, 0.0,
          reason: "setup: the gap must be open before the cancel");

      reorder.cancelDrag();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tree.liveRootKeys, ["a", "b", "c", "d"],
          reason: "cancel commits nothing");
      expect(tester.getTopLeft(find.byKey(const ValueKey("row-b"))).dy, 50.0,
          reason: "b returns to its structural slot");
      expect(tester.getTopLeft(find.byKey(const ValueKey("row-d"))).dy, 150.0);
      expect(tree.hasActiveSlides, isFalse);

      await gesture.up();
      await tester.pump();
    },
  );
}
