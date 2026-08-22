/// Regression test for issue 2 of the 2026-08-21 review: the no-slides
/// fast path of [RenderSliverTree.findRowAtPaintedY] read layout caches
/// that a structural mutation had already invalidated.
///
/// `_nodeOffsetsByNid` and the bulk cumulatives are written during
/// `performLayout`. A mutation between two frames leaves both describing
/// the OLD visible order, and the fast path had no freshness guard (the
/// slide branch has one). The caller is `DragProbe` at drag start and on
/// every pointer move, so the payload is grab geometry and the drop slot:
/// a pointer event that lands between a stream-driven mutation and the
/// next frame either threw (bulk cumulative shorter than the new visible
/// count) or answered with a recycled nid's previous occupant's offset.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

Future<RenderSliverTree<String, String>> _mount(
  WidgetTester tester,
  TreeController<String, String> controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(height: 48, child: Text(key));
              },
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
}

void main() {
  testWidgets("a mutation during a bulk animation does not leave the fast "
      "path indexing a stale cumulative", (tester) async {
    final controller = TreeController<String, String>(vsync: tester);
    addTearDown(controller.dispose);
    controller.setRoots([
      for (int i = 0; i < 10; i++) TreeNode(key: "r$i", data: "R$i"),
    ]);
    for (int i = 0; i < 10; i++) {
      controller.setChildren("r$i", [TreeNode(key: "r$i-c", data: "C")]);
    }
    final render = await _mount(tester, controller);

    controller.expandAll(animate: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      controller.isBulkAnimating,
      isTrue,
      reason: "setup: the bulk fast path is what caches the cumulatives",
    );

    // Grow the visible order past the cumulative's length, with no layout
    // in between: exactly the window a pointer event can land in.
    for (int i = 0; i < 30; i++) {
      controller.insertRoot(
        TreeNode(key: "n$i", data: "N$i"),
        index: 0,
        animate: false,
      );
    }
    expect(
      controller.hasActiveSlides,
      isFalse,
      reason: "setup: this is the no-slides branch, not the bounded scan",
    );

    // Threw `RangeError (length): Invalid value: Not in inclusive range
    // 0..20: 21` before the fix.
    final row = render.findRowAtPaintedY(960);
    expect(row, equals(render.debugFindRowFullScan(960)));
    expect(
      render.debugLastFindRowUsedFullScan,
      isTrue,
      reason: "a stale frame must route to the full scan",
    );

    // The bulk group's ticker is still running; let it settle so the test
    // binding's active-ticker check passes.
    await tester.pumpAndSettle();
  });

  testWidgets("a purge-and-recycle before the next layout does not answer "
      "with the recycled nid's previous occupant", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      for (int i = 0; i < 10; i++) TreeNode(key: "r$i", data: "R$i"),
    ]);
    final render = await _mount(tester, controller);

    // Immediate removal releases nids; the inserts recycle them, so the
    // new keys inherit offset slots describing the OLD rows.
    for (int i = 0; i < 3; i++) {
      controller.remove(key: "r$i");
    }
    for (int i = 0; i < 3; i++) {
      controller.insertRoot(TreeNode(key: "n$i", data: "N$i"), index: i);
    }

    // Answered `n0 @ 96.0` (r2's old slot) before the fix.
    final row = render.findRowAtPaintedY(10);
    expect(row?.key, "n0");
    expect(row?.paintedOffset, 0.0);
    expect(row, equals(render.debugFindRowFullScan(10)));
  });

  testWidgets("a settled frame still takes the fast path", (tester) async {
    // Control: the guard must not push every lookup onto the O(N) scan.
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      for (int i = 0; i < 30; i++) TreeNode(key: "r$i", data: "R$i"),
    ]);
    final render = await _mount(tester, controller);

    final row = render.findRowAtPaintedY(100);
    expect(row?.key, "r2");
    expect(
      render.debugLastFindRowUsedFullScan,
      isFalse,
      reason: "a fresh frame must stay on the binary-search fast path",
    );
  });
}
