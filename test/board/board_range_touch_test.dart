/// Tests for item 7I of the board audit fixes: range selection starts at
/// once for a precise pointer and after a long press for touch, so a touch
/// drag over cells scrolls.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7I", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Case 1 was red at its TARGET on the tree item 7H left, with every
/// setup sanity assertion before it passing; cases 2, 3 and 4 pin what
/// the change must keep, and were shown red against a mutation each.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

/// 40 rows of 50 px under a 300 px frame, seven 40 px columns.
BoardController<String, _Item> _controller(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(40, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
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

Widget _board(
  BoardController<String, _Item> controller,
  ScrollController vertical, {
  BoardDragConfig<String>? drag,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: _frameKey,
          width: 280.0,
          height: 300.0,
          child: Board<String, _Item>(
            controller: controller,
            verticalDetails: ScrollableDetails.vertical(controller: vertical),
            drag: drag,
            cellBuilder: (context, cell) {
              return const SizedBox.expand();
            },
            itemBuilder: (context, item) {
              return const ColoredBox(color: Color(0xFF4CAF50));
            },
            selection: BoardSelectionConfig(onChanged: (selection) {}),
          ),
        ),
      ),
    ),
  );
}

Offset _at(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

void main() {
  // Test 1 (A4).
  testWidgets("a touch drag over cells scrolls and selects nothing",
      (tester) async {
    final controller = _controller(tester);
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(_board(controller, vertical));
    // Setup sanity: range is the mode, and nothing is selected.
    expect(controller.selection.value.isEmpty, isTrue);
    await tester.dragFrom(
      _at(tester, const Offset(100.0, 250.0)),
      const Offset(0.0, -200.0),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    // TARGET: the board scrolled ...
    expect(vertical.offset, greaterThan(0.0));
    // ... and selected nothing.
    expect(controller.selection.value.isEmpty, isTrue);
  });

  // Test 2 (A4).
  testWidgets("a touch long press then a drag selects a range",
      (tester) async {
    final controller = _controller(tester);
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(_board(controller, vertical));
    // Row 4, column 1.
    final gesture = await tester.startGesture(
      _at(tester, const Offset(60.0, 225.0)),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    // Two rows UP, two columns right: row 2, column 3. Upward, so a drag
    // the scrollable took instead would scroll it off offset 0.
    await gesture.moveBy(const Offset(80.0, -100.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // TARGET: the range ...
    expect(
      controller.selection.value,
      const BoardSelection(
        anchor: (row: 4, col: 1),
        focus: (row: 2, col: 3),
      ),
    );
    // ... and no scroll.
    expect(vertical.offset, 0.0);
  });

  // Test 3 (A4), what must be kept: a mouse selects at once.
  testWidgets("a mouse drag selects a range at once", (tester) async {
    final controller = _controller(tester);
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(_board(controller, vertical));
    final gesture = await tester.startGesture(
      _at(tester, const Offset(60.0, 125.0)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(80.0, 100.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // TARGET.
    expect(
      controller.selection.value,
      const BoardSelection(
        anchor: (row: 2, col: 1),
        focus: (row: 4, col: 3),
      ),
    );
    // Whether it scrolled is not asserted: a mouse is not a drag device of
    // the default scroll behavior, so it never could.
  });

  // Test 4, what must be kept: a long press on an ITEM drags the item.
  // Its handle's delayed recognizer joins the arena first and its timer
  // fires first.
  testWidgets("a touch long press on an item drags the item, not a range",
      (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    final moves = <BoardSpan>[];
    await tester.pumpWidget(
      _board(
        controller,
        vertical,
        drag: BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moves.add(span);
            controller.moveItem(key, span);
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      _at(tester, const Offset(60.0, 125.0)),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    // TARGET: the item is dragged ...
    expect(controller.isDragging("m"), isTrue);
    await gesture.moveBy(const Offset(80.0, 100.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // ... to where it was dropped, and no range was selected.
    expect(moves, <BoardSpan>[const BoardSpan(rowStart: 4, colStart: 3)]);
    expect(controller.selection.value.isEmpty, isTrue);
  });
}
