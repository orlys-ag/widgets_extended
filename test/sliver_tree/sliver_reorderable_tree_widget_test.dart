import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

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
