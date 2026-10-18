/// The lane order: a comparator that orders the lanes of items whose
/// sweep-axis intervals are identical, after their start and end and
/// before the id. The resolver cases drive `OverlapLaneResolver` and
/// `BoardStore` directly, as `overlap_lanes_test.dart` does; the others
/// drive a `BoardController` whose rows carry the lane extent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/_board_store.dart';
import 'package:widgets_extended/board/_overlap_lanes.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

/// A board item: its key and the rank the lane order compares.
@immutable
class _Ranked {
  const _Ranked(this.key, this.rank);

  final String key;
  final int rank;

  @override
  bool operator ==(Object other) {
    return other is _Ranked && other.key == key && other.rank == rank;
  }

  @override
  int get hashCode {
    return Object.hash(key, rank);
  }

  @override
  String toString() {
    return "_Ranked($key, $rank)";
  }
}

int _ascending(_Ranked a, _Ranked b) {
  return a.rank.compareTo(b.rank);
}

int _descending(_Ranked a, _Ranked b) {
  return b.rank.compareTo(a.rank);
}

const BoardAnimationSpec _ms200 = BoardAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// Three 100px rows carrying a 20px lane extent, the LANE axis, and seven
/// 50px columns, the sweep axis.
BoardController<String, _Ranked> _controller(
  WidgetTester tester, {
  Comparator<_Ranked>? laneOrder,
  BoardAnimationStyle animationStyle = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Ranked>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(3, 100.0), laneExtent: 20.0),
    columns: BoardAxisConfig(axis: UniformAxis(7, 50.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: animationStyle,
    laneOrder: laneOrder,
  );
  addTearDown(controller.dispose);
  return controller;
}

BoardSpan _cell(int row, int col) {
  return BoardSpan(rowStart: row, colStart: col);
}

/// L2's items: x rank 0 and y rank 1 in row 0, z rank 0 in row 1.
void _addXyz(BoardController<String, _Ranked> controller) {
  controller.addItem(const _Ranked("x", 0), _cell(0, 0));
  controller.addItem(const _Ranked("y", 1), _cell(0, 0));
  controller.addItem(const _Ranked("z", 0), _cell(1, 0));
}

/// The structural and item-data notifications [controller] fires, until
/// the test ends.
({List<Set<String>?> structural, List<String> data}) _listen(
  BoardController<String, _Ranked> controller,
) {
  final structural = <Set<String>?>[];
  final data = <String>[];
  void onStructural(Set<String>? keys) {
    structural.add(keys == null ? null : Set<String>.of(keys));
  }

  controller.addStructuralListener(onStructural);
  controller.addItemDataListener(data.add);
  addTearDown(() {
    controller.removeStructuralListener(onStructural);
    controller.removeItemDataListener(data.add);
  });
  return (structural: structural, data: data);
}

const Key _frameKey = ValueKey<String>("board-frame");

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

Widget _board(BoardController<String, _Ranked> controller) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: _frameKey,
          width: 350.0,
          height: 300.0,
          child: Board<String, _Ranked>(
            controller: controller,
            cellBuilder: (context, cell) {
              return const SizedBox.shrink();
            },
            itemBuilder: (context, item) {
              return ColoredBox(
                key: _itemKey(item.key),
                color: const Color(0xFF4CAF50),
              );
            },
          ),
        ),
      ),
    ),
  );
}

RenderBoardViewport<String> _viewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

