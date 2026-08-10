/// Z2 pins: the floating drag proxy renders the dragged row's visible
/// SUBTREE as a stack, not just the dragged row.
///
/// The stack is captured frozen at drag start: the dragged row's clone
/// first (its captured widget instance, as before), then one fresh
/// clone per visible descendant, each pinned to its captured extent and
/// padded by its indent RELATIVE to the dragged row. The whole stack
/// rides the animated proxy indent as one unit, so retargeting shifts
/// parent and children together and their relative structure is
/// preserved. A collapsed or leaf drag degenerates to the single-row
/// proxy by construction.
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

/// Row heights are per-key so extent pinning is observable:
/// "g" is 30px, every other row 50px.
///
///   p  (depth 0, y 0..50)
///     c  (depth 1, y 50..100)     <- dragged, indent 24
///       g  (depth 2, y 100..130)  <- 30px, relative indent +24
///   q  (depth 0, y 130..180)
///     r  (depth 1, y 180..230)
Future<_Harness> _mount(
  WidgetTester tester, {
  bool expandC = true,
  TreeAnimationStyle? style,
}) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle:
        style ??
        const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 200),
            curve: Curves.linear,
          ),
          makeRoom: TreeAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
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
  if (expandC) {
    tree.expand(key: "c");
  }
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
                    height: key == "g" ? 30 : 50,
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

/// The proxy CLONE of a row: the row-key ancestor of the OVERLAY copy
/// of its text (the in-place row is not an ancestor of the overlay
/// subtree, so this is unambiguous).
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
    "the proxy stacks the dragged row's visible descendants with "
    "pinned heights and relative indents",
    (tester) async {
      final h = await _mount(tester);

      // Setup sanity: a genuine subtree with a distinct child extent.
      expect(h.tree.visibleSubtreeSize("c"), 2);
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byType(CustomScrollView),
                matching: find.byKey(const ValueKey("row-g")),
              ),
            )
            .height,
        30.0,
      );

      final gesture = await _lift(tester, "c");

      // THE PIN: the child is cloned into the overlay (in-place plus
      // clone = 2), directly below the dragged row's clone, at its
      // captured 30px extent, indented +24 relative to the parent
      // clone. Fails today: no descendant clones exist.
      expect(
        find.text("g"),
        findsNWidgets(2),
        reason: "the proxy must clone the dragged row's visible child",
      );
      final cloneC = tester.getTopLeft(_clone("c"));
      final cloneG = tester.getTopLeft(_clone("g"));
      expect(cloneG.dy, moreOrLessEquals(cloneC.dy + 50.0),
          reason: "the child clone stacks below the parent's row extent");
      expect(cloneG.dx, moreOrLessEquals(cloneC.dx + 24.0),
          reason: "the child clone keeps its indent relative to the parent");
      expect(tester.getSize(_clone("g")).height, moreOrLessEquals(30.0),
          reason: "the child clone is pinned to its captured extent");
      // Width: viewport minus the parent's animated indent (seeded at
      // 24) minus the relative indent.
      expect(
        tester.getSize(_clone("g")).width,
        moreOrLessEquals(800.0 - 24.0 - 24.0),
        reason: "the relative padding narrows the clone, not shifts it",
      );

      h.reorder.cancelDrag();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text("g"), findsOneWidget,
          reason: "the clone is torn down with the session");
    },
  );

  testWidgets(
    "a collapsed dragged parent degenerates to the single-row proxy",
    (tester) async {
      final h = await _mount(tester, expandC: false);

      // Setup sanity: no visible subtree below "c".
      expect(h.tree.visibleSubtreeSize("c"), 1);
      expect(find.text("g"), findsNothing);

      final gesture = await _lift(tester, "c");

      expect(find.text("c"), findsNWidgets(2),
          reason: "in-place row plus its single clone");
      expect(find.text("g"), findsNothing,
          reason: "hidden descendants must not be conjured into the proxy");

      h.reorder.cancelDrag();
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "the stack rides the animated proxy indent as one unit",
    (tester) async {
      final h = await _mount(
        tester,
        style: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 200),
            curve: Curves.linear,
          ),
          // Slow tracking so the mid-flight sample is genuinely
          // mid-animation.
          makeRoom: TreeAnimationSpec(
            duration: Duration(milliseconds: 400),
            curve: Curves.linear,
          ),
        ),
      );

      final gesture = await _lift(tester, "c");
      final beforeC = tester.getTopLeft(_clone("c")).dx;
      final beforeG = tester.getTopLeft(_clone("g")).dx;
      expect(beforeG - beforeC, moreOrLessEquals(24.0));

      // Hover the depth-0 column below the last row: the parent indent
      // animates 24 -> 0 while the relative offset must stay 24.
      await gesture.moveTo(const Offset(10, 280));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final midC = tester.getTopLeft(_clone("c")).dx;
      final midG = tester.getTopLeft(_clone("g")).dx;
      expect(midC, lessThan(beforeC),
          reason: "setup: the parent indent is genuinely animating");
      expect(midG - midC, moreOrLessEquals(24.0),
          reason: "the stack must move as one unit under the animated "
              "indent, preserving relative structure");

      h.reorder.cancelDrag();
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );
}
