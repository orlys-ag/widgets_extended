/// Internal: the drop-fit search, which slides a REFUSED move onto nearby
/// free space and stops a refused resize at the item in its way.
///
/// Pure functions over spans and axes, with no key type, no controller
/// and no render port: the caller supplies the obstacles and the
/// predicate, so this library never learns what "occupied" means to an
/// app. It answers how much of a box is geometrically free, which nearby
/// placement holds the whole box clear of everything, and where a
/// dragged edge stops short of an item.
///
/// THE BOX IS ALWAYS A SPAN'S RECTANGLE and never a painted one. A laned
/// item paints as a slice of its lane-axis track, so two items sharing a
/// time paint side by side while their spans overlap completely, and what
/// a drop conflicts with is the interval held rather than the pixels
/// drawn.
///
/// Not exported from the module barrel.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '_board_axis.dart';
import '_board_drop_resolver.dart';
import '_board_span.dart';
import 'board_config.dart';

/// One obstacle clipped to the box under test, in track space.
class _Clipped {
  const _Clipped(this.rowLow, this.rowHigh, this.colLow, this.colHigh);

  final double rowLow;
  final double rowHigh;
  final double colLow;
  final double colHigh;

  bool covers(double row, double col) {
    return row >= rowLow && row < rowHigh && col >= colLow && col < colHigh;
  }
}

/// The gate and the scan behind `BoardDragConfig.dropFit`.
class BoardDropFitter {
  BoardDropFitter._();

  /// Steps the scan takes per direction on one axis, whatever radius the
  /// policy asks for.
  ///
  /// The steps are the placements the scan tries whether or not an item
  /// ends there, so that a free placement the app's predicate refuses can
  /// give way to its neighbour. Beyond them the radius is searched through
  /// the FLUSH placements alone ([nearestFit]), which are what bounds the
  /// candidate set by the obstacles rather than by the radius: stepping a
  /// large radius would generate a set as long as the radius, every
  /// member of which can reach the app's predicate.
  static const int maxStepsPerDirection = 4;

  /// Steps available per axis under [policy] and [snap]. Both zero means
  /// no candidate can exist, which the caller uses to skip the gather and
  /// the gate entirely.
  ///
  /// [wholeTrackAxis] is an axis the scan steps by WHOLE tracks whatever
  /// the snap: the lane axis of a laned item, which occupies one track
  /// there and moves by whole tracks, as the resolver moves it.
  static ({int rows, int cols}) stepsOf({
    required BoardDropFit policy,
    required BoardSnap snap,
    Axis? wholeTrackAxis,
  }) {
    int stepsFor(double radius, Axis axis) {
      final quantum = BoardDropResolver.quantumOn(axis, snap, wholeTrackAxis);
      if (radius <= 0.0 || quantum <= 0.0) {
        return 0;
      }
      // Compared before the floor, which an infinite radius would throw
      // on.
      final raw = radius / quantum;
      return raw < maxStepsPerDirection ? raw.floor() : maxStepsPerDirection;
    }

    return (
      rows: stepsFor(policy.rowRadius, Axis.vertical),
      cols: stepsFor(policy.colRadius, Axis.horizontal),
    );
  }

  /// [box] moved onto the lattice on each axis where it starts at or past
  /// the lattice's end, [rowCount] or [colCount]: its start is clamped
  /// into that axis's window of starts, [rowWindow] or [colWindow], so it
  /// takes the window's last start, or its first where the window is
  /// empty, and is floored to a whole track under a track [snap] and on
  /// [wholeTrackAxis], as the resolver places a start; its extent is kept.
  /// An axis where it starts inside the lattice keeps its fields. Null
  /// where an axis has no track.
  static BoardSpan? ontoLattice(
    BoardSpan box, {
    required int rowCount,
    required int colCount,
    required BoardStartWindow rowWindow,
    required BoardStartWindow colWindow,
    required BoardSnap snap,
    Axis? wholeTrackAxis,
  }) {
    if (rowCount <= 0 || colCount <= 0) {
      return null;
    }
    double? onto(Axis axis, int count, BoardStartWindow window) {
      final start = box.startTrackOn(axis);
      if (start < count) {
        return null;
      }
      final moved = clampToWindow(start, window);
      final whole = snap.mode == BoardSnapMode.track || axis == wholeTrackAxis;
      return whole ? moved.floorToDouble() : moved;
    }

    final row = onto(Axis.vertical, rowCount, rowWindow);
    final col = onto(Axis.horizontal, colCount, colWindow);
    if (row == null && col == null) {
      return box;
    }
    return box.copyWith(
      rowStart: row?.floor(),
      rowFraction: row == null ? null : row - row.floorToDouble(),
      colStart: col?.floor(),
      colFraction: col == null ? null : col - col.floorToDouble(),
    );
  }

