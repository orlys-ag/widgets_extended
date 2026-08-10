import 'package:widgets_extended/sliver_tree/animation_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/synced_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/synced_tree_node.dart';
import 'tree_input_helpers.dart';

/// Section list to tree input: each section owns one child, `${section}_1`.
/// Rebuilt per build so a changed section list re-syncs, matching the
/// per-build roots list this fixture used before.
List<SyncedTreeNode<String, String>> _treeFor(List<String> sections) {
  return treeFrom(
    roots: sections,
    dataByKey: <String, String>{
      for (final s in sections) ...<String, String>{s: s, "${s}_1": "${s}_1"},
    },
    childrenByParent: <String, List<String>>{
      for (final s in sections) s: <String>["${s}_1"],
    },
  );
}

class _Harness extends StatefulWidget {
  const _Harness({required this.sections});
  final List<String> sections;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  TreeController<String, String>? _controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<String, String>(
              tree: _treeFor(widget.sections),
              maxStickyDepth: 1,
              animationStyle: const TreeAnimationStyle(
                expandCollapse: TreeAnimationSpec(
                  duration: Duration(milliseconds: 300),
                  curve: Curves.linear,
                ),
              ),
              itemBuilder: (context, node) {
                _controller ??= node.controller;
                return SizedBox(
                  key: ValueKey(node.key),
                  height: 48,
                  child: Text(node.key),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AsyncLoadHarness extends StatefulWidget {
  const _AsyncLoadHarness({required this.childKeys});

  /// Children of "parent", empty until the simulated load resolves.
  final List<String> childKeys;

  @override
  State<_AsyncLoadHarness> createState() => _AsyncLoadHarnessState();
}

class _AsyncLoadHarnessState extends State<_AsyncLoadHarness> {
  TreeController<String, String>? _controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<String, String>(
              tree: treeFrom(
                roots: const ["parent"],
                dataByKey: <String, String>{
                  "parent": "parent",
                  for (final k in widget.childKeys) k: k,
                },
                childrenByParent: widget.childKeys.isEmpty
                    ? const <String, List<String>>{}
                    : <String, List<String>>{"parent": widget.childKeys},
              ),
              animationStyle: const TreeAnimationStyle(
                expandCollapse: TreeAnimationSpec(
                  duration: Duration(milliseconds: 300),
                  curve: Curves.linear,
                ),
              ),
              itemBuilder: (context, node) {
                _controller ??= node.controller;
                return SizedBox(
                  key: ValueKey(node.key),
                  height: 48,
                  child: Text(node.key),
                );
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
    "user-collapsed section stays collapsed after filter-out and filter-back-in",
    (tester) async {
      await tester.pumpWidget(
        const _Harness(sections: ["today", "overdue", "comingUp", "noDueDate"]),
      );
      await tester.pumpAndSettle();

      final controller = tester
          .state<_HarnessState>(find.byType(_Harness))
          ._controller!;

      controller.collapse(key: "overdue", animate: false);
      await tester.pump();
      expect(controller.isExpanded("overdue"), isFalse);

      await tester.pumpWidget(const _Harness(sections: ["today"]));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const _Harness(sections: ["overdue"]));
      await tester.pumpAndSettle();

      expect(
        controller.isExpanded("overdue"),
        isFalse,
        reason:
            "overdue was user-collapsed before being filtered out; "
            "on re-add it must stay collapsed",
      );
    },
  );

  testWidgets(
    "parent that gains its first children (async-load) still auto-expands",
    (tester) async {
      await tester.pumpWidget(const _AsyncLoadHarness(childKeys: <String>[]));
      await tester.pumpAndSettle();

      final controller = tester
          .state<_AsyncLoadHarnessState>(find.byType(_AsyncLoadHarness))
          ._controller!;

      expect(controller.hasChildren("parent"), isFalse);

      await tester.pumpWidget(
        const _AsyncLoadHarness(childKeys: <String>["c1", "c2"]),
      );
      await tester.pumpAndSettle();

      expect(controller.hasChildren("parent"), isTrue);
      expect(
        controller.isExpanded("parent"),
        isTrue,
        reason:
            "parent gained its first children via a later sync: the "
            "auto-expand heuristic must still fire for this async-load case",
      );
    },
  );
}
