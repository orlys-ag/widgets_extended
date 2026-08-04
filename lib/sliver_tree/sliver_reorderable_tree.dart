/// Declarative wrapper around [SliverTree] that adds drag-and-drop reorder
/// over a [TreeReorderController].
///
/// Each row produced by [nodeBuilder] receives a `wrap` callback. Calling
/// `wrap` returns a widget that:
///
/// - Attaches gestures: a long-press [GestureDetector] over the whole row
///   (`longPressToDrag: true`, mobile) or a vertical-drag detector over a
///   provided `handle` widget (desktop).
/// - On drag start, starts a session on [reorderController] (a `false`
///   return — `canReorder` refusal or not-yet-laid-out tree — quietly
///   declines the gesture), dims or hides the source row, and shows the
///   drag UI.
/// - On drag update / end / cancel, forwards to the controller. The row
///   re-validates session ownership before every forward so a stale
///   gesture can never commit another session, and a `deactivate()`
///   backstop cancels a session whose row unmounts mid-drag.
/// - Exposes custom semantics actions (move up / down / out / into
///   previous sibling) so assistive-technology users can reorder without
///   pointer drags, gated by the same `canReorder` / `canAcceptDrop`
///   policies.
///
/// Row wrappers are wired through an inherited `_ReorderableScope`: rows
/// read the reorder controller, presentation config, and the owner's
/// callbacks from the scope (no ancestor-State references) and locate the
/// render surface by walking up to the first [ReorderRenderPort] ancestor
/// rather than any concrete render type.
///
/// Drop feedback is the **make-room preview**, always on: while dragging,
/// rows part to open a live gap at the prospective slot. The gap is
/// paint-only — structure is untouched until the drop commits, and no
/// structural listeners or sync diffs fire from the preview. The dragged
/// row's in-place copy is hidden entirely (its slot closes up under it),
/// so the floating drag proxy is its only representation.
///
/// Drag UI lives in one overlay entry owned by this widget's state: the
/// drag proxy ([showDragProxy] / [dragProxyBuilder]) subscribes to
/// [TreeReorderController.pointerPosition] — the per-move channel — and
/// floats the dragged row's preview at the grab point.
///
/// The pointer's horizontal position picks the drop depth at subtree
/// right-boundaries (the default `x ~/ indentPerDepth` mapper passed to
/// `startDrag`). With the proxy enabled (the default), slot selection is
/// CARD-ANCHORED: it probes at the floating card's midpoint rather than
/// the pointer, so a long-press touch drag tracks the card in hand
/// regardless of grab point (handle drags are unaffected — their grab is
/// centered). Opt-in [hapticsOnDrag] adds lift / slot-change feedback.
library;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import 'reorder_render_port.dart';
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
    this.showDragProxy = true,
    this.dragProxyBuilder,
    this.hapticsOnDrag = false,
    this.addRepaintBoundaries = true,
    super.key,
  });

  /// The tree controller driving structural state and animations.
  final TreeController<TKey, TData> controller;

  /// The reorder controller orchestrating the drag lifecycle.
  ///
  /// Must wrap the same [TreeController] instance as [controller]
  /// (checked by an assert in debug builds; a mismatch throws from
  /// `startDrag` at the first drag otherwise).
  final TreeReorderController<TKey> reorderController;

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

  /// Horizontal indent per depth level, used to map the pointer's
  /// horizontal position to a preferred drop depth (`x ~/ indentPerDepth`)
  /// at subtree boundaries, where one visible slot has several legal depth
  /// expressions. Should match the indent your [nodeBuilder] produces.
  ///
  /// Set to `0` to disable x-aware depth selection entirely — drops then
  /// always resolve at the deepest legal level.
  final double indentPerDepth;

  /// Whether to render a floating preview of the dragged row that follows
  /// the pointer, anchored at the grab point. Defaults to true, and is
  /// implied true when [dragProxyBuilder] is provided.
  ///
  /// Turning this off leaves the drag with no representation under the
  /// pointer: the make-room preview hides the dragged row's in-place copy
  /// so its slot can close, and only the opening gap remains as feedback.
  ///
  /// The preview renders in the root [Overlay], OUTSIDE the row's original
  /// ancestry — the same contract as `Draggable.feedback`. Rows using
  /// inherited-ancestor-dependent widgets (e.g. Material ink widgets,
  /// which assert on a `Material` ancestor) need a [dragProxyBuilder] that
  /// re-provides those ancestors (e.g. wrap in
  /// `Material(type: MaterialType.transparency)`); this package is
  /// widgets-layer-only and cannot supply Material itself.
  final bool showDragProxy;

  /// Builds the floating drag preview. Receives the dragged key and the
  /// row's child widget (the same widget passed to `wrap`; null when the
  /// drag was started imperatively without a row). When null and
  /// [showDragProxy] is true, the default preview renders the row's child
  /// at 90% opacity, sized to the row's extent and viewport width.
  ///
  /// See [showDragProxy] for the overlay-ancestry contract (Material apps
  /// typically wrap the preview in a transparency `Material` here).
  final Widget Function(BuildContext context, TKey key, Widget? rowChild)?
  dragProxyBuilder;

  /// Opt-in drag haptics: [HapticFeedback.selectionClick] on lift and on
  /// each SEMANTIC SLOT change. Deliberately debounced on the slot identity
  /// `(parentKey, indexInFinalList)` rather than raw controller
  /// notifications — the coalesced channel also fires on same-slot
  /// EXPRESSION changes (crossing between e.g. below-last-row and
  /// above-next-header, which are the same slot), and buzzing while the
  /// gap stands still would be noise. Default off.
  final bool hapticsOnDrag;

  /// Whether to wrap each row in a [RepaintBoundary]. Forwarded to
  /// [SliverTree.addRepaintBoundaries].
  final bool addRepaintBoundaries;

  @override
  State<SliverReorderableTree<TKey, TData>> createState() =>
      _SliverReorderableTreeState<TKey, TData>();
}

