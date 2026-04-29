/// Targeted regression for the operation-group dismissed handler when
/// `pendingRemoval` contains a mix of:
///   - category (1): nodes in `_pendingDeletion` (full purge)
///   - category (2): nodes only being hidden because their ancestors
///     finished collapsing (no purge)
///
/// The unified `_purgeAndRemoveFromOrder` helper is applied only to
/// category (1); category (2) routes through the batched
/// `_removeFromVisibleOrder` directly. This test exercises both
/// happening simultaneously inside one operation group.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "dismissed handler: collapse + remove on same animation completes "
    "without cache desync",
    (tester) async {
      final c = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 80),
      );
      addTearDown(c.dispose);

      // Build a tree:
      //   r
      //   ├── a (will be collapsed, animating its children out)
      //   │   ├── a1
      //   │   └── a2 (will be REMOVED mid-collapse → category (1))
      //   └── b
      c.setRoots([const TreeNode(key: "r", data: "r")]);
      c.setChildren("r", [
        const TreeNode(key: "a", data: "a"),
        const TreeNode(key: "b", data: "b"),
      ]);
      c.setChildren("a", [
        const TreeNode(key: "a1", data: "a1"),
        const TreeNode(key: "a2", data: "a2"),
      ]);
      c.expand(key: "r", animate: false);
      c.expand(key: "a", animate: false);
      await tester.pump();

      // Start animated collapse of `a`. While the collapse is in flight,
      // a2 will leave the visible order via category (2) (ancestor
      // collapse). Then mid-flight, schedule a real removal of a1 →
      // category (1) when its own exit animation completes.
      c.collapse(key: "a", animate: true);

      // Halfway through, force a real removal of a1.
      await tester.pump(const Duration(milliseconds: 40));
      c.remove(key: "a1", animate: true);

      // Let everything settle.
      await tester.pumpAndSettle();

      // Tree should now be: r ─ a (collapsed, children only a2 left), b.
      // The cache must still be consistent enough that an insert under
      // r computes a valid index.
      c.insert(
        parentKey: "r",
        node: const TreeNode(key: "fresh", data: "fresh"),
        animate: false,
      );

      expect(c.getChildren("r"), contains("fresh"));
      expect(c.getChildren("a"), equals(["a2"]));
      // The debug invariant must hold.
      c.debugAssertVisibleSubtreeSizeConsistency();
    },
  );

  testWidgets(
    "dismissed handler: pending-deletion sibling and pending-hide "
    "sibling under same parent both clear correctly",
    (tester) async {
      final c = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 60),
      );
      addTearDown(c.dispose);

      c.setRoots([const TreeNode(key: "r", data: "r")]);
      c.setChildren("r", [
        const TreeNode(key: "p", data: "p"),
      ]);
      c.setChildren("p", [
        const TreeNode(key: "x", data: "x"),
        const TreeNode(key: "y", data: "y"),
        const TreeNode(key: "z", data: "z"),
      ]);
      c.expand(key: "r", animate: false);
      c.expand(key: "p", animate: false);
      await tester.pump();

      // Collapse p (pending-hide for x, y, z) and remove y (pending-deletion).
      c.collapse(key: "p", animate: true);
      c.remove(key: "y", animate: true);
      await tester.pumpAndSettle();

      // After settle: p collapsed, x and z still children of p, y gone.
      expect(c.getChildren("p"), equals(["x", "z"]));
      c.debugAssertVisibleSubtreeSizeConsistency();

      // Re-expand p and verify x, z are visible.
      c.expand(key: "p", animate: false);
      await tester.pump();
      expect(c.visibleNodes, equals(["r", "p", "x", "z"]));
      c.debugAssertVisibleSubtreeSizeConsistency();
    },
  );
}
