/// Regression tests for M3: `expand(animate: false)` mid-collapse spliced
/// the new descendants ahead of the ones still animating out.
///
/// `expand`'s non-animated branch collected every member of the DFS
/// pre-order flatten that was not already in `_order` and inserted the
/// whole block at `parentIndex + 1`, ignoring where the members already
/// in the order sat. Mid-collapse those members still hold their slots,
/// because the op group's `pendingRemoval` is not consumed until the
/// animation reaches dismissed, so `[A, a1, a2]` plus a new `a3`
/// produced `[A, a3, a1, a2]`. `_removeAnimation`, the only other thing
/// that branch did to an already-visible member, detaches animation
/// state and never touches `_order`, so nothing corrected the placement
/// afterwards.
///
/// The pre-fix code is described by NAME rather than by line: it no
/// longer exists, so any line number for it would resolve to whatever
/// replaced it.
///
/// Path 2's OWN mixed branch already walked a cursor and got the order
/// right, and M3 replaces it with the same shared helper. That branch is
/// NOT covered here, and not anywhere: instrumented and measured across
/// the whole suite, `expand` Path 2 takes all-new 107 times and
/// all-visible 3 times and its mixed branch ZERO times. Reaching it needs
/// a node that is collapsed, holds no operation group, and whose
/// expansion-gated flatten still names a row sitting in `_order`; several
/// attempted sequences all collapsed into the all-new branch instead. So
/// the Path-2 call site rides on the helper being pinned by the three
/// repros here, not on a test of its own. Treat that as a known gap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

TreeController<String, String> _controller(WidgetTester tester) {
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
  return controller;
}

