/// Internal: structural-component storage for [TreeController].
///
/// Owns the nid registry plus every dense per-nid array that describes the
/// tree's structure (parent, children, depth, expansion, ancestors-expanded).
/// Pure data: no animation state, no visibility/order state, no
/// notifications. Visibility-related per-nid arrays
/// (`_visibleSubtreeSizeByNid`, the order buffer's reverse index) live on
/// the controller because they describe which nodes are currently rendered,
/// not the structure itself.
library;

import 'dart:typed_data';

import '_node_id_registry.dart';
import 'types.dart';

/// Sentinel value in nid-indexed parent arrays meaning "no parent" (root
/// node) or "slot is free". Same sentinel is safe for both because a freed
/// nid is never queried through [NodeStore.nids].
const int kNoParentNid = -1;

/// Dense ECS-style storage for the tree's structural state.
///
/// Hands out stable integer "nids" (via the embedded [NodeIdRegistry]) and
/// keeps every structural property in a typed-data array indexed by nid.
/// Reads cost an O(1) array access; writes update the array in place.
///
/// All mutators are intentionally low-level: they update the local arrays
/// and propagate the [_ancestorsExpandedByNid] cache where relevant, but
/// they do **not** update the visible-order buffer or the
/// visible-subtree-size cache. The owning controller wraps these calls
/// when those side effects are required.
class NodeStore<TKey, TData> {
  NodeStore({this.onCapacityGrew});

  /// Optional callback fired when [_ensureDenseCapacity] reallocates the
  /// per-nid arrays. The argument is the new capacity, in slots. The
  /// controller uses this to grow its own per-nid arrays
  /// ([_visibleSubtreeSizeByNid], the order buffer's reverse index) in
  /// lockstep.
  final void Function(int newCapacity)? onCapacityGrew;

  /// Bidirectional key↔nid registry with free-list recycling.
  final NodeIdRegistry<TKey> nids = NodeIdRegistry<TKey>();

  /// Node data indexed by nid. Entries for freed nids are null.
  final List<TreeNode<TKey, TData>?> _dataByNid = <TreeNode<TKey, TData>?>[];

  /// Parent nid for each node, indexed by nid. [kNoParentNid] for roots and
  /// freed slots.
  Int32List _parentByNid = Int32List(0);

  /// Ordered list of child keys for each node, indexed by the parent's nid.
  /// Inner lists remain keyed by [TKey].
  final List<List<TKey>?> _childrenByNid = <List<TKey>?>[];

  /// Cached depth for each node (0 for roots), indexed by nid. Entries for
  /// freed nids are 0.
  Int32List _depthByNid = Int32List(0);

  /// Expansion state for each node, indexed by nid. 0 = collapsed,
  /// 1 = expanded. Entries for freed nids are 0.
  Uint8List _expandedByNid = Uint8List(0);

  /// Cached "all ancestors expanded" bit for each node, indexed by nid. 1
  /// means every ancestor in the chain to the root is expanded (so the node
  /// is reachable by traversing the visible structure). Roots always carry
  /// 1 since they have no ancestors. A node's own expanded flag does not
  /// contribute. Maintained incrementally by [setParent], [setExpanded],
  /// and [adopt]; rebuilt wholesale by [rebuildAllAncestorsExpanded].
  /// Entries for freed nids are 0.
  Uint8List _ancestorsExpandedByNid = Uint8List(0);

  // ────────────────────────────────────────────────────────────────────────
  // Raw array exposure (read-only hot-path accessors)
  // ────────────────────────────────────────────────────────────────────────

  /// Read-only view of the parent-nid array. Hot-path consumers (e.g. the
  /// visible-subtree-size walker) read directly to skip per-call dispatch.
  /// Caller must not mutate.
  Int32List get parentByNid => _parentByNid;

  /// Read-only view of the depth-by-nid array.
  Int32List get depthByNid => _depthByNid;

  /// Read-only view of the expanded-flag array.
  Uint8List get expandedByNid => _expandedByNid;

  /// Read-only view of the ancestors-expanded cache.
  Uint8List get ancestorsExpandedByNid => _ancestorsExpandedByNid;

