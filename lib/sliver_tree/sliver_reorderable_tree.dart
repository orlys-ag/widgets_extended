/// Declarative wrapper around [SliverTree] that adds drag-and-drop reorder
/// over a [TreeReorderController].
///
/// EVERY row produced by [nodeBuilder] is wrapped, unconditionally, the
/// same way `SliverReorderableList._itemBuilder` wraps every item. The
/// wrapper:
///
/// - Publishes a [TreeRowDragScope], so a [TreeDragHandle] placed
///   ANYWHERE inside the row can arm it. The package composes no drag
///   surface of its own and reserves no space for one; where the handle
///   sits, how big it is, and whether there are two of them are the
///   caller's decisions.
/// - Owns the drag recognizer and one `Drag` per gesture. Handles are
///   stateless pointer-down reporters that own nothing, which is what
///   makes two handles in one row safe, a handle inside a nested
///   scrollable harmless, and an unmounted handle a non-event for a live
///   drag.
/// - On drag start, starts a session on [reorderController] (a `false`
///   return, `canReorder` refusal or not-yet-laid-out tree, quietly
///   declines the gesture, and the row hands the recognizer a null
///   `Drag`), hides the source row, and shows the drag UI.
/// - On drag update / end / cancel, forwards to the controller. Each
///   `Drag` carries the [TreeReorderController.dragGeneration] it was
///   born under and re-validates it before every forward, so a stale
///   gesture can never commit another session; a `deactivate()` backstop
///   cancels a session whose row unmounts mid-drag.
/// - Exposes custom semantics actions (move up / down / out / into
///   previous sibling) so assistive-technology users can reorder without
///   pointer drags, gated by the same `canReorder` / `canAcceptDrop`
///   policies. A row with NO handle keeps all of this: it cannot be
///   lifted by a pointer, but it is still a drop TARGET and still
///   reorderable from assistive technology.
///
/// Row wrappers are wired through an inherited `_ReorderableScope`: rows
/// read the reorder controller, presentation config, and the owner's
/// callbacks from the scope (no ancestor-State references) and locate the
/// render surface by walking up to the first [ReorderRenderPort] ancestor
/// rather than any concrete render type.
///
/// Drop feedback is the **make-room preview**, always on: while dragging,
/// rows part to open a live gap at the prospective slot. The gap is
/// paint-only, structure is untouched until the drop commits, and no
/// structural listeners or sync diffs fire from the preview. The dragged
/// row's in-place copy is hidden entirely (its slot closes up under it),
/// so the floating drag proxy is its only representation.
///
/// Drag UI lives in one overlay entry owned by this widget's state: the
/// drag proxy ([showDragProxy] / [dragProxyBuilder]) subscribes to
/// [TreeReorderController.pointerPosition], the per-move channel, and
/// floats the dragged row's preview at the grab point.
///
/// The pointer's horizontal position picks the drop depth at subtree
/// right-boundaries (the default `x ~/ indentWidth` mapper passed to
/// `startDrag`). With the proxy enabled (the default), slot selection is
/// CARD-ANCHORED: it probes at the floating card's midpoint rather than
/// the pointer, so a touch drag tracks the card in hand regardless of
/// where it was grabbed. That USED to be described as mattering only for
/// long-press drags, on the grounds that a handle's grab is centred; it
/// is not, now that handles are caller-placed. A grip bar across the top
/// of an 80px card is grabbed 16px down, so the probe sits 24px below the
/// pointer, and the card in hand is what picks the slot. Opt-in
/// [hapticsOnDrag] adds lift / slot-change feedback.
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart'
    show Drag, DragEndDetails, DragUpdateDetails, MultiDragGestureRecognizer;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import 'animation_style.dart';
import 'reorder_render_port.dart';
import 'sliver_tree_widget.dart';
import 'tree_controller.dart';
import 'tree_drag_handle.dart';
import 'tree_reorder_controller.dart';

/// Transforms the reorder actions a row exposes to assistive technology.
///
/// [builtIn] is the package's own set for [nodeKey], already gated by
/// `canReorder` and `canAcceptDrop`. Returning it unchanged is the
/// default behavior; returning a superset adds actions, a subset removes
/// them, and a re-keyed map relabels them, which is the only way to
/// localize the built-in English labels since this package has no
/// localization layer.
///
/// Called on every build of a reorderable row, so keep it cheap and
/// pure. NOT called for a row that `canReorder` refused, or one that is
/// absent or mid-exit: this refines a movable row's vocabulary, it
/// cannot make an immovable row movable.
///
/// Contributed actions should commit through
/// [TreeReorderController.moveTo] or the named move methods, which apply
/// `canAcceptDrop`, refuse while a drag is in flight, and report through
/// `onReorder`. An action that mutates the tree controller directly
/// bypasses all three.
///
/// Labels must be `const` or module-level. `CustomSemanticsAction`
/// interns its identifiers in static maps with no removal path, so a
/// label that varies per row leaks one entry per distinct string for the
/// life of the process.
///
/// The ORDER actions appear in is not controllable from here. Flutter
/// emits `customSemanticsActionIds` sorted by interned identifier, which
/// is global first-use order across the process, not this map's
/// iteration order.
typedef ReorderSemanticsActionsBuilder<TKey> =
    Map<CustomSemanticsAction, VoidCallback> Function(
      TKey nodeKey,
      Map<CustomSemanticsAction, VoidCallback> builtIn,
    );

