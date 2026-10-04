/// The board's L4 widget: [Board], its `State`, and the two private
/// widgets that carry it down to `RenderBoardViewport`.
///
/// [Board] is a `StatefulWidget` that BUILDS a private
/// `TwoDimensionalScrollView` rather than being one: that class is a
/// `StatelessWidget` requiring a `delegate`
/// (`widgets/two_dimensional_scroll_view.dart:50`) while the board's
/// surface is stateful and takes a controller and builders. The two cannot
/// be one class; composition satisfies both.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter/gestures.dart';

import '_board_axis.dart';
import '_board_span.dart';
import 'board_background.dart';
import 'board_config.dart';
import 'board_controller.dart';
import 'board_drag_controller.dart';
import 'board_drag_handle.dart';
import 'board_views.dart';
import 'render_board_viewport.dart';

/// A two-axis scrolling cell lattice driven by a [BoardController].
///
/// The full fifteen-parameter surface; `background`, `drag`, `selection`,
/// `focusNode` and `autofocus` landed as optional named parameters with
/// their types, so every call site written against the cells-only
/// constructor compiles unchanged.
///
/// KEYBOARD. The board takes focus from a tap or a range press on a cell,
/// from Tab while [selection] is active (enabled, and a mode other than
/// `none`), and when a drag starts. While [selection] is active:
///
/// - an arrow key moves the selection one cell that way on the screen;
///   with Shift in range mode it moves the selection's focus corner and
///   keeps its anchor;
/// - Home and End go to the first and last cell of the row, and with
///   Control or Meta to the first and last cell of the board;
/// - Page Up and Page Down move by the scrolled rows in view, less one;
/// - with nothing selected, any of these selects the first scrolled cell
///   in view.
///
/// Each move scrolls the least that shows the new cell, through
/// [BoardController.revealCell]. Escape cancels a live drag. Every other
/// key, and these with nothing to do, reach the rest of the app.
class Board<TKey, TItem> extends StatefulWidget {
  /// Creates a board over [controller].
  ///
  /// [verticalDetails] through [primary], and [scrollCacheExtent] through
  /// [hitTestBehavior], are pass-throughs to `TwoDimensionalScrollView`
  /// (`widgets/two_dimensional_scroll_view.dart:57`), and [restorationId]
  /// to the `TwoDimensionalScrollable` it builds. [primary] is nullable
  /// with no default, matching the base
  /// (`widgets/two_dimensional_scroll_view.dart:59`), and
  /// [diagonalDragBehavior] departs from the framework default because a
  /// board scrolls in both axes at once by design.
  const Board({
    required this.controller,
    required this.cellBuilder,
    this.itemBuilder,
    this.background,
    this.drag,
    this.selection,
    this.addRepaintBoundaries = true,
    this.verticalDetails = const ScrollableDetails.vertical(),
    this.horizontalDetails = const ScrollableDetails.horizontal(),
    this.mainAxis = Axis.vertical,
    this.diagonalDragBehavior = DiagonalDragBehavior.free,
    this.clipBehavior = Clip.hardEdge,
    this.primary,
    this.focusNode,
    this.autofocus = false,
    this.scrollCacheExtent,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.restorationId,
    super.key,
  });

  /// The controller that owns the lattice and the items on it.
  final BoardController<TKey, TItem> controller;

  /// Builds one cell, or returns null to build nothing at that cell.
  final BoardCellBuilder<TKey, TItem> cellBuilder;

  /// Builds one item. With a null builder an item vicinity builds
  /// nothing, so a board that holds items renders none of them.
  final BoardItemBuilder<TKey, TItem>? itemBuilder;

  /// Painted behind every cell and item, at no render-child cost. Null
  /// paints nothing.
  final BoardBackgroundPainter? background;

  /// Drag-and-drop policy, or null for a board that does not drag.
  ///
  /// A new instance is APPLIED IN PLACE, so building it inline in a
  /// parent's `build` is fine: a live drag carries on under it, unless
  /// the new config sets [BoardDragConfig.enabled] false, or leaves a live
  /// resize without [BoardDragConfig.onItemResized] or without an edge
  /// policy that admits its edge, either of which cancels it; and no cell
  /// or item builder runs. Mounted items re-evaluate the policy
  /// once per new instance; the identical instance does not reach them.
  ///
  /// [BoardDragConfig.enabled] is the runtime switch, and toggling it
  /// keeps every item's `State`. Changing PRESENCE, null to non-null or
  /// back, re-creates each item's widgets under the board, since the drag
  /// wrapper around every item comes or goes with it.
  final BoardDragConfig<TKey>? drag;

  /// Selection gesture policy, or null. Changing it, its presence, its
  /// [BoardSelectionConfig.enabled] flag or its mode keeps every cell's
  /// and item's `State`.
  final BoardSelectionConfig? selection;

  /// Whether each child is wrapped in a `RepaintBoundary`.
  final bool addRepaintBoundaries;

  /// The vertical `Scrollable`'s configuration.
  final ScrollableDetails verticalDetails;

  /// The horizontal `Scrollable`'s configuration.
  ///
  /// The board reads no `Directionality`: its columns run the way this
  /// says, so a right-to-left board passes
  /// `ScrollableDetails.horizontal(reverse: true)`.
  final ScrollableDetails horizontalDetails;

  /// Which axis is the main one, which decides the framework's default
  /// child traversal order.
  final Axis mainAxis;

  /// Whether a drag gesture may move both axes at once.
  final DiagonalDragBehavior diagonalDragBehavior;

  /// How the viewport clips its children.
  final Clip clipBehavior;

  /// Whether the main axis attaches to the surrounding
  /// `PrimaryScrollController`.
  final bool? primary;

  /// How far past the viewport, on each axis, children are built and laid
  /// out ahead of scrolling into view. Null is the framework's default,
  /// 250 logical pixels.
  final ScrollCacheExtent? scrollCacheExtent;

  /// Whether a scroll drag starts at the pointer's first contact or once
  /// it has moved past the slop; the `Scrollable` parameter of the same
  /// name.
  final DragStartBehavior dragStartBehavior;

  /// Whether a scroll drag dismisses the keyboard; null takes the
  /// surrounding `ScrollConfiguration`'s.
  final ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior;

  /// How the scrollables behave during hit testing; the `Scrollable`
  /// parameter of the same name.
  final HitTestBehavior hitTestBehavior;

  /// The restoration id of the board's two scroll offsets, or null to
  /// restore neither. With an id, and restoration enabled above the board
  /// (`MaterialApp.restorationScopeId`, for instance), both offsets come
  /// back after the app is restarted, as a `ListView`'s does with the
  /// `Scrollable` parameter of the same name. The offsets are restored in
  /// pixels; the controller's items, selection and axes are the app's to
  /// restore.
  final String? restorationId;

  /// The node the board takes keyboard focus with, or null for one the
  /// board owns. A node given here stays the caller's to dispose. See the
  /// class doc for when the board takes focus and what it does with keys.
  ///
  /// The board CONFIGURES the node it is given, as any `Focus` does
  /// (`widgets/focus_scope.dart:566-574`): its `onKeyEvent`,
  /// `canRequestFocus` and `skipTraversal` are the board's. Listen to it
  /// or focus it; to handle keys of the app's own, wrap the board in a
  /// `Focus` of the app's instead, which the board's unhandled keys
  /// reach.
  final FocusNode? focusNode;

  /// Whether the board takes focus when it is first built, if nothing
  /// else in its scope already has.
  final bool autofocus;

  @override
  State<Board<TKey, TItem>> createState() {
    return _BoardState<TKey, TItem>();
  }
}

