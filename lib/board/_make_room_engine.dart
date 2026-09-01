/// Internal: the makeRoom animation source.
///
/// HELD paint-only gap offsets: an entry animates to a non-zero target and
/// then PERSISTS until re-targeted or released, which is what makes the
/// gap the target state rather than a transient toward one. The offsets
/// come from a DRY-RUN lane resolution over at most two lane-axis
/// buckets, supplied by the controller; the model is never written.
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
  Curve _curve = Curves.linear;

  bool get hasActive {
    return _held.isNotEmpty;
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
    if (_laneAxisOf() == null) {
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
      final from = existing == null ? 0.0 : _valueOf(existing);
      if (snap) {
        _held[id] = _HeldOffset(target: target, from: target, snapped: true);
      } else {
        _held[id] = _HeldOffset(target: target, from: from, snapped: false);
      }
    });
    if (snap) {
      _held.removeWhere((id, entry) {
        return entry.target == 0.0;
      });
      _notifyNow();
      return;
    }
    _ensureTicking();
  }

  /// Closes every held offset. The release side reads the SAME snap
  /// disjunction as the install, so a zero-family drag's gap opens and
  /// closes instantly as a pair.
  void releasePreview({Duration? duration, Curve? curve}) {
    if (_held.isEmpty) {
      return;
    }
    final spec = _styleOf().effectiveMakeRoom;
    final resolved = duration ?? spec.duration;
    final snap = spec.duration == Duration.zero || resolved == Duration.zero;
    if (snap) {
      _held.clear();
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
    _ensureTicking();
  }

  void clearForId(int id) {
    _held.remove(id);
    _stopIfIdle();
  }

  void _ensureTicking() {
    var animating = false;
    for (final entry in _held.values) {
      if (!entry.snapped && entry.t < 1.0) {
        animating = true;
        break;
      }
    }
    if (animating && !_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  }

  void _stopIfIdle() {
    if (!_ticker.isActive) {
      return;
    }
    for (final entry in _held.values) {
      if (!entry.snapped && entry.t < 1.0) {
        return;
      }
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
    // Same settle protocol as the slide engine: deltas observed at their
    // settled values before a closing entry is removed, then the
    // idle transition.
    _notifyNow();
    if (anyClosed) {
      _held.removeWhere((id, entry) {
        return entry.t >= 1.0 && entry.target == 0.0;
      });
      _notifyNow();
    }
    _stopIfIdle();
  }

  void dispose() {
    _ticker.dispose();
  }
}
