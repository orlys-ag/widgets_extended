/// Internal: scroll-related operations for [TreeController].
///
/// Owns the full-extent prefix-sum cache plus the four scroll-API methods
/// ([scrollOffsetOf], [extentOf], [ensureAncestorsExpanded],
/// [animateScrollToKey]). The controller exposes these via thin delegators
/// so the public surface is unchanged.
///
/// Not exported from the package barrel; used only by [TreeController].
library;

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'tree_controller.dart';
import 'types.dart';

/// Scroll orchestration for one [TreeController]. See the library doc for
/// the surface it owns.
///
/// Two of its concerns are stateful and worth knowing before editing it:
/// the full-extent prefix cache, which every offset query reads and any
/// visible-order or extent change invalidates, and the single in-flight
/// animated scroll, whose teardown three different parties can race to
/// perform.
class ScrollOrchestrator<TKey, TData> {
  ScrollOrchestrator({
    required TreeController<TKey, TData> controller,
    required TickerProvider vsync,
  }) : _controller = controller,
       _vsync = vsync;

  final TreeController<TKey, TData> _controller;
  final TickerProvider _vsync;

  /// Set by [dispose]. Checked by the in-flight async paths so a scroll
  /// running when the controller is disposed cancels instead of pumping
  /// frames forever (offstage trees mute the ticker, so the completion
  /// loop's exit conditions can otherwise never fire).
  bool _disposed = false;

  /// The in-flight [_animatedConcurrentScroll] session, held so [dispose]
  /// and a superseding scroll can tear it down SYNCHRONOUSLY. Waiting for
  /// the loop's next iteration is not enough: `TreeController.dispose()`
  /// typically runs inside the vsync State's own dispose, and an active
  /// Ticker at that point trips the framework's active-Ticker assert.
  ///
  /// Animated scrolls are SINGLE-FLIGHT: starting a new one cancels the
  /// in-flight one, since two animations fighting over `position.jumpTo`
  /// is not a meaningful state and the newer target wins. That is what
  /// makes one slot sufficient. It must stay a whole session rather than
  /// loose progress and follower fields: a second scroll would overwrite
  /// those, stranding the first scroll's ticker and listener past
  /// [dispose], which is the active-Ticker assert described above.
  _ActiveScroll? _activeScroll;

  /// Idempotently releases [session]'s resources (follower listener +
  /// progress controller). Callable from the owning loop's `finally`,
  /// from a superseding scroll, and from [dispose]. Whichever runs first
  /// wins, and the rest no-op via [_ActiveScroll.tornDown].
  void _teardownScroll(_ActiveScroll session) {
    if (session.tornDown) {
      return;
    }
    session.tornDown = true;
    _controller.removeAnimationListener(session.follower);
    session.progress.dispose();
  }

  /// Pending single-shot post-frame settle snap for [animateScrollToKey]
  /// (H1 part b). The render layer's `scrollOffsetCorrection` keeps
  /// `pixels` and the offset array in one coordinate system, but an
  /// `animateTo` overwrites corrections tick by tick with ABSOLUTE
  /// values, and a caller-supplied estimator can disagree with
  /// `defaultExtent`; the snap re-derives the target once, next frame.
  /// One slot, newest wins; exactly one iteration and never rescheduled
  /// from inside itself: with the correction in place the no-estimator
  /// re-derive already matches `pixels`, and with an estimator the snap
  /// removes the whole measured-rows residual, which is all iteration
  /// could remove without measuring the remaining rows.
  ({
    TKey key,
    ScrollController scrollController,
    double alignment,
    double sliverBaseOffset,
    double Function(TKey key)? extentEstimator,
  })?
  _pendingSnap;
  bool _snapScheduled = false;

