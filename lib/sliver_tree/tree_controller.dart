/// Controller that manages tree state, visibility, and animations.
library;

import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' show lerpDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '_node_id_registry.dart';
import '_visible_order_buffer.dart';
import 'types.dart';

part '_tree_controller_animation.dart';
part '_tree_controller_helpers.dart';

/// Controller for a [SliverTree] widget.
///
/// Manages:
/// - Tree structure (nodes, parent/child relationships, depth)
/// - Visibility (which nodes are in the flattened visible list)
/// - Expansion state (which nodes are expanded)
/// - Animation state (which nodes are animating and their progress)
///
/// Uses an ECS-style architecture where components are stored separately
/// for efficient iteration and memory usage.
///
/// The controller provides two notification channels:
/// - [addListener] / [removeListener] from [ChangeNotifier]: for structure changes
/// - [addAnimationListener] / [removeAnimationListener]: for animation ticks
///
/// This separation allows the render object to only do full relayout when
/// structure changes, and just update geometry/repaint during animations.
class TreeController<TKey, TData> extends ChangeNotifier {
  /// Creates a tree controller.
  ///
  /// Requires a [TickerProvider] to drive animations. Typically this is
  /// the State object of the widget that creates the controller, using
  /// [TickerProviderStateMixin] or [SingleTickerProviderStateMixin].
  TreeController({
    required TickerProvider vsync,
    Duration animationDuration = const Duration(milliseconds: 300),
    Curve animationCurve = Curves.easeInOut,
    double indentWidth = 0.0,
    this.comparator,
  }) : _animationDuration = animationDuration,
       _animationCurve = animationCurve,
       _indentWidth = indentWidth,
       _vsync = vsync;

  final TickerProvider _vsync;

  Duration _animationDuration;

  /// Duration for expand/collapse animations.
  ///
  /// Mutable at runtime. Setting a new value propagates to every in-flight
  /// [AnimationController] (operation groups and the bulk group) so their
  /// remaining progress plays at the new rate. The per-node standalone
  /// ticker re-reads this on every tick, so its animations adjust on the
  /// next frame. Newly started animations pick up the new duration at
  /// construction time.
  Duration get animationDuration => _animationDuration;
  set animationDuration(Duration value) {
    if (value == _animationDuration) {
      return;
    }
    _animationDuration = value;
    _bulkAnimationGroup?.controller.duration = value;
    for (final group in _operationGroups.values) {
      group.controller.duration = value;
    }
  }

  Curve _animationCurve;

  /// Curve for expand/collapse animations.
  ///
  /// Mutable at runtime. The standalone ticker re-reads this every frame,
  /// so per-node enter/exit animations switch curves immediately. Bulk and
  /// operation groups capture the curve at construction and keep it for the
  /// remainder of that animation — swapping a group's curve mid-flight would
  /// produce a visual discontinuity since the prior frames were already
  /// committed under the old curve. New groups pick up the new curve.
  Curve get animationCurve => _animationCurve;
  set animationCurve(Curve value) {
    if (value == _animationCurve) {
      return;
    }
    _animationCurve = value;
  }

  double _indentWidth;

  /// Horizontal indent per depth level in logical pixels.
  ///
  /// Mutable at runtime. [getIndent] reads this live, so setting a new
  /// value only needs to trigger a relayout on subscribers — fires the
  /// animation-tick channel (layout-only) rather than the structural
  /// channel so children aren't rebuilt unnecessarily.
  double get indentWidth => _indentWidth;
  set indentWidth(double value) {
    if (value == _indentWidth) {
      return;
    }
    _indentWidth = value;
    _notifyAnimationListeners();
  }

  /// Optional comparator for maintaining sorted order among siblings.
  ///
  /// When set, [insertRoot] and [insert] automatically place new nodes at the
  /// correct sorted position (unless an explicit [index] is provided).
  /// [setRoots] and [setChildren] sort their input before storing.
  final Comparator<TreeNode<TKey, TData>>? comparator;

  // ══════════════════════════════════════════════════════════════════════════
  // ECS-STYLE COMPONENT STORAGE
  // ══════════════════════════════════════════════════════════════════════════

  /// Node data indexed by nid (see INTERNAL NID REGISTRY below). Entries
  /// for freed nids are null. Look up by key via [_nids].
  final List<TreeNode<TKey, TData>?> _dataByNid = <TreeNode<TKey, TData>?>[];

  /// Parent nid for each node, indexed by nid. [_kNoParent] for roots and
  /// freed slots. Dense, capacity ≥ `_nids.length`; grown by
  /// [_ensureDenseCapacity].
  Int32List _parentByNid = Int32List(0);

  /// Sentinel value in nid-indexed parent arrays meaning "no parent" (root
  /// node) or "slot is free". Same sentinel is safe for both because a
  /// freed nid is never queried through [_nids].
  static const int _kNoParent = -1;

  /// Ordered list of child keys for each node, indexed by the parent's
  /// nid. Inner lists remain keyed by [TKey] for now — a later phase can
  /// convert them to child-nid lists once consumers use nids directly.
  final List<List<TKey>?> _childrenByNid = <List<TKey>?>[];

  /// Cached depth for each node (0 for roots), indexed by nid. Entries for
  /// freed nids are 0. Grown by [_ensureDenseCapacity].
  Int32List _depthByNid = Int32List(0);

  /// Expansion state for each node, indexed by nid. 0 = collapsed,
  /// 1 = expanded. Entries for freed nids are 0.
  Uint8List _expandedByNid = Uint8List(0);

  /// Cached "all ancestors expanded" bit for each node, indexed by nid. 1
  /// means every ancestor in the chain to the root is expanded (so the node
  /// is reachable by traversing the visible structure). Roots always carry
  /// 1 since they have no ancestors. A node's own expanded flag does not
  /// contribute. Maintained incrementally by [_setExpandedKey],
  /// [_setParentKey], and [_adoptKey]; rebuilt wholesale by
  /// [_rebuildAllAncestorsExpanded] after bulk operations. Entries for
  /// freed nids are 0.
  ///
  /// Replaces the O(depth) walk in the former `_areAncestorsExpanded` with
  /// an O(1) array read. The old walk was called up to O(N) times at the
  /// tail of every bulk animation.
  Uint8List _ancestorsExpandedByNid = Uint8List(0);

  /// Per-nid count of currently-visible entries in the subtree rooted at
  /// this nid, **including this nid itself when it is in `_order`**.
  ///
  /// Invariant (debug-asserted): for every live nid,
  /// `_visibleSubtreeSizeByNid[nid] == (nid in _order ? 1 : 0)
  ///     + sum over children c of _visibleSubtreeSizeByNid[c]`.
  ///
  /// Maintained incrementally: every mutation that changes an
  /// individual nid's presence in `_order` flows through
  /// [_onNidVisibilityGained] / [_onNidVisibilityLost], each of which
  /// walks the parent chain applying a ±1 delta in O(depth). Bulk
  /// mutations that rebuild the order wholesale (see
  /// [_rebuildVisibleOrder]) suppress those per-event callbacks and
  /// recompute the whole array in a single O(N) post-order pass via
  /// [_rebuildVisibleSubtreeSizes].
  ///
  /// Replaces the O(visibleSubtreeSize) `_countVisibleDescendants` walks
  /// that previously appeared inside O(k) sibling loops in the insert
  /// hot paths, closing an O(k × subtree) cost on child populations.
  Int32List _visibleSubtreeSizeByNid = Int32List(0);

  /// Whether per-nid visibility callbacks should skip their incremental
  /// delta propagation. Set during bulk rebuilds
  /// ([_rebuildVisibleOrder]) that will recompute the derived state in
  /// a single O(N) pass afterwards.
  ///
  /// Read directly inside [_onNidVisibilityGained] / [_onNidVisibilityLost]
  /// and [_setParentKey]. **Writes go through
  /// [_runWithSubtreeSizeUpdatesSuppressed]** — never flip the flag by
  /// hand, since the wrapper preserves the prior value (re-entrant safe)
  /// and guarantees the flag is restored even if the wrapped body throws.
  bool _suppressSubtreeSizeUpdates = false;

