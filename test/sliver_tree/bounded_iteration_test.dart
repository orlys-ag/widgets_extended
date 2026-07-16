/// Regression tests for audit items 5.2 and 4.7.
///
/// 5.2: paint's Pass A, hit-test's Phase 2, and the semantics visitor
/// used to iterate from the first visible index to the END of the tree —
/// every below-viewport row paid a sticky check, a nid→key resolution,
/// and a children-map probe per frame (paint) and per pointer event
/// (hit-test). The loops must terminate at the viewport end (± the FLIP
/// slide overreach); semantics must iterate the mounted set.
///
/// 4.7: during slides, hit-test order must match paint z-order — sliding
/// rows first in descending |delta| (paint's topmost = first hit
/// priority) — and the clipped-away region of an entry-phantom row must
/// not steal taps from the anchor covering it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets(
    "paint / hit-test / semantics iteration counts are viewport-bounded "
    "(audit 5.2)",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      const rowCount = 500;
      controller.setRoots([
        for (int i = 0; i < rowCount; i++) TreeNode(key: "r$i", data: "R$i"),
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

      // Near the top: ~487 below-viewport rows follow the viewport.
      scrollController.jumpTo(100.0);
      await tester.pump();

      final sliver = tester.renderObject<RenderSliverTree<String, String>>(
          find.byType(SliverTree<String, String>));

      // Viewport 600px / 48px rows ≈ 13 rows; cache adds ~11 more. A
      // generous bound of 60 is still an order of magnitude below the
      // ~490 an unbounded walk pays.
      const bound = 60;

      expect(
        sliver.debugLastPaintIterationCount,
        lessThan(bound),
        reason: "Pass A must break at the viewport end instead of "
            "iterating all $rowCount visible rows per frame",
      );

      final hit = SliverHitTestResult();
      sliver.hitTest(hit, mainAxisPosition: 300.0, crossAxisPosition: 100.0);
      expect(
        sliver.debugLastHitTestIterationCount,
        lessThan(bound),
        reason: "hit-test Phase 2 must break past the hit offset instead "
            "of iterating all $rowCount visible rows per pointer event",
      );

      int visited = 0;
      sliver.visitChildrenForSemantics((_) => visited++);
      expect(
        sliver.debugLastSemanticsIterationCount,
        lessThan(bound),
        reason: "the semantics visitor must iterate the mounted set, not "
            "the full visible order",
      );
      expect(visited, greaterThan(0),
          reason: "sanity: semantics still visits the mounted rows");
    },
  );

  testWidgets(
    "mid-slide overlapping rows: tap routes to the visually-top row "
    "(audit 4.7)",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);

      String? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => tapped = key,
                      child: SizedBox(height: 48, child: Text(key)),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Move a to the end: post-move order [b, c, a].
      //   a: baseline 0   -> structural 96 (delta -96, decaying)
      //   b: baseline 48  -> structural 0  (delta +48, decaying)
      //   c: baseline 96  -> structural 48 (delta +48, decaying)
      controller.moveNode(
        "a",
        null,
        index: 2,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // At t=0.5: a painted [48, 96) (|delta| 48 — painted LAST, on
      // top); c painted [72, 120) (|delta| 24). The overlap [72, 96)
      // visually shows a.
      expect(controller.getSlideDelta("a"), closeTo(-48.0, 2.0),
          reason: "setup: a mid-slide");
      expect(controller.getSlideDelta("c"), closeTo(24.0, 2.0),
          reason: "setup: c mid-slide");

      await tester.tapAt(const Offset(200, 80));
      await tester.pump();

      expect(
        tapped,
        "a",
        reason: "the tap point (y=80) is covered by both sliding rows; "
            "paint puts a (larger |delta|) on top, so the hit must route "
            "to a — not to the structurally-earlier c",
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "entry-phantom occluded region routes taps to the anchor (audit 4.7)",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // p (collapsed) hides x; q is a visible root below.
      controller.setRoots([
        const TreeNode(key: "p", data: "P"),
        const TreeNode(key: "q", data: "Q"),
      ]);
      controller.setChildren("p", [const TreeNode(key: "x", data: "X")]);

      String? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => tapped = key,
                      child: SizedBox(height: 48, child: Text(key)),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Reparent the HIDDEN x to root level (entry-phantom: x slides out
      // from behind p, clipped so p occludes it until it emerges).
      controller.moveNode(
        "x",
        null,
        index: 2,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Mid-emergence, x's sliding box still overlaps p's row band, but
      // that portion is clipped away — p is what the user sees at y=24.
      expect(controller.isVisible("x"), isTrue,
          reason: "setup: x is emerging (visible, mid-slide)");
      expect(controller.getSlideDelta("x"), isNot(0.0),
          reason: "setup: x must still be sliding");

      await tester.tapAt(const Offset(200, 24));
      await tester.pump();

      expect(
        tapped,
        "p",
        reason: "the tap lands inside p's row band where x's box is "
            "clipped away — the visible row (p) must receive it, not the "
            "occluded portion of the emerging x",
      );

      await tester.pumpAndSettle();
    },
  );
}
