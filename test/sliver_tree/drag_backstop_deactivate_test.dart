/// Regression test for R1 (post-audit review, 2026-07-15): the
/// `_ReorderableRowState.deactivate()` drag backstop must not fire
/// `notifyListeners`/`setState` synchronously inside a build scope.
///
/// `deactivate()` only ever runs inside a `BuildOwner.buildScope`. The
/// backstop's own target scenario — the dragged node removed and purged
/// mid-drag — deactivates the row from the element's dead-node GC pass
/// (`sliver_tree_element.dart`, `_collectGarbage`), which runs inside
/// `owner!.buildScope(...)` in a post-frame callback. The drag pin cannot
/// protect the row: a purged node has no data left to build, so GC
/// deliberately ignores `isNodeRetained`.
///
/// Before the fix, the synchronous `cancelDrag()` in `deactivate()`
/// notified listeners that call `setState` on the ancestor
/// `_SliverReorderableTreeState` and rebuild the overlay drag proxy while
/// `_debugBuilding` is true ("setState() or markNeedsBuild() called
/// during build"), and the follow-up direct `_onDragEnd()` call threw
/// UNCAUGHT out of the GC's buildScope — aborting the remaining
/// evictions of that GC pass.
///
/// The fix keeps only the `_isDraggingThisRow` flag flip synchronous and
/// defers the session teardown to a post-frame callback that re-validates
/// session ownership before acting.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Future<
  ({
    TreeController<String, String> tree,
    TreeReorderController<String> reorder,
  })
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
    const TreeNode(key: "d", data: "D"),
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

/// Long-press-drags the row for [key] and returns the held gesture.
Future<TestGesture> _startDragOn(WidgetTester tester, String key) async {
  final rowCenter = tester.getCenter(find.byKey(ValueKey("row-$key")));
  final gesture = await tester.startGesture(rowCenter);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await gesture.moveBy(const Offset(0, 10));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets(
    "dragged row removed and purged mid-drag: GC-driven deactivate must "
    "not setState during build, and the GC pass must complete",
    (tester) async {
      final h = await _mount(tester);

      final gesture = await _startDragOn(tester, "a");

      // Setup sanity: the drag session is genuinely active on row "a".
      expect(h.reorder.isDragging, isTrue,
          reason: "setup: long-press drag must have started");
      expect(h.reorder.draggedKey, "a");

      // Remove the dragged row AND a sibling with animate: false — both
      // are purged immediately. The next frame's dead-node GC evicts both
      // elements in one buildScope pass; row "a"'s deactivate() runs the
      // drag backstop inside that scope.
      h.tree.remove(key: "a", animate: false);
      h.tree.remove(key: "b", animate: false);

      // Setup sanity: purge really happened (this is the GC path, not the
      // pin-protected stale-eviction path).
      expect(h.tree.getNodeData("a"), isNull,
          reason: "setup: removed row must be purged so dead-node GC — "
              "not pin-respecting stale eviction — evicts its element");
      expect(h.tree.getNodeData("b"), isNull);

      // Frame 1: relayout; its post-frame GC pass deactivates both rows.
      // Frame 2: the deferred backstop teardown runs post-frame.
      // Frame 3: flush the teardown's setState.
      // On the unfixed tree, frame 1's GC pass reports "setState() or
      // markNeedsBuild() called during build" (twice via ChangeNotifier)
      // and the direct _onDragEnd() throw unwinds the buildScope —
      // flutter_test fails the test on those errors.
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(h.reorder.isDragging, isFalse,
          reason: "backstop must end the orphaned session (its gesture "
              "callbacks can never fire again)");

      // The sibling dead row evicted in the SAME GC pass must actually be
      // unmounted — proves the pass wasn't aborted by an uncaught throw
      // from row \"a\"'s deactivate.
      expect(find.byKey(const ValueKey("row-b")), findsNothing,
          reason: "sibling eviction in the same GC pass must complete");
      expect(find.byKey(const ValueKey("row-a")), findsNothing);
      expect(find.byKey(const ValueKey("row-c")), findsOneWidget);

      // Release the held pointer; the row element is gone, so no gesture
      // callback fires.
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "tree swapped out mid-drag: deactivate must not rebuild the overlay "
    "proxy during build; session cancelled, proxy removed",
    (tester) async {
      final h = await _mount(tester);

      final gesture = await _startDragOn(tester, "a");
      // Hover the center of row "c" so a real drop target resolves and
      // the overlay proxy is floating the dragged row's clone.
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey("row-c"))),
      );
      await tester.pump();

      // Setup sanity: active session with the proxy clone mounted in the
      // root overlay (it survives the home swap below).
      expect(h.reorder.isDragging, isTrue);
      expect(h.reorder.currentTarget, isNotNull,
          reason: "setup: a resolved drop target is required for the drag "
              "UI to be live");
      expect(
        find.text("a"),
        findsNWidgets(2),
        reason: "setup: the proxy clones the dragged row's child into the "
            "overlay (hidden in-place copy + floating copy)",
      );

      // Swap the tree out (same MaterialApp, so the root overlay — where
      // the proxy entry and its still-active state live — persists). Row
      // deactivation runs inside this pump's build phase; on the unfixed
      // tree the synchronous cancelDrag() drives the overlay's rebuild
      // during build, a reported FlutterError.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text("no tree"))),
        ),
      );
      // Deferred backstop teardown (post-frame) + overlay rebuild.
      await tester.pump();
      await tester.pump();

      expect(h.reorder.isDragging, isFalse,
          reason: "backstop must cancel the session when its row unmounts "
              "with the tree");
      expect(
        find.text("a"),
        findsNothing,
        reason: "the overlay proxy entry must be removed, not leaked — the "
            "tree itself is gone, so the in-place copy is gone too",
      );

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );
}
