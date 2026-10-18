/// A drag resize's preview paints the rectangle its drop commits: the
/// dragged edge moves while the opposite edge holds, a laned item's
/// preview reads its prospective lane-axis track, a resize that lanes an
/// item holds a lane slot in the track it joins, and the preview follows
/// every track it resizes.
///
/// Rects are paint space in the board's frame, compared within 0.01 px
/// per edge unless a case says otherwise. Drag cases report through
/// `resizeItem`, so the committed rect is the one the drop gives.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_animation_coordinator.dart';
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

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

const BoardAnimationSpec _ms100 = BoardAnimationSpec(
  duration: Duration(milliseconds: 100),
  curve: Curves.linear,
);

const BoardAnimationSpec _ms200 = BoardAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

const BoardAnimationSpec _ms300 = BoardAnimationSpec(
  duration: Duration(milliseconds: 300),
  curve: Curves.linear,
);

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  required BoardAxisConfig rows,
  BoardAxisConfig? columns,
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: rows,
    columns: columns ?? BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Six 50 px rows, seven 40 px columns, no lanes.
BoardController<String, _Item> _uniform(
  WidgetTester tester, {
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  return _controller(
    tester,
    rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
    style: style,
  );
}

/// Content-sized rows carrying 18 px lanes under a 4 px padding.
BoardController<String, _Item> _contentLaned(
  WidgetTester tester, {
  int rowCount = 6,
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  return _controller(
    tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(rowCount, 80.0),
      laneExtent: 18.0,
      lanePadding: 4.0,
    ),
    style: style,
  );
}

Widget _board(
  BoardController<String, _Item> controller, {
  double width = 280.0,
  double height = 300.0,
  double Function(int row) cellHeight = _fiftyPx,
  ScrollableDetails verticalDetails = const ScrollableDetails.vertical(),
}) {
  return MaterialApp(
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
            cellBuilder: (context, cell) {
              return SizedBox(width: 40.0, height: cellHeight(cell.row));
            },
            itemBuilder: (context, item) {
              return Text(item.key);
            },
          ),
        ),
      ),
    ),
  );
}

double _fiftyPx(int row) {
  return 50.0;
}

double _tenPx(int row) {
  return 10.0;
}

double _twoPx(int row) {
  return 2.0;
}

double _twentyPx(int row) {
  return 20.0;
}

/// The cost pin's board: content-sized rows of 18 px lanes under a 4 px
/// padding and 20 px cells; `a` and `b` laned in row 1 on two lanes, `c`
/// unlaned on rows [2, 4), `f` unlaned and fractional, `g` laned and
/// fractional.
Future<(BoardController<String, _Item>, RenderBoardViewport<String>)>
_costBoard(WidgetTester tester) async {
  final controller = _controller(
    tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(60, 30.0),
      laneExtent: 18.0,
      lanePadding: 4.0,
    ),
  );
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 1, colStart: 0, colSpan: 3),
  );
  controller.addItem(
    const _Item("b"),
    const BoardSpan(rowStart: 1, colStart: 1, colSpan: 3),
  );
  controller.addItem(
    const _Item("c"),
    const BoardSpan(rowStart: 2, colStart: 4, rowSpan: 2),
  );
  controller.addItem(
    const _Item("f"),
    const BoardSpan(
      rowStart: 4,
      colStart: 5,
      rowFraction: 0.25,
      rowSpanFraction: 0.5,
    ),
  );
  controller.addItem(
    const _Item("g"),
    const BoardSpan(
      rowStart: 6,
      colStart: 0,
      rowFraction: 0.25,
      rowSpan: 0,
      rowSpanFraction: 0.5,
    ),
  );
  final viewport = await _mount(tester, controller, cellHeight: _twentyPx);
  return (controller, viewport);
}

