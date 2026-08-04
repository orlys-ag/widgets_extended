/// Style-flow tests: [TreeAnimationStyle] drives each animation family
/// on [TreeController]; per-family zero gating (including the
/// kill-switch rule that family-zero dominates explicit per-call
/// durations); per-call null-resolution; widget/sectioned forwarding;
/// and the documented runtime-restyling semantics.
library;

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

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

Future<TreeReorderController<String>> _mountReorderable(
  WidgetTester tester,
  TreeController<String, String> tree,
) async {
  final reorder = TreeReorderController<String>(
    treeController: tree,
    vsync: tester,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              nodeBuilder: (context, key, depth, wrap) {
                return wrap(
                  longPressToDrag: true,
                  child: SizedBox(
                    key: ValueKey("row-$key"),
                    height: 50,
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
  await tester.pumpAndSettle();
  addTearDown(() {
    if (reorder.isDragging) {
      reorder.cancelDrag();
    }
    reorder.dispose();
  });
  return reorder;
}

/// The exotic drop-settle configuration: reorder slides off, settle
/// glides explicitly on.
const TreeAnimationStyle _exoticStyle = TreeAnimationStyle(
  reorderSlide: TreeAnimationSpec(
    duration: Duration.zero,
    curve: Curves.linear,
  ),
  dropSettle: TreeAnimationSpec(
    duration: Duration(milliseconds: 200),
    curve: Curves.linear,
  ),
);

void main() {
  group("style-driven timing", () {
    testWidgets(
        "enterExit spec drives insert enter timing independently of "
        "expandCollapse", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 100),
            curve: Curves.linear,
          ),
          enterExit: TreeAnimationSpec(
            duration: Duration(milliseconds: 400),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "a", data: "A")]);
      controller.insertRoot(const TreeNode(key: "b", data: "B"));
      controller.setFullExtent("b", 40.0);
      expect(controller.getAnimationState("b")?.type, AnimationType.entering,
          reason: "Sanity: insertRoot must start an enter animation");

      // ~208ms: past the 100ms expandCollapse duration, well inside the
      // 400ms enterExit duration.
      for (var i = 0; i < 13; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final midExtent = controller.getCurrentExtent("b");
      expect(midExtent, greaterThan(0.0));
      expect(midExtent, lessThan(40.0),
          reason: "enter must still be in flight at ~200ms — the 400ms "
              "enterExit spec governs, not the 100ms expandCollapse");

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.getCurrentExtent("b"), closeTo(40.0, 0.5));
    });

    testWidgets("expandCollapse spec drives expand op-group timing",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 400),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      controller.setFullExtent("c", 40.0);
      controller.expand(key: "p");
      expect(controller.isExpanded("p"), isTrue,
          reason: "Sanity: expand must have taken effect");

      // ~208ms of a 400ms linear expand: strictly mid-flight.
      for (var i = 0; i < 13; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final mid = controller.getCurrentExtent("c");
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(40.0),
          reason: "expand must still be in flight at ~200ms under the "
              "400ms expandCollapse spec");

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.getCurrentExtent("c"), closeTo(40.0, 0.5));
    });

    testWidgets(
        "zeroing enterExit at runtime finalizes in-flight standalone "
        "animations on the next tick (live re-read through the style)",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          enterExit: TreeAnimationSpec(
            duration: Duration(milliseconds: 400),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);

      controller.setRoots([const TreeNode(key: "a", data: "A")]);
      controller.insertRoot(const TreeNode(key: "b", data: "B"));
      controller.setFullExtent("b", 40.0);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.getAnimationState("b"), isNotNull,
          reason: "Sanity: enter animation must be mid-flight");

      controller.animationStyle = controller.animationStyle.copyWith(
        enterExit: const TreeAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.getAnimationState("b"), isNull,
          reason: "zero enter/exit duration must finalize on the next tick");
      expect(controller.getCurrentExtent("b"), closeTo(40.0, 0.5));
    });
  });

  group("per-family zero gating", () {
    testWidgets(
        "kill switch: an explicit per-call duration cannot revive a "
        "zeroed slide family", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      controller.moveNode(
        "a",
        null,
        index: 2,
        slideDuration: const Duration(milliseconds: 300),
        slideCurve: Curves.linear,
      );
      await tester.pump();
      expect(controller.hasActiveSlides, isFalse,
          reason: "a zero reorderSlide family must dominate explicit "
              "per-call durations (the family kill switch)");
      expect(controller.getSlideDelta("a"), 0.0);
      expect(controller.rootKeys, ["b", "c", "a"],
          reason: "Sanity: the mutation itself must still apply");
    });

    testWidgets(
        "family independence: zero reorderSlide snaps slides while "
        "expand/collapse still animates", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 400),
            curve: Curves.linear,
          ),
          reorderSlide: TreeAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "p", data: "P"),
        const TreeNode(key: "x", data: "X"),
        const TreeNode(key: "y", data: "Y"),
      ]);
      controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      controller.moveNode("x", null, index: 2);
      await tester.pump();
      expect(controller.hasActiveSlides, isFalse,
          reason: "the zeroed slide family must snap");

      controller.expand(key: "p");
      for (var i = 0; i < 13; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final mid = controller.getCurrentExtent("c");
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(48.0),
          reason: "expand/collapse must STILL animate — zeroing one "
              "family must not disable the others");
      await tester.pumpAndSettle();
    });
  });

  group("per-call style resolution", () {
    testWidgets(
        "bare animateSlideFromOffsets consumes the reorderSlide spec",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 400),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      controller.animateSlideFromOffsets(
        {"a": (y: 100.0, x: 0.0)},
        {"a": (y: 0.0, x: 0.0)},
      );
      expect(controller.hasActiveSlides, isTrue,
          reason: "Sanity: the slide must have installed");
      expect(controller.getSlideDelta("a"), 100.0);

      // ~208ms of a 400ms linear slide: roughly halfway.
      for (var i = 0; i < 13; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.getSlideDelta("a"), greaterThan(20.0),
          reason: "a 220ms default would be nearly settled by now — the "
              "400ms reorderSlide spec must govern");
      expect(controller.getSlideDelta("a"), lessThan(80.0));

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.hasActiveSlides, isFalse);
      expect(controller.getSlideDelta("a"), 0.0);
    });

    testWidgets("bare moveNode consumes the reorderSlide spec",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 400),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      controller.moveNode("a", null, index: 2);
      await tester.pump();
      expect(controller.hasActiveSlides, isTrue,
          reason: "Sanity: the bare moveNode must install a slide");
      expect(controller.getSlideDelta("a"), closeTo(-96.0, 1.0));

      // ~256ms in: a 220ms interim default would already have settled;
      // the 400ms reorderSlide spec keeps it mid-flight.
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.hasActiveSlides, isTrue,
          reason: "the style's 400ms reorderSlide spec must govern the "
              "bare moveNode slide");
      expect(controller.getSlideDelta("a").abs(), greaterThan(0.0));

      await tester.pumpAndSettle();
      expect(controller.hasActiveSlides, isFalse);
      expect(controller.getSlideDelta("a"), 0.0);
    });

    testWidgets(
        "bare setReorderPreview / clearReorderPreview consume the "
        "effective makeRoom spec", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          makeRoom: TreeAnimationSpec(
            duration: Duration(milliseconds: 400),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);
      controller.setFullExtent("a", 40.0);
      controller.setFullExtent("b", 40.0);

      controller.setReorderPreview(
        draggedKey: "a",
        targetKey: "b",
        gapBelowTarget: true,
      );
      expect(controller.hasActiveSlides, isTrue,
          reason: "Sanity: the preview must be active");

      // ~208ms of a 400ms linear open: the -40 shift is roughly half.
      for (var i = 0; i < 13; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final mid = controller.getSlideDelta("b");
      expect(mid, lessThan(-8.0),
          reason: "the gap open must be in flight under the 400ms "
              "makeRoom spec");
      expect(mid, greaterThan(-36.0));

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.getSlideDelta("b"), closeTo(-40.0, 0.5),
          reason: "the opened gap HOLDS at the full shift");

      controller.clearReorderPreview(animate: true);
      for (var i = 0; i < 13; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.getSlideDelta("b"), greaterThan(-36.0),
          reason: "the release must animate back under the makeRoom spec");
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.getSlideDelta("b"), 0.0);
    });

    testWidgets(
        "bare reorderRoots consumes reorderSlide, not expandCollapse "
        "(family flow)", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 500),
            curve: Curves.linear,
          ),
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 150),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      controller.reorderRoots(["b", "c", "a"]);
      await tester.pump();
      expect(controller.hasActiveSlides, isTrue,
          reason: "Sanity: the reorder must install a slide");
      expect(controller.getSlideDelta("a"), closeTo(-96.0, 1.0));

      // ~256ms: under the historical expandCollapse-driven staging
      // (500ms) the slide would still be in flight; under the 150ms
      // reorderSlide spec it has settled.
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.hasActiveSlides, isFalse,
          reason: "reorderRoots must consume the reorderSlide spec");
      expect(controller.getSlideDelta("a"), 0.0);
    });

    testWidgets(
        "reorder and move consume the SAME family (semantics-action "
        "consistency)", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 500),
            curve: Curves.linear,
          ),
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 150),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      // "Move down" shape (reorder path).
      controller.reorderRoots(["b", "a", "c"]);
      await tester.pump();
      expect(controller.hasActiveSlides, isTrue);
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.hasActiveSlides, isFalse,
          reason: "reorder path settles on the reorderSlide clock");

      // "Move out/into" shape (moveNode path) on the same tree.
      controller.moveNode("a", null, index: 2);
      await tester.pump();
      expect(controller.hasActiveSlides, isTrue);
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.hasActiveSlides, isFalse,
          reason: "moveNode path settles on the SAME reorderSlide clock — "
              "adjacent semantics actions animate consistently");
    });

    testWidgets("per-call override wins over the style", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 500),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      controller.reorderRoots(
        ["b", "c", "a"],
        slideDuration: const Duration(milliseconds: 100),
        slideCurve: Curves.linear,
      );
      await tester.pump();
      expect(controller.hasActiveSlides, isTrue,
          reason: "Sanity: the reorder must install a slide");
      for (var i = 0; i < 13; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.hasActiveSlides, isFalse,
          reason: "the explicit 100ms per-call duration must beat the "
              "500ms style spec");
    });

    testWidgets(
        "sync-driven reorder rides expandCollapse (batch cohesion "
        "exemption)", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 500),
            curve: Curves.linear,
          ),
          reorderSlide: TreeAnimationSpec(
            duration: Duration(milliseconds: 150),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      final sync = TreeSyncController<String, String>(
        treeController: controller,
      );
      addTearDown(sync.dispose);

      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
      ]);
      await tester.pumpWidget(_buildHarness(controller));
      await tester.pumpAndSettle();

      sync.syncRoots([
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
        const TreeNode(key: "a", data: "A"),
      ]);
      await tester.pump();
      expect(controller.hasActiveSlides, isTrue,
          reason: "Sanity: the sync reorder must install a slide");

      // ~256ms: past the 150ms reorderSlide spec — the sync-driven
      // slide must STILL be in flight, because sync passes the
      // expandCollapse spec explicitly for batch cohesion.
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.hasActiveSlides, isTrue,
          reason: "sync-driven reorders ride expandCollapse, not "
              "reorderSlide");
      await tester.pumpAndSettle();
      expect(controller.hasActiveSlides, isFalse);
    });

    testWidgets("a zero effective makeRoom spec snaps the preview",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          makeRoom: TreeAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);
      controller.setFullExtent("a", 40.0);
      controller.setFullExtent("b", 40.0);

      controller.setReorderPreview(
        draggedKey: "a",
        targetKey: "b",
        gapBelowTarget: true,
      );
      expect(controller.getSlideDelta("b"), -40.0,
          reason: "a zero makeRoom spec must snap to the held offset "
              "with no animation, while other families stay animated");
    });
  });

  group("drop-settle channel (per-family kill switch)", () {
    testWidgets(
        "the channel installs under reorderSlide-zero when dropSettle is "
        "explicitly non-zero", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: _exoticStyle,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      controller.animateDropSettleGlide(
        {"a": (y: 100.0, x: 0.0)},
        {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      expect(controller.hasActiveSlides, isTrue,
          reason: "the drop-settle family is non-zero — its glide must "
              "install even though reorderSlide is zeroed");
      expect(controller.getSlideDelta("a"), 100.0);

      // ~104ms of a 200ms linear glide: strictly mid-flight.
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.getSlideDelta("a"), greaterThan(10.0));
      expect(controller.getSlideDelta("a"), lessThan(90.0));

      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.hasActiveSlides, isFalse);
      expect(controller.getSlideDelta("a"), 0.0);
    });

    testWidgets(
        "the channel's kill switch reads the LIVE effective dropSettle, "
        "dominating captured values", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: _exoticStyle,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      // Restyle dropSettle to zero AFTER the (simulated) session capture.
      controller.animationStyle = controller.animationStyle.copyWith(
        dropSettle: const TreeAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
      );
      controller.animateDropSettleGlide(
        {"a": (y: 100.0, x: 0.0)},
        {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 200), // captured, non-zero
        curve: Curves.linear,
      );
      expect(controller.hasActiveSlides, isFalse,
          reason: "a zero live dropSettle family must kill the glide "
              "even though the captured duration is non-zero");
      expect(controller.getSlideDelta("a"), 0.0);
    });

    testWidgets(
        "an unset dropSettle inherits reorderSlide's zero — the channel "
        "stays off", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          reorderSlide: TreeAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      controller.animateDropSettleGlide(
        {"a": (y: 100.0, x: 0.0)},
        {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      expect(controller.hasActiveSlides, isFalse,
          reason: "unset dropSettle inherits the zeroed reorderSlide — "
              "correct per-family inheritance keeps the glide off");
    });

    testWidgets(
        "e2e: the cancel return glide runs under the exotic config",
        (tester) async {
      final tree = TreeController<String, String>(
        vsync: tester,
        animationStyle: _exoticStyle,
      );
      addTearDown(tree.dispose);
      tree.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
        const TreeNode(key: "d", data: "D"),
      ]);
      final reorder = await _mountReorderable(tester, tree);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey("row-a"))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(reorder.isDragging, isTrue,
          reason: "Sanity: the drag session must be live");

      reorder.cancelDrag();
      expect(tree.hasActiveSlides, isTrue,
          reason: "the cancel return glide must install — dropSettle is "
              "explicitly non-zero even though reorderSlide is zero");
      expect(tree.getSlideDelta("a"), isNot(0.0),
          reason: "the dragged row must be gliding home from the release "
              "position");

      await gesture.up();
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tree.hasActiveSlides, isFalse);
      expect(tree.getSlideDelta("a"), 0.0);
      expect(tree.rootKeys, ["a", "b", "c", "d"],
          reason: "cancel mutates nothing");
    });

    testWidgets(
        "e2e: the commit fallback glide — instant mutation, one row "
        "glides into the new slot and survives the next frame",
        (tester) async {
      final tree = TreeController<String, String>(
        vsync: tester,
        animationStyle: _exoticStyle,
      );
      addTearDown(tree.dispose);
      tree.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
        const TreeNode(key: "d", data: "D"),
      ]);
      final reorder = await _mountReorderable(tester, tree);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey("row-a"))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(reorder.isDragging, isTrue,
          reason: "Sanity: the drag session must be live");
      expect(reorder.currentTarget, isNotNull,
          reason: "Sanity: a drop target must be resolved");

      await gesture.up();
      await tester.pump();

      expect(tree.rootKeys, isNot(equals(["a", "b", "c", "d"])),
          reason: "controller truth must commit instantly");
      expect(tree.hasActiveSlides, isTrue,
          reason: "the fallback glide must be installed — dropSettle is "
              "explicitly non-zero even though the commit slide is dead");
      expect(tree.getSlideDelta("a").abs(), greaterThan(0.0),
          reason: "the dragged row must be gliding from the release "
              "position into its NEW slot");
      expect(tree.getSlideDelta("b"), 0.0,
          reason: "neighbors snap — their motion is the zeroed "
              "reorderSlide family");
      expect(tree.getSlideDelta("c"), 0.0);

      // Frame-survival pin: a staged dead baseline's consume (or the
      // mutation's self-staging) would clear the glide in this frame.
      await tester.pump(const Duration(milliseconds: 16));
      expect(tree.hasActiveSlides, isTrue,
          reason: "the glide must survive the first post-commit frames "
              "(under the disabled-mode split even a staged dead "
              "baseline's consume re-bases rather than clears — this "
              "pin now guards the install path end to end)");

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tree.hasActiveSlides, isFalse);
      expect(tree.getSlideDelta("a"), 0.0);
      // Landing pin (settled extents): the row's painted y equals its
      // NEW structural slot.
      final landedIndex = tree.rootKeys.indexOf("a");
      expect(
        tester.getTopLeft(find.byKey(const ValueKey("row-a"))).dy,
        closeTo(landedIndex * 50.0, 0.5),
        reason: "the glide must land exactly on the new structural slot",
      );
    });

    testWidgets(
        "D-7 dissolved: an external zero-family mutation mid-glide "
        "re-bases the settle glide instead of killing it", (tester) async {
      final tree = TreeController<String, String>(
        vsync: tester,
        animationStyle: _exoticStyle,
      );
      addTearDown(tree.dispose);
      tree.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
        const TreeNode(key: "c", data: "C"),
        const TreeNode(key: "d", data: "D"),
      ]);
      final reorder = await _mountReorderable(tester, tree);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey("row-a"))),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(reorder.isDragging, isTrue,
          reason: "Sanity: the drag session must be live");
      await gesture.up();
      await tester.pump();
      expect(tree.hasActiveSlides, isTrue,
          reason: "Sanity: the fallback glide must be in flight");

      // The "server" moves a row while the glide runs. moveNode's
      // self-staging covers every visible row, and its staged duration
      // resolves to the ZEROED reorderSlide family — pre-split, that
      // consume's clear-all killed the glide (the fix plan's accepted
      // D-7 edge); post-split it must RE-BASE the glide and refuse
      // fresh installs for the shifted neighbors.
      tree.moveNode("d", null, index: 0);
      await tester.pump();
      expect(tree.hasActiveSlides, isTrue,
          reason: "D-7 dissolved: the zero-family consume must re-base "
              "the glide, not clear it");
      expect(tree.getSlideDelta("d"), 0.0,
          reason: "the externally moved row snaps — its motion is the "
              "zeroed reorder family");

      await tester.pump(const Duration(milliseconds: 16));
      expect(tree.hasActiveSlides, isTrue,
          reason: "the re-based glide keeps running on its own clock");

      await tester.pumpAndSettle();
      expect(tree.getSlideDelta("a"), 0.0);
      final landedIndex = tree.rootKeys.indexOf("a");
      expect(
        tester.getTopLeft(find.byKey(const ValueKey("row-a"))).dy,
        closeTo(landedIndex * 50.0, 0.5),
        reason: "the re-based glide must land on the post-mutation slot",
      );
    });
  });

  group("disabled-mode split", () {
    testWidgets(
        "DISABLING stops motion: zeroing reorderSlide mid-flight purges "
        "in-flight slides at the transition", (tester) async {
      final controller = TreeController<String, String>(vsync: tester);
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      controller.animateSlideFromOffsets(
        {"a": (y: 100.0, x: 0.0)},
        {"a": (y: 0.0, x: 0.0)},
      );
      await tester.pump(const Duration(milliseconds: 32));
      expect(controller.hasActiveSlides, isTrue,
          reason: "Sanity: a slide must be mid-flight");

      controller.animationStyle = TreeAnimationStyle.disabled;
      expect(controller.hasActiveSlides, isFalse,
          reason: "the reorderSlide non-zero → zero TRANSITION must purge "
              "in-flight slides (disabling stops motion)");
      expect(controller.getSlideDelta("a"), 0.0);
    });

    testWidgets(
        "zeroing only dropSettle mid-flight does NOT purge a running "
        "glide (no transition purge for non-reorderSlide families)",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: _exoticStyle,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      controller.animateDropSettleGlide(
        {"a": (y: 100.0, x: 0.0)},
        {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      await tester.pump(const Duration(milliseconds: 32));
      expect(controller.hasActiveSlides, isTrue,
          reason: "Sanity: the glide must be mid-flight");

      controller.animationStyle = controller.animationStyle.copyWith(
        dropSettle: const TreeAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
      );
      expect(controller.hasActiveSlides, isTrue,
          reason: "a dropSettle-only zeroing kills at INSTALL time only — "
              "the running glide finishes (matches pre-split behavior)");

      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.hasActiveSlides, isFalse);
      expect(controller.getSlideDelta("a"), 0.0);
    });

    testWidgets(
        "an explicit zero-duration install no longer drops unrelated "
        "in-flight slides", (tester) async {
      final controller = TreeController<String, String>(vsync: tester);
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);

      controller.animateSlideFromOffsets(
        {"a": (y: 100.0, x: 0.0)},
        {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      expect(controller.hasActiveSlides, isTrue,
          reason: "Sanity: a's slide must be in flight");

      controller.animateSlideFromOffsets(
        {"b": (y: 50.0, x: 0.0)},
        {"b": (y: 0.0, x: 0.0)},
        duration: Duration.zero,
        curve: Curves.linear,
      );
      expect(controller.getSlideDelta("b"), 0.0,
          reason: "the zero-duration call installs nothing fresh");
      expect(controller.hasActiveSlides, isTrue,
          reason: "pre-split this call cleared EVERY in-flight slide; "
              "the split must leave a's slide running");
      expect(controller.getSlideDelta("a"), 100.0);

      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.hasActiveSlides, isFalse);
      expect(controller.getSlideDelta("a"), 0.0);
    });

    testWidgets(
        "a zero-family install re-bases a surviving glide on its OWN "
        "timing and refuses fresh installs", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: _exoticStyle,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ]);

      controller.animateDropSettleGlide(
        {"a": (y: 100.0, x: 0.0)},
        {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      expect(controller.getSlideDelta("a"), 100.0,
          reason: "Sanity: the glide must be installed at delta 100");

      // A base change delivered through the ZEROED reorderSlide family
      // (the re-base consume's shape): a's base moved down by 30, and b
      // — which has no entry — must be refused.
      controller.animateSlideFromOffsets(
        {"a": (y: 0.0, x: 0.0), "b": (y: 50.0, x: 0.0)},
        {"a": (y: 30.0, x: 0.0), "b": (y: 80.0, x: 0.0)},
        duration: const Duration(milliseconds: 50),
        curve: Curves.easeInOut,
      );
      expect(controller.getSlideDelta("a"), 70.0,
          reason: "painted continuity: composed delta = 100 + (0 − 30)");
      expect(controller.getSlideDelta("b"), 0.0,
          reason: "no fresh install through a zeroed family");
      expect(controller.hasActiveSlides, isTrue);

      // Own timing preserved: had the entry adopted the staged 50ms, it
      // would be settled by ~96ms; on its own 200ms clock it is not.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.hasActiveSlides, isTrue,
          reason: "the re-based glide must keep its OWN 200ms duration, "
              "not adopt the staged 50ms");
      expect(controller.getSlideDelta("a"), greaterThan(5.0));
      expect(controller.getSlideDelta("a"), lessThan(70.0));

      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.hasActiveSlides, isFalse);
      expect(controller.getSlideDelta("a"), 0.0);
    });
  });

  group("widget forwarding", () {
    testWidgets(
        "SyncedSliverTree forwards animationStyle at init and on rebuild",
        (tester) async {
      const styleA = TreeAnimationStyle(
        expandCollapse: TreeAnimationSpec(
          duration: Duration(milliseconds: 400),
          curve: Curves.linear,
        ),
      );
      const styleB = TreeAnimationStyle(
        reorderSlide: TreeAnimationSpec(
          duration: Duration(milliseconds: 90),
          curve: Curves.linear,
        ),
      );
      TreeController<String, String>? captured;
      Widget build(TreeAnimationStyle style) {
        return MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SyncedSliverTree<String, String>.nodes(
                  roots: const [TreeNode(key: "a", data: "A")],
                  childrenOf: (_) => const [],
                  animationStyle: style,
                  itemBuilder: (context, node) {
                    captured ??= node.controller;
                    return SizedBox(
                      key: ValueKey(node.key),
                      height: 48,
                      child: Text(node.key),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      }

      await tester.pumpWidget(build(styleA));
      expect(captured, isNotNull, reason: "Sanity: a row must have built");
      expect(captured!.animationStyle, styleA);

      await tester.pumpWidget(build(styleB));
      expect(captured!.animationStyle, styleB,
          reason: "didUpdateWidget must forward the new style");
    });

    testWidgets("SectionedListController round-trips the style passthrough",
        (tester) async {
      const style = TreeAnimationStyle(
        expandCollapse: TreeAnimationSpec(
          duration: Duration(milliseconds: 123),
          curve: Curves.linear,
        ),
      );
      final controller = SectionedListController<String, String, String>(
        vsync: tester,
        sectionKeyOf: (s) => s,
        itemKeyOf: (i) => i,
        animationStyle: style,
      );
      addTearDown(controller.dispose);
      expect(controller.animationStyle, style);
      expect(controller.treeController.animationStyle, style);

      const restyled = TreeAnimationStyle(
        reorderSlide: TreeAnimationSpec(
          duration: Duration(milliseconds: 77),
          curve: Curves.linear,
        ),
      );
      controller.animationStyle = restyled;
      expect(controller.treeController.animationStyle, restyled,
          reason: "the setter must reach the underlying tree controller");
    });
  });
}
