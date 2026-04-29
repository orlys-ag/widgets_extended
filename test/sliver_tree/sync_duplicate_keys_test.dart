/// Regression: `TreeSyncController.syncRoots` / `syncChildren` must reject
/// duplicate keys in the desired list, mirroring the validation
/// `TreeController.setRoots` / `setChildren` already perform.
///
/// Without the guard, a desired list like `[a, a]` silently corrupts the
/// sync controller's internal tracking state: `_currentRoots` ends up
/// holding two `a` entries even though `desiredSet.difference(currentSet)`
/// dedupes to one. Subsequent sync passes then loop with stale
/// duplicates, double-firing Fenwick updates and producing wrong
/// insertion offsets.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("syncRoots rejects duplicate desired keys", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);
    final sync = TreeSyncController<String, String>(
      treeController: controller,
    );
    addTearDown(sync.dispose);

    expect(
      () => sync.syncRoots([
        TreeNode(key: "a", data: "1"),
        TreeNode(key: "a", data: "2"),
      ]),
      throwsArgumentError,
      reason: "syncRoots must reject duplicate keys — silently accepting "
          "them leaves _currentRoots with stale duplicate entries.",
    );
  });

  testWidgets("syncChildren rejects duplicate desired keys", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controller.dispose);
    final sync = TreeSyncController<String, String>(
      treeController: controller,
    );
    addTearDown(sync.dispose);

    sync.syncRoots([TreeNode(key: "p", data: "p")]);

    expect(
      () => sync.syncChildren("p", [
        TreeNode(key: "x", data: "1"),
        TreeNode(key: "x", data: "2"),
      ]),
      throwsArgumentError,
      reason: "syncChildren must reject duplicate keys — same rationale as "
          "syncRoots.",
    );
  });
}
