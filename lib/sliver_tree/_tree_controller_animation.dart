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
    final opGroupKey = _nodeToOperationGroup[key];
    if (opGroupKey != null) {
      final group = _operationGroups[opGroupKey];
      if (group != null) {
        final member = group.members[key];
        if (member != null) {
          final full = _fullExtents[key] ?? TreeController.defaultExtent;
          final extent = member.computeExtent(group.curvedValue, full);
          group.members.remove(key);
          group.pendingRemoval.remove(key);
          _nodeToOperationGroup.remove(key);
          _disposeOperationGroupIfEmpty(opGroupKey, group);
          return extent;
        }
      }
      _nodeToOperationGroup.remove(key);
    }

    // 2. Check bulk animation group
    if (_bulkAnimationGroup?.members.contains(key) == true) {
      final full = _fullExtents[key] ?? TreeController.defaultExtent;
      final extent = full * _bulkAnimationGroup!.value;
      _bulkAnimationGroup!.members.remove(key);
      _bulkAnimationGroup!.pendingRemoval.remove(key);
      _bulkAnimationGeneration++;
      return extent;
    }

    // 3. Check standalone animations
    final standalone = _standaloneAnimations.remove(key);
    if (standalone != null) {
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
    group.dispose();
  }

  /// Cancels pending-deletion and all animation state for [key] and all
  /// of its descendants. Intended for use when a subtree is reparented —
  /// its prior animation state was computed against the old position and
  /// must not continue to drive finalize/purge after the move.
  void _cancelAnimationStateForSubtree(TKey key) {
    // Also dispose any OperationGroup whose operationKey is inside the moved
    // subtree. Its controller would otherwise keep running and, on dismiss,
    // remove the (now relocated) members from _visibleOrder — destroying the
    // moved subtree under its new parent.
    final subtreeGroupKeys = <TKey>[];
    void visit(TKey nodeId) {
      _pendingDeletion.remove(nodeId);
      if (_operationGroups.containsKey(nodeId)) {
        subtreeGroupKeys.add(nodeId);
      }
      _removeAnimation(nodeId);
      final children = _childListOf(nodeId);
      if (children != null) {
        for (final child in children) {
          visit(child);
        }
      }
    }

    visit(key);

    for (final groupKey in subtreeGroupKeys) {
      final group = _operationGroups.remove(groupKey);
      if (group == null) {
        continue;
      }
      for (final member in group.members.keys) {
        if (_nodeToOperationGroup[member] == groupKey) {
          _nodeToOperationGroup.remove(member);
        }
      }
      group.dispose();
    }

    if (_standaloneAnimations.isEmpty) {
      _standaloneTicker?.stop();
    }
  }

  /// Removes an animation from all sources and cleans up group membership.
  AnimationState? _removeAnimation(TKey key) {
    final state = _standaloneAnimations.remove(key);
    // Remove from operation group
    final opGroupKey = _nodeToOperationGroup.remove(key);
    if (opGroupKey != null) {
      final group = _operationGroups[opGroupKey];
      if (group != null) {
        group.members.remove(key);
        group.pendingRemoval.remove(key);
        _disposeOperationGroupIfEmpty(opGroupKey, group);
      }
    }
    // Also remove from bulk animation group
    final bulk = _bulkAnimationGroup;
    if (bulk != null) {
      final removedMember = bulk.members.remove(key);
      final removedPending = bulk.pendingRemoval.remove(key);
      if (removedMember || removedPending) {
        _bulkAnimationGeneration++;
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

    _bulkAnimationGeneration++;
    return group;
  }

  /// Disposes the current bulk animation group if it exists.
  void _disposeBulkAnimationGroup() {
    final group = _bulkAnimationGroup;
    // Set to null first to prevent callback interference
    _bulkAnimationGroup = null;
    if (group != null) {
      _bulkAnimationGeneration++;
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
        if (!_pendingDeletion.contains(key)) {
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
    if (didMutateOrder) {
      _notifyStructural();
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
        _nodeToOperationGroup.remove(nodeId);
      }
      _operationGroups.remove(operationKey);
      group.dispose();
    } else if (status == AnimationStatus.dismissed) {
      // Collapse done (value = 0). Remove nodes from visible order.
      _keysToRemoveScratch.clear();
      for (final nodeId in group.pendingRemoval) {
        if (_pendingDeletion.contains(nodeId)) {
          // Fully remove the node from all data structures
          final parentKey = _parentKeyOfKey(nodeId);
          if (parentKey != null) {
            _childListOf(parentKey)?.remove(nodeId);
          } else {
            _roots.remove(nodeId);
          }
          _nodeToOperationGroup.remove(nodeId);
          _purgeNodeData(nodeId);
          _keysToRemoveScratch.add(nodeId);
        } else {
          final parentKey = _parentKeyOfKey(nodeId);
          final shouldRemove = parentKey == null
              ? !_roots.contains(nodeId)
              : !_ancestorsExpandedFast(nodeId);
          if (shouldRemove) {
            _keysToRemoveScratch.add(nodeId);
          }
          _nodeToOperationGroup.remove(nodeId);
        }
      }
      // Clean up remaining members not in pendingRemoval
      for (final nodeId in group.members.keys) {
        _nodeToOperationGroup.remove(nodeId);
      }
      bool didMutateOrder = false;
      if (_keysToRemoveScratch.isNotEmpty) {
        _removeFromVisibleOrder(_keysToRemoveScratch);
        _structureGeneration++;
        didMutateOrder = true;
      }
      _operationGroups.remove(operationKey);
      group.dispose();
      // Only notify when visible order actually changed. If every pending-
      // removal member was already hidden (ancestor re-collapsed mid-flight,
      // reparented, etc.), this branch is structurally a no-op.
      if (didMutateOrder) {
        _notifyStructural();
      }
    }
  }

  void _startStandaloneEnterAnimation(TKey key, {TKey? triggeringAncestorId}) {
    // Capture current animated extent from any source BEFORE removing
    final capturedExtent = _captureAndRemoveFromGroups(key);
    final startExtent = capturedExtent ?? 0.0;
    final targetExtent = _fullExtents[key] ?? _unknownExtent;

    // Compute speed multiplier for proportional timing
    final full = _fullExtents[key] ?? TreeController.defaultExtent;
    final speedMultiplier = startExtent > 0
        ? _computeAnimationSpeedMultiplier(full - startExtent, full)
        : 1.0;

    _standaloneAnimations[key] = AnimationState(
      type: AnimationType.entering,
      startExtent: startExtent,
      targetExtent: targetExtent,
      triggeringAncestorId: triggeringAncestorId,
      speedMultiplier: speedMultiplier,
    );
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
    _pendingDeletion.remove(key);
    if (animate) {
      _startStandaloneEnterAnimation(key);
    } else {
      _removeAnimation(key);
    }
    final descendants = _getDescendants(key);
    for (final nodeId in descendants) {
      if (!animate) {
        _pendingDeletion.remove(nodeId);
        _removeAnimation(nodeId);
        continue;
      }
      final animation = _standaloneAnimations[nodeId];
      final isExitingDescendant =
          animation != null && animation.type == AnimationType.exiting;
      if (preserveSubtreeState &&
          isExitingDescendant &&
          _ancestorsExpandedFast(nodeId)) {
        _pendingDeletion.remove(nodeId);
        _startStandaloneEnterAnimation(nodeId);
      } else if (isExitingDescendant) {
        // Case 2: clear pending-deletion so _finalizeAnimation preserves the
        // node's structural data, but let the exit animation run to
        // completion so the visible row shrinks away smoothly.
        _pendingDeletion.remove(nodeId);
      } else {
        _pendingDeletion.remove(nodeId);
        _removeAnimation(nodeId);
      }
    }
  }

  void _startStandaloneExitAnimation(TKey key, {TKey? triggeringAncestorId}) {
    // Capture current animated extent from any source BEFORE removing
    final capturedExtent = _captureAndRemoveFromGroups(key);
    final currentExtent = capturedExtent ?? (_fullExtents[key] ?? 0.0);

    // Compute speed multiplier for proportional timing
    final full = _fullExtents[key] ?? TreeController.defaultExtent;
    final speedMultiplier = _computeAnimationSpeedMultiplier(
      currentExtent,
      full,
    );

    _standaloneAnimations[key] = AnimationState(
      type: AnimationType.exiting,
      startExtent: currentExtent,
      targetExtent: 0.0,
      triggeringAncestorId: triggeringAncestorId,
      speedMultiplier: speedMultiplier,
    );
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
    if (_standaloneAnimations.isEmpty) {
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

    // Process standalone animations
    final completed = <TKey>[];
    for (final entry in _standaloneAnimations.entries) {
      final state = entry.value;
      state.progress += progressDelta * state.speedMultiplier;
      state.updateExtent(animationCurve);
      if (state.isComplete) {
        completed.add(entry.key);
      }
    }

    // Finalize completed standalone animations
    _keysToRemoveScratch.clear();
    for (final key in completed) {
      if (_finalizeAnimation(key)) {
        _keysToRemoveScratch.add(key);
      }
    }

    if (_keysToRemoveScratch.isNotEmpty) {
      _removeFromVisibleOrder(_keysToRemoveScratch);
      _structureGeneration++;
      _notifyStructural();
    }

    _notifyAnimationListeners();

    // Stop ticker if no more standalone animations
    if (_standaloneAnimations.isEmpty) {
      _standaloneTicker?.stop();
    }
  }

  bool _finalizeAnimation(TKey key) {
    final state = _standaloneAnimations.remove(key);
    if (state == null) {
      return false;
    }

    if (state.type == AnimationType.exiting) {
      final isDeleted = _pendingDeletion.contains(key);
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
        // Skip _visibleOrder.remove — caller batches it
        _purgeNodeData(key);
        for (final desc in descendants) {
          // Only purge orphans that have no active exit animation.
          // Visible descendants with their own animation will finalize
          // themselves when their animation completes.
          if (_pendingDeletion.contains(desc) &&
              !_standaloneAnimations.containsKey(desc)) {
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
    // other code paths), purge it.
    if (_pendingDeletion.contains(key)) {
      final parentKey = _parentKeyOfKey(key);
      if (parentKey != null) {
        _childListOf(parentKey)?.remove(key);
      } else {
        _roots.remove(key);
      }
      _purgeNodeData(key);
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
      for (final sib in siblings) {
        if (sib == nodeId) {
          break;
        }
        final sibIdx = _order.indexOf(sib);
        if (sibIdx != VisibleOrderBuffer.kNotVisible) {
          insertIndex = sibIdx + 1 + _countVisibleDescendants(sib);
        }
      }
    }
    _order.insertKey(insertIndex, nodeId);
    _updateIndicesFrom(insertIndex);
  }
}