/// Inherited scope publishing everything a row wrapper needs: the reorder
/// controller, presentation config, session state, and the owner state's
/// callbacks. Rows hold no reference to the ancestor [State] object.
///
/// The callbacks are method tear-offs of the owner state. Tear-off
/// identity is NOT stable across rebuilds, so [updateShouldNotify]
/// compares only the value fields — the callbacks always target the same
/// state object for the lifetime of the scope's element anyway.
class _ReorderableScope<TKey> extends InheritedWidget {
  const _ReorderableScope({
    required this.reorderController,
    required this.draggedKey,
    required this.indentPerDepth,
    required this.dragProxyEnabled,
    required this.onDragStart,
    required this.onSessionInterrupted,
    required super.child,
  });

  final TreeReorderController<TKey> reorderController;

  /// The key whose row is currently dragged, or null. Drives hiding the
  /// source row declaratively — make-room closes its slot underneath it.
  final TKey? draggedKey;

  /// Indent per depth level; rows use it to build the default x → depth
  /// hint mapper passed to `startDrag`. Carried as the raw double
  /// (value-comparable) rather than a closure so [updateShouldNotify]
  /// stays honest.
  final double indentPerDepth;

  /// Whether the floating drag proxy is enabled. Rows forward it as
  /// `startDrag(settleFromRelease:)` so the drop FLIP starts at the
  /// proxy's release position — the proxy hands off to the real row
  /// mid-flight instead of the row replaying the old-slot slide.
  final bool dragProxyEnabled;

  /// Row [key] successfully started a drag session: hide it and (when
  /// enabled) float the drag proxy built from [rowChild].
  final void Function(TKey key, Widget rowChild) onDragStart;

  /// Deactivate-backstop channel: the row owning [key]'s session unmounted
  /// mid-drag and its session was cancelled post-frame. The owner clears
  /// the drag UI iff its UI still shows that session — the key guard
  /// lives in the owner, next to the state it protects.
  final void Function(TKey key) onSessionInterrupted;

  @override
  bool updateShouldNotify(_ReorderableScope<TKey> old) {
    return draggedKey != old.draggedKey ||
        indentPerDepth != old.indentPerDepth ||
        dragProxyEnabled != old.dragProxyEnabled ||
        !identical(reorderController, old.reorderController);
  }

  static _ReorderableScope<TKey>? maybeOf<TKey>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ReorderableScope<TKey>>();
  }
}

