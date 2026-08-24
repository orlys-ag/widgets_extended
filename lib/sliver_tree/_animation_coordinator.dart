/// Internal: facade over the five animation sources (standalone,
/// per-operation groups, bulk, slide, make-room preview), plus the
/// cross-source state that spans them.
///
/// The first three drive layout and are unioned by [hasActiveAnimations];
/// slide and preview are paint-only and are read through the slide-delta
/// getters instead.
///
/// Owns the cross-source per-nid state (full extents, pending deletion,
/// the animating and exiting union mirrors), the broad animation
/// generation counter (the bulk-specific one lives on [BulkAnimator]),
/// the animating-keys cache, and the animation-listener channel. The five
/// sub-coordinators are held by composition, not inheritance.
///
/// Implements [AnimationReader] so [RenderSliverTree] can hold an abstract
/// reference instead of the concrete coordinator (or the controller).
///
/// Status-change handlers and the standalone tick body stay on
/// `TreeController`: they cross structure, order and structural
/// notification concerns, and are wired in here as callbacks.
library;

import 'dart:async' show scheduleMicrotask;
import 'dart:typed_data';
import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart' show AnimationStatus, Curve;
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/scheduler.dart'
    show SchedulerBinding, SchedulerPhase, TickerProvider;

import '_bulk_animator.dart';
import '_node_id_registry.dart';
import '_operation_group_registry.dart';
import '_reorder_preview_engine.dart';
import '_slide_animation_engine.dart';
import '_standalone_animator.dart';
import 'types.dart';

/// [AnimationState.targetExtent] value meaning "target not known yet",
/// set when a row starts animating before it has ever been measured.
/// Extent computations then scale the full extent by curved progress
/// instead of interpolating toward a fixed target.
const double _kUnknownExtent = -1.0;

/// Sentinel in [_fullExtentByNid] meaning "never measured". Shares the
/// -1.0 value with [_kUnknownExtent] but is a distinct concept: a missing
/// measurement rather than a missing animation target.
const double _kUnmeasuredExtent = -1.0;

/// Narrow read interface that the render layer depends on instead of
/// [TreeController]. Allows render-layer tests to stub animation reads
/// without standing up a full controller.
abstract class AnimationReader<TKey> {
  // Per-nid extent / animation status reads (per-row layout hot path).
  double getCurrentExtentNid(int nid);
  double? fullExtentOfNid(int nid);
  bool isAnimatingNid(int nid);
  bool isExitingNid(int nid);

  /// Union of the three layout-driving sources: standalone, operation
  /// groups, bulk. Read by paint scheduling, eviction deferral and the
  /// sticky band's entering-extent check. Deliberately EXCLUDES slide and
  /// preview, which are paint-only.
  bool get hasActiveAnimations;

  // Slide engine reads (paint hot path).
  bool get hasActiveSlides;
  bool get hasActiveXSlides;
  double getSlideDeltaNid(int nid);
  double getSlideDeltaXNid(int nid);

  /// Bulk-state snapshot. Holds references to the live member sets rather
  /// than copying them, and returns a shared const value when no bulk
  /// group runs, so a per-frame read costs at most the snapshot record.
  BulkAnimationData<TKey> bulkAnimationData();

  // Generation counters for cache validation in render-side prefix sums.
  int get animationGeneration;
  int get bulkAnimationGeneration;
}

class AnimationCoordinator<TKey> implements AnimationReader<TKey> {
  AnimationCoordinator({
    required TickerProvider vsync,
    required NodeIdRegistry<TKey> nids,
    required Duration Function() enterExitDurationGetter,
    required Curve Function() enterExitCurveGetter,
    required Duration Function() expandCollapseDurationGetter,
    required void Function(TKey opKey, AnimationStatus status)
    onOperationGroupStatus,
    required void Function(AnimationStatus status) onBulkAnimationStatus,
    required void Function(Iterable<TKey> completedKeys)
    onStandaloneTickComplete,
    required double defaultExtent,
  }) : _vsync = vsync,
       _nids = nids,
       _enterExitDurationGetter = enterExitDurationGetter,
       _enterExitCurveGetter = enterExitCurveGetter,
       _expandCollapseDurationGetter = expandCollapseDurationGetter,
       _onOperationGroupStatus = onOperationGroupStatus,
       _onBulkAnimationStatus = onBulkAnimationStatus,
       _onStandaloneTickComplete = onStandaloneTickComplete,
       _defaultExtent = defaultExtent;

  final TickerProvider _vsync;
  final NodeIdRegistry<TKey> _nids;

  /// Enter/exit (standalone) timing: the style's `effectiveEnterExit`.
  final Duration Function() _enterExitDurationGetter;
  final Curve Function() _enterExitCurveGetter;