  /// The SEARCH REGION on one axis, as a half-open range of whole tracks:
  /// the smallest one covering the box `[start, end)`'s own tracks and the
  /// box widened by [radius] on BOTH sides, clamped to `[0, trackCount]`.
  ///
  /// On an axis the scan [stepped], the widened box's two ends are
  /// CLAMPED into the reach of [window]: the near one is
  /// `floor(clampToWindow(start - radius))`, and the far one is
  /// `ceil(end + radius)` clamped into `[ceil(window.min + extent),
  /// ceil(window.max + extent)]`, upper bound first as [clampToWindow]
  /// applies it, `extent` being `end - start`. In exact arithmetic that is
  /// `ceil(clampToWindow(start + radius) + extent)`, and wherever neither
  /// clamp binds both ends are the widened box's own expressions, so no
  /// rounding of a different sum moves an end across a track edge. A
  /// candidate there is the box moved by at most [radius], clamped into
  /// [window] and, on the whole-track axis, floored, keeping the box's own
  /// extent; the clamp is monotone and the floor only lowers a start, so
  /// every candidate lies inside the clamped ends. An axis the scan does
  /// not step keeps the box's own fields, and its range is the widened
  /// box, [window] unread.
  static ({int start, int end}) searchRangeOn({
    required double start,
    required double end,
    required double radius,
    required BoardStartWindow window,
    required bool stepped,
    required int trackCount,
  }) {
    // Each end is bounded by the lattice before it is rounded, which an
    // infinite radius would otherwise throw on; the bound changes no
    // finite answer, since the result is clamped to the same range.
    final low = stepped
        ? clampToWindow(start - radius, window).floor()
        : math.max(start - radius, 0.0).floor();
    var high = math.min(end + radius, trackCount.toDouble()).ceil();
    if (stepped) {
      final last = (window.max + (end - start)).ceil();
      if (high > last) {
        high = last;
      }
      final first = (window.min + (end - start)).ceil();
      if (high < first) {
        high = first;
      }
    }
    final own = start.floor();
    final ownEnd = end.ceil();
    return (
      start: (low < own ? low : own).clamp(0, trackCount),
      end: (high > ownEnd ? high : ownEnd).clamp(0, trackCount),
    );
  }

