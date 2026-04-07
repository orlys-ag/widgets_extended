import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/tree_sync_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

void main() {
  late TreeController<String, String> controller;
  late TreeSyncController<String, String> sync;

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
}
