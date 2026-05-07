/// Tests for visible → hidden reparenting via the exit-phantom (ghost) path.
///
/// Symmetric to phantom_anchor_reparent_test.dart. When `moveNode(animate: true)`
/// reparents a visible node into a collapsed parent (or any new ancestor
/// chain that ends up collapsed), the controller stages an exit-phantom
/// anchor — the deepest visible NEW ancestor — and the render object:
///   1. Injects the anchor's painted position as the slide DESTINATION.
///   2. Retains the moved node's render box past the visible-order purge.
///   3. Paints the ghost in a separate pass clipped so the anchor visually
///      occludes the row as it slides into the parent's row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Widget _harness(
  TreeController<String, String> controller, {
  ScrollController? scrollController,
  double height = 600,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: CustomScrollView(
          controller: scrollController,
          slivers: <Widget>[
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: 48,
                  child: Padding(
                    padding: EdgeInsets.only(left: depth * 20.0),
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
  group("visible → hidden reparenting", () {
    testWidgets("visible row reparented to collapsed parent gets exit slide",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // Tree: A (expanded) [Y, Y2]; B (COLLAPSED) [b1]. Y, Y2 visible.
      // Layout: A=0, Y=48, Y2=96, B=144. After move Y to B (still
      // collapsed): order is [A, Y2, B]. Y2 shifts up to y=48, B to
      // y=96. Slide delta for Y = baseline 48 - new anchor B's
      // position 96 = -48 (non-zero ✓).
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
      ]);
      controller.setChildren("A", [
        const TreeNode(key: "Y", data: "Y"),
        const TreeNode(key: "Y2", data: "Y2"),
      ]);
      controller.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);
      controller.expand(key: "A", animate: false);
      // B intentionally NOT expanded.

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      // Sanity: Y is visible at structural y=48.
      expect(controller.visibleNodes.contains("Y"), true);
      expect(controller.visibleNodes.contains("b1"), false);

      // Reparent Y to collapsed B at index 0.
      controller.moveNode(
        "Y",
        "B",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();

      // Y is now structurally under B but B is collapsed → Y is hidden.
      expect(controller.visibleNodes.contains("Y"), false,
          reason: "After move, B is still collapsed → Y is structurally "
              "under B but not in visibleNodes");
      // The exit-phantom path should have installed a slide for Y so it
      // visually slides into B's row before disappearing.
      expect(controller.hasActiveSlides, true,
          reason: "Exit phantom should install a slide for Y");
      expect(controller.getSlideDelta("Y"), isNot(0.0),
          reason: "Y should have a non-zero exit slide delta");

      // After the slide settles, Y is no longer in active slides AND
      // Y stays out of visibleNodes (B is still collapsed). Y's render
      // box will be released by the next stale-eviction pass.
      await tester.pumpAndSettle();
      expect(controller.hasActiveSlides, false);
      expect(controller.visibleNodes.contains("Y"), false);
    });

    testWidgets("exit slide delta = baseline_Y - new_anchor_position",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // Setup: A (expanded) [Y]; B (collapsed). Layout:
      //   A at y=0, Y at y=48, B at y=96.
      // After move Y to B (collapsed): order is [A, B]. B at y=48.
      // Exit anchor = B (the new visible ancestor — B IS visible since
      // it's a root, just not expanded). B's new structural y = 48.
      // Y's baseline y = 48 (its old position). Slide delta = 48 - 48 = 0.
      // Hmm, that's zero — let me make the test position different.
      //
      // Better setup: A (expanded) [Y, Y2]; B (collapsed). Layout:
      //   A at 0, Y at 48, Y2 at 96, B at 144.
      // After move Y to B: order is [A, Y2, B]. Y2 at 48, B at 96.
      // Exit anchor B at y=96. Y baseline = 48. Slide = 48 - 96 = -48.
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
      ]);
      controller.setChildren("A", [
        const TreeNode(key: "Y", data: "Y"),
        const TreeNode(key: "Y2", data: "Y2"),
      ]);
      controller.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);
      controller.expand(key: "A", animate: false);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      controller.moveNode(
        "Y",
        "B",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();

      // Y baseline = 48. New B position (after Y2 takes Y's slot) = 96.
      // Slide delta = 48 - 96 = -48.
      expect(controller.getSlideDelta("Y"), closeTo(-48.0, 1.0),
          reason: "Y slides from old position (y=48) toward new anchor B "
              "(y=96). delta = 48 - 96 = -48.");

      await tester.pumpAndSettle();
    });

    testWidgets("nested-collapsed reparent uses deepest visible new ancestor",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // Tree: A (expanded) [Y]; D (expanded) > E (COLLAPSED) > F.
      // Reparent Y to F. F is hidden because E is collapsed. Y is
      // moved structurally under F but visually disappears into E
      // (the deepest visible NEW ancestor).
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "D", data: "D"),
      ]);
      controller.setChildren("A", [const TreeNode(key: "Y", data: "Y")]);
      controller.setChildren("D", [const TreeNode(key: "E", data: "E")]);
      controller.setChildren("E", [const TreeNode(key: "F", data: "F")]);
      controller.expand(key: "A", animate: false);
      controller.expand(key: "D", animate: false);
      // E intentionally NOT expanded → F hidden.

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      // Layout: A=0, Y=48, D=96, E=144. Y visible.
      expect(controller.visibleNodes.contains("Y"), true);
      expect(controller.visibleNodes.contains("F"), false);

      // Reparent Y to F (under E, hidden).
      controller.moveNode(
        "Y",
        "F",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();

      // Y is now structurally under F (hidden). visibleNodes after
      // move: [A, D, E]. A=0, D=48, E=96. Exit anchor = E (deepest
      // visible new ancestor). Y baseline = 48. Slide = 48 - 96 = -48.
      expect(controller.visibleNodes.contains("Y"), false);
      expect(controller.hasActiveSlides, true);
      expect(controller.getSlideDelta("Y"), closeTo(-48.0, 1.0),
          reason: "Y slides toward E (deepest visible new ancestor). "
              "Y baseline=48, E new position=96. delta = -48.");

      await tester.pumpAndSettle();
    });

    testWidgets("hidden → hidden reparent does NOT install a slide",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // Tree: A (collapsed) > Y; B (collapsed) > b1. Y is hidden under
      // collapsed A. Move Y to also-collapsed B → Y stays hidden.
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
      ]);
      controller.setChildren("A", [const TreeNode(key: "Y", data: "Y")]);
      controller.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      expect(controller.visibleNodes.contains("Y"), false);

      controller.moveNode(
        "Y",
        "B",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();

      // Neither entry-phantom nor exit-phantom should fire — Y was
      // hidden before AND is hidden after. No slide visible to the user.
      expect(controller.hasActiveSlides, false,
          reason: "hidden→hidden moves can't be animated meaningfully — "
              "the user can't see Y at either endpoint");
    });

    testWidgets("exit anchor off-screen falls back to viewport edge",
        (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // Tree: A (expanded) [Y]; spacers; B (collapsed) far below.
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        for (int i = 0; i < 10; i++)
          TreeNode(key: "sp-$i", data: "sp-$i"),
        const TreeNode(key: "B", data: "B"),
      ]);
      controller.setChildren("A", [const TreeNode(key: "Y", data: "Y")]);
      controller.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);
      controller.expand(key: "A", animate: false);

      // Layout pre-move: A=0, Y=48, sp0..sp9 at 96..528, B=576.
      await tester.pumpWidget(
        _harness(controller, scrollController: scrollController, height: 400),
      );
      await tester.pumpAndSettle();

      // Move Y to B — Y is visible, B is at y=576 (below viewport).
      // After move (B still collapsed): order is [A, sp0..sp9, B].
      // A=0, sp0=48, ..., sp9=480, B=528. B at y=528 is below viewport
      // [0, 400] → off-screen below. Exit anchor B is off-screen →
      // fallback to viewport bottom edge plus overhang
      // (y=400 + 0.1*400 = 440).
      // Y baseline = 48. Destination = 440.
      // Slide delta = 48 - 440 = -392. |delta| < gate 600 → install.
      controller.moveNode(
        "Y",
        "B",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();

      expect(controller.hasActiveSlides, true);
      expect(controller.getSlideDelta("Y"), closeTo(-392.0, 1.0),
          reason: "B is off-screen → fallback to viewport bottom plus "
              "overhang (y=400+40=440). Y baseline=48. delta = 48 - 440 "
              "= -392.");

      await tester.pumpAndSettle();
    });
  });
}
