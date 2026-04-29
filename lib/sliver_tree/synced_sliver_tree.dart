/// A declarative sliver tree with data-first input modes.
///
/// [SyncedSliverTree] owns both a [TreeController] and a [TreeSyncController]
/// internally. Callers provide domain data through one of five input shapes:
///
/// - [SyncedSliverTree.new] for an immutable nested [SyncedTreeNode] tree
/// - [SyncedSliverTree.nodes] for existing [TreeNode] roots plus [childrenOf]
/// - [SyncedSliverTree.hierarchy] for nested objects
/// - [SyncedSliverTree.flat] for flat items with parent keys
/// - [SyncedSliverTree.snapshot] for precomputed tree structure
///
/// The widget diffs the normalized tree on rebuild and applies animated
/// insertions, removals, and reparenting.
library;

import 'package:flutter/widgets.dart';

import '_sync_helpers.dart';
import 'sliver_tree_widget.dart';
import 'synced_tree_node.dart';
import 'tree_controller.dart';
import 'tree_node_builder.dart';
import 'tree_sync_controller.dart';
import 'types.dart';

/// Builds a widget for a visible synced tree node.
typedef TreeItemBuilder<TKey, TItem> =
    Widget Function(BuildContext context, TreeItemView<TKey, TItem> node);

enum _SyncedSliverTreeMode { tree, nodes, hierarchy, flat, snapshot }

/// Rich view of a visible synced tree node passed to [itemBuilder].
class TreeItemView<TKey, TItem> {
  const TreeItemView({
    required this.key,
    required this.item,
    required this.depth,
    required this.parentKey,
    required this.controller,
  });

  /// Unique identifier for this node.
  final TKey key;

  /// User payload for this node.
  final TItem item;

  /// Nesting depth (0 for roots).
  final int depth;

  /// Parent node key, or null when this node is a root.
  final TKey? parentKey;

  /// The backing tree controller.
  ///
  /// Most callers should rely on the richer convenience properties on this
  /// view, but the controller remains available as an escape hatch.
  final TreeController<TKey, TItem> controller;

  /// Whether this node is a root.
  bool get isRoot {
    return parentKey == null;
  }

  /// Horizontal indent for this node in logical pixels.
  double get indent {
    return controller.getIndent(key);
  }

  /// Whether this node currently has children.
  bool get hasChildren {
    return controller.hasChildren(key);
  }

  /// Number of direct children currently attached to this node.
  int get childCount {
    return controller.getChildCount(key);
  }

  /// Whether this node is currently expanded.
  bool get isExpanded {
    return controller.isExpanded(key);
  }

  /// Expands this node.
  void expand({bool animate = true}) {
    controller.expand(key: key, animate: animate);
  }

  /// Collapses this node.
  void collapse({bool animate = true}) {
    controller.collapse(key: key, animate: animate);
  }

  /// Toggles this node between expanded and collapsed.
  void toggle({bool animate = true}) {
    controller.toggle(key: key, animate: animate);
  }
}

extension TreeItemViewWatch<TKey, TItem> on TreeItemView<TKey, TItem> {
  /// Rebuilds [builder] when this node's expand/collapse state changes.
  Widget watch({
    required Widget Function(
      BuildContext context,
      TreeItemView<TKey, TItem> node,
    )
    builder,
    Key? key,
  }) {
    return TreeNodeBuilder<TKey, TItem>(
      key: key,
      controller: controller,
      nodeId: this.key,
      builder: (context, hasChildren, isExpanded) {
        final current = controller.getNodeData(this.key);
        if (current == null) {
          return const SizedBox.shrink();
        }
        return builder(
          context,
          TreeItemView<TKey, TItem>(
            key: this.key,
            item: current.data,
            depth: controller.getDepth(this.key),
            parentKey: controller.getParent(this.key),
            controller: controller,
          ),
        );
      },
    );
  }
}

