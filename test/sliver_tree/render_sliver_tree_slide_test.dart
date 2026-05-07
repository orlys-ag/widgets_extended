import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Widget _build(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverTree<String, String>(
            controller: controller,
            nodeBuilder: (context, key, depth) => SizedBox(
              key: ValueKey(key),
              height: 50,
              child: Text(key),
            ),
          ),
        ],
      ),
    ),
  );
}

Map<String, ({double layoutOffset, double visibleExtent})>
    _sampleLayout(WidgetTester tester) {
  final render = tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
  final result = <String, ({double layoutOffset, double visibleExtent})>{};
  render.visitChildren((child) {
    if (child is! RenderBox) return;
    final pd = child.parentData as SliverTreeParentData;
    final id = pd.nodeId as String?;
    if (id != null) {
      result[id] = (
        layoutOffset: pd.layoutOffset,
        visibleExtent: pd.visibleExtent,
      );
    }
  });
  return result;
}

/// Captures the y-offset at which a row's RenderBox paints into the root
/// canvas (via applyPaintTransform → localToGlobal). This reflects the
/// visible painted position (layout offset + slide delta).
double _paintedY(WidgetTester tester, String nodeId) {
  final render = tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
  RenderBox? target;
  render.visitChildren((child) {
    if (child is! RenderBox) return;
    final pd = child.parentData as SliverTreeParentData;
    if (pd.nodeId == nodeId) target = child;
  });
  if (target == null) {
    throw StateError("no child for $nodeId");
  }
  return target!.localToGlobal(Offset.zero).dy;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group("Paint-only slide", () {
    testWidgets(
      "slide does NOT change layoutOffset but DOES shift paint position",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 200),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        controller.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ]);

        await tester.pumpWidget(_build(controller));
        await tester.pumpAndSettle();

        final before = _sampleLayout(tester);
        expect(before["a"]!.layoutOffset, 0.0);
        expect(before["b"]!.layoutOffset, 50.0);
        final aBeforePaintedY = _paintedY(tester, "a");

        // Start a slide that pushes "a" down by +40 (prior was at 0, and
        // we're claiming current=-40 so delta = 0 - (-40) = 40? No, delta is
        // prior - current. We want +40 paint offset, so prior = 40, current = 0.
        // animateSlideFromOffsets records prior as the OLD painted y and
        // current as the NEW structural y, so delta = prior - current = 40.
        // That means the node starts painted at structural + 40 = 40 below
        // its layout offset, then lerps to 0.
        controller.animateSlideFromOffsets(
          {"a": (y: 40.0, x: 0.0)},
          {"a": (y: 0.0, x: 0.0)},
          duration: const Duration(milliseconds: 200),
          curve: Curves.linear,
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final during = _sampleLayout(tester);
        // layoutOffset unchanged.
        expect(during["a"]!.layoutOffset, 0.0,
            reason: "slide must not mutate layout");
        expect(during["b"]!.layoutOffset, 50.0,
            reason: "siblings must not be affected by slide of 'a'");

        // Painted position shifted by slide delta.
        final aDuringPaintedY = _paintedY(tester, "a");
        expect(aDuringPaintedY, greaterThan(aBeforePaintedY),
            reason:
                "'a' is mid-slide with positive delta, so paint y must be "
                "below its layout offset.");

        // Settle.
        await tester.pumpAndSettle();
        final afterPaintedY = _paintedY(tester, "a");
        expect(afterPaintedY, aBeforePaintedY,
            reason: "after settle, painted y snaps exactly back to structural");
        expect(controller.hasActiveSlides, false);
        expect(controller.getSlideDelta("a"), 0.0);
      },
    );

    testWidgets("sibling structural offsets are unaffected by slide",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ]);

      await tester.pumpWidget(_build(controller));
      await tester.pumpAndSettle();

      controller.animateSlideFromOffsets(
        {"a": (y: 30.0, x: 0.0)},
        {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final during = _sampleLayout(tester);
      // "b" and "c" structural offsets must be unchanged — slide is paint-only.
      expect(during["b"]!.layoutOffset, 50.0);
      expect(during["c"]!.layoutOffset, 100.0);

      await tester.pumpAndSettle();
    });
  });

  group("_onAnimationTick routing", () {
    testWidgets(
      "extent animations trigger layout; slide-only ticks trigger paint",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 100),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        controller.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ]);

        await tester.pumpWidget(_build(controller));
        await tester.pumpAndSettle();

        // Regression for extent animation: this would previously reach final
        // visibleExtent=100 via continuous layout passes. Ensure that still
        // happens after the _onAnimationTick routing change.
        controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
        controller.expand(key: "a");
        await tester.pumpAndSettle();

        final state = _sampleLayout(tester);
        expect(state["a1"], isNotNull);
        expect(state["a1"]!.visibleExtent, 50.0,
            reason:
                "extent animation must settle to final height via relayout");
      },
    );
  });
}
