/// Regression test for audit item 2.5: `SyncedSliverTree.didUpdateWidget`
/// must skip the whole re-diff when the mode input is identical to the
/// old widget's.
///
/// Uses STABLE top-level extractor references, complementing
/// `synced_noop_rebuild_lambda_test.dart`, which covers the inline-lambda
/// case that plan item T1 fixed. Both must skip: after T1 the gate
/// compares the collection only, so extractor identity is irrelevant in
/// either direction. Callers routinely pass the same collection instance
/// across ancestor rebuilds; without the identity fast path every no-op
/// rebuild paid two deep copies of the children-by-parent map, a full
/// desired-tree walk (calling `childrenOf` for every node), and a
/// per-parent diff — O(N) UI-thread work per frame for zero change.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Node {
  const _Node(this.id, {this.children = const <_Node>[]});

  final String id;
  final List<_Node> children;
}

class _Harness extends StatefulWidget {
  const _Harness({
    required this.roots,
    required this.childrenOf,
    required this.onController,
  });

  final List<_Node> roots;
  final List<_Node> Function(_Node item) childrenOf;
  final void Function(TreeController<String, _Node>) onController;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<String, _Node>.hierarchy(
              roots: widget.roots,
              keyOf: _keyOf,
              childrenOf: widget.childrenOf,
              animationStyle: const TreeAnimationStyle(
                expandCollapse: TreeAnimationSpec(
                  duration: Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                ),
              ),
              itemBuilder: (context, node) {
                widget.onController(node.controller);
                return SizedBox(height: 48, child: Text(node.key));
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _keyOf(_Node item) {
  return item.id;
}

void main() {
  testWidgets(
    "ancestor rebuild with identical mode inputs runs no diff at all",
    (tester) async {
      int childrenOfCalls = 0;
      final roots = <_Node>[
        const _Node("a", children: <_Node>[_Node("a1")]),
        const _Node("b"),
      ];
      List<_Node> childrenOf(_Node item) {
        childrenOfCalls++;
        return item.children;
      }

      TreeController<String, _Node>? controller;
      await tester.pumpWidget(
        _Harness(
          roots: roots,
          childrenOf: childrenOf,
          onController: (c) => controller = c,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        childrenOfCalls,
        greaterThan(0),
        reason: "sanity: the initial sync walks the desired tree",
      );

      final genBefore = controller!.structureGeneration;
      childrenOfCalls = 0;

      // Ancestor rebuild passing the SAME instances (same list, same
      // top-level function reference).
      tester.state<_HarnessState>(find.byType(_Harness)).rebuild();
      await tester.pump();

      expect(
        childrenOfCalls,
        0,
        reason:
            "identical mode inputs must skip the re-diff entirely — "
            "no desired-tree walk, no per-parent sync",
      );
      expect(
        controller!.structureGeneration,
        genBefore,
        reason: "no controller mutation may occur on a no-op rebuild",
      );
    },
  );

  testWidgets(
    "changed inputs still sync after a prior identity-skipped rebuild",
    (tester) async {
      final rootsV1 = <_Node>[const _Node("a")];
      final rootsV2 = <_Node>[const _Node("a"), const _Node("b")];
      List<_Node> childrenOf(_Node item) {
        return item.children;
      }

      TreeController<String, _Node>? controller;
      await tester.pumpWidget(
        _Harness(
          roots: rootsV1,
          childrenOf: childrenOf,
          onController: (c) => controller = c,
        ),
      );
      await tester.pumpAndSettle();

      // Identity-skipped rebuild.
      tester.state<_HarnessState>(find.byType(_Harness)).rebuild();
      await tester.pump();
      expect(controller!.visibleNodes, ["a"]);

      // A genuinely new list instance must diff and apply.
      await tester.pumpWidget(
        _Harness(
          roots: rootsV2,
          childrenOf: childrenOf,
          onController: (c) => controller = c,
        ),
      );
      await tester.pumpAndSettle();
      expect(controller!.visibleNodes, ["a", "b"]);
    },
  );
}
