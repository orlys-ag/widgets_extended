import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Repro tests for M5: a standalone animation spawned by an
/// expand/collapse mutator must run on the `expandCollapse` family the
/// mutator's own kill-switch gate reads, not on `enterExit`. Pre-fix the
/// install sites never declared a family and the standalone ticker
/// hard-coded `effectiveEnterExit` for every active state.
///
/// Family-flow style (house convention): each test sets the two families
/// to DISTINCTIVE specs and asserts which one governs, never a literal
/// default.
void main() {
  // Builds P > [C1 > G1, C2], everything collapsed, and drives it to the
  // point where collapsing P spawns a standalone exit for G1 (Path 1:
  // G1's op-group timeline belongs to C1's expand, not to P's collapse).
  Future<TreeController<String, String>> driveToStandaloneExit(
    WidgetTester tester,
    TreeAnimationStyle style,
  ) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: style,
    );
    addTearDown(controller.dispose);
    controller.setRoots([const TreeNode(key: "P", data: "P")]);
    controller.setChildren("P", [
      const TreeNode(key: "C1", data: "C1"),
      const TreeNode(key: "C2", data: "C2"),
    ]);
    controller.setChildren("C1", [const TreeNode(key: "G1", data: "G1")]);

    controller.expand(key: "P");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    controller.expand(key: "C1");
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      controller.getAnimationState("G1"),
      isNotNull,
      reason: "setup sanity: G1 must be on a standalone/op timeline",
    );

    controller.collapse(key: "P");
    expect(
      controller.getAnimationState("G1")?.type,
      AnimationType.exiting,
      reason: "setup sanity: the collapse must spawn a standalone exit "
          "for G1",
    );
    return controller;
  }

  testWidgets(
    "a collapse-spawned standalone exit runs on the expandCollapse family",
    (tester) async {
      final controller = await driveToStandaloneExit(
        tester,
        const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
          // Deliberately distinctive: if the exit ran on enterExit it
          // would still be mid-flight long after the collapse settled.
          enterExit: TreeAnimationSpec(
            duration: Duration(seconds: 10),
            curve: Curves.linear,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 310));
      expect(
        controller.visibleNodes,
        ["P"],
        reason:
            "the exit was spawned by a collapse whose kill switch reads "
            "expandCollapse (300 ms), so 310 ms later nothing of the "
            "collapsed subtree may linger; on enterExit's 10 s clock G1 "
            "would still be visible",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "a zero enterExit must not snap a collapse-spawned exit",
    (tester) async {
      final controller = await driveToStandaloneExit(
        tester,
        const TreeAnimationStyle(
          expandCollapse: TreeAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
          enterExit: TreeAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
        ),
      );

      // First tick after the collapse: dt is zero, so a correctly-routed
      // 300 ms exit has made no progress; the pre-fix ticker's
      // zero-duration branch snapped EVERY standalone state instantly.
      await tester.pump();
      expect(
        controller.visibleNodes,
        contains("G1"),
        reason:
            "G1's exit belongs to the expandCollapse family (300 ms); a "
            "zero enterExit must not vanish it in a single frame",
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "control: an insertRoot enter still runs on the enterExit family",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          // Deliberately distinctive: if the enter ran on expandCollapse
          // it would still be mid-flight at +310 ms.
          expandCollapse: TreeAnimationSpec(
            duration: Duration(seconds: 10),
            curve: Curves.linear,
          ),
          enterExit: TreeAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.setRoots([const TreeNode(key: "a", data: "A")]);

      controller.insertRoot(const TreeNode(key: "b", data: "B"));
      expect(
        controller.getAnimationState("b")?.type,
        AnimationType.entering,
        reason: "setup sanity: the insert must install a standalone enter",
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 310));
      expect(
        controller.getAnimationState("b"),
        isNull,
        reason:
            "the enter belongs to the enterExit family (300 ms), so it "
            "must have completed at +310 ms; the fix must not route "
            "everything onto expandCollapse (10 s)",
      );
      await tester.pumpAndSettle();
    },
  );
}
