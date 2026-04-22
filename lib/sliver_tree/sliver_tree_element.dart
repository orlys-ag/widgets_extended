/// Element for [SliverTree] that manages child element lifecycle.
library;

import 'package:flutter/widgets.dart';

import 'render_sliver_tree.dart';
import 'sliver_tree_widget.dart';

// ════════════════════════════════════════════════════════════════════════════
// CHILD MANAGER INTERFACE
// ════════════════════════════════════════════════════════════════════════════

/// Interface for managing child render objects in [RenderSliverTree].
///
/// Implemented by [SliverTreeElement] to allow the render object to
/// request child creation/removal during layout.
abstract class TreeChildManager<TKey> {
  /// Creates or updates the child for the given node.
  void createChild(TKey nodeId);

  /// Removes the child for the given node.
  void removeChild(TKey nodeId);

  /// Called when layout starts.
  void didStartLayout();

  /// Called when layout finishes.
  void didFinishLayout();
}

// ════════════════════════════════════════════════════════════════════════════
// ELEMENT
// ════════════════════════════════════════════════════════════════════════════

/// Element for [SliverTree] that creates and manages child elements.
///
/// Uses nodeId-based storage for straightforward element lifecycle management.
class SliverTreeElement<TKey, TData> extends RenderObjectElement
    implements TreeChildManager<TKey> {
  /// Creates a sliver tree element.
  SliverTreeElement(SliverTree<TKey, TData> super.widget);

  @override
  SliverTree<TKey, TData> get widget => super.widget as SliverTree<TKey, TData>;

  @override
  RenderSliverTree<TKey, TData> get renderObject =>
      super.renderObject as RenderSliverTree<TKey, TData>;

  /// Child elements by nodeId.
  final Map<TKey, Element> _children = {};

  /// Whether we're currently in a layout callback.
  bool _inLayout = false;

  /// Whether garbage collection is already scheduled.
  bool _gcScheduled = false;

  /// Whether stale-node eviction is already scheduled for a post-frame
  /// callback. Dedupes across layout passes so continuous scroll doesn't
  /// queue one callback per frame (each of which would walk [_children]).
  bool _staleEvictionScheduled = false;

  /// Set by [reassemble] to signal that [update] should invalidate children.
  bool _didReassemble = false;

  /// Keys whose mounted widget may be stale and needs refresh.
  ///
  /// Populated by three sources:
  ///   - [update] (parent rebuild): every mounted key is queued so rows
  ///     pick up the new `nodeBuilder` closure / captured parent state.
  ///   - [_onStructuralChange]: null affectedKeys queues every mounted
  ///     key; a non-empty set queues only the listed mounted keys.
  ///   - [_onNodeDataChanged]: queues the single affected mounted key.
  ///
  /// Consumed lazily in [createChild] during the next layout: cache-
  /// region and sticky children are rebuilt there; off-screen queued
  /// entries wait until they re-enter the cache region (refreshed on
  /// re-entry) or until stale eviction fires (discarded).
  ///
  /// This bounds refresh work by "what the viewport actually needs this
  /// frame" instead of walking `_children.keys` unconditionally on every
  /// parent rebuild. Without this bound, an external listener that
  /// rebuilds SliverTree's ancestor (e.g. `ListenableBuilder` on the
  /// controller) would cause `update` to rebuild every mounted row —
  /// including off-screen descendants that are moments away from
  /// stale-eviction. See `sliver_tree_widget_test.dart` regressions.
  final Set<TKey> _dirtyKeys = {};

  /// Whether the last animation tick observed [TreeController.hasActiveAnimations]
  /// as true. Used by [_onAnimationTick] so the settle tick (where the
  /// controller has already cleared animation state before notifying) still
  /// triggers [RenderObject.markNeedsLayout]. Without this, completed extent
  /// animations would never relayout and the render would remain at the
  /// partial animated value instead of the final settled extent.
  bool _priorTickHadAnimations = false;

  // ══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    renderObject.childManager = this;
    widget.controller.addStructuralListener(_onStructuralChange);
    widget.controller.addAnimationListener(_onAnimationTick);
    widget.controller.addNodeDataListener(_onNodeDataChanged);
  }

  @override
  void unmount() {
    widget.controller.removeStructuralListener(_onStructuralChange);
    widget.controller.removeAnimationListener(_onAnimationTick);
    widget.controller.removeNodeDataListener(_onNodeDataChanged);
    _gcScheduled = false;
    _staleEvictionScheduled = false;
    super.unmount();
  }

  @override
  void reassemble() {
    super.reassemble();
    _didReassemble = true;
  }

  @override
  void update(SliverTree<TKey, TData> newWidget) {
    final oldWidget = widget;
    super.update(newWidget);

    if (oldWidget.controller != newWidget.controller) {
      oldWidget.controller.removeStructuralListener(_onStructuralChange);
      oldWidget.controller.removeAnimationListener(_onAnimationTick);
      oldWidget.controller.removeNodeDataListener(_onNodeDataChanged);
      newWidget.controller.addStructuralListener(_onStructuralChange);
      newWidget.controller.addAnimationListener(_onAnimationTick);
      newWidget.controller.addNodeDataListener(_onNodeDataChanged);
      renderObject.controller = newWidget.controller;
      // Old-controller keys are meaningless under the new controller;
      // drop the queue and let createChild rebuild against fresh data.
      _dirtyKeys.clear();
    }

    if (_didReassemble) {
      _didReassemble = false;
      _invalidateAllChildren();
      renderObject.markStructureChanged();
      return;
    }

    // Parent rebuild: the `nodeBuilder` closure may have captured new
    // state. Queue every mounted row for lazy refresh and trigger a
    // layout pass — retained rows rebuild in [createChild] within the
    // same frame; off-screen rows wait for re-entry or discard. This
    // bounds the rebuild fan-out to the retained set (≈ cache region),
    // not the full mounted set. See [_dirtyKeys] doc.
    _dirtyKeys.addAll(_children.keys);
    renderObject.markNeedsLayout();
  }

  @override
  void performRebuild() {
    super.performRebuild();
    // All widget-refresh work happens lazily in [createChild] during
    // layout (see [_dirtyKeys]). If the framework marks us dirty, the
    // super call satisfies that contract — the actual reconciliation
    // lands when the next layout fires and iterates cache-region keys.
  }

  /// Deactivates all existing children so they are recreated with the
  /// current widget's [SliverTree.nodeBuilder] on the next layout pass.
  ///
  /// Called from [update] (under `_didReassemble`), which already runs
  /// inside the framework's build scope, so no additional
  /// [BuildOwner.buildScope] call is needed.
  void _invalidateAllChildren() {
    final childrenToDeactivate = Map.of(_children);
    _children.clear();
    _dirtyKeys.clear();

    for (final entry in childrenToDeactivate.entries) {
      updateChild(entry.value, null, entry.key);
    }
  }

  /// Handles structural notifications from the controller.
  ///
  /// [affectedKeys] semantics (set by the controller):
  ///   - `null` — scope unknown; every mounted row may need refresh.
  ///     Queued lazily; consumed in [createChild] for retained rows.
  ///   - empty set — structural change occurred but no mounted row's
  ///     builder output changed (new rows first-build via [createChild],
  ///     removed rows GC'd); only relayout + GC are required. Nothing
  ///     is added to [_dirtyKeys]; avoiding this queue is what keeps an
  ///     external `ChangeNotifier` subscriber that rebuilds SliverTree's
  ///     ancestor from amplifying the empty-set notify into a refresh
  ///     sweep over off-screen descendants.
  ///   - non-empty set — queue exactly the listed mounted keys.
  void _onStructuralChange(Set<TKey>? affectedKeys) {
    renderObject.markNeedsLayout();
    _scheduleGarbageCollection();

    if (affectedKeys == null) {
      _dirtyKeys.addAll(_children.keys);
      return;
    }

    if (affectedKeys.isEmpty) {
      return;
    }

    for (final key in affectedKeys) {
      if (_children.containsKey(key)) {
        _dirtyKeys.add(key);
      }
    }
  }

  /// Called on pure animation ticks (no structural change).
  ///
  /// Routes to [RenderObject.markNeedsLayout] for extent animations
  /// (enter/exit/bulk/op-group) — they change structural layout.
  ///
  /// Routes to [RenderObject.markNeedsPaint] for slide-only ticks — slide
  /// is paint-only; structural layout is unchanged and marking layout dirty
  /// would trigger an unnecessary relayout every frame.
  ///
  /// The completion tick of an extent animation fires **after** the
  /// controller has cleared its state (so [TreeController.hasActiveAnimations]
  /// is already false). We still need a final relayout to settle the final
  /// extent, which is why [_priorTickHadAnimations] is checked — if the
  /// previous tick saw active animations, the current tick is the settle
  /// tick and must relayout even though the flag is now false.
  ///
  /// The completion tick of a slide fires **before** the controller clears
  /// its entries, so `hasActiveSlides` is still true and the paint branch
  /// schedules a final paint at `currentDelta == 0.0`. After that there's
  /// no further tick; the clear-and-stop is a no-visual-change operation.
  void _onAnimationTick() {
    final c = widget.controller;
    final active = c.hasActiveAnimations;
    if (active || _priorTickHadAnimations) {
      renderObject.markNeedsLayout();
    } else if (c.hasActiveSlides) {
      renderObject.markNeedsPaint();
    }
    _priorTickHadAnimations = active;
  }

  /// Called when a single node's data changed (via [TreeController.updateNode])
  /// without any structural mutation. Queues a targeted rebuild of just
  /// that row, consumed lazily by [createChild] during the next layout.
  void _onNodeDataChanged(TKey key) {
    // Node not mounted — nothing to refresh. Don't queue or schedule a
    // layout, otherwise we'd do a no-op pass for every off-screen update.
    if (!_children.containsKey(key)) return;
    _dirtyKeys.add(key);
    renderObject.markNeedsLayout();
  }

  /// Schedules cleanup of elements for nodes that no longer exist.
  void _scheduleGarbageCollection() {
    if (_gcScheduled) return;
    _gcScheduled = true;

    // Run after the frame when we're definitely not in layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gcScheduled = false;
      if (!mounted || _inLayout) return;
      _collectGarbage();
    });
  }

  /// Removes elements for nodes that no longer exist in the controller.
  ///
  /// Only evicts *dead* nodes (removed from the tree entirely). Stale-node
  /// eviction (mounted rows that scrolled outside the cache region) is
  /// handled separately by [_scheduleStaleEviction] on a post-layout
  /// cadence.
  void _collectGarbage() {
    final controller = widget.controller;
    final deadNodes = <TKey>[];

    // Dead nodes — no longer in the controller at all. Always evict.
    for (final nodeId in _children.keys) {
      if (controller.getNodeData(nodeId) == null) {
        deadNodes.add(nodeId);
      }
    }

    if (deadNodes.isEmpty) return;

    // Batch evictions to avoid frame spikes after animation settles.
    // Scale batch size with dead count so large removals clear faster.
    final maxPerPass = deadNodes.length.clamp(50, 200);
    final evictNow = deadNodes.length <= maxPerPass
        ? deadNodes
        : deadNodes.sublist(0, maxPerPass);

    owner!.buildScope(this, () {
      for (final nodeId in evictNow) {
        final element = _children.remove(nodeId);
        _dirtyKeys.remove(nodeId);
        if (element != null) {
          updateChild(element, null, nodeId);
        }
      }
    });

    // If more remain, schedule another pass.
    if (deadNodes.length > maxPerPass) {
      _scheduleGarbageCollection();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TREE CHILD MANAGER
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void didStartLayout() {
    _inLayout = true;
  }

  @override
  void didFinishLayout() {
    _inLayout = false;
    _scheduleStaleEviction();
  }

  /// Schedules eviction of mounted children that are outside the cache
  /// region and not needed as sticky headers.
  ///
  /// Skipped while animations are active so exiting rows keep their
  /// element until the animation settles. The [_staleEvictionScheduled]
  /// flag dedupes across layout passes — continuous scroll fires
  /// `didFinishLayout` every frame, but we only want one post-frame
  /// eviction sweep per frame. The [_children] walk happens inside the
  /// post-frame callback (not in the hot layout path) so per-layout cost
  /// stays O(1).
  void _scheduleStaleEviction() {
    if (_staleEvictionScheduled) return;
    if (widget.controller.hasActiveAnimations) return;
    _staleEvictionScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _staleEvictionScheduled = false;
      if (!mounted || _inLayout) return;
      // An animation may have started between scheduling and firing —
      // e.g. the user expanded a node in the same frame. Bail out so we
      // don't evict a row that's about to begin its enter/exit animation.
      if (widget.controller.hasActiveAnimations) return;

      final render = renderObject;
      final staleNodes = <TKey>[];
      for (final nodeId in _children.keys) {
        // Dead rows are handled by [_collectGarbage]; skip them here so
        // both paths don't race over the same element.
        if (widget.controller.getNodeData(nodeId) == null) continue;
        if (!render.isNodeRetained(nodeId)) {
          staleNodes.add(nodeId);
        }
      }
      if (staleNodes.isEmpty) return;

      // Batch evictions to cap per-frame work after a large scroll.
      // Scale with stale count so big sweeps clear quickly without
      // pathologically long pauses.
      final maxPerPass = staleNodes.length.clamp(50, 200);
      final evictNow = staleNodes.length <= maxPerPass
          ? staleNodes
          : staleNodes.sublist(0, maxPerPass);

      owner!.buildScope(this, () {
        for (final nodeId in evictNow) {
          final element = _children.remove(nodeId);
          _dirtyKeys.remove(nodeId);
          if (element != null) {
            updateChild(element, null, nodeId);
          }
        }
      });

      if (staleNodes.length > maxPerPass) {
        _scheduleStaleEviction();
      }
    });
  }

  @override
  void createChild(TKey nodeId) {
    assert(_inLayout, 'createChild must be called during layout');
    final existing = _children[nodeId];
    // Three cases handled here:
    //   1. No existing element: build a fresh widget via [nodeBuilder].
    //   2. Existing element, queued as dirty by a prior update / notify:
    //      rebuild with a fresh widget so the row picks up any new state
    //      captured by the `nodeBuilder` closure or new controller data.
    //   3. Existing element, not dirty: no-op — this is the hot path
    //      every layout hits for already-mounted cache-region keys.
    final needsRefresh = existing != null && _dirtyKeys.remove(nodeId);
    if (existing != null && !needsRefresh) {
      return;
    }
    owner!.buildScope(this, () {
      final nodeData = widget.controller.getNodeData(nodeId);
      if (nodeData == null) {
        return;
      }
      final depth = widget.controller.getDepth(nodeId);
      final childWidget = widget.nodeBuilder(this, nodeId, depth);
      final element = updateChild(existing, childWidget, nodeId);
      if (element != null) {
        _children[nodeId] = element;
      } else if (existing != null) {
        _children.remove(nodeId);
      }
    });
  }

  @override
  void removeChild(TKey nodeId) {
    // No-op: we don't actively remove children because it triggers
    // markNeedsLayout. Stale children remain but are not painted/hit-tested.
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RENDER OBJECT CHILD MANAGEMENT
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void insertRenderObjectChild(RenderBox child, Object slot) {
    renderObject.insertChild(child, slot as TKey);
  }

  @override
  void moveRenderObjectChild(RenderBox child, Object oldSlot, Object newSlot) {
    // NodeIds don't change, this shouldn't happen
    assert(oldSlot == newSlot);
  }

  @override
  void removeRenderObjectChild(RenderBox child, Object slot) {
    renderObject.removeChild(child, slot as TKey);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ELEMENT TREE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void visitChildren(ElementVisitor visitor) {
    for (final element in _children.values) {
      visitor(element);
    }
  }

  @override
  void forgetChild(Element child) {
    final nodeId = child.slot as TKey?;
    if (nodeId != null) {
      _children.remove(nodeId);
      // forgetChild bypasses removeRenderObjectChild, so if a GlobalKey
      // inside nodeBuilder moves the element elsewhere, the RenderBox
      // stays adopted as a zombie in renderObject._children and gets
      // walked by attach/detach/visitChildren. Drop it here when it's
      // still our adopted child.
      final box = renderObject.getChildForNode(nodeId);
      if (box != null && identical(box.parent, renderObject)) {
        renderObject.removeChild(box, nodeId);
      }
    }
    super.forgetChild(child);
  }
}
