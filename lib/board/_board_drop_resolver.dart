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
import 'board_render_port.dart';

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

/// The snap-to-span rule: how a pointer becomes the span `endDrag`
/// reports. Wraps the port's spatial queries; both arms are total, and a
/// null track-space sample resolves to null, which leaves the session's
/// current target unchanged.
class BoardDropResolver {
  BoardDropResolver._();

  /// The snap's QUANTUM in track space: one track under `track`, the
  /// configured fraction under `fraction`, and a VISIBLE quarter track
  /// under `free`, where an epsilon would satisfy the span asserts while
  /// leaving nothing paintable or grabbable.
  ///
  /// TWO READERS, and the name is the general one because they want the
  /// same number for different reasons: this file floors a resize at it,
  /// and `_board_drop_fit.dart` steps its candidate scan by it. Neither
  /// may keep a second copy of the three cases.
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

  /// For a move, [anchorLocal] is the proxy's content-LEADING corner
  /// (`BoardRenderPort.leadingCornerOf`), so [BoardRenderPort.trackSpaceAt]
  /// of it is where the item would START on both axes, reversed or not;
  /// for a resize it is the pointer, and [liftTrack] is the pointer's
  /// track coordinate when the session began: a resize moves the dragged
  /// ENDPOINT by the pointer's displacement since then, because a press
  /// lands somewhere inside a handle rather than on the edge. See
  /// [_resolveResize].
  ///
  /// [pointerAnchoredAxis] is the axis whose start a whole-track move
  /// takes from the POINTER rather than from that corner, or null when
  /// neither axis does. The caller passes the lane axis of a LANED item
  /// and nothing else; see [_resolveMove].
  static BoardDropTarget? resolve({
    required BoardRenderPort<Object?> port,
    required Offset anchorLocal,
    required Offset pointerLocal,
    required int grabCellRow,
    required int grabCellCol,
    required BoardSpan draggedSpan,
    required BoardDragKind kind,
    required BoardSnap snap,
    required int rowCount,
    required int colCount,
    required Axis? pointerAnchoredAxis,
    ({double row, double col})? liftTrack,
  }) {
    if (kind == BoardDragKind.move) {
      return _resolveMove(
        port: port,
        anchorLocal: anchorLocal,
        pointerLocal: pointerLocal,
        grabCellRow: grabCellRow,
        grabCellCol: grabCellCol,
        draggedSpan: draggedSpan,
        snap: snap,
        rowCount: rowCount,
        colCount: colCount,
        pointerAnchoredAxis: pointerAnchoredAxis,
      );
    }
    assert(liftTrack != null, "A resize resolves from its lift sample.");
    return _resolveResize(
      port: port,
      anchorLocal: anchorLocal,
      liftTrack: liftTrack!,
      draggedSpan: draggedSpan,
      kind: kind,
      snap: snap,
      rowCount: rowCount,
      colCount: colCount,
    );
  }

  static BoardDropTarget? _resolveMove({
    required BoardRenderPort<Object?> port,
    required Offset anchorLocal,
    required Offset pointerLocal,
    required int grabCellRow,
    required int grabCellCol,
    required BoardSpan draggedSpan,
    required BoardSnap snap,
    required int rowCount,
    required int colCount,
    required Axis? pointerAnchoredAxis,
  }) {
    // The ITEM'S CORNER decides, quantized by the snap: a track snap
    // ROUNDS it to the nearest track, because a straddling item covers
    // more of the aligned placement its corner rounds to than of any
    // other, so the cells committed are the cells the user sees it over;
    // a fraction snap takes the nearest quantum; a free one takes it as
    // it is.
    //
    // Flooring the POINTER's track and subtracting a grab cell floored at
    // lift would quantize TWICE, and two floors of one continuous quantity
    // disagree by one depending on where inside a cell the item was
    // grabbed, so the placement would flip when the finger crossed a cell
    // boundary rather than when the item's body did.
    //
    // [pointerAnchoredAxis] is the one exception, under EVERY snap, and the
    // caller passes the lane axis of a LANED item: its painted lead there
    // is a lane origin inside ONE track rather than its span, so the
    // corner there says nothing about which track it is over (rounding it
    // would carry a chip lying wholly inside a tall row into the next row
    // the moment its top passed the midpoint, and quantizing it finely
    // would land a lane-1 event halfway through its day). There the cell
    // under the finger decides, minus the whole-cell grab offset, which
    // keeps the grabbed cell under the pointer, and the start is a WHOLE
    // track, as a laned item occupies one.
    final corner = port.trackSpaceAt(anchorLocal);
    final pointer = port.trackSpaceAt(pointerLocal);
    if (corner == null || pointer == null) {
      return null;
    }
    // Whole-track on an axis a track snap governs or the pointer anchors.
    bool whole(Axis axis) {
      return snap.mode == BoardSnapMode.track || pointerAnchoredAxis == axis;
    }

    double startOn(Axis axis) {
      final vertical = axis == Axis.vertical;
      if (pointerAnchoredAxis == axis) {
        final cell = (vertical ? pointer.row : pointer.col).floor();
        return (cell - (vertical ? grabCellRow : grabCellCol)).toDouble();
      }
      return snap.quantize(vertical ? corner.row : corner.col);
    }

    final rowExtent = draggedSpan.rowSpan + draggedSpan.rowSpanFraction;
    final colExtent = draggedSpan.colSpan + draggedSpan.colSpanFraction;
    // The clamp is on the ENDPOINT, not the start: q is clamped so that
    // the span's end stays inside the lattice, with the start clamped
    // inclusively at 0, which keeps the last legal placement REACHABLE
    // and every evaluation inside offsetOfFraction's domain. A whole-track
    // axis then floors what the clamp returns, which a fractional extent
    // at the lattice's end can leave between two tracks.
    var row = clampStart(startOn(Axis.vertical), rowExtent, rowCount);
    var col = clampStart(startOn(Axis.horizontal), colExtent, colCount);
    if (whole(Axis.vertical)) {
      row = row.floorToDouble();
    }
    if (whole(Axis.horizontal)) {
      col = col.floorToDouble();
    }
    // A move never changes an item's extent: the span fractions carry
    // across unchanged.
    return BoardDropTarget(
      span: draggedSpan.copyWith(
        rowStart: row.floor(),
        rowFraction: row - row.floorToDouble(),
        colStart: col.floor(),
        colFraction: col - col.floorToDouble(),
      ),
      kind: BoardDragKind.move,
    );
  }

