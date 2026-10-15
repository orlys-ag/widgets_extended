/// The render's own-free lattice in the states the resize repros do not
/// reach: tracks of differing extents, settled and while a track resize
/// runs; a track whose cells build nothing or measure below the minimum;
/// a short lattice; frozen bands holding own tracks; own data grown past
/// its first capacity; an own track left outside the window; a foreign
/// change at the end of the scroll range; and the own data's key across a
/// controller swap, an axis instance change and a new scope.
///
/// Points are paint space in the board's frame. Every row is 10 px but
/// where a test says otherwise: a laned row holds 18 px lanes under a
/// 4 px padding, so one lane is 22 px and two are 40 px.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
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

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// Make-room on a 200 ms linear clock, which it inherits from itemSlide.
const BoardAnimationStyle _animated = BoardAnimationStyle(
  trackResize: _ms200,
  itemSlide: _ms200,
);

/// Track resizes on a 200 ms linear clock and make-room off.
const BoardAnimationStyle _resizesOnly = BoardAnimationStyle(
  trackResize: _ms200,
  itemSlide: _zero,
  itemEnterExit: _zero,
);

BoardAxisConfig _laned(
  BoardAxis axis, {
  int frozenStart = 0,
  int frozenEnd = 0,
}) {
  return BoardAxisConfig(
    axis: axis,
    laneExtent: 18.0,
    lanePadding: 4.0,
    frozenStart: frozenStart,
    frozenEnd: frozenEnd,
  );
}

/// Content-sized laned rows over seven 40 px columns.
BoardController<String, _Item> _rowsLaned(
  WidgetTester tester, {
  int rowCount = 6,
  double estimate = 80.0,
  double minTrackExtent = 1.0,
  int frozenStart = 0,
  int frozenEnd = 0,
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: _laned(
      LazyContentAxis(rowCount, estimate, minTrackExtent: minTrackExtent),
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

/// A 280 x 300 frame holding a board on [controller] whose cells are
/// [cellHeight] tall, or build nothing where it answers null.
Widget _app(
  BoardController<String, _Item> controller, {
  double? Function(int row)? cellHeight,
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
            cellBuilder: (context, view) {
              final height = cellHeight == null ? 10.0 : cellHeight(view.row);
              if (height == null) {
                return null;
              }
              return SizedBox(width: 40.0, height: height);
            },
            itemBuilder: (context, item) {
              return const ColoredBox(color: Color(0xFF4CAF50));
            },
          ),
        ),
      ),
    ),
  );
}

