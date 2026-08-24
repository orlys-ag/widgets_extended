import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Regression tests for M21: the same-parent relocation branch of
/// [TreeController.insertRoot] / [TreeController.insert] must notify the
/// full sibling refresh set (every sibling, plus the parent for the child
/// case), not only the moved key. The displaced siblings' rendered inputs
/// (index in parent, first/last, sibling count) changed too; a one-element
/// set leaves their mounted rows stale.
void main() {
  TreeController<String, String> makeController(WidgetTester tester) {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  testWidgets("root relocation notifies every displaced sibling", (
    tester,
  ) async {
    final controller = makeController(tester);
    controller.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
      const TreeNode(key: "c", data: "C"),
    ]);
    expect(
      controller.getIndexInParent("a"),
      0,
      reason: "setup sanity: a starts at index 0",
    );

    final captured = <Set<String>?>[];
    controller.addStructuralListener(captured.add);

    controller.insertRoot(const TreeNode(key: "c", data: "C"), index: 0);
    expect(
      controller.liveRootKeys,
      ["c", "a", "b"],
      reason: "setup sanity: the re-insert must really relocate c",
    );
    expect(
      captured.length,
      1,
      reason: "a relocation fires exactly one structural notification",
    );
    expect(
      captured.single,
      unorderedEquals(<String>{"a", "b", "c"}),
      reason:
          "every root shifted by the relocation must be in affectedKeys, "
          "not only the moved key",
    );
  });

  testWidgets("child relocation notifies the siblings and the parent", (
    tester,
  ) async {
    final controller = makeController(tester);
    controller.setRoots([const TreeNode(key: "p", data: "P")]);
    controller.setChildren("p", [
      const TreeNode(key: "x", data: "X"),
      const TreeNode(key: "y", data: "Y"),
      const TreeNode(key: "z", data: "Z"),
    ]);
    controller.expand(key: "p");
    expect(
      controller.getIndexInParent("x"),
      0,
      reason: "setup sanity: x starts at index 0",
    );

    final captured = <Set<String>?>[];
    controller.addStructuralListener(captured.add);

    controller.insert(
      parentKey: "p",
      node: const TreeNode(key: "z", data: "Z"),
      index: 0,
    );
    expect(
      controller.getLiveChildren("p"),
      ["z", "x", "y"],
      reason: "setup sanity: the re-insert must really relocate z",
    );
    expect(
      captured.length,
      1,
      reason: "a relocation fires exactly one structural notification",
    );
    expect(
      captured.single,
      unorderedEquals(<String>{"p", "x", "y", "z"}),
      reason:
          "the child case additionally carries the parent, whose "
          "child-list order changed",
    );
  });

  testWidgets("displaced rows re-render their index labels", (tester) async {
    final controller = makeController(tester);
    controller.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
      const TreeNode(key: "c", data: "C"),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverTree<String, String>(
                controller: controller,
                nodeBuilder: (context, key, depth) {
                  return SizedBox(
                    height: 48,
                    child: Text("$key:${controller.getIndexInParent(key)}"),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      find.text("a:0"),
      findsOneWidget,
      reason: "setup sanity: initial index labels rendered",
    );
    expect(find.text("b:1"), findsOneWidget, reason: "setup sanity");
    expect(find.text("c:2"), findsOneWidget, reason: "setup sanity");

    controller.insertRoot(const TreeNode(key: "c", data: "C"), index: 0);
    await tester.pump();

    expect(
      find.text("c:0"),
      findsOneWidget,
      reason: "the moved row re-renders at its new index",
    );
    expect(
      find.text("a:1"),
      findsOneWidget,
      reason:
          "row a was displaced by the relocation and must re-render its "
          "index label",
    );
    expect(
      find.text("b:2"),
      findsOneWidget,
      reason:
          "row b was displaced by the relocation and must re-render its "
          "index label",
    );
  });

  testWidgets("batched relocations join the deferred token path", (
    tester,
  ) async {
    final controller = makeController(tester);
    controller.setRoots([const TreeNode(key: "p", data: "P")]);
    controller.setChildren("p", [
      for (int i = 0; i < 5; i++) TreeNode(key: "c$i", data: "C$i"),
    ]);
    controller.expand(key: "p");

    final captured = <Set<String>?>[];
    controller.addStructuralListener(captured.add);
    controller.debugSiblingRefreshSetBuilds = 0;

    controller.runBatch(() {
      controller.insert(
        parentKey: "p",
        node: const TreeNode(key: "c4", data: "C4"),
        index: 0,
      );
      controller.insert(
        parentKey: "p",
        node: const TreeNode(key: "c3", data: "C3"),
        index: 0,
      );
    });

    expect(
      controller.getLiveChildren("p"),
      ["c3", "c4", "c0", "c1", "c2"],
      reason: "setup sanity: both relocations ran",
    );
    expect(
      controller.debugSiblingRefreshSetBuilds,
      1,
      reason:
          "in-batch relocations record a token; the refresh set is built "
          "once per distinct parent at batch exit",
    );
    expect(
      captured.length,
      1,
      reason: "the batch coalesces to one structural fire",
    );
    expect(
      captured.single,
      unorderedEquals(<String>{"p", "c0", "c1", "c2", "c3", "c4"}),
      reason:
          "the exit-time set carries the parent and every sibling, not "
          "only the two moved keys",
    );
  });
}
