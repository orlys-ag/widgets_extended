/// Declarative wrapper around [SliverTree] that adds drag-and-drop reorder
/// over a [TreeReorderController].
///
/// Each row produced by [nodeBuilder] receives a `wrap` callback. Calling
/// `wrap` returns a widget that:
///
/// - Attaches a gesture recognizer (long-press on the whole row, or an
///   [ImmediateMultiDragGestureRecognizer] over a provided drag handle).
/// - On drag start, captures the pointer, lowers the source row's opacity,
///   starts a session on [reorderController].
/// - On drag update / end / cancel, forwards to the controller.
///
/// The drop indicator is rendered by a lightweight overlay entry owned by
/// this widget's internal state. It repaints on each
/// [TreeReorderController]'s target change (listened via
/// [TreeController.addAnimationListener] is insufficient — drops update
/// between ticks, so the widget listens directly to the reorder controller
/// via a lightweight [ValueNotifier]).
library;

import 'package:flutter/widgets.dart';

import 'render_sliver_tree.dart';
import 'sliver_tree_widget.dart';
import 'tree_controller.dart';
import 'tree_reorder_controller.dart';

/// Signature of the `wrap` callback passed to [SliverReorderableTree.nodeBuilder].
///
/// Returns a widget that wraps [child] with drag behavior. Exactly one of
/// [handle] or [longPressToDrag] must be chosen:
///
/// - Provide a [handle] widget (e.g. `Icon(Icons.drag_indicator)`) to
///   restrict drag initiation to that handle. Recommended for desktop.
/// - Pass `longPressToDrag: true` to start the drag after a long press
///   anywhere on the row. Recommended for mobile.
///
/// If both [handle] is non-null and [longPressToDrag] is true, [handle]
/// wins and the long-press is ignored.
typedef ReorderableNodeWrapper =
    Widget Function({
      required Widget child,
      Widget? handle,
      bool longPressToDrag,
    });

/// Declarative drag-and-drop reorderable [SliverTree].
class SliverReorderableTree<TKey, TData> extends StatefulWidget {
  const SliverReorderableTree({
    required this.controller,
    required this.reorderController,
    required this.nodeBuilder,
    this.maxStickyDepth = 0,
    this.indentPerDepth = 24.0,
    this.draggedOpacity = 0.3,
    this.dropIndicatorColor = const Color(0xFF2196F3),
    this.dropIndicatorThickness = 2.0,
    super.key,
  });

  /// The tree controller driving structural state and animations.
  final TreeController<TKey, TData> controller;

  /// The reorder controller orchestrating the drag lifecycle.
  final TreeReorderController<TKey, TData> reorderController;

  /// Builds each row. Wrap the row widget with [wrap] to enable dragging.
  final Widget Function(
    BuildContext context,
    TKey nodeKey,
    int nodeDepth,
    ReorderableNodeWrapper wrap,
  )
  nodeBuilder;

  /// See [SliverTree.maxStickyDepth].
  final int maxStickyDepth;

  /// Horizontal indent used per depth level when positioning the drop
  /// indicator. Should match the indent your [nodeBuilder] produces.
  final double indentPerDepth;

  /// Opacity applied to the source row while it is being dragged.
  final double draggedOpacity;

  /// Color of the drop indicator line.
  final Color dropIndicatorColor;

  /// Thickness of the drop indicator line in logical pixels.
  final double dropIndicatorThickness;

  @override
  State<SliverReorderableTree<TKey, TData>> createState() =>
      _SliverReorderableTreeState<TKey, TData>();
}

/// Inherited state published down the subtree so wrapper widgets can read
/// "am I being dragged?" without a separate subscription.
class _ReorderableScope<TKey, TData> extends InheritedWidget {
  const _ReorderableScope({
    required this.state,
    required super.child,
    required this.draggedKey,
  });

  final _SliverReorderableTreeState<TKey, TData> state;
  final TKey? draggedKey;

  @override
  bool updateShouldNotify(_ReorderableScope<TKey, TData> old) =>
      draggedKey != old.draggedKey || !identical(state, old.state);

  static _ReorderableScope<TKey, TData>? maybeOf<TKey, TData>(
    BuildContext context,
  ) {
    return context
        .dependOnInheritedWidgetOfExactType<_ReorderableScope<TKey, TData>>();
  }
}

