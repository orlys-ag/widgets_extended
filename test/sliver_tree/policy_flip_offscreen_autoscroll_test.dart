/// Repro: a `canReorder` refusal goes unenforced while a drag autoscrolls.
///
/// This is the scenario the enforcement was written for, and the first
/// attempt missed it entirely by living in `updateDrag`. A finger parked
/// in the autoscroll edge zone produces NO pointer events, so `updateDrag`
/// never fires; autoscroll drives the scroll position instead, which
/// re-resolves through the controller's funnel. Meanwhile the dragged row
/// leaves the cache region and is held mounted by the drag pin without
/// being rebuilt, so the widget layer's build-time and deactivate
/// backstops are both mute.
///
/// With enforcement in the wrong place, all three go quiet at once and the
/// list keeps scrolling under a drag the policy has forbidden.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets("a refusal ends an autoscrolling drag with no pointer move", (
    tester,
  ) async {
    final locked = <String>{};
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(<TreeNode<String, String>>[
      for (int i = 0; i < 100; i++) TreeNode(key: "n$i", data: "n$i"),
    ]);
    final reorder = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
      canReorder: (key) {
        return !locked.contains(key);
      },
      onReorder: (key, newParent, index) {},
    );
    addTearDown(() {
      reorder.dispose();
      tree.dispose();
    });

    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: CustomScrollView(
              controller: scroll,
              slivers: <Widget>[
                SliverReorderableTree<String, String>(
                  controller: tree,
                  reorderController: reorder,
                  showDragProxy: false,
                  nodeBuilder: (context, key, depth) {
                    return TreeDelayedDragHandle(
                      child: SizedBox(
                        key: ValueKey("row-$key"),
                        height: 50,
                        child: Text(key),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Grab the first row, then park the finger in the bottom edge zone so
    // autoscroll takes over. No further pointer events are sent.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey("row-n0"))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(const Offset(400.0, 292.0));
    await tester.pump();

    expect(reorder.isDragging, isTrue, reason: "setup: the drag is running");

    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // Setup sanity, and the whole point: the list really did autoscroll,
    // so the dragged row is far outside the cache region and no longer
    // being rebuilt. Both widget-side backstops are mute from here.
    final scrolled = scroll.position.pixels;
    expect(
      scrolled,
      greaterThan(400.0),
      reason: "setup: autoscroll must have carried the row off-screen",
    );
    // Still MOUNTED, because the drag pin retains it: that is exactly why
    // the widget backstops cannot see a policy flip here. Off-screen is
    // asserted by geometry, not by absence.
    expect(
      tester.getRect(find.byKey(const ValueKey("row-n0"))).bottom,
      lessThan(0.0),
      reason: "setup: the pinned row must be above the viewport",
    );
    expect(reorder.isDragging, isTrue);

    // Refuse the dragged row. No pointer event, no widget rebuild.
    locked.add("n0");
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      reorder.isDragging,
      isFalse,
      reason: "the refusal must end the drag on the next re-resolution",
    );

    // And the list must stop moving under it.
    final settled = scroll.position.pixels;
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      scroll.position.pixels,
      settled,
      reason: "the autoscroll ticker must be torn down with the session",
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tree.liveRootKeys.first, "n0", reason: "nothing was committed");
  });
}
