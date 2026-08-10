/// Regression tests for sibling ORDER in the input normalizers.
///
/// `normalizeHierarchy` walks with an explicit LIFO stack (so deep trees
/// do not overflow the Dart stack). Its children loop pushes in reverse so
/// the first child pops first, but the roots seeding loop originally
/// pushed FORWARD, which reversed the entire root list: `[a, b, c]` came
/// out as `[c, b, a]`. That reached every `SyncedSliverTree.hierarchy`
/// user with more than one root, and no test covered root order. (The bug
/// predates the normalizer file; the walker moved here verbatim from
/// `TreeSnapshot.fromHierarchy`.)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/_synced_input_normalizer.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

class _Node {
  const _Node(this.id, {this.children = const <_Node>[]});

  final String id;
  final List<_Node> children;
}

String _keyOf(_Node item) {
  return item.id;
}

List<_Node> _childrenOf(_Node item) {
  return item.children;
}

List<K> _keys<K, V>(Iterable<TreeNode<K, V>> nodes) {
  return <K>[for (final node in nodes) node.key];
}

void main() {
  test("normalizeHierarchy preserves root order", () {
    final normalized = normalizeHierarchy<String, _Node>(
      roots: const [_Node("a"), _Node("b"), _Node("c")],
      keyOf: _keyOf,
      childrenOf: _childrenOf,
    );
    expect(_keys(normalized.roots), ["a", "b", "c"]);
  });

  test("normalizeHierarchy preserves child order at every depth", () {
    final normalized = normalizeHierarchy<String, _Node>(
      roots: const [
        _Node(
          "p",
          children: <_Node>[
            _Node("x", children: <_Node>[_Node("x1"), _Node("x2")]),
            _Node("y"),
            _Node("z"),
          ],
        ),
      ],
      keyOf: _keyOf,
      childrenOf: _childrenOf,
    );
    expect(_keys(normalized.childrenByParent["p"]!), ["x", "y", "z"]);
    expect(_keys(normalized.childrenByParent["x"]!), ["x1", "x2"]);
  });

  test(
    "normalizeHierarchy preserves order for a non-List iterable of roots",
    () {
      final normalized = normalizeHierarchy<String, _Node>(
        roots: const [_Node("a"), _Node("b"), _Node("c")].where((_) {
          return true;
        }),
        keyOf: _keyOf,
        childrenOf: _childrenOf,
      );
      expect(_keys(normalized.roots), ["a", "b", "c"]);
    },
  );

  test("normalizeFlat preserves root and child order", () {
    final normalized = normalizeFlat<String, String>(
      items: const ["a", "b", "a1", "a2"],
      keyOf: (item) {
        return item;
      },
      parentOf: (item) {
        return item.startsWith("a") && item != "a" ? "a" : null;
      },
    );
    expect(_keys(normalized.roots), ["a", "b"]);
    expect(_keys(normalized.childrenByParent["a"]!), ["a1", "a2"]);
  });

  test("normalizeFlat treats a parent key absent from items as root", () {
    final normalized = normalizeFlat<String, String>(
      items: const ["orphaned", "a"],
      keyOf: (item) {
        return item;
      },
      parentOf: (item) {
        return item == "orphaned" ? "not-in-items" : null;
      },
    );
    expect(_keys(normalized.roots), ["orphaned", "a"]);
    expect(normalized.childrenByParent, isEmpty);
  });
}
