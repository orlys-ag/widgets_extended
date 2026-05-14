/// Internal: flattened visible-order buffer for a [TreeController].
library;

import 'dart:typed_data';

import '_node_id_registry.dart';
import '_node_store.dart' show kNoParentNid;

/// Maintains the tree's flattened visible order as a dense buffer of nids
/// (not keys), plus a reverse nid → visible-index map for O(1) membership
/// queries.
///
/// Also owns the **roots list** (with order) and the **visible-subtree-size
/// cache** — both are pure functions of (structure × visible order), so they
/// belong inside this layer rather than on the controller. The cache satisfies
/// the invariant
///
/// ```
/// _subtreeSizeByNid[nid] == (nid in order ? 1 : 0)
///                         + sum over children c of _subtreeSizeByNid[c]
/// ```
///
/// Maintained incrementally on order mutations and parent-change events
/// (subscribed via [NodeStore.onParentChanged]); rebuilt wholesale by
/// [rebuild] for bulk paths.
///
/// The order buffer ([orderNids]) is sized independently and grown by
/// doubling on insert. The reverse-index buffer ([indexByNid]) and the
/// subtree-size buffer are per-nid dense arrays that must be grown in
/// lockstep with every other per-nid array maintained by the controller:
/// call [resizeForCapacity] from the same path that grows `_parentByNid`,
/// `_depthByNid`, and friends.
///
/// Does not own the registry; the registry is passed in and used to
/// translate [TKey] ↔ nid on the public boundary. Reads `parentByNid` and
/// `childKeysOf` via constructor callbacks so the buffer stays decoupled
/// from [NodeStore].
///
/// Mutating operations invoke the [onOrderMutated] callback so the
/// owner can invalidate derived caches (e.g. the full-extent prefix sum).
class VisibleOrderBuffer<TKey> {
  VisibleOrderBuffer({
    required NodeIdRegistry<TKey> registry,
    required int Function(int nid) parentByNid,
    required List<TKey>? Function(TKey key) childKeysOf,
    required void Function() onOrderMutated,
  })  : _nids = registry,
        _parentByNidLookup = parentByNid,
        _childKeysOf = childKeysOf,
        _onMutated = onOrderMutated;

  final NodeIdRegistry<TKey> _nids;
  final int Function(int nid) _parentByNidLookup;
  final List<TKey>? Function(TKey key) _childKeysOf;
  final void Function() _onMutated;

  /// Sentinel in [indexByNid] meaning "not currently in the visible
  /// order". Freed nids also carry this value so a recycled nid starts
  /// invisible.
  static const int kNotVisible = -1;

  Int32List _orderNids = Int32List(0);
  int _len = 0;
  Int32List _indexByNid = Int32List(0);
  Int32List _subtreeSizeByNid = Int32List(0);

  /// Roots (with order). Live, internally-owned `List<TKey>` — the reference
  /// is stable for the lifetime of this buffer instance, so wrapping it with
  /// an [UnmodifiableListView] produces a view that reflects subsequent
  /// mutations.
  ///
  /// Internal callers (TreeController and its part files) mutate this list
  /// directly using standard List operations (add, remove, insert, clear,
  /// chained `..clear()..addAll(...)`, etc.). External callers should use
  /// `TreeController.rootKeys` (the unmodifiable view).
  final List<TKey> roots = <TKey>[];

  /// Whether incremental subtree-size updates are currently suppressed.
  /// Set inside [runWithSubtreeSizeUpdatesSuppressed] (and therefore inside
  /// [rebuild]). Read by the inlined visibility callbacks in [insertNid] /
  /// [removeAt] / etc. before bumping the cache.
  bool _suppress = false;

  /// Number of entries currently in the visible order.
  int get length => _len;

  /// Underlying nid buffer. Read-only access for hot loops — do not
  /// mutate directly; use the insert/remove methods. Entries beyond
  /// [length] carry stale data from prior mutations.
  Int32List get orderNids => _orderNids;

  /// Underlying reverse-index buffer. Read-only access for hot loops.
  Int32List get indexByNid => _indexByNid;

  /// Per-nid count of currently-visible entries in the subtree rooted at
  /// [nid], including [nid] itself when it is in the order. O(1) array
  /// read. Returns 0 for nids that are not currently in the order and have
  /// no visible descendants, or for freed nids whose slot was reset.
  int subtreeSizeOf(int nid) {
    if (nid < 0 || nid >= _subtreeSizeByNid.length) {
      return 0;
    }
    return _subtreeSizeByNid[nid];
  }

