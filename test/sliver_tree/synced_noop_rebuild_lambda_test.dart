/// Regression test for plan item T1: the identity fast path in
/// `SyncedSliverTree.didUpdateWidget` must gate on the mode's COLLECTION
/// reference only.
///
/// The original gate also required `identical` FUNCTION props (`keyOf`,
/// `childrenOf`, `parentOf`). Inline lambdas, the dominant calling style
/// (`keyOf: (item) => item.id`), produce a new closure instance on every
/// build, so the gate missed and the hierarchy / flat modes re-ran the
/// full diff (snapshot construction, validation, whole-tree walk,
/// per-parent sync) on every ancestor rebuild: exactly the O(N)-per-frame
/// hazard the fast path exists to prevent.
///
/// The probes count invocations of the user-supplied extractors, which is
/// the only way to observe the wasted walk: `TreeSyncController`'s
/// exact-match early-outs mean a redundant diff produces no mutations and
/// no notifications, so counter- or notification-based pins are blind to
/// it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Node {
  const _Node(this.id, {this.children = const <_Node>[], this.parent});

  final String id;
  final List<_Node> children;
  final String? parent;
}

class _HierarchyHarness extends StatefulWidget {
  const _HierarchyHarness({
    required this.roots,
    required this.onKeyOf,
    required this.onChildrenOf,
  });

  final List<_Node> roots;
  final VoidCallback onKeyOf;
  final VoidCallback onChildrenOf;

  @override
  State<_HierarchyHarness> createState() {
    return _HierarchyHarnessState();
  }
}

class _HierarchyHarnessState extends State<_HierarchyHarness> {
  void rebuild() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<String, _Node>.hierarchy(
              roots: widget.roots,
              // Inline lambdas: a NEW closure instance on every build.
              // That is the calling style this test exists to protect.
              keyOf: (item) {
                widget.onKeyOf();
                return item.id;
              },
              childrenOf: (item) {
                widget.onChildrenOf();
                return item.children;
              },
              itemBuilder: (context, node) {
                return SizedBox(height: 48, child: Text(node.key));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FlatHarness extends StatefulWidget {
  const _FlatHarness({
    required this.items,
    required this.onKeyOf,
    required this.onParentOf,
  });

  final List<_Node> items;
  final VoidCallback onKeyOf;
  final VoidCallback onParentOf;

  @override
  State<_FlatHarness> createState() {
    return _FlatHarnessState();
  }
}

class _FlatHarnessState extends State<_FlatHarness> {
  void rebuild() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<String, _Node>.flat(
              items: widget.items,
              keyOf: (item) {
                widget.onKeyOf();
                return item.id;
              },
              parentOf: (item) {
                widget.onParentOf();
                return item.parent;
              },
              itemBuilder: (context, node) {
                return SizedBox(height: 48, child: Text(node.key));
              },
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    "hierarchy mode: ancestor rebuild with inline lambdas and an identical "
    "roots collection runs no diff",
    (tester) async {
      int keyOfCalls = 0;
      int childrenOfCalls = 0;
      final roots = <_Node>[
        const _Node("a", children: <_Node>[_Node("a1")]),
        const _Node("b"),
      ];

      await tester.pumpWidget(
        _HierarchyHarness(
          roots: roots,
          onKeyOf: () {
            keyOfCalls++;
          },
          onChildrenOf: () {
            childrenOfCalls++;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        keyOfCalls,
        greaterThan(0),
        reason: "sanity: the initial sync must walk the desired hierarchy",
      );
      expect(
        find.text("a1"),
        findsOneWidget,
        reason: "sanity: the nested child rendered, so the walk was real",
      );

      keyOfCalls = 0;
      childrenOfCalls = 0;

      tester
          .state<_HierarchyHarnessState>(find.byType(_HierarchyHarness))
          .rebuild();
      await tester.pump();

      expect(
        keyOfCalls,
        0,
        reason:
            "an identical roots collection must skip the re-diff even "
            "though the inline keyOf is a fresh closure instance",
      );
      expect(
        childrenOfCalls,
        0,
        reason:
            "an identical roots collection must skip the re-diff even "
            "though the inline childrenOf is a fresh closure instance",
      );
    },
  );

  testWidgets(
    "flat mode: ancestor rebuild with inline lambdas and an identical items "
    "collection runs no diff",
    (tester) async {
      int keyOfCalls = 0;
      int parentOfCalls = 0;
      final items = <_Node>[
        const _Node("a"),
        const _Node("a1", parent: "a"),
        const _Node("b"),
      ];

      await tester.pumpWidget(
        _FlatHarness(
          items: items,
          onKeyOf: () {
            keyOfCalls++;
          },
          onParentOf: () {
            parentOfCalls++;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        keyOfCalls,
        greaterThan(0),
        reason: "sanity: the initial sync must walk the desired item list",
      );
      expect(
        find.text("a1"),
        findsOneWidget,
        reason: "sanity: the child row rendered, so the walk was real",
      );

      keyOfCalls = 0;
      parentOfCalls = 0;

      tester.state<_FlatHarnessState>(find.byType(_FlatHarness)).rebuild();
      await tester.pump();

      expect(
        keyOfCalls,
        0,
        reason:
            "an identical items collection must skip the re-diff even "
            "though the inline keyOf is a fresh closure instance",
      );
      expect(
        parentOfCalls,
        0,
        reason:
            "an identical items collection must skip the re-diff even "
            "though the inline parentOf is a fresh closure instance",
      );
    },
  );

  testWidgets("hierarchy mode: a new roots instance still syncs after an "
      "identity-skipped rebuild", (tester) async {
    final rootsV1 = <_Node>[const _Node("a")];
    final rootsV2 = <_Node>[const _Node("a"), const _Node("b")];

    await tester.pumpWidget(
      _HierarchyHarness(roots: rootsV1, onKeyOf: () {}, onChildrenOf: () {}),
    );
    await tester.pumpAndSettle();
    expect(find.text("b"), findsNothing);

    // Identity-skipped rebuild.
    tester
        .state<_HierarchyHarnessState>(find.byType(_HierarchyHarness))
        .rebuild();
    await tester.pump();
    expect(find.text("b"), findsNothing);

    // A genuinely new collection instance must diff and apply.
    await tester.pumpWidget(
      _HierarchyHarness(roots: rootsV2, onKeyOf: () {}, onChildrenOf: () {}),
    );
    await tester.pumpAndSettle();
    expect(
      find.text("b"),
      findsOneWidget,
      reason: "a new collection instance is the signal that inputs changed",
    );
  });
}