  /// Expand/collapse timing: the style's `expandCollapse`. Feeds the
  /// per-operation group registry's controller durations.
  final Duration Function() _expandCollapseDurationGetter;
  final void Function(TKey opKey, AnimationStatus status)
  _onOperationGroupStatus;
  final void Function(AnimationStatus status) _onBulkAnimationStatus;
  final void Function(Iterable<TKey> completedKeys) _onStandaloneTickComplete;

  /// Fallback extent for unmeasured rows, injected from
  /// `TreeController.defaultExtent`: layering forbids importing the
  /// controller, and a mirrored constant would drift.
  final double _defaultExtent;

  // ──────────────────────────────────────────────────────────────────────
  // Sub-coordinators (composition)
  // ──────────────────────────────────────────────────────────────────────

  late final StandaloneAnimator<TKey> standalone = StandaloneAnimator<TKey>(
    vsync: _vsync,
    nids: _nids,
    enterExitCurveGetter: _enterExitCurveGetter,
    enterExitDurationGetter: _enterExitDurationGetter,
    defaultExtent: _defaultExtent,
    fullExtentGetter: (nid) {
      if (nid < 0 || nid >= _fullExtentByNid.length) return null;
      final ext = _fullExtentByNid[nid];
      return ext < 0 ? null : ext;
    },
    onTick: (completedKeys) {
      // Forwards to the controller's finalize handler AND fires the
      // listener channel; the animator itself knows about neither.
      _onStandaloneTickComplete(completedKeys);
      notifyListeners();
    },
  );

  late final OperationGroupRegistry<TKey> opGroups =
      OperationGroupRegistry<TKey>(
        nids: _nids,
        vsync: _vsync,
        durationGetter: _expandCollapseDurationGetter,
        onTick: notifyListeners,
        onStatusChanged: _onOperationGroupStatus,
        // A detached group is invisible to `groups`, so a union mirror
        // rebuilt during the detach window omits its members and caches
        // that omission against the current generation. Wired at the
        // construction boundary so no detach call site can forget the
        // pairing; the extra bumps are free, since bumpAnimGen only
        // increments a counter.
        onMembershipVisibilityChanged: bumpAnimGen,
      );

  late final BulkAnimator<TKey> bulk = BulkAnimator<TKey>(
    nids: _nids,
    vsync: _vsync,
    onTick: notifyListeners,
    onStatusChanged: _onBulkAnimationStatus,
    // Group disposal invalidates the generation-keyed union mirrors
    // ([ensureAnimatingKeys]). Wired at the construction boundary so no
    // disposal path can forget the pairing; the extra bumps on
    // replacement and teardown are free, since bumpBulkGen only
    // increments counters.
    onGroupDisposed: bumpBulkGen,
  );

  late final SlideAnimationEngine<TKey> slide = SlideAnimationEngine<TKey>(
    vsync: _vsync,
    nids: _nids,
    // IMMEDIATE dispatch, never coalesced. The engine's settle protocol
    // notifies BEFORE completed entries are removed, so listeners observe
    // delta == 0 while hasActiveSlides is still true and schedule a final
    // zero-delta paint; a deferred dispatch would land after that cleanup
    // and lose the frame. One ticker drives every slide, so this costs at
    // most one sweep per frame.
    onTick: notifyListenersNow,
  );

  /// Make-room preview offsets: paint-only Y offsets that are HELD until
  /// re-targeted or released, rather than decaying to zero like a slide.
  /// Composed with slide deltas in [getSlideDeltaNid], so the render
  /// layer sees one combined offset per row and needs no preview
  /// awareness. Dispatches immediately for the same settle-ordering
  /// reason as [slide].
  late final ReorderPreviewEngine preview = ReorderPreviewEngine(
    vsync: _vsync,
    onTick: notifyListenersNow,
  );

  // ──────────────────────────────────────────────────────────────────────
  // Cross-source per-nid state
  // ──────────────────────────────────────────────────────────────────────

  /// Cached "natural full extent" per nid. -1 sentinel = never measured.
  /// Read by every animation-source extent computation.
  Float64List _fullExtentByNid = Float64List(0);

  /// Pending-deletion bit per nid. 1 means the node is mid-exit and
  /// should be purged from structure on completion.
  Uint8List _isPendingDeletionByNid = Uint8List(0);

  /// Counter mirroring how many slots in [_isPendingDeletionByNid] are
  /// set. Saves an O(N) scan when callers ask "are there any
  /// pending-deletion nodes?" (a common predicate in the visible-order
  /// fast paths).
  int _pendingDeletionCount = 0;

  // ──────────────────────────────────────────────────────────────────────
  // Union mirrors (rebuilt by ensureAnimatingKeys)
  // ──────────────────────────────────────────────────────────────────────

