/// Edge-ghost lifecycle registry — install, re-evaluate under scroll,
/// re-promote when the true structural row re-enters the viewport,
/// prune on settle, and resolve a ghost's painted base Y on demand.
///
/// Edge ghosts are rows whose new structural position is off-screen
/// when a slide animation begins. Instead of painting them at their
/// invisible structural Y, the render layer anchors them to the
/// viewport edge they're nearest to and slides them in / out from
/// there. The actual painted Y is derived **live** from the current
/// viewport via [GhostBaseResolver.baseFor], so the ghost stays pinned
/// to the live edge under concurrent scrolling.
///
/// This file also defines the [GhostBaseResolver] interface — the
/// narrow paint-time read contract that `RenderSliverTree` holds.
library;

import 'package:flutter/animation.dart' show Curve;

import '_viewport_snapshot.dart';
import 'tree_controller.dart';

/// Paint-time read contract for edge ghosts. Held by `RenderSliverTree`
/// in `applyPaintTransform`, `childMainAxisPosition`, `paint`, and the
/// hit-test admission path. Same idiom as Plan A's `AnimationReader` —
/// a narrow abstract interface lets paint-side tests stub it without
/// constructing a full ghost registry.
abstract class GhostBaseResolver<TKey> {
  /// Returns the live scroll-space base Y for [key] if it is currently
  /// an edge ghost, `null` otherwise. Caller composes the result with
  /// the row's slide delta separately (the resolver is unaware of
  /// per-frame slide progress).
  double? baseFor(TKey key, ViewportSnapshot viewport);

  /// Whether any edge ghosts are currently active. Render-side fast
  /// paths use this to skip ghost-related work when there are none.
  bool get hasGhosts;

  /// Returns the edge entry for [key] if it is currently a ghost. Used
  /// by paint/hit-test sites that need both the side AND timing info
  /// (the resolver-only [baseFor] discards the side after resolving).
  ({ViewportEdge edge, Duration duration, Curve curve})? entryFor(TKey key);
}

/// Active-edge-ghost entry shape. Mirrors the record formerly stored
/// inline in `_phantomEdgeExits`. Promoted to a named record so the
/// registry's lifecycle methods can refer to it without re-spelling
/// the tuple at every signature.
typedef GhostEntry = ({ViewportEdge edge, Duration duration, Curve curve});

class GhostRegistry<TKey, TData> implements GhostBaseResolver<TKey> {
  GhostRegistry({required TreeController<TKey, TData> controller})
      : _controller = controller;

  TreeController<TKey, TData> _controller;

  /// Active edge ghosts keyed by emerging row key. The registry owns
  /// this map; the render layer consults it only through the read API
  /// ([baseFor], [hasGhosts], [entryFor]) and the lifecycle methods
  /// below.
  Map<TKey, GhostEntry>? _entries;

  // ──────────────────────────────────────────────────────────────────────
  // Controller swap
  // ──────────────────────────────────────────────────────────────────────

