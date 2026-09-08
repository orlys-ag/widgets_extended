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
/// The full thirteen-parameter surface; `background`, `drag` and
/// `selection` landed as optional named parameters with their types, so
/// every call site written against the cells-only constructor compiles
/// unchanged.
class Board<TKey, TItem> extends StatefulWidget {
  /// Creates a board over [controller].
  ///
  /// The last six parameters are pass-throughs to
  /// `TwoDimensionalScrollView` (`widgets/two_dimensional_scroll_view.dart:57`).
  /// [primary] is nullable with no default, matching the base
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

  /// Drag-and-drop policy. PRESENCE is fixed at widget creation (the
  /// `State` owns a drag controller exactly when this is non-null);
  /// [BoardDragConfig.enabled] is the runtime switch.
  final BoardDragConfig<TKey>? drag;

  /// Selection gesture policy. Same presence rule.
  final BoardSelectionConfig? selection;

  /// Whether each child is wrapped in a `RepaintBoundary`.
  final bool addRepaintBoundaries;

  /// The vertical `Scrollable`'s configuration.
  final ScrollableDetails verticalDetails;

  /// The horizontal `Scrollable`'s configuration.
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

  /// The proxy shows and hides with the session; a plain setState is
  /// enough because the proxy is built in [build].
  void _handleDragChanged() {
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
  }

