/// Internal: the makeRoom animation source.
///
/// HELD paint-only gap offsets: an entry animates to a non-zero target and
/// then PERSISTS until re-targeted or released, which is what makes the
/// gap the target state rather than a transient toward one. The offsets
/// come from a DRY-RUN lane resolution over at most two lane-axis
/// buckets, supplied by the controller; the model is never written.
///
/// Beside the offsets the engine holds a HELD EXTENT per id: for every
/// member the dry run touched, the band its prospective lanes would give
/// it minus the band it has, so a neighbour on a FIXED lane axis shrinks
/// or widens with the gap instead of after the drop. Extents ride the
/// offsets' clock and their two doors.
///
/// A RESIZE session's own item holds no offset. It holds a LEAD and an
/// EXTENT, deltas over the geometry the render gives its STORED span, so
/// its dragged edge moves and its far edge holds while the model stays
/// unwritten, and on a content-sized lane axis a BAND, the term its lane
/// band adds while it stays laned in its track, or a VACATE, the share of
/// its term it gives up while it leaves that track. The controller
/// computes their targets through the item-geometry rule, and the layout
/// re-derives them every frame from the session's prospective span and
/// lane assignment, its SOURCE, so they follow every track the preview
/// itself resizes.
///
/// Beside the offsets the engine holds prospective lane SLOTS for the
/// session's item, a LIFTED one or a resized one the preview lanes in a
/// track it is not laned in: a slot has no paint half at all and exists
/// only so the track-sizing walk can count the lane the drop would
/// occupy. The contribution reaches the SOURCE track as well as the
/// prospective one, because the dry run re-sweeps the stored bucket; the
/// one term held still is the lifted item's own band, which its in-place
/// widget keeps painting. An install is IDEMPOTENT for an unchanged target, which is
/// what lets a closing entry ever retire under a per-frame re-resolve.
///
/// Not exported from the module barrel.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '_board_span.dart';
import 'board_animation_style.dart';

/// A resize session's geometry targets for its own item, per axis and in
/// content space: the LEAD and the EXTENT the item-geometry rule gives it
/// under the prospective span and lanes, minus the ones the stored span
/// and lanes give it, both over the lattice as it paints.
typedef MakeRoomResizeGeometry = ({Offset lead, Offset extent});

/// A resize session's term targets for its own item on the lane axis: the
/// BAND, a content-space length the item's lane band adds to its stored
/// track's term while it stays laned there, and whether it VACATES that
/// track instead, both zero for an item that is not laned in a track of a
/// content-sized lane axis; and whether it JOINS a track, the prospective
/// lanes laning it in a lane-axis track whose bucket it is not in, where
/// it then holds a slot.
typedef MakeRoomResizeTerm = ({double band, bool vacates, bool joins});

/// The geometry or the term targets of a resize session's item [id] under
/// [prospective] and the dry run's [assignment], null when the dry run
/// did not lane it.
typedef MakeRoomResizeTargets<T> =
    T Function(
      int id,
      BoardSpan prospective,
      ({int lane, int laneCount, int laneSpan})? assignment,
    );

/// What a SNAP discarded: the clock left on the unsnapped motion it
/// dropped, and the make-room curve's tail from where that motion stood,
/// so a continuation runs the rest of the same ramp. Published by every
/// snap arm, null when the snap discarded nothing unsnapped.
typedef MakeRoomHandOff = ({Duration remaining, Curve curve});

/// The TAIL of a curve from [_from]: maps `[0, 1]` onto the curve's
/// `[from, 1]` segment, renormalised, so a motion interrupted at [_from]
/// and re-run on this curve over its remaining time traces what the
/// uninterrupted curve would have, with no velocity kink at the join. A
/// curve sitting exactly at 1 by [_from] has no tail and reports 1. A
/// curve ABOVE 1 at [_from] (an overshoot, `Curves.easeOutBack` past its
/// midpoint) has a NEGATIVE span, and the division renormalises that
/// segment from above 1 back down to 1; treating it as "no tail" would
/// report 1 at every clock and step the continuation to rest.
///
/// CLAMPED TO `[0, 1]`. The hand-off continues EVERY discarded motion on
/// this one tail, the earliest clock's, and the renormalisation is exact
/// only for a motion on that clock. For one on a later clock, under a
/// curve that leaves `[0, 1]` in the segment, a small span (the curve
/// near 1 at [_from]) multiplies its residual: a neighbour settling back
/// from an overshoot was carried several times its residual past its
/// rest. Clamped, a continuation approaches its rest from where it
/// painted and never passes it, whatever clock it was on. Inside
/// `[0, 1]` nothing changes; the motion on the earliest clock loses only
/// the part of its own overshoot beyond its rest or beyond where it
/// painted.
class _CurveTail extends Curve {
  const _CurveTail(this._inner, this._from);

  final Curve _inner;
  final double _from;

  @override
  double transformInternal(double t) {
    final at = _inner.transform(_from);
    final span = 1.0 - at;
    if (span.abs() <= 1e-9) {
      return 1.0;
    }
    final value = (_inner.transform(_from + (1.0 - _from) * t) - at) / span;
    return value.clamp(0.0, 1.0);
  }
}

/// A HELD per-axis value, in content space: an EXTENT preview, which
/// paint adds to the item's extent, or a resized item's LEAD, which paint
/// adds to its lead, so a resized block follows the finger and a
/// displaced neighbour takes its prospective slice while the model stays
/// unwritten.
///
/// Zero means this entry is CLOSING and is removed when it settles, the
/// rule its sibling below uses.
class _HeldAxes {
  _HeldAxes({
    required this.target,
    required this.from,
    required this.snapped,
  });

  Offset target;
  Offset from;
  bool snapped;
  double t = 0.0;
}

/// A HELD single value: a gap offset or a resized item's band, both
/// content-space lengths on the lane axis, or a resized item's vacate, a
/// unitless share.
class _HeldOffset {
  _HeldOffset({
    required this.target,
    required this.from,
    required this.snapped,
  });

  /// The held value. Zero means this entry is CLOSING and is removed when
  /// it settles.
  double target;

  /// The value at clock 0, for a re-target that composes from where the
  /// item currently paints.
  double from;

  /// A snapped entry sits at its target with no motion.
  bool snapped;

  /// The 0-to-1 animation clock, advanced by tick deltas.
  double t = 0.0;
}

