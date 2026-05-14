/// Single-slot pending-baseline buffer used by the slide pipeline.
///
/// `RenderSliverTree.beginSlideBaseline` captures the current painted
/// offsets BEFORE a structural mutation; the next `performLayout`
/// consumes that snapshot to install a FLIP slide. Only one baseline
/// per frame is meaningful — first-wins (the first caller captured the
/// truly-painted positions; later callers would read already-mutated
/// state).
///
/// This class owns the slot and the (offsets, viewport, duration,
/// curve) tuple. It is one of the two collaborators composed by
/// [SlideComposer] (the other is `GhostRegistry`).
library;

import 'package:flutter/animation.dart' show Curve;

import '_viewport_snapshot.dart';

/// Internal record bound to a single staged baseline. Held privately so
/// the slot can guarantee duration/curve and viewport are present
/// together when staging succeeds.
final class _SlideBaseline<TKey> {
  const _SlideBaseline({
    required this.offsets,
    required this.viewport,
    required this.duration,
    required this.curve,
  });

  final Map<TKey, ({double y, double x})> offsets;
  final ViewportSnapshot viewport;
  final Duration duration;
  final Curve curve;
}

class SlideBaselineSlot<TKey> {
  _SlideBaseline<TKey>? _pending;

  /// Stages a baseline. First-wins per frame: returns `true` if the slot
  /// was empty and the baseline was accepted, `false` if a prior stage
  /// in the same frame already filled the slot.
  bool stage({
    required Map<TKey, ({double y, double x})> offsets,
    required ViewportSnapshot viewport,
    required Duration duration,
    required Curve curve,
  }) {
    if (_pending != null) return false;
    _pending = _SlideBaseline<TKey>(
      offsets: offsets,
      viewport: viewport,
      duration: duration,
      curve: curve,
    );
    return true;
  }

  /// Consumes the staged baseline (if any) and clears the slot.
  ({
    Map<TKey, ({double y, double x})> offsets,
    ViewportSnapshot viewport,
    Duration duration,
    Curve curve,
  })? consume() {
    final pending = _pending;
    if (pending == null) return null;
    _pending = null;
    return (
      offsets: pending.offsets,
      viewport: pending.viewport,
      duration: pending.duration,
      curve: pending.curve,
    );
  }

  bool get isStaged => _pending != null;

  /// Discards a staged baseline without consuming it. Used on
  /// controller swap (render object's controller setter) so a baseline
  /// staged against the old controller doesn't leak into the new one.
  void reset() {
    _pending = null;
  }
}
