// Audit repro for finding f24:
// animateScrollToKey (immediate mode) clamps the target against a
// maxScrollExtent that predates the synchronous ancestor expansion.
//
// Expected (correct) behavior asserted here: after the immediate-mode
// ancestor expansion enlarges the scrollable content, the scroll must land
// far enough down that the target row is inside the viewport (the target
// offset clamped against the POST-expansion maxScrollExtent).
//
// On buggy code the clamp uses the stale pre-expansion maxScrollExtent
// (100.0), so the scroll lands at exactly 100.0 and the target row stays
// more than 1000px below the viewport.
//
// Note on exact values: the sliver estimates never-laid-out rows at
// TreeController.defaultExtent (48px) rather than the harness's 50px, so
// the post-expansion maxScrollExtent is estimate-dependent (~1552 rather
// than the theoretical 1600). The assertions below therefore use the
// row-in-viewport contract plus conservative lower bounds instead of
// estimate-sensitive exact pixel values.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  // Estimator matching the harness row height so offset math is
  // deterministic even for rows that have never been laid out.
  double estimator50(String _) => 50.0;

  testWidgets(
    "immediate-mode animateScrollToKey clamps against the post-expansion "
    "maxScrollExtent and reveals the deep target row",
    (tester) async {
      late TreeController<String, String> controller;
      late ScrollController scrollController;

      await tester.pumpWidget(
        _ScrollToKeyHarness(
          rowHeight: 50,
          rowCount: 10,
          onReady: (c, s) {
            controller = c;
            scrollController = s;
          },
        ),
      );
      await tester.pump();

      // Sanity: 10 roots x 50px = 500px content, viewport 400px.
      expect(scrollController.position.pixels, 0.0);
      expect(
        scrollController.position.maxScrollExtent,
        100.0,
        reason: "sanity: pre-expansion maxScrollExtent must be 100",
      );

      // Give the last root 30 children (50px each); keep it collapsed.
      controller.setChildren("k9", [
        for (int i = 0; i < 30; i++) TreeNode(key: "k9c$i", data: "k9c$i"),
      ]);
      await tester.pump();

      expect(
        controller.getVisibleIndex("k9c25"),
        -1,
        reason: "sanity: target must start hidden behind a collapsed ancestor",
      );
      expect(
        scrollController.position.maxScrollExtent,
        100.0,
        reason: "sanity: collapsed children must not change scroll extent",
      );

      // Scroll to a deep descendant of the collapsed last root using the
      // default immediate ancestor expansion. Do not await directly: a
      // correct implementation may need frames to commit the new layout
      // before it can clamp, so drive frames with a bounded pump loop.
      bool completed = false;
      bool? result;
      unawaited(
        controller
            .animateScrollToKey(
              "k9c25",
              scrollController: scrollController,
              duration: Duration.zero,
              extentEstimator: estimator50,
            )
            .then((ok) {
              result = ok;
              completed = true;
            }),
      );
      for (int i = 0; i < 60 && !completed; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        completed,
        isTrue,
        reason: "animateScrollToKey future must complete",
      );
      expect(result, isTrue, reason: "animateScrollToKey must report success");
      // Let any post-scroll corrective work settle (bounded).
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Sanity: the expansion happened and the new layout is committed.
      // Content is now 40 rows (measured rows 50px, unmeasured estimated
      // at 48px), so maxScrollExtent is at least 40*48 - 400 = 1520.
      expect(controller.isExpanded("k9"), isTrue);
      expect(
        controller.getVisibleIndex("k9c25"),
        35,
        reason: "sanity: k9c25 must be visible at index 35 after expansion",
      );
      expect(
        scrollController.position.maxScrollExtent,
        greaterThanOrEqualTo(1520.0),
        reason:
            "sanity: post-expansion content must dwarf the stale max of 100",
      );

      // EXPECTED behavior: rawTarget for k9c25 is index 35 * 50px = 1750
      // (alignment 0). Clamped against the true post-expansion
      // maxScrollExtent the scroll must land near the tail. Even with the
      // 48px estimate for unmeasured rows, revealing k9c25 requires
      // pixels >= 35*48 + 48 - 400 = 1328, so any correct landing is far
      // above 1300... whereas the buggy stale clamp lands at exactly 100.0.
      expect(
        scrollController.position.pixels,
        greaterThan(1300.0),
        reason:
            "scroll must land at the target offset clamped against the "
            "post-expansion maxScrollExtent (>= ~1328 to reveal k9c25); "
            "the stale pre-expansion clamp lands at exactly 100.0",
      );
      expect(
        find.text("k9c25"),
        findsOneWidget,
        reason: "the target row must be built inside the viewport",
      );
      final Rect rowRect = tester.getRect(find.text("k9c25"));
      final Rect viewportRect = tester.getRect(find.byType(CustomScrollView));
      expect(
        rowRect.top,
        greaterThanOrEqualTo(viewportRect.top - 0.01),
        reason: "target row top must be inside the viewport",
      );
      expect(
        rowRect.bottom,
        lessThanOrEqualTo(viewportRect.bottom + 0.01),
        reason: "target row bottom must be inside the viewport",
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

/// Widget-test harness copied from the `_ScrollToKeyHarness` pattern in
/// sliver_tree_widget_test.dart: [rowCount] roots of [rowHeight] px inside
/// a 400px-tall CustomScrollView.
class _ScrollToKeyHarness extends StatefulWidget {
  const _ScrollToKeyHarness({
    required this.rowHeight,
    required this.rowCount,
    required this.onReady,
  });
  final double rowHeight;
  final int rowCount;
  final void Function(
    TreeController<String, String> controller,
    ScrollController scrollController,
  )
  onReady;

  @override
  State<_ScrollToKeyHarness> createState() => _ScrollToKeyHarnessState();
}

class _ScrollToKeyHarnessState extends State<_ScrollToKeyHarness>
    with TickerProviderStateMixin {
  late final TreeController<String, String> _controller;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _controller = TreeController<String, String>(
      vsync: this,
      animationDuration: Duration.zero,
    );
    _controller.setRoots([
      for (int i = 0; i < widget.rowCount; i++)
        TreeNode(key: "k$i", data: "row $i"),
    ]);
    widget.onReady(_controller, _scrollController);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverTree<String, String>(
                controller: _controller,
                nodeBuilder: (context, key, depth) {
                  return SizedBox(height: widget.rowHeight, child: Text(key));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
