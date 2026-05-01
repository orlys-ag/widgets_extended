/// Internal: sticky-header layout helper for [RenderSliverTree].
///
/// Owns every piece of state that exists solely to compute and cache
/// sticky-header positions: the per-frame throttle counter, the
/// last-computed-at scroll offset, the precompute scratch arrays, and the
/// nid-indexed sticky lookup. Extracted from the render object so the
/// sticky logic is testable in isolation by feeding precomputed offsets
/// and extents in directly.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'tree_controller.dart';
import 'types.dart';

/// Resolves a scroll offset to the first visible-position index whose
/// row's bottom edge is past it.
///
/// The render object uses a binary search over per-nid offsets, with a
/// special-case fast path when the bulk-only cumulatives are valid. The
/// computer accepts that resolver as a callback rather than reimplementing
/// it, so the bulk-fast-path knowledge stays inside the render object.
typedef FindFirstVisibleIndex = int Function(double scrollOffset);

/// Computes sticky headers and owns the scratch state required for the
/// computation. The owning render object hands in the per-frame inputs
/// (visible nodes, layout-space offsets and extents, scroll position) and
/// reads back the computed [headers] / [infoForNid] for paint, hit-test,
/// and transform.
///
/// The computer is **layout-state-shaped**: a single instance is
/// long-lived per render object and mutated in place each layout. Reset
/// it via [reset] when the underlying controller swaps.
class StickyHeaderComputer<TKey, TData> {
  StickyHeaderComputer({
    required TreeController<TKey, TData> controller,
    int maxStickyDepth = 0,
  }) : _controller = controller,
       _maxStickyDepth = maxStickyDepth;

  TreeController<TKey, TData> _controller;
  TreeController<TKey, TData> get controller => _controller;
  set controller(TreeController<TKey, TData> value) {
    if (identical(_controller, value)) return;
    _controller = value;
  }

  int _maxStickyDepth;
  int get maxStickyDepth => _maxStickyDepth;
  set maxStickyDepth(int value) {
    _maxStickyDepth = value;
  }

  // ────────────────────────────────────────────────────────────────────────
  // PER-FRAME LAYOUT STATE
  // ────────────────────────────────────────────────────────────────────────

  /// Frame counter for throttling sticky recomputation during animation.
  int _throttleCounter = 0;

  /// Scroll offset observed on the last frame that computed sticky
  /// headers. Used to force a recompute when the user scrolls during an
  /// animation, so sticky [pinnedY] values don't lag behind the actual
  /// scroll position. NaN means "never computed."
  double _lastStickyScrollOffset = double.nan;

  /// Whether sticky subtree precomputation needs to re-run. Set on
  /// structure change, extent change, or animation-to-idle transition;
  /// cleared by [precomputeStableSubtreeBottoms].
  bool dirty = true;

  /// Computed sticky headers for the current layout, ordered root→leaf.
  final List<StickyHeaderInfo<TKey>> _stickyHeaders = [];

  /// Sticky header info indexed by nid. Null when the node is not
  /// currently a sticky header. Doubles as the membership flag used by
  /// paint, hit-test, transform, and `isNodeRetained`.
  List<StickyHeaderInfo<TKey>?> _stickyByNid = <StickyHeaderInfo<TKey>?>[];

  /// Nids written into [_stickyByNid] this frame. Tracked separately from
  /// [_stickyHeaders] so the next frame's clear loop can null its slots
  /// without going through `nidOf(sticky.nodeId)` — a freed key would
  /// resolve to `noNid` and the slot would survive into the next frame,
  /// leaking stickiness onto whichever fresh key recycles that nid.
  ///
  /// Backed by an [Int32List] with explicit length tracking
  /// ([_writtenStickyNidsLen]) so per-frame appends don't box ints.
  /// Capacity is bounded by [_maxStickyDepth] in practice.
  Int32List _writtenStickyNids = Int32List(8);
  int _writtenStickyNidsLen = 0;

  // ────────────────────────────────────────────────────────────────────────
  // PRECOMPUTE SCRATCH (rebuilt each layout, reused across frames)
  // ────────────────────────────────────────────────────────────────────────

  Int32List _depthScratch = Int32List(0);
  Float64List _stablePrefix = Float64List(0);
  Int32List _subtreeEndIndex = Int32List(0);
  Float64List _subtreeBottomByIndex = Float64List(0);
  Int32List _indexStack = Int32List(0);
  int _indexStackLen = 0;
  int _lastPrecomputedCount = 0;

