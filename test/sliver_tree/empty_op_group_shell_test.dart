/// Regression tests for M23: an operation group that took no members
/// held `hasActiveAnimations` true for its full duration.
///
/// `hasActiveAnimations` is `standalone.hasAny || opGroups.isNotEmpty ||
/// !bulk.isEmpty` (`_animation_coordinator.dart:929-930`), so group
/// LIFETIME decides it, not group CONTENT. Two producers could leave a
/// group with zero members and zero pendingRemoval:
///
///   - the Path-2 install sites, which install unconditionally
///     (`tree_controller.dart:3854-3857` / `:4065-4069`) and only then
///     filter `_isPendingDeletion` out of the member loops (`:3881`,
///     `:3894`, `:3913` / `:4073`);
///   - `_purgeNodeData`, which removed the last member of a live group
///     (`_tree_controller_helpers.dart:325-329`) without asking
///     `disposeIfEmpty`.
///
/// While such a shell was up, `SliverTreeElement._onAnimationTick` reads
/// `hasActiveAnimations` (`sliver_tree_element.dart:333`) and calls
/// `renderObject.markNeedsLayout()` (`:340`) on every tick, so an
/// animation containing nothing cost one whole-sliver layout per frame:
/// measured at six layouts across six frames by the third assertion in
/// the first test below.
///
/// The fix asks whether the group took anything before starting it
/// (`_abandonEmptyOperationGroup`) and disposes an emptied group on the
/// purge path, so the two producers no longer outlive their content.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