/// Immutable normalized tree structure consumed by [SyncedSliverTree].
///
/// [roots] defines root order, [dataByKey] stores payloads, and
/// [childrenByParent] stores sibling order for each parent.
class TreeSnapshot<TKey, TItem> {
  TreeSnapshot({
    required Iterable<TKey> roots,
    required Map<TKey, TItem> dataByKey,
    Map<TKey, Iterable<TKey>>? childrenByParent,
  }) : roots = List<TKey>.unmodifiable(List<TKey>.of(roots)),
       dataByKey = Map<TKey, TItem>.unmodifiable(
         Map<TKey, TItem>.of(dataByKey),
       ),
       childrenByParent = Map<TKey, List<TKey>>.unmodifiable(<TKey, List<TKey>>{
         for (final entry
             in (childrenByParent ?? <TKey, Iterable<TKey>>{}).entries)
           entry.key: List<TKey>.unmodifiable(List<TKey>.of(entry.value)),
       }) {
    _validate();
  }

  /// Builds a validated snapshot from nested domain objects.
  factory TreeSnapshot.fromHierarchy({
    required Iterable<TItem> roots,
    required TKey Function(TItem item) keyOf,
    required Iterable<TItem> Function(TItem item) childrenOf,
  }) {
    final rootKeys = <TKey>[];
    final dataByKey = <TKey, TItem>{};
    final childrenByParent = <TKey, List<TKey>>{};
    final visiting = <TKey>{};

    // Iterative DFS so deep hierarchies do not stack-overflow Dart's
    // recursion limit. Two parallel stacks: `items` holds the work
    // queue; `exitMarkers` mirrors it as `null` for entry frames or as
    // the key whose `visiting` slot must be cleared on exit (post-order).
    final items = <TItem>[];
    final isRootStack = <bool>[];
    final exitMarkers = <TKey?>[];

    for (final root in roots) {
      items.add(root);
      isRootStack.add(true);
      exitMarkers.add(null);
    }

    while (items.isNotEmpty) {
      final item = items.removeLast();
      final isRoot = isRootStack.removeLast();
      final exitKey = exitMarkers.removeLast();

      if (exitKey != null) {
        // Post-order pop: leaving this key's subtree.
        visiting.remove(exitKey);
        continue;
      }

      final key = keyOf(item);
      if (!visiting.add(key)) {
        throw ArgumentError(
          "TreeSnapshot.fromHierarchy detected a cycle involving key \"$key\".",
        );
      }
      if (dataByKey.containsKey(key)) {
        throw ArgumentError(
          "TreeSnapshot.fromHierarchy encountered duplicate key \"$key\".",
        );
      }

      dataByKey[key] = item;
      if (isRoot) {
        rootKeys.add(key);
      }

      final childKeys = <TKey>[];
      final seenChildren = <TKey>{};
      // Resolve children once so we can both populate childrenByParent and
      // push them in the correct visit order (last-pushed = first-popped).
      final childItems = <TItem>[];
      for (final child in childrenOf(item)) {
        final childKey = keyOf(child);
        if (!seenChildren.add(childKey)) {
          throw ArgumentError(
            "TreeSnapshot.fromHierarchy encountered duplicate child key "
            "\"$childKey\" under parent \"$key\".",
          );
        }
        childKeys.add(childKey);
        childItems.add(child);
      }
      if (childKeys.isNotEmpty) {
        childrenByParent[key] = childKeys;
      }

      // Push exit marker FIRST so it pops AFTER all children — preserves
      // the recursive version's `visiting.remove(key)` placement at the
      // tail of the function body.
      items.add(item); // placeholder, ignored on exit pop
      isRootStack.add(false);
      exitMarkers.add(key);

      // Then push children in reverse so the first child pops first,
      // matching the recursive version's left-to-right visit order.
      for (int i = childItems.length - 1; i >= 0; i--) {
        items.add(childItems[i]);
        isRootStack.add(false);
        exitMarkers.add(null);
      }
    }

    return TreeSnapshot<TKey, TItem>(
      roots: rootKeys,
      dataByKey: dataByKey,
      childrenByParent: childrenByParent,
    );
  }

