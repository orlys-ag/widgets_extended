/// Regression tests for the "mid-flight FLIP slide gets lost on re-moveTo
/// to off-screen" bug.
///
/// Symptom: when `moveNode(animate: true)` is called on a row whose
/// painted Y at staging is already off-screen AND whose new structural Y
/// is also off-screen (but on the OPPOSITE side, so the slide trajectory
/// passes through the viewport), the slide was never installed —
/// the row jumped structurally with no animation. The user reported
/// this as "the node doesn't seem to correctly transition the animation
/// to its new position."
///
/// Root cause:
///   1. `moveNode` calls `_cancelAnimationStateForSubtree(key)` which
///      destroys the moved row's existing engine slide entry.
///   2. The next `_consumeSlideBaselineIfAny` snapshots `current` with
///      `slideY = 0` (entry just got cleared).
///   3. `_applyClampAndInstallNewGhosts` enters the `!priorOn && !currOn`
///      branch and the legacy "no in-flight slide → suppress" guard
///      drops the row from the engine batch entirely.
///   4. No new slide is installed; the row paints at its new structural
///      position immediately. Visually: a jump, not a slide.
///
/// Secondary symptom: even when a slide WAS in flight (composition
/// path), the row was eligible for stale-eviction once
/// `maxActiveSlideAbsDelta` shrank below the structural distance from
/// the viewport — the render box could be dropped before the slide
/// settled, producing a vanishing-mid-transit artifact.
///
/// Fix:
///   - `_applyClampAndInstallNewGhosts` no longer suppresses when the
///     baseline→current trajectory crosses the viewport. The engine
///     receives a fresh install whose `rawDeltaY = baseline.y -
///     current.y`, and the visible transit is animated.
///   - `RenderSliverTree.isNodeRetained` retains rows with a non-zero
///     slide delta (in either axis) so the render box survives the
///     full slide even if the structural Y is well outside the cache
///     region.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const _kRowHeight = 50.0;
const _kViewportHeight = 500.0;

