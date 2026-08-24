/// X2 pins: the floating drag proxy is indent-aware.
///
/// The proxy content carries an animated left padding in sliver cross
/// space: seeded with the SOURCE row's indent at drag start (seamless
/// lift), re-targeted toward `targetDepth * TreeController.indentWidth`
/// (the render-truth constant `getIndent` multiplies) on each semantic
/// target change, riding the `makeRoom` family (drag-gap feedback), and
/// reported to the settle glides as the proxy's instantaneous visual
/// cross offset so a release mid-animation hands off exactly where the
/// card visually is.
///
/// The regime guard pins that a controller `indentWidth` of 0 (indent
/// baked into rows by the nodeBuilder, or no indent at all) keeps the
/// proxy padding at 0 for the whole drag: the POINTER-MAPPING override
/// (`SliverReorderableTree.indentWidth`) must never leak into
/// presentation.
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

/// Same tree shape as the X1 handoff repros:
///
///   p  (depth 0, y 0..50)
///     c  (depth 1, y 50..100)
///       g  (depth 2, y 100..150)   <- the dragged row
///   q  (depth 0, y 150..200)
///     r  (depth 1, y 200..250)
Future<_Harness> _mount(
  WidgetTester tester, {
  required TreeAnimationStyle style,
  double indentWidth = 24.0,
  double pointerIndentWidth = 24.0,
}) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: style,
    indentWidth: indentWidth,
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
              indentWidth: pointerIndentWidth,
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

/// Long-presses row [key], pumps one zero-duration frame so the proxy
/// overlay entry builds, and returns the live gesture.
Future<TestGesture> _lift(WidgetTester tester, String key) async {
  final center = tester.getCenter(find.byKey(ValueKey("row-$key")));
  final gesture = await tester.startGesture(center);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await tester.pump();
  return gesture;
}

/// Finder for the proxy CLONE of the dragged row: the row-key ancestor
/// of the overlay copy of the row's text. The in-place row is not an
/// ancestor of the overlay subtree, so this is unambiguous while the
/// in-place `find.byKey` is not (the clone duplicates the key).
Finder _cloneRow(String key) {
  return find.ancestor(
    of: find.text(key).last,
    matching: find.byKey(ValueKey("row-$key")),
  );
}

/// The proxy content's visual left padding: the clone renders inside a
/// full-viewport-width band anchored at the viewport's left edge (x 0
/// in this harness), so its global left IS the padding.
double _clonePadding(WidgetTester tester, String key) {
  return tester.getTopLeft(_cloneRow(key)).dx;
}

double _paintedCrossOffset(TreeController<String, String> tree, String key) {
  return tree.getIndent(key) + tree.getSlideDeltaX(key);
}

const TreeAnimationSpec _zero = TreeAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

