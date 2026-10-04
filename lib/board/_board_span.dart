/// L0 span value types for the board module.
///
/// [BoardSpan] is the board's track-space rectangle and [BoardPlacement]
/// pairs one with a caller item. Both are exported from the module barrel;
/// the file name carries a leading underscore because the barrel decides
/// the exported surface with explicit `show` clauses.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The track a track-space coordinate LEADS INTO: its floor, with a
/// coordinate within [precisionErrorTolerance] BELOW an integer taken as
/// that integer. The one rule for turning an item's START into a track
/// index, the start-side mirror of [trackEndIndexOf].
///
/// A start one ulp below an integer, which the sum of two exact multiples
/// of a quantum can come to in doubles, is ON that track's leading edge,
/// and flooring it raw puts the item in the track before, where it covers
/// nothing. Every site that indexes a start reads this, never `floor()`,
/// and never a span's integer component: that component is the raw floor.
int trackIndexOf(double trackSpace) {
  return (trackSpace + precisionErrorTolerance).floor();
}

/// One past the last track a half-open interval ending at the
/// track-space [end] reaches: its ceiling, with an end within
/// [precisionErrorTolerance] ABOVE an integer taken as that integer, so
/// an end one ulp past a track's leading edge does not reach into it.
int trackEndIndexOf(double end) {
  return (end - precisionErrorTolerance).ceil();
}

/// [trackSpace], or the integer it lies within [precisionErrorTolerance]
/// of. For a value the board PRODUCES from arithmetic on a quantum, so a
/// placement meant to start on a track edge starts exactly there.
double snapToTrackEdge(double trackSpace) {
  final nearest = trackSpace.roundToDouble();
  return (trackSpace - nearest).abs() <= precisionErrorTolerance
      ? nearest
      : trackSpace;
}

/// One axis of a paint-space point, mapped in BOTH lattices the axis can
/// paint, the frozen bands' and the scrolled tracks', with the band
/// geometry a drop reads. `BoardRenderPort.trackSampleAt` produces it.
///
/// `painted`: the coordinate `BoardRenderPort.trackSpaceAt` answers on the
/// axis, the integer track plus the fraction into it of the lattice that
/// paints at the point.
///
/// `paintedExtended`: `painted`, except past the viewport's outer edge
/// beside a frozen band, where the band's mapping clamps to the band's
/// outer end. There it continues at the outermost track's extent, read as
/// the band reads its tracks: in normalized space `n`, with `V` the
/// viewport extent and `N` the track count, `n / extentOf(0)` for `n < 0`
/// beside a leading band and `N + (n - V) / extentOf(N - 1)` for `n > V`
/// beside a trailing band. Monotone and continuous at the outer edges, it
/// jumps at a band's inner edge as `painted` does: a point 30 px above a
/// 50 px header reads -0.6.
///
/// `scrolled`: the scrolled lattice's coordinate at the point, read
/// through the animated geometry whether or not a band paints over it,
/// clamped into `[0, trackCount]` and bounded by [boundedScrolled]: over
/// the scrolled region it is `painted`, the scrolled coordinate clamped
/// into `[leadingBandEnd, trailingBandStart]`, and over a band it never
/// passes `painted` toward the band's inner side.
///
/// `scrollPixels`: the scroll offset on the axis that `scrolled` and the
/// two visible bounds were read at: the board's, or the one
/// `BoardRenderPort.trackSampleAt` was asked to sample at.
///
/// `band`: the frozen band whose mapping answers `painted`, as a half-open
/// track range, or null. That is the band the point lies over, and also a
/// band beside which the point lies past the viewport's outer edge, since
/// the band's mapping has no outer bound and answers there.
///
/// `visibleFrom`, `visibleTo`: the scrolled coordinate at the leading
/// band's inner edge and at the trailing band's, each clamped into
/// `[leadingBandEnd, trailingBandStart]`. Each is present only where its
/// band exists, except that both are present, and equal, when the bands
/// leave no scrolled region. A scrolled span SHOWS when it overlaps the
/// open interval between them, each bound only where it is present.
///
/// `trackCount`, `leadingBandEnd`, `trailingBandStart`: the axis's track
/// count and its two band bounds, so a consumer never pairs a sample with
/// another config.
typedef BoardAxisSample = ({
  double painted,
  double paintedExtended,
  double scrolled,
  double scrollPixels,
  ({int start, int end})? band,
  double? visibleFrom,
  double? visibleTo,
  int trackCount,
  int leadingBandEnd,
  int trailingBandStart,
});

