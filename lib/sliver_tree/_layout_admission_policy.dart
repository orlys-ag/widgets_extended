/// Internal: cache-region admission policy for [RenderSliverTree].
///
/// Owns the dual-accumulator (live/post) admission decision used in the
/// non-bulk path of the layout's Pass 2. Stateless apart from a back-pointer
/// to its [TreeController] — every per-frame input is passed in via
/// parameters. Mirrors the extracted-helper pattern set by
/// [StickyHeaderComputer].
///
/// Not exported from the package barrel; used only by [RenderSliverTree].
library;

import 'dart:typed_data';

import 'tree_controller.dart';

/// Cache-region admission policy. Decides which visible-order positions
/// should be admitted into the cache region during Pass 2 of the layout.
///
/// The bulk-only fast path is handled separately (inline on the render
/// object) — this policy is for the non-bulk path where extent animations
/// require the dual-view (live extent / post-animation extent) cap.
class LayoutAdmissionPolicy<TKey, TData> {
  LayoutAdmissionPolicy({required TreeController<TKey, TData> controller})
    : _controller = controller;

  TreeController<TKey, TData> _controller;
  TreeController<TKey, TData> get controller => _controller;
  set controller(TreeController<TKey, TData> value) {
    if (identical(_controller, value)) return;
    _controller = value;
  }

  /// Admits cache-region members into [inCacheRegionByNid] (writes 1) and
  /// fires [onCacheRegionAdmit] for each admitted nid in iteration order.
  /// Returns the new `cacheEndIndex` (one past the last admitted index).
  ///
  /// Dual-view semantics:
  ///   * liveAccum — uses full extent for animating rows; caps admission
  ///     at the pre-animation row count during enters (prevents
  ///     mass-mounting the entering subtree on frame 1 of an expand).
  ///   * postAccum — uses target extent (full for enters, 0 for exits,
  ///     live for non-animating); tracks the post-animation layout.
  /// A row is admitted when it passes either view, with the constraint
  /// that exits can only be admitted via the LIVE view.
  ///
  /// Loop stops only when BOTH views agree no future row could be admitted.
  int admit({
    required int cacheStartIndex,
    required List<TKey> visibleNodes,
    required Float64List nodeOffsetsByNid,
    required Float64List nodeExtentsByNid,
    required Uint8List inCacheRegionByNid,
    required void Function(int nid) onCacheRegionAdmit,
    required double effectiveCacheEnd,
    required double slideOverreach,
    required double remainingCacheExtent,
  }) {
    int cacheEndIndex = cacheStartIndex;
    double liveAccum = 0.0;
    double postAccum = 0.0;
    final orderNids = _controller.orderNidsView;
    final double postOffsetOrigin = cacheStartIndex < visibleNodes.length
        ? nodeOffsetsByNid[orderNids[cacheStartIndex]]
        : 0.0;
    double postOffsetCumul = 0.0;
    // The admission walk starts at `cacheStart - slideOverreach` and may
    // continue through `cacheEnd + slideOverreach`. Rows from both widened
    // sides consume accumulator budget, so the cap must cover the full
    // widened interval, not just one extra side.
    final double budgetCap = remainingCacheExtent + slideOverreach * 2.0;
    for (int i = cacheStartIndex; i < visibleNodes.length; i++) {
      final nid = orderNids[i];

      final double liveOffset = nodeOffsetsByNid[nid];
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
      final bool isAnimating = _controller.isAnimatingNid(nid);
      final bool isExit = isAnimating && _controller.isExitingNid(nid);
      final bool admit = liveBudgetOk || (!isExit && postBudgetOk);
      if (admit) {
        inCacheRegionByNid[nid] = 1;
        onCacheRegionAdmit(nid);
        cacheEndIndex = i + 1;
      }

      // Update accumulators regardless of admission — the budget is a
      // cumulative quantity measured over every row the loop has
      // considered, not just admitted ones. Future-row break decisions
      // depend on these.
      final double liveContribution;
      final double postContribution;
      if (isAnimating) {
        final full = _controller.getEstimatedExtentNid(nid);
        liveContribution = full;
        postContribution = isExit ? 0.0 : full;
      } else {
        final live = nodeExtentsByNid[nid];
        liveContribution = live;
        postContribution = live;
      }
      liveAccum += liveContribution;
      postAccum += postContribution;
      postOffsetCumul += postContribution;
    }
    return cacheEndIndex;
  }
}
