/// Regression test for S059: when app code calls
/// `controller.cancelDrag()` directly (NOT via the widget's gesture
/// handlers), the local UI in `_SliverReorderableTreeState` must clear
/// — `_draggedKey` reset and the drag proxy overlay removed.
///
/// Before the fix, the state class never subscribed to the reorder
/// controller; only the gesture handlers cleared `_draggedKey`. An
/// external `cancelDrag()` cleared the controller's `_session` but
/// left the source row hidden indefinitely.
///
/// The fix adds an `initState`/`didUpdateWidget`/`dispose` lifecycle
/// for a controller listener that calls `_onDragEnd` when the session
/// ends from outside the gesture path.
library;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Reads the in-place row's opacity. Mounts that assert on it disable the
/// drag proxy: the default proxy clones the dragged row's child into the
/// overlay under its own [Opacity], which would make this finder ambiguous
/// mid-drag.
double _opacityOf(WidgetTester tester, String rowKey) {
  final op = tester.widget<Opacity>(
    find.ancestor(
      of: find.byKey(ValueKey("row-$rowKey")),
      matching: find.byType(Opacity),
    ),
  );
  return op.opacity;
}

/// A mid-drag HANDLE swap must be a NON-EVENT.
///
/// This is the inverse of a hazard that used to be real. When the
/// recognizer lived in the row's build output, replacing the drag surface
/// mid-drag (an app-level mode toggle hit by a second finger) disposed
/// the recognizer that owned the active pointer, its end/cancel callbacks
/// could never fire, and the session was orphaned along with its pin,
/// scroll listener and autoscroll ticker. The row needed a
/// `didUpdateWidget` backstop to notice and cancel.
///
/// The ownership split retires that by construction: the recognizer lives
/// on the row's `State`, and handles are stateless pointer-down reporters
/// that own nothing. So the correct behaviour is now the OPPOSITE of what
/// the backstop provided, and it is worth pinning in that direction: the
/// session survives the swap untouched, and the original finger still
/// commits it.
void _addModeSwapTest() {
  testWidgets("a mid-drag handle swap leaves the live session alone", (
    tester,
  ) async {
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    tree.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
      const TreeNode(key: "c", data: "C"),
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

    final touchMode = ValueNotifier<bool>(true);
    addTearDown(touchMode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: touchMode,
            builder: (context, touch, _) => CustomScrollView(
              slivers: [
                SliverReorderableTree<String, String>(
                  controller: tree,
                  reorderController: reorder,
                  showDragProxy: false,
                  nodeBuilder: (context, key, depth) {
                    final row = SizedBox(
                      key: ValueKey("row-$key"),
                      height: 50,
                      child: Text(key),
                    );
                    // The whole row is the handle in touch mode; a
                    // trailing grip in pointer mode. Flipping between them
                    // is the swap under test.
                    if (touch) {
                      return TreeDelayedDragHandle(child: row);
                    }
                    return Row(
                      children: <Widget>[
                        Expanded(child: row),
                        TreeDragHandle(
                          child: SizedBox(
                            key: ValueKey("h-$key"),
                            width: 24.0,
                            height: 50.0,
                            child: const ColoredBox(color: Color(0xFF000000)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Lift row a via long-press, then swap the handle shape MID-DRAG.
    final gesture = await tester.startGesture(const Offset(400, 25));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0.0, 10.0));
    await tester.pump();
    expect(reorder.isDragging, isTrue, reason: "setup: session active");

    touchMode.value = false;
    await tester.pump();
    await tester.pump();

    expect(
      reorder.isDragging,
      isTrue,
      reason:
          "the recognizer lives on the row's State, so replacing the "
          "handle widget cannot disturb the gesture it started",
    );
    expect(
      _opacityOf(tester, "a"),
      0.0,
      reason: "the drag UI must survive the swap along with the session",
    );

    // And the original finger still drives it to a real commit.
    await gesture.moveBy(const Offset(0.0, 110.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(reorder.isDragging, isFalse);
    expect(
      tree.liveRootKeys.first,
      isNot("a"),
      reason: "the surviving session committed normally",
    );
  });
}

Future<
  ({TreeController<String, String> tree, TreeReorderController<String> reorder})
>
_mount(WidgetTester tester) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  tree.setRoots([
    const TreeNode(key: "a", data: "A"),
    const TreeNode(key: "b", data: "B"),
    const TreeNode(key: "c", data: "C"),
  ]);

  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              showDragProxy: false,
              nodeBuilder: (context, key, depth) {
                return TreeDelayedDragHandle(
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
  _addModeSwapTest();

  testWidgets("external cancelDrag clears local UI state (S059)", (
    tester,
  ) async {
    final h = await _mount(tester);

    // Start a drag via the gesture system. After this, _draggedKey is
    // set internally and row "a" should be dimmed.
    final rowACenter = tester.getCenter(find.byKey(const ValueKey("row-a")));
    final gesture = await tester.startGesture(rowACenter);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();

    // Sanity: drag is active.
    expect(
      _opacityOf(tester, "a"),
      0.0,
      reason:
          "Mid-drag, row 'a' must be hidden — make-room closes "
          "its slot underneath it",
    );
    expect(h.reorder.isDragging, isTrue);

    // External cancel — bypasses the gesture system entirely.
    h.reorder.cancelDrag();
    await tester.pump();

    // S059 assertion: local UI clears even though the gesture
    // wasn't released.
    expect(
      _opacityOf(tester, "a"),
      1.0,
      reason:
          "External cancelDrag() must clear _draggedKey via the "
          "state's controller listener (S059). Without the fix, "
          "the row stays hidden indefinitely.",
    );

    // Clean up the held gesture so the test framework doesn't
    // complain about unfinished gestures.
    await gesture.up();
    await tester.pumpAndSettle();
  });

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
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      h.reorder.startDrag(
        key: "b",
        renderPort: render,
        scrollable: scrollable,
        pointerGlobal: tester.getCenter(find.byKey(const ValueKey("row-c"))),
      );
      expect(h.reorder.draggedKey, "b");
      expect(
        h.reorder.currentTarget,
        isNotNull,
        reason:
            "setup: session 2 must have a live drop target so a "
            "stale forwarded endDrag would visibly commit it",
      );
      final orderBefore = List.of(h.tree.visibleNodes);

      // Finger 1 releases. Row "a"'s _endDrag must verify ownership
      // (draggedKey == its key) and NOT forward endDrag — otherwise it
      // commits SESSION 2's target and tears down its indicator.
      await gesture.up();
      await tester.pump();

      expect(
        h.reorder.isDragging,
        isTrue,
        reason:
            "session 2 must survive the release of the stale "
            "first gesture",
      );
      expect(h.reorder.draggedKey, "b");
      expect(
        h.tree.visibleNodes,
        orderBefore,
        reason:
            "session 2's target must not be committed by the "
            "unrelated released gesture",
      );

      h.reorder.cancelDrag();
      await tester.pumpAndSettle();
    },
  );

  testWidgets("controller swap moves listener to the new controller", (
    tester,
  ) async {
    // Sanity test for the didUpdateWidget swap path.
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(tree.dispose);
    tree.setRoots([const TreeNode(key: "x", data: "X")]);

    final reorderA = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
    );
    addTearDown(reorderA.dispose);

    Widget buildWith(TreeReorderController<String> r) => MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: r,
              nodeBuilder: (_, key, depth) => SizedBox(
                key: ValueKey("row-$key"),
                height: 50,
                child: Text(key),
              ),
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(buildWith(reorderA));
    await tester.pumpAndSettle();

    final reorderB = TreeReorderController<String>(
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
  });
}
