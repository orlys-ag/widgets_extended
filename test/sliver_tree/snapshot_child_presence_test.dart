/// Pins [TreeSyncController.snapshotChildPresence] to the method it was
/// extracted from.
///
/// `snapshotChildPresence` exists so the sync-time expansion passes stop
/// materializing a child list per node to answer two boolean questions.
/// It is only a valid substitute while it reports the same key set and
/// the same "has live children" answer as
/// `snapshotCurrentChildren().map((k, v) => MapEntry(k, v.isNotEmpty))`.
///
/// The interesting case is mid-exit: the old method filtered through
/// `getLiveChildren`, the new one filters `getChildren` inline, so a
/// pending-deletion node is where the two would diverge if the inline
/// filter were wrong.
library;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets("snapshotChildPresence agrees with snapshotCurrentChildren", (
    tester,
  ) async {
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: const TreeAnimationStyle(
        expandCollapse: TreeAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      ),
    );
    addTearDown(tree.dispose);
    final sync = TreeSyncController<String, String>(treeController: tree);

    /// The answer the old method yields, reduced to what its callers
    /// actually read off it.
    Map<String, bool> viaCurrentChildren() {
      return <String, bool>{
        for (final entry in sync.snapshotCurrentChildren().entries)
          entry.key: entry.value.isNotEmpty,
      };
    }

    tree.setRoots([
      const TreeNode(key: "r0", data: "r0"),
      const TreeNode(key: "r1", data: "r1"),
      const TreeNode(key: "r2", data: "r2"),
    ]);
    tree.setChildren("r0", [
      const TreeNode(key: "a", data: "a"),
      const TreeNode(key: "b", data: "b"),
    ]);
    tree.setChildren("a", [const TreeNode(key: "a1", data: "a1")]);
    tree.setChildren("r2", [const TreeNode(key: "c", data: "c")]);

    // Settled: every live node is present, leaves report false.
    expect(sync.snapshotChildPresence(), equals(viaCurrentChildren()));
    expect(sync.snapshotChildPresence(), equals({
      "r0": true,
      "a": true,
      "a1": false,
      "b": false,
      "r1": false,
      "r2": true,
      "c": false,
    }));

    tree.expand(key: "r0");
    tree.expand(key: "r2");
    await tester.pump();

    // Mid-exit children. Setup sanity: the removals must still be in
    // flight, or this asserts nothing.
    tree.remove(key: "b");
    tree.remove(key: "c");
    await tester.pump(const Duration(milliseconds: 100));
    expect(tree.isPendingDeletion("b"), isTrue);
    expect(tree.isPendingDeletion("c"), isTrue);

    final midExit = sync.snapshotChildPresence();
    expect(midExit, equals(viaCurrentChildren()));
    // Exiting nodes leave the key set entirely...
    expect(midExit.containsKey("b"), isFalse);
    expect(midExit.containsKey("c"), isFalse);
    // ...and do not count as children, so r2 reads childless while its
    // only child animates out.
    expect(midExit["r2"], isFalse);
    expect(midExit["r0"], isTrue);

    await tester.pumpAndSettle();
    expect(sync.snapshotChildPresence(), equals(viaCurrentChildren()));

    // Mid-exit ROOT, which exercises the root filter rather than the
    // child filter.
    tree.remove(key: "r1");
    await tester.pump(const Duration(milliseconds: 100));
    expect(tree.isPendingDeletion("r1"), isTrue);

    final exitingRoot = sync.snapshotChildPresence();
    expect(exitingRoot, equals(viaCurrentChildren()));
    expect(exitingRoot.containsKey("r1"), isFalse);

    await tester.pumpAndSettle();
  });

  testWidgets("snapshotChildPresence on an empty tree", (tester) async {
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(tree.dispose);
    final sync = TreeSyncController<String, String>(treeController: tree);

    expect(sync.snapshotChildPresence(), isEmpty);
  });

  testWidgets("snapshotChildPresence does not stack-overflow on a deep chain", (
    tester,
  ) async {
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(tree.dispose);
    final sync = TreeSyncController<String, String>(treeController: tree);

    const depth = 5000;
    tree.setRoots([const TreeNode(key: "n0", data: "n0")]);
    for (int i = 1; i < depth; i++) {
      tree.setChildren("n${i - 1}", [
        TreeNode(key: "n$i", data: "n$i"),
      ]);
    }

    final presence = sync.snapshotChildPresence();
    expect(presence.length, equals(depth));
    expect(presence["n0"], isTrue);
    expect(presence["n${depth - 1}"], isFalse);
  });
}
