/// Pure drop-target resolution for drag-and-drop reorder.
///
/// Resolution is a pure function of controller state, hovered-row
/// geometry, and the pointer position, so the full zone table is
/// unit-testable without a widget tree. Same split as the other
/// render/logic collaborators (`StickyHeaderComputer`, `SlideComposer`).
///
/// This library owns the **semantic** drop-target model. Pixel concerns
/// like indent-per-depth never enter resolution: the pointer's x arrives
/// pre-mapped to a preferred DEPTH, and the resolved slot leaves as
/// [TreeDropTarget.gapVisibleIndex], a visible-order position.
library;

import 'package:flutter/foundation.dart';

import 'tree_controller.dart';

/// Where the pointer lies relative to a candidate drop-target row.
///
/// The zone names where the pointer IS, not the depth that results.
/// [above] and [below] each resolve over a chain of legal levels, and
/// either may fall back to a hidden-interior slot (the inside of a
/// collapsed or empty container) when every level in that chain is
/// rejected, so a zone of `above` can still produce a child slot inside
/// the row above. Read [TreeDropTarget.parentKey] and
/// [TreeDropTarget.depth] for what was actually resolved.
enum TreeDropZone {
  /// Pointer is in the leading portion of [TreeDropTarget.targetKey]'s
  /// row. Normally a sibling slot before it.
  above,

  /// Pointer is in the middle of the row: the first-child slot of
  /// [TreeDropTarget.targetKey].
  into,

