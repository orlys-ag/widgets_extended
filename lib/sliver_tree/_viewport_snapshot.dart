/// Immutable per-frame viewport state shared between the render layer
/// and the slide composer. Owns the predicates the slide pipeline uses
/// to classify rows as "visible" / "meaningfully visible" / "past an
/// edge," so capture-time vs current-time questions can be expressed in
/// terms of two snapshots instead of ad-hoc scroll-offset arithmetic.
///
/// Lives in its own file (rather than inside `render_sliver_tree.dart`)
/// so both the render layer and the slide composer can import it without
/// a backward dependency between them.
library;

import 'dart:math' as math;

/// Which side of the viewport an edge ghost is anchored to.
///
/// Replaces the old "frozen absolute edgeY" representation that the
/// render layer used to keep in `_phantomEdgeExits`. The actual painted
/// Y is derived live from the current viewport via
/// [ViewportSnapshot.baseForEdge], so the ghost stays pinned to the live
/// edge under concurrent scrolling.
enum ViewportEdge {
  top,
  bottom,
}

/// Minimum number of visible pixels a row must show inside the viewport
/// for the slide pipeline to consider it "on-screen" when classifying
/// slide-clamp branches and edge-ghost re-promotion.
///
/// Absolute (not a fraction of extent) so the threshold doesn't grow
/// with row height — a 200 px row that's 30 px visible at the bottom
/// edge is just as perceptible to the user as a 40 px row that's 30 px
/// visible.
///
/// Set to the smallest value that's safely above the `epsilon = 0.5`
/// clamp used by the slide-composer's `applyClampAndInstallNewGhosts`:
/// without that margin, a row whose baseline was just clamped to "just
/// inside the viewport edge" (visiblePx == epsilon == 0.5) would tip
/// the predicate based on floating-point noise alone. 1.0 leaves a 2×
/// margin and still rejects the genuine sub-pixel ε intersections that
/// the predicate exists to filter (a row whose bottom edge intrudes by
/// 0.001 px is `intersects == true` but visually imperceptible).
///
/// Erring small biases the slide pipeline toward "smooth continuation"
/// over "clamp into viewport" for marginally-visible rows: any row the
/// user is already seeing — even faintly — animates from its current
/// painted position rather than jumping to a fully-visible baseline.
///
/// See [ViewportSnapshot.meaningfullyVisible].
const double _kMinMeaningfulVisiblePx = 1.0;

/// Immutable record of the slide-pipeline-relevant viewport state at a
/// single moment in time: the scroll offset, the sliver's paint extent,
/// and the current overhang setting. Owns every viewport-derived value
/// the slide pipeline reads (top/bottom, overhang-adjusted edge bases),
/// so capture-time vs current-time questions can be expressed in code
/// instead of dropping into ad-hoc scroll-offset arithmetic.
final class ViewportSnapshot {
  const ViewportSnapshot({
    required this.scrollOffset,
    required this.paintExtent,
    required this.overhangPx,
  });

  /// Top of the viewport in scroll-space.
  final double scrollOffset;

  /// Sliver paint extent (height of the visible viewport region this
  /// sliver paints into). Used to derive the bottom edge and to scale
  /// the slide overhang.
  final double paintExtent;

  /// Overhang region beyond the viewport edge used by edge-ghost paint
  /// and slide-IN clamps. Captured here (not read live from the
  /// controller) so a snapshot can be reused without picking up later
  /// setting changes mid-batch.
  final double overhangPx;

  double get top => scrollOffset;
  double get bottom => scrollOffset + paintExtent;

  /// Any-pixel-overlap predicate. Use for paint culling, hit-test
  /// admission, ghost re-evaluation, and re-promotion decisions where
  /// the question is "does this row's bounding box intersect the
  /// viewport rect at all."
  bool intersects({
    required double y,
    required double extent,
  }) {
    if (extent <= 0.0) {
      return y >= top && y < bottom;
    }
    return y < bottom && y + extent > top;
  }

  /// "Meaningfully visible" predicate. Used for slide-pipeline branch
  /// decisions: the clamp's priorOn / targetOn classification in
  /// `applyClampAndInstallNewGhosts` and edge-ghost re-promotion in
  /// `reEvaluateGhostStatus` / `normalizeEdgeGhostsForViewport`. The
  /// question being answered is "does the user perceive this row as
  /// on-screen?"
  ///
  /// Neither [intersects] nor a midpoint-in-viewport heuristic answers
  /// it correctly:
  ///
  ///   * [intersects] is too generous — a sub-pixel sliver counts as
  ///     on-screen, which routes a slide-IN composition into the
  ///     on-screen branch (priorOn flips true), the baseline-clamp
  ///     does not fire, and painted at t=0 lands off-viewport.
  ///   * Midpoint-in-viewport is too strict — the threshold scales
  ///     with extent (a 200 px row needs 100 px visible), so a row
  ///     that's 10–40 px visible at the top or bottom edge is
  ///     classified off-screen, falls into !priorOn && !targetOn, and
  ///     (when no in-flight slide exists) gets its slide entry
  ///     suppressed. The row pops into structural place instead of
  ///     animating — visible only on edges, where partial visibility
  ///     is most common.
  ///
  /// Resolution: require a small ABSOLUTE-pixel overlap, capped by
  /// `extent * 0.5` so very-small rows (smaller than the threshold)
  /// only need to be majority visible. See [_kMinMeaningfulVisiblePx].
  bool meaningfullyVisible({
    required double y,
    required double extent,
  }) {
    if (extent <= 0.0) {
      return y >= top && y < bottom;
    }
    final visibleTop = math.max(y, top);
    final visibleBottom = math.min(y + extent, bottom);
    final visiblePx = visibleBottom - visibleTop;
    if (visiblePx <= 0.0) {
      return false;
    }
    return visiblePx >= math.min(_kMinMeaningfulVisiblePx, extent * 0.5);
  }

  /// Edge side a y-coordinate sits past relative to this viewport.
  /// Top side iff `y < top`; otherwise bottom (the symmetric exclusive
  /// convention from [intersects]).
  ViewportEdge edgeFor(double y) {
    return y < top ? ViewportEdge.top : ViewportEdge.bottom;
  }

  /// Live scroll-space base Y for an edge anchor on this viewport. Top
  /// edge = `top - overhangPx` (sits above the viewport by the overhang
  /// region); bottom edge = `bottom + overhangPx`. An edge ghost's
  /// painted Y in scroll-space is `baseForEdge(edge) + slideDelta`.
  double baseForEdge(ViewportEdge edge) {
    return switch (edge) {
      ViewportEdge.top => top - overhangPx,
      ViewportEdge.bottom => bottom + overhangPx,
    };
  }
}