  // ────────────────────────────────────────────────────────────────────────
  // PUBLIC READ API (consumed by paint, hit-test, transform, semantics)
  // ────────────────────────────────────────────────────────────────────────

  /// All sticky headers in root→leaf order. The render object iterates
  /// this from index 0 (shallowest, painted last so it lands on top).
  List<StickyHeaderInfo<TKey>> get headers => _stickyHeaders;

  /// Sticky info for [nid], or null when the node is not currently
  /// sticky. Hot-path lookup used by paint transform and retention checks.
  StickyHeaderInfo<TKey>? infoForNid(int nid) {
    if (nid < 0 || nid >= _stickyByNid.length) return null;
    return _stickyByNid[nid];
  }

  /// Whether [nid] is currently sticky.
  bool isSticky(int nid) => infoForNid(nid) != null;

  // ────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ────────────────────────────────────────────────────────────────────────

  /// Resets every piece of layout-derived state to the empty defaults the
  /// render object uses on first layout. Call when the controller swaps
  /// or the render object is hot-reloaded.
  void reset() {
    _stickyByNid = <StickyHeaderInfo<TKey>?>[];
    _stickyHeaders.clear();
    _writtenStickyNidsLen = 0;
    dirty = true;
    _lastStickyScrollOffset = double.nan;
    _lastPrecomputedCount = 0;
    _throttleCounter = 0;
  }

  /// Grows the nid-indexed sticky array to match the controller's current
  /// nid capacity. Called from the render object's layout-array growth
  /// path so all per-nid arrays stay in lockstep.
  void resizeForCapacity(int nidCapacity) {
    if (nidCapacity <= _stickyByNid.length) return;
    final newSticky = List<StickyHeaderInfo<TKey>?>.filled(nidCapacity, null);
    for (int i = 0; i < _stickyByNid.length; i++) {
      newSticky[i] = _stickyByNid[i];
    }
    _stickyByNid = newSticky;
  }

  /// Forces the next layout to take the per-candidate fallback path
  /// instead of the precomputed-array path. Used during animation frames
  /// where the cached subtree bottoms are stale.
  void invalidatePrecompute() {
    _lastPrecomputedCount = 0;
  }

  /// Reallocates scratch arrays to fit [_lastPrecomputedCount] (or empty
  /// if zero). Call when the tree shrinks significantly and memory
  /// matters.
  void trimScratchArrays() {
    final n = _lastPrecomputedCount;
    if (n == 0) {
      _depthScratch = Int32List(0);
      _stablePrefix = Float64List(0);
      _subtreeEndIndex = Int32List(0);
      _subtreeBottomByIndex = Float64List(0);
    } else {
      _depthScratch = Int32List(n);
      _stablePrefix = Float64List(n + 1);
      _subtreeEndIndex = Int32List(n);
      _subtreeBottomByIndex = Float64List(n);
    }
  }

