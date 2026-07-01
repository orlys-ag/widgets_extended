/// Tests for animated `TreeController.reorderChildren` / `reorderRoots`.
///
/// A same-parent reorder now stages a FLIP slide baseline (default
/// `animate: true`), like `moveNode`, so shifted rows slide to their new
/// positions instead of snapping. `animate: false` and a collapsed parent
/// (children not visible) install no slide.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Widget _buildHarness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: 48,
                  child: Padding(
                    padding: EdgeInsets.only(left: depth * 24.0),
                    child: Text(key),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group("reorderRoots animation", () {
    testWidgets("default (animate: true) slides shifted roots", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      // Rows at y = 0, 48, 96. Reorder to [b, c, a]: a moves 0 → 96,
      // slide delta = prior - new = -96.
      controller.reorderRoots(["b", "c", "a"]);
      await tester.pump();

      expect(controller.hasActiveSlides, true,
          reason: "reorderRoots default must stage a FLIP slide");
      expect(controller.getSlideDelta("a"), closeTo(-96.0, 1.0));

      await tester.pumpAndSettle();
      expect(controller.hasActiveSlides, false);
      expect(controller.getIndexInParent("a"), 2);
    });

    testWidgets("animate: false snaps (no slide)", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      controller.reorderRoots(["b", "a"], animate: false);
      await tester.pump();

      expect(controller.hasActiveSlides, false);
      expect(controller.getSlideDelta("a"), 0.0);
      expect(controller.getIndexInParent("a"), 1);
    });
  });

  group("reorderChildren animation", () {
    testWidgets(
        "default (animate: true) slides shifted children under an expanded parent",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "root", data: "R")]);
      controller.setChildren("root", [
        const TreeNode(key: "c1", data: "C1"),
        const TreeNode(key: "c2", data: "C2"),
        const TreeNode(key: "c3", data: "C3"),
      ]);
      controller.expand(key: "root", animate: false);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      // Rows: root(0), c1(48), c2(96), c3(144). Reorder children to
      // [c3, c1, c2]: c3 moves 144 → 48, slide delta = +96.
      controller.reorderChildren("root", ["c3", "c1", "c2"]);
      await tester.pump();

      expect(controller.hasActiveSlides, true,
          reason: "reorderChildren default must stage a FLIP slide");
      expect(controller.getSlideDelta("c3"), closeTo(96.0, 1.0));

      await tester.pumpAndSettle();
      expect(controller.hasActiveSlides, false);
      expect(controller.getIndexInParent("c3"), 0);
    });

    testWidgets("collapsed parent installs no slide (visibility gate)",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "root", data: "R")]);
      controller.setChildren("root", [
        const TreeNode(key: "c1", data: "C1"),
        const TreeNode(key: "c2", data: "C2"),
      ]);
      // root left collapsed → children not visible.
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      controller.reorderChildren("root", ["c2", "c1"]);
      await tester.pump();

      expect(controller.hasActiveSlides, false,
          reason: "a collapsed (invisible) reorder must not stage a baseline");
      // Structural reorder is still applied.
      expect(controller.getIndexInParent("c2"), 0);
    });

    testWidgets("animate: false snaps (no slide)", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "root", data: "R")]);
      controller.setChildren("root", [
        const TreeNode(key: "c1", data: "C1"),
        const TreeNode(key: "c2", data: "C2"),
      ]);
      controller.expand(key: "root", animate: false);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      controller.reorderChildren("root", ["c2", "c1"], animate: false);
      await tester.pump();

      expect(controller.hasActiveSlides, false);
      expect(controller.getSlideDelta("c2"), 0.0);
      expect(controller.getIndexInParent("c2"), 0);
    });
  });
}
