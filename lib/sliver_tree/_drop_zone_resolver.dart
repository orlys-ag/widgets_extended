/// Pure drop-target resolution for drag-and-drop reorder.
///
/// Resolution is a pure function of controller state, hovered-row
/// geometry, and the pointer position, so the full zone table is
/// unit-testable without a widget tree. Same split as the other
/// render/logic collaborators (`StickyHeaderComputer`, `SlideComposer`).
///
/// This library owns the **semantic** drop-target model. Presentation
/// (indicator line position and indent) is derived by the widget layer from
/// [TreeDropTarget.zone], [TreeDropTarget.targetPaintedY],
/// [TreeDropTarget.targetExtent], and [TreeDropTarget.depth] — pixel
/// concerns like indent-per-depth never enter resolution.
library;

import 'package:flutter/foundation.dart';

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

/// Resolved semantic drop target for the current pointer position during a
/// drag.
///
/// Immutable snapshot produced by [DropZoneResolver] from the pointer and
/// the hovered row's painted geometry. Consumed two ways:
///
/// - **Commit** (`TreeReorderController.endDrag`): [parentKey] +
///   [indexInFinalList] drive `moveNode` / `reorderChildren` /
///   `reorderRoots`.
/// - **Presentation** (the drop-indicator overlay): [zone] +
///   [targetPaintedY] + [targetExtent] + [depth] are the inputs from which
///   the widget layer derives the indicator line's position and indent.
@immutable
class TreeDropTarget<TKey> {
  const TreeDropTarget({
    required this.targetKey,
    required this.zone,
    required this.parentKey,
    required this.indexInFinalList,
    required this.depth,
    required this.targetPaintedY,
    required this.targetExtent,
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

  /// Depth of the dragged node **after** the move (0 for roots).
  final int depth;

  /// **Sliver-local** painted y of [targetKey]'s row at resolve time: the
  /// space `RenderSliverTree.findRowAtPaintedY` speaks (first tree row at
  /// 0, including any active FLIP slide delta). Convert to viewport scroll
  /// space by adding the tree sliver's `precedingScrollExtent`
  /// (`ReorderRenderPort.precedingScrollExtent`).
  final double targetPaintedY;

  /// Painted extent of [targetKey]'s row at resolve time.
  ///
  /// With [zone], locates the indicator edge: `above` draws at
  /// [targetPaintedY], `into`/`below` at [targetPaintedY] +
  /// [targetExtent].
  final double targetExtent;
}

/// Classifies a pointer position over a hovered row into a [TreeDropZone]
/// and translates it to a semantic [TreeDropTarget] against current
/// [TreeController] state.
///
/// Stateless between calls; safe to share for the lifetime of the owning
/// reorder controller.
class DropZoneResolver<TKey> {
  DropZoneResolver({
    required this.treeController,
    this.canAcceptDrop,
  });

  /// The controller whose structure resolution reads (parents, depths,
  /// live indices, expansion).
  final TreeController<TKey, Object?> treeController;

  /// If set, rejected drop targets resolve to `null`. Receives the dragged
  /// key, the candidate new parent, and the final-list index.
  final bool Function({
    required TKey movingKey,
    TKey? newParent,
    int? index,
  })? canAcceptDrop;

  /// Resolves the drop target for [draggedKey] with the pointer at
  /// [pointerY] (sliver-local) over the row [targetKey], whose painted
  /// geometry is [targetPaintedY] / [targetExtent].
  ///
  /// [preferredDepth] is the depth level the pointer's HORIZONTAL
  /// position indicates (unclamped — the widget layer maps
  /// `x ~/ indentPerDepth` without knowing which levels are legal). It
  /// matters at subtree boundaries, where one visible slot has several
  /// legal depth expressions: the `below` zone at a right-boundary
  /// (ancestor subtrees ending at the target row) and the `above` zone at
  /// a LEFT-boundary (deeper subtrees closing at the previous visible
  /// row). The resolver clamps the hint to the legal chain; `null` keeps
  /// each zone's classic default (deepest for `below`, the target's own
  /// depth for `above`).
  ///
  /// Returns `null` if the resolved target is invalid (cycle, no-op, or
  /// rejected by [canAcceptDrop]) at every legal level.
  TreeDropTarget<TKey>? resolve({
    required TKey draggedKey,
    required TKey targetKey,
    required double targetPaintedY,
    required double targetExtent,
    required double pointerY,
    int? preferredDepth,
  }) {
    final localY = (pointerY - targetPaintedY).clamp(0.0, targetExtent);
    final t = targetExtent <= 0 ? 0.0 : localY / targetExtent;

    // Rows that can't take the dragged node as a child collapse to a
    // two-zone split at the MIDPOINT. "Can't take" is structural (self /
    // descendant — a cycle) OR policy: a [canAcceptDrop] that vetoes
    // nesting under this row would leave the `into` third permanently
    // dead, so consult it here and give flat-list-style policies clean
    // ReorderableListView-like midpoint-crossing semantics instead.
    final targetAllowsChildren =
        !_isSameOrDescendant(targetKey, draggedKey) &&
        _canTargetAcceptInto(targetKey, draggedKey) &&
        (canAcceptDrop == null ||
            canAcceptDrop!(
              movingKey: draggedKey,
              newParent: targetKey,
              index: 0,
            ));

    TreeDropZone zone;
    if (targetAllowsChildren) {
      if (t < 1 / 3) {
        zone = TreeDropZone.above;
      } else if (t < 2 / 3) {
        zone = TreeDropZone.into;
      } else {
        zone = TreeDropZone.below;
      }
    } else if (t < 0.5) {
      zone = TreeDropZone.above;
    } else {
      zone = TreeDropZone.below;
    }

    // Translate (targetKey, zone) to (parentKey, rawIndex) and validate.
    // All sibling indices are computed in live-list space, matching the
    // reorder APIs.
    switch (zone) {
      case TreeDropZone.above:
        // LEFT-boundary chain (mirror of the below-zone right-boundary
        // chain): the slot above [targetKey] is the SAME visible slot as
        // the tail of every deeper subtree that closes at the previous
        // visible row. Example: "above a section header" is also "after
        // the previous section's last child" — when the shallow candidate
        // is filtered (policy vetoing root-level drops, cycles), the
        // deeper expressions of the same slot must be tried, or crossing
        // a boundary dies in a dead band (and, under make-room, flaps
        // the gap open/closed under a stationary pointer).
        final baseDepth = treeController.getDepth(targetKey);
        final candidates = <({TKey? parentKey, int rawIndex, int depth})>[];
        final visIndex = treeController.getVisibleIndex(targetKey);
        if (visIndex > 0) {
          final prev = treeController.visibleNodes[visIndex - 1];
          var node = prev;
          var d = treeController.getDepth(prev);
          while (d > baseDepth) {
            final idx = treeController.getIndexInParent(node);
            if (idx < 0) {
              // Pending-deletion link — its live index is meaningless;
              // stop the chain at this level.
              break;
            }
            final parent = treeController.getParent(node);
            candidates.add((
              parentKey: parent,
              rawIndex: idx + 1,
              depth: d,
            ));
            if (parent == null) {
              break;
            }
            node = parent;
            d--;
          }
        }
        candidates.add((
          parentKey: treeController.getParent(targetKey),
          rawIndex: treeController.getIndexInParent(targetKey),
          depth: baseDepth,
        ));
        // No hint defaults to the SHALLOWEST candidate — the classic
        // above-target slot (pre-chain semantics); the deeper levels are
        // reached by pointer x or by filter fallback.
        return _resolveCandidates(
          draggedKey: draggedKey,
          targetKey: targetKey,
          zone: zone,
          candidates: candidates,
          preferredDepth: preferredDepth,
          defaultDepth: baseDepth,
          targetPaintedY: targetPaintedY,
          targetExtent: targetExtent,
        );
      case TreeDropZone.into:
        return _buildTarget(
          draggedKey: draggedKey,
          targetKey: targetKey,
          zone: zone,
          parentKey: targetKey,
          rawIndex: 0,
          depth: treeController.getDepth(targetKey) + 1,
          targetPaintedY: targetPaintedY,
          targetExtent: targetExtent,
        );
      case TreeDropZone.below:
        // Below an EXPANDED target with visible children, "next sibling
        // of target" sits after the whole visible subtree — potentially
        // many rows lower than the indicator line drawn directly under
        // the target row (which is visually the FIRST CHILD's slot).
        // Resolve as first-child (identical to `into`) so indicator and
        // commit agree by construction — conventional tree-DnD
        // semantics. Such a row is never a subtree right-boundary (its
        // subtree continues below), so the x-aware chain never applies.
        if (targetAllowsChildren &&
            treeController.isExpanded(targetKey) &&
            treeController.hasLiveChildren(targetKey)) {
          return _buildTarget(
            draggedKey: draggedKey,
            targetKey: targetKey,
            zone: zone,
            parentKey: targetKey,
            rawIndex: 0,
            depth: treeController.getDepth(targetKey) + 1,
            targetPaintedY: targetPaintedY,
            targetExtent: targetExtent,
          );
        }

        // At a subtree right-boundary the slot under the target row is
        // ambiguous — it belongs equally to every ancestor whose
        // subtree ends at this row. Build the candidate chain
        // deepest-first; depths are contiguous (each ancestor level is
        // exactly one shallower).
        final candidates = <({TKey? parentKey, int rawIndex, int depth})>[
          (
            parentKey: treeController.getParent(targetKey),
            rawIndex: treeController.getIndexInParent(targetKey) + 1,
            depth: treeController.getDepth(targetKey),
          ),
        ];
        TKey node = targetKey;
        while (true) {
          final parent = treeController.getParent(node);
          final liveCount = parent == null
              ? treeController.liveRootCount
              : treeController.liveChildCount(parent);
          if (treeController.getIndexInParent(node) != liveCount - 1) {
            // node has a later live sibling — the boundary ends here.
            break;
          }
          if (parent == null) {
            // node is the last root: no shallower level exists.
            break;
          }
          candidates.add((
            parentKey: treeController.getParent(parent),
            rawIndex: treeController.getIndexInParent(parent) + 1,
            depth: treeController.getDepth(parent),
          ));
          node = parent;
        }

        // No hint defaults to the DEEPEST candidate — also what a
        // handle-drag pointer at the row's right edge clamps to.
        return _resolveCandidates(
          draggedKey: draggedKey,
          targetKey: targetKey,
          zone: zone,
          candidates: candidates,
          preferredDepth: preferredDepth,
          defaultDepth: candidates.first.depth,
          targetPaintedY: targetPaintedY,
          targetExtent: targetExtent,
        );
    }
  }

  /// Selects among boundary [candidates] (deepest-first, contiguous
  /// depths): clamp the hint (or [defaultDepth] when no hint) to the
  /// chain, then try candidates by |depth − chosen|, deeper-first on
  /// ties. A filtered candidate (cycle / policy veto) falls back to the
  /// next-nearest level instead of nulling the whole resolution — some
  /// legal expression of the slot beats a dead zone.
  TreeDropTarget<TKey>? _resolveCandidates({
    required TKey draggedKey,
    required TKey targetKey,
    required TreeDropZone zone,
    required List<({TKey? parentKey, int rawIndex, int depth})> candidates,
    required int? preferredDepth,
    required int defaultDepth,
    required double targetPaintedY,
    required double targetExtent,
  }) {
    final deepest = candidates.first.depth;
    final shallowest = candidates.last.depth;
    final clamped = (preferredDepth ?? defaultDepth).clamp(shallowest, deepest);
    final ordered = List.of(candidates)
      ..sort((a, b) {
        final da = (a.depth - clamped).abs();
        final db = (b.depth - clamped).abs();
        if (da != db) {
          return da - db;
        }
        return b.depth - a.depth;
      });
    for (final candidate in ordered) {
      final resolved = _buildTarget(
        draggedKey: draggedKey,
        targetKey: targetKey,
        zone: zone,
        parentKey: candidate.parentKey,
        rawIndex: candidate.rawIndex,
        depth: candidate.depth,
        targetPaintedY: targetPaintedY,
        targetExtent: targetExtent,
      );
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  /// Validates one `(parentKey, rawIndex, depth)` slot and builds the
  /// semantic target, or returns `null` when any filter rejects it:
  /// cycle (can't parent under self or a descendant), no-op (drop at the
  /// current position), or the user's [canAcceptDrop] policy. Shared by
  /// every zone and by each ancestor-chain candidate.
  TreeDropTarget<TKey>? _buildTarget({
    required TKey draggedKey,
    required TKey targetKey,
    required TreeDropZone zone,
    required TKey? parentKey,
    required int rawIndex,
    required int depth,
    required double targetPaintedY,
    required double targetExtent,
  }) {
    if (rawIndex < 0) {
      return null;
    }

    // Cycle filter: can't parent under self or under a descendant.
    if (parentKey != null) {
      if (parentKey == draggedKey) {
        return null;
      }
      if (isStrictDescendantOf(parentKey, draggedKey)) {
        return null;
      }
    }

    // Same-parent final-list index adjustment. Same-parent drops take a
    // final list to reorderChildren/reorderRoots; the index space is the
    // live list with dragged removed and re-inserted. If dragged sits
    // before rawIndex in the live list, subtract 1 to account for the
    // implicit removal.
    final currentParent = treeController.getParent(draggedKey);
    final isSameParent = currentParent == parentKey;
    int indexInFinalList = rawIndex;
    if (isSameParent) {
      final currentIndex = treeController.getIndexInParent(draggedKey);
      if (currentIndex >= 0 && currentIndex < rawIndex) {
        indexInFinalList = rawIndex - 1;
      }
    }

    // Current-position slot: the resolved slot IS where the dragged row
    // already sits. This is a VALID target — the honest feedback is
    // "drops back here" (indicator at the original slot; in make-room
    // mode the zero-shift state paints as an open gap at the original
    // position) — and it gives crossing hysteresis instead of a dead
    // zone: otherwise dragging DOWN onto the next sibling's top third
    // ("above next" ≡ current position) would select nothing, going dark
    // for two-thirds of the card. The commit path detects the case and
    // mutates nothing. The policy filter is deliberately skipped —
    // "not moving" is not a drop a policy can forbid.
    if (isSameParent &&
        indexInFinalList == treeController.getIndexInParent(draggedKey)) {
      return TreeDropTarget<TKey>(
        targetKey: targetKey,
        zone: zone,
        parentKey: parentKey,
        indexInFinalList: indexInFinalList,
        depth: depth,
        targetPaintedY: targetPaintedY,
        targetExtent: targetExtent,
      );
    }

    // User policy filter.
    if (canAcceptDrop != null &&
        !canAcceptDrop!(
          movingKey: draggedKey,
          newParent: parentKey,
          index: indexInFinalList,
        )) {
      return null;
    }

    return TreeDropTarget<TKey>(
      targetKey: targetKey,
      zone: zone,
      parentKey: parentKey,
      indexInFinalList: indexInFinalList,
      depth: depth,
      targetPaintedY: targetPaintedY,
      targetExtent: targetExtent,
    );
  }

  /// Whether [node] is a strict descendant (not [ancestor] itself) of
  /// [ancestor]. O(depth) ancestor walk with no allocation — the drop-target
  /// resolution path asks this up to three times per pointer move, and the
  /// alternative `getDescendants(ancestor).contains(node)` materialized a
  /// fresh list of every descendant on each call.
  ///
  /// Public (unlike the other helpers) because commit-time re-validation in
  /// `TreeReorderController.endDrag` runs the same cycle check.
  bool isStrictDescendantOf(TKey node, TKey ancestor) {
    TKey? current = treeController.getParent(node);
    while (current != null) {
      if (current == ancestor) {
        return true;
      }
      current = treeController.getParent(current);
    }
    return false;
  }

  /// Whether [candidate] lies inside [rootKey]'s subtree (inclusive).
  bool _isSameOrDescendant(TKey candidate, TKey rootKey) {
    if (candidate == rootKey) {
      return true;
    }
    return isStrictDescendantOf(candidate, rootKey);
  }

  /// Cheap "can this row accept children as a drop target?" heuristic: the
  /// node is not the dragged key and not one of its descendants. Finer
  /// policies (leaf-only, depth limits) flow through [canAcceptDrop].
  bool _canTargetAcceptInto(TKey targetKey, TKey draggedKey) {
    if (targetKey == draggedKey) {
      return false;
    }
    if (isStrictDescendantOf(targetKey, draggedKey)) {
      return false;
    }
    return true;
  }
}
