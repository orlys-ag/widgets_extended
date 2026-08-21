/// Single-slot pending-baseline buffer used by the slide pipeline.
///
/// `RenderSliverTree.beginSlideBaseline` captures the current painted
/// offsets BEFORE a structural mutation; the next `performLayout`
/// consumes that snapshot to install a FLIP slide. Only one baseline per
/// frame is meaningful, so staging is FIRST-WINS: the first caller
/// captured the truly-painted positions, while a later one would read
/// already-mutated state.
///
/// This class owns the slot and its (offsets, viewport, duration, curve)
/// tuple. It is one of the two collaborators `SlideComposer` holds, the
/// other being `GhostRegistry`.
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

/// Holds at most one staged baseline, plus a stamp letting a late expiry
/// check tell whether the stage it was scheduled for is still pending.
///
/// The caller contract is that every successful [stage] is followed by a
/// same-frame mutation that triggers layout, whose [consume] then takes
/// the baseline. [discardIfStale] is the backstop for when that does not
/// happen.
class SlideBaselineSlot<TKey> {
  /// The staged baseline, or null when the slot is empty.
  _SlideBaseline<TKey>? _pending;

  /// Monotonic counter, incremented on every successful [stage] so that
  /// no two stages ever share an identity.
  int _stamp = 0;

  /// Stamp of the baseline currently in the slot.
  ///
  /// This is what lets the expiry backstop discard exactly the stage it
  /// was scheduled for: consume, reset and re-stage all change the
  /// pending identity, so a check that arrives late becomes a no-op
  /// instead of discarding a newer baseline.
  int _pendingStamp = 0;

  /// Stamp of the pending baseline. Only meaningful while [isStaged].
  int get pendingStamp => _pendingStamp;

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
    _pendingStamp = ++_stamp;
    return true;
  }

  /// The expiry backstop: discards the pending baseline only when it is
  /// still the stage identified by [stamp].
  ///
  /// Returns true when a discard actually happened, which means the
  /// caller contract was violated. A successful [stage] was not followed
  /// by a same-frame layout-triggering mutation, so its baseline was
  /// never consumed.
  bool discardIfStale(int stamp) {
    if (_pending == null || _pendingStamp != stamp) {
      return false;
    }
    _pending = null;
    return true;
  }

  /// Takes the staged baseline, if any, and empties the slot so the next
  /// frame's first [stage] can win it.
  ({
    Map<TKey, ({double y, double x})> offsets,
    ViewportSnapshot viewport,
    Duration duration,
    Curve curve,
  })?
  consume() {
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

  /// Whether a baseline is currently staged and not yet consumed.
  bool get isStaged => _pending != null;

  /// Discards a staged baseline without consuming it. Used on
  /// controller swap (render object's controller setter) so a baseline
  /// staged against the old controller doesn't leak into the new one.
  void reset() {
    _pending = null;
  }
}
