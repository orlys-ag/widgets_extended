/// Internal: the makeRoom animation source.
///
/// HELD paint-only gap offsets: an entry animates to a non-zero target and
/// then PERSISTS until re-targeted or released, which is what makes the
/// gap the target state rather than a transient toward one. The offsets
/// come from a DRY-RUN lane resolution over at most two lane-axis
/// buckets, supplied by the controller; the model is never written.
///
/// Beside the offsets the engine holds prospective lane SLOTS for the
/// LIFTED item: a slot has no paint half at all and exists only so the
/// track-sizing walk can count the lane the drop would occupy. An
/// install is IDEMPOTENT for an unchanged target, which is what lets a
/// closing entry ever retire under a per-frame re-resolve.
///
/// Not exported from the module barrel.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '_board_span.dart';
import 'board_animation_style.dart';

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
    required Axis? Function() laneAxisOf,
    required Map<int, ({int lane, int laneCount})> Function(
      int draggedId,
      BoardSpan prospective,
    )
    dryRunOf,
    required double Function(int id, int lane, int laneCount) laneOriginOfId,
    required int Function(int id) laneOfId,
    required int Function(int id) laneCountOfId,
  }) : _styleOf = styleOf,
       _notifyNow = notifyNow,
       _laneAxisOf = laneAxisOf,
       _dryRunOf = dryRunOf,
       _laneOriginOfId = laneOriginOfId,
       _laneOfId = laneOfId,
       _laneCountOfId = laneCountOfId {
    _ticker = vsync.createTicker(_tick);
  }

  final BoardAnimationStyle Function() _styleOf;

  /// The UNCOALESCED dispatch. Load-bearing on both snap arms: a snapped
  /// install starts no ticker, so without this notify nothing repaints
  /// and a gap past the admitted bound opens over children that were
  /// never built.
  final void Function() _notifyNow;

  final Axis? Function() _laneAxisOf;
  final Map<int, ({int lane, int laneCount})> Function(
    int draggedId,
    BoardSpan prospective,
  )
  _dryRunOf;
  final double Function(int id, int lane, int laneCount) _laneOriginOfId;
  final int Function(int id) _laneOfId;
  final int Function(int id) _laneCountOfId;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  final Map<int, _HeldOffset> _held = <int, _HeldOffset>{};

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

  bool get hasActive {
    return _held.isNotEmpty;
  }

  /// Any offset or slot unsnapped with clock below 1.
  bool get hasMotion {
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

  /// Bumped when a snap arm or [clearForId] discards a SLOT whose
  /// [_Slot.snapped] flag is FALSE, and for nothing else. NEVER by an
  /// offset, on any arm: an offset has a paint half, so discarding one
  /// steps the term and the item's painted position in the same frame,
  /// and routing that step to a trackResize would animate the track's
  /// edge behind content that has already moved.
  int get snapGeneration {
    return _snapGeneration;
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

  /// The ids holding entries, for the composed per-id bound.
  Iterable<int> get activeIds {
    return _held.keys;
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

  /// Drops every slot and the lifecycle key with them, bumping the snap
  /// generation when any discarded slot was still unsnapped. The two
  /// callers are a LIFTED first install for a DIFFERENT id and the snap
  /// release arm.
  void _discardSlots() {
    var discardedUnsnapped = false;
    for (final slots in _slots.values) {
      for (final slot in slots) {
        if (!slot.snapped) {
          discardedUnsnapped = true;
        }
      }
    }
    _slots.clear();
    _liftedId = null;
    if (discardedUnsnapped) {
      _snapGeneration += 1;
    }
  }

  /// Re-targets one slot, LEAVING IT UNTOUCHED when its target already
  /// equals [target] and the install is not a snap. That idempotence is
  /// what lets a closing slot decay on the schedule it started on, so
  /// `_tick` can retire it under a per-frame re-resolve.
  void _retargetSlot(_Slot slot, double target, bool snap) {
    if (!snap && slot.target == target) {
      return;
    }
    final current = _valueOfSlot(slot);
    slot
      ..from = snap ? target : current
      ..target = target
      ..snapped = snap
      ..t = 0.0;
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

  /// PER-AXIS magnitudes over the held set, independently.
  ({double dx, double dy}) get bound {
    var dx = 0.0;
    var dy = 0.0;
    for (final id in _held.keys) {
      final delta = deltaOf(id);
      if (delta.dx.abs() > dx) {
        dx = delta.dx.abs();
      }
      if (delta.dy.abs() > dy) {
        dy = delta.dy.abs();
      }
    }
    return (dx: dx, dy: dy);
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
    if (laneAxis == null) {
      // No lane geometry exists to open; the drag proxy is the whole of
      // the feedback on such a board.
      return;
    }
    final spec = _styleOf().effectiveMakeRoom;
    final resolved = duration ?? spec.duration;
    final snap = spec.duration == Duration.zero || resolved == Duration.zero;
    _curve = curve ?? spec.curve;
    final dry = _dryRunOf(draggedId, prospective);
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
        _discardSlots();
      }
      // Both halves of the desired slot's identity come from inputs this
      // method already has: the TRACK from `prospective` on the lane
      // axis, the LANE from the dry run, present exactly when the run
      // laned the dragged id.
      final prospectiveTrack = prospective.startTrackOn(laneAxis).floor();
      final desiredLane = dry[draggedId]?.lane;
      _slots.forEach((track, slots) {
        for (final slot in slots) {
          final desired =
              desiredLane != null &&
                  track == prospectiveTrack &&
                  slot.lane == desiredLane
              ? 1.0
              : 0.0;
          _retargetSlot(slot, desired, snap);
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
      _snapSlots();
      _notifyNow();
      return;
    }
    _ensureTicking();
  }

  /// The install's snap tail for slots: every slot lands on its target,
  /// and a slot at 0 is removed. A removal of a slot that was still
  /// UNSNAPPED steps the term without ramping it there, which is the one
  /// case that bumps the snap generation.
  void _snapSlots() {
    var discardedUnsnapped = false;
    _slots.removeWhere((track, slots) {
      slots.removeWhere((slot) {
        if (slot.target != 0.0) {
          slot.snapped = true;
          return false;
        }
        if (!slot.snapped) {
          discardedUnsnapped = true;
        }
        return true;
      });
      return slots.isEmpty;
    });
    if (discardedUnsnapped) {
      _snapGeneration += 1;
    }
    if (_slots.isEmpty) {
      _liftedId = null;
    }
  }

  /// Closes every held offset. The release side reads the SAME snap
  /// disjunction as the install, so a zero-family drag's gap opens and
  /// closes instantly as a pair.
  void releasePreview({Duration? duration, Curve? curve}) {
    // THREE COLLECTIONS, not one: a slot-only hover holds no offset at
    // all, and an `_held`-only guard would return without clearing the
    // slots, leaving the target track's phantom occupancy standing for
    // the rest of the board's life.
    if (_held.isEmpty && _slots.isEmpty && _liftedId == null) {
      return;
    }
    final spec = _styleOf().effectiveMakeRoom;
    final resolved = duration ?? spec.duration;
    final snap = spec.duration == Duration.zero || resolved == Duration.zero;
    if (snap) {
      _held.clear();
      _discardSlots();
      _generation += 1;
      _stopIfIdle();
      _notifyNow();
      return;
    }
    _curve = curve ?? spec.curve;
    _held.forEach((id, entry) {
      final current = _valueOf(entry);
      entry
        ..target = 0.0
        ..from = current
        ..snapped = false
        ..t = 0.0;
    });
    _slots.forEach((track, slots) {
      for (final slot in slots) {
        // One already closing keeps the schedule it started on, the same
        // idempotence rule the install applies and for the same reason.
        _retargetSlot(slot, 0.0, false);
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
    if (id == _liftedId) {
      removed = removed || _slots.isNotEmpty;
      _discardSlots();
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
    final spec = _styleOf().effectiveMakeRoom;
    final durationUs = spec.duration.inMicroseconds;
    final delta = durationUs == 0
        ? double.infinity
        : dt.inMicroseconds / durationUs;
    var anyClosed = false;
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
    // Same settle protocol as the slide engine: deltas observed at their
    // settled values before a closing entry is removed, then the
    // idle transition.
    _notifyNow();
    if (anyClosed) {
      _held.removeWhere((id, entry) {
        return entry.t >= 1.0 && entry.target == 0.0;
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
    }
    _stopIfIdle();
  }

  void dispose() {
    _ticker.dispose();
  }
}