  /// The share of [box] that no obstacle covers, by CONTENT-SPACE area.
  ///
  /// The caller passes the SEARCH REGION here, not the item's own box:
  /// measuring the box asks what share of the item is free, which for a
  /// box aligned to whole tracks against occupants also aligned to whole
  /// tracks is only ever 0 or 1, so a threshold between them can never be
  /// met and the gate is unreachable for a single-cell item. Measuring
  /// the region asks whether the neighbourhood being dropped into is
  /// mostly empty, which is a question every shape can answer.
  ///
  /// [obstacles] may cover ground outside [box], because the caller
  /// gathers once for the whole search region, so the first step is a
  /// clip that drops everything not meeting it.
  ///
  /// The covered area is the area of the UNION of the clipped obstacles,
  /// by coordinate compression. Summing their areas instead would double
  /// count two occupants overlapping each other, which on a board with
  /// lanes is the ordinary case, and could report a negative free area.
  static double freeFractionOf({
    required BoardSpan box,
    required List<BoardSpan> obstacles,
    required BoardAxis rowAxis,
    required BoardAxis colAxis,
  }) {
    final rowLow = box.startTrackOn(Axis.vertical);
    final rowHigh = box.endTrackOn(Axis.vertical);
    final colLow = box.startTrackOn(Axis.horizontal);
    final colHigh = box.endTrackOn(Axis.horizontal);
    // Strictly positive by construction: a span asserts a positive extent
    // on both axes and every axis floors its extents at a strictly
    // positive minTrackExtent, so this needs no zero guard.
    final boxArea =
        _lengthOf(rowAxis, rowLow, rowHigh) *
        _lengthOf(colAxis, colLow, colHigh);

    final clipped = <_Clipped>[];
    for (final obstacle in obstacles) {
      final r0 = math.max(rowLow, obstacle.startTrackOn(Axis.vertical));
      final r1 = math.min(rowHigh, obstacle.endTrackOn(Axis.vertical));
      final c0 = math.max(colLow, obstacle.startTrackOn(Axis.horizontal));
      final c1 = math.min(colHigh, obstacle.endTrackOn(Axis.horizontal));
      // Half-open on both axes: an occupant beginning exactly where the
      // box ends does not meet it.
      if (r1 > r0 && c1 > c0) {
        clipped.add(_Clipped(r0, r1, c0, c1));
      }
    }
    if (clipped.isEmpty) {
      return 1.0;
    }

    final rows = <double>{rowLow, rowHigh};
    final cols = <double>{colLow, colHigh};
    for (final entry in clipped) {
      rows.add(entry.rowLow);
      rows.add(entry.rowHigh);
      cols.add(entry.colLow);
      cols.add(entry.colHigh);
    }
    final rowEdges = rows.toList()..sort();
    final colEdges = cols.toList()..sort();

    var covered = 0.0;
    for (var i = 0; i + 1 < rowEdges.length; i++) {
      final rowMid = (rowEdges[i] + rowEdges[i + 1]) / 2.0;
      for (var j = 0; j + 1 < colEdges.length; j++) {
        final colMid = (colEdges[j] + colEdges[j + 1]) / 2.0;
        var hit = false;
        for (final entry in clipped) {
          if (entry.covers(rowMid, colMid)) {
            hit = true;
            break;
          }
        }
        if (hit) {
          covered +=
              _lengthOf(rowAxis, rowEdges[i], rowEdges[i + 1]) *
              _lengthOf(colAxis, colEdges[j], colEdges[j + 1]);
        }
      }
    }
    final free = boxArea - covered;
    return free <= 0.0 ? 0.0 : free / boxArea;
  }

