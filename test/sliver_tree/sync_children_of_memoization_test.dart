/// Pins [TreeSyncController.syncRoots]'s documented contract that
/// `childrenOf` is consulted exactly once per node per sync.
///
/// `_syncRootsImpl` walks the desired tree twice: once to collect
/// descendant keys for reparent detection, once to apply the diff. Both
/// walks used to call `childrenOf` independently, so every sync built a
/// second [TreeNode] for every node in the tree to produce a list the
/// first walk already had. The answers are now memoized across both
/// walks, which is what lets the doc promise purity buys anything.
///
/// This matters most at the layer above: `SectionedListController`'s
/// `childrenOf` materializes a node per item, and `SyncedSliverTree`'s
/// snapshot modes materialize a node per child, so a regression here
/// doubles allocation for both modules at once.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets("childrenOf is consulted exactly once per node per sync", (
    tester,
  ) async {
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(tree.dispose);
    final sync = TreeSyncController<String, String>(treeController: tree);

    // Three roots, three children each, one grandchild under every first
    // child: 3 + 9 + 3 = 15 nodes, with a depth of 3 so the recursion is
    // genuinely exercised rather than a single level.
    final calls = <String, int>{};
    List<TreeNode<String, String>> childrenOf(String key) {
      calls[key] = (calls[key] ?? 0) + 1;
      if (key.startsWith("r") && !key.contains("-")) {
        return [
          for (var c = 0; c < 3; c++)
            TreeNode(key: "$key-c$c", data: "$key-c$c"),
        ];
      }
      if (key.endsWith("-c0")) {
        return [TreeNode(key: "$key-g", data: "$key-g")];
      }
      return const [];
    }

    final roots = <TreeNode<String, String>>[
      for (var r = 0; r < 3; r++) TreeNode(key: "r$r", data: "r$r"),
    ];

    sync.syncRoots(roots, childrenOf: childrenOf, animate: false);

    // Setup sanity: the tree really was built, so the counts below
    // describe a walk that happened rather than one that was skipped.
    expect(tree.rootKeys, equals(["r0", "r1", "r2"]));
    expect(tree.getChildren("r0"), equals(["r0-c0", "r0-c1", "r0-c2"]));
    expect(tree.getChildren("r0-c0"), equals(["r0-c0-g"]));
    expect(calls.length, equals(15));

    final askedMoreThanOnce = <String, int>{
      for (final entry in calls.entries)
        if (entry.value != 1) entry.key: entry.value,
    };
    expect(
      askedMoreThanOnce,
      isEmpty,
      reason: "childrenOf must be called exactly once per node per sync",
    );
  });

  testWidgets("the memo does not leak across syncs", (tester) async {
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(tree.dispose);
    final sync = TreeSyncController<String, String>(treeController: tree);

    var childrenOfCalls = 0;
    var childrenOfR0 = <TreeNode<String, String>>[
      const TreeNode(key: "a", data: "a"),
    ];
    List<TreeNode<String, String>> childrenOf(String key) {
      childrenOfCalls++;
      return key == "r0" ? childrenOfR0 : const [];
    }

    final roots = <TreeNode<String, String>>[
      const TreeNode(key: "r0", data: "r0"),
    ];

    sync.syncRoots(roots, childrenOf: childrenOf, animate: false);
    expect(tree.getChildren("r0"), equals(["a"]));
    expect(childrenOfCalls, equals(2)); // r0 and a, once each.

    // A later sync must re-ask, or a changed input would never be seen.
    childrenOfCalls = 0;
    childrenOfR0 = <TreeNode<String, String>>[
      const TreeNode(key: "a", data: "a"),
      const TreeNode(key: "b", data: "b"),
    ];
    sync.syncRoots(roots, childrenOf: childrenOf, animate: false);
    expect(tree.getChildren("r0"), equals(["a", "b"]));
    expect(childrenOfCalls, equals(3)); // r0, a, b.
  });

  testWidgets("a cyclic childrenOf still throws rather than hanging", (
    tester,
  ) async {
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(tree.dispose);
    final sync = TreeSyncController<String, String>(treeController: tree);

    // a -> b -> a. The memo must not turn the revisit guard into an
    // infinite walk by handing back a cached list forever.
    List<TreeNode<String, String>> childrenOf(String key) {
      return switch (key) {
        "a" => [const TreeNode(key: "b", data: "b")],
        "b" => [const TreeNode(key: "a", data: "a")],
        _ => const [],
      };
    }

    expect(
      () => sync.syncRoots(
        [const TreeNode(key: "a", data: "a")],
        childrenOf: childrenOf,
        animate: false,
      ),
      throwsArgumentError,
    );
  });
}
