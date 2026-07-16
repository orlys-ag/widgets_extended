/// Regression test for S059: when app code calls
/// `controller.cancelDrag()` directly (NOT via the widget's gesture
/// handlers), the local UI in `_SliverReorderableTreeState` must clear
/// — `_draggedKey` reset and the drop indicator removed.
///
/// Before the fix, the state class never subscribed to the reorder
/// controller; only the gesture handlers cleared `_draggedKey`. An
/// external `cancelDrag()` cleared the controller's `_session` but
/// left the row dimmed at `draggedOpacity` indefinitely.
///
/// The fix adds an `initState`/`didUpdateWidget`/`dispose` lifecycle
/// for a controller listener that calls `_onDragEnd` when the session
/// ends from outside the gesture path.
library;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

const _kIndicatorColor = Color(0xFF00B0FF);

double _opacityOf(WidgetTester tester, String rowKey) {
  final op = tester.widget<Opacity>(
    find.ancestor(
      of: find.byKey(ValueKey("row-$rowKey")),
      matching: find.byType(Opacity),
    ),
  );
  return op.opacity;
}

Future<({TreeController<String, String> tree, TreeReorderController<String, String> reorder})>
    _mount(WidgetTester tester) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationDuration: Duration.zero,
  );
  tree.setRoots([
    const TreeNode(key: "a", data: "A"),
    const TreeNode(key: "b", data: "B"),
    const TreeNode(key: "c", data: "C"),
  ]);

  final reorder = TreeReorderController<String, String>(
    treeController: tree,
    vsync: tester,
    slideDuration: const Duration(milliseconds: 80),
    slideCurve: Curves.linear,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              draggedOpacity: 0.3,
              dropIndicatorColor: _kIndicatorColor,
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

  addTearDown(() {
    reorder.dispose();
    tree.dispose();
  });

  return (tree: tree, reorder: reorder);
}

void main() {
  testWidgets(
    "external cancelDrag clears local UI state (S059)",
    (tester) async {
      final h = await _mount(tester);

      // Start a drag via the gesture system. After this, _draggedKey is
      // set internally and row "a" should be dimmed.
      final rowACenter = tester.getCenter(find.byKey(const ValueKey("row-a")));
      final gesture = await tester.startGesture(rowACenter);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();

      // Sanity: drag is active.
      expect(_opacityOf(tester, "a"), 0.3,
          reason: "Mid-drag, row 'a' must be dimmed");
      expect(h.reorder.isDragging, isTrue);

      // External cancel — bypasses the gesture system entirely.
      h.reorder.cancelDrag();
      await tester.pump();

      // S059 assertion: local UI clears even though the gesture
      // wasn't released.
      expect(
        _opacityOf(tester, "a"),
        1.0,
        reason: "External cancelDrag() must clear _draggedKey via the "
            "state's controller listener (S059). Without the fix, "
            "the row stays dimmed at draggedOpacity indefinitely.",
      );

      // Clean up the held gesture so the test framework doesn't
      // complain about unfinished gestures.
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "a released first gesture must not commit a DIFFERENT drag session "
    "started after an external cancel",
    (tester) async {
      final h = await _mount(tester);

      // Finger 1 long-press-drags row "a".
      final rowACenter = tester.getCenter(find.byKey(const ValueKey("row-a")));
      final gesture = await tester.startGesture(rowACenter);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      expect(h.reorder.draggedKey, "a");

      // External cancel — clears the controller session, but the ROW's
      // local _isDraggingThisRow flag is untouched.
      h.reorder.cancelDrag();
      await tester.pump();
      expect(h.reorder.isDragging, isFalse);

      // A second session starts (e.g. a second finger long-pressed row
      // "b"). Hover row "c" so the session resolves a real drop target.
      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      h.reorder.startDrag(
        key: "b",
        renderObject: render,
        scrollable: scrollable,
        indentPerDepth: 24.0,
        pointerGlobal:
            tester.getCenter(find.byKey(const ValueKey("row-c"))),
      );
      expect(h.reorder.draggedKey, "b");
      expect(h.reorder.currentTarget, isNotNull,
          reason: "setup: session 2 must have a live drop target so a "
              "stale forwarded endDrag would visibly commit it");
      final orderBefore = List.of(h.tree.visibleNodes);

      // Finger 1 releases. Row "a"'s _endDrag must verify ownership
      // (draggedKey == its key) and NOT forward endDrag — otherwise it
      // commits SESSION 2's target and tears down its indicator.
      await gesture.up();
      await tester.pump();

      expect(h.reorder.isDragging, isTrue,
          reason: "session 2 must survive the release of the stale "
              "first gesture");
      expect(h.reorder.draggedKey, "b");
      expect(h.tree.visibleNodes, orderBefore,
          reason: "session 2's target must not be committed by the "
              "unrelated released gesture");

      h.reorder.cancelDrag();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "controller swap moves listener to the new controller",
    (tester) async {
      // Sanity test for the didUpdateWidget swap path.
      final tree = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(tree.dispose);
      tree.setRoots([const TreeNode(key: "x", data: "X")]);

      final reorderA = TreeReorderController<String, String>(
        treeController: tree,
        vsync: tester,
      );
      addTearDown(reorderA.dispose);

      Widget buildWith(TreeReorderController<String, String> r) =>
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  SliverReorderableTree<String, String>(
                    controller: tree,
                    reorderController: r,
                    nodeBuilder: (_, key, depth, wrap) => wrap(
                      child: SizedBox(
                        key: ValueKey("row-$key"),
                        height: 50,
                        child: Text(key),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

      await tester.pumpWidget(buildWith(reorderA));
      await tester.pumpAndSettle();

      final reorderB = TreeReorderController<String, String>(
        treeController: tree,
        vsync: tester,
      );
      addTearDown(reorderB.dispose);

      await tester.pumpWidget(buildWith(reorderB));
      await tester.pumpAndSettle();

      // No assertion on internal state — the test just verifies the
      // controller swap doesn't throw (listener was correctly moved
      // from reorderA to reorderB in didUpdateWidget, otherwise dispose
      // of reorderA would fire callbacks on a state that no longer
      // tracks it, or reorderB would never reach the state).
    },
  );
}
