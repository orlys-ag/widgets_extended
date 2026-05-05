/// Internal: paint-only FLIP slide engine for [TreeController].
///
/// Owns every piece of slide state — the per-nid slide map, the active-set
/// working list, the shared [Ticker] driving progress, and the lifecycle.
/// The controller holds a single instance and exposes thin delegators for
/// the public surface ([TreeController.animateSlideFromOffsets],
/// [TreeController.getSlideDelta], etc.).
///
/// Slide is **paint-only**: it does not change layout, sticky geometry, or
/// extent animations. The engine fires its [onTick] callback (typically
/// `TreeController._notifyAnimationListeners`) on every tick so the render
/// object's animation-listener takes the slide branch and schedules
/// `markNeedsPaint`.
///
/// Why a raw [Ticker] and not an [AnimationController]: a ticker's
/// callbacks fire exclusively from the scheduler's transient-callbacks
/// phase (next vsync after [Ticker.start]). This means
/// [animateFromOffsets] can be invoked from inside
/// [RenderObject.performLayout] — the listener chain reaches the sliver
/// element's `_onAnimationTick` only from the next vsync, when
/// `markNeedsLayout`/`markNeedsPaint` are legal. An [AnimationController]
/// fires listeners synchronously from its `value=` setter, so starting it
/// mid-layout would trip `_debugCanPerformMutations`.
///
/// Not exported from the package barrel; used only by [TreeController].
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show Curve;

import '_node_id_registry.dart';
import 'types.dart';

/// Paint-only FLIP slide engine. See library docs.
class SlideAnimationEngine<TKey> {
  SlideAnimationEngine({
    required TickerProvider vsync,
    required NodeIdRegistry<TKey> nids,
    required VoidCallback onTick,
  }) : _vsync = vsync,
       _nids = nids,
       _onTick = onTick;

  final TickerProvider _vsync;
  final NodeIdRegistry<TKey> _nids;
  final VoidCallback _onTick;

  // Active slide map — typed-data list indexed by nid. Slot is null when
  // the node is not currently sliding. Size grows in lockstep with
  // [TreeController]'s nidCapacity via [resizeForCapacity].
  List<SlideAnimation<TKey>?> _slideByNid = <SlideAnimation<TKey>?>[];

  /// Live "set of nids that have a non-null _slideByNid slot."
  final Set<int> _activeSlideNids = <int>{};

  Ticker? _ticker;
  Duration _slideDuration = const Duration(milliseconds: 220);

  // ──────────────────────────────────────────────────────────────────────
  // PUBLIC READ API (consumed by render layer via controller delegators)
  // ──────────────────────────────────────────────────────────────────────

  bool get hasActive => _activeSlideNids.isNotEmpty;

  /// Maximum |currentDelta| across every active slide entry, or 0.0 when
  /// no slides are active.
  double get maxAbsDelta {
    if (!hasActive) return 0.0;
    double m = 0.0;
    for (final nid in _activeSlideNids) {
      final d = _slideByNid[nid]!.currentDelta.abs();
      if (d > m) m = d;
    }
    return m;
  }

  /// Slide delta for the live [nid], or 0.0 if not currently sliding.
  /// Caller must guarantee [nid] is within range.
  double deltaForNid(int nid) {
    final slide = _slideByNid[nid];
    return slide == null ? 0.0 : slide.currentDelta;
  }

  /// Slide delta for [key], or 0.0 if not currently sliding (or not
  /// registered).
  double deltaForKey(TKey key) {
    final nid = _nids[key];
    if (nid == null || nid >= _slideByNid.length) return 0.0;
    final slide = _slideByNid[nid];
    return slide == null ? 0.0 : slide.currentDelta;
  }

  // ──────────────────────────────────────────────────────────────────────
  // ANIMATE
  // ──────────────────────────────────────────────────────────────────────

