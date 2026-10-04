/// Internal: what a drag currently resolves to, and the snap-to-span rule
/// that produces it.
///
/// `BoardDropTarget` and `BoardDragKind` are re-exported from
/// `board_drag_controller.dart`, because `currentTarget`'s type is
/// unnameable by app code otherwise; the resolver itself is not.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '_board_span.dart';
import 'board_config.dart';

/// Which drag a session is running. Resolved ONCE at `startDrag` from the
/// handle's `edge` and `axis` arguments, carried on every
/// [BoardDropTarget] the session produces, and read by `endDrag` to
/// decide which callback fires.
enum BoardDragKind {
  move,
  resizeRowStart,
  resizeRowEnd,
  resizeColStart,
  resizeColEnd,
}

/// What a drag currently resolves to: a whole prospective SPAN, not a
/// cell.
@immutable
class BoardDropTarget {
  const BoardDropTarget({required this.span, required this.kind});

  /// Track space, and already snapped: this is exactly what `endDrag`
  /// reports, so the previewed span and the committed one cannot differ.
  final BoardSpan span;

  final BoardDragKind kind;

  /// The leading cell of [span], for cell-shaped consumers: the track
  /// its start is IN on each axis, by the one start rule
  /// ([trackIndexOf]), which a start one ulp below a whole track reads as
  /// that track and the span's integer components do not. DERIVED,
  /// never stored.
  ({int row, int col}) get cell {
    return (
      row: trackIndexOf(span.startTrackOn(Axis.vertical)),
      col: trackIndexOf(span.startTrackOn(Axis.horizontal)),
    );
  }

  /// VALUE equality: the re-target notification compares the previous
  /// target with the new one and notifies only when they differ, so
  /// without this every pointer move would notify.
  @override
  bool operator ==(Object other) {
    return other is BoardDropTarget &&
        other.span == span &&
        other.kind == kind;
  }

  @override
  int get hashCode {
    return Object.hash(span, kind);
  }

  @override
  String toString() {
    return "BoardDropTarget($kind, $span)";
  }
}

/// One paint-space point sampled on both axes: the non-null answer of
/// `BoardRenderPort.trackSampleAt`.
typedef BoardPointSample = ({BoardAxisSample row, BoardAxisSample col});

/// One anchor's samples at the lift, per axis. A component is null where
/// that axis has no lift sample to measure a displacement from, which
/// makes the axis moved from the first resolve.
typedef BoardLiftSamples = ({BoardAxisSample? row, BoardAxisSample? col});

/// The band an item is pinned in on each axis, as a half-open track
/// range, or null where it scrolls on that axis.
typedef BoardPins = ({
  ({int start, int end})? row,
  ({int start, int end})? col,
});

/// The snap-to-span rule: how a drag's samples become the span `endDrag`
/// reports. Arithmetic on the samples the drag controller takes, and
/// total; the controller handles a null sample by leaving the session's
/// target unchanged.
///
/// THE LIFT RULE. A drag's displacement on an axis is `now - lift`, two
/// samples of ONE anchor: the pointer for a resize, and for a move the
/// proxy's content-leading corner on an axis the corner places, and the
/// pointer's cell on the lane axis of a laned item. A move's corner axis
/// and a resize measure it in the ITEM FIELD, the coordinate of the
/// lattice the item paints in: `painted` where the item is pinned on the
/// axis at this resolve, `scrolled` otherwise. An axis whose displacement
/// has neither travelled half a quantum nor reached a grid line keeps the
/// stored fields. The lane axis has MOVED when the finger's region
/// changed lattice or its cell changed. A moved corner axis is placed on
/// the current placement path, and its start is compared with where the
/// item was at the lift, read in that path's lattice (on the scrolled
/// path the stored start of an item that scrolls and the lift corner's
/// `scrolled` of one that is pinned, the lift corner's
/// `paintedExtended` elsewhere): a start beyond it against the direction
/// of travel, by more than `precisionErrorTolerance`, is REFUSED; a
/// refused band placement falls through to the scrolled path, the whole
/// lattice where no scrolled start shows, and a refusal there, or on any
/// path but a band's, keeps the stored start. An axis with no lift
/// sample has moved from the first resolve, and nothing refuses its
/// start. On a resize the GUARD applies where the shows bound moved the
/// dragged edge: an edge it carries past where the edge began, against
/// the direction of travel, by more than `precisionErrorTolerance`,
/// keeps the stored span.
class BoardDropResolver {
  BoardDropResolver._();

