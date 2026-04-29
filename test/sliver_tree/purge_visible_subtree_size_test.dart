/// Regression for the visible-subtree-size cache going stale when a node
/// is purged while still in the deferred batched-removal queue from
/// `_removeFromVisibleOrder`.
///
/// Before the fix, `_finalizeAnimation` would `_purgeNodeData` (releasing
/// the nid and clearing `_parentByNid` for that nid) and then defer the
/// actual `_orderNids` compaction until after the loop. The deferred
/// `removeWhereKeyIn` saw `keyOf(nid) == null` for the released nid and
/// dropped the entry silently — never firing `_onNidVisibilityLost`,
/// which would have decremented the parent's `_visibleSubtreeSizeByNid`.
/// On the next `insert`, `insertIndex = parentVisibleIndex +
/// parentSubtreeSize` overran the actual visible array, and the
/// post-insert reindex left `_indexByNid` inconsistent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("delete + insert across exit-animation finalize keeps cache consistent",
      (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 100),
    );
    addTearDown(controller.dispose);

    controller.setRoots([
      const TreeNode(key: "root", data: "root"),
    ]);
    controller.setChildren("root", [
      for (var i = 0; i < 5; i++) TreeNode(key: "c$i", data: "child $i"),
    ]);
    controller.expand(key: "root", animate: false);

    // Render against a SliverTree so layout actually runs and the
    // visible-order buffer is exercised.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          SliverTree<String, String>(
            controller: controller,
            nodeBuilder: (_, key, _) => Text(key),
          ),
        ]),
      ),
    ));
    await tester.pump();

    // Remove an item, let animation finalize, then insert a new item.
    // Before the fix, the parent's _visibleSubtreeSizeByNid stayed
    // inflated after the finalize (because the deferred
    // _removeFromVisibleOrder couldn't decrement it), and the next
    // insert computed an out-of-range insertIndex.
    for (var cycle = 0; cycle < 5; cycle++) {
      controller.remove(key: "c$cycle", animate: true);
      // Wait long enough for the exit animation to finalize and the
      // deferred _removeFromVisibleOrder to run.
      await tester.pump(const Duration(milliseconds: 200));

      // Insert a fresh item — must not throw and must land at the
      // correct visible position.
      controller.insert(
        parentKey: "root",
        node: TreeNode(key: "n$cycle", data: "new $cycle"),
        animate: false,
      );
    }

    await tester.pumpAndSettle();

    // Sanity: the controller's view of root's children should match
    // what we expect after the cycles.
    final remaining = controller.getChildren("root");
    expect(remaining, isNotEmpty);
    // Original c0..c4 all removed; n0..n4 added.
    expect(remaining, equals(<String>["n0", "n1", "n2", "n3", "n4"]));
  });

  testWidgets("delete a subtree with multiple visible descendants keeps cache consistent",
      (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 100),
    );
    addTearDown(controller.dispose);

    controller.setRoots([
      const TreeNode(key: "root", data: "root"),
    ]);
    controller.setChildren("root", [
      const TreeNode(key: "branch", data: "branch"),
      const TreeNode(key: "sibling", data: "sibling"),
    ]);
    controller.setChildren("branch", [
      const TreeNode(key: "leaf1", data: "leaf1"),
      const TreeNode(key: "leaf2", data: "leaf2"),
      const TreeNode(key: "leaf3", data: "leaf3"),
    ]);
    controller.expand(key: "root", animate: false);
    controller.expand(key: "branch", animate: false);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          SliverTree<String, String>(
            controller: controller,
            nodeBuilder: (_, key, _) => Text(key),
          ),
        ]),
      ),
    ));
    await tester.pump();

    // Delete the entire branch subtree (1 + 3 visible nodes). Animation
    // finalizes the leaves and branch; then an insert under root should
    // land at the correct position.
    controller.remove(key: "branch", animate: true);
    await tester.pump(const Duration(milliseconds: 200));

    controller.insert(
      parentKey: "root",
      node: const TreeNode(key: "fresh", data: "fresh"),
      animate: false,
    );

    await tester.pumpAndSettle();

    expect(controller.getChildren("root"), equals(<String>["sibling", "fresh"]));
  });
}
