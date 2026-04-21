import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/synced_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

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
    final roots = <TreeNode<String, String>>[
      for (final s in widget.sections) TreeNode(key: s, data: s),
    ];
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SyncedSliverTree<String, String>.nodes(
              roots: roots,
              childrenOf: (key) {
                if (key.endsWith("_1")) return const [];
                return [TreeNode(key: "${key}_1", data: "${key}_1")];
              },
              maxStickyDepth: 1,
              animationDuration: const Duration(milliseconds: 300),
              animationCurve: Curves.linear,
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
  const _AsyncLoadHarness({required this.childrenOfProvider});
  final List<TreeNode<String, String>> Function(String) childrenOfProvider;

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
            SyncedSliverTree<String, String>.nodes(
              roots: const [TreeNode(key: "parent", data: "parent")],
              childrenOf: widget.childrenOfProvider,
              animationDuration: const Duration(milliseconds: 300),
              animationCurve: Curves.linear,
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
      List<TreeNode<String, String>> providerFn(String key) {
        if (key == "parent") return const [];
        return const [];
      }

      await tester.pumpWidget(
        _AsyncLoadHarness(childrenOfProvider: providerFn),
      );
      await tester.pumpAndSettle();

      final controller = tester
          .state<_AsyncLoadHarnessState>(find.byType(_AsyncLoadHarness))
          ._controller!;

      expect(controller.hasChildren("parent"), isFalse);

      await tester.pumpWidget(
        _AsyncLoadHarness(
          childrenOfProvider: (key) {
            if (key == "parent") {
              return const [
                TreeNode(key: "c1", data: "c1"),
                TreeNode(key: "c2", data: "c2"),
              ];
            }
            return const [];
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.hasChildren("parent"), isTrue);
      expect(
        controller.isExpanded("parent"),
        isTrue,
        reason:
            "parent gained its first children via a later sync — the "
            "auto-expand heuristic must still fire for this async-load case",
      );
    },
  );
}
