/// Background painting for the board: the read-only geometry view a
/// painter receives, the painter contract, and a stock grid painter.
library;

import 'package:flutter/painting.dart';

/// What a [BoardBackgroundPainter] may read while painting.
///
/// Implemented by the board's render object and handed to the painter on
/// every paint; no per-paint object is allocated.
abstract interface class BoardGeometryView {
  /// First visible SCROLLED row: the first row not in a frozen band that
  /// shows in [scrolledRegion]. A row wholly under a band does not show,
  /// and a frozen row is reported by [frozenTracksOf] instead, so no row
  /// is in both. 0 with [lastVisibleRow] -1 when no row is visible, so
  /// `first > last` is the empty test and an inclusive loop runs zero
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

  /// The paint-space rect the SCROLLED tracks show through: the viewport
  /// minus every frozen band. What a painter clips scrolled tracks to, so
  /// that nothing it draws for them lands inside a band, where they are
  /// hidden. The whole viewport on a board without bands.
  Rect get scrolledRegion;

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

/// The tracks of one axis a painter walks: the visible SCROLLED tracks,
/// and the frozen tracks split into their bands, leading then trailing.
/// Disjoint by the visible bounds' own rule.
class _Tracks {
  _Tracks(this.scrolled, this.bands);

  factory _Tracks.of(BoardGeometryView geometry, Axis axis) {
    final vertical = axis == Axis.vertical;
    final first = vertical ? geometry.firstVisibleRow : geometry.firstVisibleCol;
    final last = vertical ? geometry.lastVisibleRow : geometry.lastVisibleCol;
    final bands = <List<int>>[];
    int? previous;
    for (final track in geometry.frozenTracksOf(axis)) {
      if (previous == null || track != previous + 1) {
        bands.add(<int>[]);
      }
      bands.last.add(track);
      previous = track;
    }
    return _Tracks(<int>[for (var t = first; t <= last; t++) t], bands);
  }

  final List<int> scrolled;
  final List<List<int>> bands;

  Iterable<int> get frozen sync* {
    for (final band in bands) {
      yield* band;
    }
  }

  Iterable<int> get all sync* {
    yield* scrolled;
    yield* frozen;
  }

  bool get isEmpty {
    return scrolled.isEmpty && bands.isEmpty;
  }

  /// A track [BoardGeometryView.visibleCellRect] accepts on this axis.
  int get any {
    return scrolled.isNotEmpty ? scrolled.first : bands.first.first;
  }
}

/// A stock background: optional per-track tints under grid lines on every
/// visible cell boundary, frozen bands included. A scrolled track's tint
/// and lines are clipped to [BoardGeometryView.scrolledRegion], so
/// nothing drawn for a track hidden under a band shows through it.
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
    final rows = _Tracks.of(geometry, Axis.vertical);
    final cols = _Tracks.of(geometry, Axis.horizontal);
    if (rows.isEmpty || cols.isEmpty) {
      return;
    }
    // One legal index per axis to read the other axis's rects against:
    // visibleCellRect accepts a visible scrolled track or a frozen one.
    final refRow = rows.any;
    final refCol = cols.any;
    Rect rowRect(int row) {
      return geometry.visibleCellRect(row, refCol);
    }

    Rect colRect(int col) {
      return geometry.visibleCellRect(refRow, col);
    }

    // The painted band: every painted track's rect on each axis.
    // expandToInclude sorts the corners, so a reversed axis, whose first
    // cell paints after its last, needs no special arm.
    Rect? band;
    for (final row in rows.all) {
      final rect = rowRect(row);
      band = band == null ? rect : band.expandToInclude(rect);
    }
    for (final col in cols.all) {
      band = band!.expandToInclude(colRect(col));
    }
    final painted = band!;
    final region = geometry.scrolledRegion;

