/// Regression: when a still-entering row is reparented via
/// `moveNode(animate: true)`, the standalone enter animation must keep
/// running at the row's new structural position. Killing it on move
/// makes the row "snap" to full extent at its destination — visible to
/// the user as the row appearing without any growth animation.
library;

import "package:flutter_test/flutter_test.dart";
import "package:widgets_extended/sliver_tree/tree_controller.dart";
import "package:widgets_extended/sliver_tree/types.dart";

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets(
    "moveNode mid-enter-animation preserves the standalone enter state",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
      );
      addTearDown(controller.dispose);

      controller.runBatch(() {
        controller.setRoots(<TreeNode<String, String>>[
          const TreeNode(key: "A", data: "A"),
          const TreeNode(key: "B", data: "B"),
        ]);
        controller.setChildren("A", <TreeNode<String, String>>[
          const TreeNode(key: "A0", data: "A0"),
        ]);
        controller.expand(key: "A", animate: false);
        controller.expand(key: "B", animate: false);
      });

      // Fresh insert kicks off a standalone enter animation.
      controller.insert(
        parentKey: "A",
        node: const TreeNode(key: "X", data: "X"),
      );

      final entering = controller.getAnimationState("X");
      expect(entering, isNotNull,
          reason: "fresh insert(animate: true) should start a standalone "
              "enter animation");
      expect(entering!.type, AnimationType.entering);

      // Now reparent X to B while its enter animation is still running.
      // Currently this clears the standalone state via
      // _cancelAnimationStateForSubtree → _removeAnimation, leaving X
      // with no animation — so the user sees X "snap" to full size at
      // its new slot. The expected behavior is for X to keep entering
      // (its extent should continue growing under B).
      controller.moveNode("X", "B");

      final afterMove = controller.getAnimationState("X");
      expect(afterMove, isNotNull,
          reason: "moveNode must NOT kill an in-flight standalone enter — "
              "the row would otherwise snap to full extent at the new "
              "structural position");
      expect(afterMove!.type, AnimationType.entering);

      // Drain the standalone ticker so the test doesn't leak it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
    },
  );
}
