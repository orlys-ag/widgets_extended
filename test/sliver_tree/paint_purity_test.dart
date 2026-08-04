/// Regression for R018 + R019: paint must not mutate layout state.
///
/// Before the fix, paint() mutated `_phantomExitGhosts`,
/// `_phantomClipAnchors`, and `_composer.ghosts` mid-iteration. The
/// fix moves all cleanup to a Step 0a/0b at the start of performLayout
/// (via `_pruneSettledPhantomExitGhosts` and `_composer.ghosts.pruneSettled`)
/// so paint stays read-only.
///
/// Tests:
///  1. After a slide settles, the next layout's Step 0a/0b drops the
///     dead ghost entries (without paint having had to mutate them).
///  2. Multiple paints against the same layout (forced via
///     `markNeedsPaint`) leave the ghost-count snapshots identical.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Widget _harness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (_, key, depth) => SizedBox(
                key: ValueKey("row-$key"),
                height: 48,
                child: Padding(
                  padding: EdgeInsets.only(left: depth * 20.0),
                  child: Text(key),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    "settled ghosts are reaped by the next layout's Step 0a",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 200), curve: Curves.linear)),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
      ]);
      controller.setChildren("A", [
        const TreeNode(key: "Y", data: "Y"),
        const TreeNode(key: "Y2", data: "Y2"),
      ]);
      controller.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);
      controller.expand(key: "A", animate: false);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      // Reparent Y under (collapsed) B with animation. Ghost active.
      controller.moveNode("Y", "B", animate: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final sliver = tester.renderObject<RenderSliverTree<String, String>>(
          find.byType(SliverTree<String, String>));
      expect(
        sliver.debugPhantomExitGhostCount,
        greaterThan(0),
        reason: "Test setup: phantom-exit ghost active mid-slide",
      );

      // Let the slide settle fully.
      await tester.pumpAndSettle();

      // Step 0a should have reaped the settled ghost entries on the
      // layout that ran after the slide settled. Paint never mutated
      // them — layout did.
      expect(
        sliver.debugPhantomExitGhostCount,
        0,
        reason: "Step 0a (_pruneSettledPhantomExitGhosts) should have "
            "dropped the settled ghost",
      );
    },
  );

  testWidgets(
    "repeated paints do not mutate ghost counts (paint is pure)",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 200), curve: Curves.linear)),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
      ]);
      controller.setChildren("A", [
        const TreeNode(key: "Y", data: "Y"),
        const TreeNode(key: "Y2", data: "Y2"),
      ]);
      controller.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);
      controller.expand(key: "A", animate: false);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      // Stage an active ghost mid-slide.
      controller.moveNode("Y", "B", animate: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final sliver = tester.renderObject<RenderSliverTree<String, String>>(
          find.byType(SliverTree<String, String>));

      // Capture counts before forcing extra paints.
      final phantomBefore = sliver.debugPhantomExitGhostCount;

      // Force two additional paint passes against the same layout via
      // markNeedsPaint. If paint mutated state, the counts would
      // change between snapshots.
      sliver.markNeedsPaint();
      await tester.pump(Duration.zero);
      final phantomAfterFirst = sliver.debugPhantomExitGhostCount;

      sliver.markNeedsPaint();
      await tester.pump(Duration.zero);
      final phantomAfterSecond = sliver.debugPhantomExitGhostCount;

      expect(phantomAfterFirst, phantomBefore,
          reason: "First repaint must not mutate phantom-exit count");
      expect(phantomAfterSecond, phantomBefore,
          reason: "Second repaint must not mutate phantom-exit count");

      // Settle slides so the tester's ticker-disposal verification at
      // end of test passes.
      await tester.pumpAndSettle();
    },
  );
}