class _BoardState<TKey, TItem> extends State<Board<TKey, TItem>>
    with TickerProviderStateMixin {
  /// The delegate, CACHED rather than rebuilt per build, and rebuilt in
  /// [didUpdateWidget] exactly when one of its three inputs is not
  /// `identical` to the old one.
  ///
  /// Both halves are load-bearing. `TwoDimensionalChildBuilderDelegate.builder`
  /// is FINAL (`widgets/scroll_delegate.dart:1020`), so a board rebuilt
  /// with a new `cellBuilder` would keep rendering through the old one if
  /// the delegate were merely cached; and a FRESH instance per build is
  /// not free either, because the render object's `delegate` setter
  /// early-returns only on identity
  /// (`widgets/two_dimensional_viewport.dart:670`) and `shouldRebuild`
  /// returns true unconditionally (`widgets/scroll_delegate.dart:1131`),
  /// so every parent rebuild would rebuild every obtained child.
  late TwoDimensionalChildBuilderDelegate _delegate;

  BoardDragController<TKey>? _dragController;

  /// The two relays every mounted host listens to, stable for this
  /// state's life; the controller subscriptions feeding them move on a
  /// swap. See [_BoardScope].
  final _SelectionRelay _selectionRelay = _SelectionRelay();
  final _ItemDataRelay<TKey> _dataRelay = _ItemDataRelay<TKey>();

  /// The proxy's item host, ONE instance per move session. The pointer
  /// `ValueListenableBuilder` in [_buildDragProxy] receives it through
  /// its `child` slot and `updateChild` hands an identical instance back
  /// unchanged (`widgets/framework.dart:4014`), so the app's builder runs
  /// once at the lift and once per payload write to the dragged key,
  /// which the host's data relay delivers, never per pointer move.
  /// Rewritten when the dragged key changes and nulled at the session's
  /// end, so a session's content does not outlive it.
  Widget? _proxyHost;
  TKey? _proxyKey;

  /// The node the board owns when [Board.focusNode] is null: created on
  /// first use and disposed only with this state, whatever node the app
  /// supplies later, as `TextField` does
  /// (`material/text_field.dart:1154-1155`, `:1369`).
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode {
    return widget.focusNode ??
        (_ownedFocusNode ??= FocusNode(debugLabel: "Board"));
  }

  @override
  void initState() {
    super.initState();
    _delegate = _createDelegate();
    if (widget.drag != null) {
      _dragController = BoardDragController<TKey>(
        boardController: widget.controller,
        vsync: this,
        config: widget.drag!,
      )..addListener(_handleDragChanged);
    }
    _subscribe(widget.controller);
  }

  /// This state's two controller subscriptions, one per channel the hosts
  /// ride: the selection notifier and the item-data channel. Moved on a
  /// controller swap and removed in [dispose], so the controller's
  /// dispose assertion sees them gone.
  void _subscribe(BoardController<TKey, TItem> controller) {
    controller.selection.addListener(_handleSelectionChanged);
    controller.addItemDataListener(_handleItemData);
  }

  void _unsubscribe(BoardController<TKey, TItem> controller) {
    controller.selection.removeListener(_handleSelectionChanged);
    controller.removeItemDataListener(_handleItemData);
  }

  /// Forwards every selection CHANGE to the config's onChanged, when a
  /// config is present, and to the relay always; the ValueNotifier's
  /// equality suppression is what makes this once per change rather than
  /// once per write.
  void _handleSelectionChanged() {
    widget.selection?.onChanged(widget.controller.selection.value);
    _selectionRelay.fire();
  }

  void _handleItemData(TKey key) {
    _dataRelay.fire(key);
  }

  /// The dragged key the last [build] read, so a notification that did
  /// not move a session edge can be told from one that did.
  ///
  /// Compared rather than the session itself: the two things this build
  /// shows are the proxy's presence and its content, and both are a
  /// function of the key alone.
  TKey? _builtDraggedKey;

  /// The proxy shows and hides with the session; a plain setState is
  /// enough because the proxy is built in [build].
  ///
  /// GATED ON THE SESSION EDGE. The drag controller's own notifier fires
  /// per pointer move, and under a free snap every move re-resolves to a
  /// new span, so an unconditional rebuild here rebuilt this whole
  /// subtree at pointer rate for the length of a drag. Nothing in this
  /// build reads the target: the proxy follows the pointer through its
  /// own `ValueListenableBuilder` and reads its size inside that
  /// builder's callback.
  void _handleDragChanged() {
    final key = _dragController?.draggedKey;
    if (key == null) {
      // Cleared HERE and not only in build: an end notify and a start
      // notify on the same key inside one build window coalesce into one
      // build, in which the key compare in [_buildDragProxy] alone would
      // keep the ended session's host and the view it captured.
      _proxyHost = null;
      _proxyKey = null;
    }
    if (key == _builtDraggedKey) {
      return;
    }
    // The build this schedules is what updates [_builtDraggedKey], so
    // the coalescing case still builds once: the end differs from the
    // built key and schedules, the start compares equal to the
    // not-yet-updated built key and returns, and the scheduled build
    // sees the live session.
    if (mounted) {
      setState(() {});
    }
  }

  void _teardownDragController() {
    final controller = _dragController;
    if (controller == null) {
      return;
    }
    _dragController = null;
    controller
      ..removeListener(_handleDragChanged)
      // Cancel BEFORE dispose, so a live session tears down through the
      // ordinary path while everything it touches still exists.
      ..endDrag(cancel: true)
      ..dispose();
    // The listener that clears the proxy's cached host on a session's
    // end was removed above, before the cancel, so it is cleared here:
    // a later session on the same key would otherwise show this one's
    // content.
    _proxyHost = null;
    _proxyKey = null;
  }

  @override
  void didUpdateWidget(covariant Board<TKey, TItem> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The drag controller is REBUILT only when what it is bound to
    // changes: the board controller, which it holds as a final field, or
    // the config's PRESENCE. Any other new config instance is ASSIGNED to
    // the controller it already has, which keeps a live session (see
    // `BoardDragController.config`); a config built inline in a parent's
    // build is a new instance on every rebuild of that parent.
    //
    // A REPLACED drag controller must also replace the delegate: every
    // mounted `_BoardItemHost` captured the old controller in its widget
    // at build, and a delegate rebuild is the one route that rebuilds
    // those children (see the note above [_createDelegate]). Without it
    // a host presses on against a disposed controller. An assigned
    // config needs no such route: the hosts depend on
    // [_BoardDragScope], which notifies them.
    var rehost = false;
    if (!identical(widget.controller, oldWidget.controller) ||
        (widget.drag == null) != (oldWidget.drag == null)) {
      rehost = true;
      _teardownDragController();
      if (widget.drag != null) {
        _dragController = BoardDragController<TKey>(
          boardController: widget.controller,
          vsync: this,
          config: widget.drag!,
        )..addListener(_handleDragChanged);
      }
    } else if (widget.drag != null) {
      _dragController!.config = widget.drag!;
    }
    if (!identical(widget.controller, oldWidget.controller)) {
      _unsubscribe(oldWidget.controller);
      _subscribe(widget.controller);
    }
    if (rehost ||
        !identical(widget.cellBuilder, oldWidget.cellBuilder) ||
        !identical(widget.itemBuilder, oldWidget.itemBuilder) ||
        widget.addRepaintBoundaries != oldWidget.addRepaintBoundaries) {
      final previous = _delegate;
      _delegate = _createDelegate();
      // Safe even though the render object has not yet dropped its
      // listener: `ChangeNotifier.removeListener` "returns immediately if
      // [dispose] has been called" (`foundation/change_notifier.dart:330`),
      // and the setter's removal is exactly that call.
      previous.dispose();
    }
  }

  @override
  void dispose() {
    _teardownDragController();
    _unsubscribe(widget.controller);
    _delegate.dispose();
    // Children unmount before their parent's state disposes, so every
    // host has already dropped its relay listeners.
    _selectionRelay.dispose();
    _dataRelay.dispose();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  // Rebuild routes. A STRUCTURAL change rebuilds through the delegate,
  // which the render object requests. A selection change or a payload
  // write rebuilds only the hosts whose own answer changed, through the
  // two relays above, which is why this state and not the render object
  // subscribes to those channels; the render object keeps a plain
  // relayout on both, for re-measurement and for cells that built null
  // (see `RenderBoardViewport._handleSelectionChanged`). A `setState`
  // here reaches no child: a parent-driven rebuild goes through
  // `RenderObjectElement.update`, which calls the PRIVATE
  // `_performRebuild` (`widgets/framework.dart:6813`) and so bypasses
  // `_TwoDimensionalViewportElement.performRebuild`
  // (`widgets/two_dimensional_viewport.dart:277`), and the `delegate`
  // setter early-returns on identity
  // (`widgets/two_dimensional_viewport.dart:670`).

  TwoDimensionalChildBuilderDelegate _createDelegate() {
    return TwoDimensionalChildBuilderDelegate(
      builder: _buildChild,
      // The board wraps its children itself ([_wrapChild]): the
      // delegate's own `RepaintBoundary` carries no key
      // (`widgets/scroll_delegate.dart:1119-1121`), and an item's wrapper
      // must, for the viewport element to find the item's element by key
      // when its vicinity moves.
      addRepaintBoundaries: false,
      // `AutomaticKeepAlive` always wraps its child in a `KeepAlive`
      // (`widgets/automatic_keep_alive.dart:281`) whose `applyParentData`
      // writes `parentData.keepAlive` and dirties layout when it goes
      // false (`widgets/sliver.dart:1590`), which would make something
      // other than the render object a writer of that flag.
      addAutomaticKeepAlives: false,
      // maxXIndex and maxYIndex stay null so the board's own builder
      // decides what exists; the delegate returns null for a negative
      // index regardless (`widgets/scroll_delegate.dart:1105`).
    );
  }

  /// The delegate's builder: [_buildChildOrNull], reporting a null answer
  /// to the render object. On a delegate rebuild the base hands back the
  /// child already at a vicinity whose builder answered null, until the
  /// end of that layout (`RenderBoardViewport._liveChildFor`), and this
  /// report is how the render object tells that child from a live one.
  /// The context is the viewport element
  /// (`widgets/two_dimensional_viewport.dart:339`,
  /// `widgets/scroll_delegate.dart:1114`), active while it lays out.
  Widget? _buildChild(BuildContext context, ChildVicinity vicinity) {
    final built = _buildChildOrNull(context, vicinity);
    if (built == null) {
      final viewport = context.findRenderObject();
      if (viewport is RenderBoardViewport<TKey>) {
        viewport.noteBuiltNothing(vicinity);
      }
    }
    return built;
  }

  /// Builds one child. Cell vicinities are `(xIndex: col, yIndex: row)`;
  /// the ITEM band starts past every cell column and resolves through the
  /// controller's ordinal reads.
  Widget? _buildChildOrNull(BuildContext context, ChildVicinity vicinity) {
    final controller = widget.controller;
    final rowsConfig = controller.rows;
    final columnsConfig = controller.columns;
    final columnCount = columnsConfig.axis.trackCount;
    if (vicinity.xIndex >= columnCount) {
      // The ITEM band: xIndex carries the per-track ordinal past every
      // cell column, yIndex the primary start track. An empty slot builds
      // nothing, which is also what a stale vicinity resolves to after
      // the ordinals shift.
      final itemBuilder = widget.itemBuilder;
      if (itemBuilder == null) {
        return null;
      }
      final id = controller.itemIdAtOrdinal(
        vicinity.yIndex,
        vicinity.xIndex - columnCount,
      );
      if (id < 0) {
        return null;
      }
      final key = controller.keyOfId(id);
      if (key == null) {
        return null;
      }
      // Id-space reads throughout: an EXITING item still builds and
      // paints, and the key-space reads exclude it while it does.
      final item = controller.itemOfId(id);
      if (item == null) {
        return null;
      }
      // The builder runs ONCE here and the host adopts its output as
      // `initial`; the drag-host wrap happens in the host's build, from
      // the scope's drag controller.
      return _wrapChild(
        _BoardItemBuildHost<TKey, TItem>(
          id: id,
          itemKey: key,
          isProxy: false,
          initial: _itemContent<TKey, TItem>(
            context,
            itemBuilder,
            controller,
            id,
            key,
            item as TItem,
            isProxy: false,
          ),
        ),
        key: ValueKey<TKey>(key),
      );
    }
    if (vicinity.yIndex >= rowsConfig.axis.trackCount) {
      return null;
    }
    // The builder runs ONCE here to decide null-ness, so an empty cell
    // still costs no element; a non-null result is adopted by the host as
    // `initial`.
    final built = widget.cellBuilder(
      context,
      _cellView<TKey, TItem>(controller, vicinity.yIndex, vicinity.xIndex),
    );
    if (built == null) {
      return null;
    }
    return _wrapChild(
      _BoardCellHost<TKey, TItem>(
        row: vicinity.yIndex,
        col: vicinity.xIndex,
        initial: built,
      ),
    );
  }

  /// The top-level widget of one child, what the delegate returns: a
  /// `RepaintBoundary` when [Board.addRepaintBoundaries] asks for one, as
  /// the delegate's own wrapping did, carrying [key].
  ///
  /// An ITEM passes its own key, and the viewport element retrieves a
  /// keyed child's element by that key before it tries the vicinity
  /// (`widgets/two_dimensional_viewport.dart:357-369`). An item's
  /// vicinity moves whenever its rank on its start track does, when it
  /// moves to another primary track, and when the column count changes;
  /// with the key its element, and every `State` under it, moves with it.
  /// The item key and not its id: a key names one item at a time (a key
  /// re-added while its exit runs comes back as that same item,
  /// `BoardController._resurrect`), where an id is recycled, and would
  /// hand a dead item's element to another.
  Widget _wrapChild(Widget child, {Key? key}) {
    if (widget.addRepaintBoundaries) {
      return RepaintBoundary(key: key, child: child);
    }
    if (key != null) {
      return KeyedSubtree(key: key, child: child);
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    final Widget board = _BoardScrollView<TKey, TItem>(
      controller: widget.controller,
      background: widget.background,
      selection: widget.selection,
      delegate: _delegate,
      mainAxis: widget.mainAxis,
      verticalDetails: widget.verticalDetails,
      horizontalDetails: widget.horizontalDetails,
      diagonalDragBehavior: widget.diagonalDragBehavior,
      clipBehavior: widget.clipBehavior,
      primary: widget.primary,
      scrollCacheExtent: widget.scrollCacheExtent,
      dragStartBehavior: widget.dragStartBehavior,
      keyboardDismissBehavior: widget.keyboardDismissBehavior,
      hitTestBehavior: widget.hitTestBehavior,
      restorationId: widget.restorationId,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      dragController: _dragController,
    );
    final drag = _dragController;
    // The one write site: what this build showed is what the next
    // notification compares against.
    _builtDraggedKey = drag?.draggedKey;
    // The scope wraps EVERYTHING this build returns, the Stack included,
    // because the proxy host is the Stack's second child and must find
    // it too.
    //
    // The Stack is UNCONDITIONAL, its proxy slot a shrink box without a
    // drag config: were it present only with one, toggling `drag` would
    // change this build's root widget type and re-create the scroll view
    // under it, scroll positions and every mounted child included.
    return _BoardScope<TKey, TItem>(
      controller: widget.controller,
      cellBuilder: widget.cellBuilder,
      itemBuilder: widget.itemBuilder,
      dragController: drag,
      selectionRelay: _selectionRelay,
      dataRelay: _dataRelay,
      child: _BoardDragScope<TKey>(
        config: drag?.config,
        verticalDirection: widget.verticalDetails.direction,
        horizontalDirection: widget.horizontalDetails.direction,
        focusNode: _focusNode,
        // The SESSION cursor, over the whole board while a drag runs, so
        // it holds where the pointer leaves the strip or the item; `defer`
        // otherwise. Unconditional, as the Stack is: only its cursor
        // changes, at the session's edges, when this state rebuilds.
        child: MouseRegion(
          cursor: _sessionCursor(drag?.draggedKind),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              board,
              if (drag == null)
                const SizedBox.shrink()
              else
                _buildDragProxy(drag),
            ],
          ),
        ),
      ),
    );
  }

  /// `grabbing` for a move, the resized axis's resize cursor for a
  /// resize, and `defer` with no session.
  static MouseCursor _sessionCursor(BoardDragKind? kind) {
    switch (kind) {
      case null:
        return MouseCursor.defer;
      case BoardDragKind.move:
        return SystemMouseCursors.grabbing;
      case BoardDragKind.resizeRowStart:
      case BoardDragKind.resizeRowEnd:
        return SystemMouseCursors.resizeUpDown;
      case BoardDragKind.resizeColStart:
      case BoardDragKind.resizeColEnd:
        return SystemMouseCursors.resizeLeftRight;
    }
  }

  /// The drag proxy: a separate overlay above the board, following the
  /// pointer, sized to the dragged item's rect. The item's in-place
  /// widget stays live with `isDragging` true; the proxy is the moved
  /// visual.
  ///
  /// Gated on the SESSION's kind, never on the target's: a canDropAt
  /// refusal nulls `currentTarget` while the session stays live, and the
  /// moved visual must keep following the pointer across that cell.
  Widget _buildDragProxy(BoardDragController<TKey> drag) {
    final key = drag.draggedKey;
    if (key == null || drag.draggedKind != BoardDragKind.move) {
      return const SizedBox.shrink();
    }
    if (_proxyHost == null || _proxyKey != key) {
      // The one builder call per session; see [_proxyHost].
      _proxyKey = key;
      _proxyHost = _buildProxyContent(key);
    }
    return ValueListenableBuilder<Offset?>(
      valueListenable: drag.pointerPosition,
      child: _proxyHost,
      builder: (context, pointer, proxyHost) {
        final topLeft = drag.proxyTopLeft;
        if (pointer == null || topLeft == null) {
          return const SizedBox.shrink();
        }
        final rect = drag.proxySize;
        Widget content = IgnorePointer(
          child: SizedBox(
            width: rect?.width,
            height: rect?.height,
            child: _BoardOpacity(
              opacity: drag.config.dragProxyOpacity,
              child: proxyHost!,
            ),
          ),
        );
        final proxyBuilder = widget.drag?.dragProxyBuilder;
        if (proxyBuilder != null) {
          content = proxyBuilder(context, key, content);
        }
        return Positioned(
          left: topLeft.dx,
          top: topLeft.dy,
          child: content,
        );
      },
    );
  }

  Widget _buildProxyContent(TKey key) {
    final controller = widget.controller;
    final itemBuilder = widget.itemBuilder;
    final id = controller.idOfKey(key);
    if (itemBuilder == null || id < 0) {
      return const SizedBox.shrink();
    }
    final item = controller.itemOfId(id);
    if (item == null) {
      return const SizedBox.shrink();
    }
    return _BoardItemBuildHost<TKey, TItem>(
      id: id,
      itemKey: key,
      isProxy: true,
      initial: _itemContent<TKey, TItem>(
        context,
        itemBuilder,
        controller,
        id,
        key,
        item as TItem,
        isProxy: true,
      ),
    );
  }
}