double _paintedTop(WidgetTester tester, String key) {
  return tester.getRect(find.byKey(_itemKey(key))).top;
}

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
  testWidgets("L1 identical intervals take lanes in the lane order, the id "
      "breaking ties", (tester) async {
    void addAbcd(BoardController<String, _Ranked> controller) {
      controller.addItem(const _Ranked("a", 2), _cell(0, 0));
      controller.addItem(const _Ranked("b", 0), _cell(0, 0));
      controller.addItem(const _Ranked("c", 1), _cell(0, 0));
      controller.addItem(const _Ranked("d", 0), _cell(0, 0));
    }

    // Sanity: with no order the ids, in the order the keys were added,
    // decide the lanes.
    final unordered = _controller(tester);
    addAbcd(unordered);
    expect(
      <int?>[
        for (final key in <String>["a", "b", "c", "d"]) unordered.laneOf(key),
      ],
      <int>[0, 1, 2, 3],
    );

    final ordered = _controller(tester, laneOrder: _ascending);
    addAbcd(ordered);
    expect(ordered.laneOf("b"), 0);
    expect(ordered.laneOf("d"), 1);
    expect(ordered.laneOf("c"), 2);
    expect(ordered.laneOf("a"), 3);
    expect(ordered.laneCountOf("a"), 4);
  });

  testWidgets("L2 updateItem re-sorts the item's bucket and notifies by "
      "whether a lane moved", (tester) async {
    final controller = _controller(tester, laneOrder: _ascending);
    _addXyz(controller);
    expect(controller.laneOf("x"), 0);
    expect(controller.laneOf("y"), 1);
    final heard = _listen(controller);

    var resolves = controller.debugLaneBucketResolveCount;
    controller.updateItem("y", const _Ranked("y", -1));
    expect(controller.debugLaneBucketResolveCount, resolves + 1);
    expect(heard.structural, <Set<String>?>[
      <String>{"x", "y"},
    ]);
    expect(heard.data, isEmpty);
    expect(controller.laneOf("y"), 0);
    expect(controller.laneOf("x"), 1);

    heard.structural.clear();
    resolves = controller.debugLaneBucketResolveCount;
    controller.updateItem("y", const _Ranked("y", -2));
    expect(controller.debugLaneBucketResolveCount, resolves + 1);
    expect(heard.structural, isEmpty);
    expect(heard.data, <String>["y"]);
    expect(controller.laneOf("y"), 0);
    expect(controller.laneOf("x"), 1);
  });

  testWidgets("L3 setItems with a changed payload re-sorts that item's bucket "
      "and slides its lanes", (tester) async {
    final controller = _controller(
      tester,
      laneOrder: _ascending,
      animationStyle: const BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: _ms200,
      ),
    );
    _addXyz(controller);
    expect(controller.laneOf("x"), 0);
    final heard = _listen(controller);
    final resolves = controller.debugLaneBucketResolveCount;
    final slides = controller.debugSlideInstallCount;

    controller.setItems(<BoardPlacement<_Ranked>>[
      BoardPlacement<_Ranked>(const _Ranked("x", 2), _cell(0, 0)),
      BoardPlacement<_Ranked>(const _Ranked("y", 1), _cell(0, 0)),
      BoardPlacement<_Ranked>(const _Ranked("z", 0), _cell(1, 0)),
    ]);

    expect(controller.laneOf("x"), 1);
    expect(controller.laneOf("y"), 0);
    expect(controller.debugLaneBucketResolveCount, resolves + 1);
    expect(heard.structural, <Set<String>?>[
      <String>{"x", "y"},
    ]);
    expect(controller.debugSlideInstallCount, slides + 2);
    await tester.pumpAndSettle();
  });

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

  testWidgets("L5 a layout with no dirty lane bucket calls the order zero "
      "times", (tester) async {
    var calls = 0;
    final controller = _controller(
      tester,
      laneOrder: (a, b) {
        calls++;
        return _ascending(a, b);
      },
    );
    controller.addItem(const _Ranked("a", 2), _cell(0, 0));
    controller.addItem(const _Ranked("b", 0), _cell(0, 0));
    controller.addItem(const _Ranked("c", 1), _cell(0, 0));
    controller.addItem(const _Ranked("d", 0), _cell(0, 0));
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    // Sanity: the order ran for the bucket the adds dirtied.
    expect(calls, greaterThan(0));

    calls = 0;
    final viewport = _viewport(tester);
    final layouts = viewport.debugPerformLayoutCount;
    viewport.markNeedsLayout();
    await tester.pump();
    expect(viewport.debugPerformLayoutCount, layouts + 1);
    expect(calls, 0);

    controller.updateItem("a", const _Ranked("a", -1));
    await tester.pump();
    expect(calls, greaterThan(0));
    expect(controller.laneOf("a"), 0);
  });

  testWidgets("L6 with no order a payload change re-sorts no bucket", (
    tester,
  ) async {
    final controller = _controller(tester);
    _addXyz(controller);
    expect(controller.laneOf("x"), 0);
    expect(controller.laneOf("y"), 1);
    final heard = _listen(controller);
    final resolves = controller.debugLaneBucketResolveCount;

    controller.updateItem("y", const _Ranked("y", -1));
    expect(heard.data, <String>["y"]);
    expect(heard.structural, isEmpty);
    controller.setItems(<BoardPlacement<_Ranked>>[
      BoardPlacement<_Ranked>(const _Ranked("x", 5), _cell(0, 0)),
      BoardPlacement<_Ranked>(const _Ranked("y", -1), _cell(0, 0)),
      BoardPlacement<_Ranked>(const _Ranked("z", 0), _cell(1, 0)),
    ]);
    expect(heard.structural, <Set<String>?>[
      <String>{"x"},
    ]);
    expect(controller.debugLaneBucketResolveCount, resolves);
    expect(controller.laneOf("x"), 0);
    expect(controller.laneOf("y"), 1);
  });

  testWidgets("L7 replacing the order re-sorts every bucket once and "
      "notifies the moved keys", (tester) async {
    final controller = _controller(tester, laneOrder: _ascending);
    controller.addItem(const _Ranked("p", 0), _cell(0, 0));
    controller.addItem(const _Ranked("q", 1), _cell(0, 0));
    controller.addItem(const _Ranked("r", 2), _cell(1, 0));
    expect(controller.laneOf("p"), 0);
    expect(controller.laneOf("q"), 1);
    expect(controller.laneOf("r"), 0);
    final heard = _listen(controller);

    var resolves = controller.debugLaneBucketResolveCount;
    controller.laneOrder = _descending;
    expect(heard.structural, <Set<String>?>[
      <String>{"p", "q"},
    ]);
    expect(controller.debugLaneBucketResolveCount, resolves + 2);
    expect(controller.laneOf("q"), 0);
    expect(controller.laneOf("p"), 1);
    expect(controller.laneOf("r"), 0);

    heard.structural.clear();
    resolves = controller.debugLaneBucketResolveCount;
    int alsoDescending(_Ranked a, _Ranked b) {
      return _descending(a, b);
    }

    controller.laneOrder = alsoDescending;
    expect(heard.structural, <Set<String>?>[<String>{}]);
    expect(controller.debugLaneBucketResolveCount, resolves + 2);

    heard.structural.clear();
    resolves = controller.debugLaneBucketResolveCount;
    controller.laneOrder = controller.laneOrder;
    expect(heard.structural, isEmpty);
    expect(controller.debugLaneBucketResolveCount, resolves);

    final BoardController<String, Object?> wide = controller;
    expect(wide.hasLaneOrder, isTrue);
    expect(() {
      return wide.laneOrder;
    }, throwsA(isA<TypeError>()));

    controller.laneOrder = null;
    expect(controller.hasLaneOrder, isFalse);
    expect(controller.laneOf("p"), 0);
    expect(controller.laneOf("q"), 1);
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

  testWidgets("L9 inside runBatch an ordered updateItem notifies once at the "
      "exit, structurally when it re-lanes", (tester) async {
    final controller = _controller(tester, laneOrder: _ascending);
    _addXyz(controller);
    expect(controller.laneOf("y"), 1);
    final heard = _listen(controller);

    controller.runBatch(() {
      controller.updateItem("y", const _Ranked("y", -1));
      expect(heard.structural, isEmpty);
      expect(heard.data, isEmpty);
    });
    expect(heard.structural, <Set<String>?>[
      <String>{"x", "y"},
    ]);
    expect(heard.data, isEmpty);

    heard.structural.clear();
    controller.runBatch(() {
      controller.updateItem("y", const _Ranked("y", -2));
    });
    expect(heard.structural, isEmpty);
    expect(heard.data, <String>["y"]);
    expect(controller.laneOf("y"), 0);
  });

  testWidgets("L10 re-adding a key whose exit runs with a new payload "
      "re-sorts its bucket", (tester) async {
    final controller = _controller(
      tester,
      laneOrder: _ascending,
      animationStyle: const BoardAnimationStyle(
        trackResize: _ms200,
        itemSlide: _zero,
      ),
    );
    _addXyz(controller);
    await tester.pumpAndSettle();
    expect(controller.laneOf("x"), 0);
    expect(controller.laneOf("y"), 1);

    controller.removeItem("y");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Sanity: y's exit is running, so y holds its lane.
    expect(controller.itemOf("y"), isNull);
    expect(controller.laneOf("x"), 0);

    controller.addItem(const _Ranked("y", -1), _cell(0, 0));
    expect(controller.laneOf("y"), 0);
    expect(controller.laneOf("x"), 1);
    await tester.pumpAndSettle();
  });

  testWidgets("L11 replacing the order during a drag re-runs the make-room "
      "preview", (tester) async {
    final controller = _controller(
      tester,
      laneOrder: _ascending,
      animationStyle: const BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: _zero,
        makeRoom: _ms200,
      ),
    );
    controller.addItem(const _Ranked("a", 1), _cell(0, 0));
    controller.addItem(const _Ranked("g", 0), _cell(1, 0));
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final rest = _paintedTop(tester, "a");

    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(
        autoScrollEdgeZone: 0.0,
        onItemMoved: (key, span) {},
      ),
    );
    addTearDown(drag.dispose);
    final viewport = _viewport(tester);
    final lift = viewport.rectOfItem("g")!.center;
    expect(
      drag.startDrag(
        key: "g",
        renderPort: viewport,
        pointerGlobal: _global(tester, lift),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, Offset(lift.dx, 50.0)));
    await tester.pump();
    await tester.pumpAndSettle();
    // Sanity: g is previewed in row 0 above a, whose lane 1 of 2 starts
    // half a 100px row below its rest on the fixed lane axis.
    expect(drag.currentTarget!.span.rowStart, 0);
    expect(_paintedTop(tester, "a"), moreOrLessEquals(rest + 50.0));

    controller.laneOrder = _descending;
    // Sanity: the new order moves no committed lane.
    expect(controller.laneOf("a"), 0);
    expect(controller.laneOf("g"), 0);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_paintedTop(tester, "a"), moreOrLessEquals(rest));

    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
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
