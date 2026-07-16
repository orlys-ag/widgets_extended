/// Orchestrates drag-and-drop reorder over a [TreeController]-backed
/// [SliverTree]: gesture lifecycle, drop-target resolution, autoscroll near
/// viewport edges, and FLIP slide animation on commit.
///
/// The controller is **stateless when idle** — it holds no per-frame state
/// outside an active drag. A drag session begins with [startDrag], receives
/// pointer updates via [updateDrag], and ends with [endDrag] (commit) or
/// [cancelDrag] (no-op). Only one session can be active at a time.
///
/// Coordinate space is exclusively **scroll-space** (distance from the start
/// of the sliver's scroll extent, matching [SliverTreeParentData.layoutOffset]
/// and [RenderSliverTree.snapshotVisibleOffsets]). The global pointer is
/// converted once per [updateDrag].
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'render_sliver_tree.dart';
import 'tree_controller.dart';

/// Where the pointer lies relative to a candidate drop-target row.
enum TreeDropZone {
  /// Insert the dragged node as a sibling above [TreeDropTarget.targetKey].
  above,

  /// Insert the dragged node as the first child of [TreeDropTarget.targetKey].
  into,

  /// Insert the dragged node as a sibling below [TreeDropTarget.targetKey].
  below,
}

/// Resolved drop target for the current pointer position during a drag.
///
/// Immutable snapshot produced by [TreeReorderController] from the pointer
/// and the current visible-offset snapshot. Used to draw the drop indicator
/// and to commit the reorder on drag end.
@immutable
class TreeDropTarget<TKey> {
  const TreeDropTarget({
    required this.targetKey,
    required this.zone,
    required this.parentKey,
    required this.indexInFinalList,
    required this.depth,
    required this.indicatorScrollY,
    required this.indicatorIndent,
  });

  /// The row the pointer is over.
  final TKey targetKey;

  /// Where the pointer sits relative to [targetKey].
  final TreeDropZone zone;

  /// The dragged node's new parent after commit. `null` means "root".
  final TKey? parentKey;

  /// The index the dragged node should occupy **in the final sibling list**
  /// of [parentKey] after the move / reorder has completed.
  ///
  /// - Cross-parent drops: pass directly to
  ///   [TreeController.moveNode] as `index`.
  /// - Same-parent drops: build a live sibling list with the dragged key
  ///   removed and re-inserted at this index, then pass to
  ///   [TreeController.reorderChildren] / [TreeController.reorderRoots].
  final int indexInFinalList;

  /// Depth of the dragged node **after** the move, for indicator indent.
  final int depth;

  /// **Viewport scroll-space** y where the indicator line should be drawn:
  /// distance from the top of the viewport's total scroll extent, including
  /// any slivers that precede the tree. Subtract the scrollable's
  /// `position.pixels` to convert to viewport-local. (Sliver-local row
  /// offsets — the space `RenderSliverTree.findRowAtPaintedY` speaks —
  /// differ from this by the tree sliver's `precedingScrollExtent`.)
  final double indicatorScrollY;

  /// Horizontal inset for the indicator line, computed from [depth] and
  /// the tree's indent-per-depth.
  final double indicatorIndent;
}

/// Per-drag state held only while a drag is active.
class _DragSession<TKey> {
  _DragSession({
    required this.draggedKey,
    required this.renderObject,
    required this.scrollable,
    required this.indentPerDepth,
    required this.pointerGlobal,
  });

  final TKey draggedKey;
  final RenderSliverTree<TKey, Object?> renderObject;
  final ScrollableState scrollable;
  final double indentPerDepth;

  /// Latest pointer position in global coordinates. Updated on every
  /// [TreeReorderController.updateDrag] call so the autoscroll ticker
  /// can re-evaluate without an extra callback plumbing.
  Offset pointerGlobal;

  TreeDropTarget<TKey>? currentTarget;
}

