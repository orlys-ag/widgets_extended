/// The render's own-free lattice: while the make-room engine's
/// own-preview scope has a preview standing, a sample taken without it
/// reads every content-axis track at the extent it would have without
/// that preview, at the scroll offset the board would have without it,
/// and frozen bands at their own-free extents; with none standing it
/// reads the lattice as it paints, at the painted path's cost. The own
/// work a layout does grows with the tracks the preview changes.
///
/// Points are paint space in the board's frame.
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
  double estimate = 80.0,
  int frozenStart = 0,
  int frozenEnd = 0,
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(rowCount, estimate),
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

/// Mounts [controller] in a 280 x 300 frame of 40 x 10 cells, settles
/// it, and unmounts before the controller's own teardown disposes it.
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
            key: ObjectKey(controller),
            width: 280.0,
            height: 300.0,
            child: Board<String, _Item>(
              controller: controller,
              cellBuilder: (context, view) {
                return const SizedBox(width: 40.0, height: 10.0);
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
  await tester.pumpAndSettle(_frame);
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

/// Items that a resize of `d`'s leading edge into row 1 lanes `d` among:
/// `a` laned in row 1, so row 1 is 22 px, and `d` on rows [0, 2),
/// unlaned.
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

/// Items that a resize of `d`'s trailing edge out of [row] de-lanes `d`
/// from: `a` and `d` laned in [row], so it is 40 px, `d` on lane 0.
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

/// One single-row item laned in each of rows 3, 4 and 5 at columns
/// [5, 7).
void _addThreeLaned(BoardController<String, _Item> controller) {
  for (var row = 3; row <= 5; row++) {
    controller.addItem(
      _Item("x$row"),
      BoardSpan(rowStart: row, colStart: 5, colSpan: 2),
    );
  }
}

const BoardSpan _joinSpan = BoardSpan(rowStart: 1, colStart: 0, colSpan: 5);

const BoardSpan _joinStored = BoardSpan(
  rowStart: 0,
  colStart: 0,
  rowSpan: 2,
  colSpan: 5,
);

void _install(BoardController<String, _Item> controller, BoardSpan span) {
  controller.previewMakeRoomGap(draggedKey: "d", prospective: span);
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

/// The lane bucket member reads of one forced layout of [viewport].
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

/// The Fenwick operations of one row sample at [local], own-free when
/// [ownFree] and painted otherwise.
int _opsOfSample(
  BoardController<String, _Item> controller,
  RenderBoardViewport<String> viewport,
  Offset local, {
  required bool ownFree,
}) {
  final fenwick = (controller.rows.axis as LazyContentAxis).debugFenwick;
  fenwick.debugOpCount = 0;
  if (ownFree) {
    controller.trackSampleWithoutOwnPreview(viewport, local);
  } else {
    viewport.trackSampleAt(local);
  }
  return fenwick.debugOpCount;
}

/// Forty content-sized rows under [_animated] with [_addDelaneItems]'
/// items in row 0, a scope open, `d` installed at rows [0, 3) and the
/// rows scrolled to 45, so the vacate above the anchor pulls the pixels
/// from 45 to 27 over 20 pumps.
Future<(BoardController<String, _Item>, RenderBoardViewport<String>, int)>
_vacateAboveAnchor(WidgetTester tester) async {
  final controller = _rowsLaned(tester, rowCount: 40, style: _animated);
  _addDelaneItems(controller);
  final viewport = await _mount(tester, controller);
  final epoch = controller.beginOwnMakeRoomPreview();
  _install(
    controller,
    const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 3, colSpan: 5),
  );
  viewport.verticalPosition!.jumpTo(45.0);
  return (controller, viewport, epoch);
}

/// Forty content-sized rows under motion off with [_addDelaneItems]'
/// items in row 39, at the scroll offset [pixels] after one pump.
Future<(BoardController<String, _Item>, RenderBoardViewport<String>)>
_vacateAtEnd(WidgetTester tester, double pixels) async {
  final controller = _rowsLaned(tester, rowCount: 40);
  _addDelaneItems(controller, row: 39);
  final viewport = await _mount(tester, controller);
  viewport.verticalPosition!.jumpTo(pixels);
  await tester.pump();
  return (controller, viewport);
}

const BoardSpan _endTarget = BoardSpan(
  rowStart: 36,
  colStart: 0,
  rowSpan: 4,
  colSpan: 5,
);

void main() {
  testWidgets(
    "the own-free sample under a standing own preview reads the lattice at "
    "rest",
    (tester) async {
      final controller = _rowsLaned(tester);
      _addJoinItems(controller);
      final viewport = await _mount(tester, controller);
      controller.beginOwnMakeRoomPreview();
      _install(controller, _joinSpan);
      await tester.pump();
      const point = Offset(40.0, 20.0);
      expect(
        _ownFree(controller, viewport, point).painted,
        moreOrLessEquals(1.0 + 10.0 / 22.0, epsilon: 1e-9),
      );
      expect(
        _painted(viewport, point).painted,
        moreOrLessEquals(1.25, epsilon: 1e-9),
      );
      expect(_rowExtent(viewport, 1), 40.0);
    },
  );

  group("the own-free sample holds through the scroll its own preview "
      "causes", () {
    testWidgets("(a) a vacate above the anchor", (tester) async {
      final (controller, viewport, _) = await _vacateAboveAnchor(tester);
      final position = viewport.verticalPosition!;
      const point = Offset(40.0, 50.0);
      for (var pump = 1; pump <= 20; pump++) {
        await tester.pump(_frame);
        expect(
          _ownFree(controller, viewport, point).painted,
          moreOrLessEquals(6.5, epsilon: 1e-9),
          reason: "pump $pump, pixels ${position.pixels}",
        );
      }
      expect(position.pixels, moreOrLessEquals(27.0, epsilon: 1e-9));
    });

    testWidgets("(b) a vacate that clamps the scroll offset", (tester) async {
      final (controller, viewport) = await _vacateAtEnd(tester, 130.0);
      controller.beginOwnMakeRoomPreview();
      _install(controller, _endTarget);
      await tester.pump();
      const point = Offset(40.0, 236.0);
      expect(viewport.verticalPosition!.pixels, 112.0);
      expect(
        _ownFree(controller, viewport, point).painted,
        moreOrLessEquals(36.6, epsilon: 1e-9),
      );
      expect(
        _painted(viewport, point).painted,
        moreOrLessEquals(34.8, epsilon: 1e-9),
      );
    });

    testWidgets("(c) a vacate that leaves an overscroll", (tester) async {
      final (controller, viewport) = await _vacateAtEnd(tester, 129.0);
      final position = viewport.verticalPosition!;
      controller.beginOwnMakeRoomPreview();
      position.jumpTo(130.0);
      _install(controller, _endTarget);
      await tester.pump();
      expect(position.pixels, greaterThan(112.0));
      const point = Offset(40.0, 236.0);
      var pumps = 0;
      while (true) {
        expect(
          _ownFree(controller, viewport, point).painted,
          moreOrLessEquals(36.6, epsilon: 1e-9),
          reason: "pump $pumps, pixels ${position.pixels}",
        );
        if (position.pixels <= 112.0 || pumps == 60) {
          break;
        }
        await tester.pump(_frame);
        pumps += 1;
      }
      expect(position.pixels, 112.0);
    });

    testWidgets("(d) between a spring tick and its layout", (tester) async {
      final (controller, viewport) = await _vacateAtEnd(tester, 129.0);
      final position = viewport.verticalPosition!;
      controller.beginOwnMakeRoomPreview();
      position.jumpTo(130.0);
      _install(controller, _endTarget);
      await tester.pump();
      const point = Offset(40.0, 236.0);
      final samples = <(double, double)>[];
      void listener() {
        samples.add((
          position.pixels,
          _ownFree(controller, viewport, point).painted,
        ));
      }

      position.addListener(listener);
      addTearDown(() {
        position.removeListener(listener);
      });
      for (var pump = 1; pump <= 60 && position.pixels > 112.0; pump++) {
        await tester.pump(_frame);
      }
      for (final (pixels, painted) in samples) {
        expect(
          painted,
          moreOrLessEquals(36.6, epsilon: 1e-9),
          reason: "pixels $pixels",
        );
      }
      expect(
        samples.where((sample) {
          return sample.$1 > 112.0 && sample.$1 < 130.0;
        }),
        isNotEmpty,
      );
    });
  });

  testWidgets(
    "the own-free sample reads a frozen band at its own-free extent",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 40, frozenStart: 1);
      _addDelaneItems(controller);
      final viewport = await _mount(tester, controller);
      viewport.verticalPosition!.jumpTo(100.0);
      await tester.pump();
      controller.beginOwnMakeRoomPreview();
      _install(
        controller,
        const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 14, colSpan: 5),
      );
      await tester.pump();
      final inBand = _ownFree(controller, viewport, const Offset(40.0, 32.0));
      expect(inBand.band, (start: 0, end: 1));
      expect(inBand.painted, moreOrLessEquals(0.8, epsilon: 1e-9));
      expect(_painted(viewport, const Offset(40.0, 32.0)).band, isNull);
      expect(
        _ownFree(controller, viewport, const Offset(40.0, 62.0)).painted,
        moreOrLessEquals(13.2, epsilon: 1e-9),
      );
    },
  );

  testWidgets(
    "the own-free sample reads a trailing frozen band at its own-free extent",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 40, frozenEnd: 3);
      _addDelaneItems(controller, row: 37);
      final viewport = await _mount(tester, controller);
      expect(viewport.rectOfCell(37, 0), const Rect.fromLTRB(0, 240, 40, 280));
      controller.beginOwnMakeRoomPreview();
      _install(
        controller,
        const BoardSpan(rowStart: 37, colStart: 0, rowSpan: 2, colSpan: 5),
      );
      await tester.pump();
      expect(viewport.rectOfCell(37, 0), const Rect.fromLTRB(0, 258, 40, 280));
      final inBand = _ownFree(controller, viewport, const Offset(40.0, 250.0));
      expect(inBand.band, (start: 37, end: 40));
      expect(inBand.painted, moreOrLessEquals(37.25, epsilon: 1e-9));
      expect(_painted(viewport, const Offset(40.0, 250.0)).band, isNull);
      expect(
        _ownFree(controller, viewport, const Offset(40.0, 270.0)).painted,
        moreOrLessEquals(37.75, epsilon: 1e-9),
      );
      expect(
        _painted(viewport, const Offset(40.0, 270.0)).painted,
        moreOrLessEquals(37.0 + 12.0 / 22.0, epsilon: 1e-9),
      );
    },
  );

  group("the own scroll shift resets with the own data and follows the zoom "
      "anchor", () {
    /// [_vacateAboveAnchor]'s board after its 20 pumps: pixels 27, the
    /// shift -18, nothing in motion.
    Future<(BoardController<String, _Item>, RenderBoardViewport<String>, int)>
    settled(WidgetTester tester) async {
      final (controller, viewport, epoch) = await _vacateAboveAnchor(tester);
      for (var pump = 1; pump <= 20; pump++) {
        await tester.pump(_frame);
      }
      expect(
        viewport.verticalPosition!.pixels,
        moreOrLessEquals(27.0, epsilon: 1e-9),
      );
      return (controller, viewport, epoch);
    }

    void expectSamples(
      BoardController<String, _Item> controller,
      RenderBoardViewport<String> viewport,
    ) {
      const point = Offset(40.0, 50.0);
      expect(
        _ownFree(controller, viewport, point).painted,
        moreOrLessEquals(6.5, epsilon: 1e-9),
      );
      expect(
        _painted(viewport, point).painted,
        moreOrLessEquals(6.5, epsilon: 1e-9),
      );
    }

    testWidgets("(a) at a scope's end", (tester) async {
      final (controller, viewport, epoch) = await settled(tester);
      controller.endOwnMakeRoomPreview(epoch);
      viewport.markNeedsLayout();
      await tester.pump();
      expectSamples(controller, viewport);
    });

    testWidgets("(b) at a new scope", (tester) async {
      final (controller, viewport, _) = await settled(tester);
      // The closing re-targets of `d`'s vacate and `a`'s offset join the
      // new scope with their whole values as remainders, so row 0 is own
      // at a zero delta.
      controller.beginOwnMakeRoomPreview();
      _install(
        controller,
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 5),
      );
      await tester.pump();
      expectSamples(controller, viewport);
      await tester.pumpAndSettle(_frame);
    });

    testWidgets("(c) at a new axis instance whose two anchors agree", (
      tester,
    ) async {
      final (controller, viewport, _) = await settled(tester);
      // The painted leading edge, 27 over row 0's 22 px, and the own-free
      // one, 45 over its 40 px, both read row 1.5, so both anchor at 15 on
      // the new 10 px estimates and the shift starts at zero.
      controller.rows = BoardAxisConfig(
        axis: LazyContentAxis(40, 10.0),
        laneExtent: 18.0,
        lanePadding: 4.0,
      );
      await tester.pump();
      expect(
        viewport.verticalPosition!.pixels,
        moreOrLessEquals(15.0, epsilon: 1e-9),
      );
      const point = Offset(40.0, 50.0);
      expect(
        _ownFree(controller, viewport, point).painted,
        moreOrLessEquals(3.5, epsilon: 1e-9),
      );
      expect(
        _painted(viewport, point).painted,
        moreOrLessEquals(5.3, epsilon: 1e-9),
      );
    });

    testWidgets("(d) at a new axis instance whose two anchors differ", (
      tester,
    ) async {
      final (controller, viewport) = await _vacateAtEnd(tester, 130.0);
      controller.beginOwnMakeRoomPreview();
      _install(controller, _endTarget);
      await tester.pump();
      expect(viewport.verticalPosition!.pixels, 112.0);
      // The painted leading edge reads row 11.2 and the own-free one, at
      // 130, row 13.0, so the anchors are 112 and 130 on the new instance
      // and the shift stays -18.
      controller.rows = BoardAxisConfig(
        axis: LazyContentAxis(50, 10.0),
        laneExtent: 18.0,
        lanePadding: 4.0,
      );
      await tester.pump();
      expect(viewport.verticalPosition!.pixels, 112.0);
      const point = Offset(40.0, 236.0);
      expect(
        _ownFree(controller, viewport, point).painted,
        moreOrLessEquals(36.6, epsilon: 1e-9),
      );
      expect(
        _painted(viewport, point).painted,
        moreOrLessEquals(34.8, epsilon: 1e-9),
      );
    });
  });

  testWidgets(
    "an axis instance change whose zoom anchor computes no target resets the "
    "own scroll shift to zero",
    (tester) async {
      final (controller, viewport) = await _vacateAtEnd(tester, 130.0);
      final position = viewport.verticalPosition!;
      controller.beginOwnMakeRoomPreview();
      _install(controller, _endTarget);
      await tester.pump();
      expect(position.pixels, 112.0);
      BoardAxisConfig rows(int count) {
        return BoardAxisConfig(
          axis: LazyContentAxis(count, 10.0),
          laneExtent: 18.0,
          lanePadding: 4.0,
        );
      }

      // An anchor that computes both targets, keeping the shift at -18.
      controller.rows = rows(50);
      await tester.pump();
      const point = Offset(40.0, 236.0);
      expect(
        _ownFree(controller, viewport, point).painted,
        moreOrLessEquals(36.6, epsilon: 1e-9),
      );
      // Two anchors that compute none, onto an empty axis and from it.
      controller.rows = rows(0);
      await tester.pump();
      expect(position.pixels, 0.0);
      controller.rows = rows(50);
      await tester.pump();
      expect(position.pixels, 0.0);
      const above = Offset(40.0, 50.0);
      expect(
        _ownFree(controller, viewport, above).painted,
        moreOrLessEquals(5.0, epsilon: 1e-9),
      );
      expect(
        _painted(viewport, above).painted,
        moreOrLessEquals(5.0, epsilon: 1e-9),
      );
    },
  );

  testWidgets(
    "a measurement reset of the content axis instance drops the own deltas "
    "and keeps the own scroll shift",
    (tester) async {
      final controller = _rowsLaned(tester, rowCount: 100, estimate: 10.0);
      _addDelaneItems(controller);
      final viewport = await _mount(tester, controller);
      final position = viewport.verticalPosition!;
      position.jumpTo(45.0);
      await tester.pump();
      controller.beginOwnMakeRoomPreview();
      _install(
        controller,
        const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 3, colSpan: 5),
      );
      await tester.pump();
      expect(position.pixels, 27.0);
      // Row 0, the own track, now lies outside every window a pass sizes.
      position.jumpTo(600.0);
      await tester.pump();
      const point = Offset(40.0, 50.0);
      expect(
        _ownFree(controller, viewport, point).painted,
        moreOrLessEquals(63.8, epsilon: 1e-9),
      );
      expect(_rowExtent(viewport, 0), 22.0);
      // The same instance under another lane padding, whose setter resets
      // the instance's measurements.
      controller.rows = BoardAxisConfig(
        axis: controller.rows.axis,
        laneExtent: 18.0,
        lanePadding: 6.0,
      );
      await tester.pump();
      expect(position.pixels, 600.0);
      expect(_rowExtent(viewport, 0), 10.0);
      expect(
        _painted(viewport, point).painted,
        moreOrLessEquals(65.0, epsilon: 1e-9),
      );
      expect(
        _ownFree(controller, viewport, point).painted,
        moreOrLessEquals(66.8, epsilon: 1e-9),
      );
    },
  );

  testWidgets(
    "a sample between a measurement reset and the next layout reads the "
    "painted lattice",
    (tester) async {
      final controller = _rowsLaned(tester);
      _addJoinItems(controller);
      final viewport = await _mount(tester, controller);
      controller.beginOwnMakeRoomPreview();
      _install(controller, _joinSpan);
      await tester.pump();
      expect(
        _ownFree(controller, viewport, const Offset(40.0, 20.0)).painted,
        moreOrLessEquals(1.0 + 10.0 / 22.0, epsilon: 1e-9),
      );
      // The same instance under another lane padding: the setter resets
      // the instance's measurements to the 80 px estimate, and no layout
      // has run since.
      controller.rows = BoardAxisConfig(
        axis: controller.rows.axis,
        laneExtent: 18.0,
        lanePadding: 6.0,
      );
      const point = Offset(40.0, 100.0);
      expect(
        _painted(viewport, point).painted,
        moreOrLessEquals(1.25, epsilon: 1e-9),
      );
      expect(
        _ownFree(controller, viewport, point).painted,
        moreOrLessEquals(1.25, epsilon: 1e-9),
      );
    },
  );

  testWidgets(
    "a standing own preview adds one lane-term read per own track per pass",
    (tester) async {
      for (final extra in <bool>[false, true]) {
        final controller = _rowsLaned(tester);
        _addJoinItems(controller);
        if (extra) {
          _addThreeLaned(controller);
        }
        final viewport = await _mount(tester, controller);
        final epoch = controller.beginOwnMakeRoomPreview();
        _install(controller, _joinSpan);
        await tester.pump();
        expect(_rowExtent(viewport, 1), 40.0);
        final joinScoped = await _readsOverForcedLayout(
          tester,
          controller,
          viewport,
        );
        _install(controller, _joinStored);
        await tester.pump();
        final storedScoped = await _readsOverForcedLayout(
          tester,
          controller,
          viewport,
        );
        controller.endOwnMakeRoomPreview(epoch);
        _install(controller, _joinSpan);
        await tester.pump();
        expect(_rowExtent(viewport, 1), 40.0);
        final join = await _readsOverForcedLayout(tester, controller, viewport);
        _install(controller, _joinStored);
        await tester.pump();
        final stored = await _readsOverForcedLayout(
          tester,
          controller,
          viewport,
        );
        expect(joinScoped - join, 1, reason: "extra $extra");
        expect(storedScoped - stored, 0, reason: "extra $extra");
        controller.releaseMakeRoomPreview();
      }
    },
  );

  group("with no own preview standing the own-free sample takes no own-free "
      "mode", () {
    testWidgets("before a preview, after it closes and after its scope "
        "ends", (tester) async {
      final controller = _rowsLaned(tester);
      _addJoinItems(controller);
      final viewport = await _mount(tester, controller);
      const point = Offset(40.0, 20.0);
      void expectPaintedCost(String state) {
        final painted = _opsOfSample(
          controller,
          viewport,
          point,
          ownFree: false,
        );
        controller.debugOwnFreeMappingCount = 0;
        final ownFree = _opsOfSample(
          controller,
          viewport,
          point,
          ownFree: true,
        );
        expect(controller.debugOwnFreeMappingCount, 0, reason: state);
        expect(painted, 8, reason: state);
        expect(ownFree, painted, reason: state);
      }

      expectPaintedCost("no scope");
      final epoch = controller.beginOwnMakeRoomPreview();
      expectPaintedCost("a scope and no install");
      _install(controller, _joinSpan);
      await tester.pump();
      // The preview standing: the row axis's one mapping takes the mode,
      // and its segment search reads the own starts, no axis offset.
      controller.debugOwnFreeMappingCount = 0;
      expect(_opsOfSample(controller, viewport, point, ownFree: true), 8);
      expect(controller.debugOwnFreeMappingCount, 1);
      _install(controller, _joinStored);
      await tester.pump();
      expectPaintedCost("the scope open after the preview stood and closed");
      _install(controller, _joinSpan);
      await tester.pump();
      controller.endOwnMakeRoomPreview(epoch);
      expectPaintedCost("the preview standing after the scope's end");
    });

    testWidgets("after a scroll a closed preview left", (tester) async {
      final (controller, viewport) = await _vacateAtEnd(tester, 130.0);
      final position = viewport.verticalPosition!;
      controller.beginOwnMakeRoomPreview();
      _install(controller, _endTarget);
      await tester.pump();
      expect(position.pixels, 112.0);
      _install(
        controller,
        const BoardSpan(rowStart: 39, colStart: 0, colSpan: 5),
      );
      await tester.pump();
      expect(position.pixels, 112.0);
      expect(controller.makeRoomOwnIdCount, 0);
      expect(controller.makeRoomOwnSlotTrackCount, 0);
      const point = Offset(40.0, 236.0);
      controller.debugOwnFreeMappingCount = 0;
      final ownFree = _ownFree(controller, viewport, point);
      expect(controller.debugOwnFreeMappingCount, 0);
      expect(ownFree.painted, moreOrLessEquals(34.8, epsilon: 1e-9));
      expect(
        _painted(viewport, point).painted,
        moreOrLessEquals(34.8, epsilon: 1e-9),
      );
    });
  });

  testWidgets(
    "with a scope open and no own preview standing a layout reads the axis "
    "as with no scope",
    (tester) async {
      final ops = <bool, List<int>>{};
      for (final scoped in <bool>[false, true]) {
        final controller = _rowsLaned(tester);
        _addJoinItems(controller);
        final viewport = await _mount(tester, controller);
        final fenwick = (controller.rows.axis as LazyContentAxis).debugFenwick;
        Future<int> opsOverForcedLayout() async {
          fenwick.debugOpCount = 0;
          viewport.markNeedsLayout();
          await tester.pump();
          return fenwick.debugOpCount;
        }

        if (scoped) {
          controller.beginOwnMakeRoomPreview();
        }
        final idle = await opsOverForcedLayout();
        // The install a resize's first resolve makes, at its stored span.
        _install(controller, _joinStored);
        await tester.pump();
        final stored = await opsOverForcedLayout();
        ops[scoped] = <int>[idle, stored];
        controller.releaseMakeRoomPreview();
      }
      expect(ops[true], ops[false]);
    },
  );

  testWidgets(
    "an own track whose pairs dropped takes a zero delta with no own-free "
    "evaluation",
    (tester) async {
      final reads = <bool, int>{};
      for (final scoped in <bool>[true, false]) {
        final controller = _rowsLaned(tester);
        _addJoinItems(controller);
        final viewport = await _mount(tester, controller);
        if (scoped) {
          controller.beginOwnMakeRoomPreview();
        }
        _install(controller, _joinSpan);
        await tester.pump();
        _install(controller, _joinStored);
        controller.debugLaneBucketMemberReadCount = 0;
        await tester.pump();
        reads[scoped] = controller.debugLaneBucketMemberReadCount;
        expect(_rowExtent(viewport, 1), 22.0);
      }
      expect(reads[true], reads[false]);
    },
  );

  testWidgets(
    "an axis instance change with no own preview standing reads the old "
    "instance as the painted zoom anchor does",
    (tester) async {
      final counts = <int>[];
      for (final arm in <int>[1, 2, 3]) {
        final controller = _rowsLaned(tester, rowCount: 40);
        _addDelaneItems(controller);
        final viewport = await _mount(tester, controller);
        final position = viewport.verticalPosition!;
        position.jumpTo(45.0);
        await tester.pump();
        if (arm > 1) {
          controller.beginOwnMakeRoomPreview();
          _install(
            controller,
            const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 3, colSpan: 5),
          );
          await tester.pump();
          expect(position.pixels, 27.0, reason: "arm $arm");
          if (arm == 2) {
            _install(
              controller,
              const BoardSpan(rowStart: 0, colStart: 0, colSpan: 5),
            );
            await tester.pump();
            expect(position.pixels, 45.0, reason: "arm $arm");
          }
        }
        final held = controller.rows.axis as LazyContentAxis;
        controller.rows = BoardAxisConfig(
          axis: LazyContentAxis(40, 10.0),
          laneExtent: 18.0,
          lanePadding: 4.0,
        );
        held.debugFenwick.debugOpCount = 0;
        await tester.pump();
        counts.add(held.debugFenwick.debugOpCount);
        controller.releaseMakeRoomPreview();
      }
      expect(counts[1], counts[0], reason: "$counts");
      expect(counts[2], greaterThan(counts[0]), reason: "$counts");
    },
  );
}
