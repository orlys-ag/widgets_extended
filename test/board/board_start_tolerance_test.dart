/// Item 4 of `plans/2026-09-23-board-audit-fixes-plan.md`: a laned item
/// moves by whole tracks on the lane axis under every snap, and a start
/// one ulp below an integer belongs to the track it leads into.
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
import 'package:widgets_extended/board/board_views.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

int _itemBuilds = 0;

Widget? _nullCell(BuildContext context, BoardCellView<String, _Item> cell) {
  return null;
}

Widget _countingItem(BuildContext context, BoardItemView<String, _Item> item) {
  _itemBuilds += 1;
  return const ColoredBox(color: Color(0xFF4CAF50));
}

/// One ulp below 1.0, the value `10 / 12 + 2 / 12` comes to in doubles.
double _ulpBelowOne() {
  const quantum = 1 / 12;
  return 10.0 * quantum + 2 * quantum;
}

BoardController<String, _Item> _calendar(WidgetTester tester) {
  // Hours down, days across; the days are the lane axis, so two events
  // overlapping in time on one day take a lane each.
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(24, 60.0)),
    columns: BoardAxisConfig(
      axis: UniformAxis(7, 170.0),
      laneExtent: 170.0,
    ),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _frame(Widget board, {double width = 700.0, double height = 700.0}) {
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

/// Lifts lane-1 event "b" at its centre and releases it on the spot under
/// [snap], returning what the config was handed.
Future<List<BoardSpan>> _dropBInPlace(
  WidgetTester tester,
  BoardSnap snap,
) async {
  final controller = _calendar(tester);
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
  );
  controller.addItem(
    const _Item("b"),
    const BoardSpan(rowStart: 3, colStart: 1, rowSpan: 2),
  );
  await tester.pumpWidget(
    _frame(
      Board<String, _Item>(
        controller: controller,
        cellBuilder: _nullCell,
        itemBuilder: _countingItem,
      ),
    ),
  );
  final viewport = _viewport(tester);
  final moves = <BoardSpan>[];
  final drag = BoardDragController<String>(
    boardController: controller,
    vsync: tester,
    config: BoardDragConfig<String>(
      snap: snap,
      autoScrollEdgeZone: 0.0,
      onItemMoved: (key, span) {
        moves.add(span);
      },
    ),
  );
  addTearDown(drag.dispose);
  // Setup sanity: b is laned into the second half of Tuesday.
  expect(controller.laneOf("b"), 1);
  final rect = viewport.rectOfItem("b")!;
  expect(rect.left, 255.0);
  expect(
    drag.startDrag(
      key: "b",
      renderPort: viewport,
      pointerGlobal: _global(tester, rect.center),
    ),
    isTrue,
  );
  drag.endDrag(cancel: false);
  await tester.pump();
  return moves;
}

