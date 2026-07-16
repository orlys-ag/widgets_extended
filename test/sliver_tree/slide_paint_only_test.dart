/// Regression test for audit item 5.7: pure slide ticks must be routed
/// paint-only. The element used to mark LAYOUT dirty on every slide tick
/// (the paint-only routing was abandoned solely so Step 0a/0b ghost
/// cleanup ran) — a FLIP reorder on a large tree paid a full
/// performLayout per frame. Layout is still required on the install
/// frame and on the settle transition (where ghost cleanup runs).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets(
    "a pure FLIP slide lays out only on its install and settle frames",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        for (int i = 0; i < 6; i++) TreeNode(key: "r$i", data: "R$i"),
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

      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );

      // Pure reorder slide: no extent animations involved.
      controller.moveNode(
        "r0",
        null,
        index: 5,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump(); // install frame (consumes the baseline)
      expect(controller.hasActiveSlides, isTrue,
          reason: "setup: the FLIP slide must be in flight");
      expect(controller.hasActiveAnimations, isFalse,
          reason: "setup: no extent animations — pure slide");

      final afterInstall = render.debugPerformLayoutCount;

      // Mid-slide frames: paint-only, zero layouts.
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.hasActiveSlides, isTrue,
          reason: "setup: still mid-slide after 160 of 400 ms");
      expect(
        render.debugPerformLayoutCount,
        afterInstall,
        reason: "pure slide ticks are paint-only — no performLayout may "
            "run between the install and settle frames",
      );

      // Settle: exactly one more layout (the ghost-cleanup pass).
      await tester.pumpAndSettle();
      expect(controller.hasActiveSlides, isFalse);
      expect(
        render.debugPerformLayoutCount,
        afterInstall + 1,
        reason: "the settle transition triggers exactly one layout pass "
            "so Step 0a/0b ghost pruning runs",
      );
    },
  );
}
