/// Regression (P1, 2026-08-16 drag-proxy plan): the floating drag proxy's
/// content is session-constant, so pointer moves must NOT re-run app
/// builders. Before the fix, every `updateDrag` re-ran the custom
/// `dragProxyBuilder` and one `nodeBuilder` call per captured descendant
/// clone (the whole clone stack lived inside the pointer
/// `ValueListenableBuilder`), when the only pointer-dependent output is
/// the proxy's `top`.
///
/// The contract pinned here: after the lift settles, N pointer moves
/// leave every `nodeBuilder` invocation count and the `dragProxyBuilder`
/// call count unchanged, while the proxy still repositions with the
/// pointer.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

class _Harness {
  _Harness({required this.tree, required this.reorder, required this.builds});

  final TreeController<String, String> tree;
  final TreeReorderController<String> reorder;

  /// Per-key `nodeBuilder` invocation counts (in-place rows AND proxy
  /// clones both route through the same builder).
  final Map<String, int> builds;
}

/// Tree shape: expanded root "p" with three children, plus a sibling
/// root "q" so there is somewhere to hover.
///
///   p  (depth 0)   <- dragged; its 3 visible children ride the proxy
///     a, b, c (depth 1)
///   q  (depth 0)
Future<_Harness> _mount(
  WidgetTester tester, {
  Widget Function(BuildContext context, String key, Widget? rowChild)?
  dragProxyBuilder,
}) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
    indentWidth: 24.0,
  );
  tree.setRoots(const [
    TreeNode(key: "p", data: "P"),
    TreeNode(key: "q", data: "Q"),
  ]);
  tree.setChildren("p", const [
    TreeNode(key: "a", data: "A"),
    TreeNode(key: "b", data: "B"),
    TreeNode(key: "c", data: "C"),
  ]);
  tree.expand(key: "p");

  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
  );
  addTearDown(() {
    reorder.dispose();
    tree.dispose();
  });

  final builds = <String, int>{};
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              dragProxyBuilder: dragProxyBuilder,
              nodeBuilder: (context, key, depth) {
                builds[key] = (builds[key] ?? 0) + 1;
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
  return _Harness(tree: tree, reorder: reorder, builds: builds);
}

/// The proxy CLONE of a row: the row-key ancestor of the OVERLAY copy of
/// its text (same disambiguation as `drag_subtree_proxy_test.dart`).
Finder _clone(String key) {
  return find.ancestor(
    of: find.text(key).last,
    matching: find.byKey(ValueKey("row-$key")),
  );
}

Future<TestGesture> _lift(WidgetTester tester, String key) async {
  final center = tester.getCenter(
    find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byKey(ValueKey("row-$key")),
    ),
  );
  final gesture = await tester.startGesture(center);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets(
    "pointer moves do not re-run nodeBuilder for the proxy's clone stack",
    (tester) async {
      final h = await _mount(tester);

      final gesture = await _lift(tester, "p");

      // Setup sanity: a genuine subtree drag with descendant clones in
      // the overlay (one per key: the in-place copy is a placeholder).
      expect(h.reorder.isDragging, isTrue);
      expect(
        find.text("a"),
        findsOneWidget,
        reason: "setup: the proxy must be floating the descendant clones",
      );
      expect(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.text("a"),
        ),
        findsNothing,
        reason: "the in-place row is a sized placeholder while the proxy is "
            "its mount (H5), so the one copy is the proxy's",
      );

      final afterLift = Map<String, int>.of(h.builds);
      final topBefore = tester.getTopLeft(_clone("p")).dy;

      for (int i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, 15));
        await tester.pump();
      }

      // THE PIN: five moves, zero new builds — for the clones AND for
      // every in-place row (the sliver side's own "nothing rebuilds per
      // pointer move" doctrine). On unfixed code the descendant counts
      // grow by one per clone per move.
      expect(
        h.builds,
        afterLift,
        reason:
            "pointer moves must only reposition the proxy; the clone "
            "stack is session-frozen and must not rebuild per move",
      );
      expect(
        tester.getTopLeft(_clone("p")).dy,
        moreOrLessEquals(topBefore + 75.0),
        reason: "the proxy must still track the pointer",
      );

      h.reorder.cancelDrag();
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "pointer moves do not re-run a custom dragProxyBuilder",
    (tester) async {
      int proxyCalls = 0;
      final h = await _mount(
        tester,
        dragProxyBuilder: (context, key, rowChild) {
          proxyCalls++;
          return Material(
            type: MaterialType.transparency,
            child: rowChild ?? const SizedBox.shrink(),
          );
        },
      );

      final gesture = await _lift(tester, "p");

      // Setup sanity: the custom builder ran for the session.
      expect(h.reorder.isDragging, isTrue);
      expect(proxyCalls, greaterThan(0),
          reason: "setup: the custom proxy builder must have been invoked");

      final callsAfterLift = proxyCalls;
      final buildsAfterLift = Map<String, int>.of(h.builds);

      for (int i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, 15));
        await tester.pump();
      }

      expect(
        proxyCalls,
        callsAfterLift,
        reason:
            "dragProxyBuilder output is session-frozen; pointer moves "
            "must not re-invoke it",
      );
      expect(h.builds, buildsAfterLift,
          reason: "descendant clones must not rebuild per move either");

      h.reorder.cancelDrag();
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );
}