/// A prospective LANE OCCUPANCY on one lane-axis track, identity
/// `(the track it is filed under, lane)`. It contributes
/// `(lane + value) * laneExtent` to that track's cluster term, the
/// enter/exit formula with [t]'s curved value in the role of progress.
///
/// No slot ever VACATES: nothing creates one at an item's stored
/// `(track, lane)`, so a slot at target 0 is always one that is CLOSING.
class _Slot {
  _Slot({
    required this.lane,
    required this.target,
    required this.from,
    required this.snapped,
  });

  final int lane;

  /// Zero means this slot is CLOSING and is removed when it settles.
  double target;

  double from;

  bool snapped;

  /// The 0-to-1 animation clock, advanced by tick deltas.
  double t = 0.0;
}

/// Owns the held gap offsets, their one ticker, and the two
/// family-declaring sites `previewGap` and `releasePreview`.
class MakeRoomEngine {
  MakeRoomEngine({
    required TickerProvider vsync,
    required BoardAnimationStyle Function() styleOf,
    required void Function() notifyNow,
    required void Function() notifyCoalesced,
    required Axis? Function() laneAxisOf,
    required Map<int, ({int lane, int laneCount, int laneSpan})> Function(
      int draggedId,
      BoardSpan prospective,
    )
    dryRunOf,
    required double Function(int id, int lane, int laneCount) laneOriginOfId,
    required Offset Function(
      int id,
      BoardSpan? prospective,
      ({int lane, int laneCount, int laneSpan})? assignment,
    )
    prospectiveExtentOf,
    required int Function(int id) laneOfId,
    required int Function(int id) laneCountOfId,
    MakeRoomResizeTargets<MakeRoomResizeGeometry>? resizeGeometryOf,
    MakeRoomResizeTargets<MakeRoomResizeTerm>? resizeTermOf,
  }) : _styleOf = styleOf,
       _notifyNow = notifyNow,
       _notifyCoalesced = notifyCoalesced,
       _laneAxisOf = laneAxisOf,
       _dryRunOf = dryRunOf,
       _laneOriginOfId = laneOriginOfId,
       _prospectiveExtentOf = prospectiveExtentOf,
       _laneOfId = laneOfId,
       _laneCountOfId = laneCountOfId,
       _resizeGeometryOf = resizeGeometryOf,
       _resizeTermOf = resizeTermOf {
    _ticker = vsync.createTicker(_tick);
  }

  final BoardAnimationStyle Function() _styleOf;

  /// The UNCOALESCED dispatch. Load-bearing on both snap arms: a snapped
  /// install starts no ticker, so without this notify nothing repaints
  /// and a gap past the admitted bound opens over children that were
  /// never built. The tick uses it for the SETTLE only.
  final void Function() _notifyNow;

  /// The ordinary per-tick dispatch, coalesced with every other source
  /// ticking in the same frame; see the slide engine's field of the same
  /// name. A tick that closed no entry carries no ordering contract.
  final void Function() _notifyCoalesced;

  final Axis? Function() _laneAxisOf;
  final Map<int, ({int lane, int laneCount, int laneSpan})> Function(
    int draggedId,
    BoardSpan prospective,
  )
  _dryRunOf;
  final double Function(int id, int lane, int laneCount) _laneOriginOfId;

  /// The EXTENT the geometry rule would give an id under a prospective
  /// span and lane assignment, minus the one it gives it now. The
  /// controller answers, that rule being its own; a null assignment
  /// means the dry run did not lane the id, and a null span means the
  /// id's own stored span, which is what a neighbour's install passes.
  final Offset Function(
    int id,
    BoardSpan? prospective,
    ({int lane, int laneCount, int laneSpan})? assignment,
  )
  _prospectiveExtentOf;
  final int Function(int id) _laneOfId;
  final int Function(int id) _laneCountOfId;

  /// The two resize callbacks. A RESIZE session holds its lead and its
  /// term only when both are given; without them its extent comes from
  /// [_prospectiveExtentOf] and it holds nothing else.
  final MakeRoomResizeTargets<MakeRoomResizeGeometry>? _resizeGeometryOf;
  final MakeRoomResizeTargets<MakeRoomResizeTerm>? _resizeTermOf;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  final Map<int, _HeldOffset> _held = <int, _HeldOffset>{};

  /// One entry per id whose extent the preview holds: a resize session's
  /// own item and every dry-run member whose slice would change. Empty
  /// on a content-sized lane axis for a pure lane change, where every
  /// slice is the one lane extent and the delta is exactly zero.
  final Map<int, _HeldAxes> _heldExtent = <int, _HeldAxes>{};

  /// A resize session's item's LEAD, per axis: paint only, beside its
  /// extent. Read by [deltaOf] only while non-empty.
  final Map<int, _HeldAxes> _heldLead = <int, _HeldAxes>{};

  /// A resize session's item's BAND on the lane axis: term only. Read by
  /// [termDeltaOf] only while non-empty.
  final Map<int, _HeldOffset> _heldBand = <int, _HeldOffset>{};

  /// A resize session's item's VACATE, `0` to `1`: term only, the share
  /// of its stored track's term it has given up. Read by [vacatedOf] only
  /// while non-empty.
  final Map<int, _HeldOffset> _heldVacate = <int, _HeldOffset>{};

  /// The SESSION: the dragged id of the last install, and for a resize
  /// given both callbacks its SOURCE, the prospective span and the dry
  /// run's assignment the refreshes re-derive its targets from. A source
  /// stands exactly while [_resizeSpan] is non-null; a release and a
  /// clear of the id tear the session down.
  int? _sessionId;
  BoardSpan? _resizeSpan;
  ({int lane, int laneCount, int laneSpan})? _resizeAssignment;

  /// Debug-only: the lookups of [_heldLead], [_heldBand] and
  /// [_heldVacate] that [deltaOf], [termDeltaOf] and [vacatedOf] have
  /// made since tests last assigned it 0. A field on an unexported class,
  /// as `Fenwick.debugOpCount` is: a reader that looks up an empty map
  /// paints and sizes what one that does not paints and sizes, so no
  /// widget-level seam observes the cost.
  int debugResizeHoldReadCount = 0;

