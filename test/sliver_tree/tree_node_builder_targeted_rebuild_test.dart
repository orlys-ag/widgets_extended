import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  group('TreeNodeBuilder targeted rebuilds', () {
    testWidgets('expand on key A rebuilds A only, not unrelated B', (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      controller.setRoots([
        const TreeNode(key: 'A', data: 'A'),
        const TreeNode(key: 'B', data: 'B'),
      ]);
      controller.setChildren('A', [const TreeNode(key: 'A1', data: 'A1')]);
      controller.setChildren('B', [const TreeNode(key: 'B1', data: 'B1')]);

      int countA = 0;
      int countB = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              TreeNodeBuilder<String, String>(
                controller: controller,
                nodeId: 'A',
                builder: (context, hasChildren, isExpanded) {
                  countA++;
                  return const SizedBox.shrink();
                },
              ),
              TreeNodeBuilder<String, String>(
                controller: controller,
                nodeId: 'B',
                builder: (context, hasChildren, isExpanded) {
                  countB++;
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      );

      final initialA = countA;
      final initialB = countB;

      controller.expand(key: 'A', animate: false);
      await tester.pump();

      expect(countA, greaterThan(initialA), reason: 'A should rebuild');
      expect(countB, initialB, reason: 'B should NOT rebuild');

      controller.dispose();
    });

    testWidgets('insert under A rebuilds A (hasChildren may flip), not B', (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      // A starts with no children; B has children.
      controller.setRoots([
        const TreeNode(key: 'A', data: 'A'),
        const TreeNode(key: 'B', data: 'B'),
      ]);
      controller.setChildren('B', [const TreeNode(key: 'B1', data: 'B1')]);

      int countA = 0;
      int countB = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              TreeNodeBuilder<String, String>(
                controller: controller,
                nodeId: 'A',
                builder: (context, hasChildren, isExpanded) {
                  countA++;
                  return const SizedBox.shrink();
                },
              ),
              TreeNodeBuilder<String, String>(
                controller: controller,
                nodeId: 'B',
                builder: (context, hasChildren, isExpanded) {
                  countB++;
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      );

      final initialA = countA;
      final initialB = countB;

      // Insert first child under A — flips hasChildren false → true.
      controller.insert(
        parentKey: 'A',
        node: const TreeNode(key: 'A1', data: 'A1'),
        animate: false,
      );
      await tester.pump();

      expect(countA, greaterThan(initialA), reason: 'A should rebuild');
      expect(countB, initialB, reason: 'B should NOT rebuild');

      controller.dispose();
    });

    testWidgets('expandAll fires the full-refresh branch (both rebuild)', (
      tester,
    ) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      controller.setRoots([
        const TreeNode(key: 'A', data: 'A'),
        const TreeNode(key: 'B', data: 'B'),
      ]);
      controller.setChildren('A', [const TreeNode(key: 'A1', data: 'A1')]);
      controller.setChildren('B', [const TreeNode(key: 'B1', data: 'B1')]);

      int countA = 0;
      int countB = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              TreeNodeBuilder<String, String>(
                controller: controller,
                nodeId: 'A',
                builder: (context, hasChildren, isExpanded) {
                  countA++;
                  return const SizedBox.shrink();
                },
              ),
              TreeNodeBuilder<String, String>(
                controller: controller,
                nodeId: 'B',
                builder: (context, hasChildren, isExpanded) {
                  countB++;
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      );

      final initialA = countA;
      final initialB = countB;

      controller.expandAll(animate: false);
      await tester.pump();

      expect(countA, greaterThan(initialA), reason: 'A should rebuild');
      expect(countB, greaterThan(initialB), reason: 'B should rebuild');

      controller.dispose();
    });
  });
}
