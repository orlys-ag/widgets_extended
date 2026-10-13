/// A resize's target is independent of the track changes its own
/// make-room preview makes: a still pointer keeps its target while the
/// preview grows or shrinks a content-sized track, and a moving pointer
/// moves the dragged edge one way only, through every track boundary.
///
/// Points are paint space in the board's frame.
library;

import 'dart:math' as math;

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

/// `d`'s stored span on criterion 1's board.
const BoardSpan _joinStored = BoardSpan(
  rowStart: 0,
  colStart: 0,
  rowSpan: 2,
  colSpan: 5,
);

/// The ids the make-room engine's own-preview scope has recorded.
List<int> _ownIds(BoardController<String, _Item> controller) {
  return <int>[
    for (var index = 0; index < controller.makeRoomOwnIdCount; index++)
      controller.makeRoomOwnIdAt(index),
  ];
}

/// The lane bucket member reads of one forced layout of [viewport], which
/// runs one placement pass.
Future<int> _readsOverForcedLayout(
  WidgetTester tester,
  BoardController<String, _Item> controller,
  RenderBoardViewport<String> viewport,
) async {
  controller.debugLaneBucketMemberReadCount = 0;
  viewport.markNeedsLayout();
  await tester.pump();
  expect(viewport.debugLastCorrectionPassCount, 1);
  return controller.debugLaneBucketMemberReadCount;
}

/// The track-space coordinate of the paint-space [y] on rows whose tops
/// and extents are [tops] and [extents], from the board's leading edge.
double _coordinateOn(List<double> tops, List<double> extents, double y) {
  if (y < 0.0) {
    return y / extents.first;
  }
  for (var row = 0; row < tops.length; row++) {
    if (y < tops[row] + extents[row]) {
      return row + (y - tops[row]) / extents[row];
    }
  }
  final total = tops.last + extents.last;
  return tops.length + (y - total) / extents.last;
}

