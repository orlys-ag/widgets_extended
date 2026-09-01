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
import 'package:flutter/semantics.dart';
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

void main() {
  // AC10 semantics-only move.
  // Asserts: the built-in move action performed through the semantics
  // tree alone, with no pointer events, commits the same span the
  // scripted drag reports: three "Move right" activations take (2,1) to
  // (2,4).
  // Falsification: the no-pointer-events construction is the check.
  testWidgets(
    "a move through the semantics action alone commits the same span",
    (tester) async {
      final handle = tester.ensureSemantics();
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
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      final moves = <BoardSpan>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280.0,
              height: 300.0,
              child: Board<String, _Item>(
                controller: controller,
                drag: BoardDragConfig<String>(
                  onItemMoved: (key, span) {
                    moves.add(span);
                    controller.moveItem(key, span);
                  },
                ),
                cellBuilder: (context, cell) {
                  return const SizedBox(width: 40.0, height: 50.0);
                },
                itemBuilder: (context, item) {
                  return const ColoredBox(
                    key: ValueKey<String>("im"),
                    color: Color(0xFF4CAF50),
                  );
                },
              ),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(
        find.byKey(const ValueKey<String>("im")),
      );
      const action = CustomSemanticsAction(label: "Move right");
      final id = CustomSemanticsAction.getIdentifier(action);
      // Setup sanity: the built-in action is on the item's node.
      expect(
        node.getSemanticsData().customSemanticsActionIds,
        contains(id),
      );
      for (var i = 0; i < 3; i++) {
        tester.binding.performSemanticsAction(
          SemanticsActionEvent(
            type: SemanticsAction.customAction,
            nodeId: node.id,
            viewId: tester.view.viewId,
            arguments: id,
          ),
        );
        await tester.pump();
      }
      expect(moves, hasLength(3));
      expect(
        controller.spanOf("m"),
        const BoardSpan(rowStart: 2, colStart: 4),
      );
      // Before the harness's end-of-body verification, which runs ahead
      // of tearDowns.
      handle.dispose();
    },
  );
}
