/// Internal: the makeRoom animation source.
///
/// HELD paint-only gap offsets: an entry animates to a non-zero target and
/// then PERSISTS until re-targeted or released, which is what makes the
/// gap the target state rather than a transient toward one. The offsets
/// come from a DRY-RUN lane resolution over at most two lane-axis
/// buckets, supplied by the controller; the model is never written.
///
/// Beside the offsets the engine holds a HELD EXTENT per id: for a RESIZE
/// session's own item, the length its prospective span would give it
/// minus the length it has now, so the block follows the finger while
/// the model stays unwritten; and for every member the dry run touched,
/// the slice its prospective lane count would give it minus the slice it
/// has, so a neighbour on a FIXED lane axis shrinks or widens with the
/// gap instead of after the drop. Extents ride the offsets' clock and
/// their two doors.
///
/// Beside the offsets the engine holds prospective lane SLOTS for the
/// LIFTED item: a slot has no paint half at all and exists only so the
/// track-sizing walk can count the lane the drop would occupy. The
/// contribution reaches the SOURCE track as well as the prospective one,
/// because the dry run re-sweeps the stored bucket; the one term held
/// still is the lifted item's own band, which its in-place widget keeps
/// painting. An install is IDEMPOTENT for an unchanged target, which is
/// what lets a closing entry ever retire under a per-frame re-resolve.
///
/// Not exported from the module barrel.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '_board_span.dart';
import 'board_animation_style.dart';

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

/// A HELD EXTENT preview for one item: the length its prospective span
/// and lane count would give it, minus the length its stored ones give
/// it now, per axis. Paint adds it to the item's extent exactly as a
/// held offset is added to its lead, so a resized block follows the
/// finger and a displaced neighbour takes its prospective slice while
/// the model stays unwritten.
///
/// Zero means this entry is CLOSING and is removed when it settles, the
/// rule its sibling below uses.
class _HeldExtent {
  _HeldExtent({
    required this.target,
    required this.from,
    required this.snapped,
  });

  Offset target;
  Offset from;
  bool snapped;
  double t = 0.0;
}

class _HeldOffset {
  _HeldOffset({
    required this.target,
    required this.from,
    required this.snapped,
  });