  @override
  void didUpdateWidget(covariant Board<TKey, TItem> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The drag controller holds boardController and config as FINAL
    // fields, so a change to either, or to the config's null-ness,
    // rebuilds it rather than re-pointing anything.
    //
    // A REPLACED drag controller must also replace the delegate: every
    // mounted `_BoardItemHost` captured the old controller in its widget
    // at build, and a delegate rebuild is the one route that rebuilds
    // those children (see the note above [_createDelegate]). Without it
    // a host presses on against a disposed controller.
    var rehost = false;
    if (!identical(widget.controller, oldWidget.controller) ||
        !identical(widget.drag, oldWidget.drag)) {
      rehost = true;
      _teardownDragController();
      if (widget.drag != null) {
        _dragController = BoardDragController<TKey>(
          boardController: widget.controller,
          vsync: this,
          config: widget.drag!,
        )..addListener(_handleDragChanged);
      }
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
      addRepaintBoundaries: widget.addRepaintBoundaries,
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

  /// The delegate's builder. Cell vicinities are `(xIndex: col,
  /// yIndex: row)`; the ITEM band starts past every cell column and
  /// resolves through the controller's ordinal reads.
  Widget? _buildChild(BuildContext context, ChildVicinity vicinity) {
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
      return _BoardItemBuildHost<TKey, TItem>(
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
    return _BoardCellHost<TKey, TItem>(
      row: vicinity.yIndex,
      col: vicinity.xIndex,
      initial: built,
    );
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
    );
    final drag = _dragController;
    // The scope wraps EVERYTHING this build returns, the Stack included,
    // because the proxy host is the Stack's second child and must find
    // it too.
    return _BoardScope<TKey, TItem>(
      controller: widget.controller,
      cellBuilder: widget.cellBuilder,
      itemBuilder: widget.itemBuilder,
      dragController: drag,
      selectionRelay: _selectionRelay,
      dataRelay: _dataRelay,
      child: drag == null
          ? board
          : Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                board,
                _buildDragProxy(drag),
              ],
            ),
    );
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
    return ValueListenableBuilder<Offset?>(
      valueListenable: drag.pointerPosition,
      builder: (context, pointer, _) {
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
              child: _buildProxyContent(key),
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

/// Whether [track] is inside one of [config]'s frozen bands. This reads
/// the CONFIG; the render object derives its frozen geometry from the
/// same numbers.
bool _isFrozenTrack(BoardAxisConfig config, int track) {
  if (track < config.frozenStart) {
    return true;
  }
  return track >= config.axis.trackCount - config.frozenEnd;
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
        _isFrozenTrack(controller.rows, row) ||
        _isFrozenTrack(controller.columns, col),
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
    return _built ?? widget.initial;
  }
}

/// Hosts one ITEM's builder output, in the lattice or, under [isProxy],
/// in the drag proxy, with the same `initial` protocol as
/// [_BoardCellHost]. A lattice host wraps the content in [_BoardItemHost]
/// when the scope carries a drag controller; that host is un-keyed and
/// its `State` survives a rebuild of this wrapper, which the drag layer's
/// key capture relies on.
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
      span.startTrackOn(Axis.vertical).floor(),
      selection.rowStart,
    );
    final rowEnd = math.min(
      span.endTrackOn(Axis.vertical).ceil(),
      selection.rowEnd,
    );
    final colStart = math.max(
      span.startTrackOn(Axis.horizontal).floor(),
      selection.colStart,
    );
    final colEnd = math.min(
      span.endTrackOn(Axis.horizontal).ceil(),
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

  /// The key the owned session STARTED with. Not `widget.itemKey`: the
  /// host is un-keyed, so a rank insert can re-key this element's widget
  /// in place while the session stays on the lifted item, and both
  /// ownership checks below must follow the session, not the widget.
  /// [_armRecognizer] captures the same key one step earlier, when the
  /// pointer goes down, for the same reason.
  TKey? _ownedKey;

  /// The session's pointer, tracked by DELTA from where the drag started.
  /// Inside a scrollable the handle's recognizer shares the arena with
  /// the scrollable's own and is accepted on the first move past the
  /// slop, and the multi-drag recognizer reports that accepting move as a
  /// delta against the INITIAL position (`gestures/multidrag.dart:139-153`),
  /// so an update's position alone would drop it. The framework's drag
  /// avatar accumulates the same way (`widgets/drag_target.dart:873-876`).
  Offset _dragPosition = Offset.zero;

  bool get _canDrag {
    final config = widget.dragController.config;
    if (!config.enabled) {
      return false;
    }
    final canDrag = config.canDrag;
    return canDrag == null || canDrag(widget.itemKey);
  }

  void _armRecognizer(
    PointerDownEvent event,
    MultiDragGestureRecognizer recognizer,
    BoardResizeEdges edge,
    Axis? axis,
  ) {
    // The replacement leg: a second handle pressed while the first's
    // recognizer is still armed disposes the first, so no orphaned
    // recognizer outlives its pointer. A session the first one already
    // STARTED is cancelled before its recognizer dies: disposing a
    // multi-drag recognizer never ends the Drag it handed out, so
    // skipping this leaves the session wedged until the host unmounts.
    if (_ownsSession &&
        widget.dragController.draggedKey == _ownedKey) {
      _ownsSession = false;
      _ownedKey = null;
      widget.dragController.endDrag(cancel: true);
    }
    _recognizer?.dispose();
    // THE KEY IS CAPTURED HERE, with the edge and the axis: the three
    // things this pointer's gesture is about, fixed when it goes down.
    //
    // Not re-read at `onStart`, which runs a long-press delay or a touch
    // slop later. This host is deliberately un-keyed, so a rank shift
    // re-keys its widget IN PLACE while this `State`, which owns the
    // armed recognizer, survives (see [_ownedKey]); re-reading would
    // hand the session whatever item the element hosts by then, and the
    // app's report would mutate an item the user never pressed. The same
    // rule [_ownedKey] states for the session, one step earlier.
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
    final config = widget.dragController.config;
    // The drag policy is asked ONCE per build and threaded to both the
    // handle scope and the semantics actions below, rather than read
    // again in each: a policy is app code on a per-item build path, and
    // two reads of a stateful predicate can disagree within one build.
    final canDrag = _canDrag;
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
    // checks below do: this decides what THIS element paints, and a rank
    // shift re-keys the element in place, so the dim follows the widget.
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
    if (config.buildDefaultDragHandles) {
      // The MOVE handle wraps the whole item, delayed so touch scrolling
      // that starts on an item still works; resize handles are edge
      // strips, on the SPAN axis under `resizeEdges` and on the PRIMARY
      // axis under `primaryResizeEdges`, each strip naming its axis.
      child = BoardDelayedDragHandle(child: child);
      final strips = <Widget>[];
      void addStrips(BoardResizeEdges policy, Axis axis) {
        final vertical = axis == Axis.vertical;
        void addStrip(BoardResizeEdges edge) {
          final leading = edge == BoardResizeEdges.leading;
          final Alignment alignment;
          if (vertical) {
            alignment = leading ? Alignment.topCenter : Alignment.bottomCenter;
          } else {
            alignment = leading ? Alignment.centerLeft : Alignment.centerRight;
          }
          strips.add(
            Align(
              alignment: alignment,
              child: BoardDragHandle(
                edge: edge,
                axis: axis,
                // An empty strip defers to a child that is never hit;
                // opaque makes the band itself the target and stops the
                // pointer from falling through to the move wrap below.
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: vertical ? double.infinity : 12.0,
                  height: vertical ? 12.0 : double.infinity,
                ),
              ),
            ),
          );
        }

        switch (policy) {
          case BoardResizeEdges.none:
            break;
          case BoardResizeEdges.leading:
            addStrip(BoardResizeEdges.leading);
          case BoardResizeEdges.trailing:
            addStrip(BoardResizeEdges.trailing);
          case BoardResizeEdges.both:
            addStrip(BoardResizeEdges.leading);
            addStrip(BoardResizeEdges.trailing);
        }
      }

      final spanAxis = widget.spanAxisVertical
          ? Axis.vertical
          : Axis.horizontal;
      final primaryAxis = widget.spanAxisVertical
          ? Axis.horizontal
          : Axis.vertical;
      addStrips(config.resizeEdges, spanAxis);
      addStrips(config.primaryResizeEdges, primaryAxis);
      if (strips.isNotEmpty) {
        child = Stack(
          fit: StackFit.passthrough,
          children: <Widget>[child, ...strips],
        );
      }
    }
    child = _wrapSemantics(child, config, canDrag: canDrag);
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
          config.onItemMoved(key, span);
        };
      }

