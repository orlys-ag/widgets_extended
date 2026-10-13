/// A resize's target is independent of the track changes its own
/// make-room preview makes: a still pointer keeps its target while the
/// preview grows or shrinks a content-sized track, and a moving pointer
/// moves the dragged edge one way only, through every track boundary.
///
/// Points are paint space in the board's frame.
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

const Duration _frame = Duration(milliseconds: 16);

const BoardAnimationSpec _ms200 = BoardAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

/// Make-room on a 200 ms linear clock, which it inherits from itemSlide.
const BoardAnimationStyle _animated = BoardAnimationStyle(
  trackResize: _ms200,
  itemSlide: _ms200,
);

/// Content-sized rows carrying 18 px lanes under a 4 px padding, over
/// seven 40 px columns.
BoardController<String, _Item> _rowsLaned(
  WidgetTester tester, {
  int rowCount = 6,
  int frozenStart = 0,
  int frozenEnd = 0,
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(rowCount, 80.0),
      laneExtent: 18.0,
      lanePadding: 4.0,
      frozenStart: frozenStart,
      frozenEnd: frozenEnd,
    ),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// The horizontal mirror of [_rowsLaned]: content-sized columns carrying
/// the lanes, over seven 40 px rows.
BoardController<String, _Item> _columnsLaned(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    columns: BoardAxisConfig(
      axis: LazyContentAxis(6, 80.0),
      laneExtent: 18.0,
      lanePadding: 4.0,
    ),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Mounts [controller] in a [width] x [height] frame whose cells are
/// [cell], settles it, and unmounts before the controller's own teardown
/// disposes it.
Future<RenderBoardViewport<String>> _mount(
  WidgetTester tester,
  BoardController<String, _Item> controller, {
  double width = 280.0,
  double height = 300.0,
  Size cell = const Size(40.0, 10.0),
  ScrollableDetails verticalDetails = const ScrollableDetails.vertical(),
}) async {
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
            width: width,
            height: height,
            child: Board<String, _Item>(
              controller: controller,
              verticalDetails: verticalDetails,
              cellBuilder: (context, view) {
                return SizedBox(width: cell.width, height: cell.height);
              },
              itemBuilder: (context, item) {
                return ColoredBox(
                  key: ValueKey<String>("item-${item.key}"),
                  color: const Color(0xFF4CAF50),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(_frame);
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

/// A drag controller with the track snap unless [snap] says otherwise,
/// no autoscroll, both primary resize edges, and a resize report that
/// writes the span.
BoardDragController<String> _drag(
  WidgetTester tester,
  BoardController<String, _Item> controller, {
  BoardSnap snap = const BoardSnap.track(),
}) {
  final drag = BoardDragController<String>(
    boardController: controller,
    vsync: tester,
    config: BoardDragConfig<String>(
      snap: snap,
      autoScrollEdgeZone: 0.0,
      primaryResizeEdges: BoardResizeEdges.both,
      onItemMoved: (key, span) {},
      onItemResized: (key, span) {
        controller.resizeItem(key, span);
      },
    ),
  );
  addTearDown(drag.dispose);
  return drag;
}

/// Starts a resize of [key]'s [edge] on [axis], pressed at [local].
void _lift(
  WidgetTester tester,
  BoardDragController<String> drag,
  RenderBoardViewport<String> viewport, {
  required String key,
  required BoardResizeEdges edge,
  required Axis axis,
  required Offset local,
}) {
  expect(
    drag.startDrag(
      key: key,
      renderPort: viewport,
      pointerGlobal: _global(tester, local),
      edge: edge,
      axis: axis,
    ),
    isTrue,
  );
}

void _move(WidgetTester tester, BoardDragController<String> drag, Offset to) {
  drag.updateDrag(_global(tester, to));
}

double _rowExtent(RenderBoardViewport<String> viewport, int row) {
  return viewport.rectOfCell(row, 0)!.height;
}

double _columnExtent(RenderBoardViewport<String> viewport, int column) {
  return viewport.rectOfCell(0, column)!.width;
}

double _startRow(BoardDragController<String> drag) {
  return drag.currentTarget!.span.startTrackOn(Axis.vertical);
}

double _endRow(BoardDragController<String> drag) {
  return drag.currentTarget!.span.endTrackOn(Axis.vertical);
}

/// Criterion 1's items on [_rowsLaned]: `a` in row 1, so row 1 is 22 px,
/// and `d` on rows [0, 2), unlaned.
void _addJoinItems(BoardController<String, _Item> controller) {
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 1, colStart: 0, colSpan: 4),
  );
  controller.addItem(
    const _Item("d"),
    const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 2, colSpan: 5),
  );
}

/// Criterion 3's items on [_rowsLaned], in [row]: `a` and `d` laned
/// there, so the row is 40 px, `d` on lane 0.
void _addDelaneItems(BoardController<String, _Item> controller, {int row = 0}) {
  controller.addItem(
    const _Item("a"),
    BoardSpan(rowStart: row, colStart: 0, colSpan: 4),
  );
  controller.addItem(
    const _Item("d"),
    BoardSpan(rowStart: row, colStart: 0, colSpan: 5),
  );
}

/// The target a lift of `d`'s leading edge at (40, 9) moved to (40, 20)
/// resolves on criterion 1's board.
const BoardSpan _joinTarget = BoardSpan(rowStart: 1, colStart: 0, colSpan: 5);

/// The target a lift of `d`'s trailing edge at (40, 20) moved to (40, 50)
/// resolves on criterion 3's board.
const BoardSpan _delaneTarget = BoardSpan(
  rowStart: 0,
  colStart: 0,
  rowSpan: 3,
  colSpan: 5,
);

void main() {
  testWidgets("a resize that lanes an item keeps its target with motion off", (
    tester,
  ) async {
    final controller = _rowsLaned(tester);
    _addJoinItems(controller);
    final viewport = await _mount(tester, controller);
    expect(_rowExtent(viewport, 1), 22.0);
    final drag = _drag(tester, controller);
    _lift(
      tester,
      drag,
      viewport,
      key: "d",
      edge: BoardResizeEdges.leading,
      axis: Axis.vertical,
      local: const Offset(40.0, 9.0),
    );
    _move(tester, drag, const Offset(40.0, 20.0));
    expect(drag.currentTarget?.span, _joinTarget);
    for (var pump = 1; pump <= 20; pump++) {
      await tester.pump(_frame);
      expect(drag.currentTarget?.span, _joinTarget, reason: "pump $pump");
      expect(
        controller.anim.makeRoomSlotsOn(1).length,
        1,
        reason: "pump $pump",
      );
      expect(_rowExtent(viewport, 1), 40.0, reason: "pump $pump");
    }
    drag.endDrag(cancel: true);
  }, skip: true);

  testWidgets(
    "a resize that lanes an item keeps its target while its slot animates",
    (tester) async {
      final controller = _rowsLaned(tester, style: _animated);
      _addJoinItems(controller);
      final viewport = await _mount(tester, controller);
      final drag = _drag(tester, controller);
      _lift(
        tester,
        drag,
        viewport,
        key: "d",
        edge: BoardResizeEdges.leading,
        axis: Axis.vertical,
        local: const Offset(40.0, 9.0),
      );
      _move(tester, drag, const Offset(40.0, 20.0));
      expect(drag.currentTarget?.span, _joinTarget);
      var before = _rowExtent(viewport, 1);
      for (var pump = 1; pump <= 20; pump++) {
        await tester.pump(_frame);
        expect(drag.currentTarget?.span, _joinTarget, reason: "pump $pump");
        final extent = _rowExtent(viewport, 1);
        expect(extent, greaterThanOrEqualTo(before), reason: "pump $pump");
        before = extent;
      }
      expect(_rowExtent(viewport, 1), 40.0);
      drag.endDrag(cancel: true);
    },
    skip: true,
  );

  testWidgets(
    "a resize that de-lanes an item keeps its target with motion off",
    (tester) async {
      final controller = _rowsLaned(tester);
      _addDelaneItems(controller);
      final viewport = await _mount(tester, controller);
      expect(_rowExtent(viewport, 0), 40.0);
      expect(viewport.rectOfItem("d"), const Rect.fromLTRB(0, 4, 200, 22));
      final drag = _drag(tester, controller);
      _lift(
        tester,
        drag,
        viewport,
        key: "d",
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
        local: const Offset(40.0, 20.0),
      );
      _move(tester, drag, const Offset(40.0, 50.0));
      expect(drag.currentTarget?.span, _delaneTarget);
      for (var pump = 1; pump <= 20; pump++) {
        await tester.pump(_frame);
        expect(drag.currentTarget?.span, _delaneTarget, reason: "pump $pump");
      }
      drag.endDrag(cancel: true);
    },
    skip: true,
  );

  testWidgets(
    "a resize that de-lanes an item keeps its target while its vacate "
    "animates",
    (tester) async {
      final controller = _rowsLaned(tester, style: _animated);
      _addDelaneItems(controller);
      final viewport = await _mount(tester, controller);
      final drag = _drag(tester, controller);
      _lift(
        tester,
        drag,
        viewport,
        key: "d",
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
        local: const Offset(40.0, 20.0),
      );
      _move(tester, drag, const Offset(40.0, 50.0));
      expect(drag.currentTarget?.span, _delaneTarget);
      for (var pump = 1; pump <= 20; pump++) {
        await tester.pump(_frame);
        expect(drag.currentTarget?.span, _delaneTarget, reason: "pump $pump");
      }
      drag.endDrag(cancel: true);
    },
    skip: true,
  );

  testWidgets("a pointer moving down never moves the leading edge up", (
    tester,
  ) async {
    final controller = _rowsLaned(tester);
    _addJoinItems(controller);
    final viewport = await _mount(tester, controller);
    final drag = _drag(tester, controller);
    _lift(
      tester,
      drag,
      viewport,
      key: "d",
      edge: BoardResizeEdges.leading,
      axis: Axis.vertical,
      local: const Offset(40.0, 9.0),
    );
    double? before;
    for (var y = 10; y <= 45; y++) {
      _move(tester, drag, Offset(40.0, y.toDouble()));
      await tester.pump(_frame);
      expect(drag.currentTarget, isNotNull, reason: "y $y");
      final start = _startRow(drag);
      if (before != null) {
        expect(start, greaterThanOrEqualTo(before), reason: "y $y");
      }
      before = start;
    }
    drag.endDrag(cancel: true);
  }, skip: true);

  testWidgets("a pointer moving down reaches every row boundary", (
    tester,
  ) async {
    final controller = _rowsLaned(tester);
    _addDelaneItems(controller);
    final viewport = await _mount(tester, controller);
    final drag = _drag(tester, controller);
    _lift(
      tester,
      drag,
      viewport,
      key: "d",
      edge: BoardResizeEdges.trailing,
      axis: Axis.vertical,
      local: const Offset(40.0, 20.0),
    );
    final ends = <double>[];
    for (var y = 21; y <= 80; y++) {
      _move(tester, drag, Offset(40.0, y.toDouble()));
      await tester.pump(_frame);
      expect(drag.currentTarget, isNotNull, reason: "y $y");
      final end = _endRow(drag);
      if (ends.isNotEmpty) {
        expect(end, greaterThanOrEqualTo(ends.last), reason: "y $y");
      }
      ends.add(end);
    }
    for (var end = ends.first; end <= ends.last; end += 1.0) {
      expect(ends, contains(end), reason: "the end row $end");
    }
    drag.endDrag(cancel: true);
  }, skip: true);

  testWidgets(
    "the horizontal mirror of a resize that lanes an item keeps its target",
    (tester) async {
      final controller = _columnsLaned(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 1, rowSpan: 4),
      );
      controller.addItem(
        const _Item("d"),
        const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 5, colSpan: 2),
      );
      final viewport = await _mount(
        tester,
        controller,
        width: 300.0,
        height: 280.0,
        cell: const Size(10.0, 40.0),
      );
      const target = BoardSpan(rowStart: 0, colStart: 1, rowSpan: 5);
      final drag = _drag(tester, controller);
      _lift(
        tester,
        drag,
        viewport,
        key: "d",
        edge: BoardResizeEdges.leading,
        axis: Axis.horizontal,
        local: const Offset(9.0, 40.0),
      );
      _move(tester, drag, const Offset(20.0, 40.0));
      expect(drag.currentTarget?.span, target);
      for (var pump = 1; pump <= 20; pump++) {
        await tester.pump(_frame);
        expect(drag.currentTarget?.span, target, reason: "pump $pump");
        expect(
          controller.anim.makeRoomSlotsOn(1).length,
          1,
          reason: "pump $pump",
        );
        expect(_columnExtent(viewport, 1), 40.0, reason: "pump $pump");
      }
      drag.endDrag(cancel: true);
    },
    skip: true,
  );

  testWidgets(
    "the horizontal mirror of a resize that de-lanes an item keeps its "
    "target",
    (tester) async {
      final controller = _columnsLaned(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 4),
      );
      controller.addItem(
        const _Item("d"),
        const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 5),
      );
      final viewport = await _mount(
        tester,
        controller,
        width: 300.0,
        height: 280.0,
        cell: const Size(10.0, 40.0),
      );
      expect(viewport.rectOfItem("d"), const Rect.fromLTRB(4, 0, 22, 200));
      const target = BoardSpan(
        rowStart: 0,
        colStart: 0,
        rowSpan: 5,
        colSpan: 3,
      );
      final drag = _drag(tester, controller);
      _lift(
        tester,
        drag,
        viewport,
        key: "d",
        edge: BoardResizeEdges.trailing,
        axis: Axis.horizontal,
        local: const Offset(20.0, 40.0),
      );
      _move(tester, drag, const Offset(50.0, 40.0));
      expect(drag.currentTarget?.span, target);
      for (var pump = 1; pump <= 20; pump++) {
        await tester.pump(_frame);
        expect(drag.currentTarget?.span, target, reason: "pump $pump");
      }
      drag.endDrag(cancel: true);
    },
    skip: true,
  );

  testWidgets(
    "a resize from a scrolled frozen band keeps its target and reads the "
    "band where its own-free extent paints",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 40, frozenStart: 1);
      _addDelaneItems(controller);
      final viewport = await _mount(tester, controller);
      viewport.verticalPosition!.jumpTo(100.0);
      await tester.pump();
      expect(viewport.rectOfCell(0, 0), const Rect.fromLTRB(0, 0, 40, 40));
      expect(viewport.rectOfCell(11, 0)!.top, 40.0);
      final drag = _drag(tester, controller);
      _lift(
        tester,
        drag,
        viewport,
        key: "d",
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
        local: const Offset(40.0, 20.0),
      );
      const deep = BoardSpan(rowStart: 0, colStart: 0, rowSpan: 14, colSpan: 5);
      _move(tester, drag, const Offset(40.0, 62.0));
      expect(drag.currentTarget?.span, deep);
      for (var pump = 1; pump <= 4; pump++) {
        await tester.pump(_frame);
        expect(drag.currentTarget?.span, deep, reason: "pump $pump");
      }
      const stored = BoardSpan(rowStart: 0, colStart: 0, colSpan: 5);
      _move(tester, drag, const Offset(40.0, 32.0));
      expect(drag.currentTarget?.span, stored);
      for (var pump = 1; pump <= 4; pump++) {
        await tester.pump(_frame);
        expect(drag.currentTarget?.span, stored, reason: "pump $pump");
      }
      drag.endDrag(cancel: true);
    },
    skip: true,
  );

  testWidgets("a resize under a reversed axis keeps its target", (
    tester,
  ) async {
    final controller = _rowsLaned(tester);
    _addJoinItems(controller);
    final viewport = await _mount(
      tester,
      controller,
      verticalDetails: const ScrollableDetails(direction: AxisDirection.up),
    );
    final drag = _drag(tester, controller);
    _lift(
      tester,
      drag,
      viewport,
      key: "d",
      edge: BoardResizeEdges.leading,
      axis: Axis.vertical,
      local: const Offset(40.0, 291.0),
    );
    _move(tester, drag, const Offset(40.0, 280.0));
    for (var pump = 1; pump <= 8; pump++) {
      await tester.pump(_frame);
      expect(drag.currentTarget?.span, _joinTarget, reason: "pump $pump");
      expect(_rowExtent(viewport, 1), 40.0, reason: "pump $pump");
    }
    drag.endDrag(cancel: true);
  }, skip: true);

  testWidgets("a free-snap resize keeps its target while its vacate animates", (
    tester,
  ) async {
    final controller = _rowsLaned(tester, style: _animated);
    _addDelaneItems(controller);
    final viewport = await _mount(tester, controller);
    final drag = _drag(tester, controller, snap: const BoardSnap.free());
    _lift(
      tester,
      drag,
      viewport,
      key: "d",
      edge: BoardResizeEdges.trailing,
      axis: Axis.vertical,
      local: const Offset(40.0, 20.0),
    );
    _move(tester, drag, const Offset(40.0, 50.0));
    expect(_endRow(drag), moreOrLessEquals(2.5, epsilon: 1e-9));
    for (var pump = 1; pump <= 20; pump++) {
      await tester.pump(_frame);
      expect(
        _endRow(drag),
        moreOrLessEquals(2.5, epsilon: 1e-9),
        reason: "pump $pump",
      );
    }
    drag.endDrag(cancel: true);
  }, skip: true);

  testWidgets(
    "a resize whose vacate clamps the scroll offset keeps its target",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 40);
      _addDelaneItems(controller, row: 39);
      final viewport = await _mount(tester, controller);
      final position = viewport.verticalPosition!;
      position.jumpTo(130.0);
      await tester.pump();
      expect(position.maxScrollExtent, 130.0);
      expect(viewport.rectOfItem("d"), const Rect.fromLTRB(0, 264, 200, 282));
      final drag = _drag(tester, controller);
      _lift(
        tester,
        drag,
        viewport,
        key: "d",
        edge: BoardResizeEdges.leading,
        axis: Axis.vertical,
        local: const Offset(40.0, 266.0),
      );
      const target = BoardSpan(
        rowStart: 36,
        colStart: 0,
        rowSpan: 4,
        colSpan: 5,
      );
      _move(tester, drag, const Offset(40.0, 236.0));
      expect(drag.currentTarget?.span, target);
      for (var pump = 1; pump <= 6; pump++) {
        await tester.pump(_frame);
        if (pump == 1) {
          expect(position.pixels, 112.0);
        }
        expect(drag.currentTarget?.span, target, reason: "pump $pump");
      }
      drag.endDrag(cancel: true);
    },
    skip: true,
  );

  testWidgets(
    "a resize whose vacate leaves an overscroll keeps its target through "
    "the spring-back",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 40);
      _addDelaneItems(controller, row: 39);
      final viewport = await _mount(tester, controller);
      final position = viewport.verticalPosition!;
      position.jumpTo(129.0);
      await tester.pump();
      expect(viewport.rectOfItem("d"), const Rect.fromLTRB(0, 265, 200, 283));
      final drag = _drag(tester, controller);
      _lift(
        tester,
        drag,
        viewport,
        key: "d",
        edge: BoardResizeEdges.leading,
        axis: Axis.vertical,
        local: const Offset(40.0, 266.0),
      );
      const target = BoardSpan(
        rowStart: 36,
        colStart: 0,
        rowSpan: 4,
        colSpan: 5,
      );
      position.jumpTo(130.0);
      _move(tester, drag, const Offset(40.0, 236.0));
      expect(drag.currentTarget?.span, target);
      await tester.pump(_frame);
      expect(position.pixels, greaterThan(112.0));
      expect(drag.currentTarget?.span, target, reason: "pump 1");
      var pumps = 1;
      while (position.pixels > 112.0 && pumps < 60) {
        await tester.pump(_frame);
        pumps += 1;
        expect(drag.currentTarget?.span, target, reason: "pump $pumps");
      }
      expect(position.pixels, 112.0);
      drag.endDrag(cancel: true);
    },
    skip: true,
  );
}
