/// Regression tests for audit item 6.6: the `insert` / `insertRoot`
/// data-update branches (same key already present, no relocation) must
/// fire the node-data channel ONLY. Firing a structural notification for
/// the same key too refreshed the same row twice per update — the batch
/// path documents that structural subsumes data, and `updateNode`'s
/// contract is data-channel-only. Branches that actually relocate the
/// node keep the structural notification (positions changed).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "data-only insertRoot re-insert fires the node-data channel only",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);

      int structuralFires = 0;
      int dataFires = 0;
      controller.addStructuralListener((_) => structuralFires++);
      controller.addNodeDataListener((_) => dataFires++);

      // Same key, same live position, new payload — a pure data update.
      controller.insertRoot(const TreeNode(key: "a", data: "A2"), index: 0);
      expect(dataFires, 1);
      expect(
        structuralFires,
        0,
        reason: "no relocation happened — the node-data channel already "
            "refreshed the row; a structural notification would refresh "
            "it a second time (audit 6.6)",
      );
      expect(controller.getNodeData("a")!.data, "A2");

      // Relocation still notifies structurally.
      controller.insertRoot(const TreeNode(key: "a", data: "A3"), index: 1);
      expect(structuralFires, greaterThan(0),
          reason: "an actual relocation changes row positions");
      expect(controller.liveRootKeys, ["b", "a"]);

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "data-only insert re-insert fires the node-data channel only",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [
        const TreeNode(key: "c1", data: "C1"),
        const TreeNode(key: "c2", data: "C2"),
      ]);
      controller.expand(key: "p", animate: false);

      int structuralFires = 0;
      int dataFires = 0;
      controller.addStructuralListener((_) => structuralFires++);
      controller.addNodeDataListener((_) => dataFires++);

      controller.insert(
        parentKey: "p",
        node: const TreeNode(key: "c1", data: "C1-v2"),
        index: 0,
      );
      expect(dataFires, 1);
      expect(structuralFires, 0,
          reason: "no relocation — data channel only (audit 6.6)");
      expect(controller.getNodeData("c1")!.data, "C1-v2");

      controller.insert(
        parentKey: "p",
        node: const TreeNode(key: "c1", data: "C1-v3"),
        index: 1,
      );
      expect(structuralFires, greaterThan(0));
      expect(controller.getLiveChildren("p"), ["c2", "c1"]);

      await tester.pumpAndSettle();
    },
  );
}
