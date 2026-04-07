/// A widget that displays a SplayTreeMap as a tree with automatic diffing.
library;

import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'sliver_tree_widget.dart';
import 'tree_controller.dart';
import 'types.dart';

/// An entry in the tree map containing both key and value.
///
/// This is used internally to store both pieces of information in the
/// TreeController's data payload.
class TreeMapEntry<K, V> {
  const TreeMapEntry(this.key, this.value);

  final K key;
  final V value;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TreeMapEntry<K, V> && key == other.key && value == other.value;
  }

  @override
  int get hashCode => Object.hash(key, value);
}

/// A sliver widget that displays a [SplayTreeMap] as an animated tree.
///
/// This widget automatically detects additions and removals when the [data]
/// changes, animating the transitions using the underlying [TreeController].
///
/// The tree structure is determined by the [parentOf] callback, which returns
/// the parent key for each entry. Entries with a null parent (or a parent not
/// in the map) are treated as root nodes.
///
/// The [nodeBuilder] receives the [TreeController] to enable expand/collapse
/// functionality.
///
/// Example:
/// ```dart
/// TreeMapView<String, FileItem>(
///   data: myFileMap,
///   parentOf: (key, value) => value.parentPath,
///   nodeBuilder: (context, key, value, depth, controller) {
///     return ListTile(
///       leading: controller.hasChildren(key)
///           ? IconButton(
///               icon: Icon(controller.isExpanded(key)
///                   ? Icons.expand_less
///                   : Icons.expand_more),
///               onPressed: () => controller.toggle(key),
///             )
///           : null,
///       title: Text(value.name),
///     );
///   },
/// )
/// ```
class TreeMapView<K, V> extends StatefulWidget {
  /// Creates a tree map view.
  const TreeMapView({
    required this.data,
    required this.parentOf,
    required this.nodeBuilder,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.indentWidth = 24.0,
    this.initiallyExpanded = false,
    super.key,
  });

  /// The data source for the tree.
  ///
  /// When this changes, the widget diffs the old and new maps to determine
  /// which nodes were added or removed, and animates the changes.
  final SplayTreeMap<K, V> data;

  /// Returns the parent key for a given entry.
  ///
  /// Return null for root nodes (nodes with no parent).
  /// If the returned key is not present in [data], the node is also
  /// treated as a root.
  final K? Function(K key, V value) parentOf;

  /// Builds the widget for each node.
  ///
  /// The [depth] parameter indicates the nesting level (0 for roots).
  /// The [controller] provides access to expansion state and methods.
  final Widget Function(
    BuildContext context,
    K key,
    V value,
    int depth,
    TreeController<K, TreeMapEntry<K, V>> controller,
  )
  nodeBuilder;

  /// Duration for expand/collapse and add/remove animations.
  final Duration animationDuration;

  /// Curve for animations.
  final Curve animationCurve;

  /// Horizontal indent per depth level in logical pixels.
  final double indentWidth;

  /// Whether nodes should be initially expanded.
  final bool initiallyExpanded;

  @override
  State<TreeMapView<K, V>> createState() => _TreeMapViewState<K, V>();
}

