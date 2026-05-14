/// Internal: standalone (per-node) animation source for [TreeController].
///
/// Owns the per-frame [Ticker], the dense per-nid `_byNid` array of active
/// [AnimationState]s, and the working-set [Set] used by the tick loop.
/// Per-tick progress updates live here; completion HANDLING (purge, order
/// removal, structural notifications) stays on [TreeController] because it
/// crosses structure / order / notification concerns. The handoff is the
/// constructor-injected [onTick] callback, which fires once per tick AFTER
/// progress has advanced and receives the keys whose animations just
/// completed.
library;

import 'package:flutter/animation.dart' show Curve;
import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;

import '_node_id_registry.dart';
import 'types.dart';

/// Marker value indicating the target extent should be determined from the
/// measured size during layout. Mirrors `_unknownExtent` in the original
/// `_tree_controller_animation.dart` part file.
const double _kUnknownExtent = -1.0;

/// Computes the speed multiplier for proportional timing on cross-source
/// transitions. When a node transitions between animation sources, the
/// remaining animation distance may be less than the full extent; this
/// multiplier ensures the animation completes in proportional wall-clock
/// time. Mirrors `_computeAnimationSpeedMultiplier` in the original part
/// file.
double computeStandaloneSpeedMultiplier(
  double currentExtent,
  double fullExtent,
) {
  if (fullExtent <= 0) {
    return 1.0;
  }
  final fraction = currentExtent / fullExtent;
  if (fraction <= 0 || fraction >= 1.0) {
    return 1.0;
  }
  return (1.0 / fraction).clamp(1.0, 10.0);
}

/// Default extent fallback used when the full extent is unmeasured.
/// Mirrors `TreeController.defaultExtent`. Hard-coded here to avoid a
/// dependency on `tree_controller.dart`; callers must pass the same value
/// via [StandaloneAnimator.fullExtentGetter] for consistency.
const double _kDefaultExtent = 48.0;

class StandaloneAnimator<TKey> {
  StandaloneAnimator({
    required TickerProvider vsync,
    required NodeIdRegistry<TKey> nids,
    required void Function(Iterable<TKey> completedKeys) onTick,
    required Curve Function() animationCurveGetter,
    required Duration Function() animationDurationGetter,
    required double? Function(int nid) fullExtentGetter,
  }) : _vsync = vsync,
       _nids = nids,
       _onTick = onTick,
       _animationCurveGetter = animationCurveGetter,
       _animationDurationGetter = animationDurationGetter,
       _fullExtentGetter = fullExtentGetter;

  final TickerProvider _vsync;
  final NodeIdRegistry<TKey> _nids;
  final void Function(Iterable<TKey> completedKeys) _onTick;
  final Curve Function() _animationCurveGetter;
  final Duration Function() _animationDurationGetter;
  final double? Function(int nid) _fullExtentGetter;

  /// Per-nid animation slot. Null when the node is not animating via the
  /// standalone source. Reads / writes go through [at] / [set] / [clear]
  /// so the [_activeStandaloneNids] working set stays in sync.
  List<AnimationState?> _byNid = <AnimationState?>[];

  /// Live "set of nids that have a non-null _byNid slot." The standalone
  /// ticker iterates this set instead of scanning the whole array.
  final Set<int> _activeNids = <int>{};

  Ticker? _ticker;
  Duration? _lastTickElapsed;

  /// Reusable buffer for the tick loop's completed-key collection. Cleared
  /// at the start of each tick to avoid per-frame allocation.
  final List<TKey> _completedScratch = <TKey>[];

  // ──────────────────────────────────────────────────────────────────────
  // Capacity sync
  // ──────────────────────────────────────────────────────────────────────

  void resizeForCapacity(int newCapacity) {
    if (newCapacity > _byNid.length) {
      final grown = List<AnimationState?>.filled(newCapacity, null);
      for (int i = 0; i < _byNid.length; i++) {
        grown[i] = _byNid[i];
      }
      _byNid = grown;
    }
  }

