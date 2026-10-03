/// Internal: the trackResize animation source.
///
/// One state per resizing track, per axis. A state holds a RESIDUAL, not
/// a from and a to: the painted extent at install minus the settled
/// extent the axis stored then. The painted extent is the axis's CURRENT
/// settled extent plus that residual decayed by the eased clock, so this
/// source answers only how far a track's paint still is from its settled
/// geometry, and dropping a state lands that geometry.
///
/// Storing the residual rather than the target is what lets a settled
/// write compose with a state in flight: the write shows at once and the
/// residual keeps decaying on its own clock. A stored target would hide
/// every later write until the state ended, and then step to it.
///
/// Not exported from the module barrel.
library;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import 'board_animation_style.dart';

/// One axis's SHIFT PREFIX: the in-flight tracks in ascending order and a
/// running sum of each one's animated-minus-settled extent difference, so
/// the sum over any track range is one subtraction of two entries.
///
/// `sums` has one more entry than `tracks`, `sums[0]` being 0.0, which is
/// what makes the empty prefix and the whole-range query fall out of the
/// same expression. `settled` keeps what each entry was built from, for
/// the debug guard that catches a settled write with no invalidation.
class _ShiftPrefix {
  Int32List tracks = Int32List(0);
  Float64List sums = Float64List(1);
  Float64List settled = Float64List(0);

  /// Whether the cache holds a build. False after [invalidate] and before
  /// the first one.
  bool valid = false;

  /// The animator generation and the style INSTANCE the build read. A
  /// restyle re-curves a state without a generation bump, so the second
  /// is not redundant.
  int generation = -1;
  BoardAnimationStyle? style;

  int get length {
    return tracks.length;
  }

  void invalidate() {
    valid = false;
    style = null;
  }

  /// Rebuilds from [states]: the keys sorted ascending, then one pass
  /// accumulating the differences. O(S log S) for S states, once per
  /// generation rather than once per read.
  void rebuild(
    Map<int, Object?> states, {
    required int generation,
    required BoardAnimationStyle style,
    required double Function(int track) animatedExtentOf,
    required double Function(int track) settledExtentOf,
  }) {
    final count = states.length;
    if (tracks.length != count) {
      tracks = Int32List(count);
      sums = Float64List(count + 1);
      settled = Float64List(count);
    }
    var at = 0;
    for (final track in states.keys) {
      tracks[at++] = track;
    }
    // `sort` on a typed list is the same introsort a `List<int>` gets and
    // allocates nothing beyond it.
    tracks.sort();
    var running = 0.0;
    sums[0] = 0.0;
    for (var i = 0; i < count; i++) {
      final track = tracks[i];
      final settledExtent = settledExtentOf(track);
      settled[i] = settledExtent;
      running += animatedExtentOf(track) - settledExtent;
      sums[i + 1] = running;
    }
    this.generation = generation;
    this.style = style;
    valid = true;
  }

  /// The number of cached tracks strictly below [track], which is the
  /// index into [sums] of the sum over everything before it. Counts each
  /// comparison on [owner]'s probe counter.
  int lowerBound(int track, TrackResizeAnimator owner) {
    var low = 0;
    var high = tracks.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      owner.debugShiftProbeCount++;
      if (tracks[mid] < track) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}

class _TrackResizeState {
  _TrackResizeState({
    required this.residual,
    required this.family,
    required this.explicitDuration,
    required this.explicitCurve,
  });

  /// The painted extent at install minus the settled extent at install.
  /// Decays to zero on the eased clock.
  final double residual;

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

  /// Debug-only: calls to [offsetShiftBetween] since the last reset.
  /// After the prefix cache each call costs two binary searches rather
  /// than a walk, so this counts CALLS and [debugShiftProbeCount] counts
  /// the work; a case that wants the cost reads the second.
  int debugShiftCallCount = 0;

  /// Debug-only: comparisons the two lower-bound searches of
  /// [offsetShiftBetween] have made since the last reset. It is the only
  /// thing that separates the prefix from the walk it replaced, which
  /// return the same number; same justification as `_span_index.dart`'s
  /// `debugProbeCount`. The debug guard's settled re-reads are NOT
  /// counted here: they do not exist in a release build.
  int debugShiftProbeCount = 0;

  /// Bumped by every door that mutates a state: install, both finalize
  /// forms, and the tick. The prefix cache rebuilds when it differs from
  /// the generation the cache was built at.
  int _generation = 0;

