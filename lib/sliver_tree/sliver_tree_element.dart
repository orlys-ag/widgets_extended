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

  /// Keys whose data changed since the last build. Refreshed surgically
  /// in [performRebuild] instead of walking every mounted child.
  final Set<TKey> _dirtyDataNodes = {};

  /// Set when the controller fired a structural notification (or any event
  /// that may have changed expansion / visible order / depth / closures).
  /// Forces [performRebuild] to refresh every mounted child, which
  /// subsumes [_dirtyDataNodes].
  bool _needsFullRefresh = false;

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
    }

    if (_didReassemble) {
      _didReassemble = false;
      _invalidateAllChildren();
      renderObject.markStructureChanged();
    }

    // Parent rebuild: nodeBuilder closure may have captured new state,
    // so every mounted row must be refreshed. This supersedes any
    // targeted data-refresh already queued.
    _needsFullRefresh = true;
    _dirtyDataNodes.clear();
    _refreshMountedChildren();
    _needsFullRefresh = false;
  }

  @override
  void performRebuild() {
    super.performRebuild();
    // Triggered by markNeedsBuild. Two entry points:
    //  - _onControllerChanged (structural): _needsFullRefresh is true.
    //  - _onNodeDataChanged (per-key data): only _dirtyDataNodes is populated.
    // Full refresh subsumes targeted refresh, so check it first.
    if (_needsFullRefresh) {
      _needsFullRefresh = false;
      _dirtyDataNodes.clear();
      _refreshMountedChildren();
    } else if (_dirtyDataNodes.isNotEmpty) {
      final keys = List<TKey>.of(_dirtyDataNodes);
      _dirtyDataNodes.clear();
      _refreshMountedChildren(only: keys);
    }
  }

  /// Refreshes mounted children with fresh widgets from the current
  /// [SliverTree.nodeBuilder].
  ///
  /// When [only] is null, every mounted row is refreshed (used for
  /// structural notifications and parent rebuilds). When provided, only
  /// the listed keys are refreshed — the per-key data-change fast path.
  void _refreshMountedChildren({Iterable<TKey>? only}) {
    if (_children.isEmpty) return;
    final keysToRefresh = only ?? _children.keys.toList();
    for (final key in keysToRefresh) {
      final oldElement = _children[key];
      if (oldElement == null) continue;
      // Skip nodes that no longer exist — GC will clean them up.
      if (widget.controller.getNodeData(key) == null) continue;
      final depth = widget.controller.getDepth(key);
      final newWidget = widget.nodeBuilder(this, key, depth);
      final newElement = updateChild(oldElement, newWidget, key);
      if (newElement != null) {
        _children[key] = newElement;
      } else {
        _children.remove(key);
      }
    }
  }

  /// Deactivates all existing children so they are recreated with the
  /// current widget's [SliverTree.nodeBuilder] on the next layout pass.
  ///
  /// Called from [update], which already runs inside the framework's build
  /// scope, so no additional [BuildOwner.buildScope] call is needed.
  void _invalidateAllChildren() {
    final childrenToDeactivate = Map.of(_children);
    _children.clear();

    for (final entry in childrenToDeactivate.entries) {
      updateChild(entry.value, null, entry.key);
    }
  }

  /// Handles structural notifications from the controller.
  ///
  /// [affectedKeys] semantics (set by the controller):
  ///   - `null` — scope unknown; do a full refresh of every mounted row.
  ///   - empty set — structural change occurred but no mounted row's
  ///     builder output changed (new rows first-build via [createChild],
  ///     removed rows GC'd); only relayout + GC are required.
  ///   - non-empty set — refresh exactly the listed keys that are
  ///     currently mounted.
  void _onStructuralChange(Set<TKey>? affectedKeys) {
    renderObject.markNeedsLayout();
    _scheduleGarbageCollection();

    if (affectedKeys == null) {
      _needsFullRefresh = true;
      _dirtyDataNodes.clear();
      markNeedsBuild();
      return;
    }

    if (affectedKeys.isEmpty) {
      // Structural mutation with no builder-output change. Layout + GC only.
      return;
    }

    if (_needsFullRefresh) {
      // A prior (still-pending) notify already queued a full refresh; the
      // upcoming rebuild subsumes this one.
      return;
    }

    bool anyMounted = false;
    for (final key in affectedKeys) {
      if (_children.containsKey(key)) {
        _dirtyDataNodes.add(key);
        anyMounted = true;
      }
    }
    if (anyMounted) {
      markNeedsBuild();
    }
  }

  /// Called on pure animation ticks (no structural change).
  /// Only triggers relayout — no GC scheduling needed.
  void _onAnimationTick() {
    renderObject.markNeedsLayout();
  }

  /// Called when a single node's data changed (via [TreeController.updateNode])
  /// without any structural mutation. Queues a targeted rebuild of just
  /// that row instead of sweeping every mounted child.
  void _onNodeDataChanged(TKey key) {
    // Node not mounted — nothing to refresh. Don't mark dirty or schedule
    // a build, otherwise we'd do a no-op pass for every off-screen update.
    if (!_children.containsKey(key)) return;
    _dirtyDataNodes.add(key);
    markNeedsBuild();
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
    final key = nodeId;
    // If child already exists, nothing to do
    if (_children.containsKey(key)) {
      return;
    }
    owner!.buildScope(this, () {
      final nodeData = widget.controller.getNodeData(key);
      if (nodeData == null) {
        return;
      }
      final depth = widget.controller.getDepth(key);
      final childWidget = widget.nodeBuilder(this, key, depth);
      final element = updateChild(null, childWidget, key);
      if (element != null) {
        _children[key] = element;
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