  void _scheduleSettleSnap({
    required TKey key,
    required ScrollController scrollController,
    required double alignment,
    required double sliverBaseOffset,
    required double Function(TKey key)? extentEstimator,
  }) {
    _pendingSnap = (
      key: key,
      scrollController: scrollController,
      alignment: alignment,
      sliverBaseOffset: sliverBaseOffset,
      extentEstimator: extentEstimator,
    );
    if (_snapScheduled) {
      return;
    }
    _snapScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapScheduled = false;
      final snap = _pendingSnap;
      _pendingSnap = null;
      if (snap == null || _disposed) {
        return;
      }
      final sc = snap.scrollController;
      if (!sc.hasClients) {
        return;
      }
      if (_activeScroll != null) {
        // The animated-concurrent follower owns the position.
        return;
      }
      final position = sc.position;
      if (position.userScrollDirection != ScrollDirection.idle) {
        // A user drag or fling took over. `jumpTo` itself goes through
        // `goIdle`, whose activity publishes idle, so this guard rejects
        // exactly user-driven motion, not the snap's own jumps.
        return;
      }
      final sliverOffset = scrollOffsetOf(
        snap.key,
        extentEstimator: snap.extentEstimator,
      );
      if (sliverOffset == null) {
        return;
      }
      final rowExtent = extentOf(
        snap.key,
        extentEstimator: snap.extentEstimator,
      );
      final target =
          snap.sliverBaseOffset +
          sliverOffset -
          (position.viewportDimension - rowExtent) * snap.alignment;
      final clamped = target.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((clamped - position.pixels).abs() > 0.5) {
        position.jumpTo(clamped);
      }
    });
  }

  // ──────────────────────────────────────────────────────────────────────
  // PREFIX-SUM CACHE
  // ──────────────────────────────────────────────────────────────────────
  //
  // Lazy prefix sum of full (non-animated) extents over the current visible
  // order. When valid, `_fullOffsetPrefix[i]` is the sum of
  // `getEstimatedExtentNid(orderNids[k])` for visible indices `0..i-1`,
  // and `_fullOffsetPrefix.length == visibleNodeCount + 1`.
  //
  // Invalidated by visible-order mutations (via the controller's
  // `onOrderMutated` callback) and by [setFullExtent] / [_clearFullExtent]
  // when the stored value actually changes.

  List<double>? _fullOffsetPrefix;
  bool _fullOffsetPrefixDirty = true;

  /// Marks the prefix sum stale. Called from `_order`'s `onOrderMutated`
  /// callback (via the controller wrapper) and from `setFullExtent` /
  /// `_purgeNodeData` when the stored extent changes.
  void invalidatePrefix() {
    _fullOffsetPrefixDirty = true;
  }

  /// Rebuilds [_fullOffsetPrefix] if dirty or stale. O(N) on rebuild,
  /// O(1) when the cache is already valid.
  void _ensureFullOffsetPrefix() {
    final n = _controller.visibleNodeCount;
    final cached = _fullOffsetPrefix;
    if (!_fullOffsetPrefixDirty && cached != null && cached.length == n + 1) {
      return;
    }
    final prefix = List<double>.filled(n + 1, 0.0, growable: false);
    double acc = 0.0;
    final orderNids = _controller.orderNidsView;
    for (int i = 0; i < n; i++) {
      // `getEstimatedExtentNid` already folds the `< 0` sentinel check
      // into a `defaultExtent` fallback for unmeasured nodes.
      acc += _controller.getEstimatedExtentNid(orderNids[i]);
      prefix[i + 1] = acc;
    }
    _fullOffsetPrefix = prefix;
    _fullOffsetPrefixDirty = false;
  }

  /// Prefix-sum full-extent offset up to visible index [index], exclusive.
  /// Rebuilds the cache first when it is stale, so the first call after a
  /// mutation is O(N) and every call until the next one is O(1).
  double fullOffsetAt(int index) {
    _ensureFullOffsetPrefix();
    return _fullOffsetPrefix![index];
  }

  // ──────────────────────────────────────────────────────────────────────
  // PUBLIC SCROLL API (delegated from TreeController)
  // ──────────────────────────────────────────────────────────────────────

  /// Returns the sliver-space scroll offset of [key], or null if [key] is
  /// not in the current visible order. See
  /// [TreeController.scrollOffsetOf] for the full contract.
  double? scrollOffsetOf(
    TKey key, {
    double Function(TKey key)? extentEstimator,
  }) {
    final targetIndex = _controller.getVisibleIndex(key);
    if (targetIndex < 0) return null;
    if (extentEstimator == null) {
      return fullOffsetAt(targetIndex);
    }
    // Slow path: caller supplied an estimator for un-measured nodes. We
    // can't use the cache because it falls back to [defaultExtent], which
    // may disagree with the caller's estimator.
    double offset = 0.0;
    final orderNids = _controller.orderNidsView;
    for (int i = 0; i < targetIndex; i++) {
      // The slow path iterates visible-order nids, and the order buffer's
      // invariants guarantee every entry there is live, so the cast is
      // safe. `as TKey` rather than `!` satisfies the analyzer's
      // nullable-type-parameter check: TKey may itself be nullable, while
      // `keyOfNid` returns a `TKey?` that is known non-null here.
      final k = _controller.keyOfNid(orderNids[i]) as TKey;
      final measured = _controller.getMeasuredExtent(k);
      if (measured != null) {
        offset += measured;
      } else {
        offset += extentEstimator(k);
      }
    }
    return offset;
  }

  /// Returns the best-known full (non-animated) extent for [key]: measured
  /// if available, else estimator, else defaultExtent.
  double extentOf(TKey key, {double Function(TKey key)? extentEstimator}) {
    final measured = _controller.getMeasuredExtent(key);
    if (measured != null) return measured;
    if (extentEstimator != null) return extentEstimator(key);
    return TreeController.defaultExtent;
  }

  /// Synchronously expands every collapsed ancestor of [key].
  int ensureAncestorsExpanded(TKey key) {
    final toExpand = <TKey>[];
    TKey? current = _controller.getParent(key);
    while (current != null) {
      if (!_controller.isExpanded(current)) toExpand.add(current);
      current = _controller.getParent(current);
    }
    if (toExpand.isEmpty) return 0;
    // Expand root-first.
    for (int i = toExpand.length - 1; i >= 0; i--) {
      _controller.expand(key: toExpand[i], animate: false);
    }
    return toExpand.length;
  }

  /// Animates [scrollController] to reveal [key]. See
  /// [TreeController.animateScrollToKey] for the full contract.
  Future<bool> animateScrollToKey(
    TKey key, {
    required ScrollController scrollController,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.linear,
    double alignment = 0.0,
    AncestorExpansionMode ancestorExpansion = AncestorExpansionMode.immediate,
    double Function(TKey key)? extentEstimator,
    double sliverBaseOffset = 0.0,
  }) async {
    assert(
      alignment >= 0.0 && alignment <= 1.0,
      "alignment must be between 0.0 and 1.0",
    );

    if (!scrollController.hasClients) return false;

    // Collect any ancestors that are currently collapsed.
    final collapsedAncestors = <TKey>[];
    {
      TKey? current = _controller.getParent(key);
      while (current != null) {
        if (!_controller.isExpanded(current)) collapsedAncestors.add(current);
        current = _controller.getParent(current);
      }
    }

    // Animated concurrent expand+scroll. Falls back to the standard path
    // when there's nothing to expand or when animations are disabled.
    if (ancestorExpansion == AncestorExpansionMode.animated &&
        collapsedAncestors.isNotEmpty &&
        _controller.animationStyle.expandCollapse.duration != Duration.zero &&
        duration != Duration.zero) {
      return _animatedConcurrentScroll(
        key: key,
        ancestors: collapsedAncestors,
        scrollController: scrollController,
        duration: duration,
        curve: curve,
        alignment: alignment,
        extentEstimator: extentEstimator,
        sliverBaseOffset: sliverBaseOffset,
        waitForQuiescence: false,
      );
    }

    if (ancestorExpansion == AncestorExpansionMode.none &&
        collapsedAncestors.isNotEmpty) {
      return false;
    }

    if (collapsedAncestors.isNotEmpty) {
      final expandedCount = ensureAncestorsExpanded(key);
      if (expandedCount > 0) {
        // The synchronous expansion enlarged the scrollable content, but
        // `position.maxScrollExtent` still reflects the last laid-out
        // geometry, so clamping against it would stop the scroll at the
        // stale max and leave the target row below the viewport. Wait one
        // frame (scheduling one if none is pending) so the enlarged
        // sliver lays out before reading the position. Mirrors the
        // animated-concurrent path's endOfFrame wait + final snap.
        final scheduler = SchedulerBinding.instance;
        if (!scheduler.hasScheduledFrame) {
          scheduler.scheduleFrame();
        }
        await scheduler.endOfFrame;
        if (_disposed || !scrollController.hasClients) return false;
      }
    }

    // H3 (a0): the key must resolve BEFORE either routing decision
    // below. Routing an unresolvable key would both report success (the
    // follower and the final snap have no validity early-out of their
    // own) and cancel an in-flight animated scroll through the
    // single-flight slot. This hoists the existing `sliverOffset == null`
    // test rather than inventing a new one; the null check below stays,
    // now unreachable for a visible key. L13's plain-path session
    // install, when it lands, must sit BELOW this guard.
    if (_controller.getVisibleIndex(key) < 0) {
      return false;
    }

    // H3 (a): the content is still moving, so the target is moving; a
    // one-shot animateTo would clamp against stale geometry and ride the
    // whole duration to the wrong place. Route to the existing follower,
    // which re-derives the target every tick, and hold the returned
    // Future until the tree is quiescent so the final snap lands on
    // settled geometry.
    if (duration != Duration.zero && _controller.hasActiveAnimations) {
      return _animatedConcurrentScroll(
        key: key,
        ancestors: const [],
        scrollController: scrollController,
        duration: duration,
        curve: curve,
        alignment: alignment,
        extentEstimator: extentEstimator,
        sliverBaseOffset: sliverBaseOffset,
        waitForQuiescence: true,
      );
    }

    // H3 (b): a caller-side mutation not yet laid out leaves
    // `maxScrollExtent` describing the pre-mutation content, and the
    // clamp below would silently truncate the target to it. The rule is
    // one-sided and therefore safe: the scrollable's content is at least
    // `sliverBaseOffset + treeTotal` once laid out (later slivers only
    // add), so a materially SMALLER observed max proves a layout is
    // pending. Exactly one wait, never a loop: one frame suffices when
    // no animation is in flight, and the animating case was routed to
    // the follower above.
    {
      final position = scrollController.position;
      if (position.hasViewportDimension && position.hasContentDimensions) {
        final double treeTotal = fullOffsetAt(_controller.visibleNodeCount);
        final double requiredMax =
            sliverBaseOffset + treeTotal - position.viewportDimension;
        if (requiredMax > position.maxScrollExtent + 0.5) {
          final scheduler = SchedulerBinding.instance;
          if (!scheduler.hasScheduledFrame) {
            scheduler.scheduleFrame();
          }
          await scheduler.endOfFrame;
          if (_disposed || !scrollController.hasClients) return false;
        }
      }
    }

    final sliverOffset = scrollOffsetOf(key, extentEstimator: extentEstimator);
    if (sliverOffset == null) return false;

    final position = scrollController.position;
    final viewportExtent = position.viewportDimension;
    final rowExtent = extentOf(key, extentEstimator: extentEstimator);
    final rawTarget =
        sliverBaseOffset +
        sliverOffset -
        (viewportExtent - rowExtent) * alignment;
    final clamped = rawTarget.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (duration == Duration.zero) {
      position.jumpTo(clamped);
    } else {
      await position.animateTo(clamped, duration: duration, curve: curve);
    }
    // H1 part (b): the landing above was computed against pre-layout
    // geometry; the post-frame snap re-derives it after the corrected
    // layout settles. Scheduled, not awaited: the returned Future's
    // timing is unchanged.
    _scheduleSettleSnap(
      key: key,
      scrollController: scrollController,
      alignment: alignment,
      sliverBaseOffset: sliverBaseOffset,
      extentEstimator: extentEstimator,
    );
    return true;
  }

  /// Runs ancestor expansion concurrently with a scroll animation,
  /// re-deriving the target from the current animated offsets on every
  /// tick. Required because the rendered sliver's `scrollExtent` uses
  /// animated extents: `position.maxScrollExtent` is undersized while the
  /// ancestors grow, so a one-shot `animateTo` would clamp short.
  Future<bool> _animatedConcurrentScroll({
    required TKey key,
    required List<TKey> ancestors,
    required ScrollController scrollController,
    required Duration duration,
    required Curve curve,
    required double alignment,
    required double Function(TKey key)? extentEstimator,
    required double sliverBaseOffset,
    // H3: when true, the completion loop also waits for the tree to be
    // quiescent (`hasActiveAnimations` false) before the final snap, so
    // a scroll issued DURING caller-side animations resolves on settled
    // geometry. The animated-ancestor call site passes false and keeps
    // its token-based exit bit-for-bit.
    required bool waitForQuiescence,
  }) async {
    // Mutable, not captured: a [ScrollController] can detach from one
    // [ScrollPosition] and attach to another while this scroll runs (the
    // scrollable rebuilt with a fresh identity), and the old position is
    // disposed on detach. The follower below re-reads the live position
    // every tick and re-seeds this baseline when it changes; see its
    // "position swap" note.
    var lastPosition = scrollController.position;
    var initialPixels = lastPosition.pixels;

    // Dedicated progress animation for the scroll curve. An
    // AnimationController rather than a raw Ticker: it rides the standard
    // ticker pipeline, stays FakeAsync-compatible under test, and avoids
    // the `currentFrameTimeStamp` assertion a hand-rolled ticker hits.
    final scrollProgress = AnimationController(
      vsync: _vsync,
      duration: duration,
    );
    scrollProgress.addListener(_controller.notifyAnimationListenersForScroll);

    // Root-first: each expansion runs against an already-visible parent.
    for (int i = ancestors.length - 1; i >= 0; i--) {
      _controller.expand(key: ancestors[i], animate: true);
    }

    // Snapshot opaque tokens identifying the operation groups we just
    // started. Waiting on identity rather than an operationKey lookup
    // matters because a concurrent collapse and re-expand of the same
    // ancestor swaps in a fresh group under the same key, which would
    // otherwise read as our targets having already settled.
    final startedTokens = <(TKey, Object)>[];
    for (final ancestor in ancestors) {
      final token = _controller.captureOperationGroupToken(ancestor);
      if (token != null) startedTokens.add((ancestor, token));
    }

    scrollProgress.forward();

    void follower() {
      // Position swap: `hasClients` stays true when a controller moves
      // from one scrollable to another in the same frame, so the loop
      // below cannot notice it and the captured position would already
      // be disposed. Re-read the live one every tick, and skip a tick
      // whose position has not been laid out yet (a fresh position has
      // no pixels, viewport or content dimensions until its first
      // layout, and every read below would throw on the null check).
      if (!scrollController.hasClients) {
        return;
      }
      final position = scrollController.position;
      if (!position.hasPixels ||
          !position.hasViewportDimension ||
          !position.hasContentDimensions) {
        return;
      }
      if (!identical(position, lastPosition)) {
        // The lerp baseline belongs to the position that is now gone;
        // measure the remaining curve distance from where the new one
        // actually sits, so the swap does not jump.
        lastPosition = position;
        initialPixels = position.pixels;
      }
      final targetIdx = _controller.getVisibleIndex(key);
      if (targetIdx < 0) return;
      final tCurved = curve.transform(scrollProgress.value);

      // Base offset from the cached full-extent prefix sum (O(1)
      // amortized). Then correct for each animating node whose visible
      // index precedes the target: swap its full extent for its current
      // (animated) extent.
      double currentOffset = fullOffsetAt(targetIdx);
      void correct(TKey k) {
        final idx = _controller.getVisibleIndex(k);
        if (idx < 0 || idx >= targetIdx) return;
        final full =
            _controller.getMeasuredExtent(k) ?? TreeController.defaultExtent;
        currentOffset += _controller.getCurrentExtent(k) - full;
      }

      for (final k in _controller.currentlyAnimatingKeys) {
        correct(k);
      }

      final rowExtent = _controller.getCurrentExtent(key);
      final viewportExtent = position.viewportDimension;
      final desired =
          sliverBaseOffset +
          currentOffset -
          (viewportExtent - rowExtent) * alignment;
      final desiredClamped = desired.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      final scroll = initialPixels + (desiredClamped - initialPixels) * tCurved;
      position.jumpTo(
        scroll.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }

    _controller.addAnimationListener(follower);
    // Single-flight: cancel and tear down any scroll already in flight
    // BEFORE installing this one. Its loop wakes on the next frame, sees
    // its own `cancelled` token, and resolves false without the final
    // snap; its `finally` no-ops (already torn down) and leaves the slot
    // alone (identity check below).
    final superseded = _activeScroll;
    if (superseded != null) {
      superseded.cancelled = true;
      _teardownScroll(superseded);
    }
    final session = _ActiveScroll(scrollProgress, follower);
    _activeScroll = session;

    // Wait for both timelines to complete:
    //   1. The dedicated [scrollProgress], so the curve reaches 1.0.
    //   2. Every ancestor expansion's terminal tick, observable from
    //      outside as its operation group no longer matching the token
    //      captured above.
    //
    // The try/finally makes listener removal and controller disposal
    // structural: every exit path (normal completion, lost clients,
    // cancellation, an unexpected throw) releases both, idempotently. If
    // [dispose] or a superseding scroll already cancelled this session,
    // they tore it down synchronously and [_teardownScroll] no-ops. The
    // `cancelled` check must run before anything touches [scrollProgress],
    // because a cancelled session's controller is already disposed.
    try {
      while (true) {
        if (session.cancelled || _disposed) {
          // Cancelled: exit without the final snap.
          return false;
        }
        if (!scrollController.hasClients) {
          return true;
        }
        final scrollDone =
            scrollProgress.status == AnimationStatus.completed ||
            scrollProgress.status == AnimationStatus.dismissed;
        bool expansionDone = true;
        for (final (opKey, token) in startedTokens) {
          if (_controller.isOperationGroupSame(opKey, token)) {
            expansionDone = false;
            break;
          }
        }
        if (scrollDone &&
            expansionDone &&
            (!waitForQuiescence || !_controller.hasActiveAnimations)) {
          break;
        }
        await SchedulerBinding.instance.endOfFrame;
      }
    } finally {
      _teardownScroll(session);
      // Clear the slot only when it still holds THIS invocation's
      // session, never a successor's: an unconditional null-out here
      // would strand the successor's own teardown handles.
      if (identical(_activeScroll, session)) {
        _activeScroll = null;
      }
    }

    if (!scrollController.hasClients) return true;

    // Final precise snap. Catches estimator/defaultExtent disagreement
    // and cancelled-mid-flight ancestor expansions.
    final finalOffset = scrollOffsetOf(key, extentEstimator: extentEstimator);
    if (finalOffset == null) return true;
    final finalPosition = scrollController.position;
    final viewportExtent = finalPosition.viewportDimension;
    final rowExtent = extentOf(key, extentEstimator: extentEstimator);
    final finalTarget =
        sliverBaseOffset +
        finalOffset -
        (viewportExtent - rowExtent) * alignment;
    finalPosition.jumpTo(
      finalTarget.clamp(
        finalPosition.minScrollExtent,
        finalPosition.maxScrollExtent,
      ),
    );
    return true;
  }

  /// Cancels any in-flight [_animatedConcurrentScroll] and releases the
  /// prefix cache. Wired from [TreeController.dispose].
  ///
  /// Teardown is synchronous, removing the follower listener and
  /// disposing the progress controller here rather than waiting for the
  /// loop's next iteration: the vsync State typically disposes right
  /// after the owning [TreeController], and an active Ticker at that
  /// point trips the framework's assert.
  void dispose() {
    _disposed = true;
    _pendingSnap = null;
    final active = _activeScroll;
    if (active != null) {
      active.cancelled = true;
      _teardownScroll(active);
      _activeScroll = null;
    }
    _fullOffsetPrefix = null;
    _fullOffsetPrefixDirty = true;
  }
}

/// Per-invocation session record for [ScrollOrchestrator]'s animated
/// concurrent scroll. Bundles the resources needing teardown with the
/// flags that make teardown single-flight-safe: [cancelled] is the
/// per-session cancellation token the completion loop polls (a successor
/// or [ScrollOrchestrator.dispose] sets it), [tornDown] makes teardown
/// idempotent across the three parties that may race to perform it (the
/// owning loop's `finally`, a superseding scroll, dispose).
class _ActiveScroll {
  _ActiveScroll(this.progress, this.follower);

  final AnimationController progress;
  final VoidCallback follower;
  bool cancelled = false;
  bool tornDown = false;
}