/// A closed interval of starts.
typedef BoardStartWindow = ({double min, double max});

/// Where one axis is resolved: in [band] when non-null, else in the
/// scrolled lattice when [scrolled], else in the whole lattice; with the
/// starts that lattice allows.
typedef BoardAxisPath = ({
  ({int start, int end})? band,
  bool scrolled,
  BoardStartWindow window,
});

/// The first start on the grid of [quantum] strictly above [bound]. The
/// bound is read in grid steps, `bound / quantum`, through [trackIndexOf],
/// so one within [precisionErrorTolerance] steps below a grid line is
/// taken as that line.
double firstGridStartAbove(double bound, double quantum) {
  return snapToTrackEdge((trackIndexOf(bound / quantum) + 1) * quantum);
}

/// The last start on the grid of [quantum] strictly below [bound]. The
/// bound is read in grid steps, `bound / quantum`, through
/// [trackEndIndexOf], so one within [precisionErrorTolerance] steps above
/// a grid line is taken as that line.
double lastGridStartBelow(double bound, double quantum) {
  return snapToTrackEdge((trackEndIndexOf(bound / quantum) - 1) * quantum);
}

/// [start] clamped into [window], its upper bound applied first, so an
/// empty window answers its lower bound.
double clampToWindow(double start, BoardStartWindow window) {
  var clamped = start;
  if (clamped > window.max) {
    clamped = window.max;
  }
  if (clamped < window.min) {
    clamped = window.min;
  }
  return clamped;
}

/// The starts that keep a span of [extent] inside a lattice of
/// [trackCount] tracks: `[0, trackCount - extent]`.
BoardStartWindow latticeWindowOf(int trackCount, double extent) {
  return (min: 0.0, max: trackCount - extent);
}

/// The starts that keep a span of [extent] inside [band], or null when the
/// band holds fewer than [extent] tracks, within
/// [precisionErrorTolerance].
BoardStartWindow? bandWindowOf(({int start, int end}) band, double extent) {
  if (band.end - band.start + precisionErrorTolerance < extent) {
    return null;
  }
  return (min: band.start.toDouble(), max: band.end - extent);
}

/// The starts on the grid of [quantum] at which a scrolled span of
/// [extent] shows beside [sample]'s bands, intersected with the lattice's
/// `[0, trackCount - extent]`, or null when no scrolled start shows.
///
/// A present `visibleFrom` bounds the lower side at the first grid start
/// whose span ends past it, and a present `visibleTo` the upper side at
/// the last grid start below it; an absent bound leaves that side at the
/// lattice's, which need not lie on the grid. Null exactly when both
/// bounds are present with `visibleFrom >= visibleTo`, or when the
/// intersection is empty: equal bounds can still give a one-start window
/// over no region, and a thin region can give an empty one under a
/// coarse grid.
BoardStartWindow? scrolledWindowOf(
  BoardAxisSample sample,
  double extent,
  double quantum,
) {
  final from = sample.visibleFrom;
  final to = sample.visibleTo;
  if (from != null && to != null && from >= to) {
    return null;
  }
  var min = 0.0;
  var max = sample.trackCount - extent;
  if (from != null) {
    final bound = firstGridStartAbove(from - extent, quantum);
    if (bound > min) {
      min = bound;
    }
  }
  if (to != null) {
    final bound = lastGridStartBelow(to, quantum);
    if (bound < max) {
      max = bound;
    }
  }
  if (min > max) {
    return null;
  }
  return (min: min, max: max);
}

