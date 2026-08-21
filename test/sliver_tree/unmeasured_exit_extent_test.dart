/// Regression: an exiting row that has never been measured must animate out
/// from its resting (estimated) extent, not snap to zero.
///
/// `_startStandaloneExitAnimation` seeded `startExtent` with
/// `_fullExtentOf(key) ?? 0.0`. A visible row that has never been laid out
/// has no measured extent, so its exit started at zero: layout sized the row
/// at [TreeController.defaultExtent] one frame and at nothing the next.
/// Every other consumer of an unmeasured row's extent resolves to the
/// estimate (`getCurrentExtent` for non-animating rows, the collapse group's
/// target extent, the exit's own speed-multiplier `full`), so the exit
/// install was the one place the visual truth jumped.
///
/// Real-world path (the My Work example): drill into a section via a sync
/// diff, switch back (the removed sections re-enter ABOVE the viewport with
/// fresh nids and are never rebuilt), then drill in again. The re-added rows
/// exited at extent zero and everything below leapt up by their combined
/// estimated extent in a single frame, which read as the incoming section
/// header snapping to the top of the viewport instead of sliding there.
library;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/tree_sync_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

const Duration kExit = Duration(milliseconds: 300);

void main() {
  TreeController<String, String> createController(WidgetTester tester) {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.uniform(
        duration: kExit,
        curve: Curves.linear,
      ),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// Setup sanity shared by both tests: the keys are visible (the animated
  /// remove path requires order membership) and genuinely unmeasured (no
  /// widget ever laid them out), so the controller's only truth for their
  /// height is the estimate, which is exactly what a layout pass would
  /// have rendered them at.
  double assertUnmeasuredAndResting(
    TreeController<String, String> controller,
    List<String> keys,
  ) {
    expect(controller.hasActiveAnimations, isFalse);
    expect(controller.visibleNodes, containsAll(keys));
    final resting = controller.getCurrentExtent(keys.first);
    expect(resting, greaterThan(0.0));
    for (final key in keys) {
      expect(
        controller.getMeasuredExtent(key),
        isNull,
        reason: "$key must be unmeasured for this repro to bite",
      );
      expect(controller.getCurrentExtent(key), resting);
    }
    return resting;
  }

  testWidgets("remove: a never-measured row exits from its resting extent", (
    tester,
  ) async {
    final controller = createController(tester);
    controller.setRoots([
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "keep", data: "K"),
    ]);
    controller.setChildren("a", [
      TreeNode(key: "a1", data: "A1"),
      TreeNode(key: "a2", data: "A2"),
    ]);
    controller.expand(key: "a", animate: false);
    await tester.pump();
    await tester.pump(kExit + const Duration(milliseconds: 16));

    final resting = assertUnmeasuredAndResting(controller, [
      "a",
      "a1",
      "a2",
    ]);

    controller.remove(key: "a");

    // Setup sanity: the animated path was taken for the whole subtree.
    expect(controller.isExiting("a"), isTrue);
    expect(controller.isExiting("a1"), isTrue);
    expect(controller.isExiting("a2"), isTrue);

    // EXPECTED: the exit starts where layout was rendering the row the
    // frame before, so the block's extent is continuous at install.
    // Unfixed, startExtent is 0.0 and both rows report zero here.
    expect(
      controller.getCurrentExtent("a1"),
      moreOrLessEquals(resting),
      reason: "an exit must start at the row's resting extent",
    );
    expect(controller.getCurrentExtent("a"), moreOrLessEquals(resting));

    // Mid-animation the extent is genuinely between resting and zero:
    // the row shrinks, it does not hold and vanish.
    await tester.pump();
    await tester.pump(kExit ~/ 2);
    final mid = controller.getCurrentExtent("a1");
    expect(mid, lessThan(resting));
    expect(mid, greaterThan(0.0));

    // And the subtree still purges at exit end.
    await tester.pump(kExit);
    await tester.pump();
    expect(controller.getNodeData("a"), isNull);
    expect(controller.getNodeData("a1"), isNull);
    expect(controller.visibleNodes, ["keep"]);
  });

  testWidgets(
    "syncRoots: a removed root's never-measured rows exit from their "
    "resting extents",
    (tester) async {
      final controller = createController(tester);
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(sync.dispose);

      List<TreeNode<String, String>> childrenOf(String key) {
        return switch (key) {
          "a" => [
            TreeNode(key: "a1", data: "A1"),
            TreeNode(key: "a2", data: "A2"),
          ],
          "b" => [TreeNode(key: "b1", data: "B1")],
          _ => const [],
        };
      }

      sync.syncRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ], childrenOf: childrenOf);
      controller.expand(key: "a", animate: false);
      await tester.pump();
      await tester.pump(kExit + const Duration(milliseconds: 16));

      final resting = assertUnmeasuredAndResting(controller, [
        "a",
        "a1",
        "a2",
      ]);

      // The diff that removes root "a" (the See-all drill-in shape).
      sync.syncRoots([
        TreeNode(key: "b", data: "B"),
      ], childrenOf: childrenOf);

      // Setup sanity: the sync removal is animated.
      expect(controller.isExiting("a"), isTrue);
      expect(controller.isExiting("a1"), isTrue);

      // EXPECTED: same contract through the sync layer. Unfixed, the
      // never-measured rows report zero from the first frame and the
      // content below them leaps up by the whole block in one frame.
      expect(
        controller.getCurrentExtent("a1"),
        moreOrLessEquals(resting),
        reason: "a sync-removed unmeasured row must exit from its estimate",
      );
      expect(controller.getCurrentExtent("a"), moreOrLessEquals(resting));

      await tester.pump();
      await tester.pump(kExit + kExit);
      await tester.pump();
      expect(controller.getNodeData("a"), isNull);
      expect(controller.liveRootKeys, ["b"]);
    },
  );
}
