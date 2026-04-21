/// Internal: bidirectional key↔nid mapping with free-list recycling.
///
/// Hands out stable integer handles ("nids") for arbitrary user keys so
/// hot-path per-node state can live in dense typed-data arrays indexed by
/// nid rather than hash maps keyed by [TKey]. Not exported from the
/// package barrel; used only by [TreeController].
library;

/// A bidirectional registry from opaque user keys to dense integer "nids".
///
/// Callers that maintain per-nid dense arrays must:
///
/// 1. Grow those arrays so their length is at least [length] whenever
///    [allocate] returns `grew: true`.
/// 2. Reset their per-nid slot to a defined default inside the allocation
///    path (either after every [allocate] call, or conditionally on
///    `isNew`), since recycled slots carry stale data from the previous
///    occupant.
/// 3. Zero their per-nid slot whenever [release] returns a non-null nid.
///
/// The registry does not own any per-nid arrays itself.
class NodeIdRegistry<TKey> {
  /// Sentinel returned by [nidOf] when a key is not registered. Shares the
  /// value of many other "not-present" sentinels in the controller (-1).
  static const int noNid = -1;

  final Map<TKey, int> _keyToNid = {};
  final List<TKey?> _nidToKey = <TKey?>[];
  final List<int> _freeNids = <int>[];
  int _nextNid = 0;

  /// Number of nid slots ever allocated (including freed slots currently in
  /// the recycle pool). Per-nid dense arrays maintained by the caller must
  /// have capacity at least this value.
  int get length => _nidToKey.length;

  /// Number of freed slots available for reuse.
  int get freeSlotCount => _freeNids.length;

  /// Number of live (registered) keys.
  int get liveCount => _keyToNid.length;

  /// Forward lookup: returns the nid for [key], or `null` if [key] is not
  /// registered. Matches the API of the underlying `Map<TKey, int>`.
  int? operator [](TKey key) {
    return _keyToNid[key];
  }

  /// Forward lookup with sentinel: returns the nid for [key], or [noNid]
  /// if [key] is not registered. Suited to public APIs and hot paths that
  /// prefer a branch on an int over a nullable check.
  int nidOf(TKey key) {
    return _keyToNid[key] ?? noNid;
  }

  /// Whether [key] is currently registered.
  bool contains(TKey key) {
    return _keyToNid.containsKey(key);
  }

  /// Reverse lookup: returns the key for [nid], or `null` if [nid] is free
  /// or out of range.
  TKey? keyOf(int nid) {
    if (nid < 0 || nid >= _nidToKey.length) {
      return null;
    }
    return _nidToKey[nid];
  }

  /// Hot-path reverse lookup. [nid] must refer to a live slot within
  /// `[0, length)`; behavior on a free slot is a nullable-cast failure in
  /// checked mode and undefined in production. Use [keyOf] when unsure.
  TKey keyOfUnchecked(int nid) {
    return _nidToKey[nid] as TKey;
  }

  /// Whether the slot [nid] is free (either out of range, or currently in
  /// the recycle pool). O(1).
  bool isFree(int nid) {
    if (nid < 0 || nid >= _nidToKey.length) {
      return true;
    }
    return _nidToKey[nid] == null;
  }

  /// Allocates a nid for [key]. Idempotent for already-registered keys.
  ///
  /// * `nid` — the handle to use.
  /// * `isNew` — `true` if this call registered the key. `false` means the
  ///   returned nid was already in use and no per-nid initialization is
  ///   required.
  /// * `grew` — `true` if the call appended a fresh slot at the tail
  ///   (i.e. [length] increased). `false` means a slot was recycled from
  ///   the free list. Callers that hold per-nid dense arrays must grow
  ///   those arrays to match [length] when `grew` is `true`; when `grew`
  ///   is `false` but `isNew` is `true`, the per-nid slot at `nid` carries
  ///   stale data from a prior occupant and must be reset.
  ({int nid, bool isNew, bool grew}) allocate(TKey key) {
    final existing = _keyToNid[key];
    if (existing != null) {
      return (nid: existing, isNew: false, grew: false);
    }
    final int nid;
    final bool grew;
    if (_freeNids.isNotEmpty) {
      nid = _freeNids.removeLast();
      _nidToKey[nid] = key;
      grew = false;
    } else {
      nid = _nextNid++;
      _nidToKey.add(key);
      grew = true;
    }
    _keyToNid[key] = nid;
    return (nid: nid, isNew: true, grew: grew);
  }

  /// Releases [key]'s nid back to the pool and returns it, or `null` if
  /// [key] was not registered. Callers must zero their per-nid arrays at
  /// the returned nid so a future [allocate] that recycles the slot sees
  /// a clean state.
  int? release(TKey key) {
    final nid = _keyToNid.remove(key);
    if (nid == null) {
      return null;
    }
    _nidToKey[nid] = null;
    _freeNids.add(nid);
    return nid;
  }

  /// Resets the registry to its initial empty state. Callers must
  /// separately clear any per-nid arrays they maintain.
  void clear() {
    _keyToNid.clear();
    _nidToKey.clear();
    _freeNids.clear();
    _nextNid = 0;
  }

  /// Debug-only: verifies the forward and reverse maps agree and that
  /// every freed nid has a null reverse entry. Throws [StateError] on any
  /// inconsistency. Wrapped in `assert` at call sites so release builds
  /// pay nothing.
  void debugAssertConsistent() {
    assert(() {
      for (final entry in _keyToNid.entries) {
        final key = entry.key;
        final nid = entry.value;
        if (nid < 0 || nid >= _nidToKey.length) {
          throw StateError(
            "nid $nid for key $key out of range [0, ${_nidToKey.length})",
          );
        }
        if (_nidToKey[nid] != key) {
          throw StateError(
            "nid $nid reverse mismatch: nidToKey[$nid] = ${_nidToKey[nid]}, "
            "expected $key",
          );
        }
      }
      for (final freed in _freeNids) {
        if (freed < 0 || freed >= _nidToKey.length) {
          throw StateError("freed nid $freed out of range");
        }
        if (_nidToKey[freed] != null) {
          throw StateError(
            "freed nid $freed still has key ${_nidToKey[freed]}",
          );
        }
      }
      return true;
    }());
  }
}
