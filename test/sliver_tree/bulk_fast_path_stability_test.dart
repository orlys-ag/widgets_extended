/// Regression tests for M6: the bulk-only fast path must survive across
/// frames. `_admitBulkFastPath` used to write the per-row extent estimate
/// as a difference of two cumulative offsets, which is only algebraically
/// (not bitwise) equal to the `fullExtent * value` product Pass 2
/// measures, so the exact `!=` compare at the measurement site fired on
/// the last bit of that difference, ran `_materializeBulkStaleExtents`
/// plus `_recomputeOffsetsFrom`, and the next frame rebuilt the
/// cumulatives again: the documented O(1) steady-state bulk frame never
/// held for more than one frame.
///
/// Oracle: `debugBulkCumulativeRebuildCount`, the lifetime count of
/// `_rebuildBulkCumulatives` calls. A bulk animation whose rows do not
/// change height must build the cumulatives ONCE, and a genuine
/// mid-animation height change must still rebuild them (the fix must not
/// simply disable the extent-changed signal).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "bulk-only fast path holds across frames when no row height changes",
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

      // r stays COLLAPSED at first layout, so expandAll harvests
      // c0..c999 as bulk members; r itself is the lone non-member.
      controller.setRoots([const TreeNode(key: "r", data: "r")]);
      controller.setChildren("r", [
        for (int i = 0; i < 1000; i++) TreeNode(key: "c$i", data: "c$i"),
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
      expect(
        render.debugBulkCumulativeRebuildCount,
        0,
        reason: "no bulk animation has run yet",
      );

      controller.expandAll();
      await tester.pump();

      // Setup sanity: the first bulk frame built the cumulatives exactly
      // once, so the fast path really was entered.
      expect(
        render.debugBulkCumulativeRebuildCount,
        1,
        reason: "the first bulk frame must build the cumulatives once",
      );

      // 10 more animation frames, all inside the 300 ms window. No row
      // height changes, so the cumulatives must never be rebuilt.
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        render.debugBulkCumulativeRebuildCount,
        1,
        reason: "a bulk animation whose rows do not change height must "
            "build the cumulatives once, not once per frame",
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "a genuine mid-animation height change still rebuilds the cumulatives",
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

      final c4Height = ValueNotifier<double>(48.0);
      addTearDown(c4Height.dispose);

      controller.setRoots([const TreeNode(key: "r", data: "r")]);
      controller.setChildren("r", [
        for (int i = 0; i < 1000; i++) TreeNode(key: "c$i", data: "c$i"),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    if (key == "c4") {
                      return ValueListenableBuilder<double>(
                        valueListenable: c4Height,
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

      controller.expandAll();
      await tester.pump();
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Setup sanity 1: the fast path has held so far (fails on unfixed
      // code, where the counter climbs one per frame).
      expect(
        render.debugBulkCumulativeRebuildCount,
        1,
        reason: "the fast path must have held before the height change",
      );
      // Setup sanity 2: c4 is mounted, i.e. inside the admitted band; a
      // never-built row could not remeasure and the case would test
      // nothing.
      expect(
        find.text("c4"),
        findsOneWidget,
        reason: "c4 must be admitted for its remeasure to fire the signal",
      );

      // Flip c4 from 48 to 96 mid-animation. Frame A rebuilds the row,
      // remeasures it, and the extent-changed signal drops the fast path;
      // frame B rebuilds the cumulatives exactly once.
      c4Height.value = 96.0;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        render.debugBulkCumulativeRebuildCount,
        2,
        reason: "a genuine height change must rebuild the cumulatives; "
            "the fix must not disable the extent-changed signal",
      );

      await tester.pumpAndSettle();
    },
  );
}
