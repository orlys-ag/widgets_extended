/// Internal: bulk animation source for [TreeController].
///
/// Owns the single shared [AnimationGroup] used by `expandAll` /
/// `collapseAll`. One [AnimationController] drives every member
/// proportionally — bulk semantics, not per-node.
///
/// Maintains a per-nid mirror `_isMemberByNid` so render-layer hot paths
/// can do O(1) membership checks via [isMemberNid] without HashMap probes.
/// Generation counter `_generation` bumps on every membership change so
/// downstream caches (the render-layer prefix sums, the coordinator's
/// [BulkAnimationData] snapshot) can validate freshness in O(1).
library;

import 'dart:typed_data';

import 'package:flutter/animation.dart' show AnimationController, AnimationStatus, Curve;
import 'package:flutter/scheduler.dart' show TickerProvider;

import '_node_id_registry.dart';
import 'types.dart';

class BulkAnimator<TKey> {
  BulkAnimator({
    required NodeIdRegistry<TKey> nids,
    required TickerProvider vsync,
    required void Function() onTick,
    required void Function(AnimationStatus status) onStatusChanged,
  }) : _nids = nids,
       _vsync = vsync,
       _onTick = onTick,
       _onStatusChanged = onStatusChanged;

  final NodeIdRegistry<TKey> _nids;
  final TickerProvider _vsync;
  final void Function() _onTick;
  final void Function(AnimationStatus status) _onStatusChanged;

  AnimationGroup<TKey>? _group;

  /// Per-nid mirror of `_group.members ∪ pendingRemoval`. Slot is `1`
  /// when the corresponding nid is in either set, `0` otherwise. Sized
  /// to the registry's nid capacity via [resizeForCapacity].
  Uint8List _isMemberByNid = Uint8List(0);

  int _generation = 0;

  // ──────────────────────────────────────────────────────────────────────
  // Capacity sync
  // ──────────────────────────────────────────────────────────────────────

  void resizeForCapacity(int newCapacity) {
    if (newCapacity > _isMemberByNid.length) {
      final grown = Uint8List(newCapacity);
      grown.setRange(0, _isMemberByNid.length, _isMemberByNid);
      _isMemberByNid = grown;
    }
  }

  /// Per-nid cleanup used by the controller's adopt/release paths.
  /// Idempotent.
  void clearForNid(int nid) {
    if (nid >= 0 && nid < _isMemberByNid.length) {
      _isMemberByNid[nid] = 0;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Read API
  // ──────────────────────────────────────────────────────────────────────

  AnimationGroup<TKey>? get group => _group;

  /// Whether the bulk source has any members. True when no group exists
  /// OR the group exists but has no members.
  bool get isEmpty => _group == null || _group!.isEmpty;

  bool isMember(TKey key) {
    final nid = _nids[key];
    return nid != null && nid < _isMemberByNid.length && _isMemberByNid[nid] != 0;
  }

  bool isMemberNid(int nid) {
    if (nid < 0 || nid >= _isMemberByNid.length) return false;
    return _isMemberByNid[nid] != 0;
  }

  int get generation => _generation;

  /// Bumps the generation counter. Public so optimized callers can
  /// invalidate downstream caches without going through a member mutation.
  /// Mirrors today's `_bumpBulkGen` (controller-side caller would also
  /// call `coordinator.bumpAnimGen()` to bump the broad counter; the
  /// coordinator's `bumpBulkGen()` does both).
  void bumpGeneration() {
    _generation++;
  }

  /// Construct an allocation-free bulk-state snapshot. Mirrors the
  /// existing `BulkAnimationData.snapshot<TKey>(...)` static factory.
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

  /// Adds [key] to `_group.members` and updates the nid-keyed mirror.
  /// Returns true if the membership state changed. Caller is responsible
  /// for bumping the generation if needed (or the coordinator's
  /// [bumpBulkGen] does it as part of the broader bump).
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

  bool removeMember(TKey key) {
    final g = _group;
    if (g == null) return false;
    final removed = g.members.remove(key);
    if (removed) {
      final nid = _nids[key];
      // Only zero the mirror if the key isn't ALSO in pendingRemoval.
      if (nid != null && nid < _isMemberByNid.length &&
          !g.pendingRemoval.contains(key)) {
        _isMemberByNid[nid] = 0;
      }
    }
    return removed;
  }

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

  bool removePending(TKey key) {
    final g = _group;
    if (g == null) return false;
    final removed = g.pendingRemoval.remove(key);
    if (removed) {
      final nid = _nids[key];
      // Only zero the mirror if the key isn't ALSO in members.
      if (nid != null && nid < _isMemberByNid.length &&
          !g.members.contains(key)) {
        _isMemberByNid[nid] = 0;
      }
    }
    return removed;
  }

  void clearPending() {
    final g = _group;
    if (g == null) return;
    if (g.pendingRemoval.isEmpty) return;
    for (final key in g.pendingRemoval) {
      final nid = _nids[key];
      // Only zero if not in members.
      if (nid != null && nid < _isMemberByNid.length &&
          !g.members.contains(key)) {
        _isMemberByNid[nid] = 0;
      }
    }
    g.pendingRemoval.clear();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Group lifecycle
  // ──────────────────────────────────────────────────────────────────────

  /// Creates a fresh AnimationGroup, disposing any prior one first.
  /// [initialValue] is 0.0 for expandAll (forward), 1.0 for collapseAll
  /// (reverse). Wires the constructor-injected [onTick] and
  /// [onStatusChanged] callbacks.
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
    final group = AnimationGroup<TKey>(
      controller: controller,
      curve: curve,
    );
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

  /// Disposes the current group's controller (if any) and zeros every
  /// member's mirror slot. Mirrors today's `_disposeBulkAnimationGroup`
  /// — set the field to null FIRST to prevent the disposing controller's
  /// final synchronous status event from interfering.
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
    }
    g?.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────

  /// Disposes the current group (if any), zeros the mirror, resets
  /// generation. Leaves the animator usable for further `createGroup`
  /// calls.
  void clear() {
    disposeGroup();
    _isMemberByNid = Uint8List(0);
    _generation = 0;
  }

  /// Same as [clear] plus marks the animator terminal.
  void dispose() {
    clear();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Debug
  // ──────────────────────────────────────────────────────────────────────

  /// Debug-only: asserts the bulk member mirror matches
  /// `_group.members ∪ pendingRemoval` exactly across live nids.
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
      // Walk the mirror — every set bit must be in `expected`, and every
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