/// Lifts `d`'s trailing edge at (40, [lift]) and moves it through
/// [steps], one pump after each. At each step the row at the target's
/// end paints within the change the session's own preview made to the
/// rows between the lift and the pointer of where the track snap puts the
/// end on the rows at rest, read before the lift; and where the preview
/// spans more than one row, `d`'s painted bottom is that row's top.
Future<void> _sweepEdge(
  WidgetTester tester,
  BoardController<String, _Item> controller,
  RenderBoardViewport<String> viewport, {
  required double lift,
  required List<double> steps,
  required double storedEnd,
}) async {
  final count = controller.rows.axis.trackCount;
  final tops = <double>[];
  final extents = <double>[];
  for (var row = 0; row < count; row++) {
    final rect = viewport.rectOfCell(row, 0)!;
    tops.add(rect.top);
    extents.add(rect.height);
  }
  double restTopOf(int row) {
    return row == count ? tops.last + extents.last : tops[row];
  }

  double paintedTopOf(int row) {
    return row == count
        ? viewport.rectOfCell(count - 1, 0)!.bottom
        : viewport.rectOfCell(row, 0)!.top;
  }

  final drag = _drag(tester, controller);
  _lift(
    tester,
    drag,
    viewport,
    key: "d",
    edge: BoardResizeEdges.trailing,
    axis: Axis.vertical,
    local: Offset(40.0, lift),
  );
  final liftCoordinate = _coordinateOn(tops, extents, lift);
  for (final y in steps) {
    _move(tester, drag, Offset(40.0, y));
    await tester.pump(_frame);
    final target = drag.currentTarget!.span;
    final end = target.endTrackOn(Axis.vertical).round();
    final snapped =
        (storedEnd + _coordinateOn(tops, extents, y) - liftCoordinate)
            .roundToDouble()
            .clamp(1.0, count.toDouble())
            .toInt();
    final low = math.min(lift, y);
    final high = math.max(lift, y);
    var allowance = 0.0;
    for (var row = 0; row < count; row++) {
      final painted = viewport.rectOfCell(row, 0)!;
      final restMeets = tops[row] <= high && tops[row] + extents[row] >= low;
      final paintedMeets = painted.top <= high && painted.bottom >= low;
      if (restMeets || paintedMeets) {
        allowance += (painted.height - extents[row]).abs();
      }
    }
    final edge = paintedTopOf(end);
    expect(
      (edge - restTopOf(snapped)).abs(),
      lessThanOrEqualTo(allowance + 1e-9),
      reason: "y $y, end $end, snapped $snapped",
    );
    if (target.endTrackOn(Axis.vertical) - target.startTrackOn(Axis.vertical) >
        1.0) {
      expect(
        viewport.paintedRectOfItem("d")!.bottom,
        moreOrLessEquals(edge, epsilon: 1e-9),
        reason: "y $y",
      );
    }
  }
  drag.endDrag(cancel: true);
  await tester.pumpAndSettle(_frame);
}

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
    await tester.pumpAndSettle(_frame);
  });

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
      await tester.pumpAndSettle(_frame);
    },
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
      await tester.pumpAndSettle(_frame);
    },
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
      await tester.pumpAndSettle(_frame);
    },
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
    await tester.pumpAndSettle(_frame);
  });

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
    await tester.pumpAndSettle(_frame);
  });

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
      await tester.pumpAndSettle(_frame);
    },
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
      await tester.pumpAndSettle(_frame);
    },
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
      await tester.pumpAndSettle(_frame);
    },
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
    await tester.pumpAndSettle(_frame);
  });

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
    await tester.pumpAndSettle(_frame);
  });

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
      await tester.pumpAndSettle(_frame);
    },
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
      await tester.pumpAndSettle(_frame);
    },
  );

  testWidgets(
    "another session's closing preview moves a resize target under a still "
    "pointer",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 8, style: _animated);
      _addDelaneItems(controller);
      controller.addItem(
        const _Item("e"),
        const BoardSpan(rowStart: 0, colStart: 5, colSpan: 2),
      );
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
      for (var pump = 1; pump <= 20; pump++) {
        await tester.pump(_frame);
      }
      expect(_rowExtent(viewport, 0), 22.0);
      drag.endDrag(cancel: true);
      _lift(
        tester,
        drag,
        viewport,
        key: "e",
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
        local: const Offset(220.0, 20.0),
      );
      _move(tester, drag, const Offset(220.0, 50.0));
      expect(
        drag.currentTarget?.span,
        const BoardSpan(rowStart: 0, colStart: 5, rowSpan: 4, colSpan: 2),
      );
      final ends = <double>[];
      for (var pump = 1; pump <= 20; pump++) {
        await tester.pump(_frame);
        final end = _endRow(drag);
        if (ends.isNotEmpty) {
          expect(end, lessThanOrEqualTo(ends.last), reason: "pump $pump");
        }
        ends.add(end);
      }
      expect(ends.first, 4.0);
      expect(ends.last, 2.0);
      expect(_rowExtent(viewport, 0), 40.0);
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle(_frame);
    },
  );

  testWidgets(
    "a scroll under a still pointer moves a resize target while its own "
    "preview stands",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 40);
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
      await tester.pump(_frame);
      expect(drag.currentTarget?.span, _delaneTarget);
      expect(_rowExtent(viewport, 0), 22.0);
      const scrolled = BoardSpan(
        rowStart: 0,
        colStart: 0,
        rowSpan: 4,
        colSpan: 5,
      );
      viewport.verticalPosition!.jumpTo(12.0);
      expect(drag.currentTarget?.span, scrolled);
      await tester.pump(_frame);
      expect(drag.currentTarget?.span, scrolled);
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle(_frame);
    },
  );

  testWidgets(
    "a vacate above the scroll anchor leaves a resize target where the "
    "scroll put it",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 40, style: _animated);
      _addDelaneItems(controller);
      final viewport = await _mount(tester, controller);
      final position = viewport.verticalPosition!;
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
      const target = BoardSpan(
        rowStart: 0,
        colStart: 0,
        rowSpan: 7,
        colSpan: 5,
      );
      position.jumpTo(45.0);
      expect(drag.currentTarget?.span, target);
      for (var pump = 1; pump <= 20; pump++) {
        await tester.pump(_frame);
        expect(drag.currentTarget?.span, target, reason: "pump $pump");
      }
      expect(position.pixels, moreOrLessEquals(27.0, epsilon: 1e-9));
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle(_frame);
    },
  );

  testWidgets(
    "another item's enter ramp moves a resize target under a still pointer",
    (tester) async {
      final controller = _rowsLaned(
        tester,
        style: const BoardAnimationStyle(
          trackResize: _ms200,
          itemSlide: BoardAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
        ),
      );
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
      await tester.pump(_frame);
      await tester.pump(_frame);
      expect(drag.currentTarget?.span, _joinTarget);
      expect(_rowExtent(viewport, 1), 40.0);
      controller.addItem(
        const _Item("f"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 3),
      );
      expect(drag.currentTarget?.span, _joinTarget);
      for (var pump = 1; pump <= 20; pump++) {
        await tester.pump(_frame);
      }
      expect(drag.currentTarget?.span, _joinStored);
      expect(_rowExtent(viewport, 0), 22.0);
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle(_frame);
    },
  );

  testWidgets(
    "a resize that a pointerPosition listener ends inside startDrag leaves "
    "no scope open",
    (tester) async {
      final controller = _rowsLaned(tester);
      _addJoinItems(controller);
      final viewport = await _mount(tester, controller);
      final drag = _drag(tester, controller);
      var ended = false;
      void listener() {
        if (!ended && drag.pointerPosition.value != null) {
          ended = true;
          drag.endDrag(cancel: true);
        }
      }

      drag.pointerPosition.addListener(listener);
      addTearDown(() {
        drag.pointerPosition.removeListener(listener);
      });
      _lift(
        tester,
        drag,
        viewport,
        key: "d",
        edge: BoardResizeEdges.leading,
        axis: Axis.vertical,
        local: const Offset(40.0, 9.0),
      );
      expect(ended, isTrue);
      expect(controller.makeRoomOwnPreviewEpoch, 0);
    },
  );

  group("a resize's dragged edge paints within its own preview's change of "
      "where the snap puts it", () {
    testWidgets("(a) a sweep down that de-lanes the item", (tester) async {
      final controller = _rowsLaned(tester);
      _addDelaneItems(controller);
      final viewport = await _mount(tester, controller);
      await _sweepEdge(
        tester,
        controller,
        viewport,
        lift: 20.0,
        steps: <double>[for (var y = 21; y <= 80; y++) y.toDouble()],
        storedEnd: 1.0,
      );
    });

    testWidgets("(b) a sweep up that lanes the item", (tester) async {
      final controller = _rowsLaned(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 4),
      );
      controller.addItem(
        const _Item("d"),
        const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 3, colSpan: 5),
      );
      final viewport = await _mount(tester, controller);
      await _sweepEdge(
        tester,
        controller,
        viewport,
        lift: 41.0,
        steps: <double>[for (var y = 40; y >= 1; y--) y.toDouble()],
        storedEnd: 3.0,
      );
    });
  });

  testWidgets(
    "an axis-config change re-derives a resize's lift without its own "
    "preview",
    (tester) async {
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
      _move(tester, drag, const Offset(40.0, 50.0));
      await tester.pump(_frame);
      expect(drag.currentTarget?.span, _delaneTarget);
      expect(_rowExtent(viewport, 0), 22.0);
      // One more track, which re-derives the lift: the lift point reads
      // row 20 / 22 as the rows paint and 0.5 without the preview.
      controller.rows = BoardAxisConfig(
        axis: LazyContentAxis(7, 80.0),
        laneExtent: 18.0,
        lanePadding: 4.0,
      );
      for (var pump = 1; pump <= 4; pump++) {
        await tester.pump(_frame);
        if (pump == 1) {
          expect(_rowExtent(viewport, 0), 22.0);
        }
        expect(drag.currentTarget?.span, _delaneTarget, reason: "pump $pump");
      }
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle(_frame);
    },
  );

  testWidgets(
    "a track resize in flight on the track its own preview changes moves a "
    "resize target",
    (tester) async {
      final controller = _rowsLaned(
        tester,
        style: const BoardAnimationStyle(
          trackResize: _ms200,
          itemSlide: BoardAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
          itemEnterExit: BoardAnimationSpec(
            duration: Duration.zero,
            curve: Curves.linear,
          ),
        ),
      );
      _addDelaneItems(controller);
      final viewport = await _mount(tester, controller);
      // A third lane in row 0, which a track resize grows the row to.
      controller.addItem(
        const _Item("f"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 3),
      );
      await tester.pump(_frame);
      expect(_rowExtent(viewport, 0), 40.0);
      expect(controller.anim.hasActiveTrackResize, isTrue);
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
      final ends = <double>[];
      for (var pump = 1; pump <= 20; pump++) {
        await tester.pump(_frame);
        final end = _endRow(drag);
        if (ends.isNotEmpty) {
          expect(end, lessThanOrEqualTo(ends.last), reason: "pump $pump");
        }
        ends.add(end);
      }
      expect(ends.first, 2.0);
      expect(ends.last, 1.0);
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle(_frame);
    },
  );

  testWidgets("an id recycled on an own track is not own", (tester) async {
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
    _move(tester, drag, const Offset(40.0, 20.0));
    await tester.pump(_frame);
    final id = controller.idOfKey("a");
    expect(drag.currentTarget?.span, _joinTarget);
    expect(_rowExtent(viewport, 1), 40.0);
    expect(_ownIds(controller), <int>[id]);
    controller.removeItem("a");
    await tester.pump(_frame);
    expect(_ownIds(controller), isEmpty);
    expect(drag.currentTarget?.span, _joinTarget);
    controller.addItem(
      const _Item("g"),
      const BoardSpan(rowStart: 1, colStart: 5, colSpan: 2),
    );
    expect(controller.idOfKey("g"), id);
    for (var pump = 1; pump <= 4; pump++) {
      await tester.pump(_frame);
      expect(_ownIds(controller), isEmpty, reason: "pump $pump");
      expect(drag.currentTarget?.span, _joinTarget, reason: "pump $pump");
    }
    drag.endDrag(cancel: true);
    await tester.pumpAndSettle(_frame);
  });

  testWidgets(
    "with no resize preview standing a layout does no own-free work",
    (tester) async {
      for (final style in <BoardAnimationStyle>[
        BoardAnimationStyle.disabled,
        _animated,
      ]) {
        final controller = _rowsLaned(tester, style: style);
        _addJoinItems(controller);
        final viewport = await _mount(tester, controller);
        final idle = await _readsOverForcedLayout(tester, controller, viewport);
        final drag = _drag(tester, controller);
        if (identical(style, BoardAnimationStyle.disabled)) {
          // (i) A move of `a` into row 4, whose slot stands there.
          expect(
            drag.startDrag(
              key: "a",
              renderPort: viewport,
              pointerGlobal: _global(tester, const Offset(40.0, 20.0)),
            ),
            isTrue,
          );
          _move(tester, drag, const Offset(40.0, 60.0));
          await tester.pump(_frame);
          expect(controller.anim.makeRoomSlotsOn(4).length, 1);
          expect(
            await _readsOverForcedLayout(tester, controller, viewport),
            idle,
            reason: "a move",
          );
          drag.endDrag(cancel: true);
          await tester.pump(_frame);
          // (ii) A resize whose target is the stored span.
          _lift(
            tester,
            drag,
            viewport,
            key: "d",
            edge: BoardResizeEdges.leading,
            axis: Axis.vertical,
            local: const Offset(40.0, 9.0),
          );
          _move(tester, drag, const Offset(40.0, 12.0));
          await tester.pump(_frame);
          expect(drag.currentTarget?.span, _joinStored);
          expect(
            await _readsOverForcedLayout(tester, controller, viewport),
            idle,
            reason: "a resize at its stored span",
          );
          drag.endDrag(cancel: true);
          await tester.pumpAndSettle(_frame);
        } else {
          // (iii) R2's session, cancelled while its slot animates.
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
          await tester.pump(_frame);
          await tester.pump(_frame);
          drag.endDrag(cancel: true);
          await tester.pump(_frame);
          expect(controller.anim.makeRoomSlotsOn(1).length, 1);
          expect(
            await _readsOverForcedLayout(tester, controller, viewport),
            idle,
            reason: "a cancelled resize's closing preview",
          );
          await tester.pumpAndSettle(_frame);
        }
      }
    },
  );

  testWidgets(
    "a resize whose own preview closed with the board scrolled steps once to "
    "the pointer and then holds",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 40);
      _addDelaneItems(controller, row: 39);
      final viewport = await _mount(tester, controller);
      final position = viewport.verticalPosition!;
      position.jumpTo(130.0);
      await tester.pump();
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
      _move(tester, drag, const Offset(40.0, 236.0));
      await tester.pump(_frame);
      expect(
        drag.currentTarget?.span,
        const BoardSpan(rowStart: 36, colStart: 0, rowSpan: 4, colSpan: 5),
      );
      expect(position.pixels, 112.0);
      // Back to the lift point: the stored span, whose install closes the
      // vacate and leaves the pixels at 112, 18 px short of where the
      // own-free lattice read them.
      _move(tester, drag, const Offset(40.0, 266.0));
      expect(
        drag.currentTarget?.span,
        const BoardSpan(rowStart: 39, colStart: 0, colSpan: 5),
      );
      // The layout that closes the preview takes the scroll it left as the
      // board's own, and the resolve after it reads the pointer on row
      // 37.8, so the leading edge steps once, to row 38.
      const stepped = BoardSpan(
        rowStart: 38,
        colStart: 0,
        rowSpan: 2,
        colSpan: 5,
      );
      await tester.pump(_frame);
      expect(drag.currentTarget?.span, stepped);
      for (var pump = 1; pump <= 6; pump++) {
        await tester.pump(_frame);
        expect(drag.currentTarget?.span, stepped, reason: "pump $pump");
      }
      expect(position.pixels, 112.0);
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle(_frame);
    },
  );
}
