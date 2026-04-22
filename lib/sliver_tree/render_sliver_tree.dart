/// Render object for [SliverTree] that handles sliver layout and painting.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

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
       _maxStickyDepth = maxStickyDepth;

  // ══════════════════════════════════════════════════════════════════════════
  // PROPERTIES
  // ══════════════════════════════════════════════════════════════════════════

  TreeController<TKey, TData> _controller;
  TreeController<TKey, TData> get controller => _controller;
  set controller(TreeController<TKey, TData> value) {
    if (_controller == value) return;
    _controller = value;
    // Stale per-node caches keyed by the old controller's keys would
    // produce wrong geometry on the next layout — especially if the new
    // controller's structureGeneration happens to match the cached value
    // (fresh controllers start at 0). Reset everything that's keyed by
    // node and force a structure-change pass.
    _structureChanged = true;
    _stickyPrecomputeDirty = true;
    _lastStructureGeneration = -1;
    _lastVisibleNodeCount = 0;
    _lastTotalScrollExtent = 0.0;
    _animationsWereActive = false;
    _lastStickyScrollOffset = double.nan;
    // Nid-indexed arrays are sized against the old controller; reset to
    // empty and let [_ensureLayoutCapacity] regrow against the new one.
    _nodeOffsetsByNid = Float64List(0);
    _nodeExtentsByNid = Float64List(0);
    _inCacheRegionByNid = Uint8List(0);
    _stickyByNid = <StickyHeaderInfo<TKey>?>[];
    _stickyHeaders.clear();
    _lastPrecomputedCount = 0;
    // Bulk-only fast-path caches are visible-position-indexed; any
    // structure from the old controller is meaningless under the new one.
    _bulkCumulativesValid = false;
    _bulkCumulativesCount = 0;
    _lastBulkAnimationGeneration = -1;
    _lastFrameUsedBulkCumulatives = false;
    // Drop child map bookkeeping — the actual RenderBoxes stay adopted and
    // will be reconciled on the next layout via the child manager.
    _children.clear();
    markNeedsLayout();
  }

  int _maxStickyDepth;
  int get maxStickyDepth => _maxStickyDepth;
  set maxStickyDepth(int value) {
    if (_maxStickyDepth == value) return;
    _maxStickyDepth = value;
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

  /// Frame counter for throttling sticky header recomputation during animation.
  int _stickyThrottleCounter = 0;

  /// Scroll offset observed on the last frame that computed sticky headers.
  /// Used to force a recompute when the user scrolls during an animation, so
  /// sticky [pinnedY] values don't lag behind the actual scroll position.
  double _lastStickyScrollOffset = double.nan;

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
  void _rebuildBulkCumulatives(List<TKey> visibleNodes) {
    final n = visibleNodes.length;
    if (_stableCumulative.length < n + 1) {
      final newLen = math.max(n + 1, math.max(16, _stableCumulative.length * 2));
      _stableCumulative = Float64List(newLen);
      _bulkFullCumulative = Float64List(newLen);
    }
    double sStable = 0.0;
    double sBulkFull = 0.0;
    _stableCumulative[0] = 0.0;
    _bulkFullCumulative[0] = 0.0;
    for (int i = 0; i < n; i++) {
      final key = visibleNodes[i];
      final full = controller.getEstimatedExtent(key);
      if (controller.isBulkMember(key)) {
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
  /// region. Cleared via [Uint8List.fillRange] at the start of Pass 2 each
  /// layout, then set for every cache-region member.
  Uint8List _inCacheRegionByNid = Uint8List(0);

  /// Sticky header info indexed by nid. Null when the node is not currently
  /// a sticky header. Serves as both membership flag (non-null means sticky)
  /// and the data payload used by paint/hit-test/transform.
  List<StickyHeaderInfo<TKey>?> _stickyByNid = <StickyHeaderInfo<TKey>?>[];

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
    final newSticky = List<StickyHeaderInfo<TKey>?>.filled(cap, null);
    for (int i = 0; i < _stickyByNid.length; i++) {
      newSticky[i] = _stickyByNid[i];
    }
    _stickyByNid = newSticky;
  }

  /// Whether structure changed since last layout.
  bool _structureChanged = true;

  /// Cached total scroll extent from the last Pass 1 run.
  double _lastTotalScrollExtent = 0.0;

  /// Whether animations were active in the previous frame.
  /// Used to ensure one final Pass 1 runs after animation settles so that
  /// extents snapshot the final (progress=1) values.
  bool _animationsWereActive = false;

  /// Whether sticky subtree precomputation needs to re-run.
  /// Set on structure change, extent change, or animation-to-idle transition.
  /// Cleared after [_precomputeStableSubtreeBottoms] completes.
  bool _stickyPrecomputeDirty = true;

  /// Computed sticky headers for the current layout, ordered root→leaf.
  final List<StickyHeaderInfo<TKey>> _stickyHeaders = [];

  // Stable subtree precompute caches (rebuilt each layout, reused across frames).
  // Use nullable backing lists that are replaced when capacity grows, avoiding
  // the Dart issue where setting .length on a non-nullable List<int> fails.
  List<int> _depthScratch = List<int>.empty();
  List<double> _stablePrefix = List<double>.empty();
  List<int> _subtreeEndIndex = List<int>.empty();
  List<double> _subtreeBottomByIndex = List<double>.empty();
  final List<int> _indexStack = <int>[];
  int _lastPrecomputedCount = 0;

  /// Marks the tree structure as changed, clears layout caches, and
  /// requests a new layout pass.
  ///
  /// Called by the element during hot reload to ensure children are
  /// recreated with the new `nodeBuilder`.
  void markStructureChanged() {
    _structureChanged = true;
    _stickyPrecomputeDirty = true;
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
  void beginSlideBaseline({
    required Duration duration,
    required Curve curve,
  }) {
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

  /// Reallocates scratch arrays to fit [_lastPrecomputedCount] (or empty
  /// if zero). Call when the tree shrinks significantly and memory matters.
  void trimScratchArrays() {
    final n = _lastPrecomputedCount;
    if (n == 0) {
      _depthScratch = List<int>.empty();
      _stablePrefix = List<double>.empty();
      _subtreeEndIndex = List<int>.empty();
      _subtreeBottomByIndex = List<double>.empty();
    } else {
      _depthScratch = List<int>.filled(n, 0);
      _stablePrefix = List<double>.filled(n + 1, 0.0);
      _subtreeEndIndex = List<int>.filled(n, 0);
      _subtreeBottomByIndex = List<double>.filled(n, 0.0);
    }
  }

  /// Pre-allocates scratch arrays for [capacity] nodes. Useful when the
  /// tree size is known upfront to avoid incremental resizing.
  void resizeScratchArrays(int capacity) {
    if (capacity <= 0) {
      _depthScratch = List<int>.empty();
      _stablePrefix = List<double>.empty();
      _subtreeEndIndex = List<int>.empty();
      _subtreeBottomByIndex = List<double>.empty();
    } else {
      _depthScratch = List<int>.filled(capacity, 0);
      _stablePrefix = List<double>.filled(capacity + 1, 0.0);
      _subtreeEndIndex = List<int>.filled(capacity, 0);
      _subtreeBottomByIndex = List<double>.filled(capacity, 0.0);
    }
  }

  /// Whether the given node is retained by the current layout — i.e. it is
  /// in the cache region or is a sticky header. Used by the element to
  /// decide whether an off-screen child can be evicted. O(1), no allocation.
  bool isNodeRetained(TKey id) {
    final nid = _controller.nidOf(id);
    if (nid < 0) return false;
    if (nid < _inCacheRegionByNid.length && _inCacheRegionByNid[nid] != 0) {
      return true;
    }
    if (nid < _stickyByNid.length && _stickyByNid[nid] != null) {
      return true;
    }
    return false;
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
    for (final key in controller.visibleNodes) {
      final slide = controller.getSlideDelta(key);
      result[key] = structural + slide;
      structural += _currentVisibleExtentOf(key);
    }
    return result;
  }

  /// Structural extent of [key] accounting for any in-flight enter/exit
  /// animation — same value Pass 1 would compute. Does not include slide
  /// delta (slide is paint-only).
  double _currentVisibleExtentOf(TKey key) {
    return controller.getCurrentExtent(key);
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
    for (final sticky in _stickyHeaders) {
      final child = getChildForNode(sticky.nodeId);
      if (child == null) continue;
      if (controller.getNodeData(sticky.nodeId) == null) continue;
      if (controller.isExiting(sticky.nodeId)) continue;
      visitor(child);
    }
    // Then in-flow visible nodes, skipping any already emitted as sticky.
    for (final nodeId in controller.visibleNodes) {
      final nid = _controller.nidOf(nodeId);
      if (nid >= 0 &&
          nid < _stickyByNid.length &&
          _stickyByNid[nid] != null) {
        continue;
      }
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

  /// Computes the bottom edge of a node's subtree using DFS ordering.
  ///
  /// Bug 2 fix: When a descendant is entering (expand animation), its animated
  /// extent is growing from 0 which would cause the parent header to get pushed
  /// up prematurely. To prevent bounce, we use full (target) extents for
  /// entering descendants and recompute their offset contribution stably.
  double _computeSubtreeBottom(TKey nodeId, List<TKey> visibleNodes) {
    final index = controller.getVisibleIndex(nodeId);
    if (index < 0) return 0.0;
    final nodeDepth = controller.getDepth(nodeId);

    // Walk descendants, accumulating stable offsets using full extents for
    // entering nodes. This prevents push-up bounce during expand animations.
    final nid = _controller.nidOf(nodeId);
    double stableOffset = _nodeOffsetsByNid[nid];
    stableOffset += _nodeExtentsByNid[nid];
    double bottom = stableOffset;

    for (int i = index + 1; i < visibleNodes.length; i++) {
      final childId = visibleNodes[i];
      if (controller.getDepth(childId) <= nodeDepth) break;

      final animation = controller.getAnimationState(childId);
      final double childExtent;
      if (animation != null && animation.type == AnimationType.entering) {
        // Use full (target) extent instead of animated extent to keep bottom stable.
        childExtent = controller.getEstimatedExtent(childId);
      } else {
        childExtent = _nodeExtentsByNid[_controller.nidOf(childId)];
      }

      final childEnd = stableOffset + childExtent;
      if (childEnd > bottom) bottom = childEnd;
      stableOffset += childExtent;
    }
    return bottom;
  }

  /// Precomputes subtree bottom offsets for all visible nodes in O(N).
  ///
  /// Uses the same "entering nodes use full estimated extent" logic as
  /// [_computeSubtreeBottom], but does it for the entire visible list in
  /// three linear passes instead of per-candidate descent scanning.
  ///
  /// After this call, [_subtreeBottomByIndex] contains the subtree bottom
  /// (in scroll-space) for each index in [visibleNodes].
  void _precomputeStableSubtreeBottoms(List<TKey> visibleNodes) {
    final n = visibleNodes.length;
    if (n == 0) return;

    // Resize scratch arrays if needed (reuse across frames when possible).
    if (_depthScratch.length < n) {
      _depthScratch = List<int>.filled(n, 0);
      _subtreeEndIndex = List<int>.filled(n, 0);
      _subtreeBottomByIndex = List<double>.filled(n, 0.0);
      _stablePrefix = List<double>.filled(n + 1, 0.0);
    }
    _stablePrefix[0] = 0.0;

    // Pass A: depths + stable prefix sums.
    for (int i = 0; i < n; i++) {
      final nodeId = visibleNodes[i];

      final depth = controller.getDepth(nodeId);
      _depthScratch[i] = depth;

      final anim = controller.getAnimationState(nodeId);
      final double stableExtent;
      if (anim != null && anim.type == AnimationType.entering) {
        // Use full extent so ancestor push-up doesn't bounce during expand.
        stableExtent = controller.getEstimatedExtent(nodeId);
      } else {
        stableExtent = _nodeExtentsByNid[_controller.nidOf(nodeId)];
      }

      _stablePrefix[i + 1] = _stablePrefix[i] + stableExtent;
    }

    // Pass B: subtree end index for each node using a monotonic depth stack.
    _indexStack.clear();
    for (int i = 0; i < n; i++) {
      final depth = _depthScratch[i];

      while (_indexStack.isNotEmpty &&
          depth <= _depthScratch[_indexStack.last]) {
        final j = _indexStack.removeLast();
        _subtreeEndIndex[j] = i - 1;
      }
      _indexStack.add(i);
    }
    while (_indexStack.isNotEmpty) {
      final j = _indexStack.removeLast();
      _subtreeEndIndex[j] = n - 1;
    }

    // Pass C: subtree bottom per node.
    // For each node i: bottom = (node's actual end) + (stable sum of descendants).
    for (int i = 0; i < n; i++) {
      final nid = _controller.nidOf(visibleNodes[i]);
      final actualEnd = _nodeOffsetsByNid[nid] + _nodeExtentsByNid[nid];

      final end = _subtreeEndIndex[i];
      final descendantStableSum = _stablePrefix[end + 1] - _stablePrefix[i + 1];

      _subtreeBottomByIndex[i] = actualEnd + descendantStableSum;
    }
    _lastPrecomputedCount = n;
  }

  /// Returns the ancestor of [nodeId] at the given [targetDepth], or null.
  TKey? _ancestorAtDepth(TKey nodeId, int targetDepth) {
    TKey? current = nodeId;
    while (current != null) {
      final depth = controller.getDepth(current);
      if (depth == targetDepth) return current;
      if (depth < targetDepth) return null;
      current = controller.getParent(current);
    }
    return null;
  }

  /// Iterates sticky candidates top-down, calling [onCandidate] for each
  /// valid depth. Stops when the chain breaks (animation, no children, etc.)
  /// or when [onCandidate] returns false.
  ///
  /// Shared probe logic for both [_identifyPotentialStickyNodes] and
  /// [_computeStickyHeaders].
  void _forEachStickyCandidate(
    double scrollOffset,
    double overlap,
    List<TKey> visibleNodes,
    bool Function(TKey candidateId, double pinnedY, double extent, double stackTop) onCandidate,
  ) {
    if (_maxStickyDepth <= 0 || visibleNodes.isEmpty) return;

    double stackTop = math.max(0.0, overlap);
    TKey? parentStickyId;

    for (int targetDepth = 0; targetDepth < _maxStickyDepth; targetDepth++) {
      final probeScrollY = scrollOffset + stackTop;
      final probeIndex = _findFirstVisibleIndex(visibleNodes, probeScrollY);
      if (probeIndex >= visibleNodes.length) break;

      final nodeAtProbe = visibleNodes[probeIndex];
      final candidateId = _ancestorAtDepth(nodeAtProbe, targetDepth);
      if (candidateId == null) break;

      if (parentStickyId != null &&
          controller.getParent(candidateId) != parentStickyId) {
        break;
      }

      if (controller.isAnimating(candidateId)) break;
      if (!controller.hasChildren(candidateId)) break;

      // Candidate must be in the current visible list — otherwise its
      // offset slot holds stale data from a prior layout pass (or zero).
      final candidateIndex = controller.getVisibleIndex(candidateId);
      if (candidateIndex < 0) break;
      final naturalOffset = _nodeOffsetsByNid[_controller.nidOf(candidateId)];

      final naturalY = naturalOffset - scrollOffset;
      if (naturalY > stackTop) break;

      final extent = controller.getEstimatedExtent(candidateId);
      final subtreeBottom =
          (candidateIndex >= 0 && candidateIndex < _lastPrecomputedCount)
              ? _subtreeBottomByIndex[candidateIndex]
              : _computeSubtreeBottom(candidateId, visibleNodes);
      final pushUpY = (subtreeBottom - scrollOffset) - extent;

      final pinnedY = math.min(stackTop, pushUpY);

      if (pinnedY + extent <= stackTop) break;

      if (!onCandidate(candidateId, pinnedY, extent, stackTop)) break;

      parentStickyId = candidateId;
      stackTop = pinnedY + extent;
    }
  }

  /// Lightweight pre-pass that identifies nodes which might need to be
  /// sticky. Used before Pass 2 to force-create their render objects.
  Set<TKey> _identifyPotentialStickyNodes(double scrollOffset, double overlap, List<TKey> visibleNodes) {
    final result = <TKey>{};
    _forEachStickyCandidate(scrollOffset, overlap, visibleNodes,
        (candidateId, pinnedY, extent, stackTop) {
      result.add(candidateId);
      return true;
    });
    return result;
  }

  /// Computes sticky headers based on scroll position.
  ///
  /// Called after Pass 2 when actual extents and offsets are available.
  /// [overlap] is `constraints.overlap` — the number of pixels at the top
  /// covered by a preceding pinned sliver (e.g. PinnedHeaderSliver).
  void _computeStickyHeaders(double scrollOffset, double overlap, List<TKey> visibleNodes) {
    // Null out prior-layout sticky entries before recomputing. The nid slots
    // for nodes that remain sticky this frame are rewritten below; slots for
    // nodes that no longer qualify stay null, which doubles as the
    // "is-sticky" membership test used by paint/hit-test/semantics.
    for (final sticky in _stickyHeaders) {
      final nid = _controller.nidOf(sticky.nodeId);
      if (nid >= 0 && nid < _stickyByNid.length) {
        _stickyByNid[nid] = null;
      }
    }
    _stickyHeaders.clear();

    double? parentPinnedY;
    _forEachStickyCandidate(scrollOffset, overlap, visibleNodes,
        (candidateId, pinnedY, extent, stackTop) {
      // Deeper headers can slide behind parent, but must never go above parent TOP.
      if (parentPinnedY != null) {
        pinnedY = math.max(parentPinnedY!, pinnedY);
        if (pinnedY + extent <= stackTop) return false;
      }

      final indent = controller.getIndent(candidateId);
      final info = StickyHeaderInfo<TKey>(
        nodeId: candidateId,
        pinnedY: pinnedY,
        extent: extent,
        indent: indent,
      );
      _stickyHeaders.add(info);
      _stickyByNid[_controller.nidOf(candidateId)] = info;

      parentPinnedY = pinnedY;
      return true;
    });
  }

  /// Recomputes [_nodeOffsetsByNid] from current [_nodeExtentsByNid] and
  /// returns the new total scroll extent. Call after Pass 2 when extents
  /// have been updated with actual measured values.
  double _recomputeOffsets(List<TKey> visibleNodes) {
    double offset = 0.0;
    for (final nodeId in visibleNodes) {
      final nid = _controller.nidOf(nodeId);
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
  double _recomputeOffsetsFrom(List<TKey> visibleNodes, int fromIndex) {
    if (visibleNodes.isEmpty) return 0.0;
    if (fromIndex <= 0) return _recomputeOffsets(visibleNodes);

    double offset = _nodeOffsetsByNid[_controller.nidOf(visibleNodes[fromIndex])];
    for (int i = fromIndex; i < visibleNodes.length; i++) {
      final nid = _controller.nidOf(visibleNodes[i]);
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
  double? _layoutNodeChild(
    TKey nodeId,
    double crossAxisExtent,
  ) {
    final child = getChildForNode(nodeId);
    if (child == null) return null;

    final indent = controller.getIndent(nodeId);
    final w = math.max(0.0, crossAxisExtent - indent);
    final childConstraints = BoxConstraints(
      minWidth: w, maxWidth: w,
      minHeight: 0.0, maxHeight: double.infinity,
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
      _stickyPrecomputeDirty = true;
      _lastStructureGeneration = controller.structureGeneration;
    }
    if (visibleNodes.length != _lastVisibleNodeCount) {
      _structureChanged = true;
      _stickyPrecomputeDirty = true;
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

    // ────────────────────────────────────────────────────────────────────────
    // PASS 1: Calculate offsets and extents
    // ────────────────────────────────────────────────────────────────────────
    double totalScrollExtent;
    final bool hasAnimations = controller.hasActiveAnimations;
    final bool bulkOnly =
        controller.isBulkAnimating && !controller.hasOpGroupAnimations;

    if (bulkOnly) {
      // Fast path: bulk animation only. Every node's offset is a scalar
      // function of position via the precomputed cumulatives. Avoid touching
      // _nodeOffsetsByNid for nodes outside the cache region — that write
      // is what the per-frame O(N) cost was buying.
      final bulkGen = controller.bulkAnimationGeneration;
      final n = visibleNodes.length;
      if (!_bulkCumulativesValid ||
          _bulkCumulativesCount != n ||
          bulkGen != _lastBulkAnimationGeneration ||
          _structureChanged) {
        _rebuildBulkCumulatives(visibleNodes);
        _lastBulkAnimationGeneration = bulkGen;
        _structureChanged = false;
      }
      _bulkValueCached = controller.bulkAnimationValue;
      totalScrollExtent = _offsetAtVisibleIndex(n);
      _lastFrameUsedBulkCumulatives = true;
    } else if (_structureChanged || _lastFrameUsedBulkCumulatives) {
      // Either the visible order changed OR we just exited the bulk-only
      // fast path — in both cases the per-nid offset/extent arrays are
      // not guaranteed fresh for every visible node, so do a full walk.
      _bulkCumulativesValid = false;
      _lastFrameUsedBulkCumulatives = false;
      totalScrollExtent = 0.0;

      for (final nodeId in visibleNodes) {
        final nid = _controller.nidOf(nodeId);
        _nodeOffsetsByNid[nid] = totalScrollExtent;
        final extent = controller.getCurrentExtent(nodeId);
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
        if (firstAnimIdx == 0) {
          totalScrollExtent = 0.0;
        } else {
          final prevNid = _controller.nidOf(visibleNodes[firstAnimIdx - 1]);
          totalScrollExtent =
              _nodeOffsetsByNid[prevNid] + _nodeExtentsByNid[prevNid];
        }
        for (int i = firstAnimIdx; i < visibleNodes.length; i++) {
          final nodeId = visibleNodes[i];
          final newExtent = controller.getCurrentExtent(nodeId);
          final nid = _controller.nidOf(nodeId);
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

      for (final nodeId in visibleNodes) {
        final newExtent = controller.getCurrentExtent(nodeId);
        final nid = _controller.nidOf(nodeId);
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
    _inCacheRegionByNid.fillRange(0, _inCacheRegionByNid.length, 0);
    final cacheStartIndex = _findFirstVisibleIndex(visibleNodes, cacheStart);

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
      fullCacheEnd = fullStart + remainingCacheExtent;
    } else {
      fullCacheEnd = 0.0;
    }

    int cacheEndIndex = cacheStartIndex;
    // Steady-state accumulator for the non-bulk (op-group) path. Mirrors the
    // rationale of the bulk branch above: at low animation values, entering
    // rows have sub-pixel animated extents, so reading live offsets would
    // admit the entire entering subtree into the cache region on frame 1 of
    // a single-node expand — e.g. all 1150 children of a large parent,
    // causing a mass-mount / mass-rebuild hitch. We cap admission at what
    // the cache region would hold at steady state (full extents for
    // entering rows, live extent for the rest).
    double steadyAccum = 0.0;
    for (int i = cacheStartIndex; i < visibleNodes.length; i++) {
      final nodeId = visibleNodes[i];
      final nid = _controller.nidOf(nodeId);
      final double offset;
      if (_bulkCumulativesValid) {
        // Under bulk-only fast path, pull from cumulatives and sync into the
        // per-nid slots so downstream code (Pass 2, paint-extent, paint,
        // hit-test) reads correct values without a branch per access.
        offset = _offsetAtVisibleIndex(i);
        _nodeOffsetsByNid[nid] = offset;
        _nodeExtentsByNid[nid] = _offsetAtVisibleIndex(i + 1) - offset;
        final fullOffset = _stableCumulative[i] + _bulkFullCumulative[i];
        if (fullOffset >= fullCacheEnd) break;
      } else {
        offset = _nodeOffsetsByNid[nid];
        if (offset >= cacheEnd) break;
        if (steadyAccum >= remainingCacheExtent) break;
      }
      _inCacheRegionByNid[nid] = 1;
      cacheEndIndex = i + 1;
      if (!_bulkCumulativesValid) {
        final anim = controller.getAnimationState(nodeId);
        final double contribution;
        if (anim != null && anim.type == AnimationType.entering) {
          contribution = controller.getEstimatedExtent(nodeId);
        } else {
          contribution = _nodeExtentsByNid[nid];
        }
        steadyAccum += contribution;
      }
    }

    // Create children for nodes in cache region
    if (cacheEndIndex > cacheStartIndex) {
      invokeLayoutCallback<SliverConstraints>((SliverConstraints constraints) {
        for (int i = cacheStartIndex; i < cacheEndIndex; i++) {
          childManager?.createChild(visibleNodes[i]);
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
      final actualAnimatedExtent = _layoutNodeChild(
        nodeId, crossAxisExtent,
      );
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
      _stickyPrecomputeDirty = true;

      if (_bulkCumulativesValid) {
        // A child's measured size perturbed _fullExtents mid-bulk; the
        // cumulatives are now inconsistent with truth for positions beyond
        // firstChangedIdx. Materialize per-nid extents for the affected
        // tail so _recomputeOffsetsFrom can walk it, then fall back off
        // the fast path for this frame. The next frame will rebuild cumulatives
        // fresh via _rebuildBulkCumulatives.
        for (int i = firstChangedIdx; i < visibleNodes.length; i++) {
          final nodeId = visibleNodes[i];
          if (i >= cacheStartIndex && i < cacheEndIndex) continue;
          final nid = _controller.nidOf(nodeId);
          _nodeExtentsByNid[nid] = controller.getCurrentExtent(nodeId);
        }
        _bulkCumulativesValid = false;
      }

      totalScrollExtent = _recomputeOffsetsFrom(visibleNodes, firstChangedIdx);

      // Only rewrite parentData.layoutOffset for cache-region nodes at or
      // after firstChangedIdx. Earlier cache-region nodes already had the
      // correct value written in the measurement loop above.
      final updateStart = math.max(cacheStartIndex, firstChangedIdx);
      for (int i = updateStart; i < cacheEndIndex; i++) {
        final nodeId = visibleNodes[i];
        final child = getChildForNode(nodeId);
        if (child == null) continue;
        final parentData = child.parentData! as SliverTreeParentData;
        parentData.layoutOffset = _nodeOffsetsByNid[_controller.nidOf(nodeId)];
      }
    }

    // Precompute subtree bottoms BEFORE sticky identification so that
    // _identifyPotentialStickyNodes can use O(1) lookups instead of
    // O(n)-per-candidate subtree scans.
    // Skip during animation: _identifyPotentialStickyNodes bails on animating
    // nodes anyway, so the O(3N) precomputation is wasted. The fallback
    // per-candidate _computeSubtreeBottom is trivially cheap since it also
    // bails immediately.
    // Also skip when nothing changed since last precomputation (pure scrolling).
    if (_animationsWereActive && !hasAnimations) {
      _stickyPrecomputeDirty = true; // animation just settled — one final pass
    }
    if (_maxStickyDepth > 0 && !hasAnimations && _stickyPrecomputeDirty) {
      _precomputeStableSubtreeBottoms(visibleNodes);
      _stickyPrecomputeDirty = false;
    } else if (hasAnimations || _maxStickyDepth == 0) {
      _lastPrecomputedCount = 0; // force fallback to per-candidate scan
    }

    // Throttle sticky header recomputation during animation: only recompute
    // every 3rd frame. Both _identifyPotentialStickyNodes and
    // _computeStickyHeaders bail on animating candidates anyway, so results
    // are approximate and largely unchanged frame-to-frame.
    //
    // Exception: if the user scrolled since the last sticky computation, we
    // MUST recompute. pinnedY is relative to scrollOffset, and stale values
    // produce visible header jitter plus wrong hit-test coordinates.
    final bool scrolledSinceLastSticky =
        _lastStickyScrollOffset != scrollOffset;
    final bool skipStickyRecompute;
    if (controller.hasActiveAnimations && _maxStickyDepth > 0) {
      _stickyThrottleCounter++;
      skipStickyRecompute = !scrolledSinceLastSticky &&
          (_stickyThrottleCounter % 3) != 0;
    } else {
      _stickyThrottleCounter = 0;
      skipStickyRecompute = false;
    }

    if (skipStickyRecompute) {
      // Even when throttling, purge entries for nodes that just started
      // exiting so a stale pinned row doesn't keep painting / inflate
      // paintExtent for another 1–2 frames.
      if (_stickyHeaders.isNotEmpty) {
        _stickyHeaders.removeWhere((s) {
          if (controller.isExiting(s.nodeId)) {
            final nid = _controller.nidOf(s.nodeId);
            if (nid >= 0 && nid < _stickyByNid.length) {
              _stickyByNid[nid] = null;
            }
            return true;
          }
          return false;
        });
      }
    } else {
      // Identify sticky candidates now that offsets and precomputed data are ready.
      final potentialStickyNodes = _identifyPotentialStickyNodes(
        scrollOffset,
        constraints.overlap,
        visibleNodes,
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
        invokeLayoutCallback<SliverConstraints>((SliverConstraints constraints) {
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
          totalScrollExtent = _recomputeOffsets(visibleNodes);
          if (_maxStickyDepth > 0 && !hasAnimations) {
            _precomputeStableSubtreeBottoms(visibleNodes);
            _stickyPrecomputeDirty = false;
          }
        }
        // Always write the newly-created sticky children's layoutOffset —
        // they were outside the cache region during Pass 1 and never had it set.
        for (final nodeId in newStickyNodes) {
          final child = getChildForNode(nodeId);
          if (child == null) continue;
          final parentData = child.parentData! as SliverTreeParentData;
          parentData.layoutOffset = _nodeOffsetsByNid[_controller.nidOf(nodeId)];
        }
      }

      _computeStickyHeaders(scrollOffset, constraints.overlap, visibleNodes);
      _lastStickyScrollOffset = scrollOffset;
    }

    // ────────────────────────────────────────────────────────────────────────
    // Calculate paint extent
    // ────────────────────────────────────────────────────────────────────────
    double paintExtent = 0.0;

    final startIndex = _findFirstVisibleIndex(visibleNodes, scrollOffset);
    for (int i = startIndex; i < visibleNodes.length; i++) {
      final nodeId = visibleNodes[i];
      final nid = _controller.nidOf(nodeId);
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
    for (final sticky in _stickyHeaders) {
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
      hasVisualOverflow: stickyInflationClamped ||
          scrollOffset + paintExtent < totalScrollExtent,
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
    if (hasAnimations && _children.isNotEmpty) {
      for (int i = 0; i < visibleNodes.length; i++) {
        if (i >= cacheStartIndex && i < cacheEndIndex) continue;
        final nodeId = visibleNodes[i];
        final child = getChildForNode(nodeId);
        if (child == null) continue;
        final nid = _controller.nidOf(nodeId);
        final double offset;
        if (_bulkCumulativesValid) {
          // Bulk-only fast path: per-nid offset slots are not kept fresh
          // for out-of-cache-region nids — derive from cumulatives.
          offset = _offsetAtVisibleIndex(i);
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

    // If a caller (TreeReorderController.endDrag) staged a FLIP slide
    // baseline before the structural mutation that triggered this layout,
    // install the slide now — AFTER all parentData.layoutOffset writes so
    // `snapshotVisibleOffsets()` reads the post-mutation structural truth,
    // but BEFORE paint in the same frame so the first paint already renders
    // rows at their prior painted position (slide at progress 0).
    _consumeSlideBaselineIfAny();

    childManager?.didFinishLayout();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAINTING
  // ══════════════════════════════════════════════════════════════════════════

  int _findFirstVisibleIndex(List<TKey> nodes, double scrollOffset) {
    if (nodes.isEmpty) return 0;

    int low = 0;
    int high = nodes.length - 1;

    if (_bulkCumulativesValid && _bulkCumulativesCount == nodes.length) {
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

    while (low < high) {
      final mid = (low + high) ~/ 2;
      final nid = _controller.nidOf(nodes[mid]);
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

    final startIndex = _findFirstVisibleIndex(visibleNodes, scrollOffset);

    // Pass A: Paint non-sticky nodes. Rows with a non-zero slide delta are
    // deferred to a second sub-pass so they paint on top of static rows —
    // without this, an upward-moving row that hasn't yet crossed into its
    // final index slot would be covered by siblings sliding down past it.
    // Among sliding rows, sort by ascending |delta| so the row that moved
    // the most (typically the just-dropped row) paints last and lands on
    // top. Ties preserve natural iteration order.
    List<int>? slidingIndices;
    for (int i = startIndex; i < visibleNodes.length; i++) {
      final nodeId = visibleNodes[i];
      final nid = _controller.nidOf(nodeId);
      if (nid >= 0 && nid < _stickyByNid.length && _stickyByNid[nid] != null) {
        continue;
      }

      final child = getChildForNode(nodeId);
      if (child == null) continue;

      // Paint-only FLIP slide delta — read from the controller on every
      // frame so localToGlobal / semantics (which can resolve between
      // ticks) always see the current value.
      final slideDelta = controller.getSlideDelta(nodeId);

      if (slideDelta != 0.0) {
        (slidingIndices ??= <int>[]).add(i);
        continue;
      }

      _paintRow(
        context: context,
        offset: offset,
        nodeId: nodeId,
        child: child,
        slideDelta: 0.0,
        scrollOffset: scrollOffset,
        remainingPaintExtent: remainingPaintExtent,
      );
    }

    if (slidingIndices != null) {
      slidingIndices.sort((a, b) {
        final da = controller.getSlideDelta(visibleNodes[a]).abs();
        final db = controller.getSlideDelta(visibleNodes[b]).abs();
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
          nodeId: nodeId,
          child: child,
          slideDelta: controller.getSlideDelta(nodeId),
          scrollOffset: scrollOffset,
          remainingPaintExtent: remainingPaintExtent,
        );
      }
    }

    // Pass B: Paint sticky headers (deepest first so shallower paints on top).
    final paintExtent = geometry!.paintExtent;
    for (int i = _stickyHeaders.length - 1; i >= 0; i--) {
      final sticky = _stickyHeaders[i];
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
    required TKey nodeId,
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

    final paintOffset = offset +
        Offset(parentData.indent, nodeOffset - scrollOffset + slideDelta);

    if (controller.isAnimating(nodeId) && nodeExtent < child.size.height) {
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

    // Phase 1: Test sticky headers first (they're visually on top).
    // Iterate shallowest first (index 0) = topmost = first hit priority.
    for (final sticky in _stickyHeaders) {
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

    // Phase 2: Test normal nodes (skip sticky IDs).
    final hitOffset = scrollOffset + mainAxisPosition;
    final startIndex = _findFirstVisibleIndex(visibleNodes, hitOffset);

    for (int i = startIndex; i < visibleNodes.length; i++) {
      final nodeId = visibleNodes[i];
      final nid = _controller.nidOf(nodeId);
      if (nid >= 0 && nid < _stickyByNid.length && _stickyByNid[nid] != null) {
        continue;
      }

      final child = getChildForNode(nodeId);
      if (child == null) continue;

      // Skip exiting nodes - they should not receive interactions
      // This prevents crashes when rapidly tapping delete buttons
      if (controller.isExiting(nodeId)) continue;

      final parentData = child.parentData! as SliverTreeParentData;
      final nodeOffset = parentData.layoutOffset;
      final nodeExtent = parentData.visibleExtent;

      // Shift the hit coordinate by the node's current slide delta so a
      // tap lands on the visually-displaced child rather than on the
      // structural position nobody sees during a slide.
      final slideDelta = controller.getSlideDelta(nodeId);
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
          (controller.isAnimating(nodeId) &&
              nodeExtent < child.size.height)
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
                position: Offset(
                  crossAxisPosition,
                  mainAxisPosition + yAdjust,
                ),
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

    // Check if this child is a sticky header (O(1) lookup).
    if (nodeId != null) {
      final nid = _controller.nidOf(nodeId as TKey);
      if (nid >= 0 && nid < _stickyByNid.length) {
        final sticky = _stickyByNid[nid];
        if (sticky != null) {
          transform.translateByDouble(sticky.indent, sticky.pinnedY, 0.0, 1.0);
          return;
        }
      }
    }

    // Mirror paint's clip-and-translate trick. When a node is animating and
    // its visible extent is smaller than its intrinsic box, paint shifts the
    // child up by (height - extent) so the bottom slice peeks through the
    // clipped strip. The transform must include that same Y shift or callers
    // that resolve via applyPaintTransform (localToGlobal, layer composition,
    // showOnScreen, semantics) will be off by (height - extent) pixels.
    final yAdjust =
        (nodeId != null &&
            controller.isAnimating(nodeId as TKey) &&
            parentData.visibleExtent < child.size.height)
        ? (child.size.height - parentData.visibleExtent)
        : 0.0;

    // Include the node's current slide delta (paint-only FLIP offset) so
    // callers that resolve coordinates via applyPaintTransform — localToGlobal,
    // focus traversal, semantics, Scrollable.ensureVisible — track the
    // visually-displaced row during a slide.
    final slideDelta = nodeId != null
        ? controller.getSlideDelta(nodeId as TKey)
        : 0.0;

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
      final nid = _controller.nidOf(nodeId as TKey);
      if (nid >= 0 && nid < _stickyByNid.length) {
        final sticky = _stickyByNid[nid];
        if (sticky != null) return sticky.pinnedY;
      }
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
