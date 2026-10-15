/// A drag resize's dragged edge is direct: under a live makeRoom family the
/// item paints, and its child is laid out, at the edge the drop would
/// commit on the frame after the pointer sample that resolved it. What the
/// edge causes, the item's re-lane among its neighbours, stays on the
/// makeRoom clock with theirs; a commit lands with no glide, and a cancel
/// or a refusal closes the preview on the clock.
///
/// Rects are paint space in the board's frame. Clock cadence: a case pumps
/// once with no duration after a sample (the install frame, where a
/// `Ticker`'s first tick reports zero elapsed), then pumps durations.
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

const Key _frameKey = ValueKey<String>("board-frame");

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// Every family that moves an item live, each on its own duration, so a
/// value read at a frame names the clock that produced it.
const BoardAnimationStyle _live = BoardAnimationStyle(
  trackResize: _zero,
  itemEnterExit: _zero,
  itemSlide: BoardAnimationSpec(
    duration: Duration(milliseconds: 200),
    curve: Curves.linear,
  ),
  makeRoom: BoardAnimationSpec(
    duration: Duration(milliseconds: 300),
    curve: Curves.linear,
  ),
  dropSettle: BoardAnimationSpec(
    duration: Duration(milliseconds: 100),
    curve: Curves.linear,
  ),
);

/// Six 50 px rows and seven 40 px columns, no lanes, unless [columns]
/// says otherwise.
BoardController<String, _Item> _controller(
  WidgetTester tester, {
  BoardAxisConfig? columns,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
    columns: columns ?? BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: _live,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Columns carrying a lane extent with no padding, a FIXED lane axis: a
/// column slices to 40 alone and 20 shared by two.
BoardController<String, _Item> _fixedLane(WidgetTester tester) {
  return _controller(
    tester,
    columns: BoardAxisConfig(
      axis: UniformAxis(7, 40.0),
      laneExtent: 18.0,
      lanePadding: 0.0,
    ),
  );
}

/// Mounts [controller] in a 280 by 300 frame and settles it.
Future<RenderBoardViewport<String>> _mount(
  WidgetTester tester,
  BoardController<String, _Item> controller,
) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: _frameKey,
            width: 280.0,
            height: 300.0,
            child: Board<String, _Item>(
              controller: controller,
              cellBuilder: (context, cell) {
                return const SizedBox(width: 40.0, height: 50.0);
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
    ),
  );
  await tester.pumpAndSettle();
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

/// The rect [key]'s child is laid out at and painted at, in the frame.
Rect _rectOf(WidgetTester tester, String key) {
  final frame = tester.getRect(find.byKey(_frameKey)).topLeft;
  return tester.getRect(find.byKey(_itemKey(key))).shift(-frame);
}

void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, moreOrLessEquals(expected.left, epsilon: 0.01));
  expect(actual.top, moreOrLessEquals(expected.top, epsilon: 0.01));
  expect(actual.right, moreOrLessEquals(expected.right, epsilon: 0.01));
  expect(actual.bottom, moreOrLessEquals(expected.bottom, epsilon: 0.01));
}

/// A drag controller with both resize edges on both axes, reporting a
/// resize through `resizeItem`.
BoardDragController<String> _drag(
  WidgetTester tester,
  BoardController<String, _Item> controller, {
  bool Function(String key, BoardSpan span)? canDropAt,
}) {
  final drag = BoardDragController<String>(
    boardController: controller,
    vsync: tester,
    config: BoardDragConfig<String>(
      onItemMoved: (key, span) {},
      onItemResized: (key, span) {
        controller.resizeItem(key, span);
      },
      canDropAt: canDropAt,
      resizeEdges: BoardResizeEdges.both,
      primaryResizeEdges: BoardResizeEdges.both,
      autoScrollEdgeZone: 0.0,
    ),
  );
  addTearDown(drag.dispose);
  return drag;
}

