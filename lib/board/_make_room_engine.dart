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
/// unwritten; on the axis of the edge it drags both are DIRECT, at their
/// targets from the install on, while on the other axis, where only its
/// lanes move it, they ride the clock with its neighbours' entries. On a
/// content-sized lane axis it also holds a BAND, the term its lane
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

import 'dart:typed_data';

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '_board_span.dart';
import 'board_animation_style.dart';

/// A resize session's targets for its own item, which the controller
/// writes through the engine's two resize callbacks and the engine reads
/// back. The engine keeps one, so neither a refresh nor an install builds
/// one.
class MakeRoomResizeTargets {
  /// The GEOMETRY, per axis and in content space: the LEAD and the EXTENT
  /// the item-geometry rule gives the item under the prospective span and
  /// lanes, minus the ones the stored span and lanes give it, both over
  /// the lattice as it paints.
  double leadDx = 0.0;
  double leadDy = 0.0;
  double extentDx = 0.0;
  double extentDy = 0.0;

  /// The TERM on the lane axis: the BAND, a content-space length the
  /// item's lane band adds to its stored track's term while it stays laned
  /// there, and whether it VACATES that track instead, both zero for an
  /// item that is not laned in a track of a content-sized lane axis.
  double band = 0.0;
  bool vacates = false;

  /// Whether the item JOINS a track: the prospective lanes lane it in a
  /// lane-axis track whose bucket it is not in, where it then holds a
  /// slot.
  bool joins = false;
}

