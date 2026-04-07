/// A widget that displays a Map as a tree with automatic diffing.
///
/// [TreeMapView] derives tree structure from a flat [Map] using a [parentOf]
/// callback, then uses [TreeSyncController] for efficient animated diffing.
library;

import 'package:flutter/widgets.dart';

import 'sliver_tree_widget.dart';
import 'tree_controller.dart';
import 'tree_sync_controller.dart';
import 'types.dart';

/// A sliver widget that displays a [Map] as an animated tree.
///
/// This widget derives tree structure from the [parentOf] callback, which
/// returns the parent key for each entry. Entries with a null parent (or a
/// parent not in the map) are treated as root nodes.
///
/// When [data] or [parentOf] changes, the widget diffs the old and new state
/// and animates the transitions.
///
/// The iteration order of [data] determines the display order of siblings.
/// Use a [SplayTreeMap] for sorted order, or a regular [Map] for insertion
/// order.
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
    this.preserveExpansion = true,
    this.maxStickyDepth = 0,
    super.key,
  });

  /// The data source for the tree.
  ///
  /// When this changes, the widget diffs the old and new state to determine
  /// which nodes were added or removed, and animates the changes.
  ///
  /// The iteration order of this map determines sibling display order.
  final Map<K, V> data;

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
    TreeController<K, V> controller,
  ) nodeBuilder;

  /// Duration for expand/collapse and add/remove animations.
  final Duration animationDuration;

  /// Curve for animations.
  final Curve animationCurve;

  /// Horizontal indent per depth level in logical pixels.
  final double indentWidth;

  /// Whether nodes should be initially expanded.
  final bool initiallyExpanded;

  /// Whether to preserve expansion state when nodes are removed and re-added.
  final bool preserveExpansion;

  /// How many depth levels of headers should stick to the top.
  ///
  /// 0 means no sticky headers. 1 means root nodes stick, etc.
  final int maxStickyDepth;

  @override
  State<TreeMapView<K, V>> createState() => _TreeMapViewState<K, V>();
}

