import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/render_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree_widget.dart';

/// Distinct color used so the indicator's ColoredBox can be matched without
/// false-positives against Scaffold background or other incidental painters.
const Color _kIndicatorColor = Color(0xFFABCDEF);

Finder _indicatorFinder() {
  return find.byWidgetPredicate(
    (w) => w is ColoredBox && w.color == _kIndicatorColor,
  );
}

class _Harness {
  _Harness({required this.tree, required this.reorder});

  final TreeController<String, String> tree;
  final TreeReorderController<String, String> reorder;
}

Future<_Harness> _mount(
  WidgetTester tester, {
  bool longPressToDrag = true,
  double draggedOpacity = 0.3,
}) async {
  final tree = TreeController<String, String>(
    vsync: tester,
    animationDuration: const Duration(milliseconds: 100),
    animationCurve: Curves.linear,
  );
  tree.setRoots([
    TreeNode(key: "a", data: "A"),
    TreeNode(key: "b", data: "B"),
    TreeNode(key: "c", data: "C"),
  ]);

  final reorder = TreeReorderController<String, String>(
    treeController: tree,
    vsync: tester,
    slideDuration: const Duration(milliseconds: 80),
    slideCurve: Curves.linear,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverReorderableTree<String, String>(
              controller: tree,
              reorderController: reorder,
              draggedOpacity: draggedOpacity,
              dropIndicatorColor: _kIndicatorColor,
              nodeBuilder: (context, key, depth, wrap) {
                return wrap(
                  longPressToDrag: longPressToDrag,
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
    reorder.dispose();
    tree.dispose();
  });

  return _Harness(tree: tree, reorder: reorder);
}

/// Reads the Opacity widget value painted above a given row key.
double _opacityOf(WidgetTester tester, String rowKey) {
  final op = tester.widget<Opacity>(
    find.ancestor(
      of: find.byKey(ValueKey("row-$rowKey")),
      matching: find.byType(Opacity),
    ),
  );
  return op.opacity;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group("SliverReorderableTree drag wiring", () {
    testWidgets("long-press-drag downward past a row reorders the roots",
        (tester) async {
      final h = await _mount(tester);

      expect(h.tree.rootKeys, ["a", "b", "c"]);

      // Row "a" lives at y≈0..50. Long-press on "a", wait past the
      // long-press threshold, then drag down onto row "c" (y≈100..150).
      final rowACenter = tester.getCenter(find.byKey(const ValueKey("row-a")));
      final gesture = await tester.startGesture(rowACenter);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(h.tree.rootKeys, isNot(equals(["a", "b", "c"])),
          reason: "drag past row b should have reordered the roots");
      expect(h.tree.rootKeys.first, isNot("a"),
          reason: "'a' must no longer be at index 0 after being dragged down");
      expect(h.tree.rootKeys.toSet(), {"a", "b", "c"},
          reason: "reorder must preserve the membership of the roots");
    });

    testWidgets("dragged source row renders at reduced opacity",
        (tester) async {
      final h = await _mount(tester, draggedOpacity: 0.25);

      expect(_opacityOf(tester, "a"), 1.0,
          reason: "pre-drag opacity must be full");

      final rowACenter = tester.getCenter(find.byKey(const ValueKey("row-a")));
      final gesture = await tester.startGesture(rowACenter);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();

      expect(_opacityOf(tester, "a"), 0.25,
          reason: "mid-drag source row must render at draggedOpacity");
      expect(_opacityOf(tester, "b"), 1.0,
          reason: "non-dragged siblings must remain fully opaque");

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(h.reorder.currentTarget, isNull);
      expect(_opacityOf(tester, "a"), 1.0,
          reason: "post-drop opacity must restore to full");
    });

    testWidgets(
      "drop indicator is painted while dragging over a valid target",
      (tester) async {
        final h = await _mount(tester);

        expect(_indicatorFinder(), findsNothing,
            reason: "no indicator before any drag");

        final rowACenter =
            tester.getCenter(find.byKey(const ValueKey("row-a")));
        final gesture = await tester.startGesture(rowACenter);
        await tester
            .pump(kLongPressTimeout + const Duration(milliseconds: 50));

        // Move pointer onto row "c" (y≈100..150) — a valid, non-no-op target.
        await gesture.moveBy(const Offset(0, 110));
        await tester.pump();

        expect(h.reorder.currentTarget, isNotNull,
            reason: "pointer is over a valid target row");
        expect(_indicatorFinder(), findsOneWidget,
            reason:
                "indicator must be painted in the overlay on pointer move, "
                "driven by TreeReorderController.notifyListeners — NOT by a "
                "per-frame poll that waits for an unrelated frame to fire");

        await gesture.up();
        await tester.pump();
        await tester.pumpAndSettle();

        expect(_indicatorFinder(), findsNothing,
            reason: "indicator overlay removed after drop");
        expect(h.reorder.currentTarget, isNull);
        expect(h.reorder.isDragging, false);
      },
    );

    testWidgets("controller notifies listeners on target changes",
        (tester) async {
      final h = await _mount(tester);

      var notifications = 0;
      h.reorder.addListener(() => notifications++);

      final rowACenter =
          tester.getCenter(find.byKey(const ValueKey("row-a")));
      final gesture = await tester.startGesture(rowACenter);
      await tester
          .pump(kLongPressTimeout + const Duration(milliseconds: 50));

      // startDrag fires one notification (session begin / initial target).
      expect(notifications, greaterThanOrEqualTo(1),
          reason: "startDrag should emit at least one notification");

      final before = notifications;
      // Move to a row that resolves a different drop target.
      await gesture.moveBy(const Offset(0, 110));
      await tester.pump();

      expect(notifications, greaterThan(before),
          reason: "moving to a new zone/row should emit a notification");

      final mid = notifications;
      // Moving within the same third of the same row should NOT fire —
      // _targetsEqual suppresses duplicate notifications.
      await gesture.moveBy(const Offset(0, 1));
      await tester.pump();
      expect(notifications, mid,
          reason: "micro-move within same zone must not re-notify");

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();
    });

    testWidgets(
      "first frame after drop paints moved row at prior y — no flicker",
      (tester) async {
        // Regression guard. The FLIP slide must be installed IN-FRAME by
        // RenderSliverTree.performLayout (via the pending-baseline hook),
        // NOT in a post-frame callback. A post-frame install paints the
        // mutation frame at the new structural y with slideDelta=0, then
        // the next frame snaps back to the prior y and slides forward —
        // visible as a one-frame content flicker at the drop destination.
        final h = await _mount(tester);

        // Row "a" lives at y≈0 before the drag. Confirm baseline.
        expect(
          tester.getTopLeft(find.byKey(const ValueKey("row-a"))).dy,
          0.0,
          reason: "pre-drag painted y must equal structural y",
        );

        final rowACenter =
            tester.getCenter(find.byKey(const ValueKey("row-a")));
        final gesture = await tester.startGesture(rowACenter);
        await tester
            .pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.moveBy(const Offset(0, 120));
        await tester.pump();

        await gesture.up();
        // Exactly one pump — the frame that commits the reorder. With the
        // in-frame baseline consumption, this frame paints "a" at its
        // prior y (0), not its new structural y (≈100).
        await tester.pump();

        expect(h.tree.hasActiveSlides, true,
            reason: "slide must be installed in the same frame as the "
                "structural mutation, not in a post-frame callback");

        final paintedY =
            tester.getTopLeft(find.byKey(const ValueKey("row-a"))).dy;
        expect(paintedY, lessThan(10.0),
            reason: "first frame after drop must paint 'a' near its PRIOR y "
                "(≈0), not at its new structural y (≈100). A y>=50 indicates "
                "the flicker regression: the mutation frame paints at the "
                "new structural position with slideDelta=0.");

        await tester.pumpAndSettle();
        // After the slide settles, "a" lands at its new structural y.
        expect(
          tester.getTopLeft(find.byKey(const ValueKey("row-a"))).dy,
          greaterThanOrEqualTo(50.0),
          reason: "after settle, 'a' must be at its new structural position",
        );
      },
    );

    testWidgets(
      "drop while an extent animation is in flight does not mutate the "
      "sliver during its own performLayout",
      (tester) async {
        // Regression guard for the in-layout FLIP install path. The
        // render object consumes the pending slide baseline at the tail
        // of `performLayout`; if that consume path were to start the
        // slide controller synchronously (`ctrl.value = 0.0` →
        // `_onSlideTick` → `_notifyAnimationListeners` → sliver element
        // `_onAnimationTick`), the element would call `markNeedsLayout`
        // on the sliver currently being laid out and trip Flutter's
        // `_debugCanPerformMutations` assertion. The controller start is
        // therefore deferred to a post-frame callback; this test
        // exercises the `hasActiveAnimations=true at drop time` branch
        // that makes the element route to `markNeedsLayout` rather than
        // the benign `markNeedsPaint` branch.
        // The expand animation must still be running at drop time so the
        // element's tick listener routes through `markNeedsLayout` rather
        // than the `markNeedsPaint` branch. `kLongPressTimeout` (500ms) +
        // pump slack consumes ~600ms before the drop commits, so pick a
        // duration comfortably longer than that.
        final tree = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(seconds: 2),
          animationCurve: Curves.linear,
        );
        tree.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
          TreeNode(key: "c", data: "C"),
        ]);
        tree.setChildren("b", [
          TreeNode(key: "b1", data: "B1"),
          TreeNode(key: "b2", data: "B2"),
        ]);

        final reorder = TreeReorderController<String, String>(
          treeController: tree,
          vsync: tester,
          slideDuration: const Duration(milliseconds: 80),
          slideCurve: Curves.linear,
        );
        addTearDown(() {
          reorder.dispose();
          tree.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  SliverReorderableTree<String, String>(
                    controller: tree,
                    reorderController: reorder,
                    dropIndicatorColor: _kIndicatorColor,
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

        // Kick off an expand animation on "b" and let it run just long
        // enough for one frame of children to become visible.
        tree.expand(key: "b");
        await tester.pump(const Duration(milliseconds: 20));
        expect(tree.hasActiveAnimations, true,
            reason: "setup precondition: an extent animation must be in "
                "flight when the drop is committed, so the element routes "
                "through `markNeedsLayout` in the tick listener");

        final rowACenter =
            tester.getCenter(find.byKey(const ValueKey("row-a")));
        final gesture = await tester.startGesture(rowACenter);
        await tester
            .pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.moveBy(const Offset(0, 120));
        await tester.pump();

        // Critical precondition: the expand animation is still running
        // right before the drop commits. If this ever starts failing, the
        // test is not exercising the `markNeedsLayout` branch anymore and
        // needs its durations adjusted.
        expect(tree.hasActiveAnimations, true,
            reason: "expand animation must still be in flight at drop time "
                "so the tick listener hits the `markNeedsLayout` branch");

        // Drop. The `await tester.pump()` below drives the frame that
        // consumes the FLIP baseline inside performLayout. Prior to the
        // deferred-start fix, this pump threw `_debugCanPerformMutations`
        // from `markNeedsLayout` reached via `ctrl.value = 0` →
        // `_onSlideTick` → sliver element `_onAnimationTick`.
        await gesture.up();
        await tester.pump();

        // No assertion thrown → fix is holding. Settle and verify the
        // tree is still consistent so the test isn't a false positive —
        // the exact landing position depends on animation progress at
        // drop time and isn't what this test is asserting.
        await tester.pumpAndSettle();
        expect(tree.getNodeData("a"), isNotNull,
            reason: "the drop must leave node 'a' somewhere in the tree");
      },
    );

    testWidgets("slide ticks fire after drop so final positions settle",
        (tester) async {
      final h = await _mount(tester);

      final rowACenter = tester.getCenter(find.byKey(const ValueKey("row-a")));
      final gesture = await tester.startGesture(rowACenter);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // Immediately after up() the FLIP slide is mid-flight. Pump a few
      // frames and confirm the controller reports active slides at some
      // point, then settles.
      var sawActiveSlide = false;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 15));
        if (h.tree.hasActiveSlides) sawActiveSlide = true;
      }
      await tester.pumpAndSettle();

      expect(sawActiveSlide, true,
          reason: "a slide animation must run after the commit so rows glide "
              "from their pre-commit painted y to their new structural y");
      expect(h.tree.hasActiveSlides, false,
          reason: "slides must clear after pumpAndSettle");
    });
  });
}
