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

  // The cases below are from
  // plans/2026-09-04-board-drag-policy-and-proxy-plan.md, T1 to T6 and
  // T9. Each states how it fails on unfixed code.

  testWidgets(
    "the built-in move actions are absent and inert when the drag config "
    "is disabled",
    (tester) async {
      final handle = tester.ensureSemantics();
      final moves = <BoardSpan>[];
      await _pumpItem(
        tester,
        BoardDragConfig<String>(
          enabled: false,
          onItemMoved: (key, span) {
            moves.add(span);
          },
        ),
      );
      final node = _itemNode(tester);
      // Unfixed: the id is advertised.
      expect(_actionIds(node), isNot(contains(_id("Move right"))));
      _perform(tester, node, "Move right");
      await tester.pump();
      // Unfixed: one move reported.
      expect(moves, isEmpty);
      handle.dispose();
    },
  );

  testWidgets(
    "the built-in move actions are absent and inert when canDrag refuses "
    "the item",
    (tester) async {
      final handle = tester.ensureSemantics();
      final moves = <BoardSpan>[];
      await _pumpItem(
        tester,
        BoardDragConfig<String>(
          canDrag: (key) {
            return false;
          },
          onItemMoved: (key, span) {
            moves.add(span);
          },
        ),
      );
      final node = _itemNode(tester);
      expect(_actionIds(node), isNot(contains(_id("Move right"))));
      _perform(tester, node, "Move right");
      await tester.pump();
      expect(moves, isEmpty);
      handle.dispose();
    },
  );

  testWidgets(
    "a move action whose destination canDropAt refuses is not advertised",
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpItem(
        tester,
        BoardDragConfig<String>(
          canDropAt: (key, span) {
            return span.colStart < 4;
          },
          onItemMoved: (key, span) {},
        ),
      );
      final node = _itemNode(tester);
      // Setup sanity: the admitted direction IS advertised, so the case
      // cannot pass by advertising nothing.
      expect(_actionIds(node), contains(_id("Move left")));
      // Unfixed: advertised.
      expect(_actionIds(node), isNot(contains(_id("Move right"))));
      handle.dispose();
    },
  );

  testWidgets(
    "an advertised move action re-checks canDropAt at activation",
    (tester) async {
      final handle = tester.ensureSemantics();
      var allow = true;
      final moves = <BoardSpan>[];
      await _pumpItem(
        tester,
        BoardDragConfig<String>(
          canDropAt: (key, span) {
            return allow;
          },
          onItemMoved: (key, span) {
            moves.add(span);
          },
        ),
      );
      final node = _itemNode(tester);
      // Setup sanity: advertised while allowed.
      expect(_actionIds(node), contains(_id("Move left")));
      // The policy changes its answer with NO rebuild.
      allow = false;
      _perform(tester, node, "Move left");
      await tester.pump();
      // Unfixed: one move reported.
      expect(moves, isEmpty);
      handle.dispose();
    },
  );

  testWidgets(
    "semanticsActionsBuilder is not consulted for a refused item",
    (tester) async {
      final handle = tester.ensureSemantics();
      var calls = 0;
      await _pumpItem(
        tester,
        BoardDragConfig<String>(
          canDrag: (key) {
            return false;
          },
          semanticsActionsBuilder: (key, builtIn) {
            calls += 1;
            return builtIn;
          },
          onItemMoved: (key, span) {},
        ),
      );
      _itemNode(tester);
      // Unfixed: one call.
      expect(calls, 0);
      handle.dispose();
    },
  );

  testWidgets(
    "an item with no admissible destination advertises no custom action",
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpItem(
        tester,
        BoardDragConfig<String>(onItemMoved: (key, span) {}),
        rows: 1,
        cols: 1,
        span: const BoardSpan(rowStart: 0, colStart: 0),
      );
      final node = _itemNode(tester);
      // Unfixed: four no-op actions raise the bit.
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.customAction),
        isFalse,
      );
      handle.dispose();
    },
  );

  // T9. The lattice-bounds test must read the EXACT trailing endpoint:
  // an item at row 4 spanning 1.5 rows on a 6-row axis ends at 5.5, and
  // "Move down" would end it at 6.5, past the lattice. The integer test
  // (5 + 1 > 6) admits it.
  testWidgets(
    "a move that carries a fractional span past the lattice is not "
    "advertised",
    (tester) async {
      final handle = tester.ensureSemantics();
      final moves = <BoardSpan>[];
      await _pumpItem(
        tester,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moves.add(span);
          },
        ),
        span: const BoardSpan(rowStart: 4, colStart: 3, rowSpanFraction: 0.5),
      );
      final node = _itemNode(tester);
      // Setup sanity: the in-lattice direction is advertised.
      expect(_actionIds(node), contains(_id("Move up")));
      // Unfixed: advertised, and reports a span ending at 6.5.
      expect(_actionIds(node), isNot(contains(_id("Move down"))));
      _perform(tester, node, "Move down");
      await tester.pump();
      expect(moves, isEmpty);
      handle.dispose();
    },
  );
}

/// Pumps a board with one item "m" under [drag]; the caller's config
/// decides what a report does.
Future<void> _pumpItem(
  WidgetTester tester,
  BoardDragConfig<String> drag, {
  int rows = 6,
  int cols = 7,
  BoardSpan span = const BoardSpan(rowStart: 2, colStart: 3),
}) async {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(rows, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(cols, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  controller.addItem(const _Item("m"), span);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 280.0,
          height: 300.0,
          child: Board<String, _Item>(
            controller: controller,
            drag: drag,
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
}

SemanticsNode _itemNode(WidgetTester tester) {
  return tester.getSemantics(find.byKey(const ValueKey<String>("im")));
}

int _id(String label) {
  return CustomSemanticsAction.getIdentifier(
    CustomSemanticsAction(label: label),
  );
}

List<int> _actionIds(SemanticsNode node) {
  return node.getSemanticsData().customSemanticsActionIds ?? const <int>[];
}

void _perform(WidgetTester tester, SemanticsNode node, String label) {
  tester.binding.performSemanticsAction(
    SemanticsActionEvent(
      type: SemanticsAction.customAction,
      nodeId: node.id,
      viewId: tester.view.viewId,
      arguments: _id(label),
    ),
  );
}
