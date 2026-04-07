import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

void main() {
  late TreeController<String, String> controller;

  setUp(() {
    // TestWidgetsFlutterBinding provides the TickerProvider via
    // WidgetTester, but for pure controller tests we use a zero-duration
    // controller so no real ticker is needed.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('updateNode', () {
    testWidgets('updates data without structural change', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
      ]);

      controller.updateNode(TreeNode(key: 'a', data: 'A-updated'));

      expect(controller.getNodeData('a')!.data, 'A-updated');
      expect(controller.getNodeData('b')!.data, 'B');
      // Structure unchanged.
      expect(controller.visibleNodes, ['a', 'b']);
    });

    testWidgets('notifies listeners', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: 'a', data: 'A')]);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.updateNode(TreeNode(key: 'a', data: 'A2'));
      expect(notifyCount, 1);
    });

    testWidgets('preserves expansion state', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: 'a', data: 'A')]);
      controller.setChildren('a', [TreeNode(key: 'a1', data: 'A1')]);
      controller.expand(key: 'a');

      expect(controller.isExpanded('a'), true);

      controller.updateNode(TreeNode(key: 'a', data: 'A-updated'));

      expect(controller.isExpanded('a'), true);
      expect(controller.visibleNodes, ['a', 'a1']);
    });
  });

  group('reorderRoots', () {
    testWidgets('changes visible order of roots', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
        TreeNode(key: 'c', data: 'C'),
      ]);
      expect(controller.visibleNodes, ['a', 'b', 'c']);

      controller.reorderRoots(['c', 'a', 'b']);
      expect(controller.visibleNodes, ['c', 'a', 'b']);
    });

    testWidgets('preserves expansion state and subtrees', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
      ]);
      controller.setChildren('a', [TreeNode(key: 'a1', data: 'A1')]);
      controller.expand(key: 'a');
      expect(controller.visibleNodes, ['a', 'a1', 'b']);

      controller.reorderRoots(['b', 'a']);
      expect(controller.visibleNodes, ['b', 'a', 'a1']);
      expect(controller.isExpanded('a'), true);
    });

    testWidgets('bumps structureGeneration', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
      ]);
      final gen = controller.structureGeneration;

      controller.reorderRoots(['b', 'a']);
      expect(controller.structureGeneration, greaterThan(gen));
    });
  });

  group('reorderChildren', () {
    testWidgets('reorders children of an expanded parent', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: 'root', data: 'Root')]);
      controller.setChildren('root', [
        TreeNode(key: 'c1', data: 'C1'),
        TreeNode(key: 'c2', data: 'C2'),
        TreeNode(key: 'c3', data: 'C3'),
      ]);
      controller.expand(key: 'root');
      expect(controller.visibleNodes, ['root', 'c1', 'c2', 'c3']);

      controller.reorderChildren('root', ['c3', 'c1', 'c2']);
      expect(controller.visibleNodes, ['root', 'c3', 'c1', 'c2']);
    });

    testWidgets('no visible change if parent is collapsed', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: 'root', data: 'Root')]);
      controller.setChildren('root', [
        TreeNode(key: 'c1', data: 'C1'),
        TreeNode(key: 'c2', data: 'C2'),
      ]);
      // Parent is collapsed — children not visible.
      expect(controller.visibleNodes, ['root']);

      controller.reorderChildren('root', ['c2', 'c1']);

      // Still not visible — but internal order changed.
      expect(controller.visibleNodes, ['root']);

      // Now expand to verify internal order.
      controller.expand(key: 'root');
      expect(controller.visibleNodes, ['root', 'c2', 'c1']);
    });
  });

  group('moveNode', () {
    testWidgets('moves a child to become a root', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: 'a', data: 'A')]);
      controller.setChildren('a', [TreeNode(key: 'a1', data: 'A1')]);
      controller.expand(key: 'a');
      expect(controller.visibleNodes, ['a', 'a1']);

      controller.moveNode('a1', null);
      expect(controller.visibleNodes, ['a', 'a1']);
      expect(controller.getDepth('a1'), 0);
      expect(controller.getParent('a1'), null);
    });

    testWidgets('moves a root to become a child', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
      ]);

      controller.moveNode('b', 'a');
      expect(controller.getParent('b'), 'a');
      expect(controller.getDepth('b'), 1);
      expect(controller.rootCount, 1);

      // Expand a to reveal the moved child.
      controller.expand(key: 'a');
      expect(controller.visibleNodes, ['a', 'b']);
    });

    testWidgets('moves between parents and updates depths recursively', (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
      ]);
      controller.setChildren('a', [TreeNode(key: 'a1', data: 'A1')]);
      controller.setChildren('a1', [TreeNode(key: 'a1x', data: 'A1X')]);
      controller.expand(key: 'a');
      controller.expand(key: 'a1');
      expect(controller.getDepth('a1x'), 2);

      // Move subtree a1 (with child a1x) under b.
      controller.moveNode('a1', 'b');
      expect(controller.getParent('a1'), 'b');
      expect(controller.getDepth('a1'), 1);
      expect(controller.getDepth('a1x'), 2);
    });

    testWidgets('preserves expansion state of moved subtree', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
      ]);
      controller.setChildren('a', [TreeNode(key: 'a1', data: 'A1')]);
      controller.setChildren('a1', [TreeNode(key: 'a1x', data: 'A1X')]);
      controller.expand(key: 'a');
      controller.expand(key: 'a1');
      expect(controller.isExpanded('a1'), true);

      controller.moveNode('a1', 'b');
      // Expansion state preserved.
      expect(controller.isExpanded('a1'), true);
    });

    testWidgets('is a no-op when already at the target parent', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: 'a', data: 'A')]);
      controller.setChildren('a', [TreeNode(key: 'a1', data: 'A1')]);
      final gen = controller.structureGeneration;

      controller.moveNode('a1', 'a');
      // No change — structureGeneration should not bump.
      expect(controller.structureGeneration, gen);
    });
  });

  group('animation-path safety', () {
    testWidgets('reorderRoots during expand animation does not corrupt state', (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );

      controller.setRoots([
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
      ]);
      controller.setChildren('a', [TreeNode(key: 'a1', data: 'A1')]);

      // Start an expand animation on 'a'.
      controller.expand(key: 'a');
      expect(controller.hasActiveAnimations, true);

      // Reorder roots while the expand animation is in flight.
      controller.reorderRoots(['b', 'a']);

      // Let the animation settle.
      await tester.pumpAndSettle();

      // State should be consistent.
      expect(controller.visibleNodes.first, 'b');
      expect(controller.isExpanded('a'), true);
      expect(controller.visibleNodes, contains('a1'));
      controller.dispose();
    });

    testWidgets('moveNode during expand animation preserves subtree', (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );

      controller.setRoots([
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
      ]);
      controller.setChildren('a', [TreeNode(key: 'a1', data: 'A1')]);

      controller.expand(key: 'a');
      expect(controller.hasActiveAnimations, true);

      // Move a1 to b while a is still animating.
      controller.moveNode('a1', 'b');

      await tester.pumpAndSettle();

      expect(controller.getParent('a1'), 'b');
      expect(controller.getNodeData('a1'), isNotNull);
      controller.dispose();
    });

    testWidgets('reorderChildren during animation is safe', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );

      controller.setRoots([TreeNode(key: 'root', data: 'Root')]);
      controller.setChildren('root', [
        TreeNode(key: 'c1', data: 'C1'),
        TreeNode(key: 'c2', data: 'C2'),
      ]);

      // Animate expand.
      controller.expand(key: 'root');
      expect(controller.hasActiveAnimations, true);

      // Reorder children mid-animation.
      controller.reorderChildren('root', ['c2', 'c1']);

      await tester.pumpAndSettle();

      expect(controller.visibleNodes, ['root', 'c2', 'c1']);
      controller.dispose();
    });
  });

  group('comparator', () {
    late TreeController<String, String> sorted;

    testWidgets('setRoots sorts by comparator', (tester) async {
      sorted = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
        comparator: (a, b) => a.data.compareTo(b.data),
      );
      addTearDown(sorted.dispose);

      sorted.setRoots([
        TreeNode(key: 'c', data: 'Cherry'),
        TreeNode(key: 'a', data: 'Apple'),
        TreeNode(key: 'b', data: 'Banana'),
      ]);

      expect(sorted.visibleNodes, ['a', 'b', 'c']);
    });

    testWidgets('insertRoot places node in sorted position', (tester) async {
      sorted = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
        comparator: (a, b) => a.data.compareTo(b.data),
      );
      addTearDown(sorted.dispose);

      sorted.setRoots([
        TreeNode(key: 'a', data: 'Apple'),
        TreeNode(key: 'c', data: 'Cherry'),
      ]);

      sorted.insertRoot(TreeNode(key: 'b', data: 'Banana'));
      expect(sorted.visibleNodes, ['a', 'b', 'c']);

      // Insert at the beginning.
      sorted.insertRoot(TreeNode(key: 'z', data: 'Aardvark'));
      expect(sorted.visibleNodes, ['z', 'a', 'b', 'c']);

      // Insert at the end.
      sorted.insertRoot(TreeNode(key: 'd', data: 'Durian'));
      expect(sorted.visibleNodes, ['z', 'a', 'b', 'c', 'd']);
    });

    testWidgets('insertRoot explicit index overrides comparator', (
      tester,
    ) async {
      sorted = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
        comparator: (a, b) => a.data.compareTo(b.data),
      );
      addTearDown(sorted.dispose);

      sorted.setRoots([
        TreeNode(key: 'a', data: 'Apple'),
        TreeNode(key: 'c', data: 'Cherry'),
      ]);

      // Explicit index 0 overrides sorted position.
      sorted.insertRoot(TreeNode(key: 'b', data: 'Banana'), index: 0);
      expect(sorted.visibleNodes, ['b', 'a', 'c']);
    });

    testWidgets('setChildren sorts by comparator', (tester) async {
      sorted = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
        comparator: (a, b) => a.data.compareTo(b.data),
      );
      addTearDown(sorted.dispose);

      sorted.setRoots([TreeNode(key: 'root', data: 'Root')]);
      sorted.setChildren('root', [
        TreeNode(key: 'c', data: 'Cherry'),
        TreeNode(key: 'a', data: 'Apple'),
        TreeNode(key: 'b', data: 'Banana'),
      ]);
      sorted.expand(key: 'root');

      expect(sorted.visibleNodes, ['root', 'a', 'b', 'c']);
    });

    testWidgets('insert child places node in sorted position', (tester) async {
      sorted = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
        comparator: (a, b) => a.data.compareTo(b.data),
      );
      addTearDown(sorted.dispose);

      sorted.setRoots([TreeNode(key: 'root', data: 'Root')]);
      sorted.setChildren('root', [
        TreeNode(key: 'a', data: 'Apple'),
        TreeNode(key: 'c', data: 'Cherry'),
      ]);
      sorted.expand(key: 'root');

      sorted.insert(
        parentKey: 'root',
        node: TreeNode(key: 'b', data: 'Banana'),
      );

      expect(sorted.visibleNodes, ['root', 'a', 'b', 'c']);
    });

    testWidgets('order maintained after remove and re-insert', (tester) async {
      sorted = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
        comparator: (a, b) => a.data.compareTo(b.data),
      );
      addTearDown(sorted.dispose);

      sorted.setRoots([
        TreeNode(key: 'a', data: 'Apple'),
        TreeNode(key: 'b', data: 'Banana'),
        TreeNode(key: 'c', data: 'Cherry'),
      ]);

      sorted.remove(key: 'b');
      expect(sorted.visibleNodes, ['a', 'c']);

      sorted.insertRoot(TreeNode(key: 'b', data: 'Banana'));
      expect(sorted.visibleNodes, ['a', 'b', 'c']);
    });

    testWidgets('moveNode respects comparator', (tester) async {
      sorted = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
        comparator: (a, b) => a.data.compareTo(b.data),
      );
      addTearDown(sorted.dispose);

      sorted.setRoots([
        TreeNode(key: 'root', data: 'Root'),
        TreeNode(key: 'a', data: 'Apple'),
        TreeNode(key: 'c', data: 'Cherry'),
      ]);
      sorted.setChildren('root', [TreeNode(key: 'd', data: 'Date')]);
      sorted.expand(key: 'root');

      // Move 'a' (Apple) under 'root' — should land before Date.
      sorted.moveNode('a', 'root');
      expect(sorted.visibleNodes, ['c', 'root', 'a', 'd']);

      // Move 'c' (Cherry) under 'root' — should land between Date and Cherry? No:
      // Children are [Apple, Date], Cherry sorts after Date.
      sorted.moveNode('c', 'root');
      expect(sorted.visibleNodes, ['root', 'a', 'c', 'd']);
    });

    testWidgets('insertRoot into empty tree with comparator', (tester) async {
      sorted = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
        comparator: (a, b) => a.data.compareTo(b.data),
      );
      addTearDown(sorted.dispose);

      sorted.insertRoot(TreeNode(key: 'b', data: 'Banana'));
      expect(sorted.visibleNodes, ['b']);

      sorted.insertRoot(TreeNode(key: 'a', data: 'Apple'));
      expect(sorted.visibleNodes, ['a', 'b']);
    });

    testWidgets(
      'animated: new node sorts correctly while another is pending deletion',
      (tester) async {
        sorted = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
          comparator: (a, b) => a.data.compareTo(b.data),
        );
        addTearDown(sorted.dispose);

        sorted.setRoots([
          TreeNode(key: 'a', data: 'Apple'),
          TreeNode(key: 'b', data: 'Banana'),
          TreeNode(key: 'd', data: 'Date'),
        ]);

        // Remove 'b' with animation — it becomes pending deletion.
        sorted.remove(key: 'b');
        expect(sorted.visibleNodes, containsAll(['a', 'b', 'd']));

        // Insert 'c' while 'b' is still animating out.
        // Should land between Apple and Date (skipping pending-deletion Banana).
        sorted.insertRoot(TreeNode(key: 'c', data: 'Cherry'));

        // After settling, 'b' finishes exit and 'c' is in sorted position.
        await tester.pumpAndSettle();
        expect(sorted.visibleNodes, ['a', 'c', 'd']);
      },
    );

    testWidgets(
      'animated: cancel-deletion does not reposition — node stays in place',
      (tester) async {
        sorted = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
          comparator: (a, b) => a.data.compareTo(b.data),
        );
        addTearDown(sorted.dispose);

        sorted.setRoots([
          TreeNode(key: 'a', data: 'Apple'),
          TreeNode(key: 'b', data: 'Banana'),
          TreeNode(key: 'c', data: 'Cherry'),
        ]);

        // Remove 'b' (pending deletion), then immediately re-insert.
        // The cancel-deletion path restores 'b' in its original slot,
        // which is still the correct sorted position.
        sorted.remove(key: 'b');
        sorted.insertRoot(TreeNode(key: 'b', data: 'Banana'));

        await tester.pumpAndSettle();
        expect(sorted.visibleNodes, ['a', 'b', 'c']);
      },
    );

    testWidgets('no comparator preserves insertion order', (tester) async {
      final unsorted = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(unsorted.dispose);

      unsorted.setRoots([
        TreeNode(key: 'c', data: 'Cherry'),
        TreeNode(key: 'a', data: 'Apple'),
      ]);
      unsorted.insertRoot(TreeNode(key: 'b', data: 'Banana'));

      // Without comparator, appends to end.
      expect(unsorted.visibleNodes, ['c', 'a', 'b']);
    });
  });
}
