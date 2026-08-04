/// Regression test for audit item 5.6: the animation-listener channel
/// must coalesce same-frame ticks into ONE dispatch. With K concurrent
/// expand/collapse operations (each owning its own AnimationController +
/// Ticker wired to the coordinator's notifyListeners), an uncoalesced
/// channel fired K+ full listener sweeps per frame — each allocating a
/// defensive copy of the listener list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "one animation-listener invocation per frame with 3 concurrent "
    "operation groups",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 300), curve: Curves.linear)),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "p1", data: "P1"),
        const TreeNode(key: "p2", data: "P2"),
        const TreeNode(key: "p3", data: "P3"),
      ]);
      for (final p in ["p1", "p2", "p3"]) {
        controller.setChildren(p, [
          TreeNode(key: "$p-a", data: "A"),
          TreeNode(key: "$p-b", data: "B"),
        ]);
      }

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

      int fires = 0;
      void listener() {
        fires++;
      }

      controller.addAnimationListener(listener);
      addTearDown(() {
        controller.removeAnimationListener(listener);
      });

      // Three concurrent op-group animations, each with its own ticker.
      controller.expand(key: "p1");
      controller.expand(key: "p2");
      controller.expand(key: "p3");
      await tester.pump();
      expect(controller.hasActiveAnimations, isTrue,
          reason: "setup: three op-groups mid-flight");

      // A pure tick frame: all three tickers advance, but the listener
      // channel must dispatch exactly once.
      fires = 0;
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        fires,
        1,
        reason: "3 op-group tickers ticked this frame; the coalesced "
            "channel must sweep listeners exactly once",
      );

      await tester.pumpAndSettle();
      expect(controller.hasActiveAnimations, isFalse);
    },
  );
}