  /// KEYED BY LANE-AXIS TRACK, and an emptied bucket is removed, so
  /// `_slots.isEmpty` is exactly "no slot exists". The sizing walk asks
  /// for one track at a time, once per track per obtain round per
  /// correction pass, so a flat list would be a full scan per ask.
  final Map<int, List<_Slot>> _slots = <int, List<_Slot>>{};

  /// The slots' lifecycle key, and it carries no other duty: the id of
  /// the session that owns the slots, a lifted item's or a resized item's
  /// that joins a track. ONE RULE governs it and it is total: non-null
  /// exactly while [_slots] is non-empty.
  int? _liftedId;

  int _generation = 0;
  int _snapGeneration = 0;

  Curve _curve = Curves.linear;

  /// The CAPTURED clock the offsets, extents and slots run on, resolved
  /// beside [_curve] at the two declaring sites from the caller's
  /// argument or the live spec and adopted through [_adoptClock]. Its two
  /// timing readers, the tick and the snap's hand-off, resolve it through
  /// [BoardAnimationTiming.durationFor]: an off live family still
  /// dominates it, as the kill switch does at the install, and a captured
  /// clock that is not positive is off as well.
  Duration _duration = Duration.zero;

  /// Makes [curve] and [duration] the clock every entry runs on.
  ///
  /// ONE clock serves every entry, so replacing it re-reads each entry
  /// still in motion on a curve and a duration it never ran on: its value
  /// jumps, and its remainder runs on the new clock from the old one's
  /// position. On a CHANGE, every offset, extent and slot still in motion
  /// is therefore re-based first, its current value on the old clock
  /// becoming its `from` and its clock restarting at 0, so it paints
  /// where it did and finishes on the new one. An unchanged clock touches
  /// nothing, which the idempotent install depends on.
  void _adoptClock(Curve curve, Duration duration) {
    if (curve == _curve && duration == _duration) {
      return;
    }
    for (final map in <Map<int, _HeldOffset>>[_held, _heldBand, _heldVacate]) {
      for (final entry in map.values) {
        if (!entry.snapped && entry.t < 1.0) {
          entry
            ..from = _valueOf(entry)
            ..t = 0.0;
        }
      }
    }
    for (final map in <Map<int, _HeldAxes>>[_heldExtent, _heldLead]) {
      for (final entry in map.values) {
        if (!entry.snapped && entry.t < 1.0) {
          entry
            ..from = _axesValueOf(entry)
            ..t = 0.0;
        }
      }
    }
    for (final slots in _slots.values) {
      for (final slot in slots) {
        if (!slot.snapped && slot.t < 1.0) {
          slot
            ..from = _valueOfSlot(slot)
            ..t = 0.0;
        }
      }
    }
    _curve = curve;
    _duration = duration;
  }

  /// Whether a held paint offset stands: a gap offset or a resized item's
  /// lead.
  bool get hasActive {
    return _held.isNotEmpty || _heldLead.isNotEmpty;
  }

  /// Whether an extent preview stands at all. The render lays out on a
  /// generation change while one does, on any axis: an extent changes
  /// layout wherever it is, unlike a gap.
  bool get hasHeldExtent {
    return _heldExtent.isNotEmpty;
  }

  /// Whether an extent preview is MOVING. Only then is it
  /// layout-driving; a settled one is a constant and would otherwise
  /// lay the board out per tick for a whole drag.
  bool get hasExtentMotion {
    return _axesMoving(_heldExtent);
  }

  /// The held extent preview for [id], zero for no entry.
  Offset extentDeltaOf(int id) {
    final entry = _heldExtent[id];
    if (entry == null) {
      return Offset.zero;
    }
    return _axesValueOf(entry);
  }

  /// Any offset, extent, lead, band, vacate or slot unsnapped with clock
  /// below 1.
  bool get hasMotion {
    if (_axesMoving(_heldExtent) ||
        _axesMoving(_heldLead) ||
        _offsetsMoving(_held) ||
        _offsetsMoving(_heldBand) ||
        _offsetsMoving(_heldVacate)) {
      return true;
    }
    for (final slots in _slots.values) {
      for (final slot in slots) {
        if (!slot.snapped && slot.t < 1.0) {
          return true;
        }
      }
    }
    return false;
  }

  /// Bumped by [previewGap], [releasePreview] and [clearForId]. The
  /// render lays out when it differs from the value it last laid out
  /// against.
  int get generation {
    return _generation;
  }

  /// Bumped exactly when a snap arm publishes a non-null [handOff]: it
  /// discarded an offset or a slot that was unsnapped, mid-clock, and
  /// moving (`from != target`). An offset counts as much as a slot,
  /// because the discard no longer steps anything: the drag layer
  /// continues the item's painted position from where it was, on
  /// [handOff]'s clock, and the render's hand-off arm continues the
  /// track's term on the same clock, so the two must move together.
  /// NEVER by [clearForId], which is a removal and not a snap.
  int get snapGeneration {
    return _snapGeneration;
  }

  /// The hand-off the LAST snap published; see [MakeRoomHandOff].
  MakeRoomHandOff? get handOff {
    return _handOff;
  }

  MakeRoomHandOff? _handOff;

  /// Folds one discarded entry's clock into the running minimum [minT]:
  /// an entry that was unsnapped, below clock 1 and [moving] (its `from`
  /// differs from its target, compared in the entry's own type) had
  /// motion left, and the EARLIEST such clock is the one the hand-off
  /// continues from. Anything else folds to [minT] unchanged.
  double? _foldClock(double? minT, bool snapped, double t, bool moving) {
    if (snapped || t >= 1.0 || !moving) {
      return minT;
    }
    return minT == null || t < minT ? t : minT;
  }

  /// Publishes a snap's hand-off from the folded clock: the time left on
  /// the family's duration and the curve's tail from there, plus the
  /// snap generation bump the render's hand-off arm keys on. A null
  /// [minT] publishes null, so a stale record never outlives the snap
  /// that produced it.
  void _publishSnap(double? minT) {
    if (minT == null) {
      _handOff = null;
      return;
    }
    // The captured clock through the resolver: an off family, or a
    // captured clock that is not positive, publishes no time at all.
    final duration = _styleOf().durationFor(
      BoardAnimationFamily.makeRoom,
      explicit: _duration,
    );
    _handOff = (
      remaining: duration * (1.0 - minT),
      curve: _CurveTail(_curve, minT),
    );
    _snapGeneration += 1;
  }

