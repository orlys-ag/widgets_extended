/// Tests of `BoardController.cellAt` and `BoardController.itemAt`, which
/// answer for a global point, and of `BoardController.globalRectOfCell`,
/// which answers a cell's rect in global coordinates.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

/// Twenty 50 px rows, the first frozen, and four 40 px columns, so the
/// lattice ends 160 px into a 200 px wide frame.
BoardController<String, _Item> _controller(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(20, 50.0), frozenStart: 1),
    columns: BoardAxisConfig(axis: UniformAxis(4, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// The key of the box the board builds for the cell at [row] and [col].
Key _cellKey(int row, int col) {
  return ValueKey<String>("cell-$row-$col");
}

/// The board in a 200x150 frame inset from the screen's origin, or the
/// frame alone where [shown] is false.
Widget _board(
  BoardController<String, _Item> controller,
  ScrollController vertical, {
  bool shown = true,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.only(left: 100.0, top: 60.0),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: _frameKey,
            width: 200.0,
            height: 150.0,
            child: shown
                ? Board<String, _Item>(
                    controller: controller,
                    verticalDetails: ScrollableDetails.vertical(
                      controller: vertical,
                    ),
                    cellBuilder: (context, cell) {
                      return SizedBox(
                        key: _cellKey(cell.row, cell.col),
                        width: 40.0,
                        height: 50.0,
                      );
                    },
                    itemBuilder: (context, item) {
                      return const ColoredBox(color: Color(0xFF4CAF50));
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets("cellAt names the cell painting under a global point", (
    tester,
  ) async {
    final controller = _controller(tester);
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(_board(controller, vertical));
    vertical.jumpTo(125.0);
    await tester.pump();
    final origin = tester.getTopLeft(find.byKey(_frameKey));
    // Setup sanity: the board's origin is not the screen's, so a point
    // read without converting it names another cell.
    expect(origin, const Offset(100.0, 60.0));

    // 80 px down, under the band and scrolled 125 px, is content 205:
    // row 4. 60 px across is column 1.
    expect(controller.cellAt(origin + const Offset(60.0, 80.0)), (
      row: 4,
      col: 1,
    ));
    // 180 px across lies past the lattice's 160.
    expect(controller.cellAt(origin + const Offset(180.0, 80.0)), isNull);
  });

  testWidgets("itemAt names the item painting under a global point", (
    tester,
  ) async {
    final controller = _controller(tester);
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 4, colStart: 1),
    );
    await tester.pumpWidget(_board(controller, vertical));
    vertical.jumpTo(125.0);
    await tester.pump();
    final origin = tester.getTopLeft(find.byKey(_frameKey));

    // Row 4 paints from 75 px to 125 px down at a 125 px scroll.
    expect(controller.itemAt(origin + const Offset(60.0, 100.0)), "m");
    // Column 0 of the same row holds no item.
    expect(controller.itemAt(origin + const Offset(20.0, 100.0)), isNull);
  });

  testWidgets("cellAt and itemAt answer null with no board mounted", (
    tester,
  ) async {
    final controller = _controller(tester);
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 1, colStart: 1),
    );
    const point = Offset(160.0, 135.0);

    await tester.pumpWidget(_board(controller, vertical, shown: false));
    expect(controller.cellAt(point), isNull);
    expect(controller.itemAt(point), isNull);

    await tester.pumpWidget(_board(controller, vertical));
    // Setup sanity: mounted, the board answers for the same point.
    expect(controller.cellAt(point), (row: 1, col: 1));
    expect(controller.itemAt(point), "m");

    await tester.pumpWidget(_board(controller, vertical, shown: false));
    expect(controller.cellAt(point), isNull);
    expect(controller.itemAt(point), isNull);
  });

  testWidgets("BQ1 globalRectOfCell gives the global rect a scrolled and a "
      "frozen cell paint at", (tester) async {
    final controller = _controller(tester);
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(_board(controller, vertical));
    vertical.jumpTo(125.0);
    await tester.pump();
    // Setup sanity: the board's origin is not the screen's, so a rect left
    // in the viewport's paint space lies elsewhere.
    expect(tester.getTopLeft(find.byKey(_frameKey)), const Offset(100.0, 60.0));

    // Row 4 paints from 75 px to 125 px down at a 125 px scroll, under
    // the frozen row 0's band.
    expect(
      controller.globalRectOfCell(4, 1),
      rectMoreOrLessEquals(
        tester.getRect(find.byKey(_cellKey(4, 1))),
        epsilon: 0.01,
      ),
    );
    expect(
      controller.globalRectOfCell(0, 2),
      rectMoreOrLessEquals(
        tester.getRect(find.byKey(_cellKey(0, 2))),
        epsilon: 0.01,
      ),
    );
  });

  testWidgets("BQ2 globalRectOfCell answers null with no board mounted and "
      "for an index past its axis", (tester) async {
    final controller = _controller(tester);
    final vertical = ScrollController();
    addTearDown(vertical.dispose);

    await tester.pumpWidget(_board(controller, vertical, shown: false));
    expect(controller.globalRectOfCell(1, 1), isNull);

    await tester.pumpWidget(_board(controller, vertical));
    // Setup sanity: mounted, the board answers for the same cell.
    expect(controller.globalRectOfCell(1, 1), isNotNull);
    expect(controller.globalRectOfCell(20, 1), isNull);
    expect(controller.globalRectOfCell(1, 4), isNull);

    await tester.pumpWidget(_board(controller, vertical, shown: false));
    expect(controller.globalRectOfCell(1, 1), isNull);
  });
}
