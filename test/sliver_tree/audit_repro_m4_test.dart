import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

/// Repro tests for M4: a comparator re-insert of an existing key must be
/// idempotent, and a changed-payload re-insert must land at the position
/// the NEW payload sorts to. The unfixed `_sortedIndex` is an upper-bound
/// search run with the node still in the list, so it counts the node's own
/// equal-comparing slot and reports `current + 1` (the key drifts one slot
/// right per re-insert), and because the caller overwrites the node's data
/// BEFORE searching, a changed payload breaks the sortedness the binary
/// search requires and yields an arbitrary position.
void main() {
  TreeController<String, String> makeSorted(
    WidgetTester tester, {
    TreeAnimationStyle animationStyle = TreeAnimationStyle.disabled,
  }) {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: animationStyle,
      comparator: (a, b) => a.data.compareTo(b.data),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  testWidgets("idempotent root re-insert keeps the sorted position", (
    tester,
  ) async {
    final sorted = makeSorted(tester);
    sorted.setRoots([
      const TreeNode(key: "a", data: "Apple"),
      const TreeNode(key: "b", data: "Banana"),
      const TreeNode(key: "c", data: "Cherry"),
    ]);
    expect(
      sorted.rootKeys,
      ["a", "b", "c"],
      reason: "setup sanity: the comparator must have ordered the roots",
    );

    int structural = 0;
    int dataFires = 0;
    sorted.addStructuralListener((_) => structural++);
    sorted.addNodeDataListener((_) => dataFires++);

    sorted.insertRoot(const TreeNode(key: "b", data: "Banana"));
    expect(
      sorted.rootKeys,
      ["a", "b", "c"],
      reason: "a re-insert with an identical payload must not move the key",
    );
    expect(
      structural,
      0,
      reason: "an idempotent re-insert is a data-only update",
    );
    expect(
      dataFires,
      1,
      reason: "the overwritten payload refreshes via the node-data channel",
    );

    sorted.insertRoot(const TreeNode(key: "b", data: "Banana"));
    expect(
      sorted.rootKeys,
      ["a", "b", "c"],
      reason: "repeating the re-insert must not oscillate",
    );
    expect(
      structural,
      0,
      reason: "the repeat is also a data-only update",
    );
  });

  testWidgets("idempotent child re-insert keeps the sorted position", (
    tester,
  ) async {
    final sorted = makeSorted(tester);
    sorted.setRoots([const TreeNode(key: "p", data: "Parent")]);
    sorted.setChildren("p", [
      const TreeNode(key: "a", data: "Apple"),
      const TreeNode(key: "b", data: "Banana"),
      const TreeNode(key: "c", data: "Cherry"),
    ]);
    sorted.expand(key: "p");
    expect(
      sorted.getChildren("p"),
      ["a", "b", "c"],
      reason: "setup sanity: the comparator must have ordered the children",
    );

    int structural = 0;
    sorted.addStructuralListener((_) => structural++);

    sorted.insert(
      parentKey: "p",
      node: const TreeNode(key: "b", data: "Banana"),
    );
    expect(
      sorted.getChildren("p"),
      ["a", "b", "c"],
      reason: "a re-insert with an identical payload must not move the key",
    );
    expect(
      structural,
      0,
      reason: "an idempotent re-insert is a data-only update",
    );

    sorted.insert(
      parentKey: "p",
      node: const TreeNode(key: "b", data: "Banana"),
    );
    expect(
      sorted.getChildren("p"),
      ["a", "b", "c"],
      reason: "repeating the re-insert must not oscillate",
    );
  });

  testWidgets("changed payload relocates to where the new data sorts", (
    tester,
  ) async {
    final sorted = makeSorted(tester);
    sorted.setRoots([
      const TreeNode(key: "a", data: "Apple"),
      const TreeNode(key: "b", data: "Banana"),
      const TreeNode(key: "c", data: "Cherry"),
    ]);
    expect(
      sorted.rootKeys,
      ["a", "b", "c"],
      reason: "setup sanity: the comparator must have ordered the roots",
    );

    int structural = 0;
    sorted.addStructuralListener((_) => structural++);

    // Payload moves toward the end. This is the plan's prescribed case; it
    // pins the contract but the unfixed code happens to land it correctly
    // too, so the to-front test below is the discriminator.
    sorted.insertRoot(const TreeNode(key: "b", data: "Zebra"));
    expect(
      sorted.rootKeys,
      ["a", "c", "b"],
      reason: "Zebra sorts after Cherry, so b must move to the end",
    );
    expect(
      structural,
      1,
      reason: "a genuine relocation fires exactly one structural refresh",
    );
  });

  testWidgets("changed payload sorting EARLIER relocates correctly", (
    tester,
  ) async {
    final sorted = makeSorted(tester);
    sorted.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
      const TreeNode(key: "c", data: "C"),
      const TreeNode(key: "d", data: "D"),
      const TreeNode(key: "e", data: "E"),
    ]);
    expect(
      sorted.rootKeys,
      ["a", "b", "c", "d", "e"],
      reason: "setup sanity: the comparator must have ordered the roots",
    );

    // "A0" sorts between "A" and "B", so c must land at index 1. The
    // unfixed binary search probes c's own already-overwritten slot,
    // walks the wrong way, and lands c at index 3 instead.
    sorted.insertRoot(const TreeNode(key: "c", data: "A0"));
    expect(
      sorted.rootKeys,
      ["a", "c", "b", "d", "e"],
      reason: "A0 sorts between A and B, so c must move to index 1",
    );
  });

  testWidgets(
    "re-insert with a pending-deletion sibling keeps the live order",
    (tester) async {
      // Default (enabled) animation style: the removal must leave the key
      // exiting so the comparator search takes its pending-deletion scan.
      final sorted = makeSorted(
        tester,
        animationStyle: const TreeAnimationStyle(),
      );
      sorted.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
        const TreeNode(key: "d", data: "D"),
      ]);
      expect(
        sorted.rootKeys,
        ["a", "b", "c", "d"],
        reason: "setup sanity: the comparator must have ordered the roots",
      );

      sorted.remove(key: "c");
      expect(
        sorted.isPendingDeletion("c"),
        isTrue,
        reason:
            "setup sanity: the animated removal must leave c exiting, "
            "which is what routes the comparator search to its "
            "pending-deletion scan",
      );
      expect(
        sorted.liveRootKeys,
        ["a", "b", "d"],
        reason: "setup sanity: live order before the re-insert",
      );

      sorted.insertRoot(const TreeNode(key: "b", data: "B"));
      expect(
        sorted.liveRootKeys,
        ["a", "b", "d"],
        reason:
            "an idempotent re-insert must not move b past d in live "
            "space; the unfixed scan counts b's own slot and reports the "
            "position after d",
      );

      // Let c's exit animation finish so no ticker outlives the test.
      await tester.pumpAndSettle();
    },
  );
}