/// The view a cell builder is handed, computed from the controller's
/// CURRENT configs on every call so a swap-driven rebuild reads the new
/// ones.
BoardCellView<TKey, TItem> _cellView<TKey, TItem>(
  BoardController<TKey, TItem> controller,
  int row,
  int col,
) {
  return BoardCellView<TKey, TItem>(
    row: row,
    col: col,
    isFrozen:
        controller.rows.isFrozenTrack(row) ||
        controller.columns.isFrozenTrack(col),
    controller: controller,
  );
}

/// One item's builder output, for the lattice or, under [isProxy], the
/// drag proxy. The ONE site that constructs a `BoardItemView`; the
/// delegate and the item host both call it. Id-space reads throughout:
/// an EXITING item still builds and paints, and the key-space reads
/// exclude it while it does.
Widget _itemContent<TKey, TItem>(
  BuildContext context,
  BoardItemBuilder<TKey, TItem> builder,
  BoardController<TKey, TItem> controller,
  int id,
  TKey key,
  TItem item, {
  required bool isProxy,
}) {
  return builder(
    context,
    BoardItemView<TKey, TItem>(
      key: key,
      item: item,
      span: controller.spanOfId(id),
      lane: controller.laneOfId(id),
      laneCount: controller.laneCountOfId(id),
      laneSpan: controller.laneSpanOfId(id),
      isDragging: isProxy || controller.isDraggingId(id),
      presence: controller.presenceOfId(id),
      controller: controller,
    ),
  );
}

/// Whether a notify issued NOW would land inside the build or layout
/// phase. A host answers a relay with `setState`, and the framework
/// permits a mark during a build only on a descendant of the element
/// currently building (`widgets/framework.dart:5350`), so a write issued
/// from a builder during a host's SELF-rebuild would mark a sibling and
/// throw; the two relays defer such a notify to one post-frame callback.
/// Same discriminator as the animation coordinator's coalesced dispatch.
bool _inBuildOrLayoutPhase() {
  return SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks;
}

/// Fan-out of the controller's selection notifier. Carries no value: a
/// host reads `controller.selection.value` at notify time.
class _SelectionRelay extends ChangeNotifier {
  bool _pending = false;
  bool _disposed = false;

  void fire() {
    if (_inBuildOrLayoutPhase()) {
      if (_pending) {
        return;
      }
      _pending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _pending = false;
        if (!_disposed) {
          notifyListeners();
        }
      });
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Fan-out of the controller's item-data channel, carrying the key. A
/// host resolves the id and the geometry through the controller at
/// notify time, so a write that raced a removal resolves to no id and is
/// dropped rather than read against a recycled one.
class _ItemDataRelay<TKey> extends ChangeNotifier {
  /// The key of the write being delivered; meaningful inside a listener.
  TKey? lastKey;

  final Set<TKey> _pending = <TKey>{};
  bool _disposed = false;

  void fire(TKey key) {
    if (_inBuildOrLayoutPhase()) {
      final schedule = _pending.isEmpty;
      _pending.add(key);
      if (schedule) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          final keys = List<TKey>.of(_pending);
          _pending.clear();
          if (_disposed) {
            return;
          }
          for (final pendingKey in keys) {
            lastKey = pendingKey;
            notifyListeners();
          }
        });
      }
      return;
    }
    lastKey = key;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// What every host reads: the current controller and builders, the drag
/// controller, and the two relays. It NEVER notifies: every value here
/// changes only when `_BoardState.didUpdateWidget` replaces the delegate
/// (a builder change, a controller swap or a drag-controller
/// replacement), and a delegate rebuild already hands every host a new
/// `initial` and rebuilds it, so a notification would invoke each
/// builder twice. Hosts read it with `getInheritedWidgetOfExactType`,
/// which registers no dependency.
class _BoardScope<TKey, TItem> extends InheritedWidget {
  const _BoardScope({
    required this.controller,
    required this.cellBuilder,
    required this.itemBuilder,
    required this.dragController,
    required this.selectionRelay,
    required this.dataRelay,
    required super.child,
  });

  final BoardController<TKey, TItem> controller;
  final BoardCellBuilder<TKey, TItem> cellBuilder;
  final BoardItemBuilder<TKey, TItem>? itemBuilder;
  final BoardDragController<TKey>? dragController;
  final _SelectionRelay selectionRelay;
  final _ItemDataRelay<TKey> dataRelay;

  static _BoardScope<TKey, TItem> of<TKey, TItem>(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<_BoardScope<TKey, TItem>>();
    assert(scope != null, "a board host was built outside its Board");
    return scope!;
  }

  @override
  bool updateShouldNotify(_BoardScope<TKey, TItem> oldWidget) {
    return false;
  }
}

/// What every mounted `_BoardItemHost` builds from beyond its own widget:
/// the drag config and the two axis directions. The one channel that
/// tells those hosts any of the three changed.
///
/// Separate from [_BoardScope], which never notifies: a new config is
/// ASSIGNED to the live drag controller rather than rebuilding it (see
/// `_BoardState.didUpdateWidget`), and a direction change reaches only the
/// viewport's render object, so no delegate rebuild reaches the hosts,
/// and this scope does instead. Only item hosts depend on it, so a notify
/// rebuilds their wrappers and nothing else: each passes the item's
/// content through as an identical `child`, so the app's builder does not
/// run.
///
/// The config is compared by IDENTITY. A comparison of the fields a host
/// reads would skip a rebuild that is needed: a tear-off predicate reading
/// mutable app state compares equal across the parent rebuild that
/// changed its answer. An app that hands the board the identical instance
/// pays nothing.
class _BoardDragScope<TKey> extends InheritedWidget {
  const _BoardDragScope({
    required this.config,
    required this.verticalDirection,
    required this.horizontalDirection,
    required this.focusNode,
    required super.child,
  });

  /// The board's focus node, which a host focuses when its drag session
  /// starts, so that Escape reaches the board. Read at that moment and
  /// never in a build, so it takes no part in [updateShouldNotify].
  final FocusNode focusNode;

  /// Null exactly when the board has no drag config.
  final BoardDragConfig<TKey>? config;

  /// The board's vertical axis direction, `down` or `up`.
  final AxisDirection verticalDirection;

  /// The board's horizontal axis direction, `right` or `left`.
  final AxisDirection horizontalDirection;

  /// The scope, registering [context] as a dependent.
  static _BoardDragScope<TKey> of<TKey>(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_BoardDragScope<TKey>>();
    assert(scope != null, "a board item host was built outside its Board");
    return scope!;
  }

  @override
  bool updateShouldNotify(_BoardDragScope<TKey> oldWidget) {
    return !identical(config, oldWidget.config) ||
        verticalDirection != oldWidget.verticalDirection ||
        horizontalDirection != oldWidget.horizontalDirection;
  }
}

/// Hosts one CELL's builder output. Shows [initial], the delegate's own
/// builder call, until a relay makes THIS cell's answer change, after
/// which it calls the builder itself; a new [initial] from a delegate
/// rebuild is adopted in [State.didUpdateWidget]. The builder runs only
/// when a relay handler asked for it, never on a parent-driven rebuild.
class _BoardCellHost<TKey, TItem> extends StatefulWidget {
  const _BoardCellHost({
    required this.row,
    required this.col,
    required this.initial,
  });

  final int row;
  final int col;
  final Widget initial;

  @override
  State<_BoardCellHost<TKey, TItem>> createState() {
    return _BoardCellHostState<TKey, TItem>();
  }
}