  /// Builds a validated snapshot from flat items with optional parent keys.
  ///
  /// Sibling order follows the iteration order of [items]. If [parentOf]
  /// returns a key that is not present in [items], the item is treated as a
  /// root.
  factory TreeSnapshot.fromFlat({
    required Iterable<TItem> items,
    required TKey Function(TItem item) keyOf,
    required TKey? Function(TItem item) parentOf,
  }) {
    final orderedItems = List<TItem>.of(items);
    final dataByKey = <TKey, TItem>{};

    for (final item in orderedItems) {
      final key = keyOf(item);
      if (dataByKey.containsKey(key)) {
        throw ArgumentError(
          "TreeSnapshot.fromFlat encountered duplicate key \"$key\".",
        );
      }
      dataByKey[key] = item;
    }

    final roots = <TKey>[];
    final childrenByParent = <TKey, List<TKey>>{};
    for (final item in orderedItems) {
      final key = keyOf(item);
      final parentKey = parentOf(item);
      final TKey? effectiveParent =
          parentKey != null && dataByKey.containsKey(parentKey)
          ? parentKey
          : null;

      if (effectiveParent == null) {
        roots.add(key);
      } else {
        final children = childrenByParent.putIfAbsent(
          effectiveParent,
          () => <TKey>[],
        );
        children.add(key);
      }
    }

    return TreeSnapshot<TKey, TItem>(
      roots: roots,
      dataByKey: dataByKey,
      childrenByParent: childrenByParent,
    );
  }

  /// Root node keys in render order.
  final List<TKey> roots;

  /// Payloads keyed by node ID.
  final Map<TKey, TItem> dataByKey;

  /// Child keys keyed by parent node ID.
  final Map<TKey, List<TKey>> childrenByParent;

  /// Gets the payload for [key], or null if missing.
  TItem? operator [](TKey key) {
    return dataByKey[key];
  }

  /// Converts the snapshot roots into [TreeNode] objects for syncing.
  List<TreeNode<TKey, TItem>> buildRoots() {
    return <TreeNode<TKey, TItem>>[
      for (final key in roots)
        TreeNode<TKey, TItem>(key: key, data: dataByKey[key] as TItem),
    ];
  }

  /// Converts the children of [parentKey] into [TreeNode] objects.
  List<TreeNode<TKey, TItem>> buildChildren(TKey parentKey) {
    final childKeys = childrenByParent[parentKey];
    if (childKeys == null) {
      return <TreeNode<TKey, TItem>>[];
    }
    return <TreeNode<TKey, TItem>>[
      for (final key in childKeys)
        TreeNode<TKey, TItem>(key: key, data: dataByKey[key] as TItem),
    ];
  }

  void _validate() {
    final rootSet = <TKey>{};
    for (final rootKey in roots) {
      if (!dataByKey.containsKey(rootKey)) {
        throw ArgumentError(
          "TreeSnapshot roots contains \"$rootKey\", but dataByKey does not.",
        );
      }
      if (!rootSet.add(rootKey)) {
        throw ArgumentError(
          "TreeSnapshot roots contains duplicate key \"$rootKey\".",
        );
      }
    }

    final parentCount = <TKey, int>{};
    for (final entry in childrenByParent.entries) {
      final parentKey = entry.key;
      if (!dataByKey.containsKey(parentKey)) {
        throw ArgumentError(
          "TreeSnapshot childrenByParent contains parent \"$parentKey\", "
          "but dataByKey does not.",
        );
      }

      final seenChildren = <TKey>{};
      for (final childKey in entry.value) {
        if (!dataByKey.containsKey(childKey)) {
          throw ArgumentError(
            "TreeSnapshot childrenByParent contains child \"$childKey\", "
            "but dataByKey does not.",
          );
        }
        if (!seenChildren.add(childKey)) {
          throw ArgumentError(
            "TreeSnapshot childrenByParent contains duplicate child "
            "\"$childKey\" under parent \"$parentKey\".",
          );
        }
        parentCount[childKey] = (parentCount[childKey] ?? 0) + 1;
        if (parentCount[childKey]! > 1) {
          throw ArgumentError(
            "TreeSnapshot assigns child \"$childKey\" to multiple parents.",
          );
        }
      }
    }

    for (final rootKey in roots) {
      if (parentCount.containsKey(rootKey)) {
        throw ArgumentError(
          "TreeSnapshot root \"$rootKey\" also appears as a child.",
        );
      }
    }

    final visited = <TKey>{};
    final visiting = <TKey>{};

    // Iterative DFS so deep trees do not stack-overflow Dart's
    // recursion limit. Two parallel stacks: `keys` is the work queue,
    // `exits` carries `null` for entry frames and the key that should
    // be moved from `visiting` to `visited` on the matching post-order
    // pop.
    final keys = <TKey>[];
    final exits = <TKey?>[];
    for (final rootKey in roots) {
      if (visited.contains(rootKey)) continue;
      keys.add(rootKey);
      exits.add(null);
      while (keys.isNotEmpty) {
        final key = keys.removeLast();
        final exitKey = exits.removeLast();

        if (exitKey != null) {
          // Post-order pop: subtree fully validated.
          visiting.remove(exitKey);
          visited.add(exitKey);
          continue;
        }

        if (visited.contains(key)) continue;
        if (!visiting.add(key)) {
          throw ArgumentError(
            "TreeSnapshot contains a cycle involving key \"$key\".",
          );
        }

        // Push exit marker first so it pops AFTER all children.
        keys.add(key);
        exits.add(key);

        final children = childrenByParent[key];
        if (children != null) {
          for (int i = children.length - 1; i >= 0; i--) {
            final childKey = children[i];
            if (visited.contains(childKey)) continue;
            keys.add(childKey);
            exits.add(null);
          }
        }
      }
    }

    if (visited.length != dataByKey.length) {
      final unreachable = <TKey>[
        for (final key in dataByKey.keys)
          if (!visited.contains(key)) key,
      ];
      throw ArgumentError(
        "TreeSnapshot contains unreachable nodes or a rootless cycle: "
        "$unreachable.",
      );
    }
  }
}