  /// Capacity high-water mark (number of nid slots ever allocated, including
  /// freed ones in the recycle pool). Per-nid arrays maintained externally
  /// must have at least this many slots.
  int get capacity => nids.length;

  // ────────────────────────────────────────────────────────────────────────
  // Allocation & release
  // ────────────────────────────────────────────────────────────────────────

  /// Allocates a nid for [key] (or returns the existing one) and resets every
  /// dense per-nid slot to its default. Grows the dense arrays via
  /// [_ensureDenseCapacity] when a fresh slot is appended; the
  /// [onCapacityGrew] callback fires from inside that path.
  ({int nid, bool isNew, bool grew}) adopt(TKey key) {
    final result = nids.allocate(key);
    final nid = result.nid;
    if (!result.isNew) {
      return result;
    }
    if (result.grew) {
      _dataByNid.add(null);
      _childrenByNid.add(null);
      _ensureDenseCapacity(nids.length);
    } else {
      _dataByNid[nid] = null;
      _childrenByNid[nid] = null;
    }
    _parentByNid[nid] = kNoParentNid;
    _depthByNid[nid] = 0;
    _expandedByNid[nid] = 0;
    _ancestorsExpandedByNid[nid] = 1;
    return result;
  }

  /// Releases the nid associated with [key] back to the pool and clears
  /// every dense slot. Returns the released nid, or null if [key] wasn't
  /// registered.
  int? release(TKey key) {
    final nid = nids.release(key);
    if (nid == null) return null;
    _dataByNid[nid] = null;
    _parentByNid[nid] = kNoParentNid;
    _childrenByNid[nid] = null;
    _depthByNid[nid] = 0;
    _expandedByNid[nid] = 0;
    _ancestorsExpandedByNid[nid] = 0;
    return nid;
  }

