/// Repro for L7: Pass A's edge-ghost skip must ask the FLIP-only
/// question.
///
/// Pass A skips a row with a registry ghost entry when its COMPOSED
/// delta is non-zero, while Pass A.6 declines to paint it when its
/// FLIP-only delta is zero. With a held make-room preview on a
/// FLIP-settled ghost, composed is non-zero and FLIP is zero, so the
/// row is painted by NEITHER pass, on every paint-only frame until
/// something forces a layout. The hole needs three ingredients: a
/// LEADING-edge ghost (a trailing ghost's structural destination is off
/// the bottom and `_paintRow` culls it anyway), a SECOND FLIP still in
/// flight (or the settle-transition layout clears the registry the same
/// frame), and a held preview large enough to put the row's composed
/// painted position back inside the paint region.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

class _CountPainter extends CustomPainter {
  _CountPainter(this.counts, this.key);

  final Map<String, int> counts;
  final String key;

  @override
  void paint(Canvas canvas, Size size) {
    counts[key] = (counts[key] ?? 0) + 1;
  }

  @override
  bool shouldRepaint(covariant _CountPainter oldDelegate) => true;
}

void main() {
  testWidgets(
    "a FLIP-settled edge ghost under a held preview still paints through "
    "Pass A",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
          makeRoom: TreeAnimationSpec(
            duration: Duration(milliseconds: 200),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      // 60 roots, every row 40 px EXCEPT n20 at 200 px: y(n_i) = 40 * i
      // for i <= 20 (n20 spans [800, 1000)), 1000 + 40 * (i - 21) above.
      controller.setRoots([
        for (int i = 0; i < 60; i++) TreeNode(key: "n$i", data: "n$i"),
      ]);

      final counts = <String, int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 550,
              child: CustomScrollView(
                controller: scroll,
                slivers: [
                  SliverTree<String, String>(
                    controller: controller,
                    addRepaintBoundaries: false,
                    nodeBuilder: (context, key, depth) {
                      return SizedBox(
                        height: key == "n20" ? 200.0 : 40.0,
                        child: CustomPaint(
                          painter: _CountPainter(counts, key),
                          child: Text(key),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Settle at 0 first (measures the leading rows), THEN jump: the
      // paint region becomes [400, 950) in sliver scroll space and this
      // layout measures n20.
      scroll.jumpTo(400.0);
      await tester.pump();
      expect(
        controller.getCurrentExtent("n20"),
        200.0,
        reason: "setup: the preview lift IS n20's measured extent; an "
            "unmeasured row would contribute the estimate instead",
      );

      final sliver = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );

      // n12 goes from y=480 (fully visible) to y=360, overlapping the
      // viewport by 0 px: a TOP edge ghost installs, and only that row
      // installs an entry.
      controller.moveNode(
        "n12",
        null,
        index: 9,
        animate: true,
        slideDuration: const Duration(milliseconds: 300),
        slideCurve: Curves.linear,
      );
      await tester.pump(); // consume the baseline
      expect(
        sliver.debugComposerGhostCount,
        1,
        reason: "setup: exactly one (leading) edge ghost must install",
      );

      // Second FLIP, long and far away, installed WITHOUT a baseline
      // consume so the engine cannot re-base n12.
      controller.animateSlideFromOffsets(
        {"n55": (y: 600.0, x: 0.0)},
        {"n55": (y: 0.0, x: 0.0)},
        duration: const Duration(seconds: 3),
        curve: Curves.linear,
      );
      await tester.pump();

      // Open and HOLD the gap: n20's 200 px lift shifts every row at
      // visible index [5, 21), n12 (index 9) and n17 (index 17) included.
      controller.setReorderPreviewAtIndex(
        draggedKey: "n20",
        gapVisibleIndex: 5,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // n12's 300 ms slide ends here (350 ms in); n55 keeps ticking.
      final layoutsBeforeHold = sliver.debugPerformLayoutCount;
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        controller.hasActiveFlipSlides,
        isTrue,
        reason: "setup: n55's long FLIP must still be in flight",
      );
      expect(
        controller.getFlipSlideDeltaNid(controller.nidOf("n12")),
        0.0,
        reason: "setup: n12's own FLIP must have settled",
      );
      expect(
        controller.getSlideDelta("n12"),
        closeTo(200.0, 0.001),
        reason: "setup: n12 must carry exactly the held preview lift",
      );
      final paintedTop = 360.0 - 400.0 + controller.getSlideDelta("n12");
      expect(
        paintedTop,
        closeTo(160.0, 0.5),
        reason: "setup: the composed painted position must be inside the "
            "paint region",
      );
      expect(
        paintedTop + 40.0,
        lessThan(550.0),
        reason: "setup: the row must be fully visible, so its absence is "
            "user-visible",
      );
      expect(
        sliver.debugComposerGhostCount,
        1,
        reason: "setup: the registry entry must have survived; no layout "
            "ran to prune it",
      );
      expect(
        sliver.debugPerformLayoutCount,
        layoutsBeforeHold,
        reason: "setup: the hold frame must have been paint-only",
      );

      final n12Before = counts["n12"] ?? 0;
      final n17Before = counts["n17"] ?? 0;
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        sliver.debugPerformLayoutCount,
        layoutsBeforeHold,
        reason: "setup: the sampled frame must be paint-only, or Step 0b "
            "prunes the entry and nothing discriminates",
      );
      expect(
        (counts["n17"] ?? 0),
        greaterThan(n17Before),
        reason: "control: n17 carries the same held offset with no "
            "registry entry; its painter advancing proves the frame "
            "painted at all",
      );
      expect(
        (counts["n12"] ?? 0),
        greaterThan(n12Before),
        reason: "a FLIP-settled ghost row with a held preview must fall "
            "through Pass A's skip and paint at its composed position; "
            "skipped by Pass A and declined by Pass A.6, it is painted "
            "by neither",
      );

      await tester.pumpAndSettle();
    },
  );
}
