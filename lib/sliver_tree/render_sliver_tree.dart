/// Render object for [SliverTree] that handles sliver layout and painting.
library;

import 'dart:math' as math;

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
    _nodeOffsets.clear();
    _nodeExtents.clear();
    _nodesInCacheRegion.clear();
    _stickyHeaders.clear();
    _stickyNodeIds.clear();
    _stickyById.clear();
    _lastPrecomputedCount = 0;
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

  /// Children by nodeId.
  final Map<TKey, RenderBox> _children = {};

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

  /// Reusable map for node offsets during layout.
  final Map<TKey, double> _nodeOffsets = {};

  /// Reusable map for node extents during layout.
  final Map<TKey, double> _nodeExtents = {};

  /// Reusable set for nodes in the cache region during layout.
  final Set<TKey> _nodesInCacheRegion = {};

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

  /// Fast lookup of sticky node IDs for paint/hit-test.
  final Set<TKey> _stickyNodeIds = {};

  /// Fast lookup of sticky info by node ID for applyPaintTransform.
  final Map<TKey, StickyHeaderInfo<TKey>> _stickyById = {};

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

  /// The set of node IDs that should be retained (in cache region + sticky).
  ///
  /// Updated each layout pass. Used by the element to decide which off-screen
  /// children can be safely evicted.
  Set<TKey> get retainedNodeIds => {..._nodesInCacheRegion, ..._stickyNodeIds};

  /// Gets the child for the given node ID, or null if not present.
  RenderBox? getChildForNode(TKey id) => _children[id];

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
    final parentData = child.parentData! as SliverTreeParentData;
    parentData.nodeId = nodeId;
  }

  /// Removes the child for the specified node.
  void removeChild(RenderBox child, TKey nodeId) {
    _children.remove(nodeId);
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
      final child = _children[sticky.nodeId];
      if (child == null) continue;
      if (controller.getNodeData(sticky.nodeId) == null) continue;
      if (controller.isExiting(sticky.nodeId)) continue;
      visitor(child);
    }
    // Then in-flow visible nodes, skipping any already emitted as sticky.
    for (final nodeId in controller.visibleNodes) {
      if (_stickyNodeIds.contains(nodeId)) continue;
      final child = _children[nodeId];
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
    double stableOffset = _nodeOffsets[nodeId] ?? 0.0;
    stableOffset += _nodeExtents[nodeId] ?? 0.0;
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
        childExtent = _nodeExtents[childId] ?? 0.0;
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
        stableExtent = _nodeExtents[nodeId] ?? 0.0;
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
      final nodeId = visibleNodes[i];
      final actualEnd =
          (_nodeOffsets[nodeId] ?? 0.0) + (_nodeExtents[nodeId] ?? 0.0);

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

      final naturalOffset = _nodeOffsets[candidateId];
      if (naturalOffset == null) break;

      final naturalY = naturalOffset - scrollOffset;
      if (naturalY > stackTop) break;

      final extent = controller.getEstimatedExtent(candidateId);
      final candidateIndex = controller.getVisibleIndex(candidateId);
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
    _stickyHeaders.clear();
    _stickyNodeIds.clear();
    _stickyById.clear();

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
      _stickyNodeIds.add(candidateId);
      _stickyById[candidateId] = info;

      parentPinnedY = pinnedY;
      return true;
    });
  }

  /// Recomputes [_nodeOffsets] from current [_nodeExtents] and returns
  /// the new total scroll extent. Call after Pass 2 when extents have
  /// been updated with actual measured values.
  double _recomputeOffsets(List<TKey> visibleNodes) {
    double offset = 0.0;
    for (final nodeId in visibleNodes) {
      _nodeOffsets[nodeId] = offset;
      offset += _nodeExtents[nodeId] ?? 0.0;
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

    double offset = _nodeOffsets[visibleNodes[fromIndex]] ?? 0.0;
    for (int i = fromIndex; i < visibleNodes.length; i++) {
      final nodeId = visibleNodes[i];
      _nodeOffsets[nodeId] = offset;
      offset += _nodeExtents[nodeId] ?? 0.0;
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
    final child = _children[nodeId];
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

    if (_structureChanged) {
      totalScrollExtent = 0.0;
      _nodeOffsets.clear();
      _nodeExtents.clear();

      for (final nodeId in visibleNodes) {
        _nodeOffsets[nodeId] = totalScrollExtent;
        final extent = controller.getCurrentExtent(nodeId);
        _nodeExtents[nodeId] = extent;
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
          final prevId = visibleNodes[firstAnimIdx - 1];
          totalScrollExtent = (_nodeOffsets[prevId] ?? 0.0)
              + (_nodeExtents[prevId] ?? 0.0);
        }
        for (int i = firstAnimIdx; i < visibleNodes.length; i++) {
          final nodeId = visibleNodes[i];
          final newExtent = controller.getCurrentExtent(nodeId);
          _nodeOffsets[nodeId] = totalScrollExtent;
          _nodeExtents[nodeId] = newExtent;
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
        final oldExtent = _nodeExtents[nodeId];

        if (!foundAnimating && oldExtent != null && oldExtent == newExtent) {
          totalScrollExtent = _nodeOffsets[nodeId]! + newExtent;
        } else {
          foundAnimating = true;
          _nodeOffsets[nodeId] = totalScrollExtent;
          _nodeExtents[nodeId] = newExtent;
          totalScrollExtent += newExtent;
        }
      }
    }

    // ────────────────────────────────────────────────────────────────────────
    // PASS 2: Create children for nodes in cache region
    // ────────────────────────────────────────────────────────────────────────

    _nodesInCacheRegion.clear();
    final nodesInCacheRegion = _nodesInCacheRegion;
    final cacheStartIndex = _findFirstVisibleIndex(visibleNodes, cacheStart);

    int cacheEndIndex = cacheStartIndex;
    for (int i = cacheStartIndex; i < visibleNodes.length; i++) {
      final nodeId = visibleNodes[i];
      final offset = _nodeOffsets[nodeId]!;
      if (offset >= cacheEnd) break;
      nodesInCacheRegion.add(nodeId);
      cacheEndIndex = i + 1;
    }

    // Create children for nodes in cache region
    if (nodesInCacheRegion.isNotEmpty) {
      invokeLayoutCallback<SliverConstraints>((SliverConstraints constraints) {
        for (final nodeId in nodesInCacheRegion) {
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
      final actualAnimatedExtent = _layoutNodeChild(
        nodeId, crossAxisExtent,
      );
      if (actualAnimatedExtent == null) continue;

      final estimatedExtent = _nodeExtents[nodeId]!;
      if (actualAnimatedExtent != estimatedExtent) {
        _nodeExtents[nodeId] = actualAnimatedExtent;
        totalScrollExtent += actualAnimatedExtent - estimatedExtent;
        extentsChanged = true;
        if (i < firstChangedIdx) firstChangedIdx = i;
      }

      final child = _children[nodeId]!;
      final parentData = child.parentData! as SliverTreeParentData;
      parentData.layoutOffset = _nodeOffsets[nodeId]!;
    }

    // Only recompute offsets if actual extents differed from estimates.
    // During steady-state animation (constraint cache hit → same sizes),
    // this skips the full O(N) recomputation. When extents did change,
    // only walk from the first changed index forward — offsets before
    // that point are unaffected by later-index extent changes.
    if (extentsChanged) {
      _stickyPrecomputeDirty = true;
      totalScrollExtent = _recomputeOffsetsFrom(visibleNodes, firstChangedIdx);

      // Only rewrite parentData.layoutOffset for cache-region nodes at or
      // after firstChangedIdx. Earlier cache-region nodes already had the
      // correct value written in the measurement loop above.
      final updateStart = math.max(cacheStartIndex, firstChangedIdx);
      for (int i = updateStart; i < cacheEndIndex; i++) {
        final nodeId = visibleNodes[i];
        final child = _children[nodeId];
        if (child == null) continue;
        final parentData = child.parentData! as SliverTreeParentData;
        parentData.layoutOffset = _nodeOffsets[nodeId] ?? 0.0;
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
            _stickyNodeIds.remove(s.nodeId);
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
      final newStickyNodes = potentialStickyNodes.difference(nodesInCacheRegion);
      if (newStickyNodes.isNotEmpty) {
        invokeLayoutCallback<SliverConstraints>((SliverConstraints constraints) {
          for (final nodeId in newStickyNodes) {
            childManager?.createChild(nodeId);
          }
        });
        for (final nodeId in newStickyNodes) {
          final extent = _layoutNodeChild(
            nodeId, crossAxisExtent,
          );
          if (extent != null) {
            _nodeExtents[nodeId] = extent;
          }
        }
        // Recompute offsets again since new sticky nodes may have changed extents.
        totalScrollExtent = _recomputeOffsets(visibleNodes);
        for (final nodeId in newStickyNodes) {
          final child = _children[nodeId];
          if (child == null) continue;
          final parentData = child.parentData! as SliverTreeParentData;
          parentData.layoutOffset = _nodeOffsets[nodeId] ?? 0.0;
        }
        // Re-precompute subtree bottoms with updated extents.
        if (_maxStickyDepth > 0 && !hasAnimations) {
          _precomputeStableSubtreeBottoms(visibleNodes);
          _stickyPrecomputeDirty = false;
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
      final offset = _nodeOffsets[nodeId]!;
      final extent = _nodeExtents[nodeId]!;
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

    _lastVisibleNodeCount = visibleNodes.length;
    _lastTotalScrollExtent = totalScrollExtent;
    _animationsWereActive = hasAnimations;
    childManager?.didFinishLayout();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAINTING
  // ══════════════════════════════════════════════════════════════════════════

  int _findFirstVisibleIndex(List<TKey> nodes, double scrollOffset) {
    if (nodes.isEmpty) return 0;

    int low = 0;
    int high = nodes.length - 1;

    while (low < high) {
      final mid = (low + high) ~/ 2;
      final nodeId = nodes[mid];
      final offset = _nodeOffsets[nodeId] ?? 0.0;
      final extent = _nodeExtents[nodeId] ?? 0.0;

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

    // Pass A: Paint non-sticky nodes normally.
    for (int i = startIndex; i < visibleNodes.length; i++) {
      final nodeId = visibleNodes[i];
      if (_stickyNodeIds.contains(nodeId)) continue;

      final child = _children[nodeId];
      if (child == null) continue;

      final parentData = child.parentData! as SliverTreeParentData;
      final nodeOffset = parentData.layoutOffset;
      final nodeExtent = parentData.visibleExtent;

      if (nodeOffset >= scrollOffset + remainingPaintExtent) break;

      final paintOffset =
          offset + Offset(parentData.indent, nodeOffset - scrollOffset);

      // Clip if animating (individual or bulk) and extent is less than full size
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

    // Pass B: Paint sticky headers (deepest first so shallower paints on top).
    final paintExtent = geometry!.paintExtent;
    for (int i = _stickyHeaders.length - 1; i >= 0; i--) {
      final sticky = _stickyHeaders[i];
      final child = _children[sticky.nodeId];
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
      final child = _children[sticky.nodeId];
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
      if (_stickyNodeIds.contains(nodeId)) continue;

      final child = _children[nodeId];
      if (child == null) continue;

      // Skip exiting nodes - they should not receive interactions
      // This prevents crashes when rapidly tapping delete buttons
      if (controller.isExiting(nodeId)) continue;

      final parentData = child.parentData! as SliverTreeParentData;
      final nodeOffset = parentData.layoutOffset;
      final nodeExtent = parentData.visibleExtent;

      final localMainAxisPosition =
          mainAxisPosition + scrollOffset - nodeOffset;
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

      final hit = result.addWithAxisOffset(
        paintOffset: Offset(parentData.indent, nodeOffset - scrollOffset),
        mainAxisOffset: nodeOffset - scrollOffset,
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
      final sticky = _stickyById[nodeId];
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
        (nodeId != null &&
            controller.isAnimating(nodeId as TKey) &&
            parentData.visibleExtent < child.size.height)
        ? (child.size.height - parentData.visibleExtent)
        : 0.0;

    final scrollOffset = constraints.scrollOffset;
    transform.translateByDouble(
      parentData.indent,
      parentData.layoutOffset - scrollOffset - yAdjust,
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
      final sticky = _stickyById[nodeId];
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
