/// Indirect tests for `NodeStore.onParentChanged` (the Plan B Observer
/// hook). `NodeStore` itself is library-private, so we exercise the
/// callback through `TreeController`'s public mutation API and verify the
/// effects on the visible-subtree-size cache.
///
/// What this exercises:
/// - Every `setParent` write fires the callback (validated indirectly via
///   the cache's correctness after reparent operations).
/// - `setParent(key, sameParent)` — the Observer fires, but
///   `handleParentChanged` short-circuits when `oldParent == newParent`,
///   leaving the cache untouched.
/// - `dispose()` clears the closure → `_order` reference cycle (covered
///   by addTearDown not throwing).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "setParent fires onParentChanged: cache shifts on reparent",
    (tester) async {
      final c = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(c.dispose);

      c.setRoots([
        const TreeNode(key: "p1", data: "p1"),
        const TreeNode(key: "p2", data: "p2"),
      ]);
      c.setChildren("p1", [const TreeNode(key: "n", data: "n")]);
      c.setChildren("n", [
        const TreeNode(key: "n1", data: "n1"),
        const TreeNode(key: "n2", data: "n2"),
      ]);
      // Give p2 a placeholder child so we can expand it (expand is a
      // no-op on a childless node), then expand both subtrees.
      c.setChildren("p2", [const TreeNode(key: "ph", data: "ph")]);
      c.expand(key: "p1");
      c.expand(key: "n");
      c.expand(key: "p2");
      c.debugAssertVisibleSubtreeSizeConsistency();
      expect(c.visibleNodes.toList(), ["p1", "n", "n1", "n2", "p2", "ph"]);

      // Reparent n (subtree size 3) from p1 to p2.
      // The Observer subscriber must shift the cache from p1's chain to
      // p2's chain. Cache invariant must hold afterward, regardless of
      // index ordering inside p2's child list.
      c.moveNode("n", "p2");
      c.debugAssertVisibleSubtreeSizeConsistency();
      // p2 still expanded; n + n1 + n2 + ph all visible under p2.
      expect(c.visibleNodes.length, 6); // p1, p2, n, n1, n2, ph (order varies)
    },
  );

  testWidgets(
    "setParent(key, sameParent) is a cache no-op (handler short-circuits)",
    (tester) async {
      final c = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(c.dispose);

      c.setRoots([const TreeNode(key: "p", data: "p")]);
      c.setChildren("p", [
        const TreeNode(key: "a", data: "a"),
        const TreeNode(key: "b", data: "b"),
        const TreeNode(key: "c", data: "c"),
      ]);
      c.expand(key: "p", animate: false);
      c.debugAssertVisibleSubtreeSizeConsistency();
      expect(c.visibleNodes.length, 4);

      // Reorder within same parent — the underlying setParent calls
      // (if any) fire the observer with oldParent == newParent. The
      // handler must short-circuit; the cache must remain consistent.
      c.reorderChildren("p", const ["c", "b", "a"]);
      c.debugAssertVisibleSubtreeSizeConsistency();
      expect(c.visibleNodes.length, 4);
    },
  );

  testWidgets(
    "dispose clears Observer wiring without throwing",
    (tester) async {
      final c = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      // Drive at least one mutation so the wiring is established.
      c.setRoots([const TreeNode(key: "r", data: "r")]);
      c.setChildren("r", [const TreeNode(key: "x", data: "x")]);
      // dispose() should clear `_store.onParentChanged` and run cleanly.
      c.dispose();
    },
  );
}
