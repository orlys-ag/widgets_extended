/// Immutable nested tree node for [SyncedSliverTree].
library;

class SyncedTreeNode<TKey, TItem> {
  SyncedTreeNode({
    required this.key,
    required this.data,
    Iterable<SyncedTreeNode<TKey, TItem>> children = const [],
  }) : children = List<SyncedTreeNode<TKey, TItem>>.unmodifiable(children);

  /// Unique identifier for this node.
  final TKey key;

  /// User payload for this node.
  final TItem data;

  /// Nested child nodes in sibling order.
  final List<SyncedTreeNode<TKey, TItem>> children;
}
