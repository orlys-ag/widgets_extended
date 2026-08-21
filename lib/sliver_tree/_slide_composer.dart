/// Facade composing the two slide-pipeline collaborators into a single
/// surface the render layer holds: [SlideBaselineSlot], which stages and
/// consumes pending baselines, and [GhostRegistry], which owns the active
/// edge ghosts. Implements [GhostBaseResolver] by delegating to the
/// registry, so the render layer's paint-time hot paths can be typed
/// against that narrow read contract.
///
/// The render object owns one composer per attached controller. The
/// composer is **purely passive**: the render layer hands it the
/// current viewport snapshot, asks for a ghost base Y, and tells it
/// when to install / re-evaluate / prune. Viewport assembly and the
/// `TreeRenderHost` callback registration stay on the render object.
library;

import 'package:flutter/animation.dart' show Curve;
import 'package:flutter/foundation.dart' show visibleForTesting;

import '_ghost_registry.dart';
import '_slide_baseline_slot.dart';
import '_viewport_snapshot.dart';
import 'tree_controller.dart';

/// One composer per attached controller, owned by the render object.
///
/// Holds no slide state of its own: both collaborators are exposed
/// directly, and the forwarders below exist only to shorten the most
/// frequent call sites. Anything beyond those goes through [baselineSlot]
/// or [ghosts], whose own docs carry the contracts.
class SlideComposer<TKey, TData> implements GhostBaseResolver<TKey> {
  SlideComposer({required TreeController<TKey, TData> controller})
    : baselineSlot = SlideBaselineSlot<TKey>(),
      ghosts = GhostRegistry<TKey, TData>(controller: controller);

  /// Pending-baseline slot: staged before a mutation, consumed by the
  /// layout that follows it.
  final SlideBaselineSlot<TKey> baselineSlot;

  /// Active edge-ghost registry.
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

  /// Forwards to [SlideBaselineSlot.stage]. Returns false when a baseline
  /// is already staged for this frame, per that slot's first-wins rule.
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

  /// Forwards to [SlideBaselineSlot.consume], taking the staged baseline
  /// and emptying the slot. Null when nothing was staged.
  ({
    Map<TKey, ({double y, double x})> offsets,
    ViewportSnapshot viewport,
    Duration duration,
    Curve curve,
  })?
  consumeBaseline() => baselineSlot.consume();

  /// Whether a baseline is staged and not yet consumed.
  bool get isBaselineStaged => baselineSlot.isStaged;

  // ──────────────────────────────────────────────────────────────────────
  // GhostBaseResolver: forwards to the ghost registry.
  // ──────────────────────────────────────────────────────────────────────

  @override
  double? baseFor(TKey key, ViewportSnapshot viewport) =>
      ghosts.baseFor(key, viewport);

  @override
  bool get hasGhosts => ghosts.hasGhosts;

  /// Number of live ghost entries. Forwards to the registry's debug
  /// accessor for symmetry with the render object's count exposures.
  @visibleForTesting
  int get debugGhostEntryCount =>
      // ignore: invalid_use_of_visible_for_testing_member
      ghosts.debugEntryCount;

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