  /// Pointer is in the trailing portion of the row. Normally a sibling
  /// slot after it, or its first-child slot when it is an expanded
  /// parent.
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
/// - **Feedback** (the make-room preview): [gapVisibleIndex] names the
///   row the gap opens before. Derived from the resolved slot, NOT from
///   the hovered row, so the gap and the commit cannot disagree.
@immutable
class TreeDropTarget<TKey> {
  const TreeDropTarget({
    required this.targetKey,
    required this.zone,
    required this.parentKey,
    required this.indexInFinalList,
    required this.depth,
    required this.gapVisibleIndex,
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

  /// Visible-order index of the resolved slot's leading edge: the
  /// make-room gap opens BEFORE the row at this index.
  ///
  /// Derived from the resolved slot ([parentKey] + [indexInFinalList]),
  /// NOT from [targetKey], so the previewed gap and the committed
  /// position cannot disagree. They differ whenever the resolved slot is
  /// not visually adjacent to the hovered row, which happens when a
  /// [DropZoneResolver.canAcceptDrop] veto or a cycle disables the
  /// below-on-expanded-parent rule over a row that has a visible
  /// subtree.
  ///
  /// Valid range is `[0, visibleNodeCount]` INCLUSIVE. The terminal value
  /// means "after every visible row", which is the correct answer for
  /// appending at the very end.
  final int gapVisibleIndex;

  /// **Sliver-local** painted y of [targetKey]'s row at resolve time: the
  /// space `RenderSliverTree.findRowAtPaintedY` speaks (first tree row at
  /// 0, including any active FLIP slide delta). Convert to viewport scroll
  /// space by adding the tree sliver's `precedingScrollExtent`
  /// (`ReorderRenderPort.precedingScrollExtent`).
  final double targetPaintedY;

  /// Painted extent of [targetKey]'s row at resolve time.
  ///
  /// Describes the HOVERED ROW, not the resolved slot. The two are only
  /// interchangeable when the slot is visually adjacent to that row; use
  /// [gapVisibleIndex] for the slot itself.
  final double targetExtent;
}

/// One legal expression of a drop slot, before validation.
///
/// The gap's visible-order index is carried in one of two forms, exactly
/// one of which is non-null. [gapIndex] is a precomputed value, used
/// where the branch already had it in hand or where there is a single
/// candidate so laziness buys nothing. [gapAnchor] defers it: the gap
/// opens just past that node's visible subtree, resolved only for the
/// candidate that survives every filter, so a chain of rejected
/// candidates costs no lookups.
typedef _Candidate<TKey> = ({
  TKey? parentKey,
  int rawIndex,
  int depth,
  int? gapIndex,
  TKey? gapAnchor,
});

/// Classifies a pointer position over a hovered row into a [TreeDropZone]
/// and translates it to a semantic [TreeDropTarget] against current
/// [TreeController] state.
///
/// Stateless between calls; safe to share for the lifetime of the owning
/// reorder controller.
class DropZoneResolver<TKey> {
  DropZoneResolver({required this.treeController, this.canAcceptDrop});

  /// The controller whose structure resolution reads (parents, depths,
  /// live indices, expansion).
  final TreeController<TKey, Object?> treeController;

  /// If set, rejected drop targets resolve to `null`. Receives the dragged
  /// key, the candidate new parent, and the final-list index.
  final bool Function({required TKey movingKey, TKey? newParent, int? index})?
  canAcceptDrop;

  /// Resolves the drop target for [draggedKey] with the pointer at
  /// [pointerY] (sliver-local) over the row [targetKey], whose painted
  /// geometry is [targetPaintedY] / [targetExtent].
  ///
  /// [preferredDepth] is the depth level the pointer's HORIZONTAL
  /// position indicates (unclamped — the widget layer maps
  /// `x ~/ indentWidth` without knowing which levels are legal). It
  /// matters at subtree boundaries, where one visible slot has several
  /// legal depth expressions: the `below` zone at a right-boundary
  /// (ancestor subtrees ending at the target row) and the `above` zone at
  /// a LEFT-boundary (deeper subtrees closing at the previous visible
  /// row). The resolver clamps the hint to the legal chain; `null` keeps
  /// each zone's classic default (deepest for `below`, the target's own
  /// depth for `above`).
  ///
  /// When every ordered candidate is rejected, one HIDDEN-INTERIOR slot
  /// is tried as a last resort: the inside of a collapsed or empty
  /// container at this boundary (the row above for `above`, the target
  /// itself for `below`). It is outside the depth clamp, so a horizontal
  /// hint can never steer into an invisible subtree; it only ever
  /// converts a dead zone into a legal slot. This is what keeps
  /// resolution invariant under collapsing: collapsing a container
  /// deprioritizes its slots, it does not delete them.
  ///
  /// Returns `null` if the resolved target is invalid (cycle, no-op, or
  /// rejected by [canAcceptDrop]) at every legal level including that
  /// fallback, or if [targetKey] is not in the visible order.
  TreeDropTarget<TKey>? resolve({
    required TKey draggedKey,
    required TKey targetKey,
    required double targetPaintedY,
    required double targetExtent,
    required double pointerY,
    int? preferredDepth,
  }) {
    // Every zone anchors its gap on a visible-order index derived from
    // this row or its ancestors, so a target outside that order has no
    // expressible slot, and letting the -1 propagate would invent one at
    // the top of the list.
    //
    // UNREACHABLE from the drag path, deliberately kept anyway: both of
    // `findRowAtPaintedY`'s scans iterate `controller.visibleNodes`, so
    // every key it can hand back is in the order by construction (its
    // ghost handling substitutes a painted BASE for rows that are still
    // in `visibleNodes`, it does not surface rows that are not). The
    // guard exists for direct callers, which is how this resolver is
    // unit-tested, and it is what lets [TreeDropTarget.gapVisibleIndex]
    // promise a range rather than a range-or-minus-one.
    final targetVisibleIndex = treeController.getVisibleIndex(targetKey);
    if (targetVisibleIndex < 0) {
      return null;
    }

    final localY = (pointerY - targetPaintedY).clamp(0.0, targetExtent);
    final t = targetExtent <= 0 ? 0.0 : localY / targetExtent;

    // Rows that can't take the dragged node as a child collapse to a
    // two-zone split at the MIDPOINT. "Can't take" is structural (self /
    // descendant — a cycle) OR policy: a [canAcceptDrop] that vetoes
    // nesting under this row would leave the `into` third permanently
    // dead, so consult it here and give flat-list-style policies clean
    // ReorderableListView-like midpoint-crossing semantics instead.
    final targetAllowsChildren =
        _canTargetAcceptInto(targetKey, draggedKey) &&
        (canAcceptDrop == null ||
            canAcceptDrop!(
              movingKey: draggedKey,
              newParent: targetKey,
              // A concrete 0, deliberately, and an earlier change to
              // `null` here was a REGRESSION that had to be reverted.
              //
              // The argument for null was that this asks "can the row
              // take children at all", not "may the node land at index
              // 0". True, but the zones downstream cannot act on the
              // distinction: `into` and the below-on-expanded-parent
              // rule both commit to `rawIndex: 0` and RETURN
              // UNCONDITIONALLY, with no fallback chain. So under null a
              // policy that vetoes only index 0 passes this gate, gets
              // the three-zone split, and then resolves null in the
              // middle third while both outer thirds work, which flaps
              // the gap as the pointer crosses 1/3 and 2/3.
              //
              // With 0 the same policy simply collapses the row to a
              // clean two-zone midpoint split. A row that degrades
              // uniformly beats a row with a hole in the middle of it.
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
        final candidates = <_Candidate<TKey>>[];
        final visIndex = targetVisibleIndex;
        // EVERY above candidate opens its gap immediately before the
        // target's row. The chain walks up from the row directly above
        // the target, and that row is by construction the last visible
        // row of every subtree in the chain, so each candidate's
        // "after N" edge lands on exactly this index. Already in hand,
        // so this whole branch costs no extra lookups.
        final aboveGapIndex = visIndex;
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
              gapIndex: aboveGapIndex,
              gapAnchor: null,
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
          gapIndex: aboveGapIndex,
          gapAnchor: null,
        ));
        // NO shallower ancestor climb here, deliberately, even though
        // the `below` zone has one. That climb is sound because it only
        // fires while a node is its parent's LAST live child, which makes
        // "after the node" and "after its ancestor" the SAME visible
        // edge. The mirror does not hold: the parent's own header row
        // sits between "before the parent" and "before its first child",
        // so offering the shallower slot here would place the gap a row
        // away from the pointer, which is the divergence
        // [TreeDropTarget.gapVisibleIndex] exists to eliminate.
        //
        // Consequence, and it is the honest one: dragging a container
        // over another container's expanded contents resolves only at
        // that subtree's tail, because no legal slot for it exists
        // anywhere else along those rows.
        // Hidden-interior fallback: when the row above is a CONTAINER
        // whose contents are not on screen, the chain above cannot see
        // into it (its depth is not greater than the target's), so the
        // slot at the end of its child list silently ceases to exist.
        // Collapsing should deprioritize that slot, not delete it.
        //
        // Appended rather than index 0, because this is the same slot the
        // chain yields when that container IS expanded, which is what
        // makes resolution invariant under collapsing.
        _Candidate<TKey>? lastResort;
        if (visIndex > 0) {
          final prev = treeController.visibleNodes[visIndex - 1];
          // A pending-deletion container is on its way out; adopting it
          // would drop the dragged node into a vanishing subtree. Its
          // live index is meaningless too, exactly as in the chain above.
          // And a container that is already expanded WITH live children
          // was reachable through the chain, so offering it here would
          // duplicate a candidate rather than recover a lost one.
          final prevIsOpen =
              treeController.isExpanded(prev) &&
              treeController.hasLiveChildren(prev);
          if (!treeController.isPendingDeletion(prev) && !prevIsOpen) {
            lastResort = (
              parentKey: prev,
              rawIndex: treeController.liveChildCount(prev),
              depth: treeController.getDepth(prev) + 1,
              gapIndex: null,
              gapAnchor: prev,
            );
          }
        }
        // No hint defaults to the SHALLOWEST candidate — the classic
        // above-target slot (pre-chain semantics); the deeper levels are
        // reached by pointer x or by filter fallback.
        return _resolveCandidates(
          draggedKey: draggedKey,
          targetKey: targetKey,
          zone: zone,
          candidates: candidates,
          lastResort: lastResort,
          preferredDepth: preferredDepth,
          defaultDepth: baseDepth,
          targetPaintedY: targetPaintedY,
          targetExtent: targetExtent,
        );
      case TreeDropZone.into:
        // First-child slot: the edge directly below the target's OWN row,
        // whether or not the target is expanded.
        return _buildTarget(
          draggedKey: draggedKey,
          targetKey: targetKey,
          zone: zone,
          parentKey: targetKey,
          rawIndex: 0,
          depth: treeController.getDepth(targetKey) + 1,
          gapIndex: targetVisibleIndex + 1,
          targetPaintedY: targetPaintedY,
          targetExtent: targetExtent,
        );
      case TreeDropZone.below:
        // Below an EXPANDED target with visible children, "next sibling
        // of target" sits after the whole visible subtree, potentially
        // many rows below the edge directly under the target row (which
        // is visually the FIRST CHILD's slot). Resolve as first-child
        // (identical to `into`) so the gap and the commit agree by
        // construction: conventional tree-DnD semantics. Such a row is never a subtree right-boundary (its
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
            gapIndex: targetVisibleIndex + 1,
            targetPaintedY: targetPaintedY,
            targetExtent: targetExtent,
          );
        }

        // At a subtree right-boundary the slot under the target row is
        // ambiguous — it belongs equally to every ancestor whose
        // subtree ends at this row. Build the candidate chain
        // deepest-first; depths are contiguous (each ancestor level is
        // exactly one shallower).
        // Each candidate anchors its gap on the node whose sibling index
        // it incremented, resolved lazily for the winner only. The levels
        // do NOT share one anchor: the chain climbs on a LIVE-space index
        // while the visible order still contains pending-deletion rows,
        // so a target that is the last live child climbs past an exiting
        // sibling whose rows are still painted, and the ancestor's
        // visible tail includes them while the target's does not.
        final candidates = <_Candidate<TKey>>[
          (
            parentKey: treeController.getParent(targetKey),
            rawIndex: treeController.getIndexInParent(targetKey) + 1,
            depth: treeController.getDepth(targetKey),
            gapIndex: null,
            gapAnchor: targetKey,
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
            gapIndex: null,
            gapAnchor: parent,
          ));
          node = parent;
        }

