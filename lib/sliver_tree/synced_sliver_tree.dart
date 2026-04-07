/// A declarative sliver tree that automatically diffs data changes.
///
/// [SyncedSliverTree] owns both a [TreeController] and a [TreeSyncController]
/// internally. When [roots] (or the result of [childrenOf]) change, it
/// computes the diff and applies animated insertions and removals.
///
/// For full control over the [TreeController], use [TreeSyncController]
/// directly with a [SliverTree] instead.
library;

import 'package:flutter/widgets.dart';

import 'sliver_tree_widget.dart';
import 'tree_controller.dart';
import 'tree_sync_controller.dart';
import 'types.dart';

/// A sliver widget that declaratively displays a tree and animates changes.
///
/// Provide [roots] and optionally [childrenOf] to describe the desired tree
/// structure. When these change, the widget diffs the old and new state and
/// animates the transitions.
///
/// Expansion state is preserved across data changes by default
/// ([preserveExpansion]).
///
/// Example:
/// ```dart
/// // childrenOf is called recursively at all depths.
/// // Return an empty list for leaf nodes.
/// final childrenByParent = <String, List<TreeNode<String, String>>>{
///   "folders":   [TreeNode(key: "docs", data: "Documents")],
///   "docs":      [TreeNode(key: "readme", data: "README.md")],
///   // "readme" has no entry → childrenOf returns []
/// };
///
/// SyncedSliverTree<String, String>(
///   roots: [TreeNode(key: "folders", data: "Folders")],
///   childrenOf: (key) => childrenByParent[key] ?? [],
///   nodeBuilder: (context, key, depth, controller) {
///     final label = controller.getNodeData(key)?.data ?? key;
///     return ListTile(title: Text(label));
///   },
/// )
/// ```
class SyncedSliverTree<TKey, TData> extends StatefulWidget {
  /// Creates a synced sliver tree.
  const SyncedSliverTree({
    required this.roots,
    this.childrenOf,
    required this.nodeBuilder,
    this.preserveExpansion = true,
    this.initiallyExpanded = true,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
    this.indentWidth = 0.0,
    this.maxStickyDepth = 0,
    super.key,
  });

  /// The desired root nodes of the tree.
  ///
  /// When this list changes, the widget diffs the old and new roots and
  /// animates the transitions.
  final List<TreeNode<TKey, TData>> roots;

  /// Optional callback that provides children for a given node key.
  ///
  /// Called recursively for every node in the tree — roots and their
  /// descendants — to populate and sync children at all depths. Return an
  /// empty list for leaf nodes. If null, roots are added as leaf nodes.
  final List<TreeNode<TKey, TData>> Function(TKey key)? childrenOf;

  /// Builds the widget for each visible node.
  ///
  /// The [controller] parameter provides access to expansion state and
  /// methods like [TreeController.toggle].
  final Widget Function(
    BuildContext context,
    TKey key,
    int depth,
    TreeController<TKey, TData> controller,
  )
  nodeBuilder;

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
  State<SyncedSliverTree<TKey, TData>> createState() =>
      _SyncedSliverTreeState<TKey, TData>();
}

class _SyncedSliverTreeState<TKey, TData>
    extends State<SyncedSliverTree<TKey, TData>>
    with TickerProviderStateMixin {
  late TreeController<TKey, TData> _treeController;
  late TreeSyncController<TKey, TData> _syncController;

  @override
  void initState() {
    super.initState();
    _treeController = TreeController<TKey, TData>(
      vsync: this,
      animationDuration: widget.animationDuration,
      animationCurve: widget.animationCurve,
      indentWidth: widget.indentWidth,
    );
    _syncController = TreeSyncController<TKey, TData>(
      treeController: _treeController,
      preserveExpansion: widget.preserveExpansion,
    );
    _sync(animate: false);
    if (widget.initiallyExpanded) {
      _treeController.expandAll(animate: false);
    }
  }

  @override
  void didUpdateWidget(SyncedSliverTree<TKey, TData> oldWidget) {
    super.didUpdateWidget(oldWidget);

    assert(
      oldWidget.animationDuration == widget.animationDuration &&
          oldWidget.animationCurve == widget.animationCurve &&
          oldWidget.indentWidth == widget.indentWidth,
      'SyncedSliverTree animationDuration, animationCurve, and indentWidth '
      'cannot be changed after creation. Use a Key to force recreation.',
    );

    if (widget.preserveExpansion != oldWidget.preserveExpansion) {
      _syncController.dispose();
      _syncController = TreeSyncController<TKey, TData>(
        treeController: _treeController,
        preserveExpansion: widget.preserveExpansion,
      );
      _syncController.initializeTracking();
    }

    _sync(animate: true);
  }

  void _sync({required bool animate}) {
    _syncController.syncRoots(
      widget.roots,
      childrenOf: widget.childrenOf,
      animate: animate,
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
    return SliverTree<TKey, TData>(
      controller: _treeController,
      maxStickyDepth: widget.maxStickyDepth,
      nodeBuilder: (context, key, depth) {
        return widget.nodeBuilder(context, key, depth, _treeController);
      },
    );
  }
}
