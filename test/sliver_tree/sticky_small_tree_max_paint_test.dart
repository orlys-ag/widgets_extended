/// Regression for R002: paintExtent must not exceed maxPaintExtent.
///
/// When a tree's total scroll extent is small and a sticky header is taller
/// than the in-flow content, the sticky-inflation loop in `performLayout`
/// pushes `paintExtent` above `totalScrollExtent` (which equals
/// `maxPaintExtent`). Before the fix this would trip Flutter's SDK assert
/// `paintExtent <= maxPaintExtent` inside `SliverGeometry.debugAssertIsValid`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "small tree with tall sticky header keeps paintExtent <= maxPaintExtent",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      // Two short rows total ~80px. A tall (100px) sticky header would
      // otherwise inflate paintExtent above totalScrollExtent.
      controller.setRoots([
        const TreeNode(key: "root", data: "root"),
      ]);
      controller.setChildren("root", [
        const TreeNode(key: "child", data: "child"),
      ]);
      controller.expand(key: "root", animate: false);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  maxStickyDepth: 1,
                  nodeBuilder: (_, key, depth) => SizedBox(
                    // Root is the sticky candidate; make it tall (100px).
                    // Children are short (40px). totalScrollExtent ≈ 140.
                    height: depth == 0 ? 100 : 40,
                    child: Text(key),
                  ),
                ),
              ],
            ),
          ),
        ),
      ));

      await tester.pumpAndSettle();

      // Find the sliver render object.
      final sliver = tester
          .renderObject<RenderSliver>(find.byType(SliverTree<String, String>));
      final geometry = sliver.geometry!;

      expect(
        geometry.paintExtent,
        lessThanOrEqualTo(geometry.maxPaintExtent),
        reason: "Sticky inflation must not push paintExtent above "
            "maxPaintExtent (= totalScrollExtent). "
            "paintExtent=${geometry.paintExtent}, "
            "maxPaintExtent=${geometry.maxPaintExtent}",
      );
    },
  );
}
