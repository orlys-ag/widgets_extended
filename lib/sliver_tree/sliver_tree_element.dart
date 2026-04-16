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

  /// Set by [reassemble] to signal that [update] should invalidate children.
  bool _didReassemble = false;

  // ══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    renderObject.childManager = this;
    widget.controller.addListener(_onControllerChanged);
    widget.controller.addAnimationListener(_onAnimationTick);
  }

  @override
  void unmount() {
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.removeAnimationListener(_onAnimationTick);
    _gcScheduled = false;
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
      oldWidget.controller.removeListener(_onControllerChanged);
      oldWidget.controller.removeAnimationListener(_onAnimationTick);
      newWidget.controller.addListener(_onControllerChanged);
      newWidget.controller.addAnimationListener(_onAnimationTick);
      renderObject.controller = newWidget.controller;
    }

    if (_didReassemble) {
      _didReassemble = false;
      _invalidateAllChildren();
      renderObject.markStructureChanged();
    }

    // Refresh mounted children with the (potentially new) nodeBuilder so
    // that visible rows always reflect current parent state and closures.
    _refreshMountedChildren();
  }

  @override
  void performRebuild() {
    super.performRebuild();
    // Triggered by markNeedsBuild (e.g. controller data change via updateNode).
    // Walk mounted children and feed them fresh widgets from the current
    // nodeBuilder so same-key data updates propagate without recreation.
    _refreshMountedChildren();
  }

  /// Refreshes all mounted children with fresh widgets from the current
  /// [SliverTree.nodeBuilder].
  ///
  /// Called from [update] (parent rebuild) and [performRebuild] (controller
  /// data change) so that existing visible rows always reflect the latest
  /// widget tree and controller state.
  void _refreshMountedChildren() {
    if (_children.isEmpty) return;
    for (final entry in _children.entries.toList()) {
      final key = entry.key;
      final oldElement = entry.value;
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

  void _onControllerChanged() {
    renderObject.markNeedsLayout();
    markNeedsBuild();
    _scheduleGarbageCollection();
  }

  /// Called on pure animation ticks (no structural change).
  /// Only triggers relayout — no GC scheduling needed.
  void _onAnimationTick() {
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
  /// Only evicts dead nodes (removed from the tree entirely). Stale-node
  /// eviction (nodes outside the cache region) is not yet implemented.
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
  /// Skipped during animations to avoid evicting nodes that may re-enter
  /// the viewport. Runs as a post-frame callback so that `dropChild` /
  /// `markNeedsLayout` is called between frames, not during layout.
  void _scheduleStaleEviction() {
    if (widget.controller.hasActiveAnimations) return;

    final retained = renderObject.retainedNodeIds;
    final staleNodes = <TKey>[];
    for (final nodeId in _children.keys) {
      // Only evict nodes that still exist in the controller but are outside
      // the retention window. Dead nodes are handled by _collectGarbage.
      if (!retained.contains(nodeId) &&
          widget.controller.getNodeData(nodeId) != null) {
        staleNodes.add(nodeId);
      }
    }
    if (staleNodes.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _inLayout) return;
      // Re-check retention — scroll position may have changed.
      final currentRetained = renderObject.retainedNodeIds;
      owner!.buildScope(this, () {
        for (final nodeId in staleNodes) {
          if (currentRetained.contains(nodeId)) continue;
          final element = _children.remove(nodeId);
          if (element != null) {
            updateChild(element, null, nodeId);
          }
        }
      });
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
