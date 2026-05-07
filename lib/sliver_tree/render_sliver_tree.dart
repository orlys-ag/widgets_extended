/// Render object for [SliverTree] that handles sliver layout and painting.
library;

import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '_layout_admission_policy.dart';
import '_sticky_header_computer.dart';
import 'sliver_tree_element.dart';
import 'tree_controller.dart';
import 'types.dart';

// ══════════════════════════════════════════════════════════════════════════
// VIEWPORT SNAPSHOT + EDGE GHOST SUPPORT TYPES
// ══════════════════════════════════════════════════════════════════════════

/// Which side of the viewport an edge ghost is anchored to.
///
/// Replaces the old "frozen absolute edgeY" representation in
/// [_phantomEdgeExits]. The actual painted Y is derived live from the
/// current viewport via [_ViewportSnapshot.baseForEdge], so the ghost
/// stays pinned to the live edge under concurrent scrolling.
enum _ViewportEdge {
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
/// clamp used in [RenderSliverTree._applyClampAndInstallNewGhosts]:
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
/// See [_ViewportSnapshot.meaningfullyVisible].
const double _kMinMeaningfulVisiblePx = 1.0;

/// Immutable record of the slide-pipeline-relevant viewport state at a
/// single moment in time: the scroll offset, the sliver's paint extent,
/// and the current overhang setting. Owns every viewport-derived value
/// the slide pipeline reads (top/bottom, overhang-adjusted edge bases),
/// so capture-time vs current-time questions can be expressed in code
/// instead of dropping into ad-hoc scroll-offset arithmetic.
final class _ViewportSnapshot {
  const _ViewportSnapshot({
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
  /// [RenderSliverTree._applyClampAndInstallNewGhosts] and edge-ghost
  /// re-promotion in [RenderSliverTree._reEvaluateGhostStatus] /
  /// [RenderSliverTree._normalizeEdgeGhostsForViewport]. The question
  /// being answered is "does the user perceive this row as on-screen?"
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
  _ViewportEdge edgeFor(double y) {
    return y < top ? _ViewportEdge.top : _ViewportEdge.bottom;
  }

  /// Live scroll-space base Y for an edge anchor on this viewport. Top
  /// edge = `top - overhangPx` (sits above the viewport by the overhang
  /// region); bottom edge = `bottom + overhangPx`. An edge ghost's
  /// painted Y in scroll-space is `baseForEdge(edge) + slideDelta`.
  double baseForEdge(_ViewportEdge edge) {
    return switch (edge) {
      _ViewportEdge.top => top - overhangPx,
      _ViewportEdge.bottom => bottom + overhangPx,
    };
  }
}

/// Pending FLIP slide baseline plus the viewport in which it was
/// captured. Replaces the bare `Map<TKey, ({double y, double x})>?`
/// pending-baseline field. The viewport is consulted at consume time
/// to answer capture-time visibility questions independently of the
/// (possibly different) consume-time viewport.
final class _SlideBaseline<TKey> {
  const _SlideBaseline({
    required this.offsets,
    required this.viewport,
  });

  final Map<TKey, ({double y, double x})> offsets;
  final _ViewportSnapshot viewport;
}

/// Render object for displaying a tree structure as a sliver.
///
/// Uses nodeId-based child storage for straightforward element management.
class RenderSliverTree<TKey, TData> extends RenderSliver {
  /// Creates a render sliver tree.
  RenderSliverTree({
    required TreeController<TKey, TData> controller,
    int maxStickyDepth = 0,
  }) : _controller = controller,
       _maxStickyDepth = maxStickyDepth,
       _sticky = StickyHeaderComputer<TKey, TData>(
         controller: controller,
         maxStickyDepth: maxStickyDepth,
       ),
       _admission = LayoutAdmissionPolicy<TKey, TData>(controller: controller);

  /// Sticky-header computation + cache. Owns every piece of state that
  /// exists solely to compute and cache sticky-header positions; see
  /// [StickyHeaderComputer].
  final StickyHeaderComputer<TKey, TData> _sticky;

  /// Cache-region admission policy for the non-bulk path of Pass 2.
  /// Stateless apart from a controller back-pointer; per-frame inputs are
  /// passed in via parameters. See [LayoutAdmissionPolicy].
  final LayoutAdmissionPolicy<TKey, TData> _admission;

  // ══════════════════════════════════════════════════════════════════════════
  // PROPERTIES
  // ══════════════════════════════════════════════════════════════════════════

  TreeController<TKey, TData> _controller;
  TreeController<TKey, TData> get controller => _controller;
  set controller(TreeController<TKey, TData> value) {
    if (_controller == value) return;
    if (attached) _controller.unregisterRenderHost(_hostCallback);
    _controller = value;
    if (attached) _controller.registerRenderHost(_hostCallback);
    // Pending baseline fields are keyed against the OLD controller's TKey
    // instances; consuming them against the new controller would miss
    // every key (silent no-op) at best, or — if the two controllers share
    // key identities (e.g. string keys reused) — produce wrong deltas at
    // worst.
    _pendingSlideBaseline = null;
    _pendingSlideDuration = null;
    _pendingSlideCurve = null;
    _sticky.controller = value;
    _admission.controller = value;
    // Stale per-node caches keyed by the old controller's keys would
    // produce wrong geometry on the next layout — especially if the new
    // controller's structureGeneration happens to match the cached value
    // (fresh controllers start at 0). Reset everything that's keyed by
    // node and force a structure-change pass.
    _structureChanged = true;
    _lastStructureGeneration = -1;
    _lastVisibleNodeCount = 0;
    _lastTotalScrollExtent = 0.0;
    _animationsWereActive = false;
    // Nid-indexed arrays are sized against the old controller; reset to
    // empty and let [_ensureLayoutCapacity] regrow against the new one.
    _nodeOffsetsByNid = Float64List(0);
    _nodeExtentsByNid = Float64List(0);
    _inCacheRegionByNid = Uint8List(0);
    _writtenCacheRegionNidsLen = 0;
    _sticky.reset();
    // Bulk-only fast-path caches are visible-position-indexed; any
    // structure from the old controller is meaningless under the new one.
    _bulkCumulativesValid = false;
    _bulkCumulativesCount = 0;
    _lastBulkAnimationGeneration = -1;
    _lastFrameUsedBulkCumulatives = false;
    // Do NOT clear `_children`: it is keyed by user TKey, not by the
    // controller's internal nid space, so a key shared between the old
    // and new controller (e.g. the user keeps the same node identity
    // when swapping data sources) maps to the same already-adopted
    // RenderBox. Clearing the map would orphan that box (it stays
    // adopted in the parent-child relationship but vanishes from the
    // iteration map, so paint/hit-test/visitChildren skip it), and the
    // element-side update path won't re-insert it because in-place
    // widget updates don't trigger `insertRenderObjectChild`.
    //
    // Stale entries for keys that exist only under the old controller
    // are evicted by the element manager's GC pass (scheduled from
    // `update` when the controller swaps), which calls
    // `removeRenderObjectChild` and properly drops the adopted box.
    markNeedsLayout();
  }

  int _maxStickyDepth;
  int get maxStickyDepth => _maxStickyDepth;
  set maxStickyDepth(int value) {
    if (_maxStickyDepth == value) return;
    _maxStickyDepth = value;
    _sticky.maxStickyDepth = value;
    markNeedsLayout();
  }

  /// Child manager (the element) that creates/removes children.
  TreeChildManager<TKey>? childManager;

  // ══════════════════════════════════════════════════════════════════════════
  // CHILD STORAGE (nodeId-based)
  // ══════════════════════════════════════════════════════════════════════════

  /// Mounted render boxes keyed by node ID. Keyed by the stable user-level
  /// identifier rather than the controller's internal nid, because nids are
  /// recycled on node purge — a recycled nid would shadow the prior key's
  /// adopted render box until the element's GC pass runs.
  final Map<TKey, RenderBox> _children = <TKey, RenderBox>{};

  /// Count of visible nodes from last layout - used to detect structure changes.
  int _lastVisibleNodeCount = 0;

  /// Last observed structure generation from the controller.
  int _lastStructureGeneration = -1;

  /// Layout-space offsets indexed by the controller's internal nid. Slots
  /// for nids not present in [TreeController.visibleNodes] are undefined —
  /// the layout only reads from slots it just wrote this frame (or a
  /// previous frame under the stable-extent fast path), never from stale
  /// slots left by purged keys.
  ///
  /// Under the bulk-only animation fast path ([_bulkCumulativesValid] == true),
  /// only slots for cache-region nids are kept fresh; offsets for other
  /// visible nids are read on-demand from [_stableCumulative] / [_bulkFullCumulative].
  Float64List _nodeOffsetsByNid = Float64List(0);

  /// Layout-space extents indexed by the controller's internal nid.
  /// Same slot-validity invariant as [_nodeOffsetsByNid].
  Float64List _nodeExtentsByNid = Float64List(0);

  // ──────── Bulk-only animation fast path ────────
  // When a bulk animation is active AND no op-group/standalone animations
  // are active, every node's offset collapses to a simple scalar formula:
  //
  //   offset(i) = _stableCumulative[i] + _bulkValueCached * _bulkFullCumulative[i]
  //
  // where i is the node's position in the controller's visible order. The
  // cumulatives are indexed by visible position (NOT nid), built once when the
  // bulk group's membership snapshot changes, and remain valid as the
  // bulk's scalar value ticks. This turns the O(N)-per-frame Pass 1 walk
  // during expandAll / collapseAll into O(1).

  /// Prefix sum of stable (non-bulk-member) extents. Size = n+1 where
  /// n = visible node count at last rebuild. Valid iff [_bulkCumulativesValid].
  Float64List _stableCumulative = Float64List(0);

  /// Prefix sum of full target extents for bulk members (0 elsewhere).
  /// Size = n+1 where n = visible node count at last rebuild. Valid iff
  /// [_bulkCumulativesValid].
  Float64List _bulkFullCumulative = Float64List(0);

  /// Visible-node count at the last cumulative rebuild.
  int _bulkCumulativesCount = 0;

  /// Whether [_stableCumulative] / [_bulkFullCumulative] match the current visible order
  /// and bulk group membership.
  bool _bulkCumulativesValid = false;

  /// Last observed [TreeController.bulkAnimationGeneration] at cumulative rebuild.
  int _lastBulkAnimationGeneration = -1;

  /// Cached bulk animation value for the current frame, to avoid
  /// repeatedly reading it from the controller during inner loops.
  double _bulkValueCached = 0.0;

  /// Whether the previous frame ran the bulk-only fast path. Used to
  /// force a full Pass 1 walk on the frame we exit fast path, because
  /// during the fast path only cache-region nid slots are fresh.
  bool _lastFrameUsedBulkCumulatives = false;

  /// Rebuilds [_stableCumulative] and [_bulkFullCumulative] from the current visible
  /// order and bulk group membership. O(N) but amortized across many
  /// frames of a bulk animation.
  ///
  /// Reads the per-key bulk membership through [bulkData] (a single
  /// snapshot fetched once at the start of the frame) so the inner loop
  /// avoids the four-getter tax on the controller surface.
  void _rebuildBulkCumulatives(
    List<TKey> visibleNodes,
    BulkAnimationData<TKey> bulkData,
  ) {
    final n = visibleNodes.length;
    if (_stableCumulative.length < n + 1) {
      final newLen = math.max(
        n + 1,
        math.max(16, _stableCumulative.length * 2),
      );
      _stableCumulative = Float64List(newLen);
      _bulkFullCumulative = Float64List(newLen);
    }
    double sStable = 0.0;
    double sBulkFull = 0.0;
    _stableCumulative[0] = 0.0;
    _bulkFullCumulative[0] = 0.0;
    // Read nids straight from the order buffer to skip the
    // [TKey]→nid hash inside this O(N)-per-frame loop. Membership
    // check goes through the snapshot's nid-keyed mirror (Uint8List read).
    final orderNids = controller.orderNidsView;
    for (int i = 0; i < n; i++) {
      final nid = orderNids[i];
      final full = controller.getEstimatedExtentNid(nid);
      if (bulkData.containsMemberNid(nid)) {
        sBulkFull += full;
      } else {
        // Non-bulk nodes are stable during bulk-only frames (gated by
        // !hasOpGroupAnimations at entry), so their full extent equals
        // their current extent.
        sStable += full;
      }
      _stableCumulative[i + 1] = sStable;
      _bulkFullCumulative[i + 1] = sBulkFull;
    }
    _bulkCumulativesCount = n;
    _bulkCumulativesValid = true;
  }

  /// Offset at visible index [i] under the bulk-only fast path.
  /// Caller is responsible for ensuring [_bulkCumulativesValid] is true.
  double _offsetAtVisibleIndex(int i) {
    return _stableCumulative[i] + _bulkValueCached * _bulkFullCumulative[i];
  }

  /// Admits cache-region members under the bulk-only fast path.
  ///
  /// Invoked from Pass 2 when [_bulkCumulativesValid] is true. Pulls per-row
  /// offset/extent from the precomputed cumulatives and syncs them into the
  /// per-nid slots so downstream code (Pass 2 measurement, paint extent,
  /// paint, hit-test) reads correct values without a branch per access.
  /// Anchors the admission band to full-space (`fullCacheEnd`) so low
  /// `bulkValue` doesn't admit thousands of sub-pixel rows on frame 1 of
  /// `expandAll`.
  ///
  /// Body is byte-equivalent to the pre-extraction `if (_bulkCumulativesValid)`
  /// branch of the original Pass 2 loop, with the surrounding outer-loop
  /// dispatch hoisted to the call site. Preserves the same per-row writes
  /// and sparse-track buffer maintenance.
  int _admitBulkFastPath({
    required int cacheStartIndex,
    required List<TKey> visibleNodes,
    required double fullCacheEnd,
  }) {
    int cacheEndIndex = cacheStartIndex;
    final orderNids = controller.orderNidsView;
    for (int i = cacheStartIndex; i < visibleNodes.length; i++) {
      final nid = orderNids[i];
      final offset = _offsetAtVisibleIndex(i);
      _nodeOffsetsByNid[nid] = offset;
      _nodeExtentsByNid[nid] = _offsetAtVisibleIndex(i + 1) - offset;
      final fullOffset = _stableCumulative[i] + _bulkFullCumulative[i];
      if (fullOffset >= fullCacheEnd) break;
      _inCacheRegionByNid[nid] = 1;
      _writeCacheRegionNid(nid);
      cacheEndIndex = i + 1;
    }
    return cacheEndIndex;
  }

  /// Flags indexed by nid: non-zero iff the node lies in the current cache
  /// region. Cleared sparsely at the start of Pass 2 each layout (via
  /// [_writtenCacheRegionNids]), then set for every cache-region member.
  Uint8List _inCacheRegionByNid = Uint8List(0);

  /// Nids written into [_inCacheRegionByNid] last frame. Drives the sparse
  /// clear at the start of each Pass 2 — zeroing only the slots actually
  /// dirtied avoids an O(nidCapacity) memset on every layout.
  ///
  /// Mirrors the pattern used by `_writtenStickyNids` in
  /// [StickyHeaderComputer]. Backed by an [Int32List] with explicit length
  /// tracking ([_writtenCacheRegionNidsLen]) so per-frame appends don't box
  /// ints. Capacity is bounded by the cache region size (≈ viewport rows),
  /// grown by doubling when exceeded.
  Int32List _writtenCacheRegionNids = Int32List(64);
  int _writtenCacheRegionNidsLen = 0;

  /// Number of nids in [_writtenCacheRegionNids]. Exposed for tests that
  /// verify the sparse-clear bound is `O(viewport)`, not `O(nidCapacity)`.
  @visibleForTesting
  int get debugWrittenCacheRegionNidCount => _writtenCacheRegionNidsLen;

  /// Appends [nid] to [_writtenCacheRegionNids], doubling capacity when full.
  void _writeCacheRegionNid(int nid) {
    if (_writtenCacheRegionNidsLen == _writtenCacheRegionNids.length) {
      final grown = Int32List(_writtenCacheRegionNids.length * 2);
      grown.setRange(0, _writtenCacheRegionNidsLen, _writtenCacheRegionNids);
      _writtenCacheRegionNids = grown;
    }
    _writtenCacheRegionNids[_writtenCacheRegionNidsLen++] = nid;
  }

  /// Iteration count of the post-sticky parentData refresh loop on the
  /// last layout. Reset at the top of `performLayout`. Used by Phase 4's
  /// regression test to verify the loop bound is `O(_children)`, not
  /// `O(visibleNodes)`, without relying on flaky wall-time measurements.
  @visibleForTesting
  int debugLastParentDataRefreshIterationCount = 0;

  /// Grows all nid-indexed layout arrays to match the controller's current
  /// nid capacity. Doubles on each realloc so amortized growth is O(1)
  /// per node insertion.
  void _ensureLayoutCapacity() {
    final needed = _controller.nidCapacity;
    if (needed <= _nodeOffsetsByNid.length) return;
    int cap = _nodeOffsetsByNid.isEmpty ? 16 : _nodeOffsetsByNid.length;
    while (cap < needed) {
      cap *= 2;
    }
    final newOffsets = Float64List(cap);
    newOffsets.setRange(0, _nodeOffsetsByNid.length, _nodeOffsetsByNid);
    _nodeOffsetsByNid = newOffsets;
    final newExtents = Float64List(cap);
    newExtents.setRange(0, _nodeExtentsByNid.length, _nodeExtentsByNid);
    _nodeExtentsByNid = newExtents;
    final newCacheFlags = Uint8List(cap);
    newCacheFlags.setRange(0, _inCacheRegionByNid.length, _inCacheRegionByNid);
    _inCacheRegionByNid = newCacheFlags;
    _sticky.resizeForCapacity(cap);
  }

  /// Whether structure changed since last layout.
  bool _structureChanged = true;

  /// Cached total scroll extent from the last Pass 1 run.
  double _lastTotalScrollExtent = 0.0;

  /// Whether animations were active in the previous frame.
  /// Used to ensure one final Pass 1 runs after animation settles so that
  /// extents snapshot the final (progress=1) values.
  bool _animationsWereActive = false;

  /// Marks the tree structure as changed, clears layout caches, and
  /// requests a new layout pass.
  ///
  /// Called by the element during hot reload to ensure children are
  /// recreated with the new `nodeBuilder`.
  void markStructureChanged() {
    _structureChanged = true;
    _sticky.dirty = true;
    markNeedsLayout();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FLIP slide baseline — set by a caller (typically TreeReorderController)
  // BEFORE it mutates the controller. The next [performLayout] consumes the
  // baseline IN-FRAME: it takes a second snapshot after the new offsets have
  // been computed and calls [TreeController.animateSlideFromOffsets] so the
  // paint pass of the SAME frame renders rows at their prior painted position
  // (slide at progress 0) — avoiding the one-frame "jump to new position,
  // then slide back to old" flicker that a post-frame callback would produce.
  // ──────────────────────────────────────────────────────────────────────────

  /// Pending FLIP slide baseline (offsets + capture viewport) plus the
  /// duration/curve from the originating mutation. The viewport is
  /// captured alongside the offset map so consume can answer
  /// capture-time visibility questions independently of the (possibly
  /// scrolled-since) consume-time viewport. See [_SlideBaseline].
  _SlideBaseline<TKey>? _pendingSlideBaseline;
  Duration? _pendingSlideDuration;
  Curve? _pendingSlideCurve;

  /// Tracks rows whose slide was installed from a phantom anchor (a
  /// previously-hidden node now reparented into a visible position) AND
  /// whose anchor was on-screen at install time. Each such row needs a
  /// direction-aware clip during paint so the anchor visually occludes
  /// the emerging row's overlap region — the "slides out from behind
  /// the parent" effect.
  ///
  /// Maps emerging key → anchor key. Used by `_paintRow` to look up the
  /// anchor's current painted bounds (which may have shifted if the
  /// anchor itself is sliding) and clip accordingly.
  ///
  /// Cleared at the start of each baseline consumption — no entries
  /// persist across slide cycles. An entry whose slide has settled
  /// (currentDelta == 0) is effectively a no-op (clip excludes nothing
  /// because the row no longer overlaps the anchor) so lazy cleanup
  /// is safe.
  Map<TKey, TKey>? _phantomClipAnchors;

  /// Tracks rows that were visible at staging time but are now hidden
  /// (reparented under a collapsed parent). Each such "ghost" row needs:
  ///   1. Its render box retained past the visible-order purge ([isNodeRetained]).
  ///   2. A separate paint pass — the standard pass iterates visibleNodes
  ///      which excludes ghosts.
  ///   3. A direction-aware clip (same mechanism as entry-phantom
  ///      [_phantomClipAnchors]) so the row visually disappears INTO
  ///      the collapsed parent's row.
  ///
  /// Maps ghost key → exit anchor key. The ghost is painted at
  /// `anchor.paintedY + ghost.slideDelta` — as the slide settles, the
  /// ghost converges on the anchor's position and the clip fully
  /// occludes it.
  ///
  /// Entries are removed lazily during the ghost paint pass when the
  /// ghost's slide has settled (currentDelta == 0 AND currentDeltaX == 0).
  Map<TKey, TKey>? _phantomExitGhosts;

  /// Synthetic-anchor exit ghosts: rows whose new structural position is
  /// off-screen (slide-OUT distance exceeds viewport) and that animate out
  /// toward the viewport edge instead of to the (invisible) structural
  /// position. The row is removed from standard paint/hit-test/transform
  /// paths and painted via a parallel ghost pass at
  /// `_edgeGhostBaseY(entry, currentViewport) + slideDelta`.
  ///
  /// Each entry stores the *side* of the viewport the ghost is anchored
  /// to (top or bottom) plus the original install duration and curve so
  /// scroll-induced re-promotion ([_normalizeEdgeGhostsForViewport]) can
  /// install the re-promotion slide using the same animation parameters.
  ///
  /// The actual painted Y is derived live from the current viewport via
  /// [_edgeGhostBaseY] / [_ViewportSnapshot.baseForEdge], so the ghost
  /// stays pinned to the live edge under concurrent scrolling. If the
  /// row's true structural comes back into the viewport mid-slide (user
  /// scrolled toward it), [_normalizeEdgeGhostsForViewport] re-installs
  /// it as a normal slide ending at structural — avoiding a snap at
  /// slide end. If the row remains off-screen but switches sides
  /// (top→bottom or vice versa), the helper updates the stored edge
  /// side and composes a direction-flip slide.
  ///
  /// Pruned eagerly during the edge-ghost paint pass when the slide
  /// settles, lazily at the start of `_consumeSlideBaselineIfAny`.
  Map<TKey, ({_ViewportEdge edge, Duration duration, Curve curve})>?
      _phantomEdgeExits;

  /// Last-observed `constraints.scrollOffset`, captured at the end of
  /// every `performLayout`. Used by [_checkGhostRepromotionOnScroll] to
  /// detect scroll changes between layouts (mutation-less re-paints) so
  /// active edge ghosts can be re-promoted when the user scrolls toward
  /// their structural destination during the slide.
  ///
  /// `double.nan` initially (first layout has no previous to compare).
  double _lastObservedScrollOffset = double.nan;

  /// Cached callback registered with the controller's host registry on
  /// `attach` and unregistered on `detach`. `late final` so the same
  /// closure identity is registered and unregistered (the registry is a
  /// `Set` keyed by identity).
  late final TreeRenderHost _hostCallback =
      ({required Duration duration, required Curve curve}) {
        // Mirror beginSlideBaseline's geometry guard so the bool return
        // contract reflects "host could participate at all."
        if (geometry == null) return false;
        beginSlideBaseline(duration: duration, curve: curve);
        return true;
      };

  /// Captures the current painted offsets so the next [performLayout] can
  /// install a FLIP slide from them to the post-mutation offsets.
  ///
  /// Call this BEFORE invoking a structural mutation on the controller
  /// (`reorderRoots`, `reorderChildren`, `moveNode`). Calling it after
  /// the mutation would capture the already-new offsets and produce a
  /// zero-delta (no visible slide).
  ///
  /// **First-wins semantic:** if a baseline is already pending this frame
  /// (from a prior call by any entry path — host fan-out OR a direct
  /// caller like the reorder controller), this call is a no-op. The first
  /// stage captured the truly-painted positions; subsequent stages would
  /// read already-mutated controller state and produce wrong deltas for
  /// rows touched by earlier same-frame calls.
  ///
  /// **Caller contract:** every successful stage MUST be followed by a
  /// structural mutation that triggers a layout pass in the same frame
  /// (or via a microtask before the next frame). Otherwise the staged
  /// baseline stays pending and blocks all subsequent stages until some
  /// other layout-triggering mutation flushes it.
  ///
  /// **Internal contract** — intended for the reorder controller and
  /// the controller's host fan-out. External callers should not invoke
  /// this directly.
  void beginSlideBaseline({required Duration duration, required Curve curve}) {
    // Not-laid-out guard: snapshotVisibleOffsets walks visible rows
    // accumulating extents from controller state. Before first layout,
    // those extents fall through to defaultExtent and the snapshot is
    // fictitious. Silently no-op rather than stage a garbage baseline.
    if (geometry == null) return;
    // First-wins.
    if (_pendingSlideBaseline != null) return;
    _pendingSlideBaseline = _SlideBaseline<TKey>(
      offsets: snapshotVisibleOffsets(),
      viewport: _currentViewportSnapshot(),
    );
    _pendingSlideDuration = duration;
    _pendingSlideCurve = curve;
  }

  /// Consumes a pending baseline (if any) by snapshotting post-mutation
  /// offsets and installing the FLIP slide. Safe to call when none is
  /// pending — returns immediately.
  ///
  /// Runs inside [performLayout]. [TreeController.animateSlideFromOffsets]
  /// is safe to call here because the slide is driven by a raw [Ticker]:
  /// `Ticker.start()` does not fire listeners synchronously, so the first
  /// tick — and with it the listener chain that reaches `markNeedsLayout`
  /// / `markNeedsPaint` on this sliver — lands on the next vsync, outside
  /// layout.
  void _consumeSlideBaselineIfAny({
    required _ViewportSnapshot currentViewport,
  }) {
    final pending = _pendingSlideBaseline;
    if (pending == null) return;
    final baseline = pending.offsets;
    final captureViewport = pending.viewport;
    final duration = _pendingSlideDuration!;
    final curve = _pendingSlideCurve!;
    _pendingSlideBaseline = null;
    _pendingSlideDuration = null;
    _pendingSlideCurve = null;
    final current = snapshotVisibleOffsets();

    // CRITICAL: do NOT clear _phantomClipAnchors or _phantomExitGhosts
    // unconditionally. Both can hold entries whose slides are still in
    // flight from a prior consume cycle.
    //
    // Clearing _phantomExitGhosts would drop ghosts that an unrelated
    // moveNode happened to coincide with → ghost row pops out of
    // existence.
    //
    // Clearing _phantomClipAnchors mid-slide would remove the
    // direction-aware clip that was occluding part of an entry-phantom
    // row → the previously-occluded portion suddenly appears (visual
    // pop on re-move).
    //
    // Instead, lazy-prune entries whose slides have settled
    // (currentDelta == 0 AND currentDeltaX == 0). New phantom processing
    // below will overwrite any entry whose key is touched this cycle.
    _phantomClipAnchors?.removeWhere((key, _) {
      final nid = _controller.nidOf(key);
      if (nid < 0) return true; // key gone entirely
      return _controller.getSlideDeltaNid(nid) == 0.0 &&
          _controller.getSlideDeltaXNid(nid) == 0.0;
    });
    if (_phantomClipAnchors?.isEmpty ?? false) _phantomClipAnchors = null;

    // Mirror the lazy-prune for edge ghosts: remove entries whose slide
    // has settled or whose key has been freed.
    _pruneSettledEdgeGhosts();

    // Rewrite ghost entries in baseline to use the CURRENT viewport's
    // edge base. This is the prerequisite that makes §7.2's
    // "snapshot uses live base" rule compose correctly under scroll
    // change. See plan §9.1 for the full derivation. Without this
    // rewrite, a stays-same edge ghost whose viewport scrolled by Δ
    // between staging and consume would feed `rawDeltaY = -Δ` into the
    // engine — visibly drifting the slide instead of leaving it alone.
    //
    // Direction-flip and re-promotion paths (§7.4, §7.5) still produce
    // non-zero deltas because they explicitly write DIFFERENT edge
    // bases for prior vs current.
    final ghostsForRewrite = _phantomEdgeExits;
    if (ghostsForRewrite != null) {
      for (final ghostEntry in ghostsForRewrite.entries) {
        final ghostKey = ghostEntry.key;
        if (!baseline.containsKey(ghostKey)) continue;
        final ghostNid = controller.nidOf(ghostKey);
        if (ghostNid < 0) continue;
        final ghostSlideY = controller.getSlideDeltaNid(ghostNid);
        final ghostSlideX = controller.getSlideDeltaXNid(ghostNid);
        final ghostIndent = controller.getIndent(ghostKey);
        baseline[ghostKey] = (
          y: _edgeGhostBaseY(ghostEntry.value, currentViewport) + ghostSlideY,
          x: ghostIndent + ghostSlideX,
        );
      }
    }

    // Per plan §6: capture-time visibility checks use captureViewport,
    // current-time checks use currentViewport. New edge anchors created
    // in this consume use currentViewport. All viewport math is routed
    // through the snapshot's helper methods rather than ad-hoc
    // top/bottom/overhang scalars.

    // Augment baseline with phantom priors for keys that were hidden at
    // moveNode time but became visible after mutation. The controller
    // staged a key→anchor relationship for each such key during
    // moveNode(animate: true); resolve them to scroll-space positions
    // here using the just-staged baseline (anchor's painted position
    // at STAGING time) or the staging-time viewport edge (anchor was
    // off-screen at staging).
    //
    // Per plan §6: this is a CAPTURE-TIME question — "where was the
    // anchor at staging?" — so the visibility check and the edge
    // fallback both use `captureViewport`, not `currentViewport`.
    // anchorPos.y comes from `pending.offsets`, which was captured
    // against captureViewport at staging.
    final relationships = controller.takePendingPhantomAnchors();
    if (relationships != null && relationships.isNotEmpty) {
      for (final entry in relationships.entries) {
        final key = entry.key;
        final anchorKey = entry.value;
        // Skip if baseline already has a real prior — the row was
        // visible at staging time and doesn't need a phantom.
        if (baseline.containsKey(key)) continue;
        // Skip if the row didn't actually become visible (e.g. moved
        // into another collapsed parent). No slide to install.
        if (!current.containsKey(key)) continue;
        final anchorPos = baseline[anchorKey];
        if (anchorPos == null) continue;
        final anchorOnScreen = captureViewport.intersects(
          y: anchorPos.y,
          extent: _currentExtentOfKey(anchorKey),
        );
        // Add the ghost row's own in-flight slideDelta to the injected
        // baseline so engine composition gives the right painted-at-t=0
        // when the row already had a slide entry (rare composition case).
        // For the typical first-install case, ghostSlide* is 0 and the
        // formula reduces to today's behavior.
        final ghostNid = controller.nidOf(key);
        final ghostSlideY = ghostNid >= 0
            ? controller.getSlideDeltaNid(ghostNid)
            : 0.0;
        final ghostSlideX = ghostNid >= 0
            ? controller.getSlideDeltaXNid(ghostNid)
            : 0.0;
        if (anchorOnScreen) {
          // Anchor visible: phantom prior = anchor's painted position
          // (anchorPos already includes anchor's slideDelta via the
          // staging snapshot) plus the ghost row's own slideDelta.
          // Clip during paint so the anchor occludes the emerging row's
          // overlap.
          baseline[key] = (
            y: anchorPos.y + ghostSlideY,
            x: anchorPos.x + ghostSlideX,
          );
          (_phantomClipAnchors ??= <TKey, TKey>{})[key] = anchorKey;
        } else {
          // Anchor was off-screen at staging: fall back to the
          // staging-time viewport edge nearest the anchor's structural
          // location. No clip — the row enters from a region nobody
          // could paint into at staging.
          final edge = captureViewport.edgeFor(anchorPos.y);
          final edgeY = captureViewport.baseForEdge(edge);
          baseline[key] = (
            y: edgeY + ghostSlideY,
            x: anchorPos.x + ghostSlideX,
          );
        }
      }
    }

    // Symmetric exit-phantom handling: keys that were visible at staging
    // time but are now hidden. Inject the exit anchor's painted position
    // as the slide DESTINATION (current[key] = anchor.position), retain
    // the ghost render box past visible-order purge, and paint the ghost
    // in a separate pass clipped so it visually disappears into the
    // anchor's row.
    final exitRels = controller.takePendingExitPhantomAnchors();
    if (exitRels != null && exitRels.isNotEmpty) {
      for (final entry in exitRels.entries) {
        final key = entry.key;
        final anchorKey = entry.value;
        // Skip if the row IS in current — it became visible somehow,
        // not actually exiting. Standard slide path applies.
        if (current.containsKey(key)) continue;
        // Skip if baseline doesn't have the row — it wasn't actually
        // visible at staging time. Can't slide a row with no prior.
        if (!baseline.containsKey(key)) continue;
        // Anchor must be in current (it's the new visible parent — must
        // be in visibleNodes post-mutation). The visibility question is
        // CURRENT-TIME ("is the anchor visible NOW"), so use
        // currentViewport.
        final anchorCurrent = current[anchorKey];
        if (anchorCurrent == null) continue;
        final anchorOnScreen = currentViewport.intersects(
          y: anchorCurrent.y,
          extent: _currentExtentOfKey(anchorKey),
        );
        // Add the ghost row's own in-flight slideDelta — see entry-phantom
        // block above for the rationale.
        final ghostNid = controller.nidOf(key);
        final ghostSlideY = ghostNid >= 0
            ? controller.getSlideDeltaNid(ghostNid)
            : 0.0;
        final ghostSlideX = ghostNid >= 0
            ? controller.getSlideDeltaXNid(ghostNid)
            : 0.0;
        if (anchorOnScreen) {
          // Inject destination = anchor's painted position (anchorCurrent
          // includes anchor's slide) + ghost row's own slideDelta. Slide
          // engine composes correctly across paint-base changes.
          current[key] = (
            y: anchorCurrent.y + ghostSlideY,
            x: anchorCurrent.x + ghostSlideX,
          );
          (_phantomExitGhosts ??= <TKey, TKey>{})[key] = anchorKey;
          // Ghost also needs the direction-aware clip so the anchor
          // occludes it as it slides in.
          (_phantomClipAnchors ??= <TKey, TKey>{})[key] = anchorKey;
        } else {
          // Anchor off-screen at consume: ghost slides toward the
          // current viewport edge (with overhang) nearest the anchor's
          // structural position. No clip — the ghost simply slides
          // off-screen and disappears.
          final edge = currentViewport.edgeFor(anchorCurrent.y);
          final edgeY = currentViewport.baseForEdge(edge);
          current[key] = (
            y: edgeY + ghostSlideY,
            x: anchorCurrent.x + ghostSlideX,
          );
          (_phantomExitGhosts ??= <TKey, TKey>{})[key] = anchorKey;
        }
      }
    }

    // Render-side fallback for vanishing keys: any baseline key NOT in
    // current AND not handled by the controller-staged exit phantom
    // above. The most common case is a ghost re-moved to ANOTHER
    // collapsed parent — the controller's exit-phantom check requires
    // wasVisible=true (in _order) at moveNode time, but a ghost is
    // hidden, so the controller doesn't stage. Without this fallback
    // the row gets no slide and pops out of existence on the next
    // ghost-paint pass when its old (now-stale) ghost relationship is
    // pruned by the slide-settled check.
    //
    // Walk the controller's CURRENT parent chain to find the deepest
    // visible new ancestor — same anchor logic as the controller's
    // exit-phantom block, just derived render-side because we have
    // access to controller.getParent and isVisible.
    for (final key in baseline.keys.toList()) {
      if (current.containsKey(key)) continue;
      // Already handled by controller-staged exit phantom above? Skip.
      if (_phantomExitGhosts != null &&
          _phantomExitGhosts!.containsKey(key)) {
        continue;
      }
      TKey? cursor = controller.getParent(key);
      while (cursor != null && !controller.isVisible(cursor)) {
        cursor = controller.getParent(cursor);
      }
      if (cursor == null) continue;
      final anchorCurrent = current[cursor];
      if (anchorCurrent == null) continue;
      // Current-time visibility check — fallback runs at consume time
      // and asks whether the new anchor is visible NOW.
      final anchorOnScreen = currentViewport.intersects(
        y: anchorCurrent.y,
        extent: _currentExtentOfKey(cursor),
      );
      // Add the ghost row's own in-flight slideDelta — same rationale as
      // controller-staged exit-phantom block above.
      final ghostNid = controller.nidOf(key);
      final ghostSlideY = ghostNid >= 0
          ? controller.getSlideDeltaNid(ghostNid)
          : 0.0;
      final ghostSlideX = ghostNid >= 0
          ? controller.getSlideDeltaXNid(ghostNid)
          : 0.0;
      if (anchorOnScreen) {
        current[key] = (
          y: anchorCurrent.y + ghostSlideY,
          x: anchorCurrent.x + ghostSlideX,
        );
        (_phantomExitGhosts ??= <TKey, TKey>{})[key] = cursor;
        (_phantomClipAnchors ??= <TKey, TKey>{})[key] = cursor;
      } else {
        final edge = currentViewport.edgeFor(anchorCurrent.y);
        final edgeY = currentViewport.baseForEdge(edge);
        current[key] = (
          y: edgeY + ghostSlideY,
          x: anchorCurrent.x + ghostSlideX,
        );
        (_phantomExitGhosts ??= <TKey, TKey>{})[key] = cursor;
      }
    }

    // Lazy-prune ghosts that became visible again. A ghost re-moved
    // back to a visible parent now sits in current (visibleNodes),
    // gets a normal slide via the standard path, and must NOT also
    // paint via the ghost pass (would render twice). The augmented
    // baseline already captured the ghost's painted position so the
    // re-move slide installs from the right starting point.
    final ghostMap = _phantomExitGhosts;
    if (ghostMap != null) {
      ghostMap.removeWhere((key, _) => controller.isVisible(key));
      if (ghostMap.isEmpty) _phantomExitGhosts = null;
    }

    // Step 3b: a row that was an edge ghost in the previous cycle has
    // now become an exit-phantom (anchor-based) ghost via the phantom
    // injection above (mutation moved it under a hidden parent).
    // Drop the edge-ghost entry — the exit-phantom mechanism takes over
    // paint and composition. No preserve-flag clear needed (set-only
    // semantics; engine resets via composition path).
    _dropEdgeExitsForKeysThatBecameAnchorGhosts();

    // Steps 4-6: re-evaluate active edge ghosts (re-promote / direction
    // flip / stays-same), apply slide-IN clamp + new ghost installs for
    // non-ghost keys, then remove ghost-stays-same-edge from the batch
    // so the engine doesn't re-baseline them.
    final ghostKeysTouchedThisCycle = <TKey>{};
    _reEvaluateGhostStatus(
      baseline: baseline,
      current: current,
      viewport: currentViewport,
      duration: duration,
      curve: curve,
      ghostKeysTouchedThisCycle: ghostKeysTouchedThisCycle,
    );
    _applyClampAndInstallNewGhosts(
      baseline: baseline,
      current: current,
      viewport: currentViewport,
      duration: duration,
      curve: curve,
      ghostKeysTouchedThisCycle: ghostKeysTouchedThisCycle,
    );
    _removeGhostStaysFromBatch(baseline, current, ghostKeysTouchedThisCycle);

    // Snapshot the keys that the engine batch is about to touch — we
    // need this for Step 8 below (mark all of them with preserve so
    // subsequent batches don't restart their progress clocks).
    final batchedKeys = <TKey>[];
    for (final key in baseline.keys) {
      if (current.containsKey(key)) batchedKeys.add(key);
    }

    // Step 7: hand to engine. maxSlideDistance no longer passed —
    // render-side clamp/ghost mechanism bounds the delta to
    // viewport+overhang per row. Direct callers of
    // controller.animateSlideFromOffsets can still pass it explicitly
    // for safety.
    controller.animateSlideFromOffsets(
      baseline,
      current,
      duration: duration,
      curve: curve,
    );

    // Step 7b: re-prune `_phantomEdgeExits` after the engine call.
    //
    // The engine's composition path (`_slide_animation_engine.dart`,
    // composition branch with `composedY == 0.0 && composedX == 0.0`)
    // CLEARS the slide entry without notifying the render layer. If
    // this row was kept in `_phantomEdgeExits` by `_reEvaluateGhostStatus`'s
    // direction-flip branch (or by stays-same), the entry survives the
    // engine clear. The next paint then takes a broken path:
    //
    //   * Standard pass A skips the row because
    //     `_phantomEdgeExits.containsKey(nodeId)` is true.
    //   * Edge-ghost paint pass A.6 sees `getSlideDeltaNid == 0` and
    //     prunes the entry instead of painting (lazy-prune of settled
    //     ghosts).
    //
    // Net effect: the row is invisible for one paint while its
    // structural slot in the viewport sits empty. The user sees a gap
    // that only resolves on the NEXT layout (e.g. a scroll), where the
    // map no longer has the entry and standard paint runs normally.
    //
    // The repeated `_pruneSettledEdgeGhosts()` here drops any entry the
    // engine just cleared, so standard paint A can render the row at
    // its (already-up-to-date by Pass 2 measurement) `parentData.layoutOffset`.
    _pruneSettledEdgeGhosts();

    // Step 8: mark preserve-progress flag for EVERY slide installed/
    // composed by this consume — edge ghosts, anchor-based exit ghosts,
    // AND every other slide in the batch. Without this, subsequent
    // batches (rapid mutations / autoscroll) would re-baseline these
    // un-touched-next-time slides — restarting their progress clock and
    // making them effectively never settle. The user-visible symptom
    // was rows stuck mid-slide, appearing as "gaps" / "wrong widget at
    // position" / "snap to final at settle" in the example app's
    // `Reparent ALL` repeated-tap scenario.
    //
    // Set-only semantics: engine clears the flag implicitly when the
    // slide entry is destroyed (settles, cancelled, or replaced via
    // composition).
    for (final key in batchedKeys) {
      controller.markSlidePreserveProgress(key);
    }
    _syncPreserveProgressFlags();

    // Step 9: clean up if engine has no slides remaining (Duration.zero
    // short-circuit, all installs were no-ops, etc.).
    if (!controller.hasActiveSlides) {
      _phantomEdgeExits = null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // EDGE-GHOST HELPERS (synthetic-anchor exit ghosts for long slide-OUTs)
  // See docs/plans/slide-viewport-clamp-v2.3.2.md for the design.
  // ──────────────────────────────────────────────────────────────────────────

  /// Lazy-prune `_phantomEdgeExits` entries whose slide has settled or
  /// whose key has been freed. Mirrors the `_phantomClipAnchors` prune
  /// pattern at the top of `_consumeSlideBaselineIfAny`.
  void _pruneSettledEdgeGhosts() {
    final exits = _phantomEdgeExits;
    if (exits == null) return;
    exits.removeWhere((key, _) {
      final nid = _controller.nidOf(key);
      if (nid < 0) return true;
      return _controller.getSlideDeltaNid(nid) == 0.0 &&
          _controller.getSlideDeltaXNid(nid) == 0.0;
    });
    if (exits.isEmpty) _phantomEdgeExits = null;
  }

  /// Computes the row's true structural Y (no slideDelta), or -1 if the
  /// row is not in `visibleNodes`. O(N_visible). Called only for edge-
  /// ghost keys during re-promotion checks; total cost is bounded by
  /// (N_ghosts × N_visible) per consume which is tiny in practice.
  double _computeTrueStructuralAt(TKey key) {
    final visible = controller.visibleNodes;
    final orderNids = controller.orderNidsView;
    double structural = 0.0;
    for (int i = 0; i < visible.length; i++) {
      if (visible[i] == key) return structural;
      structural += controller.getCurrentExtentNid(orderNids[i]);
    }
    return -1.0;
  }

  double _currentExtentOfKey(TKey key) {
    final nid = controller.nidOf(key);
    return nid >= 0 ? controller.getCurrentExtentNid(nid) : 0.0;
  }

  /// Builds a [_ViewportSnapshot] describing the layout's current
  /// viewport state. Reads `constraints.scrollOffset`, the sliver's
  /// `viewportMainAxisExtent`, and the controller's live overhang
  /// setting. Cheap to call and intended to be used at every entry to
  /// the slide pipeline so capture-time vs current-time questions are
  /// expressed against an explicit viewport rather than scattered
  /// scroll-offset arithmetic.
  ///
  /// Caller must guarantee [constraints] is set (i.e. `performLayout`
  /// has begun, OR a layout has previously completed and `geometry`
  /// is non-null). External entry points (`beginSlideBaseline`) check
  /// `geometry != null` before calling.
  _ViewportSnapshot _currentViewportSnapshot() {
    final paintExtent = constraints.viewportMainAxisExtent;
    return _ViewportSnapshot(
      scrollOffset: constraints.scrollOffset,
      paintExtent: paintExtent,
      overhangPx: paintExtent * controller.slideClampOverhangViewports,
    );
  }

  /// Live scroll-space base Y for an edge-ghost entry against the
  /// supplied viewport. Single source of truth for the conversion
  /// between an [_phantomEdgeExits] entry and the position the row's
  /// paint base should sit at right now. Replaces every former direct
  /// read of `entry.edgeY` (which was a frozen absolute, stale under
  /// scroll change).
  double _edgeGhostBaseY(
    ({_ViewportEdge edge, Duration duration, Curve curve}) entry,
    _ViewportSnapshot viewport,
  ) {
    return viewport.baseForEdge(entry.edge);
  }

  /// Step 3b: drop `_phantomEdgeExits` entries that became
  /// `_phantomExitGhosts` this cycle (an edge-ghost row was reparented
  /// under a hidden parent — the exit-phantom mechanism takes over).
  void _dropEdgeExitsForKeysThatBecameAnchorGhosts() {
    final exits = _phantomEdgeExits;
    final anchors = _phantomExitGhosts;
    if (exits == null || anchors == null) return;
    for (final key in anchors.keys) {
      exits.remove(key);
    }
    if (exits.isEmpty) _phantomEdgeExits = null;
  }

  /// Step 4: re-evaluate every active edge ghost. Three outcomes per row:
  ///
  /// - **Re-promote** (true structural now in viewport): remove from
  ///   `_phantomEdgeExits`, override `current[key]` to structural-based
  ///   form so the engine composes the slide back to a normal slide
  ///   ending at the visible position.
  /// - **Direction flip** (still off-screen but the OPPOSITE side from
  ///   the captured edge): update the `_phantomEdgeExits` entry's edge
  ///   side (preserving original duration/curve) and override
  ///   `current[key]` with the new live edge base.
  /// - **Stays-same-edge**: don't touch — the existing slide already
  ///   targets the right edge. NOT added to `ghostKeysTouchedThisCycle`
  ///   so Step 6 will remove it from the batch.
  void _reEvaluateGhostStatus({
    required Map<TKey, ({double y, double x})> baseline,
    required Map<TKey, ({double y, double x})> current,
    required _ViewportSnapshot viewport,
    required Duration duration,
    required Curve curve,
    required Set<TKey> ghostKeysTouchedThisCycle,
  }) {
    final exits = _phantomEdgeExits;
    if (exits == null) return;
    for (final key in exits.keys.toList()) {
      final trueStructuralY = _computeTrueStructuralAt(key);
      if (trueStructuralY < 0) continue; // row left visibleNodes
      final nid = controller.nidOf(key);
      if (nid < 0) continue;
      final slideY = controller.getSlideDeltaNid(nid);
      final slideX = controller.getSlideDeltaXNid(nid);
      final indent = controller.getIndent(key);
      // Re-promotion uses [_ViewportSnapshot.meaningfullyVisible] (not
      // bounding-box [intersects]) so it agrees with the clamp branch
      // decision in [_applyClampAndInstallNewGhosts]. With [intersects],
      // a row with sub-pixel overlap could re-promote here and then be
      // reclassified off-screen by the clamp's `priorOn`/`targetOn`,
      // producing an edge-only flicker as the row bounced between
      // promoted and ghost states across cycles.
      if (viewport.meaningfullyVisible(
        y: trueStructuralY,
        extent: controller.getCurrentExtentNid(nid),
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
          // Per plan §7.4: the consume-time baseline rewrite has already
          // set baseline[key] = oldBaseY + slideY (using the OLD edge).
          // Override current[key] with the NEW edge base so the engine
          // composes oldBaseY → newBaseY into a fresh slide. The new
          // currentDelta retains the old painted position (oldBaseY +
          // existing.currentDelta) at t=0 and animates toward newBaseY.
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
    if (exits.isEmpty) _phantomEdgeExits = null;
  }

  /// Step 5: clamp slide-IN starts and install new edge ghosts for
  /// slide-OUT cases. Skips keys already handled by Step 4.
  void _applyClampAndInstallNewGhosts({
    required Map<TKey, ({double y, double x})> baseline,
    required Map<TKey, ({double y, double x})> current,
    required _ViewportSnapshot viewport,
    required Duration duration,
    required Curve curve,
    required Set<TKey> ghostKeysTouchedThisCycle,
  }) {
    final viewportTop = viewport.top;
    final viewportBottom = viewport.bottom;
    final overhangPx = viewport.overhangPx;
    // Iterate keys that have BOTH a baseline and current entry.
    final keysToProcess = <TKey>[];
    for (final key in baseline.keys) {
      if (current.containsKey(key)) keysToProcess.add(key);
    }
    final exits = _phantomEdgeExits;
    for (final key in keysToProcess) {
      // Skip direction-flipped / stays-same ghosts — these are still in
      // `exits` and `_reEvaluateGhostStatus` set up their composition
      // already (baseline = ghost-painted from snapshot; current =
      // edge_y + slideY). Re-running the clamp would interfere.
      if (exits != null && exits.containsKey(key)) continue;
      // Re-promoted ghosts (`ghostKeysTouchedThisCycle`) are NOT skipped
      // here. Their snapshot baseline is `edge_y + slideY` from the
      // ghost-aware snapshot — when the slide has advanced enough that
      // `edge_y + slideY` lies past the viewport edge, the row was
      // painted off-viewport at staging time. The clamp below
      // (`!priorOn && targetOn`) brings the new slide's painted at t=0
      // back into the viewport. The historical concern about a "double-
      // clamp visible JUMP" only applies if the row was painted INSIDE
      // the viewport — captured by the `priorOn=true` short-circuit two
      // lines below, which leaves baseline untouched.
      final prior = baseline[key]!;
      final curr = current[key]!;
      final nid = controller.nidOf(key);
      final slideY = nid >= 0 ? controller.getSlideDeltaNid(nid) : 0.0;
      final slideX = nid >= 0 ? controller.getSlideDeltaXNid(nid) : 0.0;
      final hasInFlightSlide = slideY != 0.0 || slideX != 0.0;
      final rowExtent = nid >= 0 ? controller.getCurrentExtentNid(nid) : 0.0;

      // `curr` includes the existing slide delta so the engine can
      // compose from the currently painted position. Viewport admission
      // decisions need the destination paint base instead. Otherwise a
      // row retargeted into the viewport while its old slide is still
      // pulling it past an edge is misclassified as off-screen and kept
      // invisible as an edge ghost until the slide settles.
      final targetY = curr.y - slideY;
      // Use [_ViewportSnapshot.meaningfullyVisible] (an absolute-pixel
      // overlap threshold) for the clamp branch decision. Bounding-box
      // intersection routes ε-overlapping rows through the on-screen
      // branch (skipping the slide-IN baseline clamp), and a midpoint
      // heuristic routes partially-visible edge rows through the
      // off-screen branch (suppressing slides for rows the user can
      // clearly see). See [_ViewportSnapshot.meaningfullyVisible].
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
        // Both off-screen. Two sub-cases:
        //
        // (a) Row has no in-flight engine slide — invisible mutation,
        //     suppress to keep maxActiveSlideAbsDelta clean.
        // (b) Row has an in-flight slide (composition case) — must NOT
        //     suppress. The engine's existing slide is targeting an OLD
        //     destination; if we suppress, the slide settles at the
        //     wrong painted position and the row visibly SNAPS to its
        //     new structural at slide end. Pass through to engine so
        //     composition redirects toward the new destination.
        if (!hasInFlightSlide) {
          baseline.remove(key);
          current.remove(key);
        }
        // else: leave (baseline, current) as-is — engine composes the
        // existing slide toward the new (off-screen) destination. The
        // row paints at structural+slideDelta in scroll-space; if both
        // are off-screen, the row is invisible throughout the slide,
        // and at settle painted == structural (correct).
        continue;
      }
      if (!priorOn && targetOn) {
        // SLIDE-IN. Two distinct cases:
        //
        // (a) Initial install (no existing engine slide): clamp baseline
        //     to viewport edge ± overhang. Bounds the slide delta and
        //     gives the user a visible "row enters from edge" animation
        //     instead of the row appearing somewhere off-screen and
        //     never visibly transitioning into place.
        //
        // (b) Composition (existing slide active — typically because a
        //     PRIOR mutation installed a slide on this row that's still
        //     in flight, AND the current mutation re-targets it to an
        //     in-viewport destination): clamp baseline to JUST INSIDE the
        //     viewport edge so painted at t=0 of the new slide is
        //     visible. Without this bound, `baseline.y` from the
        //     ghost-aware snapshot can sit past the viewport edge — for
        //     example baseline=429 past a viewport bottom of 390 — and
        //     engine composition then sets the new currentDelta such
        //     that painted at t=0 = baseline.y (off-viewport). Under
        //     cascaded `Reparent ALL` taps each composition repeats the
        //     pattern; the row stays invisible for an accumulating
        //     fraction of each slide. The user observed this as "ghost
        //     rows disappearing during rapid reparent".
        //
        //     Note: composition CANNOT use the same `edge_y ± overhang`
        //     clamp as initial install. `edge_y` sits PAST the viewport
        //     by `overhangPx`; for `prior.y` in the overhang region
        //     (between viewport edge and edge_y, common because the
        //     prior install clamped to edge_y and the row hasn't ticked
        //     far yet), clamping to edge_y would push painted FURTHER
        //     off-viewport — the opposite of what we want. The "tiny-
        //     delta needs enlargement" rationale that justifies the
        //     overhang in initial installs doesn't apply to composition:
        //     `composedY = currentDelta + rawDeltaY` already inherits
        //     the in-flight slide's energy, so the new slide is
        //     guaranteed to have perceptible motion.
        if (!hasInFlightSlide) {
          final edgeY = prior.y < viewportTop
              ? viewportTop - overhangPx
              : viewportBottom + overhangPx;
          baseline[key] = (y: edgeY, x: prior.x);
        } else {
          // `epsilon` keeps painted strictly INSIDE the viewport so
          // `_paintRow`'s past-bottom early-return (`>= viewportBottom`)
          // doesn't skip the t=0 paint. For above-top entries, we add
          // epsilon (>= viewportTop is in viewport).
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
      // Corner: row was visible exactly at the edge already → no
      // animation needed; structural ≈ edge.
      if (baseline[key]!.y == edgeY) continue;
      final indent = controller.getIndent(key);
      current[key] = (y: edgeY + slideY, x: indent + slideX);
      (_phantomEdgeExits ??= {})[key] = (
        edge: edge,
        duration: duration,
        curve: curve,
      );
      ghostKeysTouchedThisCycle.add(key);
    }
  }

  /// Step 6: remove ghost-stays-same-edge_y entries from the engine
  /// batch so the engine doesn't re-baseline them. The existing engine
  /// slide already targets the correct edge — leaving it un-touched lets
  /// it continue uninterrupted (combined with the preserve-progress
  /// flag set in Step 8).
  void _removeGhostStaysFromBatch(
    Map<TKey, ({double y, double x})> baseline,
    Map<TKey, ({double y, double x})> current,
    Set<TKey> ghostKeysTouchedThisCycle,
  ) {
    final exits = _phantomEdgeExits;
    if (exits == null) return;
    for (final key in exits.keys) {
      if (ghostKeysTouchedThisCycle.contains(key)) continue;
      baseline.remove(key);
      current.remove(key);
    }
  }

  /// Normalizes [_phantomEdgeExits] for the supplied [viewport]. Replaces
  /// the older `_checkGhostRepromotionOnScroll` and folds in direction-
  /// flip and stays-same handling so a single helper covers every
  /// scroll-induced edge-ghost adjustment.
  ///
  /// For each active edge ghost:
  ///   1. If its true structural Y now intersects [viewport], remove
  ///      the ghost from the map. When [installStandaloneSlides] is
  ///      true the helper also installs a re-promotion slide from the
  ///      live edge base to structural Y; when false, the helper just
  ///      normalizes bookkeeping and leaves slide installation to the
  ///      caller (the consume path that owns the single batch).
  ///   2. Else, recompute the side via [viewport.edgeFor]. If the side
  ///      changed (direction flip), update the stored side. When
  ///      [installStandaloneSlides] is true, install a fresh slide
  ///      from old-edge live base to new-edge live base so the row
  ///      visibly sweeps across the viewport edge.
  ///   3. Else (stays-same edge), do nothing — the ghost is already
  ///      anchored to the right side, and live-base lookup means the
  ///      paint pass automatically tracks the new viewport.
  ///
  /// Per plan §5.3: when a pending mutation baseline exists, this
  /// helper runs with `installStandaloneSlides: false` so the upcoming
  /// consume owns the single animation batch for the layout. When no
  /// pending baseline exists, this helper installs slides itself.
  ///
  /// Re-promotions / direction-flips are grouped by (duration, curve)
  /// so each `animateSlideFromOffsets` call uses the matching original
  /// install parameters. Composition with the existing engine slide
  /// preserves visual continuity.
  void _normalizeEdgeGhostsForViewport({
    required _ViewportSnapshot viewport,
    required bool installStandaloneSlides,
  }) {
    final exits = _phantomEdgeExits;
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
      final nid = controller.nidOf(key);
      if (nid < 0) continue;
      final entry = exits[key]!;
      final slideY = controller.getSlideDeltaNid(nid);
      final slideX = controller.getSlideDeltaXNid(nid);
      final indent = controller.getIndent(key);
      // See [_reEvaluateGhostStatus] for why this uses
      // [_ViewportSnapshot.meaningfullyVisible] instead of [intersects]:
      // promotion threshold must match the clamp's branch decision
      // threshold or the row can flicker between the two states.
      final structVisible = viewport.meaningfullyVisible(
        y: trueStructuralY,
        extent: controller.getCurrentExtentNid(nid),
      );
      if (structVisible) {
        // Re-promote: structural is back in viewport. Drop the ghost.
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
            y: _edgeGhostBaseY(entry, viewport) + slideY,
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
      // Still off-screen. Did the side change?
      final newEdge = viewport.edgeFor(trueStructuralY);
      if (newEdge != entry.edge) {
        // Direction flip. Update the stored side; when standalone,
        // install a slide that composes oldBaseY → newBaseY so the
        // row visibly transits between edges.
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
          group.baseline[key] = (y: oldBaseY + slideY, x: indent + slideX);
          group.current[key] = (y: newBaseY + slideY, x: indent + slideX);
        }
        exits[key] = (
          edge: newEdge,
          duration: entry.duration,
          curve: entry.curve,
        );
        continue;
      }
      // Stays-same edge. Nothing to update — paint, hit-test, snapshot
      // all read live base from the entry's stored side, so they pick
      // up the new viewport automatically.
    }
    if (exits.isEmpty) _phantomEdgeExits = null;

    if (!installStandaloneSlides) return;
    for (final entry in groups.entries) {
      controller.animateSlideFromOffsets(
        entry.value.baseline,
        entry.value.current,
        duration: entry.key.$1,
        curve: entry.key.$2,
      );
      // Mark the re-promoted / direction-flipped slides with the
      // preserve-progress flag. Without this, the next consume cycle
      // whose batch doesn't touch these keys will hit the engine's
      // re-baseline branch (`_slide_animation_engine.dart` ~290-294):
      // `startDelta = currentDelta`, `progress = 0`,
      // `slideStartElapsed = now`. The slide's clock restarts, and
      // the effective remaining motion (already-shrunk `currentDelta`)
      // is dragged out over another full `slideDuration`. Under
      // cascaded mutations the re-baseline fires every batch — the
      // slide makes essentially zero net per-tick progress.
      //
      // Composition (called inside `animateSlideFromOffsets` above)
      // resets `preserveProgressOnRebatch = false`, and the re-
      // promoted keys are no longer in `_phantomEdgeExits` (removed at
      // `exits.remove(key)` above), so `_syncPreserveProgressFlags`
      // doesn't catch them. We re-set the flag explicitly here.
      for (final key in entry.value.current.keys) {
        controller.markSlidePreserveProgress(key);
      }
    }
  }

  /// Step 8: ensure preserve-progress flag set for all active edge
  /// ghosts AND existing exit-phantom anchor ghosts. Set-only-true —
  /// the engine clears the flag implicitly when the slide entry is
  /// destroyed (settles, cancelled, replaced via composition).
  void _syncPreserveProgressFlags() {
    final exits = _phantomEdgeExits;
    if (exits != null) {
      for (final key in exits.keys) {
        controller.markSlidePreserveProgress(key);
      }
    }
    final anchors = _phantomExitGhosts;
    if (anchors != null) {
      for (final key in anchors.keys) {
        controller.markSlidePreserveProgress(key);
      }
    }
  }

  /// Reallocates sticky-precompute scratch arrays to fit the last
  /// precomputed count (or empty if zero). Call when the tree shrinks
  /// significantly and memory matters.
  void trimScratchArrays() => _sticky.trimScratchArrays();

  /// Pre-allocates sticky-precompute scratch arrays for [capacity] nodes.
  /// Useful when the tree size is known upfront to avoid incremental
  /// resizing.
  void resizeScratchArrays(int capacity) =>
      _sticky.resizeScratchArrays(capacity);

  /// Whether the given node is retained by the current layout — i.e. it is
  /// in the cache region, a sticky header, or a phantom-exit ghost
  /// mid-slide. Used by the element to decide whether an off-screen child
  /// can be evicted. O(1) (Map containsKey + Set lookup), no allocation.
  bool isNodeRetained(TKey id) {
    // Phantom-exit ghosts: retain past visible-order purge so their
    // slide can finish. Removed from _phantomExitGhosts when their
    // slide settles, after which the next stale eviction will release
    // the render box normally.
    final ghosts = _phantomExitGhosts;
    if (ghosts != null && ghosts.containsKey(id)) return true;
    // Edge-anchor exit ghosts: retain so the parallel ghost paint pass
    // can render them. The row IS in visibleNodes (its structural is
    // still in the tree) but may sit outside the cache region; without
    // explicit retention here, layout admission would evict the child
    // and the ghost paint pass would have nothing to paint.
    final edgeGhosts = _phantomEdgeExits;
    if (edgeGhosts != null && edgeGhosts.containsKey(id)) return true;
    final nid = _controller.nidOf(id);
    if (nid < 0) return false;
    if (nid < _inCacheRegionByNid.length && _inCacheRegionByNid[nid] != 0) {
      return true;
    }
    // Mid-flight FLIP slide: the engine has a live slide entry for this
    // nid (currentDelta != 0 in either axis is the externally-observable
    // proxy — the engine clears entries whose composedY/X both reach 0
    // and the lerp only crosses zero at completion). Retain so paint can
    // continue to render the row at `structural + slideDelta` even when
    // the post-mutation structural Y has moved outside the cache region
    // (e.g. a re-moveTo mid-slide pushed the row far off-screen). Without
    // this, stale-eviction (gated only by `hasActiveAnimations`, which
    // excludes slides — see [TreeController.hasActiveAnimations] doc)
    // would drop the render box mid-slide, leaving the engine ticking a
    // slide for a child that no longer exists, so the row appears stuck
    // / vanishes during its visible transit through the viewport. Once
    // the slide settles (delta=0), this branch falls through and the
    // next eviction releases the box normally.
    if (_controller.getSlideDeltaNid(nid) != 0.0 ||
        _controller.getSlideDeltaXNid(nid) != 0.0) {
      return true;
    }
    return _sticky.isSticky(nid);
  }

  /// Gets the child for the given node ID, or null if not present.
  RenderBox? getChildForNode(TKey id) => _children[id];

  /// A per-node snapshot of the painted position (in scroll-space) for every
  /// visible node. Painted y = structural y + that node's own slide delta.
  ///
  /// Used as the "before" baseline for FLIP slide animation. Calling this
  /// again post-mutation produces the "after" baseline; the per-node
  /// difference is the new slide's startDelta.
  ///
  /// Coordinate space: scroll-space, matching [SliverTreeParentData.layoutOffset].
  ///
  /// Slide deltas are paint-only: a node's delta shifts only that node's
  /// painted position and never contributes to the structural accumulator
  /// used for subsequent rows.
  ///
  /// O(N_visible). Walks [TreeController.visibleNodes] independently of
  /// [_nodeOffsetsByNid], so the result is correct even under the bulk-only
  /// fast path (where the nid-indexed array is not fresh for every node).
  Map<TKey, ({double y, double x})> snapshotVisibleOffsets() {
    assert(
      geometry != null,
      "snapshotVisibleOffsets called before first layout",
    );
    // Hoist per-axis activity checks. The common case is no slides at
    // all (idle) or Y-only slides (same-depth reorders). Skip the
    // per-row delta reads in those cases.
    final hasSlides = controller.hasActiveSlides;
    final hasXSlides = hasSlides && controller.hasActiveXSlides;
    final result = <TKey, ({double y, double x})>{};
    double structural = 0.0;
    final visible = controller.visibleNodes;
    final orderNids = controller.orderNidsView;
    final edgeExits = _phantomEdgeExits;
    // Build the viewport snapshot lazily — only needed if there are
    // active edge ghosts. Plan §7.2: ghost rows paint at the LIVE
    // viewport edge, so snapshot must derive their painted Y from the
    // current viewport, not a frozen capture.
    final _ViewportSnapshot? viewportForGhosts =
        edgeExits != null ? _currentViewportSnapshot() : null;
    for (int i = 0; i < visible.length; i++) {
      final nid = orderNids[i];
      final key = visible[i];
      final slideY = hasSlides ? controller.getSlideDeltaNid(nid) : 0.0;
      final slideX = hasXSlides ? controller.getSlideDeltaXNid(nid) : 0.0;
      final indent = controller.getIndent(key);
      // Edge-ghost rows paint at `_edgeGhostBaseY + slideDelta`, not at
      // `structural + slideDelta`. Override to keep snapshot consistent
      // with what the edge-ghost paint pass actually paints — required
      // for composition correctness when a ghost row gets re-mutated
      // mid-slide.
      if (edgeExits != null) {
        final entry = edgeExits[key];
        if (entry != null) {
          result[key] = (
            y: _edgeGhostBaseY(entry, viewportForGhosts!) + slideY,
            x: indent + slideX,
          );
          structural += controller.getCurrentExtentNid(nid);
          continue;
        }
      }
      result[key] = (y: structural + slideY, x: indent + slideX);
      structural += controller.getCurrentExtentNid(nid);
    }
    // Augment with exit-ghost rows (visible→hidden reparents whose slide
    // is still in flight). Ghosts aren't in visibleNodes — they're
    // rendered in a separate pass anchored to a visible parent — but if
    // a ghost gets re-moved before its slide settles, the next staging
    // call MUST capture its current painted position. Otherwise the
    // baseline misses the ghost entirely and the new slide installs
    // from a wrong starting point, producing a visible snap.
    //
    // Painted position of a ghost = anchor's painted position + ghost's
    // own slideDelta. anchor's painted position is already in `result`
    // (anchor is in visibleNodes by definition of the exit-phantom path).
    final ghosts = _phantomExitGhosts;
    if (ghosts != null) {
      // Reuse the same hoist as the visible loop. Settled-but-unpruned
      // ghosts have slide=0 either way, so skipping the read is safe.
      for (final entry in ghosts.entries) {
        final ghostKey = entry.key;
        // Skip if the key is already in the visible loop's result —
        // a ghost from a prior cycle whose key has been re-promoted to
        // visible is being handled via the standard path now. The
        // consume's lazy-prune will drop the stale ghost entry; until
        // then, prefer the structural entry over the ghost-derived one.
        if (result.containsKey(ghostKey)) continue;
        final anchorKey = entry.value;
        final anchorPos = result[anchorKey];
        if (anchorPos == null) continue; // anchor itself disappeared
        final ghostNid = controller.nidOf(ghostKey);
        if (ghostNid < 0) continue;
        final ghostSlideY =
            hasSlides ? controller.getSlideDeltaNid(ghostNid) : 0.0;
        final ghostSlideX =
            hasXSlides ? controller.getSlideDeltaXNid(ghostNid) : 0.0;
        result[ghostKey] = (
          y: anchorPos.y + ghostSlideY,
          x: anchorPos.x + ghostSlideX,
        );
      }
    }
    return result;
  }

  /// Finds the first live (non-pending-deletion) visible row whose painted
  /// scroll-space range `[paintedOffset, paintedOffset + extent)` contains
  /// [scrollY], falling back to the last live row when [scrollY] sits past
  /// the bottom of the tree. Returns null when the visible order is empty or
  /// every entry is pending-deletion.
  ///
  /// Painted offsets include the node's current FLIP slide delta, matching
  /// what [snapshotVisibleOffsets] would return — but without allocating an
  /// O(N) map. Designed for [TreeReorderController], which polls the hovered
  /// row every pointer move and every autoscroll tick; the previous
  /// implementation materialized a `Map<TKey, double>` for the whole tree on
  /// each call.
  ///
  /// Fast path (no active slides): O(log N) via binary search on
  /// structural offsets, plus a forward scan to skip pending-deletion rows.
  ///
  /// Slow path (active slides): O(N) linear scan — slide deltas can reorder
  /// painted positions relative to structural positions, so binary search
  /// over structural offsets is unsafe. A slide only overlaps a drag when
  /// the user starts a new drag while a prior commit's FLIP is still
  /// animating (≤ slideDuration).
  ({TKey key, double paintedOffset, double extent})? findRowAtPaintedY(
    double scrollY,
  ) {
    final visible = controller.visibleNodes;
    if (visible.isEmpty) return null;

    if (controller.hasActiveSlides) {
      TKey? lastLiveKey;
      double lastLiveOffset = 0.0;
      double lastLiveExtent = 0.0;
      double structural = 0.0;
      final orderNids = controller.orderNidsView;
      final edgeExits = _phantomEdgeExits;
      // Lazy: only build viewport snapshot if there are ghosts to
      // resolve. Edge ghosts paint at the LIVE viewport edge.
      final _ViewportSnapshot? viewportForGhosts =
          edgeExits != null ? _currentViewportSnapshot() : null;
      for (int i = 0; i < visible.length; i++) {
        final nid = orderNids[i];
        final key = visible[i];
        final extent = controller.getCurrentExtentNid(nid);
        final slide = controller.getSlideDeltaNid(nid);
        // Edge-ghost rows paint at `_edgeGhostBaseY + slide`, not at
        // `structural + slide`. Substitute so drag-target lookup lands
        // on the correct ghost row.
        final edgeEntry = edgeExits?[key];
        final paintedOffset = edgeEntry != null
            ? _edgeGhostBaseY(edgeEntry, viewportForGhosts!) + slide
            : structural + slide;
        if (!controller.isPendingDeletion(key)) {
          if (scrollY < paintedOffset + extent) {
            return (key: key, paintedOffset: paintedOffset, extent: extent);
          }
          lastLiveKey = key;
          lastLiveOffset = paintedOffset;
          lastLiveExtent = extent;
        }
        structural += extent;
      }
      if (lastLiveKey == null) return null;
      return (
        key: lastLiveKey,
        paintedOffset: lastLiveOffset,
        extent: lastLiveExtent,
      );
    }

    // Fast path: no slides active, painted offset == structural offset.
    final startIdx = _findFirstVisibleIndex(scrollY);
    for (int i = startIdx; i < visible.length; i++) {
      final key = visible[i];
      if (controller.isPendingDeletion(key)) continue;
      return _liveRowAt(i, key);
    }
    // Past the end (or every trailing row is pending-deletion) — walk back
    // for the last live row.
    for (int i = visible.length - 1; i >= 0; i--) {
      final key = visible[i];
      if (controller.isPendingDeletion(key)) continue;
      return _liveRowAt(i, key);
    }
    return null;
  }

  ({TKey key, double paintedOffset, double extent}) _liveRowAt(
    int visibleIndex,
    TKey key,
  ) {
    final double offset;
    final double extent;
    if (_bulkCumulativesValid) {
      // Per-nid slots aren't kept fresh for out-of-cache-region nids under
      // the bulk fast path; derive from cumulatives.
      offset = _offsetAtVisibleIndex(visibleIndex);
      extent = _offsetAtVisibleIndex(visibleIndex + 1) - offset;
    } else {
      final nid = _controller.nidOf(key);
      offset = _nodeOffsetsByNid[nid];
      extent = _nodeExtentsByNid[nid];
    }
    return (key: key, paintedOffset: offset, extent: extent);
  }

  /// Inserts a child for the specified node.
  void insertChild(RenderBox child, TKey nodeId) {
    // Defensive drop of any prior box at this slot. Normal lifecycle pairs
    // removeRenderObjectChild before insertRenderObjectChild, but a path
    // that skips remove (forgetChild + reparent, an exception between
    // remove/insert) would leave the old box adopted — causing adoptChild
    // to assert "child already has a parent" or the old box to become a
    // zombie still walked by attach/detach.
    final existing = _children[nodeId];
    if (existing != null && !identical(existing, child)) {
      dropChild(existing);
    }
    _children[nodeId] = child;
    adoptChild(child);
    (child.parentData! as SliverTreeParentData).nodeId = nodeId;
  }

  /// Removes the child for the specified node.
  void removeChild(RenderBox child, TKey nodeId) {
    if (identical(_children[nodeId], child)) {
      _children.remove(nodeId);
    }
    dropChild(child);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RENDER OBJECT LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void setupParentData(covariant RenderObject child) {
    if (child.parentData is! SliverTreeParentData) {
      child.parentData = SliverTreeParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (final child in _children.values) {
      child.attach(owner);
    }
    _controller.registerRenderHost(_hostCallback);
  }

  @override
  void detach() {
    _controller.unregisterRenderHost(_hostCallback);
    // A pending FLIP baseline that was never consumed (widget unmounted
    // between mutation and next frame) would leak the offset map and
    // trip stale-state assertions on re-attach. Drop it eagerly.
    _pendingSlideBaseline = null;
    _pendingSlideDuration = null;
    _pendingSlideCurve = null;
    super.detach();
    for (final child in _children.values) {
      child.detach();
    }
  }

  /// Filters out children whose nodes have been removed from the controller
  /// (or are mid-exit) so screen readers don't announce/focus them while
  /// the render boxes wait for their post-frame eviction.
  ///
  /// Walks in visual order (sticky headers first, then in-flow visible
  /// nodes top-to-bottom) so screen readers announce rows in the same
  /// order the user sees them rather than raw insertion order.
  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    // Sticky headers paint on top, shallowest first (visual top).
    for (final sticky in _sticky.headers) {
      final child = getChildForNode(sticky.nodeId);
      if (child == null) continue;
      if (controller.getNodeData(sticky.nodeId) == null) continue;
      if (controller.isExiting(sticky.nodeId)) continue;
      visitor(child);
    }
    // Then in-flow visible nodes, skipping any already emitted as sticky.
    for (final nodeId in controller.visibleNodes) {
      final nid = _controller.nidOf(nodeId);
      if (_sticky.isSticky(nid)) continue;
      final child = getChildForNode(nodeId);
      if (child == null) continue;
      if (controller.getNodeData(nodeId) == null) continue;
      if (controller.isExiting(nodeId)) continue;
      visitor(child);
    }
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    for (final child in _children.values) {
      visitor(child);
    }
  }

  @override
  void redepthChildren() {
    for (final child in _children.values) {
      redepthChild(child);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STICKY HEADER COMPUTATION
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Owned by [_sticky] (see [StickyHeaderComputer]). The render object
  // hands off scroll inputs and per-nid offset/extent arrays each layout;
  // paint, hit-test, and transform read [_sticky.headers] /
  // [_sticky.infoForNid] for the per-frame results.

  /// Recomputes [_nodeOffsetsByNid] from current [_nodeExtentsByNid] and
  /// returns the new total scroll extent. Call after Pass 2 when extents
  /// have been updated with actual measured values.
  double _recomputeOffsets() {
    double offset = 0.0;
    final orderNids = _controller.orderNidsView;
    final n = _controller.visibleNodeCount;
    for (int i = 0; i < n; i++) {
      final nid = orderNids[i];
      _nodeOffsetsByNid[nid] = offset;
      offset += _nodeExtentsByNid[nid];
    }
    return offset;
  }

  /// Incremental variant of [_recomputeOffsets] that only walks from
  /// [fromIndex] forward. Offsets for earlier indices are assumed
  /// already correct — extents only affect the offsets of nodes that
  /// come AFTER them, so changes at index `k` leave indices `< k`
  /// untouched. Returns the new total scroll extent.
  double _recomputeOffsetsFrom(int fromIndex) {
    final n = _controller.visibleNodeCount;
    if (n == 0) return 0.0;
    if (fromIndex <= 0) return _recomputeOffsets();

    final orderNids = _controller.orderNidsView;
    double offset = _nodeOffsetsByNid[orderNids[fromIndex]];
    for (int i = fromIndex; i < n; i++) {
      final nid = orderNids[i];
      _nodeOffsetsByNid[nid] = offset;
      offset += _nodeExtentsByNid[nid];
    }
    return offset;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NODE LAYOUT
  // ══════════════════════════════════════════════════════════════════════════

  /// Lays out a single node's child and updates extent bookkeeping.
  ///
  /// Returns the actual animated extent, or null if the child doesn't exist.
  /// Uses a consistent width-tight, height-flexible constraint shape so
  /// rows can change height at the same width. Flutter's built-in
  /// `RenderBox.layout` short-circuit handles the unchanged case efficiently.
  double? _layoutNodeChild(TKey nodeId, double crossAxisExtent) {
    final child = getChildForNode(nodeId);
    if (child == null) return null;

    final indent = controller.getIndent(nodeId);
    final w = math.max(0.0, crossAxisExtent - indent);
    final childConstraints = BoxConstraints(
      minWidth: w,
      maxWidth: w,
      minHeight: 0.0,
      maxHeight: double.infinity,
    );

    // Always call layout — the child's own early-exit handles the case
    // where neither constraints nor needs-layout changed. This ensures
    // internally-dirty children (from setState) still get processed.
    child.layout(childConstraints, parentUsesSize: true);
    controller.setFullExtent(nodeId, child.size.height);

    final actualAnimatedExtent = controller.getAnimatedExtent(
      nodeId,
      child.size.height,
    );

    final parentData = child.parentData! as SliverTreeParentData;
    parentData.nodeId = nodeId;
    parentData.indent = indent;
    parentData.visibleExtent = actualAnimatedExtent;

    return actualAnimatedExtent;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LAYOUT
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void performLayout() {
    debugLastParentDataRefreshIterationCount = 0;
    final constraints = this.constraints;
    // This sliver's layout and paint code assume a vertical-forward axis.
    // Child constraints, offset math, sticky pinning and hit-testing all use
    // plain (x = indent, y = layoutOffset) coordinates with no axis mapping.
    // Running in any other axis/growth/reverse configuration silently renders
    // incorrectly, so fail loudly in debug builds.
    assert(
      constraints.axis == Axis.vertical &&
          constraints.axisDirection == AxisDirection.down &&
          constraints.growthDirection == GrowthDirection.forward,
      "SliverTree currently supports only vertical, forward-growing axes "
      "(Axis.vertical, AxisDirection.down, GrowthDirection.forward). Got "
      "axis=${constraints.axis}, axisDirection=${constraints.axisDirection}, "
      "growthDirection=${constraints.growthDirection}.",
    );
    childManager?.didStartLayout();

    final visibleNodes = controller.visibleNodes;
    if (visibleNodes.isEmpty) {
      _structureChanged = true;
      _lastVisibleNodeCount = 0;
      geometry = SliverGeometry.zero;
      childManager?.didFinishLayout();
      return;
    }

    _ensureLayoutCapacity();

    // Detect structure changes
    if (controller.structureGeneration != _lastStructureGeneration) {
      _structureChanged = true;
      _sticky.dirty = true;
      _lastStructureGeneration = controller.structureGeneration;
    }
    if (visibleNodes.length != _lastVisibleNodeCount) {
      _structureChanged = true;
      _sticky.dirty = true;
    }

    final scrollOffset = constraints.scrollOffset;
    final remainingPaintExtent = constraints.remainingPaintExtent;
    final remainingCacheExtent = constraints.remainingCacheExtent;
    final crossAxisExtent = constraints.crossAxisExtent;

    // Cache region bounds — per sliver protocol, remainingCacheExtent starts
    // at scrollOffset + cacheOrigin (cacheOrigin is typically ≤ 0).
    final cacheOrigin = constraints.cacheOrigin;
    final cacheStart = scrollOffset + cacheOrigin;
    final cacheEnd = cacheStart + remainingCacheExtent;

    // Slide-pipeline ordering (per plan §5):
    //
    //   1. Build the current viewport snapshot.
    //   2. If scroll changed since last layout and edge ghosts exist,
    //      normalize the ghost map for the current viewport — handle
    //      re-promotions, direction flips, and stays-same. When a
    //      pending mutation baseline exists, normalization runs WITHOUT
    //      installing standalone slides so the upcoming consume owns
    //      the single animation batch for this layout (avoids two
    //      independent `animateSlideFromOffsets` calls in the same
    //      frame). When no pending baseline exists, normalization
    //      installs slides directly.
    //   3. Consume the pending mutation baseline. After step 2 the
    //      ghost map already reflects the current viewport, so consume
    //      composes against fresh state instead of the stale frozen
    //      `edgeY` the previous implementation carried.
    //   4. Update `_lastObservedScrollOffset` to the new scroll.
    //
    // `snapshotVisibleOffsets()` walks `visibleNodes` with
    // `getCurrentExtent`, which is independent of Pass 1's per-nid
    // offset array, so all three steps are safe before Pass 1.
    final currentViewport = _currentViewportSnapshot();
    final currentScroll = currentViewport.scrollOffset;
    final scrollChanged = !_lastObservedScrollOffset.isNaN
        && currentScroll != _lastObservedScrollOffset;
    final hasEdgeGhosts =
        _phantomEdgeExits != null && _phantomEdgeExits!.isNotEmpty;
    if (scrollChanged && hasEdgeGhosts) {
      _normalizeEdgeGhostsForViewport(
        viewport: currentViewport,
        installStandaloneSlides: _pendingSlideBaseline == null,
      );
    }
    _consumeSlideBaselineIfAny(currentViewport: currentViewport);
    _lastObservedScrollOffset = currentScroll;

    // FLIP-slide overreach (Option A): during a slide, a row's painted y
    // can differ from its structural y by up to `slideOverreach` px in
    // either direction. Widen the effective cache region by that amount
    // so rows whose painted y lies in the viewport — but whose structural
    // y is outside the normal cache region — still get built. Without
    // this, a swap of two large subtrees leaves a visible gap at the slot
    // where a sliding row should appear (no child created for it), and
    // the gap does NOT resolve on scroll because the build decision still
    // only considers structural offsets. Overreach shrinks to 0 as the
    // slide progresses (see [TreeController.maxActiveSlideAbsDelta]), so
    // the transient overbuild contracts with the animation.
    //
    // Future optimization (Option B): replace this blanket clamp with a
    // per-entry precise union. For each active slide, compute the
    // structural index range whose painted y (structural + currentDelta)
    // intersects the cache region, then union those ranges with the
    // normal cache-region index range. This eliminates the transient
    // overbuild for the common case of a few small slides, at the cost
    // of a per-entry scan every frame. Worth doing only when the
    // overbuild measurably hurts — large-subtree swaps are rare and
    // short-lived, so the blanket clamp is usually fine.
    final slideOverreach = controller.maxActiveSlideAbsDelta;
    final effectiveCacheStart = cacheStart - slideOverreach;
    final effectiveCacheEnd = cacheEnd + slideOverreach;

    // ────────────────────────────────────────────────────────────────────────
    // PASS 1: Calculate offsets and extents
    // ────────────────────────────────────────────────────────────────────────
    double totalScrollExtent;
    final bool hasAnimations = controller.hasActiveAnimations;
    // Fetch the bulk-animation snapshot once so downstream branches share a
    // single read of value/generation/membership. Per-key membership
    // queries inside _rebuildBulkCumulatives go through this snapshot too.
    final BulkAnimationData<TKey> bulkData = controller.bulkAnimationData();
    final bool bulkOnly = bulkData.isValid && !controller.hasOpGroupAnimations;

    if (bulkOnly) {
      // Fast path: bulk animation only. Every node's offset is a scalar
      // function of position via the precomputed cumulatives. Avoid touching
      // _nodeOffsetsByNid for nodes outside the cache region — that write
      // is what the per-frame O(N) cost was buying.
      final bulkGen = bulkData.generation;
      final n = visibleNodes.length;
      if (!_bulkCumulativesValid ||
          _bulkCumulativesCount != n ||
          bulkGen != _lastBulkAnimationGeneration ||
          _structureChanged) {
        _rebuildBulkCumulatives(visibleNodes, bulkData);
        _lastBulkAnimationGeneration = bulkGen;
        _structureChanged = false;
      }
      _bulkValueCached = bulkData.value;
      totalScrollExtent = _offsetAtVisibleIndex(n);
      _lastFrameUsedBulkCumulatives = true;
    } else if (_structureChanged || _lastFrameUsedBulkCumulatives) {
      // Either the visible order changed OR we just exited the bulk-only
      // fast path — in both cases the per-nid offset/extent arrays are
      // not guaranteed fresh for every visible node, so do a full walk.
      _bulkCumulativesValid = false;
      _lastFrameUsedBulkCumulatives = false;
      totalScrollExtent = 0.0;

      final orderNids = controller.orderNidsView;
      final n = visibleNodes.length;
      for (int i = 0; i < n; i++) {
        final nid = orderNids[i];
        _nodeOffsetsByNid[nid] = totalScrollExtent;
        final extent = controller.getCurrentExtentNid(nid);
        _nodeExtentsByNid[nid] = extent;
        totalScrollExtent += extent;
      }

      _structureChanged = false;
    } else if (!hasAnimations && !_animationsWereActive) {
      // Pure scrolling: no animations active now or last frame.
      // Offsets and extents are unchanged — reuse cached total.
      totalScrollExtent = _lastTotalScrollExtent;
    } else if (hasAnimations) {
      // Active animation frame: only indices at or beyond the first
      // animating node can have changed offsets/extents. Everything
      // before them has stable cached values from the prior frame.
      final firstAnimIdx = controller.computeFirstAnimatingVisibleIndex();
      if (firstAnimIdx >= visibleNodes.length) {
        // Animating nodes exist but none are in the visible order
        // (e.g. an animation on a subtree that was moved out of view).
        // Nothing to recompute here.
        totalScrollExtent = _lastTotalScrollExtent;
      } else {
        final orderNids = controller.orderNidsView;
        if (firstAnimIdx == 0) {
          totalScrollExtent = 0.0;
        } else {
          final prevNid = orderNids[firstAnimIdx - 1];
          totalScrollExtent =
              _nodeOffsetsByNid[prevNid] + _nodeExtentsByNid[prevNid];
        }
        for (int i = firstAnimIdx; i < visibleNodes.length; i++) {
          final nid = orderNids[i];
          final newExtent = controller.getCurrentExtentNid(nid);
          _nodeOffsetsByNid[nid] = totalScrollExtent;
          _nodeExtentsByNid[nid] = newExtent;
          totalScrollExtent += newExtent;
        }
      }
    } else {
      // Transitional frame: no active animations this frame, but there
      // were last frame. Some just-settled nodes may have their cached
      // extent stuck at an intermediate interpolated value if the
      // settling frame fired before our last layout. Walk the list with
      // the extent-equality short-circuit so stable-prefix nodes stay
      // cheap and only changed nodes get rewritten.
      totalScrollExtent = 0.0;
      bool foundAnimating = false;

      final orderNids = controller.orderNidsView;
      for (int i = 0; i < visibleNodes.length; i++) {
        final nid = orderNids[i];
        final newExtent = controller.getCurrentExtentNid(nid);
        final oldExtent = _nodeExtentsByNid[nid];

        if (!foundAnimating && oldExtent == newExtent) {
          // Structure is stable in this branch, so the prior-layout slot
          // value is valid; no null-vs-zero ambiguity to guard against.
          totalScrollExtent = _nodeOffsetsByNid[nid] + newExtent;
        } else {
          foundAnimating = true;
          _nodeOffsetsByNid[nid] = totalScrollExtent;
          _nodeExtentsByNid[nid] = newExtent;
          totalScrollExtent += newExtent;
        }
      }
    }

    // ────────────────────────────────────────────────────────────────────────
    // PASS 2: Create children for nodes in cache region
    // ────────────────────────────────────────────────────────────────────────

    // Clear prior-layout cache-region flags in one memset-style pass, then
    // mark the slice [cacheStartIndex, cacheEndIndex) as this frame's members.
    // Sparse clear of last frame's writes. Iterate the nids we wrote
    // last frame instead of memset'ing the whole nid-indexed array — the
    // array's length tracks nidCapacity, which grows monotonically and
    // dwarfs the actual cache-region size on a long-lived tree.
    for (int i = 0; i < _writtenCacheRegionNidsLen; i++) {
      final nid = _writtenCacheRegionNids[i];
      if (nid < _inCacheRegionByNid.length) {
        _inCacheRegionByNid[nid] = 0;
      }
    }
    _writtenCacheRegionNidsLen = 0;
    final cacheStartIndex = _findFirstVisibleIndex(effectiveCacheStart);

    // In bulk-only mode, break on the row's *steady-state* (full-space)
    // position rather than its animated position. At low bulkValue, animated
    // rows have sub-pixel extents — using animated offsets would admit
    // thousands of invisible rows into the cache region on frame 1 of
    // expandAll, causing a mass-mount hitch. Anchoring the band to full-space
    // caps admission at the count we'd mount at bulkValue=1.
    final double fullCacheEnd;
    if (_bulkCumulativesValid && cacheStartIndex < visibleNodes.length) {
      final fullStart =
          _stableCumulative[cacheStartIndex] +
          _bulkFullCumulative[cacheStartIndex];
      fullCacheEnd =
          fullStart + remainingCacheExtent + slideOverreach * 2.0;
    } else {
      fullCacheEnd = 0.0;
    }

    // Dispatch the per-iteration `if (_bulkCumulativesValid)` branch out of
    // the loop body — it's invariant across one loop run, so a single
    // up-front decision replaces N per-iteration branches.
    //
    // Bulk fast path: scalar offset = _stableCumulative[i] + value *
    // _bulkFullCumulative[i]. Inline because the loop writes per-nid
    // arrays the render object owns and reads cumulative arrays the
    // render object owns.
    //
    // Op-group path: dual-view (live/post) admission cap that pre-mounts
    // post-animation visible rows during a collapse and caps mass-mounting
    // during an expand. Lives in [LayoutAdmissionPolicy.admit].
    final int cacheEndIndex;
    if (_bulkCumulativesValid) {
      cacheEndIndex = _admitBulkFastPath(
        cacheStartIndex: cacheStartIndex,
        visibleNodes: visibleNodes,
        fullCacheEnd: fullCacheEnd,
      );
    } else {
      cacheEndIndex = _admission.admit(
        cacheStartIndex: cacheStartIndex,
        visibleNodes: visibleNodes,
        nodeOffsetsByNid: _nodeOffsetsByNid,
        nodeExtentsByNid: _nodeExtentsByNid,
        inCacheRegionByNid: _inCacheRegionByNid,
        onCacheRegionAdmit: _writeCacheRegionNid,
        effectiveCacheEnd: effectiveCacheEnd,
        slideOverreach: slideOverreach,
        remainingCacheExtent: remainingCacheExtent,
      );
    }

    // Create children for nodes in the cache region.
    //
    // The range `[cacheStartIndex, cacheEndIndex)` may contain rows that
    // were iterated but not admitted (e.g. off-screen exits during a
    // collapse — iterated past to reach the post-animation-visible
    // following rows, but not admitted themselves). Gate on
    // `_inCacheRegionByNid[nid]` so skipped rows do not trigger a build.
    if (cacheEndIndex > cacheStartIndex) {
      invokeLayoutCallback<SliverConstraints>((SliverConstraints constraints) {
        for (int i = cacheStartIndex; i < cacheEndIndex; i++) {
          final nodeId = visibleNodes[i];
          final nid = _controller.nidOf(nodeId);
          if (_inCacheRegionByNid[nid] == 0) continue;
          childManager?.createChild(nodeId);
        }
      });
    }

    // Layout the children — track whether any extent changed to skip
    // the O(N) _recomputeOffsets when sizes are stable (cache hit path).
    // Also track the smallest index whose extent changed so we can walk
    // only from there when recomputing offsets.
    bool extentsChanged = false;
    int firstChangedIdx = visibleNodes.length;

    for (int i = cacheStartIndex; i < cacheEndIndex; i++) {
      final nodeId = visibleNodes[i];
      final actualAnimatedExtent = _layoutNodeChild(nodeId, crossAxisExtent);
      if (actualAnimatedExtent == null) continue;

      final nid = _controller.nidOf(nodeId);
      final estimatedExtent = _nodeExtentsByNid[nid];
      if (actualAnimatedExtent != estimatedExtent) {
        _nodeExtentsByNid[nid] = actualAnimatedExtent;
        totalScrollExtent += actualAnimatedExtent - estimatedExtent;
        extentsChanged = true;
        if (i < firstChangedIdx) firstChangedIdx = i;
      }

      final child = getChildForNode(nodeId)!;
      final parentData = child.parentData! as SliverTreeParentData;
      parentData.layoutOffset = _nodeOffsetsByNid[nid];
    }

    // Only recompute offsets if actual extents differed from estimates.
    // During steady-state animation (constraint cache hit → same sizes),
    // this skips the full O(N) recomputation. When extents did change,
    // only walk from the first changed index forward — offsets before
    // that point are unaffected by later-index extent changes.
    if (extentsChanged) {
      _sticky.dirty = true;

      if (_bulkCumulativesValid) {
        // A child's measured size perturbed _fullExtents mid-bulk; the
        // cumulatives are now inconsistent with truth for positions beyond
        // firstChangedIdx. Materialize per-nid extents for the affected
        // tail so _recomputeOffsetsFrom can walk it, then fall back off
        // the fast path for this frame. The next frame will rebuild cumulatives
        // fresh via _rebuildBulkCumulatives.
        final orderNids = controller.orderNidsView;
        for (int i = firstChangedIdx; i < visibleNodes.length; i++) {
          if (i >= cacheStartIndex && i < cacheEndIndex) continue;
          final nid = orderNids[i];
          _nodeExtentsByNid[nid] = controller.getCurrentExtentNid(nid);
        }
        _bulkCumulativesValid = false;
      }

      totalScrollExtent = _recomputeOffsetsFrom(firstChangedIdx);

      // Only rewrite parentData.layoutOffset for cache-region nodes at or
      // after firstChangedIdx. Earlier cache-region nodes already had the
      // correct value written in the measurement loop above.
      final updateStart = math.max(cacheStartIndex, firstChangedIdx);
      final orderNids = controller.orderNidsView;
      for (int i = updateStart; i < cacheEndIndex; i++) {
        final nodeId = visibleNodes[i];
        final child = getChildForNode(nodeId);
        if (child == null) continue;
        final parentData = child.parentData! as SliverTreeParentData;
        parentData.layoutOffset = _nodeOffsetsByNid[orderNids[i]];
      }
    }

    // Precompute subtree bottoms BEFORE sticky identification so that
    // candidate probing can use O(1) lookups instead of O(n)-per-candidate
    // subtree scans. Skip during animation: candidate probing bails on
    // animating nodes anyway, so the O(3N) precomputation is wasted. The
    // fallback per-candidate scan inside the computer is trivially cheap
    // since it also bails immediately. Also skip when nothing changed
    // since last precomputation (pure scrolling).
    if (_animationsWereActive && !hasAnimations) {
      _sticky.dirty = true; // animation just settled — one final pass
    }
    if (_maxStickyDepth > 0 && !hasAnimations && _sticky.dirty) {
      _sticky.precomputeStableSubtreeBottoms(
        visibleNodes: visibleNodes,
        nodeOffsetsByNid: _nodeOffsetsByNid,
        nodeExtentsByNid: _nodeExtentsByNid,
      );
      _sticky.dirty = false;
    } else if (hasAnimations || _maxStickyDepth == 0) {
      _sticky.invalidatePrecompute();
    }

    // Throttle sticky header recomputation during animation: only recompute
    // every 3rd frame. The candidate probe bails on animating candidates
    // anyway, so results are approximate and largely unchanged frame-to-
    // frame. Exception: scrolling since the last sticky computation forces
    // a recompute — pinnedY is relative to scrollOffset, and stale values
    // produce visible header jitter plus wrong hit-test coordinates.
    final bool skipStickyRecompute = !_sticky.shouldRecomputeThisFrame(
      hasActiveAnimations: controller.hasActiveAnimations,
      scrollOffset: scrollOffset,
    );

    if (skipStickyRecompute) {
      // Even when throttling, purge entries for nodes that just started
      // exiting so a stale pinned row doesn't keep painting / inflate
      // paintExtent for another 1–2 frames.
      _sticky.purgeExitingDuringThrottle();
    } else {
      // Identify sticky candidates now that offsets and precomputed data are ready.
      final potentialStickyNodes = _sticky.identifyPotentialStickyNodes(
        scrollOffset: scrollOffset,
        overlap: constraints.overlap,
        visibleNodes: visibleNodes,
        nodeOffsetsByNid: _nodeOffsetsByNid,
        nodeExtentsByNid: _nodeExtentsByNid,
        findFirstVisibleIndex: _findFirstVisibleIndex,
      );

      // Force-create and layout any sticky nodes not already in cache region.
      // Filter by the cache-region flag rather than allocating a diff set.
      final newStickyNodes = <TKey>{};
      for (final id in potentialStickyNodes) {
        final nid = _controller.nidOf(id);
        if (nid < 0 || _inCacheRegionByNid[nid] == 0) {
          newStickyNodes.add(id);
        }
      }
      if (newStickyNodes.isNotEmpty) {
        invokeLayoutCallback<SliverConstraints>((
          SliverConstraints constraints,
        ) {
          for (final nodeId in newStickyNodes) {
            childManager?.createChild(nodeId);
          }
        });
        // Track whether any measured sticky extent actually differs from the
        // prior stored (estimated) extent. When all match, Pass 1's offsets
        // and subtree-bottom precompute are still valid, so both the O(N)
        // offset recompute and the O(3N) subtree-bottom precompute can be
        // skipped entirely.
        bool stickyExtentsChanged = false;
        for (final nodeId in newStickyNodes) {
          final nid = _controller.nidOf(nodeId);
          final priorExtent = _nodeExtentsByNid[nid];
          final extent = _layoutNodeChild(nodeId, crossAxisExtent);
          if (extent != null) {
            _nodeExtentsByNid[nid] = extent;
            if (extent != priorExtent) stickyExtentsChanged = true;
          }
        }
        if (stickyExtentsChanged) {
          totalScrollExtent = _recomputeOffsets();
          if (_maxStickyDepth > 0 && !hasAnimations) {
            _sticky.precomputeStableSubtreeBottoms(
              visibleNodes: visibleNodes,
              nodeOffsetsByNid: _nodeOffsetsByNid,
              nodeExtentsByNid: _nodeExtentsByNid,
            );
            _sticky.dirty = false;
          }
        }
        // Always write the newly-created sticky children's layoutOffset —
        // they were outside the cache region during Pass 1 and never had it set.
        for (final nodeId in newStickyNodes) {
          final child = getChildForNode(nodeId);
          if (child == null) continue;
          final parentData = child.parentData! as SliverTreeParentData;
          parentData.layoutOffset =
              _nodeOffsetsByNid[_controller.nidOf(nodeId)];
        }
      }

      _sticky.computeStickyHeaders(
        scrollOffset: scrollOffset,
        overlap: constraints.overlap,
        visibleNodes: visibleNodes,
        nodeOffsetsByNid: _nodeOffsetsByNid,
        nodeExtentsByNid: _nodeExtentsByNid,
        findFirstVisibleIndex: _findFirstVisibleIndex,
      );
    }

    // ────────────────────────────────────────────────────────────────────────
    // Calculate paint extent
    // ────────────────────────────────────────────────────────────────────────
    double paintExtent = 0.0;

    final startIndex = _findFirstVisibleIndex(scrollOffset);
    final orderNids = controller.orderNidsView;
    for (int i = startIndex; i < visibleNodes.length; i++) {
      final nid = orderNids[i];
      final offset = _nodeOffsetsByNid[nid];
      final extent = _nodeExtentsByNid[nid];
      final endOfNode = offset + extent;

      if (offset >= scrollOffset + remainingPaintExtent) break;

      final visibleStart = math.max(offset, scrollOffset);
      final visibleEnd = math.min(
        endOfNode,
        scrollOffset + remainingPaintExtent,
      );
      // Only add positive contributions (can be negative when scrolled past content)
      if (visibleEnd > visibleStart) {
        paintExtent += visibleEnd - visibleStart;
      }
    }

    // Bug 1 fix: Ensure paintExtent covers sticky headers. Sticky headers
    // paint at pinnedY (near viewport top) but content may have scrolled far
    // enough that the natural paint extent doesn't cover them, causing clipping.
    bool stickyInflationClamped = false;
    for (final sticky in _sticky.headers) {
      final stickyBottom = sticky.pinnedY + sticky.extent;
      if (stickyBottom > remainingPaintExtent) {
        // This header would extend past our paint budget and overlap the
        // next sliver. We cannot relocate it here (pinnedY is final), but
        // flagging visual overflow ensures the viewport clips us to
        // paintExtent so it doesn't bleed through.
        stickyInflationClamped = true;
      }
      if (stickyBottom > paintExtent) paintExtent = stickyBottom;
    }

    // Ensure paintExtent is non-negative and within bounds
    paintExtent = paintExtent.clamp(0.0, remainingPaintExtent);

    geometry = SliverGeometry(
      scrollExtent: totalScrollExtent,
      paintExtent: paintExtent,
      maxPaintExtent: totalScrollExtent,
      cacheExtent: math.min(remainingCacheExtent, totalScrollExtent),
      // Overflow means: our painted region would exceed the portion of the
      // scroll extent visible within our own paintExtent. Comparing against
      // remainingPaintExtent (which includes space occupied by later slivers)
      // gave false negatives and missed clipping. Also flag when a sticky
      // header's inflated bottom was clamped against remainingPaintExtent.
      // The `scrollOffset > 0` clause mirrors RenderSliverMultiBoxAdaptor:
      // when the first visible row starts before scrollOffset, it paints at
      // a negative y relative to the sliver's paint origin. Without this
      // flag, the viewport skips its clip layer and the partial top row
      // spills above the sliver — visible at max scroll extent, where the
      // "content extends below" clause is false.
      hasVisualOverflow:
          stickyInflationClamped ||
          scrollOffset + paintExtent < totalScrollExtent ||
          scrollOffset > 0.0,
    );

    // Refresh parentData.layoutOffset for children mounted in a prior
    // frame that now fall outside [cacheStartIndex, cacheEndIndex). The
    // admission cap (steadyAccum / fullCacheEnd) deliberately limits *new*
    // mounts to prevent mass-mounting during large expansions, but
    // siblings below the expanding subtree that were already mounted keep
    // their pre-expand parentData.layoutOffset — causing them to paint at
    // stale positions through the whole animation and only snap into place
    // on the settle frame, when Pass 1's "Transitional frame" branch
    // finally rewrites extents.
    //
    // Placed after the sticky pass so any _recomputeOffsets triggered by
    // stickyExtentsChanged has already landed in _nodeOffsetsByNid /
    // cumulatives before we write to parentData.
    //
    // Only runs during active animations; pure scrolling doesn't mutate
    // offsets so cached parentData is already correct.
    //
    // Iterate `_children.keys` directly: the loop body acts only on
    // mounted boxes, so the previous `for (int i = 0; i < visibleNodes.length; i++)`
    // walk did O(visibleNodes) work to update O(_children) entries. On a
    // dense expandAll with 10⁵ visible nodes and a 50-row viewport this
    // walked 10⁵ entries per frame for ~50 writes — now O(_children).
    // Refresh parentData (layoutOffset, indent, visibleExtent) for
    // off-cache mounted children.
    //
    // Runs unconditionally when there are mounted children. Cost is
    // O(_children) — bounded by cache-region size plus any retained
    // off-cache rows (edge ghosts, exit phantoms, slide-active rows).
    // Always running closes a subtle staleness window:
    //
    //   * Past trigger (now baseline) was `hasAnimations || hasActiveSlides`,
    //     under the assumption that pure scrolling can't mutate offsets so
    //     cached parentData is already correct. That assumption breaks for
    //     a sequence: STRUCTURAL MUTATION (no slides installed — e.g. rapid
    //     cascaded toggle whose composedY/X both round to 0 → engine clears
    //     the entry), then PURE SCROLL. The mutation's layout updates
    //     parentData only for in-cache rows; off-cache rows whose structural
    //     just shifted keep their pre-mutation layoutOffset. The follow-up
    //     scroll's layout sees `!hasAnimations && !hasActiveSlides` so the
    //     gated refresh skips them. The off-cache row paints at its OLD
    //     structural Y until something else triggers a layout that DOES
    //     re-admit it to cache (typically a further scroll into its new
    //     structural Y). User-perceived symptom: "row stuck at old position
    //     until I scroll again."
    //
    //   * Stale `indent` for depth-changing reparents: same path. Painted
    //     X = `parentData.indent + slideDeltaX` resolves to `oldIndent +
    //     (oldIndent - newIndent)` at slide t=0 if `parentData.indent` is
    //     stale.
    //
    //   * Stale `visibleExtent`: the per-row clip-and-translate in
    //     `_paintRow` slices the wrong portion of the child box.
    //
    // For non-bulk mode, `_nodeOffsetsByNid` is stale for off-cache rows.
    // Compute a fresh structural cumulative on-demand by walking
    // `visibleNodes` once into a local Float64List, then index into it.
    if (_children.isNotEmpty) {
      Float64List? freshCumulative;
      if (!_bulkCumulativesValid) {
        // O(N_visible) one-time accumulation for the loop below.
        final vlen = visibleNodes.length;
        freshCumulative = Float64List(vlen + 1);
        double acc = 0.0;
        for (int i = 0; i < vlen; i++) {
          freshCumulative[i] = acc;
          acc += controller.getCurrentExtentNid(orderNids[i]);
        }
        freshCumulative[vlen] = acc;
      }
      for (final nodeId in _children.keys) {
        debugLastParentDataRefreshIterationCount++;
        final child = _children[nodeId]!;
        final nid = _controller.nidOf(nodeId);
        if (nid < 0) {
          // Dead key — purge handled by stale-node eviction.
          continue;
        }
        // Cache-region children already had their parentData written by
        // the measurement loop. Skip them. Non-admitted-but-mounted
        // children inside [cacheStartIndex, cacheEndIndex) have
        // `_inCacheRegionByNid[nid] == 0` here and would also have been
        // touched by the measurement loop via `_layoutNodeChild` — letting
        // them through is a redundant (but correctness-safe) re-write of
        // the same offset. Cost is one field assignment per such row;
        // the case is rare (off-screen exits during a collapse).
        if (nid < _inCacheRegionByNid.length && _inCacheRegionByNid[nid] != 0) {
          continue;
        }
        final visIdx = _controller.visibleIndexOfNid(nid);
        if (visIdx < 0) {
          // Mounted but no longer in visible order — happens transiently
          // during structure changes. Eviction sweeps it next.
          continue;
        }
        final double offset;
        if (_bulkCumulativesValid) {
          // Bulk-only fast path: per-nid offset slots are not kept fresh
          // for out-of-cache-region nids — derive from cumulatives.
          offset = _offsetAtVisibleIndex(visIdx);
        } else {
          // Non-bulk: `_nodeOffsetsByNid` is stale for off-cache rows.
          // Use the freshly-computed cumulative.
          offset = freshCumulative![visIdx];
        }
        final parentData = child.parentData! as SliverTreeParentData;
        parentData.layoutOffset = offset;
        // Refresh indent + visibleExtent against the controller's live
        // values. Both are read directly from the controller (no per-
        // child layout call required), matching the assignments
        // `_layoutNodeChild` would have performed on a cache-region row.
        // `controller.getIndent` reads `getDepth(key) * indentWidth`,
        // and `controller.getCurrentExtentNid` resolves the
        // bulk → operation-group → standalone → fullExtent chain — the
        // same chain `_layoutNodeChild` consumes via `getAnimatedExtent`.
        parentData.indent = controller.getIndent(nodeId);
        parentData.visibleExtent = controller.getCurrentExtentNid(nid);
      }
    }

    _lastVisibleNodeCount = visibleNodes.length;
    _lastTotalScrollExtent = totalScrollExtent;
    _animationsWereActive = hasAnimations;

    childManager?.didFinishLayout();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAINTING
  // ══════════════════════════════════════════════════════════════════════════

  int _findFirstVisibleIndex(double scrollOffset) {
    final n = _controller.visibleNodeCount;
    if (n == 0) return 0;

    int low = 0;
    int high = n - 1;

    if (_bulkCumulativesValid && _bulkCumulativesCount == n) {
      // Bulk-only fast path: derive offset+extent at each probe from cumulatives
      // without touching per-nid arrays (which are only kept fresh for
      // cache-region nids in this mode).
      while (low < high) {
        final mid = (low + high) ~/ 2;
        final offsetEnd = _offsetAtVisibleIndex(mid + 1);
        if (offsetEnd <= scrollOffset) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      return low;
    }

    final orderNids = _controller.orderNidsView;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final nid = orderNids[mid];
      final offset = _nodeOffsetsByNid[nid];
      final extent = _nodeExtentsByNid[nid];

      if (offset + extent <= scrollOffset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (geometry == null || geometry!.paintExtent == 0) return;

    final scrollOffset = constraints.scrollOffset;
    final remainingPaintExtent = constraints.remainingPaintExtent;
    final visibleNodes = controller.visibleNodes;
    final orderNids = controller.orderNidsView;

    // Hoist per-axis slide-activity checks out of the loop. When idle
    // (no slides in flight), the per-row deltas are guaranteed 0 — skip
    // the lookups entirely. X-axis slides are rare even during slide
    // cycles (most reorders are same-depth) so a separate check
    // suppresses X reads in the common Y-only case.
    final hasSlides = controller.hasActiveSlides;
    final hasXSlides = hasSlides && controller.hasActiveXSlides;

    // Widen the paint iteration start by the active FLIP-slide overreach
    // so rows structurally before the viewport but painting INTO it (via
    // a positive slide delta) are not skipped. `_paintRow` already bails
    // on rows whose painted y lies past the viewport, so extra iterated
    // rows on the bottom edge are harmless. See the matching comment in
    // `performLayout` for why structural offsets alone aren't enough.
    final slideOverreach = controller.maxActiveSlideAbsDelta;
    final startIndex = _findFirstVisibleIndex(scrollOffset - slideOverreach);

    // Pass A: Paint non-sticky nodes. Rows with a non-zero slide delta are
    // deferred to a second sub-pass so they paint on top of static rows —
    // without this, an upward-moving row that hasn't yet crossed into its
    // final index slot would be covered by siblings sliding down past it.
    // Among sliding rows, sort by ascending |delta| so the row that moved
    // the most (typically the just-dropped row) paints last and lands on
    // top. Ties preserve natural iteration order.
    final edgeExits = _phantomEdgeExits;
    List<int>? slidingIndices;
    for (int i = startIndex; i < visibleNodes.length; i++) {
      final nid = orderNids[i];
      if (_sticky.isSticky(nid)) {
        continue;
      }

      final nodeId = visibleNodes[i];

      final child = getChildForNode(nodeId);
      if (child == null) continue;

      // Paint-only FLIP slide delta — read from the controller on every
      // frame so localToGlobal / semantics (which can resolve between
      // ticks) always see the current value. Skipped entirely when no
      // slides are active.
      final slideDelta = hasSlides ? controller.getSlideDeltaNid(nid) : 0.0;
      final slideDeltaX = hasXSlides ? controller.getSlideDeltaXNid(nid) : 0.0;

      // Edge-ghost rows paint via the parallel edge-ghost pass at
      // `entry.edgeY + slideDelta` — skip standard paint so they don't
      // double-paint at the wrong (structural) position. BUT only when
      // the engine still has a live slide entry for this nid; if the
      // engine cleared the slide via composition (composedY/X both 0)
      // while the `_phantomEdgeExits` map entry survived (e.g.
      // direction-flip kept the entry, then composition zeroed the
      // delta), the edge-ghost paint pass will prune the entry without
      // painting. Skipping standard paint here would leave the row
      // invisible until the next layout's prune. Instead, only skip
      // when there's actually a delta to render via the edge-ghost
      // pass; otherwise fall through to standard paint at structural+0.
      if (edgeExits != null
          && edgeExits.containsKey(nodeId)
          && (slideDelta != 0.0 || slideDeltaX != 0.0)) {
        continue;
      }

      if (slideDelta != 0.0 || slideDeltaX != 0.0) {
        (slidingIndices ??= <int>[]).add(i);
        continue;
      }

      _paintRow(
        context: context,
        offset: offset,
        nid: nid,
        child: child,
        slideDelta: 0.0,
        slideDeltaX: 0.0,
        scrollOffset: scrollOffset,
        remainingPaintExtent: remainingPaintExtent,
      );
    }

    if (slidingIndices != null) {
      // Sort by Y delta only — X delta is bounded by indent (~24-200px
      // typical) and much smaller than Y; Y-only sort suffices for "row
      // that moved most paints last."
      slidingIndices.sort((a, b) {
        final da = controller.getSlideDeltaNid(orderNids[a]).abs();
        final db = controller.getSlideDeltaNid(orderNids[b]).abs();
        final cmp = da.compareTo(db);
        if (cmp != 0) return cmp;
        return a.compareTo(b);
      });
      for (final i in slidingIndices) {
        final nodeId = visibleNodes[i];
        final child = getChildForNode(nodeId);
        if (child == null) continue;
        // hasSlides is implicitly true here (slidingIndices is non-empty
        // means at least one row had a non-zero delta). Read directly.
        _paintRow(
          context: context,
          offset: offset,
          nid: orderNids[i],
          child: child,
          slideDelta: controller.getSlideDeltaNid(orderNids[i]),
          slideDeltaX:
              hasXSlides ? controller.getSlideDeltaXNid(orderNids[i]) : 0.0,
          scrollOffset: scrollOffset,
          remainingPaintExtent: remainingPaintExtent,
        );
      }
    }

    // Pass A.5: Paint phantom-exit ghosts. These are rows that were
    // visible at staging time but are now hidden under a collapsed
    // parent; they slide INTO the parent's row and disappear behind
    // it. Iterated in a separate pass because they're not in
    // visibleNodes (they were purged when the move ran). Each ghost
    // is painted at the exit anchor's current painted position offset
    // by the ghost's own slide delta. The clip in `_paintRow`
    // (driven by _phantomClipAnchors) handles the "occluded by
    // parent" effect.
    final ghosts = _phantomExitGhosts;
    if (ghosts != null && ghosts.isNotEmpty) {
      // Idle-state shortcut: if no slides are active, every ghost in
      // the map is settled (no slide entry exists for any of them).
      // Drop the whole map and skip the loop.
      if (!hasSlides) {
        for (final ghostKey in ghosts.keys) {
          _phantomClipAnchors?.remove(ghostKey);
        }
        _phantomExitGhosts = null;
      } else {
        // Snapshot keys to avoid concurrent-modification when we lazily
        // evict settled ghosts mid-iteration.
        final ghostKeys = ghosts.keys.toList();
        for (final ghostKey in ghostKeys) {
          final anchorKey = ghosts[ghostKey];
          if (anchorKey == null) continue;
          final ghostNid = controller.nidOf(ghostKey);
          if (ghostNid < 0) {
            ghosts.remove(ghostKey);
            continue;
          }
          final ghostSlide = controller.getSlideDeltaNid(ghostNid);
          final ghostSlideX =
              hasXSlides ? controller.getSlideDeltaXNid(ghostNid) : 0.0;
          // Slide settled — drop the ghost. The next stale-eviction pass
          // will release the render box.
          if (ghostSlide == 0.0 && ghostSlideX == 0.0) {
            ghosts.remove(ghostKey);
            _phantomClipAnchors?.remove(ghostKey);
            continue;
          }
          final ghostChild = getChildForNode(ghostKey);
          if (ghostChild == null) continue;
          final anchorChild = getChildForNode(anchorKey);
          if (anchorChild == null) continue;
          final anchorParentData = anchorChild.parentData;
          if (anchorParentData is! SliverTreeParentData) continue;
          final anchorNid = controller.nidOf(anchorKey);
          final anchorSlide = anchorNid >= 0
              ? controller.getSlideDeltaNid(anchorNid)
              : 0.0;
          final anchorSlideX = (hasXSlides && anchorNid >= 0)
              ? controller.getSlideDeltaXNid(anchorNid)
              : 0.0;
        // Ghost's painted position = anchor's painted position + ghost's
        // own slide delta. As the ghost's slide settles to 0, the ghost
        // converges on the anchor's row.
        final paintedY =
            anchorParentData.layoutOffset - scrollOffset + anchorSlide +
            ghostSlide;
        final paintedX =
            anchorParentData.indent + anchorSlideX + ghostSlideX;
        // Skip if entirely outside the paint region.
        if (paintedY >= remainingPaintExtent) continue;
        if (paintedY + ghostChild.size.height <= 0) continue;
        // Apply the same clip mechanism as the entry-phantom case so
        // the anchor visually occludes the ghost as it slides in.
        final clipRect = _resolvePhantomAnchorBounds(
          nid: ghostNid,
          paintedY: paintedY,
          offset: offset,
          remainingPaintExtent: remainingPaintExtent,
        );
        final paintOffset = offset + Offset(paintedX, paintedY);
        if (clipRect != null) {
          context.pushClipRect(
            needsCompositing,
            offset,
            clipRect,
            (ctx, off) => ctx.paintChild(ghostChild, paintOffset),
          );
        } else {
          context.paintChild(ghostChild, paintOffset);
        }
        }
      }
    }

    // Pass A.6: Paint edge-anchor exit ghosts (live-edge-anchored
    // ghosts for long slide-OUTs). These rows ARE in visibleNodes but
    // skipped by the standard paint pass — their painted position is
    // `_edgeGhostBaseY(entry, currentViewport) + slideDelta` in
    // scroll-space, recomputed against the live viewport so the ghost
    // stays pinned to the live edge under concurrent scrolling. As the
    // slide settles, the row converges on the viewport edge and is
    // then lazily pruned (no visible cut because the row's structural
    // position is far off-screen).
    final edgeGhosts = _phantomEdgeExits;
    if (edgeGhosts != null && edgeGhosts.isNotEmpty) {
      // Idle-state shortcut.
      if (!hasSlides) {
        _phantomEdgeExits = null;
      } else {
        final viewport = _currentViewportSnapshot();
        final edgeKeys = edgeGhosts.keys.toList();
        for (final ghostKey in edgeKeys) {
          final entry = edgeGhosts[ghostKey];
          if (entry == null) continue;
          final ghostNid = controller.nidOf(ghostKey);
          if (ghostNid < 0) {
            edgeGhosts.remove(ghostKey);
            continue;
          }
          // Defensive: if a ghost row is also a sticky header, let the
          // sticky pass handle it (paints at pinned structural y). Edge
          // ghost behaviour is lost for this row, but no double-paint.
          // Sticky + slide-OUT-to-far-off-screen is uncommon.
          if (_sticky.isSticky(ghostNid)) continue;
          final ghostSlide = controller.getSlideDeltaNid(ghostNid);
          final ghostSlideX = hasXSlides
              ? controller.getSlideDeltaXNid(ghostNid)
              : 0.0;
          // Eager prune on settle — avoids one-frame lingering at edge
          // between settle and next consume's lazy-prune.
          if (ghostSlide == 0.0 && ghostSlideX == 0.0) {
            edgeGhosts.remove(ghostKey);
            continue;
          }
          final ghostChild = getChildForNode(ghostKey);
          if (ghostChild == null) continue;
          final indent = controller.getIndent(ghostKey);
          // Ghost paints at `liveBaseY + slideDelta` in scroll-space,
          // converted to local paint coords by subtracting scrollOffset.
          final paintedY =
              _edgeGhostBaseY(entry, viewport) - scrollOffset + ghostSlide;
          final paintedX = indent + ghostSlideX;
          // Skip if entirely outside the paint region.
          if (paintedY >= remainingPaintExtent) continue;
          if (paintedY + ghostChild.size.height <= 0) continue;
          context.paintChild(ghostChild, offset + Offset(paintedX, paintedY));
        }
        if (edgeGhosts.isEmpty) _phantomEdgeExits = null;
      }
    }

    // Pass B: Paint sticky headers (deepest first so shallower paints on top).
    final paintExtent = geometry!.paintExtent;
    final stickyHeaders = _sticky.headers;
    for (int i = stickyHeaders.length - 1; i >= 0; i--) {
      final sticky = stickyHeaders[i];
      final child = getChildForNode(sticky.nodeId);
      if (child == null) continue;
      // Skip nodes currently animating out. Sticky recompute is throttled
      // during animations, so _stickyHeaders may still contain entries for
      // nodes that just entered pendingRemoval — painting them would leave
      // a ghost row until the next recompute tick.
      if (controller.isExiting(sticky.nodeId)) continue;

      // Don't paint a header that has been pushed entirely past the sliver's
      // paint region (e.g. by a tiny remainingPaintExtent near the bottom).
      if (sticky.pinnedY >= paintExtent) continue;

      // Clip to whichever is smaller: the header's natural extent, or the
      // remaining paint region. Without this clamp the header would spill
      // into the next sliver when pinnedY + extent > paintExtent.
      final clippedExtent = math.min(
        sticky.extent,
        paintExtent - sticky.pinnedY,
      );
      if (clippedExtent <= 0) continue;

      final paintOffset = offset + Offset(sticky.indent, sticky.pinnedY);
      context.pushClipRect(
        needsCompositing,
        paintOffset,
        Rect.fromLTWH(0, 0, child.size.width, clippedExtent),
        (context, offset) {
          context.paintChild(child, offset);
        },
      );
    }
  }

  void _paintRow({
    required PaintingContext context,
    required Offset offset,
    required int nid,
    required RenderBox child,
    required double slideDelta,
    required double slideDeltaX,
    required double scrollOffset,
    required double remainingPaintExtent,
  }) {
    final parentData = child.parentData! as SliverTreeParentData;
    final nodeOffset = parentData.layoutOffset;
    final nodeExtent = parentData.visibleExtent;

    // A node whose painted position lies past the paint region can't be
    // visible; skip. The caller can't `break` on this — a later node might
    // have a negative slideDelta that puts it back in view.
    if (nodeOffset + slideDelta >= scrollOffset + remainingPaintExtent) {
      return;
    }

    final paintOffset =
        offset +
        Offset(
          parentData.indent + slideDeltaX,
          nodeOffset - scrollOffset + slideDelta,
        );

    // Phantom-clip: if this row was installed with a phantom anchor (i.e.
    // a previously-hidden node now reparented into view), clip its paint
    // to the region outside the anchor's bounds so the anchor visually
    // occludes it. Direction: clip below the anchor for downward slides
    // (destination below anchor), above for upward. As the slide
    // progresses, the row emerges past the anchor's edge.
    final phantomAnchor = _resolvePhantomAnchorBounds(
      nid: nid,
      paintedY: nodeOffset - scrollOffset + slideDelta,
      offset: offset,
      remainingPaintExtent: remainingPaintExtent,
    );

    final paintChild = (PaintingContext ctx, Offset off) {
      if (controller.isAnimatingNid(nid) && nodeExtent < child.size.height) {
        final yOffset = -(child.size.height - nodeExtent);
        ctx.pushClipRect(
          needsCompositing,
          off,
          Rect.fromLTWH(0, 0, child.size.width, nodeExtent),
          (ctx2, off2) {
            ctx2.paintChild(child, off2 + Offset(0, yOffset));
          },
        );
      } else {
        ctx.paintChild(child, off);
      }
    };

    if (phantomAnchor != null) {
      // Push a clip rect covering the visible region OUTSIDE the anchor's
      // painted bounds in the slide direction. The clip is in the local
      // coordinate space of the sliver's paint offset (offset.dy at the
      // top of the sliver in viewport coordinates).
      context.pushClipRect(
        needsCompositing,
        offset,
        phantomAnchor,
        (ctx, off) => paintChild(ctx, paintOffset),
      );
    } else {
      paintChild(context, paintOffset);
    }
  }

  /// Computes the clip rect for a phantom-anchored sliding row, or null
  /// if no clip is needed (no phantom anchor recorded for this row, or
  /// the anchor isn't currently mounted).
  ///
  /// Returns a rect in coordinates LOCAL to the sliver's paint offset.
  /// The rect covers the entire viewport main-axis range EXCEPT the
  /// anchor's painted Y range — depending on slide direction, either
  /// the region above the anchor (for upward slides) or below (for
  /// downward).
  Rect? _resolvePhantomAnchorBounds({
    required int nid,
    required double paintedY,
    required Offset offset,
    required double remainingPaintExtent,
  }) {
    final clipAnchors = _phantomClipAnchors;
    if (clipAnchors == null || clipAnchors.isEmpty) return null;

    final key = _controller.keyOfNid(nid);
    if (key == null) return null;
    final anchorKey = clipAnchors[key];
    if (anchorKey == null) return null;

    final anchorChild = _children[anchorKey];
    if (anchorChild == null) return null;
    final anchorParentData = anchorChild.parentData;
    if (anchorParentData is! SliverTreeParentData) return null;

    final scrollOffset = constraints.scrollOffset;
    final anchorNid = _controller.nidOf(anchorKey);
    final anchorSlideDelta = anchorNid >= 0
        ? _controller.getSlideDeltaNid(anchorNid)
        : 0.0;
    // Anchor's current painted Y (sliver-local — relative to the start
    // of this sliver's paint region).
    final anchorPaintedY =
        anchorParentData.layoutOffset - scrollOffset + anchorSlideDelta;
    final anchorHeight = anchorChild.size.height;

    // Clip direction = "side of the anchor where painted lies."
    //
    // For ENTRY (row sliding FROM anchor TO destination): painted starts
    // at anchor and moves toward destination. After the install frame
    // painted is on the destination side of anchor → clip to that side.
    // The anchor occludes the row's start of trajectory.
    //
    // For EXIT (row sliding FROM old position TO anchor): painted starts
    // at old position and moves toward anchor. Throughout, painted is
    // on the old-position side of anchor → clip to that side. The anchor
    // occludes the row's end of trajectory.
    //
    // Both reduce to: visible region = the half-plane on the side where
    // painted Y currently sits relative to anchor's Y range.
    final width = constraints.crossAxisExtent;
    if (paintedY > anchorPaintedY) {
      // Painted below anchor → visible region = y >= anchor.bottom.
      final clipTop = anchorPaintedY + anchorHeight;
      final clipBottom = remainingPaintExtent;
      if (clipBottom <= clipTop) return Rect.zero;
      return Rect.fromLTRB(0, clipTop, width, clipBottom);
    } else if (paintedY < anchorPaintedY) {
      // Painted above anchor → visible region = y <= anchor.top.
      if (anchorPaintedY <= 0) return Rect.zero;
      return Rect.fromLTRB(0, 0, width, anchorPaintedY);
    } else {
      // Painted exactly at anchor → row entirely occluded by anchor's
      // row-height range. Empty clip = nothing painted.
      return Rect.zero;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HIT TESTING
  // ══════════════════════════════════════════════════════════════════════════

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    final scrollOffset = constraints.scrollOffset;
    final visibleNodes = controller.visibleNodes;
    final orderNids = controller.orderNidsView;

    // Phase 1: Test sticky headers first (they're visually on top).
    // Iterate shallowest first (index 0) = topmost = first hit priority.
    for (final sticky in _sticky.headers) {
      final child = getChildForNode(sticky.nodeId);
      if (child == null) continue;
      if (controller.isExiting(sticky.nodeId)) continue;

      final localMain = mainAxisPosition - sticky.pinnedY;
      if (localMain < 0 || localMain >= sticky.extent) continue;

      final localCross = crossAxisPosition - sticky.indent;
      if (localCross < 0) continue;

      final hit = result.addWithAxisOffset(
        paintOffset: Offset(sticky.indent, sticky.pinnedY),
        mainAxisOffset: sticky.pinnedY,
        crossAxisOffset: sticky.indent,
        mainAxisPosition: mainAxisPosition,
        crossAxisPosition: crossAxisPosition,
        hitTest:
            (
              SliverHitTestResult result, {
              required double mainAxisPosition,
              required double crossAxisPosition,
            }) {
              return child.hitTest(
                BoxHitTestResult.wrap(result),
                position: Offset(crossAxisPosition, mainAxisPosition),
              );
            },
      );

      if (hit) return true;
    }

    // Phase 2: Test normal nodes (skip sticky IDs). Widen the start by
    // the FLIP-slide overreach so a tap on a row whose structural y is
    // above the hit offset — but which has slid down into the tap point
    // — is still tested. The per-row `localMainAxisPosition` bounds
    // check below naturally skips non-overlapping rows, so iterating
    // extra rows at the top is cheap.
    final slideOverreach = controller.maxActiveSlideAbsDelta;
    final hitOffset = scrollOffset + mainAxisPosition;
    final startIndex = _findFirstVisibleIndex(hitOffset - slideOverreach);

    // Hoist per-axis slide-activity checks (idle-state fast path).
    final hasSlides = controller.hasActiveSlides;
    final hasXSlides = hasSlides && controller.hasActiveXSlides;
    // Lazy viewport: only built if a ghost row is encountered.
    _ViewportSnapshot? hitViewport;

    for (int i = startIndex; i < visibleNodes.length; i++) {
      final nid = orderNids[i];
      if (_sticky.isSticky(nid)) {
        continue;
      }

      final nodeId = visibleNodes[i];
      final child = getChildForNode(nodeId);
      if (child == null) continue;

      // Skip exiting nodes - they should not receive interactions
      // This prevents crashes when rapidly tapping delete buttons
      if (controller.isExitingNid(nid)) continue;

      final parentData = child.parentData! as SliverTreeParentData;
      // Edge-ghost rows paint at `_edgeGhostBaseY + slideDelta` (NOT at
      // structural + slideDelta). Substitute the live edge base for
      // the structural offset so hit-tests land on the painted (ghost)
      // position. Lazy: build the snapshot once, only if any ghost is
      // actually encountered.
      final edgeEntry = _phantomEdgeExits?[nodeId];
      final double nodeOffset;
      if (edgeEntry != null) {
        hitViewport ??= _currentViewportSnapshot();
        nodeOffset = _edgeGhostBaseY(edgeEntry, hitViewport);
      } else {
        nodeOffset = parentData.layoutOffset;
      }
      final nodeExtent = parentData.visibleExtent;

      // Shift the hit coordinate by the node's current slide delta so a
      // tap lands on the visually-displaced child rather than on the
      // structural position nobody sees during a slide. Skip the read
      // when no slides are in flight.
      final slideDelta = hasSlides ? controller.getSlideDeltaNid(nid) : 0.0;
      final slideDeltaX = hasXSlides
          ? controller.getSlideDeltaXNid(nid)
          : 0.0;
      final localMainAxisPosition =
          mainAxisPosition + scrollOffset - nodeOffset - slideDelta;
      if (localMainAxisPosition < 0) continue;
      if (localMainAxisPosition >= nodeExtent) continue;

      final localCrossAxisPosition =
          crossAxisPosition - parentData.indent - slideDeltaX;
      if (localCrossAxisPosition < 0) continue;

      // Mirror paint's clip-and-translate trick. When a node is animating
      // and its visible extent is smaller than its intrinsic box, paint
      // draws the child shifted up by (height - extent) so the bottom slice
      // peeks through the clipped visible strip. Hit tests must apply the
      // same Y adjustment or taps on the visible slice would route to the
      // clipped-away top of the child box.
      final yAdjust =
          (controller.isAnimatingNid(nid) && nodeExtent < child.size.height)
          ? (child.size.height - nodeExtent)
          : 0.0;

      final paintedMainOffset = nodeOffset - scrollOffset + slideDelta;
      final paintedCrossOffset = parentData.indent + slideDeltaX;
      final hit = result.addWithAxisOffset(
        paintOffset: Offset(paintedCrossOffset, paintedMainOffset),
        mainAxisOffset: paintedMainOffset,
        crossAxisOffset: paintedCrossOffset,
        mainAxisPosition: mainAxisPosition,
        crossAxisPosition: crossAxisPosition,
        hitTest:
            (
              SliverHitTestResult result, {
              required double mainAxisPosition,
              required double crossAxisPosition,
            }) {
              return child.hitTest(
                BoxHitTestResult.wrap(result),
                position: Offset(crossAxisPosition, mainAxisPosition + yAdjust),
              );
            },
      );

      if (hit) return true;
    }

    return false;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TRANSFORM
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void applyPaintTransform(covariant RenderBox child, Matrix4 transform) {
    final parentData = child.parentData! as SliverTreeParentData;
    final nodeId = parentData.nodeId;

    // Resolve nid once and reuse it for sticky / animating / slide
    // checks below — three queries that all share the same key→nid hash.
    final nid = nodeId == null ? -1 : _controller.nidOf(nodeId as TKey);

    // Check if this child is a sticky header (O(1) lookup).
    if (nid >= 0) {
      final sticky = _sticky.infoForNid(nid);
      if (sticky != null) {
        transform.translateByDouble(sticky.indent, sticky.pinnedY, 0.0, 1.0);
        return;
      }
    }

    // Mirror paint's clip-and-translate trick. When a node is animating and
    // its visible extent is smaller than its intrinsic box, paint shifts the
    // child up by (height - extent) so the bottom slice peeks through the
    // clipped strip. The transform must include that same Y shift or callers
    // that resolve via applyPaintTransform (localToGlobal, layer composition,
    // showOnScreen, semantics) will be off by (height - extent) pixels.
    final yAdjust =
        (nid >= 0 &&
            controller.isAnimatingNid(nid) &&
            parentData.visibleExtent < child.size.height)
        ? (child.size.height - parentData.visibleExtent)
        : 0.0;

    // Include the node's current slide delta (paint-only FLIP offset) so
    // callers that resolve coordinates via applyPaintTransform — localToGlobal,
    // focus traversal, semantics, Scrollable.ensureVisible — track the
    // visually-displaced row during a slide. Skip the reads entirely when
    // no slides are in flight (idle-state fast path).
    final hasSlides = controller.hasActiveSlides;
    final hasXSlides = hasSlides && controller.hasActiveXSlides;
    final slideDelta =
        (hasSlides && nid >= 0) ? controller.getSlideDeltaNid(nid) : 0.0;
    final slideDeltaX =
        (hasXSlides && nid >= 0) ? controller.getSlideDeltaXNid(nid) : 0.0;

    final scrollOffset = constraints.scrollOffset;
    // Edge-ghost rows paint at `_edgeGhostBaseY + slideDelta`, not at
    // `parentData.layoutOffset + slideDelta`. Substitute the live edge
    // base so framework code (`localToGlobal`, semantics, focus
    // traversal) sees the row at its actual painted position. The live
    // base re-anchors to the current viewport edge under concurrent
    // scrolling. Settled-check: if the slide is settled but lazy-prune
    // hasn't run, fall back to the structural offset so post-settlement
    // queries report the row's real (off-screen) position.
    final edgeEntry = nodeId == null ? null : _phantomEdgeExits?[nodeId];
    final useGhost = edgeEntry != null
        && (slideDelta != 0.0 || slideDeltaX != 0.0);
    final base = useGhost
        ? _edgeGhostBaseY(edgeEntry, _currentViewportSnapshot())
        : parentData.layoutOffset;
    transform.translateByDouble(
      parentData.indent + slideDeltaX,
      base - scrollOffset - yAdjust + slideDelta,
      0.0,
      1.0,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CHILD POSITION QUERIES
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Required by Scrollable.ensureVisible / showOnScreen / RenderAbstractViewport
  // .getOffsetToReveal. The base RenderSliver implementation throws.

  @override
  double childMainAxisPosition(covariant RenderBox child) {
    final parentData = child.parentData! as SliverTreeParentData;
    final nodeId = parentData.nodeId;
    if (nodeId != null) {
      final sticky = _sticky.infoForNid(_controller.nidOf(nodeId as TKey));
      if (sticky != null) return sticky.pinnedY;
    }
    return parentData.layoutOffset - constraints.scrollOffset;
  }

  @override
  double childCrossAxisPosition(covariant RenderBox child) {
    return (child.parentData! as SliverTreeParentData).indent;
  }

  @override
  double? childScrollOffset(covariant RenderObject child) {
    return (child.parentData! as SliverTreeParentData).layoutOffset;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DEBUG
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty('controller', controller));
    properties.add(IntProperty('childCount', _children.length));
  }
}
