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
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

void main() {
  // AC20 range selection, the snap half.
  // Asserts: the selection edges are quantized by the fractional snap: a
  // touch at track-space 1.6 under a half-track quantum resolves cell 1,
  // while plain containment would also give 1; the discriminating touch
  // is 1.8, whose half-track quantization rounds to 2.0 and selects
  // cell 2 where containment keeps 1.
  testWidgets("a fractional snap quantizes the selection edges", (
    tester,
  ) async {
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
                selection: BoardSelectionConfig(
                  onChanged: changes.add,
                  snap: const BoardSnap.fraction(0.5),
                ),
                cellBuilder: (context, cell) {
                  return const SizedBox(width: 40.0, height: 50.0);
                },
              ),
            ),
          ),
        ),
      ),
    );

    // Row track-space 1.8 (y = 90): the half-track quantization rounds
    // to 2.0 and the anchor lands in row 2; containment alone would keep
    // row 1. Column 0.4 (x = 16) quantizes to 0.5, cell 0.
    final gesture = await tester.startGesture(const Offset(16.0, 90.0));
    await tester.pump();
    // Drag to row-space 3.1 (y = 155): quantizes to 3.0, focus row 3.
    await gesture.moveTo(const Offset(16.0, 155.0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final selection = controller.selection.value;
    expect(selection.rowStart, 2);
    expect(selection.rowEnd, 4);
    expect(selection.colStart, 0);
    expect(selection.colEnd, 1);
    expect(changes, isNotEmpty);
  });

  // DERIVED name. No AC.
  // Asserts: BoardSnap.quantize directly for all three modes, including
  // that fraction is null for track and free, which is what makes the
  // value branchable at all.
  test(
    "BoardSnap.quantize covers all three modes and leaves fraction null "
    "for track and free",
    () {
      const track = BoardSnap.track();
      expect(track.mode, BoardSnapMode.track);
      expect(track.fraction, isNull);
      expect(track.quantize(2.6), 3.0);
      expect(track.quantize(2.4), 2.0);

      const quarter = BoardSnap.fraction(0.25);
      expect(quarter.mode, BoardSnapMode.fraction);
      expect(quarter.fraction, 0.25);
      expect(quarter.quantize(2.6), 2.5);
      expect(quarter.quantize(2.9), 3.0);

      const free = BoardSnap.free();
      expect(free.mode, BoardSnapMode.free);
      expect(free.fraction, isNull);
      expect(free.quantize(2.618), 2.618);
    },
  );

  // The RESIZE ARM's conversion from a quantized edge to a span, as a
  // PAIR on one fixture: the same quarter-track drag commits colSpan 0
  // with colSpanFraction 0.25 under fraction(0.25) and colSpan 1 with
  // 0.0 under track(), through the quantum floor. An implementation
  // keeping a span >= 1 floor fails the first while passing the second;
  // one that never quantizes fails the second while passing the first.
  testWidgets(
    "the same quarter-track resize commits a fractional span under "
    "fraction and a whole one under track",
    (tester) async {
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
      controller.addItem(
        const _Item("r"),
        const BoardSpan(rowStart: 0, colStart: 1),
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
                    return const SizedBox(width: 40.0, height: 50.0);
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
      final viewport = tester.allRenderObjects
          .whereType<RenderBoardViewport<String>>()
          .single;

      Future<BoardSpan> resize(BoardSnap snap) async {
        final resizes = <BoardSpan>[];
        final drag = BoardDragController<String>(
          boardController: controller,
          vsync: tester,
          config: BoardDragConfig<String>(
            onItemMoved: (key, span) {},
            onItemResized: (key, span) {
              resizes.add(span);
            },
            resizeEdges: BoardResizeEdges.trailing,
            snap: snap,
          ),
        );
        addTearDown(drag.dispose);
        // Trailing edge from x 80 to x 50: the dragged edge lands at
        // track-space 1.25, a quarter past the item's own start.
        expect(
          drag.startDrag(
            key: "r",
            renderPort: viewport,
            pointerGlobal: const Offset(80.0, 25.0),
            edge: BoardResizeEdges.trailing,
          ),
          isTrue,
        );
        drag.updateDrag(const Offset(50.0, 25.0));
        await tester.pump();
        drag.endDrag(cancel: false);
        await tester.pump();
        expect(resizes, hasLength(1));
        return resizes.single;
      }

      expect(
        await resize(const BoardSnap.fraction(0.25)),
        const BoardSpan(
          rowStart: 0,
          colStart: 1,
          colSpan: 0,
          colSpanFraction: 0.25,
        ),
      );
      expect(
        await resize(const BoardSnap.track()),
        const BoardSpan(rowStart: 0, colStart: 1),
      );
    },
  );
}
