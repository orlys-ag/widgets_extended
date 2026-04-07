import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

// ════════════════════════════════════════════════════════════════════════════
// TEST HELPERS
// ════════════════════════════════════════════════════════════════════════════

/// Wraps a SliverTree in a minimal scrollable for widget tests.
Widget buildTestTree({
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
  // ══════════════════════════════════════════════════════════════════════════
  // PHASE 2: Rebuild propagation
  // ══════════════════════════════════════════════════════════════════════════

  group('Rebuild propagation', () {
    testWidgets(
      'visible rows update when parent state changes (new nodeBuilder)',
      (tester) async {
        await tester.pumpWidget(
          _RebuildTestHarness(onControllerCreated: (_) {}),
        );

        // Initial label should be visible.
        expect(find.text('A - version 0'), findsOneWidget);

        // Trigger a parent setState that changes the nodeBuilder closure.
        final state = tester.state<_RebuildTestHarnessState>(
          find.byType(_RebuildTestHarness),
        );
        state.bumpVersion();
        await tester.pump();

        // The row should reflect the new version without removing/recreating.
        expect(find.text('A - version 1'), findsOneWidget);
        expect(find.text('A - version 0'), findsNothing);
      },
    );

    testWidgets(
      'visible rows update when controller data changes via updateNode',
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: Duration.zero,
        );
        addTearDown(controller.dispose);

        controller.setRoots([TreeNode(key: 'a', data: 'Original')]);

        await tester.pumpWidget(
          buildTestTree(
            controller: controller,
            nodeBuilder: (context, key, depth) {
              final label = controller.getNodeData(key)?.data ?? '';
              return SizedBox(height: 48, child: Text(label));
            },
          ),
        );
        expect(find.text('Original'), findsOneWidget);

        controller.updateNode(TreeNode(key: 'a', data: 'Updated'));
        await tester.pump();

        expect(find.text('Updated'), findsOneWidget);
        expect(find.text('Original'), findsNothing);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // PHASE 3: Dynamic height
  // ══════════════════════════════════════════════════════════════════════════

  group('Dynamic height', () {
    testWidgets('rows can change height at the same width', (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationDuration: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.setRoots([
        TreeNode(key: 'a', data: 'short'),
        TreeNode(key: 'b', data: 'B'),
      ]);

      await tester.pumpWidget(_DynamicHeightHarness(controller: controller));
      await tester.pump();

      // Find the initial size of row 'a'.
      final finderA = find.byKey(const ValueKey('row-a'));
      expect(finderA, findsOneWidget);
      final initialSize = tester.getSize(finderA);

      // Change data to something that produces a taller widget.
      controller.updateNode(TreeNode(key: 'a', data: 'tall'));
      await tester.pump();

      final newSize = tester.getSize(finderA);
      expect(newSize.height, greaterThan(initialSize.height));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // PHASE 0: TreeMapView insertion order
  // ══════════════════════════════════════════════════════════════════════════

  group('TreeMapView insertion order', () {
    testWidgets('independent roots preserve source-map order', (tester) async {
      // SplayTreeMap keys are ordered by natural comparison (alphabetic).
      final data = SplayTreeMap<String, String>.from({
        'alpha': 'A',
        'beta': 'B',
        'gamma': 'G',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                TreeMapView<String, String>(
                  data: data,
                  parentOf: (key, value) => null,
                  nodeBuilder: (context, key, value, depth, controller) {
                    return SizedBox(height: 48, child: Text(key));
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify alphabetic order (SplayTreeMap's natural order).
      final alphaY = tester.getTopLeft(find.text('alpha')).dy;
      final betaY = tester.getTopLeft(find.text('beta')).dy;
      final gammaY = tester.getTopLeft(find.text('gamma')).dy;

      expect(alphaY, lessThan(betaY));
      expect(betaY, lessThan(gammaY));
    });

    testWidgets('retained entries with value changes update rendered content', (
      tester,
    ) async {
      final data1 = SplayTreeMap<String, String>.from({'a': 'Original'});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(slivers: [_TreeMapViewHarness(data: data1)]),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Original'), findsOneWidget);

      // Update with same key, different value.
      final data2 = SplayTreeMap<String, String>.from({'a': 'Changed'});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(slivers: [_TreeMapViewHarness(data: data2)]),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Changed'), findsOneWidget);
      expect(find.text('Original'), findsNothing);
    });

    testWidgets('retained child survives when old parent is removed', (
      tester,
    ) async {
      // Parent 'p' has child 'c', both visible (initiallyExpanded).
      final data1 = SplayTreeMap<String, String>.from({
        'c': 'Child',
        'p': 'Parent',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                TreeMapView<String, String>(
                  data: data1,
                  parentOf: (key, value) => key == 'c' ? 'p' : null,
                  nodeBuilder: (context, key, value, depth, controller) {
                    return SizedBox(height: 48, child: Text(value));
                  },
                  initiallyExpanded: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Parent'), findsOneWidget);
      expect(find.text('Child'), findsOneWidget);

      // Remove parent, keep child as root.
      final data2 = SplayTreeMap<String, String>.from({'c': 'Child'});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                TreeMapView<String, String>(
                  data: data2,
                  parentOf: (key, value) => null,
                  nodeBuilder: (context, key, value, depth, controller) {
                    return SizedBox(height: 48, child: Text(value));
                  },
                  initiallyExpanded: true,
                ),
              ],
            ),
          ),
        ),
      );
      // Let removal animation complete.
      await tester.pumpAndSettle();

      // Child must survive and be visible.
      expect(find.text('Child'), findsOneWidget);
      expect(find.text('Parent'), findsNothing);
    });

    testWidgets('retained child moved to different parent appears correctly', (
      tester,
    ) async {
      final data1 = SplayTreeMap<String, String>.from({
        'a': 'A',
        'b': 'B',
        'c': 'C',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                TreeMapView<String, String>(
                  data: data1,
                  parentOf: (key, value) => key == 'c' ? 'a' : null,
                  nodeBuilder: (context, key, value, depth, controller) {
                    return SizedBox(height: 48, child: Text(value));
                  },
                  initiallyExpanded: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('C'), findsOneWidget);

      // Move 'c' from parent 'a' to parent 'b'.
      final data2 = SplayTreeMap<String, String>.from({
        'a': 'A',
        'b': 'B',
        'c': 'C',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                TreeMapView<String, String>(
                  data: data2,
                  parentOf: (key, value) => key == 'c' ? 'b' : null,
                  nodeBuilder: (context, key, value, depth, controller) {
                    return SizedBox(height: 48, child: Text(value));
                  },
                  initiallyExpanded: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 'c' should still be visible under its new parent.
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets(
      'rescued-to-root nodes are reordered to match SplayTreeMap order',
      (tester) async {
        // 'p' is parent of 'a' and 'b'. All expanded.
        final data1 = SplayTreeMap<String, String>.from({
          'a': 'A',
          'b': 'B',
          'p': 'Parent',
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  TreeMapView<String, String>(
                    data: data1,
                    parentOf: (key, value) =>
                        key == 'a' || key == 'b' ? 'p' : null,
                    nodeBuilder: (context, key, value, depth, controller) {
                      return SizedBox(height: 48, child: Text(key));
                    },
                    initiallyExpanded: true,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        // Remove parent — 'a' and 'b' become roots.
        final data2 = SplayTreeMap<String, String>.from({'a': 'A', 'b': 'B'});

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  TreeMapView<String, String>(
                    data: data2,
                    parentOf: (key, value) => null,
                    nodeBuilder: (context, key, value, depth, controller) {
                      return SizedBox(height: 48, child: Text(key));
                    },
                    initiallyExpanded: true,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Both survive, and 'a' appears before 'b' (SplayTreeMap order).
        expect(find.text('a'), findsOneWidget);
        expect(find.text('b'), findsOneWidget);

        final aY = tester.getTopLeft(find.text('a')).dy;
        final bY = tester.getTopLeft(find.text('b')).dy;
        expect(aY, lessThan(bY));
      },
    );
  });
}

// ════════════════════════════════════════════════════════════════════════════
// TEST HARNESS WIDGETS
// ════════════════════════════════════════════════════════════════════════════

/// Harness that creates a SliverTree and lets tests trigger parent rebuilds
/// with a new nodeBuilder closure that includes a version counter.
class _RebuildTestHarness extends StatefulWidget {
  const _RebuildTestHarness({required this.onControllerCreated});
  final void Function(TreeController<String, String>) onControllerCreated;

  @override
  State<_RebuildTestHarness> createState() => _RebuildTestHarnessState();
}

class _RebuildTestHarnessState extends State<_RebuildTestHarness>
    with TickerProviderStateMixin {
  late final TreeController<String, String> _controller;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _controller = TreeController<String, String>(
      vsync: this,
      animationDuration: Duration.zero,
    );
    _controller.setRoots([TreeNode(key: 'a', data: 'A')]);
    widget.onControllerCreated(_controller);
  }

  void bumpVersion() {
    setState(() => _version++);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _version;
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: _controller,
              nodeBuilder: (context, key, depth) {
                final data = _controller.getNodeData(key)?.data ?? '';
                return SizedBox(height: 48, child: Text('$data - version $v'));
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Harness that changes row height based on controller data.
class _DynamicHeightHarness extends StatelessWidget {
  const _DynamicHeightHarness({required this.controller});
  final TreeController<String, String> controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverTree<String, String>(
              controller: controller,
              nodeBuilder: (context, key, depth) {
                final data = controller.getNodeData(key)?.data ?? '';
                final height = data == 'tall' ? 120.0 : 48.0;
                return SizedBox(
                  key: ValueKey('row-$key'),
                  height: height,
                  child: Text(data),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin harness around TreeMapView for retained-entry tests.
class _TreeMapViewHarness extends StatelessWidget {
  const _TreeMapViewHarness({required this.data});
  final Map<String, String> data;

  @override
  Widget build(BuildContext context) {
    return TreeMapView<String, String>(
      data: data,
      parentOf: (key, value) => null,
      nodeBuilder: (context, key, value, depth, controller) {
        return SizedBox(height: 48, child: Text(value));
      },
    );
  }
}
