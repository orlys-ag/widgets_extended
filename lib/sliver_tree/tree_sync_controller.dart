/// A diffing/syncing layer on top of [TreeController].
///
/// [TreeSyncController] tracks the current tree state, computes diffs against
/// a desired state, and applies animated insert/remove operations. It also
/// preserves expansion state across remove/re-add cycles.
///
/// Use [syncRoots] to sync the top-level nodes and [syncChildren] to sync
/// the children of a specific parent.
///
/// Example:
/// ```dart
/// final treeController = TreeController<String, String>(vsync: this);
/// final syncController = TreeSyncController(treeController: treeController);
///
/// // Sync roots with optional children provider
/// syncController.syncRoots(
///   [TreeNode(key: 'a', data: 'A'), TreeNode(key: 'b', data: 'B')],
///   childrenOf: (key) => [TreeNode(key: '${key}_1', data: 'Child 1')],
/// );
///
/// // Sync children of a specific parent
/// syncController.syncChildren('a', [
///   TreeNode(key: 'a_1', data: 'Child 1'),
///   TreeNode(key: 'a_2', data: 'Child 2'),
/// ]);
/// ```
library;

import 'tree_controller.dart';
import 'types.dart';

/// A controller that syncs a [TreeController] to a desired state using
/// animated diffs.
///
/// This controller does not own the [TreeController] — it drives it.
/// Dispose this controller before disposing the underlying [TreeController].
class TreeSyncController<TKey, TData> {
  /// Creates a sync controller.
  ///
  /// If [preserveExpansion] is true (the default), the controller remembers
  /// expansion state of removed nodes and restores it when they are re-added.
  TreeSyncController({
    required TreeController<TKey, TData> treeController,
    this.preserveExpansion = true,
    this.maxExpansionMemorySize = 1024,
  }) : _controller = treeController;

  final TreeController<TKey, TData> _controller;

  /// Whether to remember and restore expansion state across remove/re-add
  /// cycles.
  final bool preserveExpansion;

  /// Maximum number of entries in [_expansionMemory]. When exceeded, the
  /// oldest entries are evicted (FIFO via [LinkedHashMap] insertion order).
  /// Set to 0 to disable expansion memory entirely.
  final int maxExpansionMemorySize;

  /// Remembered expansion states for removed nodes.
  final Map<TKey, bool> _expansionMemory = {};

  /// Current root keys in order, tracked to compute diffs.
  final List<TKey> _currentRoots = [];

  /// Current child keys per parent, tracked to compute diffs.
  final Map<TKey, List<TKey>> _currentChildren = {};

  /// During a [syncRoots] call with [childrenOf], holds the union of all
  /// desired child keys across all parents. [syncChildren] checks this to
  /// defer removal of nodes that are desired under a different parent.
  Set<TKey>? _globallyDesiredChildren;

  /// The underlying [TreeController] being driven.
  TreeController<TKey, TData> get treeController => _controller;

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ══════════════════════════════════════════════════════════════════════════