class _BoardCellHostState<TKey, TItem>
    extends State<_BoardCellHost<TKey, TItem>> {
  _BoardScope<TKey, TItem>? _scope;
  Widget? _built;
  bool _builderRequested = false;
  bool _wasSelected = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scope == null) {
      final scope = _BoardScope.of<TKey, TItem>(context);
      _scope = scope;
      scope.selectionRelay.addListener(_handleSelection);
      scope.dataRelay.addListener(_handleData);
    }
  }

  @override
  void didUpdateWidget(covariant _BoardCellHost<TKey, TItem> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.initial, oldWidget.initial)) {
      _built = null;
    }
  }

  @override
  void dispose() {
    final scope = _scope;
    if (scope != null) {
      scope.selectionRelay.removeListener(_handleSelection);
      scope.dataRelay.removeListener(_handleData);
    }
    super.dispose();
  }

  void _requestBuilder() {
    _builderRequested = true;
    setState(() {});
  }

  void _handleSelection() {
    final scope = _scope!;
    if (scope.controller.isSelected(widget.row, widget.col) != _wasSelected) {
      _requestBuilder();
    }
  }

  void _handleData() {
    final scope = _scope!;
    final key = scope.dataRelay.lastKey as TKey;
    final id = scope.controller.idOfKey(key);
    if (id < 0) {
      return;
    }
    if (scope.controller.idCoversCell(id, widget.row, widget.col)) {
      _requestBuilder();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = _BoardScope.of<TKey, TItem>(context);
    _scope = scope;
    _wasSelected = scope.controller.isSelected(widget.row, widget.col);
    if (_builderRequested) {
      _builderRequested = false;
      _built =
          scope.cellBuilder(
            context,
            _cellView<TKey, TItem>(scope.controller, widget.row, widget.col),
          ) ??
          const SizedBox.shrink();
    }
    // The surface is CONSTRUCTED HERE, fresh on every build of this
    // host, which is the whole of its mechanism: a new instance makes
    // the framework call `updateRenderObject`, and that call is what
    // tells the board this cell's content may have changed size. See
    // [_BoardCellSurface].
    return _BoardCellSurface(child: _built ?? widget.initial);
  }
}

/// Wraps one cell's content so the board learns when it was rebuilt.
///
/// A `StatelessWidget` would not do: the signal is not the widget being
/// built, it is the RENDER OBJECT being updated, which is the one event
/// that reaches the render tree on every host rebuild and on no other
/// occasion. `updateRenderObject` runs whenever the new widget is not
/// identical to the old (`widgets/framework.dart:6837`), and this host
/// builds a new instance every time, so the two coincide exactly.
///
/// It carries no fields on purpose. A field would tempt a `==` that
/// suppressed the update, which is the one thing this must never do.
class _BoardCellSurface extends SingleChildRenderObjectWidget {
  const _BoardCellSurface({required Widget super.child});

  @override
  RenderBoardCellSurface createRenderObject(BuildContext context) {
    // A first build needs no poke: the vicinity is newly obtained, so
    // its cache is null and the measure step measures it anyway.
    return RenderBoardCellSurface();
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBoardCellSurface renderObject,
  ) {
    renderObject.requestRemeasure();
  }
}

/// Hosts one ITEM's builder output, in the lattice or, under [isProxy],
/// in the drag proxy, with the same `initial` protocol as
/// [_BoardCellHost]. A lattice host wraps the content in [_BoardItemHost]
/// when the scope carries a drag controller; that host's `State` survives
/// a rebuild of this wrapper. The lattice child above both is keyed by
/// the item's key (`_BoardState._wrapChild`), so an element hosts one
/// item for its whole life, wherever that item's vicinity moves.
class _BoardItemBuildHost<TKey, TItem> extends StatefulWidget {
  const _BoardItemBuildHost({
    required this.id,
    required this.itemKey,
    required this.isProxy,
    required this.initial,
  });

  final int id;
  final TKey itemKey;
  final bool isProxy;
  final Widget initial;

  @override
  State<_BoardItemBuildHost<TKey, TItem>> createState() {
    return _BoardItemBuildHostState<TKey, TItem>();
  }
}

class _BoardItemBuildHostState<TKey, TItem>
    extends State<_BoardItemBuildHost<TKey, TItem>> {
  _BoardScope<TKey, TItem>? _scope;
  Widget? _built;
  bool _builderRequested = false;

  /// The selection's intersection with the item's CELL range, the integer
  /// rectangle `[floor(start), ceil(end))` per axis, or null when they do
  /// not meet. A selection change rebuilds the item exactly when this
  /// changes.
  ({int rowStart, int rowEnd, int colStart, int colEnd})? _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scope == null) {
      final scope = _BoardScope.of<TKey, TItem>(context);
      _scope = scope;
      scope.selectionRelay.addListener(_handleSelection);
      scope.dataRelay.addListener(_handleData);
    }
  }

  @override
  void didUpdateWidget(covariant _BoardItemBuildHost<TKey, TItem> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.initial, oldWidget.initial)) {
      _built = null;
    }
  }

  @override
  void dispose() {
    final scope = _scope;
    if (scope != null) {
      scope.selectionRelay.removeListener(_handleSelection);
      scope.dataRelay.removeListener(_handleData);
    }
    super.dispose();
  }

  ({int rowStart, int rowEnd, int colStart, int colEnd})? _intersection(
    _BoardScope<TKey, TItem> scope,
  ) {
    final controller = scope.controller;
    final selection = controller.selection.value;
    if (selection.isEmpty || controller.keyOfId(widget.id) != widget.itemKey) {
      return null;
    }
    final span = controller.spanOfId(widget.id);
    final rowStart = math.max(
      trackIndexOf(span.startTrackOn(Axis.vertical)),
      selection.rowStart,
    );
    final rowEnd = math.min(
      trackEndIndexOf(span.endTrackOn(Axis.vertical)),
      selection.rowEnd,
    );
    final colStart = math.max(
      trackIndexOf(span.startTrackOn(Axis.horizontal)),
      selection.colStart,
    );
    final colEnd = math.min(
      trackEndIndexOf(span.endTrackOn(Axis.horizontal)),
      selection.colEnd,
    );
    if (rowStart >= rowEnd || colStart >= colEnd) {
      return null;
    }
    return (
      rowStart: rowStart,
      rowEnd: rowEnd,
      colStart: colStart,
      colEnd: colEnd,
    );
  }

  void _requestBuilder() {
    _builderRequested = true;
    setState(() {});
  }

  void _handleSelection() {
    if (_intersection(_scope!) != _selected) {
      _requestBuilder();
    }
  }

  void _handleData() {
    final scope = _scope!;
    // The second test drops a write that raced an id recycle.
    if (scope.dataRelay.lastKey == widget.itemKey &&
        scope.controller.keyOfId(widget.id) == widget.itemKey) {
      _requestBuilder();
    }
  }

  Widget _rebuild(BuildContext context, _BoardScope<TKey, TItem> scope) {
    final controller = scope.controller;
    final builder = scope.itemBuilder;
    if (builder == null || controller.keyOfId(widget.id) != widget.itemKey) {
      // The id was released between the write and the build; a
      // structural rebuild is already scheduled.
      return const SizedBox.shrink();
    }
    final item = controller.itemOfId(widget.id);
    if (item == null) {
      return const SizedBox.shrink();
    }
    return _itemContent<TKey, TItem>(
      context,
      builder,
      controller,
      widget.id,
      widget.itemKey,
      item as TItem,
      isProxy: widget.isProxy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = _BoardScope.of<TKey, TItem>(context);
    _scope = scope;
    _selected = _intersection(scope);
    if (_builderRequested) {
      _builderRequested = false;
      _built = _rebuild(context, scope);
    }
    final content = _built ?? widget.initial;
    if (widget.isProxy) {
      return content;
    }
    final drag = scope.dragController;
    if (drag == null) {
      return content;
    }
    return _BoardItemHost<TKey>(
      itemKey: widget.itemKey,
      dragController: drag,
      spanAxisVertical: scope.controller.primaryAxis == Axis.horizontal,
      child: content,
    );
  }
}

/// Hosts one built item for the drag layer: publishes the scope whose
/// tear-off closes over this `State`'s typed key, owns the recognizer a
/// handle arms, wraps the default handles, and carries the deferred
/// deactivate BACKSTOP for a session whose item leaves the tree while the
/// render object's pin cannot help.
class _BoardItemHost<TKey> extends StatefulWidget {
  const _BoardItemHost({
    required this.itemKey,
    required this.dragController,
    required this.spanAxisVertical,
    required this.child,
  });

  final TKey itemKey;
  final BoardDragController<TKey> dragController;
  final bool spanAxisVertical;
  final Widget child;

  @override
  State<_BoardItemHost<TKey>> createState() {
    return _BoardItemHostState<TKey>();
  }
}

class _BoardItemHostState<TKey> extends State<_BoardItemHost<TKey>> {
  MultiDragGestureRecognizer? _recognizer;
  bool _ownsSession = false;

  /// The key the owned session STARTED with, which both ownership checks
  /// below follow. The lattice child is keyed by the item, so this
  /// element's `widget.itemKey` does not change under it; the record is
  /// the session's all the same, which is what the checks are about, and
  /// costs a field. [_armRecognizer] captures the same key one step
  /// earlier, when the pointer goes down.
  TKey? _ownedKey;

  /// The session's pointer, tracked by DELTA from where the drag started.
  /// Inside a scrollable the handle's recognizer shares the arena with
  /// the scrollable's own and is accepted on the first move past the
  /// slop, and the multi-drag recognizer reports that accepting move as a
  /// delta against the INITIAL position (`gestures/multidrag.dart:139-153`),
  /// so an update's position alone would drop it. The framework's drag
  /// avatar accumulates the same way (`widgets/drag_target.dart:873-876`).
  Offset _dragPosition = Offset.zero;

  /// Whether [config] lets this host's item start a drag: the lift-time
  /// half of the drag policy, `enabled` and `canDrag`.
  bool _canDragUnder(BoardDragConfig<TKey> config) {
    if (!config.enabled) {
      return false;
    }
    return askCanDrag(config, widget.itemKey);
  }

  void _armRecognizer(
    PointerDownEvent event,
    MultiDragGestureRecognizer recognizer,
    BoardResizeEdges edge,
    Axis? axis,
  ) {
    // A pointer landing while this host's own session runs is IGNORED:
    // a second finger on the item being dragged, or on one of its
    // handles, must not end the drag the first is still making, and
    // disposing the recognizer would orphan the Drag it handed out,
    // which a multi-drag recognizer's disposal never ends.
    if (_ownsSession &&
        widget.dragController.draggedKey == _ownedKey) {
      return;
    }
    // The replacement leg: a second handle pressed while the first's
    // recognizer is still ARMED, its delay not yet run out, disposes the
    // first, so the later press wins and no orphaned recognizer outlives
    // its pointer.
    _recognizer?.dispose();
    // THE KEY IS CAPTURED HERE, with the edge and the axis: the three
    // things this pointer's gesture is about, fixed when it goes down.
    //
    // Not re-read at `onStart`, which runs a long-press delay or a touch
    // slop later: the gesture is about the item that was pressed. The
    // lattice child is keyed by the item, so a rank shift in that window
    // moves this element with its item rather than handing it another,
    // and a re-read would find the same key; the capture states the rule
    // rather than depending on that. The same rule [_ownedKey] states for
    // the session, one step earlier.
    final armedKey = widget.itemKey;
    _recognizer = recognizer
      ..onStart = (position) {
        return _beginDrag(position, edge, axis, armedKey);
      }
      ..addPointer(event);
  }

