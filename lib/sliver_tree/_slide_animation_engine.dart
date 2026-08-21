/// Internal: paint-only FLIP slide engine for [TreeController].
///
/// Owns every piece of slide state: the per-nid slide map, the active-set
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
/// [RenderObject.performLayout]: the listener chain reaches the sliver
/// element's `_onAnimationTick` only from the next vsync, when
/// `markNeedsLayout`/`markNeedsPaint` are legal. An [AnimationController]
/// fires listeners synchronously from its `value=` setter, so starting it
/// mid-layout would trip `_debugCanPerformMutations`.
///
/// Per-slide timing: each [SlideAnimation] tracks its own
/// `slideStartElapsed` (the [Ticker.elapsed] value at install /
/// composition / re-baseline) and `slideDuration`. The shared ticker
/// runs continuously while any slide is active and is NOT reset
/// per-batch; per-slide progress in `_onSlideTick` derives from
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

/// Paint-only FLIP slide engine. See the library doc for the timing model.
///
/// Two protocols here are load-bearing and easy to break. The SETTLE
/// protocol in [_onSlideTick] notifies with deltas at exactly 0 BEFORE
/// removing completed entries, then notifies once more after cleanup so
/// listeners can observe the active-to-idle transition. And COMPOSITION
/// retargets an entry in place, which is why completion cleanup checks
/// [SlideAnimation.installStamp] as well as identity: a listener may have
/// composed onto the very entry that just completed.
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

  // Active slide map: a list indexed by nid, null when
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
  /// O(1) and yields the value, not just presence), so no separate
  /// membership structure is needed.
  final Set<int> _activeSlideNids = <int>{};

  /// Count of active slide entries whose `startDeltaX != 0`, meaning entries
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
  /// after a fully-settled period. See [animateFromOffsets].
  Duration _lastTickElapsed = Duration.zero;

  // ──────────────────────────────────────────────────────────────────────
  // PUBLIC READ API (consumed by render layer via controller delegators)
  // ──────────────────────────────────────────────────────────────────────

  /// Whether any slide is currently installed, animating or settled but
  /// not yet cleaned up. Composed into `TreeController.hasActiveSlides`.
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
  /// [structuralAnimationsDisabled] = the calling family's spec is
  /// zeroed (`reorderSlide` for this public path; the drop-settle
  /// channel passes its own family's flag), passed in so the engine never
  /// reaches back into the controller for it. An explicit zero [duration]
  /// is treated the same way. DISABLED-MODE SPLIT: either gate means this
  /// call CREATES no motion, so nothing fresh installs, but existing
  /// entries are NOT destroyed: entries
  /// whose bases this batch moved are re-based on their OWN
  /// duration/curve so they continue seamlessly. Stopping existing
  /// motion is an explicit transition event ([purgeActive]), never a
  /// side effect of another family's install call.
  void animateFromOffsets(
    Map<TKey, ({double y, double x})> priorOffsets,
    Map<TKey, ({double y, double x})> currentOffsets, {
    required Duration duration,
    required Curve curve,
    required bool structuralAnimationsDisabled,
    double maxSlideDistance = double.infinity,
  }) {
    if (structuralAnimationsDisabled || duration == Duration.zero) {
      // Disabled-mode split: refuse fresh installs; re-base survivors.
      // O(1) on the dominant no-actives path (`.disabled` configs).
      if (!hasActive) {
        return;
      }
      if (_ticker == null || !_ticker!.isActive) {
        _lastTickElapsed = Duration.zero;
      }
      // Iterate ACTIVES (a handful), not the maps (every visible row).
      // Copy: _clearSlide mutates the set mid-iteration.
      final touched = <int>{};
      for (final nid in _activeSlideNids.toList()) {
        final entry = _slideByNid[nid]!;
        final key = _nids.keyOfUnchecked(nid);
        final current = currentOffsets[key];
        final prior = priorOffsets[key];
        if (current == null || prior == null) {
          continue; // Absent from this batch: re-baselined below.
        }
        final rawDeltaY = prior.y - current.y;
        final rawDeltaX = prior.x - current.x;
        final composedY = entry.currentDelta + rawDeltaY;
        final composedX = entry.currentDeltaX + rawDeltaX;
        if (composedY.abs() > maxSlideDistance) {
          _clearSlide(key);
          continue;
        }
        if (composedY == 0.0 && composedX == 0.0) {
          _clearSlide(key); // Painted where it belongs: no slide left.
          continue;
        }
        if (rawDeltaY == 0.0 && rawDeltaX == 0.0) {
          // No-op for this entry: the un-touched branch below is the
          // only authority over its clock (mirrors the enabled path's
          // no-op composition rule).
          continue;
        }
        final hadX = entry.startDeltaX != 0.0;
        final newHasX = composedX != 0.0;
        if (hadX && !newHasX) {
          _xActiveCount--;
        } else if (!hadX && newHasX) {
          _xActiveCount++;
        }
        entry.startDelta = composedY;
        entry.currentDelta = composedY;
        entry.startDeltaX = composedX;
        entry.currentDeltaX = composedX;
        entry.slideStartElapsed = _lastTickElapsed;
        entry.progress = 0.0;
        // KEEP entry.slideDuration and entry.curve: the staged timing
        // belongs to the fresh installs this branch refuses.
        entry.preserveProgressOnRebatch = false;
        entry.installStamp++;
        touched.add(nid);
      }
      _rebaselineUntouched(touched);
      // "hasActive implies ticker active" holds at every stop site, and
      // this branch only mutates pre-existing actives, so ensure-start keeps
      // the invariant locally enforced WITHOUT threading the enabled
      // tail's `installed == 0` early-return (which always fires here).
      final ticker = _ticker ??= _vsync.createTicker(_onSlideTick);
      if (!ticker.isActive) ticker.start();
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
      // |existing.currentDelta|, which was itself within maxSlideDistance.
      final composedY = (existing?.currentDelta ?? 0.0) + rawDeltaY;
      if (composedY.abs() > maxSlideDistance) {
        if (existing != null) {
          _clearSlide(key);
          // Removing a touched entry mid-iteration is fine: touched is
          // populated only on install or compose.
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
        // position as identical in the baseline and current snapshots
        // (rawDeltaY == 0 && rawDeltaX == 0), so the existing trajectory
        // is still valid. Animating from `currentDelta` toward 0 reaches
        // the same structural target either way.
        //
        // Resetting the clock here instead would STARVE the slide under a
        // rapid burst of batches that keep including this row without
        // moving it. Each reset restarts the animation from a
        // `currentDelta` that has already ticked down, so per-frame motion
        // shrinks toward sub-pixel and the row reads as frozen until the
        // burst stops and one full duration finally runs uninterrupted.
        //
        // Treat the entry as UN-TOUCHED by this batch: it stays in
        // `_activeSlideNids`, so the re-baseline branch below is the sole
        // authority over its clock. That branch honors
        // `preserveProgressOnRebatch`, so a slide already carrying the
        // flag keeps ticking on its original install clock. `installed`
        // is not incremented, because nothing was installed or composed.
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
        // Adapt the slide's effective duration so per-frame motion stays
        // perceptible. Under rapid cascaded `moveNode(animate: true)`,
        // each batch re-composes the row with a new
        // `composedY = currentDelta + rawDeltaY`. When the existing
        // `currentDelta` and the batch's `rawDeltaY` partially cancel,
        // which is common under random reparenting, `composedY` shrinks
        // relative to the original `rawDeltaY`. Applying the caller's
        // `slideDuration` unchanged then spreads that small delta over the
        // full time, so per-frame motion drops below a pixel and the row
        // reads as not animating, even though the slide is active and
        // does settle correctly.
        //
        // Clamping keeps per-tick motion at [_minPxPerTick] or better: a
        // small composedY settles faster, as a brief but visible move,
        // while a large composedY keeps the caller's duration. Neither
        // case jumps, since `composedY` is still the start delta; only
        // the time it animates over changes.
        //
        // The microseconds-per-pixel ratio assumes 60Hz, so a
        // higher-refresh display over-shortens slightly. That errs toward
        // more visible motion, which is the safe direction.
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
        // Mark the in-place retarget so a completion cleanup collected
        // BEFORE this composition (same tick) cannot mistake the fresh
        // slide for the entry that completed.
        existing.installStamp++;
        final nid = _nids[key];
        if (nid != null) touched.add(nid);
        installed++;
      }
    }

    _rebaselineUntouched(touched);

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
  /// The final zero-delta paint is guaranteed by three rules together:
  ///
  /// 1. `entry.currentDelta` is set to exactly 0.0 on completion so the
  ///    post-tick paint matches structural layout pixel-exactly.
  /// 2. `_onTick` (the animation listener channel) fires BEFORE any
  ///    completed entries are removed from `_slideByNid`. The sliver
  ///    element's `_onAnimationTick` schedules `markNeedsPaint`, and
  ///    that paint reads `deltaForNid(nid) == 0.0`.
  /// 3. Per-slide cleanup runs AFTER `_onTick`, and is reference-safe: it
  ///    clears the slot if it still holds the same entry that completed
  ///    (an `_onTick` listener may have re-installed a new slide on the
  ///    same nid via composition).
  void _onSlideTick(Duration elapsed) {
    _lastTickElapsed = elapsed;
    if (!hasActive) {
      _ticker?.stop();
      return;
    }
    final completedEntries = <(int, SlideAnimation<TKey>, int)>[];
    bool anyStillActive = false;
    for (final nid in _activeSlideNids) {
      final entry = _slideByNid[nid]!;
      final perSlideMicros =
          elapsed.inMicroseconds - entry.slideStartElapsed.inMicroseconds;
      final totalUs = entry.slideDuration.inMicroseconds;
      final raw = totalUs <= 0 ? 1.0 : perSlideMicros / totalUs;
      // 1e-9 epsilon: absorbs floating-point drift from the
      // microsecond division so a slide that should settle exactly at
      // duration boundary doesn't linger one extra tick at progress
      // near 0.999999999. Trades at most one sub-frame of early settle for
      // deterministic completion. Imperceptible at 60 Hz.
      final complete = raw >= 1.0 - 1e-9;
      entry.progress = complete ? 1.0 : raw.clamp(0.0, 1.0);
      final t = entry.curve.transform(entry.progress);
      if (complete) {
        entry.currentDelta = 0.0;
        entry.currentDeltaX = 0.0;
        completedEntries.add((nid, entry, entry.installStamp));
      } else {
        entry.currentDelta = lerpDouble(entry.startDelta, 0.0, t)!;
        entry.currentDeltaX = lerpDouble(entry.startDeltaX, 0.0, t)!;
        anyStillActive = true;
      }
    }

    _onTick();

    // Reference-safe cleanup AFTER paint scheduling. Only clear the slot
    // if it still holds the entry that completed: an `_onTick` listener
    // may have re-installed a new slide on the same nid (identity check)
    // or COMPOSED onto the completed entry, which mutates it in place
    // (the stamp check; identity alone would delete the freshly
    // retargeted slide).
    for (final (nid, originalEntry, stamp) in completedEntries) {
      final current = _slideByNid[nid];
      if (!identical(current, originalEntry)) continue;
      if (originalEntry.installStamp != stamp) continue;
      if (originalEntry.startDeltaX != 0.0) _xActiveCount--;
      _slideByNid[nid] = null;
      _activeSlideNids.remove(nid);
    }

    if (!anyStillActive && _activeSlideNids.isEmpty) {
      _ticker?.stop();
      // Post-cleanup settle notify: the notify above fired with
      // `hasActive` still true (the documented zero-delta-paint
      // contract), and the ticker stops here. With no further tick, a
      // listener routing slide-only ticks to paint could never observe
      // the active-to-idle transition that must trigger the
      // one layout pass where Step 0a/0b ghost pruning runs. Fire once
      // more now that the map is clear so the transition is observable.
      _onTick();
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

  /// Defensive slot reset for the nid adopt and release paths.
  /// Bounds-checked because those can run before [resizeForCapacity] has
  /// grown this engine's array to cover [nid].
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
  /// Only ever sets the flag: the engine clears it implicitly when
  /// the slide entry is destroyed (settles, cancelled, or replaced via
  /// composition). The render layer should never need to clear explicitly.
  void markPreserveProgress(TKey key) {
    final nid = _nids[key];
    if (nid == null || nid >= _slideByNid.length) return;
    final entry = _slideByNid[nid];
    if (entry == null) return;
    entry.preserveProgressOnRebatch = true;
  }

  /// Capacity-preserving purge of every active slide: entries cleared and
  /// the ticker STOPPED, not disposed, so the next install restarts it.
  ///
  /// The controller calls this on the style transition meaning "stop
  /// slide motion now", which is `reorderSlide` being zeroed. That is the
  /// other half of the disabled-mode split: a zero family refuses NEW
  /// motion at install time, while stopping EXISTING motion is this
  /// explicit event. Unlike [clearAll] this is safe mid-lifecycle, since
  /// `_slideByNid` keeps its capacity and later installs cannot
  /// range-error.
  void purgeActive() {
    if (hasActive) {
      _clearAllSlidesInternal();
    }
    _ticker?.stop();
  }

  /// Resets every slide-related field back to its initial state and
  /// disposes the ticker. Called from `TreeController._clear` (and
  /// indirectly from `dispose`). The next [animateFromOffsets] call
  /// recreates the ticker via the existing `_ticker ??= ...` pattern.
  /// NOT safe mid-lifecycle, since it drops `_slideByNid` capacity; use
  /// [purgeActive] for that.
  void clearAll() {
    _ticker?.dispose();
    _ticker = null;
    _slideByNid = <SlideAnimation<TKey>?>[];
    _activeSlideNids.clear();
    _xActiveCount = 0;
  }

  /// Terminal teardown. Identical to [clearAll], which already disposes
  /// the ticker, and kept as its own entry point so every engine tears
  /// down through the same name.
  void dispose() {
    clearAll();
  }

  // ──────────────────────────────────────────────────────────────────────
  // INTERNAL HELPERS
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

  /// A duration no longer than [requested], for which a slide animating
  /// from `composedY` (or `composedX`) toward 0 keeps per-frame motion at
  /// [_minPxPerTick] logical pixels or better at 60 Hz. Floored at one
  /// tick so the slide is never instantaneous. The composition call site
  /// explains why the clamp exists at all.
  ///
  /// Why 2 px rather than 1: one pixel per tick (60 px/sec) is
  /// technically visible but borderline on opaque rectangular widgets
  /// such as text and colored rows, where a single-pixel step alternating
  /// between adjacent rows reads as faint flicker rather than motion. Two
  /// pixels per tick (120 px/sec) is reliably perceptible.
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
    return Duration(microseconds: math.max(_minDurationMicros, clamped));
  }

  /// Re-baselines every active slide that a batch did NOT touch,
  /// shared by the enabled install/compose path and the disabled-mode
  /// re-base branch (the "no third mechanism" rule). Without this, an
  /// un-touched slide's progress would snap to ~0 after a fresh-ticker
  /// elapsed reset and lerp currentDelta back to its ORIGINAL
  /// startDelta (visible jump).
  ///
  /// Slides marked [SlideAnimation.preserveProgressOnRebatch] (set by
  /// the render layer for active edge-ghost and exit-phantom slides)
  /// are skipped, so their progress continues uninterrupted across
  /// batches so concurrent mutations (e.g. autoscroll commits) don't
  /// reset ghost slides that should be settling smoothly. Un-touched
  /// entries keep their existing curve and slideDuration.
  void _rebaselineUntouched(Set<int> touched) {
    if (_activeSlideNids.length == touched.length) return;
    for (final nid in _activeSlideNids) {
      if (touched.contains(nid)) continue;
      final entry = _slideByNid[nid]!;
      if (entry.currentDelta == 0.0 && entry.currentDeltaX == 0.0) {
        // Already settled: let the next tick mark complete and clear.
        continue;
      }
      if (entry.preserveProgressOnRebatch) continue;
      entry.startDelta = entry.currentDelta;
      entry.startDeltaX = entry.currentDeltaX;
      entry.slideStartElapsed = _lastTickElapsed;
      entry.progress = 0.0;
    }
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
