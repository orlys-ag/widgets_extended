/// Internal: bidirectional key-to-nid mapping with free-list recycling.
///
/// Hands out stable integer handles ("nids") for arbitrary user keys so
/// hot-path per-node state can live in dense typed-data arrays indexed by
/// nid rather than hash maps keyed by the key type. Not exported from the
/// package barrel: `NodeStore` owns the single instance and injects it
/// into every component that maintains per-nid arrays.
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
  /// Sentinel returned by [nidOf] when a key is not registered. Its value
  /// is -1, matching the "not present" sentinel the controller's other
  /// index APIs return.
  static const int noNid = -1;

  /// Forward map. Absence means the key is not registered.
  final Map<TKey, int> _keyToNid = {};

  /// Reverse map indexed by nid. A null entry marks a free slot, which is
  /// what [isFree] and [keyOf] test for.
  final List<TKey?> _nidToKey = <TKey?>[];

  /// Recycle pool. [release] appends and [allocate] takes from the tail,
  /// LIFO because both ends of that are O(1) on a `List`. Recycling at
  /// all is what bounds [length] at the high-water mark of concurrently
  /// live keys instead of at every key ever registered, which is what
  /// keeps the callers' dense per-nid arrays small.
  final List<int> _freeNids = <int>[];

  /// Next never-used nid, handed out only when the recycle pool is empty.
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

  /// Hot-path reverse lookup that skips the bounds and liveness checks
  /// [keyOf] performs. [nid] must refer to a live slot within
  /// `[0, length)`; anything else is a programming error, and a free slot
  /// fails the cast whenever the key type is non-nullable. Use [keyOf]
  /// when unsure.
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
  /// - `nid`: the handle to use.
  /// - `isNew`: true when this call registered the key; false means the
  ///   nid was already in use and needs no per-nid initialization.
  /// - `grew`: true when the call appended a fresh slot at the tail, so
  ///   [length] increased; false when the slot came from the recycle
  ///   pool.
  ///
  /// The two flags drive different obligations, and the combination that
  /// catches callers out is `grew: false` with `isNew: true`: no array
  /// needs growing, but the slot is recycled and still holds the previous
  /// occupant's data, so it must be reset. `grew: true` is the signal to
  /// grow per-nid arrays to [length].
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