  /// Per-nid cleanup used by the controller's adopt/release paths.
  /// Idempotent.
  void clearForNid(int nid) {
    if (nid >= 0 && nid < _byNid.length && _byNid[nid] != null) {
      _byNid[nid] = null;
      _activeNids.remove(nid);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Per-key API
  // ──────────────────────────────────────────────────────────────────────

  /// Returns the standalone state for [key], or null if not animating.
  AnimationState? at(TKey key) {
    final nid = _nids[key];
    return nid == null ? null : _byNid[nid];
  }

  /// Direct slot access by nid (read-only). Used by the coordinator's
  /// `ensureAnimatingKeys` to query the standalone contribution to the
  /// union mirrors.
  AnimationState? slotAtNid(int nid) {
    if (nid < 0 || nid >= _byNid.length) return null;
    return _byNid[nid];
  }

  /// Sets the standalone slot for [key]. [key] must be registered.
  /// Maintains [activeNids].
  void set(TKey key, AnimationState state) {
    final nid = _nids[key]!;
    final prev = _byNid[nid];
    _byNid[nid] = state;
    if (prev == null) _activeNids.add(nid);
  }

  /// Clears the standalone slot for [key] and returns the cleared state
  /// (null if absent). Maintains [activeNids]. Named `clearAt` (not
  /// `clear`) to disambiguate from the parameter-less lifecycle [clear].
  AnimationState? clearAt(TKey key) {
    final nid = _nids[key];
    if (nid == null) return null;
    final prev = _byNid[nid];
    if (prev == null) return null;
    _byNid[nid] = null;
    _activeNids.remove(nid);
    return prev;
  }

  /// Whether [key] currently has a standalone animation.
  bool hasAt(TKey key) {
    final nid = _nids[key];
    return nid != null && nid < _byNid.length && _byNid[nid] != null;
  }

  /// Whether any standalone animation is active.
  bool get hasAny => _activeNids.isNotEmpty;

  /// Iterate active nids — used by the coordinator's `ensureAnimatingKeys`
  /// to write the standalone contribution into the union mirrors.
  Iterable<int> get activeNids => _activeNids;

  // ──────────────────────────────────────────────────────────────────────
  // Visible-extent helper for capture sites
  // ──────────────────────────────────────────────────────────────────────

  /// Computes the visible extent for a standalone [AnimationState],
  /// matching the read path in the coordinator's `getCurrentExtentNid`.
  /// When the state's `targetExtent` is unknown (the row hasn't been
  /// measured yet), [AnimationState.currentExtent] holds a stale
  /// negative value; capture sites must use this helper instead of
  /// reading `state.currentExtent` directly.
  double visibleExtent(TKey key, AnimationState state) {
    if (state.targetExtent != _kUnknownExtent) {
      return state.currentExtent;
    }
    final nid = _nids[key];
    final full = (nid != null ? _fullExtentGetter(nid) : null)
        ?? _kDefaultExtent;
    final t = _animationCurveGetter()
        .transform(state.progress.clamp(0.0, 1.0));
    return state.type == AnimationType.entering ? full * t : full * (1.0 - t);
  }

  // ──────────────────────────────────────────────────────────────────────
  // Ticker control
  // ──────────────────────────────────────────────────────────────────────

  /// Starts the per-frame ticker if not already running. Idempotent.
  /// Called from controller-side enter/exit start paths after writing a
  /// fresh entry into the standalone slot.
  void ensureRunning() {
    _ticker ??= _vsync.createTicker(_runTick);
    if (!_ticker!.isActive) {
      _lastTickElapsed = null;
      _ticker!.start();
    }
  }

  /// Stops the per-frame ticker if running. Idempotent. Called when
  /// `hasAny` becomes false — there's nothing to advance until
  /// [ensureRunning] is called again.
  void stop() {
    _ticker?.stop();
  }

  /// Internal ticker callback. Per-tick steps:
  /// 1. Stop early if nothing to animate or animationDuration is zero.
  /// 2. Compute dt and advance every active state's progress + extent.
  /// 3. Collect newly-completed keys and forward them to the controller's
  ///    [onTick] callback (which drives `_finalizeAnimation` and fires
  ///    the listener channel).
  void _runTick(Duration elapsed) {
    if (_activeNids.isEmpty) {
      _ticker?.stop();
      return;
    }
    final duration = _animationDurationGetter();
    if (duration.inMicroseconds == 0) {
      _ticker?.stop();
      return;
    }

    final dt = _lastTickElapsed == null
        ? Duration.zero
        : elapsed - _lastTickElapsed!;
    _lastTickElapsed = elapsed;
    final progressDelta = dt.inMicroseconds / duration.inMicroseconds;
    final curve = _animationCurveGetter();

    _completedScratch.clear();
    for (final nid in _activeNids) {
      final state = _byNid[nid]!;
      state.progress += progressDelta * state.speedMultiplier;
      state.updateExtent(curve);
      if (state.isComplete) {
        _completedScratch.add(_nids.keyOfUnchecked(nid));
      }
    }

    _onTick(_completedScratch);
  }

  // ──────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────

  /// Resets state and disposes the underlying ticker. Leaves the animator
  /// usable for re-allocation (the ticker is recreated on next
  /// [ensureRunning]).
  void clear() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _lastTickElapsed = null;
    _byNid = <AnimationState?>[];
    _activeNids.clear();
    _completedScratch.clear();
  }

  /// Same destructive cleanup as [clear], plus marks the animator terminal
  /// (further calls are undefined).
  void dispose() {
    clear();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Debug
  // ──────────────────────────────────────────────────────────────────────

  /// Debug-only: asserts [_activeNids] contains exactly the nids whose
  /// `_byNid` slot is non-null, and that no slot is set for a freed nid.
  void debugAssertConsistent() {
    assert(() {
      int activeCount = 0;
      for (int nid = 0; nid < _byNid.length; nid++) {
        if (_byNid[nid] != null) {
          if (_nids.keyOf(nid) == null) {
            throw StateError(
              "StandaloneAnimator._byNid[$nid] non-null for freed slot",
            );
          }
          if (!_activeNids.contains(nid)) {
            throw StateError(
              "StandaloneAnimator._byNid[$nid] non-null but missing from "
              "_activeNids",
            );
          }
          activeCount++;
        }
      }
      if (activeCount != _activeNids.length) {
        throw StateError(
          "StandaloneAnimator activeNids contains "
          "${_activeNids.length - activeCount} stale entries",
        );
      }
      return true;
    }());
  }
}
