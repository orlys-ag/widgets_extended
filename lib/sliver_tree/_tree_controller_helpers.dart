/// Internal: helper methods for [TreeController] split out via a part file
/// so the core controller class stays readable. All methods live as extension
/// members and have unrestricted access to [TreeController]'s private state
/// because part files share a library.
part of "tree_controller.dart";

/// Internal helpers for [TreeController]: bulk visible-order maintenance,
/// descendant/subtree walks, and node-data purging. Extracted purely for
/// file-size reasons; the logical owner is still [TreeController].
extension _TreeControllerHelpers<TKey, TData> on TreeController<TKey, TData> {
  void _clear() {
    _standaloneTicker?.stop();
    _standaloneTicker?.dispose();
    _standaloneTicker = null;
    _disposeBulkAnimationGroup();
    for (final group in _operationGroups.values) {
      group.dispose();
    }
    _operationGroups.clear();
    _slideTicker?.dispose();
    _slideTicker = null;
    _slideAnimations.clear();
    _store.clear();
    _visibleSubtreeSizeByNid = Int32List(0);
    _roots.clear();
    _order.reset();
    _standaloneAnimations.clear();
    _animStates.clear();
    _pendingDeletionCount = 0;
    _bumpAnimGen();
  }

  void _rebuildVisibleIndex() {
    _order.rebuildIndex();
    _assertIndexConsistency();
  }

  /// Updates indices for all nodes from [startIndex] to the end of the list.
  ///
  /// Call after inserting (single or bulk) into the visible order.
  void _updateIndicesFrom(int startIndex) {
    _order.reindexFrom(startIndex);
    _assertIndexConsistency();
  }

  /// Updates indices after removing items that were at [removeIndex].
  /// Removed keys must already have had their reverse-index slot cleared.
  void _updateIndicesAfterRemove(int removeIndex) {
    _order.reindexFrom(removeIndex);
    _assertIndexConsistency();
  }

  /// Debug assertion to verify index consistency.
  void _assertIndexConsistency() {
    assert(() {
      _order.debugAssertConsistent();
      _assertNidRegistryConsistency();
      return true;
    }());
  }

  /// Debug-only: delegates the per-nid data + registry consistency check to
  /// the [NodeStore].
  void _assertNidRegistryConsistency() {
    assert(() {
      _store.debugAssertConsistent();
      return true;
    }());
  }

  /// Removes a set of keys from the visible order and updates the index.
  ///
  /// Detects if the keys form a contiguous block via the reverse-index map
  /// and uses a range removal (O(1) shift) when possible, falling back to
  /// key-set compaction otherwise. Uses incremental index updates for
  /// contiguous removals, full rebuild for non-contiguous.
  void _removeFromVisibleOrder(Set<TKey> keys) {
    if (keys.isEmpty) {
      return;
    }
    if (keys.length == 1) {
      final key = keys.first;
      final idx = _order.indexOf(key);
      if (idx != VisibleOrderBuffer.kNotVisible &&
          idx < _order.length &&
          _order.keyAt(idx) == key) {
        _order.clearIndexOf(key);
        _order.removeAt(idx);
        _updateIndicesAfterRemove(idx);
        return;
      }
    }
    // Check if keys form a contiguous range via the nid-indexed visibility map.
    // Compare against [visibleCount] (not keys.length): a caller can pass a
    // key whose nid was already released (e.g. an op group's dismissed
    // handler purges pendingDeletion members before batching the visible-
    // order removal). Those keys report VisibleOrderBuffer.kNotVisible here, and using
    // keys.length would let the fast path fire when non-key rows sit in the
    // range gap, clobbering unrelated siblings.
    int minIdx = _order.length;
    int maxIdx = -1;
    int visibleCount = 0;
    for (final key in keys) {
      final idx = _order.indexOf(key);
      if (idx == VisibleOrderBuffer.kNotVisible) {
        continue;
      }
      visibleCount++;
      if (idx < minIdx) {
        minIdx = idx;
      }
      if (idx > maxIdx) {
        maxIdx = idx;
      }
    }
    if (maxIdx >= 0 && maxIdx - minIdx + 1 == visibleCount) {
      // Contiguous: clear the index first, then remove from the array.
      for (int i = minIdx; i <= maxIdx; i++) {
        _order.indexByNid[_order.orderNids[i]] = VisibleOrderBuffer.kNotVisible;
      }
      _order.removeRange(minIdx, maxIdx + 1);
      _updateIndicesAfterRemove(minIdx);
    } else {
      // Non-contiguous: remove from index, then list, then full rebuild
      for (final key in keys) {
        _order.clearIndexOf(key);
      }
      _order.removeWhereKeyIn(keys);
      _rebuildVisibleIndex();
    }
  }

  List<TKey> _getDescendants(TKey key) {
    final result = <TKey>[];
    _getDescendantsInto(key, result);
    return result;
  }

