/// Internal: per-operation animation source for [TreeController].
///
/// Each call to `expand()` / `collapse()` creates an [OperationGroup] with
/// its own [AnimationController] — proportional reversal timing is the
/// payoff (collapsing a 60%-done expand takes 60% of the duration, not
/// 100%). This registry owns the map of live groups and the per-nid
/// reverse index `_opGroupKeyByNid`.
///
/// The registry wires per-group `addListener` (tick → `onTick`) and
/// `addStatusListener` (status → `onStatusChanged(opKey, status)`) at
/// install time. The status handler lives on [TreeController] because it
/// crosses structure / order / notification concerns; the registry just
/// forwards the event with the operation key.
library;

import 'package:flutter/animation.dart' show AnimationController, AnimationStatus, Curve;
import 'package:flutter/scheduler.dart' show TickerProvider;

import '_node_id_registry.dart';
import 'types.dart';

class OperationGroupRegistry<TKey> {
  OperationGroupRegistry({
    required NodeIdRegistry<TKey> nids,
    required TickerProvider vsync,
    required Duration Function() durationGetter,
    required void Function() onTick,
    required void Function(TKey opKey, AnimationStatus status) onStatusChanged,
  }) : _nids = nids,
       _vsync = vsync,
       _durationGetter = durationGetter,
       _onTick = onTick,
       _onStatusChanged = onStatusChanged;

  final NodeIdRegistry<TKey> _nids;
  final TickerProvider _vsync;
  final Duration Function() _durationGetter;
  final void Function() _onTick;
  final void Function(TKey opKey, AnimationStatus status) _onStatusChanged;

  /// Live groups keyed by their `operationKey` (the node whose
  /// expand/collapse created the group).
  final Map<TKey, OperationGroup<TKey>> _groups = <TKey, OperationGroup<TKey>>{};

  /// Per-nid reverse index: `[nid]` → the operation key whose group
  /// contains this node as a member, or null. Sized to the registry's
  /// nid capacity via [resizeForCapacity].
  List<TKey?> _opGroupKeyByNid = <TKey?>[];

  // ──────────────────────────────────────────────────────────────────────
  // Capacity sync
  // ──────────────────────────────────────────────────────────────────────

  void resizeForCapacity(int newCapacity) {
    if (newCapacity > _opGroupKeyByNid.length) {
      final grown = List<TKey?>.filled(newCapacity, null);
      for (int i = 0; i < _opGroupKeyByNid.length; i++) {
        grown[i] = _opGroupKeyByNid[i];
      }
      _opGroupKeyByNid = grown;
    }
  }

