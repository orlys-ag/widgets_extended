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
  /// Computes the visible extent for a standalone [AnimationState],
  /// matching the read path in [getCurrentExtentNid]. When the
  /// state's `targetExtent` is unknown (the row hasn't been measured
  /// yet), [AnimationState.currentExtent] holds `lerp(0, -1, t) = -t`
  /// — a stale, negative value that bypasses the proportional
  /// fallback. Capture sites must use this helper instead of reading
  /// `state.currentExtent` directly, otherwise the captured value
  /// becomes a negative number and corrupts a downstream op-group
  /// member's envelope.
  double _standaloneVisibleExtent(TKey key, AnimationState state) {
    if (state.targetExtent != _unknownExtent) {
      return state.currentExtent;
    }
    final full = _fullExtentOf(key) ?? TreeController.defaultExtent;
    final t = animationCurve.transform(state.progress.clamp(0.0, 1.0));
    return state.type == AnimationType.entering ? full * t : full * (1.0 - t);
  }

  /// Captures a node's current animated extent from whichever source it's in,
  /// removes it from that source, and returns the extent (or null if not animating).
  double? _captureAndRemoveFromGroups(TKey key) {
    // 1. Check operation group
    final opGroupKey = _operationGroupOf(key);
    if (opGroupKey != null) {
      final group = _opGroupAt(opGroupKey);
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
    if (_activeBulkGroup?.members.contains(key) == true) {
      final full = _fullExtentOf(key) ?? TreeController.defaultExtent;
      final extent = full * _activeBulkGroup!.value;
      _removeBulkMember(key);
      _removeBulkPending(key);
      _bumpBulkGen();
      return extent;
    }

    // 3. Check standalone animations
    final standalone = _clearStandalone(key);
    if (standalone != null) {
      _bumpAnimGen();
      return _standaloneVisibleExtent(key, standalone);
    }

    return null;
  }

  // Plan A: _disposeOperationGroupIfEmpty and _installOperationGroup
  // moved into OperationGroupRegistry (disposeIfEmpty, install). The
  // controller-side forwarder for _disposeOperationGroupIfEmpty is in
  // tree_controller.dart; the install callers (Path-2 fresh-expand /
  // fresh-collapse in expand() and collapse()) call _anim.opGroups.install
  // directly with the appropriate initialValue.

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
  /// **Pending-deletion deferral (animated path).** When [cancelSlides] is
  /// false (i.e. `moveNode(animate: true)`), members where
  /// [_isPendingDeletion] is true are skipped entirely — pending-deletion
  /// is NOT cleared and the standalone exit state is NOT removed. The
  /// caller is responsible for invoking [_revertSubtreeFromPendingDeletion]
  /// AFTER the structural reparent so the case-1/2/3 policy can read the
  /// post-mutation ancestor chain. This composes a smooth extent reversal
  /// with the FLIP slide instead of snapping the row to full extent.
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
  void _cancelAnimationStateForSubtree(
    TKey key, {
    bool cancelSlides = true,
  }) {
    final preservedOpKeys = <TKey>{};
    final stack = <TKey>[key];
    while (stack.isNotEmpty) {
      final nodeId = stack.removeLast();

      // Add to preservedOpKeys BEFORE the detach branch so the lookup
      // `preservedOpKeys.contains(opGroupKey)` below resolves correctly
      // for nodes whose op-group's operationKey IS this node (rare but
      // possible in principle; harmless in practice since
      // _nodeToOperationGroup never points a member at itself).
      if (_opGroupAt(nodeId) != null) {
        preservedOpKeys.add(nodeId);
      }

      // Defer pending-deletion cleanup on the animated path so Phase B
      // (`_revertSubtreeFromPendingDeletion`, called by `moveNode` after
      // structural reparent) can apply the case-1/2/3 policy with
      // post-mutation ancestor visibility. Pending-deletion is set only by
      // `remove()` and always pairs with a standalone exit — no op-group
      // entanglement, so this skip is safe alongside the preservedOpKeys
      // logic below.
      final defer = !cancelSlides && _isPendingDeletion(nodeId);

      if (!defer) {
        _clearPendingDeletion(nodeId);
      }
      // Slide cancellation is conditional — when the caller is
      // `moveNode(animate: true)`, the staged baseline already captured
      // the row's mid-flight painted position (structural + currentDelta),
      // and the next consume will COMPOSE the existing slide toward the
      // new destination. Cancelling here would force the consume's
      // post-mutation snapshot to read `slideY = 0`, masking the in-
      // flight state from `_applyClampAndInstallNewGhosts` — its both-
      // off-screen guard would then suppress what should have been a
      // composition install, and the row would jump structurally with
      // no visible animation.
      if (cancelSlides) {
        _slide.cancelForKey(nodeId);
      }

      final opGroupKey = _operationGroupOf(nodeId);
      if (opGroupKey != null && preservedOpKeys.contains(opGroupKey)) {
        // Member of a preserved op group — keep its op-group state intact
        // so the animation continues against the post-move position.
        // Still detach from standalone / bulk sources defensively: a node
        // shouldn't be in both an op group and another source, but any
        // residue would otherwise drive a stray animation anchored to the
        // pre-move layout. (Skip standalone clearing on the deferred path
        // so Phase B can read the in-flight exit state.)
        if (!defer) {
          if (_clearStandalone(nodeId) != null) {
            _bumpAnimGen();
          }
        }
        final bulk = _activeBulkGroup;
        if (bulk != null) {
          final removedMember = _removeBulkMember(nodeId);
          final removedPending = _removeBulkPending(nodeId);
          if (removedMember || removedPending) {
            _bumpBulkGen();
          }
        }
      } else if (!defer) {
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
      _anim.standalone.stop();
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
      final group = _opGroupAt(opGroupKey);
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
    final bulk = _activeBulkGroup;
    if (bulk != null) {
      final removedMember = _removeBulkMember(key);
      final removedPending = _removeBulkPending(key);
      if (removedMember || removedPending) {
        _bumpBulkGen();
      }
    }
    return state;
  }

  // Plan A: _createBulkAnimationGroup and _disposeBulkAnimationGroup
  // moved into BulkAnimator (createGroup, disposeGroup). The
  // controller-side forwarder for _disposeBulkAnimationGroup is in
  // tree_controller.dart; the create-group callers (expandAll /
  // collapseAll fresh-group branches) call _anim.bulk.createGroup
  // directly with the appropriate initialValue.

  /// Called when the bulk animation completes or is dismissed. The
  /// [_unusedStatus] parameter matches the BulkAnimator's onStatusChanged
  /// callback contract; the body reads the status from the controller
  /// directly (matching today's flow).
  void _onBulkAnimationComplete([AnimationStatus? _unusedStatus]) {
    if (_activeBulkGroup == null) {
      return;
    }
    final controller = _activeBulkGroup!.controller;
    bool didMutateOrder = false;
    // If dismissed (value = 0), remove nodes marked for removal
    if (controller.status == AnimationStatus.dismissed) {
      _keysToRemoveScratch.clear();
      for (final key in _activeBulkGroup!.pendingRemoval) {
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
    final group = _opGroupAt(operationKey);
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
      //
      for (final nodeId in group.members.keys) {
        _clearOperationGroup(nodeId);
      }
      // Group disposal happens inside removeGroup (which also clears the
      // reverse-index slot for any straggling members). _clearOperationGroup
      // calls above already handled the membership; this just tears down
      // the controller.
      _anim.opGroups.removeGroup(operationKey);
      _bumpAnimGen();
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
      // Group disposal happens inside removeGroup (which also clears the
      // reverse-index slot for any straggling members). _clearOperationGroup
      // calls above already handled the membership; this just tears down
      // the controller.
      _anim.opGroups.removeGroup(operationKey);
      _bumpAnimGen();
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
    _anim.standalone.ensureRunning();
  }

  /// Cancels a pending deletion for a node and all its descendants.
  ///
  /// Reverses the exit animation of [key] into an enter animation so the
  /// re-inserted node animates back in. The root is always reversed (the
  /// caller explicitly requested cancellation); descendants are routed
  /// through [_revertSinglePendingDeletion] for the case-1/2/3 policy.
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
      _revertSinglePendingDeletion(
        nodeId,
        preserveSubtreeState: preserveSubtreeState,
      );
    }
  }

  /// Reverts pending-deletion state for an entire subtree, applying the
  /// case-1/2/3 policy to every member where [_isPendingDeletion] is true.
  /// Non-pending members are left untouched.
  ///
  /// Reads post-mutation [_ancestorsExpandedFast]; callers must invoke this
  /// AFTER any structural reparent so the visibility check reflects the
  /// new ancestor chain. Used by [moveNode] to compose a smooth extent
  /// reversal with the FLIP slide for a moved subtree whose members were
  /// mid-exit at the time of the move.
  void _revertSubtreeFromPendingDeletion(TKey rootKey) {
    final keys = <TKey>[rootKey, ..._getDescendants(rootKey)];
    for (final nodeId in keys) {
      _revertSinglePendingDeletion(nodeId, preserveSubtreeState: true);
    }
  }

  /// Per-node case-1/2/3 policy for reverting a pending-deletion node.
  ///
  /// 1. [preserveSubtreeState] is true AND the node was mid-exit AND its
  ///    ancestor chain is expanded: reverse the exit into an enter
  ///    animation so the row animates back in from its current extent.
  ///    [_startStandaloneEnterAnimation] also detaches the node from any
  ///    bulk/op group via [_captureAndRemoveFromGroups].
  /// 2. The node was mid-exit but case 1 does not apply: clear its
  ///    pending-deletion marker but leave the exit animation running so the
  ///    row shrinks away smoothly under its (collapsed) ancestor chain.
  ///    Yanking the animation here would drop the row's current extent
  ///    from the visible order in a single frame, jumping every following
  ///    row upward. With pending-deletion cleared, [_finalizeAnimation]
  ///    takes the non-deleted branch and only removes the node from the
  ///    visible order, preserving its structural data so an ancestor
  ///    re-expand can restore it.
  /// 3. The node had no active standalone exit (e.g. member of a bulk/op
  ///    exit group, or under a collapsed ancestor when the remove started):
  ///    clear pending-deletion and detach from any group via
  ///    [_removeAnimation] so the group's completion handler doesn't try to
  ///    purge a row that has been adopted elsewhere.
  ///
  /// No-op if the node is not pending-deletion. Callers can pass any subtree
  /// member without filtering first.
  void _revertSinglePendingDeletion(
    TKey nodeId, {
    required bool preserveSubtreeState,
  }) {
    if (!_isPendingDeletion(nodeId)) {
      return;
    }
    final animation = _standaloneAt(nodeId);
    final isStandaloneExiting =
        animation != null && animation.type == AnimationType.exiting;
    if (preserveSubtreeState &&
        isStandaloneExiting &&
        _ancestorsExpandedFast(nodeId)) {
      _clearPendingDeletion(nodeId);
      _startStandaloneEnterAnimation(nodeId);
    } else if (isStandaloneExiting) {
      _clearPendingDeletion(nodeId);
    } else {
      _clearPendingDeletion(nodeId);
      _removeAnimation(nodeId);
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
    _anim.standalone.ensureRunning();
  }

  // Plan A: _ensureStandaloneTickerRunning and _onStandaloneTick moved
  // into StandaloneAnimator (ensureRunning, _runTick). The
  // controller-side completion handler is `_onStandaloneTickComplete`
  // (constructor-injected into the AnimationCoordinator), which receives
  // the completed-key list and drives `_finalizeAnimation` per key,
  // batches the order removal, fires the structural notification.

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
              _order.bumpFromSelf(parentNid, -visibleLoss);
            }
          }
        }

        // Skip _visibleOrder.remove — caller batches it
        _purgeNodeData(key);
        for (final desc in descendants) {
          // Only purge orphans that have no active exit animation.
          // Visible descendants with their own animation will finalize
          // themselves when their animation completes.
          if (_isPendingDeletion(desc) && !_hasStandalone(desc)) {
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
      // Fast path via [VisibleOrderBuffer.subtreeSizeOf]: one O(1) cache
      // read per prior sibling instead of the former
      // O(visibleSubtreeSize) `_countVisibleDescendants` walk inside an
      // O(siblingIndex) loop. Keeps re-expansion of an operation group
      // linear in the sibling count regardless of per-sibling subtree depth.
      for (final sib in siblings) {
        if (sib == nodeId) {
          break;
        }
        final sibNid = _nids[sib];
        if (sibNid != null) {
          insertIndex += _order.subtreeSizeOf(sibNid);
        }
      }
    }
    _order.insertKey(insertIndex, nodeId);
    _updateIndicesFrom(insertIndex);
  }
}
