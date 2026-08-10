/// Declarative reorder configuration: one nullable object instead of a
/// parameter per knob on every constructor.
///
/// Passing a non-null [TreeReorderConfig] IS enabling reorder, and by
/// default that is all the wiring a row needs: [
/// TreeReorderConfig.buildDefaultDragHandles] installs a long-press drag
/// over the whole row, the way `ReorderableListView` does. Set it false
/// to place [TreeDragHandle]s yourself, anywhere in the row you like.
library;

import 'package:flutter/widgets.dart';

import 'sliver_reorderable_tree.dart';
import 'tree_drag_handle.dart';
import 'tree_reorder_controller.dart';

/// Everything a declarative tree needs to support drag-and-drop reorder.
///
/// Null disables reorder at zero cost. Non-null enables it, and the only
/// required member is [onReorder]: the gesture, its affordance, the drag
/// proxy, autoscroll and hover-to-expand all have working defaults.
///
/// The config's PRESENCE is fixed when the widget is created. Its
/// CONTENTS are live on every rebuild. The drag tunings
/// ([autoExpandDelay], [autoScrollEdgeZone], [autoScrollMaxVelocity])
/// are captured once per drag session at drag start, so a changed value
/// applies from the next drag rather than retuning a live one.
///
/// To toggle reorder at runtime, keep the config and return false from
/// [canReorder], which disarms each refused row's handles rather than
/// leaving a grip that declines.
class TreeReorderConfig<TKey> {
  const TreeReorderConfig({
    required this.onReorder,
    this.canReorder,
    this.canAcceptDrop,
    this.semanticsActionsBuilder,
    this.buildDefaultDragHandles = true,
    this.indentWidth,
    this.showDragProxy = true,
    this.dragProxyBuilder,
    this.hapticsOnDrag = false,
    this.autoExpandDelay = const Duration(milliseconds: 700),
    this.autoScrollEdgeZone = 48.0,
    this.autoScrollMaxVelocity = 1200.0,
    this.onControllerCreated,
  });

  /// Reports a committed reorder. See
  /// [TreeReorderController.onReorder] for the index convention, which is
  /// live-space and names a position in the FINAL child list.
  ///
  /// The widget's own input collection stays authoritative, so a move
  /// this handler does not record is reverted by the next sync. That is
  /// the rejection mechanism, not a bug. An async handler must record
  /// optimistically BEFORE awaiting.
  final void Function(TKey key, TKey? newParent, int index) onReorder;

  /// Rows for which this returns false cannot be dragged.
  ///
  /// Every handle in a refused row is DISARMED: its `onPointerDown` is
  /// null, so no recognizer is ever built, no arena is joined, and the
  /// gesture is free for the app's own menu. The row's widget SHAPE is
  /// unchanged, which matters more than it sounds: a shape that varied
  /// with this policy would fail `Widget.canUpdate` and re-inflate the
  /// row subtree on every toggle, disposing whatever `State` the app
  /// keeps there.
  ///
  /// A disarmed handle still RENDERS, because the package does not
  /// decide what your grip looks like. To hide it, and to keep it inert
  /// while reserving its space, read
  /// [TreeRowDragScope.canDrag] from a `Builder` inside the row; the
  /// idiom is written out on that member.
  ///
  /// Refusing the row that currently owns a drag ends that drag on the
  /// next re-resolution: a pointer move, a scroll notification, or the
  /// row's own rebuild, whichever comes first.
  ///
  /// Consulted on every row build as well as at drag start, so it must be
  /// a cheap, pure function of state the CONTROLLER can observe. A policy
  /// keyed on app-private state stays stale until something rebuilds the
  /// row.
  final bool Function(TKey key)? canReorder;

  /// Filters drop destinations. Also shapes the zones: a row that cannot
  /// take children collapses from a three-zone split to a two-zone one.
  ///
  /// The shaping query is `(newParent: thatRow, index: 0)`, which matters
  /// if you write a pin-the-first-slot policy. Refusing index 0 under a
  /// container withdraws that row's `into` zone entirely, because `into`
  /// has exactly one index to offer and 0 is it. The row keeps a clean
  /// two-zone midpoint split, and slots 1..n under it stay reachable by
  /// pointing at its children instead. This is why the probe passes a
  /// concrete 0 rather than null: the zones downstream commit to index 0
  /// unconditionally, so a shape-only answer would promise an `into` zone
  /// that then resolves to nothing under the pointer.
  ///
  /// [index] is declared nullable but is always a concrete position in
  /// practice: no call site in this package passes null. It stays
  /// nullable because narrowing it to `required int` is a BREAKING change
  /// rather than a tightening, and not for the reason contravariance
  /// suggests. A callback literal written `({required movingKey,
  /// newParent, index}) => ...` infers `index` as optional, and an
  /// optional parameter cannot satisfy a required one, so every existing
  /// policy in every consumer would stop compiling to delete a branch
  /// none of them can reach.
  ///
  /// A policy may therefore answer null without consulting the index. If
  /// a genuine shape-only query is ever wanted, it should get its own
  /// callback: overloading null onto a parameter whose entire meaning is
  /// a position is what produced the dead-zone regression described
  /// above.
  final bool Function({required TKey movingKey, TKey? newParent, int? index})?
  canAcceptDrop;