  Drag? _beginDrag(
    Offset position,
    BoardResizeEdges edge,
    Axis? axis,
    TKey key,
  ) {
    final viewport = context
        .findAncestorRenderObjectOfType<RenderBoardViewport<TKey>>();
    if (viewport == null) {
      return null;
    }
    // A key whose item left during the window is refused by `startDrag`'s
    // own liveness check, which drops the gesture rather than starting a
    // session on whatever replaced it.
    final started = widget.dragController.startDrag(
      key: key,
      renderPort: viewport,
      pointerGlobal: position,
      edge: edge,
      axis: axis,
    );
    if (!started) {
      // The null-on-refusal return: no Drag exists, so nothing can
      // forward an end into a session that does not exist.
      return null;
    }
    _ownsSession = true;
    _ownedKey = key;
    _dragPosition = position;
    // The board takes focus with the session, so Escape reaches its key
    // handler and is consumed there; see `_SelectionLayer`.
    context
        .getInheritedWidgetOfExactType<_BoardDragScope<TKey>>()
        ?.focusNode
        .requestFocus();
    return _ItemDrag<TKey>(this);
  }

  /// Whether the live session is still the one this host started: the
  /// same rule [_armRecognizer] and [deactivate] apply. A span mutator on
  /// the dragged key cancels the session through the controller's hook
  /// without telling this host, and a later session another host starts
  /// must not be driven or committed by this host's pointer. On a
  /// mismatch ownership is dropped here, so the stale pointer's
  /// remaining events are inert.
  bool _stillOwnsSession() {
    if (!_ownsSession) {
      return false;
    }
    if (widget.dragController.draggedKey == _ownedKey) {
      return true;
    }
    _ownsSession = false;
    _ownedKey = null;
    return false;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _dragPosition += details.delta;
    if (!_stillOwnsSession()) {
      return;
    }
    widget.dragController.updateDrag(_dragPosition);
  }

  void _handleDragEnd({required bool cancel}) {
    if (!_stillOwnsSession()) {
      return;
    }
    _ownsSession = false;
    _ownedKey = null;
    widget.dragController.endDrag(cancel: cancel);
  }

  @override
  void deactivate() {
    if (_ownsSession) {
      // The SESSION BACKSTOP: this `State` may be leaving the tree with
      // a live drag it owns. Flip ownership synchronously; cancel
      // DEFERRED one frame, because a synchronous cancel here runs
      // inside the build scope and its notifications throw. If the
      // element was merely moved and reactivates, ownership was still
      // handed off: the deferred cancel runs regardless, which is the
      // one-owner rule rather than a leak.
      _ownsSession = false;
      final controller = widget.dragController;
      final key = _ownedKey;
      _ownedKey = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (key != null && controller.draggedKey == key) {
          controller.endDrag(cancel: true);
        }
      });
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _recognizer?.dispose();
    _recognizer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Read through the scope, which registers the dependency that
    // rebuilds this host when a new config instance is assigned or an
    // axis direction changes. The config is null only for the frame a
    // board drops its drag config: the scope has already notified and the
    // delegate rebuild that removes this host runs in the layout after
    // this build, so the controller's own last config serves until then.
    final scope = _BoardDragScope.of<TKey>(context);
    final config = scope.config ?? widget.dragController.config;
    final reverseVertical = scope.verticalDirection == AxisDirection.up;
    final reverseHorizontal = scope.horizontalDirection == AxisDirection.left;
    // The drag policy is asked ONCE per build and threaded to the zones,
    // the handle scope and the semantics actions below, rather than read
    // again in each: a policy is app code on a per-item build path, and
    // two reads of a stateful predicate can disagree within one build.
    final canDrag = _canDragUnder(config);
    final gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    // The left-behind dim. Driven by the drag controller's narrow
    // session-edge channel and NOT by `BoardItemView.isDragging`: the
    // lattice item is built by the viewport's delegate, and a session
    // edge fires no structural notification, so the flag that build
    // captured is stale for the whole session.
    //
    // The item passes through as `child`, so a session edge rebuilds
    // this wrapper and nothing under it: `updateChild` returns the
    // existing element without updating it when the new widget equals
    // the old (`widgets/framework.dart:4014`), and an identical instance
    // does.
    //
    // Compares `widget.itemKey` rather than the session's captured
    // `_ownedKey`, which is the opposite of what the two ownership
    // checks below do: this decides what THIS element paints, which is
    // the item its widget names.
    Widget child = ValueListenableBuilder<TKey?>(
      valueListenable: widget.dragController.movedItem,
      child: widget.child,
      builder: (context, moved, child) {
        return _BoardOpacity(
          opacity: moved == widget.itemKey ? config.draggedItemOpacity : 1.0,
          child: child!,
        );
      },
    );
    // The DEFAULT HANDLES, one render object classifying each press: an
    // edge band admitted by `resizeEdges` (the span axis) or
    // `primaryResizeEdges` (the primary axis) starts a resize on that
    // edge, anywhere else a delayed move, delayed so touch scrolling that
    // starts on an item still works. Built whatever the config says, and
    // inert when default handles are off or the item may not drag: its
    // presence never varies, so no toggle re-creates the item under it.
    final defaults = config.buildDefaultDragHandles;
    child = _BoardHandleZones(
      active: defaults && canDrag,
      reverseVertical: reverseVertical,
      reverseHorizontal: reverseHorizontal,
      primaryAxis: widget.spanAxisVertical ? Axis.horizontal : Axis.vertical,
      primaryEdges: defaults
          ? config.primaryResizeEdges
          : BoardResizeEdges.none,
      spanEdges: defaults ? config.resizeEdges : BoardResizeEdges.none,
      bandCap: config.resizeHandleExtent,
      onPointerDown: (event, edge, axis) {
        final MultiDragGestureRecognizer recognizer =
            edge == BoardResizeEdges.none
            ? DelayedMultiDragGestureRecognizer(delay: config.dragStartDelay)
            : ImmediateMultiDragGestureRecognizer();
        recognizer.gestureSettings = gestureSettings;
        _armRecognizer(event, recognizer, edge, axis);
      },
      child: child,
    );
    child = _wrapSemantics(
      child,
      config,
      canDrag: canDrag,
      reverseVertical: reverseVertical,
      reverseHorizontal: reverseHorizontal,
    );
    return BoardItemDragScope(
      canDrag: canDrag,
      startDrag: _armRecognizer,
      child: child,
    );
  }

  /// The built-in semantics move actions, one track per activation, plus
  /// whatever the config's builder adds or replaces.
  ///
  /// Gated by the SAME drag policy the pointer path applies: [canDrag]
  /// is the build's one answer to `enabled` and `canDrag`, and each
  /// destination passes [_semanticsMoveSpan], which applies the lattice
  /// bounds and `canDropAt`. A refused item advertises nothing and its
  /// builder is not consulted; an admitted item advertises exactly the
  /// destinations the predicate admits, and the builder may add to or
  /// replace that set.
  ///
  /// The WRAPPER is unconditional and only its payload varies, so the
  /// item's widget shape is the same across every policy flip. The
  /// payload is null, never an empty map: `RenderObject` installs the map
  /// whenever it is non-null and the semantics config's setter raises the
  /// `customAction` bit unconditionally, so an empty map would advertise
  /// a node that claims custom actions and offers none.
  Widget _wrapSemantics(
    Widget child,
    BoardDragConfig<TKey> config, {
    required bool canDrag,
    required bool reverseVertical,
    required bool reverseHorizontal,
  }) {
    final key = widget.itemKey;
    Map<CustomSemanticsAction, VoidCallback>? actions;
    if (canDrag) {
      final builtIn = <CustomSemanticsAction, VoidCallback>{};
      void addMove(String label, int rowDelta, int colDelta) {
        // Advertised only for a destination admitted NOW, and re-checked
        // at activation: a policy that changed its answer in between
        // degrades the activation to a no-op rather than a wrong move.
        if (_semanticsMoveSpan(key, rowDelta, colDelta) == null) {
          return;
        }
        builtIn[CustomSemanticsAction(label: label)] = () {
          final span = _semanticsMoveSpan(key, rowDelta, colDelta);
          if (span == null) {
            return;
          }
          // The LIVE config's report: a config assigned since this
          // build is the one the app expects to hear from.
          widget.dragController.config.onItemMoved(key, span);
        };
      }

      // Each label names a direction ON THE SCREEN. A reversed axis
      // paints higher tracks toward the top or the left, so there the
      // content delta that moves the item that way is the opposite one.
      //
      // The labels are the framework's own, which its reorderable list
      // reads for the same four actions (`widgets/reorderable_list.dart:1175`)
      // and every supported locale translates; the English defaults when
      // no `Localizations` is in scope, so a board outside an app builds.
      final strings =
          Localizations.of<WidgetsLocalizations>(
            context,
            WidgetsLocalizations,
          ) ??
          const DefaultWidgetsLocalizations();
      final up = reverseVertical ? 1 : -1;
      final left = reverseHorizontal ? 1 : -1;
      addMove(strings.reorderItemUp, up, 0);
      addMove(strings.reorderItemDown, -up, 0);
      addMove(strings.reorderItemLeft, 0, left);
      addMove(strings.reorderItemRight, 0, -left);
      final builder = config.semanticsActionsBuilder;
      final built = builder == null ? builtIn : builder(key, builtIn);
      if (built.isNotEmpty) {
        actions = built;
      }
    }
    return Semantics(
      container: true,
      customSemanticsActions: actions,
      child: child,
    );
  }

  /// The span moving [key] by one track per non-zero delta would give it,
  /// or null when the drag policy refuses it: the item is not live, the
  /// moved span leaves the lattice, or `canDropAt` declines or throws.
  /// The ONE predicate behind both the advertised set and an activation.
  ///
  /// The bounds test reads the EXACT trailing endpoint, as the drop
  /// resolver's clamp does, so a fractional span is kept inside the
  /// lattice; the start is tested before the span is built, because
  /// `BoardSpan` asserts a non-negative start.
  BoardSpan? _semanticsMoveSpan(TKey key, int rowDelta, int colDelta) {
    final controller = widget.dragController.boardController;
    final span = controller.spanOf(key);
    if (span == null) {
      return null;
    }
    final rowStart = span.rowStart + rowDelta;
    final colStart = span.colStart + colDelta;
    if (rowStart < 0 || colStart < 0) {
      return null;
    }
    final moved = span.copyWith(rowStart: rowStart, colStart: colStart);
    if (moved.endTrackOn(Axis.vertical) > controller.rows.axis.trackCount ||
        moved.endTrackOn(Axis.horizontal) >
            controller.columns.axis.trackCount) {
      return null;
    }
    if (askCanDropAt(widget.dragController.config, key, moved) != true) {
      return null;
    }
    return moved;
  }
}

/// The `Drag` a session hands the gesture layer: updates and ends route
/// to the drag controller through the owning host.
class _ItemDrag<TKey> extends Drag {
  _ItemDrag(this._host);

  final _BoardItemHostState<TKey> _host;

  @override
  void update(DragUpdateDetails details) {
    _host._handleDragUpdate(details);
  }

  @override
  void end(DragEndDetails details) {
    _host._handleDragEnd(cancel: false);
  }

  @override
  void cancel() {
    _host._handleDragEnd(cancel: true);
  }
}

