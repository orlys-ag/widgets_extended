/// Internal: paint-only make-room preview engine.
///
/// Holds per-nid Y offsets that open a gap at the prospective drop slot
/// during a drag: rows after the vacated slot shift up, rows at/after the
/// gap shift down, and the offsets are HELD until re-targeted or
/// released. Deliberately a sibling of `SlideAnimationEngine` rather than
/// an extension of it: the FLIP engine's model is "start at a delta, decay
/// to zero, remove at settle", while a preview is the inverse, "start at
/// zero, animate to a held non-zero target, persist". Grafting hold
/// semantics onto the FLIP tick loop would entangle its composition,
/// re-baseline and settle protocols; composing the two engines' deltas at
/// the `TreeController` read surface keeps both simple.
///
/// Painted positions need NO render-layer changes for previews to work:
/// every painted position, the painted-truth snapshot of VISIBLE rows
/// (FLIP baselines!), painted-space hit testing and the overreach bound
/// all read slide deltas through `TreeController.getSlideDeltaNid` /
/// `hasActiveSlides` / `composedSlideAbsDeltaBound`, and those delegators
/// compose `slide + preview`. Two carve-outs are named rather than
/// accidental. LIFECYCLE decisions (the edge- and exit-ghost prune and
/// paint gates, stale eviction, and `RenderSliverTree.isNodeRetained`'s
/// delta clause) read the FLIP-only accessors instead, because a HELD
/// offset never goes idle and a composed read would suspend them for the
/// length of a drag. And the exit ghost's painted-truth BASE reads
/// `TreeController.getHeldPreviewDeltaNid` directly, because what it needs
/// is the anchor's SETTLED position, which under a held preview is
/// structural + preview
/// (`RenderSliverTree._exitGhostPaintedBaseScrollSpace`). The free consequence is the seamless commit
/// handoff: a FLIP baseline staged while a preview is held captures the
/// SHIFTED painted positions; the commit clears the preview and mutates;
/// the consume-time snapshot reads post-mutation structural positions, so
/// rows that were previewing at their destination get near-zero FLIP
/// deltas.
///
/// Same raw-[Ticker] rationale as the slide engine: ticks are the only
/// place listeners fire, and [Ticker.start] never fires synchronously, so
/// engine calls are legal from any phase. Paint-only: consumers route
/// preview ticks to `markNeedsPaint` exactly like slide ticks (the
/// composed `hasActiveSlides` makes that automatic).
///
/// Keyed by nid, not key: every caller sits below [TreeController], which
/// resolves keys once. Not exported from the package barrel.
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show Curve;

/// One previewing row: [current] lerps from [start] to [target] on the
/// shared ticker, then HOLDS at [target] with [done] set, until it is
/// re-targeted, released toward zero, or cleared.
class _PreviewEntry {
  _PreviewEntry({
    required this.start,
    required this.current,
    required this.target,
    required this.startElapsed,
    required this.duration,
    required this.curve,
    this.done = false,
  });

  double start;
  double current;
  double target;
  Duration startElapsed;
  Duration duration;
  Curve curve;
  bool done;
}

/// Paint-only held-offset engine. See the library doc for how it composes
/// with the FLIP engine.
///
/// Every entry is either animating toward its target or HELD at it, which
/// [_PreviewEntry.done] records. The ticker runs only while at least one
/// entry is still animating, so a fully held preview costs nothing per
/// frame even though paint keeps reading its offsets.
class ReorderPreviewEngine {
  ReorderPreviewEngine({
    required TickerProvider vsync,
    required VoidCallback onTick,
  }) : _vsync = vsync,
       _onTick = onTick;

  final TickerProvider _vsync;
  final VoidCallback _onTick;

  /// Sparse per-nid entries. Bounded by the visible row count and only
  /// populated during a make-room drag, so a map (no capacity-lockstep
  /// wiring) is the right storage; reads happen per visible row per paint
  /// only while [hasActive].
  final Map<int, _PreviewEntry> _entries = <int, _PreviewEntry>{};

  Ticker? _ticker;

  /// Mirror of the ticker's elapsed value, reset to zero whenever the
  /// ticker restarts from idle. Without that reset an entry installed
  /// after the restart would measure progress against a stale elapsed
  /// base and run negative.
  Duration _lastTickElapsed = Duration.zero;

