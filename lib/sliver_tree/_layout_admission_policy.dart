/// Internal: cache-region admission policy for [RenderSliverTree].
///
/// Owns the cache-region admission decision for BOTH arms of the layout's
/// Pass 2: two accumulators (live/post), under a geometric paint-region
/// floor. The bulk arm arrives as DATA, a [BulkAdmissionView] the render
/// object passes per frame, not as a second loop. Stateless apart from a
/// back-pointer to its [TreeController]: every per-frame input arrives as
/// a parameter, and nothing is cached between calls.
///
/// Not exported from the package barrel; used only by [RenderSliverTree].
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'tree_controller.dart';
import 'types.dart';

/// Per-frame view of the bulk fast path's admission inputs, passed by the
/// render object when the frame decides on the BULK arm. Carries the
/// position-indexed cumulative prefix sums, the curved group value, the
/// group direction, the frame's [BulkAnimationData] snapshot for
/// membership, and whether any non-member row measures exactly 0 px
/// (which routes the collapse phase's survivor enumeration to a linear
/// scan, because the hop cannot see a zero-extent survivor).
class BulkAdmissionView<TKey> {
  BulkAdmissionView({
    required this.stableCumulative,
    required this.fullCumulative,
    required this.value,
    required this.isCollapsing,
    required this.bulkData,
    required this.hasZeroExtentNonMember,
  });

  /// Prefix sums of NON-member full extents; entry `i` covers rows
  /// `[0, i)`. Valid for indices `0..visibleNodes.length`.
  final Float64List stableCumulative;

  /// Prefix sums of MEMBER full extents, same indexing.
  final Float64List fullCumulative;

  /// The curved bulk group value the frame's offsets are computed with.
  final double value;

  /// Whether the group is collapsing ([BulkAnimationData.isCollapsing]).
  final bool isCollapsing;

  /// The frame's membership snapshot.
  final BulkAnimationData<TKey> bulkData;

  /// True when some non-member row's full extent is exactly 0.0.
  final bool hasZeroExtentNonMember;
}