/// The `TwoDimensionalScrollView` [Board] composes: it owns the two
/// `Scrollable`s and defers the viewport to [buildViewport].
class _BoardScrollView<TKey, TItem> extends TwoDimensionalScrollView {
  const _BoardScrollView({
    required this.controller,
    required this.background,
    required this.selection,
    required this.focusNode,
    required this.autofocus,
    required this.dragController,
    required super.delegate,
    required super.mainAxis,
    required super.verticalDetails,
    required super.horizontalDetails,
    required super.diagonalDragBehavior,
    required super.clipBehavior,
    required super.primary,
    required super.scrollCacheExtent,
    required super.dragStartBehavior,
    required super.keyboardDismissBehavior,
    required super.hitTestBehavior,
    required this.restorationId,
  });

  final BoardController<TKey, TItem> controller;

  final BoardBackgroundPainter? background;

  final String? restorationId;

  final BoardSelectionConfig? selection;

  final FocusNode focusNode;
  final bool autofocus;
  final BoardDragController<TKey>? dragController;

  /// The base's build (`widgets/two_dimensional_scroll_view.dart:165-236`)
  /// with [restorationId] handed to the scrollable, which the base never
  /// does: its `TwoDimensionalScrollable` is built without one (:197-210),
  /// and that scrollable keys the `RestorationScope` over both of its
  /// `Scrollable`s by it (`widgets/scrollable.dart:2095-2096`), a null id
  /// turning restoration OFF below the scope (`widgets/restoration.dart:59`),
  /// so no scope an app puts around the board reaches the offsets.
  /// Everything else is the base's, in its order: the direction asserts,
  /// the main axis's primary controller, and the keyboard dismissal.
  @override
  Widget build(BuildContext context) {
    assert(
      axisDirectionToAxis(verticalDetails.direction) == Axis.vertical,
      "Board.verticalDetails are not Axis.vertical.",
    );
    assert(
      axisDirectionToAxis(horizontalDetails.direction) == Axis.horizontal,
      "Board.horizontalDetails are not Axis.horizontal.",
    );
    var mainAxisDetails = switch (mainAxis) {
      Axis.vertical => verticalDetails,
      Axis.horizontal => horizontalDetails,
    };
    final effectivePrimary =
        primary ??
        mainAxisDetails.controller == null &&
            PrimaryScrollController.shouldInherit(context, mainAxis);
    if (effectivePrimary) {
      assert(
        mainAxisDetails.controller == null,
        "Board.primary was explicitly set to true, but a ScrollController "
        "was provided in the ScrollableDetails of the Board's main axis.",
      );
      mainAxisDetails = mainAxisDetails.copyWith(
        controller: PrimaryScrollController.of(context),
      );
    }
    final scrollable = TwoDimensionalScrollable(
      horizontalDetails: switch (mainAxis) {
        Axis.horizontal => mainAxisDetails,
        Axis.vertical => horizontalDetails,
      },
      verticalDetails: switch (mainAxis) {
        Axis.vertical => mainAxisDetails,
        Axis.horizontal => verticalDetails,
      },
      diagonalDragBehavior: diagonalDragBehavior,
      viewportBuilder: buildViewport,
      dragStartBehavior: dragStartBehavior,
      hitTestBehavior: hitTestBehavior,
      restorationId: restorationId,
    );
    // Further descendant scroll views do not inherit the same primary
    // controller.
    final Widget scrollableResult = effectivePrimary
        ? PrimaryScrollController.none(child: scrollable)
        : scrollable;
    final effectiveKeyboardDismissBehavior =
        keyboardDismissBehavior ??
        ScrollConfiguration.of(context).getKeyboardDismissBehavior(context);
    if (effectiveKeyboardDismissBehavior ==
        ScrollViewKeyboardDismissBehavior.onDrag) {
      return NotificationListener<ScrollUpdateNotification>(
        child: scrollableResult,
        onNotification: (notification) {
          final currentScope = FocusScope.of(context);
          if (notification.dragDetails != null &&
              !currentScope.hasPrimaryFocus &&
              currentScope.hasFocus) {
            FocusManager.instance.primaryFocus?.unfocus();
          }
          return false;
        },
      );
    }
    return scrollableResult;
  }

  @override
  Widget buildViewport(
    BuildContext context,
    ViewportOffset verticalOffset,
    ViewportOffset horizontalOffset,
  ) {
    final Widget viewport = _BoardViewport<TKey, TItem>(
      controller: controller,
      background: background,
      delegate: delegate,
      mainAxis: mainAxis,
      clipBehavior: clipBehavior,
      scrollCacheExtent: scrollCacheExtent,
      verticalOffset: verticalOffset,
      verticalAxisDirection: verticalDetails.direction,
      horizontalOffset: horizontalOffset,
      horizontalAxisDirection: horizontalDetails.direction,
    );
    // UNCONDITIONAL: the layer installs no recognizer for a null, disabled
    // or `none` config, and stays in the tree regardless. Returned bare in
    // those cases, the viewport would change parent type with every toggle
    // of the selection config and be re-created, render object and every
    // mounted child with it.
    return _SelectionLayer<TKey, TItem>(
      controller: controller,
      config: selection,
      focusNode: focusNode,
      autofocus: autofocus,
      dragController: dragController,
      verticalDirection: verticalDetails.direction,
      horizontalDirection: horizontalDetails.direction,
      child: viewport,
    );
  }
}

/// The selection gesture path, wrapped INSIDE the scrollable and around
/// the viewport, which decides the arena outcome by hit-test order: an
/// item handle's recognizer is deeper and enters the arena first, so it
/// beats this layer on items; this layer's immediate recognizer beats
/// the scrollable's slop-based pan everywhere else, so RANGE mode trades
/// touch scrolling on cell surfaces for selection; CELL mode installs
/// only a tap and contends with nothing.
class _SelectionLayer<TKey, TItem> extends StatefulWidget {
  const _SelectionLayer({
    required this.controller,
    required this.config,
    required this.focusNode,
    required this.autofocus,
    required this.dragController,
    required this.verticalDirection,
    required this.horizontalDirection,
    required this.child,
  });

  final BoardController<TKey, TItem> controller;

  /// The policy, or null for a board without one. Null, disabled and
  /// `none` all install no recognizer.
  final BoardSelectionConfig? config;

  /// The board's focus node, which this layer's `Focus` takes focus
  /// with; see [Board]'s keyboard doc.
  final FocusNode focusNode;
  final bool autofocus;

  /// The board's drag controller, or null without a drag config: Escape
  /// cancels its live session.
  final BoardDragController<TKey>? dragController;

  /// The two axis directions, for the arrows' screen directions.
  final AxisDirection verticalDirection;
  final AxisDirection horizontalDirection;

  final Widget child;

  @override
  State<_SelectionLayer<TKey, TItem>> createState() {
    return _SelectionLayerState<TKey, TItem>();
  }
}