class _SliverReorderableTreeState<TKey, TData>
    extends State<SliverReorderableTree<TKey, TData>> {
  OverlayEntry? _indicatorEntry;
  TKey? _draggedKey;

  @override
  void dispose() {
    _removeIndicator();
    super.dispose();
  }

  void _removeIndicator() {
    _indicatorEntry?.remove();
    _indicatorEntry = null;
  }

  void _ensureIndicator(BuildContext context) {
    if (_indicatorEntry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _indicatorEntry = OverlayEntry(
      builder: (_) => _DropIndicator<TKey, TData>(
        reorderController: widget.reorderController,
        color: widget.dropIndicatorColor,
        thickness: widget.dropIndicatorThickness,
        scrollableFinder: () {
          // Resolve the innermost scrollable at this widget's build context.
          // Called lazily on every repaint so a changing viewport still works.
          return Scrollable.maybeOf(this.context);
        },
      ),
    );
    overlay.insert(_indicatorEntry!);
  }

  /// Called from a row wrapper when drag starts. Lowers the source row's
  /// opacity (via the inherited scope) and shows the drop indicator.
  void _onDragStart(TKey key) {
    _ensureIndicator(context);
    setState(() => _draggedKey = key);
  }

  /// Called when drag ends or cancels. Restores opacity and hides indicator.
  void _onDragEnd() {
    if (!mounted) return;
    setState(() => _draggedKey = null);
    _removeIndicator();
  }

  RenderSliverTree<TKey, TData>? _renderObjectForSliver(BuildContext context) {
    // Walk up from a row's context to find the sliver's render object. The
    // sliver's element is reached via the first SliverTree ancestor.
    RenderSliverTree<TKey, TData>? found;
    context.visitAncestorElements((element) {
      final ro = element.findRenderObject();
      if (ro is RenderSliverTree<TKey, TData>) {
        found = ro;
        return false;
      }
      return true;
    });
    return found;
  }

  @override
  Widget build(BuildContext context) {
    return _ReorderableScope<TKey, TData>(
      state: this,
      draggedKey: _draggedKey,
      child: SliverTree<TKey, TData>(
        controller: widget.controller,
        maxStickyDepth: widget.maxStickyDepth,
        nodeBuilder: (context, key, depth) {
          Widget wrap({
            required Widget child,
            Widget? handle,
            bool longPressToDrag = false,
          }) {
            return _ReorderableRow<TKey, TData>(
              nodeKey: key,
              state: this,
              handle: handle,
              longPressToDrag: longPressToDrag,
              child: child,
            );
          }

          return widget.nodeBuilder(context, key, depth, wrap);
        },
      ),
    );
  }
}

/// Wrapper produced by `wrap(...)` in the node builder. Handles:
///
/// - Gesture recognition (long-press on the whole row or drag from a handle).
/// - Dimming the source during a drag.
/// - Forwarding pointer events to the [TreeReorderController].
class _ReorderableRow<TKey, TData> extends StatefulWidget {
  const _ReorderableRow({
    required this.nodeKey,
    required this.state,
    this.handle,
    this.longPressToDrag = false,
    required this.child,
  });

  final TKey nodeKey;
  final _SliverReorderableTreeState<TKey, TData> state;
  final Widget child;
  final Widget? handle;
  final bool longPressToDrag;

  @override
  State<_ReorderableRow<TKey, TData>> createState() =>
      _ReorderableRowState<TKey, TData>();
}

class _ReorderableRowState<TKey, TData>
    extends State<_ReorderableRow<TKey, TData>> {
  bool _isDraggingThisRow = false;

  @override
  Widget build(BuildContext context) {
    final scope = _ReorderableScope.maybeOf<TKey, TData>(context);
    final isMe = scope?.draggedKey == widget.nodeKey;
    final opacity = isMe ? widget.state.widget.draggedOpacity : 1.0;

    Widget content = Opacity(opacity: opacity, child: widget.child);

    if (widget.handle != null) {
      // Handle-only drag: row is otherwise freely scrollable/tappable.
      content = Row(
        children: [
          Expanded(child: content),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (details) =>
                _startDrag(context, details.globalPosition),
            onVerticalDragUpdate: (details) =>
                _updateDrag(details.globalPosition),
            onVerticalDragEnd: (_) => _endDrag(),
            onVerticalDragCancel: _cancelDrag,
            child: widget.handle!,
          ),
        ],
      );
    } else if (widget.longPressToDrag) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (details) =>
            _startDrag(context, details.globalPosition),
        onLongPressMoveUpdate: (details) => _updateDrag(details.globalPosition),
        onLongPressEnd: (_) => _endDrag(),
        onLongPressCancel: _cancelDrag,
        child: content,
      );
    }

    return content;
  }

  void _startDrag(BuildContext context, Offset globalPosition) {
    final renderObject = widget.state._renderObjectForSliver(context);
    final scrollable = Scrollable.maybeOf(context);
    if (renderObject == null || scrollable == null) return;
    try {
      widget.state.widget.reorderController.startDrag(
        key: widget.nodeKey,
        renderObject: renderObject,
        scrollable: scrollable,
        indentPerDepth: widget.state.widget.indentPerDepth,
        pointerGlobal: globalPosition,
      );
    } on ArgumentError {
      // canReorder returned false, or renderObject mismatch. Silently
      // decline to start the drag — gesture callbacks must not throw.
      return;
    }
    _isDraggingThisRow = true;
    widget.state._onDragStart(widget.nodeKey);
  }

  void _updateDrag(Offset globalPosition) {
    if (!_isDraggingThisRow) return;
    widget.state.widget.reorderController.updateDrag(globalPosition);
  }

  void _endDrag() {
    if (!_isDraggingThisRow) return;
    _isDraggingThisRow = false;
    final future = widget.state.widget.reorderController.endDrag();
    widget.state._onDragEnd();
    // endDrag is async (waits one post-frame for the FLIP "after" snapshot);
    // we release the opacity immediately so the slide runs visibly.
    unawaited(future);
  }

  void _cancelDrag() {
    if (!_isDraggingThisRow) return;
    _isDraggingThisRow = false;
    widget.state.widget.reorderController.cancelDrag();
    widget.state._onDragEnd();
  }
}

