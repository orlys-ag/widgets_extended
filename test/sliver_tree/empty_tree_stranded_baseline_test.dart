/// Regression test for audit item 4.6: the empty-visible-order early
/// return in `performLayout` must discard a staged FLIP baseline (and
/// reset ghost/scroll bookkeeping) instead of leaving it pending.
///
/// An animated mutation that stages a baseline and empties the tree in
/// the same frame used to leave the baseline stranded: first-wins staging
/// then blocked every later `beginSlideBaseline`, and when the tree
/// repopulated, the stale pre-empty offsets were consumed as the FLIP
/// "before" of an unrelated mutation — wrong one-frame deltas (rows
/// sliding after a plain setRoots).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "baseline staged by a batch that empties the tree is discarded — "
    "repopulating does not consume stale offsets, later slides install "
    "correctly",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return SizedBox(height: 48, child: Text(key));
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // One batch: an animated move stages a FLIP baseline (a@0, b@48),
      // then the tree is emptied. The layout that follows sees an empty
      // visible order and takes the early return.
      controller.runBatch(() {
        controller.moveNode(
          "b",
          null,
          index: 0,
          animate: true,
          slideDuration: const Duration(milliseconds: 1000),
          slideCurve: Curves.linear,
        );
        controller.remove(key: "b", animate: false);
        controller.remove(key: "a", animate: false);
      });
      await tester.pump();
      expect(controller.visibleNodes, isEmpty,
          reason: "setup: the batch must empty the tree");

      // Repopulate with the same keys in swapped positions. A stranded
      // baseline (a@0, b@48) consumed against the new layout (b@0, a@48)
      // would install ±48px slides for a plain, non-animated setRoots.
      controller.setRoots([
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "a", data: "A"),
      ]);
      await tester.pump();

      expect(
        controller.hasActiveSlides,
        isFalse,
        reason: "a non-animated setRoots must not inherit the stale "
            "pre-empty baseline as its FLIP 'before'",
      );
      expect(controller.getSlideDelta("a"), 0.0);
      expect(controller.getSlideDelta("b"), 0.0);

      // And a fresh animated move must stage + install normally (the
      // stranded baseline used to block every later stage under
      // first-wins).
      controller.moveNode(
        "a",
        null,
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 1000),
        slideCurve: Curves.linear,
      );
      await tester.pump();

      expect(controller.hasActiveSlides, isTrue,
          reason: "the fresh animated move must install a slide");
      expect(controller.getSlideDelta("a"), closeTo(48.0, 1.0),
          reason: "a moved from y=48 to y=0 — its FLIP delta starts at "
              "+48 so the painted position is continuous");
      expect(controller.getSlideDelta("b"), closeTo(-48.0, 1.0));

      await tester.pumpAndSettle();
      expect(controller.hasActiveSlides, isFalse);
    },
  );
}
