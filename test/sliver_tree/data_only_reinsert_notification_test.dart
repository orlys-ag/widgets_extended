/// Regression tests for audit item 6.6 and review item R3: the `insert` /
/// `insertRoot` data-update branches (same key already present) must obey
/// "structural subsumes data — never fire both for one row":
///
/// - No relocation → node-data channel ONLY (6.6; `updateNode` contract).
/// - Same-parent relocation → structural (`affectedKeys: {key}`) ONLY —
///   the 6.6 change left the data fire before the relocate decision, so
///   the relocation path still refreshed the row twice (R3).
/// - Different-parent (moveNode delegation) → the data fire must SURVIVE:
///   moveNode's targeted structural `affectedKeys` omits the moved key on
///   an equal-depth move, so the data channel is the only refresh path
///   for the overwritten payload.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "data-only insertRoot re-insert fires the node-data channel only",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
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
      expect(
        dataFires,
        1,
        reason: "the relocation's structural notification carries the key "
            "in affectedKeys and subsumes the data channel's row refresh "
            "— firing both refreshes the same row twice (R3)",
      );
      expect(controller.getNodeData("a")!.data, "A3",
          reason: "the overwritten payload must land via the structural "
              "refresh alone");

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "data-only insert re-insert fires the node-data channel only",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
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
      expect(
        dataFires,
        1,
        reason: "same-parent relocation is structural-only — the data "
            "channel firing too refreshes the same row twice (R3)",
      );
      expect(controller.getNodeData("c1")!.data, "C1-v3");

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "cross-parent re-insert at equal depth (moveNode delegation) keeps "
    "the data-channel fire — the moved row must show the new payload",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "p1", data: "P1"),
        const TreeNode(key: "p2", data: "P2"),
      ]);
      controller.setChildren("p1", [
        const TreeNode(key: "x", data: "X-old"),
      ]);
      // p2 needs a pre-existing child: expanding a childless parent does
      // not stick, and the moved row must land VISIBLE for the
      // widget-level assertion below to mean anything.
      controller.setChildren("p2", [
        const TreeNode(key: "y", data: "Y"),
      ]);
      controller.expand(key: "p1", animate: false);
      controller.expand(key: "p2", animate: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return SizedBox(
                      height: 40,
                      child: Text(controller.getNodeData(key)!.data),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("X-old"), findsOneWidget);

      int dataFires = 0;
      controller.addNodeDataListener((_) => dataFires++);

      final depthBefore = controller.getDepth("x");
      controller.insert(
        parentKey: "p2",
        node: const TreeNode(key: "x", data: "X-new"),
        index: 0,
        animate: false,
      );

      // Setup sanity: this exercised the equal-depth moveNode delegation
      // — the path where moveNode's targeted structural affectedKeys
      // omits the moved key, leaving the data channel as the only refresh
      // path for the overwritten payload.
      expect(controller.getParent("x"), "p2");
      expect(controller.getDepth("x"), depthBefore,
          reason: "setup: the move must be depth-preserving");
      expect(controller.visibleNodes, contains("x"),
          reason: "setup: the moved row must stay visible — otherwise the "
              "widget-level payload assertion below is vacuous");

      expect(dataFires, greaterThan(0),
          reason: "the moveNode-delegation branch must keep its data fire "
              "(R3 moves the fire AFTER the relocate decision on the "
              "same-parent paths only)");
      await tester.pumpAndSettle();
      expect(find.text("X-new"), findsOneWidget,
          reason: "the mounted row must rebuild with the new payload");
      expect(find.text("X-old"), findsNothing);
    },
  );
}