  /// Nid-indexed mirror of `ensureAnimatingKeys()`'s result. Slot is `1`
  /// when the corresponding nid is animating in any source (standalone,
  /// operation group, bulk).
  Uint8List _isAnimatingByNid = Uint8List(0);

  /// Nid-indexed mirror of [isExiting]. Slot is `1` when the nid is
  /// exiting in any source.
  Uint8List _isExitingByNid = Uint8List(0);

  /// Nids written into [_isAnimatingByNid] by the last
  /// `ensureAnimatingKeys` rebuild. Drives the sparse clear at the start
  /// of each rebuild: zeroing only the slots actually dirtied avoids an
  /// O(nidCapacity) memset on every animation-generation bump.
  final List<int> _writtenAnimatingNids = <int>[];
  final List<int> _writtenExitingNids = <int>[];

  // ──────────────────────────────────────────────────────────────────────
  // Generation + animating-keys cache
  // ──────────────────────────────────────────────────────────────────────

  /// Monotonically increasing counter bumped on any mutation to animation
  /// membership. Serves as the O(1) cache signature for
  /// [_animatingKeysCache].
  int _animationGeneration = 0;

  /// Union of every currently-animating key across standalone, operation,
  /// and bulk groups. Rebuilt on demand when [_animationGeneration]
  /// changes via `ensureAnimatingKeys`.
  Set<TKey>? _animatingKeysCache;
  int _animatingKeysCacheGen = -1;

  /// Bumps [_animationGeneration]. Called from any path that mutates
  /// animation membership, including standalone, operation-group, and
  /// bulk-group changes.
  void bumpAnimGen() {
    _animationGeneration++;
  }

