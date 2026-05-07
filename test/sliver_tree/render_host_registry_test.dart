/// Tests for Phase 0 render-host registry lifecycle.
///
/// Verifies registry membership across attach, detach, controller swap,
/// dispose, and multi-sliver scenarios. Uses indirect verification via
/// the public moveNode(animate: true) entry point — it fan-outs to all
/// hosts and the resulting hasActiveSlides reflects participation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Widget _harness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 400,
        child: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  height: 40,
                  child: Text(key),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _twoSliverHarness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 400,
        child: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) =>
                  SizedBox(height: 40, child: Text("a-$key")),
            ),
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) =>
                  SizedBox(height: 40, child: Text("b-$key")),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets("attach registers a host; detach unregisters", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
    ]);

    // No sliver mounted yet.
    controller.moveNode("a", null, index: 1, animate: true);
    expect(controller.hasActiveSlides, false,
        reason: "no host registered → no slide installed");

    // Mount a sliver.
    controller.moveNode("a", null, index: 0); // restore order
    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    // Now host is registered; animated move should install slide.
    controller.moveNode(
      "a",
      null,
      index: 1,
      animate: true,
      slideDuration: const Duration(milliseconds: 200),
      slideCurve: Curves.linear,
    );
    await tester.pump();
    expect(controller.hasActiveSlides, true,
        reason: "after attach, animated move installs a slide");
    await tester.pumpAndSettle();

    // Unmount.
    await tester.pumpWidget(const SizedBox.shrink());

    // Host unregistered: animated move is a no-op again.
    controller.moveNode("a", null, index: 0, animate: true);
    expect(controller.hasActiveSlides, false,
        reason: "after detach, no host → no slide");
  });

  testWidgets("two slivers register independently", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 200),
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
    ]);

    await tester.pumpWidget(_twoSliverHarness(controller));
    await tester.pumpAndSettle();

    // With two slivers attached, animated move still installs (each sliver
    // calls beginSlideBaseline; first-wins makes them coalesce into one
    // pending baseline per sliver, both consume on next layout).
    controller.moveNode(
      "a",
      null,
      index: 1,
      animate: true,
      slideDuration: const Duration(milliseconds: 200),
      slideCurve: Curves.linear,
    );
    await tester.pump();
    expect(controller.hasActiveSlides, true);

    await tester.pumpAndSettle();
  });

  testWidgets("registry survives controller swap", (tester) async {
    final controllerA = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 200),
    );
    final controllerB = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 200),
    );
    addTearDown(controllerA.dispose);
    addTearDown(controllerB.dispose);

    controllerA.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
    ]);
    controllerB.setRoots([
      const TreeNode(key: "x", data: "X"),
      const TreeNode(key: "y", data: "Y"),
    ]);

    await tester.pumpWidget(_harness(controllerA));
    await tester.pumpAndSettle();

    // A has the host registered.
    controllerA.moveNode(
      "a",
      null,
      index: 1,
      animate: true,
      slideDuration: const Duration(milliseconds: 200),
      slideCurve: Curves.linear,
    );
    await tester.pump();
    expect(controllerA.hasActiveSlides, true);
    await tester.pumpAndSettle();

    // Swap to B.
    await tester.pumpWidget(_harness(controllerB));
    await tester.pumpAndSettle();

    // A no longer has the host; animated move on A is a no-op.
    controllerA.moveNode("a", null, index: 0, animate: true);
    expect(controllerA.hasActiveSlides, false,
        reason: "after swap, controller A has no host");

    // B has the host now; animated move on B installs slide.
    controllerB.moveNode(
      "x",
      null,
      index: 1,
      animate: true,
      slideDuration: const Duration(milliseconds: 200),
      slideCurve: Curves.linear,
    );
    await tester.pump();
    expect(controllerB.hasActiveSlides, true,
        reason: "after swap, controller B has the host");

    await tester.pumpAndSettle();
  });

  testWidgets("dispose-before-detach is safe", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 200),
    );
    controller.setRoots([
      const TreeNode(key: "a", data: "A"),
    ]);

    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    // Dispose while still mounted. Then unmount.
    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    // Pass condition: no exception thrown.
  });
}