  /// Grows every typed-data nid-indexed array to at least [needed] slots.
  /// Doubles capacity on each realloc so amortized growth is O(1) per
  /// [adopt] call. Fires [onCapacityGrew] with the new capacity so external
  /// per-nid arrays can be resized in lockstep.
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
    onCapacityGrew?.call(cap);
  }

  /// Releases all nids and zeros every dense array. The onCapacityGrew
  /// callback is **not** fired; callers that maintain external per-nid
  /// arrays are responsible for clearing them too.
  void clear() {
    _dataByNid.clear();
    _childrenByNid.clear();
    _parentByNid = Int32List(0);
    _depthByNid = Int32List(0);
    _expandedByNid = Uint8List(0);
    _ancestorsExpandedByNid = Uint8List(0);
    nids.clear();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Forward / reverse lookups
  // ────────────────────────────────────────────────────────────────────────

  /// Nid for [key], or null when unregistered.
  int? nidOf(TKey key) => nids[key];

  /// Nid for [key], or [NodeIdRegistry.noNid] when unregistered. Hot path.
  int nidOfOrSentinel(TKey key) => nids.nidOf(key);

  /// Reverse lookup: key for [nid], or null if the slot is free.
  TKey? keyOf(int nid) => nids.keyOf(nid);

  /// Hot-path reverse lookup. [nid] must refer to a live slot.
  TKey keyOfUnchecked(int nid) => nids.keyOfUnchecked(nid);

  /// Whether [key] is currently registered.
  bool has(TKey key) => nids.contains(key);

  // ────────────────────────────────────────────────────────────────────────
  // Node data
  // ────────────────────────────────────────────────────────────────────────

  /// Node payload for [key], or null when unregistered.
  TreeNode<TKey, TData>? dataOf(TKey key) {
    final nid = nids[key];
    return nid == null ? null : _dataByNid[nid];
  }

  /// Sets the node payload for [key]. [key] must be registered.
  void setData(TKey key, TreeNode<TKey, TData> node) {
    _dataByNid[nids[key]!] = node;
  }

  /// Internal — used by debug consistency checks. Returns the data slot at
  /// [nid] (which may be null for freed slots).
  TreeNode<TKey, TData>? rawDataAtNid(int nid) => _dataByNid[nid];

  /// Internal — used by debug consistency checks.
  int get rawDataLength => _dataByNid.length;

  // ────────────────────────────────────────────────────────────────────────
  // Parent / children
  // ────────────────────────────────────────────────────────────────────────

  /// Parent nid for [key], or [kNoParentNid] for roots / unregistered keys.
  /// Hot path — no allocation, no exception.
  int parentNidOf(TKey key) {
    final nid = nids[key];
    return nid == null ? kNoParentNid : _parentByNid[nid];
  }

  /// Parent key for [key], or null for roots / unregistered keys.
  ///
  /// The parent nid slot can be null when the parent has already been freed
  /// ahead of this node in a removal sweep, so the reverse lookup must
  /// tolerate a null result.
  TKey? parentOf(TKey key) {
    final pNid = parentNidOf(key);
    return pNid == kNoParentNid ? null : nids.keyOf(pNid);
  }

  /// Sets the parent of [key] to [parent] (or null for root) and refreshes
  /// the cached [_ancestorsExpandedByNid] bit for [key], propagating the
  /// change through [key]'s subtree.
  ///
  /// Does **not** maintain the visibility-subtree-size cache (that lives on
  /// the controller) — callers that need that bookkeeping must capture the
  /// old parent first via [parentNidOf] and adjust externally before calling.
  void setParent(TKey key, TKey? parent) {
    final nid = nids[key]!;
    final newParentNid = parent == null ? kNoParentNid : nids[parent]!;
    _parentByNid[nid] = newParentNid;
    final newAe = _computeAncestorsExpandedNid(nid);
    if (_ancestorsExpandedByNid[nid] != newAe) {
      _ancestorsExpandedByNid[nid] = newAe;
      final childAe = (newAe != 0 && _expandedByNid[nid] != 0) ? 1 : 0;
      _propagateAncestorsExpandedToDescendants(key, childAe);
    }
  }

  /// Child key list for [key], or null when [key] has no list allocated yet
  /// (or is unregistered).
  List<TKey>? childListOf(TKey key) {
    final nid = nids[key];
    return nid == null ? null : _childrenByNid[nid];
  }

  /// Child key list for [key], allocating an empty list when none exists.
  /// [key] must be registered.
  List<TKey> childListOrCreate(TKey key) {
    final nid = nids[key]!;
    return _childrenByNid[nid] ??= <TKey>[];
  }

  /// Replaces the child list for [key]. [key] must be registered.
  void setChildList(TKey key, List<TKey> list) {
    _childrenByNid[nids[key]!] = list;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Depth
  // ────────────────────────────────────────────────────────────────────────

  /// Depth of [key], or 0 when unregistered.
  int depthOf(TKey key) {
    final nid = nids[key];
    return nid == null ? 0 : _depthByNid[nid];
  }

  /// Depth of the live nid [nid].
  int depthOfNid(int nid) => _depthByNid[nid];

  /// Sets the depth of [key]. [key] must be registered.
  void setDepth(TKey key, int depth) {
    _depthByNid[nids[key]!] = depth;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Expansion
  // ────────────────────────────────────────────────────────────────────────

  /// Whether [key] is expanded. False for unregistered keys.
  bool isExpanded(TKey key) {
    final nid = nids[key];
    return nid != null && _expandedByNid[nid] != 0;
  }

  /// Sets the expansion flag for [key]. [key] must be registered.
  ///
  /// By default propagates the change through [_ancestorsExpandedByNid] for
  /// descendants so ancestor-expansion queries stay O(1). Pass [propagate]
  /// as `false` in bulk paths that rebuild the cache wholesale via
  /// [rebuildAllAncestorsExpanded] — per-call propagation would compound to
  /// O(N × subtree) across the batch.
  void setExpanded(TKey key, bool expanded, {bool propagate = true}) {
    final nid = nids[key]!;
    final newVal = expanded ? 1 : 0;
    if (_expandedByNid[nid] == newVal) return;
    _expandedByNid[nid] = newVal;
    // Children's ae bit equals expanded(key) && ae(key). If ae(key) is 0,
    // children's ae is already 0 and unaffected by this flip.
    if (propagate && _ancestorsExpandedByNid[nid] != 0) {
      _propagateAncestorsExpandedToDescendants(key, newVal);
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Ancestors-expanded cache
  // ────────────────────────────────────────────────────────────────────────

  /// O(1) "are all ancestors of [key] expanded?" check. Returns true for
  /// roots and unregistered keys.
  bool ancestorsExpandedFast(TKey key) {
    final nid = nids[key];
    if (nid == null) return true;
    return _ancestorsExpandedByNid[nid] != 0;
  }

  int _computeAncestorsExpandedNid(int nid) {
    final parentNid = _parentByNid[nid];
    if (parentNid == kNoParentNid) return 1;
    return (_expandedByNid[parentNid] != 0 &&
            _ancestorsExpandedByNid[parentNid] != 0)
        ? 1
        : 0;
  }

  /// Sets the ancestors-expanded bit for every descendant of [key]. The bit
  /// assigned to [key]'s direct children is [childAe]; grandchildren then
  /// get `(expanded(child) && childAe)`, and so on.
  ///
  /// Short-circuits on descendants whose current bit already matches.
  /// Iterative (explicit worklist) so deep trees do not stack-overflow.
  void _propagateAncestorsExpandedToDescendants(TKey key, int childAe) {
    final parents = <TKey>[key];
    final childAes = <int>[childAe];
    while (parents.isNotEmpty) {
      final parent = parents.removeLast();
      final ae = childAes.removeLast();
      final children = childListOf(parent);
      if (children == null || children.isEmpty) continue;
      for (final child in children) {
        final childNid = nids[child];
        if (childNid == null) continue;
        if (_ancestorsExpandedByNid[childNid] == ae) continue;
        _ancestorsExpandedByNid[childNid] = ae;
        final grandAe = (ae != 0 && _expandedByNid[childNid] != 0) ? 1 : 0;
        parents.add(child);
        childAes.add(grandAe);
      }
    }
  }

  /// Rebuilds [_ancestorsExpandedByNid] wholesale in a single pass starting
  /// from [roots]. Used by bulk operations that bypass per-call propagation.
  void rebuildAllAncestorsExpanded(List<TKey> roots) {
    _ancestorsExpandedByNid.fillRange(0, _ancestorsExpandedByNid.length, 0);
    for (final rootKey in roots) {
      final rootNid = nids[rootKey];
      if (rootNid == null) continue;
      _ancestorsExpandedByNid[rootNid] = 1;
      final childAe = _expandedByNid[rootNid] != 0 ? 1 : 0;
      _propagateAncestorsExpandedToDescendants(rootKey, childAe);
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Bulk expansion clear
  // ────────────────────────────────────────────────────────────────────────

  /// Clears the expanded flag for every registered node whose depth is less
  /// than [maxDepth] (or for every node when [maxDepth] is null), then
  /// rebuilds the ancestors-expanded cache from [roots].
  void collapseAllInRegistry(int? maxDepth, List<TKey> roots) {
    if (maxDepth == null) {
      _expandedByNid.fillRange(0, _expandedByNid.length, 0);
    } else {
      final n = nids.length;
      for (int nid = 0; nid < n; nid++) {
        if (nids.isFree(nid)) continue;
        if (_expandedByNid[nid] == 0) continue;
        if (_depthByNid[nid] < maxDepth) {
          _expandedByNid[nid] = 0;
        }
      }
    }
    rebuildAllAncestorsExpanded(roots);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Debug
  // ────────────────────────────────────────────────────────────────────────

  /// Debug: verify per-nid data slots match the registry. Throws
  /// [StateError] on inconsistency. Wrapped in `assert` at call sites so
  /// release builds pay nothing.
  void debugAssertConsistent() {
    if (_dataByNid.length != nids.length) {
      throw StateError(
        "_dataByNid size ${_dataByNid.length} != registry size ${nids.length}",
      );
    }
    for (int nid = 0; nid < nids.length; nid++) {
      final key = nids.keyOf(nid);
      if (key == null) continue;
      if (_dataByNid[nid] == null) {
        throw StateError("nid $nid for key $key has null data slot");
      }
    }
    nids.debugAssertConsistent();
  }
}
