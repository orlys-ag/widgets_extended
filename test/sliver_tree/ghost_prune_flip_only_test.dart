/// Repro suite for backlog item B17
/// (`plans/2026-08-11-b17-ghost-prune-flip-only.md`): edge ghosts must
/// retire when their FLIP slide settles, even while a make-room preview is
/// held.
///
/// Three defects share one root cause (ghost-lifecycle decisions read the
/// COMPOSED slide+preview state), and the tests below separate them:
///
/// - **Defect 1**, the element keys its ghost-cleanup layout on composed
///   `hasActiveSlides` (`sliver_tree_element.dart:277`), so a held preview
///   means NO layout runs and no prune path is reached at all. Covered by
///   "settled ghost retires" and "bounded scan restored", both of which put
///   the ghost OUTSIDE the preview span so its composed delta equals its
///   FLIP delta: defect 2's criterion would prune it, and only defect 1
///   explains its survival.
/// - **Defects 2 and 3**, `pruneSettled`'s composed criterion
///   (`_ghost_registry.dart:122-127`) and the composed `clearAll` gates
///   (`render_sliver_tree.dart:1218`, `:2255`). These bite only for a ghost
///   INSIDE the preview span, and only once something forces a layout.
///   Covered by "ghost inside the preview span", which forces that layout
///   with a scroll.
///
/// The last test is a GUARD, not a repro: it passes today and must keep
/// passing. It pins that a preview settling with no FLIP slide active still
/// triggers a layout. The fix adds a FLIP-only cleanup trigger, and if a
/// later change makes that trigger REPLACE the composed one rather than
/// join it, this is the test that catches the lost layout (and with it the
/// post-layout stale-eviction cadence, `sliver_tree_element.dart:364-366`).
///
/// The second group covers the INSTALL-side follow-up
/// (`plans/2026-08-11-ghost-install-inflight-predicate.md`): the
/// in-flight-slide predicate in
/// `GhostRegistry.applyClampAndInstallNewGhosts` must ask the FLIP engine,
/// not the composed delta, while the painted-position arithmetic around it
/// stays composed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const double _viewportHeight = 550.0;
const double _rowHeight = 40.0;
const int _rowCount = 60;
const Duration _slide = Duration(milliseconds: 300);
const Duration _makeRoom = Duration(milliseconds: 200);

/// Visible index the moved row lands on. Far below the viewport
/// (`40 * 40px = 1600px` against a 550px viewport) so its destination is
/// off-screen, which is the edge-ghost install condition
/// (`_ghost_registry.dart:326-337`).
const int _ghostDestIndex = 40;

Widget _harness(
  TreeController<String, String> controller, {
  ScrollController? scrollController,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: _viewportHeight,
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: _rowHeight,
                  child: Text(key),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

RenderSliverTree<String, String> _sliver(WidgetTester tester) {
  return tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
}

TreeController<String, String> _controller(WidgetTester tester) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: const TreeAnimationStyle(
      expandCollapse: TreeAnimationSpec(duration: _slide, curve: Curves.linear),
      enterExit: TreeAnimationSpec(duration: _slide, curve: Curves.linear),
      reorderSlide: TreeAnimationSpec(duration: _slide, curve: Curves.linear),
      makeRoom: TreeAnimationSpec(duration: _makeRoom, curve: Curves.linear),
    ),
  );
  controller.setRoots([
    for (int i = 0; i < _rowCount; i++) TreeNode(key: "n$i", data: "N$i"),
  ]);
  return controller;
}

/// Pumps the harness, then moves visible row `n2` to [_ghostDestIndex] so
/// exactly one edge ghost installs. Returns after the install frame, with
/// the ghost's FLIP slide still in flight.
///
/// Post-move visible order: `n0, n1, n3, n4, ... n40, n2, n41, ... n59`,
/// so `n2` sits at index 40 and index `i >= 41` holds `n(i)`.
Future<RenderSliverTree<String, String>> _installGhost(
  WidgetTester tester,
  TreeController<String, String> controller, {
  ScrollController? scrollController,
}) async {
  await tester.pumpWidget(
    _harness(controller, scrollController: scrollController),
  );
  await tester.pumpAndSettle();
  final sliver = _sliver(tester);

  expect(sliver.debugComposerGhostCount, 0, reason: "setup: idle, no ghosts");
  expect(
    _rowCount * _rowHeight,
    greaterThan(_viewportHeight * 2),
    reason: "setup: the tree must overflow the viewport",
  );

  controller.moveNode(
    "n2",
    null,
    index: _ghostDestIndex,
    animate: true,
    slideDuration: _slide,
    slideCurve: Curves.linear,
  );
  await tester.pump(); // install frame: consumes the baseline

  expect(
    sliver.debugComposerGhostCount,
    greaterThan(0),
    reason:
        "setup: the move must install at least one edge ghost, otherwise "
        "this test exercises nothing",
  );
  return sliver;
}