  /// Transforms each row's assistive-technology reorder actions.
  final ReorderSemanticsActionsBuilder<TKey>? semanticsActionsBuilder;

  /// Whether the package wraps each row in a [TreeDelayedDragHandle],
  /// making the whole row draggable after a long press.
  ///
  /// Defaults to true, matching
  /// `ReorderableListView.buildDefaultDragHandles` and preserving the
  /// gesture this package has always installed. A uniform long-press
  /// default is predictable, needs no platform reasoning to understand,
  /// and does not change your layout as a side effect of turning reorder
  /// on. The cost is that desktop users get no visible affordance and a
  /// mouse long-press reads as lag, so DESKTOP-TARGETED APPS SHOULD SET
  /// THIS FALSE and place their own grip.
  ///
  /// Set false to decide the affordance yourself. The row is still
  /// wrapped: it still hides itself while dragged, still exposes the
  /// reorder semantics actions, and is still a drop TARGET. What it loses
  /// is a pointer gesture, which you put back by placing a
  /// [TreeDragHandle] (immediate, for a dedicated grip) or a
  /// [TreeDelayedDragHandle] (press-and-hold, safe around a whole row)
  /// anywhere inside the row:
  ///
  /// ```dart
  /// itemBuilder: (context, view) {
  ///   return Card(
  ///     child: Column(
  ///       children: <Widget>[
  ///         const TreeDragHandle(
  ///           child: SizedBox(height: 32.0, width: double.infinity),
  ///         ),
  ///         content,
  ///       ],
  ///     ),
  ///   );
  /// }
  /// ```
  ///
  /// Placement, size and appearance are entirely yours, and there may be
  /// more than one handle per row. The package reserves no gutter and
  /// composes nothing around your row.
  ///
  /// This package ships no platform-adaptive default. Branching belongs
  /// where the platform is actually known: a `Theme.of(context).platform`
  /// switch in your own config honours an app's deliberate override,
  /// which a widgets-layer `defaultTargetPlatform` read cannot.
  ///
  /// Treat this as FIXED for a row's lifetime. Flipping it changes the
  /// row's widget shape, so `Widget.canUpdate` fails and every row
  /// subtree is re-inflated, disposing whatever `State` your builder
  /// keeps there. [canReorder] is the runtime knob, and is shaped to
  /// avoid exactly that.
  final bool buildDefaultDragHandles;

  /// Pixels per depth level for mapping pointer x to a drop depth at
  /// subtree boundaries. Null (the default) uses the widget's own
  /// `indentWidth`, which is the indent it actually renders; these are
  /// the same constant read in opposite directions, and letting them
  /// drift keys depth selection to a column that appears nowhere on
  /// screen. Set it only when rows bake their own indent in
  /// `itemBuilder` (widget `indentWidth` 0).
  final double? indentWidth;

  /// See [SliverReorderableTree.showDragProxy].
  final bool showDragProxy;

  /// See [SliverReorderableTree.dragProxyBuilder].
  final Widget Function(BuildContext context, TKey key, Widget? rowChild)?
  dragProxyBuilder;

  /// See [SliverReorderableTree.hapticsOnDrag].
  final bool hapticsOnDrag;

  /// Hover-to-open delay for a collapsed drop target. Live on rebuild;
  /// captured once per drag session, so a change applies from the next
  /// drag.
  final Duration? autoExpandDelay;

  /// Autoscroll edge band. Live on rebuild; captured per drag session.
  final double autoScrollEdgeZone;

  /// Peak autoscroll velocity. Live on rebuild; captured per drag
  /// session.
  final double autoScrollMaxVelocity;

  /// Hands back the internally owned reorder controller, right after it
  /// is created.
  ///
  /// The supported way to reach what the config cannot express: reading
  /// `isDragging` for chrome, `cancelDrag()`, subscribing to
  /// `pointerPosition` for a custom overlay, or driving [
  /// TreeReorderController.moveTo] programmatically. Do NOT dispose it.
  final void Function(TreeReorderController<TKey> controller)?
  onControllerCreated;
}
