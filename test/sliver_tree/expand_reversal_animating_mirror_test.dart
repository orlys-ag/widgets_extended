import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  testWidgets("M22: reversing an in-flight collapse leaves the animating "
      "mirror stale", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: const TreeAnimationStyle(
        expandCollapse: TreeAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.setRoots([TreeNode(key: "A", data: "A")]);
    controller.setChildren("A", [
      TreeNode(key: "a1", data: "A1"),
      TreeNode(key: "a2", data: "A2"),
    ]);
    controller.expand(key: "A");
    // The bare pump is load-bearing, not tidiness. A ticker started
    // outside a frame leaves `_startTime` null (scheduler/ticker.dart:
    // 202-204) and the first tick sets `_startTime ??= timeStamp`
    // (:276), so it reports elapsed 0. Without a bare pump to start the
    // clock, the timed pump below advances the animation by nothing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Start a collapse and let it run PART way, so the group for "A" is
    // genuinely mid-flight. Expanding now takes expand Path 1, the
    // reversal branch, which is the only path under test.
    controller.collapse(key: "A");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Sanity: the collapse really is partway, not parked at either end.
    // An earlier version of this test pumped without starting the clock
    // and reversed a collapse that had made zero progress.
    //
    // The bound must be the row's own full extent, not an arbitrary
    // number: computeExtent IGNORES the `fullExtent` argument whenever
    // `targetExtent != -1.0` (types.dart:251-257), and an unmeasured row
    // targets `TreeController.defaultExtent`, which is 48.0. (Named,
    // not cited by line: it moves whenever that file is edited, and
    // M23's insert already staled a `:831` here once.) Passing
    // 100.0 here made the upper bound unreachable, so the degenerate
    // case measured 48.0 and still passed.
    final full =
        controller.getMeasuredExtent("a1") ?? TreeController.defaultExtent;
    final midExtent = controller.getAnimatedExtent("a1", full);
    expect(
      midExtent,
      lessThan(full),
      reason: "sanity: the collapse must have started",
    );
    expect(
      midExtent,
      greaterThan(0.0),
      reason: "sanity: the collapse must not have finished",
    );

    expect(
      controller.isAnimating("a1"),
      isTrue,
      reason:
          "sanity: the collapse must be in flight, so the reversal branch "
          "is the path expand() takes below",
    );

    // A synchronous listener that reads the union mirror is what poisons
    // the cache: it rebuilds from `opGroups.groups` DURING the detach
    // window, when the group is temporarily absent, and caches that
    // result against the current generation. The scroll orchestrator's
    // follower is exactly such a listener.
    controller.addAnimationListener(() {
      controller.currentlyAnimatingKeys;
    });

    // Called from the test body, NOT from a ticker callback, so the
    // dispatch is inline rather than deferred to a microtask past the
    // detach window.
    controller.expand(key: "A");

    // CONTROL, asserted FIRST so the assertions below are diagnosable.
    // The plan lists this second, but its stated job is to prove the
    // group is genuinely alive; that only rules anything out if it runs
    // before the assertions it explains. It passes both today and after
    // the fix, because runWithGroupDetached re-inserts the group in its
    // `finally` before this line can run.
    expect(
      controller.hasActiveAnimations,
      isTrue,
      reason:
          "control: the group survives the detach window, so a failure "
          "below is a stale MIRROR, not a missing group",
    );

    expect(
      controller.isAnimating("a1"),
      isTrue,
      reason:
          "the reversed group's members must still read as animating; "
          "today the mirror rebuilt inside the detach window omits them "
          "and is cached against the pre-detach generation",
    );

    expect(
      controller.computeFirstAnimatingVisibleIndex(),
      lessThan(controller.visibleNodeCount),
      reason:
          "the first animating visible index must find the reversed "
          "group's members; today it reads the same poisoned mirror and "
          "returns the end of the order",
    );

    // Let the reversal finish so the group disposes its AnimationController.
    // Without this the FIXED code fails teardown with "A Ticker was
    // active at the end of the test" (widget_tester.dart:1042-1059), so
    // the test could never go green. It does NOT mask a failure on
    // unfixed code: flutter_test/binding.dart:1955 guards the invariant
    // checks on `_pendingExceptionDetails == null`, so a body that has
    // already failed skips them.
    await tester.pumpAndSettle();
    expect(
      controller.hasActiveAnimations,
      isFalse,
      reason: "the reversal must settle, leaving no live ticker at teardown",
    );
  });
}
