/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 2 (L1 store). The Testing Plan writes these
/// cases in terms of `setItems`, `removeItem`, `runBatch` and `laneCountOf`,
/// which are `BoardController` members landing at step 4; at step 2 the only
/// L1 units that exist are `BoardStore`, `SpanIndex` and
/// `OverlapLaneResolver`, so each case drives those directly and the
/// comment on it names which controller call it stands in for.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/_board_store.dart';
import 'package:widgets_extended/board/_overlap_lanes.dart';
import 'package:widgets_extended/board/_span_index.dart';

void main() {
  // Performance plan T1 (plans/2026-09-07-board-performance-plan.md).
  // Asserts: once the rank list is built, one ordinalOf read costs one
  // probe whatever the id's rank.
  // Falsification: a linear rank search reports the rank plus one.
  test("ordinalOf on a bucket of 1000 items costs one probe", () {
    final store = BoardStore<String, String>();
    final index = SpanIndex(store: store, primaryAxis: Axis.vertical);
    final ids = _registerRow(store, index, 1000);
    // Setup sanity: the id at column 999 ranks last, so a linear search
    // would walk the whole list. This read also builds the rank list.
    expect(index.ordinalOf(ids[999]), 999);
    index.debugProbeCount = 0;
    index.ordinalOf(ids[999]);
    expect(index.debugProbeCount, 1);
  });

  // Performance plan T2.
  // Asserts: removing an id from a sorted bucket of 1000 costs at most
  // log2(1000) probes plus the one-element run walk plus slack.
  // Falsification: a linear removal reports about 500.
  test(
    "deregister from a sorted bucket of 1000 items stays inside the probe "
    "bound",
    () {
      final store = BoardStore<String, String>();
      final index = SpanIndex(store: store, primaryAxis: Axis.vertical);
      final ids = _registerRow(store, index, 1000);
      // Setup sanity: the bucket is sorted and holds the id.
      expect(index.itemsInRect(0, 1, 500, 501), <int>[ids[500]]);
      index.debugProbeCount = 0;
      index.deregister(ids[500]);
      expect(index.debugProbeCount, lessThanOrEqualTo(12));
      expect(index.itemsInRect(0, 1, 500, 501), isEmpty);
    },
    skip: "lands with the sorted removal, plan step 4",
  );

  // Performance plan T2b.
  // Asserts: a de-registration that lands between a bulk append and its
  // flush still removes the id.
  // Falsification: a removal that binary-searches the still-unsorted
  // bucket misses, and the id survives the flush.
  test("deregister during a bulk append removes the id", () {
    final store = BoardStore<String, String>();
    final index = SpanIndex(store: store, primaryAxis: Axis.vertical);
    final ids = <int>[];
    // Descending columns, so the appended order is the REVERSE of the
    // sorted order and a sorted search over it cannot land on the id.
    for (var i = 49; i >= 0; i--) {
      ids.add(
        _register(
          store,
          index,
          "b$i",
          BoardSpan(rowStart: 0, colStart: i, colSpan: 1),
          bulk: true,
        ),
      );
    }
    index.deregister(ids[7]);
    index.flushPendingSorts();
    final found = index.itemsInRect(0, 1, 0, 50);
    expect(found, isNot(contains(ids[7])));
    expect(found.length, 49);
  });

  // DERIVED name. No AC.
  // Asserts: an oracle fuzz against a linear scan over randomized add,
  // move, resize and remove scripts.
  // Falsification: not stated in the Testing Plan section for this case.
  test(
    "itemsInRect and itemsInRectIncludingExiting differ by exactly the exiting set under an oracle fuzz",
    () {
      final random = math.Random(20260830);
      final store = BoardStore<String, String>();
      final index = SpanIndex(store: store, primaryAxis: Axis.vertical);
      final live = <String>[];
      var nextKey = 0;
      // Setup sanity counters. Each is asserted non-zero at the end,
      // because a script that never produced an exiting item inside a
      // queried rect would make the difference assertion vacuous.
      var exitingInsideRectSeen = 0;
      var nonEmptyResultsSeen = 0;
      var duplicateBucketMembershipsSeen = 0;

      for (var step = 0; step < 400; step++) {
        final op = live.isEmpty ? 0 : random.nextInt(6);
        switch (op) {
          case 0:
            final key = "k${nextKey++}";
            _register(store, index, key, _randomSpan(random));
            live.add(key);
          case 1:
            // MOVE: new start, same extents.
            final key = live[random.nextInt(live.length)];
            final id = store.idOf(key);
            final old = store.spanOf(id);
            index.deregister(id);
            store.setSpan(
              id,
              old.copyWith(
                rowStart: random.nextInt(16),
                colStart: random.nextInt(16),
              ),
            );
            index.register(id);
          case 2:
            // RESIZE: same start, new extents.
            final key = live[random.nextInt(live.length)];
            final id = store.idOf(key);
            final old = store.spanOf(id);
            index.deregister(id);
            final resized = _randomSpan(random);
            store.setSpan(
              id,
              old.copyWith(
                rowSpan: resized.rowSpan,
                colSpan: resized.colSpan,
                rowSpanFraction: resized.rowSpanFraction,
                colSpanFraction: resized.colSpanFraction,
              ),
            );
            index.register(id);
          case 3:
            // REMOVE.
            final key = live.removeAt(random.nextInt(live.length));
            final id = store.idOf(key);
            index.deregister(id);
            store.release(key);
          default:
            // Toggle the exiting bit, which is the only thing the two query
            // forms differ on.
            final key = live[random.nextInt(live.length)];
            final id = store.idOf(key);
            store.setFlag(id, BoardStore.exitingBit, !store.isExiting(id));
        }

        for (var query = 0; query < 3; query++) {
          final rowStart = random.nextInt(18);
          final rowEnd = rowStart + 1 + random.nextInt(4);
          final colStart = random.nextInt(18);
          final colEnd = colStart + 1 + random.nextInt(4);

          final including = index.itemsInRectIncludingExiting(
            rowStart,
            rowEnd,
            colStart,
            colEnd,
            <int>[],
          );
          final excluding = index.itemsInRect(
            rowStart,
            rowEnd,
            colStart,
            colEnd,
          );
          final oracleAll = _oracle(
            store,
            rowStart,
            rowEnd,
            colStart,
            colEnd,
            includeExiting: true,
          );
          final oracleLive = _oracle(
            store,
            rowStart,
            rowEnd,
            colStart,
            colEnd,
            includeExiting: false,
          );

          expect(including.toSet(), oracleAll, reason: "step $step including");
          expect(excluding.toSet(), oracleLive, reason: "step $step excluding");
          // The seen-set: every id appears at most once even when its span
          // covers several primary-axis buckets in the queried range.
          expect(
            including.length,
            including.toSet().length,
            reason: "step $step duplicate id in the including form",
          );
          expect(
            excluding.length,
            excluding.toSet().length,
            reason: "step $step duplicate id in the excluding form",
          );
          // The two forms differ by EXACTLY the exiting members of the
          // rect, asserted on what the INDEX returned and not on the two
          // oracles, which would compare the oracle against itself.
          expect(
            including.toSet().difference(excluding.toSet()),
            oracleAll.where((id) {
              return store.isExiting(id);
            }).toSet(),
            reason: "step $step difference",
          );

          if (oracleAll.length > oracleLive.length) {
            exitingInsideRectSeen++;
          }
          if (oracleAll.isNotEmpty) {
            nonEmptyResultsSeen++;
          }
          for (final id in oracleAll) {
            final first = store.startTrackOf(id, Axis.vertical).floor();
            final last = store.endTrackOf(id, Axis.vertical).ceil() - 1;
            if (last > first && rowEnd - rowStart > 1) {
              duplicateBucketMembershipsSeen++;
            }
          }
        }
      }

      // Setup sanity, all three falsifiable: a script that never queried a
      // populated rect, never caught an exiting item inside one, or never
      // put a multi-bucket item inside a multi-track range would leave the
      // corresponding assertions above inert.
      expect(nonEmptyResultsSeen, greaterThan(0));
      expect(exitingInsideRectSeen, greaterThan(0));
      expect(duplicateBucketMembershipsSeen, greaterThan(0));
    },
  );

  // DERIVED name. No AC; the de-duplication half, which the fuzz's set
  // comparison cannot see.
  // Asserts: an item spanning three primary tracks, queried over a range
  // covering all three, appears exactly ONCE in the returned sequence,
  // asserted on a List and not on a Set.
  // Falsification: dropping the seen-set returns it three times.
  test("an item spanning three primary tracks appears exactly once in a "
      "range query", () {
    final store = BoardStore<String, String>();
    final index = SpanIndex(store: store, primaryAxis: Axis.vertical);

    final tall = _register(
      store,
      index,
      "tall",
      const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 3),
    );
    final short = _register(
      store,
      index,
      "short",
      const BoardSpan(rowStart: 3, colStart: 2),
    );

    // Setup sanity, and it can fail: the item must genuinely occupy three
    // buckets, or "appears once" would be true of a one-bucket item too.
    expect(store.endTrackOf(tall, Axis.vertical).ceil() - 1, 4);
    expect(store.startTrackOf(tall, Axis.vertical).floor(), 2);

    final result = index.itemsInRect(0, 10, 0, 5);
    expect(
      result.where((id) {
        return id == tall;
      }).length,
      1,
    );
    expect(result.length, 2);
    expect(result.toSet(), <int>{tall, short});

    // A span whose end lands an ulp ABOVE an integer boundary (endTrackOf
    // 3.0000000000000004). Both halves of the tolerance rule: the ulp is
    // not occupancy, so a range starting AT the boundary does not see the
    // item, while a range starting one track earlier does. The second
    // half is also the padded-break reproducer: an unpadded backward-walk
    // break computes fl(start + fl(end - start)), which can undershoot
    // the boundary and drop the item before its admit test.
    final grazing = _register(
      store,
      index,
      "grazing",
      const BoardSpan(
        rowStart: 0,
        colStart: 0,
        colFraction: 0.25864326010491845,
        colSpan: 2,
        colSpanFraction: 0.7413567398950821,
      ),
    );
    expect(index.itemsInRect(0, 1, 3, 6), isNot(contains(grazing)));
    expect(index.itemsInRect(0, 1, 2, 6), contains(grazing));
  });

  // DERIVED name. No AC; the bucket-scan bound, which no set comparison can
  // see.
  // Asserts: on a fixture of one bucket holding 1000 items with a
  // maxSpanAxisExtent of 2, a range query returning h items leaves
  // debugProbeCount below log2(1000) + h + s with s computed from the
  // fixture.
  // Falsification: a full linear scan leaves it at 1000.
  test("a range query over a bucket of 1000 items stays inside the probe "
      "bound", () {
    final fixture = _OneBucketFixture(itemCount: 1000, wideItemStart: 480);

    // Setup sanity, both falsifiable: one bucket, and an aggregate of 2.
    expect(fixture.index.bucketCount, 1);
    expect(fixture.index.maxSpanAxisExtentOf(0), closeTo(2.0, 1e-9));

    fixture.index.debugProbeCount = 0;
    final result = fixture.index.itemsInRect(0, 1, 500, 510);
    final probes = fixture.index.debugProbeCount;

    // h: the items the query returns. The ten unit items at columns 500 to
    // 509; column 499 ends exactly at 500 and a span is HALF-OPEN.
    const h = 10;
    expect(result.length, h);
    // s: the entries the backward walk touches WITHOUT returning them,
    // which are the ids whose start falls in
    // [rangeStart - maxSpanAxisExtent, rangeStart) = [498, 500).
    const s = 2;
    // The binary search costs ceil(log2(k + 1)) probes, the plan's
    // corrected form (the earlier ceil(log2(k)) is unsatisfiable at every
    // power-of-two k; the two coincide at k = 1000). The walk costs h + s
    // plus ONE terminator probe per bucket visited: the break is padded by
    // precisionErrorTolerance so a legal item whose end undershoots an
    // integer boundary by an ulp is admitted rather than dropped, and the
    // pad's price is probing the first entry that fails it. One bucket
    // here, so + 1. A full linear scan leaves this at 1000, so the bound
    // still discriminates by two orders of magnitude.
    final bound = (math.log(1000 + 1) / math.ln2).ceil() + h + s + 1;
    expect(bound, 23);
    expect(probes, lessThanOrEqualTo(bound));
    // And the answer is still right, which is what stops the bound being
    // met by returning nothing.
    expect(
      result.toSet(),
      _oracle(fixture.store, 0, 1, 500, 510, includeExiting: false),
    );
  });

  // DERIVED name. No AC; the BULK registration path.
  // Asserts: setItems of N items into one bucket leaves that bucket sorted
  // and its maxSpanAxisExtent correct, asserted by a query over it.
  // Falsification: N sorted inserts and one sort-on-exit are distinguished
  // by debugProbeCount measured across the setItems call rather than across
  // the query.
  //
  // Stands in for `BoardController.setItems`, which lands at step 4: the
  // BULK path is `register(bulk: true)` per placement plus one
  // `flushPendingSorts` at the call's exit, which is exactly what setItems
  // will drive.
  test("setItems leaves the bucket sorted with a correct maxSpanAxisExtent", () {
    const n = 200;
    final store = BoardStore<String, String>();
    final index = SpanIndex(store: store, primaryAxis: Axis.vertical);

    // Appended in DESCENDING start order, so an implementation that never
    // sorts leaves the bucket in exactly the order a binary search cannot
    // read.
    index.debugProbeCount = 0;
    for (var i = n - 1; i >= 0; i--) {
      _register(
        store,
        index,
        "k$i",
        BoardSpan(rowStart: 0, colStart: i, colSpan: i == 40 ? 3 : 1),
        bulk: true,
      );
    }
    index.flushPendingSorts();
    final bulkProbes = index.debugProbeCount;

    // The same N registrations down the SINGLE-mutation path, which is
    // what the bulk path exists to avoid: N sorted inserts into one bucket
    // is quadratic in the shifts.
    final sortedStore = BoardStore<String, String>();
    final sortedIndex = SpanIndex(
      store: sortedStore,
      primaryAxis: Axis.vertical,
    );
    sortedIndex.debugProbeCount = 0;
    for (var i = n - 1; i >= 0; i--) {
      _register(
        sortedStore,
        sortedIndex,
        "k$i",
        BoardSpan(rowStart: 0, colStart: i, colSpan: i == 40 ? 3 : 1),
      );
    }
    final sortedProbes = sortedIndex.debugProbeCount;

    expect(bulkProbes, lessThan(n));
    expect(sortedProbes, greaterThan(10 * n));

    // Sorted, asserted by a query over the bucket: the binary search is
    // what fails on an unsorted one.
    expect(
      index.itemsInRect(0, 1, 100, 110).toSet(),
      _oracle(store, 0, 1, 100, 110, includeExiting: false),
    );
    expect(
      index.itemsInRect(0, 1, 39, 42).toSet(),
      _oracle(store, 0, 1, 39, 42, includeExiting: false),
    );
    // And the aggregate is the truth, not the last raise.
    expect(index.maxSpanAxisExtentOf(0), closeTo(3.0, 1e-9));
  });

  // DERIVED name. No AC; the pending-sort set's INDEPENDENCE from the lane
  // dirty set, which the debugProbeCount assertion cannot see because both
  // implementations sort eventually.
  // Asserts: inside a runBatch that appends N registrations into one
  // bucket, read laneCountOf on a member (which flushes and CLEARS the lane
  // set) and then let the batch exit; a query afterwards returns the same
  // set as a linear oracle. A second arm throws from inside the runBatch
  // body, catches it, and asserts the same query still matches the oracle,
  // which is the finally half.
  // Falsification: an implementation that hung the pending sorts on the
  // lane set leaves the bucket unsorted with a stale maxSpanAxisExtent and
  // the binary search returns a strict subset.
  //
  // Stands in for `runBatch` and the `laneCountOf` read inside it, both of
  // which land at step 4: `resolver.ensureResolved()` IS what the read's
  // entry arm calls, and it is the call that clears the lane dirty set.
  test("the pending-sort set survives a laneCountOf read inside the batch", () {
    const n = 200;
    final store = BoardStore<String, String>();
    final index = SpanIndex(store: store, primaryAxis: Axis.vertical);
    // Columns carry the lane extent, so the lane axis is the columns and
    // the resolver has buckets of its own to dirty.
    final resolver = OverlapLaneResolver(
      store: store,
      laneAxis: Axis.horizontal,
    );

    for (var i = n - 1; i >= 0; i--) {
      final id = _register(
        store,
        index,
        "k$i",
        BoardSpan(rowStart: 0, colStart: i),
        bulk: true,
      );
      resolver.registerItem(id);
    }

    // The interleaved lane read, which is an ORDINARY event: it flushes and
    // CLEARS the lane dirty set in the middle of the batch.
    expect(resolver.hasDirtyBuckets, isTrue);
    resolver.ensureResolved();
    expect(resolver.hasDirtyBuckets, isFalse);

    // The batch exits and flushes its OWN pending sorts.
    index.flushPendingSorts();

    expect(
      index.itemsInRect(0, 1, 50, 60).toSet(),
      _oracle(store, 0, 1, 50, 60, includeExiting: false),
    );
    expect(index.itemsInRect(0, 1, 50, 60).length, 10);

    // Second arm: the body throws part way through. The bulk exit's flush
    // runs in a `finally`, and every query form flushes on ENTRY as well,
    // so a half-appended bucket is still queryable. NOTE: because of that
    // entry arm, the `finally` itself is not observable through a query;
    // what this arm pins is the entry arm, and an implementation without it
    // returns a strict subset here.
    final throwingStore = BoardStore<String, String>();
    final throwingIndex = SpanIndex(
      store: throwingStore,
      primaryAxis: Axis.vertical,
    );
    var threw = false;
    try {
      for (var i = n - 1; i >= 0; i--) {
        _register(
          throwingStore,
          throwingIndex,
          "k$i",
          BoardSpan(rowStart: 0, colStart: i),
          bulk: true,
        );
        if (i == 20) {
          throw StateError("mid-batch failure");
        }
      }
    } on StateError {
      threw = true;
    }
    expect(threw, isTrue);
    expect(
      throwingIndex.itemsInRect(0, 1, 50, 60).toSet(),
      _oracle(throwingStore, 0, 1, 50, 60, includeExiting: false),
    );
    expect(throwingIndex.itemsInRect(0, 1, 50, 60).length, 10);
  });

  // DERIVED name. No AC; the SHRINK direction, which the fixture above
  // cannot see because it only ever adds.
  // Asserts: register one item of span 40 into that bucket, query and
  // record debugProbeCount, then removeItem it, query the same range again
  // and assert the count is UNCHANGED (the accepted monotone-high value,
  // not a bug), and then setItems the bucket's survivors and assert the
  // count DROPS back to the log2(k) + h + s bound.
  // Falsification: an implementation that rescans on de-registration fails
  // the middle assertion and one that never recomputes on the bulk exit
  // fails the last.
  test("maxSpanAxisExtent shrinks only on the bulk exit", () {
    final fixture = _OneBucketFixture(itemCount: 1000, wideItemStart: 480);
    final store = fixture.store;
    final index = fixture.index;

    // One long item, spanning columns [460, 500), which raises the bucket's
    // aggregate from 2 to 40 in place.
    final longId = _register(
      store,
      index,
      "long",
      const BoardSpan(rowStart: 0, colStart: 460, colSpan: 40),
    );
    expect(index.maxSpanAxisExtentOf(0), closeTo(40.0, 1e-9));

    index.debugProbeCount = 0;
    final withLong = index.itemsInRect(0, 1, 500, 510);
    final probesWithLong = index.debugProbeCount;
    expect(withLong.length, 10);

    // DE-REGISTRATION accepts a monotone-HIGH aggregate and does NOT
    // rescan, so the walk still pays for a 40-wide item that has gone.
    index.deregister(longId);
    store.release("long");
    expect(index.maxSpanAxisExtentOf(0), closeTo(40.0, 1e-9));

    index.debugProbeCount = 0;
    final afterRemove = index.itemsInRect(0, 1, 500, 510);
    final probesAfterRemove = index.debugProbeCount;
    expect(afterRemove.length, 10);
    // Minus exactly ONE: the padded break probes THROUGH a boundary-
    // equality entry, and the removed item was one such entry, so its own
    // probe disappears with it while the STALE aggregate still drives the
    // walk over everything else. A deregistration that rescanned the
    // bucket would shrink the aggregate and land near the settled ~23.
    expect(probesAfterRemove, probesWithLong - 1);

    // The BULK path's exit is the ONE thing that ever lowers it. Standing
    // in for a `setItems` of the survivors, whose diff re-registers the one
    // placement whose span differs and marks that bucket pending.
    final movedId = store.idOf("c100");
    index.deregister(movedId);
    store.setSpan(movedId, const BoardSpan(rowStart: 0, colStart: 200));
    index.register(movedId, bulk: true);
    index.flushPendingSorts();
    expect(index.maxSpanAxisExtentOf(0), closeTo(2.0, 1e-9));

    index.debugProbeCount = 0;
    final afterBulk = index.itemsInRect(0, 1, 500, 510);
    final probesAfterBulk = index.debugProbeCount;
    expect(afterBulk.length, 10);
    // Corrected form plus the one padded-break terminator probe; see the
    // budget case above.
    final bound = (math.log(1000 + 1) / math.ln2).ceil() + 10 + 2 + 1;
    expect(probesAfterBulk, lessThanOrEqualTo(bound));
    expect(probesAfterBulk, lessThan(probesAfterRemove));
  });
}

