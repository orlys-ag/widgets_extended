import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

// Audit repro for finding f32:
// A single syncRoots(childrenOf:) that both reparents a child OUT of parent
// r1 (to r2, which is DFS-processed after r1) and reorders r1's remaining
// siblings must complete without throwing and leave the controller in the
// desired state. On buggy code, step 1 of _syncChildrenImpl defers the
// removal of "a" (it is globally desired under r2), so "a" is still a live
// child of r1 when step 5 calls reorderChildren(r1, [c, b]) — whose
// all-build-modes validation throws ArgumentError because the ordered keys
// do not contain exactly r1's current live children {a, b, c}.
void main() {
  testWidgets(
    "f32: reparenting a child out of a parent whose remaining siblings are "
    "reordered in the same sync succeeds and yields the desired tree",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      final sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      // Initial state: roots [r1, r2]; r1 -> [a, b, c]; r2 -> [].
      sync.syncRoots(
        [
          TreeNode(key: "r1", data: "R1"),
          TreeNode(key: "r2", data: "R2"),
        ],
        childrenOf: (key) {
          if (key == "r1") {
            return [
              TreeNode(key: "a", data: "A"),
              TreeNode(key: "b", data: "B"),
              TreeNode(key: "c", data: "C"),
            ];
          }
          return [];
        },
        animate: false,
      );

      // Sanity: setup landed as expected.
      expect(controller.getChildren("r1"), ["a", "b", "c"]);
      expect(controller.getParent("a"), "r1");

      // One sync that both moves "a" from r1 to r2 AND swaps b/c under r1.
      // Expected (correct) behavior: no throw, tree matches desired state.
      sync.syncRoots(
        [
          TreeNode(key: "r1", data: "R1"),
          TreeNode(key: "r2", data: "R2"),
        ],
        childrenOf: (key) {
          if (key == "r1") {
            return [
              TreeNode(key: "c", data: "C"),
              TreeNode(key: "b", data: "B"),
            ];
          }
          if (key == "r2") {
            return [TreeNode(key: "a", data: "A")];
          }
          return [];
        },
        animate: false,
      );

      expect(controller.getChildren("r1"), ["c", "b"]);
      expect(controller.getChildren("r2"), ["a"]);
      expect(controller.getParent("a"), "r2");
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