/// Declarative drag-and-drop reorderable [SliverTree].
class SliverReorderableTree<TKey, TData> extends StatefulWidget {
  const SliverReorderableTree({
    required this.controller,
    required this.reorderController,
    required this.nodeBuilder,
    this.maxStickyDepth = 0,
    this.indentWidth,
    this.showDragProxy = true,
    this.dragProxyBuilder,
    this.hapticsOnDrag = false,
    this.semanticsActionsBuilder,
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

  /// Builds each row, with the plain [SliverTree] signature.
  ///
  /// The returned widget is wrapped for you, so there is nothing to call
  /// and nothing to forget. To make a row draggable by a POINTER, place a
  /// [TreeDragHandle] (or [TreeDelayedDragHandle]) somewhere inside it;
  /// the handle can be anywhere, any size, and there can be more than
  /// one.
  final Widget Function(BuildContext context, TKey nodeKey, int nodeDepth)
  nodeBuilder;

  /// See [SliverTree.maxStickyDepth].
  final int maxStickyDepth;

  /// Horizontal indent per depth level, used to map the pointer's
  /// horizontal position to a preferred drop depth (`x ~/ indentWidth`)
  /// at subtree boundaries, where one visible slot has several legal
  /// depth expressions.
  ///
  /// Null (the default) reads [TreeController.indentWidth] at drag
  /// start, the constant the render layer indents rows by, so the
  /// mapping matches what is on screen with no configuration. Set it
  /// explicitly only when the rendered indent is NOT render-applied:
  /// rows that bake their own indent from the node depth (controller
  /// `indentWidth` 0) should pass the pixel constant they bake.
  ///
  /// A resolved value of `0` disables x-aware depth selection entirely;
  /// drops then always resolve at the deepest legal level.
  final double? indentWidth;

  /// Whether to render a floating preview of the dragged row that follows
  /// the pointer, anchored at the grab point. Defaults to true, and is
  /// implied true when [dragProxyBuilder] is provided.
  ///
  /// Turning this off leaves the drag with no representation under the
  /// pointer: the make-room preview hides the dragged row's in-place copy
  /// so its slot can close, and only the opening gap remains as feedback.
  ///
  /// The preview is INDENT-AWARE: its content carries a left padding
  /// seeded with the source row's indent at lift (so the lift does not
  /// jump horizontally) and animated toward the resolved drop target's
  /// column (`targetDepth * TreeController.indentWidth`, the constant
  /// the render layer indents rows by) on each semantic target change.
  /// The tracking rides the `makeRoom` animation family (it is drag-gap
  /// feedback; a zero family snaps), resolved once per drag. On
  /// release, the settle glide starts at the padding's instantaneous
  /// value, so the proxy-to-row handoff is seamless in x as well as y.
  /// With `indentWidth: 0` (indent baked into rows by [nodeBuilder], or
  /// no indent at all) every term is 0 and the preview renders flush
  /// left, unchanged.
  ///
  /// Dragging an EXPANDED parent floats its whole visible subtree: the
  /// preview stacks the dragged row's clone above one fresh clone per
  /// visible descendant, each pinned to its extent at lift and padded
  /// by its indent RELATIVE to the dragged row, and the settle glides
  /// carry every row of the stack, so the subtree emerges from under
  /// the card at release. (The in-place subtree rows hide for the
  /// drag, and the make-room gap accounts for their summed extents.)
  /// The stack is captured FROZEN at drag start; mid-drag structural
  /// mutations of the dragged subtree do not rebuild it. Its DRAWING
  /// is capped at one viewport of cumulative extent: deeper rows still
  /// travel structurally and in the settle handoff, they are just not
  /// drawn in the band.
  ///
  /// The preview renders in the root [Overlay], OUTSIDE the row's original
  /// ancestry, the same contract as `Draggable.feedback`. Rows using
  /// inherited-ancestor-dependent widgets (e.g. Material ink widgets,
  /// which assert on a `Material` ancestor) need a [dragProxyBuilder] that
  /// re-provides those ancestors (e.g. wrap in
  /// `Material(type: MaterialType.transparency)`); this package is
  /// widgets-layer-only and cannot supply Material itself.
  final bool showDragProxy;

  /// Builds the floating drag preview. Receives the dragged key and the
  /// row's child widget (exactly what [nodeBuilder] returned for it, so
  /// any [TreeDragHandle] inside is cloned too; null when the drag was
  /// started imperatively without a row). The clone renders in the root
  /// `Overlay`, where a handle finds no [TreeRowDragScope] and is
  /// therefore inert. When null and
  /// [showDragProxy] is true, the default preview renders the row's child
  /// at 90% opacity, sized to the row's extent and viewport width.
  ///
  /// The returned widget is wrapped in the indent-tracking left padding
  /// described on [showDragProxy], default and custom builders alike:
  /// the content lays out at `viewportWidth - indent`, matching the
  /// real row's render-applied width at the tracked depth, so text
  /// wrapping matches at handoff. Do not add a depth indent of your own
  /// inside the builder. The builder's portion is pinned to the
  /// grab-time row extent, so a row whose extent would change at the
  /// target width clips until handoff.
  ///
  /// The builder receives and styles the DRAGGED ROW's portion only.
  /// When an expanded parent is dragged, its visible descendants'
  /// clones stack below the builder's output unchanged: builds of
  /// [nodeBuilder] against the overlay's context, each with the
  /// row's original depth and pinned to its extent at lift (see
  /// [showDragProxy] for the subtree stack contract).
  ///
  /// The builder is invoked ONCE PER DRAG SESSION (plus on
  /// inherited-ancestry changes and hot reload), not per pointer move,
  /// pointer moves only reposition the proxy. Do not rely on rebuild
  /// cadence to refresh ambient reads; that cadence was never part of
  /// the contract (a stationary pointer, e.g. a finger parked in the
  /// autoscroll edge zone, fires no moves at all). Dynamic proxy
  /// content self-drives instead, and works fully because the returned
  /// subtree stays mounted for the whole session: use self-owned
  /// animations (a mount-triggered `TweenAnimationBuilder` lift effect,
  /// a repeating `AnimationController`) for motion, and listenable
  /// subscriptions for drag-state reactivity (a `ListenableBuilder` on
  /// the [TreeReorderController] rebuilds on every semantic target
  /// change; [TreeReorderController.pointerPosition] serves
  /// pointer-reactive parts).
  ///
  /// See [showDragProxy] for the overlay-ancestry contract (Material apps
  /// typically wrap the preview in a transparency `Material` here).
  final Widget Function(BuildContext context, TKey key, Widget? rowChild)?
  dragProxyBuilder;

  /// Opt-in drag haptics: [HapticFeedback.selectionClick] on lift and on
  /// each SEMANTIC SLOT change. Deliberately debounced on the slot identity
  /// `(parentKey, indexInFinalList)` rather than raw controller
  /// notifications, the coalesced channel also fires on same-slot
  /// EXPRESSION changes (crossing between e.g. below-last-row and
  /// above-next-header, which are the same slot), and buzzing while the
  /// gap stands still would be noise. Default off.
  final bool hapticsOnDrag;

  /// Transforms the reorder actions each row exposes to assistive
  /// technology. See [ReorderSemanticsActionsBuilder].
  ///
  /// Pass a STABLE reference: a method tear-off, a field, or a top-level
  /// function. Rows depend on this through an inherited scope, so a fresh
  /// closure on every build rebuilds every visible row each time an
  /// ancestor rebuilds. (A changed builder must reach mounted rows, so it
  /// cannot simply be ignored the way the internal tear-offs are.)
  final ReorderSemanticsActionsBuilder<TKey>? semanticsActionsBuilder;

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
/// compares only the value fields, the callbacks always target the same
/// state object for the lifetime of the scope's element anyway.
class _ReorderableScope<TKey> extends InheritedWidget {
  const _ReorderableScope({
    required this.reorderController,
    required this.draggedKey,
    required this.indentWidth,
    required this.dragProxyEnabled,
    required this.proxyCrossOffset,
    required this.onDragStart,
    required this.onSessionInterrupted,
    required this.semanticsActionsBuilder,
    required super.child,
  });

  final TreeReorderController<TKey> reorderController;

  /// The key whose row is currently dragged, or null. Drives hiding the
  /// source row declaratively, make-room closes its slot underneath it.
  final TKey? draggedKey;

  /// Indent per depth level; rows use it to build the default x to depth
  /// hint mapper passed to `startDrag`. Carried as the RAW nullable
  /// widget value (value-comparable, so [updateShouldNotify] stays
  /// honest); rows resolve null against the tree controller's
  /// `indentWidth` at drag start, so the render-truth constant is read
  /// live rather than frozen at build time.
  final double? indentWidth;

  /// Whether the floating drag proxy is enabled. Rows forward it as
  /// `startDrag(settleFromRelease:)` so the drop FLIP starts at the
  /// proxy's release position, the proxy hands off to the real row
  /// mid-flight instead of the row replaying the old-slot slide.
  final bool dragProxyEnabled;

  /// The proxy's VISUAL cross offset in sliver cross space, read at
  /// settle-glide install time. Rows forward it as
  /// `startDrag(proxyCrossOffset:)` so the proxy-to-row handoff starts
  /// exactly where the card visually is. A tear-off of the owner state,
  /// like [onDragStart]: excluded from [updateShouldNotify], unlike the
  /// value fields.
  final double Function() proxyCrossOffset;

  /// Row [key] successfully started a drag session: hide it and (when
  /// enabled) float the drag proxy built from [rowChild].
  final void Function(TKey key, Widget rowChild) onDragStart;

  /// Deactivate-backstop channel: the row owning [key]'s session unmounted
  /// mid-drag and its session was cancelled post-frame. The owner clears
  /// the drag UI iff its UI still shows that session, the key guard
  /// lives in the owner, next to the state it protects.
  final void Function(TKey key) onSessionInterrupted;

  /// Consumer-supplied action transform, forwarded to rows.
  ///
  /// INCLUDED in [updateShouldNotify], unlike the tear-offs above. Those
  /// are stable by construction and their identity churn is meaningless;
  /// this is a value the consumer supplies, and rows cache it, so
  /// excluding it would make a changed builder invisible to every
  /// already-mounted row. Turning the seam on at runtime would do
  /// nothing at all.
  ///
  /// The cost is that an INLINE closure notifies every dependent row on
  /// every ancestor rebuild. That is why the widget field documents a
  /// stable reference, and why the declarative layer passes a forwarder
  /// built once rather than the caller's closure.
  final ReorderSemanticsActionsBuilder<TKey>? semanticsActionsBuilder;

  @override
  bool updateShouldNotify(_ReorderableScope<TKey> old) {
    return draggedKey != old.draggedKey ||
        indentWidth != old.indentWidth ||
        dragProxyEnabled != old.dragProxyEnabled ||
        // `!=`, NOT `!identical`. Dart canonicalizes instance-method
        // tear-off EQUALITY but not identity: `a.foo == a.foo` is true
        // while `identical(a.foo, a.foo)` is false. Comparing by identity
        // therefore reported a change on every single rebuild for the
        // recommended usage (a stable tear-off), rebuilding every visible
        // row each time, which is precisely the storm this comparison
        // exists to prevent. An inline closure still compares unequal and
        // still churns, which is why the field documents a stable
        // reference.
        semanticsActionsBuilder != old.semanticsActionsBuilder ||
        !identical(reorderController, old.reorderController);
  }

  static _ReorderableScope<TKey>? maybeOf<TKey>(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ReorderableScope<TKey>>();
  }
}

class _SliverReorderableTreeState<TKey, TData>
    extends State<SliverReorderableTree<TKey, TData>>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _proxyEntry;
  TKey? _draggedKey;

  /// The dragged row's child widget, captured at drag start for the
  /// default proxy content. Cleared with the session.
  Widget? _draggedRowChild;

  /// Frozen per-session capture of the dragged row's VISIBLE
  /// descendants, in visible order: key, the original depth the
  /// in-place build received, the extent at capture, and the indent
  /// RELATIVE to the dragged row. Drives the proxy's subtree stack;
  /// null for a leaf or collapsed drag (single-row proxy by
  /// construction). Bounded at capture to one viewport of cumulative
  /// extent: a drawing cap only; the settle handoff is not capped.
  /// Cleared with the session.
  List<({TKey key, int depth, double extent, double relativeIndent})>?
  _dragStack;

  /// Captures [_dragStack] for the row lifting [key]. Reads are all
  /// controller truth (`getVisibleIndex`, `visibleSubtreeSize`,
  /// `visibleNodes`, `nidOf` + `getCurrentExtentNid`, `getDepth`); the
  /// capture is FROZEN for the session, the same policy as the frozen
  /// [_draggedRowChild] capture, so mid-drag structural mutations do
  /// not rebuild the stack.
  List<({TKey key, int depth, double extent, double relativeIndent})>?
  _captureDragStack(TKey key) {
    final tree = widget.controller;
    final index = tree.getVisibleIndex(key);
    if (index < 0) {
      return null;
    }
    final size = tree.visibleSubtreeSize(key);
    if (size <= 1) {
      return null;
    }
    final draggedDepth = tree.getDepth(key);
    final indentWidth = tree.indentWidth;
    final cap =
        Scrollable.maybeOf(context)?.position.viewportDimension ??
        double.infinity;
    final parentNid = tree.nidOf(key);
    double cumulative = parentNid >= 0
        ? tree.getCurrentExtentNid(parentNid)
        : 0.0;
    final rows =
        <({TKey key, int depth, double extent, double relativeIndent})>[];
    for (int i = index + 1; i < index + size; i++) {
      if (cumulative >= cap) {
        break;
      }
      final rowKey = tree.visibleNodes[i];
      final nid = tree.nidOf(rowKey);
      final extent = nid >= 0 ? tree.getCurrentExtentNid(nid) : 0.0;
      final depth = tree.getDepth(rowKey);
      rows.add((
        key: rowKey,
        depth: depth,
        extent: extent,
        relativeIndent: (depth - draggedDepth) * indentWidth,
      ));
      cumulative += extent;
    }
    return rows.isEmpty ? null : rows;
  }

  /// The proxy content's animated indent (its left padding), in sliver
  /// cross space. Seeded with the SOURCE row's indent at drag start so
  /// the lift is seamless, then re-targeted toward the semantic
  /// target's column (`depth * indentWidth`, the render-truth constant
  /// `TreeController.getIndent` multiplies) on each coalesced target
  /// change. [_DragProxy] consumes it per frame; [_proxyCrossOffset]
  /// reports its instantaneous value to the settle glides.
  final ValueNotifier<double> _proxyIndent = ValueNotifier<double>(0.0);

  /// Drives [_proxyIndent] between [_proxyIndentFrom] and
  /// [_proxyIndentTo] under [_proxyIndentSpec]. Constructed in
  /// [initState]: `createTicker` looks up [TickerMode] through the
  /// element tree, so a lazy first touch from [dispose] (a tree that
  /// never dragged) would throw the deactivated-ancestor-lookup assert.
  late final AnimationController _proxyIndentDriver;

  /// FAMILY DECLARATION SITE (makeRoom): the proxy's indent tracking is
  /// drag-gap feedback, so it rides the same family as the gap.
  /// Resolved ONCE per drag in [_onDragStart], matching the session
  /// convention; a zero family snaps (kill-switch rule).
  TreeAnimationSpec _proxyIndentSpec = TreeAnimationStyle.defaultSpec;

  /// Endpoints the indent driver interpolates between. Re-based on every
  /// re-target so the proxy continues from where it currently sits.
  double _proxyIndentFrom = 0.0;
  double _proxyIndentTo = 0.0;

  /// Drives [_proxyIndent] from the raw driver value, applying the
  /// family's curve so the proxy's horizontal travel eases like the gap.
  void _onProxyIndentTick() {
    final t = _proxyIndentSpec.curve.transform(_proxyIndentDriver.value);
    _proxyIndent.value =
        _proxyIndentFrom + (_proxyIndentTo - _proxyIndentFrom) * t;
  }

  /// Animates (or snaps, for a zero family) the proxy indent toward the
  /// resolved target's column. A null target keeps the last value
  /// rather than snapping to 0; a target already being animated toward
  /// is left alone (the coalesced channel also fires on same-slot
  /// EXPRESSION changes, and restarting the clock would stutter).
  void _retargetProxyIndent() {
    final target = widget.reorderController.currentTarget;
    if (target == null) {
      return;
    }
    final indent = target.depth * widget.controller.indentWidth;
    if (indent == _proxyIndentTo &&
        (_proxyIndentDriver.isAnimating || _proxyIndent.value == indent)) {
      return;
    }
    _proxyIndentDriver.stop();
    _proxyIndentFrom = _proxyIndent.value;
    _proxyIndentTo = indent;
    if (_proxyIndentSpec.duration == Duration.zero) {
      _proxyIndent.value = indent;
      return;
    }
    _proxyIndentDriver.duration = _proxyIndentSpec.duration;
    _proxyIndentDriver.forward(from: 0.0);
  }

  @override
  void initState() {
    super.initState();
    _proxyIndentDriver = AnimationController(vsync: this)
      ..addListener(_onProxyIndentTick);
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
    _proxyIndentDriver.dispose();
    _proxyIndent.dispose();
    super.dispose();
  }

  /// Syncs local drag UI (hidden source row + drag proxy) with the
  /// controller's session state. This is the SINGLE owner of drag-UI
  /// teardown for controller-driven session ends: the row wrappers'
  /// end/cancel handlers only forward to the controller, whose
  /// `notifyListeners` lands here. The exceptions are the row-side
  /// orphaned-session backstops, deactivate, policy flip, and the
  /// reorder-controller-swap hook in the row's `didChangeDependencies`,
  /// which reach this state via
  /// [_ReorderableScope.onSessionInterrupted] because by the time their
  /// deferred cancel notifies, this state no longer listens to the
  /// controller that owned the session.
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
    if (_draggedKey != null && widget.reorderController.isDragging) {
      // Semantic target change mid-drag: track the resolved depth's
      // column with the proxy indent.
      _retargetProxyIndent();
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

  /// Fires one selection click when a drag starts and one on every change
  /// of resolved slot, and nothing while the pointer moves within a slot.
  /// Tracks the last slot so a re-resolution to the same slot stays
  /// silent.
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

  /// Tears the overlay entry down and drops the captured drawing, so a
  /// later drag rebuilds both rather than reusing stale content.
  void _removeProxy() {
    _proxyEntry?.remove();
    _proxyEntry = null;
    _draggedRowChild = null;
    _dragStack = null;
  }

  /// Inserts the floating proxy into the root overlay, once per session.
  /// A no-op when the row has no proxy configured, when one is already
  /// mounted, or when no overlay is available.
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
        proxyIndent: _proxyIndent,
        rowChildResolver: () {
          return _draggedRowChild;
        },
        stackResolver: () {
          return _dragStack;
        },
        nodeBuilder: (context, key, depth) {
          return widget.nodeBuilder(context, key, depth);
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
    _dragStack = _captureDragStack(key);
    // Per-drag resolution of the proxy-indent family (see
    // [_proxyIndentSpec]), then seed with the SOURCE row's indent: the
    // proxy's first frame matches the row it lifts from, so the lift is
    // seamless. `indentWidth: 0` (indent baked into the row by the
    // nodeBuilder, or no indent at all) seeds and re-targets to 0, so
    // the tracking is inert there by construction.
    _proxyIndentSpec = widget.controller.animationStyle.effectiveMakeRoom;
    _proxyIndentDriver.stop();
    final seed = widget.controller.getIndent(key);
    _proxyIndentFrom = seed;
    _proxyIndentTo = seed;
    _proxyIndent.value = seed;
    _ensureProxy(context);
    setState(() => _draggedKey = key);
    // The session's start notify fires before this callback runs, so a
    // session born over a slot at a different depth would otherwise
    // wait for the next target change; catch up once here.
    _retargetProxyIndent();
  }

  /// Called when drag ends or cancels. Restores the source row and hides
  /// the proxy.
  void _onDragEnd() {
    if (!mounted) return;
    _proxyIndentDriver.stop();
    // Reset haptic state here as well as in [_syncHaptics]: on the
    // interrupted-session paths (deactivate backstop, policy flip,
    // reorder-controller swap) nothing notifies on the controller this
    // state listens to, so [_syncHaptics] never observes the session end
    // and a stale `_hapticsDragging = true` would swallow the next
    // session's lift click. On the normal path [_syncHaptics] already ran
    // with `dragging == false`, so this is a no-op there.
    _hapticsDragging = false;
    _lastHapticSlot = null;
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

  /// The proxy's VISUAL cross offset in sliver cross space, forwarded to
  /// `startDrag(proxyCrossOffset:)` through the scope. Reads
  /// [_proxyIndent]'s INSTANTANEOUS value (visual state, not a
  /// recomputed semantic target indent) so a release mid-animation
  /// hands off exactly where the card visually is.
  double _proxyCrossOffset() {
    return _proxyIndent.value;
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
      indentWidth: widget.indentWidth,
      dragProxyEnabled: widget.showDragProxy || widget.dragProxyBuilder != null,
      proxyCrossOffset: _proxyCrossOffset,
      onDragStart: _onDragStart,
      onSessionInterrupted: _onSessionInterrupted,
      semanticsActionsBuilder: widget.semanticsActionsBuilder,
      child: SliverTree<TKey, TData>(
        controller: widget.controller,
        maxStickyDepth: widget.maxStickyDepth,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        // Unconditional, matching `SliverReorderableList._itemBuilder`.
        // The wrapper is what publishes the drag scope a caller-placed
        // [TreeDragHandle] looks up, hides the dragged row so its slot
        // can close, and carries the reorder semantics actions, none of
        // which a row can opt out of and still take part in a reorder.
        nodeBuilder: (context, key, depth) {
          return _ReorderableRow<TKey>(
            nodeKey: key,
            child: widget.nodeBuilder(context, key, depth),
          );
        },
      ),
    );
  }
}

/// The wrapper every row gets. Handles:
///
/// - Publishing the [TreeRowDragScope] a caller-placed [TreeDragHandle]
///   arms itself from, and OWNING the recognizer those handles hand over.
/// - Hiding the source row during a drag (make-room closes its slot).
/// - Forwarding pointer events to the [TreeReorderController] (read from
///   the inherited scope, no ancestor-State reference).
class _ReorderableRow<TKey> extends StatefulWidget {
  const _ReorderableRow({required this.nodeKey, required this.child});

  final TKey nodeKey;
  final Widget child;

  @override
  State<_ReorderableRow<TKey>> createState() => _ReorderableRowState<TKey>();
}

/// The `Drag` handed back to the recognizer for ONE gesture.
///
/// Carries the [TreeReorderController.dragGeneration] its session was
/// born under. That is the identity `isDragging` and `draggedKey` cannot
/// supply, since the same node dragged twice is indistinguishable through
/// them, and it is what stops a pointer that has been superseded (a
/// second handle in the same row, an external `cancelDrag`, a programmatic
/// restart) from committing or cancelling somebody else's session.
class _RowDrag<TKey> implements Drag {
  _RowDrag({
    required this.row,
    required this.generation,
    required Offset startGlobal,
  }) : _position = startGlobal;

  final _ReorderableRowState<TKey> row;
  final int generation;

  /// The pointer's global position, ACCUMULATED from deltas rather than
  /// read off `DragUpdateDetails.globalPosition`.
  ///
  /// Not a stylistic choice. `MultiDragPointerState._startDrag`
  /// (gestures/multidrag.dart) synthesises the FIRST update as
  /// `DragUpdateDetails(delta: pendingDelta, globalPosition:
  /// initialPosition)`: it reports the movement that won the arena as a
  /// delta, while still naming the TOUCH-DOWN position. Trusting
  /// `globalPosition` there makes a drag that is accepted and released
  /// without a further move look as though the pointer never left the
  /// grab point, so the drop resolves onto the row's own slot and commits
  /// nothing. Summing deltas from the start position reconstructs the
  /// true position exactly, which is what Flutter's own `_DragInfo.update`
  /// does for the same reason.
  Offset _position;

  @override
  void update(DragUpdateDetails details) {
    _position += details.delta;
    row._forwardUpdate(generation, _position);
  }

  @override
  void end(DragEndDetails details) {
    row._forwardEnd(generation);
  }

  @override
  void cancel() {
    row._forwardCancel(generation);
  }
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

  /// The [TreeReorderController.dragGeneration] of the session this row
  /// started, or null when it owns none.
  int? _sessionGeneration;

  /// The recognizer handed over by the last handle to report a
  /// pointer-down. At most ONE per row: a second pointer-down replaces
  /// it, which is why two handles in one row cannot fight over a session.
  MultiDragGestureRecognizer? _recognizer;

  /// Scope values cached at dependency-update time. Gesture callbacks and
  /// `deactivate()` must not read the InheritedWidget (`dependOn*` is
  /// illegal outside build/didChangeDependencies), so they use these.
  ///
  /// On a reorder-controller swap the scope notifies dependents
  /// (`updateShouldNotify` compares controller identity) and the cache
  /// re-points at the NEW controller in the swap frame. A session this
  /// row owns cannot survive that re-pointing, every later gesture
  /// callback would fail [_ownsSession] against the new controller, so
  /// `didChangeDependencies` ends the orphaned session through
  /// [_endOrphanedSessionAfterFrame] BEFORE re-caching, while [_reorder]
  /// still names the session's owner. Within the swap frame itself
  /// (before the dependency update runs) callbacks still reach the OLD
  /// controller, which is the one that owns the session.
  late TreeReorderController<TKey> _reorder;
  double? _indentWidth;
  late bool _dragProxyEnabled;
  late double Function() _proxyCrossOffset;
  late void Function(TKey, Widget) _onDragStartCallback;
  late void Function(TKey) _onSessionInterruptedCallback;
  ReorderSemanticsActionsBuilder<TKey>? _semanticsActionsBuilder;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _ReorderableScope.maybeOf<TKey>(context);
    assert(
      scope != null,
      "_ReorderableRow is created by SliverReorderableTree for every row, "
      "below its _ReorderableScope",
    );
    // Reorder-controller swap while this row owns the live session: the
    // session stays on the OLD controller (still cached in [_reorder]),
    // but once the cache below re-points at the new controller every
    // future gesture callback fails [_ownsSession] against it, the
    // session would leak un-ended (pin, scroll listener, autoscroll
    // ticker, held make-room preview) with the drag UI stuck. End it
    // through the shared orphaned-session backstop BEFORE re-caching,
    // while [_reorder] still names the session's owner; the ordering is
    // load-bearing because the helper reads [_reorder]. The
    // [_isDraggingThisRow] guard also short-circuits the `late` read on
    // this State's first dependency update (no drag can have started),
    // and same-controller notifications (draggedKey flips, indent
    // changes) never trip the identity check.
    if (_isDraggingThisRow &&
        !identical(scope!.reorderController, _reorder)) {
      _endOrphanedSessionAfterFrame();
    }
    _reorder = scope!.reorderController;
    _indentWidth = scope.indentWidth;
    _dragProxyEnabled = scope.dragProxyEnabled;
    _proxyCrossOffset = scope.proxyCrossOffset;
    _onDragStartCallback = scope.onDragStart;
    _onSessionInterruptedCallback = scope.onSessionInterrupted;
    _semanticsActionsBuilder = scope.semanticsActionsBuilder;
  }

  // No gesture-mode-swap backstop, and none is needed: the recognizer
  // lives on this State rather than in the build output, so a handle
  // appearing, disappearing or changing shape mid-drag cannot dispose the
  // recognizer that owns the live pointer.

  @override
  void dispose() {
    // The recognizer outlives every gesture (it is only replaced by the
    // next pointer-down), so this State is the only thing that can
    // reclaim it. `deactivate` is deliberately not the place: an element
    // can be reactivated, and the drag it is driving would lose its
    // recognizer mid-flight.
    _disposeRecognizer();
    super.dispose();
  }

  void _disposeRecognizer() {
    _recognizer?.dispose();
    _recognizer = null;
  }

  /// Tear down a session this row still owns but can no longer receive
  /// gesture callbacks for, deferred past the current frame.
  ///
  /// Shared by every "the recognizer is about to vanish out from under a
  /// live pointer" path. All of them run inside the build phase, where
  /// `cancelDrag`'s notifyListeners (and the owner's setState behind it)
  /// must not run synchronously.
  void _endOrphanedSessionAfterFrame() {
    _isDraggingThisRow = false;
    _sessionGeneration = null;
    final reorder = _reorder;
    final onInterrupted = _onSessionInterruptedCallback;
    final nodeKey = widget.nodeKey;
    if (reorder.draggedKey != nodeKey) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (reorder.draggedKey != nodeKey) {
        return;
      }
      reorder.cancelDrag();
      onInterrupted(nodeKey);
    });
  }