/// Controls a drag-and-drop reorder over a [TreeController].
///
/// Owns an autoscroll [Ticker] for edge-zone scrolling. Not usable with a
/// comparator-based controller (auto-sort would override user order) —
/// the constructor throws [ArgumentError] in that case.
///
/// Extends [ChangeNotifier]: listeners are notified whenever
/// [currentTarget] changes or the drag session begins/ends. Consumers
/// that need to repaint per-pointer-move (like the built-in drop
/// indicator) subscribe here instead of polling per-frame.
class TreeReorderController<TKey, TData> extends ChangeNotifier {
  TreeReorderController({
    required this.treeController,
    required TickerProvider vsync,
    this.canReorder,
    this.canAcceptDrop,
    this.slideDuration = const Duration(milliseconds: 220),
    this.slideCurve = Curves.easeOutCubic,
    this.autoScrollEdgeZone = 48.0,
    this.autoScrollMaxVelocity = 1200.0,
  }) {
    // Runtime check in all build modes — asserts disappear in release.
    if (treeController.comparator != null) {
      throw ArgumentError.value(
        treeController,
        "treeController",
        "TreeReorderController is incompatible with a comparator-based "
        "TreeController: comparator auto-sort would override drag order. "
        "Pass a controller with comparator: null, or remove the comparator.",
      );
    }
    _autoScrollTicker = vsync.createTicker(_onAutoScrollTick);
  }

  /// The tree controller to mutate on drop.
  final TreeController<TKey, TData> treeController;

  /// If set, rows for which this returns false cannot be dragged.
  final bool Function(TKey key)? canReorder;

  /// If set, rejected drop targets are filtered out. Receives the dragged
  /// key, the candidate new parent, and the final-list index.
  final bool Function({
    required TKey movingKey,
    TKey? newParent,
    int? index,
  })? canAcceptDrop;

  /// Duration of the FLIP slide animation on commit.
  final Duration slideDuration;

  /// Curve of the FLIP slide animation.
  final Curve slideCurve;

  /// Height in pixels from each viewport edge within which the pointer
  /// triggers autoscroll. Velocity ramps linearly from 0 at the zone's
  /// inner edge to [autoScrollMaxVelocity] at the viewport edge.
  final double autoScrollEdgeZone;

  /// Peak autoscroll velocity in logical pixels per second.
  final double autoScrollMaxVelocity;

  _DragSession<TKey>? _session;
  late final Ticker _autoScrollTicker;
  Duration? _lastAutoScrollTick;

  /// Whether a drag is currently in flight.
  bool get isDragging => _session != null;

  /// The currently-dragged key, or `null` if no drag is active.
  TKey? get draggedKey => _session?.draggedKey;

  /// The current drop target, or `null` if the pointer is outside any row.
  TreeDropTarget<TKey>? get currentTarget => _session?.currentTarget;

  /// Begins a drag session for [key].
  ///
  /// [renderObject] is the [RenderSliverTree] that currently displays
  /// [treeController]. [scrollable] is the ancestor scrollable whose
  /// viewport clips the tree — used for pointer → scroll-space conversion
  /// and autoscroll. [indentPerDepth] is the horizontal indent the tree
  /// uses per depth level; used to position the drop indicator.
  ///
  /// Throws [ArgumentError] if [renderObject.controller] is not the same
  /// controller passed to this reorder controller (cross-controller drag
  /// is out of scope) or if [canReorder] returns false for [key].
  void startDrag({
    required TKey key,
    required RenderSliverTree<TKey, TData> renderObject,
    required ScrollableState scrollable,
    required double indentPerDepth,
    required Offset pointerGlobal,
  }) {
    if (!identical(renderObject.controller, treeController)) {
      throw ArgumentError.value(
        renderObject,
        "renderObject",
        "renderObject.controller must be the same TreeController passed to "
        "TreeReorderController. Cross-controller drag is not supported.",
      );
    }
    if (canReorder != null && !canReorder!(key)) {
      throw ArgumentError.value(
        key,
        "key",
        "canReorder returned false for this key; drag cannot start",
      );
    }
    if (_session != null) {
      cancelDrag();
    }
    _session = _DragSession<TKey>(
      draggedKey: key,
      // Store under a less-tightly-typed field so this controller doesn't
      // need to propagate the TData parameter into every internal helper.
      renderObject: renderObject as RenderSliverTree<TKey, Object?>,
      scrollable: scrollable,
      indentPerDepth: indentPerDepth,
      pointerGlobal: pointerGlobal,
    );
    // Pin the dragged row against stale eviction for the session's
    // lifetime: the drag gesture lives on the row's own GestureDetector,
    // so autoscrolling it out of the cache region would otherwise evict
    // the row, its end/cancel callbacks would never fire, and the session
    // (plus the autoscroll ticker) would run forever.
    renderObject.pinNode(key);
    _recomputeDropTarget();
    // Drag session just started; currentTarget may have become non-null.
    notifyListeners();
  }

