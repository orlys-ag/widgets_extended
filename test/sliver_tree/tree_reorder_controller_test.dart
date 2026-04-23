import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Mounts a minimal SliverTree harness and returns `(scrollable, render)`.
class _Harness {
  _Harness({required this.controller});

  final TreeController<String, String> controller;

  Widget build() {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey(key),
                  height: 50,
                  child: Text("$key (d=$depth)"),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

ScrollableState _findScrollable(WidgetTester tester) {
  return tester.state<ScrollableState>(find.byType(Scrollable));
}

RenderSliverTree<String, String> _findRender(WidgetTester tester) {
  return tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
}

/// Converts a scroll-space y to a global pointer offset using the scrollable's
/// viewport render box so TreeReorderController's `_pointerToScrollSpaceY`
/// reverses it correctly.
Offset _scrollYToGlobal(ScrollableState scrollable, double scrollY) {
  final viewport = scrollable.context.findRenderObject() as RenderBox;
  // Pick a horizontal coordinate that is inside the viewport; use the center.
  final viewportLocalY = scrollY - scrollable.position.pixels;
  return viewport.localToGlobal(
    Offset(viewport.size.width / 2, viewportLocalY),
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group("Constructor validation", () {
    testWidgets("rejects comparator-based TreeController with ArgumentError",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
        comparator: (a, b) => a.key.compareTo(b.key),
      );
      addTearDown(controller.dispose);

      expect(
        () => TreeReorderController<String, String>(
          treeController: controller,
          vsync: tester,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    testWidgets("accepts a comparator-less TreeController", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      final reorder = TreeReorderController<String, String>(
        treeController: controller,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      expect(reorder.isDragging, false);
    });
  });

  group("startDrag validation", () {
    testWidgets("throws ArgumentError on cross-controller renderObject",
        (tester) async {
      final treeA = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(treeA.dispose);
      final treeB = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(treeB.dispose);

      treeB.setRoots([TreeNode(key: "x", data: "X")]);
      final reorder = TreeReorderController<String, String>(
        treeController: treeA,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      // Mount treeB's tree — get its render.
      await tester.pumpWidget(_Harness(controller: treeB).build());
      final renderB = _findRender(tester);
      final scrollable = _findScrollable(tester);

      expect(
        () => reorder.startDrag(
          key: "x",
          renderObject: renderB,
          scrollable: scrollable,
          indentPerDepth: 24.0,
          pointerGlobal: Offset.zero,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    testWidgets("throws ArgumentError when canReorder returns false",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([TreeNode(key: "a", data: "A")]);

      final reorder = TreeReorderController<String, String>(
        treeController: controller,
        vsync: tester,
        canReorder: (key) => false,
      );
      addTearDown(reorder.dispose);

      await tester.pumpWidget(_Harness(controller: controller).build());
      final render = _findRender(tester);
      final scrollable = _findScrollable(tester);

      expect(
        () => reorder.startDrag(
          key: "a",
          renderObject: render,
          scrollable: scrollable,
          indentPerDepth: 24.0,
          pointerGlobal: Offset.zero,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group("Drop target resolution", () {
    testWidgets("classifies above / into / below by vertical third",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ]);

      final reorder = TreeReorderController<String, String>(
        treeController: controller,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      await tester.pumpWidget(_Harness(controller: controller).build());
      await tester.pumpAndSettle();

      final render = _findRender(tester);
      final scrollable = _findScrollable(tester);

      // Rows: a[0..50], b[50..100], c[100..150]. Drag "c" and hover over
      // row "a" across its three zones. All three drop positions are real
      // structural changes (c is at index 2; above/into/below a yields
      // indexInFinalList 0 / 0 / 1, none of which equal 2).
      reorder.startDrag(
        key: "c",
        renderObject: render,
        scrollable: scrollable,
        indentPerDepth: 24.0,
        pointerGlobal: _scrollYToGlobal(scrollable, 10.0),
      );
      // Top third of a (y=10 in [0..50]) → above.
      expect(reorder.currentTarget?.zone, TreeDropZone.above);
      expect(reorder.currentTarget?.targetKey, "a");

      // Middle third → into.
      reorder.updateDrag(_scrollYToGlobal(scrollable, 25.0));
      expect(reorder.currentTarget?.zone, TreeDropZone.into);
      expect(reorder.currentTarget?.targetKey, "a");
      expect(reorder.currentTarget?.parentKey, "a");

      // Bottom third → below.
      reorder.updateDrag(_scrollYToGlobal(scrollable, 45.0));
      expect(reorder.currentTarget?.zone, TreeDropZone.below);
      expect(reorder.currentTarget?.targetKey, "a");

      reorder.cancelDrag();
    });

    testWidgets("cycle: drop-into-descendant rejected", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
      controller.setChildren("b", [TreeNode(key: "c", data: "C")]);
      controller.expand(key: "a");
      controller.expand(key: "b");

      final reorder = TreeReorderController<String, String>(
        treeController: controller,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      await tester.pumpWidget(_Harness(controller: controller).build());
      await tester.pumpAndSettle();

      final render = _findRender(tester);
      final scrollable = _findScrollable(tester);

      // Drag "a", hover in the middle of "b" (descendant): "into" would
      // reparent a under b, a cycle. Expect currentTarget == null.
      reorder.startDrag(
        key: "a",
        renderObject: render,
        scrollable: scrollable,
        indentPerDepth: 24.0,
        pointerGlobal: _scrollYToGlobal(scrollable, 75.0),
      );
      // Middle of b (y=75 in row [50..100]). With descendant check, "into"
      // is forbidden so the zone resolves to below; but below "b" would
      // reparent to b's parent (which is "a", the dragged) — also a cycle.
      // Expected: null target.
      expect(reorder.currentTarget, isNull);
      reorder.cancelDrag();
    });

    testWidgets("no-op: dropping at current position yields null target",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);

      final reorder = TreeReorderController<String, String>(
        treeController: controller,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      await tester.pumpWidget(_Harness(controller: controller).build());
      await tester.pumpAndSettle();

      final render = _findRender(tester);
      final scrollable = _findScrollable(tester);

      // Drag "a" and hover above "a" itself (its own current position at y=0)
      // — dropping above-self is a no-op.
      reorder.startDrag(
        key: "a",
        renderObject: render,
        scrollable: scrollable,
        indentPerDepth: 24.0,
        pointerGlobal: _scrollYToGlobal(scrollable, 5.0),
      );
      expect(reorder.currentTarget, isNull,
          reason: "drop above self should be filtered");
      reorder.cancelDrag();
    });

    testWidgets("canAcceptDrop policy filters targets", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);

      final reorder = TreeReorderController<String, String>(
        treeController: controller,
        vsync: tester,
        canAcceptDrop: ({required movingKey, newParent, index}) =>
            newParent != "b",
      );
      addTearDown(reorder.dispose);

      await tester.pumpWidget(_Harness(controller: controller).build());
      await tester.pumpAndSettle();

      final render = _findRender(tester);
      final scrollable = _findScrollable(tester);

      reorder.startDrag(
        key: "a",
        renderObject: render,
        scrollable: scrollable,
        indentPerDepth: 24.0,
        pointerGlobal: _scrollYToGlobal(scrollable, 75.0),
      );
      // "into b" would make newParent = b, rejected by canAcceptDrop.
      expect(reorder.currentTarget, isNull);
      reorder.cancelDrag();
    });
  });

  group("Commit paths", () {
    testWidgets("same-parent reorder routes through reorderRoots",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ]);

      final reorder = TreeReorderController<String, String>(
        treeController: controller,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      await tester.pumpWidget(_Harness(controller: controller).build());
      await tester.pumpAndSettle();

      final render = _findRender(tester);
      final scrollable = _findScrollable(tester);

      // Drag "a" to below "c" (y in [100..150], bottom third).
      reorder.startDrag(
        key: "a",
        renderObject: render,
        scrollable: scrollable,
        indentPerDepth: 24.0,
        pointerGlobal: _scrollYToGlobal(scrollable, 145.0),
      );
      expect(reorder.currentTarget?.zone, TreeDropZone.below);
      expect(reorder.currentTarget?.targetKey, "c");
      expect(reorder.currentTarget?.parentKey, null);

      // endDrag awaits _afterNextFrame; we must pump to let that callback fire.
      final future = reorder.endDrag();
      await tester.pump();
      await future;
      await tester.pumpAndSettle();

      expect(controller.visibleNodes, ["b", "c", "a"]);
    });

    testWidgets("cross-parent reorder routes through moveNode",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
      controller.expand(key: "a");

      final reorder = TreeReorderController<String, String>(
        treeController: controller,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      await tester.pumpWidget(_Harness(controller: controller).build());
      await tester.pumpAndSettle();

      final render = _findRender(tester);
      final scrollable = _findScrollable(tester);

      // Rows: a(0..50), a1(50..100), b(100..150).
      // Drag "a1" INTO "b" (middle of b, y=125).
      reorder.startDrag(
        key: "a1",
        renderObject: render,
        scrollable: scrollable,
        indentPerDepth: 24.0,
        pointerGlobal: _scrollYToGlobal(scrollable, 125.0),
      );
      expect(reorder.currentTarget?.zone, TreeDropZone.into);
      expect(reorder.currentTarget?.parentKey, "b");

      final future = reorder.endDrag();
      await tester.pump();
      await future;
      await tester.pumpAndSettle();

      // a1 should now be a child of b (not a).
      expect(controller.getParent("a1"), "b");
      expect(controller.getChildCount("a"), 0);
      expect(controller.getChildCount("b"), 1);
    });
  });

  group("Live-list correctness", () {
    testWidgets(
        "drop target resolution skips pending-deletion rows", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ]);

      final reorder = TreeReorderController<String, String>(
        treeController: controller,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      await tester.pumpWidget(_Harness(controller: controller).build());
      await tester.pumpAndSettle();

      // Start removing "b" — it becomes pending-deletion mid-animation.
      controller.remove(key: "b");
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.isPendingDeletion("b"), true);

      // Drop-target resolution: hover over where b is visually — it must
      // be skipped and the resolution should fall through to a live row.
      final render = _findRender(tester);
      final scrollable = _findScrollable(tester);

      reorder.startDrag(
        key: "a",
        renderObject: render,
        scrollable: scrollable,
        indentPerDepth: 24.0,
        // Hover near where "b" would be (y≈60). Resolution should NOT
        // produce "b" as a target.
        pointerGlobal: _scrollYToGlobal(scrollable, 60.0),
      );
      expect(reorder.currentTarget?.targetKey, isNot(equals("b")));
      reorder.cancelDrag();
      await tester.pumpAndSettle();
    });
  });
}
