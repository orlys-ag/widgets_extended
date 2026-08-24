/// Regression tests for M8: bulk `collapseAll` admission.
///
/// Case 1: the bulk fast path's admission break was a full-space position
/// test whose operands do not depend on the animation value, so the break
/// index was constant for the whole collapse and rows AFTER the
/// collapsing subtree never entered the cache region: they mass-mounted
/// in one shot at dismiss (the non-bulk path pre-mounts them via its
/// post-animation view; the bulk path had no post view at all).
///
/// Case 2: the guard. Frame 1 of a bulk `expandAll` must NOT mass-mount
/// the entering subtree: both admission views charge full extents, so
/// admission stays near the pre-animation row count.
///
/// Case 3: the freshness teeth. When an ADMITTED row's height changes
/// mid-collapse, the recompute must materialize every stale slot,
/// including bulk members inside the iteration bound that admission never
/// visited. A range-keyed freshness test believes those rows' stale
/// slots and overstates `geometry.scrollExtent`. Passes before M8 (the
/// old loop wrote every iterated slot) and after it (the skip is
/// per-nid); it exists to reject the intermediate where the admission
/// prefix hop lands while the materialize skip is still range-keyed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "bulk collapseAll pre-mounts rows following the collapsing subtree",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
        const TreeNode(key: "C", data: "C"),
      ]);
      controller.setChildren("A", [
        for (int i = 0; i < 50; i++) TreeNode(key: "a$i", data: "a$i"),
      ]);
      controller.expand(key: "A", animate: false);

      final buildCounts = <String, int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    buildCounts[key] = (buildCounts[key] ?? 0) + 1;
                    return SizedBox(height: 48, child: Text(key));
                  },
                ),
              ],
            ),
          ),
        ),
      );

      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );

      // Setup sanity: B sits past the cache region (A's expanded subtree
      // is 2448 px against an 850 px cache band), so it was never built.
      expect(
        buildCounts["B"],
        isNull,
        reason: "B must start outside the cache region or the case "
            "tests nothing",
      );

      controller.collapseAll();
      await tester.pump();
      // Setup sanity: the render object is on the bulk fast path.
      expect(
        render.debugBulkCumulativeRebuildCount,
        1,
        reason: "the collapse must run on the bulk fast path",
      );

      // 250 ms in (value about 0.17) B's animated offset is about 448,
      // inside the viewport. It must already be mounted, BEFORE the
      // settle layout.
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        buildCounts["B"],
        isNotNull,
        reason: "rows following the collapsing subtree must be "
            "pre-mounted during the collapse, not popped in at dismiss",
      );
      expect(
        buildCounts["C"],
        isNotNull,
        reason: "every follower inside the post-animation cache band "
            "must be pre-mounted",
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "frame 1 of bulk expandAll does not mass-mount the entering subtree",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "r", data: "r")]);
      controller.setChildren("r", [
        for (int i = 0; i < 2000; i++) TreeNode(key: "c$i", data: "c$i"),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
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

      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );

      controller.expandAll();
      await tester.pump();
      // Setup sanity: the frame ran the bulk fast path.
      expect(
        render.debugBulkCumulativeRebuildCount,
        1,
        reason: "frame 1 of expandAll must be a bulk frame",
      );
      expect(
        render.debugChildCount,
        lessThan(50),
        reason: "the admission cap must hold frame 1 near the "
            "pre-animation row count, not mass-mount 2000 rows",
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "mid-collapse height change of an admitted row keeps scrollExtent "
    "consistent with controller extents",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);

      final a0Height = ValueNotifier<double>(48.0);
      addTearDown(a0Height.dispose);

      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
        const TreeNode(key: "C", data: "C"),
      ]);
      controller.setChildren("A", [
        for (int i = 0; i < 50; i++) TreeNode(key: "a$i", data: "a$i"),
      ]);
      controller.expand(key: "A", animate: false);

      final buildCounts = <String, int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    buildCounts[key] = (buildCounts[key] ?? 0) + 1;
                    if (key == "a0") {
                      return ValueListenableBuilder<double>(
                        valueListenable: a0Height,
                        builder: (context, height, child) {
                          return SizedBox(height: height, child: Text(key));
                        },
                      );
                    }
                    return SizedBox(height: 48, child: Text(key));
                  },
                ),
              ],
            ),
          ),
        ),
      );

      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );

      controller.collapseAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      // Setup sanity: the damage must be CAUSED by an admitted row and
      // LAND in the span admission never visits. a0 (visible index 1) is
      // admitted at every value; a30 (visible index 31) is inside the
      // span past the live cut and is never created.
      expect(
        buildCounts["a0"],
        isNotNull,
        reason: "a0 must be admitted for its remeasure to fire the "
            "extent-changed signal",
      );
      expect(
        buildCounts["a30"],
        isNull,
        reason: "a30 must sit in the never-admitted span or the case "
            "tests nothing",
      );

      // Flip a0 from 48 to 96 mid-collapse and let the frame remeasure,
      // materialize and recompute.
      a0Height.value = 96.0;
      await tester.pump(const Duration(milliseconds: 16));

      double truth = 0.0;
      for (final key in controller.visibleNodes) {
        truth += controller.getCurrentExtent(key);
      }
      expect(
        (render.geometry!.scrollExtent - truth).abs(),
        lessThan(1e-6),
        reason: "the recompute must materialize every stale slot, "
            "including bulk members the admission walk never visited",
      );

      await tester.pumpAndSettle();
    },
  );
}
