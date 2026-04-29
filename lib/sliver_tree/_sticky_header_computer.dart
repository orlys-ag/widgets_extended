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

/// Resolves a key to its visible-position index.
///
/// The render object uses a binary search over per-nid offsets, with a
/// special-case fast path when the bulk-only cumulatives are valid. The
/// computer accepts that resolver as a callback rather than reimplementing
/// it, so the bulk-fast-path knowledge stays inside the render object.
typedef FindFirstVisibleIndex<TKey> =
    int Function(List<TKey> visibleNodes, double scrollOffset);

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

  // ────────────────────────────────────────────────────────────────────────
  // PRECOMPUTE SCRATCH (rebuilt each layout, reused across frames)
  // ────────────────────────────────────────────────────────────────────────

  List<int> _depthScratch = List<int>.empty();
  List<double> _stablePrefix = List<double>.empty();
  List<int> _subtreeEndIndex = List<int>.empty();
  List<double> _subtreeBottomByIndex = List<double>.empty();
  final List<int> _indexStack = <int>[];
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
    _stickyHeaders.removeWhere((s) {
      if (_controller.isExiting(s.nodeId)) {
        final nid = _controller.nidOf(s.nodeId);
        if (nid >= 0 && nid < _stickyByNid.length) {
          _stickyByNid[nid] = null;
        }
        return true;
      }
      return false;
    });
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
      _depthScratch = List<int>.filled(n, 0);
      _subtreeEndIndex = List<int>.filled(n, 0);
      _subtreeBottomByIndex = List<double>.filled(n, 0.0);
      _stablePrefix = List<double>.filled(n + 1, 0.0);
    }
    _stablePrefix[0] = 0.0;

    // Pass A: depths + stable prefix sums.
    for (int i = 0; i < n; i++) {
      final nodeId = visibleNodes[i];
      final depth = _controller.getDepth(nodeId);
      _depthScratch[i] = depth;

      final anim = _controller.getAnimationState(nodeId);
      final double stableExtent;
      if (anim != null && anim.type == AnimationType.entering) {
        // Use full extent so ancestor push-up doesn't bounce during expand.
        stableExtent = _controller.getEstimatedExtent(nodeId);
      } else {
        stableExtent = nodeExtentsByNid[_controller.nidOf(nodeId)];
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
    // For each node i: bottom = (node's actual end) + (stable sum of
    // descendants).
    for (int i = 0; i < n; i++) {
      final nid = _controller.nidOf(visibleNodes[i]);
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
    required FindFirstVisibleIndex<TKey> findFirstVisibleIndex,
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
      final probeIndex = findFirstVisibleIndex(visibleNodes, probeScrollY);
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

    final nid = _controller.nidOf(nodeId);
    double stableOffset = nodeOffsetsByNid[nid];
    stableOffset += nodeExtentsByNid[nid];
    double bottom = stableOffset;

    for (int i = index + 1; i < visibleNodes.length; i++) {
      final childId = visibleNodes[i];
      if (_controller.getDepth(childId) <= nodeDepth) break;

      final animation = _controller.getAnimationState(childId);
      final double childExtent;
      if (animation != null && animation.type == AnimationType.entering) {
        childExtent = _controller.getEstimatedExtent(childId);
      } else {
        childExtent = nodeExtentsByNid[_controller.nidOf(childId)];
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
    required FindFirstVisibleIndex<TKey> findFirstVisibleIndex,
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
    required FindFirstVisibleIndex<TKey> findFirstVisibleIndex,
  }) {
    // Null out prior-layout sticky entries before recomputing. The nid
    // slots for nodes that remain sticky this frame are rewritten below;
    // slots for nodes that no longer qualify stay null, which doubles as
    // the "is-sticky" membership test used by paint/hit-test/semantics.
    for (final sticky in _stickyHeaders) {
      final nid = _controller.nidOf(sticky.nodeId);
      if (nid >= 0 && nid < _stickyByNid.length) {
        _stickyByNid[nid] = null;
      }
    }
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
        _stickyByNid[_controller.nidOf(candidateId)] = info;

        parentPinnedY = pinnedY;
        return true;
      },
    );
    _lastStickyScrollOffset = scrollOffset;
  }
}
