/// Verifies that swapping the [TreeController] on a live [SliverTree]
/// produces a clean transition: the old controller's nodes are no longer
/// painted/hit-tested, the new controller's nodes are, and no orphan
/// RenderBoxes remain adopted in the render object's child map.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/render_sliver_tree.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("swapping controllers between two trees with overlapping keys "
      "rebuilds rows against the new controller's data", (tester) async {
    final controllerA = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controllerA.dispose);
    controllerA.setRoots([
      const TreeNode(key: "shared", data: "DATA-FROM-A"),
      const TreeNode(key: "onlyA", data: "ONLY-A"),
    ]);

    final controllerB = TreeController<String, String>(
      vsync: tester,
      animationDuration: Duration.zero,
    );
    addTearDown(controllerB.dispose);
    controllerB.setRoots([
      const TreeNode(key: "shared", data: "DATA-FROM-B"),
      const TreeNode(key: "onlyB", data: "ONLY-B"),
    ]);

    final ValueNotifier<TreeController<String, String>> active =
        ValueNotifier(controllerA);
    addTearDown(active.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<TreeController<String, String>>(
          valueListenable: active,
          builder: (_, controller, _) {
            return CustomScrollView(slivers: [
              SliverTree<String, String>(
                controller: controller,
                nodeBuilder: (_, key, _) {
                  final data = controller.getNodeData(key)?.data ?? "<gone>";
                  return SizedBox(height: 40, child: Text("$key=$data"));
                },
              ),
            ]);
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Sanity: A is rendered.
    expect(find.text("shared=DATA-FROM-A"), findsOneWidget);
    expect(find.text("onlyA=ONLY-A"), findsOneWidget);
    expect(find.text("shared=DATA-FROM-B"), findsNothing);
    expect(find.text("onlyB=ONLY-B"), findsNothing);

    // Swap to B.
    active.value = controllerB;
    await tester.pumpAndSettle();

    // The "shared" key exists in both controllers but with different data —
    // the row must rebuild against B's data.
    expect(find.text("shared=DATA-FROM-A"), findsNothing,
        reason: "Old data leaked through after controller swap");
    expect(find.text("shared=DATA-FROM-B"), findsOneWidget,
        reason: "Shared key did not rebuild against new controller's data");
    // OnlyA must be evicted; OnlyB must appear.
    expect(find.text("onlyA=ONLY-A"), findsNothing,
        reason: "Stale 'onlyA' from the old controller is still painted");
    expect(find.text("onlyB=ONLY-B"), findsOneWidget,
        reason: "New 'onlyB' from the swapped controller did not render");

    // No orphan RenderBoxes: every adopted child of the render object must
    // have a corresponding live entry in the new controller.
    final renderObject =
        tester.renderObject(find.byType(SliverTree<String, String>))
            as RenderSliverTree<String, String>;
    for (final key in const ["shared", "onlyB"]) {
      expect(renderObject.getChildForNode(key), isNotNull,
          reason: "Render object lost track of '$key' after swap");
    }
    expect(renderObject.getChildForNode("onlyA"), isNull,
        reason: "Stale render box for 'onlyA' still adopted by render object");
  });
}
