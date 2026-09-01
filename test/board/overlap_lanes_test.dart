/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 2 (L1 store). The stub carried these as
/// `testWidgets` cases; at step 2 there is no `BoardController` and no
/// widget to pump, so they drive `OverlapLaneResolver` and `BoardStore`
/// directly and are plain `test` cases. `laneOf` and `laneCountOf` below are
/// the store's id-keyed reads, which the controller's key-keyed pair will
/// forward to at step 4, preceded by the same `ensureResolved` flush this
/// file calls explicitly.
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/_board_store.dart';
import 'package:widgets_extended/board/_overlap_lanes.dart';

void main() {
  // AC6 lane assignment.
  // Asserts: no two cluster members share a lane and laneCount equals
  // maximum concurrency.
  // Falsification: the plan states the greedy defeater on the second case,
  // not on this one.
  test("three mutually overlapping items take three lanes", () {
    final store = BoardStore<String, String>();
    // Columns carry the lane extent, so the LANE axis is the columns and
    // the sweep runs along the rows.
    final resolver = OverlapLaneResolver(
      store: store,
      laneAxis: Axis.horizontal,
    );

    final a = _add(
      store,
      resolver,
      "a",
      const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 3),
    );
    final b = _add(
      store,
      resolver,
      "b",
      const BoardSpan(rowStart: 1, colStart: 0, rowSpan: 3),
    );
    final c = _add(
      store,
      resolver,
      "c",
      const BoardSpan(rowStart: 2, colStart: 0, rowSpan: 3),
    );

    // Setup sanity, all falsifiable: the three must be laned at all, and
    // they must land in ONE lane-axis bucket, or "cluster members" would
    // name nobody.
    expect(resolver.isLaned(a), isTrue);
    expect(resolver.isLaned(b), isTrue);
    expect(resolver.isLaned(c), isTrue);
    expect(resolver.bucketCount, 1);
    expect(resolver.hasDirtyBuckets, isTrue);

    resolver.ensureResolved();
    expect(resolver.debugBucketResolveCount, 1);
    expect(resolver.hasDirtyBuckets, isFalse);

    // No two cluster members share a lane: all three overlap at row 2.
    expect(<int>{
      store.laneOf(a),
      store.laneOf(b),
      store.laneOf(c),
    }, hasLength(3));
    // And laneCount equals the maximum concurrency, which is 3.
    expect(store.laneCountOf(a), 3);
    expect(store.laneCountOf(b), 3);
    expect(store.laneCountOf(c), 3);
  });

  // AC6 lane assignment.
  // Asserts: laneCount equals maximum concurrency, which for the chain is 2
  // rather than the chain's length.
  // Falsification: a greedy first-fit that never closes clusters fails this
  // case.
  //
  // The fixture carries the chain AND a denser group in the SAME lane-axis
  // track, because a bucket holding only the chain cannot separate the two
  // implementations: a first-fit that never closes still REUSES lanes, so
  // it reports 2 for a chain that is alone. What closing decides is that
  // the chain's members get the CHAIN's count and not the bucket's.
  test("a pairwise-but-not-mutually overlapping chain closes its clusters", () {
    final store = BoardStore<String, String>();
    final resolver = OverlapLaneResolver(
      store: store,
      laneAxis: Axis.horizontal,
    );

    // The chain: each overlaps only its neighbours, so concurrency is 2.
    final a = _add(
      store,
      resolver,
      "a",
      const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 2),
    );
    final b = _add(
      store,
      resolver,
      "b",
      const BoardSpan(rowStart: 1, colStart: 0, rowSpan: 2),
    );
    final c = _add(
      store,
      resolver,
      "c",
      const BoardSpan(rowStart: 2, colStart: 0, rowSpan: 2),
    );
    final d = _add(
      store,
      resolver,
      "d",
      const BoardSpan(rowStart: 3, colStart: 0, rowSpan: 2),
    );
    // A second, denser cluster further down the same column, needing 3.
    final x = _add(
      store,
      resolver,
      "x",
      const BoardSpan(rowStart: 10, colStart: 0, rowSpan: 3),
    );
    final y = _add(
      store,
      resolver,
      "y",
      const BoardSpan(rowStart: 11, colStart: 0, rowSpan: 3),
    );
    final z = _add(
      store,
      resolver,
      "z",
      const BoardSpan(rowStart: 12, colStart: 0, rowSpan: 3),
    );

    // Setup sanity, and it can fail: all seven must share ONE lane-axis
    // bucket, or the two groups would be resolved apart for the wrong
    // reason and the case would prove nothing about closing.
    expect(resolver.bucketCount, 1);

    resolver.ensureResolved();

    // The chain's members take the CHAIN's concurrency, not the bucket's.
    expect(store.laneCountOf(a), 2);
    expect(store.laneCountOf(b), 2);
    expect(store.laneCountOf(c), 2);
    expect(store.laneCountOf(d), 2);
    // Neighbours never share a lane, and the lane frees up behind them.
    expect(store.laneOf(a), isNot(store.laneOf(b)));
    expect(store.laneOf(b), isNot(store.laneOf(c)));
    expect(store.laneOf(c), isNot(store.laneOf(d)));
    expect(store.laneOf(c), store.laneOf(a));
    expect(store.laneOf(d), store.laneOf(b));

    // The denser cluster keeps its own count, which is what the chain's
    // count is being separated from.
    expect(store.laneCountOf(x), 3);
    expect(store.laneCountOf(y), 3);
    expect(store.laneCountOf(z), 3);
    expect(<int>{
      store.laneOf(x),
      store.laneOf(y),
      store.laneOf(z),
    }, hasLength(3));

    // The TOLERANCE pin, and the only one: every other endpoint in this
    // file is an exact integer, where a tolerant comparison is
    // indistinguishable from a bare one (measured: stripping both
    // tolerance terms left every earlier assertion green). Here the first
    // item's end lands 1e-13 ABOVE the next item's start, inside
    // precisionErrorTolerance, so the overlap must read as a TOUCH: the
    // lane is reused and no second lane opens. A bare comparison reads it
    // as an overlap and doubles the lane count.
    final grazeA = _add(
      store,
      resolver,
      "grazeA",
      const BoardSpan(
        rowStart: 0,
        colStart: 1,
        rowSpan: 2,
        rowSpanFraction: 1e-13,
      ),
    );
    final grazeB = _add(
      store,
      resolver,
      "grazeB",
      const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 1),
    );
    resolver.ensureResolved();
    expect(store.laneOf(grazeB), store.laneOf(grazeA));
    expect(store.laneCountOf(grazeA), 1);
  });

  // AC6 lane assignment, the THIRD case. Written into this file rather than
  // un-skipped: the Testing Plan lists it among the cases Round 15 adds,
  // which are not among the stubs.
  // Asserts: the five the plan enumerates, each red against a different
  // implementation.
  // Falsification: named per assertion below.
  test("items spanning several primary tracks are laned once, not once per "
      "track", () {
    // The weekday time grid: UniformAxis rows (time), UniformAxis columns
    // carrying laneExtent. So the LANE axis is the columns, nothing is
    // content-sized, and the PRIMARY axis is the ROW axis. Items span N
    // rows each, which is exactly the shape a primary partition breaks.
    final store = BoardStore<String, String>();
    final resolver = OverlapLaneResolver(
      store: store,
      laneAxis: Axis.horizontal,
    );

    final a = _add(
      store,
      resolver,
      "a",
      const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 2),
    );
    final b = _add(
      store,
      resolver,
      "b",
      const BoardSpan(rowStart: 1, colStart: 0, rowSpan: 2),
    );
    final c = _add(
      store,
      resolver,
      "c",
      const BoardSpan(rowStart: 0, colStart: 1, rowSpan: 2),
    );
    final d = _add(
      store,
      resolver,
      "d",
      const BoardSpan(rowStart: 0, colStart: 2),
    );
    final e = _add(
      store,
      resolver,
      "e",
      const BoardSpan(rowStart: 1, colStart: 2),
    );

    // Setup sanity, and it can fail: A and B must each occupy TWO primary
    // (row) buckets, which is the configuration a primary partition
    // mis-resolves, and all five must be laned.
    expect(store.endTrackOf(a, Axis.vertical).ceil() - 1, 1);
    expect(store.startTrackOf(a, Axis.vertical).floor(), 0);
    expect(resolver.isLaned(a), isTrue);
    expect(resolver.isLaned(b), isTrue);
    expect(resolver.isLaned(c), isTrue);
    expect(resolver.isLaned(d), isTrue);
    expect(resolver.isLaned(e), isTrue);
    // One entry per laned item, in three lane-axis buckets.
    expect(resolver.bucketCount, 3);

    resolver.ensureResolved();

    // Red against the span-1 filter this plan carried before Round 15,
    // which excludes both A and B and leaves them stacked in lane 0.
    expect(store.laneOf(a), isNot(store.laneOf(b)));
    // Red against a per-PRIMARY-bucket resolve, which writes one answer per
    // bucket into one slot per item: with buckets visited ascending, B's
    // last write comes from row bucket 2, where it is alone, so it lands
    // lane 0 of 1 while A's half passes. Hence the conjunction.
    expect(store.laneCountOf(a), 2);
    expect(store.laneCountOf(b), 2);
    // Red against treating shared PRIMARY-bucket membership as conflict,
    // which puts C in a cluster with A and B though it is a whole day
    // column away.
    expect(store.laneOf(c), 0);
    expect(store.laneCountOf(c), 1);
    // Red against a STRICT overlap test at step 2: D ends exactly where E
    // starts, so a tolerance-free or closed-interval comparison reads a
    // touch as an overlap and gives them two lanes.
    expect(store.laneOf(d), 0);
    expect(store.laneOf(e), 0);
    expect(store.laneCountOf(d), 1);
    expect(store.laneCountOf(e), 1);

    final laneOfABefore = store.laneOf(a);
    final laneOfBBefore = store.laneOf(b);
    final laneCountOfABefore = store.laneCountOf(a);
    final laneCountOfBBefore = store.laneCountOf(b);

    // F spans ONE primary track and TWO lane-axis tracks, so a criterion
    // written on the primary axis (or on the content axis, which on this
    // board is neither) admits it, and an admitted F takes a lane in column
    // 0's sweep. This is the EXCLUSION arm, red under ANY bucket iteration
    // order.
    final f = _add(
      store,
      resolver,
      "f",
      const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
    );
    expect(resolver.isLaned(f), isFalse);
    resolver.ensureResolved();

    expect(store.laneOf(f), 0);
    expect(store.laneCountOf(f), 1);
    // And A and B keep the lanes they hold without F.
    expect(store.laneOf(a), laneOfABefore);
    expect(store.laneOf(b), laneOfBBefore);
    expect(store.laneCountOf(a), laneCountOfABefore);
    expect(store.laneCountOf(b), laneCountOfBBefore);
  });

  // DERIVED name. No AC; the lane-change accumulator, which Landing Order
  // step 2 names beside the dirty-bucket set and which nothing else at this
  // step reaches. The `affectedKeys` derivation that drains it lands at
  // step 4.
  // Asserts: the accumulator survives a flush, is drained rather than
  // cleared on flush, and names exactly the ids whose lane or lane count
  // moved.
  // Falsification: an implementation that cleared the accumulator on every
  // flush, as the dirty-bucket set is cleared, drains an empty set.
  test("the lane-change accumulator survives a flush and drains once", () {
    final store = BoardStore<String, String>();
    final resolver = OverlapLaneResolver(
      store: store,
      laneAxis: Axis.horizontal,
    );

    final a = _add(
      store,
      resolver,
      "a",
      const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 2),
    );
    final b = _add(
      store,
      resolver,
      "b",
      const BoardSpan(rowStart: 1, colStart: 0, rowSpan: 2),
    );
    resolver.ensureResolved();

    // Both moved off the allocation default of lane 0 of 1: B took lane 1
    // and both took lane count 2.
    expect(resolver.drainLaneChangedIds(), <int>{a, b});
    // Drained, so a second read reports nothing.
    expect(resolver.drainLaneChangedIds(), isEmpty);

    // A resolve that changes nothing names nobody, which is what stops a
    // structural notification naming every item on every layout.
    resolver.ensureResolved();
    expect(resolver.drainLaneChangedIds(), isEmpty);

    // The accumulator UNIONS across flushes and is emptied only by the
    // drain. This is the shape a batch has: two mutations with a lane READ
    // between them, each read flushing and clearing the DIRTY set, and one
    // drain at the end. An implementation that cleared the accumulator on
    // every flush, as the dirty set is cleared, reports only the second
    // mutation's keys.
    final p = _add(
      store,
      resolver,
      "p",
      const BoardSpan(rowStart: 0, colStart: 1, rowSpan: 2),
    );
    final q = _add(
      store,
      resolver,
      "q",
      const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 2),
    );
    resolver.ensureResolved();
    final r = _add(
      store,
      resolver,
      "r",
      const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 2),
    );
    final s = _add(
      store,
      resolver,
      "s",
      const BoardSpan(rowStart: 1, colStart: 2, rowSpan: 2),
    );
    resolver.ensureResolved();
    expect(resolver.drainLaneChangedIds(), <int>{p, q, r, s});

    // Removing A drops B back to lane 0 of 1, and the drain names BOTH: A,
    // whose values were reset by the de-registration, and B, the surviving
    // neighbour whose lane count fell. The neighbour is the half an
    // implementation that only reports the mutated item drops.
    resolver.deregisterItem(a);
    store.release("a");
    resolver.ensureResolved();
    final drained = resolver.drainLaneChangedIds();
    expect(drained, contains(b));
    expect(store.laneOf(b), 0);
    expect(store.laneCountOf(b), 1);
  });
}

int _add(
  BoardStore<String, String> store,
  OverlapLaneResolver resolver,
  String key,
  BoardSpan span,
) {
  final id = store.allocate(key);
  store.setData(id, key);
  store.setSpan(id, span);
  resolver.registerItem(id);
  return id;
}
