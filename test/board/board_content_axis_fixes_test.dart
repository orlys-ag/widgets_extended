/// Tests for item 7H of the board audit fixes: a content-sized axis keeps
/// its measurements through an equal config and its rows' heights
/// through a sideways scroll, and lays out again after its cluster check
/// fires.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7H", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Cases 1, 3 and 4 were red at their TARGETs on the tree item 7G left,
/// with every setup sanity assertion before them passing. Cases 2 and 5
/// pin what the change must keep (a changed lane geometry still resets;
/// a cell shrinking in view still lowers its row) and were green there;
/// cases 6 and 7 pin the new record's invalidation, whose setup needs the
/// record. All seven were shown red against a mutation each.
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

Widget _frame(Widget board, {double width = 300.0, double height = 200.0}) {
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

/// A scrolled content-sized board of 200 rows: returns the row at the top
/// and its painted top.
Future<({int row, double top})> _scrolledRows(
  WidgetTester tester,
  BoardController<String, _Item> controller,
  ScrollController vertical,
) async {
  await tester.pumpWidget(
    _frame(
      Board<String, _Item>(
        controller: controller,
        verticalDetails: ScrollableDetails.vertical(controller: vertical),
        cellBuilder: (context, cell) {
          return SizedBox(key: _cellKey(cell.row, cell.col), height: 30.0);
        },
      ),
    ),
  );
  // Small steps, so every row is measured in the cache region before it
  // becomes visible and the corrections keep the anchor.
  for (var i = 0; i < 12; i++) {
    vertical.jumpTo(vertical.offset + 120.0);
    await tester.pump();
  }
  final row = _viewport(tester).firstVisibleRow;
  return (row: row, top: tester.getRect(find.byKey(_cellKey(row, 0))).top);
}

/// Row 1 holds one tall cell, far to the right, whose height [heights]
/// supplies, a negative height building no cell at all; an item over it
/// and the row below lets a payload write rebuild it. Three 100 px
/// columns show at a time.
Widget _sideways(
  BoardController<String, _Item> controller,
  ScrollController horizontal,
  Map<int, double> heights,
) {
  return _frame(
    Board<String, _Item>(
      controller: controller,
      horizontalDetails: ScrollableDetails.horizontal(controller: horizontal),
      cellBuilder: (context, cell) {
        final tall = cell.row == 1 ? heights[cell.col] : null;
        if (tall != null && tall < 0.0) {
          return null;
        }
        return SizedBox(
          key: _cellKey(cell.row, cell.col),
          height: tall ?? 30.0,
        );
      },
      itemBuilder: (context, item) {
        return const SizedBox.shrink();
      },
    ),
  );
}

BoardController<String, _Item> _sidewaysController(WidgetTester tester) {
  final controller = _controller(
    tester,
    rows: BoardAxisConfig(axis: LazyContentAxis(6, 30.0)),
    columns: BoardAxisConfig(axis: UniformAxis(12, 100.0)),
  );
  // Two rows tall, so it is no intra-track cluster on the content axis.
  controller.addItem(
    const _Item("poke"),
    const BoardSpan(rowStart: 1, colStart: 11, rowSpan: 2),
  );
  return controller;
}

double _rowHeight(WidgetTester tester, int col) {
  return tester.getRect(find.byKey(_cellKey(1, col))).height;
}

void main() {
  // Test 1 (F13).
  testWidgets("re-assigning an equal row config keeps the rows on screen",
      (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: LazyContentAxis(200, 80.0)),
      columns: BoardAxisConfig(axis: UniformAxis(2, 100.0)),
    );
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    final before = await _scrolledRows(tester, controller, vertical);
    // Setup sanity: well past the top, on measured rows.
    expect(before.row, greaterThan(20));

    // The same axis, the same values, a new config instance.
    controller.rows = BoardAxisConfig(axis: controller.rows.axis);
    await tester.pump();

    // TARGET: the same row is at the same place.
    expect(_viewport(tester).firstVisibleRow, before.row);
    expect(
      tester.getRect(find.byKey(_cellKey(before.row, 0))).top,
      before.top,
    );
  });

  // Test 2 (F13). New lane geometry changes what the sizing step folds
  // into a row's measurement, so those measurements still go.
  testWidgets("a config with other lane geometry still drops the "
      "measurements", (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: LazyContentAxis(200, 80.0)),
      columns: BoardAxisConfig(axis: UniformAxis(2, 100.0)),
    );
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await _scrolledRows(tester, controller, vertical);
    final lazy = controller.rows.axis as LazyContentAxis;
    // Setup sanity: row 0, scrolled past, is measured.
    expect(lazy.isMeasured(0), isTrue);

    controller.rows = BoardAxisConfig(axis: lazy, laneExtent: 18.0);
    // TARGET.
    expect(lazy.isMeasured(0), isFalse);
    await tester.pump();
  });

  // Test 3 (F14).
  testWidgets("a board lays out again once the item that tripped the "
      "cluster check is removed", (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: LazyContentAxis(6, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    );
    // One row, three columns: an intra-track cluster on the content axis
    // with no lane axis.
    controller.addItem(
      const _Item("bar"),
      const BoardSpan(rowStart: 1, colStart: 1, colSpan: 3),
    );
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return const SizedBox(height: 30.0);
          },
          itemBuilder: (context, item) {
            return const ColoredBox(color: Color(0xFF4CAF50));
          },
        ),
        width: 280.0,
        height: 300.0,
      ),
    );
    // Setup sanity: the check fired, with its message.
    final first = tester.takeException();
    expect(first, isA<FlutterError>());
    expect(first.toString(), contains("intra-track item cluster"));

    controller.removeItem("bar");
    await tester.pump();
    // TARGET: the board lays out cleanly again.
    expect(tester.takeException(), isNull);
  });

  // Test 4 (F18).
  testWidgets("a row keeps its height when its tallest cell scrolls out "
      "sideways", (tester) async {
    final controller = _sidewaysController(tester);
    final horizontal = ScrollController();
    addTearDown(horizontal.dispose);
    await tester.pumpWidget(
      _sideways(controller, horizontal, <int, double>{11: 100.0}),
    );
    horizontal.jumpTo(900.0);
    await tester.pump();
    // Setup sanity: with the tall cell on screen, row 1 is 100 tall.
    expect(_rowHeight(tester, 10), 100.0);
    horizontal.jumpTo(0.0);
    await tester.pump();
    // TARGET.
    expect(_rowHeight(tester, 0), 100.0);
  });

  // Test 5 (F18).
  testWidgets("the tallest cell measured again, smaller, lowers its row",
      (tester) async {
    final controller = _sidewaysController(tester);
    final horizontal = ScrollController();
    addTearDown(horizontal.dispose);
    final heights = <int, double>{11: 100.0};
    await tester.pumpWidget(_sideways(controller, horizontal, heights));
    horizontal.jumpTo(900.0);
    await tester.pump();
    expect(_rowHeight(tester, 10), 100.0);

    heights[11] = 30.0;
    controller.updateItem("poke", const _Item("poke", "shorter"));
    await tester.pump();
    // TARGET: re-measured in view, the cell lowers its row ...
    expect(_rowHeight(tester, 10), 30.0);
    horizontal.jumpTo(0.0);
    await tester.pump();
    // ... and nothing brings the old height back out of view.
    expect(_rowHeight(tester, 0), 30.0);
  });

  // Test 7 (F18).
  testWidgets("a recorded cell that stops building no longer holds its row",
      (tester) async {
    final controller = _sidewaysController(tester);
    final horizontal = ScrollController();
    addTearDown(horizontal.dispose);
    final heights = <int, double>{11: 100.0};
    await tester.pumpWidget(_sideways(controller, horizontal, heights));
    horizontal.jumpTo(900.0);
    await tester.pump();
    expect(_rowHeight(tester, 10), 100.0);

    heights[11] = -1.0;
    // A structural change rebuilds every child through the delegate.
    controller.addItem(
      const _Item("other"),
      const BoardSpan(rowStart: 3, colStart: 9, rowSpan: 2),
    );
    await tester.pump();
    // Setup sanity: the cell is gone.
    expect(find.byKey(_cellKey(1, 11)), findsNothing);
    // TARGET.
    expect(_rowHeight(tester, 10), 30.0);
  });

  // Test 8 (finding 4). No content-sized axis: the defect is in the
  // paint lists, not in the measurement.
  testWidgets("a cell that stops building paints nothing and no error",
      (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 30.0)),
      columns: BoardAxisConfig(axis: UniformAxis(12, 100.0)),
    );
    var gone = false;
    await tester.pumpWidget(
      _frame(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            if (gone && cell.row == 1 && cell.col == 1) {
              return null;
            }
            return SizedBox(key: _cellKey(cell.row, cell.col));
          },
          itemBuilder: (context, item) {
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // Setup sanity: the cell is built.
    expect(find.byKey(_cellKey(1, 1)), findsOneWidget);
    gone = true;
    // A structural change rebuilds every child through the delegate.
    controller.addItem(
      const _Item("other"),
      const BoardSpan(rowStart: 3, colStart: 0, rowSpan: 2),
    );
    await tester.pump();
    // Setup sanity: the builder's null answer took effect. (The element
    // goes whatever the paint lists hold, so this is no TARGET.)
    expect(find.byKey(_cellKey(1, 1)), findsNothing);
    // TARGET: the frame painted without error.
    expect(tester.takeException(), isNull);
  });

  // Test 9 (finding 4), the item arm: a builder that turns null reaches
  // every mounted item at once.
  testWidgets("an item whose builder turns null paints nothing and no error",
      (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 30.0)),
      columns: BoardAxisConfig(axis: UniformAxis(12, 100.0)),
    );
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 1, colStart: 1),
    );
    const itemKey = ValueKey<String>("im");
    Widget board({required bool items}) {
      return _frame(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return const SizedBox.shrink();
          },
          itemBuilder: items
              ? (context, item) {
                  return const SizedBox(key: itemKey);
                }
              : null,
        ),
      );
    }

    await tester.pumpWidget(board(items: true));
    // Setup sanity: the item is built.
    expect(find.byKey(itemKey), findsOneWidget);
    await tester.pumpWidget(board(items: false));
    // Setup sanity: the builder's null answer took effect.
    expect(find.byKey(itemKey), findsNothing);
    // TARGET.
    expect(tester.takeException(), isNull);
  });

  // Test 6 (F18).
  testWidgets("invalidateCellMeasurements forgets a cell out of view",
      (tester) async {
    final controller = _sidewaysController(tester);
    final horizontal = ScrollController();
    addTearDown(horizontal.dispose);
    final heights = <int, double>{11: 100.0};
    await tester.pumpWidget(_sideways(controller, horizontal, heights));
    horizontal.jumpTo(900.0);
    await tester.pump();
    horizontal.jumpTo(0.0);
    await tester.pump();
    // Setup sanity: row 1 holds the height of the cell out of view.
    expect(_rowHeight(tester, 0), 100.0);

    heights[11] = 30.0;
    controller.invalidateCellMeasurements();
    await tester.pump();
    // TARGET.
    expect(_rowHeight(tester, 0), 30.0);
  });
}