  /// The nearest placement within [policy]'s radius that holds [box]
  /// clear of every obstacle and that [accepts] admits, or null when
  /// nothing does.
  ///
  /// Candidates are [box] moved to one START per axis, clamped into the
  /// window of each axis it steps, [rowWindow] and [colWindow], and
  /// tested in ascending CONTENT-SPACE distance from the box's leading
  /// corner. An axis the scan does not step offers the box's own fields
  /// alone. An axis it steps offers the box's own start, the starts up to
  /// [maxStepsPerDirection] quanta from it, and, within the radius, the
  /// FLUSH starts: for each obstacle, the first start on the box's grid
  /// at or past the obstacle's end, and the last one at which the box
  /// ends at or before the obstacle's start.
  ///
  /// THE FLUSH STARTS ARE WHAT REACH THE WHOLE RADIUS. Take the nearest
  /// placement on the box's grid that holds the box clear, and move it
  /// one quantum toward the box's own start on one axis. That placement is
  /// nearer, so it meets an obstacle, one the original clears: the
  /// original's start on that axis is that obstacle's flush start. So the
  /// nearest clear placement starts, on each axis, at the box's own start
  /// or at a flush one, and the set grows with the obstacles rather than
  /// with the radius.
  ///
  /// The order is TOTAL, distance then the signed track-space offset on
  /// the row axis then on the column axis, so two candidates at equal
  /// distance cannot swap between two resolves and flicker the preview.
  ///
  /// TWO COSTS, and only one is app code: every candidate pays a
  /// rectangle test against [obstacles], while only a FREE candidate
  /// reaches [accepts], and the walk stops at the first admitted.
  static BoardSpan? nearestFit({
    required BoardSpan box,
    required BoardDropFit policy,
    required BoardSnap snap,
    required BoardAxis rowAxis,
    required BoardAxis colAxis,
    required List<BoardSpan> obstacles,
    required bool Function(BoardSpan candidate) accepts,
    required BoardStartWindow rowWindow,
    required BoardStartWindow colWindow,
    Axis? wholeTrackAxis,
  }) {
    final steps = stepsOf(
      policy: policy,
      snap: snap,
      wholeTrackAxis: wholeTrackAxis,
    );
    if (steps.rows == 0 && steps.cols == 0) {
      return null;
    }
    final rows = _startsOn(
      Axis.vertical,
      box: box,
      steps: steps.rows,
      radius: policy.rowRadius,
      quantum: BoardDropResolver.quantumOn(Axis.vertical, snap, wholeTrackAxis),
      window: rowWindow,
      whole: wholeTrackAxis == Axis.vertical,
      obstacles: obstacles,
    );
    final cols = _startsOn(
      Axis.horizontal,
      box: box,
      steps: steps.cols,
      radius: policy.colRadius,
      quantum: BoardDropResolver.quantumOn(
        Axis.horizontal,
        snap,
        wholeTrackAxis,
      ),
      window: colWindow,
      whole: wholeTrackAxis == Axis.horizontal,
      obstacles: obstacles,
    );
    final rowLow = box.startTrackOn(Axis.vertical);
    final colLow = box.startTrackOn(Axis.horizontal);
    final baseRow = rowAxis.offsetOfFraction(rowLow);
    final baseCol = colAxis.offsetOfFraction(colLow);
    final rowOffsets = <double>[
      for (final row in rows)
        row == null ? 0.0 : rowAxis.offsetOfFraction(row) - baseRow,
    ];
    final colOffsets = <double>[
      for (final col in cols)
        col == null ? 0.0 : colAxis.offsetOfFraction(col) - baseCol,
    ];

    final candidates =
        <({double distance, double dRow, double dCol, BoardSpan span})>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      for (var j = 0; j < cols.length; j++) {
        final col = cols[j];
        if (row == null && col == null) {
          continue;
        }
        // RE-SPLIT, never an addition to the fraction field: a span
        // asserts its leading fraction below 1.0, so a move carrying past
        // a track boundary has to move the integer start. An axis offering
        // the box's own start keeps the box's own fields.
        final span = box.copyWith(
          rowStart: row?.floor(),
          rowFraction: row == null ? null : row - row.floorToDouble(),
          colStart: col?.floor(),
          colFraction: col == null ? null : col - col.floorToDouble(),
        );
        final dy = rowOffsets[i];
        final dx = colOffsets[j];
        candidates.add((
          // Squared, which orders identically and avoids the root.
          distance: dx * dx + dy * dy,
          dRow: row == null ? 0.0 : row - rowLow,
          dCol: col == null ? 0.0 : col - colLow,
          span: span,
        ));
      }
    }
    candidates.sort((a, b) {
      final byDistance = a.distance.compareTo(b.distance);
      if (byDistance != 0) {
        return byDistance;
      }
      final byRow = a.dRow.compareTo(b.dRow);
      if (byRow != 0) {
        return byRow;
      }
      return a.dCol.compareTo(b.dCol);
    });

