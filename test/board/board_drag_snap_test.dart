/// Where a drag's target lands under each snap when the drag has not moved the
/// item far: a press or a lift that does not move leaves the span as it was
/// where `canDropAt` admits it, an axis stays put until its anchor reaches a
/// grid line or travels half a quantum, and a resize never lengthens a short
/// item against the pointer.
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
import 'package:widgets_extended/board/board_views.dart';
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

BoardController<String, _Item> _calendar(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(24, 60.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 170.0), laneExtent: 170.0),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  return controller;
}

Widget? _nullCell(BuildContext context, BoardCellView<String, _Item> cell) {
  return null;
}

Widget _plainItem(BuildContext context, BoardItemView<String, _Item> item) {
  return const ColoredBox(color: Color(0xFF4CAF50));
}

Widget _frame(Widget board, {double width = 700.0, double height = 700.0}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: _frameKey,
          width: width,
          height: height,
          child: board,
        ),
      ),
    ),
  );
}

/// What a config's callbacks heard.
class _Record {
  final List<BoardSpan> reports = <BoardSpan>[];
  final List<BoardDropTarget?> targets = <BoardDropTarget?>[];
  final List<(String, bool)> ends = <(String, bool)>[];
}

BoardDragConfig<String> _config(
  BoardController<String, _Item> controller,
  _Record record, {
  required BoardSnap snap,
  BoardResizeEdges primaryResizeEdges = BoardResizeEdges.none,
  Duration dragStartDelay = kLongPressTimeout,
  BoardDropFit? dropFit,
  bool Function(String key, BoardSpan span)? canDropAt,
  double autoScrollEdgeZone = 48.0,
}) {
  return BoardDragConfig<String>(
    snap: snap,
    primaryResizeEdges: primaryResizeEdges,
    dragStartDelay: dragStartDelay,
    dropFit: dropFit,
    canDropAt: canDropAt,
    autoScrollEdgeZone: autoScrollEdgeZone,
    onItemMoved: (key, span) {
      record.reports.add(span);
      controller.moveItem(key, span);
    },
    onItemResized: (key, span) {
      record.reports.add(span);
      controller.resizeItem(key, span);
    },
    onDragTargetChanged: (key, target) {
      record.targets.add(target);
    },
    onDragEnd: (key, committed) {
      record.ends.add((key, committed));
    },
  );
}

double _end(BoardSpan span) {
  return span.endTrackOn(Axis.vertical);
}

double _start(BoardSpan span) {
  return span.startTrackOn(Axis.vertical);
}

bool _overlapsOther(
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
    final rowsMeet =
        span.startTrackOn(Axis.vertical) < o.endTrackOn(Axis.vertical) &&
        o.startTrackOn(Axis.vertical) < span.endTrackOn(Axis.vertical);
    final colsMeet =
        span.startTrackOn(Axis.horizontal) < o.endTrackOn(Axis.horizontal) &&
        o.startTrackOn(Axis.horizontal) < span.endTrackOn(Axis.horizontal);
    if (rowsMeet && colsMeet) {
      return true;
    }
  }
  return false;
}

/// Presses at [local], holds it for [hold], and releases it: on a resize
/// handle, or, when [lifted], on the body of an item the press moves.
///
/// (b) runs for a resize only: the make-room preview gives a lifted item
/// no held offset, so its painted rect stays where it was whatever the
/// target.
Future<void> _gestureTap(
  WidgetTester tester,
  BoardController<String, _Item> controller,
  Offset local, {
  required BoardSpan stored,
  required _Record record,
  required Rect before,
  Duration hold = Duration.zero,
  bool lifted = false,
}) async {
  final gesture = await tester.startGesture(_global(tester, local));
  await tester.pump(hold);
  await tester.pump();
  // Setup sanity: the press started a session.
  expect(controller.isDragging("m"), isTrue);
  // (a) The first target reported is the stored span.
  expect(record.targets.first!.span, stored);
  if (!lifted) {
    // (b) Nothing previews a change.
    expect(_viewport(tester).paintedRectOfItem("m"), before);
  }
  await gesture.up();
  await tester.pumpAndSettle();
  // (c) The single report is the stored span.
  expect(record.reports, <BoardSpan>[stored]);
  // (d) The item rests where it was.
  expect(_viewport(tester).rectOfItem("m"), before);
  // (e) The drop was reported as committed.
  expect(record.ends, <(String, bool)>[("m", true)]);
}

