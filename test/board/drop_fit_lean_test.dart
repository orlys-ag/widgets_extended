/// Tests for where a refused move's drop fit measures from: the start the
/// dragged item shows at, not the start the snap gave it. Of two
/// placements equally far from the snapped start, the fit takes the one
/// the item leans toward, on the lane axis of a laned item and on an axis
/// its corner places, and it follows the finger inside a refused
/// placement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_drop_fit.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

bool _always(BoardSpan span) {
  return true;
}

class _Item {
  const _Item(this.key);

  final String key;
}

/// Whether [span] meets an item of [controller] other than [key],
/// half-open on both axes.
bool _meetsOther(
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
    if (span.startTrackOn(Axis.vertical) < o.endTrackOn(Axis.vertical) &&
        o.startTrackOn(Axis.vertical) < span.endTrackOn(Axis.vertical) &&
        span.startTrackOn(Axis.horizontal) < o.endTrackOn(Axis.horizontal) &&
        o.startTrackOn(Axis.horizontal) < span.endTrackOn(Axis.horizontal)) {
      return true;
    }
  }
  return false;
}

/// A pumped board of seven 40px columns by five 40px rows, with "m" in
/// the cell at [mAt], row 0 of column 0 by default, and "o" at row 2 of
/// column 3, and a drag controller over it under [fit] that refuses any
/// placement meeting another item. [laned] gives the columns a lane
/// extent, which makes each one-column item laned on them.
class _Run {
  _Run._(
    this.viewport,
    this.drag,
    this.origin,
    this.asked,
    this.moves,
    this.liftAt,
  );

  final RenderBoardViewport<String> viewport;
  final BoardDragController<String> drag;

  /// The board's global top-left.
  final Offset origin;

  /// Every span the drop gate was asked about.
  final List<BoardSpan> asked;

  /// Every span a committed move reported.
  final List<BoardSpan> moves;

  /// The centre of "m" on the board, where [lift] presses.
  final Offset liftAt;

  static Future<_Run> pump(
    WidgetTester tester, {
    required bool laned,
    required BoardDropFit fit,
    ({int row, int col}) mAt = (row: 0, col: 0),
  }) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(5, 40.0)),
      columns: BoardAxisConfig(
        axis: UniformAxis(7, 40.0),
        laneExtent: laned ? 40.0 : null,
      ),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.addItem(
      const _Item("m"),
      BoardSpan(rowStart: mAt.row, colStart: mAt.col),
    );
    controller.addItem(
      const _Item("o"),
      const BoardSpan(rowStart: 2, colStart: 3),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280.0,
              height: 200.0,
              child: Board<String, _Item>(
                controller: controller,
                cellBuilder: (context, cell) {
                  return const SizedBox.expand();
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
    final asked = <BoardSpan>[];
    final moves = <BoardSpan>[];
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(
        onItemMoved: (key, span) {
          moves.add(span);
        },
        canDropAt: (key, span) {
          asked.add(span);
          return !_meetsOther(controller, key, span);
        },
        dropFit: fit,
      ),
    );
    addTearDown(drag.dispose);
    final origin = tester.getTopLeft(find.byType(Board<String, _Item>));
    final liftAt = Offset(mAt.col * 40.0 + 20.0, mAt.row * 40.0 + 20.0);
    return _Run._(viewport, drag, origin, asked, moves, liftAt);
  }

  /// Lifts "m" at its centre.
  void lift() {
    drag.startDrag(
      key: "m",
      renderPort: viewport,
      pointerGlobal: origin + liftAt,
    );
  }

  /// Moves the finger to [local] on the board and pumps a frame.
  Future<void> moveTo(WidgetTester tester, Offset local) async {
    drag.updateDrag(origin + local);
    await tester.pump();
  }
}

const BoardDropFit _sideways = BoardDropFit(
  minFreeFraction: 0.0,
  rowRadius: 0.0,
  colRadius: 1.0,
);