  /// Bumps both [_animationGeneration] and the bulk generation. Bulk
  /// progress invalidates broad animation-keyed caches too, so callers
  /// never need to bump the two counters separately.
  void bumpBulkGen() {
    _animationGeneration++;
    bulk.bumpGeneration();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Animation listener channel
  // ──────────────────────────────────────────────────────────────────────

  final List<VoidCallback> _animationListeners = <VoidCallback>[];

  /// Reused snapshot buffer for [_dispatchListeners], avoiding a fresh
  /// defensive list copy per sweep.
  final List<VoidCallback> _dispatchScratch = <VoidCallback>[];

  /// Whether a coalesced dispatch microtask is already queued this frame.
  bool _notifyScheduled = false;

  /// Whether [_dispatchListeners] is currently iterating the scratch
  /// buffer (re-entrancy guard).
  bool _dispatching = false;

  /// Subscribes [cb] to the animation tick channel.
  void addListener(VoidCallback cb) {
    _animationListeners.add(cb);
  }

  /// Unsubscribes a callback added by [addListener].
  void removeListener(VoidCallback cb) {
    _animationListeners.remove(cb);
  }

  /// Fires the animation channel, coalesced to one dispatch per frame.
  ///
  /// With K concurrent op-group tickers plus the standalone, bulk and
  /// slide tickers, an uncoalesced channel would fire K+3 full listener
  /// sweeps per frame. Inside the transient-callbacks phase the dispatch
  /// is deferred to one microtask, which lands after every same-frame
  /// tick and still before build and layout, in the test binding as well
  /// as production. Outside that phase (structural mutators, direct
  /// controller driving) there is nothing to coalesce.
  void notifyListeners() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.transientCallbacks) {
      if (_notifyScheduled) return;
      _notifyScheduled = true;
      scheduleMicrotask(() {
        // No-op when an intervening [notifyListenersNow] already covered
        // this frame's owed dispatch.
        if (!_notifyScheduled) return;
        _notifyScheduled = false;
        _dispatchListeners();
      });
      return;
    }
    _dispatchListeners();
  }

  /// Uncoalesced dispatch for callers whose notify carries a synchronous
  /// ordering contract: the slide and preview engines, which notify
  /// before clearing completed entries. Also satisfies any dispatch owed
  /// by a pending coalesced microtask, since listeners read live state.
  void notifyListenersNow() {
    _notifyScheduled = false;
    _dispatchListeners();
  }

  void _dispatchListeners() {
    if (_dispatching) {
      // Re-entrant notify from inside a listener: fall back to a fresh
      // copy rather than clobbering the in-flight scratch iteration.
      for (final listener in List<VoidCallback>.of(_animationListeners)) {
        listener();
      }
      return;
    }
    _dispatching = true;
    try {
      // Iterate a reused snapshot so listeners that remove themselves
      // mid-fire don't mutate the iteration source, without a fresh
      // list allocation per sweep.
      _dispatchScratch
        ..clear()
        ..addAll(_animationListeners);
      for (final listener in _dispatchScratch) {
        listener();
      }
    } finally {
      _dispatchScratch.clear();
      _dispatching = false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Capacity sync
  // ──────────────────────────────────────────────────────────────────────

  /// Aggregating per-capacity grow. Calls each sub-coordinator's
  /// `resizeForCapacity` plus grows coordinator-owned per-nid arrays.
  void resizeForCapacity(int newCapacity) {
    if (newCapacity > _fullExtentByNid.length) {
      final oldLen = _fullExtentByNid.length;
      final grown = Float64List(newCapacity);
      grown.setRange(0, oldLen, _fullExtentByNid);
      grown.fillRange(oldLen, newCapacity, _kUnmeasuredExtent);
      _fullExtentByNid = grown;
    }
    if (newCapacity > _isPendingDeletionByNid.length) {
      final grown = Uint8List(newCapacity);
      grown.setRange(
        0,
        _isPendingDeletionByNid.length,
        _isPendingDeletionByNid,
      );
      _isPendingDeletionByNid = grown;
    }
    if (newCapacity > _isAnimatingByNid.length) {
      final grown = Uint8List(newCapacity);
      grown.setRange(0, _isAnimatingByNid.length, _isAnimatingByNid);
      _isAnimatingByNid = grown;
    }
    if (newCapacity > _isExitingByNid.length) {
      final grown = Uint8List(newCapacity);
      grown.setRange(0, _isExitingByNid.length, _isExitingByNid);
      _isExitingByNid = grown;
    }
    standalone.resizeForCapacity(newCapacity);
    opGroups.resizeForCapacity(newCapacity);
    bulk.resizeForCapacity(newCapacity);
    slide.resizeForCapacity(newCapacity);
  }

  /// Aggregating per-nid clear: forwards to every sub-coordinator and
  /// resets coordinator-owned per-nid state. The union mirrors are left
  /// alone deliberately, because the next [ensureAnimatingKeys] rebuild
  /// clears them through the sparse-tracking lists.
  ///
  /// **Generation invariant:** this does NOT bump `_animationGeneration`,
  /// so the caller must guarantee a bump lands before any
  /// generation-keyed cache is read again. Animation finalization already
  /// bumps before it clears; the remaining callers are nid lifecycle
  /// paths, which run where no cache-gated reader can observe the gap.
  void clearForNid(int nid) {
    standalone.clearForNid(nid);
    opGroups.clearForNid(nid);
    bulk.clearForNid(nid);
    slide.clearForNid(nid);
    preview.clearForNid(nid);
    if (nid >= 0 &&
        nid < _isPendingDeletionByNid.length &&
        _isPendingDeletionByNid[nid] != 0) {
      _isPendingDeletionByNid[nid] = 0;
      _pendingDeletionCount--;
    }
    if (nid >= 0 && nid < _fullExtentByNid.length) {
      _fullExtentByNid[nid] = _kUnmeasuredExtent;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // Full extent table (shared across sources)
  // ──────────────────────────────────────────────────────────────────────

  /// Measured full extent for [key], or null when the row has never been
  /// measured or the key is unknown.
  double? fullExtentOf(TKey key) {
    final nid = _nids[key];
    if (nid == null) return null;
    final ext = _fullExtentByNid[nid];
    return ext < 0 ? null : ext;
  }

  /// Nid-keyed equivalent of [fullExtentOf]: a direct dense-array read
  /// with the unmeasured sentinel folded to null. The store is already
  /// nid-indexed, so the per-frame O(N) readers must not pay a nid to key
  /// to hash round-trip per row. Caller must guarantee [nid] is live and
  /// within range.
  @override
  double? fullExtentOfNid(int nid) {
    final ext = _fullExtentByNid[nid];
    return ext < 0 ? null : ext;
  }

  /// Records a freshly measured full extent for [key] and repairs any
  /// animation that started before the row had a size: a member still
  /// carrying [_kUnknownExtent] has its target resolved to [extent], and
  /// an op-group member whose target was not captured re-targets onto the
  /// new measurement. Returns the previous extent (null if unmeasured) so
  /// callers can invalidate downstream caches when it changed.
  double? setFullExtent(TKey key, double extent) {
    final oldExtent = fullExtentOf(key);

    // Check operation group member: resolve unknown extents
    final groupKey = opGroups.groupKeyOf(key);
    if (groupKey != null) {
      final group = opGroups.groupAt(groupKey);
      if (group != null) {
        final member = group.members[key];
        if (member != null) {
          if (member.targetExtent == _kUnknownExtent) {
            final status = group.controller.status;
            if (status == AnimationStatus.forward ||
                status == AnimationStatus.completed) {
              member.targetExtent = extent;
            }
          } else if (oldExtent != extent && !member.targetIsCaptured) {
            member.targetExtent = extent;
          }
        }
      }
      _setFullExtentRaw(key, extent);
      return oldExtent;
    }

    if (oldExtent == extent) {
      // Still resolve unknown standalone targets even when extent matches.
      final animation = standalone.at(key);
      if (animation != null && animation.targetExtent == _kUnknownExtent) {
        if (animation.type == AnimationType.entering) {
          animation.targetExtent = extent;
          animation.updateExtent(_enterExitCurveGetter());
        }
      }
      return oldExtent;
    }
    _setFullExtentRaw(key, extent);

    // Update standalone animation if mid-flight.
    final animation = standalone.at(key);
    if (animation != null && animation.targetExtent == _kUnknownExtent) {
      if (animation.type == AnimationType.entering) {
        animation.targetExtent = extent;
        animation.updateExtent(_enterExitCurveGetter());
      }
    } else if (animation != null) {
      if (animation.type == AnimationType.entering) {
        animation.targetExtent = extent;
        animation.updateExtent(_enterExitCurveGetter());
      }
      // Exiting: leave startExtent as historical (extent at exit start).
    }
    return oldExtent;
  }

  /// Direct slot write. Returns the previous value (null if previously
  /// unmeasured).
  double? _setFullExtentRaw(TKey key, double extent) {
    final nid = _nids[key];
    if (nid == null) return null;
    final prev = _fullExtentByNid[nid];
    _fullExtentByNid[nid] = extent;
    return prev < 0 ? null : prev;
  }

  /// Clears the cached full extent for [key]. Returns the previous value
  /// (null if previously unmeasured). Caller uses the return value to
  /// decide whether to invalidate downstream caches.
  double? clearFullExtent(TKey key) {
    final nid = _nids[key];
    if (nid == null) return null;
    final prev = _fullExtentByNid[nid];
    if (prev < 0) return null;
    _fullExtentByNid[nid] = _kUnmeasuredExtent;
    return prev;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Pending deletion
  // ──────────────────────────────────────────────────────────────────────

  /// Whether [key] is marked for purge once its exit animation finishes.
  bool isPendingDeletion(TKey key) {
    final nid = _nids[key];
    if (nid == null) return false;
    return nid < _isPendingDeletionByNid.length &&
        _isPendingDeletionByNid[nid] != 0;
  }

  /// Marks [key] for purge on exit completion. Idempotent: the counter
  /// tracks distinct set slots, not calls.
  void markPendingDeletion(TKey key) {
    final nid = _nids[key];
    if (nid == null) return;
    if (_isPendingDeletionByNid[nid] == 0) {
      _isPendingDeletionByNid[nid] = 1;
      _pendingDeletionCount++;
    }
  }

  /// Unmarks [key], for a re-add that cancels a pending purge.
  void clearPendingDeletion(TKey key) {
    final nid = _nids[key];
    if (nid == null) return;
    if (nid < _isPendingDeletionByNid.length &&
        _isPendingDeletionByNid[nid] != 0) {
      _isPendingDeletionByNid[nid] = 0;
      _pendingDeletionCount--;
    }
  }

  /// Number of nids currently marked pending deletion.
  int get pendingDeletionCount => _pendingDeletionCount;

  // ──────────────────────────────────────────────────────────────────────
  // Dispatch: the "which source owns this key?" methods
  // ──────────────────────────────────────────────────────────────────────

  /// Captures a node's current animated extent from whichever source it's
  /// in, removes it from that source, and returns the extent (or null if
  /// not animating). Used in cross-source-move paths to seed a follow-on
  /// animation with the current visible extent.
  double? captureAndRemoveFromGroups(TKey key) {
    // 1. Op group
    final opGroupKey = opGroups.groupKeyOf(key);
    if (opGroupKey != null) {
      final group = opGroups.groupAt(opGroupKey);
      if (group != null) {
        final member = group.members[key];
        if (member != null) {
          final full = fullExtentOf(key) ?? _defaultExtent;
          final extent = member.computeExtent(group.curvedValue, full);
          group.members.remove(key);
          group.pendingRemoval.remove(key);
          opGroups.clearMembership(key);
          bumpAnimGen();
          opGroups.disposeIfEmpty(opGroupKey);
          return extent;
        }
      }
      opGroups.clearMembership(key);
    }

    // 2. Bulk
    if (bulk.isMember(key)) {
      final full = fullExtentOf(key) ?? _defaultExtent;
      final extent = full * (bulk.group?.value ?? 0.0);
      bulk.removeMember(key);
      bulk.removePending(key);
      bumpBulkGen();
      return extent;
    }

    // 3. Standalone
    final state = standalone.clearAt(key);
    if (state != null) {
      bumpAnimGen();
      return standalone.visibleExtent(key, state);
    }

    return null;
  }

  /// Walks every animation source [key] might belong to, clears
  /// membership, returns the standalone state if any was cleared. Does
  /// NOT compute a visible extent, so it is cheaper than
  /// [captureAndRemoveFromGroups] when callers don't need it.
  AnimationState? removeFromAllSources(TKey key) {
    final state = standalone.clearAt(key);
    if (state != null) {
      bumpAnimGen();
    }
    final opGroupKey = opGroups.clearMembership(key);
    if (opGroupKey != null) {
      final group = opGroups.groupAt(opGroupKey);
      if (group != null) {
        final removedMember = group.members.remove(key) != null;
        final removedPending = group.pendingRemoval.remove(key);
        if (removedMember || removedPending) {
          bumpAnimGen();
        }
        opGroups.disposeIfEmpty(opGroupKey);
      }
    }
    final removedBulkMember = bulk.removeMember(key);
    final removedBulkPending = bulk.removePending(key);
    if (removedBulkMember || removedBulkPending) {
      bumpBulkGen();
    }
    return state;
  }

  // Subtree animation cancellation deliberately does NOT live here.
  // `_cancelAnimationStateForSubtree` on the controller stays the single
  // implementation: it needs a `preserveEntering` branch that a
  // coordinator-level copy would not naturally carry.

  // ──────────────────────────────────────────────────────────────────────
  // Per-key animation queries (forwarded by TreeController)
  // ──────────────────────────────────────────────────────────────────────

  /// Whether [key] is animating in any layout-driving source. Gated on
  /// the O(1) [hasActiveAnimations] check so an idle tree never builds
  /// the union set.
  bool isAnimating(TKey key) {
    if (!hasActiveAnimations) return false;
    return ensureAnimatingKeys().contains(key);
  }

  /// Whether [key] is animating OUT: pending removal in the bulk group
  /// or in its operation group, or a standalone exit. Probes each source
  /// directly, so it stays correct without forcing a union rebuild.
  bool isExiting(TKey key) {
    // Bulk pending removal
    if (bulk.group?.pendingRemoval.contains(key) == true) return true;
    // Op-group pending removal
    final groupKey = opGroups.groupKeyOf(key);
    if (groupKey != null) {
      final group = opGroups.groupAt(groupKey);
      if (group != null && group.pendingRemoval.contains(key)) return true;
    }
    // Standalone exit
    final animation = standalone.at(key);
    return animation != null && animation.type == AnimationType.exiting;
  }

  /// Animation state for [key], or null when it is not animating. Group
  /// members carry no per-node state, so an expanding operation-group or
  /// bulk member reports a synthetic entering state, and a member already
  /// pending removal reports null.
  AnimationState? getAnimationState(TKey key) {
    // 1. Standalone
    final standaloneState = standalone.at(key);
    if (standaloneState != null) return standaloneState;

    // 2. Op group
    final groupKey = opGroups.groupKeyOf(key);
    if (groupKey != null) {
      final group = opGroups.groupAt(groupKey);
      if (group != null && !group.pendingRemoval.contains(key)) {
        final status = group.controller.status;
        if (status == AnimationStatus.forward ||
            status == AnimationStatus.completed) {
          return _buildSyntheticEnteringState();
        }
      }
      return null;
    }

    // 3. Bulk
    final bulkGroup = bulk.group;
    if (bulkGroup != null &&
        bulkGroup.members.contains(key) &&
        !bulkGroup.pendingRemoval.contains(key)) {
      final status = bulkGroup.controller.status;
      if (status == AnimationStatus.forward ||
          status == AnimationStatus.completed) {
        return _buildSyntheticEnteringState();
      }
    }
    return null;
  }

  /// Current animated extent for [key], falling back to the default
  /// extent when the row has never been measured.
  double getCurrentExtent(TKey key) {
    return getAnimatedExtent(key, fullExtentOf(key) ?? _defaultExtent);
  }

  /// Current extent for [key] against a caller-supplied [fullExtent].
  /// Checks the sources in fixed precedence order (bulk, operation group,
  /// standalone) and returns [fullExtent] when none owns the key.
  double getAnimatedExtent(TKey key, double fullExtent) {
    // 1. Bulk. `isMember` covers members AND pendingRemoval, matching the
    // nid-keyed mirror `getCurrentExtentNid` consults. A members-only
    // check here would let the scroll orchestrator compute offsets that
    // disagree with rendered layout whenever the two sets diverge.
    if (bulk.isMember(key)) {
      return fullExtent * (bulk.group?.value ?? 0.0);
    }
    // 2. Op group
    final groupKey = opGroups.groupKeyOf(key);
    if (groupKey != null) {
      final group = opGroups.groupAt(groupKey);
      if (group != null) {
        final member = group.members[key];
        if (member != null) {
          return member.computeExtent(group.curvedValue, fullExtent);
        }
      }
    }
    // 3. Standalone
    final animation = standalone.at(key);
    if (animation == null) return fullExtent;
    final t = _enterExitCurveGetter().transform(
      animation.progress.clamp(0.0, 1.0),
    );
    if (animation.targetExtent == _kUnknownExtent) {
      return animation.type == AnimationType.entering
          ? fullExtent * t
          : fullExtent * (1.0 - t);
    }
    return lerpDouble(animation.startExtent, animation.targetExtent, t)!;
  }

  /// Builds a fresh synthetic entering state for [getAnimationState] to
  /// return for op/bulk members that are expanding. Fresh per call so
  /// external mutation can't leak.
  static AnimationState _buildSyntheticEnteringState() {
    return AnimationState(
      type: AnimationType.entering,
      startExtent: 0,
      targetExtent: 0,
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Union mirrors maintenance
  // ──────────────────────────────────────────────────────────────────────

  /// Returns the union of every currently-animating key across all three
  /// sources. Rebuilt on demand when [_animationGeneration] changes; also
  /// refreshes the nid-keyed mirrors using sparse-tracking cleanup.
  Set<TKey> ensureAnimatingKeys() {
    final cached = _animatingKeysCache;
    if (cached != null && _animationGeneration == _animatingKeysCacheGen) {
      return cached;
    }
    // Sparse clear of slots written by the previous rebuild.
    for (final nid in _writtenAnimatingNids) {
      if (nid < _isAnimatingByNid.length) {
        _isAnimatingByNid[nid] = 0;
      }
    }
    _writtenAnimatingNids.clear();
    for (final nid in _writtenExitingNids) {
      if (nid < _isExitingByNid.length) {
        _isExitingByNid[nid] = 0;
      }
    }
    _writtenExitingNids.clear();

    final set = <TKey>{};

    // 1. Standalone
    if (standalone.hasAny) {
      for (final nid in standalone.activeNids) {
        set.add(_nids.keyOfUnchecked(nid));
        if (_isAnimatingByNid[nid] == 0) {
          _isAnimatingByNid[nid] = 1;
          _writtenAnimatingNids.add(nid);
        }
        final state = standalone.slotAtNid(nid);
        if (state != null &&
            state.type == AnimationType.exiting &&
            _isExitingByNid[nid] == 0) {
          _isExitingByNid[nid] = 1;
          _writtenExitingNids.add(nid);
        }
      }
    }

    // 2. Op groups
    if (opGroups.isNotEmpty) {
      for (final entry in opGroups.groups) {
        final group = entry.value;
        for (final key in group.members.keys) {
          set.add(key);
          final nid = _nids[key];
          if (nid == null) continue;
          if (_isAnimatingByNid[nid] == 0) {
            _isAnimatingByNid[nid] = 1;
            _writtenAnimatingNids.add(nid);
          }
          if (group.pendingRemoval.contains(key) && _isExitingByNid[nid] == 0) {
            _isExitingByNid[nid] = 1;
            _writtenExitingNids.add(nid);
          }
        }
      }
    }

    // 3. Bulk
    final bulkGroup = bulk.group;
    if (bulkGroup != null) {
      for (final key in bulkGroup.members) {
        set.add(key);
        final nid = _nids[key];
        if (nid == null) continue;
        if (_isAnimatingByNid[nid] == 0) {
          _isAnimatingByNid[nid] = 1;
          _writtenAnimatingNids.add(nid);
        }
      }
      for (final key in bulkGroup.pendingRemoval) {
        final nid = _nids[key];
        if (nid == null) continue;
        if (_isExitingByNid[nid] == 0) {
          _isExitingByNid[nid] = 1;
          _writtenExitingNids.add(nid);
        }
      }
    }

    _animatingKeysCache = set;
    _animatingKeysCacheGen = _animationGeneration;
    return set;
  }

  // ──────────────────────────────────────────────────────────────────────
  // AnimationReader implementation (render-layer hot-path reads)
  // ──────────────────────────────────────────────────────────────────────

  /// Nid-keyed [getAnimatedExtent] for the per-row layout hot path. Same
  /// precedence order, but each probe is a dense-array read where it can
  /// be, and the key is resolved at most once per call.
  @override
  double getCurrentExtentNid(int nid) {
    final fullRaw = _fullExtentByNid[nid];
    final full = fullRaw < 0 ? _defaultExtent : fullRaw;
    // 1. Bulk: the nid mirror is the fast path.
    if (bulk.isMemberNid(nid) && bulk.group != null) {
      return full * bulk.group!.value;
    }
    // 2. Op group. Guard on `isNotEmpty` so the common no-op-group frame
    // skips the `keyOfUnchecked` + `groupKeyOf` probe (including a TKey
    // hash) entirely. `key` is resolved once and reused for both the
    // membership probe and the member lookup.
    if (opGroups.isNotEmpty) {
      final key = _nids.keyOfUnchecked(nid);
      final opKey = opGroups.groupKeyOf(key);
      if (opKey != null) {
        final group = opGroups.groupAt(opKey);
        if (group != null) {
          final member = group.members[key];
          if (member != null) {
            return member.computeExtent(group.curvedValue, full);
          }
        }
      }
    }
    // 3. Standalone
    final animation = standalone.slotAtNid(nid);
    if (animation == null) return full;
    final t = _enterExitCurveGetter().transform(
      animation.progress.clamp(0.0, 1.0),
    );
    if (animation.targetExtent == _kUnknownExtent) {
      return animation.type == AnimationType.entering
          ? full * t
          : full * (1.0 - t);
    }
    return lerpDouble(animation.startExtent, animation.targetExtent, t)!;
  }

  /// Nid-keyed [isAnimating], served from the union mirror. Refreshes the
  /// mirror first so a stale generation cannot serve a stale bit.
  @override
  bool isAnimatingNid(int nid) {
    ensureAnimatingKeys();
    return nid >= 0 &&
        nid < _isAnimatingByNid.length &&
        _isAnimatingByNid[nid] != 0;
  }

  /// Nid-keyed [isExiting], served from the union mirror rather than by
  /// probing each source.
  @override
  bool isExitingNid(int nid) {
    ensureAnimatingKeys();
    return nid >= 0 &&
        nid < _isExitingByNid.length &&
        _isExitingByNid[nid] != 0;
  }

  @override
  bool get hasActiveAnimations =>
      standalone.hasAny || opGroups.isNotEmpty || !bulk.isEmpty;

  // Slide reads compose the FLIP engine with the make-room preview:
  // the render layer sees one combined paint offset per row and needs no
  // preview awareness. The hasActive guard keeps the non-drag hot path at
  // one boolean check. X is FLIP-only (previews are Y offsets).
  @override
  bool get hasActiveSlides => slide.hasActive || preview.hasActive;

  @override
  bool get hasActiveXSlides => slide.hasActiveX;

  @override
  double getSlideDeltaNid(int nid) {
    final base = slide.deltaForNid(nid);
    if (!preview.hasActive) {
      return base;
    }
    return base + preview.deltaForNid(nid);
  }

  @override
  double getSlideDeltaXNid(int nid) => slide.deltaXForNid(nid);

  @override
  BulkAnimationData<TKey> bulkAnimationData() => bulk.snapshot();

  @override
  int get animationGeneration => _animationGeneration;

  @override
  int get bulkAnimationGeneration => bulk.generation;

  // ──────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────────

  /// Aggregating clear. Calls each sub-coordinator's `clear()` plus
  /// resets coordinator-owned state.
  void clear() {
    standalone.clear();
    opGroups.clear();
    bulk.clear();
    slide.clearAll();
    preview.clearAll();
    _fullExtentByNid = Float64List(0);
    _isPendingDeletionByNid = Uint8List(0);
    _isAnimatingByNid = Uint8List(0);
    _isExitingByNid = Uint8List(0);
    _writtenAnimatingNids.clear();
    _writtenExitingNids.clear();
    _pendingDeletionCount = 0;
    _animatingKeysCache = null;
    _animationGeneration++;
  }

  /// Terminal teardown: disposes every sub-coordinator and drops the
  /// listener list, which [clear] deliberately keeps.
  void dispose() {
    standalone.dispose();
    opGroups.dispose();
    bulk.dispose();
    slide.dispose();
    preview.dispose();
    _fullExtentByNid = Float64List(0);
    _isPendingDeletionByNid = Uint8List(0);
    _isAnimatingByNid = Uint8List(0);
    _isExitingByNid = Uint8List(0);
    _writtenAnimatingNids.clear();
    _writtenExitingNids.clear();
    _animationListeners.clear();
    _pendingDeletionCount = 0;
    _animatingKeysCache = null;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Debug
  // ──────────────────────────────────────────────────────────────────────

  /// Aggregates each sub-coordinator's `debugAssertConsistent()` plus a
  /// coordinator-only pending-deletion-counter check.
  void debugAssertConsistent() {
    assert(() {
      standalone.debugAssertConsistent();
      opGroups.debugAssertConsistent();
      bulk.debugAssertConsistent();
      // Coordinator-only: pending-deletion counter.
      int pdCount = 0;
      for (int nid = 0; nid < _isPendingDeletionByNid.length; nid++) {
        if (_isPendingDeletionByNid[nid] != 0) {
          if (_nids.keyOf(nid) == null) {
            throw StateError(
              "AnimationCoordinator._isPendingDeletionByNid[$nid] = 1 "
              "for freed slot",
            );
          }
          pdCount++;
        }
      }
      if (pdCount != _pendingDeletionCount) {
        throw StateError(
          "AnimationCoordinator._pendingDeletionCount = $_pendingDeletionCount, "
          "but counted $pdCount slots set",
        );
      }
      return true;
    }());
  }
}