/// Writes the geometry or the term targets of a resize session's item
/// [id] under [prospective] and the dry run's [assignment], null when the
/// dry run did not lane it, into [out].
typedef MakeRoomResizeTargetsWriter =
    void Function(
      int id,
      BoardSpan prospective,
      ({int lane, int laneCount, int laneSpan})? assignment,
      MakeRoomResizeTargets out,
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

/// A set of int pairs `(a, b)`, each with a double beside it, open
/// addressed over typed buffers: the pairs lie dense in [_a] and [_b],
/// their values in [_values], and [_index], twice the dense capacity and
/// a power of two, holds each pair's dense position plus one at its HOME,
/// `(a * 31 + b) & (length - 1)`, or at the first empty position after
/// it, probed linearly, and zero where empty. A removal moves the last
/// pair into the removed one's dense position and empties the removed
/// one's index position by backward shift, so the index holds no
/// tombstone and its load stays at most one half: an insert, a lookup and
/// a removal are each one probe sequence. The buffers are allocated at
/// the first insert, double when full and are kept by [clear], so once
/// they have reached a board's need nothing here allocates.
class _PairTable {
  static const int _initialCapacity = 8;

  Int32List? _a;
  Int32List? _b;
  Float64List? _values;
  Int32List? _index;
  int _count = 0;

  /// The number of pairs, which the dense reads below index.
  int get count {
    return _count;
  }

  int aAt(int position) {
    return _a![position];
  }

  int bAt(int position) {
    return _b![position];
  }

  double valueAt(int position) {
    return _values![position];
  }

  void setValueAt(int position, double value) {
    _values![position] = value;
  }

  static int _home(int a, int b, int mask) {
    return (a * 31 + b) & mask;
  }

  /// The dense position of `(a, b)`, or -1 when it is absent.
  int find(int a, int b) {
    if (_count == 0) {
      return -1;
    }
    final index = _index!;
    final pairsA = _a!;
    final pairsB = _b!;
    final mask = index.length - 1;
    var slot = _home(a, b, mask);
    while (true) {
      final entry = index[slot];
      if (entry == 0) {
        return -1;
      }
      final position = entry - 1;
      if (pairsA[position] == a && pairsB[position] == b) {
        return position;
      }
      slot = (slot + 1) & mask;
    }
  }

  /// Adds `(a, b)` with [value]; the caller has found it absent.
  void add(int a, int b, double value) {
    var pairsA = _a;
    if (pairsA == null || _count == pairsA.length) {
      _grow();
      pairsA = _a!;
    }
    final position = _count;
    pairsA[position] = a;
    _b![position] = b;
    _values![position] = value;
    _count += 1;
    _indexPosition(position);
  }

  /// Removes the pair at the dense [position].
  void removeAt(int position) {
    final index = _index!;
    final mask = index.length - 1;
    _emptyIndexAt(_slotOf(position, mask), mask);
    final last = _count - 1;
    if (position != last) {
      final pairsA = _a!;
      final pairsB = _b!;
      final values = _values!;
      pairsA[position] = pairsA[last];
      pairsB[position] = pairsB[last];
      values[position] = values[last];
      index[_slotOf(last, mask)] = position + 1;
    }
    _count = last;
  }

  /// Removes every pair, keeping the buffers.
  void clear() {
    if (_count == 0) {
      return;
    }
    final index = _index!;
    index.fillRange(0, index.length, 0);
    _count = 0;
  }

  /// The index position holding the dense [position].
  int _slotOf(int position, int mask) {
    final index = _index!;
    var slot = _home(_a![position], _b![position], mask);
    while (index[slot] != position + 1) {
      slot = (slot + 1) & mask;
    }
    return slot;
  }

  /// Files the dense [position] at its home or the first empty position
  /// after it.
  void _indexPosition(int position) {
    final index = _index!;
    final mask = index.length - 1;
    var slot = _home(_a![position], _b![position], mask);
    while (index[slot] != 0) {
      slot = (slot + 1) & mask;
    }
    index[slot] = position + 1;
  }

  /// Empties the index position [hole] by backward shift: each entry
  /// after it, up to the next empty position, whose home does not lie
  /// cyclically in `(hole, slot]` moves back into the hole, which moves
  /// to where it was.
  void _emptyIndexAt(int hole, int mask) {
    final index = _index!;
    var slot = hole;
    while (true) {
      slot = (slot + 1) & mask;
      final entry = index[slot];
      if (entry == 0) {
        break;
      }
      final home = _home(_a![entry - 1], _b![entry - 1], mask);
      final reachable = hole < slot
          ? home > hole && home <= slot
          : home > hole || home <= slot;
      if (!reachable) {
        index[hole] = entry;
        hole = slot;
      }
    }
    index[hole] = 0;
  }

  /// Doubles the dense capacity, the first allocation included, and
  /// re-files every pair in an index twice its size.
  void _grow() {
    final old = _a;
    final capacity = old == null ? _initialCapacity : old.length * 2;
    final pairsA = Int32List(capacity);
    final pairsB = Int32List(capacity);
    final values = Float64List(capacity);
    if (old != null) {
      pairsA.setRange(0, _count, old);
      pairsB.setRange(0, _count, _b!);
      values.setRange(0, _count, _values!);
    }
    _a = pairsA;
    _b = pairsB;
    _values = values;
    _index = Int32List(capacity * 2);
    for (var position = 0; position < _count; position++) {
      _indexPosition(position);
    }
  }
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
      ({int lane, int laneCount, int laneSpan}) assignment,
    )
    neighbourExtentOf,
    required int Function(int id) laneOfId,
    required int Function(int id) laneCountOfId,
    required MakeRoomResizeTargetsWriter resizeGeometryOf,
    required MakeRoomResizeTargetsWriter resizeTermOf,
  }) : _styleOf = styleOf,
       _notifyNow = notifyNow,
       _notifyCoalesced = notifyCoalesced,
       _laneAxisOf = laneAxisOf,
       _dryRunOf = dryRunOf,
       _laneOriginOfId = laneOriginOfId,
       _neighbourExtentOf = neighbourExtentOf,
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

  /// The EXTENT the geometry rule would give a dry-run neighbour under the
  /// dry run's lane assignment, minus the one it gives it now: it keeps
  /// its span and its track, so only its lane band can change. The
  /// controller answers, that rule being its own.
  final Offset Function(
    int id,
    ({int lane, int laneCount, int laneSpan}) assignment,
  )
  _neighbourExtentOf;
  final int Function(int id) _laneOfId;
  final int Function(int id) _laneCountOfId;

  /// The two resize callbacks, which write a RESIZE session's targets for
  /// its own item into [_resizeTargets].
  final MakeRoomResizeTargetsWriter _resizeGeometryOf;
  final MakeRoomResizeTargetsWriter _resizeTermOf;

  /// What the two resize callbacks write: created at the first resize
  /// install, then reused by every install and refresh. Non-null whenever
  /// a session's source stands.
  MakeRoomResizeTargets? _resizeTargets;

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
  /// its SOURCE, the prospective span and the dry run's assignment the
  /// refreshes re-derive its targets from. A source stands exactly while
  /// [_resizeSpan] is non-null; a release and a clear of the id tear the
  /// session down.
  int? _sessionId;
  BoardSpan? _resizeSpan;
  ({int lane, int laneCount, int laneSpan})? _resizeAssignment;

  /// The axis of the edge a resize session drags, on which its own lead
  /// and extent are DIRECT (see [_installOwnAxes]); null for a lifted
  /// session and for a resize that names none.
  Axis? _resizeAxis;

  /// The OWN-PREVIEW SCOPE's epoch, 0 while no scope is open, and the
  /// count the next one is taken from. While a scope is open every write
  /// that changes a held offset, band or vacate or a slot JOINS the
  /// entry: its pair goes into the JOIN RECORD, [_ownEntries] for
  /// `(id, kind)` and [_ownSlots] for a slot's `(track, lane)`, once, with
  /// its REMAINDER, the value that entry held for whoever wrote it before
  /// the scope did, beside it. An entry is OWN while its pair is
  /// recorded. Each removal from [_held], [_heldBand], [_heldVacate] or
  /// [_slots] drops the removed entry's pair, so the record holds only
  /// standing entries, and each change of the epoch empties it
  /// ([_emptyOwnRecord]). Lead and extent entries never join.
  int _ownEpoch = 0;
  int _ownEpochCount = 0;

  /// The join record's two tables, created at their first join and kept
  /// across scopes. The entry table's `b` is one of [_offsetKind],
  /// [_bandKind] and [_vacateKind], naming the map the entry is in.
  _PairTable? _ownEntries;
  _PairTable? _ownSlots;

  static const int _offsetKind = 0;
  static const int _bandKind = 1;
  static const int _vacateKind = 2;

  /// Debug-only: the lookups of [_heldLead], [_heldBand] and
  /// [_heldVacate] that [deltaOf], [termDeltaOf] and [vacatedOf] have
  /// made since tests last assigned it 0. A field on an unexported class,
  /// as `Fenwick.debugOpCount` is: a reader that looks up an empty map
  /// paints and sizes what one that does not paints and sizes, so no
  /// widget-level seam observes the cost.
  int debugResizeHoldReadCount = 0;

  /// Debug-only: the point-mapping calls the render object has made in
  /// its OWN-FREE mode, the lattice without the own-preview scope's
  /// preview, since tests last assigned it 0. Here beside the scope that
  /// mode leaves out, and forwarded by the controller's internals, because
  /// the mode makes the same axis reads as the painted mapping does, so
  /// no axis counter tells the two apart, and a field on the render object
  /// would be a member of an exported type.
  int debugOwnFreeMappingCount = 0;

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
    _rebaseOwnRemainders();
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

  /// The number of slots on lane-axis track [track]: the ones [slotsOn]
  /// maps, which [slotLaneAt] and [slotValueAt] read one at a time and in
  /// its order, so a per-layout walk builds no iterable.
  int slotCountOn(int track) {
    return _slots[track]?.length ?? 0;
  }

  /// The lane of the slot at [index] on lane-axis track [track], below
  /// [slotCountOn].
  int slotLaneAt(int track, int index) {
    return _slots[track]![index].lane;
  }

  /// The value, in `[0, 1]`, of the slot at [index] on lane-axis track
  /// [track], below [slotCountOn].
  double slotValueAt(int track, int index) {
    return _valueOfSlot(_slots[track]![index]);
  }

  /// Opens a new own-preview scope and returns its epoch, emptying the
  /// join record; a scope still open is replaced.
  int beginOwnPreview() {
    _ownEpochCount += 1;
    _ownEpoch = _ownEpochCount;
    _emptyOwnRecord();
    return _ownEpoch;
  }

  /// Closes the scope [epoch] opened and empties the join record, while
  /// [epoch] is the open one; any other epoch changes nothing, so a
  /// session's teardown never closes a scope a later session opened.
  void endOwnPreview(int epoch) {
    if (epoch == 0 || epoch != _ownEpoch) {
      return;
    }
    _ownEpoch = 0;
    _emptyOwnRecord();
  }

  /// The open scope's epoch, 0 while none is open.
  int get ownPreviewEpoch {
    return _ownEpoch;
  }

  /// The ids of the entry table's pairs, in its dense order: an id once
  /// per kind of entry it holds that the scope recorded.
  int get ownIdCount {
    return _ownEntries?.count ?? 0;
  }

  int ownIdAt(int index) {
    return _ownEntries!.aAt(index);
  }

  /// The tracks of the slot table's pairs, in its dense order: a track
  /// once per lane the scope recorded a slot of there.
  int get ownSlotTrackCount {
    return _ownSlots?.count ?? 0;
  }

  int ownSlotTrackAt(int index) {
    return _ownSlots!.aAt(index);
  }

  /// [termDeltaOf]'s lane-axis length with every own entry's value
  /// replaced by its FOREIGN value ([_foreignOf]), so it answers the term
  /// delta as it would stand without the scope's own preview. Zero for no
  /// entry or with no lane axis.
  double termDeltaWithoutOwnOf(int id) {
    final entry = _held[id];
    final band = _heldBand.isEmpty ? null : _heldBand[id];
    if (entry == null && band == null) {
      return 0.0;
    }
    if (_laneAxisOf() == null) {
      return 0.0;
    }
    return (entry == null ? 0.0 : _foreignOf(entry, id, _offsetKind)) +
        (band == null ? 0.0 : _foreignOf(band, id, _bandKind));
  }

  /// [vacatedOf] with an own entry's value replaced by its foreign value.
  double vacatedWithoutOwnOf(int id) {
    if (_heldVacate.isEmpty) {
      return 0.0;
    }
    final entry = _heldVacate[id];
    return entry == null ? 0.0 : _foreignOf(entry, id, _vacateKind);
  }

  /// [slotValueAt] with an own slot's value replaced by its foreign
  /// value.
  double slotValueWithoutOwnAt(int track, int index) {
    final slot = _slots[track]![index];
    final table = _ownSlots;
    if (table == null || table.count == 0) {
      return _valueOfSlot(slot);
    }
    final at = table.find(track, slot.lane);
    if (at < 0) {
      return _valueOfSlot(slot);
    }
    return _remainderOf(table.valueAt(at), slot.snapped, slot.t);
  }

  /// The FOREIGN value of [entry], [id]'s entry of [kind]: its whole value
  /// when its pair is not recorded, and otherwise its remainder decaying on
  /// the entry's own clock ([_remainderOf]).
  double _foreignOf(_HeldOffset entry, int id, int kind) {
    final table = _ownEntries;
    if (table == null || table.count == 0) {
      return _valueOf(entry);
    }
    final at = table.find(id, kind);
    if (at < 0) {
      return _valueOf(entry);
    }
    return _remainderOf(table.valueAt(at), entry.snapped, entry.t);
  }

  /// A recorded entry's foreign value: [foreignFrom] scaled by what its
  /// clock [t] has left on the curve, clamped as [_valueOf] clamps it, so a
  /// clock past 1 or driven to infinity by an off family reads zero; zero
  /// when [snapped]. An entry's value is `from * (1 - c) + target * c`, and
  /// the remainder is the share of its `from` that was not the scope's.
  double _remainderOf(double foreignFrom, bool snapped, double t) {
    if (snapped) {
      return 0.0;
    }
    return foreignFrom * (1.0 - _curve.transform(t.clamp(0.0, 1.0)));
  }

  /// The map an entry of [kind] lives in.
  Map<int, _HeldOffset> _offsetsOf(int kind) {
    switch (kind) {
      case _offsetKind:
        return _held;
      case _bandKind:
        return _heldBand;
      default:
        return _heldVacate;
    }
  }

  /// The slot on [track] at [lane]; the record holds only standing slots.
  _Slot _slotOf(int track, int lane) {
    for (final slot in _slots[track]!) {
      if (slot.lane == lane) {
        return slot;
      }
    }
    throw StateError("No slot on track $track at lane $lane.");
  }

  /// Empties both tables of the join record, keeping their buffers. The
  /// one site that does, run by each change of the scope's epoch.
  void _emptyOwnRecord() {
    _ownEntries?.clear();
    _ownSlots?.clear();
  }

  /// A write that CREATES [id]'s entry of [kind] joins it with a zero
  /// remainder: nothing of it was anyone else's.
  void _joinCreated(int id, int kind) {
    if (_ownEpoch == 0) {
      return;
    }
    final table = _ownEntries ??= _PairTable();
    final at = table.find(id, kind);
    if (at < 0) {
      table.add(id, kind, 0.0);
    } else {
      table.setValueAt(at, 0.0);
    }
  }

  /// A re-base of [id]'s standing [entry] of [kind], which keeps its
  /// clock, joins it BEFORE the write: an absent pair is recorded with the
  /// entry's `from`, which a closing entry's value decays from on that
  /// clock; a recorded one keeps its remainder.
  void _joinRebase(_HeldOffset entry, int id, int kind) {
    if (_ownEpoch == 0) {
      return;
    }
    final table = _ownEntries ??= _PairTable();
    if (table.find(id, kind) < 0) {
      table.add(id, kind, entry.from);
    }
  }

  /// [_joinCreated] for the slot at [lane] on [track].
  void _joinCreatedSlot(int track, int lane) {
    if (_ownEpoch == 0) {
      return;
    }
    final table = _ownSlots ??= _PairTable();
    final at = table.find(track, lane);
    if (at < 0) {
      table.add(track, lane, 0.0);
    } else {
      table.setValueAt(at, 0.0);
    }
  }

  /// Drops the pair of [id]'s entry of [kind], removed beside this call;
  /// nothing while the entry table is empty.
  void _dropEntry(int id, int kind) {
    final table = _ownEntries;
    if (table == null || table.count == 0) {
      return;
    }
    final at = table.find(id, kind);
    if (at >= 0) {
      table.removeAt(at);
    }
  }

  /// Drops the pair of every recorded entry [closed] answers true for,
  /// before the caller removes those entries. Walked from the dense end,
  /// so the pair a drop moves into the dropped position has been read.
  void _dropClosedEntries(bool Function(_HeldOffset entry) closed) {
    final table = _ownEntries;
    if (table == null) {
      return;
    }
    for (var at = table.count - 1; at >= 0; at--) {
      final entry = _offsetsOf(table.bAt(at))[table.aAt(at)]!;
      if (closed(entry)) {
        table.removeAt(at);
      }
    }
  }

  /// [_dropClosedEntries] for the recorded slots.
  void _dropClosedSlots(bool Function(_Slot slot) closed) {
    final table = _ownSlots;
    if (table == null) {
      return;
    }
    for (var at = table.count - 1; at >= 0; at--) {
      if (closed(_slotOf(table.aAt(at), table.bAt(at)))) {
        table.removeAt(at);
      }
    }
  }

  /// A changed clock re-bases every entry still in motion; a recorded one
  /// first takes its foreign value on the old clock as its remainder, so
  /// it decays on the new clock from where it stood.
  void _rebaseOwnRemainders() {
    final entries = _ownEntries;
    if (entries != null) {
      for (var at = 0; at < entries.count; at++) {
        final entry = _offsetsOf(entries.bAt(at))[entries.aAt(at)]!;
        if (!entry.snapped && entry.t < 1.0) {
          entries.setValueAt(
            at,
            _remainderOf(entries.valueAt(at), entry.snapped, entry.t),
          );
        }
      }
    }
    final slots = _ownSlots;
    if (slots != null) {
      for (var at = 0; at < slots.count; at++) {
        final slot = _slotOf(slots.aAt(at), slots.bAt(at));
        if (!slot.snapped && slot.t < 1.0) {
          slots.setValueAt(
            at,
            _remainderOf(slots.valueAt(at), slot.snapped, slot.t),
          );
        }
      }
    }
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
  /// [clearForId], which discards the fold. The join record's slot table
  /// empties with them.
  double? _discardSlots(double? minT) {
    for (final slots in _slots.values) {
      for (final slot in slots) {
        minT = _foldClock(minT, slot.snapped, slot.t, slot.from != slot.target);
      }
    }
    _slots.clear();
    _ownSlots?.clear();
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
  /// of it. A re-target that writes joins the slot, filed under [track].
  /// Returns the fold.
  double? _retargetSlot(
    _Slot slot,
    int track,
    double target,
    bool snap,
    double? minT,
  ) {
    if (!snap && slot.target == target) {
      return minT;
    }
    if (snap) {
      minT = _foldClock(minT, slot.snapped, slot.t, slot.from != slot.target);
    }
    // The JOIN, before the write and from the one curve evaluation that
    // gives the value the slot restarts from: an absent pair is recorded
    // with that value, a recorded one's remainder decays to its foreign
    // value at this instant, and a snap leaves nothing foreign.
    final eased = slot.snapped ? 1.0 : _curve.transform(slot.t.clamp(0.0, 1.0));
    final current = slot.snapped
        ? slot.target
        : slot.from + (slot.target - slot.from) * eased;
    if (_ownEpoch != 0) {
      final table = _ownSlots ??= _PairTable();
      final at = table.find(track, slot.lane);
      if (at < 0) {
        table.add(track, slot.lane, snap ? 0.0 : current);
      } else {
        final values = table._values!;
        values[at] = snap ? 0.0 : values[at] * (1.0 - eased);
      }
    }
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
  /// [target] is a content-space offset on the lane axis. A re-target
  /// that writes joins the entry, [id]'s of [kind]. Returns the fold.
  double? _retargetOffset(
    _HeldOffset entry,
    int id,
    int kind,
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
    // The JOIN, before the write and from the one curve evaluation that
    // gives the value the entry restarts from: an absent pair is recorded
    // with that value, a recorded one's remainder decays to its foreign
    // value at this instant, and a snap leaves nothing foreign.
    final eased = entry.snapped
        ? 1.0
        : _curve.transform(entry.t.clamp(0.0, 1.0));
    final current = entry.snapped
        ? entry.target
        : entry.from + (entry.target - entry.from) * eased;
    if (_ownEpoch != 0) {
      final table = _ownEntries ??= _PairTable();
      final at = table.find(id, kind);
      if (at < 0) {
        table.add(id, kind, snap ? 0.0 : current);
      } else {
        final values = table._values!;
        values[at] = snap ? 0.0 : values[at] * (1.0 - eased);
      }
    }
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

  /// A resize session's install of its own item's entry in [map]. On the
  /// session's dragged axis, [_resizeAxis], the entry is DIRECT: its
  /// `from` is written equal to its target there, so it paints the target
  /// at once whatever its clock reads, and [_rebaseAxes] and
  /// [_adoptClock] keep the two equal. The other axis changes only with
  /// the item's lanes, which its neighbours make room for on the clock,
  /// so it follows [_retargetAxes]'s rule: re-targeted from where it
  /// paints when its own target changed, and otherwise left on the clock
  /// it runs on, so a step of the dragged edge alone keeps it in step with
  /// those neighbours. An entry left with nothing to move is at rest, and
  /// one at rest at zero is removed, as [_rebaseAxes] removes one. Without
  /// a dragged axis, or on a snapped install, [_installAxes] installs it.
  /// Returns the fold, which a direct write never adds to.
  double? _installOwnAxes(
    Map<int, _HeldAxes> map,
    int id,
    Offset target,
    bool snap,
    double? minT,
  ) {
    final axis = _resizeAxis;
    if (axis == null || snap) {
      return _installAxes(map, id, target, snap, minT);
    }
    final vertical = axis == Axis.vertical;
    var entry = map[id];
    if (entry == null) {
      if (target == Offset.zero) {
        return minT;
      }
      entry = _HeldAxes(
        target: target,
        from: vertical ? Offset(0.0, target.dy) : Offset(target.dx, 0.0),
        snapped: false,
      );
      map[id] = entry;
    } else {
      final held = entry.target;
      if (vertical ? held.dx != target.dx : held.dy != target.dy) {
        final current = _axesValueOf(entry);
        entry
          ..from = vertical
              ? Offset(current.dx, target.dy)
              : Offset(target.dx, current.dy)
          ..snapped = false
          ..t = 0.0;
      } else {
        final from = entry.from;
        entry.from = vertical
            ? Offset(from.dx, target.dy)
            : Offset(target.dx, from.dy);
      }
      entry.target = target;
    }
    final atRest = entry.snapped || entry.from == entry.target;
    if (atRest && entry.target == Offset.zero) {
      map.remove(id);
    } else if (atRest && !entry.snapped) {
      entry.t = 1.0;
    }
    return minT;
  }

  /// [id]'s current value in [map], zero for no entry.
  Offset _axesOf(Map<int, _HeldAxes> map, int id) {
    final entry = map[id];
    return entry == null ? Offset.zero : _axesValueOf(entry);
  }

  /// An install's close of every entry in [map] but [keep]'s, each
  /// re-targeted to zero by [_retargetAxes]'s rule. Returns the fold.
  double? _closeAxesBeside(
    Map<int, _HeldAxes> map,
    int? keep,
    bool snap,
    double? minT,
  ) {
    for (final id in map.keys) {
      if (id != keep) {
        minT = _retargetAxes(map[id]!, Offset.zero, snap, minT);
      }
    }
    return minT;
  }

  /// [_closeAxesBeside] for a held single value, over the entries of
  /// [kind].
  double? _closeOffsetsBeside(
    int kind,
    int? keep,
    bool snap,
    double? minT,
  ) {
    final map = _offsetsOf(kind);
    for (final id in map.keys) {
      if (id != keep) {
        minT = _retargetOffset(map[id]!, id, kind, 0.0, snap, minT);
      }
    }
    return minT;
  }

  /// [_installAxes] for a held single value, [id]'s entry of [kind]; a
  /// new entry joins.
  double? _installOffset(
    int kind,
    int id,
    double target,
    bool snap,
    double? minT,
  ) {
    final map = _offsetsOf(kind);
    final existing = map[id];
    if (existing != null) {
      return _retargetOffset(existing, id, kind, target, snap, minT);
    }
    if (target != 0.0) {
      map[id] = _HeldOffset(
        target: target,
        from: snap ? target : 0.0,
        snapped: snap,
      );
      _joinCreated(id, kind);
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
    if (id == null || span == null) {
      return;
    }
    final targets = _resizeTargets!;
    _resizeTermOf(id, span, _resizeAssignment, targets);
    _rebaseOffset(_bandKind, id, targets.band);
    _rebaseOffset(_vacateKind, id, targets.vacates ? 1.0 : 0.0);
  }

  /// Re-derives the resize session's LEAD and EXTENT from its source, over
  /// the lattice as it paints; see [_rebaseOffset]. Returns at once
  /// without a source.
  void refreshResizeGeometry() {
    final id = _sessionId;
    final span = _resizeSpan;
    if (id == null || span == null) {
      return;
    }
    final targets = _resizeTargets!;
    _resizeGeometryOf(id, span, _resizeAssignment, targets);
    _rebaseAxes(_heldLead, id, targets.leadDx, targets.leadDy);
    _rebaseAxes(_heldExtent, id, targets.extentDx, targets.extentDy);
  }

  /// RE-BASES [id]'s entry of [kind] onto a re-derived [target]: the
  /// target and the `from` move by the same difference, so the entry
  /// keeps its clock and paints over the stored span's new geometry where
  /// it painted over the old one, moved only by the change in the target.
  /// A missing entry counts as one at rest at zero, so a non-zero target
  /// creates it at rest; an entry at rest whose target becomes zero is
  /// removed, and one in motion closes on its clock, by the rule that
  /// zero means closing. A creation and a move join the entry, and a
  /// removal drops its pair. Notifies nothing, bumps no generation and
  /// leaves the ticker alone, so it is safe inside a layout.
  void _rebaseOffset(int kind, int id, double target) {
    final map = _offsetsOf(kind);
    final entry = map[id];
    if (entry == null) {
      if (target != 0.0) {
        map[id] = _HeldOffset(target: target, from: target, snapped: false)
          ..t = 1.0;
        _joinCreated(id, kind);
      }
      return;
    }
    if (entry.target == target) {
      return;
    }
    if (target == 0.0 && (entry.snapped || entry.t >= 1.0)) {
      map.remove(id);
      _dropEntry(id, kind);
      return;
    }
    _joinRebase(entry, id, kind);
    entry
      ..from = entry.from + (target - entry.target)
      ..target = target;
  }

  /// [_rebaseOffset] for a held per-axis value, whose target [dx], [dy]
  /// is given per axis so that an unchanged one builds no [Offset].
  void _rebaseAxes(Map<int, _HeldAxes> map, int id, double dx, double dy) {
    final entry = map[id];
    final zero = dx == 0.0 && dy == 0.0;
    if (entry == null) {
      if (!zero) {
        final target = Offset(dx, dy);
        map[id] = _HeldAxes(target: target, from: target, snapped: false)
          ..t = 1.0;
      }
      return;
    }
    final held = entry.target;
    if (held.dx == dx && held.dy == dy) {
      return;
    }
    if (zero && (entry.snapped || entry.t >= 1.0)) {
      map.remove(id);
      return;
    }
    entry
      ..from = entry.from + Offset(dx - held.dx, dy - held.dy)
      ..target = Offset(dx, dy);
  }

  /// Ends the session: its id, its source and its dragged axis.
  void _clearSession() {
    _sessionId = null;
    _resizeSpan = null;
    _resizeAssignment = null;
    _resizeAxis = null;
  }

  /// Opens (or re-targets) the gap for a drag of [draggedId] resolving to
  /// [prospective]. Never refuses: under an off family, or with a
  /// [duration] that is not positive, it INSTALLS AND SNAPS, because the
  /// gap IS the target state, and an off family removes its motion, not
  /// the gap. The snap flag is the kill switch, resolved here through
  /// [BoardAnimationTiming.isOff], at one of the family's two declaring
  /// sites; [duration] and [curve] are a session's captured values and
  /// an off family dominates them. [resizeAxis] is, for a resize, the
  /// axis of the edge it drags, on which its own item's lead and extent
  /// are direct rather than on the clock; null holds both axes on the
  /// clock, and a lifted session names none.
  void previewGap({
    required int draggedId,
    required BoardSpan prospective,
    bool lifted = false,
    Axis? resizeAxis,
    Duration? duration,
    Curve? curve,
  }) {
    assert(!lifted || resizeAxis == null, "A lifted session drags no edge.");
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
    // THE SESSION. A RESIZE records its SOURCE, the span and the dry
    // run's assignment its targets are re-derived from every layout; a
    // LIFTED install records none, so no refresh runs for it. The
    // discriminator is the session's argument, NOT the dragging bit: that
    // bit is set for every session and carries no kind.
    final assignment = dry[draggedId];
    _sessionId = draggedId;
    _resizeSpan = lifted ? null : prospective;
    _resizeAssignment = lifted ? null : assignment;
    _resizeAxis = lifted ? null : resizeAxis;
    MakeRoomResizeTargets? resize;
    if (!lifted) {
      resize = _resizeTargets ??= MakeRoomResizeTargets();
      _resizeGeometryOf(draggedId, prospective, assignment, resize);
      _resizeTermOf(draggedId, prospective, assignment, resize);
    }
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
    // of the drag's in-place feedback. The resized item's TERM entries
    // follow the same rules, and so do its LEAD and EXTENT but on the axis
    // of the edge it drags, where [_installOwnAxes] makes them direct.
    // What that item paints before its own entries install, so the live
    // tails can tell a direct write, which changes it with nothing left
    // moving, from one the clock will show.
    final leadBefore = _axesOf(_heldLead, draggedId);
    final extentBefore = _axesOf(_heldExtent, draggedId);
    if (resize != null) {
      minT = _installOwnAxes(
        _heldExtent,
        draggedId,
        Offset(resize.extentDx, resize.extentDy),
        snap,
        minT,
      );
    }
    final extentTargets = <int, Offset>{};
    dry.forEach((id, assignment) {
      if (id == draggedId) {
        return;
      }
      extentTargets[id] = _neighbourExtentOf(id, assignment);
    });
    for (final id in _heldExtent.keys) {
      if (resize == null || id != draggedId) {
        extentTargets.putIfAbsent(id, () {
          return Offset.zero;
        });
      }
    }
    extentTargets.forEach((id, extent) {
      minT = _installAxes(_heldExtent, id, extent, snap, minT);
    });
    // A held lead, band or vacate of any id but a resize session's own
    // item closes back to zero, re-targeted in place, before that item's
    // entries install.
    final keep = resize == null ? null : draggedId;
    minT = _closeAxesBeside(_heldLead, keep, snap, minT);
    minT = _closeOffsetsBeside(_bandKind, keep, snap, minT);
    minT = _closeOffsetsBeside(_vacateKind, keep, snap, minT);
    if (resize != null) {
      minT = _installOwnAxes(
        _heldLead,
        draggedId,
        Offset(resize.leadDx, resize.leadDy),
        snap,
        minT,
      );
      minT = _installOffset(_bandKind, draggedId, resize.band, snap, minT);
      minT = _installOffset(
        _vacateKind,
        draggedId,
        resize.vacates ? 1.0 : 0.0,
        snap,
        minT,
      );
    }
    final direct =
        resize != null &&
        (_axesOf(_heldLead, draggedId) != leadBefore ||
            _axesOf(_heldExtent, draggedId) != extentBefore);
    if (laneAxis == null) {
      // No lane geometry exists to open a gap in; the extent and lead
      // preview above is the whole of the in-place feedback on such a
      // board, and the drag proxy is the rest of it. The fold is
      // discarded unpublished here; the case is a restyle to off mid-drag
      // on a board with no lanes.
      if (snap) {
        _removeClosed();
      }
      _generation += 1;
      if (snap) {
        _notifyNow();
      } else {
        _ensureTicking();
        _notifyDirect(direct);
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
      minT = _installOffset(_offsetKind, id, target, snap, minT);
    });
    // THE SLOTS: a LIFTED item's, and a RESIZED item's while its preview
    // lanes it in a track it is not laned in; an install by the slots'
    // own session runs the block too, so a resize that stops joining
    // closes its slot by the same re-target.
    final joins = resize?.joins ?? false;
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
          minT = _retargetSlot(slot, track, desired, snap, minT);
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
          _joinCreatedSlot(prospectiveTrack, desiredLane);
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
    _notifyDirect(direct);
  }

  /// The live install's dispatch for a DIRECT write: one that changed what
  /// the resized item paints at once, which no tick may follow, the write
  /// leaving nothing in motion. Without it nothing lays the board out to
  /// show the write, as the snap arm's [_notifyNow] exists to; an install
  /// that wrote nothing direct dispatches nothing, so an idempotent
  /// re-install costs no dispatch.
  void _notifyDirect(bool direct) {
    if (direct) {
      _notifyNow();
    }
  }

  /// The install's snap tail for every held entry: one a snap re-targeted
  /// to zero is closed, and goes, its pair dropped.
  void _removeClosed() {
    _dropClosedEntries(_targetsZero);
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
  /// mid-motion without ramping it there, so both fold into [minT]. A
  /// removed slot's pair is dropped.
  double? _snapSlots(double? minT) {
    _dropClosedSlots(_slotTargetsZero);
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
      var minT = _discardOffsets(_offsetKind, null, null);
      minT = _discardOffsets(_bandKind, survivors, minT);
      minT = _discardOffsets(_vacateKind, survivors, minT);
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
    _closeOffsetsBeside(_offsetKind, null, false, null);
    _closeOffsetsBeside(_bandKind, null, false, null);
    _closeOffsetsBeside(_vacateKind, null, false, null);
    for (final map in <Map<int, _HeldAxes>>[_heldExtent, _heldLead]) {
      for (final entry in map.values) {
        _retargetAxes(entry, Offset.zero, false, null);
      }
    }
    _slots.forEach((track, slots) {
      for (final slot in slots) {
        _retargetSlot(slot, track, 0.0, false, null);
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
    var removed = _removeHeld(_offsetKind, id);
    removed = _heldExtent.remove(id) != null || removed;
    removed = _heldLead.remove(id) != null || removed;
    removed = _removeHeld(_bandKind, id) || removed;
    removed = _removeHeld(_vacateKind, id) || removed;
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

  /// Removes [id]'s entry of [kind] and drops its pair; whether there was
  /// one.
  bool _removeHeld(int kind, int id) {
    if (_offsetsOf(kind).remove(id) == null) {
      return false;
    }
    _dropEntry(id, kind);
    return true;
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
    _dropClosedEntries(_settledClosed);
    _dropClosedSlots(_slotSettledClosed);
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

  /// The snap's discard of the entries of [kind]: every entry goes, its
  /// clock folded into [minT] and its pair dropped, but a CLOSING one of an
  /// id in [keep]. Returns the fold.
  double? _discardOffsets(int kind, Set<int>? keep, double? minT) {
    _offsetsOf(kind).removeWhere((id, entry) {
      if (keep != null && entry.target == 0.0 && keep.contains(id)) {
        return false;
      }
      minT = _foldClock(minT, entry.snapped, entry.t, entry.from != entry.target);
      _dropEntry(id, kind);
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
    return _settledClosed(entry);
  }

  static bool _settledClosed(_HeldOffset entry) {
    return entry.t >= 1.0 && entry.target == 0.0;
  }

  static bool _slotSettledClosed(_Slot slot) {
    return slot.t >= 1.0 && slot.target == 0.0;
  }

  /// Whether a snap re-targeted [entry] to zero, so its tail removes it.
  static bool _targetsZero(_HeldOffset entry) {
    return entry.target == 0.0;
  }

  static bool _slotTargetsZero(_Slot slot) {
    return slot.target == 0.0;
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
