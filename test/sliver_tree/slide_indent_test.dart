/// Tests for Phase 1 X-axis (indent) interpolation in `SlideAnimation`
/// and the slide engine.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

Future<void> _primeScheduler(WidgetTester tester) async {
  await tester.pumpWidget(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox.expand(),
    ),
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group("SlideAnimation X-axis fields", () {
    test("startDeltaX defaults to 0; currentDeltaX initializes to startDeltaX",
        () {
      final s = SlideAnimation<String>(
        startDelta: 100.0,
        curve: Curves.linear,
      );
      expect(s.startDeltaX, 0.0);
      expect(s.currentDeltaX, 0.0);
      expect(s.startDelta, 100.0);
      expect(s.currentDelta, 100.0);
    });

    test("explicit startDeltaX initializes both startDeltaX and currentDeltaX",
        () {
      final s = SlideAnimation<String>(
        startDelta: 100.0,
        startDeltaX: -24.0,
        curve: Curves.linear,
      );
      expect(s.startDeltaX, -24.0);
      expect(s.currentDeltaX, -24.0);
    });
  });

  group("animateFromOffsets with X axis", () {
    testWidgets("X-only delta installs a slide with zero Y", (tester) async {
      await _primeScheduler(tester);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      // Same Y, different X (depth changed but row sits at same y).
      controller.animateSlideFromOffsets(
        const {"a": (y: 50.0, x: 24.0)},
        const {"a": (y: 50.0, x: 0.0)},
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );

      expect(controller.hasActiveSlides, true);
      expect(controller.getSlideDelta("a"), 0.0,
          reason: "Y delta = 50 - 50 = 0");
      expect(controller.getSlideDeltaX("a"), 24.0,
          reason: "X delta = 24 - 0 = 24");
      await tester.pumpAndSettle();
    });

    testWidgets("both X and Y lerp independently to 0 at completion",
        (tester) async {
      await _primeScheduler(tester);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      controller.animateSlideFromOffsets(
        const {"a": (y: 100.0, x: 48.0)},
        const {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );

      // First pump records ticker start (elapsed=0).
      await tester.pump();
      // Halfway.
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.getSlideDelta("a"), closeTo(50.0, 10.0),
          reason: "Y lerps from 100 toward 0");
      expect(controller.getSlideDeltaX("a"), closeTo(24.0, 5.0),
          reason: "X lerps from 48 toward 0 with same curve/progress");

      await tester.pumpAndSettle();
      expect(controller.getSlideDelta("a"), 0.0);
      expect(controller.getSlideDeltaX("a"), 0.0);
    });

    testWidgets("composition adds Y and X independently", (tester) async {
      await _primeScheduler(tester);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      // Install Y=100, X=24.
      controller.animateSlideFromOffsets(
        const {"a": (y: 100.0, x: 24.0)},
        const {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final midY = controller.getSlideDelta("a");
      final midX = controller.getSlideDeltaX("a");
      expect(midY, closeTo(50.0, 15.0));
      expect(midX, closeTo(12.0, 5.0));

      // Compose another Y=20, X=10. Composed: midY+20, midX+10.
      controller.animateSlideFromOffsets(
        const {"a": (y: 20.0, x: 10.0)},
        const {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      expect(controller.getSlideDelta("a"), closeTo(midY + 20, 2.0));
      expect(controller.getSlideDeltaX("a"), closeTo(midX + 10, 2.0));

      await tester.pumpAndSettle();
    });

    testWidgets("zero Y AND zero X is skipped (no install)", (tester) async {
      await _primeScheduler(tester);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      controller.animateSlideFromOffsets(
        const {"a": (y: 50.0, x: 24.0)},
        const {"a": (y: 50.0, x: 24.0)},
        duration: const Duration(milliseconds: 100),
      );
      expect(controller.hasActiveSlides, false);
    });
  });

  group("getSlideDeltaX accessor", () {
    testWidgets("returns 0 for non-sliding keys", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);
      expect(controller.getSlideDeltaX("a"), 0.0);
      expect(controller.getSlideDeltaX("nonexistent"), 0.0);
    });
  });
}
