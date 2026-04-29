/// Verifies that extents (per-node, total scroll extent, prefix sums)
/// stay correct when multiple structural operations overlap:
///   • simultaneous remove + insert
///   • expand of one node while collapsing another
///   • cascading removes within an animation window
///   • scroll happening concurrently with animations
///   • subtree insert with un-measured children, then settling
///
/// All assertions are computed against the controller's measured-extent
/// cache and the render object's per-nid offset arrays. Sums must agree
/// with what the render reports as `geometry.scrollExtent`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/render_sliver_tree.dart';
import 'package:widgets_extended/widgets_extended.dart';

const double _rowH = 40.0;

Widget _harness({
  required TreeController<String, String> controller,
  ScrollController? scroll,
  double height = 200.0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (_, key, _) => SizedBox(
                height: _rowH,
                child: Text(key),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

RenderSliverTree<String, String> _renderOf(WidgetTester tester) {
  return tester.renderObject(find.byType(SliverTree<String, String>))
      as RenderSliverTree<String, String>;
}

double _liveScrollExtent(TreeController<String, String> controller) {
  double sum = 0.0;
  for (final k in controller.visibleNodes) {
    sum += controller.getCurrentExtent(k);
  }
  return sum;
}

double _settledScrollExtent(TreeController<String, String> controller) {
  double sum = 0.0;
  for (final k in controller.visibleNodes) {
    sum += controller.getEstimatedExtent(k);
  }
  return sum;
}

void main() {
  group("concurrent remove + insert", () {
    testWidgets("removing one root and inserting another simultaneously: "
        "geometry.scrollExtent matches sum of per-node animated extents "
        "throughout the animation", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        for (var i = 0; i < 5; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);

      await tester.pumpWidget(_harness(controller: controller));
      await tester.pumpAndSettle();

      final render = _renderOf(tester);
      // After settle, all rows measured at 40px each: 5 rows = 200.
      expect(render.geometry!.scrollExtent, closeTo(5 * _rowH, 0.5));

      controller.runBatch(() {
        controller.remove(key: "r2", animate: true);
        controller.insertRoot(const TreeNode(key: "rNew", data: "NEW"));
      });

      // Pump through the animation, asserting extent consistency at
      // each frame.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        // The render geometry must always equal the sum of per-node
        // animated extents — anything else means Pass 1 lost track of
        // some row's contribution.
        expect(
          render.geometry!.scrollExtent,
          closeTo(_liveScrollExtent(controller), 0.5),
          reason: "Frame $i: scrollExtent (${render.geometry!.scrollExtent}) "
              "vs live sum (${_liveScrollExtent(controller)})",
        );
      }

      await tester.pumpAndSettle();
      // After settle: r0, r1, r3, r4, rNew — 5 rows, 200px.
      expect(controller.visibleNodes.length, 5);
      expect(render.geometry!.scrollExtent, closeTo(5 * _rowH, 0.5));
      expect(controller.visibleNodes.toList(),
          equals(["r0", "r1", "r3", "r4", "rNew"]));
    });

    testWidgets("removing a child while inserting siblings under same "
        "parent: visible-subtree-size cache stays consistent",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [
        for (var i = 0; i < 4; i++) TreeNode(key: "c$i", data: "C$i"),
      ]);
      controller.expand(key: "p", animate: false);

      await tester.pumpWidget(_harness(controller: controller));
      await tester.pumpAndSettle();

      controller.runBatch(() {
        controller.remove(key: "c1", animate: true);
        controller.insert(parentKey: "p", node: const TreeNode(key: "cNew", data: "NEW"));
      });

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        controller.debugAssertVisibleSubtreeSizeConsistency();
      }

      await tester.pumpAndSettle();
      controller.debugAssertVisibleSubtreeSizeConsistency();
      expect(controller.getChildren("p"),
          equals(["c0", "c2", "c3", "cNew"]));
    });
  });

  group("concurrent expand + collapse", () {
    testWidgets("expand of one parent while collapsing another: "
        "scrollExtent equals the live per-node sum every frame",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("a", [
        for (var i = 0; i < 3; i++) TreeNode(key: "a$i", data: "A$i"),
      ]);
      controller.setChildren("b", [
        for (var i = 0; i < 3; i++) TreeNode(key: "b$i", data: "B$i"),
      ]);
      // 'a' starts expanded, 'b' starts collapsed.
      controller.expand(key: "a", animate: false);

      await tester.pumpWidget(
        _harness(controller: controller, height: 600),
      );
      await tester.pumpAndSettle();

      // Trigger both animations at once.
      controller.runBatch(() {
        controller.collapse(key: "a", animate: true);
        controller.expand(key: "b", animate: true);
      });

      final render = _renderOf(tester);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          render.geometry!.scrollExtent,
          closeTo(_liveScrollExtent(controller), 0.5),
          reason: "Frame $i mismatch — scrollExtent="
              "${render.geometry!.scrollExtent}, live="
              "${_liveScrollExtent(controller)}",
        );
        controller.debugAssertVisibleSubtreeSizeConsistency();
      }

      await tester.pumpAndSettle();
      // After settle: a collapsed, b expanded.
      expect(controller.visibleNodes.toList(),
          equals(["a", "b", "b0", "b1", "b2"]));
      expect(render.geometry!.scrollExtent, closeTo(5 * _rowH, 0.5));
    });
  });

  group("cascading removes", () {
    testWidgets("removing 5 siblings in quick succession: each finishes "
        "without leaving the cache inconsistent", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        for (var i = 0; i < 8; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);

      await tester.pumpWidget(
        _harness(controller: controller, height: 400),
      );
      await tester.pumpAndSettle();

      // Stagger 5 removes. Some overlap.
      for (var i = 0; i < 5; i++) {
        controller.remove(key: "r$i", animate: true);
        await tester.pump(const Duration(milliseconds: 8));
      }

      // Drain.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        controller.debugAssertVisibleSubtreeSizeConsistency();
      }

      await tester.pumpAndSettle();
      expect(controller.rootKeys, equals(["r5", "r6", "r7"]));
      controller.debugAssertVisibleSubtreeSizeConsistency();
    });
  });

  group("scroll concurrent with animations", () {
    testWidgets("scrolling during a remove animation: scrollExtent shrinks "
        "smoothly, position stays valid, no exception", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        for (var i = 0; i < 30; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);

      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      await tester.pumpWidget(
        _harness(controller: controller, scroll: scroll, height: 200),
      );
      await tester.pumpAndSettle();

      // Initial scrollExtent: rows in cache region are measured at 40px,
      // unmeasured rows contribute defaultExtent (48px). Don't assume
      // a specific total — just assert it matches the controller's
      // live sum.
      final render = _renderOf(tester);
      expect(render.geometry!.scrollExtent,
          closeTo(_liveScrollExtent(controller), 0.5));

      // Scroll partway, then start a remove. Continue scrolling during
      // the animation.
      scroll.jumpTo(400);
      await tester.pump();
      controller.remove(key: "r10", animate: true);

      for (var i = 0; i < 12; i++) {
        scroll.jumpTo(400 + i * 8.0);
        await tester.pump(const Duration(milliseconds: 8));
        // scrollExtent must always equal sum of live extents.
        expect(
          render.geometry!.scrollExtent,
          closeTo(_liveScrollExtent(controller), 0.5),
          reason: "Frame $i: scrollExtent vs live sum mismatch",
        );
      }

      await tester.pumpAndSettle();
      expect(controller.rootKeys.length, 29);
      // Same caveat about measured vs unmeasured rows post-settle.
      expect(render.geometry!.scrollExtent,
          closeTo(_liveScrollExtent(controller), 0.5));
    });
  });

  group("subtree insert with un-measured children", () {
    testWidgets("inserting a parent with 3 children: extents stabilize "
        "as children get measured frame-by-frame", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "r0", data: "R0")]);

      await tester.pumpWidget(_harness(controller: controller, height: 400));
      await tester.pumpAndSettle();

      final render = _renderOf(tester);
      expect(render.geometry!.scrollExtent, closeTo(_rowH, 0.5));

      // Add a new root with 3 children, then expand it.
      controller.runBatch(() {
        controller.insertRoot(const TreeNode(key: "p", data: "P"));
        controller.setChildren("p", [
          for (var i = 0; i < 3; i++) TreeNode(key: "p$i", data: "P$i"),
        ]);
        controller.expand(key: "p", animate: true);
      });

      // Pump to let entering animation run + render measure children.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        // No strict equality check here (extents transition through
        // unknown→measured), but invariant must hold.
        controller.debugAssertVisibleSubtreeSizeConsistency();
      }

      await tester.pumpAndSettle();
      // Final state: r0, p, p0, p1, p2 = 5 rows.
      expect(controller.visibleNodes.length, 5);
      expect(render.geometry!.scrollExtent, closeTo(5 * _rowH, 0.5));
      expect(_settledScrollExtent(controller), closeTo(5 * _rowH, 0.5));
    });
  });

  group("combined chaos", () {
    testWidgets("expand + remove + insert + scroll all overlapping: "
        "no extent drift, cache invariant holds, final state correct",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
        const TreeNode(key: "d", data: "D"),
      ]);
      controller.setChildren("a", [
        for (var i = 0; i < 3; i++) TreeNode(key: "a$i", data: "A$i"),
      ]);
      controller.setChildren("c", [
        for (var i = 0; i < 3; i++) TreeNode(key: "c$i", data: "C$i"),
      ]);

      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _harness(controller: controller, scroll: scroll, height: 300),
      );
      await tester.pumpAndSettle();

      // Kick off a soup of operations.
      controller.runBatch(() {
        controller.expand(key: "a", animate: true);
        controller.remove(key: "b", animate: true);
        controller.insertRoot(const TreeNode(key: "z", data: "Z"));
        controller.expand(key: "c", animate: true);
      });

      final render = _renderOf(tester);
      // Run through the animation while scrolling.
      for (var i = 0; i < 15; i++) {
        scroll.jumpTo(20.0 + i * 4.0);
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          render.geometry!.scrollExtent,
          closeTo(_liveScrollExtent(controller), 0.5),
          reason: "Frame $i drift",
        );
        controller.debugAssertVisibleSubtreeSizeConsistency();
      }

      await tester.pumpAndSettle();
      controller.debugAssertVisibleSubtreeSizeConsistency();
      // Final order: a, a0, a1, a2, c, c0, c1, c2, d, z. ('b' removed.)
      expect(controller.visibleNodes.toList(),
          equals(["a", "a0", "a1", "a2", "c", "c0", "c1", "c2", "d", "z"]));
      expect(render.geometry!.scrollExtent, closeTo(10 * _rowH, 0.5));
    });
  });
}
