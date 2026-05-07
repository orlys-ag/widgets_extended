/// Regression test for the bug where rapid `moveNode(animate: true)` taps
/// during cascaded reparents would leave a row painted PAST the viewport
/// for a substantial fraction of the slide, even though the row's new
/// structural Y was inside the viewport.
///
/// Repro chain:
/// 1. Row R is at structural Y far below viewport (settled, no slide).
/// 2. Tap 1: `moveNode(R, animate: true)` to a new structural Y inside
///    the viewport. The slide-IN clamp installs baseline at edge_y
///    (above viewport top, by overhang). painted starts off-viewport,
///    crosses viewport edge mid-slide, settles at struct.
/// 3. Mid-flight (slide barely advanced), Tap 2: `moveNode(R, animate:
///    true)` to ANOTHER inside-viewport structural Y. Snapshot baseline
///    captures the row's current painted Y, which is still past the edge
///    because the slide hasn't ticked far enough to reach the viewport.
///
/// Pre-fix: the composition path of `_applyClampAndInstallNewGhosts`'s
/// `!priorOn && currOn` branch left baseline as-is when an in-flight
/// slide existed. The new slide's `composedY = baseline.y - struct`
/// kept painted at t=0 ≈ baseline.y (off-viewport). The row was
/// invisible until the slide ticked enough to bring painted into
/// viewport — a substantial off-viewport delay perceived by the user as
/// "ghost rows disappearing during rapid reparent".
///
/// Post-fix: the composition path now clamps baseline to JUST INSIDE
/// the viewport edge. painted at t=0 is in-viewport; the slide is
/// fully visible from the first frame.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const _kRowHeight = 50.0;
const _kViewportHeight = 500.0;