const BoardDropFit _upAndDown = BoardDropFit(
  minFreeFraction: 0.0,
  rowRadius: 1.0,
  colRadius: 0.0,
);

void main() {
  // Column 3 of the one row is taken; columns 2 and 4, a column either
  // way, are free.
  BoardSpan? sideFit(({double row, double col})? reference) {
    return BoardDropFitter.nearestFit(
      box: const BoardSpan(rowStart: 0, colStart: 3),
      policy: _sideways,
      snap: const BoardSnap.track(),
      rowAxis: UniformAxis(1, 10.0),
      colAxis: UniformAxis(7, 10.0),
      rowWindow: (min: 0.0, max: 0.0),
      colWindow: (min: 0.0, max: 6.0),
      obstacles: const <BoardSpan>[BoardSpan(rowStart: 0, colStart: 3)],
      accepts: _always,
      reference: reference,
    );
  }

  test("a fit measures from the reference, toward the side it leans", () {
    expect(
      sideFit((row: 0.0, col: 3.25)),
      const BoardSpan(rowStart: 0, colStart: 4),
    );
    expect(
      sideFit((row: 0.0, col: 2.75)),
      const BoardSpan(rowStart: 0, colStart: 2),
    );
  });

  test("with no reference, of two placements equally far the fit takes "
      "the lower", () {
    expect(sideFit(null), const BoardSpan(rowStart: 0, colStart: 2));
  });

  // Row 5 of the one column is taken; rows 4 and 6 are free.
  test("a reference leaning down the rows lands on the later row", () {
    expect(
      BoardDropFitter.nearestFit(
        box: const BoardSpan(rowStart: 5, colStart: 0),
        policy: _upAndDown,
        snap: const BoardSnap.track(),
        rowAxis: UniformAxis(10, 10.0),
        colAxis: UniformAxis(1, 10.0),
        rowWindow: (min: 0.0, max: 9.0),
        colWindow: (min: 0.0, max: 0.0),
        obstacles: const <BoardSpan>[BoardSpan(rowStart: 5, colStart: 0)],
        accepts: _always,
        reference: (row: 5.25, col: 0.0),
      ),
      const BoardSpan(rowStart: 6, colStart: 0),
    );
  });

  // The box at row 2 of column 3 is taken, with columns 10px wide and
  // rows 7.2px tall, and the item shows a quarter column right of it. The
  // next column is 7.5px from it; the rows either way, on the box's own
  // column, are 7.2px down the rows and 2.5px back across them, 7.6px.
  test("a placement on the box's own column is measured from the "
      "reference too", () {
    expect(
      BoardDropFitter.nearestFit(
        box: const BoardSpan(rowStart: 2, colStart: 3),
        policy: const BoardDropFit(
          minFreeFraction: 0.0,
          rowRadius: 1.0,
          colRadius: 1.0,
        ),
        snap: const BoardSnap.track(),
        rowAxis: UniformAxis(5, 7.2),
        colAxis: UniformAxis(7, 10.0),
        rowWindow: (min: 0.0, max: 4.0),
        colWindow: (min: 0.0, max: 6.0),
        obstacles: const <BoardSpan>[BoardSpan(rowStart: 2, colStart: 3)],
        accepts: _always,
        reference: (row: 2.0, col: 3.25),
      ),
      const BoardSpan(rowStart: 2, colStart: 4),
    );
  });

  // The same with the axes swapped: rows 10px, columns 7.2px, the item a
  // quarter row below the box.
  test("a placement on the box's own row is measured from the reference "
      "too", () {
    expect(
      BoardDropFitter.nearestFit(
        box: const BoardSpan(rowStart: 3, colStart: 2),
        policy: const BoardDropFit(
          minFreeFraction: 0.0,
          rowRadius: 1.0,
          colRadius: 1.0,
        ),
        snap: const BoardSnap.track(),
        rowAxis: UniformAxis(7, 10.0),
        colAxis: UniformAxis(5, 7.2),
        rowWindow: (min: 0.0, max: 6.0),
        colWindow: (min: 0.0, max: 4.0),
        obstacles: const <BoardSpan>[BoardSpan(rowStart: 3, colStart: 2)],
        accepts: _always,
        reference: (row: 3.25, col: 2.0),
      ),
      const BoardSpan(rowStart: 4, colStart: 2),
    );
  });

  // Column 0 is taken; an item dragged past the lattice's start shows
  // before column 0, where the axis has no offset to measure from.
  test("a reference past the lattice is held inside it", () {
    expect(
      BoardDropFitter.nearestFit(
        box: const BoardSpan(rowStart: 0, colStart: 0),
        policy: _sideways,
        snap: const BoardSnap.track(),
        rowAxis: UniformAxis(1, 10.0),
        colAxis: UniformAxis(7, 10.0),
        rowWindow: (min: 0.0, max: 0.0),
        colWindow: (min: 0.0, max: 6.0),
        obstacles: const <BoardSpan>[BoardSpan(rowStart: 0, colStart: 0)],
        accepts: _always,
        reference: (row: 0.0, col: -0.4),
      ),
      const BoardSpan(rowStart: 0, colStart: 1),
    );
  });

  // "m" lifted at its centre is carried over "o" with the finger a quarter
  // column off the middle of o's cell; columns 2 and 4 are equally far
  // from column 3, where the drop is refused.
  for (final laned in <bool>[true, false]) {
    final which = laned ? "a laned item" : "an item its corner places";
    testWidgets("$which leaning right lands right, and left lands left", (
      tester,
    ) async {
      final run = await _Run.pump(tester, laned: laned, fit: _sideways);
      run.lift();
      await run.moveTo(tester, const Offset(150.0, 100.0));
      // Setup sanity: the placement under the finger was refused.
      expect(run.asked, contains(const BoardSpan(rowStart: 2, colStart: 3)));
      expect(
        run.drag.currentTarget!.span,
        const BoardSpan(rowStart: 2, colStart: 4),
      );
      run.drag.endDrag(cancel: false);
      await tester.pump();
      expect(run.moves, const <BoardSpan>[BoardSpan(rowStart: 2, colStart: 4)]);

      final left = await _Run.pump(tester, laned: laned, fit: _sideways);
      left.lift();
      await left.moveTo(tester, const Offset(130.0, 100.0));
      expect(
        left.drag.currentTarget!.span,
        const BoardSpan(rowStart: 2, colStart: 2),
      );
      left.drag.endDrag(cancel: false);
      await tester.pump();
    });
  }

  testWidgets("an item leaning down the rows lands below, and up lands "
      "above", (tester) async {
    final run = await _Run.pump(tester, laned: true, fit: _upAndDown);
    run.lift();
    await run.moveTo(tester, const Offset(140.0, 110.0));
    expect(run.asked, contains(const BoardSpan(rowStart: 2, colStart: 3)));
    expect(
      run.drag.currentTarget!.span,
      const BoardSpan(rowStart: 3, colStart: 3),
    );
    await run.moveTo(tester, const Offset(140.0, 90.0));
    expect(
      run.drag.currentTarget!.span,
      const BoardSpan(rowStart: 1, colStart: 3),
    );
    run.drag.endDrag(cancel: false);
    await tester.pump();
  });

  // "m" at row 2 of column 0 is carried along its row onto "o" with the
  // finger a quarter row low or high, too little to move its row.
  testWidgets("a row the drag keeps leans by the corner's displacement", (
    tester,
  ) async {
    final run = await _Run.pump(
      tester,
      laned: true,
      fit: _upAndDown,
      mAt: (row: 2, col: 0),
    );
    run.lift();
    await run.moveTo(tester, const Offset(140.0, 110.0));
    expect(run.asked, contains(const BoardSpan(rowStart: 2, colStart: 3)));
    expect(
      run.drag.currentTarget!.span,
      const BoardSpan(rowStart: 3, colStart: 3),
    );
    run.drag.endDrag(cancel: true);
    await tester.pump();

    final up = await _Run.pump(
      tester,
      laned: true,
      fit: _upAndDown,
      mAt: (row: 2, col: 0),
    );
    up.lift();
    await up.moveTo(tester, const Offset(140.0, 90.0));
    expect(
      up.drag.currentTarget!.span,
      const BoardSpan(rowStart: 1, colStart: 3),
    );
    up.drag.endDrag(cancel: true);
    await tester.pump();
  });

  // "m" at row 0 of column 3 is carried down its column onto "o" with the
  // finger a quarter column right or left of where it pressed, inside
  // the cell, so a laned item keeps its column.
  testWidgets("a lane column the drag keeps leans by the finger's place "
      "across its cell", (tester) async {
    final run = await _Run.pump(
      tester,
      laned: true,
      fit: _sideways,
      mAt: (row: 0, col: 3),
    );
    run.lift();
    await run.moveTo(tester, const Offset(150.0, 100.0));
    expect(run.asked, contains(const BoardSpan(rowStart: 2, colStart: 3)));
    expect(
      run.drag.currentTarget!.span,
      const BoardSpan(rowStart: 2, colStart: 4),
    );
    await run.moveTo(tester, const Offset(130.0, 100.0));
    expect(
      run.drag.currentTarget!.span,
      const BoardSpan(rowStart: 2, colStart: 2),
    );
    run.drag.endDrag(cancel: true);
    await tester.pump();
  });

  testWidgets("an admitted placement asks nothing for a new lean", (
    tester,
  ) async {
    final run = await _Run.pump(tester, laned: true, fit: _sideways);
    run.lift();
    await run.moveTo(tester, const Offset(100.0, 60.0));
    expect(
      run.drag.currentTarget!.span,
      const BoardSpan(rowStart: 1, colStart: 2),
    );
    final asked = run.asked.length;
    await run.moveTo(tester, const Offset(110.0, 60.0));
    expect(run.asked, hasLength(asked));
    expect(
      run.drag.currentTarget!.span,
      const BoardSpan(rowStart: 1, colStart: 2),
    );
    run.drag.endDrag(cancel: true);
    await tester.pump();
  });

  testWidgets("the fit follows the finger inside a refused placement, "
      "re-running only for a new lean", (tester) async {
    final run = await _Run.pump(tester, laned: true, fit: _sideways);
    run.lift();
    await run.moveTo(tester, const Offset(130.0, 100.0));
    expect(
      run.drag.currentTarget!.span,
      const BoardSpan(rowStart: 2, colStart: 2),
    );

    // Across the same cell to its right side.
    await run.moveTo(tester, const Offset(150.0, 100.0));
    expect(
      run.drag.currentTarget!.span,
      const BoardSpan(rowStart: 2, colStart: 4),
    );

    // A pixel on is the same lean, a quarter column to an eighth: the
    // gate is not asked again.
    var asked = run.asked.length;
    await run.moveTo(tester, const Offset(151.0, 100.0));
    expect(run.asked, hasLength(asked));

    // Three eighths is a new lean, which lands on column 4 again: the fit
    // ran, without asking about the refused placement again, and the
    // unchanged target notifies nothing.
    asked = run.asked.length;
    const refused = BoardSpan(rowStart: 2, colStart: 3);
    final refusals = run.asked.where((span) => span == refused).length;
    var notifications = 0;
    void count() {
      notifications += 1;
    }

    run.drag.addListener(count);
    await run.moveTo(tester, const Offset(155.0, 100.0));
    run.drag.removeListener(count);
    expect(run.asked.length, greaterThan(asked));
    expect(run.asked.where((span) => span == refused), hasLength(refusals));
    expect(
      run.drag.currentTarget!.span,
      const BoardSpan(rowStart: 2, colStart: 4),
    );
    expect(notifications, 0);
    run.drag.endDrag(cancel: false);
    await tester.pump();
  });
}