/// The path a move's corner axis is placed on: the band under [centre]
/// when the span fits it, else the scrolled lattice, else the whole
/// lattice.
BoardAxisPath placementPathOf({
  required BoardAxisSample corner,
  required BoardAxisSample centre,
  required double extent,
  required double quantum,
}) {
  final band = centre.band;
  if (band != null) {
    final window = bandWindowOf(band, extent);
    if (window != null) {
      return (band: band, scrolled: false, window: window);
    }
  }
  return _scrolledOrLatticePathOf(corner, extent, quantum);
}

/// The path of the region the sample's point is over, or the whole
/// lattice where the point is over the scrolled region and no start of
/// [extent] shows there.
BoardAxisPath regionPathOf(
  BoardAxisSample sample, {
  required double extent,
  required double quantum,
}) {
  final band = sample.band;
  if (band != null) {
    return (band: band, scrolled: false, window: bandWindowOf(band, extent)!);
  }
  return _scrolledOrLatticePathOf(sample, extent, quantum);
}

/// The path of the lattice a span pinned in [pinned] lies in, the
/// scrolled one when [pinned] is null (the whole lattice where no start
/// of [extent] shows), with the window that [sample]'s bounds give it.
///
/// A band's window is `[pinned.start, pinned.end - extent]`, empty when
/// the span is longer than the band, which [bandHolding] admits by up to
/// `precisionErrorTolerance` at each end; [clampToWindow] answers an
/// empty window's lower bound.
BoardAxisPath pinnedPathOf(
  ({int start, int end})? pinned,
  BoardAxisSample sample, {
  required double extent,
  required double quantum,
}) {
  if (pinned != null) {
    return (
      band: pinned,
      scrolled: false,
      window: (min: pinned.start.toDouble(), max: pinned.end - extent),
    );
  }
  return _scrolledOrLatticePathOf(sample, extent, quantum);
}

/// The scrolled path when a scrolled start of [extent] shows, else the
/// whole lattice.
BoardAxisPath _scrolledOrLatticePathOf(
  BoardAxisSample sample,
  double extent,
  double quantum,
) {
  final scrolled = scrolledWindowOf(sample, extent, quantum);
  if (scrolled != null) {
    return (band: null, scrolled: true, window: scrolled);
  }
  return (
    band: null,
    scrolled: false,
    window: latticeWindowOf(sample.trackCount, extent),
  );
}

/// `painted` on a band or whole-lattice path, `scrolled` on the scrolled
/// one.
double coordinateIn(BoardAxisPath path, BoardAxisSample sample) {
  return path.scrolled ? sample.scrolled : sample.painted;
}

/// The coordinate a drag measures an item's anchor in: `painted` where
/// [pinned] is non-null, `scrolled` otherwise.
double itemCoordinateOf(
  ({int start, int end})? pinned,
  BoardAxisSample sample,
) {
  return pinned != null ? sample.painted : sample.scrolled;
}

/// [scrolled], a sample point's scrolled coordinate, bounded by the
/// lattice that paints at the point: [painted] where [band] is null, the
/// scrolled region; at least [painted] over the leading band, the one
/// ending at [leadingBandEnd]; at most [painted] over a trailing band.
///
/// On a lattice that fills the viewport, with the scroll offset in range
/// and the geometry settled, the scrolled tracks under a band lie on the
/// band's inner side of its own coordinate, and the bound over a band
/// changes nothing. Where the scrolled region shows past the unfrozen
/// tracks, in the gap a short lattice leaves above a trailing band and
/// under overscroll, the unbounded coordinate reads a band's track that
/// no scrolled cell paints there, and under the band it reads past the
/// band's own coordinate: a displacement from a lift read in the band's
/// lattice to a pointer read in the scrolled one then runs against the
/// pointer, and one read across the band's inner edge jumps.
double boundedScrolled(
  double scrolled, {
  required double painted,
  required ({int start, int end})? band,
  required int leadingBandEnd,
}) {
  if (band == null) {
    return painted;
  }
  if (band.start == 0 && band.end == leadingBandEnd) {
    return scrolled < painted ? painted : scrolled;
  }
  return scrolled > painted ? painted : scrolled;
}

