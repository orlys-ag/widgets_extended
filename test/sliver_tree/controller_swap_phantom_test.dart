/// Regression for R033: phantom-exit ghost maps must be nulled when the
/// controller is swapped, otherwise entries keyed against the old
/// controller's TKey leak into the new controller's layout.
library;

import 'package:flutter/material.dart';
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
    "controller swap nulls _phantomExitGhosts to prevent stale-key leak",
    (tester) async {
      // Controller A: tree where a visible row gets reparented into a
      // collapsed parent, populating _phantomExitGhosts mid-animation.
      final controllerA = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 400), curve: Curves.linear)),
      );
      addTearDown(controllerA.dispose);

      // Mirror the working pattern in phantom_exit_reparent_test.dart:
      // A (expanded) [Y, Y2]; B (collapsed) [b1].
      controllerA.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
      ]);
      controllerA.setChildren("A", [
        const TreeNode(key: "Y", data: "Y"),
        const TreeNode(key: "Y2", data: "Y2"),
      ]);
      controllerA.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);
      controllerA.expand(key: "A", animate: false);

      await tester.pumpWidget(_harness(controllerA));
      await tester.pumpAndSettle();

      // Reparent Y under (collapsed) B with animation — stages an
      // exit-phantom ghost so Y can slide INTO B's row.
      controllerA.moveNode("Y", "B", animate: true);
      // Pump one frame so the slide pipeline runs and the phantom
      // ghost is installed, but don't settle (ghost must be live).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final sliver = tester.renderObject<RenderSliverTree<String, String>>(
          find.byType(SliverTree<String, String>));
      expect(
        sliver.debugPhantomExitGhostCount,
        greaterThan(0),
        reason: "Test setup: exit-phantom ghost should be populated "
            "during the reparent slide",
      );

      // Swap to controller B (shares some key identities — "Y" exists
      // in both, common when both controllers reflect the same
      // underlying data model with different versions).
      final controllerB = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controllerB.dispose);
      controllerB.setRoots([const TreeNode(key: "Y", data: "Y-fresh")]);

      await tester.pumpWidget(_harness(controllerB));
      await tester.pumpAndSettle();

      // After the swap, the same SliverTree element is reused, but
      // its render object's `_phantomExitGhosts` must have been
      // nulled — otherwise the entry for "Y" from controller A
      // would be applied to controller B's "Y" (which has different
      // semantics) and produce wrong paint geometry.
      final sliverAfter = tester.renderObject<RenderSliverTree<String, String>>(
          find.byType(SliverTree<String, String>));
      expect(
        sliverAfter.debugPhantomExitGhostCount,
        0,
        reason: "Controller swap must null _phantomExitGhosts",
      );
    },
  );
}
