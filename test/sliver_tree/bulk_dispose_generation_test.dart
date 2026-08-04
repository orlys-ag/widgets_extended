/// Regression tests for the 2026-07-29 review, item 4: bulk-animation
/// completion must invalidate the coordinator's generation-keyed union
/// mirrors. Before the fix, `_onBulkAnimationComplete` disposed the bulk
/// group without bumping the animation generation (the op-group handler
/// pairs `removeGroup` with `_bumpAnimGen`; the bulk handler forgot), so
/// `ensureAnimatingKeys` kept returning the stale cache: every former bulk
/// member stayed marked animating — and pendingRemoval members stayed
/// marked EXITING — until an unrelated mutation happened to bump the
/// generation, which after a bulk completion may be never.
///
/// The assertions read the nid mirrors (`isAnimatingNid`/`isExitingNid`)
/// and the cached key set (`currentlyAnimatingKeys`) — deliberately NOT
/// the key-space `isAnimating`/`isExiting`, whose liveness guards and
/// direct source probes mask the staleness and pass on unfixed code.
///
/// The mid-animation sanity reads are load-bearing beyond setup proof:
/// they arm the generation-keyed cache at the post-install generation, so
/// the post-completion reads deterministically hit the stale-cache path on
/// unfixed code instead of rebuilding fresh on a never-populated cache.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

const double kRowExtent = 100.0;

Widget _harness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverTree<String, String>(
            controller: controller,
            nodeBuilder: (context, key, depth) {
              return SizedBox(
                key: ValueKey(key),
                height: kRowExtent,
                child: Text(key),
              );
            },
          ),
        ],
      ),
    ),
  );
}

TreeController<String, String> _animatedController(WidgetTester tester) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: const TreeAnimationStyle(
      expandCollapse: TreeAnimationSpec(
        duration: Duration(milliseconds: 300),
        curve: Curves.linear,
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets(
    "collapseAll completion (dismissed) clears the animating and exiting "
    "mirrors with no further mutation",
    (tester) async {
      final controller = _animatedController(tester);
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "r", data: "R")]);
      controller.setChildren("r", [
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);
      controller.expand(key: "r", animate: false);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      controller.collapseAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Setup sanity — and load-bearing cache arming (see library doc):
      // mid-animation, the bulk membership must be visible through the
      // mirrors, proving the claimed path is genuinely exercised.
      final aNid = controller.nidOf("a");
      expect(
        controller.isAnimatingNid(aNid),
        isTrue,
        reason: "setup: a must be animating mid-collapseAll",
      );
      expect(
        controller.isExitingNid(aNid),
        isTrue,
        reason: "setup: a is a pendingRemoval bulk member mid-collapseAll, "
            "so the exiting mirror must see it",
      );
      expect(
        controller.currentlyAnimatingKeys,
        isNotEmpty,
        reason: "setup: the bulk group must be animating",
      );

      await tester.pumpAndSettle();

      // Collapse hides but does not purge: the nid stays alive, so the
      // mirror reads below are meaningful (not dead-slot reads).
      expect(
        controller.visibleNodes,
        ["r"],
        reason: "setup: collapseAll must have completed",
      );

      expect(
        controller.currentlyAnimatingKeys,
        isEmpty,
        reason: "bulk completion disposed the group; no key may still "
            "report as animating",
      );
      expect(
        controller.isAnimatingNid(aNid),
        isFalse,
        reason: "the animating mirror must be invalidated when the bulk "
            "group is disposed",
      );
      expect(
        controller.isExitingNid(aNid),
        isFalse,
        reason: "the exiting mirror must be invalidated when the bulk "
            "group is disposed — a stale true here misroutes render "
            "clip/retention guards indefinitely",
      );
    },
  );

  testWidgets(
    "expandAll completion (completed) clears the animating mirror with no "
    "further mutation",
    (tester) async {
      final controller = _animatedController(tester);
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "r", data: "R")]);
      controller.setChildren("r", [
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      controller.expandAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final aNid = controller.nidOf("a");
      expect(
        controller.isAnimatingNid(aNid),
        isTrue,
        reason: "setup: a must be animating mid-expandAll",
      );
      expect(
        controller.currentlyAnimatingKeys,
        isNotEmpty,
        reason: "setup: the bulk group must be animating",
      );

      await tester.pumpAndSettle();

      expect(
        controller.visibleNodes,
        ["r", "a", "b"],
        reason: "setup: expandAll must have completed",
      );

      expect(
        controller.currentlyAnimatingKeys,
        isEmpty,
        reason: "bulk completion disposed the group; no key may still "
            "report as animating",
      );
      expect(
        controller.isAnimatingNid(aNid),
        isFalse,
        reason: "the animating mirror must be invalidated when the bulk "
            "group is disposed",
      );
    },
  );
}