  /// Pre-allocates scratch arrays for [capacity] nodes. Useful when the
  /// tree size is known upfront to avoid incremental resizing.
  void resizeScratchArrays(int capacity) {
    if (capacity <= 0) {
      _depthScratch = Int32List(0);
      _stablePrefix = Float64List(0);
      _subtreeEndIndex = Int32List(0);
      _subtreeBottomByIndex = Float64List(0);
    } else {
      _depthScratch = Int32List(capacity);
      _stablePrefix = Float64List(capacity + 1);
      _subtreeEndIndex = Int32List(capacity);
      _subtreeBottomByIndex = Float64List(capacity);
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // THROTTLING DECISION
  // ────────────────────────────────────────────────────────────────────────

  /// Returns true when sticky should be recomputed this frame. The
  /// throttle keeps mid-animation frames cheap (every third frame) but
  /// fires on every scroll, since stale `pinnedY` values produce visible
  /// jitter and wrong hit-test coordinates.
  bool shouldRecomputeThisFrame({
    required bool hasActiveAnimations,
    required double scrollOffset,
  }) {
    final scrolledSinceLast = _lastStickyScrollOffset != scrollOffset;
    if (hasActiveAnimations && _maxStickyDepth > 0) {
      _throttleCounter++;
      return scrolledSinceLast || (_throttleCounter % 3) == 0;
    }
    _throttleCounter = 0;
    return true;
  }

  /// During a throttle-skip frame, drop sticky entries whose node just
  /// entered exiting state. Without this, a stale pinned row would keep
  /// painting / inflating paintExtent for another 1–2 frames until the
  /// next non-throttled recompute.
  void purgeExitingDuringThrottle() {
    if (_stickyHeaders.isEmpty) return;
    // Track removals so [_writtenStickyNids] stays in sync with
    // [_stickyByNid] for the next recompute's clear loop.
    final purgedNids = <int>{};
    _stickyHeaders.removeWhere((s) {
      if (_controller.isExiting(s.nodeId)) {
        final nid = _controller.nidOf(s.nodeId);
        if (nid >= 0 && nid < _stickyByNid.length) {
          _stickyByNid[nid] = null;
          purgedNids.add(nid);
        }
        return true;
      }
      return false;
    });
    if (purgedNids.isNotEmpty) {
      // In-place compaction over the typed-data scratch buffer.
      int writeIdx = 0;
      for (int readIdx = 0; readIdx < _writtenStickyNidsLen; readIdx++) {
        final nid = _writtenStickyNids[readIdx];
        if (!purgedNids.contains(nid)) {
          _writtenStickyNids[writeIdx++] = nid;
        }
      }
      _writtenStickyNidsLen = writeIdx;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // PRECOMPUTE PASS
  // ────────────────────────────────────────────────────────────────────────

  /// Precomputes subtree bottom offsets for all visible nodes in O(N).
  ///
  /// Uses the same "entering nodes contribute their full estimated extent"
  /// logic as the per-candidate fallback, but does it for the entire
  /// visible list in three linear passes instead of a per-candidate
  /// descent.
  ///
  /// Reads layout-space offsets and extents directly from the per-nid
  /// arrays passed in. Caller is responsible for ensuring those arrays
  /// are fresh.
  void precomputeStableSubtreeBottoms({
    required List<TKey> visibleNodes,
    required Float64List nodeOffsetsByNid,
    required Float64List nodeExtentsByNid,
  }) {
    final n = visibleNodes.length;
    if (n == 0) return;

    if (_depthScratch.length < n) {
      _depthScratch = Int32List(n);
      _subtreeEndIndex = Int32List(n);
      _subtreeBottomByIndex = Float64List(n);
      _stablePrefix = Float64List(n + 1);
    }
    _stablePrefix[0] = 0.0;

    final orderNids = _controller.orderNidsView;

    // Pass A: depths + stable prefix sums.
    for (int i = 0; i < n; i++) {
      final nid = orderNids[i];
      final depth = _controller.depthOfNid(nid);
      _depthScratch[i] = depth;

      final nodeId = visibleNodes[i];
      final anim = _controller.getAnimationState(nodeId);
      final double stableExtent;
      if (anim != null && anim.type == AnimationType.entering) {
        // Use full extent so ancestor push-up doesn't bounce during expand.
        stableExtent = _controller.getEstimatedExtentNid(nid);
      } else {
        stableExtent = nodeExtentsByNid[nid];
      }
      _stablePrefix[i + 1] = _stablePrefix[i] + stableExtent;
    }

    // Pass B: subtree end index for each node using a monotonic depth stack.
    // _indexStack is an Int32List + explicit length; bound is n entries.
    if (_indexStack.length < n) {
      _indexStack = Int32List(n);
    }
    _indexStackLen = 0;
    for (int i = 0; i < n; i++) {
      final depth = _depthScratch[i];
      while (_indexStackLen > 0 &&
          depth <= _depthScratch[_indexStack[_indexStackLen - 1]]) {
        final j = _indexStack[--_indexStackLen];
        _subtreeEndIndex[j] = i - 1;
      }
      _indexStack[_indexStackLen++] = i;
    }
    while (_indexStackLen > 0) {
      final j = _indexStack[--_indexStackLen];
      _subtreeEndIndex[j] = n - 1;
    }

    // Pass C: subtree bottom per node.
    // For each node i: bottom = (node's actual end) + (stable sum of
    // descendants).
    for (int i = 0; i < n; i++) {
      final nid = orderNids[i];
      final actualEnd = nodeOffsetsByNid[nid] + nodeExtentsByNid[nid];
      final end = _subtreeEndIndex[i];
      final descendantStableSum =
          _stablePrefix[end + 1] - _stablePrefix[i + 1];
      _subtreeBottomByIndex[i] = actualEnd + descendantStableSum;
    }
    _lastPrecomputedCount = n;
  }

  // ────────────────────────────────────────────────────────────────────────
  // CANDIDATE PROBE & COMPUTE
  // ────────────────────────────────────────────────────────────────────────

  /// Returns the ancestor of [nodeId] at the given [targetDepth], or null.
  TKey? _ancestorAtDepth(TKey nodeId, int targetDepth) {
    TKey? current = nodeId;
    while (current != null) {
      final depth = _controller.getDepth(current);
      if (depth == targetDepth) return current;
      if (depth < targetDepth) return null;
      current = _controller.getParent(current);
    }
    return null;
  }

  /// Walks down sticky candidates by depth, calling [onCandidate] for
  /// each valid level. Stops when the chain breaks (animation, no
  /// children, etc.) or [onCandidate] returns false.
  ///
  /// Shared probe logic for both [identifyPotentialStickyNodes] and
  /// [computeStickyHeaders]. [nodeExtentsByNid] is only consulted by the
  /// per-candidate fallback subtree-bottom scan; it is read every call so
  /// the fallback can avoid stashing it on a nullable field.
  void _forEachStickyCandidate({
    required double scrollOffset,
    required double overlap,
    required List<TKey> visibleNodes,
    required Float64List nodeOffsetsByNid,
    required Float64List nodeExtentsByNid,
    required FindFirstVisibleIndex findFirstVisibleIndex,
    required bool Function(
      TKey candidateId,
      double pinnedY,
      double extent,
      double stackTop,
    )
    onCandidate,
  }) {
    if (_maxStickyDepth <= 0 || visibleNodes.isEmpty) return;

    double stackTop = math.max(0.0, overlap);
    TKey? parentStickyId;

    for (int targetDepth = 0; targetDepth < _maxStickyDepth; targetDepth++) {
      final probeScrollY = scrollOffset + stackTop;
      final probeIndex = findFirstVisibleIndex(probeScrollY);
      if (probeIndex >= visibleNodes.length) break;

      final nodeAtProbe = visibleNodes[probeIndex];
      final candidateId = _ancestorAtDepth(nodeAtProbe, targetDepth);
      if (candidateId == null) break;

      if (parentStickyId != null &&
          _controller.getParent(candidateId) != parentStickyId) {
        break;
      }
      if (_controller.isAnimating(candidateId)) break;
      if (!_controller.hasChildren(candidateId)) break;

      // Candidate must be in the current visible list — otherwise its
      // offset slot holds stale data from a prior layout pass (or zero).
      final candidateIndex = _controller.getVisibleIndex(candidateId);
      if (candidateIndex < 0) break;
      final naturalOffset = nodeOffsetsByNid[_controller.nidOf(candidateId)];

      final naturalY = naturalOffset - scrollOffset;
      if (naturalY > stackTop) break;

      final extent = _controller.getEstimatedExtent(candidateId);
      final subtreeBottom = (candidateIndex < _lastPrecomputedCount)
          ? _subtreeBottomByIndex[candidateIndex]
          : _computeSubtreeBottomFallback(
              candidateId,
              visibleNodes,
              nodeOffsetsByNid,
              nodeExtentsByNid,
            );
      final pushUpY = (subtreeBottom - scrollOffset) - extent;
      final pinnedY = math.min(stackTop, pushUpY);

      if (pinnedY + extent <= stackTop) break;

      if (!onCandidate(candidateId, pinnedY, extent, stackTop)) break;

      parentStickyId = candidateId;
      stackTop = pinnedY + extent;
    }
  }

  /// Per-candidate fallback subtree-bottom scan, used when the precompute
  /// is invalidated (e.g. during animation). Walks descendants from the
  /// candidate's index forward, accumulating stable extents (full for
  /// entering nodes to prevent ancestor bounce). Reads per-nid extents
  /// directly from [nodeExtentsByNid] — same direct typed-array access
  /// pattern the original render-object implementation used.
  double _computeSubtreeBottomFallback(
    TKey nodeId,
    List<TKey> visibleNodes,
    Float64List nodeOffsetsByNid,
    Float64List nodeExtentsByNid,
  ) {
    final index = _controller.getVisibleIndex(nodeId);
    if (index < 0) return 0.0;
    final nodeDepth = _controller.getDepth(nodeId);

    final orderNids = _controller.orderNidsView;
    final nid = orderNids[index];
    double stableOffset = nodeOffsetsByNid[nid];
    stableOffset += nodeExtentsByNid[nid];
    double bottom = stableOffset;

    for (int i = index + 1; i < visibleNodes.length; i++) {
      final childNid = orderNids[i];
      if (_controller.depthOfNid(childNid) <= nodeDepth) break;

      final childId = visibleNodes[i];
      final animation = _controller.getAnimationState(childId);
      final double childExtent;
      if (animation != null && animation.type == AnimationType.entering) {
        childExtent = _controller.getEstimatedExtentNid(childNid);
      } else {
        childExtent = nodeExtentsByNid[childNid];
      }
      final childEnd = stableOffset + childExtent;
      if (childEnd > bottom) bottom = childEnd;
      stableOffset += childExtent;
    }
    return bottom;
  }

  /// Lightweight pre-pass that identifies nodes which might need to be
  /// sticky. Used before Pass 2 to force-create their render objects.
  Set<TKey> identifyPotentialStickyNodes({
    required double scrollOffset,
    required double overlap,
    required List<TKey> visibleNodes,
    required Float64List nodeOffsetsByNid,
    required Float64List nodeExtentsByNid,
    required FindFirstVisibleIndex findFirstVisibleIndex,
  }) {
    final result = <TKey>{};
    _forEachStickyCandidate(
      scrollOffset: scrollOffset,
      overlap: overlap,
      visibleNodes: visibleNodes,
      nodeOffsetsByNid: nodeOffsetsByNid,
      nodeExtentsByNid: nodeExtentsByNid,
      findFirstVisibleIndex: findFirstVisibleIndex,
      onCandidate: (candidateId, pinnedY, extent, stackTop) {
        result.add(candidateId);
        return true;
      },
    );
    return result;
  }

  /// Computes sticky headers based on scroll position, populating
  /// [headers] and the per-nid lookup. Called after Pass 2 when actual
  /// extents and offsets are available. [overlap] is `constraints.overlap`
  /// — the number of pixels at the top covered by a preceding pinned
  /// sliver (e.g. PinnedHeaderSliver).
  void computeStickyHeaders({
    required double scrollOffset,
    required double overlap,
    required List<TKey> visibleNodes,
    required Float64List nodeOffsetsByNid,
    required Float64List nodeExtentsByNid,
    required FindFirstVisibleIndex findFirstVisibleIndex,
  }) {
    // Null out prior-layout sticky entries before recomputing. Iterate
    // [_writtenStickyNids] (the nids we wrote LAST frame) instead of
    // resolving keys back to nids — a key that was freed since last
    // layout (immediate-purge removal) would yield `noNid`, leaving the
    // stale entry to leak stickiness onto whichever fresh key recycles
    // the nid. The nid handle is stable until reallocation, so clearing
    // through it is correct even when the original occupant is gone.
    for (int i = 0; i < _writtenStickyNidsLen; i++) {
      final nid = _writtenStickyNids[i];
      if (nid >= 0 && nid < _stickyByNid.length) {
        _stickyByNid[nid] = null;
      }
    }
    _writtenStickyNidsLen = 0;
    _stickyHeaders.clear();

    double? parentPinnedY;
    _forEachStickyCandidate(
      scrollOffset: scrollOffset,
      overlap: overlap,
      visibleNodes: visibleNodes,
      nodeOffsetsByNid: nodeOffsetsByNid,
      nodeExtentsByNid: nodeExtentsByNid,
      findFirstVisibleIndex: findFirstVisibleIndex,
      onCandidate: (candidateId, pinnedY, extent, stackTop) {
        // Deeper headers can slide behind parent, but must never go above
        // parent TOP.
        if (parentPinnedY != null) {
          pinnedY = math.max(parentPinnedY!, pinnedY);
          if (pinnedY + extent <= stackTop) return false;
        }

        final indent = _controller.getIndent(candidateId);
        final info = StickyHeaderInfo<TKey>(
          nodeId: candidateId,
          pinnedY: pinnedY,
          extent: extent,
          indent: indent,
        );
        _stickyHeaders.add(info);
        final nid = _controller.nidOf(candidateId);
        _stickyByNid[nid] = info;
        if (_writtenStickyNidsLen == _writtenStickyNids.length) {
          final grown = Int32List(_writtenStickyNids.length * 2);
          grown.setRange(0, _writtenStickyNidsLen, _writtenStickyNids);
          _writtenStickyNids = grown;
        }
        _writtenStickyNids[_writtenStickyNidsLen++] = nid;

        parentPinnedY = pinnedY;
        return true;
      },
    );
    _lastStickyScrollOffset = scrollOffset;
  }
}