  /// Returns the nid at visible position [i]. Unchecked — [i] must satisfy
  /// `0 <= i < length`.
  int nidAt(int i) {
    return _orderNids[i];
  }

  /// Returns the key at visible position [i]. Unchecked — [i] must satisfy
  /// `0 <= i < length`.
  TKey keyAt(int i) {
    return _nids.keyOfUnchecked(_orderNids[i]);
  }

  /// Visible position of [key], or [kNotVisible] if [key] is not in the
  /// order (or not registered). O(1).
  int indexOf(TKey key) {
    final nid = _nids[key];
    return nid == null ? kNotVisible : _indexByNid[nid];
  }

  /// Whether [key] is currently in the visible order.
  bool contains(TKey key) {
    return indexOf(key) != kNotVisible;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Reverse-index writes
  // ──────────────────────────────────────────────────────────────────────

  /// Writes [index] into the reverse-index slot for [nid]. [nid] must be
  /// live. Does not touch the order buffer.
  void setIndexByNid(int nid, int index) {
    _indexByNid[nid] = index;
  }

  /// Marks [key] as not visible. Safe on an unregistered key.
  void clearIndexOf(TKey key) {
    final nid = _nids[key];
    if (nid == null) {
      return;
    }
    _indexByNid[nid] = kNotVisible;
  }

  /// Clears the reverse-index slot for [nid] directly. Used by the
  /// controller during nid allocation/release to reset per-nid state.
  void clearIndexByNid(int nid) {
    _indexByNid[nid] = kNotVisible;
  }

  /// Per-nid cache cleanup used by the controller's adopt/release paths.
  /// Zeros both the subtree-size slot and the reverse-index slot in one
  /// call. Idempotent — safe to call on already-cleared slots. [nid] must
  /// be in range (callers that only have a key should resolve nid via the
  /// registry first).
  void clearForNid(int nid) {
    if (nid >= 0 && nid < _subtreeSizeByNid.length) {
      _subtreeSizeByNid[nid] = 0;
    }
    if (nid >= 0 && nid < _indexByNid.length) {
      _indexByNid[nid] = kNotVisible;
    }
  }

  /// Resets every reverse-index slot to [kNotVisible].
  void resetIndexAll() {
    _indexByNid.fillRange(0, _indexByNid.length, kNotVisible);
  }

  /// Grows every per-nid dense array (reverse index + subtree-size cache)
  /// to at least [capacity]. New reverse-index slots are initialised to
  /// [kNotVisible]; new subtree-size slots are initialised to 0. Call from
  /// the same code path that grows every other per-nid dense array the
  /// controller maintains.
  void resizeForCapacity(int capacity) {
    if (capacity > _indexByNid.length) {
      final grown = Int32List(capacity);
      grown.fillRange(_indexByNid.length, capacity, kNotVisible);
      grown.setRange(0, _indexByNid.length, _indexByNid);
      _indexByNid = grown;
    }
    if (capacity > _subtreeSizeByNid.length) {
      final grown = Int32List(capacity);
      grown.setRange(0, _subtreeSizeByNid.length, _subtreeSizeByNid);
      _subtreeSizeByNid = grown;
    }
  }

  /// Backwards-compatible alias for [resizeForCapacity] used by older
  /// call sites that grew only the reverse index. Plan B unifies the two
  /// growth paths since both per-nid arrays must stay in lockstep with
  /// the registry's capacity.
  void resizeIndex(int capacity) => resizeForCapacity(capacity);

  /// Rebuilds [indexByNid] from the current order buffer. Use after bulk
  /// rewrites that leave the reverse map stale.
  void rebuildIndex() {
    resetIndexAll();
    for (int i = 0; i < _len; i++) {
      _indexByNid[_orderNids[i]] = i;
    }
  }

  /// Refreshes [indexByNid] entries for positions in `[startIndex, length)`.
  /// Call after inserts at [startIndex] or after a contiguous removal that
  /// shifted the suffix.
  void reindexFrom(int startIndex) {
    for (int i = startIndex; i < _len; i++) {
      _indexByNid[_orderNids[i]] = i;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Subtree-size cache mutators (advanced)
  // ──────────────────────────────────────────────────────────────────────

  /// Adds [delta] to the subtree-size cache at [startNid] and at every
  /// ancestor. Stops at [kNoParentNid]. O(depth).
  ///
  /// Public so optimized callers (e.g. `_purgeAndRemoveFromOrder` Step 1)
  /// can do their own batched cache maintenance — pre-bumping ancestors
  /// before a downstream removal that they wrap in
  /// [runWithSubtreeSizeUpdatesSuppressed]. Most callers should rely on
  /// the inlined cache updates that fire automatically from the order
  /// mutators.
  ///
  /// No-op when [delta] is zero.
  void bumpFromSelf(int startNid, int delta) {
    if (delta == 0) return;
    int cur = startNid;
    while (cur != kNoParentNid &&
        cur >= 0 &&
        cur < _subtreeSizeByNid.length) {
      // Refuse to mutate a freed slot. In debug, surface the violation;
      // in release, bail out — corrupting a freed slot causes downstream
      // visibility-cache bugs once the nid is recycled.
      if (_nids.keyOf(cur) == null) {
        assert(
          false,
          "VisibleOrderBuffer.bumpFromSelf walked through freed nid $cur "
          "from start nid $startNid (delta=$delta)",
        );
        break;
      }
      final next = _subtreeSizeByNid[cur] + delta;
      assert(
        next >= 0,
        "subtree-size would go negative at nid $cur "
        "(current=${_subtreeSizeByNid[cur]}, delta=$delta, "
        "key=${_nids.keyOf(cur)})",
      );
      _subtreeSizeByNid[cur] = next;
      cur = _parentByNidLookup(cur);
    }
  }

  /// Rebuilds the subtree-size cache wholesale from the current tree
  /// structure and [orderNids] membership. O(N) via iterative pre-order
  /// walk followed by reverse-order summation (equivalent to iterative
  /// post-order). Used by [rebuild] after bulk operations that rewrite
  /// the order from scratch.
  void _rebuildSubtreeSizes() {
    _subtreeSizeByNid.fillRange(0, _subtreeSizeByNid.length, 0);
    final preOrderNids = <int>[];
    final stack = <TKey>[];
    for (int i = roots.length - 1; i >= 0; i--) {
      stack.add(roots[i]);
    }
    while (stack.isNotEmpty) {
      final key = stack.removeLast();
      final nid = _nids[key];
      if (nid == null) {
        assert(false, "key $key has no nid during _rebuildSubtreeSizes");
        continue;
      }
      preOrderNids.add(nid);
      final children = _childKeysOf(key);
      if (children == null) continue;
      for (int i = children.length - 1; i >= 0; i--) {
        stack.add(children[i]);
      }
    }
    for (int i = preOrderNids.length - 1; i >= 0; i--) {
      final nid = preOrderNids[i];
      final key = _nids.keyOf(nid);
      int size = _indexByNid[nid] == kNotVisible ? 0 : 1;
      if (key != null) {
        final children = _childKeysOf(key);
        if (children != null) {
          for (final child in children) {
            final childNid = _nids[child];
            if (childNid != null) {
              size += _subtreeSizeByNid[childNid];
            }
          }
        }
      }
      _subtreeSizeByNid[nid] = size;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Bulk paths
  // ──────────────────────────────────────────────────────────────────────

  /// ADVANCED. Suppresses the inlined subtree-size cache callbacks for the
  /// closure body. Caller is fully responsible for keeping the
  /// subtree-size cache consistent across the body — typically by
  /// pre-bumping via [bumpFromSelf] before the closure runs. Misuse
  /// silently corrupts the cache.
  ///
  /// Used by `_purgeAndRemoveFromOrder` Step 3 to avoid double-decrementing
  /// the cache on top of Step 1's pre-bump. Most callers should use
  /// [rebuild] instead.
  ///
  /// Re-entrant safe — nested calls preserve the prior suppression state.
  void runWithSubtreeSizeUpdatesSuppressed(void Function() body) {
    final wasSuppressed = _suppress;
    _suppress = true;
    try {
      body();
    } finally {
      _suppress = wasSuppressed;
    }
  }

  /// Convenience for clear+rebuild paths. Suppresses callbacks, clears the
  /// order, runs the closure (which populates via [addKey]), then rebuilds
  /// the reverse-index buffer (since [addKey] only appends to [orderNids]
  /// and does not write [indexByNid]) and runs the O(N) post-order
  /// subtree-size pass. Owns "clear + fill + finalize all derived state"
  /// so the closure body shrinks to just the populate work.
  void rebuild(void Function() build) {
    runWithSubtreeSizeUpdatesSuppressed(() {
      clear();
      build();
      rebuildIndex();
      _rebuildSubtreeSizes();
    });
  }

  // ──────────────────────────────────────────────────────────────────────
  // Observer subscription
  // ──────────────────────────────────────────────────────────────────────

  /// Wired up as the subscriber for [NodeStore.onParentChanged]. Shifts
  /// the moved subtree's contribution from the old parent's ancestor
  /// chain to the new parent's chain. No-op when [oldParent] equals
  /// [newParent], when the moved subtree contributes nothing, or when
  /// updates are currently suppressed (e.g. inside [rebuild]).
  ///
  /// Safe even though [NodeStore.setParent] has already written
  /// `parentByNid[nid] = newParent` at call time — the walks start from
  /// [oldParent] / [newParent] (not from [nid]) and traverse ancestor
  /// chains via the [parentByNid] callback; only the moved node's own
  /// slot was overwritten, ancestor slots are untouched.
  void handleParentChanged(int nid, int oldParent, int newParent) {
    if (_suppress) return;
    if (oldParent == newParent) return;
    if (nid < 0 || nid >= _subtreeSizeByNid.length) return;
    final delta = _subtreeSizeByNid[nid];
    if (delta == 0) return;
    if (oldParent != kNoParentNid) {
      bumpFromSelf(oldParent, -delta);
    }
    if (newParent != kNoParentNid) {
      bumpFromSelf(newParent, delta);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Order mutations
  // ──────────────────────────────────────────────────────────────────────

  void _ensureOrderCapacity(int needed) {
    if (needed <= _orderNids.length) {
      return;
    }
    int cap = _orderNids.isEmpty ? 16 : _orderNids.length;
    while (cap < needed) {
      cap *= 2;
    }
    final grown = Int32List(cap);
    grown.setRange(0, _len, _orderNids);
    _orderNids = grown;
  }

  /// Inserts [nid] at visible position [index], shifting the suffix right.
  /// [nid] must be live.
  void insertNid(int index, int nid) {
    _ensureOrderCapacity(_len + 1);
    // Int32List.setRange uses memmove semantics — overlap-safe even when
    // source and destination are the same buffer.
    _orderNids.setRange(index + 1, _len + 1, _orderNids, index);
    _orderNids[index] = nid;
    _len++;
    if (!_suppress) bumpFromSelf(nid, 1);
    _onMutated();
  }

  /// Inserts [key]'s nid at visible position [index]. [key] must be
  /// registered.
  void insertKey(int index, TKey key) {
    insertNid(index, _nids[key]!);
  }

  /// Appends [key]'s nid to the tail of the order. [key] must be registered.
  void addKey(TKey key) {
    _ensureOrderCapacity(_len + 1);
    final nid = _nids[key]!;
    _orderNids[_len++] = nid;
    if (!_suppress) bumpFromSelf(nid, 1);
    _onMutated();
  }

  /// Inserts the nids of [keys] at visible position [index], preserving
  /// their relative order. Each key must be registered.
  void insertAllKeys(int index, List<TKey> keys) {
    final n = keys.length;
    if (n == 0) {
      return;
    }
    _ensureOrderCapacity(_len + n);
    // memmove: shift [index, _len) to [index + n, _len + n).
    _orderNids.setRange(index + n, _len + n, _orderNids, index);
    for (int i = 0; i < n; i++) {
      final nid = _nids[keys[i]]!;
      _orderNids[index + i] = nid;
    }
    _len += n;
    if (!_suppress) {
      for (int i = 0; i < n; i++) {
        bumpFromSelf(_orderNids[index + i], 1);
      }
    }
    _onMutated();
  }

  /// Removes the entry at visible position [index], shifting the suffix
  /// left by one.
  void removeAt(int index) {
    final removed = _orderNids[index];
    // memmove: shift [index + 1, _len) to [index, _len - 1).
    _orderNids.setRange(index, _len - 1, _orderNids, index + 1);
    _len--;
    if (!_suppress) bumpFromSelf(removed, -1);
    _onMutated();
  }

  /// Removes entries in `[start, end)`, shifting the suffix left.
  void removeRange(int start, int end) {
    final n = end - start;
    if (n <= 0) {
      return;
    }
    if (!_suppress) {
      for (int i = start; i < end; i++) {
        bumpFromSelf(_orderNids[i], -1);
      }
    }
    // memmove: shift [start + n, _len) to [start, _len - n).
    _orderNids.setRange(start, _len - n, _orderNids, start + n);
    _len -= n;
    _onMutated();
  }

  /// Compacts the order by dropping every entry whose key is in [keys], or
  /// whose nid has been released. Preserves the relative order of kept
  /// entries.
  ///
  /// Per-nid cache decrements fire only for dropped nids whose key is
  /// still live at call time (and only when [_suppress] is false).
  /// Released nids are assumed to have already been cleaned up in the
  /// per-nid caches by the path that released them (e.g. the controller's
  /// `_releaseNid`).
  void removeWhereKeyIn(Set<TKey> keys) {
    int writeIdx = 0;
    for (int readIdx = 0; readIdx < _len; readIdx++) {
      final nid = _orderNids[readIdx];
      final key = _nids.keyOf(nid);
      if (key == null) {
        continue;
      }
      if (keys.contains(key)) {
        if (!_suppress) bumpFromSelf(nid, -1);
        continue;
      }
      _orderNids[writeIdx++] = nid;
    }
    if (writeIdx != _len) {
      _onMutated();
    }
    _len = writeIdx;
  }

  /// Zeros [length] but keeps the order and reverse-index buffers
  /// allocated so follow-up inserts can reuse them without realloc.
  /// Callers that want the reverse map cleared too must call
  /// [resetIndexAll] separately — this method does not touch it. Does NOT
  /// touch the subtree-size cache or [roots]; for a full reset use
  /// [reset].
  void clear() {
    _len = 0;
    _onMutated();
  }

  /// Full reset: zeros length and releases the order buffer, the
  /// reverse-index buffer, the subtree-size cache buffer back to empty,
  /// and clears [roots] in place (preserving the stable list reference).
  /// Used on controller-wide clear.
  void reset() {
    _len = 0;
    _orderNids = Int32List(0);
    _indexByNid = Int32List(0);
    _subtreeSizeByNid = Int32List(0);
    roots.clear();
    _onMutated();
  }

  /// Debug-only: asserts the order and reverse-index agree on every live
  /// entry, and that the number of non-sentinel reverse-index entries
  /// matches [length]. Wrapped in `assert(...)` so release builds skip it.
  void debugAssertConsistent() {
    assert(() {
      int visibleCount = 0;
      for (int i = 0; i < _len; i++) {
        final nid = _orderNids[i];
        final idx = _indexByNid[nid];
        if (idx != i) {
          final key = _nids.keyOf(nid);
          throw StateError(
            "Index mismatch: visible[$i] = $key (nid $nid), "
            "but indexByNid[$nid] = $idx",
          );
        }
      }
      for (int nid = 0; nid < _nids.length; nid++) {
        if (_indexByNid[nid] != kNotVisible) {
          visibleCount++;
        }
      }
      if (visibleCount != _len) {
        throw StateError(
          "Length mismatch: indexByNid has $visibleCount visible entries, "
          "but length = $_len",
        );
      }
      return true;
    }());
  }

  /// Debug-only: walks the tree and verifies every live nid's
  /// subtree-size slot equals the structural definition
  /// (own-presence + sum of children's sizes). Wrapped in `assert(...)`
  /// so release builds skip it.
  void debugAssertSubtreeSizeConsistent() {
    assert(() {
      for (int nid = 0; nid < _nids.length; nid++) {
        final key = _nids.keyOf(nid);
        if (key == null) continue;
        int expected = _indexByNid[nid] == kNotVisible ? 0 : 1;
        final children = _childKeysOf(key);
        if (children != null) {
          for (final child in children) {
            final childNid = _nids[child];
            if (childNid != null) {
              expected += _subtreeSizeByNid[childNid];
            }
          }
        }
        if (_subtreeSizeByNid[nid] != expected) {
          throw StateError(
            "_subtreeSizeByNid[$nid] (key=$key) = "
            "${_subtreeSizeByNid[nid]}, expected $expected",
          );
        }
      }
      return true;
    }());
  }
}
