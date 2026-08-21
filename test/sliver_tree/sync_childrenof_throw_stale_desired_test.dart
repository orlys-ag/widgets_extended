/// Regression (B1, 2026-08-16 bugfix plan): a `syncRoots(childrenOf:)`
/// call that throws during `childrenOf` validation must not leave
/// `TreeSyncController`'s internal desired-descendants set populated.
///
/// The leaked set is consulted by `syncChildren`'s removal loop ("defer
/// removal of nodes desired under a different parent"), so on unfixed
/// code every later `syncChildren` silently skips removing any key that
/// happened to enter the set before the throw fired, until the next
/// successful `syncRoots(childrenOf:)` overwrites it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "syncChildren removals survive a childrenOf validation throw",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(sync.dispose);

      // Seed: root p with child x.
      sync.syncRoots([const TreeNode(key: "p", data: "p")]);
      sync.syncChildren("p", [const TreeNode(key: "x", data: "x")]);
      expect(controller.getChildren("p"), ["x"]);

      // Throwing sync: desired [r] with childrenOf shaped so "x" enters
      // the desired-descendants set BEFORE the duplicate is detected:
      // r -> [x], x -> [x] (x repeats while visiting x's children).
      expect(
        () => sync.syncRoots(
          [const TreeNode(key: "r", data: "r")],
          childrenOf: (key) {
            if (key == "r" || key == "x") {
              return [const TreeNode(key: "x", data: "x")];
            }
            return const [];
          },
        ),
        throwsArgumentError,
        reason:
            "setup sanity: the cyclic childrenOf must be rejected; the "
            "repro depends on the throw firing after x was collected",
      );

      // Setup sanity: the throw fired before any mutation, so the tree
      // is untouched.
      expect(
        controller.rootKeys,
        ["p"],
        reason: "setup sanity: the failed sync must not mutate roots",
      );
      expect(
        controller.getChildren("p"),
        ["x"],
        reason: "setup sanity: the failed sync must not mutate children",
      );

      // EXPECTED (correct) behavior: a later syncChildren removal works.
      // On unfixed code the leaked desired-descendants set still contains
      // "x", the removal loop's deferral check skips it, and x survives.
      sync.syncChildren("p", const []);
      expect(
        controller.getChildren("p"),
        isEmpty,
        reason:
            "x must be removed; a stale desired-descendants set from the "
            "failed syncRoots(childrenOf:) must not defer its removal",
      );
    },
  );
}