class _SelectionLayerState<TKey, TItem>
    extends State<_SelectionLayer<TKey, TItem>>
    with TickerProviderStateMixin {
  ({int row, int col})? _anchor;

  /// The running range gesture's edge autoscroll, or null between
  /// gestures; see [_beginRange].
  BoardAutoScroller? _autoScroller;

  /// The scroll positions the running range listens to, so content that
  /// scrolls under a still pointer extends the range as it arrives.
  ScrollPosition? _verticalSubscription;
  ScrollPosition? _horizontalSubscription;

  /// The range gesture's pointer, tracked by DELTA from where it began,
  /// for the reason `_BoardItemHostState._dragPosition` gives: the
  /// recognizer's first update reports the accepting move as a delta
  /// against the initial position, so reading the position alone would
  /// leave the focus on the anchor cell for that move.
  Offset _dragPosition = Offset.zero;

  RenderBoardViewport<TKey>? _viewport() {
    RenderObject? render = context.findRenderObject();
    while (render != null) {
      if (render is RenderBoardViewport<TKey>) {
        return render;
      }
      if (render is RenderObjectWithChildMixin<RenderObject>) {
        render = render.child;
      } else {
        return null;
      }
    }
    return null;
  }

  /// The cell a selection gesture resolves at [global]. Under a
  /// FRACTIONAL snap the coordinate is quantized before the containment
  /// floor, which is what snaps the selection's edges to the grid;
  /// `track` and `free` use plain containment, because rounding a
  /// mid-cell touch to the nearest EDGE would select the neighbour. Each
  /// axis resolves among the cells of the region the point is over, so a
  /// point over a frozen band selects a cell of that band and one between
  /// the bands a scrolled cell that shows, or any cell where none of them
  /// shows.
  ///
  /// [onLattice] asks for a cell that PAINTS under the point, and answers
  /// null anywhere else: a tap or a range's first press on empty space
  /// past the lattice selects nothing. A range drag's extension passes
  /// false and takes the clamped sample, so a drag past the lattice's
  /// edge selects up to it.
  ({int row, int col})? _cellAt(Offset global, {required bool onLattice}) {
    final viewport = _viewport();
    if (viewport == null) {
      return null;
    }
    final local = viewport.globalToPaintLocal(global);
    if (onLattice && viewport.cellAt(local) == null) {
      return null;
    }
    final sample = viewport.trackSampleAt(local);
    if (sample == null) {
      return null;
    }
    // A gesture only starts under a live config, but one already running
    // can outlive a rebuild that removed it; such a gesture resolves as
    // the default snap does.
    final snap = widget.config?.snap ?? const BoardSnap.track();
    final rows = widget.controller.rows.axis.trackCount;
    final cols = widget.controller.columns.axis.trackCount;
    if (rows == 0 || cols == 0) {
      return null;
    }
    int cellOn(BoardAxisSample axis) {
      final path = regionPathOf(axis, extent: 1.0, quantum: 1.0);
      final coordinate = coordinateIn(path, axis);
      final snapped = snap.mode == BoardSnapMode.fraction
          ? snap.quantize(coordinate)
          : coordinate;
      return clampToWindow(snapped.floorToDouble(), path.window).toInt();
    }

    return (row: cellOn(sample.row), col: cellOn(sample.col));
  }

  Drag? _beginRange(Offset global) {
    final anchor = _cellAt(global, onLattice: true);
    if (anchor == null) {
      return null;
    }
    widget.focusNode.requestFocus();
    _anchor = anchor;
    _dragPosition = global;
    widget.controller.setSelection(
      BoardSelection(anchor: anchor, focus: anchor),
    );
    _startRangeScroll();
    return _SelectionDrag<TKey, TItem>(this);
  }

  /// Starts the range's edge autoscroll: the drag layer's scroller, with
  /// this state as its ticker provider and the selection config's zone
  /// and speed, evaluated from the pointer at the start and on every
  /// update. A range still running from an earlier gesture is released
  /// first.
  void _startRangeScroll() {
    _endRangeScroll();
    final viewport = _viewport();
    final config = widget.config;
    if (viewport == null || config == null) {
      return;
    }
    _autoScroller = BoardAutoScroller(
      vsync: this,
      port: viewport,
      edgeZone: config.autoScrollEdgeZone,
      maxVelocity: config.autoScrollMaxVelocity,
      onTick: _repointRangeScroll,
    );
    _repointRangeScroll();
    _evaluateRangeScroll();
  }

  void _evaluateRangeScroll() {
    final scroller = _autoScroller;
    final viewport = _viewport();
    if (scroller == null || viewport == null) {
      return;
    }
    scroller.evaluate(viewport.globalToPaintLocal(_dragPosition));
  }

  /// Listens to the viewport's current positions, moving a listener off a
  /// position the scrollable has swapped out, as the drag controller's
  /// subscriptions do.
  void _repointRangeScroll() {
    final viewport = _viewport();
    final vertical = viewport?.verticalPosition;
    if (!identical(vertical, _verticalSubscription)) {
      _verticalSubscription?.removeListener(_handleRangeScroll);
      _verticalSubscription = vertical?..addListener(_handleRangeScroll);
    }
    final horizontal = viewport?.horizontalPosition;
    if (!identical(horizontal, _horizontalSubscription)) {
      _horizontalSubscription?.removeListener(_handleRangeScroll);
      _horizontalSubscription = horizontal
        ?..addListener(_handleRangeScroll);
    }
  }

  /// Content moved under the pointer: the range reaches the cell now
  /// under it.
  void _handleRangeScroll() {
    if (_anchor != null) {
      _extendTo(_dragPosition);
    }
  }

  void _endRangeScroll() {
    _autoScroller?.dispose();
    _autoScroller = null;
    _verticalSubscription?.removeListener(_handleRangeScroll);
    _horizontalSubscription?.removeListener(_handleRangeScroll);
    _verticalSubscription = null;
    _horizontalSubscription = null;
  }

  @override
  void didUpdateWidget(covariant _SelectionLayer<TKey, TItem> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final config = widget.config;
    if (config == null ||
        !config.enabled ||
        config.mode != BoardSelectionMode.range) {
      // The range's recognizer goes with the config that armed it, and
      // disposing a multi-drag recognizer disposes its pointer states
      // without ending the drag it handed out
      // (`gestures/multidrag.dart:189-197`, `:318-327`): nothing else
      // would end this range, or stop its autoscroll.
      _anchor = null;
      _endRangeScroll();
      return;
    }
    // A config that still selects ranges keeps the gesture; the running
    // range takes its new zone and speed.
    _autoScroller
      ?..edgeZone = config.autoScrollEdgeZone
      ..maxVelocity = config.autoScrollMaxVelocity;
  }

  @override
  void dispose() {
    _endRangeScroll();
    super.dispose();
  }

  void _extendTo(Offset global) {
    final anchor = _anchor;
    if (anchor == null) {
      return;
    }
    final focus = _cellAt(global, onLattice: false);
    if (focus == null) {
      return;
    }
    widget.controller.setSelection(
      BoardSelection(anchor: anchor, focus: focus),
    );
  }

  void _tapAt(Offset global) {
    final cell = _cellAt(global, onLattice: true);
    if (cell == null) {
      return;
    }
    widget.focusNode.requestFocus();
    widget.controller.setSelection(
      BoardSelection(anchor: cell, focus: cell),
    );
  }

  /// The pointers that start a range at once. Not touch, and not
  /// `unknown`, the kind VoiceAccess scrolls a scrollable with
  /// (`widgets/scroll_configuration.dart:34-36`): both start a range after
  /// a long press, so their plain drags scroll.
  static const Set<PointerDeviceKind> _precisePointers = <PointerDeviceKind>{
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  };

  /// Whether selection is ACTIVE: a config, enabled, in a mode that
  /// selects.
  bool get _selecting {
    final config = widget.config;
    return config != null &&
        config.enabled &&
        config.mode != BoardSelectionMode.none;
  }

  /// The board's keys; see [Board]'s keyboard doc. Handled only when the
  /// key has something to act on, so everything else reaches the app.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      final drag = widget.dragController;
      if (event is KeyDownEvent && drag != null && drag.draggedKey != null) {
        drag.endDrag(cancel: true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        !_selecting) {
      return KeyEventResult.ignored;
    }
    final rows = widget.controller.rows.axis.trackCount;
    final cols = widget.controller.columns.axis.trackCount;
    if (rows == 0 || cols == 0 || !_isSelectionKey(key)) {
      return KeyEventResult.ignored;
    }
    ({int row, int col}) clamp(({int row, int col}) cell) {
      return (row: cell.row.clamp(0, rows - 1), col: cell.col.clamp(0, cols - 1));
    }

    final selection = widget.controller.selection.value;
    final ({int row, int col}) anchor;
    final ({int row, int col}) focus;
    if (selection.isEmpty) {
      focus = clamp(_firstCellInView());
      anchor = focus;
    } else {
      focus = clamp(_keyTarget(key, clamp(selection.focus!), rows, cols));
      final keyboard = HardwareKeyboard.instance;
      final extend =
          keyboard.isShiftPressed &&
          widget.config!.mode == BoardSelectionMode.range;
      anchor = extend ? clamp(selection.anchor!) : focus;
    }
    widget.controller.setSelection(
      BoardSelection(anchor: anchor, focus: focus),
    );
    widget.controller.revealCell(focus.row, focus.col);
    return KeyEventResult.handled;
  }

  static bool _isSelectionKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.end ||
        key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.pageDown;
  }

  /// Where [key] takes the cell [from], unclamped. The arrows and pages
  /// name SCREEN directions: a reversed axis paints higher tracks toward
  /// the top or the left, so there the content delta that goes that way
  /// is the opposite one, as the semantics move actions have it.
  ({int row, int col}) _keyTarget(
    LogicalKeyboardKey key,
    ({int row, int col}) from,
    int rows,
    int cols,
  ) {
    final up = widget.verticalDirection == AxisDirection.up ? 1 : -1;
    final left = widget.horizontalDirection == AxisDirection.left ? 1 : -1;
    final keyboard = HardwareKeyboard.instance;
    final toCorner = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (key == LogicalKeyboardKey.arrowUp) {
      return (row: from.row + up, col: from.col);
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return (row: from.row - up, col: from.col);
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return (row: from.row, col: from.col + left);
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return (row: from.row, col: from.col - left);
    }
    if (key == LogicalKeyboardKey.home) {
      return (row: toCorner ? 0 : from.row, col: 0);
    }
    if (key == LogicalKeyboardKey.end) {
      return (row: toCorner ? rows - 1 : from.row, col: cols - 1);
    }
    final page = _page();
    if (key == LogicalKeyboardKey.pageUp) {
      return (row: from.row + up * page, col: from.col);
    }
    return (row: from.row - up * page, col: from.col);
  }

  /// A page: the scrolled rows in view, less one, so the row at the
  /// edge stays in view across the move; at least one.
  int _page() {
    final viewport = _viewport();
    if (viewport == null) {
      return 1;
    }
    final span = viewport.lastVisibleRow - viewport.firstVisibleRow;
    return span < 1 ? 1 : span;
  }

  /// The first scrolled cell in view, which a key selects when nothing
  /// is selected; `(0, 0)` when no scrolled track shows on an axis.
  ({int row, int col}) _firstCellInView() {
    final viewport = _viewport();
    if (viewport == null) {
      return (row: 0, col: 0);
    }
    final row = viewport.lastVisibleRow >= viewport.firstVisibleRow
        ? viewport.firstVisibleRow
        : 0;
    final col = viewport.lastVisibleCol >= viewport.firstVisibleCol
        ? viewport.firstVisibleCol
        : 0;
    return (row: row, col: col);
  }

  @override
  Widget build(BuildContext context) {
    final gestures = <Type, GestureRecognizerFactory>{};
    final config = widget.config;
    final mode = config == null || !config.enabled
        ? BoardSelectionMode.none
        : config.mode;
    // The detector is built in every mode, `none` with an empty map, and
    // its `excludeFromSemantics` is left at its default in all of them:
    // either one varying would change this widget's shape and re-create
    // the viewport under it.
    if (mode == BoardSelectionMode.range) {
      // SPLIT BY POINTER KIND, as Flutter's reorderable lists split their
      // drag-start listeners: a precise pointer starts a range the moment
      // it moves, and TOUCH only after a long press. An immediate
      // recognizer on touch races the scrollable's own drag for the same
      // move and wins, so a touch board could not be scrolled by its
      // cells; the delayed one rejects a pointer that moves before its
      // delay (`gestures/multidrag.dart:541-544`), leaving the drag to the
      // scrollable. `supportedDevices` keeps each pointer to one of them.
      gestures[ImmediateMultiDragGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<
            ImmediateMultiDragGestureRecognizer
          >(
            () {
              return ImmediateMultiDragGestureRecognizer(
                supportedDevices: _precisePointers,
              );
            },
            (recognizer) {
              recognizer.onStart = _beginRange;
            },
          );
      gestures[DelayedMultiDragGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<
            DelayedMultiDragGestureRecognizer
          >(
            () {
              return DelayedMultiDragGestureRecognizer(
                supportedDevices: const <PointerDeviceKind>{
                  PointerDeviceKind.touch,
                  PointerDeviceKind.unknown,
                },
              );
            },
            (recognizer) {
              recognizer.onStart = _beginRange;
            },
          );
    } else if (mode == BoardSelectionMode.cell) {
      gestures[TapGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () {
              return TapGestureRecognizer();
            },
            (recognizer) {
              recognizer.onTapUp = (details) {
                _tapAt(details.globalPosition);
              };
            },
          );
    }
    // The FOCUS is unconditional, as the detector is, so no toggle of
    // the selection or drag config changes the widget shape above the
    // viewport. It can take focus while selection is active or a drag
    // config is present, and Tab stops on it only while selection is
    // active: a board that drags but does not select takes focus when a
    // drag starts, for Escape, and otherwise stays out of the traversal.
    final selecting = _selecting;
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: selecting || widget.dragController != null,
      skipTraversal: !selecting,
      onKeyEvent: _handleKey,
      child: RawGestureDetector(
        gestures: gestures,
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      ),
    );
  }
}

class _SelectionDrag<TKey, TItem> extends Drag {
  _SelectionDrag(this._layer);

  final _SelectionLayerState<TKey, TItem> _layer;

  @override
  void update(DragUpdateDetails details) {
    _layer._dragPosition += details.delta;
    _layer._extendTo(_layer._dragPosition);
    _layer._evaluateRangeScroll();
  }

  @override
  void end(DragEndDetails details) {
    _layer._anchor = null;
    _layer._endRangeScroll();
  }

  @override
  void cancel() {
    _layer._anchor = null;
    _layer._endRangeScroll();
  }
}

/// The `TwoDimensionalViewport` that creates and updates
/// [RenderBoardViewport]. Its `updateRenderObject` is the single re-bind
/// route to the render object's controller setter.
class _BoardViewport<TKey, TItem> extends TwoDimensionalViewport {
  const _BoardViewport({
    required this.controller,
    required this.background,
    required super.delegate,
    required super.mainAxis,
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required super.clipBehavior,
    required super.scrollCacheExtent,
  });

  final BoardController<TKey, TItem> controller;

  final BoardBackgroundPainter? background;

  @override
  RenderBoardViewport<TKey> createRenderObject(BuildContext context) {
    // The constructor forwards the base's seven required parameters only
    // (its doc says why), so the cache extent is set as `updateRenderObject`
    // sets it.
    return RenderBoardViewport<TKey>(
      controller: controller,
      background: background,
      horizontalOffset: horizontalOffset,
      horizontalAxisDirection: horizontalAxisDirection,
      verticalOffset: verticalOffset,
      verticalAxisDirection: verticalAxisDirection,
      delegate: delegate,
      mainAxis: mainAxis,
      childManager: context as TwoDimensionalChildManager,
      clipBehavior: clipBehavior,
    )..scrollCacheExtent = _resolvedCacheExtent;
  }