Future<void> _pumpTree(
  WidgetTester tester,
  TreeController<String, String> controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: CustomScrollView(
            slivers: [
              SliverTree<String, String>(
                controller: controller,
                nodeBuilder: (context, key, depth) {
                  return SizedBox(height: 48, child: Text(key));
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets("M23 install path: collapsing a parent whose only descendant "
      "is pending-deletion installs a group that takes no members", (
    tester,
  ) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      // The two families must differ: the exit is what makes C
      // pending-deletion, and it has to be OVER before the assertions
      // run, or `standalone.hasAny` would hold `hasActiveAnimations`
      // true for an honest reason and the discriminating assertion
      // below would not be about the shell at all.
      animationStyle: const TreeAnimationStyle(
        expandCollapse: TreeAnimationSpec(
          duration: Duration(milliseconds: 1000),
          curve: Curves.linear,
        ),
        enterExit: TreeAnimationSpec(
          duration: Duration(milliseconds: 100),
          curve: Curves.linear,
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.setRoots([TreeNode(key: "P", data: "P")]);
    controller.setChildren("P", [TreeNode(key: "C", data: "C")]);
    controller.expand(key: "P", animate: false);

    await _pumpTree(tester, controller);
    final render = tester.renderObject<RenderSliverTree<String, String>>(
      find.byType(SliverTree<String, String>),
    );

    expect(
      controller.hasActiveAnimations,
      isFalse,
      reason: "setup: the tree must be idle before the exit starts",
    );

    controller.remove(key: "C", animate: true);
    // Bare pump first: a ticker started outside a frame leaves
    // `_startTime` null (scheduler/ticker.dart:202-204) and the first
    // tick sets `_startTime ??= timeStamp` (:276), so without this the
    // timed pump advances the exit by nothing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(
      controller.isPendingDeletion("C"),
      isTrue,
      reason:
          "setup: C must be mid-exit, so the collapse below filters it "
          "out of the member loop and the group takes nothing",
    );

    // Path 2. The entry guard only rejects `descendants.isEmpty`
    // (tree_controller.dart:3992-3995); C is still in visible order, so
    // `descendants` is [C] and the guard passes.
    controller.collapse(key: "P");
    await tester.pump();
    // Past the 100ms exit, so the standalone source is empty and the
    // only thing that can hold `hasActiveAnimations` true is the shell.
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      controller.currentlyAnimatingKeys,
      isEmpty,
      reason:
          "control: nothing is genuinely animating, so a true "
          "`hasActiveAnimations` below is a shell and not a live member",
    );

    expect(
      controller.hasActiveAnimations,
      isFalse,
      reason:
          "the group took no members, so it must never have been started; "
          "before the fix it reversed for its full 1000ms with nothing "
          "in it",
    );

    // The cost the shell imposes, pinned directly rather than inferred:
    // `_onAnimationTick` reads `hasActiveAnimations`
    // (sliver_tree_element.dart:333) and marks layout (:340) on every
    // tick, so an idle tree must perform ZERO layouts here.
    //
    // The bare pump absorbs the exit's settle, which is ONE frame late
    // by two independent mechanisms and is not what this pin is about.
    // A ticker schedules its tick as a frame callback (scheduler/
    // ticker.dart:298) and `handleBeginFrame` invokes those with
    // `_schedulerPhase = SchedulerPhase.transientCallbacks`
    // (scheduler/binding.dart:1258, invoked at :1261-1264), which is the
    // phase the coordinator defers its dispatch to a microtask in
    // (`_animation_coordinator.dart:306-317`), so the tick's
    // `markNeedsLayout` lands after this frame's layout. And the settle
    // tick marks layout at all via `_priorTickHadAnimations`
    // (`sliver_tree_element.dart:336`, assigned at `:378`) even once
    // `active` is false. Measured: 1 layout on that frame, then 0.
    await tester.pump();

    // The loop is what makes this a PER-FRAME claim. `tester.pump(d)`
    // produces ONE frame however large `d` is, so a single pump of 300ms
    // could not tell a one-off from a per-frame cost. Six frames inside
    // the shell's 1000ms window cost six layouts on unfixed code.
    final layoutsBefore = render.debugPerformLayoutCount;
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      render.debugPerformLayoutCount - layoutsBefore,
      0,
      reason:
          "an empty shell must not force a whole-sliver layout per frame",
    );

    // Abandoning the group must not cost the collapse its effect.
    //
    // Only the expansion flag is asserted here. Companion checks on
    // `getNodeData("C")` and `visibleNodeCount` were tried and DROPPED:
    // measured with the collapse commented out, both still passed,
    // because C's own standalone exit purges it whether or not the
    // collapse ran, and P alone is then the entire tree. The stranding
    // question they were meant to answer needs a group with real
    // members, which is the third test below.
    await tester.pumpAndSettle();
    expect(
      controller.isExpanded("P"),
      isFalse,
      reason: "the collapse must still have taken effect",
    );
  });

  testWidgets("M23 guard: a collapse whose descendant is NOT pending-deletion "
      "still installs and runs its group", (tester) async {
    // The emptiness condition in `_abandonEmptyOperationGroup` is
    // load-bearing, not decorative: abandoning unconditionally would
    // skip `reverse()` on a group holding real members, so their
    // `pendingRemoval` entries are never consumed. Measured with the
    // condition removed: C is still visible after `pumpAndSettle` and
    // `visibleNodeCount` reads 2 instead of 1.
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
    controller.setRoots([TreeNode(key: "P", data: "P")]);
    controller.setChildren("P", [TreeNode(key: "C", data: "C")]);
    controller.expand(key: "P", animate: false);

    await _pumpTree(tester, controller);

    expect(
      controller.isPendingDeletion("C"),
      isFalse,
      reason: "setup: C must be a live member, so the group takes it",
    );

    controller.collapse(key: "P");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      controller.hasActiveAnimations,
      isTrue,
      reason:
          "a group that took a member must actually be started; an "
          "unconditional abandon would skip `reverse()` here",
    );
    expect(
      controller.isVisible("C"),
      isTrue,
      reason: "C is mid-collapse, so it is still in visible order",
    );

    await tester.pumpAndSettle();
    expect(
      controller.isVisible("C"),
      isFalse,
      reason:
          "the group's `reverse()` must reach dismissed and consume its "
          "`pendingRemoval` entry; without it C never leaves visible order",
    );
    expect(
      controller.visibleNodeCount,
      1,
      reason: "only P may remain visible once the collapse completes",
    );
  });

  testWidgets("M23 purge path: removing a live group's last members leaves "
      "the group behind", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: const TreeAnimationStyle(
        expandCollapse: TreeAnimationSpec(
          duration: Duration(milliseconds: 1000),
          curve: Curves.linear,
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.setRoots([TreeNode(key: "P", data: "P")]);
    controller.setChildren("P", [
      TreeNode(key: "c1", data: "C1"),
      TreeNode(key: "c2", data: "C2"),
    ]);

    await _pumpTree(tester, controller);

    controller.expand(key: "P");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      controller.currentlyAnimatingKeys,
      containsAll(<String>["c1", "c2"]),
      reason:
          "setup: both children must have joined the group, so the "
          "removals below take it from two members to zero",
    );
    expect(
      controller.hasActiveAnimations,
      isTrue,
      reason: "setup: the group must be live before its members are purged",
    );

    // `animate: false`, so neither removal creates a standalone exit:
    // after the second one the group holds no members and no
    // pendingRemoval, and nothing else is animating.
    controller.remove(key: "c1", animate: false);
    controller.remove(key: "c2", animate: false);

    expect(
      controller.currentlyAnimatingKeys,
      isEmpty,
      reason:
          "control: both members are gone, so a true `hasActiveAnimations` "
          "below is the emptied group and not a survivor",
    );

    expect(
      controller.hasActiveAnimations,
      isFalse,
      reason:
          "purging the last member must dispose the group, the way "
          "`removeFromAllSources` already does "
          "(_animation_coordinator.dart:620, its `disposeIfEmpty` at :634)",
    );
  });
}
