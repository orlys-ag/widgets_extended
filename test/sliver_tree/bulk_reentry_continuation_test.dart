/// Regression tests for audit item 1.6: a second `collapseAll` /
/// `expandAll` while a bulk animation is already running in the SAME
/// direction must continue the in-flight group instead of disposing it
/// and creating a fresh one (which snaps every member's extent).
///
/// Buggy behavior:
///   - `collapseAll(); ...; collapseAll();` — the second call's
///     bulk-members sweep re-adds the collapsing members to nodesToHide,
///     the reverse branch is skipped (pendingRemoval non-empty), and the
///     else branch creates a fresh group at value 1.0: rows painting at
///     `full * 0.5` jump back to `full * 1.0` in one frame.
///   - `expandAll(); ...; insert new nodes; expandAll();` — the second
///     call takes the fresh-group branch (active group has empty
///     pendingRemoval), disposing the in-flight group: half-expanded
///     members pop to full extent instantly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

const double kRowExtent = 100.0;

/// Off-cache harness for the L27 unmeasured-member legs: `g`-prefixed
/// rows are 100 px, everything else is exactly
/// [TreeController.defaultExtent] (48 px) so an unmeasured row's assumed
/// extent equals its real one and the scroll extent stays exact. 30 pad
/// roots push the `p -> c -> g1, g2` subtree past the viewport plus the
/// default cache extent, so nothing in it is ever laid out and
/// `getMeasuredExtent` stays null.
Widget _offCacheHarness(
  TreeController<String, String> controller,
  ScrollController scrollController,
) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverTree<String, String>(
            controller: controller,
            nodeBuilder: (context, key, depth) {
              return SizedBox(
                key: ValueKey(key),
                height: key.startsWith("g") ? 100.0 : 48.0,
                child: Text(key),
              );
            },
          ),
        ],
      ),
    ),
  );
}

