/// Verifies that [TreeSnapshot] construction does not stack-overflow on
/// a 20k-deep chain. The internal `_validate` cycle-checker, plus the
/// `fromHierarchy` walker, both recursed one frame per node.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _DeepNode {
  _DeepNode(this.id, [this.child]);
  final int id;
  final _DeepNode? child;
}

void main() {
  test("TreeSnapshot constructor does not stack-overflow on a 20k-deep "
      "chain", () {
    const depth = 20000;
    final dataByKey = <int, int>{
      for (var i = 0; i < depth; i++) i: i,
    };
    final childrenByParent = <int, List<int>>{
      for (var i = 0; i < depth - 1; i++) i: [i + 1],
    };
    expect(
      () => TreeSnapshot<int, int>(
        roots: [0],
        dataByKey: dataByKey,
        childrenByParent: childrenByParent,
      ),
      returnsNormally,
      reason: "TreeSnapshot._validate stack-overflowed on a 20k-deep chain — "
          "the cycle-detection visit() helper needs to be iterative.",
    );
  });

  test("TreeSnapshot.fromHierarchy does not stack-overflow on a 20k-deep "
      "chain", () {
    const depth = 20000;
    // Build a 20k-deep chain of _DeepNode objects.
    _DeepNode? tail;
    for (var i = depth - 1; i >= 0; i--) {
      tail = _DeepNode(i, tail);
    }
    final root = tail!;
    expect(
      () => TreeSnapshot<int, _DeepNode>.fromHierarchy(
        roots: [root],
        keyOf: (n) => n.id,
        childrenOf: (n) => n.child == null ? const [] : [n.child!],
      ),
      returnsNormally,
      reason: "TreeSnapshot.fromHierarchy stack-overflowed on a 20k-deep "
          "chain — the visit() helper needs to be iterative.",
    );
  });

  testWidgets("SyncedSliverTree.tree normalizes a 20k-deep nested "
      "SyncedTreeNode without stack overflow", (tester) async {
    const depth = 20000;
    SyncedTreeNode<int, int>? leafTail;
    for (var i = depth - 1; i >= 0; i--) {
      leafTail = SyncedTreeNode<int, int>(
        key: i,
        data: i,
        children: leafTail == null ? const [] : [leafTail],
      );
    }
    final root = leafTail!;

    expect(
      () => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CustomScrollView(
            slivers: [
              SyncedSliverTree<int, int>(
                tree: [root],
                animationDuration: Duration.zero,
                initiallyExpanded: false,
                itemBuilder: (context, view) =>
                    Text("${view.key}", textDirection: TextDirection.ltr),
              ),
            ],
          ),
        ),
      ),
      returnsNormally,
      reason: "SyncedSliverTree._normalizeTree stack-overflowed on a 20k-deep "
          "nested SyncedTreeNode tree.",
    );
  });
}
