/// Regression tests for H2: admission starves the viewport below a row
/// taller than the cache extent.
///
/// The admission accumulators are seeded at 0 at `cacheStartIndex`, the
/// row CONTAINING the window start, while the budget cap measures the
/// window itself; the part of the leading row lying ABOVE the window is
/// therefore charged against budget it never occupies. Invisible for
/// 48 px rows, a viewport-sized hole once one row approaches the cache
/// extent: rows still on screen below it are refused and paint as a
/// blank band.
///
/// Case 1 drives the non-bulk arm with a 700 px row and a scroll sweep.
/// Case 2 drives the BULK arm mid-`expandAll` with the window starting
/// inside the tall row, on rows that were never mounted by any earlier
/// frame (force-creation and retention would otherwise mask the miss),
/// pinned to the bulk arm via `debugLastLayoutUsedBulkAdmission`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "non-bulk: every row intersecting the viewport is built below a row "
    "taller than the cache extent",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      // r1 is 700 px, taller than the 250 px cache extent plus viewport
      // margin; everything else is 48 px.
      controller.setRoots([
        for (int i = 0; i < 31; i++) TreeNode(key: "r$i", data: "r$i"),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return SizedBox(
                      height: key == "r1" ? 700 : 48,
                      child: Text(key),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );

      // Static offsets: r0 [0, 48), r1 [48, 748), rk (k >= 2) at
      // 748 + 48 * (k - 2).
      double topOf(int k) {
        if (k == 0) return 0.0;
        if (k == 1) return 48.0;
        return 748.0 + 48.0 * (k - 2);
      }

      double extentOf(int k) => k == 1 ? 700.0 : 48.0;

      // Setup sanity: the pre-fix condition is reachable; at x = 995 at
      // least 9 rows past r1 intersect the viewport.
      int intersecting = 0;
      for (int k = 0; k < 31; k++) {
        if (topOf(k) < 995.0 + 600.0 && topOf(k) + extentOf(k) > 995.0) {
          intersecting++;
        }
      }
      expect(
        intersecting,
        greaterThanOrEqualTo(9),
        reason: "the sweep must cover a window with many rows at stake",
      );

      for (double x = 600.0; x <= 1000.0; x += 5.0) {
        scroll.jumpTo(x);
        await tester.pump();
        for (int k = 0; k < 31; k++) {
          if (topOf(k) < x + 600.0 && topOf(k) + extentOf(k) > x) {
            expect(
              render.getChildForNode("r$k"),
              isNotNull,
              reason: "row r$k intersects the viewport at scroll $x and "
                  "must be built; a refused row paints as a blank band",
            );
          }
        }
      }
    },
  );

  testWidgets(
    "bulk: rows below the tall row are built when the window starts "
    "inside it mid-expandAll",
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
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      // 92 roots in visible order: p0..p29 (48), mp (48, carrying ten
      // COLLAPSED children m0..m9), rTall (700), f0..f59 (48). mp is the
      // only collapsed node, so expandAll opens exactly one bulk group
      // whose members are m0..m9.
      controller.setRoots([
        for (int i = 0; i < 30; i++) TreeNode(key: "p$i", data: "p$i"),
        const TreeNode(key: "mp", data: "mp"),
        const TreeNode(key: "rTall", data: "rTall"),
        for (int i = 0; i < 60; i++) TreeNode(key: "f$i", data: "f$i"),
      ]);
      controller.setChildren("mp", [
        for (int j = 0; j < 10; j++) TreeNode(key: "m$j", data: "m$j"),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return SizedBox(
                      height: key == "rTall" ? 700 : 48,
                      child: Text(key),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );

      // Step b: scroll to 700 so rTall is measured at 700 and the layout
      // settles with it in the cache region.
      scroll.jumpTo(700.0);
      await tester.pump();

      // Step c: open the bulk group at value 0.
      controller.expandAll();
      await tester.pump();

      // Setup sanities. The last one is what this case turns on: the
      // asserted rows were never mounted by ANY earlier frame, so step d
      // measures a first mount rather than a leftover (nothing unmounts
      // during a bulk animation: stale eviction returns early while any
      // animation runs).
      expect(
        render.debugLastLayoutUsedBulkAdmission,
        isTrue,
        reason: "the frame must decide admission on the bulk arm",
      );
      expect(
        controller.isBulkMember("m0"),
        isTrue,
        reason: "expandAll must have opened a bulk group over m0..m9",
      );
      expect(
        controller.getMeasuredExtent("rTall"),
        700.0,
        reason: "rTall must have been measured before the jump",
      );
      for (int k = 4; k <= 17; k++) {
        expect(
          render.getChildForNode("f$k"),
          isNull,
          reason: "f$k must be unmounted before the jump or the case "
              "cannot distinguish a first mount from a leftover",
        );
      }

      // Step d: jump deep so the window starts inside rTall, and pump one
      // frame 150 ms in (bulk value exactly 0.5). Live offsets: rTall
      // spans [1728, 2428), f_k at 2428 + 48k; the viewport [2650, 3250)
      // is covered by f4..f17.
      scroll.jumpTo(2650.0);
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        render.debugLastLayoutUsedBulkAdmission,
        isTrue,
        reason: "the jump frame must still decide on the bulk arm",
      );
      for (int k = 4; k <= 17; k++) {
        expect(
          render.getChildForNode("f$k"),
          isNotNull,
          reason: "f$k intersects the viewport at bulk value 0.5 and must "
              "be built; the window's overhang above rTall's top must not "
              "be charged against the admission budget",
        );
      }

      await tester.pumpAndSettle();
    },
  );
}
