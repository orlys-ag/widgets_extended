/// Z1 repro pins: dragging an expanded parent hides its WHOLE visible
/// subtree in place, not just the parent row.
///
/// The make-room gap already lifts the full subtree's extent and the
/// dragged subtree's rows keep their painted positions, but the widget
/// layer hid only the dragged row itself: an expanded parent's children
/// lingered at their parked positions, painted at full opacity, while
/// every other row shifted around them. Expected behavior, asserted
/// here: every row of the dragged subtree is hidden (in-place opacity
/// 0.0) for the duration of the drag, and restored on cancel and after
/// a commit alike.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

class _Harness {
  _Harness({required this.tree, required this.reorder});

  final TreeController<String, String> tree;
  final TreeReorderController<String> reorder;
}

/// Same tree shape as the handoff suites:
///
///   p  (depth 0, y 0..50)
///     c  (depth 1, y 50..100)     <- dragged: an EXPANDED parent
///       g  (depth 2, y 100..150)  <- must hide along with c
///   q  (depth 0, y 150..200)
///     r  (depth 1, y 200..250)
Future<_Harness> _mount(WidgetTester tester) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: const TreeAnimationStyle(
      expandCollapse: TreeAnimationSpec(
        duration: Duration.zero,
        curve: Curves.linear,
      ),
      reorderSlide: TreeAnimationSpec(
        duration: Duration(milliseconds: 200),
        curve: Curves.linear,
      ),
      makeRoom: TreeAnimationSpec(duration: Duration.zero, curve: Curves.linear),
    ),
    indentWidth: 24.0,
  );
  tree.setRoots(const [
    TreeNode(key: "p", data: "P"),
    TreeNode(key: "q", data: "Q"),
  ]);
  tree.setChildren("p", const [TreeNode(key: "c", data: "C")]);
  tree.setChildren("c", const [TreeNode(key: "g", data: "G")]);
  tree.setChildren("q", const [TreeNode(key: "r", data: "R")]);
  tree.expand(key: "p");
  tree.expand(key: "c");
  tree.expand(key: "q");

  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
  );
  addTearDown(() {
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
  return _Harness(tree: tree, reorder: reorder);
}

/// The IN-PLACE row's drag-hide opacity. Scoped under the scroll view
/// so the floating proxy's clones (which duplicate row keys) can never
/// make the finder ambiguous.
double _inPlaceOpacityOf(WidgetTester tester, String rowKey) {
  final inPlaceRow = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byKey(ValueKey("row-$rowKey")),
  );
  final op = tester.widget<Opacity>(
    find.ancestor(of: inPlaceRow, matching: find.byType(Opacity)),
  );
  return op.opacity;
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
    "dragging an expanded parent hides its visible descendants in "
    "place, restored on cancel",
    (tester) async {
      final h = await _mount(tester);

      // Setup sanity: the dragged row genuinely has a visible subtree,
      // and both rows start fully visible.
      expect(h.tree.visibleSubtreeSize("c"), 2);
      expect(_inPlaceOpacityOf(tester, "c"), 1.0);
      expect(_inPlaceOpacityOf(tester, "g"), 1.0);

      final gesture = await _lift(tester, "c");
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();

      // Sanity: the dragged row itself hides (existing behavior).
      expect(_inPlaceOpacityOf(tester, "c"), 0.0);

      // THE PIN: the dragged row's visible CHILD hides with it. The
      // make-room gap already lifts its extent; leaving it painted
      // orphans it visually while the tree shifts around it.
      expect(
        _inPlaceOpacityOf(tester, "g"),
        0.0,
        reason:
            "a dragged parent's visible descendants must hide in "
            "place along with it",
      );

      h.reorder.cancelDrag();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_inPlaceOpacityOf(tester, "c"), 1.0);
      expect(_inPlaceOpacityOf(tester, "g"), 1.0);
      expect(h.tree.getParent("c"), "p", reason: "cancel must not mutate");
    },
  );

  testWidgets(
    "descendants are restored after a committed cross-parent drop",
    (tester) async {
      final h = await _mount(tester);

      final gesture = await _lift(tester, "c");
      // Below the last visible row ("r") with x in the depth-1 column:
      // the slot after "r" resolves as q's second child.
      await gesture.moveTo(const Offset(30, 280));
      await tester.pump();

      expect(
        _inPlaceOpacityOf(tester, "g"),
        0.0,
        reason: "the child must stay hidden right up to the drop",
      );

      await gesture.up();
      await tester.pumpAndSettle();

      // Commit sanity plus restore: the subtree moved under q and both
      // rows are visible again.
      expect(h.tree.getParent("c"), "q");
      expect(h.tree.getParent("g"), "c");
      expect(_inPlaceOpacityOf(tester, "c"), 1.0);
      expect(_inPlaceOpacityOf(tester, "g"), 1.0);
    },
  );

  testWidgets(
    "an unrelated row outside the dragged subtree stays visible",
    (tester) async {
      final h = await _mount(tester);

      final gesture = await _lift(tester, "c");
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();

      // Guard against over-hiding: "r" is not in c's subtree.
      expect(_inPlaceOpacityOf(tester, "r"), 1.0);
      expect(_inPlaceOpacityOf(tester, "q"), 1.0);
      expect(_inPlaceOpacityOf(tester, "p"), 1.0);

      h.reorder.cancelDrag();
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );
}
