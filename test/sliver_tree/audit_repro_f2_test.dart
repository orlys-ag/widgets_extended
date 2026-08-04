/// Audit repro for finding f2 (plans/sliver_tree_review_2026_07_plan.md):
///
/// "Setting animationDuration to Duration.zero mid-flight permanently
/// freezes standalone animations and pending deletions."
///
/// The `animationDuration` setter (tree_controller.dart:89-98) documents
/// that in-flight animations "adjust on the next frame", but it only
/// propagates the new duration to bulk/op-group AnimationControllers. The
/// standalone ticker's zero-duration branch (_standalone_animator.dart:
/// 219-223) stops the ticker WITHOUT completing or finalizing active
/// states, so a node mid-exit (pending deletion) is stranded forever:
/// it stays in visibleNodes at partial extent, isPendingDeletion stays
/// true, and hasActiveAnimations stays true permanently.
///
/// These tests assert the EXPECTED (correct) behavior: after the duration
/// is set to zero, the in-flight standalone exit must complete promptly
/// (within a bounded number of frames far exceeding the original
/// duration), purging the removed node and returning the controller to
/// an idle animation state. They FAIL on current code if the bug is real.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

Widget _harness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                return SizedBox(
                  key: ValueKey("row-$key"),
                  height: 48,
                  child: Padding(
                    padding: EdgeInsets.only(left: depth * 20.0),
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
}

/// Sets up a two-root tree, starts an animated remove of "a", advances to
/// mid-exit, and verifies (as setup sanity checks) that the exit is
/// genuinely in flight before the duration change.
Future<TreeController<String, String>> _startMidFlightExit(
  WidgetTester tester,
) async {
  final controller = TreeController<String, String>(
    vsync: tester,
    animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 300), curve: Curves.linear)),
  );
  addTearDown(controller.dispose);

  controller.setRoots([
    const TreeNode(key: "a", data: "a"),
    const TreeNode(key: "b", data: "b"),
  ]);

  await tester.pumpWidget(_harness(controller));
  await tester.pumpAndSettle();

  // Start the animated (standalone) exit of "a".
  controller.remove(key: "a", animate: true);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  // Sanity: the exit is genuinely in flight (mid-exit) — these are setup
  // preconditions, not the bug assertions.
  expect(controller.isPendingDeletion("a"), isTrue,
      reason: "setup: 'a' must be mid-exit (pending deletion)");
  expect(controller.isVisible("a"), isTrue,
      reason: "setup: 'a' must still be in the visible order mid-exit");
  expect(controller.hasActiveAnimations, isTrue,
      reason: "setup: the standalone exit must be active");

  // Trigger the claimed bug: honor a reduce-motion-style setting
  // mid-flight.
  controller.animationStyle = TreeAnimationStyle.disabled;

  // Bounded pumps only (the buggy state never settles, so no
  // pumpAndSettle). Total simulated time here (~1.16s) far exceeds the
  // original 300ms duration, so even an animation that merely kept
  // playing at the old rate would have completed by now. Only a
  // genuinely stranded animation can keep the assertions failing.
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(seconds: 1));

  return controller;
}

void main() {
  testWidgets(
    "setting animationDuration to zero mid-exit finalizes the pending "
    "deletion instead of freezing it",
    (tester) async {
      final controller = await _startMidFlightExit(tester);

      // EXPECTED (doc contract at tree_controller.dart:82-88): in-flight
      // animations adjust on the next frame — with a zero duration that
      // means immediate completion, so "a" must be finalized and purged.
      expect(controller.isPendingDeletion("a"), isFalse,
          reason: "after duration is set to zero, the in-flight exit of "
              "'a' must complete and be finalized, not freeze forever");
      expect(controller.visibleNodes, isNot(contains("a")),
          reason: "the removed node must leave visibleNodes once its exit "
              "completes under zero duration");
      expect(find.byKey(const ValueKey("row-a")), findsNothing,
          reason: "the removed row must visibly disappear; a frozen "
              "partial-extent row means the exit was stranded");
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    "setting animationDuration to zero mid-exit returns the controller to "
    "an idle animation state (hasActiveAnimations false)",
    (tester) async {
      final controller = await _startMidFlightExit(tester);

      // EXPECTED: once the exit is snapped to completion there is nothing
      // left to animate. A permanently-true hasActiveAnimations makes the
      // render layer defer stale-child eviction and sticky precomputation
      // indefinitely.
      expect(controller.hasActiveAnimations, isFalse,
          reason: "no animation can still be active after the duration "
              "was set to zero and >1s of frames were pumped; a "
              "permanently-true value means the standalone state was "
              "stranded instead of completed");
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
