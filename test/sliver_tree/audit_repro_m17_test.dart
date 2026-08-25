import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Repro for M17: the drag proxy was sized and positioned in the
/// VIEWPORT's cross-axis frame and the depth hint consumed the
/// scrollable's local x, while rows live in the TREE SLIVER's frame,
/// which a `SliverPadding` insets. Under a 100 px horizontal padding the
/// card spanned the whole viewport, the x-aware drop resolution read the
/// pointer 100 px too far right, and the card jumped by the padding at
/// release.
///
/// Harness: 800 px surface, the tree under
/// `SliverPadding(horizontal: 100)`, 50 px rows, `indentWidth: 30`, the
/// proxy enabled. Roots `[x, p, b]` with `p` expanded over `c`, so the
/// visible order is x(0) 0..50, p(1) 50..100, c(2) 100..150, b(3)
/// 150..200. `b` is a depth-0 row whose previous visible row is depth 1,
/// so the `above` zone on it offers two candidate depths (1 under `p`,
/// 0 at the root) and the x hint decides between them.
void main() {
  testWidgets(
    "case A: the proxy spans the padded band and the depth hint reads "
    "sliver-local x",
    (tester) async {
      final reorder = await _mount(tester, TreeAnimationStyle.disabled);

      final rowX = tester.getRect(find.byKey(const ValueKey("row-x")));
      expect(
        rowX.left,
        100.0,
        reason: "setup sanity: rows lay out from the padded origin",
      );
      expect(
        rowX.width,
        600.0,
        reason: "setup sanity: rows lay out against the padded extent",
      );

      final gesture = await _liftRowX(tester);
      final proxy = _proxyRect(tester, "x");
      expect(
        proxy.left,
        100.0,
        reason:
            "the proxy band must start at the tree sliver's cross-axis "
            "origin, not the viewport's left edge",
      );
      expect(
        proxy.width,
        600.0,
        reason:
            "the proxy band must span the tree sliver's cross-axis extent, "
            "not the viewport width",
      );

      // 5 px into row b (150..200): the `above` zone at a subtree left
      // boundary; x = 105 is 5 px into the band, hint depth 0.
      await gesture.moveTo(const Offset(105, 155));
      await tester.pump();
      final target = reorder.currentTarget;
      expect(
        target?.targetKey,
        "b",
        reason: "setup sanity: the pointer is over b",
      );
      expect(
        target?.zone,
        TreeDropZone.above,
        reason: "setup sanity: 5 px into the row is the above zone",
      );
      expect(
        target?.depth,
        0,
        reason:
            "x = 5 px into the band hints depth 0; reading the scrollable's "
            "x (105) hints depth 3, clamped to the depth-1 candidate",
      );

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "case B: the proxy's indent is painted in the sliver's frame and the "
    "release handoff is continuous",
    (tester) async {
      final reorder = await _mount(tester, _liveCommitStyle);

      final gesture = await _liftRowX(tester);
      // x = 140 is 40 px into the band: hint depth 1 either way (the
      // unfixed 140 hints 4, clamped to 1), so only the frame differs.
      await gesture.moveTo(const Offset(140, 155));
      await tester.pump();
      expect(
        reorder.currentTarget?.depth,
        1,
        reason: "setup sanity: the depth-1 candidate under p wins",
      );

      final crossOrigin = tester
          .getTopLeft(find.byKey(const ValueKey("row-b")))
          .dx;
      expect(
        crossOrigin,
        100.0,
        reason: "setup sanity: a depth-0 row paints at the sliver's origin",
      );
      final proxyGlobalX = _proxyRect(tester, "x").left;
      expect(
        proxyGlobalX - crossOrigin,
        moreOrLessEquals(30.0),
        reason:
            "the proxy's tracked indent (1 x 30) must be painted from the "
            "sliver's origin; painted from the viewport's it sits 100 px "
            "left of the column it claims",
      );

      await gesture.up();
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey("row-x"))).dx,
        proxyGlobalX,
        reason:
            "the committed row (depth 1, indent 30, FLIP x delta 0) must "
            "appear exactly where the card was: any other value is the "
            "jump at release",
      );
      await tester.pumpAndSettle();
    },
  );
}

const TreeAnimationSpec _zero = TreeAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);
const TreeAnimationSpec _live200 = TreeAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

/// makeRoom zero snaps the proxy indent to the hovered column, so its
/// visual x is deterministic; reorderSlide and dropSettle live, so the
/// commit FLIP is in flight when the continuity pin reads the row.
const TreeAnimationStyle _liveCommitStyle = TreeAnimationStyle(
  expandCollapse: _zero,
  reorderSlide: _live200,
  makeRoom: _zero,
  dropSettle: _live200,
);

Future<TreeReorderController<String>> _mount(
  WidgetTester tester,
  TreeAnimationStyle style,
) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: style,
    indentWidth: 30,
  );
  tree.setRoots([
    const TreeNode(key: "x", data: "X"),
    const TreeNode(key: "p", data: "P"),
    const TreeNode(key: "b", data: "B"),
  ]);
  tree.setChildren("p", [const TreeNode(key: "c", data: "C")]);
  tree.expand(key: "p", animate: false);

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
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 100),
              sliver: SliverReorderableTree<String, String>(
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
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return reorder;
}

/// Long-presses row x at its centre and pumps once so the overlay entry
/// builds; the grab is at the row's centre, so the probe is the raw
/// pointer.
Future<TestGesture> _liftRowX(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const ValueKey("row-x"))),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await tester.pump();
  return gesture;
}

/// The proxy clone's rect, measured off the row-key ancestor of the
/// OVERLAY copy of the row text (`.last`); the in-place row is a
/// placeholder without the text.
Rect _proxyRect(WidgetTester tester, String key) {
  return tester.getRect(
    find.ancestor(
      of: find.text(key).last,
      matching: find.byKey(ValueKey("row-$key")),
    ),
  );
}
