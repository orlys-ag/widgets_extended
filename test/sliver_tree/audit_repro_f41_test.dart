/// Audit repro for finding f41: the dragged row's element can be evicted
/// mid-drag by the post-frame stale-eviction sweep (autoscroll moves the
/// viewport far away from the source row; `RenderSliverTree.isNodeRetained`
/// has no dragged-row case). The gesture recognizer that drives the whole
/// drag lifecycle lives on that row's own `GestureDetector`, and
/// `_ReorderableRowState` has no dispose/deactivate hook — so once the
/// element is unmounted, `onLongPressEnd` / `onLongPressCancel` never fire,
/// `reorderController.endDrag()` / `cancelDrag()` is never called, the
/// session stays active forever, and the autoscroll ticker keeps jumping
/// the scroll position toward the frozen edge-zone pointer every frame.
///
/// EXPECTED (correct) behavior asserted here — agnostic to which fix lands
/// (retaining the dragged row in `isNodeRetained` OR cancelling the session
/// from a deactivate/dispose override):
///
///  1. Mid-drag invariant: the source row's element being evicted while the
///     session is still active must never happen (either the row is
///     retained, or eviction terminates the session).
///  2. Lifting the finger must end the drag session (`isDragging == false`).
///  3. After the finger lifts, the autoscroll ticker must stop — the scroll
///     position must not keep drifting on subsequent frames.
///
/// On current (buggy) code, assertion 1 fails: the row is evicted while
/// `isDragging` is still true, orphaning the session.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets(
    "f41: autoscroll-evicted source row must not orphan the drag session "
    "or leave the autoscroll ticker running",
    (tester) async {
      // 100 roots at 50 px each => 5000 px of content in a 600 px viewport
      // (default 800x600 test surface, cacheExtent defaults to 250 px).
      final tree = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      tree.setRoots([
        for (var i = 0; i < 100; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);

      final reorder = TreeReorderController<String>(
        treeController: tree,
        vsync: tester,
      );

      addTearDown(() {
        // Safety net so teardown is deterministic even when an assertion
        // above throws mid-drag: kill any orphaned session/ticker before
        // disposing.
        reorder.cancelDrag();
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
      await tester.pump();

      // Scroll deep into the list so autoscroll toward the top edge has
      // >1000 px of runway before hitting minScrollExtent.
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      scrollable.position.jumpTo(2000.0);
      await tester.pump();

      // Row r42 sits at structural y=2100..2150 => viewport-local y=100..150.
      final sourceRow = find.byKey(const ValueKey("row-r42"));
      expect(sourceRow, findsOneWidget,
          reason: "setup: source row must be visible before the drag");

      // Long-press to start the drag.
      final gesture = await tester.startGesture(tester.getCenter(sourceRow));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));

      expect(reorder.isDragging, isTrue,
          reason: "setup: long press must have started the drag session");
      expect(reorder.draggedKey, "r42",
          reason: "setup: the drag session must be for the pressed row");

      // Move the pointer into the top autoscroll edge zone (y=10 is inside
      // the default 48 px autoScrollEdgeZone) and hold it there.
      await gesture.moveTo(const Offset(400, 10));
      await tester.pump();

      // Let the autoscroll ticker run. At ~950 px/s upward it scrolls
      // ~15 px per 16 ms frame; 90 frames move the offset from 2000 to
      // roughly 630, putting r42 (structural y=2100) far outside the
      // viewport + cache region (offset + 600 + 250), where the post-frame
      // stale-eviction sweep unmounts its element.
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final scrolled = 2000.0 - scrollable.position.pixels;
      expect(scrolled, greaterThan(300.0),
          reason: "setup: the autoscroll ticker must have actually scrolled "
              "the viewport away from the source row "
              "(pixels=${scrollable.position.pixels})");

      final sourceRowMounted = tester.any(sourceRow);

      // (1) Core f41 invariant: an evicted source row must never leave an
      // active drag session behind — the row's GestureDetector was the only
      // thing that could ever call endDrag()/cancelDrag().
      expect(sourceRowMounted || !reorder.isDragging, isTrue,
          reason: "the dragged row's element was evicted by the stale "
              "eviction sweep (find.byKey(row-r42) found nothing) while "
              "reorder.isDragging is still true — the drag session is "
              "orphaned: no gesture callback can ever end it");

      // (2) Lifting the finger must end the session.
      await gesture.up();
      await tester.pump();

      expect(reorder.isDragging, isFalse,
          reason: "lifting the finger must end the drag session; if the "
              "source row's element (mounted=$sourceRowMounted) was "
              "evicted mid-drag, its recognizer was disposed and "
              "onLongPressEnd never fires, so endDrag() is never called");

      // (3) The autoscroll ticker must be stopped: the scroll offset must
      // not keep drifting after the pointer is gone.
      final pixelsAfterUp = scrollable.position.pixels;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scrollable.position.pixels, closeTo(pixelsAfterUp, 0.5),
          reason: "the autoscroll ticker must stop when the drag ends; a "
              "drifting offset means the orphaned ticker is still jumping "
              "the position toward the stale edge-zone pointer every frame");

      // Drain any commit slide with a bounded pump loop (no pumpAndSettle:
      // on buggy code the orphaned ticker would make it spin forever).
      reorder.cancelDrag();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
