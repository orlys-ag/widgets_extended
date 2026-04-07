/// Widget for displaying a tree structure as a sliver.
library;

import 'package:flutter/widgets.dart';

import 'render_sliver_tree.dart';
import 'sliver_tree_element.dart';
import 'tree_controller.dart';

/// A sliver that displays a tree structure with support for
/// expand/collapse animations.
///
/// The tree data and state are managed by [TreeController]. The widget
/// rebuilds when the controller notifies listeners (e.g., on animation tick
/// or expand/collapse).
///
/// Children are built lazily using [nodeBuilder] only when they become
/// visible in the viewport.
///
/// Example:
/// ```dart
/// class _MyTreeState extends State<MyTree> with TickerProviderStateMixin {
///   late final TreeController<String, String> _controller;
///
///   @override
///   void initState() {
///     super.initState();
///     _controller = TreeController<String, String>(vsync: this);
///     _controller.setRoots([
///       TreeNodeData(id: '1', data: 'Root 1'),
///       TreeNodeData(id: '2', data: 'Root 2'),
///     ]);
///     _controller.setChildren('1', [
///       TreeNodeData(id: '1.1', data: 'Child 1.1'),
///       TreeNodeData(id: '1.2', data: 'Child 1.2'),
///     ]);
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return CustomScrollView(
///       slivers: [
///         SliverTree<String, String>(
///           controller: _controller,
///           nodeBuilder: (context, nodeKey, depth) {
///             final data = _controller.getNodeData(nodeKey)!.data;
///             return ListTile(
///               title: Text(data),
///               leading: Icon(Icons.folder),
///             );
///           },
///         ),
///       ],
///     );
///   }
/// }
/// ```
class SliverTree<TKey, TData> extends RenderObjectWidget {
  /// Creates a sliver tree.
  const SliverTree({
    required this.controller,
    required this.nodeBuilder,
    this.maxStickyDepth = 0,
    super.key,
  });

  /// Controller that manages tree state and animations.
  final TreeController<TKey, TData> controller;

  /// Builder function that creates a widget for each visible tree node.
  ///
  /// The [nodeKey] parameter is the unique identifier for the node.
  /// The [nodeDepth] parameter is the nesting level (0 for roots).
  ///
  /// Use [TreeController.getNodeData] to look up the node's data payload.
  ///
  /// The returned widget should typically be a fixed-height item like
  /// [ListTile] or a custom row widget. Variable-height items are supported
  /// but may affect scroll performance.
  final Widget Function(BuildContext context, TKey nodeKey, int nodeDepth)
  nodeBuilder;

  /// Maximum depth of nodes that become sticky headers.
  ///
  /// - `0` = no sticky headers (default, zero overhead)
  /// - `1` = root nodes (depth 0) stick
  /// - `2` = roots + their direct children (depths 0–1) stick
  /// - etc.
  final int maxStickyDepth;

  @override
  SliverTreeElement<TKey, TData> createElement() =>
      SliverTreeElement<TKey, TData>(this);

  @override
  RenderSliverTree<TKey, TData> createRenderObject(BuildContext context) {
    return RenderSliverTree<TKey, TData>(
      controller: controller,
      maxStickyDepth: maxStickyDepth,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverTree<TKey, TData> renderObject,
  ) {
    renderObject
      ..controller = controller
      ..maxStickyDepth = maxStickyDepth;
  }
}
