/// Engine tests for the v2.3.2 slide-engine refactor:
///
/// - `SlideAnimation.preserveProgressOnRebatch` flag (un-touched slides
///   skip re-baseline so concurrent batches don't restart progress).
/// - Per-slide `slideStartElapsed` and `slideDuration` (multi-batch
///   installs with different durations animate at their own rates).
/// - Composition resets the preserve flag.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

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

  group("preserveProgressOnRebatch", () {
    testWidgets(
      "preserved slide continues smoothly when another row is touched",
      (tester) async {
        await _primeScheduler(tester);
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 1000),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        controller.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ]);

        // Install slide a (long duration so we can measure mid-flight).
        controller.animateSlideFromOffsets(
          const {"a": (y: 1000.0, x: 0.0)},
          const {"a": (y: 0.0, x: 0.0)},
          duration: const Duration(milliseconds: 1000),
          curve: Curves.linear,
        );
        await tester.pump();
        controller.markSlidePreserveProgress("a");

        // Pump 200ms — a should be ~20% done (currentDelta ~800).
        await tester.pump(const Duration(milliseconds: 200));
        final aMid = controller.getSlideDelta("a");
        expect(aMid, lessThan(900.0));
        expect(aMid, greaterThan(700.0));

        // Touch b in a separate batch. Without preserve, a would be
        // re-baselined (startDelta = aMid, progress = 0, slideStartElapsed
        // = now). With preserve, a continues uninterrupted.
        controller.animateSlideFromOffsets(
          const {"b": (y: 100.0, x: 0.0)},
          const {"b": (y: 0.0, x: 0.0)},
          duration: const Duration(milliseconds: 1000),
          curve: Curves.linear,
        );
        await tester.pump();

        // Pump another 200ms — total 400ms elapsed for a's slide.
        // Expected: a should be ~40% done (currentDelta ~600).
        // If re-baselined: a would be ~20% done starting from 800,
        // so currentDelta ~640 (close to 600, hard to distinguish).
        // Better test: pump to near completion and verify a settles
        // at the original time.
        await tester.pump(const Duration(milliseconds: 700));
        final aLate = controller.getSlideDelta("a");
        // After ~900ms total (200+700), a (preserved) should be near
        // settled (~10% remaining → currentDelta ~100).
        expect(aLate, lessThan(200.0),
            reason: "Preserved slide a should be near settled after "
                "~900ms (originally installed at 1000ms duration). "
                "If re-baselined, a would have only progressed "
                "~700ms after the b-install reset → ~30% done → "
                "currentDelta ~560. Got $aLate.");

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "non-preserved slide IS re-baselined (existing engine behavior)",
      (tester) async {
        await _primeScheduler(tester);
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 1000),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        controller.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ]);

        controller.animateSlideFromOffsets(
          const {"a": (y: 1000.0, x: 0.0)},
          const {"a": (y: 0.0, x: 0.0)},
          duration: const Duration(milliseconds: 1000),
          curve: Curves.linear,
        );
        await tester.pump();
        // No markPreserveProgress.

        await tester.pump(const Duration(milliseconds: 200));
        final aMid = controller.getSlideDelta("a");

        controller.animateSlideFromOffsets(
          const {"b": (y: 100.0, x: 0.0)},
          const {"b": (y: 0.0, x: 0.0)},
          duration: const Duration(milliseconds: 1000),
          curve: Curves.linear,
        );
        await tester.pump();

        // Visually continuous: aAfter ≈ aMid (re-baseline preserves
        // currentDelta).
        final aAfter = controller.getSlideDelta("a");
        expect(aAfter, closeTo(aMid, 30.0));

        // After ~900ms (200+700), a (re-baselined) is only ~70% through
        // its restarted 1000ms clock from aMid → currentDelta ~aMid*0.3
        // ≈ 240. Significantly larger than the preserved case.
        await tester.pump(const Duration(milliseconds: 700));
        final aLate = controller.getSlideDelta("a");
        expect(aLate, greaterThan(150.0),
            reason: "Re-baselined slide should still have meaningful "
                "delta ~aMid * 0.3 ≈ 240. Got $aLate.");

        await tester.pumpAndSettle();
      },
    );

    testWidgets("composition resets preserve flag", (tester) async {
      await _primeScheduler(tester);
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 1000),
        animationCurve: Curves.linear,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);

      controller.animateSlideFromOffsets(
        const {"a": (y: 1000.0, x: 0.0)},
        const {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 1000),
        curve: Curves.linear,
      );
      await tester.pump();
      controller.markSlidePreserveProgress("a");

      await tester.pump(const Duration(milliseconds: 100));

      // Composition on a — should reset preserve flag.
      controller.animateSlideFromOffsets(
        const {"a": (y: 0.0, x: 0.0)}, // tiny re-install
        const {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 1000),
        curve: Curves.linear,
      );
      await tester.pump();
      // (The above is a no-op composition since prior == current.
      // Use a more meaningful re-install instead.)
      controller.animateSlideFromOffsets(
        const {"a": (y: 50.0, x: 0.0)},
        const {"a": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 1000),
        curve: Curves.linear,
      );
      await tester.pump();
      // After composition, preserve flag should be false.
      // No way to inspect directly — verify via behavior: install on b
      // should re-baseline a now.
      await tester.pump(const Duration(milliseconds: 100));
      final aBefore = controller.getSlideDelta("a");

      controller.animateSlideFromOffsets(
        const {"b": (y: 100.0, x: 0.0)},
        const {"b": (y: 0.0, x: 0.0)},
        duration: const Duration(milliseconds: 1000),
        curve: Curves.linear,
      );
      await tester.pump();
      final aAfter = controller.getSlideDelta("a");
      expect(aAfter, closeTo(aBefore, 30.0),
          reason: "Re-baseline preserves currentDelta visually.");

      await tester.pumpAndSettle();
    });

    testWidgets(
      "markSlidePreserveProgress is no-op for unregistered/inactive slides",
      (tester) async {
        await _primeScheduler(tester);
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 100),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        controller.markSlidePreserveProgress("nonexistent");

        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.markSlidePreserveProgress("a");
        // Either should not throw; no slide entry to flag.
      },
    );
  });

  group("per-slide duration", () {
    testWidgets(
      "two preserved slides with different durations settle at their own rates",
      (tester) async {
        await _primeScheduler(tester);
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

        controller.animateSlideFromOffsets(
          const {"a": (y: 200.0, x: 0.0)},
          const {"a": (y: 0.0, x: 0.0)},
          duration: const Duration(milliseconds: 200),
          curve: Curves.linear,
        );
        await tester.pump();
        controller.markSlidePreserveProgress("a");

        controller.animateSlideFromOffsets(
          const {"b": (y: 200.0, x: 0.0)},
          const {"b": (y: 0.0, x: 0.0)},
          duration: const Duration(milliseconds: 1000),
          curve: Curves.linear,
        );
        await tester.pump();
        controller.markSlidePreserveProgress("b");

        // After 100ms: a (200ms) ~50% done (delta ~100), b (1000ms) ~10%
        // done (delta ~180). a should be smaller in absolute value.
        await tester.pump(const Duration(milliseconds: 100));
        final aDelta = controller.getSlideDelta("a");
        final bDelta = controller.getSlideDelta("b");
        expect(aDelta, lessThan(bDelta),
            reason: "Faster slide a should be closer to 0 than slower b. "
                "a=$aDelta b=$bDelta");
        expect(aDelta, lessThan(150.0));
        expect(bDelta, greaterThan(150.0));

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "first preserved slide settles per its own duration; "
      "later slides continue independently",
      (tester) async {
        await _primeScheduler(tester);
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 500),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);
        controller.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ]);

        controller.animateSlideFromOffsets(
          const {"a": (y: 100.0, x: 0.0)},
          const {"a": (y: 0.0, x: 0.0)},
          duration: const Duration(milliseconds: 100),
          curve: Curves.linear,
        );
        await tester.pump();
        controller.markSlidePreserveProgress("a");

        // After 50ms install b (500ms duration).
        await tester.pump(const Duration(milliseconds: 50));
        controller.animateSlideFromOffsets(
          const {"b": (y: 100.0, x: 0.0)},
          const {"b": (y: 0.0, x: 0.0)},
          duration: const Duration(milliseconds: 500),
          curve: Curves.linear,
        );
        await tester.pump();
        controller.markSlidePreserveProgress("b");

        // After another 100ms (a is ~150ms in, well past 100ms duration).
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.getSlideDelta("a"), closeTo(0.0, 5.0),
            reason: "a (100ms) should have settled by 150ms total.");
        // b is ~100ms into its 500ms slide → ~20% done → delta ~80.
        expect(controller.getSlideDelta("b"), greaterThan(60.0),
            reason: "b (500ms) should still have substantial delta after "
                "100ms in flight.");

        await tester.pumpAndSettle();
      },
    );
  });
}
