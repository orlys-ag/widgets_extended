// Audit repro for finding f23:
// "Setting animationDuration to Duration.zero mid-flight permanently
// strands standalone animations and pending-deletion purges."
//
// StandaloneAnimator._runTick stops the ticker when it reads a zero
// duration WITHOUT completing or clearing the active AnimationState
// entries, and nothing ever restarts the ticker (every mutator forces
// animate=false while the duration is zero, and the animationDuration
// setter does not touch the standalone ticker). A node removed with
// remove(key, animate: true) therefore stays pending-deletion forever:
// it is never purged from the visible order and hasActiveAnimations
// stays true permanently.
//
// These tests assert the EXPECTED (correct) behavior: disabling
// animations mid-flight must complete/purge the in-flight exit (either
// immediately, per the suggested fix, or at latest once a non-zero
// duration is restored, per the setter's documented contract). They
// FAIL on current code if the bug is real.

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("f23: animationDuration set to zero mid-flight", () {
    testWidgets(
      "control: animated remove finalizes on its own at a non-zero duration",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        addTearDown(controller.dispose);

        controller.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ]);

        controller.remove(key: "a", animate: true);
        expect(controller.hasActiveAnimations, true,
            reason: "Sanity: the exit animation must be in flight.");
        expect(controller.isPendingDeletion("a"), true,
            reason: "Sanity: 'a' must be marked pending-deletion.");

        // Bounded pump loop: a 300ms exit needs ~19 frames at 16ms; 60
        // frames (960ms of fake clock) is ample and cannot hang.
        for (var i = 0; i < 60 && controller.hasActiveAnimations; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(controller.hasActiveAnimations, false,
            reason: "Control: the exit animation completes normally.");
        expect(controller.getVisibleIndex("a"), -1,
            reason: "Control: 'a' is purged from the visible order.");
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    testWidgets(
      "zeroing the duration mid-flight must complete and purge the "
      "pending removal instead of stranding it",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        addTearDown(controller.dispose);

        controller.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ]);

        controller.remove(key: "a", animate: true);
        expect(controller.hasActiveAnimations, true,
            reason: "Sanity: the exit animation must be in flight.");
        expect(controller.isPendingDeletion("a"), true,
            reason: "Sanity: 'a' must be marked pending-deletion.");

        // Let one real tick run so the animation has partial progress.
        await tester.pump(const Duration(milliseconds: 16));

        // App reacts to e.g. an accessibility "disable animations"
        // toggle while the exit is in flight.
        controller.animationDuration = Duration.zero;

        // A few bounded frames. The zero-duration tick branch stops the
        // ticker itself, so these pumps cannot hang.
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        // EXPECTED: with animations disabled, the in-flight removal
        // resolves instantly — nothing stays mid-animation and the
        // removed node is gone from the visible order.
        expect(controller.hasActiveAnimations, false,
            reason: "Disabling animations mid-flight must not leave "
                "standalone animations active forever (this also blocks "
                "the render layer's eviction/caching gates).");
        expect(controller.getVisibleIndex("a"), -1,
            reason: "The removed node must be purged from the visible "
                "order, not frozen at partial extent.");
        expect(controller.isPendingDeletion("a"), false,
            reason: "The pending-deletion mark must be resolved by the "
                "finalize/purge path.");
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    testWidgets(
      "restoring a non-zero duration afterwards must not leave the node "
      "stranded forever",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        addTearDown(controller.dispose);

        controller.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ]);

        controller.remove(key: "a", animate: true);
        await tester.pump(const Duration(milliseconds: 16));

        controller.animationDuration = Duration.zero;
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        // Re-enable animations. Per the setter's documented contract
        // ("the per-node standalone ticker re-reads this on every tick,
        // so its animations adjust on the next frame"), the in-flight
        // exit should at the very least resume and finish now.
        controller.animationDuration = const Duration(milliseconds: 300);

        // Bounded pump loop far past the full 300ms duration.
        for (var i = 0; i < 60 && controller.hasActiveAnimations; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(controller.hasActiveAnimations, false,
            reason: "After restoring a non-zero duration and pumping "
                "well past it, no animation may remain active.");
        expect(controller.getVisibleIndex("a"), -1,
            reason: "The removed node must eventually be purged once "
                "animations are re-enabled.");
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