  /// The snap's QUANTUM in track space: one track under `track`, the
  /// configured fraction under `fraction`, and a VISIBLE quarter track
  /// under `free`, where an epsilon would satisfy the span asserts while
  /// leaving nothing paintable or grabbable.
  ///
  /// THREE READERS, and the name is the general one because they want
  /// the same number for different reasons: this file floors a resize at
  /// it, or at the item's own extent when that is less; it grids the
  /// windows of starts a drag is placed in, a move's through
  /// [quantumOn]; and `_board_drop_fit.dart` steps its candidate scan by
  /// it, through [quantumOn]. None may keep a second copy of the three
  /// cases.
  static double quantumOf(BoardSnap snap) {
    switch (snap.mode) {
      case BoardSnapMode.track:
        return 1.0;
      case BoardSnapMode.fraction:
        return snap.fraction!;
      case BoardSnapMode.free:
        return 0.25;
    }
  }

  /// The grid on [axis]: one track on [wholeTrackAxis], the snap's
  /// [quantumOf] elsewhere. A move's windows are on it, and the drop fit
  /// steps its scan by it.
  static double quantumOn(Axis axis, BoardSnap snap, Axis? wholeTrackAxis) {
    return axis == wholeTrackAxis ? 1.0 : quantumOf(snap);
  }

  /// A MOVE's target, and the window of starts each axis was placed in,
  /// from the samples `_resolve` took this resolve: [corner] at the
  /// proxy's content-leading corner, [centre] at its centre and [pointer]
  /// at the finger. Total: the samples are non-null by the caller's
  /// check. See [BoardDropResolver] for the lift rule it applies.
  ///
  /// [pointerAnchoredAxis] is the axis whose start a whole-track move
  /// takes from the POINTER rather than from the corner, or null when
  /// neither axis does. The caller passes the lane axis of a LANED item
  /// and nothing else.
  static ({BoardDropTarget target, BoardStartWindow rows, BoardStartWindow cols})
  resolveMove({
    required BoardPointSample corner,
    required BoardPointSample centre,
    required BoardPointSample pointer,
    required int grabCellRow,
    required int grabCellCol,
    required BoardSpan draggedSpan,
    required BoardSnap snap,
    required Axis? pointerAnchoredAxis,
    required BoardLiftSamples? liftCorner,
    required BoardLiftSamples? liftPointer,
    required BoardPins pinned,
  }) {
    // The ITEM'S CORNER decides, quantized by the snap: a track snap
    // ROUNDS it to the nearest track, because a straddling item covers
    // more of the aligned placement its corner rounds to than of any
    // other, so the cells committed are the cells the user sees it over;
    // a fraction snap takes the nearest quantum; a free one takes it as
    // it is. Which lattice the corner is read in is the placement path's
    // choice: the band under the proxy's centre when the span fits it,
    // else the scrolled tracks where a start of the span shows, else the
    // whole lattice.
    //
    // [pointerAnchoredAxis] is the one exception, under EVERY snap: a
    // laned item's painted lead there is a lane origin inside ONE track
    // rather than its span, so the cell under the finger decides, in the
    // region the finger is over, minus the whole-cell grab offset, and
    // the start is a WHOLE track, as a laned item occupies one.
    //
    // An axis that has not moved since the lift keeps the stored start;
    // a drag along one axis leaves the other where it was.
    final row = _moveAxis(
      axis: Axis.vertical,
      corner: corner.row,
      centre: centre.row,
      pointer: pointer.row,
      grabCell: grabCellRow,
      draggedSpan: draggedSpan,
      snap: snap,
      pointerAnchoredAxis: pointerAnchoredAxis,
      liftCorner: liftCorner?.row,
      liftPointer: liftPointer?.row,
      pinned: pinned.row,
    );
    final col = _moveAxis(
      axis: Axis.horizontal,
      corner: corner.col,
      centre: centre.col,
      pointer: pointer.col,
      grabCell: grabCellCol,
      draggedSpan: draggedSpan,
      snap: snap,
      pointerAnchoredAxis: pointerAnchoredAxis,
      liftCorner: liftCorner?.col,
      liftPointer: liftPointer?.col,
      pinned: pinned.col,
    );
    final rowStart = row.start;
    final colStart = col.start;
    if (rowStart == null && colStart == null) {
      return (
        target: BoardDropTarget(span: draggedSpan, kind: BoardDragKind.move),
        rows: row.window,
        cols: col.window,
      );
    }
    // A move never changes an item's extent: the span fractions carry
    // across unchanged. A kept axis passes null, which keeps its fields.
    return (
      target: BoardDropTarget(
        span: draggedSpan.copyWith(
          rowStart: rowStart?.floor(),
          rowFraction: rowStart == null
              ? null
              : rowStart - rowStart.floorToDouble(),
          colStart: colStart?.floor(),
          colFraction: colStart == null
              ? null
              : colStart - colStart.floorToDouble(),
        ),
        kind: BoardDragKind.move,
      ),
      rows: row.window,
      cols: col.window,
    );
  }

