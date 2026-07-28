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

import 'package:flutter/foundation.dart';

import 'tree_controller.dart';
import 'types.dart';

/// A controller that syncs a [TreeController] to a desired state using
/// animated diffs.
///
/// This controller does not own the [TreeController] — it drives it.
/// Dispose this controller before disposing the underlying [TreeController].
///
/// **Composes with direct controller mutations.** Every diff reads the
/// controller's live state ([TreeController.liveRootKeys] /
/// [TreeController.getLiveChildren]) as its "current" baseline, so
/// structural mutations that bypass this controller — imperative
/// `insert`/`remove`/`moveNode` calls through an escape-hatch reference,
/// or [TreeReorderController] committing a drag-drop — are simply the new
/// baseline for the next sync. No resync hook is needed.
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

  /// Parents whose child list was emptied by a sync while the parent
  /// itself survived **collapsed** (e.g. a filter-sync temporarily
  /// removing all children of a user-collapsed parent).
  ///
  /// This is the suppress signal for the "gained first children"
  /// auto-expand heuristic (surfaced through [snapshotRememberedKeys]):
  /// when the children return in a later sync, the heuristic must not
  /// override the user's deliberate collapse. [_expansionMemory] cannot
  /// carry this — the parent is never removed, so a memory entry for it
  /// would be consumed by the restore/prune passes of the very sync that
  /// recorded it. Bounded by [maxExpansionMemorySize] (FIFO eviction).
  final Set<TKey> _emptiedWhileCollapsed = <TKey>{};

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
  /// **Reparent through removed root.** A descendant of a root that is
  /// being removed in this sync, but that appears elsewhere in the desired
  /// tree (under a different parent), is animated (slid) into its new
  /// position rather than purged with the old root. This is implemented
  /// by deferring root removal until after the recursive children sync
  /// has had a chance to call [TreeController.moveNode] for every cross-
  /// parent reparent. The old root then exits as a clean separate animation
  /// on the (now-empty or non-desired-residue) subtree it had left.
  ///
  /// Set [animate] to false to suppress animations (useful for initial setup).
  void syncRoots(
    List<TreeNode<TKey, TData>> desired, {
    List<TreeNode<TKey, TData>> Function(TKey key)? childrenOf,
    bool animate = true,
  }) {
    _assertNoDuplicateKeys(desired, "syncRoots");
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
    // Controller truth as the diff baseline. Live-filtered: exiting
    // (pending-deletion) roots are neither "current" (which would put
    // them in toRemove and restart their exit animation) nor retained.
    final currentRoots = _controller.liveRootKeys;
    final currentSet = currentRoots.toSet();

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

    // 1. Compute which roots are no longer desired, but DEFER their actual
    //    removal until after the recursive children sync (step 5). Reason:
    //    when a child reparents from a soon-to-be-removed root into a
    //    surviving root in the same sync, `moveNode` in step 5 needs to
    //    see the old root still alive so it can resolve `getParent(child)`
    //    and stage a clean FLIP slide. Removing the old root first marks
    //    the entire subtree pending-deletion, which leaves the child's
    //    slide composing against an ancestor-driven exit animation — the
    //    bug fixed by this ordering.
    //
    //    When childrenOf is provided, the `desiredDescendants.contains(key)`
    //    check below in step 2' also skips removal of roots that appear
    //    anywhere in the desired tree — they are being reparented, not
    //    deleted.
    final toRemove = currentSet.difference(desiredSet);

    // 2. Build the post-removal list plus a Fenwick tree keyed by desired
    //    position, seeded with 1s at retained keys' desired positions. The
    //    insertion loop below uses prefix sums for O(log N) insertion-index
    //    queries instead of the old O(N) walk over desiredOrder per insert.
    final desiredPos = <TKey, int>{
      for (int i = 0; i < desiredKeys.length; i++) desiredKeys[i]: i,
    };
    final remaining = <TKey>[
      for (final k in currentRoots)
        if (!toRemove.contains(k)) k,
    ];
    final remainingBit = _Fenwick(desiredKeys.length);
    for (final k in remaining) {
      final p = desiredPos[k];
      if (p != null) remainingBit.update(p, 1);
    }

    // 3. Insert new roots at their correct position. If a node already
    //    exists in the controller (e.g., promoted from child to root), use
    //    moveNode to preserve subtree state instead of insertRoot.
    final toAdd = desiredSet.difference(currentSet);
    final addedRoots = <TKey>[];
    for (final node in desired) {
      if (!toAdd.contains(node.key)) continue;

      final p = desiredPos[node.key]!;
      final targetIndex = remainingBit.prefixSum(p);

      if (_controller.getNodeData(node.key) != null) {
        final oldParent = _controller.getParent(node.key);
        if (oldParent == null) {
          // Already a root: insertRoot handles relocation and, when the
          // node is mid-exit, cancels the deletion and reverses the
          // standalone exit into an enter. preservePendingSubtreeState is
          // ignored when the node is not pending-deletion, so passing it
          // unconditionally is safe and keeps the re-add path symmetric.
          _controller.insertRoot(
            node,
            index: targetIndex,
            animate: animate,
            preservePendingSubtreeState: true,
          );
        } else {
          // Reparenting child → root. moveNode now composes a smooth
          // extent reversal with the FLIP slide for any pending-deletion
          // members of the moved subtree (Phase B / `_revertSubtreeFrom-
          // PendingDeletion`), so this path is correct even when the
          // moved node is mid-exit.
          _controller.updateNode(node);
          _controller.moveNode(
            node.key,
            null,
            index: targetIndex,
            animate: animate,
            slideDuration: _controller.animationDuration,
            slideCurve: _controller.animationCurve,
          );
        }
      } else {
        _controller.insertRoot(node, index: targetIndex, animate: animate);
      }
      remaining.insert(targetIndex, node.key);
      remainingBit.update(p, 1);
      addedRoots.add(node.key);
    }

    // 4. Update data for retained roots whose payload changed.
    //
    //    Exiting (pending-deletion) roots never reach this loop: the
    //    live-filtered `currentSet` excludes them, so a desired key that
    //    is mid-exit lands in `toAdd` and the branch above cancels the
    //    deletion (the desired state is authoritative — asking for the
    //    key means it should exist). Callers that want an imperative
    //    `remove()` to keep animating out should mirror live state via
    //    `liveRootKeys` so the exiting key drops out of `desired`.
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
    //    This must run BEFORE step 2' (root removal) and BEFORE reorderRoots:
    //    a former root being reparented into another root's subtree is still
    //    a live root at this point, and reorderRoots asserts that orderedKeys
    //    matches the current live roots exactly. The reparenting moveNode
    //    happens inside this recursive pass. By keeping the old roots alive
    //    until after this pass, moveNode can resolve getParent(child) cleanly
    //    and stage a FLIP slide against a stable baseline — the fix for the
    //    "reparent through removed root" bug.
    if (childrenOf != null) {
      _deferExpansionRestore = true;
      try {
        _syncChildrenRecursive(desired, childrenOf, animate);
      } finally {
        _deferExpansionRestore = false;
        _globallyDesiredChildren = null;
      }
    }

    // 2'. Now actually remove the orphan roots. Their desired descendants
    //     have been reparented out by step 5; whatever non-desired descendants
    //     remain under each toRemove root are correctly purged with it.
    //
    //     Read the captured local `desiredDescendants` here, NOT the
    //     `_globallyDesiredChildren` field — the field is set to null in the
    //     finally block above before this loop runs.
    assert(() {
      if (desiredDescendants != null) {
        for (final key in toRemove) {
          // Skip roots that are themselves being reparented: their entire
          // subtree rides along with the moveNode call in step 3 or step 5,
          // so it's expected that their remaining descendants are still in
          // desiredDescendants — that's how moveNode found them.
          if (desiredDescendants.contains(key)) continue;
          final tracked = _controller.getNodeData(key) != null
              ? _controller.getChildren(key)
              : const [];
          for (final childKey in tracked) {
            assert(
              !desiredDescendants.contains(childKey),
              "Descendant $childKey of soon-to-be-removed $key was not "
                  "reparented out before root removal. Step 5 should have "
                  "moved it via moveNode.",
            );
          }
        }
      }
      return true;
    }());
    for (final key in toRemove) {
      if (desiredDescendants != null && desiredDescendants.contains(key)) {
        // Skip: this root is being reparented (its key appears as a
        // descendant in the desired tree). The reparent was handled in
        // step 3 (former-child-to-root) or step 5 (cross-parent move).
        continue;
      }
      // Skip if already removed or moved by an earlier operation.
      if (_controller.getNodeData(key) == null ||
          _controller.getParent(key) != null) {
        continue;
      }
      // _rememberExpansion walks the controller's current subtree under
      // `key`. By this point any reparented descendants have been pulled
      // out via moveNode at step 5, so their expansion is preserved
      // natively by the controller (not via memory). What remains under
      // `key` are non-desired descendants that are about to be purged.
      _rememberExpansion(key);
      _controller.remove(key: key, animate: animate);
    }

    // 6. Reorder all live roots to match desired order if needed.
    //    After recursive children sync, any former roots that were reparented
    //    into the new tree have been moved out, so the controller's live
    //    roots should match desiredKeys (possibly in a different order).
    //
    //    `reorderRoots` validates against the controller's `liveRootKeys`
    //    (roots that are not pending deletion), so callers that mirror the
    //    raw `rootKeys` view back into `desired` while a section's exit
    //    animation is still in flight would otherwise pass the exiting
    //    key in `desiredKeys` and trip the length check. Filter
    //    `desiredKeys` against `isExiting` here so the exit is honored
    //    (the row keeps animating out) without breaking the rest of the
    //    reorder.
    final liveRoots = <TKey>[
      for (final k in _controller.rootKeys)
        if (!_controller.isExiting(k)) k,
    ];
    final liveDesiredKeys = <TKey>[
      for (final k in desiredKeys)
        if (!_controller.isExiting(k)) k,
    ];
    if (!_listEquals(liveRoots, liveDesiredKeys)) {
      _controller.reorderRoots(liveDesiredKeys, animate: animate);
    }

    // 7. Restore expansion state for newly inserted roots after their
    // children have been reattached.
    for (final key in addedRoots) {
      _restoreExpansion(key, animate: animate);
    }

    // 8. Prune expansion memory of keys that are now live in the controller.
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
  /// **Reparent through removed root:** when invoked from [syncRoots] and
  /// a child is reparented out of a root that is itself being removed in
  /// the same sync, the source root's removal is deferred until after this
  /// reparent completes. This lets [TreeController.moveNode] resolve the
  /// child's old parent cleanly and stage a FLIP slide against a stable
  /// baseline instead of fighting an ancestor-driven exit animation.
  ///
  /// Set [animate] to false to suppress animations.
  void syncChildren(
    TKey parentKey,
    List<TreeNode<TKey, TData>> desired, {
    bool animate = true,
  }) {
    _assertNoDuplicateKeys(desired, "syncChildren($parentKey)");
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

  /// Throws [ArgumentError] when [desired] contains the same key more
  /// than once. The diff machinery downstream dedupes via a set, but the
  /// per-position loops walk the raw list — duplicates land in the
  /// internal `remaining` tracker, producing wrong Fenwick offsets.
  /// `TreeController.setRoots`/`setChildren` already enforce this for the
  /// imperative path; matching it here closes the declarative path.
  static void _assertNoDuplicateKeys<TKey, TData>(
    List<TreeNode<TKey, TData>> desired,
    String context,
  ) {
    if (desired.length < 2) {
      return;
    }
    final seen = <TKey>{};
    for (final node in desired) {
      if (!seen.add(node.key)) {
        throw ArgumentError("Duplicate key ${node.key} in $context");
      }
    }
  }

  void _syncChildrenImpl(
    TKey parentKey,
    List<TreeNode<TKey, TData>> desired, {
    bool animate = true,
  }) {
    // Cheap early-out, mirroring TreeController.setChildren's exact-match
    // fast path: when [desired] exactly matches the controller's
    // current child list — same keys in order, same data, no
    // pending-deletion members — skip the whole diff (keys list, two
    // sets, Fenwick) before any allocation. The deferred
    // expansion-restore retry still runs: a parent whose children arrived
    // in an earlier sync may still be awaiting its expand.
    if (_childrenExactMatch(parentKey, desired)) {
      if (preserveExpansion &&
          !_deferExpansionRestore &&
          _expansionMemory.containsKey(parentKey)) {
        _restoreExpansion(parentKey, animate: animate);
      }
      return;
    }

    final desiredKeys = desired.map((n) => n.key).toList();
    final desiredSet = desiredKeys.toSet();
    // Controller truth as the diff baseline. Live-filtered: exiting
    // (pending-deletion) children are neither "current" (which would put
    // them in toRemove and restart their exit animation) nor retained.
    final currentKeys = _controller.getLiveChildren(parentKey);
    final currentSet = currentKeys.toSet();

    // Track a deliberate collapse across a child-list emptying: when this
    // sync removes the parent's last child while the parent survives in a
    // collapsed state, record the suppress signal so the auto-expand
    // heuristic does not re-open the parent when children return in a
    // later sync. Consume the signal as soon as children (re)arrive.
    if (preserveExpansion && maxExpansionMemorySize > 0) {
      if (desiredKeys.isEmpty && currentKeys.isNotEmpty) {
        if (!_controller.isExpanded(parentKey)) {
          _emptiedWhileCollapsed.add(parentKey);
          while (_emptiedWhileCollapsed.length > maxExpansionMemorySize) {
            _emptiedWhileCollapsed.remove(_emptiedWhileCollapsed.first);
          }
        }
      } else if (desiredKeys.isNotEmpty) {
        _emptiedWhileCollapsed.remove(parentKey);
      }
    }

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
    }

    // 2. Build the post-removal list plus a Fenwick tree keyed by desired
    //    position, seeded with 1s at retained keys' desired positions. The
    //    insertion loop below uses prefix sums for O(log N) insertion-index
    //    queries instead of the old O(N) walk over desiredOrder per insert.
    final desiredPos = <TKey, int>{
      for (int i = 0; i < desiredKeys.length; i++) desiredKeys[i]: i,
    };
    final remaining = <TKey>[
      for (final k in currentKeys)
        if (!toRemove.contains(k)) k,
    ];
    final remainingBit = _Fenwick(desiredKeys.length);
    for (final k in remaining) {
      final p = desiredPos[k];
      if (p != null) remainingBit.update(p, 1);
    }

    // 3. Insert new children at their correct position. If a node already
    //    exists in the controller (reparented from another location), use
    //    moveNode to preserve subtree state.
    final toAdd = desiredSet.difference(currentSet);
    for (final node in desired) {
      if (!toAdd.contains(node.key)) continue;

      final p = desiredPos[node.key]!;
      final targetIndex = remainingBit.prefixSum(p);

      if (_controller.getNodeData(node.key) != null) {
        final oldParent = _controller.getParent(node.key);
        if (oldParent == parentKey) {
          // Same parent: insert handles relocation and, when the node is
          // mid-exit, cancels the deletion. preservePendingSubtreeState
          // is ignored when the node is not pending-deletion, so passing
          // it unconditionally is safe.
          _controller.insert(
            parentKey: parentKey,
            node: node,
            index: targetIndex,
            animate: animate,
            preservePendingSubtreeState: true,
          );
        } else {
          // Reparenting across parents. moveNode now composes a smooth
          // extent reversal with the FLIP slide for any pending-deletion
          // members of the moved subtree (Phase B / `_revertSubtreeFrom-
          // PendingDeletion`), so this path is correct even when the
          // moved node is mid-exit.
          _controller.updateNode(node);
          _controller.moveNode(
            node.key,
            parentKey,
            index: targetIndex,
            animate: animate,
            slideDuration: _controller.animationDuration,
            slideCurve: _controller.animationCurve,
          );
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
      remainingBit.update(p, 1);
    }

    // 4. Update data for retained children whose payload changed.
    //
    //    Exiting (pending-deletion) children never reach this loop: the
    //    live-filtered `currentSet` excludes them, so a desired key that
    //    is mid-exit lands in `toAdd`, and step 3's re-add cancels the
    //    deletion (same parent: `insert` with
    //    `preservePendingSubtreeState: true`; cross-parent mover:
    //    `moveNode`'s pending-subtree revert) — the same policy as
    //    `_syncRootsImpl` step 4: the desired state is authoritative;
    //    asking for the key means it should exist. Callers
    //    that want an imperative `remove()` / `removeItem` to keep
    //    animating out should mirror live state (`getLiveChildren`, or
    //    `SectionedListController.itemsOf` with its default
    //    `includeExiting: false`) so the exiting key drops out of `desired`.
    final retained = desiredSet.intersection(currentSet);
    for (final node in desired) {
      if (!retained.contains(node.key)) continue;
      final current = _controller.getNodeData(node.key);
      if (current != null && current.data != node.data) {
        _controller.updateNode(node);
      }
    }

    // 5. Reorder all live children to match desired order if needed.
    //    Compare against CONTROLLER truth, not the tracking mirror: a
    //    deferred cross-parent mover (skipped in step 1 because it is
    //    globally desired elsewhere) is still a live child of [parentKey]
    //    at this point, so a mirror-derived comparison both misses genuine
    //    misorders (the mirror never disagrees with itself — silent
    //    permanent misorder) and, when a reorder IS issued, fails
    //    [TreeController.reorderChildren]'s exact-live-set validation.
    //
    //    Build the target order as a permutation of the controller's live
    //    children: desired keys first (in desired order), then any live
    //    children not in the desired set — i.e. the deferred movers, in
    //    their current relative order, appended. The movers are moved out
    //    later in the same batch when their destination parent syncs, so
    //    the transient tail position is invisible. Exiting
    //    (pending-deletion) rows are excluded by [getLiveChildren] and
    //    continue animating out untouched.
    final controllerLive = _controller.getLiveChildren(parentKey);
    final controllerLiveSet = controllerLive.toSet();
    final orderedKeys = <TKey>[
      for (final k in desiredKeys)
        if (controllerLiveSet.contains(k)) k,
      for (final k in controllerLive)
        if (!desiredSet.contains(k)) k,
    ];
    if (!_listEquals(controllerLive, orderedKeys)) {
      _controller.reorderChildren(parentKey, orderedKeys, animate: animate);
    }

    // 6. If the parent itself had a pending expansion restore that was
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
  /// The same child key MUST NOT appear under two different parents in
  /// [desiredByParent]. If it does, the second `syncChildren` call would
  /// reparent the key from the first parent's tree, producing last-write-
  /// wins semantics. Debug builds assert against this; release builds
  /// silently apply last-write-wins.
  ///
  /// Set [animate] to false to suppress animations.
  void syncMultipleChildren(
    Map<TKey, List<TreeNode<TKey, TData>>> desiredByParent, {
    bool animate = true,
  }) {
    _controller.runBatch(() {
      _globallyDesiredChildren = <TKey>{};
      try {
        // Build the union of all desired keys AND detect cross-parent
        // duplicates in debug mode. The duplicate-key check costs one
        // extra Set lookup per child but only runs under `assert(...)`.
        assert(() {
          final seenKeys = <TKey>{};
          for (final entry in desiredByParent.entries) {
            for (final c in entry.value) {
              if (!seenKeys.add(c.key)) {
                throw FlutterError(
                  "syncMultipleChildren: child key ${c.key} appears under "
                  "more than one parent in desiredByParent. The same key "
                  "cannot be a child of two parents; the second "
                  "syncChildren call would reparent it (last-write-wins). "
                  "Deduplicate the input map before calling.",
                );
              }
            }
          }
          return true;
        }());
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

  /// No-op, kept for backward compatibility.
  ///
  /// Diffs now read the controller's live state directly
  /// ([TreeController.liveRootKeys] / [TreeController.getLiveChildren]),
  /// so there is no private tracking state to initialize: a sync
  /// controller created against a populated [TreeController] — or one
  /// whose tree was mutated directly — always diffs against the
  /// controller's actual current state.
  void initializeTracking() {}

  /// Returns a deep-copied snapshot of the current live child order,
  /// derived from the controller.
  ///
  /// The returned map and lists are detached from the controller's internal
  /// state, so callers can safely compare snapshots across sync operations.
  /// Exiting (pending-deletion) nodes are excluded — they are on their way
  /// out and not part of the current logical tree.
  Map<TKey, List<TKey>> snapshotCurrentChildren() {
    final out = <TKey, List<TKey>>{};
    // Iterative DFS so deep linear chains do not stack-overflow Dart's
    // recursion limit (typically ~10k–20k frames).
    final stack = <TKey>[..._controller.liveRootKeys];
    while (stack.isNotEmpty) {
      final key = stack.removeLast();
      final children = _controller.getLiveChildren(key);
      out[key] = children;
      for (final childKey in children) {
        stack.add(childKey);
      }
    }
    return out;
  }

  /// Clears all remembered expansion state.
  void clearExpansionMemory() {
    _expansionMemory.clear();
    _emptiedWhileCollapsed.clear();
  }

  /// Returns the set of keys currently held in expansion memory, plus
  /// parents whose child list was emptied by a sync while they survived
  /// collapsed.
  ///
  /// A key is present here only if it was previously removed by
  /// [syncRoots]/[syncChildren] and its expansion state was recorded
  /// for restoration on re-add, or if it is a retained parent whose
  /// deliberate collapse must not be overridden when its children return.
  /// Intended for callers (e.g., the auto-expand heuristic in
  /// [SyncedSliverTree]) that need to distinguish a genuinely new key
  /// from one that is being re-added after having been filtered out.
  Set<TKey> snapshotRememberedKeys() {
    return {..._expansionMemory.keys, ..._emptiedWhileCollapsed};
  }

  /// Releases resources. Call before disposing the underlying [TreeController].
  void dispose() {
    _expansionMemory.clear();
    _emptiedWhileCollapsed.clear();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  /// Whether [desired] exactly matches the controller's current child
  /// list under [parentKey]: same keys in the same order, same data
  /// values, and no pending-deletion children (which would need the slow
  /// path's resurrection logic). One O(children) walk, zero allocation.
  bool _childrenExactMatch(
    TKey parentKey,
    List<TreeNode<TKey, TData>> desired,
  ) {
    final current = _controller.getChildren(parentKey);
    if (current.length != desired.length) {
      return false;
    }
    for (int i = 0; i < desired.length; i++) {
      final key = current[i];
      if (key != desired[i].key) {
        return false;
      }
      if (_controller.isPendingDeletion(key)) {
        return false;
      }
      final data = _controller.getNodeData(key);
      if (data == null || data.data != desired[i].data) {
        return false;
      }
    }
    return true;
  }

  /// Collects all desired descendant keys into [_globallyDesiredChildren].
  ///
  /// Iterative DFS so deep desired trees do not stack-overflow. Guards
  /// against revisits: a cyclic [childrenOf] (`a → b → a`) would loop
  /// forever on an unguarded walk (hanging the UI thread), and a DAG
  /// (same key under two parents) would walk exponentially before
  /// producing last-write-wins thrash. Throws [ArgumentError] naming the
  /// repeated key, matching the validation the other `SyncedSliverTree`
  /// input modes already perform.
  void _collectDesiredDescendants(
    List<TreeNode<TKey, TData>> nodes,
    List<TreeNode<TKey, TData>> Function(TKey key) childrenOf,
  ) {
    final seen = <TKey>{for (final n in nodes) n.key};
    final stack = <TreeNode<TKey, TData>>[...nodes];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      final children = childrenOf(node.key);
      for (final child in children) {
        if (!seen.add(child.key)) {
          throw ArgumentError(
            "syncRoots childrenOf detected a cycle or repeated key "
            "involving key \"${child.key}\".",
          );
        }
        _globallyDesiredChildren!.add(child.key);
        stack.add(child);
      }
    }
  }

  /// Syncs children for each node, then descends into their children.
  /// After all descendants are synced, restores expansion bottom-up so
  /// each `expand()` sees its children already registered.
  ///
  /// Iterative DFS so deep desired trees do not stack-overflow. The
  /// restore phase walks `restoreOrder` in reverse — the order keys are
  /// pushed in is top-down (parent before children); reversing yields
  /// the bottom-up order the recursive version produced.
  ///
  /// The [animate] flag is passed through unconditionally to each
  /// [syncChildren] call. A previous version suppressed animation
  /// (`animate: false`) when the parent was in the newly-added set,
  /// which was intended to avoid double-animation when a brand-new
  /// subtree appeared. That suppression also disabled the FLIP slide
  /// on cross-parent reparented children whose new parent happened to
  /// be newly added — the "Failure B" bug fixed here. Letting fresh
  /// children of a fresh parent animate alongside the parent's enter
  /// produces cohesive subtree growth, which is an acceptable (and
  /// arguably preferable) visual.
  void _syncChildrenRecursive(
    List<TreeNode<TKey, TData>> nodes,
    List<TreeNode<TKey, TData>> Function(TKey key) childrenOf,
    bool animate,
  ) {
    // Revisit guard — see [_collectDesiredDescendants]. That walk runs
    // first and throws on the same inputs, but [childrenOf] is a caller
    // function that may answer differently across calls, so this walk
    // carries its own guard rather than trusting the earlier pass.
    final seen = <TKey>{for (final n in nodes) n.key};
    final stack = <TreeNode<TKey, TData>>[];
    final restoreOrder = <TKey>[];
    for (int i = nodes.length - 1; i >= 0; i--) {
      stack.add(nodes[i]);
    }
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      final children = childrenOf(node.key);
      for (final child in children) {
        if (!seen.add(child.key)) {
          throw ArgumentError(
            "syncRoots childrenOf detected a cycle or repeated key "
            "involving key \"${child.key}\".",
          );
        }
      }
      syncChildren(node.key, children, animate: animate);
      // Defer restore to after all descendants are synced (bottom-up).
      for (final child in children) {
        restoreOrder.add(child.key);
      }
      // Push children for recursion (reversed so first child pops first,
      // matching the recursive version's left-to-right visit order).
      for (int i = children.length - 1; i >= 0; i--) {
        stack.add(children[i]);
      }
    }
    // Restore in reverse push order = bottom-up, matching recursion's
    // post-order placement of `_restoreExpansion(child.key, ...)` after
    // `_syncChildrenRecursive(children, ...)` returned.
    for (int i = restoreOrder.length - 1; i >= 0; i--) {
      _restoreExpansion(restoreOrder[i], animate: animate);
    }
  }

  /// Remembers the expansion state of [key] and all its descendants before
  /// removal. This is necessary because [TreeController.remove] purges the
  /// entire subtree, so descendant expansion states would be lost.
  ///
  /// Iterative DFS so deep linear chains do not stack-overflow.
  void _rememberExpansion(TKey key) {
    if (!preserveExpansion || maxExpansionMemorySize <= 0) {
      return;
    }
    final stack = <TKey>[key];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      _expansionMemory[current] = _controller.isExpanded(current);
      for (final childKey in _controller.getChildren(current)) {
        stack.add(childKey);
      }
    }
    // Evict oldest entries if over capacity.
    while (_expansionMemory.length > maxExpansionMemorySize) {
      _expansionMemory.remove(_expansionMemory.keys.first);
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
}

/// Minimal Fenwick / binary indexed tree over a fixed-size array of ints.
///
/// Used by [TreeSyncController] to compute insertion indices in O(log N)
/// per call across a batch of insertions, in place of the prior O(N)
/// linear walk over the desired order.
class _Fenwick {
  _Fenwick(int size)
      : _size = size,
        _tree = List<int>.filled(size + 1, 0);

  final int _size;
  final List<int> _tree;

  /// Adds [delta] at 0-based position [pos].
  void update(int pos, int delta) {
    for (int i = pos + 1; i <= _size; i += i & -i) {
      _tree[i] += delta;
    }
  }

  /// Returns the prefix sum over positions `[0, pos)` (exclusive).
  int prefixSum(int pos) {
    int sum = 0;
    for (int i = pos; i > 0; i -= i & -i) {
      sum += _tree[i];
    }
    return sum;
  }
}