  /// The id whose prospective occupancy the slots carry, a lifted item's
  /// or a resized item's that joins a track, or null.
  int? get liftedId {
    return _liftedId;
  }

  /// The slots on lane-axis track [track]; `value` is in `[0, 1]`.
  Iterable<({int lane, double value})> slotsOn(int track) {
    final slots = _slots[track];
    if (slots == null) {
      return const <({int lane, double value})>[];
    }
    return slots.map((slot) {
      return (lane: slot.lane, value: _valueOfSlot(slot));
    });
  }

  /// The ids holding entries, offset, extent or lead, for the composed
  /// per-id bound and the commit's painted-truth capture. A lane-0
  /// neighbour holds a zero offset and a non-zero extent, so an
  /// offset-only enumeration would leave it out of both; a resized item
  /// can hold a lead alone. A band and a vacate have no paint half. The
  /// leads are appended only while one stands, so a board with no resize
  /// hold builds what it would without them.
  Iterable<int> get activeIds {
    final held = _held.keys.followedBy(
      _heldExtent.keys.where((id) {
        return !_held.containsKey(id);
      }),
    );
    if (_heldLead.isEmpty) {
      return held;
    }
    return held.followedBy(
      _heldLead.keys.where((id) {
        return !_held.containsKey(id) && !_heldExtent.containsKey(id);
      }),
    );
  }

  double _valueOf(_HeldOffset entry) {
    if (entry.snapped) {
      return entry.target;
    }
    return entry.from +
        (entry.target - entry.from) *
            _curve.transform(entry.t.clamp(0.0, 1.0));
  }

  /// A held per-axis value's current value, in content space per axis.
  Offset _axesValueOf(_HeldAxes entry) {
    if (entry.snapped) {
      return entry.target;
    }
    final eased = _curve.transform(entry.t.clamp(0.0, 1.0));
    return entry.from + (entry.target - entry.from) * eased;
  }

  double _valueOfSlot(_Slot slot) {
    if (slot.snapped) {
      return slot.target;
    }
    return slot.from +
        (slot.target - slot.from) * _curve.transform(slot.t.clamp(0.0, 1.0));
  }

  /// Drops every slot and the lifecycle key with them, folding each
  /// slot's clock into [minT] for the caller to publish. The callers are
  /// a LIFTED first install for a DIFFERENT id, the snap release arm and
  /// [clearForId], which discards the fold.
  double? _discardSlots(double? minT) {
    for (final slots in _slots.values) {
      for (final slot in slots) {
        minT = _foldClock(minT, slot.snapped, slot.t, slot.from != slot.target);
      }
    }
    _slots.clear();
    _liftedId = null;
    return minT;
  }

  /// Re-targets one slot, LEAVING IT UNTOUCHED when its target already
  /// equals [target] and the install is not a snap. That idempotence is
  /// what lets a closing slot decay on the schedule it started on, so
  /// `_tick` can retire it under a per-frame re-resolve.
  ///
  /// A SNAP folds the slot's clock into [minT] BEFORE the re-target
  /// resets it: the snap tail reads the flag after this has set it, so
  /// the discard has to be folded from here or the hand-off never learns
  /// of it. Returns the fold.
  double? _retargetSlot(_Slot slot, double target, bool snap, double? minT) {
    if (!snap && slot.target == target) {
      return minT;
    }
    if (snap) {
      minT = _foldClock(minT, slot.snapped, slot.t, slot.from != slot.target);
    }
    final current = _valueOfSlot(slot);
    slot
      ..from = snap ? target : current
      ..target = target
      ..snapped = snap
      ..t = 0.0;
    return minT;
  }

  /// Re-targets one held offset in place, by [_retargetSlot]'s rule: LEFT
  /// UNTOUCHED when its target already equals [target] and the call is
  /// not a snap. A free or fraction snap re-enters [previewGap] on every
  /// frame of the resize it caused, where restarting the clock would keep
  /// a gap from ever settling; a drag releases again at its teardown,
  /// where a restart would end the close one duration after that release
  /// instead of on the first release's schedule. A SNAP always
  /// re-targets, since the kill switch dominates
  /// a captured value, and folds the entry's clock into [minT] first.
  /// [target] is a content-space offset on the lane axis. Returns the
  /// fold.
  double? _retargetOffset(
    _HeldOffset entry,
    double target,
    bool snap,
    double? minT,
  ) {
    if (!snap && entry.target == target) {
      return minT;
    }
    if (snap) {
      minT = _foldClock(
        minT,
        entry.snapped,
        entry.t,
        entry.from != entry.target,
      );
    }
    final current = _valueOf(entry);
    entry
      ..from = snap ? target : current
      ..target = target
      ..snapped = snap
      ..t = 0.0;
    return minT;
  }

  /// [_retargetOffset] for a held per-axis value; [target] is a
  /// content-space length per axis, as [extentDeltaOf] answers.
  double? _retargetAxes(
    _HeldAxes entry,
    Offset target,
    bool snap,
    double? minT,
  ) {
    if (!snap && entry.target == target) {
      return minT;
    }
    if (snap) {
      minT = _foldClock(
        minT,
        entry.snapped,
        entry.t,
        entry.from != entry.target,
      );
    }
    final current = _axesValueOf(entry);
    entry
      ..from = snap ? target : current
      ..target = target
      ..snapped = snap
      ..t = 0.0;
    return minT;
  }

  /// An install's write of [id]'s entry in [map]: a re-target of the
  /// entry it holds, or a new entry for a non-zero [target], opening from
  /// zero on a live install and landed on a snapped one. Returns the
  /// fold.
  double? _installAxes(
    Map<int, _HeldAxes> map,
    int id,
    Offset target,
    bool snap,
    double? minT,
  ) {
    final existing = map[id];
    if (existing != null) {
      return _retargetAxes(existing, target, snap, minT);
    }
    if (target != Offset.zero) {
      map[id] = _HeldAxes(
        target: target,
        from: snap ? target : Offset.zero,
        snapped: snap,
      );
    }
    return minT;
  }

