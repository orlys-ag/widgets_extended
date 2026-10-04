/// The narrow contract the board's collaborators use to reach the render
/// object: geometry, scroll positions, and the two pin operations a drag
/// session needs.
///
/// `RenderBoardViewport.attach` registers itself through
/// `BoardControllerInternals.attachRenderPort`, whose parameter type is this
/// interface. Every member is declared here even where its consumer does
/// not exist yet: the interface is what a test fakes, and adding a member
/// later breaks every fake written against it.
library;

import 'package:flutter/widgets.dart';

import '_board_span.dart';

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

  /// The cell that PAINTS under a viewport-paint-space point: a frozen
  /// cell where its band paints, a scrolled one elsewhere, read through
  /// the geometry as it paints mid track resize. Null when no cell paints
  /// there, past the lattice or past the viewport beside a band, or when
  /// the board has not been laid out.
  ///
  /// All coordinates on this interface are viewport-paint space; see
  /// Coordinate Spaces.
  ({int row, int col})? cellAt(Offset local);

  /// [cellAt], answered only for a point inside a FROZEN band on at least
  /// one axis, and null everywhere else.
  ({int row, int col})? frozenCellAt(Offset local);

  /// The viewport-paint-space rect a cell paints at, a frozen cell in its
  /// band, or null when the board has not been laid out or either index
  /// is outside its axis.
  Rect? rectOfCell(int row, int col);

  /// The topmost item painted under a viewport-paint-space point, or null
  /// when there is none or a frozen cell painted above it covers the
  /// point: a band hides what scrolls beneath it. Excludes items that are
  /// animating out AND the item currently being dragged: neither can be a
  /// tap target or a drop target.
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

  /// The viewport-paint-space point of [paintRect]'s content-LEADING
  /// corner: on each axis, the rect's near edge (left, top) where that
  /// axis runs forward and its far edge (right, bottom) where it is
  /// reversed, because a reversed axis paints content's leading edge last.
  ///
  /// The one rule for turning a painted rect into a content-space START:
  /// [trackSpaceAt] of this point is the rect's leading track coordinate,
  /// and [contentDeltaFromPaint] of the difference between two rects'
  /// corners is the content-space difference of their leads. A plain
  /// top-left serves only where both axes run forward; on a reversed one
  /// it is the TRAILING corner.
  Offset leadingCornerOf(Rect paintRect);

  /// The nearest cell to a pointer among the cells of the region the
  /// point is over, per axis: a frozen band's cells over a band, and
  /// elsewhere the scrolled cells that show between the bands, or every
  /// cell where none of them shows. The coordinate is rounded by the rule
  /// `BoardSnap.track`'s quantize applies. A pure cell query: it excludes
  /// nothing, because it names no item.
  ({int row, int col}) resolveDropCell(Offset local);

  /// Track-space coordinate under a viewport-paint pointer: the integer
  /// track plus the fraction into it, per axis, of the lattice as it
  /// PAINTS: a frozen band's tracks where the band paints, the scrolled
  /// tracks between the bands through the geometry mid track resize.
  ///
  /// CLAMPED, so a pointer past the lattice samples an edge rather than
  /// nothing: past a band's viewport edge, the band's outer end; in the
  /// scrolled region, the unfrozen tracks, which with no band is
  /// `[0, trackCount]`, inclusive at the top because
  /// `offsetOfFraction(trackCount)` is the legal trailing endpoint.
  ///
  /// Null ONLY when there is no lattice to sample: the board is not laid
  /// out, or an axis has `trackCount` 0.
  ({double row, double col})? trackSpaceAt(Offset local);

  /// The paint-space point [local] mapped on each axis in BOTH lattices
  /// that axis can paint: `painted` is the coordinate [trackSpaceAt]
  /// answers, `scrolled` the scrolled tracks' coordinate at the point
  /// whether or not a frozen band paints over it, bounded by the lattice
  /// that paints there, and the remaining fields
  /// the band geometry a drop needs, each as [BoardAxisSample] documents
  /// it. Null exactly when [trackSpaceAt] is. A null sample leaves the
  /// drag session's target UNCHANGED and installs no gap.
  ///
  /// This is the ONE producer of a fractional track coordinate.
  ///
  /// [verticalPixels] and [horizontalPixels] sample the point as the
  /// board would at those scroll offsets, each null for the board's own:
  /// a frozen band reads no offset, and the scrolled coordinate and the
  /// two visible bounds read the one given. Internal-use for the drag
  /// session, which samples its lift point again at the lift's offsets
  /// when the axis configs change under it.
  ({BoardAxisSample row, BoardAxisSample col})? trackSampleAt(
    Offset local, {
    double? verticalPixels,
    double? horizontalPixels,
  });

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

  /// The viewport-paint-space rect the scrolled tracks show through: the
  /// viewport minus every frozen band. [Rect.zero] before the first
  /// layout. The drag layer's autoscroll zones are measured from its
  /// edges, so a pointer over a band chooses a frozen track instead of
  /// scrolling.
  Rect get scrolledRegion;

  /// Drops every mounted cell's cached measurement and schedules one
  /// layout that re-measures each. The whole-board arm of the cell
  /// measurement cache; the per-cell arm is the cell host's poke. See
  /// `BoardController.invalidateCellMeasurements`.
  void invalidateCellMeasurements();
}