Widget _harness(TreeController<String, String> controller) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverTree<String, String>(
            controller: controller,
            nodeBuilder: (context, key, depth) {
              return SizedBox(
                key: ValueKey(key),
                height: kRowExtent,
                child: Text(key),
              );
            },
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets("second collapseAll mid-flight continues the bulk collapse — no "
      "member's extent increases frame-over-frame", (tester) async {
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

    controller.setRoots([TreeNode(key: "r", data: "R")]);
    controller.setChildren("r", [
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
    ]);
    controller.expand(key: "r", animate: false);

    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    controller.collapseAll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final midExtent = controller.getAnimatedExtent("a", kRowExtent);
    expect(
      midExtent,
      lessThan(kRowExtent),
      reason: "setup: a must be mid-collapse (partial extent)",
    );
    expect(
      midExtent,
      greaterThan(0.0),
      reason: "setup: a must not have finished collapsing yet",
    );

    // Double-tap "collapse all": must continue, not restart.
    controller.collapseAll();

    double prev = controller.getAnimatedExtent("a", kRowExtent);
    expect(
      prev,
      lessThanOrEqualTo(midExtent + 0.001),
      reason:
          "the second collapseAll must not snap a's extent back up "
          "(fresh group at value 1.0 would repaint it at full extent)",
    );
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (!controller.visibleNodes.contains("a")) {
        // Collapse finished (on the ORIGINAL timeline — continuation
        // does not restart the clock); getAnimatedExtent now falls
        // back to the full extent of the hidden row.
        break;
      }
      final now = controller.getAnimatedExtent("a", kRowExtent);
      expect(
        now,
        lessThanOrEqualTo(prev + 0.001),
        reason:
            "collapse extent must be monotonically non-increasing "
            "frame-over-frame (frame $i: $prev -> $now)",
      );
      prev = now;
    }

    await tester.pumpAndSettle();
    expect(controller.visibleNodes, ["r"]);
  });

  testWidgets(
    "second expandAll mid-flight continues the bulk expand — existing "
    "members do not pop to full extent; new nodes still animate in",
    (tester) async {
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

      controller.setRoots([TreeNode(key: "r", data: "R")]);
      controller.setChildren("r", [
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);

      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      controller.expandAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final midExtent = controller.getAnimatedExtent("a", kRowExtent);
      expect(
        midExtent,
        greaterThan(0.0),
        reason: "setup: a must be mid-expand",
      );
      expect(
        midExtent,
        lessThan(kRowExtent),
        reason: "setup: a must not have finished expanding yet",
      );

      // A new collapsed parent appears mid-flight; the user hits
      // "expand all" again.
      controller.insertRoot(TreeNode(key: "n", data: "N"), animate: false);
      controller.setChildren("n", [TreeNode(key: "m", data: "M")]);
      controller.expandAll();

      final afterReentry = controller.getAnimatedExtent("a", kRowExtent);
      expect(
        afterReentry,
        lessThan(kRowExtent * 0.9),
        reason:
            "the second expandAll must not dispose the in-flight group "
            "(which would pop half-expanded a to full extent instantly)",
      );

      double prev = afterReentry;
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final now = controller.getAnimatedExtent("a", kRowExtent);
        expect(
          now,
          greaterThanOrEqualTo(prev - 0.001),
          reason:
              "expand extent must be monotonically non-decreasing "
              "frame-over-frame (frame $i: $prev -> $now)",
        );
        prev = now;
      }

      // The genuinely-new node m must still animate in (from zero), not
      // pop in at the mid-flight group value.
      expect(controller.hasActiveAnimations, isTrue);

      await tester.pumpAndSettle();
      expect(controller.visibleNodes, containsAll(["r", "a", "b", "n", "m"]));
      expect(controller.getAnimatedExtent("m", kRowExtent), kRowExtent);
    },
  );

  // L27: bulk reversals must run the Path-1 rebase.

  TreeController<String, String> makeController(WidgetTester tester) {
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
    return controller;
  }

  // Shared off-cache setup for legs (d), (e1), (e2), (f): 30 pad roots,
  // then p (expanded) -> c (collapsed) -> g1, g2.
  Future<(TreeController<String, String>, ScrollController)> pumpOffCacheTree(
    WidgetTester tester,
  ) async {
    final controller = makeController(tester);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    controller.setRoots([
      for (int i = 0; i < 30; i++) TreeNode(key: "pad$i", data: "P$i"),
      const TreeNode(key: "p", data: "P"),
    ]);
    controller.setChildren("p", [const TreeNode(key: "c", data: "C")]);
    controller.setChildren("c", [
      const TreeNode(key: "g1", data: "G1"),
      const TreeNode(key: "g2", data: "G2"),
    ]);
    controller.expand(key: "p", animate: false);
    await tester.pumpWidget(_offCacheHarness(controller, scrollController));
    await tester.pumpAndSettle();
    return (controller, scrollController);
  }

  testWidgets(
    "L27 (a): expandAll reversing a mid-collapse op group holds the "
    "painted extent across the reversal frame",
    (tester) async {
      final controller = makeController(tester);
      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "x", data: "X")]);
      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      controller.expand(key: "p");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      controller.collapse(key: "p");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final before = controller.getCurrentExtent("x");
      expect(
        before,
        greaterThan(0.0),
        reason: "setup sanity: x must be mid-collapse, not settled",
      );
      expect(
        before,
        lessThan(kRowExtent),
        reason: "setup sanity: x must be mid-collapse, not at full extent",
      );

      controller.expandAll();
      await tester.pump();
      expect(
        controller.getCurrentExtent("x"),
        closeTo(before, 1.0),
        reason:
            "the reversal must rebase startExtent and reset the "
            "controller; re-targeting alone pops the painted extent by "
            "(full - capturedTarget) * curvedValue in one frame",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "L27 (b): collapseAll reversing a mid-expand op group holds the "
    "painted extent across the reversal frame",
    (tester) async {
      final controller = makeController(tester);
      controller.setRoots([const TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [const TreeNode(key: "x", data: "X")]);
      controller.expand(key: "p", animate: false);
      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      controller.collapse(key: "p");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      controller.expand(key: "p");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // expand Path 1 rebased to startExtent = 50, target = 100, reset to
      // 0; at cv 0.5 the row paints lerp(50, 100, 0.5) = 75, a value
      // neither a missing rebase (50) nor a settled group (100) produces.
      final before = controller.getCurrentExtent("x");
      expect(
        before,
        closeTo(75.0, 0.5),
        reason: "setup sanity: x must paint the Path-1-rebased envelope",
      );

      controller.collapseAll();
      await tester.pump();
      expect(
        controller.getCurrentExtent("x"),
        closeTo(before, 1.0),
        reason:
            "the mirror must capture the painted extent BEFORE zeroing "
            "startExtent (compute first, then write) and reset the "
            "controller; zeroing alone pops by startExtent * (1 - cv)",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "L27 (c): expandAll's bulk-reverse branch routes genuinely new nodes "
    "to standalone enters",
    (tester) async {
      final controller = makeController(tester);
      controller.setRoots([
        const TreeNode(key: "A", data: "A"),
        const TreeNode(key: "B", data: "B"),
      ]);
      controller.setChildren("A", [
        const TreeNode(key: "a1", data: "A1"),
        const TreeNode(key: "a2", data: "A2"),
      ]);
      controller.setChildren("B", [
        const TreeNode(key: "b1", data: "B1"),
        const TreeNode(key: "b2", data: "B2"),
      ]);
      controller.expand(key: "A", animate: false);
      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      controller.collapseAll();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        controller.visibleNodes,
        isNot(contains("b1")),
        reason: "setup sanity: b1 was never visible (B stayed collapsed)",
      );
      final a1Mid = controller.getAnimatedExtent("a1", kRowExtent);
      expect(
        a1Mid,
        greaterThan(0.0),
        reason: "setup sanity: the bulk collapse must be mid-flight",
      );
      expect(
        a1Mid,
        lessThan(kRowExtent),
        reason: "setup sanity: the bulk collapse must not have settled",
      );

      controller.expandAll();
      await tester.pump();
      expect(
        controller.getAnimatedExtent("b1", kRowExtent),
        closeTo(0.0, 1.0),
        reason:
            "a genuinely new joiner must enter from zero on its own "
            "timeline, not join the mid-flight bulk group and pop to "
            "full * currentValue",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "L27 (d): expandAll rebases an unmeasured member instead of writing "
    "the sentinel back over its capture",
    (tester) async {
      final (controller, _) = await pumpOffCacheTree(tester);

      controller.expand(key: "c");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        controller.getCurrentExtent("g1"),
        closeTo(24.0, 0.01),
        reason:
            "setup sanity: an unmeasured member reads defaultExtent * cv "
            "= 48 * 0.5; a measured 100 px row would read 50 here",
      );

      controller.collapse(key: "c");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final before = controller.getCurrentExtent("g1");
      expect(
        before,
        closeTo(12.0, 0.01),
        reason:
            "setup sanity: collapse Path 1 captured 24 into targetExtent, "
            "so at cv 0.5 the row paints lerp(0, 24, 0.5) = 12",
      );

      controller.expandAll();
      await tester.pump();
      expect(
        controller.getCurrentExtent("g1"),
        closeTo(before, 1.0),
        reason:
            "the reversal must rebase the unmeasured member onto its "
            "captured extent; writing the sentinel back reads "
            "defaultExtent * cv = 24 again, a 12 -> 24 pop, and leaving "
            "the sentinel in a reset controller would read 0",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "L27 (e1): a rebased unmeasured member's terminus repairs on first "
    "measurement (expandAll site)",
    (tester) async {
      final (controller, scrollController) = await pumpOffCacheTree(tester);

      controller.expand(key: "c");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        controller.getMeasuredExtent("g1"),
        isNull,
        reason: "setup sanity: g1 must be off cache and never laid out",
      );
      expect(
        controller.getCurrentExtent("g1"),
        closeTo(24.0, 0.01),
        reason: "setup sanity: unmeasured member at cv 0.5",
      );

      controller.collapse(key: "p");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        controller.getCurrentExtent("g1"),
        closeTo(12.0, 0.01),
        reason:
            "setup sanity: collapse Path 2 captured g1 at 24 (setting "
            "targetIsCaptured), so at cv 0.5 the row paints 12",
      );

      controller.expandAll();
      await tester.pump();
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        controller.getMeasuredExtent("g1"),
        100.0,
        reason: "setup sanity: the jump must have laid g1 out",
      );
      expect(
        controller.getCurrentExtent("g1"),
        closeTo(29.6, 0.1),
        reason:
            "the rebase must clear targetIsCaptured for an unmeasured "
            "member so the first measurement re-targets the envelope to "
            "the real 100: lerp(12, 100, 0.2) = 29.6; a guessed 48 held "
            "captive reads lerp(12, 48, 0.2) = 19.2",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "L27 (e2): a rebased unmeasured member's terminus repairs on first "
    "measurement (expand Path 1 site)",
    (tester) async {
      final (controller, scrollController) = await pumpOffCacheTree(tester);

      controller.expand(key: "c");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      controller.collapse(key: "p");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        controller.getMeasuredExtent("g1"),
        isNull,
        reason: "setup sanity: g1 must be off cache and never laid out",
      );
      expect(
        controller.getCurrentExtent("g1"),
        closeTo(12.0, 0.01),
        reason: "setup sanity: captured envelope at cv 0.5",
      );

      controller.expand(key: "p");
      await tester.pump();
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        controller.getMeasuredExtent("g1"),
        100.0,
        reason: "setup sanity: the jump must have laid g1 out",
      );
      expect(
        controller.getCurrentExtent("g1"),
        closeTo(29.6, 0.1),
        reason:
            "expand Path 1's rebase must clear targetIsCaptured for an "
            "unmeasured member so the first measurement re-targets to the "
            "real 100: lerp(12, 100, 0.2) = 29.6, not lerp(12, 48, 0.2)",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "L27 (f): a sentinel member survives collapseAll and expandAll "
    "reversals without popping (route C guard)",
    (tester) async {
      final (controller, _) = await pumpOffCacheTree(tester);

      controller.expand(key: "c");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        controller.getMeasuredExtent("g1"),
        isNull,
        reason: "setup sanity: g1 must be off cache and never laid out",
      );
      expect(
        controller.getCurrentExtent("g1"),
        closeTo(24.0, 0.01),
        reason:
            "setup sanity: a fresh expand group's unmeasured member "
            "carries the sentinel and reads defaultExtent * cv",
      );

      controller.collapseAll();
      await tester.pump();
      expect(
        controller.getCurrentExtent("g1"),
        closeTo(24.0, 0.01),
        reason:
            "the collapseAll reversal must not move a sentinel member's "
            "painted extent; a sentinel surviving into a controller reset "
            "to 1.0 would paint the whole default row (48)",
      );

      controller.expandAll();
      await tester.pump();
      expect(
        controller.getCurrentExtent("g1"),
        closeTo(24.0, 0.01),
        reason:
            "the expandAll reversal must hold the same painted extent; "
            "the first reversal's capture took the sentinel out of the "
            "record, so this frame reads the rebased envelope",
      );
      await tester.pumpAndSettle();
    },
  );
}
