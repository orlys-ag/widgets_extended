/// Regression test for R124: `debugLastParentDataRefreshIterationCount`
/// is a diagnostic counter set inside the post-sticky parentData refresh
/// loop in `performLayout`. The loop iterates `_children.keys` exactly
/// once per layout, so the counter is bounded by `_children.length`.
///
/// The field's docstring previously promised "Phase 4's regression test"
/// to verify this bound, but that test was never written. This file
/// fills the gap.
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
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (_, key, depth) => SizedBox(
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
  testWidgets(
    "debugLastParentDataRefreshIterationCount is bounded by _children.length",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);

      // Small tree first; should exercise the loop with a handful of
      // mounted rows.
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      controller.setChildren("a", [
        const TreeNode(key: "a1", data: "A1"),
        const TreeNode(key: "a2", data: "A2"),
      ]);
      controller.expand(key: "a", animate: false);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      final sliver = tester.renderObject<RenderSliverTree<String, String>>(
          find.byType(SliverTree<String, String>));

      expect(
        sliver.debugLastParentDataRefreshIterationCount,
        lessThanOrEqualTo(sliver.debugChildCount),
        reason: "parentData refresh loop must iterate at most "
            "_children.length times per layout",
      );
    },
  );

  testWidgets(
    "pure-scroll frame with all mounted children in-cache builds NO "
    "structural cumulative (audit 5.1)",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      // Large flat tree so a scroll frame has plenty of below-viewport
      // rows: the refresh loop must not pay an O(N_visible) cumulative
      // build (with allocation) to service zero off-cache children.
      controller.setRoots([
        for (int i = 0; i < 500; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverTree<String, String>(
                    controller: controller,
                    nodeBuilder: (_, key, depth) =>
                        SizedBox(height: 48, child: Text(key)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sliver = tester.renderObject<RenderSliverTree<String, String>>(
          find.byType(SliverTree<String, String>));

      // Jump deep, then give the post-frame eviction sweep a frame to
      // release the rows mounted at the old position (they are
      // legitimately off-cache during the jump frame itself).
      scrollController.jumpTo(2000.0);
      await tester.pump();
      await tester.pump();

      // Pure scroll, small step (no row crosses out of the cache
      // region): every mounted child is still in-cache, so the refresh
      // loop must not build the O(N_visible) structural cumulative.
      scrollController.jumpTo(2010.0);
      await tester.pump();

      expect(
        sliver.debugLastParentDataCumulativeBuilds,
        0,
        reason: "a pure-scroll frame with every mounted child in-cache "
            "must not rebuild the O(N_visible) structural cumulative — "
            "the dominant steady-state cost for large trees",
      );
      expect(controller.hasActiveAnimations, isFalse,
          reason: "sanity: this is a pure-scroll frame");
    },
  );

  testWidgets(
    "bound holds under structural churn (insert + collapse + expand)",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "root", data: "root")]);
      // Build a wider tree to exercise more mounted children.
      controller.setChildren("root", [
        for (int i = 0; i < 20; i++)
          TreeNode(key: "n$i", data: "N$i"),
      ]);
      controller.expand(key: "root", animate: false);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      final sliver = tester.renderObject<RenderSliverTree<String, String>>(
          find.byType(SliverTree<String, String>));

      // Churn: collapse, re-expand, insert, remove. Re-layout each time
      // and verify the bound holds.
      controller.collapse(key: "root", animate: false);
      await tester.pumpAndSettle();
      expect(
        sliver.debugLastParentDataRefreshIterationCount,
        lessThanOrEqualTo(sliver.debugChildCount),
      );

      controller.expand(key: "root", animate: false);
      await tester.pumpAndSettle();
      expect(
        sliver.debugLastParentDataRefreshIterationCount,
        lessThanOrEqualTo(sliver.debugChildCount),
      );

      controller.insert(
        parentKey: "root",
        node: const TreeNode(key: "n_new", data: "N_NEW"),
      );
      await tester.pumpAndSettle();
      expect(
        sliver.debugLastParentDataRefreshIterationCount,
        lessThanOrEqualTo(sliver.debugChildCount),
      );

      controller.remove(key: "n0");
      await tester.pumpAndSettle();
      expect(
        sliver.debugLastParentDataRefreshIterationCount,
        lessThanOrEqualTo(sliver.debugChildCount),
      );
    },
  );

  testWidgets(
    "counter resets at the top of each layout (never accumulates)",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      final sliver = tester.renderObject<RenderSliverTree<String, String>>(
          find.byType(SliverTree<String, String>));

      final firstCount = sliver.debugLastParentDataRefreshIterationCount;

      // Force several additional layouts via structural churn.
      for (int i = 0; i < 5; i++) {
        controller.insertRoot(TreeNode(key: "r$i", data: "R$i"));
        await tester.pumpAndSettle();
        // Counter must reflect ONE layout's iteration, not cumulative
        // across layouts.
        expect(
          sliver.debugLastParentDataRefreshIterationCount,
          lessThanOrEqualTo(sliver.debugChildCount),
          reason: "Counter must reset at the top of each layout. "
              "Original count: $firstCount, iteration $i",
        );
      }
    },
  );
}