  final Map<int, _TrackResizeState> _vertical = <int, _TrackResizeState>{};
  final Map<int, _TrackResizeState> _horizontal = <int, _TrackResizeState>{};

  /// The prefix cache, one per axis. Built lazily by [_prefixOf].
  final _ShiftPrefix _verticalPrefix = _ShiftPrefix();
  final _ShiftPrefix _horizontalPrefix = _ShiftPrefix();

  Map<int, _TrackResizeState> _statesOf(Axis axis) {
    return axis == Axis.vertical ? _vertical : _horizontal;
  }

  _ShiftPrefix _prefixSlotOf(Axis axis) {
    return axis == Axis.vertical ? _verticalPrefix : _horizontalPrefix;
  }

  bool get hasActive {
    return _vertical.isNotEmpty || _horizontal.isNotEmpty;
  }

  /// Installs or RE-TARGETS a resize from the painted extent [from] to
  /// the settled extent the axis ALREADY stores: the caller records the
  /// target first and captures [from] before recording it. A re-target
  /// overwrites rather than stacking, and [from] being what paints is
  /// what makes the overwrite compose. [family] defaults to trackResize;
  /// the track-sizing hand-off arm passes makeRoom with the snap's
  /// remaining [duration] and curve tail, so a residue runs on the clock
  /// the gap was on.
  ///
  /// Two outcomes install nothing, in this order:
  ///
  /// - A residual within `precisionErrorTolerance` is NO MOTION: the
  ///   track already paints its settled extent, so any state it holds is
  ///   DROPPED, which is continuous by that same fact. A state kept there
  ///   would add its residual on top of an extent that already arrived.
  /// - A zero [family] or a zero [duration] REFUSES: the call creates no
  ///   motion, so the new geometry lands this frame, and it destroys none,
  ///   so a state already in flight for the track keeps decaying its
  ///   residual from the new settled extent.
  void animateTrackResize(
    Axis axis,
    int track,
    double from, {
    BoardAnimationFamily family = BoardAnimationFamily.trackResize,
    Duration? duration,
    Curve? curve,
  }) {
    _generation++;
    final residual = from - _settledExtentOf(axis, track);
    if (residual.abs() <= precisionErrorTolerance) {
      _statesOf(axis).remove(track);
      _stopIfIdle();
      return;
    }
    final spec = _styleOf().specFor(family);
    if (spec.duration == Duration.zero ||
        (duration ?? spec.duration) == Duration.zero) {
      return;
    }
    _statesOf(axis)[track] = _TrackResizeState(
      residual: residual,
      family: family,
      explicitDuration: duration,
      explicitCurve: curve,
    );
    _ensureTicking();
  }

  /// The painted extent: the settled one plus the residual of a state in
  /// flight, decayed by its eased clock.
  ///
  /// FLOORED AT ZERO HERE, at the producer, as the enter/exit ramp is
  /// clamped at its own: an overshooting curve (`Curves.easeOutBack`)
  /// carries a shrinking track past its target, and past zero when the
  /// target is small, which would reach layout as a negative constraint.
  /// A floor and not a clamp of the eased value, so a growing track keeps
  /// the curve's overshoot, which is valid geometry.
  double animatedExtentOf(Axis axis, int track) {
    final settled = _settledExtentOf(axis, track);
    final state = _statesOf(axis)[track];
    if (state == null) {
      return settled;
    }
    final curve =
        state.explicitCurve ?? _styleOf().specFor(state.family).curve;
    final eased = curve.transform(state.t.clamp(0.0, 1.0));
    final painted = settled + state.residual * (1.0 - eased);
    return painted < 0.0 ? 0.0 : painted;
  }

  /// Sum over the in-flight states on [axis] in `[fromTrack, track)` of
  /// the animated-minus-settled extent difference: how far [track]'s
  /// painted offset sits from its settled one. [fromTrack] is the
  /// window's first track: the accumulation starts THERE, anchored at its
  /// settled offset, so a resize before the window is invisible.
  ///
  /// Answered from a PREFIX over the axis's in-flight tracks, so the cost
  /// is two lower-bound searches rather than a walk of every state. The
  /// prefix is rebuilt by the first query after any state mutation, so a
  /// frame's many reads share one build; see [_prefixOf].
  double offsetShiftBetween(Axis axis, int fromTrack, int track) {
    debugShiftCallCount++;
    // The EMPTY RANGE, which the walk this replaced answered 0.0 for and
    // a subtraction of two bounds would answer a negation for. Reachable:
    // a retained exit or the drag pin can sit before the window's floor
    // and the item geometry rule reads the shift at its start track.
    if (track <= fromTrack) {
      return 0.0;
    }
    final prefix = _prefixOf(axis);
    if (prefix.length == 0) {
      return 0.0;
    }
    return prefix.sums[prefix.lowerBound(track, this)] -
        prefix.sums[prefix.lowerBound(fromTrack, this)];
  }