class _TreeMapViewState<K, V> extends State<TreeMapView<K, V>>
    with TickerProviderStateMixin {
  late TreeController<K, V> _controller;
  late TreeSyncController<K, V> _syncController;

  /// Cached grouping from the last sync, used to detect changes.
  Map<K?, List<K>> _lastGrouping = {};

  @override
  void initState() {
    super.initState();
    _controller = TreeController<K, V>(
      vsync: this,
      animationDuration: widget.animationDuration,
      animationCurve: widget.animationCurve,
      indentWidth: widget.indentWidth,
    );
    _syncController = TreeSyncController<K, V>(
      treeController: _controller,
      preserveExpansion: widget.preserveExpansion,
    );
    _lastGrouping = _groupByParent(widget.data, widget.parentOf);
    _syncFromGrouping(_lastGrouping, animate: false);
    if (widget.initiallyExpanded) {
      _controller.expandAll(animate: false);
    }
  }

  @override
  void didUpdateWidget(TreeMapView<K, V> oldWidget) {
    super.didUpdateWidget(oldWidget);

    assert(
      oldWidget.animationDuration == widget.animationDuration &&
          oldWidget.animationCurve == widget.animationCurve &&
          oldWidget.indentWidth == widget.indentWidth,
      "TreeMapView animationDuration, animationCurve, and indentWidth cannot "
      "be changed after creation. Use a Key to force recreation.",
    );

    if (widget.preserveExpansion != oldWidget.preserveExpansion) {
      _syncController.dispose();
      _syncController = TreeSyncController<K, V>(
        treeController: _controller,
        preserveExpansion: widget.preserveExpansion,
      );
    }

    if (!identical(oldWidget.data, widget.data) ||
        !identical(oldWidget.parentOf, widget.parentOf)) {
      final oldGrouping = _lastGrouping;
      final newGrouping = _groupByParent(widget.data, widget.parentOf);

      // Rescue retained nodes from subtrees about to be cascade-deleted.
      _rescueRetained(oldGrouping, newGrouping);

      _syncFromGrouping(newGrouping, animate: true);

      // Expand parents that gained new children so reparented nodes
      // are visible.
      _expandNewParents(oldGrouping, newGrouping);

      _lastGrouping = newGrouping;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GROUPING & SYNC
  // ══════════════════════════════════════════════════════════════════════════

  /// Groups map entries by effective parent key.
  Map<K?, List<K>> _groupByParent(
    Map<K, V> data,
    K? Function(K key, V value) parentOf,
  ) {
    final result = <K?, List<K>>{};
    for (final entry in data.entries) {
      final parent = parentOf(entry.key, entry.value);
      final K? effectiveParent =
          parent != null && data.containsKey(parent) ? parent : null;
      final list = result.putIfAbsent(effectiveParent, () => []);
      list.add(entry.key);
    }
    return result;
  }

  /// Converts grouping to roots + childrenOf and syncs via the controller.
  void _syncFromGrouping(
    Map<K?, List<K>> grouping, {
    required bool animate,
  }) {
    final data = widget.data;
    final roots = (grouping[null] ?? [])
        .map((key) => TreeNode(key: key, data: data[key] as V))
        .toList();

    _syncController.syncRoots(
      roots,
      childrenOf: (key) {
        final children = grouping[key];
        if (children == null) {
          return [];
        }
        return children
            .map((k) => TreeNode(key: k, data: data[k] as V))
            .toList();
      },
      animate: animate,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESCUE & EXPAND
  // ══════════════════════════════════════════════════════════════════════════

  /// Moves retained descendants of to-be-removed roots to root level
  /// before sync, preventing cascade deletion.
  void _rescueRetained(
    Map<K?, List<K>> oldGrouping,
    Map<K?, List<K>> newGrouping,
  ) {
    final retainedKeys = widget.data.keys.toSet();
    final oldRoots = (oldGrouping[null] ?? []).toSet();
    final newRoots = (newGrouping[null] ?? []).toSet();
    final removedRoots = oldRoots.difference(newRoots);

    for (final rootKey in removedRoots) {
      if (!retainedKeys.contains(rootKey)) {
        _rescueDescendants(rootKey, oldGrouping, retainedKeys);
      }
    }
  }

  /// Recursively moves retained descendants of [key] to root level.
  void _rescueDescendants(
    K key,
    Map<K?, List<K>> grouping,
    Set<K> retainedKeys,
  ) {
    final children = grouping[key];
    if (children == null) {
      return;
    }
    for (final childKey in children) {
      if (retainedKeys.contains(childKey) &&
          _controller.getNodeData(childKey) != null) {
        _controller.moveNode(childKey, null);
      }
      _rescueDescendants(childKey, grouping, retainedKeys);
    }
  }

  /// Expands parents that gained new children after sync, so that
  /// reparented nodes are visible.
  void _expandNewParents(
    Map<K?, List<K>> oldGrouping,
    Map<K?, List<K>> newGrouping,
  ) {
    for (final entry in newGrouping.entries) {
      if (entry.key == null) {
        continue;
      }
      final parentKey = entry.key as K;
      final oldChildren = (oldGrouping[parentKey] ?? []).toSet();
      final newChildren = entry.value.toSet();
      if (newChildren.difference(oldChildren).isNotEmpty &&
          _controller.getNodeData(parentKey) != null &&
          !_controller.isExpanded(parentKey)) {
        _controller.expand(key: parentKey, animate: true);
      }
    }
  }

  @override
  void dispose() {
    _syncController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SliverTree<K, V>(
      controller: _controller,
      maxStickyDepth: widget.maxStickyDepth,
      nodeBuilder: (context, key, depth) {
        final nodeData = _controller.getNodeData(key);
        if (nodeData == null) {
          return const SizedBox.shrink();
        }
        return widget.nodeBuilder(
          context,
          key,
          nodeData.data,
          depth,
          _controller,
        );
      },
    );
  }
}