  /// Clamps a leading track coordinate so a span of [extent] stays inside
  /// `[0, trackCount]`, moving the START and never the extent.
  ///
  /// Non-private because `_board_drop_fit.dart` clamps its candidates by
  /// the same rule; two copies of an endpoint rule is how the two
  /// disagree at the lattice edge.
  static double clampStart(double q, double extent, int trackCount) {
    var start = q;
    if (start + extent > trackCount) {
      start = trackCount - extent;
    }
    if (start < 0.0) {
      start = 0.0;
    }
    return start;
  }

  /// The dragged endpoint, moved by the pointer's TRACK-SPACE
  /// displacement since [liftTrack], then quantized by the snap, floored
  /// at one quantum and clamped into the lattice.
  ///
  /// A displacement and not the pointer itself: the press lands inside a
  /// handle, not on the edge, and the raw pointer would commit the edge
  /// where the finger happened to land, so that a tap alone resized. Zero
  /// displacement is exactly zero, so a press that does not move leaves
  /// the endpoint as it was. Track space and not a paint-space grab: on
  /// the lane axis a laned item paints a lane BAND inside its track, so
  /// its painted edge is not its span's endpoint;
  /// [BoardRenderPort.trackSpaceAt] answers frozen bands, reversal and
  /// an in-flight resize for both samples alike.
  static BoardDropTarget? _resolveResize({
    required BoardRenderPort<Object?> port,
    required Offset anchorLocal,
    required ({double row, double col}) liftTrack,
    required BoardSpan draggedSpan,
    required BoardDragKind kind,
    required BoardSnap snap,
    required int rowCount,
    required int colCount,
  }) {
    final track = port.trackSpaceAt(anchorLocal);
    if (track == null) {
      return null;
    }
    final vertical =
        kind == BoardDragKind.resizeRowStart ||
        kind == BoardDragKind.resizeRowEnd;
    final leadingKind =
        kind == BoardDragKind.resizeRowStart ||
        kind == BoardDragKind.resizeColStart;
    final trackCount = vertical ? rowCount : colCount;
    // EXACT track-space endpoints; fields are written once, at the end.
    var lead = vertical
        ? draggedSpan.rowStart + draggedSpan.rowFraction
        : draggedSpan.colStart + draggedSpan.colFraction;
    var trail = vertical
        ? lead + draggedSpan.rowSpan + draggedSpan.rowSpanFraction
        : lead + draggedSpan.colSpan + draggedSpan.colSpanFraction;
    final displacement = vertical
        ? track.row - liftTrack.row
        : track.col - liftTrack.col;
    final quantum = quantumOf(snap);
    if (leadingKind) {
      lead = snap
          .quantize(lead + displacement)
          .clamp(0.0, trackCount.toDouble());
      // Floor the extent at one quantum by moving the DRAGGED edge,
      // never the held one.
      if (trail - lead < quantum) {
        lead = trail - quantum;
      }
      if (lead < 0.0) {
        lead = 0.0;
      }
    } else {
      trail = snap
          .quantize(trail + displacement)
          .clamp(0.0, trackCount.toDouble());
      if (trail - lead < quantum) {
        trail = lead + quantum;
      }
      if (trail > trackCount) {
        trail = trackCount.toDouble();
      }
    }
    final extent = trail - lead;
    final start = lead.floor();
    final fraction = lead - start;
    final span = extent.floor();
    final spanFraction = extent - span;
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
}
