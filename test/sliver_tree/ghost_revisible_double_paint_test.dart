/// Regression test for audit item 4.5: an exit ghost whose key becomes
/// visible again through a NON-staging mutation must be dropped by the
/// next LAYOUT (Step 0a), not only by the slide-baseline consume path.
///
/// The "ghost became visible again" prune used to run only inside
/// `_consumeSlideBaselineIfAny` — i.e. only when a mutation staged a
/// baseline. `expand()` stages one when a revealed row has a live slide
/// (`_stageSlideBaselineForBaseChange`), but that gate reads the row's
/// OWN slide delta — and an ADJACENT exit ghost has zero own-delta by
/// construction (its baseline already equals the destination's settled
/// position; only its ANCHOR is still sliding up to absorb it). Expanding
/// the destination then re-promotes the key to `visibleNodes` with no
/// consume in sight: Pass A paints the row structurally AND Pass A.5
/// keeps painting the same RenderBox anchor-relative until the anchor
/// settles — two copies per frame.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets(
    "expand(destination, animate: false) mid-absorption drops the "
    "re-promoted ADJACENT ghost at the next layout",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 1000),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // Layout: A=0, Y=48, B=96, C=144. Moving Y into B makes B settle
      // at Y's old slot (48): Y's baseline equals the destination's
      // settled top -> ADJACENT ghost with zero own slide delta.
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
        const TreeNode(key: "C", data: "C"),
      ]);
      controller.setChildren("A", [const TreeNode(key: "Y", data: "Y")]);
      controller.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);
      controller.expand(key: "A", animate: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return RepaintBoundary(
                      child: SizedBox(
                        key: ValueKey("row-$key"),
                        height: 48,
                        child: Text(key),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      controller.moveNode(
        "Y",
        "B",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 1000),
        slideCurve: Curves.linear,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final sliver = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );
      expect(controller.isVisible("Y"), isFalse,
          reason: "setup: Y must be mid-absorption (hidden ghost)");
      expect(controller.getSlideDelta("Y"), 0.0,
          reason: "setup: Y must be an ADJACENT ghost (zero own slide — "
              "only its anchor B is still sliding)");
      expect(controller.getSlideDelta("B"), isNot(0.0),
          reason: "setup: anchor B must still be sliding up to absorb Y");
      expect(sliver.debugPhantomExitGhostCount, greaterThan(0),
          reason: "setup: Y must be registered as a phantom-exit ghost");

      // Non-staging re-promotion: no revealed row carries a live slide
      // (Y's own delta is 0), so expand() stages NO baseline and no
      // consume will run. Only a layout-time (Step 0a) prune can drop
      // the ghost entry.
      controller.expand(key: "B", animate: false);
      await tester.pump();
      expect(controller.isVisible("Y"), isTrue,
          reason: "setup: Y is visible again through the expand");

      expect(
        sliver.debugPhantomExitGhostCount,
        0,
        reason: "a ghost whose key became visible again must be dropped "
            "by the next layout regardless of whether the mutation staged "
            "a slide baseline — otherwise Pass A (structural) and Pass "
            "A.5 (anchor-relative) both paint the same RenderBox until "
            "the anchor settles",
      );

      // And the row must paint exactly once per frame while the anchor's
      // slide finishes (a double-painted RepaintBoundary would throw).
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final exception = tester.takeException();
        expect(exception, isNull,
            reason: "frame $i: single paint expected (got: $exception)");
      }

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("row-Y")), findsOneWidget);
    },
  );
}
