/// Controller that manages tree state, visibility, and animations.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '_animation_coordinator.dart';
import '_node_id_registry.dart';
import '_node_store.dart';
import '_reorder_preview_engine.dart';
import '_scroll_orchestrator.dart';
import '_slide_animation_engine.dart';
import '_visible_order_buffer.dart';
import 'animation_style.dart';
import 'types.dart';

export '_animation_coordinator.dart' show AnimationReader;

part '_tree_controller_animation.dart';
part '_tree_controller_helpers.dart';

/// Callback registered by every [RenderSliverTree] attached to a
/// [TreeController].
///
/// Invoked from [TreeController.moveNode] (and any future animated mutation)
/// to ask the render object to snapshot current painted offsets BEFORE the
/// mutation so the next `performLayout` can install a FLIP slide from
/// baseline → post-mutation.
///
/// Returning `true` means "the host is participating in this slide cycle" —
/// either it staged a fresh baseline now, or a prior call this frame already
/// staged one and the host is honoring the first-wins policy. Returning
/// `false` indicates the host cannot participate at all (not yet laid out,
/// detached, etc.).
///
/// **Internal contract** — this typedef is part of the sliver-render-object
/// staging protocol. External callers should not implement or depend on it.
typedef TreeRenderHost =
    bool Function({required Duration duration, required Curve curve});

/// Controller for a [SliverTree] widget.
///
/// Manages:
/// - Tree structure (nodes, parent/child relationships, depth)
/// - Visibility (which nodes are in the flattened visible list)
/// - Expansion state (which nodes are expanded)
/// - Animation state (which nodes are animating and their progress)
///
/// Uses an ECS-style architecture where components are stored separately
/// for efficient iteration and memory usage.
///
/// The controller provides two notification channels:
/// - [addListener] / [removeListener] from [ChangeNotifier]: for structure changes
/// - [addAnimationListener] / [removeAnimationListener]: for animation ticks
///
/// This separation allows the render object to only do full relayout when
/// structure changes, and just update geometry/repaint during animations.
class TreeController<TKey, TData> extends ChangeNotifier {
  /// Creates a tree controller.
  ///
  /// Requires a [TickerProvider] to drive animations. Typically this is
  /// the State object of the widget that creates the controller, using
  /// [TickerProviderStateMixin] or [SingleTickerProviderStateMixin].
  TreeController({
    required TickerProvider vsync,
    TreeAnimationStyle animationStyle = const TreeAnimationStyle(),
    double indentWidth = 0.0,
    this.comparator,
  }) : assert(animationStyle.debugValidate()),
       _animationStyle = animationStyle,
       _indentWidth = indentWidth,
       _vsync = vsync;

  final TickerProvider _vsync;

  TreeAnimationStyle _animationStyle;

  /// Animation timing/easing for every family: expand/collapse,
  /// enter/exit, reorder slides, make-room preview, drop settle.
  ///
  /// Mutable at runtime. When [TreeAnimationStyle.expandCollapse]'s
  /// duration changes, the new value is written onto every in-flight
  /// [AnimationController] (operation groups and the bulk group), but a
  /// running simulation is **not** re-timed — the controller reads
  /// `duration` at the next `forward()`/`reverse()`, so in-flight groups
  /// finish at their old rate and the new duration applies from the next
  /// start. Curves apply to newly started groups only. The per-node
  /// standalone ticker re-reads [TreeAnimationStyle.effectiveEnterExit]
  /// on every tick, so enter/exit animations adjust immediately; a zero
  /// enter/exit duration makes all in-flight standalone animations
  /// complete (finalize) on the next tick.
  TreeAnimationStyle get animationStyle {
    return _animationStyle;
  }

  set animationStyle(TreeAnimationStyle value) {
    assert(value.debugValidate());
    if (value == _animationStyle) {
      return;
    }
    final oldOpDuration = _animationStyle.expandCollapse.duration;
    final oldSlideDuration = _animationStyle.reorderSlide.duration;
    _animationStyle = value;
    final newOpDuration = value.expandCollapse.duration;
    if (newOpDuration != oldOpDuration) {
      _activeBulkGroup?.controller.duration = newOpDuration;
      for (final entry in _opGroupEntries) {
        entry.value.controller.duration = newOpDuration;
      }
    }
    // Disabled-mode split: a zero family CREATES no motion (install-time
    // refusal), while DISABLING — this transition — STOPS motion. Zeroing
    // the reorderSlide family purges in-flight slides here, explicitly;
    // no other family transition purges (a live drop-settle glide already
    // survives a live dropSettle zeroing, and standalone/op-group
    // families carry their own live-read semantics).
    if (oldSlideDuration != Duration.zero &&
        value.reorderSlide.duration == Duration.zero) {
      _slide.purgeActive();
      // Rows painted mid-delta must repaint at their snapped positions.
      _notifyAnimationListeners();
    }
  }

  double _indentWidth;

  /// Horizontal indent per depth level in logical pixels.
  ///
  /// Mutable at runtime. [getIndent] reads this live, so setting a new
  /// value only needs to trigger a relayout on subscribers — fires the
  /// animation-tick channel (layout-only) rather than the structural
  /// channel so children aren't rebuilt unnecessarily.
  double get indentWidth => _indentWidth;
  set indentWidth(double value) {
    if (value == _indentWidth) {
      return;
    }
    _indentWidth = value;
    _notifyAnimationListeners();
  }

  /// Optional comparator for maintaining sorted order among siblings.
  ///
  /// When set, [insertRoot] and [insert] automatically place new nodes at the
  /// correct sorted position (unless an explicit [index] is provided).
  /// [setRoots] and [setChildren] sort their input before storing.
  final Comparator<TreeNode<TKey, TData>>? comparator;

