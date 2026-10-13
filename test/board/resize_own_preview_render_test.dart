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

/// Criterion 1's items: `a` laned in row 1, so row 1 is 22 px, and `d`
/// on rows [0, 2), unlaned.
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

/// Criterion 3's items in [row]: `a` and `d` laned there, so the row is
/// 40 px, `d` on lane 0.
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

/// S2 (a)'s board and install: B40 under [_animated], criterion 3's
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

/// R11's board: B40 under motion off, criterion 3's items in row 39, at
/// the scroll offset [pixels] after one pump.
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

  group("the own scroll shift resets with the own data", () {
    /// S2 (a)'s board after its 20 pumps: pixels 27, the shift -18, nothing
    /// in motion.
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
      controller.beginOwnMakeRoomPreview();
      viewport.markNeedsLayout();
      await tester.pump();
      expectSamples(controller, viewport);
    });

    testWidgets("(c) at a new axis instance", (tester) async {
      final (controller, viewport, _) = await settled(tester);
      controller.rows = BoardAxisConfig(
        axis: LazyContentAxis(40, 10.0),
        laneExtent: 18.0,
        lanePadding: 4.0,
      );
      await tester.pump();
      expect(
        viewport.verticalPosition!.pixels,
        moreOrLessEquals(27.0, epsilon: 1e-9),
      );
      expectSamples(controller, viewport);
    });
  });

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

  testWidgets(
    "with no own preview the own-free sample reads the content axis as the "
    "painted one",
    (tester) async {
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
        final ownFree = _opsOfSample(
          controller,
          viewport,
          point,
          ownFree: true,
        );
        expect(painted, 8, reason: state);
        expect(ownFree, painted, reason: state);
      }

      expectPaintedCost("no scope");
      final epoch = controller.beginOwnMakeRoomPreview();
      expectPaintedCost("a scope and no install");
      _install(controller, _joinSpan);
      await tester.pump();
      expect(_opsOfSample(controller, viewport, point, ownFree: true), 9);
      _install(controller, _joinStored);
      await tester.pump();
      expectPaintedCost("the scope open after the preview stood and closed");
      _install(controller, _joinSpan);
      await tester.pump();
      controller.endOwnMakeRoomPreview(epoch);
      expectPaintedCost("the preview standing after the scope's end");
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
}
