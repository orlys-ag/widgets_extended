/// End-to-end tests for `TreeController.moveNode(animate: true)`.
///
/// Covers the Phase 2 entry point that fans out a baseline-capture request
/// across attached `RenderSliverTree` hosts, mutates structure, and lets
/// the next layout install a FLIP slide via the existing engine.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Widget _buildHarness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: 48,
                  child: Padding(
                    padding: EdgeInsets.only(left: depth * 24.0),
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
}

void main() {
  group("moveNode(animate: true) basic happy path", () {
    testWidgets("installs a slide for the moved row", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);

      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      // Sanity: rows at structural y = 0, 48, 96.
      // Move "a" to the end (between "c" and bottom). New order: B, C, A.
      // a's new structural y = 96; prior y = 0 → slide delta = -96.
      controller.moveNode(
        "a",
        null,
        index: 2,
        animate: true,
        slideDuration: const Duration(milliseconds: 200),
        slideCurve: Curves.linear,
      );
      await tester.pump();

      expect(controller.hasActiveSlides, true,
          reason: "animate: true must install a slide");
      expect(controller.getSlideDelta("a"), closeTo(-96.0, 1.0),
          reason: "a moved from y=0 to y=96, delta = 0 - 96 = -96");

      // Settle.
      await tester.pumpAndSettle();
      expect(controller.hasActiveSlides, false);
      expect(controller.getSlideDelta("a"), 0.0);
    });

    testWidgets("animate: false (default) installs no slide", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      controller.moveNode("a", null, index: 1);
      await tester.pump();

      expect(controller.hasActiveSlides, false,
          reason: "animate: false must not stage a baseline");
      expect(controller.getSlideDelta("a"), 0.0);
    });
  });

  group("moveNode(animate: true) edge cases", () {
    testWidgets("no-op move (same parent, no index) does not stage a baseline",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "a", data: "A")]);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      // Move "a" to its own current parent (root, since it's already a root)
      // with no index — the no-op early return must fire.
      controller.moveNode("a", null, animate: true);
      await tester.pump();

      // No slide installed (mutation was a no-op).
      expect(controller.hasActiveSlides, false);

      // Critical: a SUBSEQUENT animated move must succeed (the no-op path
      // must not have left a stuck pending baseline that blocks future
      // stages under first-wins).
      controller.setChildren("a", [const TreeNode(key: "a1", data: "A1")]);
      controller.expand(key: "a");
      await tester.pumpAndSettle();

      controller.moveNode(
        "a1",
        null,
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 200),
        slideCurve: Curves.linear,
      );
      await tester.pump();
      expect(controller.hasActiveSlides, true,
          reason: "the prior no-op move must not have left a stuck baseline");

      await tester.pumpAndSettle();
    });

    testWidgets("animate: true with no mounted sliver is a no-op (no exception)",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);

      // No SliverTree mounted → no render hosts registered.
      controller.moveNode("a", null, index: 1, animate: true);

      // Mutation still applied; no slide installed; no exception.
      expect(controller.getIndexInParent("a"), 1);
      expect(controller.hasActiveSlides, false);
    });
  });

  group("moveNode(animate: true) same-frame coherence (first-wins)", () {
    testWidgets(
      "two animated moves in one synchronous block share one baseline",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 1000),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        controller.setRoots([
          const TreeNode(key: "a", data: "A"),
          const TreeNode(key: "b", data: "B"),
          const TreeNode(key: "c", data: "C"),
          const TreeNode(key: "d", data: "D"),
        ]);
        await tester.pumpWidget(_buildHarness(controller));
        await tester.pumpAndSettle();

        // Move "a" to end (becomes index 3) AND "d" to start (becomes
        // index 0). Two moves in one synchronous block. Pre-move order:
        // [a, b, c, d] at y = [0, 48, 96, 144]. Post-move order:
        // [d, b, c, a] at y = [0, 48, 96, 144].
        //
        // First-wins baseline captures pre-everything painted positions.
        // Per-row delta:
        //   a: prior 0 - current 144 = -144
        //   b: prior 48 - current 48 = 0 (no slide)
        //   c: prior 96 - current 96 = 0 (no slide)
        //   d: prior 144 - current 0 = +144
        controller.moveNode(
          "a",
          null,
          index: 3,
          animate: true,
          slideDuration: const Duration(milliseconds: 1000),
          slideCurve: Curves.linear,
        );
        controller.moveNode(
          "d",
          null,
          index: 0,
          animate: true,
          // Different duration on second call — should be ignored under
          // first-wins; first call's 1000ms wins.
          slideDuration: const Duration(milliseconds: 50),
          slideCurve: Curves.linear,
        );
        await tester.pump();

        // Both moved rows have slides matching their full pre→post deltas.
        expect(controller.getSlideDelta("a"), closeTo(-144.0, 1.0),
            reason: "first-wins baseline must reflect pre-anything position");
        expect(controller.getSlideDelta("d"), closeTo(144.0, 1.0),
            reason: "first-wins baseline must reflect pre-anything position");

        // First call's 1000ms duration wins. Pump 100ms — slide is ~10%
        // through, must still be active. (Under "latest wins" with 50ms,
        // the slide would have completed by now.)
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.hasActiveSlides, true,
            reason: "first call's 1000ms duration must win, not second's 50ms");

        await tester.pumpAndSettle();
        expect(controller.hasActiveSlides, false);
      },
    );

    testWidgets("two animated moves inside runBatch coalesce coherently",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 500),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      // Inside runBatch: same-frame coherence still holds; no StateError.
      controller.runBatch(() {
        controller.moveNode("a", null, index: 2, animate: true);
        controller.moveNode("c", null, index: 0, animate: true);
      });
      await tester.pump();

      expect(controller.hasActiveSlides, true,
          reason: "runBatch with animated moves still installs slides");
      // After both moves: order is [c, b, a]. a went from 0→96, c went
      // from 96→0. Slide deltas reflect full pre→post movement.
      expect(controller.getSlideDelta("a"), closeTo(-96.0, 1.0));
      expect(controller.getSlideDelta("c"), closeTo(96.0, 1.0));

      await tester.pumpAndSettle();
    });
  });

  group("moveNode(animate: true) controller disposal safety", () {
    testWidgets("controller disposed before render-object detach is safe",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
      );

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      // Dispose controller while sliver is still mounted.
      controller.dispose();

      // Unmount — detach() will call unregisterRenderHost on the disposed
      // controller. The Set was cleared in dispose(), so Set.remove on an
      // empty set is a no-op. Must not crash.
      await tester.pumpWidget(const SizedBox.shrink());
      // No expectation other than "no exception."
    });
  });
}
