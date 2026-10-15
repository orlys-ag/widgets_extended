/// A resize resolves again only when the pointer's sample on its resized
/// axis moved by more than the tolerance, so a sample that rounds on a
/// tie does not flip the target between two spans while the pointer
/// stays where it is.
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
import 'package:widgets_extended/board/board_render_port.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

const Duration _frame = Duration(milliseconds: 16);

/// The viewport behind a port that, once [counting], shifts the row
/// sample of every sample it takes by [shift]: added on the odd-numbered
/// ones, counted from 1, and subtracted on the even ones.
class _JitterPort implements BoardRenderPort<String> {
  _JitterPort(this._inner);

  final RenderBoardViewport<String> _inner;

  static const double shift = 1e-12;

  bool counting = false;
  int _samples = 0;

  @override
  ({BoardAxisSample row, BoardAxisSample col})? trackSampleAt(
    Offset local, {
    double? verticalPixels,
    double? horizontalPixels,
  }) {
    final sample = _inner.trackSampleAt(
      local,
      verticalPixels: verticalPixels,
      horizontalPixels: horizontalPixels,
    );
    if (sample == null || !counting) {
      return sample;
    }
    _samples += 1;
    final delta = _samples.isOdd ? shift : -shift;
    final row = sample.row;
    return (
      row: (
        painted: row.painted + delta,
        paintedExtended: row.paintedExtended + delta,
        scrolled: row.scrolled + delta,
        scrollPixels: row.scrollPixels,
        band: row.band,
        visibleFrom: row.visibleFrom,
        visibleTo: row.visibleTo,
        trackCount: row.trackCount,
        leadingBandEnd: row.leadingBandEnd,
        trailingBandStart: row.trailingBandStart,
      ),
      col: sample.col,
    );
  }

  @override
  bool get isLaidOut {
    return _inner.isLaidOut;
  }

  @override
  Size get viewportDimension {
    return _inner.viewportDimension;
  }

  @override
  bool drivesController(Object boardController) {
    return _inner.drivesController(boardController);
  }

  @override
  void pinItem(String key) {
    _inner.pinItem(key);
  }

  @override
  void unpinItem(String key) {
    _inner.unpinItem(key);
  }

  @override
  ({int row, int col})? cellAt(Offset local) {
    return _inner.cellAt(local);
  }

  @override
  ({int row, int col})? frozenCellAt(Offset local) {
    return _inner.frozenCellAt(local);
  }

  @override
  Rect? rectOfCell(int row, int col) {
    return _inner.rectOfCell(row, col);
  }

  @override
  String? itemAt(Offset local) {
    return _inner.itemAt(local);
  }

  @override
  Rect? rectOfItem(String key) {
    return _inner.rectOfItem(key);
  }

  @override
  Rect? paintedRectOfItem(String key) {
    return _inner.paintedRectOfItem(key);
  }

  @override
  Offset contentDeltaFromPaint(Offset paintDelta) {
    return _inner.contentDeltaFromPaint(paintDelta);
  }

  @override
  Offset leadingCornerOf(Rect paintRect) {
    return _inner.leadingCornerOf(paintRect);
  }

  @override
  ({int row, int col}) resolveDropCell(Offset local) {
    return _inner.resolveDropCell(local);
  }

  @override
  ({double row, double col})? trackSpaceAt(Offset local) {
    return _inner.trackSpaceAt(local);
  }

  @override
  Offset globalToPaintLocal(Offset global) {
    return _inner.globalToPaintLocal(global);
  }

  @override
  ScrollPosition? get verticalPosition {
    return _inner.verticalPosition;
  }

  @override
  ScrollPosition? get horizontalPosition {
    return _inner.horizontalPosition;
  }

  @override
  double frozenInsetOf(Axis axis) {
    return _inner.frozenInsetOf(axis);
  }

  @override
  Rect get scrolledRegion {
    return _inner.scrolledRegion;
  }

  @override
  void invalidateCellMeasurements() {
    _inner.invalidateCellMeasurements();
  }
}

/// The viewport behind a port whose row samples read half a track
/// further on than the viewport's.
class _ShiftedPort extends _JitterPort {
  _ShiftedPort(super.inner);

  @override
  ({BoardAxisSample row, BoardAxisSample col})? trackSampleAt(
    Offset local, {
    double? verticalPixels,
    double? horizontalPixels,
  }) {
    final sample = _inner.trackSampleAt(
      local,
      verticalPixels: verticalPixels,
      horizontalPixels: horizontalPixels,
    );
    if (sample == null) {
      return null;
    }
    final row = sample.row;
    return (
      row: (
        painted: row.painted + 0.5,
        paintedExtended: row.paintedExtended + 0.5,
        scrolled: row.scrolled + 0.5,
        scrollPixels: row.scrollPixels,
        band: row.band,
        visibleFrom: row.visibleFrom,
        visibleTo: row.visibleTo,
        trackCount: row.trackCount,
        leadingBandEnd: row.leadingBandEnd,
        trailingBandStart: row.trailingBandStart,
      ),
      col: sample.col,
    );
  }
}

