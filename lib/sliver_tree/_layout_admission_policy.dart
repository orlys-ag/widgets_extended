/// Internal: cache-region admission policy for [RenderSliverTree].
///
/// Owns the dual-accumulator (live/post) admission decision used in the
/// non-bulk path of the layout's Pass 2. Stateless apart from a
/// back-pointer to its [TreeController]: every per-frame input arrives as
/// a parameter, and nothing is cached between calls.
///
/// Not exported from the package barrel; used only by [RenderSliverTree].
library;

import 'dart:typed_data';

import 'tree_controller.dart';

/// Cache-region admission policy. Decides which visible-order positions
/// should be admitted into the cache region during Pass 2 of the layout.
///
/// The bulk-only fast path is handled separately, inline on the render
/// object. This policy serves the non-bulk path, where an extent
/// animation makes a row's current position and its post-animation
/// position disagree, so admission has to weigh both.
class LayoutAdmissionPolicy<TKey, TData> {
  LayoutAdmissionPolicy({required TreeController<TKey, TData> controller})
    : _controller = controller;

  TreeController<TKey, TData> _controller;

  /// The controller admission reads structure and animation state from.
  /// Re-bindable so a render object that swaps controllers keeps one
  /// policy instance; assigning the same instance is a no-op.
  TreeController<TKey, TData> get controller => _controller;
  set controller(TreeController<TKey, TData> value) {
    if (identical(_controller, value)) return;
    _controller = value;
  }

  /// Admits cache-region members into [inCacheRegionByNid] (writes 1) and
  /// fires [onCacheRegionAdmit] for each admitted nid in iteration order.
  /// Returns the new `cacheEndIndex`, one past the last admitted index.
  ///
  /// Two accumulators run in parallel, because an extent animation makes
  /// "where the row is now" and "where it will end up" disagree:
  ///
  /// - liveAccum tracks the current layout, charging animating rows their
  ///   FULL extent. That fills the budget faster during an enter, which
  ///   is what holds admission near the pre-animation row count instead
  ///   of mass-mounting the entering subtree on frame 1 of an expand.
  /// - postAccum tracks the post-animation layout, charging each row its
  ///   target extent: full for enters, 0 for exits, live otherwise.
  ///
  /// A row is admitted when EITHER view has room, except that an exit can
  /// only be admitted through the live view, having no post-animation
  /// position worth pre-mounting for. The loop stops only once both views
  /// agree no later row could be admitted.
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

      // Both views failed: offsets and accumulators only grow, so no
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

      // Update accumulators regardless of admission: the budget is
      // measured over every row the loop has considered, not just the
      // admitted ones, and the break decision above depends on them.
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