        // Hidden-interior fallback, mirroring the above zone: reaching
        // here with `targetAllowsChildren` means the first-child rule was
        // skipped because the target is collapsed or has no live
        // children, so its interior slot is exactly what fell out of the
        // candidate space. The gate is exact rather than approximate:
        // `targetAllowsChildren` already carries the cycle check and the
        // identical `canAcceptDrop(newParent: target, index: 0)` query.
        //
        // Consequence worth knowing: whenever `into` is legal on a row,
        // that row's `below` zone can never be dead.
        final _Candidate<TKey>? lastResort = targetAllowsChildren
            ? (
                parentKey: targetKey,
                rawIndex: 0,
                // First-child edge, directly below the target's own row,
                // the same slot `into` names, and deliberately NOT the
                // anchored form that would sit past the target's whole
                // visible subtree.
                //
                // Not because that subtree is off screen: this branch
                // only establishes that no VISIBLE CHILD produced a
                // candidate, which is also true of a target expanded over
                // nothing but pending-deletion children, and those are
                // still painted. It is because index 0 is where the node
                // actually lands, and the gap has to show the slot the
                // commit will use. Anchoring past rows that are on their
                // way out would open the gap below them and then close it
                // somewhere else when the exits finish.
                gapIndex: targetVisibleIndex + 1,
                gapAnchor: null,
                depth: treeController.getDepth(targetKey) + 1,
              )
            : null;

