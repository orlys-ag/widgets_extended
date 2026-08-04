/// Regression test for audit item 4.2: `geometry.cacheExtent` must report
/// the cache-region portion THIS sliver consumes
/// (`calculateCacheOffset(constraints, from: 0, to: scrollExtent)`), not
/// `min(remainingCacheExtent, scrollExtent)`.
///
/// Over-reporting starves every subsequent sliver's cache region: with the
/// tree scrolled so its start is far behind the cache origin, the next
/// sliver received hundreds of px less cache than entitled, so its
/// children weren't pre-built (visible jank crossing the tree/footer
/// boundary).
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "trailing sliver receives the protocol-correct remainingCacheExtent",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      // Tree: 10 roots x 100px = 1000px scroll extent.
      controller.setRoots([
        for (int i = 0; i < 10; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);

      const trailingKey = Key("trailing");
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return SizedBox(height: 100, child: Text(key));
                  },
                ),
                SliverList(
                  key: trailingKey,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) =>
                        SizedBox(height: 50, child: Text("t$i")),
                    childCount: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Viewport is 800x600, default cacheExtent 250. Scroll to 700: the
      // tree's cache-region portion is [700-250, 700+600+250] ∩ [0, 1000]
      // = [450, 1000] → 550. remainingCacheExtent entering the tree is
      // 250 + 600 + 250 = 1100, so the trailing sliver is entitled to
      // 1100 - 550 = 550. The buggy report (min(1100, 1000) = 1000) left
      // it only 100.
      scrollController.jumpTo(700.0);
      await tester.pump();

      final tree = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );
      expect(
        tree.geometry!.cacheExtent,
        550.0,
        reason: "cacheExtent is the cache-region portion this sliver "
            "consumes (calculateCacheOffset), not its whole scrollExtent",
      );

      final trailing = tester.renderObject<RenderSliver>(
        find.byKey(trailingKey, skipOffstage: false),
      );
      expect(
        trailing.constraints.remainingCacheExtent,
        550.0,
        reason: "the trailing sliver's cache budget must not be starved "
            "by the tree over-reporting its cacheExtent",
      );
    },
  );
}
