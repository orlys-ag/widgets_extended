/// Repro for the make-room gap being anchored on the HOVERED ROW while the
/// commit uses the RESOLVED SLOT.
///
/// The two agree whenever the slot is visually adjacent to the hovered row,
/// which is why this went unnoticed. They diverge in exactly one shape:
/// `targetAllowsChildren` is false (a `canAcceptDrop` veto or a cycle) AND
/// the hovered row has a visible subtree. The below-as-first-child rule that
/// normally keeps them agreeing is gated on `targetAllowsChildren`, so it
/// switches off, the ancestor chain resolves to a slot after the row's whole
/// subtree, and the gap stays directly under the row.
///
/// Both cases below are generic-tree cases. The sectioned module hits the
/// same defect on every expanded header once its shape policy exists, but
/// that module has no reorder yet, so the veto is supplied directly here.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/_drop_zone_resolver.dart';
import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

void main() {
  late TreeController<String, String> tree;

  /// Builds: a > (a1, a2), b, c. All expanded, so the visible order is
  /// [a, a1, a2, b, c].
  Future<void> build(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(<TreeNode<String, String>>[
      const TreeNode(key: "a", data: "a"),
      const TreeNode(key: "b", data: "b"),
      const TreeNode(key: "c", data: "c"),
    ]);
    tree.setChildren("a", <TreeNode<String, String>>[
      const TreeNode(key: "a1", data: "a1"),
      const TreeNode(key: "a2", data: "a2"),
    ]);
    tree.expandAll(animate: false);
  }

  tearDown(() {
    tree.dispose();
  });

  /// Resolves the BELOW zone of [target] by probing near its bottom edge.
  TreeDropTarget<String>? below(
    DropZoneResolver<String> resolver,
    String dragged,
    String target,
  ) {
    return resolver.resolve(
      draggedKey: dragged,
      targetKey: target,
      targetPaintedY: 0.0,
      targetExtent: 30.0,
      // Bottom sixth: unambiguously the `below` third under a three-zone
      // split, and still `below` under the two-zone midpoint split.
      pointerY: 27.0,
    );
  }

  testWidgets("setup sanity: the divergent shape is genuinely exercised", (
    tester,
  ) async {
    await build(tester);
    // The whole defect needs a row that (1) cannot take children and
    // (2) has a visible subtree. Prove both, or the test below could pass
    // for a reason unrelated to the bug.
    expect(
      tree.visibleNodes,
      <String>["a", "a1", "a2", "b", "c"],
      reason: "a's subtree must be VISIBLE for the anchor to differ",
    );
    expect(tree.isExpanded("a"), isTrue);
    expect(tree.hasLiveChildren("a"), isTrue);
    expect(tree.visibleSubtreeSize("a"), 3);
  });

  testWidgets("policy veto: gap anchors on the slot, not the hovered row", (
    tester,
  ) async {
    await build(tester);
    // A flat-list-style policy: nothing may nest, everything lives at
    // root. This is the shape the sectioned module's section drags take.
    final resolver = DropZoneResolver<String>(
      treeController: tree,
      canAcceptDrop: ({required movingKey, newParent, index}) {
        return newParent == null;
      },
    );

    final target = below(resolver, "c", "a");
    expect(target, isNotNull);

    // The commit lands AFTER a's whole subtree, at root index 1.
    expect(target!.parentKey, isNull);
    expect(target.indexInFinalList, 1);

    // So the gap must open there too: past a, a1 and a2, i.e. before "b"
    // at visible index 3. Anchoring on the hovered row would give 1, and
    // the gap would appear between "a" and "a1" while the row commits
    // three positions lower.
    expect(
      target.gapVisibleIndex,
      3,
      reason:
          "gap must open at the committed slot, not under the hovered "
          "row; index 1 is the pre-fix answer",
    );
    expect(tree.visibleNodes[target.gapVisibleIndex], "b");
  });

  testWidgets("cycle veto: dragging over one's own expanded subtree", (
    tester,
  ) async {
    await build(tester);
    // No policy at all. "a" is dragged, and the pointer is over "a" itself,
    // whose subtree is visible and is part of the dragged block. The
    // structural cycle filter makes targetAllowsChildren false, so this is
    // the same divergent shape with no canAcceptDrop involved.
    final resolver = DropZoneResolver<String>(treeController: tree);

    final target = below(resolver, "a", "a");
    expect(target, isNotNull);
    expect(target!.parentKey, isNull);

    // "below a" is a's own current slot, which resolves as the valid
    // "returns here" target. Its gap belongs past a's subtree, not
    // immediately under a's row.
    expect(
      target.gapVisibleIndex,
      3,
      reason:
          "the dragged block spans three visible rows; the gap belongs "
          "past it",
    );
  });

  testWidgets("no divergence when the hovered row has no visible subtree", (
    tester,
  ) async {
    await build(tester);
    tree.collapse(key: "a", animate: false);
    expect(tree.visibleNodes, <String>["a", "b", "c"]);

    final resolver = DropZoneResolver<String>(
      treeController: tree,
      canAcceptDrop: ({required movingKey, newParent, index}) {
        return newParent == null;
      },
    );

    final target = below(resolver, "c", "a");
    expect(target, isNotNull);
    expect(target!.indexInFinalList, 1);
    // Collapsed, so visibleSubtreeSize is 1 and the anchored form reduces
    // to the hovered row's own trailing edge. This is the case that was
    // always correct, and it must stay bit-identical.
    expect(target.gapVisibleIndex, 1);
  });

  testWidgets("above zone: every candidate shares the target's leading edge", (
    tester,
  ) async {
    await build(tester);
    // The above-chain's deeper candidates are reached by filter fallback.
    // A policy admitting only "a" as a parent vetoes the shallow
    // root-level candidate, so resolution falls through to "append to a".
    final resolver = DropZoneResolver<String>(
      treeController: tree,
      canAcceptDrop: ({required movingKey, newParent, index}) {
        return newParent == "a";
      },
    );

    final target = resolver.resolve(
      draggedKey: "c",
      targetKey: "b",
      targetPaintedY: 0.0,
      targetExtent: 30.0,
      pointerY: 3.0, // top sixth: the `above` zone
    );
    expect(target, isNotNull);
    expect(target!.zone, TreeDropZone.above);

    // Fell back to the deeper candidate: appended under "a".
    expect(target.parentKey, "a");
    expect(target.indexInFinalList, 2);

    // Both expressions of this slot are the SAME visible edge, directly
    // before "b". The deeper candidate is "after a2", and a2 is the row
    // immediately above b, so the two coincide by construction.
    expect(target.gapVisibleIndex, tree.getVisibleIndex("b"));
    expect(target.gapVisibleIndex, 3);
  });

  testWidgets("into zone: gap is the target's own trailing row edge", (
    tester,
  ) async {
    await build(tester);
    final resolver = DropZoneResolver<String>(treeController: tree);

    final target = resolver.resolve(
      draggedKey: "c",
      targetKey: "a",
      targetPaintedY: 0.0,
      targetExtent: 30.0,
      pointerY: 15.0, // middle third: the `into` zone
    );
    expect(target, isNotNull);
    expect(target!.zone, TreeDropZone.into);
    expect(target.parentKey, "a");
    expect(target.indexInFinalList, 0);

    // First-child slot: directly below a's OWN row, NOT past its subtree.
    // This is the row where the anchored form would give the wrong answer,
    // which is why `into` carries a precomputed index instead.
    expect(target.gapVisibleIndex, 1);
    expect(tree.visibleNodes[1], "a1");
  });

  testWidgets("end to end: the wrong rows physically move without the fix", (
    tester,
  ) async {
    await build(tester);
    // The tests above assert the resolved INDEX. This one closes the loop
    // to the symptom a user sees: which rows actually shift. Extents must
    // be non-zero for the preview to install, so give every row one.
    for (final k in tree.visibleNodes) {
      tree.setFullExtent(k, 30.0);
    }
    final resolver = DropZoneResolver<String>(
      treeController: tree,
      canAcceptDrop: ({required movingKey, newParent, index}) {
        return newParent == null;
      },
    );
    final target = below(resolver, "c", "a");
    expect(target, isNotNull);

    // Install the gap exactly as MakeRoomDriver now does.
    tree.setReorderPreviewAtIndex(
      draggedKey: "c",
      gapVisibleIndex: target!.gapVisibleIndex,
    );

    // The drop lands after a's whole subtree, so a's own rows must sit
    // still and only "b" parts to make room.
    expect(tree.getSlideDelta("a"), 0.0);
    expect(
      tree.getSlideDelta("a1"),
      0.0,
      reason: "a1 is inside the untargeted subtree and must not move",
    );
    expect(
      tree.getSlideDelta("a2"),
      0.0,
      reason: "a2 is inside the untargeted subtree and must not move",
    );
    expect(tree.getSlideDelta("b"), 30.0, reason: "b parts for the drop");

    // Now the pre-fix arithmetic: anchor the gap on the HOVERED ROW.
    tree.setReorderPreviewAtIndex(
      draggedKey: "c",
      gapVisibleIndex: tree.getVisibleIndex("a") + 1,
    );
    expect(
      tree.getSlideDelta("a1"),
      30.0,
      reason:
          "this is the bug: rows inside a's subtree are shoved apart "
          "even though the drop commits after that whole subtree",
    );
    expect(tree.getSlideDelta("a2"), 30.0);
  });

  testWidgets("gapVisibleIndex stays in range at the very end of the list", (
    tester,
  ) async {
    await build(tester);
    final resolver = DropZoneResolver<String>(treeController: tree);

    // Below the last root: the slot is "after every visible row", which is
    // the terminal index, equal to the count rather than one less.
    final target = below(resolver, "a", "c");
    expect(target, isNotNull);
    expect(target!.gapVisibleIndex, tree.visibleNodes.length);
    expect(target.gapVisibleIndex, 5);
  });
}
