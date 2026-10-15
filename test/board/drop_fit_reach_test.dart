/// Tests for how far a `BoardDropFit` reaches: a refused move searches its
/// whole radius, placements flush against an item included, and a refused
/// resize under `clampResizes` stops its dragged edge at the item it ran
/// into.
///
/// The searches are pure functions over rectangles and axes, tested
/// directly as `drop_fit_test.dart` tests them; two cases drive a pumped
/// board through `BoardDragController` to show the drag reaches them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_drop_fit.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

bool _always(BoardSpan span) {
  return true;
}

class _Item {
  const _Item(this.key);

  final String key;
}

/// Whether [span] meets an item of [controller] other than [key],
/// half-open on both axes.
bool _meetsOther(
  BoardController<String, _Item> controller,
  String key,
  BoardSpan span,
) {
  for (final other in controller.itemsIn(
    span.rowStart,
    span.endTrackOn(Axis.vertical).ceil(),
    span.colStart,
    span.endTrackOn(Axis.horizontal).ceil(),
  )) {
    if (other == key) {
      continue;
    }
    final o = controller.spanOf(other)!;
    if (span.startTrackOn(Axis.vertical) < o.endTrackOn(Axis.vertical) &&
        o.startTrackOn(Axis.vertical) < span.endTrackOn(Axis.vertical) &&
        span.startTrackOn(Axis.horizontal) < o.endTrackOn(Axis.horizontal) &&
        o.startTrackOn(Axis.horizontal) < span.endTrackOn(Axis.horizontal)) {
      return true;
    }
  }
  return false;
}

Future<RenderBoardViewport<String>> _pump(
  WidgetTester tester,
  BoardController<String, _Item> controller, {
  required double width,
  required double height,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: height,
            child: Board<String, _Item>(
              controller: controller,
              cellBuilder: (context, cell) {
                return const SizedBox.expand();
              },
              itemBuilder: (context, item) {
                return const ColoredBox(color: Color(0xFF4CAF50));
              },
            ),
          ),
        ),
      ),
    ),
  );
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

