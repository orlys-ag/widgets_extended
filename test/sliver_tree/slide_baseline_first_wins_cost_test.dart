/// Perf pin for issue 7 of the 2026-08-21 review: `beginSlideBaseline`
/// took its O(visible) snapshot BEFORE asking whether a baseline was
/// already staged.
///
/// Staging is first-wins: `SlideBaselineSlot.stage` returns false and
/// keeps the existing baseline when one is pending, because only the
/// first capture holds the truly-painted positions. The snapshot that
/// fed the refused call was still computed, so K animated mutations in
/// one frame walked the visible order K times and allocated K maps to
/// use one. Measured on 4000 rows, 400 batched moves: 465ms against
/// 158ms for the same batch with `animate: false`.
///
/// `moveNode` stages even under a zero `reorderSlide` spec, deliberately
/// (other families' in-flight slides re-base across the mutation), so a
/// disabled style paid the same cost.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("a batch of K animated moves takes ONE staging snapshot", (
    tester,
  ) async {
    final controller = TreeController<String, String>(vsync: tester);
    addTearDown(controller.dispose);
    controller.setRoots([
      for (int i = 0; i < 60; i++) TreeNode(key: "r$i", data: "R$i"),
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
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final render = tester.renderObject<RenderSliverTree<String, String>>(
      find.byType(SliverTree<String, String>),
    );

    // Count only the STAGING snapshots: the post-mutation snapshot the
    // consume path takes runs during the next layout, which has not
    // happened yet when the batch returns.
    render.debugSnapshotVisibleOffsetsCount = 0;
    controller.runBatch(() {
      for (int i = 0; i < 12; i++) {
        controller.moveNode("r$i", null, index: 59 - i, animate: true);
      }
    });
    expect(
      render.debugSnapshotVisibleOffsetsCount,
      1,
      reason: "first-wins keeps the FIRST baseline, so the other 11 "
          "snapshots were computed only to be thrown away",
    );

    await tester.pumpAndSettle();
  });

  testWidgets("the batch still installs slides from the first baseline", (
    tester,
  ) async {
    // Correctness control for the early return: skipping the snapshot
    // must not skip the SLIDE. The rows that moved still animate from
    // their pre-batch painted positions.
    final controller = TreeController<String, String>(vsync: tester);
    addTearDown(controller.dispose);
    controller.setRoots([
      for (int i = 0; i < 20; i++) TreeNode(key: "r$i", data: "R$i"),
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
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.runBatch(() {
      controller.moveNode("r0", null, index: 5, animate: true);
      controller.moveNode("r1", null, index: 9, animate: true);
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      controller.hasActiveFlipSlides,
      isTrue,
      reason: "the staged baseline must still be consumed into slides",
    );
    expect(controller.getSlideDelta("r0") != 0.0, isTrue);

    await tester.pumpAndSettle();
    expect(controller.hasActiveFlipSlides, isFalse);
    // r0 lands at live index 5, then r1's move pulls it one slot left.
    expect(controller.rootKeys.indexOf("r0"), 4);
    expect(controller.rootKeys.indexOf("r1"), 9);
  });

  testWidgets("a single animated move still takes its one snapshot", (
    tester,
  ) async {
    // Control: the early return must not suppress the FIRST stage.
    final controller = TreeController<String, String>(vsync: tester);
    addTearDown(controller.dispose);
    controller.setRoots([
      for (int i = 0; i < 20; i++) TreeNode(key: "r$i", data: "R$i"),
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
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final render = tester.renderObject<RenderSliverTree<String, String>>(
      find.byType(SliverTree<String, String>),
    );

    render.debugSnapshotVisibleOffsetsCount = 0;
    controller.moveNode("r0", null, index: 5, animate: true);
    expect(render.debugSnapshotVisibleOffsetsCount, 1);

    await tester.pumpAndSettle();
  });
}