  @override
  void deactivate() {
    // Lifecycle backstop: if this row unmounts while it owns the drag
    // (node removed and purged mid-drag, tree swapped, ...), its gesture
    // callbacks can never fire again, end the session instead of leaving
    // it (and the autoscroll ticker) orphaned. Eviction of a LIVE dragged
    // row is prevented by the render object's drag pin; this covers the
    // remaining unmount paths (dead-node GC deliberately ignores pins,
    // a purged row has nothing left to build).
    //
    // deactivate() only ever runs inside a BuildOwner.buildScope, for
    // the removed-and-purged case, the element's post-frame dead-node GC
    // pass. cancelDrag()'s notifyListeners and the ancestor's setState
    // must therefore NOT run synchronously here: they would throw
    // "setState() or markNeedsBuild() called during build" and abort the
    // rest of the GC pass. Only the local flag flip stays synchronous;
    // the teardown is deferred to a post-frame callback (the first point
    // guaranteed outside every build scope; a microtask can still land
    // inside this frame's build window). The callback re-validates
    // session ownership before acting: by the time it runs a new session
    // may have started, or the reorder controller may have been disposed
    // (after dispose, draggedKey is null, so the ownership check covers
    // both). Everything the callback needs is captured now from the
    // cached scope values, `widget`/`context` are unreadable after this
    // State unmounts.
    // The mechanics live in _endOrphanedSessionAfterFrame, shared with
    // the policy-flip backstop and the reorder-controller-swap hook in
    // didChangeDependencies: flag flips stay synchronous, everything the
    // deferred callback needs is captured from the cached scope values
    // before super.deactivate() (widget/context are unreadable after this
    // State unmounts), and the callback re-validates session ownership
    // before acting.
    if (_isDraggingThisRow) {
      _endOrphanedSessionAfterFrame();
    }
    super.deactivate();
  }