  /// Syncs the root nodes to match [desired].
  ///
  /// Roots present in the tree but absent from [desired] are removed.
  /// Roots in [desired] but not in the tree are inserted at the correct index.
  /// The order of [desired] is respected.
  ///
  /// If [childrenOf] is provided, it is called recursively for every node
  /// in the desired tree — roots and their descendants — to sync children
  /// at all depths. Return an empty list for leaf nodes. If a re-added node
  /// was previously expanded (and [preserveExpansion] is true), it is
  /// automatically expanded after its children are set.
  ///
  /// Set [animate] to false to suppress animations (useful for initial setup).
  void syncRoots(
    List<TreeNode<TKey, TData>> desired, {
    List<TreeNode<TKey, TData>> Function(TKey key)? childrenOf,
    bool animate = true,
  }) {
    final desiredKeys = desired.map((n) => n.key).toList();
    final desiredSet = desiredKeys.toSet();
    final currentSet = _currentRoots.toSet();

    // 1. Remove roots no longer desired.
    //    When childrenOf is provided, skip removal of roots that appear in
    //    a desired child list — they are being reparented, not deleted.
    final toRemove = currentSet.difference(desiredSet);
    final movedToChild = <TKey>{};
    if (childrenOf != null) {
      for (final key in toRemove) {
        for (final root in desired) {
          if (childrenOf(root.key).any((c) => c.key == key)) {
            movedToChild.add(key);
            break;
          }
        }
      }
    }
    for (final key in toRemove) {
      if (movedToChild.contains(key)) continue;
      // Skip if already removed or moved by an earlier operation.
      if (_controller.getNodeData(key) == null ||
          _controller.getParent(key) != null) {
        continue;
      }
      _rememberExpansion(key);
      _controller.remove(key: key, animate: animate);
      _clearChildrenTracking(key);
    }

    // 2. Build the post-removal set for insertion index computation.
    final remaining = <TKey>[
      for (final k in _currentRoots)
        if (!toRemove.contains(k)) k,
    ];

    // 3. Insert new roots at their correct position. If a node already
    //    exists in the controller (e.g., promoted from child to root), use
    //    moveNode to preserve subtree state instead of insertRoot.
    final toAdd = desiredSet.difference(currentSet);
    final addedRoots = <TKey>[];
    for (final node in desired) {
      if (!toAdd.contains(node.key)) continue;

      final targetIndex = _insertionIndex(desiredKeys, remaining, node.key);

      if (_controller.getNodeData(node.key) != null) {
        _controller.updateNode(node);
        _controller.moveNode(node.key, null, index: targetIndex);
      } else {
        _controller.insertRoot(node, index: targetIndex, animate: animate);
      }
      remaining.insert(targetIndex, node.key);
      addedRoots.add(node.key);
    }

    // 4. Update data for retained roots whose payload changed.
    final retained = desiredSet.intersection(currentSet);
    for (final node in desired) {
      if (!retained.contains(node.key)) continue;
      final current = _controller.getNodeData(node.key);
      if (current != null && current.data != node.data) {
        _controller.updateNode(node);
      }
    }

    // 5. Reorder all live roots to match desired order if needed.
    // After removals and insertions, `remaining` holds the current live root
    // order. If it differs from `desiredKeys`, reorder the controller.
    if (!_listEquals(remaining, desiredKeys)) {
      _controller.reorderRoots(desiredKeys);
    }

    // 6. Re-sync children recursively for all desired nodes.
    //    Pre-compute all desired descendant keys so syncChildren can defer
    //    removal of nodes that are desired under a different parent.
    if (childrenOf != null) {
      _globallyDesiredChildren = <TKey>{};
      _collectDesiredDescendants(desired, childrenOf);
      _syncChildrenRecursive(desired, childrenOf, toAdd, animate);
      _globallyDesiredChildren = null;
    }

    // 7. Restore expansion state for newly inserted roots after their
    // children have been reattached.
    for (final key in addedRoots) {
      _restoreExpansion(key, animate: animate);
    }

    // 8. Update tracking state.
    _currentRoots
      ..clear()
      ..addAll(desiredKeys);

    // 9. Prune expansion memory of keys that are now live in the controller.
    if (preserveExpansion) {
      _pruneExpansionMemory();
    }
  }

