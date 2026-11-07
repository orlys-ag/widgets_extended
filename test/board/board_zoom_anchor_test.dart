/// Tests for item 7P of the board audit fixes: a new axis config keeps
/// the scrolled region's leading edge on the same place in the lattice.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7P", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Cases 1 to 3 were red at their TARGETs on the tree item 7O left, with
/// every setup sanity assertion before them passing; case 4 pins what the
/// change must keep.
///
/// And a landing ([BoardController.landSwappedAxisAt]), which puts a named
/// track there in place of the one the anchor keeps (LA1 to LA8).
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

  /// [controller]'s board scrolled so row 4 and a half of its 24 rows of
  /// 50 px lies at the top.
  Future<void> atRowFourAndAHalf(
    WidgetTester tester,
    BoardController<String, _Item> controller,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(_board(controller, vertical, horizontal));
    vertical.jumpTo(225.0);
    await tester.pumpAndSettle();
    // Setup sanity: row 4 and a half at the top.
    expect(vertical.offset, 225.0);
  }

  BoardController<String, _Item> rowsOfFifty(WidgetTester tester) {
    return _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(24, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    );
  }

  testWidgets("LA1 a landing puts the row it names at the top of the new "
      "rows, one past the old rows' count included", (tester) async {
    final controller = rowsOfFifty(tester);
    await atRowFourAndAHalf(tester, controller);
    controller.rows = BoardAxisConfig(axis: UniformAxis(96, 25.0));
    controller.landSwappedAxisAt(Axis.vertical, 40.5);
    await tester.pump();
    expect(vertical.offset, 1012.5);
  });

  testWidgets("LA2 a landing puts the row it names under a frozen header, "
      "or the distance it names from the viewport's top", (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(24, 50.0), frozenStart: 1),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    );
    await atRowFourAndAHalf(tester, controller);
    BoardAxisConfig finer() {
      return BoardAxisConfig(
        axis: ExplicitAxis(<double>[50.0, for (var i = 1; i < 48; i++) 25.0]),
        frozenStart: 1,
      );
    }

    controller.rows = finer();
    controller.landSwappedAxisAt(Axis.vertical, 30.0);
    await tester.pump();
    // Row 30's top, 50 + 29 * 25 in content, under the 50 px band.
    expect(vertical.offset, 725.0);
    controller.rows = finer();
    controller.landSwappedAxisAt(Axis.vertical, 30.0, at: 80.0);
    await tester.pump();
    // Row 30's top 80 px down the viewport.
    expect(vertical.offset, 695.0);
  });

  testWidgets("LA3 a landing lands once: the instance it named, laid out "
      "again later, takes the anchor's", (tester) async {
    final controller = rowsOfFifty(tester);
    await atRowFourAndAHalf(tester, controller);
    final finer = BoardAxisConfig(axis: UniformAxis(96, 25.0));
    controller.rows = finer;
    controller.landSwappedAxisAt(Axis.vertical, 40.5);
    await tester.pump();
    // Setup sanity: landed.
    expect(vertical.offset, 1012.5);
    controller.rows = BoardAxisConfig(axis: UniformAxis(96, 50.0));
    await tester.pump();
    vertical.jumpTo(500.0);
    await tester.pump();
    controller.rows = finer;
    await tester.pump();
    // Row 10 at the top, as the anchor keeps it.
    expect(vertical.offset, 250.0);
  });

  testWidgets("LA4 a landing given before another new axis instance lands "
      "nothing", (tester) async {
    final controller = rowsOfFifty(tester);
    await atRowFourAndAHalf(tester, controller);
    controller.rows = BoardAxisConfig(axis: UniformAxis(96, 25.0));
    controller.landSwappedAxisAt(Axis.vertical, 40.5);
    controller.rows = BoardAxisConfig(axis: UniformAxis(96, 50.0));
    await tester.pump();
    // Row 4 and a half at the top, as the anchor keeps it.
    expect(vertical.offset, 225.0);
  });

  testWidgets("LA5 a landing on a controller new to the board lands "
      "nothing, then or at a later swap back to the instance it named", (
    tester,
  ) async {
    final first = rowsOfFifty(tester);
    final second = rowsOfFifty(tester);
    await atRowFourAndAHalf(tester, second);
    final finer = BoardAxisConfig(axis: UniformAxis(96, 25.0));
    first.rows = finer;
    first.landSwappedAxisAt(Axis.vertical, 40.5);
    await tester.pumpWidget(_board(first, vertical, horizontal));
    expect(vertical.offset, 225.0);
    first.rows = BoardAxisConfig(axis: UniformAxis(96, 50.0));
    await tester.pump();
    first.rows = finer;
    await tester.pump();
    // Row 9 at the top, as the anchor keeps it.
    expect(vertical.offset, 225.0);
  });

  testWidgets("LA6 a landing past either end of the rows lands at that end "
      "of the scroll range", (tester) async {
    final controller = rowsOfFifty(tester);
    await atRowFourAndAHalf(tester, controller);
    controller.rows = BoardAxisConfig(axis: UniformAxis(96, 25.0));
    controller.landSwappedAxisAt(Axis.vertical, 200.0);
    await tester.pump();
    // 96 * 25 less the 300 px viewport.
    expect(vertical.offset, 2100.0);
    controller.rows = BoardAxisConfig(axis: UniformAxis(96, 25.0));
    controller.landSwappedAxisAt(Axis.vertical, -5.0);
    await tester.pump();
    expect(vertical.offset, 0.0);
  });

  testWidgets("LA7 a landing on new columns puts the column it names at "
      "the distance it names from the leading edge", (tester) async {
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
    await tester.pumpAndSettle();
    // Setup sanity: column 2 and a half at the leading edge.
    expect(horizontal.offset, 100.0);
    controller.columns = BoardAxisConfig(axis: UniformAxis(120, 20.0));
    controller.landSwappedAxisAt(Axis.horizontal, 60.25, at: 10.0);
    await tester.pump();
    expect(horizontal.offset, 1195.0);
  });

  testWidgets("LA8 an animated scroll in flight on the axis goes on to its "
      "cell past a landing", (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(60, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(_board(controller, vertical, horizontal));
    final landed = controller.animateScrollToCell(40, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: the scroll is under way.
    expect(vertical.offset, allOf(greaterThan(0.0), lessThan(2000.0)));
    controller.rows = BoardAxisConfig(axis: UniformAxis(60, 25.0));
    controller.landSwappedAxisAt(Axis.vertical, 5.0);
    await tester.pump();
    // Setup sanity: the landing applied.
    expect(vertical.offset, 125.0);
    await tester.pumpAndSettle();
    expect(await landed, isTrue);
    expect(vertical.offset, 1000.0);
  });
}
