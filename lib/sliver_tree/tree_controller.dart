/// Controller that manages tree state, visibility, and animations.
library;

import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' show lerpDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'types.dart';

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
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.indentWidth = 0.0,
    this.comparator,
  }) : _vsync = vsync;

  final TickerProvider _vsync;

  /// Duration for expand/collapse animations.
  final Duration animationDuration;

  /// Curve for expand/collapse animations.
  final Curve animationCurve;

  /// Horizontal indent per depth level in logical pixels.
  final double indentWidth;

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
  /// for freed nids are null. Look up by key via [_keyToNid].
  final List<TreeNode<TKey, TData>?> _dataByNid =
      <TreeNode<TKey, TData>?>[];

  /// Parent nid for each node, indexed by nid. [_kNoParent] for roots and
  /// freed slots. Dense, capacity ≥ [_nidToKey].length; grown by
  /// [_ensureDenseCapacity].
  Int32List _parentByNid = Int32List(0);

  /// Sentinel value in nid-indexed parent arrays meaning "no parent" (root
  /// node) or "slot is free". Same sentinel is safe for both because a
  /// freed nid is never queried through [_keyToNid].
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

  // ══════════════════════════════════════════════════════════════════════════
  // INTERNAL NID REGISTRY
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Every live key is assigned a stable internal integer "nid". Planned later
  // phases replace the TKey-keyed maps above with dense arrays indexed by nid
  // (ints hash and compare faster than arbitrary TKey, enabling Float64List /
  // Int32List storage for hot-path state). Phase 1 only establishes the
  // mapping — no existing map logic changes.

  /// Forward lookup: user key → internal nid.
  final Map<TKey, int> _keyToNid = {};

  /// Reverse lookup: nid → user key. Entries for freed nids are null.
  final List<TKey?> _nidToKey = <TKey?>[];

  /// Pool of released nids available for reuse. Populated by [_releaseNid].
  final List<int> _freeNids = <int>[];

  /// Next fresh nid to hand out when [_freeNids] is empty.
  int _nextNid = 0;

  /// Returns the nid for [key], allocating one if the key isn't registered.
  /// Idempotent for already-registered keys. Grows every dense per-nid
  /// array in lockstep so callers can safely index them at the returned nid.
  int _adoptKey(TKey key) {
    final existing = _keyToNid[key];
    if (existing != null) return existing;
    final int nid;
    if (_freeNids.isNotEmpty) {
      nid = _freeNids.removeLast();
      _nidToKey[nid] = key;
      _dataByNid[nid] = null;
      _parentByNid[nid] = _kNoParent;
      _childrenByNid[nid] = null;
      _depthByNid[nid] = 0;
      _expandedByNid[nid] = 0;
      _ancestorsExpandedByNid[nid] = 1;
      _indexByNid[nid] = _kNotVisible;
    } else {
      nid = _nextNid++;
      _nidToKey.add(key);
      _dataByNid.add(null);
      _childrenByNid.add(null);
      _ensureDenseCapacity(_nidToKey.length);
      _parentByNid[nid] = _kNoParent;
      _depthByNid[nid] = 0;
      _expandedByNid[nid] = 0;
      _ancestorsExpandedByNid[nid] = 1;
      _indexByNid[nid] = _kNotVisible;
    }
    _keyToNid[key] = nid;
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
    final newIndex = Int32List(cap);
    newIndex.fillRange(_indexByNid.length, cap, _kNotVisible);
    newIndex.setRange(0, _indexByNid.length, _indexByNid);
    _indexByNid = newIndex;
  }

  /// Returns the parent nid for [key], or [_kNoParent] if [key] is a root
  /// or unregistered. Hot path — no allocation, no exception.
  int _parentNidOfKey(TKey key) {
    final nid = _keyToNid[key];
    return nid == null ? _kNoParent : _parentByNid[nid];
  }

  /// Returns the parent key for [key], or null if [key] is a root or
  /// unregistered. Equivalent to the old `_parentKeyOfKey(key)`.
  TKey? _parentKeyOfKey(TKey key) {
    final pNid = _parentNidOfKey(key);
    return pNid == _kNoParent ? null : _nidToKey[pNid];
  }

  /// Sets the parent of [key] to [parent] (or null for root). [key] must
  /// already be registered; [parent] must also be registered (unless null).
  /// Also refreshes the cached [_ancestorsExpandedByNid] bit for [key] and
  /// propagates the change through [key]'s subtree so the cache stays
  /// consistent with the new ancestor chain.
  void _setParentKey(TKey key, TKey? parent) {
    final nid = _keyToNid[key]!;
    _parentByNid[nid] = parent == null ? _kNoParent : _keyToNid[parent]!;
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
    final nid = _keyToNid.remove(key);
    if (nid == null) return;
    _nidToKey[nid] = null;
    _dataByNid[nid] = null;
    _parentByNid[nid] = _kNoParent;
    _childrenByNid[nid] = null;
    _depthByNid[nid] = 0;
    _expandedByNid[nid] = 0;
    _ancestorsExpandedByNid[nid] = 0;
    _indexByNid[nid] = _kNotVisible;
    _freeNids.add(nid);
  }

  /// Nullable lookup of the [TreeNode] record for [key]. Equivalent to the
  /// old `_nodeData[key]` — returns null if [key] is not registered.
  TreeNode<TKey, TData>? _dataOf(TKey key) {
    final nid = _keyToNid[key];
    return nid == null ? null : _dataByNid[nid];
  }

  /// Whether [key] currently has a node record. Equivalent to the old
  /// `_nodeData.containsKey(key)`.
  bool _hasKey(TKey key) => _keyToNid.containsKey(key);

  /// Returns the child key list for [key], or null if unregistered or no
  /// list has been allocated yet. Equivalent to the old `_childListOf(key)`.
  List<TKey>? _childListOf(TKey key) {
    final nid = _keyToNid[key];
    return nid == null ? null : _childrenByNid[nid];
  }

  /// Returns the child key list for [key], allocating an empty list if
  /// none exists. [key] must already be registered.
  /// Equivalent to the old `_childListOrCreate(key)`.
  List<TKey> _childListOrCreate(TKey key) {
    final nid = _keyToNid[key]!;
    return _childrenByNid[nid] ??= <TKey>[];
  }

  /// Replaces the child key list for [key]. [key] must be registered.
  /// Equivalent to the old `_children[key] = list`.
  void _setChildList(TKey key, List<TKey> list) {
    _childrenByNid[_keyToNid[key]!] = list;
  }

  /// Depth for [key], or 0 if unregistered.
  /// Equivalent to the old `_depthOfKey(key)`.
  int _depthOfKey(TKey key) {
    final nid = _keyToNid[key];
    return nid == null ? 0 : _depthByNid[nid];
  }

  /// Sets the depth for [key]. [key] must be registered.
  void _setDepthKey(TKey key, int depth) {
    _depthByNid[_keyToNid[key]!] = depth;
  }

  /// Whether [key] is currently expanded. Returns false if unregistered.
  /// Equivalent to the old `_isExpandedKey(key)` / `_isExpandedKey(key)`.
  bool _isExpandedKey(TKey key) {
    final nid = _keyToNid[key];
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
    final nid = _keyToNid[key]!;
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
  void _propagateAncestorsExpandedToDescendants(TKey key, int childAe) {
    final children = _childListOf(key);
    if (children == null || children.isEmpty) return;
    for (final child in children) {
      final childNid = _keyToNid[child];
      if (childNid == null) continue;
      if (_ancestorsExpandedByNid[childNid] == childAe) continue;
      _ancestorsExpandedByNid[childNid] = childAe;
      final grandAe =
          (childAe != 0 && _expandedByNid[childNid] != 0) ? 1 : 0;
      _propagateAncestorsExpandedToDescendants(child, grandAe);
    }
  }

  /// Rebuilds [_ancestorsExpandedByNid] wholesale in a single pass from the
  /// roots. Used by bulk operations (collapseAll / expandAll /
  /// [_collapseAllInRegistry]) that bypass per-call propagation.
  void _rebuildAllAncestorsExpanded() {
    _ancestorsExpandedByNid.fillRange(
      0,
      _ancestorsExpandedByNid.length,
      0,
    );
    for (final rootKey in _roots) {
      final rootNid = _keyToNid[rootKey];
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
    final nid = _keyToNid[key];
    if (nid == null) return true;
    return _ancestorsExpandedByNid[nid] != 0;
  }

  /// Visible-order index for [key], or [_kNotVisible] (-1) if [key] isn't
  /// currently visible or isn't registered. Equivalent to the old
  /// `_visibleIndex[key] ?? -1`.
  int _visibleIndexOf(TKey key) {
    final nid = _keyToNid[key];
    return nid == null ? _kNotVisible : _indexByNid[nid];
  }

  /// Writes [index] into the visible-index slot for [nid]. [nid] must be live.
  void _setVisibleIndexByNid(int nid, int index) {
    _indexByNid[nid] = index;
  }

  /// Marks [key] as not present in [_visibleOrder]. Safe to call on an
  /// unregistered key (no-op). Equivalent to the old
  /// `_clearVisibleIndex(key)`.
  void _clearVisibleIndex(TKey key) {
    final nid = _keyToNid[key];
    if (nid == null) return;
    _indexByNid[nid] = _kNotVisible;
  }

  /// Whether [key] is present in [_visibleOrder]. Equivalent to the old
  /// `_isVisible(key)`.
  bool _isVisible(TKey key) => _visibleIndexOf(key) != _kNotVisible;

  /// Resets every slot of [_indexByNid] to [_kNotVisible]. Used by
  /// [_clear] and [_rebuildVisibleIndex].
  void _resetVisibleIndexAll() {
    _indexByNid.fillRange(0, _indexByNid.length, _kNotVisible);
  }

  /// Grows [_visibleOrderNids] to at least [needed] slots (doubling).
  /// Amortized O(1) per [_visibleInsertNid]/[_visibleAddKey] call.
  void _ensureVisibleCapacity(int needed) {
    if (needed <= _visibleOrderNids.length) return;
    int cap = _visibleOrderNids.isEmpty ? 16 : _visibleOrderNids.length;
    while (cap < needed) {
      cap *= 2;
    }
    final grown = Int32List(cap);
    grown.setRange(0, _visibleLen, _visibleOrderNids);
    _visibleOrderNids = grown;
  }

  /// Returns the key stored at visible index [i]. [i] must satisfy
  /// `0 <= i < _visibleLen`.
  TKey _visibleKeyAt(int i) => _nidToKey[_visibleOrderNids[i]] as TKey;

  /// Inserts [key]'s nid at visible index [index]. [key] must be registered.
  void _visibleInsertKey(int index, TKey key) {
    _visibleInsertNid(index, _keyToNid[key]!);
  }

  /// Inserts [nid] at visible index [index]. Shifts all entries at
  /// `[index, _visibleLen)` right by one. [nid] must be live.
  void _visibleInsertNid(int index, int nid) {
    _ensureVisibleCapacity(_visibleLen + 1);
    for (int i = _visibleLen; i > index; i--) {
      _visibleOrderNids[i] = _visibleOrderNids[i - 1];
    }
    _visibleOrderNids[index] = nid;
    _visibleLen++;
    _invalidateFullOffsetPrefix();
  }

  /// Appends [key]'s nid to the end of the visible order. [key] must be
  /// registered.
  void _visibleAddKey(TKey key) {
    _ensureVisibleCapacity(_visibleLen + 1);
    _visibleOrderNids[_visibleLen++] = _keyToNid[key]!;
    _invalidateFullOffsetPrefix();
  }

  /// Inserts the nids of [keys] at visible index [index], preserving
  /// their order.
  void _visibleInsertAllKeys(int index, List<TKey> keys) {
    final n = keys.length;
    if (n == 0) return;
    _ensureVisibleCapacity(_visibleLen + n);
    for (int i = _visibleLen - 1; i >= index; i--) {
      _visibleOrderNids[i + n] = _visibleOrderNids[i];
    }
    for (int i = 0; i < n; i++) {
      _visibleOrderNids[index + i] = _keyToNid[keys[i]]!;
    }
    _visibleLen += n;
    _invalidateFullOffsetPrefix();
  }

  /// Removes the entry at visible index [index], shifting the suffix left.
  void _visibleRemoveAt(int index) {
    for (int i = index; i < _visibleLen - 1; i++) {
      _visibleOrderNids[i] = _visibleOrderNids[i + 1];
    }
    _visibleLen--;
    _invalidateFullOffsetPrefix();
  }

  /// Removes entries in `[start, end)` (half-open) from the visible order.
  void _visibleRemoveRange(int start, int end) {
    final n = end - start;
    if (n <= 0) return;
    for (int i = start; i < _visibleLen - n; i++) {
      _visibleOrderNids[i] = _visibleOrderNids[i + n];
    }
    _visibleLen -= n;
    _invalidateFullOffsetPrefix();
  }

  /// Compacts the visible order by dropping every entry whose key appears
  /// in [keys]. Preserves relative order of retained entries. Also drops
  /// entries whose nid has been released (e.g. callers that purge node data
  /// before rewriting the visible order) — those are always stale.
  void _visibleRemoveWhereKeyIn(Set<TKey> keys) {
    int writeIdx = 0;
    for (int readIdx = 0; readIdx < _visibleLen; readIdx++) {
      final nid = _visibleOrderNids[readIdx];
      final key = _nidToKey[nid];
      if (key == null) continue;
      if (keys.contains(key)) continue;
      _visibleOrderNids[writeIdx++] = nid;
    }
    if (writeIdx != _visibleLen) {
      _invalidateFullOffsetPrefix();
    }
    _visibleLen = writeIdx;
  }

  /// Resets the visible order to empty. Does not clear [_indexByNid];
  /// callers that want a fully invisible state must also invoke
  /// [_resetVisibleIndexAll] or zero individual slots.
  void _visibleClear() {
    _visibleLen = 0;
    _invalidateFullOffsetPrefix();
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
      final n = _nidToKey.length;
      for (int nid = 0; nid < n; nid++) {
        if (_nidToKey[nid] == null) continue;
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

  /// Flattened visible order, stored as nids for cache-friendly iteration.
  /// Includes nodes that are animating out (exiting). Capacity grows by
  /// doubling; live range is `0.._visibleLen`. See [_ensureVisibleCapacity],
  /// [_visibleInsertNid], [_visibleInsertAllKeys], [_visibleRemoveAt],
  /// [_visibleRemoveRange], [_visibleRemoveWhereKeyIn].
  Int32List _visibleOrderNids = Int32List(0);

  /// Number of live entries in [_visibleOrderNids]. Always
  /// `<= _visibleOrderNids.length`. The public [visibleNodes] view and every
  /// internal loop reads this instead of the underlying array's length.
  int _visibleLen = 0;

  /// Fast lookup: nid → index in [_visibleOrder], or [_kNotVisible] if the
  /// node is not currently in the visible list. Dense, indexed by nid; grown
  /// in lockstep with every other per-nid dense array by [_ensureDenseCapacity].
  Int32List _indexByNid = Int32List(0);

  /// Sentinel value in [_indexByNid] meaning "not in [_visibleOrder]". Freed
  /// nids also carry this sentinel so a recycled nid starts invisible.
  static const int _kNotVisible = -1;

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

  /// Listeners notified on every animation tick (layout-only updates).
  final List<VoidCallback> _animationListeners = [];

  /// Listeners notified when a single node's data changes without any
  /// structural change (e.g. [updateNode]). Receives the changed key.
  final List<void Function(TKey)> _nodeDataListeners = [];

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
  /// `_fullOffsetPrefix.length == _visibleLen + 1`.
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
        cached.length == _visibleLen + 1) {
      return;
    }
    final prefix = List<double>.filled(_visibleLen + 1, 0.0, growable: false);
    double acc = 0.0;
    for (int i = 0; i < _visibleLen; i++) {
      final key = _nidToKey[_visibleOrderNids[i]] as TKey;
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

  /// Lazy union of every currently-animating key across standalone, operation,
  /// and bulk groups. Invalidation is signature-based: [_animationStateSig]
  /// walks the current animation topology so overlapping transitions that keep
  /// collection lengths constant still invalidate correctly on next access.
  Set<TKey>? _animatingKeysCache;
  int _animatingKeysCacheSig = -1;

  /// Cached result of [computeFirstAnimatingVisibleIndex]. Depends on both
  /// animation state and the visible order, so the signature combines
  /// [_animationStateSig] with [_structureGeneration].
  int _firstAnimatingIndexCacheSig = -1;
  int _firstAnimatingIndexCacheVal = 0;

  /// Cheap O(1) signature over all animation collections. A transfer that
  /// keeps every collection's length identical would not change the signature,
  /// but no controller path performs such a transfer atomically — moves always
  /// pass through `_captureAndRemoveFromGroups` followed by a fresh insert,
  /// which shifts at least one length on each side.
  int _animationStateSig() {
    int s = 17;
    for (final entry in _standaloneAnimations.entries) {
      s = Object.hash(s, entry.key, entry.value.type);
    }
    for (final entry in _operationGroups.entries) {
      final groupKey = entry.key;
      final group = entry.value;
      s = Object.hash(s, groupKey, group.members.length);
      for (final memberKey in group.members.keys) {
        s = Object.hash(s, groupKey, memberKey);
      }
      for (final pendingKey in group.pendingRemoval) {
        s = Object.hash(s, groupKey, pendingKey, 1);
      }
    }
    final bulk = _bulkAnimationGroup;
    if (bulk != null) {
      s = Object.hash(s, bulk.members.length, bulk.pendingRemoval.length);
      for (final memberKey in bulk.members) {
        s = Object.hash(s, memberKey);
      }
      for (final pendingKey in bulk.pendingRemoval) {
        s = Object.hash(s, pendingKey, 1);
      }
    }
    return s;
  }

  /// Returns a set of every currently-animating key. Rebuilt on demand when
  /// [_animationStateSig] changes.
  Set<TKey> _ensureAnimatingKeys() {
    final sig = _animationStateSig();
    final cached = _animatingKeysCache;
    if (cached != null && sig == _animatingKeysCacheSig) return cached;
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
    _animatingKeysCacheSig = sig;
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
  int get visibleNodeCount => _visibleLen;

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
  /// as the internal [_kNotVisible] but exposed separately since callers
  /// should treat it as "unknown key".
  static const int noNid = -1;

  /// Returns the internal nid for [key], or [noNid] if the key isn't
  /// currently registered. O(1).
  int nidOf(TKey key) => _keyToNid[key] ?? noNid;

  /// Returns the key associated with [nid], or null if the nid has been
  /// released. O(1). Consumers that cache nid-indexed state can use this to
  /// detect stale entries after node removal.
  TKey? keyOfNid(int nid) {
    if (nid < 0 || nid >= _nidToKey.length) return null;
    return _nidToKey[nid];
  }

  /// The current high-water mark for allocated nids. Nid-indexed dense
  /// arrays maintained externally should grow to at least this length.
  int get nidCapacity => _nidToKey.length;

  /// Returns the nid of the visible node at [visibleIndex]. No [TKey] hash
  /// occurs. Panics (unchecked read) if [visibleIndex] is out of range.
  int visibleNidAt(int visibleIndex) => _visibleOrderNids[visibleIndex];

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

  /// Whether any nodes are currently animating.
  ///
  /// Used by the element and render object to defer expensive operations
  /// (like stale-node eviction and sticky precomputation) during animation.
  bool get hasActiveAnimations =>
      _standaloneAnimations.isNotEmpty ||
      _operationGroups.isNotEmpty ||
      (_bulkAnimationGroup != null && !_bulkAnimationGroup!.isEmpty);

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
    if (!hasActiveAnimations) return _visibleLen;
    // Cache key combines animation-state signature with structure generation:
    // the result depends on which keys are animating AND their visible indices.
    final sig = _animationStateSig() ^ (_structureGeneration * 2654435761);
    if (sig == _firstAnimatingIndexCacheSig &&
        _firstAnimatingIndexCacheVal <= _visibleLen) {
      return _firstAnimatingIndexCacheVal;
    }
    int min = _visibleLen;
    for (final k in _ensureAnimatingKeys()) {
      final idx = _visibleIndexOf(k);
      if (idx != _kNotVisible && idx < min) min = idx;
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
    return _visibleIndexOf(key);
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
    final targetIndex = _visibleIndexOf(key);
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
      final k = _nidToKey[_visibleOrderNids[i]] as TKey;
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
  double extentOf(
    TKey key, {
    double Function(TKey key)? extentEstimator,
  }) {
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
        sliverBaseOffset + sliverOffset - (viewportExtent - rowExtent) * alignment;
    final clamped = rawTarget.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (duration == Duration.zero) {
      position.jumpTo(clamped);
    } else {
      await position.animateTo(
        clamped,
        duration: duration,
        curve: curve,
      );
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
    final stopwatch = Stopwatch()..start();
    final scrollMs = duration.inMilliseconds;
    final expandMs = animationDuration.inMilliseconds;
    final totalMs = scrollMs > expandMs ? scrollMs : expandMs;

    // Root-first: each expansion runs against an already-visible parent.
    for (int i = ancestors.length - 1; i >= 0; i--) {
      expand(key: ancestors[i], animate: true);
    }

    void follower() {
      final targetIdx = _visibleIndexOf(key);
      if (targetIdx < 0) return;
      final progress = scrollMs == 0
          ? 1.0
          : (stopwatch.elapsedMilliseconds / scrollMs).clamp(0.0, 1.0);
      final tCurved = curve.transform(progress);

      // Base offset from the cached full-extent prefix sum (O(1) amortized).
      // Then correct for each animating node whose visible index precedes
      // the target: swap its full extent for its current (animated) extent.
      // The number of animating nodes is typically tiny compared to N.
      double currentOffset = _fullOffsetAt(targetIdx);
      void correct(TKey k) {
        final idx = _visibleIndexOf(k);
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
          sliverBaseOffset + currentOffset - (viewportExtent - rowExtent) * alignment;
      final desiredClamped = desired.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      final scroll =
          initialPixels + (desiredClamped - initialPixels) * tCurved;
      position.jumpTo(
        scroll.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }

    addAnimationListener(follower);
    await Future<void>.delayed(Duration(milliseconds: totalMs));
    removeAnimationListener(follower);

    if (!scrollController.hasClients) return true;

    // Final precise snap. Layout is settled, so scrollOffsetOf returns the
    // exact target — the running clamp may have drifted slightly while
    // maxScrollExtent was still catching up.
    final finalOffset = scrollOffsetOf(key, extentEstimator: extentEstimator);
    if (finalOffset == null) return true;
    final finalPosition = scrollController.position;
    final viewportExtent = finalPosition.viewportDimension;
    final rowExtent = extentOf(key, extentEstimator: extentEstimator);
    final finalTarget =
        sliverBaseOffset + finalOffset - (viewportExtent - rowExtent) * alignment;
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
        _batchDidRequestStructural = false;
        _batchDirtyDataNodes = null;
        // Fire structural first: a structural notify causes the element to
        // mark itself for a full refresh, which subsumes any data-only
        // refresh for the same keys. Firing data first would queue a
        // targeted refresh that the full refresh then redundantly repeats.
        if (didStructural) {
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
  void _notifyStructural() {
    if (_batchDepth > 0) {
      _batchDidRequestStructural = true;
      return;
    }
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
    final sorted = comparator != null ? (List.of(roots)..sort(comparator)) : roots;
    for (final node in sorted) {
      _adoptKey(node.key);
      _dataByNid[_keyToNid[node.key]!] = node;
      _setParentKey(node.key, null);
      _setChildList(node.key, []);
      _setDepthKey(node.key, 0);
      _setExpandedKey(node.key, false);
      _roots.add(node.key);
      _visibleAddKey(node.key);
    }
    _rebuildVisibleIndex();
    _structureGeneration++;
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
        final effectiveIndex = index ??
            (comparator != null ? _sortedIndex(_roots, node) : null);
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
      _dataByNid[_keyToNid[node.key]!] = node;
      if (preservePendingSubtreeState) {
        _rebuildVisibleOrder();
        _structureGeneration++;
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
      _dataByNid[_keyToNid[node.key]!] = node;
      final currentParent = _parentKeyOfKey(node.key);
      if (currentParent != null) {
        // Different parent — delegate to moveNode.
        moveNode(node.key, null, index: index);
        return;
      }
      final currentRootIndex = _roots.indexOf(node.key);
      final desiredIndex = index ??
          (comparator != null ? _sortedIndex(_roots, node) : null);
      final wantsRelocate = desiredIndex != null &&
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
      _notifyStructural();
      return;
    }

    // Add to data structures
    _adoptKey(node.key);
    _dataByNid[_keyToNid[node.key]!] = node;
    _setParentKey(node.key, null);
    _setChildList(node.key, []);
    _setDepthKey(node.key, 0);
    _setExpandedKey(node.key, false);

    // Add to roots list
    final effectiveIndex = index ?? (comparator != null ? _sortedIndex(_roots, node) : null);
    // Compute visible insert position BEFORE modifying _roots, since
    // _calculateRootInsertIndex reads _roots[effectiveIndex].
    final visibleInsertIndex = effectiveIndex != null && effectiveIndex < _roots.length
        ? _calculateRootInsertIndex(effectiveIndex)
        : _visibleLen;
    if (effectiveIndex != null && effectiveIndex < _roots.length) {
      _roots.insert(effectiveIndex, node.key);
    } else {
      _roots.add(node.key);
    }

    // Add to visible order (root nodes are always visible)
    final insertIndex = visibleInsertIndex;
    _visibleInsertKey(insertIndex, node.key);
    _updateIndicesFrom(insertIndex);
    _structureGeneration++;

    if (animate) {
      _startStandaloneEnterAnimation(node.key);
    }

    _notifyStructural();
  }

  /// Calculates the visible order index for inserting a root at the given root index.
  int _calculateRootInsertIndex(int rootIndex) {
    if (rootIndex == 0) return 0;
    if (rootIndex >= _roots.length) return _visibleLen;

    // Find the root at the given index and return its visible index
    final rootId = _roots[rootIndex];
    final idx = _visibleIndexOf(rootId);
    return idx == _kNotVisible ? _visibleLen : idx;
  }

  /// Adds children to a node.
  ///
  /// The children are added but not visible until the parent is expanded.
  /// If the parent already has children, the old children and their
  /// descendants are purged from all data structures first.
  void setChildren(TKey parentKey, List<TreeNode<TKey, TData>> children) {
    assert(
      _hasKey(parentKey),
      'Parent node $parentKey not found',
    );
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
      if (_hasKey(child.key) &&
          _parentKeyOfKey(child.key) != parentKey) {
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
      int minIdx = _visibleLen;
      int maxIdx = -1;
      int visibleCount = 0;
      for (final key in allOldKeys) {
        final idx = _visibleIndexOf(key);
        if (idx != _kNotVisible) {
          visibleCount++;
          if (idx < minIdx) minIdx = idx;
          if (idx > maxIdx) maxIdx = idx;
        }
      }

      final oldKeySet = allOldKeys.toSet();
      for (final key in allOldKeys) {
        _purgeNodeData(key);
      }

      if (visibleCount > 0) {
        if (maxIdx - minIdx + 1 == visibleCount) {
          // Contiguous removal
          _visibleRemoveRange(minIdx, maxIdx + 1);
          _updateIndicesAfterRemove(minIdx);
        } else {
          // Non-contiguous removal
          _visibleRemoveWhereKeyIn(oldKeySet);
          _rebuildVisibleIndex();
        }
        _structureGeneration++;
      }
    }

    final parentDepth = _depthOfKey(parentKey);
    final childIds = <TKey>[];
    final sorted = comparator != null ? (List.of(children)..sort(comparator)) : children;

    for (final child in sorted) {
      _adoptKey(child.key);
      _dataByNid[_keyToNid[child.key]!] = child;
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
      final parentIdx = _visibleIndexOf(parentKey);
      if (parentIdx != _kNotVisible) {
        final insertIdx = parentIdx + 1;
        _visibleInsertAllKeys(insertIdx, childIds);
        _updateIndicesFrom(insertIdx);
        _structureGeneration++;
      }
    }

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
    assert(
      _hasKey(parentKey),
      "Parent node $parentKey not found",
    );
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
        final effectiveIndex = index ??
            (comparator != null ? _sortedIndex(siblings, node) : null);
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
      _dataByNid[_keyToNid[node.key]!] = node;
      if (preservePendingSubtreeState) {
        _rebuildVisibleOrder();
        _structureGeneration++;
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
      _dataByNid[_keyToNid[node.key]!] = node;
      final currentParent = _parentKeyOfKey(node.key);
      if (currentParent != parentKey) {
        // Different parent — delegate to moveNode.
        moveNode(node.key, parentKey, index: index);
        return;
      }
      final siblings = _childListOrCreate(parentKey);
      final currentIndex = siblings.indexOf(node.key);
      final desiredIndex = index ??
          (comparator != null ? _sortedIndex(siblings, node) : null);
      final wantsRelocate = desiredIndex != null &&
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
      _notifyStructural();
      return;
    }
    final parentDepth = _depthOfKey(parentKey);
    // Add to data structures
    _adoptKey(node.key);
    _dataByNid[_keyToNid[node.key]!] = node;
    _setParentKey(node.key, parentKey);
    _setChildList(node.key, []);
    _setDepthKey(node.key, parentDepth + 1);
    _setExpandedKey(node.key, false);
    // Add to parent's children
    final siblings = _childListOrCreate(parentKey);
    final effectiveIndex = index ?? (comparator != null ? _sortedIndex(siblings, node) : null);
    if (effectiveIndex != null && effectiveIndex < siblings.length) {
      siblings.insert(effectiveIndex, node.key);
    } else {
      siblings.add(node.key);
    }
    // If parent is expanded, add to visible order
    if (_isExpandedKey(parentKey)) {
      final parentVisibleIndex = _visibleIndexOf(parentKey);
      if (parentVisibleIndex != _kNotVisible) {
        int insertIndex = parentVisibleIndex + 1;
        // Find position among siblings
        if (effectiveIndex != null) {
          for (int i = 0; i < effectiveIndex && i < siblings.length - 1; i++) {
            final siblingId = siblings[i];
            final siblingIndex = _visibleIndexOf(siblingId);
            if (siblingIndex != _kNotVisible) {
              insertIndex =
                  siblingIndex + 1 + _countVisibleDescendants(siblingId);
            }
          }
        } else {
          // Append after last visible descendant of parent
          // Note: _countVisibleDescendants only counts visible nodes, so the
          // newly added node (not yet visible) is not counted.
          insertIndex =
              parentVisibleIndex + 1 + _countVisibleDescendants(parentKey);
        }
        _visibleInsertKey(insertIndex, node.key);
        _updateIndicesFrom(insertIndex);
        _structureGeneration++;
        if (animate) {
          _startStandaloneEnterAnimation(node.key);
        }
      }
    }
    _notifyStructural();
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
    if (animate && _isVisible(key)) {
      // Mark nodes as pending deletion so _finalizeAnimation knows to
      // fully remove them (vs just hiding due to parent collapse)
      _pendingDeletion.addAll(nodesToRemove);
      // Mark all visible nodes as exiting
      for (final nodeId in nodesToRemove) {
        if (_isVisible(nodeId)) {
          _startStandaloneExitAnimation(nodeId);
        }
      }
    } else {
      _removeNodesImmediate(nodesToRemove);
      _structureGeneration++;
    }
    _notifyStructural();
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
    _dataByNid[_keyToNid[node.key]!] = node;
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
    _notifyStructural();
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
    _notifyStructural();
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
      final effectiveIndex = index ?? (comparator != null ? _sortedIndex(siblings, node) : null);
      if (effectiveIndex != null && effectiveIndex < siblings.length) {
        siblings.insert(effectiveIndex, key);
      } else {
        siblings.add(key);
      }
    } else {
      final effectiveIndex = index ?? (comparator != null ? _sortedIndex(_roots, node) : null);
      if (effectiveIndex != null && effectiveIndex < _roots.length) {
        _roots.insert(effectiveIndex, key);
      } else {
        _roots.add(key);
      }
    }

    final newDepth = newParentKey != null
        ? (_depthOfKey(newParentKey)) + 1
        : 0;
    _refreshSubtreeDepths(key, newDepth);

    _rebuildVisibleOrder();
    _structureGeneration++;
    _notifyStructural();
  }

  /// Recursively sets [_depths] for [key] and all its descendants.
  void _refreshSubtreeDepths(TKey key, int depth) {
    _setDepthKey(key, depth);
    final children = _childListOf(key);
    if (children != null) {
      for (final childKey in children) {
        _refreshSubtreeDepths(childKey, depth + 1);
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
      _notifyStructural();
      return;
    }
    _setExpandedKey(key, true);
    // Find where to insert children in visible order
    final parentIndex = _visibleIndexOf(key);
    if (parentIndex == _kNotVisible) {
      return;
    }

    if (!animate) {
      // No animation — insert and return
      final nodesToShow = _flattenSubtree(key, includeRoot: false);
      final nodesToInsert = <TKey>[];
      for (final nodeId in nodesToShow) {
        if (_pendingDeletion.contains(nodeId)) continue;
        if (!_isVisible(nodeId)) {
          nodesToInsert.add(nodeId);
        } else {
          _removeAnimation(nodeId);
        }
      }
      if (nodesToInsert.isNotEmpty) {
        final insertIndex = parentIndex + 1;
        _visibleInsertAllKeys(insertIndex, nodesToInsert);
        _updateIndicesFrom(insertIndex);
      }
      _structureGeneration++;
      _notifyStructural();
      return;
    }

    // Animated expand
    final existingGroup = _operationGroups[key];
    if (existingGroup != null) {
      // Path 1: Reversing a collapse — group already exists
      existingGroup.pendingRemoval.clear();
      // Restore each member's targetExtent to its full (natural) extent.
      // A prior fresh collapse may have captured mid-flight extents below
      // full (e.g., nodes taken from a bulk or standalone animation), so
      // computeExtent at value=1 would stop at the captured value and
      // snap to full on group disposal. Updating here ensures the
      // reversal terminates at the correct natural size.
      for (final entry in existingGroup.members.entries) {
        entry.value.targetExtent =
            _fullExtents[entry.key] ?? _unknownExtent;
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
        } else if (!_isVisible(nodeId)) {
          // New node not yet visible — insert at correct sibling position
          // and animate. _insertNodeIntoVisibleOrder appends at the end of
          // the grandparent's subtree, which drops the node past its
          // following siblings when they are already in the visible order.
          _insertNewNodeAmongSiblings(nodeId);
          _startStandaloneEnterAnimation(nodeId);
        }
      }
      _structureGeneration++;
      _notifyStructural();
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
    _operationGroups[key] = group;

    controller.addListener(_notifyAnimationListeners);
    controller.addStatusListener((status) {
      // Identity guard: if the group under [key] has been replaced (e.g. after
      // a purge + re-expand), ignore status events from the stale instance.
      if (!identical(_operationGroups[key], group)) return;
      _onOperationGroupStatusChange(key, status);
    });

    // Fast path check: count new vs existing nodes
    int newNodeCount = 0;
    int effectiveCount = 0;
    for (final nodeId in nodesToShow) {
      if (_pendingDeletion.contains(nodeId)) continue;
      effectiveCount++;
      if (!_isVisible(nodeId)) {
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
      _visibleInsertAllKeys(insertIndex, nodesToInsert);
      _updateIndicesFrom(insertIndex);
    } else {
      // Mixed path: some visible (exiting), some need insertion
      int currentInsertIndex = parentIndex + 1;
      int insertOffset = 0;
      int minInsertIndex = _visibleLen;
      for (final nodeId in nodesToShow) {
        if (_pendingDeletion.contains(nodeId)) continue;
        final existingIndex = _visibleIndexOf(nodeId);
        final capturedExtent = _captureAndRemoveFromGroups(nodeId);
        final nge = NodeGroupExtent(
          startExtent: capturedExtent ?? 0.0,
          targetExtent: _fullExtents[nodeId] ?? _unknownExtent,
        );
        group.members[nodeId] = nge;
        _nodeToOperationGroup[nodeId] = key;

        if (existingIndex != _kNotVisible) {
          // Node already visible (was exiting)
          currentInsertIndex = existingIndex + insertOffset + 1;
        } else {
          // Insert at current position
          if (currentInsertIndex < minInsertIndex) {
            minInsertIndex = currentInsertIndex;
          }
          _visibleInsertKey(currentInsertIndex, nodeId);
          insertOffset++;
          currentInsertIndex++;
        }
      }
      if (insertOffset > 0) {
        for (int i = minInsertIndex; i < _visibleLen; i++) {
          _setVisibleIndexByNid(_visibleOrderNids[i], i);
        }
        _assertIndexConsistency();
      }
    }

    _structureGeneration++;
    controller.forward();
    _notifyStructural();
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
      _notifyStructural();
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
      _notifyStructural();
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
      existingGroup.controller.reverse();

      // Handle descendants NOT in this group (from nested expansions)
      for (final nodeId in descendants) {
        if (_pendingDeletion.contains(nodeId)) continue;
        if (existingGroup.members.containsKey(nodeId)) continue;
        // Create standalone exit animation with speedMultiplier
        _startStandaloneExitAnimation(nodeId, triggeringAncestorId: key);
      }
      _structureGeneration++;
      _notifyStructural();
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
    _operationGroups[key] = group;

    controller.addListener(_notifyAnimationListeners);
    controller.addStatusListener((status) {
      // Identity guard: if the group under [key] has been replaced (e.g. after
      // a purge + re-expand), ignore status events from the stale instance.
      if (!identical(_operationGroups[key], group)) return;
      _onOperationGroupStatusChange(key, status);
    });

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
    _notifyStructural();
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

    void collectRecursive(TKey key) {
      if (_pendingDeletion.contains(key)) return;
      final children = _childListOf(key);
      if (children == null || children.isEmpty) return;

      final depth = _depthOfKey(key);
      final withinDepthLimit = maxDepth == null || depth < maxDepth;

      if (withinDepthLimit && !_isExpandedKey(key)) {
        nodesToExpand.add(key);
        for (final childId in children) {
          if (!_isVisible(childId)) {
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

      // Only recurse into children if within depth limit.
      if (withinDepthLimit) {
        for (final childId in children) {
          collectRecursive(childId);
        }
      }
    }

    // Collect from all roots
    for (final rootId in _roots) {
      collectRecursive(rootId);
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
      for (final entry in _operationGroups.entries) {
        final group = entry.value;
        if (group.pendingRemoval.isNotEmpty) {
          group.pendingRemoval.clear();
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
          if (_isVisible(key) &&
              !_nodeToOperationGroup.containsKey(key)) {
            _bulkAnimationGroup!.members.add(key);
          }
        }

        // Reverse the controller direction
        _bulkAnimationGroup!.controller.forward();
        _bulkAnimationGeneration++;
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
          if (_isVisible(key) &&
              !_nodeToOperationGroup.containsKey(key)) {
            _bulkAnimationGroup!.members.add(key);
          }
        }

        // Start expanding (value 0 -> 1)
        _bulkAnimationGroup!.controller.forward();
        _bulkAnimationGeneration++;
      }
    } else {
      // Remove animations if not animating
      for (final key in nodesToReverseExit) {
        _removeAnimation(key);
      }
    }
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
      for (final entry in _operationGroups.entries) {
        final group = entry.value;
        if (group.pendingRemoval.isEmpty) {
          // Group is expanding — reverse it
          for (final nodeId in group.members.keys) {
            if (!_pendingDeletion.contains(nodeId)) {
              group.pendingRemoval.add(nodeId);
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
        _bulkAnimationGeneration++;
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
        _bulkAnimationGeneration++;
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
    _notifyStructural();
  }

  /// Rebuilds the entire visible order from the tree structure.
  ///
  /// More efficient than incremental updates when making bulk changes.
  void _rebuildVisibleOrder() {
    _visibleClear();

    void addSubtree(TKey key) {
      _visibleAddKey(key);
      if (_pendingDeletion.contains(key)) {
        // Don't recurse based on expansion state (prevents zombie children),
        // but DO include children that are also pending deletion and still
        // have running exit animations — they need to stay in _visibleOrder
        // to animate out smoothly.
        final children = _childListOf(key);
        if (children != null) {
          for (final childId in children) {
            if (_pendingDeletion.contains(childId) &&
                _standaloneAnimations.containsKey(childId)) {
              addSubtree(childId);
            }
          }
        }
        return;
      }
      if (_isExpandedKey(key)) {
        final children = _childListOf(key);
        if (children != null) {
          for (final childId in children) {
            addSubtree(childId);
          }
        }
      } else {
        // Parent is collapsed, but children that are still in an active
        // animation (e.g. collapsing via an OperationGroup) must remain
        // in the visible order so their exit animation completes smoothly
        // instead of snapping away.
        final children = _childListOf(key);
        if (children != null) {
          for (final childId in children) {
            if (_nodeToOperationGroup.containsKey(childId) ||
                _bulkAnimationGroup?.members.contains(childId) == true ||
                _standaloneAnimations.containsKey(childId)) {
              addSubtree(childId);
            }
          }
        }
      }
    }

    for (final rootId in _roots) {
      addSubtree(rootId);
    }
    _rebuildVisibleIndex();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ANIMATION
  // ══════════════════════════════════════════════════════════════════════════

  /// Marker value indicating the target extent should be determined
  /// from the measured size during layout.
  static const double _unknownExtent = -1.0;

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
          final full = _fullExtents[key] ?? defaultExtent;
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
      final full = _fullExtents[key] ?? defaultExtent;
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
      if (group == null) continue;
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
      if (removedMember || removedPending) _bulkAnimationGeneration++;
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
    _bulkAnimationGroup =
        null; // Set to null first to prevent callback interference
    if (group != null) _bulkAnimationGeneration++;
    group?.dispose();
  }

  /// Called when the bulk animation completes or is dismissed.
  void _onBulkAnimationComplete() {
    if (_bulkAnimationGroup == null) return;
    final controller = _bulkAnimationGroup!.controller;
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
      }
    }

    // Dispose the group. Leaving it live retains an idle AnimationController
    // and its ticker registration for the life of the TreeController, which
    // is wasteful. A subsequent expandAll/collapseAll will create a new one.
    _disposeBulkAnimationGroup();

    _notifyStructural();
  }

  /// Called when an operation group's animation completes or is dismissed.
  void _onOperationGroupStatusChange(
    TKey operationKey,
    AnimationStatus status,
  ) {
    final group = _operationGroups[operationKey];
    if (group == null) return;

    if (status == AnimationStatus.completed) {
      // Expansion done (value = 1). Remove group, clean up maps.
      for (final nodeId in group.members.keys) {
        _nodeToOperationGroup.remove(nodeId);
      }
      _operationGroups.remove(operationKey);
      group.dispose();
      _notifyStructural();
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
      if (_keysToRemoveScratch.isNotEmpty) {
        _removeFromVisibleOrder(_keysToRemoveScratch);
        _structureGeneration++;
      }
      _operationGroups.remove(operationKey);
      group.dispose();
      _notifyStructural();
    }
  }

  /// Computes the speed multiplier for proportional timing.
  ///
  /// When a node transitions between animation sources, the remaining
  /// animation distance may be less than the full extent. The speed
  /// multiplier ensures the animation completes in proportional time.
  static double _computeSpeedMultiplier(
    double currentExtent,
    double fullExtent,
  ) {
    if (fullExtent <= 0) return 1.0;
    final fraction = currentExtent / fullExtent;
    if (fraction <= 0 || fraction >= 1.0) return 1.0;
    return (1.0 / fraction).clamp(1.0, 10.0);
  }

  void _startStandaloneEnterAnimation(TKey key, {TKey? triggeringAncestorId}) {
    // Capture current animated extent from any source BEFORE removing
    final capturedExtent = _captureAndRemoveFromGroups(key);
    final startExtent = capturedExtent ?? 0.0;
    final targetExtent = _fullExtents[key] ?? _unknownExtent;

    // Compute speed multiplier for proportional timing
    final full = _fullExtents[key] ?? defaultExtent;
    final speedMultiplier = startExtent > 0
        ? _computeSpeedMultiplier(full - startExtent, full)
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
    if (animationDuration == Duration.zero) animate = false;
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
    final full = _fullExtents[key] ?? defaultExtent;
    final speedMultiplier = _computeSpeedMultiplier(currentExtent, full);

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
    if (state == null) return false;

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
    if (parent == null) return;
    final parentVisibleIndex = _visibleIndexOf(parent);
    if (parentVisibleIndex == _kNotVisible) return;
    final siblings = _childListOf(parent);
    int insertIndex = parentVisibleIndex + 1;
    if (siblings != null) {
      for (final sib in siblings) {
        if (sib == nodeId) break;
        final sibIdx = _visibleIndexOf(sib);
        if (sibIdx != _kNotVisible) {
          insertIndex = sibIdx + 1 + _countVisibleDescendants(sib);
        }
      }
    }
    _visibleInsertKey(insertIndex, nodeId);
    _updateIndicesFrom(insertIndex);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

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
    _dataByNid.clear();
    _childrenByNid.clear();
    _parentByNid = Int32List(0);
    _depthByNid = Int32List(0);
    _expandedByNid = Uint8List(0);
    _ancestorsExpandedByNid = Uint8List(0);
    _indexByNid = Int32List(0);
    _roots.clear();
    _visibleClear();
    _standaloneAnimations.clear();
    _fullExtents.clear();
    _pendingDeletion.clear();
    _keyToNid.clear();
    _nidToKey.clear();
    _freeNids.clear();
    _nextNid = 0;
  }

  void _rebuildVisibleIndex() {
    _resetVisibleIndexAll();
    for (int i = 0; i < _visibleLen; i++) {
      _setVisibleIndexByNid(_visibleOrderNids[i], i);
    }
    _assertIndexConsistency();
  }

  /// Updates indices for all nodes from [startIndex] to the end of the list.
  ///
  /// Call after inserting (single or bulk) into the visible order.
  void _updateIndicesFrom(int startIndex) {
    for (int i = startIndex; i < _visibleLen; i++) {
      _setVisibleIndexByNid(_visibleOrderNids[i], i);
    }
    _assertIndexConsistency();
  }

  /// Updates indices after removing items that were at [removeIndex].
  /// Removed keys must already have had [_clearVisibleIndex] called on them.
  void _updateIndicesAfterRemove(int removeIndex) {
    // Shift indices for nodes after the removal point
    for (int i = removeIndex; i < _visibleLen; i++) {
      _setVisibleIndexByNid(_visibleOrderNids[i], i);
    }
    _assertIndexConsistency();
  }

  /// Debug assertion to verify index consistency.
  void _assertIndexConsistency() {
    assert(() {
      int visibleCount = 0;
      for (int i = 0; i < _visibleLen; i++) {
        final nid = _visibleOrderNids[i];
        final idx = _indexByNid[nid];
        if (idx != i) {
          final key = _nidToKey[nid];
          throw StateError(
            'Index mismatch: visible[$i] = $key (nid $nid), '
            'but _indexByNid[$nid] = $idx',
          );
        }
      }
      for (int nid = 0; nid < _nidToKey.length; nid++) {
        if (_indexByNid[nid] != _kNotVisible) visibleCount++;
      }
      if (visibleCount != _visibleLen) {
        throw StateError(
          'Length mismatch: _indexByNid has $visibleCount visible entries, '
          'but _visibleLen = $_visibleLen',
        );
      }
      _assertNidRegistryConsistency();
      return true;
    }());
  }

  /// Debug-only: verifies the nid registry matches the live node set.
  /// Every key in [_keyToNid] must reverse-map through [_nidToKey] and
  /// resolve to a non-null entry in [_dataByNid]; every freed nid must
  /// have a null reverse entry and a null data slot.
  void _assertNidRegistryConsistency() {
    assert(() {
      if (_dataByNid.length != _nidToKey.length) {
        throw StateError(
          '_dataByNid size ${_dataByNid.length} != _nidToKey size '
          '${_nidToKey.length}',
        );
      }
      for (final entry in _keyToNid.entries) {
        final key = entry.key;
        final nid = entry.value;
        if (nid < 0 || nid >= _nidToKey.length) {
          throw StateError('nid $nid for key $key out of range '
              '[0, ${_nidToKey.length})');
        }
        if (_nidToKey[nid] != key) {
          throw StateError(
            'nid $nid reverse mismatch: _nidToKey[$nid] = ${_nidToKey[nid]}, '
            'expected $key',
          );
        }
        if (_dataByNid[nid] == null) {
          throw StateError('nid $nid for key $key has null data slot');
        }
      }
      for (final freed in _freeNids) {
        if (freed < 0 || freed >= _nidToKey.length) {
          throw StateError('freed nid $freed out of range');
        }
        if (_nidToKey[freed] != null) {
          throw StateError(
            'freed nid $freed still has key ${_nidToKey[freed]}',
          );
        }
      }
      return true;
    }());
  }

  /// Removes a set of keys from `_visibleOrder` and updates the index.
  ///
  /// Detects if the keys form a contiguous block via `_visibleIndex` and
  /// uses `removeRange` (O(1) shift) when possible, falling back to
  /// `removeWhere` otherwise. Uses incremental index updates for contiguous
  /// removals, full rebuild for non-contiguous.
  void _removeFromVisibleOrder(Set<TKey> keys) {
    if (keys.isEmpty) return;
    if (keys.length == 1) {
      final key = keys.first;
      final idx = _visibleIndexOf(key);
      if (idx != _kNotVisible &&
          idx < _visibleLen &&
          _visibleKeyAt(idx) == key) {
        _clearVisibleIndex(key);
        _visibleRemoveAt(idx);
        _updateIndicesAfterRemove(idx);
        return;
      }
    }
    // Check if keys form a contiguous range via the nid-indexed visibility map.
    // Compare against [visibleCount] (not keys.length): a caller can pass a
    // key whose nid was already released (e.g. an op group's dismissed
    // handler purges pendingDeletion members before batching the visible-
    // order removal). Those keys report _kNotVisible here, and using
    // keys.length would let the fast path fire when non-key rows sit in the
    // range gap, clobbering unrelated siblings.
    int minIdx = _visibleLen;
    int maxIdx = -1;
    int visibleCount = 0;
    for (final key in keys) {
      final idx = _visibleIndexOf(key);
      if (idx == _kNotVisible) continue;
      visibleCount++;
      if (idx < minIdx) minIdx = idx;
      if (idx > maxIdx) maxIdx = idx;
    }
    if (maxIdx >= 0 && maxIdx - minIdx + 1 == visibleCount) {
      // Contiguous: clear the index first, then remove from the array.
      for (int i = minIdx; i <= maxIdx; i++) {
        _indexByNid[_visibleOrderNids[i]] = _kNotVisible;
      }
      _visibleRemoveRange(minIdx, maxIdx + 1);
      _updateIndicesAfterRemove(minIdx);
    } else {
      // Non-contiguous: remove from index, then list, then full rebuild
      for (final key in keys) {
        _clearVisibleIndex(key);
      }
      _visibleRemoveWhereKeyIn(keys);
      _rebuildVisibleIndex();
    }
  }

  List<TKey> _getDescendants(TKey key) {
    final result = <TKey>[];
    _getDescendantsInto(key, result);
    return result;
  }

  void _getDescendantsInto(TKey key, List<TKey> result) {
    final children = _childListOf(key);
    if (children == null) return;
    for (final childId in children) {
      result.add(childId);
      _getDescendantsInto(childId, result);
    }
  }

  List<TKey> _getVisibleDescendants(TKey key) {
    final result = <TKey>[];
    _getVisibleDescendantsInto(key, result);
    return result;
  }

  void _getVisibleDescendantsInto(TKey key, List<TKey> result) {
    final children = _childListOf(key);
    if (children == null) return;
    for (final childId in children) {
      if (_isVisible(childId)) {
        result.add(childId);
        if (_isExpandedKey(childId)) {
          _getVisibleDescendantsInto(childId, result);
        }
      }
    }
  }

  int _countVisibleDescendants(TKey key) {
    // Walk structural children regardless of [key]'s own expansion state:
    // a collapsed node can still have children in the visible order when
    // they are mid-animation (see _rebuildVisibleOrder's "collapsed with
    // active animations" branch). Gating on _isExpandedKey here would
    // under-count those rows and cause _insertNewNodeAmongSiblings /
    // insert() to place new siblings in the middle of a mid-collapsing
    // subtree instead of after it.
    int count = 0;
    final children = _childListOf(key);
    if (children == null) return 0;
    for (final childId in children) {
      if (_isVisible(childId)) {
        count++;
        count += _countVisibleDescendants(childId);
      }
    }
    return count;
  }

  /// Flattens a subtree into a list of node IDs in depth-first order.
  List<TKey> _flattenSubtree(TKey key, {bool includeRoot = true}) {
    final result = <TKey>[];
    _flattenSubtreeInto(key, result, includeRoot: includeRoot);
    return result;
  }

  void _flattenSubtreeInto(
    TKey key,
    List<TKey> result, {
    bool includeRoot = true,
  }) {
    if (includeRoot) result.add(key);
    if (_isExpandedKey(key)) {
      final children = _childListOf(key);
      if (children != null) {
        for (final childId in children) {
          _flattenSubtreeInto(childId, result);
        }
      }
    }
  }

  /// Removes a single key from all internal maps (but not from _visibleOrder,
  /// _roots, or the parent's _children list — those are handled by the caller).
  void _purgeNodeData(TKey key) {
    if (_fullExtents.remove(key) != null) _invalidateFullOffsetPrefix();
    // Clean up standalone animation state
    _standaloneAnimations.remove(key);
    // Clean up operation group membership
    final opGroupKey = _nodeToOperationGroup.remove(key);
    if (opGroupKey != null) {
      final group = _operationGroups[opGroupKey];
      if (group != null) {
        group.members.remove(key);
        group.pendingRemoval.remove(key);
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
      orphanGroup.dispose();
    }
    // Clean up bulk animation group membership
    final bulk = _bulkAnimationGroup;
    if (bulk != null) {
      final removedMember = bulk.members.remove(key);
      final removedPending = bulk.pendingRemoval.remove(key);
      if (removedMember || removedPending) _bulkAnimationGeneration++;
    }
    _pendingDeletion.remove(key);
    _clearVisibleIndex(key);
    _releaseNid(key);
  }

  void _removeNodesImmediate(List<TKey> nodeIds) {
    final keysToRemove = nodeIds.toSet();

    // Check visibility and contiguity BEFORE purging (purge clears the index)
    int minIdx = _visibleLen;
    int maxIdx = -1;
    int visibleCount = 0;
    for (final key in nodeIds) {
      final idx = _visibleIndexOf(key);
      if (idx != _kNotVisible) {
        visibleCount++;
        if (idx < minIdx) minIdx = idx;
        if (idx > maxIdx) maxIdx = idx;
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
        _visibleRemoveRange(minIdx, maxIdx + 1);
        _updateIndicesAfterRemove(minIdx);
      } else {
        // Non-contiguous removal
        _visibleRemoveWhereKeyIn(keysToRemove);
        _rebuildVisibleIndex();
      }
    }
  }

  @override
  void dispose() {
    _clear();
    _animationListeners.clear();
    _nodeDataListeners.clear();
    super.dispose();
  }
}

/// Read-only [List] view over a [TreeController]'s visible order, backed by
/// the controller's nid buffer. Every read resolves a nid back to its key
/// through [TreeController._nidToKey], so the view always reflects the latest
/// state. Mutation attempts throw.
class _VisibleNodesView<TKey, TData> extends ListBase<TKey> {
  _VisibleNodesView(this._controller);

  final TreeController<TKey, TData> _controller;

  @override
  int get length => _controller._visibleLen;

  @override
  set length(int value) {
    throw UnsupportedError('visibleNodes is read-only.');
  }

  @override
  TKey operator [](int index) {
    if (index < 0 || index >= _controller._visibleLen) {
      throw RangeError.index(index, this, 'index', null, _controller._visibleLen);
    }
    return _controller._nidToKey[_controller._visibleOrderNids[index]] as TKey;
  }

  @override
  void operator []=(int index, TKey value) {
    throw UnsupportedError('visibleNodes is read-only.');
  }
}
