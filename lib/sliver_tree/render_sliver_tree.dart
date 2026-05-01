/// Render object for [SliverTree] that handles sliver layout and painting.
library;

import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '_sticky_header_computer.dart';
import 'sliver_tree_element.dart';
import 'tree_controller.dart';
import 'types.dart';

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
       );

  /// Sticky-header computation + cache. Owns every piece of state that
  /// exists solely to compute and cache sticky-header positions; see
  /// [StickyHeaderComputer].
  final StickyHeaderComputer<TKey, TData> _sticky;

  // ══════════════════════════════════════════════════════════════════════════
  // PROPERTIES
  // ══════════════════════════════════════════════════════════════════════════

  TreeController<TKey, TData> _controller;
  TreeController<TKey, TData> get controller => _controller;
  set controller(TreeController<TKey, TData> value) {
    if (_controller == value) return;
    _controller = value;
    _sticky.controller = value;
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

  Map<TKey, double>? _pendingSlideBaseline;
  Duration? _pendingSlideDuration;
  Curve? _pendingSlideCurve;

  /// Captures the current painted offsets so the next [performLayout] can
  /// install a FLIP slide from them to the post-mutation offsets.
  ///
  /// Call this BEFORE invoking a structural mutation on the controller
  /// (`reorderRoots`, `reorderChildren`, `moveNode`). Calling it after
  /// the mutation would capture the already-new offsets and produce a
  /// zero-delta (no visible slide). A second call before consumption
  /// overwrites the pending baseline — the latest request wins.
  void beginSlideBaseline({required Duration duration, required Curve curve}) {
    _pendingSlideBaseline = snapshotVisibleOffsets();
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
  void _consumeSlideBaselineIfAny() {
    final baseline = _pendingSlideBaseline;
    if (baseline == null) return;
    final duration = _pendingSlideDuration!;
    final curve = _pendingSlideCurve!;
    _pendingSlideBaseline = null;
    _pendingSlideDuration = null;
    _pendingSlideCurve = null;
    final current = snapshotVisibleOffsets();
    controller.animateSlideFromOffsets(
      baseline,
      current,
      duration: duration,
      curve: curve,
    );
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
  /// in the cache region or is a sticky header. Used by the element to
  /// decide whether an off-screen child can be evicted. O(1), no allocation.
  bool isNodeRetained(TKey id) {
    final nid = _controller.nidOf(id);
    if (nid < 0) return false;
    if (nid < _inCacheRegionByNid.length && _inCacheRegionByNid[nid] != 0) {
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
  Map<TKey, double> snapshotVisibleOffsets() {
    final result = <TKey, double>{};
    double structural = 0.0;
    final visible = controller.visibleNodes;
    final orderNids = controller.orderNidsView;
    for (int i = 0; i < visible.length; i++) {
      final nid = orderNids[i];
      final slide = controller.getSlideDeltaNid(nid);
      result[visible[i]] = structural + slide;
      structural += controller.getCurrentExtentNid(nid);
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
      for (int i = 0; i < visible.length; i++) {
        final nid = orderNids[i];
        final key = visible[i];
        final extent = controller.getCurrentExtentNid(nid);
        final slide = controller.getSlideDeltaNid(nid);
        final paintedOffset = structural + slide;
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
  }

  @override
  void detach() {
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

    // If a caller (TreeReorderController.endDrag) staged a FLIP slide
    // baseline before the structural mutation that triggered this layout,
    // install the slide NOW — before Pass 2's build-range decision, so
    // `maxActiveSlideAbsDelta` reflects the just-installed deltas and Pass
    // 2 builds rows sliding INTO the viewport from outside the structural
    // cache region. `snapshotVisibleOffsets()` walks `visibleNodes` with
    // `getCurrentExtent`, which is independent of Pass 1's per-nid offset
    // array, so calling it before Pass 1 is safe.
    _consumeSlideBaselineIfAny();

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
      fullCacheEnd = fullStart + remainingCacheExtent + slideOverreach;
    } else {
      fullCacheEnd = 0.0;
    }

    int cacheEndIndex = cacheStartIndex;
    // Dual-view admission for the non-bulk (op-group) path.
    //
    // Two running accumulators track the cache budget in parallel:
    //
    //   liveAccum  — per-row contribution using FULL extent for any animating
    //                row (enter or exit). Preserves the original
    //                "steady-state" accumulator's role of capping admission
    //                at the pre-animation row count during enters (prevents
    //                mass-mounting the entering subtree on frame 1 of an
    //                expand).
    //
    //   postAccum  — per-row contribution using TARGET extent: full for
    //                enters, 0 for exits, live for non-animating. Tracks
    //                what the cumulative layout will look like AFTER the
    //                animation settles.
    //
    // A row is admitted when it passes either view (with the constraint
    // that exits can only be admitted via the LIVE view — a row that will
    // be gone after the animation does not belong in the post-animation
    // cache set). The loop stops iterating only when BOTH views agree no
    // future row could be admitted.
    //
    // During a collapse of a many-child parent: exits beyond the live
    // window fail the live check and — being exits — are excluded from
    // the post view, so they are iterated past but not admitted. Once we
    // reach the non-exit following rows, the post view admits them based
    // on their post-animation positions, pre-mounting them before dismiss
    // and eliminating the "flicker as they appear" pop. During an expand,
    // the live-view cap still prevents mass-mounting the full entering
    // subtree.
    //
    // Post-animation offset is tracked relative to the live offset of the
    // row at [cacheStartIndex] — rows before the cache start are treated
    // as stable (the common case for animations on a parent visible in
    // the viewport).
    {
      double liveAccum = 0.0;
      double postAccum = 0.0;
      final orderNids = controller.orderNidsView;
      final double postOffsetOrigin = cacheStartIndex < visibleNodes.length
          ? _nodeOffsetsByNid[orderNids[cacheStartIndex]]
          : 0.0;
      double postOffsetCumul = 0.0;
      final double budgetCap = remainingCacheExtent + slideOverreach;
      for (int i = cacheStartIndex; i < visibleNodes.length; i++) {
        final nid = orderNids[i];
        if (_bulkCumulativesValid) {
          // Under bulk-only fast path, pull from cumulatives and sync into the
          // per-nid slots so downstream code (Pass 2, paint-extent, paint,
          // hit-test) reads correct values without a branch per access.
          final offset = _offsetAtVisibleIndex(i);
          _nodeOffsetsByNid[nid] = offset;
          _nodeExtentsByNid[nid] = _offsetAtVisibleIndex(i + 1) - offset;
          final fullOffset = _stableCumulative[i] + _bulkFullCumulative[i];
          if (fullOffset >= fullCacheEnd) break;
          _inCacheRegionByNid[nid] = 1;
          _writeCacheRegionNid(nid);
          cacheEndIndex = i + 1;
          continue;
        }

        final double liveOffset = _nodeOffsetsByNid[nid];
        final double postOffset = postOffsetOrigin + postOffsetCumul;

        final bool liveBudgetOk =
            liveOffset < effectiveCacheEnd && liveAccum < budgetCap;
        final bool postBudgetOk =
            postOffset < effectiveCacheEnd && postAccum < budgetCap;

        // Both views failed — offsets and accumulators only grow, so no
        // future row can be admitted.
        if (!liveBudgetOk && !postBudgetOk) {
          break;
        }

        // [isAnimatingNid] and [isExitingNid] are O(1) (nid-keyed mirror).
        // Exits must admit via the LIVE view only; they have no
        // post-animation position and should not be pre-mounted just
        // because the post view has budget.
        final bool isAnimating = controller.isAnimatingNid(nid);
        final bool isExit = isAnimating && controller.isExitingNid(nid);
        final bool admit = liveBudgetOk || (!isExit && postBudgetOk);
        if (admit) {
          _inCacheRegionByNid[nid] = 1;
          _writeCacheRegionNid(nid);
          cacheEndIndex = i + 1;
        }

        // Update accumulators regardless of admission — the budget is a
        // cumulative quantity measured over every row the loop has
        // considered, not just admitted ones. Future-row break decisions
        // depend on these.
        final double liveContribution;
        final double postContribution;
        if (isAnimating) {
          final full = controller.getEstimatedExtentNid(nid);
          liveContribution = full;
          postContribution = isExit ? 0.0 : full;
        } else {
          final live = _nodeExtentsByNid[nid];
          liveContribution = live;
          postContribution = live;
        }
        liveAccum += liveContribution;
        postAccum += postContribution;
        postOffsetCumul += postContribution;
      }
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
    if (hasAnimations && _children.isNotEmpty) {
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
          offset = _nodeOffsetsByNid[nid];
        }
        final parentData = child.parentData! as SliverTreeParentData;
        parentData.layoutOffset = offset;
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
      // ticks) always see the current value.
      final slideDelta = controller.getSlideDeltaNid(nid);

      if (slideDelta != 0.0) {
        (slidingIndices ??= <int>[]).add(i);
        continue;
      }

      _paintRow(
        context: context,
        offset: offset,
        nid: nid,
        child: child,
        slideDelta: 0.0,
        scrollOffset: scrollOffset,
        remainingPaintExtent: remainingPaintExtent,
      );
    }

    if (slidingIndices != null) {
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
        _paintRow(
          context: context,
          offset: offset,
          nid: orderNids[i],
          child: child,
          slideDelta: controller.getSlideDeltaNid(orderNids[i]),
          scrollOffset: scrollOffset,
          remainingPaintExtent: remainingPaintExtent,
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
        Offset(parentData.indent, nodeOffset - scrollOffset + slideDelta);

    if (controller.isAnimatingNid(nid) && nodeExtent < child.size.height) {
      final yOffset = -(child.size.height - nodeExtent);
      context.pushClipRect(
        needsCompositing,
        paintOffset,
        Rect.fromLTWH(0, 0, child.size.width, nodeExtent),
        (context, offset) {
          context.paintChild(child, offset + Offset(0, yOffset));
        },
      );
    } else {
      context.paintChild(child, paintOffset);
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
      final nodeOffset = parentData.layoutOffset;
      final nodeExtent = parentData.visibleExtent;

      // Shift the hit coordinate by the node's current slide delta so a
      // tap lands on the visually-displaced child rather than on the
      // structural position nobody sees during a slide.
      final slideDelta = controller.getSlideDeltaNid(nid);
      final localMainAxisPosition =
          mainAxisPosition + scrollOffset - nodeOffset - slideDelta;
      if (localMainAxisPosition < 0) continue;
      if (localMainAxisPosition >= nodeExtent) continue;

      final localCrossAxisPosition = crossAxisPosition - parentData.indent;
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
      final hit = result.addWithAxisOffset(
        paintOffset: Offset(parentData.indent, paintedMainOffset),
        mainAxisOffset: paintedMainOffset,
        crossAxisOffset: parentData.indent,
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
    // visually-displaced row during a slide.
    final slideDelta = nid >= 0 ? controller.getSlideDeltaNid(nid) : 0.0;

    final scrollOffset = constraints.scrollOffset;
    transform.translateByDouble(
      parentData.indent,
      parentData.layoutOffset - scrollOffset - yAdjust + slideDelta,
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