  /// The held value on the lane axis. Zero means this entry is CLOSING
  /// and is removed when it settles.
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
  }) : _styleOf = styleOf,
       _notifyNow = notifyNow,
       _notifyCoalesced = notifyCoalesced,
       _laneAxisOf = laneAxisOf,
       _dryRunOf = dryRunOf,
       _laneOriginOfId = laneOriginOfId,
       _prospectiveExtentOf = prospectiveExtentOf,
       _laneOfId = laneOfId,
       _laneCountOfId = laneCountOfId {
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

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  final Map<int, _HeldOffset> _held = <int, _HeldOffset>{};

  /// One entry per id whose extent the preview holds: a resize session's
  /// own item and every dry-run member whose slice would change. Empty
  /// on a content-sized lane axis for a pure lane change, where every
  /// slice is the one lane extent and the delta is exactly zero.
  final Map<int, _HeldExtent> _heldExtent = <int, _HeldExtent>{};

  /// KEYED BY LANE-AXIS TRACK, and an emptied bucket is removed, so
  /// `_slots.isEmpty` is exactly "no slot exists". The sizing walk asks
  /// for one track at a time, once per track per obtain round per
  /// correction pass, so a flat list would be a full scan per ask.
  final Map<int, List<_Slot>> _slots = <int, List<_Slot>>{};

  /// The slots' lifecycle key, and it carries no other duty. ONE RULE
  /// governs it and it is total: non-null exactly while [_slots] is
  /// non-empty.
  int? _liftedId;

  int _generation = 0;
  int _snapGeneration = 0;

  Curve _curve = Curves.linear;

  /// The CAPTURED clock the offsets, extents and slots run on, resolved
  /// beside [_curve] at the two declaring sites from the caller's
  /// argument or the live spec and adopted through [_adoptClock]. The
  /// live spec's ZERO still dominates at the tick and the snap, as the
  /// kill switch does at the install.
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
    for (final entry in _held.values) {
      if (!entry.snapped && entry.t < 1.0) {
        entry
          ..from = _valueOf(entry)
          ..t = 0.0;
      }
    }
    _heldExtent.forEach((id, entry) {
      if (!entry.snapped && entry.t < 1.0) {
        entry
          ..from = extentDeltaOf(id)
          ..t = 0.0;
      }
    });
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

  bool get hasActive {
    return _held.isNotEmpty;
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
    for (final entry in _heldExtent.values) {
      if (!entry.snapped && entry.t < 1.0) {
        return true;
      }
    }
    return false;
  }

  /// The held extent preview for [id], zero for no entry.
  Offset extentDeltaOf(int id) {
    final entry = _heldExtent[id];
    if (entry == null) {
      return Offset.zero;
    }
    if (entry.snapped) {
      return entry.target;
    }
    final eased = _curve.transform(entry.t.clamp(0.0, 1.0));
    return entry.from + (entry.target - entry.from) * eased;
  }

  /// Any offset or slot unsnapped with clock below 1.
  bool get hasMotion {
    if (hasExtentMotion) {
      return true;
    }
    for (final entry in _held.values) {
      if (!entry.snapped && entry.t < 1.0) {
        return true;
      }
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
  /// an entry that was unsnapped, below clock 1 and actually moving had
  /// motion left, and the EARLIEST such clock is the one the hand-off
  /// continues from. Anything else folds to [minT] unchanged.
  double? _foldClock(
    double? minT,
    bool snapped,
    double t,
    double from,
    double target,
  ) {
    if (snapped || t >= 1.0 || from == target) {
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
    final duration = _styleOf().effectiveMakeRoom.duration == Duration.zero
        ? Duration.zero
        : _duration;
    _handOff = (
      remaining: duration * (1.0 - minT),
      curve: _CurveTail(_curve, minT),
    );
    _snapGeneration += 1;
  }

  /// The id whose prospective occupancy the slots carry, or null.
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

  /// The ids holding entries, offset or extent, for the composed per-id
  /// bound and the commit's painted-truth capture. A lane-0 neighbour
  /// holds a zero offset and a non-zero extent, so an offset-only
  /// enumeration would leave it out of both.
  Iterable<int> get activeIds {
    return _held.keys.followedBy(
      _heldExtent.keys.where((id) {
        return !_held.containsKey(id);
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
        minT = _foldClock(minT, slot.snapped, slot.t, slot.from, slot.target);
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
      minT = _foldClock(minT, slot.snapped, slot.t, slot.from, slot.target);
    }
    final current = _valueOfSlot(slot);
    slot
      ..from = snap ? target : current
      ..target = target
      ..snapped = snap
      ..t = 0.0;
    return minT;
  }

  /// The held delta for [id], on the lane axis, zero for no entry.
  Offset deltaOf(int id) {
    final entry = _held[id];
    if (entry == null) {
      return Offset.zero;
    }
    final axis = _laneAxisOf();
    if (axis == null) {
      return Offset.zero;
    }
    final value = _valueOf(entry);
    return axis == Axis.vertical ? Offset(0.0, value) : Offset(value, 0.0);
  }

  /// Opens (or re-targets) the gap for a drag of [draggedId] resolving to
  /// [prospective]. Never refuses: under a zero family it INSTALLS AND
  /// SNAPS, because the gap IS the target state and section 9.5 names no
  /// other drop-feedback mechanism. The snap flag is the kill-switch
  /// disjunction, resolved here, at one of the family's two declaring
  /// sites; [duration] and [curve] are a session's captured values and
  /// the flag dominates them.
  void previewGap({
    required int draggedId,
    required BoardSpan prospective,
    bool lifted = false,
    Duration? duration,
    Curve? curve,
  }) {
    final laneAxis = _laneAxisOf();
    final spec = _styleOf().effectiveMakeRoom;
    final resolved = duration ?? spec.duration;
    final snap = spec.duration == Duration.zero || resolved == Duration.zero;
    _adoptClock(curve ?? spec.curve, resolved);
    // The dry run needs lane geometry; without it nothing is laned and
    // no gap exists to open, but the EXTENT preview below still does.
    final dry = laneAxis == null
        ? const <int, ({int lane, int laneCount, int laneSpan})>{}
        : _dryRunOf(draggedId, prospective);
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
    // of the drag's in-place feedback.
    final extentTargets = <int, Offset>{};
    if (!lifted) {
      final assignment = dry[draggedId];
      extentTargets[draggedId] = _prospectiveExtentOf(
        draggedId,
        prospective,
        assignment,
      );
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
      final existing = _heldExtent[id];
      if (extent == Offset.zero && existing == null) {
        // Nothing to hold.
        return;
      }
      if (snap) {
        // The same fold the offsets' snap arm makes, in the inline form
        // the release arm uses for an Offset entry.
        if (existing != null &&
            !existing.snapped &&
            existing.t < 1.0 &&
            existing.from != existing.target) {
          final current = minT;
          minT = current == null || existing.t < current ? existing.t : current;
        }
        _heldExtent[id] = _HeldExtent(
          target: extent,
          from: extent,
          snapped: true,
        );
      } else if (existing == null || existing.target != extent) {
        _heldExtent[id] = _HeldExtent(
          target: extent,
          from: existing == null ? Offset.zero : extentDeltaOf(id),
          snapped: false,
        );
      }
    });
    if (laneAxis == null) {
      // No lane geometry exists to open a gap in; the extent preview
      // above is the whole of the in-place feedback on such a board, and
      // the drag proxy is the rest of it. The fold is discarded
      // unpublished here, as it always was on this branch: the case is a
      // restyle to zero mid-drag on a board with no lanes.
      _heldExtent.removeWhere((id, entry) {
        return snap && entry.target == Offset.zero;
      });
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
      if (id == draggedId && lifted) {
        // A LIFTED (moved) item paints as the proxy, not as a gap. A
        // resize is not lifted and keeps its own held offset. The
        // discriminator is the session's argument, NOT the dragging bit:
        // that bit is set for every session and carries no kind.
        return;
      }
      final target =
          _laneOriginOfId(id, assignment.lane, assignment.laneCount) -
          _laneOriginOfId(id, _laneOfId(id), _laneCountOfId(id));
      if (target != 0.0) {
        targets[id] = target;
      }
    });
    // The dragged item's DE-LANING arm: prospectively unlaned, so absent
    // from the dry result, while its stored lane holds a slice it is
    // growing out of. Its held offset carries it onto the track's
    // leading edge.
    if (!dry.containsKey(draggedId) &&
        !lifted &&
        (_laneOfId(draggedId) != 0 || _laneCountOfId(draggedId) != 1)) {
      final target =
          _laneOriginOfId(draggedId, 0, 1) -
          _laneOriginOfId(
            draggedId,
            _laneOfId(draggedId),
            _laneCountOfId(draggedId),
          );
      if (target != 0.0) {
        targets[draggedId] = target;
      }
    }
    // Entries not re-targeted close back to zero.
    for (final id in _held.keys) {
      targets.putIfAbsent(id, () {
        return 0.0;
      });
    }
    targets.forEach((id, target) {
      final existing = _held[id];
      if (target == 0.0 && existing == null) {
        return;
      }
      if (!snap && existing != null && existing.target == target) {
        // IDEMPOTENT FOR AN UNCHANGED TARGET. A free or fraction snap
        // re-enters this method on every frame of the resize it caused,
        // and restarting every clock there means the gap never settles
        // and the ticker never stops. The SNAP arm still replaces
        // unconditionally: the kill switch dominates a captured value,
        // so a re-send under a zero family must force instant arrival.
        return;
      }
      final from = existing == null ? 0.0 : _valueOf(existing);
      if (snap) {
        if (existing != null) {
          minT = _foldClock(
            minT,
            existing.snapped,
            existing.t,
            existing.from,
            existing.target,
          );
        }
        _held[id] = _HeldOffset(target: target, from: target, snapped: true);
      } else {
        _held[id] = _HeldOffset(target: target, from: from, snapped: false);
      }
    });
    if (lifted) {
      if (_liftedId != null && _liftedId != draggedId) {
        // A PREVIOUS session's item, whose closing slot is still ramping
        // down. Snap-drop it, or its phantom occupancy outlives the
        // session that owned it, on a track it never reached. A LIFTED
        // install for the SAME id takes the re-target path below.
        minT = _discardSlots(minT);
      }
      // Both halves of the desired slot's identity come from inputs this
      // method already has: the TRACK from `prospective` on the lane
      // axis, the LANE from the dry run, present exactly when the run
      // laned the dragged id.
      final prospectiveTrack = trackIndexOf(prospective.startTrackOn(laneAxis));
      final desiredLane = dry[draggedId]?.lane;
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
      _held.removeWhere((id, entry) {
        return entry.target == 0.0;
      });
      _heldExtent.removeWhere((id, entry) {
        return entry.target == Offset.zero;
      });
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

  /// The install's snap tail for slots: every slot lands on its target,
  /// and a slot at 0 is removed. Either lands a slot that was still
  /// mid-motion without ramping it there, so both fold into [minT].
  double? _snapSlots(double? minT) {
    _slots.removeWhere((track, slots) {
      slots.removeWhere((slot) {
        minT = _foldClock(minT, slot.snapped, slot.t, slot.from, slot.target);
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

  /// Closes every held offset. The release side reads the SAME snap
  /// disjunction as the install, so a zero-family drag's gap opens and
  /// closes instantly as a pair.
  void releasePreview({Duration? duration, Curve? curve}) {
    // THREE COLLECTIONS, not one: a slot-only hover holds no offset at
    // all, and an `_held`-only guard would return without clearing the
    // slots, leaving the target track's phantom occupancy standing for
    // the rest of the board's life.
    if (_held.isEmpty &&
        _slots.isEmpty &&
        _liftedId == null &&
        _heldExtent.isEmpty) {
      return;
    }
    final spec = _styleOf().effectiveMakeRoom;
    final resolved = duration ?? spec.duration;
    final snap = spec.duration == Duration.zero || resolved == Duration.zero;
    if (snap) {
      // The commit's snap: fold every offset and slot it drops, so the
      // hand-off carries the clock of whatever was still moving.
      double? minT;
      for (final entry in _held.values) {
        minT = _foldClock(
          minT,
          entry.snapped,
          entry.t,
          entry.from,
          entry.target,
        );
      }
      for (final entry in _heldExtent.values) {
        // The same fold the offsets get, on the same three terms: an
        // entry unsnapped, below clock 1 and actually moving had motion
        // left, and the earliest such clock is the one the hand-off
        // continues from.
        if (!entry.snapped && entry.t < 1.0 && entry.from != entry.target) {
          minT = minT == null || entry.t < minT ? entry.t : minT;
        }
      }
      _held.clear();
      _heldExtent.clear();
      minT = _discardSlots(minT);
      _publishSnap(minT);
      _generation += 1;
      _stopIfIdle();
      _notifyNow();
      return;
    }
    _adoptClock(curve ?? spec.curve, resolved);
    _held.forEach((id, entry) {
      final current = _valueOf(entry);
      entry
        ..target = 0.0
        ..from = current
        ..snapped = false
        ..t = 0.0;
    });
    _heldExtent.forEach((id, entry) {
      final current = extentDeltaOf(id);
      entry
        ..target = Offset.zero
        ..from = current
        ..snapped = false
        ..t = 0.0;
    });
    _slots.forEach((track, slots) {
      for (final slot in slots) {
        // One already closing keeps the schedule it started on, the same
        // idempotence rule the install applies and for the same reason.
        _retargetSlot(slot, 0.0, false, null);
      }
    });
    if (_slots.isEmpty) {
      // The release of a session that never got a slot; otherwise the
      // key is cleared at the settle, when `_tick` removes the last one.
      _liftedId = null;
    }
    _generation += 1;
    _ensureTicking();
  }

  void clearForId(int id) {
    // THIS REMOVAL NEVER BUMPS THE SNAP GENERATION, on either branch: an
    // offset has a paint half.
    var removed = _held.remove(id) != null;
    removed = _heldExtent.remove(id) != null || removed;
    if (id == _liftedId) {
      removed = removed || _slots.isNotEmpty;
      _discardSlots(null);
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
    // The captured clock, under the live family's zero: a restyle to
    // zero mid-gap drives every clock past 1 on this tick.
    final spec = _styleOf().effectiveMakeRoom;
    final durationUs = spec.duration == Duration.zero
        ? 0
        : _duration.inMicroseconds;
    final delta = durationUs == 0
        ? double.infinity
        : dt.inMicroseconds / durationUs;
    var anyClosed = false;
    _heldExtent.forEach((id, entry) {
      if (entry.snapped || entry.t >= 1.0) {
        return;
      }
      entry.t += delta;
      if (entry.t >= 1.0 && entry.target == Offset.zero) {
        anyClosed = true;
      }
    });
    _held.forEach((id, entry) {
      if (entry.snapped || entry.t >= 1.0) {
        return;
      }
      entry.t += delta;
      if (entry.t >= 1.0 && entry.target == 0.0) {
        anyClosed = true;
      }
    });
    // Both iterations complete before the first dispatch.
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
    _held.removeWhere((id, entry) {
      return entry.t >= 1.0 && entry.target == 0.0;
    });
    _heldExtent.removeWhere((id, entry) {
      return entry.t >= 1.0 && entry.target == Offset.zero;
    });
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

  void dispose() {
    _ticker.dispose();
  }
}
