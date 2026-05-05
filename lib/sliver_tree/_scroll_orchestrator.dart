/// Internal: scroll-related operations for [TreeController].
///
/// Owns the full-extent prefix-sum cache plus the four scroll-API methods
/// ([scrollOffsetOf], [extentOf], [ensureAncestorsExpanded],
/// [animateScrollToKey]). The controller exposes these via thin delegators
/// so the public surface is unchanged.
///
/// Not exported from the package barrel; used only by [TreeController].
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'tree_controller.dart';
import 'types.dart';

/// Scroll orchestration. See library docs.
class ScrollOrchestrator<TKey, TData> {
  ScrollOrchestrator({
    required TreeController<TKey, TData> controller,
    required TickerProvider vsync,
  }) : _controller = controller,
       _vsync = vsync;

  final TreeController<TKey, TData> _controller;
  final TickerProvider _vsync;

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

  /// Returns the prefix-sum full-extent offset up to visible index [index]
  /// (exclusive). Public so the controller can access it via a thin
  /// shim if any other path inside the controller still needs it.
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
      // The slow path iterates visible-order nids — every entry there is
      // guaranteed live by the order buffer's invariants, so the cast is
      // safe. `as TKey` instead of `!` to satisfy the analyzer's
      // nullable-type-parameter check (TKey itself may be nullable; the
      // result of `keyOfNid` is `TKey?` which we know is non-null here).
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
    Curve curve = Curves.easeInOut,
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
        _controller.animationDuration != Duration.zero &&
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
      );
    }

    if (ancestorExpansion == AncestorExpansionMode.none &&
        collapsedAncestors.isNotEmpty) {
      return false;
    }

    if (collapsedAncestors.isNotEmpty) {
      ensureAncestorsExpanded(key);
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
    return true;
  }

  /// Runs ancestor expansion concurrently with a scroll animation. Each
  /// animation tick re-derives the target from the current animated
  /// offsets. Required because the rendered sliver's `scrollExtent` uses
  /// animated extents — `position.maxScrollExtent` is undersized while
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
  }) async {
    final position = scrollController.position;
    final initialPixels = position.pixels;

    // Dedicated progress animation for the scroll curve. See
    // [TreeController._animatedConcurrentScroll]'s original commentary
    // for why this is an [AnimationController] (Ticker pipeline,
    // FakeAsync compatibility, no `currentFrameTimeStamp` assertion).
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
    // started. We wait on identity (not operationKey lookup) so a
    // concurrent collapse + re-expand of the same ancestor — which
    // would swap in a fresh group under the same key — does not mask
    // our targets as already settled.
    final startedTokens = <(TKey, Object)>[];
    for (final ancestor in ancestors) {
      final token = _controller.captureOperationGroupToken(ancestor);
      if (token != null) startedTokens.add((ancestor, token));
    }

    scrollProgress.forward();

    void follower() {
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
      final scroll =
          initialPixels + (desiredClamped - initialPixels) * tCurved;
      position.jumpTo(
        scroll.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }

    _controller.addAnimationListener(follower);

    // Wait for both timelines to complete:
    //   1. The dedicated [scrollProgress] (so the curve reaches 1.0).
    //   2. Every ancestor expansion's terminal V=1.0 tick (observable
    //      externally as the operation group's identity disappearing
    //      from the controller's _operationGroups map).
    while (true) {
      if (!scrollController.hasClients) {
        _controller.removeAnimationListener(follower);
        scrollProgress.dispose();
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
      if (scrollDone && expansionDone) break;
      await SchedulerBinding.instance.endOfFrame;
    }

    _controller.removeAnimationListener(follower);
    scrollProgress.dispose();

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

  /// No-op forward-compat hook. Today the orchestrator owns no disposable
  /// resources (the AnimationController inside `_animatedConcurrentScroll`
  /// is a method-local that disposes itself when the loop completes).
  void dispose() {
    _fullOffsetPrefix = null;
    _fullOffsetPrefixDirty = true;
  }
}