class _NormalizedTreeInput<TKey, TItem> {
  const _NormalizedTreeInput({
    required this.roots,
    required this.childrenByParent,
  });

  final List<TreeNode<TKey, TItem>> roots;
  final Map<TKey, List<TreeNode<TKey, TItem>>> childrenByParent;

  List<TreeNode<TKey, TItem>> childrenOf(TKey key) {
    return childrenByParent[key] ?? <TreeNode<TKey, TItem>>[];
  }
}

/// A sliver widget that declaratively displays a tree and animates changes.
///
/// Example:
/// ```dart
/// SyncedSliverTree<String, Folder>(
///   tree: <SyncedTreeNode<String, Folder>>[
///     SyncedTreeNode<String, Folder>(
///       key: rootFolder.id,
///       data: rootFolder,
///       children: <SyncedTreeNode<String, Folder>>[
///         SyncedTreeNode<String, Folder>(
///           key: childFolder.id,
///           data: childFolder,
///         ),
///       ],
///     ),
///   ],
///   itemBuilder: (context, node) {
///     return ListTile(
///       title: Text(node.item.name),
///       leading: node.hasChildren
///           ? IconButton(
///               icon: Icon(
///                 node.isExpanded
///                     ? Icons.expand_more
///                     : Icons.chevron_right,
///               ),
///               onPressed: node.toggle,
///             )
///           : null,
///     );
///   },
/// )
/// ```
class SyncedSliverTree<TKey, TItem> extends StatefulWidget {
  /// Creates a synced sliver tree from an immutable nested tree.
  const SyncedSliverTree({
    required Iterable<SyncedTreeNode<TKey, TItem>> tree,
    required this.itemBuilder,
    this.preserveExpansion = true,
    this.initiallyExpanded = true,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.indentWidth = 0.0,
    this.maxStickyDepth = 0,
    super.key,
  }) : _mode = _SyncedSliverTreeMode.tree,
       _tree = tree,
       _nodeRoots = null,
       _nodeChildrenOf = null,
       _hierarchyRoots = null,
       _flatItems = null,
       _snapshot = null,
       _keyOf = null,
       _childrenOf = null,
       _parentOf = null;

  /// Creates a synced sliver tree from existing [TreeNode] roots plus
  /// a [childrenOf] callback.
  const SyncedSliverTree.nodes({
    required Iterable<TreeNode<TKey, TItem>> roots,
    required Iterable<TreeNode<TKey, TItem>> Function(TKey key) childrenOf,
    required this.itemBuilder,
    this.preserveExpansion = true,
    this.initiallyExpanded = true,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.indentWidth = 0.0,
    this.maxStickyDepth = 0,
    super.key,
  }) : _mode = _SyncedSliverTreeMode.nodes,
       _tree = null,
       _nodeRoots = roots,
       _nodeChildrenOf = childrenOf,
       _hierarchyRoots = null,
       _flatItems = null,
       _snapshot = null,
       _keyOf = null,
       _childrenOf = null,
       _parentOf = null;

