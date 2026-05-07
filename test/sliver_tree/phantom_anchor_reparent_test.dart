/// Tests for collapsed → visible reparenting via the phantom-anchor path.
///
/// When `moveNode(animate: true)` reparents a node whose old subtree was
/// hidden (its old parent or an ancestor was collapsed), the controller
/// stages a phantom anchor — the deepest visible old ancestor — so the
/// render object can install a slide from the anchor's painted position
/// to the moved node's new structural position. With the anchor on-screen,
/// a clip is applied so the anchor visually occludes the emerging row;
/// off-screen, the row slides from the nearest viewport edge.
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
  group("collapsed → visible reparenting", () {
    testWidgets("hidden child reparented to visible parent gets a slide",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // Tree: A (collapsed) [Y, Z]; B (expanded) [b1].
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
      ]);
      controller.setChildren("A", [
        const TreeNode(key: "Y", data: "Y"),
        const TreeNode(key: "Z", data: "Z"),
      ]);
      controller.setChildren("B", [
        const TreeNode(key: "b1", data: "b1"),
      ]);
      // A stays collapsed (default). B explicitly expanded.
      controller.expand(key: "B", animate: false);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      // Sanity: Y is hidden (A is collapsed).
      expect(controller.visibleNodes.contains("Y"), false);
      expect(find.byKey(const ValueKey("row-Y")), findsNothing);

      // Reparent Y to B at index 0 with animate=true.
      controller.moveNode(
        "Y",
        "B",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();

      // Y is now visible AND has an active slide installed via the
      // phantom anchor (A's painted position).
      expect(controller.visibleNodes.contains("Y"), true);
      expect(controller.hasActiveSlides, true,
          reason: "Phantom anchor should have installed a slide for Y");
      expect(controller.getSlideDelta("Y"), isNot(0.0),
          reason: "Y's slide delta should be non-zero (anchor.y - destination.y)");

      await tester.pumpAndSettle();
      expect(controller.hasActiveSlides, false);
      expect(controller.getSlideDelta("Y"), 0.0);
    });

    testWidgets("deeply-nested hidden reparent uses deepest visible ancestor",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // Tree: A (expanded) > B (expanded) > C (COLLAPSED) > Y; plus D
      // (expanded) for the destination. Y is hidden because C is
      // collapsed (its grandparent A is expanded, parent B is expanded,
      // but C breaks the chain).
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "D", data: "D"),
      ]);
      controller.setChildren("A", [
        const TreeNode(key: "B", data: "B"),
      ]);
      controller.setChildren("B", [
        const TreeNode(key: "C", data: "C"),
      ]);
      controller.setChildren("C", [
        const TreeNode(key: "Y", data: "Y"),
      ]);
      controller.setChildren("D", [
        const TreeNode(key: "d1", data: "d1"),
      ]);
      controller.expand(key: "A", animate: false);
      controller.expand(key: "B", animate: false);
      controller.expand(key: "D", animate: false);
      // C stays collapsed → Y is hidden.

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      // Sanity: A, B, C, D, d1 visible; Y hidden.
      expect(controller.visibleNodes.contains("C"), true);
      expect(controller.visibleNodes.contains("Y"), false);

      // Reparent Y to D. The phantom anchor should be C (Y's
      // deepest visible old ancestor), NOT B or A.
      controller.moveNode(
        "Y",
        "D",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();

      // Y now visible with a slide installed.
      expect(controller.visibleNodes.contains("Y"), true);
      expect(controller.hasActiveSlides, true);
      // Y's slide delta = C's painted Y - Y's new structural Y.
      // After move: order is [A, B, C, D, Y, d1]. C is at y=2*48=96
      // (A at 0, B at 48). Y is at y=4*48=192. Slide = 96 - 192 = -96.
      expect(controller.getSlideDelta("Y"), closeTo(-96.0, 1.0),
          reason: "Phantom anchor should be C (deepest visible) at y=96");

      await tester.pumpAndSettle();
    });

    testWidgets("fully-visible reparent does NOT use phantom anchor",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // Tree: A (expanded) [Y]; B (expanded) [b1]. Y is visible.
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
      ]);
      controller.setChildren("A", [const TreeNode(key: "Y", data: "Y")]);
      controller.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);
      controller.expand(key: "A", animate: false);
      controller.expand(key: "B", animate: false);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();
      // Order: [A, Y, B, b1] at y=[0, 48, 96, 144]. Y at y=48.
      expect(controller.visibleNodes.contains("Y"), true);

      controller.moveNode(
        "Y",
        "B",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();
      // After move: [A, B, Y, b1] at y=[0, 48, 96, 144]. Y at y=96.
      // Standard slide: 48 (old) - 96 (new) = -48. NOT phantom-derived.
      expect(controller.getSlideDelta("Y"), closeTo(-48.0, 1.0));

      await tester.pumpAndSettle();
    });

    testWidgets("anchor-off-screen falls back to viewport edge",
        (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // Tree:
      //   A (collapsed) [Y]
      //   spacer-0 .. spacer-4
      //   Z (expanded) [z1]
      //   spacer-5 .. spacer-9 (extra rows so we can scroll past A
      //                          while keeping Z and its child in view)
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        for (int i = 0; i < 5; i++)
          TreeNode(key: "spacer-$i", data: "spacer-$i"),
        const TreeNode(key: "Z", data: "Z"),
        for (int i = 5; i < 10; i++)
          TreeNode(key: "spacer-$i", data: "spacer-$i"),
      ]);
      controller.setChildren("A", [const TreeNode(key: "Y", data: "Y")]);
      controller.setChildren("Z", [const TreeNode(key: "z1", data: "z1")]);
      controller.expand(key: "Z", animate: false);

      // Roots laid out at y = 0,48,96,144,192,240,288,336,384,432,480,528.
      // Total content = 12 rows × 48 = 576 px. Viewport = 400 px.
      // Scrollable range = [0, 176] in this setup (576 - 400).
      await tester.pumpWidget(
        _harness(controller, scrollController: scrollController, height: 400),
      );
      await tester.pumpAndSettle();

      // Scroll to 100 so A (y=0..48) is above the viewport.
      // Viewport now covers scroll-space [100, 500].
      // Z is at y=288 (in viewport). Y's destination after move = 336
      // (z1 is shifted to 384, both in viewport).
      scrollController.jumpTo(100);
      await tester.pump();
      await tester.pumpAndSettle();

      // Reparent Y to Z. A is the phantom anchor; A.y=0 < viewportTop=100
      // → off-screen → fallback to viewport top edge minus overhang
      // (y=100 - 0.1*400 = 60). Y's new structural y = 336. Slide delta
      // = 60 - 336 = -276. |276| < gate (1.5 * 400 = 600) → install.
      controller.moveNode(
        "Y",
        "Z",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();

      expect(controller.hasActiveSlides, true,
          reason: "Off-screen-anchor path must install a slide via the "
              "viewport-edge fallback");
      expect(controller.getSlideDelta("Y"), closeTo(-276.0, 1.0),
          reason: "Slide should anchor at viewport top minus overhang "
              "(y=100-40=60), NOT at A's structural y (=0). delta = "
              "60 - 336 = -276. (If anchor was used directly: delta would "
              "be 0 - 336 = -336.)");

      await tester.pumpAndSettle();
    });

    testWidgets("hidden subtree reparent — children also slide",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 400),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      // A (collapsed) > Y (expanded internally, but hidden because A is
      // collapsed) > [y1, y2]; B (expanded) > [b1].
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
      ]);
      controller.setChildren("A", [const TreeNode(key: "Y", data: "Y")]);
      controller.setChildren("Y", [
        const TreeNode(key: "y1", data: "y1"),
        const TreeNode(key: "y2", data: "y2"),
      ]);
      controller.setChildren("B", [const TreeNode(key: "b1", data: "b1")]);
      controller.expand(key: "Y", animate: false);
      controller.expand(key: "B", animate: false);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      // Y, y1, y2 all hidden (A is collapsed).
      expect(controller.visibleNodes.contains("Y"), false);
      expect(controller.visibleNodes.contains("y1"), false);
      expect(controller.visibleNodes.contains("y2"), false);

      controller.moveNode(
        "Y",
        "B",
        index: 0,
        animate: true,
        slideDuration: const Duration(milliseconds: 400),
        slideCurve: Curves.linear,
      );
      await tester.pump();

      // All three of Y, y1, y2 should now be visible AND each should
      // have a slide installed (they all share the same phantom anchor A).
      expect(controller.visibleNodes.contains("Y"), true);
      expect(controller.visibleNodes.contains("y1"), true);
      expect(controller.visibleNodes.contains("y2"), true);
      expect(controller.hasActiveSlides, true);
      expect(controller.getSlideDelta("Y"), isNot(0.0));
      expect(controller.getSlideDelta("y1"), isNot(0.0));
      expect(controller.getSlideDelta("y2"), isNot(0.0));

      await tester.pumpAndSettle();
    });
  });
}