  /// [_installAxes] for a held single value.
  double? _installOffset(
    Map<int, _HeldOffset> map,
    int id,
    double target,
    bool snap,
    double? minT,
  ) {
    final existing = map[id];
    if (existing != null) {
      return _retargetOffset(existing, target, snap, minT);
    }
    if (target != 0.0) {
      map[id] = _HeldOffset(
        target: target,
        from: snap ? target : 0.0,
        snapped: snap,
      );
    }
    return minT;
  }

  /// The held PAINT delta for [id], both axes, zero for no entry: its gap
  /// offset on the lane axis plus, for a resized item, its lead on both.
  /// [_heldLead] is looked up only while it is non-empty.
  Offset deltaOf(int id) {
    var delta = Offset.zero;
    final entry = _held[id];
    if (entry != null) {
      final axis = _laneAxisOf();
      if (axis != null) {
        final value = _valueOf(entry);
        delta = axis == Axis.vertical ? Offset(0.0, value) : Offset(value, 0.0);
      }
    }
    if (_heldLead.isNotEmpty) {
      debugResizeHoldReadCount += 1;
      final lead = _heldLead[id];
      if (lead != null) {
        delta += _axesValueOf(lead);
      }
    }
    return delta;
  }

  /// The held TERM delta for [id] on the lane axis, zero for no entry or
  /// with no lane axis: its gap offset plus, for a resized item, its
  /// band. What the sizing term adds to a member's ceiling, which a
  /// resized item's lead never reaches. [_heldBand] is looked up only
  /// while it is non-empty.
  Offset termDeltaOf(int id) {
    final entry = _held[id];
    _HeldOffset? band;
    if (_heldBand.isNotEmpty) {
      debugResizeHoldReadCount += 1;
      band = _heldBand[id];
    }
    if (entry == null && band == null) {
      return Offset.zero;
    }
    final axis = _laneAxisOf();
    if (axis == null) {
      return Offset.zero;
    }
    final value =
        (entry == null ? 0.0 : _valueOf(entry)) +
        (band == null ? 0.0 : _valueOf(band));
    return axis == Axis.vertical ? Offset(0.0, value) : Offset(value, 0.0);
  }

  /// The share of its stored track's term a resized item has given up,
  /// `0` to `1`, zero for no entry. [_heldVacate] is looked up only while
  /// it is non-empty.
  double vacatedOf(int id) {
    if (_heldVacate.isEmpty) {
      return 0.0;
    }
    debugResizeHoldReadCount += 1;
    final entry = _heldVacate[id];
    return entry == null ? 0.0 : _valueOf(entry);
  }

  /// Re-derives the resize session's BAND and VACATE from its source, the
  /// lanes having resolved; see [_rebaseOffset]. Returns at once without
  /// a source.
  void refreshResizeTerm() {
    final id = _sessionId;
    final span = _resizeSpan;
    final termOf = _resizeTermOf;
    if (id == null || span == null || termOf == null) {
      return;
    }
    final term = termOf(id, span, _resizeAssignment);
    _rebaseOffset(_heldBand, id, term.band);
    _rebaseOffset(_heldVacate, id, term.vacates ? 1.0 : 0.0);
  }

  /// Re-derives the resize session's LEAD and EXTENT from its source, over
  /// the lattice as it paints; see [_rebaseOffset]. Returns at once
  /// without a source.
  void refreshResizeGeometry() {
    final id = _sessionId;
    final span = _resizeSpan;
    final geometryOf = _resizeGeometryOf;
    if (id == null || span == null || geometryOf == null) {
      return;
    }
    final geometry = geometryOf(id, span, _resizeAssignment);
    _rebaseAxes(_heldLead, id, geometry.lead);
    _rebaseAxes(_heldExtent, id, geometry.extent);
  }

  /// RE-BASES [id]'s entry in [map] onto a re-derived [target]: the target
  /// and the `from` move by the same difference, so the entry keeps its
  /// clock and paints over the stored span's new geometry where it
  /// painted over the old one, moved only by the change in the target. A
  /// missing entry counts as one at rest at zero, so a non-zero target
  /// creates it at rest; an entry at rest whose target becomes zero is
  /// removed, and one in motion closes on its clock, by the rule that
  /// zero means closing. Notifies nothing, bumps no generation and
  /// leaves the ticker alone, so it is safe inside a layout.
  void _rebaseOffset(Map<int, _HeldOffset> map, int id, double target) {
    final entry = map[id];
    if (entry == null) {
      if (target != 0.0) {
        map[id] = _HeldOffset(target: target, from: target, snapped: false)
          ..t = 1.0;
      }
      return;
    }
    if (entry.target == target) {
      return;
    }
    if (target == 0.0 && (entry.snapped || entry.t >= 1.0)) {
      map.remove(id);
      return;
    }
    entry
      ..from = entry.from + (target - entry.target)
      ..target = target;
  }

  /// [_rebaseOffset] for a held per-axis value.
  void _rebaseAxes(Map<int, _HeldAxes> map, int id, Offset target) {
    final entry = map[id];
    if (entry == null) {
      if (target != Offset.zero) {
        map[id] = _HeldAxes(target: target, from: target, snapped: false)
          ..t = 1.0;
      }
      return;
    }
    if (entry.target == target) {
      return;
    }
    if (target == Offset.zero && (entry.snapped || entry.t >= 1.0)) {
      map.remove(id);
      return;
    }
    entry
      ..from = entry.from + (target - entry.target)
      ..target = target;
  }

  /// Ends the session: its id and its source.
  void _clearSession() {
    _sessionId = null;
    _resizeSpan = null;
    _resizeAssignment = null;
  }