class _TreeMapViewState<K, V> extends State<TreeMapView<K, V>>
    with TickerProviderStateMixin {
  late TreeController<K, TreeMapEntry<K, V>> _controller;

  @override
  void initState() {
    super.initState();
    _controller = TreeController<K, TreeMapEntry<K, V>>(
      vsync: this,
      animationDuration: widget.animationDuration,
      animationCurve: widget.animationCurve,
      indentWidth: widget.indentWidth,
    );
    _initializeFromData(animate: false);
  }

  @override
  void didUpdateWidget(TreeMapView<K, V> oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Controller properties are final — changing them requires recreation via Key.
    assert(
      oldWidget.animationDuration == widget.animationDuration &&
          oldWidget.animationCurve == widget.animationCurve &&
          oldWidget.indentWidth == widget.indentWidth,
      'TreeMapView animationDuration, animationCurve, and indentWidth cannot '
      'be changed after creation. Use a Key to force recreation.',
    );

    // Diff data changes
    if (!identical(oldWidget.data, widget.data)) {
      _diffAndUpdate(oldWidget.data, widget.data);
    }
  }

  /// Builds the initial tree structure from the data.
  void _initializeFromData({required bool animate}) {
    final data = widget.data;
    if (data.isEmpty) return;

    // Group nodes by parent
    final Map<K?, List<K>> childrenByParent = {};
    for (final key in data.keys) {
      final value = data[key] as V;
      final parentKey = widget.parentOf(key, value);
      // Treat as root if parent is null or not in data
      final K? effectiveParent =
          parentKey != null && data.containsKey(parentKey) ? parentKey : null;
      childrenByParent.putIfAbsent(effectiveParent, () => []).add(key);
    }

    // Get roots (nodes with null effective parent)
    final roots = childrenByParent[null] ?? [];
    if (roots.isEmpty) return;

    // Set roots
    _controller.setRoots(
      roots.map((key) {
        final value = data[key] as V;
        return TreeNode(key: key, data: TreeMapEntry(key, value));
      }).toList(),
    );

    // Recursively add children
    void addChildren(K parentKey) {
      final children = childrenByParent[parentKey];
      if (children == null || children.isEmpty) return;

      _controller.setChildren(
        parentKey,
        children.map((key) {
          final value = data[key] as V;
          return TreeNode(key: key, data: TreeMapEntry(key, value));
        }).toList(),
      );

      for (final childKey in children) {
        addChildren(childKey);
      }
    }

    for (final root in roots) {
      addChildren(root);
    }

    // Optionally expand all nodes
    if (widget.initiallyExpanded) {
      _controller.expandAll(animate: animate);
    }
  }

  /// Diffs old and new data, applying changes with animations.
  void _diffAndUpdate(SplayTreeMap<K, V> oldData, SplayTreeMap<K, V> newData) {
    final oldKeys = oldData.keys.toSet();
    final newKeys = newData.keys.toSet();

    final added = newKeys.difference(oldKeys);
    final removed = oldKeys.difference(newKeys);
    final retained = oldKeys.intersection(newKeys);

    // Rescue retained nodes from subtrees about to be cascade-deleted,
    // then process removals, additions, and retained-key reconciliation.
    final rescuedToRoot = _rescueRetainedFromRemovals(retained, removed);
    _processRemovals(removed, oldData);
    _processAdditions(added, newData);
    _processRetainedUpdates(retained, oldData, newData, rescuedToRoot);
  }

  /// Moves retained nodes out of subtrees that are about to be
  /// cascade-deleted by [_processRemovals].
  ///
  /// Processes shallowest-first so that a retained parent is rescued before
  /// its retained children, keeping the subtree intact. Returns the set of
  /// keys that were actually moved to root (used to trigger root reordering).
  Set<K> _rescueRetainedFromRemovals(Set<K> retained, Set<K> removed) {
    final toRescue = <K>[];
    for (final key in retained) {
      if (_controller.getNodeData(key) == null) continue;
      K? ancestor = _controller.getParent(key);
      while (ancestor != null) {
        if (removed.contains(ancestor)) {
          toRescue.add(key);
          break;
        }
        ancestor = _controller.getParent(ancestor);
      }
    }
    if (toRescue.isEmpty) return const {};

    // Shallowest first — rescuing a parent also rescues its children.
    toRescue.sort(
      (a, b) => _controller.getDepth(a).compareTo(_controller.getDepth(b)),
    );

    final rescued = <K>{};
    for (final key in toRescue) {
      if (_controller.getNodeData(key) == null) continue;
      // Re-check: a shallower rescue may have already pulled this node out.
      bool needsRescue = false;
      K? ancestor = _controller.getParent(key);
      while (ancestor != null) {
        if (removed.contains(ancestor)) {
          needsRescue = true;
          break;
        }
        ancestor = _controller.getParent(ancestor);
      }
      if (needsRescue) {
        _controller.moveNode(key, null);
        rescued.add(key);
      }
    }
    return rescued;
  }

  /// Updates retained nodes whose value or parent changed.
  void _processRetainedUpdates(
    Set<K> retained,
    SplayTreeMap<K, V> oldData,
    SplayTreeMap<K, V> newData,
    Set<K> rescuedToRoot,
  ) {
    // Track parents whose child order was affected by moves so we can
    // reorder them to match the SplayTreeMap source order afterwards.
    // null represents the root list.
    final affectedParents = <K?>{};

    // Rescued nodes were moved to root before removals. If any of them
    // remain roots in the desired state, the root list needs reordering.
    if (rescuedToRoot.isNotEmpty) {
      affectedParents.add(null);
    }

    for (final key in retained) {
      // Guard: node may have been cascade-removed by parent removal.
      if (_controller.getNodeData(key) == null) continue;

      final oldValue = oldData[key] as V;
      final newValue = newData[key] as V;

      // Data change — update payload.
      if (oldValue != newValue) {
        _controller.updateNode(
          TreeNode(key: key, data: TreeMapEntry(key, newValue)),
        );
      }

      // Parent change — compare the controller's actual current parent
      // with the desired new parent. Using the controller state avoids
      // relying on the old widget's parentOf callback (which may have
      // changed after didUpdateWidget).
      final K? currentParent = _controller.getParent(key);
      final newParent = widget.parentOf(key, newValue);
      final K? effectiveNewParent =
          newParent != null && newData.containsKey(newParent)
          ? newParent
          : null;

      if (currentParent != effectiveNewParent) {
        // New parent must exist in the controller for moveNode.
        if (effectiveNewParent == null ||
            _controller.getNodeData(effectiveNewParent) != null) {
          _controller.moveNode(key, effectiveNewParent);
          affectedParents.add(effectiveNewParent);

          // Expand the new parent so the moved child is visible, matching
          // the behavior of _processAdditions.
          if (effectiveNewParent != null &&
              !_controller.isExpanded(effectiveNewParent)) {
            _controller.expand(key: effectiveNewParent, animate: true);
          }
        }
      }
    }

    // Restore source order for containers affected by moves.
    _reorderAffectedParents(affectedParents, newData);
  }

  /// Reorders children of [affectedParents] to match [newData]'s key order.
  void _reorderAffectedParents(
    Set<K?> affectedParents,
    SplayTreeMap<K, V> newData,
  ) {
    if (affectedParents.isEmpty) return;

    // Group newData keys by effective parent.
    final Map<K?, List<K>> childrenByParent = {};
    for (final key in newData.keys) {
      final value = newData[key] as V;
      final parentKey = widget.parentOf(key, value);
      final K? effectiveParent =
          parentKey != null && newData.containsKey(parentKey)
          ? parentKey
          : null;
      childrenByParent.putIfAbsent(effectiveParent, () => []).add(key);
    }

    for (final parent in affectedParents) {
      final desiredOrder = childrenByParent[parent];
      if (desiredOrder == null || desiredOrder.isEmpty) continue;

      // Filter to only keys that actually exist in the controller under
      // this parent, preserving the source order.
      if (parent == null) {
        final liveRoots = <K>[
          for (final k in desiredOrder)
            if (_controller.getNodeData(k) != null &&
                _controller.getParent(k) == null)
              k,
        ];
        if (liveRoots.length > 1) {
          _controller.reorderRoots(liveRoots);
        }
      } else {
        final liveChildren = <K>[
          for (final k in desiredOrder)
            if (_controller.getNodeData(k) != null &&
                _controller.getParent(k) == parent)
              k,
        ];
        if (liveChildren.length > 1) {
          _controller.reorderChildren(parent, liveChildren);
        }
      }
    }
  }

  /// Removes nodes, handling parent-child relationships.
  void _processRemovals(Set<K> removed, SplayTreeMap<K, V> oldData) {
    if (removed.isEmpty) return;

    // Find top-level removed nodes (whose parents are not being removed)
    // Removing a parent automatically removes its children
    final topLevelRemovals = <K>{};

    for (final key in removed) {
      final value = oldData[key] as V;
      final parentKey = widget.parentOf(key, value);

      // If parent is null, not in old data, or not being removed, this is top-level
      if (parentKey == null ||
          !oldData.containsKey(parentKey) ||
          !removed.contains(parentKey)) {
        topLevelRemovals.add(key);
      }
    }

    // Remove top-level nodes (cascades to children)
    for (final key in topLevelRemovals) {
      _controller.remove(key: key, animate: true);
    }
  }

  /// Adds nodes, ensuring parents are added before children.
  void _processAdditions(Set<K> added, SplayTreeMap<K, V> newData) {
    if (added.isEmpty) return;

    // Topological sort via Kahn's algorithm — O(N+E) instead of O(N×D).
    // Build in-degree counts and dependents adjacency for nodes within `added`.
    final Map<K, int> inDegree = {};
    final Map<K, List<K>> dependents = {};

    for (final key in added) {
      final value = newData[key] as V;
      final parentKey = widget.parentOf(key, value);

      // A node has an unresolved dependency only if its parent is also
      // in `added` (parents already in the tree don't block insertion).
      if (parentKey != null &&
          newData.containsKey(parentKey) &&
          added.contains(parentKey)) {
        inDegree[key] = (inDegree[key] ?? 0) + 1;
        (dependents[parentKey] ??= []).add(key);
      } else {
        inDegree.putIfAbsent(key, () => 0);
      }
    }

    // Seed queue with zero-dependency nodes (FIFO to preserve source order).
    final queue = Queue<K>.from([
      for (final entry in inDegree.entries)
        if (entry.value == 0) entry.key,
    ]);

    final ordered = <K>[];
    while (queue.isNotEmpty) {
      final key = queue.removeFirst();
      ordered.add(key);
      final children = dependents[key];
      if (children != null) {
        for (final child in children) {
          final remaining = inDegree[child]! - 1;
          inDegree[child] = remaining;
          if (remaining == 0) queue.add(child);
        }
      }
    }

    // Circular dependency — add remaining as roots.
    if (ordered.length < added.length) {
      final orderedSet = Set<K>.from(ordered);
      for (final key in added) {
        if (!orderedSet.contains(key)) ordered.add(key);
      }
    }

    // Add nodes in order
    for (final key in ordered) {
      final value = newData[key] as V;
      final parentKey = widget.parentOf(key, value);
      final entry = TreeMapEntry(key, value);

      if (parentKey == null || !newData.containsKey(parentKey)) {
        // It's a root
        _controller.insertRoot(TreeNode(key: key, data: entry), animate: true);
      } else {
        // It's a child - insert and expand parent to show it
        _controller.insert(
          parentKey: parentKey,
          node: TreeNode(key: key, data: entry),
          animate: true,
        );

        // Expand parent if not already expanded
        if (!_controller.isExpanded(parentKey)) {
          _controller.expand(key: parentKey, animate: true);
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SliverTree<K, TreeMapEntry<K, V>>(
      controller: _controller,
      nodeBuilder: (context, key, depth) {
        final nodeData = _controller.getNodeData(key);
        if (nodeData == null) return const SizedBox.shrink();
        final entry = nodeData.data;
        return widget.nodeBuilder(
          context,
          entry.key,
          entry.value,
          depth,
          _controller,
        );
      },
    );
  }
}