  /// Drops both axes' prefix caches.
  ///
  /// The door for a SETTLED write: the prefix captures settled extents,
  /// and layout's `recordMeasurement` moves one without touching a state,
  /// so the render calls this through the controller wherever it records.
  /// Every other invalidation rides [_generation] or the style identity.
  void invalidateShiftCache() {
    _verticalPrefix.invalidate();
    _horizontalPrefix.invalidate();
  }

  /// The axis's prefix, rebuilt when the generation moved, when the style
  /// INSTANCE changed (a restyle re-curves a state with no bump), or when
  /// [invalidateShiftCache] dropped it.
  ///
  /// Debug builds re-read every captured settled extent on every serve
  /// and assert it is unchanged, which is the assert form of the rule
  /// that a settled write invalidates.
  _ShiftPrefix _prefixOf(Axis axis) {
    final prefix = _prefixSlotOf(axis);
    final style = _styleOf();
    if (!prefix.valid ||
        prefix.generation != _generation ||
        !identical(prefix.style, style)) {
      prefix.rebuild(
        _statesOf(axis),
        generation: _generation,
        style: style,
        animatedExtentOf: (track) {
          return animatedExtentOf(axis, track);
        },
        settledExtentOf: (track) {
          return _settledExtentOf(axis, track);
        },
      );
      return prefix;
    }
    assert(() {
      for (var i = 0; i < prefix.length; i++) {
        final track = prefix.tracks[i];
        final settled = _settledExtentOf(axis, track);
        if ((settled - prefix.settled[i]).abs() > precisionErrorTolerance) {
          throw FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary(
              "TrackResizeAnimator served a stale shift prefix on "
              "$axis track $track.",
            ),
            ErrorDescription(
              "The prefix captured a settled extent of "
              "${prefix.settled[i]} and the axis now reports $settled. "
              "The prefix is a function of the settled extents it was "
              "built from, so a site that writes one must invalidate it.",
            ),
            ErrorHint(
              "Call BoardController.invalidateAnimatedShifts() from "
              "whichever site recorded the measurement.",
            ),
          ]);
        }
      }
      return true;
    }());
    return prefix;
  }

  /// Drops every in-flight state, landing each track at the settled
  /// extent the axis stores. The anti-stranding arm of an axis swap; a
  /// PURGE would be identical here, but the name states the intent:
  /// nothing is abandoned mid-lattice.
  /// [axis] narrows the snap to one axis's states: an axis swap
  /// invalidates only the swapped lattice, and extents animating against
  /// the OTHER one are still evidence.
  void finalizeAll({Axis? axis}) {
    _generation++;
    if (axis == null || axis == Axis.vertical) {
      _vertical.clear();
    }
    if (axis == null || axis == Axis.horizontal) {
      _horizontal.clear();
    }
    _stopIfIdle();
  }

  /// Drops, landing at its settled extent, every state whose family [off]
  /// answers true for, and returns whether any went. The restyle
  /// transition: the controller passes the families the NEW style
  /// resolves to zero, so a family restyled to zero stops its own motion
  /// and no other's. It dispatches nothing; the caller notifies.
  bool finalizeWhere(bool Function(BoardAnimationFamily family) off) {
    var removed = false;
    for (final states in <Map<int, _TrackResizeState>>[
      _vertical,
      _horizontal,
    ]) {
      states.removeWhere((track, state) {
        if (off(state.family)) {
          removed = true;
          return true;
        }
        return false;
      });
    }
    if (removed) {
      _generation++;
      _stopIfIdle();
    }
    return removed;
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
    _generation++;
    final dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    final style = _styleOf();
    for (final states in <Map<int, _TrackResizeState>>[
      _vertical,
      _horizontal,
    ]) {
      states.forEach((track, state) {
        final spec = style.specFor(state.family);
        // The family's zero dominates the state's explicit duration. The
        // restyle to zero stops a family's states in the setter, so this
        // is the guard against a division by zero rather than the
        // mechanism: a zero family drives a state past 1 here.
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