/// One primary-axis bucket holding [itemCount] unit-wide items at columns
/// `0` to `itemCount - 1`, plus one two-wide item at [wideItemStart] so the
/// bucket's aggregate is 2.
class _OneBucketFixture {
  _OneBucketFixture({required this.itemCount, required this.wideItemStart}) {
    for (var i = 0; i < itemCount; i++) {
      _register(
        store,
        index,
        "c$i",
        BoardSpan(
          rowStart: 0,
          colStart: i,
          colSpan: i == wideItemStart ? 2 : 1,
        ),
        bulk: true,
      );
    }
    index.flushPendingSorts();
  }

  final int itemCount;
  final int wideItemStart;
  final BoardStore<String, String> store = BoardStore<String, String>();
  late final SpanIndex index = SpanIndex(
    store: store,
    primaryAxis: Axis.vertical,
  );
}

/// [count] single-cell items on row 0, one per column, appended in bulk
/// and flushed, so the row-0 bucket is sorted by column.
List<int> _registerRow(
  BoardStore<String, String> store,
  SpanIndex index,
  int count,
) {
  final ids = <int>[];
  for (var i = 0; i < count; i++) {
    ids.add(
      _register(
        store,
        index,
        "r$i",
        BoardSpan(rowStart: 0, colStart: i, colSpan: 1),
        bulk: true,
      ),
    );
  }
  index.flushPendingSorts();
  return ids;
}