  /// Creates a synced sliver tree from nested domain objects.
  const SyncedSliverTree.hierarchy({
    required Iterable<TItem> roots,
    required TKey Function(TItem item) keyOf,
    required Iterable<TItem> Function(TItem item) childrenOf,
    required this.itemBuilder,
    this.preserveExpansion = true,
    this.initiallyExpanded = true,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.indentWidth = 0.0,
    this.maxStickyDepth = 0,
    super.key,
  }) : _mode = _SyncedSliverTreeMode.hierarchy,
       _tree = null,
       _nodeRoots = null,
       _nodeChildrenOf = null,
       _hierarchyRoots = roots,
       _flatItems = null,
       _snapshot = null,
       _keyOf = keyOf,
       _childrenOf = childrenOf,
       _parentOf = null;

  /// Creates a synced sliver tree from flat items with optional parent keys.
  const SyncedSliverTree.flat({
    required Iterable<TItem> items,
    required TKey Function(TItem item) keyOf,
    required TKey? Function(TItem item) parentOf,
    required this.itemBuilder,
    this.preserveExpansion = true,
    this.initiallyExpanded = true,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.indentWidth = 0.0,
    this.maxStickyDepth = 0,
    super.key,
  }) : _mode = _SyncedSliverTreeMode.flat,
       _tree = null,
       _nodeRoots = null,
       _nodeChildrenOf = null,
       _hierarchyRoots = null,
       _flatItems = items,
       _snapshot = null,
       _keyOf = keyOf,
       _childrenOf = null,
       _parentOf = parentOf;

  /// Creates a synced sliver tree from a precomputed validated snapshot.
  const SyncedSliverTree.snapshot({
    required TreeSnapshot<TKey, TItem> snapshot,
    required this.itemBuilder,
    this.preserveExpansion = true,
    this.initiallyExpanded = true,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.indentWidth = 0.0,
    this.maxStickyDepth = 0,
    super.key,
  }) : _mode = _SyncedSliverTreeMode.snapshot,
       _tree = null,
       _nodeRoots = null,
       _nodeChildrenOf = null,
       _hierarchyRoots = null,
       _flatItems = null,
       _snapshot = snapshot,
       _keyOf = null,
       _childrenOf = null,
       _parentOf = null;

  final _SyncedSliverTreeMode _mode;
  final Iterable<SyncedTreeNode<TKey, TItem>>? _tree;
  final Iterable<TreeNode<TKey, TItem>>? _nodeRoots;
  final Iterable<TreeNode<TKey, TItem>> Function(TKey key)? _nodeChildrenOf;
  final Iterable<TItem>? _hierarchyRoots;
  final Iterable<TItem>? _flatItems;
  final TreeSnapshot<TKey, TItem>? _snapshot;
  final TKey Function(TItem item)? _keyOf;
  final Iterable<TItem> Function(TItem item)? _childrenOf;
  final TKey? Function(TItem item)? _parentOf;

  /// Builds the widget for each visible node.
  final TreeItemBuilder<TKey, TItem> itemBuilder;

  /// Whether to preserve expansion state when nodes are removed and re-added.
  final bool preserveExpansion;

  /// Whether all nodes should be expanded when the tree is first created.
  final bool initiallyExpanded;

  /// Duration for expand/collapse and add/remove animations.
  final Duration animationDuration;

  /// Curve for animations.
  final Curve animationCurve;

  /// Horizontal indent per depth level in logical pixels.
  final double indentWidth;

  /// How many depth levels of headers should stick to the top.
  ///
  /// 0 means no sticky headers. 1 means root nodes stick, etc.
  final int maxStickyDepth;

  @override
  State<SyncedSliverTree<TKey, TItem>> createState() =>
      _SyncedSliverTreeState<TKey, TItem>();
}

