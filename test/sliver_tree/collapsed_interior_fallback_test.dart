/// Repro: collapsing a subtree must not make its interior UNREACHABLE.
///
/// Collapsing should deprioritize the slots inside a container, which is
/// what collapsing means. Today it removes them from the candidate space
/// entirely: the above-chain only descends while the previous visible row
/// is DEEPER than the target, and the below-as-first-child rule is gated
/// on `hasLiveChildren`. Under a policy that restricts where a node may
/// live, the surviving candidates are then all illegal and resolution
/// returns null, so large parts of a collapsed container's header become
/// dead zones.
///
/// Stated as a two-level sections/items model because that is where it
/// bites hardest, but nothing here is sectioned-specific: any "containers
/// only at level N" policy reproduces it.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/_drop_zone_resolver.dart';
import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

void main() {
  late TreeController<String, String> tree;

  /// secA (a1, a2), secB (b1). Items are legal only under a section.
  Future<void> build(
    WidgetTester tester, {
    List<String> itemsA = const <String>["a1", "a2"],
    bool expandA = true,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots(<TreeNode<String, String>>[
      const TreeNode(key: "secA", data: "secA"),
      const TreeNode(key: "secB", data: "secB"),
    ]);
    if (itemsA.isNotEmpty) {
      tree.setChildren("secA", <TreeNode<String, String>>[
        for (final k in itemsA) TreeNode<String, String>(key: k, data: k),
      ]);
    }
    tree.setChildren("secB", <TreeNode<String, String>>[
      const TreeNode(key: "b1", data: "b1"),
    ]);
    tree.expandAll(animate: false);
    if (!expandA) {
      tree.collapse(key: "secA", animate: false);
    }
  }

  tearDown(() {
    tree.dispose();
  });

  /// The two-level shape policy: items only under a section.
  DropZoneResolver<String> sectioned() {
    return DropZoneResolver<String>(
      treeController: tree,
      canAcceptDrop: ({required movingKey, newParent, index}) {
        return newParent == "secA" || newParent == "secB";
      },
    );
  }

  /// [dragged] defaults to "b1". Pick one that is NOT the target and not
  /// already occupying the resolved slot: `_buildTarget` deliberately
  /// bypasses the policy filter for a node's own current position ("not
  /// moving" is not a drop a policy can forbid), so a self-drag would
  /// resolve non-null regardless of what the policy says and would pass a
  /// dead-zone assertion for entirely the wrong reason.
  TreeDropTarget<String>? at(
    DropZoneResolver<String> resolver,
    String target,
    double pointerY, {
    int? preferredDepth,
    String dragged = "b1",
  }) {
    return resolver.resolve(
      draggedKey: dragged,
      targetKey: target,
      targetPaintedY: 0.0,
      targetExtent: 30.0,
      pointerY: pointerY,
      preferredDepth: preferredDepth,
    );
  }

  group("must fail before the fix", () {
    testWidgets("above a header, previous section COLLAPSED with items", (
      tester,
    ) async {
      await build(tester, expandA: false);
      expect(tree.visibleNodes, <String>["secA", "secB", "b1"]);
      expect(tree.liveChildCount("secA"), 2, reason: "items still exist");

      final target = at(sectioned(), "secB", 3.0);
      expect(target, isNotNull, reason: "top of secB must not be a dead zone");
      expect(target!.parentKey, "secA");
      expect(target.indexInFinalList, 2, reason: "appended after a1, a2");
      expect(target.depth, 1);
      // Anchored past secA's visible subtree, which is one row while
      // collapsed, so the gap lands directly before secB.
      expect(target.gapVisibleIndex, tree.getVisibleIndex("secB"));
    });

    testWidgets("above a header, previous section EMPTY", (tester) async {
      await build(tester, itemsA: const <String>[]);
      expect(tree.visibleNodes, <String>["secA", "secB", "b1"]);

      final target = at(sectioned(), "secB", 3.0);
      expect(target, isNotNull);
      expect(target!.parentKey, "secA");
      expect(target.indexInFinalList, 0);
      expect(target.depth, 1);
    });

    testWidgets("below a COLLAPSED header with items", (tester) async {
      await build(tester, expandA: false);

      final target = at(sectioned(), "secA", 27.0);
      expect(target, isNotNull, reason: "bottom of secA must not be dead");
      expect(target!.zone, TreeDropZone.below);
      expect(target.parentKey, "secA");
      expect(target.indexInFinalList, 0, reason: "first child");
      expect(target.depth, 1);
    });

    testWidgets("below an EMPTY header", (tester) async {
      await build(tester, itemsA: const <String>[]);

      final target = at(sectioned(), "secA", 27.0);
      expect(target, isNotNull);
      expect(target!.zone, TreeDropZone.below);
      expect(target.parentKey, "secA");
      expect(target.indexInFinalList, 0);
    });

    testWidgets("reachability is invariant under collapsing", (tester) async {
      // The principle, as a test. Collapsing changes what is VISIBLE; it
      // must not change which slots exist.
      await build(tester);
      final expanded = at(sectioned(), "secB", 3.0);
      expect(expanded, isNotNull);
      expect(expanded!.parentKey, "secA");
      expect(expanded.indexInFinalList, 2);

      tree.collapse(key: "secA", animate: false);
      final collapsed = at(sectioned(), "secB", 3.0);

      expect(collapsed, isNotNull);
      expect(collapsed!.parentKey, expanded.parentKey);
      expect(collapsed.indexInFinalList, expanded.indexInFinalList);
      expect(collapsed.depth, expanded.depth);
    });
  });

  group("guards: must still hold after the fix", () {
    testWidgets("no policy: the shallow default is unmoved", (tester) async {
      await build(tester, expandA: false);
      final resolver = DropZoneResolver<String>(treeController: tree);

      final target = at(resolver, "secB", 3.0);
      expect(target, isNotNull);
      // Root-level sibling slot, exactly as before: the last resort is
      // never consulted because an ordered candidate succeeded.
      expect(target!.parentKey, isNull);
      expect(target.depth, 0);
    });

    testWidgets("the hidden interior is NOT clamp-addressable by an x hint", (
      tester,
    ) async {
      await build(tester);
      final resolver = DropZoneResolver<String>(treeController: tree);

      // b1 is a childless leaf. A far-right hint must still pick the
      // deepest CHAIN candidate, not nest into the leaf itself. Drag a1
      // rather than b1: a self-drag would resolve through the
      // current-position path and prove nothing.
      final target = at(
        resolver,
        "b1",
        27.0,
        preferredDepth: 99,
        dragged: "a1",
      );
      expect(target, isNotNull);
      expect(
        target!.depth,
        1,
        reason: "deepest legal chain level, not the leaf's interior",
      );
      expect(target.parentKey, "secB");
      expect(target.indexInFinalList, 1);
    });

    testWidgets("a flat-list policy keeps its vetoed tail dead", (
      tester,
    ) async {
      await build(tester);
      // Nothing may nest. `targetAllowsChildren` is false everywhere, so
      // the below last resort is never built and the make-room hold
      // contract is preserved.
      final resolver = DropZoneResolver<String>(
        treeController: tree,
        canAcceptDrop: ({required movingKey, newParent, index}) {
          return newParent == null && (index == null || index <= 1);
        },
      );

      final target = at(resolver, "b1", 27.0, dragged: "a1");
      expect(target, isNull);
    });

    testWidgets("the first header's top third stays correctly dead", (
      tester,
    ) async {
      await build(tester, expandA: false);
      // No section precedes secA, so no legal item slot exists above it.
      final target = at(sectioned(), "secA", 3.0);
      expect(target, isNull);
    });
  });

  testWidgets("a mid-exit previous row is never used as a fallback parent", (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: const TreeAnimationStyle(
        expandCollapse: TreeAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      ),
    );
    tree.setRoots(<TreeNode<String, String>>[
      const TreeNode(key: "secA", data: "secA"),
      const TreeNode(key: "secB", data: "secB"),
    ]);
    tree.setChildren("secB", <TreeNode<String, String>>[
      const TreeNode(key: "b1", data: "b1"),
    ]);
    tree.expandAll(animate: false);
    await tester.pump();

    tree.remove(key: "secA", animate: true);
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tree.isPendingDeletion("secA"),
      isTrue,
      reason: "setup: secA must be mid-exit for this to test anything",
    );

    // secA is on its way out; adopting it as a parent would drop the
    // dragged node into a vanishing subtree.
    final target = at(sectioned(), "secB", 3.0);
    expect(target, isNull);

    await tester.pumpAndSettle();
  });
}
