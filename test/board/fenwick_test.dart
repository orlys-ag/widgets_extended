/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 1 (L0 geometry), which is why these import
/// the module's private files directly: the module barrel lands at step 13,
/// and importing a private file from a test is already the house pattern.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_fenwick.dart';

void main() {
  // AC2 Fenwick oracle.
  // Asserts: 100000 tracks, seeded random measurement ORDER, every measured
  // prefix compared against a naive sum.
  // Falsification: a watermark prefix array passes this case and fails the
  // budget case below on a far jump.
  test(
    "offsetOf and trackAt match a naive summation under random measurement order",
    () {
      const trackCount = 100000;
      const estimate = 20.0;
      final axis = LazyContentAxis(trackCount, estimate);
      // The oracle: one plain extent per track, summed left to right.
      final naiveExtents = List<double>.filled(trackCount, estimate);

      final random = math.Random(20260829);
      final order = List<int>.generate(trackCount, (i) {
        return i;
      })..shuffle(random);

      // Measurement ORDER is what separates a Fenwick from a watermark
      // prefix array, so the script measures in a shuffled order and
      // checks the whole prefix twice on the way through.
      var measured = 0;
      for (final track in order) {
        final extent = 1.0 + random.nextDouble() * 99.0;
        axis.recordMeasurement(track, extent);
        naiveExtents[track] = extent;
        measured++;
        if (measured == trackCount ~/ 2 || measured == trackCount) {
          _expectMatchesNaive(axis, naiveExtents);
        }
      }

      // Setup sanity, and it can fail: an implementation that recorded
      // nothing, or one whose floor swallowed every measurement, leaves the
      // axis provisional and its total at the all-estimate value.
      expect(axis.isProvisional, isFalse);
      expect(axis.totalExtent, isNot(closeTo(trackCount * estimate, 1.0)));
    },
  );

  // AC2 Fenwick oracle.
  // Asserts: debugOpCount per call bounded by a constant times log2 of
  // trackCount.
  // Falsification: a watermark prefix array fails here on a far jump.
  test("operation count stays inside the log budget", () {
    const trackCount = 100000;
    // A constant times log2(trackCount). The structure touches at most one
    // entry per level, so 2 levels of headroom is generous and still three
    // orders of magnitude below the trackCount a linear structure needs.
    final budget = 2 * (math.log(trackCount) / math.ln2).ceil();

    final tree = Fenwick(trackCount);

    tree.debugOpCount = 0;
    tree.add(0, 5.0);
    expect(tree.debugOpCount, lessThanOrEqualTo(budget));

    // The FAR JUMP: an update at the far end, and then a prefix read and a
    // descent across the whole structure. This is the shape a watermark
    // prefix array has to rebuild O(n) for.
    tree.debugOpCount = 0;
    tree.add(trackCount - 1, 7.0);
    expect(tree.debugOpCount, lessThanOrEqualTo(budget));

    tree.debugOpCount = 0;
    tree.prefixSum(trackCount - 1);
    expect(tree.debugOpCount, lessThanOrEqualTo(budget));

    tree.debugOpCount = 0;
    tree.lowerBound(3.0);
    expect(tree.debugOpCount, lessThanOrEqualTo(budget));

    // The same budget through the axis, which is the only consumer: one
    // measurement at the far end, then an offset and a track lookup across
    // the whole axis.
    final axis = LazyContentAxis(trackCount, 20.0);
    final fenwick = axis.debugFenwick;

    fenwick.debugOpCount = 0;
    axis.recordMeasurement(trackCount - 1, 55.0);
    // recordMeasurement reads the current extent (two prefix reads) and
    // then updates, so its budget is the per-call one times three.
    expect(fenwick.debugOpCount, lessThanOrEqualTo(3 * budget));

    fenwick.debugOpCount = 0;
    axis.offsetOf(trackCount - 1);
    expect(fenwick.debugOpCount, lessThanOrEqualTo(budget));

    fenwick.debugOpCount = 0;
    axis.trackAt(axis.totalExtent - 1.0);
    expect(fenwick.debugOpCount, lessThanOrEqualTo(2 * budget));
  });
}

/// Compares every prefix and every track lookup against a naive left to
/// right summation of [naiveExtents].
void _expectMatchesNaive(LazyContentAxis axis, List<double> naiveExtents) {
  final trackCount = axis.trackCount;
  final naiveOffsets = List<double>.filled(trackCount + 1, 0.0);
  var running = 0.0;
  for (var i = 0; i < trackCount; i++) {
    running += naiveExtents[i];
    naiveOffsets[i + 1] = running;
  }
  // Tolerance, not equality: the tree sums in a different ASSOCIATION order
  // than the naive left to right walk, so the two agree to double
  // precision and not to the bit.
  for (var track = 0; track <= trackCount; track++) {
    expect(
      axis.offsetOf(track),
      closeTo(naiveOffsets[track], 1e-6),
      reason: "offsetOf($track)",
    );
  }
  for (var track = 0; track < trackCount; track++) {
    final probe = naiveOffsets[track] + naiveExtents[track] * 0.5;
    expect(axis.trackAt(probe), track, reason: "trackAt inside track $track");
  }
  // LEADING EDGES, and not only midpoints. offsetOf and the descent
  // trackAt runs are different floating-point expressions over the same
  // tree, and they disagree at the boundary and nowhere else, so a
  // midpoint-only oracle cannot see it. The probe is the axis's OWN
  // offsetOf rather than the naive offset: the constraint is the
  // round-trip, and the naive sum accumulates in a different association.
  for (var track = 0; track < trackCount; track++) {
    expect(
      axis.trackAt(axis.offsetOf(track)),
      track,
      reason: "trackAt(offsetOf($track))",
    );
  }
  expect(axis.totalExtent, closeTo(naiveOffsets[trackCount], 1e-6));
}
