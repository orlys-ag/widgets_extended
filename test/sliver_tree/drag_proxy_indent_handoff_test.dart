/// X1 repro pins: every proxy-to-row settle glide must START at the
/// proxy's VISUAL cross offset instead of a structural indent.
///
/// On release, the handoff to the real row is seamless in Y by design,
/// but X was broken on all three glide paths of a proxy-enabled drag:
///
/// - Commit: the FLIP baseline override rewrote only the dragged row's
///   y and preserved the captured x (the OLD indent), so the row
///   materialized at its old indent column instead of where the proxy
///   visually was.
/// - Cancel: the return glide passed `x: 0.0` on both ends, so the row
///   snapped to its structural indent with no x motion.
/// - Dead-commit fallback (reorderSlide zeroed, dropSettle live): same
///   `x: 0.0` on both ends, so the row snapped to its NEW indent.
///
/// Expected behavior, asserted here: at t = 0 the dragged row's painted
/// cross offset (`getIndent + getSlideDeltaX`) equals the proxy's
/// visual cross offset (measured off the floating clone, since the
/// proxy indent-tracks the resolved target), then the glide settles at
/// the row's structural indent. Each setup arranges for the proxy's
/// visual x to DIFFER from the structural indent the unfixed code
/// painted, so every pin fails on the unfixed behavior.
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

/// Mounts a proxy-enabled reorderable tree with render-applied indent:
///
///   p  (depth 0, y 0..50)
///     c  (depth 1, y 50..100)
///       g  (depth 2, y 100..150)   <- the dragged row, indent 48
///   q  (depth 0, y 150..200)
///     r  (depth 1, y 200..250)
///
/// The proxy must be ENABLED: the settler (and with it the
/// release-position handoff) only exists for proxy-enabled sessions.
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

/// The dragged row's painted cross offset: structural indent plus the
/// composed FLIP x delta. This is exactly what the render layer paints
/// (`parentData.indent + slideDeltaX`).
double _paintedCrossOffset(TreeController<String, String> tree, String key) {
  return tree.getIndent(key) + tree.getSlideDeltaX(key);
}

/// The proxy clone's visual left padding (its global left edge; the
/// harness viewport starts at x 0). Measured off the row-key ancestor
/// of the OVERLAY copy of the row text, which the in-place row is not
/// an ancestor of.
double _proxyVisualX(WidgetTester tester, String key) {
  return tester
      .getTopLeft(
        find.ancestor(
          of: find.text(key).last,
          matching: find.byKey(ValueKey("row-$key")),
        ),
      )
      .dx;
}

