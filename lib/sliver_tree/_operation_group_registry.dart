/// Internal: per-operation animation source for [TreeController].
///
/// Each call to `expand()` or `collapse()` creates an [OperationGroup]
/// with its own [AnimationController]. Proportional reversal timing is the
/// payoff: collapsing a 60%-done expand takes 60% of the duration, not
/// 100%. This registry owns the map of live groups and the per-nid reverse
/// index from member to operation key.
///
/// Per-group listeners are wired at install time, forwarding ticks to
/// `onTick` and status changes to `onStatusChanged(opKey, status)`. The
/// status handler itself lives on [TreeController] because it crosses
/// structure, order and notification concerns; the registry only tags the
/// event with the operation key.
library;

import 'package:flutter/animation.dart'
    show AnimationController, AnimationStatus, Curve;
import 'package:flutter/scheduler.dart' show TickerProvider;

import '_node_id_registry.dart';
import 'types.dart';

/// Owns the live [OperationGroup] map and the member-to-operation reverse
/// index.
///
/// Membership lives in TWO places that callers must keep in step: each
/// group's own `members` map, and this registry's per-nid reverse index.
/// [setMembership] and [clearMembership] maintain only the latter, by
/// design, so whichever caller adds or removes a member from the group is
/// the one responsible for both halves.
class OperationGroupRegistry<TKey> {
  OperationGroupRegistry({
    required NodeIdRegistry<TKey> nids,
    required TickerProvider vsync,
    required Duration Function() durationGetter,
    required void Function() onTick,
    required void Function(TKey opKey, AnimationStatus status) onStatusChanged,
    required void Function() onMembershipVisibilityChanged,
  }) : _nids = nids,
       _vsync = vsync,
       _durationGetter = durationGetter,
       _onTick = onTick,
       _onStatusChanged = onStatusChanged,
       _onMembershipVisibilityChanged = onMembershipVisibilityChanged;

  final NodeIdRegistry<TKey> _nids;
  final TickerProvider _vsync;
  final Duration Function() _durationGetter;
  final void Function() _onTick;
  final void Function(TKey opKey, AnimationStatus status) _onStatusChanged;

  /// Invoked when a group is hidden from [groups] and then restored
  /// without the group itself changing: today, the detach window in
  /// [runWithGroupDetached]. Injected rather than reached for, so this
  /// registry stays unaware of what the owner caches, exactly as
  /// [_onTick] and [_onStatusChanged] are.
  final void Function() _onMembershipVisibilityChanged;

  /// Live groups keyed by their `operationKey` (the node whose
  /// expand/collapse created the group).
  final Map<TKey, OperationGroup<TKey>> _groups =
      <TKey, OperationGroup<TKey>>{};

  /// Per-nid reverse index: for each nid, the operation key whose group
  /// holds that node as a member, or null. Sized to the nid registry's
  /// capacity via [resizeForCapacity].
  List<TKey?> _opGroupKeyByNid = <TKey?>[];

  // ──────────────────────────────────────────────────────────────────────
  // Capacity sync
  // ──────────────────────────────────────────────────────────────────────

  /// Grows the reverse index to [newCapacity], preserving existing
  /// entries. Never shrinks; [clear] releases the backing list.
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

  /// The operation key whose group [nid] is currently a member of, or
  /// null. Nid-keyed twin of [groupKeyOf], for hot paths that already
  /// hold the nid: [groupKeyOf] hashes the key back to the same nid.
  TKey? groupKeyOfNid(int nid) {
    return (nid >= 0 && nid < _opGroupKeyByNid.length)
        ? _opGroupKeyByNid[nid]
        : null;
  }

  /// Whether [key] is currently a member of any operation group.
  bool hasGroup(TKey key) {
    final nid = _nids[key];
    return nid != null && _opGroupKeyByNid[nid] != null;
  }

  /// Sets the reverse-index slot for [key] to [opKey]. [key] must be
  /// registered. Does NOT add [key] to the group's `members` map; the
  /// caller owns both halves.
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
  Iterable<MapEntry<TKey, OperationGroup<TKey>>> get groups => _groups.entries;

  /// Creates an [OperationGroup] whose controller starts at
  /// [initialValue]: 0.0 for a fresh expand, which runs forward, and 1.0
  /// for a fresh collapse, which reverses. Wires the injected tick and
  /// status callbacks.
  ///
  /// The status listener carries an IDENTITY GUARD. In the narrow window
  /// between `_groups.remove(opKey)` and `group.dispose()`, a stale
  /// controller can still fire one final synchronous status event;
  /// without the guard it would act on whichever newer group has taken
  /// its slot.
  ///
  /// Asserts the slot at [opKey] is empty. The controller's fresh-expand
  /// and fresh-collapse branches reach here only once their
  /// reverse-an-existing-group branch has early-returned.
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
      // Identity guard: see the method doc.
      if (!identical(_groups[opKey], group)) return;
      _onStatusChanged(opKey, status);
    });

    return group;
  }

  /// Disposes the group at [opKey] when it has no members and no
  /// pendingRemoval entries; a no-op otherwise. Re-checks identity before
  /// removing, so a group that was replaced in its slot since the lookup
  /// is left alone.
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

  /// Escape hatch for the controller's reverse-and-replay flow: the
  /// "reversing a collapse" branch of `expand()` and the "reversing an
  /// expand" branch of `collapse()`.
  ///
  /// Removes the group from the registry for the duration of [body], so
  /// the synchronous dismissed status event fired by assigning
  /// `controller.value` is dropped by the install-time identity guard
  /// instead of acted on. The `finally` re-attaches it, so a throw inside
  /// [body] cannot strand the group outside the registry.
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
      // The window above hides a LIVE group from [groups]. A synchronous
      // listener that rebuilds a membership-derived cache inside `body`
      // therefore builds it without this group's members and stamps it
      // with the pre-detach generation, which nothing else invalidates.
      // Fired here so no call site can forget the pairing.
      _onMembershipVisibilityChanged();
    }
  }

  /// Unconditionally removes and disposes the group at [opKey], clearing
  /// every member's reverse-index slot. Used by the controller's
  /// `_purgeNodeData` orphan-group teardown, when [opKey] itself is being
  /// deleted. Unlike [disposeIfEmpty], this fires even when members
  /// remain.
  ///
  /// Returns true when a group was removed, false when the slot was
  /// empty.
  bool removeGroup(TKey opKey) {
    final group = _groups.remove(opKey);
    if (group == null) return false;
    for (final memberKey in group.members.keys) {
      // Only clear the reverse-index slot for members that still point at
      // this opKey: a member may have moved to a different group between
      // scheduling and teardown, and clearing it would orphan that entry.
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

  /// Terminal teardown. Identical to [clear], because the registry holds
  /// nothing beyond its groups, and kept as its own entry point so every
  /// sub-coordinator tears down through the same name.
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
