/// Repro for H3: `animateScrollToKey` after a mutation clamps to the
/// pre-layout `maxScrollExtent`.
///
/// The orchestrator waits a frame only when it expanded ancestors
/// itself; any caller-side mutation (insertRoot, expand) leaves
/// `position.maxScrollExtent` describing the pre-mutation content, and
/// the target silently clamps to it. With H1's settle snap already
/// landed, the LANDING of a zero-duration call self-heals a frame
/// later, so these cases discriminate on the JOURNEY: mid-flight the
/// scroll must be moving toward the real target, not riding a
/// 300 ms animation to the stale clamp (0).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

Widget _harness(
  TreeController<String, String> controller,
  ScrollController scroll,
) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: 50,
                  child: Text(key),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    "animated scroll after a synchronous insertRoot rides toward the "
    "real target, not the stale clamp",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      controller.setRoots([
        for (int i = 0; i < 20; i++) TreeNode(key: "k$i", data: "k$i"),
      ]);

      await tester.pumpWidget(_harness(controller, scroll));
      await tester.pumpAndSettle();
      // Measure every row (the opening layout only measures the cache
      // band; unmeasured tails leave the max at an estimate-based 396).
      scroll.jumpTo(400.0);
      await tester.pump();
      scroll.jumpTo(0.0);
      await tester.pump();

      // Setup sanity: 20 rows of 50 px against a 600 px viewport leave a
      // stale max of exactly 400, so the wrong ride is a real journey (a
      // clamp to the CURRENT pixels would complete instantly, go idle,
      // and let H1's settle snap mask the defect).
      expect(
        scroll.position.maxScrollExtent,
        400.0,
        reason: "setup: pre-mutation maxScrollExtent must be 400",
      );

      for (int i = 20; i < 45; i++) {
        controller.insertRoot(TreeNode(key: "k$i", data: "k$i"),
            animate: false);
      }

      // Fire with no pump in between: the position's geometry is stale.
      final f = controller.animateScrollToKey(
        "k44",
        scrollController: scroll,
        duration: const Duration(milliseconds: 400),
      );
      await tester.pump();
      // The ride can start between frames (after the stale-geometry
      // wait), and a Ticker's epoch is its FIRST tick: give it one
      // epoch-setting tick before sampling elapsed time.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        scroll.position.pixels,
        greaterThan(500.0),
        reason: "mid-flight the scroll must be riding toward the real "
            "target (about 1580 under estimates); a scroll clamped to "
            "the stale max rides a 400 ms animation to 400",
      );

      bool done = false;
      f.then((_) => done = true);
      for (int i = 0; i < 60 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(done, isTrue, reason: "setup: the future must resolve");
      expect(await f, isTrue);
      await tester.pump();
      await tester.pump();
      final csTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final top =
          tester.getTopLeft(find.byKey(const ValueKey("row-k44"))).dy - csTop;
      expect(
        top,
        inInclusiveRange(-1.0, 551.0),
        reason: "the landing must reveal the target inside the viewport "
            "(exact pixels depend on estimate-vs-measured corrections)",
      );
    },
  );

  testWidgets(
    "animated scroll after a caller-side animated expand follows the "
    "growing target",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      controller.setRoots([
        for (int i = 0; i < 10; i++) TreeNode(key: "k$i", data: "k$i"),
      ]);
      controller.setChildren("k9", [
        for (int j = 0; j < 30; j++) TreeNode(key: "k9c$j", data: "k9c$j"),
      ]);

      await tester.pumpWidget(_harness(controller, scroll));
      await tester.pumpAndSettle();
      expect(
        scroll.position.maxScrollExtent,
        0.0,
        reason: "setup: pre-expand maxScrollExtent must be 0",
      );

      // Caller-side expand: the flag flips synchronously, so the
      // orchestrator sees no collapsed ancestor and skips its wait.
      controller.expand(key: "k9");
      expect(
        controller.isExpanded("k9"),
        isTrue,
        reason: "setup: the ancestor chain must hold no collapsed node, "
            "proving the orchestrator's own expansion wait is skipped",
      );

      final f = controller.animateScrollToKey(
        "k9c29",
        scrollController: scroll,
        duration: const Duration(milliseconds: 300),
      );
      await tester.pump();
      // Same epoch-setting tick as case 1: the follower's progress
      // controller can start between frames.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        scroll.position.pixels,
        greaterThan(50.0),
        reason: "mid-flight the scroll must be following the growing "
            "target (the tracked value depends on the clamp against the "
            "mid-expansion max); a scroll clamped to the stale max (0) "
            "never moves",
      );

      bool done = false;
      f.then((_) => done = true);
      for (int i = 0; i < 60 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(done, isTrue, reason: "setup: the future must resolve");
      expect(await f, isTrue);
      await tester.pump();
      await tester.pump();

      expect(
        scroll.position.pixels,
        greaterThan(1000.0),
        reason: "the landing must reveal the deep target",
      );
      final csTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final top =
          tester.getTopLeft(find.byKey(const ValueKey("row-k9c29"))).dy -
          csTop;
      expect(
        top,
        inInclusiveRange(-1.0, 551.0),
        reason: "the target row must end inside the viewport",
      );
    },
  );

  testWidgets(
    "an unresolvable key reports false without killing an in-flight "
    "animated scroll",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      controller.setRoots([
        for (int i = 0; i < 40; i++) TreeNode(key: "k$i", data: "k$i"),
      ]);
      controller.setChildren("k9", [
        for (int j = 0; j < 30; j++) TreeNode(key: "k9c$j", data: "k9c$j"),
      ]);

      await tester.pumpWidget(_harness(controller, scroll));
      await tester.pumpAndSettle();

      final f1 = controller.animateScrollToKey(
        "k9c29",
        scrollController: scroll,
        ancestorExpansion: AncestorExpansionMode.animated,
        duration: const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // GUARD (red only in an intermediate that routes before resolving):
      // an unknown key must fail fast and must not enter any path that
      // cancels the in-flight session.
      final f2 = controller.animateScrollToKey(
        "nope",
        scrollController: scroll,
        duration: const Duration(milliseconds: 300),
      );
      bool f2done = false;
      f2.then((_) => f2done = true);
      await tester.pump();
      expect(f2done, isTrue, reason: "the unresolvable call must fail fast");
      expect(await f2, isFalse);

      bool done = false;
      f1.then((_) => done = true);
      for (int i = 0; i < 80 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(done, isTrue, reason: "setup: the first future must resolve");
      expect(
        await f1,
        isTrue,
        reason: "the animated scroll must survive the unresolvable call; "
            "a cancelled session reports false",
      );

      await tester.pumpAndSettle();
    },
  );
}
