/// Internal: bulk animation source for [TreeController].
///
/// Owns the single shared [AnimationGroup] used by `expandAll` and
/// `collapseAll`. One [AnimationController] drives every member
/// proportionally: bulk semantics, not per-node state.
///
/// Maintains a per-nid mirror `_isMemberByNid` so render-layer hot paths
/// can test membership in O(1) via [isMemberNid] without hashing a key.
/// The mirror covers `members` and `pendingRemoval` together, so a key
/// leaving one set clears its bit only when it is absent from the other;
/// every mutator below carries that check. [generation] bumps on each
/// membership change so downstream caches validate freshness in O(1).
library;

import 'dart:typed_data';

import 'package:flutter/animation.dart'
    show AnimationController, AnimationStatus, Curve;
import 'package:flutter/scheduler.dart' show TickerProvider;

import '_node_id_registry.dart';
import 'types.dart';

class BulkAnimator<TKey> {
  BulkAnimator({
    required NodeIdRegistry<TKey> nids,
    required TickerProvider vsync,
    required void Function() onTick,
    required void Function(AnimationStatus status) onStatusChanged,
    required void Function() onGroupDisposed,
  }) : _nids = nids,
       _vsync = vsync,
       _onTick = onTick,
       _onStatusChanged = onStatusChanged,
       _onGroupDisposed = onGroupDisposed;

  final NodeIdRegistry<TKey> _nids;
  final TickerProvider _vsync;
  final void Function() _onTick;
  final void Function(AnimationStatus status) _onStatusChanged;

  /// Invoked on every group disposal, whatever the caller: completion
  /// teardown, a [createGroup] replacement, or [clear]. The coordinator
  /// wires it to its broad-generation bump, so disposal always
  /// invalidates the union mirrors by construction and no individual
  /// teardown path can forget the pairing.
  final void Function() _onGroupDisposed;

  AnimationGroup<TKey>? _group;

  /// Per-nid mirror of the group's `members` and `pendingRemoval` sets
  /// combined: a slot is `1` when the nid is in either, `0` otherwise.
  /// Sized to the registry's nid capacity via [resizeForCapacity].
  Uint8List _isMemberByNid = Uint8List(0);

  int _generation = 0;

  // ──────────────────────────────────────────────────────────────────────
  // Capacity sync
  // ──────────────────────────────────────────────────────────────────────

  /// Grows the membership mirror to [newCapacity], preserving set bits.
  /// Never shrinks; [clear] releases the backing array.
  void resizeForCapacity(int newCapacity) {
    if (newCapacity > _isMemberByNid.length) {
      final grown = Uint8List(newCapacity);
      grown.setRange(0, _isMemberByNid.length, _isMemberByNid);
      _isMemberByNid = grown;
    }
  }