/// Seven 40 px rows over seven 40 px columns with `m` at row 0, column
/// 1, mounted in a 280 x 300 frame and unmounted before the controller's
/// own teardown disposes it. Returns the frame's top-left too.
Future<(BoardController<String, _Item>, RenderBoardViewport<String>, Offset)>
_mountUniform(WidgetTester tester) async {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  controller.addItem(
    const _Item("m"),
    const BoardSpan(rowStart: 0, colStart: 1),
  );
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
              cellBuilder: (context, view) {
                return const SizedBox(width: 40.0, height: 40.0);
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
  final viewport = tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
  return (controller, viewport, tester.getRect(find.byKey(_frameKey)).topLeft);
}

/// A resize config under [snap] with no autoscroll and every edge.
BoardDragConfig<String> _resizeConfig(
  BoardController<String, _Item> controller,
  BoardSnap snap,
) {
  return BoardDragConfig<String>(
    snap: snap,
    autoScrollEdgeZone: 0.0,
    resizeEdges: BoardResizeEdges.both,
    primaryResizeEdges: BoardResizeEdges.both,
    onItemMoved: (key, span) {},
    onItemResized: (key, span) {
      controller.resizeItem(key, span);
    },
  );
}

void main() {
  testWidgets(
    "a resize sample within the tolerance of the last one resolves nothing",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
        columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 0, colStart: 1),
      );
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
                  cellBuilder: (context, view) {
                    return const SizedBox(width: 40.0, height: 40.0);
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
      final viewport = tester.allRenderObjects
          .whereType<RenderBoardViewport<String>>()
          .single;
      final drag = BoardDragController<String>(
        boardController: controller,
        vsync: tester,
        config: BoardDragConfig<String>(
          autoScrollEdgeZone: 0.0,
          resizeEdges: BoardResizeEdges.both,
          primaryResizeEdges: BoardResizeEdges.both,
          onItemMoved: (key, span) {},
          onItemResized: (key, span) {
            controller.resizeItem(key, span);
          },
        ),
      );
      addTearDown(drag.dispose);
      final frame = tester.getRect(find.byKey(_frameKey)).topLeft;
      final port = _JitterPort(viewport);
      expect(
        drag.startDrag(
          key: "m",
          renderPort: port,
          pointerGlobal: frame + const Offset(60.0, 20.0),
          edge: BoardResizeEdges.trailing,
          axis: Axis.vertical,
        ),
        isTrue,
      );
      port.counting = true;
      const target = BoardSpan(rowStart: 0, colStart: 1, rowSpan: 3);
      drag.updateDrag(frame + const Offset(60.0, 80.0));
      expect(drag.currentTarget?.span, target);
      for (var pump = 1; pump <= 6; pump++) {
        await tester.pump(_frame);
        expect(drag.currentTarget?.span, target, reason: "pump $pump");
      }
      drag.endDrag(cancel: true);
    },
  );

  testWidgets("a resize started where the last one ended resolves at once", (
    tester,
  ) async {
    final (controller, viewport, frame) = await _mountUniform(tester);
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: _resizeConfig(controller, const BoardSnap.track()),
    );
    addTearDown(drag.dispose);
    const stored = BoardSpan(rowStart: 0, colStart: 1);
    for (final session in <int>[1, 2]) {
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: frame + const Offset(60.0, 20.0),
          edge: BoardResizeEdges.trailing,
          axis: Axis.vertical,
        ),
        isTrue,
      );
      expect(drag.currentTarget?.span, stored, reason: "session $session");
      drag.endDrag(cancel: true);
    }
  });

  testWidgets("a config change resolves a resize again under a still pointer", (
    tester,
  ) async {
    final (controller, viewport, frame) = await _mountUniform(tester);
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: _resizeConfig(controller, const BoardSnap.track()),
    );
    addTearDown(drag.dispose);
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: frame + const Offset(60.0, 20.0),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      ),
      isTrue,
    );
    // From row 0.5 to row 1.75: the end moves from 1 to 2.25, which the
    // track snap puts at 2 and a quarter-track snap at 2.25.
    drag.updateDrag(frame + const Offset(60.0, 70.0));
    expect(
      drag.currentTarget?.span,
      const BoardSpan(rowStart: 0, colStart: 1, rowSpan: 2),
    );
    drag.config = _resizeConfig(controller, const BoardSnap.fraction(0.25));
    await tester.pump(_frame);
    expect(
      drag.currentTarget?.span,
      const BoardSpan(
        rowStart: 0,
        colStart: 1,
        rowSpan: 2,
        rowSpanFraction: 0.25,
      ),
    );
    drag.endDrag(cancel: true);
  });

  testWidgets(
    "a resize through a port that is not the board's samples that port",
    (tester) async {
      final (controller, viewport, _) = await _mountUniform(tester);
      final port = _ShiftedPort(viewport);
      const point = Offset(60.0, 20.0);
      expect(viewport.trackSampleAt(point)!.row.painted, 0.5);
      expect(
        controller.trackSampleWithoutOwnPreview(viewport, point)!.row.painted,
        0.5,
      );
      expect(
        controller.trackSampleWithoutOwnPreview(port, point)!.row.painted,
        1.0,
      );
    },
  );
}
