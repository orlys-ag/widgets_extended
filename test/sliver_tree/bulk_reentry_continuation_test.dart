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

import 'package:flutter/animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

const double kRowExtent = 100.0;

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
  testWidgets(
    "second collapseAll mid-flight continues the bulk collapse — no "
    "member's extent increases frame-over-frame",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.linear,
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
      expect(midExtent, lessThan(kRowExtent),
          reason: "setup: a must be mid-collapse (partial extent)");
      expect(midExtent, greaterThan(0.0),
          reason: "setup: a must not have finished collapsing yet");

      // Double-tap "collapse all": must continue, not restart.
      controller.collapseAll();

      double prev = controller.getAnimatedExtent("a", kRowExtent);
      expect(
        prev,
        lessThanOrEqualTo(midExtent + 0.001),
        reason: "the second collapseAll must not snap a's extent back up "
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
          reason: "collapse extent must be monotonically non-increasing "
              "frame-over-frame (frame $i: $prev -> $now)",
        );
        prev = now;
      }

      await tester.pumpAndSettle();
      expect(controller.visibleNodes, ["r"]);
    },
  );

  testWidgets(
    "second expandAll mid-flight continues the bulk expand — existing "
    "members do not pop to full extent; new nodes still animate in",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
        animationCurve: Curves.linear,
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
      expect(midExtent, greaterThan(0.0),
          reason: "setup: a must be mid-expand");
      expect(midExtent, lessThan(kRowExtent),
          reason: "setup: a must not have finished expanding yet");

      // A new collapsed parent appears mid-flight; the user hits
      // "expand all" again.
      controller.insertRoot(TreeNode(key: "n", data: "N"), animate: false);
      controller.setChildren("n", [TreeNode(key: "m", data: "M")]);
      controller.expandAll();

      final afterReentry = controller.getAnimatedExtent("a", kRowExtent);
      expect(
        afterReentry,
        lessThan(kRowExtent * 0.9),
        reason: "the second expandAll must not dispose the in-flight group "
            "(which would pop half-expanded a to full extent instantly)",
      );

      double prev = afterReentry;
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final now = controller.getAnimatedExtent("a", kRowExtent);
        expect(
          now,
          greaterThanOrEqualTo(prev - 0.001),
          reason: "expand extent must be monotonically non-decreasing "
              "frame-over-frame (frame $i: $prev -> $now)",
        );
        prev = now;
      }

      // The genuinely-new node m must still animate in (from zero), not
      // pop in at the mid-flight group value.
      expect(controller.hasActiveAnimations, isTrue);

      await tester.pumpAndSettle();
      expect(
        controller.visibleNodes,
        containsAll(["r", "a", "b", "n", "m"]),
      );
      expect(controller.getAnimatedExtent("m", kRowExtent), kRowExtent);
    },
  );
}