  // ──────────────────────────────────────────────────────────────────────
  // READ API (composed into TreeController's slide-delta delegators)
  // ──────────────────────────────────────────────────────────────────────

  /// Whether any row currently carries a preview offset, animating or
  /// held. Composed into `TreeController.hasActiveSlides`, which is what
  /// gates the render layer's slide-aware paths.
  bool get hasActive => _entries.isNotEmpty;

  /// The nid a held make-room preview has LIFTED (the dragged row; its
  /// visible subtree rides with it), or -1 when no preview is installed
  /// (M11). Independent of [_entries]: an own-slot hover legitimately
  /// holds no offsets while the row is still lifted and hidden, so this
  /// survives [releaseAll] and the tick's arrived-at-zero cleanup. It is
  /// cleared by [setLifted] with -1 (the controller's preview clear),
  /// [snapClearAll], [clearAll], and a [clearForNid] of the lifted nid
  /// itself.
  int get liftedNid => _liftedNid;
  int _liftedNid = -1;

  /// Records the lifted nid; -1 clears it.
  void setLifted(int nid) {
    _liftedNid = nid;
  }

  /// Preview delta for [nid], or 0.0 when not previewing.
  double deltaForNid(int nid) {
    final entry = _entries[nid];
    return entry == null ? 0.0 : entry.current;
  }

  /// TERMINAL bound on every offset this engine will produce from now
  /// on, composed into the layout overreach bound so preview-shifted
  /// rows stay built.
  ///
  /// `max(|current|, |target|)` per entry, not `|current|`. An entry
  /// lerps from its start to its target and then HOLDS there, so the
  /// target is where it is going and the current value is where it is;
  /// the larger of the two bounds the whole remaining animation. That
  /// is what lets a consumer widen its admission window ONCE per
  /// retarget instead of re-checking on every tick as the offset grows.
  /// `current` stays in the max for a release, whose target is 0 while
  /// the row is still displaced.
  double get maxAbsDelta {
    double m = 0.0;
    for (final entry in _entries.values) {
      final current = entry.current.abs();
      final target = entry.target.abs();
      final d = current > target ? current : target;
      if (d > m) {
        m = d;
      }
    }
    return m;
  }

  // ──────────────────────────────────────────────────────────────────────
  // WRITE API
  // ──────────────────────────────────────────────────────────────────────

  /// Re-targets the preview to exactly [targets], mapping nid to held
  /// offset.
  ///
  /// - A nid whose existing target equals its new target is left
  ///   UNTOUCHED, so its animation or hold continues. Re-resolving to the
  ///   same slot must not restart motion.
  /// - A nid with a different target re-baselines from its CURRENT value
  ///   (no visual jump).
  /// - Active nids absent from [targets] are released toward zero and
  ///   removed on arrival.
  /// - [snap] applies everything instantly (global animations disabled or
  ///   zero duration) and notifies once so paint refreshes.
  void setTargetsForNids(
    Map<int, double> targets, {
    required Duration duration,
    required Curve curve,
    required bool snap,
  }) {
    if (snap) {
      _entries.clear();
      for (final entry in targets.entries) {
        if (entry.value == 0.0) {
          continue;
        }
        _entries[entry.key] = _PreviewEntry(
          start: entry.value,
          current: entry.value,
          target: entry.value,
          startElapsed: Duration.zero,
          duration: Duration.zero,
          curve: curve,
          done: true,
        );
      }
      _ticker?.stop();
      _onTick();
      return;
    }

    if (_ticker == null || !_ticker!.isActive) {
      _lastTickElapsed = Duration.zero;
    }

    var anyAnimating = false;
    // Retarget / install the requested nids.
    for (final requested in targets.entries) {
      final nid = requested.key;
      final target = requested.value;
      final existing = _entries[nid];
      if (existing != null) {
        if (existing.target == target) {
          if (!existing.done) {
            anyAnimating = true;
          }
          continue;
        }
        existing.start = existing.current;
        existing.target = target;
        existing.startElapsed = _lastTickElapsed;
        existing.duration = duration;
        existing.curve = curve;
        existing.done = false;
        anyAnimating = true;
      } else {
        if (target == 0.0) {
          continue;
        }
        _entries[nid] = _PreviewEntry(
          start: 0.0,
          current: 0.0,
          target: target,
          startElapsed: _lastTickElapsed,
          duration: duration,
          curve: curve,
        );
        anyAnimating = true;
      }
    }
    // Release everything this batch no longer wants.
    final toRemove = <int>[];
    for (final entry in _entries.entries) {
      if (targets.containsKey(entry.key)) {
        continue;
      }
      final e = entry.value;
      if (e.current == 0.0) {
        toRemove.add(entry.key);
        continue;
      }
      if (e.target != 0.0 || e.done) {
        e.start = e.current;
        e.target = 0.0;
        e.startElapsed = _lastTickElapsed;
        e.duration = duration;
        e.curve = curve;
        e.done = false;
      }
      anyAnimating = true;
    }
    for (final nid in toRemove) {
      _entries.remove(nid);
    }

    if (!anyAnimating) {
      return;
    }
    final ticker = _ticker ??= _vsync.createTicker(_onPreviewTick);
    if (!ticker.isActive) {
      ticker.start();
    }
  }

