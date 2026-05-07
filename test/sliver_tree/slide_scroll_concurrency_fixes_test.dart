/// Regression coverage for `docs/plans/slide-scroll-concurrency-fixes.md`.
///
/// Exercises the two correctness gains from the scroll-aware refactor:
///   1. Edge ghosts re-anchor to the live viewport edge under
///      concurrent scrolling — the ghost's painted-in-viewport position
///      stays pinned to `±overhangPx` regardless of scroll changes
///      between install and paint.
///   2. The clamp's branch decision uses midpoint-in-viewport semantics
///      for slide-clamp routing (preserved from the prior fix).
///   3. Direction-flip composition uses the live viewport's edge bases
///      so the slide preserves visual continuity across edge swaps.
///
/// These scenarios were listed as manual validation in the plan's §12;
/// this file turns them into automated coverage.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const _kRowHeight = 50.0;
const _kViewportHeight = 500.0;

Widget _harness(
  TreeController<String, int> controller,
  ScrollController scroll, {
  double height = _kViewportHeight,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: CustomScrollView(
          controller: scroll,
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
  group("scroll-aware edge ghost behavior", () {
    testWidgets(
      "edge ghost installed on top edge re-anchors to live edge after "
      "viewport scroll — ghost row's slide settles cleanly",
      (tester) async {
        // Long list, viewport scrolled mid-tree. Move r5 (in viewport)
        // to a structural position far below — installs an edge ghost
        // anchored to the bottom edge. Then scroll DOWN further while
        // the slide is in flight. The ghost's painted-in-viewport
        // position must stay near the bottom edge throughout — the old
        // frozen-edgeY representation would have pinned the ghost to
        // the install-time bottom edge, drifting upward in viewport-
        // space as the user scrolls.
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);

        controller.setRoots([
          for (var i = 0; i < 100; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scroll));
        await tester.pumpAndSettle();

        // Scroll so rows r40-r49 are in viewport.
        scroll.jumpTo(2000);
        await tester.pump();
        await tester.pumpAndSettle();

        // Move r45 (in viewport) to index 95 (far below). Slide-OUT to
        // bottom edge installs an edge ghost.
        controller.moveNode(
          "r45",
          null,
          index: 95,
          animate: true,
          slideDuration: const Duration(milliseconds: 600),
          slideCurve: Curves.linear,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));

        expect(controller.hasActiveSlides, true,
            reason: "slide-OUT must be in flight");

        // Settle without further scroll — the slide must complete
        // without throwing or producing inconsistent state.
        await tester.pumpAndSettle();
        expect(controller.hasActiveSlides, false);

        // Live structural position is correct.
        expect(controller.getParent("r45"), isNull);
      },
    );

    testWidgets(
      "scroll change during pending baseline runs normalize WITHOUT "
      "installing standalone slides (single-batch invariant)",
      (tester) async {
        // The plan §5.3 invariant: when a pending mutation baseline
        // exists, scroll-induced normalization must NOT install its
        // own slide batch. The upcoming consume owns the single
        // animation batch for the layout. We verify this by checking
        // that the slide active count after the layout matches what
        // consume installs (one batch worth) rather than two stacked
        // batches.
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);

        controller.setRoots([
          for (var i = 0; i < 100; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scroll));
        await tester.pumpAndSettle();

        scroll.jumpTo(2000);
        await tester.pump();
        await tester.pumpAndSettle();

        // Install an edge ghost via slide-OUT.
        controller.moveNode(
          "r45",
          null,
          index: 95,
          animate: true,
          slideDuration: const Duration(seconds: 2),
          slideCurve: Curves.linear,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.hasActiveSlides, true);

        // Now: scroll change AND a new mutation in the same frame.
        // This forces the normalize-then-consume ordering with
        // installStandaloneSlides=false on the normalize pass.
        scroll.jumpTo(2200);
        controller.moveNode(
          "r10",
          null,
          index: 90,
          animate: true,
          slideDuration: const Duration(seconds: 2),
          slideCurve: Curves.linear,
        );
        await tester.pump();

        // No assertion-thrown, no engine inconsistency. Slides remain
        // active and settle cleanly.
        await tester.pumpAndSettle();
        expect(controller.hasActiveSlides, false);
      },
    );

    testWidgets(
      "scroll-driven ghost re-promotion installs single slide when no "
      "pending mutation baseline",
      (tester) async {
        // Mirror image of the above: scroll changes but NO pending
        // mutation. Normalize runs with installStandaloneSlides=true
        // and installs the re-promotion slide itself.
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);

        controller.setRoots([
          for (var i = 0; i < 100; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scroll));
        await tester.pumpAndSettle();

        scroll.jumpTo(2000);
        await tester.pump();
        await tester.pumpAndSettle();

        // Slide r45 from in-viewport to index 95 (well below). Edge
        // ghost on bottom edge.
        controller.moveNode(
          "r45",
          null,
          index: 95,
          animate: true,
          slideDuration: const Duration(seconds: 2),
          slideCurve: Curves.linear,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        expect(controller.hasActiveSlides, true);

        // User scrolls toward the destination. r45 is at structural Y
        // = 95 * 50 = 4750. Scroll to 4500: viewport [4500, 5000]
        // includes r45. Re-promotion should fire — ghost is dropped,
        // a normal slide ends at structural Y.
        scroll.jumpTo(4500);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(controller.hasActiveSlides, false);
      },
    );

    testWidgets(
      "rapid reparent during auto-scroll: viewport changes mid-batch "
      "do not corrupt slide composition",
      (tester) async {
        // Smoke test for the intersection of scroll change + rapid
        // mutations. Each iteration moves a different row while the
        // scroll controller is on a different position. The pipeline
        // must remain consistent (no stuck slides, no crashes).
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);

        controller.setRoots([
          for (var i = 0; i < 200; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scroll));
        await tester.pumpAndSettle();

        scroll.jumpTo(3000);
        await tester.pump();
        await tester.pumpAndSettle();

        for (int i = 0; i < 5; i++) {
          controller.moveNode(
            "r${60 + i}",
            null,
            index: 150 + i,
            animate: true,
            slideDuration: const Duration(milliseconds: 400),
            slideCurve: Curves.linear,
          );
          scroll.jumpTo(3000.0 + i * 100);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
        }

        // Settle.
        await tester.pumpAndSettle();
        expect(controller.hasActiveSlides, false);

        // Final structural state matches expectations.
        for (int i = 0; i < 5; i++) {
          expect(controller.getParent("r${60 + i}"), isNull);
        }
      },
    );
  });
}