  /// Opens (or re-targets) the gap for a drag of [draggedId] resolving to
  /// [prospective]. Never refuses: under an off family, or with a
  /// [duration] that is not positive, it INSTALLS AND SNAPS, because the
  /// gap IS the target state, and an off family removes its motion, not
  /// the gap. The snap flag is the kill switch, resolved here through
  /// [BoardAnimationTiming.isOff], at one of the family's two declaring
  /// sites; [duration] and [curve] are a session's captured values and
  /// an off family dominates them.
  void previewGap({
    required int draggedId,
    required BoardSpan prospective,
    bool lifted = false,
    Duration? duration,
    Curve? curve,
  }) {
    final laneAxis = _laneAxisOf();
    final style = _styleOf();
    final spec = style.effectiveMakeRoom;
    final resolved = duration ?? spec.duration;
    final snap = style.isOff(BoardAnimationFamily.makeRoom, explicit: duration);
    _adoptClock(curve ?? spec.curve, resolved);
    // The dry run needs lane geometry; without it nothing is laned and
    // no gap exists to open, but the EXTENT preview below still does.
    final dry = laneAxis == null
        ? const <int, ({int lane, int laneCount, int laneSpan})>{}
        : _dryRunOf(draggedId, prospective);
    // THE SESSION. A RESIZE given both callbacks records its SOURCE, the
    // span and the dry run's assignment its targets are re-derived from
    // every layout; any other install records none, so no refresh runs
    // for it. The discriminator is the session's argument, NOT the
    // dragging bit: that bit is set for every session and carries no
    // kind.
    final geometryOf = _resizeGeometryOf;
    final termOf = _resizeTermOf;
    final resizes = !lifted && geometryOf != null && termOf != null;
    final assignment = dry[draggedId];
    _sessionId = draggedId;
    _resizeSpan = resizes ? prospective : null;
    _resizeAssignment = resizes ? assignment : null;
    final geometry = resizes
        ? geometryOf(draggedId, prospective, assignment)
        : null;
    final term = resizes ? termOf(draggedId, prospective, assignment) : null;
    // The hand-off fold: the earliest clock among everything this call
    // discards mid-motion. A snapped install discards every entry it
    // replaces and every slot it snaps; a live install discards only a
    // previous session's closing slots.
    double? minT;
    // THE EXTENT PREVIEW. Three sources of targets, one install loop:
    // a RESIZE session's own item under its prospective span (a move
    // changes no span extent, and a LIFTED item paints as the proxy);
    // every other dry-run member under its OWN span and prospective lane
    // count, which is what shrinks or widens a neighbour's slice on a
    // fixed lane axis; and every held entry neither re-targeted, which
    // closes back to zero. Re-targeted from where it currently paints,
    // and left alone for an unchanged target, the two rules the offsets
    // use and for the same reasons. BEFORE the lane-axis gate: an extent
    // needs no lane geometry, and on a board with none it is the whole
    // of the drag's in-place feedback. The resized item's LEAD and TERM
    // entries follow the same rules.
    final extentTargets = <int, Offset>{};
    if (!lifted) {
      extentTargets[draggedId] =
          geometry?.extent ??
          _prospectiveExtentOf(draggedId, prospective, assignment);
    }
    dry.forEach((id, assignment) {
      if (id == draggedId) {
        return;
      }
      extentTargets[id] = _prospectiveExtentOf(id, null, assignment);
    });
    for (final id in _heldExtent.keys) {
      extentTargets.putIfAbsent(id, () {
        return Offset.zero;
      });
    }
    extentTargets.forEach((id, extent) {
      minT = _installAxes(_heldExtent, id, extent, snap, minT);
    });
    final leadTargets = <int, Offset>{
      if (geometry != null) draggedId: geometry.lead,
    };
    for (final id in _heldLead.keys) {
      leadTargets.putIfAbsent(id, () {
        return Offset.zero;
      });
    }
    leadTargets.forEach((id, lead) {
      minT = _installAxes(_heldLead, id, lead, snap, minT);
    });
    final bandTargets = <int, double>{
      if (term != null) draggedId: term.band,
    };
    final vacateTargets = <int, double>{
      if (term != null) draggedId: term.vacates ? 1.0 : 0.0,
    };
    for (final id in _heldBand.keys) {
      bandTargets.putIfAbsent(id, () {
        return 0.0;
      });
    }
    for (final id in _heldVacate.keys) {
      vacateTargets.putIfAbsent(id, () {
        return 0.0;
      });
    }
    bandTargets.forEach((id, band) {
      minT = _installOffset(_heldBand, id, band, snap, minT);
    });
    vacateTargets.forEach((id, vacate) {
      minT = _installOffset(_heldVacate, id, vacate, snap, minT);
    });
    if (laneAxis == null) {
      // No lane geometry exists to open a gap in; the extent and lead
      // preview above is the whole of the in-place feedback on such a
      // board, and the drag proxy is the rest of it. The fold is
      // discarded unpublished here, as it always was on this branch: the
      // case is a restyle to off mid-drag on a board with no lanes.
      if (snap) {
        _removeClosed();
      }
      _generation += 1;
      if (snap) {
        _notifyNow();
      } else {
        _ensureTicking();
      }
      return;
    }
    final targets = <int, double>{};
    dry.forEach((id, assignment) {
      if (id == draggedId) {
        // The dragged item holds no offset: a LIFTED (moved) one paints
        // as the proxy, not as a gap, and a RESIZED one holds its lead
        // in [_heldLead], over the geometry its stored span is given.
        return;
      }
      final target =
          _laneOriginOfId(id, assignment.lane, assignment.laneCount) -
          _laneOriginOfId(id, _laneOfId(id), _laneCountOfId(id));
      if (target != 0.0) {
        targets[id] = target;
      }
    });
    // Entries not re-targeted close back to zero.
    for (final id in _held.keys) {
      targets.putIfAbsent(id, () {
        return 0.0;
      });
    }
    targets.forEach((id, target) {
      minT = _installOffset(_held, id, target, snap, minT);
    });
    // THE SLOTS: a LIFTED item's, and a RESIZED item's while its preview
    // lanes it in a track it is not laned in; an install by the slots'
    // own session runs the block too, so a resize that stops joining
    // closes its slot by the same re-target.
    final joins = term?.joins ?? false;
    if (lifted || joins || _liftedId == draggedId) {
      if (_liftedId != null && _liftedId != draggedId) {
        // A PREVIOUS session's item, whose closing slot is still ramping
        // down. Snap-drop it, or its phantom occupancy outlives the
        // session that owned it, on a track it never reached. An install
        // for the SAME id takes the re-target path below.
        minT = _discardSlots(minT);
      }
      // Both halves of the desired slot's identity come from inputs this
      // method already has: the TRACK from `prospective` on the lane
      // axis, the LANE from the dry run, present exactly when the run
      // laned the dragged id. A resize that no longer joins desires none.
      final prospectiveTrack = trackIndexOf(prospective.startTrackOn(laneAxis));
      final desiredLane = lifted || joins ? dry[draggedId]?.lane : null;
      _slots.forEach((track, slots) {
        for (final slot in slots) {
          final desired =
              desiredLane != null &&
                  track == prospectiveTrack &&
                  slot.lane == desiredLane
              ? 1.0
              : 0.0;
          minT = _retargetSlot(slot, desired, snap, minT);
        }
      });
      if (desiredLane != null) {
        final slots = _slots.putIfAbsent(prospectiveTrack, () {
          return <_Slot>[];
        });
        var held = false;
        for (final slot in slots) {
          if (slot.lane == desiredLane) {
            held = true;
            break;
          }
        }
        if (!held) {
          slots.add(
            _Slot(lane: desiredLane, target: 1.0, from: 0.0, snapped: snap),
          );
        }
      }
      _liftedId = _slots.isEmpty ? null : draggedId;
    }
    // BEFORE either tail: the snap arm ends in a notify and a return, so
    // a bump written after it would never run on a snapped install, and
    // the snapped install is the one the router's generation arm exists
    // for.
    _generation += 1;
    if (snap) {
      _removeClosed();
      minT = _snapSlots(minT);
      _publishSnap(minT);
      _notifyNow();
      return;
    }
    if (minT != null) {
      // Only a discard publishes on the live arm: a live install that
      // discarded nothing must leave the last snap's record standing
      // for the layout that has not yet read it.
      _publishSnap(minT);
    }
    _ensureTicking();
  }

