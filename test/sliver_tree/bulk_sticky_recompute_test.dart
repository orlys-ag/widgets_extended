/// Regression test for audit item 4.1: under the bulk-only fast path the
/// per-nid extent slots are fresh ONLY for cache-region nids. The sticky
/// force-create path used to call the full `_recomputeOffsets()` when a
/// force-created sticky ancestor's measured extent differed from its
/// (stale) slot — walking ALL visible nids over stale extents and
/// overwriting correct offsets and the frame's `geometry.scrollExtent`
/// with garbage while `_bulkCumulativesValid` stayed true.
///
/// Trigger: expandAll (bulk) + maxStickyDepth > 0 + a sticky ancestor
/// outside the cache region whose height changed while off-cache, on a
/// non-throttled sticky frame.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "sticky force-create extent change mid-bulk keeps geometry.scrollExtent "
    "consistent with controller extents",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      // p: sticky ancestor with many children (so it pins while scrolled
      // deep); q: a collapsed parent for expandAll to animate.
      controller.setRoots([
        const TreeNode(key: "p", data: "100"),
        const TreeNode(key: "q", data: "50"),
      ]);
      controller.setChildren("p", [
        for (int i = 0; i < 200; i++) TreeNode(key: "c$i", data: "50"),
      ]);
      controller.setChildren("q", [
        for (int i = 0; i < 5; i++) TreeNode(key: "q$i", data: "50"),
      ]);
      controller.expand(key: "p", animate: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  maxStickyDepth: 1,
                  nodeBuilder: (context, key, depth) {
                    final height = double.parse(
                      controller.getNodeData(key)?.data ?? "50",
                    );
                    return SizedBox(height: height, child: Text(key));
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll deep into p's children: p is far outside the cache region
      // and sticky-pinned.
      scrollController.jumpTo(5000.0);
      await tester.pumpAndSettle();

      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );

      // Start the bulk expand and let the bulk-only fast path establish
      // itself (first frame after a structure change runs the full walk;
      // subsequent frames use the cumulative fast path where only
      // cache-region extent slots stay fresh).
      controller.expandAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      // NOW change p's height while it is off-cache (pure data update:
      // same key, same position — no structure change, so the fast path
      // stays engaged). p's stale per-nid extent slot keeps 100 until the
      // sticky force-create measures the rebuilt 140px row mid-bulk.
      controller.insertRoot(
        const TreeNode(key: "p", data: "140"),
        index: 0,
        animate: false,
      );

      double expectedScrollExtent() {
        double sum = 0.0;
        for (final key in controller.visibleNodes) {
          sum += controller.getCurrentExtent(key);
        }
        return sum;
      }

      // Pump through the bulk animation. Sticky recompute is throttled to
      // every 3rd frame during animation, so several frames guarantee at
      // least one non-throttled sticky frame mid-bulk. On every frame the
      // laid-out scrollExtent must match the controller-side sum of
      // current extents.
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final expected = expectedScrollExtent();
        expect(
          render.geometry!.scrollExtent,
          moreOrLessEquals(expected, epsilon: 0.5),
          reason: "frame $i: geometry.scrollExtent must track the "
              "controller's current extents — a full-order offset "
              "recompute over stale per-nid extents corrupts it while "
              "the bulk fast path is active",
        );
      }

      await tester.pumpAndSettle();
      expect(
        render.geometry!.scrollExtent,
        moreOrLessEquals(expectedScrollExtent(), epsilon: 0.5),
      );
    },
  );
}