/// Long-presses row [key], pumps one zero-duration frame so the proxy
/// overlay entry builds, and returns the live gesture.
Future<TestGesture> _lift(WidgetTester tester, String key) async {
  final center = tester.getCenter(find.byKey(ValueKey("row-$key")));
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

/// makeRoom ZERO: the proxy indent SNAPS to the hovered slot's column,
/// making the proxy's visual x deterministic in the pins below.
const TreeAnimationStyle _liveCommitStyle = TreeAnimationStyle(
  expandCollapse: _zero,
  reorderSlide: _live200,
  makeRoom: _zero,
  dropSettle: _live200,
);

/// reorderSlide zeroed (dead commit FLIP), dropSettle live: `endDrag`
/// takes the settle-fallback branch and installs the glide directly.
/// makeRoom is SLOW so the release lands mid-x-animation, where the
/// proxy's visual x differs from both the old and the new indent.
const TreeAnimationStyle _deadCommitStyle = TreeAnimationStyle(
  expandCollapse: _zero,
  reorderSlide: _zero,
  makeRoom: TreeAnimationSpec(
    duration: Duration(milliseconds: 400),
    curve: Curves.linear,
  ),
  dropSettle: _live200,
);

void main() {
  testWidgets(
    "commit FLIP starts at the proxy's visual cross offset, not the "
    "old indent",
    (tester) async {
      final h = await _mount(tester, style: _liveCommitStyle);

      // Setup sanity: the dragged row is genuinely deep and genuinely
      // indented. A zero indent would make the pin below pass vacuously.
      expect(h.tree.getDepth("g"), 2);
      expect(h.tree.getIndent("g"), 48.0);

      final gesture = await _lift(tester, "g");
      // Below the last visible row ("r", y 200..250) with x inside the
      // depth-1 column (24..48): the slot after "r" resolves as q's
      // second child, one level shallower than the source.
      await gesture.moveTo(const Offset(30, 280));
      await tester.pump();

      // Setup sanity: the proxy has snapped to the target's column
      // (zero makeRoom), which DIFFERS from the old indent, so the pin
      // discriminates against the old-indent bug.
      final proxyX = _proxyVisualX(tester, "g");
      expect(proxyX, moreOrLessEquals(24.0));

      await gesture.up();
      await tester.pump(); // the frame that consumes the FLIP baseline

      // Commit sanity: the drop genuinely changed depth (2 -> 1).
      expect(h.tree.getParent("g"), "q");
      expect(h.tree.getDepth("g"), 1);

      // THE PIN: at t = 0 the row paints where the proxy visually was
      // at release. Unfixed code preserves the captured baseline x,
      // painting the row at the OLD indent (48) instead.
      expect(
        _paintedCrossOffset(h.tree, "g"),
        moreOrLessEquals(proxyX),
        reason:
            "the drop handoff must start at the proxy's visual x, not "
            "at the pre-drag indent column",
      );

      // And the glide settles at the NEW indent.
      await tester.pumpAndSettle();
      expect(_paintedCrossOffset(h.tree, "g"), moreOrLessEquals(24.0));
    },
  );

  testWidgets(
    "cancel return-glide starts at the proxy's visual cross offset",
    (tester) async {
      final h = await _mount(tester, style: _liveCommitStyle);

      // Setup sanity: nonzero indent, see the commit repro.
      expect(h.tree.getDepth("g"), 2);
      expect(h.tree.getIndent("g"), 48.0);

      final gesture = await _lift(tester, "g");
      // Hover the shallower slot first so the proxy's visual x (24)
      // differs from the row's unchanged indent (48): a cancel from the
      // untouched seed position would be motionless either way and pin
      // nothing.
      await gesture.moveTo(const Offset(30, 280));
      await tester.pump();
      final proxyX = _proxyVisualX(tester, "g");
      expect(proxyX, moreOrLessEquals(24.0));
      expect(
        h.reorder.isDragging,
        isTrue,
        reason: "setup: the drag session must be live before the cancel",
      );

      h.reorder.cancelDrag();

      // THE PIN: the return glide is installed synchronously and must
      // start at the proxy's visual x. Unfixed code passes x: 0.0 on
      // both ends (zero delta), painting the row at its structural
      // indent (48) immediately.
      expect(
        _paintedCrossOffset(h.tree, "g"),
        moreOrLessEquals(proxyX),
        reason:
            "the cancel return-glide must start at the proxy's visual "
            "x, not snap to the row's structural indent",
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_paintedCrossOffset(h.tree, "g"), moreOrLessEquals(48.0));
      expect(h.tree.getDepth("g"), 2, reason: "cancel must not mutate");
    },
  );

  testWidgets(
    "dead-commit fallback glide starts at the proxy's visual cross "
    "offset",
    (tester) async {
      final h = await _mount(tester, style: _deadCommitStyle);

      // Setup sanity: nonzero indent, see the commit repro.
      expect(h.tree.getDepth("g"), 2);
      expect(h.tree.getIndent("g"), 48.0);

      final gesture = await _lift(tester, "g");
      await gesture.moveTo(const Offset(30, 280));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Setup sanity: mid-x-animation, so the proxy's visual x differs
      // from BOTH the old indent (48) and the new one (24); a
      // no-x-motion regression cannot slip past this pin.
      final proxyX = _proxyVisualX(tester, "g");
      expect(proxyX, greaterThan(24.0));
      expect(proxyX, lessThan(48.0));

      // endDrag runs synchronously in the up handler: snap commit, then
      // the settle-fallback glide installs directly (no baseline).
      await gesture.up();

      // Commit sanity: the fallback path genuinely committed the
      // cross-depth move.
      expect(h.tree.getParent("g"), "q");
      expect(h.tree.getDepth("g"), 1);

      // THE PIN: the glide must start at the proxy's visual x. Unfixed
      // code passes x: 0.0 on both ends (zero delta), painting the row
      // at its NEW indent (24) with no x motion at all.
      expect(
        _paintedCrossOffset(h.tree, "g"),
        moreOrLessEquals(proxyX),
        reason:
            "the dead-commit fallback glide must start at the proxy's "
            "visual x, not snap to the new indent column",
      );

      await tester.pumpAndSettle();
      expect(_paintedCrossOffset(h.tree, "g"), moreOrLessEquals(24.0));
    },
  );
}
