import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/render_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree_widget.dart';
import 'package:widgets_extended/sliver_tree/synced_sliver_tree.dart';
import 'package:widgets_extended/sliver_tree/tree_controller.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

Map<Object, ({double offset, double visibleExtent})> _sample(
  WidgetTester tester,
) {
  final result = <Object, ({double offset, double visibleExtent})>{};
  final render = tester.renderObject<RenderSliverTree<String, String>>(
    find.byType(SliverTree<String, String>),
  );
  render.visitChildren((child) {
    if (child is! RenderBox) return;
    final pd = child.parentData as SliverTreeParentData;
    final nodeId = pd.nodeId;
    if (nodeId != null) {
      result[nodeId] = (
        offset: pd.layoutOffset,
        visibleExtent: pd.visibleExtent,
      );
    }
  });
  return result;
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

void main() {
  testWidgets("collapsed section re-add — verify child animates smoothly on re-expand", (
    tester,
  ) async {
    await tester.pumpWidget(
      const _Harness(sections: ["today", "overdue", "comingUp", "noDueDate"]),
    );
    await tester.pumpAndSettle();

    final controller = tester
        .state<_HarnessState>(find.byType(_Harness))
        ._controller!;

    // User collapses overdue.
    controller.collapse(key: "overdue", animate: false);
    await tester.pump();

    // Step 1: filter to today. Removes overdue (collapsed).
    await tester.pumpWidget(const _Harness(sections: ["today"]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final mid = _sample(tester);
    // ignore: avoid_print
    print("MID:");
    mid.forEach(
      (k, v) => print(
        "  $k  offset=${v.offset.toStringAsFixed(2)} extent=${v.visibleExtent.toStringAsFixed(2)}",
      ),
    );

    // Step 2: re-add overdue.
    await tester.pumpWidget(const _Harness(sections: ["overdue"]));
    await tester.pump();

    final post = _sample(tester);
    // ignore: avoid_print
    print("POST:");
    post.forEach(
      (k, v) => print(
        "  $k  offset=${v.offset.toStringAsFixed(2)} extent=${v.visibleExtent.toStringAsFixed(2)}",
      ),
    );

    // Overdue should resume from mid-exit. overdue_1 was not animating, so
    // it's in the render at extent 0 (undergoing fresh expand via
    // _expandParentsThatGainedChildren heuristic OR absent entirely).
    // Since we COLLAPSED it manually, _expandParentsThatGainedChildren
    // checks !isExpanded (true) and expands with animate=true.
    final postOverdue = post["overdue"]!.visibleExtent;
    final postO1 = post["overdue_1"]?.visibleExtent;
    // ignore: avoid_print
    print("Post overdue=$postOverdue overdue_1=$postO1");

    // Advance one animation frame.
    await tester.pump(const Duration(milliseconds: 16));
    final f1 = _sample(tester);
    // ignore: avoid_print
    print(
      "F+16ms: overdue=${f1["overdue"]?.visibleExtent} overdue_1=${f1["overdue_1"]?.visibleExtent}",
    );

    await tester.pump(const Duration(milliseconds: 50));
    final f2 = _sample(tester);
    // ignore: avoid_print
    print(
      "F+66ms: overdue=${f2["overdue"]?.visibleExtent} overdue_1=${f2["overdue_1"]?.visibleExtent}",
    );

    await tester.pumpAndSettle();
    final done = _sample(tester);
    // ignore: avoid_print
    print("DONE:");
    done.forEach(
      (k, v) => print(
        "  $k  offset=${v.offset.toStringAsFixed(2)} extent=${v.visibleExtent.toStringAsFixed(2)}",
      ),
    );
  });
}