        // No hint defaults to the DEEPEST candidate — also what a
        // handle-drag pointer at the row's right edge clamps to.
        return _resolveCandidates(
          draggedKey: draggedKey,
          targetKey: targetKey,
          zone: zone,
          candidates: candidates,
          lastResort: lastResort,
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
  ///
  /// [lastResort] is a hidden-interior slot: the inside of a collapsed or
  /// empty container at this boundary. It participates in NEITHER the
  /// depth clamp NOR the distance sort, and is tried only once every
  /// ordered candidate has been rejected. That asymmetry is the rule
  /// itself: an x hint pointing into a subtree the user cannot see must
  /// never be a PREFERENCE, and dropping into an invisible container is
  /// acceptable only when the alternative is a dead zone. Admitting it to
  /// the chain would widen `deepest`, so a far-right drag over any leaf
  /// would silently nest into that leaf.
  TreeDropTarget<TKey>? _resolveCandidates({
    required TKey draggedKey,
    required TKey targetKey,
    required TreeDropZone zone,
    required List<_Candidate<TKey>> candidates,
    required int? preferredDepth,
    required int defaultDepth,
    required double targetPaintedY,
    required double targetExtent,
    _Candidate<TKey>? lastResort,
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
        gapIndex: candidate.gapIndex,
        gapAnchor: candidate.gapAnchor,
        targetPaintedY: targetPaintedY,
        targetExtent: targetExtent,
      );
      if (resolved != null) {
        return resolved;
      }
    }
    if (lastResort != null) {
      return _buildTarget(
        draggedKey: draggedKey,
        targetKey: targetKey,
        zone: zone,
        parentKey: lastResort.parentKey,
        rawIndex: lastResort.rawIndex,
        depth: lastResort.depth,
        gapIndex: lastResort.gapIndex,
        gapAnchor: lastResort.gapAnchor,
        targetPaintedY: targetPaintedY,
        targetExtent: targetExtent,
      );
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
    int? gapIndex,
    TKey? gapAnchor,
  }) {
    assert(
      (gapIndex == null) != (gapAnchor == null),
      "_buildTarget needs exactly one of gapIndex / gapAnchor",
    );
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
    // already sits. This is a VALID target: the honest feedback is
    // "drops back here", which make-room paints as an open gap at the
    // original position, and it gives crossing hysteresis instead of a dead
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
        gapVisibleIndex: _resolveGapIndex(gapIndex, gapAnchor),
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
      gapVisibleIndex: _resolveGapIndex(gapIndex, gapAnchor),
      targetPaintedY: targetPaintedY,
      targetExtent: targetExtent,
    );
  }

