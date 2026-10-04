/// Tests for item 7F of the board audit fixes: a resize keeps its grab,
/// a second finger leaves a live drag alone, the autoscroller stops at
/// the extent, and a board change under a parked pointer is put to the
/// drop gate.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7F", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Every TARGET was red on the tree item 7E left, with every setup sanity
/// assertion before it passing.
library;

import 'package:flutter/gestures.dart';
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

const Key _frameKey = ValueKey<String>("board-frame");

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  int rows = 6,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(rows, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  // Registered after the dispose, so it runs before it: the board
  // unsubscribes when it unmounts.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  return controller;
}

Widget _board(
  BoardController<String, _Item> controller, {
  BoardDragConfig<String>? drag,
  bool reverseVertical = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: _frameKey,
          width: 280.0,
          height: 300.0,
          child: Board<String, _Item>(
            controller: controller,
            drag: drag,
            verticalDetails: ScrollableDetails.vertical(
              reverse: reverseVertical,
            ),
            cellBuilder: (context, cell) {
              return null;
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

BoardDragController<String> _drag(
  WidgetTester tester,
  BoardController<String, _Item> controller,
  BoardDragConfig<String> config,
) {
  final drag = BoardDragController<String>(
    boardController: controller,
    vsync: tester,
    config: config,
  );
  addTearDown(drag.dispose);
  return drag;
}

/// A board whose item "m" spans rows 2 and 3 of column 1 under [snap],
/// with the default trailing strip on the rows; returns the resize
/// reports.
Future<List<BoardSpan>> _resizeBoard(
  WidgetTester tester,
  BoardController<String, _Item> controller,
  BoardSnap snap,
) async {
  controller.addItem(
    const _Item("m"),
    const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
  );
  final resizes = <BoardSpan>[];
  await tester.pumpWidget(
    _board(
      controller,
      drag: BoardDragConfig<String>(
        snap: snap,
        onItemMoved: (key, span) {},
        onItemResized: (key, span) {
          resizes.add(span);
          controller.resizeItem(key, span);
        },
        primaryResizeEdges: BoardResizeEdges.trailing,
      ),
    ),
  );
  return resizes;
}

const BoardSpan _tall = BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2);

void main() {
  // Test 1 (A6).
  testWidgets("tapping a resize strip under a free snap keeps the span",
      (tester) async {
    final controller = _controller(tester);
    final resizes = await _resizeBoard(
      tester,
      controller,
      const BoardSnap.free(),
    );
    final rect = _viewport(tester).rectOfItem("m")!;
    expect(rect, const Rect.fromLTWH(40.0, 100.0, 40.0, 100.0));

    final gesture = await tester.startGesture(
      _global(tester, Offset(rect.center.dx, rect.bottom - 4.0)),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // Setup sanity: the tap reached the resize path.
    expect(resizes, isNotEmpty);
    // TARGET: a tap is not a resize.
    expect(resizes.last, _tall);
  });

  // Test 2 (A6).
  testWidgets("tapping a resize strip under a fine fraction snap keeps the "
      "span", (tester) async {
    final controller = _controller(tester);
    final resizes = await _resizeBoard(
      tester,
      controller,
      const BoardSnap.fraction(0.1),
    );
    final rect = _viewport(tester).rectOfItem("m")!;
    final gesture = await tester.startGesture(
      _global(tester, Offset(rect.center.dx, rect.bottom - 4.0)),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(resizes, isNotEmpty);
    // TARGET.
    expect(resizes.last, _tall);
  });

  // Test 3 (A6). Pressed 4 px inside the edge and moved down half a row:
  // the edge moves half a row, from where it was.
  testWidgets("a resize moves the edge by the pointer's displacement",
      (tester) async {
    final controller = _controller(tester);
    final resizes = await _resizeBoard(
      tester,
      controller,
      const BoardSnap.free(),
    );
    final rect = _viewport(tester).rectOfItem("m")!;
    final gesture = await tester.startGesture(
      _global(tester, Offset(rect.center.dx, rect.bottom - 4.0)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0.0, 25.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(resizes, isNotEmpty);
    final span = resizes.last;
    // TARGET: the start held, the end half a row further.
    expect(span.startTrackOn(Axis.vertical), 2.0);
    expect(span.endTrackOn(Axis.vertical), closeTo(4.5, 1e-9));
  });

  // Test 4 (A11).
  testWidgets("a second finger on the dragged item does not cancel the drag",
      (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    final moves = <BoardSpan>[];
    await tester.pumpWidget(
      _board(
        controller,
        drag: BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moves.add(span);
            controller.moveItem(key, span);
          },
        ),
      ),
    );
    final inPlace = _viewport(tester).rectOfItem("m")!;
    final first = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m")).first),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    await first.moveBy(const Offset(80.0, 0.0));
    await tester.pump();
    // Setup sanity: the session is live.
    expect(controller.isDragging("m"), isTrue);

    final second = await tester.startGesture(
      _global(tester, inPlace.center),
      pointer: 7,
    );
    await tester.pump();
    // TARGET: the first finger's drag goes on ...
    expect(controller.isDragging("m"), isTrue);
    await second.up();
    await first.up();
    await tester.pumpAndSettle();
    // ... and commits.
    expect(moves, hasLength(1));
  });

  // Test 5 (A12).
  testWidgets("the autoscroller stops ticking at the scroll extent",
      (tester) async {
    final controller = _controller(tester, rows: 10);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 1, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    final viewport = _viewport(tester);
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(onItemMoved: (key, span) {}),
    );
    final position = viewport.verticalPosition!;
    final rect = viewport.rectOfItem("m")!;
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, rect.center),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(60.0, 298.0)));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Setup sanity: the scroll reached the end.
    expect(position.pixels, position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    // TARGET: nothing is left to animate, so nothing asks for a frame.
    expect(tester.binding.hasScheduledFrame, isFalse);
    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
  });

  // Test 6 (A12). On a reversed vertical axis the content's end paints at
  // the TOP, so a finger in the top zone drives the offset toward its
  // maximum.
  testWidgets("the autoscroller stops at the extent of a reversed axis",
      (tester) async {
    final controller = _controller(tester, rows: 10);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 1, colStart: 1),
    );
    await tester.pumpWidget(_board(controller, reverseVertical: true));
    final viewport = _viewport(tester);
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(onItemMoved: (key, span) {}),
    );
    final position = viewport.verticalPosition!;
    final rect = viewport.rectOfItem("m")!;
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, rect.center),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(60.0, 2.0)));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Setup sanity: there is somewhere to scroll.
    expect(position.maxScrollExtent, greaterThan(0.0));
    // TARGET: the top zone drove the offset to its MAXIMUM, the content's
    // end on this axis; a direction read in paint space would not have
    // started at all.
    expect(position.pixels, position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    // TARGET.
    expect(tester.binding.hasScheduledFrame, isFalse);
    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
  });

  // Test 7 (A12). Stopped at the end, a move inside the same zone starts
  // nothing, and a move into the other zone scrolls back.
  testWidgets("a pointer move back into the other zone resumes the scroll",
      (tester) async {
    final controller = _controller(tester, rows: 10);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 1, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    final viewport = _viewport(tester);
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(onItemMoved: (key, span) {}),
    );
    final position = viewport.verticalPosition!;
    final rect = viewport.rectOfItem("m")!;
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, rect.center),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(60.0, 298.0)));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 16));

    drag.updateDrag(_global(tester, const Offset(61.0, 297.0)));
    // TARGET: at the end, a move that still points past it asks for no
    // frame.
    expect(tester.binding.hasScheduledFrame, isFalse);

    drag.updateDrag(_global(tester, const Offset(60.0, 2.0)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    // TARGET: the other zone scrolls back.
    expect(position.pixels, lessThan(position.maxScrollExtent));
    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
  });

  bool refuseOverlap(
    BoardController<String, _Item> controller,
    String key,
    BoardSpan span,
  ) {
    for (final other in controller.itemsIn(
      span.rowStart,
      span.rowStart + span.rowSpan,
      span.colStart,
      span.colStart + span.colSpan,
    )) {
      if (other != key) {
        return false;
      }
    }
    return true;
  }

  // Test 8 (A13).
  testWidgets("a placement freed under a parked pointer is accepted",
      (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    controller.addItem(
      const _Item("o"),
      const BoardSpan(rowStart: 2, colStart: 4),
    );
    await tester.pumpWidget(_board(controller));
    final viewport = _viewport(tester);
    final moves = <BoardSpan>[];
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        autoScrollEdgeZone: 0.0,
        canDropAt: (key, span) {
          return refuseOverlap(controller, key, span);
        },
        onItemMoved: (key, span) {
          moves.add(span);
        },
      ),
    );
    final rect = viewport.rectOfItem("m")!;
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, rect.center),
      ),
      isTrue,
    );
    // Over (2, 4), which o occupies.
    drag.updateDrag(_global(tester, const Offset(180.0, 125.0)));
    await tester.pump();
    // Setup sanity: refused while o is there.
    expect(drag.currentTarget, isNull);

    controller.removeItem("o");
    await tester.pump();
    // TARGET: the freed placement is the target without the pointer
    // moving ...
    expect(drag.currentTarget?.span, const BoardSpan(rowStart: 2, colStart: 4));
    // ... and a tremble inside the same cell keeps it for the release.
    drag.updateDrag(_global(tester, const Offset(181.0, 126.0)));
    await tester.pump();
    drag.endDrag(cancel: false);
    await tester.pumpAndSettle();
    expect(moves, <BoardSpan>[const BoardSpan(rowStart: 2, colStart: 4)]);
  });

  // Test 9 (A13), the other way.
  testWidgets("a placement occupied under a parked pointer is withdrawn",
      (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    final viewport = _viewport(tester);
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        autoScrollEdgeZone: 0.0,
        canDropAt: (key, span) {
          return refuseOverlap(controller, key, span);
        },
        onItemMoved: (key, span) {},
      ),
    );
    final rect = viewport.rectOfItem("m")!;
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, rect.center),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(180.0, 125.0)));
    await tester.pump();
    // Setup sanity: (2, 4) is free and accepted.
    expect(drag.currentTarget?.span, const BoardSpan(rowStart: 2, colStart: 4));

    controller.addItem(
      const _Item("o"),
      const BoardSpan(rowStart: 2, colStart: 4),
    );
    await tester.pump();
    // TARGET: withdrawn before any release. (What the release then does
    // is not asserted: `endDrag` re-validates a standing target against
    // the predicate, so it would commit nothing even with the target
    // left standing.)
    expect(drag.currentTarget, isNull);
    drag.endDrag(cancel: false);
    await tester.pumpAndSettle();
  });
}
