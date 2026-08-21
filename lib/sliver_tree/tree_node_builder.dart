/// A widget that rebuilds only when a specific node's state changes.
library;

import 'package:flutter/widgets.dart';

import 'tree_controller.dart';

/// A widget that listens to a [TreeController] but rebuilds only when the
/// specified node's [TreeController.hasChildren] or
/// [TreeController.isExpanded] answer actually changes.
///
/// Subscribes to the structural channel alone, so a change to a node's
/// DATA does not rebuild it; those two flags are all it surfaces. Being
/// named in a structural notification is not enough either: the values
/// are re-read and compared, and an unchanged pair rebuilds nothing.
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
///         onPressed: () => controller.toggle(key: path),
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

  /// The node to track. Changing it re-reads the flags without
  /// re-subscribing, because the listener is per-controller, not per-node.
  final TKey nodeId;

  /// Builder called with the node's current state.
  ///
  /// Re-invoked only when one of those two flags changes for this node.
  final Widget Function(BuildContext context, bool hasChildren, bool isExpanded)
  builder;

  @override
  State<TreeNodeBuilder<TKey, TData>> createState() =>
      _TreeNodeBuilderState<TKey, TData>();
}

class _TreeNodeBuilderState<TKey, TData>
    extends State<TreeNodeBuilder<TKey, TData>> {
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

  /// Re-reads both flags from the controller without rebuilding. For the
  /// paths that already know the widget is about to build.
  void _updateCachedValues() {
    _hasChildren = widget.controller.hasChildren(widget.nodeId);
    _isExpanded = widget.controller.isExpanded(widget.nodeId);
  }

  /// Structural-channel handler, and where the selectivity lives.
  ///
  /// A non-null [affectedKeys] that omits this node is ignored outright; a
  /// null one means "scope unknown" and is always examined. Either way the
  /// flags are re-read and [setState] runs only if one actually moved.
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