/// Mounts [controller], settles it, and unmounts before the controller's
/// own teardown disposes it.
Future<RenderBoardViewport<String>> _mount(
  WidgetTester tester,
  BoardController<String, _Item> controller, {
  double? Function(int row)? cellHeight,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpWidget(_app(controller, cellHeight: cellHeight));
  await tester.pumpAndSettle(_frame);
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

void _add(
  BoardController<String, _Item> controller,
  String key,
  BoardSpan span,
) {
  controller.addItem(_Item(key), span);
}

/// `a` laned in row 1 at columns [0, 4), so row 1 is 22 px, and `d` on
/// rows [0, 2) at columns [0, 5), unlaned: [_joinSpan] lanes `d` in row
/// 1 beside `a`, which grows row 1 to 40.
void _addJoinItems(BoardController<String, _Item> controller) {
  _add(controller, "a", const BoardSpan(rowStart: 1, colStart: 0, colSpan: 4));
  _add(
    controller,
    "d",
    const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 2, colSpan: 5),
  );
}

/// `a` and `d` laned in [row], so it is 40 px: a resize of `d` out of it
/// vacates it to 22.
void _addDelaneItems(BoardController<String, _Item> controller, {int row = 0}) {
  _add(controller, "a", BoardSpan(rowStart: row, colStart: 0, colSpan: 4));
  _add(controller, "d", BoardSpan(rowStart: row, colStart: 0, colSpan: 5));
}

const BoardSpan _joinSpan = BoardSpan(rowStart: 1, colStart: 0, colSpan: 5);

BoardSpan _rows(int start, int span) {
  return BoardSpan(rowStart: start, colStart: 0, rowSpan: span, colSpan: 5);
}

void _install(
  BoardController<String, _Item> controller,
  BoardSpan span, {
  String key = "d",
}) {
  controller.previewMakeRoomGap(draggedKey: key, prospective: span);
}

BoardAxisSample _ownFree(
  BoardController<String, _Item> controller,
  RenderBoardViewport<String> viewport,
  Offset local,
) {
  return controller.trackSampleWithoutOwnPreview(viewport, local)!.row;
}

BoardAxisSample _painted(RenderBoardViewport<String> viewport, Offset local) {
  return viewport.trackSampleAt(local)!.row;
}

double _rowExtent(RenderBoardViewport<String> viewport, int row) {
  return viewport.rectOfCell(row, 0)!.height;
}

Matcher _near(double value) {
  return moreOrLessEquals(value, epsilon: 1e-9);
}

/// Forty rows with [_addDelaneItems]' items in row 39, at the scroll
/// offset [pixels] after one pump, so the rows end at 430 and the scroll
/// range at 130; [laneInRow38] adds a laned item in row 38, which ends
/// them at 442 and the range at 142.
Future<(BoardController<String, _Item>, RenderBoardViewport<String>)>
_vacateAtEnd(
  WidgetTester tester,
  double pixels, {
  bool laneInRow38 = false,
}) async {
  final controller = _rowsLaned(tester, rowCount: 40);
  _addDelaneItems(controller, row: 39);
  if (laneInRow38) {
    _add(
      controller,
      "x",
      const BoardSpan(rowStart: 38, colStart: 5, colSpan: 2),
    );
  }
  final viewport = await _mount(tester, controller);
  viewport.verticalPosition!.jumpTo(pixels);
  await tester.pump();
  return (controller, viewport);
}

void main() {
  testWidgets("the own-free lookup finds its track among tracks of differing "
      "extents, settled and while a track resize runs", (tester) async {
    final controller = _rowsLaned(tester, style: _resizesOnly);
    _addJoinItems(controller);
    _add(
      controller,
      "x3",
      const BoardSpan(rowStart: 3, colStart: 5, colSpan: 2),
    );
    final viewport = await _mount(tester, controller);
    expect(_rowExtent(viewport, 3), 22.0);
    controller.beginOwnMakeRoomPreview();
    _install(controller, _joinSpan);
    await tester.pump();
    expect(_rowExtent(viewport, 1), 40.0);
    expect(controller.anim.hasActiveTrackResize, isFalse);
    // Rows start at 0, 10, 50, 60 and 82 as they paint, and at 0, 10,
    // 32, 42 and 64 without the preview, whose row 1 is 22.
    const settled = Offset(40.0, 70.0);
    expect(_painted(viewport, settled).painted, _near(3.0 + 10.0 / 22.0));
    expect(_ownFree(controller, viewport, settled).painted, _near(4.6));

    // A lane in row 2 grows it from 10 to 22 on the track-resize clock:
    // half way it is 16, rows 3 and 4 start at 66 and 88 as they paint
    // and at 48 and 70 without the preview, and settled at 72 and 94,
    // and 54 and 76.
    _add(
      controller,
      "x2",
      const BoardSpan(rowStart: 2, colStart: 5, colSpan: 2),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.anim.hasActiveTrackResize, isTrue);
    expect(_rowExtent(viewport, 2), _near(16.0));
    const moving = Offset(40.0, 75.0);
    expect(_painted(viewport, moving).painted, _near(3.0 + 9.0 / 22.0));
    expect(_ownFree(controller, viewport, moving).painted, _near(4.5));
    await tester.pumpAndSettle(_frame);
  });

  testWidgets(
    "the own-free extent of a track whose cells build nothing stands in "
    "with the estimate",
    (tester) async {
      final controller = _rowsLaned(tester, estimate: 30.0);
      _addJoinItems(controller);
      final viewport = await _mount(
        tester,
        controller,
        cellHeight: (row) {
          return row == 1 ? null : 10.0;
        },
      );
      expect(_rowExtent(viewport, 1), 30.0);
      controller.beginOwnMakeRoomPreview();
      _install(controller, _joinSpan);
      await tester.pump();
      expect(_rowExtent(viewport, 1), 40.0);
      // Without the preview row 1 is the estimate's 30, the larger of it
      // and the one lane's 22, so row 2 starts at 40, not 50.
      const point = Offset(40.0, 55.0);
      expect(_painted(viewport, point).painted, _near(2.5));
      expect(_ownFree(controller, viewport, point).painted, _near(3.5));
    },
  );

  testWidgets(
    "the own-free extent of a track whose cells measure below the minimum "
    "is the minimum",
    (tester) async {
      final controller = _rowsLaned(tester, minTrackExtent: 8.0);
      _add(controller, "d", _rows(0, 3));
      final viewport = await _mount(
        tester,
        controller,
        cellHeight: (row) {
          return 2.0;
        },
      );
      expect(_rowExtent(viewport, 2), 8.0);
      controller.beginOwnMakeRoomPreview();
      _install(
        controller,
        const BoardSpan(rowStart: 2, colStart: 0, colSpan: 5),
      );
      await tester.pump();
      expect(_rowExtent(viewport, 2), 22.0);
      // Without the preview row 2 holds no lane and its 2 px cells floor
      // at 8, so row 3 starts at 24.
      const point = Offset(40.0, 30.0);
      expect(_painted(viewport, point).painted, _near(2.0 + 14.0 / 22.0));
      expect(_ownFree(controller, viewport, point).painted, _near(3.75));
    },
  );

  testWidgets(
    "an own-free sample past a short lattice whose last track is own reads "
    "the lattice's end",
    (tester) async {
      final controller = _rowsLaned(tester);
      _addDelaneItems(controller, row: 5);
      final viewport = await _mount(tester, controller);
      expect(_rowExtent(viewport, 5), 40.0);
      controller.beginOwnMakeRoomPreview();
      _install(controller, _rows(4, 2));
      await tester.pump();
      expect(_rowExtent(viewport, 5), 22.0);
      const point = Offset(40.0, 200.0);
      expect(_painted(viewport, point).painted, 6.0);
      final ownFree = _ownFree(controller, viewport, point);
      expect(ownFree.painted, 6.0);
      expect(ownFree.scrolled, 6.0);
    },
  );

  testWidgets(
    "a sample between an axis instance change and the next layout reads "
    "the painted lattice",
    (tester) async {
      final controller = _rowsLaned(tester);
      _addJoinItems(controller);
      final viewport = await _mount(tester, controller);
      BoardAxisConfig padded(BoardAxis axis) {
        return BoardAxisConfig(axis: axis, laneExtent: 18.0, lanePadding: 6.0);
      }

      // One measurement reset of the first instance, so its count is the
      // one the new instance's own reset gives it.
      controller.rows = padded(controller.rows.axis);
      await tester.pump();
      expect(_rowExtent(viewport, 1), 24.0);
      controller.beginOwnMakeRoomPreview();
      _install(controller, _joinSpan);
      await tester.pump();
      expect(_rowExtent(viewport, 1), 42.0);
      expect(
        _ownFree(controller, viewport, const Offset(40.0, 20.0)).painted,
        _near(1.0 + 10.0 / 24.0),
      );

      controller.rows = padded(LazyContentAxis(6, 80.0));
      const point = Offset(40.0, 100.0);
      expect(_painted(viewport, point).painted, _near(1.25));
      expect(_ownFree(controller, viewport, point).painted, _near(1.25));
    },
  );

  testWidgets(
    "a scroll past where its preview's spring-back began moves the own-free "
    "scroll offset with it",
    (tester) async {
      final (controller, viewport) = await _vacateAtEnd(tester, 129.0);
      final position = viewport.verticalPosition!;
      controller.beginOwnMakeRoomPreview();
      position.jumpTo(130.0);
      _install(controller, _rows(36, 4));
      await tester.pump();
      expect(position.pixels, greaterThan(112.0));
      expect(position.pixels, lessThanOrEqualTo(130.0));
      const point = Offset(40.0, 236.0);
      expect(_ownFree(controller, viewport, point).painted, _near(36.6));
      final samples = <(double, double)>[];
      void listener() {
        samples.add((
          position.pixels,
          _ownFree(controller, viewport, point).painted,
        ));
      }

      position.addListener(listener);
      position.jumpTo(140.0);
      position.removeListener(listener);
      expect(samples, hasLength(1));
      expect(samples.single.$1, 140.0);
      expect(samples.single.$2, _near(37.6));
      await tester.pumpAndSettle(_frame);
    },
  );

  testWidgets(
    "an own track its preview left outside the window keeps its delta once "
    "its pairs drop",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 100, estimate: 10.0);
      _addDelaneItems(controller, row: 90);
      final viewport = await _mount(tester, controller);
      final position = viewport.verticalPosition!;
      position.jumpTo(700.0);
      await tester.pump();
      position.jumpTo(730.0);
      await tester.pump();
      expect(position.pixels, 730.0);
      controller.beginOwnMakeRoomPreview();
      _install(controller, _rows(90, 3));
      await tester.pump();
      // The vacate clamps the scroll offset to 712, which it would not
      // without the preview.
      expect(position.pixels, 712.0);
      position.jumpTo(0.0);
      await tester.pump();
      _install(
        controller,
        const BoardSpan(rowStart: 90, colStart: 0, colSpan: 5),
      );
      await tester.pump();
      expect(controller.makeRoomOwnIdCount, 0);
      // Row 90, far outside the window, still stores the vacated 22, so
      // the scroll the preview left stands: without it the board would be
      // 18 px further on.
      const point = Offset(40.0, 50.0);
      expect(_painted(viewport, point).painted, _near(5.0));
      expect(_ownFree(controller, viewport, point).painted, _near(6.8));
    },
  );

  testWidgets(
    "own data grown past eight own tracks keeps each track's mark and "
    "delta",
    (tester) async {
      final controller = _rowsLaned(
        tester,
        rowCount: 100,
        estimate: 10.0,
        style: _animated,
      );
      _addDelaneItems(controller);
      _add(
        controller,
        "n",
        const BoardSpan(rowStart: 60, colStart: 0, colSpan: 4),
      );
      final viewport = await _mount(tester, controller);
      final position = viewport.verticalPosition!;
      position.jumpTo(45.0);
      await tester.pump();
      controller.beginOwnMakeRoomPreview();
      _install(controller, _rows(0, 3));
      for (var pump = 1; pump <= 20; pump++) {
        await tester.pump(_frame);
      }
      expect(position.pixels, _near(27.0));
      // Row 0, the vacated track, now lies outside every window.
      position.jumpTo(600.0);
      await tester.pump();
      _install(
        controller,
        const BoardSpan(rowStart: 60, colStart: 0, colSpan: 5),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_rowExtent(viewport, 60), _near(31.0));
      // In one frame, slots on eight more rows: rows 0, 60 and 61 to 66
      // fill the own data's first eight places, and row 67 grows it.
      for (var row = 61; row <= 68; row++) {
        _install(controller, BoardSpan(rowStart: row, colStart: 0, colSpan: 5));
      }
      await tester.pump();
      // Without the preview row 0 is 40 and row 60 is 22, so row 61
      // starts at 652, and the scroll offset is 618.
      expect(
        _ownFree(controller, viewport, const Offset(40.0, 50.0)).painted,
        _near(62.6),
      );
      controller.releaseMakeRoomPreview();
      await tester.pumpAndSettle(_frame);
    },
  );

  testWidgets(
    "a controller swap resets the own data of a shared axis instance",
    (tester) async {
      final axis = LazyContentAxis(40, 80.0);
      BoardController<String, _Item> create() {
        final controller = BoardController<String, _Item>(
          vsync: tester,
          rows: _laned(axis),
          columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
          keyOf: (item) {
            return item.key;
          },
          animationStyle: BoardAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        return controller;
      }

      final first = create();
      _addDelaneItems(first);
      final second = create();
      _add(second, "b", const BoardSpan(rowStart: 30, colStart: 0, colSpan: 4));
      _add(second, "e", const BoardSpan(rowStart: 30, colStart: 0, colSpan: 5));
      final viewport = await _mount(tester, first);
      final position = viewport.verticalPosition!;
      position.jumpTo(45.0);
      await tester.pump();
      first.beginOwnMakeRoomPreview();
      _install(first, _rows(0, 3));
      await tester.pump();
      expect(position.pixels, 27.0);
      expect(
        _ownFree(first, viewport, const Offset(40.0, 50.0)).painted,
        _near(6.5),
      );

      // The second controller's first scope takes the epoch the first's
      // did, and its preview vacates row 30.
      second.beginOwnMakeRoomPreview();
      _install(second, _rows(30, 3), key: "e");
      await tester.pumpWidget(_app(second));
      await tester.pump();
      expect(identical(viewport.controller, second), isTrue);
      expect(second.makeRoomOwnIdCount, greaterThan(0));
      const point = Offset(40.0, 50.0);
      second.debugOwnFreeMappingCount = 0;
      final ownFree = _ownFree(second, viewport, point);
      expect(second.debugOwnFreeMappingCount, 1);
      expect(ownFree.painted, _near(_painted(viewport, point).painted));
      second.releaseMakeRoomPreview();
      first.releaseMakeRoomPreview();
    },
  );

  testWidgets(
    "a scope opened in the frame another ended, during its spring-back, "
    "reads the scroll from its own start",
    (tester) async {
      final (controller, viewport) = await _vacateAtEnd(tester, 129.0);
      final position = viewport.verticalPosition!;
      final first = controller.beginOwnMakeRoomPreview();
      position.jumpTo(130.0);
      _install(controller, _rows(36, 4));
      await tester.pump();
      expect(position.pixels, greaterThan(112.0));
      for (var pump = 1; pump <= 4; pump++) {
        await tester.pump(_frame);
      }
      controller.endOwnMakeRoomPreview(first);
      controller.beginOwnMakeRoomPreview();
      _install(controller, _rows(36, 4));
      await tester.pump(_frame);
      final start = position.pixels;
      expect(start, lessThan(129.0));
      expect(start, greaterThan(112.0));
      // The new scope's preview is the same vacate, so without it the
      // board would rest where it stood when the scope began.
      const point = Offset(40.0, 236.0);
      var pumps = 0;
      while (true) {
        expect(
          _ownFree(controller, viewport, point).painted,
          _near((start + 236.0) / 10.0),
          reason: "pump $pumps, pixels ${position.pixels}",
        );
        if (position.pixels <= 112.0 || pumps == 60) {
          break;
        }
        await tester.pump(_frame);
        pumps += 1;
      }
      expect(position.pixels, 112.0);
    },
  );

  testWidgets(
    "a foreign shrink that clamps the scroll offset under an own vacate "
    "clamps the own-free offset into its own range",
    (tester) async {
      final (controller, viewport) = await _vacateAtEnd(
        tester,
        142.0,
        laneInRow38: true,
      );
      final position = viewport.verticalPosition!;
      expect(position.pixels, 142.0);
      controller.beginOwnMakeRoomPreview();
      _install(controller, _rows(36, 4));
      await tester.pump();
      expect(position.pixels, 124.0);
      const point = Offset(40.0, 236.0);
      expect(_ownFree(controller, viewport, point).painted, _near(37.8));
      // Row 38 loses its lane: 12 px off the end of the rows, below the
      // scroll anchor, which ends the range at 112 as the rows paint and
      // at 130 without the preview.
      controller.removeItem("x");
      await tester.pump();
      expect(position.pixels, 112.0);
      expect(_painted(viewport, point).painted, _near(34.8));
      expect(_ownFree(controller, viewport, point).painted, _near(36.6));
    },
  );

  testWidgets("a foreign shrink during an own vacate's spring-back springs the "
      "own-free offset back into its own range", (tester) async {
    final (controller, viewport) = await _vacateAtEnd(
      tester,
      141.0,
      laneInRow38: true,
    );
    final position = viewport.verticalPosition!;
    controller.beginOwnMakeRoomPreview();
    position.jumpTo(142.0);
    _install(controller, _rows(36, 4));
    await tester.pump();
    expect(position.pixels, greaterThan(124.0));
    controller.removeItem("x");
    await tester.pump();
    for (var pump = 1; pump <= 60 && position.pixels > 112.0; pump++) {
      await tester.pump(_frame);
    }
    expect(position.pixels, 112.0);
    viewport.markNeedsLayout();
    await tester.pump();
    const point = Offset(40.0, 236.0);
    expect(_painted(viewport, point).painted, _near(34.8));
    expect(_ownFree(controller, viewport, point).painted, _near(36.6));
  });

  testWidgets(
    "a zoom whose own-free leading edge lies in an own track anchors it "
    "at its own-free extent",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 40);
      _addDelaneItems(controller);
      final viewport = await _mount(tester, controller);
      final position = viewport.verticalPosition!;
      position.jumpTo(45.0);
      await tester.pump();
      controller.beginOwnMakeRoomPreview();
      _install(controller, _rows(0, 3));
      await tester.pump();
      expect(position.pixels, 27.0);
      position.jumpTo(10.0);
      await tester.pump();
      // 10 px into row 0 as it paints, 22 px; 28 px into it without the
      // preview, 40 px.
      const edge = Offset(40.0, 0.0);
      expect(_painted(viewport, edge).painted, _near(10.0 / 22.0));
      expect(_ownFree(controller, viewport, edge).painted, _near(0.7));
      // Both anchors land on the new 10 px estimates, at 4.55 and at 7.0,
      // before row 0 measures 22 as it paints and 40 without the preview.
      controller.rows = _laned(LazyContentAxis(40, 10.0));
      await tester.pump();
      expect(position.pixels, _near(100.0 / 22.0));
      expect(_painted(viewport, edge).painted, _near(100.0 / 22.0 / 22.0));
      expect(_ownFree(controller, viewport, edge).painted, _near(7.0 / 40.0));
    },
  );

  testWidgets(
    "a zoom with an own track in the leading band anchors the own-free "
    "leading edge of the scrolled tracks",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 40, frozenStart: 1);
      _addDelaneItems(controller);
      final viewport = await _mount(tester, controller);
      viewport.verticalPosition!.jumpTo(100.0);
      await tester.pump();
      controller.beginOwnMakeRoomPreview();
      _install(controller, _rows(0, 14));
      await tester.pump();
      const point = Offset(40.0, 62.0);
      expect(_ownFree(controller, viewport, point).visibleFrom, _near(11.0));
      controller.rows = _laned(LazyContentAxis(40, 10.0), frozenStart: 1);
      await tester.pump();
      expect(viewport.verticalPosition!.pixels, 100.0);
      expect(_painted(viewport, point).visibleFrom, _near(11.0));
      expect(_ownFree(controller, viewport, point).visibleFrom, _near(11.0));
    },
  );

  testWidgets(
    "the own-free sample over a leading band holding an own track reads "
    "its scrolled coordinate, its visible start and its extension own-free",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 40, frozenStart: 1);
      _addDelaneItems(controller);
      final viewport = await _mount(tester, controller);
      viewport.verticalPosition!.jumpTo(100.0);
      await tester.pump();
      controller.beginOwnMakeRoomPreview();
      _install(controller, _rows(0, 14));
      await tester.pump();
      expect(_rowExtent(viewport, 0), 22.0);
      // Without the preview row 0, the band, is 40 px, so the scrolled
      // rows show from 40, and row 1 starts at 40 in content.
      final inBand = _ownFree(controller, viewport, const Offset(40.0, 32.0));
      expect(inBand.band, (start: 0, end: 1));
      expect(inBand.painted, _near(0.8));
      expect(inBand.scrolled, _near(10.2));
      expect(inBand.visibleFrom, _near(11.0));
      final above = _ownFree(controller, viewport, const Offset(40.0, -10.0));
      expect(above.band, (start: 0, end: 1));
      expect(above.paintedExtended, _near(-0.25));
      expect(
        _painted(viewport, const Offset(40.0, -10.0)).paintedExtended,
        _near(-10.0 / 22.0),
      );
    },
  );

  testWidgets(
    "the own-free sample over a trailing band within the own preview's "
    "shrink of the rows' end reads the band's last track",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 40, frozenEnd: 3);
      _addDelaneItems(controller, row: 37);
      final viewport = await _mount(tester, controller);
      controller.beginOwnMakeRoomPreview();
      _install(controller, _rows(37, 2));
      await tester.pump();
      expect(_rowExtent(viewport, 37), 22.0);
      // The rows end at 412 as they paint and at 430 without the preview,
      // so the band's last 5 px read 425 of 430, half way into row 39.
      const point = Offset(40.0, 295.0);
      expect(_painted(viewport, point).painted, _near(39.5));
      final ownFree = _ownFree(controller, viewport, point);
      expect(ownFree.band, (start: 37, end: 40));
      expect(ownFree.painted, _near(39.5));
    },
  );

  testWidgets(
    "the own-free sample over a trailing band reads its coordinates, its "
    "visible end and its extension own-free",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 40, frozenEnd: 3);
      _addDelaneItems(controller, row: 39);
      _add(
        controller,
        "f",
        const BoardSpan(rowStart: 5, colStart: 0, colSpan: 4),
      );
      final viewport = await _mount(tester, controller);
      controller.beginOwnMakeRoomPreview();
      // `d` joins row 5 beside `f`, growing it to 40, and vacates row 39,
      // the band's last, to 22.
      _install(
        controller,
        const BoardSpan(rowStart: 5, colStart: 0, colSpan: 5),
      );
      await tester.pump();
      expect(_rowExtent(viewport, 5), 40.0);
      expect(_rowExtent(viewport, 39), 22.0);
      // Without the preview row 5 is 22 and row 39 is 40: the band is 60
      // px, so the scrolled rows show to 240, row 6 starts at 72 and row
      // 39 at 402 of 442.
      final inBand = _ownFree(controller, viewport, const Offset(40.0, 250.0));
      expect(inBand.band, (start: 37, end: 40));
      expect(inBand.painted, _near(38.0));
      expect(inBand.scrolled, _near(23.8));
      expect(inBand.visibleTo, _near(22.8));
      expect(
        _ownFree(controller, viewport, const Offset(40.0, 285.0)).painted,
        _near(39.625),
      );
      expect(
        _ownFree(
          controller,
          viewport,
          const Offset(40.0, 310.0),
        ).paintedExtended,
        _near(40.25),
      );
    },
  );
}
