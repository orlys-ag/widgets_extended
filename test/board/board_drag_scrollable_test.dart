/// The host's pointer tracking on a SCROLLABLE board.
///
/// Inside a scrollable, the item handle's recognizer shares the arena
/// with the scrollable's own, so it is accepted on the first move past
/// the touch slop rather than at pointer down, and the multi-drag
/// recognizer then reports that accepting move as a DELTA against the
/// initial position (`gestures/multidrag.dart:139-153`). A host that
/// reads the update's position alone loses that move; the framework's
/// own drag avatar accumulates deltas (`widgets/drag_target.dart:873-876`)
/// and so does the host now. A board whose content fits its viewport
/// never showed this: its scrollables accept no user offset
/// (`widgets/scroll_physics.dart:218-226`), the arena has one member, and
/// the drag starts at pointer down.
///
/// Both cases failed at the assertion marked TARGET before the fix: the
/// drag session resolved the initial position, so the end edge stayed
/// put and no resize was reported, and the range selection's focus stayed
/// on its anchor cell.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

void main() {
  testWidgets("an immediate strip drag on a scrollable board lands the move "
      "that accepted it", (tester) async {
    // Twelve 50px rows in a 300px frame: the vertical scrollable accepts
    // user offsets, so the strip's recognizer contends in the arena.
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(12, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 2),
    );
    final resizes = <BoardSpan>[];
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
                drag: BoardDragConfig<String>(
                  onItemMoved: (key, span) {},
                  onItemResized: (key, span) {
                    resizes.add(span);
                    controller.resizeItem(key, span);
                  },
                  primaryResizeEdges: BoardResizeEdges.trailing,
                ),
                cellBuilder: (context, cell) {
                  return const SizedBox(width: 40.0, height: 50.0);
                },
                itemBuilder: (context, item) {
                  return ColoredBox(
                    key: ValueKey<String>("i${item.key}"),
                    color: const Color(0xFF4CAF50),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    final viewport = tester.allRenderObjects
        .whereType<RenderBoardViewport<String>>()
        .single;
    // Setup sanity: the board scrolls, and the item sits where the strip
    // geometry assumes.
    expect(viewport.verticalPosition!.maxScrollExtent, greaterThan(0.0));
    final rect = tester.getRect(find.byKey(const ValueKey<String>("im")));
    expect(rect.height, 100.0);
    // ONE move, from the bottom strip, one row down: the move that
    // accepts the gesture is the only move there is.
    final gesture = await tester.startGesture(
      Offset(rect.center.dx, rect.bottom - 4.0),
    );
    await gesture.moveBy(const Offset(0.0, 50.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // TARGET.
    expect(resizes, hasLength(1));
    expect(
      resizes.single,
      const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 3),
    );
    expect(viewport.rectOfItem("m")!.height, 150.0);
  });

  testWidgets("an immediate range selection on a scrollable board extends "
      "by the move that accepted it", (tester) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(12, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
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
                selection: BoardSelectionConfig(onChanged: (selection) {}),
                cellBuilder: (context, cell) {
                  return const SizedBox(width: 40.0, height: 50.0);
                },
              ),
            ),
          ),
        ),
      ),
    );
    final viewport = tester.allRenderObjects
        .whereType<RenderBoardViewport<String>>()
        .single;
    expect(viewport.verticalPosition!.maxScrollExtent, greaterThan(0.0));
    final origin = tester.getRect(find.byType(Board<String, _Item>)).topLeft;
    // ONE move, from the centre of cell (2, 2) one row down.
    final gesture = await tester.startGesture(
      origin + viewport.rectOfCell(2, 2)!.center,
    );
    await gesture.moveBy(const Offset(0.0, 50.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final selection = controller.selection.value;
    // TARGET: two rows, anchor to the cell under the moved pointer.
    expect(selection.rowStart, 2);
    expect(selection.rowEnd, 4);
    expect(selection.colStart, 2);
    expect(selection.colEnd, 3);
  });
}
