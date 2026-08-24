/// Repro for M20: `animateScrollToKey` ignores the sticky band.
///
/// At `alignment: 0.0` the target lands at painted y 0, exactly under
/// its own pinned ancestor. The default keeps that behavior (first
/// case, the recorded defect); `avoidStickyHeaders: true` lands the
/// target just below the band, using settled extents for one-shot
/// scrolls and CURRENT animated extents inside the concurrent follower.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

Widget _harness(
  TreeController<String, String> controller,
  ScrollController scroll, {
  int maxStickyDepth = 1,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              maxStickyDepth: maxStickyDepth,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: 48,
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

/// Six roots of twenty children; `r3c1` additionally carries ten
/// grandchildren (collapsed unless a case expands it), the depth-2
/// target of the animated case.
TreeController<String, String> _controller(
  WidgetTester tester, {
  Duration expand = Duration.zero,
}) {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: expand == Duration.zero
        ? TreeAnimationStyle.disabled
        : TreeAnimationStyle(
            expandCollapse: TreeAnimationSpec(
              duration: expand,
              curve: Curves.linear,
            ),
          ),
  );
  controller.setRoots([
    for (int i = 0; i < 6; i++) TreeNode(key: "r$i", data: "r$i"),
  ]);
  for (int i = 0; i < 6; i++) {
    controller.setChildren("r$i", [
      for (int j = 0; j < 20; j++) TreeNode(key: "r${i}c$j", data: "r${i}c$j"),
    ]);
  }
  controller.setChildren("r3c1", [
    for (int g = 0; g < 10; g++) TreeNode(key: "r3c1g$g", data: "r3c1g$g"),
  ]);
  return controller;
}

/// Painted top of [key]'s row SLOT: its parent-data layout offset minus
/// the sliver's scroll offset. Measured at the slot rather than the row
/// widget because, while a row is entering, the widget's painted top is
/// not the slot's (observed mid-flight: widget 48.64, slot 72.32); the
/// two agree once the row is settled.
double _paintedTop(WidgetTester tester, String key) {
  final render = tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
  RenderObject ro = tester.renderObject(find.byKey(ValueKey("row-$key")));
  while (ro.parentData is! SliverTreeParentData) {
    ro = ro.parent!;
  }
  final slot = (ro.parentData! as SliverTreeParentData).layoutOffset;
  return slot - render.constraints.scrollOffset;
}

void main() {
  testWidgets(
    "default: the target lands under its own pinned ancestor (the "
    "recorded defect, preserved)",
    (tester) async {
      final controller = _controller(tester);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      for (int i = 0; i < 6; i++) {
        controller.expand(key: "r$i", animate: false);
      }
      await tester.pumpWidget(_harness(controller, scroll));
      await tester.pumpAndSettle();

      final ok = await controller.animateScrollToKey(
        "r3c10",
        scrollController: scroll,
        duration: Duration.zero,
      );
      expect(ok, isTrue);
      await tester.pump();
      await tester.pump();

      expect(
        _paintedTop(tester, "r3c10"),
        closeTo(0.0, 0.5),
        reason: "the default must keep landing at the viewport top",
      );
      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );
      final headers = render.debugStickyHeaders;
      expect(
        headers.map((h) => h.nodeId),
        contains("r3"),
        reason: "setup: r3 must be pinned over the landed target",
      );
      final r3 = headers.firstWhere((h) => h.nodeId == "r3");
      expect(r3.pinnedY, closeTo(0.0, 0.5));
      expect(r3.extent, closeTo(48.0, 0.5));
    },
  );

  testWidgets(
    "avoidStickyHeaders lands the target just below the band",
    (tester) async {
      final controller = _controller(tester);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      for (int i = 0; i < 6; i++) {
        controller.expand(key: "r$i", animate: false);
      }
      await tester.pumpWidget(_harness(controller, scroll));
      await tester.pumpAndSettle();

      final ok = await controller.animateScrollToKey(
        "r3c10",
        scrollController: scroll,
        duration: Duration.zero,
        avoidStickyHeaders: true,
      );
      expect(ok, isTrue);
      await tester.pump();
      await tester.pump();

      expect(
        _paintedTop(tester, "r3c10"),
        closeTo(48.0, 0.5),
        reason: "the target must land just below its pinned ancestor's "
            "48 px band, not under it",
      );
      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );
      expect(
        render.debugStickyHeaders.map((h) => h.nodeId),
        contains("r3"),
        reason: "the band itself is unchanged",
      );
    },
  );

  testWidgets(
    "alignment 1.0 is untouched by avoidStickyHeaders (the band does "
    "not cover the bottom)",
    (tester) async {
      final controller = _controller(tester);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      for (int i = 0; i < 6; i++) {
        controller.expand(key: "r$i", animate: false);
      }
      await tester.pumpWidget(_harness(controller, scroll));
      await tester.pumpAndSettle();

      final ok1 = await controller.animateScrollToKey(
        "r3c10",
        scrollController: scroll,
        duration: Duration.zero,
        alignment: 1.0,
      );
      expect(ok1, isTrue);
      await tester.pump();
      await tester.pump();
      final without = _paintedTop(tester, "r3c10");

      final ok2 = await controller.animateScrollToKey(
        "r3c10",
        scrollController: scroll,
        duration: Duration.zero,
        alignment: 1.0,
        avoidStickyHeaders: true,
      );
      expect(ok2, isTrue);
      await tester.pump();
      await tester.pump();
      final with_ = _paintedTop(tester, "r3c10");

      expect(
        with_,
        closeTo(without, 0.5),
        reason: "bottom alignment must be identical with and without the "
            "inset: the formula collapses to the plain bottom pin",
      );
      expect(
        with_,
        closeTo(552.0, 0.5),
        reason: "the row's bottom sits at the viewport bottom (600 - 48)",
      );
    },
  );

  testWidgets(
    "the concurrent follower uses CURRENT animated extents for the band",
    (tester) async {
      final controller = _controller(
        tester,
        expand: const Duration(milliseconds: 600),
      );
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      // r3 and r3c1 stay COLLAPSED: the animated mode expands both while
      // the scroll runs, and r3c1, a depth-1 sticky ancestor of the
      // target, ENTERS under r3's expansion, so its own extent animates
      // 0 -> 48 while it is part of the band.
      for (int i = 0; i < 6; i++) {
        if (i != 3) {
          controller.expand(key: "r$i", animate: false);
        }
      }
      await tester.pumpWidget(
        _harness(controller, scroll, maxStickyDepth: 2),
      );
      await tester.pumpAndSettle();

      // Short scroll under a long expansion: once the scroll's own curve
      // reaches 1.0 the follower jumps straight to its per-tick target,
      // so the painted top IS the inset the follower computed.
      final f = controller.animateScrollToKey(
        "r3c1g5",
        scrollController: scroll,
        ancestorExpansion: AncestorExpansionMode.animated,
        duration: const Duration(milliseconds: 100),
        avoidStickyHeaders: true,
      );
      bool done = false;
      f.then((_) => done = true);
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        done,
        isFalse,
        reason: "setup: the expansion must still be running",
      );
      final current = controller.getCurrentExtent("r3c1");
      expect(current, greaterThan(8.0), reason: "setup: mid-flight");
      expect(current, lessThan(40.0), reason: "setup: mid-flight");
      expect(
        _paintedTop(tester, "r3c1g5"),
        closeTo(48.0 + current, 0.5),
        reason: "mid-flight the target sits under the CURRENT band (48 for "
            "r3 plus r3c1's animated extent); a settled-extent follower "
            "would place it under a 96 px band that does not exist yet",
      );

      for (int i = 0; i < 120 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(done, isTrue, reason: "setup: the future must resolve");
      expect(await f, isTrue);
      await tester.pump();
      await tester.pump();

      expect(
        _paintedTop(tester, "r3c1g5"),
        closeTo(96.0, 0.5),
        reason: "after settle the target sits below the settled 96 px band",
      );
      final render = tester.renderObject<RenderSliverTree<String, String>>(
        find.byType(SliverTree<String, String>),
      );
      expect(
        render.debugStickyHeaders.map((h) => h.nodeId),
        containsAll(["r3", "r3c1"]),
        reason: "the two-level band must exist over the landed target",
      );

      await tester.pumpAndSettle();
    },
  );
}
