/// Regression for the contiguous fast path in `_removeFromVisibleOrder`
/// leaking a zombie entry into the visible order.
///
/// `_finalizeAnimation`'s deletion branch `_purgeNodeData`s a node —
/// releasing its nid and clearing its reverse-index slot — but deliberately
/// leaves the stale `_orderNids` entry in place, deferring the compaction to
/// the caller's batched `_removeFromVisibleOrder`. That batch mixes the
/// already-purged key with still-live keys (e.g. a node finishing a
/// non-deletion exit animation because an ancestor collapsed).
///
/// The contiguous fast path removes an index *range*; it locates keys only
/// through the reverse index, so a purged key (reverse index already
/// cleared) is invisible to it. When the live keys in the batch are
/// contiguous, the fast path fired and removed only them, leaving the purged
/// key's entry behind as a zombie. `debugAssertConsistent` did not catch it:
/// the post-removal `reindexFrom` re-establishes a self-consistent (but
/// wrong) reverse index for the freed nid whenever the zombie lands inside
/// the reindexed suffix. Once that freed nid was later recycled, the
/// duplicate `_orderNids` slot drove unmatched subtree-size cache decrements
/// and the cache eventually underflowed (`subtree-size would go negative`).
///
/// The fix routes any batch containing a not-currently-visible key through
/// the non-contiguous full-scan path, whose `removeWhereKeyIn` sweeps every
/// zombie via its null-key check.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "standalone finalize batch mixing a purged node with a collapse-exit "
    "node does not leak a zombie order entry",
    (tester) async {
      final c = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 60),
      );
      addTearDown(c.dispose);

      // root
      // ├── A            (collapsed; will be expand-animated then collapsed)
      // │   ├── leaf1
      // │   └── B        (collapsed; expanded NON-animated mid-flight)
      // │       └── C
      // └── victim       (genuinely removed)
      c.setRoots([const TreeNode(key: "root", data: "root")]);
      c.setChildren("root", [
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "victim", data: "victim"),
      ]);
      c.setChildren("A", [
        const TreeNode(key: "leaf1", data: "leaf1"),
        const TreeNode(key: "B", data: "B"),
      ]);
      c.setChildren("B", [
        const TreeNode(key: "C", data: "C"),
      ]);
      c.expand(key: "root", animate: false);
      await tester.pump();
      expect(c.visibleNodes, equals(["root", "A", "victim"]));

      // All in one frame, before any pump:
      //  1. animate-expand A   → operation group G_A = {leaf1, B}
      //  2. NON-animated expand B → C enters the order at full extent, in
      //     no animation group
      //  3. animate-collapse A → Path 1 reverses G_A; C (a visible
      //     descendant outside G_A) gets a standalone *non-deletion* exit
      //     animation and stays in the visible order
      //  4. remove victim      → standalone *pending-deletion* exit
      c.expand(key: "A", animate: true);
      c.expand(key: "B", animate: false);
      c.collapse(key: "A", animate: true);
      c.remove(key: "victim", animate: true);

      // When C's and victim's exit animations finalize on the same tick,
      // `_onStandaloneTickComplete` batches {victim, C} into one
      // `_removeFromVisibleOrder`: victim is purged (kNotVisible), C is
      // still in the order. The buggy contiguous fast path removes C by
      // index and leaks victim's stale entry.
      await tester.pumpAndSettle();

      // A is collapsed and victim is gone — the only visible rows are
      // root and A. A leaked zombie inflates this count.
      expect(c.visibleNodeCount, equals(2));
      expect(c.visibleNodes, equals(["root", "A"]));
      expect(c.getChildren("root"), equals(["A"]));
      c.debugAssertVisibleSubtreeSizeConsistency();

      // Re-expanding A must restore exactly its (still-intact) subtree.
      c.expand(key: "A", animate: false);
      c.expand(key: "B", animate: false);
      await tester.pump();
      expect(c.visibleNodes, equals(["root", "A", "leaf1", "B", "C"]));
      c.debugAssertVisibleSubtreeSizeConsistency();
    },
  );
}
