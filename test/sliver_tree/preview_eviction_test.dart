/// Regression test for issue 8 of the 2026-08-21 review: a held make-room
/// preview disabled stale-node eviction for the whole drag.
///
/// Both eviction gates in [SliverTreeElement] read the COMPOSED
/// `hasActiveSlides`, which a preview keeps true from the first resolve to
/// the release, because a preview offset is HELD rather than decaying.
/// `isNodeRetained` likewise retained any row with a non-zero composed
/// delta. So every row scrolled past during an autoscroll drag stayed
/// mounted until the drop: 2000 rows and 200 autoscroll frames took the
/// mounted set from 18 to 143.
///
/// Both reads move to the FLIP-only variants. That is sound only because
/// issue 6's fix admits preview-shifted rows at layout time: a row whose
/// painted position can reach the cache region is built and in-cache, so
/// it is retained by the cache-region check rather than by the delta
/// clause. FLIP slides keep the composed-free treatment they had, because
/// a FLIP tick is paint-only and a row can transit the viewport between
/// two layouts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("a held preview does not pin every row scrolled past", (
    tester,
  ) async {
    final controller = TreeController<String, String>(vsync: tester);
    addTearDown(controller.dispose);
    controller.setRoots([
      for (int i = 0; i < 2000; i++) TreeNode(key: "r$i", data: "R$i"),
    ]);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverTree<String, String>(
                controller: controller,
                nodeBuilder: (context, key, depth) {
                  return SizedBox(height: 48, child: Text(key));
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
    final steadyState = render.debugChildCount;

    // Hold a preview, as a drag does between resolve and release.
    controller.setReorderPreviewAtIndex(
      draggedKey: "r0",
      gapVisibleIndex: 4,
    );
    await tester.pumpAndSettle();
    expect(
      controller.hasActiveSlides,
      isTrue,
      reason: "setup: the preview is held, which is what used to pin the "
          "eviction gates",
    );

    // Autoscroll past a few hundred rows.
    for (int i = 0; i < 200; i++) {
      scrollController.jumpTo(scrollController.offset + 30);
      await tester.pump();
    }

    expect(
      render.debugChildCount,
      lessThan(steadyState + 12),
      reason: "mounted rows must not accumulate for the length of a drag "
          "(this read 143 against a steady state of 18)",
    );

    // The rows the preview actually shifted must still be built while
    // their painted band is inside the viewport.
    for (final key in ["r1", "r2", "r3"]) {
      final index = controller.getVisibleIndex(key);
      if (index < 0) continue;
      final painted =
          index * 48.0 +
          controller.getSlideDeltaNid(controller.nidOf(key)) -
          scrollController.offset;
      if (painted > -48 && painted < 600) {
        expect(
          render.getChildForNode(key),
          isNotNull,
          reason: "$key paints at $painted and must stay built",
        );
      }
    }

    controller.clearReorderPreview(animate: false);
    await tester.pumpAndSettle();
  });

  testWidgets("a preview installed while a FLIP settles keeps every "
      "viewport row built", (tester) async {
    // The interaction the plan left open: the FLIP gate pauses eviction
    // until the slide settles, then eviction resumes under the held
    // preview. Nothing may drop out of the viewport across that
    // transition.
    final controller = TreeController<String, String>(vsync: tester);
    addTearDown(controller.dispose);
    controller.setRoots([
      for (int i = 0; i < 60; i++) TreeNode(key: "r$i", data: "R$i"),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return SizedBox(height: 48, child: Text(key));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final render = tester.renderObject<RenderSliverTree<String, String>>(
      find.byType(SliverTree<String, String>),
    );

    // Start a FLIP that is still in flight when the preview arrives.
    final order = controller.liveRootKeys;
    final moved = order.removeAt(0);
    order.insert(20, moved);
    controller.reorderRoots(order, animate: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.hasActiveFlipSlides, isTrue, reason: "setup");

    controller.setReorderPreviewAtIndex(
      draggedKey: "r5",
      gapVisibleIndex: 30,
    );

    for (int frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (int i = 0; i < controller.visibleNodeCount; i++) {
        final nid = controller.visibleNidAt(i);
        final painted = i * 48.0 + controller.getSlideDeltaNid(nid);
        if (painted > -48 && painted < 600) {
          final key = controller.keyOfNid(nid) as String;
          expect(
            render.getChildForNode(key),
            isNotNull,
            reason: "frame $frame: $key paints at $painted with no child",
          );
        }
      }
    }
    expect(
      controller.hasActiveFlipSlides,
      isFalse,
      reason: "the FLIP settled during the loop, so the transition from "
          "FLIP-gated to preview-only eviction was exercised",
    );

    controller.clearReorderPreview(animate: false);
    await tester.pumpAndSettle();
  });
}
