/// Internal: animation-driver methods for [TreeController], split out via a
/// part file so the core controller class stays readable. All methods live
/// as extension members and have unrestricted access to [TreeController]'s
/// private state because part files share a library.
part of "tree_controller.dart";

/// Marker value indicating the target extent should be determined
/// from the measured size during layout. Top-level in this part so every
/// part of the library resolves the same constant.
const double _unknownExtent = -1.0;

/// Computes the speed multiplier for proportional timing.
///
/// When a node transitions between animation sources, the remaining
/// animation distance may be less than the full extent. The speed
/// multiplier ensures the animation completes in proportional time.
double _computeAnimationSpeedMultiplier(
  double currentExtent,
  double fullExtent,
) {
  if (fullExtent <= 0) {
    return 1.0;
  }
  final fraction = currentExtent / fullExtent;
  if (fraction <= 0 || fraction >= 1.0) {
    return 1.0;
  }
  return (1.0 / fraction).clamp(1.0, 10.0);
}

/// Animation-driver methods for [TreeController]. See class docs for the
/// high-level contract; this extension only exists so we can split the file.
extension _TreeControllerAnimationOps<TKey, TData>
    on TreeController<TKey, TData> {
  /// Captures a node's current animated extent from whichever source it's in,
  /// removes it from that source, and returns the extent (or null if not animating).
  double? _captureAndRemoveFromGroups(TKey key) {
    // 1. Check operation group
    final opGroupKey = _operationGroupOf(key);
    if (opGroupKey != null) {
      final group = _operationGroups[opGroupKey];
      if (group != null) {
        final member = group.members[key];
        if (member != null) {
          final full = _fullExtentOf(key) ?? TreeController.defaultExtent;
          final extent = member.computeExtent(group.curvedValue, full);
          group.members.remove(key);
          group.pendingRemoval.remove(key);
          _clearOperationGroup(key);
          _bumpAnimGen();
          _disposeOperationGroupIfEmpty(opGroupKey, group);
          return extent;
        }
      }
      _clearOperationGroup(key);
    }

    // 2. Check bulk animation group
    if (_bulkAnimationGroup?.members.contains(key) == true) {
      final full = _fullExtentOf(key) ?? TreeController.defaultExtent;
      final extent = full * _bulkAnimationGroup!.value;
      _removeBulkMember(key);
      _removeBulkPending(key);
      _bumpBulkGen();
      return extent;
    }

    // 3. Check standalone animations
    final standalone = _clearStandalone(key);
    if (standalone != null) {
      _bumpAnimGen();
      return standalone.currentExtent;
    }

    return null;
  }

  void _disposeOperationGroupIfEmpty(
    TKey operationKey,
    OperationGroup<TKey> group,
  ) {
    if (group.members.isNotEmpty || group.pendingRemoval.isNotEmpty) {
      return;
    }
    if (!identical(_operationGroups[operationKey], group)) {
      return;
    }
    _operationGroups.remove(operationKey);
    _bumpAnimGen();
    group.dispose();
  }

  /// Consolidates the duplicated listener-wiring that the fresh-expand
  /// and fresh-collapse Path-2 branches used to do inline. Asserts the
  /// Path-2 invariant that the slot is empty at install time, so any
  /// future code path that violates it fails loudly in debug rather
  /// than silently orphaning a controller.
  ///
  /// The status listener's identity guard prevents a stale controller's
  /// final synchronous status event (during the narrow window between
  /// `_operationGroups.remove` and `group.dispose()`) from mutating a
  /// newer group that has taken its slot.
  void _installOperationGroup(TKey key, OperationGroup<TKey> group) {
    assert(
      _operationGroups[key] == null,
      "_installOperationGroup: slot for $key already occupied; the "
      "fresh-expand / fresh-collapse paths must only reach here when "
      "the prior path-1 branch early-returned.",
    );

    _operationGroups[key] = group;
    _bumpAnimGen();

    group.controller.addListener(_notifyAnimationListeners);
    group.controller.addStatusListener((status) {
      if (!identical(_operationGroups[key], group)) return;
      _onOperationGroupStatusChange(key, status);
    });
  }

  /// Prepares [key]'s subtree for reparenting. Clears in-flight slide
  /// animations (their deltas were computed against the prior position and
  /// would paint at the wrong offset post-move) and pending-deletion state,
  /// and detaches subtree members from **external** animation sources whose
  /// anchor stays at the old position: standalone state, the bulk group, and
  /// operation groups whose `operationKey` lives outside the moved subtree.
  ///
  /// Operation groups whose `operationKey` lives **inside** the moved subtree
  /// are preserved intact. Their members are all in the subtree too, so both
  /// the timeline and the affected rows land together at the new position;
  /// the dismiss handler's `_ancestorsExpandedFast` check naturally routes
  /// hides against the new ancestry. Without this preservation, a node
  /// dragged mid-collapse would snap to its fully-collapsed state on drop
  /// instead of finishing the animation.
  ///
  /// Implementation note: single-pass iterative pre-order DFS. Safe to
  /// fold preservation collection into the same pass as detach work
  /// because op-group operation keys are always ancestors of their
  /// members (members are created via `_flattenSubtree(key,
  /// includeRoot: false)` with `_nodeToOperationGroup[member] = key`).
  /// Pre-order visits ancestors before descendants, so by the time we
  /// process a node, every ancestor inside the subtree has already been
  /// added to [preservedOpKeys] if applicable — the membership lookup
  /// is correct. If this traversal order ever changes to BFS or
  /// post-order, the lookup will silently desync; keep pre-order or
  /// split into two passes again.
  ///
  /// Iterative (heap worklist) so deep dragged subtrees cannot
  /// stack-overflow. Children pushed in reverse so pops preserve the
  /// left-to-right visit order the two recursive closures used to
  /// produce.
  void _cancelAnimationStateForSubtree(TKey key) {
    final preservedOpKeys = <TKey>{};
    final stack = <TKey>[key];
    while (stack.isNotEmpty) {
      final nodeId = stack.removeLast();

      // Add to preservedOpKeys BEFORE the detach branch so the lookup
      // `preservedOpKeys.contains(opGroupKey)` below resolves correctly
      // for nodes whose op-group's operationKey IS this node (rare but
      // possible in principle; harmless in practice since
      // _nodeToOperationGroup never points a member at itself).
      if (_operationGroups.containsKey(nodeId)) {
        preservedOpKeys.add(nodeId);
      }

      _clearPendingDeletion(nodeId);
      _clearSlide(nodeId);

      final opGroupKey = _operationGroupOf(nodeId);
      if (opGroupKey != null && preservedOpKeys.contains(opGroupKey)) {
        // Member of a preserved op group — keep its op-group state intact
        // so the animation continues against the post-move position.
        // Still detach from standalone / bulk sources defensively: a node
        // shouldn't be in both an op group and another source, but any
        // residue would otherwise drive a stray animation anchored to the
        // pre-move layout.
        if (_clearStandalone(nodeId) != null) {
          _bumpAnimGen();
        }
        final bulk = _bulkAnimationGroup;
        if (bulk != null) {
          final removedMember = _removeBulkMember(nodeId);
          final removedPending = _removeBulkPending(nodeId);
          if (removedMember || removedPending) {
            _bumpBulkGen();
          }
        }
      } else {
        // External-source cleanup: removes from standalone, external op
        // group (detaching the member), and bulk. Op group disposal, if
        // the external group becomes empty, is handled inside
        // _removeAnimation via _disposeOperationGroupIfEmpty.
        _removeAnimation(nodeId);
      }

      final children = _childListOf(nodeId);
      if (children == null) continue;
      // Reverse-push so the first child pops first, preserving the
      // pre-order left-to-right visit sequence the recursive closures
      // produced.
      for (int i = children.length - 1; i >= 0; i--) {
        stack.add(children[i]);
      }
    }

    if (!_hasAnyStandalone) {
      _standaloneTicker?.stop();
    }
  }

  /// Removes an animation from all sources and cleans up group membership.
  AnimationState? _removeAnimation(TKey key) {
    final state = _clearStandalone(key);
    if (state != null) {
      _bumpAnimGen();
    }
    // Remove from operation group
    final opGroupKey = _clearOperationGroup(key);
    if (opGroupKey != null) {
      final group = _operationGroups[opGroupKey];
      if (group != null) {
        final removedMember = group.members.remove(key) != null;
        final removedPending = group.pendingRemoval.remove(key);
        if (removedMember || removedPending) {
          _bumpAnimGen();
        }
        _disposeOperationGroupIfEmpty(opGroupKey, group);
      }
    }
    // Also remove from bulk animation group
    final bulk = _bulkAnimationGroup;
    if (bulk != null) {
      final removedMember = _removeBulkMember(key);
      final removedPending = _removeBulkPending(key);
      if (removedMember || removedPending) {
        _bumpBulkGen();
      }
    }
    return state;
  }

  /// Creates a new bulk animation group with an AnimationController.
  AnimationGroup<TKey> _createBulkAnimationGroup({double initialValue = 0.0}) {
    final controller = AnimationController(
      vsync: _vsync,
      duration: animationDuration,
      value: initialValue,
    );

    final group = AnimationGroup<TKey>(
      controller: controller,
      curve: animationCurve,
    );

    controller.addListener(_notifyAnimationListeners);

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _onBulkAnimationComplete();
      }
    });

    _bumpBulkGen();
    return group;
  }

  /// Disposes the current bulk animation group if it exists.
  void _disposeBulkAnimationGroup() {
    final group = _bulkAnimationGroup;
    // Set to null first to prevent callback interference
    _bulkAnimationGroup = null;
    if (group != null) {
      // Zero mirror slots for keys leaving via this disposal. Bounded by
      // group size, not nidCapacity. The walk reads from the local `group`
      // reference whose Set contents are intact even after the field was
      // nulled above.
      for (final key in group.members) {
        final nid = _nids[key];
        if (nid != null && nid < _isBulkMemberByNid.length) {
          _isBulkMemberByNid[nid] = 0;
        }
      }
      for (final key in group.pendingRemoval) {
        final nid = _nids[key];
        if (nid != null && nid < _isBulkMemberByNid.length) {
          _isBulkMemberByNid[nid] = 0;
        }
      }
      _bumpBulkGen();
    }
    group?.dispose();
  }

  /// Called when the bulk animation completes or is dismissed.
  void _onBulkAnimationComplete() {
    if (_bulkAnimationGroup == null) {
      return;
    }
    final controller = _bulkAnimationGroup!.controller;
    bool didMutateOrder = false;
    // If dismissed (value = 0), remove nodes marked for removal
    if (controller.status == AnimationStatus.dismissed) {
      _keysToRemoveScratch.clear();
      for (final key in _bulkAnimationGroup!.pendingRemoval) {
        if (!_isPendingDeletion(key)) {
          final parentKey = _parentKeyOfKey(key);
          final shouldRemove = parentKey == null
              ? !_roots.contains(key)
              : !_ancestorsExpandedFast(key);
          if (shouldRemove) {
            _keysToRemoveScratch.add(key);
          }
        }
      }
      if (_keysToRemoveScratch.isNotEmpty) {
        _removeFromVisibleOrder(_keysToRemoveScratch);
        _structureGeneration++;
        didMutateOrder = true;
      }
    }

    // Dispose the group. Leaving it live retains an idle AnimationController
    // and its ticker registration for the life of the TreeController, which
    // is wasteful. A subsequent expandAll/collapseAll will create a new one.
    _disposeBulkAnimationGroup();

    // Only notify when visible order actually changed. The .completed branch
    // (expandAll finished) inserts nothing new — every expansion happened at
    // expandAll() call time and already fired _notifyStructural then. Firing
    // here a second time makes SliverTreeElement mark every mounted row dirty
    // and rebuild it, producing the end-of-animation rebuild spike.
    //
    // Affected keys: empty. The bulk path only removes entries from _order;
    // it never touches parent child lists, so no parent's hasChildren can
    // flip. Newly-visible rows first-build via createChild; removed rows
    // are GC'd by SliverTreeElement. No mounted row needs a widget refresh.
    if (didMutateOrder) {
      _notifyStructural(affectedKeys: const {});
    }
  }

  /// Called when an operation group's animation completes or is dismissed.
  void _onOperationGroupStatusChange(
    TKey operationKey,
    AnimationStatus status,
  ) {
    final group = _operationGroups[operationKey];
    if (group == null) {
      return;
    }

    if (status == AnimationStatus.completed) {
      // Expansion done (value = 1). Remove group, clean up maps.
      // No structural notification: the subtree was inserted into _order at
      // expand() call time and already notified then. This status flip is
      // animation bookkeeping — the widget tree sees no change, so firing
      // notifyListeners here would force SliverTreeElement to rebuild every
      // mounted row for nothing.
      for (final nodeId in group.members.keys) {
        _clearOperationGroup(nodeId);
      }
      _operationGroups.remove(operationKey);
      _bumpAnimGen();
      group.dispose();
    } else if (status == AnimationStatus.dismissed) {
      // Collapse done (value = 0). Remove nodes from visible order.
      //
      // pendingRemoval splits into two semantic categories:
      //   (1) _pendingDeletion members: fully purge (unlink → cache
      //       decrement → release nid). Order compaction is batched.
      //   (2) Others: structurally still present; just leave _order if
      //       their ancestors are no longer expanded. No purge.
      //
      // Both categories funnel into _keysToRemoveScratch for one
      // batched _removeFromVisibleOrder call afterwards.
      _keysToRemoveScratch.clear();
      final categoryOne = <TKey>[];
      final parentsOfCategoryOne = <TKey>{};
      for (final nodeId in group.pendingRemoval) {
        if (_isPendingDeletion(nodeId)) {
          categoryOne.add(nodeId);
          final parentKey = _parentKeyOfKey(nodeId);
          if (parentKey != null) {
            parentsOfCategoryOne.add(parentKey);
          }
        } else {
          final parentKey = _parentKeyOfKey(nodeId);
          final shouldRemove = parentKey == null
              ? !_roots.contains(nodeId)
              : !_ancestorsExpandedFast(nodeId);
          if (shouldRemove) {
            _keysToRemoveScratch.add(nodeId);
          }
        }
        _clearOperationGroup(nodeId);
      }

      // Process category (1) via the unified helper, deferring order
      // compaction so it batches with category (2) below.
      final affectedParents = <TKey>{};
      if (categoryOne.isNotEmpty) {
        _purgeAndRemoveFromOrder(categoryOne, compactOrder: false);
        // Detect parents whose child list became empty as a result.
        // The helper purged the children and released their nids; the
        // captured parents may themselves have been purged (their key
        // looked up returns null). _childListOf handles unregistered
        // keys by returning null — treat that as "child list empty"
        // for the affectedKeys signal (a dead key in affectedKeys is a
        // cheap no-op at the element side).
        for (final parent in parentsOfCategoryOne) {
          final siblings = _childListOf(parent);
          if (siblings == null || siblings.isEmpty) {
            affectedParents.add(parent);
          }
        }
        _keysToRemoveScratch.addAll(categoryOne);
      }

      // Clean up remaining members not in pendingRemoval
      for (final nodeId in group.members.keys) {
        _clearOperationGroup(nodeId);
      }
      bool didMutateOrder = false;
      if (_keysToRemoveScratch.isNotEmpty) {
        _removeFromVisibleOrder(_keysToRemoveScratch);
        _structureGeneration++;
        didMutateOrder = true;
      }
      _operationGroups.remove(operationKey);
      _bumpAnimGen();
      group.dispose();
      // Only notify when visible order actually changed. If every pending-
      // removal member was already hidden (ancestor re-collapsed mid-flight,
      // reparented, etc.), this branch is structurally a no-op.
      //
      // Affected keys: parents whose hasChildren flipped false. Removed
      // rows are GC'd by SliverTreeElement. Remaining visible rows retain
      // their builder output (depth/data/parent unchanged).
      if (didMutateOrder) {
        _notifyStructural(affectedKeys: affectedParents);
      }
    }
  }

  void _startStandaloneEnterAnimation(TKey key, {TKey? triggeringAncestorId}) {
    // Capture current animated extent from any source BEFORE removing
    final capturedExtent = _captureAndRemoveFromGroups(key);
    final startExtent = capturedExtent ?? 0.0;
    final targetExtent = _fullExtentOf(key) ?? _unknownExtent;

    // Compute speed multiplier for proportional timing
    final full = _fullExtentOf(key) ?? TreeController.defaultExtent;
    final speedMultiplier = startExtent > 0
        ? _computeAnimationSpeedMultiplier(full - startExtent, full)
        : 1.0;

    _setStandalone(
      key,
      AnimationState(
        type: AnimationType.entering,
        startExtent: startExtent,
        targetExtent: targetExtent,
        triggeringAncestorId: triggeringAncestorId,
        speedMultiplier: speedMultiplier,
      ),
    );
    _bumpAnimGen();
    _ensureStandaloneTickerRunning();
  }

  /// Cancels a pending deletion for a node and all its descendants.
  ///
  /// Reverses the exit animation of [key] into an enter animation so the
  /// re-inserted node animates back in.
  ///
  /// Descendant handling has three branches:
  ///
  /// 1. [preserveSubtreeState] is true AND the descendant was mid-exit AND
  ///    its ancestor chain is expanded: reverse its exit into an enter so
  ///    the whole subtree animates back in coherently with [key].
  /// 2. The descendant was mid-exit but case 1 does not apply: clear its
  ///    pending-deletion marker but leave the exit animation running so the
  ///    row shrinks away smoothly under the restored (collapsed) parent.
  ///    Yanking the animation here would drop the descendant's current
  ///    extent from the visible order in a single frame, jumping every
  ///    following row upward. Because pending-deletion is cleared,
  ///    [_finalizeAnimation] takes the non-deleted branch and only removes
  ///    the descendant from the visible order, preserving its structural
  ///    data so an ancestor re-expand can restore it.
  /// 3. The descendant had no active exit animation (e.g. it was under a
  ///    collapsed ancestor when the remove started, or it was a
  ///    just-adopted zombie): clear its pending-deletion marker and any
  ///    residual animation state. Nothing is visible to disrupt.
  void _cancelDeletion(
    TKey key, {
    bool animate = true,
    bool preserveSubtreeState = false,
  }) {
    if (animationDuration == Duration.zero) {
      animate = false;
    }
    _clearPendingDeletion(key);
    if (animate) {
      _startStandaloneEnterAnimation(key);
    } else {
      _removeAnimation(key);
    }
    final descendants = _getDescendants(key);
    for (final nodeId in descendants) {
      if (!animate) {
        _clearPendingDeletion(nodeId);
        _removeAnimation(nodeId);
        continue;
      }
      final animation = _standaloneAt(nodeId);
      final isExitingDescendant =
          animation != null && animation.type == AnimationType.exiting;
      if (preserveSubtreeState &&
          isExitingDescendant &&
          _ancestorsExpandedFast(nodeId)) {
        _clearPendingDeletion(nodeId);
        _startStandaloneEnterAnimation(nodeId);
      } else if (isExitingDescendant) {
        // Case 2: clear pending-deletion so _finalizeAnimation preserves the
        // node's structural data, but let the exit animation run to
        // completion so the visible row shrinks away smoothly.
        _clearPendingDeletion(nodeId);
      } else {
        _clearPendingDeletion(nodeId);
        _removeAnimation(nodeId);
      }
    }
  }

  void _startStandaloneExitAnimation(TKey key, {TKey? triggeringAncestorId}) {
    // Capture current animated extent from any source BEFORE removing
    final capturedExtent = _captureAndRemoveFromGroups(key);
    final currentExtent = capturedExtent ?? (_fullExtentOf(key) ?? 0.0);

    // Compute speed multiplier for proportional timing
    final full = _fullExtentOf(key) ?? TreeController.defaultExtent;
    final speedMultiplier = _computeAnimationSpeedMultiplier(
      currentExtent,
      full,
    );

    _setStandalone(
      key,
      AnimationState(
        type: AnimationType.exiting,
        startExtent: currentExtent,
        targetExtent: 0.0,
        triggeringAncestorId: triggeringAncestorId,
        speedMultiplier: speedMultiplier,
      ),
    );
    _bumpAnimGen();
    _ensureStandaloneTickerRunning();
  }

  /// Ensures the standalone animation ticker is running.
  void _ensureStandaloneTickerRunning() {
    _standaloneTicker ??= _vsync.createTicker(_onStandaloneTick);
    if (!_standaloneTicker!.isActive) {
      _lastStandaloneTickTime = null;
      _standaloneTicker!.start();
    }
  }

  /// Ticker callback for standalone (individual) animations only.
  /// Bulk and operation group animations are driven by AnimationController.
  void _onStandaloneTick(Duration elapsed) {
    if (!_hasAnyStandalone) {
      _standaloneTicker?.stop();
      return;
    }
    if (animationDuration.inMicroseconds == 0) {
      _standaloneTicker?.stop();
      return;
    }

    final dt = _lastStandaloneTickTime == null
        ? Duration.zero
        : elapsed - _lastStandaloneTickTime!;
    _lastStandaloneTickTime = elapsed;
    final progressDelta = dt.inMicroseconds / animationDuration.inMicroseconds;

    // Process standalone animations. Iterate the working set rather than
    // scanning the dense array — most slots are null in steady state, and
    // the working set tracks exactly the live ones.
    final completed = <TKey>[];
    for (final nid in _activeStandaloneNids) {
      final state = _standaloneByNid[nid]!;
      state.progress += progressDelta * state.speedMultiplier;
      state.updateExtent(animationCurve);
      if (state.isComplete) {
        completed.add(_nids.keyOfUnchecked(nid));
      }
    }

    // Finalize completed standalone animations.
    //
    // Capture parents of pending-deletion keys before calling
    // _finalizeAnimation — that method purges the key (releasing its nid),
    // so _parentKeyOfKey would return null afterwards.
    final parentBeforeFinalize = <TKey, TKey>{};
    for (final key in completed) {
      if (_isPendingDeletion(key)) {
        final parent = _parentKeyOfKey(key);
        if (parent != null) {
          parentBeforeFinalize[key] = parent;
        }
      }
    }

    _keysToRemoveScratch.clear();
    final affectedParents = <TKey>{};
    for (final key in completed) {
      if (_finalizeAnimation(key)) {
        _keysToRemoveScratch.add(key);
        // After finalize, check if the captured parent's child list is
        // now empty → its hasChildren flipped false. Parent may itself
        // be pending-deletion (purged by a sibling's finalize); in that
        // case _childListOf returns null and we record it anyway — a
        // dead key in affectedKeys is a cheap no-op at the element side.
        final parent = parentBeforeFinalize[key];
        if (parent != null) {
          final siblings = _childListOf(parent);
          if (siblings == null || siblings.isEmpty) {
            affectedParents.add(parent);
          }
        }
      }
    }

    if (_keysToRemoveScratch.isNotEmpty) {
      _removeFromVisibleOrder(_keysToRemoveScratch);
      _structureGeneration++;
      _notifyStructural(affectedKeys: affectedParents);
    }

    _notifyAnimationListeners();

    // Stop ticker if no more standalone animations
    if (!_hasAnyStandalone) {
      _standaloneTicker?.stop();
    }
  }

  bool _finalizeAnimation(TKey key) {
    final state = _clearStandalone(key);
    if (state == null) {
      return false;
    }
    _bumpAnimGen();

    if (state.type == AnimationType.exiting) {
      final isDeleted = _isPendingDeletion(key);
      if (isDeleted) {
        // Fully remove the node from all data structures
        final parentKey = _parentKeyOfKey(key);
        if (parentKey != null) {
          _childListOf(parentKey)?.remove(key);
        } else {
          _roots.remove(key);
        }
        // Also purge descendants that were pending deletion but never got
        // their own exit animation (invisible children of a collapsed node).
        // Must collect before purging `key`, since _getDescendants reads
        // _childListOf(key).
        final descendants = _getDescendants(key);

        // Decrement the visible-subtree-size cache up the parent chain
        // BEFORE any purge releases the nids. The actual removal of
        // entries from _orderNids is deferred and batched in
        // _removeFromVisibleOrder, but by then _releaseNid has cleared
        // _parentByNid for every released nid — the visibility-loss
        // callback fired from the deferred removal would walk a broken
        // parent chain and never reach the real ancestors. Doing the
        // bookkeeping here, while parent links are still intact,
        // preserves the cache invariant.
        //
        // Visible loss = key (if visible) + every visible pending-deletion
        // descendant. Descendants with their own in-flight animation are
        // counted here too: when they later finalize, their parent slot
        // points to this nid (which is about to be freed), so
        // _parentKeyOfKey returns null and their own visibleLoss block
        // is skipped. Without pre-counting them here, the ancestor's
        // cache would stay inflated by the descendant count forever.
        if (parentKey != null) {
          int visibleLoss = 0;
          final keyNid = _nids[key];
          if (keyNid != null &&
              _order.indexByNid[keyNid] != VisibleOrderBuffer.kNotVisible) {
            visibleLoss++;
          }
          for (final desc in descendants) {
            if (_isPendingDeletion(desc)) {
              final descNid = _nids[desc];
              if (descNid != null &&
                  _order.indexByNid[descNid] !=
                      VisibleOrderBuffer.kNotVisible) {
                visibleLoss++;
              }
            }
          }
          if (visibleLoss > 0) {
            final parentNid = _nids[parentKey];
            if (parentNid != null) {
              _bumpVisibleSubtreeSizeFromSelf(parentNid, -visibleLoss);
            }
          }
        }

        // Skip _visibleOrder.remove — caller batches it
        _purgeNodeData(key);
        for (final desc in descendants) {
          // Only purge orphans that have no active exit animation.
          // Visible descendants with their own animation will finalize
          // themselves when their animation completes.
          if (_isPendingDeletion(desc) &&
              !_hasStandalone(desc)) {
            _purgeNodeData(desc);
          }
        }
        return true;
      } else {
        // Node is exiting due to ancestor collapse - remove from visible order
        // if ancestors are still collapsed
        final parentKey = _parentKeyOfKey(key);
        final shouldRemove = parentKey == null
            ? !_roots.contains(key)
            : !_ancestorsExpandedFast(key);
        return shouldRemove;
        // If all ancestors are expanded, the node should stay visible (user re-expanded mid-collapse)
      }
    }

    // Safety net: if an entering node is pending deletion (shouldn't happen
    // with the guards in collectRecursive and addSubtree, but defend against
    // other code paths), purge it. Order compaction is deferred to the
    // caller's batched _removeFromVisibleOrder; we just signal via
    // `return true` that the key should be added to that batch.
    if (_isPendingDeletion(key)) {
      _purgeAndRemoveFromOrder([key], compactOrder: false);
      return true;
    }

    return false;
  }

  /// Inserts [nodeId] into the visible order at the DFS position implied by
  /// its place among its real parent's children list. Used when restoring
  /// visibility to a node whose siblings may already be in the visible order
  /// (e.g. re-expanding a collapsing operation group after a mid-collapse
  /// insert). Falls back to a no-op if the node's parent isn't visible.
  void _insertNewNodeAmongSiblings(TKey nodeId) {
    final parent = _parentKeyOfKey(nodeId);
    if (parent == null) {
      return;
    }
    final parentVisibleIndex = _order.indexOf(parent);
    if (parentVisibleIndex == VisibleOrderBuffer.kNotVisible) {
      return;
    }
    final siblings = _childListOf(parent);
    int insertIndex = parentVisibleIndex + 1;
    if (siblings != null) {
      // Fast path via [_visibleSubtreeSizeByNid]: one O(1) cache read
      // per prior sibling instead of the former O(visibleSubtreeSize)
      // `_countVisibleDescendants` walk inside an O(siblingIndex)
      // loop. Keeps re-expansion of an operation group linear in the
      // sibling count regardless of per-sibling subtree depth.
      for (final sib in siblings) {
        if (sib == nodeId) {
          break;
        }
        final sibNid = _nids[sib];
        if (sibNid != null) {
          insertIndex += _visibleSubtreeSizeByNid[sibNid];
        }
      }
    }
    _order.insertKey(insertIndex, nodeId);
    _updateIndicesFrom(insertIndex);
  }
}