  /// The install's snap tail for every held entry: one a snap re-targeted
  /// to zero is closed, and goes.
  void _removeClosed() {
    for (final map in <Map<int, _HeldOffset>>[_held, _heldBand, _heldVacate]) {
      map.removeWhere((id, entry) {
        return entry.target == 0.0;
      });
    }
    for (final map in <Map<int, _HeldAxes>>[_heldExtent, _heldLead]) {
      map.removeWhere((id, entry) {
        return entry.target == Offset.zero;
      });
    }
  }

  /// The install's snap tail for slots: every slot lands on its target,
  /// and a slot at 0 is removed. Either lands a slot that was still
  /// mid-motion without ramping it there, so both fold into [minT].
  double? _snapSlots(double? minT) {
    _slots.removeWhere((track, slots) {
      slots.removeWhere((slot) {
        minT = _foldClock(minT, slot.snapped, slot.t, slot.from != slot.target);
        if (slot.target != 0.0) {
          slot.snapped = true;
          return false;
        }
        return true;
      });
      return slots.isEmpty;
    });
    if (_slots.isEmpty) {
      _liftedId = null;
    }
    return minT;
  }

  /// Closes every held offset. The release side reads the SAME kill
  /// switch as the install, so an off-family drag's gap opens and closes
  /// instantly as a pair. A live release leaves an offset, an
  /// extent or a slot that is already closing on the schedule it started
  /// on, so a second release on the same clock changes no entry. Both
  /// arms end the session, so no refresh re-derives a target the release
  /// closed.
  void releasePreview({Duration? duration, Curve? curve}) {
    // EVERY COLLECTION, not one: a slot-only hover holds no offset at
    // all, and an `_held`-only guard would return without clearing the
    // slots, leaving the target track's phantom occupancy standing for
    // the rest of the board's life; a resize source left standing would
    // re-open its targets on the next layout.
    if (_held.isEmpty &&
        _slots.isEmpty &&
        _liftedId == null &&
        _heldExtent.isEmpty &&
        _heldLead.isEmpty &&
        _heldBand.isEmpty &&
        _heldVacate.isEmpty &&
        _resizeSpan == null) {
      _clearSession();
      return;
    }
    final style = _styleOf();
    final spec = style.effectiveMakeRoom;
    final resolved = duration ?? spec.duration;
    final snap = style.isOff(BoardAnimationFamily.makeRoom, explicit: duration);
    if (snap) {
      // The commit's snap: fold every entry and slot it drops, so the
      // hand-off carries the clock of whatever was still moving. Under a
      // LIVE family the snap is the commit's own zero duration, not the
      // kill switch, and another session's CLOSING resize hold is no part
      // of this commit: its lead, band and vacate, and that id's closing
      // extent, stay on their clock, neither folded nor removed, so they
      // finish closing in lockstep while the commit's hand-off continues
      // only what this snap discards. Read before the session ends.
      final survivors = style.isOff(BoardAnimationFamily.makeRoom)
          ? null
          : _closingHoldsBeside(_sessionId);
      var minT = _discardOffsets(_held, null, null);
      minT = _discardOffsets(_heldBand, survivors, minT);
      minT = _discardOffsets(_heldVacate, survivors, minT);
      minT = _discardAxes(_heldLead, survivors, minT);
      minT = _discardAxes(_heldExtent, survivors, minT);
      minT = _discardSlots(minT);
      _clearSession();
      _publishSnap(minT);
      _generation += 1;
      _stopIfIdle();
      _notifyNow();
      return;
    }
    _adoptClock(curve ?? spec.curve, resolved);
    // An entry already closing keeps the schedule it started on, by the
    // idempotence rule the install applies.
    for (final map in <Map<int, _HeldOffset>>[_held, _heldBand, _heldVacate]) {
      for (final entry in map.values) {
        _retargetOffset(entry, 0.0, false, null);
      }
    }
    for (final map in <Map<int, _HeldAxes>>[_heldExtent, _heldLead]) {
      for (final entry in map.values) {
        _retargetAxes(entry, Offset.zero, false, null);
      }
    }
    _slots.forEach((track, slots) {
      for (final slot in slots) {
        _retargetSlot(slot, 0.0, false, null);
      }
    });
    if (_slots.isEmpty) {
      // The release of a session that never got a slot; otherwise the
      // key is cleared at the settle, when `_tick` removes the last one.
      _liftedId = null;
    }
    _clearSession();
    _generation += 1;
    _ensureTicking();
  }

  void clearForId(int id) {
    // THIS REMOVAL NEVER BUMPS THE SNAP GENERATION, on either branch: an
    // offset has a paint half.
    var removed = _held.remove(id) != null;
    removed = _heldExtent.remove(id) != null || removed;
    removed = _heldLead.remove(id) != null || removed;
    removed = _heldBand.remove(id) != null || removed;
    removed = _heldVacate.remove(id) != null || removed;
    if (id == _liftedId) {
      removed = removed || _slots.isNotEmpty;
      _discardSlots(null);
    }
    if (id == _sessionId) {
      // A recycled id must not have the next layout re-derive the dead
      // item's targets for its new occupant.
      _clearSession();
    }
    if (removed) {
      // Conditional: this runs on every exit release, and an
      // unconditional bump would cost a layout per settle on every board
      // with a content-sized lane axis.
      _generation += 1;
    }
    _stopIfIdle();
  }

