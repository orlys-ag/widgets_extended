/// Internal: the trackResize animation source.
///
/// One state per resizing track, per axis. The axis already holds the
/// TARGET extent when a state is installed (the install site records the
/// measurement first), so this source only answers what a track's PAINTED
/// extent is mid-flight; dropping a state lands the settled geometry.
///
/// Not exported from the module barrel.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import 'board_animation_style.dart';

class _TrackResizeState {
  _TrackResizeState({
    required this.from,
    required this.to,
    required this.family,
    required this.explicitDuration,
    required this.explicitCurve,
  });

  final double from;
  final double to;

  /// The family whose spec times and shapes this state: trackResize for
  /// a settled-structure resize, makeRoom for a residue the track-sizing
  /// hand-off arm continues on the make-room clock. Read live at every
  /// tick, so the family's zero dominates [explicitDuration].
  final BoardAnimationFamily family;

  /// A captured duration and curve, or null for the family's own.
  final Duration? explicitDuration;
  final Curve? explicitCurve;

  /// The 0-to-1 animation clock, advanced by tick deltas.
  double t = 0.0;
}

/// Owns the per-track resize states and their one ticker.
class TrackResizeAnimator {
  TrackResizeAnimator({
    required TickerProvider vsync,
    required BoardAnimationStyle Function() styleOf,
    required double Function(Axis axis, int track) settledExtentOf,
    required void Function() onTick,
  }) : _styleOf = styleOf,
       _settledExtentOf = settledExtentOf,
       _onTick = onTick {
    _ticker = vsync.createTicker(_tick);
  }

  final BoardAnimationStyle Function() _styleOf;
  final double Function(Axis axis, int track) _settledExtentOf;
  final void Function() _onTick;

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  final Map<int, _TrackResizeState> _vertical = <int, _TrackResizeState>{};
  final Map<int, _TrackResizeState> _horizontal = <int, _TrackResizeState>{};

  Map<int, _TrackResizeState> _statesOf(Axis axis) {
    return axis == Axis.vertical ? _vertical : _horizontal;
  }

  bool get hasActive {
    return _vertical.isNotEmpty || _horizontal.isNotEmpty;
  }

  /// Installs or RE-TARGETS a resize. Refuses under a zero [family] or a
  /// zero [duration]: the axis already holds the target, so a refusal
  /// lands the new geometry on the same frame. A re-target overwrites
  /// rather than stacking; the caller captures [from] from the currently
  /// painted extent, which is what makes the overwrite compose. [family]
  /// defaults to trackResize; the track-sizing hand-off arm passes
  /// makeRoom with the snap's remaining [duration] and curve tail, so a
  /// residue runs on the clock the gap was on.
  void animateTrackResize(
    Axis axis,
    int track,
    double from,
    double to, {
    BoardAnimationFamily family = BoardAnimationFamily.trackResize,
    Duration? duration,
    Curve? curve,
  }) {
    final spec = _styleOf().specFor(family);
    if (spec.duration == Duration.zero ||
        (duration ?? spec.duration) == Duration.zero) {
      return;
    }
    _statesOf(axis)[track] = _TrackResizeState(
      from: from,
      to: to,
      family: family,
      explicitDuration: duration,
      explicitCurve: curve,
    );
    _ensureTicking();
  }

  /// The painted extent: the settled one unless a state is in flight.
  double animatedExtentOf(Axis axis, int track) {
    final state = _statesOf(axis)[track];
    if (state == null) {
      return _settledExtentOf(axis, track);
    }
    final curve =
        state.explicitCurve ?? _styleOf().specFor(state.family).curve;
    final eased = curve.transform(state.t.clamp(0.0, 1.0));
    return state.from + (state.to - state.from) * eased;
  }

  /// Sum over the in-flight states on [axis] in `[fromTrack, track)` of
  /// the animated-minus-settled extent difference: how far [track]'s
  /// painted offset sits from its settled one. [fromTrack] is the
  /// window's first track: the accumulation starts THERE, anchored at its
  /// settled offset, so a resize before the window is invisible.
  double offsetShiftBetween(Axis axis, int fromTrack, int track) {
    var shift = 0.0;
    _statesOf(axis).forEach((stateTrack, state) {
      if (stateTrack >= fromTrack && stateTrack < track) {
        shift += animatedExtentOf(axis, stateTrack) -
            _settledExtentOf(axis, stateTrack);
      }
    });
    return shift;
  }

  /// Drops every in-flight state, landing each track at its target, which
  /// the axis already stores. The anti-stranding arm of the restyle
  /// transition and of a controller swap; a PURGE would be identical
  /// here, but the name states the intent: nothing is abandoned
  /// mid-lattice.
  /// [axis] narrows the snap to one axis's states: an axis swap
  /// invalidates only the swapped lattice, and extents animating against
  /// the OTHER one are still evidence.
  void finalizeAll({Axis? axis}) {
    if (axis == null || axis == Axis.vertical) {
      _vertical.clear();
    }
    if (axis == null || axis == Axis.horizontal) {
      _horizontal.clear();
    }
    _stopIfIdle();
  }

  /// [finalizeAll]'s body narrowed to ONE track: the door the track
  /// sizing step's make-room latch EDGE hands an in-flight resize in
  /// through. A track holding no state is a no-op, so no caller needs a
  /// residue test. It dispatches NOTHING, which is what makes it callable
  /// from inside layout like the install beside it; the only reachable
  /// side effect is the ticker stop.
  void finalizeTrack(Axis axis, int track) {
    _statesOf(axis).remove(track);
    _stopIfIdle();
  }

  void _ensureTicking() {
    if (!_ticker.isActive && hasActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
  }

  void _stopIfIdle() {
    if (_ticker.isActive && !hasActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    final style = _styleOf();
    for (final states in <Map<int, _TrackResizeState>>[
      _vertical,
      _horizontal,
    ]) {
      states.forEach((track, state) {
        final spec = style.specFor(state.family);
        // The family's zero dominates the state's explicit duration: a
        // restyle to zero between two ticks drives every state past 1
        // here rather than dividing by zero.
        final effective = spec.duration == Duration.zero
            ? Duration.zero
            : (state.explicitDuration ?? spec.duration);
        final durationUs = effective.inMicroseconds;
        state.t += durationUs == 0
            ? double.infinity
            : dt.inMicroseconds / durationUs;
      });
      states.removeWhere((track, state) {
        return state.t >= 1.0;
      });
    }
    _stopIfIdle();
    // Coalesced dispatch: a settle tick's record is already gone when the
    // deferred callback runs, which is what the render object's
    // prior-tick latch exists for.
    _onTick();
  }

  void dispose() {
    _ticker.dispose();
  }
}