    for (final candidate in candidates) {
      if (meetsAny(candidate.span, obstacles)) {
        continue;
      }
      if (!accepts(candidate.span)) {
        continue;
      }
      return candidate.span;
    }
    return null;
  }

  /// The starts [nearestFit] offers on [axis], each distinct: null first,
  /// for the box's own fields, and then, unless [steps] is zero, the
  /// starts up to [steps] quanta either way and the flush starts within
  /// [radius] (see [nearestFit]), all on the box's grid: its start plus
  /// whole quanta, or on the [whole]-track axis its own track plus whole
  /// tracks.
  ///
  /// Each is snapped to a track edge it lies within the tolerance of, as
  /// `low + k * quantum` is a sum of two exact multiples that in doubles
  /// can come to one ulp below the integer it means; clamped into
  /// [window] before the caller splits it, so the distance is read off
  /// the clamped value; and, on the [whole]-track axis, floored. A flush
  /// start is counted in whole quanta within the tolerance, so an
  /// obstacle edge one ulp off the grid does not push it a quantum on.
  static List<double?> _startsOn(
    Axis axis, {
    required BoardSpan box,
    required int steps,
    required double radius,
    required double quantum,
    required BoardStartWindow window,
    required bool whole,
    required List<BoardSpan> obstacles,
  }) {
    final starts = <double?>[null];
    if (steps == 0) {
      return starts;
    }
    final low = box.startTrackOn(axis);
    final seen = <double>{low};
    void add(double start) {
      var placed = clampToWindow(snapToTrackEdge(start), window);
      if (whole) {
        placed = placed.floorToDouble();
      }
      if (seen.add(placed)) {
        starts.add(placed);
      }
    }

    for (var step = 1; step <= steps; step++) {
      add(low - step * quantum);
      add(low + step * quantum);
    }
    // The grid a candidate lands on: on the whole-track axis the steps
    // above land on whole tracks, the box's own track plus whole tracks,
    // and a flush start is counted on the same grid. Zero quanta is the
    // box's own start, offered as null, or on the whole-track axis its own
    // track, which the steps never offer either.
    final base = whole ? low.floorToDouble() : low;
    final extent = box.endTrackOn(axis) - low;
    for (final obstacle in obstacles) {
      final past =
          ((obstacle.endTrackOn(axis) - base) / quantum -
                  precisionErrorTolerance)
              .ceil();
      final before =
          ((obstacle.startTrackOn(axis) - extent - base) / quantum +
                  precisionErrorTolerance)
              .floor();
      for (final quanta in <int>[past, before]) {
        if (quanta != 0 &&
            (quanta * quantum).abs() <= radius + precisionErrorTolerance) {
          add(base + quanta * quantum);
        }
      }
    }
    return starts;
  }

  /// The span a RESIZE that [BoardDragConfig.canDropAt] refused at
  /// [refused] takes when its dragged edge stops at the item in its way,
  /// or null when nothing stops it: [kind] names the dragged edge, and
  /// [lift] is the item's span when the drag began, which [refused] shares
  /// but for that edge.
  ///
  /// An obstacle that [lift] already meets is not in the edge's way: the
  /// item overlapped it before the drag, so it is not what the drag ran
  /// into. With the rest, the gate's first term is the move's: [refused]
  /// must meet one, so a refusal for a rule of the app's own stops
  /// nothing.
  ///
  /// The edges tried lie between the lifted edge and the refused one, on
  /// the snap's grid, the lifted edge included: up to
  /// [maxStepsPerDirection] quanta back from the refused edge, the edge
  /// flush against each obstacle in the way (at or before its start for a
  /// trailing edge, at or after its end for a leading one), and the
  /// lifted edge, whose span is [lift] itself. They are tried nearest the
  /// refused edge first, so the item keeps as much of the drag as holds
  /// it clear of those obstacles and [accepts] admits. The flush edges
  /// make that the whole drag: the edge nearest the pointer that holds
  /// the span clear is flush against the obstacle that stops it one
  /// quantum further on.
  static BoardSpan? clampedResize({
    required BoardSpan lift,
    required BoardSpan refused,
    required BoardDragKind kind,
    required BoardSnap snap,
    required List<BoardSpan> obstacles,
    required bool Function(BoardSpan candidate) accepts,
  }) {
    assert(kind != BoardDragKind.move, "clampedResize: a move has no edge.");
    final axis =
        kind == BoardDragKind.resizeRowStart ||
            kind == BoardDragKind.resizeRowEnd
        ? Axis.vertical
        : Axis.horizontal;
    final leading =
        kind == BoardDragKind.resizeRowStart ||
        kind == BoardDragKind.resizeColStart;
    final inWay = <BoardSpan>[
      for (final obstacle in obstacles)
        if (!meetsAny(lift, <BoardSpan>[obstacle])) obstacle,
    ];
    if (!meetsAny(refused, inWay)) {
      return null;
    }
    final from = leading ? lift.startTrackOn(axis) : lift.endTrackOn(axis);
    final to = leading ? refused.startTrackOn(axis) : refused.endTrackOn(axis);
    final held = leading
        ? refused.endTrackOn(axis)
        : refused.startTrackOn(axis);
    final forward = to > from;
    bool between(double edge) {
      return forward
          ? edge > from + precisionErrorTolerance &&
                edge < to - precisionErrorTolerance
          : edge < from - precisionErrorTolerance &&
                edge > to + precisionErrorTolerance;
    }

    final quantum = BoardDropResolver.quantumOf(snap);
    final edges = <double>{};
    for (var step = 1; step <= maxStepsPerDirection; step++) {
      final edge = snapToTrackEdge(
        forward ? to - step * quantum : to + step * quantum,
      );
      if (between(edge)) {
        edges.add(edge);
      }
    }
    for (final obstacle in inWay) {
      final edge = forward
          ? _gridAtOrBelow(obstacle.startTrackOn(axis), snap)
          : _gridAtOrAbove(obstacle.endTrackOn(axis), snap);
      if (between(edge)) {
        edges.add(edge);
      }
    }
    final ordered = edges.toList()
      ..sort((a, b) {
        return (to - a).abs().compareTo((to - b).abs());
      });
    for (final edge in ordered) {
      final candidate = _withEdge(refused, axis, leading, edge, held);
      if (meetsAny(candidate, inWay) || !accepts(candidate)) {
        continue;
      }
      return candidate;
    }
    // The lifted span meets nothing in the way by construction.
    return accepts(lift) ? lift : null;
  }

  /// [span] with its [leading] or trailing edge on [axis] at [edge], the
  /// other one at [held], re-split as the resolver writes a resize.
  static BoardSpan _withEdge(
    BoardSpan span,
    Axis axis,
    bool leading,
    double edge,
    double held,
  ) {
    final start = leading ? edge : held;
    final extent = leading ? held - edge : edge - held;
    final whole = extent.floor();
    final fraction = extent - whole;
    if (!leading) {
      return axis == Axis.vertical
          ? span.copyWith(rowSpan: whole, rowSpanFraction: fraction)
          : span.copyWith(colSpan: whole, colSpanFraction: fraction);
    }
    final startTrack = start.floor();
    final startFraction = start - startTrack;
    return axis == Axis.vertical
        ? span.copyWith(
            rowStart: startTrack,
            rowFraction: startFraction,
            rowSpan: whole,
            rowSpanFraction: fraction,
          )
        : span.copyWith(
            colStart: startTrack,
            colFraction: startFraction,
            colSpan: whole,
            colSpanFraction: fraction,
          );
  }

  /// The last point of [snap]'s grid at or below [trackSpace], within the
  /// tolerance; [trackSpace] itself under a free snap, which has no grid.
  static double _gridAtOrBelow(double trackSpace, BoardSnap snap) {
    if (snap.mode == BoardSnapMode.free) {
      return trackSpace;
    }
    final quantum = BoardDropResolver.quantumOf(snap);
    return snapToTrackEdge(
      (trackSpace / quantum + precisionErrorTolerance).floor() * quantum,
    );
  }

  /// The first point of [snap]'s grid at or above [trackSpace], within
  /// the tolerance; [trackSpace] itself under a free snap.
  static double _gridAtOrAbove(double trackSpace, BoardSnap snap) {
    if (snap.mode == BoardSnapMode.free) {
      return trackSpace;
    }
    final quantum = BoardDropResolver.quantumOf(snap);
    return snapToTrackEdge(
      (trackSpace / quantum - precisionErrorTolerance).ceil() * quantum,
    );
  }

  /// Whether any obstacle intersects [span], half-open on both axes.
  ///
  /// The gate's FIRST term reads this rather than comparing an area
  /// against 1.0: it answers the same question in `O(n)` where the area
  /// is cubic, and it answers it about the BOX while the second term
  /// measures the REGION.
  static bool meetsAny(BoardSpan span, List<BoardSpan> obstacles) {
    for (final obstacle in obstacles) {
      if (span.startTrackOn(Axis.vertical) <
              obstacle.endTrackOn(Axis.vertical) &&
          obstacle.startTrackOn(Axis.vertical) <
              span.endTrackOn(Axis.vertical) &&
          span.startTrackOn(Axis.horizontal) <
              obstacle.endTrackOn(Axis.horizontal) &&
          obstacle.startTrackOn(Axis.horizontal) <
              span.endTrackOn(Axis.horizontal)) {
        return true;
      }
    }
    return false;
  }

  /// The content-space length of a track-space interval on [axis]. The
  /// one conversion in this library, and what makes every area PIXELS
  /// rather than a count of cells: three of the four axis kinds allow
  /// unequal tracks.
  static double _lengthOf(BoardAxis axis, double low, double high) {
    return axis.offsetOfFraction(high) - axis.offsetOfFraction(low);
  }
}
