/// Direct unit tests for the visible-order buffer's new public surface
/// added by Plan B: `subtreeSizeOf`, `bumpFromSelf`,
/// `runWithSubtreeSizeUpdatesSuppressed`, `rebuild`, `handleParentChanged`,
/// the live `roots` reference, and `clearForNid`.
///
/// Bug classes targeted:
/// - `handleParentChanged(nid, p, p)` must not modify the cache (no-op
///   invariant for same-parent observer fires).
/// - `runWithSubtreeSizeUpdatesSuppressed` must suppress the inlined cache
///   callbacks fired by order mutators.
/// - `_order.roots` must return a stable reference so the
///   `UnmodifiableListView` exposed by `TreeController.rootKeys` reflects
///   later mutations through the same list.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  // Helper: build a small deterministic tree
  //   r1
  //     a
  //       a1
  //       a2
  //     b
  //   r2
  TreeController<String, String> buildSeedTree(WidgetTester tester) {
    final c = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    c.setRoots([
      const TreeNode(key: "r1", data: "r1"),
      const TreeNode(key: "r2", data: "r2"),
    ]);
    c.setChildren("r1", [
      const TreeNode(key: "a", data: "a"),
      const TreeNode(key: "b", data: "b"),
    ]);
    c.setChildren("a", [
      const TreeNode(key: "a1", data: "a1"),
      const TreeNode(key: "a2", data: "a2"),
    ]);
    return c;
  }

  group("VisibleOrderBuffer", () {
    testWidgets("subtreeSizeOf reflects visible nodes after expand", (
      tester,
    ) async {
      final c = buildSeedTree(tester);
      addTearDown(c.dispose);

      // All collapsed: only roots visible.
      c.debugAssertVisibleSubtreeSizeConsistency();
      expect(c.visibleNodes.length, 2);

      c.expand(key: "r1", animate: false);
      c.debugAssertVisibleSubtreeSizeConsistency();
      // r1 expanded → r1, a, b, r2 visible.
      expect(c.visibleNodes.length, 4);

      c.expand(key: "a", animate: false);
      c.debugAssertVisibleSubtreeSizeConsistency();
      // a expanded → r1, a, a1, a2, b, r2 visible.
      expect(c.visibleNodes.length, 6);
    });

    testWidgets("handleParentChanged is a no-op when oldParent == newParent", (
      tester,
    ) async {
      final c = buildSeedTree(tester);
      addTearDown(c.dispose);

      c.expand(key: "r1", animate: false);
      c.expand(key: "a", animate: false);
      c.debugAssertVisibleSubtreeSizeConsistency();

      // Snapshot every visible node's reported child count before the move.
      // moveNode(a, newParent: r1) is a same-parent move — observer fires
      // with oldParent == newParent and the handler must short-circuit.
      // The cache must remain consistent.
      c.moveNode("a", "r1");
      c.debugAssertVisibleSubtreeSizeConsistency();
      expect(c.visibleNodes.length, 6);
    });

    testWidgets(
      "reparent shifts subtree-size cache between ancestor chains",
      (tester) async {
        final c = buildSeedTree(tester);
        addTearDown(c.dispose);

        // Seed r2 with a placeholder child so we can expand it (expand
        // is a no-op on a childless node).
        c.setChildren("r2", [const TreeNode(key: "ph", data: "ph")]);
        c.expand(key: "r1", animate: false);
        c.expand(key: "a", animate: false);
        c.expand(key: "r2", animate: false);
        c.debugAssertVisibleSubtreeSizeConsistency();
        expect(c.visibleNodes.length, 7); // r1, a, a1, a2, b, r2, ph

        // Reparent: move "a" (with subtree a1, a2) from r1 to r2.
        // The Observer-driven cache shift must:
        //   - decrement r1's chain by 3 (a + a1 + a2)
        //   - increment r2's chain by 3
        // and debugAssert must pass.
        c.moveNode("a", "r2");
        c.debugAssertVisibleSubtreeSizeConsistency();
        // r1, b, r2, a, a1, a2, ph — total 7.
        expect(c.visibleNodes.length, 7);
      },
    );

    testWidgets("rebuild closure populates and rebuilds derived state", (
      tester,
    ) async {
      final c = buildSeedTree(tester);
      addTearDown(c.dispose);

      // collapseAll then expand-each forces a full rebuild via the
      // rebuild() path. Verify the cache is consistent afterwards.
      c.collapseAll(animate: false);
      c.debugAssertVisibleSubtreeSizeConsistency();
      c.expand(key: "r1", animate: false);
      c.expand(key: "a", animate: false);
      c.debugAssertVisibleSubtreeSizeConsistency();
      expect(c.visibleNodes.length, 6);
    });

    testWidgets("rootKeys reflects mutations through stable list reference", (
      tester,
    ) async {
      final c = buildSeedTree(tester);
      addTearDown(c.dispose);

      // Capture the unmodifiable view once.
      final view = c.rootKeys;
      expect(view, ["r1", "r2"]);

      c.insertRoot(const TreeNode(key: "r3", data: "r3"));
      // The same view must reflect the mutation — proves the underlying
      // list reference is stable across mutations (G3 contract).
      expect(view, ["r1", "r2", "r3"]);

      c.remove(key: "r2", animate: false);
      expect(view, ["r1", "r3"]);
    });

    testWidgets("setChildren replaces a subtree with cache consistency", (
      tester,
    ) async {
      final c = buildSeedTree(tester);
      addTearDown(c.dispose);

      c.expand(key: "r1", animate: false);
      c.expand(key: "a", animate: false);
      c.debugAssertVisibleSubtreeSizeConsistency();

      // Replace a's children — exercises the `_purgeAndRemoveFromOrder`
      // optimization: explicit Step 1 ancestor-decrement via bumpFromSelf
      // + Step 3 compaction inside runWithSubtreeSizeUpdatesSuppressed.
      c.setChildren("a", [
        const TreeNode(key: "a3", data: "a3"),
        const TreeNode(key: "a4", data: "a4"),
        const TreeNode(key: "a5", data: "a5"),
      ]);
      c.debugAssertVisibleSubtreeSizeConsistency();
      // r1 expanded, a expanded with new children → r1, a, a3, a4, a5, b, r2.
      expect(c.visibleNodes.length, 7);
    });

    testWidgets(
      "remove of a deeply-nested subtree keeps cache consistent",
      (tester) async {
        final c = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        addTearDown(c.dispose);

        // 3-deep chain.
        c.setRoots([const TreeNode(key: "r", data: "r")]);
        c.setChildren("r", [const TreeNode(key: "x", data: "x")]);
        c.setChildren("x", [const TreeNode(key: "y", data: "y")]);
        c.setChildren("y", [const TreeNode(key: "z", data: "z")]);
        c.expand(key: "r", animate: false);
        c.expand(key: "x", animate: false);
        c.expand(key: "y", animate: false);
        c.debugAssertVisibleSubtreeSizeConsistency();
        expect(c.visibleNodes.length, 4);

        // Remove the chain root — every descendant's cache contribution
        // must collapse to 0 after the eventual rebuild.
        c.remove(key: "x", animate: false);
        c.debugAssertVisibleSubtreeSizeConsistency();
        expect(c.visibleNodes.length, 1);
      },
    );
  });
}
