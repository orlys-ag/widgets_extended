import 'package:flutter/animation.dart' show Curves;
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

    testWidgets('fires node-data listener with the changed key', (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
      ]);

      int structuralCount = 0;
      final dataChangedKeys = <String>[];
      controller.addListener(() => structuralCount++);
      controller.addNodeDataListener(dataChangedKeys.add);

      controller.updateNode(TreeNode(key: 'a', data: 'A2'));

      expect(dataChangedKeys, ['a']);
      // Data-only change must not fire the structural channel, otherwise
      // listeners that rebuild all mounted rows (e.g. SliverTreeElement)
      // would defeat the targeted-refresh optimization.
      expect(structuralCount, 0);
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

    testWidgets(
      "preservePendingSubtreeState keeps tree coherent when parent is collapsed",
      (tester) async {
        // Collapse 'a' mid-animation, then remove mid-collapse, then re-insert
        // with preservePendingSubtreeState=true. Since 'a' was collapsed at the
        // time of remove, its descendants must NOT be left visible under a
        // collapsed parent after the reversed animations complete.
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
        controller.expand(key: "a", animate: false);
        expect(controller.visibleNodes, ["a", "a1"]);

        controller.collapse(key: "a");
        await tester.pump(const Duration(milliseconds: 80));
        expect(controller.isExpanded("a"), false);

        controller.remove(key: "a");
        await tester.pump(const Duration(milliseconds: 50));

        controller.insertRoot(
          TreeNode(key: "a", data: "A"),
          preservePendingSubtreeState: true,
        );
        await tester.pumpAndSettle();

        expect(
          controller.visibleNodes,
          ["a"],
          reason:
              "Preserving subtree state must not park descendants in the "
              "visible order under a collapsed ancestor.",
        );
      },
    );

    testWidgets(
      "preservePendingSubtreeState reverses descendants when parent was expanded",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
        controller.expand(key: "a", animate: false);

        controller.remove(key: "a");
        await tester.pump(const Duration(milliseconds: 80));

        controller.insertRoot(
          TreeNode(key: "a", data: "A"),
          preservePendingSubtreeState: true,
        );
        await tester.pumpAndSettle();

        expect(controller.isExpanded("a"), true);
        expect(controller.visibleNodes, ["a", "a1"]);
      },
    );
  });

  group("reorderChildren during collapse animation", () {
    testWidgets(
      "reorders visible order for children still animating out",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "root", data: "R")]);
        controller.setChildren("root", [
          TreeNode(key: "x", data: "X"),
          TreeNode(key: "y", data: "Y"),
        ]);
        controller.expand(key: "root", animate: false);
        expect(controller.visibleNodes, ["root", "x", "y"]);

        // Begin an animated collapse. Children remain in visibleOrder until
        // the collapse animation finishes.
        controller.collapse(key: "root");
        await tester.pump(const Duration(milliseconds: 50));
        expect(controller.visibleNodes, ["root", "x", "y"]);

        // Reorder mid-collapse. Pre-fix this was a no-op because
        // _expanded['root'] is already false at this point.
        controller.reorderChildren("root", ["y", "x"]);
        expect(controller.visibleNodes, ["root", "y", "x"]);

        await tester.pumpAndSettle();
      },
    );
  });

  group("moveNode during exit animation", () {
    testWidgets(
      "reparented pending-deletion node is not purged after the animation",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        addTearDown(controller.dispose);

        controller.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ]);
        // Start removing 'b' (animated exit).
        controller.remove(key: "b");
        await tester.pump(const Duration(milliseconds: 50));
        expect(controller.getNodeData("b"), isNotNull);

        // Reparent 'b' under 'a' mid-exit. Pre-fix, _pendingDeletion still
        // flagged 'b' and _finalizeAnimation would purge it once the
        // animation completed — destroying the node at its new location.
        controller.moveNode("b", "a");
        controller.expand(key: "a", animate: false);

        await tester.pumpAndSettle();

        expect(controller.getNodeData("b"), isNotNull);
        expect(controller.getParent("b"), "a");
      },
    );
  });

  group("insert with pending-deletion node", () {
    testWidgets(
      "honors parentKey when node is pending deletion under another parent",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        addTearDown(controller.dispose);

        controller.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ]);
        controller.setChildren("a", [TreeNode(key: "x", data: "X-old")]);
        controller.expand(key: "a", animate: false);

        // Start removing 'x' (animated exit) — it's now pending deletion
        // under parent 'a'.
        controller.remove(key: "x");
        await tester.pump(const Duration(milliseconds: 50));
        expect(controller.getParent("x"), "a");

        // Insert 'x' under 'b'. Pre-fix, cancelDeletion resurrected 'x'
        // under 'a' and the parentKey argument was silently ignored.
        controller.insert(
          parentKey: "b",
          node: TreeNode(key: "x", data: "X-new"),
        );
        await tester.pumpAndSettle();

        expect(controller.getParent("x"), "b");
        expect(controller.getChildren("a"), isEmpty);
        expect(controller.getChildren("b"), ["x"]);
        expect(controller.getNodeData("x")!.data, "X-new");
        expect(controller.getDepth("x"), 1);
      },
    );

    testWidgets(
      "depth is refreshed when reparenting subtree from pending deletion",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        addTearDown(controller.dispose);

        // Build: root → a → x → y. Remove 'a' (animated) so 'a', 'x', 'y'
        // are all pending deletion at depths 1, 2, 3.
        controller.setRoots([TreeNode(key: "root", data: "R")]);
        controller.setChildren("root", [TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "x", data: "X")]);
        controller.setChildren("x", [TreeNode(key: "y", data: "Y")]);
        controller.expand(key: "root", animate: false);
        controller.expand(key: "a", animate: false);
        controller.expand(key: "x", animate: false);

        controller.remove(key: "a");
        await tester.pump(const Duration(milliseconds: 50));

        // Re-insert 'a' at root. Depth of 'a' should become 0 and the
        // subtree depths must cascade (x=1, y=2).
        controller.insertRoot(TreeNode(key: "a", data: "A-new"));
        await tester.pumpAndSettle();

        expect(controller.getParent("a"), isNull);
        expect(controller.getDepth("a"), 0);
        expect(controller.getDepth("x"), 1);
        expect(controller.getDepth("y"), 2);
      },
    );
  });

  group("insertRoot with pending-deletion node", () {
    testWidgets(
      "promotes a pending-deletion child back to the roots list",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "p", data: "P")]);
        controller.setChildren("p", [TreeNode(key: "c", data: "C-old")]);
        controller.expand(key: "p", animate: false);

        controller.remove(key: "c");
        await tester.pump(const Duration(milliseconds: 50));
        expect(controller.getParent("c"), "p");

        // Promote 'c' to a root. Pre-fix, cancelDeletion left 'c' under
        // 'p' and 'c' never appeared in the roots list.
        controller.insertRoot(TreeNode(key: "c", data: "C-new"));
        await tester.pumpAndSettle();

        expect(controller.getParent("c"), isNull);
        expect(controller.getDepth("c"), 0);
        expect(controller.getChildren("p"), isEmpty);
        expect(controller.rootKeys, containsAll(["p", "c"]));
        expect(controller.getNodeData("c")!.data, "C-new");
      },
    );
  });

  group("setFullExtent during collapse animation", () {
    testWidgets(
      "resize during reverse updates targetExtent so node still collapses to 0",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "r", data: "R")]);
        controller.setChildren("r", [TreeNode(key: "a", data: "A")]);
        controller.setFullExtent("a", 48);

        controller.expand(key: "r");
        await tester.pumpAndSettle();

        // Start the collapse. Member for 'a' is {start: 0, target: 48}.
        controller.collapse(key: "r");
        // Halfway through (linear curve → curvedValue = 0.5).
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 200));

        // Sanity: 'a' is mid-collapse — visible extent ≈ 24 (half of 48).
        expect(controller.getCurrentExtent("a"), closeTo(24, 5));

        // Simulate the render object measuring 'a' at a new, larger size
        // mid-collapse (e.g., text reflow). Pre-fix, this set startExtent=100
        // so the lerp ran from 100 → 48 instead of 0 → 100, leaving the node
        // with a non-zero extent even when fully dismissed.
        controller.setFullExtent("a", 100);

        // With the fix (targetExtent = 100, startExtent = 0):
        //   computeExtent(0.5, 100) = lerp(0, 100, 0.5) = 50
        // With the bug (startExtent = 100, targetExtent = 48):
        //   computeExtent(0.5, 100) = lerp(100, 48, 0.5) = 74
        expect(controller.getCurrentExtent("a"), closeTo(50, 5));

        await tester.pumpAndSettle();
        // Node is collapsed out of the visible order. Full extent cache is
        // the last measured value.
        expect(controller.getEstimatedExtent("a"), 100);
      },
    );
  });

  group("Path-1 reversal of captured mid-flight members", () {
    testWidgets(
      "re-expand after a collapse that captured a mid-flight descendant "
      "animates toward full extent, not the captured value",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        // A → B → C. Only A starts expanded.
        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
        controller.setChildren("b", [TreeNode(key: "c", data: "C")]);
        controller.setFullExtent("a", 48);
        controller.setFullExtent("b", 48);
        controller.setFullExtent("c", 48);
        controller.expand(key: "a", animate: false);
        expect(controller.visibleNodes, ["a", "b"]);

        // Expand B with animation. C joins Gb with target = 48 (full).
        controller.expand(key: "b");
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 200));
        // Mid-flight: C ≈ 24 (half of full).
        expect(controller.getCurrentExtent("c"), closeTo(24, 5));

        // Collapse A. Path-2 fresh collapse captures C from Gb at ≈24 and
        // stores it as Ga.member[c].targetExtent. Pre-fix, this captured
        // value stuck around when we reversed the collapse.
        controller.collapse(key: "a");
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 100));

        // Re-expand A. Path-1 reversal of Ga. With the fix, Ga.member[c]
        // .targetExtent is restored to the full extent so the forward
        // animation terminates at 48. Without the fix, C would cap out at
        // the captured ≈24 and snap to 48 at group disposal.
        controller.expand(key: "a");
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 50));

        // Ga.controller ≈ 0.875 (reverse reached 0.75, then forward ran
        // 50ms of the 100ms remaining). With fix: lerp(0, 48, 0.875) ≈ 42.
        // Without fix: lerp(0, 24, 0.875) ≈ 21.
        expect(
          controller.getCurrentExtent("c"),
          greaterThan(28),
          reason: "C should be animating toward its full 48-pixel extent "
              "after the collapse reversal, not capped at its captured "
              "mid-flight value.",
        );

        await tester.pumpAndSettle();
        expect(controller.visibleNodes, ["a", "b", "c"]);
        expect(controller.getCurrentExtent("c"), 48);
      },
    );

    testWidgets(
      "re-collapse after an expand that captured a mid-flight descendant "
      "animates toward zero extent, not the captured start",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        // A → B → C. A expanded, B expanded. C is visible and fully sized.
        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
        controller.setChildren("b", [TreeNode(key: "c", data: "C")]);
        controller.setFullExtent("a", 48);
        controller.setFullExtent("b", 48);
        controller.setFullExtent("c", 48);
        controller.expand(key: "a", animate: false);
        controller.expand(key: "b", animate: false);
        expect(controller.visibleNodes, ["a", "b", "c"]);

        // Collapse B with animation. C starts shrinking via Gb
        // (start=0, target=48, controller reversing from 1.0).
        controller.collapse(key: "b");
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 200));
        expect(controller.getCurrentExtent("c"), closeTo(24, 5));

        // Expand A — but A is already expanded. Expand B instead to force
        // Path-2 expand while C is mid-collapse via Gb.
        // Actually: Path-1 expand of Gb reverses the collapse. To hit
        // Path-2 expand with a captured non-zero start, we need a fresh
        // operation group. Collapse A first to remove Gb, then re-expand.
        controller.collapse(key: "a");
        await tester.pumpAndSettle();
        // Rebuild mid-flight setup: expand A with B already flagged
        // expanded. Expand B to trigger a fresh Gb, then mid-flight
        // capture into a new expand via A-level.
        controller.expand(key: "a", animate: false);
        controller.collapse(key: "b", animate: false);
        controller.expand(key: "b");
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 200));
        // C mid-entering via Gb at ≈24.

        // Now collapse A. Path-2 fresh collapse captures C at ≈24 into Ga
        // with (start=0, target≈24). This is the "captured target" path.
        controller.collapse(key: "a");
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 100));

        // Re-expand A. Path-1 reversal of Ga. Fix ensures target is
        // restored to 48; re-collapse should still terminate at 0.
        controller.expand(key: "a");
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 50));
        // Collapse A again. Path-1 reversal of Ga's forward. With fix,
        // each member's startExtent is normalized to 0 so the reversal
        // terminates at a fully-collapsed (0) extent.
        controller.collapse(key: "a");
        await tester.pumpAndSettle();

        // After full settle, only "a" is visible and C has been removed.
        expect(controller.visibleNodes, ["a"]);
      },
    );
  });

  group("bulk reversal of captured mid-flight members", () {
    testWidgets(
      "expandAll reversing an in-flight collapse group restores each "
      "member's targetExtent to full, not the captured mid-flight value",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        // A → B → C. Only A starts expanded.
        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
        controller.setChildren("b", [TreeNode(key: "c", data: "C")]);
        controller.setFullExtent("a", 48);
        controller.setFullExtent("b", 48);
        controller.setFullExtent("c", 48);
        controller.expand(key: "a", animate: false);

        // Expand B mid-flight. C joins Gb with target = 48.
        controller.expand(key: "b");
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 200));
        expect(controller.getCurrentExtent("c"), closeTo(24, 5));

        // Collapse A. Path-2 fresh collapse captures C from Gb at ≈24
        // into Ga with members[c].targetExtent ≈ 24.
        controller.collapse(key: "a");
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 100));

        // expandAll reverses Ga via controller.forward(). The fix must
        // normalize Ga.members[c].targetExtent back to 48 so the forward
        // reversal terminates at the full natural extent. Without the
        // fix, the lerp tops out at the captured ≈24 and snaps to 48
        // when the group disposes.
        controller.expandAll();
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          controller.getCurrentExtent("c"),
          greaterThan(28),
          reason: "C should be animating toward its full 48-pixel extent "
              "during expandAll's reversal of the collapsing Ga, not "
              "capped at its captured mid-flight value.",
        );

        await tester.pumpAndSettle();
        expect(controller.visibleNodes, ["a", "b", "c"]);
        expect(controller.getCurrentExtent("c"), 48);
      },
    );

    testWidgets(
      "collapseAll reversing an in-flight expand group normalizes each "
      "member's startExtent to 0, not the captured mid-flight value",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        // A → B → C. All expanded so C is visible at full extent.
        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
        controller.setChildren("b", [TreeNode(key: "c", data: "C")]);
        controller.setFullExtent("a", 48);
        controller.setFullExtent("b", 48);
        controller.setFullExtent("c", 48);
        controller.expand(key: "a", animate: false);
        controller.expand(key: "b", animate: false);
        expect(controller.visibleNodes, ["a", "b", "c"]);

        // collapseAll drives a bulk collapse. B, C shrink via the bulk
        // group (start=0, target=48, controller 1 → 0).
        controller.collapseAll();
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 200));
        expect(controller.getCurrentExtent("b"), closeTo(24, 5));

        // Expand A fresh while B, C are mid-collapse in the bulk.
        // Path-2 fresh expand of A captures B's ≈24 mid-flight extent
        // as startExtent into Ga. Ga.members[b] = (≈24, 48).
        controller.expand(key: "a");
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 50));

        // Now collapseAll again. This reverses Ga via controller.reverse().
        // The fix must normalize Ga.members[b].startExtent to 0 so the
        // reversal terminates at a fully-collapsed 0. Without the fix,
        // the lerp bottoms out at the captured ≈24 and visually snaps
        // to 0 on group disposal.
        controller.collapseAll();
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 30));

        expect(
          controller.getCurrentExtent("b"),
          lessThan(20),
          reason: "B should be collapsing toward 0 during collapseAll's "
              "reversal of the expanding Ga, not anchored at its "
              "captured mid-flight start value.",
        );

        await tester.pumpAndSettle();
        expect(controller.visibleNodes, ["a"]);
      },
    );
  });

  group("collapse with no visible descendants", () {
    testWidgets(
      "notifies listeners when collapsing a node whose children aren't visible",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        addTearDown(controller.dispose);

        // Tree: g -> p -> c. Collapse g so p's children aren't visible.
        // Then expand p — it takes the "ancestors collapsed" path which
        // sets _expanded[p]=true without touching visible order.
        controller.setRoots([TreeNode(key: "g", data: "G")]);
        controller.setChildren("g", [TreeNode(key: "p", data: "P")]);
        controller.setChildren("p", [TreeNode(key: "c", data: "C")]);
        controller.expand(key: "p", animate: false);
        // g is still collapsed, so p isn't in visibleOrder and neither is c.
        expect(controller.isExpanded("p"), true);
        expect(controller.visibleNodes, ["g"]);

        int notifyCount = 0;
        controller.addListener(() => notifyCount++);

        // Pre-fix: _expanded['p'] flipped to false, but the empty-descendants
        // early return skipped notifyListeners, leaving observers (e.g.
        // TreeNodeBuilder watching isExpanded) stale.
        controller.collapse(key: "p");

        expect(controller.isExpanded("p"), false);
        expect(
          notifyCount,
          greaterThan(0),
          reason:
              "collapse() must notify listeners even when there are no "
              "visible descendants — observers watch isExpanded.",
        );
      },
    );
  });

  group("getAnimationState for bulk group members", () {
    testWidgets(
      "returns synthetic entering state for forward bulk members",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "r", data: "R")]);
        controller.setChildren("r", [
          TreeNode(key: "c1", data: "C1"),
          TreeNode(key: "c2", data: "C2"),
        ]);

        // expandAll drives a bulk animation group. Pre-fix, members in that
        // group had no standalone AnimationState, so getAnimationState
        // returned null — callers (sticky header anchoring) couldn't see
        // them as entering and computed the wrong subtree bottom.
        controller.expandAll();
        await tester.pump(const Duration(milliseconds: 50));

        final state = controller.getAnimationState("c1");
        expect(
          state,
          isNotNull,
          reason:
              "Bulk-group members advancing forward must report a synthetic "
              "entering state so render-layer code can detect them.",
        );
        expect(state!.type, AnimationType.entering);

        await tester.pumpAndSettle();
      },
    );
  });

  group("insertRoot / insert re-insert honors index", () {
    testWidgets(
      "insertRoot with an existing key relocates to the requested index",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        addTearDown(controller.dispose);

        controller.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
          TreeNode(key: "c", data: "C"),
        ]);
        expect(controller.rootKeys, ["a", "b", "c"]);

        // Pre-fix, this silently returned without honoring index=0.
        controller.insertRoot(
          TreeNode(key: "c", data: "C-updated"),
          index: 0,
        );

        expect(controller.rootKeys, ["c", "a", "b"]);
        expect(controller.getNodeData("c")!.data, "C-updated");
        expect(controller.visibleNodes, ["c", "a", "b"]);
      },
    );

    testWidgets(
      "insert with an existing key reparents to the requested parent",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        addTearDown(controller.dispose);

        controller.setRoots([
          TreeNode(key: "p1", data: "P1"),
          TreeNode(key: "p2", data: "P2"),
        ]);
        controller.setChildren("p1", [TreeNode(key: "x", data: "X")]);
        controller.expand(key: "p1", animate: false);
        controller.expand(key: "p2", animate: false);
        expect(controller.getParent("x"), "p1");

        // Pre-fix, this was a silent no-op because 'x' already existed.
        controller.insert(
          parentKey: "p2",
          node: TreeNode(key: "x", data: "X-updated"),
        );

        expect(controller.getParent("x"), "p2");
        expect(controller.getNodeData("x")!.data, "X-updated");
        expect(controller.getChildren("p1"), isEmpty);
        expect(controller.getChildren("p2"), ["x"]);
      },
    );

    testWidgets(
      "insertRoot with same index is a no-op relocation (no notifyListeners spam is acceptable)",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        addTearDown(controller.dispose);

        controller.setRoots([
          TreeNode(key: "a", data: "A"),
          TreeNode(key: "b", data: "B"),
        ]);

        // Same position, same parent → just a data update.
        controller.insertRoot(TreeNode(key: "a", data: "A-updated"));
        expect(controller.rootKeys, ["a", "b"]);
        expect(controller.getNodeData("a")!.data, "A-updated");
      },
    );
  });

  group("getAnimationState returns fresh instances", () {
    testWidgets(
      "two synthetic entering states are not the same instance",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "r", data: "R")]);
        controller.setChildren("r", [
          TreeNode(key: "c1", data: "C1"),
          TreeNode(key: "c2", data: "C2"),
        ]);
        controller.expandAll();
        await tester.pump(const Duration(milliseconds: 50));

        final a = controller.getAnimationState("c1");
        final b = controller.getAnimationState("c2");
        expect(a, isNotNull);
        expect(b, isNotNull);
        // Pre-fix these were the same static singleton; mutating [a] would
        // have corrupted [b]. Post-fix each call yields a fresh instance.
        expect(identical(a, b), isFalse,
            reason: "Synthetic entering state must not be a shared singleton.");
        a!.progress = 0.42;
        expect(b!.progress, 0.0,
            reason: "Mutating one synthetic state must not affect another.");

        await tester.pumpAndSettle();
      },
    );
  });

  group("bulk animation group disposal", () {
    testWidgets(
      "bulk group is disposed after expandAll completes",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 100),
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "r", data: "R")]);
        controller.setChildren("r", [
          TreeNode(key: "c1", data: "C1"),
          TreeNode(key: "c2", data: "C2"),
        ]);

        expect(controller.hasActiveAnimations, isFalse);
        controller.expandAll();
        expect(controller.hasActiveAnimations, isTrue);

        await tester.pumpAndSettle();
        // Pre-fix, the bulk group's AnimationController stayed alive even
        // after completion (held a ticker registration for the life of the
        // controller). Post-fix it is disposed and hasActiveAnimations is
        // false without any lingering non-empty group.
        expect(controller.hasActiveAnimations, isFalse);
      },
    );
  });

  group("setChildren on pending-deletion parent", () {
    testWidgets(
      "asserts to prevent orphaned state",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 100),
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "b", data: "B")]);
        controller.expand(key: "a", animate: false);

        // Start an animated remove. 'a' is now pending deletion.
        controller.remove(key: "a", animate: true);
        await tester.pump(const Duration(milliseconds: 20));

        // Attaching children to a pending-deletion parent would leak state
        // once the parent's exit animation finalizes and purges only
        // pending-deletion descendants. Assertion prevents it.
        expect(
          () => controller.setChildren("a", [TreeNode(key: "x", data: "X")]),
          throwsA(isA<AssertionError>()),
        );

        await tester.pumpAndSettle();
      },
    );
  });

  group("orphaned operation group cleanup", () {
    testWidgets(
      "re-inserting and re-expanding a removed key does not reuse a stale "
      "operation group",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 200),
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "p", data: "P")]);
        controller.setChildren("p", [
          TreeNode(key: "c1", data: "C1"),
          TreeNode(key: "c2", data: "C2"),
        ]);

        // Fresh animated expand creates _operationGroups["p"].
        controller.expand(key: "p", animate: true);
        await tester.pump(const Duration(milliseconds: 50));
        expect(controller.isAnimating("c1"), isTrue);

        // Remove 'p' mid-animation without animating out (synchronous purge).
        // Pre-fix: _operationGroups["p"] survived because _purgeNodeData
        // only scrubbed membership, not the group keyed by the purged key.
        controller.remove(key: "p", animate: false);
        expect(controller.getNodeData("p"), isNull);
        expect(controller.getNodeData("c1"), isNull);

        // Re-insert and re-expand. If the old group were reused, the controller
        // value may already be at 1.0 (completed), so forward() is a no-op
        // and the child may never animate in — and later a stale status
        // callback could mutate the new state.
        controller.insertRoot(TreeNode(key: "p", data: "P"));
        controller.setChildren("p", [
          TreeNode(key: "c1", data: "C1"),
          TreeNode(key: "c2", data: "C2"),
        ]);
        controller.expand(key: "p", animate: true);

        // Children must actually animate in post-fix.
        expect(
          controller.isAnimating("c1"),
          isTrue,
          reason:
              "Expanding a re-inserted parent must create a fresh operation "
              "group with a controller starting at 0.0.",
        );
        await tester.pumpAndSettle();
        expect(controller.isExpanded("p"), isTrue);
        expect(controller.visibleNodes, contains("c1"));
      },
    );
  });

  group("remove and re-add across intermediate animation states", () {
    testWidgets(
      "remove during expand then re-add and re-expand preserves the child's current extent",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
        controller.setFullExtent("a", 48);
        controller.setFullExtent("a1", 48);

        controller.expand(key: "a");
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 100));

        expect(controller.getCurrentExtent("a1"), greaterThan(0.0));
        expect(controller.getCurrentExtent("a1"), lessThan(48.0));

        controller.remove(key: "a");
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 80));

        final extentBeforeReadd = controller.getCurrentExtent("a1");
        expect(extentBeforeReadd, greaterThan(0.0));
        expect(extentBeforeReadd, lessThan(48.0));

        controller.insertRoot(TreeNode(key: "a", data: "A"));
        controller.expand(key: "a");

        final extentAfterReexpand = controller.getCurrentExtent("a1");
        expect(
          extentAfterReexpand,
          closeTo(extentBeforeReadd, 0.01),
          reason:
              "A child restored while its parent transitions from remove "
              "back to expand should resume from the current extent instead "
              "of skipping to a different size.",
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1000));
        expect(
          controller.hasActiveAnimations,
          isFalse,
          reason:
              "The remove -> re-add -> re-expand transition should settle "
              "cleanly instead of leaving orphaned animation state behind.",
        );
        expect(controller.visibleNodes, ["a", "a1"]);
        expect(controller.getCurrentExtent("a1"), 48.0);
      },
    );

    testWidgets(
      "remove during expandAll then re-add and expandAll preserves the child's current extent",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "a", data: "A")]);
        controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
        controller.setFullExtent("a", 48);
        controller.setFullExtent("a1", 48);

        controller.expandAll();
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 100));

        expect(controller.getCurrentExtent("a1"), greaterThan(0.0));
        expect(controller.getCurrentExtent("a1"), lessThan(48.0));

        controller.remove(key: "a");
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 80));

        final extentBeforeReadd = controller.getCurrentExtent("a1");
        expect(extentBeforeReadd, greaterThan(0.0));
        expect(extentBeforeReadd, lessThan(48.0));

        controller.insertRoot(TreeNode(key: "a", data: "A"));
        controller.expandAll();

        final extentAfterReexpand = controller.getCurrentExtent("a1");
        expect(
          extentAfterReexpand,
          closeTo(extentBeforeReadd, 0.01),
          reason:
              "A child restored while switching from remove back to "
              "expandAll should resume from the current extent instead of "
              "skipping to a different size.",
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1000));
        expect(
          controller.hasActiveAnimations,
          isFalse,
          reason:
              "The remove -> re-add -> expandAll transition should settle "
              "cleanly instead of leaving orphaned animation state behind.",
        );
        expect(controller.visibleNodes, ["a", "a1"]);
        expect(controller.getCurrentExtent("a1"), 48.0);
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════════
  // BUG REGRESSION: moveNode silently ignores explicit index when the node is
  // already under the target parent.
  //
  // `moveNode(key, parent, index: N)` short-circuits when `oldParent == parent`
  // and never applies the requested position. Callers expecting "move to
  // index N within my current parent" silently get a no-op.
  // ════════════════════════════════════════════════════════════════════════════

  group("moveNode same-parent reorder", () {
    testWidgets("reorders within current parent when explicit index given", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "root", data: "R")]);
      controller.setChildren("root", [
        TreeNode(key: "c1", data: "C1"),
        TreeNode(key: "c2", data: "C2"),
        TreeNode(key: "c3", data: "C3"),
      ]);
      controller.expand(key: "root");
      expect(controller.visibleNodes, ["root", "c1", "c2", "c3"]);

      // Move c3 to index 0 within its existing parent.
      controller.moveNode("c3", "root", index: 0);

      expect(
        controller.visibleNodes,
        ["root", "c3", "c1", "c2"],
        reason: "moveNode with explicit index must honor it even when the "
            "old and new parent are the same",
      );
    });

    testWidgets("reorders within roots when explicit index given", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ]);

      // Move 'c' (currently a root) to root index 0.
      controller.moveNode("c", null, index: 0);

      expect(
        controller.visibleNodes,
        ["c", "a", "b"],
        reason: "moveNode into roots with explicit index must reorder",
      );
    });

    testWidgets("no-op fast path still applies when index is null", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);
      controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
      final gen = controller.structureGeneration;

      // No index → preserve the existing "already there" no-op semantics.
      controller.moveNode("a1", "a");
      expect(controller.structureGeneration, gen);
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // BUG REGRESSION: reorderRoots / reorderChildren use debug-only asserts for
  // user-API input validation. In release builds the asserts are stripped, so
  // invalid `orderedKeys` silently corrupt internal state (missing children,
  // duplicated entries, dropped subtrees). Validation must throw an
  // ArgumentError in all build modes.
  // ════════════════════════════════════════════════════════════════════════════

  group("reorder release-mode validation", () {
    testWidgets("reorderRoots throws ArgumentError on duplicate keys", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);

      expect(
        () => controller.reorderRoots(["a", "a"]),
        throwsArgumentError,
      );
    });

    testWidgets("reorderRoots throws ArgumentError on missing key", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);

      // Missing 'b'.
      expect(() => controller.reorderRoots(["a"]), throwsArgumentError);
    });

    testWidgets("reorderRoots throws ArgumentError on unknown key", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "a", data: "A")]);

      expect(() => controller.reorderRoots(["x"]), throwsArgumentError);
    });

    testWidgets(
      "reorderChildren throws ArgumentError on unknown parent",
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: "root", data: "R")]);

        expect(
          () => controller.reorderChildren("missing", const []),
          throwsArgumentError,
        );
      },
    );

    testWidgets("reorderChildren throws ArgumentError on duplicate keys", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "root", data: "R")]);
      controller.setChildren("root", [
        TreeNode(key: "c1", data: "C1"),
        TreeNode(key: "c2", data: "C2"),
      ]);

      expect(
        () => controller.reorderChildren("root", ["c1", "c1"]),
        throwsArgumentError,
      );
    });

    testWidgets("reorderChildren throws ArgumentError on missing key", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "root", data: "R")]);
      controller.setChildren("root", [
        TreeNode(key: "c1", data: "C1"),
        TreeNode(key: "c2", data: "C2"),
      ]);

      expect(
        () => controller.reorderChildren("root", ["c1"]),
        throwsArgumentError,
      );
    });

    testWidgets("reorderChildren throws ArgumentError on unknown key", (
      tester,
    ) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: "root", data: "R")]);
      controller.setChildren("root", [TreeNode(key: "c1", data: "C1")]);

      expect(
        () => controller.reorderChildren("root", ["x"]),
        throwsArgumentError,
      );
    });
  });

  group("computeFirstAnimatingVisibleIndex", () {
    testWidgets("returns visibleNodeCount when no animations are active",
        (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);

      expect(controller.hasActiveAnimations, isFalse);
      expect(controller.computeFirstAnimatingVisibleIndex(),
          controller.visibleNodeCount);
    });

    testWidgets("returns smallest visible index among active operation groups",
        (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ]);
      controller.setChildren("b", [
        TreeNode(key: "b1", data: "B1"),
        TreeNode(key: "b2", data: "B2"),
      ]);

      // Expand b — triggers an operation group with b1, b2 as members.
      // visible order mid-anim: [a, b, b1, b2, c], animating members = {b1, b2}.
      controller.expand(key: "b");
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.hasActiveAnimations, isTrue);

      final idx = controller.computeFirstAnimatingVisibleIndex();
      expect(idx, 2,
          reason: "b1 at index 2 is the first animating visible node");

      await tester.pumpAndSettle();
    });

    testWidgets(
        "returns visibleNodeCount when animating members are not in visible order",
        (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
      ]);
      controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);

      // Expanding then immediately removing the parent leaves the group
      // momentarily populated but the members no longer in _visibleOrder.
      controller.expand(key: "a");
      controller.remove(key: "a");
      await tester.pump(const Duration(milliseconds: 10));

      final idx = controller.computeFirstAnimatingVisibleIndex();
      // Any animating member still in visible order counts; any not in
      // visible order is ignored. The result must always be ≤ visibleNodeCount.
      expect(idx, lessThanOrEqualTo(controller.visibleNodeCount));

      await tester.pumpAndSettle();
    });

    testWidgets("scales with smallest of multiple concurrent groups",
        (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: const Duration(milliseconds: 300),
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        TreeNode(key: "a", data: "A"),
        TreeNode(key: "b", data: "B"),
        TreeNode(key: "c", data: "C"),
      ]);
      controller.setChildren("a", [TreeNode(key: "a1", data: "A1")]);
      controller.setChildren("c", [TreeNode(key: "c1", data: "C1")]);

      controller.expand(key: "c");
      controller.expand(key: "a");
      await tester.pump(const Duration(milliseconds: 50));

      // After both expands, visible: [a, a1, b, c, c1]. Two groups active.
      // Smallest animating visible index is a1 (index 1).
      final idx = controller.computeFirstAnimatingVisibleIndex();
      expect(idx, 1);

      await tester.pumpAndSettle();
    });
  });

  group('scroll-to-key', () {
    testWidgets('scrollOffsetOf returns null for unregistered key',
        (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: 'a', data: 'A')]);

      expect(controller.scrollOffsetOf('ghost'), isNull);
    });

    testWidgets('scrollOffsetOf returns null for key under collapsed ancestor',
        (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: 'a', data: 'A')]);
      controller.setChildren('a', [TreeNode(key: 'a1', data: 'A1')]);

      // 'a' is collapsed, so 'a1' is not in the visible order.
      expect(controller.scrollOffsetOf('a1'), isNull);
    });

    testWidgets('scrollOffsetOf sums default extents when nothing measured',
        (tester) async {
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

      // No layout has run, so _fullExtents is empty — falls back to
      // defaultExtent (48.0) per row.
      expect(controller.scrollOffsetOf('a'), 0.0);
      expect(controller.scrollOffsetOf('b'), 48.0);
      expect(controller.scrollOffsetOf('c'), 96.0);
    });

    testWidgets('scrollOffsetOf honors extentEstimator override',
        (tester) async {
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

      double estimator(String k) => k == 'b' ? 100.0 : 20.0;

      // a at 0, b at 20 (a-estimated=20), c at 120 (a-estimated=20 + b-estimated=100)
      expect(controller.scrollOffsetOf('c', extentEstimator: estimator), 120.0);
    });

    testWidgets('scrollOffsetOf prefers measured extent over estimator',
        (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: 'a', data: 'A'),
        TreeNode(key: 'b', data: 'B'),
      ]);

      // Simulate render-pass measurement: a = 72px.
      controller.setFullExtent('a', 72.0);

      // Estimator returns 999 for any key, but 'a' is measured at 72.
      double estimator(String k) => 999.0;

      expect(controller.scrollOffsetOf('b', extentEstimator: estimator), 72.0);
    });

    testWidgets('extentOf fallback chain: measured → estimator → default',
        (tester) async {
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
      controller.setFullExtent('a', 60.0);

      double estimator(String k) => k == 'b' ? 40.0 : -1.0;

      // Measured wins.
      expect(controller.extentOf('a', extentEstimator: estimator), 60.0);
      // Estimator fills in when no measurement.
      expect(controller.extentOf('b', extentEstimator: estimator), 40.0);
      // Default when neither.
      expect(controller.extentOf('c'), TreeController.defaultExtent);
    });

    testWidgets(
        'ensureAncestorsExpanded expands chain root-first, returns count',
        (tester) async {
      controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([TreeNode(key: 'a', data: 'A')]);
      controller.setChildren('a', [TreeNode(key: 'a1', data: 'A1')]);
      controller.setChildren('a1', [TreeNode(key: 'a1x', data: 'A1X')]);

      // Nothing expanded yet: 'a1x' is not visible.
      expect(controller.getVisibleIndex('a1x'), -1);

      final expandedCount = controller.ensureAncestorsExpanded('a1x');

      expect(expandedCount, 2); // 'a' and 'a1'
      expect(controller.isExpanded('a'), true);
      expect(controller.isExpanded('a1'), true);
      expect(controller.visibleNodes, ['a', 'a1', 'a1x']);
    });

    testWidgets('ensureAncestorsExpanded is a no-op for roots and already-open',
        (tester) async {
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
      controller.expand(key: 'a', animate: false);

      // Root: nothing to expand.
      expect(controller.ensureAncestorsExpanded('a'), 0);
      // Descendant of already-expanded parent: nothing to expand.
      expect(controller.ensureAncestorsExpanded('a1'), 0);
    });
  });

  group('ancestorsExpanded cache', () {
    // These tests exercise the cached _ancestorsExpandedByNid bit indirectly:
    // the "exits because ancestor still collapsed" decision in
    // _onOperationGroupStatusChange / _onBulkAnimationComplete used to do an
    // O(depth) walk; it now reads the cached bit. The cases below are the
    // ones most likely to regress if the cache gets out of sync with the
    // real expansion state.

    testWidgets(
      'collapse mid-expand: descendants vanish once animations settle',
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 300),
        );
        addTearDown(controller.dispose);

        // A → B → C, start collapsed.
        controller.setRoots([TreeNode(key: 'a', data: 'A')]);
        controller.setChildren('a', [TreeNode(key: 'b', data: 'B')]);
        controller.setChildren('b', [TreeNode(key: 'c', data: 'C')]);

        controller.expand(key: 'a');
        controller.expand(key: 'b');
        // Mid-animation, collapse the root — C's ancestor chain becomes
        // fully collapsed and it must disappear once animations settle.
        await tester.pump(const Duration(milliseconds: 50));
        controller.collapse(key: 'a');
        await tester.pumpAndSettle();

        expect(controller.visibleNodes, ['a']);
      },
    );

    testWidgets(
      'moveNode under a collapsed parent clears descendants ancestor bit',
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        addTearDown(controller.dispose);

        // A (expanded) with child A1.
        // B (collapsed) is a sibling root.
        controller.setRoots([
          TreeNode(key: 'a', data: 'A'),
          TreeNode(key: 'b', data: 'B'),
        ]);
        controller.setChildren('a', [TreeNode(key: 'a1', data: 'A1')]);
        controller.expand(key: 'a', animate: false);
        expect(controller.visibleNodes, ['a', 'a1', 'b']);

        // Move A1 under B (which is collapsed). A1 must disappear from
        // visible order, and a subsequent expand of B must show it.
        controller.moveNode('a1', 'b');
        expect(controller.visibleNodes, ['a', 'b']);

        controller.expand(key: 'b', animate: false);
        expect(controller.visibleNodes, ['a', 'b', 'a1']);
      },
    );

    testWidgets(
      'expandAll then collapseAll leaves the cache consistent for re-expand',
      (tester) async {
        controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        addTearDown(controller.dispose);

        // A 3-level tree with several branches.
        controller.setRoots([
          TreeNode(key: 'r1', data: 'R1'),
          TreeNode(key: 'r2', data: 'R2'),
        ]);
        controller.setChildren('r1', [
          TreeNode(key: 'r1a', data: 'R1A'),
          TreeNode(key: 'r1b', data: 'R1B'),
        ]);
        controller.setChildren('r1a', [TreeNode(key: 'r1a1', data: 'R1A1')]);
        controller.setChildren('r2', [TreeNode(key: 'r2a', data: 'R2A')]);

        controller.expandAll(animate: false);
        expect(controller.visibleNodes, [
          'r1', 'r1a', 'r1a1', 'r1b', 'r2', 'r2a',
        ]);

        controller.collapseAll(animate: false);
        expect(controller.visibleNodes, ['r1', 'r2']);

        // If the cache still thinks r1a's ancestors are expanded (stale),
        // a targeted expand of r1a would skip the "invisible-ancestor"
        // fast path and try to insert r1a1 at a missing visible index.
        controller.expand(key: 'r1a', animate: false);
        expect(controller.visibleNodes, ['r1', 'r2']);

        controller.expand(key: 'r1', animate: false);
        // Now r1a's ancestors are fully expanded and its own children appear.
        expect(controller.visibleNodes, [
          'r1', 'r1a', 'r1a1', 'r1b', 'r2',
        ]);
      },
    );
  });
}