  /// Installs FLIP slides for every node whose offset changed between
  /// [priorOffsets] and [currentOffsets]. See
  /// [TreeController.animateSlideFromOffsets] for the full contract.
  ///
  /// [structuralAnimationsDisabled] = controller's `animationDuration ==
  /// Duration.zero` — caller passes it in so the engine never reaches back
  /// into the controller for it. The engine ALSO short-circuits when
  /// [duration] is zero. Both gates exist in the original code and are
  /// preserved bit-for-bit.
  void animateFromOffsets(
    Map<TKey, double> priorOffsets,
    Map<TKey, double> currentOffsets, {
    required Duration duration,
    required Curve curve,
    required bool structuralAnimationsDisabled,
  }) {
    if (structuralAnimationsDisabled || duration == Duration.zero) {
      // No-animation mode: drop any in-flight slide and return.
      if (hasActive) {
        _clearAllSlidesInternal();
        _ticker?.stop();
      }
      return;
    }

    int installed = 0;
    final touched = <int>{};
    for (final entry in currentOffsets.entries) {
      final key = entry.key;
      final current = entry.value;
      final prior = priorOffsets[key];
      if (prior == null) continue;
      final rawDelta = prior - current;
      final existing = _slideAt(key);
      if (existing == null) {
        if (rawDelta == 0.0) continue;
        _setSlide(
          key,
          SlideAnimation<TKey>(startDelta: rawDelta, curve: curve),
        );
        final nid = _nids[key];
        if (nid != null) touched.add(nid);
        installed++;
      } else {
        // Composition: preserve currently rendered visual position as the
        // new starting delta so the slide continues seamlessly.
        final composed = existing.currentDelta + rawDelta;
        if (composed == 0.0) {
          _clearSlide(key);
          continue;
        }
        existing.startDelta = composed;
        existing.currentDelta = composed;
        existing.progress = 0.0;
        existing.curve = curve;
        final nid = _nids[key];
        if (nid != null) touched.add(nid);
        installed++;
      }
    }

    // Re-baseline every active slide that this call did NOT touch — without
    // this, an un-touched slide's progress would snap to ~0 and lerp
    // currentDelta back to its ORIGINAL startDelta (visible jump).
    if (_activeSlideNids.length != touched.length) {
      for (final nid in _activeSlideNids) {
        if (touched.contains(nid)) continue;
        final entry = _slideByNid[nid]!;
        if (entry.currentDelta == 0.0) {
          // Already settled — let the next tick mark complete and clear.
          continue;
        }
        entry.startDelta = entry.currentDelta;
        entry.progress = 0.0;
        // Keep the un-touched entry's existing curve.
      }
    }

    if (!hasActive) {
      _ticker?.stop();
      return;
    }
    if (installed == 0) return;

    // (Re)start the shared progress clock. Stop-then-start resets the
    // ticker's elapsed time to zero so progress begins at 0 for every
    // entry in this batch. [Ticker.start] does NOT fire callbacks
    // synchronously — the first tick lands on the next vsync, so this is
    // safe to call from inside [RenderObject.performLayout].
    _slideDuration = duration;
    final ticker = _ticker ??= _vsync.createTicker(_onSlideTick);
    if (ticker.isActive) ticker.stop();
    ticker.start();
  }

