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
/// handle's `edge` argument, carried on every [BoardDropTarget] the
/// session produces, and read by `endDrag` to decide which callback
/// fires.
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

  /// The minimum extent, in track space, a resize may leave: one quantum
  /// under `track` and `fraction`, and a VISIBLE quarter track under
  /// `free`, where an epsilon extent would satisfy the span asserts while
  /// leaving nothing paintable or grabbable.
  static double _quantumOf(BoardSnap snap) {
    switch (snap.mode) {
      case BoardSnapMode.track:
        return 1.0;
      case BoardSnapMode.fraction:
        return snap.fraction!;
      case BoardSnapMode.free:
        return 0.25;
    }
  }

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
  }) {
    if (snap.mode == BoardSnapMode.track) {
      // The POINTER decides under a whole-cell snap: the cell under the
      // finger, minus the whole-cell grab offset, is the start. Item
      // geometry never enters it, so a lane-thin item low in a tall
      // cell stays in the cell the user is pointing at, and the grabbed
      // cell of a multi-track item stays under the pointer.
      final track = port.trackSpaceAt(pointerLocal);
      if (track == null) {
        return null;
      }
      final cell = (
        row: track.row.floor() - grabCellRow,
        col: track.col.floor() - grabCellCol,
      );
      final rowExtent = draggedSpan.rowSpan + draggedSpan.rowSpanFraction;
      final colExtent = draggedSpan.colSpan + draggedSpan.colSpanFraction;
      final row = _clampStart(cell.row.toDouble(), rowExtent, rowCount);
      final col = _clampStart(cell.col.toDouble(), colExtent, colCount);
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
    final row = _clampStart(snap.quantize(track.row), rowExtent, rowCount);
    final col = _clampStart(snap.quantize(track.col), colExtent, colCount);
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

  static double _clampStart(double q, double extent, int trackCount) {
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
    final quantum = _quantumOf(snap);
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
