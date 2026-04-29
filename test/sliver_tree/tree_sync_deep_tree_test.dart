/// Verifies that [TreeSyncController]'s tracking-state helpers do not
/// stack-overflow on deep linear chains. Several helpers recurse:
/// `_clearChildrenTracking`, `_rememberExpansionRecursive`,
/// `initializeTracking.trackChildren`. A 20k-deep chain exceeds Dart's
/// default stack frame limit when recursing one frame per node.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("TreeSyncController.initializeTracking does not "
      "stack-overflow on a 20k-deep chain", (tester) async {
    final controller = TreeController<int, int>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    // Build a 20000-deep linear chain: 0 → 1 → 2 → ... → 19999
    const depth = 20000;
    controller.setRoots([const TreeNode(key: 0, data: 0)]);
    for (var i = 0; i < depth - 1; i++) {
      controller.setChildren(i, [TreeNode(key: i + 1, data: i + 1)]);
    }

    final sync = TreeSyncController<int, int>(treeController: controller);
    addTearDown(sync.dispose);

    // initializeTracking walks the tree recursively. On a 20k-deep chain
    // this would overflow with one stack frame per node.
    expect(sync.initializeTracking, returnsNormally,
        reason: "initializeTracking stack-overflowed on a 20k-deep chain — "
            "trackChildren needs to be iterative.");
  });

  testWidgets("TreeSyncController.syncRoots removal of a 20k-deep chain "
      "does not stack-overflow in _rememberExpansion / "
      "_clearChildrenTracking", (tester) async {
    final controller = TreeController<int, int>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);

    const depth = 20000;
    controller.setRoots([const TreeNode(key: 0, data: 0)]);
    for (var i = 0; i < depth - 1; i++) {
      controller.setChildren(i, [TreeNode(key: i + 1, data: i + 1)]);
    }

    final sync = TreeSyncController<int, int>(treeController: controller);
    addTearDown(sync.dispose);
    sync.initializeTracking();

    // Now sync to an EMPTY root list. This triggers:
    //   - _rememberExpansion(0) → _rememberExpansionRecursive — recursive
    //   - _clearChildrenTracking(0) — recursive
    expect(
      () => sync.syncRoots(<TreeNode<int, int>>[], animate: false),
      returnsNormally,
      reason: "syncRoots removal of a 20k-deep chain stack-overflowed in "
          "_rememberExpansionRecursive or _clearChildrenTracking.",
    );
  });
}