  /// Whether this row belongs to the dragged subtree: it IS the dragged
  /// row, or a strict descendant of it. The whole subtree travels with
  /// the drag (the make-room gap already lifts its full visible extent),
  /// so the whole subtree hides in place. O(depth) parent walk, the same
  /// predicate shape as `DropZoneResolver.isStrictDescendantOf`; only
  /// drag-lifecycle rebuilds pay it (the scope's `draggedKey` flip
  /// rebuilds every visible row, and nothing rebuilds per pointer move).
  bool _inDraggedSubtree(TKey? draggedKey) {
    if (draggedKey == null) {
      return false;
    }
    if (draggedKey == widget.nodeKey) {
      return true;
    }
    final tree = _reorder.treeController;
    TKey? current = tree.getParent(widget.nodeKey);
    while (current != null) {
      if (current == draggedKey) {
        return true;
      }
      current = tree.getParent(current);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scope = _ReorderableScope.maybeOf<TKey>(context);
    final hidden = _inDraggedSubtree(scope?.draggedKey);
    Widget content = widget.child;

    // Ask the policy HERE, not only at `startDrag`. A row that armed its
    // handles unconditionally would claim the gesture and then decline
    // it, so an app wanting that gesture for its own menu would never see
    // it. Asked ONCE and threaded into both the scope below and
    // `_semanticsActions`, rather than called again in each: a policy is
    // app code sitting on a per-row build path.
    final policy = _reorder.canReorder;
    final canDrag = policy == null || policy(widget.nodeKey);

    // Policy-flip backstop. `canReorder` is NOT a widget field, so
    // refusing the row that currently owns the session rebuilds it with
    // IDENTICAL widget fields and nothing else notices.
    //
    // THIS SITE IS LOAD-BEARING, not belt-and-braces. Disarming a handle
    // does not end the drag it started: the recognizer lives on this
    // State and keeps driving a session the policy has just forbidden,
    // so the row would stay at zero opacity with make-room re-targeting
    // until the finger lifts. Nothing else ends a session orphaned this
    // way.
    //
    // NOT the whole guarantee, and deliberately so: this site can only
    // fire when the row is rebuilt, and a dragged row that has
    // autoscrolled out of the cache region is held by the drag pin
    // without being rebuilt. `TreeReorderController._resolveAndNotify`
    // covers that case from the controller side, on every re-resolution
    // (pointer move, scroll notification, dwell tick).
    //
    // An earlier version of this comment named `updateDrag` as the
    // covering mechanism. It was not: `updateDrag` fires only on pointer
    // events, and the scenario is a finger parked in the autoscroll edge
    // zone producing none.
    //
    // This site remains worth having because it catches a refusal made
    // while the row is on screen and nothing is re-resolving, which is
    // the ordinary "edit mode toggle" case.
    if (!canDrag && _isDraggingThisRow) {
      _endOrphanedSessionAfterFrame();
    }

    // The row composes NOTHING around the caller's content: no gutter, no
    // `Row`, no reserved cell. It publishes a scope, and any
    // [TreeDragHandle] the caller placed inside arms itself from it.
    //
    // The scope's `canDrag` is what disarms a refused row's handles, and
    // the shape stays identical across a `canReorder` flip because the
    // handle nulls its `onPointerDown` rather than being omitted. That
    // property is enforced in `TreeDragHandle.build`.
    content = TreeRowDragScope(
      canDrag: canDrag,
      startDrag: _startDragFromHandle,
      child: content,
    );

    // Make-room hides the in-place dragged SUBTREE entirely: the gap
    // lift already accounts for every visible row of it, so their slots
    // close up underneath them and any residual paint (the dragged
    // row's or a descendant's) would overlap the rows shifting into
    // that space. The drag proxy is the subtree's representation.
    //
    // Applied AFTER the scope, so a handle is hidden along with the row
    // it belongs to. Wrapping only `widget.child` left a caller's grip
    // painting at full opacity in the closing slot, which is residual
    // paint of exactly the kind this hide exists to remove.
    //
    // Nesting is load-bearing in both directions. The drag surface may
    // sit INSIDE: `RenderOpacity` does not override `hitTest`, and an
    // in-flight drag routes to the row's recognizer regardless.
    // `Semantics`
    // must stay OUTSIDE: `RenderOpacity.visitChildrenForSemantics` drops
    // its subtree at zero alpha unless `alwaysIncludeSemantics` is set,
    // so hoisting this any further would silently strip the row's reorder
    // actions from the semantics tree for the length of every drag.
    content = Opacity(opacity: hidden ? 0.0 : 1.0, child: content);

    // Expose the reorder capability to assistive technology. Pointer
    // drags are unusable with a screen reader; these actions commit the
    // same controller mutations as the equivalent drops, gated by the
    // same canReorder / canAcceptDrop policies. Availability is computed
    // per build (structural changes rebuild affected rows); execution
    // fresh-computes indices so a stale action invocation degrades to a
    // no-op instead of a wrong move.
    final builtIn = _semanticsActions(canDrag: canDrag);
    Map<CustomSemanticsAction, VoidCallback>? actions;
    if (builtIn != null) {
      final built =
          _semanticsActionsBuilder?.call(widget.nodeKey, builtIn) ?? builtIn;
      // Tested AFTER the builder, not before: a row that is reorderable
      // but has no built-in action (a lone root, or every destination
      // vetoed) is exactly a case a consumer may want to contribute to,
      // and testing the built-in set would silently drop what it added.
      //
      // And never an EMPTY non-null map: `RenderObject` installs
      // `customSemanticsActions` whenever the map is non-null, and the
      // setter unconditionally raises the `customAction` bit, so an empty
      // map advertises a node that claims custom actions and offers none.
      if (built.isNotEmpty) {
        actions = built;
      }
    }

    // The WRAPPER is unconditional; only its payload varies. Emitting the
    // widget itself conditionally changed the row's shape every time its
    // action set emptied or `canReorder` flipped, re-inflating the whole
    // row subtree and disposing the app's `State` under it. Same hazard
    // and same reasoning as `TreeDragHandle` disarming by nulling its
    // `onPointerDown` rather than omitting itself.
    // A null payload adds no annotation, so the semantics tree is
    // identical to the version that omitted the wrapper.
    content = Semantics(customSemanticsActions: actions, child: content);

    return content;
  }

  /// The package's own reorder actions for this row, mapped to their
  /// handlers, or NULL when the row is not reorderable at all.
  ///
  /// Null and empty are different answers, and the difference is what a
  /// [ReorderSemanticsActionsBuilder] is allowed to see. Null is a hard
  /// refusal: `canReorder` said no, or the row is absent / mid-exit, so
  /// no consumer may contribute to it. Empty means the row IS
  /// reorderable but none of the four built-ins currently apply (a lone
  /// root, or every destination vetoed), which a consumer may legitimately
  /// add to.
  ///
  /// [canDrag] is the caller's already-computed `canReorder` answer,
  /// passed in rather than re-derived so a single build asks the app's
  /// policy exactly once.
  Map<CustomSemanticsAction, VoidCallback>? _semanticsActions({
    required bool canDrag,
  }) {
    final tree = _reorder.treeController;
    final key = widget.nodeKey;
    if (!canDrag) {
      return null;
    }
    final idx = tree.getIndexInParent(key);
    if (idx < 0) {
      return null;
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
      // Non-allocating: this runs on EVERY row build, and the list forms
      // of these queries copy the whole sibling list to be indexed once
      // and thrown away. Under a parent with many children that is a full
      // copy per visible row per build pass.
      final prev = tree.liveSiblingAt(parent, idx - 1);
      if (prev != null && _dropAllowed(prev, tree.liveChildCount(prev))) {
        actions[_moveIntoPreviousAction] = _performMoveIntoPrevious;
      }
    }
    return actions;
  }

  /// Whether the app's `canAcceptDrop` policy admits moving THIS row to
  /// `(newParent, index)`. Used to decide which semantics actions the row
  /// advertises; absence of a policy allows everything.
  bool _dropAllowed(TKey? newParent, int index) {
    final policy = _reorder.canAcceptDrop;
    if (policy == null) {
      return true;
    }
    return policy(
      movingKey: widget.nodeKey,
      newParent: newParent,
      index: index,
    );
  }

  // Execution delegates to the controller, which owns the mutation shape,
  // the live-space index convention, the policy re-check and the
  // `onReorder` report. Availability stays here: deciding which actions a
  // row ADVERTISES is presentation, and it already reads only public
  // controller queries.
  //
  // The controller also refuses these while a drag is in flight, which
  // matters more than it looks: the Semantics wrapper is deliberately
  // kept outside the Opacity that hides the dragged row (see build), so
  // these actions stay live on the row being dragged for the whole
  // gesture. Mutating there would leave the session resolving against
  // painted offsets that predate the change, and would silently shadow
  // the commit script's FLIP baseline, dropping the proxy handoff with
  // no error and no test signal.

  void _performMoveUp() {
    _reorder.moveUp(widget.nodeKey);
  }

  void _performMoveDown() {
    _reorder.moveDown(widget.nodeKey);
  }

  void _performMoveOut() {
    _reorder.moveOut(widget.nodeKey);
  }

  void _performMoveIntoPrevious() {
    _reorder.moveIntoPrevious(widget.nodeKey);
  }

  /// Walks up from this row to the first [ReorderRenderPort] ancestor,
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

  /// Installs [recognizer] for [event]'s pointer, on behalf of a
  /// [TreeDragHandle] that has just seen a pointer-down.
  ///
  /// This is [TreeRowDragScope.startDrag], and it follows
  /// `SliverReorderableListState.startItemDragReorder` including BOTH
  /// legs of its guard.
  void _startDragFromHandle(
    PointerDownEvent event,
    MultiDragGestureRecognizer recognizer,
  ) {
    if (_ownsSession()) {
      // Leg one, and the one that is easy to drop and impossible to
      // notice without two handles in one row.
      // `MultiDragGestureRecognizer.dispose` resolves its arena entries
      // and never calls `cancel()` or `end()` on its client, so replacing
      // the recognizer below would otherwise ORPHAN the live session: its
      // drag pin, its scroll listener and its autoscroll ticker would all
      // outlive the gesture with nothing left to end them.
      _cancelDrag();
    }
    // Leg two. Unconditional rather than Flutter's
    // `_recognizerPointer != event.pointer`, because NESTED handles
    // (a `TreeDragHandle` inside another) deliver two pointer-downs for
    // the SAME pointer, and that guard would leak the inner recognizer
    // by overwriting it. Disposing whatever is in hand is correct in both
    // cases: the new recognizer is about to take the pointer.
    _disposeRecognizer();
    _recognizer = recognizer
      ..onStart = _onDragStart
      ..addPointer(event);
  }

  /// The recognizer's `onStart`. Returns the [Drag] that will receive
  /// this gesture's updates, or null.
  ///
  /// Returning null when the controller refuses is NOT optional: a
  /// non-null [Drag] leaves a `MultiDragPointerState` driving a session
  /// that does not exist, and its eventual `end`/`cancel` would forward
  /// against whatever session happened to be live by then.
  Drag? _onDragStart(Offset globalPosition) {
    if (!_startDrag(globalPosition)) {
      return null;
    }
    return _RowDrag<TKey>(
      row: this,
      generation: _sessionGeneration!,
      startGlobal: globalPosition,
    );
  }

  /// Resolves the render surface and the scrollable from THIS ROW's
  /// context, never a handle's, which is what makes a handle inside a
  /// nested scrollable harmless: the tree still gets dragged, not the
  /// inner list.
  bool _startDrag(Offset globalPosition) {
    final renderPort = _findRenderPort(context);
    final scrollable = Scrollable.maybeOf(context);
    if (renderPort == null || scrollable == null) {
      return false;
    }
    // A false return is a policy refusal (canReorder) or a not-yet-laid-out
    // tree, decline the gesture quietly. Genuine wiring misuse
    // (cross-controller) still throws and should surface; the ancestor
    // widget's build assert catches it earlier in debug builds.
    //
    // The depth hint is the default column mapping: floor(x /
    // indentWidth), clamped by the resolver to the legal levels. A null
    // widget value resolves to the render-truth constant HERE, at drag
    // start, so a runtime indent change is honored without a rebuild.
    // Disabled for non-positive indents (nothing to divide by).
    final indent = _indentWidth ?? _reorder.treeController.indentWidth;
    final started = _reorder.startDrag(
      key: widget.nodeKey,
      renderPort: renderPort,
      scrollable: scrollable,
      pointerGlobal: globalPosition,
      depthForPointerX: indent > 0 ? (x) => (x / indent).floor() : null,
      proxyCrossOffset: _proxyCrossOffset,
      makeRoom: true,
      settleFromRelease: _dragProxyEnabled,
    );
    if (!started) {
      return false;
    }
    _isDraggingThisRow = true;
    _sessionGeneration = _reorder.dragGeneration;
    _onDragStartCallback(widget.nodeKey, widget.child);
    return true;
  }

  /// Whether this row still OWNS the controller's drag session, and (when
  /// [generation] is supplied) whether it is still the SAME session the
  /// calling gesture started.
  ///
  /// The local [_isDraggingThisRow] flag alone is not enough: an external
  /// `cancelDrag()` (or a second gesture silently replacing the session
  /// via `startDrag`) clears/replaces the controller session without
  /// resetting the row-local flag, and a later gesture callback from this
  /// row would then commit or cancel a DIFFERENT session.
  ///
  /// Nor is `draggedKey == nodeKey`: the same node dragged twice is
  /// indistinguishable through it, which is exactly what
  /// [TreeReorderController.dragGeneration] exists to answer. An external
  /// `cancelDrag` plus a fresh `startDrag` for the SAME key leaves both
  /// `isDragging` and `draggedKey` unchanged while this row's recognizer
  /// stays alive and routed, so its release would otherwise commit the
  /// REPLACEMENT session. Comparing [_sessionGeneration] against the
  /// controller's is what stops it. Clears the stale local state when
  /// ownership is lost.
  ///
  /// The optional [generation] is DEFENCE, not a demonstrated guard, and
  /// it is worth being precise about which. It can only differ from
  /// [_sessionGeneration] if a stale [_RowDrag] is still receiving
  /// callbacks after this row started a newer session, and that is
  /// unreachable while a row owns AT MOST ONE recognizer: installing a
  /// replacement disposes the old one, which removes its pointer route,
  /// so its `Drag` never hears from the framework again. It is kept
  /// because that at-most-one invariant lives in
  /// [_startDragFromHandle] rather than in the type system, and this is
  /// what would catch a change to it.
  bool _ownsSession([int? generation]) {
    if (!_isDraggingThisRow) {
      return false;
    }
    final mine = _sessionGeneration;
    if (mine == null ||
        _reorder.dragGeneration != mine ||
        _reorder.draggedKey != widget.nodeKey) {
      _isDraggingThisRow = false;
      _sessionGeneration = null;
      return false;
    }
    return generation == null || generation == mine;
  }

  // End/cancel do NOT call the owner's drag-UI teardown directly: the
  // controller's notifyListeners (fired by endDrag/cancelDrag) drives
  // _onControllerChanged, then _onDragEnd on the listening state. A second
  // direct call would be a redundant no-op setState, and teardown must
  // stay single-owner. (_ownsSession guarantees the cached controller
  // holds THIS row's session, and the owner state always listens to its
  // current controller.)

  // The three [_RowDrag] forwarders. Each re-validates the generation its
  // gesture was born under, so a superseded pointer's late callback is a
  // no-op rather than a foreign commit.

  void _forwardUpdate(int generation, Offset globalPosition) {
    if (!_ownsSession(generation)) {
      return;
    }
    _reorder.updateDrag(globalPosition);
  }

  void _forwardEnd(int generation) {
    if (!_ownsSession(generation)) {
      return;
    }
    _isDraggingThisRow = false;
    _sessionGeneration = null;
    _reorder.endDrag();
  }

  void _forwardCancel(int generation) {
    if (!_ownsSession(generation)) {
      return;
    }
    _cancelDrag();
  }

  /// Cancels this row's session, if it still owns one. Teardown of the
  /// drag UI follows from the controller's notification, not from here.
  void _cancelDrag() {
    if (!_ownsSession()) {
      return;
    }
    _isDraggingThisRow = false;
    _sessionGeneration = null;
    _reorder.cancelDrag();
  }
}

/// Overlay entry rendering the floating drag preview.
///
/// Repositions on EVERY pointer move via
/// [TreeReorderController.pointerPosition], the per-move channel that
/// exists precisely because the controller's [ChangeNotifier] channel is
/// coalesced to semantic target changes. Anchored at the grab point
/// ([TreeReorderController.dragProxyGeometry]) so the preview stays
/// "held" where the user picked the row up.
///
/// POSITION is per-move; CONTENT is session-frozen. The proxy content
/// (custom builder output, the dragged row's captured child, the
/// descendant clone stack) is derived once in [build]; the entry is
/// created per session, after the session captures, and passed through
/// the pointer builder's `child:` slot, so pointer moves reposition an
/// identical subtree instead of rebuilding it. A [RepaintBoundary]
/// around the content makes the reposition offset-only compositing.
/// Dynamic proxy content self-drives: see
/// [SliverReorderableTree.dragProxyBuilder].
class _DragProxy<TKey> extends StatelessWidget {
  const _DragProxy({
    required this.reorderController,
    required this.proxyBuilder,
    required this.proxyIndent,
    required this.rowChildResolver,
    required this.stackResolver,
    required this.nodeBuilder,
    required this.scrollableFinder,
  });