  /// Runs [body] with [_suppressSubtreeSizeUpdates] forced to true,
  /// restoring the prior value (not necessarily false) on return.
  /// Use this around bulk order mutations whose per-nid callbacks
  /// would otherwise double-count cache updates.
  void _runWithSubtreeSizeUpdatesSuppressed(void Function() body) {
    final wasSuppressed = _suppressSubtreeSizeUpdates;
    _suppressSubtreeSizeUpdates = true;
    try {
      body();
    } finally {
      _suppressSubtreeSizeUpdates = wasSuppressed;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INTERNAL NID REGISTRY
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Every live key is assigned a stable internal integer "nid". The dense
  // per-nid arrays above are indexed by nid (ints hash and compare faster
  // than arbitrary TKey, enabling Float64List / Int32List storage for
  // hot-path state). The mapping itself lives in [_nids]; see
  // [NodeIdRegistry].

  /// Bidirectional key↔nid registry with free-list recycling. Owns the
  /// [TKey] ↔ `int` mapping; the per-nid dense arrays above are owned by
  /// the controller and grown in lockstep with [_nids.length].
  final NodeIdRegistry<TKey> _nids = NodeIdRegistry<TKey>();

  /// Returns the nid for [key], allocating one if the key isn't registered.
  /// Idempotent for already-registered keys. Grows every dense per-nid
  /// array in lockstep so callers can safely index them at the returned nid.
  int _adoptKey(TKey key) {
    final result = _nids.allocate(key);
    final nid = result.nid;
    if (!result.isNew) {
      return nid;
    }
    if (result.grew) {
      _dataByNid.add(null);
      _childrenByNid.add(null);
      _ensureDenseCapacity(_nids.length);
    } else {
      _dataByNid[nid] = null;
      _childrenByNid[nid] = null;
    }
    _parentByNid[nid] = _kNoParent;
    _depthByNid[nid] = 0;
    _expandedByNid[nid] = 0;
    _ancestorsExpandedByNid[nid] = 1;
    _visibleSubtreeSizeByNid[nid] = 0;
    _order.clearIndexByNid(nid);
    return nid;
  }

  /// Grows every typed-data nid-indexed array to at least [needed] slots.
  /// Doubles capacity on each realloc so amortized growth is O(1) per
  /// [_adoptKey] call.
  void _ensureDenseCapacity(int needed) {
    if (needed <= _parentByNid.length) return;
    int cap = _parentByNid.isEmpty ? 8 : _parentByNid.length;
    while (cap < needed) {
      cap *= 2;
    }
    final newParent = Int32List(cap);
    newParent.setRange(0, _parentByNid.length, _parentByNid);
    _parentByNid = newParent;
    final newDepth = Int32List(cap);
    newDepth.setRange(0, _depthByNid.length, _depthByNid);
    _depthByNid = newDepth;
    final newExpanded = Uint8List(cap);
    newExpanded.setRange(0, _expandedByNid.length, _expandedByNid);
    _expandedByNid = newExpanded;
    final newAncestorsExpanded = Uint8List(cap);
    newAncestorsExpanded.setRange(
      0,
      _ancestorsExpandedByNid.length,
      _ancestorsExpandedByNid,
    );
    _ancestorsExpandedByNid = newAncestorsExpanded;
    final newVisibleSubtreeSize = Int32List(cap);
    newVisibleSubtreeSize.setRange(
      0,
      _visibleSubtreeSizeByNid.length,
      _visibleSubtreeSizeByNid,
    );
    _visibleSubtreeSizeByNid = newVisibleSubtreeSize;
    _order.resizeIndex(cap);
  }

  /// Returns the parent nid for [key], or [_kNoParent] if [key] is a root
  /// or unregistered. Hot path — no allocation, no exception.
  int _parentNidOfKey(TKey key) {
    final nid = _nids[key];
    return nid == null ? _kNoParent : _parentByNid[nid];
  }

  /// Returns the parent key for [key], or null if [key] is a root or
  /// unregistered. Equivalent to the old `_parentKeyOfKey(key)`.
  ///
  /// The parent nid slot can be null when the parent has already been
  /// freed ahead of this node in a removal sweep, so the reverse lookup
  /// must tolerate a null result.
  TKey? _parentKeyOfKey(TKey key) {
    final pNid = _parentNidOfKey(key);
    return pNid == _kNoParent ? null : _nids.keyOf(pNid);
  }

  /// Sets the parent of [key] to [parent] (or null for root). [key] must
  /// already be registered; [parent] must also be registered (unless null).
  /// Also refreshes the cached [_ancestorsExpandedByNid] bit for [key] and
  /// propagates the change through [key]'s subtree so the cache stays
  /// consistent with the new ancestor chain.
  ///
  /// Reparenting also shifts [key]'s visible-subtree contribution from
  /// the old parent chain to the new one. The subtree's own visible
  /// count is unchanged (the members are the same); only which
  /// ancestors account for them changes.
  void _setParentKey(TKey key, TKey? parent) {
    final nid = _nids[key]!;
    final oldParentNid = _parentByNid[nid];
    final newParentNid = parent == null ? _kNoParent : _nids[parent]!;
    if (oldParentNid != newParentNid &&
        !_suppressSubtreeSizeUpdates &&
        nid < _visibleSubtreeSizeByNid.length) {
      final delta = _visibleSubtreeSizeByNid[nid];
      if (delta != 0) {
        // Detach from the old ancestor chain, then attach to the new.
        // Walk from the parent (not from `nid` itself) because the
        // subtree rooted at `nid` has not changed its own composition.
        if (oldParentNid != _kNoParent) {
          _bumpVisibleSubtreeSizeFromSelf(oldParentNid, -delta);
        }
        if (newParentNid != _kNoParent) {
          _bumpVisibleSubtreeSizeFromSelf(newParentNid, delta);
        }
      }
    }
    _parentByNid[nid] = newParentNid;
    final newAe = _computeAncestorsExpanded(nid);
    if (_ancestorsExpandedByNid[nid] != newAe) {
      _ancestorsExpandedByNid[nid] = newAe;
      final childAe = (newAe != 0 && _expandedByNid[nid] != 0) ? 1 : 0;
      _propagateAncestorsExpandedToDescendants(key, childAe);
    }
  }

  /// Releases the nid associated with [key] back to the pool. Clears every
  /// per-nid dense array slot so a future [_adoptKey] that recycles the nid
  /// sees a clean state.
  void _releaseNid(TKey key) {
    final nid = _nids.release(key);
    if (nid == null) return;
    _dataByNid[nid] = null;
    _parentByNid[nid] = _kNoParent;
    _childrenByNid[nid] = null;
    _depthByNid[nid] = 0;
    _expandedByNid[nid] = 0;
    _ancestorsExpandedByNid[nid] = 0;
    _visibleSubtreeSizeByNid[nid] = 0;
    _order.clearIndexByNid(nid);
  }

  /// Nullable lookup of the [TreeNode] record for [key]. Equivalent to the
  /// old `_nodeData[key]` — returns null if [key] is not registered.
  TreeNode<TKey, TData>? _dataOf(TKey key) {
    final nid = _nids[key];
    return nid == null ? null : _dataByNid[nid];
  }

  /// Whether [key] currently has a node record. Equivalent to the old
  /// `_nodeData.containsKey(key)`.
  bool _hasKey(TKey key) => _nids.contains(key);

  /// Returns the child key list for [key], or null if unregistered or no
  /// list has been allocated yet. Equivalent to the old `_childListOf(key)`.
  List<TKey>? _childListOf(TKey key) {
    final nid = _nids[key];
    return nid == null ? null : _childrenByNid[nid];
  }

  /// Returns the child key list for [key], allocating an empty list if
  /// none exists. [key] must already be registered.
  /// Equivalent to the old `_childListOrCreate(key)`.
  List<TKey> _childListOrCreate(TKey key) {
    final nid = _nids[key]!;
    return _childrenByNid[nid] ??= <TKey>[];
  }

  /// Replaces the child key list for [key]. [key] must be registered.
  /// Equivalent to the old `_children[key] = list`.
  void _setChildList(TKey key, List<TKey> list) {
    _childrenByNid[_nids[key]!] = list;
  }

  /// Depth for [key], or 0 if unregistered.
  /// Equivalent to the old `_depthOfKey(key)`.
  int _depthOfKey(TKey key) {
    final nid = _nids[key];
    return nid == null ? 0 : _depthByNid[nid];
  }

  /// Sets the depth for [key]. [key] must be registered.
  void _setDepthKey(TKey key, int depth) {
    _depthByNid[_nids[key]!] = depth;
  }

  /// Whether [key] is currently expanded. Returns false if unregistered.
  /// Equivalent to the old `_isExpandedKey(key)` / `_isExpandedKey(key)`.
  bool _isExpandedKey(TKey key) {
    final nid = _nids[key];
    return nid != null && _expandedByNid[nid] != 0;
  }

  /// Sets the expansion flag for [key]. [key] must be registered.
  /// Equivalent to the old `_expanded[key] = expanded`.
  ///
  /// By default propagates the change through [_ancestorsExpandedByNid] for
  /// descendants so ancestor-expansion queries stay O(1). Pass
  /// [propagate] as `false` in bulk paths that rebuild the cache wholesale
  /// via [_rebuildAllAncestorsExpanded] — per-call propagation would
  /// compound to O(N × subtree) across the batch.
  void _setExpandedKey(TKey key, bool expanded, {bool propagate = true}) {
    final nid = _nids[key]!;
    final newVal = expanded ? 1 : 0;
    if (_expandedByNid[nid] == newVal) return;
    _expandedByNid[nid] = newVal;
    // Children's ae bit equals expanded(key) && ae(key). If ae(key) is 0,
    // children's ae is already 0 and unaffected by this flip.
    if (propagate && _ancestorsExpandedByNid[nid] != 0) {
      _propagateAncestorsExpandedToDescendants(key, newVal);
    }
  }

  /// Computes the ancestors-expanded bit for [nid] from its parent's state.
  /// Roots (and detached nodes) return 1.
  int _computeAncestorsExpanded(int nid) {
    final parentNid = _parentByNid[nid];
    if (parentNid == _kNoParent) return 1;
    return (_expandedByNid[parentNid] != 0 &&
            _ancestorsExpandedByNid[parentNid] != 0)
        ? 1
        : 0;
  }

  /// Sets the ancestors-expanded bit for every descendant of [key]. The
  /// bit assigned to [key]'s direct children is [childAe]; grandchildren
  /// then get `(expanded(child) && childAe)`, and so on.
  ///
  /// Short-circuits on descendants whose current bit already matches: under
  /// the maintained invariant, their whole subtree is also already
  /// consistent.
  ///
  /// Iterative (explicit worklist) rather than recursive so deep trees do
  /// not risk a Dart stack overflow. Sibling visit order is irrelevant —
  /// each child's new bit depends only on its parent, never on siblings.
  void _propagateAncestorsExpandedToDescendants(TKey key, int childAe) {
    // Parallel stacks: the node at parents[i] has children that should
    // receive ancestorsExpanded == childAes[i]. Seeded with the initial
    // (key, childAe) pair; grows one entry per descendant whose bit is
    // actually updated (short-circuited descendants are never pushed).
    final parents = <TKey>[key];
    final childAes = <int>[childAe];
    while (parents.isNotEmpty) {
      final parent = parents.removeLast();
      final ae = childAes.removeLast();
      final children = _childListOf(parent);
      if (children == null || children.isEmpty) continue;
      for (final child in children) {
        final childNid = _nids[child];
        if (childNid == null) continue;
        if (_ancestorsExpandedByNid[childNid] == ae) continue;
        _ancestorsExpandedByNid[childNid] = ae;
        final grandAe = (ae != 0 && _expandedByNid[childNid] != 0) ? 1 : 0;
        parents.add(child);
        childAes.add(grandAe);
      }
    }
  }

  /// Rebuilds [_ancestorsExpandedByNid] wholesale in a single pass from the
  /// roots. Used by bulk operations (collapseAll / expandAll /
  /// [_collapseAllInRegistry]) that bypass per-call propagation.
  void _rebuildAllAncestorsExpanded() {
    _ancestorsExpandedByNid.fillRange(0, _ancestorsExpandedByNid.length, 0);
    for (final rootKey in _roots) {
      final rootNid = _nids[rootKey];
      if (rootNid == null) continue;
      _ancestorsExpandedByNid[rootNid] = 1;
      final childAe = _expandedByNid[rootNid] != 0 ? 1 : 0;
      _propagateAncestorsExpandedToDescendants(rootKey, childAe);
    }
  }

  /// O(1) "are all ancestors of [key] expanded?" check, backed by the
  /// cached [_ancestorsExpandedByNid] array. Returns true for roots and
  /// unregistered keys (the latter preserves the semantics of the original
  /// [_areAncestorsExpanded] walk, which returned true when there was no
  /// parent chain to traverse).
  bool _ancestorsExpandedFast(TKey key) {
    final nid = _nids[key];
    if (nid == null) return true;
    return _ancestorsExpandedByNid[nid] != 0;
  }

  /// Clears the expanded flag for every registered node whose depth is
  /// less than [maxDepth] (or for every node when [maxDepth] is null).
  /// Equivalent to the old `_expanded.updateAll` calls used by
  /// [collapseAll]. Freed nids are already 0 so skipping them is optional
  /// — we iterate only live ones to avoid spurious work in very sparse
  /// registries.
  void _collapseAllInRegistry(int? maxDepth) {
    if (maxDepth == null) {
      _expandedByNid.fillRange(0, _expandedByNid.length, 0);
    } else {
      final n = _nids.length;
      for (int nid = 0; nid < n; nid++) {
        if (_nids.isFree(nid)) continue;
        if (_expandedByNid[nid] == 0) continue;
        if (_depthByNid[nid] < maxDepth) {
          _expandedByNid[nid] = 0;
        }
      }
    }
    _rebuildAllAncestorsExpanded();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VISIBILITY STATE
  // ══════════════════════════════════════════════════════════════════════════

  /// Root node IDs in order.
  final List<TKey> _roots = [];

  /// Flattened visible-order buffer: maintains the dense nid array plus the
  /// reverse nid → visible-index map. Mutations invalidate the full-extent
  /// prefix sum via the [onOrderMutated] callback, and per-nid
  /// add/remove callbacks drive the incremental maintenance of
  /// [_visibleSubtreeSizeByNid].
  late final VisibleOrderBuffer<TKey> _order = VisibleOrderBuffer<TKey>(
    registry: _nids,
    onOrderMutated: _invalidateFullOffsetPrefix,
    onNidAdded: _onNidVisibilityGained,
    onNidRemoved: _onNidVisibilityLost,
  );

  /// Handler for "nid [nid] just entered the visible order." Propagates
  /// +1 up the ancestor chain to keep [_visibleSubtreeSizeByNid]
  /// consistent. Skips propagation during a bulk rebuild that will
  /// recompute the array from scratch afterwards.
  void _onNidVisibilityGained(int nid) {
    if (_suppressSubtreeSizeUpdates) return;
    _bumpVisibleSubtreeSizeFromSelf(nid, 1);
  }

  /// Handler for "nid [nid] just left the visible order." Propagates
  /// -1 up the ancestor chain.
  void _onNidVisibilityLost(int nid) {
    if (_suppressSubtreeSizeUpdates) return;
    _bumpVisibleSubtreeSizeFromSelf(nid, -1);
  }

  /// Adds [delta] to [_visibleSubtreeSizeByNid] at [startNid] and at
  /// every ancestor. Stops at the root (`_kNoParent`). O(depth).
  ///
  /// Used for both visibility changes (where [startNid] is the node
  /// whose order membership flipped) and reparenting (where [startNid]
  /// is the moved subtree's parent, and the moved subtree itself does
  /// not change its own size slot).
  void _bumpVisibleSubtreeSizeFromSelf(int startNid, int delta) {
    if (delta == 0) return;
    int cur = startNid;
    while (cur != _kNoParent && cur >= 0 && cur < _visibleSubtreeSizeByNid.length) {
      // Refuse to mutate a freed slot. In debug, surface the violation;
      // in release, bail out — corrupting a freed slot causes downstream
      // visibility-cache bugs once the nid is recycled.
      if (_nids.keyOf(cur) == null) {
        assert(
          false,
          "_bumpVisibleSubtreeSizeFromSelf walked through freed nid $cur "
          "from start nid $startNid (delta=$delta)",
        );
        break;
      }
      final next = _visibleSubtreeSizeByNid[cur] + delta;
      assert(
        next >= 0,
        "visible-subtree-size would go negative at nid $cur "
        "(current=${_visibleSubtreeSizeByNid[cur]}, delta=$delta, "
        "key=${_nids.keyOf(cur)})",
      );
      _visibleSubtreeSizeByNid[cur] = next;
      cur = _parentByNid[cur];
    }
  }

  /// Rebuilds [_visibleSubtreeSizeByNid] wholesale from the current
  /// tree structure and `_order` membership. O(N) via iterative
  /// pre-order walk followed by reverse-order summation (equivalent to
  /// iterative post-order). Used after bulk operations that rebuild
  /// the visible order in one shot.
  void _rebuildVisibleSubtreeSizes() {
    _visibleSubtreeSizeByNid.fillRange(
      0,
      _visibleSubtreeSizeByNid.length,
      0,
    );
    // Pre-order DFS to collect nids. Reverse pre-order is a valid
    // post-order for the purpose of summing children before parents.
    final preOrderNids = <int>[];
    final stack = <TKey>[];
    for (int i = _roots.length - 1; i >= 0; i--) {
      stack.add(_roots[i]);
    }
    final indexByNid = _order.indexByNid;
    while (stack.isNotEmpty) {
      final key = stack.removeLast();
      final nid = _nids[key];
      if (nid == null) {
        assert(false, "key $key has no nid during _rebuildVisibleSubtreeSizes");
        continue;
      }
      preOrderNids.add(nid);
      final children = _childListOf(key);
      if (children == null) continue;
      for (int i = children.length - 1; i >= 0; i--) {
        stack.add(children[i]);
      }
    }
    // Walk reverse pre-order. For each nid, its own contribution is 1
    // if it is currently in [_order], 0 otherwise. Children have
    // already been summed because they appear later in pre-order.
    for (int i = preOrderNids.length - 1; i >= 0; i--) {
      final nid = preOrderNids[i];
      final key = _nids.keyOf(nid);
      int size = indexByNid[nid] == VisibleOrderBuffer.kNotVisible ? 0 : 1;
      if (key != null) {
        final children = _childListOf(key);
        if (children != null) {
          for (final child in children) {
            final childNid = _nids[child];
            if (childNid != null) {
              size += _visibleSubtreeSizeByNid[childNid];
            }
          }
        }
      }
      _visibleSubtreeSizeByNid[nid] = size;
    }
  }

  /// Debug-only consistency check for [_visibleSubtreeSizeByNid].
  /// Exposed for fuzz tests via [debugAssertVisibleSubtreeSizeConsistency].
  @visibleForTesting
  void debugAssertVisibleSubtreeSizeConsistency() =>
      _assertVisibleSubtreeSizeConsistency();

  /// All currently-live keys, in nid order. Debug-only accessor for tests
  /// that need to pick a random key from the live set.
  @visibleForTesting
  Iterable<TKey> get debugAllKeys sync* {
    for (int nid = 0; nid < _nids.length; nid++) {
      final key = _nids.keyOf(nid);
      if (key != null) {
        yield key;
      }
    }
  }

  /// Debug-only consistency check for [_visibleSubtreeSizeByNid].
  /// Walks the tree and verifies every live nid's size slot equals the
  /// structural definition.
  void _assertVisibleSubtreeSizeConsistency() {
    assert(() {
      final indexByNid = _order.indexByNid;
      for (int nid = 0; nid < _nids.length; nid++) {
        final key = _nids.keyOf(nid);
        if (key == null) continue;
        int expected =
            indexByNid[nid] == VisibleOrderBuffer.kNotVisible ? 0 : 1;
        final children = _childListOf(key);
        if (children != null) {
          for (final child in children) {
            final childNid = _nids[child];
            if (childNid != null) {
              expected += _visibleSubtreeSizeByNid[childNid];
            }
          }
        }
        if (_visibleSubtreeSizeByNid[nid] != expected) {
          throw StateError(
            "_visibleSubtreeSizeByNid[$nid] (key=$key) = "
            "${_visibleSubtreeSizeByNid[nid]}, expected $expected",
          );
        }
      }
      return true;
    }());
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ANIMATION STATE
  // ══════════════════════════════════════════════════════════════════════════

  /// Animation state for nodes animating via standalone ticker.
  /// Used for inserts, removes, and cross-group transitions.
  final Map<TKey, AnimationState> _standaloneAnimations = {};

  /// Ticker for standalone animations only.
  Ticker? _standaloneTicker;
  Duration? _lastStandaloneTickTime;

  /// The current bulk animation group (for expandAll/collapseAll).
  /// Only one bulk group is active at a time. New bulk operations
  /// reverse or replace this group.
  AnimationGroup<TKey>? _bulkAnimationGroup;

  /// Per-operation animation groups (for individual expand/collapse).
  /// Key is the operation key (the node whose expand/collapse created the group).
  final Map<TKey, OperationGroup<TKey>> _operationGroups = {};

  /// Reverse lookup: node key → operation group key.
  /// Provides O(1) group membership checks.
  final Map<TKey, TKey> _nodeToOperationGroup = {};

  /// Cached full extents for nodes (measured size before animation).
  final Map<TKey, double> _fullExtents = {};

  /// Nodes pending deletion (animating out due to remove(), not collapse).
  /// These nodes should be fully removed from data structures when their
  /// exit animation completes.
  final Set<TKey> _pendingDeletion = {};

  /// Active FLIP slide animations, keyed by node. A node present here is
  /// painted with a vertical translation equal to [SlideAnimation.currentDelta];
  /// structural layout is unaffected (slide is paint-only).
  ///
  /// Populated by [animateSlideFromOffsets] and cleared by the slide tick
  /// handler on completion. A node can simultaneously be a slide entry and
  /// have an enter/exit extent animation — the two channels compose at paint.
  final Map<TKey, SlideAnimation<TKey>> _slideAnimations = {};

  /// Lazy [Ticker] driving every entry in [_slideAnimations]. One shared
  /// ticker is sufficient because all active slides share the same start
  /// time (FLIP from the same mutation) and reset together.
  ///
  /// Why a raw [Ticker] and not an [AnimationController]: a ticker's
  /// callbacks fire exclusively from the scheduler's transient-callbacks
  /// phase (next vsync after [Ticker.start]). This means
  /// [animateSlideFromOffsets] can be invoked from inside
  /// [RenderObject.performLayout] — the listener chain reaches the sliver
  /// element's `_onAnimationTick` only from the next vsync, when
  /// `markNeedsLayout`/`markNeedsPaint` are legal.
  ///
  /// An [AnimationController], by contrast, fires listeners synchronously
  /// from its `value=` setter (and from `reset()`/`forward(from:)`), so
  /// starting it mid-layout would trip `_debugCanPerformMutations`.
  ///
  /// Disposed in [dispose]; stopped when [_slideAnimations] empties.
  Ticker? _slideTicker;

  /// Total duration of the current slide batch. All entries in
  /// [_slideAnimations] share this duration — progress at a tick with
  /// elapsed `e` is `e / _slideDuration`.
  Duration _slideDuration = const Duration(milliseconds: 220);

  /// Listeners notified on every animation tick (layout-only updates).
  final List<VoidCallback> _animationListeners = [];

  /// Listeners notified when a single node's data changes without any
  /// structural change (e.g. [updateNode]). Receives the changed key.
  final List<void Function(TKey)> _nodeDataListeners = [];

  /// Listeners notified on structural mutations with an optional set of
  /// affected keys. A `null` set means "scope unknown — full refresh"; an
  /// empty set means "structural change happened, but no mounted row's
  /// builder output changed" (valid when the effect is absorbed by
  /// `createChild` for new rows and GC for removed rows); a non-empty set
  /// lists exactly the keys whose builder output may differ.
  final List<void Function(Set<TKey>? affectedKeys)> _structuralListeners = [];

  /// Depth of nested [runBatch] calls. Mutations inside a batch defer
  /// their structural notification to the outermost [runBatch] exit.
  int _batchDepth = 0;

  /// Set when a mutation inside [runBatch] requested a structural
  /// notification. Drained and fired once when [_batchDepth] returns to 0.
  bool _batchDidRequestStructural = false;

  /// Keys whose data changed inside the current [runBatch]. Drained after
  /// the structural notification fires so that targeted row refreshes see
  /// a coherent post-batch state.
  Set<TKey>? _batchDirtyDataNodes;

  /// Union of [affectedKeys] sets passed to [_notifyStructural] inside the
  /// current [runBatch]. Fired as a single set at the outermost batch exit.
  /// Null when no mutation has specified affected keys yet.
  Set<TKey>? _batchAffectedStructuralKeys;

  /// Poison pill: set to true when any in-batch [_notifyStructural] call
  /// passes `affectedKeys: null`. Forces a full refresh at batch exit even
  /// if other in-batch calls carried specific keys.
  bool _batchAffectedStructuralUnknown = false;

  /// Default extent for nodes that haven't been measured yet.
  static const double defaultExtent = 48.0;

  /// Monotonically increasing counter incremented whenever the visible
  /// order is structurally mutated (nodes added, removed, or reordered).
  /// Used by the render object to detect structure changes even when the
  /// visible node count stays the same.
  int _structureGeneration = 0;
  int get structureGeneration => _structureGeneration;

  /// Scratch set reused to avoid per-frame allocation.
  final Set<TKey> _keysToRemoveScratch = {};

  /// Lazy prefix sum of full (non-animated) extents over the current visible
  /// order. When valid, `_fullOffsetPrefix[i]` is the sum of
  /// `_fullExtents[k] ?? defaultExtent` for visible indices `0..i-1`, and
  /// `_fullOffsetPrefix.length == _order.length + 1`.
  ///
  /// Invalidated by visible-order mutations and by [setFullExtent] when the
  /// stored value actually changes. Rebuild is O(N) but amortized: the cache
  /// survives animation frames because full extents don't change during
  /// expand/collapse (only the animated extent does).
  List<double>? _fullOffsetPrefix;
  bool _fullOffsetPrefixDirty = true;

  void _invalidateFullOffsetPrefix() {
    _fullOffsetPrefixDirty = true;
  }

  /// Rebuilds [_fullOffsetPrefix] if dirty or stale. O(N) on rebuild, O(1)
  /// when the cache is already valid.
  void _ensureFullOffsetPrefix() {
    final cached = _fullOffsetPrefix;
    if (!_fullOffsetPrefixDirty &&
        cached != null &&
        cached.length == _order.length + 1) {
      return;
    }
    final prefix = List<double>.filled(_order.length + 1, 0.0, growable: false);
    double acc = 0.0;
    for (int i = 0; i < _order.length; i++) {
      final key = _nids.keyOfUnchecked(_order.orderNids[i]);
      acc += _fullExtents[key] ?? defaultExtent;
      prefix[i + 1] = acc;
    }
    _fullOffsetPrefix = prefix;
    _fullOffsetPrefixDirty = false;
  }

  /// Returns the prefix-sum full-extent offset up to visible index [index]
  /// (exclusive). Un-measured nodes contribute [defaultExtent]. O(1)
  /// amortized via [_fullOffsetPrefix].
  double _fullOffsetAt(int index) {
    _ensureFullOffsetPrefix();
    return _fullOffsetPrefix![index];
  }

  /// Monotonically increasing counter bumped on any mutation to
  /// animation-state membership (standalone animations, operation-group
  /// members or pendingRemoval, bulk-group members or pendingRemoval).
  /// Serves as the O(1) cache signature for [_animatingKeysCache] and
  /// [_firstAnimatingIndexCacheVal] so per-frame queries like
  /// [isAnimating] don't rescan every animating node per call.
  ///
  /// All animation-state mutations flow through [_bumpAnimGen] (direct or
  /// via [_bumpBulkGen], which also bumps [_bulkAnimationGeneration]).
  int _animationGeneration = 0;

  /// Union of every currently-animating key across standalone, operation,
  /// and bulk groups. Rebuilt on demand when [_animationGeneration] changes.
  Set<TKey>? _animatingKeysCache;
  int _animatingKeysCacheGen = -1;

  /// Cached result of [computeFirstAnimatingVisibleIndex]. Depends on both
  /// animation state and the visible order, so the cache key combines
  /// [_animationGeneration] with [_structureGeneration].
  int _firstAnimatingIndexCacheSig = -1;
  int _firstAnimatingIndexCacheVal = 0;

  /// Bumps [_animationGeneration] so the next call to [_ensureAnimatingKeys]
  /// or [computeFirstAnimatingVisibleIndex] rebuilds its cache. Must be
  /// called from every path that mutates standalone, operation-group, or
  /// bulk-group membership. Paths that mutate bulk state use [_bumpBulkGen].
  void _bumpAnimGen() {
    _animationGeneration++;
  }

  /// Bumps both the broad [_animationGeneration] and the bulk-specific
  /// [_bulkAnimationGeneration]. Call from any path that mutates
  /// [_bulkAnimationGroup]'s identity or membership.
  void _bumpBulkGen() {
    _animationGeneration++;
    _bulkAnimationGeneration++;
  }

  /// Returns a set of every currently-animating key. Rebuilt on demand when
  /// [_animationGeneration] changes.
  Set<TKey> _ensureAnimatingKeys() {
    final cached = _animatingKeysCache;
    if (cached != null && _animationGeneration == _animatingKeysCacheGen) {
      return cached;
    }
    final set = <TKey>{};
    if (_standaloneAnimations.isNotEmpty) {
      set.addAll(_standaloneAnimations.keys);
    }
    if (_operationGroups.isNotEmpty) {
      for (final g in _operationGroups.values) {
        set.addAll(g.members.keys);
      }
    }
    final bulk = _bulkAnimationGroup;
    if (bulk != null && bulk.members.isNotEmpty) {
      set.addAll(bulk.members);
    }
    _animatingKeysCache = set;
    _animatingKeysCacheGen = _animationGeneration;
    return set;
  }

  /// Builds a fresh synthetic entering state for [getAnimationState] to return
  /// for operation or bulk group members that are expanding. A fresh object
  /// per call avoids any cross-controller corruption if an external caller
  /// mutates the returned [AnimationState].
  static AnimationState _buildSyntheticEnteringState() {
    return AnimationState(
      type: AnimationType.entering,
      startExtent: 0,
      targetExtent: 0,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC QUERIES
  // ══════════════════════════════════════════════════════════════════════════

  /// The flattened list of visible node IDs in render order.
  ///
  /// Returns a read-only live view over the internal nid-indexed buffer.
  /// Mutations to the visible order are reflected automatically.
  late final List<TKey> visibleNodes = _VisibleNodesView<TKey, TData>(this);

  /// Number of visible nodes.
  int get visibleNodeCount => _order.length;

  int get rootCount => _roots.length;

  /// Root node IDs in order.
  ///
  /// Returns an unmodifiable view of the internal list.
  /// The wrapper reflects mutations to [_roots] automatically.
  late final List<TKey> rootKeys = UnmodifiableListView<TKey>(_roots);

  /// Gets the ordered list of child keys for the given node.
  ///
  /// Returns an empty list if the node has no children or doesn't exist.
  List<TKey> getChildren(TKey key) {
    final c = _childListOf(key);
    if (c == null || c.isEmpty) return const [];
    return UnmodifiableListView<TKey>(c);
  }

  /// Gets the node data for the given key, or null if not found.
  TreeNode<TKey, TData>? getNodeData(TKey key) {
    return _dataOf(key);
  }

  /// Gets the depth of the given node (0 for roots).
  int getDepth(TKey key) {
    return _depthOfKey(key);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NID-SPACE ACCESSORS (intended for render-layer consumers)
  // ══════════════════════════════════════════════════════════════════════════
  //
  // These expose the internal nid registry so hot-path consumers (notably
  // RenderSliverTree) can keep per-node state in dense typed-data arrays
  // indexed by nid instead of hashing [TKey] on every read.
  //
  // Nids are stable for the lifetime of a node but may be recycled after
  // [remove]/purge. Consumers that cache nid-indexed state must invalidate
  // or overwrite on structural change.

  /// Sentinel returned by [nidOf] when the key isn't registered. Same value
  /// as the internal [VisibleOrderBuffer.kNotVisible] but exposed separately since callers
  /// should treat it as "unknown key".
  static const int noNid = NodeIdRegistry.noNid;

  /// Returns the internal nid for [key], or [noNid] if the key isn't
  /// currently registered. O(1).
  int nidOf(TKey key) => _nids.nidOf(key);

  /// Returns the key associated with [nid], or null if the nid has been
  /// released. O(1). Consumers that cache nid-indexed state can use this to
  /// detect stale entries after node removal.
  TKey? keyOfNid(int nid) => _nids.keyOf(nid);

  /// The current high-water mark for allocated nids. Nid-indexed dense
  /// arrays maintained externally should grow to at least this length.
  int get nidCapacity => _nids.length;

  /// Returns the nid of the visible node at [visibleIndex]. No [TKey] hash
  /// occurs. Panics (unchecked read) if [visibleIndex] is out of range.
  int visibleNidAt(int visibleIndex) => _order.orderNids[visibleIndex];

  /// Depth for [nid] (0 for roots). No [TKey] hash. [nid] must be live.
  int depthOfNid(int nid) => _depthByNid[nid];

  /// Gets the horizontal indent for the given node.
  double getIndent(TKey key) {
    return getDepth(key) * indentWidth;
  }

  /// Whether the given node is expanded.
  bool isExpanded(TKey key) {
    return _isExpandedKey(key);
  }

  /// Whether the given node has children.
  bool hasChildren(TKey key) {
    final c = _childListOf(key);
    return c != null && c.isNotEmpty;
  }

  /// Gets the number of children for the given node.
  int getChildCount(TKey key) {
    return _childListOf(key)?.length ?? 0;
  }

  /// Returns all descendants of [key] in pre-order (children, grandchildren,
  /// ...). Does not include [key] itself. Returns an empty list if [key] has
  /// no children or is not present.
  ///
  /// Intended for drop-target validation (cycle prevention): a node cannot
  /// be reparented under any of its own descendants.
  List<TKey> getDescendants(TKey key) => _getDescendants(key);

  /// Whether [key] is pending deletion — present in the structural maps but
  /// animating out and scheduled for purge once the animation settles.
  ///
  /// Drop-target resolution should skip pending-deletion rows: they are
  /// visually vanishing and cannot be valid reorder targets. Also used as
  /// the predicate for filtering [rootKeys] / [getChildren] down to the
  /// live sets accepted by [reorderRoots] / [reorderChildren].
  bool isPendingDeletion(TKey key) => _pendingDeletion.contains(key);

  /// Root keys that are not pending deletion.
  ///
  /// Matches the input contract of [reorderRoots]: the reorder API
  /// validates `orderedKeys` against exactly this set and re-appends
  /// pending-deletion entries internally. Passing the full [rootKeys] to
  /// [reorderRoots] would fail the length check when any root is mid-exit.
  List<TKey> get liveRootKeys {
    if (_pendingDeletion.isEmpty) return List<TKey>.of(_roots);
    final result = <TKey>[];
    for (final k in _roots) {
      if (!_pendingDeletion.contains(k)) result.add(k);
    }
    return result;
  }

  /// Children of [parent] that are not pending deletion.
  ///
  /// Matches the input contract of [reorderChildren]. Returns an empty list
  /// if [parent] is not present or has no children.
  List<TKey> getLiveChildren(TKey parent) {
    final full = _childListOf(parent);
    if (full == null || full.isEmpty) return const [];
    if (_pendingDeletion.isEmpty) return List<TKey>.of(full);
    final result = <TKey>[];
    for (final k in full) {
      if (!_pendingDeletion.contains(k)) result.add(k);
    }
    return result;
  }

  /// Returns the zero-based index of [key] within the **live** sibling list
  /// of its parent (or the live root list, if [key] is a root). Returns -1
  /// if [key] is not present or is itself pending deletion.
  ///
  /// Live-space — not full-list-space — so the returned index directly
  /// matches positions in [liveRootKeys] / [getLiveChildren] and the input
  /// space of [reorderRoots] / [reorderChildren].
  int getIndexInParent(TKey key) {
    if (!_hasKey(key) || _pendingDeletion.contains(key)) return -1;
    final parent = _parentKeyOfKey(key);
    final List<TKey> full = parent == null
        ? _roots
        : (_childListOf(parent) ?? <TKey>[]);
    int liveIndex = 0;
    for (final k in full) {
      if (k == key) return liveIndex;
      if (!_pendingDeletion.contains(k)) liveIndex++;
    }
    return -1;
  }

  /// Whether any nodes are currently animating.
  ///
  /// Used by the element and render object to defer expensive operations
  /// (like stale-node eviction and sticky precomputation) during animation.
  ///
  /// **Slide animations are deliberately excluded.** Slide is paint-only —
  /// it does not change layout, sticky geometry, or eviction decisions.
  /// Callers that care about slide state read [hasActiveSlides] instead.
  bool get hasActiveAnimations =>
      _standaloneAnimations.isNotEmpty ||
      _operationGroups.isNotEmpty ||
      (_bulkAnimationGroup != null && !_bulkAnimationGroup!.isEmpty);

  /// Whether any FLIP slide animations are currently active.
  ///
  /// Deliberately separate from [hasActiveAnimations]: slide is paint-only
  /// and must not be mixed into the sticky-throttle / eviction-deferral
  /// signal that [hasActiveAnimations] drives. The sliver element routes
  /// slide-only ticks to [RenderObject.markNeedsPaint] rather than
  /// [RenderObject.markNeedsLayout] based on this flag.
  bool get hasActiveSlides => _slideAnimations.isNotEmpty;

  /// Maximum |currentDelta| across every active slide entry, or 0.0 when
  /// no slides are active.
  ///
  /// The render object uses this as a "slide overreach" to widen its build
  /// and iteration ranges during a FLIP slide: a row whose *structural* y
  /// is outside the viewport can still be painted inside the viewport if
  /// its slide delta translates it there, and conversely a row whose
  /// structural y is inside the viewport can translate out. Both ranges
  /// (build window in performLayout, iteration window in paint/hit-test)
  /// need to extend by this amount on each side to cover the displaced
  /// rows — otherwise a swap of two large subtrees paints a visible gap
  /// where a sliding row should appear.
  ///
  /// Shrinks toward 0.0 as the slide progresses (since entries'
  /// currentDelta lerps to 0), so the transient overbuild contracts with
  /// the animation.
  double get maxActiveSlideAbsDelta {
    if (_slideAnimations.isEmpty) return 0.0;
    double m = 0.0;
    for (final entry in _slideAnimations.values) {
      final d = entry.currentDelta.abs();
      if (d > m) m = d;
    }
    return m;
  }

  /// Current slide delta for [key] in scroll-space y, or 0.0 if the node is
  /// not currently sliding. Read by [RenderSliverTree.paint],
  /// [RenderSliverTree.applyPaintTransform], and the hit-test path on
  /// every frame (no caching — staleness-safe under tick-without-paint).
  double getSlideDelta(TKey key) {
    final slide = _slideAnimations[key];
    if (slide == null) {
      return 0.0;
    }
    return slide.currentDelta;
  }

  /// True when a bulk animation group is currently active and has members
  /// animating in either direction.
  ///
  /// Used by the render object to gate its scalar-offset fast path.
  bool get isBulkAnimating {
    final g = _bulkAnimationGroup;
    if (g == null) return false;
    return g.members.isNotEmpty || g.pendingRemoval.isNotEmpty;
  }

  /// Current animation value of the bulk animation group, or 0.0 if none.
  double get bulkAnimationValue => _bulkAnimationGroup?.value ?? 0.0;

  /// Whether [key] is a member of the bulk animation group (either active
  /// or pending removal at animation end).
  bool isBulkMember(TKey key) {
    final g = _bulkAnimationGroup;
    if (g == null) return false;
    return g.members.contains(key) || g.pendingRemoval.contains(key);
  }

  /// Whether any non-bulk animations (operation groups or standalone) are
  /// currently active. When false and [isBulkAnimating] is true, the render
  /// object can use its scalar-offset fast path for the whole frame.
  bool get hasOpGroupAnimations =>
      _operationGroups.isNotEmpty || _standaloneAnimations.isNotEmpty;

  /// Monotonic counter that bumps whenever the bulk animation group is
  /// created, destroyed, or its member set changes. The render object uses
  /// this to detect when its cached per-position offset cumulatives are stale.
  int get bulkAnimationGeneration => _bulkAnimationGeneration;
  int _bulkAnimationGeneration = 0;

  /// Returns the smallest [_visibleOrder] index among all currently-animating
  /// nodes, or [visibleNodeCount] when none are visible / none are animating.
  ///
  /// Used by the render object to skip the O(N) Pass 1 offset rescan during
  /// animation: everything before the returned index has stable offset and
  /// extent from the prior frame, so only indices `>= firstAnimatingIndex`
  /// need to be recomputed.
  ///
  /// Complexity is O(A) in the number of animating nodes, which is normally
  /// much smaller than the visible-order length.
  int computeFirstAnimatingVisibleIndex() {
    if (!hasActiveAnimations) return _order.length;
    // Cache key combines animation generation with structure generation:
    // the result depends on which keys are animating AND their visible indices.
    final sig = _animationGeneration ^ (_structureGeneration * 2654435761);
    if (sig == _firstAnimatingIndexCacheSig &&
        _firstAnimatingIndexCacheVal <= _order.length) {
      return _firstAnimatingIndexCacheVal;
    }
    int min = _order.length;
    for (final k in _ensureAnimatingKeys()) {
      final idx = _order.indexOf(k);
      if (idx != VisibleOrderBuffer.kNotVisible && idx < min) min = idx;
    }
    _firstAnimatingIndexCacheSig = sig;
    _firstAnimatingIndexCacheVal = min;
    return min;
  }

  /// Debug helper to print bulk animation state.
  /// Call this to verify animation is running correctly.
  void debugPrintBulkAnimationState() {
    if (_bulkAnimationGroup == null) {
      debugPrint('TreeController: No bulk animation group');
      return;
    }
    final controller = _bulkAnimationGroup!.controller;
    debugPrint(
      'TreeController bulk animation: '
      'value=${_bulkAnimationGroup!.value.toStringAsFixed(3)}, '
      'controllerValue=${controller.value.toStringAsFixed(3)}, '
      'status=${controller.status}, '
      'members=${_bulkAnimationGroup!.members.length}, '
      'pendingRemoval=${_bulkAnimationGroup!.pendingRemoval.length}',
    );
  }

  /// Whether the given node is currently animating. O(1) via the cached
  /// [_ensureAnimatingKeys] set (rebuilt lazily when animation membership
  /// changes).
  bool isAnimating(TKey key) {
    if (!hasActiveAnimations) return false;
    return _ensureAnimatingKeys().contains(key);
  }

  /// Gets the animation state for a node, or null if not animating.
  ///
  /// Returns the standalone state if present, a synthetic entering state
  /// for operation group members that are expanding, or null for bulk/
  /// collapsing groups.
  AnimationState? getAnimationState(TKey key) {
    // 1. Standalone animations
    final standalone = _standaloneAnimations[key];
    if (standalone != null) return standalone;

    // 2. Operation group
    final groupKey = _nodeToOperationGroup[key];
    if (groupKey != null) {
      final group = _operationGroups[groupKey];
      if (group != null && !group.pendingRemoval.contains(key)) {
        final status = group.controller.status;
        if (status == AnimationStatus.forward ||
            status == AnimationStatus.completed) {
          return _buildSyntheticEnteringState();
        }
      }
      return null;
    }

    // 3. Bulk group — synthesize entering state for members advancing forward
    // so consumers (e.g. sticky header anchoring) can detect entering nodes.
    final bulk = _bulkAnimationGroup;
    if (bulk != null &&
        bulk.members.contains(key) &&
        !bulk.pendingRemoval.contains(key)) {
      final status = bulk.controller.status;
      if (status == AnimationStatus.forward ||
          status == AnimationStatus.completed) {
        return _buildSyntheticEnteringState();
      }
    }
    return null;
  }

  /// Whether the given node is currently exiting (animating out).
  ///
  /// Exiting nodes should not receive hit tests or user interactions.
  bool isExiting(TKey key) {
    // Check bulk group pending removal
    if (_bulkAnimationGroup?.pendingRemoval.contains(key) == true) return true;
    // Check operation group pending removal
    final groupKey = _nodeToOperationGroup[key];
    if (groupKey != null) {
      final group = _operationGroups[groupKey];
      if (group != null && group.pendingRemoval.contains(key)) return true;
    }
    // Check standalone animations
    final animation = _standaloneAnimations[key];
    return animation != null && animation.type == AnimationType.exiting;
  }

  /// Gets the estimated full extent for a node.
  ///
  /// Returns the cached measured extent if available, otherwise [defaultExtent].
  double getEstimatedExtent(TKey key) {
    return _fullExtents[key] ?? defaultExtent;
  }

  /// Gets the current extent for a node, accounting for animation.
  double getCurrentExtent(TKey key) {
    return getAnimatedExtent(key, _fullExtents[key] ?? defaultExtent);
  }

  /// Gets the animated extent for a node.
  ///
  /// If the node is animating, returns the interpolated extent.
  /// Otherwise returns [fullExtent].
  double getAnimatedExtent(TKey key, double fullExtent) {
    // 1. Check bulk animation group
    if (_bulkAnimationGroup?.members.contains(key) == true) {
      return fullExtent * _bulkAnimationGroup!.value;
    }

    // 2. Check operation group
    final groupKey = _nodeToOperationGroup[key];
    if (groupKey != null) {
      final group = _operationGroups[groupKey];
      if (group != null) {
        final member = group.members[key];
        if (member != null) {
          return member.computeExtent(group.curvedValue, fullExtent);
        }
      }
    }

    // 3. Check standalone animations
    final animation = _standaloneAnimations[key];
    if (animation == null) return fullExtent;

    final t = animationCurve.transform(animation.progress.clamp(0.0, 1.0));
    if (animation.targetExtent == _unknownExtent) {
      return animation.type == AnimationType.entering
          ? fullExtent * t
          : fullExtent * (1.0 - t);
    }
    return lerpDouble(animation.startExtent, animation.targetExtent, t)!;
  }

  /// Starts a FLIP slide animation for every visible node whose position in
  /// scroll-space changed between [priorOffsets] (pre-mutation) and
  /// [currentOffsets] (post-mutation). Produce both with
  /// [RenderSliverTree.snapshotVisibleOffsets] — the first **before** the
  /// structural mutation, the second from inside a
  /// [WidgetsBinding.addPostFrameCallback] **after** the mutation's layout
  /// has run.
  ///
  /// A node present in both maps with `priorOffsets[key] != currentOffsets[key]`
  /// receives a new [SlideAnimation] with `startDelta = prior - current`.
  /// A node only in one map is ignored (it was either added or removed and
  /// has its own enter/exit animation for that). A zero delta installs no
  /// entry.
  ///
  /// Composes with an in-flight slide: if [key] already has an entry,
  /// its `startDelta` is replaced with `currentDelta_old + (prior - current)`
  /// and `progress` is reset to 0.0. This preserves the currently rendered
  /// position as the new animation's starting point (no visual jump).
  ///
  /// Slide is paint-only: it does **not** fire the structural-change channel,
  /// does **not** touch layout, and is **not** counted in
  /// [hasActiveAnimations]. It fires on the animation-listener channel on
  /// every tick and on completion; see the slide tick handler for ordering.
  ///
  /// Safe to invoke from inside [RenderObject.performLayout]: the slide is
  /// driven by a [Ticker] whose first callback fires on the next vsync (in
  /// `SchedulerPhase.transientCallbacks`). No listeners fire synchronously
  /// from this call, so there is no path that reaches
  /// `markNeedsLayout`/`markNeedsPaint` on a sliver currently being laid
  /// out. The per-entry `currentDelta` is seeded to `startDelta`, so the
  /// paint pass of the same frame reads the pre-mutation position.
  void animateSlideFromOffsets(
    Map<TKey, double> priorOffsets,
    Map<TKey, double> currentOffsets, {
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.easeOutCubic,
  }) {
    if (animationDuration == Duration.zero || duration == Duration.zero) {
      // No-animation mode: drop any in-flight slide and return. Callers that
      // want the slide machinery to "settle" synchronously see
      // hasActiveSlides == false immediately.
      if (_slideAnimations.isNotEmpty) {
        _slideAnimations.clear();
        _slideTicker?.stop();
      }
      return;
    }

    int installed = 0;
    for (final entry in currentOffsets.entries) {
      final key = entry.key;
      final current = entry.value;
      final prior = priorOffsets[key];
      if (prior == null) continue;
      final rawDelta = prior - current;
      final existing = _slideAnimations[key];
      if (existing == null) {
        if (rawDelta == 0.0) continue;
        _slideAnimations[key] = SlideAnimation<TKey>(
          startDelta: rawDelta,
          curve: curve,
        );
        installed++;
      } else {
        // Composition: the new prior/current describes the mutation that just
        // happened, but the node was already sliding. Preserve the currently
        // rendered visual position (existing.currentDelta + rawDelta gives
        // "how far is the node from its new structural offset") as the new
        // starting delta so the slide continues seamlessly.
        final composed = existing.currentDelta + rawDelta;
        if (composed == 0.0) {
          _slideAnimations.remove(key);
          continue;
        }
        existing.startDelta = composed;
        existing.currentDelta = composed;
        existing.progress = 0.0;
        existing.curve = curve;
        installed++;
      }
    }

    if (_slideAnimations.isEmpty) {
      _slideTicker?.stop();
      return;
    }
    if (installed == 0) return;

    // (Re)start the shared progress clock. Stop-then-start resets the
    // ticker's elapsed time to zero so progress begins at 0 for every entry
    // in this batch. [Ticker.start] does NOT fire callbacks synchronously —
    // the first tick lands on the next vsync, so this is safe to call from
    // inside [RenderObject.performLayout].
    _slideDuration = duration;
    final ticker = _slideTicker ??= _vsync.createTicker(_onSlideTick);
    if (ticker.isActive) ticker.stop();
    ticker.start();
  }

  /// Tick handler for slide animations. Elapsed time comes from the ticker
  /// (reset to zero on each fresh batch via stop+start in
  /// [animateSlideFromOffsets]). **Ordering matters** — see the inline
  /// comments. Final zero-delta paint is guaranteed because:
  ///
  /// 1. Progress and [SlideAnimation.currentDelta] are updated for every
  ///    entry; on completion, currentDelta is snapped to exact 0.0 so the
  ///    final painted position matches structural layout pixel-exactly.
  /// 2. The animation-listener channel fires **before** the map is cleared.
  ///    [hasActiveSlides] is still true, so the sliver element's
  ///    `_onAnimationTick` takes the slide branch and schedules
  ///    `markNeedsPaint`. That paint reads `getSlideDelta(key) == 0.0`.
  /// 3. Only after the paint has been scheduled do we clear the map and
  ///    stop the ticker. No further tick will fire, so there is no "second
  ///    paint needed" window.
  void _onSlideTick(Duration elapsed) {
    if (_slideAnimations.isEmpty) {
      _slideTicker?.stop();
      return;
    }
    final totalUs = _slideDuration.inMicroseconds;
    final raw = totalUs <= 0 ? 1.0 : elapsed.inMicroseconds / totalUs;
    final complete = raw >= 1.0 - 1e-9;

    for (final entry in _slideAnimations.values) {
      entry.progress = complete ? 1.0 : raw.clamp(0.0, 1.0);
      final t = entry.curve.transform(entry.progress);
      entry.currentDelta = complete
          ? 0.0
          : lerpDouble(entry.startDelta, 0.0, t)!;
    }

    _notifyAnimationListeners();

    if (complete) {
      _slideAnimations.clear();
      _slideTicker?.stop();
    }
  }

  /// Stores the measured full extent for a node.
  ///
  /// Called by the render object after laying out a child.
  void setFullExtent(TKey key, double extent) {
    final oldExtent = _fullExtents[key];

    // Check operation group member — resolve unknown extents
    final groupKey = _nodeToOperationGroup[key];
    if (groupKey != null) {
      final group = _operationGroups[groupKey];
      if (group != null) {
        final member = group.members[key];
        if (member != null) {
          if (member.targetExtent == _unknownExtent) {
            final status = group.controller.status;
            if (status == AnimationStatus.forward ||
                status == AnimationStatus.completed) {
              member.targetExtent = extent;
            }
          } else if (oldExtent != extent) {
            // targetExtent is the "fully expanded" reference (value=1);
            // startExtent is always 0 (fully collapsed). Update targetExtent
            // regardless of direction — during reverse (collapsing), setting
            // startExtent = extent would make the lerp return `extent` at
            // value=0 instead of 0, so the node would never collapse to zero.
            member.targetExtent = extent;
          }
        }
      }
      _fullExtents[key] = extent;
      if (oldExtent != extent) _invalidateFullOffsetPrefix();
      return;
    }

    if (oldExtent == extent) {
      // Still resolve unknown targets even when extent matches.
      final animation = _standaloneAnimations[key];
      if (animation != null && animation.targetExtent == _unknownExtent) {
        if (animation.type == AnimationType.entering) {
          animation.targetExtent = extent;
          animation.updateExtent(animationCurve);
        }
      }
      return;
    }
    _fullExtents[key] = extent;
    _invalidateFullOffsetPrefix();
    // If node is animating with unknown target, update the animation
    final animation = _standaloneAnimations[key];
    if (animation != null && animation.targetExtent == _unknownExtent) {
      // Now we know the real extent - update the animation state
      if (animation.type == AnimationType.entering) {
        animation.targetExtent = extent;
        animation.updateExtent(animationCurve);
      }
    }
    // Also update if extent changed and node is animating
    else if (animation != null) {
      if (animation.type == AnimationType.entering) {
        animation.targetExtent = extent;
        animation.updateExtent(animationCurve);
      }
      // For exiting animations, startExtent is historical (the extent at the
      // moment the exit began, potentially captured mid-transition from an
      // earlier source). Overwriting it with the freshly-measured full extent
      // would retroactively rewrite where the exit started and jump the row
      // forward on the next tick. Let the exit run from its original
      // startExtent to 0 without interference.
    }
  }

  /// Gets the index of a node in the visible order, or -1 if not visible.
  int getVisibleIndex(TKey key) {
    return _order.indexOf(key);
  }

  /// Gets the parent key for the given node, or null if it is a root.
  TKey? getParent(TKey key) => _parentKeyOfKey(key);

  // ══════════════════════════════════════════════════════════════════════════
  // SCROLL-TO-KEY SUPPORT
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns the sliver-space scroll offset of [key], or null if [key] is
  /// not in the current visible order (e.g., ancestors collapsed, or key
  /// not registered). The offset corresponds to the node's top edge within
  /// the [SliverTree]'s own scroll extent.
  ///
  /// Walks preceding visible nodes and sums their full (non-animated)
  /// extents, preferring measured values from the render pass and falling
  /// back to [extentEstimator] or [defaultExtent] for nodes that have
  /// never been laid out.
  ///
  /// For scrollables that contain other slivers above the tree, add those
  /// slivers' combined extent to the returned value before seeking.
  double? scrollOffsetOf(
    TKey key, {
    double Function(TKey key)? extentEstimator,
  }) {
    final targetIndex = _order.indexOf(key);
    if (targetIndex < 0) return null;
    if (extentEstimator == null) {
      // O(1) via cached prefix sum (rebuilt lazily when invalidated).
      return _fullOffsetAt(targetIndex);
    }
    // Slow path: caller supplied an estimator for un-measured nodes. We can't
    // use the cache because it falls back to [defaultExtent], which may
    // disagree with the caller's estimator.
    double offset = 0.0;
    for (int i = 0; i < targetIndex; i++) {
      final k = _nids.keyOfUnchecked(_order.orderNids[i]);
      final measured = _fullExtents[k];
      if (measured != null) {
        offset += measured;
      } else {
        offset += extentEstimator(k);
      }
    }
    return offset;
  }

  /// Returns the best-known full (non-animated) extent for [key]: the
  /// measured value if the node has ever been laid out, otherwise
  /// [extentEstimator] if supplied, otherwise [defaultExtent]. Matches the
  /// fallback chain used by [scrollOffsetOf].
  double extentOf(TKey key, {double Function(TKey key)? extentEstimator}) {
    final measured = _fullExtents[key];
    if (measured != null) return measured;
    if (extentEstimator != null) return extentEstimator(key);
    return defaultExtent;
  }

  /// Immediately expands every collapsed ancestor of [key] so that [key]
  /// becomes part of the visible order. Expansion is synchronous (no
  /// animation) so a subsequent [scrollOffsetOf] call sees the updated
  /// structure. Returns the number of ancestors that were expanded.
  int ensureAncestorsExpanded(TKey key) {
    final toExpand = <TKey>[];
    TKey? current = _parentKeyOfKey(key);
    while (current != null) {
      if (!isExpanded(current)) toExpand.add(current);
      current = _parentKeyOfKey(current);
    }
    if (toExpand.isEmpty) return 0;
    // Expand root-first: each expansion operates on a list that already
    // contains the parent being expanded against.
    for (int i = toExpand.length - 1; i >= 0; i--) {
      expand(key: toExpand[i], animate: false);
    }
    return toExpand.length;
  }

  /// Animates [scrollController] to reveal [key] in its attached viewport.
  ///
  /// [ancestorExpansion] controls how collapsed ancestors of [key] are
  /// handled:
  /// - [AncestorExpansionMode.none]: ancestors are not expanded. If any
  ///   ancestor of [key] is collapsed, returns false without scrolling.
  /// - [AncestorExpansionMode.immediate] (default): ancestors are expanded
  ///   synchronously (no animation) before the scroll begins, so layout is
  ///   already settled when [scrollController] starts moving.
  /// - [AncestorExpansionMode.animated]: ancestors animate open while the
  ///   scroll runs concurrently. Each animation tick the scroll target is
  ///   re-derived from the current animated offsets so it stays glued to
  ///   the moving target. A precise jump lands on the settled offset once
  ///   both finish. In this mode the concurrent phase runs for
  ///   `max(duration, animationDuration)` so both the expansion and the
  ///   scroll have time to complete.
  ///
  /// [alignment] controls placement within the viewport:
  /// 0.0 pins the row's top to the viewport top (default), 0.5 centers,
  /// 1.0 pins the row's bottom to the viewport bottom.
  ///
  /// For nodes that have never been laid out, [extentEstimator] supplies
  /// a fallback height; without it, [defaultExtent] is used. A mismatch
  /// between estimate and actual measurement may cause slight over- or
  /// undershoot — the render pass that includes the target will snap to
  /// the exact offset on the next frame.
  ///
  /// [sliverBaseOffset] is the scroll-space distance from the top of the
  /// scrollable's content to the top of this sliver. It is added to the
  /// computed sliver-local offset. Leave at 0.0 when [SliverTree] is the
  /// first (or only) sliver in the [CustomScrollView].
  ///
  /// Returns true if a scroll was issued, false if [key] could not be
  /// resolved or [scrollController] has no attached position.
  Future<bool> animateScrollToKey(
    TKey key, {
    required ScrollController scrollController,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
    double alignment = 0.0,
    AncestorExpansionMode ancestorExpansion = AncestorExpansionMode.immediate,
    double Function(TKey key)? extentEstimator,
    double sliverBaseOffset = 0.0,
  }) async {
    assert(
      alignment >= 0.0 && alignment <= 1.0,
      "alignment must be between 0.0 and 1.0",
    );

    if (!scrollController.hasClients) return false;

    // Collect any ancestors that are currently collapsed.
    final collapsedAncestors = <TKey>[];
    {
      TKey? current = _parentKeyOfKey(key);
      while (current != null) {
        if (!isExpanded(current)) collapsedAncestors.add(current);
        current = _parentKeyOfKey(current);
      }
    }

    // Animated concurrent expand+scroll. Falls back to the standard path
    // when there's nothing to expand or when animations are disabled.
    if (ancestorExpansion == AncestorExpansionMode.animated &&
        collapsedAncestors.isNotEmpty &&
        animationDuration != Duration.zero &&
        duration != Duration.zero) {
      return _animatedConcurrentScroll(
        key: key,
        ancestors: collapsedAncestors,
        scrollController: scrollController,
        duration: duration,
        curve: curve,
        alignment: alignment,
        extentEstimator: extentEstimator,
        sliverBaseOffset: sliverBaseOffset,
      );
    }

    if (ancestorExpansion == AncestorExpansionMode.none &&
        collapsedAncestors.isNotEmpty) {
      return false;
    }

    if (collapsedAncestors.isNotEmpty) {
      ensureAncestorsExpanded(key);
    }

    final sliverOffset = scrollOffsetOf(key, extentEstimator: extentEstimator);
    if (sliverOffset == null) return false;

    final position = scrollController.position;
    final viewportExtent = position.viewportDimension;
    final rowExtent = extentOf(key, extentEstimator: extentEstimator);
    final rawTarget =
        sliverBaseOffset +
        sliverOffset -
        (viewportExtent - rowExtent) * alignment;
    final clamped = rawTarget.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (duration == Duration.zero) {
      position.jumpTo(clamped);
    } else {
      await position.animateTo(clamped, duration: duration, curve: curve);
    }
    return true;
  }

  /// Runs ancestor expansion concurrently with a scroll animation, with
  /// each animation tick re-deriving the target from the current animated
  /// offsets. Required because the rendered sliver's `scrollExtent` uses
  /// animated extents — `position.maxScrollExtent` is undersized while
  /// ancestors grow, so a one-shot `animateTo` would clamp short.
  Future<bool> _animatedConcurrentScroll({
    required TKey key,
    required List<TKey> ancestors,
    required ScrollController scrollController,
    required Duration duration,
    required Curve curve,
    required double alignment,
    required double Function(TKey key)? extentEstimator,
    required double sliverBaseOffset,
  }) async {
    final position = scrollController.position;
    final initialPixels = position.pixels;

    // Dedicated progress animation for the scroll curve. Using an
    // AnimationController (rather than scheduler timestamps or a
    // wall-clock Stopwatch) gives three properties at once:
    //
    //   • Safe to create outside a frame. `Ticker._startTime` is set on
    //     the first tick via `_startTime ??= timeStamp`, so calling this
    //     from e.g. a button-press handler never trips the
    //     `currentFrameTimeStamp != null` assertion.
    //
    //   • Correctly anchors t=0 to the first animation frame, not to the
    //     last vsync before the call. Reading
    //     `SchedulerBinding.currentSystemFrameTimeStamp` at call time
    //     would capture whenever the last frame happened to render — if
    //     the app was idle for hundreds of ms before the button tap, the
    //     very first follower tick would see `elapsed >> duration`,
    //     clamp progress to 1.0, and jumpTo the final offset in one
    //     frame (visible as an instant snap with no animation).
    //
    //   • Drives the same Ticker pipeline as the expansion groups, so
    //     FakeAsync widget tests advance all timelines together with
    //     `tester.pump(duration)`.
    final scrollProgress = AnimationController(
      vsync: _vsync,
      duration: duration,
    );
    scrollProgress.addListener(_notifyAnimationListeners);

    // Root-first: each expansion runs against an already-visible parent.
    for (int i = ancestors.length - 1; i >= 0; i--) {
      expand(key: ancestors[i], animate: true);
    }

    // Snapshot the operation groups we just started. We wait on identity
    // (not operationKey lookup) so a concurrent collapse + re-expand of
    // the same ancestor — which would swap in a fresh group under the
    // same key — does not mask our targets as already settled.
    final startedGroups = <OperationGroup<TKey>>[];
    for (final ancestor in ancestors) {
      final group = _operationGroups[ancestor];
      if (group != null) startedGroups.add(group);
    }

    scrollProgress.forward();

    void follower() {
      final targetIdx = _order.indexOf(key);
      if (targetIdx < 0) return;
      final tCurved = curve.transform(scrollProgress.value);

      // Base offset from the cached full-extent prefix sum (O(1) amortized).
      // Then correct for each animating node whose visible index precedes
      // the target: swap its full extent for its current (animated) extent.
      // The number of animating nodes is typically tiny compared to N.
      double currentOffset = _fullOffsetAt(targetIdx);
      void correct(TKey k) {
        final idx = _order.indexOf(k);
        if (idx < 0 || idx >= targetIdx) return;
        final full = _fullExtents[k] ?? defaultExtent;
        currentOffset += getCurrentExtent(k) - full;
      }

      for (final group in _operationGroups.values) {
        for (final k in group.members.keys) {
          correct(k);
        }
      }
      final bulk = _bulkAnimationGroup;
      if (bulk != null) {
        for (final k in bulk.members) {
          correct(k);
        }
      }
      for (final k in _standaloneAnimations.keys) {
        correct(k);
      }

      final rowExtent = getCurrentExtent(key);
      final viewportExtent = position.viewportDimension;
      final desired =
          sliverBaseOffset +
          currentOffset -
          (viewportExtent - rowExtent) * alignment;
      final desiredClamped = desired.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      final scroll = initialPixels + (desiredClamped - initialPixels) * tCurved;
      position.jumpTo(
        scroll.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }

    addAnimationListener(follower);

    // Wait for two independent timelines to both complete:
    //
    //   1. The dedicated scroll progress controller ([scrollProgress]),
    //      so the curve actually reaches 1.0 via the follower.
    //   2. Every ancestor expansion's terminal V=1.0 tick. That tick fires
    //      on the vsync AFTER the nominal duration (Flutter's
    //      `_InterpolationSimulation.isDone` transitions true only once
    //      `elapsed > duration`), and is observable externally by the
    //      operation group's identity disappearing from [_operationGroups]
    //      (the status listener removes + disposes it when completed).
    //
    // The previous implementation awaited `Future.delayed(totalMs)`, a
    // wall-clock timer. Because the terminal tick lands ~1 frame after
    // the nominal duration, the timer consistently removed the follower
    // BEFORE the tick fired — the scroll froze at the next-to-last
    // follower call (V < 1), and the post-loop jumpTo then snapped the
    // residual distance in a single frame. Visible as an end-of-scroll
    // hitch whose magnitude scales with the fanout of collapsed
    // ancestors (more animating preceding nodes → larger residual).
    //
    // Yielding via `endOfFrame` keeps the ticker driving the follower
    // between polls, so each ancestor's final V=1.0 tick runs through
    // the follower while it is still registered.
    while (true) {
      if (!scrollController.hasClients) {
        removeAnimationListener(follower);
        scrollProgress.dispose();
        return true;
      }
      final scrollDone =
          scrollProgress.status == AnimationStatus.completed ||
          scrollProgress.status == AnimationStatus.dismissed;
      bool expansionDone = true;
      for (final g in startedGroups) {
        if (identical(_operationGroups[g.operationKey], g)) {
          expansionDone = false;
          break;
        }
      }
      if (scrollDone && expansionDone) break;
      await SchedulerBinding.instance.endOfFrame;
    }

    removeAnimationListener(follower);
    scrollProgress.dispose();

    if (!scrollController.hasClients) return true;

    // Final precise snap. In the nominal case the follower already landed
    // on the settled target (every captured group fired its V=1.0 tick
    // through the follower before the loop exited), so this jump is a
    // no-op. It still matters when a caller-provided [extentEstimator]
    // disagrees with [defaultExtent] for unmeasured preceding nodes, or
    // when an ancestor expansion was cancelled mid-flight (e.g. user
    // collapse) and its group vanished before reaching V=1.
    final finalOffset = scrollOffsetOf(key, extentEstimator: extentEstimator);
    if (finalOffset == null) return true;
    final finalPosition = scrollController.position;
    final viewportExtent = finalPosition.viewportDimension;
    final rowExtent = extentOf(key, extentEstimator: extentEstimator);
    final finalTarget =
        sliverBaseOffset +
        finalOffset -
        (viewportExtent - rowExtent) * alignment;
    finalPosition.jumpTo(
      finalTarget.clamp(
        finalPosition.minScrollExtent,
        finalPosition.maxScrollExtent,
      ),
    );
    return true;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ANIMATION LISTENERS
  // ══════════════════════════════════════════════════════════════════════════

  /// Registers a callback that fires on every animation tick.
  ///
  /// Unlike [addListener], these callbacks fire for pure animation progress
  /// updates (no structural changes). Use this to trigger repaint/relayout
  /// without scheduling garbage collection.
  void addAnimationListener(VoidCallback listener) {
    _animationListeners.add(listener);
  }

  /// Removes a previously registered animation listener.
  void removeAnimationListener(VoidCallback listener) {
    _animationListeners.remove(listener);
  }

  void _notifyAnimationListeners() {
    // Snapshot before iteration so a listener that removes itself during
    // the callback doesn't trigger ConcurrentModificationError.
    final listeners = List<VoidCallback>.of(_animationListeners);
    for (final listener in listeners) {
      listener();
    }
  }

  /// Registers a callback that fires when a single node's data changes
  /// without any structural change (e.g. after [updateNode]).
  ///
  /// The callback receives the changed node's key. Use this to rebuild
  /// only the affected row without scanning every mounted child.
  void addNodeDataListener(void Function(TKey key) listener) {
    _nodeDataListeners.add(listener);
  }

  /// Removes a previously registered node-data listener.
  void removeNodeDataListener(void Function(TKey key) listener) {
    _nodeDataListeners.remove(listener);
  }

  /// Fires a per-node data-changed notification, or records the intent
  /// when inside [runBatch]. Unlike [_notifyStructural], callers pass the
  /// affected key so listeners can do targeted work.
  void _notifyNodeDataChanged(TKey key) {
    if (_batchDepth > 0) {
      (_batchDirtyDataNodes ??= <TKey>{}).add(key);
      return;
    }
    _fireNodeDataListeners(key);
  }

  void _fireNodeDataListeners(TKey key) {
    // Snapshot before iteration — listeners may remove themselves.
    final listeners = List<void Function(TKey)>.of(_nodeDataListeners);
    for (final listener in listeners) {
      listener(key);
    }
  }

  /// Registers a callback that fires on structural mutations with an
  /// optional set of affected keys. See [_structuralListeners] for the
  /// semantics of the argument.
  ///
  /// This is a finer-grained channel than [addListener] ([ChangeNotifier]).
  /// External callers that only need to know "something changed" can keep
  /// using [addListener] — [notifyListeners] still fires from
  /// [_notifyStructural]. Listeners that can do targeted work (e.g. the
  /// sliver tree element refreshing only specific mounted rows) should
  /// prefer this channel.
  void addStructuralListener(void Function(Set<TKey>? affectedKeys) listener) {
    _structuralListeners.add(listener);
  }

  /// Removes a previously registered structural listener.
  void removeStructuralListener(
    void Function(Set<TKey>? affectedKeys) listener,
  ) {
    _structuralListeners.remove(listener);
  }

  void _fireStructuralListeners(Set<TKey>? affectedKeys) {
    // Snapshot before iteration so a listener that synchronously mutates
    // the controller (triggering a reentrant notify) does not corrupt this
    // walk. Same pattern as [_fireNodeDataListeners].
    final listeners = List<void Function(Set<TKey>?)>.of(_structuralListeners);
    for (final listener in listeners) {
      listener(affectedKeys);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BATCHING
  // ══════════════════════════════════════════════════════════════════════════

  /// Runs [body] with structural notifications coalesced into a single
  /// [notifyListeners] call fired after [body] returns.
  ///
  /// Any number of mutations inside [body] — [insertRoot], [insert],
  /// [remove], [expand], [collapse], [updateNode], [moveNode], etc. — fire
  /// at most one structural notification when the outermost [runBatch]
  /// exits. Nested [runBatch] calls coalesce into the outermost one.
  ///
  /// Animation tick notifications ([addAnimationListener]) are not affected
  /// and continue to fire in real time.
  ///
  /// The notification fires even if [body] throws, so listeners always see
  /// the post-batch state. Exceptions propagate after the notification.
  T runBatch<T>(T Function() body) {
    _batchDepth++;
    try {
      return body();
    } finally {
      _batchDepth--;
      if (_batchDepth == 0) {
        final didStructural = _batchDidRequestStructural;
        final dirtyData = _batchDirtyDataNodes;
        final structuralAffected = _batchAffectedStructuralUnknown
            ? null
            : _batchAffectedStructuralKeys;
        _batchDidRequestStructural = false;
        _batchDirtyDataNodes = null;
        _batchAffectedStructuralKeys = null;
        _batchAffectedStructuralUnknown = false;
        // Fire structural first: a structural notify causes the element to
        // mark itself for a full refresh, which subsumes any data-only
        // refresh for the same keys. Firing data first would queue a
        // targeted refresh that the full refresh then redundantly repeats.
        if (didStructural) {
          _fireStructuralListeners(structuralAffected);
          notifyListeners();
        }
        if (dirtyData != null && dirtyData.isNotEmpty) {
          for (final key in dirtyData) {
            _fireNodeDataListeners(key);
          }
        }
      }
    }
  }

  /// Fires a structural notification, or records the intent when inside
  /// [runBatch]. All in-controller mutation paths call this instead of
  /// [notifyListeners] directly so batching works uniformly.
  ///
  /// [affectedKeys] narrows the refresh scope for listeners subscribed via
  /// [addStructuralListener]:
  ///   - `null` — scope unknown; listeners should do a full refresh.
  ///   - empty set — structural change occurred but no mounted row's
  ///     builder output changed; listeners need only relayout/GC.
  ///   - non-empty set — exactly these keys need refresh.
  ///
  /// Inside [runBatch], `null` is a poison pill: any in-batch call with
  /// `null` forces the coalesced exit notification to use `null`, even if
  /// other in-batch calls carried specific sets.
  ///
  /// External observers via [addListener] (ChangeNotifier) always see a
  /// single `notifyListeners()` fire regardless of [affectedKeys].
  void _notifyStructural({Set<TKey>? affectedKeys}) {
    if (_batchDepth > 0) {
      _batchDidRequestStructural = true;
      if (affectedKeys == null) {
        _batchAffectedStructuralUnknown = true;
        _batchAffectedStructuralKeys = null;
      } else if (!_batchAffectedStructuralUnknown) {
        (_batchAffectedStructuralKeys ??= <TKey>{}).addAll(affectedKeys);
      }
      return;
    }
    _fireStructuralListeners(affectedKeys);
    notifyListeners();
  }

  /// Binary-searches [siblings] for the sorted insertion index of [node]
  /// using [comparator]. Skips pending-deletion keys.
  ///
  /// Fast path (no pending deletions): a plain binary search over [siblings]
  /// with no allocation. Slow path: a linear scan that skips pending-deletion
  /// entries, still without allocating an intermediate filtered list.
  int _sortedIndex(List<TKey> siblings, TreeNode<TKey, TData> node) {
    assert(comparator != null);
    final cmp = comparator!;
    if (_pendingDeletion.isEmpty) {
      int lo = 0, hi = siblings.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        final midNode = _dataOf(siblings[mid])!;
        if (cmp(midNode, node) <= 0) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo;
    }
    // Pending-deletion keys are intermixed, so a binary search would need a
    // rank-mapping structure to locate live entries. A single linear scan is
    // allocation-free and competitive for typical sibling counts.
    for (int i = 0; i < siblings.length; i++) {
      final k = siblings[i];
      if (_pendingDeletion.contains(k)) continue;
      final other = _dataOf(k)!;
      if (cmp(other, node) > 0) return i;
    }
    return siblings.length;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TREE MUTATIONS
  // ══════════════════════════════════════════════════════════════════════════

  /// Initializes the tree with the given root nodes.
  ///
  /// This clears any existing state.
  void setRoots(List<TreeNode<TKey, TData>> roots) {
    final seen = <TKey>{};
    for (final node in roots) {
      if (!seen.add(node.key)) {
        throw ArgumentError("Duplicate key ${node.key} in setRoots");
      }
    }
    _clear();
    final sorted = comparator != null
        ? (List.of(roots)..sort(comparator))
        : roots;
    for (final node in sorted) {
      _adoptKey(node.key);
      _dataByNid[_nids[node.key]!] = node;
      _setParentKey(node.key, null);
      _setChildList(node.key, []);
      _setDepthKey(node.key, 0);
      _setExpandedKey(node.key, false);
      _roots.add(node.key);
      _order.addKey(node.key);
    }
    _rebuildVisibleIndex();
    _structureGeneration++;
    // Bulk wholesale replacement: _clear() purged every prior key. Callers
    // frequently reuse the same TKey identities, and any retained mounted
    // Element's builder output may differ. Keep the conservative full
    // refresh rather than try to enumerate every retained key.
    _notifyStructural();
  }

  /// Adds a new root node to the tree.
  ///
  /// If [animate] is true, the node will animate in.
  /// If the node is currently pending deletion (animating out from a previous
  /// remove), the deletion is cancelled and the node animates back in.
  void insertRoot(
    TreeNode<TKey, TData> node, {
    int? index,
    bool animate = true,
    bool preservePendingSubtreeState = false,
  }) {
    if (animationDuration == Duration.zero) animate = false;
    // If the node is pending deletion, cancel the deletion
    if (_pendingDeletion.contains(node.key)) {
      // If the node was pending deletion under a non-null parent, detach
      // it and re-attach as a root. Without this relocation, cancelling
      // the deletion would resurrect it under its old parent, silently
      // ignoring the insertRoot() contract.
      final oldParent = _parentKeyOfKey(node.key);
      if (oldParent != null) {
        _childListOf(oldParent)?.remove(node.key);
        _setParentKey(node.key, null);
        final effectiveIndex =
            index ?? (comparator != null ? _sortedIndex(_roots, node) : null);
        if (effectiveIndex != null && effectiveIndex < _roots.length) {
          _roots.insert(effectiveIndex, node.key);
        } else {
          _roots.add(node.key);
        }
        _refreshSubtreeDepths(node.key, 0);
      } else if (index != null) {
        // Already a root — honor an explicitly requested index by
        // relocating within _roots.
        final current = _roots.indexOf(node.key);
        if (current != -1) {
          _roots.removeAt(current);
          final clamped = index.clamp(0, _roots.length);
          _roots.insert(clamped, node.key);
        }
      }
      _cancelDeletion(
        node.key,
        animate: animate,
        preserveSubtreeState: preservePendingSubtreeState,
      );
      _adoptKey(node.key);
      _dataByNid[_nids[node.key]!] = node;
      if (preservePendingSubtreeState) {
        _rebuildVisibleOrder();
        _structureGeneration++;
        // Cancelling a pending deletion restores the node (and possibly
        // descendants) to the tree. Downstream builder-output effects span
        // the restored subtree plus any ancestor whose hasChildren state
        // flips; enumerating all of that precisely is complex, so fall back
        // to a full refresh.
        _notifyStructural();
        return;
      }
      // Reset expansion state so a subsequent expand() works cleanly.
      // Descendants that were mid-exit are left alone by _cancelDeletion
      // and continue animating out under the restored parent via
      // _rebuildVisibleOrder's "collapsed with active animations" branch.
      // Yanking them here would visually jump following rows upward by
      // the descendant's current extent in a single frame.
      _setExpandedKey(node.key, false);
      _rebuildVisibleOrder();
      _structureGeneration++;
      _notifyStructural();
      return;
    }

    // Node is already present (e.g. restored by an ancestor's
    // _cancelDeletion, or a live re-insert). Update the data and — if the
    // caller requested a different location — relocate it to honor the
    // insertRoot(index:) contract instead of silently dropping the index.
    if (_hasKey(node.key)) {
      _adoptKey(node.key);
      _dataByNid[_nids[node.key]!] = node;
      final currentParent = _parentKeyOfKey(node.key);
      if (currentParent != null) {
        // Different parent — delegate to moveNode.
        moveNode(node.key, null, index: index);
        return;
      }
      final currentRootIndex = _roots.indexOf(node.key);
      final desiredIndex =
          index ?? (comparator != null ? _sortedIndex(_roots, node) : null);
      final wantsRelocate =
          desiredIndex != null &&
          desiredIndex != currentRootIndex &&
          // Appending is a no-op if already at the end.
          !(currentRootIndex == _roots.length - 1 &&
              desiredIndex >= _roots.length);
      if (wantsRelocate) {
        _roots.removeAt(currentRootIndex);
        final clamped = desiredIndex.clamp(0, _roots.length);
        _roots.insert(clamped, node.key);
        _rebuildVisibleOrder();
        _structureGeneration++;
      }
      // Data payload for node.key was just overwritten — rebuild its row.
      _notifyStructural(affectedKeys: <TKey>{node.key});
      return;
    }

    // Add to data structures
    _adoptKey(node.key);
    _dataByNid[_nids[node.key]!] = node;
    _setParentKey(node.key, null);
    _setChildList(node.key, []);
    _setDepthKey(node.key, 0);
    _setExpandedKey(node.key, false);

    // Add to roots list
    final effectiveIndex =
        index ?? (comparator != null ? _sortedIndex(_roots, node) : null);
    // Compute visible insert position BEFORE modifying _roots, since
    // _calculateRootInsertIndex reads _roots[effectiveIndex].
    final visibleInsertIndex =
        effectiveIndex != null && effectiveIndex < _roots.length
        ? _calculateRootInsertIndex(effectiveIndex)
        : _order.length;
    if (effectiveIndex != null && effectiveIndex < _roots.length) {
      _roots.insert(effectiveIndex, node.key);
    } else {
      _roots.add(node.key);
    }

    // Add to visible order (root nodes are always visible)
    final insertIndex = visibleInsertIndex;
    _order.insertKey(insertIndex, node.key);
    _updateIndicesFrom(insertIndex);
    _structureGeneration++;

    if (animate) {
      _startStandaloneEnterAnimation(node.key);
    }

    // Fresh root: the new key enters visible order via createChild, not a
    // refresh. Roots have no parent whose hasChildren could flip, and no
    // sibling's builder output depends on the new key. Empty set.
    _notifyStructural(affectedKeys: const {});
  }

  /// Calculates the visible order index for inserting a root at the given root index.
  int _calculateRootInsertIndex(int rootIndex) {
    if (rootIndex == 0) return 0;
    if (rootIndex >= _roots.length) return _order.length;

    // Find the root at the given index and return its visible index
    final rootId = _roots[rootIndex];
    final idx = _order.indexOf(rootId);
    return idx == VisibleOrderBuffer.kNotVisible ? _order.length : idx;
  }

  /// Adds children to a node.
  ///
  /// The children are added but not visible until the parent is expanded.
  /// If the parent already has children, the old children and their
  /// descendants are purged from all data structures first.
  void setChildren(TKey parentKey, List<TreeNode<TKey, TData>> children) {
    assert(_hasKey(parentKey), 'Parent node $parentKey not found');
    assert(
      !_pendingDeletion.contains(parentKey),
      'Cannot setChildren on $parentKey while it is animating out '
      '(pending deletion). The parent will be purged when its exit animation '
      'completes, leaving the new children orphaned.',
    );
    final seen = <TKey>{};
    for (final child in children) {
      if (!seen.add(child.key)) {
        throw ArgumentError(
          "Duplicate key ${child.key} in setChildren($parentKey)",
        );
      }
      if (child.key == parentKey) {
        throw ArgumentError(
          "setChildren($parentKey): child key ${child.key} equals parentKey "
          "(a node cannot be its own child)",
        );
      }
      // Reject keys that already exist under a different parent — silently
      // overwriting _childListOf(child.key) = [] below would orphan the existing
      // subtree and leave a stale reference in the old parent's child list.
      // Accept when the key is already a child of this same parent (no-op
      // reparent — handled by the purge-old-children step).
      if (_hasKey(child.key) && _parentKeyOfKey(child.key) != parentKey) {
        throw ArgumentError(
          "setChildren($parentKey): key ${child.key} already exists under "
          "parent ${_parentKeyOfKey(child.key)}. Use moveNode() or remove() first.",
        );
      }
    }

    // Purge old children and their descendants before overwriting.
    final oldChildren = _childListOf(parentKey);
    if (oldChildren != null && oldChildren.isNotEmpty) {
      final allOldKeys = <TKey>[];
      for (final oldChildKey in oldChildren) {
        allOldKeys.add(oldChildKey);
        _getDescendantsInto(oldChildKey, allOldKeys);
      }

      // Check visibility and contiguity BEFORE purging (purge clears the index)
      int minIdx = _order.length;
      int maxIdx = -1;
      int visibleCount = 0;
      for (final key in allOldKeys) {
        final idx = _order.indexOf(key);
        if (idx != VisibleOrderBuffer.kNotVisible) {
          visibleCount++;
          if (idx < minIdx) minIdx = idx;
          if (idx > maxIdx) maxIdx = idx;
        }
      }

      // Decrement the parent's visible-subtree-size cache by the
      // count of visible old descendants BEFORE _purgeNodeData
      // releases their nids. Mirrors the fix in _removeNodesImmediate
      // and _finalizeAnimation: the deferred order-buffer compaction
      // below cannot fire useful visibility-loss callbacks once the
      // released nids' parent chains are cleared.
      if (visibleCount > 0) {
        final parentNid = _nids[parentKey];
        if (parentNid != null) {
          _bumpVisibleSubtreeSizeFromSelf(parentNid, -visibleCount);
        }
      }

      final oldKeySet = allOldKeys.toSet();
      for (final key in allOldKeys) {
        _purgeNodeData(key);
      }

      if (visibleCount > 0) {
        _runWithSubtreeSizeUpdatesSuppressed(() {
          if (maxIdx - minIdx + 1 == visibleCount) {
            // Contiguous removal
            _order.removeRange(minIdx, maxIdx + 1);
            _updateIndicesAfterRemove(minIdx);
          } else {
            // Non-contiguous removal
            _order.removeWhereKeyIn(oldKeySet);
            _rebuildVisibleIndex();
          }
        });
        _structureGeneration++;
      }
    }

    final parentDepth = _depthOfKey(parentKey);
    final childIds = <TKey>[];
    final sorted = comparator != null
        ? (List.of(children)..sort(comparator))
        : children;

    for (final child in sorted) {
      _adoptKey(child.key);
      _dataByNid[_nids[child.key]!] = child;
      _setParentKey(child.key, parentKey);
      _setChildList(child.key, []);
      _setDepthKey(child.key, parentDepth + 1);
      _setExpandedKey(child.key, false);
      childIds.add(child.key);
    }

    _setChildList(parentKey, childIds);

    // If parent is expanded and visible, insert new children into the
    // visible order so they render immediately.
    if (_isExpandedKey(parentKey) && childIds.isNotEmpty) {
      final parentIdx = _order.indexOf(parentKey);
      if (parentIdx != VisibleOrderBuffer.kNotVisible) {
        final insertIdx = parentIdx + 1;
        _order.insertAllKeys(insertIdx, childIds);
        _updateIndicesFrom(insertIdx);
        _structureGeneration++;
      }
    }

    // Bulk child replacement: old children (and their subtrees) were purged,
    // new children registered. Any retained row under [parentKey] may have
    // its builder output differ — fall back to a full refresh.
    _notifyStructural();
  }

  /// Inserts a new node as a child of the given parent.
  ///
  /// If [animate] is true, the node will animate in.
  void insert({
    required TKey parentKey,
    required TreeNode<TKey, TData> node,
    int? index,
    bool animate = true,
    bool preservePendingSubtreeState = false,
  }) {
    if (animationDuration == Duration.zero) animate = false;
    assert(_hasKey(parentKey), "Parent node $parentKey not found");
    assert(
      !_pendingDeletion.contains(parentKey),
      "Cannot insert under $parentKey while it is animating out "
      "(pending deletion). The parent will be purged when its exit animation "
      "completes, leaving the new child orphaned.",
    );
    // If the node is pending deletion, cancel the deletion
    if (_pendingDeletion.contains(node.key)) {
      // If the pending-deletion node lives under a different parent (or is
      // a root), move it to [parentKey] before cancelling the deletion.
      // Without this relocation, cancelDeletion would resurrect the node
      // under its old parent, silently ignoring the parentKey/index args.
      final oldParent = _parentKeyOfKey(node.key);
      if (oldParent != parentKey) {
        if (oldParent != null) {
          _childListOf(oldParent)?.remove(node.key);
        } else {
          _roots.remove(node.key);
        }
        _setParentKey(node.key, parentKey);
        final siblings = _childListOrCreate(parentKey);
        final effectiveIndex =
            index ?? (comparator != null ? _sortedIndex(siblings, node) : null);
        if (effectiveIndex != null && effectiveIndex < siblings.length) {
          siblings.insert(effectiveIndex, node.key);
        } else {
          siblings.add(node.key);
        }
        final parentDepth = _depthOfKey(parentKey);
        _refreshSubtreeDepths(node.key, parentDepth + 1);
      } else if (index != null) {
        // Same parent — honor an explicitly requested index by relocating
        // within the sibling list.
        final siblings = _childListOrCreate(parentKey);
        final current = siblings.indexOf(node.key);
        if (current != -1) {
          siblings.removeAt(current);
          final clamped = index.clamp(0, siblings.length);
          siblings.insert(clamped, node.key);
        }
      }
      _cancelDeletion(
        node.key,
        animate: animate,
        preserveSubtreeState: preservePendingSubtreeState,
      );
      _adoptKey(node.key);
      _dataByNid[_nids[node.key]!] = node;
      if (preservePendingSubtreeState) {
        _rebuildVisibleOrder();
        _structureGeneration++;
        // See insertRoot's matching branch: cancelling a pending deletion
        // may restore a subtree and flip ancestor hasChildren state — fall
        // back to a full refresh.
        _notifyStructural();
        return;
      }
      // Reset expansion state so a subsequent expand() works cleanly.
      // Descendants that were mid-exit are left alone by _cancelDeletion
      // and continue animating out under the restored parent via
      // _rebuildVisibleOrder's "collapsed with active animations" branch.
      // Yanking them here would visually jump following rows upward by
      // the descendant's current extent in a single frame.
      _setExpandedKey(node.key, false);
      _rebuildVisibleOrder();
      _structureGeneration++;
      _notifyStructural();
      return;
    }
    // Node is already present (e.g. restored by an ancestor's
    // _cancelDeletion, or a live re-insert). Update the data and — if the
    // caller requested a different location — relocate it to honor the
    // insert(parentKey:, index:) contract instead of silently dropping it.
    if (_hasKey(node.key)) {
      _adoptKey(node.key);
      _dataByNid[_nids[node.key]!] = node;
      final currentParent = _parentKeyOfKey(node.key);
      if (currentParent != parentKey) {
        // Different parent — delegate to moveNode.
        moveNode(node.key, parentKey, index: index);
        return;
      }
      final siblings = _childListOrCreate(parentKey);
      final currentIndex = siblings.indexOf(node.key);
      final desiredIndex =
          index ?? (comparator != null ? _sortedIndex(siblings, node) : null);
      final wantsRelocate =
          desiredIndex != null &&
          desiredIndex != currentIndex &&
          !(currentIndex == siblings.length - 1 &&
              desiredIndex >= siblings.length);
      if (wantsRelocate) {
        siblings.removeAt(currentIndex);
        final clamped = desiredIndex.clamp(0, siblings.length);
        siblings.insert(clamped, node.key);
        _rebuildVisibleOrder();
        _structureGeneration++;
      }
      // Data payload for node.key was just overwritten — rebuild its row.
      _notifyStructural(affectedKeys: <TKey>{node.key});
      return;
    }
    final parentDepth = _depthOfKey(parentKey);
    // Add to data structures
    _adoptKey(node.key);
    _dataByNid[_nids[node.key]!] = node;
    _setParentKey(node.key, parentKey);
    _setChildList(node.key, []);
    _setDepthKey(node.key, parentDepth + 1);
    _setExpandedKey(node.key, false);
    // Add to parent's children
    final siblings = _childListOrCreate(parentKey);
    final parentHadChildren = siblings.isNotEmpty;
    final effectiveIndex =
        index ?? (comparator != null ? _sortedIndex(siblings, node) : null);
    if (effectiveIndex != null && effectiveIndex < siblings.length) {
      siblings.insert(effectiveIndex, node.key);
    } else {
      siblings.add(node.key);
    }
    // If parent is expanded, add to visible order
    if (_isExpandedKey(parentKey)) {
      final parentVisibleIndex = _order.indexOf(parentKey);
      if (parentVisibleIndex != VisibleOrderBuffer.kNotVisible) {
        // Fast path: the visible insertion index equals the parent's
        // visible index plus every prior sibling's visible-subtree
        // contribution. Cache lookups are O(1) per sibling, so the
        // whole computation is O(prior-sibling-count) — one array
        // read per sibling, no nested descendant walks.
        int insertIndex;
        if (effectiveIndex != null) {
          insertIndex = parentVisibleIndex + 1;
          final limit = effectiveIndex < siblings.length - 1
              ? effectiveIndex
              : siblings.length - 1;
          for (int i = 0; i < limit; i++) {
            final siblingNid = _nids[siblings[i]];
            if (siblingNid != null) {
              insertIndex += _visibleSubtreeSizeByNid[siblingNid];
            }
          }
        } else {
          // Append after last visible descendant of parent. Parent is
          // visible (checked above) so its cached subtree size counts
          // itself + all currently-visible descendants; subtracting
          // 1 for the parent itself and adding 1 for "position after"
          // yields parentVisibleIndex + subtreeSize directly.
          final parentNid = _nids[parentKey]!;
          insertIndex =
              parentVisibleIndex + _visibleSubtreeSizeByNid[parentNid];
        }
        _order.insertKey(insertIndex, node.key);
        _updateIndicesFrom(insertIndex);
        _structureGeneration++;
        if (animate) {
          _startStandaloneEnterAnimation(node.key);
        }
      }
    }
    // The new key enters via createChild. The only retained row whose
    // builder output can change is the parent — and only when its
    // hasChildren state just flipped from false → true (the chevron
    // appears for the first time).
    final affected = <TKey>{};
    if (!parentHadChildren) {
      affected.add(parentKey);
    }
    _notifyStructural(affectedKeys: affected);
  }

  /// Removes a node and all its descendants from the tree.
  ///
  /// If [animate] is true, the nodes will animate out.
  void remove({required TKey key, bool animate = true}) {
    if (animationDuration == Duration.zero) animate = false;
    if (!_hasKey(key)) {
      return;
    }
    final descendants = _getDescendants(key);
    final nodesToRemove = [key, ...descendants];
    // Capture the parent BEFORE mutation; _removeNodesImmediate purges the
    // node and releases its nid, after which _parentKeyOfKey returns null.
    final parentKey = _parentKeyOfKey(key);
    final affected = <TKey>{};
    if (animate && _order.contains(key)) {
      // Mark nodes as pending deletion so _finalizeAnimation knows to
      // fully remove them (vs just hiding due to parent collapse)
      _pendingDeletion.addAll(nodesToRemove);
      // Mark all visible nodes as exiting
      for (final nodeId in nodesToRemove) {
        if (_order.contains(nodeId)) {
          _startStandaloneExitAnimation(nodeId);
        }
      }
      // Animated path: parent's child list is not mutated until exit
      // animations complete; the hasChildren-flip refresh is fired from
      // the standalone-tick / group-dismissed sites at completion time.
    } else {
      _removeNodesImmediate(nodesToRemove);
      _structureGeneration++;
      // Immediate path: if [key] was the last child under its parent, the
      // parent's hasChildren just flipped true → false.
      if (parentKey != null) {
        final siblings = _childListOf(parentKey);
        if (siblings == null || siblings.isEmpty) {
          affected.add(parentKey);
        }
      }
    }
    _notifyStructural(affectedKeys: affected);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RETAINED-NODE UPDATE, REORDER, AND MOVE
  // ══════════════════════════════════════════════════════════════════════════

  /// Updates the data payload for an existing node without structural changes.
  ///
  /// Preserves the node's position, expansion state, and animation state.
  /// Notifies listeners so that mounted widgets rebuild with the new data.
  void updateNode(TreeNode<TKey, TData> node) {
    assert(_hasKey(node.key), 'Node ${node.key} not found');
    _adoptKey(node.key);
    _dataByNid[_nids[node.key]!] = node;
    // Data-only change: no structural mutation, no visible order shift,
    // no expansion/hasChildren change. Fire the targeted data channel
    // so the element rebuilds only this row instead of sweeping every
    // mounted child.
    _notifyNodeDataChanged(node.key);
  }

  /// Reorders the root nodes to match [orderedKeys].
  ///
  /// [orderedKeys] must contain exactly the current live (non-pending-deletion)
  /// root keys. Expansion state, animation state, and measured extents are
  /// preserved. Pending-deletion roots are appended after the live roots.
  void reorderRoots(List<TKey> orderedKeys) {
    final pendingRoots = <TKey>[];
    final liveRootSet = <TKey>{};
    for (final k in _roots) {
      if (_pendingDeletion.contains(k)) {
        pendingRoots.add(k);
      } else {
        liveRootSet.add(k);
      }
    }
    // Validate in all build modes: an `assert` here would be stripped in
    // release and silently corrupt `_roots` (duplicated entries, lost subtrees,
    // references to unknown keys).
    if (orderedKeys.length != liveRootSet.length ||
        orderedKeys.toSet().length != orderedKeys.length ||
        !liveRootSet.containsAll(orderedKeys)) {
      throw ArgumentError.value(
        orderedKeys,
        "orderedKeys",
        "must contain exactly the current live root keys with no duplicates",
      );
    }

    _roots
      ..clear()
      ..addAll(orderedKeys)
      ..addAll(pendingRoots);
    _rebuildVisibleOrder();
    _structureGeneration++;
    // Pure reorder: positions change but no row's builder output does
    // (nodeBuilder signature takes (context, key, depth) — no index). The
    // sliver's layout repositions elements in place.
    _notifyStructural(affectedKeys: const {});
  }

  /// Reorders the children of [parentKey] to match [orderedKeys].
  ///
  /// [orderedKeys] must contain exactly the current live (non-pending-deletion)
  /// children of [parentKey]. Expansion state, animation state, and measured
  /// extents are preserved.
  void reorderChildren(TKey parentKey, List<TKey> orderedKeys) {
    if (!_hasKey(parentKey)) {
      throw ArgumentError.value(parentKey, "parentKey", "not found");
    }
    final currentChildren = _childListOf(parentKey) ?? <TKey>[];

    final pendingChildren = <TKey>[];
    final liveChildSet = <TKey>{};
    for (final k in currentChildren) {
      if (_pendingDeletion.contains(k)) {
        pendingChildren.add(k);
      } else {
        liveChildSet.add(k);
      }
    }
    // Validate in all build modes — see reorderRoots for rationale.
    if (orderedKeys.length != liveChildSet.length ||
        orderedKeys.toSet().length != orderedKeys.length ||
        !liveChildSet.containsAll(orderedKeys)) {
      throw ArgumentError.value(
        orderedKeys,
        "orderedKeys",
        "must contain exactly the current live children of $parentKey with "
            "no duplicates",
      );
    }

    _setChildList(parentKey, [...orderedKeys, ...pendingChildren]);
    bool needsVisibleRebuild =
        _isExpandedKey(parentKey) && _ancestorsExpandedFast(parentKey);
    if (!needsVisibleRebuild) {
      // Even if the parent is not expanded, children may still be present
      // in _visibleOrder because they are mid-animation (collapse in
      // progress, pending-deletion exit). Those entries would otherwise
      // retain the old order until the animation completes.
      for (final child in _childListOf(parentKey)!) {
        if (_nodeToOperationGroup.containsKey(child) ||
            _bulkAnimationGroup?.members.contains(child) == true ||
            _standaloneAnimations.containsKey(child)) {
          needsVisibleRebuild = true;
          break;
        }
      }
    }
    if (needsVisibleRebuild) {
      _rebuildVisibleOrder();
      _structureGeneration++;
    }
    // See reorderRoots: pure reorder — no builder output changes.
    _notifyStructural(affectedKeys: const {});
  }

  /// Moves a node from its current parent to [newParentKey].
  ///
  /// If [newParentKey] is null, the node becomes a root. If [index] is
  /// provided, the node is inserted at that position among its new siblings;
  /// otherwise it is appended.
  ///
  /// The node's subtree (children, expansion state, and measured extents) is
  /// preserved. Any in-flight enter/exit animations on the moved subtree are
  /// cancelled so a mid-exit node isn't purged at its new location when the
  /// animation finalizes — callers that need animation on the new position
  /// should trigger it explicitly after the move.
  void moveNode(TKey key, TKey? newParentKey, {int? index}) {
    assert(_hasKey(key), 'Node $key not found');
    assert(
      newParentKey == null || _hasKey(newParentKey),
      'New parent $newParentKey not found',
    );
    // Self-reparent would build a cycle in _childListOf(key) and stack-overflow
    // _refreshSubtreeDepths. Guard at runtime so release builds don't crash.
    if (newParentKey != null && newParentKey == key) {
      throw StateError("Cannot move $key onto itself");
    }
    // Reparenting under a descendant would form a cycle; check at runtime
    // (release builds skip the assert below).
    if (newParentKey != null && _getDescendants(key).contains(newParentKey)) {
      throw StateError(
        "Cannot move $key under its own descendant $newParentKey",
      );
    }

    final oldParent = _parentKeyOfKey(key);
    // If already under the target parent and no explicit position was
    // requested, nothing to do. With an explicit [index], fall through so the
    // node is repositioned among its existing siblings.
    if (oldParent == newParentKey && index == null) return;

    // Snapshot state needed to compute precise affected-keys after the move.
    final oldDepth = _depthOfKey(key);
    final newParentWasEmpty = newParentKey != null
        ? (_childListOf(newParentKey)?.isEmpty ?? true)
        : false;

    // Cancel any animation/deletion state tied to the moved subtree's old
    // position. Without this, a node caught mid-exit-animation would still
    // be purged by _finalizeAnimation after the move, destroying the subtree
    // under its new parent.
    _cancelAnimationStateForSubtree(key);

    // Remove from old parent's child list (or roots).
    if (oldParent != null) {
      _childListOf(oldParent)?.remove(key);
    } else {
      _roots.remove(key);
    }

    // Insert into new parent's child list (or roots).
    _setParentKey(key, newParentKey);
    final node = _dataOf(key)!;
    if (newParentKey != null) {
      final siblings = _childListOrCreate(newParentKey);
      final effectiveIndex =
          index ?? (comparator != null ? _sortedIndex(siblings, node) : null);
      if (effectiveIndex != null && effectiveIndex < siblings.length) {
        siblings.insert(effectiveIndex, key);
      } else {
        siblings.add(key);
      }
    } else {
      final effectiveIndex =
          index ?? (comparator != null ? _sortedIndex(_roots, node) : null);
      if (effectiveIndex != null && effectiveIndex < _roots.length) {
        _roots.insert(effectiveIndex, key);
      } else {
        _roots.add(key);
      }
    }

    final newDepth = newParentKey != null ? (_depthOfKey(newParentKey)) + 1 : 0;
    _refreshSubtreeDepths(key, newDepth);

    _rebuildVisibleOrder();
    _structureGeneration++;

    final affected = <TKey>{};
    // If the moved subtree's depth changed, every row in it must rebuild
    // — nodeBuilder receives `depth` as an argument and indentation scales
    // with it. Use _flattenSubtree so we enumerate the currently-expanded
    // rows (the only ones that can be mounted).
    if (newDepth != oldDepth) {
      affected.addAll(_flattenSubtree(key, includeRoot: true));
    }
    // Old parent may have just lost its last child (hasChildren true → false).
    if (oldParent != null) {
      final siblings = _childListOf(oldParent);
      if (siblings == null || siblings.isEmpty) {
        affected.add(oldParent);
      }
    }
    // New parent may have just gained its first child (hasChildren false → true).
    if (newParentKey != null && newParentWasEmpty) {
      affected.add(newParentKey);
    }
    _notifyStructural(affectedKeys: affected);
  }

  /// Sets [_depths] for [key] and all its descendants. Iterative so deep
  /// trees do not stack-overflow. Depth for each descendant is computed
  /// on visit from the entry paired with it in the worklist, not derived
  /// from its parent's already-written depth, so visit order is irrelevant.
  void _refreshSubtreeDepths(TKey key, int depth) {
    final keys = <TKey>[key];
    final depths = <int>[depth];
    while (keys.isNotEmpty) {
      final k = keys.removeLast();
      final d = depths.removeLast();
      _setDepthKey(k, d);
      final children = _childListOf(k);
      if (children == null) {
        continue;
      }
      final childDepth = d + 1;
      for (final childKey in children) {
        keys.add(childKey);
        depths.add(childDepth);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EXPAND / COLLAPSE
  // ══════════════════════════════════════════════════════════════════════════

  /// Expands the given node, revealing its children.
  void expand({required TKey key, bool animate = true}) {
    if (animationDuration == Duration.zero) animate = false;
    if (!_hasKey(key)) {
      return;
    }
    if (_isExpandedKey(key)) {
      return;
    }
    final children = _childListOf(key);
    if (children == null || children.isEmpty) {
      return;
    }
    // Don't expand if this node is currently exiting
    if (isExiting(key)) {
      return;
    }
    // If ancestors are collapsed, just record the expansion state.
    // The node is not visible, so there is nothing to animate or
    // insert into the visible order. When ancestors are later expanded,
    // this node's children will appear immediately.
    if (!_ancestorsExpandedFast(key)) {
      _setExpandedKey(key, true);
      _notifyStructural(affectedKeys: <TKey>{key});
      return;
    }
    _setExpandedKey(key, true);
    // Find where to insert children in visible order
    final parentIndex = _order.indexOf(key);
    if (parentIndex == VisibleOrderBuffer.kNotVisible) {
      return;
    }

    if (!animate) {
      // No animation — insert and return
      final nodesToShow = _flattenSubtree(key, includeRoot: false);
      final nodesToInsert = <TKey>[];
      for (final nodeId in nodesToShow) {
        if (_pendingDeletion.contains(nodeId)) continue;
        if (!_order.contains(nodeId)) {
          nodesToInsert.add(nodeId);
        } else {
          _removeAnimation(nodeId);
        }
      }
      if (nodesToInsert.isNotEmpty) {
        final insertIndex = parentIndex + 1;
        _order.insertAllKeys(insertIndex, nodesToInsert);
        _updateIndicesFrom(insertIndex);
      }
      _structureGeneration++;
      _notifyStructural(affectedKeys: <TKey>{key});
      return;
    }

    // Animated expand
    final existingGroup = _operationGroups[key];
    if (existingGroup != null) {
      // Path 1: Reversing a collapse — group already exists
      if (existingGroup.pendingRemoval.isNotEmpty) {
        existingGroup.pendingRemoval.clear();
        _bumpAnimGen();
      }
      // Restore each member's targetExtent to its full (natural) extent.
      // A prior fresh collapse may have captured mid-flight extents below
      // full (e.g., nodes taken from a bulk or standalone animation), so
      // computeExtent at value=1 would stop at the captured value and
      // snap to full on group disposal. Updating here ensures the
      // reversal terminates at the correct natural size.
      for (final entry in existingGroup.members.entries) {
        entry.value.targetExtent = _fullExtents[entry.key] ?? _unknownExtent;
      }
      existingGroup.controller.forward();

      // Handle descendants NOT in this group (from nested expansions)
      final nodesToShow = _flattenSubtree(key, includeRoot: false);
      for (final nodeId in nodesToShow) {
        if (_pendingDeletion.contains(nodeId)) continue;
        if (existingGroup.members.containsKey(nodeId)) continue;

        if (_standaloneAnimations[nodeId] case final anim?
            when anim.type == AnimationType.exiting) {
          // Reverse the exit to an enter with speedMultiplier
          _startStandaloneEnterAnimation(nodeId);
        } else if (!_order.contains(nodeId)) {
          // New node not yet visible — insert at correct sibling position
          // and animate. _insertNodeIntoVisibleOrder appends at the end of
          // the grandparent's subtree, which drops the node past its
          // following siblings when they are already in the visible order.
          _insertNewNodeAmongSiblings(nodeId);
          _startStandaloneEnterAnimation(nodeId);
        }
      }
      _structureGeneration++;
      _notifyStructural(affectedKeys: <TKey>{key});
      return;
    }

    // Path 2: Fresh expand — create new operation group
    final nodesToShow = _flattenSubtree(key, includeRoot: false);
    final controller = AnimationController(
      vsync: _vsync,
      duration: animationDuration,
      value: 0.0,
    );
    final group = OperationGroup<TKey>(
      controller: controller,
      curve: animationCurve,
      operationKey: key,
    );
    _installOperationGroup(key, group);

    // Fast path check: count new vs existing nodes
    int newNodeCount = 0;
    int effectiveCount = 0;
    for (final nodeId in nodesToShow) {
      if (_pendingDeletion.contains(nodeId)) continue;
      effectiveCount++;
      if (!_order.contains(nodeId)) {
        newNodeCount++;
      }
    }

    if (newNodeCount == 0) {
      // All nodes already visible (reversing collapse animation)
      for (final nodeId in nodesToShow) {
        if (_pendingDeletion.contains(nodeId)) continue;
        final capturedExtent = _captureAndRemoveFromGroups(nodeId);
        final nge = NodeGroupExtent(
          startExtent: capturedExtent ?? 0.0,
          targetExtent: _fullExtents[nodeId] ?? _unknownExtent,
        );
        group.members[nodeId] = nge;
        _nodeToOperationGroup[nodeId] = key;
      }
    } else if (newNodeCount == effectiveCount) {
      // All nodes need insertion (normal expand)
      final nodesToInsert = <TKey>[];
      for (final nodeId in nodesToShow) {
        if (_pendingDeletion.contains(nodeId)) continue;
        final capturedExtent = _captureAndRemoveFromGroups(nodeId);
        final nge = NodeGroupExtent(
          startExtent: capturedExtent ?? 0.0,
          targetExtent: _fullExtents[nodeId] ?? _unknownExtent,
        );
        group.members[nodeId] = nge;
        _nodeToOperationGroup[nodeId] = key;
        nodesToInsert.add(nodeId);
      }
      final insertIndex = parentIndex + 1;
      _order.insertAllKeys(insertIndex, nodesToInsert);
      _updateIndicesFrom(insertIndex);
    } else {
      // Mixed path: some visible (exiting), some need insertion
      int currentInsertIndex = parentIndex + 1;
      int insertOffset = 0;
      int minInsertIndex = _order.length;
      for (final nodeId in nodesToShow) {
        if (_pendingDeletion.contains(nodeId)) continue;
        final existingIndex = _order.indexOf(nodeId);
        final capturedExtent = _captureAndRemoveFromGroups(nodeId);
        final nge = NodeGroupExtent(
          startExtent: capturedExtent ?? 0.0,
          targetExtent: _fullExtents[nodeId] ?? _unknownExtent,
        );
        group.members[nodeId] = nge;
        _nodeToOperationGroup[nodeId] = key;

        if (existingIndex != VisibleOrderBuffer.kNotVisible) {
          // Node already visible (was exiting)
          currentInsertIndex = existingIndex + insertOffset + 1;
        } else {
          // Insert at current position
          if (currentInsertIndex < minInsertIndex) {
            minInsertIndex = currentInsertIndex;
          }
          _order.insertKey(currentInsertIndex, nodeId);
          insertOffset++;
          currentInsertIndex++;
        }
      }
      if (insertOffset > 0) {
        for (int i = minInsertIndex; i < _order.length; i++) {
          _order.setIndexByNid(_order.orderNids[i], i);
        }
        _assertIndexConsistency();
      }
    }

    _structureGeneration++;
    controller.forward();
    _notifyStructural(affectedKeys: <TKey>{key});
  }

  /// Collapses the given node, hiding its children.
  ///
  /// Note: This preserves the expansion state of descendant nodes. When the
  /// node is re-expanded, any previously expanded children will also show
  /// their children automatically.
  void collapse({required TKey key, bool animate = true}) {
    if (animationDuration == Duration.zero) animate = false;
    if (!_hasKey(key) || !_isExpandedKey(key)) {
      return;
    }
    _setExpandedKey(key, false);
    // Find all visible descendants (includes nodes currently entering)
    final descendants = _getVisibleDescendants(key);
    if (descendants.isEmpty) {
      _notifyStructural(affectedKeys: <TKey>{key});
      return;
    }

    if (!animate) {
      // Remove immediately from visible order
      final toRemove = <TKey>{};
      for (final nodeId in descendants) {
        if (!_pendingDeletion.contains(nodeId)) {
          toRemove.add(nodeId);
          _removeAnimation(nodeId);
        }
      }
      if (toRemove.isNotEmpty) {
        _removeFromVisibleOrder(toRemove);
        _structureGeneration++;
      }
      _notifyStructural(affectedKeys: <TKey>{key});
      return;
    }

    // Animated collapse
    final existingGroup = _operationGroups[key];
    if (existingGroup != null) {
      // Path 1: Reversing an expand — group already exists
      // Normalize each member's startExtent to 0 so the reversal
      // terminates at fully-collapsed (value=0 → extent=0). A prior
      // fresh expand may have captured a non-zero start from a node
      // that was mid-animation, which would leave a residual visible
      // extent at dismissal and cause a visible snap when the member
      // is removed from the visible order.
      for (final entry in existingGroup.members.entries) {
        entry.value.startExtent = 0.0;
        existingGroup.pendingRemoval.add(entry.key);
      }
      _bumpAnimGen();
      existingGroup.controller.reverse();

      // Handle descendants NOT in this group (from nested expansions)
      for (final nodeId in descendants) {
        if (_pendingDeletion.contains(nodeId)) continue;
        if (existingGroup.members.containsKey(nodeId)) continue;
        // Create standalone exit animation with speedMultiplier
        _startStandaloneExitAnimation(nodeId, triggeringAncestorId: key);
      }
      _structureGeneration++;
      _notifyStructural(affectedKeys: <TKey>{key});
      return;
    }

    // Path 2: Fresh collapse — create new operation group
    final controller = AnimationController(
      vsync: _vsync,
      duration: animationDuration,
      value: 1.0,
    );
    final group = OperationGroup<TKey>(
      controller: controller,
      curve: animationCurve,
      operationKey: key,
    );
    _installOperationGroup(key, group);

    for (final nodeId in descendants) {
      if (_pendingDeletion.contains(nodeId)) continue;
      final capturedExtent = _captureAndRemoveFromGroups(nodeId);
      final nge = NodeGroupExtent(
        startExtent: 0.0,
        targetExtent: capturedExtent ?? (_fullExtents[nodeId] ?? defaultExtent),
      );
      group.members[nodeId] = nge;
      group.pendingRemoval.add(nodeId);
      _nodeToOperationGroup[nodeId] = key;
    }

    _structureGeneration++;
    controller.reverse();
    _notifyStructural(affectedKeys: <TKey>{key});
  }

  /// Toggles the expansion state of the given node.
  void toggle({required TKey key, bool animate = true}) {
    if (_isExpandedKey(key)) {
      collapse(key: key, animate: animate);
    } else {
      expand(key: key, animate: animate);
    }
  }

  /// Expands all nodes in the tree.
  ///
  /// Uses batch operations for better performance with large trees.
  void expandAll({bool animate = true, int? maxDepth}) {
    if (animationDuration == Duration.zero) animate = false;
    // Collect all nodes to expand, nodes to show, and nodes currently exiting
    final nodesToExpand = <TKey>[];
    final nodesToShow = <TKey>[];
    final nodesToReverseExit = <TKey>[];

    // Iterative DFS. Depth is recomputed per-visit via [_depthOfKey]
    // (matching the original recursive implementation) so we do not
    // need to carry depth along in a parallel stack.
    final stack = <TKey>[];
    for (final rootId in _roots) {
      stack.add(rootId);
    }
    while (stack.isNotEmpty) {
      final key = stack.removeLast();
      if (_pendingDeletion.contains(key)) {
        continue;
      }
      final children = _childListOf(key);
      if (children == null || children.isEmpty) {
        continue;
      }

      final depth = _depthOfKey(key);
      final withinDepthLimit = maxDepth == null || depth < maxDepth;

      if (withinDepthLimit && !_isExpandedKey(key)) {
        nodesToExpand.add(key);
        for (final childId in children) {
          if (!_order.contains(childId)) {
            nodesToShow.add(childId);
          }
        }
      }

      // Still check children for exiting animations regardless of depth.
      for (final childId in children) {
        // Check standalone exiting
        final animation = _standaloneAnimations[childId];
        if (animation != null && animation.type == AnimationType.exiting) {
          if (!_pendingDeletion.contains(childId)) {
            nodesToReverseExit.add(childId);
          }
        }
        // Check operation group exiting (pendingRemoval)
        final opGroupKey = _nodeToOperationGroup[childId];
        if (opGroupKey != null) {
          final opGroup = _operationGroups[opGroupKey];
          if (opGroup != null && opGroup.pendingRemoval.contains(childId)) {
            if (!_pendingDeletion.contains(childId)) {
              nodesToReverseExit.add(childId);
            }
          }
        }
      }

      // Only descend into children if within depth limit.
      if (withinDepthLimit) {
        for (final childId in children) {
          stack.add(childId);
        }
      }
    }
    if (nodesToExpand.isEmpty && nodesToReverseExit.isEmpty) {
      return;
    }
    // Batch update expansion states. Skip per-call ancestors-expanded
    // propagation — we rebuild it wholesale below in O(N).
    for (final key in nodesToExpand) {
      _setExpandedKey(key, true, propagate: false);
    }
    _rebuildAllAncestorsExpanded();
    // Rebuild visible order from scratch (more efficient for bulk operations)
    _rebuildVisibleOrder();
    _structureGeneration++;
    // Start animations for newly visible nodes and reverse exiting animations
    if (animate) {
      // Reverse collapsing operation groups
      bool opGroupReversed = false;
      for (final entry in _operationGroups.entries) {
        final group = entry.value;
        if (group.pendingRemoval.isNotEmpty) {
          group.pendingRemoval.clear();
          opGroupReversed = true;
          // Restore each member's targetExtent to full so the reversal
          // terminates at the correct natural size instead of at a
          // captured mid-flight value.
          for (final member in group.members.entries) {
            member.value.targetExtent =
                _fullExtents[member.key] ?? _unknownExtent;
          }
          group.controller.forward();
        }
      }
      if (opGroupReversed) _bumpAnimGen();

      // Check if there's a collapsing bulk animation we can reverse
      if (_bulkAnimationGroup != null &&
          _bulkAnimationGroup!.pendingRemoval.isNotEmpty) {
        // Reverse the animation - nodes being removed will now expand
        // Clear pending removal since we're expanding now
        _bulkAnimationGroup!.pendingRemoval.clear();

        // Reverse standalone exit animations smoothly
        for (final key in nodesToReverseExit) {
          if (!_nodeToOperationGroup.containsKey(key)) {
            _startStandaloneEnterAnimation(key);
          }
        }

        // Add any new nodes to the group (skip if already in an operation group)
        for (final key in nodesToShow) {
          if (_order.contains(key) && !_nodeToOperationGroup.containsKey(key)) {
            _bulkAnimationGroup!.members.add(key);
          }
        }

        // Reverse the controller direction
        _bulkAnimationGroup!.controller.forward();
        _bumpBulkGen();
      } else {
        // Dispose old group and create fresh to avoid status listener race
        _disposeBulkAnimationGroup();
        _bulkAnimationGroup = _createBulkAnimationGroup();

        // Reverse standalone exit animations smoothly
        for (final key in nodesToReverseExit) {
          if (!_nodeToOperationGroup.containsKey(key)) {
            _startStandaloneEnterAnimation(key);
          }
        }

        // Add new nodes to the bulk group (skip if already in an operation group)
        for (final key in nodesToShow) {
          if (_order.contains(key) && !_nodeToOperationGroup.containsKey(key)) {
            _bulkAnimationGroup!.members.add(key);
          }
        }

        // Start expanding (value 0 -> 1)
        _bulkAnimationGroup!.controller.forward();
        _bumpBulkGen();
      }
    } else {
      // Remove animations if not animating
      for (final key in nodesToReverseExit) {
        _removeAnimation(key);
      }
    }
    // Bulk expansion touches many ancestors' expansion state + every
    // previously-collapsed node now flips its chevron. Enumerating the
    // affected set precisely is error-prone; fall back to a full refresh.
    _notifyStructural();
  }

  /// Collapses all nodes in the tree.
  ///
  /// Uses batch operations for better performance with large trees.
  void collapseAll({bool animate = true, int? maxDepth}) {
    if (animationDuration == Duration.zero) animate = false;
    // Collect all expanded nodes and their visible descendants
    final nodesToCollapse = <TKey>[];
    final nodesToHide = <TKey>[];
    for (final rootId in _roots) {
      if (_isExpandedKey(rootId)) {
        nodesToCollapse.add(rootId);
        nodesToHide.addAll(_getVisibleDescendants(rootId));
      }
    }
    // Also check for nodes that are entering (from an interrupted expandAll)
    final nodesToHideSet = nodesToHide.toSet();

    // Check standalone entering animations
    for (final entry in _standaloneAnimations.entries) {
      if (entry.value.type == AnimationType.entering) {
        if (!nodesToHideSet.contains(entry.key)) {
          if (_parentKeyOfKey(entry.key) != null) {
            nodesToHide.add(entry.key);
            nodesToHideSet.add(entry.key);
          }
        }
      }
    }

    // Check operation group members (expanding)
    for (final group in _operationGroups.values) {
      if (group.pendingRemoval.isEmpty) {
        // Group is expanding
        for (final key in group.members.keys) {
          if (!nodesToHideSet.contains(key)) {
            if (_parentKeyOfKey(key) != null) {
              nodesToHide.add(key);
              nodesToHideSet.add(key);
            }
          }
        }
      }
    }

    // Check bulk group members (expanding nodes)
    if (_bulkAnimationGroup != null) {
      for (final key in _bulkAnimationGroup!.members) {
        if (!nodesToHideSet.contains(key)) {
          if (_parentKeyOfKey(key) != null) {
            nodesToHide.add(key);
            nodesToHideSet.add(key);
          }
        }
      }
    }

    if (nodesToHide.isEmpty) {
      if (nodesToCollapse.isNotEmpty) {
        _collapseAllInRegistry(maxDepth);
        // Bulk expansion-state clear — see main collapseAll branch below.
        _notifyStructural();
      }
      return;
    }
    // Clear expansion state for ALL nodes within depth limit,
    // not just visible ones.
    _collapseAllInRegistry(maxDepth);
    _structureGeneration++;
    if (animate) {
      // Reverse expanding operation groups
      bool opGroupReversed = false;
      for (final entry in _operationGroups.entries) {
        final group = entry.value;
        if (group.pendingRemoval.isEmpty) {
          // Group is expanding — reverse it
          for (final nodeId in group.members.keys) {
            if (!_pendingDeletion.contains(nodeId)) {
              group.pendingRemoval.add(nodeId);
              opGroupReversed = true;
            }
          }
          // Normalize startExtent to 0 so the reversal terminates at
          // zero instead of at a captured mid-flight start value.
          for (final member in group.members.entries) {
            member.value.startExtent = 0.0;
          }
          group.controller.reverse();
        }
      }
      if (opGroupReversed) _bumpAnimGen();

      // Check if there's an expanding bulk animation we can reverse
      if (_bulkAnimationGroup != null &&
          _bulkAnimationGroup!.members.isNotEmpty &&
          _bulkAnimationGroup!.pendingRemoval.isEmpty) {
        // Mark all members for removal when animation completes at 0
        for (final key in _bulkAnimationGroup!.members) {
          if (!_pendingDeletion.contains(key)) {
            _bulkAnimationGroup!.pendingRemoval.add(key);
          }
        }

        // Handle additional nodes not in any group
        for (final key in nodesToHide) {
          if (_pendingDeletion.contains(key)) continue;
          if (!_bulkAnimationGroup!.members.contains(key) &&
              !_nodeToOperationGroup.containsKey(key)) {
            _startStandaloneExitAnimation(key);
          }
        }

        // Reverse the controller direction
        _bulkAnimationGroup!.controller.reverse();
        _bumpBulkGen();
      } else {
        // Dispose old group and create fresh with value=1.0
        _disposeBulkAnimationGroup();
        _bulkAnimationGroup = _createBulkAnimationGroup(initialValue: 1.0);

        // Add nodes to the bulk group, keeping individually-animating
        // nodes on their own timeline for smooth transitions.
        for (final key in nodesToHide) {
          if (_pendingDeletion.contains(key)) continue;
          if (_nodeToOperationGroup.containsKey(key)) continue;
          if (_standaloneAnimations.containsKey(key)) {
            // Reverse standalone animation smoothly
            _startStandaloneExitAnimation(key);
          } else {
            _removeAnimation(key);
            _bulkAnimationGroup!.members.add(key);
            _bulkAnimationGroup!.pendingRemoval.add(key);
          }
        }

        // Start collapsing (value 1 -> 0)
        if (_bulkAnimationGroup!.members.isNotEmpty) {
          _bulkAnimationGroup!.controller.reverse();
        }
        _bumpBulkGen();
      }
    } else {
      // Remove immediately
      final toRemove = <TKey>{};
      for (final key in nodesToHide) {
        if (!_pendingDeletion.contains(key)) {
          toRemove.add(key);
          _removeAnimation(key);
        }
      }
      if (toRemove.isNotEmpty) {
        _removeFromVisibleOrder(toRemove);
      }
    }
    // Bulk expansion-state clear: every node whose isExpanded state flipped
    // may render differently (chevron rotation, etc.). The set can span
    // arbitrary subtrees; fall back to a full refresh.
    _notifyStructural();
  }

  /// Rebuilds the entire visible order from the tree structure.
  ///
  /// More efficient than incremental updates when making bulk changes.
  /// Iterative DFS so deep trees do not stack-overflow. Children are
  /// pushed in reverse order so popping yields the original
  /// left-to-right pre-order visit sequence the recursive version
  /// produced (and which the visible-order buffer expects).
  ///
  /// Suppresses per-nid visibility callbacks during the rebuild and
  /// recomputes [_visibleSubtreeSizeByNid] in one O(N) post-order pass
  /// afterwards. Firing the incremental callback N times would be
  /// O(N·depth), which degenerates to O(N²) on deep trees.
  void _rebuildVisibleOrder() {
    _runWithSubtreeSizeUpdatesSuppressed(_rebuildVisibleOrderImpl);
  }

  void _rebuildVisibleOrderImpl() {
    _order.clear();

    final stack = <TKey>[];
    for (int i = _roots.length - 1; i >= 0; i--) {
      stack.add(_roots[i]);
    }

    while (stack.isNotEmpty) {
      final key = stack.removeLast();
      _order.addKey(key);
      final children = _childListOf(key);
      if (children == null) {
        continue;
      }

      if (_pendingDeletion.contains(key)) {
        // Don't recurse based on expansion state (prevents zombie children),
        // but DO include children that are also pending deletion and still
        // have running exit animations — they need to stay in _visibleOrder
        // to animate out smoothly.
        for (int i = children.length - 1; i >= 0; i--) {
          final childId = children[i];
          if (_pendingDeletion.contains(childId) &&
              _standaloneAnimations.containsKey(childId)) {
            stack.add(childId);
          }
        }
      } else if (_isExpandedKey(key)) {
        for (int i = children.length - 1; i >= 0; i--) {
          stack.add(children[i]);
        }
      } else {
        // Parent is collapsed, but children that are still in an active
        // animation (e.g. collapsing via an OperationGroup) must remain
        // in the visible order so their exit animation completes smoothly
        // instead of snapping away.
        for (int i = children.length - 1; i >= 0; i--) {
          final childId = children[i];
          if (_nodeToOperationGroup.containsKey(childId) ||
              _bulkAnimationGroup?.members.contains(childId) == true ||
              _standaloneAnimations.containsKey(childId)) {
            stack.add(childId);
          }
        }
      }
    }

    _rebuildVisibleIndex();
    _rebuildVisibleSubtreeSizes();
    // No post-rebuild consistency check: _rebuildVisibleSubtreeSizes uses
    // the same recursive sum formula as _assertVisibleSubtreeSizeConsistency,
    // so the check is tautological here. The fuzz test covers the
    // incremental path where the cross-check is meaningful.
  }

  @override
  void dispose() {
    _clear();
    _animationListeners.clear();
    _nodeDataListeners.clear();
    _structuralListeners.clear();
    super.dispose();
  }
}