  /// Syncs the children of [parentKey] to match [desired].
  ///
  /// Children present under [parentKey] but absent from [desired] are removed.
  /// Children in [desired] but not currently shown are inserted at the correct
  /// index. The order of [desired] is respected.
  ///
  /// If a desired child already exists in the controller under a different
  /// parent, it is moved via [TreeController.moveNode] instead of being
  /// freshly inserted, preserving subtree state.
  ///
  /// **Reparenting note:** When called from [syncRoots] with [childrenOf]
  /// or from [syncMultipleChildren], removal of nodes that are desired
  /// under a different parent is automatically deferred. When calling
  /// [syncChildren] directly for a single parent, nodes absent from
  /// [desired] are removed immediately; use [syncMultipleChildren] when
  /// reparenting across parents.
  ///
  /// Set [animate] to false to suppress animations.
  void syncChildren(
    TKey parentKey,
    List<TreeNode<TKey, TData>> desired, {
    bool animate = true,
  }) {
    final desiredKeys = desired.map((n) => n.key).toList();
    final desiredSet = desiredKeys.toSet();
    final currentKeys = _currentChildren[parentKey] ?? const [];
    final currentSet = currentKeys.toSet();

    // 1. Remove children no longer desired. Skip nodes that:
    //    - have already been moved elsewhere (controller parent != parentKey)
    //    - are desired under a different parent in this sync cycle
    final toRemove = currentSet.difference(desiredSet);
    for (final key in toRemove) {
      if (_controller.getNodeData(key) == null ||
          _controller.getParent(key) != parentKey) {
        continue;
      }
      // Defer removal if the node is desired under a different parent.
      if (_globallyDesiredChildren != null &&
          _globallyDesiredChildren!.contains(key)) {
        continue;
      }
      _rememberExpansion(key);
      _controller.remove(key: key, animate: animate);
      _clearChildrenTracking(key);
    }

    // 2. Build the post-removal list for insertion index computation.
    final remaining = <TKey>[
      for (final k in currentKeys)
        if (!toRemove.contains(k)) k,
    ];

    // 3. Insert new children at their correct position. If a node already
    //    exists in the controller (reparented from another location), use
    //    moveNode to preserve subtree state.
    final toAdd = desiredSet.difference(currentSet);
    for (final node in desired) {
      if (!toAdd.contains(node.key)) continue;

      final targetIndex = _insertionIndex(desiredKeys, remaining, node.key);

      if (_controller.getNodeData(node.key) != null) {
        _controller.updateNode(node);
        _controller.moveNode(node.key, parentKey, index: targetIndex);
      } else {
        _controller.insert(
          parentKey: parentKey,
          node: node,
          index: targetIndex,
          animate: animate,
        );
        // Restore expansion state only for truly new nodes.
        // When inside a recursive sync (_globallyDesiredChildren is set),
        // defer restoration — the node's own children haven't been synced
        // yet, so expand() would be a no-op. _syncChildrenRecursive
        // handles restoration after the full subtree is in place.
        if (_globallyDesiredChildren == null) {
          _restoreExpansion(node.key, animate: animate);
        }
      }
      remaining.insert(targetIndex, node.key);
    }

    // 4. Update data for retained children whose payload changed.
    final retained = desiredSet.intersection(currentSet);
    for (final node in desired) {
      if (!retained.contains(node.key)) continue;
      final current = _controller.getNodeData(node.key);
      if (current != null && current.data != node.data) {
        _controller.updateNode(node);
      }
    }

    // 5. Reorder all live children to match desired order if needed.
    if (!_listEquals(remaining, desiredKeys)) {
      _controller.reorderChildren(parentKey, desiredKeys);
    }

    // 6. Update tracking state.
    _currentChildren[parentKey] = desiredKeys;
  }

  /// Syncs children for multiple parents in a single batch.
  ///
  /// This is the safe way to reparent nodes across parents when calling
  /// [syncChildren] directly (outside of [syncRoots]). The method
  /// pre-computes the union of all desired child keys so that removal of
  /// a node from its old parent is deferred when it is desired under a
  /// different parent, allowing [TreeController.moveNode] to preserve
  /// subtree state.
  ///
  /// Set [animate] to false to suppress animations.
  void syncMultipleChildren(
    Map<TKey, List<TreeNode<TKey, TData>>> desiredByParent, {
    bool animate = true,
  }) {
    _globallyDesiredChildren = <TKey>{};
    for (final children in desiredByParent.values) {
      for (final c in children) {
        _globallyDesiredChildren!.add(c.key);
      }
    }
    for (final entry in desiredByParent.entries) {
      syncChildren(entry.key, entry.value, animate: animate);
    }
    _globallyDesiredChildren = null;
  }

  /// Initializes tracking state from the current tree controller.
  ///
  /// Call after construction when the tree controller already has nodes
  /// (e.g., when recreating the sync controller mid-lifetime). Without
  /// this, the first [syncRoots] call treats all existing nodes as new
  /// and cannot remove nodes that are no longer desired.
  void initializeTracking() {
    _currentRoots
      ..clear()
      ..addAll(_controller.rootKeys);
    _currentChildren.clear();

    void trackChildren(TKey key) {
      final children = _controller.getChildren(key);
      if (children.isNotEmpty) {
        _currentChildren[key] = List<TKey>.of(children);
        for (final childKey in children) {
          trackChildren(childKey);
        }
      }
    }

    for (final rootKey in _currentRoots) {
      trackChildren(rootKey);
    }
  }

