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
}
