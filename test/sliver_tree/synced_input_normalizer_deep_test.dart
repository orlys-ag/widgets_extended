/// Verifies that input normalization does not stack-overflow on a
/// 20k-deep chain. The walkers all recursed one frame per node in an
/// earlier form, and `normalizeFlat`'s reachability walk is the successor
/// of `TreeSnapshot._validate`'s cycle-checker, which carried the same
/// duty for flat inputs; each must stay iterative.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/_synced_input_normalizer.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _DeepNode {
  _DeepNode(this.id, [this.child]);
  final int id;
  final _DeepNode? child;
}

void main() {
  test("normalizeFlat does not stack-overflow on a 20k-deep chain", () {
    const depth = 20000;
    expect(
      () => normalizeFlat<int, int>(
        items: [for (var i = 0; i < depth; i++) i],
        keyOf: (item) => item,
        parentOf: (item) => item == 0 ? null : item - 1,
      ),
      returnsNormally,
      reason:
          "normalizeFlat stack-overflowed on a 20k-deep chain; the "
          "reachability walk needs to be iterative.",
    );
  });

  test("normalizeHierarchy does not stack-overflow on a 20k-deep chain", () {
    const depth = 20000;
    // Build a 20k-deep chain of _DeepNode objects.
    _DeepNode? tail;
    for (var i = depth - 1; i >= 0; i--) {
      tail = _DeepNode(i, tail);
    }
    final root = tail!;
    expect(
      () => normalizeHierarchy<int, _DeepNode>(
        roots: [root],
        keyOf: (n) => n.id,
        childrenOf: (n) => n.child == null ? const [] : [n.child!],
      ),
      returnsNormally,
      reason:
          "normalizeHierarchy stack-overflowed on a 20k-deep chain; the "
          "walker needs to be iterative.",
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
                animationStyle: TreeAnimationStyle.disabled,
                initiallyExpanded: false,
                itemBuilder: (context, view) =>
                    Text("${view.key}", textDirection: TextDirection.ltr),
              ),
            ],
          ),
        ),
      ),
      returnsNormally,
      reason:
          "normalizeSyncedNodes stack-overflowed on a 20k-deep nested "
          "SyncedTreeNode tree.",
    );
  });
}
