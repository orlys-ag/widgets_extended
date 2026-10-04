/// Tests for item 7P of the board audit fixes: a new axis config keeps
/// the scrolled region's leading edge on the same place in the lattice.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7P", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Cases 1 to 3 were red at their TARGETs on the tree item 7O left, with
/// every setup sanity assertion before them passing; case 4 pins what the
/// change must keep.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
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
  return controller;
}

Widget _board(
  BoardController<String, _Item> controller,
  ScrollController vertical,
  ScrollController horizontal,
) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280.0,
          height: 300.0,
          child: Board<String, _Item>(
            controller: controller,
            verticalDetails: ScrollableDetails.vertical(controller: vertical),
            horizontalDetails: ScrollableDetails.horizontal(
              controller: horizontal,
            ),
            cellBuilder: (context, cell) {
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  late ScrollController vertical;
  late ScrollController horizontal;

  setUp(() {
    vertical = ScrollController();
    horizontal = ScrollController();
  });

  tearDown(() {
    vertical.dispose();
    horizontal.dispose();
  });

  // Test 1.
  testWidgets("zooming the rows keeps the row at the top", (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(24, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(_board(controller, vertical, horizontal));
    vertical.jumpTo(225.0);
    await tester.pump();
    // Setup sanity: row 4 and a half at the top.
    expect(vertical.offset, 225.0);

    controller.rows = BoardAxisConfig(axis: UniformAxis(24, 100.0));
    await tester.pump();
    // TARGET: still row 4 and a half at the top, at twice the pixels.
    expect(vertical.offset, 450.0);
  });

  // Test 2. A one-row header of 50 px that KEEPS its size while the rows
  // below double: the scrolled region starts under it at 50 px both
  // times, so an anchor that ignored the band would land on another row
  // (a uniform zoom scales the band with the rows, hiding that).
  testWidgets("zooming under a frozen header keeps the row under the band",
      (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(24, 50.0), frozenStart: 1),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(_board(controller, vertical, horizontal));
    vertical.jumpTo(200.0);
    await tester.pump();
    // Setup sanity: content offset 250 under the band, row 5's top.
    expect(vertical.offset, 200.0);

    controller.rows = BoardAxisConfig(
      axis: ExplicitAxis(<double>[50.0, for (var i = 1; i < 24; i++) 100.0]),
      frozenStart: 1,
    );
    await tester.pump();
    // TARGET: row 5's top under the band again: 50 + 4 * 100 = 450 in
    // content, minus the 50 px band.
    expect(vertical.offset, 400.0);
  });

  // Test 3.
  testWidgets("zooming the columns keeps the column at the leading edge",
      (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(30, 40.0)),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(_board(controller, vertical, horizontal));
    horizontal.jumpTo(100.0);
    await tester.pump();
    // Setup sanity: column 2 and a half at the leading edge.
    expect(horizontal.offset, 100.0);

    controller.columns = BoardAxisConfig(axis: UniformAxis(30, 80.0));
    await tester.pump();
    // TARGET.
    expect(horizontal.offset, 200.0);
  });

  // Test 4. A new controller is a new model, not a zoom.
  testWidgets("a controller swap keeps the offset as it is", (tester) async {
    final first = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(24, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    );
    final second = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(24, 100.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(_board(first, vertical, horizontal));
    vertical.jumpTo(225.0);
    await tester.pump();
    await tester.pumpWidget(_board(second, vertical, horizontal));
    // TARGET.
    expect(vertical.offset, 225.0);
  });
}