Future<void> _pumpTree(
  WidgetTester tester,
  TreeController<String, String> controller, {
  ScrollController? scrollController,
}) async {
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
                nodeBuilder: (context, key, depth) {
                  return SizedBox(height: 48, child: Text(key));
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets("M3: expand(animate: false) mid-collapse keeps new children "
      "after the ones still animating out", (tester) async {
    final controller = _controller(tester);
    controller.setRoots([const TreeNode(key: "A", data: "A")]);
    controller.setChildren("A", [
      const TreeNode(key: "a1", data: "A1"),
      const TreeNode(key: "a2", data: "A2"),
    ]);
    controller.expand(key: "A", animate: false);
    await _pumpTree(tester, controller);

    controller.collapse(key: "A");
    // Bare pump first: a ticker started outside a frame leaves
    // `_startTime` null (scheduler/ticker.dart:202-204) and the first
    // tick sets `_startTime ??= timeStamp` (:276), so without this the
    // timed pump advances the collapse by nothing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      controller.isAnimating("a1"),
      isTrue,
      reason:
          "setup: the collapse must be in flight, so a1 and a2 still hold "
          "their order slots through the op group's pendingRemoval",
    );
    expect(
      controller.visibleNodes,
      ["A", "a1", "a2"],
      reason: "setup: the collapsing members must still hold order slots",
    );

    controller.insert(
      parentKey: "A",
      node: const TreeNode(key: "a3", data: "A3"),
      animate: false,
    );
    controller.expand(key: "A", animate: false);

    expect(
      controller.visibleNodes,
      ["A", "a1", "a2", "a3"],
      reason:
          "a3 is the third child, so it must land after a1 and a2; the "
          "block insert at parentIndex + 1 put it in front of both",
    );
  });

  testWidgets("M3: animateScrollToKey's immediate ancestor expansion hits "
      "the same path", (tester) async {
    // The real-world trigger. `ScrollOrchestrator.ensureAncestorsExpanded`
    // calls `expand(animate: false)` once per collapsed ancestor, so a
    // scroll issued while a collapse is in flight corrupts the order
    // without anyone calling `expand` directly.
    final controller = _controller(tester);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    controller.setRoots([const TreeNode(key: "A", data: "A")]);
    controller.setChildren("A", [
      const TreeNode(key: "a1", data: "A1"),
      const TreeNode(key: "a2", data: "A2"),
    ]);
    controller.expand(key: "A", animate: false);
    await _pumpTree(tester, controller, scrollController: scrollController);

    controller.collapse(key: "A");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      controller.visibleNodes,
      ["A", "a1", "a2"],
      reason: "setup: the collapsing members must still hold order slots",
    );

    controller.insert(
      parentKey: "A",
      node: const TreeNode(key: "a3", data: "A3"),
      animate: false,
    );
    expect(
      controller.isExpanded("A"),
      isFalse,
      reason:
          "setup: A must read as collapsed, or ensureAncestorsExpanded has "
          "nothing to expand and the test would not exercise the path",
    );

    controller.animateScrollToKey(
      "a3",
      scrollController: scrollController,
      ancestorExpansion: AncestorExpansionMode.immediate,
      duration: Duration.zero,
    );
    await tester.pump();

    expect(
      controller.visibleNodes,
      ["A", "a1", "a2", "a3"],
      reason:
          "the orchestrator's expand(animate: false) must splice a3 after "
          "its earlier siblings, not ahead of them",
    );
  });

  testWidgets("M3 guard: reversing a collapse with newly inserted children "
      "keeps the order", (tester) async {
    // NOT a repro: this passes before the fix, and it does NOT exercise
    // Path 2. An animated `expand` whose key already holds an operation
    // group takes Path 1, the reversal branch
    // (`tree_controller.dart:3804-3806`), and an in-flight collapse is
    // exactly such a group. Measured, not assumed: neutering the helper's
    // cursor leaves this test green, which is what exposed the earlier
    // version of this comment as wrong.
    //
    // It stays because Path 1 is the branch a real reversal takes and
    // nothing else here pins its ordering with newly inserted children.
    final controller = _controller(tester);
    controller.setRoots([const TreeNode(key: "A", data: "A")]);
    controller.setChildren("A", [
      const TreeNode(key: "a1", data: "A1"),
      const TreeNode(key: "a2", data: "A2"),
    ]);
    controller.expand(key: "A", animate: false);
    await _pumpTree(tester, controller);

    controller.collapse(key: "A");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      controller.visibleNodes,
      ["A", "a1", "a2"],
      reason: "setup: the collapsing members must still hold order slots",
    );

    for (final k in ["a3", "a4", "a5"]) {
      controller.insert(
        parentKey: "A",
        node: TreeNode(key: k, data: k.toUpperCase()),
        animate: false,
      );
    }
    // Animated, and "A" already holds the collapse's operation group, so
    // this is Path 1's reversal, not Path 2.
    controller.expand(key: "A");
    await tester.pump();

    expect(
      controller.visibleNodes,
      ["A", "a1", "a2", "a3", "a4", "a5"],
      reason:
          "the reversal must keep every new key after the members that "
          "already hold slots",
    );

    await tester.pumpAndSettle();
    expect(
      controller.visibleNodes,
      ["A", "a1", "a2", "a3", "a4", "a5"],
      reason: "the order must survive the expand settling",
    );
  });

  testWidgets("M3: a new child BETWEEN two mid-collapse siblings lands "
      "between them", (tester) async {
    // The interleaved case, which the append-only cases above do not
    // reach: the gap for a3 must fall strictly between a1's slot and
    // a2's, so the cursor has to advance past a1 and stop before a2.
    // Pre-fix this produced ["A", "a3", "a1", "a2"] like the others,
    // because the block insert ignores the cursor entirely.
    final controller = _controller(tester);
    controller.setRoots([const TreeNode(key: "A", data: "A")]);
    controller.setChildren("A", [
      const TreeNode(key: "a1", data: "A1"),
      const TreeNode(key: "a2", data: "A2"),
    ]);
    controller.expand(key: "A", animate: false);
    await _pumpTree(tester, controller);

    controller.collapse(key: "A");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      controller.visibleNodes,
      ["A", "a1", "a2"],
      reason: "setup: the collapsing members must still hold order slots",
    );

    // index 1 puts a3 between a1 and a2 structurally.
    controller.insert(
      parentKey: "A",
      node: const TreeNode(key: "a3", data: "A3"),
      index: 1,
      animate: false,
    );
    expect(
      controller.getLiveChildren("A"),
      ["a1", "a3", "a2"],
      reason:
          "setup: a3 must sit between its siblings structurally, or the "
          "splice has no interleaving to get right",
    );

    controller.expand(key: "A", animate: false);

    expect(
      controller.visibleNodes,
      ["A", "a1", "a3", "a2"],
      reason:
          "the visible order must follow the structural order: a3 after "
          "a1 and before a2",
    );
  });

  testWidgets("M3: a multi-gap mixed splice matches the structural order", (
    tester,
  ) async {
    // The cases above all splice a SINGLE key, so they exercise
    // `insertAllKeysAtGaps` only at k == 1, where the backward merge is
    // indistinguishable from one memmove. This one interleaves six new
    // children among four that are mid-collapse, producing gaps that are
    // non-decreasing but NOT all equal, and checks the result against the
    // structural child order as an oracle rather than a literal.
    final controller = _controller(tester);
    controller.setRoots([const TreeNode(key: "A", data: "A")]);
    controller.setChildren("A", [
      for (int i = 0; i < 4; i++) TreeNode(key: "old$i", data: "OLD$i"),
    ]);
    controller.expand(key: "A", animate: false);
    await _pumpTree(tester, controller);

    controller.collapse(key: "A");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      controller.visibleNodes,
      ["A", "old0", "old1", "old2", "old3"],
      reason: "setup: all four members must still hold order slots",
    );

    // Deterministic interleave: two at the head, one mid, one mid, two at
    // the tail. Indices are chosen against the list as it grows, so the
    // structural order below is the oracle, not these numbers.
    const spots = <int>[0, 1, 3, 5, 8, 9];
    for (int i = 0; i < spots.length; i++) {
      controller.insert(
        parentKey: "A",
        node: TreeNode(key: "new$i", data: "NEW$i"),
        index: spots[i],
        animate: false,
      );
    }
    final structural = controller.getLiveChildren("A");
    expect(
      structural.length,
      10,
      reason: "setup: four old children plus six new ones",
    );
    // The property this test exists for: the new keys must be INTERLEAVED
    // among the old ones, not one contiguous run, or every gap would be
    // identical and the merge would degenerate to a single memmove. An
    // assertion on the old keys' relative order was tried here first and
    // dropped: `insert` never reorders existing children, so it could not
    // fail in the direction it claimed to check.
    final firstNew = structural.indexWhere((k) => k.startsWith("new"));
    final lastNew = structural.lastIndexWhere((k) => k.startsWith("new"));
    expect(
      lastNew - firstNew + 1,
      greaterThan(6),
      reason:
          "setup: the six new keys must span more than six slots, so at "
          "least one old key sits between them and the gaps differ",
    );

    controller.expand(key: "A", animate: false);

    expect(
      controller.visibleNodes,
      ["A", ...structural],
      reason:
          "every new key must land at its structural position relative to "
          "the members already holding slots",
    );
  });
}
