/// Render object for [SliverTree] that handles sliver layout and painting.
library;

import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '_layout_admission_policy.dart';
import '_slide_composer.dart';
import '_sticky_header_computer.dart';
import '_viewport_snapshot.dart';
import 'reorder_render_port.dart';
import 'sliver_tree_element.dart';
import 'tree_controller.dart';
import 'types.dart';

// `ViewportSnapshot` / `ViewportEdge` live in `_viewport_snapshot.dart`.
// Pending FLIP baselines and active edge ghosts are owned by
// `SlideComposer` (composed sub-objects `SlideBaselineSlot` and
// `GhostRegistry`) — see `_slide_composer.dart`. The render object
// here is purely the orchestrator.

/// Role of a phantom-anchored sliding row, selecting how
/// [RenderSliverTree._resolvePhantomAnchorBounds] computes its clip.
///
/// The clip helper is a chokepoint with two callers whose intent is
/// OPPOSITE, so the rule must branch on the role:
///
/// - [entry]: a previously-hidden node reparented INTO view that must
///   EMERGE past its anchor. A plain half-plane clip applies: the anchor
///   occludes the START of the trajectory, and as the row slides away the
///   half-plane reveals progressively more of it. There is NO header
///   repaint over this row, so the band/far-overhang rule MUST NOT reach
///   it.
/// - [exit]: a row purged from `visibleNodes` sliding INTO a collapsed
///   header to DISAPPEAR. The destination band is repainted on top by
///   Pass A.7 / Pass B, so the clip bounds the FAR overhang of a tall
///   card past the destination header's PAINTED band.
enum PhantomClipRole { entry, exit }

/// Consolidated per-ghost exit-phantom state.
///
/// - [anchor]: the visible destination row the ghost converges on (or,
///   for edge ghosts, the off-screen ancestor whose direction picked the
///   edge).
/// - [slidUp]: consume-time direction decision (`settledAnchorY <
///   baseline.y`) driving the direction-aware tuck and EXIT clip side.
/// - [edge]: live viewport edge for ghosts whose anchor was off-screen at
///   consume (painted at the edge, unclipped).
/// - [clipped]: whether the ghost carries the direction-aware EXIT clip
///   against its on-screen anchor's painted band.
///
/// `edge != null` XOR [clipped] — a ghost is either edge-painted and
/// unclipped, or anchor-painted and clipped. Holding both in one record
/// enforces that structurally instead of by cross-map convention.
class _ExitGhost<TKey> {
  _ExitGhost({
    required this.anchor,
    this.slidUp = false,
    this.edge,
    this.clipped = false,
  }) : assert(
         (edge != null) ^ clipped,
         "An exit ghost is either edge-painted (edge != null, unclipped) "
         "or anchor-painted (clipped, no edge)",
       );

  final TKey anchor;
  final bool slidUp;
  final ViewportEdge? edge;
  final bool clipped;
}

