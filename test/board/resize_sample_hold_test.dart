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
}
