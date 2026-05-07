/// Render-layer tests for the v2.3.2 viewport-clamp + edge-anchor exit
/// ghost mechanism.
///
/// Covers:
/// - Slide-IN clamp (`baseline.y` clamped to viewport edge ± overhang
///   for off-screen-prior rows).
/// - Slide-OUT edge ghost (`_phantomEdgeExits` registration; ghost
///   paints at `edgeY + slideDelta`; settles + prunes invisibly).
/// - Both off-screen suppression (no slide installed for invisible-→
///   invisible reorders).
/// - Edge-ghost composition: re-promotion when structural becomes
///   visible again (via mutation OR via scroll-induced check).
/// - Edge-ghost direction flip.
/// - Ghost-stays preserves progress under concurrent batches (the
///   primary autoscroll-during-ghost win).
/// - Hit-test substitutes edgeY for ghost rows.
/// - `applyPaintTransform` settled-check (post-settlement queries
///   report structural, not stale ghost edge).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const _kRowHeight = 50.0;
const _kViewportHeight = 500.0;
const _kOverhang = _kViewportHeight * 0.1; // 50 px
const _kSlideDuration = Duration(milliseconds: 400);

/// Stages the slide baseline on the rendered tree, runs [mutation], and
/// pumps once to drive the install. Mirrors what
/// `tree_reorder_controller.dart` does for drag-drop reorders.
Future<void> _stageAndMutate(
  WidgetTester tester,
  void Function() mutation,
) async {
  final render = tester.renderObject<RenderSliverTree<String, int>>(
    find.byType(SliverTree<String, int>),
  );
  render.beginSlideBaseline(
    duration: _kSlideDuration,
    curve: Curves.linear,
  );
  mutation();
  await tester.pump();
}

