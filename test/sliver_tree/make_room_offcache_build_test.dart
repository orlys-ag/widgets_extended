/// Regression test for issue 6 of the 2026-08-21 review: the make-room
/// preview shifted rows into the viewport that had never been built.
///
/// A preview is paint-only, so its ticks route to `markNeedsPaint`. The
/// overreach that admits rows whose PAINTED position lands in the cache
/// region while their structural position does not is computed inside
/// `performLayout`, against the bound at that moment, and nothing on the
/// pointer-move path triggers a layout. So when the dragged subtree's
/// lift exceeds the cache extent (250px by default, six 48px rows), the
/// rows the preview pulled up into the viewport had no element: the user
/// saw blank space until autoscroll or the drop forced a layout.
///
/// The fix makes the preview's contribution to
/// `composedSlideAbsDeltaBound` its TERMINAL magnitude, records the bound
/// each layout admitted against, and lets the element mark layout on a
/// tick whose bound exceeds it. Terminal-ness is what keeps that to ONE
/// layout per retarget instead of one per tick.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("rows the preview lifts into the viewport are built, in one "
      "layout", (tester) async {
    final controller = TreeController<String, String>(vsync: tester);
    addTearDown(controller.dispose);
    // 40 roots at 48px in a 600px viewport, with a 13-row dragged
    // subtree: the 624px lift is well past the 250px default cache
    // extent, so the rows it pulls up start outside any built range.
    controller.setRoots([
      for (int i = 0; i < 40; i++) TreeNode(key: "r$i", data: "R$i"),
    ]);
    controller.setChildren("r0", [
      for (int i = 0; i < 12; i++) TreeNode(key: "c$i", data: "C$i"),
    ]);
    controller.expand(key: "r0", animate: false);

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
    expect(
      controller.visibleNodeCount,
      52,
      reason: "setup: r0 + 12 children + r1..r39",
    );
    expect(
      render.getChildForNode("r13"),
      isNull,
      reason: "setup: r13 sits at 1200px, far outside the cache region",
    );

    final layoutsBefore = render.debugPerformLayoutCount;

    // Open the gap after every visible row: the whole dragged subtree
    // vacates its slot, so r1..r39 shift UP by 624px.
    controller.setReorderPreviewAtIndex(
      draggedKey: "r0",
      gapVisibleIndex: controller.visibleNodeCount,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // r1..r13 are structurally at 624..1200 and painted at 0..576, so
    // every one of them is inside the viewport and must have a child.
    for (int i = 1; i <= 13; i++) {
      final key = "r$i";
      final nid = controller.nidOf(key);
      final painted =
          controller.getVisibleIndex(key) * 48.0 +
          controller.getSlideDeltaNid(nid);
      expect(
        painted,
        lessThan(600.0),
        reason: "setup: $key is painted inside the viewport",
      );
      expect(
        render.getChildForNode(key),
        isNotNull,
        reason: "$key paints at $painted but was never built",
      );
    }

    expect(
      render.debugPerformLayoutCount - layoutsBefore,
      1,
      reason: "the preview's bound is terminal, so one retarget costs one "
          "layout, not one per tick",
    );

    controller.clearReorderPreview(animate: false);
    await tester.pumpAndSettle();
  });

  testWidgets("a preview costs one layout when the window widens and none "
      "when it does not", (tester) async {
    // Control for the routing rule: the element lays out when the
    // composed bound EXCEEDS what the last layout admitted against, not
    // on every preview tick and not on every retarget. Installing a
    // preview widens the window once; re-targeting it to another slot
    // with the same dragged extent moves rows inside the window that is
    // already admitted, so it stays paint-only.
    final controller = TreeController<String, String>(vsync: tester);
    addTearDown(controller.dispose);
    controller.setRoots([
      for (int i = 0; i < 40; i++) TreeNode(key: "r$i", data: "R$i"),
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

    final layoutsBefore = render.debugPerformLayoutCount;
    controller.setReorderPreviewAtIndex(draggedKey: "r0", gapVisibleIndex: 4);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      render.debugPerformLayoutCount - layoutsBefore,
      1,
      reason: "one layout for the install, not one per tick",
    );

    final layoutsAfterInstall = render.debugPerformLayoutCount;
    controller.setReorderPreviewAtIndex(draggedKey: "r0", gapVisibleIndex: 9);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      render.debugPerformLayoutCount - layoutsAfterInstall,
      0,
      reason: "the dragged extent is unchanged, so the admitted window "
          "already contains every painted position",
    );

    controller.clearReorderPreview(animate: false);
    await tester.pumpAndSettle();
  });
}