  void _ensureTicking() {
    if (hasMotion && !_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  }

  void _stopIfIdle() {
    if (!_ticker.isActive) {
      return;
    }
    if (hasMotion) {
      return;
    }
    _ticker.stop();
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    // The captured clock, under the live family's off: a restyle to off
    // mid-gap drives every clock past 1 on this tick, and so does a
    // captured clock that is not positive.
    final durationUs = _styleOf()
        .durationFor(BoardAnimationFamily.makeRoom, explicit: _duration)
        .inMicroseconds;
    final delta = durationUs == 0
        ? double.infinity
        : dt.inMicroseconds / durationUs;
    // Every iteration runs, none short-circuited by an earlier close, and
    // all complete before the first dispatch.
    var anyClosed = _advanceAxes(_heldExtent, delta);
    anyClosed = _advanceAxes(_heldLead, delta) || anyClosed;
    anyClosed = _advanceOffsets(_held, delta) || anyClosed;
    anyClosed = _advanceOffsets(_heldBand, delta) || anyClosed;
    anyClosed = _advanceOffsets(_heldVacate, delta) || anyClosed;
    _slots.forEach((track, slots) {
      for (final slot in slots) {
        if (slot.snapped || slot.t >= 1.0) {
          continue;
        }
        slot.t += delta;
        if (slot.t >= 1.0 && slot.target == 0.0) {
          anyClosed = true;
        }
      }
    });
    if (!anyClosed) {
      // An ordinary tick: nothing closed, so nothing depends on when
      // within the frame this lands. Coalesced with every other source.
      _notifyCoalesced();
      _stopIfIdle();
      return;
    }
    // Same settle protocol as the slide engine: deltas observed at their
    // settled values before a closing entry is removed, then the
    // idle transition. Both synchronous.
    _notifyNow();
    _held.removeWhere(_offsetClosed);
    _heldBand.removeWhere(_offsetClosed);
    _heldVacate.removeWhere(_offsetClosed);
    _heldExtent.removeWhere(_axesClosed);
    _heldLead.removeWhere(_axesClosed);
    _slots.removeWhere((track, slots) {
      slots.removeWhere((slot) {
        return slot.t >= 1.0 && slot.target == 0.0;
      });
      // An emptied bucket goes, which is what keeps `_slots.isEmpty`
      // meaning "no slot exists".
      return slots.isEmpty;
    });
    if (_slots.isEmpty) {
      _liftedId = null;
    }
    _notifyNow();
    _stopIfIdle();
  }

  /// The ids other than [sessionId] holding a CLOSING lead, band or
  /// vacate: a cancelled or refused resize's hold, still on its clock.
  Set<int> _closingHoldsBeside(int? sessionId) {
    final ids = <int>{};
    _heldLead.forEach((id, entry) {
      if (id != sessionId && entry.target == Offset.zero) {
        ids.add(id);
      }
    });
    for (final map in <Map<int, _HeldOffset>>[_heldBand, _heldVacate]) {
      map.forEach((id, entry) {
        if (id != sessionId && entry.target == 0.0) {
          ids.add(id);
        }
      });
    }
    return ids;
  }

  /// The snap's discard of [map]: every entry goes, its clock folded into
  /// [minT], but a CLOSING one of an id in [keep]. Returns the fold.
  double? _discardOffsets(
    Map<int, _HeldOffset> map,
    Set<int>? keep,
    double? minT,
  ) {
    map.removeWhere((id, entry) {
      if (keep != null && entry.target == 0.0 && keep.contains(id)) {
        return false;
      }
      minT = _foldClock(minT, entry.snapped, entry.t, entry.from != entry.target);
      return true;
    });
    return minT;
  }

  /// [_discardOffsets] for held per-axis values.
  double? _discardAxes(
    Map<int, _HeldAxes> map,
    Set<int>? keep,
    double? minT,
  ) {
    map.removeWhere((id, entry) {
      if (keep != null && entry.target == Offset.zero && keep.contains(id)) {
        return false;
      }
      minT = _foldClock(minT, entry.snapped, entry.t, entry.from != entry.target);
      return true;
    });
    return minT;
  }

  /// Advances every moving entry of [map] by [delta] and answers whether
  /// one of them CLOSED on this tick.
  static bool _advanceOffsets(Map<int, _HeldOffset> map, double delta) {
    var closed = false;
    for (final entry in map.values) {
      if (entry.snapped || entry.t >= 1.0) {
        continue;
      }
      entry.t += delta;
      if (entry.t >= 1.0 && entry.target == 0.0) {
        closed = true;
      }
    }
    return closed;
  }

  /// [_advanceOffsets] for held per-axis values.
  static bool _advanceAxes(Map<int, _HeldAxes> map, double delta) {
    var closed = false;
    for (final entry in map.values) {
      if (entry.snapped || entry.t >= 1.0) {
        continue;
      }
      entry.t += delta;
      if (entry.t >= 1.0 && entry.target == Offset.zero) {
        closed = true;
      }
    }
    return closed;
  }

  /// Whether [entry] closed and settled, so the tick removes it.
  static bool _offsetClosed(int id, _HeldOffset entry) {
    return entry.t >= 1.0 && entry.target == 0.0;
  }

  /// [_offsetClosed] for a held per-axis value.
  static bool _axesClosed(int id, _HeldAxes entry) {
    return entry.t >= 1.0 && entry.target == Offset.zero;
  }

  /// Whether an entry of [map] is unsnapped with clock below 1.
  static bool _offsetsMoving(Map<int, _HeldOffset> map) {
    for (final entry in map.values) {
      if (!entry.snapped && entry.t < 1.0) {
        return true;
      }
    }
    return false;
  }

  /// [_offsetsMoving] for held per-axis values.
  static bool _axesMoving(Map<int, _HeldAxes> map) {
    for (final entry in map.values) {
      if (!entry.snapped && entry.t < 1.0) {
        return true;
      }
    }
    return false;
  }

  void dispose() {
    _ticker.dispose();
  }
}