void main() {
  group("resize", () {
    testWidgets("T1 a tap on a trailing handle under a fraction snap keeps "
        "an off-grid end", (tester) async {
      final controller = _controller(tester);
      const stored = BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowSpan: 1,
        rowSpanFraction: 0.4,
      );
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(
        _board(
          controller,
          drag: _config(
            controller,
            record,
            snap: const BoardSnap.fraction(0.25),
            primaryResizeEdges: BoardResizeEdges.trailing,
          ),
        ),
      );
      final before = _viewport(tester).rectOfItem("m")!;
      await _gestureTap(
        tester,
        controller,
        const Offset(60.0, 166.0),
        stored: stored,
        record: record,
        before: before,
      );
    });

    testWidgets("T2 a tap on a trailing handle under a track snap keeps a "
        "quarter-track item", (tester) async {
      final controller = _controller(tester);
      const stored = BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowSpan: 0,
        rowSpanFraction: 0.25,
      );
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(
        _board(
          controller,
          drag: _config(
            controller,
            record,
            snap: const BoardSnap.track(),
            primaryResizeEdges: BoardResizeEdges.trailing,
          ),
        ),
      );
      final before = _viewport(tester).rectOfItem("m")!;
      await _gestureTap(
        tester,
        controller,
        const Offset(60.0, 110.5),
        stored: stored,
        record: record,
        before: before,
      );
    });

    testWidgets("T3 a leading press that does not move keeps an off-grid "
        "start", (tester) async {
      final controller = _controller(tester);
      const stored = BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowFraction: 0.6,
        rowSpan: 1,
        rowSpanFraction: 0.4,
      );
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        _config(
          controller,
          record,
          snap: const BoardSnap.fraction(0.25),
          primaryResizeEdges: BoardResizeEdges.leading,
        ),
      );
      expect(
        drag.startDrag(
          key: "m",
          renderPort: _viewport(tester),
          pointerGlobal: _global(tester, const Offset(60.0, 134.0)),
          edge: BoardResizeEdges.leading,
          axis: Axis.vertical,
        ),
        isTrue,
      );
      expect(drag.currentTarget!.span, stored);
      drag.endDrag(cancel: false);
      expect(record.reports.single, stored);
    });

    testWidgets("T4 a free-snap tap reports the stored fields", (
      tester,
    ) async {
      final controller = _controller(tester);
      const stored = BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowSpan: 1,
        rowSpanFraction: 0.4,
      );
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        _config(
          controller,
          record,
          snap: const BoardSnap.free(),
          primaryResizeEdges: BoardResizeEdges.trailing,
        ),
      );
      drag.startDrag(
        key: "m",
        renderPort: _viewport(tester),
        pointerGlobal: _global(tester, const Offset(60.0, 166.0)),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      );
      drag.endDrag(cancel: false);
      expect(record.reports.single, stored);
      expect(record.reports.single.rowSpanFraction, 0.4);
    });

    testWidgets("T5 a free-snap tap keeps an item shorter than the free "
        "quantum", (tester) async {
      final controller = _controller(tester);
      const stored = BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowSpan: 0,
        rowSpanFraction: 0.1,
      );
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        _config(
          controller,
          record,
          snap: const BoardSnap.free(),
          primaryResizeEdges: BoardResizeEdges.trailing,
        ),
      );
      drag.startDrag(
        key: "m",
        renderPort: _viewport(tester),
        pointerGlobal: _global(tester, const Offset(60.0, 104.0)),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      );
      drag.endDrag(cancel: false);
      expect(record.reports.single, stored);
    });

    testWidgets("T6 an edge short of a grid line and of half a quantum "
        "stays", (tester) async {
      final controller = _controller(tester);
      const stored = BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowSpan: 1,
        rowSpanFraction: 0.4,
      );
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(_board(controller));
      final viewport = _viewport(tester);
      final drag = _drag(
        tester,
        controller,
        _config(
          controller,
          record,
          snap: const BoardSnap.fraction(0.25),
          primaryResizeEdges: BoardResizeEdges.trailing,
        ),
      );
      // Setup sanity: 4 px is 0.08 of a track.
      expect(
        viewport.trackSpaceAt(const Offset(60.0, 170.0))!.row -
            viewport.trackSpaceAt(const Offset(60.0, 166.0))!.row,
        closeTo(0.08, 1e-9),
      );
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(60.0, 166.0)),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      );
      drag.updateDrag(_global(tester, const Offset(60.0, 170.0)));
      expect(drag.currentTarget!.span, stored);
      drag.updateDrag(_global(tester, const Offset(60.0, 172.0)));
      expect(_end(drag.currentTarget!.span), closeTo(3.5, 1e-9));
      drag.updateDrag(_global(tester, const Offset(60.0, 161.0)));
      expect(drag.currentTarget!.span, stored);
      drag.endDrag(cancel: false);
      expect(record.reports.single, stored);
    });

    testWidgets("T7 a reversed axis keeps and releases by the content "
        "direction", (tester) async {
      final controller = _controller(tester);
      const stored = BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowSpan: 1,
        rowSpanFraction: 0.4,
      );
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(_board(controller, reverseVertical: true));
      final viewport = _viewport(tester);
      // Setup sanity: the content-trailing edge is on top.
      expect(
        viewport.rectOfItem("m"),
        const Rect.fromLTRB(40.0, 130.0, 80.0, 200.0),
      );
      final drag = _drag(
        tester,
        controller,
        _config(
          controller,
          record,
          snap: const BoardSnap.fraction(0.25),
          primaryResizeEdges: BoardResizeEdges.trailing,
        ),
      );
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(60.0, 134.0)),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      );
      // Setup sanity: screen-up is content-forward.
      expect(
        viewport.trackSpaceAt(const Offset(60.0, 130.0))!.row -
            viewport.trackSpaceAt(const Offset(60.0, 134.0))!.row,
        closeTo(0.08, 1e-9),
      );
      drag.updateDrag(_global(tester, const Offset(60.0, 130.0)));
      expect(drag.currentTarget!.span, stored);
      drag.updateDrag(_global(tester, const Offset(60.0, 128.0)));
      expect(_end(drag.currentTarget!.span), closeTo(3.5, 1e-9));
      drag.updateDrag(_global(tester, const Offset(60.0, 125.0)));
      expect(_end(drag.currentTarget!.span), closeTo(3.5, 1e-9));
      drag.updateDrag(_global(tester, const Offset(60.0, 130.0)));
      expect(drag.currentTarget!.span, stored);
      drag.endDrag(cancel: false);
      expect(record.reports.single, stored);
    });

    testWidgets("T8 half a quantum releases the edge", (tester) async {
      final controller = _controller(tester);
      const stored = BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowSpan: 1,
        rowSpanFraction: 0.4,
      );
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        _config(
          controller,
          record,
          snap: const BoardSnap.fraction(0.25),
          primaryResizeEdges: BoardResizeEdges.trailing,
        ),
      );
      drag.startDrag(
        key: "m",
        renderPort: _viewport(tester),
        pointerGlobal: _global(tester, const Offset(60.0, 166.0)),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      );
      drag.updateDrag(_global(tester, const Offset(60.0, 173.0)));
      expect(_end(drag.currentTarget!.span), closeTo(3.5, 1e-9));
      drag.updateDrag(_global(tester, const Offset(60.0, 159.0)));
      expect(_end(drag.currentTarget!.span), closeTo(3.25, 1e-9));
      drag.endDrag(cancel: true);
    });

    testWidgets("T9 an on-grid edge moves as before", (tester) async {
      final controller = _controller(tester);
      const stored = BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowSpan: 1,
        rowSpanFraction: 0.5,
      );
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        _config(
          controller,
          record,
          snap: const BoardSnap.fraction(0.25),
          primaryResizeEdges: BoardResizeEdges.trailing,
        ),
      );
      drag.startDrag(
        key: "m",
        renderPort: _viewport(tester),
        pointerGlobal: _global(tester, const Offset(60.0, 171.0)),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      );
      expect(drag.currentTarget!.span, stored);
      drag.updateDrag(_global(tester, const Offset(60.0, 176.0)));
      expect(drag.currentTarget!.span, stored);
      drag.updateDrag(_global(tester, const Offset(60.0, 178.0)));
      expect(_end(drag.currentTarget!.span), closeTo(3.75, 1e-9));
      drag.endDrag(cancel: true);
    });

    testWidgets("T10 the floor never lengthens a short item against the "
        "pointer", (tester) async {
      final controller = _controller(tester);
      const stored = BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowSpan: 0,
        rowSpanFraction: 0.25,
      );
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        _config(
          controller,
          record,
          snap: const BoardSnap.track(),
          primaryResizeEdges: BoardResizeEdges.trailing,
        ),
      );
      drag.startDrag(
        key: "m",
        renderPort: _viewport(tester),
        pointerGlobal: _global(tester, const Offset(60.0, 110.0)),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      );
      drag.updateDrag(_global(tester, const Offset(60.0, 80.0)));
      expect(drag.currentTarget!.span, stored);
      drag.endDrag(cancel: false);
      expect(record.reports.single, stored);
    });

    testWidgets("T11 a short off-grid item grown lands on the grid and "
        "keeps its start fields", (tester) async {
      final controller = _controller(tester);
      const stored = BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowFraction: 0.1,
        rowSpan: 0,
        rowSpanFraction: 0.25,
      );
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        _config(
          controller,
          record,
          snap: const BoardSnap.track(),
          primaryResizeEdges: BoardResizeEdges.trailing,
        ),
      );
      drag.startDrag(
        key: "m",
        renderPort: _viewport(tester),
        pointerGlobal: _global(tester, const Offset(60.0, 115.5)),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      );
      drag.updateDrag(_global(tester, const Offset(60.0, 145.5)));
      final span = drag.currentTarget!.span;
      expect(_end(span), closeTo(3.0, 1e-9));
      expect(span.rowStart, 2);
      expect(span.rowFraction, 0.1);
      drag.endDrag(cancel: true);
    });

    testWidgets("T12 a long item shrunk far floors at one quantum", (
      tester,
    ) async {
      final controller = _controller(tester);
      const stored = BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowSpan: 1,
        rowSpanFraction: 0.5,
      );
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        _config(
          controller,
          record,
          snap: const BoardSnap.track(),
          primaryResizeEdges: BoardResizeEdges.trailing,
        ),
      );
      drag.startDrag(
        key: "m",
        renderPort: _viewport(tester),
        pointerGlobal: _global(tester, const Offset(60.0, 171.0)),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      );
      drag.updateDrag(_global(tester, const Offset(60.0, 81.0)));
      expect(
        drag.currentTarget!.span,
        const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 1),
      );
      drag.endDrag(cancel: true);
    });

    testWidgets("T13 a laned item's press previews nothing", (tester) async {
      final controller = _calendar(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
      );
      const stored = BoardSpan(
        rowStart: 3,
        colStart: 1,
        rowSpan: 1,
        rowSpanFraction: 0.4,
      );
      controller.addItem(const _Item("b"), stored);
      final record = _Record();
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _nullCell,
            itemBuilder: _plainItem,
          ),
        ),
      );
      final viewport = _viewport(tester);
      expect(controller.laneOf("b"), 1);
      final before = viewport.rectOfItem("b")!;
      expect(before, const Rect.fromLTRB(255.0, 180.0, 340.0, 264.0));
      final drag = _drag(
        tester,
        controller,
        _config(
          controller,
          record,
          snap: const BoardSnap.fraction(0.25),
          primaryResizeEdges: BoardResizeEdges.trailing,
        ),
      );
      drag.startDrag(
        key: "b",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(297.0, 260.0)),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      );
      await tester.pump();
      expect(viewport.paintedRectOfItem("b"), before);
      drag.endDrag(cancel: false);
      expect(record.reports.single, stored);
    });
  });

  group("move", () {
    Future<void> longPressInPlace(
      WidgetTester tester,
      BoardSpan stored,
      BoardSnap snap,
    ) async {
      final controller = _controller(tester);
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(
        _board(
          controller,
          drag: _config(
            controller,
            record,
            snap: snap,
            dragStartDelay: const Duration(milliseconds: 100),
          ),
        ),
      );
      final before = _viewport(tester).rectOfItem("m")!;
      await _gestureTap(
        tester,
        controller,
        before.center,
        stored: stored,
        record: record,
        before: before,
        hold: const Duration(milliseconds: 150),
        lifted: true,
      );
    }

    testWidgets("M1 a long press released in place keeps an off-grid "
        "item under a fraction snap", (tester) async {
      await longPressInPlace(
        tester,
        const BoardSpan(rowStart: 2, colStart: 1, rowFraction: 0.1),
        const BoardSnap.fraction(0.25),
      );
    });

    testWidgets("M2 a long press released in place keeps an off-grid "
        "item under a track snap", (tester) async {
      await longPressInPlace(
        tester,
        const BoardSpan(rowStart: 2, colStart: 1, rowFraction: 0.3),
        const BoardSnap.track(),
      );
    });

    Future<
      ({
        BoardController<String, _Item> controller,
        BoardDragController<String> drag,
        _Record record,
      })
    >
    plainMove(
      WidgetTester tester,
      BoardSnap snap, {
      BoardSpan stored = const BoardSpan(
        rowStart: 2,
        colStart: 1,
        rowFraction: 0.1,
      ),
      int rows = 6,
      bool reverseVertical = false,
      double autoScrollEdgeZone = 48.0,
    }) async {
      final controller = _controller(tester, rows: rows);
      controller.addItem(const _Item("m"), stored);
      final record = _Record();
      await tester.pumpWidget(
        _board(controller, reverseVertical: reverseVertical),
      );
      final drag = _drag(
        tester,
        controller,
        _config(
          controller,
          record,
          snap: snap,
          autoScrollEdgeZone: autoScrollEdgeZone,
        ),
      );
      return (controller: controller, drag: drag, record: record);
    }

    testWidgets("M3 a free-snap lift reports the stored fields", (
      tester,
    ) async {
      const stored = BoardSpan(rowStart: 2, colStart: 1, rowFraction: 0.1);
      final setup = await plainMove(tester, const BoardSnap.free());
      setup.drag.startDrag(
        key: "m",
        renderPort: _viewport(tester),
        pointerGlobal: _global(tester, const Offset(60.0, 130.0)),
      );
      setup.drag.endDrag(cancel: false);
      expect(setup.record.reports.single, stored);
      expect(setup.record.reports.single.rowFraction, 0.1);
    });

    testWidgets("M4 a drag short of the dead zone on both axes keeps the "
        "span", (tester) async {
      const stored = BoardSpan(rowStart: 2, colStart: 1, rowFraction: 0.1);
      final setup = await plainMove(tester, const BoardSnap.fraction(0.25));
      final viewport = _viewport(tester);
      final drag = setup.drag;
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(60.0, 130.0)),
      );
      final cornerBefore = viewport.trackSpaceAt(
        viewport.leadingCornerOf(drag.proxyTopLeft! & drag.proxySize!),
      )!;
      drag.updateDrag(_global(tester, const Offset(64.0, 135.0)));
      final cornerAfter = viewport.trackSpaceAt(
        viewport.leadingCornerOf(drag.proxyTopLeft! & drag.proxySize!),
      )!;
      // Setup sanity: the corner moved 0.1 track on each axis.
      expect(cornerAfter.row - cornerBefore.row, closeTo(0.1, 1e-9));
      expect(cornerAfter.col - cornerBefore.col, closeTo(0.1, 1e-9));
      expect(drag.currentTarget!.span, stored);
      drag.endDrag(cancel: false);
      expect(setup.record.reports.single, stored);
    });

    testWidgets("M5 a drag along one axis keeps the other", (tester) async {
      final setup = await plainMove(tester, const BoardSnap.track());
      final drag = setup.drag;
      drag.startDrag(
        key: "m",
        renderPort: _viewport(tester),
        pointerGlobal: _global(tester, const Offset(60.0, 130.0)),
      );
      drag.updateDrag(_global(tester, const Offset(140.0, 133.0)));
      final span = drag.currentTarget!.span;
      expect(span.colStart, 3);
      expect(span.rowStart, 2);
      expect(span.rowFraction, 0.1);
      drag.endDrag(cancel: true);
    });

    testWidgets("M6 a drag of 0.2 track under a quarter snap moves", (
      tester,
    ) async {
      final setup = await plainMove(tester, const BoardSnap.fraction(0.25));
      final drag = setup.drag;
      drag.startDrag(
        key: "m",
        renderPort: _viewport(tester),
        pointerGlobal: _global(tester, const Offset(60.0, 130.0)),
      );
      drag.updateDrag(_global(tester, const Offset(60.0, 140.0)));
      expect(_start(drag.currentTarget!.span), closeTo(2.25, 1e-9));
      drag.endDrag(cancel: true);
    });

    testWidgets("M7 content scrolled under a still finger counts as "
        "displacement", (tester) async {
      const stored = BoardSpan(rowStart: 2, colStart: 1, rowFraction: 0.1);
      final setup = await plainMove(
        tester,
        const BoardSnap.fraction(0.25),
        rows: 12,
        autoScrollEdgeZone: 0.0,
      );
      final viewport = _viewport(tester);
      expect(viewport.verticalPosition!.maxScrollExtent, greaterThan(0.0));
      final drag = setup.drag;
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(60.0, 130.0)),
      );
      viewport.verticalPosition!.jumpTo(5.0);
      await tester.pump();
      expect(drag.currentTarget!.span, stored);
      viewport.verticalPosition!.jumpTo(10.0);
      await tester.pump();
      expect(_start(drag.currentTarget!.span), closeTo(2.25, 1e-9));
      drag.endDrag(cancel: true);
    });

    testWidgets("M8 a reversed axis measures the corner content-forward", (
      tester,
    ) async {
      const stored = BoardSpan(rowStart: 2, colStart: 1, rowFraction: 0.1);
      final setup = await plainMove(
        tester,
        const BoardSnap.fraction(0.25),
        reverseVertical: true,
      );
      final viewport = _viewport(tester);
      expect(
        viewport.rectOfItem("m"),
        const Rect.fromLTRB(40.0, 145.0, 80.0, 195.0),
      );
      final drag = setup.drag;
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(60.0, 170.0)),
      );
      expect(drag.currentTarget!.span, stored);
      drag.updateDrag(_global(tester, const Offset(60.0, 165.0)));
      expect(drag.currentTarget!.span, stored);
      drag.updateDrag(_global(tester, const Offset(60.0, 160.0)));
      expect(_start(drag.currentTarget!.span), closeTo(2.25, 1e-9));
      drag.endDrag(cancel: true);
    });

    Future<
      ({
        BoardController<String, _Item> controller,
        BoardDragController<String> drag,
        _Record record,
      })
    >
    calendarMove(WidgetTester tester, BoardSnap snap) async {
      final controller = _calendar(tester);
      final record = _Record();
      final drag = _drag(
        tester,
        controller,
        _config(controller, record, snap: snap, autoScrollEdgeZone: 0.0),
      );
      return (controller: controller, drag: drag, record: record);
    }

    testWidgets("M9 a laned item moved one day keeps its time", (
      tester,
    ) async {
      final setup = await calendarMove(tester, const BoardSnap.fraction(0.25));
      final controller = setup.controller;
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
      );
      const stored = BoardSpan(
        rowStart: 3,
        colStart: 1,
        rowFraction: 0.1,
        rowSpan: 2,
      );
      controller.addItem(const _Item("b"), stored);
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _nullCell,
            itemBuilder: _plainItem,
          ),
        ),
      );
      final viewport = _viewport(tester);
      expect(controller.laneOf("b"), 1);
      expect(
        viewport.rectOfItem("b"),
        const Rect.fromLTRB(255.0, 186.0, 340.0, 306.0),
      );
      final drag = setup.drag;
      drag.startDrag(
        key: "b",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(297.0, 246.0)),
      );
      expect(drag.currentTarget!.span, stored);
      drag.updateDrag(_global(tester, const Offset(467.0, 246.0)));
      final span = drag.currentTarget!.span;
      expect(span.colStart, 2);
      expect(span.colFraction, 0.0);
      expect(span.rowStart, 3);
      expect(span.rowFraction, 0.1);
      drag.endDrag(cancel: true);
    });

    testWidgets("M10 a half-day chip lifted in place keeps its lane-axis "
        "fraction", (tester) async {
      final setup = await calendarMove(tester, const BoardSnap.fraction(0.25));
      final controller = setup.controller;
      const stored = BoardSpan(
        rowStart: 8,
        colStart: 1,
        colFraction: 0.5,
        colSpan: 0,
        colSpanFraction: 0.5,
      );
      controller.addItem(const _Item("c"), stored);
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _nullCell,
            itemBuilder: _plainItem,
          ),
        ),
      );
      final viewport = _viewport(tester);
      expect(controller.isLanedId(controller.idOfKey("c")), isTrue);
      setup.drag.startDrag(
        key: "c",
        renderPort: viewport,
        pointerGlobal: _global(tester, viewport.rectOfItem("c")!.center),
      );
      setup.drag.endDrag(cancel: false);
      expect(setup.record.reports.single, stored);
    });

    testWidgets("M11 the nudge keeps the axis it does not step", (
      tester,
    ) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("o"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1, rowFraction: 0.1),
      );
      final record = _Record();
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        _config(
          controller,
          record,
          snap: const BoardSnap.track(),
          dropFit: const BoardDropFit(),
          canDropAt: (key, span) {
            return !_overlapsOther(controller, key, span);
          },
        ),
      );
      drag.startDrag(
        key: "m",
        renderPort: _viewport(tester),
        pointerGlobal: _global(tester, const Offset(60.0, 130.0)),
      );
      drag.endDrag(cancel: false);
      final span = record.reports.single;
      expect(span.colStart, 0);
      expect(span.colFraction, 0.0);
      expect(span.rowStart, 2);
      expect(span.rowFraction, 0.1);
    });

    testWidgets("M12 a corner put onto the nearest line lands there", (
      tester,
    ) async {
      const stored = BoardSpan(rowStart: 2, colStart: 1, rowFraction: 0.9);
      final setup = await plainMove(
        tester,
        const BoardSnap.track(),
        stored: stored,
      );
      final viewport = _viewport(tester);
      expect(viewport.rectOfItem("m")!.top, 145.0);
      final drag = setup.drag;
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(60.0, 170.0)),
      );
      drag.updateDrag(_global(tester, const Offset(60.0, 173.0)));
      expect(drag.currentTarget!.span, stored);
      drag.updateDrag(_global(tester, const Offset(60.0, 175.0)));
      expect(drag.currentTarget!.span.rowStart, 3);
      expect(drag.currentTarget!.span.rowFraction, 0.0);
      drag.updateDrag(_global(tester, const Offset(60.0, 190.0)));
      expect(drag.currentTarget!.span.rowStart, 3);
      expect(drag.currentTarget!.span.rowFraction, 0.0);
      drag.endDrag(cancel: false);
      expect(setup.record.reports.single.rowStart, 3);
      expect(setup.record.reports.single.rowFraction, 0.0);
    });

    testWidgets("M13 a lift during a start-track resize measures from the "
        "lift corner", (tester) async {
      const stored = BoardSpan(rowStart: 2, colStart: 1, rowFraction: 0.4);
      final setup = await plainMove(
        tester,
        const BoardSnap.fraction(0.25),
        stored: stored,
      );
      final controller = setup.controller;
      const zero = BoardAnimationSpec(
        duration: Duration.zero,
        curve: Curves.linear,
      );
      controller.animationStyle = const BoardAnimationStyle(
        trackResize: BoardAnimationSpec(
          duration: Duration(seconds: 10),
          curve: Curves.linear,
        ),
        itemSlide: zero,
        itemEnterExit: zero,
        makeRoom: zero,
        dropSettle: zero,
      );
      controller.animateTrackResize(Axis.vertical, 2, 75.0);
      await tester.pump();
      final viewport = _viewport(tester);
      final rect = viewport.rectOfItem("m")!;
      // Setup sanity: the corner maps below the stored start.
      expect(
        viewport.trackSpaceAt(viewport.leadingCornerOf(rect))!.row,
        closeTo(2.2667, 1e-3),
      );
      final drag = setup.drag;
      final lift = rect.center;
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, lift),
      );
      expect(drag.currentTarget!.span, stored);
      drag.updateDrag(_global(tester, lift + const Offset(0.0, 8.0)));
      expect(drag.currentTarget!.span, stored);
      drag.updateDrag(_global(tester, lift + const Offset(0.0, 9.0)));
      expect(drag.currentTarget!.span, stored);
      drag.updateDrag(_global(tester, lift + const Offset(0.0, 10.0)));
      expect(_start(drag.currentTarget!.span), closeTo(2.5, 1e-9));
      drag.endDrag(cancel: true);
      // Restyled to zero, the resize in flight stops, so no ticker is
      // left running at the end of the test.
      controller.animationStyle = BoardAnimationStyle.disabled;
      await tester.pump();
    });
  });
}
