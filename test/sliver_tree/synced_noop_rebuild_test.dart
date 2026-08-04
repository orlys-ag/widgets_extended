/// Regression test for audit item 2.5: `SyncedSliverTree.didUpdateWidget`
/// must skip the whole re-diff when the mode inputs are identical to the
/// old widget's. Callers routinely pass the same collection instance
/// across ancestor rebuilds; without the identity fast path every no-op
/// rebuild paid two deep copies of the children-by-parent map, a full
/// desired-tree walk (calling `childrenOf` for every node), and a
/// per-parent diff — O(N) UI-thread work per frame for zero change.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Harness extends StatefulWidget {
  const _Harness({
    required this.roots,
    required this.childrenOf,
    required this.onController,
  });

  final List<TreeNode<String, String>> roots;
  final List<TreeNode<String, String>> Function(String key) childrenOf;
  final void Function(TreeController<String, String>) onController;

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
            SyncedSliverTree<String, String>.nodes(
              roots: widget.roots,
              childrenOf: widget.childrenOf,
              animationStyle: const TreeAnimationStyle(expandCollapse: TreeAnimationSpec(duration: Duration(milliseconds: 300), curve: Curves.easeInOut)),
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

void main() {
  testWidgets(
    "ancestor rebuild with identical mode inputs runs no diff at all",
    (tester) async {
      int childrenOfCalls = 0;
      final roots = <TreeNode<String, String>>[
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ];
      List<TreeNode<String, String>> childrenOf(String key) {
        childrenOfCalls++;
        return key == "a"
            ? const [TreeNode(key: "a1", data: "A1")]
            : const <TreeNode<String, String>>[];
      }

      TreeController<String, String>? controller;
      await tester.pumpWidget(_Harness(
        roots: roots,
        childrenOf: childrenOf,
        onController: (c) => controller = c,
      ));
      await tester.pumpAndSettle();
      expect(childrenOfCalls, greaterThan(0),
          reason: "sanity: the initial sync walks the desired tree");

      final genBefore = controller!.structureGeneration;
      childrenOfCalls = 0;

      // Ancestor rebuild passing the SAME instances (same list, same
      // top-level function reference).
      tester.state<_HarnessState>(find.byType(_Harness)).rebuild();
      await tester.pump();

      expect(
        childrenOfCalls,
        0,
        reason: "identical mode inputs must skip the re-diff entirely — "
            "no desired-tree walk, no per-parent sync",
      );
      expect(controller!.structureGeneration, genBefore,
          reason: "no controller mutation may occur on a no-op rebuild");
    },
  );

  testWidgets(
    "changed inputs still sync after a prior identity-skipped rebuild",
    (tester) async {
      final rootsV1 = <TreeNode<String, String>>[
        const TreeNode(key: "a", data: "A"),
      ];
      final rootsV2 = <TreeNode<String, String>>[
        const TreeNode(key: "a", data: "A"),
        const TreeNode(key: "b", data: "B"),
      ];
      List<TreeNode<String, String>> childrenOf(String key) {
        return const <TreeNode<String, String>>[];
      }

      TreeController<String, String>? controller;
      await tester.pumpWidget(_Harness(
        roots: rootsV1,
        childrenOf: childrenOf,
        onController: (c) => controller = c,
      ));
      await tester.pumpAndSettle();

      // Identity-skipped rebuild.
      tester.state<_HarnessState>(find.byType(_Harness)).rebuild();
      await tester.pump();
      expect(controller!.visibleNodes, ["a"]);

      // A genuinely new list instance must diff and apply.
      await tester.pumpWidget(_Harness(
        roots: rootsV2,
        childrenOf: childrenOf,
        onController: (c) => controller = c,
      ));
      await tester.pumpAndSettle();
      expect(controller!.visibleNodes, ["a", "b"]);
    },
  );
}
