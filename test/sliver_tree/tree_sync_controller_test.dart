import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  late TreeController<String, String> controller;
  late TreeSyncController<String, String> sync;

  group('snapshotCurrentChildren', () {
    testWidgets('returns a deep-copied snapshot', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      sync.syncRoots(
        [TreeNode(key: 'root', data: 'Root')],
        childrenOf: (key) =>
            key == 'root' ? [TreeNode(key: 'child', data: 'Child')] : [],
        animate: false,
      );

      final snapshot = sync.snapshotCurrentChildren();
      snapshot['root']!.add('mutated');

      expect(snapshot['root'], ['child', 'mutated']);
      expect(sync.snapshotCurrentChildren()['root'], ['child']);
    });
  });

  group('syncRoots — reorder retained keys', () {
    testWidgets('reorders roots when only order changes', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      sync.syncRoots([
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
        TreeNode(key: 'c', data: 'C'),
      ], animate: false);
      expect(controller.visibleNodes, ['a', 'b', 'c']);

      // Reorder only — same keys, different order.
      sync.syncRoots([
        TreeNode(key: 'c', data: 'C'),
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
      ], animate: false);
      expect(controller.visibleNodes, ['c', 'a', 'b']);
    });

    testWidgets('updates data for retained roots', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      sync.syncRoots([TreeNode(key: 'a', data: 'old-A')], animate: false);
      expect(controller.getNodeData('a')!.data, 'old-A');

      sync.syncRoots([TreeNode(key: 'a', data: 'new-A')], animate: false);
      expect(controller.getNodeData('a')!.data, 'new-A');
    });
  });

  group('syncChildren — reorder retained keys', () {
    testWidgets('reorders children when only order changes', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      sync.syncRoots([TreeNode(key: 'root', data: 'Root')], animate: false);
      sync.syncChildren('root', [
        TreeNode(key: 'c1', data: 'C1'),
        TreeNode(key: 'c2', data: 'C2'),
        TreeNode(key: 'c3', data: 'C3'),
      ], animate: false);
      controller.expand(key: 'root');
      expect(controller.visibleNodes, ['root', 'c1', 'c2', 'c3']);

      sync.syncChildren('root', [
        TreeNode(key: 'c3', data: 'C3'),
        TreeNode(key: 'c1', data: 'C1'),
        TreeNode(key: 'c2', data: 'C2'),
      ], animate: false);
      expect(controller.visibleNodes, ['root', 'c3', 'c1', 'c2']);
    });

    testWidgets('updates data for retained children', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      sync.syncRoots([TreeNode(key: 'root', data: 'Root')], animate: false);
      sync.syncChildren('root', [
        TreeNode(key: 'c1', data: 'old-C1'),
      ], animate: false);

      expect(controller.getNodeData('c1')!.data, 'old-C1');

      sync.syncChildren('root', [
        TreeNode(key: 'c1', data: 'new-C1'),
      ], animate: false);

      expect(controller.getNodeData('c1')!.data, 'new-C1');
    });
  });

  group('syncRoots — add, remove, and reorder combined', () {
    testWidgets('handles simultaneous add, remove, and reorder', (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      sync.syncRoots([
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
        TreeNode(key: 'c', data: 'C'),
      ], animate: false);

      // Remove b, add d, reorder a and c.
      sync.syncRoots([
        TreeNode(key: 'c', data: 'C'),
        TreeNode(key: 'd', data: 'D'),
        TreeNode(key: 'a', data: 'A'),
      ], animate: false);

      expect(controller.visibleNodes, ['c', 'd', 'a']);
      expect(controller.getNodeData('b'), isNull);
    });
  });

  group('syncRoots/syncChildren — reparenting via moveNode', () {
    testWidgets('root demoted to child preserves expansion state', (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      // Initial: two roots, 'b' has children and is expanded.
      sync.syncRoots(
        [TreeNode(key: 'a', data: 'A'), TreeNode(key: 'b', data: 'B')],
        childrenOf: (key) =>
            key == 'b' ? [TreeNode(key: 'b1', data: 'B1')] : [],
        animate: false,
      );
      controller.expand(key: 'b');
      expect(controller.isExpanded('b'), true);
      expect(controller.visibleNodes, ['a', 'b', 'b1']);

      // Reparent: 'b' moves from root to child of 'a'.
      sync.syncRoots(
        [TreeNode(key: 'a', data: 'A')],
        childrenOf: (key) => key == 'a'
            ? [TreeNode(key: 'b', data: 'B')]
            : key == 'b'
            ? [TreeNode(key: 'b1', data: 'B1')]
            : [],
        animate: false,
      );

      // 'b' should be under 'a' with expansion state preserved.
      expect(controller.getParent('b'), 'a');
      expect(controller.isExpanded('b'), true);
      expect(controller.getNodeData('b'), isNotNull);
      expect(controller.getNodeData('b1'), isNotNull);
    });

    testWidgets('child promoted to root via syncRoots preserves data', (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      sync.syncRoots(
        [TreeNode(key: 'a', data: 'A')],
        childrenOf: (key) => key == 'a' ? [TreeNode(key: 'b', data: 'B')] : [],
        animate: false,
      );
      expect(controller.getParent('b'), 'a');

      // Promote 'b' to root.
      sync.syncRoots(
        [TreeNode(key: 'a', data: 'A'), TreeNode(key: 'b', data: 'B')],
        childrenOf: (key) => [],
        animate: false,
      );

      expect(controller.getParent('b'), isNull);
      expect(controller.getNodeData('b'), isNotNull);
      expect(controller.visibleNodes, ['a', 'b']);
    });

    testWidgets('child-to-child reparent preserves expansion state', (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      // Initial: root a has children [x, y], root b has no children.
      // childrenOf is only called for roots (not recursive).
      sync.syncRoots(
        [TreeNode(key: 'a', data: 'A'), TreeNode(key: 'b', data: 'B')],
        childrenOf: (key) => key == 'a'
            ? [TreeNode(key: 'x', data: 'X'), TreeNode(key: 'y', data: 'Y')]
            : [],
        animate: false,
      );
      controller.expand(key: 'a');
      expect(controller.getParent('x'), 'a');
      expect(controller.getParent('y'), 'a');
      expect(controller.visibleNodes, ['a', 'x', 'y', 'b']);

      // Move x from child of a to child of b.
      sync.syncRoots(
        [TreeNode(key: 'a', data: 'A'), TreeNode(key: 'b', data: 'B')],
        childrenOf: (key) => key == 'a'
            ? [TreeNode(key: 'y', data: 'Y')]
            : key == 'b'
            ? [TreeNode(key: 'x', data: 'X')]
            : [],
        animate: false,
      );

      // x moved from a to b via moveNode, preserving its data.
      expect(controller.getParent('x'), 'b');
      expect(controller.getNodeData('x'), isNotNull);
      // y still under a.
      expect(controller.getParent('y'), 'a');
    });
  });

  group('syncMultipleChildren — standalone batch reparenting', () {
    testWidgets('reparents across parents regardless of map iteration order', (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      // Initial: a has child x, b is empty.
      sync.syncRoots(
        [TreeNode(key: 'a', data: 'A'), TreeNode(key: 'b', data: 'B')],
        childrenOf: (key) => key == 'a' ? [TreeNode(key: 'x', data: 'X')] : [],
        animate: false,
      );
      controller.expand(key: 'a');
      expect(controller.getParent('x'), 'a');

      // Move x from a to b using the batch API.
      // The map may iterate a before b (source before destination),
      // but the batch pre-scan prevents premature removal.
      sync.syncMultipleChildren({
        'a': [],
        'b': [TreeNode(key: 'x', data: 'X')],
      }, animate: false);

      expect(controller.getParent('x'), 'b');
      expect(controller.getNodeData('x'), isNotNull);
    });

    testWidgets('animated reparent does not lose node to pending deletion', (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      sync = TreeSyncController(treeController: controller);

      sync.syncRoots(
        [TreeNode(key: 'a', data: 'A'), TreeNode(key: 'b', data: 'B')],
        childrenOf: (key) => key == 'a' ? [TreeNode(key: 'x', data: 'X')] : [],
        animate: false,
      );
      controller.expand(key: 'a');
      expect(controller.getParent('x'), 'a');

      // Animated batch reparent — source iterated before destination.
      sync.syncMultipleChildren({
        'a': [],
        'b': [TreeNode(key: 'x', data: 'X')],
      }, animate: true);

      // Let animations settle.
      await tester.pumpAndSettle();

      expect(controller.getParent('x'), 'b');
      expect(controller.getNodeData('x'), isNotNull);

      sync.dispose();
      controller.dispose();
    });
  });

  group("syncMultipleChildren — expansion restoration", () {
    testWidgets("restores expansion for newly inserted children", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      // Setup: root a with expanded child x.
      sync.syncRoots(
        [TreeNode(key: "a", data: "A")],
        childrenOf: (key) => key == "a" ? [TreeNode(key: "x", data: "X")] : [],
        animate: false,
      );
      controller.expand(key: "a");
      controller.expand(key: "x"); // no children, but marks as expanded

      // Remove x, which remembers its expansion state.
      sync.syncChildren("a", [], animate: false);
      expect(controller.getNodeData("x"), isNull);

      // Re-add x via syncMultipleChildren — should restore expansion.
      sync.syncMultipleChildren({
        "a": [TreeNode(key: "x", data: "X")],
      }, animate: false);

      expect(controller.getNodeData("x"), isNotNull);
      expect(controller.getParent("x"), "a");
    });
  });

  group("expansion memory — descendants preserved across remove/re-add", () {
    testWidgets("removing a parent remembers descendant expansion states", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      // Build: root -> child -> grandchild
      sync.syncRoots(
        [TreeNode(key: "root", data: "Root")],
        childrenOf: (key) => switch (key) {
          "root" => [TreeNode(key: "child", data: "Child")],
          "child" => [TreeNode(key: "grand", data: "Grand")],
          _ => [],
        },
        animate: false,
      );
      controller.expand(key: "root");
      controller.expand(key: "child");
      expect(controller.visibleNodes, ["root", "child", "grand"]);

      // Filter removes root (and its entire subtree).
      sync.syncRoots([], animate: false);
      expect(controller.visibleNodes, isEmpty);

      // Filter is cleared — root and subtree come back.
      sync.syncRoots(
        [TreeNode(key: "root", data: "Root")],
        childrenOf: (key) => switch (key) {
          "root" => [TreeNode(key: "child", data: "Child")],
          "child" => [TreeNode(key: "grand", data: "Grand")],
          _ => [],
        },
        animate: false,
      );

      // Expansion state of root AND child should be restored.
      expect(controller.isExpanded("root"), true);
      expect(controller.isExpanded("child"), true);
      expect(controller.visibleNodes, ["root", "child", "grand"]);
    });

    testWidgets("removing a child remembers its descendant expansion states", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      sync = TreeSyncController(treeController: controller);
      addTearDown(() {
        sync.dispose();
        controller.dispose();
      });

      // Build: root -> mid -> leaf
      sync.syncRoots(
        [TreeNode(key: "root", data: "Root")],
        childrenOf: (key) => switch (key) {
          "root" => [TreeNode(key: "mid", data: "Mid")],
          "mid" => [TreeNode(key: "leaf", data: "Leaf")],
          _ => [],
        },
        animate: false,
      );
      controller.expand(key: "root");
      controller.expand(key: "mid");
      expect(controller.visibleNodes, ["root", "mid", "leaf"]);

      // Remove only the mid child (root stays).
      sync.syncRoots(
        [TreeNode(key: "root", data: "Root")],
        childrenOf: (key) => [],
        animate: false,
      );
      expect(controller.visibleNodes, ["root"]);

      // Re-add mid with its subtree.
      sync.syncRoots(
        [TreeNode(key: "root", data: "Root")],
        childrenOf: (key) => switch (key) {
          "root" => [TreeNode(key: "mid", data: "Mid")],
          "mid" => [TreeNode(key: "leaf", data: "Leaf")],
          _ => [],
        },
        animate: false,
      );

      expect(controller.isExpanded("root"), true);
      expect(controller.isExpanded("mid"), true);
      expect(controller.visibleNodes, ["root", "mid", "leaf"]);
    });
  });

  group("expansion memory — animated remove then re-add", () {
    testWidgets("expansion memory survives pruning when removal is animated", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      sync = TreeSyncController(treeController: controller);

      // Build: two expanded root sections with children (like SyncedSliverTree).
      sync.syncRoots(
        [
          TreeNode(key: "today", data: "Today"),
          TreeNode(key: "overdue", data: "Overdue"),
        ],
        childrenOf: (key) => switch (key) {
          "today" => [TreeNode(key: "t1", data: "Task 1")],
          "overdue" => [TreeNode(key: "o1", data: "Task 2")],
          _ => [],
        },
        animate: false,
      );
      controller.expandAll(animate: false);
      expect(controller.isExpanded("today"), true);
      expect(controller.isExpanded("overdue"), true);
      expect(controller.visibleNodes, ["today", "t1", "overdue", "o1"]);

      // Filter: keep only "today" (animated removal of "overdue").
      sync.syncRoots(
        [TreeNode(key: "today", data: "Today")],
        childrenOf: (key) => switch (key) {
          "today" => [TreeNode(key: "t1", data: "Task 1")],
          _ => [],
        },
        animate: true,
      );

      // Let exit animation complete.
      await tester.pumpAndSettle();
      expect(controller.getNodeData("overdue"), isNull);

      // Clear filter: re-add "overdue" (animated insertion).
      sync.syncRoots(
        [
          TreeNode(key: "today", data: "Today"),
          TreeNode(key: "overdue", data: "Overdue"),
        ],
        childrenOf: (key) => switch (key) {
          "today" => [TreeNode(key: "t1", data: "Task 1")],
          "overdue" => [TreeNode(key: "o1", data: "Task 2")],
          _ => [],
        },
        animate: true,
      );
      await tester.pumpAndSettle();

      // "overdue" must come back expanded.
      expect(controller.isExpanded("overdue"), true);
      expect(controller.visibleNodes, ["today", "t1", "overdue", "o1"]);

      sync.dispose();
      controller.dispose();
    });

    testWidgets(
      "re-adding a filtered root before its exit completes restores its subtree",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        sync = TreeSyncController(treeController: controller);

        sync.syncRoots(
          [
            TreeNode(key: "today", data: "Today"),
            TreeNode(key: "overdue", data: "Overdue"),
          ],
          childrenOf: (key) => switch (key) {
            "today" => [TreeNode(key: "t1", data: "Task 1")],
            "overdue" => [TreeNode(key: "o1", data: "Task 2")],
            _ => [],
          },
          animate: false,
        );
        controller.expandAll(animate: false);
        expect(controller.visibleNodes, ["today", "t1", "overdue", "o1"]);

        sync.syncRoots(
          [TreeNode(key: "today", data: "Today")],
          childrenOf: (key) => switch (key) {
            "today" => [TreeNode(key: "t1", data: "Task 1")],
            _ => [],
          },
          animate: true,
        );

        await tester.pump(const Duration(milliseconds: 120));

        sync.syncRoots(
          [
            TreeNode(key: "today", data: "Today"),
            TreeNode(key: "overdue", data: "Overdue"),
          ],
          childrenOf: (key) => switch (key) {
            "today" => [TreeNode(key: "t1", data: "Task 1")],
            "overdue" => [TreeNode(key: "o1", data: "Task 2")],
            _ => [],
          },
          animate: true,
        );

        await tester.pumpAndSettle();

        expect(controller.getNodeData("overdue"), isNotNull);
        expect(controller.getNodeData("o1"), isNotNull);
        expect(controller.isExpanded("overdue"), true);
        expect(controller.visibleNodes, ["today", "t1", "overdue", "o1"]);

        sync.dispose();
        controller.dispose();
      },
    );

    testWidgets(
      "re-adding a filtered child before its exit completes restores descendants",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        sync = TreeSyncController(treeController: controller);

        sync.syncRoots(
          [TreeNode(key: "root", data: "Root")],
          childrenOf: (key) => switch (key) {
            "root" => [TreeNode(key: "mid", data: "Mid")],
            "mid" => [TreeNode(key: "leaf", data: "Leaf")],
            _ => [],
          },
          animate: false,
        );
        controller.expand(key: "root", animate: false);
        controller.expand(key: "mid", animate: false);
        expect(controller.visibleNodes, ["root", "mid", "leaf"]);

        sync.syncRoots(
          [TreeNode(key: "root", data: "Root")],
          childrenOf: (key) => switch (key) {
            "root" => <TreeNode<String, String>>[],
            _ => [],
          },
          animate: true,
        );

        await tester.pump(const Duration(milliseconds: 120));

        sync.syncRoots(
          [TreeNode(key: "root", data: "Root")],
          childrenOf: (key) => switch (key) {
            "root" => [TreeNode(key: "mid", data: "Mid")],
            "mid" => [TreeNode(key: "leaf", data: "Leaf")],
            _ => [],
          },
          animate: true,
        );

        await tester.pumpAndSettle();

        expect(controller.getNodeData("mid"), isNotNull);
        expect(controller.getNodeData("leaf"), isNotNull);
        expect(controller.isExpanded("root"), true);
        expect(controller.isExpanded("mid"), true);
        expect(controller.visibleNodes, ["root", "mid", "leaf"]);

        sync.dispose();
        controller.dispose();
      },
    );

    testWidgets(
      "promoting an exiting child to a root reverses from its current extent",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        sync = TreeSyncController(treeController: controller);

        sync.syncRoots(
          [
            TreeNode(key: "parent", data: "Parent"),
            TreeNode(key: "sibling", data: "Sibling"),
          ],
          childrenOf: (key) => switch (key) {
            "parent" => [TreeNode(key: "child", data: "Child")],
            _ => <TreeNode<String, String>>[],
          },
          animate: false,
        );
        controller.expand(key: "parent", animate: false);
        controller.setFullExtent("child", 48.0);

        sync.syncRoots(
          [
            TreeNode(key: "parent", data: "Parent"),
            TreeNode(key: "sibling", data: "Sibling"),
          ],
          childrenOf: (key) => const <TreeNode<String, String>>[],
          animate: true,
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        final extentDuringRemoval = controller.getCurrentExtent("child");
        expect(extentDuringRemoval, greaterThan(0.0));
        expect(extentDuringRemoval, lessThan(48.0));

        sync.syncRoots(
          [
            TreeNode(key: "parent", data: "Parent"),
            TreeNode(key: "sibling", data: "Sibling"),
            TreeNode(key: "child", data: "Child"),
          ],
          childrenOf: (key) => const <TreeNode<String, String>>[],
          animate: true,
        );

        final extentAfterReadd = controller.getCurrentExtent("child");
        expect(
          extentAfterReadd,
          closeTo(extentDuringRemoval, 0.01),
          reason:
              "A child restored as a root mid-exit should reverse from its "
              "current extent instead of snapping fully open.",
        );

        await tester.pumpAndSettle();

        expect(controller.getParent("child"), isNull);
        expect(controller.visibleNodes, ["parent", "sibling", "child"]);

        sync.dispose();
        controller.dispose();
      },
    );

    testWidgets(
      "reparenting an exiting child reverses from its current extent",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        sync = TreeSyncController(treeController: controller);

        sync.syncRoots(
          [
            TreeNode(key: "a", data: "A"),
            TreeNode(key: "b", data: "B"),
          ],
          childrenOf: (key) => switch (key) {
            "a" => [TreeNode(key: "x", data: "X")],
            "b" => [TreeNode(key: "b1", data: "B1")],
            _ => <TreeNode<String, String>>[],
          },
          animate: false,
        );
        controller.expand(key: "a", animate: false);
        controller.expand(key: "b", animate: false);
        controller.setFullExtent("x", 48.0);

        sync.syncRoots(
          [
            TreeNode(key: "a", data: "A"),
            TreeNode(key: "b", data: "B"),
          ],
          childrenOf: (key) => switch (key) {
            "b" => [TreeNode(key: "b1", data: "B1")],
            _ => <TreeNode<String, String>>[],
          },
          animate: true,
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        final extentDuringRemoval = controller.getCurrentExtent("x");
        expect(extentDuringRemoval, greaterThan(0.0));
        expect(extentDuringRemoval, lessThan(48.0));

        sync.syncRoots(
          [
            TreeNode(key: "a", data: "A"),
            TreeNode(key: "b", data: "B"),
          ],
          childrenOf: (key) => switch (key) {
            "b" => [
              TreeNode(key: "x", data: "X"),
              TreeNode(key: "b1", data: "B1"),
            ],
            _ => <TreeNode<String, String>>[],
          },
          animate: true,
        );

        final extentAfterReadd = controller.getCurrentExtent("x");
        expect(
          extentAfterReadd,
          closeTo(extentDuringRemoval, 0.01),
          reason:
              "A child restored under a new parent mid-exit should reverse "
              "from its current extent instead of snapping fully open.",
        );

        await tester.pumpAndSettle();

        expect(controller.getParent("x"), "b");
        expect(controller.visibleNodes, ["a", "b", "x", "b1"]);

        sync.dispose();
        controller.dispose();
      },
    );
  });

  group("sync controller recreation preserves state", () {
    testWidgets(
      "re-syncing after controller recreation does not corrupt tree",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        sync = TreeSyncController(
          treeController: controller,
          preserveExpansion: true,
        );
        addTearDown(() {
          sync.dispose();
          controller.dispose();
        });

        final roots = [
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ];
        List<TreeNode<String, String>> childrenOf(String key) {
          if (key == "a") {
            return [TreeNode(key: "a1", data: "A1")];
          }
          return [];
        }

        sync.syncRoots(roots, childrenOf: childrenOf, animate: false);
        controller.expand(key: "a");
        expect(controller.visibleNodes, ["a", "a1", "b"]);
        expect(controller.isExpanded("a"), true);

        // Simulate what SyncedSliverTree does on preserveExpansion change:
        // dispose old sync controller, create new one, re-sync.
        sync.dispose();
        sync = TreeSyncController(
          treeController: controller,
          preserveExpansion: false,
        );
        sync.initializeTracking();

        sync.syncRoots(roots, childrenOf: childrenOf, animate: false);

        // State must be fully preserved — same visible order, same expansion.
        expect(controller.visibleNodes, ["a", "a1", "b"]);
        expect(controller.isExpanded("a"), true);
        expect(controller.getParent("a1"), "a");
        expect(controller.rootCount, 2);
      },
    );

    testWidgets(
      "re-syncing with changed data after recreation applies diff correctly",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        sync = TreeSyncController(
          treeController: controller,
          preserveExpansion: true,
        );
        addTearDown(() {
          sync.dispose();
          controller.dispose();
        });

        sync.syncRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ], animate: false);

        // Recreate sync controller and initialize tracking from existing tree.
        sync.dispose();
        sync = TreeSyncController(
          treeController: controller,
          preserveExpansion: false,
        );
        sync.initializeTracking();

        // Sync with different data — 'b' removed, 'c' added.
        sync.syncRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "c", data: "C"),
        ], animate: false);

        expect(controller.visibleNodes, ["a", "c"]);
        expect(controller.getNodeData("b"), isNull);
        expect(controller.getNodeData("c"), isNotNull);
      },
    );
  });

  group("syncRoots — deep reparenting of former root", () {
    testWidgets(
      "root demoted to grandchild survives exit animation",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        sync = TreeSyncController(treeController: controller);

        // Initial: two roots 'a' and 'b'. 'b' has a child 'b1'.
        sync.syncRoots(
          [TreeNode(key: "a", data: "A"), TreeNode(key: "b", data: "B")],
          childrenOf: (key) =>
              key == "b" ? [TreeNode(key: "b1", data: "B1")] : [],
          animate: false,
        );
        controller.expand(key: "b");

        // Reparent: 'b' becomes a grandchild under 'a' -> 'mid'.
        // The buggy code path treated 'b' as a deletion because it was not
        // a direct child of any new root, scheduled an exit animation, then
        // moved it — and _finalizeAnimation would later purge the subtree.
        sync.syncRoots(
          [TreeNode(key: "a", data: "A")],
          childrenOf: (key) => switch (key) {
            "a" => [TreeNode(key: "mid", data: "Mid")],
            "mid" => [TreeNode(key: "b", data: "B")],
            "b" => [TreeNode(key: "b1", data: "B1")],
            _ => <TreeNode<String, String>>[],
          },
          animate: true,
        );

        await tester.pumpAndSettle();

        expect(controller.getNodeData("b"), isNotNull);
        expect(controller.getNodeData("b1"), isNotNull);
        expect(controller.getParent("b"), "mid");
        expect(controller.getParent("mid"), "a");
        expect(controller.getParent("b1"), "b");

        sync.dispose();
        controller.dispose();
      },
    );
  });

  group("syncMultipleChildren — tracking after partial reparent", () {
    testWidgets(
      "reparenting without including old parent leaves no stale tracking",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        sync = TreeSyncController(treeController: controller);
        addTearDown(() {
          sync.dispose();
          controller.dispose();
        });

        // a has child x, b is empty.
        sync.syncRoots(
          [TreeNode(key: "a", data: "A"), TreeNode(key: "b", data: "B")],
          childrenOf: (key) => key == "a" ? [TreeNode(key: "x", data: "X")] : [],
          animate: false,
        );

        // Move x to b without including 'a' in the batch.
        sync.syncMultipleChildren({
          "b": [TreeNode(key: "x", data: "X")],
        }, animate: false);
        expect(controller.getParent("x"), "b");

        // Now sync x back under 'a'. Previously this was a no-op because
        // _currentChildren['a'] was stale and still contained 'x', so
        // syncChildren saw nothing to add.
        sync.syncChildren(
          "a",
          [TreeNode(key: "x", data: "X")],
          animate: false,
        );
        expect(controller.getParent("x"), "a");
      },
    );
  });

  group("expansion memory — async children via direct syncChildren", () {
    testWidgets(
      "parent stays expanded when its children arrive in a later syncChildren",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        sync = TreeSyncController(treeController: controller);
        addTearDown(() {
          sync.dispose();
          controller.dispose();
        });

        // Seed: parent with a child, parent expanded.
        sync.syncRoots([TreeNode(key: "p", data: "P")], animate: false);
        sync.syncChildren(
          "p",
          [TreeNode(key: "c", data: "C")],
          animate: false,
        );
        controller.expand(key: "p", animate: false);
        expect(controller.isExpanded("p"), true);

        // Remove parent — expansion memory records isExpanded=true.
        sync.syncRoots([], animate: false);
        expect(controller.getNodeData("p"), isNull);

        // Re-add parent WITHOUT syncing its children in the same call
        // (simulates async-loaded subtrees or caller ordering). Pre-fix,
        // _restoreExpansion ran immediately, found no children, no-op'd,
        // and cleared the memory — so the later syncChildren could never
        // restore expansion.
        sync.syncRoots([TreeNode(key: "p", data: "P")], animate: false);

        // Children arrive in a later direct syncChildren call.
        sync.syncChildren(
          "p",
          [TreeNode(key: "c", data: "C")],
          animate: false,
        );

        expect(
          controller.isExpanded("p"),
          true,
          reason:
              "Expansion memory must survive until the parent's children "
              "are registered, so a deferred syncChildren can complete the "
              "restore.",
        );
        expect(controller.visibleNodes, ["p", "c"]);
      },
    );
  });

  group("maxExpansionMemorySize == 0 disables expansion memory", () {
    testWidgets(
      "memory does not grow when capacity is 0",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        sync = TreeSyncController(
          treeController: controller,
          maxExpansionMemorySize: 0,
        );
        addTearDown(() {
          sync.dispose();
          controller.dispose();
        });

        sync.syncRoots(
          [TreeNode(key: "p", data: "P")],
          childrenOf: (k) =>
              k == "p" ? [TreeNode(key: "c", data: "C")] : [],
          animate: false,
        );
        controller.expand(key: "p", animate: false);
        expect(controller.isExpanded("p"), true);

        // Remove the parent. Pre-fix, _rememberExpansion still populated
        // _expansionMemory (the eviction loop was gated by > 0, so 0 just
        // disabled eviction — not storage). Post-fix, capacity <= 0 bails
        // out of remembrance entirely.
        sync.syncRoots([], animate: false);

        // Re-add. With memory disabled, the re-added parent must NOT auto-
        // expand — there's no remembered state to restore from.
        sync.syncRoots(
          [TreeNode(key: "p", data: "P")],
          childrenOf: (k) =>
              k == "p" ? [TreeNode(key: "c", data: "C")] : [],
          animate: false,
        );
        expect(
          controller.isExpanded("p"),
          false,
          reason:
              "With maxExpansionMemorySize=0, expansion state must not be "
              "remembered across remove/re-add per the documented contract.",
        );
      },
    );
  });

  // Reparent-through-removed-root: a child that reparents while its old
  // parent (a root) is being removed in the same sync should play a clean
  // moveTo slide instead of a remove + add. This requires deferring the
  // old root's removal until after the recursive children sync has had a
  // chance to call moveNode on the reparented child.
  group("syncRoots — reparent through removed root", () {
    testWidgets(
      "child reparents cleanly when its old root is being removed in the "
      "same sync — new parent already exists",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.linear,
        );
        sync = TreeSyncController(treeController: controller);
        addTearDown(() {
          sync.dispose();
          controller.dispose();
        });

        // Initial: today=[taskA], comingUp=[taskC]. Both sections present.
        sync.syncRoots(
          [TreeNode(key: "today", data: "Today"),
           TreeNode(key: "comingUp", data: "Coming Up")],
          childrenOf: (k) {
            switch (k) {
              case "today":
                return [TreeNode(key: "taskA", data: "Task A")];
              case "comingUp":
                return [TreeNode(key: "taskC", data: "Task C")];
              default:
                return const [];
            }
          },
          animate: false,
        );
        controller.expand(key: "today", animate: false);
        controller.expand(key: "comingUp", animate: false);
        expect(controller.visibleNodes,
            ["today", "taskA", "comingUp", "taskC"]);

        final fullExtent = controller.getCurrentExtent("taskA");
        expect(fullExtent, greaterThan(0.0));

        // Sync to: today removed, taskA reparented under comingUp.
        sync.syncRoots(
          [TreeNode(key: "comingUp", data: "Coming Up")],
          childrenOf: (k) {
            switch (k) {
              case "comingUp":
                return [
                  TreeNode(key: "taskA", data: "Task A"),
                  TreeNode(key: "taskC", data: "Task C"),
                ];
              default:
                return const [];
            }
          },
          animate: true,
        );

        // After the first post-sync pump: taskA must NOT be pending-deletion.
        await tester.pump();
        expect(controller.isPendingDeletion("taskA"), isFalse,
            reason: "taskA was reparented, not removed");
        expect(controller.getParent("taskA"), "comingUp");

        // Extent invariance — the primary signal that the fix works.
        // Sample at several intermediate ticks; taskA should never shrink.
        for (int i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 80));
          expect(
            controller.getCurrentExtent("taskA"),
            closeTo(fullExtent, 1.0),
            reason: "taskA's extent must stay full throughout the slide "
                "(not shrink with today's exit)",
          );
        }

        // After settle: today purged, taskA under comingUp.
        await tester.pumpAndSettle();
        expect(controller.getNodeData("today"), isNull,
            reason: "today was removed and its exit completed");
        expect(controller.getParent("taskA"), "comingUp");
        expect(controller.visibleNodes, ["comingUp", "taskA", "taskC"]);
      },
    );

    testWidgets(
      "child reparents cleanly when its old root is being removed AND new "
      "root is being added in the same sync",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.linear,
        );
        sync = TreeSyncController(treeController: controller);
        addTearDown(() {
          sync.dispose();
          controller.dispose();
        });

        // Initial: only today exists, with taskA.
        sync.syncRoots(
          [TreeNode(key: "today", data: "Today")],
          childrenOf: (k) =>
              k == "today" ? [TreeNode(key: "taskA", data: "Task A")] : const [],
          animate: false,
        );
        controller.expand(key: "today", animate: false);
        expect(controller.visibleNodes, ["today", "taskA"]);

        final fullExtent = controller.getCurrentExtent("taskA");

        // Sync to: today gone, comingUp added containing taskA.
        sync.syncRoots(
          [TreeNode(key: "comingUp", data: "Coming Up")],
          childrenOf: (k) => k == "comingUp"
              ? [TreeNode(key: "taskA", data: "Task A")]
              : const [],
          animate: true,
        );

        await tester.pump();
        // taskA is reparented via moveNode(animate: true) — even though
        // comingUp is newly added. The previous "animate: false when parent
        // newly added" suppression would have made this a structural-only
        // move, defeating the slide. Without a mounted SliverTree the
        // slide engine has no hosts to stage a baseline on, so we don't
        // assert hasActiveSlides here — the visual regression test below
        // covers that path; here we rely on extent invariance.
        expect(controller.isPendingDeletion("taskA"), isFalse);
        expect(controller.getParent("taskA"), "comingUp");

        // Extent invariance across the full animation.
        for (int i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 80));
          expect(
            controller.getCurrentExtent("taskA"),
            closeTo(fullExtent, 1.0),
            reason: "taskA must stay at full extent, not shrink + regrow",
          );
        }

        await tester.pumpAndSettle();
        expect(controller.getNodeData("today"), isNull);
        expect(controller.getParent("taskA"), "comingUp");
        // comingUp was newly inserted, so it starts collapsed and taskA is
        // structurally present but not in the visible order yet. Expand it
        // to verify taskA is reachable.
        controller.expand(key: "comingUp", animate: false);
        expect(controller.visibleNodes, ["comingUp", "taskA"]);
      },
    );

    testWidgets(
      "former root reparented under a sibling root while a third root is "
      "being removed",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        sync = TreeSyncController(treeController: controller);
        addTearDown(() {
          sync.dispose();
          controller.dispose();
        });

        // Initial: roots A, B, C — all bare.
        sync.syncRoots(
          [TreeNode(key: "A", data: "A"),
           TreeNode(key: "B", data: "B"),
           TreeNode(key: "C", data: "C")],
          childrenOf: (k) => const [],
          animate: false,
        );

        // Desired: A has B as child; C removed.
        sync.syncRoots(
          [TreeNode(key: "A", data: "A")],
          childrenOf: (k) =>
              k == "A" ? [TreeNode(key: "B", data: "B")] : const [],
          animate: false,
        );

        expect(controller.getNodeData("C"), isNull,
            reason: "C had no descendants in desired tree — removed");
        expect(controller.getParent("B"), "A",
            reason: "B was reparented under A, not removed");
        expect(controller.getNodeData("B"), isNotNull);
      },
    );

    testWidgets(
      "all roots removed with no desired descendants — clean exits",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        sync = TreeSyncController(treeController: controller);
        addTearDown(() {
          sync.dispose();
          controller.dispose();
        });

        sync.syncRoots(
          [TreeNode(key: "a", data: "A"),
           TreeNode(key: "b", data: "B")],
          childrenOf: (k) {
            switch (k) {
              case "a":
                return [TreeNode(key: "a1", data: "A1")];
              case "b":
                return [TreeNode(key: "b1", data: "B1")];
              default:
                return const [];
            }
          },
          animate: false,
        );
        expect(controller.getNodeData("a"), isNotNull);
        expect(controller.getNodeData("b"), isNotNull);

        // Empty desired tree — both roots and their subtrees should go.
        sync.syncRoots(const [],
            childrenOf: (k) => const [], animate: false);

        expect(controller.getNodeData("a"), isNull);
        expect(controller.getNodeData("b"), isNull);
        expect(controller.getNodeData("a1"), isNull);
        expect(controller.getNodeData("b1"), isNull);
        expect(controller.visibleNodes, isEmpty);
      },
    );

    testWidgets(
      "insertRoot index correctness while pending removals are in flight",
      (tester) async {
        // Sync from [a, b, c] to [c, d] where d is new and a/b are removed.
        // The old roots are still in _roots when insertRoot(d) runs, so the
        // index plumbing must rely on the post-step-(2') filter, not on
        // current _roots length matching the desired view.
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.linear,
        );
        sync = TreeSyncController(treeController: controller);
        addTearDown(() {
          sync.dispose();
          controller.dispose();
        });

        sync.syncRoots(
          [TreeNode(key: "a", data: "A"),
           TreeNode(key: "b", data: "B"),
           TreeNode(key: "c", data: "C")],
          childrenOf: (k) => const [],
          animate: false,
        );

        sync.syncRoots(
          [TreeNode(key: "c", data: "C"),
           TreeNode(key: "d", data: "D")],
          childrenOf: (k) => const [],
          animate: true,
        );

        // After the full settle, the visible order must be exactly [c, d],
        // independent of the intermediate _roots state.
        await tester.pumpAndSettle();
        expect(controller.visibleNodes, ["c", "d"]);
        expect(controller.getNodeData("a"), isNull);
        expect(controller.getNodeData("b"), isNull);
      },
    );

    testWidgets(
      "expansion is preserved natively across reparent-through-removed-root",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        sync = TreeSyncController(treeController: controller);
        addTearDown(() {
          sync.dispose();
          controller.dispose();
        });

        // Initial: today=[taskA=[grand1]], comingUp=[taskC]. Expand taskA.
        sync.syncRoots(
          [TreeNode(key: "today", data: "Today"),
           TreeNode(key: "comingUp", data: "Coming Up")],
          childrenOf: (k) {
            switch (k) {
              case "today":
                return [TreeNode(key: "taskA", data: "Task A")];
              case "taskA":
                return [TreeNode(key: "grand1", data: "Grand 1")];
              case "comingUp":
                return [TreeNode(key: "taskC", data: "Task C")];
              default:
                return const [];
            }
          },
          animate: false,
        );
        controller.expand(key: "today", animate: false);
        controller.expand(key: "comingUp", animate: false);
        controller.expand(key: "taskA", animate: false);
        expect(controller.isExpanded("taskA"), isTrue);
        expect(controller.visibleNodes,
            ["today", "taskA", "grand1", "comingUp", "taskC"]);

        // Pre-sync: expansion memory is empty (no removals happened).
        expect(sync.snapshotRememberedKeys(), isEmpty);

        // Reparent taskA from today (being removed) to comingUp,
        // preserving grand1 underneath.
        sync.syncRoots(
          [TreeNode(key: "comingUp", data: "Coming Up")],
          childrenOf: (k) {
            switch (k) {
              case "comingUp":
                return [
                  TreeNode(key: "taskA", data: "Task A"),
                  TreeNode(key: "taskC", data: "Task C"),
                ];
              case "taskA":
                return [TreeNode(key: "grand1", data: "Grand 1")];
              default:
                return const [];
            }
          },
          animate: false,
        );

        // Expansion is preserved natively by moveNode, not via memory.
        expect(controller.isExpanded("taskA"), isTrue,
            reason: "moveNode preserves the moved subtree's expanded flag");
        expect(controller.visibleNodes,
            ["comingUp", "taskA", "grand1", "taskC"]);
        expect(controller.getParent("taskA"), "comingUp");
        expect(controller.getParent("grand1"), "taskA");

        // Expansion memory does NOT contain taskA or grand1 — they were
        // never removed, only moved. A future change that breaks this
        // (e.g., regressing moveNode's expansion preservation, or
        // accidentally walking reparented descendants through
        // _rememberExpansion) would surface here.
        final remembered = sync.snapshotRememberedKeys();
        expect(remembered.contains("taskA"), isFalse,
            reason: "taskA was reparented, not removed");
        expect(remembered.contains("grand1"), isFalse,
            reason: "grand1 rode along with taskA via moveNode");
      },
    );

    testWidgets(
      "visual regression: reparent through removed root preserves the row "
      "across the slide (My Work scenario)",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.linear,
        );
        sync = TreeSyncController(treeController: controller);
        addTearDown(() {
          sync.dispose();
          controller.dispose();
        });

        Widget harness() {
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
                            padding: EdgeInsets.only(left: depth * 16.0),
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

        sync.syncRoots(
          [TreeNode(key: "today", data: "Today"),
           TreeNode(key: "comingUp", data: "Coming Up")],
          childrenOf: (k) {
            switch (k) {
              case "today":
                return [TreeNode(key: "taskA", data: "Task A")];
              case "comingUp":
                return [TreeNode(key: "taskC", data: "Task C")];
              default:
                return const [];
            }
          },
          animate: false,
        );
        controller.expand(key: "today", animate: false);
        controller.expand(key: "comingUp", animate: false);

        await tester.pumpWidget(harness());
        await tester.pumpAndSettle();

        // Capture taskA's row before the reparent — must remain present
        // in the widget tree throughout the animation (no unmount).
        final taskARowFinder = find.byKey(const ValueKey("row-taskA"));
        expect(taskARowFinder, findsOneWidget);
        final oldY = tester.getTopLeft(taskARowFinder).dy;

        sync.syncRoots(
          [TreeNode(key: "comingUp", data: "Coming Up")],
          childrenOf: (k) {
            switch (k) {
              case "comingUp":
                return [
                  TreeNode(key: "taskA", data: "Task A"),
                  TreeNode(key: "taskC", data: "Task C"),
                ];
              default:
                return const [];
            }
          },
          animate: true,
        );

        // Sample intermediate ticks: taskA must stay mounted (finds one
        // widget) and never paint at a snap-to-zero / snap-to-final
        // position. This is the strongest signal we can assert without
        // committing to a specific trajectory.
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 70));
          expect(taskARowFinder, findsOneWidget,
              reason: "taskA must remain mounted across the slide — the "
                  "old bug would unmount it as part of today's exit");
        }

        await tester.pumpAndSettle();
        expect(taskARowFinder, findsOneWidget);
        // taskA's old painted Y (under today) and final painted Y (under
        // comingUp) happen to coincide in this canonical 48-px-row
        // scenario, but allow rounding tolerance.
        final newY = tester.getTopLeft(taskARowFinder).dy;
        expect(newY, closeTo(oldY, 1.0));
      },
    );
  });
}
