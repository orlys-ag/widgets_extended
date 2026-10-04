/// Item 3 of `plans/2026-09-23-board-audit-fixes-plan.md`: frozen bands.
/// Items wholly inside a band pin with it, and every point-to-cell
/// mapping, the reveal, the anchor, the visible bounds, the stock painter
/// and the autoscroll zones read the lattice as it paints.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_background.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_views.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

Key _cellKey(int row, int col) {
  return ValueKey<String>("c${row}_$col");
}

const BoardAnimationSpec _ms300 = BoardAnimationSpec(
  duration: Duration(milliseconds: 300),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

Widget _plainCell(BuildContext context, BoardCellView<String, _Item> cell) {
  return ColoredBox(
    key: _cellKey(cell.row, cell.col),
    color: cell.isFrozen ? const Color(0xFF2196F3) : const Color(0xFFE0E0E0),
  );
}

Widget? _nullCell(BuildContext context, BoardCellView<String, _Item> cell) {
  return null;
}

Widget _plainItem(BuildContext context, BoardItemView<String, _Item> item) {
  return ColoredBox(
    key: _itemKey(item.key),
    color: const Color(0xFF4CAF50),
  );
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  required BoardAxisConfig rows,
  BoardAxisConfig? columns,
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: rows,
    columns: columns ?? BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _frame(
  Widget board, {
  double width = 280.0,
  double height = 300.0,
}) {
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

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

Rect _painted(WidgetTester tester, Key key) {
  return tester
      .getRect(find.byKey(key))
      .shift(-tester.getRect(find.byKey(_frameKey)).topLeft);
}

void main() {
  group("pinning", () {
    testWidgets(
      "items wholly inside a frozen band stay with it; a straddler scrolls",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(
            axis: UniformAxis(30, 50.0),
            frozenStart: 1,
            frozenEnd: 1,
          ),
        );
        controller.addItem(
          const _Item("head"),
          const BoardSpan(rowStart: 0, colStart: 2),
        );
        controller.addItem(
          const _Item("foot"),
          const BoardSpan(rowStart: 29, colStart: 2),
        );
        controller.addItem(
          const _Item("both"),
          const BoardSpan(rowStart: 0, colStart: 4, rowSpan: 3),
        );
        final vertical = ScrollController();
        addTearDown(vertical.dispose);
        await tester.pumpWidget(
          _frame(
            Board<String, _Item>(
              controller: controller,
              verticalDetails: ScrollableDetails.vertical(
                controller: vertical,
              ),
              cellBuilder: _nullCell,
              itemBuilder: _plainItem,
            ),
          ),
        );
        // Setup sanity: the predicate agrees with the geometry.
        expect(
          controller.pinOfId(controller.idOfKey("head"), Axis.vertical),
          BoardPin.leading,
        );
        expect(
          controller.pinOfId(controller.idOfKey("foot"), Axis.vertical),
          BoardPin.trailing,
        );
        expect(
          controller.pinOfId(controller.idOfKey("both"), Axis.vertical),
          BoardPin.none,
        );
        vertical.jumpTo(300.0);
        await tester.pump();
        // TARGET: the band's items did not move with the content.
        expect(_painted(tester, _itemKey("head")).top, 0.0);
        expect(_painted(tester, _itemKey("foot")).bottom, 300.0);
        // TARGET: the straddler scrolled with it.
        expect(_painted(tester, _itemKey("both")).top, -300.0);
      },
    );

    testWidgets("a frozen column pins its items, and the corner pins both", (
      tester,
    ) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
        columns: BoardAxisConfig(axis: UniformAxis(30, 40.0), frozenStart: 1),
      );
      controller.addItem(
        const _Item("gutter"),
        const BoardSpan(rowStart: 5, colStart: 0),
      );
      controller.addItem(
        const _Item("corner"),
        const BoardSpan(rowStart: 0, colStart: 0),
      );
      final vertical = ScrollController();
      final horizontal = ScrollController();
      addTearDown(vertical.dispose);
      addTearDown(horizontal.dispose);
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            verticalDetails: ScrollableDetails.vertical(controller: vertical),
            horizontalDetails: ScrollableDetails.horizontal(
              controller: horizontal,
            ),
            cellBuilder: _nullCell,
            itemBuilder: _plainItem,
          ),
        ),
      );
      horizontal.jumpTo(200.0);
      vertical.jumpTo(100.0);
      await tester.pump();
      // TARGET: pinned horizontally, scrolled vertically.
      expect(_painted(tester, _itemKey("gutter")).topLeft, const Offset(0.0, 150.0));
      // TARGET: pinned both ways.
      expect(_painted(tester, _itemKey("corner")).topLeft, Offset.zero);
    });

    testWidgets(
      "a pinned item paints above its band's cells, and the band hides a "
      "scrolled item from taps and from itemAt",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
        );
        controller.addItem(
          const _Item("p"),
          const BoardSpan(rowStart: 0, colStart: 4),
        );
        controller.addItem(
          const _Item("s"),
          const BoardSpan(rowStart: 5, colStart: 2),
        );
        final taps = <String>[];
        final vertical = ScrollController();
        addTearDown(vertical.dispose);
        await tester.pumpWidget(
          _frame(
            Board<String, _Item>(
              controller: controller,
              verticalDetails: ScrollableDetails.vertical(
                controller: vertical,
              ),
              cellBuilder: (context, cell) {
                return GestureDetector(
                  key: _cellKey(cell.row, cell.col),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    taps.add("cell ${cell.row},${cell.col}");
                  },
                );
              },
              itemBuilder: (context, item) {
                return GestureDetector(
                  key: _itemKey(item.key),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    taps.add("item ${item.key}");
                  },
                );
              },
            ),
          ),
        );
        // Row 5 scrolled to paint 0..50, wholly under the header row.
        vertical.jumpTo(250.0);
        await tester.pump();
        final viewport = _viewport(tester);
        // Setup sanity: s paints under the header, p on it.
        expect(_painted(tester, _itemKey("s")).top, 0.0);
        expect(_painted(tester, _itemKey("p")).top, 0.0);

        await tester.tapAt(_global(tester, const Offset(180.0, 25.0)));
        await tester.tapAt(_global(tester, const Offset(100.0, 25.0)));
        // TARGET: the pinned item takes its tap over its band cell; the
        // band cell takes the one over the hidden scrolled item.
        expect(taps, <String>["item p", "cell 0,2"]);
        // TARGET: the probe agrees.
        expect(viewport.itemAt(const Offset(180.0, 25.0)), "p");
        expect(viewport.itemAt(const Offset(100.0, 25.0)), isNull);
        // Setup sanity: below the band, the scrolled item is found.
        vertical.jumpTo(200.0);
        await tester.pump();
        expect(viewport.itemAt(const Offset(100.0, 75.0)), "s");
      },
    );

    testWidgets(
      "a move out of a frozen row slides from where it painted, scrolled "
      "or not",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
          style: const BoardAnimationStyle(
            trackResize: _zero,
            itemSlide: _ms300,
            itemEnterExit: _zero,
          ),
        );
        controller.addItem(
          const _Item("f"),
          const BoardSpan(rowStart: 0, colStart: 0),
        );
        controller.addItem(
          const _Item("g"),
          const BoardSpan(rowStart: 0, colStart: 2),
        );
        final vertical = ScrollController();
        addTearDown(vertical.dispose);
        await tester.pumpWidget(
          _frame(
            Board<String, _Item>(
              controller: controller,
              verticalDetails: ScrollableDetails.vertical(
                controller: vertical,
              ),
              cellBuilder: _nullCell,
              itemBuilder: _plainItem,
            ),
          ),
        );
        // At offset 0: 0 to 150.
        controller.moveItem("f", const BoardSpan(rowStart: 3, colStart: 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        // TARGET: halfway.
        expect(_painted(tester, _itemKey("f")).top, closeTo(75.0, 1.0));
        await tester.pumpAndSettle();

        // Scrolled 100: g paints pinned at 0 and lands at 250 - 100.
        vertical.jumpTo(100.0);
        await tester.pump();
        expect(_painted(tester, _itemKey("g")).top, 0.0);
        controller.moveItem("g", const BoardSpan(rowStart: 5, colStart: 2));
        await tester.pump();
        // TARGET: it starts where it painted, pinned.
        expect(_painted(tester, _itemKey("g")).top, closeTo(0.0, 1.0));
        await tester.pump(const Duration(milliseconds: 150));
        // TARGET: halfway from 0 to 150.
        expect(_painted(tester, _itemKey("g")).top, closeTo(75.0, 1.0));
        await tester.pumpAndSettle();
        expect(_painted(tester, _itemKey("g")).top, 150.0);
      },
    );

    test("the pin predicate", () {
      final controller = BoardController<String, _Item>(
        vsync: const TestVSync(),
        rows: BoardAxisConfig(
          axis: UniformAxis(10, 50.0),
          frozenStart: 2,
          frozenEnd: 1,
          laneExtent: 12.0,
        ),
        columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      BoardPin pinOf(String key, BoardSpan span) {
        controller.addItem(_Item(key), span);
        return controller.pinOfId(controller.idOfKey(key), Axis.vertical);
      }

      // Inside the two-row leading band, whole or fractional.
      expect(pinOf("a", const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 2)), BoardPin.leading);
      expect(
        pinOf(
          "b",
          const BoardSpan(
            rowStart: 1,
            colStart: 1,
            rowFraction: 0.5,
            rowSpan: 0,
            rowSpanFraction: 0.5,
          ),
        ),
        BoardPin.leading,
      );
      // Across the band's edge: not pinned.
      expect(pinOf("c", const BoardSpan(rowStart: 1, colStart: 2, rowSpan: 2)), BoardPin.none);
      // The trailing band.
      expect(pinOf("d", const BoardSpan(rowStart: 9, colStart: 3)), BoardPin.trailing);
      // Unfrozen.
      expect(pinOf("e", const BoardSpan(rowStart: 5, colStart: 4)), BoardPin.none);
      // The span axis has no bands here.
      expect(
        controller.pinOfId(controller.idOfKey("a"), Axis.horizontal),
        BoardPin.none,
      );
    });
  });

  group("point mapping", () {
    testWidgets("a selection tap on a frozen cell selects that cell", (
      tester,
    ) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(40, 50.0), frozenStart: 1),
      );
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            verticalDetails: ScrollableDetails.vertical(controller: vertical),
            cellBuilder: _plainCell,
            selection: BoardSelectionConfig(
              mode: BoardSelectionMode.cell,
              onChanged: (selection) {},
            ),
          ),
        ),
      );
      vertical.jumpTo(200.0);
      await tester.pump();
      await tester.tapAt(_global(tester, const Offset(60.0, 10.0)));
      await tester.pump();
      // TARGET.
      expect(controller.selection.value.anchor, (row: 0, col: 1));
    });

    testWidgets("a cell-mode tap past a short lattice selects nothing", (
      tester,
    ) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(3, 50.0)),
      );
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _plainCell,
            selection: BoardSelectionConfig(
              mode: BoardSelectionMode.cell,
              onChanged: (selection) {},
            ),
          ),
        ),
      );
      // Setup sanity: the lattice ends at y 150 in a 300 tall board.
      expect(_painted(tester, _cellKey(2, 1)).bottom, 150.0);
      await tester.tapAt(_global(tester, const Offset(60.0, 250.0)));
      await tester.pump();
      // TARGET.
      expect(controller.selection.value.isEmpty, isTrue);
    });

    testWidgets(
      "a drop over a frozen header lands in the header, where it pins",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
        );
        controller.addItem(
          const _Item("m"),
          const BoardSpan(rowStart: 6, colStart: 1),
        );
        await tester.pumpWidget(
          _frame(
            Board<String, _Item>(
              controller: controller,
              cellBuilder: _nullCell,
              itemBuilder: _plainItem,
            ),
          ),
        );
        final viewport = _viewport(tester);
        viewport.verticalPosition!.jumpTo(100.0);
        await tester.pump();
        final drag = BoardDragController<String>(
          boardController: controller,
          vsync: tester,
          config: BoardDragConfig<String>(
            autoScrollEdgeZone: 0.0,
            onItemMoved: (key, span) {
              controller.moveItem(key, span);
            },
          ),
        );
        addTearDown(drag.dispose);
        final rect = viewport.rectOfItem("m")!;
        expect(rect.top, 200.0);
        expect(
          drag.startDrag(
            key: "m",
            renderPort: viewport,
            pointerGlobal: _global(tester, rect.center),
          ),
          isTrue,
        );
        // The proxy's corner at y 10, inside the header band.
        drag.updateDrag(_global(tester, const Offset(60.0, 35.0)));
        await tester.pump();
        drag.endDrag(cancel: false);
        await tester.pumpAndSettle();
        // TARGET: row 0, painted in the band at this offset.
        expect(controller.spanOf("m")!.rowStart, 0);
        expect(_painted(tester, _itemKey("m")).top, 0.0);
      },
    );

    testWidgets(
      "cellAt, resolveDropCell and rectOfCell read a frozen cell where it "
      "paints",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
        );
        await tester.pumpWidget(
          _frame(
            Board<String, _Item>(
              controller: controller,
              cellBuilder: _plainCell,
            ),
          ),
        );
        final viewport = _viewport(tester);
        viewport.verticalPosition!.jumpTo(500.0);
        await tester.pump();
        const point = Offset(60.0, 20.0);
        // TARGET.
        expect(viewport.cellAt(point), (row: 0, col: 1));
        expect(viewport.resolveDropCell(point).row, 0);
        expect(viewport.trackSpaceAt(point)!.row, closeTo(0.4, 1e-9));
        expect(viewport.rectOfCell(0, 1), const Rect.fromLTWH(40.0, 0.0, 40.0, 50.0));
        // Setup sanity: the frozen-only probe still answers the same cell.
        expect(viewport.frozenCellAt(point), (row: 0, col: 1));
      },
    );

    testWidgets(
      "trackSpaceAt reads the rows as they paint mid track resize",
      (tester) async {
        final heights = <int, double>{};
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(axis: LazyContentAxis(10, 50.0)),
          columns: BoardAxisConfig(axis: UniformAxis(3, 40.0)),
          style: const BoardAnimationStyle(
            trackResize: _ms300,
            itemSlide: _zero,
            itemEnterExit: _zero,
          ),
        );
        Widget board() {
          return _frame(
            Board<String, _Item>(
              controller: controller,
              cellBuilder: (context, cell) {
                return SizedBox(height: heights[cell.row] ?? 50.0);
              },
            ),
          );
        }

        await tester.pumpWidget(board());
        await tester.pumpAndSettle();
        heights[1] = 200.0;
        await tester.pumpWidget(board());
        await tester.pump(const Duration(milliseconds: 150));
        final port = _viewport(tester);
        final painted = port.rectOfCell(3, 0)!;
        // Setup sanity: mid resize, row 3 paints above its settled 300.
        expect(painted.top, lessThan(290.0));
        expect(painted.top, greaterThan(160.0));
        // TARGET.
        expect(port.trackSpaceAt(painted.center)!.row, closeTo(3.5, 1e-6));
        await tester.pumpAndSettle();
      },
    );
  });

  group("reveal and anchor", () {
    testWidgets(
      "showOnScreen brings a cell out from under the band, and leaves a "
      "frozen one where it is",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
        );
        final vertical = ScrollController(initialScrollOffset: 500.0);
        addTearDown(vertical.dispose);
        await tester.pumpWidget(
          _frame(
            Board<String, _Item>(
              controller: controller,
              verticalDetails: ScrollableDetails.vertical(controller: vertical),
              cellBuilder: _plainCell,
            ),
          ),
        );
        // Setup sanity: row 10 paints wholly under the header.
        expect(_painted(tester, _cellKey(10, 1)).top, 0.0);
        tester.renderObject(find.byKey(_cellKey(0, 1))).showOnScreen();
        await tester.pumpAndSettle();
        // TARGET: a frozen cell is on screen at every offset.
        expect(vertical.offset, 500.0);
        tester.renderObject(find.byKey(_cellKey(10, 1))).showOnScreen();
        await tester.pumpAndSettle();
        // TARGET: out from under the band, and no further.
        expect(_painted(tester, _cellKey(10, 1)).top, 50.0);
      },
    );

    testWidgets(
      "a growing frozen header on a content-sized axis pushes row 1 down",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(axis: LazyContentAxis(30, 50.0), frozenStart: 1),
          columns: BoardAxisConfig(axis: UniformAxis(2, 100.0)),
        );
        final vertical = ScrollController();
        addTearDown(vertical.dispose);
        var headerHeight = 40.0;
        Widget board() {
          return _frame(
            Board<String, _Item>(
              controller: controller,
              verticalDetails: ScrollableDetails.vertical(controller: vertical),
              cellBuilder: (context, cell) {
                return SizedBox(
                  key: _cellKey(cell.row, cell.col),
                  height: cell.row == 0 ? headerHeight : 30.0,
                );
              },
            ),
          );
        }

        await tester.pumpWidget(board());
        await tester.pumpAndSettle();
        expect(_painted(tester, _cellKey(1, 0)).top, 40.0);
        headerHeight = 60.0;
        await tester.pumpWidget(board());
        await tester.pumpAndSettle();
        // Setup sanity: the header grew and stays pinned.
        expect(_painted(tester, _cellKey(0, 0)), const Rect.fromLTWH(0.0, 0.0, 100.0, 60.0));
        // TARGET.
        expect(vertical.offset, 0.0);
        expect(_painted(tester, _cellKey(1, 0)).top, 60.0);
      },
    );
  });

  group("visible bounds and the grid", () {
    testWidgets("the visible bounds leave out rows wholly under the band", (
      tester,
    ) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
      );
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            verticalDetails: ScrollableDetails.vertical(controller: vertical),
            cellBuilder: _plainCell,
          ),
        ),
      );
      final viewport = _viewport(tester);
      // TARGET: at the top, the band is row 0 and the scrolled rows
      // start at 1.
      expect(viewport.firstVisibleRow, 1);
      expect(viewport.scrolledRegion, const Rect.fromLTRB(0.0, 50.0, 280.0, 300.0));
      vertical.jumpTo(500.0);
      await tester.pump();
      // TARGET: row 10 paints wholly under the band.
      expect(viewport.firstVisibleRow, 11);
    });

    testWidgets(
      "the grid painter draws each boundary once and no scrolled line "
      "inside the band",
      (tester) async {
        final controller = _controller(
          tester,
          rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
          columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
        );
        final vertical = ScrollController(initialScrollOffset: 520.0);
        addTearDown(vertical.dispose);
        await tester.pumpWidget(
          _frame(
            Board<String, _Item>(
              controller: controller,
              verticalDetails: ScrollableDetails.vertical(controller: vertical),
              cellBuilder: _plainCell,
            ),
          ),
        );
        final viewport = _viewport(tester);
        final canvas = TestRecordingCanvas();
        const BoardGridPainter().paint(canvas, viewport);
        final ys = <double>[];
        for (final recorded in canvas.invocations) {
          final invocation = recorded.invocation;
          if (invocation.memberName != #drawLine) {
            continue;
          }
          final p1 = invocation.positionalArguments[0] as Offset;
          final p2 = invocation.positionalArguments[1] as Offset;
          if (p1.dy == p2.dy) {
            ys.add(p1.dy);
          }
        }
        ys.sort();
        // TARGET: rows at 520 paint from 30 under the 0..50 header; the
        // horizontal boundaries on screen are the header's two and each
        // scrolled row's top below it: 80, 130, ..., 280, and the
        // lattice's end is past the viewport.
        expect(ys.where((y) => y > 0.0 && y < 50.0), isEmpty);
        expect(ys.toSet().length, ys.length);
        expect(ys.take(3), <double>[0.0, 50.0, 80.0]);
      },
    );
  });

  testWidgets(
    "autoscroll starts at the band's inner edge and not inside the band",
    (tester) async {
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
      );
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 10, colStart: 1),
      );
      final vertical = ScrollController(initialScrollOffset: 300.0);
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            verticalDetails: ScrollableDetails.vertical(controller: vertical),
            cellBuilder: _nullCell,
            itemBuilder: _plainItem,
          ),
        ),
      );
      final viewport = _viewport(tester);
      final drag = BoardDragController<String>(
        boardController: controller,
        vsync: tester,
        config: BoardDragConfig<String>(onItemMoved: (key, span) {}),
      );
      addTearDown(drag.dispose);
      final rect = viewport.rectOfItem("m")!;
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, rect.center),
        ),
        isTrue,
      );
      drag.updateDrag(_global(tester, const Offset(60.0, 25.0)));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // TARGET: inside the band, nothing scrolls.
      expect(vertical.offset, 300.0);
      drag.updateDrag(_global(tester, const Offset(60.0, 60.0)));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // TARGET: just below it, the content above comes into view.
      expect(vertical.offset, lessThan(300.0));
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle();
    },
  );
}
