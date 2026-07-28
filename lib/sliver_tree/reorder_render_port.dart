/// The narrow render-layer surface a drag-and-drop reorder session needs.
///
/// Keeping reorder code off the concrete `RenderSliverTree` avoids a
/// variance cast, keeps sliver layout protocol out of gesture
/// orchestration, and lets the controller be tested without a full widget
/// tree. Same idiom as the codebase's other render-boundary contracts,
/// `AnimationReader` and `TreeRenderHost`.
///
/// `RenderSliverTree` is the production implementation; tests exercise the
/// reorder controller against scripted fakes.
library;

import 'package:flutter/animation.dart' show Curve;

/// Render-layer contract consumed by [TreeReorderController].
///
/// All y-coordinates are **sliver-local**: distance from the start of the
/// tree sliver's scroll extent (first tree row at 0). Viewport scroll space
/// differs by [precedingScrollExtent].
///
/// **Internal contract** — external code should not implement this
/// interface. Its shape follows the reorder controller's needs and may
/// change without notice; it is public only so the production render object
/// can implement it across library boundaries and tests can fake it.
abstract interface class ReorderRenderPort<TKey> {
  /// Whether the render object has completed at least one layout pass.
  ///
  /// Geometry-reading members below are only meaningful when this is true;
  /// a drag cannot start against an un-laid-out tree (there are no painted
  /// rows to resolve).
  bool get isLaidOut;

  /// The scroll extent of all slivers preceding the tree in its viewport,
  /// or `0.0` when [isLaidOut] is false.
  ///
  /// Adding this converts sliver-local y to viewport scroll-space y (and
  /// subtracting, the reverse).
  double get precedingScrollExtent;

  /// Whether this render object is currently driven by [treeController]
  /// (identity comparison).
  ///
  /// Guards the wiring: a reorder controller must only operate on a render
  /// object displaying the same tree it mutates on drop.
  bool drivesController(Object treeController);

  /// Finds the live (non-pending-deletion) visible row whose painted
  /// sliver-local range contains [scrollY], falling back to the last live
  /// row when [scrollY] sits past the bottom of the tree. Returns `null`
  /// when no live row exists.
  ///
  /// Painted offsets include any active FLIP slide delta — this is the
  /// row under the pointer as the user sees it, not as the structure says.
  ({TKey key, double paintedOffset, double extent})? findRowAtPaintedY(
    double scrollY,
  );

  /// Pins [key] against stale eviction until [unpinNode]. Idempotent.
  ///
  /// The reorder controller pins the dragged row for the session's
  /// lifetime: the drag gesture lives on the row's own detector, so
  /// evicting the row would orphan the session.
  void pinNode(TKey key);

  /// Removes the eviction pin for [key]. Idempotent.
  void unpinNode(TKey key);

  /// Captures the current painted offsets so the next layout pass can
  /// install a FLIP slide from them to the post-mutation offsets. No-op
  /// when [isLaidOut] is false.
  ///
  /// [baselineYOverrides] replaces the captured sliver-local y for the
  /// given keys before staging. The reorder controller uses it for the
  /// proxy drop-settle: overriding the dragged row's entry to the RELEASE
  /// position makes the commit FLIP carry the row from where the floating
  /// proxy was let go into its new slot, instead of from its pre-drag
  /// slot. Keys absent from the snapshot are ignored.
  ///
  /// Caller contract (first-wins staging): every successful stage MUST be
  /// followed by a structural mutation that triggers a layout in the same
  /// frame — see `RenderSliverTree.beginSlideBaseline` for the full
  /// protocol.
  void beginSlideBaseline({
    required Duration duration,
    required Curve curve,
    Map<TKey, double>? baselineYOverrides,
  });
}