void main() {
  BoardSpan? oneColumnFit(double rowRadius) {
    return BoardDropFitter.nearestFit(
      box: const BoardSpan(rowStart: 10, colStart: 0),
      policy: BoardDropFit(rowRadius: rowRadius, colRadius: 0.0),
      snap: const BoardSnap.track(),
      rowAxis: UniformAxis(24, 10.0),
      colAxis: UniformAxis(1, 10.0),
      rowWindow: (min: 0.0, max: 23.0),
      colWindow: (min: 0.0, max: 0.0),
      obstacles: const <BoardSpan>[
        BoardSpan(rowStart: 5, colStart: 0, rowSpan: 12),
      ],
      accepts: _always,
    );
  }

  // Rows 5 to 17 are taken around a one-row box at row 10. The free rows
  // nearest it are 4, six rows back, and 17, seven ahead: both further
  // than the four steps of one track the scan takes.
  test("a fit reaches past four steps to the nearest free placement", () {
    expect(oneColumnFit(10.0), const BoardSpan(rowStart: 4, colStart: 0));
  });

  test("the radius still bounds the reach", () {
    expect(oneColumnFit(5.0), isNull);
    expect(oneColumnFit(6.0), const BoardSpan(rowStart: 4, colStart: 0));
  });

  // Rows 0 to 30 are taken, so nothing before the box is free, and the
  // nearest free row is 30, twenty rows ahead.
  test("an infinite radius reaches every placement in the window", () {
    const policy = BoardDropFit(rowRadius: double.infinity, colRadius: 0.0);
    expect(
      BoardDropFitter.stepsOf(policy: policy, snap: const BoardSnap.track()),
      (rows: 4, cols: 0),
    );
    expect(
      BoardDropFitter.nearestFit(
        box: const BoardSpan(rowStart: 10, colStart: 0),
        policy: policy,
        snap: const BoardSnap.track(),
        rowAxis: UniformAxis(40, 10.0),
        colAxis: UniformAxis(1, 10.0),
        rowWindow: (min: 0.0, max: 39.0),
        colWindow: (min: 0.0, max: 0.0),
        obstacles: const <BoardSpan>[
          BoardSpan(rowStart: 0, colStart: 0, rowSpan: 30),
        ],
        accepts: _always,
      ),
      const BoardSpan(rowStart: 30, colStart: 0),
    );
  });

  test("an infinite radius's search region is the whole lattice", () {
    expect(
      BoardDropFitter.searchRangeOn(
        start: 10.0,
        end: 11.0,
        radius: double.infinity,
        window: (min: 0.0, max: 39.0),
        stepped: true,
        trackCount: 40,
      ),
      (start: 0, end: 40),
    );
    expect(
      BoardDropFitter.searchRangeOn(
        start: 10.0,
        end: 11.0,
        radius: double.infinity,
        window: (min: 0.0, max: 39.0),
        stepped: false,
        trackCount: 40,
      ),
      (start: 0, end: 40),
    );
  });

  // Rows 0 to 10 are taken across columns 0 to 20, and columns 0 to 10
  // across rows 0 to 20: a box at (5, 5) can leave neither by moving
  // along one axis inside the window, and the nearest free placement,
  // (10, 10), is flush with both.
  test("a fit across both axes lands flush on each", () {
    expect(
      BoardDropFitter.nearestFit(
        box: const BoardSpan(rowStart: 5, colStart: 5),
        policy: const BoardDropFit(
          rowRadius: double.infinity,
          colRadius: double.infinity,
        ),
        snap: const BoardSnap.track(),
        rowAxis: UniformAxis(20, 10.0),
        colAxis: UniformAxis(20, 10.0),
        rowWindow: (min: 0.0, max: 19.0),
        colWindow: (min: 0.0, max: 19.0),
        obstacles: const <BoardSpan>[
          BoardSpan(rowStart: 0, colStart: 0, rowSpan: 10, colSpan: 20),
          BoardSpan(rowStart: 0, colStart: 0, rowSpan: 20, colSpan: 10),
        ],
        accepts: _always,
      ),
      const BoardSpan(rowStart: 10, colStart: 10),
    );
  });

  // Quarter-track steps, and the box over columns 2 to 3 meets an item
  // over 1 to 3.6. The first start past the item on the box's grid is
  // 3.75: 3.5 would still meet it. The placement before it, at 0, is
  // further away.
  test("a flush placement rounds out onto the box's grid", () {
    expect(
      BoardDropFitter.nearestFit(
        box: const BoardSpan(rowStart: 0, colStart: 2),
        policy: const BoardDropFit(rowRadius: 0.0, colRadius: 2.0),
        snap: const BoardSnap.fraction(0.25),
        rowAxis: UniformAxis(1, 10.0),
        colAxis: UniformAxis(8, 10.0),
        rowWindow: (min: 0.0, max: 0.0),
        colWindow: (min: 0.0, max: 7.0),
        obstacles: const <BoardSpan>[
          BoardSpan(rowStart: 0, colStart: 1, colSpan: 2, colSpanFraction: 0.6),
        ],
        accepts: _always,
      ),
      const BoardSpan(rowStart: 0, colStart: 3, colFraction: 0.75),
    );
  });

  // Tenth-of-a-track steps. The item ends at 0.2 + 0.4, which in doubles
  // is a hair past six tenths, so the first free start, six steps on, is
  // a hair past six steps as well.
  test("a flush placement within rounding error of the grid is not pushed "
      "a step further", () {
    final answer = BoardDropFitter.nearestFit(
      box: const BoardSpan(
        rowStart: 0,
        colStart: 0,
        colSpan: 0,
        colSpanFraction: 0.5,
      ),
      policy: const BoardDropFit(rowRadius: 0.0, colRadius: 2.0),
      snap: const BoardSnap.fraction(0.1),
      rowAxis: UniformAxis(1, 10.0),
      colAxis: UniformAxis(4, 10.0),
      rowWindow: (min: 0.0, max: 0.0),
      colWindow: (min: 0.0, max: 3.5),
      obstacles: const <BoardSpan>[
        BoardSpan(
          rowStart: 0,
          colStart: 0,
          colFraction: 0.2,
          colSpan: 0,
          colSpanFraction: 0.4,
        ),
      ],
      accepts: _always,
    );
    expect(answer!.startTrackOn(Axis.horizontal), closeTo(0.6, 1e-9));
  });

  // A laned chip over the right half of column 1 moves by whole tracks on
  // its lane axis. An item over columns 0 to 7.2 leaves column 8 the
  // nearest track it fits in, seven tracks on, which counted from the
  // chip's own start rather than its track would land on 7 and meet it.
  test("a flush placement on the lane axis of a laned item is a whole "
      "track", () {
    expect(
      BoardDropFitter.nearestFit(
        box: const BoardSpan(
          rowStart: 0,
          colStart: 1,
          colFraction: 0.5,
          colSpan: 0,
          colSpanFraction: 0.5,
        ),
        policy: const BoardDropFit(rowRadius: 0.0, colRadius: double.infinity),
        snap: const BoardSnap.track(),
        rowAxis: UniformAxis(1, 10.0),
        colAxis: UniformAxis(12, 10.0),
        rowWindow: (min: 0.0, max: 0.0),
        colWindow: (min: 0.0, max: 11.0),
        obstacles: const <BoardSpan>[
          BoardSpan(rowStart: 0, colStart: 0, colSpan: 7, colSpanFraction: 0.2),
        ],
        accepts: _always,
        wholeTrackAxis: Axis.horizontal,
      ),
      const BoardSpan(
        rowStart: 0,
        colStart: 8,
        colSpan: 0,
        colSpanFraction: 0.5,
      ),
    );
  });

  // Rows 2 to 4, their bottom edge dragged to [refusedEnd].
  BoardSpan? rowEndResize(
    List<BoardSpan> obstacles, {
    int refusedEnd = 12,
    bool Function(BoardSpan candidate) accepts = _always,
  }) {
    return BoardDropFitter.clampedResize(
      lift: const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
      refused: BoardSpan(rowStart: 2, colStart: 1, rowSpan: refusedEnd - 2),
      kind: BoardDragKind.resizeRowEnd,
      snap: const BoardSnap.track(),
      obstacles: obstacles,
      accepts: accepts,
    );
  }

  // Dragged to 12, five rows past the item at row 7, so further from the
  // pointer than the four steps the search takes back from it.
  test("a resized edge dragged into an item stops at the item", () {
    expect(
      rowEndResize(const <BoardSpan>[BoardSpan(rowStart: 7, colStart: 1)]),
      const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 5),
    );
  });

  test("a resized edge stops at the first item in its way", () {
    expect(
      rowEndResize(const <BoardSpan>[
        BoardSpan(rowStart: 7, colStart: 1),
        BoardSpan(rowStart: 5, colStart: 1),
      ]),
      const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 3),
    );
  });

  // Rows 9 to 11, their top edge dragged to 0, past an item at row 5.
  test("a resized leading edge stops at the end of the item", () {
    expect(
      BoardDropFitter.clampedResize(
        lift: const BoardSpan(rowStart: 9, colStart: 1, rowSpan: 2),
        refused: const BoardSpan(rowStart: 0, colStart: 1, rowSpan: 11),
        kind: BoardDragKind.resizeRowStart,
        snap: const BoardSnap.track(),
        obstacles: const <BoardSpan>[BoardSpan(rowStart: 5, colStart: 1)],
        accepts: _always,
      ),
      const BoardSpan(rowStart: 6, colStart: 1, rowSpan: 5),
    );
  });

  test("a resized column edge stops at the item", () {
    expect(
      BoardDropFitter.clampedResize(
        lift: const BoardSpan(rowStart: 0, colStart: 1),
        refused: const BoardSpan(rowStart: 0, colStart: 1, colSpan: 7),
        kind: BoardDragKind.resizeColEnd,
        snap: const BoardSnap.track(),
        obstacles: const <BoardSpan>[BoardSpan(rowStart: 0, colStart: 3)],
        accepts: _always,
      ),
      const BoardSpan(rowStart: 0, colStart: 1, colSpan: 2),
    );
  });

  test("a resize refused without meeting an item is not clamped", () {
    expect(rowEndResize(const <BoardSpan>[]), isNull);
  });

  // The item over rows 3 to 6 already meets the lifted span, so it is not
  // what refused the drag; the item at row 8 is.
  test("an item the lifted span already meets is not in the edge's way", () {
    expect(
      rowEndResize(const <BoardSpan>[
        BoardSpan(rowStart: 3, colStart: 1, rowSpan: 3),
        BoardSpan(rowStart: 8, colStart: 1),
      ]),
      const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 6),
    );
  });

  // Dragged to 9: the stop at row 7 is refused, so the edge falls back to
  // 6, a step nearer the lifted edge.
  test("a stop the predicate refuses falls back toward the lifted edge", () {
    expect(
      rowEndResize(
        const <BoardSpan>[BoardSpan(rowStart: 7, colStart: 1)],
        refusedEnd: 9,
        accepts: (span) {
          return span.rowSpan != 5;
        },
      ),
      const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 4),
    );
  });

  // Quarter-track snap, and the item starts at 4.7: the edge stops on
  // the grid at 4.5, not at 4.75, which would meet it.
  test("a stop rounds back onto the snap's grid", () {
    expect(
      BoardDropFitter.clampedResize(
        lift: const BoardSpan(rowStart: 2, colStart: 1),
        refused: const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 4),
        kind: BoardDragKind.resizeRowEnd,
        snap: const BoardSnap.fraction(0.25),
        obstacles: const <BoardSpan>[
          BoardSpan(rowStart: 4, rowFraction: 0.7, colStart: 1),
        ],
        accepts: _always,
      ),
      const BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowSpan: 2,
        rowSpanFraction: 0.5,
      ),
    );
  });

  test("an edge already against an item stays where it was lifted", () {
    expect(
      BoardDropFitter.clampedResize(
        lift: const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
        refused: const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 3),
        kind: BoardDragKind.resizeRowEnd,
        snap: const BoardSnap.track(),
        obstacles: const <BoardSpan>[
          BoardSpan(rowStart: 4, colStart: 1, rowSpan: 2),
        ],
        accepts: _always,
      ),
      const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
    );
  });

  // Twelve 25px rows by three 40px columns. "m" at row 0 is dropped at
  // row 6 of column 1, inside a wall over rows 1 to 11: the nearest free
  // row there is 11, five rows on, where row 0 is six back.
  testWidgets("a refused move lands past four steps on a board", (
    tester,
  ) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(12, 25.0)),
      columns: BoardAxisConfig(axis: UniformAxis(3, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 0, colStart: 0),
    );
    controller.addItem(
      const _Item("wall"),
      const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 10),
    );
    final viewport = await _pump(
      tester,
      controller,
      width: 120.0,
      height: 300.0,
    );
    final moves = <BoardSpan>[];
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(
        onItemMoved: (key, span) {
          moves.add(span);
        },
        canDropAt: (key, span) {
          return !_meetsOther(controller, key, span);
        },
        dropFit: const BoardDropFit(
          minFreeFraction: 0.0,
          rowRadius: double.infinity,
          colRadius: 0.0,
        ),
      ),
    );
    addTearDown(drag.dispose);
    final origin = tester.getTopLeft(find.byType(Board<String, _Item>));
    final grab = viewport.rectOfItem("m")!.topLeft + const Offset(20.0, 6.0);
    drag.startDrag(
      key: "m",
      renderPort: viewport,
      pointerGlobal: origin + grab,
    );
    drag.updateDrag(origin + grab + const Offset(40.0, 6 * 25.0));
    await tester.pump();
    expect(
      drag.currentTarget!.span,
      const BoardSpan(rowStart: 11, colStart: 1),
    );
    drag.endDrag(cancel: false);
    await tester.pump();
    expect(moves, const <BoardSpan>[BoardSpan(rowStart: 11, colStart: 1)]);
  });

  // Six 50px rows by seven 40px columns. "m" over rows 2 to 4 of column
  // 1 has its bottom edge dragged to row 6, past "o" at row 5.
  Future<
    ({
      BoardDragController<String> drag,
      List<BoardSpan> resizes,
      List<BoardSpan> refusals,
    })
  >
  resizeIntoItem(WidgetTester tester, {required bool clampResizes}) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
    );
    controller.addItem(
      const _Item("o"),
      const BoardSpan(rowStart: 5, colStart: 1),
    );
    final viewport = await _pump(
      tester,
      controller,
      width: 280.0,
      height: 300.0,
    );
    final resizes = <BoardSpan>[];
    final refusals = <BoardSpan>[];
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(
        onItemMoved: (key, span) {},
        onItemResized: (key, span) {
          resizes.add(span);
        },
        primaryResizeEdges: BoardResizeEdges.trailing,
        canDropAt: (key, span) {
          if (_meetsOther(controller, key, span)) {
            refusals.add(span);
            return false;
          }
          return true;
        },
        dropFit: BoardDropFit(
          rowRadius: 0.0,
          colRadius: 0.0,
          clampResizes: clampResizes,
        ),
      ),
    );
    addTearDown(drag.dispose);
    final origin = tester.getTopLeft(find.byType(Board<String, _Item>));
    drag.startDrag(
      key: "m",
      renderPort: viewport,
      pointerGlobal: origin + const Offset(60.0, 195.0),
      edge: BoardResizeEdges.trailing,
      axis: Axis.vertical,
    );
    drag.updateDrag(origin + const Offset(60.0, 299.0));
    await tester.pump();
    return (drag: drag, resizes: resizes, refusals: refusals);
  }

  testWidgets("a refused resize stops at the item it ran into", (tester) async {
    final run = await resizeIntoItem(tester, clampResizes: true);
    // Setup sanity: the drag reached row 6, which the app refused.
    expect(
      run.refusals,
      contains(const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 4)),
    );
    expect(
      run.drag.currentTarget!.span,
      const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 3),
    );
    run.drag.endDrag(cancel: false);
    await tester.pump();
    expect(run.resizes, const <BoardSpan>[
      BoardSpan(rowStart: 2, colStart: 1, rowSpan: 3),
    ]);
  });

  testWidgets("a refused resize is still refused without clampResizes", (
    tester,
  ) async {
    final run = await resizeIntoItem(tester, clampResizes: false);
    expect(
      run.refusals,
      contains(const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 4)),
    );
    expect(run.drag.currentTarget, isNull);
    run.drag.endDrag(cancel: false);
    await tester.pump();
    expect(run.resizes, isEmpty);
  });
}
