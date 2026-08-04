/// Audit repro for finding f14: the exit-ghost augmentation in
/// `snapshotVisibleOffsets` (render_sliver_tree.dart:1293-1296) computes the
/// ghost's painted position as `anchorPos.y + ghostSlideY`, where
/// `anchorPos.y` is the anchor's LIVE painted position (structural + the
/// anchor's own in-flight slide delta). But Pass A.5 actually paints exit
/// ghosts at the anchor's SETTLED top (structural layoutOffset WITHOUT the
/// anchor's slide) minus the direction-aware tuck, plus the ghost's own
/// slide (render_sliver_tree.dart:2684-2701).
///
/// Consequence: when a ghost is re-moved mid-slide, the new slide's baseline
/// diverges from where the ghost was ACTUALLY painted by
/// `anchorSlideDelta + tuck` — a visible t=0 snap of exactly that many
/// pixels.
///
/// This test captures the ghost's TRUE painted position from the paint-time
/// debug oracle (`debugLastPhantomGhostPaint`, sliver-local == scroll-space
/// at scrollOffset 0) and asserts visual continuity against THAT, rather
/// than against the stale snapshot formula (which the existing
/// ghost_remove_in_flight_test.dart oracle happens to mirror, masking the
/// bug). Expected on buggy code: fails by ~38.4px (the anchor B's in-flight
/// slide delta at 20% of a 48px slide).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Widget _harness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: 48,
                  child: Padding(
                    padding: EdgeInsets.only(left: depth * 20.0),
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
}

RenderSliverTree<String, String> _render(WidgetTester tester) {
  return tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
}

void main() {
  testWidgets(
    "re-moved mid-slide exit ghost installs its new slide from the ACTUAL "
    "painted position (Pass A.5), not the stale live-anchor formula",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 1000), curve: Curves.linear)),
      );
      addTearDown(controller.dispose);

      // Tree:
      //   A (expanded) [Y, Y2]
      //   B (COLLAPSED) [b1]
      //   C (expanded) [c1]
      // Layout: A=0, Y=48, Y2=96, B=144, C=192, c1=240.
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
        const TreeNode(key: "C", data: "C"),
      ]);
      controller.setChildren("A", [
        const TreeNode(key: "Y", data: "Y"),
        const TreeNode(key: "Y2", data: "Y2"),
      ]);
      controller.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);
      controller.setChildren("C", [const TreeNode(key: "c1", data: "c1")]);
      controller.expand(key: "A", animate: false);
      controller.expand(key: "C", animate: false);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      // FIRST move: Y -> B (collapsed). Y becomes an exit ghost anchored to
      // B. After mutation the visible order is [A, Y2, B, C, c1], so B's
      // structural (settled) y is 96 and B itself slides 144 -> 96
      // (startDelta +48).
      controller.moveNode(
        "Y",
        "B",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 1000),
        slideCurve: Curves.linear,
      );
      await tester.pump();
      expect(controller.hasActiveSlides, true);
      expect(controller.isVisible("Y"), false,
          reason: "Y is now structurally under collapsed B -> hidden (ghost)");

      // Tick to 20% of the 1000ms linear slide.
      await tester.pump(const Duration(milliseconds: 200));

      // Sanity: the anchor B is itself still mid-slide. This is the exact
      // precondition of the finding — if B's slide were 0, the stale formula
      // and Pass A.5 would coincide (modulo tuck, which is 0 here since ghost
      // and anchor rows are the same height) and the test would prove nothing.
      final bMidSlide = controller.getSlideDelta("B");
      expect(bMidSlide, greaterThan(10.0),
          reason: "precondition: anchor B must have a substantial in-flight "
              "slide delta for the divergence to be observable");
      final midGhostDelta = controller.getSlideDelta("Y");
      expect(midGhostDelta, lessThan(0.0),
          reason: "precondition: Y's own ghost slide is still in flight");

      // Capture Y's TRUE painted position from the Pass A.5 paint-time
      // oracle. Sliver-local coordinates; scrollOffset is 0 and the tree is
      // the only sliver, so this equals scroll-space y.
      final render = _render(tester);
      expect(render.debugLastPhantomGhostPaint.containsKey("Y"), isTrue,
          reason: "precondition: Y must be painted as a sliding exit ghost "
              "this frame (Pass A.5 debug capture)");
      final double actualPaintedY =
          render.debugLastPhantomGhostPaint["Y"]!.ghostRect.top;

      // SECOND move (mid-ghost): Y -> C (visible, expanded).
      // After mutation the visible order is [A, Y2, B, C, Y, c1]; Y's
      // structural y is 192. The staging snapshot taken inside moveNode is
      // the baseline for Y's new slide, so at t=0 of the new slide Y is
      // painted at 192 + newDelta. For visual continuity (the augmentation's
      // stated purpose, I-AGREE) that MUST equal the position Y was actually
      // painted at on the previous frame.
      controller.moveNode(
        "Y",
        "C",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 1000),
        slideCurve: Curves.linear,
      );
      await tester.pump();

      expect(controller.isVisible("Y"), true,
          reason: "Y was moved to expanded C -> now visible");
      final newDelta = controller.getSlideDelta("Y");
      final double paintedAfterRemove = 192.0 + newDelta;

      expect(
        paintedAfterRemove,
        closeTo(actualPaintedY, 2.0),
        reason: "Y's painted position must be visually continuous across the "
            "re-move. Pass A.5 actually painted Y at $actualPaintedY "
            "(settled anchor top 96 - tuck + ghostSlide $midGhostDelta), but "
            "the new slide installs Y at $paintedAfterRemove. The "
            "difference is the anchor's in-flight slide delta "
            "($bMidSlide px) that the snapshotVisibleOffsets exit-ghost "
            "augmentation wrongly includes -> visible t=0 snap.",
      );

      // Bounded drain of remaining animations (no unbounded pumpAndSettle).
      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.hasActiveSlides, false);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
