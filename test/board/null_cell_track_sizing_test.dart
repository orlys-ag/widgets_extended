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
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_views.dart';
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
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: rows,
    columns: columns,
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
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
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  return _controller(
    tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(5, 40.0, minTrackExtent: 10.0),
      laneExtent: laneExtent,
    ),
    columns: BoardAxisConfig(axis: UniformAxis(4, 50.0)),
    style: style,
  );
}

/// Adds a cluster of four items `i0` to `i3`, one per lane, over columns
/// 0 to 2 of [row].
void _addCluster(BoardController<String, _Item> controller, int row) {
  for (var i = 0; i < 4; i++) {
    controller.addItem(
      _Item("i$i"),
      BoardSpan(rowStart: row, colStart: 0, colSpan: 3),
    );
  }
}

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

Widget _itemBox(BuildContext context, BoardItemView<String, _Item> item) {
  return ColoredBox(key: _itemKey(item.key), color: const Color(0xFF4CAF50));
}

/// Row 1's cells are [height] tall, and build nothing while it is null;
/// every other cell is 20 px tall. Each call makes a new cell builder, so
/// pumping it replaces the delegate, which rebuilds every child.
Widget _rowBoard(
  BoardController<String, _Item> controller, {
  required double? height,
}) {
  return _frame(
    Board<String, _Item>(
      controller: controller,
      cellBuilder: (context, cell) {
        if (cell.row == 1) {
          if (height == null) {
            return null;
          }
          return SizedBox(key: _cellKey(cell.row, cell.col), height: height);
        }
        return SizedBox(key: _cellKey(cell.row, cell.col), height: 20.0);
      },
    ),
  );
}