  /// The cache extent with null resolved to the framework's default HERE:
  /// the render object's setter compares the value it is given with the
  /// one it holds BEFORE resolving null
  /// (`widgets/two_dimensional_viewport.dart:762-774`), so a null would
  /// mark layout on every update of this widget.
  ScrollCacheExtent get _resolvedCacheExtent {
    return scrollCacheExtent ??
        const ScrollCacheExtent.pixels(
          RenderAbstractViewport.defaultCacheExtent,
        );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBoardViewport<TKey> renderObject,
  ) {
    renderObject
      ..controller = controller
      ..background = background
      ..horizontalOffset = horizontalOffset
      ..horizontalAxisDirection = horizontalAxisDirection
      ..verticalOffset = verticalOffset
      ..verticalAxisDirection = verticalAxisDirection
      ..delegate = delegate
      ..mainAxis = mainAxis
      ..clipBehavior = clipBehavior
      ..scrollCacheExtent = _resolvedCacheExtent;
  }
}

/// An opacity wrapper that costs nothing at 1.0.
///
/// `Opacity` cannot serve. `RenderOpacity.alwaysNeedsCompositing` is
/// `child != null && _alpha > 0` and its `isRepaintBoundary` is that same
/// getter (`rendering/proxy_box.dart:884-887`), so a wrapper left in the
/// tree at full strength still composites a layer and installs a repaint
/// boundary, per item, on top of the one the delegate already adds. This
/// one pushes a layer only while it actually fades.
///
/// Costing nothing at rest is what lets the item host keep the wrapper in
/// the tree unconditionally, and an unconditional wrapper is the point: a
/// widget inserted above the item at the lift and removed at the drop
/// would re-inflate the item's subtree twice per session and drop its
/// `State` both times.
class _BoardOpacity extends SingleChildRenderObjectWidget {
  const _BoardOpacity({required this.opacity, required Widget super.child});

  final double opacity;

  @override
  _RenderBoardOpacity createRenderObject(BuildContext context) {
    return _RenderBoardOpacity(opacity);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBoardOpacity renderObject,
  ) {
    renderObject.opacity = opacity;
  }
}

class _RenderBoardOpacity extends RenderProxyBox {
  _RenderBoardOpacity(double opacity)
    : assert(opacity >= 0.0 && opacity <= 1.0),
      _opacity = opacity,
      _alpha = Color.getAlphaFromOpacity(opacity);

  double _opacity;
  int _alpha;

  final LayerHandle<OpacityLayer> _layerHandle = LayerHandle<OpacityLayer>();

  set opacity(double value) {
    assert(value >= 0.0 && value <= 1.0);
    if (_opacity == value) {
      return;
    }
    // The compositing bit moves with the alpha, so it is read BEFORE the
    // write and compared after, which is the order `RenderOpacity`'s own
    // setter uses (`rendering/proxy_box.dart:901-916`).
    final wasCompositing = alwaysNeedsCompositing;
    _opacity = value;
    _alpha = Color.getAlphaFromOpacity(value);
    if (wasCompositing != alwaysNeedsCompositing) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  /// True exactly when [paint] pushes the layer: at 255 it paints the
  /// child straight through, and at 0 it paints nothing at all.
  @override
  bool get alwaysNeedsCompositing {
    return child != null && _alpha > 0 && _alpha < 255;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // At 0 this paints nothing and still hit-tests and still reports
    // semantics, which is `RenderProxyBox`'s behaviour and not
    // `RenderOpacity`'s: an item configured invisible for the length of
    // its own drag is pinned and excluded from `itemAt` anyway.
    if (child == null || _alpha == 0) {
      _layerHandle.layer = null;
      return;
    }
    if (_alpha == 255) {
      _layerHandle.layer = null;
      super.paint(context, offset);
      return;
    }
    // `pushOpacity` carries the offset on the LAYER and calls the painter
    // at zero (`rendering/object.dart:836-848`), which is what
    // `RenderProxyBox.paint` expects to be handed.
    _layerHandle.layer = context.pushOpacity(
      offset,
      _alpha,
      super.paint,
      oldLayer: _layerHandle.layer,
    );
  }

  @override
  void dispose() {
    _layerHandle.layer = null;
    super.dispose();
  }
}

/// The default drag handles of one item: a MOVE zone and up to four
/// resize EDGE BANDS, in one render object.
///
/// Replaces a move wrap plus an opaque strip per admitted edge stacked
/// over the item. One object keeps the item's widget shape identical
/// whatever the policy says, costs one render object where the move wrap
/// cost one and the strips added a stack plus three per edge, and sizes
/// each band from the item it sits on.
class _BoardHandleZones extends SingleChildRenderObjectWidget {
  const _BoardHandleZones({
    required this.active,
    required this.reverseVertical,
    required this.reverseHorizontal,
    required this.primaryAxis,
    required this.primaryEdges,
    required this.spanEdges,
    required this.bandCap,
    required this.onPointerDown,
    required Widget super.child,
  });

  /// False makes the zones a plain proxy: no band hit-tests and no press
  /// is classified.
  final bool active;

  /// Whether the vertical axis runs `up`, which paints an item's
  /// content-leading edge at its bottom and its trailing edge at its top.
  final bool reverseVertical;

  /// Whether the horizontal axis runs `left`, the same for its right and
  /// left edges.
  final bool reverseHorizontal;

  /// The board's primary axis; the span axis is the other one.
  final Axis primaryAxis;

  /// The edges admitted on the primary axis, `primaryResizeEdges`.
  final BoardResizeEdges primaryEdges;

  /// The edges admitted on the span axis, `resizeEdges`.
  final BoardResizeEdges spanEdges;

  /// The deepest a band reaches into the item, `resizeHandleExtent`.
  final double bandCap;

  /// Called for a press on the item: `none` and a null axis for the move
  /// zone, otherwise the band's edge and its axis.
  final void Function(PointerDownEvent event, BoardResizeEdges edge, Axis? axis)
  onPointerDown;

  @override
  _RenderBoardHandleZones createRenderObject(BuildContext context) {
    return _RenderBoardHandleZones(
      active: active,
      reverseVertical: reverseVertical,
      reverseHorizontal: reverseHorizontal,
      primaryAxis: primaryAxis,
      primaryEdges: primaryEdges,
      spanEdges: spanEdges,
      bandCap: bandCap,
      onPointerDown: onPointerDown,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBoardHandleZones renderObject,
  ) {
    renderObject
      ..active = active
      ..reverseVertical = reverseVertical
      ..reverseHorizontal = reverseHorizontal
      ..primaryAxis = primaryAxis
      ..primaryEdges = primaryEdges
      ..spanEdges = spanEdges
      ..bandCap = bandCap
      ..onPointerDown = onPointerDown;
  }
}

/// A cursor carried by a hit-test entry: a `MouseTrackerAnnotation` the
/// mouse tracker reads, and a `HitTestTarget` so it can be an entry's
/// target, which receives its pointer's events and ignores them.
class _BandCursor extends MouseTrackerAnnotation implements HitTestTarget {
  const _BandCursor(MouseCursor cursor) : super(cursor: cursor);

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {}
}

class _RenderBoardHandleZones extends RenderProxyBox {
  _RenderBoardHandleZones({
    required this.active,
    required this.reverseVertical,
    required this.reverseHorizontal,
    required this.primaryAxis,
    required this.primaryEdges,
    required this.spanEdges,
    required this.bandCap,
    required this.onPointerDown,
  });

  // Plain fields: none of them changes what paints or where, and each is
  // read afresh by the next hit test or press.
  bool active;
  bool reverseVertical;
  bool reverseHorizontal;
  Axis primaryAxis;
  BoardResizeEdges primaryEdges;
  BoardResizeEdges spanEdges;

  /// The deepest a band reaches into the item, in logical pixels.
  double bandCap;
  void Function(PointerDownEvent event, BoardResizeEdges edge, Axis? axis)
  onPointerDown;

  /// A band's depth on an axis whose extent is [extent]: [bandCap],
  /// capped at a third of the item, so the move zone between two bands is
  /// never thinner than either of them and a short item stays movable.
  double _bandExtentOn(double extent) {
    return math.min(bandCap, extent / 3.0);
  }

  /// The admitted band under [position] on [axis], or null.
  BoardResizeEdges? _bandOn(
    Axis axis,
    BoardResizeEdges policy,
    Offset position,
  ) {
    if (policy == BoardResizeEdges.none) {
      return null;
    }
    final vertical = axis == Axis.vertical;
    final extent = vertical ? size.height : size.width;
    final at = vertical ? position.dy : position.dx;
    final band = _bandExtentOn(extent);
    // The PAINTED bands, near (top, left) and far (bottom, right), each
    // named by the CONTENT edge that paints there: the leading edge
    // paints near on a forward axis and far on a reversed one.
    final reversed = vertical ? reverseVertical : reverseHorizontal;
    final inNear = at < band;
    final inFar = at >= extent - band;
    final inLeading = reversed ? inFar : inNear;
    final inTrailing = reversed ? inNear : inFar;
    final trailingAdmitted =
        policy == BoardResizeEdges.trailing || policy == BoardResizeEdges.both;
    final leadingAdmitted =
        policy == BoardResizeEdges.leading || policy == BoardResizeEdges.both;
    // Trailing first: where the two bands of a short item would meet, the
    // trailing one takes the press, as the later-stacked strip did.
    if (trailingAdmitted && inTrailing) {
      return BoardResizeEdges.trailing;
    }
    if (leadingAdmitted && inLeading) {
      return BoardResizeEdges.leading;
    }
    return null;
  }

  /// The band under [position], or null for the move zone. The PRIMARY
  /// axis first: at a corner its band takes the press, as its strips,
  /// stacked last, did.
  ({BoardResizeEdges edge, Axis axis})? _bandAt(Offset position) {
    final primary = _bandOn(primaryAxis, primaryEdges, position);
    if (primary != null) {
      return (edge: primary, axis: primaryAxis);
    }
    final spanAxis = primaryAxis == Axis.vertical
        ? Axis.horizontal
        : Axis.vertical;
    final span = _bandOn(spanAxis, spanEdges, position);
    if (span != null) {
      return (edge: span, axis: spanAxis);
    }
    return null;
  }

  /// A band takes the press OUTRIGHT and the child is not asked, which is
  /// what an opaque strip on top of the item did; the move zone defers to
  /// the child, which is what the move wrap did. Inactive, this is a
  /// plain proxy.
  /// The cursor a band shows under a mouse: its axis's resize cursor.
  /// Added to a band's hit as a second entry, whose target the mouse
  /// tracker reads the cursor from (`rendering/mouse_tracker.dart:231-240`);
  /// it is the deepest non-deferring cursor on the path, so it is the one
  /// shown (`services/mouse_cursor.dart:261-266`). The move zone adds
  /// none: its lift is a long press even for a mouse.
  static const _BandCursor _verticalBandCursor = _BandCursor(
    SystemMouseCursors.resizeUpDown,
  );
  static const _BandCursor _horizontalBandCursor = _BandCursor(
    SystemMouseCursors.resizeLeftRight,
  );

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) {
      return false;
    }
    final band = active ? _bandAt(position) : null;
    if (band != null) {
      result.add(BoxHitTestEntry(this, position));
      result.add(
        HitTestEntry(
          band.axis == Axis.vertical
              ? _verticalBandCursor
              : _horizontalBandCursor,
        ),
      );
      return true;
    }
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (!active || event is! PointerDownEvent) {
      return;
    }
    final band = _bandAt(entry.localPosition);
    if (band == null) {
      onPointerDown(event, BoardResizeEdges.none, null);
    } else {
      onPointerDown(event, band.edge, band.axis);
    }
  }
}