  /// Updates the pointer position. Re-resolves the drop target and starts
  /// / stops the autoscroll ticker as needed.
  void updateDrag(Offset pointerGlobal) {
    final session = _session;
    if (session == null) return;
    session.pointerGlobal = pointerGlobal;
    final previous = session.currentTarget;
    _recomputeDropTarget();
    _updateAutoScroll();
    if (!_targetsEqual(previous, session.currentTarget)) {
      notifyListeners();
    }
  }

  /// Commits the drop: mutates [treeController] (via [TreeController.moveNode],
  /// [TreeController.reorderChildren], or [TreeController.reorderRoots]) and
  /// starts the FLIP slide animation to interpolate old → new positions.
  ///
  /// If no valid target is currently resolved, behaves like [cancelDrag].
  ///
  /// The slide is installed IN-FRAME by the sliver render object: this
  /// method asks the render object to capture a baseline of current painted
  /// offsets BEFORE mutating the controller; the next `performLayout`
  /// (triggered by that mutation) snapshots the post-mutation offsets and
  /// installs a FLIP slide from baseline → current. The paint pass of the
  /// same frame then renders rows at their prior painted position and
  /// slides them toward their new structural position smoothly — no
  /// one-frame "jump to new position, then slide back" flicker.
  void endDrag() {
    final session = _session;
    if (session == null) return;

    // Re-resolve against CURRENT tree state, then validate, BEFORE staging
    // the FLIP baseline. The last pointer-move's target may be stale: with
    // server-driven updates the dragged node or the target parent can have
    // become pending-deletion (or been purged) since. Committing a stale
    // target would throw out of a GestureDetector callback with the
    // session permanently stuck, and a baseline staged before validation
    // would be consumed by nobody — first-wins staging then blocks every
    // subsequent slide stage until an unrelated layout flushes it.
    _recomputeDropTarget();
    final target = session.currentTarget;
    final dragged = session.draggedKey;
    final bool valid;
    if (target == null) {
      valid = false;
    } else if (treeController.getNodeData(dragged) == null ||
        treeController.isPendingDeletion(dragged)) {
      valid = false;
    } else {
      final parentKey = target.parentKey;
      if (parentKey == null) {
        valid = true;
      } else {
        valid = treeController.getNodeData(parentKey) != null &&
            !treeController.isPendingDeletion(parentKey) &&
            parentKey != dragged &&
            !_isStrictDescendantOf(parentKey, dragged);
      }
    }
    if (!valid) {
      cancelDrag();
      return;
    }

    _autoScrollTicker.stop();
    _lastAutoScrollTick = null;

    // Stage the FLIP baseline BEFORE mutating. The render object's next
    // performLayout will consume it and install the slide in-frame,
    // avoiding the post-frame gap that used to produce a single-frame
    // flicker of each moved row at its destination.
    session.renderObject.beginSlideBaseline(
      duration: slideDuration,
      curve: slideCurve,
    );

    try {
      final currentParent = treeController.getParent(dragged);
      final sameParent = currentParent == target!.parentKey;

      if (sameParent) {
        // Build the live final sibling list — reorderChildren/reorderRoots
        // reject lists containing pending-deletion entries and re-append them
        // internally after validating the live ordering.
        final liveSiblings = target.parentKey == null
            ? treeController.liveRootKeys
            : treeController.getLiveChildren(target.parentKey as TKey);
        liveSiblings.remove(dragged);
        final insertAt = target.indexInFinalList.clamp(0, liveSiblings.length);
        liveSiblings.insert(insertAt, dragged);

        if (target.parentKey == null) {
          // Drag commit: the reorderable widget owns the drop animation, so
          // keep the structural commit a snap to avoid double-animating the
          // item.
          treeController.reorderRoots(liveSiblings, animate: false);
        } else {
          treeController.reorderChildren(
            target.parentKey as TKey,
            liveSiblings,
            animate: false,
          );
        }
      } else {
        // Cross-parent: moveNode's `index` is the position in the new
        // parent's final child list — exactly indexInFinalList.
        treeController.moveNode(
          dragged,
          target.parentKey,
          index: target.indexInFinalList,
        );
      }
    } finally {
      // The re-resolve + validation above makes the commit's throwing
      // paths unreachable, so an exception here is a genuine invariant
      // violation — let it propagate, but never leave the session stuck.
      session.renderObject.unpinNode(dragged);
      _session = null;
      notifyListeners();
    }
  }