  /// Tick handler. Ordering matters — see comments. Final zero-delta
  /// paint is guaranteed because:
  ///
  /// 1. Progress and [SlideAnimation.currentDelta] are updated for every
  ///    entry; on completion, currentDelta is snapped to exactly 0.0 so
  ///    the final painted position matches structural layout pixel-exactly.
  /// 2. The animation-listener channel ([_onTick]) fires **before** the
  ///    map is cleared. [hasActive] is still true, so the sliver element's
  ///    `_onAnimationTick` takes the slide branch and schedules
  ///    `markNeedsPaint`. That paint reads `deltaForNid(nid) == 0.0`.
  /// 3. Only after the paint has been scheduled do we clear the map and
  ///    stop the ticker. No further tick will fire.
  void _onSlideTick(Duration elapsed) {
    if (!hasActive) {
      _ticker?.stop();
      return;
    }
    final totalUs = _slideDuration.inMicroseconds;
    final raw = totalUs <= 0 ? 1.0 : elapsed.inMicroseconds / totalUs;
    final complete = raw >= 1.0 - 1e-9;

    for (final nid in _activeSlideNids) {
      final entry = _slideByNid[nid]!;
      entry.progress = complete ? 1.0 : raw.clamp(0.0, 1.0);
      final t = entry.curve.transform(entry.progress);
      entry.currentDelta = complete
          ? 0.0
          : lerpDouble(entry.startDelta, 0.0, t)!;
    }

    _onTick();

    if (complete) {
      _clearAllSlidesInternal();
      _ticker?.stop();
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // CAPACITY / LIFECYCLE
  // ──────────────────────────────────────────────────────────────────────

  /// Grows the per-nid slide array to match [nidCapacity]. Called by
  /// [TreeController._onStoreCapacityGrew] in lockstep with every other
  /// per-nid array. New slots default to null (not sliding).
  void resizeForCapacity(int nidCapacity) {
    if (nidCapacity <= _slideByNid.length) return;
    final grown = List<SlideAnimation<TKey>?>.filled(nidCapacity, null);
    for (int i = 0; i < _slideByNid.length; i++) {
      grown[i] = _slideByNid[i];
    }
    _slideByNid = grown;
  }

  /// Defensive slot reset for `_adoptKey` and `_releaseNid`. Bounds-checks
  /// in case the engine's array hasn't grown to [nid] yet (rare but
  /// possible during initialization races).
  void clearForNid(int nid) {
    if (nid < 0 || nid >= _slideByNid.length) return;
    if (_slideByNid[nid] != null) {
      _slideByNid[nid] = null;
      _activeSlideNids.remove(nid);
    }
  }

  /// Cancels the slide for [key], if any. Tolerant of unregistered keys.
  /// Used by `_cancelAnimationStateForSubtree` during reparenting.
  void cancelForKey(TKey key) {
    _clearSlide(key);
  }

  /// Resets every slide-related field back to its initial state and
  /// disposes the ticker. Called from `TreeController._clear` (and
  /// indirectly from `dispose`). The next [animateFromOffsets] call
  /// recreates the ticker via the existing `_ticker ??= ...` pattern.
  void clearAll() {
    _ticker?.dispose();
    _ticker = null;
    _slideByNid = <SlideAnimation<TKey>?>[];
    _activeSlideNids.clear();
  }

  /// Idempotent after [clearAll]. Implemented as a thin wrapper so the
  /// controller's `dispose` call site is in place even when no extra work
  /// is needed.
  void dispose() {
    clearAll();
  }

  // ──────────────────────────────────────────────────────────────────────
  // INTERNAL HELPERS (kept private; mirror the controller's prior helpers)
  // ──────────────────────────────────────────────────────────────────────

  SlideAnimation<TKey>? _slideAt(TKey key) {
    final nid = _nids[key];
    if (nid == null || nid >= _slideByNid.length) return null;
    return _slideByNid[nid];
  }

  void _setSlide(TKey key, SlideAnimation<TKey> slide) {
    final nid = _nids[key]!;
    final prev = _slideByNid[nid];
    _slideByNid[nid] = slide;
    if (prev == null) _activeSlideNids.add(nid);
  }

  SlideAnimation<TKey>? _clearSlide(TKey key) {
    final nid = _nids[key];
    if (nid == null || nid >= _slideByNid.length) return null;
    final prev = _slideByNid[nid];
    if (prev == null) return null;
    _slideByNid[nid] = null;
    _activeSlideNids.remove(nid);
    return prev;
  }

  void _clearAllSlidesInternal() {
    for (final nid in _activeSlideNids) {
      _slideByNid[nid] = null;
    }
    _activeSlideNids.clear();
  }

  // ──────────────────────────────────────────────────────────────────────
  // DEBUG
  // ──────────────────────────────────────────────────────────────────────

  /// Verifies [_activeSlideNids] mirrors [_slideByNid] exactly. Throws
  /// [StateError] on inconsistency. Wrapped in `assert` at call sites so
  /// release builds skip it.
  void debugAssertConsistent() {
    int slideCount = 0;
    for (int nid = 0; nid < _slideByNid.length; nid++) {
      if (_slideByNid[nid] != null) {
        if (_nids.keyOf(nid) == null) {
          throw StateError("_slideByNid[$nid] non-null for freed slot");
        }
        if (!_activeSlideNids.contains(nid)) {
          throw StateError(
            "_slideByNid[$nid] non-null but missing from _activeSlideNids",
          );
        }
        slideCount++;
      }
    }
    if (_activeSlideNids.length != slideCount) {
      throw StateError(
        "_activeSlideNids has ${_activeSlideNids.length} entries, "
        "but only $slideCount nids carry a slide slot",
      );
    }
  }
}
