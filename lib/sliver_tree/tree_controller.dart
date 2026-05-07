/// Controller that manages tree state, visibility, and animations.
library;

import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' show lerpDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '_node_id_registry.dart';
import '_node_store.dart';
import '_scroll_orchestrator.dart';
import '_slide_animation_engine.dart';
import '_visible_order_buffer.dart';
import 'types.dart';

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
    Duration animationDuration = const Duration(milliseconds: 300),
    Curve animationCurve = Curves.easeInOut,
    double indentWidth = 0.0,
    this.comparator,
  }) : _animationDuration = animationDuration,
       _animationCurve = animationCurve,
       _indentWidth = indentWidth,
       _vsync = vsync;

  final TickerProvider _vsync;

  Duration _animationDuration;

  /// Duration for expand/collapse animations.
  ///
  /// Mutable at runtime. Setting a new value propagates to every in-flight
  /// [AnimationController] (operation groups and the bulk group) so their
  /// remaining progress plays at the new rate. The per-node standalone
  /// ticker re-reads this on every tick, so its animations adjust on the
  /// next frame. Newly started animations pick up the new duration at
  /// construction time.
  Duration get animationDuration => _animationDuration;
  set animationDuration(Duration value) {
    if (value == _animationDuration) {
      return;
    }
    _animationDuration = value;
    _bulkAnimationGroup?.controller.duration = value;
    for (final group in _operationGroups.values) {
      group.controller.duration = value;
    }
  }

  Curve _animationCurve;

  /// Curve for expand/collapse animations.
  ///
  /// Mutable at runtime. The standalone ticker re-reads this every frame,
  /// so per-node enter/exit animations switch curves immediately. Bulk and
  /// operation groups capture the curve at construction and keep it for the
  /// remainder of that animation — swapping a group's curve mid-flight would
  /// produce a visual discontinuity since the prior frames were already
  /// committed under the old curve. New groups pick up the new curve.
  Curve get animationCurve => _animationCurve;
  set animationCurve(Curve value) {
    if (value == _animationCurve) {
      return;
    }
    _animationCurve = value;
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

  // ══════════════════════════════════════════════════════════════════════════
  // ECS-STYLE COMPONENT STORAGE
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Structural per-nid state (parent, children, depth, expansion, ancestors-
  // expanded cache) lives inside [_store]. Visibility-related per-nid state
  // ([_visibleSubtreeSizeByNid] below, plus the order buffer's reverse
  // index) stays here on the controller because it describes what is
  // currently rendered, not what the tree looks like structurally.
  //
  // The store grows its dense arrays in lockstep with the controller's
  // own per-nid arrays via the [onCapacityGrew] callback wired up in the
  // initializer for [_store].

  /// Sentinel value in nid-indexed parent arrays meaning "no parent" (root
  /// node) or "slot is free". Re-exported as a controller-private constant
  /// so existing call sites that referenced `_kNoParent` don't have to
  /// switch to the imported [kNoParentNid] symbol all over the file.
  static const int _kNoParent = kNoParentNid;

  /// Structural-component store. Owns the nid registry plus every dense
  /// per-nid array describing tree structure. See [NodeStore].
  late final NodeStore<TKey, TData> _store = NodeStore<TKey, TData>(
    onCapacityGrew: _onStoreCapacityGrew,
  );

  /// Convenience alias preserved so existing code that referenced `_nids`
  /// directly continues to compile. Forwards to [NodeStore.nids].
  NodeIdRegistry<TKey> get _nids => _store.nids;

  /// Grows controller-owned per-nid arrays (visible-subtree-size, the
  /// order buffer's reverse index, and the five animation-state arrays)
  /// to match the store's new capacity. Wired into [_store] via its
  /// [NodeStore.onCapacityGrew] callback.
  void _onStoreCapacityGrew(int newCapacity) {
    if (newCapacity > _visibleSubtreeSizeByNid.length) {
      final grown = Int32List(newCapacity);
      grown.setRange(
        0,
        _visibleSubtreeSizeByNid.length,
        _visibleSubtreeSizeByNid,
      );
      _visibleSubtreeSizeByNid = grown;
    }
    if (newCapacity > _fullExtentByNid.length) {
      final oldLen = _fullExtentByNid.length;
      final grown = Float64List(newCapacity);
      grown.setRange(0, oldLen, _fullExtentByNid);
      // Float64List defaults to 0.0; explicitly mark new slots as
      // unmeasured so callers can distinguish "never measured" from
      // "measured 0.0" via the < 0 sentinel.
      grown.fillRange(oldLen, newCapacity, _unmeasuredExtent);
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
    if (newCapacity > _isBulkMemberByNid.length) {
      final grown = Uint8List(newCapacity);
      grown.setRange(0, _isBulkMemberByNid.length, _isBulkMemberByNid);
      _isBulkMemberByNid = grown;
    }
    if (newCapacity > _opGroupKeyByNid.length) {
      final grown = List<TKey?>.filled(newCapacity, null);
      for (int i = 0; i < _opGroupKeyByNid.length; i++) {
        grown[i] = _opGroupKeyByNid[i];
      }
      _opGroupKeyByNid = grown;
    }
    if (newCapacity > _standaloneByNid.length) {
      final grown = List<AnimationState?>.filled(newCapacity, null);
      for (int i = 0; i < _standaloneByNid.length; i++) {
        grown[i] = _standaloneByNid[i];
      }
      _standaloneByNid = grown;
    }
    _slide.resizeForCapacity(newCapacity);
    _order.resizeIndex(newCapacity);
  }

  /// Per-nid count of currently-visible entries in the subtree rooted at
  /// this nid, **including this nid itself when it is in `_order`**.
  ///
  /// Invariant (debug-asserted): for every live nid,
  /// `_visibleSubtreeSizeByNid[nid] == (nid in _order ? 1 : 0)
  ///     + sum over children c of _visibleSubtreeSizeByNid[c]`.
  ///
  /// Maintained incrementally: every mutation that changes an
  /// individual nid's presence in `_order` flows through
  /// [_onNidVisibilityGained] / [_onNidVisibilityLost], each of which
  /// walks the parent chain applying a ±1 delta in O(depth). Bulk
  /// mutations that rebuild the order wholesale (see
  /// [_rebuildVisibleOrder]) suppress those per-event callbacks and
  /// recompute the whole array in a single O(N) post-order pass via
  /// [_rebuildVisibleSubtreeSizes].
  ///
  /// Replaces the O(visibleSubtreeSize) `_countVisibleDescendants` walks
  /// that previously appeared inside O(k) sibling loops in the insert
  /// hot paths, closing an O(k × subtree) cost on child populations.
  Int32List _visibleSubtreeSizeByNid = Int32List(0);

  /// Whether per-nid visibility callbacks should skip their incremental
  /// delta propagation. Set during bulk rebuilds
  /// ([_rebuildVisibleOrder]) that will recompute the derived state in
  /// a single O(N) pass afterwards.
  ///
  /// Read directly inside [_onNidVisibilityGained] / [_onNidVisibilityLost]
  /// and [_setParentKey]. **Writes go through
  /// [_runWithSubtreeSizeUpdatesSuppressed]** — never flip the flag by
  /// hand, since the wrapper preserves the prior value (re-entrant safe)
  /// and guarantees the flag is restored even if the wrapped body throws.
  bool _suppressSubtreeSizeUpdates = false;

  /// Runs [body] with [_suppressSubtreeSizeUpdates] forced to true,
  /// restoring the prior value (not necessarily false) on return.
  /// Use this around bulk order mutations whose per-nid callbacks
  /// would otherwise double-count cache updates.
  void _runWithSubtreeSizeUpdatesSuppressed(void Function() body) {
    final wasSuppressed = _suppressSubtreeSizeUpdates;
    _suppressSubtreeSizeUpdates = true;
    try {
      body();
    } finally {
      _suppressSubtreeSizeUpdates = wasSuppressed;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STRUCTURAL DELEGATORS
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Thin wrappers over [_store] that preserve the original `_adoptKey` /
  // `_setParentKey` / etc. names so the rest of the controller (and its
  // part files) need no rewrites at every call site. Logic that mixes
  // structural and visibility concerns (like the visible-subtree-size
  // adjustment in [_setParentKey]) stays here on the controller because
  // the controller is the only owner of the visibility-side state.

  /// Returns the nid for [key], allocating one if the key isn't registered.
  /// Idempotent for already-registered keys. Grows every dense per-nid
  /// array (structural and visibility) in lockstep so callers can safely
  /// index them at the returned nid.
  int _adoptKey(TKey key) {
    final result = _store.adopt(key);
    final nid = result.nid;
    if (!result.isNew) {
      return nid;
    }
    // Reset the controller-owned per-nid slots. The store has already
    // reset its own slots; visibility + animation arrays live here.
    _visibleSubtreeSizeByNid[nid] = 0;
    _order.clearIndexByNid(nid);
    _fullExtentByNid[nid] = _unmeasuredExtent;
    if (_isPendingDeletionByNid[nid] != 0) {
      // Recycled slot from a prior occupant that was pending-deletion;
      // counter would otherwise drift.
      _pendingDeletionCount--;
      _isPendingDeletionByNid[nid] = 0;
    }
    _opGroupKeyByNid[nid] = null;
    if (_standaloneByNid[nid] != null) {
      _standaloneByNid[nid] = null;
      _activeStandaloneNids.remove(nid);
    }
    _slide.clearForNid(nid);
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
  /// Refreshes the cached ancestors-expanded bit and propagates the change
  /// through [key]'s subtree, plus shifts [key]'s visible-subtree
  /// contribution from the old parent chain to the new one.
  void _setParentKey(TKey key, TKey? parent) {
    final nid = _nids[key]!;
    final oldParentNid = _store.parentByNid[nid];
    final newParentNid = parent == null ? _kNoParent : _nids[parent]!;
    if (oldParentNid != newParentNid &&
        !_suppressSubtreeSizeUpdates &&
        nid < _visibleSubtreeSizeByNid.length) {
      final delta = _visibleSubtreeSizeByNid[nid];
      if (delta != 0) {
        // Detach from the old ancestor chain, then attach to the new.
        // Walk from the parent (not from `nid` itself) because the
        // subtree rooted at `nid` has not changed its own composition.
        if (oldParentNid != _kNoParent) {
          _bumpVisibleSubtreeSizeFromSelf(oldParentNid, -delta);
        }
        if (newParentNid != _kNoParent) {
          _bumpVisibleSubtreeSizeFromSelf(newParentNid, delta);
        }
      }
    }
    _store.setParent(key, parent);
  }

  /// Releases the nid associated with [key] back to the pool. Clears every
  /// per-nid dense array slot so a future [_adoptKey] that recycles the nid
  /// sees a clean state.
  void _releaseNid(TKey key) {
    final nid = _store.release(key);
    if (nid == null) return;
    _visibleSubtreeSizeByNid[nid] = 0;
    _order.clearIndexByNid(nid);
    // Clear the animation-state slots. If the slot held pending-deletion,
    // the counter must be decremented; the helper handles it. The slot
    // value itself is reset so a later [_adoptKey] that recycles the nid
    // doesn't read stale data.
    if (_isPendingDeletionByNid[nid] != 0) {
      _isPendingDeletionByNid[nid] = 0;
      _pendingDeletionCount--;
    }
    _fullExtentByNid[nid] = _unmeasuredExtent;
    _opGroupKeyByNid[nid] = null;
    if (_standaloneByNid[nid] != null) {
      _standaloneByNid[nid] = null;
      _activeStandaloneNids.remove(nid);
    }
    _slide.clearForNid(nid);
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

  /// Root node IDs in order.
  final List<TKey> _roots = [];

  /// Flattened visible-order buffer: maintains the dense nid array plus the
  /// reverse nid → visible-index map. Mutations invalidate the full-extent
  /// prefix sum via the [onOrderMutated] callback, and per-nid
  /// add/remove callbacks drive the incremental maintenance of
  /// [_visibleSubtreeSizeByNid].
  late final VisibleOrderBuffer<TKey> _order = VisibleOrderBuffer<TKey>(
    registry: _nids,
    onOrderMutated: () => _scroll.invalidatePrefix(),
    onNidAdded: _onNidVisibilityGained,
    onNidRemoved: _onNidVisibilityLost,
  );

  /// Handler for "nid [nid] just entered the visible order." Propagates
  /// +1 up the ancestor chain to keep [_visibleSubtreeSizeByNid]
  /// consistent. Skips propagation during a bulk rebuild that will
  /// recompute the array from scratch afterwards.
  void _onNidVisibilityGained(int nid) {
    if (_suppressSubtreeSizeUpdates) return;
    _bumpVisibleSubtreeSizeFromSelf(nid, 1);
  }

  /// Handler for "nid [nid] just left the visible order." Propagates
  /// -1 up the ancestor chain.
  void _onNidVisibilityLost(int nid) {
    if (_suppressSubtreeSizeUpdates) return;
    _bumpVisibleSubtreeSizeFromSelf(nid, -1);
  }

  /// Adds [delta] to [_visibleSubtreeSizeByNid] at [startNid] and at
  /// every ancestor. Stops at the root (`_kNoParent`). O(depth).
  ///
  /// Used for both visibility changes (where [startNid] is the node
  /// whose order membership flipped) and reparenting (where [startNid]
  /// is the moved subtree's parent, and the moved subtree itself does
  /// not change its own size slot).
  void _bumpVisibleSubtreeSizeFromSelf(int startNid, int delta) {
    if (delta == 0) return;
    // Cache the parent-array reference locally so the loop doesn't pay a
    // store-getter call per ancestor walked. Same pattern as
    // [_purgeAndRemoveFromOrder]'s ancestor walk.
    final parentByNid = _store.parentByNid;
    int cur = startNid;
    while (cur != _kNoParent &&
        cur >= 0 &&
        cur < _visibleSubtreeSizeByNid.length) {
      // Refuse to mutate a freed slot. In debug, surface the violation;
      // in release, bail out — corrupting a freed slot causes downstream
      // visibility-cache bugs once the nid is recycled.
      if (_nids.keyOf(cur) == null) {
        assert(
          false,
          "_bumpVisibleSubtreeSizeFromSelf walked through freed nid $cur "
          "from start nid $startNid (delta=$delta)",
        );
        break;
      }
      final next = _visibleSubtreeSizeByNid[cur] + delta;
      assert(
        next >= 0,
        "visible-subtree-size would go negative at nid $cur "
        "(current=${_visibleSubtreeSizeByNid[cur]}, delta=$delta, "
        "key=${_nids.keyOf(cur)})",
      );
      _visibleSubtreeSizeByNid[cur] = next;
      cur = parentByNid[cur];
    }
  }

  /// Rebuilds [_visibleSubtreeSizeByNid] wholesale from the current
  /// tree structure and `_order` membership. O(N) via iterative
  /// pre-order walk followed by reverse-order summation (equivalent to
  /// iterative post-order). Used after bulk operations that rebuild
  /// the visible order in one shot.
  void _rebuildVisibleSubtreeSizes() {
    _visibleSubtreeSizeByNid.fillRange(0, _visibleSubtreeSizeByNid.length, 0);
    // Pre-order DFS to collect nids. Reverse pre-order is a valid
    // post-order for the purpose of summing children before parents.
    final preOrderNids = <int>[];
    final stack = <TKey>[];
    for (int i = _roots.length - 1; i >= 0; i--) {
      stack.add(_roots[i]);
    }
    final indexByNid = _order.indexByNid;
    while (stack.isNotEmpty) {
      final key = stack.removeLast();
      final nid = _nids[key];
      if (nid == null) {
        assert(false, "key $key has no nid during _rebuildVisibleSubtreeSizes");
        continue;
      }
      preOrderNids.add(nid);
      final children = _childListOf(key);
      if (children == null) continue;
      for (int i = children.length - 1; i >= 0; i--) {
        stack.add(children[i]);
      }
    }
    // Walk reverse pre-order. For each nid, its own contribution is 1
    // if it is currently in [_order], 0 otherwise. Children have
    // already been summed because they appear later in pre-order.
    for (int i = preOrderNids.length - 1; i >= 0; i--) {
      final nid = preOrderNids[i];
      final key = _nids.keyOf(nid);
      int size = indexByNid[nid] == VisibleOrderBuffer.kNotVisible ? 0 : 1;
      if (key != null) {
        final children = _childListOf(key);
        if (children != null) {
          for (final child in children) {
            final childNid = _nids[child];
            if (childNid != null) {
              size += _visibleSubtreeSizeByNid[childNid];
            }
          }
        }
      }
      _visibleSubtreeSizeByNid[nid] = size;
    }
  }

  /// Debug-only consistency check for [_visibleSubtreeSizeByNid].
  /// Exposed for fuzz tests via [debugAssertVisibleSubtreeSizeConsistency].
  @visibleForTesting
  void debugAssertVisibleSubtreeSizeConsistency() =>
      _assertVisibleSubtreeSizeConsistency();

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

  /// Debug-only consistency check for [_visibleSubtreeSizeByNid].
  /// Walks the tree and verifies every live nid's size slot equals the
  /// structural definition.
  void _assertVisibleSubtreeSizeConsistency() {
    assert(() {
      final indexByNid = _order.indexByNid;
      for (int nid = 0; nid < _nids.length; nid++) {
        final key = _nids.keyOf(nid);
        if (key == null) continue;
        int expected = indexByNid[nid] == VisibleOrderBuffer.kNotVisible
            ? 0
            : 1;
        final children = _childListOf(key);
        if (children != null) {
          for (final child in children) {
            final childNid = _nids[child];
            if (childNid != null) {
              expected += _visibleSubtreeSizeByNid[childNid];
            }
          }
        }
        if (_visibleSubtreeSizeByNid[nid] != expected) {
          throw StateError(
            "_visibleSubtreeSizeByNid[$nid] (key=$key) = "
            "${_visibleSubtreeSizeByNid[nid]}, expected $expected",
          );
        }
      }
      return true;
    }());
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ANIMATION STATE
  // ══════════════════════════════════════════════════════════════════════════

  /// Standalone animation state per nid. null = node is not animating
  /// via the standalone ticker. Reads / writes go through [_standaloneAt],
  /// [_setStandalone], [_clearStandalone] so the
  /// [_activeStandaloneNids] working set stays in sync — do NOT mutate
  /// directly.
  List<AnimationState?> _standaloneByNid = <AnimationState?>[];

  /// Live "set of nids that have a non-null _standaloneByNid slot."
  /// The standalone ticker iterates this set instead of scanning the
  /// whole array. Mutated in lockstep with every write to
  /// [_standaloneByNid] via the helpers below.
  final Set<int> _activeStandaloneNids = <int>{};

  /// Reads the standalone animation state for [key], or null when none.
  AnimationState? _standaloneAt(TKey key) {
    final nid = _nids[key];
    return nid == null ? null : _standaloneByNid[nid];
  }

  /// Sets the standalone animation state for [key]. Maintains
  /// [_activeStandaloneNids]. [key] must be registered.
  void _setStandalone(TKey key, AnimationState state) {
    final nid = _nids[key]!;
    final prev = _standaloneByNid[nid];
    _standaloneByNid[nid] = state;
    if (prev == null) _activeStandaloneNids.add(nid);
  }

  /// Clears the standalone animation state for [key]. Returns the prior
  /// state (null if absent). Maintains [_activeStandaloneNids].
  AnimationState? _clearStandalone(TKey key) {
    final nid = _nids[key];
    if (nid == null) return null;
    final prev = _standaloneByNid[nid];
    if (prev == null) return null;
    _standaloneByNid[nid] = null;
    _activeStandaloneNids.remove(nid);
    return prev;
  }

  /// Whether [key] has a standalone animation. O(1).
  bool _hasStandalone(TKey key) {
    final nid = _nids[key];
    return nid != null && _standaloneByNid[nid] != null;
  }

  /// Whether any nodes are animating via standalone ticker. O(1).
  bool get _hasAnyStandalone => _activeStandaloneNids.isNotEmpty;

  /// Ticker for standalone animations only.
  Ticker? _standaloneTicker;
  Duration? _lastStandaloneTickTime;

  /// The current bulk animation group (for expandAll/collapseAll).
  /// Only one bulk group is active at a time. New bulk operations
  /// reverse or replace this group.
  AnimationGroup<TKey>? _bulkAnimationGroup;

  /// Nid-indexed mirror of `_bulkAnimationGroup.members ∪ pendingRemoval`.
  /// Slot is `1` when the corresponding nid is in either set.
  /// Maintained incrementally by every site that mutates bulk membership;
  /// reset when the bulk group is created or disposed.
  Uint8List _isBulkMemberByNid = Uint8List(0);

  /// Adds [key] to `_bulkAnimationGroup.members` and updates the nid-keyed
  /// mirror. Caller is responsible for `_bumpBulkGen()` if needed.
  void _addBulkMember(TKey key) {
    final group = _bulkAnimationGroup;
    if (group == null) return;
    if (group.members.add(key)) {
      final nid = _nids[key];
      if (nid != null && nid < _isBulkMemberByNid.length) {
        _isBulkMemberByNid[nid] = 1;
      }
    }
  }

  /// Removes [key] from `_bulkAnimationGroup.members` and updates the
  /// mirror (only clears the slot when the key is also not in
  /// `pendingRemoval`).
  bool _removeBulkMember(TKey key) {
    final group = _bulkAnimationGroup;
    if (group == null) return false;
    final removed = group.members.remove(key);
    if (removed && !group.pendingRemoval.contains(key)) {
      final nid = _nids[key];
      if (nid != null && nid < _isBulkMemberByNid.length) {
        _isBulkMemberByNid[nid] = 0;
      }
    }
    return removed;
  }

  /// Adds [key] to `_bulkAnimationGroup.pendingRemoval` and updates the
  /// nid-keyed mirror.
  void _addBulkPending(TKey key) {
    final group = _bulkAnimationGroup;
    if (group == null) return;
    if (group.pendingRemoval.add(key)) {
      final nid = _nids[key];
      if (nid != null && nid < _isBulkMemberByNid.length) {
        _isBulkMemberByNid[nid] = 1;
      }
    }
  }

  /// Removes [key] from `_bulkAnimationGroup.pendingRemoval` and updates
  /// the mirror (only clears the slot when the key is also not in
  /// `members`).
  bool _removeBulkPending(TKey key) {
    final group = _bulkAnimationGroup;
    if (group == null) return false;
    final removed = group.pendingRemoval.remove(key);
    if (removed && !group.members.contains(key)) {
      final nid = _nids[key];
      if (nid != null && nid < _isBulkMemberByNid.length) {
        _isBulkMemberByNid[nid] = 0;
      }
    }
    return removed;
  }

  /// Clears `_bulkAnimationGroup.pendingRemoval` in one shot, dropping
  /// mirror bits for any keys that were ONLY in pendingRemoval (not also
  /// in members). In current code paths `pendingRemoval ⊆ members` for
  /// bulk groups, so in practice no mirror bit is cleared — but this
  /// helper is defensively correct under any future invariant change.
  void _clearBulkPending() {
    final group = _bulkAnimationGroup;
    if (group == null) return;
    for (final key in group.pendingRemoval) {
      if (!group.members.contains(key)) {
        final nid = _nids[key];
        if (nid != null && nid < _isBulkMemberByNid.length) {
          _isBulkMemberByNid[nid] = 0;
        }
      }
    }
    group.pendingRemoval.clear();
  }

  /// Per-operation animation groups (for individual expand/collapse).
  /// Key is the operation key (the node whose expand/collapse created the group).
  final Map<TKey, OperationGroup<TKey>> _operationGroups = {};

  // ──────── Per-node animation state (dense ECS arrays) ────────
  //
  // Five nid-indexed arrays hold every per-node animation field. Reads
  // and writes go through the accessor methods below; do NOT touch the
  // arrays directly outside those helpers, since several have
  // working-set invariants (the two `_active*Nids` sets must stay in
  // sync with their backing arrays). Capacity is grown in lockstep with
  // NodeStore via [_onStoreCapacityGrew]; reset via [_clear].

  /// Cached measured full extent. Sentinel `-1.0` = unmeasured.
  /// Float64List default is 0.0, so [_onStoreCapacityGrew] and
  /// [_adoptKey] explicitly fill new slots with `_unmeasuredExtent`.
  /// Note: a measured extent of exactly 0.0 is a valid value (zero-height
  /// row); the < 0 sentinel keeps that distinction.
  Float64List _fullExtentByNid = Float64List(0);

  /// Sentinel value in [_fullExtentByNid] meaning "never measured."
  /// Re-exported as a controller constant rather than reusing
  /// [_unknownExtent] from the animation part file so this file's
  /// initialization paths don't depend on the part-file load order.
  static const double _unmeasuredExtent = -1.0;

  /// Pending-deletion flag. 0 = not pending, 1 = pending.
  Uint8List _isPendingDeletionByNid = Uint8List(0);

  /// Counter mirroring how many slots in [_isPendingDeletionByNid]
  /// currently hold 1. Maintained by every set/clear so callers that
  /// need the O(1) "any pending?" fast-skip (`liveRootKeys`,
  /// `getLiveChildren`, `_sortedIndex`) keep their gate cheap.
  int _pendingDeletionCount = 0;

  /// Operation-group key for each nid. null = node is not a member of
  /// any operation group. Stored as `List<TKey?>` because TKey is generic.
  List<TKey?> _opGroupKeyByNid = <TKey?>[];

  /// O(1) "is [key] pending deletion?" check.
  bool _isPendingDeletion(TKey key) {
    final nid = _nids[key];
    return nid != null && _isPendingDeletionByNid[nid] != 0;
  }

  /// Marks [key] as pending deletion, maintaining [_pendingDeletionCount].
  void _markPendingDeletion(TKey key) {
    final nid = _nids[key];
    if (nid == null) return;
    if (_isPendingDeletionByNid[nid] == 0) {
      _isPendingDeletionByNid[nid] = 1;
      _pendingDeletionCount++;
    }
  }

  /// Clears the pending-deletion flag for [key], maintaining
  /// [_pendingDeletionCount].
  void _clearPendingDeletion(TKey key) {
    final nid = _nids[key];
    if (nid == null) return;
    if (_isPendingDeletionByNid[nid] != 0) {
      _isPendingDeletionByNid[nid] = 0;
      _pendingDeletionCount--;
    }
  }

  /// Returns the operation-group key [key] currently belongs to, or null.
  TKey? _operationGroupOf(TKey key) {
    final nid = _nids[key];
    return nid == null ? null : _opGroupKeyByNid[nid];
  }

  /// Whether [key] is currently a member of any operation group.
  bool _hasOperationGroup(TKey key) {
    final nid = _nids[key];
    return nid != null && _opGroupKeyByNid[nid] != null;
  }

  /// Sets [key]'s operation-group membership to [opKey].
  void _setOperationGroup(TKey key, TKey opKey) {
    final nid = _nids[key];
    if (nid == null) return;
    _opGroupKeyByNid[nid] = opKey;
  }

  /// Clears [key]'s operation-group membership and returns the previous
  /// value (null if it had no membership).
  TKey? _clearOperationGroup(TKey key) {
    final nid = _nids[key];
    if (nid == null) return null;
    final prev = _opGroupKeyByNid[nid];
    if (prev != null) {
      _opGroupKeyByNid[nid] = null;
    }
    return prev;
  }

  /// Returns the cached full extent for [key], or null if never measured.
  double? _fullExtentOf(TKey key) {
    final nid = _nids[key];
    if (nid == null) return null;
    final ext = _fullExtentByNid[nid];
    return ext < 0 ? null : ext;
  }

  /// Sets the cached full extent for [key]. Returns the previous value
  /// (null if previously unmeasured).
  double? _setFullExtentRaw(TKey key, double extent) {
    final nid = _nids[key];
    if (nid == null) return null;
    final prev = _fullExtentByNid[nid];
    _fullExtentByNid[nid] = extent;
    return prev < 0 ? null : prev;
  }

  /// Clears the cached full extent for [key]. Returns the previous value
  /// (null if previously unmeasured).
  double? _clearFullExtent(TKey key) {
    final nid = _nids[key];
    if (nid == null) return null;
    final prev = _fullExtentByNid[nid];
    if (prev < 0) return null;
    _fullExtentByNid[nid] = _unmeasuredExtent;
    return prev;
  }

  /// Paint-only FLIP slide engine. Owns every piece of slide state plus
  /// the shared [Ticker] driving progress. Hot-path getters (
  /// [getSlideDelta], [getSlideDeltaNid], [hasActiveSlides],
  /// [maxActiveSlideAbsDelta]) and the entry point
  /// [animateSlideFromOffsets] delegate here. See [SlideAnimationEngine].
  late final SlideAnimationEngine<TKey> _slide = SlideAnimationEngine<TKey>(
    vsync: _vsync,
    nids: _nids,
    onTick: _notifyAnimationListeners,
  );

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

  /// Listeners notified on every animation tick (layout-only updates).
  final List<VoidCallback> _animationListeners = [];

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

  /// Default extent for nodes that haven't been measured yet.
  static const double defaultExtent = 48.0;

  /// Monotonically increasing counter incremented whenever the visible
  /// order is structurally mutated (nodes added, removed, or reordered).
  /// Used by the render object to detect structure changes even when the
  /// visible node count stays the same.
  int _structureGeneration = 0;
  int get structureGeneration => _structureGeneration;

  /// Scratch set reused to avoid per-frame allocation.
  final Set<TKey> _keysToRemoveScratch = {};

  /// Scroll orchestrator. Owns the full-extent prefix-sum cache plus the
  /// four scroll-API methods. See [ScrollOrchestrator].
  late final ScrollOrchestrator<TKey, TData> _scroll =
      ScrollOrchestrator<TKey, TData>(controller: this, vsync: _vsync);

  /// Monotonically increasing counter bumped on any mutation to
  /// animation-state membership (standalone animations, operation-group
  /// members or pendingRemoval, bulk-group members or pendingRemoval).
  /// Serves as the O(1) cache signature for [_animatingKeysCache] and
  /// [_firstAnimatingIndexCacheVal] so per-frame queries like
  /// [isAnimating] don't rescan every animating node per call.
  ///
  /// All animation-state mutations flow through [_bumpAnimGen] (direct or
  /// via [_bumpBulkGen], which also bumps [_bulkAnimationGeneration]).
  int _animationGeneration = 0;

  /// Union of every currently-animating key across standalone, operation,
  /// and bulk groups. Rebuilt on demand when [_animationGeneration] changes.
  Set<TKey>? _animatingKeysCache;
  int _animatingKeysCacheGen = -1;

  /// Nid-indexed mirror of [_ensureAnimatingKeys]'s result. Slot is `1`
  /// when the corresponding nid is animating in any source (standalone,
  /// operation group, bulk group). Rebuilt lazily alongside
  /// [_animatingKeysCache] when [_animationGeneration] changes.
  Uint8List _isAnimatingByNid = Uint8List(0);

  /// Nid-indexed mirror of [isExiting]. Slot is `1` when the corresponding
  /// nid is exiting in any source (pending-removal in a bulk or operation
  /// group, or a standalone exit animation). Rebuilt alongside
  /// [_isAnimatingByNid].
  Uint8List _isExitingByNid = Uint8List(0);

  /// Nids written into [_isAnimatingByNid] by the last
  /// [_ensureAnimatingKeys] rebuild. Drives the sparse clear at the start
  /// of each rebuild — zeroing only the slots actually dirtied avoids an
  /// O(nidCapacity) memset on every animation-generation bump. Same pattern
  /// as `_writtenCacheRegionNids` in `RenderSliverTree`.
  final List<int> _writtenAnimatingNids = <int>[];

  /// Nids written into [_isExitingByNid] by the last rebuild.
  final List<int> _writtenExitingNids = <int>[];

  /// Cached result of [computeFirstAnimatingVisibleIndex]. Depends on both
  /// animation state and the visible order, so the cache key combines
  /// [_animationGeneration] with [_structureGeneration].
  int _firstAnimatingIndexCacheSig = -1;
  int _firstAnimatingIndexCacheVal = 0;

  /// Bumps [_animationGeneration] so the next call to [_ensureAnimatingKeys]
  /// or [computeFirstAnimatingVisibleIndex] rebuilds its cache. Must be
  /// called from every path that mutates standalone, operation-group, or
  /// bulk-group membership. Paths that mutate bulk state use [_bumpBulkGen].
  void _bumpAnimGen() {
    _animationGeneration++;
  }

  /// Bumps both the broad [_animationGeneration] and the bulk-specific
  /// [_bulkAnimationGeneration]. Call from any path that mutates
  /// [_bulkAnimationGroup]'s identity or membership.
  void _bumpBulkGen() {
    _animationGeneration++;
    _bulkAnimationGeneration++;
  }

  /// Returns a set of every currently-animating key. Rebuilt on demand when
  /// [_animationGeneration] changes. Also refreshes the nid-keyed mirrors
  /// [_isAnimatingByNid] / [_isExitingByNid] using sparse-tracking
  /// cleanup — O(animating count) per rebuild, not O(nidCapacity).
  Set<TKey> _ensureAnimatingKeys() {
    final cached = _animatingKeysCache;
    if (cached != null && _animationGeneration == _animatingKeysCacheGen) {
      return cached;
    }
    // Sparse clear of slots written by the previous rebuild. Bounded by
    // the prior frame's animating count, not by nidCapacity.
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
    // Use the mirror itself as a "visited" guard to avoid duplicate
    // entries in `_writtenAnimatingNids` / `_writtenExitingNids` when
    // the same nid appears in multiple sources (defensive — the
    // existing controller invariants say a node lives in at most one
    // source at a time, but the sparse-track lists must remain
    // duplicate-free for the consistency assertion to be exact).
    if (_hasAnyStandalone) {
      for (final nid in _activeStandaloneNids) {
        set.add(_nids.keyOfUnchecked(nid));
        if (_isAnimatingByNid[nid] == 0) {
          _isAnimatingByNid[nid] = 1;
          _writtenAnimatingNids.add(nid);
        }
        if (_standaloneByNid[nid]!.type == AnimationType.exiting &&
            _isExitingByNid[nid] == 0) {
          _isExitingByNid[nid] = 1;
          _writtenExitingNids.add(nid);
        }
      }
    }
    if (_operationGroups.isNotEmpty) {
      for (final g in _operationGroups.values) {
        for (final key in g.members.keys) {
          set.add(key);
          final nid = _nids[key];
          if (nid == null) continue;
          if (_isAnimatingByNid[nid] == 0) {
            _isAnimatingByNid[nid] = 1;
            _writtenAnimatingNids.add(nid);
          }
          if (g.pendingRemoval.contains(key) && _isExitingByNid[nid] == 0) {
            _isExitingByNid[nid] = 1;
            _writtenExitingNids.add(nid);
          }
        }
      }
    }
    final bulk = _bulkAnimationGroup;
    if (bulk != null) {
      // Mirrors the existing semantics: only bulk.members go into the
      // animating set (not pendingRemoval — pendingRemoval ⊆ members for
      // bulk groups, see expandAll / collapseAll invariants).
      for (final key in bulk.members) {
        set.add(key);
        final nid = _nids[key];
        if (nid == null) continue;
        if (_isAnimatingByNid[nid] == 0) {
          _isAnimatingByNid[nid] = 1;
          _writtenAnimatingNids.add(nid);
        }
      }
      for (final key in bulk.pendingRemoval) {
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

  /// Hot-path equivalent of [isAnimating]: O(1) array read instead of a
  /// HashMap-keyed Set lookup. Caller must guarantee [nid] is live and
  /// within range.
  bool isAnimatingNid(int nid) {
    _ensureAnimatingKeys();
    return _isAnimatingByNid[nid] != 0;
  }

  /// Hot-path equivalent of [isExiting].
  bool isExitingNid(int nid) {
    _ensureAnimatingKeys();
    return _isExitingByNid[nid] != 0;
  }

  /// Builds a fresh synthetic entering state for [getAnimationState] to return
  /// for operation or bulk group members that are expanding. A fresh object
  /// per call avoids any cross-controller corruption if an external caller
  /// mutates the returned [AnimationState].
  static AnimationState _buildSyntheticEnteringState() {
    return AnimationState(
      type: AnimationType.entering,
      startExtent: 0,
      targetExtent: 0,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC QUERIES
  // ══════════════════════════════════════════════════════════════════════════

  /// The flattened list of visible node IDs in render order.
  ///
  /// Returns a read-only live view over the internal nid-indexed buffer.
  /// Mutations to the visible order are reflected automatically.
  late final List<TKey> visibleNodes = _VisibleNodesView<TKey, TData>(this);

  /// Number of visible nodes.
  int get visibleNodeCount => _order.length;

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
  int visibleNidAt(int visibleIndex) => _order.orderNids[visibleIndex];

  /// Read-only view over the visible-order nid buffer for hot-path
  /// consumers that walk all visible positions and want to skip the
  /// per-position [visibleNidAt] dispatch. The underlying buffer's
  /// length may exceed [visibleNodeCount] — only the first N entries
  /// are valid. The buffer itself is mutated in place by structural
  /// changes; callers must not retain the reference across mutations.
  Int32List get orderNidsView => _order.orderNids;

  /// Visible-order index for the live nid [nid], or
  /// [VisibleOrderBuffer.kNotVisible] when [nid] is not currently in the
  /// visible order. O(1) typed-data read; no [TKey] hash. Hot-path
  /// equivalent of `_order.indexByNid[nid]`.
  ///
  /// Caller must guarantee [nid] is live and within range.
  int visibleIndexOfNid(int nid) => _order.indexByNid[nid];

  /// Depth for [nid] (0 for roots). No [TKey] hash. [nid] must be live.
  int depthOfNid(int nid) => _store.depthByNid[nid];

  /// Estimated full extent for the live [nid] — measured value when
  /// available, [defaultExtent] otherwise. Hot-path equivalent of
  /// [getEstimatedExtent] that avoids the [TKey]→nid hash. Caller must
  /// guarantee [nid] is live and within range.
  double getEstimatedExtentNid(int nid) {
    final ext = _fullExtentByNid[nid];
    return ext < 0 ? defaultExtent : ext;
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
  /// [_ensureAnimatingKeys] cache; **do NOT mutate** — same convention as
  /// [orderNidsView]. Iteration is stable within one frame.
  Set<TKey> get currentlyAnimatingKeys => _ensureAnimatingKeys();

  /// The measured full extent for [key], or null if [key] has never been
  /// laid out. Distinct from [getEstimatedExtent], which falls back to
  /// [defaultExtent] for unmeasured nodes.
  double? getMeasuredExtent(TKey key) => _fullExtentOf(key);

  /// Captures an opaque token identifying the current operation group at
  /// [operationKey], or null if no group is installed there. The token is
  /// only valid as input to [isOperationGroupSame] — its concrete type is
  /// not part of the public contract and may change.
  Object? captureOperationGroupToken(TKey operationKey) =>
      _operationGroups[operationKey];

  /// Whether the operation group at [operationKey] is identity-equal to
  /// the one captured by [captureOperationGroupToken]. False once the
  /// group has been replaced (re-expand cycle) or removed (animation
  /// settled). Pass `null` token to ask "was there ever one?" — always
  /// false on null.
  bool isOperationGroupSame(TKey operationKey, Object? token) =>
      token != null && identical(_operationGroups[operationKey], token);

  /// Forwards to [_notifyAnimationListeners] so the scroll orchestrator's
  /// internal `AnimationController` (`scrollProgress`) can fire ticks
  /// through the controller's listener channel without exposing
  /// [_notifyAnimationListeners] publicly.
  void notifyAnimationListenersForScroll() => _notifyAnimationListeners();

  /// Current animated extent for the live [nid]. Hot-path equivalent of
  /// [getCurrentExtent]; resolves the chain bulk → operation-group →
  /// standalone → fullExtent. Caller must guarantee [nid] is live and
  /// within range.
  double getCurrentExtentNid(int nid) {
    final fullRaw = _fullExtentByNid[nid];
    final full = fullRaw < 0 ? defaultExtent : fullRaw;
    // 1. Bulk — nid-keyed mirror skips the keyOfUnchecked + Set.contains
    // probe. Under the existing pendingRemoval ⊆ members invariant the
    // mirror returns the same answer as `bulk.members.contains(key)`.
    final bulk = _bulkAnimationGroup;
    if (bulk != null && _isBulkMemberByNid[nid] != 0) {
      return full * bulk.value;
    }
    // 2. Operation group
    final opKey = _opGroupKeyByNid[nid];
    if (opKey != null) {
      final group = _operationGroups[opKey];
      if (group != null) {
        final key = _nids.keyOfUnchecked(nid);
        final member = group.members[key];
        if (member != null) {
          return member.computeExtent(group.curvedValue, full);
        }
      }
    }
    // 3. Standalone
    final animation = _standaloneByNid[nid];
    if (animation == null) return full;
    final t = animationCurve.transform(animation.progress.clamp(0.0, 1.0));
    if (animation.targetExtent == _unknownExtent) {
      return animation.type == AnimationType.entering
          ? full * t
          : full * (1.0 - t);
    }
    return lerpDouble(animation.startExtent, animation.targetExtent, t)!;
  }

  /// Slide delta for the live [nid] (paint-only FLIP offset), or 0.0 when
  /// the node is not currently sliding. Hot-path equivalent of
  /// [getSlideDelta] — read every paint, hit-test, and transform call
  /// for visible rows, so saving the [TKey]→nid hash matters.
  double getSlideDeltaNid(int nid) => _slide.deltaForNid(nid);

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
  void markSlidePreserveProgress(TKey key) =>
      _slide.markPreserveProgress(key);

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
  bool isVisible(TKey key) => _order.contains(key);

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
    if (_pendingDeletionCount == 0) return List<TKey>.of(_roots);
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
    if (_pendingDeletionCount == 0) return List<TKey>.of(full);
    final result = <TKey>[];
    for (final k in full) {
      if (!_isPendingDeletion(k)) result.add(k);
    }
    return result;
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
  bool get hasActiveAnimations =>
      _hasAnyStandalone ||
      _operationGroups.isNotEmpty ||
      (_bulkAnimationGroup != null && !_bulkAnimationGroup!.isEmpty);

  /// Whether any FLIP slide animations are currently active.
  ///
  /// Deliberately separate from [hasActiveAnimations]: slide is paint-only
  /// and must not be mixed into the sticky-throttle / eviction-deferral
  /// signal that [hasActiveAnimations] drives. The sliver element routes
  /// slide-only ticks to [RenderObject.markNeedsPaint] rather than
  /// [RenderObject.markNeedsLayout] based on this flag.
  bool get hasActiveSlides => _slide.hasActive;

  /// Whether any in-flight slide has a non-zero X-axis component
  /// (depth-changing reparent). Hot-path render code uses this to skip
  /// per-row X-delta reads when no X-axis work is in flight — the common
  /// case, since most reorders are same-depth.
  bool get hasActiveXSlides => _slide.hasActiveX;

  /// Maximum |currentDelta| across every active slide entry, or 0.0 when
  /// no slides are active.
  ///
  /// The render object uses this as a "slide overreach" to widen its build
  /// and iteration ranges during a FLIP slide: a row whose *structural* y
  /// is outside the viewport can still be painted inside the viewport if
  /// its slide delta translates it there, and conversely a row whose
  /// structural y is inside the viewport can translate out. Both ranges
  /// (build window in performLayout, iteration window in paint/hit-test)
  /// need to extend by this amount on each side to cover the displaced
  /// rows — otherwise a swap of two large subtrees paints a visible gap
  /// where a sliding row should appear.
  ///
  /// Shrinks toward 0.0 as the slide progresses (since entries'
  /// currentDelta lerps to 0), so the transient overbuild contracts with
  /// the animation.
  double get maxActiveSlideAbsDelta => _slide.maxAbsDelta;

  /// Current slide delta for [key] in scroll-space y, or 0.0 if the node is
  /// not currently sliding. Read by [RenderSliverTree.paint],
  /// [RenderSliverTree.applyPaintTransform], and the hit-test path on
  /// every frame (no caching — staleness-safe under tick-without-paint).
  double getSlideDelta(TKey key) => _slide.deltaForKey(key);

  /// True when a bulk animation group is currently active and has members
  /// animating in either direction.
  ///
  /// Used by the render object to gate its scalar-offset fast path.
  bool get isBulkAnimating {
    final g = _bulkAnimationGroup;
    if (g == null) return false;
    return g.members.isNotEmpty || g.pendingRemoval.isNotEmpty;
  }

  /// Current animation value of the bulk animation group, or 0.0 if none.
  double get bulkAnimationValue => _bulkAnimationGroup?.value ?? 0.0;

  /// Whether [key] is a member of the bulk animation group (either active
  /// or pending removal at animation end).
  bool isBulkMember(TKey key) {
    final g = _bulkAnimationGroup;
    if (g == null) return false;
    return g.members.contains(key) || g.pendingRemoval.contains(key);
  }

  /// Whether any non-bulk animations (operation groups or standalone) are
  /// currently active. When false and [isBulkAnimating] is true, the render
  /// object can use its scalar-offset fast path for the whole frame.
  bool get hasOpGroupAnimations =>
      _operationGroups.isNotEmpty || _hasAnyStandalone;

  /// Monotonic counter that bumps whenever the bulk animation group is
  /// created, destroyed, or its member set changes. The render object uses
  /// this to detect when its cached per-position offset cumulatives are stale.
  int get bulkAnimationGeneration => _bulkAnimationGeneration;
  int _bulkAnimationGeneration = 0;

  /// Singleton "no bulk animation active" snapshot. Resolves to the
  /// const-shared sentinel inside [BulkAnimationData] — no allocation per
  /// call. Cached on the controller so the common case (no bulk animation
  /// in flight) costs zero allocation per layout.
  late final BulkAnimationData<TKey> _inactiveBulkData =
      BulkAnimationData.inactive<TKey>();

  /// Captures every per-frame bulk-animation field the render object reads
  /// during a single layout — `isValid` (formerly [isBulkAnimating]),
  /// `value` (formerly [bulkAnimationValue]), `generation` (formerly
  /// [bulkAnimationGeneration]), `memberCount`, and a per-key membership
  /// query (formerly [isBulkMember]) — into one snapshot.
  ///
  /// Render-layer hot paths that previously called four scattered getters
  /// per layout (with `isBulkMember` invoked once per visible node inside
  /// the cumulative rebuild) can now fetch the snapshot once and read it
  /// for the rest of the frame, restoring the cohesion the four-getter
  /// surface lost.
  ///
  /// Per-layout cost: zero allocation when no bulk group is active
  /// (returns the cached [_inactiveBulkData] sentinel); one snapshot
  /// allocation when active. The snapshot holds direct references to the
  /// group's `members` and `pendingRemoval` sets — no union or copy — so
  /// `containsMember` runs in O(1) without per-frame set construction.
  ///
  /// The returned snapshot captures the set references at call time. A
  /// subsequent mutation to the controller's internal bulk group will be
  /// reflected through the held set references; callers that need a
  /// stable view across mutations must copy the relevant fields out.
  BulkAnimationData<TKey> bulkAnimationData() {
    final group = _bulkAnimationGroup;
    if (group == null ||
        (group.members.isEmpty && group.pendingRemoval.isEmpty)) {
      return _inactiveBulkData;
    }
    return BulkAnimationData.snapshot<TKey>(
      value: group.value,
      generation: _bulkAnimationGeneration,
      members: group.members,
      pendingRemoval: group.pendingRemoval,
      bulkMemberByNid: _isBulkMemberByNid,
    );
  }

  /// Returns the smallest [_visibleOrder] index among all currently-animating
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
    final sig = _animationGeneration ^ (_structureGeneration * 2654435761);
    if (sig == _firstAnimatingIndexCacheSig &&
        _firstAnimatingIndexCacheVal <= _order.length) {
      return _firstAnimatingIndexCacheVal;
    }
    // Force the mirror rebuild so `_writtenAnimatingNids` reflects the
    // current generation. The discarded return value is intentional —
    // we only need the side effect of populating the sparse-tracked list.
    _ensureAnimatingKeys();
    int min = _order.length;
    final indexByNid = _order.indexByNid;
    for (final nid in _writtenAnimatingNids) {
      final idx = indexByNid[nid];
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
    if (_bulkAnimationGroup == null) {
      debugPrint('TreeController: No bulk animation group');
      return;
    }
    final controller = _bulkAnimationGroup!.controller;
    debugPrint(
      'TreeController bulk animation: '
      'value=${_bulkAnimationGroup!.value.toStringAsFixed(3)}, '
      'controllerValue=${controller.value.toStringAsFixed(3)}, '
      'status=${controller.status}, '
      'members=${_bulkAnimationGroup!.members.length}, '
      'pendingRemoval=${_bulkAnimationGroup!.pendingRemoval.length}',
    );
  }

  /// Whether the given node is currently animating. O(1) via the cached
  /// [_ensureAnimatingKeys] set (rebuilt lazily when animation membership
  /// changes).
  bool isAnimating(TKey key) {
    if (!hasActiveAnimations) return false;
    return _ensureAnimatingKeys().contains(key);
  }

  /// Gets the animation state for a node, or null if not animating.
  ///
  /// Returns the standalone state if present, a synthetic entering state
  /// for operation group members that are expanding, or null for bulk/
  /// collapsing groups.
  AnimationState? getAnimationState(TKey key) {
    // 1. Standalone animations
    final standalone = _standaloneAt(key);
    if (standalone != null) return standalone;

    // 2. Operation group
    final groupKey = _operationGroupOf(key);
    if (groupKey != null) {
      final group = _operationGroups[groupKey];
      if (group != null && !group.pendingRemoval.contains(key)) {
        final status = group.controller.status;
        if (status == AnimationStatus.forward ||
            status == AnimationStatus.completed) {
          return _buildSyntheticEnteringState();
        }
      }
      return null;
    }

    // 3. Bulk group — synthesize entering state for members advancing forward
    // so consumers (e.g. sticky header anchoring) can detect entering nodes.
    final bulk = _bulkAnimationGroup;
    if (bulk != null &&
        bulk.members.contains(key) &&
        !bulk.pendingRemoval.contains(key)) {
      final status = bulk.controller.status;
      if (status == AnimationStatus.forward ||
          status == AnimationStatus.completed) {
        return _buildSyntheticEnteringState();
      }
    }
    return null;
  }

  /// Whether the given node is currently exiting (animating out).
  ///
  /// Exiting nodes should not receive hit tests or user interactions.
  bool isExiting(TKey key) {
    // Check bulk group pending removal
    if (_bulkAnimationGroup?.pendingRemoval.contains(key) == true) return true;
    // Check operation group pending removal
    final groupKey = _operationGroupOf(key);
    if (groupKey != null) {
      final group = _operationGroups[groupKey];
      if (group != null && group.pendingRemoval.contains(key)) return true;
    }
    // Check standalone animations
    final animation = _standaloneAt(key);
    return animation != null && animation.type == AnimationType.exiting;
  }

  /// Gets the estimated full extent for a node.
  ///
  /// Returns the cached measured extent if available, otherwise [defaultExtent].
  double getEstimatedExtent(TKey key) {
    return _fullExtentOf(key) ?? defaultExtent;
  }

  /// Gets the current extent for a node, accounting for animation.
  double getCurrentExtent(TKey key) {
    return getAnimatedExtent(key, _fullExtentOf(key) ?? defaultExtent);
  }

  /// Gets the animated extent for a node.
  ///
  /// If the node is animating, returns the interpolated extent.
  /// Otherwise returns [fullExtent].
  double getAnimatedExtent(TKey key, double fullExtent) {
    // 1. Check bulk animation group
    if (_bulkAnimationGroup?.members.contains(key) == true) {
      return fullExtent * _bulkAnimationGroup!.value;
    }

    // 2. Check operation group
    final groupKey = _operationGroupOf(key);
    if (groupKey != null) {
      final group = _operationGroups[groupKey];
      if (group != null) {
        final member = group.members[key];
        if (member != null) {
          return member.computeExtent(group.curvedValue, fullExtent);
        }
      }
    }

    // 3. Check standalone animations
    final animation = _standaloneAt(key);
    if (animation == null) return fullExtent;

    final t = animationCurve.transform(animation.progress.clamp(0.0, 1.0));
    if (animation.targetExtent == _unknownExtent) {
      return animation.type == AnimationType.entering
          ? fullExtent * t
          : fullExtent * (1.0 - t);
    }
    return lerpDouble(animation.startExtent, animation.targetExtent, t)!;
  }

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
  /// Composes with an in-flight slide: if [key] already has an entry,
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
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.easeOutCubic,
    double maxSlideDistance = double.infinity,
  }) => _slide.animateFromOffsets(
    priorOffsets,
    currentOffsets,
    duration: duration,
    curve: curve,
    maxSlideDistance: maxSlideDistance,
    structuralAnimationsDisabled: animationDuration == Duration.zero,
  );

  /// Stores the measured full extent for a node.
  ///
  /// Called by the render object after laying out a child.
  void setFullExtent(TKey key, double extent) {
    final oldExtent = _fullExtentOf(key);

    // Check operation group member — resolve unknown extents
    final groupKey = _operationGroupOf(key);
    if (groupKey != null) {
      final group = _operationGroups[groupKey];
      if (group != null) {
        final member = group.members[key];
        if (member != null) {
          if (member.targetExtent == _unknownExtent) {
            final status = group.controller.status;
            if (status == AnimationStatus.forward ||
                status == AnimationStatus.completed) {
              member.targetExtent = extent;
            }
          } else if (oldExtent != extent && !member.targetIsCaptured) {
            // Update only when targetExtent is the natural full
            // reference. Captured targets (set when this member was
            // pulled in from a mid-flight standalone or other source)
            // represent the visual extent at capture time, not the
            // natural full size — overwriting them here would make a
            // freshly-inserted row caught at progress=0 mid-enter
            // suddenly read at the full natural size during the
            // parent's collapse.
            //
            // targetExtent is the "fully expanded" reference (value=1);
            // startExtent is always 0 (fully collapsed). Update targetExtent
            // regardless of direction — during reverse (collapsing), setting
            // startExtent = extent would make the lerp return `extent` at
            // value=0 instead of 0, so the node would never collapse to zero.
            member.targetExtent = extent;
          }
        }
      }
      _setFullExtentRaw(key, extent);
      if (oldExtent != extent) _scroll.invalidatePrefix();
      return;
    }

    if (oldExtent == extent) {
      // Still resolve unknown targets even when extent matches.
      final animation = _standaloneAt(key);
      if (animation != null && animation.targetExtent == _unknownExtent) {
        if (animation.type == AnimationType.entering) {
          animation.targetExtent = extent;
          animation.updateExtent(animationCurve);
        }
      }
      return;
    }
    _setFullExtentRaw(key, extent);
    _scroll.invalidatePrefix();
    // If node is animating with unknown target, update the animation
    final animation = _standaloneAt(key);
    if (animation != null && animation.targetExtent == _unknownExtent) {
      // Now we know the real extent - update the animation state
      if (animation.type == AnimationType.entering) {
        animation.targetExtent = extent;
        animation.updateExtent(animationCurve);
      }
    }
    // Also update if extent changed and node is animating
    else if (animation != null) {
      if (animation.type == AnimationType.entering) {
        animation.targetExtent = extent;
        animation.updateExtent(animationCurve);
      }
      // For exiting animations, startExtent is historical (the extent at the
      // moment the exit began, potentially captured mid-transition from an
      // earlier source). Overwriting it with the freshly-measured full extent
      // would retroactively rewrite where the exit started and jump the row
      // forward on the next tick. Let the exit run from its original
      // startExtent to 0 without interference.
    }
  }

  /// Gets the index of a node in the visible order, or -1 if not visible.
  int getVisibleIndex(TKey key) {
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
  int ensureAncestorsExpanded(TKey key) =>
      _scroll.ensureAncestorsExpanded(key);

  /// Animates [scrollController] to reveal [key] in its attached viewport.
  ///
  /// [ancestorExpansion] controls how collapsed ancestors of [key] are
  /// handled:
  /// - [AncestorExpansionMode.none]: ancestors are not expanded. If any
  ///   ancestor of [key] is collapsed, returns false without scrolling.
  /// - [AncestorExpansionMode.immediate] (default): ancestors are expanded
  ///   synchronously (no animation) before the scroll begins, so layout is
  ///   already settled when [scrollController] starts moving.
  /// - [AncestorExpansionMode.animated]: ancestors animate open while the
  ///   scroll runs concurrently. Each animation tick the scroll target is
  ///   re-derived from the current animated offsets so it stays glued to
  ///   the moving target. A precise jump lands on the settled offset once
  ///   both finish. In this mode the concurrent phase runs for
  ///   `max(duration, animationDuration)` so both the expansion and the
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
  /// Returns true if a scroll was issued, false if [key] could not be
  /// resolved or [scrollController] has no attached position.
  Future<bool> animateScrollToKey(
    TKey key, {
    required ScrollController scrollController,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
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
  // ANIMATION LISTENERS
  // ══════════════════════════════════════════════════════════════════════════

  /// Registers a callback that fires on every animation tick.
  ///
  /// Unlike [addListener], these callbacks fire for pure animation progress
  /// updates (no structural changes). Use this to trigger repaint/relayout
  /// without scheduling garbage collection.
  void addAnimationListener(VoidCallback listener) {
    _animationListeners.add(listener);
  }

  /// Removes a previously registered animation listener.
  void removeAnimationListener(VoidCallback listener) {
    _animationListeners.remove(listener);
  }

  void _notifyAnimationListeners() {
    // Snapshot before iteration so a listener that removes itself during
    // the callback doesn't trigger ConcurrentModificationError.
    final listeners = List<VoidCallback>.of(_animationListeners);
    for (final listener in listeners) {
      listener();
    }
  }

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
  /// Animation tick notifications ([addAnimationListener]) are not affected
  /// and continue to fire in real time.
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
    if (_pendingDeletionCount == 0) {
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
  void insertRoot(
    TreeNode<TKey, TData> node, {
    int? index,
    bool animate = true,
    bool preservePendingSubtreeState = false,
  }) {
    if (animationDuration == Duration.zero) animate = false;
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
        final effectiveIndex =
            index ?? (comparator != null ? _sortedIndex(_roots, node) : null);
        if (effectiveIndex != null && effectiveIndex < _roots.length) {
          _roots.insert(effectiveIndex, node.key);
        } else {
          _roots.add(node.key);
        }
        _refreshSubtreeDepths(node.key, 0);
      } else if (index != null) {
        // Already a root — honor an explicitly requested index by
        // relocating within _roots.
        final current = _roots.indexOf(node.key);
        if (current != -1) {
          _roots.removeAt(current);
          final clamped = index.clamp(0, _roots.length);
          _roots.insert(clamped, node.key);
        }
      }
      _cancelDeletion(
        node.key,
        animate: animate,
        preserveSubtreeState: preservePendingSubtreeState,
      );
      _adoptKey(node.key);
      _store.setData(node.key, node);
      if (preservePendingSubtreeState) {
        _rebuildVisibleOrder();
        _structureGeneration++;
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
      _rebuildVisibleOrder();
      _structureGeneration++;
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
        // Different parent — delegate to moveNode.
        moveNode(node.key, null, index: index);
        return;
      }
      final currentRootIndex = _roots.indexOf(node.key);
      final desiredIndex =
          index ?? (comparator != null ? _sortedIndex(_roots, node) : null);
      final wantsRelocate =
          desiredIndex != null &&
          desiredIndex != currentRootIndex &&
          // Appending is a no-op if already at the end.
          !(currentRootIndex == _roots.length - 1 &&
              desiredIndex >= _roots.length);
      if (wantsRelocate) {
        _roots.removeAt(currentRootIndex);
        final clamped = desiredIndex.clamp(0, _roots.length);
        _roots.insert(clamped, node.key);
        _rebuildVisibleOrder();
        _structureGeneration++;
      }
      // Data payload for node.key was just overwritten — rebuild its row.
      _notifyStructural(affectedKeys: <TKey>{node.key});
      return;
    }

    // Add to data structures
    _adoptKey(node.key);
    _store.setData(node.key, node);
    _setParentKey(node.key, null);
    _setChildList(node.key, []);
    _setDepthKey(node.key, 0);
    _setExpandedKey(node.key, false);

    // Add to roots list
    final effectiveIndex =
        index ?? (comparator != null ? _sortedIndex(_roots, node) : null);
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

  /// Adds children to a node.
  ///
  /// The children are added but not visible until the parent is expanded.
  /// If the parent already has children, the old children and their
  /// descendants are purged from all data structures first.
  void setChildren(TKey parentKey, List<TreeNode<TKey, TData>> children) {
    assert(_hasKey(parentKey), 'Parent node $parentKey not found');
    assert(
      !_isPendingDeletion(parentKey),
      'Cannot setChildren on $parentKey while it is animating out '
      '(pending deletion). The parent will be purged when its exit animation '
      'completes, leaving the new children orphaned.',
    );
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

    // Purge old children and their descendants before overwriting.
    final oldChildren = _childListOf(parentKey);
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
          _bumpVisibleSubtreeSizeFromSelf(parentNid, -visibleCount);
        }
      }

      final oldKeySet = allOldKeys.toSet();
      for (final key in allOldKeys) {
        _purgeNodeData(key);
      }

      if (visibleCount > 0) {
        _runWithSubtreeSizeUpdatesSuppressed(() {
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
  void insert({
    required TKey parentKey,
    required TreeNode<TKey, TData> node,
    int? index,
    bool animate = true,
    bool preservePendingSubtreeState = false,
  }) {
    if (animationDuration == Duration.zero) animate = false;
    assert(_hasKey(parentKey), "Parent node $parentKey not found");
    assert(
      !_isPendingDeletion(parentKey),
      "Cannot insert under $parentKey while it is animating out "
      "(pending deletion). The parent will be purged when its exit animation "
      "completes, leaving the new child orphaned.",
    );
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
        final effectiveIndex =
            index ?? (comparator != null ? _sortedIndex(siblings, node) : null);
        if (effectiveIndex != null && effectiveIndex < siblings.length) {
          siblings.insert(effectiveIndex, node.key);
        } else {
          siblings.add(node.key);
        }
        final parentDepth = _depthOfKey(parentKey);
        _refreshSubtreeDepths(node.key, parentDepth + 1);
      } else if (index != null) {
        // Same parent — honor an explicitly requested index by relocating
        // within the sibling list.
        final siblings = _childListOrCreate(parentKey);
        final current = siblings.indexOf(node.key);
        if (current != -1) {
          siblings.removeAt(current);
          final clamped = index.clamp(0, siblings.length);
          siblings.insert(clamped, node.key);
        }
      }
      _cancelDeletion(
        node.key,
        animate: animate,
        preserveSubtreeState: preservePendingSubtreeState,
      );
      _adoptKey(node.key);
      _store.setData(node.key, node);
      if (preservePendingSubtreeState) {
        _rebuildVisibleOrder();
        _structureGeneration++;
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
      _rebuildVisibleOrder();
      _structureGeneration++;
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
        // Different parent — delegate to moveNode.
        moveNode(node.key, parentKey, index: index);
        return;
      }
      final siblings = _childListOrCreate(parentKey);
      final currentIndex = siblings.indexOf(node.key);
      final desiredIndex =
          index ?? (comparator != null ? _sortedIndex(siblings, node) : null);
      final wantsRelocate =
          desiredIndex != null &&
          desiredIndex != currentIndex &&
          !(currentIndex == siblings.length - 1 &&
              desiredIndex >= siblings.length);
      if (wantsRelocate) {
        siblings.removeAt(currentIndex);
        final clamped = desiredIndex.clamp(0, siblings.length);
        siblings.insert(clamped, node.key);
        _rebuildVisibleOrder();
        _structureGeneration++;
      }
      // Data payload for node.key was just overwritten — rebuild its row.
      _notifyStructural(affectedKeys: <TKey>{node.key});
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
    // Add to parent's children
    final siblings = _childListOrCreate(parentKey);
    final parentHadChildren = siblings.isNotEmpty;
    final effectiveIndex =
        index ?? (comparator != null ? _sortedIndex(siblings, node) : null);
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
              insertIndex += _visibleSubtreeSizeByNid[siblingNid];
            }
          }
        } else {
          // Append after last visible descendant of parent. Parent is
          // visible (checked above) so its cached subtree size counts
          // itself + all currently-visible descendants; subtracting
          // 1 for the parent itself and adding 1 for "position after"
          // yields parentVisibleIndex + subtreeSize directly.
          final parentNid = _nids[parentKey]!;
          insertIndex =
              parentVisibleIndex + _visibleSubtreeSizeByNid[parentNid];
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
    // builder output can change is the parent — and only when its
    // hasChildren state just flipped from false → true (the chevron
    // appears for the first time).
    final affected = <TKey>{};
    if (!parentHadChildren) {
      affected.add(parentKey);
    }
    _notifyStructural(affectedKeys: affected);
  }

  /// Removes a node and all its descendants from the tree.
  ///
  /// If [animate] is true, the nodes will animate out.
  void remove({required TKey key, bool animate = true}) {
    if (animationDuration == Duration.zero) animate = false;
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
      // Animated path: parent's child list is not mutated until exit
      // animations complete; the hasChildren-flip refresh is fired from
      // the standalone-tick / group-dismissed sites at completion time.
    } else {
      _removeNodesImmediate(nodesToRemove);
      _structureGeneration++;
      // Immediate path: if [key] was the last child under its parent, the
      // parent's hasChildren just flipped true → false.
      if (parentKey != null) {
        final siblings = _childListOf(parentKey);
        if (siblings == null || siblings.isEmpty) {
          affected.add(parentKey);
        }
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
  /// root keys. Expansion state, animation state, and measured extents are
  /// preserved. Pending-deletion roots are appended after the live roots.
  void reorderRoots(List<TKey> orderedKeys) {
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

    _roots
      ..clear()
      ..addAll(orderedKeys)
      ..addAll(pendingRoots);
    _rebuildVisibleOrder();
    _structureGeneration++;
    // Pure reorder: positions change but no row's builder output does
    // (nodeBuilder signature takes (context, key, depth) — no index). The
    // sliver's layout repositions elements in place.
    _notifyStructural(affectedKeys: const {});
  }

  /// Reorders the children of [parentKey] to match [orderedKeys].
  ///
  /// [orderedKeys] must contain exactly the current live (non-pending-deletion)
  /// children of [parentKey]. Expansion state, animation state, and measured
  /// extents are preserved.
  void reorderChildren(TKey parentKey, List<TKey> orderedKeys) {
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

    _setChildList(parentKey, [...orderedKeys, ...pendingChildren]);
    bool needsVisibleRebuild =
        _isExpandedKey(parentKey) && _ancestorsExpandedFast(parentKey);
    if (!needsVisibleRebuild) {
      // Even if the parent is not expanded, children may still be present
      // in _visibleOrder because they are mid-animation (collapse in
      // progress, pending-deletion exit). Those entries would otherwise
      // retain the old order until the animation completes.
      for (final child in _childListOf(parentKey)!) {
        if (_hasOperationGroup(child) ||
            _bulkAnimationGroup?.members.contains(child) == true ||
            _hasStandalone(child)) {
          needsVisibleRebuild = true;
          break;
        }
      }
    }
    if (needsVisibleRebuild) {
      _rebuildVisibleOrder();
      _structureGeneration++;
    }
    // See reorderRoots: pure reorder — no builder output changes.
    _notifyStructural(affectedKeys: const {});
  }

  /// Moves a node from its current parent to [newParentKey].
  ///
  /// If [newParentKey] is null, the node becomes a root. If [index] is
  /// provided, the node is inserted at that position among its new siblings;
  /// otherwise it is appended.
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
  /// [slideDuration] using [slideCurve]. The slide is paint-only — layout
  /// settles immediately at the new structural positions.
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
  /// when the controller's [animationDuration] is `Duration.zero` (the
  /// engine no-ops in that case to honor the global animation-disabled
  /// setting).
  void moveNode(
    TKey key,
    TKey? newParentKey, {
    int? index,
    bool animate = false,
    Duration slideDuration = const Duration(milliseconds: 220),
    Curve slideCurve = Curves.easeOutCubic,
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
    // (release builds skip the assert below).
    if (newParentKey != null && _getDescendants(key).contains(newParentKey)) {
      throw StateError(
        "Cannot move $key under its own descendant $newParentKey",
      );
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
    // requested, nothing to do. With an explicit [index], fall through so the
    // node is repositioned among its existing siblings.
    //
    // CRITICAL: this no-op return MUST precede the animate staging below.
    // Otherwise an animated no-op call would stage a baseline (via
    // _stageSlideBaselineOnHosts → beginSlideBaseline) that triggers no
    // layout (no _notifyStructural fires for a no-op), leaving the
    // _pendingSlideBaseline stuck and blocking all subsequent stages
    // under first-wins until something else triggers a layout.
    if (oldParent == newParentKey && index == null) return;

    // Capture pre-mutation visibility so we can decide entry vs exit
    // phantom paths after _rebuildVisibleOrder runs.
    final wasVisible = animate && _order.contains(key);

    // First-wins staging fan-out. Every attached sliver render object's
    // beginSlideBaseline is invoked. Inside runBatch (or for adjacent
    // same-frame moveNode calls), the first such call wins; subsequent
    // calls no-op at the host level. The single staged baseline is
    // consumed by the next layout post-mutation.
    if (animate) {
      _stageSlideBaselineOnHosts(
        duration: slideDuration,
        curve: slideCurve,
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
      if (!wasVisible) {
        TKey? cursor = _parentKeyOfKey(key);
        while (cursor != null && !_order.contains(cursor)) {
          cursor = _parentKeyOfKey(cursor);
        }
        if (cursor != null) {
          _pendingPhantomAnchors ??= <TKey, TKey>{};
          // Apply the same anchor to the entire moved subtree — children
          // inherit the parent's anchor since they were all hidden inside
          // the same collapsed ancestor.
          for (final k in _flattenSubtree(key, includeRoot: true)) {
            _pendingPhantomAnchors![k] = cursor;
          }
        }
      }
    }

    // Snapshot state needed to compute precise affected-keys after the move.
    final oldDepth = _depthOfKey(key);
    final newParentWasEmpty = newParentKey != null
        ? (_childListOf(newParentKey)?.isEmpty ?? true)
        : false;

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
    // `_applyClampAndInstallNewGhosts`. Composition correctly absorbs the
    // structural shift into the new currentDelta — no double-counting.
    _cancelAnimationStateForSubtree(key, cancelSlides: !animate);

    // Remove from old parent's child list (or roots).
    if (oldParent != null) {
      _childListOf(oldParent)?.remove(key);
    } else {
      _roots.remove(key);
    }

    // Insert into new parent's child list (or roots).
    _setParentKey(key, newParentKey);
    final node = _dataOf(key)!;
    if (newParentKey != null) {
      final siblings = _childListOrCreate(newParentKey);
      final effectiveIndex =
          index ?? (comparator != null ? _sortedIndex(siblings, node) : null);
      if (effectiveIndex != null && effectiveIndex < siblings.length) {
        siblings.insert(effectiveIndex, key);
      } else {
        siblings.add(key);
      }
    } else {
      final effectiveIndex =
          index ?? (comparator != null ? _sortedIndex(_roots, node) : null);
      if (effectiveIndex != null && effectiveIndex < _roots.length) {
        _roots.insert(effectiveIndex, key);
      } else {
        _roots.add(key);
      }
    }

    final newDepth = newParentKey != null ? (_depthOfKey(newParentKey)) + 1 : 0;
    _refreshSubtreeDepths(key, newDepth);

    _rebuildVisibleOrder();
    _structureGeneration++;

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
    if (animate && wasVisible && !_order.contains(key)) {
      TKey? cursor = newParentKey;
      while (cursor != null && !_order.contains(cursor)) {
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
        for (final k in _flattenSubtree(key, includeRoot: true)) {
          _pendingExitPhantomAnchors![k] = cursor;
        }
      }
    }

    final affected = <TKey>{};
    // If the moved subtree's depth changed, every row in it must rebuild
    // — nodeBuilder receives `depth` as an argument and indentation scales
    // with it. Use _flattenSubtree so we enumerate the currently-expanded
    // rows (the only ones that can be mounted).
    if (newDepth != oldDepth) {
      affected.addAll(_flattenSubtree(key, includeRoot: true));
    }
    // Old parent may have just lost its last child (hasChildren true → false).
    if (oldParent != null) {
      final siblings = _childListOf(oldParent);
      if (siblings == null || siblings.isEmpty) {
        affected.add(oldParent);
      }
    }
    // New parent may have just gained its first child (hasChildren false → true).
    if (newParentKey != null && newParentWasEmpty) {
      affected.add(newParentKey);
    }
    _notifyStructural(affectedKeys: affected);
  }

  /// Sets [_depths] for [key] and all its descendants. Iterative so deep
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
    if (animationDuration == Duration.zero) animate = false;
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
    final existingGroup = _operationGroups[key];
    if (existingGroup != null) {
      // Path 1: Reversing a collapse — group already exists.
      //
      // The op-group's controller is the shared timing primitive;
      // each member's NodeGroupExtent envelope (start/target) defines
      // what it animates between. To reverse the collapse smoothly:
      //
      //   1. Rebase each member: capture its current visual extent
      //      (under the OLD envelope at the OLD curvedValue) and set
      //      startExtent to that value, targetExtent to full. Reset
      //      the controller to value=0 and forward(); the group
      //      replays each row from `current → full` over the full
      //      configured duration, no jump.
      //   2. Clear pendingRemoval so the dismissed handler doesn't
      //      yank rows.
      //
      // Resetting `controller.value = 0` fires the `dismissed` status
      // synchronously, which the group's status listener would
      // otherwise treat as a real collapse-complete and dispose the
      // group. The listener has an identity guard
      // (`identical(_operationGroups[key], group)`), so we briefly
      // detach the group from `_operationGroups` around the value=0
      // store, let the gated dismissed event fire harmlessly, then
      // re-attach for the actual `forward()` call.
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
      _operationGroups.remove(key);
      try {
        existingGroup.controller.value = 0.0;
      } finally {
        _operationGroups[key] = existingGroup;
      }
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

    // Path 2: Fresh expand — create new operation group
    final nodesToShow = _flattenSubtree(key, includeRoot: false);
    final controller = AnimationController(
      vsync: _vsync,
      duration: animationDuration,
      value: 0.0,
    );
    final group = OperationGroup<TKey>(
      controller: controller,
      curve: animationCurve,
      operationKey: key,
    );
    _installOperationGroup(key, group);

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
        for (int i = minInsertIndex; i < _order.length; i++) {
          _order.setIndexByNid(_order.orderNids[i], i);
        }
        _assertIndexConsistency();
      }
    }

    _structureGeneration++;
    controller.forward();
    _ensureStandaloneTickerRunning();
    _notifyStructural(affectedKeys: <TKey>{key});
  }

  /// Collapses the given node, hiding its children.
  ///
  /// Note: This preserves the expansion state of descendant nodes. When the
  /// node is re-expanded, any previously expanded children will also show
  /// their children automatically.
  void collapse({required TKey key, bool animate = true}) {
    if (animationDuration == Duration.zero) animate = false;
    if (!_hasKey(key) || !_isExpandedKey(key)) {
      return;
    }
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
    final existingGroup = _operationGroups[key];
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
      _operationGroups.remove(key);
      try {
        existingGroup.controller.value = 1.0;
      } finally {
        _operationGroups[key] = existingGroup;
      }
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

    // Path 2: Fresh collapse — create new operation group
    final controller = AnimationController(
      vsync: _vsync,
      duration: animationDuration,
      value: 1.0,
    );
    final group = OperationGroup<TKey>(
      controller: controller,
      curve: animationCurve,
      operationKey: key,
    );
    _installOperationGroup(key, group);

    for (final nodeId in descendants) {
      if (_isPendingDeletion(nodeId)) continue;
      final capturedExtent = _captureAndRemoveFromGroups(nodeId);
      final nge = NodeGroupExtent(
        startExtent: 0.0,
        targetExtent:
            capturedExtent ?? (_fullExtentOf(nodeId) ?? defaultExtent),
        // When this member's target was set from a captured visual
        // extent, freeze it: a later setFullExtent resize must not
        // retroactively expand the row to its natural full size
        // mid-collapse (the "children appear all at once at full"
        // bug). When the target was the natural full reference (no
        // capture), resize updates are still welcome.
        targetIsCaptured: capturedExtent != null,
      );
      group.members[nodeId] = nge;
      group.pendingRemoval.add(nodeId);
      _setOperationGroup(nodeId, key);
    }

    _structureGeneration++;
    controller.reverse();
    _ensureStandaloneTickerRunning();
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
    if (animationDuration == Duration.zero) animate = false;
    // Collect all nodes to expand, nodes to show, and nodes currently exiting
    final nodesToExpand = <TKey>[];
    final nodesToShow = <TKey>[];
    final nodesToReverseExit = <TKey>[];

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
            nodesToShow.add(childId);
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
          final opGroup = _operationGroups[opGroupKey];
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
    _rebuildVisibleOrder();
    _structureGeneration++;
    // Start animations for newly visible nodes and reverse exiting animations
    if (animate) {
      // Reverse collapsing operation groups
      bool opGroupReversed = false;
      for (final entry in _operationGroups.entries) {
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
      if (opGroupReversed) _bumpAnimGen();

      // Check if there's a collapsing bulk animation we can reverse
      if (_bulkAnimationGroup != null &&
          _bulkAnimationGroup!.pendingRemoval.isNotEmpty) {
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
        _bulkAnimationGroup!.controller.forward();
        _bumpBulkGen();
      } else {
        // Dispose old group and create fresh to avoid status listener race
        _disposeBulkAnimationGroup();
        _bulkAnimationGroup = _createBulkAnimationGroup();

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
        _bulkAnimationGroup!.controller.forward();
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
    if (animationDuration == Duration.zero) animate = false;
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
    for (final nid in _activeStandaloneNids) {
      final state = _standaloneByNid[nid]!;
      if (state.type != AnimationType.entering) continue;
      final key = _nids.keyOfUnchecked(nid);
      if (nodesToHideSet.contains(key)) continue;
      if (_parentKeyOfKey(key) != null) {
        nodesToHide.add(key);
        nodesToHideSet.add(key);
      }
    }

    // Check operation group members (expanding)
    for (final group in _operationGroups.values) {
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
    if (_bulkAnimationGroup != null) {
      for (final key in _bulkAnimationGroup!.members) {
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
      // Reverse expanding operation groups
      bool opGroupReversed = false;
      for (final entry in _operationGroups.entries) {
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
      if (opGroupReversed) _bumpAnimGen();

      // Check if there's an expanding bulk animation we can reverse
      if (_bulkAnimationGroup != null &&
          _bulkAnimationGroup!.members.isNotEmpty &&
          _bulkAnimationGroup!.pendingRemoval.isEmpty) {
        // Mark all members for removal when animation completes at 0
        for (final key in _bulkAnimationGroup!.members) {
          if (!_isPendingDeletion(key)) {
            _addBulkPending(key);
          }
        }

        // Handle additional nodes not in any group
        for (final key in nodesToHide) {
          if (_isPendingDeletion(key)) continue;
          if (!_bulkAnimationGroup!.members.contains(key) &&
              !_hasOperationGroup(key)) {
            _startStandaloneExitAnimation(key);
          }
        }

        // Reverse the controller direction
        _bulkAnimationGroup!.controller.reverse();
        _bumpBulkGen();
      } else {
        // Dispose old group and create fresh with value=1.0
        _disposeBulkAnimationGroup();
        _bulkAnimationGroup = _createBulkAnimationGroup(initialValue: 1.0);

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
        if (_bulkAnimationGroup!.members.isNotEmpty) {
          _bulkAnimationGroup!.controller.reverse();
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
  /// recomputes [_visibleSubtreeSizeByNid] in one O(N) post-order pass
  /// afterwards. Firing the incremental callback N times would be
  /// O(N·depth), which degenerates to O(N²) on deep trees.
  void _rebuildVisibleOrder() {
    _runWithSubtreeSizeUpdatesSuppressed(_rebuildVisibleOrderImpl);
  }

  void _rebuildVisibleOrderImpl() {
    _order.clear();

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
        // have running exit animations — they need to stay in _visibleOrder
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
              _bulkAnimationGroup?.members.contains(childId) == true ||
              _hasStandalone(childId)) {
            stack.add(childId);
          }
        }
      }
    }

    _rebuildVisibleIndex();
    _rebuildVisibleSubtreeSizes();
    // No post-rebuild consistency check: _rebuildVisibleSubtreeSizes uses
    // the same recursive sum formula as _assertVisibleSubtreeSizeConsistency,
    // so the check is tautological here. The fuzz test covers the
    // incremental path where the cross-check is meaningful.
  }

  @override
  void dispose() {
    _clear();
    _slide.dispose();
    _animationListeners.clear();
    _nodeDataListeners.clear();
    _structuralListeners.clear();
    _renderHosts.clear();
    _pendingPhantomAnchors = null;
    _pendingExitPhantomAnchors = null;
    super.dispose();
  }
}