  /// One axis of a move: the start it resolves to, null where the axis
  /// keeps the stored one, and the window of starts it was placed in.
  static ({double? start, BoardStartWindow window}) _moveAxis({
    required Axis axis,
    required BoardAxisSample corner,
    required BoardAxisSample centre,
    required BoardAxisSample pointer,
    required int grabCell,
    required BoardSpan draggedSpan,
    required BoardSnap snap,
    required Axis? pointerAnchoredAxis,
    required BoardAxisSample? liftCorner,
    required BoardAxisSample? liftPointer,
    required ({int start, int end})? pinned,
  }) {
    final stored = draggedSpan.startTrackOn(axis);
    final laneAxis = pointerAnchoredAxis == axis;
    final extent = laneAxis
        ? 1.0
        : draggedSpan.spanOn(axis) +
              (axis == Axis.vertical
                  ? draggedSpan.rowSpanFraction
                  : draggedSpan.colSpanFraction);
    final quantum = laneAxis
        ? 1.0
        : quantumOn(axis, snap, pointerAnchoredAxis);
    // The window of a kept axis: the lattice the stored span lies in,
    // which the nudge may still step.
    final kept = (
      start: null,
      window: pinnedPathOf(
        pinned,
        pointer,
        extent: extent,
        quantum: quantum,
      ).window,
    );
    if (laneAxis) {
      final path = regionPathOf(pointer, extent: 1.0, quantum: 1.0);
      if (liftCorner != null && liftPointer != null) {
        final liftPath = regionPathOf(liftPointer, extent: 1.0, quantum: 1.0);
        if (sameLattice(path, liftPath) &&
            coordinateIn(path, pointer).floor() ==
                coordinateIn(liftPath, liftPointer).floor()) {
          return kept;
        }
      }
      final start = clampToWindow(
        (coordinateIn(path, pointer).floor() - grabCell).toDouble(),
        path.window,
      ).floorToDouble();
      if (_landsBack(start, stored)) {
        return kept;
      }
      return (start: start, window: path.window);
    }
    // THE ITEM FIELD: the corner read in the lattice the item paints in.
    double? displacement;
    if (liftCorner != null) {
      final lift = itemCoordinateOf(pinned, liftCorner);
      displacement = itemCoordinateOf(pinned, corner) - lift;
      if (_unmoved(snap, lift, displacement)) {
        return kept;
      }
    }
    final whole = snap.mode == BoardSnapMode.track;
    // Clamped into the path's window, whose bounds are inclusive: the
    // upper one keeps the span's END inside its lattice, so the last
    // legal placement stays REACHABLE and every evaluation stays inside
    // offsetOfFraction's domain. A whole-track axis then floors what the
    // clamp returns, which a fractional extent at the window's end can
    // leave between two tracks.
    double place(BoardAxisPath path) {
      final start = clampToWindow(
        snap.quantize(coordinateIn(path, corner)),
        path.window,
      );
      return whole ? start.floorToDouble() : start;
    }

    // THE GUARD: a start beyond where the item was at the lift, read in
    // the placement path's lattice, against the direction of travel. An
    // item that scrolls lies at its stored start in the scrolled
    // lattice; its lift corner's `scrolled` reads the same except where
    // the sample's bound replaces it, below the leading band's end in a
    // region that content held past the top shows.
    bool refused(double start, BoardAxisPath path) {
      final d = displacement;
      if (d == null) {
        return false;
      }
      final reference = path.scrolled
          ? (pinned == null ? stored : liftCorner!.scrolled)
          : liftCorner!.paintedExtended;
      if (d > 0.0) {
        return start < reference - precisionErrorTolerance;
      }
      if (d < 0.0) {
        return start > reference + precisionErrorTolerance;
      }
      return false;
    }

    var path = placementPathOf(
      corner: corner,
      centre: centre,
      extent: extent,
      quantum: quantum,
    );
    var start = place(path);
    if (refused(start, path)) {
      if (path.band == null) {
        return kept;
      }
      // FALL THROUGH: a refused band placement is placed and guarded
      // again on the scrolled path, the whole lattice where no scrolled
      // start shows.
      path = pinnedPathOf(null, corner, extent: extent, quantum: quantum);
      start = place(path);
      if (refused(start, path)) {
        return kept;
      }
    }
    if (_landsBack(start, stored)) {
      return kept;
    }
    return (start: start, window: path.window);
  }

