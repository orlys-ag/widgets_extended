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
  // PHASE 0: SyncedSliverTree.flat insertion order
  // ══════════════════════════════════════════════════════════════════════════

  group("SyncedSliverTree.flat insertion order", () {
    testWidgets("independent roots preserve source-map order", (tester) async {
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
                buildFlatSyncedTree(
                  data: data,
                  parentOf: (key, value) => null,
                  itemBuilder: (context, node) {
                    return SizedBox(height: 48, child: Text(node.key));
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

    testWidgets("retained entries with value changes update rendered content", (
      tester,
    ) async {
      final data1 = SplayTreeMap<String, String>.from({'a': 'Original'});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(slivers: [buildFlatSyncedTree(data: data1)]),
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
            body: CustomScrollView(slivers: [buildFlatSyncedTree(data: data2)]),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Changed'), findsOneWidget);
      expect(find.text('Original'), findsNothing);
    });

    testWidgets("retained child survives when old parent is removed", (
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
                buildFlatSyncedTree(
                  data: data1,
                  parentOf: (key, value) => key == 'c' ? 'p' : null,
                  itemBuilder: (context, node) {
                    return SizedBox(height: 48, child: Text(node.item.value));
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
                buildFlatSyncedTree(
                  data: data2,
                  parentOf: (key, value) => null,
                  itemBuilder: (context, node) {
                    return SizedBox(height: 48, child: Text(node.item.value));
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

    testWidgets("retained child moved to different parent appears correctly", (
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
                buildFlatSyncedTree(
                  data: data1,
                  parentOf: (key, value) => key == 'c' ? 'a' : null,
                  itemBuilder: (context, node) {
                    return SizedBox(height: 48, child: Text(node.item.value));
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
                buildFlatSyncedTree(
                  data: data2,
                  parentOf: (key, value) => key == 'c' ? 'b' : null,
                  itemBuilder: (context, node) {
                    return SizedBox(height: 48, child: Text(node.item.value));
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
      "rescued-to-root nodes are reordered to match SplayTreeMap order",
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
                  buildFlatSyncedTree(
                    data: data1,
                    parentOf: (key, value) =>
                        key == 'a' || key == 'b' ? 'p' : null,
                    itemBuilder: (context, node) {
                      return SizedBox(height: 48, child: Text(node.key));
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
                  buildFlatSyncedTree(
                    data: data2,
                    parentOf: (key, value) => null,
                    itemBuilder: (context, node) {
                      return SizedBox(height: 48, child: Text(node.key));
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

  // ══════════════════════════════════════════════════════════════════════════
  // Hit testing during enter animation
  // ══════════════════════════════════════════════════════════════════════════

  group("hit testing on animating nodes", () {
    testWidgets(
      "tap in visible peek routes to the child's visible (bottom) slice",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        int topTaps = 0;
        int bottomTaps = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  SliverTree<String, String>(
                    controller: controller,
                    nodeBuilder: (context, key, depth) {
                      return SizedBox(
                        height: 100,
                        child: Column(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => topTaps++,
                                child: const SizedBox.expand(),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => bottomTaps++,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );

        // Start an animated root insert — 'n' animates from visibleExtent 0
        // to 100 over 400ms with a linear curve.
        controller.insertRoot(TreeNode(key: "n", data: "N"));
        // The standalone ticker's first tick only seeds _lastStandaloneTickTime
        // and produces no progress delta. A second pump actually advances the
        // animation: at ~20% progress the visibleExtent ≈ 20. Paint draws the
        // child shifted up by (100 - 20) = 80 and clipped to a 20px strip at
        // top of viewport — only the child's bottom slice (y ∈ [80, 100]) is
        // visible, entirely inside the bottom detector's half (y ∈ [50, 100]).
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 80));

        // Tap at screen y=10 (inside the ~20px visible strip).
        await tester.tapAt(const Offset(50, 10));
        await tester.pump();

        // Pre-fix: hit test passed local y=10 to the child, routing to the
        // top detector (y ∈ [0, 50]) — which is the clipped-away portion
        // the user did NOT visually touch. Post-fix: y=10 + (100-20)=90
        // routes to the bottom detector that is actually rendered at that
        // screen position.
        expect(bottomTaps, 1);
        expect(topTaps, 0);

        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      "applyPaintTransform mirrors paint's clip shift for animating nodes",
      (tester) async {
        final controller = TreeController<String, String>(
          vsync: tester,
          animationDuration: const Duration(milliseconds: 400),
          animationCurve: Curves.linear,
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return SizedBox(
                      key: ValueKey("row-$key"),
                      height: 100,
                      child: const SizedBox.expand(),
                    );
                  },
                ),
              ],
            ),
          ),
        );

        controller.insertRoot(TreeNode(key: "n", data: "N"));
        // Two pumps: first seeds the ticker, second actually advances by 80ms.
        // At ~20% progress the visibleExtent ≈ 20, so paint shifts the child
        // up by (100 - 20) = 80.
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 80));

        // localToGlobal walks applyPaintTransform. The child's (0,0) should
        // map to the screen position where paint actually draws the child's
        // top — ~80px above the viewport top. Before the fix this returned
        // the un-shifted paintOffset (viewport top), off by 80.
        final topLeft = tester.getTopLeft(find.byKey(const ValueKey("row-n")));
        expect(topLeft.dy, closeTo(-80, 2));

        await tester.pumpAndSettle();

        // After settle, no animation → no clip shift → localToGlobal reports
        // the natural offset.
        final settledTopLeft =
            tester.getTopLeft(find.byKey(const ValueKey("row-n")));
        expect(settledTopLeft.dy, closeTo(0, 0.5));
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

Widget buildFlatSyncedTree({
  required Map<String, String> data,
  String? Function(String key, String value)? parentOf,
  Widget Function(
    BuildContext context,
    TreeItemView<String, MapEntry<String, String>> node,
  )?
  itemBuilder,
  bool initiallyExpanded = false,
}) {
  final resolveParentOf =
      parentOf ??
      (String key, String value) {
        return null;
      };

  return SyncedSliverTree<String, MapEntry<String, String>>.flat(
    items: data.entries,
    keyOf: (entry) {
      return entry.key;
    },
    parentOf: (entry) {
      return resolveParentOf(entry.key, entry.value);
    },
    initiallyExpanded: initiallyExpanded,
    animationDuration: Duration.zero,
    itemBuilder:
        itemBuilder ??
        (context, node) {
          return SizedBox(height: 48, child: Text(node.item.value));
        },
  );
}
