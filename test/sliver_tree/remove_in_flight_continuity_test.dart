/// Tests for two specific re-move-while-in-flight scenarios that previously
/// snapped despite the ghost-based fixes:
///
/// 1. Entry-phantom row (sliding out from behind a collapsed parent) gets
///    re-moved before its slide settles. Prior bug: consume cleared
///    _phantomClipAnchors → previously-occluded portion of the row popped
///    into view. Fix: don't clear; lazy-prune settled clips.
///
/// 2. Ghost row (under collapsed parent, mid-exit-slide) gets re-moved to
///    ANOTHER collapsed parent. Prior bug: controller's exit-phantom check
///    requires wasVisible=true (ghost is hidden, fails check) → no new
///    slide installed → ghost popped out. Fix: render-side fallback that
///    derives a new exit anchor from the controller's parent chain.
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
  testWidgets("entry-phantom row re-moved mid-slide preserves clip",
      (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 1000),
      animationCurve: Curves.linear,
    );
    addTearDown(controller.dispose);

    // P (collapsed, holds Y); Q (expanded); R (expanded with placeholder).
    controller.setRoots([
      const TreeNode(key: "P", data: "P"),
      const TreeNode(key: "Q", data: "Q"),
      const TreeNode(key: "R", data: "R"),
    ]);
    controller.setChildren("P", [const TreeNode(key: "Y", data: "Y")]);
    controller.setChildren("Q", [const TreeNode(key: "q1", data: "q1")]);
    controller.setChildren("R", [const TreeNode(key: "r1", data: "r1")]);
    controller.expand(key: "Q", animate: false);
    controller.expand(key: "R", animate: false);

    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    // FIRST move: Y from collapsed P → expanded Q (entry phantom).
    // Y's phantom anchor = P (Y's old visible ancestor). Y starts
    // sliding from P's row outward.
    controller.moveNode(
      "Y",
      "Q",
      index: 0,
      animate: true,
      slideDuration: const Duration(milliseconds: 1000),
      slideCurve: Curves.linear,
    );
    await tester.pump();
    expect(controller.hasActiveSlides, true);
    expect(controller.isVisible("Y"), true);
    final entryDelta = controller.getSlideDelta("Y");
    expect(entryDelta, isNot(0.0),
        reason: "Y has an entry-phantom slide installed");

    // Tick mid-slide.
    await tester.pump(const Duration(milliseconds: 200));
    final yPaintedBefore = _yPaintedScrollSpace(controller, "Y");

    // SECOND move: Y → R (also expanded). Y goes visible-to-visible.
    //
    // BEFORE the fix: consume cleared _phantomClipAnchors → Y's clip
    // was lost mid-slide → portion previously occluded by P pops into
    // view.
    //
    // AFTER the fix: _phantomClipAnchors is preserved across consumes;
    // settled entries are pruned lazily, but Y's slide is still in
    // flight so its clip stays. Y's painted position is also smooth
    // (compose/install math preserves visual continuity).
    controller.moveNode(
      "Y",
      "R",
      index: 0,
      animate: true,
      slideDuration: const Duration(milliseconds: 1000),
      slideCurve: Curves.linear,
    );
    await tester.pump();

    final yPaintedAfter = _yPaintedScrollSpace(controller, "Y");
    expect(yPaintedAfter, closeTo(yPaintedBefore, 2.0),
        reason: "Y's painted position must be visually continuous "
            "across the re-move (no snap). Before: $yPaintedBefore, "
            "after: $yPaintedAfter");

    await tester.pumpAndSettle();
    expect(controller.hasActiveSlides, false);
  });

  testWidgets("ghost re-moved to ANOTHER collapsed parent keeps sliding",
      (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 1000),
      animationCurve: Curves.linear,
    );
    addTearDown(controller.dispose);

    // A (expanded) [Y, Y2]; B (collapsed) [b1]; C (collapsed) [c1].
    // Layout: A=0, Y=48, Y2=96, B=144, C=192.
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

    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    // FIRST move: Y → B (collapsed). Y becomes ghost-sliding into B's row.
    // After mutation: order [A, Y2, B, C]. Y baseline = 48; B's new
    // position = 96 (Y2 took Y's slot). Slide delta = -48.
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
        reason: "Y is now ghost (under collapsed B)");

    // Tick mid-ghost-slide.
    await tester.pump(const Duration(milliseconds: 200));
    final yGhostDelta = controller.getSlideDelta("Y");
    expect(yGhostDelta, isNot(0.0),
        reason: "Y's ghost slide is still in flight");

    // SECOND move: Y → C (also collapsed). Ghost re-moved to ANOTHER
    // hidden parent.
    //
    // BEFORE the fix: wasVisible=false (Y is ghost), so controller's
    // exit-phantom check didn't trigger. Engine's animateFromOffsets
    // saw Y in baseline but not in current → no slide installed → Y's
    // slide cleared → ghost paint pruned Y on next frame → POP.
    //
    // AFTER the fix: render-side fallback walks Y's NEW parent chain
    // (Y is now under C → C is visible-as-root) → C is the new exit
    // anchor → ghost set up dynamically → slide installs from
    // baseline (Y's ghost-painted position) toward C.
    controller.moveNode(
      "Y",
      "C",
      index: 0,
      animate: true,
      slideDuration: const Duration(milliseconds: 1000),
      slideCurve: Curves.linear,
    );
    await tester.pump();

    expect(controller.isVisible("Y"), false,
        reason: "Y is still ghost (under collapsed C now)");
    expect(controller.hasActiveSlides, true,
        reason: "Y's ghost slide must continue toward the NEW exit anchor C");
    expect(controller.getSlideDelta("Y"), isNot(0.0),
        reason: "A new slide must be installed for the re-moved ghost");

    await tester.pumpAndSettle();
    expect(controller.hasActiveSlides, false);
  });
}

/// Computes Y's currently-painted scroll-space y. For a ghost (not in
/// visibleNodes), uses the controller's parent chain to derive the
/// anchor position. For a visible row, uses structural + slide.
double _yPaintedScrollSpace(
  TreeController<String, String> controller,
  String key,
) {
  if (controller.isVisible(key)) {
    // Walk visibleNodes to compute structural y, then add slide.
    final visible = controller.visibleNodes;
    double structural = 0.0;
    for (int i = 0; i < visible.length; i++) {
      if (visible[i] == key) {
        return structural + controller.getSlideDelta(key);
      }
      structural += 48.0; // Test rows are all 48px.
    }
    return double.nan;
  }
  // Ghost: anchor.painted + ghost.slide.
  String? anchor = controller.getParent(key);
  while (anchor != null && !controller.isVisible(anchor)) {
    anchor = controller.getParent(anchor);
  }
  if (anchor == null) return double.nan;
  final anchorPainted = _yPaintedScrollSpace(controller, anchor);
  return anchorPainted + controller.getSlideDelta(key);
}
