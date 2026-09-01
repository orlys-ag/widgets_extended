/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 11 with the interaction layer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_views.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

BoardController<String, _Item> _controller(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  // AC20 range selection.
  // Asserts: BoardSelection.cells has 12 entries covering rows 1 to 3 and
  // columns 1 to 4.
  // Falsification: a value carrying only anchor and focus fails on the
  // cells assertion.
  testWidgets("dragging from (1,1) to (3,4) reports the whole enclosed "
      "rectangle", (tester) async {
    final controller = _controller(tester);
    final changes = <BoardSelection>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280.0,
              height: 300.0,
              child: Board<String, _Item>(
                controller: controller,
                selection: BoardSelectionConfig(onChanged: changes.add),
                cellBuilder: (context, cell) {
                  return const SizedBox(width: 40.0, height: 50.0);
                },
              ),
            ),
          ),
        ),
      ),
    );

    // Cell centers: (1,1) is (60, 75); (3,4) is (180, 175).
    final gesture = await tester.startGesture(const Offset(60.0, 75.0));
    await tester.pump();
    await gesture.moveTo(const Offset(180.0, 175.0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final selection = controller.selection.value;
    expect(selection.rowStart, 1);
    expect(selection.colStart, 1);
    expect(selection.rowEnd, 4);
    expect(selection.colEnd, 5);
    final cells = selection.cells.toList();
    expect(cells, hasLength(12));
    expect(cells.first, (row: 1, col: 1));
    expect(cells.last, (row: 3, col: 4));
    expect(changes, isNotEmpty);
  });

  // DERIVED name. No AC; the selection ownership block.
  // Asserts: before any setSelection, controller.selection.value.isEmpty
  // is true and BoardCellView.isSelected is false for every cell.
  // Falsification: no value built from two non-nullable corners can
  // satisfy this, which is the assertion the empty form exists for.
  testWidgets(
    "an untouched board reports an empty selection and no selected cell "
    "view",
    (tester) async {
      final controller = _controller(tester);
      final selectedSeen = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280.0,
              height: 300.0,
              child: Board<String, _Item>(
                controller: controller,
                cellBuilder: (context, cell) {
                  selectedSeen.add(cell.isSelected);
                  return const SizedBox(width: 40.0, height: 50.0);
                },
              ),
            ),
          ),
        ),
      );
      expect(controller.selection.value.isEmpty, isTrue);
      expect(selectedSeen, isNotEmpty);
      expect(selectedSeen, everyElement(isFalse));
    },
  );

  // DERIVED name. No AC; the selection ownership block.
  // Asserts: select() on a cell view makes isSelected true on the next
  // frame, controller.selection.value carries the collapsed anchor and
  // focus, and BoardSelectionConfig.onChanged fired once with that value
  // even though no pointer touched the board. The equality suppression
  // is pinned corner by corner: a second EQUAL write adds no
  // notification, and a write differing in only one corner adds one.
  testWidgets(
    "select() on a cell view routes through the controller and fires "
    "onChanged once",
    (tester) async {
      final controller = _controller(tester);
      final changes = <BoardSelection>[];
      BoardCellView<String, _Item>? probe;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280.0,
              height: 300.0,
              child: Board<String, _Item>(
                controller: controller,
                selection: BoardSelectionConfig(onChanged: changes.add),
                cellBuilder: (context, cell) {
                  if (cell.row == 2 && cell.col == 3) {
                    probe = cell;
                  }
                  return SizedBox(
                    key: ValueKey<String>("c${cell.row}_${cell.col}"),
                    width: 40.0,
                    height: 50.0,
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(probe, isNotNull);

      probe!.select();
      expect(changes, hasLength(1));
      expect(
        changes.single,
        const BoardSelection(
          anchor: (row: 2, col: 3),
          focus: (row: 2, col: 3),
        ),
      );
      await tester.pump();
      expect(controller.isSelected(2, 3), isTrue);

      // The equality suppression, one corner at a time: an EQUAL write
      // notifies nothing; changing only the focus notifies once; then
      // only the anchor.
      controller.setSelection(
        const BoardSelection(
          anchor: (row: 2, col: 3),
          focus: (row: 2, col: 3),
        ),
      );
      expect(changes, hasLength(1));
      controller.setSelection(
        const BoardSelection(
          anchor: (row: 2, col: 3),
          focus: (row: 2, col: 4),
        ),
      );
      expect(changes, hasLength(2));
      controller.setSelection(
        const BoardSelection(
          anchor: (row: 1, col: 3),
          focus: (row: 2, col: 4),
        ),
      );
      expect(changes, hasLength(3));

      // The == contract's other half: equal-but-distinct values share a
      // hashCode.
      expect(
        BoardSelection(
          anchor: (row: 2, col: 3),
          focus: (row: 2, col: 4),
        ).hashCode,
        BoardSelection(
          anchor: (row: 2, col: 3),
          focus: (row: 2, col: 4),
        ).hashCode,
      );
    },
  );
}
