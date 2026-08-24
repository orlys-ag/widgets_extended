/// Regression tests for M7: on bulk frames, `performLayout` must not read
/// per-nid offset/extent slots for nids the frame never wrote.
///
/// Case 1: the paint-extent loop read raw slots for every visible index;
/// under the bulk-only fast path those are fresh only for cache-region
/// nids, so off-cache rows read 0.0/0.0, the break never fired, and
/// `paintExtent` under-reported: a following sliver painted inside the
/// tree.
///
/// Case 2: the sticky force-create compare read `_nodeExtentsByNid[nid]`
/// as the prior extent. For a force-created sticky ancestor that is a
/// bulk MEMBER, the slot holds a previous frame's product (or a
/// never-written 0.0) while the measurement moves every frame, so the
/// exact `!=` fired on nothing and dragged in a full materialize plus
/// offset recompute per frame. Oracle: `debugBulkCumulativeRebuildCount`.
///
/// Case 3: the force-created rows' `parentData.layoutOffset` write read
/// the raw offset slot, stale for off-cache nids on bulk frames. Oracle:
/// `debugStickyOffsetAuthorityMismatchCount`, which counts writes that
/// disagree with the frame's structural authority.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "paintExtent covers the viewport on bulk frames with off-cache slots "
    "unwritten",
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

      // r stays COLLAPSED at first layout, so expandAll makes c0..c1999
      // bulk members whose slots are written only for the admitted band.
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
                const SliverToBoxAdapter(
                  child: SizedBox(height: 100, child: Text("footer")),
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
      await tester.pump(const Duration(milliseconds: 150));

      // Setup sanity: the frame really is on the fast path with most
      // slots unwritten; only the admitted band plus margin is mounted.
      expect(
        render.debugChildCount,
        lessThan(100),
        reason: "most of the 2001 rows must be unmounted with their "
            "per-nid slots unwritten, or the case tests nothing",
      );

      // At v = 0.5 the tree's scroll extent is 48 + 2000 * 24 = 48048,
      // far beyond the 600 px viewport, so the sliver must claim the
      // whole remaining paint extent.
      expect(
        render.geometry!.paintExtent,
        600.0,
        reason: "paintExtent must cover the viewport; stale 0.0 slots "
            "must not starve the paint-extent computation",
      );

      // The footer must not intrude into the tree's viewport. When the
      // under-reported paintExtent pulled it up, it painted inside the
      // tree.
      final footerFinder = find.text("footer");
      if (tester.any(footerFinder)) {
        expect(
          tester.getTopLeft(footerFinder).dy,
          greaterThanOrEqualTo(600.0),
          reason: "the footer must sit at or below the viewport bottom",
        );
      }

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "force-created sticky bulk member does not knock the frame off the "
    "fast path",
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

      // R COLLAPSED at first layout: expandAll harvests C0..C39 AND all
      // 4000 grandchildren as bulk members; R is the lone non-member.
      // Every row is exactly the 48 px default extent, which matters
      // because `getCurrentExtentNid` falls back to `defaultExtent` for
      // an unmeasured nid.
      controller.setRoots([const TreeNode(key: "R", data: "R")]);
      controller.setChildren("R", [
        for (int i = 0; i < 40; i++) TreeNode(key: "C$i", data: "C$i"),
      ]);
      for (int i = 0; i < 40; i++) {
        controller.setChildren("C$i", [
          for (int j = 0; j < 100; j++)
            TreeNode(key: "g${i}_$j", data: "g${i}_$j"),
        ]);
      }

      final builtKeys = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  maxStickyDepth: 2,
                  nodeBuilder: (context, key, depth) {
                    builtKeys.add(key);
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

      // Setup sanity: every pre-expand layout saw a one-row visible
      // order, so no Ci slot was ever written by the full walk; the Ci
      // slots are still the zero-initialised 0.0.
      expect(
        controller.visibleNodeCount,
        1,
        reason: "R must be the only visible row before expandAll",
      );

      controller.expandAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Setup sanity: the fast path was entered once and has held.
      expect(
        render.debugBulkCumulativeRebuildCount,
        1,
        reason: "the fast path must be established before the jump",
      );

      final preJumpBuilt = Set<String>.of(builtKeys);

      // Jump deep into the tree. At v = 0.5 the offset of Ci is
      // 48 + 2424 * i, so 74000 lands inside C30's subtree; the pinned
      // depth-1 header is a bulk MEMBER far outside the cache region and
      // is force-created.
      scroll.jumpTo(74000.0);
      await tester.pump(const Duration(milliseconds: 16));

      final headers = render.debugStickyHeaders;
      expect(
        headers.length,
        greaterThanOrEqualTo(2),
        reason: "a depth-1 header must be pinned after the jump",
      );
      // Setup sanity: the pinned depth-1 header was never built, so it
      // was never measured: its extent slot is the zero-initialised 0.0
      // and its full extent is the unmeasured sentinel.
      final pinnedKey = headers[1].nodeId;
      expect(
        preJumpBuilt.contains(pinnedKey),
        isFalse,
        reason: "the pinned header must be a never-built row for its "
            "stale slot to be the thing under test",
      );

      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        render.debugBulkCumulativeRebuildCount,
        1,
        reason: "a force-created sticky bulk member whose height never "
            "changed must not fire the extent-changed signal",
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "force-created sticky row's layoutOffset is written from the "
    "structural authority",
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

      // R EXPANDED at first layout: C0..C39 are visible pre-expand, so
      // the full walk measures the admitted ones (C0..C16). expandAll
      // then makes only the 4000 grandchildren bulk members; R and every
      // Ci stay non-members, so the extent compare stays quiet and the
      // stale OFFSET write is the only thing under test.
      controller.setRoots([const TreeNode(key: "R", data: "R")]);
      controller.setChildren("R", [
        for (int i = 0; i < 40; i++) TreeNode(key: "C$i", data: "C$i"),
      ]);
      for (int i = 0; i < 40; i++) {
        controller.setChildren("C$i", [
          for (int j = 0; j < 100; j++)
            TreeNode(key: "g${i}_$j", data: "g${i}_$j"),
        ]);
      }
      controller.expand(key: "R", animate: false);

      final buildCounts = <String, int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  maxStickyDepth: 2,
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

      controller.expandAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final preJumpBuilt = Set<String>.of(buildCounts.keys);

      // Jump deep into an early Ci's subtree. Which Ci owns 25600
      // depends on the jump frame's bulk value (the pump advances it
      // past 0.5), so the assertions below read the actually-pinned
      // header instead of naming an index. Every candidate is one of
      // C0..C16, which the pre-expand layout admitted and measured, so
      // the extent compare stays quiet and only the OFFSET slot is
      // stale.
      scroll.jumpTo(25600.0);
      await tester.pump(const Duration(milliseconds: 16));

      final headers = render.debugStickyHeaders;
      expect(
        headers.length,
        greaterThanOrEqualTo(2),
        reason: "a depth-1 header must be pinned after the jump",
      );
      final pinnedKey = headers[1].nodeId;
      // Setup sanity: the pinned header really was measured BEFORE
      // the jump (force-creation itself builds the row, so a plain
      // buildCounts lookup after the jump could never fail; the
      // pre-jump snapshot can). A pre-measured header's extent slot
      // agrees with its measurement, so the extent compare stays
      // quiet and the stale OFFSET write is the only thing under
      // test.
      expect(
        preJumpBuilt.contains(pinnedKey),
        isTrue,
        reason: "the pinned header must have been built and measured "
            "before the jump",
      );
      // Setup sanity: the fast path held on every frame up to the
      // jump. An earlier fall-off would have materialized and
      // recomputed every slot wholesale, hiding the stale-offset
      // subject. (A jump-frame fall-off would not show here; its
      // rebuild lands on the next frame. That state is excluded by
      // the pre-fix red instead: the mismatch counter read 1, which
      // it could not have if a same-frame recompute had refreshed
      // the slot before the write.)
      expect(
        render.debugBulkCumulativeRebuildCount,
        1,
        reason: "the fast path must have held on every frame before "
            "the jump",
      );

      expect(
        render.debugStickyOffsetAuthorityMismatchCount,
        0,
        reason: "the layoutOffset write must agree with the frame's "
            "structural authority at the moment of the write",
      );

      await tester.pumpAndSettle();
    },
  );
}