  /// Releases every entry toward zero (animated). Entries are removed as
  /// they arrive; [hasActive] flips false when the last one settles.
  void releaseAll({required Duration duration, required Curve curve}) {
    setTargetsForNids(
      const <int, double>{},
      duration: duration,
      curve: curve,
      snap: false,
    );
  }

  /// Drops every entry instantly and notifies once. Used by the commit
  /// path (the FLIP baseline has already captured the shifted painted
  /// positions; the mutation's layout takes over from here) and by
  /// teardown paths where animating a release is meaningless.
  void snapClearAll() {
    _liftedNid = -1;
    if (_entries.isEmpty) {
      return;
    }
    _entries.clear();
    _ticker?.stop();
    _onTick();
  }

  /// Defensive slot reset mirroring the other per-nid stores: a nid freed
  /// or re-adopted mid-preview must not keep a stale offset.
  void clearForNid(int nid) {
    _entries.remove(nid);
    if (nid == _liftedNid) {
      _liftedNid = -1;
    }
  }

  /// Resets all state and disposes the ticker. Next use recreates it.
  void clearAll() {
    _ticker?.dispose();
    _ticker = null;
    _entries.clear();
    _liftedNid = -1;
    _lastTickElapsed = Duration.zero;
  }

  /// Terminal teardown. Identical to [clearAll], which already disposes
  /// the ticker, and kept as its own entry point so every engine tears
  /// down through the same name.
  void dispose() {
    clearAll();
  }

  // ──────────────────────────────────────────────────────────────────────
  // TICK
  // ──────────────────────────────────────────────────────────────────────

  /// Notify-before-cleanup, matching the slide engine: arrived entries
  /// paint their exact final value on the tick that completes them, and
  /// the active-to-idle transition fires one extra notify afterwards so
  /// listeners can observe it.
  void _onPreviewTick(Duration elapsed) {
    _lastTickElapsed = elapsed;
    if (_entries.isEmpty) {
      _ticker?.stop();
      return;
    }
    var anyAnimating = false;
    final arrivedAtZero = <int>[];
    for (final mapEntry in _entries.entries) {
      final e = mapEntry.value;
      if (e.done) {
        continue;
      }
      final perEntryMicros =
          elapsed.inMicroseconds - e.startElapsed.inMicroseconds;
      final totalUs = e.duration.inMicroseconds;
      final raw = totalUs <= 0 ? 1.0 : perEntryMicros / totalUs;
      final complete = raw >= 1.0 - 1e-9;
      if (complete) {
        e.current = e.target;
        e.done = true;
        if (e.target == 0.0) {
          arrivedAtZero.add(mapEntry.key);
        }
      } else {
        final t = e.curve.transform(raw.clamp(0.0, 1.0));
        e.current = lerpDouble(e.start, e.target, t)!;
        anyAnimating = true;
      }
    }

    _onTick();

    for (final nid in arrivedAtZero) {
      _entries.remove(nid);
    }

    if (!anyAnimating) {
      _ticker?.stop();
      if (_entries.isEmpty) {
        // The active-to-idle transition must be observable; this mirrors
        // the slide engine's post-cleanup settle notify.
        _onTick();
      }
    }
  }
}