  /// Resolves a candidate's deferred gap anchor into a visible-order
  /// index. Called only for a candidate that has survived every filter,
  /// so rejected candidates in a boundary chain cost no lookups.
  ///
  /// The anchored form means "just past this node's visible subtree",
  /// which is one row for a leaf or a collapsed node and therefore
  /// reduces to the node's own trailing edge in the common case.
  int _resolveGapIndex(int? gapIndex, TKey? gapAnchor) {
    if (gapIndex != null) {
      return gapIndex;
    }
    final anchor = gapAnchor as TKey;
    final index = treeController.getVisibleIndex(anchor);
    // Unreachable by construction: `resolve` refuses a target outside the
    // visible order, and a visible node's ancestors are all expanded and
    // therefore visible too, so every anchor this can receive is present.
    // Asserting says so; returning a fabricated index would hide the
    // invariant breaking.
    assert(index >= 0, "gap anchor $anchor is not in the visible order");
    return index + treeController.visibleSubtreeSize(anchor);
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

  /// Cheap "can this row accept children as a drop target?" heuristic: the
  /// node is not the dragged key and not one of its descendants. Finer
  /// policies (leaf-only, depth limits) flow through [canAcceptDrop].
  ///
  /// This IS the inclusive same-or-descendant test, negated. It used to be
  /// paired with a separately named helper expressing the same predicate,
  /// so the guard read `!sameOrDescendant(t, d) && canAcceptInto(t, d)`:
  /// one expression ANDed with itself, and a second O(depth) ancestor walk
  /// per pointer move on the hot path this file is otherwise careful about.
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