/// Lifts [key] by [edge] on [axis] at [lift], with no frame pumped.
void _lift(
  WidgetTester tester,
  BoardDragController<String> drag,
  RenderBoardViewport<String> viewport, {
  String key = "m",
  required BoardResizeEdges edge,
  required Axis axis,
  required Offset lift,
}) {
  expect(
    drag.startDrag(
      key: key,
      renderPort: viewport,
      pointerGlobal: _global(tester, lift),
      edge: edge,
      axis: axis,
    ),
    isTrue,
  );
}

/// Moves the pointer to [to] and pumps the install frame.
Future<void> _sample(
  WidgetTester tester,
  BoardDragController<String> drag,
  Offset to,
) async {
  drag.updateDrag(_global(tester, to));
  await tester.pump();
}

void main() {
  testWidgets(
    "a trailing-edge resize paints and lays out the committed extent on the "
    "next frame",
    (tester) async {
      // Rows: `m` on row 1 of column 1, its bottom strip dragged two rows
      // down.
      var controller = _controller(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 1, colStart: 1),
      );
      var viewport = await _mount(tester, controller);
      // Setup sanity: `m` rests on its cell.
      _expectRect(
        _rectOf(tester, "m"),
        const Rect.fromLTRB(40.0, 50.0, 80.0, 100.0),
      );
      var drag = _drag(tester, controller);
      _lift(
        tester,
        drag,
        viewport,
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
        lift: const Offset(60.0, 97.0),
      );
      await _sample(tester, drag, const Offset(60.0, 197.0));
      // Setup sanity: rows [1, 4) resolved, the model unwritten.
      expect(drag.currentTarget!.span.rowSpan, 3);
      expect(controller.spanOf("m")!.rowSpan, 1);
      // TARGET: the bottom edge is where the drop would put it.
      _expectRect(
        _rectOf(tester, "m"),
        const Rect.fromLTRB(40.0, 50.0, 80.0, 200.0),
      );
      drag.endDrag(cancel: true);
      await tester.pumpWidget(const SizedBox.shrink());

      // Columns: `m` in column 1 of row 1, its right strip dragged two
      // columns right.
      controller = _controller(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 1, colStart: 1),
      );
      viewport = await _mount(tester, controller);
      drag = _drag(tester, controller);
      _lift(
        tester,
        drag,
        viewport,
        edge: BoardResizeEdges.trailing,
        axis: Axis.horizontal,
        lift: const Offset(77.0, 75.0),
      );
      await _sample(tester, drag, const Offset(157.0, 75.0));
      // Setup sanity: columns [1, 4) resolved, the model unwritten.
      expect(drag.currentTarget!.span.colSpan, 3);
      expect(controller.spanOf("m")!.colSpan, 1);
      // TARGET: the right edge is where the drop would put it.
      _expectRect(
        _rectOf(tester, "m"),
        const Rect.fromLTRB(40.0, 50.0, 160.0, 100.0),
      );
      drag.endDrag(cancel: true);
    },
  );

  testWidgets("a leading-edge resize moves its lead and extent at once", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
    );
    final viewport = await _mount(tester, controller);
    final drag = _drag(tester, controller);
    _lift(
      tester,
      drag,
      viewport,
      edge: BoardResizeEdges.leading,
      axis: Axis.vertical,
      lift: const Offset(60.0, 103.0),
    );
    await _sample(tester, drag, const Offset(60.0, 53.0));
    // Setup sanity: rows [1, 4) resolved.
    expect(drag.currentTarget!.span.rowStart, 1);
    expect(drag.currentTarget!.span.rowSpan, 3);
    // TARGET: the top edge moved up a row and the bottom one held.
    _expectRect(
      _rectOf(tester, "m"),
      const Rect.fromLTRB(40.0, 50.0, 80.0, 200.0),
    );
    drag.endDrag(cancel: true);
  });

  testWidgets(
    "the item's re-lane stays on the clock in step with its neighbour",
    (tester) async {
      // `m` on rows [0, 2) and `n` on rows [3, 5), both alone in column
      // 2. Dragging `m`'s bottom edge to row 4 makes them share it: `m`
      // takes lane 0 and `n` lane 1, each 20 wide.
      final controller = _fixedLane(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 2),
      );
      controller.addItem(
        const _Item("n"),
        const BoardSpan(rowStart: 3, colStart: 2, rowSpan: 2),
      );
      final viewport = await _mount(tester, controller);
      // Setup sanity: each is alone in its column.
      _expectRect(
        _rectOf(tester, "m"),
        const Rect.fromLTRB(80.0, 0.0, 120.0, 100.0),
      );
      _expectRect(
        _rectOf(tester, "n"),
        const Rect.fromLTRB(80.0, 150.0, 120.0, 250.0),
      );
      final drag = _drag(tester, controller);
      _lift(
        tester,
        drag,
        viewport,
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
        lift: const Offset(100.0, 97.0),
      );
      await _sample(tester, drag, const Offset(100.0, 197.0));
      // Setup sanity: rows [0, 4) resolved.
      expect(drag.currentTarget!.span.rowSpan, 4);
      // TARGET: the dragged edge is at the target on the install frame,
      // while the width the shared column gives `m` has not started.
      _expectRect(
        _rectOf(tester, "m"),
        const Rect.fromLTRB(80.0, 0.0, 120.0, 200.0),
      );
      _expectRect(
        _rectOf(tester, "n"),
        const Rect.fromLTRB(80.0, 150.0, 120.0, 250.0),
      );
      await tester.pump(const Duration(milliseconds: 150));
      // TARGET: halfway through the makeRoom clock `m` has given up half
      // its 20 px and `n` has moved and shrunk by half of its 20 px.
      _expectRect(
        _rectOf(tester, "m"),
        const Rect.fromLTRB(80.0, 0.0, 110.0, 200.0),
      );
      _expectRect(
        _rectOf(tester, "n"),
        const Rect.fromLTRB(90.0, 150.0, 120.0, 250.0),
      );
      await tester.pump(const Duration(milliseconds: 150));
      _expectRect(
        _rectOf(tester, "m"),
        const Rect.fromLTRB(80.0, 0.0, 100.0, 200.0),
      );
      _expectRect(
        _rectOf(tester, "n"),
        const Rect.fromLTRB(100.0, 150.0, 120.0, 250.0),
      );
      drag.endDrag(cancel: true);
    },
  );

  testWidgets("a step of the dragged edge keeps the re-lane's clock", (
    tester,
  ) async {
    final controller = _fixedLane(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 2),
    );
    controller.addItem(
      const _Item("n"),
      const BoardSpan(rowStart: 3, colStart: 2, rowSpan: 2),
    );
    final viewport = await _mount(tester, controller);
    final drag = _drag(tester, controller);
    _lift(
      tester,
      drag,
      viewport,
      edge: BoardResizeEdges.trailing,
      axis: Axis.vertical,
      lift: const Offset(100.0, 97.0),
    );
    await _sample(tester, drag, const Offset(100.0, 197.0));
    await tester.pump(const Duration(milliseconds: 150));
    // Setup sanity: both are halfway through the re-lane.
    _expectRect(
      _rectOf(tester, "m"),
      const Rect.fromLTRB(80.0, 0.0, 110.0, 200.0),
    );
    _expectRect(
      _rectOf(tester, "n"),
      const Rect.fromLTRB(90.0, 150.0, 120.0, 250.0),
    );
    // One row further: rows [0, 5), the lanes unchanged.
    await _sample(tester, drag, const Offset(100.0, 247.0));
    expect(drag.currentTarget!.span.rowSpan, 5);
    // TARGET: the edge lands at once, and the width is where the clock
    // left it.
    _expectRect(
      _rectOf(tester, "m"),
      const Rect.fromLTRB(80.0, 0.0, 110.0, 250.0),
    );
    await tester.pump(const Duration(milliseconds: 75));
    // TARGET: three quarters through, `m` and `n` alike.
    _expectRect(
      _rectOf(tester, "m"),
      const Rect.fromLTRB(80.0, 0.0, 105.0, 250.0),
    );
    _expectRect(
      _rectOf(tester, "n"),
      const Rect.fromLTRB(95.0, 150.0, 120.0, 250.0),
    );
    drag.endDrag(cancel: true);
  });

  testWidgets("a step back to the stored edge lands at once", (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 1, colStart: 1),
    );
    final viewport = await _mount(tester, controller);
    final drag = _drag(tester, controller);
    _lift(
      tester,
      drag,
      viewport,
      edge: BoardResizeEdges.trailing,
      axis: Axis.vertical,
      lift: const Offset(60.0, 97.0),
    );
    await _sample(tester, drag, const Offset(60.0, 197.0));
    await tester.pump(const Duration(milliseconds: 300));
    // Setup sanity: the preview stands at rows [1, 4).
    _expectRect(
      _rectOf(tester, "m"),
      const Rect.fromLTRB(40.0, 50.0, 80.0, 200.0),
    );
    await _sample(tester, drag, const Offset(60.0, 97.0));
    // Setup sanity: the stored span resolved again.
    expect(drag.currentTarget!.span, controller.spanOf("m"));
    // TARGET: back on its cell at once.
    _expectRect(
      _rectOf(tester, "m"),
      const Rect.fromLTRB(40.0, 50.0, 80.0, 100.0),
    );
    drag.endDrag(cancel: true);
  });

  testWidgets(
    "a commit after a direct preview paints the committed rect with no glide",
    (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 1, colStart: 1),
      );
      final viewport = await _mount(tester, controller);
      final drag = _drag(tester, controller);
      _lift(
        tester,
        drag,
        viewport,
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
        lift: const Offset(60.0, 97.0),
      );
      await _sample(tester, drag, const Offset(60.0, 197.0));
      drag.endDrag(cancel: false);
      await tester.pump();
      // Setup sanity: the drop was written.
      expect(controller.spanOf("m")!.rowSpan, 3);
      // TARGET: the committed rect from the commit frame on.
      _expectRect(
        _rectOf(tester, "m"),
        const Rect.fromLTRB(40.0, 50.0, 80.0, 200.0),
      );
      await tester.pump(const Duration(milliseconds: 50));
      _expectRect(
        _rectOf(tester, "m"),
        const Rect.fromLTRB(40.0, 50.0, 80.0, 200.0),
      );
    },
  );

  testWidgets("a cancel or a refusal closes the direct edge on the clock", (
    tester,
  ) async {
    Future<void> run({required bool refuse}) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 1, colStart: 1),
      );
      final viewport = await _mount(tester, controller);
      // Spans of four rows or more are refused.
      final drag = _drag(
        tester,
        controller,
        canDropAt: (key, span) {
          return span.rowSpan < 4;
        },
      );
      _lift(
        tester,
        drag,
        viewport,
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
        lift: const Offset(60.0, 97.0),
      );
      await _sample(tester, drag, const Offset(60.0, 197.0));
      // Setup sanity: the preview stands at rows [1, 4).
      _expectRect(
        _rectOf(tester, "m"),
        const Rect.fromLTRB(40.0, 50.0, 80.0, 200.0),
      );
      if (refuse) {
        await _sample(tester, drag, const Offset(60.0, 247.0));
        // Setup sanity: rows [1, 5) were refused.
        expect(drag.currentTarget, isNull);
      } else {
        drag.endDrag(cancel: true);
        await tester.pump();
      }
      // TARGET: the close starts where the edge paints and runs on the
      // makeRoom clock.
      _expectRect(
        _rectOf(tester, "m"),
        const Rect.fromLTRB(40.0, 50.0, 80.0, 200.0),
      );
      await tester.pump(const Duration(milliseconds: 150));
      _expectRect(
        _rectOf(tester, "m"),
        const Rect.fromLTRB(40.0, 50.0, 80.0, 150.0),
      );
      await tester.pump(const Duration(milliseconds: 150));
      _expectRect(
        _rectOf(tester, "m"),
        const Rect.fromLTRB(40.0, 50.0, 80.0, 100.0),
      );
      if (refuse) {
        drag.endDrag(cancel: true);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }

    await run(refuse: false);
    await run(refuse: true);
  });
}