  /// A RESIZE's target from the pointer's sample this resolve and its
  /// sample at the lift, [liftPointer], whose components are non-null.
  /// See [BoardDropResolver] for the lift rule; [pinned] is the item's
  /// pin at this resolve.
  ///
  /// The dragged endpoint, moved by the pointer's TRACK-SPACE
  /// displacement since the lift, measured in the item field. An endpoint
  /// [_unmoved] leaves the span as it was. Past it the endpoint is placed
  /// on a PATH: the frozen band under the pointer when that band holds
  /// the HELD edge, since only then can the result pin there, unless the
  /// lift pressed through that band onto an item that scrolls, at a point
  /// the band and the item read differently, which is then resolved as an
  /// item that scrolls; and otherwise the scrolled lattice, or the whole
  /// lattice where no start of the item's extent shows. There the
  /// endpoint is the stored one plus the pointer's coordinate in that
  /// path's lattice less the lift's item field, quantized by the snap, the
  /// extent floored at one quantum or at the item's own extent when that
  /// is less, and the endpoint clamped into the lattice; an endpoint back
  /// where it began keeps the stored span. A span placed on the band path
  /// that does not pin in that band is placed again on the other path. A
  /// span that pins in a band is taken as it is; one that scrolls keeps a
  /// dragged leading edge on the grid above the trailing band's inner
  /// edge, and a dragged trailing edge on the grid below the leading
  /// band's, where the span shows, subject to the GUARD of
  /// [BoardDropResolver].
  ///
  /// A displacement and not the pointer itself: the press lands inside a
  /// handle, not on the edge, and the raw pointer would commit the edge
  /// where the finger happened to land, so that a tap alone resized.
  /// Track space and not a paint-space grab: on the lane axis a laned
  /// item paints a lane BAND inside its track, so its painted edge is not
  /// its span's endpoint.
  static BoardDropTarget resolveResize({
    required BoardPointSample pointer,
    required BoardDragKind kind,
    required BoardSpan draggedSpan,
    required BoardSnap snap,
    required BoardLiftSamples liftPointer,
    required BoardPins pinned,
  }) {
    final vertical =
        kind == BoardDragKind.resizeRowStart ||
        kind == BoardDragKind.resizeRowEnd;
    final leadingKind =
        kind == BoardDragKind.resizeRowStart ||
        kind == BoardDragKind.resizeColStart;
    final now = vertical ? pointer.row : pointer.col;
    final lift = vertical ? liftPointer.row! : liftPointer.col!;
    final pin = vertical ? pinned.row : pinned.col;
    final trackCount = now.trackCount;
    // EXACT track-space endpoints; fields are written once, at the end.
    var lead = vertical
        ? draggedSpan.rowStart + draggedSpan.rowFraction
        : draggedSpan.colStart + draggedSpan.colFraction;
    var trail = vertical
        ? lead + draggedSpan.rowSpan + draggedSpan.rowSpanFraction
        : lead + draggedSpan.colSpan + draggedSpan.colSpanFraction;
    final liftItem = itemCoordinateOf(pin, lift);
    final displacement = itemCoordinateOf(pin, now) - liftItem;
    final quantum = quantumOf(snap);
    final from = leadingKind ? lead : trail;
    if (_unmoved(snap, from, displacement)) {
      return BoardDropTarget(span: draggedSpan, kind: kind);
    }
    final liftExtent = trail - lead;
    final floor = quantum < liftExtent ? quantum : liftExtent;
    final held = leadingKind ? trail : lead;

    // The dragged endpoint placed on [path]. The extent is floored by
    // moving the DRAGGED edge, never the held one.
    double endpointOn(BoardAxisPath path) {
      final moved = from + (coordinateIn(path, now) - liftItem);
      var edge = snap.quantize(moved).clamp(0.0, trackCount.toDouble());
      if (leadingKind) {
        if (held - edge < floor) {
          edge = held - floor;
        }
        return edge < 0.0 ? 0.0 : edge;
      }
      if (edge - held < floor) {
        edge = held + floor;
      }
      return edge > trackCount ? trackCount.toDouble() : edge;
    }

    ({int start, int end})? pinOf(double edge) {
      return bandHolding(
        leadingKind ? edge : held,
        leadingKind ? held : edge,
        leadingBandEnd: now.leadingBandEnd,
        trailingBandStart: now.trailingBandStart,
        trackCount: trackCount,
      );
    }

    final band = now.band;
    // A lift over the band the pointer is over, while the item scrolls on
    // this axis, pressed through that band onto an item painting under
    // it. Where the band's coordinate and the item's differ at the lift
    // point, the band path would put the edge where the band, not the
    // item, reads the pointer, so such a resize stays in the item's
    // lattice and is resolved as an item that scrolls: it is not pinned
    // into the band from the band's tracks. Where the two agree, as under
    // a header at no scroll, the band path is the item's own.
    final pressedThroughBand =
        lift.band != null &&
        lift.band == band &&
        pin == null &&
        (lift.painted - lift.scrolled).abs() > precisionErrorTolerance;
    final holdsHeld =
        !pressedThroughBand &&
        band != null &&
        (leadingKind
            ? trackEndIndexOf(held) > band.start &&
                  trackEndIndexOf(held) <= band.end
            : trackIndexOf(held) >= band.start &&
                  trackIndexOf(held) < band.end);
    final otherPath = pinnedPathOf(
      null,
      now,
      extent: liftExtent,
      quantum: quantum,
    );
    var path = holdsHeld
        ? regionPathOf(now, extent: 1.0, quantum: 1.0)
        : otherPath;
    var edge = endpointOn(path);
    if (_landsBack(edge, from)) {
      return BoardDropTarget(span: draggedSpan, kind: kind);
    }
    var pinnedIn = pressedThroughBand ? null : pinOf(edge);
    if (path.band != null && pinnedIn != path.band) {
      path = otherPath;
      edge = endpointOn(path);
      if (_landsBack(edge, from)) {
        return BoardDropTarget(span: draggedSpan, kind: kind);
      }
      pinnedIn = pinOf(edge);
    }
    if (pinnedIn == null) {
      // A sample carries no flag for a scrolled region the bands leave
      // empty; its two bounds are then present and equal.
      final visibleFrom = now.visibleFrom;
      final visibleTo = now.visibleTo;
      final empty =
          visibleFrom != null && visibleTo != null && visibleFrom >= visibleTo;
      var bounded = edge;
      if (!empty && leadingKind && visibleTo != null) {
        final bound = lastGridStartBelow(
          visibleTo,
          quantum,
        ).clamp(0.0, trackCount.toDouble());
        if (bounded > bound) {
          bounded = bound;
        }
      }
      if (!empty && !leadingKind && visibleFrom != null) {
        final bound = firstGridStartAbove(
          visibleFrom,
          quantum,
        ).clamp(0.0, trackCount.toDouble());
        if (bounded < bound) {
          bounded = bound;
        }
      }
      if (bounded != edge) {
        final against = displacement > 0.0
            ? bounded < from - precisionErrorTolerance
            : bounded > from + precisionErrorTolerance;
        if (against) {
          return BoardDropTarget(span: draggedSpan, kind: kind);
        }
        edge = bounded;
      }
      if (_landsBack(edge, from)) {
        return BoardDropTarget(span: draggedSpan, kind: kind);
      }
    }
    if (leadingKind) {
      lead = edge;
    } else {
      trail = edge;
    }
    final extent = trail - lead;
    final span = extent.floor();
    final spanFraction = extent - span;
    if (!leadingKind) {
      return BoardDropTarget(
        span: vertical
            ? draggedSpan.copyWith(rowSpan: span, rowSpanFraction: spanFraction)
            : draggedSpan.copyWith(colSpan: span, colSpanFraction: spanFraction),
        kind: kind,
      );
    }
    // The leading arm writes all four fields; the trailing one above
    // writes only the extent, so the stored start's fields stand.
    final start = lead.floor();
    final fraction = lead - start;
    return BoardDropTarget(
      span: vertical
          ? draggedSpan.copyWith(
              rowStart: start,
              rowFraction: fraction,
              rowSpan: span,
              rowSpanFraction: spanFraction,
            )
          : draggedSpan.copyWith(
              colStart: start,
              colFraction: fraction,
              colSpan: span,
              colSpanFraction: spanFraction,
            ),
      kind: kind,
    );
  }

  /// Whether a drag axis is still where it was: its anchor,
  /// [displacement] from [lift], the coordinate the resolver quantizes
  /// taken at the lift, has neither travelled half a quantum (the
  /// displacement quantizes to zero under [snap]; under `free`, it is
  /// zero) nor reached a grid line in the direction of travel. Such an
  /// axis keeps the stored span's fields. [BoardDropResolver] says how
  /// the displacement is read.
  static bool _unmoved(BoardSnap snap, double lift, double displacement) {
    if (snap.quantize(displacement) != 0.0) {
      return false;
    }
    final at = lift + displacement;
    final nearest = snap.quantize(at);
    if (displacement > 0.0) {
      return !(nearest > lift && nearest <= at + precisionErrorTolerance);
    }
    if (displacement < 0.0) {
      return !(nearest < lift && nearest >= at - precisionErrorTolerance);
    }
    return true;
  }

  /// Whether a resolved coordinate is the axis's [stored] value within
  /// `precisionErrorTolerance`: a floor or a clamp that lands a moved
  /// coordinate on the stored one keeps the stored fields rather than a
  /// re-split of them.
  static bool _landsBack(double resolved, double stored) {
    return (resolved - stored).abs() <= precisionErrorTolerance;
  }
}
