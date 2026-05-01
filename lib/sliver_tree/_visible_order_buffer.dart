/// Internal: flattened visible-order buffer for a [TreeController].
library;

import 'dart:typed_data';

import '_node_id_registry.dart';

/// Maintains the tree's flattened visible order as a dense buffer of nids
/// (not keys), plus a reverse nid → visible-index map for O(1) membership
/// queries.
///
/// The order buffer ([orderNids]) is sized independently and grown by
/// doubling on insert. The reverse-index buffer ([indexByNid]) is a
/// per-nid dense array that must be grown in lockstep with every other
/// per-nid array maintained by the controller: call [resizeIndex] from
/// the same path that grows `_parentByNid`, `_depthByNid`, and friends.
///
/// Does not own the registry; the registry is passed in and used to
/// translate [TKey] ↔ nid on the public boundary.
///
/// Mutating operations invoke the [onOrderMutated] callback so the
/// owner can invalidate derived caches (e.g. the full-extent prefix sum).
///
/// Operations that change an individual nid's membership in the order
/// also invoke the per-nid [onNidAdded] / [onNidRemoved] callbacks so
/// owners can maintain per-nid aggregates incrementally (e.g. the
/// visible-subtree-size cache). These are **not** fired from the bulk
/// [clear] / [reset] paths — those expect the owner to perform a
/// wholesale rebuild of derived state instead of processing N
/// individual events.
class VisibleOrderBuffer<TKey> {
  VisibleOrderBuffer({
    required NodeIdRegistry<TKey> registry,
    required void Function() onOrderMutated,
    void Function(int nid)? onNidAdded,
    void Function(int nid)? onNidRemoved,
  })  : _nids = registry,
        _onMutated = onOrderMutated,
        _onNidAdded = onNidAdded,
        _onNidRemoved = onNidRemoved;

  final NodeIdRegistry<TKey> _nids;
  final void Function() _onMutated;
  final void Function(int nid)? _onNidAdded;
  final void Function(int nid)? _onNidRemoved;

  /// Sentinel in [indexByNid] meaning "not currently in the visible
  /// order". Freed nids also carry this value so a recycled nid starts
  /// invisible.
  static const int kNotVisible = -1;

  Int32List _orderNids = Int32List(0);
  int _len = 0;
  Int32List _indexByNid = Int32List(0);

  /// Number of entries currently in the visible order.
  int get length => _len;

  /// Underlying nid buffer. Read-only access for hot loops — do not
  /// mutate directly; use the insert/remove methods. Entries beyond
  /// [length] carry stale data from prior mutations.
  Int32List get orderNids => _orderNids;

  /// Underlying reverse-index buffer. Read-only access for hot loops.
  Int32List get indexByNid => _indexByNid;

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

  /// Resets every reverse-index slot to [kNotVisible].
  void resetIndexAll() {
    _indexByNid.fillRange(0, _indexByNid.length, kNotVisible);
  }

  /// Grows the reverse-index array to at least [capacity]. New slots are
  /// initialised to [kNotVisible]. Call from the same code path that
  /// grows every other per-nid dense array the controller maintains.
  void resizeIndex(int capacity) {
    if (capacity <= _indexByNid.length) {
      return;
    }
    final grown = Int32List(capacity);
    grown.fillRange(_indexByNid.length, capacity, kNotVisible);
    grown.setRange(0, _indexByNid.length, _indexByNid);
    _indexByNid = grown;
  }

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
    _onNidAdded?.call(nid);
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
    _onNidAdded?.call(nid);
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
    final cb = _onNidAdded;
    if (cb != null) {
      for (int i = 0; i < n; i++) {
        cb(_orderNids[index + i]);
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
    _onNidRemoved?.call(removed);
    _onMutated();
  }

  /// Removes entries in `[start, end)`, shifting the suffix left.
  void removeRange(int start, int end) {
    final n = end - start;
    if (n <= 0) {
      return;
    }
    final cb = _onNidRemoved;
    if (cb != null) {
      for (int i = start; i < end; i++) {
        cb(_orderNids[i]);
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
  /// Per-nid removal callbacks fire only for dropped nids whose key is
  /// still live at call time. Released nids are assumed to have already
  /// been cleaned up in per-nid aggregate caches by the path that
  /// released them (e.g. `_releaseNid`).
  void removeWhereKeyIn(Set<TKey> keys) {
    final cb = _onNidRemoved;
    int writeIdx = 0;
    for (int readIdx = 0; readIdx < _len; readIdx++) {
      final nid = _orderNids[readIdx];
      final key = _nids.keyOf(nid);
      if (key == null) {
        continue;
      }
      if (keys.contains(key)) {
        cb?.call(nid);
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
  /// [resetIndexAll] separately — this method does not touch it.
  void clear() {
    _len = 0;
    _onMutated();
  }

  /// Full reset: zeros length and releases both the order buffer and the
  /// reverse-index buffer back to empty. Used on controller-wide clear.
  void reset() {
    _len = 0;
    _orderNids = Int32List(0);
    _indexByNid = Int32List(0);
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
}
