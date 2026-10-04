/// Tests for item 7N of the board audit fixes: a resize strip shows a
/// resize cursor, and a drag holds its cursor for its whole length.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7N", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Every TARGET was red on the tree item 7M left, with every setup sanity
/// assertion before it passing.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

/// A two-row by two-column item at row 1, column 1, with every resize
/// strip on: 100 by 80 px, so each strip is the 12 px default.
Future<BoardController<String, _Item>> _pump(WidgetTester tester) async {
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
  // Registered after the dispose, so it runs before it: the board
  // unsubscribes when it unmounts.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  controller.addItem(
    const _Item("m"),
    const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 2, colSpan: 2),
  );
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
              cellBuilder: (context, cell) {
                return null;
              },
              itemBuilder: (context, item) {
                return ColoredBox(
                  key: _itemKey(item.key),
                  color: const Color(0xFF4CAF50),
                );
              },
              drag: BoardDragConfig<String>(
                primaryResizeEdges: BoardResizeEdges.both,
                resizeEdges: BoardResizeEdges.both,
                onItemMoved: (key, span) {
                  controller.moveItem(key, span);
                },
                onItemResized: (key, span) {
                  controller.resizeItem(key, span);
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return controller;
}

MouseCursor? _cursor() {
  return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
}

void main() {
  // Test 1.
  testWidgets("a resize strip shows its axis's resize cursor and the move "
      "zone none", (tester) async {
    await _pump(tester);
    final rect = tester.getRect(find.byKey(_itemKey("m")));
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();

    // The middle of the item: the move zone.
    await mouse.moveTo(rect.center);
    await tester.pump();
    // Setup sanity: the pointer is over the item, and nothing claims it.
    expect(_cursor(), SystemMouseCursors.basic);

    // TARGET: the bottom strip, on the vertical axis ...
    await mouse.moveTo(Offset(rect.center.dx, rect.bottom - 4.0));
    await tester.pump();
    expect(_cursor(), SystemMouseCursors.resizeUpDown);
    // ... the right strip, on the horizontal one ...
    await mouse.moveTo(Offset(rect.right - 4.0, rect.center.dy));
    await tester.pump();
    expect(_cursor(), SystemMouseCursors.resizeLeftRight);
    // ... and back in the move zone, none.
    await mouse.moveTo(rect.center);
    await tester.pump();
    expect(_cursor(), SystemMouseCursors.basic);
  });

  // Test 2.
  testWidgets("a drag holds its cursor off the strip, and gives it back at "
      "the release", (tester) async {
    await _pump(tester);
    final rect = tester.getRect(find.byKey(_itemKey("m")));
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();

    // A resize from the bottom strip, dragged well below the item.
    var pointer = Offset(rect.center.dx, rect.bottom - 4.0);
    await mouse.moveTo(pointer);
    await tester.pump();
    await mouse.down(pointer);
    await tester.pump();
    const move = Offset(0.0, 60.0);
    await mouse.moveBy(move);
    pointer += move;
    await tester.pump();
    // Setup sanity: the pointer is off the item, and so off its strip.
    expect(tester.getRect(find.byKey(_itemKey("m"))).contains(pointer), isFalse);
    // TARGET: the resize cursor holds ...
    expect(_cursor(), SystemMouseCursors.resizeUpDown);
    await mouse.up();
    await tester.pumpAndSettle();
    // ... and goes at the release, over an empty cell.
    expect(_cursor(), SystemMouseCursors.basic);
  });
}