Widget _harness(TreeController<String, int> controller, ScrollController s) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: _kViewportHeight,
        child: CustomScrollView(
          controller: s,
          slivers: <Widget>[
            SliverTree<String, int>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: _kRowHeight,
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

void main() {
  group("slide-IN composition keeps painted inside viewport", () {
    testWidgets(
      "after re-moveTo into viewport while a prior slide-IN is still in "
      "flight, painted Y at t=0 of the new slide is INSIDE the viewport "
      "(not past the bottom edge)",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = TreeController<String, int>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 600),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        // 100 rows. Row "r0" is at struct=0 (above viewport once we
        // scroll to 2000). We'll move it INTO the viewport twice in
        // rapid succession.
        controller.setRoots([
          for (var i = 0; i < 100; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scroll));
        await tester.pumpAndSettle();
        scroll.jumpTo(2000.0);
        await tester.pump();
        await tester.pumpAndSettle();

        final viewportTop = scroll.offset;
        final viewportBottom = viewportTop + _kViewportHeight;

        // Tap 1: move r0 into the viewport. Initial install (no in-
        // flight slide) — clamps baseline to edge_y (above viewport).
        controller.moveNode(
          "r0",
          null,
          index: 44, // struct = 44 * 50 = 2200, inside viewport
          animate: true,
          slideDuration: const Duration(milliseconds: 600),
          slideCurve: Curves.linear,
        );
        await tester.pump();
        // Advance a tiny amount so the slide has barely ticked. painted
        // should still be near edge_y (above viewport top).
        await tester.pump(const Duration(milliseconds: 16));

        expect(controller.hasActiveSlides, true,
            reason: "tap-1 slide-IN must still be in flight");

        final paintedAfterTap1 = 2200.0 + controller.getSlideDelta("r0");
        expect(
          paintedAfterTap1 < viewportTop,
          isTrue,
          reason: "after tap-1's brief tick, the row's painted top edge "
              "($paintedAfterTap1) must still be above viewport top "
              "($viewportTop) — i.e., most of the row is above the "
              "viewport with only a few pixels intruding at the top.",
        );

        // Tap 2: re-move r0 to a DIFFERENT in-viewport position.
        controller.moveNode(
          "r0",
          null,
          index: 46, // struct = 2300, still inside viewport
          animate: true,
          slideDuration: const Duration(milliseconds: 600),
          slideCurve: Curves.linear,
        );
        await tester.pump();

        // User-visible invariant: tap-2 must NOT pop the row off-screen.
        // What "off-screen pop" looks like in engine terms depends on
        // which slide-clamp branch the meaningfully-visible predicate
        // selects:
        //
        //   * Prior is meaningfully visible (≥ 4 px overlap with the
        //     viewport, the typical state after tap-1's brief tick):
        //     priorOn=true → composition does NOT clamp baseline. The
        //     row's painted Y at t=0 of tap-2 ≈ prior painted Y, so the
        //     visible portion (a few px at the top edge) is preserved
        //     from frame to frame. No clamp jump, smooth continuation.
        //
        //   * Prior is below the threshold (deeper above the viewport,
        //     e.g. when tap-1's tick advanced less): priorOn=false → the
        //     composition clamp moves baseline to viewportTop + epsilon
        //     and painted at t=0 lands strictly inside the viewport.
        //
        // Either way, the row remains MEANINGFULLY VISIBLE at t=0
        // (≥ 4 px in viewport). The pre-fix bug — painted lingering at
        // baseline ≈1950 (0 px visible) for a substantial fraction of
        // the slide — is excluded by both branches.
        final paintedAfterTap2 = 2300.0 + controller.getSlideDelta("r0");
        final visibleTopAfterTap2 = math.max(paintedAfterTap2, viewportTop);
        final visibleBottomAfterTap2 =
            math.min(paintedAfterTap2 + _kRowHeight, viewportBottom);
        final visiblePxAfterTap2 =
            visibleBottomAfterTap2 - visibleTopAfterTap2;
        expect(
          visiblePxAfterTap2,
          greaterThanOrEqualTo(4.0),
          reason: "tap-2 must keep the row meaningfully visible at t=0 "
              "(≥ 4 px in viewport [$viewportTop, $viewportBottom]). "
              "Got painted=$paintedAfterTap2, visible=$visiblePxAfterTap2 "
              "px (slideDelta=${controller.getSlideDelta('r0')}).",
        );

        // The render box must remain mounted throughout (no eviction).
        expect(
          find.byKey(const ValueKey("row-r0")),
          findsOneWidget,
          reason: "r0 should be rendered while its slide is in flight "
              "and its painted Y is inside the viewport.",
        );

        await tester.pumpAndSettle();
        // After settle: slide=0, painted=struct (2300, in viewport).
        expect(controller.getSlideDelta("r0"), 0.0);
      },
    );

    testWidgets(
      "re-promoted edge ghost (slide-OUT then move BACK into viewport) "
      "after enough advance to push painted past viewport edge — new "
      "slide paints at t=0 inside viewport (not at the off-viewport "
      "edge_y where the ghost-aware snapshot baseline sits)",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = TreeController<String, int>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 800),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        controller.setRoots([
          for (var i = 0; i < 100; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scroll));
        await tester.pumpAndSettle();

        final viewportTop = scroll.offset;
        final viewportBottom = viewportTop + _kViewportHeight;

        // Tap 1: move r0 from struct=0 (in viewport) to struct=4950
        // (far below viewport). Slide-OUT-bottom — installs edge ghost
        // at edge_y = viewportBottom + overhangPx. The ghost paints at
        // (edge_y + slideDelta), starting at struct_OLD (=0) and
        // sliding toward edge_y.
        controller.moveNode(
          "r0",
          null,
          index: 99,
          animate: true,
          slideDuration: const Duration(milliseconds: 800),
          slideCurve: Curves.linear,
        );
        await tester.pump();
        // Advance the slide far enough that the ghost's painted Y has
        // crossed past the viewport edge (≥ viewportBottom). For
        // default overhangPx = 0.1 * 500 = 50, painted crosses 500 at
        // progress ≈ 91% (= overhang/total = 50/550). Pump 750 ms
        // (94% of 800 ms duration) to put painted at ≈ 525 — past the
        // edge. This is the precondition for `priorOn=false` on the
        // next stage's snapshot.
        await tester.pump(const Duration(milliseconds: 750));

        expect(controller.hasActiveSlides, true,
            reason: "tap-1 slide-OUT must still be in flight");

        // Tap 2: move r0 BACK to struct=100 (well inside viewport).
        // Re-promote — the edge ghost is removed; with the snapshot
        // baseline still at off-viewport edge_y + slideY, the
        // composition's `priorOn=false && currOn=true` branch triggers
        // the slide-IN clamp.
        controller.moveNode(
          "r0",
          null,
          index: 2,
          animate: true,
          slideDuration: const Duration(milliseconds: 800),
          slideCurve: Curves.linear,
        );
        await tester.pump();

        final structAfterTap2 = 2 * _kRowHeight; // 100.0
        final paintedAfterTap2 =
            structAfterTap2 + controller.getSlideDelta("r0");
        expect(
          paintedAfterTap2,
          inInclusiveRange(viewportTop, viewportBottom),
          reason: "post-fix: re-promoted ghost whose snapshot baseline "
              "sits past the viewport edge must still land painted at "
              "t=0 of the new slide INSIDE the viewport. Got "
              "painted=$paintedAfterTap2, slideDelta="
              "${controller.getSlideDelta('r0')} "
              "(viewport=[$viewportTop, $viewportBottom]).",
        );

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "cascaded slide-INs (3 rapid taps into viewport) keep painted Y "
      "inside viewport after each composition install",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = TreeController<String, int>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 800),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        controller.setRoots([
          for (var i = 0; i < 200; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scroll));
        await tester.pumpAndSettle();
        scroll.jumpTo(5000.0);
        await tester.pump();
        await tester.pumpAndSettle();

        final viewportTop = scroll.offset;
        final viewportBottom = viewportTop + _kViewportHeight;

        // Three rapid taps moving r0 to different in-viewport positions.
        // Pre-fix, each composition would re-baseline from off-viewport,
        // accumulating off-viewport time across taps.
        final targets = <int>[104, 106, 108]; // struct = 5200, 5300, 5400
        for (int i = 0; i < targets.length; i++) {
          controller.moveNode(
            "r0",
            null,
            index: targets[i],
            animate: true,
            slideDuration: const Duration(milliseconds: 800),
            slideCurve: Curves.linear,
          );
          await tester.pump();
          // Brief tick between taps so the slide barely advances.
          await tester.pump(const Duration(milliseconds: 16));

          // After every tap (including the first initial install whose
          // clamp uses edge_y), painted may be just past the edge by up
          // to overhangPx. After tap 2+ (composition with my fix),
          // painted must be INSIDE viewport.
          if (i > 0) {
            final structY = targets[i] * _kRowHeight;
            final painted = structY + controller.getSlideDelta("r0");
            expect(
              painted,
              inInclusiveRange(viewportTop, viewportBottom),
              reason: "tap ${i + 1} (composition): painted=$painted must "
                  "be inside [$viewportTop, $viewportBottom]. "
                  "structY=$structY, slideDelta="
                  "${controller.getSlideDelta('r0')}.",
            );
          }
        }

        await tester.pumpAndSettle();
      },
    );
  });
}
