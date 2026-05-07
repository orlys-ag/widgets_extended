/// Tests for re-moving rows whose slide is already in flight — specifically
/// the "ghost being moved again" case that previously caused a visible
/// snap.
///
/// The fix has three parts:
///   1. snapshotVisibleOffsets now includes exit-ghost rows at their
///      current ghost-painted position (anchor.painted + ghost.slideDelta).
///   2. _consumeSlideBaselineIfAny no longer unconditionally clears
///      _phantomExitGhosts — ghost slides survive across consume cycles
///      until they settle (via lazy paint-time removal) or until the
///      ghosted key becomes visible again (lazy prune at end of consume).
///   3. controller.isVisible exposes the O(1) visibility check the render
///      object needs to detect ghost-became-visible cases.
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
              nodeBuilder: (context, key, depth) => SizedBox(
                key: ValueKey("row-$key"),
                height: 48,
                child: Padding(
                  padding: EdgeInsets.only(left: depth * 20.0),
                  child: Text(key),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets("ghost re-moved to visible parent does NOT snap", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 1000),
      animationCurve: Curves.linear,
    );
    addTearDown(controller.dispose);

    // Tree:
    //   A (expanded) [Y, Y2]
    //   B (COLLAPSED) [b1]
    //   C (expanded, has placeholder so expand isn't a no-op) [c1]
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

    // FIRST move: Y → B (collapsed). Y becomes an exit ghost sliding
    // into B's row.
    //   After mutation: order [A, Y2, B, C]. B at y=96.
    //   Y baseline = 48. Y destination (anchor B) = 96. delta = -48.
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
        reason: "Y is now structurally under collapsed B → hidden");
    final initialDelta = controller.getSlideDelta("Y");
    expect(initialDelta, closeTo(-48.0, 1.0));

    // Tick part-way through the ghost slide. Linear curve, 1000ms duration:
    // pump 200ms → progress ≈ 20% → currentDelta ≈ -38.4.
    await tester.pump(const Duration(milliseconds: 200));
    final midGhostDelta = controller.getSlideDelta("Y");
    expect(midGhostDelta, lessThan(0.0),
        reason: "Y is mid-exit-slide — currentDelta is still negative");
    expect(midGhostDelta, greaterThan(-48.0),
        reason: "Y has progressed toward 0 from -48");
    // Y's CURRENT painted position = B.painted + Y.slideDelta.
    // B is ALSO sliding (its row shifted from y=144 to y=96 as Y left,
    // so B.startDelta = +48, currentDelta = +38.4 mid-flight).
    // B.painted = 96 (structural) + 38.4 (slide) = 134.4.
    // Y.painted = 134.4 + (-38.4) = 96.
    final bMidSlide = controller.getSlideDelta("B");
    expect(bMidSlide, greaterThan(0.0),
        reason: "B was structurally at y=144, shifted to y=96, so its "
            "slide delta is positive (currently +38.4 ≈)");
    final yPaintedBeforeRemove = 96.0 + bMidSlide + midGhostDelta;

    // SECOND move (mid-ghost): Y → C (visible, expanded).
    //   After mutation: order [A, Y2, B, C, Y, c1]. Y at structural y=192.
    //
    // BEFORE the fix: baseline didn't include Y (ghost wasn't in
    // visibleNodes). Entry-phantom kicked in and set baseline[Y] = B's
    // position. Slide installed against the wrong baseline → visible
    // snap of `|yPaintedBeforeRemove - B.painted|` pixels.
    //
    // AFTER the fix: baseline includes Y at yPaintedBeforeRemove (via
    // ghost augmentation in snapshotVisibleOffsets). Slide installs
    // from there to current[Y]=192. Y painted at install =
    // yPaintedBeforeRemove. NO SNAP.
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
        reason: "Y was moved to expanded C → now visible");
    final newDelta = controller.getSlideDelta("Y");
    // Y's structural position under C is 192 (last row).
    // Y painted = 192 + newDelta. The fix guarantees this equals
    // yPaintedBeforeRemove (no snap).
    final yPaintedAfterRemove = 192.0 + newDelta;
    expect(yPaintedAfterRemove, closeTo(yPaintedBeforeRemove, 2.0),
        reason: "Y's painted position must be visually continuous across "
            "the re-move. Before: $yPaintedBeforeRemove, "
            "after: $yPaintedAfterRemove");

    await tester.pumpAndSettle();
  });

  testWidgets("unrelated moveNode does not drop in-flight ghost",
      (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 1000),
      animationCurve: Curves.linear,
    );
    addTearDown(controller.dispose);

    // Tree: A (expanded) [Y, Y2]; B (collapsed); C (expanded) [c1, c2].
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
    controller.setChildren("C", [
      const TreeNode(key: "c1", data: "c1"),
      const TreeNode(key: "c2", data: "c2"),
    ]);
    controller.expand(key: "A", animate: false);
    controller.expand(key: "C", animate: false);

    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    // FIRST move: Y → B (ghost slide).
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
    expect(controller.getSlideDelta("Y"), isNot(0.0),
        reason: "Y has ghost slide installed");

    // Tick part-way through.
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.getSlideDelta("Y"), isNot(0.0),
        reason: "Y is still mid-ghost-slide");

    // SECOND move: an unrelated row (c1) → c2's slot. Y is NOT touched.
    //
    // BEFORE the fix: consume cleared _phantomExitGhosts at the top, so
    // Y's ghost relationship was dropped. Y's slide stayed in the engine
    // but Y was no longer in the ghost paint pass → Y stopped being
    // painted entirely → POP.
    //
    // AFTER the fix: _phantomExitGhosts is preserved across consumes.
    // Y stays in the ghost map, continues to render, slide continues.
    controller.moveNode(
      "c1",
      "C",
      index: 1,
      animate: true,
      slideDuration: const Duration(milliseconds: 1000),
      slideCurve: Curves.linear,
    );
    await tester.pump();

    // Y must still have an active slide (its ghost survives the
    // unrelated mutation).
    expect(controller.getSlideDelta("Y"), isNot(0.0),
        reason: "Y's ghost slide must survive an unrelated moveNode "
            "(was previously dropped because consume cleared the ghost map)");

    await tester.pumpAndSettle();
    expect(controller.hasActiveSlides, false);
  });
}
