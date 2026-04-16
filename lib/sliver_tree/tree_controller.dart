/// Controller that manages tree state, visibility, and animations.
library;

import 'dart:collection';
import 'dart:ui' show lerpDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'types.dart';

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
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.indentWidth = 0.0,
    this.comparator,
  }) : _vsync = vsync;

  final TickerProvider _vsync;

  /// Duration for expand/collapse animations.
  final Duration animationDuration;

  /// Curve for expand/collapse animations.
  final Curve animationCurve;

  /// Horizontal indent per depth level in logical pixels.
  final double indentWidth;

  /// Optional comparator for maintaining sorted order among siblings.
  ///
  /// When set, [insertRoot] and [insert] automatically place new nodes at the
  /// correct sorted position (unless an explicit [index] is provided).
  /// [setRoots] and [setChildren] sort their input before storing.
  final Comparator<TreeNode<TKey, TData>>? comparator;

  // ══════════════════════════════════════════════════════════════════════════
  // ECS-STYLE COMPONENT STORAGE
  // ══════════════════════════════════════════════════════════════════════════

  /// Node data by key.
  final Map<TKey, TreeNode<TKey, TData>> _nodeData = {};

  /// Parent key for each node. Null for root nodes.
  final Map<TKey, TKey?> _parents = {};

  /// Ordered list of child IDs for each node.
  final Map<TKey, List<TKey>> _children = {};

  /// Cached depth for each node (0 for roots).
  final Map<TKey, int> _depths = {};

  /// Expansion state for each node.
  final Map<TKey, bool> _expanded = {};

  // ══════════════════════════════════════════════════════════════════════════
  // VISIBILITY STATE
  // ══════════════════════════════════════════════════════════════════════════

  /// Root node IDs in order.
  final List<TKey> _roots = [];

  /// Flattened list of visible node IDs in render order.
  /// Includes nodes that are animating out (exiting).
  final List<TKey> _visibleOrder = [];

  /// Fast lookup: node key → index in [_visibleOrder].
  final Map<TKey, int> _visibleIndex = {};

  // ══════════════════════════════════════════════════════════════════════════
  // ANIMATION STATE
  // ══════════════════════════════════════════════════════════════════════════

  /// Animation state for nodes animating via standalone ticker.
  /// Used for inserts, removes, and cross-group transitions.
  final Map<TKey, AnimationState> _standaloneAnimations = {};

  /// Ticker for standalone animations only.
  Ticker? _standaloneTicker;
  Duration? _lastStandaloneTickTime;

  /// The current bulk animation group (for expandAll/collapseAll).
  /// Only one bulk group is active at a time. New bulk operations
  /// reverse or replace this group.
  AnimationGroup<TKey>? _bulkAnimationGroup;

  /// Per-operation animation groups (for individual expand/collapse).
  /// Key is the operation key (the node whose expand/collapse created the group).
  final Map<TKey, OperationGroup<TKey>> _operationGroups = {};

  /// Reverse lookup: node key → operation group key.
  /// Provides O(1) group membership checks.
  final Map<TKey, TKey> _nodeToOperationGroup = {};

  /// Cached full extents for nodes (measured size before animation).
  final Map<TKey, double> _fullExtents = {};

  /// Nodes pending deletion (animating out due to remove(), not collapse).
  /// These nodes should be fully removed from data structures when their
  /// exit animation completes.
  final Set<TKey> _pendingDeletion = {};

  /// Listeners notified on every animation tick (layout-only updates).
  final List<VoidCallback> _animationListeners = [];

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
  /// Returns an unmodifiable view of the internal list.
  /// The wrapper reflects mutations to [_visibleOrder] automatically.
  late final List<TKey> visibleNodes = UnmodifiableListView<TKey>(
    _visibleOrder,
  );

  /// Number of visible nodes.
  int get visibleNodeCount => _visibleOrder.length;

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
    final c = _children[key];
    if (c == null || c.isEmpty) return const [];
    return UnmodifiableListView<TKey>(c);
  }

  /// Gets the node data for the given key, or null if not found.
  TreeNode<TKey, TData>? getNodeData(TKey key) {
    return _nodeData[key];
  }

  /// Gets the depth of the given node (0 for roots).
  int getDepth(TKey key) {
    return _depths[key] ?? 0;
  }

  /// Gets the horizontal indent for the given node.
  double getIndent(TKey key) {
    return getDepth(key) * indentWidth;
  }

  /// Whether the given node is expanded.
  bool isExpanded(TKey key) {
    return _expanded[key] ?? false;
  }

  /// Whether the given node has children.
  bool hasChildren(TKey key) {
    final c = _children[key];
    return c != null && c.isNotEmpty;
  }

  /// Gets the number of children for the given node.
  int getChildCount(TKey key) {
    return _children[key]?.length ?? 0;
  }

  /// Whether any nodes are currently animating.
  ///
  /// Used by the element and render object to defer expensive operations
  /// (like stale-node eviction and sticky precomputation) during animation.
  bool get hasActiveAnimations =>
      _standaloneAnimations.isNotEmpty ||
      _operationGroups.isNotEmpty ||
      (_bulkAnimationGroup != null && !_bulkAnimationGroup!.isEmpty);

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

  /// Whether the given node is currently animating.
  bool isAnimating(TKey key) {
    if (_standaloneAnimations.containsKey(key)) return true;
    if (_nodeToOperationGroup.containsKey(key)) return true;
    if (_bulkAnimationGroup?.members.contains(key) == true) return true;
    return false;
  }

  /// Gets the animation state for a node, or null if not animating.
  ///
  /// Returns the standalone state if present, a synthetic entering state
  /// for operation group members that are expanding, or null for bulk/
  /// collapsing groups.
  AnimationState? getAnimationState(TKey key) {
    // 1. Standalone animations
    final standalone = _standaloneAnimations[key];
    if (standalone != null) return standalone;

    // 2. Operation group
    final groupKey = _nodeToOperationGroup[key];
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
    final groupKey = _nodeToOperationGroup[key];
    if (groupKey != null) {
      final group = _operationGroups[groupKey];
      if (group != null && group.pendingRemoval.contains(key)) return true;
    }
    // Check standalone animations
    final animation = _standaloneAnimations[key];
    return animation != null && animation.type == AnimationType.exiting;
  }

  /// Gets the estimated full extent for a node.
  ///
  /// Returns the cached measured extent if available, otherwise [defaultExtent].
  double getEstimatedExtent(TKey key) {
    return _fullExtents[key] ?? defaultExtent;
  }

  /// Gets the current extent for a node, accounting for animation.
  double getCurrentExtent(TKey key) {
    return getAnimatedExtent(key, _fullExtents[key] ?? defaultExtent);
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
    final groupKey = _nodeToOperationGroup[key];
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
    final animation = _standaloneAnimations[key];
    if (animation == null) return fullExtent;

    final t = animationCurve.transform(animation.progress.clamp(0.0, 1.0));
    if (animation.targetExtent == _unknownExtent) {
      return animation.type == AnimationType.entering
          ? fullExtent * t
          : fullExtent * (1.0 - t);
    }
    return lerpDouble(animation.startExtent, animation.targetExtent, t)!;
  }

  /// Stores the measured full extent for a node.
  ///
  /// Called by the render object after laying out a child.
  void setFullExtent(TKey key, double extent) {
    final oldExtent = _fullExtents[key];

    // Check operation group member — resolve unknown extents
    final groupKey = _nodeToOperationGroup[key];
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
          } else if (oldExtent != extent) {
            // targetExtent is the "fully expanded" reference (value=1);
            // startExtent is always 0 (fully collapsed). Update targetExtent
            // regardless of direction — during reverse (collapsing), setting
            // startExtent = extent would make the lerp return `extent` at
            // value=0 instead of 0, so the node would never collapse to zero.
            member.targetExtent = extent;
          }
        }
      }
      _fullExtents[key] = extent;
      return;
    }

    if (oldExtent == extent) {
      // Still resolve unknown targets even when extent matches.
      final animation = _standaloneAnimations[key];
      if (animation != null && animation.targetExtent == _unknownExtent) {
        if (animation.type == AnimationType.entering) {
          animation.targetExtent = extent;
          animation.updateExtent(animationCurve);
        }
      }
      return;
    }
    _fullExtents[key] = extent;
    // If node is animating with unknown target, update the animation
    final animation = _standaloneAnimations[key];
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
      } else if (animation.type == AnimationType.exiting) {
        // For exiting, start extent might need updating
        animation.startExtent = extent;
        animation.updateExtent(animationCurve);
      }
    }
  }

  /// Gets the index of a node in the visible order, or -1 if not visible.
  int getVisibleIndex(TKey key) {
    return _visibleIndex[key] ?? -1;
  }

  /// Gets the parent key for the given node, or null if it is a root.
  TKey? getParent(TKey key) => _parents[key];

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

  /// Binary-searches [siblings] for the sorted insertion index of [node]
  /// using [comparator]. Skips pending-deletion keys.
  int _sortedIndex(List<TKey> siblings, TreeNode<TKey, TData> node) {
    assert(comparator != null);
    // Build a list of live siblings (skip pending-deletion).
    final live = <TKey>[
      for (final k in siblings)
        if (!_pendingDeletion.contains(k)) k,
    ];
    int lo = 0, hi = live.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final midNode = _nodeData[live[mid]]!;
      if (comparator!(midNode, node) <= 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    // Map back to the full siblings list index (including pending-deletion).
    if (lo >= live.length) return siblings.length;
    return siblings.indexOf(live[lo]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TREE MUTATIONS
  // ══════════════════════════════════════════════════════════════════════════

  /// Initializes the tree with the given root nodes.
  ///
  /// This clears any existing state.
  void setRoots(List<TreeNode<TKey, TData>> roots) {
    _clear();
    final sorted = comparator != null ? (List.of(roots)..sort(comparator)) : roots;
    for (final node in sorted) {
      _nodeData[node.key] = node;
      _parents[node.key] = null;
      _children[node.key] = [];
      _depths[node.key] = 0;
      _expanded[node.key] = false;
      _roots.add(node.key);
      _visibleOrder.add(node.key);
    }
    _rebuildVisibleIndex();
    _structureGeneration++;
    notifyListeners();
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
  }) {
    if (animationDuration == Duration.zero) animate = false;
    // If the node is pending deletion, cancel the deletion
    if (_pendingDeletion.contains(node.key)) {
      // If the node was pending deletion under a non-null parent, detach
      // it and re-attach as a root. Without this relocation, cancelling
      // the deletion would resurrect it under its old parent, silently
      // ignoring the insertRoot() contract.
      final oldParent = _parents[node.key];
      if (oldParent != null) {
        _children[oldParent]?.remove(node.key);
        _parents[node.key] = null;
        final effectiveIndex = index ??
            (comparator != null ? _sortedIndex(_roots, node) : null);
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
      _cancelDeletion(node.key, animate: animate);
      _nodeData[node.key] = node;
      // Reset expansion state so a subsequent expand() works cleanly.
      _expanded[node.key] = false;
      // Descendants had their exit animations reversed by _cancelDeletion,
      // but the parent is now collapsed so they should not be visible.
      // Remove their animations and rebuild the visible order.
      final descendants = _getDescendants(node.key);
      for (final desc in descendants) {
        _removeAnimation(desc);
      }
      _rebuildVisibleOrder();
      _structureGeneration++;
      notifyListeners();
      return;
    }

    // Node is already present (e.g. restored by an ancestor's
    // _cancelDeletion, or a live re-insert). Update the data and — if the
    // caller requested a different location — relocate it to honor the
    // insertRoot(index:) contract instead of silently dropping the index.
    if (_nodeData.containsKey(node.key)) {
      _nodeData[node.key] = node;
      final currentParent = _parents[node.key];
      if (currentParent != null) {
        // Different parent — delegate to moveNode.
        moveNode(node.key, null, index: index);
        return;
      }
      final currentRootIndex = _roots.indexOf(node.key);
      final desiredIndex = index ??
          (comparator != null ? _sortedIndex(_roots, node) : null);
      final wantsRelocate = desiredIndex != null &&
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
      notifyListeners();
      return;
    }

    // Add to data structures
    _nodeData[node.key] = node;
    _parents[node.key] = null;
    _children[node.key] = [];
    _depths[node.key] = 0;
    _expanded[node.key] = false;

    // Add to roots list
    final effectiveIndex = index ?? (comparator != null ? _sortedIndex(_roots, node) : null);
    // Compute visible insert position BEFORE modifying _roots, since
    // _calculateRootInsertIndex reads _roots[effectiveIndex].
    final visibleInsertIndex = effectiveIndex != null && effectiveIndex < _roots.length
        ? _calculateRootInsertIndex(effectiveIndex)
        : _visibleOrder.length;
    if (effectiveIndex != null && effectiveIndex < _roots.length) {
      _roots.insert(effectiveIndex, node.key);
    } else {
      _roots.add(node.key);
    }

    // Add to visible order (root nodes are always visible)
    final insertIndex = visibleInsertIndex;
    _visibleOrder.insert(insertIndex, node.key);
    _updateIndicesFrom(insertIndex);
    _structureGeneration++;

    if (animate) {
      _startStandaloneEnterAnimation(node.key);
    }

    notifyListeners();
  }

  /// Calculates the visible order index for inserting a root at the given root index.
  int _calculateRootInsertIndex(int rootIndex) {
    if (rootIndex == 0) return 0;
    if (rootIndex >= _roots.length) return _visibleOrder.length;

    // Find the root at the given index and return its visible index
    final rootId = _roots[rootIndex];
    return _visibleIndex[rootId] ?? _visibleOrder.length;
  }

  /// Adds children to a node.
  ///
  /// The children are added but not visible until the parent is expanded.
  /// If the parent already has children, the old children and their
  /// descendants are purged from all data structures first.
  void setChildren(TKey parentKey, List<TreeNode<TKey, TData>> children) {
    assert(
      _nodeData.containsKey(parentKey),
      'Parent node $parentKey not found',
    );
    assert(
      !_pendingDeletion.contains(parentKey),
      'Cannot setChildren on $parentKey while it is animating out '
      '(pending deletion). The parent will be purged when its exit animation '
      'completes, leaving the new children orphaned.',
    );

    // Purge old children and their descendants before overwriting.
    final oldChildren = _children[parentKey];
    if (oldChildren != null && oldChildren.isNotEmpty) {
      final allOldKeys = <TKey>[];
      for (final oldChildKey in oldChildren) {
        allOldKeys.add(oldChildKey);
        _getDescendantsInto(oldChildKey, allOldKeys);
      }

      // Check visibility and contiguity BEFORE purging (purge removes from _visibleIndex)
      int minIdx = _visibleOrder.length;
      int maxIdx = -1;
      int visibleCount = 0;
      for (final key in allOldKeys) {
        final idx = _visibleIndex[key];
        if (idx != null) {
          visibleCount++;
          if (idx < minIdx) minIdx = idx;
          if (idx > maxIdx) maxIdx = idx;
        }
      }

      final oldKeySet = allOldKeys.toSet();
      for (final key in allOldKeys) {
        _purgeNodeData(key);
      }

      if (visibleCount > 0) {
        if (maxIdx - minIdx + 1 == visibleCount) {
          // Contiguous removal
          _visibleOrder.removeRange(minIdx, maxIdx + 1);
          _updateIndicesAfterRemove(minIdx);
        } else {
          // Non-contiguous removal
          _visibleOrder.removeWhere(oldKeySet.contains);
          _rebuildVisibleIndex();
        }
        _structureGeneration++;
      }
    }

    final parentDepth = _depths[parentKey] ?? 0;
    final childIds = <TKey>[];
    final sorted = comparator != null ? (List.of(children)..sort(comparator)) : children;

    for (final child in sorted) {
      _nodeData[child.key] = child;
      _parents[child.key] = parentKey;
      _children[child.key] = [];
      _depths[child.key] = parentDepth + 1;
      _expanded[child.key] = false;
      childIds.add(child.key);
    }

    _children[parentKey] = childIds;

    // If parent is expanded and visible, insert new children into the
    // visible order so they render immediately.
    if (_expanded[parentKey] == true && childIds.isNotEmpty) {
      final parentIdx = _visibleIndex[parentKey];
      if (parentIdx != null) {
        final insertIdx = parentIdx + 1;
        _visibleOrder.insertAll(insertIdx, childIds);
        _updateIndicesFrom(insertIdx);
        _structureGeneration++;
      }
    }

    notifyListeners();
  }

  /// Inserts a new node as a child of the given parent.
  ///
  /// If [animate] is true, the node will animate in.
  void insert({
    required TKey parentKey,
    required TreeNode<TKey, TData> node,
    int? index,
    bool animate = true,
  }) {
    if (animationDuration == Duration.zero) animate = false;
    assert(
      _nodeData.containsKey(parentKey),
      "Parent node $parentKey not found",
    );
    // If the node is pending deletion, cancel the deletion
    if (_pendingDeletion.contains(node.key)) {
      // If the pending-deletion node lives under a different parent (or is
      // a root), move it to [parentKey] before cancelling the deletion.
      // Without this relocation, cancelDeletion would resurrect the node
      // under its old parent, silently ignoring the parentKey/index args.
      final oldParent = _parents[node.key];
      if (oldParent != parentKey) {
        if (oldParent != null) {
          _children[oldParent]?.remove(node.key);
        } else {
          _roots.remove(node.key);
        }
        _parents[node.key] = parentKey;
        final siblings = _children[parentKey] ??= [];
        final effectiveIndex = index ??
            (comparator != null ? _sortedIndex(siblings, node) : null);
        if (effectiveIndex != null && effectiveIndex < siblings.length) {
          siblings.insert(effectiveIndex, node.key);
        } else {
          siblings.add(node.key);
        }
        final parentDepth = _depths[parentKey] ?? 0;
        _refreshSubtreeDepths(node.key, parentDepth + 1);
      } else if (index != null) {
        // Same parent — honor an explicitly requested index by relocating
        // within the sibling list.
        final siblings = _children[parentKey] ??= [];
        final current = siblings.indexOf(node.key);
        if (current != -1) {
          siblings.removeAt(current);
          final clamped = index.clamp(0, siblings.length);
          siblings.insert(clamped, node.key);
        }
      }
      _cancelDeletion(node.key, animate: animate);
      _nodeData[node.key] = node;
      // Reset expansion state so a subsequent expand() works cleanly.
      _expanded[node.key] = false;
      // Descendants had their exit animations reversed by _cancelDeletion,
      // but the parent is now collapsed so they should not be visible.
      // Remove their animations and rebuild the visible order.
      final descendants = _getDescendants(node.key);
      for (final desc in descendants) {
        _removeAnimation(desc);
      }
      _rebuildVisibleOrder();
      _structureGeneration++;
      notifyListeners();
      return;
    }
    // Node is already present (e.g. restored by an ancestor's
    // _cancelDeletion, or a live re-insert). Update the data and — if the
    // caller requested a different location — relocate it to honor the
    // insert(parentKey:, index:) contract instead of silently dropping it.
    if (_nodeData.containsKey(node.key)) {
      _nodeData[node.key] = node;
      final currentParent = _parents[node.key];
      if (currentParent != parentKey) {
        // Different parent — delegate to moveNode.
        moveNode(node.key, parentKey, index: index);
        return;
      }
      final siblings = _children[parentKey] ??= [];
      final currentIndex = siblings.indexOf(node.key);
      final desiredIndex = index ??
          (comparator != null ? _sortedIndex(siblings, node) : null);
      final wantsRelocate = desiredIndex != null &&
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
      notifyListeners();
      return;
    }
    final parentDepth = _depths[parentKey] ?? 0;
    // Add to data structures
    _nodeData[node.key] = node;
    _parents[node.key] = parentKey;
    _children[node.key] = [];
    _depths[node.key] = parentDepth + 1;
    _expanded[node.key] = false;
    // Add to parent's children
    final siblings = _children[parentKey] ??= [];
    final effectiveIndex = index ?? (comparator != null ? _sortedIndex(siblings, node) : null);
    if (effectiveIndex != null && effectiveIndex < siblings.length) {
      siblings.insert(effectiveIndex, node.key);
    } else {
      siblings.add(node.key);
    }
    // If parent is expanded, add to visible order
    if (_expanded[parentKey] == true) {
      if (_visibleIndex[parentKey] case final int parentVisibleIndex) {
        int insertIndex = parentVisibleIndex + 1;
        // Find position among siblings
        if (effectiveIndex != null) {
          for (int i = 0; i < effectiveIndex && i < siblings.length - 1; i++) {
            final siblingId = siblings[i];
            if (_visibleIndex[siblingId] case final int siblingIndex) {
              insertIndex =
                  siblingIndex + 1 + _countVisibleDescendants(siblingId);
            }
          }
        } else {
          // Append after last visible descendant of parent
          // Note: _countVisibleDescendants only counts nodes in _visibleIndex,
          // so the newly added node (not yet in _visibleIndex) is not counted.
          insertIndex =
              parentVisibleIndex + 1 + _countVisibleDescendants(parentKey);
        }
        _visibleOrder.insert(insertIndex, node.key);
        _updateIndicesFrom(insertIndex);
        _structureGeneration++;
        if (animate) {
          _startStandaloneEnterAnimation(node.key);
        }
      }
    }
    notifyListeners();
  }

  /// Removes a node and all its descendants from the tree.
  ///
  /// If [animate] is true, the nodes will animate out.
  void remove({required TKey key, bool animate = true}) {
    if (animationDuration == Duration.zero) animate = false;
    if (!_nodeData.containsKey(key)) {
      return;
    }
    final descendants = _getDescendants(key);
    final nodesToRemove = [key, ...descendants];
    if (animate && _visibleIndex.containsKey(key)) {
      // Mark nodes as pending deletion so _finalizeAnimation knows to
      // fully remove them (vs just hiding due to parent collapse)
      _pendingDeletion.addAll(nodesToRemove);
      // Mark all visible nodes as exiting
      for (final nodeId in nodesToRemove) {
        if (_visibleIndex.containsKey(nodeId)) {
          _startStandaloneExitAnimation(nodeId);
        }
      }
    } else {
      _removeNodesImmediate(nodesToRemove);
      _structureGeneration++;
    }
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RETAINED-NODE UPDATE, REORDER, AND MOVE
  // ══════════════════════════════════════════════════════════════════════════

  /// Updates the data payload for an existing node without structural changes.
  ///
  /// Preserves the node's position, expansion state, and animation state.
  /// Notifies listeners so that mounted widgets rebuild with the new data.
  void updateNode(TreeNode<TKey, TData> node) {
    assert(_nodeData.containsKey(node.key), 'Node ${node.key} not found');
    _nodeData[node.key] = node;
    notifyListeners();
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
      if (_pendingDeletion.contains(k)) {
        pendingRoots.add(k);
      } else {
        liveRootSet.add(k);
      }
    }
    assert(
      orderedKeys.length == liveRootSet.length &&
          orderedKeys.toSet().length == orderedKeys.length &&
          liveRootSet.containsAll(orderedKeys),
      'orderedKeys must contain exactly the current live root keys',
    );

    _roots
      ..clear()
      ..addAll(orderedKeys)
      ..addAll(pendingRoots);
    _rebuildVisibleOrder();
    _structureGeneration++;
    notifyListeners();
  }

  /// Reorders the children of [parentKey] to match [orderedKeys].
  ///
  /// [orderedKeys] must contain exactly the current live (non-pending-deletion)
  /// children of [parentKey]. Expansion state, animation state, and measured
  /// extents are preserved.
  void reorderChildren(TKey parentKey, List<TKey> orderedKeys) {
    assert(_nodeData.containsKey(parentKey), 'Parent $parentKey not found');
    final currentChildren = _children[parentKey] ?? <TKey>[];

    final pendingChildren = <TKey>[];
    final liveChildSet = <TKey>{};
    for (final k in currentChildren) {
      if (_pendingDeletion.contains(k)) {
        pendingChildren.add(k);
      } else {
        liveChildSet.add(k);
      }
    }
    assert(
      orderedKeys.length == liveChildSet.length &&
          orderedKeys.toSet().length == orderedKeys.length &&
          liveChildSet.containsAll(orderedKeys),
      'orderedKeys must contain exactly the current live children of $parentKey',
    );

    _children[parentKey] = [...orderedKeys, ...pendingChildren];
    bool needsVisibleRebuild =
        _expanded[parentKey] == true && _areAncestorsExpanded(parentKey);
    if (!needsVisibleRebuild) {
      // Even if the parent is not expanded, children may still be present
      // in _visibleOrder because they are mid-animation (collapse in
      // progress, pending-deletion exit). Those entries would otherwise
      // retain the old order until the animation completes.
      for (final child in _children[parentKey]!) {
        if (_nodeToOperationGroup.containsKey(child) ||
            _bulkAnimationGroup?.members.contains(child) == true ||
            _standaloneAnimations.containsKey(child)) {
          needsVisibleRebuild = true;
          break;
        }
      }
    }
    if (needsVisibleRebuild) {
      _rebuildVisibleOrder();
      _structureGeneration++;
    }
    notifyListeners();
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
  /// animation finalizes — callers that need animation on the new position
  /// should trigger it explicitly after the move.
  void moveNode(TKey key, TKey? newParentKey, {int? index}) {
    assert(_nodeData.containsKey(key), 'Node $key not found');
    assert(
      newParentKey == null || _nodeData.containsKey(newParentKey),
      'New parent $newParentKey not found',
    );
    // Guard against cycles.
    assert(
      newParentKey == null || !_getDescendants(key).contains(newParentKey),
      'Cannot move $key under its own descendant $newParentKey',
    );

    final oldParent = _parents[key];
    if (oldParent == newParentKey) return; // already there

    // Cancel any animation/deletion state tied to the moved subtree's old
    // position. Without this, a node caught mid-exit-animation would still
    // be purged by _finalizeAnimation after the move, destroying the subtree
    // under its new parent.
    _cancelAnimationStateForSubtree(key);

    // Remove from old parent's child list (or roots).
    if (oldParent != null) {
      _children[oldParent]?.remove(key);
    } else {
      _roots.remove(key);
    }

    // Insert into new parent's child list (or roots).
    _parents[key] = newParentKey;
    final node = _nodeData[key]!;
    if (newParentKey != null) {
      final siblings = _children[newParentKey] ??= [];
      final effectiveIndex = index ?? (comparator != null ? _sortedIndex(siblings, node) : null);
      if (effectiveIndex != null && effectiveIndex < siblings.length) {
        siblings.insert(effectiveIndex, key);
      } else {
        siblings.add(key);
      }
    } else {
      final effectiveIndex = index ?? (comparator != null ? _sortedIndex(_roots, node) : null);
      if (effectiveIndex != null && effectiveIndex < _roots.length) {
        _roots.insert(effectiveIndex, key);
      } else {
        _roots.add(key);
      }
    }

    final newDepth = newParentKey != null
        ? (_depths[newParentKey] ?? 0) + 1
        : 0;
    _refreshSubtreeDepths(key, newDepth);

    _rebuildVisibleOrder();
    _structureGeneration++;
    notifyListeners();
  }

  /// Recursively sets [_depths] for [key] and all its descendants.
  void _refreshSubtreeDepths(TKey key, int depth) {
    _depths[key] = depth;
    final children = _children[key];
    if (children != null) {
      for (final childKey in children) {
        _refreshSubtreeDepths(childKey, depth + 1);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EXPAND / COLLAPSE
  // ══════════════════════════════════════════════════════════════════════════

  /// Expands the given node, revealing its children.
  void expand({required TKey key, bool animate = true}) {
    if (animationDuration == Duration.zero) animate = false;
    if (!_nodeData.containsKey(key)) {
      return;
    }
    if (_expanded[key] == true) {
      return;
    }
    final children = _children[key];
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
    if (!_areAncestorsExpanded(key)) {
      _expanded[key] = true;
      notifyListeners();
      return;
    }
    _expanded[key] = true;
    // Find where to insert children in visible order
    final parentIndex = _visibleIndex[key];
    if (parentIndex == null) {
      return;
    }

    if (!animate) {
      // No animation — insert and return
      final nodesToShow = _flattenSubtree(key, includeRoot: false);
      final nodesToInsert = <TKey>[];
      for (final nodeId in nodesToShow) {
        if (_pendingDeletion.contains(nodeId)) continue;
        if (!_visibleIndex.containsKey(nodeId)) {
          nodesToInsert.add(nodeId);
        } else {
          _removeAnimation(nodeId);
        }
      }
      if (nodesToInsert.isNotEmpty) {
        final insertIndex = parentIndex + 1;
        _visibleOrder.insertAll(insertIndex, nodesToInsert);
        _updateIndicesFrom(insertIndex);
      }
      _structureGeneration++;
      notifyListeners();
      return;
    }

    // Animated expand
    final existingGroup = _operationGroups[key];
    if (existingGroup != null) {
      // Path 1: Reversing a collapse — group already exists
      existingGroup.pendingRemoval.clear();
      existingGroup.controller.forward();

      // Handle descendants NOT in this group (from nested expansions)
      final nodesToShow = _flattenSubtree(key, includeRoot: false);
      for (final nodeId in nodesToShow) {
        if (_pendingDeletion.contains(nodeId)) continue;
        if (existingGroup.members.containsKey(nodeId)) continue;

        if (_standaloneAnimations[nodeId] case final anim?
            when anim.type == AnimationType.exiting) {
          // Reverse the exit to an enter with speedMultiplier
          _startStandaloneEnterAnimation(nodeId);
        } else if (!_visibleIndex.containsKey(nodeId)) {
          // New node not yet visible — insert and animate
          // Find insertion point
          _insertNodeIntoVisibleOrder(nodeId, parentIndex);
          _startStandaloneEnterAnimation(nodeId);
        }
      }
      _structureGeneration++;
      notifyListeners();
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
    _operationGroups[key] = group;

    controller.addListener(_notifyAnimationListeners);
    controller.addStatusListener((status) {
      // Identity guard: if the group under [key] has been replaced (e.g. after
      // a purge + re-expand), ignore status events from the stale instance.
      if (!identical(_operationGroups[key], group)) return;
      _onOperationGroupStatusChange(key, status);
    });

    // Fast path check: count new vs existing nodes
    int newNodeCount = 0;
    int effectiveCount = 0;
    for (final nodeId in nodesToShow) {
      if (_pendingDeletion.contains(nodeId)) continue;
      effectiveCount++;
      if (!_visibleIndex.containsKey(nodeId)) {
        newNodeCount++;
      }
    }

    if (newNodeCount == 0) {
      // All nodes already visible (reversing collapse animation)
      for (final nodeId in nodesToShow) {
        if (_pendingDeletion.contains(nodeId)) continue;
        final capturedExtent = _captureAndRemoveFromGroups(nodeId);
        final nge = NodeGroupExtent(
          startExtent: capturedExtent ?? 0.0,
          targetExtent: _fullExtents[nodeId] ?? _unknownExtent,
        );
        group.members[nodeId] = nge;
        _nodeToOperationGroup[nodeId] = key;
      }
    } else if (newNodeCount == effectiveCount) {
      // All nodes need insertion (normal expand)
      final nodesToInsert = <TKey>[];
      for (final nodeId in nodesToShow) {
        if (_pendingDeletion.contains(nodeId)) continue;
        final capturedExtent = _captureAndRemoveFromGroups(nodeId);
        final nge = NodeGroupExtent(
          startExtent: capturedExtent ?? 0.0,
          targetExtent: _fullExtents[nodeId] ?? _unknownExtent,
        );
        group.members[nodeId] = nge;
        _nodeToOperationGroup[nodeId] = key;
        nodesToInsert.add(nodeId);
      }
      final insertIndex = parentIndex + 1;
      _visibleOrder.insertAll(insertIndex, nodesToInsert);
      _updateIndicesFrom(insertIndex);
    } else {
      // Mixed path: some visible (exiting), some need insertion
      int currentInsertIndex = parentIndex + 1;
      int insertOffset = 0;
      int minInsertIndex = _visibleOrder.length;
      for (final nodeId in nodesToShow) {
        if (_pendingDeletion.contains(nodeId)) continue;
        final existingIndex = _visibleIndex[nodeId];
        final capturedExtent = _captureAndRemoveFromGroups(nodeId);
        final nge = NodeGroupExtent(
          startExtent: capturedExtent ?? 0.0,
          targetExtent: _fullExtents[nodeId] ?? _unknownExtent,
        );
        group.members[nodeId] = nge;
        _nodeToOperationGroup[nodeId] = key;

        if (existingIndex != null) {
          // Node already visible (was exiting)
          currentInsertIndex = existingIndex + insertOffset + 1;
        } else {
          // Insert at current position
          if (currentInsertIndex < minInsertIndex) {
            minInsertIndex = currentInsertIndex;
          }
          _visibleOrder.insert(currentInsertIndex, nodeId);
          insertOffset++;
          currentInsertIndex++;
        }
      }
      if (insertOffset > 0) {
        for (int i = minInsertIndex; i < _visibleOrder.length; i++) {
          _visibleIndex[_visibleOrder[i]] = i;
        }
        _assertIndexConsistency();
      }
    }

    _structureGeneration++;
    controller.forward();
    notifyListeners();
  }

  /// Collapses the given node, hiding its children.
  ///
  /// Note: This preserves the expansion state of descendant nodes. When the
  /// node is re-expanded, any previously expanded children will also show
  /// their children automatically.
  void collapse({required TKey key, bool animate = true}) {
    if (animationDuration == Duration.zero) animate = false;
    if (!_nodeData.containsKey(key) || _expanded[key] == false) {
      return;
    }
    _expanded[key] = false;
    // Find all visible descendants (includes nodes currently entering)
    final descendants = _getVisibleDescendants(key);
    if (descendants.isEmpty) {
      notifyListeners();
      return;
    }

    if (!animate) {
      // Remove immediately from visible order
      final toRemove = <TKey>{};
      for (final nodeId in descendants) {
        if (!_pendingDeletion.contains(nodeId)) {
          toRemove.add(nodeId);
          _removeAnimation(nodeId);
        }
      }
      if (toRemove.isNotEmpty) {
        _removeFromVisibleOrder(toRemove);
        _structureGeneration++;
      }
      notifyListeners();
      return;
    }

    // Animated collapse
    final existingGroup = _operationGroups[key];
    if (existingGroup != null) {
      // Path 1: Reversing an expand — group already exists
      for (final nodeId in existingGroup.members.keys) {
        existingGroup.pendingRemoval.add(nodeId);
      }
      existingGroup.controller.reverse();

      // Handle descendants NOT in this group (from nested expansions)
      for (final nodeId in descendants) {
        if (_pendingDeletion.contains(nodeId)) continue;
        if (existingGroup.members.containsKey(nodeId)) continue;
        // Create standalone exit animation with speedMultiplier
        _startStandaloneExitAnimation(nodeId, triggeringAncestorId: key);
      }
      _structureGeneration++;
      notifyListeners();
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
    _operationGroups[key] = group;

    controller.addListener(_notifyAnimationListeners);
    controller.addStatusListener((status) {
      // Identity guard: if the group under [key] has been replaced (e.g. after
      // a purge + re-expand), ignore status events from the stale instance.
      if (!identical(_operationGroups[key], group)) return;
      _onOperationGroupStatusChange(key, status);
    });

    for (final nodeId in descendants) {
      if (_pendingDeletion.contains(nodeId)) continue;
      final capturedExtent = _captureAndRemoveFromGroups(nodeId);
      final nge = NodeGroupExtent(
        startExtent: 0.0,
        targetExtent: capturedExtent ?? (_fullExtents[nodeId] ?? defaultExtent),
      );
      group.members[nodeId] = nge;
      group.pendingRemoval.add(nodeId);
      _nodeToOperationGroup[nodeId] = key;
    }

    _structureGeneration++;
    controller.reverse();
    notifyListeners();
  }

  /// Toggles the expansion state of the given node.
  void toggle({required TKey key, bool animate = true}) {
    if (_expanded[key] == true) {
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

    void collectRecursive(TKey key) {
      if (_pendingDeletion.contains(key)) return;
      final children = _children[key];
      if (children == null || children.isEmpty) return;

      final depth = _depths[key] ?? 0;
      final withinDepthLimit = maxDepth == null || depth < maxDepth;

      if (withinDepthLimit && _expanded[key] != true) {
        nodesToExpand.add(key);
        for (final childId in children) {
          if (!_visibleIndex.containsKey(childId)) {
            nodesToShow.add(childId);
          }
        }
      }

      // Still check children for exiting animations regardless of depth.
      for (final childId in children) {
        // Check standalone exiting
        final animation = _standaloneAnimations[childId];
        if (animation != null && animation.type == AnimationType.exiting) {
          if (!_pendingDeletion.contains(childId)) {
            nodesToReverseExit.add(childId);
          }
        }
        // Check operation group exiting (pendingRemoval)
        final opGroupKey = _nodeToOperationGroup[childId];
        if (opGroupKey != null) {
          final opGroup = _operationGroups[opGroupKey];
          if (opGroup != null && opGroup.pendingRemoval.contains(childId)) {
            if (!_pendingDeletion.contains(childId)) {
              nodesToReverseExit.add(childId);
            }
          }
        }
      }

      // Only recurse into children if within depth limit.
      if (withinDepthLimit) {
        for (final childId in children) {
          collectRecursive(childId);
        }
      }
    }

    // Collect from all roots
    for (final rootId in _roots) {
      collectRecursive(rootId);
    }
    if (nodesToExpand.isEmpty && nodesToReverseExit.isEmpty) {
      return;
    }
    // Batch update expansion states
    for (final key in nodesToExpand) {
      _expanded[key] = true;
    }
    // Rebuild visible order from scratch (more efficient for bulk operations)
    _rebuildVisibleOrder();
    _structureGeneration++;
    // Start animations for newly visible nodes and reverse exiting animations
    if (animate) {
      // Reverse collapsing operation groups
      for (final entry in _operationGroups.entries) {
        final group = entry.value;
        if (group.pendingRemoval.isNotEmpty) {
          group.pendingRemoval.clear();
          group.controller.forward();
        }
      }

      // Check if there's a collapsing bulk animation we can reverse
      if (_bulkAnimationGroup != null &&
          _bulkAnimationGroup!.pendingRemoval.isNotEmpty) {
        // Reverse the animation - nodes being removed will now expand
        // Clear pending removal since we're expanding now
        _bulkAnimationGroup!.pendingRemoval.clear();

        // Reverse standalone exit animations smoothly
        for (final key in nodesToReverseExit) {
          if (!_nodeToOperationGroup.containsKey(key)) {
            _startStandaloneEnterAnimation(key);
          }
        }

        // Add any new nodes to the group (skip if already in an operation group)
        for (final key in nodesToShow) {
          if (_visibleIndex.containsKey(key) &&
              !_nodeToOperationGroup.containsKey(key)) {
            _bulkAnimationGroup!.members.add(key);
          }
        }

        // Reverse the controller direction
        _bulkAnimationGroup!.controller.forward();
      } else {
        // Dispose old group and create fresh to avoid status listener race
        _disposeBulkAnimationGroup();
        _bulkAnimationGroup = _createBulkAnimationGroup();

        // Reverse standalone exit animations smoothly
        for (final key in nodesToReverseExit) {
          if (!_nodeToOperationGroup.containsKey(key)) {
            _startStandaloneEnterAnimation(key);
          }
        }

        // Add new nodes to the bulk group (skip if already in an operation group)
        for (final key in nodesToShow) {
          if (_visibleIndex.containsKey(key) &&
              !_nodeToOperationGroup.containsKey(key)) {
            _bulkAnimationGroup!.members.add(key);
          }
        }

        // Start expanding (value 0 -> 1)
        _bulkAnimationGroup!.controller.forward();
      }
    } else {
      // Remove animations if not animating
      for (final key in nodesToReverseExit) {
        _removeAnimation(key);
      }
    }
    notifyListeners();
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
      if (_expanded[rootId] == true) {
        nodesToCollapse.add(rootId);
        nodesToHide.addAll(_getVisibleDescendants(rootId));
      }
    }
    // Also check for nodes that are entering (from an interrupted expandAll)
    final nodesToHideSet = nodesToHide.toSet();

    // Check standalone entering animations
    for (final entry in _standaloneAnimations.entries) {
      if (entry.value.type == AnimationType.entering) {
        if (!nodesToHideSet.contains(entry.key)) {
          if (_parents[entry.key] != null) {
            nodesToHide.add(entry.key);
            nodesToHideSet.add(entry.key);
          }
        }
      }
    }

    // Check operation group members (expanding)
    for (final group in _operationGroups.values) {
      if (group.pendingRemoval.isEmpty) {
        // Group is expanding
        for (final key in group.members.keys) {
          if (!nodesToHideSet.contains(key)) {
            if (_parents[key] != null) {
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
          if (_parents[key] != null) {
            nodesToHide.add(key);
            nodesToHideSet.add(key);
          }
        }
      }
    }

    if (nodesToHide.isEmpty) {
      if (nodesToCollapse.isNotEmpty) {
        if (maxDepth == null) {
          _expanded.updateAll((key, value) => false);
        } else {
          _expanded.updateAll((key, value) {
            if (!value) return false;
            final depth = _depths[key] ?? 0;
            return (depth < maxDepth) ? false : value;
          });
        }
        notifyListeners();
      }
      return;
    }
    // Clear expansion state for ALL nodes within depth limit,
    // not just visible ones.
    if (maxDepth == null) {
      _expanded.updateAll((key, value) => false);
    } else {
      _expanded.updateAll((key, value) {
        if (!value) return false;
        final depth = _depths[key] ?? 0;
        return (depth < maxDepth) ? false : value;
      });
    }
    _structureGeneration++;
    if (animate) {
      // Reverse expanding operation groups
      for (final entry in _operationGroups.entries) {
        final group = entry.value;
        if (group.pendingRemoval.isEmpty) {
          // Group is expanding — reverse it
          for (final nodeId in group.members.keys) {
            if (!_pendingDeletion.contains(nodeId)) {
              group.pendingRemoval.add(nodeId);
            }
          }
          group.controller.reverse();
        }
      }

      // Check if there's an expanding bulk animation we can reverse
      if (_bulkAnimationGroup != null &&
          _bulkAnimationGroup!.members.isNotEmpty &&
          _bulkAnimationGroup!.pendingRemoval.isEmpty) {
        // Mark all members for removal when animation completes at 0
        for (final key in _bulkAnimationGroup!.members) {
          if (!_pendingDeletion.contains(key)) {
            _bulkAnimationGroup!.pendingRemoval.add(key);
          }
        }

        // Handle additional nodes not in any group
        for (final key in nodesToHide) {
          if (_pendingDeletion.contains(key)) continue;
          if (!_bulkAnimationGroup!.members.contains(key) &&
              !_nodeToOperationGroup.containsKey(key)) {
            _startStandaloneExitAnimation(key);
          }
        }

        // Reverse the controller direction
        _bulkAnimationGroup!.controller.reverse();
      } else {
        // Dispose old group and create fresh with value=1.0
        _disposeBulkAnimationGroup();
        _bulkAnimationGroup = _createBulkAnimationGroup(initialValue: 1.0);

        // Add nodes to the bulk group, keeping individually-animating
        // nodes on their own timeline for smooth transitions.
        for (final key in nodesToHide) {
          if (_pendingDeletion.contains(key)) continue;
          if (_nodeToOperationGroup.containsKey(key)) continue;
          if (_standaloneAnimations.containsKey(key)) {
            // Reverse standalone animation smoothly
            _startStandaloneExitAnimation(key);
          } else {
            _removeAnimation(key);
            _bulkAnimationGroup!.members.add(key);
            _bulkAnimationGroup!.pendingRemoval.add(key);
          }
        }

        // Start collapsing (value 1 -> 0)
        if (_bulkAnimationGroup!.members.isNotEmpty) {
          _bulkAnimationGroup!.controller.reverse();
        }
      }
    } else {
      // Remove immediately
      final toRemove = <TKey>{};
      for (final key in nodesToHide) {
        if (!_pendingDeletion.contains(key)) {
          toRemove.add(key);
          _removeAnimation(key);
        }
      }
      if (toRemove.isNotEmpty) {
        _removeFromVisibleOrder(toRemove);
      }
    }
    notifyListeners();
  }

  /// Rebuilds the entire visible order from the tree structure.
  ///
  /// More efficient than incremental updates when making bulk changes.
  void _rebuildVisibleOrder() {
    _visibleOrder.clear();

    void addSubtree(TKey key) {
      _visibleOrder.add(key);
      if (_pendingDeletion.contains(key)) {
        // Don't recurse based on expansion state (prevents zombie children),
        // but DO include children that are also pending deletion and still
        // have running exit animations — they need to stay in _visibleOrder
        // to animate out smoothly.
        final children = _children[key];
        if (children != null) {
          for (final childId in children) {
            if (_pendingDeletion.contains(childId) &&
                _standaloneAnimations.containsKey(childId)) {
              addSubtree(childId);
            }
          }
        }
        return;
      }
      if (_expanded[key] == true) {
        final children = _children[key];
        if (children != null) {
          for (final childId in children) {
            addSubtree(childId);
          }
        }
      } else {
        // Parent is collapsed, but children that are still in an active
        // animation (e.g. collapsing via an OperationGroup) must remain
        // in the visible order so their exit animation completes smoothly
        // instead of snapping away.
        final children = _children[key];
        if (children != null) {
          for (final childId in children) {
            if (_nodeToOperationGroup.containsKey(childId) ||
                _bulkAnimationGroup?.members.contains(childId) == true ||
                _standaloneAnimations.containsKey(childId)) {
              addSubtree(childId);
            }
          }
        }
      }
    }

    for (final rootId in _roots) {
      addSubtree(rootId);
    }
    _rebuildVisibleIndex();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ANIMATION
  // ══════════════════════════════════════════════════════════════════════════

  /// Marker value indicating the target extent should be determined
  /// from the measured size during layout.
  static const double _unknownExtent = -1.0;

  /// Captures a node's current animated extent from whichever source it's in,
  /// removes it from that source, and returns the extent (or null if not animating).
  double? _captureAndRemoveFromGroups(TKey key) {
    // 1. Check operation group
    final opGroupKey = _nodeToOperationGroup[key];
    if (opGroupKey != null) {
      final group = _operationGroups[opGroupKey];
      if (group != null) {
        final member = group.members[key];
        if (member != null) {
          final full = _fullExtents[key] ?? defaultExtent;
          final extent = member.computeExtent(group.curvedValue, full);
          group.members.remove(key);
          group.pendingRemoval.remove(key);
          _nodeToOperationGroup.remove(key);
          return extent;
        }
      }
      _nodeToOperationGroup.remove(key);
    }

    // 2. Check bulk animation group
    if (_bulkAnimationGroup?.members.contains(key) == true) {
      final full = _fullExtents[key] ?? defaultExtent;
      final extent = full * _bulkAnimationGroup!.value;
      _bulkAnimationGroup!.members.remove(key);
      _bulkAnimationGroup!.pendingRemoval.remove(key);
      return extent;
    }

    // 3. Check standalone animations
    final standalone = _standaloneAnimations.remove(key);
    if (standalone != null) {
      return standalone.currentExtent;
    }

    return null;
  }

  /// Cancels pending-deletion and all animation state for [key] and all
  /// of its descendants. Intended for use when a subtree is reparented —
  /// its prior animation state was computed against the old position and
  /// must not continue to drive finalize/purge after the move.
  void _cancelAnimationStateForSubtree(TKey key) {
    // Also dispose any OperationGroup whose operationKey is inside the moved
    // subtree. Its controller would otherwise keep running and, on dismiss,
    // remove the (now relocated) members from _visibleOrder — destroying the
    // moved subtree under its new parent.
    final subtreeGroupKeys = <TKey>[];
    void visit(TKey nodeId) {
      _pendingDeletion.remove(nodeId);
      if (_operationGroups.containsKey(nodeId)) {
        subtreeGroupKeys.add(nodeId);
      }
      _removeAnimation(nodeId);
      final children = _children[nodeId];
      if (children != null) {
        for (final child in children) {
          visit(child);
        }
      }
    }

    visit(key);

    for (final groupKey in subtreeGroupKeys) {
      final group = _operationGroups.remove(groupKey);
      if (group == null) continue;
      for (final member in group.members.keys) {
        if (_nodeToOperationGroup[member] == groupKey) {
          _nodeToOperationGroup.remove(member);
        }
      }
      group.dispose();
    }

    if (_standaloneAnimations.isEmpty) {
      _standaloneTicker?.stop();
    }
  }

  /// Removes an animation from all sources and cleans up group membership.
  AnimationState? _removeAnimation(TKey key) {
    final state = _standaloneAnimations.remove(key);
    // Remove from operation group
    final opGroupKey = _nodeToOperationGroup.remove(key);
    if (opGroupKey != null) {
      final group = _operationGroups[opGroupKey];
      if (group != null) {
        group.members.remove(key);
        group.pendingRemoval.remove(key);
      }
    }
    // Also remove from bulk animation group
    _bulkAnimationGroup?.members.remove(key);
    _bulkAnimationGroup?.pendingRemoval.remove(key);
    return state;
  }

  /// Creates a new bulk animation group with an AnimationController.
  AnimationGroup<TKey> _createBulkAnimationGroup({double initialValue = 0.0}) {
    final controller = AnimationController(
      vsync: _vsync,
      duration: animationDuration,
      value: initialValue,
    );

    final group = AnimationGroup<TKey>(
      controller: controller,
      curve: animationCurve,
    );

    controller.addListener(_notifyAnimationListeners);

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _onBulkAnimationComplete();
      }
    });

    return group;
  }

  /// Disposes the current bulk animation group if it exists.
  void _disposeBulkAnimationGroup() {
    final group = _bulkAnimationGroup;
    _bulkAnimationGroup =
        null; // Set to null first to prevent callback interference
    group?.dispose();
  }

  /// Called when the bulk animation completes or is dismissed.
  void _onBulkAnimationComplete() {
    if (_bulkAnimationGroup == null) return;
    final controller = _bulkAnimationGroup!.controller;
    // If dismissed (value = 0), remove nodes marked for removal
    if (controller.status == AnimationStatus.dismissed) {
      _keysToRemoveScratch.clear();
      for (final key in _bulkAnimationGroup!.pendingRemoval) {
        if (!_pendingDeletion.contains(key)) {
          final parentKey = _parents[key];
          final shouldRemove = parentKey == null
              ? !_roots.contains(key)
              : !_areAncestorsExpanded(key);
          if (shouldRemove) {
            _keysToRemoveScratch.add(key);
          }
        }
      }
      if (_keysToRemoveScratch.isNotEmpty) {
        _removeFromVisibleOrder(_keysToRemoveScratch);
        _structureGeneration++;
      }
    }

    // Dispose the group. Leaving it live retains an idle AnimationController
    // and its ticker registration for the life of the TreeController, which
    // is wasteful. A subsequent expandAll/collapseAll will create a new one.
    _disposeBulkAnimationGroup();

    notifyListeners();
  }

  /// Called when an operation group's animation completes or is dismissed.
  void _onOperationGroupStatusChange(
    TKey operationKey,
    AnimationStatus status,
  ) {
    final group = _operationGroups[operationKey];
    if (group == null) return;

    if (status == AnimationStatus.completed) {
      // Expansion done (value = 1). Remove group, clean up maps.
      for (final nodeId in group.members.keys) {
        _nodeToOperationGroup.remove(nodeId);
      }
      _operationGroups.remove(operationKey);
      group.dispose();
      notifyListeners();
    } else if (status == AnimationStatus.dismissed) {
      // Collapse done (value = 0). Remove nodes from visible order.
      _keysToRemoveScratch.clear();
      for (final nodeId in group.pendingRemoval) {
        if (_pendingDeletion.contains(nodeId)) {
          // Fully remove the node from all data structures
          final parentKey = _parents[nodeId];
          if (parentKey != null) {
            _children[parentKey]?.remove(nodeId);
          } else {
            _roots.remove(nodeId);
          }
          _nodeToOperationGroup.remove(nodeId);
          _purgeNodeData(nodeId);
          _keysToRemoveScratch.add(nodeId);
        } else {
          final parentKey = _parents[nodeId];
          final shouldRemove = parentKey == null
              ? !_roots.contains(nodeId)
              : !_areAncestorsExpanded(nodeId);
          if (shouldRemove) {
            _keysToRemoveScratch.add(nodeId);
          }
          _nodeToOperationGroup.remove(nodeId);
        }
      }
      // Clean up remaining members not in pendingRemoval
      for (final nodeId in group.members.keys) {
        _nodeToOperationGroup.remove(nodeId);
      }
      if (_keysToRemoveScratch.isNotEmpty) {
        _removeFromVisibleOrder(_keysToRemoveScratch);
        _structureGeneration++;
      }
      _operationGroups.remove(operationKey);
      group.dispose();
      notifyListeners();
    }
  }

  /// Computes the speed multiplier for proportional timing.
  ///
  /// When a node transitions between animation sources, the remaining
  /// animation distance may be less than the full extent. The speed
  /// multiplier ensures the animation completes in proportional time.
  static double _computeSpeedMultiplier(
    double currentExtent,
    double fullExtent,
  ) {
    if (fullExtent <= 0) return 1.0;
    final fraction = currentExtent / fullExtent;
    if (fraction <= 0 || fraction >= 1.0) return 1.0;
    return (1.0 / fraction).clamp(1.0, 10.0);
  }

  void _startStandaloneEnterAnimation(TKey key, {TKey? triggeringAncestorId}) {
    // Capture current animated extent from any source BEFORE removing
    final capturedExtent = _captureAndRemoveFromGroups(key);
    final startExtent = capturedExtent ?? 0.0;
    final targetExtent = _fullExtents[key] ?? _unknownExtent;

    // Compute speed multiplier for proportional timing
    final full = _fullExtents[key] ?? defaultExtent;
    final speedMultiplier = startExtent > 0
        ? _computeSpeedMultiplier(full - startExtent, full)
        : 1.0;

    _standaloneAnimations[key] = AnimationState(
      type: AnimationType.entering,
      startExtent: startExtent,
      targetExtent: targetExtent,
      triggeringAncestorId: triggeringAncestorId,
      speedMultiplier: speedMultiplier,
    );
    _ensureStandaloneTickerRunning();
  }

  /// Cancels a pending deletion for a node and all its descendants.
  ///
  /// Reverses the exit animation of [key] into an enter animation so the
  /// re-inserted node animates back in. Descendants are cleared of pending
  /// deletion and their animations are simply removed: the caller always
  /// forces expansion to false on the restored node, so descendants will not
  /// be visible. Starting an enter animation for each descendant (only to
  /// have it torn down immediately) would also yank them out of any
  /// unrelated [OperationGroup] they still belong to via
  /// [_captureAndRemoveFromGroups], leaving that group short a member.
  void _cancelDeletion(TKey key, {bool animate = true}) {
    if (animationDuration == Duration.zero) animate = false;
    _pendingDeletion.remove(key);
    if (animate) {
      _startStandaloneEnterAnimation(key);
    } else {
      _removeAnimation(key);
    }
    final descendants = _getDescendants(key);
    for (final nodeId in descendants) {
      _pendingDeletion.remove(nodeId);
      _removeAnimation(nodeId);
    }
  }

  void _startStandaloneExitAnimation(TKey key, {TKey? triggeringAncestorId}) {
    // Capture current animated extent from any source BEFORE removing
    final capturedExtent = _captureAndRemoveFromGroups(key);
    final currentExtent = capturedExtent ?? (_fullExtents[key] ?? 0.0);

    // Compute speed multiplier for proportional timing
    final full = _fullExtents[key] ?? defaultExtent;
    final speedMultiplier = _computeSpeedMultiplier(currentExtent, full);

    _standaloneAnimations[key] = AnimationState(
      type: AnimationType.exiting,
      startExtent: currentExtent,
      targetExtent: 0.0,
      triggeringAncestorId: triggeringAncestorId,
      speedMultiplier: speedMultiplier,
    );
    _ensureStandaloneTickerRunning();
  }

  /// Ensures the standalone animation ticker is running.
  void _ensureStandaloneTickerRunning() {
    _standaloneTicker ??= _vsync.createTicker(_onStandaloneTick);
    if (!_standaloneTicker!.isActive) {
      _lastStandaloneTickTime = null;
      _standaloneTicker!.start();
    }
  }

  /// Ticker callback for standalone (individual) animations only.
  /// Bulk and operation group animations are driven by AnimationController.
  void _onStandaloneTick(Duration elapsed) {
    if (_standaloneAnimations.isEmpty) {
      _standaloneTicker?.stop();
      return;
    }
    if (animationDuration.inMicroseconds == 0) {
      _standaloneTicker?.stop();
      return;
    }

    final dt = _lastStandaloneTickTime == null
        ? Duration.zero
        : elapsed - _lastStandaloneTickTime!;
    _lastStandaloneTickTime = elapsed;
    final progressDelta = dt.inMicroseconds / animationDuration.inMicroseconds;

    // Process standalone animations
    final completed = <TKey>[];
    for (final entry in _standaloneAnimations.entries) {
      final state = entry.value;
      state.progress += progressDelta * state.speedMultiplier;
      state.updateExtent(animationCurve);
      if (state.isComplete) {
        completed.add(entry.key);
      }
    }

    // Finalize completed standalone animations
    _keysToRemoveScratch.clear();
    for (final key in completed) {
      if (_finalizeAnimation(key)) {
        _keysToRemoveScratch.add(key);
      }
    }

    if (_keysToRemoveScratch.isNotEmpty) {
      _removeFromVisibleOrder(_keysToRemoveScratch);
      _structureGeneration++;
      notifyListeners();
    }

    _notifyAnimationListeners();

    // Stop ticker if no more standalone animations
    if (_standaloneAnimations.isEmpty) {
      _standaloneTicker?.stop();
    }
  }

  bool _finalizeAnimation(TKey key) {
    final state = _standaloneAnimations.remove(key);
    if (state == null) return false;

    if (state.type == AnimationType.exiting) {
      final isDeleted = _pendingDeletion.contains(key);
      if (isDeleted) {
        // Fully remove the node from all data structures
        final parentKey = _parents[key];
        if (parentKey != null) {
          _children[parentKey]?.remove(key);
        } else {
          _roots.remove(key);
        }
        // Also purge descendants that were pending deletion but never got
        // their own exit animation (invisible children of a collapsed node).
        // Must collect before purging `key`, since _getDescendants reads
        // _children[key].
        final descendants = _getDescendants(key);
        // Skip _visibleOrder.remove — caller batches it
        _purgeNodeData(key);
        for (final desc in descendants) {
          // Only purge orphans that have no active exit animation.
          // Visible descendants with their own animation will finalize
          // themselves when their animation completes.
          if (_pendingDeletion.contains(desc) &&
              !_standaloneAnimations.containsKey(desc)) {
            _purgeNodeData(desc);
          }
        }
        return true;
      } else {
        // Node is exiting due to ancestor collapse - remove from visible order
        // if ancestors are still collapsed
        final parentKey = _parents[key];
        final shouldRemove = parentKey == null
            ? !_roots.contains(key)
            : !_areAncestorsExpanded(key);
        return shouldRemove;
        // If all ancestors are expanded, the node should stay visible (user re-expanded mid-collapse)
      }
    }

    // Safety net: if an entering node is pending deletion (shouldn't happen
    // with the guards in collectRecursive and addSubtree, but defend against
    // other code paths), purge it.
    if (_pendingDeletion.contains(key)) {
      final parentKey = _parents[key];
      if (parentKey != null) {
        _children[parentKey]?.remove(key);
      } else {
        _roots.remove(key);
      }
      _purgeNodeData(key);
      return true;
    }

    return false;
  }

  /// Inserts a node into _visibleOrder at the correct position relative to
  /// the given parent index.
  void _insertNodeIntoVisibleOrder(TKey nodeId, int parentIndex) {
    final parentKey = _visibleOrder[parentIndex];
    final insertIndex = parentIndex + 1 + _countVisibleDescendants(parentKey);
    _visibleOrder.insert(insertIndex, nodeId);
    _updateIndicesFrom(insertIndex);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  void _clear() {
    _standaloneTicker?.stop();
    _standaloneTicker?.dispose();
    _standaloneTicker = null;
    _disposeBulkAnimationGroup();
    for (final group in _operationGroups.values) {
      group.dispose();
    }
    _operationGroups.clear();
    _nodeToOperationGroup.clear();
    _nodeData.clear();
    _parents.clear();
    _children.clear();
    _depths.clear();
    _expanded.clear();
    _roots.clear();
    _visibleOrder.clear();
    _visibleIndex.clear();
    _standaloneAnimations.clear();
    _fullExtents.clear();
    _pendingDeletion.clear();
  }

  void _rebuildVisibleIndex() {
    _visibleIndex.clear();
    for (int i = 0; i < _visibleOrder.length; i++) {
      _visibleIndex[_visibleOrder[i]] = i;
    }
    _assertIndexConsistency();
  }

  /// Updates indices for all nodes from [startIndex] to the end of the list.
  ///
  /// Call after inserting (single or bulk) into [_visibleOrder].
  void _updateIndicesFrom(int startIndex) {
    for (int i = startIndex; i < _visibleOrder.length; i++) {
      _visibleIndex[_visibleOrder[i]] = i;
    }
    _assertIndexConsistency();
  }

  /// Updates indices after removing items that were at [removeIndex].
  /// The keys must already be removed from [_visibleIndex] before calling.
  void _updateIndicesAfterRemove(int removeIndex) {
    // Shift indices for nodes after the removal point
    for (int i = removeIndex; i < _visibleOrder.length; i++) {
      _visibleIndex[_visibleOrder[i]] = i;
    }
    _assertIndexConsistency();
  }

  /// Debug assertion to verify index consistency.
  void _assertIndexConsistency() {
    assert(() {
      for (int i = 0; i < _visibleOrder.length; i++) {
        final key = _visibleOrder[i];
        final idx = _visibleIndex[key];
        if (idx != i) {
          throw StateError(
            'Index mismatch: _visibleOrder[$i] = $key, '
            'but _visibleIndex[$key] = $idx',
          );
        }
      }
      if (_visibleIndex.length != _visibleOrder.length) {
        throw StateError(
          'Length mismatch: _visibleIndex has ${_visibleIndex.length} entries, '
          'but _visibleOrder has ${_visibleOrder.length} entries',
        );
      }
      return true;
    }());
  }

  /// Removes a set of keys from `_visibleOrder` and updates the index.
  ///
  /// Detects if the keys form a contiguous block via `_visibleIndex` and
  /// uses `removeRange` (O(1) shift) when possible, falling back to
  /// `removeWhere` otherwise. Uses incremental index updates for contiguous
  /// removals, full rebuild for non-contiguous.
  void _removeFromVisibleOrder(Set<TKey> keys) {
    if (keys.isEmpty) return;
    if (keys.length == 1) {
      final key = keys.first;
      final idx = _visibleIndex[key];
      if (idx != null &&
          idx < _visibleOrder.length &&
          _visibleOrder[idx] == key) {
        _visibleIndex.remove(key);
        _visibleOrder.removeAt(idx);
        _updateIndicesAfterRemove(idx);
        return;
      }
    }
    // Check if keys form a contiguous range via _visibleIndex.
    int minIdx = _visibleOrder.length;
    int maxIdx = -1;
    for (final key in keys) {
      final idx = _visibleIndex[key];
      if (idx == null) continue;
      if (idx < minIdx) minIdx = idx;
      if (idx > maxIdx) maxIdx = idx;
    }
    if (maxIdx >= 0 && maxIdx - minIdx + 1 == keys.length) {
      // Contiguous: remove from index first, then from list
      for (int i = minIdx; i <= maxIdx; i++) {
        _visibleIndex.remove(_visibleOrder[i]);
      }
      _visibleOrder.removeRange(minIdx, maxIdx + 1);
      _updateIndicesAfterRemove(minIdx);
    } else {
      // Non-contiguous: remove from index, then list, then full rebuild
      for (final key in keys) {
        _visibleIndex.remove(key);
      }
      _visibleOrder.removeWhere(keys.contains);
      _rebuildVisibleIndex();
    }
  }

  List<TKey> _getDescendants(TKey key) {
    final result = <TKey>[];
    _getDescendantsInto(key, result);
    return result;
  }

  void _getDescendantsInto(TKey key, List<TKey> result) {
    final children = _children[key];
    if (children == null) return;
    for (final childId in children) {
      result.add(childId);
      _getDescendantsInto(childId, result);
    }
  }

  List<TKey> _getVisibleDescendants(TKey key) {
    final result = <TKey>[];
    _getVisibleDescendantsInto(key, result);
    return result;
  }

  void _getVisibleDescendantsInto(TKey key, List<TKey> result) {
    final children = _children[key];
    if (children == null) return;
    for (final childId in children) {
      if (_visibleIndex.containsKey(childId)) {
        result.add(childId);
        if (_expanded[childId] == true) {
          _getVisibleDescendantsInto(childId, result);
        }
      }
    }
  }

  /// Checks if all ancestors of a node are expanded.
  /// Returns true for root nodes (no ancestors).
  bool _areAncestorsExpanded(TKey key) {
    TKey? parentKey = _parents[key];
    while (parentKey != null) {
      if (_expanded[parentKey] != true) {
        return false;
      }
      parentKey = _parents[parentKey];
    }
    return true;
  }

  int _countVisibleDescendants(TKey key) {
    int count = 0;
    final children = _children[key];
    if (children == null || _expanded[key] != true) {
      return 0;
    }
    for (final childId in children) {
      if (_visibleIndex.containsKey(childId)) {
        count++;
        count += _countVisibleDescendants(childId);
      }
    }
    return count;
  }

  /// Flattens a subtree into a list of node IDs in depth-first order.
  List<TKey> _flattenSubtree(TKey key, {bool includeRoot = true}) {
    final result = <TKey>[];
    _flattenSubtreeInto(key, result, includeRoot: includeRoot);
    return result;
  }

  void _flattenSubtreeInto(
    TKey key,
    List<TKey> result, {
    bool includeRoot = true,
  }) {
    if (includeRoot) result.add(key);
    if (_expanded[key] == true) {
      final children = _children[key];
      if (children != null) {
        for (final childId in children) {
          _flattenSubtreeInto(childId, result);
        }
      }
    }
  }

  /// Removes a single key from all internal maps (but not from _visibleOrder,
  /// _roots, or the parent's _children list — those are handled by the caller).
  void _purgeNodeData(TKey key) {
    _nodeData.remove(key);
    _parents.remove(key);
    _children.remove(key);
    _depths.remove(key);
    _expanded.remove(key);
    _fullExtents.remove(key);
    // Clean up standalone animation state
    _standaloneAnimations.remove(key);
    // Clean up operation group membership
    final opGroupKey = _nodeToOperationGroup.remove(key);
    if (opGroupKey != null) {
      final group = _operationGroups[opGroupKey];
      if (group != null) {
        group.members.remove(key);
        group.pendingRemoval.remove(key);
      }
    }
    // If [key] IS an operation key (the node that triggered an expand/collapse),
    // tear down the whole group. Without this, the entry lives on in
    // [_operationGroups] orphaned — a later insert+expand with the same key
    // would reuse the stale group via the Path 1 branch in [expand]/[collapse].
    final orphanGroup = _operationGroups.remove(key);
    if (orphanGroup != null) {
      for (final memberKey in orphanGroup.members.keys) {
        if (_nodeToOperationGroup[memberKey] == key) {
          _nodeToOperationGroup.remove(memberKey);
        }
      }
      orphanGroup.dispose();
    }
    // Clean up bulk animation group membership
    _bulkAnimationGroup?.members.remove(key);
    _bulkAnimationGroup?.pendingRemoval.remove(key);
    _pendingDeletion.remove(key);
    _visibleIndex.remove(key);
  }

  void _removeNodesImmediate(List<TKey> nodeIds) {
    final keysToRemove = nodeIds.toSet();

    // Check visibility and contiguity BEFORE purging (purge removes from _visibleIndex)
    int minIdx = _visibleOrder.length;
    int maxIdx = -1;
    int visibleCount = 0;
    for (final key in nodeIds) {
      final idx = _visibleIndex[key];
      if (idx != null) {
        visibleCount++;
        if (idx < minIdx) minIdx = idx;
        if (idx > maxIdx) maxIdx = idx;
      }
    }

    // Purge node data (removes from _visibleIndex)
    for (final key in nodeIds) {
      final parentKey = _parents[key];
      if (parentKey != null) {
        _children[parentKey]?.remove(key);
      } else {
        _roots.remove(key);
      }
      _purgeNodeData(key);
    }

    // Update visible order
    if (visibleCount > 0) {
      if (maxIdx - minIdx + 1 == visibleCount) {
        // Contiguous removal
        _visibleOrder.removeRange(minIdx, maxIdx + 1);
        _updateIndicesAfterRemove(minIdx);
      } else {
        // Non-contiguous removal
        _visibleOrder.removeWhere(keysToRemove.contains);
        _rebuildVisibleIndex();
      }
    }
  }

  @override
  void dispose() {
    _clear();
    _animationListeners.clear();
    super.dispose();
  }
}
