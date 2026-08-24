/// Perf pin for issue 12 of the 2026-08-21 review: a pinned sticky header
/// whose own row sits outside the cache region rebuilt an O(N_visible)
/// cumulative on every scroll frame.
///
/// The sticky block force-mounts the pinned header's row, and the
/// parentData refresh loop treats a mounted-but-off-cache row as needing
/// an offset it cannot read from the per-nid array, so it built a fresh
/// prefix sum over the whole visible order. For a 100k-node tree that is
/// 100k extent resolutions per scroll frame, which is the steady state
/// while scrolling anywhere inside a large pinned subtree.
///
/// In fact the per-nid array IS authoritative on any frame whose Pass 1
/// took a non-bulk branch (each of them writes the full visible prefix)
/// or whose sticky block ran the full recompute. The exception, found by
/// running the freshness assert across the suite, is a frame that STARTS
/// on the bulk fast path and leaves it mid-frame: Pass 2 then rewrites
/// only the slots at or after the first changed row. The render object
/// tracks which case it is in and reads the slot directly when it can.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("scrolling under a pinned off-cache header builds no "
      "cumulative", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      const TreeNode(key: "root", data: "ROOT"),
      for (int i = 0; i < 2000; i++) TreeNode(key: "r$i", data: "R$i"),
    ]);
    controller.setChildren("root", [
      for (int i = 0; i < 400; i++) TreeNode(key: "k$i", data: "K$i"),
    ]);
    controller.expand(key: "root", animate: false);

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverTree<String, String>(
                controller: controller,
                maxStickyDepth: 1,
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

    // Deep inside the pinned subtree: "root" is pinned while its own row
    // is thousands of pixels above the viewport, so the sticky block has
    // to force-mount an off-cache row on every frame.
    scrollController.jumpTo(5000);
    await tester.pump();
    expect(
      render.debugLastPaintedStickyKeys,
      contains("root"),
      reason: "setup: the header is pinned with its row far off-cache",
    );

    var builds = 0;
    for (int frame = 0; frame < 20; frame++) {
      scrollController.jumpTo(scrollController.offset + 10);
      await tester.pump();
      builds += render.debugLastParentDataCumulativeBuilds;
    }
    expect(
      builds,
      0,
      reason: "each of these frames used to rebuild a prefix sum over "
          "every visible row",
    );
  });

  testWidgets("the pinned header and the rows below it stay correctly "
      "positioned while scrolling", (tester) async {
    // Correctness control for reading the per-nid slot directly: the
    // offsets the refresh loop writes must match what the cumulative
    // would have produced, or rows paint at the wrong y.
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      const TreeNode(key: "root", data: "ROOT"),
      for (int i = 0; i < 200; i++) TreeNode(key: "r$i", data: "R$i"),
    ]);
    controller.setChildren("root", [
      for (int i = 0; i < 100; i++) TreeNode(key: "k$i", data: "K$i"),
    ]);
    controller.expand(key: "root", animate: false);

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverTree<String, String>(
                controller: controller,
                maxStickyDepth: 1,
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

    for (final offset in [1000.0, 2000.0, 3000.0]) {
      scrollController.jumpTo(offset);
      await tester.pump();
      // The row at this offset is the one the visible order puts there.
      final index = (offset / 48).floor();
      final key = controller.visibleNodes[index];
      // No `.first`: the finder matches exactly one row at these
      // offsets, and letting an ambiguity throw is better than silently
      // measuring whichever copy came first (the pinned header paints a
      // second time in its band).
      final rect = tester.getRect(find.text(key));
      expect(
        rect.top,
        closeTo(index * 48.0 - offset, 0.01),
        reason: "$key must paint at its structural offset",
      );
    }
  });

  testWidgets("the pinned header's subtree-bottom fallback stops once the "
      "pin is saturated (L25.3)", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: const TreeAnimationStyle(
        expandCollapse: TreeAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      const TreeNode(key: "root", data: "ROOT"),
      const TreeNode(key: "other", data: "OTHER"),
    ]);
    controller.setChildren("root", [
      for (int i = 0; i < 400; i++) TreeNode(key: "k$i", data: "K$i"),
    ]);
    controller.setChildren("other", [
      for (int i = 0; i < 5; i++) TreeNode(key: "o$i", data: "O$i"),
    ]);
    controller.expand(key: "root", animate: false);

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverTree<String, String>(
                controller: controller,
                maxStickyDepth: 1,
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

    scrollController.jumpTo(5000);
    await tester.pump();
    expect(
      render.debugLastPaintedStickyKeys,
      contains("root"),
      reason: "setup: the header is pinned deep inside its subtree",
    );

    // A per-node animation elsewhere invalidates the precompute, so every
    // layout during it takes the fallback walk for the pinned candidate.
    controller.expand(key: "other", animate: true);
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      controller.hasActiveAnimations,
      isTrue,
      reason: "setup: the expansion must still be running",
    );
    final iterationsBefore = render.debugStickyFallbackIterationCount;
    final layoutsBefore = render.debugPerformLayoutCount;
    await tester.pump(const Duration(milliseconds: 16));
    final layouts = render.debugPerformLayoutCount - layoutsBefore;
    final delta = render.debugStickyFallbackIterationCount - iterationsBefore;
    expect(layouts, 1, reason: "setup: exactly one layout in the frame");
    expect(delta, greaterThan(0), reason: "setup: the fallback walk ran");
    // Two probes per layout (the sticky block's force-create pass and the
    // final compute both call `computeStickyHeaders`), each walking 105
    // children: the running bottom starts at the root's 48 and grows 48
    // per child until it reaches the saturation line scrollOffset (5000)
    // + stackTop (0) + extent (48) = 5048. Before L25.3 each walk visited
    // all 400 children (800 per layout).
    expect(
      delta,
      210,
      reason: "the walk must stop once the running bottom passes the "
          "saturation line instead of visiting all 400 children",
    );
    await tester.pumpAndSettle();
  });
}