  /// Aborts the current drag without mutating the tree.
  void cancelDrag() {
    _autoScrollTicker.stop();
    _lastAutoScrollTick = null;
    final session = _session;
    if (session == null) return;
    session.renderObject.unpinNode(session.draggedKey);
    _session = null;
    notifyListeners();
  }

  /// Releases the autoscroll ticker. Call from the owning widget's
  /// `dispose`.
  @override
  void dispose() {
    final session = _session;
    if (session != null) {
      session.renderObject.unpinNode(session.draggedKey);
      _session = null;
    }
    _autoScrollTicker.dispose();
    super.dispose();
  }

  /// Value-equality for two drop targets so we only notify on real changes
  /// (pointer moves that cross a zone or row boundary), not on every
  /// pointer event that produces a structurally identical target.
  static bool _targetsEqual<TKey>(
    TreeDropTarget<TKey>? a,
    TreeDropTarget<TKey>? b,
  ) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.targetKey == b.targetKey &&
        a.zone == b.zone &&
        a.parentKey == b.parentKey &&
        a.indexInFinalList == b.indexInFinalList &&
        a.depth == b.depth &&
        a.indicatorScrollY == b.indicatorScrollY &&
        a.indicatorIndent == b.indicatorIndent;
  }

  /// Converts a global pointer offset to **sliver-local** y — distance from
  /// the start of THIS tree sliver's scroll extent, the space
  /// [RenderSliverTree.findRowAtPaintedY] consumes (first tree row at 0).
  ///
  /// Viewport scroll space and sliver-local space differ by the tree
  /// sliver's `constraints.precedingScrollExtent` whenever any sliver
  /// precedes the tree in the CustomScrollView; without the subtraction the
  /// resolved drop target lands `precedingScrollExtent` px below the
  /// hovered row.
  double _pointerToSliverLocalY(
    Offset globalPointer,
    _DragSession<TKey> session,
  ) {
    final viewport =
        session.scrollable.context.findRenderObject() as RenderBox;
    final viewportLocal = viewport.globalToLocal(globalPointer);
    final scrollSpaceY =
        session.scrollable.position.pixels + viewportLocal.dy;
    return scrollSpaceY - _precedingScrollExtent(session);
  }

  /// The tree sliver's `precedingScrollExtent`, or 0 when it has not been
  /// laid out yet (its `constraints` are only readable after layout; the
  /// sliver is laid out for the whole lifetime of a drag session).
  double _precedingScrollExtent(_DragSession<TKey> session) {
    final renderObject = session.renderObject;
    if (renderObject.geometry == null) {
      return 0.0;
    }
    return renderObject.constraints.precedingScrollExtent;
  }

  /// Finds the live row the pointer sits over via
  /// [RenderSliverTree.findRowAtPaintedY], classifies above/into/below, and
  /// resolves `(parentKey, indexInFinalList)`. Pending-deletion rows are
  /// vanishing and cannot be valid drop targets; the lookup skips them.
  void _recomputeDropTarget() {
    final session = _session;
    if (session == null) return;
    final scrollPointerY = _pointerToSliverLocalY(
      session.pointerGlobal,
      session,
    );

    final hovered = session.renderObject.findRowAtPaintedY(scrollPointerY);
    if (hovered == null) {
      session.currentTarget = null;
      return;
    }

    final resolved = _resolveZone(
      session: session,
      targetKey: hovered.key,
      targetOffset: hovered.paintedOffset,
      targetExtent: hovered.extent,
      scrollPointerY: scrollPointerY,
    );
    session.currentTarget = resolved;
  }

  /// Classifies the pointer position into a [TreeDropZone] and builds a
  /// [TreeDropTarget]. Returns `null` if the resolved target is invalid
  /// (cycle, no-op, or rejected by [canAcceptDrop]).
  TreeDropTarget<TKey>? _resolveZone({
    required _DragSession<TKey> session,
    required TKey targetKey,
    required double targetOffset,
    required double targetExtent,
    required double scrollPointerY,
  }) {
    final dragged = session.draggedKey;
    final localY = (scrollPointerY - targetOffset).clamp(0.0, targetExtent);
    final t = targetExtent <= 0 ? 0.0 : localY / targetExtent;

    // Rows that can't accept children collapse into/below into a two-zone
    // split at the midpoint.
    final targetAllowsChildren = !_isSameOrDescendant(targetKey, dragged) &&
        _canTargetAcceptInto(targetKey, dragged);

    TreeDropZone zone;
    if (t < 1 / 3) {
      zone = TreeDropZone.above;
    } else if (t < 2 / 3 && targetAllowsChildren) {
      zone = TreeDropZone.into;
    } else {
      zone = TreeDropZone.below;
    }

    // Translate (targetKey, zone) to (parentKey, rawIndex). All sibling
    // indices are computed in live-list space, matching the reorder APIs.
    //
    // [targetOffset] is sliver-local (from findRowAtPaintedY);
    // [TreeDropTarget.indicatorScrollY] is documented as VIEWPORT scroll
    // space (its consumer subtracts `position.pixels`), so add the tree
    // sliver's precedingScrollExtent when constructing the target.
    final preceding = _precedingScrollExtent(session);
    TKey? parentKey;
    int rawIndex;
    int depth;
    double indicatorScrollY;
    switch (zone) {
      case TreeDropZone.above:
        parentKey = treeController.getParent(targetKey);
        rawIndex = treeController.getIndexInParent(targetKey);
        depth = treeController.getDepth(targetKey);
        indicatorScrollY = targetOffset + preceding;
        break;
      case TreeDropZone.below:
        // Below an EXPANDED target with visible children, "next sibling
        // of target" sits after the whole visible subtree — potentially
        // many rows lower than the indicator line drawn directly under
        // the target row (which is visually the FIRST CHILD's slot).
        // Resolve as first-child (identical to `into`) so indicator and
        // commit agree by construction — conventional tree-DnD
        // semantics. Collapsed/leaf targets keep next-sibling semantics.
        if (targetAllowsChildren &&
            treeController.isExpanded(targetKey) &&
            treeController.getLiveChildren(targetKey).isNotEmpty) {
          parentKey = targetKey;
          rawIndex = 0;
          depth = treeController.getDepth(targetKey) + 1;
        } else {
          parentKey = treeController.getParent(targetKey);
          rawIndex = treeController.getIndexInParent(targetKey) + 1;
          depth = treeController.getDepth(targetKey);
        }
        indicatorScrollY = targetOffset + targetExtent + preceding;
        break;
      case TreeDropZone.into:
        parentKey = targetKey;
        rawIndex = 0;
        depth = treeController.getDepth(targetKey) + 1;
        indicatorScrollY = targetOffset + targetExtent + preceding;
        break;
    }

    if (rawIndex < 0) {
      return null;
    }

    // Cycle filter: can't parent under self or under a descendant.
    if (parentKey != null) {
      if (parentKey == dragged) return null;
      if (_isStrictDescendantOf(parentKey, dragged)) return null;
    }

    // Same-parent final-list index adjustment. Same-parent drops take a
    // final list to reorderChildren/reorderRoots; the index space is the
    // live list with dragged removed and re-inserted. If dragged sits
    // before rawIndex in the live list, subtract 1 to account for the
    // implicit removal.
    final currentParent = treeController.getParent(dragged);
    final isSameParent = currentParent == parentKey;
    int indexInFinalList = rawIndex;
    if (isSameParent) {
      final currentIndex = treeController.getIndexInParent(dragged);
      if (currentIndex >= 0 && currentIndex < rawIndex) {
        indexInFinalList = rawIndex - 1;
      }
    }

    // No-op filter: drop exactly at current position.
    if (isSameParent &&
        indexInFinalList == treeController.getIndexInParent(dragged)) {
      return null;
    }

    // User policy filter.
    if (canAcceptDrop != null &&
        !canAcceptDrop!(
          movingKey: dragged,
          newParent: parentKey,
          index: indexInFinalList,
        )) {
      return null;
    }

    final indicatorIndent = session.indentPerDepth * depth;
    return TreeDropTarget<TKey>(
      targetKey: targetKey,
      zone: zone,
      parentKey: parentKey,
      indexInFinalList: indexInFinalList,
      depth: depth,
      indicatorScrollY: indicatorScrollY,
      indicatorIndent: indicatorIndent,
    );
  }

  /// Whether [candidate] lies inside [rootKey]'s subtree (inclusive).
  bool _isSameOrDescendant(TKey candidate, TKey rootKey) {
    if (candidate == rootKey) return true;
    return _isStrictDescendantOf(candidate, rootKey);
  }

  /// Cheap "can this row accept children as a drop target?" heuristic: the
  /// node is not the dragged key and not one of its descendants. Finer
  /// policies (leaf-only, depth limits) flow through [canAcceptDrop].
  bool _canTargetAcceptInto(TKey targetKey, TKey draggedKey) {
    if (targetKey == draggedKey) return false;
    if (_isStrictDescendantOf(targetKey, draggedKey)) return false;
    return true;
  }

  /// Whether [node] is a strict descendant (not [ancestor] itself) of
  /// [ancestor]. O(depth) ancestor walk with no allocation — the drop-target
  /// resolution path asks this up to three times per pointer move, and the
  /// alternative `getDescendants(ancestor).contains(node)` materialized a
  /// fresh list of every descendant on each call.
  bool _isStrictDescendantOf(TKey node, TKey ancestor) {
    TKey? current = treeController.getParent(node);
    while (current != null) {
      if (current == ancestor) return true;
      current = treeController.getParent(current);
    }
    return false;
  }

  // ──────── Autoscroll ────────

  void _updateAutoScroll() {
    final session = _session;
    if (session == null) return;
    final viewport =
        session.scrollable.context.findRenderObject() as RenderBox;
    final local = viewport.globalToLocal(session.pointerGlobal);
    final height = viewport.size.height;
    final inEdgeZone =
        local.dy < autoScrollEdgeZone ||
        local.dy > height - autoScrollEdgeZone;
    if (inEdgeZone) {
      if (!_autoScrollTicker.isActive) {
        _lastAutoScrollTick = null;
        _autoScrollTicker.start();
      }
    } else {
      if (_autoScrollTicker.isActive) {
        _autoScrollTicker.stop();
        _lastAutoScrollTick = null;
      }
    }
  }

  void _onAutoScrollTick(Duration elapsed) {
    final session = _session;
    if (session == null) {
      _autoScrollTicker.stop();
      _lastAutoScrollTick = null;
      return;
    }
    final viewport =
        session.scrollable.context.findRenderObject() as RenderBox;
    final local = viewport.globalToLocal(session.pointerGlobal);
    final height = viewport.size.height;

    double velocity = 0;
    if (local.dy < autoScrollEdgeZone) {
      final t = 1 - (local.dy / autoScrollEdgeZone).clamp(0.0, 1.0);
      velocity = -autoScrollMaxVelocity * t;
    } else if (local.dy > height - autoScrollEdgeZone) {
      final t =
          ((local.dy - (height - autoScrollEdgeZone)) / autoScrollEdgeZone)
              .clamp(0.0, 1.0);
      velocity = autoScrollMaxVelocity * t;
    }

    if (velocity == 0) {
      _autoScrollTicker.stop();
      _lastAutoScrollTick = null;
      return;
    }

    final dt = _lastAutoScrollTick == null
        ? const Duration(milliseconds: 16)
        : elapsed - _lastAutoScrollTick!;
    _lastAutoScrollTick = elapsed;

    final position = session.scrollable.position;
    final newPixels = (position.pixels + velocity * dt.inMicroseconds / 1e6)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (newPixels != position.pixels) {
      position.jumpTo(newPixels);
      final previous = session.currentTarget;
      _recomputeDropTarget();
      if (!_targetsEqual(previous, session.currentTarget)) {
        notifyListeners();
      }
    }
  }
}

