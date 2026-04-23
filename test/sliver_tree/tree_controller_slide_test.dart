import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

/// Pumps a minimal widget tree so the test binding's scheduler drives
/// attached tickers (needed for AnimationController-backed slide animations).
Future<void> _primeScheduler(WidgetTester tester) async {
  await tester.pumpWidget(const Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox.expand(),
  ));
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group("animateSlideFromOffsets basic behavior", () {
    testWidgets("installs deltas, ticks to zero, clears state", (tester) async {
      await _primeScheduler(tester);
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

      // Simulate that "a" moved up by 50 (prior was at y=50, now at y=0).
      controller.animateSlideFromOffsets(
        {"a": 50.0, "b": 0.0},
        {"a": 0.0, "b": 50.0},
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );

      expect(controller.hasActiveSlides, true);
      expect(controller.getSlideDelta("a"), 50.0);
      expect(controller.getSlideDelta("b"), -50.0);
      // Slide must NOT count as an active animation.
      expect(controller.hasActiveAnimations, false);

      // First pump records the Ticker's start time (elapsed=0 for this tick).
      await tester.pump();
      // Tick halfway.
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.getSlideDelta("a"), closeTo(25.0, 5.0));

      // Complete.
      await tester.pumpAndSettle();
      expect(controller.hasActiveSlides, false);
      expect(controller.getSlideDelta("a"), 0.0);
      expect(controller.getSlideDelta("b"), 0.0);
    });

    testWidgets("zero rawDelta entries are skipped", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);

      controller.animateSlideFromOffsets(
        {"a": 50.0},
        {"a": 50.0},
        duration: const Duration(milliseconds: 100),
      );
      expect(controller.hasActiveSlides, false);
    });

    testWidgets("getSlideDelta returns 0 for non-sliding keys", (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);

      expect(controller.getSlideDelta("a"), 0.0);
      expect(controller.getSlideDelta("nonexistent"), 0.0);
    });

    testWidgets("no-animation mode clears slides without animating",
        (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);

      controller.animateSlideFromOffsets(
        {"a": 100.0},
        {"a": 0.0},
      );
      // animationDuration is zero → immediate no-op.
      expect(controller.hasActiveSlides, false);
    });
  });

  group("slide interruption and composition", () {
    testWidgets("mid-slide cancel preserves current rendered delta",
        (tester) async {
      await _primeScheduler(tester);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 200),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);
      controller.animateSlideFromOffsets(
        {"a": 100.0},
        {"a": 0.0},
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final midDelta = controller.getSlideDelta("a");
      expect(midDelta, closeTo(50.0, 15.0));

      // Compose a restart that says "the node is now at offset 30 but should
      // be at 0" — prior=30, current=0 → rawDelta=30. Composition:
      // existing.currentDelta (≈50) + 30 = ≈80.
      controller.animateSlideFromOffsets(
        {"a": 30.0},
        {"a": 0.0},
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      // Composed start should be approximately midDelta + 30.
      expect(
        controller.getSlideDelta("a"),
        closeTo(midDelta + 30, 2.0),
      );
      // Let the ticker settle before the test binding checks for leaks.
      await tester.pumpAndSettle();
    });
  });

  group("flag independence", () {
    testWidgets(
        "hasActiveSlides is independent of hasActiveAnimations",
        (tester) async {
      await _primeScheduler(tester);
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
      controller.setChildren("a", [TreeNode(key: "c", data: "C")]);

      // Start an extent animation (expand "a") and a slide concurrently.
      controller.setFullExtent("a", 100.0);
      controller.setFullExtent("c", 100.0);
      controller.expand(key: "a");
      expect(controller.hasActiveAnimations, true);
      expect(controller.hasActiveSlides, false);

      controller.animateSlideFromOffsets(
        {"b": 200.0},
        {"b": 100.0},
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
      expect(controller.hasActiveAnimations, true);
      expect(controller.hasActiveSlides, true);

      // Let them both complete independently.
      await tester.pumpAndSettle();
      expect(controller.hasActiveAnimations, false);
      expect(controller.hasActiveSlides, false);
    });
  });

  group("slide settle ordering", () {
    testWidgets(
        "on completion tick, animation listener fires with hasActiveSlides "
        "still true, map cleared after", (tester) async {
      await _primeScheduler(tester);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 60),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);

      final observations = <({bool hasSlides, double delta})>[];
      controller.addAnimationListener(() {
        observations.add(
          (
            hasSlides: controller.hasActiveSlides,
            delta: controller.getSlideDelta("a"),
          ),
        );
      });

      controller.animateSlideFromOffsets(
        {"a": 60.0},
        {"a": 0.0},
        duration: const Duration(milliseconds: 60),
        curve: Curves.linear,
      );

      // Run all ticks until the slide settles.
      await tester.pumpAndSettle();

      // At least one observation happened.
      expect(observations.isNotEmpty, true);
      // The final notification must capture hasActiveSlides=true with
      // delta snapped to exactly 0.0 (the paint-this-frame-at-zero guarantee).
      final settlement = observations.lastWhere(
        (o) => o.hasSlides && o.delta == 0.0,
        orElse: () => (hasSlides: false, delta: -1),
      );
      expect(settlement.hasSlides, true,
          reason:
              "Completion tick must fire listener while hasActiveSlides is "
              "still true so the sliver element schedules a final zero-delta "
              "paint. Observations: $observations");
      expect(settlement.delta, 0.0);

      // After completion, the map is cleared.
      expect(controller.hasActiveSlides, false);
      expect(controller.getSlideDelta("a"), 0.0);
    });
  });
}
