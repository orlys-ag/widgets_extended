/// Internal: facade over the four animation sources (standalone,
/// per-operation groups, bulk, slide), plus the cross-source state and
/// dispatch logic that span them.
///
/// Owns:
/// - Cross-source per-nid state (`_fullExtentByNid`, `_isPendingDeletionByNid`,
///   the union mirrors `_isAnimatingByNid` / `_isExitingByNid`).
/// - The animation generation counter `_animationGeneration` (the broad
///   counter; the bulk-specific counter lives on [BulkAnimator]).
/// - The animating-keys cache + sparse-tracking lists used by
///   `_ensureAnimatingKeys`.
/// - The animation-listener channel (`addListener` / `removeListener` /
///   `notifyListeners`).
/// - The four sub-coordinators (composition, not inheritance).
///
/// Implements [AnimationReader] so [RenderSliverTree] can hold an abstract
/// reference instead of the concrete coordinator (or the controller).
///
/// Status-change handlers and the standalone tick body STAY on
/// `TreeController` — they cross structure / order / structural-notification
/// concerns. The coordinator wires them as callbacks (see constructor).
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
import '_slide_animation_engine.dart';
import '_standalone_animator.dart';
import 'types.dart';

/// Marker for unknown target extent. Mirrors `_unknownExtent` in the
/// original part file.
const double _kUnknownExtent = -1.0;

/// Sentinel in [_fullExtentByNid] meaning "never measured."
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

  /// 3-source union getter — paint scheduling, sticky throttle, eviction
  /// deferral all read this. **Excludes slide** (slide is paint-only).
  bool get hasActiveAnimations;

  // Slide engine reads (paint hot path).
  bool get hasActiveSlides;
  bool get hasActiveXSlides;
  double getSlideDeltaNid(int nid);
  double getSlideDeltaXNid(int nid);

  /// Bulk-state snapshot (allocation-free per the existing const sentinel).
  BulkAnimationData<TKey> bulkAnimationData();

  // Generation counters for cache validation in render-side prefix sums.
  int get animationGeneration;
  int get bulkAnimationGeneration;
}

class AnimationCoordinator<TKey> implements AnimationReader<TKey> {
  AnimationCoordinator({
    required TickerProvider vsync,
    required NodeIdRegistry<TKey> nids,
    required Duration Function() animationDurationGetter,
    required Curve Function() animationCurveGetter,
    required void Function(TKey opKey, AnimationStatus status)
        onOperationGroupStatus,
    required void Function(AnimationStatus status) onBulkAnimationStatus,
    required void Function(Iterable<TKey> completedKeys)
        onStandaloneTickComplete,
    required double defaultExtent,
  }) : _vsync = vsync,
       _nids = nids,
       _animationDurationGetter = animationDurationGetter,
       _animationCurveGetter = animationCurveGetter,
       _onOperationGroupStatus = onOperationGroupStatus,
       _onBulkAnimationStatus = onBulkAnimationStatus,
       _onStandaloneTickComplete = onStandaloneTickComplete,
       _defaultExtent = defaultExtent;

  final TickerProvider _vsync;
  final NodeIdRegistry<TKey> _nids;
  final Duration Function() _animationDurationGetter;
  final Curve Function() _animationCurveGetter;
  final void Function(TKey opKey, AnimationStatus status)
      _onOperationGroupStatus;
  final void Function(AnimationStatus status) _onBulkAnimationStatus;
  final void Function(Iterable<TKey> completedKeys) _onStandaloneTickComplete;

  /// Fallback extent for unmeasured rows, injected from
  /// `TreeController.defaultExtent` (audit 6.1 — layering forbids the
  /// import, and a hard-coded mirror had already been copied three
  /// times).
  final double _defaultExtent;

  // ──────────────────────────────────────────────────────────────────────
  // Sub-coordinators (composition)
  // ──────────────────────────────────────────────────────────────────────

  late final StandaloneAnimator<TKey> standalone = StandaloneAnimator<TKey>(
    vsync: _vsync,
    nids: _nids,
    animationCurveGetter: _animationCurveGetter,
    animationDurationGetter: _animationDurationGetter,
    defaultExtent: _defaultExtent,
    fullExtentGetter: (nid) {
      if (nid < 0 || nid >= _fullExtentByNid.length) return null;
      final ext = _fullExtentByNid[nid];
      return ext < 0 ? null : ext;
    },
    onTick: (completedKeys) {
      // Wrapper closure (Gap M): forwards to the controller's
      // _finalizeAnimation handler AND fires the listener channel.
      _onStandaloneTickComplete(completedKeys);
      notifyListeners();
    },
  );

  late final OperationGroupRegistry<TKey> opGroups =
      OperationGroupRegistry<TKey>(
    nids: _nids,
    vsync: _vsync,
    durationGetter: _animationDurationGetter,
    onTick: notifyListeners,
    onStatusChanged: _onOperationGroupStatus,
  );

  late final BulkAnimator<TKey> bulk = BulkAnimator<TKey>(
    nids: _nids,
    vsync: _vsync,
    onTick: notifyListeners,
    onStatusChanged: _onBulkAnimationStatus,
  );