  final TreeReorderController<TKey> reorderController;
  final Widget Function(BuildContext context, TKey key, Widget? rowChild)?
  proxyBuilder;

  /// The animated indent applied as left padding to the proxy content,
  /// default and [SliverReorderableTree.dragProxyBuilder] output alike.
  /// The padding narrows the content to `viewportWidth - indent`,
  /// matching the real row's render-applied layout width at the tracked
  /// depth, so text wrapping matches at handoff.
  final ValueListenable<double> proxyIndent;

  final Widget? Function() rowChildResolver;

  /// Resolves the frozen descendant stack captured at drag start, or
  /// null for a single-row drag. See
  /// `_SliverReorderableTreeState._dragStack`.
  final List<({TKey key, int depth, double extent, double relativeIndent})>?
  Function()
  stackResolver;

  /// Builds a descendant clone with the row's captured ORIGINAL depth.
  /// Built ONCE PER DRAG SESSION against the overlay's context (the
  /// content is hoisted out of the pointer builder, so pointer moves
  /// never re-invoke it), unlike the dragged row's captured widget
  /// instance; the [SliverReorderableTree.showDragProxy]
  /// overlay-ancestry contract covers both, and a handle inside a clone
  /// finds no [TreeRowDragScope] and is inert.
  final Widget Function(BuildContext context, TKey key, int depth) nodeBuilder;

