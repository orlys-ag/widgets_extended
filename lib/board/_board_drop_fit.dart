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
  static ({int rows, int cols}) stepsOf({
    required BoardDropFit policy,
    required BoardSnap snap,
  }) {
    final quantum = BoardDropResolver.quantumOf(snap);
    int stepsFor(double radius) {
      if (radius <= 0.0 || quantum <= 0.0) {
        return 0;
      }
      final raw = (radius / quantum).floor();
      return raw < maxStepsPerDirection ? raw : maxStepsPerDirection;
    }

    return (
      rows: stepsFor(policy.rowRadius),
      cols: stepsFor(policy.colRadius),
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
  /// lattice by the resolver's own endpoint rule, and tested in ascending
  /// CONTENT-SPACE distance from the box's leading corner. The order is
  /// TOTAL, distance then row step then column step, so two candidates at
  /// equal distance cannot swap between two resolves and flicker the
  /// preview.
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
  }) {
    final steps = stepsOf(policy: policy, snap: snap);
    if (steps.rows == 0 && steps.cols == 0) {
      return null;
    }
    final quantum = BoardDropResolver.quantumOf(snap);
    final rowLow = box.startTrackOn(Axis.vertical);
    final colLow = box.startTrackOn(Axis.horizontal);
    final rowExtent = box.endTrackOn(Axis.vertical) - rowLow;
    final colExtent = box.endTrackOn(Axis.horizontal) - colLow;
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
        // clamped value: at the lattice edge the clamp moves a candidate,
        // so the step count stops describing how far it went.
        final row = BoardDropResolver.clampStart(
          rowLow + dRow * quantum,
          rowExtent,
          rowAxis.trackCount,
        );
        final col = BoardDropResolver.clampStart(
          colLow + dCol * quantum,
          colExtent,
          colAxis.trackCount,
        );
        // RE-SPLIT, never an addition to the fraction field: a span
        // asserts its leading fraction below 1.0, so a quantum carrying
        // past a track boundary has to move the integer start.
        final span = box.copyWith(
          rowStart: row.floor(),
          rowFraction: row - row.floorToDouble(),
          colStart: col.floor(),
          colFraction: col - col.floorToDouble(),
        );
        final dy = rowAxis.offsetOfFraction(row) - baseRow;
        final dx = colAxis.offsetOfFraction(col) - baseCol;
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