  /// Clears one nid's mirror bit, for the registry's adopt and release
  /// paths. Idempotent, and resets the mirror only: the group's own sets
  /// are left untouched, since the key is going away regardless.
  void clearForNid(int nid) {
    if (nid >= 0 && nid < _isMemberByNid.length) {
      _isMemberByNid[nid] = 0;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Read API
  // ──────────────────────────────────────────────────────────────────────

  /// The live bulk group, or null when no bulk animation is running.
  AnimationGroup<TKey>? get group => _group;

  /// Whether the bulk source has NO members: no group at all, or a group
  /// holding none. Counts `members` only, so a key sitting in
  /// `pendingRemoval` alone does not make this false.
  bool get isEmpty => _group == null || _group!.isEmpty;

  /// Whether [key] is in the group's `members` or its `pendingRemoval`.
  bool isMember(TKey key) {
    final nid = _nids[key];
    return nid != null &&
        nid < _isMemberByNid.length &&
        _isMemberByNid[nid] != 0;
  }

  /// Nid-keyed [isMember] for the render-layer hot path: one dense-array
  /// read, no key hashing. Out-of-range nids report false.
  bool isMemberNid(int nid) {
    if (nid < 0 || nid >= _isMemberByNid.length) return false;
    return _isMemberByNid[nid] != 0;
  }

  /// Counter bumped on every membership and group-lifecycle change, used
  /// as the O(1) validity signature for caches derived from bulk state.
  int get generation => _generation;

  /// Invalidates bulk-derived caches without mutating membership.
  ///
  /// Bumps the bulk counter ONLY. A caller that also needs the broad
  /// animation counter invalidated goes through the coordinator's
  /// `bumpBulkGen`, which bumps both.
  void bumpGeneration() {
    _generation++;
  }

  /// Bulk state as a value the render layer can read once per frame.
  /// Holds references to the live sets rather than copying them, and
  /// returns a shared const value while no group runs, so a read costs at
  /// most the snapshot record itself.
  BulkAnimationData<TKey> snapshot() {
    final g = _group;
    if (g == null || g.isEmpty) {
      return BulkAnimationData.inactive<TKey>();
    }
    return BulkAnimationData.snapshot<TKey>(
      value: g.value,
      generation: _generation,
      members: g.members,
      pendingRemoval: g.pendingRemoval,
      bulkMemberByNid: _isMemberByNid,
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Member mutators
  // ──────────────────────────────────────────────────────────────────────

  /// Adds [key] to the group's `members` and sets its mirror bit.
  /// Returns whether membership actually changed; no-ops without a group.
  ///
  /// Generation contract shared by every mutator here: they do NOT bump
  /// [generation]. The caller does, normally through the coordinator's
  /// `bumpBulkGen` so the broad counter moves with it.
  bool addMember(TKey key) {
    final g = _group;
    if (g == null) return false;
    final added = g.members.add(key);
    if (added) {
      final nid = _nids[key];
      if (nid != null && nid < _isMemberByNid.length) {
        _isMemberByNid[nid] = 1;
      }
    }
    return added;
  }

  /// Removes [key] from `members`. Its mirror bit survives when the key
  /// is also in `pendingRemoval`, since the mirror covers both sets.
  bool removeMember(TKey key) {
    final g = _group;
    if (g == null) return false;
    final removed = g.members.remove(key);
    if (removed) {
      final nid = _nids[key];
      // Only zero the mirror if the key isn't ALSO in pendingRemoval.
      if (nid != null &&
          nid < _isMemberByNid.length &&
          !g.pendingRemoval.contains(key)) {
        _isMemberByNid[nid] = 0;
      }
    }
    return removed;
  }

  /// Marks [key] as exiting for this bulk operation and sets its mirror
  /// bit. Its presence in `members` is left as it is.
  bool addPending(TKey key) {
    final g = _group;
    if (g == null) return false;
    final added = g.pendingRemoval.add(key);
    if (added) {
      final nid = _nids[key];
      if (nid != null && nid < _isMemberByNid.length) {
        _isMemberByNid[nid] = 1;
      }
    }
    return added;
  }

  /// Unmarks [key] as exiting. Its mirror bit survives when the key is
  /// also in `members`.
  bool removePending(TKey key) {
    final g = _group;
    if (g == null) return false;
    final removed = g.pendingRemoval.remove(key);
    if (removed) {
      final nid = _nids[key];
      // Only zero the mirror if the key isn't ALSO in members.
      if (nid != null &&
          nid < _isMemberByNid.length &&
          !g.members.contains(key)) {
        _isMemberByNid[nid] = 0;
      }
    }
    return removed;
  }

  /// Drops every pending-removal entry, clearing the mirror bits only of
  /// keys not also in `members`. Bounded by the pending set, not by nid
  /// capacity.
  void clearPending() {
    final g = _group;
    if (g == null) return;
    if (g.pendingRemoval.isEmpty) return;
    for (final key in g.pendingRemoval) {
      final nid = _nids[key];
      // Only zero if not in members.
      if (nid != null &&
          nid < _isMemberByNid.length &&
          !g.members.contains(key)) {
        _isMemberByNid[nid] = 0;
      }
    }
    g.pendingRemoval.clear();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Group lifecycle
  // ──────────────────────────────────────────────────────────────────────

  /// Creates a fresh [AnimationGroup], disposing any prior one first, and
  /// wires the injected tick and status callbacks to its controller.
  /// [initialValue] is 0.0 for `expandAll`, which runs forward, and 1.0
  /// for `collapseAll`, which reverses toward 0. Only completed and
  /// dismissed statuses are forwarded.
  AnimationGroup<TKey> createGroup(
    Duration duration,
    Curve curve, {
    double initialValue = 0.0,
  }) {
    disposeGroup();
    final controller = AnimationController(
      vsync: _vsync,
      duration: duration,
      value: initialValue,
    );
    final group = AnimationGroup<TKey>(controller: controller, curve: curve);
    controller.addListener(_onTick);
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _onStatusChanged(status);
      }
    });
    _group = group;
    _generation++;
    return group;
  }

  /// Disposes the current group's controller and zeros every member's
  /// mirror slot. The field is nulled FIRST so the disposing controller's
  /// final synchronous status event cannot act on a half-torn-down group.
  ///
  /// Generation contract: unlike the member mutators, this bumps
  /// [generation] itself, and the coordinator-wired [_onGroupDisposed]
  /// callback discharges the broad-generation bump, so callers never pair
  /// one manually.
  void disposeGroup() {
    final g = _group;
    _group = null;
    if (g != null) {
      // Walk members and pendingRemoval, zeroing the mirror. Bounded by
      // group size, not nidCapacity.
      for (final key in g.members) {
        final nid = _nids[key];
        if (nid != null && nid < _isMemberByNid.length) {
          _isMemberByNid[nid] = 0;
        }
      }
      for (final key in g.pendingRemoval) {
        final nid = _nids[key];
        if (nid != null && nid < _isMemberByNid.length) {
          _isMemberByNid[nid] = 0;
        }
      }
      _generation++;
      // After the field is nulled and the mirror is zeroed, so any
      // re-entrant read triggered from here observes post-bump state.
      _onGroupDisposed();
      g.dispose();
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────

  /// Disposes the current group, releases the mirror array and resets
  /// [generation]. Leaves the animator usable for a later [createGroup];
  /// the mirror stays empty until the next [resizeForCapacity].
  void clear() {
    disposeGroup();
    _isMemberByNid = Uint8List(0);
    _generation = 0;
  }

  /// Terminal teardown. Identical to [clear], because this animator holds
  /// nothing beyond its group, and kept as its own entry point so every
  /// sub-animator tears down through the same name.
  void dispose() {
    clear();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Debug
  // ──────────────────────────────────────────────────────────────────────

  /// Debug-only: asserts every mirror bit matches the union of the
  /// group's `members` and `pendingRemoval`, in both directions, across
  /// the whole mirror.
  void debugAssertConsistent() {
    assert(() {
      final g = _group;
      // Build expected from the group.
      final expected = <int>{};
      if (g != null) {
        for (final key in g.members) {
          final nid = _nids[key];
          if (nid != null) expected.add(nid);
        }
        for (final key in g.pendingRemoval) {
          final nid = _nids[key];
          if (nid != null) expected.add(nid);
        }
      }
      // Walk the mirror: every set bit must be in `expected`, and every
      // expected nid must have its bit set.
      for (int nid = 0; nid < _isMemberByNid.length; nid++) {
        final isSet = _isMemberByNid[nid] != 0;
        final shouldBeSet = expected.contains(nid);
        if (isSet != shouldBeSet) {
          final key = _nids.keyOf(nid);
          throw StateError(
            "BulkAnimator._isMemberByNid[$nid] (key=$key) = $isSet, "
            "expected $shouldBeSet",
          );
        }
      }
      return true;
    }());
  }
}