/// Whether two paths name one lattice: the same band, or both scrolled,
/// or both the whole lattice.
bool sameLattice(BoardAxisPath a, BoardAxisPath b) {
  if (a.band != null || b.band != null) {
    return a.band == b.band;
  }
  return a.scrolled == b.scrolled;
}

/// THE PIN TEST: the band an interval lies wholly inside, within
/// `precisionErrorTolerance`, or null.
({int start, int end})? bandHolding(
  double start,
  double end, {
  required int leadingBandEnd,
  required int trailingBandStart,
  required int trackCount,
}) {
  if (leadingBandEnd > 0 &&
      start >= -precisionErrorTolerance &&
      end <= leadingBandEnd + precisionErrorTolerance) {
    return (start: 0, end: leadingBandEnd);
  }
  if (trailingBandStart < trackCount &&
      start >= trailingBandStart - precisionErrorTolerance &&
      end <= trackCount + precisionErrorTolerance) {
    return (start: trailingBandStart, end: trackCount);
  }
  return null;
}

/// A rectangle in TRACK space: an integer start plus a leading fraction on
/// each axis, and an integer span plus a trailing fraction on each axis.
///
/// The fractions are what make a continuous axis expressible: 09:15 on an
/// hour axis is track 9 plus [rowFraction] 0.25, and a 09:15 to 10:45 item
/// is [rowSpan] 1 plus [rowSpanFraction] 0.5.
///
/// Read a span's geometry through [startTrackOn] and [endTrackOn] and
/// nothing else. `startOn(axis) + spanOn(axis)` still compiles and is
/// silently wrong the moment either fraction on that axis is non-zero; no
/// signature change can catch that, so the rule is textual.
///
/// The board reads both ends within `precisionErrorTolerance`: a start
/// that far below a whole track, which arithmetic on a fraction can come
/// to in doubles, starts ON that track, and an end that far past one
/// does not reach into it. A span built as `rowStart: 0, rowFraction:
/// 0.9999999999999999` is on track 1 everywhere the board asks.
@immutable
class BoardSpan {
  /// Creates a span. The two asserts that pair [rowSpan] with
  /// [rowSpanFraction], and their column twins, are what admit a
  /// SUB-TRACK item: a span of 0 with a non-zero span fraction has a
  /// positive extent without the integer span having to be at least 1.
  const BoardSpan({
    required this.rowStart,
    required this.colStart,
    this.rowSpan = 1,
    this.colSpan = 1,
    this.rowFraction = 0.0,
    this.colFraction = 0.0,
    this.rowSpanFraction = 0.0,
    this.colSpanFraction = 0.0,
  }) : assert(rowStart >= 0 && colStart >= 0),
       assert(rowFraction >= 0.0 && rowFraction < 1.0),
       assert(colFraction >= 0.0 && colFraction < 1.0),
       assert(rowSpan >= 0 && colSpan >= 0),
       assert(rowSpanFraction >= 0.0 && rowSpanFraction < 1.0),
       assert(colSpanFraction >= 0.0 && colSpanFraction < 1.0),
       assert(rowSpan + rowSpanFraction > 0.0),
       assert(colSpan + colSpanFraction > 0.0),
       // The extent must SURVIVE at the span's own magnitude: a fraction
       // like 1e-17 passes the sum-at-zero assert above and then vanishes
       // inside startTrackOn/endTrackOn at a non-zero start, leaving a
       // span whose end is its start.
       assert(
         rowStart + rowFraction + rowSpan + rowSpanFraction >
             rowStart + rowFraction,
       ),
       assert(
         colStart + colFraction + colSpan + colSpanFraction >
             colStart + colFraction,
       );

  /// Leading row track. Track space.
  final int rowStart;

  /// Leading column track. Track space.
  final int colStart;

  /// Integer part of the row extent. Track space.
  final int rowSpan;

  /// Integer part of the column extent. Track space.
  final int colSpan;

  /// Fractional offset into [rowStart], for a continuous axis: 09:15 on an
  /// hour axis is track 9 plus 0.25. Track space.
  final double rowFraction;

