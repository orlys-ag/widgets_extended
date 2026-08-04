/// Regression test for R123: `_children` (the render object's
/// TKey-keyed RenderBox map) must survive a controller swap. When the
/// user swaps in a new controller that shares some TKey values with the
/// old one, the existing RenderBox for each shared key must be reused —
/// not rebuilt — so paint, hit-test, and `visitChildrenForSemantics`
/// stay consistent across the swap.
///
/// The retention rationale already lives in `render_sliver_tree.dart`
/// near the controller setter (the long "Do NOT clear `_children`"
/// comment); the rationale was untested. Mechanism:
/// `SliverTreeElement.update()` clears `_dirtyKeys` on a controller
/// swap, which makes `createChild()` early-return for keys already in
/// `_children` — leaving the existing Element and RenderBox untouched.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Widget _harness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (_, key, depth) => SizedBox(
                key: ValueKey("row-$key"),
                height: 48,
                child: Padding(
                  padding: EdgeInsets.only(left: depth * 20.0),
                  child: Text(key),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    "shared TKey across controller swap reuses the same RenderBox",
    (tester) async {
      // Controller A: a single root with key "shared".
      final controllerA = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controllerA.dispose);

      controllerA.setRoots([const TreeNode(key: "shared", data: "A_data")]);

      await tester.pumpWidget(_harness(controllerA));
      await tester.pumpAndSettle();

      // Capture the RenderBox for "shared" via the row's value key.
      final boxBefore = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey("row-shared")));

      // Swap to controller B which ALSO has a node keyed "shared"
      // (different `data` payload). The user's intent here is the
      // common "same logical row, different data source" pattern.
      final controllerB = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controllerB.dispose);

      controllerB.setRoots([const TreeNode(key: "shared", data: "B_data")]);

      await tester.pumpWidget(_harness(controllerB));
      await tester.pumpAndSettle();

      final boxAfter = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey("row-shared")));

      expect(
        identical(boxBefore, boxAfter),
        isTrue,
        reason: "RenderBox for a TKey shared across controller swap "
            "must be reused (not rebuilt). render_sliver_tree.dart's "
            "controller setter intentionally preserves _children for "
            "this reason.",
      );
    },
  );

  testWidgets(
    "controller swap retains RenderBoxes for the keys that overlap, "
    "drops RenderBoxes for keys only in the old controller",
    (tester) async {
      final controllerA = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controllerA.dispose);

      controllerA.setRoots([
        const TreeNode(key: "shared", data: "A_shared"),
        const TreeNode(key: "a_only", data: "A_only"),
      ]);

      await tester.pumpWidget(_harness(controllerA));
      await tester.pumpAndSettle();

      final sharedBefore = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey("row-shared")));
      // Verify "a_only" exists before the swap.
      expect(find.byKey(const ValueKey("row-a_only")), findsOneWidget);

      // Controller B: keeps "shared", drops "a_only", adds "b_only".
      final controllerB = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controllerB.dispose);
      controllerB.setRoots([
        const TreeNode(key: "shared", data: "B_shared"),
        const TreeNode(key: "b_only", data: "B_only"),
      ]);

      await tester.pumpWidget(_harness(controllerB));
      await tester.pumpAndSettle();

      // Shared key: same RenderBox.
      final sharedAfter = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey("row-shared")));
      expect(
        identical(sharedBefore, sharedAfter),
        isTrue,
        reason: "Shared TKey must keep its RenderBox across swap",
      );

      // a_only: gone from the new tree (GC'd by SliverTreeElement post-frame).
      expect(find.byKey(const ValueKey("row-a_only")), findsNothing);

      // b_only: new RenderBox materialized.
      expect(find.byKey(const ValueKey("row-b_only")), findsOneWidget);
    },
  );
}
