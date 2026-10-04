/// Internal: the drop-fit search, which slides a REFUSED move onto nearby
/// free space.
///
/// Two pure functions over spans and axes, with no key type, no
/// controller and no render port: the caller supplies the obstacles and
/// the predicate, so this library never learns what "occupied" means to
/// an app. It answers how much of a box is geometrically free, and which
/// nearby placement holds the whole box clear of everything.
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

  /// Steps the scan may take per direction on one axis, whatever radius
  /// the policy asks for.
  ///
  /// Four honours a one-track radius at the finest quantum (a quarter
  /// track) and a four-track one under a whole-track snap, which covers
  /// every radius a board is likely to set, and it bounds the candidate
  /// set at `9 * 9 - 1`. Without a cap a `free` snap with a large radius
  /// would generate an unbounded set, every member of which can reach the
  /// app's predicate.
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
      final raw = (radius / quantum).floor();
      return raw < maxStepsPerDirection ? raw : maxStepsPerDirection;
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
    final low = stepped
        ? clampToWindow(start - radius, window).floor()
        : (start - radius).floor();
    var high = (end + radius).ceil();
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
  /// Candidates are [box] translated by whole quanta, clamped into the
  /// window of each axis it steps, [rowWindow] and [colWindow], and
  /// tested in ascending CONTENT-SPACE distance from the box's leading
  /// corner. The order is TOTAL, distance then row step then column
  /// step, so two candidates at equal distance cannot swap between two
  /// resolves and flicker the preview. An axis the scan does not step
  /// keeps the box's own fields.
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
    final rowQuantum = BoardDropResolver.quantumOn(
      Axis.vertical,
      snap,
      wholeTrackAxis,
    );
    final colQuantum = BoardDropResolver.quantumOn(
      Axis.horizontal,
      snap,
      wholeTrackAxis,
    );
    final rowLow = box.startTrackOn(Axis.vertical);
    final colLow = box.startTrackOn(Axis.horizontal);
    final baseRow = rowAxis.offsetOfFraction(rowLow);
    final baseCol = colAxis.offsetOfFraction(colLow);

    final candidates =
        <({double distance, int dRow, int dCol, BoardSpan span})>[];
    for (var dRow = -steps.rows; dRow <= steps.rows; dRow++) {
      for (var dCol = -steps.cols; dCol <= steps.cols; dCol++) {
        if (dRow == 0 && dCol == 0) {
          continue;
        }
        // Clamped BEFORE the split, and the distance is read off the
        // clamped value: at a window edge the clamp moves a candidate,
        // so the step count stops describing how far it went.
        // Each candidate start snapped to a track edge it lies within the
        // tolerance of: `low + d * quantum` is a sum of two exact
        // multiples, which in doubles can come to one ulp below the
        // integer it means.
        // An axis the scan does not step keeps the box's own fields: no
        // clamp, no floor and no re-split, and no distance.
        var row = rowLow;
        var col = colLow;
        if (dRow != 0) {
          row = clampToWindow(
            snapToTrackEdge(rowLow + dRow * rowQuantum),
            rowWindow,
          );
          if (wholeTrackAxis == Axis.vertical) {
            row = row.floorToDouble();
          }
        }
        if (dCol != 0) {
          col = clampToWindow(
            snapToTrackEdge(colLow + dCol * colQuantum),
            colWindow,
          );
          if (wholeTrackAxis == Axis.horizontal) {
            col = col.floorToDouble();
          }
        }
        // RE-SPLIT, never an addition to the fraction field: a span
        // asserts its leading fraction below 1.0, so a quantum carrying
        // past a track boundary has to move the integer start.
        final span = box.copyWith(
          rowStart: dRow == 0 ? null : row.floor(),
          rowFraction: dRow == 0 ? null : row - row.floorToDouble(),
          colStart: dCol == 0 ? null : col.floor(),
          colFraction: dCol == 0 ? null : col - col.floorToDouble(),
        );
        final dy = dRow == 0 ? 0.0 : rowAxis.offsetOfFraction(row) - baseRow;
        final dx = dCol == 0 ? 0.0 : colAxis.offsetOfFraction(col) - baseCol;
        candidates.add((
          // Squared, which orders identically and avoids the root.
          distance: dx * dx + dy * dy,
          dRow: dRow,
          dCol: dCol,
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
