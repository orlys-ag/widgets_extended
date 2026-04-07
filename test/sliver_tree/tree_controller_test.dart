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

  // ════════════════════════════════════════════════════════════════════════════
  // BUG REGRESSION: setChildren on an already-expanded parent
  // ════════════════════════════════════════════════════════════════════════════

  group("setChildren on expanded parent", () {
    testWidgets("new children are visible after replacing on expanded parent", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [TreeNode(key: "c1", data: "C1")]);
      controller.expand(key: "a");
      expect(controller.visibleNodes, ["a", "c1"]);

      // Replace children while parent is expanded.
      controller.setChildren("a", [
        TreeNode(key: "c2", data: "C2"),
        TreeNode(key: "c3", data: "C3"),
      ]);

      // New children must appear in the visible order.
      expect(controller.visibleNodes, ["a", "c2", "c3"]);
      expect(controller.isExpanded("a"), true);
      expect(controller.hasChildren("a"), true);
    });

    testWidgets("replacing with empty list on expanded parent hides children", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [TreeNode(key: "c1", data: "C1")]);
      controller.expand(key: "a");
      expect(controller.visibleNodes, ["a", "c1"]);

      // Replace with empty list — old children removed, no new children.
      controller.setChildren("a", []);

      expect(controller.visibleNodes, ["a"]);
      expect(controller.hasChildren("a"), false);
    });

    testWidgets("replacing children preserves parent expansion state", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [TreeNode(key: "c1", data: "C1")]);
      controller.expand(key: "a");

      controller.setChildren("a", [TreeNode(key: "c2", data: "C2")]);

      // Parent should still be expanded and collapsible.
      expect(controller.isExpanded("a"), true);
      controller.collapse(key: "a");
      expect(controller.visibleNodes, ["a"]);
      controller.expand(key: "a");
      expect(controller.visibleNodes, ["a", "c2"]);
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // BUG REGRESSION: _rebuildVisibleOrder during collapse animation
  //
  // _rebuildVisibleOrder drops OperationGroup pendingRemoval nodes because
  // _expanded[key] is already false, so it doesn't recurse into the
  // collapsed parent's children. The collapsing nodes snap away instead of
  // completing their animation. These tests check INTERMEDIATE state (right
  // after the reorder) to catch the visual snap.
  // ════════════════════════════════════════════════════════════════════════════

  group("reorder during collapse animation", () {
    testWidgets("collapsing children survive reorderRoots (not snapped away)", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );

      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
      controller.expand(key: "a", animate: false);
      expect(controller.visibleNodes, ["a", "a1", "b"]);

      // Start a collapse animation on "a".
      controller.collapse(key: "a");
      expect(controller.hasActiveAnimations, true);
      // "a1" should still be in visibleNodes (animating out).
      expect(controller.visibleNodes, contains("a1"));

      // Reorder roots while collapse is in flight.
      controller.reorderRoots(["b", "a"]);

      // KEY CHECK: "a1" must still be present (still animating), not
      // snapped away by _rebuildVisibleOrder.
      expect(
        controller.visibleNodes,
        contains("a1"),
        reason: "collapsing child should survive reorderRoots",
      );

      // After settling, "a1" should be gone.
      await tester.pumpAndSettle();
      expect(controller.visibleNodes, ["b", "a"]);
      controller.dispose();
    });

    testWidgets("collapsing descendants survive reorderRoots with deep tree", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );

      controller.setRoots([
        TreeNode(key: "root", data: "Root"),
        TreeNode(key: "other", data: "Other"),
      ]);
      controller.setChildren("root", [
        TreeNode(key: "c1", data: "C1"),
        TreeNode(key: "c2", data: "C2"),
      ]);
      controller.setChildren("c1", [TreeNode(key: "c1a", data: "C1A")]);
      controller.expand(key: "root", animate: false);
      controller.expand(key: "c1", animate: false);
      expect(controller.visibleNodes, ["root", "c1", "c1a", "c2", "other"]);

      // Start collapsing "root" (c1, c1a, c2 enter exit animation).
      controller.collapse(key: "root");
      expect(controller.hasActiveAnimations, true);

      // Reorder roots while collapse is in flight.
      controller.reorderRoots(["other", "root"]);

      // KEY CHECK: collapsing descendants must still be animating.
      expect(
        controller.visibleNodes,
        contains("c1"),
        reason: "collapsing child should survive reorderRoots",
      );

      await tester.pumpAndSettle();
      expect(controller.visibleNodes, ["other", "root"]);
      expect(controller.getNodeData("c1"), isNotNull);
      controller.dispose();
    });

    testWidgets("moveNode during collapse animation preserves subtree", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );

      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
      controller.expand(key: "a", animate: false);
      expect(controller.visibleNodes, ["a", "a1", "b"]);

      // Start a collapse animation on "a".
      controller.collapse(key: "a");
      expect(controller.hasActiveAnimations, true);

      // Move "a1" to "b" while collapse is in flight.
      controller.moveNode("a1", "b");

      await tester.pumpAndSettle();

      // "a1" should be preserved under "b", not lost.
      expect(controller.getParent("a1"), "b");
      expect(controller.getNodeData("a1"), isNotNull);
      controller.dispose();
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // SAFETY: nested concurrent collapse
  //
  // When collapsing a parent while a child is already mid-collapse,
  // _getVisibleDescendants does not recurse into the collapsed child.
  // The grandchildren are handled by the child's own OperationGroup.
  // These tests verify the final state is always consistent.
  // ════════════════════════════════════════════════════════════════════════════

  group("nested concurrent collapse", () {
    testWidgets("collapsing parent while child is mid-collapse cleans up all", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );

      // Build a 3-level tree: A → B → C
      controller.setRoots([TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
      controller.setChildren("b", [TreeNode(key: "c", data: "C")]);
      controller.expandAll(animate: false);
      expect(controller.visibleNodes, ["a", "b", "c"]);

      // Collapse B — C starts exiting animation.
      controller.collapse(key: "b");
      expect(controller.hasActiveAnimations, true);
      expect(controller.visibleNodes, contains("c")); // still animating out

      // Immediately collapse A — B (and ideally C) should be captured.
      controller.collapse(key: "a");

      // Let all animations settle.
      await tester.pumpAndSettle();

      // Only "a" should remain visible. B and C must be gone.
      expect(controller.visibleNodes, ["a"]);
      expect(controller.isExpanded("a"), false);
      expect(controller.isExpanded("b"), false);
      controller.dispose();
    });

    testWidgets(
      "nested collapse followed by expand-all restores correct state",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );

        // A → B → C, all expanded.
        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
        controller.setChildren("b", [TreeNode(key: "c", data: "C")]);
        controller.expandAll(animate: false);
        expect(controller.visibleNodes, ["a", "b", "c"]);

        // Collapse B, then collapse A while B is still collapsing.
        controller.collapse(key: "b");
        controller.collapse(key: "a");

        // Let it all settle.
        await tester.pumpAndSettle();
        expect(controller.visibleNodes, ["a"]);

        // Now expand all — B and C should reappear cleanly.
        controller.expandAll(animate: false);
        expect(controller.visibleNodes, ["a", "b", "c"]);
        controller.dispose();
      },
    );

    testWidgets(
      "collapsing grandparent during child collapse with multiple children",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );

        // A → B → [C, D], all expanded.
        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
        controller.setChildren("b", [
          TreeNode(key: "c", data: "C"),
          TreeNode(key: "d", data: "D"),
        ]);
        controller.expandAll(animate: false);
        expect(controller.visibleNodes, ["a", "b", "c", "d"]);

        // Collapse B — C and D start exiting.
        controller.collapse(key: "b");

        // Advance partway through the animation.
        await tester.pump(const Duration(milliseconds: 100));
        expect(controller.hasActiveAnimations, true);

        // Collapse A while B's children are still animating.
        controller.collapse(key: "a");

        await tester.pumpAndSettle();

        // Only "a" should remain. No orphaned C or D.
        expect(controller.visibleNodes, ["a"]);
        controller.dispose();
      },
    );

    testWidgets(
      "4-level tree: collapse at level 2 then level 1 cleans up all",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );

        // A → B → C → D
        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
        controller.setChildren("b", [TreeNode(key: "c", data: "C")]);
        controller.setChildren("c", [TreeNode(key: "d", data: "D")]);
        controller.expandAll(animate: false);
        expect(controller.visibleNodes, ["a", "b", "c", "d"]);

        // Collapse C — D starts exiting.
        controller.collapse(key: "c");
        // Collapse B — C (and ideally D) should be captured.
        controller.collapse(key: "b");
        // Collapse A — B should be captured.
        controller.collapse(key: "a");

        await tester.pumpAndSettle();

        expect(controller.visibleNodes, ["a"]);

        // Re-expand all to verify internal state is clean.
        controller.expandAll(animate: false);
        expect(controller.visibleNodes, ["a", "b", "c", "d"]);
        controller.dispose();
      },
    );
  });

  group("expand with collapsed ancestors", () {
    testWidgets("sets expansion state even when ancestors are collapsed", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
      controller.setChildren("b", [TreeNode(key: "c", data: "C")]);

      // a is collapsed, b is collapsed.
      expect(controller.isExpanded("a"), false);
      expect(controller.isExpanded("b"), false);

      // Expand b while a is collapsed — should set state, not animate.
      controller.expand(key: "b");
      expect(controller.isExpanded("b"), true);
      // b's children are not visible (a is still collapsed).
      expect(controller.visibleNodes, ["a"]);

      // Now expand a — b should already be expanded, so c is visible.
      controller.expand(key: "a");
      expect(controller.visibleNodes, ["a", "b", "c"]);
    });

    testWidgets("notifies listeners when expanding under collapsed ancestor", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
      controller.setChildren("b", [TreeNode(key: "c", data: "C")]);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.expand(key: "b");
      expect(notifyCount, 1);
    });

    testWidgets(
      "does not expand an exiting node regardless of ancestor state",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );

        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
        controller.setChildren("b", [TreeNode(key: "c", data: "C")]);
        controller.expand(key: "a", animate: false);

        // Start removing b (puts it in exit animation).
        controller.remove(key: "b", animate: true);
        expect(controller.isExiting("b"), true);

        // Trying to expand an exiting node should be a no-op.
        controller.expand(key: "b");
        expect(controller.isExpanded("b"), false);

        await tester.pumpAndSettle();
        controller.dispose();
      },
    );
  });

  group("cancel-deletion zombie nodes", () {
    testWidgets(
      "re-inserting a removed node does not leave zombie children visible",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );

        // Build tree: root 'a' with child 'a1', expanded.
        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
        controller.expand(key: "a", animate: false);
        expect(controller.visibleNodes, ["a", "a1"]);

        // Remove with animation (puts both in pendingDeletion).
        controller.remove(key: "a", animate: true);
        expect(controller.visibleNodes, contains("a"));
        expect(controller.visibleNodes, contains("a1"));

        // Re-insert before animation completes (triggers cancel-deletion).
        controller.insertRoot(TreeNode(key: "a", data: "A"));
        expect(controller.isExpanded("a"), false);

        // Let all animations settle.
        await tester.pumpAndSettle();

        // Child should NOT be visible since parent is collapsed.
        expect(
          controller.visibleNodes,
          ["a"],
          reason:
              "Children of a collapsed parent must not remain in visibleNodes "
              "after cancel-deletion animations complete.",
        );

        controller.dispose();
      },
    );
  });
}
