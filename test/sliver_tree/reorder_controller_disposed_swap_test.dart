/// Regression test for issue 10 of the 2026-08-21 review: DISPOSING a
/// [TreeReorderController] mid-drag and swapping in a new one stranded
/// the drag UI.
///
/// Sibling of `reorder_controller_swap_mid_drag_test.dart`, which covers
/// swapping to a different LIVE controller (B2 of the 2026-08-16 plan).
/// That path is reconciled by the row-side backstop, which reads the old
/// controller's `draggedKey`; a DISPOSED controller reports null there,
/// so the backstop returns early and this path needs its own reconcile.
///
/// `TreeReorderController.dispose` tears its session down without
/// notifying, and `_onControllerChanged` is the single owner of drag-UI
/// teardown, so it never ran. The row-side orphan backstop returns early
/// because `draggedKey` is already null on the disposed controller, and
/// `didUpdateWidget` swapped listeners without reconciling the dragged
/// key. The result: the dragged row stayed at opacity 0 and the drag
/// proxy stayed in the overlay until the next drag or the widget's own
/// disposal.
///
/// `setState(() { old.dispose(); controller = TreeReorderController(...); })`
/// is the ordinary way an app swaps a controller, so this is reachable
/// without any misuse.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Widget _host(
  TreeController<String, String> tree,
  TreeReorderController<String> reorder,
) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverReorderableTree<String, String>(
            controller: tree,
            reorderController: reorder,
            showDragProxy: true,
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
  );
}

/// Opacity applied to the single remaining in-place row for [key].
///
/// Only meaningful once the drag proxy is gone: while a drag is live the
/// key matches twice (in-place copy plus proxy clone) and which one this
/// resolves is not defined.
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
  testWidgets("disposing the reorder controller mid-drag and swapping in a "
      "new one restores the drag UI", (tester) async {
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(tree.dispose);
    tree.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
      const TreeNode(key: "c", data: "C"),
    ]);

    final first = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
    );
    await tester.pumpWidget(_host(tree, first));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(400, 75));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(const Offset(400, 76));
    await tester.pump();
    expect(first.isDragging, isTrue, reason: "setup: a live session");
    expect(
      find.text("b"),
      findsOneWidget,
      reason:
          "setup: the floating proxy holds the row's only mount (the "
          "in-place copy is a placeholder), which is why the opacity helper "
          "below is only read once the proxy is gone",
    );
    expect(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.text("b"),
      ),
      findsNothing,
      reason: "the in-place row is a sized placeholder while the proxy is "
          "its mount (H5), so the one copy is the proxy's",
    );

    // The app disposes the controller and rebuilds with a fresh one.
    first.dispose();
    final second = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
    );
    addTearDown(() {
      if (second.isDragging) {
        second.cancelDrag();
      }
      second.dispose();
    });
    await tester.pumpWidget(_host(tree, second));
    await tester.pumpAndSettle();

    await gesture.up();
    await tester.pumpAndSettle();

    expect(second.isDragging, isFalse);
    expect(
      _rowOpacity(tester, "b"),
      1.0,
      reason: "the row must not stay invisible after the controller that "
          "owned its session is gone",
    );
    expect(
      find.byKey(const ValueKey("row-b")),
      findsOneWidget,
      reason: "no stranded proxy copy of the row is left in the overlay",
    );
  });

  testWidgets("swapping controllers with no drag in flight changes nothing", (
    tester,
  ) async {
    // Control: the reconcile is scoped to a stranded session, so an
    // ordinary controller swap is untouched.
    final tree = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(tree.dispose);
    tree.setRoots([
      const TreeNode(key: "a", data: "A"),
      const TreeNode(key: "b", data: "B"),
    ]);

    final first = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
    );
    await tester.pumpWidget(_host(tree, first));
    await tester.pumpAndSettle();
    first.dispose();

    final second = TreeReorderController<String>(
      treeController: tree,
      vsync: tester,
    );
    addTearDown(second.dispose);
    await tester.pumpWidget(_host(tree, second));
    await tester.pumpAndSettle();

    expect(_rowOpacity(tester, "b"), 1.0);
    expect(second.isDragging, isFalse);

    // And a drag on the new controller still works end to end.
    final gesture = await tester.startGesture(const Offset(400, 75));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(const Offset(400, 130));
    await tester.pump();
    expect(second.isDragging, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tree.rootKeys, ["a", "b"]);
  });
}
