import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Repro test for M16: a cross-depth [TreeController.moveNode] must dirty
/// the STRUCTURAL moved subtree, not only the expansion-gated one. A row
/// collapsed earlier in the same handler is still mounted (the element's
/// removeChild is a no-op and eviction is post-frame), and createChild
/// never rebuilds a mounted row that is not dirty, so an expansion-gated
/// affected set leaves that row rendering its pre-move depth.
class _LifecycleRow extends StatefulWidget {
  const _LifecycleRow({required this.label, required this.onDispose});

  final String label;
  final VoidCallback onDispose;

  @override
  State<_LifecycleRow> createState() => _LifecycleRowState();
}

class _LifecycleRowState extends State<_LifecycleRow> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 48, child: Text(widget.label));
  }
}

void main() {
  testWidgets(
    "collapse then cross-depth move in one handler refreshes the hidden row",
    (tester) async {
      final controller = TreeController<String, String>(
        vsync: tester,
        animationStyle: TreeAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.setRoots([
        const TreeNode(key: "P", data: "P"),
        const TreeNode(key: "Q", data: "Q"),
      ]);
      controller.setChildren("P", [const TreeNode(key: "C", data: "C")]);
      controller.expand(key: "P");

      final disposedKeys = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: controller,
                  nodeBuilder: (context, key, depth) {
                    return _LifecycleRow(
                      label: "$key@$depth",
                      onDispose: () => disposedKeys.add(key),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        find.text("P@0"),
        findsOneWidget,
        reason: "setup sanity: P renders at depth 0",
      );
      expect(
        find.text("C@1"),
        findsOneWidget,
        reason: "setup sanity: C is mounted and renders at depth 1",
      );
      expect(
        find.text("Q@0"),
        findsOneWidget,
        reason: "setup sanity: Q renders at depth 0",
      );

      // ONE handler, no pump in between: the collapse hides C but the
      // element keeps its row mounted, then the move changes C's depth
      // while the expansion-gated flatten of P's subtree is just [P].
      controller.collapse(key: "P");
      controller.moveNode("P", "Q");
      controller.expand(key: "Q");
      controller.expand(key: "P");
      await tester.pump();

      expect(
        controller.getDepth("C"),
        2,
        reason: "setup sanity: the move re-depthed C to 2",
      );
      expect(
        disposedKeys,
        isNot(contains("C")),
        reason:
            "setup sanity: C's element must never unmount across the "
            "handler; the defect exists precisely because the mounted row "
            "survives and is reused",
      );
      expect(
        find.text("C@2"),
        findsOneWidget,
        reason:
            "the still-mounted row, visible again, must render its "
            "post-move depth; an expansion-gated affected set never "
            "dirtied it",
      );
      expect(
        find.text("C@1"),
        findsNothing,
        reason: "no row may keep rendering the pre-move depth",
      );
      // Deliberately NOT asserted: find.text("P@1"). P's refresh is
      // carried by expand(key: "P")'s own notification (the toggled node
      // rebuilds; rebuild_budget_test.dart pins that), so a P-label
      // assertion cannot fail in the direction this test checks. Verified
      // by mutation: with moveNode notifying an empty set, "P@1" still
      // renders.
    },
  );
}
