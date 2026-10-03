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
