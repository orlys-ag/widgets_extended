/// Background painting for the board: the read-only geometry view a
/// painter receives, the painter contract, and a stock grid painter.
library;

import 'package:flutter/painting.dart';

/// What a [BoardBackgroundPainter] may read while painting.
///
/// Implemented by the board's render object and handed to the painter on
/// every paint; no per-paint object is allocated.
abstract interface class BoardGeometryView {
  /// First visible row. 0 with [lastVisibleRow] -1 when no row is visible,
  /// so `first > last` is the empty test and an inclusive loop runs zero
  /// times.
  int get firstVisibleRow;

  /// Last visible row, inclusive.
  int get lastVisibleRow;

  /// First visible column. Same empty convention as [firstVisibleRow].
  int get firstVisibleCol;

  /// Last visible column, inclusive.
  int get lastVisibleCol;

  /// The paint-space rect of one cell. Non-nullable, and legal only for a
  /// cell whose row is inside the visible row bounds above or is a frozen
  /// row, and whose column is inside the visible column bounds or is a
  /// frozen column. A frozen track is positioned where its frozen band
  /// paints, pinned to the viewport, whether or not the scrolled window
  /// also covers it.
  Rect visibleCellRect(int row, int col);

  /// The viewport's size.
  Size get viewportDimension;

  /// The extent of the LEADING frozen band on [axis], 0.0 when there is
  /// none.
  double frozenInsetOf(Axis axis);

  /// The frozen tracks of [axis], leading band then trailing band,
  /// ascending within each. A frozen track paints in its band whatever the
  /// scroll offset, so it can lie outside the visible bounds above and is
  /// still legal for [visibleCellRect]; it can also lie inside them.
  Iterable<int> frozenTracksOf(Axis axis);
}

/// Paints behind every cell and item. Costs no render children: the render
/// object calls [paint] directly as its first paint pass.
abstract class BoardBackgroundPainter {
  const BoardBackgroundPainter();

  /// Paints onto [canvas], reading [geometry] for what is visible and
  /// where it sits.
  void paint(Canvas canvas, BoardGeometryView geometry);

  /// Whether replacing [old] with this painter requires a repaint.
  bool shouldRepaint(covariant BoardBackgroundPainter old);
}

/// A stock background: optional per-track tints under grid lines on every
/// visible cell boundary.
class BoardGridPainter extends BoardBackgroundPainter {
  const BoardGridPainter({
    this.gridLineColor = const Color(0x1F000000),
    this.gridLineWidth = 1.0,
    this.trackTint,
  });

  /// Color of the boundary lines.
  final Color gridLineColor;

  /// Stroke width of the boundary lines.
  final double gridLineWidth;

  /// Optional fill for a whole track's visible band, keyed by axis
  /// ([Axis.vertical] is a row, [Axis.horizontal] a column) and track
  /// index. Null means no tint for that track.
  final Color? Function(Axis axis, int track)? trackTint;

  @override
  void paint(Canvas canvas, BoardGeometryView geometry) {
    final firstRow = geometry.firstVisibleRow;
    final lastRow = geometry.lastVisibleRow;
    final firstCol = geometry.firstVisibleCol;
    final lastCol = geometry.lastVisibleCol;
    if (firstRow > lastRow || firstCol > lastCol) {
      return;
    }
    // The tracks to paint on each axis: the visible range, then the
    // frozen tracks the range does not already cover. A frozen track
    // inside the range is painted ONCE, at the position the geometry
    // reports for it, which is its band.
    final rows = _tracksToPaint(
      geometry.frozenTracksOf(Axis.vertical),
      firstRow,
      lastRow,
    );
    final cols = _tracksToPaint(
      geometry.frozenTracksOf(Axis.horizontal),
      firstCol,
      lastCol,
    );

    // The painted band: the visible window widened to every frozen
    // track's rect. expandToInclude sorts the corners, so a reversed axis,
    // whose first cell paints after its last, needs no special arm.
    var band = geometry
        .visibleCellRect(firstRow, firstCol)
        .expandToInclude(geometry.visibleCellRect(lastRow, lastCol));
    for (final row in rows) {
      band = band.expandToInclude(geometry.visibleCellRect(row, firstCol));
    }
    for (final col in cols) {
      band = band.expandToInclude(geometry.visibleCellRect(firstRow, col));
    }

    // Tints first, so the lines stay visible on top of them.
    final tint = trackTint;
    if (tint != null) {
      final fill = Paint();
      for (final row in rows) {
        final color = tint(Axis.vertical, row);
        if (color != null) {
          final rect = geometry.visibleCellRect(row, firstCol);
          fill.color = color;
          canvas.drawRect(
            Rect.fromLTRB(band.left, rect.top, band.right, rect.bottom),
            fill,
          );
        }
      }
      for (final col in cols) {
        final color = tint(Axis.horizontal, col);
        if (color != null) {
          final rect = geometry.visibleCellRect(firstRow, col);
          fill.color = color;
          canvas.drawRect(
            Rect.fromLTRB(rect.left, band.top, rect.right, band.bottom),
            fill,
          );
        }
      }
    }

    // One line per boundary, each derived from ONE expression: every
    // track's top (its leading edge under the paint mapping) plus the
    // band's own trailing edge. Deriving a shared boundary from two
    // expressions, one track's top plus its neighbour's bottom, and
    // deduplicating by value does not survive fractional extents: the
    // two doubles need not compare equal, and the translucent default
    // color then doubles at that boundary.
    final line = Paint()
      ..color = gridLineColor
      ..strokeWidth = gridLineWidth;
    for (final row in rows) {
      final y = geometry.visibleCellRect(row, firstCol).top;
      canvas.drawLine(Offset(band.left, y), Offset(band.right, y), line);
    }
    canvas.drawLine(
      Offset(band.left, band.bottom),
      Offset(band.right, band.bottom),
      line,
    );
    for (final col in cols) {
      final x = geometry.visibleCellRect(firstRow, col).left;
      canvas.drawLine(Offset(x, band.top), Offset(x, band.bottom), line);
    }
    canvas.drawLine(
      Offset(band.right, band.top),
      Offset(band.right, band.bottom),
      line,
    );
  }

  /// The tracks of one axis the painter iterates: `first..last` inclusive,
  /// followed by every track of [frozen] outside that range. Deduplicated
  /// by track index, so a frozen track the range covers appears once.
  static List<int> _tracksToPaint(Iterable<int> frozen, int first, int last) {
    final tracks = <int>[for (var track = first; track <= last; track++) track];
    for (final track in frozen) {
      if (track < first || track > last) {
        tracks.add(track);
      }
    }
    return tracks;
  }

  @override
  bool shouldRepaint(BoardGridPainter old) {
    return old.gridLineColor != gridLineColor ||
        old.gridLineWidth != gridLineWidth ||
        old.trackTint != trackTint;
  }
}