  /// Re-bind to a new controller. Used when `RenderSliverTree.controller`
  /// changes; the caller separately calls [reset] to drop any state
  /// staged against the old controller's keys.
  void rebindController(TreeController<TKey, TData> controller) {
    _controller = controller;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Read API — GhostBaseResolver
  // ──────────────────────────────────────────────────────────────────────

  @override
  double? baseFor(TKey key, ViewportSnapshot viewport) {
    final entries = _entries;
    if (entries == null) return null;
    final entry = entries[key];
    if (entry == null) return null;
    return viewport.baseForEdge(entry.edge);
  }

  @override
  bool get hasGhosts => _entries != null && _entries!.isNotEmpty;

  @override
  GhostEntry? entryFor(TKey key) => _entries?[key];

  /// Iteration over the active ghosts. Used by render-side helpers
  /// (e.g. `_syncPreserveProgressFlags`) that need to iterate keys
  /// without modifying the map. Empty iterable when no ghosts active.
  Iterable<TKey> get activeKeys =>
      _entries?.keys ?? const Iterable<Never>.empty();

  // ──────────────────────────────────────────────────────────────────────
  // Lifecycle — called from RenderSliverTree.performLayout's slide
  // pipeline. Body fidelity to the pre-extraction inline versions is
  // verified by the full test suite; comments documenting the WHY are
  // preserved verbatim from the original sites so the rationale stays
  // adjacent to the code.
  // ──────────────────────────────────────────────────────────────────────

  /// Lazy-prune entries whose slide has settled or whose key has been
  /// freed. Mirrors the `_phantomClipAnchors` prune pattern.
  void pruneSettled() {
    final exits = _entries;
    if (exits == null) return;
    exits.removeWhere((key, _) {
      final nid = _controller.nidOf(key);
      if (nid < 0) return true;
      return _controller.getSlideDeltaNid(nid) == 0.0 &&
          _controller.getSlideDeltaXNid(nid) == 0.0;
    });
    if (exits.isEmpty) _entries = null;
  }

  /// Drop entries that became `_phantomExitGhosts` this cycle (an
  /// edge-ghost row was reparented under a hidden parent — the
  /// exit-phantom mechanism takes over).
  void dropForKeysThatBecameAnchorGhosts(Iterable<TKey> anchorGhostKeys) {
    final exits = _entries;
    if (exits == null) return;
    for (final key in anchorGhostKeys) {
      exits.remove(key);
    }
    if (exits.isEmpty) _entries = null;
  }

  /// Clears all entries unconditionally. Used by the render layer's
  /// Step 9 cleanup when `controller.hasActiveSlides` is false.
  void clearAll() {
    _entries = null;
  }

  /// Removes a single entry by key. Used by the ghost paint pass for
  /// eager prune of freed/settled keys (cheaper than scanning the
  /// whole map). No-op if [key] is not present.
  void removeKey(TKey key) {
    final exits = _entries;
    if (exits == null) return;
    exits.remove(key);
    if (exits.isEmpty) _entries = null;
  }

  /// Computes the row's true structural Y (no slideDelta), or -1 if
  /// the row is not in `visibleNodes`. O(N_visible). Called only for
  /// edge-ghost keys during re-promotion checks; total cost is bounded
  /// by (N_ghosts × N_visible) per consume which is tiny in practice.
  double _computeTrueStructuralAt(TKey key) {
    final visible = _controller.visibleNodes;
    final orderNids = _controller.orderNidsView;
    double structural = 0.0;
    for (int i = 0; i < visible.length; i++) {
      if (visible[i] == key) return structural;
      structural += _controller.getCurrentExtentNid(orderNids[i]);
    }
    return -1.0;
  }

  /// Step 4: re-evaluate every active edge ghost. Three outcomes per row:
  ///
  /// - **Re-promote** (true structural now in viewport): remove from
  ///   entries, override `current[key]` to structural-based form so
  ///   the engine composes the slide back to a normal slide ending at
  ///   the visible position.
  /// - **Direction flip** (still off-screen but the OPPOSITE side from
  ///   the captured edge): update the entry's edge side (preserving
  ///   original duration/curve) and override `current[key]` with the
  ///   new live edge base.
  /// - **Stays-same-edge**: don't touch — the existing slide already
  ///   targets the right edge. NOT added to
  ///   `ghostKeysTouchedThisCycle` so Step 6 will remove it from the
  ///   batch.
  void reEvaluateGhostStatus({
    required Map<TKey, ({double y, double x})> baseline,
    required Map<TKey, ({double y, double x})> current,
    required ViewportSnapshot viewport,
    required Duration duration,
    required Curve curve,
    required Set<TKey> ghostKeysTouchedThisCycle,
  }) {
    final exits = _entries;
    if (exits == null) return;
    for (final key in exits.keys.toList()) {
      final trueStructuralY = _computeTrueStructuralAt(key);
      if (trueStructuralY < 0) continue; // row left visibleNodes
      final nid = _controller.nidOf(key);
      if (nid < 0) continue;
      final slideY = _controller.getSlideDeltaNid(nid);
      final slideX = _controller.getSlideDeltaXNid(nid);
      final indent = _controller.getIndent(key);
      if (viewport.meaningfullyVisible(
        y: trueStructuralY,
        extent: _controller.getCurrentExtentNid(nid),
      )) {
        // Re-promote.
        current[key] = (
          y: trueStructuralY + slideY,
          x: indent + slideX,
        );
        exits.remove(key);
        ghostKeysTouchedThisCycle.add(key);
      } else {
        final newEdge = viewport.edgeFor(trueStructuralY);
        final entry = exits[key]!;
        if (newEdge != entry.edge) {
          // Direction flip. Update the entry; keep original duration/curve.
          exits[key] = (
            edge: newEdge,
            duration: entry.duration,
            curve: entry.curve,
          );
          current[key] = (
            y: viewport.baseForEdge(newEdge) + slideY,
            x: indent + slideX,
          );
          ghostKeysTouchedThisCycle.add(key);
        }
        // else: stays-same-edge — do NOT add to touched set. Step 6
        // will remove from batch; the consume-time baseline rewrite +
        // snapshotVisibleOffsets()'s live-base ghost rule means
        // baseline.y == current.y, engine sees no delta, slide untouched.
      }
    }
    if (exits.isEmpty) _entries = null;
  }

  /// Step 5: clamp slide-IN starts and install new edge ghosts for
  /// slide-OUT cases. Skips keys already handled by Step 4.
  void applyClampAndInstallNewGhosts({
    required Map<TKey, ({double y, double x})> baseline,
    required Map<TKey, ({double y, double x})> current,
    required ViewportSnapshot viewport,
    required Duration duration,
    required Curve curve,
    required Set<TKey> ghostKeysTouchedThisCycle,
  }) {
    final viewportTop = viewport.top;
    final viewportBottom = viewport.bottom;
    final overhangPx = viewport.overhangPx;
    final keysToProcess = <TKey>[];
    for (final key in baseline.keys) {
      if (current.containsKey(key)) keysToProcess.add(key);
    }
    final exits = _entries;
    for (final key in keysToProcess) {
      // Skip direction-flipped / stays-same ghosts — these are still in
      // `exits` and `reEvaluateGhostStatus` set up their composition
      // already (baseline = ghost-painted from snapshot; current =
      // edge_y + slideY). Re-running the clamp would interfere.
      if (exits != null && exits.containsKey(key)) continue;
      final prior = baseline[key]!;
      final curr = current[key]!;
      final nid = _controller.nidOf(key);
      final slideY = nid >= 0 ? _controller.getSlideDeltaNid(nid) : 0.0;
      final slideX = nid >= 0 ? _controller.getSlideDeltaXNid(nid) : 0.0;
      final hasInFlightSlide = slideY != 0.0 || slideX != 0.0;
      final rowExtent =
          nid >= 0 ? _controller.getCurrentExtentNid(nid) : 0.0;

      // `curr` includes the existing slide delta so the engine can
      // compose from the currently painted position. Viewport admission
      // decisions need the destination paint base instead.
      final targetY = curr.y - slideY;
      final priorOn = viewport.meaningfullyVisible(
        y: prior.y,
        extent: rowExtent,
      );
      final targetOn = viewport.meaningfullyVisible(
        y: targetY,
        extent: rowExtent,
      );
      if (priorOn && targetOn) continue; // animate real delta
      if (!priorOn && !targetOn) {
        if (!hasInFlightSlide) {
          baseline.remove(key);
          current.remove(key);
        }
        // else: leave (baseline, current) as-is — engine composes the
        // existing slide toward the new (off-screen) destination.
        continue;
      }
      if (!priorOn && targetOn) {
        // SLIDE-IN. Two distinct cases:
        //
        // (a) Initial install (no existing engine slide): clamp baseline
        //     to viewport edge ± overhang.
        // (b) Composition (existing slide active): clamp baseline to
        //     JUST INSIDE the viewport edge so painted at t=0 of the new
        //     slide is visible.
        if (!hasInFlightSlide) {
          final edgeY = prior.y < viewportTop
              ? viewportTop - overhangPx
              : viewportBottom + overhangPx;
          baseline[key] = (y: edgeY, x: prior.x);
        } else {
          const epsilon = 0.5;
          final clampedY = prior.y < viewportTop
              ? viewportTop + epsilon
              : viewportBottom - epsilon;
          baseline[key] = (y: clampedY, x: prior.x);
        }
        continue;
      }
      // priorOn && !targetOn: install new edge ghost.
      final edge = viewport.edgeFor(targetY);
      final edgeY = viewport.baseForEdge(edge);
      if (baseline[key]!.y == edgeY) continue;
      final indent = _controller.getIndent(key);
      current[key] = (y: edgeY + slideY, x: indent + slideX);
      (_entries ??= <TKey, GhostEntry>{})[key] = (
        edge: edge,
        duration: duration,
        curve: curve,
      );
      ghostKeysTouchedThisCycle.add(key);
    }
  }

  /// Step 6: remove ghost-stays-same-edge entries from the engine
  /// batch so the engine doesn't re-baseline them.
  void removeStaysFromBatch({
    required Map<TKey, ({double y, double x})> baseline,
    required Map<TKey, ({double y, double x})> current,
    required Set<TKey> ghostKeysTouchedThisCycle,
  }) {
    final exits = _entries;
    if (exits == null) return;
    for (final key in exits.keys) {
      if (ghostKeysTouchedThisCycle.contains(key)) continue;
      baseline.remove(key);
      current.remove(key);
    }
  }

  /// Normalize entries for the supplied [viewport]. For each active
  /// edge ghost:
  ///
  ///   1. If its true structural Y now intersects [viewport], remove
  ///      from the map. When [installStandaloneSlides] is true, also
  ///      install a re-promotion slide from the live edge base to
  ///      structural Y; when false, just normalize bookkeeping.
  ///   2. Else, recompute the side via [viewport.edgeFor]. On change,
  ///      update the stored side. When [installStandaloneSlides] is
  ///      true, install a fresh slide from old-edge live base to
  ///      new-edge live base.
  ///   3. Else (stays-same edge), do nothing.
  void normalizeForViewport({
    required ViewportSnapshot viewport,
    required bool installStandaloneSlides,
  }) {
    final exits = _entries;
    if (exits == null) return;
    final keys = exits.keys.toList();
    final groups = <
      (Duration duration, Curve curve),
      ({
        Map<TKey, ({double y, double x})> baseline,
        Map<TKey, ({double y, double x})> current,
      })
    >{};
    for (final key in keys) {
      final trueStructuralY = _computeTrueStructuralAt(key);
      if (trueStructuralY < 0) continue;
      final nid = _controller.nidOf(key);
      if (nid < 0) continue;
      final entry = exits[key]!;
      final slideY = _controller.getSlideDeltaNid(nid);
      final slideX = _controller.getSlideDeltaXNid(nid);
      final indent = _controller.getIndent(key);
      final structVisible = viewport.meaningfullyVisible(
        y: trueStructuralY,
        extent: _controller.getCurrentExtentNid(nid),
      );
      if (structVisible) {
        if (installStandaloneSlides) {
          final groupKey = (entry.duration, entry.curve);
          final group = groups.putIfAbsent(
            groupKey,
            () => (
              baseline: <TKey, ({double y, double x})>{},
              current: <TKey, ({double y, double x})>{},
            ),
          );
          group.baseline[key] = (
            y: viewport.baseForEdge(entry.edge) + slideY,
            x: indent + slideX,
          );
          group.current[key] = (
            y: trueStructuralY + slideY,
            x: indent + slideX,
          );
        }
        exits.remove(key);
        continue;
      }
      final newEdge = viewport.edgeFor(trueStructuralY);
      if (newEdge != entry.edge) {
        if (installStandaloneSlides) {
          final groupKey = (entry.duration, entry.curve);
          final group = groups.putIfAbsent(
            groupKey,
            () => (
              baseline: <TKey, ({double y, double x})>{},
              current: <TKey, ({double y, double x})>{},
            ),
          );
          final oldBaseY = viewport.baseForEdge(entry.edge);
          final newBaseY = viewport.baseForEdge(newEdge);
          group.baseline[key] =
              (y: oldBaseY + slideY, x: indent + slideX);
          group.current[key] =
              (y: newBaseY + slideY, x: indent + slideX);
        }
        exits[key] = (
          edge: newEdge,
          duration: entry.duration,
          curve: entry.curve,
        );
        continue;
      }
      // Stays-same edge — no update needed.
    }
    if (exits.isEmpty) _entries = null;

    if (!installStandaloneSlides) return;
    for (final entry in groups.entries) {
      _controller.animateSlideFromOffsets(
        entry.value.baseline,
        entry.value.current,
        duration: entry.key.$1,
        curve: entry.key.$2,
      );
      // Re-set preserve-progress for re-promoted / direction-flipped
      // slides: composition resets the flag and re-promoted keys are
      // no longer in `_entries`, so `_syncPreserveProgressFlags`
      // doesn't catch them.
      for (final key in entry.value.current.keys) {
        _controller.markSlidePreserveProgress(key);
      }
    }
  }

  /// Set the preserve-progress flag for every active edge ghost.
  /// Set-only-true — the engine clears the flag implicitly when the
  /// slide entry is destroyed.
  void syncPreserveProgressFlags() {
    final exits = _entries;
    if (exits == null) return;
    for (final key in exits.keys) {
      _controller.markSlidePreserveProgress(key);
    }
  }

  void reset() {
    _entries = null;
  }
}