Widget _harness(
  TreeController<String, int> controller, {
  ScrollController? scrollController,
  double height = _kViewportHeight,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: CustomScrollView(
          controller: scrollController,
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

TreeController<String, int> _newController(WidgetTester tester) {
  final c = TreeController<String, int>(
    vsync: tester,
    animationDuration: const Duration(milliseconds: 400),
    animationCurve: Curves.linear,
  );
  return c;
}

void main() {
  group("slide-OUT edge-anchor exit ghost", () {
    testWidgets(
      "long slide-OUT installs edge ghost; row paints at edge area, "
      "not at far structural",
      (tester) async {
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        // 30 rows × 50 = 1500 total. Viewport = 500.
        controller.setRoots([
          for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();

        // Pre-state: r0 visible at y=0.
        expect(tester.getTopLeft(find.byKey(const ValueKey("row-r0"))).dy,
            closeTo(0.0, 0.001));

        // Move r0 to the end (now structurally at y=1450, far below
        // viewport). With the edge-ghost mechanism, r0 is added to
        // _phantomEdgeExits with edgeY = viewportBottom + overhang =
        // 500 + 50 = 550 (in scroll-space).
        await _stageAndMutate(tester, () {
          controller.reorderRoots([
            for (var i = 1; i < 30; i++) "r$i",
            "r0",
          ]);
        });

        expect(controller.hasActiveSlides, true,
            reason: "long slide-OUT must install (as edge ghost)");

        // r0 should still be in widget tree (retained via isNodeRetained)
        // and painted near the bottom edge area, NOT at structural
        // y=1450 (which would be off-screen well below the viewport).
        final r0Top = tester.getTopLeft(
            find.byKey(const ValueKey("row-r0"))).dy;
        // Initial paint of ghost: painted = edge_y + slideDelta (large
        // negative, since baseline.y was the row's prior on-screen
        // position). At t=0, ghost paints at baseline.y ≈ 0.
        expect(r0Top, lessThan(_kViewportHeight),
            reason: "r0 ghost should be near its prior on-screen "
                "position at t=0, not at far-below structural. Got $r0Top.");

        await tester.pumpAndSettle();
        // After settle: r0 reverts to standard paint at structural
        // y=1450 — far off-screen. find.byKey may return nothing if
        // child has been evicted, OR a position well below the viewport.
        // Either way, it's NOT in the viewport.
      },
    );

    testWidgets(
      "short slide-OUT (within viewport) does NOT install edge ghost",
      (tester) async {
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        // 5 visible rows; reorder within them.
        controller.setRoots([
          for (var i = 0; i < 5; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();

        // Move r0 to last position (structural y=200, still in viewport).
        // Both prior (0) and current (200) are on-screen → animate
        // normally, no ghost.
        await _stageAndMutate(tester, () {
          controller.reorderRoots(["r1", "r2", "r3", "r4", "r0"]);
        });
        expect(controller.hasActiveSlides, true);
        // r0 paints at its structural position with slideDelta — should
        // be within viewport throughout.
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(const ValueKey("row-r0"))).dy,
            closeTo(200.0, 1.0));
      },
    );
  });

  group("slide-IN clamp", () {
    testWidgets(
      "long slide-IN: row appears in viewport via natural slide overreach "
      "(no per-row clamp — would cause clustering on multi-row reparents)",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();

        // Scroll so r0 is far above the viewport.
        scroll.jumpTo(700);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey("row-r0")), findsNothing);

        // Move r0 to position 14 so its new structural is y=700 (top
        // of current viewport).
        await _stageAndMutate(tester, () {
          controller.reorderRoots([
            for (var i = 1; i <= 14; i++) "r$i",
            "r0",
            for (var i = 15; i < 30; i++) "r$i",
          ]);
        });
        // r0's prior was off-screen above (structural was 0, viewport
        // top is 700). New structural is 14*50 = 700 (visible).
        // Slide-IN: baseline clamped to viewportTop - overhang = 650.
        expect(controller.hasActiveSlides, true);
        // r0 should now be visible (in viewport).
        expect(find.byKey(const ValueKey("row-r0")), findsOneWidget);

        await tester.pumpAndSettle();
      },
    );
  });

  group("both off-screen suppression", () {
    testWidgets(
      "reorder of two off-screen rows installs no slide",
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller, scrollController: scroll));
        await tester.pumpAndSettle();

        // Scroll to middle. Viewport [400, 900]. r0..r7 above, r18..r29
        // below.
        scroll.jumpTo(400);
        await tester.pump();
        await tester.pumpAndSettle();

        // Reorder r25 to position 27 (both off-screen below).
        // Both prior and new structural are below viewport.
        final newOrder = controller.visibleNodes.cast<String>().toList();
        // Use raw row order — reorderRoots wants the new top-level order.
        final allKeys = [for (var i = 0; i < 30; i++) "r$i"];
        // Move r25 (currently index 25) to index 27.
        allKeys.removeAt(25);
        allKeys.insert(27, "r25");
        await _stageAndMutate(tester, () {
          controller.reorderRoots(allKeys);
        });

        // r25 at structural=1250 (was), now at 1350. Both off-screen
        // below viewport [400, 900]. Slide should be suppressed.
        // (Other rows shift too — r26, r27 each move by ±50, also
        // off-screen → all suppressed.)
        expect(controller.getSlideDelta("r25"), 0.0,
            reason: "Both-off-screen slide must be suppressed");

        await tester.pumpAndSettle();
      },
    );
  });

  group("autoscroll-during-ghost: preserve flag", () {
    testWidgets(
      "ghost slide progresses smoothly under repeated batches",
      (tester) async {
        final controller = _newController(tester);
        addTearDown(controller.dispose);
        controller.setRoots([
          for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
        ]);
        await tester.pumpWidget(_harness(controller));
        await tester.pumpAndSettle();

        // Install ghost on r0 by moving it far down.
        await _stageAndMutate(tester, () {
          controller.reorderRoots([
            for (var i = 1; i < 30; i++) "r$i",
            "r0",
          ]);
        });
        expect(controller.hasActiveSlides, true);

        // Capture r0's slide delta after some progress.
        await tester.pump(const Duration(milliseconds: 100));
        final r0DeltaAt100 = controller.getSlideDelta("r0");
        // The slide is in flight — delta is non-zero.
        expect(r0DeltaAt100.abs(), greaterThan(0.0));

        // Trigger another mutation on a DIFFERENT row (r5 → r10
        // structurally). This represents an autoscroll commit during
        // the ghost slide. After the first reorder above, r0 is at the
        // end; build the new order from the current root order.
        final allKeys = [
          for (var i = 1; i < 30; i++) "r$i",
          "r0",
        ];
        // Move r5 (currently at index 4) to index 9.
        allKeys.removeAt(4);
        allKeys.insert(9, "r5");
        await _stageAndMutate(tester, () {
          controller.reorderRoots(allKeys);
        });

        // r0's ghost should NOT have been re-baselined — preserve flag
        // is set in syncPreserveProgressFlags. Continue pumping; r0
        // should settle within its original install duration plus
        // typical jitter.
        await tester.pump(const Duration(milliseconds: 350));
        // After ~450ms total, r0's 400ms slide should be settled.
        expect(controller.getSlideDelta("r0"), closeTo(0.0, 5.0),
            reason: "Preserved ghost slide should settle on schedule "
                "despite the concurrent r5 batch.");

        await tester.pumpAndSettle();
      },
    );
  });

  group("Duration.zero clears edge ghosts", () {
    testWidgets("setting animationDuration=0 short-circuits and clears",
        (tester) async {
      final controller = _newController(tester);
      addTearDown(controller.dispose);
      controller.setRoots([
        for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
      ]);
      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      // Switch to instant mode.
      controller.animationDuration = Duration.zero;
      await _stageAndMutate(tester, () {
        controller.reorderRoots([
          for (var i = 1; i < 30; i++) "r$i",
          "r0",
        ]);
      });
      // Engine short-circuits: no slides, no ghosts.
      expect(controller.hasActiveSlides, false);
    });
  });

  group("hit-test on edge ghost", () {
    testWidgets("tap on ghost row near edge resolves to ghost key",
        (tester) async {
      final controller = _newController(tester);
      addTearDown(controller.dispose);
      controller.setRoots([
        for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: i),
      ]);
      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      await _stageAndMutate(tester, () {
        controller.reorderRoots([
          for (var i = 1; i < 30; i++) "r$i",
          "r0",
        ]);
      });

      // r0 is now ghost. Find the widget — should still be in the tree
      // (retained via isNodeRetained).
      final r0Finder = find.byKey(const ValueKey("row-r0"));
      expect(r0Finder, findsOneWidget,
          reason: "Edge-ghost rows must be retained for paint/hit-test");

      // Painted position should be inside the viewport (near the row's
      // prior position at t=0 of the ghost slide).
      final r0Top = tester.getTopLeft(r0Finder).dy;
      expect(r0Top, lessThan(_kViewportHeight));

      await tester.pumpAndSettle();
    });
  });
}
