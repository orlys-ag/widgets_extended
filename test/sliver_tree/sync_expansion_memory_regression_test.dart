/// Regression tests for issue 4 of the 2026-08-21 review: three defects
/// in [TreeSyncController]'s expansion-memory lifecycle, each of which
/// silently overrode a user's expand/collapse across a remove/re-add.
///
/// 4a. `_pruneExpansionMemory` tested `isExiting`, while its own comment
///     said "pending deletion". `remove()` marks every descendant
///     pending-deletion but installs a standalone exit only for rows in
///     the visible order, so a descendant under a COLLAPSED ancestor
///     inside the removed subtree is pending-deletion with `isExiting`
///     false, and step 8 of the very sync that recorded it pruned it.
/// 4b. A retained ROOT re-added childless keeps its remembered `true` on
///     purpose, but no later sync restored it: the recursive walk's
///     restore list held only child keys, step 7 restored only newly
///     ADDED roots, and both retry sites in `_syncChildrenImpl` are
///     suppressed inside a recursive sync. The next prune then dropped
///     the entry because the node had children by then.
/// 4c. `_rememberExpansion` wrote `isExpanded` unconditionally, so a node
///     removed again while transiently childless overwrote the kept
///     `true` with `false` (a childless node cannot be expanded).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

TreeNode<String, String> _n(String key) => TreeNode(key: key, data: key);

void main() {
  testWidgets("4a: a hidden pending-deletion descendant keeps its "
      "remembered expansion", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: const TreeAnimationStyle(),
    );
    addTearDown(controller.dispose);
    final sync = TreeSyncController<String, String>(
      treeController: controller,
    );
    addTearDown(sync.dispose);

    List<TreeNode<String, String>> childrenOf(String key) {
      if (key == "R") return [_n("P")];
      if (key == "P") return [_n("c")];
      return const [];
    }

    sync.syncRoots([_n("R"), _n("X")], childrenOf: childrenOf, animate: false);
    controller.expand(key: "R", animate: false);
    controller.expand(key: "P", animate: false);
    expect(controller.visibleNodes, ["R", "P", "c", "X"]);

    // The user collapses P, then R. P's expansion state is now recorded
    // under a collapsed ancestor.
    controller.collapse(key: "P", animate: false);
    controller.collapse(key: "R", animate: false);

    // A filter sync drops R. Its exit animates; P is inside the removed
    // subtree but hidden, so it never gets an exit of its own.
    sync.syncRoots([_n("X")], childrenOf: childrenOf, animate: true);
    expect(
      controller.isExiting("R"),
      isTrue,
      reason: "setup: the visible root animates out",
    );
    expect(
      controller.isPendingDeletion("P"),
      isTrue,
      reason: "setup: the hidden descendant is marked for purge",
    );
    expect(
      controller.isExiting("P"),
      isFalse,
      reason: "setup: but it has no exit animation, which is exactly the "
          "case the old isExiting predicate missed",
    );
    expect(sync.snapshotRememberedKeys(), containsAll(<String>["R", "P"]));

    await tester.pumpAndSettle();

    // Bring R back. Both R and P must return COLLAPSED, as the user left
    // them.
    sync.syncRoots([_n("R"), _n("X")], childrenOf: childrenOf, animate: false);
    expect(controller.isExpanded("R"), isFalse);
    controller.expand(key: "R", animate: false);
    expect(
      controller.isExpanded("P"),
      isFalse,
      reason: "P was collapsed by the user before the removal",
    );
  });

  testWidgets("4b: a retained root re-added childless is restored when its "
      "children arrive in a later sync", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    final sync = TreeSyncController<String, String>(
      treeController: controller,
    );
    addTearDown(sync.dispose);

    var childrenOfP = <TreeNode<String, String>>[_n("c")];
    List<TreeNode<String, String>> childrenOf(String key) {
      return key == "P" ? childrenOfP : const [];
    }

    sync.syncRoots([_n("P")], childrenOf: childrenOf, animate: false);
    controller.expand(key: "P", animate: false);
    expect(controller.isExpanded("P"), isTrue);

    // Remove P, then re-add it before its children are known (the
    // async-loaded-subtree shape).
    sync.syncRoots([], childrenOf: childrenOf, animate: false);
    expect(sync.snapshotRememberedKeys(), contains("P"));
    childrenOfP = <TreeNode<String, String>>[];
    sync.syncRoots([_n("P")], childrenOf: childrenOf, animate: false);
    expect(
      sync.snapshotRememberedKeys(),
      contains("P"),
      reason: "setup: the memory is deliberately kept while P is childless",
    );

    // Children arrive: the kept memory must now be spent.
    childrenOfP = <TreeNode<String, String>>[_n("c")];
    sync.syncRoots([_n("P")], childrenOf: childrenOf, animate: false);
    expect(controller.isExpanded("P"), isTrue);
    expect(controller.visibleNodes, ["P", "c"]);
  });

  testWidgets("4c: removing a childless node again does not overwrite its "
      "remembered expansion", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    final sync = TreeSyncController<String, String>(
      treeController: controller,
    );
    addTearDown(sync.dispose);

    var childrenOfP = <TreeNode<String, String>>[_n("c")];
    List<TreeNode<String, String>> childrenOf(String key) {
      return key == "P" ? childrenOfP : const [];
    }

    sync.syncRoots(
      [_n("R"), _n("P")],
      childrenOf: childrenOf,
      animate: false,
    );
    controller.expand(key: "P", animate: false);
    expect(controller.isExpanded("P"), isTrue);

    // Remove, re-add childless, remove again: the second removal is the
    // one that used to overwrite the kept `true` with `false`.
    sync.syncRoots([_n("R")], childrenOf: childrenOf, animate: false);
    childrenOfP = <TreeNode<String, String>>[];
    sync.syncRoots(
      [_n("R"), _n("P")],
      childrenOf: childrenOf,
      animate: false,
    );
    sync.syncRoots([_n("R")], childrenOf: childrenOf, animate: false);

    childrenOfP = <TreeNode<String, String>>[_n("c")];
    sync.syncRoots(
      [_n("R"), _n("P")],
      childrenOf: childrenOf,
      animate: false,
    );
    expect(controller.isExpanded("P"), isTrue);
  });

  testWidgets("a node the user collapsed is not re-expanded by memory", (
    tester,
  ) async {
    // Control for all three: memory restores what the user LEFT, so a
    // node collapsed before removal must come back collapsed rather than
    // being re-expanded by a stale `true`.
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    final sync = TreeSyncController<String, String>(
      treeController: controller,
    );
    addTearDown(sync.dispose);

    List<TreeNode<String, String>> childrenOf(String key) {
      return key == "P" ? [_n("c")] : const [];
    }

    sync.syncRoots([_n("P")], childrenOf: childrenOf, animate: false);
    controller.expand(key: "P", animate: false);
    controller.collapse(key: "P", animate: false);

    sync.syncRoots([], childrenOf: childrenOf, animate: false);
    sync.syncRoots([_n("P")], childrenOf: childrenOf, animate: false);
    expect(controller.isExpanded("P"), isFalse);
  });
}