class _SyncedSliverTreeState<TKey, TItem>
    extends State<SyncedSliverTree<TKey, TItem>>
    with TickerProviderStateMixin {
  late TreeController<TKey, TItem> _treeController;
  late TreeSyncController<TKey, TItem> _syncController;
  bool _hasSyncedOnce = false;

  @override
  void initState() {
    super.initState();
    _treeController = TreeController<TKey, TItem>(
      vsync: this,
      animationDuration: widget.animationDuration,
      animationCurve: widget.animationCurve,
      indentWidth: widget.indentWidth,
    );
    _syncController = TreeSyncController<TKey, TItem>(
      treeController: _treeController,
      preserveExpansion: widget.preserveExpansion,
    );
    _sync(animate: false);
    if (widget.initiallyExpanded) {
      _treeController.expandAll(animate: false);
    }
  }

  @override
  void didUpdateWidget(SyncedSliverTree<TKey, TItem> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.animationDuration != widget.animationDuration) {
      _treeController.animationDuration = widget.animationDuration;
    }
    if (oldWidget.animationCurve != widget.animationCurve) {
      _treeController.animationCurve = widget.animationCurve;
    }
    if (oldWidget.indentWidth != widget.indentWidth) {
      _treeController.indentWidth = widget.indentWidth;
    }

    if (widget.preserveExpansion != oldWidget.preserveExpansion) {
      _syncController.dispose();
      _syncController = TreeSyncController<TKey, TItem>(
        treeController: _treeController,
        preserveExpansion: widget.preserveExpansion,
      );
      _syncController.initializeTracking();
    }

    _sync(animate: true);
  }

  void _sync({required bool animate}) {
    final previousChildrenByParent = _hasSyncedOnce
        ? _syncController.snapshotCurrentChildren()
        : null;
    // Capture the set of keys with remembered expansion state BEFORE the
    // sync. syncRoots will clear entries as part of _restoreExpansion /
    // _pruneExpansionMemory, so by the time _expandParentsThatGainedChildren
    // runs below, the memory no longer reflects which keys were filtered
    // out previously — and the heuristic would wrongly auto-expand a
    // re-added, user-collapsed section.
    final rememberedBeforeSync = _syncController.snapshotRememberedKeys();

    switch (widget._mode) {
      case _SyncedSliverTreeMode.tree:
        final normalized = _normalizeTree(
          widget._tree as Iterable<SyncedTreeNode<TKey, TItem>>,
        );
        _syncController.syncRoots(
          normalized.roots,
          childrenOf: normalized.childrenOf,
          animate: animate,
        );
        break;
      case _SyncedSliverTreeMode.nodes:
        _syncController.syncRoots(
          List<TreeNode<TKey, TItem>>.of(
            widget._nodeRoots as Iterable<TreeNode<TKey, TItem>>,
          ),
          childrenOf: (key) {
            return List<TreeNode<TKey, TItem>>.of(
              (widget._nodeChildrenOf
                  as Iterable<TreeNode<TKey, TItem>> Function(TKey key))(key),
            );
          },
          animate: animate,
        );
        break;
      case _SyncedSliverTreeMode.hierarchy:
      case _SyncedSliverTreeMode.flat:
      case _SyncedSliverTreeMode.snapshot:
        final snapshot = _buildSnapshot();
        _syncController.syncRoots(
          snapshot.buildRoots(),
          childrenOf: snapshot.buildChildren,
          animate: animate,
        );
        break;
    }

    if (previousChildrenByParent != null && widget.initiallyExpanded) {
      expandParentsThatGainedChildren<TKey, TItem>(
        controller: _treeController,
        oldChildrenByParent: previousChildrenByParent,
        newChildrenByParent: _syncController.snapshotCurrentChildren(),
        rememberedBeforeSync: rememberedBeforeSync,
        animate: animate,
      );
    }
    _hasSyncedOnce = true;
  }

  TreeSnapshot<TKey, TItem> _buildSnapshot() {
    return switch (widget._mode) {
      _SyncedSliverTreeMode.tree => throw StateError(
        "SyncedSliverTree tree and nodes modes do not build TreeSnapshot "
        "internally.",
      ),
      _SyncedSliverTreeMode.nodes => throw StateError(
        "SyncedSliverTree tree and nodes modes do not build TreeSnapshot "
        "internally.",
      ),
      _SyncedSliverTreeMode.hierarchy =>
        TreeSnapshot<TKey, TItem>.fromHierarchy(
          roots: widget._hierarchyRoots as Iterable<TItem>,
          keyOf: widget._keyOf as TKey Function(TItem item),
          childrenOf:
              widget._childrenOf as Iterable<TItem> Function(TItem item),
        ),
      _SyncedSliverTreeMode.flat => TreeSnapshot<TKey, TItem>.fromFlat(
        items: widget._flatItems as Iterable<TItem>,
        keyOf: widget._keyOf as TKey Function(TItem item),
        parentOf: widget._parentOf as TKey? Function(TItem item),
      ),
      _SyncedSliverTreeMode.snapshot =>
        widget._snapshot as TreeSnapshot<TKey, TItem>,
    };
  }

  _NormalizedTreeInput<TKey, TItem> _normalizeTree(
    Iterable<SyncedTreeNode<TKey, TItem>> tree,
  ) {
    final roots = <TreeNode<TKey, TItem>>[];
    final childrenByParent = <TKey, List<TreeNode<TKey, TItem>>>{};
    final seen = <TKey>{};
    final visiting = <TKey>{};
    // Iterative DFS so deep input trees do not stack-overflow Dart's
    // recursion limit. Tracks each node's [TreeNode] in [nodeByKey] so
    // the post-order exit phase can populate `childrenByParent[key]`
    // by looking up each child's already-built [TreeNode] — sidesteps
    // the recursive version's "visit child returns its TreeNode for the
    // parent's list" pattern.
    final nodeByKey = <TKey, TreeNode<TKey, TItem>>{};

    final stack = <SyncedTreeNode<TKey, TItem>>[];
    final isRootStack = <bool>[];
    // true = post-order exit frame, false = pre-order entry frame.
    final exitMarkers = <bool>[];

    for (final root in tree) {
      stack.add(root);
      isRootStack.add(true);
      exitMarkers.add(false);
    }

    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      final isRoot = isRootStack.removeLast();
      final isExit = exitMarkers.removeLast();

      if (isExit) {
        visiting.remove(node.key);
        if (node.children.isNotEmpty) {
          final childNodes = <TreeNode<TKey, TItem>>[];
          for (final child in node.children) {
            childNodes.add(nodeByKey[child.key]!);
          }
          childrenByParent[node.key] = childNodes;
        }
        continue;
      }

      final key = node.key;
      if (!visiting.add(key)) {
        throw ArgumentError(
          "SyncedSliverTree.tree detected a cycle involving key \"$key\".",
        );
      }
      if (!seen.add(key)) {
        throw ArgumentError(
          "SyncedSliverTree.tree encountered duplicate key \"$key\".",
        );
      }

      // Pre-validate sibling-key uniqueness within node.children. Done
      // before the recursion so the error matches the recursive version's
      // throw site (parent context, not deep inside the child's visit).
      final seenChildren = <TKey>{};
      for (final child in node.children) {
        if (!seenChildren.add(child.key)) {
          throw ArgumentError(
            "SyncedSliverTree.tree encountered duplicate child key "
            "\"${child.key}\" under parent \"$key\".",
          );
        }
      }

      final treeNode = TreeNode<TKey, TItem>(key: key, data: node.data);
      nodeByKey[key] = treeNode;
      if (isRoot) {
        roots.add(treeNode);
      }

      // Push exit marker FIRST so it pops AFTER all children — the
      // recursive version's `visiting.remove(key)` and its
      // `childrenByParent[key] = childNodes` happen at the tail of the
      // function body, after all child recursion completes.
      stack.add(node);
      isRootStack.add(false);
      exitMarkers.add(true);

      // Then push children in reverse so the first child pops first,
      // preserving left-to-right visit order.
      for (int i = node.children.length - 1; i >= 0; i--) {
        stack.add(node.children[i]);
        isRootStack.add(false);
        exitMarkers.add(false);
      }
    }

    return _NormalizedTreeInput<TKey, TItem>(
      roots: roots,
      childrenByParent: childrenByParent,
    );
  }

  @override
  void dispose() {
    _syncController.dispose();
    _treeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SliverTree<TKey, TItem>(
      controller: _treeController,
      maxStickyDepth: widget.maxStickyDepth,
      nodeBuilder: (context, key, depth) {
        final nodeData = _treeController.getNodeData(key);
        if (nodeData == null) {
          return const SizedBox.shrink();
        }
        return widget.itemBuilder(
          context,
          TreeItemView<TKey, TItem>(
            key: key,
            item: nodeData.data,
            depth: depth,
            parentKey: _treeController.getParent(key),
            controller: _treeController,
          ),
        );
      },
    );
  }
}
