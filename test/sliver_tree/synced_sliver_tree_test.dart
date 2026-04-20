import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

sealed class _WorkNode {
  const _WorkNode();
}

class _SectionNode extends _WorkNode {
  const _SectionNode({
    required this.id,
    required this.title,
    this.children = const <_WorkNode>[],
  });

  final String id;
  final String title;
  final List<_WorkNode> children;
}

class _ItemNode extends _WorkNode {
  const _ItemNode({required this.id, required this.label});

  final String id;
  final String label;
}

class _FlatItem {
  const _FlatItem({required this.id, required this.label, this.parentId});

  final String id;
  final String label;
  final String? parentId;
}

String _workKey(_WorkNode node) {
  return switch (node) {
    _SectionNode(:final id) => "section:$id",
    _ItemNode(:final id) => "item:$id",
  };
}

Iterable<_WorkNode> _workChildren(_WorkNode node) {
  return switch (node) {
    _SectionNode(:final children) => children,
    _ItemNode() => const <_WorkNode>[],
  };
}

String _workLabel(_WorkNode node) {
  return switch (node) {
    _SectionNode(:final title) => title,
    _ItemNode(:final label) => label,
  };
}

void main() {
  group("TreeSnapshot", () {
    test("fromHierarchy preserves deep nesting and validates reachability", () {
      const roots = <_WorkNode>[
        _SectionNode(
          id: "today",
          title: "Today",
          children: <_WorkNode>[
            _ItemNode(id: "a", label: "Alpha"),
            _SectionNode(
              id: "nested",
              title: "Nested",
              children: <_WorkNode>[_ItemNode(id: "b", label: "Beta")],
            ),
          ],
        ),
      ];

      final snapshot = TreeSnapshot<String, _WorkNode>.fromHierarchy(
        roots: roots,
        keyOf: _workKey,
        childrenOf: _workChildren,
      );

      expect(snapshot.roots, <String>["section:today"]);
      expect(snapshot.childrenByParent["section:today"], <String>[
        "item:a",
        "section:nested",
      ]);
      expect(snapshot.childrenByParent["section:nested"], <String>["item:b"]);
      expect(() {
        TreeSnapshot<String, String>(
          roots: <String>["root"],
          dataByKey: <String, String>{"root": "Root", "orphan": "Orphan"},
          childrenByParent: const <String, Iterable<String>>{},
        );
      }, throwsArgumentError);
    });
  });

  group("SyncedSliverTree.tree", () {
    testWidgets("renders a nested immutable tree", (tester) async {
      final tree = <SyncedTreeNode<String, String>>[
        SyncedTreeNode<String, String>(
          key: "root",
          data: "Root",
          children: <SyncedTreeNode<String, String>>[
            SyncedTreeNode<String, String>(key: "child", data: "Child"),
          ],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                SyncedSliverTree<String, String>(
                  tree: tree,
                  initiallyExpanded: true,
                  animationDuration: Duration.zero,
                  itemBuilder: (context, node) {
                    return SizedBox(
                      height: 48,
                      child: Text(
                        "${node.depth}|${node.parentKey}|${node.item}",
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text("0|null|Root"), findsOneWidget);
      expect(find.text("1|root|Child"), findsOneWidget);
    });

    testWidgets("throws on duplicate keys", (tester) async {
      final tree = <SyncedTreeNode<String, String>>[
        SyncedTreeNode<String, String>(
          key: "root",
          data: "Root",
          children: <SyncedTreeNode<String, String>>[
            SyncedTreeNode<String, String>(key: "dup", data: "Child A"),
            SyncedTreeNode<String, String>(key: "dup", data: "Child B"),
          ],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                SyncedSliverTree<String, String>(
                  tree: tree,
                  animationDuration: Duration.zero,
                  itemBuilder: (context, node) {
                    return const SizedBox(height: 48);
                  },
                ),
              ],
            ),
          ),
        ),
      );

      final exception = tester.takeException();
      expect(exception, isA<ArgumentError>());
      expect(
        exception.toString(),
        contains('duplicate child key "dup" under parent "root"'),
      );
    });

    testWidgets("throws when a child key is reused under multiple parents", (
      tester,
    ) async {
      final shared = SyncedTreeNode<String, String>(
        key: "shared",
        data: "Shared",
      );
      final tree = <SyncedTreeNode<String, String>>[
        SyncedTreeNode<String, String>(
          key: "left",
          data: "Left",
          children: <SyncedTreeNode<String, String>>[shared],
        ),
        SyncedTreeNode<String, String>(
          key: "right",
          data: "Right",
          children: <SyncedTreeNode<String, String>>[shared],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                SyncedSliverTree<String, String>(
                  tree: tree,
                  animationDuration: Duration.zero,
                  itemBuilder: (context, node) {
                    return const SizedBox(height: 48);
                  },
                ),
              ],
            ),
          ),
        ),
      );

      final exception = tester.takeException();
      expect(exception, isA<ArgumentError>());
      expect(
        exception.toString(),
        contains('encountered duplicate key "shared"'),
      );
    });

    testWidgets("watch rebuilds on expand and collapse", (tester) async {
      final tree = <SyncedTreeNode<String, String>>[
        SyncedTreeNode<String, String>(
          key: "root",
          data: "Root",
          children: <SyncedTreeNode<String, String>>[
            SyncedTreeNode<String, String>(key: "child", data: "Child"),
          ],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                SyncedSliverTree<String, String>(
                  tree: tree,
                  initiallyExpanded: false,
                  animationDuration: Duration.zero,
                  itemBuilder: (context, node) {
                    if (node.hasChildren) {
                      return node.watch(
                        builder: (context, currentNode) {
                          return GestureDetector(
                            onTap: () => currentNode.toggle(),
                            child: SizedBox(
                              height: 48,
                              child: Text(
                                "${currentNode.item}|${currentNode.isExpanded}",
                              ),
                            ),
                          );
                        },
                      );
                    }

                    return SizedBox(height: 48, child: Text(node.item));
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text("Root|false"), findsOneWidget);
      expect(find.text("Child"), findsNothing);

      await tester.tap(find.text("Root|false"));
      await tester.pump();

      expect(find.text("Root|true"), findsOneWidget);
      expect(find.text("Child"), findsOneWidget);
    });
  });

  group("SyncedSliverTree.nodes", () {
    testWidgets(
      "renders roots and lazy children without snapshot boilerplate",
      (tester) async {
        final roots = <TreeNode<String, String>>[
          const TreeNode<String, String>(key: "root", data: "Root"),
        ];
        final childrenByParent = <String, List<TreeNode<String, String>>>{
          "root": <TreeNode<String, String>>[
            const TreeNode<String, String>(key: "child", data: "Child"),
          ],
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: <Widget>[
                  SyncedSliverTree<String, String>.nodes(
                    roots: roots,
                    childrenOf: (key) =>
                        childrenByParent[key] ??
                        const <TreeNode<String, String>>[],
                    initiallyExpanded: true,
                    animationDuration: Duration.zero,
                    itemBuilder: (context, node) {
                      return SizedBox(
                        height: 48,
                        child: Text(
                          "${node.depth}|${node.parentKey}|${node.item}",
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text("0|null|Root"), findsOneWidget);
        expect(find.text("1|root|Child"), findsOneWidget);
      },
    );
  });

  group("SyncedSliverTree.hierarchy", () {
    testWidgets("supports heterogeneous trees without controller lookups", (
      tester,
    ) async {
      const roots = <_WorkNode>[
        _SectionNode(
          id: "today",
          title: "Today",
          children: <_WorkNode>[
            _ItemNode(id: "a", label: "Alpha"),
            _ItemNode(id: "b", label: "Beta"),
          ],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                SyncedSliverTree<String, _WorkNode>.hierarchy(
                  roots: roots,
                  keyOf: _workKey,
                  childrenOf: _workChildren,
                  initiallyExpanded: false,
                  animationDuration: Duration.zero,
                  itemBuilder: (context, node) {
                    return GestureDetector(
                      onTap: node.hasChildren ? node.toggle : null,
                      child: SizedBox(
                        height: 48,
                        child: Text(
                          "${node.depth}|${node.childCount}|"
                          "${_workLabel(node.item)}|${node.isExpanded}",
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text("0|2|Today|false"), findsOneWidget);
      expect(find.text("1|0|Alpha|false"), findsNothing);

      await tester.tap(find.text("0|2|Today|false"));
      await tester.pump();

      expect(find.text("0|2|Today|true"), findsOneWidget);
      expect(find.text("1|0|Alpha|false"), findsOneWidget);
      expect(find.text("1|0|Beta|false"), findsOneWidget);
    });
  });

  group("SyncedSliverTree.flat", () {
    testWidgets("reparents retained nodes and updates payloads", (
      tester,
    ) async {
      Widget buildTree(List<_FlatItem> items) {
        return MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                SyncedSliverTree<String, _FlatItem>.flat(
                  items: items,
                  keyOf: (item) {
                    return item.id;
                  },
                  parentOf: (item) {
                    return item.parentId;
                  },
                  initiallyExpanded: true,
                  animationDuration: Duration.zero,
                  itemBuilder: (context, node) {
                    return SizedBox(
                      height: 48,
                      child: Text(
                        "${node.depth}|${node.parentKey}|${node.item.label}",
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      }

      await tester.pumpWidget(
        buildTree(const <_FlatItem>[
          _FlatItem(id: "a", label: "Parent A"),
          _FlatItem(id: "b", label: "Parent B"),
          _FlatItem(id: "x", label: "Child X", parentId: "a"),
        ]),
      );
      await tester.pump();

      expect(find.text("1|a|Child X"), findsOneWidget);

      await tester.pumpWidget(
        buildTree(const <_FlatItem>[
          _FlatItem(id: "a", label: "Parent A"),
          _FlatItem(id: "b", label: "Parent B"),
          _FlatItem(id: "x", label: "Child X moved", parentId: "b"),
        ]),
      );
      await tester.pump();

      expect(find.text("1|b|Child X moved"), findsOneWidget);
      expect(find.text("1|a|Child X"), findsNothing);
    });
  });

  group("SyncedSliverTree.snapshot", () {
    testWidgets("renders a precomputed snapshot with rich node metadata", (
      tester,
    ) async {
      final snapshot = TreeSnapshot<String, String>(
        roots: const <String>["root"],
        dataByKey: const <String, String>{"root": "Root", "child": "Child"},
        childrenByParent: const <String, Iterable<String>>{
          "root": <String>["child"],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                SyncedSliverTree<String, String>.snapshot(
                  snapshot: snapshot,
                  initiallyExpanded: true,
                  animationDuration: Duration.zero,
                  itemBuilder: (context, node) {
                    return SizedBox(
                      height: 48,
                      child: Text(
                        "${node.depth}|${node.parentKey}|${node.item}",
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text("0|null|Root"), findsOneWidget);
      expect(find.text("1|root|Child"), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // preserveExpansion runtime flip: didUpdateWidget must detect a change to
  // the prop, dispose the old sync controller, and reinitialise tracking
  // from the current tree. The first sync after the flip must diff against
  // fresh tracking, not a stale snapshot — otherwise nodes get double-
  // removed or ghosted.
  // ══════════════════════════════════════════════════════════════════════════

  group("preserveExpansion runtime flip", () {
    testWidgets(
      "flipping preserveExpansion mid-lifetime keeps tree state intact",
      (tester) async {
        const items = <_FlatItem>[
          _FlatItem(id: "a", label: "A"),
          _FlatItem(id: "b", label: "B"),
          _FlatItem(id: "a.1", label: "A.1", parentId: "a"),
          _FlatItem(id: "a.2", label: "A.2", parentId: "a"),
        ];

        await tester.pumpWidget(
          _PreserveExpansionFlipHarness(
            items: items,
            preserveExpansion: true,
          ),
        );
        await tester.pump();

        // Baseline: all four rows visible (initiallyExpanded=true).
        expect(find.text("A"), findsOneWidget);
        expect(find.text("A.1"), findsOneWidget);
        expect(find.text("A.2"), findsOneWidget);
        expect(find.text("B"), findsOneWidget);

        // Flip preserveExpansion at runtime. The widget swaps its sync
        // controller in didUpdateWidget.
        await tester.pumpWidget(
          _PreserveExpansionFlipHarness(
            items: items,
            preserveExpansion: false,
          ),
        );
        await tester.pump();

        // Tree unchanged — all four rows still visible, in order. If the
        // new sync controller diffed against stale tracking, 'A.1' or 'A.2'
        // might have been re-inserted as duplicates or dropped entirely.
        expect(find.text("A"), findsOneWidget);
        expect(find.text("A.1"), findsOneWidget);
        expect(find.text("A.2"), findsOneWidget);
        expect(find.text("B"), findsOneWidget);

        // A subsequent data change (remove a child) must apply cleanly
        // against the freshly-initialised tracking state.
        const reduced = <_FlatItem>[
          _FlatItem(id: "a", label: "A"),
          _FlatItem(id: "b", label: "B"),
          _FlatItem(id: "a.1", label: "A.1", parentId: "a"),
        ];
        await tester.pumpWidget(
          _PreserveExpansionFlipHarness(
            items: reduced,
            preserveExpansion: false,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text("A.1"), findsOneWidget);
        expect(find.text("A.2"), findsNothing);
        expect(find.text("A"), findsOneWidget);
        expect(find.text("B"), findsOneWidget);
      },
    );

    testWidgets(
      "flipping preserveExpansion to false drops memoized expansion",
      (tester) async {
        // preserveExpansion=true remembers expansion across remove/re-add.
        // Flipping to false mid-lifetime must stop honouring that memory —
        // the fresh sync controller has an empty memory map, so a re-added
        // node that was expanded before removal must come back collapsed.
        const fullTree = <_FlatItem>[
          _FlatItem(id: "a", label: "A"),
          _FlatItem(id: "a.1", label: "A.1", parentId: "a"),
          _FlatItem(id: "other", label: "Other"),
        ];
        // "Parent gone" state — removes 'a' entirely so the controller
        // purges its expansion state. Only the memoization inside
        // TreeSyncController can bring it back on re-add.
        const parentGone = <_FlatItem>[
          _FlatItem(id: "other", label: "Other"),
        ];

        await tester.pumpWidget(
          _PreserveExpansionFlipHarness(
            items: fullTree,
            preserveExpansion: true,
            initiallyExpanded: false,
          ),
        );
        await tester.pump();

        final harness = tester.state<_PreserveExpansionFlipState>(
          find.byType(_PreserveExpansionFlipHarness),
        );
        harness.treeController.expand(key: "a", animate: false);
        await tester.pump();
        expect(find.text("A.1"), findsOneWidget);

        // Remove 'a' (and its subtree) while preserveExpansion=true.
        // Memory stores a→true.
        await tester.pumpWidget(
          _PreserveExpansionFlipHarness(
            items: parentGone,
            preserveExpansion: true,
            initiallyExpanded: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text("A"), findsNothing);
        expect(find.text("A.1"), findsNothing);

        // Flip to preserveExpansion=false. The old sync controller (with
        // its memory map) is disposed; a fresh one is created and
        // initialized against the current tree (no 'a' anywhere).
        await tester.pumpWidget(
          _PreserveExpansionFlipHarness(
            items: parentGone,
            preserveExpansion: false,
            initiallyExpanded: false,
          ),
        );
        await tester.pump();

        // Re-add 'a' and 'a.1'. With preserveExpansion=false and a fresh
        // memory, 'a' must be inserted collapsed by default.
        await tester.pumpWidget(
          _PreserveExpansionFlipHarness(
            items: fullTree,
            preserveExpansion: false,
            initiallyExpanded: false,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text("A"), findsOneWidget);
        expect(
          find.text("A.1"),
          findsNothing,
          reason: "expansion memory leaked across preserveExpansion flip",
        );
      },
    );
  });

  group("mid-animation filter toggles", () {
    testWidgets(
      "re-adding a filtered subtree reverses from its current extent",
      (tester) async {
        const fullTree = <_FlatItem>[
          _FlatItem(id: "today", label: "Today"),
          _FlatItem(id: "overdue", label: "Overdue"),
          _FlatItem(id: "t1", label: "Task 1", parentId: "today"),
          _FlatItem(id: "o1", label: "Task 2", parentId: "overdue"),
        ];
        const filteredTree = <_FlatItem>[
          _FlatItem(id: "today", label: "Today"),
          _FlatItem(id: "t1", label: "Task 1", parentId: "today"),
        ];

        await tester.pumpWidget(
          _MidAnimationFilterHarness(items: fullTree),
        );
        await tester.pump();

        final harness = tester.state<_MidAnimationFilterHarnessState>(
          find.byType(_MidAnimationFilterHarness),
        );
        final controller = harness.treeController;

        expect(controller.getCurrentExtent("o1"), closeTo(48.0, 0.01));

        await tester.pumpWidget(
          _MidAnimationFilterHarness(items: filteredTree),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        final extentDuringRemoval = controller.getCurrentExtent("o1");
        expect(extentDuringRemoval, greaterThan(0.0));
        expect(extentDuringRemoval, lessThan(48.0));

        await tester.pumpWidget(
          _MidAnimationFilterHarness(items: fullTree),
        );
        await tester.pump();

        final extentAfterReadd = controller.getCurrentExtent("o1");
        expect(
          extentAfterReadd,
          closeTo(extentDuringRemoval, 0.01),
          reason:
              "A subtree restored mid-exit should reverse from its current "
              "measured extent instead of snapping closed and restarting.",
        );

        await tester.pumpAndSettle();
        expect(find.text("Today"), findsOneWidget);
        expect(find.text("Overdue"), findsOneWidget);
        expect(find.text("Task 1"), findsOneWidget);
        expect(find.text("Task 2"), findsOneWidget);
      },
    );
  });
}

// ════════════════════════════════════════════════════════════════════════════
// HARNESS FOR preserveExpansion FLIP
// ════════════════════════════════════════════════════════════════════════════

class _PreserveExpansionFlipHarness extends StatefulWidget {
  const _PreserveExpansionFlipHarness({
    required this.items,
    required this.preserveExpansion,
    this.initiallyExpanded = true,
  });

  final List<_FlatItem> items;
  final bool preserveExpansion;
  final bool initiallyExpanded;

  @override
  State<_PreserveExpansionFlipHarness> createState() =>
      _PreserveExpansionFlipState();
}

class _PreserveExpansionFlipState
    extends State<_PreserveExpansionFlipHarness> {
  TreeController<String, _FlatItem>? _capturedController;

  TreeController<String, _FlatItem> get treeController {
    return _capturedController!;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: <Widget>[
            SyncedSliverTree<String, _FlatItem>.flat(
              items: widget.items,
              keyOf: (item) {
                return item.id;
              },
              parentOf: (item) {
                return item.parentId;
              },
              preserveExpansion: widget.preserveExpansion,
              initiallyExpanded: widget.initiallyExpanded,
              animationDuration: Duration.zero,
              itemBuilder: (context, node) {
                _capturedController = node.controller;
                return SizedBox(height: 48, child: Text(node.item.label));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MidAnimationFilterHarness extends StatefulWidget {
  const _MidAnimationFilterHarness({required this.items});

  final List<_FlatItem> items;

  @override
  State<_MidAnimationFilterHarness> createState() =>
      _MidAnimationFilterHarnessState();
}

class _MidAnimationFilterHarnessState
    extends State<_MidAnimationFilterHarness> {
  TreeController<String, _FlatItem>? _capturedController;

  TreeController<String, _FlatItem> get treeController {
    return _capturedController!;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: <Widget>[
            SyncedSliverTree<String, _FlatItem>.flat(
              items: widget.items,
              keyOf: (item) {
                return item.id;
              },
              parentOf: (item) {
                return item.parentId;
              },
              initiallyExpanded: true,
              animationDuration: const Duration(milliseconds: 300),
              itemBuilder: (context, node) {
                _capturedController = node.controller;
                return SizedBox(height: 48, child: Text(node.item.label));
              },
            ),
          ],
        ),
      ),
    );
  }
}
