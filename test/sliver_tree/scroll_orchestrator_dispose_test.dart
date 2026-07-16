/// Regression test for audit item 1.9: disposing the [TreeController]
/// while an animated-concurrent `animateScrollToKey` is mid-flight must
/// cancel the scroll cleanly — the completion loop used to be
/// `while (true) { ...; await endOfFrame; }` with no cancellation hook,
/// leaving the follower listener registered and the internal
/// AnimationController's Ticker active forever (tripping the framework's
/// active-Ticker check) and pumping frames indefinitely for offstage
/// trees.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets(
    "disposing the controller mid animated-concurrent scroll cancels "
    "cleanly (no active ticker, future completes false)",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      controller.setRoots([
        for (int i = 0; i < 20; i++) TreeNode(key: "r$i", data: "R$i"),
      ]);
      // Deep collapsed chain under the last root so the animated
      // ancestor-expansion path is exercised.
      controller.setChildren("r19", [const TreeNode(key: "mid", data: "M")]);
      controller.setChildren("mid", [
        const TreeNode(key: "target", data: "T"),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return SizedBox(height: 50, child: Text(key));
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      bool completed = false;
      bool? result;
      controller
          .animateScrollToKey(
            "target",
            scrollController: scrollController,
            duration: const Duration(milliseconds: 300),
            ancestorExpansion: AncestorExpansionMode.animated,
          )
          .then((v) {
        completed = true;
        result = v;
      });

      // Let the concurrent expand+scroll get genuinely mid-flight.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(completed, isFalse,
          reason: "setup: the animated scroll must still be in flight");

      // Dispose the controller mid-flight — the scrollable is still
      // mounted (hasClients stays true), so only the cancellation path
      // can end the loop.
      controller.dispose();
      await tester.pump();

      expect(
        completed,
        isTrue,
        reason: "the in-flight animateScrollToKey future must complete "
            "when the controller is disposed (cancellation), not keep "
            "awaiting endOfFrame forever",
      );
      expect(result, isFalse,
          reason: "a cancelled scroll reports false (did not complete)");
      // The framework's end-of-test ticker check enforces that the
      // internal scroll-progress AnimationController was disposed.
    },
  );
}