  /// Iterative DFS pre-order collection of every descendant of [key]
  /// (excluding [key] itself). Children are pushed in reverse so the
  /// first child pops first; this matches the original recursive
  /// implementation's visit order, which [remove] and other callers
  /// depend on.
  void _getDescendantsInto(TKey key, List<TKey> result) {
    final stack = <TKey>[];
    final seed = _childListOf(key);
    if (seed == null) {
      return;
    }
    for (int i = seed.length - 1; i >= 0; i--) {
      stack.add(seed[i]);
    }
    while (stack.isNotEmpty) {
      final k = stack.removeLast();
      result.add(k);
      final children = _childListOf(k);
      if (children == null) {
        continue;
      }
      for (int i = children.length - 1; i >= 0; i--) {
        stack.add(children[i]);
      }
    }
  }

  List<TKey> _getVisibleDescendants(TKey key) {
    final result = <TKey>[];
    _getVisibleDescendantsInto(key, result);
    return result;
  }

  /// Iterative DFS collection of every visible descendant of [key].
  ///
  /// A node is emitted when it is in the visible order. The original
  /// recursive version gated *descent into grandchildren* on the child's
  /// expansion state but **did not** gate the top-level walk on [key]'s
  /// own expansion — callers such as [collapse] deliberately flip
  /// expanded=false before asking which descendants to hide, and rely
  /// on the first level being returned regardless.
  void _getVisibleDescendantsInto(TKey key, List<TKey> result) {
    final seed = _childListOf(key);
    if (seed == null) {
      return;
    }
    final stack = <TKey>[];
    for (int i = seed.length - 1; i >= 0; i--) {
      stack.add(seed[i]);
    }
    while (stack.isNotEmpty) {
      final k = stack.removeLast();
      if (!_order.contains(k)) {
        continue;
      }
      result.add(k);
      if (!_isExpandedKey(k)) {
        continue;
      }
      final children = _childListOf(k);
      if (children == null) {
        continue;
      }
      for (int i = children.length - 1; i >= 0; i--) {
        stack.add(children[i]);
      }
    }
  }

  /// Flattens a subtree into a list of node IDs in depth-first order.
  List<TKey> _flattenSubtree(TKey key, {bool includeRoot = true}) {
    final result = <TKey>[];
    _flattenSubtreeInto(key, result, includeRoot: includeRoot);
    return result;
  }

  /// Iterative DFS pre-order flatten. Only descends into expanded nodes
  /// (matching the original recursive behaviour). Emits [key] itself
  /// iff [includeRoot], then every descendant reachable through the
  /// expanded subtree in DFS pre-order.
  void _flattenSubtreeInto(
    TKey key,
    List<TKey> result, {
    bool includeRoot = true,
  }) {
    if (includeRoot) {
      result.add(key);
    }
    if (!_isExpandedKey(key)) {
      return;
    }
    final stack = <TKey>[];
    final seed = _childListOf(key);
    if (seed == null) {
      return;
    }
    for (int i = seed.length - 1; i >= 0; i--) {
      stack.add(seed[i]);
    }
    while (stack.isNotEmpty) {
      final k = stack.removeLast();
      result.add(k);
      if (!_isExpandedKey(k)) {
        continue;
      }
      final children = _childListOf(k);
      if (children == null) {
        continue;
      }
      for (int i = children.length - 1; i >= 0; i--) {
        stack.add(children[i]);
      }
    }
  }

  /// Removes a single key from all internal maps (but not from the visible
  /// order, _roots, or the parent's children list — those are handled by
  /// the caller).
  void _purgeNodeData(TKey key) {
    if (_clearFullExtent(key) != null) {
      _invalidateFullOffsetPrefix();
    }
    // Clean up standalone animation state
    if (_standaloneAnimations.remove(key) != null) {
      _bumpAnimGen();
    }
    // Clean up operation group membership
    final opGroupKey = _clearOperationGroup(key);
    if (opGroupKey != null) {
      final group = _operationGroups[opGroupKey];
      if (group != null) {
        final removedMember = group.members.remove(key) != null;
        final removedPending = group.pendingRemoval.remove(key);
        if (removedMember || removedPending) {
          _bumpAnimGen();
        }
      }
    }
    // If [key] IS an operation key (the node that triggered an expand/collapse),
    // tear down the whole group. Without this, the entry lives on in
    // [_operationGroups] orphaned — a later insert+expand with the same key
    // would reuse the stale group via the Path 1 branch in [expand]/[collapse].
    final orphanGroup = _operationGroups.remove(key);
    if (orphanGroup != null) {
      for (final memberKey in orphanGroup.members.keys) {
        if (_operationGroupOf(memberKey) == key) {
          _clearOperationGroup(memberKey);
        }
      }
      _bumpAnimGen();
      orphanGroup.dispose();
    }
    // Clean up bulk animation group membership
    final bulk = _bulkAnimationGroup;
    if (bulk != null) {
      final removedMember = bulk.members.remove(key);
      final removedPending = bulk.pendingRemoval.remove(key);
      if (removedMember || removedPending) {
        _bumpBulkGen();
      }
    }
    _clearPendingDeletion(key);
    _order.clearIndexOf(key);
    _releaseNid(key);
  }

