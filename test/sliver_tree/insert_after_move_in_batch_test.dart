/// Regression: inside a single [runBatch], a [moveNode] marks the
/// visible order dirty but defers the rebuild. A subsequent [insert]
/// reads the stale `_order.indexOf(parent) + subtreeSizeOf(parent)` and
/// can pass an invalid index to `VisibleOrderBuffer.insertNid`, which
/// fails with a `RangeError` inside `Int32List.setRange`.
///
/// Reproduces the crash observed in the
/// `SectionedCommandReplayExample` "End-of-quarter shuffle" preset
/// (reparent → add → remove in one runBatch).
library;

import 'package:widgets_extended/sliver_tree/animation_style.dart';
import "package:flutter_test/flutter_test.dart";
import "package:widgets_extended/sliver_tree/tree_controller.dart";
import "package:widgets_extended/sliver_tree/types.dart";

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets(
    "moveNode then insert in the same runBatch does not crash",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);

      controller.runBatch(() {
        controller.setRoots(<TreeNode<String, String>>[
          TreeNode(key: "A", data: "A"),
          TreeNode(key: "B", data: "B"),
        ]);
        controller.setChildren("A", <TreeNode<String, String>>[
          for (int i = 0; i < 4; i++)
            TreeNode(key: "A$i", data: "A$i"),
        ]);
        controller.setChildren("B", <TreeNode<String, String>>[
          for (int i = 0; i < 4; i++)
            TreeNode(key: "B$i", data: "B$i"),
        ]);
        controller.expand(key: "A", animate: false);
        controller.expand(key: "B", animate: false);
      });

      expect(controller.visibleNodeCount, 10);

      // The "End-of-quarter shuffle" pattern: reparent some children,
      // then insert new ones — all inside one runBatch.
      controller.runBatch(() {
        controller.moveNode("A0", "B");
        controller.moveNode("A1", "B");
        controller.moveNode("A2", "B");
        controller.insert(
          parentKey: "B",
          node: TreeNode(key: "B_new", data: "B_new"),
        );
      });

      expect(controller.visibleNodeCount, 11);
      expect(controller.getChildren("B"), contains("B_new"));
    },
  );

  testWidgets(
    "insert after moveNode reads fresh subtree-size cache",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);

      // 6 sections × 4 leaves — mirrors the example's startup shape.
      controller.runBatch(() {
        controller.setRoots(<TreeNode<String, String>>[
          for (int s = 0; s < 6; s++)
            TreeNode(key: "S$s", data: "S$s"),
        ]);
        for (int s = 0; s < 6; s++) {
          controller.setChildren("S$s", <TreeNode<String, String>>[
            for (int i = 0; i < 4; i++)
              TreeNode(key: "S${s}_$i", data: "S${s}_$i"),
          ]);
          controller.expand(key: "S$s", animate: false);
        }
      });
      expect(controller.visibleNodeCount, 6 + 6 * 4);

      // Reparent several children, then insert into one of the affected
      // sections. The original crash was a RangeError thrown by
      // _orderNids.setRange because insert read a stale subtree size.
      controller.runBatch(() {
        controller.moveNode("S0_0", "S5");
        controller.moveNode("S0_1", "S5");
        controller.moveNode("S0_2", "S5");
        controller.moveNode("S1_0", "S2");
        controller.moveNode("S1_1", "S4");
        controller.moveNode("S1_2", "S3");
        controller.insert(
          parentKey: "S5",
          node: TreeNode(key: "S5_new", data: "S5_new"),
        );
        controller.insert(
          parentKey: "S0",
          node: TreeNode(key: "S0_new", data: "S0_new"),
        );
      });

      expect(controller.visibleNodeCount, 6 + 6 * 4 + 2);
    },
  );
}
