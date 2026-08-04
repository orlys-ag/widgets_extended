import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Regression repro for finding f42: `_pointerToScrollSpaceY` converts the
/// global pointer to `position.pixels + viewportLocal.dy` (viewport scroll
/// space), but `findRowAtPaintedY` consumes sliver-LOCAL offsets that start
/// at 0 for the first tree row. The two spaces differ by the tree sliver's
/// `precedingScrollExtent`. With any sliver mounted above the tree, the
/// resolved drop target is `precedingScrollExtent` below the row the pointer
/// is actually over.
///
/// This harness mounts a 200px SliverToBoxAdapter ABOVE the tree, then hovers
/// the real painted center of row "a". Correct behavior: the drop target is
/// "a". Buggy behavior: the target resolves 200px lower (row "e").
class _Harness {
  _Harness({required this.controller, required this.headerHeight});

  final TreeController<String, String> controller;
  final double headerHeight;

  Widget build() {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: headerHeight,
                child: const Text("header"),
              ),
            ),
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

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets(
    "f42: drop target resolves the row under the pointer when a sliver "
    "precedes the tree",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
        TreeNode(key: "d", data: "D"),
        TreeNode(key: "e", data: "E"),
      ]);

      final reorder = TreeReorderController<String>(
        treeController: controller,
        vsync: tester,
      );
      addTearDown(reorder.dispose);

      await tester.pumpWidget(
        _Harness(controller: controller, headerHeight: 200.0).build(),
      );
      await tester.pumpAndSettle();

      final render = _findRender(tester);
      final scrollable = _findScrollable(tester);

      // Sanity: the multi-sliver path is really exercised — row "a" paints
      // BELOW the 200px header, and the scroll offset is 0.
      expect(scrollable.position.pixels, 0.0);
      final rowACenter = tester.getCenter(find.text("a (d=0)"));
      expect(
        rowACenter.dy,
        225.0,
        reason: "row a (50px tall) must paint directly below the 200px "
            "header, so its painted center sits at viewport y=225",
      );

      // Hover the real painted center of row "a" while dragging "c".
      // Any zone over row "a" (above/into/below) is a valid, non-no-op
      // target for dragged "c", so the resolved targetKey must be "a".
      reorder.startDrag(
        key: "c",
        renderPort: render,
        scrollable: scrollable,
        pointerGlobal: rowACenter,
      );
      addTearDown(() {
        if (reorder.isDragging) {
          reorder.cancelDrag();
        }
      });

      expect(
        reorder.currentTarget,
        isNotNull,
        reason: "the pointer is over a live row, so a target must resolve",
      );
      expect(
        reorder.currentTarget?.targetKey,
        "a",
        reason: "the pointer hovers the painted center of row 'a'; the "
            "resolved drop target must be 'a', not a row "
            "precedingScrollExtent (200px) lower",
      );

      // Mirrored coordinate bug, post-D2 shape: the semantic target's
      // `targetPaintedY` is SLIVER-LOCAL (row a at 0, NOT 200 — a target
      // built from unconverted viewport scroll space would report 200),
      // and the widget layer derives the viewport-scroll-space indicator
      // edge by adding the port's precedingScrollExtent back: the `into`
      // indicator sits at the row's bottom edge, 200px header + 50px row
      // = 250 in viewport scroll space.
      expect(reorder.currentTarget?.zone, TreeDropZone.into,
          reason: "row center resolves the into zone for a valid target");
      expect(
        reorder.currentTarget?.targetPaintedY,
        0.0,
        reason: "targetPaintedY is sliver-local: row a is the first tree "
            "row regardless of the 200px preceding sliver",
      );
      expect(
        reorder.renderPort?.precedingScrollExtent,
        200.0,
        reason: "the port must expose the preceding sliver's extent — the "
            "widget layer's indicator derivation depends on it",
      );
      final t = reorder.currentTarget!;
      expect(
        t.targetPaintedY + t.targetExtent +
            reorder.renderPort!.precedingScrollExtent,
        250.0,
        reason: "derived indicator edge must account for the 200px "
            "preceding sliver (row a's bottom edge in viewport scroll "
            "space)",
      );

      reorder.cancelDrag();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