  /// Clears all remembered expansion state.
  void clearExpansionMemory() {
    _expansionMemory.clear();
  }

  /// Releases resources. Call before disposing the underlying [TreeController].
  void dispose() {
    _expansionMemory.clear();
    _currentRoots.clear();
    _currentChildren.clear();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  /// Recursively clears [_currentChildren] tracking for [key] and all its
  /// tracked descendants. Must be called when a node is removed so that
  /// future [syncChildren] calls don't diff against stale state.
  void _clearChildrenTracking(TKey key) {
    final children = _currentChildren.remove(key);
    if (children != null) {
      for (final childKey in children) {
        _clearChildrenTracking(childKey);
      }
    }
  }

  /// Recursively collects all desired descendant keys into
  /// [_globallyDesiredChildren].
  void _collectDesiredDescendants(
    List<TreeNode<TKey, TData>> nodes,
    List<TreeNode<TKey, TData>> Function(TKey key) childrenOf,
  ) {
    for (final node in nodes) {
      final children = childrenOf(node.key);
      for (final child in children) {
        _globallyDesiredChildren!.add(child.key);
      }
      _collectDesiredDescendants(children, childrenOf);
    }
  }

  /// Recursively syncs children for each node, then recurses into
  /// their children.
  void _syncChildrenRecursive(
    List<TreeNode<TKey, TData>> nodes,
    List<TreeNode<TKey, TData>> Function(TKey key) childrenOf,
    Set<TKey> newlyAdded,
    bool animate,
  ) {
    for (final node in nodes) {
      final children = childrenOf(node.key);
      syncChildren(
        node.key,
        children,
        animate: newlyAdded.contains(node.key) ? false : animate,
      );
      _syncChildrenRecursive(children, childrenOf, newlyAdded, animate);
      // Restore expansion for children after their full subtrees are synced.
      // This is deferred from syncChildren because expand() requires the
      // node to already have children registered in the controller.
      for (final child in children) {
        _restoreExpansion(child.key, animate: animate);
      }
    }
  }

  /// Remembers the expansion state of [key] and all its descendants before
  /// removal. This is necessary because [TreeController.remove] purges the
  /// entire subtree, so descendant expansion states would be lost.
  void _rememberExpansion(TKey key) {
    if (!preserveExpansion) {
      return;
    }
    _rememberExpansionRecursive(key);
    // Evict oldest entries if over capacity.
    while (_expansionMemory.length > maxExpansionMemorySize &&
        maxExpansionMemorySize > 0) {
      _expansionMemory.remove(_expansionMemory.keys.first);
    }
  }

  /// Recursively stores the expansion state for [key] and its descendants.
  void _rememberExpansionRecursive(TKey key) {
    _expansionMemory[key] = _controller.isExpanded(key);
    for (final childKey in _controller.getChildren(key)) {
      _rememberExpansionRecursive(childKey);
    }
  }

  /// Removes [_expansionMemory] entries for keys that are currently present
  /// in the tree controller. Their expansion state is already live in the
  /// controller, so remembering it is redundant.
  void _pruneExpansionMemory() {
    if (_expansionMemory.isEmpty) return;
    _expansionMemory.removeWhere((key, _) {
      return _controller.getNodeData(key) != null;
    });
  }

  /// Restores expansion state for [key] after insertion.
  void _restoreExpansion(TKey key, {required bool animate}) {
    if (!preserveExpansion) return;
    final wasExpanded = _expansionMemory.remove(key);
    if (wasExpanded == true) {
      _controller.expand(key: key, animate: animate);
    }
  }

  /// Shallow list equality check.
  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Computes the insertion index for [key] in [remaining] such that the
  /// final order matches [desiredOrder].
  ///
  /// Walks [desiredOrder] and counts how many keys before [key] are already
  /// in [remaining]. That count is the correct insertion index.
  static int _insertionIndex<T>(
    List<T> desiredOrder,
    List<T> remaining,
    T key,
  ) {
    final remainingSet = remaining.toSet();
    int index = 0;
    for (final k in desiredOrder) {
      if (k == key) {
        break;
      }
      if (remainingSet.contains(k)) {
        ++index;
      }
    }
    return index;
  }
}
