/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 7 with the item-cluster contributor term.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

Key _cellKey(int row, int col) {
  return ValueKey<String>("c${row}_$col");
}

void main() {
  // AC1 intrinsic sizing over item clusters.
  // Asserts: the row measures 4 * laneExtent + lanePadding while its
  // cellBuilder returns a 20px widget, read through tester.getRect of a
  // keyed cell probe.
  // Falsification: a cells-only rule returns 20 and fails.
  testWidgets("a week row of EMPTY cells is sized by four overlapping items", (
    tester,
  ) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(
        axis: LazyContentAxis(4, 30.0),
        laneExtent: 18.0,
        lanePadding: 4.0,
      ),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    // Four MUTUALLY overlapping chips in week row 1: one cluster of four
    // lanes.
    for (var i = 0; i < 4; i++) {
      controller.addItem(
        _Item("chip$i"),
        const BoardSpan(rowStart: 1, colStart: 2, colSpan: 3),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280.0,
              height: 400.0,
              child: Board<String, _Item>(
                controller: controller,
                cellBuilder: (context, cell) {
                  return SizedBox(
                    key: _cellKey(cell.row, cell.col),
                    width: 40.0,
                    height: 20.0,
                  );
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

    // Setup sanity: the cluster really is four deep.
    expect(controller.laneCountOf("chip0"), 4);

    // The row holds its cluster: 4 * 18 + 4 = 76, not the cells' 20.
    final cell = tester.getRect(find.byKey(_cellKey(1, 0)));
    expect(cell.height, 76.0);
    // A row with no items keeps the cells-only measurement.
    final plain = tester.getRect(find.byKey(_cellKey(0, 0)));
    expect(plain.height, 20.0);
  });

  // The I15 content-axis assert, step 7's obligation: it needs both facts
  // in hand (a contributing cluster AND a null laneExtent), which only the
  // sizing step ever has together.
  // Falsification: the same board with laneExtent set pumps clean, and
  // with the items removed pumps clean too, so the case fails on the
  // conjunction and not on the config alone; an implementation asserting
  // on the CONFIG rather than a contributing cluster reddens the
  // no-items arm.
  testWidgets(
    "a content-sized axis with contributing item clusters and no "
    "laneExtent asserts",
    (tester) async {
      Widget boardFor(BoardController<String, _Item> controller) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280.0,
              height: 400.0,
              child: Board<String, _Item>(
                controller: controller,
                cellBuilder: (context, cell) {
                  return const SizedBox(width: 40.0, height: 20.0);
                },
                itemBuilder: (context, item) {
                  return const ColoredBox(color: Color(0xFF4CAF50));
                },
              ),
            ),
          ),
        );
      }

      BoardController<String, _Item> controllerWith({double? laneExtent}) {
        final controller = BoardController<String, _Item>(
          vsync: tester,
          rows: BoardAxisConfig(
            axis: LazyContentAxis(4, 30.0),
            laneExtent: laneExtent,
          ),
          columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
          keyOf: (item) {
            return item.key;
          },
          animationStyle: BoardAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        return controller;
      }

      // The clean arms run FIRST: an intentional layout throw poisons the
      // element tree for every later pump in the same body.
      // Arm 1: the SAME shape with laneExtent set pumps clean.
      final laned = controllerWith(laneExtent: 18.0);
      laned.addItem(
        const _Item("chip"),
        const BoardSpan(rowStart: 1, colStart: 2, colSpan: 3),
      );
      await tester.pumpWidget(boardFor(laned));
      expect(tester.takeException(), isNull);

      // Arm 2: null laneExtent with NO items pumps clean, which is what
      // reddens an assert written against the config alone.
      final empty = controllerWith();
      await tester.pumpWidget(boardFor(empty));
      expect(tester.takeException(), isNull);

      // Arm 2b: laneExtent on the OTHER axis, none on the content axis,
      // plus a single-track item. LEGAL: the lanes stack along the
      // columns, no contributor term exists for the rows, and the assert
      // must not fire. Reddens a predicate that tests only the content
      // config's laneExtent.
      final crossLaned = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: LazyContentAxis(4, 30.0)),
        columns: BoardAxisConfig(
          axis: UniformAxis(7, 40.0),
          laneExtent: 18.0,
        ),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(crossLaned.dispose);
      crossLaned.addItem(
        const _Item("chip"),
        const BoardSpan(rowStart: 1, colStart: 2, colSpan: 3),
      );
      await tester.pumpWidget(boardFor(crossLaned));
      expect(tester.takeException(), isNull);

      // Arm 3, LAST: null laneExtent AND a contributing single-track
      // item: the pump throws.
      final broken = controllerWith();
      broken.addItem(
        const _Item("chip"),
        const BoardSpan(rowStart: 1, colStart: 2, colSpan: 3),
      );
      await tester.pumpWidget(boardFor(broken));
      expect(tester.takeException(), isA<AssertionError>());
    },
  );
}
