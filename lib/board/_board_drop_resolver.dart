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

  /// The leading cell of [span], for cell-shaped consumers. DERIVED,
  /// never stored.
  ({int row, int col}) get cell {
    return (row: span.rowStart, col: span.colStart);
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

  /// [pointerAnchoredAxis] is the axis whose start a whole-track move
  /// takes from the POINTER rather than from the item's painted corner,
  /// or null when neither axis does. The caller passes the lane axis of
  /// a LANED item and nothing else; see [_resolveMove].
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
    return _resolveResize(
      port: port,
      anchorLocal: anchorLocal,
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
    if (snap.mode == BoardSnapMode.track) {
      // The ITEM'S CORNER decides under a whole-cell snap, ROUNDED to
      // the nearest track: a straddling item covers more of the aligned
      // placement its corner rounds to than of any other, so the cells
      // committed are the cells the user sees it over. This is the same
      // rule the fraction and free arm below applies, which quantizes
      // the same corner.
      //
      // Flooring the POINTER's track and subtracting a grab cell floored
      // at lift quantized TWICE, and two floors of one continuous
      // quantity disagree by one depending on where inside a cell the
      // item was grabbed, so the placement flipped when the finger
      // crossed a cell boundary rather than when the item's body did.
      //
      // [pointerAnchoredAxis] is the one exception, and the caller
      // passes the lane axis of a LANED item: its painted lead there is
      // a lane origin inside ONE track rather than its span, so rounding
      // that corner would carry a chip lying wholly inside a tall row
      // into the next row the moment its top passed the midpoint. There
      // the cell under the finger decides, minus the whole-cell grab
      // offset, which keeps the grabbed cell under the pointer.
      final corner = port.trackSpaceAt(anchorLocal);
      final pointer = port.trackSpaceAt(pointerLocal);
      if (corner == null || pointer == null) {
        return null;
      }
      final cell = (
        row: pointerAnchoredAxis == Axis.vertical
            ? pointer.row.floor() - grabCellRow
            : corner.row.round(),
        col: pointerAnchoredAxis == Axis.horizontal
            ? pointer.col.floor() - grabCellCol
            : corner.col.round(),
      );
      final rowExtent = draggedSpan.rowSpan + draggedSpan.rowSpanFraction;
      final colExtent = draggedSpan.colSpan + draggedSpan.colSpanFraction;
      final row = clampStart(cell.row.toDouble(), rowExtent, rowCount);
      final col = clampStart(cell.col.toDouble(), colExtent, colCount);
      return BoardDropTarget(
        span: draggedSpan.copyWith(
          rowStart: row.floor(),
          rowFraction: 0.0,
          colStart: col.floor(),
          colFraction: 0.0,
        ),
        kind: BoardDragKind.move,
      );
    }
    final track = port.trackSpaceAt(anchorLocal);
    if (track == null) {
      return null;
    }
    final rowExtent = draggedSpan.rowSpan + draggedSpan.rowSpanFraction;
    final colExtent = draggedSpan.colSpan + draggedSpan.colSpanFraction;
    // The clamp is on the ENDPOINT, not the start: q is clamped so that
    // the span's end stays inside the lattice, with the start clamped
    // inclusively at 0, which keeps the last legal placement REACHABLE
    // and every evaluation inside offsetOfFraction's domain.
    final row = clampStart(snap.quantize(track.row), rowExtent, rowCount);
    final col = clampStart(snap.quantize(track.col), colExtent, colCount);
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

  static BoardDropTarget? _resolveResize({
    required BoardRenderPort<Object?> port,
    required Offset anchorLocal,
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
    final pointer = vertical ? track.row : track.col;
    final quantum = quantumOf(snap);
    if (leadingKind) {
      lead = snap.quantize(pointer).clamp(0.0, trackCount.toDouble());
      // Floor the extent at one quantum by moving the DRAGGED edge,
      // never the held one.
      if (trail - lead < quantum) {
        lead = trail - quantum;
      }
      if (lead < 0.0) {
        lead = 0.0;
      }
    } else {
      trail = snap.quantize(pointer).clamp(0.0, trackCount.toDouble());
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