/// Overlay entry rendering the drop indicator line.
///
/// Subscribes directly to [TreeReorderController] (which is a
/// [ChangeNotifier]) so the indicator rebuilds on every target change —
/// including pointer moves that don't otherwise schedule a frame.
class _DropIndicator<TKey, TData> extends StatefulWidget {
  const _DropIndicator({
    required this.reorderController,
    required this.color,
    required this.thickness,
    required this.scrollableFinder,
  });

  final TreeReorderController<TKey, TData> reorderController;
  final Color color;
  final double thickness;
  final ScrollableState? Function() scrollableFinder;

  @override
  State<_DropIndicator<TKey, TData>> createState() =>
      _DropIndicatorState<TKey, TData>();
}

class _DropIndicatorState<TKey, TData>
    extends State<_DropIndicator<TKey, TData>> {
  @override
  void initState() {
    super.initState();
    widget.reorderController.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _DropIndicator<TKey, TData> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.reorderController, widget.reorderController)) {
      oldWidget.reorderController.removeListener(_onControllerChanged);
      widget.reorderController.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.reorderController.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.reorderController.currentTarget;
    if (target == null) return const SizedBox.shrink();
    final scrollable = widget.scrollableFinder();
    if (scrollable == null) return const SizedBox.shrink();

    final viewport = scrollable.context.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.attached) {
      return const SizedBox.shrink();
    }

    final viewportLocalY = target.indicatorScrollY - scrollable.position.pixels;
    if (viewportLocalY < 0 || viewportLocalY > viewport.size.height) {
      return const SizedBox.shrink();
    }

    final globalTopLeft = viewport.localToGlobal(
      Offset(target.indicatorIndent, viewportLocalY),
    );
    final lineWidth = viewport.size.width - target.indicatorIndent;

    // Center the line visually on the indicator y rather than painting it
    // below so the user's eye lands where the insertion will occur.
    final topOffset = globalTopLeft.dy - widget.thickness / 2;
    return Stack(
      children: [
        Positioned(
          left: globalTopLeft.dx,
          top: topOffset,
          width: lineWidth,
          height: widget.thickness,
          child: IgnorePointer(child: ColoredBox(color: widget.color)),
        ),
      ],
    );
  }
}

// Lightweight fire-and-forget for the async endDrag future.
void unawaited(Future<void> future) {
  // Intentionally empty; matches the naming of dart:async's unawaited
  // without requiring that import.
  future.ignore();
}