  late final SlideAnimationEngine<TKey> slide = SlideAnimationEngine<TKey>(
    vsync: _vsync,
    nids: _nids,
    // IMMEDIATE dispatch — never coalesced. The engine's settle protocol
    // documents that its notify fires BEFORE completed entries are
    // removed (listeners must observe delta == 0 with hasActiveSlides
    // still true so a final zero-delta paint is scheduled); a deferred
    // dispatch would land after the cleanup. The engine runs ONE ticker
    // for all slides, so this contributes at most one sweep per frame —
    // it is not part of the K-multiplier the coalescing removes.
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
  /// of each rebuild — zeroing only the slots actually dirtied avoids an
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

  /// Bumps both [_animationGeneration] and [bulk.generation]. Preserves
  /// today's `_bumpBulkGen` "bumps both" semantic.
  void bumpBulkGen() {
    _animationGeneration++;
    bulk.bumpGeneration();
  }

  // ──────────────────────────────────────────────────────────────────────
  // Animation listener channel
  // ──────────────────────────────────────────────────────────────────────

  final List<VoidCallback> _animationListeners = <VoidCallback>[];

  /// Reused snapshot buffer for [_dispatchListeners] — avoids a fresh
  /// defensive list copy per sweep (audit 5.6).
  final List<VoidCallback> _dispatchScratch = <VoidCallback>[];

  /// Whether a coalesced dispatch microtask is already queued this frame.
  bool _notifyScheduled = false;

  /// Whether [_dispatchListeners] is currently iterating the scratch
  /// buffer (re-entrancy guard).
  bool _dispatching = false;

  void addListener(VoidCallback cb) {
    _animationListeners.add(cb);
  }

  void removeListener(VoidCallback cb) {
    _animationListeners.remove(cb);
  }

  void notifyListeners() {
    // Per-frame coalescing (audit 5.6): with K concurrent op-group
    // tickers plus the standalone/bulk/slide tickers, an uncoalesced
    // channel fires K+3 full listener sweeps per frame. During the
    // transient-callbacks phase (ticker callbacks) defer to a single
    // microtask — it runs after every same-frame tick has fired and
    // before build/layout (the test binding flushes microtasks between
    // handleBeginFrame and handleDrawFrame, matching production). Outside
    // that phase (structural mutators, direct controller driving),
    // dispatch immediately.
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

  /// Uncoalesced dispatch for callers whose notify carries a documented
  /// synchronous ordering contract (currently the slide engine's settle
  /// protocol). Also satisfies any dispatch owed by a pending coalesced
  /// microtask — listeners read live state, so this covers it.
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
      // mid-fire don't mutate the iteration source — without a fresh
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
      grown.setRange(0, _isPendingDeletionByNid.length, _isPendingDeletionByNid);
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

  /// Aggregating per-nid clear. Calls each sub-coordinator's
  /// `clearForNid` plus resets coordinator-owned per-nid state. Does NOT
  /// explicitly clear the union mirrors `_isAnimatingByNid` /
  /// `_isExitingByNid` — they're rebuilt from scratch on the next
  /// `ensureAnimatingKeys()` via the sparse-tracking lists.
  ///
  /// **Generation invariant (C095):** this method does NOT bump
  /// `_animationGeneration`. Callers that read animation-gen-keyed caches
  /// (e.g. render-layer prefix-sum caches gated on `animationGeneration`)
  /// must ensure a bump happens before any such read between this call
  /// and the next mutation. The animation-finalization path
  /// (`_finalizeAnimation` in `_tree_controller_animation.dart`) already
  /// bumps the generation before invoking transitively-clearing helpers,
  /// so animation-driven cleanup is covered. The unpaired call sites are
  /// `_adoptKey` and `_releaseNid` in `tree_controller.dart`; both are
  /// lifecycle-only and run in contexts where cache-gated readers are
  /// not reachable before the next structural mutation.
  void clearForNid(int nid) {
    standalone.clearForNid(nid);
    opGroups.clearForNid(nid);
    bulk.clearForNid(nid);
    slide.clearForNid(nid);
    if (nid >= 0 && nid < _isPendingDeletionByNid.length &&
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

  double? fullExtentOf(TKey key) {
    final nid = _nids[key];
    if (nid == null) return null;
    final ext = _fullExtentByNid[nid];
    return ext < 0 ? null : ext;
  }

  /// Nid-keyed equivalent of [fullExtentOf] — a direct dense-array read
  /// with the unmeasured sentinel folded to null. The store is already
  /// nid-indexed, so the O(N)-per-frame hot paths (bulk cumulatives,
  /// settled-offset snapshots, scroll prefix rebuild, sticky computer,
  /// admission policy) must not pay a nid→key→hash→nid round-trip per
  /// row. Caller must guarantee [nid] is live and within range.
  double? fullExtentOfNid(int nid) {
    final ext = _fullExtentByNid[nid];
    return ext < 0 ? null : ext;
  }

  /// Coordinates across op-group members: if [key] is mid-flight in an
  /// op-group with `targetExtent == _unknownExtent`, resolves the target
  /// from [extent]; if `targetIsCaptured` is false and the value changed,
  /// updates the natural full reference. ~30 lines of cross-source logic
  /// — ported verbatim from `tree_controller.dart:1705`. Returns the
  /// previous extent value (null if previously unmeasured) so callers can
  /// invalidate downstream caches when it changed.
  double? setFullExtent(TKey key, double extent) {
    final oldExtent = fullExtentOf(key);

    // Check operation group member — resolve unknown extents
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
          animation.updateExtent(_animationCurveGetter());
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
        animation.updateExtent(_animationCurveGetter());
      }
    } else if (animation != null) {
      if (animation.type == AnimationType.entering) {
        animation.targetExtent = extent;
        animation.updateExtent(_animationCurveGetter());
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

  bool isPendingDeletion(TKey key) {
    final nid = _nids[key];
    if (nid == null) return false;
    return nid < _isPendingDeletionByNid.length &&
        _isPendingDeletionByNid[nid] != 0;
  }

  void markPendingDeletion(TKey key) {
    final nid = _nids[key];
    if (nid == null) return;
    if (_isPendingDeletionByNid[nid] == 0) {
      _isPendingDeletionByNid[nid] = 1;
      _pendingDeletionCount++;
    }
  }

  void clearPendingDeletion(TKey key) {
    final nid = _nids[key];
    if (nid == null) return;
    if (nid < _isPendingDeletionByNid.length &&
        _isPendingDeletionByNid[nid] != 0) {
      _isPendingDeletionByNid[nid] = 0;
      _pendingDeletionCount--;
    }
  }

  int get pendingDeletionCount => _pendingDeletionCount;

  // ──────────────────────────────────────────────────────────────────────
  // Dispatch — the "which source owns this key?" methods
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
  /// NOT compute a visible extent — cheaper than
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

  // Audit 6.1: the coordinator's `cancelAnimationStateForSubtree` copy
  // was deleted. It had ZERO callers yet looked authoritative — and it
  // LACKED the `preserveEntering` branch that the live implementation
  // (`_cancelAnimationStateForSubtree` in `_tree_controller_animation.dart`,
  // guarded by `move_preserves_entering_test.dart`) carries; "finishing
  // the refactor" onto this copy would have silently regressed tested
  // behavior. The extension version is the single spec.

  // ──────────────────────────────────────────────────────────────────────
  // Per-key animation queries (forwarded by TreeController)
  // ──────────────────────────────────────────────────────────────────────

  bool isAnimating(TKey key) {
    if (!hasActiveAnimations) return false;
    return ensureAnimatingKeys().contains(key);
  }

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

  double getCurrentExtent(TKey key) {
    return getAnimatedExtent(key, fullExtentOf(key) ?? _defaultExtent);
  }

  double getAnimatedExtent(TKey key, double fullExtent) {
    // 1. Bulk — `isMember` covers members ∪ pendingRemoval, matching the
    // nid-keyed mirror `getCurrentExtentNid` consults (audit 6.5: a
    // members-only check here would let the scroll orchestrator compute
    // offsets that disagree with rendered layout if the two sets ever
    // diverged).
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
    final t = _animationCurveGetter()
        .transform(animation.progress.clamp(0.0, 1.0));
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
        if (state != null && state.type == AnimationType.exiting &&
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

  @override
  double getCurrentExtentNid(int nid) {
    final fullRaw = _fullExtentByNid[nid];
    final full = fullRaw < 0 ? _defaultExtent : fullRaw;
    // 1. Bulk — nid mirror is the fast path.
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
    final t = _animationCurveGetter()
        .transform(animation.progress.clamp(0.0, 1.0));
    if (animation.targetExtent == _kUnknownExtent) {
      return animation.type == AnimationType.entering
          ? full * t
          : full * (1.0 - t);
    }
    return lerpDouble(animation.startExtent, animation.targetExtent, t)!;
  }

  @override
  bool isAnimatingNid(int nid) {
    ensureAnimatingKeys();
    return nid >= 0 && nid < _isAnimatingByNid.length &&
        _isAnimatingByNid[nid] != 0;
  }

  @override
  bool isExitingNid(int nid) {
    ensureAnimatingKeys();
    return nid >= 0 && nid < _isExitingByNid.length &&
        _isExitingByNid[nid] != 0;
  }

  @override
  bool get hasActiveAnimations =>
      standalone.hasAny || opGroups.isNotEmpty || !bulk.isEmpty;

  @override
  bool get hasActiveSlides => slide.hasActive;

  @override
  bool get hasActiveXSlides => slide.hasActiveX;

  @override
  double getSlideDeltaNid(int nid) => slide.deltaForNid(nid);

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

  /// Same as [clear] plus disposes the slide engine (which is the only
  /// sub-coordinator with a meaningful `dispose()` distinction — the
  /// others' `dispose()` is currently equivalent to `clear()`).
  void dispose() {
    standalone.dispose();
    opGroups.dispose();
    bulk.dispose();
    slide.dispose();
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
