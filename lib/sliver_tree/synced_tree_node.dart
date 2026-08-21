/// Immutable nested tree node for `SyncedSliverTree`.
library;

/// A node of the nested tree that `SyncedSliverTree`'s default
/// constructor consumes.
///
/// Instances are immutable: every field is final and [children] cannot be
/// modified after construction. Signal a change by handing the widget a
/// new tree rather than mutating one in place, which is what its
/// identical-input fast path relies on.
class SyncedTreeNode<TKey, TItem> {
  /// Creates a node. [children] is copied into an unmodifiable list, so
  /// mutating the iterable passed here afterwards has no effect.
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
