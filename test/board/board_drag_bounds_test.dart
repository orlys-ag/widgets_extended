/// `BoardDragConfig.boundsOf`: a drag keeps an item inside the tracks its
/// bounds give, a move's start and a resize's dragged edge clamped into
/// them as into the lattice, on the corner axis, past a frozen band too,
/// and on the lane axis, a resize's even where the bounds lie out of
/// view, a drop fit nudging only inside them, on a moved axis and on a
/// kept one, measured from where the item shows held inside them; a
/// range that does not hold the item's span at the lift binds nothing,
/// the bounds are asked on every resolve, and a throw is reported and
/// binds nothing.
///
/// The lattice is a calendar's: a frozen 20 px header row, eight 40 px
/// slot rows and a 10 px row below them, over a frozen 40 px gutter and
/// three 100 px day columns carrying the lanes, all of it showing, so
/// nothing scrolls, but in a frame cut to 150 px, where the row below the
/// slots may be frozen too. Points are paint space in the board's frame.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

/// The slot rows, 1 to 8, and the first two day columns.
const ({int start, int end}) _slots = (start: 1, end: 9);
const ({int start, int end}) _twoDays = (start: 1, end: 3);

/// A block over rows 3 and 4 of the first day, from y 100 to 180 and x 40
/// to 140.
const BoardSpan _block = BoardSpan(rowStart: 3, rowSpan: 2, colStart: 1);

/// The board, its viewport, the frame's origin, and the moves and resizes
/// the drag reports.
class _Scene {
  _Scene(this.controller, this.viewport, this.origin, this.drag);

  final BoardController<String, _Item> controller;
  final RenderBoardViewport<String> viewport;
  final Offset origin;
  final BoardDragController<String> drag;
  final List<BoardSpan> moves = <BoardSpan>[];
  final List<BoardSpan> resizes = <BoardSpan>[];

  /// Lifts [key] with the pointer at [local], resizing its [edge] of the
  /// rows where one is given.
  void lift(
    String key,
    Offset local, {
    BoardResizeEdges edge = BoardResizeEdges.none,
  }) {
    final started = drag.startDrag(
      key: key,
      renderPort: viewport,
      pointerGlobal: origin + local,
      edge: edge,
      axis: edge == BoardResizeEdges.none ? null : Axis.vertical,
    );
    expect(started, isTrue, reason: "the drag of $key starts");
  }

  Future<void> moveTo(WidgetTester tester, Offset local) async {
    drag.updateDrag(origin + local);
    await tester.pump();
  }

  Future<void> drop(WidgetTester tester) async {
    drag.endDrag(cancel: false);
    await tester.pump();
  }

  /// The target's start or end on [axis].
  double? startOn(Axis axis) {
    return drag.currentTarget?.span.startTrackOn(axis);
  }

  double? endOn(Axis axis) {
    return drag.currentTarget?.span.endTrackOn(axis);
  }
}