Widget _harness(
  TreeController<String, int> controller, {
  ScrollController? scrollController,
  double height = _kViewportHeight,
  double cacheExtent = 0.0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: CustomScrollView(
          controller: scrollController,
          cacheExtent: cacheExtent,
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

TreeController<String, int> _newController(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 600),
}) {
  return TreeController<String, int>(
    vsync: tester,
    animationDuration: duration,
    animationCurve: Curves.linear,
  );
}

void main() {
  group("mid-flight FLIP slide retention across re-moveTo", () {
    testWidgets(
      "row whose painted Y is just past one viewport edge and whose "
      "new structural Y is past the OPPOSITE edge gets a slide whose "
      "visible trajectory crosses the viewport (was: jumped silently)",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 100; i++) TreeNode(key: "r$i", data: i),
        ]);

        await tester.pumpWidget(_harness(
          controller,
          scrollController: scroll,
          cacheExtent: 0.0,
        ));
        await tester.pumpAndSettle();

        // Scroll so r0's structural Y (= 0) is far above the viewport.
        // Viewport = [2000, 2500] in scroll-space; cache extent is 0.
        scroll.jumpTo(2000);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey("row-r0")), findsNothing,
            reason: "r0 must be evicted before the test starts");

        // Move r0 to position 44 (structural y = 2200, inside viewport).
        // Slide-IN: baseline clamped to top edgeY = 1950. Initial
        // currentDelta = 1950 - 2200 = -250. Painted at t=0 ≈ 1950
        // (just past top edge — `priorOn` will be false on the next
        // re-move snapshot).
        controller.moveNode(
          "r0",
          null,
          index: 44,
          animate: true,
          slideDuration: const Duration(milliseconds: 600),
          slideCurve: Curves.linear,
        );
        await tester.pump();
        // Advance the slide a tiny amount so painted is still close to
        // edgeY (off-screen above viewport).
        await tester.pump(const Duration(microseconds: 100));

        expect(controller.hasActiveSlides, true,
            reason: "slide-IN must be in flight");

        // Re-move r0 to position 99 (structural y = 4950, far below
        // viewport). The painted-at-stage (≈1950) is past the TOP
        // edge; the new structural (4950) is past the BOTTOM edge.
        // Their trajectory crosses the visible viewport [2000, 2500].
        // The fix re-installs a slide whose visible transit shows the
        // row crossing the viewport.
        controller.moveNode(
          "r0",
          null,
          index: 99,
          animate: true,
          slideDuration: const Duration(milliseconds: 600),
          slideCurve: Curves.linear,
        );
        await tester.pump();

        // The new slide's startDelta should reflect the full trajectory
        // (≈ -3000: from painted ≈ 1950 to structural 4950). Without the
        // fix, the engine slide would be 0 (cancelled, then suppressed).
        expect(controller.hasActiveSlides, true,
            reason: "the cross-viewport re-moveTo must install a slide");
        expect(controller.getSlideDelta("r0").abs(), greaterThan(2000.0),
            reason: "engine slide must reflect the full baseline→current "
                "trajectory (≈3000 px). Got ${controller.getSlideDelta('r0')}.");

        // Pump enough to reach the visible-transit window. With duration
        // 600 ms and linear curve, the row crosses the viewport between
        // ~10 ms (painted enters at top) and ~120 ms (painted exits at
        // bottom).
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        // r0's render box must remain mounted while its FLIP slide is
        // still in flight. Without the retention fix, stale-eviction
        // could drop the render box mid-transit even though the slide
        // is still ticking.
        expect(find.byKey(const ValueKey("row-r0")), findsOneWidget,
            reason: "r0 must remain mounted while its FLIP slide is "
                "still in flight, even when both old painted Y and new "
                "structural Y sit outside the viewport.");

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "engine slide for re-moveTo with off-screen → off-screen-opposite "
      "trajectory composes correctly: at t=0 painted ≈ old painted; "
      "at t=1 painted = new structural",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester,
            duration: const Duration(milliseconds: 1000));
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 100; i++) TreeNode(key: "r$i", data: i),
        ]);

        await tester.pumpWidget(_harness(
          controller,
          scrollController: scroll,
          cacheExtent: 0.0,
        ));
        await tester.pumpAndSettle();
        scroll.jumpTo(2000);
        await tester.pump();
        await tester.pumpAndSettle();

        controller.moveNode(
          "r0",
          null,
          index: 44,
          animate: true,
          slideDuration: const Duration(milliseconds: 1000),
          slideCurve: Curves.linear,
        );
        await tester.pump();
        await tester.pump(const Duration(microseconds: 100));

        controller.moveNode(
          "r0",
          null,
          index: 99,
          animate: true,
          slideDuration: const Duration(milliseconds: 1000),
          slideCurve: Curves.linear,
        );
        await tester.pump();

        // Right after install + one frame tick, the slide's painted Y
        // should be near the row's painted-at-stage position (≈1950),
        // monotonically progressing toward the new structural Y (4950).
        // The first frame tick advances progress slightly, so allow
        // generous slack — the assertion proves the slide installed
        // with a near-full trajectory delta (~3000 px), not zero.
        final initialDelta = controller.getSlideDelta("r0");
        expect(initialDelta.abs(), greaterThan(2500.0),
            reason: "the freshly installed slide should still carry "
                "most of the ≈3000 px trajectory after one frame tick. "
                "Got ${initialDelta.abs()}.");
        final initialPainted = 4950.0 + initialDelta;
        expect(initialPainted, lessThan(2500.0),
            reason: "right after install, painted Y should be near the "
                "old painted (≈1950), well above the viewport bottom.");

        await tester.pumpAndSettle();
        // After settle: slide delta = 0, painted = structural.
        expect(controller.getSlideDelta("r0"), 0.0);
      },
    );
  });
}