void main() {
  testWidgets(
    "lift seeds the proxy indent with the source row's indent (no jump)",
    (tester) async {
      final h = await _mount(
        tester,
        style: const TreeAnimationStyle(
          expandCollapse: _zero,
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 200),
            curve: Curves.linear,
          ),
          makeRoom: TreeAnimationSpec(
            duration: Duration(milliseconds: 240),
            curve: Curves.linear,
          ),
        ),
      );

      // Setup sanity: the lifted row is genuinely deep and indented.
      expect(h.tree.getDepth("g"), 2);
      expect(h.tree.getIndent("g"), 48.0);

      final gesture = await _lift(tester, "g");
      expect(
        find.text("g"),
        findsOneWidget,
        reason:
            "setup: the floating proxy clone (the in-place row is a "
            "placeholder)",
      );
      expect(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.text("g"),
        ),
        findsNothing,
        reason: "the in-place row is a sized placeholder while the proxy is "
            "its mount (H5), so the one copy is the proxy's",
      );

      // The seed, on the proxy's FIRST rendered frame: the source row's
      // indent, so the lift does not jump horizontally.
      expect(
        _clonePadding(tester, "g"),
        moreOrLessEquals(48.0),
        reason: "the proxy must lift at the source row's indent column",
      );
      // And the content narrows to the row's render-applied width.
      expect(
        tester.getSize(_cloneRow("g")).width,
        moreOrLessEquals(800.0 - 48.0),
        reason: "the padding must narrow the content, not shift it",
      );

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "retarget animates the proxy indent under the makeRoom family's "
    "spec toward targetDepth * indentWidth",
    (tester) async {
      final h = await _mount(
        tester,
        style: const TreeAnimationStyle(
          expandCollapse: _zero,
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 200),
            curve: Curves.linear,
          ),
          // DISTINCTIVE: neither the 300ms default nor reorderSlide's
          // 200ms. The midpoint assertion below only holds if THIS spec
          // governs the proxy indent animation.
          makeRoom: TreeAnimationSpec(
            duration: Duration(milliseconds: 240),
            curve: Curves.linear,
          ),
        ),
      );

      final gesture = await _lift(tester, "g");
      expect(_clonePadding(tester, "g"), moreOrLessEquals(48.0));

      // Hover the depth-1 slot below the last row ("r"): x inside the
      // 24..48 column selects depth 1, whose column is 24.
      await gesture.moveTo(const Offset(30, 280));
      await tester.pump();

      // Family-flow pin: halfway through the CONFIGURED 240ms makeRoom
      // spec, a linear curve sits exactly halfway between 48 and 24.
      // The 300ms default would sit at 38.4, reorderSlide's 200ms at
      // 33.6; only the configured family produces 36.
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        _clonePadding(tester, "g"),
        moreOrLessEquals(36.0),
        reason: "the configured makeRoom spec must govern the tracking",
      );

      // Past the full spec: settled at the target's column.
      await tester.pump(const Duration(milliseconds: 150));
      expect(_clonePadding(tester, "g"), moreOrLessEquals(24.0));
      expect(
        tester.getSize(_cloneRow("g")).width,
        moreOrLessEquals(800.0 - 24.0),
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(h.tree.getParent("g"), "q");
    },
  );

  testWidgets("a zeroed makeRoom family snaps the proxy indent", (
    tester,
  ) async {
    final h = await _mount(
      tester,
      style: const TreeAnimationStyle(
        expandCollapse: _zero,
        // reorderSlide non-zero: the explicit makeRoom zero must
        // dominate its own family, not inherit the live fallback.
        reorderSlide: TreeAnimationSpec(
          duration: Duration(milliseconds: 200),
          curve: Curves.linear,
        ),
        makeRoom: _zero,
      ),
    );

    final gesture = await _lift(tester, "g");
    expect(_clonePadding(tester, "g"), moreOrLessEquals(48.0));

    await gesture.moveTo(const Offset(30, 280));
    await tester.pump();

    // No clock: the zero family snaps to the target column immediately.
    expect(
      _clonePadding(tester, "g"),
      moreOrLessEquals(24.0),
      reason: "a zero makeRoom family must snap, not animate",
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.tree.getParent("g"), "q");
  });

  testWidgets(
    "regime guard: indentWidth 0 keeps the proxy padding at 0 for the "
    "whole drag, whatever the widget's pointer-mapping indentWidth is",
    (tester) async {
      final h = await _mount(
        tester,
        style: const TreeAnimationStyle(
          expandCollapse: _zero,
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 200),
            curve: Curves.linear,
          ),
          makeRoom: TreeAnimationSpec(
            duration: Duration(milliseconds: 240),
            curve: Curves.linear,
          ),
        ),
        indentWidth: 0.0,
        pointerIndentWidth: 24.0,
      );

      // Setup sanity: structurally deep, rendered UNindented.
      expect(h.tree.getDepth("g"), 2);
      expect(h.tree.getIndent("g"), 0.0);

      final gesture = await _lift(tester, "g");
      expect(_clonePadding(tester, "g"), moreOrLessEquals(0.0));

      await gesture.moveTo(const Offset(30, 280));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        _clonePadding(tester, "g"),
        moreOrLessEquals(0.0),
        reason:
            "the pointer-mapping indentWidth override must never "
            "leak into the proxy's presentation",
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(_clonePadding(tester, "g"), moreOrLessEquals(0.0));
      expect(tester.getSize(_cloneRow("g")).width, moreOrLessEquals(800.0));

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "release mid-x-animation hands off at the proxy's instantaneous "
    "visual cross offset",
    (tester) async {
      final h = await _mount(
        tester,
        style: const TreeAnimationStyle(
          expandCollapse: _zero,
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 200),
            curve: Curves.linear,
          ),
          // Slow tracking so the release genuinely lands mid-flight.
          makeRoom: TreeAnimationSpec(
            duration: Duration(milliseconds: 400),
            curve: Curves.linear,
          ),
          dropSettle: TreeAnimationSpec(
            duration: Duration(milliseconds: 200),
            curve: Curves.linear,
          ),
        ),
      );

      final gesture = await _lift(tester, "g");
      await gesture.moveTo(const Offset(30, 280));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Setup sanity: the proxy indent is genuinely mid-flight, at
      // neither endpoint.
      final padBefore = _clonePadding(tester, "g");
      expect(padBefore, greaterThan(24.0));
      expect(padBefore, lessThan(48.0));

      // Release with no intervening frame: the commit baseline reads
      // the getter's instantaneous value, which is padBefore.
      await gesture.up();
      await tester.pump(); // the frame that consumes the FLIP baseline

      expect(h.tree.getParent("g"), "q");
      expect(
        _paintedCrossOffset(h.tree, "g"),
        moreOrLessEquals(padBefore),
        reason:
            "the handoff must start exactly where the card visually "
            "was at release, mid-animation included",
      );

      await tester.pumpAndSettle();
      expect(_paintedCrossOffset(h.tree, "g"), moreOrLessEquals(24.0));
    },
  );
}
