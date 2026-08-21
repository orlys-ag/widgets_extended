/// Regression test: the sticky candidate probe must read FRESH offsets
/// under the bulk-only fast path.
///
/// Under `expandAll` / `collapseAll` the render layer's bulk-only fast path
/// keeps `_nodeOffsetsByNid` / `_nodeExtentsByNid` fresh ONLY for
/// cache-region nids; a pinned section's header row sits far ABOVE the
/// viewport, outside the cache region, so its slots hold pre-bulk values.
/// Candidate SELECTION is bulk-aware (`findFirstVisibleIndex` derives from
/// the bulk cumulatives), but the probe's geometry (`naturalY`, the
/// fallback subtree bottom feeding `pushUpY`) read the raw arrays.
///
/// When content BEFORE the pinned section grows during `expandAll`, the
/// section's true offsets move down while its stale slots stay put, so the
/// probe computes the subtree bottom too high and the retirement gate
/// (`pinnedY + extent <= stackTop`) kills the header: the band goes
/// completely blank for the whole bulk animation and pops back at settle.
/// Frame log on unfixed code: painted=[] and computed=[] for every mid-bulk
/// frame while the ground-truth band owner (from the controller's bulk-aware
/// extents) is the pinned section.
///
/// The fix threads the render layer's bulk-aware structural-offset accessor
/// (`_offsetAtVisibleIndex`, the same source `_structuralOffsetAt` gives
/// paint and hit-test) into the sticky probe, which uses it for the
/// candidate's natural offset and the fallback subtree-bottom walk whenever
/// the bulk cumulatives are the live authority.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

const Duration kAnim = Duration(milliseconds: 300);

void main() {
  testWidgets(
    "the pinned band survives expandAll when preceding content grows: it "
    "always shows the root whose subtree covers it",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: kAnim,
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      // a: collapsed root whose expansion grows content ABOVE p.
      // p: long expanded section; its header is far outside the cache
      //    region while the viewport sits near the section's end.
      // z: expanded tail so the deep scroll offset is reachable.
      controller.setRoots(const [
        TreeNode(key: "a", data: "a"),
        TreeNode(key: "p", data: "p"),
        TreeNode(key: "z", data: "z"),
      ]);
      controller.setChildren("a", [
        for (int i = 0; i < 5; i++) TreeNode(key: "a$i", data: "a$i"),
      ]);
      controller.setChildren("p", [
        for (int i = 0; i < 200; i++) TreeNode(key: "c$i", data: "c$i"),
      ]);
      controller.setChildren("z", [
        for (int i = 0; i < 100; i++) TreeNode(key: "z$i", data: "z$i"),
      ]);
      controller.expand(key: "p", animate: false);
      controller.expand(key: "z", animate: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: CustomScrollView(
                controller: scroll,
                slivers: [
                  SliverTree<String, String>(
                    controller: controller,
                    maxStickyDepth: 1,
                    nodeBuilder: (context, key, depth) {
                      final bool isRoot = key.length == 1;
                      return SizedBox(
                        height: isRoot ? 40.0 : 50.0,
                        child: Text(key),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Park the viewport 20px past p's subtree bottom, computed from the
      // controller's own extents (unmeasured off-cache rows sit at the
      // default estimate, so a fixed number would miss). z owns the band.
      double pBottom = 0.0;
      for (final key in controller.visibleNodes) {
        pBottom += controller.getCurrentExtent(key);
        if (key == "c199") {
          break;
        }
      }
      scroll.jumpTo(pBottom + 20);
      await tester.pumpAndSettle();

      final render =
          tester.renderObject(find.byType(SliverTree<String, String>))
              as RenderSliverTree<String, String>;
      expect(
        render.debugLastPaintedStickyKeys,
        <String>{"z"},
        reason: "setup sanity: z owns the band before the bulk starts",
      );

      // Ground truth from the controller's bulk-aware extents: the depth-0
      // root whose subtree covers the band top, plus how many pixels of
      // that subtree extend past it.
      (String, double) bandTruth() {
        double cum = 0.0;
        for (final key in controller.visibleNodes) {
          cum += controller.getCurrentExtent(key);
          if (cum > scroll.offset) {
            var owner = key;
            for (var par = controller.getParent(owner); par != null;) {
              owner = par;
              par = controller.getParent(owner);
            }
            // Owner subtree bottom: the covering row's bottom plus every
            // following row down to the next depth-0 root. This holds
            // whether the covering row is the owner itself (the following
            // deeper rows are its descendants) or one of its descendants
            // (the rest of the owner's subtree follows contiguously).
            double subtreeEnd = cum;
            for (final k in controller.visibleNodes.skip(
              controller.getVisibleIndex(key) + 1,
            )) {
              if (controller.getDepth(k) == 0) {
                break;
              }
              subtreeEnd += controller.getCurrentExtent(k);
            }
            return (owner, subtreeEnd - scroll.offset);
          }
        }
        return ("", 0.0);
      }

      // expandAll grows a's subtree above p; p's true bottom moves down
      // past the scroll offset, so the band must hand over from z to p
      // and never go blank.
      controller.expandAll();
      var sawPPinnedMidBulk = false;
      for (var f = 0; f < 25; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        final (owner, coverage) = bandTruth();
        if (owner.isEmpty || coverage < 2.0) {
          // Handover boundary noise: skip the sub-2px crossover frame.
          continue;
        }
        final painted = render.debugLastPaintedStickyKeys;
        expect(
          painted,
          <String>{owner},
          reason: "frame $f: $owner's subtree covers the band by "
              "${coverage.toStringAsFixed(1)}px but painted=$painted",
        );
        if (owner == "p" && controller.hasActiveAnimations) {
          sawPPinnedMidBulk = true;
        }
      }
      expect(
        sawPPinnedMidBulk,
        isTrue,
        reason: "setup sanity: the handover to p must happen MID-bulk, "
            "while the stale-slot window is open",
      );

      await tester.pumpAndSettle();
      expect(render.debugLastPaintedStickyKeys, <String>{"p"});

      // Reverse direction: collapseAll shrinks everything (content before
      // p included), so p's true bottom rises back past the offset and the
      // band must keep tracking the true owner instead of holding p on the
      // stale (too-low) bottom. The scrollable clamps the offset as content
      // shrinks; bandTruth reads the live offset each frame.
      controller.collapseAll();
      var checkedMidBulkFrames = 0;
      for (var f = 0; f < 25; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        final (owner, coverage) = bandTruth();
        if (owner.isEmpty || coverage < 2.0) {
          continue;
        }
        final painted = render.debugLastPaintedStickyKeys;
        expect(
          painted,
          <String>{owner},
          reason: "collapseAll frame $f: $owner's subtree covers the band "
              "by ${coverage.toStringAsFixed(1)}px but painted=$painted",
        );
        if (controller.hasActiveAnimations) {
          checkedMidBulkFrames++;
        }
      }
      expect(
        checkedMidBulkFrames,
        greaterThan(3),
        reason: "setup sanity: the collapse direction must be checked on "
            "genuinely mid-bulk frames",
      );
    },
  );
}