void main() {
  group("edge ghosts retire on FLIP-slide state, not composed state", () {
    testWidgets(
      "a settled FLIP slide's edge ghost retires while a preview is held",
      (tester) async {
        final controller = _controller(tester);
        addTearDown(controller.dispose);
        final sliver = await _installGhost(tester, controller);

        // Preview span is n1..n3 only: dragged n0 (index 0, subtree size 1)
        // with the gap after n3 (index 2). Rows at or after the gap take
        // -lift +lift = 0, so the ghost row (n2, index 40) carries NO
        // preview offset. That is what makes this test discriminate defect
        // 1 from defect 2.
        controller.setReorderPreview(
          draggedKey: "n0",
          targetKey: "n3",
          gapBelowTarget: true,
        );
        await tester.pump(); // arm the preview ticker

        final layoutsBeforeSettle = sliver.debugPerformLayoutCount;
        await tester.pump(_makeRoom);
        await tester.pump(_slide);

        expect(
          controller.hasActiveSlides,
          isTrue,
          reason: "setup: the held preview must keep hasActiveSlides true",
        );
        // Prove the surviving ghost is settled without assuming which row
        // it is: the only rows still carrying a delta are the two the
        // preview shifted, and neither can be an edge ghost (both were
        // on-screen before AND after the move, which is the "animate real
        // delta" case, not the ghost-install case).
        final stillMoving = <String>{
          for (int i = 0; i < _rowCount; i++)
            if (controller.getSlideDelta("n$i") != 0.0) "n$i",
        };
        expect(
          stillMoving,
          <String>{"n1", "n3"},
          reason:
              "setup: only the preview-shifted rows may still carry a "
              "delta, so any retained ghost is provably settled",
        );

        expect(
          sliver.debugComposerGhostCount,
          0,
          reason:
              "a settled edge ghost must retire during a held preview; "
              "retaining it forces every drop-target lookup onto the O(N) "
              "full scan",
        );
        expect(
          sliver.debugPerformLayoutCount,
          greaterThan(layoutsBeforeSettle),
          reason:
              "the FLIP settle must schedule the cleanup layout even while "
              "a preview is held, otherwise no prune path can run at all",
        );

        controller.clearReorderPreview(animate: false);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "the bounded drop-target scan is restored once the ghost retires",
      (tester) async {
        final controller = _controller(tester);
        addTearDown(controller.dispose);
        final sliver = await _installGhost(tester, controller);

        controller.setReorderPreview(
          draggedKey: "n0",
          targetKey: "n3",
          gapBelowTarget: true,
        );
        await tester.pump();
        await tester.pump(_makeRoom);
        await tester.pump(_slide);

        expect(
          controller.hasActiveSlides,
          isTrue,
          reason: "setup: still mid-drag, preview held",
        );

        // The payoff of the whole item: with no ghosts and fresh offsets,
        // the per-pointer-event lookup returns to the bounded window scan
        // instead of the exact O(N) full scan
        // (`render_sliver_tree.dart:1660-1664`).
        final hit = sliver.findRowAtPaintedY(100.0);
        expect(hit, isNotNull, reason: "setup: the probe must find a row");
        expect(
          sliver.debugLastFindRowUsedFullScan,
          isFalse,
          reason:
              "a retained ghost fails the bounded-scan precondition, so "
              "every drop-target lookup in a back-to-back drag pays O(N)",
        );
        // The routed answer must still be right, not merely cheap. This
        // state previously took the exact full scan, so bounded-scan
        // correctness has never been pinned here.
        //
        // The sweep stays INSIDE the viewport band on purpose. The bounded
        // path reads layout-stamped extents while the oracle reads
        // controller truth, and the two are only defined to agree for rows
        // a layout has measured. This tree is 2400px against a 550px
        // viewport plus cache, so most rows are never measured and a
        // full-height sweep would diverge for reasons that have nothing to
        // do with this item (same constraint the oracle suite documents at
        // `findrow_bounded_scan_oracle_test.dart:23-30`).
        for (double y = 10.0; y <= 500.0; y += 25.0) {
          final routed = sliver.findRowAtPaintedY(y);
          final oracle = sliver.debugFindRowFullScan(y);
          expect(oracle, isNotNull, reason: "oracle null at y=$y");
          expect(routed, isNotNull, reason: "routed null at y=$y");
          expect(routed!.key, oracle!.key, reason: "key mismatch at y=$y");
          expect(
            routed.paintedOffset,
            closeTo(oracle.paintedOffset, 1e-6),
            reason: "offset mismatch at y=$y",
          );
          expect(
            routed.extent,
            closeTo(oracle.extent, 1e-6),
            reason: "extent mismatch at y=$y",
          );
        }

        controller.clearReorderPreview(animate: false);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "a ghost inside the preview span retires once a layout runs",
      (tester) async {
        // Isolates defects 2 and 3 from defect 1. The ghost row DOES carry
        // a preview offset here, so its composed delta is non-zero while
        // its FLIP delta is zero, and a scroll forces the layout that
        // defect 1 otherwise withholds. What survives that layout is
        // attributable to the composed prune criterion and the composed
        // clearAll gates alone.
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);
        final controller = _controller(tester);
        addTearDown(controller.dispose);
        final sliver = await _installGhost(
          tester,
          controller,
          scrollController: scrollController,
        );

        // Gap at index 45 straddles the ghost: rows 1..44 shift by -lift,
        // which includes n2 at index 40. Rows at index 45 and beyond
        // cancel to zero.
        controller.setReorderPreviewAtIndex(
          draggedKey: "n0",
          gapVisibleIndex: 45,
        );
        await tester.pump();
        await tester.pump(_makeRoom);
        await tester.pump(_slide);

        expect(
          controller.getSlideDelta("n45"),
          0.0,
          reason:
              "setup: a row past the gap carries no preview offset, so a "
              "zero delta there proves the FLIP slides have settled",
        );
        expect(
          controller.getSlideDelta("n2"),
          isNot(0.0),
          reason:
              "setup: the ghost row must sit INSIDE the preview span, "
              "otherwise this test degenerates into the defect 1 case",
        );

        // Force the layout defect 1 withholds, without bringing the ghost
        // row (y = 1600) back on screen.
        final layoutsBeforeScroll = sliver.debugPerformLayoutCount;
        scrollController.jumpTo(50.0);
        await tester.pump();
        expect(
          sliver.debugPerformLayoutCount,
          greaterThan(layoutsBeforeScroll),
          reason: "setup: the scroll must actually run a layout pass",
        );

        expect(
          sliver.debugComposerGhostCount,
          0,
          reason:
              "a ghost whose FLIP slide has settled is semantically "
              "settled; a held preview offset must not keep it alive",
        );

        controller.clearReorderPreview(animate: false);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "a settled ghost inside the span retires while other rows still slide",
      (tester) async {
        // Isolates change 2 (`pruneSettled`'s criterion) from change 3
        // (the `clearAll` gates). The previous test cannot: by the time it
        // forces a layout, every FLIP slide has settled, so Step 0b takes
        // the `clearAll` branch and `pruneSettled` is never reached.
        //
        // Here a SECOND move keeps other rows sliding, so Step 0b takes
        // the prune branch instead and the criterion alone decides the
        // settled ghost's fate. This is an ordinary drag state: an
        // autoscroll commit landing while an earlier slide is still in
        // flight.
        final controller = _controller(tester);
        addTearDown(controller.dispose);
        final sliver = await _installGhost(tester, controller);

        // Drag n30 (visible index 29), gap at 45: the shifted span is
        // indices 30..44, which contains the ghost at 40 and excludes
        // every row the second move touches. That exclusion is load
        // bearing. A preview offset moves PAINTED positions, and the
        // ghost-install decision is made on painted positions, so a
        // second move among preview-shifted rows installs additional,
        // legitimately-active ghosts and the count assertion below would
        // be measuring the wrong thing.
        controller.setReorderPreviewAtIndex(
          draggedKey: "n30",
          gapVisibleIndex: 45,
        );
        await tester.pump();
        await tester.pump(_makeRoom);
        await tester.pump(_slide);

        final ghostNid = controller.nidOf("n2");
        expect(ghostNid, greaterThanOrEqualTo(0), reason: "setup: n2 is live");
        expect(
          controller.getFlipSlideDeltaNid(ghostNid),
          0.0,
          reason: "setup: the ghost's own FLIP slide must have settled",
        );
        expect(
          controller.getSlideDelta("n2"),
          isNot(0.0),
          reason:
              "setup: the ghost must carry a held preview offset, so only "
              "the FLIP-only criterion can retire it",
        );

        // Second move, entirely among on-screen rows and nowhere near the
        // ghost's slot, so fresh FLIP slides start WITHOUT disturbing the
        // ghost row's own (settled) slide. The mutation runs a layout.
        controller.moveNode(
          "n5",
          null,
          index: 8,
          animate: true,
          slideDuration: _slide,
          slideCurve: Curves.linear,
        );
        await tester.pump();

        expect(
          controller.hasActiveFlipSlides,
          isTrue,
          reason:
              "setup: other rows must still be sliding, otherwise Step 0b "
              "takes the clearAll branch and this degenerates into the "
              "previous test",
        );
        expect(
          controller.getFlipSlideDeltaNid(ghostNid),
          0.0,
          reason:
              "setup: the second move must not restart the ghost row's own "
              "slide, or it is no longer a settled ghost",
        );

        expect(
          sliver.debugComposerGhostCount,
          0,
          reason:
              "pruneSettled must key on the FLIP delta: a ghost held up "
              "only by a preview offset is semantically settled",
        );

        controller.clearReorderPreview(animate: false);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "GUARD: a preview settling with no FLIP active still runs a layout",
      (tester) async {
        // Passes today. The fix adds a FLIP-only cleanup trigger; if that
        // trigger ever REPLACES the composed one instead of joining it,
        // this release tick matches no branch at all (the paint-only
        // branch also requires composed hasActiveSlides) and the
        // post-settle layout disappears, taking the stale-eviction cadence
        // with it.
        final controller = _controller(tester);
        addTearDown(controller.dispose);
        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();
        final sliver = _sliver(tester);

        controller.setReorderPreview(
          draggedKey: "n0",
          targetKey: "n3",
          gapBelowTarget: true,
        );
        await tester.pump();
        await tester.pump(_makeRoom);
        expect(
          controller.hasActiveSlides,
          isTrue,
          reason: "setup: the preview must be held",
        );
        expect(
          sliver.debugComposerGhostCount,
          0,
          reason: "setup: no ghosts here, this is a preview-only lifecycle",
        );

        final layoutsBeforeRelease = sliver.debugPerformLayoutCount;
        controller.clearReorderPreview(animate: true);
        await tester.pump();
        await tester.pump(_makeRoom);

        expect(
          controller.hasActiveSlides,
          isFalse,
          reason: "setup: the release must have fully settled",
        );
        expect(
          sliver.debugPerformLayoutCount,
          greaterThan(layoutsBeforeRelease),
          reason:
              "the preview settle transition must still schedule one "
              "layout so post-layout stale eviction keeps its cadence",
        );
      },
    );
  });

  group("ghost install predicate reads FLIP-only state", () {
    // Repros for the INSTALL-side follow-up
    // (`plans/2026-08-11-ghost-install-inflight-predicate.md`).
    // `applyClampAndInstallNewGhosts` asks per row "is there an existing
    // engine slide to compose against?" but derives the answer from the
    // COMPOSED delta, so every row a held make-room preview has shifted
    // answers yes even with no FLIP slide at all. Both tests hold a
    // preview whose span covers off-screen rows (dragging n0 with the gap
    // at index 45 shifts rows 1..44 up by one row height, and
    // `snapshotVisibleOffsets` walks ALL visible rows, so off-screen rows
    // are in the staged baseline), then trigger a staged mutation with
    // `moveNode`, the simpler of the two verified reaching paths (the
    // realistic one is a dwell-expand mid-drag).

    testWidgets(
      "no slide is installed for a preview-shifted row that is off-screen "
      "before and after the mutation",
      (tester) async {
        final controller = _controller(tester);
        addTearDown(controller.dispose);
        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();

        controller.setReorderPreviewAtIndex(
          draggedKey: "n0",
          gapVisibleIndex: 45,
        );
        await tester.pump();
        await tester.pump(_makeRoom);

        final nid15 = controller.nidOf("n15");
        expect(nid15, greaterThanOrEqualTo(0), reason: "setup: n15 is live");
        expect(
          controller.getFlipSlideDeltaNid(nid15),
          0.0,
          reason: "setup: n15 must carry no FLIP slide",
        );
        final composedBefore = controller.getSlideDelta("n15");
        expect(
          composedBefore,
          isNot(0.0),
          reason:
              "setup: n15 must carry a held preview offset, so its "
              "composed delta diverges from its FLIP delta",
        );
        // n15 sits at visible index 15 (structural y 600 against a 550px
        // viewport); the preview shift leaves it past the bottom edge.
        expect(
          15 * _rowHeight + composedBefore,
          greaterThan(_viewportHeight),
          reason: "setup: n15 must be painted off-screen before the move",
        );

        // Staged mutation: moving n16 to index 2 shifts n2..n15 down one
        // slot, so n15's structural base changes while the row stays
        // off-screen on both sides of the mutation.
        controller.moveNode(
          "n16",
          null,
          index: 2,
          animate: true,
          slideDuration: _slide,
          slideCurve: Curves.linear,
        );
        await tester.pump(); // install frame: consumes the baseline

        expect(
          controller.visibleNodes.indexOf("n15"),
          16,
          reason: "setup: the move must shift n15 down one slot",
        );
        expect(
          16 * _rowHeight + controller.getSlideDelta("n15"),
          greaterThan(_viewportHeight),
          reason: "setup: n15 must be painted off-screen after the move too",
        );
        // Proof the consume genuinely ran and installed slides: a VISIBLE
        // row the move shifted carries a real FLIP delta.
        expect(
          controller.getFlipSlideDeltaNid(controller.nidOf("n3")),
          isNot(0.0),
          reason: "setup: the mutation must install slides for visible rows",
        );

        expect(
          controller.getFlipSlideDeltaNid(nid15),
          0.0,
          reason:
              "a row that is off-screen before AND after the mutation and "
              "has no engine slide to compose must be dropped from the "
              "batch; a held preview offset is not an in-flight slide, "
              "and installing one extends the FLIP-active window (and "
              "with it ghost cleanup) for a row nobody can see",
        );

        controller.clearReorderPreview(animate: false);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "a preview-shifted row sliding IN starts beyond the viewport edge, "
      "not just inside it",
      (tester) async {
        final controller = _controller(tester);
        addTearDown(controller.dispose);
        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();

        expect(
          controller.slideClampOverhangViewports,
          greaterThan(0.0),
          reason:
              "setup: with a zero overhang the two clamps differ by only "
              "the 0.5px epsilon, which this test cannot discriminate",
        );

        controller.setReorderPreviewAtIndex(
          draggedKey: "n0",
          gapVisibleIndex: 45,
        );
        await tester.pump();
        await tester.pump(_makeRoom);

        final nid15 = controller.nidOf("n15");
        expect(
          controller.getFlipSlideDeltaNid(nid15),
          0.0,
          reason: "setup: n15 must carry no FLIP slide",
        );
        expect(
          controller.getSlideDelta("n15"),
          isNot(0.0),
          reason: "setup: n15 must carry a held preview offset",
        );
        expect(
          15 * _rowHeight + controller.getSlideDelta("n15"),
          greaterThan(_viewportHeight),
          reason: "setup: n15 must start painted off-screen",
        );

        // Slide-IN: n15 moves from off-screen to a visible slot. Both the
        // buggy and the fixed predicate install a slide; what differs is
        // the clamped start. The initial-install clamp starts at viewport
        // bottom + overhang (off-screen); the composition clamp starts at
        // viewport bottom - 0.5 (inside), and taking it here means the
        // row pops in at the boundary instead of gliding in.
        controller.moveNode(
          "n15",
          null,
          index: 5,
          animate: true,
          slideDuration: _slide,
          slideCurve: Curves.linear,
        );
        await tester.pump(); // install frame

        expect(
          controller.visibleNodes.indexOf("n15"),
          5,
          reason: "setup: n15 must land on the visible slot",
        );
        expect(
          controller.getFlipSlideDeltaNid(nid15),
          isNot(0.0),
          reason: "setup: a slide-IN must install a real engine slide",
        );

        // Painted position at install = structural + FLIP + preview. The
        // assertion is deliberately "outside the viewport", not a literal
        // delta: `overhangPx` is a captured setting-derived value
        // (`_viewport_snapshot.dart:69-73`), not a constant this test
        // should hardcode.
        final paintedAtInstall =
            5 * _rowHeight + controller.getSlideDelta("n15");
        expect(
          paintedAtInstall,
          greaterThanOrEqualTo(_viewportHeight),
          reason:
              "a slide-IN with no engine slide to compose must take the "
              "initial-install clamp (edge plus overhang, off-screen); "
              "the just-inside-the-edge clamp exists only to keep an "
              "already painted row visible at the moment of "
              "re-composition",
        );

        controller.clearReorderPreview(animate: false);
        await tester.pumpAndSettle();
      },
    );
  });
}