  /// Whether this controller sorts siblings with a [comparator].
  ///
  /// Exists because reading [comparator] itself through a covariantly-typed
  /// reference (`TreeController<TKey, Object?>` — how `TreeReorderController`
  /// holds its controller) throws a runtime `TypeError` whenever a
  /// comparator is actually set: the comparator's function type uses
  /// `TData` contravariantly, so a non-null value fails the implicit
  /// covariance check on the read. (A null comparator reads fine — null
  /// inhabits every nullable type — which makes the failure mode
  /// data-dependent and easy to miss.) A `bool` carries no `TData` and is
  /// safe from any reference type.
  bool get hasComparator {
    return comparator != null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ECS-STYLE COMPONENT STORAGE
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Structural per-nid state (parent, children, depth, expansion, ancestors-
  // expanded cache) lives inside [_store]. Visibility-related per-nid state
  // (the order buffer's reverse index, the visible-subtree-size cache, and
  // the roots list) lives inside [_order] (a [VisibleOrderBuffer]). Animation
  // state lives inside [_anim] (an [AnimationCoordinator]).
  //
  // The store grows its dense arrays in lockstep with the controller's
  // own per-nid arrays via the [onCapacityGrew] callback wired up in the
  // initializer for [_store]. The store also fires
  // [NodeStore.onParentChanged] on every [setParent] write; the order
  // buffer subscribes to that callback so the visible-subtree-size cache
  // shifts between ancestor chains automatically. The wiring uses a
  // closure (not a method tearoff) so the [_order] lookup is deferred
  // until the callback fires, breaking what would otherwise be a
  // late-final initialization cycle (`_order`'s initializer references
  // `_store.nids`).
  static const int _kNoParent = kNoParentNid;

  /// Structural-component store. Owns the nid registry plus every dense
  /// per-nid array describing tree structure. See [NodeStore].
  late final NodeStore<TKey, TData> _store =
      NodeStore<TKey, TData>(onCapacityGrew: _onStoreCapacityGrew)
        ..onParentChanged = (nid, oldParent, newParent) =>
            _order.handleParentChanged(nid, oldParent, newParent);

  /// Shorthand for [NodeStore.nids], used throughout this file and its
  /// part files.
  NodeIdRegistry<TKey> get _nids => _store.nids;

  /// Wired into [_store] via [NodeStore.onCapacityGrew]. The controller owns
  /// no per-nid arrays itself: [_anim] aggregates every sub-coordinator's
  /// `resizeForCapacity`, and [_order] owns the visible-subtree-size cache
  /// plus the reverse index.
  void _onStoreCapacityGrew(int newCapacity) {
    _anim.resizeForCapacity(newCapacity);
    _order.resizeForCapacity(newCapacity);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STRUCTURAL DELEGATORS
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Thin wrappers over [_store], used by the rest of the controller and
  // its part files. Logic that mixes structural and visibility concerns
  // (like the visible-subtree-size adjustment in [_setParentKey]) stays
  // here on the controller, the only owner of the visibility-side state.

  /// Returns the nid for [key], allocating one if the key isn't registered.
  /// Idempotent for already-registered keys. Nids are recycled, so a freshly
  /// allocated one must have every per-nid array slot reset.
  int _adoptKey(TKey key) {
    final result = _store.adopt(key);
    final nid = result.nid;
    if (!result.isNew) {
      return nid;
    }
    _order.clearForNid(nid); // visible-subtree-size + reverse index
    _anim.clearForNid(nid); // every animation source + shared per-nid state
    return nid;
  }

  /// Returns the parent key for [key], or null if [key] is a root or
  /// unregistered.
  ///
  /// The parent nid slot can be null when the parent has already been
  /// freed ahead of this node in a removal sweep, so the reverse lookup
  /// must tolerate a null result.
  TKey? _parentKeyOfKey(TKey key) => _store.parentOf(key);

  /// Sets the parent of [key] to [parent] (or null for root). [key] must
  /// already be registered; [parent] must also be registered (unless null).
  ///
  /// Forwards directly to [NodeStore.setParent], which fires
  /// [NodeStore.onParentChanged] after the structural write — the order
  /// buffer's [VisibleOrderBuffer.handleParentChanged] subscriber shifts
  /// the visible-subtree-size cache from the old ancestor chain to the
  /// new one. No additional bookkeeping needed here.
  void _setParentKey(TKey key, TKey? parent) => _store.setParent(key, parent);

  /// Releases the nid associated with [key] back to the pool. Clears every
  /// per-nid dense array slot so a future [_adoptKey] that recycles the
  /// nid sees a clean state.
  void _releaseNid(TKey key) {
    final nid = _store.release(key);
    if (nid == null) return;
    _order.clearForNid(nid);
    _anim.clearForNid(nid);
  }

  /// Nullable lookup of the [TreeNode] record for [key].
  TreeNode<TKey, TData>? _dataOf(TKey key) => _store.dataOf(key);

  /// Whether [key] currently has a node record.
  bool _hasKey(TKey key) => _store.has(key);

  /// Returns the child key list for [key], or null if unregistered or no
  /// list has been allocated yet.
  List<TKey>? _childListOf(TKey key) => _store.childListOf(key);

  /// Returns the child key list for [key], allocating an empty list if
  /// none exists. [key] must already be registered.
  List<TKey> _childListOrCreate(TKey key) => _store.childListOrCreate(key);

  /// Replaces the child key list for [key]. [key] must be registered.
  void _setChildList(TKey key, List<TKey> list) =>
      _store.setChildList(key, list);

  /// Depth for [key], or 0 if unregistered.
  int _depthOfKey(TKey key) => _store.depthOf(key);

  /// Sets the depth for [key]. [key] must be registered.
  void _setDepthKey(TKey key, int depth) => _store.setDepth(key, depth);

  /// Whether [key] is currently expanded. Returns false if unregistered.
  bool _isExpandedKey(TKey key) => _store.isExpanded(key);

  /// Sets the expansion flag for [key]. [key] must be registered.
  ///
  /// By default propagates the change through the ancestors-expanded cache
  /// for descendants so ancestor-expansion queries stay O(1). Pass
  /// [propagate] as `false` in bulk paths that rebuild the cache wholesale
  /// via [_rebuildAllAncestorsExpanded].
  void _setExpandedKey(TKey key, bool expanded, {bool propagate = true}) =>
      _store.setExpanded(key, expanded, propagate: propagate);

  /// Rebuilds the ancestors-expanded cache wholesale from the current roots.
  void _rebuildAllAncestorsExpanded() =>
      _store.rebuildAllAncestorsExpanded(_roots);

  /// O(1) "are all ancestors of [key] expanded?" check.
  bool _ancestorsExpandedFast(TKey key) => _store.ancestorsExpandedFast(key);

  /// Clears the expanded flag for every registered node whose depth is
  /// less than [maxDepth] (or for every node when [maxDepth] is null), then
  /// rebuilds the ancestors-expanded cache.
  void _collapseAllInRegistry(int? maxDepth) =>
      _store.collapseAllInRegistry(maxDepth, _roots);

  // ══════════════════════════════════════════════════════════════════════════
  // VISIBILITY STATE
  // ══════════════════════════════════════════════════════════════════════════

  /// Live, mutable accessor for the root-key list. `_order.roots` is the
  /// source of truth, and the reference is stable for the lifetime of the
  /// buffer. Controller call sites mutate it via standard List operations
  /// (`add`, `remove`, `insert`, `..clear()..addAll(...)`); the
  /// `UnmodifiableListView` exposed publicly as [rootKeys] reflects every
  /// mutation through the same underlying list.
  List<TKey> get _roots => _order.roots;

  /// Flattened visible-order buffer: maintains the dense nid array, the
  /// reverse nid → visible-index map, the per-nid visible-subtree-size
  /// cache, and the roots list. Mutations invalidate the full-extent
  /// prefix sum via the `onOrderMutated` callback. The buffer subscribes
  /// to [NodeStore.onParentChanged] (wired in the [_store] initializer
  /// cascade above) so the subtree-size cache shifts between ancestor
  /// chains automatically on reparent.
  late final VisibleOrderBuffer<TKey> _order = VisibleOrderBuffer<TKey>(
    registry: _nids,
    parentByNid: (nid) => _store.parentByNid[nid],
    childKeysOf: (key) => _store.childListOf(key),
    onOrderMutated: () => _scroll.invalidatePrefix(),
  );

  /// Number of full reverse-index resets (O(nidCapacity) memsets) the
  /// order buffer has performed. Perf oracle for the contiguous-removal
  /// fast path: incremental mutations must not trigger one.
  @visibleForTesting
  int get debugOrderResetIndexAllCount => _order.debugResetIndexAllCount;

  /// Opt-in: run the FULL cross-structure consistency sweep (whole order
  /// walk, nid-table walks, every animation mirror) after every
  /// incremental order mutation in debug builds. Off by default — the
  /// sweep makes N sequential inserts O(N²) in debug; the default is an
  /// O(changed-range) order/reverse-index agreement check. The fuzz/purge
  /// suites, which exist to exercise the invariants, enable this.
  static bool debugFullConsistencyChecks = false;

  /// Debug-only forwarder to
  /// [VisibleOrderBuffer.debugAssertSubtreeSizeConsistent], used by the
  /// fuzz and purge suites.
  @visibleForTesting
  void debugAssertVisibleSubtreeSizeConsistency() =>
      _order.debugAssertSubtreeSizeConsistent();

  /// All currently-live keys, in nid order. Debug-only accessor for tests
  /// that need to pick a random key from the live set.
  @visibleForTesting
  Iterable<TKey> get debugAllKeys sync* {
    for (int nid = 0; nid < _nids.length; nid++) {
      final key = _nids.keyOf(nid);
      if (key != null) {
        yield key;
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ANIMATION STATE — owned by AnimationCoordinator
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Every animation source (standalone, per-operation groups, bulk, slide)
  // and every cross-source per-nid array (full-extent, pending-deletion,
  // union mirrors) lives inside [_anim]. The controller keeps:
  //
  // - Status-change handlers (`_onBulkAnimationComplete`,
  //   `_onOperationGroupStatusChange`) because they cross structure /
  //   order / structural-notification concerns.
  // - The standalone-tick completion handler (`_onStandaloneTickComplete`)
  //   for the same reason — it calls `_finalizeAnimation`, which purges
  //   structure.
  // - Private forwarders (`_clearStandalone`, `_setOperationGroup`,
  //   `_isPendingDeletion`, …) used by this file and the part files.
  // - `_keysToRemoveScratch` — controller-owned scratch buffer for the
  //   status / finalize handlers.

  /// Animation subsystem facade. Owns the five animation sources plus
  /// every cross-source per-nid array.
  late final AnimationCoordinator<TKey> _anim = AnimationCoordinator<TKey>(
    vsync: _vsync,
    nids: _nids,
    enterExitDurationGetter: () =>
        _animationStyle.effectiveEnterExit.duration,
    enterExitCurveGetter: () => _animationStyle.effectiveEnterExit.curve,
    expandCollapseDurationGetter: () =>
        _animationStyle.expandCollapse.duration,
    onOperationGroupStatus: _onOperationGroupStatusChange,
    onBulkAnimationStatus: _onBulkAnimationComplete,
    onStandaloneTickComplete: _onStandaloneTickComplete,
    // Single source of the unmeasured-row fallback: the animator layers
    // can't import this class, so the constant is injected rather than
    // mirrored.
    defaultExtent: defaultExtent,
  );

  /// Public read-only accessor for the animation subsystem. Render-layer
  /// hot paths bind to this via [AnimationReader] (the narrow read
  /// interface implemented by [AnimationCoordinator]).
  AnimationReader<TKey> get anim => _anim;

  /// Scratch buffer used by the status-change handlers and
  /// `_finalizeAnimation` to batch order-removal. Lives on the controller
  /// because its consumers do.
  final Set<TKey> _keysToRemoveScratch = <TKey>{};

  /// Forwards completed standalone keys from the StandaloneAnimator's
  /// per-tick callback into the controller-side `_finalizeAnimation`
  /// handler. Stays here because `_finalizeAnimation` crosses structure /
  /// order / notification.
  ///
  /// Mirrors the standalone tick's post-progress block: capture
  /// parent-before-finalize → finalize each → batch _removeFromVisibleOrder
  /// → bump structure → fire structural notification. The animator's
  /// tick callback ALSO fires the listener channel via the wrapper
  /// closure in AnimationCoordinator, so this method does not need to
  /// call _notifyAnimationListeners.
  void _onStandaloneTickComplete(Iterable<TKey> completedKeys) {
    if (completedKeys.isEmpty) return;
    final parentBeforeFinalize = <TKey, TKey>{};
    for (final key in completedKeys) {
      if (_isPendingDeletion(key)) {
        final parent = _parentKeyOfKey(key);
        if (parent != null) {
          parentBeforeFinalize[key] = parent;
        }
      }
    }
    _keysToRemoveScratch.clear();
    final affectedParents = <TKey>{};
    for (final key in completedKeys) {
      if (_finalizeAnimation(key)) {
        _keysToRemoveScratch.add(key);
        final parent = parentBeforeFinalize[key];
        if (parent != null) {
          // The parent's child-list length just changed; its builder may
          // render the count (TreeItemView.childCount), so it must
          // refresh, not only on the empty flip. A parent purged along
          // with its subtree is a dead key here, which is a cheap no-op
          // at the element side.
          affectedParents.add(parent);
        }
      }
    }
    if (_keysToRemoveScratch.isNotEmpty) {
      _removeFromVisibleOrder(_keysToRemoveScratch);
      _structureGeneration++;
      _notifyStructural(affectedKeys: affectedParents);
    }
    // Stop the ticker if no standalone animations remain.
    if (!_hasAnyStandalone) {
      _anim.standalone.stop();
    }
  }

  // ──────── Forwarders to AnimationCoordinator ─────────────────────────
  //
  // One-liners delegating to `_anim`, keeping the call sites in this file
  // and the two part files free of the coordinator's internal layout.

  // Standalone animator
  AnimationState? _standaloneAt(TKey key) => _anim.standalone.at(key);
  void _setStandalone(TKey key, AnimationState state) =>
      _anim.standalone.set(key, state);
  AnimationState? _clearStandalone(TKey key) => _anim.standalone.clearAt(key);
  bool _hasStandalone(TKey key) => _anim.standalone.hasAt(key);
  bool get _hasAnyStandalone => _anim.standalone.hasAny;

  // Operation groups
  TKey? _operationGroupOf(TKey key) => _anim.opGroups.groupKeyOf(key);
  bool _hasOperationGroup(TKey key) => _anim.opGroups.hasGroup(key);
  void _setOperationGroup(TKey key, TKey opKey) =>
      _anim.opGroups.setMembership(key, opKey);
  TKey? _clearOperationGroup(TKey key) => _anim.opGroups.clearMembership(key);
  void _disposeOperationGroupIfEmpty(TKey opKey, OperationGroup<TKey> _) =>
      _anim.opGroups.disposeIfEmpty(opKey);

  // Bulk animator
  bool _addBulkMember(TKey key) => _anim.bulk.addMember(key);
  bool _removeBulkMember(TKey key) => _anim.bulk.removeMember(key);
  bool _addBulkPending(TKey key) => _anim.bulk.addPending(key);
  bool _removeBulkPending(TKey key) => _anim.bulk.removePending(key);
  void _clearBulkPending() => _anim.bulk.clearPending();
  void _disposeBulkAnimationGroup() => _anim.bulk.disposeGroup();

  // Pending deletion
  bool _isPendingDeletion(TKey key) => _anim.isPendingDeletion(key);
  void _markPendingDeletion(TKey key) => _anim.markPendingDeletion(key);
  void _clearPendingDeletion(TKey key) => _anim.clearPendingDeletion(key);

  // Full extent table
  double? _fullExtentOf(TKey key) => _anim.fullExtentOf(key);
  double? _clearFullExtent(TKey key) => _anim.clearFullExtent(key);

  // Generation bumps
  void _bumpAnimGen() => _anim.bumpAnimGen();
  void _bumpBulkGen() => _anim.bumpBulkGen();

  // Capture / cancel / multi-source remove
  double? _captureAndRemoveFromGroups(TKey key) =>
      _anim.captureAndRemoveFromGroups(key);
  AnimationState? _removeAnimation(TKey key) => _anim.removeFromAllSources(key);

  // Listener channel
  void _notifyAnimationListeners() => _anim.notifyListeners();

  // Animating-keys cache — public access via `currentlyAnimatingKeys`
  // and the AnimationReader getters; in-file callers use _anim directly.

  // Slide engine — used by the controller's public slide API forwarders
  // and by `_cancelAnimationStateForSubtree`.
  SlideAnimationEngine<TKey> get _slide => _anim.slide;
  ReorderPreviewEngine get _preview => _anim.preview;

  // Cross-class accessors used by the part files
  // (_tree_controller_animation.dart, _tree_controller_helpers.dart) so
  // they reach bulk and operation-group state through one named hop
  // instead of indexing the coordinator's collections directly. Group
  // removal goes through `_anim.opGroups.removeGroup`; the
  // pending-deletion count is read-only via `_anim.pendingDeletionCount`.
  AnimationGroup<TKey>? get _activeBulkGroup => _anim.bulk.group;
  OperationGroup<TKey>? _opGroupAt(TKey opKey) => _anim.opGroups.groupAt(opKey);
  Iterable<MapEntry<TKey, OperationGroup<TKey>>> get _opGroupEntries =>
      _anim.opGroups.groups;
  bool get _hasAnyOpGroup => _anim.opGroups.isNotEmpty;

  /// Reusable snapshot buffer used by [expandAll] and [collapseAll] when
  /// they iterate [_opGroupEntries] and call `forward()`/`reverse()` inside
  /// the loop. The status listener registered by the operation-group
  /// registry calls `removeGroup` on terminal status, which mutates the
  /// underlying `_groups` map. If a group's controller is already at a
  /// terminal value (1.0 / 0.0) when `forward()`/`reverse()` is invoked,
  /// the SDK fires the status callback synchronously, mutating the map
  /// mid-iteration and throwing `ConcurrentModificationError`. The buffer
  /// is shared because the two callers run sequentially on the same
  /// controller instance.
  final List<MapEntry<TKey, OperationGroup<TKey>>> _opGroupSnapshot =
      <MapEntry<TKey, OperationGroup<TKey>>>[];

  // Private field — already invisible across files.
  final Set<TreeRenderHost> _renderHosts = <TreeRenderHost>{};

  /// Phantom-anchor relationships staged by `moveNode(animate: true)` for
  /// keys whose moved subtree was hidden at mutation time (because the old
  /// parent or an ancestor was collapsed). Each entry maps a soon-to-be-
  /// visible key to the OLD visible ancestor whose painted position should
  /// be used as the slide's "prior" anchor.
  ///
  /// Drained by `RenderSliverTree._consumeSlideBaselineIfAny` via
  /// [takePendingPhantomAnchors] when the next layout consumes the staged
  /// baseline. Cleared after consumption — never persists across slide
  /// cycles.
  Map<TKey, TKey>? _pendingPhantomAnchors;

  /// Returns and clears the staged phantom-anchor relationships. Called by
  /// the render object during baseline consumption. Returns null when no
  /// relationships were staged (the common case — only animated reparents
  /// of hidden subtrees produce entries).
  ///
  /// **Internal contract** — sliver-render-object-specific.
  Map<TKey, TKey>? takePendingPhantomAnchors() {
    final result = _pendingPhantomAnchors;
    _pendingPhantomAnchors = null;
    return result;
  }

  /// Exit-phantom relationships staged by `moveNode(animate: true)` for
  /// keys whose moved subtree was visible BEFORE mutation but became
  /// hidden AFTER (because the new parent or an ancestor is collapsed).
  /// Each entry maps a soon-to-be-hidden key to the NEW visible ancestor
  /// (typically the new collapsed parent's row) whose painted position
  /// should be used as the slide's destination anchor — the row visually
  /// slides into the new parent's row and disappears behind it.
  ///
  /// Symmetric to [_pendingPhantomAnchors] (the entry case). Drained by
  /// the render object during baseline consumption.
  Map<TKey, TKey>? _pendingExitPhantomAnchors;

  /// Returns and clears the staged exit-phantom relationships. Companion
  /// to [takePendingPhantomAnchors] for the visible-to-hidden case.
  ///
  /// **Internal contract** — sliver-render-object-specific.
  Map<TKey, TKey>? takePendingExitPhantomAnchors() {
    final result = _pendingExitPhantomAnchors;
    _pendingExitPhantomAnchors = null;
    return result;
  }

  /// Padding past the viewport edge (in viewport-heights) used as the
  /// start position (slide-IN) or end position (slide-OUT edge ghost) for
  /// FLIP slides whose prior or current is off-screen. A small overhang
  /// gives the row visible motion *into* / *out of* the viewport rather
  /// than appearing/disappearing exactly at the edge.
  ///
  /// Defaults to 0.1 (10% of viewport extent). Set to 0 to clamp exactly
  /// at the viewport edge; set higher to extend the start/end further off
  /// screen (lengthening the visible portion of the slide-in entrance).
  ///
  /// Live setting; changes take effect on the next slide install.
  double slideClampOverhangViewports = 0.1;

  /// Registers a render host. Called by `RenderSliverTree.attach`. Idempotent.
  ///
  /// **Internal contract** — the staging protocol is sliver-render-object-
  /// specific; external callers will get inconsistent results.
  void registerRenderHost(TreeRenderHost host) {
    _renderHosts.add(host);
  }

  /// Unregisters a render host. Called by `RenderSliverTree.detach`. Tolerant
  /// of a host that was never registered (no-op).
  ///
  /// **Internal contract** — see [registerRenderHost].
  void unregisterRenderHost(TreeRenderHost host) {
    _renderHosts.remove(host);
  }

  /// Fans out a baseline-capture request to every attached render host.
  /// Returns true if at least one host is participating in this slide cycle —
  /// either it freshly staged a baseline, or a prior pending baseline (from
  /// an earlier same-frame call) is being honored under first-wins. Returns
  /// false only when no host could participate at all (no hosts attached, or
  /// all hosts unmounted).
  bool _stageSlideBaselineOnHosts({
    required Duration duration,
    required Curve curve,
  }) {
    if (_renderHosts.isEmpty) return false;
    bool any = false;
    for (final host in _renderHosts) {
      if (host(duration: duration, curve: curve)) any = true;
    }
    return any;
  }

  /// Whether [key] currently has a live (non-zero) FLIP slide delta — which,
  /// because exit ghosts slide toward their anchor's SETTLED y, is also true
  /// for any in-flight exit-ghost (its delta is non-zero for the whole
  /// traversal). Gates base-change staging so idle expand/collapse stays
  /// free of staging
  /// overhead. No need to peek the render layer's `_phantomExitGhosts`: a live
  /// exit-ghost always carries a non-zero slide delta here.
  bool _hasLiveSlideOrExitGhost(TKey key) => getSlideDelta(key) != 0.0;

  /// Stages a slide baseline (first-wins) when a row whose structural
  /// base is about to change currently has a live slide/ghost. Called from
  /// [expand]/[collapse] BEFORE the structural mutation so the captured
  /// painted positions are the FLIP "before". The next `performLayout` consume
  /// composes `newDelta = currentPaintedPosition − newStructuralOffset` through
  /// the engine's existing composition path, preserving painted position
  /// across the base change (no teleport, no extra layout pass).
  ///
  /// The live-slide gate is load-bearing: staging unconditionally would
  /// install a FLIP slide for every descendant on every expand/collapse and
  /// double-animate against the op-group extent envelope. Only rows already
  /// mid-slide get rebased.
  void _stageSlideBaselineForBaseChange(Iterable<TKey> rows) {
    var anyLive = false;
    for (final row in rows) {
      if (_hasLiveSlideOrExitGhost(row)) {
        anyLive = true;
        break;
      }
    }
    if (!anyLive) return;
    _stageSlideBaselineOnHosts(
      duration: _animationStyle.expandCollapse.duration,
      curve: _animationStyle.expandCollapse.curve,
    );
  }

  // Animation tick listeners live in AnimationCoordinator; the
  // addAnimationListener / removeAnimationListener forwarders are in the
  // ANIMATION LISTENERS section below.

  /// Listeners notified when a single node's data changes without any
  /// structural change (e.g. [updateNode]). Receives the changed key.
  final List<void Function(TKey)> _nodeDataListeners = [];

  /// Listeners notified on structural mutations with an optional set of
  /// affected keys. A `null` set means "scope unknown — full refresh"; an
  /// empty set means "structural change happened, but no mounted row's
  /// builder output changed" (valid when the effect is absorbed by
  /// `createChild` for new rows and GC for removed rows); a non-empty set
  /// lists exactly the keys whose builder output may differ.
  final List<void Function(Set<TKey>? affectedKeys)> _structuralListeners = [];

  /// Depth of nested [runBatch] calls. Mutations inside a batch defer
  /// their structural notification to the outermost [runBatch] exit.
  int _batchDepth = 0;

  /// Set when a mutation inside [runBatch] requested a structural
  /// notification. Drained and fired once when [_batchDepth] returns to 0.
  bool _batchDidRequestStructural = false;

  /// Keys whose data changed inside the current [runBatch]. Drained after
  /// the structural notification fires so that targeted row refreshes see
  /// a coherent post-batch state.
  Set<TKey>? _batchDirtyDataNodes;

  /// Union of [affectedKeys] sets passed to [_notifyStructural] inside the
  /// current [runBatch]. Fired as a single set at the outermost batch exit.
  /// Null when no mutation has specified affected keys yet.
  Set<TKey>? _batchAffectedStructuralKeys;

  /// Poison pill: set to true when any in-batch [_notifyStructural] call
  /// passes `affectedKeys: null`. Forces a full refresh at batch exit even
  /// if other in-batch calls carried specific keys.
  bool _batchAffectedStructuralUnknown = false;

  /// Set when a mutation inside [runBatch] would have triggered a full
  /// [_rebuildVisibleOrder] call. Inside a batch, mutations call
  /// [_markVisibleOrderDirty] instead of rebuilding directly: K reparents
  /// in one batch then collapse to ONE rebuild at outermost batch exit
  /// instead of K full DFS+post-order passes. Outside a batch, the
  /// helper rebuilds immediately so external behavior is unchanged.
  ///
  /// While the flag is true, [_order] reflects the structural state at
  /// batch entry, not the live mutated state. In-batch readers that
  /// depend on visible-order membership (e.g. [moveNode]'s phantom-anchor
  /// decisions) must consult a structural predicate that's correct
  /// regardless of [_order] freshness — see [_isStructurallyVisible].
  /// Public visible-order accessors call [_ensureVisibleOrder] first to
  /// flush the deferred rebuild on demand.
  bool _visibleOrderDirty = false;

  /// Default extent for nodes that haven't been measured yet.
  static const double defaultExtent = 48.0;

  /// Monotonically increasing counter incremented whenever the visible
  /// order is structurally mutated (nodes added, removed, or reordered).
  /// Used by the render object to detect structure changes even when the
  /// visible node count stays the same.
  int _structureGeneration = 0;
  int get structureGeneration => _structureGeneration;

  /// Scroll orchestrator. Owns the full-extent prefix-sum cache plus the
  /// Whether [_scroll]'s lazy initializer has run. Lets [dispose] tear
  /// down an in-flight animated scroll without instantiating the
  /// orchestrator just to dispose it.
  bool _scrollCreated = false;

  /// four scroll-API methods. See [ScrollOrchestrator].
  late final ScrollOrchestrator<TKey, TData> _scroll = () {
    _scrollCreated = true;
    return ScrollOrchestrator<TKey, TData>(controller: this, vsync: _vsync);
  }();

  /// Cached result of [computeFirstAnimatingVisibleIndex]. Depends on both
  /// animation state and the visible order, so the cache key combines
  /// the coordinator's animation generation with [_structureGeneration].
  int _firstAnimatingIndexCacheSig = -1;
  int _firstAnimatingIndexCacheVal = 0;

  // The animation generation counters, union mirrors and animating-key
  // caches all live in AnimationCoordinator; the ANIMATION STATE block
  // above forwards to them. The two render-layer hot-path reads
  // (isAnimatingNid / isExitingNid) are public and delegate directly.

  /// Hot-path equivalent of [isAnimating]: O(1) array read via the
  /// AnimationCoordinator's union mirror. Caller must guarantee [nid] is
  /// live and within range.
  bool isAnimatingNid(int nid) => _anim.isAnimatingNid(nid);

  /// Hot-path equivalent of [isExiting].
  bool isExitingNid(int nid) => _anim.isExitingNid(nid);

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC QUERIES
  // ══════════════════════════════════════════════════════════════════════════

  /// The flattened list of visible node IDs in render order.
  ///
  /// Returns a read-only live view over the internal nid-indexed buffer.
  /// Mutations to the visible order are reflected automatically.
  late final List<TKey> visibleNodes = _VisibleNodesView<TKey, TData>(this);

  /// Number of visible nodes.
  int get visibleNodeCount {
    _ensureVisibleOrder();
    return _order.length;
  }

  int get rootCount => _roots.length;

  /// Root node IDs in order.
  ///
  /// Returns an unmodifiable view of the internal list.
  /// The wrapper reflects mutations to [_roots] automatically.
  late final List<TKey> rootKeys = UnmodifiableListView<TKey>(_roots);

  /// Gets the ordered list of child keys for the given node.
  ///
  /// Returns an empty list if the node has no children or doesn't exist.
  List<TKey> getChildren(TKey key) {
    final c = _childListOf(key);
    if (c == null || c.isEmpty) return const [];
    return UnmodifiableListView<TKey>(c);
  }

  /// Gets the node data for the given key, or null if not found.
  TreeNode<TKey, TData>? getNodeData(TKey key) {
    return _dataOf(key);
  }

  /// Gets the depth of the given node (0 for roots).
  int getDepth(TKey key) {
    return _depthOfKey(key);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NID-SPACE ACCESSORS (intended for render-layer consumers)
  // ══════════════════════════════════════════════════════════════════════════
  //
  // These expose the internal nid registry so hot-path consumers (notably
  // RenderSliverTree) can keep per-node state in dense typed-data arrays
  // indexed by nid instead of hashing [TKey] on every read.
  //
  // Nids are stable for the lifetime of a node but may be recycled after
  // [remove]/purge. Consumers that cache nid-indexed state must invalidate
  // or overwrite on structural change.

  /// Sentinel returned by [nidOf] when the key isn't registered. Same value
  /// as the internal [VisibleOrderBuffer.kNotVisible] but exposed separately since callers
  /// should treat it as "unknown key".
  static const int noNid = NodeIdRegistry.noNid;

  /// Returns the internal nid for [key], or [noNid] if the key isn't
  /// currently registered. O(1).
  int nidOf(TKey key) => _nids.nidOf(key);

  /// Returns the key associated with [nid], or null if the nid has been
  /// released. O(1). Consumers that cache nid-indexed state can use this to
  /// detect stale entries after node removal.
  TKey? keyOfNid(int nid) => _nids.keyOf(nid);

  /// The current high-water mark for allocated nids. Nid-indexed dense
  /// arrays maintained externally should grow to at least this length.
  int get nidCapacity => _nids.length;

  /// Returns the nid of the visible node at [visibleIndex]. No [TKey] hash
  /// occurs. Panics (unchecked read) if [visibleIndex] is out of range.
  int visibleNidAt(int visibleIndex) {
    _ensureVisibleOrder();
    return _order.orderNids[visibleIndex];
  }

  /// Read-only view over the visible-order nid buffer for hot-path
  /// consumers that walk all visible positions and want to skip the
  /// per-position [visibleNidAt] dispatch. The underlying buffer's
  /// length may exceed [visibleNodeCount] — only the first N entries
  /// are valid. The buffer itself is mutated in place by structural
  /// changes; callers must not retain the reference across mutations.
  Int32List get orderNidsView {
    _ensureVisibleOrder();
    return _order.orderNids;
  }

  /// Visible-order index for the live nid [nid], or
  /// [VisibleOrderBuffer.kNotVisible] when [nid] is not currently in the
  /// visible order. O(1) typed-data read; no [TKey] hash. Hot-path
  /// equivalent of `_order.indexByNid[nid]`.
  ///
  /// Caller must guarantee [nid] is live and within range.
  int visibleIndexOfNid(int nid) {
    _ensureVisibleOrder();
    return _order.indexByNid[nid];
  }

  /// Depth for [nid] (0 for roots). No [TKey] hash. [nid] must be live.
  int depthOfNid(int nid) => _store.depthByNid[nid];

  /// Estimated full extent for the live [nid] — measured value when
  /// available, [defaultExtent] otherwise. Hot-path equivalent of
  /// [getEstimatedExtent] that avoids the [TKey]→nid hash. Caller must
  /// guarantee [nid] is live and within range.
  double getEstimatedExtentNid(int nid) {
    // Direct nid-indexed read — the store is nid-keyed, so no key
    // resolution (and no string hash) is involved at all.
    return _anim.fullExtentOfNid(nid) ?? defaultExtent;
  }

  // ════════════════════════════════════════════════════════════════════════
  // INTERNAL ACCESSORS (for in-package collaborators only)
  // ════════════════════════════════════════════════════════════════════════
  //
  // Documented as internal-use-only via doc comments. The package layout
  // (`lib/sliver_tree/...`) doesn't qualify for the `@internal` annotation,
  // which expects elements in `lib/src/`. Used by `_scroll_orchestrator.dart`
  // and the render layer to reach state that would otherwise require
  // `part of` coupling.

  /// Live, read-only view of every key currently animating across
  /// standalone, operation-group, and bulk sources. Backed by the lazy
  /// `AnimationCoordinator.ensureAnimatingKeys` cache; **do NOT mutate**
  /// — same convention as
  /// [orderNidsView]. Iteration is stable within one frame.
  Set<TKey> get currentlyAnimatingKeys => _anim.ensureAnimatingKeys();

  /// The measured full extent for [key], or null if [key] has never been
  /// laid out. Distinct from [getEstimatedExtent], which falls back to
  /// [defaultExtent] for unmeasured nodes.
  double? getMeasuredExtent(TKey key) => _fullExtentOf(key);

  /// Captures an opaque token identifying the current operation group at
  /// [operationKey], or null if no group is installed there.
  Object? captureOperationGroupToken(TKey operationKey) =>
      _opGroupAt(operationKey);

  /// Whether the operation group at [operationKey] is identity-equal to
  /// the one captured by [captureOperationGroupToken].
  bool isOperationGroupSame(TKey operationKey, Object? token) =>
      token != null && identical(_opGroupAt(operationKey), token);

  /// Forwards to the coordinator's listener channel so the scroll
  /// orchestrator's `AnimationController` (`scrollProgress`) can fire
  /// ticks through the controller's animation-listener channel.
  void notifyAnimationListenersForScroll() => _anim.notifyListeners();

  /// Current animated extent for the live [nid]. Hot-path forwarder to
  /// the AnimationCoordinator's nid-keyed read.
  double getCurrentExtentNid(int nid) => _anim.getCurrentExtentNid(nid);

  /// Slide delta for the live [nid] (paint-only FLIP offset), or 0.0 when
  /// the node is not currently sliding. Hot-path equivalent of
  /// [getSlideDelta] — read every paint, hit-test, and transform call
  /// for visible rows, so saving the [TKey]→nid hash matters.
  double getSlideDeltaNid(int nid) {
    // Composed with the make-room preview: painted position =
    // structural + FLIP delta + held preview offset. One boolean guard
    // keeps the non-drag hot path unchanged.
    final base = _slide.deltaForNid(nid);
    if (!_preview.hasActive) {
      return base;
    }
    return base + _preview.deltaForNid(nid);
  }

  /// X-axis (cross-axis indent) slide delta for the live [nid], or 0.0
  /// when the node is not currently sliding. Hot-path equivalent of
  /// [getSlideDeltaX] — read on every paint, hit-test, and transform
  /// call for visible rows during a depth-changing reparent.
  double getSlideDeltaXNid(int nid) => _slide.deltaXForNid(nid);

  /// X-axis (cross-axis indent) slide delta for [key], or 0.0 when the
  /// node is not currently sliding (or not registered).
  double getSlideDeltaX(TKey key) => _slide.deltaXForKey(key);

  /// Internal-use-only: marks the slide entry for [key] to bypass the
  /// engine's "un-touched re-baseline" branch on subsequent batch
  /// installs.
  ///
  /// Set-only-true semantics — the engine implicitly clears the flag
  /// when the slide entry is destroyed (settles, cancelled, or replaced
  /// via composition). The render layer should never need to clear the
  /// flag explicitly.
  ///
  /// Used by the render layer for active edge-ghost and exit-phantom
  /// slides so concurrent mutations (e.g. autoscroll commits) don't
  /// restart the ghost's progress clock. Tolerant of unregistered keys
  /// and inactive slides (no-op).
  void markSlidePreserveProgress(TKey key) => _slide.markPreserveProgress(key);

  /// Gets the horizontal indent for the given node.
  double getIndent(TKey key) {
    return getDepth(key) * indentWidth;
  }

  /// Whether the given node is expanded.
  bool isExpanded(TKey key) {
    return _isExpandedKey(key);
  }

  /// Whether [key] is currently in the flattened visible order — i.e.
  /// every ancestor (if any) is expanded AND the node itself exists.
  ///
  /// O(1) via the visible-order buffer's nid-indexed reverse lookup.
  /// Useful for the render object to distinguish "truly hidden" from
  /// "ghost-rendered after a visible→hidden reparent."
  bool isVisible(TKey key) {
    _ensureVisibleOrder();
    return _order.contains(key);
  }

  /// Whether the given node has children.
  bool hasChildren(TKey key) {
    final c = _childListOf(key);
    return c != null && c.isNotEmpty;
  }

  /// Gets the number of children for the given node.
  int getChildCount(TKey key) {
    return _childListOf(key)?.length ?? 0;
  }

  /// Returns all descendants of [key] in pre-order (children, grandchildren,
  /// ...). Does not include [key] itself. Returns an empty list if [key] has
  /// no children or is not present.
  ///
  /// Intended for drop-target validation (cycle prevention): a node cannot
  /// be reparented under any of its own descendants.
  List<TKey> getDescendants(TKey key) => _getDescendants(key);

  /// Whether [key] is pending deletion — present in the structural maps but
  /// animating out and scheduled for purge once the animation settles.
  ///
  /// Drop-target resolution should skip pending-deletion rows: they are
  /// visually vanishing and cannot be valid reorder targets. Also used as
  /// the predicate for filtering [rootKeys] / [getChildren] down to the
  /// live sets accepted by [reorderRoots] / [reorderChildren].
  bool isPendingDeletion(TKey key) => _isPendingDeletion(key);

  /// Root keys that are not pending deletion.
  ///
  /// Matches the input contract of [reorderRoots]: the reorder API
  /// validates `orderedKeys` against exactly this set and re-appends
  /// pending-deletion entries internally. Passing the full [rootKeys] to
  /// [reorderRoots] would fail the length check when any root is mid-exit.
  List<TKey> get liveRootKeys {
    if (_anim.pendingDeletionCount == 0) return List<TKey>.of(_roots);
    final result = <TKey>[];
    for (final k in _roots) {
      if (!_isPendingDeletion(k)) result.add(k);
    }
    return result;
  }

  /// Children of [parent] that are not pending deletion.
  ///
  /// Matches the input contract of [reorderChildren]. Returns an empty list
  /// if [parent] is not present or has no children.
  List<TKey> getLiveChildren(TKey parent) {
    final full = _childListOf(parent);
    if (full == null || full.isEmpty) return const [];
    if (_anim.pendingDeletionCount == 0) return List<TKey>.of(full);
    final result = <TKey>[];
    for (final k in full) {
      if (!_isPendingDeletion(k)) result.add(k);
    }
    return result;
  }

  /// Whether [parent] has at least one live (non-pending-deletion) child.
  ///
  /// Non-allocating variant of `getLiveChildren(parent).isNotEmpty` for
  /// per-pointer-move hot paths: drop-zone resolution asks this on every
  /// pointer move and autoscroll tick, and the list-materializing form
  /// copied the full child list just to test emptiness. O(1) when no
  /// deletions are pending; otherwise O(children until the first live hit).
  bool hasLiveChildren(TKey parent) {
    final full = _childListOf(parent);
    if (full == null || full.isEmpty) {
      return false;
    }
    if (_anim.pendingDeletionCount == 0) {
      return true;
    }
    for (final k in full) {
      if (!_isPendingDeletion(k)) {
        return true;
      }
    }
    return false;
  }

  /// Number of live (non-pending-deletion) roots. Non-allocating variant
  /// of `liveRootKeys.length` for hot paths (drop-zone boundary checks).
  int get liveRootCount {
    if (_anim.pendingDeletionCount == 0) {
      return _roots.length;
    }
    var count = 0;
    for (final k in _roots) {
      if (!_isPendingDeletion(k)) {
        count++;
      }
    }
    return count;
  }

  /// Number of live (non-pending-deletion) children of [parent].
  /// Non-allocating variant of `getLiveChildren(parent).length` for hot
  /// paths (drop-zone boundary checks ask this per candidate level).
  int liveChildCount(TKey parent) {
    final full = _childListOf(parent);
    if (full == null || full.isEmpty) {
      return 0;
    }
    if (_anim.pendingDeletionCount == 0) {
      return full.length;
    }
    var count = 0;
    for (final k in full) {
      if (!_isPendingDeletion(k)) {
        count++;
      }
    }
    return count;
  }

  /// Returns the zero-based index of [key] within the **live** sibling list
  /// of its parent (or the live root list, if [key] is a root). Returns -1
  /// if [key] is not present or is itself pending deletion.
  ///
  /// Live-space — not full-list-space — so the returned index directly
  /// matches positions in [liveRootKeys] / [getLiveChildren] and the input
  /// space of [reorderRoots] / [reorderChildren].
  int getIndexInParent(TKey key) {
    if (!_hasKey(key) || _isPendingDeletion(key)) return -1;
    final parent = _parentKeyOfKey(key);
    final List<TKey> full = parent == null
        ? _roots
        : (_childListOf(parent) ?? <TKey>[]);
    int liveIndex = 0;
    for (final k in full) {
      if (k == key) return liveIndex;
      if (!_isPendingDeletion(k)) liveIndex++;
    }
    return -1;
  }

  /// Whether any nodes are currently animating.
  ///
  /// Used by the element and render object to defer expensive operations
  /// (like stale-node eviction and sticky precomputation) during animation.
  ///
  /// **Slide animations are deliberately excluded.** Slide is paint-only —
  /// it does not change layout, sticky geometry, or eviction decisions.
  /// Callers that care about slide state read [hasActiveSlides] instead.
  bool get hasActiveAnimations => _anim.hasActiveAnimations;

  /// Whether any FLIP slide animations are currently active.
  ///
  /// Deliberately separate from [hasActiveAnimations]: slide is paint-only
  /// and must not be mixed into the sticky-throttle / eviction-deferral
  /// signal that [hasActiveAnimations] drives. The sliver element routes
  /// slide-only ticks to [RenderObject.markNeedsPaint] rather than
  /// [RenderObject.markNeedsLayout] based on this flag.
  bool get hasActiveSlides => _slide.hasActive || _preview.hasActive;

  /// Whether any in-flight slide has a non-zero X-axis component
  /// (depth-changing reparent). Hot-path render code uses this to skip
  /// per-row X-delta reads when no X-axis work is in flight — the common
  /// case, since most reorders are same-depth.
  bool get hasActiveXSlides => _slide.hasActiveX;

  /// Test-only: the LARGER of the two engines' maxima (|currentDelta|
  /// ceilings), or 0.0 when both are idle.
  ///
  /// NOT a bound on the composed per-row delta and deliberately not part
  /// of the production read surface: [getSlideDeltaNid] SUMS the FLIP
  /// engine and the make-room preview, so a row carrying both can exceed
  /// this max — the bug class every former consumer was migrated off of.
  /// Every window that must provably contain the composed painted
  /// positions (the render's build/paint/hit-test overreach widening, the
  /// bounded drop-target scan) reads [composedSlideAbsDeltaBound] (the
  /// sum). This getter is retained solely for tests that pin the
  /// max-vs-sum distinction: the make-room composition pin, and the
  /// bounded-scan oracle's teeth gate, which must prove its engineered
  /// overlap state exceeds a max-based bound — a value not derivable from
  /// any other public read.
  @visibleForTesting
  double get maxActiveSlideAbsDelta {
    final base = _slide.maxAbsDelta;
    if (!_preview.hasActive) {
      return base;
    }
    final previewMax = _preview.maxAbsDelta;
    return base > previewMax ? base : previewMax;
  }

  /// A true upper bound on the COMPOSED per-row delta — the SUM companion
  /// of [maxActiveSlideAbsDelta]'s max. [getSlideDeltaNid] SUMS the FLIP
  /// engine and the make-room preview, and a row can carry both at once
  /// (a drag started while the prior commit's FLIP is still animating),
  /// reaching up to `slideMax + previewMax`; a max-based bound
  /// under-estimates exactly there. Use THIS bound wherever a window must
  /// provably contain every composed painted position (render overreach
  /// widening, the bounded drop-target scan). Degenerates to the single
  /// engine's max whenever the other is idle (an idle engine's max is
  /// 0.0), so single-engine states pay no extra width. Both engine maxima
  /// are computed on demand — never stale.
  double get composedSlideAbsDeltaBound =>
      _slide.maxAbsDelta + _preview.maxAbsDelta;

  /// Current slide delta for [key] in scroll-space y, or 0.0 if the node is
  /// not currently sliding. Read by [RenderSliverTree.paint],
  /// [RenderSliverTree.applyPaintTransform], and the hit-test path on
  /// every frame (no caching — staleness-safe under tick-without-paint).
  double getSlideDelta(TKey key) {
    final base = _slide.deltaForKey(key);
    if (!_preview.hasActive) {
      return base;
    }
    return base + _preview.deltaForNid(nidOf(key));
  }

  /// True when a bulk animation group is currently active and has members
  /// animating in either direction.
  ///
  /// Used by the render object to gate its scalar-offset fast path.
  bool get isBulkAnimating {
    final g = _activeBulkGroup;
    if (g == null) return false;
    return g.members.isNotEmpty || g.pendingRemoval.isNotEmpty;
  }

  /// Current animation value of the bulk animation group, or 0.0 if none.
  double get bulkAnimationValue => _activeBulkGroup?.value ?? 0.0;

  /// Whether [key] is a member of the bulk animation group (either active
  /// or pending removal at animation end).
  bool isBulkMember(TKey key) {
    final g = _activeBulkGroup;
    if (g == null) return false;
    return g.members.contains(key) || g.pendingRemoval.contains(key);
  }

  /// Whether any non-bulk animations (operation groups or standalone) are
  /// currently active. When false and [isBulkAnimating] is true, the render
  /// object can use its scalar-offset fast path for the whole frame.
  bool get hasOpGroupAnimations => _hasAnyOpGroup || _hasAnyStandalone;

  /// Monotonic counter that bumps whenever the bulk animation group is
  /// created, destroyed, or its member set changes. The render object uses
  /// this to detect when its cached per-position offset cumulatives are stale.
  int get bulkAnimationGeneration => _anim.bulkAnimationGeneration;

  /// Captures every per-frame bulk-animation field the render object reads
  /// during a single layout into one snapshot. Forwards to
  /// [AnimationCoordinator.bulkAnimationData] which delegates to
  /// [BulkAnimator.snapshot]; the inactive case returns the const sentinel
  /// for zero per-call allocation.
  BulkAnimationData<TKey> bulkAnimationData() => _anim.bulkAnimationData();

  /// Returns the smallest visible-order index among all currently-animating
  /// nodes, or [visibleNodeCount] when none are visible / none are animating.
  ///
  /// Used by the render object to skip the O(N) Pass 1 offset rescan during
  /// animation: everything before the returned index has stable offset and
  /// extent from the prior frame, so only indices `>= firstAnimatingIndex`
  /// need to be recomputed.
  ///
  /// Complexity is O(A) in the number of animating nodes, which is normally
  /// much smaller than the visible-order length.
  int computeFirstAnimatingVisibleIndex() {
    if (!hasActiveAnimations) return _order.length;
    // Cache key combines animation generation with structure generation:
    // the result depends on which keys are animating AND their visible indices.
    final sig = _anim.animationGeneration ^ (_structureGeneration * 2654435761);
    if (sig == _firstAnimatingIndexCacheSig &&
        _firstAnimatingIndexCacheVal <= _order.length) {
      return _firstAnimatingIndexCacheVal;
    }
    // Force the mirror rebuild via the coordinator. Iterate the
    // animating-keys cache (the union across all three sources) and find
    // the smallest visible index.
    final animatingKeys = _anim.ensureAnimatingKeys();
    int min = _order.length;
    for (final key in animatingKeys) {
      final idx = _order.indexOf(key);
      if (idx != VisibleOrderBuffer.kNotVisible && idx < min) {
        min = idx;
      }
    }
    _firstAnimatingIndexCacheSig = sig;
    _firstAnimatingIndexCacheVal = min;
    return min;
  }

  /// Debug helper to print bulk animation state.
  /// Call this to verify animation is running correctly.
  void debugPrintBulkAnimationState() {
    if (_activeBulkGroup == null) {
      debugPrint('TreeController: No bulk animation group');
      return;
    }
    final controller = _activeBulkGroup!.controller;
    debugPrint(
      'TreeController bulk animation: '
      'value=${_activeBulkGroup!.value.toStringAsFixed(3)}, '
      'controllerValue=${controller.value.toStringAsFixed(3)}, '
      'status=${controller.status}, '
      'members=${_activeBulkGroup!.members.length}, '
      'pendingRemoval=${_activeBulkGroup!.pendingRemoval.length}',
    );
  }

  /// Whether the given node is currently animating. Forwards to the
  /// AnimationCoordinator's per-key check.
  bool isAnimating(TKey key) => _anim.isAnimating(key);

  /// Gets the animation state for a node, or null if not animating.
  /// Returns the standalone state if present, a synthetic entering state
  /// for operation group members that are expanding, or null for bulk/
  /// collapsing groups.
  AnimationState? getAnimationState(TKey key) => _anim.getAnimationState(key);

  /// Whether the given node is currently exiting (animating out).
  bool isExiting(TKey key) => _anim.isExiting(key);

  /// Gets the estimated full extent for a node.
  /// Returns the cached measured extent if available, otherwise [defaultExtent].
  double getEstimatedExtent(TKey key) =>
      _anim.fullExtentOf(key) ?? defaultExtent;

  /// Gets the current extent for a node, accounting for animation.
  double getCurrentExtent(TKey key) => _anim.getCurrentExtent(key);

  /// Gets the animated extent for a node.
  /// If the node is animating, returns the interpolated extent.
  /// Otherwise returns [fullExtent].
  double getAnimatedExtent(TKey key, double fullExtent) =>
      _anim.getAnimatedExtent(key, fullExtent);

  /// Starts a FLIP slide animation for every visible node whose position in
  /// scroll-space changed between [priorOffsets] (pre-mutation) and
  /// [currentOffsets] (post-mutation). Produce both with
  /// [RenderSliverTree.snapshotVisibleOffsets] — the first **before** the
  /// structural mutation, the second from inside a
  /// [WidgetsBinding.addPostFrameCallback] **after** the mutation's layout
  /// has run.
  ///
  /// A node present in both maps with `priorOffsets[key] != currentOffsets[key]`
  /// receives a new [SlideAnimation] with `startDelta = prior - current`.
  /// A node only in one map is ignored (it was either added or removed and
  /// has its own enter/exit animation for that). A zero delta installs no
  /// entry.
  ///
  /// Composes with an in-flight slide: if a key already has an entry,
  /// its `startDelta` is replaced with `currentDelta_old + (prior - current)`
  /// and `progress` is reset to 0.0. This preserves the currently rendered
  /// position as the new animation's starting point (no visual jump).
  ///
  /// Slide is paint-only: it does **not** fire the structural-change channel,
  /// does **not** touch layout, and is **not** counted in
  /// [hasActiveAnimations]. It fires on the animation-listener channel on
  /// every tick and on completion; see the slide tick handler for ordering.
  ///
  /// Safe to invoke from inside [RenderObject.performLayout]: the slide is
  /// driven by a [Ticker] whose first callback fires on the next vsync (in
  /// `SchedulerPhase.transientCallbacks`). No listeners fire synchronously
  /// from this call, so there is no path that reaches
  /// `markNeedsLayout`/`markNeedsPaint` on a sliver currently being laid
  /// out. The per-entry `currentDelta` is seeded to `startDelta`, so the
  /// paint pass of the same frame reads the pre-mutation position.
  void animateSlideFromOffsets(
    Map<TKey, ({double y, double x})> priorOffsets,
    Map<TKey, ({double y, double x})> currentOffsets, {
    Duration? duration,
    Curve? curve,
    double maxSlideDistance = double.infinity,
  }) {
    // Null timing resolves to the style's reorderSlide spec.
    _slide.animateFromOffsets(
      priorOffsets,
      currentOffsets,
      duration: duration ?? _animationStyle.reorderSlide.duration,
      curve: curve ?? _animationStyle.reorderSlide.curve,
      maxSlideDistance: maxSlideDistance,
      structuralAnimationsDisabled:
          _animationStyle.reorderSlide.duration == Duration.zero,
    );
  }

  /// Internal-use-only: installs a drop-settle glide (the drag proxy's
  /// cancel return / dead-commit-slide fallback).
  ///
  /// Identical to [animateSlideFromOffsets] except the slide-engine
  /// kill switch is computed from the DROP-SETTLE family
  /// ([TreeAnimationStyle.effectiveDropSettle]) instead of
  /// `reorderSlide`, so the glide honors its own family's zero rule.
  /// [duration]/[curve] are the drag session's CAPTURED spec — values
  /// are captured per session, the kill switch reads the live style
  /// (the same split the make-room family uses).
  void animateDropSettleGlide(
    Map<TKey, ({double y, double x})> priorOffsets,
    Map<TKey, ({double y, double x})> currentOffsets, {
    required Duration duration,
    required Curve curve,
  }) {
    _slide.animateFromOffsets(
      priorOffsets,
      currentOffsets,
      duration: duration,
      curve: curve,
      structuralAnimationsDisabled:
          _animationStyle.effectiveDropSettle.duration == Duration.zero,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MAKE-ROOM PREVIEW
  // ══════════════════════════════════════════════════════════════════════════

  /// Debug-only: number of visible-order slots examined by the last
  /// [setReorderPreview] target computation. -1 when the computation has
  /// never run (calls that exit before the target loop leave it
  /// unchanged). Pins the loop's O(visibleNodeCount) contract — the order
  /// buffer is grow-only, so an unbounded loop would silently scan the
  /// stale capacity tail after a high-water mark.
  int debugLastPreviewTargetIterationCount = -1;

  /// Debug-only: number of full target-map computations performed by
  /// [setReorderPreview] (memo misses). Never decremented. Pins the
  /// geometry memo's contract: re-resolving an unchanged slot at pointer
  /// frequency must not recompute the O(visibleNodeCount) target map.
  int debugPreviewInstallCount = 0;

  // Geometry memo for [setReorderPreview]: the target map is a pure
  // function of (draggedNid, gapIndex, lift) over the visible order, so
  // an identical re-send — the per-pointer-event common case while the
  // pointer dwells in one slot — can skip the O(visibleNodeCount) loop
  // and map allocation entirely. `_previewMemoStructureGen` guards the
  // one case geometry can't see (an equal-extent swap inside the shifted
  // span); the validity flag (rather than `_preview.hasActive`) keeps
  // empty-target installs — hovering the dragged block's own slot, the
  // initial state of every drag — memoizable too. Reset as the first
  // line of [clearReorderPreview]; every other preview writer is either
  // a purge path (which bumps the structure generation) or the engine's
  // self-settle (only reachable via a release that started in
  // [clearReorderPreview]).
  bool _previewMemoValid = false;
  int _previewMemoDraggedNid = -1;
  int _previewMemoGapIndex = -1;
  double _previewMemoLift = -1.0;
  int _previewMemoStructureGen = -1;
  bool _previewMemoSnap = false;

  /// Opens (or re-targets) the paint-only make-room preview for a drag of
  /// [draggedKey] hovering [targetKey]: rows at/after the gap slot shift
  /// down by the dragged subtree's visible extent, rows after the vacated
  /// slot shift up, and the offsets are HELD until this is called again
  /// (new slot) or [clearReorderPreview] releases them.
  ///
  /// [gapBelowTarget] selects the slot edge, matching the drop-indicator
  /// rule: `false` = the gap opens above [targetKey]'s row (the `above`
  /// zone); `true` = directly below it (`into`/`below` zones — including
  /// the below-on-expanded-parent first-child resolution, whose slot is
  /// visually the same edge).
  ///
  /// Structure never changes: no structural listeners fire, no sync diff
  /// runs, layout is untouched. The offsets ride the same composed read
  /// path as FLIP slide deltas, so painted positions, painted-truth
  /// snapshots (FLIP baselines — this is what makes the commit handoff
  /// seamless), hit-testing, retention, and overreach all see them
  /// automatically. Snaps instead of animating when the effective
  /// make-room spec (or the resolved per-call duration) is zero.
  ///
  /// The dragged subtree's own rows keep their painted position (the
  /// reorderable widget hides them behind the drag proxy in make-room
  /// mode).
  void setReorderPreview({
    required TKey draggedKey,
    required TKey targetKey,
    required bool gapBelowTarget,
    Duration? duration,
    Curve? curve,
  }) {
    final draggedNid = _nids[draggedKey];
    final targetNid = _nids[targetKey];
    if (draggedNid == null || targetNid == null) {
      clearReorderPreview(animate: false);
      return;
    }
    _ensureVisibleOrder();
    final draggedIndex = _order.indexByNid[draggedNid];
    final targetIndex = _order.indexByNid[targetNid];
    if (draggedIndex < 0 || targetIndex < 0) {
      clearReorderPreview(animate: false);
      return;
    }
    final draggedSize = _order.subtreeSizeOf(draggedNid);
    final draggedEnd = draggedIndex + draggedSize;
    final nids = orderNidsView;
    double lift = 0.0;
    for (int i = draggedIndex; i < draggedEnd; i++) {
      lift += getCurrentExtentNid(nids[i]);
    }
    if (lift <= 0.0) {
      clearReorderPreview(animate: false);
      return;
    }
    final gapIndex = gapBelowTarget ? targetIndex + 1 : targetIndex;

    // Null timing resolves to the style's effective make-room spec. The
    // snap MODE is resolved here, above the memo check, because it is
    // part of the memo key: the engine's retarget path early-outs on
    // identical targets (so dropped re-sends with different
    // duration/curve VALUES are behavior-identical), but the snap branch
    // has no such early-out — an animating→snap re-send with identical
    // geometry forces instant arrival and must not be skipped.
    final resolvedDuration =
        duration ?? _animationStyle.effectiveMakeRoom.duration;
    final resolvedSnap =
        _animationStyle.effectiveMakeRoom.duration == Duration.zero ||
            resolvedDuration == Duration.zero;

    // Geometry memo (see field docs): identical geometry + timing mode
    // already installed — nothing to do. `lift` compares exactly: an
    // unchanged state recomputes the same left-to-right sum bitwise, and
    // any input extent change flows into the sum (or into gapIndex / the
    // structure generation).
    if (_previewMemoValid &&
        draggedNid == _previewMemoDraggedNid &&
        gapIndex == _previewMemoGapIndex &&
        lift == _previewMemoLift &&
        _structureGeneration == _previewMemoStructureGen &&
        resolvedSnap == _previewMemoSnap) {
      return;
    }

    // Per-row shift over the CURRENT visible order (which still contains
    // the dragged rows in place): closing the vacated slot (−lift for
    // rows after the dragged subtree) composes with opening the gap
    // (+lift for rows at/after the slot). Rows on the far side of both
    // cancel to zero; only the span between the old and new positions
    // moves.
    final targets = <int, double>{};
    // Bound the scan by the VISIBLE count, not the buffer's grow-only
    // capacity: [orderNidsView]'s tail beyond `_order.length` holds stale
    // nids from the high-water mark ("only the first N entries are
    // valid"). The `_ensureVisibleOrder()` above already flushed, so the
    // length is current.
    final scanCount = _order.length;
    debugLastPreviewTargetIterationCount = scanCount;
    for (int i = 0; i < scanCount; i++) {
      if (i >= draggedIndex && i < draggedEnd) {
        continue;
      }
      double shift = 0.0;
      if (i >= draggedEnd) {
        shift -= lift;
      }
      if (i >= gapIndex) {
        shift += lift;
      }
      if (shift != 0.0) {
        targets[nids[i]] = shift;
      }
    }
    debugPreviewInstallCount++;
    _preview.setTargetsForNids(
      targets,
      duration: resolvedDuration,
      curve: curve ?? _animationStyle.effectiveMakeRoom.curve,
      snap: resolvedSnap,
    );
    // Written after the install, for every install — including an
    // empty-target one (own-slot hover), which the engine expresses as
    // "no entries" but is still a held, re-skippable state.
    _previewMemoValid = true;
    _previewMemoDraggedNid = draggedNid;
    _previewMemoGapIndex = gapIndex;
    _previewMemoLift = lift;
    _previewMemoStructureGen = _structureGeneration;
    _previewMemoSnap = resolvedSnap;
  }

  /// Ends the make-room preview: animate the shifted rows back
  /// ([animate] true — pointer left every valid slot, or the drag was
  /// cancelled) or drop the offsets instantly ([animate] false — the
  /// commit path, where the staged FLIP baseline has already captured the
  /// shifted painted positions and the mutation's layout takes over).
  void clearReorderPreview({
    required bool animate,
    Duration? duration,
    Curve? curve,
  }) {
    // BEFORE the hasActive early return: a cleared-then-restarted preview
    // must never memo-skip its first re-install, and the empty-target
    // (own-slot) memo state has no engine entries to make hasActive true.
    _previewMemoValid = false;
    if (!_preview.hasActive) {
      return;
    }
    // Null timing resolves to the style's effective make-room spec; a
    // resolved zero snaps (mirrors [setReorderPreview]'s snap rule).
    final resolvedDuration =
        duration ?? _animationStyle.effectiveMakeRoom.duration;
    if (!animate ||
        _animationStyle.effectiveMakeRoom.duration == Duration.zero ||
        resolvedDuration == Duration.zero) {
      _preview.snapClearAll();
    } else {
      _preview.releaseAll(
        duration: resolvedDuration,
        curve: curve ?? _animationStyle.effectiveMakeRoom.curve,
      );
    }
  }

  /// Stores the measured full extent for a node.
  ///
  /// Called by the render object after laying out a child.
  ///
  /// Forwards to [AnimationCoordinator.setFullExtent] which carries the
  /// cross-source coordination logic (op-group member target resolve,
  /// captured-vs-natural target distinction, animation-status check).
  /// Invalidates the scroll prefix sum on extent change.
  void setFullExtent(TKey key, double extent) {
    final oldExtent = _anim.setFullExtent(key, extent);
    if (oldExtent != extent) {
      _scroll.invalidatePrefix();
    }
  }

  /// Gets the index of a node in the visible order, or -1 if not visible.
  int getVisibleIndex(TKey key) {
    _ensureVisibleOrder();
    return _order.indexOf(key);
  }

  /// Gets the parent key for the given node, or null if it is a root.
  TKey? getParent(TKey key) => _parentKeyOfKey(key);

  // ══════════════════════════════════════════════════════════════════════════
  // SCROLL-TO-KEY SUPPORT
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns the sliver-space scroll offset of [key], or null if [key] is
  /// not in the current visible order (e.g., ancestors collapsed, or key
  /// not registered). The offset corresponds to the node's top edge within
  /// the [SliverTree]'s own scroll extent.
  ///
  /// Walks preceding visible nodes and sums their full (non-animated)
  /// extents, preferring measured values from the render pass and falling
  /// back to [extentEstimator] or [defaultExtent] for nodes that have
  /// never been laid out.
  ///
  /// For scrollables that contain other slivers above the tree, add those
  /// slivers' combined extent to the returned value before seeking.
  double? scrollOffsetOf(
    TKey key, {
    double Function(TKey key)? extentEstimator,
  }) => _scroll.scrollOffsetOf(key, extentEstimator: extentEstimator);

  /// Returns the best-known full (non-animated) extent for [key]: the
  /// measured value if the node has ever been laid out, otherwise
  /// [extentEstimator] if supplied, otherwise [defaultExtent]. Matches the
  /// fallback chain used by [scrollOffsetOf].
  double extentOf(TKey key, {double Function(TKey key)? extentEstimator}) =>
      _scroll.extentOf(key, extentEstimator: extentEstimator);

  /// Immediately expands every collapsed ancestor of [key] so that [key]
  /// becomes part of the visible order. Expansion is synchronous (no
  /// animation) so a subsequent [scrollOffsetOf] call sees the updated
  /// structure. Returns the number of ancestors that were expanded.
  int ensureAncestorsExpanded(TKey key) => _scroll.ensureAncestorsExpanded(key);

  /// Animates [scrollController] to reveal [key] in its attached viewport.
  ///
  /// [ancestorExpansion] controls how collapsed ancestors of [key] are
  /// handled:
  /// - [AncestorExpansionMode.none]: ancestors are not expanded. If any
  ///   ancestor of [key] is collapsed, returns false without scrolling.
  /// - [AncestorExpansionMode.immediate] (default): ancestors are expanded
  ///   synchronously (no animation) before the scroll begins. When this
  ///   actually expanded something, the method waits one frame before
  ///   computing the target so the enlarged sliver lays out first —
  ///   otherwise the scroll would clamp against the pre-expansion
  ///   `maxScrollExtent` and stop short of the target row.
  /// - [AncestorExpansionMode.animated]: ancestors animate open while the
  ///   scroll runs concurrently. Each animation tick the scroll target is
  ///   re-derived from the current animated offsets so it stays glued to
  ///   the moving target. A precise jump lands on the settled offset once
  ///   both finish. In this mode the concurrent phase runs for
  ///   `max(duration, expandCollapse.duration)` so both the expansion and the
  ///   scroll have time to complete.
  ///
  /// [alignment] controls placement within the viewport:
  /// 0.0 pins the row's top to the viewport top (default), 0.5 centers,
  /// 1.0 pins the row's bottom to the viewport bottom.
  ///
  /// For nodes that have never been laid out, [extentEstimator] supplies
  /// a fallback height; without it, [defaultExtent] is used. A mismatch
  /// between estimate and actual measurement may cause slight over- or
  /// undershoot — the render pass that includes the target will snap to
  /// the exact offset on the next frame.
  ///
  /// [sliverBaseOffset] is the scroll-space distance from the top of the
  /// scrollable's content to the top of this sliver. It is added to the
  /// computed sliver-local offset. Leave at 0.0 when [SliverTree] is the
  /// first (or only) sliver in the [CustomScrollView].
  ///
  /// Animated-mode scrolls are single-flight: starting one while another
  /// is still in flight cancels the earlier scroll (its future resolves
  /// false) — the newer target wins.
  ///
  /// Returns true if a scroll was issued, false if [key] could not be
  /// resolved, [scrollController] has no attached position, or the scroll
  /// was cancelled (superseded, or the controller was disposed) before
  /// completing.
  Future<bool> animateScrollToKey(
    TKey key, {
    required ScrollController scrollController,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.linear,
    double alignment = 0.0,
    AncestorExpansionMode ancestorExpansion = AncestorExpansionMode.immediate,
    double Function(TKey key)? extentEstimator,
    double sliverBaseOffset = 0.0,
  }) => _scroll.animateScrollToKey(
    key,
    scrollController: scrollController,
    duration: duration,
    curve: curve,
    alignment: alignment,
    ancestorExpansion: ancestorExpansion,
    extentEstimator: extentEstimator,
    sliverBaseOffset: sliverBaseOffset,
  );

  // ══════════════════════════════════════════════════════════════════════════
  // ANIMATION LISTENERS — forwarded to AnimationCoordinator
  // ══════════════════════════════════════════════════════════════════════════

  /// Registers a callback that fires on every animation tick.
  ///
  /// Unlike [addListener], these callbacks fire for pure animation progress
  /// updates (no structural changes). Use this to trigger repaint/relayout
  /// without scheduling garbage collection.
  void addAnimationListener(VoidCallback listener) =>
      _anim.addListener(listener);

  /// Removes a previously registered animation listener.
  void removeAnimationListener(VoidCallback listener) =>
      _anim.removeListener(listener);

  /// Registers a callback that fires when a single node's data changes
  /// without any structural change (e.g. after [updateNode]).
  ///
  /// The callback receives the changed node's key. Use this to rebuild
  /// only the affected row without scanning every mounted child.
  void addNodeDataListener(void Function(TKey key) listener) {
    _nodeDataListeners.add(listener);
  }

  /// Removes a previously registered node-data listener.
  void removeNodeDataListener(void Function(TKey key) listener) {
    _nodeDataListeners.remove(listener);
  }

  /// Fires a per-node data-changed notification, or records the intent
  /// when inside [runBatch]. Unlike [_notifyStructural], callers pass the
  /// affected key so listeners can do targeted work.
  void _notifyNodeDataChanged(TKey key) {
    if (_batchDepth > 0) {
      (_batchDirtyDataNodes ??= <TKey>{}).add(key);
      return;
    }
    _fireNodeDataListeners(key);
  }

  void _fireNodeDataListeners(TKey key) {
    // Snapshot before iteration — listeners may remove themselves.
    final listeners = List<void Function(TKey)>.of(_nodeDataListeners);
    for (final listener in listeners) {
      listener(key);
    }
  }

  /// Registers a callback that fires on structural mutations with an
  /// optional set of affected keys. See [_structuralListeners] for the
  /// semantics of the argument.
  ///
  /// This is a finer-grained channel than [addListener] ([ChangeNotifier]).
  /// External callers that only need to know "something changed" can keep
  /// using [addListener] — [notifyListeners] still fires from
  /// [_notifyStructural]. Listeners that can do targeted work (e.g. the
  /// sliver tree element refreshing only specific mounted rows) should
  /// prefer this channel.
  void addStructuralListener(void Function(Set<TKey>? affectedKeys) listener) {
    _structuralListeners.add(listener);
  }

  /// Removes a previously registered structural listener.
  void removeStructuralListener(
    void Function(Set<TKey>? affectedKeys) listener,
  ) {
    _structuralListeners.remove(listener);
  }

  void _fireStructuralListeners(Set<TKey>? affectedKeys) {
    // Snapshot before iteration so a listener that synchronously mutates
    // the controller (triggering a reentrant notify) does not corrupt this
    // walk. Same pattern as [_fireNodeDataListeners].
    final listeners = List<void Function(Set<TKey>?)>.of(_structuralListeners);
    for (final listener in listeners) {
      listener(affectedKeys);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BATCHING
  // ══════════════════════════════════════════════════════════════════════════

  /// Runs [body] with structural notifications coalesced into a single
  /// [notifyListeners] call fired after [body] returns.
  ///
  /// Any number of mutations inside [body] — [insertRoot], [insert],
  /// [remove], [expand], [collapse], [updateNode], [moveNode], etc. — fire
  /// at most one structural notification when the outermost [runBatch]
  /// exits. Nested [runBatch] calls coalesce into the outermost one.
  ///
  /// Per-channel batching contract:
  ///   - **Structural** ([addStructuralListener] / [notifyListeners]):
  ///     deferred. Fires once on batch exit with the union of affected
  ///     keys.
  ///   - **Node-data** ([addNodeDataListener]): deferred. Fires once per
  ///     dirty key on batch exit, after structural. A key that was both
  ///     structurally and data-mutated triggers both notifications.
  ///   - **Animation tick** ([addAnimationListener]): NOT deferred. These
  ///     fire on the next animation vsync frame (their natural schedule)
  ///     and are unaffected by batching either way.
  ///
  /// The notification fires even if [body] throws, so listeners always see
  /// the post-batch state. Exceptions propagate after the notification.
  T runBatch<T>(T Function() body) {
    _batchDepth++;
    try {
      return body();
    } finally {
      _batchDepth--;
      if (_batchDepth == 0) {
        // Flush any deferred visible-order rebuild BEFORE notifications
        // fire — listeners reading visibleNodes/orderNidsView in their
        // callback must see the post-batch state. Cheap when no
        // mutation flagged dirtiness (single bool check).
        _ensureVisibleOrder();
        final didStructural = _batchDidRequestStructural;
        final dirtyData = _batchDirtyDataNodes;
        final structuralAffected = _batchAffectedStructuralUnknown
            ? null
            : _batchAffectedStructuralKeys;
        _batchDidRequestStructural = false;
        _batchDirtyDataNodes = null;
        _batchAffectedStructuralKeys = null;
        _batchAffectedStructuralUnknown = false;
        // Fire structural first: a structural notify causes the element to
        // mark itself for a full refresh, which subsumes any data-only
        // refresh for the same keys. Firing data first would queue a
        // targeted refresh that the full refresh then redundantly repeats.
        if (didStructural) {
          _fireStructuralListeners(structuralAffected);
          notifyListeners();
        }
        if (dirtyData != null && dirtyData.isNotEmpty) {
          for (final key in dirtyData) {
            _fireNodeDataListeners(key);
          }
        }
      }
    }
  }

  /// Fires a structural notification, or records the intent when inside
  /// [runBatch]. All in-controller mutation paths call this instead of
  /// [notifyListeners] directly so batching works uniformly.
  ///
  /// [affectedKeys] narrows the refresh scope for listeners subscribed via
  /// [addStructuralListener]:
  ///   - `null` — scope unknown; listeners should do a full refresh.
  ///   - empty set — structural change occurred but no mounted row's
  ///     builder output changed; listeners need only relayout/GC.
  ///   - non-empty set — exactly these keys need refresh.
  ///
  /// Inside [runBatch], `null` is a poison pill: any in-batch call with
  /// `null` forces the coalesced exit notification to use `null`, even if
  /// other in-batch calls carried specific sets.
  ///
  /// External observers via [addListener] (ChangeNotifier) always see a
  /// single `notifyListeners()` fire regardless of [affectedKeys].
  void _notifyStructural({Set<TKey>? affectedKeys}) {
    if (_batchDepth > 0) {
      _batchDidRequestStructural = true;
      if (affectedKeys == null) {
        _batchAffectedStructuralUnknown = true;
        _batchAffectedStructuralKeys = null;
      } else if (!_batchAffectedStructuralUnknown) {
        (_batchAffectedStructuralKeys ??= <TKey>{}).addAll(affectedKeys);
      }
      return;
    }
    _fireStructuralListeners(affectedKeys);
    notifyListeners();
  }

  /// Binary-searches [siblings] for the sorted insertion index of [node]
  /// using [comparator]. Skips pending-deletion keys.
  ///
  /// Fast path (no pending deletions): a plain binary search over [siblings]
  /// with no allocation. Slow path: a linear scan that skips pending-deletion
  /// entries, still without allocating an intermediate filtered list.
  int _sortedIndex(List<TKey> siblings, TreeNode<TKey, TData> node) {
    assert(comparator != null);
    final cmp = comparator!;
    if (_anim.pendingDeletionCount == 0) {
      int lo = 0, hi = siblings.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        final midNode = _dataOf(siblings[mid])!;
        if (cmp(midNode, node) <= 0) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo;
    }
    // Pending-deletion keys are intermixed, so a binary search would need a
    // rank-mapping structure to locate live entries. A single linear scan is
    // allocation-free and competitive for typical sibling counts.
    for (int i = 0; i < siblings.length; i++) {
      final k = siblings[i];
      if (_isPendingDeletion(k)) continue;
      final other = _dataOf(k)!;
      if (cmp(other, node) > 0) return i;
    }
    return siblings.length;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TREE MUTATIONS
  // ══════════════════════════════════════════════════════════════════════════

  /// Initializes the tree with the given root nodes.
  ///
  /// This clears any existing state.
  ///
  /// Throws an [ArgumentError] if [roots] contains duplicate keys.
  void setRoots(List<TreeNode<TKey, TData>> roots) {
    final seen = <TKey>{};
    for (final node in roots) {
      if (!seen.add(node.key)) {
        throw ArgumentError("Duplicate key ${node.key} in setRoots");
      }
    }
    _clear();
    final sorted = comparator != null
        ? (List.of(roots)..sort(comparator))
        : roots;
    for (final node in sorted) {
      _adoptKey(node.key);
      _store.setData(node.key, node);
      _setParentKey(node.key, null);
      _setChildList(node.key, []);
      _setDepthKey(node.key, 0);
      _setExpandedKey(node.key, false);
      _roots.add(node.key);
      _order.addKey(node.key);
    }
    _rebuildVisibleIndex();
    _structureGeneration++;
    // Bulk wholesale replacement: _clear() purged every prior key. Callers
    // frequently reuse the same TKey identities, and any retained mounted
    // Element's builder output may differ. Keep the conservative full
    // refresh rather than try to enumerate every retained key.
    _notifyStructural();
  }

  /// Adds a new root node to the tree.
  ///
  /// If [animate] is true, the node will animate in.
  /// If the node is currently pending deletion (animating out from a previous
  /// remove), the deletion is cancelled and the node animates back in.
  ///
  /// [index] is the position among **live** root siblings — exiting
  /// (pending-deletion) roots are skipped, matching [liveRootKeys] /
  /// [getIndexInParent] and the input space of [reorderRoots].
  void insertRoot(
    TreeNode<TKey, TData> node, {
    int? index,
    bool animate = true,
    bool preservePendingSubtreeState = false,
  }) {
    if (_animationStyle.effectiveEnterExit.duration == Duration.zero) {
      animate = false;
    }
    // See [insert] for the rationale: flush any deferred visible-order
    // rebuild from a prior in-batch mutator so the positional reads
    // below (`_calculateRootInsertIndex`, `_order.length`) operate on
    // fresh state instead of corrupting the buffer.
    _ensureVisibleOrder();
    // If the node is pending deletion, cancel the deletion
    if (_isPendingDeletion(node.key)) {
      // If the node was pending deletion under a non-null parent, detach
      // it and re-attach as a root. Without this relocation, cancelling
      // the deletion would resurrect it under its old parent, silently
      // ignoring the insertRoot() contract.
      final oldParent = _parentKeyOfKey(node.key);
      if (oldParent != null) {
        _childListOf(oldParent)?.remove(node.key);
        _setParentKey(node.key, null);
        // Explicit index is live-space; the comparator path already
        // returns a full-space position.
        final effectiveIndex = index != null
            ? _liveIndexToFullInsertIndex(_roots, index)
            : (comparator != null ? _sortedIndex(_roots, node) : null);
        if (effectiveIndex != null && effectiveIndex < _roots.length) {
          _roots.insert(effectiveIndex, node.key);
        } else {
          _roots.add(node.key);
        }
        _refreshSubtreeDepths(node.key, 0);
      } else if (index != null) {
        // Already a root — honor an explicitly requested index by
        // relocating within _roots. The index is live-space; convert
        // after the removal so the conversion sees the list the insert
        // will apply to.
        final current = _roots.indexOf(node.key);
        if (current != -1) {
          _roots.removeAt(current);
          final fullIndex = _liveIndexToFullInsertIndex(_roots, index);
          _roots.insert(fullIndex, node.key);
        }
      }
      _cancelDeletion(
        node.key,
        animate: animate,
        preserveSubtreeState: preservePendingSubtreeState,
      );
      _adoptKey(node.key);
      _store.setData(node.key, node);
      // Fire the node-data channel so subscribers via
      // [addNodeDataListener] see the data update. The structural
      // notification below covers a different channel (full refresh)
      // that some callers don't subscribe to.
      _notifyNodeDataChanged(node.key);
      if (preservePendingSubtreeState) {
        _markVisibleOrderDirty();
        // Cancelling a pending deletion restores the node (and possibly
        // descendants) to the tree. Downstream builder-output effects span
        // the restored subtree plus any ancestor whose hasChildren state
        // flips; enumerating all of that precisely is complex, so fall back
        // to a full refresh.
        _notifyStructural();
        return;
      }
      // Reset expansion state so a subsequent expand() works cleanly.
      // Descendants that were mid-exit are left alone by _cancelDeletion
      // and continue animating out under the restored parent via
      // _rebuildVisibleOrder's "collapsed with active animations" branch.
      // Yanking them here would visually jump following rows upward by
      // the descendant's current extent in a single frame.
      _setExpandedKey(node.key, false);
      _markVisibleOrderDirty();
      _notifyStructural();
      return;
    }

    // Node is already present (e.g. restored by an ancestor's
    // _cancelDeletion, or a live re-insert). Update the data and — if the
    // caller requested a different location — relocate it to honor the
    // insertRoot(index:) contract instead of silently dropping the index.
    if (_hasKey(node.key)) {
      _adoptKey(node.key);
      _store.setData(node.key, node);
      final currentParent = _parentKeyOfKey(node.key);
      if (currentParent != null) {
        // Fire the node-data channel BEFORE delegating. moveNode's
        // structural notification is targeted — on a depth-preserving
        // move its affectedKeys omits the moved key itself — so this is
        // the only refresh path for the overwritten payload.
        _notifyNodeDataChanged(node.key);
        // Different parent — delegate to moveNode. Forward the caller's
        // `animate` so insertRoot(animate: false) doesn't silently slide
        // (now that moveNode itself defaults to animate: true).
        moveNode(node.key, null, index: index, animate: animate);
        return;
      }
      final currentRootIndex = _roots.indexOf(node.key);
      // Explicit index is live-space (compare live-vs-live and convert at
      // the insert); the comparator path stays full-space end to end.
      final int? sortedDesired = index == null && comparator != null
          ? _sortedIndex(_roots, node)
          : null;
      final bool wantsRelocate;
      if (index != null) {
        final currentLiveIndex = getIndexInParent(node.key);
        final liveCount = _liveCountOf(_roots);
        wantsRelocate =
            index != currentLiveIndex &&
            // Appending is a no-op if already live-last.
            !(currentLiveIndex == liveCount - 1 && index >= liveCount);
      } else if (sortedDesired != null) {
        wantsRelocate =
            sortedDesired != currentRootIndex &&
            // Appending is a no-op if already at the end.
            !(currentRootIndex == _roots.length - 1 &&
                sortedDesired >= _roots.length);
      } else {
        wantsRelocate = false;
      }
      if (wantsRelocate) {
        _roots.removeAt(currentRootIndex);
        final insertAt = index != null
            ? _liveIndexToFullInsertIndex(_roots, index)
            : sortedDesired!.clamp(0, _roots.length);
        _roots.insert(insertAt, node.key);
        _markVisibleOrderDirty();
        // Relocation changes row positions (and the payload was
        // overwritten) — structural refresh, which subsumes the data
        // channel's row refresh, so the data channel does not also fire.
        _notifyStructural(affectedKeys: <TKey>{node.key});
      } else {
        // Data-only update — fire the node-data channel only, matching
        // updateNode's contract. Firing a structural notification too
        // would refresh the same row twice.
        _notifyNodeDataChanged(node.key);
      }
      return;
    }

    // Add to data structures
    _adoptKey(node.key);
    _store.setData(node.key, node);
    _setParentKey(node.key, null);
    _setChildList(node.key, []);
    _setDepthKey(node.key, 0);
    _setExpandedKey(node.key, false);

    // Add to roots list. Explicit index is live-space; the comparator
    // path already returns a full-space position.
    final effectiveIndex = index != null
        ? _liveIndexToFullInsertIndex(_roots, index)
        : (comparator != null ? _sortedIndex(_roots, node) : null);
    // Compute visible insert position BEFORE modifying _roots, since
    // _calculateRootInsertIndex reads _roots[effectiveIndex].
    final visibleInsertIndex =
        effectiveIndex != null && effectiveIndex < _roots.length
        ? _calculateRootInsertIndex(effectiveIndex)
        : _order.length;
    if (effectiveIndex != null && effectiveIndex < _roots.length) {
      _roots.insert(effectiveIndex, node.key);
    } else {
      _roots.add(node.key);
    }

    // Add to visible order (root nodes are always visible)
    final insertIndex = visibleInsertIndex;
    _order.insertKey(insertIndex, node.key);
    _updateIndicesFrom(insertIndex);
    _structureGeneration++;

    if (animate) {
      _startStandaloneEnterAnimation(node.key);
    }

    // Fresh root: the new key enters visible order via createChild, not a
    // refresh. Roots have no parent whose hasChildren could flip, and no
    // sibling's builder output depends on the new key. Empty set.
    _notifyStructural(affectedKeys: const {});
  }

  /// Calculates the visible order index for inserting a root at the given root index.
  int _calculateRootInsertIndex(int rootIndex) {
    if (rootIndex == 0) return 0;
    if (rootIndex >= _roots.length) return _order.length;

    // Find the root at the given index and return its visible index
    final rootId = _roots[rootIndex];
    final idx = _order.indexOf(rootId);
    return idx == VisibleOrderBuffer.kNotVisible ? _order.length : idx;
  }

  /// Full-list insertion position such that, after insertion, the node sits
  /// at [liveIndex] among live (non-pending-deletion) entries.
  ///
  /// This is the write-boundary conversion for the package's single public
  /// index space: every `index` parameter on [insertRoot], [insert], and
  /// [moveNode] is live-space (matching [getIndexInParent],
  /// [getLiveChildren], [liveRootKeys], and the reorder APIs), while the
  /// underlying sibling lists still contain pending-deletion (exiting)
  /// entries.
  ///
  /// Returns the full-list index of the live entry currently at live
  /// position [liveIndex] — the insert lands directly above that live
  /// sibling, so intervening exiting rows stay above the new node (matching
  /// drop-indicator semantics) — or `fullList.length` when [liveIndex] is
  /// at or past the live count. O(1) when no pending deletions exist;
  /// O(list) otherwise.
  int _liveIndexToFullInsertIndex(List<TKey> fullList, int liveIndex) {
    if (_anim.pendingDeletionCount == 0) {
      return liveIndex.clamp(0, fullList.length);
    }
    if (liveIndex < 0) {
      liveIndex = 0;
    }
    int live = 0;
    for (int i = 0; i < fullList.length; i++) {
      if (_isPendingDeletion(fullList[i])) {
        continue;
      }
      if (live == liveIndex) {
        return i;
      }
      live++;
    }
    return fullList.length;
  }

  /// Number of live (non-pending-deletion) entries in [fullList]. O(1)
  /// when no pending deletions exist anywhere; O(list) otherwise.
  int _liveCountOf(List<TKey> fullList) {
    if (_anim.pendingDeletionCount == 0) {
      return fullList.length;
    }
    int count = 0;
    for (final k in fullList) {
      if (!_isPendingDeletion(k)) {
        count++;
      }
    }
    return count;
  }

  /// Fast-path equality check for [setChildren]. Returns true iff the
  /// new list exactly matches the existing child list — same keys in
  /// the same order, same data values, and no pending-deletion children
  /// (which would otherwise force the slow path's resurrection logic).
  ///
  /// Used to short-circuit no-op `setChildren` calls so reactive sync
  /// code doesn't destroy in-flight animation state on identical input.
  bool _isExactKeyAndDataMatch(
    List<TKey> oldKeys,
    List<TreeNode<TKey, TData>> newNodes,
  ) {
    if (oldKeys.length != newNodes.length) return false;
    for (int i = 0; i < oldKeys.length; i++) {
      final oldKey = oldKeys[i];
      final newNode = newNodes[i];
      if (oldKey != newNode.key) return false;
      // Conservative: any pending-deletion child forces the slow path
      // so the existing purge-and-resurrect behavior is preserved.
      if (_isPendingDeletion(oldKey)) return false;
      final oldData = _dataOf(oldKey)?.data;
      if (oldData != newNode.data) return false;
    }
    return true;
  }

  /// Adds children to a node.
  ///
  /// The children are added but not visible until the parent is expanded.
  /// If the parent already has children, the old children and their
  /// descendants are purged from all data structures first.
  ///
  /// Throws a [StateError] if [parentKey] is pending deletion (animating
  /// out), which would orphan the new children when the parent is purged.
  ///
  /// Throws an [ArgumentError] if [children] contains duplicate keys, if
  /// any child key equals [parentKey], or if any child key already exists
  /// under a *different* parent — use [moveNode] or [remove] for that
  /// case rather than re-parenting by side effect.
  void setChildren(TKey parentKey, List<TreeNode<TKey, TData>> children) {
    assert(_hasKey(parentKey), 'Parent node $parentKey not found');
    // Runtime check (not just an assert) so release builds also reject
    // this rather than silently corrupting state: children set under a
    // mid-exit parent survive the parent's purge with dangling parent
    // nids and leak their registry entries. Mirrors moveNode's policy.
    if (_isPendingDeletion(parentKey)) {
      throw StateError(
        "Cannot setChildren on $parentKey while it is animating out "
        "(pending deletion). The parent will be purged when its exit "
        "animation completes, leaving the new children orphaned.",
      );
    }
    final seen = <TKey>{};
    for (final child in children) {
      if (!seen.add(child.key)) {
        throw ArgumentError(
          "Duplicate key ${child.key} in setChildren($parentKey)",
        );
      }
      if (child.key == parentKey) {
        throw ArgumentError(
          "setChildren($parentKey): child key ${child.key} equals parentKey "
          "(a node cannot be its own child)",
        );
      }
      // Reject keys that already exist under a different parent — silently
      // overwriting _childListOf(child.key) = [] below would orphan the existing
      // subtree and leave a stale reference in the old parent's child list.
      // Accept when the key is already a child of this same parent (no-op
      // reparent — handled by the purge-old-children step).
      if (_hasKey(child.key) && _parentKeyOfKey(child.key) != parentKey) {
        throw ArgumentError(
          "setChildren($parentKey): key ${child.key} already exists under "
          "parent ${_parentKeyOfKey(child.key)}. Use moveNode() or remove() first.",
        );
      }
    }

    // Fast path: if the new list exactly matches the existing child
    // list — same keys in order, same data values, no pending-deletion
    // children — this is a structural no-op. Without this short-circuit,
    // the purge-and-re-adopt loop below destroys any in-flight animation
    // state on these children (the purge calls _purgeNodeData which
    // clears standalone/op-group/bulk membership) for zero visual change.
    // Reactive sync code that re-sends an identical child list (e.g.
    // setState-driven rebuild) would visibly reset mid-flight expand
    // animations without this guard. Pending-deletion children force the
    // slow path so the existing purge-resurrects-and-overwrites behavior
    // is preserved unchanged.
    final oldChildren = _childListOf(parentKey);
    if (oldChildren != null && _isExactKeyAndDataMatch(oldChildren, children)) {
      return;
    }

    // Purge old children and their descendants before overwriting.
    if (oldChildren != null && oldChildren.isNotEmpty) {
      final allOldKeys = <TKey>[];
      for (final oldChildKey in oldChildren) {
        allOldKeys.add(oldChildKey);
        _getDescendantsInto(oldChildKey, allOldKeys);
      }

      // Check visibility and contiguity BEFORE purging (purge clears the index)
      int minIdx = _order.length;
      int maxIdx = -1;
      int visibleCount = 0;
      for (final key in allOldKeys) {
        final idx = _order.indexOf(key);
        if (idx != VisibleOrderBuffer.kNotVisible) {
          visibleCount++;
          if (idx < minIdx) minIdx = idx;
          if (idx > maxIdx) maxIdx = idx;
        }
      }

      // Decrement the parent's visible-subtree-size cache by the
      // count of visible old descendants BEFORE _purgeNodeData
      // releases their nids. Mirrors the fix in _removeNodesImmediate
      // and _finalizeAnimation: the deferred order-buffer compaction
      // below cannot fire useful visibility-loss callbacks once the
      // released nids' parent chains are cleared.
      if (visibleCount > 0) {
        final parentNid = _nids[parentKey];
        if (parentNid != null) {
          _order.bumpFromSelf(parentNid, -visibleCount);
        }
      }

      final oldKeySet = allOldKeys.toSet();
      for (final key in allOldKeys) {
        _purgeNodeData(key);
      }

      if (visibleCount > 0) {
        _order.runWithSubtreeSizeUpdatesSuppressed(() {
          if (maxIdx - minIdx + 1 == visibleCount) {
            // Contiguous removal
            _order.removeRange(minIdx, maxIdx + 1);
            _updateIndicesAfterRemove(minIdx);
          } else {
            // Non-contiguous removal
            _order.removeWhereKeyIn(oldKeySet);
            _rebuildVisibleIndex();
          }
        });
        _structureGeneration++;
      }
    }

    final parentDepth = _depthOfKey(parentKey);
    final childIds = <TKey>[];
    final sorted = comparator != null
        ? (List.of(children)..sort(comparator))
        : children;

    for (final child in sorted) {
      _adoptKey(child.key);
      _store.setData(child.key, child);
      _setParentKey(child.key, parentKey);
      _setChildList(child.key, []);
      _setDepthKey(child.key, parentDepth + 1);
      _setExpandedKey(child.key, false);
      childIds.add(child.key);
    }

    _setChildList(parentKey, childIds);

    // If parent is expanded and visible, insert new children into the
    // visible order so they render immediately.
    if (_isExpandedKey(parentKey) && childIds.isNotEmpty) {
      final parentIdx = _order.indexOf(parentKey);
      if (parentIdx != VisibleOrderBuffer.kNotVisible) {
        final insertIdx = parentIdx + 1;
        _order.insertAllKeys(insertIdx, childIds);
        _updateIndicesFrom(insertIdx);
        _structureGeneration++;
      }
    }

    // Bulk child replacement: old children (and their subtrees) were purged,
    // new children registered. Any retained row under [parentKey] may have
    // its builder output differ — fall back to a full refresh.
    _notifyStructural();
  }

  /// Inserts a new node as a child of the given parent.
  ///
  /// If [animate] is true, the node will animate in.
  ///
  /// [index] is the position among **live** siblings — exiting
  /// (pending-deletion) siblings are skipped, matching [getLiveChildren] /
  /// [getIndexInParent] and the input space of [reorderChildren].
  ///
  /// Throws a [StateError] if [parentKey] is pending deletion (animating
  /// out): the parent will be purged when its exit animation completes,
  /// which would leave the new child orphaned.
  void insert({
    required TKey parentKey,
    required TreeNode<TKey, TData> node,
    int? index,
    bool animate = true,
    bool preservePendingSubtreeState = false,
  }) {
    if (_animationStyle.effectiveEnterExit.duration == Duration.zero) {
      animate = false;
    }
    assert(_hasKey(parentKey), "Parent node $parentKey not found");
    // Flush any pending visible-order rebuild from a prior in-batch mutator
    // (moveNode, reorderRoots, reorderChildren, cancelDeletion, …). Without
    // this, the `_order.indexOf(parentKey)` / `_order.subtreeSizeOf(parentNid)`
    // reads further down would return stale values and yield an insertIndex
    // past `_order.length`, crashing `VisibleOrderBuffer.insertNid` with a
    // RangeError on its setRange shift. Must run BEFORE the mutations below
    // (`_adoptKey`, `siblings.add`, etc.) so the rebuild sees pre-mutation
    // child lists and doesn't try to incorporate the new node twice.
    _ensureVisibleOrder();
    // Runtime check (not just an assert) so release builds also reject
    // this rather than silently corrupting state: a child inserted under
    // a mid-exit parent survives the parent's purge with a dangling
    // parent nid and leaks its registry entry. Mirrors moveNode's policy.
    if (_isPendingDeletion(parentKey)) {
      throw StateError(
        "Cannot insert under $parentKey while it is animating out "
        "(pending deletion). The parent will be purged when its exit "
        "animation completes, leaving the new child orphaned.",
      );
    }
    // If the node is pending deletion, cancel the deletion
    if (_isPendingDeletion(node.key)) {
      // If the pending-deletion node lives under a different parent (or is
      // a root), move it to [parentKey] before cancelling the deletion.
      // Without this relocation, cancelDeletion would resurrect the node
      // under its old parent, silently ignoring the parentKey/index args.
      final oldParent = _parentKeyOfKey(node.key);
      if (oldParent != parentKey) {
        if (oldParent != null) {
          _childListOf(oldParent)?.remove(node.key);
        } else {
          _roots.remove(node.key);
        }
        _setParentKey(node.key, parentKey);
        final siblings = _childListOrCreate(parentKey);
        // Explicit index is live-space; the comparator path already
        // returns a full-space position.
        final effectiveIndex = index != null
            ? _liveIndexToFullInsertIndex(siblings, index)
            : (comparator != null ? _sortedIndex(siblings, node) : null);
        if (effectiveIndex != null && effectiveIndex < siblings.length) {
          siblings.insert(effectiveIndex, node.key);
        } else {
          siblings.add(node.key);
        }
        final parentDepth = _depthOfKey(parentKey);
        _refreshSubtreeDepths(node.key, parentDepth + 1);
      } else if (index != null) {
        // Same parent — honor an explicitly requested index by relocating
        // within the sibling list. The index is live-space; convert after
        // the removal so the conversion sees the list the insert will
        // apply to.
        final siblings = _childListOrCreate(parentKey);
        final current = siblings.indexOf(node.key);
        if (current != -1) {
          siblings.removeAt(current);
          final fullIndex = _liveIndexToFullInsertIndex(siblings, index);
          siblings.insert(fullIndex, node.key);
        }
      }
      _cancelDeletion(
        node.key,
        animate: animate,
        preserveSubtreeState: preservePendingSubtreeState,
      );
      _adoptKey(node.key);
      _store.setData(node.key, node);
      // Same as insertRoot's matching branch — fire the node-data channel
      // so listeners subscribed via [addNodeDataListener] see the data
      // update.
      _notifyNodeDataChanged(node.key);
      if (preservePendingSubtreeState) {
        _markVisibleOrderDirty();
        // See insertRoot's matching branch: cancelling a pending deletion
        // may restore a subtree and flip ancestor hasChildren state — fall
        // back to a full refresh.
        _notifyStructural();
        return;
      }
      // Reset expansion state so a subsequent expand() works cleanly.
      // Descendants that were mid-exit are left alone by _cancelDeletion
      // and continue animating out under the restored parent via
      // _rebuildVisibleOrder's "collapsed with active animations" branch.
      // Yanking them here would visually jump following rows upward by
      // the descendant's current extent in a single frame.
      _setExpandedKey(node.key, false);
      _markVisibleOrderDirty();
      _notifyStructural();
      return;
    }
    // Node is already present (e.g. restored by an ancestor's
    // _cancelDeletion, or a live re-insert). Update the data and — if the
    // caller requested a different location — relocate it to honor the
    // insert(parentKey:, index:) contract instead of silently dropping it.
    if (_hasKey(node.key)) {
      _adoptKey(node.key);
      _store.setData(node.key, node);
      final currentParent = _parentKeyOfKey(node.key);
      if (currentParent != parentKey) {
        // Fire the node-data channel BEFORE delegating. moveNode's
        // structural notification is targeted — on a depth-preserving
        // move its affectedKeys omits the moved key itself — so this is
        // the only refresh path for the overwritten payload.
        _notifyNodeDataChanged(node.key);
        // Different parent — delegate to moveNode. Forward the caller's
        // `animate` so insert(animate: false) doesn't silently slide
        // (now that moveNode itself defaults to animate: true).
        moveNode(node.key, parentKey, index: index, animate: animate);
        return;
      }
      final siblings = _childListOrCreate(parentKey);
      final currentIndex = siblings.indexOf(node.key);
      // Explicit index is live-space (compare live-vs-live and convert at
      // the insert); the comparator path stays full-space end to end.
      final int? sortedDesired = index == null && comparator != null
          ? _sortedIndex(siblings, node)
          : null;
      final bool wantsRelocate;
      if (index != null) {
        final currentLiveIndex = getIndexInParent(node.key);
        final liveCount = _liveCountOf(siblings);
        wantsRelocate =
            index != currentLiveIndex &&
            // Appending is a no-op if already live-last.
            !(currentLiveIndex == liveCount - 1 && index >= liveCount);
      } else if (sortedDesired != null) {
        wantsRelocate =
            sortedDesired != currentIndex &&
            !(currentIndex == siblings.length - 1 &&
                sortedDesired >= siblings.length);
      } else {
        wantsRelocate = false;
      }
      if (wantsRelocate) {
        siblings.removeAt(currentIndex);
        final insertAt = index != null
            ? _liveIndexToFullInsertIndex(siblings, index)
            : sortedDesired!.clamp(0, siblings.length);
        siblings.insert(insertAt, node.key);
        _markVisibleOrderDirty();
        // Relocation changes row positions (and the payload was
        // overwritten) — structural refresh, which subsumes the data
        // channel's row refresh, so the data channel does not also fire.
        _notifyStructural(affectedKeys: <TKey>{node.key});
      } else {
        // Data-only update — fire the node-data channel only, matching
        // updateNode's contract. Firing a structural notification too
        // would refresh the same row twice.
        _notifyNodeDataChanged(node.key);
      }
      return;
    }
    final parentDepth = _depthOfKey(parentKey);
    // Add to data structures
    _adoptKey(node.key);
    _store.setData(node.key, node);
    _setParentKey(node.key, parentKey);
    _setChildList(node.key, []);
    _setDepthKey(node.key, parentDepth + 1);
    _setExpandedKey(node.key, false);
    // Add to parent's children. Explicit index is live-space; the
    // comparator path already returns a full-space position.
    final siblings = _childListOrCreate(parentKey);
    final effectiveIndex = index != null
        ? _liveIndexToFullInsertIndex(siblings, index)
        : (comparator != null ? _sortedIndex(siblings, node) : null);
    if (effectiveIndex != null && effectiveIndex < siblings.length) {
      siblings.insert(effectiveIndex, node.key);
    } else {
      siblings.add(node.key);
    }
    // If parent is expanded, add to visible order
    if (_isExpandedKey(parentKey)) {
      final parentVisibleIndex = _order.indexOf(parentKey);
      if (parentVisibleIndex != VisibleOrderBuffer.kNotVisible) {
        // Fast path: the visible insertion index equals the parent's
        // visible index plus every prior sibling's visible-subtree
        // contribution. Cache lookups are O(1) per sibling, so the
        // whole computation is O(prior-sibling-count) — one array
        // read per sibling, no nested descendant walks.
        int insertIndex;
        if (effectiveIndex != null) {
          insertIndex = parentVisibleIndex + 1;
          final limit = effectiveIndex < siblings.length - 1
              ? effectiveIndex
              : siblings.length - 1;
          for (int i = 0; i < limit; i++) {
            final siblingNid = _nids[siblings[i]];
            if (siblingNid != null) {
              insertIndex += _order.subtreeSizeOf(siblingNid);
            }
          }
        } else {
          // Append after last visible descendant of parent. Parent is
          // visible (checked above) so its cached subtree size counts
          // itself + all currently-visible descendants; subtracting
          // 1 for the parent itself and adding 1 for "position after"
          // yields parentVisibleIndex + subtreeSize directly.
          final parentNid = _nids[parentKey]!;
          insertIndex = parentVisibleIndex + _order.subtreeSizeOf(parentNid);
        }
        _order.insertKey(insertIndex, node.key);
        _updateIndicesFrom(insertIndex);
        _structureGeneration++;
        if (animate) {
          _startStandaloneEnterAnimation(node.key);
        }
      }
    }
    // The new key enters via createChild. The only retained row whose
    // builder output can change is the parent: its child count grew (and
    // possibly its hasChildren flipped), both reachable from nodeBuilder
    // via TreeItemView.
    _notifyStructural(affectedKeys: <TKey>{parentKey});
  }

  /// Removes a node and all its descendants from the tree.
  ///
  /// If [animate] is true, the nodes will animate out.
  void remove({required TKey key, bool animate = true}) {
    if (_animationStyle.effectiveEnterExit.duration == Duration.zero) {
      animate = false;
    }
    if (!_hasKey(key)) {
      return;
    }
    final descendants = _getDescendants(key);
    final nodesToRemove = [key, ...descendants];
    // Capture the parent BEFORE mutation; _removeNodesImmediate purges the
    // node and releases its nid, after which _parentKeyOfKey returns null.
    final parentKey = _parentKeyOfKey(key);
    final affected = <TKey>{};
    if (animate && _order.contains(key)) {
      // Mark nodes as pending deletion so _finalizeAnimation knows to
      // fully remove them (vs just hiding due to parent collapse)
      for (final nodeId in nodesToRemove) {
        _markPendingDeletion(nodeId);
      }
      // Mark all visible nodes as exiting
      for (final nodeId in nodesToRemove) {
        if (_order.contains(nodeId)) {
          _startStandaloneExitAnimation(nodeId);
        }
      }
      // Animated path: the parent's child list is not mutated until exit
      // animations complete; the raw-count refresh fires from the
      // standalone-tick / group-dismissed sites at purge time. But the
      // parent's LIVE child count changed right here: pending-deletion
      // marking is the moment liveChildCount readers go stale, so the
      // parent row must refresh now as well.
      if (parentKey != null) {
        affected.add(parentKey);
      }
    } else {
      _removeNodesImmediate(nodesToRemove);
      _structureGeneration++;
      // Immediate path: the parent's child-list length changed (and its
      // hasChildren may have flipped); its builder may render the count.
      if (parentKey != null) {
        affected.add(parentKey);
      }
    }
    _notifyStructural(affectedKeys: affected);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RETAINED-NODE UPDATE, REORDER, AND MOVE
  // ══════════════════════════════════════════════════════════════════════════

  /// Updates the data payload for an existing node without structural changes.
  ///
  /// Preserves the node's position, expansion state, and animation state.
  /// Notifies listeners so that mounted widgets rebuild with the new data.
  void updateNode(TreeNode<TKey, TData> node) {
    assert(_hasKey(node.key), 'Node ${node.key} not found');
    _adoptKey(node.key);
    _store.setData(node.key, node);
    // Data-only change: no structural mutation, no visible order shift,
    // no expansion/hasChildren change. Fire the targeted data channel
    // so the element rebuilds only this row instead of sweeping every
    // mounted child.
    _notifyNodeDataChanged(node.key);
  }

  /// Reorders the root nodes to match [orderedKeys].
  ///
  /// [orderedKeys] must contain exactly the current live (non-pending-deletion)
  /// root keys, with no duplicates; violating that throws an
  /// [ArgumentError]. Expansion state, animation state, and measured
  /// extents are preserved. Pending-deletion roots are appended after the
  /// live roots.
  ///
  /// When [animate] is true, shifted roots get a paint-only FLIP slide
  /// over [slideDuration]/[slideCurve]; both default to the controller's
  /// [animationStyle] `reorderSlide` spec when omitted.
  void reorderRoots(
    List<TKey> orderedKeys, {
    bool animate = true,
    Duration? slideDuration,
    Curve? slideCurve,
  }) {
    final pendingRoots = <TKey>[];
    final liveRootSet = <TKey>{};
    for (final k in _roots) {
      if (_isPendingDeletion(k)) {
        pendingRoots.add(k);
      } else {
        liveRootSet.add(k);
      }
    }
    // Validate in all build modes: an `assert` here would be stripped in
    // release and silently corrupt `_roots` (duplicated entries, lost subtrees,
    // references to unknown keys).
    if (orderedKeys.length != liveRootSet.length ||
        orderedKeys.toSet().length != orderedKeys.length ||
        !liveRootSet.containsAll(orderedKeys)) {
      throw ArgumentError.value(
        orderedKeys,
        "orderedKeys",
        "must contain exactly the current live root keys with no duplicates",
      );
    }

    // Stage the FLIP slide baseline BEFORE mutating so shifted roots slide to
    // their new positions (roots are depth-0 and the _markVisibleOrderDirty
    // below always fires, so the next layout consumes the baseline).
    // Family kill switch: a zero reorderSlide spec disables reorder
    // slides even for explicit per-call durations (the engine also
    // snaps a staged zero duration on its own).
    if (animate && _animationStyle.reorderSlide.duration != Duration.zero) {
      // Null timing resolves to the style's reorderSlide spec.
      _stageSlideBaselineOnHosts(
        duration: slideDuration ?? _animationStyle.reorderSlide.duration,
        curve: slideCurve ?? _animationStyle.reorderSlide.curve,
      );
    }
    _roots
      ..clear()
      ..addAll(orderedKeys)
      ..addAll(pendingRoots);
    _markVisibleOrderDirty();
    // Pure reorder: positions change but no row's builder output does
    // (nodeBuilder signature takes (context, key, depth) — no index). The
    // sliver's layout repositions elements in place.
    _notifyStructural(affectedKeys: const {});
  }

  /// Reorders the children of [parentKey] to match [orderedKeys].
  ///
  /// [orderedKeys] must contain exactly the current live (non-pending-deletion)
  /// children of [parentKey], with no duplicates; violating that throws an
  /// [ArgumentError], as does an unknown [parentKey]. Expansion state,
  /// animation state, and measured extents are preserved.
  ///
  /// When [animate] is true and the children are visible, shifted rows
  /// get a paint-only FLIP slide over [slideDuration]/[slideCurve]; both
  /// default to the controller's [animationStyle] `reorderSlide` spec
  /// when omitted.
  void reorderChildren(
    TKey parentKey,
    List<TKey> orderedKeys, {
    bool animate = true,
    Duration? slideDuration,
    Curve? slideCurve,
  }) {
    if (!_hasKey(parentKey)) {
      throw ArgumentError.value(parentKey, "parentKey", "not found");
    }
    final currentChildren = _childListOf(parentKey) ?? <TKey>[];

    final pendingChildren = <TKey>[];
    final liveChildSet = <TKey>{};
    for (final k in currentChildren) {
      if (_isPendingDeletion(k)) {
        pendingChildren.add(k);
      } else {
        liveChildSet.add(k);
      }
    }
    // Validate in all build modes — see reorderRoots for rationale.
    if (orderedKeys.length != liveChildSet.length ||
        orderedKeys.toSet().length != orderedKeys.length ||
        !liveChildSet.containsAll(orderedKeys)) {
      throw ArgumentError.value(
        orderedKeys,
        "orderedKeys",
        "must contain exactly the current live children of $parentKey with "
            "no duplicates",
      );
    }

    // Stage the FLIP slide baseline BEFORE mutating, but only when the children
    // are strictly visible (parent + ancestors expanded). The
    // _markVisibleOrderDirty below fires for the same `visible` case, so the next
    // layout consumes the baseline and slides shifted rows. Gating on `visible`
    // avoids a pointless slide for a collapsed reorder and never strands an
    // unconsumed baseline.
    final visible =
        _isExpandedKey(parentKey) && _ancestorsExpandedFast(parentKey);
    // Family kill switch — see reorderRoots.
    if (animate &&
        visible &&
        _animationStyle.reorderSlide.duration != Duration.zero) {
      // Null timing resolves to the style's reorderSlide spec.
      _stageSlideBaselineOnHosts(
        duration: slideDuration ?? _animationStyle.reorderSlide.duration,
        curve: slideCurve ?? _animationStyle.reorderSlide.curve,
      );
    }

    _setChildList(parentKey, [...orderedKeys, ...pendingChildren]);
    bool needsVisibleRebuild = visible;
    if (!needsVisibleRebuild) {
      // Even if the parent is not expanded, children may still be present
      // in the visible order because they are mid-animation (collapse in
      // progress, pending-deletion exit). Those entries would otherwise
      // retain the old order until the animation completes.
      for (final child in _childListOf(parentKey)!) {
        if (_hasOperationGroup(child) ||
            _activeBulkGroup?.members.contains(child) == true ||
            _hasStandalone(child)) {
          needsVisibleRebuild = true;
          break;
        }
      }
    }
    if (needsVisibleRebuild) {
      _markVisibleOrderDirty();
    }
    // See reorderRoots: pure reorder — no builder output changes.
    _notifyStructural(affectedKeys: const {});
  }

  /// Moves a node from its current parent to [newParentKey].
  ///
  /// If [newParentKey] is null, the node becomes a root. If [index] is
  /// provided, the node is inserted at that position among its new siblings;
  /// otherwise it is appended. [index] is the position among **live**
  /// siblings — exiting (pending-deletion) siblings are skipped, matching
  /// [getIndexInParent] / [getLiveChildren] and the space
  /// `TreeReorderController` computes drop indices in.
  ///
  /// The node's subtree (children, expansion state, and measured extents) is
  /// preserved. Any in-flight enter/exit animations on the moved subtree are
  /// cancelled so a mid-exit node isn't purged at its new location when the
  /// animation finalizes.
  ///
  /// When [animate] is true, every visible row whose painted position changes
  /// as a result of the move (the moved subtree itself plus any siblings
  /// that shift to make room) gets a FLIP slide that lerps from its
  /// pre-move painted position to its post-move structural position over
  /// [slideDuration] using [slideCurve]. Both default to the
  /// controller's [animationStyle] `reorderSlide` spec when omitted.
  /// The slide is paint-only — layout settles immediately at the new
  /// structural positions.
  ///
  /// **Same-frame composition:** multiple animated `moveNode` calls in the
  /// same synchronous block (or inside the same [runBatch]) coalesce under
  /// a first-wins baseline policy — the first call's pre-mutation snapshot
  /// covers every visible row, and subsequent calls' deltas are computed
  /// relative to that single baseline. The first call's [slideDuration]
  /// and [slideCurve] win for the cohesive transition. If the batch
  /// contains both `animate: true` and `animate: false` mutations, **all**
  /// mutations effectively animate (the baseline captures everything; any
  /// row whose final position differs from its baseline gets a slide).
  ///
  /// Has no effect when no [SliverTree] is mounted on this controller, or
  /// when the style's `reorderSlide` duration is `Duration.zero` (the
  /// engine no-ops in that case to honor the global animation-disabled
  /// setting).
  ///
  /// Throws a [StateError] — in all build modes, not just debug — if
  /// [key] is [newParentKey], if [newParentKey] is a descendant of [key]
  /// (either would form a cycle), or if [newParentKey] is pending
  /// deletion (it will be purged when its exit animation completes,
  /// orphaning the moved subtree). Callers driving this from a gesture,
  /// such as `TreeReorderController`, must re-validate against current
  /// tree state before committing.
  void moveNode(
    TKey key,
    TKey? newParentKey, {
    int? index,
    bool animate = true,
    Duration? slideDuration,
    Curve? slideCurve,
  }) {
    assert(_hasKey(key), 'Node $key not found');
    assert(
      newParentKey == null || _hasKey(newParentKey),
      'New parent $newParentKey not found',
    );
    // Self-reparent would build a cycle in _childListOf(key) and stack-overflow
    // _refreshSubtreeDepths. Guard at runtime so release builds don't crash.
    if (newParentKey != null && newParentKey == key) {
      throw StateError("Cannot move $key onto itself");
    }
    // Reparenting under a descendant would form a cycle; check at runtime
    // (release builds skip the assert below). O(depth) ancestor walk from
    // the new parent — materializing every descendant
    // (`_getDescendants(key).contains(...)`) cost O(subtree) time and
    // allocation per move.
    if (newParentKey != null) {
      TKey? cycleCursor = newParentKey;
      while (cycleCursor != null) {
        if (cycleCursor == key) {
          throw StateError(
            "Cannot move $key under its own descendant $newParentKey",
          );
        }
        cycleCursor = _parentKeyOfKey(cycleCursor);
      }
    }
    // Reparenting under a pending-deletion node would orphan the moved
    // subtree when the new parent's exit animation finalizes:
    // `_finalizeAnimation` only purges descendants that are themselves
    // pending-deletion, so a non-pending child is left behind with a stale
    // `parentKey` pointing at a freed nid, and the grandparent's
    // visible-subtree-size cache is decremented for a row that still
    // exists. Mirror the policy `insert(parentKey:)` already enforces.
    // Runtime check (not just an assert) so release builds also reject
    // this rather than silently corrupting state.
    if (newParentKey != null && _isPendingDeletion(newParentKey)) {
      throw StateError(
        "Cannot move $key under $newParentKey while $newParentKey is "
        "animating out (pending deletion). The parent will be purged when "
        "its exit animation completes, leaving the moved subtree orphaned.",
      );
    }

    final oldParent = _parentKeyOfKey(key);
    // If already under the target parent and no explicit position was
    // requested, nothing to do. With an explicit [index] that matches the
    // node's current position under the same parent, also a no-op —
    // avoid wasted baseline staging + structural notification + slide
    // composition for a mutation that produces zero visual change.
    //
    // CRITICAL: this no-op return MUST precede the animate staging below.
    // Otherwise an animated no-op call would stage a baseline (via
    // _stageSlideBaselineOnHosts → beginSlideBaseline) that triggers no
    // layout (no _notifyStructural fires for a no-op), leaving the
    // _pendingSlideBaseline stuck and blocking all subsequent stages
    // under first-wins until something else triggers a layout.
    if (oldParent == newParentKey) {
      if (index == null) return;
      // Compare against the LIVE index (excluding pending-deletion
      // siblings). getIndexInParent returns -1 only when the key is
      // unknown or pending-deletion — neither applies here, so the
      // value is the current live index.
      if (index == getIndexInParent(key)) return;
    }

    // Capture pre-mutation visibility so we can decide entry vs exit
    // phantom paths after the visible-order rebuild runs.
    //
    // Use the structural predicate ([_ancestorsExpandedFast]) instead of
    // [_order.contains] because, inside [runBatch] with deferred rebuilds,
    // [_order] still reflects state at batch entry — any prior in-batch
    // mutation that changed this key's visibility hasn't been flushed yet.
    // The structural predicate reads parent-chain expansion which is
    // eagerly maintained on every [_setParentKey] / [_setExpandedKey],
    // so it's correct regardless of [_order] freshness. The predicate
    // also gives the desired user-facing answer for the rare "key is in
    // [_order] only because it has an active animation under a collapsed
    // ancestor" case — the user sees a collapsed parent, no row visible,
    // so an entry-phantom path is the right choice.
    final wasVisible = animate && _isStructurallyVisible(key);

    // Lazily computed, shared expansion-gated flatten of the moved
    // subtree. The phantom-anchor, exit-anchor, and affected-keys
    // consumers below all need the identical set — the
    // subtree's INTERNAL structure (children lists, expansion flags) is
    // invariant across the move; only key's parent pointer and the
    // subtree's depths change — so one walk serves whichever of the
    // three fire instead of up to three full walks per move.
    List<TKey>? movedSubtreeScratch;
    List<TKey> movedSubtree() {
      return movedSubtreeScratch ??= _flattenSubtree(key, includeRoot: true);
    }

    // First-wins staging fan-out. Every attached sliver render object's
    // beginSlideBaseline is invoked. Inside runBatch (or for adjacent
    // same-frame moveNode calls), the first such call wins; subsequent
    // calls no-op at the host level. The single staged baseline is
    // consumed by the next layout post-mutation.
    //
    // The participation result gates the phantom-anchor staging below
    // (and the exit-anchor staging further down): with no participating
    // host, nothing ever drains the anchor maps, and a LATER animated
    // mutation's consume would apply anchors recorded for this
    // long-finished move to the wrong slide cycle.
    bool hostParticipating = false;
    if (animate) {
      // Null timing resolves to the style's reorderSlide spec. Zero
      // durations are killed downstream by the slide engine's disabled
      // gate, not here — hostParticipating has anchor-draining side
      // effects that must match today's master-zero shape.
      hostParticipating = _stageSlideBaselineOnHosts(
        duration: slideDuration ?? _animationStyle.reorderSlide.duration,
        curve: slideCurve ?? _animationStyle.reorderSlide.curve,
      );

      // Phantom-anchor for collapsed → visible reparenting:
      // If the moved subtree's root is currently NOT in the visible order
      // (because the old parent or an ancestor is collapsed), the staged
      // baseline contains no entry for it — animateFromOffsets would skip
      // installing a slide and the row would pop instantly into its new
      // visible position. Walk up the OLD parent chain to find the
      // deepest visible ancestor (the row the user actually sees with
      // the chevron) and record it as the phantom anchor for every node
      // in the moved subtree. The render object resolves these to
      // painted positions during baseline consumption — anchor's painted
      // position when it's on-screen, viewport edge otherwise — so the
      // emerging row visually slides "out from behind" its old parent.
      if (!wasVisible && hostParticipating) {
        TKey? cursor = _parentKeyOfKey(key);
        while (cursor != null && !_isStructurallyVisible(cursor)) {
          cursor = _parentKeyOfKey(cursor);
        }
        if (cursor != null) {
          _pendingPhantomAnchors ??= <TKey, TKey>{};
          // Apply the same anchor to the entire moved subtree — children
          // inherit the parent's anchor since they were all hidden inside
          // the same collapsed ancestor.
          for (final k in movedSubtree()) {
            _pendingPhantomAnchors![k] = cursor;
          }
        }
      }
    }

    // Snapshot state needed to compute precise affected-keys after the move.
    final oldDepth = _depthOfKey(key);

    // Cancel any animation/deletion state tied to the moved subtree's old
    // position. Without this, a node caught mid-exit-animation would still
    // be purged by _finalizeAnimation after the move, destroying the subtree
    // under its new parent.
    //
    // For the animate=true path we keep any in-flight FLIP slide entries
    // alive: the staged baseline above captured each row's mid-flight
    // painted position (structural + currentDelta), and the next consume's
    // composition path requires reading the still-live slideY in the
    // post-mutation snapshot to recognize the row as having an active
    // slide and avoid the both-off-screen suppression guard inside
    // `GhostRegistry.applyClampAndInstallNewGhosts`. Composition absorbs the
    // structural shift into the new currentDelta — no double-counting.
    _cancelAnimationStateForSubtree(key, cancelSlides: !animate);

    // Remove from old parent's child list (or roots).
    if (oldParent != null) {
      _childListOf(oldParent)?.remove(key);
    } else {
      _roots.remove(key);
    }

    // Insert into new parent's child list (or roots). Explicit index is
    // live-space (matching the live-space no-op guard above); the
    // comparator path already returns a full-space position.
    _setParentKey(key, newParentKey);
    final node = _dataOf(key)!;
    if (newParentKey != null) {
      final siblings = _childListOrCreate(newParentKey);
      final effectiveIndex = index != null
          ? _liveIndexToFullInsertIndex(siblings, index)
          : (comparator != null ? _sortedIndex(siblings, node) : null);
      if (effectiveIndex != null && effectiveIndex < siblings.length) {
        siblings.insert(effectiveIndex, key);
      } else {
        siblings.add(key);
      }
    } else {
      final effectiveIndex = index != null
          ? _liveIndexToFullInsertIndex(_roots, index)
          : (comparator != null ? _sortedIndex(_roots, node) : null);
      if (effectiveIndex != null && effectiveIndex < _roots.length) {
        _roots.insert(effectiveIndex, key);
      } else {
        _roots.add(key);
      }
    }

    final newDepth = newParentKey != null ? (_depthOfKey(newParentKey)) + 1 : 0;
    _refreshSubtreeDepths(key, newDepth);

    _markVisibleOrderDirty();

    // Phase B of the deferred pending-deletion handling started in
    // `_cancelAnimationStateForSubtree`. Now that ancestry reflects the
    // new parent chain, revert any pending-deletion members of the moved
    // subtree using post-mutation `_ancestorsExpandedFast`:
    //   - exit reverses to enter where the new chain is expanded (visible
    //     row regrows from current extent), composing with the staged
    //     slide baseline so the row simultaneously lerps Y/X to its new
    //     painted position;
    //   - exit continues to extent 0 where the new chain is collapsed,
    //     with pending-deletion cleared so finalize skips the purge.
    // No-op when the subtree contains no pending-deletion members (the
    // common case).
    if (animate) {
      _revertSubtreeFromPendingDeletion(key);
    }

    // Exit-phantom for visible → hidden reparenting:
    // Symmetric to the entry-phantom block above. If the moved subtree
    // was visible BEFORE mutation but is hidden AFTER (because the new
    // parent or an ancestor is collapsed), the staged baseline has the
    // moved row at its OLD position but the post-mutation snapshot has
    // no entry for it (it's not in visibleNodes). animateFromOffsets
    // would skip installing a slide and the row would pop out of
    // existence. Walk the NEW parent chain to find the deepest visible
    // ancestor (typically the new collapsed parent's row); record it
    // as the exit anchor for every node in the moved subtree. The
    // render object will inject the anchor's painted position as the
    // slide DESTINATION, retain a ghost render box, and paint the
    // sliding row clipped to "outside the anchor" so it visually
    // disappears INTO the new parent.
    if (animate &&
        hostParticipating &&
        wasVisible &&
        !_isStructurallyVisible(key)) {
      TKey? cursor = newParentKey;
      while (cursor != null && !_isStructurallyVisible(cursor)) {
        cursor = _parentKeyOfKey(cursor);
      }
      if (cursor != null) {
        _pendingExitPhantomAnchors ??= <TKey, TKey>{};
        // Every node that was in the visible OLD subtree shares the same
        // exit anchor. Use the OLD-subtree flatten by enumerating from
        // baseline keys is impractical here; instead, flatten the now-
        // structural subtree (children list still intact post-move) —
        // the moved subtree's expanded structure is preserved through
        // moveNode, so the same set of nodes was visible before and is
        // hidden after.
        for (final k in movedSubtree()) {
          _pendingExitPhantomAnchors![k] = cursor;
        }
      }
    }

    final affected = <TKey>{};
    // If the moved subtree's depth changed, every row in it must rebuild
    // — nodeBuilder receives `depth` as an argument and indentation scales
    // with it. The shared flatten enumerates the currently-expanded rows
    // (the only ones that can be mounted).
    if (newDepth != oldDepth) {
      affected.addAll(movedSubtree());
    }
    // Both parents' child-list lengths changed (and hasChildren may have
    // flipped on either); their builders may render the count.
    if (oldParent != null) {
      affected.add(oldParent);
    }
    if (newParentKey != null) {
      affected.add(newParentKey);
    }
    _notifyStructural(affectedKeys: affected);
  }

  /// Sets the stored depth for [key] and all its descendants. Iterative so deep
  /// trees do not stack-overflow. Depth for each descendant is computed
  /// on visit from the entry paired with it in the worklist, not derived
  /// from its parent's already-written depth, so visit order is irrelevant.
  void _refreshSubtreeDepths(TKey key, int depth) {
    final keys = <TKey>[key];
    final depths = <int>[depth];
    while (keys.isNotEmpty) {
      final k = keys.removeLast();
      final d = depths.removeLast();
      _setDepthKey(k, d);
      final children = _childListOf(k);
      if (children == null) {
        continue;
      }
      final childDepth = d + 1;
      for (final childKey in children) {
        keys.add(childKey);
        depths.add(childDepth);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EXPAND / COLLAPSE
  // ══════════════════════════════════════════════════════════════════════════

  /// Expands the given node, revealing its children.
  void expand({required TKey key, bool animate = true}) {
    if (_animationStyle.expandCollapse.duration == Duration.zero) {
      animate = false;
    }
    if (!_hasKey(key)) {
      return;
    }
    if (_isExpandedKey(key)) {
      return;
    }
    final children = _childListOf(key);
    if (children == null || children.isEmpty) {
      return;
    }
    // Don't expand if this node is currently exiting
    if (isExiting(key)) {
      return;
    }
    // See [insert] for the rationale: flush any deferred visible-order
    // rebuild so `_order.indexOf(key)` below reads fresh state.
    _ensureVisibleOrder();
    // If any descendant about to (re)enter visible order currently has
    // a live exit-slide/ghost, stage a slide baseline FIRST (first-wins),
    // capturing each row's pre-expand painted position. Must precede
    // `_setExpandedKey`/op-group install so the baseline is the FLIP "before";
    // the downstream `_notifyStructural` consume composes the rebase against
    // the row's NEW structural offset, preserving painted position across the
    // base change. The live-slide gate inside the helper makes idle expands a
    // no-op.
    //
    // Use the FULL structural descendant set ([getDescendants]) rather than an
    // expansion-gated flatten: at this point [key] is still collapsed
    // (`_setExpandedKey(key, true)` runs below), so an expansion-gated walk of
    // [key] would return empty and miss the very exit-ghost row whose base is
    // about to change. [getDescendants] walks the structural subtree
    // regardless of expansion state, so the moved exit-ghost (a structural
    // child of [key]) is included.
    _stageSlideBaselineForBaseChange(getDescendants(key));
    // If ancestors are collapsed, just record the expansion state.
    // The node is not visible, so there is nothing to animate or
    // insert into the visible order. When ancestors are later expanded,
    // this node's children will appear immediately.
    if (!_ancestorsExpandedFast(key)) {
      _setExpandedKey(key, true);
      _notifyStructural(affectedKeys: <TKey>{key});
      return;
    }
    _setExpandedKey(key, true);
    // Find where to insert children in visible order
    final parentIndex = _order.indexOf(key);
    if (parentIndex == VisibleOrderBuffer.kNotVisible) {
      return;
    }

    if (!animate) {
      // No animation — insert and return
      final nodesToShow = _flattenSubtree(key, includeRoot: false);
      final nodesToInsert = <TKey>[];
      for (final nodeId in nodesToShow) {
        if (_isPendingDeletion(nodeId)) continue;
        if (!_order.contains(nodeId)) {
          nodesToInsert.add(nodeId);
        } else {
          _removeAnimation(nodeId);
        }
      }
      if (nodesToInsert.isNotEmpty) {
        final insertIndex = parentIndex + 1;
        _order.insertAllKeys(insertIndex, nodesToInsert);
        _updateIndicesFrom(insertIndex);
      }
      _structureGeneration++;
      _notifyStructural(affectedKeys: <TKey>{key});
      return;
    }

    // Animated expand
    final existingGroup = _opGroupAt(key);
    if (existingGroup != null) {
      // Path 1: Reversing a collapse — group already exists.
      //
      // The op-group's controller is the shared timing primitive;
      // each member's NodeGroupExtent envelope (start/target) defines
      // what it animates between. To reverse the collapse smoothly:
      //   1. Rebase each member: capture its current visual extent under
      //      the OLD envelope, set startExtent = current, targetExtent =
      //      full. Reset value=0 and forward().
      //   2. Clear pendingRemoval so the dismissed handler doesn't yank.
      //
      // Resetting controller.value=0 fires a synchronous dismissed event;
      // the registry's install-time identity guard ignores it if the
      // group has been briefly detached. runWithGroupDetached encapsulates
      // the detach/reattach pattern.
      if (existingGroup.pendingRemoval.isNotEmpty) {
        existingGroup.pendingRemoval.clear();
        _bumpAnimGen();
      }
      final preReversalCurvedValue = existingGroup.curvedValue;
      for (final entry in existingGroup.members.entries) {
        final full = _fullExtentOf(entry.key) ?? defaultExtent;
        final currentExtent = entry.value.computeExtent(
          preReversalCurvedValue,
          full,
        );
        entry.value.startExtent = currentExtent;
        entry.value.targetExtent = full;
      }
      _anim.opGroups.runWithGroupDetached(key, (group) {
        group.controller.value = 0.0;
      });
      existingGroup.controller.forward();

      // Handle descendants NOT in this group (from nested expansions)
      final nodesToShow = _flattenSubtree(key, includeRoot: false);
      for (final nodeId in nodesToShow) {
        if (_isPendingDeletion(nodeId)) continue;
        if (existingGroup.members.containsKey(nodeId)) continue;

        if (_standaloneAt(nodeId) case final anim?
            when anim.type == AnimationType.exiting) {
          // Reverse the exit to an enter with speedMultiplier
          _startStandaloneEnterAnimation(nodeId);
        } else if (!_order.contains(nodeId)) {
          // New node not yet visible — insert at correct sibling position
          // and animate. _insertNodeIntoVisibleOrder appends at the end of
          // the grandparent's subtree, which drops the node past its
          // following siblings when they are already in the visible order.
          _insertNewNodeAmongSiblings(nodeId);
          _startStandaloneEnterAnimation(nodeId);
        }
      }
      _structureGeneration++;
      _notifyStructural(affectedKeys: <TKey>{key});
      return;
    }

    // Path 2: Fresh expand — create new operation group via the
    // OperationGroupRegistry's install API (constructs the controller +
    // OperationGroup internally and wires the tick + status callbacks).
    final nodesToShow = _flattenSubtree(key, includeRoot: false);
    final group = _anim.opGroups.install(
      key,
      _animationStyle.expandCollapse.curve,
    );
    _bumpAnimGen(); // invalidate animation-generation-keyed caches

    // Fast path check: count new vs existing nodes
    int newNodeCount = 0;
    int effectiveCount = 0;
    for (final nodeId in nodesToShow) {
      if (_isPendingDeletion(nodeId)) continue;
      effectiveCount++;
      if (!_order.contains(nodeId)) {
        newNodeCount++;
      }
    }

    // Path 2 expand: each newly-affected descendant joins the group as
    // a member with a NodeGroupExtent envelope. Per-node animation
    // records are NOT created on a fresh op — they only come into
    // existence on CAPTURE (a prior op's mid-flight node being pulled
    // into a new op). The op-group's controller is the shared timing
    // primitive for non-captured members; private records, when they
    // exist on captured members, carry the captured node's own clock.
    if (newNodeCount == 0) {
      // All nodes already visible (reversing collapse animation)
      for (final nodeId in nodesToShow) {
        if (_isPendingDeletion(nodeId)) continue;
        final capturedExtent = _captureAndRemoveFromGroups(nodeId);
        final nge = NodeGroupExtent(
          startExtent: capturedExtent ?? 0.0,
          targetExtent: _fullExtentOf(nodeId) ?? _unknownExtent,
        );
        group.members[nodeId] = nge;
        _setOperationGroup(nodeId, key);
      }
    } else if (newNodeCount == effectiveCount) {
      // All nodes need insertion (normal expand)
      final nodesToInsert = <TKey>[];
      for (final nodeId in nodesToShow) {
        if (_isPendingDeletion(nodeId)) continue;
        final capturedExtent = _captureAndRemoveFromGroups(nodeId);
        final nge = NodeGroupExtent(
          startExtent: capturedExtent ?? 0.0,
          targetExtent: _fullExtentOf(nodeId) ?? _unknownExtent,
        );
        group.members[nodeId] = nge;
        _setOperationGroup(nodeId, key);
        nodesToInsert.add(nodeId);
      }
      final insertIndex = parentIndex + 1;
      _order.insertAllKeys(insertIndex, nodesToInsert);
      _updateIndicesFrom(insertIndex);
    } else {
      // Mixed path: some visible (exiting), some need insertion
      int currentInsertIndex = parentIndex + 1;
      int insertOffset = 0;
      int minInsertIndex = _order.length;
      for (final nodeId in nodesToShow) {
        if (_isPendingDeletion(nodeId)) continue;
        final existingIndex = _order.indexOf(nodeId);
        final capturedExtent = _captureAndRemoveFromGroups(nodeId);
        final nge = NodeGroupExtent(
          startExtent: capturedExtent ?? 0.0,
          targetExtent: _fullExtentOf(nodeId) ?? _unknownExtent,
        );
        group.members[nodeId] = nge;
        _setOperationGroup(nodeId, key);

        if (existingIndex != VisibleOrderBuffer.kNotVisible) {
          // Node already visible (was exiting)
          currentInsertIndex = existingIndex + insertOffset + 1;
        } else {
          // Insert at current position
          if (currentInsertIndex < minInsertIndex) {
            minInsertIndex = currentInsertIndex;
          }
          _order.insertKey(currentInsertIndex, nodeId);
          insertOffset++;
          currentInsertIndex++;
        }
      }
      if (insertOffset > 0) {
        _updateIndicesFrom(minInsertIndex);
      }
    }

    _structureGeneration++;
    group.controller.forward();
    // Path 2 creates no standalone states of its own — only keep the
    // standalone ticker alive when states from other sources exist. An
    // ungated start costs one wasted start/stop frame per operation.
    if (_anim.standalone.hasAny) {
      _anim.standalone.ensureRunning();
    }
    _notifyStructural(affectedKeys: <TKey>{key});
  }

  /// Collapses the given node, hiding its children.
  ///
  /// Note: This preserves the expansion state of descendant nodes. When the
  /// node is re-expanded, any previously expanded children will also show
  /// their children automatically.
  void collapse({required TKey key, bool animate = true}) {
    if (_animationStyle.expandCollapse.duration == Duration.zero) {
      animate = false;
    }
    if (!_hasKey(key) || !_isExpandedKey(key)) {
      return;
    }
    // See [insert] for the rationale: flush any deferred visible-order
    // rebuild so the descendant / index lookups below operate on fresh
    // state.
    _ensureVisibleOrder();
    // Symmetric case: if any visible descendant about to LEAVE visible
    // order currently has a live entry-slide/ghost, stage a slide baseline
    // FIRST (first-wins), capturing pre-collapse painted positions. Computed
    // from the still-current visible order BEFORE `_setExpandedKey` flips the
    // node, so the descendants are still visible here. Mirrors the expand
    // path; the live-slide gate keeps idle collapses a no-op.
    _stageSlideBaselineForBaseChange(_getVisibleDescendants(key));
    _setExpandedKey(key, false);
    // Find all visible descendants (includes nodes currently entering)
    final descendants = _getVisibleDescendants(key);
    if (descendants.isEmpty) {
      _notifyStructural(affectedKeys: <TKey>{key});
      return;
    }

    if (!animate) {
      // Remove immediately from visible order
      final toRemove = <TKey>{};
      for (final nodeId in descendants) {
        if (!_isPendingDeletion(nodeId)) {
          toRemove.add(nodeId);
          _removeAnimation(nodeId);
        }
      }
      if (toRemove.isNotEmpty) {
        _removeFromVisibleOrder(toRemove);
        _structureGeneration++;
      }
      _notifyStructural(affectedKeys: <TKey>{key});
      return;
    }

    // Animated collapse
    final existingGroup = _opGroupAt(key);
    if (existingGroup != null) {
      // Path 1: Reversing an expand — group already exists.
      //
      // Mirror of the expand Path-1 reversal block:
      //   1. Rebase each member: capture its current visual extent
      //      and animate from `current → 0` over the configured
      //      duration. We do this by setting startExtent=0 and
      //      targetExtent=currentExtent (so as the controller's
      //      reverse takes value from 1 → 0, lerp(0, current, value)
      //      runs from current → 0).
      //   2. Add all members to pendingRemoval so the dismissed
      //      handler removes them from `_order`.
      //   3. Reset controller.value=1 with the detach/reattach trick
      //      so the reverse plays over full duration with no jump.
      //
      // Captured members' private records re-pause as their nodes
      // re-enter pendingRemoval; their preserved progress is unchanged
      // and they'll resume only on a subsequent re-expand.
      final preReversalCurvedValue = existingGroup.curvedValue;
      for (final entry in existingGroup.members.entries) {
        final full = _fullExtentOf(entry.key) ?? defaultExtent;
        final currentExtent = entry.value.computeExtent(
          preReversalCurvedValue,
          full,
        );
        entry.value.startExtent = 0.0;
        entry.value.targetExtent = currentExtent;
        existingGroup.pendingRemoval.add(entry.key);
      }
      _anim.opGroups.runWithGroupDetached(key, (group) {
        group.controller.value = 1.0;
      });
      _bumpAnimGen();
      existingGroup.controller.reverse();

      // Handle descendants NOT in this group (from nested expansions)
      for (final nodeId in descendants) {
        if (_isPendingDeletion(nodeId)) continue;
        if (existingGroup.members.containsKey(nodeId)) continue;
        // Create standalone exit animation with speedMultiplier
        _startStandaloneExitAnimation(nodeId, triggeringAncestorId: key);
      }
      _structureGeneration++;
      _notifyStructural(affectedKeys: <TKey>{key});
      return;
    }

    // Path 2: Fresh collapse — create new operation group via the
    // OperationGroupRegistry's install API with initialValue=1.0
    // (collapse starts fully expanded and reverses toward 0).
    final group = _anim.opGroups.install(
      key,
      _animationStyle.expandCollapse.curve,
      initialValue: 1.0,
    );
    _bumpAnimGen(); // invalidate animation-generation-keyed caches

    for (final nodeId in descendants) {
      if (_isPendingDeletion(nodeId)) continue;
      final capturedExtent = _captureAndRemoveFromGroups(nodeId);
      final nge = NodeGroupExtent(
        startExtent: 0.0,
        targetExtent:
            capturedExtent ?? (_fullExtentOf(nodeId) ?? defaultExtent),
        targetIsCaptured: capturedExtent != null,
      );
      group.members[nodeId] = nge;
      group.pendingRemoval.add(nodeId);
      _setOperationGroup(nodeId, key);
    }

    _structureGeneration++;
    group.controller.reverse();
    // See the matching gate in the expand path.
    if (_anim.standalone.hasAny) {
      _anim.standalone.ensureRunning();
    }
    _notifyStructural(affectedKeys: <TKey>{key});
  }

  /// Toggles the expansion state of the given node.
  void toggle({required TKey key, bool animate = true}) {
    if (_isExpandedKey(key)) {
      collapse(key: key, animate: animate);
    } else {
      expand(key: key, animate: animate);
    }
  }

  /// Expands all nodes in the tree.
  ///
  /// Uses batch operations for better performance with large trees.
  void expandAll({bool animate = true, int? maxDepth}) {
    if (_animationStyle.expandCollapse.duration == Duration.zero) {
      animate = false;
    }
    // Flush any pending visible-order rebuild from a prior in-batch mutator
    // (moveNode, reorderRoots, reorderChildren, cancelDeletion, …). The
    // collection loop below classifies children via `_order.contains`;
    // inside a [runBatch] the order still reflects state at batch entry,
    // so a child whose visibility was changed by an earlier in-batch
    // mutation would be misclassified — omitted from nodesToShow (pops in
    // at full extent, never joins the bulk group). Same pattern as
    // [insert] / [expand] / [collapse].
    _ensureVisibleOrder();
    // Collect all nodes to expand, nodes to show, and nodes currently exiting
    final nodesToExpand = <TKey>[];
    final nodesToShow = <TKey>[];
    final nodesToReverseExit = <TKey>[];
    // Scratch for the expansion-gated flatten harvest below.
    final flattenScratch = <TKey>[];

    // Iterative DFS. Depth is recomputed per-visit via [_depthOfKey]
    // (matching the original recursive implementation) so we do not
    // need to carry depth along in a parallel stack.
    final stack = <TKey>[];
    for (final rootId in _roots) {
      stack.add(rootId);
    }
    while (stack.isNotEmpty) {
      final key = stack.removeLast();
      if (_isPendingDeletion(key)) {
        continue;
      }
      final children = _childListOf(key);
      if (children == null || children.isEmpty) {
        continue;
      }

      final depth = _depthOfKey(key);
      final withinDepthLimit = maxDepth == null || depth < maxDepth;

      if (withinDepthLimit && !_isExpandedKey(key)) {
        nodesToExpand.add(key);
        for (final childId in children) {
          if (!_order.contains(childId)) {
            // Harvest the child plus everything reachable through
            // already-expanded interior nodes: a hidden node B whose own
            // expansion flag stayed true through an ancestor collapse
            // becomes visible together with its children when [key]
            // expands. The DFS below only harvests at nodes it flips
            // (already-expanded children are never re-pushed as
            // nodesToExpand, and depth-limited nodes are not descended
            // into), so without this flatten those revealed descendants
            // would render at full extent from frame one while everything
            // around them animates — expand(key:) on the identical
            // structure animates the whole revealed subtree.
            flattenScratch.clear();
            _flattenSubtreeInto(childId, flattenScratch, includeRoot: true);
            for (final k in flattenScratch) {
              // Preserve the child-level invariants: skip nodes already
              // in the order (e.g. still animating an exit under this
              // collapsed ancestor) and pending-deletion nodes.
              if (!_order.contains(k) && !_isPendingDeletion(k)) {
                nodesToShow.add(k);
              }
            }
          }
        }
      }

      // Still check children for exiting animations regardless of depth.
      for (final childId in children) {
        // Check standalone exiting
        final animation = _standaloneAt(childId);
        if (animation != null && animation.type == AnimationType.exiting) {
          if (!_isPendingDeletion(childId)) {
            nodesToReverseExit.add(childId);
          }
        }
        // Check operation group exiting (pendingRemoval)
        final opGroupKey = _operationGroupOf(childId);
        if (opGroupKey != null) {
          final opGroup = _opGroupAt(opGroupKey);
          if (opGroup != null && opGroup.pendingRemoval.contains(childId)) {
            if (!_isPendingDeletion(childId)) {
              nodesToReverseExit.add(childId);
            }
          }
        }
      }

      // Only descend into children if within depth limit.
      if (withinDepthLimit) {
        for (final childId in children) {
          stack.add(childId);
        }
      }
    }
    if (nodesToExpand.isEmpty && nodesToReverseExit.isEmpty) {
      return;
    }
    // Batch update expansion states. Skip per-call ancestors-expanded
    // propagation — we rebuild it wholesale below in O(N).
    for (final key in nodesToExpand) {
      _setExpandedKey(key, true, propagate: false);
    }
    _rebuildAllAncestorsExpanded();
    // Rebuild visible order from scratch (more efficient for bulk operations)
    _markVisibleOrderDirty();
    // Flush the deferred rebuild NOW. The bulk-member registration loops
    // below gate on `_order.contains(key)` to skip children that aren't
    // structurally visible; inside a [runBatch], `_markVisibleOrderDirty`
    // sets only a dirty flag and `_order` remains pre-mutation. Without
    // this flush, every newly-visible child fails the `contains` check
    // and never gets added to the bulk group, so the bulk animation runs
    // empty and the children appear at full extent in one frame.
    // Outside a batch this is a no-op (the mark already triggered the
    // rebuild synchronously); inside a batch it forces consumption now,
    // and any subsequent in-batch mutation can re-mark dirty as needed.
    _ensureVisibleOrder();
    // Start animations for newly visible nodes and reverse exiting animations
    if (animate) {
      // Reverse collapsing operation groups. Snapshot before iterating: a
      // group's controller already at upperBound would fire `completed`
      // synchronously inside `forward()`, removing itself from `_groups`
      // mid-iteration. See [_opGroupSnapshot] docs.
      bool opGroupReversed = false;
      _opGroupSnapshot
        ..clear()
        ..addAll(_opGroupEntries);
      for (final entry in _opGroupSnapshot) {
        final group = entry.value;
        if (group.pendingRemoval.isNotEmpty) {
          group.pendingRemoval.clear();
          opGroupReversed = true;
          // Restore each member's targetExtent to full so the reversal
          // terminates at the correct natural size instead of at a
          // captured mid-flight value.
          for (final member in group.members.entries) {
            member.value.targetExtent =
                _fullExtentOf(member.key) ?? _unknownExtent;
          }
          group.controller.forward();
        }
      }
      _opGroupSnapshot.clear();
      if (opGroupReversed) _bumpAnimGen();

      // Check if there's a collapsing bulk animation we can reverse
      if (_activeBulkGroup != null &&
          _activeBulkGroup!.pendingRemoval.isNotEmpty) {
        // Reverse the animation - nodes being removed will now expand
        // Clear pending removal since we're expanding now
        _clearBulkPending();

        // Reverse standalone exit animations smoothly
        for (final key in nodesToReverseExit) {
          if (!_hasOperationGroup(key)) {
            _startStandaloneEnterAnimation(key);
          }
        }

        // Add any new nodes to the group (skip if already in an operation group)
        for (final key in nodesToShow) {
          if (_order.contains(key) && !_hasOperationGroup(key)) {
            _addBulkMember(key);
          }
        }

        // Reverse the controller direction
        _activeBulkGroup!.controller.forward();
        _bumpBulkGen();
      } else if (_activeBulkGroup != null &&
          _activeBulkGroup!.members.isNotEmpty) {
        // Continuation: a bulk expand is already mid-flight (members
        // present, nothing pending removal). Keep the group — existing
        // members continue from their current extent. Creating a fresh
        // group here would dispose the in-flight one and pop every
        // half-expanded member to full extent in a single frame.
        //
        // Genuinely NEW nodes must NOT join the mid-flight group (they
        // would pop from 0 to `full * currentValue` on join); route them
        // through standalone enter animations instead — the same policy
        // the reverse branch applies to nodesToReverseExit.
        for (final key in nodesToReverseExit) {
          if (!_hasOperationGroup(key)) {
            _startStandaloneEnterAnimation(key);
          }
        }
        for (final key in nodesToShow) {
          if (_order.contains(key) &&
              !_hasOperationGroup(key) &&
              !_activeBulkGroup!.members.contains(key)) {
            final st = _standaloneAt(key);
            if (st != null && st.type == AnimationType.entering) {
              continue;
            }
            _startStandaloneEnterAnimation(key);
          }
        }
        _bumpBulkGen();
      } else {
        // Create fresh group via the BulkAnimator (auto-disposes any
        // prior). All listener wiring happens inside createGroup.
        _anim.bulk.createGroup(
          _animationStyle.expandCollapse.duration,
          _animationStyle.expandCollapse.curve,
        );
        _bumpBulkGen(); // invalidate bulk + broad generation caches

        // Reverse standalone exit animations smoothly
        for (final key in nodesToReverseExit) {
          if (!_hasOperationGroup(key)) {
            _startStandaloneEnterAnimation(key);
          }
        }

        // Add new nodes to the bulk group (skip if already in an operation group)
        for (final key in nodesToShow) {
          if (_order.contains(key) && !_hasOperationGroup(key)) {
            _addBulkMember(key);
          }
        }

        // Start expanding (value 0 -> 1)
        _activeBulkGroup!.controller.forward();
        _bumpBulkGen();
      }
    } else {
      // Remove animations if not animating
      for (final key in nodesToReverseExit) {
        _removeAnimation(key);
      }
    }
    // Bulk expansion touches many ancestors' expansion state + every
    // previously-collapsed node now flips its chevron. Enumerating the
    // affected set precisely is error-prone; fall back to a full refresh.
    _notifyStructural();
  }

  /// Collapses all nodes in the tree.
  ///
  /// Uses batch operations for better performance with large trees.
  void collapseAll({bool animate = true, int? maxDepth}) {
    if (_animationStyle.expandCollapse.duration == Duration.zero) {
      animate = false;
    }
    // Flush any pending visible-order rebuild from a prior in-batch mutator.
    // `_getVisibleDescendants` below reads `_order.contains`; inside a
    // [runBatch] the order still reflects state at batch entry, so a node
    // made visible by an earlier in-batch mutation would be missed —
    // never joining the bulk group and popping out in one frame. Same
    // pattern as [insert] / [expand] / [collapse].
    _ensureVisibleOrder();
    // Collect all expanded nodes and their visible descendants
    final nodesToCollapse = <TKey>[];
    final nodesToHide = <TKey>[];
    for (final rootId in _roots) {
      if (_isExpandedKey(rootId)) {
        nodesToCollapse.add(rootId);
        nodesToHide.addAll(_getVisibleDescendants(rootId));
      }
    }
    // Also check for nodes that are entering (from an interrupted expandAll)
    final nodesToHideSet = nodesToHide.toSet();

    // Check standalone entering animations
    for (final nid in _anim.standalone.activeNids) {
      final state = _anim.standalone.slotAtNid(nid)!;
      if (state.type != AnimationType.entering) continue;
      final key = _nids.keyOfUnchecked(nid);
      if (nodesToHideSet.contains(key)) continue;
      if (_parentKeyOfKey(key) != null) {
        nodesToHide.add(key);
        nodesToHideSet.add(key);
      }
    }

    // Check operation group members (expanding)
    for (final entry in _opGroupEntries) {
      final group = entry.value;
      // (loop body uses `group`)
      if (group.pendingRemoval.isEmpty) {
        // Group is expanding
        for (final key in group.members.keys) {
          if (!nodesToHideSet.contains(key)) {
            if (_parentKeyOfKey(key) != null) {
              nodesToHide.add(key);
              nodesToHideSet.add(key);
            }
          }
        }
      }
    }

    // Check bulk group members (expanding nodes)
    if (_activeBulkGroup != null) {
      for (final key in _activeBulkGroup!.members) {
        if (!nodesToHideSet.contains(key)) {
          if (_parentKeyOfKey(key) != null) {
            nodesToHide.add(key);
            nodesToHideSet.add(key);
          }
        }
      }
    }

    if (nodesToHide.isEmpty) {
      if (nodesToCollapse.isNotEmpty) {
        _collapseAllInRegistry(maxDepth);
        // Bulk expansion-state clear — see main collapseAll branch below.
        _notifyStructural();
      }
      return;
    }
    // Clear expansion state for ALL nodes within depth limit,
    // not just visible ones.
    _collapseAllInRegistry(maxDepth);
    _structureGeneration++;
    if (animate) {
      // Reverse expanding operation groups. Snapshot before iterating: a
      // group's controller already at lowerBound would fire `dismissed`
      // synchronously inside `reverse()`, removing itself from `_groups`
      // mid-iteration. See [_opGroupSnapshot] docs.
      bool opGroupReversed = false;
      _opGroupSnapshot
        ..clear()
        ..addAll(_opGroupEntries);
      for (final entry in _opGroupSnapshot) {
        final group = entry.value;
        if (group.pendingRemoval.isEmpty) {
          // Group is expanding — reverse it
          for (final nodeId in group.members.keys) {
            if (!_isPendingDeletion(nodeId)) {
              group.pendingRemoval.add(nodeId);
              opGroupReversed = true;
            }
          }
          // Normalize startExtent to 0 so the reversal terminates at
          // zero instead of at a captured mid-flight start value.
          for (final member in group.members.entries) {
            member.value.startExtent = 0.0;
          }
          group.controller.reverse();
        }
      }
      _opGroupSnapshot.clear();
      if (opGroupReversed) _bumpAnimGen();

      // Check if there's an expanding bulk animation we can reverse
      if (_activeBulkGroup != null &&
          _activeBulkGroup!.members.isNotEmpty &&
          _activeBulkGroup!.pendingRemoval.isEmpty) {
        // Mark all members for removal when animation completes at 0
        for (final key in _activeBulkGroup!.members) {
          if (!_isPendingDeletion(key)) {
            _addBulkPending(key);
          }
        }

        // Handle additional nodes not in any group
        for (final key in nodesToHide) {
          if (_isPendingDeletion(key)) continue;
          if (!_activeBulkGroup!.members.contains(key) &&
              !_hasOperationGroup(key)) {
            _startStandaloneExitAnimation(key);
          }
        }

        // Reverse the controller direction
        _activeBulkGroup!.controller.reverse();
        _bumpBulkGen();
      } else if (_activeBulkGroup != null &&
          _activeBulkGroup!.pendingRemoval.isNotEmpty) {
        // Continuation: a bulk collapse is already mid-flight. Keep the
        // group — existing members continue from their current extent.
        // Creating a fresh group at value 1.0 here (e.g. on a double-tap
        // of a "collapse all" button) would dispose the in-flight one and
        // snap every half-collapsed row back to full extent for a frame.
        //
        // Genuinely NEW nodes must NOT join the mid-flight group (they
        // would jump straight to `full * currentValue`); route them
        // through standalone exit animations instead.
        for (final key in nodesToHide) {
          if (_isPendingDeletion(key)) continue;
          if (_hasOperationGroup(key)) continue;
          if (_activeBulkGroup!.members.contains(key) ||
              _activeBulkGroup!.pendingRemoval.contains(key)) {
            continue;
          }
          final st = _standaloneAt(key);
          if (st != null && st.type == AnimationType.exiting) {
            continue;
          }
          _startStandaloneExitAnimation(key);
        }
        _bumpBulkGen();
      } else {
        // Create fresh group via the BulkAnimator with value=1.0 (collapse
        // starts fully expanded and reverses toward 0).
        _anim.bulk.createGroup(
          _animationStyle.expandCollapse.duration,
          _animationStyle.expandCollapse.curve,
          initialValue: 1.0,
        );
        _bumpBulkGen();

        // Add nodes to the bulk group, keeping individually-animating
        // nodes on their own timeline for smooth transitions.
        for (final key in nodesToHide) {
          if (_isPendingDeletion(key)) continue;
          if (_hasOperationGroup(key)) continue;
          if (_hasStandalone(key)) {
            // Reverse standalone animation smoothly
            _startStandaloneExitAnimation(key);
          } else {
            _removeAnimation(key);
            _addBulkMember(key);
            _addBulkPending(key);
          }
        }

        // Start collapsing (value 1 -> 0)
        if (_activeBulkGroup!.members.isNotEmpty) {
          _activeBulkGroup!.controller.reverse();
        }
        _bumpBulkGen();
      }
    } else {
      // Remove immediately
      final toRemove = <TKey>{};
      for (final key in nodesToHide) {
        if (!_isPendingDeletion(key)) {
          toRemove.add(key);
          _removeAnimation(key);
        }
      }
      if (toRemove.isNotEmpty) {
        _removeFromVisibleOrder(toRemove);
      }
    }
    // Bulk expansion-state clear: every node whose isExpanded state flipped
    // may render differently (chevron rotation, etc.). The set can span
    // arbitrary subtrees; fall back to a full refresh.
    _notifyStructural();
  }

  /// Rebuilds the entire visible order from the tree structure.
  ///
  /// More efficient than incremental updates when making bulk changes.
  /// Iterative DFS so deep trees do not stack-overflow. Children are
  /// pushed in reverse order so popping yields the original
  /// left-to-right pre-order visit sequence the recursive version
  /// produced (and which the visible-order buffer expects).
  ///
  /// Suppresses per-nid visibility callbacks during the rebuild and
  /// recomputes the visible-subtree-size cache in one O(N) post-order
  /// pass afterwards. Firing the incremental callback N times would be
  /// O(N·depth), which degenerates to O(N²) on deep trees.
  ///
  /// Delegates to [VisibleOrderBuffer.rebuild], which owns "clear + fill
  /// + finalize all derived state" — it clears the order, runs the
  /// closure (which only does the populate work), then calls
  /// `rebuildIndex()` and `_rebuildSubtreeSizes()` itself.
  void _rebuildVisibleOrder() {
    _order.rebuild(_rebuildVisibleOrderImpl);
  }

  /// Shared body for the immediate-mode helper and the deferred-flush
  /// helper: rebuild the visible order and bump the structure generation
  /// in a single coherent step. Stays out-of-line so [_markVisibleOrderDirty]
  /// and [_ensureVisibleOrder] don't carry the literal pair.
  void _rebuildVisibleOrderAndBump() {
    _rebuildVisibleOrder();
    ++_structureGeneration;
  }

  /// Equivalent of `_rebuildVisibleOrder(); _structureGeneration++;` for
  /// internal mutators, but defers the rebuild when called inside
  /// [runBatch]. Outside a batch, behavior matches the inlined pair so
  /// existing single-mutation paths are unchanged.
  ///
  /// Inside a batch, only the dirty flag is set; the actual rebuild
  /// happens once at outermost batch exit (or on the first public
  /// visible-order read via [_ensureVisibleOrder]). The structure
  /// generation is bumped at flush time so external observers, which
  /// are themselves notified at batch exit, see a single coherent bump.
  void _markVisibleOrderDirty() {
    if (_batchDepth > 0) {
      _visibleOrderDirty = true;
    } else {
      _rebuildVisibleOrderAndBump();
    }
  }

  /// Materializes any deferred [_rebuildVisibleOrder] and clears the
  /// dirty flag. Cheap when not dirty (single bool check). Called from
  /// [runBatch]'s exit path before listeners fire, and from public
  /// visible-order accessors so external reads always see fresh state.
  void _ensureVisibleOrder() {
    if (_visibleOrderDirty) {
      _visibleOrderDirty = false;
      _rebuildVisibleOrderAndBump();
    }
  }

  /// Whether [key] would currently be in the visible order based purely
  /// on its parent chain's expansion state. Independent of [_order]
  /// freshness, so safe to call from inside a batch where the deferred
  /// rebuild hasn't run yet.
  ///
  /// Backed by [_ancestorsExpandedFast] (O(1), eagerly maintained by
  /// [_setParentKey] / [_setExpandedKey] through the node store). Does
  /// NOT reflect the "pending-deletion ancestor with active descendant
  /// animation" carve-out that [_rebuildVisibleOrderImpl] applies — but
  /// that case is irrelevant for [moveNode] (its `_cancelAnimationStateForSubtree`
  /// step already strips pending-deletion state from the moved subtree
  /// before any post-mutation visibility check fires).
  bool _isStructurallyVisible(TKey key) {
    if (!_hasKey(key)) return false;
    return _ancestorsExpandedFast(key);
  }

  /// Populates the visible order (called by [VisibleOrderBuffer.rebuild]
  /// as the closure body). The wrapper handles `clear()`, index rebuild,
  /// and subtree-size rebuild itself, so this body only walks the
  /// structure and calls [VisibleOrderBuffer.addKey] for each visible nid.
  void _rebuildVisibleOrderImpl() {
    final stack = <TKey>[];
    for (int i = _roots.length - 1; i >= 0; i--) {
      stack.add(_roots[i]);
    }

    while (stack.isNotEmpty) {
      final key = stack.removeLast();
      _order.addKey(key);
      final children = _childListOf(key);
      if (children == null) {
        continue;
      }

      if (_isPendingDeletion(key)) {
        // Don't recurse based on expansion state (prevents zombie children),
        // but DO include children that are also pending deletion and still
        // have running exit animations — they need to stay in the visible order
        // to animate out smoothly.
        for (int i = children.length - 1; i >= 0; i--) {
          final childId = children[i];
          if (_isPendingDeletion(childId) && _hasStandalone(childId)) {
            stack.add(childId);
          }
        }
      } else if (_isExpandedKey(key)) {
        for (int i = children.length - 1; i >= 0; i--) {
          stack.add(children[i]);
        }
      } else {
        // Parent is collapsed, but children that are still in an active
        // animation (e.g. collapsing via an OperationGroup) must remain
        // in the visible order so their exit animation completes smoothly
        // instead of snapping away.
        for (int i = children.length - 1; i >= 0; i--) {
          final childId = children[i];
          if (_hasOperationGroup(childId) ||
              _activeBulkGroup?.members.contains(childId) == true ||
              _hasStandalone(childId)) {
            stack.add(childId);
          }
        }
      }
    }
  }

  @override
  void dispose() {
    // Cancel any in-flight animated scroll (its completion loop would
    // otherwise keep pumping frames and hold an active Ticker through the
    // vsync State's dispose). Guarded so a never-used orchestrator isn't
    // instantiated just to be disposed.
    if (_scrollCreated) {
      _scroll.dispose();
    }
    // Break the closure → _order reference wired in _store's initializer
    // cascade so the GC graph is clean even if something holds a stale
    // _store reference past dispose. No-op if the wiring never fired.
    _store.onParentChanged = null;
    _clear();
    _anim.dispose(); // sub-coordinators + slide engine
    _nodeDataListeners.clear();
    _structuralListeners.clear();
    _renderHosts.clear();
    _pendingPhantomAnchors = null;
    _pendingExitPhantomAnchors = null;
    super.dispose();
  }
}