  /// Per-nid cleanup used by the controller's adopt/release paths.
  /// Idempotent.
  void clearForNid(int nid) {
    if (nid >= 0 && nid < _opGroupKeyByNid.length) {
      _opGroupKeyByNid[nid] = null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Membership
  // ──────────────────────────────────────────────────────────────────────

  /// The operation key whose group [key] is currently a member of, or
  /// null if not in any group.
  TKey? groupKeyOf(TKey key) {
    final nid = _nids[key];
    return nid == null ? null : _opGroupKeyByNid[nid];
  }

  /// Whether [key] is currently a member of any operation group.
  bool hasGroup(TKey key) {
    final nid = _nids[key];
    return nid != null && _opGroupKeyByNid[nid] != null;
  }

  /// Sets the reverse-index slot for [key] to [opKey]. [key] must be
  /// registered. Does NOT add [key] to the group's `members` map — caller
  /// is responsible for that.
  void setMembership(TKey key, TKey opKey) {
    final nid = _nids[key]!;
    _opGroupKeyByNid[nid] = opKey;
  }

  /// Clears the reverse-index slot for [key]. Returns the prior operation
  /// key if any. Does NOT remove [key] from any group's `members` map.
  TKey? clearMembership(TKey key) {
    final nid = _nids[key];
    if (nid == null) return null;
    final prev = _opGroupKeyByNid[nid];
    if (prev != null) {
      _opGroupKeyByNid[nid] = null;
    }
    return prev;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Group lifecycle
  // ──────────────────────────────────────────────────────────────────────

  /// Returns the group at [opKey], or null if none.
  OperationGroup<TKey>? groupAt(TKey opKey) => _groups[opKey];

  /// Whether the registry has any live groups.
  bool get isNotEmpty => _groups.isNotEmpty;

  /// Iterate live groups. Used by the coordinator's `ensureAnimatingKeys`
  /// to add member contributions to the union mirrors.
  Iterable<MapEntry<TKey, OperationGroup<TKey>>> get groups =>
      _groups.entries;

  /// Creates an OperationGroup whose AnimationController starts at
  /// [initialValue] (0.0 for fresh expand / forward, 1.0 for fresh
  /// collapse / reverse). Wires the constructor-injected [onTick] and
  /// [onStatusChanged] callbacks. The status listener carries an
  /// **identity guard** that prevents a stale controller's final
  /// synchronous status event (during the narrow window between
  /// `_groups.remove(opKey)` and `group.dispose()`) from mutating a
  /// newer group that has taken its slot.
  ///
  /// Asserts the slot at [opKey] is empty — Path-2 fresh-expand /
  /// fresh-collapse must only reach here when the prior path-1 branch
  /// early-returned.
  OperationGroup<TKey> install(
    TKey opKey,
    Curve curve, {
    double initialValue = 0.0,
  }) {
    assert(
      _groups[opKey] == null,
      "OperationGroupRegistry.install: slot for $opKey already occupied; "
      "the fresh-expand / fresh-collapse paths must only reach here when "
      "the prior path-1 branch early-returned.",
    );

    final controller = AnimationController(
      vsync: _vsync,
      duration: _durationGetter(),
      value: initialValue,
    );
    final group = OperationGroup<TKey>(
      controller: controller,
      curve: curve,
      operationKey: opKey,
    );
    _groups[opKey] = group;

    controller.addListener(_onTick);
    controller.addStatusListener((status) {
      // Identity guard — see method doc.
      if (!identical(_groups[opKey], group)) return;
      _onStatusChanged(opKey, status);
    });

    return group;
  }

  /// Disposes the group at [opKey] if it has no members and no
  /// pendingRemoval entries. No-op otherwise. Mirrors the
  /// existing `_disposeOperationGroupIfEmpty` semantics including the
  /// identity guard against a newer occupant.
  void disposeIfEmpty(TKey opKey) {
    final group = _groups[opKey];
    if (group == null) return;
    if (group.members.isNotEmpty || group.pendingRemoval.isNotEmpty) {
      return;
    }
    if (!identical(_groups[opKey], group)) return;
    _groups.remove(opKey);
    group.dispose();
  }

  /// Internal escape hatch used by the controller's Path-1 reverse/replay
  /// flow (the "reversing a collapse" branch in expand() and the
  /// "reversing an expand" branch in collapse()). Briefly removes the
  /// group entry from the registry around [body] so a synchronous
  /// dismissed status event fired by `controller.value = 0.0` (or 1.0)
  /// is ignored by the install-time identity guard. Re-attaches the group
  /// in a `finally` block so an exception inside [body] doesn't leave the
  /// registry in an inconsistent state.
  void runWithGroupDetached(
    TKey opKey,
    void Function(OperationGroup<TKey> group) body,
  ) {
    final group = _groups.remove(opKey);
    if (group == null) return;
    try {
      body(group);
    } finally {
      _groups[opKey] = group;
    }
  }

  /// Unconditionally removes (and disposes) the group at [opKey],
  /// clearing every member's reverse-index slot. Used by the controller's
  /// `_purgeNodeData` orphan-group teardown when [opKey] IS being deleted.
  /// Distinct from [disposeIfEmpty] — this fires even when members remain.
  ///
  /// Returns true if a group was removed; false if the slot was empty.
  bool removeGroup(TKey opKey) {
    final group = _groups.remove(opKey);
    if (group == null) return false;
    for (final memberKey in group.members.keys) {
      // Only clear the reverse-index slot for members that still point at
      // this opKey — defensive, since a member could have been moved to
      // a different group between scheduling and teardown.
      final memberNid = _nids[memberKey];
      if (memberNid != null && _opGroupKeyByNid[memberNid] == opKey) {
        _opGroupKeyByNid[memberNid] = null;
      }
    }
    group.dispose();
    return true;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────

  /// Disposes every live OperationGroup's controller and clears the map +
  /// reverse index. Leaves the registry usable for further `install`
  /// calls.
  void clear() {
    for (final group in _groups.values) {
      group.dispose();
    }
    _groups.clear();
    _opGroupKeyByNid = <TKey?>[];
  }

  /// Same as [clear] plus marks the registry terminal. (Currently
  /// equivalent to [clear] — the registry has no separate "terminal"
  /// flag; the call is provided for API symmetry with the other
  /// sub-coordinators.)
  void dispose() {
    clear();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Debug
  // ──────────────────────────────────────────────────────────────────────

  /// Debug-only: asserts every live nid in `_opGroupKeyByNid` corresponds
  /// to a live `_groups[opKey]` entry that lists the nid's key as a
  /// member.
  void debugAssertConsistent() {
    assert(() {
      for (int nid = 0; nid < _opGroupKeyByNid.length; nid++) {
        final opKey = _opGroupKeyByNid[nid];
        if (opKey == null) continue;
        final memberKey = _nids.keyOf(nid);
        if (memberKey == null) {
          throw StateError(
            "OperationGroupRegistry._opGroupKeyByNid[$nid] = $opKey "
            "for freed nid",
          );
        }
        final group = _groups[opKey];
        if (group == null) {
          throw StateError(
            "OperationGroupRegistry: nid $nid (key=$memberKey) points at "
            "opKey $opKey but no group exists",
          );
        }
        if (!group.members.containsKey(memberKey)) {
          throw StateError(
            "OperationGroupRegistry: nid $nid (key=$memberKey) points at "
            "opKey $opKey but is not in the group's members map",
          );
        }
      }
      return true;
    }());
  }
}
