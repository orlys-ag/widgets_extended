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
    _nodeToOperationGroup.clear();
    _slideTicker?.dispose();
    _slideTicker = null;
    _slideAnimations.clear();
    _dataByNid.clear();
    _childrenByNid.clear();
    _parentByNid = Int32List(0);
    _depthByNid = Int32List(0);
    _expandedByNid = Uint8List(0);
    _ancestorsExpandedByNid = Uint8List(0);
    _visibleSubtreeSizeByNid = Int32List(0);
    _roots.clear();
    _order.reset();
    _standaloneAnimations.clear();
    _fullExtents.clear();
    _pendingDeletion.clear();
    _nids.clear();
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

  /// Debug-only: verifies the per-nid data slots match the registry, then
  /// delegates cross-checking of the forward/reverse maps to the registry.
  /// Every live nid must reverse-map correctly and resolve to a non-null
  /// entry in [_dataByNid]; every freed nid must have a null data slot.
  void _assertNidRegistryConsistency() {
    assert(() {
      if (_dataByNid.length != _nids.length) {
        throw StateError(
          "_dataByNid size ${_dataByNid.length} != registry size "
          "${_nids.length}",
        );
      }
      for (int nid = 0; nid < _nids.length; nid++) {
        final key = _nids.keyOf(nid);
        if (key == null) {
          continue;
        }
        if (_dataByNid[nid] == null) {
          throw StateError("nid $nid for key $key has null data slot");
        }
      }
      _nids.debugAssertConsistent();
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
    if (_fullExtents.remove(key) != null) {
      _invalidateFullOffsetPrefix();
    }
    // Clean up standalone animation state
    if (_standaloneAnimations.remove(key) != null) {
      _bumpAnimGen();
    }
    // Clean up operation group membership
    final opGroupKey = _nodeToOperationGroup.remove(key);
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
        if (_nodeToOperationGroup[memberKey] == key) {
          _nodeToOperationGroup.remove(memberKey);
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
    _pendingDeletion.remove(key);
    _order.clearIndexOf(key);
    _releaseNid(key);
  }

  void _removeNodesImmediate(List<TKey> nodeIds) {
    final keysToRemove = nodeIds.toSet();

    // Check visibility and contiguity BEFORE purging (purge clears the index)
    int minIdx = _order.length;
    int maxIdx = -1;
    int visibleCount = 0;
    for (final key in nodeIds) {
      final idx = _order.indexOf(key);
      if (idx != VisibleOrderBuffer.kNotVisible) {
        visibleCount++;
        if (idx < minIdx) {
          minIdx = idx;
        }
        if (idx > maxIdx) {
          maxIdx = idx;
        }
      }
    }

    // Purge node data (releases nid and clears visibility)
    for (final key in nodeIds) {
      final parentKey = _parentKeyOfKey(key);
      if (parentKey != null) {
        _childListOf(parentKey)?.remove(key);
      } else {
        _roots.remove(key);
      }
      _purgeNodeData(key);
    }

    // Update visible order
    if (visibleCount > 0) {
      if (maxIdx - minIdx + 1 == visibleCount) {
        // Contiguous removal
        _order.removeRange(minIdx, maxIdx + 1);
        _updateIndicesAfterRemove(minIdx);
      } else {
        // Non-contiguous removal
        _order.removeWhereKeyIn(keysToRemove);
        _rebuildVisibleIndex();
      }
    }
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
