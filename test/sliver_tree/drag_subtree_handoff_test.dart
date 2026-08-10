/// Z3 repro pins: the settle handoff carries the dragged row's WHOLE
/// visible subtree, so children emerge from under the card instead of
/// flying in from their parked in-place positions.
///
/// All three glide paths of a proxy-enabled drag used to move only the
/// dragged key: on commit the (hidden-in-place) descendants FLIPped
/// from their stale parked offsets, on cancel they reappeared with no
/// motion, and on the dead-commit fallback they snapped to the new
/// slot. Expected behavior, asserted here on the CHILD row: at t = 0
/// its painted position (structural offset plus composed slide deltas,
/// exactly what the render layer paints) equals its clone's measured
/// position in the proxy stack, then it settles at its structural slot.
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

/// "g" is 30px, every other row 50px:
///
///   p  (depth 0, y 0..50)
///     c  (depth 1, y 50..100)     <- dragged, indent 24
///       g  (depth 2, y 100..130)  <- must emerge from the stack
///   q  (depth 0, y 130..180)
///     r  (depth 1, y 180..230)
Future<_Harness> _mount(
  WidgetTester tester, {
  required TreeAnimationStyle style,
}) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: style,
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

/// A row's painted position: structural offset plus the composed slide
/// deltas, exactly the render layer's paint formula. The harness
/// viewport sits at the origin with zero scroll offset, so this is
/// directly comparable to overlay-measured global positions.
Offset _painted(TreeController<String, String> tree, String key) {
  final y = tree.scrollOffsetOf(key)! + tree.getSlideDelta(key);
  final x = tree.getIndent(key) + tree.getSlideDeltaX(key);
  return Offset(x, y);
}

/// The proxy clone of a row (the overlay copy; the in-place row is not
/// an ancestor of the overlay subtree).
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

const TreeAnimationSpec _zero = TreeAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

const TreeAnimationSpec _live200 = TreeAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

/// makeRoom ZERO: the proxy indent snaps to the hovered column, so the
/// clone measurements below are deterministic.
const TreeAnimationStyle _liveCommitStyle = TreeAnimationStyle(
  expandCollapse: _zero,
  reorderSlide: _live200,
  makeRoom: _zero,
  dropSettle: _live200,
);

const TreeAnimationStyle _deadCommitStyle = TreeAnimationStyle(
  expandCollapse: _zero,
  reorderSlide: _zero,
  makeRoom: _zero,
  dropSettle: _live200,
);

void main() {
  testWidgets(
    "commit: the child emerges from its position in the proxy stack",
    (tester) async {
      final h = await _mount(tester, style: _liveCommitStyle);

      final gesture = await _lift(tester, "c");
      // Below the last row with x in the depth-0 column: "c" becomes a
      // root after "q" (depth 1 -> 0, a cross-depth drop).
      await gesture.moveTo(const Offset(10, 280));
      await tester.pump();

      // Setup sanity: the child's clone is genuinely in the stack, one
      // parent-extent below the card's top, indented +24 from the
      // snapped depth-0 column.
      final proxyG = tester.getTopLeft(_clone("g"));
      expect(proxyG.dx, moreOrLessEquals(24.0));
      expect(proxyG.dy, moreOrLessEquals(280.0 - 25.0 + 50.0));

      await gesture.up();
      await tester.pump(); // the frame that consumes the FLIP baseline

      // Commit sanity: the subtree moved to the root level.
      expect(h.tree.getParent("c"), isNull);
      expect(h.tree.getDepth("g"), 1);

      // THE PIN: at t = 0 the child paints exactly where its clone
      // was. Unfixed code FLIPs it from its parked pre-drag offset
      // (y 100, x 48) instead.
      final paintedG = _painted(h.tree, "g");
      expect(
        paintedG.dy,
        moreOrLessEquals(proxyG.dy),
        reason:
            "the child must emerge from the stack's y, not its parked "
            "in-place offset",
      );
      expect(
        paintedG.dx,
        moreOrLessEquals(proxyG.dx),
        reason:
            "the child must emerge from the stack's x, not its old "
            "indent column",
      );

      await tester.pumpAndSettle();
      expect(_painted(h.tree, "g").dy,
          moreOrLessEquals(h.tree.scrollOffsetOf("g")!));
      expect(_painted(h.tree, "g").dx, moreOrLessEquals(24.0));
    },
  );

  testWidgets(
    "cancel: the child glides from the proxy stack back to its slot",
    (tester) async {
      final h = await _mount(tester, style: _liveCommitStyle);

      final gesture = await _lift(tester, "c");
      // Hover the depth-0 column so the stack's x differs from the
      // child's structural indent (48): a stack sitting exactly on the
      // structural column would pin nothing.
      await gesture.moveTo(const Offset(10, 280));
      await tester.pump();
      final proxyG = tester.getTopLeft(_clone("g"));
      expect(proxyG.dx, moreOrLessEquals(24.0));

      h.reorder.cancelDrag();

      // THE PIN: the return glide starts at the child's stack
      // position. Unfixed code installs no glide for the child, which
      // paints at its unchanged structural slot (y 100, x 48)
      // immediately.
      final paintedG = _painted(h.tree, "g");
      expect(paintedG.dy, moreOrLessEquals(proxyG.dy));
      expect(paintedG.dx, moreOrLessEquals(proxyG.dx));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(h.tree.getParent("c"), "p", reason: "cancel must not mutate");
      expect(_painted(h.tree, "g"), const Offset(48.0, 100.0));
    },
  );

  testWidgets(
    "dead-commit fallback: the child glides from the proxy stack into "
    "the committed slot",
    (tester) async {
      final h = await _mount(tester, style: _deadCommitStyle);

      final gesture = await _lift(tester, "c");
      await gesture.moveTo(const Offset(10, 280));
      await tester.pump();
      final proxyG = tester.getTopLeft(_clone("g"));
      expect(proxyG.dx, moreOrLessEquals(24.0));

      // endDrag runs synchronously in the up handler: snap commit,
      // then the settle-fallback glide installs directly.
      await gesture.up();

      expect(h.tree.getParent("c"), isNull);
      expect(h.tree.getDepth("g"), 1);

      // THE PIN: unfixed code glides only the parent; the child snaps
      // to its NEW slot with no motion at all.
      final paintedG = _painted(h.tree, "g");
      expect(paintedG.dy, moreOrLessEquals(proxyG.dy));
      expect(paintedG.dx, moreOrLessEquals(proxyG.dx));

      await tester.pumpAndSettle();
      expect(_painted(h.tree, "g").dy,
          moreOrLessEquals(h.tree.scrollOffsetOf("g")!));
      expect(_painted(h.tree, "g").dx, moreOrLessEquals(24.0));
    },
  );
}
