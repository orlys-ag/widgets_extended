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

void main() {
  testWidgets("mywork-style: re-add mid-exit of collapsed section", (
    tester,
  ) async {
    await tester.pumpWidget(
      const _Harness(sections: ["today", "overdue", "comingUp", "noDueDate"]),
    );
    await tester.pumpAndSettle();

    final controller = tester
        .state<_HarnessState>(find.byType(_Harness))
        ._controller!;

    // Collapse overdue before the filter sequence
    controller.collapse(key: "overdue", animate: false);
    await tester.pump();

    // Step 1: Filter to "today" → removes overdue (collapsed, no visible child).
    await tester.pumpWidget(const _Harness(sections: ["today"]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final overdueMid = controller.getCurrentExtent("overdue");
    // ignore: avoid_print
    print("Mid-exit overdue=$overdueMid (collapsed before remove)");
    expect(overdueMid, greaterThan(0));
    expect(overdueMid, lessThan(48));

    // Step 2: Filter to "overdue" → removes today, re-adds overdue.
    await tester.pumpWidget(const _Harness(sections: ["overdue"]));
    await tester.pump();

    final overdueAfter = controller.getCurrentExtent("overdue");
    // ignore: avoid_print
    print("After re-add overdue=$overdueAfter");

    expect(
      overdueAfter,
      closeTo(overdueMid, 2.0),
      reason: "overdue should resume from mid-exit, not jump to full",
    );
    expect(controller.isAnimating("overdue"), isTrue);

    // The child row should re-appear via expand animation after the
    // _expandParentsThatGainedChildren heuristic.
    await tester.pumpAndSettle();
    expect(controller.getCurrentExtent("overdue"), 48.0);
  });

  testWidgets("mywork-style: re-add mid-exit of section while another removes", (
    tester,
  ) async {
    await tester.pumpWidget(
      const _Harness(sections: ["today", "overdue", "comingUp", "noDueDate"]),
    );
    await tester.pumpAndSettle();

    final controller = tester
        .state<_HarnessState>(find.byType(_Harness))
        ._controller!;

    // Step 1: Filter to "today" → removes overdue, comingUp, noDueDate.
    await tester.pumpWidget(const _Harness(sections: ["today"]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final overdueMid = controller.getCurrentExtent("overdue");
    final o1Mid = controller.getCurrentExtent("overdue_1");
    // ignore: avoid_print
    print("Mid-exit overdue=$overdueMid overdue_1=$o1Mid");
    expect(overdueMid, greaterThan(0));
    expect(overdueMid, lessThan(48));

    // Step 2: Filter to "overdue" → removes today, re-adds overdue.
    await tester.pumpWidget(const _Harness(sections: ["overdue"]));
    await tester.pump();

    final overdueAfter = controller.getCurrentExtent("overdue");
    final o1After = controller.getCurrentExtent("overdue_1");
    // ignore: avoid_print
    print("After re-add overdue=$overdueAfter overdue_1=$o1After");

    expect(
      overdueAfter,
      closeTo(overdueMid, 2.0),
      reason:
          "overdue section should resume from mid-exit extent, not jump to full",
    );
    expect(
      o1After,
      closeTo(o1Mid, 2.0),
      reason: "overdue_1 should resume from mid-exit, not jump to full",
    );
    expect(controller.isAnimating("overdue"), isTrue);
    expect(controller.isAnimating("overdue_1"), isTrue);

    await tester.pumpAndSettle();
  });
}