/// Cache-region admission policy. Decides which visible-order positions
/// should be admitted into the cache region during Pass 2 of the layout.
///
/// BOTH arms of Pass 2 decide here, under one copy of the rule. The
/// NON-BULK arm reads each row's position and extent from the render
/// object's per-nid slots, and weighs where the row is now against where
/// it ends up, because an extent animation makes the two disagree. The
/// BULK arm passes a [BulkAdmissionView] instead, and the same two views
/// take closed forms on it: the live position is
/// `stableCumulative[i] + value * fullCumulative[i]`, and the post view
/// charges 0 for a member of a COLLAPSING group. That post view is the one
/// the render object's old inline bulk loop never grew, which is why rows
/// after a collapsing subtree were never pre-mounted however far the
/// subtree had shrunk.
///
/// A collapse resolves that post view WITHOUT a walk: every member charges
/// 0, so its admissible set is a prefix found by binary search on
/// `stableCumulative`, and the survivors inside it are reached by
/// survivor-to-survivor hops. A 200k-row `collapseAll` therefore does not
/// pay O(N) per frame, which is the whole reason the bulk fast path
/// exists.
///
/// A row taller than the cache extent can exhaust both weighings while
/// later rows are still on screen, which is what the paint-region floor
/// exists to prevent.
///
/// This class writes exactly one piece of render state, the
/// `inCacheRegionByNid` flag whose meaning it owns. The per-nid offset and
/// extent slots stay the render object's: on the bulk arm its
/// [onCacheRegionAdmit] callback writes them for each admitted row.
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
  /// fires `onCacheRegionAdmit(nid, visibleIndex)` for each admitted nid,
  /// in ascending visible-index order. The callback carries the index
  /// because the CALLER writes that row's per-nid offset and extent slots
  /// from it, so admission has exactly three effects and all three happen
  /// at one site: the flag here, the caller's sparse-track append, and
  /// those two slots. `inCacheRegionByNid[nid] != 0` therefore means
  /// precisely "admitted this layout, and its per-nid slots were written
  /// this layout", an invariant held by construction rather than by two
  /// sites staying in step.
  ///
  /// Returns the new `cacheEndIndex`, one past the last admitted index.
  /// That is an ITERATION BOUND, never a membership test:
  /// `[cacheStartIndex, cacheEndIndex)` contains rows this method iterated
  /// past without admitting, and on a bulk collapse it contains long runs
  /// it never visited at all. To ask whether a row was admitted, or
  /// whether its per-nid slots are fresh, read [inCacheRegionByNid]; to
  /// VISIT the admitted rows, iterate the caller's sparse track.
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
  /// Both are spent against `budgetCap`, which is the width of the WINDOW
  /// `[effectiveCacheStart, effectiveCacheEnd)`, so both have to measure
  /// that same window. The walk starts at the row CONTAINING
  /// [effectiveCacheStart], not at a row whose top coincides with it, so
  /// both start at the seed `nodeOffsetsByNid[first] - effectiveCacheStart`,
  /// the signed distance from the window's start to the leading row's top
  /// (0 when the walk starts past the end of the visible order). The seed is
  /// negative in the scrolled case, handing back the part of the leading row
  /// that lies ABOVE the window and that the window's budget must not be
  /// charged for; it is positive when the window starts before the content
  /// (scroll offset 0 with a non-zero [slideOverreach], where
  /// [effectiveCacheStart] is negative), which cancels the leading half of
  /// `slideOverreach * 2.0` that no row can occupy.
  ///
  /// Admission is then a THREE-WAY decision:
  ///
  /// - either budget view has room, except that an exit can only be
  ///   admitted through the live view, having no post-animation position
  ///   worth pre-mounting for;
  /// - or the PAINT FLOOR holds: the row is NOT animating and its live span
  ///   intersects `[paintRegionStart, paintRegionEnd)`, the region the
  ///   caller passes as `scrollOffset` and
  ///   `scrollOffset + remainingPaintExtent`.
  ///
  /// The floor is geometric, not budgeted, and it exists because the budget
  /// views can be exhausted while later rows are still on screen: one row
  /// taller than the cache extent does it on its own, and a row the viewport
  /// paints but nobody built is a blank band. Animating rows are excluded
  /// from the floor, so an enter's sub-pixel rows cannot reach it and the
  /// mass-mount cap the two views impose is untouched.
  ///
  /// The loop stops once both views agree no later row could be admitted
  /// AND the floor does not hold for the current row. That still terminates:
  /// live offsets are monotonically non-decreasing, so once a row's
  /// `liveOffset` reaches [paintRegionEnd] the floor is false for every
  /// later row, animating or not, and the two-view stop condition applies
  /// unchanged.
  ///
  /// The stop is CONSERVATIVE where both views are exhausted at an
  /// ANIMATING row whose live offset is still inside the paint region: the
  /// walk ends at that row, so the floor reaches no further. It still
  /// admits no fewer rows than it did before the floor existed, both the
  /// stop and the admission only gained a disjunct, but it does mean the
  /// floor does not repair a blank band that begins below such a row.
  ///
  /// On the BULK arm ([BulkAdmissionView] non-null) the same two views take
  /// closed forms, and nothing else about the rule changes:
  ///
  /// - the live position is `stableCumulative[i] + value *
  ///   fullCumulative[i]`, the animated offset the render object's
  ///   `_offsetAtVisibleIndex` computes, not a per-nid slot read;
  /// - both views charge the row its FULL extent
  ///   ([TreeController.getEstimatedExtentNid]), for the same reason the
  ///   non-bulk arm charges an animating row its full extent: it is what
  ///   holds admission near the pre-animation row count;
  /// - the post view charges 0 for a MEMBER of a COLLAPSING group. That is
  ///   the exit rule with `isCollapsing && containsMemberNid(nid)` standing
  ///   in for `isAnimatingNid && isExitingNid`; a bulk group's direction is
  ///   uniform by construction ([BulkAnimationData.isCollapsing]).
  ///
  /// For an EXPAND the post charge equals the live charge, so the post view
  /// adds nothing and the walk stops where the live view stops, which is
  /// what keeps frame 1 of `expandAll` from mass-mounting the entering
  /// subtree. For a COLLAPSE the post view's admissible set is a PREFIX,
  /// because `postAccum(i)` reduces to a difference of `stableCumulative`,
  /// so it is resolved by binary search and its survivors are enumerated by
  /// survivor-to-survivor hops rather than by walking the collapsing
  /// subtree. Rows that phase hops over are NOT admitted and NOT flagged,
  /// which is what routes them to the render object's per-nid freshness
  /// paths instead of leaving them silently stale.
  int admit({
    required int cacheStartIndex,
    required List<TKey> visibleNodes,
    required Float64List nodeOffsetsByNid,
    required Float64List nodeExtentsByNid,
    required Uint8List inCacheRegionByNid,
    required void Function(int nid, int visibleIndex) onCacheRegionAdmit,
    required double effectiveCacheStart,
    required double effectiveCacheEnd,
    required double paintRegionStart,
    required double paintRegionEnd,
    required double slideOverreach,
    required double remainingCacheExtent,
    BulkAdmissionView<TKey>? bulkView,
  }) {
    int cacheEndIndex = cacheStartIndex;
    final orderNids = _controller.orderNidsView;
    // On the bulk arm the per-nid offset slot is written only for rows
    // already admitted this layout, so the origin (and every per-row live
    // position below) comes from the view's closed form instead.
    final double postOffsetOrigin;
    if (cacheStartIndex < visibleNodes.length) {
      postOffsetOrigin = bulkView != null
          ? bulkView.stableCumulative[cacheStartIndex] +
                bulkView.value * bulkView.fullCumulative[cacheStartIndex]
          : nodeOffsetsByNid[orderNids[cacheStartIndex]];
    } else {
      postOffsetOrigin = 0.0;
    }
    // Seed: the signed distance from the window's start to the leading
    // row's top, negative in the scrolled case, handing back the part of
    // the leading row that lies ABOVE the window and that the window's
    // budget must not be charged for. `postOffsetOrigin` IS the leading
    // row's live top on both arms.
    final double seed = cacheStartIndex < visibleNodes.length
        ? postOffsetOrigin - effectiveCacheStart
        : 0.0;
    double liveAccum = seed;
    double postAccum = seed;
    double postOffsetCumul = 0.0;
    // The admission walk starts at the row CONTAINING
    // `cacheStart - slideOverreach` and may continue through
    // `cacheEnd + slideOverreach`. Rows from both widened sides consume
    // accumulator budget, so the cap must cover the full widened interval,
    // not just one extra side. The cap therefore measures an INTERVAL, and
    // the seed above is what makes the accumulators measure the same one:
    // without it the leading row is charged in full while occupying only
    // the part of itself that falls inside that interval.
    final double budgetCap = remainingCacheExtent + slideOverreach * 2.0;
    // Once the live view fails it stays failed (`liveOffset` and
    // `liveAccum` are monotone on both arms), so a run of exits past that
    // point can skip the estimate read: nothing can consume their live
    // charge, and an exit charges the post view 0 by rule.
    bool liveDead = false;
    for (int i = cacheStartIndex; i < visibleNodes.length; i++) {
      final nid = orderNids[i];

      final double liveOffset = bulkView != null
          ? bulkView.stableCumulative[i] +
                bulkView.value * bulkView.fullCumulative[i]
          : nodeOffsetsByNid[nid];
      final double postOffset = postOffsetOrigin + postOffsetCumul;

      final bool liveBudgetOk =
          liveOffset < effectiveCacheEnd && liveAccum < budgetCap;
      final bool postBudgetOk =
          postOffset < effectiveCacheEnd && postAccum < budgetCap;
      if (!liveBudgetOk) {
        liveDead = true;
      }

      // [isAnimatingNid] and [isExitingNid] are O(1) (nid-keyed mirror).
      // Read BEFORE the break, not after it: the floor below is guarded on
      // `!isAnimating` and the break consults that same floor, so both
      // decisions need this row's animation state.
      //
      // On the BULK arm neither mirror is consulted. The view answers both
      // questions in closed form, "animating" being membership of the
      // running group and "exit" being membership of a COLLAPSING one, so
      // the same two locals are produced without a per-row read.
      final bool isAnimating;
      final bool isExit;
      final double liveExtent;
      if (bulkView != null) {
        final bool isMember = bulkView.bulkData.containsMemberNid(nid);
        isAnimating = isMember;
        isExit = bulkView.isCollapsing && isMember;
        // Read for the floor only, which the `!isAnimating` guard limits
        // to NON-members, whose live extent IS the full estimate; the
        // per-nid slot is not written for the row being decided here.
        liveExtent = _controller.getEstimatedExtentNid(nid);
      } else {
        isAnimating = _controller.isAnimatingNid(nid);
        isExit = isAnimating && _controller.isExitingNid(nid);
        liveExtent = nodeExtentsByNid[nid];
      }

      // The paint floor: a NON-ANIMATING row whose live span intersects the
      // paint region is admitted whatever the two budget views say, because
      // the viewport paints it and a row nobody built paints as a blank
      // band. A single row taller than the cache extent exhausts both views
      // on its own, which is how rows still on screen below it came to be
      // refused. Animating rows are excluded deliberately: on frame 1 of an
      // expand the entering subtree sits at sub-pixel extents packed inside
      // the paint region, so an unguarded floor would hold this loop open
      // across the whole subtree and destroy its bound. (On the bulk arm
      // "animating" is membership, so the guard also keeps sub-pixel
      // MEMBERS out of the floor.)
      final bool paintFloor = !isAnimating &&
          liveOffset < paintRegionEnd &&
          liveOffset + liveExtent > paintRegionStart;

      // Both views failed and the floor does not hold: offsets and
      // accumulators only grow, and `liveOffset` is monotonically
      // non-decreasing on both arms (the bulk live position is a sum of
      // two non-decreasing prefix sums of non-negative extents), so once
      // it reaches `paintRegionEnd` the floor is false for every later
      // row. No future row can be admitted BY THIS WALK, which is the
      // whole decision on the non-bulk arm and on a bulk EXPAND. On a
      // bulk COLLAPSE it is phase 1 only: the post view's prefix is
      // resolved after this loop, by binary search, and admits survivors
      // past this break.
      //
      // The stop is CONSERVATIVE, and that is the whole of what the guarded
      // floor gives up. The floor is guarded on `!isAnimating`, so if both
      // views are exhausted at an ANIMATING row whose live offset is still
      // inside the paint region (the accumulator update below charges an
      // animating row its FULL extent while its live offset reflects the
      // shrunken animated position, which is what caps mass-mounting on
      // frame 1 of an expand), the walk ends at that row even though a
      // later NON-animating row at the same live offset would have
      // satisfied the floor. Ending there admits no fewer rows than this
      // loop admitted before the floor existed, since both the stop and the
      // admission below only gained a disjunct; it bounds how far the floor
      // reaches, it does not change what an expand mounts. Breaking on
      // `liveOffset >= paintRegionEnd` instead would reach those rows and
      // hold the loop open across the whole entering subtree, which is
      // exactly what the guard exists to prevent. A row below the stop that
      // was mounted on an earlier frame still paints in the right place:
      // the post-sticky parentData refresh rewrites `layoutOffset` for
      // mounted off-cache rows.
      if (!liveBudgetOk && !postBudgetOk && !paintFloor) {
        break;
      }
      if (bulkView != null && !liveBudgetOk && !paintFloor) {
        // Bulk arm: the live view (plus the floor) is the whole of phase
        // 1. On an EXPAND the post view is identical to the live view, so
        // nothing is lost; on a COLLAPSE members keep the post
        // accumulator flat, so waiting for the post view to fail would
        // walk the entire collapsing subtree, which is the O(N) the
        // collapse phase's binary search exists to avoid. Survivors past
        // this cut are admitted by that phase, not by this walk.
        break;
      }

      // Exits admit through the LIVE view only; they have no post-animation
      // position and should not be pre-mounted just because the post view
      // has budget. The floor cannot admit one either, being guarded on
      // `!isAnimating`.
      final bool admit =
          liveBudgetOk || (!isExit && postBudgetOk) || paintFloor;
      if (admit) {
        inCacheRegionByNid[nid] = 1;
        onCacheRegionAdmit(nid, i);
        cacheEndIndex = i + 1;
      }

      // Update accumulators regardless of admission: the budget is measured
      // over the window from `effectiveCacheStart`, seeded with the leading
      // row's out-of-window part and then charged for every row the loop has
      // considered, not just the admitted ones. The break decision above
      // still depends on them, though no longer on them alone; a row the
      // paint floor admitted is charged here like any other, so the floor
      // cannot make a later row look cheaper than it is.
      final double liveContribution;
      final double postContribution;
      if (isExit && liveDead) {
        // Nothing can read this row's extent: the live view is
        // permanently dead, and an exit contributes 0.0 to the post view.
        liveContribution = 0.0;
        postContribution = 0.0;
      } else if (isAnimating) {
        final full = _controller.getEstimatedExtentNid(nid);
        liveContribution = full;
        postContribution = isExit ? 0.0 : full;
      } else {
        // Bulk arm: the per-nid extent slot is written only for admitted
        // rows, so a non-member's charge comes from the same estimate the
        // cumulatives were built from.
        final live = bulkView != null
            ? _controller.getEstimatedExtentNid(nid)
            : nodeExtentsByNid[nid];
        liveContribution = live;
        postContribution = live;
      }
      liveAccum += liveContribution;
      postAccum += postContribution;
      postOffsetCumul += postContribution;
    }

    // Collapse phase: for a COLLAPSE every member charges the post view 0,
    // so `postAccum(i)` reduces to
    // `stableCumulative[i] - stableCumulative[cacheStartIndex]` and the
    // post view's admissible set is a PREFIX, cut where that difference
    // reaches the budget. Survivors (non-members) inside it are admitted
    // without walking the collapsing subtree. For an EXPAND the post
    // charge equals the live charge, the post view adds nothing, and this
    // phase must NOT run: returning here is what preserves the frame-1
    // mass-mount cap.
    if (bulkView != null && bulkView.isCollapsing) {
      cacheEndIndex = _admitCollapsePrefix(
        bulkView: bulkView,
        phase1End: cacheEndIndex,
        n: visibleNodes.length,
        inCacheRegionByNid: inCacheRegionByNid,
        onCacheRegionAdmit: onCacheRegionAdmit,
        effectiveCacheEnd: effectiveCacheEnd,
        budgetCap: budgetCap,
        seed: seed,
        postOffsetOrigin: postOffsetOrigin,
        cacheStartIndex: cacheStartIndex,
      );
    }
    return cacheEndIndex;
  }

  /// Phase 2 of a bulk COLLAPSE: admits the surviving (non-member) rows
  /// inside the post view's prefix without walking the collapsing
  /// subtree. Each hop is one upper-bound binary search on the
  /// non-decreasing `stableCumulative`, which is constant across a run of
  /// members; when a non-member row measures exactly 0 px the hop cannot
  /// see it, so [BulkAdmissionView.hasZeroExtentNonMember] routes this
  /// phase to a plain linear scan instead.
  int _admitCollapsePrefix({
    required BulkAdmissionView<TKey> bulkView,
    required int phase1End,
    required int n,
    required Uint8List inCacheRegionByNid,
    required void Function(int nid, int visibleIndex) onCacheRegionAdmit,
    required double effectiveCacheEnd,
    required double budgetCap,
    required double seed,
    required double postOffsetOrigin,
    required int cacheStartIndex,
  }) {
    final stable = bulkView.stableCumulative;
    // Row i is post-admissible while
    // `stable[i] - stable[cacheStartIndex] < threshold`, folding the
    // position test and the budget test over the same monotone quantity.
    // With the seed, `postAccum(i)` is `seed + (stable[i] - stable[cs])`,
    // so the budget term folds to `budgetCap - seed`. Since
    // `effectiveCacheStart + budgetCap == effectiveCacheEnd` identically
    // while `seed == postOffsetOrigin - effectiveCacheStart`, the two
    // min-terms coincide; both are kept spelled out so the fold survives
    // either input changing independently.
    final double threshold = math.min(
      effectiveCacheEnd - postOffsetOrigin,
      budgetCap - seed,
    );
    if (threshold <= 0.0) {
      return phase1End;
    }
    final double cutValue = stable[cacheStartIndex] + threshold;
    final orderNids = _controller.orderNidsView;
    int end = phase1End;
    if (bulkView.hasZeroExtentNonMember) {
      // Linear fallback: no worse than the naive walk it replaces, and
      // only reachable when a row widget measures a survivor at 0 px.
      final data = bulkView.bulkData;
      for (int i = phase1End; i < n; i++) {
        if (stable[i] >= cutValue) {
          break;
        }
        final nid = orderNids[i];
        if (data.containsMemberNid(nid)) {
          continue;
        }
        if (inCacheRegionByNid[nid] == 0) {
          inCacheRegionByNid[nid] = 1;
          onCacheRegionAdmit(nid, i);
        }
        end = i + 1;
      }
      return end;
    }
    int from = phase1End;
    while (from < n && stable[from] < cutValue) {
      // First k in (from, n] with stable[k] > stable[from]; k - 1 is the
      // next surviving (non-member) row. stable[k - 1] == stable[from],
      // so the loop condition above is exactly the survivor's own
      // admissibility test.
      final int k = _firstGreater(stable, from + 1, n, stable[from]);
      if (k > n) {
        // Every remaining row is a member; nothing left to admit.
        break;
      }
      final int survivor = k - 1;
      final int nid = orderNids[survivor];
      if (inCacheRegionByNid[nid] == 0) {
        inCacheRegionByNid[nid] = 1;
        onCacheRegionAdmit(nid, survivor);
      }
      end = survivor + 1;
      from = k;
    }
    return end;
  }

  /// First index `k` in `[lo, n]` with `stable[k] > target`; `n + 1` when
  /// none. `stable` is non-decreasing over `[0, n]`.
  static int _firstGreater(Float64List stable, int lo, int n, double target) {
    int low = lo;
    int high = n + 1;
    while (low < high) {
      final int mid = (low + high) >> 1;
      if (stable[mid] > target) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }
}