/// Mounts, under its own [key], a board whose cells all build nothing,
/// and counts the cell builder's calls on its first layout and on a
/// 16 px scroll.
Future<({int first, int scrolled})> _nullBoardCalls(
  WidgetTester tester,
  BoardController<String, _Item> controller,
  ScrollController vertical,
  Key key,
) async {
  var calls = 0;
  await tester.pumpWidget(
    _frame(
      Board<String, _Item>(
        key: key,
        controller: controller,
        verticalDetails: ScrollableDetails.vertical(controller: vertical),
        cellBuilder: (context, cell) {
          calls += 1;
          return null;
        },
      ),
      height: 600.0,
    ),
  );
  final first = calls;
  calls = 0;
  vertical.jumpTo(16.0);
  await tester.pump();
  return (first: first, scrolled: calls);
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

/// Row 1's cells are 100 px tall while unselected and build nothing while
/// selected; every other cell is 20 px tall. [calls] counts the cell
/// builder's calls per row.
Widget _selectionBoard(
  BoardController<String, _Item> controller,
  Map<int, int> calls,
) {
  return _frame(
    Board<String, _Item>(
      controller: controller,
      cellBuilder: (context, cell) {
        calls[cell.row] = (calls[cell.row] ?? 0) + 1;
        if (cell.row == 1) {
          if (cell.isSelected) {
            return null;
          }
          return SizedBox(key: _cellKey(cell.row, cell.col), height: 100.0);
        }
        return SizedBox(key: _cellKey(cell.row, cell.col), height: 20.0);
      },
    ),
  );
}

void main() {
  testWidgets("a laned content row whose cells build nothing holds its lanes", (
    tester,
  ) async {
    final controller = _rowsController(tester, laneExtent: 30.0);
    _addCluster(controller, 1);
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return null;
          },
          itemBuilder: _itemBox,
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

  testWidgets("a laned content row of small cells takes its lanes' extent", (
    tester,
  ) async {
    final controller = _rowsController(tester, laneExtent: 30.0);
    _addCluster(controller, 1);
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return SizedBox(key: _cellKey(cell.row, cell.col), height: 20.0);
          },
          itemBuilder: _itemBox,
        ),
      ),
    );
    final rows = controller.rows.axis;

    // Control: the cluster outgrows the cells, and an itemless row takes
    // its cells' extent.
    expect(rows.extentOf(1), 120.0);
    expect(rows.extentOf(0), 20.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a cluster growing above the viewport leaves rows whose cells "
      "build nothing where they are", (tester) async {
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(
        axis: LazyContentAxis(400, 40.0, minTrackExtent: 10.0),
        laneExtent: 30.0,
      ),
      columns: BoardAxisConfig(axis: UniformAxis(4, 50.0)),
    );
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          verticalDetails: ScrollableDetails.vertical(controller: vertical),
          cellBuilder: (context, cell) {
            return null;
          },
          itemBuilder: _itemBox,
        ),
        height: 300.0,
      ),
    );
    vertical.jumpTo(2000.0);
    await tester.pump();
    final viewport = _viewport(tester);
    final row = viewport.firstVisibleRow;
    final top = viewport.rectOfCell(row, 0)!.top;
    // Setup sanity: the row the cluster joins is above the viewport.
    expect(
      viewport.rectOfCell(row - 1, 0)!.bottom,
      lessThanOrEqualTo(0.0 + 1e-6),
    );

    _addCluster(controller, row - 1);
    await tester.pump();

    // TARGET: the cluster grows its row.
    expect(controller.rows.axis.extentOf(row - 1), 120.0);
    // Control: the growth above the viewport moves nothing in it.
    expect(
      viewport.rectOfCell(row, 0)!.top,
      moreOrLessEquals(top, epsilon: 1e-6),
    );
    expect(tester.takeException(), isNull);
  });

  for (final invalidate in <bool>[true, false]) {
    testWidgets("a content row whose cells stop building returns to its "
        "estimate (${invalidate ? "after" : "without"} "
        "invalidateCellMeasurements)", (tester) async {
      final controller = _rowsController(tester);
      await tester.pumpWidget(_rowBoard(controller, height: 100.0));
      final rows = controller.rows.axis;
      // Setup sanity: the tall cells hold the row.
      expect(rows.extentOf(1), 100.0);

      if (invalidate) {
        controller.invalidateCellMeasurements();
      }
      await tester.pumpWidget(_rowBoard(controller, height: null));
      // Setup sanity: the cells are gone.
      expect(find.byKey(_cellKey(1, 0)), findsNothing);
      // TARGET.
      expect(rows.extentOf(1), 40.0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final invalidate in <bool>[true, false]) {
    testWidgets("a content row whose cells shrink to no extent rests at its "
        "floor (${invalidate ? "after" : "without"} "
        "invalidateCellMeasurements)", (tester) async {
      final controller = _rowsController(tester);
      await tester.pumpWidget(_rowBoard(controller, height: 100.0));
      final rows = controller.rows.axis;
      // Setup sanity: the tall cells hold the row.
      expect(rows.extentOf(1), 100.0);

      if (invalidate) {
        controller.invalidateCellMeasurements();
      }
      await tester.pumpWidget(_rowBoard(controller, height: 0.0));
      // Control: a cell that takes no extent measures zero, which the
      // floor raises.
      expect(rows.extentOf(1), 10.0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("a row returning to its estimate runs on the trackResize "
      "family", (tester) async {
    final controller = _rowsController(
      tester,
      style: const BoardAnimationStyle(
        trackResize: BoardAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
        itemSlide: _zero,
      ),
    );
    await tester.pumpWidget(_rowBoard(controller, height: 100.0));
    await tester.pumpAndSettle();
    final rows = controller.rows.axis;
    final viewport = _viewport(tester);
    // Setup sanity: the row rests at its tall cells' extent.
    expect(viewport.rectOfCell(1, 0)!.height, 100.0);

    await tester.pumpWidget(_rowBoard(controller, height: null));
    // TARGET 1: the axis takes the estimate at once.
    expect(rows.extentOf(1), 40.0);
    await tester.pump(const Duration(milliseconds: 150));
    // TARGET 2: the painted row is on its way there.
    expect(viewport.rectOfCell(1, 0)!.height, inExclusiveRange(40.0, 100.0));
    await tester.pumpAndSettle();
    // TARGET 3: and arrives.
    expect(viewport.rectOfCell(1, 0)!.height, 40.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a content column whose cells stop building returns to its "
      "estimate", (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(5, 50.0)),
      columns: BoardAxisConfig(
        axis: LazyContentAxis(4, 40.0, minTrackExtent: 10.0),
      ),
    );
    Widget board({required bool wide}) {
      return _frame(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            if (cell.col == 1) {
              if (!wide) {
                return null;
              }
              return SizedBox(key: _cellKey(cell.row, cell.col), width: 100.0);
            }
            return SizedBox(key: _cellKey(cell.row, cell.col), width: 20.0);
          },
        ),
        width: 400.0,
        height: 300.0,
      );
    }

    await tester.pumpWidget(board(wide: true));
    final columns = controller.columns.axis;
    // Setup sanity: the wide cells hold the column.
    expect(columns.extentOf(1), 100.0);

    await tester.pumpWidget(board(wide: false));
    // Setup sanity: the cells are gone.
    expect(find.byKey(_cellKey(0, 1)), findsNothing);
    // TARGET.
    expect(columns.extentOf(1), 40.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a row whose cells build nothing is measured once, not on "
      "every layout", (tester) async {
    final rows = LazyContentAxis(6, 40.0, minTrackExtent: 10.0);
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: rows),
      columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    );
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            if (cell.row == 2) {
              return null;
            }
            return SizedBox(key: _cellKey(cell.row, cell.col), height: 20.0);
          },
        ),
      ),
    );
    // TARGET: the row is resolved to the estimate.
    expect(rows.isMeasured(2), isTrue);
    expect(rows.extentOf(2), 40.0);

    final records = rows.debugRecordCount;
    final layouts = _viewport(tester).debugPerformLayoutCount;
    controller.setSelection(
      const BoardSelection(anchor: (row: 0, col: 0), focus: (row: 0, col: 0)),
    );
    await tester.pump();
    await tester.pump();
    // Setup sanity: the selection change laid the board out again, which
    // it does while a cell that builds nothing is obtained.
    expect(_viewport(tester).debugPerformLayoutCount, greaterThan(layouts));
    // Control: that layout recorded nothing.
    expect(rows.debugRecordCount, records);
    expect(tester.takeException(), isNull);
  });

  testWidgets("rows whose cells build nothing cost what fixed rows of their "
      "estimate cost", (tester) async {
    final lazyVertical = ScrollController();
    addTearDown(lazyVertical.dispose);
    final uniformVertical = ScrollController();
    addTearDown(uniformVertical.dispose);
    final lazy = _controller(
      tester,
      rows: BoardAxisConfig(axis: LazyContentAxis(400, 40.0)),
      columns: BoardAxisConfig(axis: UniformAxis(4, 50.0)),
    );
    final uniform = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(400, 40.0)),
      columns: BoardAxisConfig(axis: UniformAxis(4, 50.0)),
    );
    final lazyCalls = await _nullBoardCalls(
      tester,
      lazy,
      lazyVertical,
      const ValueKey<String>("lazy"),
    );
    final uniformCalls = await _nullBoardCalls(
      tester,
      uniform,
      uniformVertical,
      const ValueKey<String>("uniform"),
    );

    // Setup sanity: every counted layout asked for cells.
    expect(lazyCalls.first, greaterThan(0));
    expect(lazyCalls.scrolled, greaterThan(0));
    expect(uniformCalls.first, greaterThan(0));
    expect(uniformCalls.scrolled, greaterThan(0));
    // Control: the content-sized rows ask for the cells the fixed rows
    // ask for, and rest at their estimate.
    expect(lazyCalls.first, uniformCalls.first);
    expect(lazyCalls.scrolled, uniformCalls.scrolled);
    expect(lazy.rows.axis.extentOf(0), 40.0);
    // TARGET: such a row is resolved.
    expect(lazy.rows.axis.isMeasured(0), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a drag over an empty row whose cells build nothing opens the "
      "lane it would take", (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(
        axis: LazyContentAxis(6, 30.0, minTrackExtent: 10.0),
        laneExtent: 40.0,
        lanePadding: 4.0,
      ),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    );
    controller.addItem(
      const _Item("d"),
      const BoardSpan(rowStart: 5, colStart: 0, colSpan: 3),
    );
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return null;
          },
          itemBuilder: _itemBox,
        ),
        width: 280.0,
      ),
    );
    final viewport = _viewport(tester);
    final origin = tester.getTopLeft(find.byKey(_frameKey));
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(onItemMoved: (key, span) {}),
    );
    addTearDown(drag.dispose);
    expect(
      drag.startDrag(
        key: "d",
        renderPort: viewport,
        pointerGlobal: origin + viewport.rectOfItem("d")!.center,
      ),
      isTrue,
    );
    drag.updateDrag(origin + viewport.rectOfCell(3, 1)!.center);
    await tester.pump();

    // Setup sanity: the drag would land on row 3, which holds the lane it
    // would take.
    expect(drag.currentTarget!.span.rowStart, 3);
    expect(controller.anim.makeRoomSlotsOn(3).toList(), hasLength(1));
    // TARGET: the row opens that lane, 40 px and the 4 px padding.
    expect(viewport.rectOfCell(3, 0)!.height, 44.0);

    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
    // Control: the cancel returns the row to its estimate.
    expect(viewport.rectOfCell(3, 0)!.height, 30.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a row keeps its recorded height while its window builds "
      "nothing", (tester) async {
    final horizontal = ScrollController();
    addTearDown(horizontal.dispose);
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: LazyContentAxis(6, 30.0)),
      columns: BoardAxisConfig(axis: UniformAxis(12, 100.0)),
    );
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          horizontalDetails: ScrollableDetails.horizontal(
            controller: horizontal,
          ),
          cellBuilder: (context, cell) {
            if (cell.row == 1) {
              if (cell.col != 11) {
                return null;
              }
              return SizedBox(key: _cellKey(cell.row, cell.col), height: 100.0);
            }
            return SizedBox(key: _cellKey(cell.row, cell.col), height: 30.0);
          },
        ),
        width: 300.0,
        height: 200.0,
      ),
    );
    final rows = controller.rows.axis;

    horizontal.jumpTo(900.0);
    await tester.pump();
    // Setup sanity: the tall cell, in view, holds the row.
    expect(rows.extentOf(1), 100.0);

    horizontal.jumpTo(0.0);
    await tester.pump();
    // Setup sanity: the tall cell is out of the window.
    expect(find.byKey(_cellKey(1, 11)), findsNothing);
    // Control: its record still holds the row.
    expect(rows.extentOf(1), 100.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets("the last chips leaving a row whose cells build nothing settle "
      "without a step", (tester) async {
    final controller = _rowsController(
      tester,
      laneExtent: 30.0,
      style: const BoardAnimationStyle(
        trackResize: _zero,
        itemSlide: _zero,
        itemEnterExit: BoardAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      ),
    );
    for (var i = 0; i < 2; i++) {
      controller.addItem(
        _Item("c$i"),
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
          itemBuilder: _itemBox,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    // TARGET: two 30 px lanes.
    expect(controller.rows.axis.extentOf(1), 60.0);

    controller.removeItem("c0");
    controller.removeItem("c1");
    await tester.pump();
    final heights = <double>[viewport.rectOfCell(1, 0)!.height];
    for (var i = 0; i < 40 && tester.binding.hasScheduledFrame; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      heights.add(viewport.rectOfCell(1, 0)!.height);
    }
    // Setup sanity: the exit ran over several frames and settled.
    expect(heights.length, greaterThan(2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    // Control: the row never dips below its estimate, and rests there.
    for (final height in heights) {
      expect(height, greaterThanOrEqualTo(40.0 - 1e-6));
    }
    expect(heights.last, 40.0);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets("a row whose cells a payload write turned to nothing stays at "
      "its estimate after invalidateCellMeasurements", (tester) async {
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

    final row1Before = calls[1];
    final layouts = _viewport(tester).debugPerformLayoutCount;
    controller.invalidateCellMeasurements();
    await tester.pump();
    // Setup sanity: the invalidation laid the board out again and ran no
    // builder of row 1, so its hosts still show the empty box.
    expect(_viewport(tester).debugPerformLayoutCount, greaterThan(layouts));
    expect(calls[1], row1Before);
    // TARGET: the empty boxes are taken as no cell, not measured at zero.
    expect(rows.extentOf(1), 40.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a row whose cells a selection change turns to nothing rests "
      "at its estimate", (tester) async {
    final controller = _rowsController(tester);
    final calls = <int, int>{};
    await tester.pumpWidget(_selectionBoard(controller, calls));
    final rows = controller.rows.axis;
    // Setup sanity: the tall cells hold the row.
    expect(rows.extentOf(1), 100.0);

    final row1Before = calls[1];
    final row3Before = calls[3];
    controller.setSelection(
      const BoardSelection(anchor: (row: 1, col: 0), focus: (row: 1, col: 3)),
    );
    await tester.pump();
    // Setup sanity: the selection reached row 1's cells through their
    // hosts, not through the delegate, and their builder answered null.
    expect(calls[1], isNot(row1Before));
    expect(calls[3], row3Before);
    expect(find.byKey(_cellKey(1, 0)), findsNothing);
    // TARGET.
    expect(rows.extentOf(1), 40.0);

    controller.setSelection(const BoardSelection.none());
    await tester.pump();
    // Control: a builder answering a widget again is measured again.
    expect(rows.extentOf(1), 100.0);
    expect(tester.takeException(), isNull);
  });
}
