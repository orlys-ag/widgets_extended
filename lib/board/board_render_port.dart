/// The narrow contract the board's collaborators use to reach the render
/// object: geometry, scroll positions, and the two pin operations a drag
/// session needs.
///
/// `RenderBoardViewport.attach` registers itself through
/// `BoardController.attachRenderPort`, whose parameter type is this
/// interface. Every member is declared here even where its consumer does
/// not exist yet: the interface is what a test fakes, and adding a member
/// later breaks every fake written against it.
library;

import 'package:flutter/widgets.dart';

/// Internal contract: external code should not implement this. Public only
/// so the production render object can implement it across library
/// boundaries and tests can fake it. Same rationale as
/// `reorder_render_port.dart:24`.
abstract interface class BoardRenderPort<TKey> {
  /// Whether the render object has been laid out at least once.
  ///
  /// Read before anything that measures from [viewportDimension], which is
  /// `assert(hasSize); return size;` on the base class and throws a
  /// `StateError` in release when it has not.
  bool get isLaidOut;

  /// The size of the visible area.
  Size get viewportDimension;

  /// Whether this render object is currently driven by [boardController]
  /// (identity comparison). Shape and doc from
  /// `reorder_render_port.dart:63`, whose rationale applies unchanged:
  /// "a reorder controller must only operate on a render object displaying
  /// the same tree it mutates on drop" (`reorder_render_port.dart:61`).
  bool drivesController(Object boardController);

  /// Pins [key]'s child against unmounting until [unpinItem]. Idempotent.
  /// The DRAG PIN, owned by the drag session; at most one is live.
  /// Shape from `reorder_render_port.dart:124`
  /// and `reorder_render_port.dart:127`, whose doc states the same reason:
  /// "the drag gesture's recognizer lives on the row's own `State`, so
  /// evicting the row would orphan the session"
  /// (`reorder_render_port.dart:121`).
  void pinItem(TKey key);

  /// Releases the pin [pinItem] took. Idempotent, and a no-op for a key
  /// that is not the pinned one.
  void unpinItem(TKey key);

  /// The cell under a viewport-paint-space point, or null when the point
  /// is outside the lattice or the board has not been laid out.
  ///
  /// All coordinates on this interface are viewport-paint space; see
  /// Coordinate Spaces.
  ({int row, int col})? cellAt(Offset local);

  /// The cell of a FROZEN band under a viewport-paint-space point, or
  /// null outside every band.
  ({int row, int col})? frozenCellAt(Offset local);

  /// The viewport-paint-space rect of a cell, or null when the board has
  /// not been laid out or either index is outside its axis.
  Rect? rectOfCell(int row, int col);

  /// The item under a viewport-paint-space point. Excludes items that
  /// are animating out AND the item currently being dragged: neither can
  /// be a tap target or a drop target.
  TKey? itemAt(Offset local);

  /// The viewport-paint-space rect of an item, or null when the board
  /// has not been laid out or [key] is not live.
  Rect? rectOfItem(TKey key);

  /// [rectOfItem] shifted by the item's PAINTED shift: the coordinator's
  /// composed offset (a slide's lead plus the held make-room delta)
  /// converted to paint space. Where the item is drawn this instant, in
  /// the same space as every other rect here. Null exactly when
  /// [rectOfItem] is.
  Rect? paintedRectOfItem(TKey key);

  /// Converts a per-item DELTA between viewport-paint space and content
  /// space: per axis, negated when that axis is reversed, unchanged
  /// otherwise. An involution, so the one function serves both
  /// directions. The animation coordinator stores content-space deltas,
  /// so a paint-space difference (proxy corner minus painted corner)
  /// passes through here before an install.
  Offset contentDeltaFromPaint(Offset paintDelta);

  /// Nearest cell for a pointer, clamped into the lattice: the
  /// fractional track-space coordinate rounded per axis, by the same
  /// rule `BoardSnap.track`'s quantize applies, so the cell route and
  /// the [trackSpaceAt] route land an anchor on the same cell. A pure
  /// cell query: it excludes nothing, because it names no item.
  ({int row, int col}) resolveDropCell(Offset local);

  /// Track-space coordinate under a viewport-paint pointer: the integer
  /// track plus the fraction into it, per axis. CLAMPED into
  /// `[0, trackCount]` on each axis exactly as [resolveDropCell] is, so a
  /// pointer beyond the last track's trailing edge samples that edge
  /// rather than nothing; the top of the range is inclusive because
  /// `offsetOfFraction(trackCount)` is the legal trailing endpoint.
  ///
  /// Null ONLY when there is no lattice to sample: the board is not laid
  /// out, or an axis has `trackCount` 0. A null sample leaves the drag
  /// session's target UNCHANGED and installs no gap.
  ///
  /// This is the ONE producer of a fractional track coordinate.
  ({double row, double col})? trackSpaceAt(Offset local);

  /// Converts a GLOBAL pointer position into this port's viewport-paint
  /// space, which every spatial query above takes. Internal-use for the
  /// drag session, whose pointer events arrive global.
  Offset globalToPaintLocal(Offset global);

  /// The vertical scroll position, or null when the offset driving this
  /// axis is not a [ScrollPosition].
  ScrollPosition? get verticalPosition;

  /// The horizontal scroll position. See [verticalPosition].
  ScrollPosition? get horizontalPosition;

  /// The extent of the frozen band on [axis], measured from the leading
  /// viewport edge. 0.0 when the board carries no frozen tracks on that
  /// axis.
  double frozenInsetOf(Axis axis);

  /// Drops every mounted cell's cached measurement and schedules one
  /// layout that re-measures each. The whole-board arm of the cell
  /// measurement cache; the per-cell arm is the cell host's poke. See
  /// `BoardController.invalidateCellMeasurements`.
  void invalidateCellMeasurements();
}
