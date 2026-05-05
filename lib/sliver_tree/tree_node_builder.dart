/// A widget that rebuilds only when a specific node's state changes.
library;

import 'package:flutter/widgets.dart';

import 'tree_controller.dart';

/// A widget that listens to a [TreeController] but only rebuilds when the
/// specified node's [hasChildren] or [isExpanded] state changes.
///
///
/// Example:
/// ```dart
/// TreeNodeBuilder<String, MyData>(
///   controller: controller,
///   nodeId: path,
///   builder: (context, hasChildren, isExpanded) {
///     if (hasChildren) {
///       return IconButton(
///         icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
///         onPressed: () => controller.toggle(path),
///       );
///     }
///     return const SizedBox.shrink();
///   },
/// )
/// ```
class TreeNodeBuilder<TKey, TData> extends StatefulWidget {
  /// Creates a tree node builder.
  const TreeNodeBuilder({
    required this.controller,
    required this.nodeId,
    required this.builder,
    super.key,
  });

  /// The controller to listen to.
  final TreeController<TKey, TData> controller;

  /// The node ID to track.
  final TKey nodeId;

  /// Builder called with the node's current state.
  ///
  /// Only called when [hasChildren] or [isExpanded] changes for this node.
  final Widget Function(BuildContext context, bool hasChildren, bool isExpanded)
  builder;

  @override
  State<TreeNodeBuilder<TKey, TData>> createState() => _TreeNodeBuilderState<TKey, TData>();
}

class _TreeNodeBuilderState<TKey, TData> extends State<TreeNodeBuilder<TKey, TData>> {
  late bool _hasChildren;
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _updateCachedValues();
    widget.controller.addStructuralListener(_onStructuralChange);
  }

  @override
  void didUpdateWidget(TreeNodeBuilder<TKey, TData> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeStructuralListener(_onStructuralChange);
      widget.controller.addStructuralListener(_onStructuralChange);
      _updateCachedValues();
    } else if (oldWidget.nodeId != widget.nodeId) {
      _updateCachedValues();
    }
  }

  @override
  void dispose() {
    widget.controller.removeStructuralListener(_onStructuralChange);
    super.dispose();
  }

  void _updateCachedValues() {
    _hasChildren = widget.controller.hasChildren(widget.nodeId);
    _isExpanded = widget.controller.isExpanded(widget.nodeId);
  }

  void _onStructuralChange(Set<TKey>? affectedKeys) {
    if (affectedKeys != null && !affectedKeys.contains(widget.nodeId)) {
      return;
    }
    final hasChildren = widget.controller.hasChildren(widget.nodeId);
    final isExpanded = widget.controller.isExpanded(widget.nodeId);
    if (hasChildren != _hasChildren || isExpanded != _isExpanded) {
      setState(() {
        _hasChildren = hasChildren;
        _isExpanded = isExpanded;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _hasChildren, _isExpanded);
  }
}
