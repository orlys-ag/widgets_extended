/// D5 repro tests: the drop target must stay honest when the viewport
/// scrolls WITHOUT a pointer move, and autoscroll must engage when the
/// drag starts inside an edge zone.
///
/// Repro-test methodology: each test asserts the EXPECTED behavior and
/// fails on pre-D5 code, where re-resolution is driven only by pointer
/// moves and autoscroll ticks.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Future<({TreeController<String, String> tree, TreeReorderController<String> reorder})>
    _mount(WidgetTester tester, {int rowCount = 40}) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  tree.setRoots([
    for (var i = 0; i < rowCount; i++) TreeNode(key: "r$i", data: "R$i"),
  ]);

  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
  );
  addTearDown(() {
    if (reorder.isDragging) {
      reorder.cancelDrag();
    }
    reorder.dispose();
    tree.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              nodeBuilder: (context, key, depth, wrap) {
                return wrap(
                  longPressToDrag: true,
                  child: SizedBox(
                    key: ValueKey("row-$key"),
                    height: 50,
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
  await tester.pumpAndSettle();
  return (tree: tree, reorder: reorder);
}

void main() {
  testWidgets(
    "external scroll mid-drag re-resolves the drop target under the "
    "stationary pointer",
    (tester) async {
      final h = await _mount(tester);
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );

      // Long-press r0, then move the pointer to the middle of r2
      // (viewport y=125 → scroll-space y=125 at pixels=0 → into-r2).
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey("row-r0"))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveTo(const Offset(400, 125));
      await tester.pump();

      expect(h.reorder.currentTarget?.targetKey, "r2",
          reason: "setup: pointer over the middle of r2 resolves into-r2");

      // The user scrolls with the wheel/trackpad — the POINTER DOES NOT
      // MOVE, but the content under it does: scroll-space y becomes
      // 125 + 100 = 225 → the middle of r4.
      scrollable.position.jumpTo(100.0);
      await tester.pump();

      expect(
        h.reorder.currentTarget?.targetKey,
        "r4",
        reason: "after an external 100px scroll the stationary pointer "
            "hovers r4; a stale r2 target means scroll does not "
            "re-resolve",
      );

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );

  // REMOVED with the drop-indicator line: "external scroll mid-drag
  // repositions the indicator even when the semantic target survives".
  // It pinned a widget-layer mechanism — the indicator overlay re-deriving
  // its viewport position from `position.pixels` — that no longer exists.
  // There is no equivalent under make-room: the gap is a per-node paint
  // offset that rides the content automatically (covered by
  // `make_room_preview_test.dart`), and with the gap open the pointer sits
  // at a slot boundary, so no scroll of any size leaves the target intact
  // to assert against. The re-resolve-on-scroll contract itself is covered
  // by the test above.

  testWidgets(
    "a drag starting inside the edge zone autoscrolls without any "
    "pointer move",
    (tester) async {
      final h = await _mount(tester, rowCount: 100);
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );

      // Scroll deep so upward autoscroll has runway, then long-press a
      // row whose center sits INSIDE the top 48px edge zone.
      scrollable.position.jumpTo(1000.0);
      await tester.pump();

      // r20 spans scroll-space 1000..1050 → viewport-local 0..50; its
      // center (y=25) is inside the top edge zone.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey("row-r20"))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      expect(h.reorder.isDragging, isTrue,
          reason: "setup: the long press started a session");

      // Hold perfectly still and pump frames. The pointer is in the edge
      // zone from the very first moment — autoscroll must engage without
      // waiting for a pointer move.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(
        scrollable.position.pixels,
        lessThan(1000.0),
        reason: "a drag born inside the edge zone must autoscroll; "
            "requiring a first pointer move leaves the session parked",
      );

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );
}