int _register(
  BoardStore<String, String> store,
  SpanIndex index,
  String key,
  BoardSpan span, {
  bool bulk = false,
}) {
  final id = store.allocate(key);
  store.setData(id, key);
  store.setSpan(id, span);
  index.register(id, bulk: bulk);
  return id;
}

/// The linear scan the index is measured against: half-open intersection on
/// both axes, over every live id.
Set<int> _oracle(
  BoardStore<String, String> store,
  int rowStart,
  int rowEnd,
  int colStart,
  int colEnd, {
  required bool includeExiting,
}) {
  final result = <int>{};
  for (final id in store.ids) {
    if (!includeExiting && store.isExiting(id)) {
      continue;
    }
    if (store.startTrackOf(id, Axis.vertical) < rowEnd &&
        store.endTrackOf(id, Axis.vertical) > rowStart &&
        store.startTrackOf(id, Axis.horizontal) < colEnd &&
        store.endTrackOf(id, Axis.horizontal) > colStart) {
      result.add(id);
    }
  }
  return result;
}

BoardSpan _randomSpan(math.Random random) {
  // Non-dyadic members are load-bearing: dyadic-only fractions make
  // fl(start + fl(end - start)) exact, which is precisely the blind spot
  // that hid the unpadded walk-break drop (an item whose end undershoots
  // an integer boundary by an ulp). The audit found droppable spans only
  // among non-dyadic fractions.
  const fractions = <double>[0.0, 0.25, 0.5, 0.3, 0.7413567398950821];
  var rowSpan = random.nextInt(3);
  var rowSpanFraction = fractions[random.nextInt(fractions.length)];
  if (rowSpan == 0 && rowSpanFraction == 0.0) {
    rowSpanFraction = 0.5;
  }
  var colSpan = random.nextInt(3);
  var colSpanFraction = fractions[random.nextInt(fractions.length)];
  if (colSpan == 0 && colSpanFraction == 0.0) {
    colSpanFraction = 0.5;
  }
  return BoardSpan(
    rowStart: random.nextInt(16),
    colStart: random.nextInt(16),
    rowSpan: rowSpan,
    colSpan: colSpan,
    rowFraction: fractions[random.nextInt(fractions.length)],
    colFraction: fractions[random.nextInt(fractions.length)],
    rowSpanFraction: rowSpanFraction,
    colSpanFraction: colSpanFraction,
  );
}