  final ScrollableState? Function() scrollableFinder;

  @override
  Widget build(BuildContext context) {
    // SESSION-CONSTANT capture + content derivation, ONCE per entry.
    // The overlay entry is created per session (`_ensureProxy` only from
    // `_onDragStart`, after the captures; `_removeProxy` on every session
    // end path), so this build runs with the live session's frozen state.
    // The pointer channel below only repositions; hoisting the content
    // out of its builder, the same `child:` pattern the indent builder
    // below already uses, is what keeps `proxyBuilder` and the
    // per-descendant `nodeBuilder` clones from re-running on every
    // pointer move (`drag_proxy_move_rebuild_test.dart`).
    final capturedKey = reorderController.draggedKey;
    final geometry = reorderController.dragProxyGeometry;
    final rowChild = rowChildResolver();
    if (capturedKey == null || geometry == null) {
      // Defensive degenerate case (reassemble-window rebuild with no
      // session): render nothing until the entry is removed.
      return const SizedBox.shrink();
    }
    Widget content;
    if (proxyBuilder != null) {
      content = proxyBuilder!(context, capturedKey, rowChild);
    } else if (rowChild != null) {
      content = rowChild;
    } else {
      return const SizedBox.shrink();
    }

    // Subtree stack: the dragged row's clone first (pinned to its
    // grab extent, exactly the band the single-row proxy used),
    // then one fresh clone per captured descendant, height-pinned
    // and padded by its RELATIVE indent. The stack sits inside the
    // animated proxy indent below, so retargeting moves it as one
    // unit and relative structure is preserved by construction.
    final stack = stackResolver();
    double bandHeight = geometry.rowExtent;
    if (stack != null && geometry.rowExtent > 0) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: geometry.rowExtent, child: content),
          for (final row in stack)
            SizedBox(
              height: row.extent,
              child: Padding(
                padding: EdgeInsets.only(left: row.relativeIndent),
                child: nodeBuilder(context, row.key, row.depth),
              ),
            ),
        ],
      );
      for (final row in stack) {
        bandHeight += row.extent;
      }
    }
    // The default proxy's 90% opacity covers the WHOLE stack (a
    // custom proxyBuilder keeps styling only the dragged row's
    // portion; descendant clones stack below its output unchanged).
    if (proxyBuilder == null) {
      content = Opacity(opacity: 0.9, child: content);
    }

    // The RepaintBoundary makes repositioning offset-only compositing:
    // without it, every `Positioned` move re-rasterizes the whole proxy
    // band with the parent picture; with it, a clean child's retained
    // layer is just re-offset (`PaintingContext._compositeChild`).
    // Indent-animation frames still re-raster inside the boundary,
    // those pixels genuinely change. Matches the package's
    // `addRepaintBoundaries` convention for rows.
    final Widget positionedChild = IgnorePointer(
      child: RepaintBoundary(
        child: ValueListenableBuilder<double>(
          valueListenable: proxyIndent,
          builder: (context, indent, child) {
            return Padding(
              padding: EdgeInsets.only(left: indent),
              child: child,
            );
          },
          child: content,
        ),
      ),
    );

    return ValueListenableBuilder<Offset?>(
      valueListenable: reorderController.pointerPosition,
      builder: (context, pointer, child) {
        if (pointer == null) return const SizedBox.shrink();
        // Session guard: the entry lifecycle is per-session, so a live
        // key that differs from the captured one means this entry
        // outlived its session, render nothing rather than another
        // session's content. (Strictly stronger than the old
        // `draggedKey == null` guard: same shrink on null, plus shrink
        // on a foreign session.)
        if (reorderController.draggedKey != capturedKey) {
          return const SizedBox.shrink();
        }
        // The scrollable/viewport resolution stays PER MOVE on purpose:
        // the viewport can shift mid-drag (keyboard inset, window
        // resize), and a defunct scrollable must shrink the proxy.
        final scrollable = scrollableFinder();
        if (scrollable == null) return const SizedBox.shrink();
        final viewport = scrollable.context.findRenderObject() as RenderBox?;
        if (viewport == null || !viewport.attached) {
          return const SizedBox.shrink();
        }

        // Horizontal: span the viewport (the row's own width), with the
        // animated indent applied as left padding INSIDE the full-width
        // band, narrowing the content the same way the render layer
        // narrows the real row. Vertical: the pointer minus the grab
        // offset, in global space, pixel distances survive the global
        // mapping unscaled.
        final viewportGlobalLeft = viewport.localToGlobal(Offset.zero).dx;
        return Stack(
          children: [
            Positioned(
              left: viewportGlobalLeft,
              top: pointer.dy - geometry.grabDy,
              width: viewport.size.width,
              height: bandHeight > 0 ? bandHeight : null,
              child: child!,
            ),
          ],
        );
      },
      child: positionedChild,
    );
  }
}
