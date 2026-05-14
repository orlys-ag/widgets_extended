/// Facade that composes the two slide-pipeline collaborators —
/// [SlideBaselineSlot] (stage/consume pending baselines) and
/// [GhostRegistry] (active edge ghosts) — into a single surface the
/// render layer holds. Implements [GhostBaseResolver] by delegating to
/// the registry, so the render layer's paint-time hot paths can be
/// typed against the narrow read contract.
///
/// The render object owns one composer per attached controller. The
/// composer is **purely passive**: the render layer hands it the
/// current viewport snapshot, asks for a ghost base Y, and tells it
/// when to install / re-evaluate / prune. Viewport assembly and the
/// `TreeRenderHost` callback registration stay on the render object.
library;

import 'package:flutter/animation.dart' show Curve;

import '_ghost_registry.dart';
import '_slide_baseline_slot.dart';
import '_viewport_snapshot.dart';
import 'tree_controller.dart';

class SlideComposer<TKey, TData> implements GhostBaseResolver<TKey> {
  SlideComposer({required TreeController<TKey, TData> controller})
      : baselineSlot = SlideBaselineSlot<TKey>(),
        ghosts = GhostRegistry<TKey, TData>(controller: controller);

  final SlideBaselineSlot<TKey> baselineSlot;
  final GhostRegistry<TKey, TData> ghosts;

  /// Re-binds the registry to a new controller on `RenderSliverTree`'s
  /// controller setter. Caller separately calls [reset] to drop any
  /// state staged against the old controller's keys.
  void rebindController(TreeController<TKey, TData> controller) {
    ghosts.rebindController(controller);
  }

  // ──────────────────────────────────────────────────────────────────────
  // Convenience forwarders for the most common call sites.
  // ──────────────────────────────────────────────────────────────────────

  bool stageBaseline({
    required Map<TKey, ({double y, double x})> offsets,
    required ViewportSnapshot viewport,
    required Duration duration,
    required Curve curve,
  }) {
    return baselineSlot.stage(
      offsets: offsets,
      viewport: viewport,
      duration: duration,
      curve: curve,
    );
  }

  ({
    Map<TKey, ({double y, double x})> offsets,
    ViewportSnapshot viewport,
    Duration duration,
    Curve curve,
  })? consumeBaseline() => baselineSlot.consume();

  bool get isBaselineStaged => baselineSlot.isStaged;

  // ──────────────────────────────────────────────────────────────────────
  // GhostBaseResolver — forwards to ghost registry.
  // ──────────────────────────────────────────────────────────────────────

  @override
  double? baseFor(TKey key, ViewportSnapshot viewport) =>
      ghosts.baseFor(key, viewport);

  @override
  bool get hasGhosts => ghosts.hasGhosts;

  @override
  ({ViewportEdge edge, Duration duration, Curve curve})? entryFor(TKey key) =>
      ghosts.entryFor(key);

  // ──────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────

  /// Discards any staged baseline and clears the ghost registry. Used
  /// on controller swap so state staged against the old controller
  /// doesn't leak into the new one.
  void reset() {
    baselineSlot.reset();
    ghosts.reset();
  }
}
