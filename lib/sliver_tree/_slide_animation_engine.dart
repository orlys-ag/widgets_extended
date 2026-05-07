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
/// Per-slide timing: each [SlideAnimation] tracks its own
/// `slideStartElapsed` (the [Ticker.elapsed] value at install /
/// composition / re-baseline) and `slideDuration`. The shared ticker
/// runs continuously while any slide is active and is NOT reset
/// per-batch — per-slide progress in `_onSlideTick` derives from
/// `(elapsed - entry.slideStartElapsed) / entry.slideDuration`. This
/// allows multiple concurrent slides with different durations to
/// progress at their own rates, and lets slides marked
/// [SlideAnimation.preserveProgressOnRebatch] continue uninterrupted
/// across un-touching batches (used by the render layer for active
/// edge-ghost and exit-phantom slides).
///
/// Not exported from the package barrel; used only by [TreeController].
library;

import 'dart:math' as math;
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
  ///
  /// Used by `_onSlideTick`, `maxAbsDelta`, the re-baseline branch, and
  /// `_clearAllSlidesInternal` for iteration. For typical slide counts
  /// (5-50) the hash-set iteration is fast and the storage is bounded
  /// by the active count rather than nidCapacity. Per-row "is sliding?"
  /// checks are answered by reading `_slideByNid[nid]` directly (also
  /// O(1) and yields the value, not just presence) — no separate
  /// contains structure is needed.
  final Set<int> _activeSlideNids = <int>{};

  /// Count of active slide entries whose `startDeltaX != 0` — i.e. entries
  /// that will animate horizontally. Maintained incrementally by every
  /// install / compose / clear path so the render layer can skip per-row
  /// X-axis processing when this is 0 (the overwhelmingly common case
  /// since X deltas only arise from depth-changing reparents).
  ///
  /// Invariant: equals the number of entries in `_slideByNid` whose
  /// `startDeltaX != 0`. `currentDeltaX` lerps toward 0 during the slide
  /// but never crosses through 0, so `startDeltaX != 0` is a stable
  /// "this entry has X work" signal for the slide's lifetime.
  int _xActiveCount = 0;

  Ticker? _ticker;

  /// Last [Duration] passed to [_onSlideTick]. Updated on every tick so
  /// install/composition/re-baseline paths can read the most recent
  /// ticker elapsed value when capturing per-slide `slideStartElapsed`
  /// (the [Ticker] class does not expose `elapsed` between callbacks,
  /// so we mirror it manually).
  ///
  /// Reset to [Duration.zero] when the ticker is created or restarted
  /// after a fully-settled period — see [animateFromOffsets].
  Duration _lastTickElapsed = Duration.zero;

  // ──────────────────────────────────────────────────────────────────────
  // PUBLIC READ API (consumed by render layer via controller delegators)
  // ──────────────────────────────────────────────────────────────────────

  bool get hasActive => _activeSlideNids.isNotEmpty;

  /// Whether any active slide entry is animating horizontally
  /// (startDeltaX != 0). Lets render-layer hot paths skip per-row
  /// X-delta reads when no X-axis work is in flight.
  bool get hasActiveX => _xActiveCount > 0;

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

  /// X-axis (cross-axis indent) slide delta for the live [nid], or 0.0 if
  /// not currently sliding. Caller must guarantee [nid] is within range.
  double deltaXForNid(int nid) {
    final slide = _slideByNid[nid];
    return slide == null ? 0.0 : slide.currentDeltaX;
  }

  /// X-axis slide delta for [key], or 0.0 if not currently sliding (or
  /// not registered).
  double deltaXForKey(TKey key) {
    final nid = _nids[key];
    if (nid == null || nid >= _slideByNid.length) return 0.0;
    final slide = _slideByNid[nid];
    return slide == null ? 0.0 : slide.currentDeltaX;
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
    Map<TKey, ({double y, double x})> priorOffsets,
    Map<TKey, ({double y, double x})> currentOffsets, {
    required Duration duration,
    required Curve curve,
    required bool structuralAnimationsDisabled,
    double maxSlideDistance = double.infinity,
  }) {
    if (structuralAnimationsDisabled || duration == Duration.zero) {
      // No-animation mode: drop any in-flight slide and return.
      if (hasActive) {
        _clearAllSlidesInternal();
        _ticker?.stop();
      }
      return;
    }

    // If the ticker isn't currently running, reset our mirror of its
    // elapsed value to 0 BEFORE the install loop reads it. The ticker's
    // internal elapsed restarts from 0 on the next [Ticker.start] call,
    // and we want new slides installed in this batch to capture
    // `slideStartElapsed = 0` so the first post-install tick computes
    // progress as `vsync_delta / duration` (not negative).
    if (_ticker == null || !_ticker!.isActive) {
      _lastTickElapsed = Duration.zero;
    }

    int installed = 0;
    final touched = <int>{};
    for (final entry in currentOffsets.entries) {
      final key = entry.key;
      final current = entry.value;
      final prior = priorOffsets[key];
      if (prior == null) continue;
      final rawDeltaY = prior.y - current.y;
      final rawDeltaX = prior.x - current.x;
      final existing = _slideAt(key);

      // Distance gate: applied to the COMPOSED Y delta. When existing is
      // null, composedY == rawDeltaY (subset of the same check). On
      // exceed: drop any in-flight entry, install nothing, row paints at
      // new structural position. The visual jump is bounded by
      // |existing.currentDelta| which was itself ≤ maxSlideDistance.
      final composedY = (existing?.currentDelta ?? 0.0) + rawDeltaY;
      if (composedY.abs() > maxSlideDistance) {
        if (existing != null) {
          _clearSlide(key);
          // Removing a touched entry mid-iteration is fine — touched is
          // populated only on install/compose.
        }
        continue;
      }

      if (existing == null) {
        if (rawDeltaY == 0.0 && rawDeltaX == 0.0) continue;
        final slide = SlideAnimation<TKey>(
          startDelta: rawDeltaY,
          startDeltaX: rawDeltaX,
          curve: curve,
        );
        slide.slideStartElapsed = _lastTickElapsed;
        slide.slideDuration = duration;
        _setSlide(key, slide);
        if (rawDeltaX != 0.0) _xActiveCount++;
        final nid = _nids[key];
        if (nid != null) touched.add(nid);
        installed++;
      } else {
        // Composition: preserve currently rendered visual position as the
        // new starting delta so the slide continues seamlessly.
        final composedX = existing.currentDeltaX + rawDeltaX;
        if (composedY == 0.0 && composedX == 0.0) {
          _clearSlide(key); // handles _xActiveCount decrement internally
          continue;
        }
        // No-op composition: this batch reports the row's painted
        // position is the same in both baseline and current snapshots
        // (rawDeltaY == 0 && rawDeltaX == 0), so the slide's existing
        // trajectory is still valid — animating from `currentDelta`
        // toward 0 reaches the same structural target either way.
        // Skipping the reset here avoids the failure mode the user
        // reported under rapid tapping of `Reparent ALL` / `Move N`:
        //
        //   * Tap N installs slide for row R. `currentDelta` = X.
        //   * Tap N+1 includes R in its batch but doesn't shift R
        //     structurally (some other rows are reordered around R but
        //     R's own position is unchanged). `rawDeltaY` = 0.
        //   * Pre-fix composition: `startDelta = currentDelta`,
        //     `progress = 0`, `slideStartElapsed = now`. The clock
        //     restarts; the slide is animated again from `currentDelta`
        //     to 0 over a fresh `slideDuration`.
        //   * Per rapid tap, `currentDelta` shrinks (it had been
        //     ticking) and the clock is reset again. Per-tick motion
        //     becomes sub-pixel within a few iterations, so the user
        //     observes "the slide isn't playing" — the row ends up at
        //     its correct structural target only when tapping stops
        //     and the slide can finally run for one full duration
        //     uninterrupted.
        //
        // Treat this entry as "un-touched" by this batch: it stays in
        // `_activeSlideNids`, so the un-touched re-baseline branch
        // below is the only authority over its clock — and that branch
        // honors `preserveProgressOnRebatch`, so a slide that already
        // had the flag set (via consume's step 8 / `_syncPreserveProgressFlags`
        // / re-promotion-on-scroll) will continue ticking on its
        // original install clock. `installed` is not incremented here
        // because no new install/composition happened.
        if (rawDeltaY == 0.0 && rawDeltaX == 0.0) {
          continue;
        }
        // Update X-active count based on transition between had-X and
        // has-X states. existing.startDeltaX reflects the entry's
        // current "has X work" status (lerp doesn't cross zero).
        final hadX = existing.startDeltaX != 0.0;
        final newHasX = composedX != 0.0;
        if (hadX && !newHasX) {
          _xActiveCount--;
        } else if (!hadX && newHasX) {
          _xActiveCount++;
        }
        existing.startDelta = composedY;
        existing.currentDelta = composedY;
        existing.startDeltaX = composedX;
        existing.currentDeltaX = composedX;
        existing.slideStartElapsed = _lastTickElapsed;
        // Adapt the slide's effective duration so per-frame motion is
        // visually perceptible. Under rapid cascaded `moveNode(animate:
        // true)` (e.g. the example app's `Reparent ALL` button tapped
        // quickly), each tap re-composes a row's slide with a new
        // `composedY = currentDelta + rawDeltaY`. When the existing
        // slide's `currentDelta` and the batch's `rawDeltaY` partially
        // cancel — common under random reparenting — `composedY` can
        // shrink relative to the original `rawDeltaY`. With the user-
        // set `slideDuration` applied unchanged, the per-frame motion
        // (`composedY / ticks_per_duration`) becomes sub-pixel and the
        // user perceives "the row didn't animate", even though the
        // engine has an active slide and the row eventually settles at
        // its correct structural position.
        //
        // Clamp the duration so per-tick motion is at least ~1 px.
        // This means small composedY → faster settle (the row "snaps"
        // quickly to its target with a brief but visible animation);
        // large composedY → user-set duration unchanged (smooth slide
        // over the full duration). No visual jump: `composedY` is still
        // the slide's start delta. Only the time over which it's
        // animated is shortened.
        //
        // The 16667 µs / px ratio assumes 60Hz; on higher-refresh
        // displays this slightly over-shortens (per-tick is bigger
        // than 1 px on a 120Hz device). Acceptable — it errs on the
        // side of more-visible motion.
        existing.slideDuration = _adaptDurationToVisibleMotion(
          duration,
          composedY: composedY,
          composedX: composedX,
        );
        // Composition creates a fresh slide semantically; reset the
        // preserve flag. Render layer re-marks via syncPreserveProgressFlags
        // for slides that are still ghosts after the batch.
        existing.preserveProgressOnRebatch = false;
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
    //
    // Slides marked [SlideAnimation.preserveProgressOnRebatch] (set by
    // the render layer for active edge-ghost and exit-phantom slides) are
    // skipped — their progress continues uninterrupted across batches so
    // that concurrent mutations (e.g. autoscroll commits) don't reset
    // ghost slides that should be settling smoothly.
    if (_activeSlideNids.length != touched.length) {
      for (final nid in _activeSlideNids) {
        if (touched.contains(nid)) continue;
        final entry = _slideByNid[nid]!;
        if (entry.currentDelta == 0.0 && entry.currentDeltaX == 0.0) {
          // Already settled — let the next tick mark complete and clear.
          continue;
        }
        if (entry.preserveProgressOnRebatch) continue;
        entry.startDelta = entry.currentDelta;
        entry.startDeltaX = entry.currentDeltaX;
        entry.slideStartElapsed = _lastTickElapsed;
        entry.progress = 0.0;
        // Keep the un-touched entry's existing curve and slideDuration.
      }
    }

    if (!hasActive) {
      _ticker?.stop();
      return;
    }
    if (installed == 0) return;

    // Ticker runs continuously while any slide is active; per-slide
    // progress derives from `(elapsed - slide.slideStartElapsed)
    // / slide.slideDuration`. Starting an already-active ticker is a
    // no-op. Per the class docstring: [Ticker.start] does NOT fire
    // callbacks synchronously, so this is safe inside
    // [RenderObject.performLayout]. `_lastTickElapsed` was already reset
    // above for fresh-ticker batches.
    final ticker = _ticker ??= _vsync.createTicker(_onSlideTick);
    if (!ticker.isActive) ticker.start();
  }

  /// Tick handler. Per-slide progress: each entry's progress is derived
  /// from `(elapsed - entry.slideStartElapsed) / entry.slideDuration`, so
  /// slides installed in different batches with different durations
  /// progress at their own rates.
  ///
  /// Final zero-delta paint is guaranteed by the same contract as before:
  ///
  /// 1. `entry.currentDelta` is set to exactly 0.0 on completion so the
  ///    post-tick paint matches structural layout pixel-exactly.
  /// 2. `_onTick` (the animation listener channel) fires BEFORE any
  ///    completed entries are removed from `_slideByNid`. The sliver
  ///    element's `_onAnimationTick` schedules `markNeedsPaint`, and
  ///    that paint reads `deltaForNid(nid) == 0.0`.
  /// 3. Per-slide cleanup runs AFTER `_onTick`. Reference-safe — only
  ///    clears the slot if it still holds the same entry that completed
  ///    (an `_onTick` listener may have re-installed a new slide on the
  ///    same nid via composition).
  void _onSlideTick(Duration elapsed) {
    _lastTickElapsed = elapsed;
    if (!hasActive) {
      _ticker?.stop();
      return;
    }
    final completedEntries = <(int, SlideAnimation<TKey>)>[];
    bool anyStillActive = false;
    for (final nid in _activeSlideNids) {
      final entry = _slideByNid[nid]!;
      final perSlideMicros =
          elapsed.inMicroseconds - entry.slideStartElapsed.inMicroseconds;
      final totalUs = entry.slideDuration.inMicroseconds;
      final raw = totalUs <= 0 ? 1.0 : perSlideMicros / totalUs;
      final complete = raw >= 1.0 - 1e-9;
      entry.progress = complete ? 1.0 : raw.clamp(0.0, 1.0);
      final t = entry.curve.transform(entry.progress);
      if (complete) {
        entry.currentDelta = 0.0;
        entry.currentDeltaX = 0.0;
        completedEntries.add((nid, entry));
      } else {
        entry.currentDelta = lerpDouble(entry.startDelta, 0.0, t)!;
        entry.currentDeltaX = lerpDouble(entry.startDeltaX, 0.0, t)!;
        anyStillActive = true;
      }
    }

    _onTick();

    // Reference-safe cleanup AFTER paint scheduling. Only clear the slot
    // if it still holds the entry that completed — an `_onTick` listener
    // may have re-installed a new slide on the same nid.
    for (final (nid, originalEntry) in completedEntries) {
      if (_slideByNid[nid] != originalEntry) continue;
      if (originalEntry.startDeltaX != 0.0) _xActiveCount--;
      _slideByNid[nid] = null;
      _activeSlideNids.remove(nid);
    }

    if (!anyStillActive && _activeSlideNids.isEmpty) {
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
    final prev = _slideByNid[nid];
    if (prev != null) {
      if (prev.startDeltaX != 0.0) _xActiveCount--;
      _slideByNid[nid] = null;
      _activeSlideNids.remove(nid);
    }
  }

  /// Cancels the slide for [key], if any. Tolerant of unregistered keys.
  /// Used by `_cancelAnimationStateForSubtree` during reparenting.
  void cancelForKey(TKey key) {
    _clearSlide(key);
  }

  /// Sets [SlideAnimation.preserveProgressOnRebatch] = true on the slide
  /// entry for [key]. Tolerant of unregistered keys and inactive slides
  /// (no-op).
  ///
  /// Set-only-true semantics — the engine implicitly clears the flag when
  /// the slide entry is destroyed (settles, cancelled, or replaced via
  /// composition). The render layer should never need to clear explicitly.
  void markPreserveProgress(TKey key) {
    final nid = _nids[key];
    if (nid == null || nid >= _slideByNid.length) return;
    final entry = _slideByNid[nid];
    if (entry == null) return;
    entry.preserveProgressOnRebatch = true;
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
    _xActiveCount = 0;
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
    if (prev.startDeltaX != 0.0) _xActiveCount--;
    _slideByNid[nid] = null;
    _activeSlideNids.remove(nid);
    return prev;
  }

  /// Returns a duration ≤ [requested] for which a slide animating from
  /// `composedY` (or `composedX`) toward 0 keeps per-frame motion at
  /// least ~[_minPxPerTick] logical pixels at 60 Hz. Floor of one tick
  /// (16.67 ms) so the slide is never instantaneous. See the call site
  /// in the composition path for full rationale.
  ///
  /// 1 px / tick (60 px/sec) is technically visible but borderline on
  /// opaque rectangular widgets (text, colored rows) — Flutter's
  /// rasterizer renders the pixel grid one frame at a time, and a 1 px
  /// step alternating between two adjacent pixel rows reads as faint
  /// flicker rather than smooth motion. 2 px / tick (120 px/sec) is
  /// reliably perceptible as movement.
  static const int _microsPerTickAt60Hz = 16667;
  static const int _minDurationMicros = _microsPerTickAt60Hz;
  static const double _minPxPerTick = 2.0;

  static Duration _adaptDurationToVisibleMotion(
    Duration requested, {
    required double composedY,
    required double composedX,
  }) {
    final maxAbsDelta = math.max(composedY.abs(), composedX.abs());
    if (maxAbsDelta <= 0.0) return requested;
    final maxMicrosForVisiblePerTick =
        (maxAbsDelta / _minPxPerTick * _microsPerTickAt60Hz).round();
    final clamped = math.min(
      requested.inMicroseconds,
      maxMicrosForVisiblePerTick,
    );
    return Duration(
      microseconds: math.max(_minDurationMicros, clamped),
    );
  }

  void _clearAllSlidesInternal() {
    for (final nid in _activeSlideNids) {
      _slideByNid[nid] = null;
    }
    _activeSlideNids.clear();
    _xActiveCount = 0;
  }

  // ──────────────────────────────────────────────────────────────────────
  // DEBUG
  // ──────────────────────────────────────────────────────────────────────

  /// Verifies [_activeSlideNids] mirrors [_slideByNid] exactly. Throws
  /// [StateError] on inconsistency. Wrapped in `assert` at call sites so
  /// release builds skip it.
  void debugAssertConsistent() {
    int slideCount = 0;
    int xCount = 0;
    for (int nid = 0; nid < _slideByNid.length; nid++) {
      final entry = _slideByNid[nid];
      if (entry != null) {
        if (_nids.keyOf(nid) == null) {
          throw StateError("_slideByNid[$nid] non-null for freed slot");
        }
        if (!_activeSlideNids.contains(nid)) {
          throw StateError(
            "_slideByNid[$nid] non-null but missing from _activeSlideNids",
          );
        }
        slideCount++;
        if (entry.startDeltaX != 0.0) xCount++;
      }
    }
    if (_activeSlideNids.length != slideCount) {
      throw StateError(
        "_activeSlideNids has ${_activeSlideNids.length} entries, "
        "but only $slideCount nids carry a slide slot",
      );
    }
    if (_xActiveCount != xCount) {
      throw StateError(
        "_xActiveCount=$_xActiveCount but $xCount entries have non-zero "
        "startDeltaX",
      );
    }
  }
}
