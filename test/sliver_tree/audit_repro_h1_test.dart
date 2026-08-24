/// Repro for H1: scroll position is never corrected for estimate vs
/// measured row height.
///
/// Offsets are a global prefix sum; measuring a leading cache band above
/// the viewport rewrites every later offset while `pixels` stays put, so
/// content shifts under the user and `animateScrollToKey` lands off by
/// the accumulated residual. The fix is an anchor-preserving
/// `scrollOffsetCorrection` (render layer) plus a post-frame settle snap
/// in the orchestrator.
///
/// 400 roots of 100 px in a 600 px viewport: every row is taller than
/// `TreeController.defaultExtent` (48), so a far jump lands in a
/// never-measured band with a large positive residual.
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
                  height: 100,
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

TreeController<String, String> _controller(WidgetTester tester) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: TreeAnimationStyle.disabled,
  );
  controller.setRoots([
    for (int i = 0; i < 400; i++) TreeNode(key: "r$i", data: "r$i"),
  ]);
  return controller;
}

void main() {
  testWidgets(
    "measuring the leading cache band preserves the anchor row's painted "
    "position and moves pixels by the residual",
    (tester) async {
      final controller = _controller(tester);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      await tester.pumpWidget(_harness(controller, scroll));
      await tester.pumpAndSettle();

      // Setup sanity: the anchor row really is in the never-measured
      // band before the jump.
      expect(
        controller.getMeasuredExtent("r147"),
        isNull,
        reason: "setup: r147 must be unmeasured before the jump, or the "
            "correction path is not reachable",
      );

      // Under 48 px estimates past the measured opening band (rows
      // 0..17 measured at 100), row 147 spans [7992, 8040): it contains
      // the viewport top at 8000, painted at -8. Measuring the leading
      // cache band (rows 141..146 grow 48 to 100, +312) must not move
      // it: pixels absorbs the residual instead.
      scroll.jumpTo(8000.0);
      await tester.pump();

      expect(
        controller.getMeasuredExtent("r147"),
        isNotNull,
        reason: "setup: the jump frame must have measured the band, or "
            "no residual existed",
      );

      final csTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final anchorTop =
          tester.getTopLeft(find.byKey(const ValueKey("row-r147"))).dy - csTop;
      expect(
        anchorTop,
        closeTo(-8.0, 0.5),
        reason: "the anchor row's painted position must be preserved "
            "across the band measurement; without a correction it shifts "
            "down by the full 312 px residual",
      );
      expect(
        scroll.position.pixels,
        closeTo(8312.0, 0.5),
        reason: "pixels must absorb the residual; painted position and "
            "pixels moving together is what the correction means",
      );
    },
  );

  testWidgets(
    "immediate animateScrollToKey lands the target at the viewport top",
    (tester) async {
      final controller = _controller(tester);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      await tester.pumpWidget(_harness(controller, scroll));
      await tester.pumpAndSettle();

      final ok = await controller.animateScrollToKey(
        "r200",
        scrollController: scroll,
        duration: Duration.zero,
      );
      expect(ok, isTrue, reason: "setup: the scroll must be accepted");
      await tester.pump(); // correction cycle
      await tester.pump(); // settle snap

      final csTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final top =
          tester.getTopLeft(find.byKey(const ValueKey("row-r200"))).dy - csTop;
      expect(
        top,
        closeTo(0.0, 0.5),
        reason: "the target row must land at the viewport top; landing "
            "312 px below is the accumulated estimate-vs-measured "
            "residual of the rows scrolled past",
      );
    },
  );

  testWidgets(
    "animated animateScrollToKey lands exactly after the settle snap",
    (tester) async {
      final controller = _controller(tester);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(_harness(controller, scroll));
      await tester.pumpAndSettle();

      final future = controller.animateScrollToKey(
        "r200",
        scrollController: scroll,
        duration: const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();
      expect(await future, isTrue, reason: "setup: the scroll must complete");
      await tester.pump(); // settle snap's post-frame jump
      await tester.pump();

      final csTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final top =
          tester.getTopLeft(find.byKey(const ValueKey("row-r200"))).dy - csTop;
      expect(
        top,
        closeTo(0.0, 0.5),
        reason: "an animated scroll's absolute ticks overwrite the "
            "corrections applied mid-flight; the post-frame settle snap "
            "must re-derive the landing",
      );
    },
  );

  testWidgets(
    "no correction fires for a pure expand above the viewport",
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
        for (int i = 0; i < 400; i++) TreeNode(key: "r$i", data: "r$i"),
      ]);
      controller.setChildren("r10", [
        for (int j = 0; j < 5; j++) TreeNode(key: "c$j", data: "c$j"),
      ]);

      await tester.pumpWidget(_harness(controller, scroll));
      await tester.pumpAndSettle();
      scroll.jumpTo(3000.0);
      await tester.pumpAndSettle();

      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );
      final before = render.debugPerformLayoutCount;
      controller.expand(key: "r10", animate: true);
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final grew = render.debugPerformLayoutCount - before;
      expect(
        grew,
        lessThanOrEqualTo(6),
        reason: "an expand above the viewport is animation-driven "
            "movement, not a measurement residual: the !isAnimatingNid "
            "filter must keep the correction quiet (at most one layout "
            "per pumped frame plus the expand's own)",
      );

      await tester.pumpAndSettle();
    },
  );
}