      addMove("Move up", -1, 0);
      addMove("Move down", 1, 0);
      addMove("Move left", 0, -1);
      addMove("Move right", 0, 1);
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
  /// moved span leaves the lattice, or `canDropAt` declines. The ONE
  /// predicate behind both the advertised set and an activation.
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
    final canDropAt = widget.dragController.config.canDropAt;
    if (canDropAt != null && !canDropAt(key, moved)) {
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
    required super.delegate,
    required super.mainAxis,
    required super.verticalDetails,
    required super.horizontalDetails,
    required super.diagonalDragBehavior,
    required super.clipBehavior,
    required super.primary,
  });

  final BoardController<TKey, TItem> controller;

  final BoardBackgroundPainter? background;

  final BoardSelectionConfig? selection;

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
      verticalOffset: verticalOffset,
      verticalAxisDirection: verticalDetails.direction,
      horizontalOffset: horizontalOffset,
      horizontalAxisDirection: horizontalDetails.direction,
    );
    final config = selection;
    if (config == null ||
        !config.enabled ||
        config.mode == BoardSelectionMode.none) {
      return viewport;
    }
    return _SelectionLayer<TKey, TItem>(
      controller: controller,
      config: config,
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
    required this.child,
  });

  final BoardController<TKey, TItem> controller;
  final BoardSelectionConfig config;
  final Widget child;

  @override
  State<_SelectionLayer<TKey, TItem>> createState() {
    return _SelectionLayerState<TKey, TItem>();
  }
}

class _SelectionLayerState<TKey, TItem>
    extends State<_SelectionLayer<TKey, TItem>> {
  ({int row, int col})? _anchor;

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
  /// mid-cell touch to the nearest EDGE would select the neighbour.
  ({int row, int col})? _cellAt(Offset global) {
    final viewport = _viewport();
    if (viewport == null) {
      return null;
    }
    final track = viewport.trackSpaceAt(viewport.globalToPaintLocal(global));
    if (track == null) {
      return null;
    }
    final snap = widget.config.snap;
    final row = snap.mode == BoardSnapMode.fraction
        ? snap.quantize(track.row)
        : track.row;
    final col = snap.mode == BoardSnapMode.fraction
        ? snap.quantize(track.col)
        : track.col;
    final rows = widget.controller.rows.axis.trackCount;
    final cols = widget.controller.columns.axis.trackCount;
    if (rows == 0 || cols == 0) {
      return null;
    }
    return (
      row: row.floor().clamp(0, rows - 1),
      col: col.floor().clamp(0, cols - 1),
    );
  }

  Drag? _beginRange(Offset global) {
    final anchor = _cellAt(global);
    if (anchor == null) {
      return null;
    }
    _anchor = anchor;
    _dragPosition = global;
    widget.controller.setSelection(
      BoardSelection(anchor: anchor, focus: anchor),
    );
    return _SelectionDrag<TKey, TItem>(this);
  }

  void _extendTo(Offset global) {
    final anchor = _anchor;
    if (anchor == null) {
      return;
    }
    final focus = _cellAt(global);
    if (focus == null) {
      return;
    }
    widget.controller.setSelection(
      BoardSelection(anchor: anchor, focus: focus),
    );
  }

  void _tapAt(Offset global) {
    final cell = _cellAt(global);
    if (cell == null) {
      return;
    }
    widget.controller.setSelection(
      BoardSelection(anchor: cell, focus: cell),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gestures = <Type, GestureRecognizerFactory>{};
    if (widget.config.mode == BoardSelectionMode.range) {
      gestures[ImmediateMultiDragGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<
            ImmediateMultiDragGestureRecognizer
          >(
            () {
              return ImmediateMultiDragGestureRecognizer();
            },
            (recognizer) {
              recognizer.onStart = _beginRange;
            },
          );
    } else {
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
    return RawGestureDetector(
      gestures: gestures,
      behavior: HitTestBehavior.translucent,
      child: widget.child,
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
  }

  @override
  void end(DragEndDetails details) {
    _layer._anchor = null;
  }

  @override
  void cancel() {
    _layer._anchor = null;
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
  });

  final BoardController<TKey, TItem> controller;

  final BoardBackgroundPainter? background;

  @override
  RenderBoardViewport<TKey> createRenderObject(BuildContext context) {
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
      ..clipBehavior = clipBehavior;
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