  /// Unified node removal: decrements the visible-subtree-size cache up
  /// the parent chain for every visible node about to be purged, then
  /// unlinks each from its parent's child list (or `_roots`), purges
  /// node data (releasing nids), and finally compacts `_order`.
  ///
  /// Use this for the **general case** where caller wants to fully
  /// remove a set of arbitrary keys. Two specialized sites bypass it
  /// because they already know all removed keys share an immediate
  /// parent and exploit a single bulk decrement: [setChildren] and
  /// `_finalizeAnimation`'s deletion branch.
  ///
  /// [keysToRemoveSet] is an optional pre-built set used for the
  /// "first surviving ancestor" walk; if null, the helper builds one
  /// from [nodesToRemove]. Pass it when the caller already has the set
  /// in hand to avoid the rebuild cost.
  ///
  /// [compactOrder] controls whether step 5 (order-buffer compaction)
  /// runs. Pass `false` when the caller will batch order compaction
  /// across multiple invocations (e.g. the operation-group dismissed
  /// handler, which combines its own category-2 keys into one
  /// `_removeFromVisibleOrder` call).
  ///
  /// Callers retain responsibility for any *other* per-site cleanup
  /// (e.g. clearing `_nodeToOperationGroup` membership) before invoking
  /// this helper.
  void _purgeAndRemoveFromOrder(
    Iterable<TKey> nodesToRemove, {
    Set<TKey>? keysToRemoveSet,
    bool compactOrder = true,
  }) {
    final keysSet = keysToRemoveSet ?? nodesToRemove.toSet();
    if (keysSet.isEmpty) {
      return;
    }

    // Step 1: cache decrement (first surviving ancestor walk). Must run
    // before unlink/purge because _bumpVisibleSubtreeSizeFromSelf reads
    // _parentByNid, and _purgeNodeData → _releaseNid clears it.
    for (final key in nodesToRemove) {
      final nid = _nids[key];
      if (nid == null) {
        continue;
      }
      if (_order.indexByNid[nid] == VisibleOrderBuffer.kNotVisible) {
        continue;
      }
      final parentByNid = _store.parentByNid;
      var ancestorNid = parentByNid[nid];
      while (ancestorNid != TreeController._kNoParent && ancestorNid >= 0) {
        final ancestorKey = _nids.keyOf(ancestorNid);
        if (ancestorKey == null || !keysSet.contains(ancestorKey)) {
          break;
        }
        ancestorNid = parentByNid[ancestorNid];
      }
      if (ancestorNid != TreeController._kNoParent && ancestorNid >= 0) {
        _bumpVisibleSubtreeSizeFromSelf(ancestorNid, -1);
      }
    }

    // Step 2: unlink and purge (combined per key — purge clears the
    // parent pointer, so unlink must happen first within each iteration).
    for (final key in nodesToRemove) {
      final parentKey = _parentKeyOfKey(key);
      if (parentKey != null) {
        _childListOf(parentKey)?.remove(key);
      } else {
        _roots.remove(key);
      }
      _purgeNodeData(key);
    }

    // Step 3: order compaction. _removeFromVisibleOrder handles released
    // nids correctly (its non-contiguous path sweeps zombies via
    // removeWhereKeyIn's null-key check). Suppress per-nid callbacks
    // because the cache was already decremented in Step 1.
    if (compactOrder) {
      _runWithSubtreeSizeUpdatesSuppressed(() {
        _removeFromVisibleOrder(keysSet);
      });
    }
  }

  void _removeNodesImmediate(List<TKey> nodeIds) {
    _purgeAndRemoveFromOrder(nodeIds);
  }
}

/// Read-only [List] view over a [TreeController]'s visible order, backed by
/// the controller's nid buffer. Every read resolves a nid back to its key
/// through the controller's [NodeIdRegistry], so the view always reflects
/// the latest state. Mutation attempts throw.
class _VisibleNodesView<TKey, TData> extends ListBase<TKey> {
  _VisibleNodesView(this._controller);

  final TreeController<TKey, TData> _controller;

  @override
  int get length => _controller._order.length;

  @override
  set length(int value) {
    throw UnsupportedError("visibleNodes is read-only.");
  }

  @override
  TKey operator [](int index) {
    if (index < 0 || index >= _controller._order.length) {
      throw RangeError.index(
        index,
        this,
        "index",
        null,
        _controller._order.length,
      );
    }
    return _controller._nids.keyOfUnchecked(
      _controller._order.orderNids[index],
    );
  }

  @override
  void operator []=(int index, TKey value) {
    throw UnsupportedError("visibleNodes is read-only.");
  }
}
