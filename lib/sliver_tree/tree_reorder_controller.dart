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

import 'dart:async';

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

  /// Scroll-space y where the indicator line should be drawn. Subtract
  /// the scrollable's `position.pixels` to convert to viewport-local.
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
  /// Completes after one post-frame callback (after the FLIP "after"
  /// snapshot is taken), but the slide animation itself runs async.
  Future<void> endDrag() async {
    final session = _session;
    if (session == null) return;
    final target = session.currentTarget;
    if (target == null) {
      cancelDrag();
      return;
    }

    _autoScrollTicker.stop();
    _lastAutoScrollTick = null;

    final renderObject = session.renderObject;
    final priorOffsets = renderObject.snapshotVisibleOffsets();

    final currentParent = treeController.getParent(session.draggedKey);
    final sameParent = currentParent == target.parentKey;

    if (sameParent) {
      // Build the live final sibling list — reorderChildren/reorderRoots
      // reject lists containing pending-deletion entries and re-append them
      // internally after validating the live ordering.
      final liveSiblings = target.parentKey == null
          ? treeController.liveRootKeys
          : treeController.getLiveChildren(target.parentKey as TKey);
      liveSiblings.remove(session.draggedKey);
      final insertAt = target.indexInFinalList.clamp(0, liveSiblings.length);
      liveSiblings.insert(insertAt, session.draggedKey);

      if (target.parentKey == null) {
        treeController.reorderRoots(liveSiblings);
      } else {
        treeController.reorderChildren(
          target.parentKey as TKey,
          liveSiblings,
        );
      }
    } else {
      // Cross-parent: moveNode's `index` is the position in the new parent's
      // final child list — exactly indexInFinalList.
      treeController.moveNode(
        session.draggedKey,
        target.parentKey,
        index: target.indexInFinalList,
      );
    }

    await _afterNextFrame();
    // Session may have been cancelled during the await (e.g. widget
    // disposed). If so, the slide is still a valid animation on the
    // controller's state — start it anyway for visual continuity.
    final currentOffsets = renderObject.snapshotVisibleOffsets();
    treeController.animateSlideFromOffsets(
      priorOffsets,
      currentOffsets,
      duration: slideDuration,
      curve: slideCurve,
    );

    _session = null;
    notifyListeners();
  }

  /// Aborts the current drag without mutating the tree.
  void cancelDrag() {
    _autoScrollTicker.stop();
    _lastAutoScrollTick = null;
    if (_session == null) return;
    _session = null;
    notifyListeners();
  }

  /// Releases the autoscroll ticker. Call from the owning widget's
  /// `dispose`.
  @override
  void dispose() {
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

  /// Converts a global pointer offset to scroll-space y (distance from the
  /// start of the sliver's scroll extent).
  double _pointerToScrollSpaceY(
    Offset globalPointer,
    ScrollableState scrollable,
  ) {
    final viewport = scrollable.context.findRenderObject() as RenderBox;
    final viewportLocal = viewport.globalToLocal(globalPointer);
    return scrollable.position.pixels + viewportLocal.dy;
  }

  /// Walks [TreeController.visibleNodes] paired with
  /// [RenderSliverTree.snapshotVisibleOffsets], finds the row whose
  /// `[offset, offset + extent)` contains the scroll-space pointer y,
  /// classifies above/into/below, and resolves `(parentKey, indexInFinalList)`.
  void _recomputeDropTarget() {
    final session = _session;
    if (session == null) return;
    final scrollPointerY = _pointerToScrollSpaceY(
      session.pointerGlobal,
      session.scrollable,
    );

    final offsets = session.renderObject.snapshotVisibleOffsets();
    final visible = treeController.visibleNodes;
    if (visible.isEmpty) {
      session.currentTarget = null;
      return;
    }

    // Find the first live row whose [offset, offset + extent) contains
    // scrollPointerY. Pending-deletion rows are vanishing and cannot be
    // valid drop targets; fall through to the nearest live neighbor.
    TKey? hoveredKey;
    double hoveredOffset = 0.0;
    double hoveredExtent = 0.0;
    for (final key in visible) {
      if (treeController.isPendingDeletion(key)) continue;
      final offset = offsets[key];
      if (offset == null) continue;
      final extent = treeController.getCurrentExtent(key);
      if (scrollPointerY < offset) {
        // Pointer is above this row; if no earlier row captured it,
        // treat this row as the hovered one at its top edge.
        hoveredKey ??= key;
        hoveredOffset = offset;
        hoveredExtent = extent;
        break;
      }
      if (scrollPointerY < offset + extent) {
        hoveredKey = key;
        hoveredOffset = offset;
        hoveredExtent = extent;
        break;
      }
    }
    // Pointer past the last row — anchor to the last live row's bottom.
    if (hoveredKey == null) {
      for (int i = visible.length - 1; i >= 0; i--) {
        final key = visible[i];
        if (treeController.isPendingDeletion(key)) continue;
        hoveredKey = key;
        hoveredOffset = offsets[key] ?? 0.0;
        hoveredExtent = treeController.getCurrentExtent(key);
        break;
      }
    }
    if (hoveredKey == null) {
      session.currentTarget = null;
      return;
    }

    final resolved = _resolveZone(
      session: session,
      targetKey: hoveredKey,
      targetOffset: hoveredOffset,
      targetExtent: hoveredExtent,
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
    TKey? parentKey;
    int rawIndex;
    int depth;
    double indicatorScrollY;
    switch (zone) {
      case TreeDropZone.above:
        parentKey = treeController.getParent(targetKey);
        rawIndex = treeController.getIndexInParent(targetKey);
        depth = treeController.getDepth(targetKey);
        indicatorScrollY = targetOffset;
        break;
      case TreeDropZone.below:
        parentKey = treeController.getParent(targetKey);
        rawIndex = treeController.getIndexInParent(targetKey) + 1;
        depth = treeController.getDepth(targetKey);
        indicatorScrollY = targetOffset + targetExtent;
        break;
      case TreeDropZone.into:
        parentKey = targetKey;
        rawIndex = 0;
        depth = treeController.getDepth(targetKey) + 1;
        indicatorScrollY = targetOffset + targetExtent;
        break;
    }

    if (rawIndex < 0) {
      return null;
    }

    // Cycle filter: can't parent under self or under a descendant.
    if (parentKey != null) {
      if (parentKey == dragged) return null;
      if (treeController.getDescendants(dragged).contains(parentKey)) {
        return null;
      }
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
    return treeController.getDescendants(rootKey).contains(candidate);
  }

  /// Cheap "can this row accept children as a drop target?" heuristic: the
  /// node is not the dragged key and not one of its descendants. Finer
  /// policies (leaf-only, depth limits) flow through [canAcceptDrop].
  bool _canTargetAcceptInto(TKey targetKey, TKey draggedKey) {
    if (targetKey == draggedKey) return false;
    if (treeController.getDescendants(draggedKey).contains(targetKey)) {
      return false;
    }
    return true;
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

  /// Completes after the next frame has been laid out and painted.
  Future<void> _afterNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    // Nudge the scheduler so a frame happens even when nothing else has
    // marked the pipeline dirty (slide-only paths can otherwise miss it).
    WidgetsBinding.instance.ensureVisualUpdate();
    return completer.future;
  }
}