  /// Fractional offset into [colStart], for a continuous axis. Track
  /// space.
  final double colFraction;

  /// Fractional part of the row EXTENT, for a continuous axis: a 09:15 to
  /// 10:45 item is [rowSpan] 1 plus [rowSpanFraction] 0.5. Track space.
  final double rowSpanFraction;

  /// Fractional part of the column EXTENT, for a continuous axis. Track
  /// space.
  final double colSpanFraction;

  /// The integer span on [axis]. Kept `int` on purpose, so an integer
  /// caller that means the integer still compiles and still means it. It
  /// is NOT the extent once the matching span fraction is non-zero; use
  /// [startTrackOn] and [endTrackOn] for geometry.
  int spanOn(Axis axis) {
    return axis == Axis.vertical ? rowSpan : colSpan;
  }

  /// The integer start track on [axis]. See [spanOn] for why this stays
  /// `int`.
  int startOn(Axis axis) {
    return axis == Axis.vertical ? rowStart : colStart;
  }

  /// The EXACT track-space leading endpoint on [axis]: [startOn] plus the
  /// leading fraction.
  double startTrackOn(Axis axis) {
    return axis == Axis.vertical
        ? rowStart + rowFraction
        : colStart + colFraction;
  }

  /// The EXACT track-space trailing endpoint on [axis]: [startTrackOn]
  /// plus [spanOn] plus the span fraction. The span occupies the HALF-OPEN
  /// interval `[startTrackOn(axis), endTrackOn(axis))`.
  double endTrackOn(Axis axis) {
    return axis == Axis.vertical
        ? rowStart + rowFraction + rowSpan + rowSpanFraction
        : colStart + colFraction + colSpan + colSpanFraction;
  }

  /// Returns a copy with the named fields replaced.
  BoardSpan copyWith({
    int? rowStart,
    int? colStart,
    int? rowSpan,
    int? colSpan,
    double? rowFraction,
    double? colFraction,
    double? rowSpanFraction,
    double? colSpanFraction,
  }) {
    return BoardSpan(
      rowStart: rowStart ?? this.rowStart,
      colStart: colStart ?? this.colStart,
      rowSpan: rowSpan ?? this.rowSpan,
      colSpan: colSpan ?? this.colSpan,
      rowFraction: rowFraction ?? this.rowFraction,
      colFraction: colFraction ?? this.colFraction,
      rowSpanFraction: rowSpanFraction ?? this.rowSpanFraction,
      colSpanFraction: colSpanFraction ?? this.colSpanFraction,
    );
  }

  /// VALUE equality over all eight fields. Required, not decorative: the
  /// drag layer's re-target test compares the previous target with the new
  /// one and notifies only on a difference.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is BoardSpan &&
        other.rowStart == rowStart &&
        other.colStart == colStart &&
        other.rowSpan == rowSpan &&
        other.colSpan == colSpan &&
        other.rowFraction == rowFraction &&
        other.colFraction == colFraction &&
        other.rowSpanFraction == rowSpanFraction &&
        other.colSpanFraction == colSpanFraction;
  }

  @override
  int get hashCode {
    return Object.hash(
      rowStart,
      colStart,
      rowSpan,
      colSpan,
      rowFraction,
      colFraction,
      rowSpanFraction,
      colSpanFraction,
    );
  }

  @override
  String toString() {
    return "BoardSpan(rows [${startTrackOn(Axis.vertical)}, "
        "${endTrackOn(Axis.vertical)}), cols "
        "[${startTrackOn(Axis.horizontal)}, "
        "${endTrackOn(Axis.horizontal)}))";
  }
}

/// One caller item paired with the [BoardSpan] it occupies. The one
/// exported name that carries the item type alone.
@immutable
class BoardPlacement<TItem> {
  /// Creates a placement.
  const BoardPlacement(this.item, this.span);

  /// The caller's item.
  final TItem item;

  /// Where it sits, in track space.
  final BoardSpan span;

  @override
  String toString() {
    return "BoardPlacement($item, $span)";
  }
}
