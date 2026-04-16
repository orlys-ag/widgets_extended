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

  /// True while [_syncChildrenRecursive] is running. Tells [syncChildren]
  /// to skip immediate expansion restoration — the recursive method handles
  /// it after each node's full subtree is in place.
  bool _deferExpansionRestore = false;

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
    _controller.runBatch(() {
      _syncRootsImpl(desired, childrenOf: childrenOf, animate: animate);
    });
  }

  void _syncRootsImpl(
    List<TreeNode<TKey, TData>> desired, {
    List<TreeNode<TKey, TData>> Function(TKey key)? childrenOf,
    bool animate = true,
  }) {
    final desiredKeys = desired.map((n) => n.key).toList();
    final desiredSet = desiredKeys.toSet();
    final currentSet = _currentRoots.toSet();

    // Pre-compute the full set of desired descendant keys so the reparenting
    // check below can detect a root that is moving to any depth in the new
    // tree (not just a direct child of another new root). This set is also
    // reused in step 6 to defer cross-parent removals in _syncChildrenRecursive.
    Set<TKey>? desiredDescendants;
    if (childrenOf != null) {
      desiredDescendants = <TKey>{};
      _globallyDesiredChildren = desiredDescendants;
      _collectDesiredDescendants(desired, childrenOf);
    }

    // 1. Remove roots no longer desired.
    //    When childrenOf is provided, skip removal of roots that appear
    //    anywhere in the desired tree — they are being reparented, not
    //    deleted. If a reparented root were treated as a deletion, its
    //    subtree would enter _pendingDeletion; a later moveNode would
    //    succeed but _finalizeAnimation would eventually purge the subtree.
    final toRemove = currentSet.difference(desiredSet);
    for (final key in toRemove) {
      if (desiredDescendants != null && desiredDescendants.contains(key)) {
        continue;
      }
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
        final oldParent = _controller.getParent(node.key);
        _controller.updateNode(node);
        _controller.moveNode(node.key, null, index: targetIndex);
        if (oldParent != null) {
          _currentChildren[oldParent]?.remove(node.key);
        }
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

    // 5. Re-sync children recursively for all desired nodes.
    //    _globallyDesiredChildren was already populated at the top of this
    //    method so the reparent detection in step 1 could see deep moves.
    //    syncChildren uses it to defer removal of nodes desired under a
    //    different parent.
    //
    //    This must run BEFORE reorderRoots: a former root being reparented
    //    into another root's subtree is still a live root at this point, and
    //    reorderRoots asserts that orderedKeys matches the current live roots
    //    exactly. The reparenting moveNode happens inside this recursive pass.
    if (childrenOf != null) {
      _deferExpansionRestore = true;
      try {
        _syncChildrenRecursive(desired, childrenOf, toAdd, animate);
      } finally {
        _deferExpansionRestore = false;
        _globallyDesiredChildren = null;
      }
    }

    // 6. Reorder all live roots to match desired order if needed.
    //    After recursive children sync, any former roots that were reparented
    //    into the new tree have been moved out, so the controller's live
    //    roots should match desiredKeys (possibly in a different order).
    final liveRoots = <TKey>[
      for (final k in _controller.rootKeys)
        if (!_controller.isExiting(k)) k,
    ];
    if (!_listEquals(liveRoots, desiredKeys)) {
      _controller.reorderRoots(desiredKeys);
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
    // Silently ignore unknown parents. Without this guard, a release build
    // skips TreeController.insert's debug assert and writes _parents[child] =
    // parentKey for a ghost parent, creating a zombie subtree unreachable
    // from any root and never eligible for _purgeNodeData cleanup.
    if (_controller.getNodeData(parentKey) == null) {
      return;
    }
    _controller.runBatch(() {
      _syncChildrenImpl(parentKey, desired, animate: animate);
    });
  }

  void _syncChildrenImpl(
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
        // Read the old parent before the move so we can drop the now-stale
        // tracking entry under it. Without this, a caller that later calls
        // syncChildren(oldParent, [...node...]) would see the key as already
        // present under oldParent, skip the moveNode, and diverge from the
        // controller's actual state.
        final oldParent = _controller.getParent(node.key);
        _controller.updateNode(node);
        _controller.moveNode(node.key, parentKey, index: targetIndex);
        if (oldParent != null && oldParent != parentKey) {
          _currentChildren[oldParent]?.remove(node.key);
        }
      } else {
        _controller.insert(
          parentKey: parentKey,
          node: node,
          index: targetIndex,
          animate: animate,
        );
        // Restore expansion state only for truly new nodes.
        // When inside a recursive sync (_deferExpansionRestore is true),
        // skip — the node's own children haven't been synced yet, so
        // expand() would be a no-op. _syncChildrenRecursive handles
        // restoration after each node's full subtree is in place.
        if (!_deferExpansionRestore) {
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

    // 7. If the parent itself had a pending expansion restore that was
    // deferred because its children weren't registered yet, retry now that
    // they are. Without this retry, a re-added parent whose children arrive
    // in a later sync would remain silently collapsed.
    if (preserveExpansion &&
        !_deferExpansionRestore &&
        _expansionMemory.containsKey(parentKey)) {
      _restoreExpansion(parentKey, animate: animate);
    }
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
    _controller.runBatch(() {
      _globallyDesiredChildren = <TKey>{};
      try {
        for (final children in desiredByParent.values) {
          for (final c in children) {
            _globallyDesiredChildren!.add(c.key);
          }
        }
        for (final entry in desiredByParent.entries) {
          syncChildren(entry.key, entry.value, animate: animate);
        }
      } finally {
        _globallyDesiredChildren = null;
      }
    });
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
      _currentChildren[key] = List<TKey>.of(children);
      for (final childKey in children) {
        trackChildren(childKey);
      }
    }

    for (final rootKey in _currentRoots) {
      trackChildren(rootKey);
    }
  }

  /// Returns a deep-copied snapshot of the current tracked child order.
  ///
  /// The returned map and lists are detached from the controller's internal
  /// state, so callers can safely compare snapshots across sync operations.
  Map<TKey, List<TKey>> snapshotCurrentChildren() {
    return <TKey, List<TKey>>{
      for (final entry in _currentChildren.entries)
        entry.key: List<TKey>.of(entry.value),
    };
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
    if (!preserveExpansion || maxExpansionMemorySize <= 0) {
      return;
    }
    _rememberExpansionRecursive(key);
    // Evict oldest entries if over capacity.
    while (_expansionMemory.length > maxExpansionMemorySize) {
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

  /// Removes [_expansionMemory] entries for keys that are currently live
  /// in the tree controller. Their expansion state is already live in the
  /// controller, so remembering it is redundant.
  ///
  /// Nodes that are pending deletion (playing an exit animation) are NOT
  /// considered live — their data still exists in the controller but will
  /// be purged when the animation completes.
  void _pruneExpansionMemory() {
    if (_expansionMemory.isEmpty) return;
    _expansionMemory.removeWhere((key, wasExpanded) {
      if (_controller.getNodeData(key) == null) return false;
      if (_controller.isExiting(key)) return false;
      // If the remembered state says expanded but the node currently has
      // no children in the controller, the restore couldn't complete yet
      // (children arrive in a later sync). Keep the memory so the next
      // sync can finish restoring instead of losing the state silently.
      if (wasExpanded == true &&
          !_controller.isExpanded(key) &&
          !_controller.hasChildren(key)) {
        return false;
      }
      return true;
    });
  }

  /// Restores expansion state for [key] after insertion.
  ///
  /// If [key] was remembered as expanded but its children aren't registered
  /// with the controller yet (async-loaded subtrees, ordering of sync calls),
  /// the memory entry is preserved so a subsequent sync that adds the
  /// children can finish restoring. Clearing eagerly would leave the node
  /// permanently collapsed on re-add.
  void _restoreExpansion(TKey key, {required bool animate}) {
    if (!preserveExpansion) return;
    final wasExpanded = _expansionMemory[key];
    if (wasExpanded != true) {
      _expansionMemory.remove(key);
      return;
    }
    if (!_controller.hasChildren(key)) {
      // Keep memory for the next sync — expand() now would be a no-op.
      return;
    }
    _expansionMemory.remove(key);
    _controller.expand(key: key, animate: animate);
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