    // Tints first, so the lines stay visible on top of them. A SCROLLED
    // track's tint is clipped to the scrolled region on its own axis, so
    // none of it lands inside a band where the track is hidden; a frozen
    // track's is not clipped.
    final tint = trackTint;
    if (tint != null) {
      final fill = Paint();
      void tintRow(int row) {
        final color = tint(Axis.vertical, row);
        if (color != null) {
          final rect = rowRect(row);
          fill.color = color;
          canvas.drawRect(
            Rect.fromLTRB(painted.left, rect.top, painted.right, rect.bottom),
            fill,
          );
        }
      }

      void tintCol(int col) {
        final color = tint(Axis.horizontal, col);
        if (color != null) {
          final rect = colRect(col);
          fill.color = color;
          canvas.drawRect(
            Rect.fromLTRB(rect.left, painted.top, rect.right, painted.bottom),
            fill,
          );
        }
      }

      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(painted.left, region.top, painted.right, region.bottom),
      );
      rows.scrolled.forEach(tintRow);
      canvas.restore();
      rows.frozen.forEach(tintRow);
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(region.left, painted.top, region.right, painted.bottom),
      );
      cols.scrolled.forEach(tintCol);
      canvas.restore();
      cols.frozen.forEach(tintCol);
    }

    // One line per boundary, each derived from ONE expression. Deriving a
    // shared boundary from two expressions, one track's top plus its
    // neighbour's bottom, and deduplicating by value does not survive
    // fractional extents: the two doubles need not compare equal, and the
    // translucent default color then doubles at that boundary.
    final line = Paint()
      ..color = gridLineColor
      ..strokeWidth = gridLineWidth;
    for (final y in _boundaries(
      rows,
      (row) {
        final rect = rowRect(row);
        return (lead: rect.top, trail: rect.bottom);
      },
      region.top,
      region.bottom,
      geometry.viewportDimension.height,
    )) {
      canvas.drawLine(Offset(painted.left, y), Offset(painted.right, y), line);
    }
    for (final x in _boundaries(
      cols,
      (col) {
        final rect = colRect(col);
        return (lead: rect.left, trail: rect.right);
      },
      region.left,
      region.right,
      geometry.viewportDimension.width,
    )) {
      canvas.drawLine(Offset(x, painted.top), Offset(x, painted.bottom), line);
    }
  }

  /// The paint-space coordinates of one axis's boundary lines, each
  /// boundary once.
  ///
  /// A BAND gives every one of its tracks' near edges and its own far
  /// edge. The SCROLLED tracks give their near edges and the last one's
  /// far edge, but only where they show: strictly inside the region
  /// `[start, end]` on a side where a band sits, since the band draws that
  /// edge itself and the scrolled tracks there are hidden under it, and
  /// anywhere on a side with no band.
  static List<double> _boundaries(
    _Tracks tracks,
    ({double lead, double trail}) Function(int track) edgesOf,
    double start,
    double end,
    double viewport,
  ) {
    const tolerance = 1e-9;
    final bandAtStart = start > tolerance;
    final bandAtEnd = end < viewport - tolerance;
    bool shows(double at) {
      if (bandAtStart && at <= start + tolerance) {
        return false;
      }
      if (bandAtEnd && at >= end - tolerance) {
        return false;
      }
      return true;
    }

    final lines = <double>[];
    for (final band in tracks.bands) {
      var far = double.negativeInfinity;
      for (final track in band) {
        final edges = edgesOf(track);
        lines.add(edges.lead);
        if (edges.trail > far) {
          far = edges.trail;
        }
      }
      lines.add(far);
    }
    if (tracks.scrolled.isNotEmpty) {
      var far = double.negativeInfinity;
      for (final track in tracks.scrolled) {
        final edges = edgesOf(track);
        if (shows(edges.lead)) {
          lines.add(edges.lead);
        }
        if (edges.trail > far) {
          far = edges.trail;
        }
      }
      if (shows(far)) {
        lines.add(far);
      }
    }
    return lines;
  }

  @override
  bool shouldRepaint(BoardGridPainter old) {
    return old.gridLineColor != gridLineColor ||
        old.gridLineWidth != gridLineWidth ||
        old.trackTint != trackTint;
  }
}
