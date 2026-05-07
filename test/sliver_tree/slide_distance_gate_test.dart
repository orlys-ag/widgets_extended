/// Tests for the engine-level slide distance gate (`maxSlideDistance`
/// parameter on `controller.animateSlideFromOffsets`).
///
/// As of v2.3.2, the gate is a **direct-caller safety net**, not the
/// production path. The render layer now uses viewport-edge clamping
/// for slide-IN and synthetic-anchor edge ghosts for slide-OUT (see
/// `slide_viewport_clamp_test.dart`), so the production path naturally
/// bounds slide deltas without relying on the engine cap.
///
/// Direct callers of `controller.animateSlideFromOffsets` (typically
/// tests + advanced API users who bypass the render layer) can still
/// pass `maxSlideDistance:` explicitly to clamp their installs. Tests
/// in this file verify that engine-level behavior in isolation.
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

  group("animateSlideFromOffsets distance gate", () {
    testWidgets("delta exceeding maxSlideDistance is dropped (snap)",
        (tester) async {
      await _primeScheduler(tester);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      // delta = 200; gate = 100 → snap, no slide installed.
      controller.animateSlideFromOffsets(
        const {"a": (y: 200.0, x: 0.0)},
        const {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 100),
        maxSlideDistance: 100.0,
      );
      expect(controller.hasActiveSlides, false,
          reason: "200px delta with 100px gate must be snapped");
      expect(controller.getSlideDelta("a"), 0.0);
    });

    testWidgets("delta within maxSlideDistance installs normally",
        (tester) async {
      await _primeScheduler(tester);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      // delta = 50; gate = 100 → install.
      controller.animateSlideFromOffsets(
        const {"a": (y: 50.0, x: 0.0)},
        const {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 100),
        maxSlideDistance: 100.0,
      );
      expect(controller.hasActiveSlides, true);
      expect(controller.getSlideDelta("a"), 50.0);

      await tester.pumpAndSettle();
    });

    testWidgets("default gate is double.infinity (no gating)", (tester) async {
      await _primeScheduler(tester);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      // 10000px delta with default gate (infinity) → installs.
      controller.animateSlideFromOffsets(
        const {"a": (y: 10000.0, x: 0.0)},
        const {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 100),
      );
      expect(controller.hasActiveSlides, true,
          reason: "default maxSlideDistance is infinity");
      expect(controller.getSlideDelta("a"), 10000.0);

      await tester.pumpAndSettle();
    });

    testWidgets("composed delta exceeding gate clears in-flight slide",
        (tester) async {
      await _primeScheduler(tester);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 1000),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      // First install: delta 80, long duration so currentDelta stays high.
      // Within gate of 100.
      controller.animateSlideFromOffsets(
        const {"a": (y: 80.0, x: 0.0)},
        const {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 1000),
        maxSlideDistance: 100.0,
      );
      expect(controller.hasActiveSlides, true);

      // Single pump records ticker start with elapsed=0 → currentDelta still 80.
      await tester.pump();
      final preDelta = controller.getSlideDelta("a");

      // Compose with rawDelta=200 → composed = preDelta + 200 ≥ 280, way
      // above gate of 100 → clearSlide, snap to 0.
      controller.animateSlideFromOffsets(
        const {"a": (y: 200.0, x: 0.0)},
        const {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 1000),
        maxSlideDistance: 100.0,
      );
      expect(
        preDelta + 200,
        greaterThan(100),
        reason: "sanity: pre-state must satisfy composed > gate",
      );
      expect(controller.getSlideDelta("a"), 0.0,
          reason: "composed delta exceeded gate → clearSlide → snap to 0");
      expect(controller.hasActiveSlides, false);
    });
  });

  group("controller.slideClampOverhangViewports field", () {
    testWidgets("defaults to 0.1", (tester) async {
      final controller = TreeController<String, String>(vsync: tester);
      addTearDown(controller.dispose);
      expect(controller.slideClampOverhangViewports, 0.1);
    });

    testWidgets("is mutable", (tester) async {
      final controller = TreeController<String, String>(vsync: tester);
      addTearDown(controller.dispose);
      controller.slideClampOverhangViewports = 0.0;
      expect(controller.slideClampOverhangViewports, 0.0);
      controller.slideClampOverhangViewports = 0.25;
      expect(controller.slideClampOverhangViewports, 0.25);
    });
  });
}
