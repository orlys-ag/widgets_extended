/// Shared fixture helper: converts the (roots, dataByKey, childrenByParent)
/// triple shape many fixtures use into [SyncedTreeNode]s for
/// [SyncedSliverTree]'s default `.tree` input mode.
///
/// Returns a FRESH list per call. Fixtures that rely on the identity
/// rebuild gate (same instance across pumps means no re-diff) must call
/// this once and hold the result; fixtures that want every pump to
/// re-diff call it per build.
library;

import 'package:widgets_extended/widgets_extended.dart';

List<SyncedTreeNode<K, V>> treeFrom<K, V>({
  required Iterable<K> roots,
  required Map<K, V> dataByKey,
  Map<K, Iterable<K>>? childrenByParent,
}) {
  SyncedTreeNode<K, V> build(K key) {
    final childKeys = childrenByParent?[key];
    return SyncedTreeNode<K, V>(
      key: key,
      data: dataByKey[key] as V,
      children: <SyncedTreeNode<K, V>>[
        if (childKeys != null)
          for (final child in childKeys) build(child),
      ],
    );
  }

  return <SyncedTreeNode<K, V>>[for (final root in roots) build(root)];
}