/// Render object for displaying a tree structure as a sliver.
///
/// Uses nodeId-based child storage for straightforward element management.
///
/// Implements [ReorderRenderPort] — the narrow surface
/// `TreeReorderController` binds to for drag-and-drop (row hit-testing,
/// eviction pinning, FLIP baseline staging, coordinate conversion).
class RenderSliverTree<TKey, TData> extends RenderSliver
    implements ReorderRenderPort<TKey> {
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
       _admission = LayoutAdmissionPolicy<TKey, TData>(controller: controller),
       _composer = SlideComposer<TKey, TData>(controller: controller) {
    // O(1) structural-offset resolver for the ghost registry: its call
    // sites run inside layout, where the per-frame offsets for
    // the relevant rows are fresh (bulk-aware via _structuralOffsetAt).
    // Controller-agnostic closure — survives controller swaps.
    //
    // Accepted staleness (2026-07-15 review): `normalizeForViewport` runs
    // early in performLayout, so the offsets it reads can be one
    // animation-tick stale versus the old prefix-summed live extents.
    // Only shifts the edge-ghost re-promotion threshold by ≤1 frame —
    // cosmetic, inherent to the O(1) design; the exact O(index) fallback
    // remains for unwired registries.
    _composer.ghosts.structuralYOf = _structuralOffsetAt;
  }

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
    _composer.reset();
    // Phantom-exit ghost state is also keyed by old-controller TKey.
    // String-key reuse across controllers (a common app pattern) would
    // otherwise feed garbage entries to the new controller's layout.
    _phantomExitGhosts = null;
    _phantomClipAnchors = null;
    _composer.rebindController(value);
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
    // The out-of-layout findRowAtPaintedY scratch is keyed by the old
    // controller's structureGeneration; invalidate so a post-swap
    // pointer poll re-materializes against the new controller.
    _findFirstScratchCumulative = null;
    _findFirstScratchGen = -1;
    _findFirstScratchCount = 0;
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

  /// Count of visible nodes from last layout — used to detect structure
  /// changes.
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

  /// One-shot cumulative offset buffer used by `_findFirstVisibleIndex`
  /// when called outside layout after a bulk-only frame, where
  /// `_nodeOffsetsByNid` is fresh only for the cache region. Cached
  /// across calls keyed by `(structureGeneration, !hasActiveAnimations)`:
  /// while animations are in flight, extents tick every frame but
  /// `structureGeneration` doesn't, so the cache must be re-materialized
  /// each call instead of trusting an animation-frame snapshot.
  Float64List? _findFirstScratchCumulative;
  int _findFirstScratchGen = -1;
  int _findFirstScratchCount = 0;

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

  /// Structural offset of visible index [i] (with `nid == orderNids[i]`),
  /// readable on ANY frame: under the bulk-only fast path the per-nid
  /// offset slots are stale for off-cache nids, so derive from the
  /// position-indexed cumulatives instead. Used by the bounded paint /
  /// hit-test iteration, which needs a monotonic offset for its break
  /// condition.
  double _structuralOffsetAt(int i, int nid) {
    return _bulkCumulativesValid
        ? _offsetAtVisibleIndex(i)
        : _nodeOffsetsByNid[nid];
  }

  /// Admits cache-region members under the bulk-only fast path.
  ///
  /// Invoked from Pass 2 when [_bulkCumulativesValid] is true. Pulls per-row
  /// offset/extent from the precomputed cumulatives and syncs them into the
  /// per-nid slots so downstream code (Pass 2 measurement, paint extent,
  /// paint, hit-test) reads correct values without a branch per access.
  /// Anchors the admission band to full-space (`fullCacheEnd`) so a low
  /// bulk progress value doesn't admit thousands of sub-pixel rows on
  /// frame 1 of `expandAll`.
  ///
  /// The caller owns the outer-loop dispatch; this method performs the
  /// per-row writes and sparse-track buffer maintenance for the admitted
  /// range.
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
  /// last layout. Reset at the top of `performLayout`. The loop iterates
  /// `_children.keys` exactly once, so this counter is bounded by
  /// `_children.length` — verified by
  /// `test/sliver_tree/parent_data_refresh_iteration_test.dart`.
  /// Diagnostic only; no runtime invariant is enforced by this field.
  @visibleForTesting
  int debugLastParentDataRefreshIterationCount = 0;

  /// Number of O(N_visible) structural-cumulative builds performed by the
  /// off-cache parentData refresh during the last layout. Zero on the
  /// common scroll frame (every mounted child in-cache); at most one per
  /// layout otherwise. Reset alongside
  /// [debugLastParentDataRefreshIterationCount].
  int debugLastParentDataCumulativeBuilds = 0;

  /// Main-loop iterations of the last paint's Pass A. Bounded by the
  /// viewport-intersecting index range (± slide overreach), NOT by the
  /// total visible count — below-viewport rows must not pay a per-frame
  /// sticky check + hash probe each.
  int debugLastPaintIterationCount = 0;

  /// Phase-2 loop iterations of the last [hitTestChildren] call. Same
  /// bound as [debugLastPaintIterationCount], per pointer event.
  int debugLastHitTestIterationCount = 0;

  /// In-flow loop iterations of the last [visitChildrenForSemantics]
  /// call. Bounded by the mounted-children count, not the visible count.
  int debugLastSemanticsIterationCount = 0;

  /// Lifetime count of [performLayout] invocations. Perf oracle for
  /// slide-only paint routing: a pure FLIP slide must lay out only on its
  /// install and settle frames.
  int debugPerformLayoutCount = 0;

  /// Number of live entries in `_phantomExitGhosts`. Exposed for tests
  /// that verify phantom-exit cleanup (paint purity, controller swap,
  /// per-layout pruning). Zero when the map is null.
  @visibleForTesting
  int get debugPhantomExitGhostCount =>
      _phantomExitGhosts == null ? 0 : _phantomExitGhosts!.length;

  /// Number of live entries in the slide composer's ghost registry.
  /// Forwarded for tests that verify ghost-registry pruning behavior.
  @visibleForTesting
  int get debugComposerGhostCount =>
      // ignore: invalid_use_of_visible_for_testing_member
      _composer.debugGhostEntryCount;

  /// Number of mounted child RenderBoxes in `_children`. Used by
  /// `parent_data_refresh_iteration_test.dart` to assert
  /// [debugLastParentDataRefreshIterationCount] stays bounded by this
  /// count.
  @visibleForTesting
  int get debugChildCount => _children.length;

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

  /// Slide-pipeline composer: owns the pending FLIP baseline slot and
  /// the active edge-ghost registry. Render holds the facade and reads
  /// ghost paint bases through it via [GhostBaseResolver]. See
  /// `_slide_composer.dart`.
  final SlideComposer<TKey, TData> _composer;

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
  ///
  /// ENTRY-phantom entries only: a re-promoted exit ghost's clip MIGRATES
  /// into this map when Step 0a drops its ghost record (the emerging row
  /// keeps its clip until its slide settles); exit ghosts otherwise carry
  /// their clip inside [_phantomExitGhosts]' consolidated records.
  Map<TKey, TKey>? _phantomClipAnchors;

  /// Consolidated exit-ghost state — one [_ExitGhost] record per hidden
  /// ghost row, so the anchor, direction flag, edge and clip flag can
  /// never fall out of lockstep, and the `edge != null` XOR `clipped`
  /// mutex is asserted in the record's constructor.
  ///
  /// Tracks rows that were visible at staging time but are now hidden
  /// (reparented under a collapsed parent). Each such "ghost" row needs:
  ///   1. Its render box retained past the visible-order purge
  ///      ([isNodeRetained]).
  ///   2. A separate paint pass (Pass A.5) — the standard pass iterates
  ///      visibleNodes, which excludes ghosts. An anchor-clipped ghost
  ///      paints at the anchor's settled top (minus the direction-aware
  ///      tuck) + its own slide delta; an edge ghost paints at the LIVE
  ///      viewport edge (Pass A.6's model).
  ///   3. For on-screen anchors, a direction-aware EXIT clip
  ///      ([_ExitGhost.clipped]) so the row visually disappears INTO the
  ///      destination header; edge ghosts have no on-screen band to clip
  ///      against.
  ///
  /// Written ONCE at consume (single-writer), reaped by Step 0a
  /// ([_pruneSettledPhantomExitGhosts]) under the dual settle criterion
  /// (ghost AND anchor at rest), on key free, and on re-promotion to
  /// visibility.
  Map<TKey, _ExitGhost<TKey>>? _phantomExitGhosts;

  /// Debug-only, paint-time-only capture of each EXIT phantom ghost's
  /// painted geometry, the oracle for the far-overhang occlusion tests.
  /// Records, per ghost key:
  ///  - `ghostRect`: the ghost's painted rect in sliver PAINT space (NOT
  ///    offset by the paint `offset`, so a test can compare it directly
  ///    against `anchorBand`).
  ///  - `clipRect`: the EXIT clip rect the render pushed this frame
  ///    (sliver paint space), or null when no clip was applied.
  ///  - `anchorBand`: the destination header's PAINTED band this frame.
  ///
  /// LIFETIME CONTRACT: cleared at the top of every `paint()` and
  /// written ONLY for a ghost that is ACTIVELY SLIDING this
  /// frame (Pass A.5 `continue`s a settled ghost before the write). It is
  /// therefore EMPTY on any frame with no sliding ghost — including the
  /// settle frame, after `_pruneSettledPhantomExitGhosts` reaps the
  /// ghost. A test MUST `containsKey`-guard every read and MUST NOT
  /// non-null-deref a key on the settle frame (it would throw). Never
  /// read by production code; cannot perturb layout, distance, or
  /// hit-testing.
  @visibleForTesting
  final Map<TKey, ({Rect ghostRect, Rect? clipRect, Rect anchorBand})>
      debugLastPhantomGhostPaint = {};

  // Edge-ghost storage and lifecycle now live in `_composer.ghosts`
  // (`GhostRegistry`). Render-side reads go through `_composer.baseFor`
  // or `_composer.ghosts.entryFor` / `_composer.hasGhosts`; writes go
  // through the registry's lifecycle methods called from the consume
  // path and the pre-Pass-1 scroll-changed branch.

  /// Last-observed `constraints.scrollOffset`, captured at the end of
  /// every `performLayout`. Drives the pre-Pass-1 scroll-changed branch,
  /// which detects scroll movement between layouts (mutation-less
  /// re-paints) so active edge ghosts can be re-promoted when the user
  /// scrolls toward their structural destination during the slide.
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
  @override
  void beginSlideBaseline({
    required Duration duration,
    required Curve curve,
    Map<TKey, double>? baselineYOverrides,
  }) {
    // Not-laid-out guard: snapshotVisibleOffsets walks visible rows
    // accumulating extents from controller state. Before first layout,
    // those extents fall through to defaultExtent and the snapshot is
    // fictitious. Silently no-op rather than stage a garbage baseline.
    if (geometry == null) return;
    final offsets = snapshotVisibleOffsets();
    // Per-key y overrides (proxy drop-settle): the consume path installs
    // the FLIP from these positions instead of the painted ones. Only
    // keys already in the snapshot participate — an absent key has no
    // "current" to diff against.
    if (baselineYOverrides != null) {
      for (final entry in baselineYOverrides.entries) {
        final existing = offsets[entry.key];
        if (existing != null) {
          offsets[entry.key] = (y: entry.value, x: existing.x);
        }
      }
    }
    // First-wins is enforced by SlideBaselineSlot.stage's bool return.
    final staged = _composer.baselineSlot.stage(
      offsets: offsets,
      viewport: _currentViewportSnapshot(),
      duration: duration,
      curve: curve,
    );
    if (staged) {
      _scheduleBaselineExpiry(_composer.baselineSlot.pendingStamp);
    }
  }

  /// Whether a FLIP baseline is currently staged and unconsumed. Debug
  /// surface for tests pinning the baseline expiry backstop.
  bool get debugSlideBaselineStaged => _composer.baselineSlot.isStaged;

  /// Backstop for the stage-without-mutation protocol violation.
  ///
  /// The caller contract says every successful stage is followed by a
  /// layout-triggering mutation in the same frame (or via a microtask
  /// before the next frame). In every compliant flow, the next frame's
  /// layout consumes the baseline BEFORE post-frame callbacks run — so a
  /// baseline still pending at post-frame time was abandoned, and under
  /// first-wins staging it would silently block every subsequent slide
  /// stage until an unrelated layout flushed it. Discard it (all build
  /// modes) and report loudly (debug builds only). The stamp keys the
  /// discard to exactly this stage: consume / reset (controller swap) /
  /// re-stage all invalidate it.
  void _scheduleBaselineExpiry(int stamp) {
    // ensureVisualUpdate: addPostFrameCallback does NOT schedule a frame,
    // and the violation case by definition schedules none itself — the
    // check would otherwise wait for an arbitrarily-later frame. In the
    // compliant flow the same-frame mutation already scheduled one, so
    // this is a no-op there.
    SchedulerBinding.instance.ensureVisualUpdate();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_composer.baselineSlot.discardIfStale(stamp)) {
        return;
      }
      assert(() {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: FlutterError(
              "A FLIP slide baseline was staged via beginSlideBaseline but "
              "no structural mutation followed in the same frame, so no "
              "layout pass consumed it. The stale baseline has been "
              "discarded (it would otherwise block every subsequent slide "
              "stage — first-wins). Fix the caller: every successful stage "
              "must be followed by a layout-triggering mutation.",
            ),
            library: "widgets_extended",
            context: ErrorDescription(
              "during the slide-baseline staging protocol check",
            ),
          ),
        );
        return true;
      }());
    });
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
    required ViewportSnapshot currentViewport,
  }) {
    final pending = _composer.baselineSlot.consume();
    if (pending == null) return;
    final baseline = pending.offsets;
    final captureViewport = pending.viewport;
    final duration = pending.duration;
    final curve = pending.curve;
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
    //
    // Only ENTRY-phantom entries live here: exit ghosts carry their clip
    // inside their consolidated [_ExitGhost] record, whose lifecycle
    // Step 0a owns under the dual settle criterion. That makes the
    // adjacent-ghost hazard — own-slide pruning stripping a
    // still-absorbing ghost's EXIT clip — structurally impossible. The
    // own-slide
    // criterion below is correct for entry phantoms.
    _phantomClipAnchors?.removeWhere((key, _) {
      final nid = _controller.nidOf(key);
      if (nid < 0) return true; // key gone entirely
      return _controller.getSlideDeltaNid(nid) == 0.0 &&
          _controller.getSlideDeltaXNid(nid) == 0.0;
    });
    if (_phantomClipAnchors?.isEmpty ?? false) _phantomClipAnchors = null;

    // Mirror the lazy-prune for edge ghosts: remove entries whose slide
    // has settled or whose key has been freed.
    _composer.ghosts.pruneSettled();

    // Rewrite ghost entries in baseline to use the CURRENT viewport's
    // edge base — the prerequisite that makes the "snapshot uses live
    // base" rule compose correctly under scroll change. Without this
    // rewrite, a stays-same edge ghost whose viewport scrolled by Δ
    // between staging and consume would feed `rawDeltaY = -Δ` into the
    // engine, visibly drifting the slide instead of leaving it alone.
    //
    // Direction-flip and re-promotion still produce non-zero deltas
    // because they explicitly write DIFFERENT edge bases for prior vs
    // current.
    if (_composer.hasGhosts) {
      for (final ghostKey in _composer.ghosts.activeKeys.toList()) {
        if (!baseline.containsKey(ghostKey)) continue;
        final ghostBase = _composer.baseFor(ghostKey, currentViewport);
        if (ghostBase == null) continue;
        final ghostNid = controller.nidOf(ghostKey);
        if (ghostNid < 0) continue;
        final ghostSlideY = controller.getSlideDeltaNid(ghostNid);
        final ghostSlideX = controller.getSlideDeltaXNid(ghostNid);
        final ghostIndent = controller.getIndent(ghostKey);
        baseline[ghostKey] = (
          y: ghostBase + ghostSlideY,
          x: ghostIndent + ghostSlideX,
        );
      }
    }

    // Viewport discipline for the rest of this method: capture-time
    // visibility checks use captureViewport, current-time checks use
    // currentViewport, and new edge anchors created in this consume use
    // currentViewport. All viewport math routes through the snapshot's
    // helper methods rather than ad-hoc top/bottom/overhang scalars.

    // Augment baseline with phantom priors for keys that were hidden at
    // moveNode time but became visible after mutation. The controller
    // staged a key→anchor relationship for each such key during
    // moveNode(animate: true); resolve them to scroll-space positions
    // here using the just-staged baseline (anchor's painted position
    // at STAGING time) or the staging-time viewport edge (anchor was
    // off-screen at staging).
    //
    // This is a CAPTURE-TIME question — "where was the anchor at
    // staging?" — so the visibility check and the edge fallback both use
    // `captureViewport`, not `currentViewport`.
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
        // formula reduces to the plain structural base.
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
    // Resolve the exit-anchor slide DESTINATION against the
    // SETTLED snapshot (full-extent prefix-sum) rather than the
    // current/animated snapshot. When the source section empties to an
    // *entering* placeholder (extent 0 → full), the current-extent prefix-sum
    // under-counts the anchor's y and the exit slide degenerates to ~0; the
    // settled snapshot gives the anchor's post-settle y so the row slides the
    // full FLIP distance. Computed once and shared by the controller-staged
    // exit-phantom block below and the render-side vanish fallback. Only the
    // on-screen-anchor branches consult it; off-screen branches still slide
    // toward the live viewport edge (settled vs current extent does not change
    // which viewport edge an off-screen anchor maps to).
    final settled = snapshotSettledVisibleOffsets();
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
          // Inject destination = anchor's SETTLED painted position + ghost
          // row's own slideDelta. The settled y is where the anchor lands
          // once in-flight extent animations (e.g. an entering placeholder
          // above it) complete — the correct FLIP "after". Fall back to the
          // current/animated y if the anchor is somehow absent from the
          // settled walk (defensive; should not happen for a visible anchor).
          // Indent (x) is already settled in `anchorCurrent`, so keep it.
          //
          // STRUCTURAL-ONLY (load-bearing): this consume-time destination
          // MUST NOT read `_sticky.infoForNid` / `pinnedY`. The sticky set
          // is recomputed by `computeStickyHeaders` later in the frame,
          // during `paint()`, so `_sticky` is STALE here (prior frame's
          // value, or null
          // on the FIRST reparent frame — exactly when the destination set
          // just changed). Injecting a pinned y here would either corrupt
          // the slide DISTANCE or read garbage. The sticky-pinned
          // convergence is applied at PAINT time via
          // `_anchorPaintedBounds` (Pass A.5 ghost paint + EXIT clip +
          // Pass A.7), never here.
          final settledAnchorY = settled[anchorKey]?.y ?? anchorCurrent.y;
          // Direction-aware tuck. The card
          // slides toward a SMALLER y (from below) ⇒ UPWARD / body-side
          // approach ⇒ a card TALLER than the collapsed destination header
          // gets an extra `tuck` so its BOTTOM reaches the band BOTTOM (no
          // last-frame pop). `baseline[key]` is non-null here: the loop
          // `continue`s above if `!baseline.containsKey(key)`. The same
          // `_exitTuckFor` magnitude is subtracted at the Pass A.5 paint
          // anchor so the two convergence sites cannot diverge (no t=0
          // jump). DOWNWARD / equal-height ⇒ tuck 0 ⇒ distance unchanged.
          final slidUp = settledAnchorY < baseline[key]!.y;
          final tuck = _exitTuckFor(
            ghostNid: ghostNid,
            anchorKey: anchorKey,
            slidUp: slidUp,
          );
          current[key] = (
            y: settledAnchorY - tuck + ghostSlideY,
            x: anchorCurrent.x + ghostSlideX,
          );
          // Single consolidated record: anchor + persisted direction
          // decision (so the paint pass — which has no baseline —
          // reproduces it exactly) + the direction-aware EXIT clip flag
          // so the anchor occludes the ghost as it slides in.
          (_phantomExitGhosts ??= <TKey, _ExitGhost<TKey>>{})[key] =
              _ExitGhost<TKey>(
                anchor: anchorKey,
                slidUp: slidUp,
                clipped: true,
              );
        } else {
          // Anchor off-screen at consume: ghost slides toward the
          // current viewport edge (with overhang) nearest the anchor's
          // structural position. No clip — the ghost simply slides
          // off-screen and disappears. The consume-time EDGE enum is
          // persisted (single-writer) so the Pass A.5 EDGE-FALLBACK can
          // paint the ghost at the LIVE edge when the off-screen anchor
          // is unmounted.
          final edge = currentViewport.edgeFor(anchorCurrent.y);
          final edgeY = currentViewport.baseForEdge(edge);
          current[key] = (
            y: edgeY + ghostSlideY,
            x: anchorCurrent.x + ghostSlideX,
          );
          (_phantomExitGhosts ??= <TKey, _ExitGhost<TKey>>{})[key] =
              _ExitGhost<TKey>(anchor: anchorKey, edge: edge);
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
        // Render-side fallback half: same settled-destination
        // substitution as the controller-staged exit-phantom block above —
        // slide toward the anchor's settled y, not its current/animated y.
        //
        // STRUCTURAL-ONLY (same contract as the controller-staged branch
        // above): do NOT read `_sticky` here — it is stale at consume time
        // (before `computeStickyHeaders`). Sticky-pinned convergence is a
        // PAINT-time re-base via `_anchorPaintedBounds`.
        final settledCursorY = settled[cursor]?.y ?? anchorCurrent.y;
        // Direction-aware tuck — same shared helper, same
        // consume/paint-must-agree discipline as the controller-staged
        // branch above, here using `cursor` (the deepest visible new
        // ancestor) as the anchor.
        // `baseline[key]` is guaranteed present: the loop walks
        // `baseline.keys`.
        final slidUp = settledCursorY < baseline[key]!.y;
        final tuck = _exitTuckFor(
          ghostNid: ghostNid,
          anchorKey: cursor,
          slidUp: slidUp,
        );
        current[key] = (
          y: settledCursorY - tuck + ghostSlideY,
          x: anchorCurrent.x + ghostSlideX,
        );
        (_phantomExitGhosts ??= <TKey, _ExitGhost<TKey>>{})[key] =
            _ExitGhost<TKey>(anchor: cursor, slidUp: slidUp, clipped: true);
      } else {
        final edge = currentViewport.edgeFor(anchorCurrent.y);
        final edgeY = currentViewport.baseForEdge(edge);
        current[key] = (
          y: edgeY + ghostSlideY,
          x: anchorCurrent.x + ghostSlideX,
        );
        // Consume-time edge persisted (single-writer) for the Pass A.5
        // EDGE-FALLBACK — same rationale as the controller-staged branch.
        (_phantomExitGhosts ??= <TKey, _ExitGhost<TKey>>{})[key] =
            _ExitGhost<TKey>(anchor: cursor, edge: edge);
      }
    }

    // Ghosts that became visible again are pruned by Step 0a
    // (_pruneSettledPhantomExitGhosts) at the start of EVERY layout —
    // including this one, which ran before this consume — so no
    // re-visible entries can exist here: this cycle's injection loop
    // above only adds entries for keys that are hidden post-mutation.
    // Step 0a is the single owner — pruning here as well would leave
    // non-staging mutations (which never consume) painting re-promoted
    // ghosts twice.

    // Step 3b: a row that was an edge ghost in the previous cycle has
    // now become an exit-phantom (anchor-based) ghost via the phantom
    // injection above (mutation moved it under a hidden parent).
    // Drop the edge-ghost entry — the exit-phantom mechanism takes over
    // paint and composition. No preserve-flag clear needed (set-only
    // semantics; engine resets via composition path).
    final exitGhostKeys = _phantomExitGhosts?.keys;
    if (exitGhostKeys != null) {
      _composer.ghosts.dropForKeysThatBecameAnchorGhosts(exitGhostKeys);
    }

    // Steps 4-6: re-evaluate active edge ghosts (re-promote / direction
    // flip / stays-same), apply slide-IN clamp + new ghost installs for
    // non-ghost keys, then remove ghost-stays-same-edge from the batch
    // so the engine doesn't re-baseline them.
    final ghostKeysTouchedThisCycle = <TKey>{};
    _composer.ghosts.reEvaluateGhostStatus(
      baseline: baseline,
      current: current,
      viewport: currentViewport,
      duration: duration,
      curve: curve,
      ghostKeysTouchedThisCycle: ghostKeysTouchedThisCycle,
    );
    _composer.ghosts.applyClampAndInstallNewGhosts(
      baseline: baseline,
      current: current,
      viewport: currentViewport,
      duration: duration,
      curve: curve,
      ghostKeysTouchedThisCycle: ghostKeysTouchedThisCycle,
    );
    _composer.ghosts.removeStaysFromBatch(
      baseline: baseline,
      current: current,
      ghostKeysTouchedThisCycle: ghostKeysTouchedThisCycle,
    );

    // Snapshot the keys that the engine batch is about to touch — we
    // need this for Step 8 below (mark all of them with preserve so
    // subsequent batches don't restart their progress clocks).
    final batchedKeys = <TKey>[];
    for (final key in baseline.keys) {
      if (current.containsKey(key)) batchedKeys.add(key);
    }

    // Step 7: hand to engine. No maxSlideDistance — the render-side
    // clamp/ghost mechanism already bounds each row's delta to
    // viewport + overhang. Direct callers of
    // controller.animateSlideFromOffsets may still pass one explicitly.
    controller.animateSlideFromOffsets(
      baseline,
      current,
      duration: duration,
      curve: curve,
    );

    // Step 7b: re-prune the edge-ghost registry after the engine call.
    //
    // The engine's composition path (`_slide_animation_engine.dart`,
    // composition branch with `composedY == 0.0 && composedX == 0.0`)
    // CLEARS the slide entry without notifying the render layer. If
    // this row was kept in the ghost registry by `reEvaluateGhostStatus`'s
    // direction-flip branch (or by stays-same), the entry survives the
    // engine clear. The next paint then takes a broken path:
    //
    //   * Standard pass A skips the row because
    //     the ghost registry has an entry for `nodeId`.
    //   * Edge-ghost paint pass A.6 sees `getSlideDeltaNid == 0` and
    //     prunes the entry instead of painting (lazy-prune of settled
    //     ghosts).
    //
    // Net effect: the row is invisible for one paint while its
    // structural slot in the viewport sits empty. The user sees a gap
    // that only resolves on the NEXT layout (e.g. a scroll), where the
    // map no longer has the entry and standard paint runs normally.
    //
    // The repeated prune here drops any entry the engine just cleared,
    // so standard paint A can render the row at its (already-up-to-date
    // by Pass 2 measurement) `parentData.layoutOffset`.
    _composer.ghosts.pruneSettled();

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
      _composer.ghosts.clearAll();
    }
  }

  // Edge-ghost lifecycle (prune, re-evaluate, re-promote, direction-
  // flip, install, normalize) lives in `GhostRegistry`
  // (`_ghost_registry.dart`). Render calls into `_composer.ghosts.X`
  // from the consume path and the pre-Pass-1 scroll-changed branch.

  double _currentExtentOfKey(TKey key) {
    final nid = controller.nidOf(key);
    return nid >= 0 ? controller.getCurrentExtentNid(nid) : 0.0;
  }

  /// Builds a [ViewportSnapshot] describing the layout's current
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
  ViewportSnapshot _currentViewportSnapshot() {
    final paintExtent = constraints.viewportMainAxisExtent;
    return ViewportSnapshot(
      scrollOffset: constraints.scrollOffset,
      paintExtent: paintExtent,
      overhangPx: paintExtent * controller.slideClampOverhangViewports,
    );
  }

  // Edge-ghost prune, install, re-evaluate, re-promote, direction-flip,
  // batch removal, viewport normalization, and live-base resolution all
  // live in `GhostRegistry` (see `_ghost_registry.dart`). Render-side
  // calls go through `_composer.ghosts.*` and `_composer.baseFor`.

  /// Step 8: ensure preserve-progress flag set for all active edge
  /// ghosts AND existing exit-phantom anchor ghosts. Set-only-true —
  /// the engine clears the flag implicitly when the slide entry is
  /// destroyed (settles, cancelled, replaced via composition).
  void _syncPreserveProgressFlags() {
    _composer.ghosts.syncPreserveProgressFlags();
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

  /// Nodes explicitly pinned against stale eviction, regardless of cache
  /// region or animation state. Deliberately generic (not "the dragged
  /// key"): the render object stays ignorant of drag semantics and the
  /// set is reusable for any future retention need. Currently pinned by
  /// [TreeReorderController] for the lifetime of a drag session — the drag
  /// gesture lives on the dragged row's own GestureDetector, so evicting
  /// that row would orphan the session (its end/cancel callbacks could
  /// never fire).
  final Set<TKey> _pinnedNodes = <TKey>{};

  /// Pins [id] against stale eviction until [unpinNode]. Idempotent.
  @override
  void pinNode(TKey id) {
    _pinnedNodes.add(id);
  }

  /// Removes the eviction pin for [id]. Idempotent.
  @override
  void unpinNode(TKey id) {
    _pinnedNodes.remove(id);
  }

  // ──────── ReorderRenderPort surface (remaining members) ────────
  //
  // findRowAtPaintedY / pinNode / unpinNode / beginSlideBaseline are the
  // pre-existing methods above; these three exist so the reorder
  // controller never reads `geometry`/`constraints` (render protocol)
  // directly.

  @override
  bool get isLaidOut {
    return geometry != null;
  }

  @override
  double get precedingScrollExtent {
    // `constraints` is only readable once layout has begun; before the
    // first layout there is no preceding extent to speak of.
    if (geometry == null) {
      return 0.0;
    }
    return constraints.precedingScrollExtent;
  }

  @override
  bool drivesController(Object treeController) {
    return identical(_controller, treeController);
  }

  /// Whether the given node is retained by the current layout — i.e. it is
  /// explicitly pinned, in the cache region, a sticky header, or a
  /// phantom-exit ghost mid-slide. Used by the element to decide whether
  /// an off-screen child can be evicted. O(1) (Map containsKey + Set
  /// lookup), no allocation.
  bool isNodeRetained(TKey id) {
    if (_pinnedNodes.contains(id)) return true;
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
    if (_composer.ghosts.entryFor(id) != null) return true;
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
    final hasEdgeGhosts = _composer.hasGhosts;
    // Build the viewport snapshot lazily — only needed if there are
    // active edge ghosts. Ghost rows paint at the LIVE viewport edge,
    // so snapshot must derive their painted Y from the current viewport,
    // not a frozen capture.
    final ViewportSnapshot? viewportForGhosts =
        hasEdgeGhosts ? _currentViewportSnapshot() : null;
    for (int i = 0; i < visible.length; i++) {
      final nid = orderNids[i];
      final key = visible[i];
      final slideY = hasSlides ? controller.getSlideDeltaNid(nid) : 0.0;
      final slideX = hasXSlides ? controller.getSlideDeltaXNid(nid) : 0.0;
      final indent = controller.getIndent(key);
      // Edge-ghost rows paint at `liveBaseY + slideDelta`, not at
      // `structural + slideDelta`. Override to keep snapshot consistent
      // with what the edge-ghost paint pass actually paints — required
      // for composition correctness when a ghost row gets re-mutated
      // mid-slide.
      if (hasEdgeGhosts) {
        final entry = _composer.ghosts.entryFor(key);
        if (entry != null) {
          result[key] = (
            y: viewportForGhosts!.baseForEdge(entry.edge) + slideY,
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
    // Painted position of a ghost = the SHARED Pass A.5 base
    // ([_exitGhostPaintedBaseScrollSpace]: settled anchor top minus the
    // direction-aware tuck, or the live viewport edge for edge-anchored
    // ghosts) + the ghost's own slideDelta. Using the anchor's LIVE
    // painted position here instead would disagree with what Pass A.5
    // actually paints by `anchorSlideDelta + tuck` — a visible snap of
    // exactly that many pixels on re-move.
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
        final base = _exitGhostPaintedBaseScrollSpace(
          ghostKey: ghostKey,
          ghost: entry.value,
        );
        if (base == null) continue; // unpaintable this frame
        final ghostNid = controller.nidOf(ghostKey);
        final ghostSlideY =
            hasSlides ? controller.getSlideDeltaNid(ghostNid) : 0.0;
        final ghostSlideX =
            hasXSlides ? controller.getSlideDeltaXNid(ghostNid) : 0.0;
        result[ghostKey] = (
          y: base.y + ghostSlideY,
          x: base.x + ghostSlideX,
        );
      }
    }
    return result;
  }

  /// Scroll-space base position (y BEFORE adding the ghost's own slide
  /// delta, x BEFORE adding the ghost's own X slide delta) that Pass A.5
  /// paints exit ghost [ghostKey] at. Single source of truth for the
  /// paint pass AND for [snapshotVisibleOffsets]'s ghost augmentation: a
  /// ghost re-moved mid-slide stages its next baseline from the snapshot,
  /// so any disagreement between the two formulas becomes a visible t=0
  /// snap of exactly that many pixels.
  ///
  /// Two branches, mirroring Pass A.5's structure:
  /// - Anchor mounted: the anchor's **settled** top (sticky `pinnedY` +
  ///   scrollOffset when pinned, else `layoutOffset` WITHOUT the anchor's
  ///   own slide — see the settled-top commentary in Pass A.5) minus the
  ///   direction-aware tuck; x is the anchor's live painted indent.
  /// - Anchor unmounted with a persisted [ViewportEdge] on its
  ///   [_ExitGhost] record: the LIVE viewport edge base (mirroring the
  ///   paint fallback); x is the ghost's own indent.
  ///
  /// Returns null when the ghost cannot be painted this frame (freed key,
  /// truly orphaned anchor) — callers skip the entry.
  ({double y, double x})? _exitGhostPaintedBaseScrollSpace({
    required TKey ghostKey,
    required _ExitGhost<TKey> ghost,
    ViewportSnapshot? viewport,
  }) {
    final ghostNid = controller.nidOf(ghostKey);
    if (ghostNid < 0) return null;
    final anchorKey = ghost.anchor;
    final anchorChild = getChildForNode(anchorKey);
    if (anchorChild == null) {
      final edge = ghost.edge;
      if (edge == null) return null;
      // Callers iterating many ghosts pass a hoisted [viewport] so this
      // branch does not construct a snapshot per ghost.
      return (
        y: (viewport ?? _currentViewportSnapshot()).baseForEdge(edge),
        x: controller.getIndent(ghostKey),
      );
    }
    final anchorParentData = anchorChild.parentData;
    if (anchorParentData is! SliverTreeParentData) return null;
    final anchorNid = controller.nidOf(anchorKey);
    final anchorPinnedInfo = anchorNid >= 0
        ? _sticky.infoForNid(anchorNid)
        : null;
    // pinnedY is paint-space (viewport-relative); convert back to
    // scroll-space so both consumers can subtract their own frame's
    // scrollOffset (paint) or use the value directly (snapshot).
    final double settledTopScrollSpace = anchorPinnedInfo != null
        ? anchorPinnedInfo.pinnedY + constraints.scrollOffset
        : anchorParentData.layoutOffset;
    final tuck = _exitTuckFor(
      ghostNid: ghostNid,
      anchorKey: anchorKey,
      slidUp: ghost.slidUp,
    );
    final anchorSlideX = (controller.hasActiveXSlides && anchorNid >= 0)
        ? controller.getSlideDeltaXNid(anchorNid)
        : 0.0;
    return (
      y: settledTopScrollSpace - tuck,
      x: anchorParentData.indent + anchorSlideX,
    );
  }

  /// Internal contract — exit-anchor destination resolution only.
  ///
  /// Returns the **settled** ("FLIP after") y/x for every currently visible
  /// row: the prefix-sum of each row's FULL extent
  /// ([TreeController.getEstimatedExtentNid]) rather than its current/animated
  /// extent ([TreeController.getCurrentExtentNid]). Unlike
  /// [snapshotVisibleOffsets] this is NOT a painted position — it deliberately
  /// OMITS slide deltas and edge-ghost overrides, because its only consumer is
  /// the exit-phantom destination injection in [_consumeSlideBaselineIfAny],
  /// which needs the position the anchor *will* land at once all in-flight
  /// extent animations settle.
  ///
  /// Why full extents: when a sibling row above the anchor is mid-enter (e.g.
  /// an empty-state placeholder growing extent `0 → full`), the current-extent
  /// prefix-sum under-counts the anchor's destination, collapsing the exit
  /// slide distance to `~0`. The settled prefix-sum is stable against that
  /// transient and yields the correct FLIP "after" target.
  ///
  /// Walks [TreeController.visibleNodes] / [TreeController.orderNidsView] in
  /// the same index-aligned order as [snapshotVisibleOffsets] (including
  /// pending-deletion rows, which contribute their full extent), so the two
  /// snapshots stay key-consistent. Does NOT augment with exit-ghost rows —
  /// the anchor we read is always a visible row by construction of the
  /// exit-phantom path. Pure read; writes nothing. O(N_visible).
  Map<TKey, ({double y, double x})> snapshotSettledVisibleOffsets() {
    assert(
      geometry != null,
      "snapshotSettledVisibleOffsets called before first layout",
    );
    final result = <TKey, ({double y, double x})>{};
    double structural = 0.0;
    final visible = controller.visibleNodes;
    final orderNids = controller.orderNidsView;
    for (int i = 0; i < visible.length; i++) {
      final nid = orderNids[i];
      final key = visible[i];
      result[key] = (y: structural, x: controller.getIndent(key));
      structural += controller.getEstimatedExtentNid(nid);
    }
    return result;
  }

  /// Debug-only: rows examined by the last [findRowAtPaintedY] call
  /// (bounded-scan phases 1–3, the full-scan loop length, or the fast
  /// path's forward/backward walk). Pins the bounded path's O(window)
  /// contract against routing re-widening.
  int debugLastFindRowIterationCount = 0;

  /// Debug-only: whether the last [findRowAtPaintedY] call with active
  /// composed deltas took the exact full-scan fallback (true) or the
  /// bounded window scan (false). Untouched by no-delta fast-path calls.
  bool debugLastFindRowUsedFullScan = false;

  /// Finds the first live (non-pending-deletion) visible row whose painted
  /// scroll-space range `[paintedOffset, paintedOffset + extent)` contains
  /// [scrollY], falling back to the last live row when [scrollY] sits past
  /// the bottom of the tree. Returns null when the visible order is empty or
  /// every entry is pending-deletion.
  ///
  /// Painted offsets include the node's composed slide delta (FLIP engine
  /// + make-room preview), matching what [snapshotVisibleOffsets] would
  /// return — but without allocating an O(N) map. Designed for
  /// [TreeReorderController], which polls the hovered row every pointer
  /// move and every autoscroll tick.
  ///
  /// Routing — three branches:
  ///
  /// 1. **No composed deltas** ([TreeController.hasActiveSlides] false):
  ///    O(log N) binary search on structural offsets plus a forward scan
  ///    to skip pending-deletion rows. The make-room preview is a HELD
  ///    offset, so during a widget-driven drag this branch is never
  ///    taken — the preview keeps `hasActiveSlides` true from the first
  ///    resolve to release. (The historical "slides only overlap a drag
  ///    for ≤ slideDuration" rationale predated the preview composition
  ///    and routed every drag resolve to the O(N) scan.)
  /// 2. **Exact full scan** ([_findRowFullScan], O(N) over controller
  ///    truth) when a bounded-scan precondition fails: edge ghosts exist
  ///    (ghost rows paint at the live viewport edge, unbounded by ±D —
  ///    and ghost pruning keys on the COMPOSED delta, so a held preview
  ///    can retain settled ghosts for an entire back-to-back drag); the
  ///    last layout was bulk-only (per-nid offsets stale off-cache); or
  ///    a structural mutation has not been laid out yet (per-nid offsets
  ///    stale — the full scan computes from controller truth and is
  ///    immune).
  /// 3. **Bounded window scan** ([_findRowBoundedScan], O(window)) — the
  ///    steady state of every drag. `painted = structural + delta` with
  ///    `|delta| ≤ D =` [TreeController.composedSlideAbsDeltaBound], so
  ///    only rows whose structural span intersects `[scrollY − D,
  ///    scrollY + D]` need exact testing; any live row past the window
  ///    matches trivially, and the fallback is tracked inside the scan.
  ///    Extents read the layout-stamped arrays — at most one frame behind
  ///    controller truth during extent animations (extent ticks force
  ///    relayout every frame), the same staleness class [_liveRowAt]
  ///    already accepts.
  @override
  ({TKey key, double paintedOffset, double extent})? findRowAtPaintedY(
    double scrollY,
  ) {
    final visible = controller.visibleNodes;
    if (visible.isEmpty) return null;

    if (controller.hasActiveSlides) {
      // Bounded-scan preconditions: no ghost bases, and per-nid
      // offset/extent arrays fresh for ALL visible rows (last layout was
      // non-bulk and newer than the last structural mutation). The
      // `controller.visibleNodes` read above flushed any batch-deferred
      // generation bump, so the stamp comparison sees post-flush truth.
      if (_composer.hasGhosts ||
          _lastFrameUsedBulkCumulatives ||
          controller.structureGeneration != _lastStructureGeneration) {
        debugLastFindRowUsedFullScan = true;
        return _findRowFullScan(scrollY, visible);
      }
      debugLastFindRowUsedFullScan = false;
      return _findRowBoundedScan(scrollY, visible);
    }

    // Fast path: no composed deltas, painted offset == structural offset.
    debugLastFindRowIterationCount = 0;
    final startIdx = _findFirstVisibleIndex(scrollY);
    for (int i = startIdx; i < visible.length; i++) {
      debugLastFindRowIterationCount++;
      final key = visible[i];
      if (controller.isPendingDeletion(key)) continue;
      return _liveRowAt(i, key);
    }
    // Past the end (or every trailing row is pending-deletion) — walk back
    // for the last live row.
    for (int i = visible.length - 1; i >= 0; i--) {
      debugLastFindRowIterationCount++;
      final key = visible[i];
      if (controller.isPendingDeletion(key)) continue;
      return _liveRowAt(i, key);
    }
    return null;
  }

  /// Test-only oracle access to [_findRowFullScan], so equivalence tests
  /// can compare the bounded scan's routing result against the exact
  /// full-scan answer for the same [scrollY] with zero drift risk.
  @visibleForTesting
  ({TKey key, double paintedOffset, double extent})? debugFindRowFullScan(
    double scrollY,
  ) {
    final visible = controller.visibleNodes;
    if (visible.isEmpty) {
      return null;
    }
    return _findRowFullScan(scrollY, visible);
  }

  /// Exact O(N) fallback for [findRowAtPaintedY]: index-order scan over
  /// CONTROLLER truth (current extents accumulated per row, live composed
  /// deltas, ghost-base substitution). Correct in every state — including
  /// stale layout offsets and edge-ghost bases — at full-scan cost.
  ({TKey key, double paintedOffset, double extent})? _findRowFullScan(
    double scrollY,
    List<TKey> visible,
  ) {
    TKey? lastLiveKey;
    double lastLiveOffset = 0.0;
    double lastLiveExtent = 0.0;
    double structural = 0.0;
    final orderNids = controller.orderNidsView;
    final hasEdgeGhosts = _composer.hasGhosts;
    // Lazy: only build viewport snapshot if there are ghosts to
    // resolve. Edge ghosts paint at the LIVE viewport edge.
    final ViewportSnapshot? viewportForGhosts =
        hasEdgeGhosts ? _currentViewportSnapshot() : null;
    debugLastFindRowIterationCount = 0;
    for (int i = 0; i < visible.length; i++) {
      debugLastFindRowIterationCount++;
      final nid = orderNids[i];
      final key = visible[i];
      final extent = controller.getCurrentExtentNid(nid);
      final slide = controller.getSlideDeltaNid(nid);
      // Edge-ghost rows paint at `liveBaseY + slide`, not at
      // `structural + slide`. Substitute so drag-target lookup lands
      // on the correct ghost row.
      final ghostBase = hasEdgeGhosts
          ? _composer.baseFor(key, viewportForGhosts!)
          : null;
      final paintedOffset =
          ghostBase != null ? ghostBase + slide : structural + slide;
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

  /// Bounded window scan for [findRowAtPaintedY] — the steady-drag path.
  ///
  /// Preconditions (enforced by the caller's routing): no edge ghosts,
  /// `!_lastFrameUsedBulkCumulatives` (so [_nodeOffsetsByNid] /
  /// [_nodeExtentsByNid] are fully populated and [_findFirstVisibleIndex]
  /// binary-searches the same arrays — one offset source per call), and
  /// no structural mutation since the last layout.
  ///
  /// With `D = composedSlideAbsDeltaBound` and rows contiguous in
  /// structural space:
  /// - rows before the seed have `structuralEnd ≤ scrollY − D`, hence
  ///   `paintedEnd ≤ scrollY` — they can never match the (strict) hit
  ///   predicate;
  /// - rows past the window have `structuralStart > scrollY + D`, hence
  ///   `paintedStart > scrollY` strictly — any LIVE one matches
  ///   trivially (even at zero extent);
  /// - therefore only the window needs exact per-row testing, and the
  ///   full scan's fallback (highest-index live row) is either the last
  ///   live row seen inside the window (phase 1 tracks it — live rows in
  ///   the window can FAIL the predicate, e.g. the pointer below the
  ///   whole list with the seed clamped to the last row) or, when the
  ///   window and everything after it hold no live row at all, the first
  ///   live row walking down from the seed.
  ({TKey key, double paintedOffset, double extent})? _findRowBoundedScan(
    double scrollY,
    List<TKey> visible,
  ) {
    final orderNids = controller.orderNidsView;
    final n = visible.length;
    final d = controller.composedSlideAbsDeltaBound;
    final upperBound = scrollY + d;
    final seed = _findFirstVisibleIndex(scrollY - d);
    debugLastFindRowIterationCount = 0;

    TKey? lastLiveKey;
    double lastLiveOffset = 0.0;
    double lastLiveExtent = 0.0;

    // Phase 1: exact scan inside the window, tracking the last live row
    // (hit or miss) for the fallback.
    int i = seed;
    for (; i < n; i++) {
      final nid = orderNids[i];
      final structural = _nodeOffsetsByNid[nid];
      if (structural > upperBound) {
        // Not counted here — phase 2 examines (and counts) this row.
        break;
      }
      debugLastFindRowIterationCount++;
      final key = visible[i];
      if (controller.isPendingDeletion(key)) {
        continue;
      }
      final painted = structural + controller.getSlideDeltaNid(nid);
      final extent = _nodeExtentsByNid[nid];
      if (scrollY < painted + extent) {
        return (key: key, paintedOffset: painted, extent: extent);
      }
      lastLiveKey = key;
      lastLiveOffset = painted;
      lastLiveExtent = extent;
    }

    // Phase 2: the first live row past the window matches trivially
    // (painted start strictly below it can't reach back above scrollY).
    // O(consecutive pending-deletion rows), not O(N).
    for (; i < n; i++) {
      debugLastFindRowIterationCount++;
      final key = visible[i];
      if (controller.isPendingDeletion(key)) {
        continue;
      }
      final nid = orderNids[i];
      final painted =
          _nodeOffsetsByNid[nid] + controller.getSlideDeltaNid(nid);
      return (
        key: key,
        paintedOffset: painted,
        extent: _nodeExtentsByNid[nid],
      );
    }

    // Phase 3: no live row at/after the seed matched. The highest-index
    // live row ≥ seed (if any) was tracked by phase 1; otherwise every
    // live row sits above the window — walk down for the highest one.
    if (lastLiveKey != null) {
      return (
        key: lastLiveKey,
        paintedOffset: lastLiveOffset,
        extent: lastLiveExtent,
      );
    }
    for (int j = seed - 1; j >= 0; j--) {
      debugLastFindRowIterationCount++;
      final key = visible[j];
      if (controller.isPendingDeletion(key)) {
        continue;
      }
      final nid = orderNids[j];
      final painted =
          _nodeOffsetsByNid[nid] + controller.getSlideDeltaNid(nid);
      return (
        key: key,
        paintedOffset: painted,
        extent: _nodeExtentsByNid[nid],
      );
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
    // A pending FLIP baseline AND any registered ghosts may carry stale
    // state across the detach/re-attach gap (e.g. ghost entries against
    // freed nids). `_composer.reset()` drops both maps. Practical impact
    // is muted because the next `_consumeSlideBaselineIfAny` would also
    // run `pruneSettled`, but this defense-in-depth catches the race
    // where a structural mutation happens while detached.
    _composer.reset();
    // Phantom-exit ghost records and entry-phantom clips are the same
    // staleness class the composer reset defends against — drop them
    // alongside it.
    _phantomExitGhosts = null;
    _phantomClipAnchors = null;
    // Out-of-layout scratch can hold extents against the now-stale
    // controller state; drop it so re-attach materializes fresh.
    _findFirstScratchCumulative = null;
    _findFirstScratchGen = -1;
    _findFirstScratchCount = 0;
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
    // Iterate the MOUNTED set (bounded by the cache region plus retained
    // rows) rather than the full visible order, which would pay an
    // O(N_visible) sweep per semantics pass to visit O(mounted) children.
    // Sort by visible index so screen readers still get top-to-bottom
    // visual order.
    debugLastSemanticsIterationCount = 0;
    final inFlow = <(int, RenderBox)>[];
    for (final entry in _children.entries) {
      debugLastSemanticsIterationCount++;
      final nodeId = entry.key;
      final nid = _controller.nidOf(nodeId);
      if (nid < 0) continue;
      if (_sticky.isSticky(nid)) continue;
      if (controller.getNodeData(nodeId) == null) continue;
      if (controller.isExiting(nodeId)) continue;
      final idx = _controller.visibleIndexOfNid(nid);
      if (idx < 0) continue;
      inFlow.add((idx, entry.value));
    }
    inFlow.sort((a, b) => a.$1.compareTo(b.$1));
    for (final e in inFlow) {
      visitor(e.$2);
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

  /// Grow-only scratch buffer for [_buildParentDataRefreshCumulative] so
  /// off-cache refresh frames reuse one allocation instead of allocating
  /// a fresh Float64List(N+1) per frame.
  Float64List _parentDataRefreshScratch = Float64List(0);

  /// Builds the fresh structural cumulative the off-cache parentData
  /// refresh indexes into (prefix sums of current animated extents over
  /// the visible order). O(N_visible); called at most once per layout,
  /// and only on frames where an off-cache, live, visible child is
  /// actually mounted.
  Float64List _buildParentDataRefreshCumulative(int visibleCount) {
    debugLastParentDataCumulativeBuilds++;
    if (_parentDataRefreshScratch.length < visibleCount + 1) {
      _parentDataRefreshScratch = Float64List(
        math.max(visibleCount + 1, math.max(16, _parentDataRefreshScratch.length * 2)),
      );
    }
    final cum = _parentDataRefreshScratch;
    final orderNids = controller.orderNidsView;
    double acc = 0.0;
    for (int i = 0; i < visibleCount; i++) {
      cum[i] = acc;
      acc += controller.getCurrentExtentNid(orderNids[i]);
    }
    cum[visibleCount] = acc;
    return cum;
  }

  /// Bulk fast-path escape hatch shared by Pass 2's extent-change handler
  /// and the sticky force-create path. Under [_bulkCumulativesValid] the
  /// per-nid extent slots are fresh ONLY for cache-region nids — any
  /// full-order offset recompute must first materialize the stale slots
  /// (from [fromIndex] onward, skipping the cache region whose slots are
  /// already fresh) from the controller's current animated extents, then
  /// drop the fast path for this frame. The next frame rebuilds the
  /// cumulatives fresh via [_rebuildBulkCumulatives].
  ///
  /// Nodes measured earlier this frame are safe to overwrite:
  /// [_layoutNodeChild] stores measurements through
  /// `controller.setFullExtent`, so `getCurrentExtentNid` already returns
  /// the measured value for them.
  void _materializeBulkStaleExtents({
    required int fromIndex,
    required int cacheStartIndex,
    required int cacheEndIndex,
    required int visibleCount,
  }) {
    final orderNids = controller.orderNidsView;
    for (int i = fromIndex; i < visibleCount; i++) {
      if (i >= cacheStartIndex && i < cacheEndIndex) continue;
      final nid = orderNids[i];
      _nodeExtentsByNid[nid] = controller.getCurrentExtentNid(nid);
    }
    _bulkCumulativesValid = false;
  }

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
    debugPerformLayoutCount++;
    debugLastParentDataRefreshIterationCount = 0;
    debugLastParentDataCumulativeBuilds = 0;
    final constraints = this.constraints;
    // This sliver's layout and paint code assume a vertical-forward axis.
    // Child constraints, offset math, sticky pinning and hit-testing all use
    // plain (x = indent, y = layoutOffset) coordinates with no axis mapping.
    // Running in any other axis/growth/reverse configuration silently renders
    // incorrectly, so fail loudly in debug builds.
    final bool axisOk = constraints.axis == Axis.vertical &&
        constraints.axisDirection == AxisDirection.down &&
        constraints.growthDirection == GrowthDirection.forward;
    if (!axisOk) {
      // Release-safe degraded behavior: report zero geometry rather than
      // miscompute against vertical-down assumptions. Mirrors the empty-tree
      // pattern just below: didStartLayout before setting geometry,
      // didFinishLayout after.
      //
      // The fallback runs BEFORE the assert so that even in debug builds
      // (where the assert throws and the framework catches it) downstream
      // layout/semantics/paint see valid zero geometry instead of a null
      // SliverGeometry. Without this ordering, the framework cascades to
      // multiple downstream null-check errors trying to walk an unlaid sliver.
      childManager?.didStartLayout();
      geometry = SliverGeometry.zero;
      childManager?.didFinishLayout();
    }
    assert(
      axisOk,
      "SliverTree currently supports only vertical, forward-growing axes "
      "(Axis.vertical, AxisDirection.down, GrowthDirection.forward). Got "
      "axis=${constraints.axis}, axisDirection=${constraints.axisDirection}, "
      "growthDirection=${constraints.growthDirection}.",
    );
    if (!axisOk) return;
    childManager?.didStartLayout();

    final visibleNodes = controller.visibleNodes;
    if (visibleNodes.isEmpty) {
      // An animated mutation may have staged a FLIP baseline and then
      // emptied the tree in the same frame. Discard it here — under
      // first-wins staging a stranded baseline would block every later
      // beginSlideBaseline, and when the tree repopulates the stale
      // pre-empty offsets would be consumed as the FLIP "before" of an
      // unrelated mutation (wrong one-frame deltas). Ghost/phantom
      // state is likewise keyed against rows that no longer exist —
      // mirror the controller-swap reset. Scroll bookkeeping restarts
      // fresh with the repopulated tree.
      _composer.reset();
      _phantomExitGhosts = null;
      _phantomClipAnchors = null;
      _lastObservedScrollOffset = double.nan;
      _structureChanged = true;
      _lastVisibleNodeCount = 0;
      geometry = SliverGeometry.zero;
      childManager?.didFinishLayout();
      return;
    }

    // Step 0a — Prune freed/settled entries from `_phantomExitGhosts`
    // every layout. Runs unconditionally (not just when slides are idle)
    // so dead entries don't accumulate during active slide cycles. Paint
    // passes below can iterate these maps read-only because of this prune.
    _pruneSettledPhantomExitGhosts();

    // Step 0b — Same for the composer ghost registry. `pruneSettled`
    // handles both freed-key (nid < 0) and settled (both deltas == 0)
    // entries. When all slides have settled, we additionally drop
    // everything via `clearAll` so the map shrinks back to empty.
    if (_composer.hasGhosts) {
      if (!controller.hasActiveSlides) {
        _composer.ghosts.clearAll();
      } else {
        _composer.ghosts.pruneSettled();
      }
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

    // Slide-pipeline ordering:
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
    if (scrollChanged && _composer.hasGhosts) {
      _composer.ghosts.normalizeForViewport(
        viewport: currentViewport,
        installStandaloneSlides: !_composer.isBaselineStaged,
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
    // slide progresses (see [TreeController.composedSlideAbsDeltaBound]),
    // so the transient overbuild contracts with the animation.
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
    // Summed bound, not max: a row can carry a FLIP delta AND a held
    // make-room offset at once (drag started mid-FLIP), and the composed
    // displacement reaches the sum. Identical to the max whenever only
    // one engine is active.
    final slideOverreach = controller.composedSlideAbsDeltaBound;
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
        // the fast path for this frame.
        _materializeBulkStaleExtents(
          fromIndex: firstChangedIdx,
          cacheStartIndex: cacheStartIndex,
          cacheEndIndex: cacheEndIndex,
          visibleCount: visibleNodes.length,
        );
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
          if (_bulkCumulativesValid) {
            // Mirror Pass 2's extent-change handler: the full recompute
            // below walks EVERY visible nid, but under the bulk fast path
            // only cache-region slots are fresh — materialize the rest
            // first or the recompute overwrites correct offsets and this
            // frame's geometry.scrollExtent with stale-extent garbage.
            _materializeBulkStaleExtents(
              fromIndex: 0,
              cacheStartIndex: cacheStartIndex,
              cacheEndIndex: cacheEndIndex,
              visibleCount: visibleNodes.length,
            );
          }
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

    // Ensure paintExtent covers sticky headers. Sticky headers
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

    // Bound by both the viewport's remaining paint budget AND the sliver's own
    // maxPaintExtent (= totalScrollExtent below). Sticky inflation above can
    // push paintExtent above totalScrollExtent for a short tree with a tall
    // header; without this second cap, `SliverGeometry.debugAssertIsValid`
    // fails on `paintExtent <= maxPaintExtent`.
    paintExtent = paintExtent.clamp(
      0.0,
      math.min(remainingPaintExtent, totalScrollExtent),
    );

    geometry = SliverGeometry(
      scrollExtent: totalScrollExtent,
      paintExtent: paintExtent,
      maxPaintExtent: totalScrollExtent,
      // Protocol: the cache-region portion THIS sliver consumes —
      // accounts for where the cache region starts relative to the
      // sliver, unlike min(remainingCacheExtent, totalScrollExtent),
      // which over-reports once the sliver is scrolled past the cache
      // origin and starves every subsequent sliver's cache budget.
      cacheExtent: calculateCacheOffset(
        constraints,
        from: 0.0,
        to: totalScrollExtent,
      ),
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

    // Refresh parentData (layoutOffset, indent, visibleExtent) for
    // children mounted in a prior frame that now fall outside
    // [cacheStartIndex, cacheEndIndex). The admission cap deliberately
    // limits *new* mounts to prevent mass-mounting during large
    // expansions, but already-mounted rows below an expanding subtree keep
    // their pre-expand parentData and would otherwise paint at stale
    // positions until something re-admits them to cache.
    //
    // Placed after the sticky pass so any _recomputeOffsets triggered by
    // stickyExtentsChanged has already landed in _nodeOffsetsByNid /
    // cumulatives before we write to parentData.
    //
    // Runs UNCONDITIONALLY when there are mounted children — gating on
    // `hasAnimations || hasActiveSlides` leaves a staleness window. A
    // structural mutation that installs no slides (e.g. a rapid cascaded
    // toggle whose composedY/X both round to 0, so the engine clears the
    // entry) updates parentData only for in-cache rows; a following pure
    // scroll then sees neither flag set and skips the refresh. Three ways
    // that shows up:
    //
    //   * Stale `layoutOffset`: the row paints at its OLD structural Y —
    //     "stuck until I scroll again".
    //   * Stale `indent` on a depth-changing reparent: painted X =
    //     `parentData.indent + slideDeltaX` resolves to
    //     `oldIndent + (oldIndent - newIndent)` at slide t=0.
    //   * Stale `visibleExtent`: `_paintRow`'s clip-and-translate slices
    //     the wrong portion of the child box.
    //
    // Cost is O(_children) — bounded by the cache region plus retained
    // off-cache rows (edge ghosts, exit phantoms, slide-active rows) —
    // NOT O(visibleNodes), which on a dense expandAll would walk 10⁵
    // entries per frame for ~50 writes.
    //
    // In non-bulk mode `_nodeOffsetsByNid` is stale for off-cache rows, so
    // a fresh structural cumulative is computed on demand below.
    if (_children.isNotEmpty) {
      // Built LAZILY on the first off-cache, live, visible child the loop
      // actually encounters. On the common scroll frame every mounted
      // child is in-cache, so the O(N_visible) accumulation — a
      // Float64List(N+1) allocation plus N extent-chain resolutions, the
      // dominant steady-state cost for large trees if done
      // unconditionally — never runs.
      Float64List? freshCumulative;
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
          // Build (once) and use the fresh structural cumulative.
          freshCumulative ??= _buildParentDataRefreshCumulative(
            visibleNodes.length,
          );
          offset = freshCumulative[visIdx];
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

    // Fast path: bulk cumulatives match the current visible count.
    if (_bulkCumulativesValid && _bulkCumulativesCount == n) {
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

    // Slow path after exiting bulk: per-nid arrays are fresh only
    // for cache-region nids. Out-of-layout callers (TreeReorderController
    // via findRowAtPaintedY) read this race. Materialize a one-shot
    // cumulative; cache by structureGeneration ONLY when no animation
    // is in flight — getCurrentExtentNid ticks every animation frame
    // for bulk members and the structureGeneration alone does not
    // capture that change.
    if (_lastFrameUsedBulkCumulatives) {
      final gen = _controller.structureGeneration;
      final canCache = !_controller.hasActiveAnimations;
      final cumulativeFresh = canCache &&
          _findFirstScratchGen == gen &&
          _findFirstScratchCount == n &&
          _findFirstScratchCumulative != null &&
          _findFirstScratchCumulative!.length >= n + 1;
      if (!cumulativeFresh) {
        if (_findFirstScratchCumulative == null ||
            _findFirstScratchCumulative!.length < n + 1) {
          _findFirstScratchCumulative = Float64List(n + 1);
        }
        final cum = _findFirstScratchCumulative!;
        final orderNids = _controller.orderNidsView;
        double acc = 0.0;
        cum[0] = 0.0;
        for (int i = 0; i < n; i++) {
          acc += _controller.getCurrentExtentNid(orderNids[i]);
          cum[i + 1] = acc;
        }
        if (canCache) {
          _findFirstScratchGen = gen;
          _findFirstScratchCount = n;
        } else {
          // Don't mark valid — next call (likely still mid-animation)
          // must re-materialize against the new extents.
          _findFirstScratchGen = -1;
          _findFirstScratchCount = 0;
        }
      }
      final cum = _findFirstScratchCumulative!;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        if (cum[mid + 1] <= scrollOffset) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      return low;
    }

    // Last frame was non-bulk: per-nid arrays were fully populated.
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
    // Debug capture is paint-time-scoped: cleared each frame, rewritten
    // by Pass A.5 only for actively-sliding ghosts. Assert-guarded so
    // release builds skip the map churn entirely — @visibleForTesting
    // alone does not strip it.
    assert(() {
      debugLastPhantomGhostPaint.clear();
      return true;
    }());
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
    // Summed bound, not max — see the matching performLayout comment.
    final slideOverreach = controller.composedSlideAbsDeltaBound;
    final startIndex = _findFirstVisibleIndex(scrollOffset - slideOverreach);

    // Pass A: Paint non-sticky nodes. Rows with a non-zero slide delta are
    // deferred to a second sub-pass so they paint on top of static rows —
    // without this, an upward-moving row that hasn't yet crossed into its
    // final index slot would be covered by siblings sliding down past it.
    // Among sliding rows, sort by ascending |delta| so the row that moved
    // the most (typically the just-dropped row) paints last and lands on
    // top. Ties preserve natural iteration order.
    final hasEdgeGhosts = _composer.hasGhosts;
    // Bounded iteration end, symmetric to the widened start:
    // structural offsets are monotonic in visible order and painted y
    // differs from structural by at most `slideOverreach`, so nothing at
    // or past this offset can paint inside the viewport — break instead
    // of paying a sticky check + hash probe for every below-viewport row.
    // Composer edge-ghost rows paint at the live viewport edge regardless
    // of structural position, but Pass A already skips them (Pass A.6
    // iterates the small ghost registry), so the break cannot drop one.
    // Sticky headers likewise paint from their own pass.
    final paintBound = scrollOffset + remainingPaintExtent + slideOverreach;
    List<int>? slidingIndices;
    debugLastPaintIterationCount = 0;
    for (int i = startIndex; i < visibleNodes.length; i++) {
      debugLastPaintIterationCount++;
      final nid = orderNids[i];
      if (_structuralOffsetAt(i, nid) > paintBound) {
        break;
      }
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
      // while the ghost registry entry survived (e.g.
      // direction-flip kept the entry, then composition zeroed the
      // delta), the edge-ghost paint pass will prune the entry without
      // painting. Skipping standard paint here would leave the row
      // invisible until the next layout's prune. Instead, only skip
      // when there's actually a delta to render via the edge-ghost
      // pass; otherwise fall through to standard paint at structural+0.
      if (hasEdgeGhosts
          && _composer.ghosts.entryFor(nodeId) != null
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
    // Layout's Step 0a (_pruneSettledPhantomExitGhosts) handles cleanup;
    // paint stays read-only. When slides are idle, the map is empty by
    // the next layout's Step 0a, so we don't need to clear it here.
    if (ghosts != null && ghosts.isNotEmpty && hasSlides) {
      // Hoisted once for the whole pass — edge-anchored ghosts resolve
      // their base against it.
      final a5Viewport = _currentViewportSnapshot();
      // Read-only pass: Step 0a owns all mutation of the ghost maps (at
      // layout time), so iterating the map directly is safe — no
      // per-paint key-list allocation.
      for (final ghostEntry in ghosts.entries) {
        final ghostKey = ghostEntry.key;
        final ghost = ghostEntry.value;
        final anchorKey = ghost.anchor;
        final ghostNid = controller.nidOf(ghostKey);
        if (ghostNid < 0) {
          // Freed key — Step 0a reaps on next layout.
          continue;
        }
        final ghostSlide = controller.getSlideDeltaNid(ghostNid);
        final ghostSlideX =
            hasXSlides ? controller.getSlideDeltaXNid(ghostNid) : 0.0;
        // An ADJACENT exit-ghost has ZERO own-slide (its baseline already
        // equals the settled destination-header position) yet is NOT done:
        // it must keep painting (stationary, getting progressively occluded)
        // while its anchor — the destination header — slides UP to absorb it.
        // So "settled" requires BOTH the ghost AND its anchor to be at rest.
        // (Edge ghosts: their off-screen anchor carries slide 0, so this is
        // byte-equivalent to the old ghost-only test for them.)
        final anchorNidForGate = controller.nidOf(anchorKey);
        final anchorSlideForGate = anchorNidForGate >= 0
            ? controller.getSlideDeltaNid(anchorNidForGate)
            : 0.0;
        if (ghostSlide == 0.0 &&
            ghostSlideX == 0.0 &&
            anchorSlideForGate == 0.0) {
          // Settled — Step 0a reaps on next layout.
          continue;
        }
        final ghostChild = getChildForNode(ghostKey);
        if (ghostChild == null) continue;
        // Shared base — SINGLE SOURCE OF TRUTH with the snapshot
        // augmentation in [snapshotVisibleOffsets] (see
        // [_exitGhostPaintedBaseScrollSpace] for both branches'
        // derivations, including why the anchor's SETTLED top — not the
        // live sliding band — is load-bearing for adjacent ghosts, and
        // the direction-aware tuck that composes with the consume-time
        // destination so `paintedY == baseline.y` at t=0).
        final base = _exitGhostPaintedBaseScrollSpace(
          ghostKey: ghostKey,
          ghost: ghost,
          viewport: a5Viewport,
        );
        if (base == null) continue; // truly orphaned anchor: skip as before
        final paintedY = base.y - scrollOffset + ghostSlide;
        final paintedX = base.x + ghostSlideX;
        // Skip if entirely outside the paint region.
        if (paintedY >= remainingPaintExtent) continue;
        if (paintedY + ghostChild.size.height <= 0) continue;
        final anchorChild = getChildForNode(anchorKey);
        if (anchorChild == null) {
          // Anchor unmounted (off-screen, beyond cache): the base above
          // resolved to the LIVE viewport edge (Pass A.6's model) so the
          // ghost slides off-screen instead of vanishing. No clip: there
          // is no on-screen band to clip to, and edge ghosts register no
          // _phantomClipAnchors entry.
          context.paintChild(ghostChild, offset + Offset(paintedX, paintedY));
          continue; // edge ghost painted; skip the anchor-relative tail
        }
        // Apply the EXIT clip so the ghost is bounded to the destination
        // header's painted band on its trailing side (far overhang
        // killed; band occluded by the header repaint in Pass A.7/B).
        // The clip reads the LIVE band (with the anchor's own slide) so
        // occlusion tracks the header's on-screen position — NOT used
        // for the ghost's convergence top (that's the settled top inside
        // the shared base).
        final clipRect = _resolvePhantomAnchorBounds(
          nid: ghostNid,
          paintedY: paintedY,
          offset: offset,
          remainingPaintExtent: remainingPaintExtent,
          role: PhantomClipRole.exit,
        );
        final paintOffset = offset + Offset(paintedX, paintedY);
        // Debug capture for the far-overhang oracle (sliding-ghost-only;
        // sliver paint space, NOT offset by `offset`). Reached ONLY for a
        // sliding ghost (the settled-`continue` above precedes this), so
        // the map stays empty at settle by construction. Assert-guarded
        // so release builds skip both the LIVE-band read and the record
        // allocation per sliding ghost per frame.
        assert(() {
          final anchorBand = _anchorPaintedBounds(anchorKey);
          if (anchorBand != null) {
            debugLastPhantomGhostPaint[ghostKey] = (
              ghostRect: Rect.fromLTWH(
                paintedX,
                paintedY,
                ghostChild.size.width,
                ghostChild.size.height,
              ),
              clipRect: clipRect,
              anchorBand: Rect.fromLTWH(
                0,
                anchorBand.top,
                constraints.crossAxisExtent,
                anchorBand.height,
              ),
            );
          }
          return true;
        }());
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

    // Pass A.6: Paint edge-anchor exit ghosts (live-edge-anchored
    // ghosts for long slide-OUTs). These rows ARE in visibleNodes but
    // skipped by the standard paint pass — their painted position is
    // `_composer.baseFor(key, currentViewport) + slideDelta` in
    // scroll-space, recomputed against the live viewport so the ghost
    // stays pinned to the live edge under concurrent scrolling. As the
    // slide settles, the row converges on the viewport edge and is
    // then lazily pruned (no visible cut because the row's structural
    // position is far off-screen).
    // Layout's Step 0b (`_composer.ghosts.pruneSettled` / `clearAll` when
    // idle) handles cleanup; paint stays read-only.
    if (_composer.hasGhosts && hasSlides) {
      final viewport = _currentViewportSnapshot();
      // Read-only pass — Step 0b owns registry mutation (layout time), so
      // no per-paint key-list snapshot is needed.
      for (final ghostKey in _composer.ghosts.activeKeys) {
        final entry = _composer.ghosts.entryFor(ghostKey);
        if (entry == null) continue;
        final ghostNid = controller.nidOf(ghostKey);
        if (ghostNid < 0) {
          // Freed key — Step 0b reaps on next layout.
          continue;
        }
        // Defensive: if a ghost row is also a sticky header, let the
        // sticky pass handle it (paints at pinned structural y). Edge
        // ghost behaviour is lost for this row, but no double-paint.
        // Sticky + slide-OUT-to-far-off-screen is uncommon.
        if (_sticky.isSticky(ghostNid)) continue;
        final ghostSlide = controller.getSlideDeltaNid(ghostNid);
        final ghostSlideX =
            hasXSlides ? controller.getSlideDeltaXNid(ghostNid) : 0.0;
        if (ghostSlide == 0.0 && ghostSlideX == 0.0) {
          // Settled — Step 0b reaps on next layout.
          continue;
        }
        final ghostChild = getChildForNode(ghostKey);
        if (ghostChild == null) continue;
        final indent = controller.getIndent(ghostKey);
        // Ghost paints at `liveBaseY + slideDelta` in scroll-space,
        // converted to local paint coords by subtracting scrollOffset.
        final paintedY =
            viewport.baseForEdge(entry.edge) - scrollOffset + ghostSlide;
        final paintedX = indent + ghostSlideX;
        // Skip if entirely outside the paint region.
        if (paintedY >= remainingPaintExtent) continue;
        if (paintedY + ghostChild.size.height <= 0) continue;
        context.paintChild(ghostChild, offset + Offset(paintedX, paintedY));
      }
    }

    // Pass A.7: Header-occludes-ghost. Repaint each NON-sticky
    // EXIT-ghost destination/crossed header clipped to its painted band,
    // so it lands ON TOP of the ghost painted in Pass A.5. This closes the
    // gaps where no Pass-B repaint re-asserts the header (`maxStickyDepth:
    // 0`, or a header dropped from sticky because it's animating / has no
    // children). Sticky anchors are skipped — Pass B repaints them
    // deepest-first below. A header is repainted by EXACTLY ONE of {Pass
    // A.7 (non-sticky), Pass B (sticky)} per frame.
    //
    // Iterate the EXIT-ghost records' anchors ONLY (deduped) — NOT
    // `_phantomClipAnchors.values`, which holds ENTRY-phantom anchors
    // that must NOT be repainted on top of an emerging entry row.
    if (_phantomExitGhosts != null &&
        _phantomExitGhosts!.isNotEmpty &&
        hasSlides) {
      final seenAnchors = <TKey>{};
      for (final ghost in _phantomExitGhosts!.values) {
        final anchorKey = ghost.anchor;
        if (!seenAnchors.add(anchorKey)) continue; // dedupe shared anchors
        final anchorNid = controller.nidOf(anchorKey);
        if (anchorNid < 0) continue; // freed key
        if (_sticky.isSticky(anchorNid)) continue; // Pass B owns it
        if (controller.isExiting(anchorKey)) continue; // animating out
        final anchorChild = _children[anchorKey];
        if (anchorChild == null) continue; // not mounted in-flow
        final anchorParentData = anchorChild.parentData;
        if (anchorParentData is! SliverTreeParentData) continue;
        final band = _anchorPaintedBounds(anchorKey);
        if (band == null) continue;
        // Skip if the band is fully outside the paint region.
        if (band.top >= remainingPaintExtent) continue;
        if (band.top + band.height <= 0) continue;
        final paintOffset =
            offset + Offset(anchorParentData.indent, band.top);
        context.pushClipRect(
          needsCompositing,
          paintOffset,
          Rect.fromLTWH(0, 0, anchorChild.size.width, band.height),
          (ctx, off) => ctx.paintChild(anchorChild, off),
        );
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
      // In-flow entry phantom (collapsed→visible row emerging past its
      // anchor): plain half-plane clip. The band/far-overhang rule is
      // EXIT-only.
      role: PhantomClipRole.entry,
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

  /// Drops [_ExitGhost] records whose key has been freed (`nid < 0`),
  /// was re-promoted to visibility, or whose slide has settled (dual
  /// criterion: ghost AND anchor both at rest).
  ///
  /// Called from the start of `performLayout` every frame so dead
  /// entries can't accumulate while other slides are still in flight.
  /// Paint passes can iterate the map read-only after this runs.
  void _pruneSettledPhantomExitGhosts() {
    final ghosts = _phantomExitGhosts;
    if (ghosts == null || ghosts.isEmpty) return;
    ghosts.removeWhere((ghostKey, ghost) {
      final nid = controller.nidOf(ghostKey);
      if (nid < 0) {
        return true;
      }
      // Ghost re-promoted to visibility: any visibility-changing mutation
      // (not just baseline-staging ones — e.g. a non-animated expand of
      // the destination parent revealing an ADJACENT ghost whose own
      // slide delta is zero) puts the key back in visibleNodes, where
      // Pass A paints it structurally. Drop the record so Pass A.5 does
      // not paint the same RenderBox a second time — but MIGRATE the
      // EXIT clip into [_phantomClipAnchors] first: the re-promoted row
      // keeps emerging from behind its old anchor until its slide
      // settles, at which point the consume-time clip prune's own-slide
      // criterion reaps it (the entry-role semantics the clip map owns).
      if (controller.isVisible(ghostKey)) {
        if (ghost.clipped) {
          (_phantomClipAnchors ??= <TKey, TKey>{})[ghostKey] = ghost.anchor;
        }
        return true;
      }
      final dy = controller.getSlideDeltaNid(nid);
      final dx = controller.getSlideDeltaXNid(nid);
      // Keep an ADJACENT (zero own-slide) exit-ghost alive while its anchor —
      // the destination header — is still sliding up to absorb it. Reaping on
      // the ghost's own delta alone would drop it on the first layout (its
      // delta is 0 from the start) → the vanish. "Settled" = ghost AND anchor
      // both at rest. Edge ghosts: off-screen anchor slide is 0, so this is
      // byte-equivalent to the old ghost-only test for them.
      final anchorNid = controller.nidOf(ghost.anchor);
      final anchorDy =
          anchorNid >= 0 ? controller.getSlideDeltaNid(anchorNid) : 0.0;
      return dy == 0.0 && dx == 0.0 && anchorDy == 0.0;
    });
    if (ghosts.isEmpty) {
      _phantomExitGhosts = null;
    }
    if (_phantomClipAnchors != null && _phantomClipAnchors!.isEmpty) {
      _phantomClipAnchors = null;
    }
  }

  /// The direction-aware EXIT convergence "tuck" (a non-negative scalar
  /// MAGNITUDE) for a phantom ghost sliding into its destination header.
  ///
  /// For the UPWARD / body-side approach (`slidUp == true`) of a card
  /// TALLER than its collapsed destination header, returns
  /// `max(0, ghostExtent − headerExtent)` so the EXIT ghost's convergence
  /// target is pushed an extra `tuck` px further up — its BOTTOM reaches
  /// the header band BOTTOM (full convergence, no last-frame pop). For the
  /// DOWNWARD approach (`slidUp == false`) or equal-height geometry the
  /// tuck is exactly 0, leaving the slide distance and convergence target
  /// unchanged.
  ///
  /// This is the SINGLE shared helper called by BOTH the consume-time
  /// destination injection AND the Pass A.5 paint anchor, so the two
  /// convergence sites cannot diverge — applying it at only one produces
  /// a visible jump at t=0.
  ///
  /// Pure: reads only settled extents via [TreeController.getEstimatedExtentNid]
  /// (NOT the animated `getCurrentExtentNid`, which is 0 mid-enter — the
  /// two-extent rule) and performs NO `_sticky` read and NO layout, so it
  /// is safe to call from BOTH `_consumeSlideBaselineIfAny` (where `_sticky`
  /// is stale) and `paint()`.
  double _exitTuckFor({
    required int ghostNid,
    required TKey anchorKey,
    required bool slidUp,
  }) {
    if (!slidUp) return 0.0;
    final anchorNid = _controller.nidOf(anchorKey);
    if (ghostNid < 0 || anchorNid < 0) return 0.0;
    final ghostExtent = _controller.getEstimatedExtentNid(ghostNid);
    final headerExtent = _controller.getEstimatedExtentNid(anchorNid);
    final tuck = ghostExtent - headerExtent;
    return tuck > 0 ? tuck : 0.0;
  }

  /// The anchor header's PAINTED band (top + height) in sliver PAINT
  /// space, or null when the anchor isn't mounted.
  ///
  /// When the anchor is currently sticky-pinned (its nid resolves to a
  /// fresh [StickyHeaderInfo] this frame), returns the pinned band
  /// (`info.pinnedY` / `info.extent`) — exactly where Pass B paints the
  /// header — so an EXIT ghost converges on / is clipped against the
  /// header WHERE IT ACTUALLY APPEARS on screen under scroll. Otherwise
  /// returns the structural band (`layoutOffset − scrollOffset +
  /// anchorSlide` / child height).
  ///
  /// CONTRACT:
  ///  - Coordinates are sliver PAINT space: `scrollOffset` is ALREADY
  ///    subtracted. This is NOT the "sliver-local" space of
  ///    [ReorderRenderPort] (`findRowAtPaintedY`, `beginSlideBaseline`),
  ///    which is scroll space with the first row at 0. The two differ by
  ///    `constraints.scrollOffset`; mixing them yields an error that is
  ///    invisible while scrolled to the top.
  ///  - ONLY safe to call from `paint()` — the sticky set is recomputed
  ///    each frame by `computeStickyHeaders` at the top of `paint`,
  ///    STRICTLY BEFORE the paint passes. It MUST NOT be called from
  ///    `_consumeSlideBaselineIfAny`, which runs at layout time — before
  ///    that recompute — where `_sticky` is stale or null.
  ///  - Consumed ONLY by the EXIT role (Pass A.5 ghost paint, the EXIT
  ///    clip band, and Pass A.7 header repaint). The ENTRY role keeps the
  ///    structural read in `_resolvePhantomAnchorBounds` and does NOT
  ///    call this.
  ({double top, double height})? _anchorPaintedBounds(TKey anchorKey) {
    final anchorChild = _children[anchorKey];
    if (anchorChild == null) return null;
    final anchorParentData = anchorChild.parentData;
    if (anchorParentData is! SliverTreeParentData) return null;

    final anchorNid = _controller.nidOf(anchorKey);
    // Sticky-pinned destination (fresh this frame): use the painted band.
    if (anchorNid >= 0) {
      final info = _sticky.infoForNid(anchorNid);
      if (info != null) {
        return (top: info.pinnedY, height: info.extent);
      }
    }
    // Structural band: layoutOffset − scrollOffset + anchorSlide.
    final scrollOffset = constraints.scrollOffset;
    final anchorSlide = anchorNid >= 0
        ? _controller.getSlideDeltaNid(anchorNid)
        : 0.0;
    return (
      top: anchorParentData.layoutOffset - scrollOffset + anchorSlide,
      height: anchorChild.size.height,
    );
  }

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
    required PhantomClipRole role,
  }) {
    final key = _controller.keyOfNid(nid);
    if (key == null) return null;

    // Anchor resolution is per-role: EXIT clips live inside
    // the consolidated [_ExitGhost] record; ENTRY clips live in
    // [_phantomClipAnchors].
    final TKey anchorKey;
    _ExitGhost<TKey>? exitGhost;
    if (role == PhantomClipRole.exit) {
      exitGhost = _phantomExitGhosts?[key];
      if (exitGhost == null || !exitGhost.clipped) return null;
      anchorKey = exitGhost.anchor;
    } else {
      final entryAnchor = _phantomClipAnchors?[key];
      if (entryAnchor == null) return null;
      anchorKey = entryAnchor;
    }

    final width = constraints.crossAxisExtent;

    if (role == PhantomClipRole.exit) {
      // EXIT role: a row purged from `visibleNodes` sliding
      // INTO a collapsed header to DISAPPEAR. Clip the ghost on its
      // TRAILING half-plane but bounded so NOTHING is visible on the FAR
      // side past the destination header's PAINTED band — kills the
      // far overhang of a tall card. The band itself is occluded by the
      // header repaint (Pass A.7 / Pass B). No minimum-visible floor.
      //
      // The painted band is read at PAINT time (sticky `pinnedY` when
      // pinned, else structural) via `_anchorPaintedBounds`, so this
      // tracks the header's on-screen position every frame.
      final band = _anchorPaintedBounds(anchorKey);
      if (band == null) return null;
      final bandTop = band.top;
      final bandBottom = band.top + band.height;
      // Select the trailing side from the PERSISTED direction flag, NOT
      // an instantaneous `paintedY` vs `bandTop` comparison. With the
      // upward tuck, the converged `paintedY` (= bandTop − tuck) drops
      // BELOW `bandTop`, so an instantaneous test would flip to the
      // downward branch mid-slide and re-expose the trailing-below region
      // (a one-frame pop). The persisted flag is stable across that
      // crossover.
      final slidUp = exitGhost!.slidUp;
      if (slidUp) {
        // Ghost came from below, sliding UP into the header. Visible =
        // [bandBottom, remainingPaintExtent] ALWAYS — clipping away
        // everything above bandBottom kills both the far overhang above
        // bandTop AND, once tucked, collapses the trailing region to empty.
        if (remainingPaintExtent <= bandBottom) return Rect.zero;
        return Rect.fromLTRB(0, bandBottom, width, remainingPaintExtent);
      } else {
        // Ghost came from above, sliding DOWN into the header. Visible =
        // [0, bandTop] (unchanged downward behavior).
        if (bandTop <= 0) return Rect.zero;
        return Rect.fromLTRB(0, 0, width, bandTop);
      }
    }

    // ── ENTRY role: plain half-plane against the anchor's raw box. A
    //    previously-hidden node reparented INTO view that must EMERGE
    //    past its anchor. Deliberately does NOT call
    //    `_anchorPaintedBounds` and does NOT apply the band/far-overhang
    //    rule — both are EXIT-only.
    final anchorChild = _children[anchorKey];
    if (anchorChild == null) return null;
    final anchorParentData = anchorChild.parentData;
    if (anchorParentData is! SliverTreeParentData) return null;

    final scrollOffset = constraints.scrollOffset;
    final anchorNid = _controller.nidOf(anchorKey);
    final anchorSlideDelta = anchorNid >= 0
        ? _controller.getSlideDeltaNid(anchorNid)
        : 0.0;
    // Anchor's current painted Y in sliver PAINT space (relative to the
    // start of this sliver's paint region, i.e. scrollOffset subtracted).
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
    // Visible region = the half-plane on the side where painted Y
    // currently sits relative to anchor's Y range.
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
    // Summed bound, not max — see the matching performLayout comment.
    final slideOverreach = controller.composedSlideAbsDeltaBound;
    final hitOffset = scrollOffset + mainAxisPosition;
    final startIndex = _findFirstVisibleIndex(hitOffset - slideOverreach);

    // Hoist per-axis slide-activity checks (idle-state fast path).
    final hasSlides = controller.hasActiveSlides;
    final hasXSlides = hasSlides && controller.hasActiveXSlides;
    // Lazy viewport: only built if a ghost row is encountered.
    ViewportSnapshot? hitViewport;

    // Per-row test shared by the idle single loop, the slide-active
    // z-ordered passes, and Phase 2b (edge ghosts).
    bool testRow(int i) {
      final nid = orderNids[i];
      final nodeId = visibleNodes[i];
      final child = getChildForNode(nodeId);
      if (child == null) return false;

      // Skip exiting nodes - they should not receive interactions
      // This prevents crashes when rapidly tapping delete buttons
      if (controller.isExitingNid(nid)) return false;

      final parentData = child.parentData! as SliverTreeParentData;
      // Edge-ghost rows paint at `composer.baseFor + slideDelta` (NOT at
      // structural + slideDelta). Substitute the live edge base for
      // the structural offset so hit-tests land on the painted (ghost)
      // position. Lazy: build the snapshot once, only if any ghost is
      // actually encountered.
      final double nodeOffset;
      if (_composer.ghosts.entryFor(nodeId) != null) {
        hitViewport ??= _currentViewportSnapshot();
        nodeOffset =
            _composer.baseFor(nodeId, hitViewport!) ?? parentData.layoutOffset;
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
      if (localMainAxisPosition < 0) return false;
      if (localMainAxisPosition >= nodeExtent) return false;

      final localCrossAxisPosition =
          crossAxisPosition - parentData.indent - slideDeltaX;
      if (localCrossAxisPosition < 0) return false;

      final paintedMainOffset = nodeOffset - scrollOffset + slideDelta;
      final paintedCrossOffset = parentData.indent + slideDeltaX;

      // Paint clips an entry-phantom row to the region outside
      // its anchor's bounds; the clipped-away (occluded) portion must not
      // steal hits from the anchor covering it. Reject when the hit point
      // (already in sliver-local paint space, the space the clip rect is
      // computed in) lies outside the visible region.
      if (_phantomClipAnchors?.containsKey(nodeId) ?? false) {
        final clipRect = _resolvePhantomAnchorBounds(
          nid: nid,
          paintedY: paintedMainOffset,
          offset: Offset.zero,
          remainingPaintExtent: constraints.remainingPaintExtent,
          role: PhantomClipRole.entry,
        );
        if (clipRect != null &&
            !clipRect.contains(
              Offset(crossAxisPosition, mainAxisPosition),
            )) {
          return false;
        }
      }

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

      return result.addWithAxisOffset(
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
    }

    // Bounded iteration end — see paint's Pass A for the
    // derivation. Composer edge-ghost rows past the break are covered by
    // Phase 2b below.
    final hitBound = hitOffset + slideOverreach;

    debugLastHitTestIterationCount = 0;
    if (!hasSlides) {
      // Idle fast path: structural order, single loop — zero overhead on
      // the common path (paint z-order only diverges during slides).
      for (int i = startIndex; i < visibleNodes.length; i++) {
        debugLastHitTestIterationCount++;
        final nid = orderNids[i];
        if (_structuralOffsetAt(i, nid) > hitBound) break;
        if (_sticky.isSticky(nid)) continue;
        if (testRow(i)) return true;
      }
      return false;
    }

    // Slide-active path: match paint's z-order. Paint draws
    // static rows first, then sliding rows in ASCENDING |delta| (the row
    // that moved most paints last, on top) — so hit priority is the
    // reverse: sliding rows in DESCENDING |delta| first, then static
    // rows. Ties preserve paint's natural-order rule (later index paints
    // later → tested first).
    final slidingIdx = <int>[];
    final staticIdx = <int>[];
    for (int i = startIndex; i < visibleNodes.length; i++) {
      debugLastHitTestIterationCount++;
      final nid = orderNids[i];
      if (_structuralOffsetAt(i, nid) > hitBound) break;
      if (_sticky.isSticky(nid)) continue;
      final dy = controller.getSlideDeltaNid(nid);
      final dx = hasXSlides ? controller.getSlideDeltaXNid(nid) : 0.0;
      if (dy != 0.0 || dx != 0.0) {
        slidingIdx.add(i);
      } else {
        staticIdx.add(i);
      }
    }
    slidingIdx.sort((a, b) {
      final da = controller.getSlideDeltaNid(orderNids[a]).abs();
      final db = controller.getSlideDeltaNid(orderNids[b]).abs();
      final cmp = db.compareTo(da);
      if (cmp != 0) return cmp;
      return b.compareTo(a);
    });
    for (final i in slidingIdx) {
      if (testRow(i)) return true;
    }
    for (final i in staticIdx) {
      if (testRow(i)) return true;
    }

    // Phase 2b: composer edge-ghost rows paint at the live viewport edge
    // regardless of structural position, so the bounded main loop may
    // have broken before reaching them. The registry is small; test any
    // entries the main loop did not cover.
    if (_composer.hasGhosts) {
      for (final ghostKey in _composer.ghosts.activeKeys) {
        final nid = controller.nidOf(ghostKey);
        if (nid < 0) continue;
        final i = controller.visibleIndexOfNid(nid);
        if (i < 0) continue;
        // Rows inside the bounded range were already tested above.
        if (i >= startIndex &&
            _structuralOffsetAt(i, nid) <= hitBound) {
          continue;
        }
        if (_sticky.isSticky(nid)) continue;
        if (testRow(i)) return true;
      }
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
    // Edge-ghost rows paint at `composer.baseFor + slideDelta`, not at
    // `parentData.layoutOffset + slideDelta`. Substitute the live edge
    // base so framework code (`localToGlobal`, semantics, focus
    // traversal) sees the row at its actual painted position. The live
    // base re-anchors to the current viewport edge under concurrent
    // scrolling. Settled-check: if the slide is settled but lazy-prune
    // hasn't run, fall back to the structural offset so post-settlement
    // queries report the row's real (off-screen) position.
    final typedNodeId = nodeId as TKey?;
    final edgeEntry =
        typedNodeId == null ? null : _composer.ghosts.entryFor(typedNodeId);
    final useGhost = edgeEntry != null
        && (slideDelta != 0.0 || slideDeltaX != 0.0);
    final base = useGhost
        ? _currentViewportSnapshot().baseForEdge(edgeEntry.edge)
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
