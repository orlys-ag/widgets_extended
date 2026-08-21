/// Regression (B2, 2026-08-16 bugfix plan): rebuilding
/// [SliverReorderableTree] with a DIFFERENT [TreeReorderController] while
/// a drag session is in flight must end the orphaned session cleanly.
///
/// Before the fix, the swap re-cached every row's scope-derived controller
/// reference (the scope's `updateShouldNotify` compares controller
/// identity), so the first gesture callback after the swap failed
/// `_ownsSession` against the NEW controller and silently cleared the
/// row's local session flags. From then on nothing forwarded to either
/// controller: the old controller's session was never torn down (eviction
/// pin, scroll listener, held make-room preview), the drag proxy stayed
/// frozen on screen, the source row stayed at opacity 0, and both
/// row-side backstops (deactivate, policy-flip) were disarmed because the
/// owning-row flag was already false.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Future<void> _pump(
  WidgetTester tester,
  TreeController<String, String> tree,
  TreeReorderController<String> reorder,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
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
    const TreeNode(key: "d", data: "D"),
  ]);

  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
  );

  await _pump(tester, tree, reorder);
  await tester.pumpAndSettle();

  addTearDown(() {
    tree.dispose();
  });
  addTearDown(reorder.dispose);

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

/// Opacity applied to the single remaining in-place row for [key]. Only
/// meaningful when the proxy is gone (exactly one match for the key).
double _rowOpacity(WidgetTester tester, String key) {
  final opacity = tester.widget<Opacity>(
    find
        .ancestor(
          of: find.byKey(ValueKey("row-$key")),
          matching: find.byType(Opacity),
        )
        .first,
  );
  return opacity.opacity;
}

void main() {
  testWidgets(
    "swapping the reorder controller mid-drag cancels the old session and "
    "restores the drag UI",
    (tester) async {
      final h = await _mount(tester);
      final c1 = h.reorder;

      final gesture = await _startDragOn(tester, "a");
      // Hover row "c" so a target resolves and the make-room preview is
      // genuinely held.
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey("row-c"))),
      );
      await tester.pump();

      // Setup sanity: live session with proxy, held preview, hidden row.
      expect(c1.isDragging, isTrue, reason: "setup: drag must be active");
      expect(c1.draggedKey, "a");
      expect(
        c1.currentTarget,
        isNotNull,
        reason: "setup: a resolved target is required",
      );
      expect(
        find.text("a"),
        findsNWidgets(2),
        reason: "setup: in-place copy + floating proxy clone",
      );
      expect(
        h.tree.hasActiveSlides,
        isTrue,
        reason: "setup: the make-room preview must be held",
      );

      // THE SWAP: same tree controller, fresh reorder controller, while
      // the pointer is still down.
      final c2 = TreeReorderController<String>(
        treeController: h.tree,
        vsync: tester,
      );
      addTearDown(c2.dispose);
      await _pump(tester, h.tree, c2);
      // Flush the deferred (post-frame) session cancel and the owner's
      // setState.
      await tester.pump();
      await tester.pump();

      // Move and lift; on unfixed code these are silently swallowed
      // (ownership fails against the new controller) and nothing below
      // ever tears down.
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump();

      expect(
        c1.isDragging,
        isFalse,
        reason:
            "the old controller's session must be cancelled on the swap; "
            "nothing else can ever end it (its gesture forwarding is cut)",
      );
      expect(c2.isDragging, isFalse);
      expect(
        find.text("a"),
        findsOneWidget,
        reason: "the drag proxy must be removed, not left frozen on screen",
      );
      expect(
        _rowOpacity(tester, "a"),
        1.0,
        reason: "the source row must be visible again, not stuck hidden",
      );
      expect(
        h.tree.hasActiveSlides,
        isFalse,
        reason: "the held make-room preview must be released",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "swap plus dragged-row removal in the same frame: session still ends, "
    "backstops do not double-fire",
    (tester) async {
      final h = await _mount(tester);
      final c1 = h.reorder;

      final gesture = await _startDragOn(tester, "a");
      expect(c1.isDragging, isTrue, reason: "setup: drag must be active");

      // Same frame: purge the dragged row AND swap the controller. The
      // dead-node GC deactivates row "a" post-frame while the swap's
      // didChangeDependencies hook has also scheduled a cancel; the two
      // teardown paths must compose idempotently.
      h.tree.remove(key: "a", animate: false);
      final c2 = TreeReorderController<String>(
        treeController: h.tree,
        vsync: tester,
      );
      addTearDown(c2.dispose);
      await _pump(tester, h.tree, c2);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(
        c1.isDragging,
        isFalse,
        reason: "the orphaned session must be cancelled",
      );
      expect(c2.isDragging, isFalse);
      expect(find.byKey(const ValueKey("row-a")), findsNothing);
      expect(
        find.byKey(const ValueKey("row-b")),
        findsOneWidget,
        reason: "surviving rows keep rendering after the combined teardown",
      );

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );
}