class _SliverReorderableTreeState<TKey, TData>
    extends State<SliverReorderableTree<TKey, TData>> {
  OverlayEntry? _proxyEntry;
  TKey? _draggedKey;

  /// The dragged row's child widget, captured at drag start for the
  /// default proxy content. Cleared with the session.
  Widget? _draggedRowChild;

  @override
  void initState() {
    super.initState();
    widget.reorderController.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(SliverReorderableTree<TKey, TData> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.reorderController, widget.reorderController)) {
      oldWidget.reorderController.removeListener(_onControllerChanged);
      widget.reorderController.addListener(_onControllerChanged);
    }
    if (!widget.showDragProxy && widget.dragProxyBuilder == null) {
      _removeProxy();
    }
  }

  @override
  void dispose() {
    widget.reorderController.removeListener(_onControllerChanged);
    _removeProxy();
    super.dispose();
  }

  /// Syncs local drag UI (hidden source row + drag proxy) with the
  /// controller's session state. This is the SINGLE owner of drag-UI
  /// teardown for controller-driven session ends: the row wrappers'
  /// end/cancel handlers only forward to the controller, whose
  /// `notifyListeners` lands here. The one exception is the
  /// `deactivate()` backstop, which reaches this state via
  /// [_ReorderableScope.onSessionInterrupted] for the
  /// listener-moved-to-another-controller case.
  void _onControllerChanged() {
    if (widget.hapticsOnDrag) {
      _syncHaptics();
    } else if (_hapticsDragging || _lastHapticSlot != null) {
      // Keep the haptic state coherent while disabled: a stale
      // `_hapticsDragging = true` left by a mid-flight config toggle
      // would swallow the next session's lift click after re-enabling.
      _hapticsDragging = false;
      _lastHapticSlot = null;
    }
    if (_draggedKey != null && !widget.reorderController.isDragging) {
      _onDragEnd();
    }
  }

  /// Haptic state. The slot record uses structural equality; `null` slots
  /// (gap-hold dead spots) keep the last slot so returning to it stays
  /// silent.
  bool _hapticsDragging = false;
  (TKey?, int)? _lastHapticSlot;

  void _syncHaptics() {
    final reorder = widget.reorderController;
    final dragging = reorder.isDragging;
    final target = reorder.currentTarget;
    final slot = target == null
        ? null
        : (target.parentKey, target.indexInFinalList);
    if (dragging && !_hapticsDragging) {
      HapticFeedback.selectionClick();
      _lastHapticSlot = slot;
    } else if (dragging) {
      if (slot != null && slot != _lastHapticSlot) {
        HapticFeedback.selectionClick();
        _lastHapticSlot = slot;
      }
    } else {
      _lastHapticSlot = null;
    }
    _hapticsDragging = dragging;
  }

  void _removeProxy() {
    _proxyEntry?.remove();
    _proxyEntry = null;
    _draggedRowChild = null;
  }

  void _ensureProxy(BuildContext context) {
    if (!widget.showDragProxy && widget.dragProxyBuilder == null) {
      return;
    }
    if (_proxyEntry != null) {
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }
    _proxyEntry = OverlayEntry(
      builder: (_) => _DragProxy<TKey>(
        reorderController: widget.reorderController,
        proxyBuilder: widget.dragProxyBuilder,
        rowChildResolver: () {
          return _draggedRowChild;
        },
        scrollableFinder: () {
          return Scrollable.maybeOf(this.context);
        },
      ),
    );
    overlay.insert(_proxyEntry!);
  }

  /// Called (via the scope) from a row wrapper when drag starts. Hides the
  /// source row (make-room closes its slot) and floats the drag proxy when
  /// enabled.
  void _onDragStart(TKey key, Widget rowChild) {
    _draggedRowChild = rowChild;
    _ensureProxy(context);
    setState(() => _draggedKey = key);
  }

  /// Called when drag ends or cancels. Restores the source row and hides
  /// the proxy.
  void _onDragEnd() {
    if (!mounted) return;
    setState(() => _draggedKey = null);
    _removeProxy();
  }

  /// Deactivate-backstop entry: clear the drag UI only if it still shows
  /// [key]'s session (a newer session's UI must not be cleared by a stale
  /// backstop).
  void _onSessionInterrupted(TKey key) {
    if (_draggedKey == key) {
      _onDragEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(
      identical(widget.controller, widget.reorderController.treeController),
      "SliverReorderableTree.controller and "
      "reorderController.treeController must be the same TreeController "
      "instance — the reorder controller commits drops against its own "
      "controller, and a mismatch would mutate a tree this widget is not "
      "displaying.",
    );
    return _ReorderableScope<TKey>(
      reorderController: widget.reorderController,
      draggedKey: _draggedKey,
      indentPerDepth: widget.indentPerDepth,
      dragProxyEnabled:
          widget.showDragProxy || widget.dragProxyBuilder != null,
      onDragStart: _onDragStart,
      onSessionInterrupted: _onSessionInterrupted,
      child: SliverTree<TKey, TData>(
        controller: widget.controller,
        maxStickyDepth: widget.maxStickyDepth,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        nodeBuilder: (context, key, depth) {
          Widget wrap({
            required Widget child,
            Widget? handle,
            bool longPressToDrag = false,
          }) {
            return _ReorderableRow<TKey>(
              nodeKey: key,
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
/// - Hiding the source row during a drag (make-room closes its slot).
/// - Forwarding pointer events to the [TreeReorderController] (read from
///   the inherited scope — no ancestor-State reference).
class _ReorderableRow<TKey> extends StatefulWidget {
  const _ReorderableRow({
    required this.nodeKey,
    this.handle,
    this.longPressToDrag = false,
    required this.child,
  });

  final TKey nodeKey;
  final Widget child;
  final Widget? handle;
  final bool longPressToDrag;

  @override
  State<_ReorderableRow<TKey>> createState() => _ReorderableRowState<TKey>();
}

class _ReorderableRowState<TKey> extends State<_ReorderableRow<TKey>> {
  /// Reorder actions exposed to assistive technology. Const so every row
  /// shares one identifier per action; labels are the package's
  /// user-facing strings (no localization layer exists in this package).
  static const CustomSemanticsAction _moveUpAction = CustomSemanticsAction(
    label: "Move up",
  );
  static const CustomSemanticsAction _moveDownAction = CustomSemanticsAction(
    label: "Move down",
  );
  static const CustomSemanticsAction _moveOutAction = CustomSemanticsAction(
    label: "Move out",
  );
  static const CustomSemanticsAction _moveIntoPreviousAction =
      CustomSemanticsAction(label: "Move into previous sibling");

  bool _isDraggingThisRow = false;

  /// Scope values cached at dependency-update time. Gesture callbacks and
  /// `deactivate()` must not read the InheritedWidget (`dependOn*` is
  /// illegal outside build/didChangeDependencies), so they use these.
  ///
  /// On a reorder-controller swap the cache intentionally lags until the
  /// row's next dependency update: a session started under the old
  /// controller keeps being forwarded/cancelled on the OLD controller —
  /// the one that actually owns the session.
  late TreeReorderController<TKey> _reorder;
  late double _indentPerDepth;
  late bool _dragProxyEnabled;
  late void Function(TKey, Widget) _onDragStartCallback;
  late void Function(TKey) _onSessionInterruptedCallback;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _ReorderableScope.maybeOf<TKey>(context);
    assert(
      scope != null,
      "_ReorderableRow must be created by SliverReorderableTree's wrap "
      "callback, below its _ReorderableScope",
    );
    _reorder = scope!.reorderController;
    _indentPerDepth = scope.indentPerDepth;
    _dragProxyEnabled = scope.dragProxyEnabled;
    _onDragStartCallback = scope.onDragStart;
    _onSessionInterruptedCallback = scope.onSessionInterrupted;
  }

  @override
  void didUpdateWidget(covariant _ReorderableRow<TKey> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Gesture-mode swap backstop: flipping long-press ↔ handle mid-drag
    // (an app-level mode toggle hit by a second finger) rebuilds this
    // row with a DIFFERENT gesture structure — the recognizer that owns
    // the active pointer is disposed and its end/cancel callbacks can
    // never fire, orphaning the session (pin + scroll listener +
    // autoscroll ticker). The deactivate backstop does not cover this:
    // the State survives, only the build output changes. Same deferred
    // teardown discipline as deactivate(): didUpdateWidget runs in the
    // build phase, so cancelDrag's notifyListeners / the owner's
    // setState must not run synchronously here. A same-mode rebuild
    // (e.g. a new handle widget instance) keeps its recognizer and is
    // deliberately NOT a trigger.
    final modeChanged =
        oldWidget.longPressToDrag != widget.longPressToDrag ||
        (oldWidget.handle != null) != (widget.handle != null);
    if (modeChanged && _isDraggingThisRow) {
      _isDraggingThisRow = false;
      final reorder = _reorder;
      final onInterrupted = _onSessionInterruptedCallback;
      final nodeKey = widget.nodeKey;
      if (reorder.draggedKey == nodeKey) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (reorder.draggedKey != nodeKey) {
            return;
          }
          reorder.cancelDrag();
          onInterrupted(nodeKey);
        });
      }
    }
  }

  @override
  void deactivate() {
    // Lifecycle backstop: if this row unmounts while it owns the drag
    // (node removed and purged mid-drag, tree swapped, ...), its gesture
    // callbacks can never fire again — end the session instead of leaving
    // it (and the autoscroll ticker) orphaned. Eviction of a LIVE dragged
    // row is prevented by the render object's drag pin; this covers the
    // remaining unmount paths (dead-node GC deliberately ignores pins —
    // a purged row has nothing left to build).
    //
    // deactivate() only ever runs inside a BuildOwner.buildScope — for
    // the removed-and-purged case, the element's post-frame dead-node GC
    // pass. cancelDrag()'s notifyListeners and the ancestor's setState
    // must therefore NOT run synchronously here: they would throw
    // "setState() or markNeedsBuild() called during build" and abort the
    // rest of the GC pass. Only the local flag flip stays synchronous;
    // the teardown is deferred to a post-frame callback (the first point
    // guaranteed outside every build scope — a microtask can still land
    // inside this frame's build window). The callback re-validates
    // session ownership before acting: by the time it runs a new session
    // may have started, or the reorder controller may have been disposed
    // (after dispose, draggedKey is null, so the ownership check covers
    // both). Everything the callback needs is captured now from the
    // cached scope values — `widget`/`context` are unreadable after this
    // State unmounts.
    if (_isDraggingThisRow) {
      _isDraggingThisRow = false;
      final reorder = _reorder;
      final onInterrupted = _onSessionInterruptedCallback;
      final nodeKey = widget.nodeKey;
      if (reorder.draggedKey == nodeKey) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (reorder.draggedKey != nodeKey) {
            return;
          }
          reorder.cancelDrag();
          // cancelDrag's notifyListeners already drives the ancestor's
          // _onControllerChanged → _onDragEnd while it is listening; the
          // scope callback covers the listener having moved to a
          // different reorder controller (didUpdateWidget swap). The
          // owner's key guard keeps it from clearing UI owned by another
          // session.
          onInterrupted(nodeKey);
        });
      }
    }
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _ReorderableScope.maybeOf<TKey>(context);
    final isMe = scope?.draggedKey == widget.nodeKey;
    // Make-room hides the in-place dragged row entirely: its slot closes
    // up underneath it, so any residual paint would overlap the rows
    // shifting into that space. The drag proxy is its representation.
    Widget content = Opacity(
      opacity: isMe ? 0.0 : 1.0,
      child: widget.child,
    );

    if (widget.handle != null) {
      // Handle-only drag: row is otherwise freely scrollable/tappable.
      content = Row(
        children: [
          Expanded(child: content),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Report the TOUCH-DOWN position, not the post-slop
            // acceptance position: grab geometry (proxy anchor, probe
            // offset) is measured from where the user actually took hold
            // — the default `.start` behavior skews it by up to the
            // touch slop in the drag direction.
            dragStartBehavior: DragStartBehavior.down,
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

    // Expose the reorder capability to assistive technology. Pointer
    // drags are unusable with a screen reader; these actions commit the
    // same controller mutations as the equivalent drops, gated by the
    // same canReorder / canAcceptDrop policies. Availability is computed
    // per build (structural changes rebuild affected rows); execution
    // fresh-computes indices so a stale action invocation degrades to a
    // no-op instead of a wrong move.
    final semanticsActions = _semanticsActions();
    if (semanticsActions.isNotEmpty) {
      content = Semantics(
        customSemanticsActions: semanticsActions,
        child: content,
      );
    }

    return content;
  }

  /// Which reorder actions this row currently supports, mapped to their
  /// handlers. Empty for non-reorderable or absent/mid-exit rows.
  Map<CustomSemanticsAction, VoidCallback> _semanticsActions() {
    final tree = _reorder.treeController;
    final key = widget.nodeKey;
    final canReorder = _reorder.canReorder;
    if (canReorder != null && !canReorder(key)) {
      return const {};
    }
    final idx = tree.getIndexInParent(key);
    if (idx < 0) {
      return const {};
    }
    final parent = tree.getParent(key);
    final liveCount = parent == null
        ? tree.liveRootCount
        : tree.liveChildCount(parent);

    final actions = <CustomSemanticsAction, VoidCallback>{};
    if (idx > 0 && _dropAllowed(parent, idx - 1)) {
      actions[_moveUpAction] = _performMoveUp;
    }
    if (idx < liveCount - 1 && _dropAllowed(parent, idx + 1)) {
      actions[_moveDownAction] = _performMoveDown;
    }
    if (parent != null) {
      final grandparent = tree.getParent(parent);
      final outIndex = tree.getIndexInParent(parent) + 1;
      if (_dropAllowed(grandparent, outIndex)) {
        actions[_moveOutAction] = _performMoveOut;
      }
    }
    if (idx > 0) {
      final siblings = parent == null
          ? tree.liveRootKeys
          : tree.getLiveChildren(parent);
      final prev = siblings[idx - 1];
      if (_dropAllowed(prev, tree.liveChildCount(prev))) {
        actions[_moveIntoPreviousAction] = _performMoveIntoPrevious;
      }
    }
    return actions;
  }

  bool _dropAllowed(TKey? newParent, int index) {
    final policy = _reorder.canAcceptDrop;
    if (policy == null) {
      return true;
    }
    return policy(movingKey: widget.nodeKey, newParent: newParent, index: index);
  }

  void _performMoveUp() {
    _performSameParentMove(-1);
  }

  void _performMoveDown() {
    _performSameParentMove(1);
  }

  void _performSameParentMove(int delta) {
    final tree = _reorder.treeController;
    final key = widget.nodeKey;
    final idx = tree.getIndexInParent(key);
    if (idx < 0) {
      return;
    }
    final parent = tree.getParent(key);
    final siblings = parent == null
        ? tree.liveRootKeys
        : tree.getLiveChildren(parent);
    final newIndex = idx + delta;
    if (newIndex < 0 || newIndex >= siblings.length) {
      return;
    }
    siblings.removeAt(idx);
    siblings.insert(newIndex, key);
    if (parent == null) {
      tree.reorderRoots(siblings);
    } else {
      tree.reorderChildren(parent, siblings);
    }
  }

  void _performMoveOut() {
    final tree = _reorder.treeController;
    final key = widget.nodeKey;
    if (tree.getIndexInParent(key) < 0) {
      return;
    }
    final parent = tree.getParent(key);
    if (parent == null) {
      return;
    }
    final grandparent = tree.getParent(parent);
    final outIndex = tree.getIndexInParent(parent) + 1;
    tree.moveNode(key, grandparent, index: outIndex);
  }

  void _performMoveIntoPrevious() {
    final tree = _reorder.treeController;
    final key = widget.nodeKey;
    final idx = tree.getIndexInParent(key);
    if (idx <= 0) {
      return;
    }
    final parent = tree.getParent(key);
    final siblings = parent == null
        ? tree.liveRootKeys
        : tree.getLiveChildren(parent);
    final prev = siblings[idx - 1];
    tree.moveNode(key, prev, index: tree.liveChildCount(prev));
  }

  /// Walks up from this row to the first [ReorderRenderPort] ancestor —
  /// the tree sliver's render object. Interface-typed on purpose: the row
  /// needs the drag surface, not the concrete render class (and therefore
  /// carries no `TData` parameter at all).
  ReorderRenderPort<TKey>? _findRenderPort(BuildContext context) {
    ReorderRenderPort<TKey>? found;
    context.visitAncestorElements((element) {
      // Typed Object? so the `is` check promotes: ReorderRenderPort is an
      // interface unrelated to RenderObject, and Dart only promotes to
      // subtypes of the declared type.
      final Object? ro = element.findRenderObject();
      if (ro is ReorderRenderPort<TKey>) {
        found = ro;
        return false;
      }
      return true;
    });
    return found;
  }

  void _startDrag(BuildContext context, Offset globalPosition) {
    final renderPort = _findRenderPort(context);
    final scrollable = Scrollable.maybeOf(context);
    if (renderPort == null || scrollable == null) {
      return;
    }
    // A false return is a policy refusal (canReorder) or a not-yet-laid-out
    // tree — decline the gesture quietly. Genuine wiring misuse
    // (cross-controller) still throws and should surface; the ancestor
    // widget's build assert catches it earlier in debug builds.
    //
    // The depth hint is the default column mapping: floor(x /
    // indentPerDepth) — the resolver clamps it to the legal levels.
    // Disabled for non-positive indents (nothing to divide by).
    final indent = _indentPerDepth;
    final started = _reorder.startDrag(
      key: widget.nodeKey,
      renderPort: renderPort,
      scrollable: scrollable,
      pointerGlobal: globalPosition,
      depthForPointerX:
          indent > 0 ? (x) => (x / indent).floor() : null,
      makeRoom: true,
      settleFromRelease: _dragProxyEnabled,
    );
    if (!started) {
      return;
    }
    _isDraggingThisRow = true;
    _onDragStartCallback(widget.nodeKey, widget.child);
  }

  /// Whether this row still OWNS the controller's drag session. The local
  /// [_isDraggingThisRow] flag alone is not enough: an external
  /// `cancelDrag()` (or a second gesture silently replacing the session
  /// via `startDrag`) clears/replaces the controller session without
  /// resetting the row-local flag, and a later gesture callback from this
  /// row would then commit or cancel a DIFFERENT session. Clears the
  /// stale local flag when ownership is lost.
  bool _ownsSession() {
    if (!_isDraggingThisRow) return false;
    if (_reorder.draggedKey != widget.nodeKey) {
      _isDraggingThisRow = false;
      return false;
    }
    return true;
  }

  // End/cancel do NOT call the owner's drag-UI teardown directly: the
  // controller's notifyListeners (fired by endDrag/cancelDrag) drives
  // _onControllerChanged → _onDragEnd on the listening state. A second
  // direct call would be a redundant no-op setState, and teardown must
  // stay single-owner. (_ownsSession guarantees the cached controller
  // holds THIS row's session, and the owner state always listens to its
  // current controller.)

  void _updateDrag(Offset globalPosition) {
    if (!_ownsSession()) return;
    _reorder.updateDrag(globalPosition);
  }

  void _endDrag() {
    if (!_ownsSession()) return;
    _isDraggingThisRow = false;
    _reorder.endDrag();
  }

  void _cancelDrag() {
    if (!_ownsSession()) return;
    _isDraggingThisRow = false;
    _reorder.cancelDrag();
  }
}

/// Overlay entry rendering the floating drag preview.
///
/// Repositions on EVERY pointer move via
/// [TreeReorderController.pointerPosition] — the per-move channel that
/// exists precisely because the controller's [ChangeNotifier] channel is
/// coalesced to semantic target changes. Anchored at the grab point
/// ([TreeReorderController.dragProxyGeometry]) so the preview stays
/// "held" where the user picked the row up.
class _DragProxy<TKey> extends StatelessWidget {
  const _DragProxy({
    required this.reorderController,
    required this.proxyBuilder,
    required this.rowChildResolver,
    required this.scrollableFinder,
  });

  final TreeReorderController<TKey> reorderController;
  final Widget Function(BuildContext context, TKey key, Widget? rowChild)?
  proxyBuilder;
  final Widget? Function() rowChildResolver;
  final ScrollableState? Function() scrollableFinder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset?>(
      valueListenable: reorderController.pointerPosition,
      builder: (context, pointer, _) {
        if (pointer == null) return const SizedBox.shrink();
        final key = reorderController.draggedKey;
        if (key == null) return const SizedBox.shrink();
        final geometry = reorderController.dragProxyGeometry;
        if (geometry == null) return const SizedBox.shrink();
        final scrollable = scrollableFinder();
        if (scrollable == null) return const SizedBox.shrink();
        final viewport = scrollable.context.findRenderObject() as RenderBox?;
        if (viewport == null || !viewport.attached) {
          return const SizedBox.shrink();
        }

        final rowChild = rowChildResolver();
        Widget content;
        if (proxyBuilder != null) {
          content = proxyBuilder!(context, key, rowChild);
        } else if (rowChild != null) {
          content = Opacity(opacity: 0.9, child: rowChild);
        } else {
          return const SizedBox.shrink();
        }

        // Horizontal: span the viewport (the row's own width). Vertical:
        // the pointer minus the grab offset, in global space — pixel
        // distances survive the global mapping unscaled.
        final viewportGlobalLeft = viewport.localToGlobal(Offset.zero).dx;
        return Stack(
          children: [
            Positioned(
              left: viewportGlobalLeft,
              top: pointer.dy - geometry.grabDy,
              width: viewport.size.width,
              height: geometry.rowExtent > 0 ? geometry.rowExtent : null,
              child: IgnorePointer(child: content),
            ),
          ],
        );
      },
    );
  }
}
