/// Repro tests for the `indentWidth` default on [SliverReorderableTree]:
/// null (the default) resolves to [TreeController.indentWidth] at drag
/// start, so the pointer-to-depth mapping agrees with the indent the
/// render layer actually applies, instead of a hardcoded 24.0.
///
/// Repro-test methodology: on pre-change code the widget defaulted to
/// 24.0 regardless of the controller. With a controller indent of 30,
/// x=27 mapped to depth 1 (27 ~/ 24) rather than depth 0 (27 ~/ 30), so
/// the first test's root-level expectation fails; with a controller
/// indent of 0 the old default kept a 24 px hint column keyed to nothing
/// on screen, so the second test's deepest-level expectation fails.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Same tree shape as `x_aware_below_zone_test.dart`: x first so
/// root-level drops below a's subtree are not no-ops.
///
///   x  (depth 0, y 0..50)
///   a  (depth 0, y 50..100)
///     b  (depth 1, y 100..150)
///       c  (depth 2, y 150..200)
Future<TreeReorderController<String>> _mount(
  WidgetTester tester, {
  required double controllerIndentWidth,
}) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
    indentWidth: controllerIndentWidth,
  );
  tree.setRoots([
    const TreeNode(key: "x", data: "X"),
    const TreeNode(key: "a", data: "A"),
  ]);
  tree.setChildren("a", [const TreeNode(key: "b", data: "B")]);
  tree.setChildren("b", [const TreeNode(key: "c", data: "C")]);
  tree.expand(key: "a", animate: false);
  tree.expand(key: "b", animate: false);

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
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              // indentWidth omitted: the default under test.
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
  return reorder;
}

Future<TestGesture> _liftRowX(
  WidgetTester tester,
  TreeReorderController<String> reorder,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const ValueKey("row-x"))),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  expect(
    reorder.isDragging,
    isTrue,
    reason: "setup: long press must start the session",
  );
  return gesture;
}

void main() {
  testWidgets(
    "omitted indentWidth maps pointer x with the controller's render "
    "constant",
    (tester) async {
      final reorder = await _mount(tester, controllerIndentWidth: 30.0);
      final gesture = await _liftRowX(tester, reorder);

      // The bottom fifth of row c (y=195) is the below zone at a 3-deep
      // subtree boundary: legal depths 0 (root), 1 (in a), 2 (in b).
      await gesture.moveTo(const Offset(27, 195));
      await tester.pump();
      expect(
        reorder.currentTarget?.zone,
        TreeDropZone.below,
        reason: "setup: bottom of row c is the below zone",
      );
      expect(
        reorder.currentTarget?.parentKey,
        isNull,
        reason:
            "27 ~/ 30 = 0 selects the root level; a hardcoded 24.0 "
            "default would map 27 ~/ 24 = 1 and pick depth 1 instead",
      );
      expect(reorder.currentTarget?.depth, 0);

      // The next column over still selects depth 1, pinning that the
      // mapping is live rather than disabled.
      await gesture.moveTo(const Offset(35, 195));
      await tester.pump();
      expect(reorder.currentTarget?.parentKey, "a");
      expect(reorder.currentTarget?.depth, 1);

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "omitted indentWidth with a zero render indent disables x-aware "
    "selection",
    (tester) async {
      final reorder = await _mount(tester, controllerIndentWidth: 0.0);
      final gesture = await _liftRowX(tester, reorder);

      await gesture.moveTo(const Offset(5, 195));
      await tester.pump();
      expect(
        reorder.currentTarget?.zone,
        TreeDropZone.below,
        reason: "setup: bottom of row c is the below zone",
      );
      expect(
        reorder.currentTarget?.parentKey,
        "b",
        reason:
            "with nothing to divide by, below-boundary drops resolve at "
            "the deepest legal level even at far-left x",
      );
      expect(reorder.currentTarget?.depth, 2);

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );
}