Future<_Scene> _mount(
  WidgetTester tester, {
  required BoardDragBounds? Function(String key) boundsOf,
  Map<String, BoardSpan> items = const <String, BoardSpan>{"b": _block},
  bool refusesOverlaps = false,
  BoardDropFit? dropFit,
  double height = 350.0,
  int frozenEnd = 0,
}) async {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: ExplicitAxis(<double>[20.0, ...List<double>.filled(8, 40.0), 10.0]),
      frozenStart: 1,
      frozenEnd: frozenEnd,
    ),
    columns: BoardAxisConfig(
      axis: ExplicitAxis(const <double>[40.0, 100.0, 100.0, 100.0]),
      laneExtent: 100.0,
      frozenStart: 1,
    ),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  for (final MapEntry(:key, :value) in items.entries) {
    controller.addItem(_Item(key), value);
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 340.0,
            height: height,
            child: Board<String, _Item>(
              controller: controller,
              cellBuilder: (context, view) {
                return const SizedBox.shrink();
              },
              itemBuilder: (context, item) {
                return const ColoredBox(color: Color(0xFF7E57C2));
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final viewport = tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
  final origin = tester.getTopLeft(find.byType(Board<String, _Item>));
  late final _Scene scene;
  final drag = BoardDragController<String>(
    boardController: controller,
    vsync: tester,
    config: BoardDragConfig<String>(
      boundsOf: boundsOf,
      dropFit: dropFit,
      primaryResizeEdges: BoardResizeEdges.both,
      canDropAt: refusesOverlaps
          ? (key, span) {
              for (final other in controller.itemsIn(
                span.rowStart,
                span.endTrackOn(Axis.vertical).ceil(),
                span.colStart,
                span.endTrackOn(Axis.horizontal).ceil(),
              )) {
                if (other != key) {
                  return false;
                }
              }
              return true;
            }
          : null,
      onItemMoved: (key, span) {
        scene.moves.add(span);
      },
      onItemResized: (key, span) {
        scene.resizes.add(span);
      },
    ),
  );
  addTearDown(drag.dispose);
  scene = _Scene(controller, viewport, origin, drag);
  return scene;
}

void main() {
  testWidgets("a move dragged past its bounds stops at their last placement "
      "and their first, and the drop reports it", (tester) async {
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        return const BoardDragBounds(rows: _slots);
      },
    );
    // The block's top on y 300, row 8: the lattice's last placement for
    // two rows, past the slots by the row below them.
    scene.lift("b", const Offset(90.0, 140.0));
    await scene.moveTo(tester, const Offset(90.0, 340.0));
    expect(scene.startOn(Axis.vertical), 7.0, reason: "past the end");
    // The block's top on y 5, inside the header.
    await scene.moveTo(tester, const Offset(90.0, 45.0));
    expect(scene.startOn(Axis.vertical), 1.0, reason: "past the start");
    await scene.moveTo(tester, const Offset(90.0, 340.0));
    await scene.drop(tester);
    expect(scene.moves, <BoardSpan>[
      const BoardSpan(rowStart: 7, rowSpan: 2, colStart: 1),
    ]);
  });

  testWidgets("a move whose centre is over a frozen band its bounds leave "
      "out lands at their first placement that shows", (tester) async {
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        return const BoardDragBounds(rows: _slots);
      },
      items: const <String, BoardSpan>{
        "b": BoardSpan(rowStart: 3, colStart: 1),
      },
    );
    // A one-row block, whose centre over the header puts it on the
    // header's path, which holds a row.
    scene.lift("b", const Offset(90.0, 120.0));
    await scene.moveTo(tester, const Offset(90.0, 10.0));
    expect(scene.startOn(Axis.vertical), 1.0);
  });

  testWidgets("a resize dragged past its bounds stops its edge at them", (
    tester,
  ) async {
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        return const BoardDragBounds(rows: _slots);
      },
    );
    // Pressed 3 px inside the bottom edge, then into the row below the
    // slots, which takes the edge to the lattice's end, row 10.
    scene.lift("b", const Offset(90.0, 177.0), edge: BoardResizeEdges.trailing);
    await scene.moveTo(tester, const Offset(90.0, 345.0));
    expect(scene.endOn(Axis.vertical), 9.0, reason: "the end");
    await scene.drop(tester);
    expect(scene.resizes, <BoardSpan>[
      const BoardSpan(rowStart: 3, rowSpan: 6, colStart: 1),
    ]);
    // Pressed 3 px inside the top edge, then over the header, which
    // takes the edge to the lattice's start, row 0.
    scene.lift("b", const Offset(90.0, 103.0), edge: BoardResizeEdges.leading);
    await scene.moveTo(tester, const Offset(90.0, 5.0));
    expect(scene.startOn(Axis.vertical), 1.0, reason: "the start");
  });

  testWidgets("a resize whose bounds have scrolled under a frozen band "
      "still stops its edge at them", (tester) async {
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        return const BoardDragBounds(rows: (start: 1, end: 4));
      },
      items: const <String, BoardSpan>{
        "b": BoardSpan(rowStart: 2, colStart: 1),
      },
      height: 150.0,
    );
    // Pressed 3 px inside the bottom edge; then rows 1 to 5 scroll past,
    // under the header, which a span ending in them would not show past.
    scene.lift("b", const Offset(90.0, 97.0), edge: BoardResizeEdges.trailing);
    scene.viewport.verticalPosition!.jumpTo(200.0);
    await tester.pump();
    await scene.moveTo(tester, const Offset(90.0, 98.0));
    expect(scene.endOn(Axis.vertical), 4.0);
  });

  testWidgets("a resize whose bounds have scrolled under a trailing frozen "
      "band still stops its start at them", (tester) async {
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        return const BoardDragBounds(rows: (start: 5, end: 9));
      },
      items: const <String, BoardSpan>{
        "b": BoardSpan(rowStart: 7, colStart: 1),
      },
      height: 150.0,
      frozenEnd: 1,
    );
    // The row below the slots frozen at the bottom, and rows 6 to 8 in
    // view; pressed 3 px inside the block's top, which then scrolls back
    // to the top, where rows 5 to 8 lie under the frozen row and a span
    // starting in them would not show.
    scene.viewport.verticalPosition!.jumpTo(200.0);
    await tester.pump();
    scene.lift("b", const Offset(90.0, 63.0), edge: BoardResizeEdges.leading);
    scene.viewport.verticalPosition!.jumpTo(0.0);
    await tester.pump();
    await scene.moveTo(tester, const Offset(90.0, 62.0));
    expect(scene.startOn(Axis.vertical), 5.0);
  });

  testWidgets("a drop fit measures a move from where the item shows held "
      "inside its bounds", (tester) async {
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        return const BoardDragBounds(rows: _slots);
      },
      items: const <String, BoardSpan>{
        "b": BoardSpan(rowStart: 1, rowSpan: 4, colStart: 1),
        "last": BoardSpan(rowStart: 8, colStart: 1),
      },
      refusesOverlaps: true,
      dropFit: const BoardDropFit(
        minFreeFraction: 0.0,
        rowRadius: double.infinity,
        colRadius: 1.0,
      ),
    );
    // Far past the lattice's end: the block stops at rows 5 to 8, over
    // "last". Measured from rows 5 to 8, the free rows 4 to 7 of its day
    // lie 40 px away and the next day's rows 5 to 8 100 px; measured from
    // the lattice's end, where the item shows, the next day's are nearer.
    scene.lift("b", const Offset(90.0, 100.0));
    await scene.moveTo(tester, const Offset(90.0, 590.0));
    expect(scene.startOn(Axis.horizontal), 1.0, reason: "its own day");
    expect(scene.startOn(Axis.vertical), 4.0, reason: "the rows before");
  });

  testWidgets("a drop fit measures a move from where the item shows held "
      "inside its bounds on the lane axis too", (tester) async {
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        return const BoardDragBounds(cols: _twoDays);
      },
      items: const <String, BoardSpan>{
        "b": BoardSpan(rowStart: 4, colStart: 1),
        "wall": BoardSpan(rowStart: 2, rowSpan: 5, colStart: 2),
      },
      refusesOverlaps: true,
      dropFit: const BoardDropFit(
        minFreeFraction: 0.0,
        rowRadius: double.infinity,
        colRadius: 1.0,
      ),
    );
    // Over the third day: the block stops in the second, over "wall".
    // Measured from there, its own place lies 100 px away and the free
    // rows above and below "wall" 120 px; measured from the third day,
    // where the item shows, those rows are nearer.
    scene.lift("b", const Offset(90.0, 160.0));
    await scene.moveTo(tester, const Offset(330.0, 160.0));
    expect(scene.startOn(Axis.horizontal), 1.0, reason: "its own day");
    expect(scene.startOn(Axis.vertical), 4.0, reason: "its own row");
  });

  testWidgets("a move whose bounds show no start stays inside them", (
    tester,
  ) async {
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        return const BoardDragBounds(rows: (start: 1, end: 4));
      },
      items: const <String, BoardSpan>{
        "b": BoardSpan(rowStart: 2, colStart: 1),
      },
      height: 150.0,
    );
    scene.lift("b", const Offset(90.0, 80.0));
    // Rows 1 to 3 scrolled past, under the header: the slots from row 6
    // show.
    scene.viewport.verticalPosition!.jumpTo(200.0);
    await tester.pump();
    await scene.moveTo(tester, const Offset(90.0, 95.0));
    expect(scene.startOn(Axis.vertical), 3.0);
  });

  testWidgets("a move dragged past its bounds on the lane axis stops at "
      "their last track and their first, over a frozen band too", (
    tester,
  ) async {
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        return const BoardDragBounds(cols: _twoDays);
      },
    );
    scene.lift("b", const Offset(90.0, 140.0));
    // Over the third day.
    await scene.moveTo(tester, const Offset(330.0, 140.0));
    expect(scene.startOn(Axis.horizontal), 2.0, reason: "past the end");
    // Over the frozen gutter.
    await scene.moveTo(tester, const Offset(20.0, 140.0));
    expect(scene.startOn(Axis.horizontal), 1.0, reason: "past the start");
  });

  testWidgets("a range that does not hold the item's span at the lift "
      "binds nothing on its axis", (tester) async {
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        return const BoardDragBounds(rows: (start: 4, end: 9), cols: _twoDays);
      },
    );
    scene.lift("b", const Offset(90.0, 140.0));
    await scene.moveTo(tester, const Offset(330.0, 340.0));
    expect(scene.startOn(Axis.vertical), 8.0, reason: "the lattice's");
    expect(scene.startOn(Axis.horizontal), 2.0, reason: "the cols bound");
  });

  testWidgets("a drop fit nudges a refused move only inside the bounds", (
    tester,
  ) async {
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        return const BoardDragBounds(rows: _slots);
      },
      items: const <String, BoardSpan>{
        "b": BoardSpan(rowStart: 2, colStart: 1),
        "last": BoardSpan(rowStart: 8, colStart: 1),
      },
      refusesOverlaps: true,
      dropFit: const BoardDropFit(
        minFreeFraction: 0.0,
        rowRadius: double.infinity,
        colRadius: 0.0,
      ),
    );
    // The block's top on row 8 and a fifth, over "last", leaning toward
    // the free row below the slots rather than the free slot above it.
    scene.lift("b", const Offset(90.0, 80.0));
    await scene.moveTo(tester, const Offset(90.0, 328.0));
    expect(scene.startOn(Axis.vertical), 7.0);
  });

  testWidgets("a drop fit nudges a move its axis keeps only inside the "
      "bounds", (tester) async {
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        return const BoardDragBounds(rows: _slots);
      },
      items: const <String, BoardSpan>{
        "b": BoardSpan(rowStart: 8, colStart: 1),
        "other": BoardSpan(rowStart: 8, colStart: 2),
      },
      refusesOverlaps: true,
      dropFit: const BoardDropFit(
        minFreeFraction: 0.0,
        rowRadius: double.infinity,
        colRadius: 0.0,
      ),
    );
    // Onto "other" in the next day, a quarter row down: the rows keep the
    // stored start and lean toward the free row below the slots rather
    // than the free slot above.
    scene.lift("b", const Offset(90.0, 320.0));
    await scene.moveTo(tester, const Offset(190.0, 330.0));
    expect(scene.startOn(Axis.horizontal), 2.0, reason: "the next day");
    expect(scene.startOn(Axis.vertical), 7.0, reason: "the slot above");
  });

  testWidgets("the bounds are asked on every resolve", (tester) async {
    var bounds = const BoardDragBounds(rows: _slots);
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        return bounds;
      },
    );
    scene.lift("b", const Offset(90.0, 140.0));
    await scene.moveTo(tester, const Offset(90.0, 340.0));
    expect(scene.startOn(Axis.vertical), 7.0, reason: "the first bounds");
    bounds = const BoardDragBounds(rows: (start: 1, end: 8));
    await scene.moveTo(tester, const Offset(90.0, 341.0));
    expect(scene.startOn(Axis.vertical), 6.0, reason: "the new bounds");
  });

  testWidgets("bounds that throw are reported and bind nothing", (
    tester,
  ) async {
    final scene = await _mount(
      tester,
      boundsOf: (key) {
        throw StateError("bounds failed");
      },
    );
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    scene.lift("b", const Offset(90.0, 140.0));
    await scene.moveTo(tester, const Offset(90.0, 340.0));
    FlutterError.onError = previous;
    expect(scene.startOn(Axis.vertical), 8.0, reason: "the lattice's");
    expect(reports, isNotEmpty);
    expect(reports.first.exception, isA<StateError>());
  });
}
