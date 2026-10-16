/// The lane order: a comparator that orders the lanes of items whose
/// sweep-axis intervals are identical, after their start and end and
/// before the id. The resolver cases drive `OverlapLaneResolver` and
/// `BoardStore` directly, as `overlap_lanes_test.dart` does.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/_board_store.dart';
import 'package:widgets_extended/board/_overlap_lanes.dart';

/// Registers [key] at [span] with the payload [rank].
int _add(
  BoardStore<String, int> store,
  OverlapLaneResolver resolver,
  String key,
  int rank,
  BoardSpan span,
) {
  final id = store.allocate(key);
  store.setData(id, rank);
  store.setSpan(id, span);
  resolver.registerItem(id);
  return id;
}

/// The ids' order by their ranks, ascending.
int Function(int a, int b) _byRank(BoardStore<String, int> store) {
  return (a, b) {
    return store.dataOf(a)!.compareTo(store.dataOf(b)!);
  };
}

/// A resolver laning on the rows, so the sweep runs along the columns.
OverlapLaneResolver _rowLanes(BoardStore<String, int> store) {
  return OverlapLaneResolver(store: store, laneAxis: Axis.vertical);
}

/// Captures every [FlutterError.reportError] call for the test's length.
List<FlutterErrorDetails> _captureReports() {
  final reports = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reports.add;
  addTearDown(() {
    FlutterError.onError = previous;
  });
  return reports;
}

void main() {
  test("L4 the make-room dry run sorts with the order", () {
    final store = BoardStore<String, int>();
    final resolver = _rowLanes(store);
    final a = _add(
      store,
      resolver,
      "a",
      1,
      const BoardSpan(rowStart: 0, colStart: 0),
    );
    final b = _add(
      store,
      resolver,
      "b",
      2,
      const BoardSpan(rowStart: 0, colStart: 0),
    );
    final d = _add(
      store,
      resolver,
      "d",
      0,
      const BoardSpan(rowStart: 1, colStart: 0),
    );
    resolver.ensureResolved();

    Map<int, ({int lane, int laneCount, int laneSpan})> dryRun() {
      return resolver.resolveDryRun(
        draggedId: d,
        prospectiveLaneStart: 0.0,
        prospectiveLaneEnd: 1.0,
        prospectiveSweepStart: 0.0,
        prospectiveSweepEnd: 1.0,
      );
    }

    // Sanity: with no order the id breaks the tie, and d, allocated last,
    // takes the last lane.
    var lanes = dryRun();
    expect(lanes[a]!.lane, 0);
    expect(lanes[b]!.lane, 1);
    expect(lanes[d]!.lane, 2);

    resolver.idOrder = _byRank(store);
    lanes = dryRun();
    expect(lanes[d]!.lane, 0);
    expect(lanes[a]!.lane, 1);
    expect(lanes[b]!.lane, 2);
    expect(lanes[d]!.laneCount, 3);
  });

  test("L8 an order that throws mid-shift is reported and its bucket sorts "
      "by id", () {
    final store = BoardStore<String, int>();
    final resolver = _rowLanes(store);
    const cell = BoardSpan(rowStart: 0, colStart: 0);
    final ids = <int>[
      _add(store, resolver, "i0", 3, cell),
      _add(store, resolver, "i1", 2, cell),
      _add(store, resolver, "i2", 1, cell),
      _add(store, resolver, "i3", 0, cell),
    ];
    final byRank = _byRank(store);
    var calls = 0;
    // Answers by rank for its first two calls and throws on its third,
    // which `Sort._insertionSort` makes after shifting i0 up one place:
    // sorted in place, the bucket would then hold i0 twice and no i2.
    resolver.idOrder = (a, b) {
      calls++;
      if (calls == 3) {
        throw StateError("order failed");
      }
      return byRank(a, b);
    };
    final reports = _captureReports();

    resolver.ensureResolved();

    expect(calls, 3);
    expect(reports, hasLength(1));
    expect(reports.single.toString(), contains("BoardController.laneOrder"));
    expect(reports.single.exception, isA<StateError>());
    for (var i = 0; i < ids.length; i++) {
      expect(store.laneOf(ids[i]), i);
      expect(store.laneCountOf(ids[i]), 4);
    }
    final members = resolver.laneBucketMembers(0);
    expect(members, hasLength(4));
    expect(members.toSet(), ids.toSet());

    resolver.idOrder = null;
    resolver.invalidateAllBuckets();
    resolver.ensureResolved();
    expect(reports, hasLength(1));
    for (var i = 0; i < ids.length; i++) {
      expect(store.laneOf(ids[i]), i);
    }
  });

  test("L12 ordered resolves and dry runs reuse one backup buffer", () {
    final store = BoardStore<String, int>();
    final resolver = _rowLanes(store);
    resolver.idOrder = _byRank(store);
    const cell = BoardSpan(rowStart: 0, colStart: 0);
    final ids = <int>[
      for (var i = 0; i < 5; i++) _add(store, resolver, "m$i", 5 - i, cell),
    ];

    resolver.ensureResolved();
    // Sanity: the first ordered sort grows the buffer.
    expect(resolver.debugOrderBackupGrowCount, 1);
    expect(store.laneOf(ids.last), 0);

    for (var i = 0; i < 3; i++) {
      resolver.invalidateOrderOf(ids[i]);
      expect(resolver.hasDirtyBuckets, isTrue);
      resolver.ensureResolved();
    }
    for (var i = 0; i < 3; i++) {
      resolver.resolveDryRun(
        draggedId: ids[i],
        prospectiveLaneStart: 0.0,
        prospectiveLaneEnd: 1.0,
        prospectiveSweepStart: 1.0,
        prospectiveSweepEnd: 2.0,
      );
    }
    expect(resolver.debugOrderBackupGrowCount, 1);

    for (var i = 5; i < 9; i++) {
      _add(store, resolver, "m$i", 9 - i, cell);
    }
    resolver.ensureResolved();
    // Sanity: a sort past the buffer's length counts.
    expect(resolver.debugOrderBackupGrowCount, 2);
  });
}