void main() {
  group("whole tracks on a laned item's lane axis", () {
    testWidgets(
      "a zero-motion move of a lane-1 event under a fraction snap keeps "
      "its day",
      (tester) async {
        final moves = await _dropBInPlace(
          tester,
          const BoardSnap.fraction(0.25),
        );
        // TARGET.
        expect(
          moves.single,
          const BoardSpan(rowStart: 3, colStart: 1, rowSpan: 2),
        );
      },
    );

    testWidgets(
      "a zero-motion move of a lane-1 event under a free snap keeps its "
      "day",
      (tester) async {
        final moves = await _dropBInPlace(tester, const BoardSnap.free());
        // TARGET.
        expect(
          moves.single,
          const BoardSpan(rowStart: 3, colStart: 1, rowSpan: 2),
        );
      },
    );

    testWidgets(
      "a laned event under a fraction snap follows the finger across a "
      "day's edge",
      (tester) async {
        final controller = _calendar(tester);
        controller.addItem(
          const _Item("a"),
          const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
        );
        controller.addItem(
          const _Item("b"),
          const BoardSpan(rowStart: 3, colStart: 1, rowSpan: 2),
        );
        await tester.pumpWidget(
          _frame(
            Board<String, _Item>(
              controller: controller,
              cellBuilder: _nullCell,
              itemBuilder: _countingItem,
            ),
          ),
        );
        final viewport = _viewport(tester);
        final drag = BoardDragController<String>(
          boardController: controller,
          vsync: tester,
          config: BoardDragConfig<String>(
            snap: const BoardSnap.fraction(0.25),
            autoScrollEdgeZone: 0.0,
            onItemMoved: (key, span) {},
          ),
        );
        addTearDown(drag.dispose);
        final rect = viewport.rectOfItem("b")!;
        // Setup sanity: lane 1 of Tuesday, which ends at x 340.
        expect(rect.right, 340.0);
        // Grabbed 5px inside Tuesday's end, then 10px right: the finger
        // is over Wednesday, while the lane's leading edge is still
        // inside Tuesday.
        final grab = Offset(rect.right - 5.0, rect.center.dy);
        expect(
          drag.startDrag(
            key: "b",
            renderPort: viewport,
            pointerGlobal: _global(tester, grab),
          ),
          isTrue,
        );
        drag.updateDrag(_global(tester, grab + const Offset(10.0, 0.0)));
        // TARGET: the day under the finger, whole.
        expect(drag.currentTarget!.span.colStart, 2);
        expect(drag.currentTarget!.span.colFraction, 0.0);
        drag.endDrag(cancel: true);
        await tester.pumpAndSettle();
      },
    );

    testWidgets("a nudged laned event lands on a whole day", (tester) async {
      final controller = _calendar(tester);
      controller.addItem(
        const _Item("e"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      // An occupant on the morning half of Thursday.
      controller.addItem(
        const _Item("o"),
        const BoardSpan(
          rowStart: 2,
          colStart: 3,
          colSpan: 0,
          colSpanFraction: 0.5,
        ),
      );
      await tester.pumpWidget(
        _frame(
          Board<String, _Item>(
            controller: controller,
            cellBuilder: _nullCell,
            itemBuilder: _countingItem,
          ),
        ),
      );
      final viewport = _viewport(tester);
      final drag = BoardDragController<String>(
        boardController: controller,
        vsync: tester,
        config: BoardDragConfig<String>(
          snap: const BoardSnap.fraction(0.25),
          autoScrollEdgeZone: 0.0,
          dropFit: const BoardDropFit(rowRadius: 0.0, colRadius: 1.0),
          canDropAt: (key, span) {
            for (final other in controller.itemsIn(
              span.rowStart,
              span.rowStart + span.rowSpan,
              span.colStart,
              span.colStart + 1,
            )) {
              if (other == key) {
                continue;
              }
              final o = controller.spanOf(other)!;
              if (o.startTrackOn(Axis.horizontal) <
                      span.endTrackOn(Axis.horizontal) &&
                  o.endTrackOn(Axis.horizontal) >
                      span.startTrackOn(Axis.horizontal)) {
                return false;
              }
            }
            return true;
          },
          onItemMoved: (key, span) {},
        ),
      );
      addTearDown(drag.dispose);
      final rect = viewport.rectOfItem("e")!;
      expect(
        drag.startDrag(
          key: "e",
          renderPort: viewport,
          pointerGlobal: _global(tester, rect.center),
        ),
        isTrue,
      );
      // Over Thursday, which the occupant refuses.
      drag.updateDrag(_global(tester, Offset(3 * 170.0 + 85.0, rect.center.dy)));
      final target = drag.currentTarget!.span;
      // TARGET: nudged by whole days, never to half of one.
      expect(target.colFraction, 0.0);
      expect(target.colStart, anyOf(2, 4));
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle();
    });
  });

  group("a near-integer start", () {
    testWidgets(
      "itemsAt does not list an item in the track before its start, on "
      "either axis",
      (tester) async {
        final controller = BoardController<String, _Item>(
          vsync: tester,
          rows: BoardAxisConfig(axis: UniformAxis(24, 40.0)),
          columns: BoardAxisConfig(axis: UniformAxis(7, 60.0)),
          keyOf: (item) {
            return item.key;
          },
          animationStyle: BoardAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        final start = _ulpBelowOne();
        // Setup sanity: one ulp below 1.0, splitting to integer track 0.
        expect(start, lessThan(1.0));
        expect(start.floor(), 0);
        controller.addItem(
          _Item("row"),
          BoardSpan(
            rowStart: 0,
            rowFraction: start,
            rowSpan: 1,
            colStart: 0,
          ),
        );
        controller.addItem(
          _Item("col"),
          BoardSpan(rowStart: 5, colStart: 0, colFraction: start, colSpan: 1),
        );
        expect(controller.itemsAt(1, 0), contains("row"));
        expect(controller.itemsAt(5, 1), contains("col"));
        // TARGET.
        expect(controller.itemsAt(0, 0), isNot(contains("row")));
        expect(controller.itemsAt(5, 0), isNot(contains("col")));
        // TARGET: the vicinity's row is the one the item starts in.
        expect(controller.primaryStartOfId(controller.idOfKey("row")), 1);
      },
    );

    testWidgets(
      "two overlapping chips at a near-integer lane-axis start take two "
      "lanes",
      (tester) async {
        final controller = BoardController<String, _Item>(
          vsync: tester,
          rows: BoardAxisConfig(axis: UniformAxis(6, 40.0), laneExtent: 12.0),
          columns: BoardAxisConfig(axis: UniformAxis(7, 60.0)),
          keyOf: (item) {
            return item.key;
          },
          animationStyle: BoardAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        final start = _ulpBelowOne();
        BoardSpan chip(int colStart) {
          return BoardSpan(
            rowStart: 0,
            rowFraction: start,
            rowSpan: 1,
            colStart: colStart,
            colSpan: 2,
          );
        }

        controller.addItem(const _Item("a"), chip(0));
        controller.addItem(const _Item("b"), chip(1));
        // TARGET.
        expect(controller.laneCountOf("a"), 2);
        expect(controller.laneCountOf("b"), 2);
      },
    );

    testWidgets(
      "a laned chip at a near-integer start paints in the row it starts in",
      (tester) async {
        final controller = BoardController<String, _Item>(
          vsync: tester,
          rows: BoardAxisConfig(axis: UniformAxis(6, 40.0), laneExtent: 12.0),
          columns: BoardAxisConfig(axis: UniformAxis(7, 60.0)),
          keyOf: (item) {
            return item.key;
          },
          animationStyle: BoardAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        controller.addItem(
          const _Item("a"),
          const BoardSpan(rowStart: 1, colStart: 0, colSpan: 2),
        );
        controller.addItem(
          _Item("b"),
          BoardSpan(
            rowStart: 0,
            rowFraction: _ulpBelowOne(),
            rowSpan: 1,
            colStart: 1,
            colSpan: 2,
          ),
        );
        await tester.pumpWidget(
          _frame(
            Board<String, _Item>(
              controller: controller,
              cellBuilder: _nullCell,
              itemBuilder: _countingItem,
            ),
            width: 420.0,
            height: 240.0,
          ),
        );
        final viewport = _viewport(tester);
        // TARGET: b is laned beside a in row 1 (40..80), not in row 0.
        final b = viewport.rectOfItem("b")!;
        expect(b.top, greaterThanOrEqualTo(40.0 - 1e-9));
        expect(b.bottom, lessThanOrEqualTo(80.0 + 1e-9));
        expect(controller.laneOf("b"), 1);
      },
    );

    testWidgets(
      "a selection of the row before a near-integer start does not "
      "rebuild the item",
      (tester) async {
        final controller = BoardController<String, _Item>(
          vsync: tester,
          rows: BoardAxisConfig(axis: UniformAxis(6, 40.0)),
          columns: BoardAxisConfig(axis: UniformAxis(7, 60.0)),
          keyOf: (item) {
            return item.key;
          },
          animationStyle: BoardAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        controller.addItem(
          _Item("m"),
          BoardSpan(
            rowStart: 0,
            rowFraction: _ulpBelowOne(),
            rowSpan: 1,
            colStart: 2,
          ),
        );
        await tester.pumpWidget(
          _frame(
            Board<String, _Item>(
              controller: controller,
              cellBuilder: _nullCell,
              itemBuilder: _countingItem,
            ),
            width: 420.0,
            height: 240.0,
          ),
        );
        _itemBuilds = 0;
        controller.setSelection(
          const BoardSelection(anchor: (row: 0, col: 2), focus: (row: 0, col: 2)),
        );
        await tester.pump();
        // TARGET: row 0 is not the item's.
        expect(_itemBuilds, 0);
        // Setup sanity: row 1 is, and rebuilds it.
        controller.setSelection(
          const BoardSelection(anchor: (row: 1, col: 2), focus: (row: 1, col: 2)),
        );
        await tester.pump();
        expect(_itemBuilds, 1);
      },
    );
  });

  group("exact sources", () {
    test("BoardSnap.fraction lands a whole number of tracks exactly", () {
      // 49 quanta of 1/49 and 180 of 0.35 each come to one ulp below an
      // integer in doubles.
      expect(49 * (1 / 49), lessThan(1.0));
      expect(180 * 0.35, lessThan(63.0));
      // TARGET.
      expect(const BoardSnap.fraction(1 / 49).quantize(1.0), 1.0);
      expect(const BoardSnap.fraction(0.35).quantize(63.0), 63.0);
    });

    test("a drop target's leading cell is the one its start is in", () {
      final target = BoardDropTarget(
        span: BoardSpan(
          rowStart: 0,
          rowFraction: _ulpBelowOne(),
          rowSpan: 1,
          colStart: 2,
        ),
        kind: BoardDragKind.move,
      );
      // TARGET.
      expect(target.cell, (row: 1, col: 2));
    });

    test("a drop-fit candidate on a track edge starts exactly there", () {
      const quantum = 1 / 12;
      final box = BoardSpan(
        rowStart: 0,
        rowFraction: 10 * quantum,
        rowSpan: 0,
        rowSpanFraction: quantum,
        colStart: 0,
      );
      // Everything from 8/12 to 1 is taken, so the nearest free
      // placement is two quanta later, at 1.0.
      final blocker = BoardSpan(
        rowStart: 0,
        rowFraction: 8 * quantum,
        rowSpan: 0,
        rowSpanFraction: 4 * quantum,
        colStart: 0,
      );
      final fit = BoardDropFitter.nearestFit(
        box: box,
        policy: const BoardDropFit(rowRadius: 1.0, colRadius: 0.0),
        snap: const BoardSnap.fraction(quantum),
        rowAxis: UniformAxis(24, 40.0),
        colAxis: UniformAxis(7, 60.0),
        rowWindow: (min: 0.0, max: 24 - quantum),
        colWindow: (min: 0.0, max: 6.0),
        obstacles: <BoardSpan>[blocker],
        accepts: (candidate) {
          return true;
        },
      );
      // TARGET.
      expect(fit, isNotNull);
      expect(fit!.rowStart, 1);
      expect(fit.rowFraction, 0.0);
    });
  });
}
