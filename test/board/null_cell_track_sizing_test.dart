/// A content-sized track whose obtained cells build nothing: it still
/// takes its lane cluster's term, it returns to its axis's estimate when
/// its cells stop building, and it does so whether the delegate dropped
/// the cells or their hosts answered null on a rebuild of their own.
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
  const _Item(this.key, [this.label = ""]);

  final String key;
  final String label;

  @override
  bool operator ==(Object other) {
    return other is _Item && other.key == key && other.label == label;
  }

  @override
  int get hashCode {
    return Object.hash(key, label);
  }
}

const Key _frameKey = ValueKey<String>("board-frame");

Key _cellKey(int row, int col) {
  return ValueKey<String>("c$row,$col");
}

/// The key of an item's content; the board keys the item's own child by
/// the item's key.
Key _itemKey(String key) {
  return ValueKey<String>("item-$key");
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  required BoardAxisConfig rows,
  required BoardAxisConfig columns,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: rows,
    columns: columns,
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

Widget _frame(Widget board, {double width = 200.0, double height = 400.0}) {
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

RenderBoardViewport<String> _viewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

/// Five content-sized rows with a 40 px estimate and a 10 px floor, over
/// four 50 px columns.
BoardController<String, _Item> _rowsController(
  WidgetTester tester, {
  double? laneExtent,
}) {
  return _controller(
    tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(5, 40.0, minTrackExtent: 10.0),
      laneExtent: laneExtent,
    ),
    columns: BoardAxisConfig(axis: UniformAxis(4, 50.0)),
  );
}

/// Row 1's cells are 100 px tall while [tall] says so and build nothing
/// otherwise; every other cell is 20 px tall.
Widget _tallRowBoard(
  BoardController<String, _Item> controller, {
  required bool tall,
}) {
  return _frame(
    Board<String, _Item>(
      controller: controller,
      cellBuilder: (context, cell) {
        if (cell.row == 1) {
          if (!tall) {
            return null;
          }
          return SizedBox(key: _cellKey(cell.row, cell.col), height: 100.0);
        }
        return SizedBox(key: _cellKey(cell.row, cell.col), height: 20.0);
      },
    ),
  );
}

/// The fixture of the relay cases: item `k` covers rows 1 and 2 across
/// every column, two rows tall so it is no cluster of one row, and row
/// 1's cells are 100 px tall while `k`'s label is "on" or [forceTall]
/// answers true, and build nothing otherwise. Every other cell is 20 px
/// tall. [calls] counts the cell builder's calls per row.
Widget _relayBoard(
  BoardController<String, _Item> controller,
  Map<int, int> calls, {
  bool Function()? forceTall,
}) {
  return _frame(
    Board<String, _Item>(
      controller: controller,
      cellBuilder: (context, cell) {
        calls[cell.row] = (calls[cell.row] ?? 0) + 1;
        if (cell.row == 1) {
          final on = controller.itemOf("k")?.label == "on";
          if (!on && !(forceTall?.call() ?? false)) {
            return null;
          }
          return SizedBox(key: _cellKey(cell.row, cell.col), height: 100.0);
        }
        return SizedBox(key: _cellKey(cell.row, cell.col), height: 20.0);
      },
      itemBuilder: (context, item) {
        return const SizedBox.shrink();
      },
    ),
  );
}

void main() {
  testWidgets("a laned content row whose cells build nothing holds its lanes", (
    tester,
  ) async {
    final controller = _rowsController(tester, laneExtent: 30.0);
    for (var i = 0; i < 4; i++) {
      controller.addItem(
        _Item("i$i"),
        const BoardSpan(rowStart: 1, colStart: 0, colSpan: 3),
      );
    }
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
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
    );
    final rows = controller.rows.axis;

    // Setup sanity: one cluster four lanes deep, every member built.
    expect(controller.laneCountOf("i0"), 4);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(_itemKey("i$i")), findsOneWidget);
    }
    // TARGET 1: four 30 px lanes and no padding.
    expect(rows.extentOf(1), 120.0);
    // TARGET 2: the deepest lane ends where the next row starts.
    final origin = tester.getTopLeft(find.byKey(_frameKey));
    var bottom = double.negativeInfinity;
    for (var i = 0; i < 4; i++) {
      final rect = tester.getRect(find.byKey(_itemKey("i$i")));
      if (rect.bottom - origin.dy > bottom) {
        bottom = rect.bottom - origin.dy;
      }
    }
    expect(
      bottom,
      moreOrLessEquals(_viewport(tester).rectOfCell(2, 0)!.top, epsilon: 1e-6),
    );
    // TARGET 3: an itemless row of such cells is measured at the
    // estimate.
    expect(rows.isMeasured(0), isTrue);
    expect(rows.extentOf(0), 40.0);
    expect(tester.takeException(), isNull);
  });

  for (final invalidate in <bool>[true, false]) {
    testWidgets("a content row whose cells stop building returns to its "
        "estimate (${invalidate ? "after" : "without"} "
        "invalidateCellMeasurements)", (tester) async {
      final controller = _rowsController(tester);
      await tester.pumpWidget(_tallRowBoard(controller, tall: true));
      final rows = controller.rows.axis;
      // Setup sanity: the tall cells hold the row.
      expect(rows.extentOf(1), 100.0);

      if (invalidate) {
        controller.invalidateCellMeasurements();
      }
      // A new builder replaces the delegate, which rebuilds every child.
      await tester.pumpWidget(_tallRowBoard(controller, tall: false));
      // Setup sanity: the cells are gone.
      expect(find.byKey(_cellKey(1, 0)), findsNothing);
      // TARGET.
      expect(rows.extentOf(1), 40.0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("a row whose cells a payload write turns to nothing rests at "
      "its estimate", (tester) async {
    final controller = _rowsController(tester);
    controller.addItem(
      const _Item("k", "on"),
      const BoardSpan(rowStart: 1, colStart: 0, rowSpan: 2, colSpan: 4),
    );
    final calls = <int, int>{};
    await tester.pumpWidget(_relayBoard(controller, calls));
    final rows = controller.rows.axis;
    // Setup sanity: the tall cells hold the row.
    expect(rows.extentOf(1), 100.0);

    final row3Before = calls[3];
    controller.updateItem("k", const _Item("k", "off"));
    await tester.pump();
    // Setup sanity: the write reached the cells through their hosts, not
    // through the delegate, and their builder answered null.
    expect(calls[3], row3Before);
    expect(find.byKey(_cellKey(1, 0)), findsNothing);
    // TARGET 1.
    expect(rows.extentOf(1), 40.0);

    controller.updateItem("k", const _Item("k", "on"));
    await tester.pump();
    // Control: a builder answering a widget again is measured again.
    expect(rows.extentOf(1), 100.0);

    controller.updateItem("k", const _Item("k", "off"));
    await tester.pump();
    final row3BeforeRebuild = calls[3];
    controller.addItem(
      const _Item("other"),
      const BoardSpan(rowStart: 3, colStart: 0, rowSpan: 2),
    );
    await tester.pump();
    // Setup sanity: the structural change rebuilt the cells through the
    // delegate.
    expect(calls[3], isNot(row3BeforeRebuild));
    // TARGET 2: the delegate dropping the cells keeps the row where the
    // hosts' null answer left it.
    expect(rows.extentOf(1), 40.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a cell a relay turned to nothing measures again when the "
      "delegate brings it back", (tester) async {
    final controller = _rowsController(tester);
    controller.addItem(
      const _Item("k", "on"),
      const BoardSpan(rowStart: 1, colStart: 0, rowSpan: 2, colSpan: 4),
    );
    final calls = <int, int>{};
    var forceTall = false;
    await tester.pumpWidget(
      _relayBoard(
        controller,
        calls,
        forceTall: () {
          return forceTall;
        },
      ),
    );
    final rows = controller.rows.axis;

    final row3Before = calls[3];
    controller.updateItem("k", const _Item("k", "off"));
    await tester.pump();
    // Setup sanity: the write went through the hosts, so the cells kept
    // their elements, and their builder answered null.
    expect(calls[3], row3Before);
    expect(find.byKey(_cellKey(1, 0)), findsNothing);

    forceTall = true;
    final row3BeforeRebuild = calls[3];
    controller.addItem(
      const _Item("other"),
      const BoardSpan(rowStart: 3, colStart: 0, rowSpan: 2),
    );
    await tester.pump();
    // Setup sanity: the structural change ran the delegate, which handed
    // the hosts a tall cell.
    expect(calls[3], isNot(row3BeforeRebuild));
    expect(find.byKey(_cellKey(1, 0)), findsOneWidget);
    // CONTROL: the host showing the delegate's cell is measured.
    expect(rows.extentOf(1), 100.0);
    expect(tester.takeException(), isNull);
  });
}