/// Mounts [controller] and settles it, unmounting before the controller's
/// own teardown disposes it.
Future<RenderBoardViewport<String>> _mount(
  WidgetTester tester,
  BoardController<String, _Item> controller, {
  double width = 280.0,
  double height = 300.0,
  double Function(int row) cellHeight = _fiftyPx,
  ScrollableDetails verticalDetails = const ScrollableDetails.vertical(),
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpWidget(
    _board(
      controller,
      width: width,
      height: height,
      cellHeight: cellHeight,
      verticalDetails: verticalDetails,
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

/// A drag controller reporting a resize through `resizeItem`.
BoardDragController<String> _drag(
  WidgetTester tester,
  BoardController<String, _Item> controller, {
  BoardResizeEdges resizeEdges = BoardResizeEdges.none,
  BoardResizeEdges primaryResizeEdges = BoardResizeEdges.none,
  BoardSnap snap = const BoardSnap.track(),
  bool Function(String key, BoardSpan span)? canDropAt,
}) {
  final drag = BoardDragController<String>(
    boardController: controller,
    vsync: tester,
    config: BoardDragConfig<String>(
      onItemMoved: (key, span) {
        controller.moveItem(key, span);
      },
      onItemResized: (key, span) {
        controller.resizeItem(key, span);
      },
      canDropAt: canDropAt,
      snap: snap,
      resizeEdges: resizeEdges,
      primaryResizeEdges: primaryResizeEdges,
      autoScrollEdgeZone: 0.0,
    ),
  );
  addTearDown(drag.dispose);
  return drag;
}

void _expectRect(Rect? actual, Rect expected, {double epsilon = 0.01}) {
  expect(actual, isNotNull);
  expect(actual!.left, moreOrLessEquals(expected.left, epsilon: epsilon));
  expect(actual.top, moreOrLessEquals(expected.top, epsilon: epsilon));
  expect(actual.right, moreOrLessEquals(expected.right, epsilon: epsilon));
  expect(actual.bottom, moreOrLessEquals(expected.bottom, epsilon: epsilon));
}

void _expectSpan(
  BoardSpan? actual, {
  required double rowStart,
  required double rowEnd,
  required double colStart,
  required double colEnd,
}) {
  expect(actual, isNotNull);
  final span = actual!;
  expect(
    span.rowStart + span.rowFraction,
    moreOrLessEquals(rowStart, epsilon: 1e-9),
  );
  expect(
    span.rowStart + span.rowFraction + span.rowSpan + span.rowSpanFraction,
    moreOrLessEquals(rowEnd, epsilon: 1e-9),
  );
  expect(
    span.colStart + span.colFraction,
    moreOrLessEquals(colStart, epsilon: 1e-9),
  );
  expect(
    span.colStart + span.colFraction + span.colSpan + span.colSpanFraction,
    moreOrLessEquals(colEnd, epsilon: 1e-9),
  );
}

double _rowHeight(RenderBoardViewport<String> viewport, int row) {
  return viewport.rectOfCell(row, 0)!.height;
}

/// Lifts [key] by [edge] at [lift], moves to [to] and pumps one frame.
Future<void> _resizeTo(
  WidgetTester tester,
  BoardDragController<String> drag,
  RenderBoardViewport<String> viewport, {
  String key = "m",
  required BoardResizeEdges edge,
  required Axis axis,
  required Offset lift,
  required Offset to,
}) async {
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
  drag.updateDrag(_global(tester, to));
  await tester.pump();
}

/// Commits [drag] and pumps one frame; the committed rect of [key].
Future<Rect?> _commit(
  WidgetTester tester,
  BoardDragController<String> drag,
  RenderBoardViewport<String> viewport, {
  String key = "m",
}) async {
  drag.endDrag(cancel: false);
  await tester.pump();
  return viewport.paintedRectOfItem(key);
}

void main() {
  group("repros", () {
    testWidgets(
      "a leading-edge resize on a board with no lane axis previews its "
      "committed rect",
      (tester) async {
        Future<void> run(
          BoardSnap snap, {
          required double moveBy,
          required double rowStart,
          Rect? preview,
        }) async {
          final controller = _uniform(tester);
          controller.addItem(
            const _Item("m"),
            const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
          );
          final viewport = await _mount(tester, controller);
          final drag = _drag(
            tester,
            controller,
            primaryResizeEdges: BoardResizeEdges.leading,
            snap: snap,
          );
          await _resizeTo(
            tester,
            drag,
            viewport,
            edge: BoardResizeEdges.leading,
            axis: Axis.vertical,
            lift: const Offset(60.0, 105.0),
            to: Offset(60.0, 105.0 + moveBy),
          );
          // Setup sanity: the drag resolves the leading edge it moved.
          _expectSpan(
            drag.currentTarget?.span,
            rowStart: rowStart,
            rowEnd: 4.0,
            colStart: 1.0,
            colEnd: 2.0,
          );
          final painted = viewport.paintedRectOfItem("m");
          final committed = await _commit(tester, drag, viewport);
          final expected =
              preview ?? Rect.fromLTRB(40.0, 50.0 * rowStart, 80.0, 200.0);
          // TARGET: the preview is the committed rect.
          _expectRect(painted, expected);
          _expectRect(committed, expected);
          await tester.pumpWidget(const SizedBox.shrink());
        }

        await run(
          const BoardSnap.track(),
          moveBy: 50.0,
          rowStart: 3.0,
          preview: const Rect.fromLTRB(40.0, 150.0, 80.0, 200.0),
        );
        await run(
          const BoardSnap.fraction(0.5),
          moveBy: 25.0,
          rowStart: 2.5,
          preview: const Rect.fromLTRB(40.0, 125.0, 80.0, 200.0),
        );
        await run(const BoardSnap.free(), moveBy: 30.0, rowStart: 2.6);
      },
    );

    testWidgets(
      "a leading-edge resize on the span axis previews its committed rect",
      (tester) async {
        final controller = _uniform(tester);
        controller.addItem(
          const _Item("m"),
          const BoardSpan(rowStart: 2, colStart: 2, colSpan: 2),
        );
        final viewport = await _mount(tester, controller);
        final drag = _drag(
          tester,
          controller,
          resizeEdges: BoardResizeEdges.leading,
        );
        await _resizeTo(
          tester,
          drag,
          viewport,
          edge: BoardResizeEdges.leading,
          axis: Axis.horizontal,
          lift: const Offset(85.0, 125.0),
          to: const Offset(45.0, 125.0),
        );
        // Setup sanity: columns [1, 4).
        _expectSpan(
          drag.currentTarget?.span,
          rowStart: 2.0,
          rowEnd: 3.0,
          colStart: 1.0,
          colEnd: 4.0,
        );
        final painted = viewport.paintedRectOfItem("m");
        final committed = await _commit(tester, drag, viewport);
        const expected = Rect.fromLTRB(40.0, 100.0, 160.0, 150.0);
        // TARGET: the leading edge moved and the trailing one held.
        _expectRect(painted, expected);
        _expectRect(committed, expected);
      },
    );

    testWidgets(
      "a leading-edge resize of a laned item on a fixed lane axis previews "
      "its committed rect",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(
            axis: UniformAxis(6, 50.0),
            laneExtent: 20.0,
            lanePadding: 4.0,
          ),
        );
        controller.addItem(
          const _Item("m"),
          const BoardSpan(rowStart: 2, colStart: 1),
        );
        final viewport = await _mount(tester, controller);
        // Setup sanity: `m` is laned and rests under the padding.
        _expectRect(
          viewport.paintedRectOfItem("m"),
          const Rect.fromLTRB(40.0, 104.0, 80.0, 150.0),
        );
        final drag = _drag(
          tester,
          controller,
          primaryResizeEdges: BoardResizeEdges.leading,
        );
        await _resizeTo(
          tester,
          drag,
          viewport,
          edge: BoardResizeEdges.leading,
          axis: Axis.vertical,
          lift: const Offset(60.0, 106.0),
          to: const Offset(60.0, 56.0),
        );
        // Setup sanity: rows [1, 3).
        _expectSpan(
          drag.currentTarget?.span,
          rowStart: 1.0,
          rowEnd: 3.0,
          colStart: 1.0,
          colEnd: 2.0,
        );
        final painted = viewport.paintedRectOfItem("m");
        final committed = await _commit(tester, drag, viewport);
        const expected = Rect.fromLTRB(40.0, 50.0, 80.0, 150.0);
        // TARGET: the preview is the committed, unlaned rect.
        _expectRect(painted, expected);
        _expectRect(committed, expected);
      },
    );

    testWidgets(
      "a leading-edge resize under AxisDirection.up previews its committed "
      "rect",
      (tester) async {
        final controller = _uniform(tester);
        controller.addItem(
          const _Item("m"),
          const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
        );
        final viewport = await _mount(
          tester,
          controller,
          verticalDetails: const ScrollableDetails(direction: AxisDirection.up),
        );
        // Setup sanity: the reversed rows paint `m` at the same rect.
        _expectRect(
          viewport.paintedRectOfItem("m"),
          const Rect.fromLTRB(40.0, 100.0, 80.0, 200.0),
        );
        final drag = _drag(
          tester,
          controller,
          primaryResizeEdges: BoardResizeEdges.leading,
        );
        await _resizeTo(
          tester,
          drag,
          viewport,
          edge: BoardResizeEdges.leading,
          axis: Axis.vertical,
          lift: const Offset(60.0, 195.0),
          to: const Offset(60.0, 145.0),
        );
        // Setup sanity: rows [3, 4).
        _expectSpan(
          drag.currentTarget?.span,
          rowStart: 3.0,
          rowEnd: 4.0,
          colStart: 1.0,
          colEnd: 2.0,
        );
        final painted = viewport.paintedRectOfItem("m");
        final committed = await _commit(tester, drag, viewport);
        const expected = Rect.fromLTRB(40.0, 100.0, 80.0, 150.0);
        // TARGET: the content-leading edge, the painted bottom, moved.
        _expectRect(painted, expected);
        _expectRect(committed, expected);
      },
    );

    testWidgets(
      "a leading-edge resize holds its far edge through the preview and "
      "releases in place",
      (tester) async {
        final controller = _uniform(tester, style: const BoardAnimationStyle());
        controller.addItem(
          const _Item("m"),
          const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
        );
        final viewport = await _mount(tester, controller);
        final drag = _drag(
          tester,
          controller,
          primaryResizeEdges: BoardResizeEdges.leading,
        );
        await _resizeTo(
          tester,
          drag,
          viewport,
          edge: BoardResizeEdges.leading,
          axis: Axis.vertical,
          lift: const Offset(60.0, 105.0),
          to: const Offset(60.0, 155.0),
        );
        // Setup sanity: rows [3, 4), and the preview stands at once, its
        // lead and extent moved together with nothing in motion.
        _expectSpan(
          drag.currentTarget?.span,
          rowStart: 3.0,
          rowEnd: 4.0,
          colStart: 1.0,
          colEnd: 2.0,
        );
        expect(
          viewport.paintedRectOfItem("m")!.top,
          moreOrLessEquals(150.0, epsilon: 0.01),
        );
        expect(controller.anim.hasMakeRoomMotion, isFalse);
        // TARGET a: the far edge holds on every frame of the preview.
        expect(
          viewport.paintedRectOfItem("m")!.bottom,
          moreOrLessEquals(200.0, epsilon: 0.01),
        );
        for (var i = 0; i < 19; i++) {
          await tester.pump(_frame);
          expect(
            viewport.paintedRectOfItem("m")!.bottom,
            moreOrLessEquals(200.0, epsilon: 0.01),
          );
        }
        drag.endDrag(cancel: false);
        // TARGET b: the release moves the item nowhere.
        for (var i = 0; i < 40; i++) {
          await tester.pump(_frame);
          _expectRect(
            viewport.paintedRectOfItem("m"),
            const Rect.fromLTRB(40.0, 150.0, 80.0, 200.0),
          );
        }
      },
    );

    testWidgets("a resize that lanes an item into another track previews that "
        "track's slice", (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(
          axis: ExplicitAxis(<double>[100.0, 200.0, 50.0, 50.0]),
          laneExtent: 20.0,
        ),
        columns: BoardAxisConfig(axis: UniformAxis(4, 40.0)),
      );
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 2),
      );
      final viewport = await _mount(
        tester,
        controller,
        width: 160.0,
        height: 400.0,
      );
      // Setup sanity: rows 0 and 1, unlaned.
      _expectRect(
        viewport.paintedRectOfItem("m"),
        const Rect.fromLTRB(0.0, 0.0, 40.0, 300.0),
      );
      const prospective = BoardSpan(rowStart: 1, colStart: 0);
      controller.previewMakeRoomGap(draggedKey: "m", prospective: prospective);
      await tester.pump();
      final painted = viewport.paintedRectOfItem("m");
      controller.releaseMakeRoomPreview(duration: Duration.zero);
      controller.resizeItem("m", prospective);
      await tester.pump();
      final committed = viewport.paintedRectOfItem("m");
      const expected = Rect.fromLTRB(0.0, 100.0, 40.0, 300.0);
      // TARGET: row 1's slice, at row 1.
      _expectRect(painted, expected);
      _expectRect(committed, expected);
    });

    testWidgets(
      "a resize that lanes an item holds a slot in the track it joins",
      (tester) async {
        Future<void> run(BoardAnimationStyle style, {required bool off}) async {
          final controller = _contentLaned(tester, style: style);
          controller.addItem(
            const _Item("a"),
            const BoardSpan(rowStart: 1, colStart: 0, colSpan: 4),
          );
          controller.addItem(
            const _Item("m"),
            const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 2, colSpan: 2),
          );
          final viewport = await _mount(tester, controller, cellHeight: _tenPx);
          // Setup sanity: row 1 holds one lane, and `m` is unlaned.
          expect(_rowHeight(viewport, 1), 22.0);
          expect(controller.isLanedId(controller.idOfKey("m")), isFalse);
          const prospective = BoardSpan(rowStart: 1, colStart: 0, colSpan: 2);
          controller.previewMakeRoomGap(
            draggedKey: "m",
            prospective: prospective,
          );
          await tester.pump();
          await tester.pump();
          const expected = Rect.fromLTRB(0.0, 32.0, 80.0, 50.0);
          if (off) {
            // TARGET (off arm): the slot lands at once, with no
            // trackResize.
            expect(_rowHeight(viewport, 1), 40.0);
            _expectRect(viewport.paintedRectOfItem("m"), expected);
            expect(controller.anim.hasActiveTrackResize, isFalse);
            await tester.pumpWidget(const SizedBox.shrink());
            return;
          }
          // TARGET a: the preview holds a lane slot in row 1.
          expect(controller.anim.makeRoomSlotsOn(1).toList(), hasLength(1));
          // TARGET b: row 1 holds both lanes during the preview.
          expect(_rowHeight(viewport, 1), 40.0);
          // TARGET c: the preview paints where the commit lands.
          final painted = viewport.paintedRectOfItem("m");
          _expectRect(painted, expected);
          controller.releaseMakeRoomPreview(duration: Duration.zero);
          controller.resizeItem("m", prospective);
          await tester.pump();
          _expectRect(viewport.paintedRectOfItem("m"), expected);
          await tester.pumpWidget(const SizedBox.shrink());
        }

        await run(BoardAnimationStyle.disabled, off: false);
        await run(
          const BoardAnimationStyle(makeRoom: _zero, trackResize: _ms200),
          off: true,
        );
      },
    );

    testWidgets("a resize preview follows the track it vacates", (
      tester,
    ) async {
      final controller = _contentLaned(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 4),
      );
      controller.addItem(
        const _Item("d"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 5),
      );
      final viewport = await _mount(tester, controller, cellHeight: _tenPx);
      // Setup sanity: both laned in row 0, which holds two lanes.
      expect(_rowHeight(viewport, 0), 40.0);
      const prospective = BoardSpan(
        rowStart: 0,
        colStart: 0,
        rowSpan: 2,
        colSpan: 5,
      );
      controller.previewMakeRoomGap(draggedKey: "d", prospective: prospective);
      const expected = Rect.fromLTRB(0.0, 0.0, 200.0, 32.0);
      for (var i = 0; i < 3; i++) {
        await tester.pump();
        // TARGET a: row 0 sheds `d`'s lane as the commit will.
        expect(_rowHeight(viewport, 0), 22.0);
        // TARGET b: `d` spans the two rows as they paint.
        _expectRect(viewport.paintedRectOfItem("d"), expected);
      }
      controller.releaseMakeRoomPreview(duration: Duration.zero);
      controller.resizeItem("d", prospective);
      await tester.pump();
      _expectRect(viewport.paintedRectOfItem("d"), expected);
    });

    testWidgets(
      "a leading-edge resize of a pinned item previews its committed rect",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(12, 50.0), frozenStart: 2),
        );
        controller.addItem(
          const _Item("m"),
          const BoardSpan(rowStart: 0, colStart: 1, rowSpan: 2),
        );
        final viewport = await _mount(tester, controller);
        controller.jumpToCell(4, 0);
        await tester.pump();
        // Setup sanity: the lattice scrolled under the band, and `m` is
        // pinned in it.
        expect(viewport.rectOfCell(4, 0)!.top, 100.0);
        final id = controller.idOfKey("m");
        expect(controller.pinOfId(id, Axis.vertical), BoardPin.leading);
        final drag = _drag(
          tester,
          controller,
          primaryResizeEdges: BoardResizeEdges.leading,
        );
        await _resizeTo(
          tester,
          drag,
          viewport,
          edge: BoardResizeEdges.leading,
          axis: Axis.vertical,
          lift: const Offset(60.0, 5.0),
          to: const Offset(60.0, 55.0),
        );
        // Setup sanity: rows [1, 2).
        _expectSpan(
          drag.currentTarget?.span,
          rowStart: 1.0,
          rowEnd: 2.0,
          colStart: 1.0,
          colEnd: 2.0,
        );
        final painted = viewport.paintedRectOfItem("m");
        final committed = await _commit(tester, drag, viewport);
        const expected = Rect.fromLTRB(40.0, 50.0, 80.0, 100.0);
        // TARGET: the pinned preview is the committed rect.
        _expectRect(painted, expected);
        _expectRect(committed, expected);
        expect(controller.pinOfId(id, Axis.vertical), BoardPin.leading);
      },
    );

    testWidgets(
      "a resize preview under an off makeRoom family or a zero duration "
      "lands at once",
      (tester) async {
        const expected = Rect.fromLTRB(40.0, 150.0, 80.0, 200.0);
        {
          final controller = _uniform(
            tester,
            style: const BoardAnimationStyle(
              itemSlide: _ms300,
              makeRoom: _zero,
            ),
          );
          controller.addItem(
            const _Item("m"),
            const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
          );
          final viewport = await _mount(tester, controller);
          final drag = _drag(
            tester,
            controller,
            primaryResizeEdges: BoardResizeEdges.leading,
          );
          await _resizeTo(
            tester,
            drag,
            viewport,
            edge: BoardResizeEdges.leading,
            axis: Axis.vertical,
            lift: const Offset(60.0, 105.0),
            to: const Offset(60.0, 155.0),
          );
          // Setup sanity: rows [3, 4).
          _expectSpan(
            drag.currentTarget?.span,
            rowStart: 3.0,
            rowEnd: 4.0,
            colStart: 1.0,
            colEnd: 2.0,
          );
          // TARGET a: the preview landed on the first frame.
          _expectRect(viewport.paintedRectOfItem("m"), expected);
          expect(controller.anim.hasMakeRoomMotion, isFalse);
          drag.endDrag(cancel: true);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        {
          final controller = _uniform(
            tester,
            style: const BoardAnimationStyle(),
          );
          controller.addItem(
            const _Item("m"),
            const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
          );
          final viewport = await _mount(tester, controller);
          controller.previewMakeRoomGap(
            draggedKey: "m",
            prospective: const BoardSpan(rowStart: 3, colStart: 1),
            duration: Duration.zero,
          );
          await tester.pump();
          // TARGET b: a zero per-call duration lands it at once too.
          _expectRect(viewport.paintedRectOfItem("m"), expected);
          expect(controller.anim.hasMakeRoomMotion, isFalse);
        }
      },
    );

    testWidgets(
      "a resize's slot closes on release, on a re-target that stops laning "
      "it, and under another session's snapped install",
      (tester) async {
        const joins = BoardSpan(rowStart: 1, colStart: 0, colSpan: 2);
        const stored = BoardSpan(
          rowStart: 0,
          colStart: 0,
          rowSpan: 2,
          colSpan: 2,
        );
        Future<BoardController<String, _Item>> board(
          BoardAnimationStyle style,
        ) async {
          final controller = _contentLaned(tester, style: style);
          controller.addItem(
            const _Item("a"),
            const BoardSpan(rowStart: 1, colStart: 0, colSpan: 4),
          );
          controller.addItem(const _Item("m"), stored);
          await _mount(tester, controller, cellHeight: _tenPx);
          return controller;
        }

        {
          final controller = await board(BoardAnimationStyle.disabled);
          final mId = controller.idOfKey("m");
          controller.previewMakeRoomGap(draggedKey: "m", prospective: joins);
          await tester.pump();
          // TARGET a: the resize holds a slot, keyed by its own item.
          expect(controller.anim.makeRoomSlotsOn(1).toList(), hasLength(1));
          expect(controller.debugMakeRoomLiftedId, mId);
          controller.previewMakeRoomGap(draggedKey: "m", prospective: stored);
          await tester.pump();
          // TARGET b: a re-target that stops laning it closes the slot.
          expect(controller.anim.makeRoomSlotsOn(1).toList(), isEmpty);
          expect(controller.debugMakeRoomLiftedId, isNull);
          controller.previewMakeRoomGap(draggedKey: "m", prospective: joins);
          await tester.pump();
          // Setup sanity: the slot is back.
          expect(controller.anim.makeRoomSlotsOn(1).toList(), hasLength(1));
          controller.releaseMakeRoomPreview();
          await tester.pump();
          // TARGET c: the release closes it.
          expect(controller.anim.makeRoomSlotsOn(1).toList(), isEmpty);
          expect(controller.debugMakeRoomLiftedId, isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        {
          final controller = await board(
            const BoardAnimationStyle(
              trackResize: _zero,
              itemSlide: _zero,
              makeRoom: _ms200,
            ),
          );
          controller.previewMakeRoomGap(draggedKey: "m", prospective: joins);
          await tester.pumpAndSettle(_frame);
          // Setup sanity: the slot settled open.
          expect(controller.anim.makeRoomSlotsOn(1).toList(), hasLength(1));
          controller.releaseMakeRoomPreview();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          // Setup sanity: the slot is closing.
          final closing = controller.anim.makeRoomSlotsOn(1).toList();
          expect(closing, hasLength(1));
          expect(closing.single.value, greaterThan(0.0));
          controller.previewMakeRoomGap(
            draggedKey: "a",
            prospective: const BoardSpan(rowStart: 1, colStart: 0, colSpan: 4),
            duration: Duration.zero,
          );
          // TARGET d: another session's snapped install drops it.
          expect(controller.anim.makeRoomSlotsOn(1).toList(), isEmpty);
          expect(controller.debugMakeRoomLiftedId, isNull);
        }
      },
    );

    testWidgets(
      "a resize committed mid-preview into a track it joins steps nothing "
      "at release",
      (tester) async {
        final controller = _contentLaned(
          tester,
          style: const BoardAnimationStyle(
            trackResize: _ms200,
            itemSlide: _ms200,
            makeRoom: _ms200,
            itemEnterExit: _zero,
          ),
        );
        controller.addItem(
          const _Item("a"),
          const BoardSpan(rowStart: 1, colStart: 0, colSpan: 4),
        );
        controller.addItem(
          const _Item("m"),
          const BoardSpan(rowStart: 1, colStart: 0, rowSpan: 2, colSpan: 2),
        );
        final viewport = await _mount(tester, controller, cellHeight: _tenPx);
        final drag = _drag(
          tester,
          controller,
          primaryResizeEdges: BoardResizeEdges.trailing,
        );
        await _resizeTo(
          tester,
          drag,
          viewport,
          edge: BoardResizeEdges.trailing,
          axis: Axis.vertical,
          lift: const Offset(40.0, 40.0),
          to: const Offset(40.0, 20.0),
        );
        // Setup sanity: rows [1, 2).
        _expectSpan(
          drag.currentTarget?.span,
          rowStart: 1.0,
          rowEnd: 2.0,
          colStart: 0.0,
          colEnd: 2.0,
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(_frame);
        }
        await tester.pump(const Duration(milliseconds: 4));
        // Setup sanity: the target held while row 1 moved.
        _expectSpan(
          drag.currentTarget?.span,
          rowStart: 1.0,
          rowEnd: 2.0,
          colStart: 0.0,
          colEnd: 2.0,
        );
        final row1 = _rowHeight(viewport, 1);
        final before = viewport.paintedRectOfItem("m")!;
        drag.endDrag(cancel: false);
        await tester.pump();
        // TARGET a: row 1 and `m` continue from where they painted.
        expect(_rowHeight(viewport, 1), moreOrLessEquals(row1, epsilon: 0.5));
        _expectRect(viewport.paintedRectOfItem("m"), before, epsilon: 0.5);
        await tester.pumpAndSettle(_frame);
        // TARGET b: they land where the commit puts them.
        expect(_rowHeight(viewport, 1), 40.0);
        _expectRect(
          viewport.paintedRectOfItem("m"),
          const Rect.fromLTRB(0.0, 32.0, 80.0, 50.0),
        );
      },
    );

    testWidgets("a resize slot above the view keeps the scroll anchor still", (
      tester,
    ) async {
      final controller = _contentLaned(tester, rowCount: 30);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 1, colStart: 0, colSpan: 4),
      );
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 2, colSpan: 2),
      );
      final viewport = await _mount(
        tester,
        controller,
        height: 100.0,
        cellHeight: _tenPx,
      );
      controller.jumpToCell(10, 0);
      await tester.pump();
      // Setup sanity: row 1 is measured at one lane and lies above the
      // view.
      expect(_rowHeight(viewport, 1), 22.0);
      expect(viewport.rectOfCell(1, 0)!.bottom, lessThan(0.0));
      final row12 = viewport.rectOfCell(12, 0)!.top;
      controller.previewMakeRoomGap(
        draggedKey: "m",
        prospective: const BoardSpan(rowStart: 1, colStart: 0, colSpan: 2),
      );
      await tester.pump();
      await tester.pump();
      // TARGET a: the slot grew row 1.
      expect(_rowHeight(viewport, 1), 40.0);
      // TARGET b: the anchor held still.
      expect(viewport.rectOfCell(12, 0)!.top, row12);
    });

    testWidgets(
      "a resize that de-lanes its track's only laned item previews the "
      "track the commit gives it",
      (tester) async {
        const prospective = BoardSpan(
          rowStart: 0,
          colStart: 0,
          rowSpan: 2,
          colSpan: 5,
        );
        const expected = Rect.fromLTRB(0.0, 0.0, 200.0, 4.0);
        Future<(BoardController<String, _Item>, RenderBoardViewport<String>)>
        board(BoardAnimationStyle style) async {
          final controller = _contentLaned(tester, style: style);
          controller.addItem(
            const _Item("d"),
            const BoardSpan(rowStart: 0, colStart: 0, colSpan: 5),
          );
          final viewport = await _mount(tester, controller, cellHeight: _twoPx);
          // Setup sanity: row 0 holds `d`'s lane.
          expect(_rowHeight(viewport, 0), 22.0);
          return (controller, viewport);
        }

        {
          final (controller, viewport) = await board(
            BoardAnimationStyle.disabled,
          );
          controller.previewMakeRoomGap(
            draggedKey: "d",
            prospective: prospective,
          );
          await tester.pump();
          // TARGET a: row 0 sheds the lane and its padding.
          expect(_rowHeight(viewport, 0), 2.0);
          _expectRect(viewport.paintedRectOfItem("d"), expected);
          controller.releaseMakeRoomPreview(duration: Duration.zero);
          controller.resizeItem("d", prospective);
          await tester.pump();
          expect(_rowHeight(viewport, 0), 2.0);
          _expectRect(viewport.paintedRectOfItem("d"), expected);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        {
          final (controller, viewport) = await board(
            const BoardAnimationStyle(makeRoom: _zero, trackResize: _ms200),
          );
          controller.previewMakeRoomGap(
            draggedKey: "d",
            prospective: prospective,
          );
          await tester.pump();
          // TARGET b (off arm): the vacate lands at once, with no
          // trackResize.
          expect(_rowHeight(viewport, 0), 2.0);
          _expectRect(viewport.paintedRectOfItem("d"), expected);
          expect(controller.anim.hasActiveTrackResize, isFalse);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        {
          final (controller, viewport) = await board(
            const BoardAnimationStyle(
              itemSlide: _ms200,
              trackResize: _ms200,
              itemEnterExit: _zero,
            ),
          );
          controller.previewMakeRoomGap(
            draggedKey: "d",
            prospective: prospective,
          );
          // TARGET c (live arm): the row ramps down with the vacate.
          for (var t = 0; t <= 208; t += 16) {
            await tester.pump(t == 0 ? Duration.zero : _frame);
            final expected = 22.0 * (1.0 - t / 200.0);
            expect(
              _rowHeight(viewport, 0),
              moreOrLessEquals(expected < 2.0 ? 2.0 : expected, epsilon: 0.5),
            );
          }
          await tester.pumpAndSettle(_frame);
          controller.releaseMakeRoomPreview();
          for (var t = 0; t <= 208; t += 16) {
            await tester.pump(t == 0 ? Duration.zero : _frame);
            final expected = 22.0 * t / 200.0;
            expect(
              _rowHeight(viewport, 0),
              moreOrLessEquals(
                expected < 2.0 ? 2.0 : (expected > 22.0 ? 22.0 : expected),
                epsilon: 0.5,
              ),
            );
          }
        }
      },
    );

    testWidgets(
      "a laned resize that changes its lane span steps nothing at release",
      (tester) async {
        final controller = _contentLaned(
          tester,
          style: const BoardAnimationStyle(
            itemSlide: _ms200,
            trackResize: _ms200,
            itemEnterExit: _zero,
          ),
        );
        controller.addItem(
          const _Item("v"),
          const BoardSpan(rowStart: 0, colStart: 0, colSpan: 6),
        );
        controller.addItem(
          const _Item("z"),
          const BoardSpan(rowStart: 0, colStart: 0, colSpan: 4),
        );
        controller.addItem(
          const _Item("w"),
          const BoardSpan(rowStart: 0, colStart: 0, colSpan: 4),
        );
        controller.addItem(
          const _Item("m"),
          const BoardSpan(rowStart: 0, colStart: 4, colSpan: 2),
        );
        final viewport = await _mount(tester, controller, cellHeight: _tenPx);
        // Setup sanity: `m` on lane 1 with lane span 2, row 0 three lanes.
        _expectRect(
          viewport.paintedRectOfItem("m"),
          const Rect.fromLTRB(160.0, 22.0, 240.0, 58.0),
        );
        expect(_rowHeight(viewport, 0), 58.0);
        final drag = _drag(
          tester,
          controller,
          resizeEdges: BoardResizeEdges.leading,
        );
        await _resizeTo(
          tester,
          drag,
          viewport,
          edge: BoardResizeEdges.leading,
          axis: Axis.horizontal,
          lift: const Offset(165.0, 40.0),
          to: const Offset(125.0, 40.0),
        );
        // Setup sanity: columns [3, 6).
        _expectSpan(
          drag.currentTarget?.span,
          rowStart: 0.0,
          rowEnd: 1.0,
          colStart: 3.0,
          colEnd: 6.0,
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(_frame);
        }
        await tester.pump(const Duration(milliseconds: 4));
        // Setup sanity: half way, row 0 holds half of `m`'s band change.
        expect(_rowHeight(viewport, 0), moreOrLessEquals(67.0, epsilon: 0.5));
        final row0 = _rowHeight(viewport, 0);
        final before = viewport.paintedRectOfItem("m")!;
        drag.endDrag(cancel: false);
        await tester.pump();
        // TARGET a: row 0 and `m` continue from where they painted.
        expect(_rowHeight(viewport, 0), moreOrLessEquals(row0, epsilon: 0.5));
        _expectRect(viewport.paintedRectOfItem("m"), before, epsilon: 0.5);
        await tester.pumpAndSettle(_frame);
        // TARGET b: they land where the commit puts them.
        expect(_rowHeight(viewport, 0), 76.0);
        _expectRect(
          viewport.paintedRectOfItem("m"),
          const Rect.fromLTRB(120.0, 58.0, 240.0, 76.0),
        );
      },
    );

    testWidgets(
      "a released, cancelled or refused leading-edge resize continues from "
      "where it paints",
      (tester) async {
        Future<
          (
            BoardController<String, _Item>,
            RenderBoardViewport<String>,
            BoardDragController<String>,
          )
        >
        preview({bool Function(String key, BoardSpan span)? canDropAt}) async {
          final controller = _uniform(
            tester,
            style: const BoardAnimationStyle(),
          );
          controller.addItem(
            const _Item("m"),
            const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
          );
          final viewport = await _mount(tester, controller);
          final drag = _drag(
            tester,
            controller,
            primaryResizeEdges: BoardResizeEdges.leading,
            canDropAt: canDropAt,
          );
          await _resizeTo(
            tester,
            drag,
            viewport,
            edge: BoardResizeEdges.leading,
            axis: Axis.vertical,
            lift: const Offset(60.0, 105.0),
            to: const Offset(60.0, 155.0),
          );
          // Setup sanity: rows [3, 4), standing at once.
          _expectSpan(
            drag.currentTarget?.span,
            rowStart: 3.0,
            rowEnd: 4.0,
            colStart: 1.0,
            colEnd: 2.0,
          );
          for (var i = 0; i < 5; i++) {
            await tester.pump(_frame);
          }
          _expectRect(
            viewport.paintedRectOfItem("m"),
            const Rect.fromLTRB(40.0, 150.0, 80.0, 200.0),
          );
          expect(controller.anim.hasMakeRoomMotion, isFalse);
          return (controller, viewport, drag);
        }

        Future<void> closes(
          BoardController<String, _Item> controller,
          RenderBoardViewport<String> viewport,
          Rect before,
          Rect end,
        ) async {
          await tester.pump();
          // TARGET a: the frame after the release paints where the one
          // before it did.
          _expectRect(viewport.paintedRectOfItem("m"), before);
          for (var i = 0; i < 40; i++) {
            await tester.pump(_frame);
            // TARGET b: the far edge holds through the close.
            expect(
              viewport.paintedRectOfItem("m")!.bottom,
              moreOrLessEquals(200.0, epsilon: 0.01),
            );
          }
          // TARGET c: it ends where it rests.
          _expectRect(viewport.paintedRectOfItem("m"), end);
        }

        {
          final (controller, viewport, drag) = await preview();
          final before = viewport.paintedRectOfItem("m")!;
          drag.endDrag(cancel: false);
          await closes(
            controller,
            viewport,
            before,
            const Rect.fromLTRB(40.0, 150.0, 80.0, 200.0),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        }
        {
          final (controller, viewport, drag) = await preview();
          final before = viewport.paintedRectOfItem("m")!;
          drag.endDrag(cancel: true);
          await closes(
            controller,
            viewport,
            before,
            const Rect.fromLTRB(40.0, 100.0, 80.0, 200.0),
          );
          // TARGET d: nothing is left held.
          expect(controller.makeRoomHeldKeys, isEmpty);
          expect(controller.anim.hasActiveOffsets, isFalse);
          expect(controller.anim.hasMakeRoomMotion, isFalse);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        {
          final (controller, viewport, drag) = await preview(
            canDropAt: (key, span) {
              return !(span.rowStart == 1 && span.rowSpan == 3);
            },
          );
          final before = viewport.paintedRectOfItem("m")!;
          drag.updateDrag(_global(tester, const Offset(60.0, 55.0)));
          // Setup sanity: the hover is refused.
          expect(drag.currentTarget, isNull);
          await closes(
            controller,
            viewport,
            before,
            const Rect.fromLTRB(40.0, 100.0, 80.0, 200.0),
          );
          // TARGET e: nothing is left held while the drag stands.
          expect(drag.draggedKey, "m");
          expect(controller.makeRoomHeldKeys, isEmpty);
          expect(controller.anim.hasActiveOffsets, isFalse);
          expect(controller.anim.hasMakeRoomMotion, isFalse);
          drag.endDrag(cancel: true);
        }
      },
    );

    testWidgets(
      "a re-lane of the stored bucket under a standing resize preview "
      "neither steps the track nor strands an entry",
      (tester) async {
        Future<(BoardController<String, _Item>, RenderBoardViewport<String>)>
        board(
          BoardAnimationStyle style, {
          required BoardSpan m,
          bool withX = true,
        }) async {
          final controller = _contentLaned(tester, style: style);
          if (withX) {
            controller.addItem(
              const _Item("x"),
              const BoardSpan(rowStart: 1, colStart: 0, colSpan: 4),
            );
          }
          controller.addItem(const _Item("m"), m);
          final viewport = await _mount(tester, controller, cellHeight: _tenPx);
          return (controller, viewport);
        }

        const style = BoardAnimationStyle(
          itemSlide: _ms100,
          itemEnterExit: _ms100,
          trackResize: _zero,
        );
        {
          // The drag arm.
          final (controller, viewport) = await board(
            style,
            m: const BoardSpan(rowStart: 1, colStart: 2, colSpan: 2),
          );
          // Setup sanity: `m` on lane 1, row 1 two lanes.
          _expectRect(
            viewport.paintedRectOfItem("m"),
            const Rect.fromLTRB(80.0, 32.0, 160.0, 50.0),
          );
          expect(_rowHeight(viewport, 1), 40.0);
          final drag = _drag(
            tester,
            controller,
            resizeEdges: BoardResizeEdges.trailing,
          );
          await _resizeTo(
            tester,
            drag,
            viewport,
            edge: BoardResizeEdges.trailing,
            axis: Axis.horizontal,
            lift: const Offset(155.0, 41.0),
            to: const Offset(195.0, 41.0),
          );
          _expectSpan(
            drag.currentTarget?.span,
            rowStart: 1.0,
            rowEnd: 2.0,
            colStart: 2.0,
            colEnd: 5.0,
          );
          await tester.pumpAndSettle(_frame);
          controller.removeItem("x");
          var row1 = _rowHeight(viewport, 1);
          var top = viewport.paintedRectOfItem("m")!.top;
          var frames = 0;
          do {
            await tester.pump(_frame);
            frames += 1;
            // TARGET a: neither row 1 nor `m` steps, through the exit, its
            // settle and the close the re-resolve starts.
            expect(
              (_rowHeight(viewport, 1) - row1).abs(),
              lessThanOrEqualTo(3.0),
            );
            expect(
              (viewport.paintedRectOfItem("m")!.top - top).abs(),
              lessThanOrEqualTo(3.0),
            );
            row1 = _rowHeight(viewport, 1);
            top = viewport.paintedRectOfItem("m")!.top;
          } while (tester.binding.hasScheduledFrame && frames < 60);
          // Setup sanity: the exit settled, and row 1 closed to one lane.
          expect(controller.contains("x"), isFalse);
          expect(_rowHeight(viewport, 1), 22.0);
          drag.endDrag(cancel: true);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        {
          // The mid-clock arm.
          final (controller, viewport) = await board(
            const BoardAnimationStyle(
              makeRoom: _ms300,
              itemEnterExit: _ms100,
              trackResize: _zero,
            ),
            m: const BoardSpan(rowStart: 1, colStart: 3, colSpan: 2),
          );
          // Setup sanity: `m` on lane 1.
          _expectRect(
            viewport.paintedRectOfItem("m"),
            const Rect.fromLTRB(120.0, 32.0, 200.0, 50.0),
          );
          final drag = _drag(
            tester,
            controller,
            resizeEdges: BoardResizeEdges.leading,
          );
          expect(
            drag.startDrag(
              key: "m",
              renderPort: viewport,
              pointerGlobal: _global(tester, const Offset(125.0, 41.0)),
              edge: BoardResizeEdges.leading,
              axis: Axis.horizontal,
            ),
            isTrue,
          );
          drag.updateDrag(_global(tester, const Offset(165.0, 41.0)));
          _expectSpan(
            drag.currentTarget?.span,
            rowStart: 1.0,
            rowEnd: 2.0,
            colStart: 4.0,
            colEnd: 5.0,
          );
          controller.removeItem("x");
          await tester.pump();
          var top = viewport.paintedRectOfItem("m")!.top;
          var frames = 0;
          do {
            await tester.pump(_frame);
            frames += 1;
            // TARGET b: `m` does not step as its stored lane drops under
            // its lead.
            expect(
              (viewport.paintedRectOfItem("m")!.top - top).abs(),
              lessThanOrEqualTo(3.0),
            );
            top = viewport.paintedRectOfItem("m")!.top;
          } while (tester.binding.hasScheduledFrame && frames < 60);
          // Setup sanity: the exit settled and `m` re-laned under the
          // preview.
          expect(controller.contains("x"), isFalse);
          expect(controller.laneOfId(controller.idOfKey("m")), 0);
          drag.endDrag(cancel: true);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        {
          // The direct arm.
          final (controller, viewport) = await board(
            style,
            m: const BoardSpan(rowStart: 1, colStart: 2, colSpan: 2),
          );
          controller.previewMakeRoomGap(
            draggedKey: "m",
            prospective: const BoardSpan(rowStart: 1, colStart: 2, colSpan: 2),
          );
          await tester.pumpAndSettle(_frame);
          controller.removeItem("x");
          await tester.pumpAndSettle(_frame);
          // Setup sanity: `m` re-laned to lane 0 and is held at its
          // preview.
          expect(controller.laneOfId(controller.idOfKey("m")), 0);
          expect(controller.anim.hasActiveOffsets, isTrue);
          controller.addItem(
            const _Item("y"),
            const BoardSpan(rowStart: 1, colStart: 1, colSpan: 3),
          );
          await tester.pumpAndSettle(_frame);
          // Setup sanity: `m` is back on lane 1.
          expect(controller.laneOfId(controller.idOfKey("m")), 1);
          // TARGET c: no entry is left standing.
          expect(controller.anim.hasActiveOffsets, isFalse);
          controller.releaseMakeRoomPreview(duration: Duration.zero);
        }
      },
    );

    testWidgets(
      "a resize preview over a track that re-measures under it holds its "
      "edge and ends on its committed rect",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(axis: LazyContentAxis(6, 80.0)),
          style: const BoardAnimationStyle(
            trackResize: _ms200,
            makeRoom: _zero,
          ),
        );
        controller.addItem(
          const _Item("m"),
          const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
        );
        final viewport = await _mount(tester, controller, height: 400.0);
        controller.previewMakeRoomGap(
          draggedKey: "m",
          prospective: const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 3),
        );
        await tester.pump();
        // TARGET a: the preview moved the leading edge.
        _expectRect(
          viewport.paintedRectOfItem("m"),
          const Rect.fromLTRB(40.0, 50.0, 80.0, 200.0),
        );
        await tester.pumpWidget(
          _board(
            controller,
            height: 400.0,
            cellHeight: (row) {
              return row == 1 ? 70.0 : 50.0;
            },
          ),
        );
        // Setup sanity: row 1 re-measured and animates its growth.
        expect(controller.anim.hasActiveTrackResize, isTrue);
        var frames = 0;
        while (controller.anim.hasActiveTrackResize && frames < 30) {
          // TARGET b: the leading edge holds while row 1 grows.
          expect(
            viewport.paintedRectOfItem("m")!.top,
            moreOrLessEquals(50.0, epsilon: 0.01),
          );
          await tester.pump(_frame);
          frames += 1;
        }
        // TARGET c: it ends on the committed rect.
        _expectRect(
          viewport.paintedRectOfItem("m"),
          const Rect.fromLTRB(40.0, 50.0, 80.0, 220.0),
        );
      },
    );
  });

  testWidgets(
    "the per-item geometry path reads the content axis the pinned number "
    "of times",
    (tester) async {
      final (controller, viewport) = await _costBoard(tester);
      final fenwick = (controller.rows.axis as LazyContentAxis).debugFenwick;
      // Setup sanity: `a`, `b` and `g` are laned, `c` and `f` are not.
      for (final key in <String>["a", "b", "g"]) {
        expect(controller.isLanedId(controller.idOfKey(key)), isTrue);
      }
      for (final key in <String>["c", "f"]) {
        expect(controller.isLanedId(controller.idOfKey(key)), isFalse);
      }

      Future<int> forcedLayout() async {
        fenwick.debugOpCount = 0;
        viewport.markNeedsLayout();
        await tester.pump();
        return fenwick.debugOpCount;
      }

      int rectOf(String key) {
        fenwick.debugOpCount = 0;
        viewport.rectOfItem(key);
        return fenwick.debugOpCount;
      }

      Future<void> release() async {
        controller.releaseMakeRoomPreview(duration: Duration.zero);
        await tester.pump();
      }

      // First: one forced layout.
      final first = await forcedLayout();
      // Second: one rectOfItem per arm and kind of item.
      final second = <String, int>{
        for (final key in <String>["a", "c", "f", "g"]) key: rectOf(key),
      };
      // Third: a forced layout under a settled move preview, which the dry
      // run lanes on lane 0 of row 1, moving `a` and `b` down a lane.
      controller.previewMakeRoomGap(
        draggedKey: "c",
        prospective: const BoardSpan(rowStart: 1, colStart: 0, colSpan: 4),
        lifted: true,
      );
      await tester.pump();
      // Setup sanity: the move preview holds `a` a lane down.
      expect(
        controller.anim.makeRoomTermDeltaOf(controller.idOfKey("a")),
        const Offset(0.0, 18.0),
      );
      final third = await forcedLayout();
      await release();
      // Sixth: rectOfItem of `a` under a resize preview that de-lanes it.
      controller.previewMakeRoomGap(
        draggedKey: "a",
        prospective: const BoardSpan(
          rowStart: 1,
          colStart: 0,
          rowSpan: 2,
          colSpan: 3,
        ),
      );
      await tester.pump();
      final sixth = rectOf("a");
      await release();
      // Fourth and fifth: rectOfItem of `c` and a forced layout under a
      // settled resize preview of `c`.
      controller.previewMakeRoomGap(
        draggedKey: "c",
        prospective: const BoardSpan(rowStart: 2, colStart: 4, rowSpan: 3),
      );
      await tester.pump();
      final fourth = rectOf("c");
      final fifth = await forcedLayout();
      // Setup sanity: that layout took one pass.
      expect(viewport.debugLastCorrectionPassCount, 1);
      // Seventh: the same preview standing, a layout that scrolls into
      // rows no layout has measured, above a measured anchor. The jump to
      // row 40 measures the rows around it and leaves a gap above them,
      // which the jump back to row 32 obtains above its anchor.
      controller.jumpToCell(40, 0);
      await tester.pump();
      controller.jumpToCell(32, 0);
      fenwick.debugOpCount = 0;
      await tester.pump();
      final seventh = fenwick.debugOpCount;
      // Setup sanity: that layout took more than one pass.
      expect(viewport.debugLastCorrectionPassCount, greaterThanOrEqualTo(2));
      await release();

      // The reads one geometry refresh of `c`'s preview makes: the rule at
      // rows 2 and 4 (stored) and 2 and 5 (prospective), whose prefix
      // sums touch as many nodes as each index has set bits, 1, 1, 1 and
      // 2, the uniform columns none, and no shift with no trackResize.
      const refresh = 5;
      // TARGET: the reads each path makes, a layout under a standing
      // resize preview adding one refresh however many passes it takes.
      expect(first, 1772);
      expect(second, <String, int>{"a": 1, "c": 2, "f": 10, "g": 2});
      expect(third, 1781);
      expect(fourth, 2);
      expect(fifth, 1869 + refresh);
      expect(sixth, 1);
      expect(seventh, 4753 + refresh);
    },
  );

  group("pins", () {
    testWidgets(
      "a resize that vacates a track above the view keeps the scroll anchor "
      "still",
      (tester) async {
        final controller = _contentLaned(tester, rowCount: 30);
        controller.addItem(
          const _Item("d"),
          const BoardSpan(rowStart: 1, colStart: 0, colSpan: 5),
        );
        final viewport = await _mount(
          tester,
          controller,
          height: 100.0,
          cellHeight: _tenPx,
        );
        controller.jumpToCell(10, 0);
        await tester.pump();
        // Setup sanity: row 1 holds `d`'s lane and lies above the view.
        expect(_rowHeight(viewport, 1), 22.0);
        expect(viewport.rectOfCell(1, 0)!.bottom, lessThan(0.0));
        final row12 = viewport.rectOfCell(12, 0)!.top;
        controller.previewMakeRoomGap(
          draggedKey: "d",
          prospective: const BoardSpan(
            rowStart: 1,
            colStart: 0,
            rowSpan: 2,
            colSpan: 5,
          ),
        );
        await tester.pump();
        await tester.pump();
        // TARGET a: the vacate shrank row 1 to its cells.
        expect(_rowHeight(viewport, 1), 10.0);
        // TARGET b: the anchor held still.
        expect(viewport.rectOfCell(12, 0)!.top, row12);
      },
    );

    testWidgets(
      "a de-laning resize committed mid-ramp hands its track off with no "
      "step",
      (tester) async {
        final controller = _contentLaned(
          tester,
          style: const BoardAnimationStyle(
            itemSlide: _ms200,
            trackResize: _ms200,
            itemEnterExit: _zero,
          ),
        );
        controller.addItem(
          const _Item("d"),
          const BoardSpan(rowStart: 1, colStart: 0, colSpan: 5),
        );
        final viewport = await _mount(
          tester,
          controller,
          cellHeight: (row) {
            return row == 0 ? 40.0 : 2.0;
          },
        );
        // Setup sanity: row 1 holds `d`'s lane.
        expect(_rowHeight(viewport, 1), 22.0);
        _expectRect(
          viewport.paintedRectOfItem("d"),
          const Rect.fromLTRB(0.0, 44.0, 200.0, 62.0),
        );
        final drag = _drag(
          tester,
          controller,
          primaryResizeEdges: BoardResizeEdges.leading,
        );
        await _resizeTo(
          tester,
          drag,
          viewport,
          key: "d",
          edge: BoardResizeEdges.leading,
          axis: Axis.vertical,
          lift: const Offset(100.0, 49.0),
          to: const Offset(100.0, 9.0),
        );
        // Setup sanity: rows [0, 2), which de-lanes `d`.
        _expectSpan(
          drag.currentTarget?.span,
          rowStart: 0.0,
          rowEnd: 2.0,
          colStart: 0.0,
          colEnd: 5.0,
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(_frame);
        }
        await tester.pump(const Duration(milliseconds: 4));
        // Setup sanity: half way, row 1 holds half of `d`'s term.
        expect(_rowHeight(viewport, 1), moreOrLessEquals(11.0, epsilon: 1.0));
        var row1 = _rowHeight(viewport, 1);
        var rect = viewport.paintedRectOfItem("d")!;
        drag.endDrag(cancel: false);
        await tester.pump();
        // TARGET a: the commit steps neither row 1 nor `d`.
        expect(_rowHeight(viewport, 1), moreOrLessEquals(row1, epsilon: 0.5));
        _expectRect(viewport.paintedRectOfItem("d"), rect, epsilon: 0.5);
        row1 = _rowHeight(viewport, 1);
        rect = viewport.paintedRectOfItem("d")!;
        var frames = 0;
        while (tester.binding.hasScheduledFrame && frames < 60) {
          await tester.pump(_frame);
          frames += 1;
          // TARGET b: both continue from where they painted.
          expect(
            (_rowHeight(viewport, 1) - row1).abs(),
            lessThanOrEqualTo(2.0),
          );
          final next = viewport.paintedRectOfItem("d")!;
          expect((next.left - rect.left).abs(), lessThanOrEqualTo(4.0));
          expect((next.top - rect.top).abs(), lessThanOrEqualTo(4.0));
          expect((next.right - rect.right).abs(), lessThanOrEqualTo(4.0));
          expect((next.bottom - rect.bottom).abs(), lessThanOrEqualTo(4.0));
          row1 = _rowHeight(viewport, 1);
          rect = next;
        }
        // TARGET c: they land where the commit puts them.
        expect(_rowHeight(viewport, 1), 2.0);
        _expectRect(
          viewport.paintedRectOfItem("d"),
          const Rect.fromLTRB(0.0, 0.0, 200.0, 42.0),
        );
      },
    );

    testWidgets("removing a resized item leaves its recycled id clean", (
      tester,
    ) async {
      Future<void> run(
        BoardAnimationStyle style, {
        required bool closing,
      }) async {
        final controller = _contentLaned(tester, style: style);
        controller.addItem(
          const _Item("d"),
          const BoardSpan(rowStart: 0, colStart: 0, colSpan: 5),
        );
        final viewport = await _mount(tester, controller, cellHeight: _twoPx);
        final dId = controller.idOfKey("d");
        controller.previewMakeRoomGap(
          draggedKey: "d",
          prospective: const BoardSpan(
            rowStart: 0,
            colStart: 0,
            rowSpan: 2,
            colSpan: 5,
          ),
        );
        await tester.pumpAndSettle(_frame);
        if (closing) {
          controller.releaseMakeRoomPreview();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          // Setup sanity: the hold is closing.
          expect(controller.makeRoomHeldKeys, <String>["d"]);
          expect(controller.anim.hasMakeRoomMotion, isTrue);
        } else {
          // Setup sanity: the hold stands.
          expect(controller.makeRoomHeldKeys, <String>["d"]);
        }
        controller.removeItem("d");
        controller.addItem(
          const _Item("e"),
          const BoardSpan(rowStart: 0, colStart: 0, colSpan: 5),
        );
        // Setup sanity: `e` took `d`'s id.
        expect(controller.idOfKey("e"), dId);
        await tester.pump();
        // TARGET: the recycled id holds nothing of `d`'s preview.
        expect(controller.makeRoomHeldKeys, isEmpty);
        expect(_rowHeight(viewport, 0), 22.0);
        _expectRect(
          viewport.paintedRectOfItem("e"),
          const Rect.fromLTRB(0.0, 4.0, 200.0, 22.0),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }

      await run(BoardAnimationStyle.disabled, closing: false);
      await run(
        const BoardAnimationStyle(
          makeRoom: _ms200,
          itemEnterExit: _zero,
          trackResize: _zero,
        ),
        closing: true,
      );
    });

    testWidgets(
      "a resize hold that moves only an item's lead widens the item window "
      "by it",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(30, 50.0)),
        );
        controller.addItem(
          const _Item("d"),
          const BoardSpan(rowStart: 3, colStart: 1),
        );
        final viewport = await _mount(tester, controller);
        controller.jumpToCell(18, 0);
        await tester.pump();
        // Setup sanity: `d`'s span lies outside the window, unbuilt.
        expect(viewport.verticalOffset.pixels, 900.0);
        expect(find.text("d"), findsNothing);
        controller.previewMakeRoomGap(
          draggedKey: "d",
          prospective: const BoardSpan(rowStart: 20, colStart: 1),
        );
        await tester.pump();
        // TARGET a: the bound carries the lead.
        expect(controller.anim.composedOffsetBound, (dx: 0.0, dy: 850.0));
        // TARGET b: `d` is obtained, and paints at its preview.
        expect(find.text("d"), findsOneWidget);
        _expectRect(
          viewport.paintedRectOfItem("d"),
          const Rect.fromLTRB(40.0, 100.0, 80.0, 150.0),
        );
      },
    );

    testWidgets(
      "a resize preview's refreshes and readers make the computed reads",
      (tester) async {
        final (controller, viewport) = await _costBoard(tester);
        final fenwick = (controller.rows.axis as LazyContentAxis).debugFenwick;
        final coordinator =
            controller.anim as BoardAnimationCoordinator<String>;
        final shifts = coordinator.trackResize;

        ({int fenwick, int shifts}) geometryReads() {
          fenwick.debugOpCount = 0;
          shifts.debugShiftCallCount = 0;
          controller.refreshResizeGeometry(rowShiftFloor: 0, colShiftFloor: 0);
          return (
            fenwick: fenwick.debugOpCount,
            shifts: shifts.debugShiftCallCount,
          );
        }

        ({int fenwick, int shifts}) termReads() {
          fenwick.debugOpCount = 0;
          shifts.debugShiftCallCount = 0;
          controller.refreshResizeTerm();
          return (
            fenwick: fenwick.debugOpCount,
            shifts: shifts.debugShiftCallCount,
          );
        }

        Future<void> release() async {
          controller.releaseMakeRoomPreview(duration: Duration.zero);
          await tester.pump();
        }

        Future<int> forcedLayoutHoldReads() async {
          coordinator.makeRoom.debugResizeHoldReadCount = 0;
          viewport.markNeedsLayout();
          await tester.pump();
          return coordinator.makeRoom.debugResizeHoldReadCount;
        }

        const previews = <String, BoardSpan>{
          // Unlaned under both spans.
          "c": BoardSpan(rowStart: 2, colStart: 4, rowSpan: 3),
          // A vacate: laned in row 1, then over two rows.
          "a": BoardSpan(rowStart: 1, colStart: 0, rowSpan: 2, colSpan: 3),
          // A band: from lane 1 of 2 to lane 0 of 1 in row 1.
          "b": BoardSpan(rowStart: 1, colStart: 3),
        };
        // The refresh arm: the rule at the stored and the prospective
        // spans, whose prefix sums touch as many nodes as each index has
        // set bits: `c` at rows 2 and 4, then 2 and 5; `a` laned at row
        // 1, then at rows 1 and 3; `b` laned at row 1 twice. The term
        // refresh reads lanes alone.
        const geometry = <String, int>{"c": 5, "a": 4, "b": 2};
        for (final entry in previews.entries) {
          controller.previewMakeRoomGap(
            draggedKey: entry.key,
            prospective: entry.value,
          );
          await tester.pump();
          // TARGET a: the computed reads, and no shift read with no
          // trackResize in flight.
          expect(geometryReads(), (fenwick: geometry[entry.key]!, shifts: 0));
          expect(termReads(), (fenwick: 0, shifts: 0));
          await release();
        }

        // The shift arm: a trackResize in flight under `c`'s preview.
        controller.previewMakeRoomGap(
          draggedKey: "c",
          prospective: previews["c"]!,
        );
        await tester.pump();
        controller.animationStyle = const BoardAnimationStyle(
          trackResize: _ms200,
          itemSlide: _zero,
          itemEnterExit: _zero,
        );
        await tester.pumpWidget(
          _board(
            controller,
            cellHeight: (row) {
              return row == 0 ? 30.0 : 20.0;
            },
          ),
        );
        // Setup sanity: row 0 re-measured and animates its growth.
        expect(controller.anim.hasActiveTrackResize, isTrue);
        // TARGET b: a lead and a trail per span per axis.
        expect(geometryReads().shifts, 8);
        expect(termReads(), (fenwick: 0, shifts: 0));
        await tester.pump(const Duration(milliseconds: 400));
        await release();
        controller.animationStyle = BoardAnimationStyle.disabled;
        await tester.pump();

        // The map arm.
        // TARGET c: with no resize hold, no reader looks a hold map up.
        expect(await forcedLayoutHoldReads(), 0);
        controller.previewMakeRoomGap(
          draggedKey: "c",
          prospective: const BoardSpan(rowStart: 1, colStart: 0, colSpan: 4),
          lifted: true,
        );
        await tester.pump();
        expect(await forcedLayoutHoldReads(), 0);
        await release();
        controller.previewMakeRoomGap(
          draggedKey: "b",
          prospective: previews["b"]!,
        );
        await tester.pump();
        // Setup sanity: a resize hold's readers do count.
        expect(await forcedLayoutHoldReads(), greaterThan(0));
        await release();
      },
    );

    testWidgets(
      "a commit inside a cancelled resize's close leaves its hold closing",
      (tester) async {
        const deLane = BoardSpan(
          rowStart: 0,
          colStart: 0,
          rowSpan: 2,
          colSpan: 5,
        );
        const deRest = Rect.fromLTRB(0.0, 4.0, 200.0, 22.0);

        Future<void> pump100() async {
          for (var i = 0; i < 6; i++) {
            await tester.pump(_frame);
          }
          await tester.pump(const Duration(milliseconds: 4));
        }

        /// `d` laned alone in row 0 over 2 px cells and `n` at row 3,
        /// column 6: `d`'s de-laning preview settled, then cancelled,
        /// 100 ms into its close.
        Future<(BoardController<String, _Item>, RenderBoardViewport<String>)>
        cancelled({bool enter = false}) async {
          final controller = _contentLaned(
            tester,
            style: BoardAnimationStyle(
              itemSlide: _ms200,
              trackResize: _ms200,
              itemEnterExit: enter ? _ms200 : _zero,
            ),
          );
          controller.addItem(
            const _Item("d"),
            const BoardSpan(rowStart: 0, colStart: 0, colSpan: 5),
          );
          controller.addItem(
            const _Item("n"),
            const BoardSpan(rowStart: 3, colStart: 6),
          );
          final viewport = await _mount(tester, controller, cellHeight: _twoPx);
          controller.previewMakeRoomGap(draggedKey: "d", prospective: deLane);
          await tester.pumpAndSettle(_frame);
          // Setup sanity: the vacate settled.
          expect(_rowHeight(viewport, 0), 2.0);
          controller.releaseMakeRoomPreview();
          if (enter) {
            controller.addItem(
              const _Item("e"),
              const BoardSpan(rowStart: 0, colStart: 6),
            );
          }
          await tester.pump();
          await pump100();
          // Setup sanity: row 0 half way back, or held higher by the
          // entering item's ramp.
          expect(_rowHeight(viewport, 0), enter ? 13.0 : 11.0);
          return (controller, viewport);
        }

        /// A lifted drag of `n` to [row], committed in the frame it moved.
        void commitMove(
          BoardController<String, _Item> controller,
          RenderBoardViewport<String> viewport,
          int row,
        ) {
          final drag = _drag(tester, controller);
          final lift = viewport.paintedRectOfItem("n")!.center;
          expect(
            drag.startDrag(
              key: "n",
              renderPort: viewport,
              pointerGlobal: _global(tester, lift),
            ),
            isTrue,
          );
          drag.updateDrag(
            _global(
              tester,
              Offset(lift.dx, viewport.rectOfCell(row, 6)!.center.dy),
            ),
          );
          // Setup sanity: the move resolves the row it was taken to.
          expect(drag.currentTarget?.span.rowStart, row);
          drag.endDrag(cancel: false);
        }

        {
          // A commit of another item mid-close.
          final (controller, viewport) = await cancelled();
          final row0 = _rowHeight(viewport, 0);
          final before = viewport.paintedRectOfItem("d")!;
          commitMove(controller, viewport, 4);
          await tester.pump();
          // TARGET a: the close continues, neither row 0 nor `d` steps.
          expect(_rowHeight(viewport, 0), moreOrLessEquals(row0, epsilon: 0.5));
          _expectRect(viewport.paintedRectOfItem("d"), before, epsilon: 0.5);
          await tester.pumpAndSettle(_frame);
          expect(_rowHeight(viewport, 0), 22.0);
          _expectRect(viewport.paintedRectOfItem("d"), deRest);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        {
          // A leading-edge resize's far edge across another's commit.
          final controller = _uniform(
            tester,
            style: const BoardAnimationStyle(
              makeRoom: _ms200,
              itemSlide: _ms200,
              itemEnterExit: _zero,
            ),
          );
          controller.addItem(
            const _Item("m"),
            const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
          );
          controller.addItem(
            const _Item("n"),
            const BoardSpan(rowStart: 0, colStart: 5),
          );
          final viewport = await _mount(tester, controller);
          controller.previewMakeRoomGap(
            draggedKey: "m",
            prospective: const BoardSpan(rowStart: 3, colStart: 1),
          );
          await tester.pumpAndSettle(_frame);
          controller.releaseMakeRoomPreview();
          await tester.pump();
          await pump100();
          // Setup sanity: half way through the close.
          _expectRect(
            viewport.paintedRectOfItem("m"),
            const Rect.fromLTRB(40.0, 125.0, 80.0, 200.0),
          );
          final drag = _drag(
            tester,
            controller,
            primaryResizeEdges: BoardResizeEdges.trailing,
          );
          expect(
            drag.startDrag(
              key: "n",
              renderPort: viewport,
              pointerGlobal: _global(tester, const Offset(220.0, 45.0)),
              edge: BoardResizeEdges.trailing,
              axis: Axis.vertical,
            ),
            isTrue,
          );
          drag.updateDrag(_global(tester, const Offset(220.0, 95.0)));
          // Setup sanity: rows [0, 2).
          _expectSpan(
            drag.currentTarget?.span,
            rowStart: 0.0,
            rowEnd: 2.0,
            colStart: 5.0,
            colEnd: 6.0,
          );
          drag.endDrag(cancel: false);
          var frames = 0;
          await tester.pump();
          do {
            // TARGET b: `m`'s far edge holds through the commit and the
            // rest of its close.
            expect(
              viewport.paintedRectOfItem("m")!.bottom,
              moreOrLessEquals(200.0, epsilon: 0.01),
            );
            await tester.pump(_frame);
            frames += 1;
          } while (tester.binding.hasScheduledFrame && frames < 60);
          _expectRect(
            viewport.paintedRectOfItem("m"),
            const Rect.fromLTRB(40.0, 100.0, 80.0, 200.0),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        }
        {
          // The same commit while an entering item keeps row 0 latched.
          final (controller, viewport) = await cancelled(enter: true);
          final row0 = _rowHeight(viewport, 0);
          commitMove(controller, viewport, 4);
          await tester.pump();
          // TARGET c: row 0 does not step.
          expect(_rowHeight(viewport, 0), moreOrLessEquals(row0, epsilon: 0.5));
          await tester.pumpAndSettle(_frame);
          _expectRect(viewport.paintedRectOfItem("d"), deRest);
          await tester.pumpWidget(const SizedBox.shrink());
        }
        {
          // A commit into row 0 beside `d`.
          final (controller, viewport) = await cancelled();
          commitMove(controller, viewport, 0);
          await tester.pump();
          // TARGET d: `n`'s band lands in row 0 at once, the surviving
          // vacate keeping the row latched.
          expect(_rowHeight(viewport, 0), 22.0);
          await tester.pumpAndSettle(_frame);
          _expectRect(viewport.paintedRectOfItem("d"), deRest);
          _expectRect(
            viewport.paintedRectOfItem("n"),
            const Rect.fromLTRB(240.0, 4.0, 280.0, 22.0),
          );
        }
      },
    );

    testWidgets(
      "a resize vacates only a content-sized track its item is laned in "
      "and leaves",
      (tester) async {
        {
          final controller = _controller(
            tester,
            rows: BoardAxisConfig(
              axis: UniformAxis(6, 50.0),
              laneExtent: 20.0,
              lanePadding: 4.0,
            ),
          );
          controller.addItem(
            const _Item("m"),
            const BoardSpan(rowStart: 2, colStart: 1),
          );
          await _mount(tester, controller);
          controller.previewMakeRoomGap(
            draggedKey: "m",
            prospective: const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 2),
          );
          // TARGET a: a fixed lane axis sizes no track by its lanes.
          expect(
            controller.anim.makeRoomVacatedOf(controller.idOfKey("m")),
            0.0,
          );
          await tester.pumpWidget(const SizedBox.shrink());
        }
        final (controller, _) = await _costBoard(tester);
        controller.previewMakeRoomGap(
          draggedKey: "c",
          prospective: const BoardSpan(rowStart: 2, colStart: 4, rowSpan: 3),
        );
        // TARGET b: an unlaned item is no member of a track's term.
        expect(controller.anim.makeRoomVacatedOf(controller.idOfKey("c")), 0.0);
        controller.releaseMakeRoomPreview(duration: Duration.zero);
        controller.previewMakeRoomGap(
          draggedKey: "b",
          prospective: const BoardSpan(rowStart: 3, colStart: 1, colSpan: 3),
        );
        // Setup sanity: the preview lanes `b` in row 3.
        expect(controller.anim.makeRoomSlotsOn(3).toList(), hasLength(1));
        // TARGET c: laned in another track, it leaves row 1.
        expect(controller.anim.makeRoomVacatedOf(controller.idOfKey("b")), 1.0);
        controller.releaseMakeRoomPreview(duration: Duration.zero);
      },
    );

    testWidgets("a resize whose leading edge stays put holds no lead for the "
        "rounding of its arithmetic", (tester) async {
      final controller = _uniform(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 0, colStart: 1, rowFraction: 0.3),
      );
      await _mount(tester, controller);
      controller.previewMakeRoomGap(
        draggedKey: "m",
        prospective: const BoardSpan(
          rowStart: 0,
          colStart: 1,
          rowFraction: 0.1 + 0.2,
          rowSpan: 2,
        ),
      );
      // TARGET: the extent changes and the lead does not.
      expect(controller.anim.hasActiveOffsets, isFalse);
    });

    testWidgets("a make-room install reads no prefix sum for its neighbours' "
        "extents", (tester) async {
      final (controller, _) = await _costBoard(tester);
      final fenwick = (controller.rows.axis as LazyContentAxis).debugFenwick;
      fenwick.debugOpCount = 0;
      controller.previewMakeRoomGap(
        draggedKey: "c",
        prospective: const BoardSpan(rowStart: 1, colStart: 0, colSpan: 4),
        lifted: true,
      );
      final reads = fenwick.debugOpCount;
      // Setup sanity: the dry run moves `a`, a neighbour, a lane down.
      expect(
        controller.anim.makeRoomTermDeltaOf(controller.idOfKey("a")),
        const Offset(0.0, 18.0),
      );
      // TARGET: no prefix sum.
      expect(reads, 0);
      controller.releaseMakeRoomPreview(duration: Duration.zero);
    });

    testWidgets(
      "a vacating item holds its track at its own share over a shallower "
      "member's",
      (tester) async {
        final controller = _contentLaned(
          tester,
          style: const BoardAnimationStyle(
            itemSlide: _ms200,
            trackResize: _ms200,
            itemEnterExit: _zero,
          ),
        );
        controller.addItem(
          const _Item("a"),
          const BoardSpan(rowStart: 0, colStart: 0, colSpan: 5),
        );
        controller.addItem(
          const _Item("d"),
          const BoardSpan(rowStart: 0, colStart: 0, colSpan: 4),
        );
        final viewport = await _mount(tester, controller, cellHeight: _tenPx);
        // Setup sanity: `d` on lane 1 of the two in row 0.
        expect(controller.laneOfId(controller.idOfKey("d")), 1);
        expect(_rowHeight(viewport, 0), 40.0);
        controller.previewMakeRoomGap(
          draggedKey: "d",
          prospective: const BoardSpan(
            rowStart: 0,
            colStart: 0,
            rowSpan: 2,
            colSpan: 4,
          ),
        );
        for (var t = 0; t <= 208; t += 16) {
          await tester.pump(t == 0 ? Duration.zero : _frame);
          final share = 40.0 * (1.0 - t / 200.0);
          // TARGET: row 0 follows `d`'s share down to `a`'s lane.
          expect(
            _rowHeight(viewport, 0),
            moreOrLessEquals(share < 22.0 ? 22.0 : share, epsilon: 0.5),
          );
        }
        controller.releaseMakeRoomPreview(duration: Duration.zero);
      },
    );

    testWidgets("two vacating items hold their track at the larger share", (
      tester,
    ) async {
      final controller = _contentLaned(
        tester,
        style: const BoardAnimationStyle(
          itemSlide: _ms200,
          trackResize: _ms200,
          itemEnterExit: _zero,
        ),
      );
      controller.addItem(
        const _Item("p"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 5),
      );
      controller.addItem(
        const _Item("q"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 4),
      );
      final viewport = await _mount(tester, controller, cellHeight: _tenPx);
      controller.previewMakeRoomGap(
        draggedKey: "q",
        prospective: const BoardSpan(
          rowStart: 0,
          colStart: 0,
          rowSpan: 2,
          colSpan: 4,
        ),
      );
      await tester.pumpAndSettle(_frame);
      // Setup sanity: `q` vacated, leaving `p`'s lane.
      expect(_rowHeight(viewport, 0), 22.0);
      controller.releaseMakeRoomPreview();
      controller.previewMakeRoomGap(
        draggedKey: "p",
        prospective: const BoardSpan(
          rowStart: 0,
          colStart: 0,
          rowSpan: 2,
          colSpan: 5,
        ),
      );
      for (var t = 0; t <= 48; t += 16) {
        await tester.pump(t == 0 ? Duration.zero : _frame);
        final x = t / 200.0;
        // TARGET: row 0 holds `p`'s share as it leaves, the larger of
        // the two while `q` comes back.
        expect(
          _rowHeight(viewport, 0),
          moreOrLessEquals(22.0 * (1.0 - x), epsilon: 0.5),
        );
      }
      controller.releaseMakeRoomPreview(duration: Duration.zero);
      await tester.pumpAndSettle(_frame);
    });

    testWidgets(
      "a pinned item's resize preview takes no shift from a track resizing "
      "in its band",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(
            axis: LazyContentAxis(12, 80.0),
            frozenStart: 2,
          ),
          style: const BoardAnimationStyle(
            trackResize: _ms200,
            makeRoom: _zero,
          ),
        );
        controller.addItem(
          const _Item("m"),
          const BoardSpan(rowStart: 0, colStart: 1, rowSpan: 2),
        );
        final viewport = await _mount(tester, controller, height: 400.0);
        // Setup sanity: `m` is pinned in the band.
        expect(
          controller.pinOfId(controller.idOfKey("m"), Axis.vertical),
          BoardPin.leading,
        );
        controller.previewMakeRoomGap(
          draggedKey: "m",
          prospective: const BoardSpan(rowStart: 1, colStart: 1),
        );
        await tester.pumpWidget(
          _board(
            controller,
            height: 400.0,
            cellHeight: (row) {
              return row == 0 ? 70.0 : 50.0;
            },
          ),
        );
        // Setup sanity: row 0 re-measured and animates its growth.
        expect(controller.anim.hasActiveTrackResize, isTrue);
        var frames = 0;
        while (controller.anim.hasActiveTrackResize && frames < 30) {
          await tester.pump(_frame);
          frames += 1;
          // TARGET: `m`'s leading edge stays on row 1's.
          expect(
            viewport.paintedRectOfItem("m")!.top,
            moreOrLessEquals(viewport.rectOfCell(1, 0)!.top, epsilon: 0.01),
          );
        }
        controller.releaseMakeRoomPreview(duration: Duration.zero);
      },
    );

    testWidgets(
      "a resize preview takes the trackResize shift from the window the "
      "layout walked",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(axis: LazyContentAxis(40, 80.0)),
          style: const BoardAnimationStyle(
            trackResize: _ms200,
            makeRoom: _zero,
            itemSlide: _zero,
            itemEnterExit: _zero,
          ),
        );
        controller.addItem(
          const _Item("m"),
          const BoardSpan(rowStart: 14, colStart: 1, rowSpan: 16),
        );
        final viewport = await _mount(tester, controller);
        controller.jumpToCell(10, 0);
        await tester.pump();
        controller.previewMakeRoomGap(
          draggedKey: "m",
          prospective: const BoardSpan(rowStart: 12, colStart: 1, rowSpan: 18),
        );
        await tester.pumpWidget(
          _board(
            controller,
            cellHeight: (row) {
              return row == 12 ? 70.0 : 50.0;
            },
          ),
        );
        // Setup sanity: row 12 re-measured and animates its growth.
        expect(controller.anim.hasActiveTrackResize, isTrue);
        await tester.pump(const Duration(milliseconds: 50));
        controller.jumpToCell(25, 0);
        var frames = 0;
        do {
          await tester.pump(frames == 0 ? Duration.zero : _frame);
          frames += 1;
          // TARGET: `m`'s leading edge sits on row 12's as it paints.
          expect(
            viewport.paintedRectOfItem("m")!.top,
            moreOrLessEquals(viewport.rectOfCell(12, 0)!.top, epsilon: 0.01),
          );
        } while (controller.anim.hasActiveTrackResize && frames < 30);
        controller.releaseMakeRoomPreview(duration: Duration.zero);
      },
    );
  });
}
