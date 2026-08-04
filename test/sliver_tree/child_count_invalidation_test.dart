import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Child-count invalidation regression tests
/// (plans/2026-08-04-child-count-invalidation-plan.md).
///
/// A parent row that renders its own child count must refresh whenever the
/// count it renders changes: raw counts change when the child list mutates
/// (insert / immediate remove / moveNode / animated-exit purge), live
/// counts change when children are marked pending-deletion at animated-
/// removal START. The old rule only refreshed the parent on hasChildren
/// FLIPS (empty vs non-empty), so both counts went stale on every
/// non-boundary change.
///
/// These tests run with animations ENABLED where the subject is the
/// animated path: `TreeAnimationStyle.disabled` would route `remove`
/// down the immediate path and hide the defect. Removals are driven
/// imperatively: a declarative re-sync rebuilds the tree widget, which
/// dirties every mounted row and masks exactly what is under test.

Widget _harness({
  required TreeController<String, String> controller,
  required Widget Function(BuildContext, String, int) nodeBuilder,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverTree<String, String>(
            controller: controller,
            nodeBuilder: nodeBuilder,
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets(
    "animated removal: parent's rendered childCount refreshes after purge",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          enterExit: TreeAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.setRoots([TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [
        for (int i = 0; i < 12; i++) TreeNode(key: "c$i", data: "C$i"),
      ]);
      controller.expand(key: "p", animate: false);

      await tester.pumpWidget(
        _harness(
          controller: controller,
          nodeBuilder: (context, key, depth) {
            if (key == "p") {
              return SizedBox(
                height: 48,
                child: Text("count:${controller.getChildCount(key)}"),
              );
            }
            return SizedBox(height: 48, child: Text(key));
          },
        ),
      );
      expect(find.text("count:12"), findsOneWidget);

      for (int i = 3; i < 12; i++) {
        controller.remove(key: "c$i", animate: true);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Setup sanity: the animated path is genuinely exercised (an
      // exiting row is still painted) and raw semantics hold
      // mid-animation (the departing rows are still counted).
      expect(
        find.text("c5"),
        findsOneWidget,
        reason: "setup sanity: removed row must still be painted "
            "mid-exit-animation, proving the animated path is exercised",
      );
      expect(
        find.text("count:12"),
        findsOneWidget,
        reason: "raw childCount includes rows animating out; the header "
            "must match the rows still on screen",
      );

      await tester.pumpAndSettle();

      expect(
        find.text("count:3"),
        findsOneWidget,
        reason: "after the exit animation purges the child list, the "
            "parent row must refresh to the new count, not keep the "
            "pre-removal number forever",
      );
    },
  );

  testWidgets(
    "animated removal: parent's rendered liveChildCount refreshes at "
    "animation start",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: const TreeAnimationStyle(
          enterExit: TreeAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
        ),
      );
      addTearDown(controller.dispose);
      controller.setRoots([TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [
        for (int i = 0; i < 12; i++) TreeNode(key: "c$i", data: "C$i"),
      ]);
      controller.expand(key: "p", animate: false);

      await tester.pumpWidget(
        _harness(
          controller: controller,
          nodeBuilder: (context, key, depth) {
            if (key == "p") {
              return SizedBox(
                height: 48,
                child: Text("live:${controller.liveChildCount(key)}"),
              );
            }
            return SizedBox(height: 48, child: Text(key));
          },
        ),
      );
      expect(find.text("live:12"), findsOneWidget);

      for (int i = 3; i < 12; i++) {
        controller.remove(key: "c$i", animate: true);
      }
      await tester.pump();

      // Setup sanity: the exit animation is genuinely in flight; the raw
      // count still includes the departing rows and one is still painted.
      expect(
        controller.getChildCount("p"),
        12,
        reason: "setup sanity: raw count is untouched at animation start "
            "(the child list is not mutated until purge)",
      );
      expect(
        find.text("c5"),
        findsOneWidget,
        reason: "setup sanity: removed row must still be painted mid-exit",
      );

      expect(
        find.text("live:3"),
        findsOneWidget,
        reason: "the live count changed at pending-deletion marking time; "
            "a row rendering it must refresh at animation START, not only "
            "after the purge",
      );

      await tester.pumpAndSettle();
      expect(find.text("live:3"), findsOneWidget);
    },
  );

  testWidgets(
    "immediate removal: parent's rendered childCount refreshes",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([TreeNode(key: "p", data: "P")]);
      controller.setChildren("p", [
        TreeNode(key: "c0", data: "C0"),
        TreeNode(key: "c1", data: "C1"),
        TreeNode(key: "c2", data: "C2"),
      ]);
      controller.expand(key: "p", animate: false);

      await tester.pumpWidget(
        _harness(
          controller: controller,
          nodeBuilder: (context, key, depth) {
            if (key == "p") {
              return SizedBox(
                height: 48,
                child: Text("count:${controller.getChildCount(key)}"),
              );
            }
            return SizedBox(height: 48, child: Text(key));
          },
        ),
      );
      expect(find.text("count:3"), findsOneWidget);

      controller.remove(key: "c2", animate: false);
      await tester.pump();

      expect(
        find.text("count:2"),
        findsOneWidget,
        reason: "the parent's child list shrank 3 to 2; its rendered count "
            "must refresh even though hasChildren did not flip",
      );
    },
  );

  testWidgets("insert: parent's rendered childCount refreshes", (
    tester,
  ) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.setRoots([TreeNode(key: "p", data: "P")]);
    controller.setChildren("p", [TreeNode(key: "c0", data: "C0")]);
    controller.expand(key: "p", animate: false);

    await tester.pumpWidget(
      _harness(
        controller: controller,
        nodeBuilder: (context, key, depth) {
          if (key == "p") {
            return SizedBox(
              height: 48,
              child: Text("count:${controller.getChildCount(key)}"),
            );
          }
          return SizedBox(height: 48, child: Text(key));
        },
      ),
    );
    expect(find.text("count:1"), findsOneWidget);

    controller.insert(
      parentKey: "p",
      node: TreeNode(key: "c1", data: "C1"),
      animate: false,
    );
    await tester.pump();

    expect(
      find.text("count:2"),
      findsOneWidget,
      reason: "the parent's child list grew 1 to 2; its rendered count "
          "must refresh even though hasChildren did not flip",
    );
  });

  testWidgets(
    "moveNode: both parents' rendered childCounts refresh",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "p1", data: "P1"),
        TreeNode(key: "p2", data: "P2"),
      ]);
      controller.setChildren("p1", [
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("p2", [TreeNode(key: "c", data: "C")]);
      controller.expand(key: "p1", animate: false);
      controller.expand(key: "p2", animate: false);

      await tester.pumpWidget(
        _harness(
          controller: controller,
          nodeBuilder: (context, key, depth) {
            if (key == "p1" || key == "p2") {
              return SizedBox(
                height: 48,
                child: Text("$key:${controller.getChildCount(key)}"),
              );
            }
            return SizedBox(height: 48, child: Text(key));
          },
        ),
      );
      expect(find.text("p1:2"), findsOneWidget);
      expect(find.text("p2:1"), findsOneWidget);

      controller.moveNode("a", "p2");
      await tester.pump();

      // Setup sanity: the move is an equal-depth reparent, so the widened
      // notification (not the depth-change refresh) is what must carry
      // both parents.
      expect(controller.getParent("a"), "p2");
      expect(controller.getDepth("a"), 1);

      expect(
        find.text("p1:1"),
        findsOneWidget,
        reason: "old parent lost a child (2 to 1, no flip); its rendered "
            "count must refresh",
      );
      expect(
        find.text("p2:2"),
        findsOneWidget,
        reason: "new parent gained a child (1 to 2, no flip); its rendered "
            "count must refresh",
      );
    },
  );

  testWidgets(
    "bulk collapseAll completion still notifies with an empty set",
    (tester) async {
      // Guards against over-widening: the bulk path only removes entries
      // from the visible order; it never touches child lists, so its
      // completion notification must stay empty (no mounted row's builder
      // output changed).
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
      controller.setRoots([
        TreeNode(key: "r0", data: "R0"),
        TreeNode(key: "r1", data: "R1"),
      ]);
      controller.setChildren("r0", [TreeNode(key: "r0c", data: "R0C")]);
      controller.setChildren("r1", [TreeNode(key: "r1c", data: "R1C")]);
      controller.expand(key: "r0", animate: false);
      controller.expand(key: "r1", animate: false);

      await tester.pumpWidget(
        _harness(
          controller: controller,
          nodeBuilder: (context, key, depth) {
            return SizedBox(height: 48, child: Text(key));
          },
        ),
      );

      final captured = <Set<String>?>[];
      controller.addStructuralListener(captured.add);

      controller.collapseAll();
      await tester.pumpAndSettle();

      expect(
        captured,
        isNotEmpty,
        reason: "setup sanity: collapseAll must fire structural "
            "notifications",
      );
      expect(
        captured.last,
        isNotNull,
        reason: "bulk completion must notify with a targeted (non-null) "
            "set, not a full refresh",
      );
      expect(
        captured.last,
        isEmpty,
        reason: "bulk completion only removes rows from visible order; no "
            "mounted row's builder output changed, so the set must stay "
            "empty",
      );
    },
  );
}
