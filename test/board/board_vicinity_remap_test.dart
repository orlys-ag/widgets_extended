/// Tests for item 7E of the board audit fixes: a removal that shifts the
/// ordinals on a row builds the item that shifts, not the element the
/// removed item left at that vicinity.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7E", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Every TARGET was red on the tree item 7D left, with every setup sanity
/// assertion before it passing.
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

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Unmounts the board before the controller's own tear-down disposes it.
void _unmountFirst(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// Item builds, per key, across the board's life.
final Map<String, int> _builds = <String, int>{};

Widget _board(
  BoardController<String, _Item> controller, {
  BoardDragConfig<String>? drag,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280.0,
          height: 300.0,
          child: Board<String, _Item>(
            controller: controller,
            drag: drag,
            cellBuilder: (context, cell) {
              return null;
            },
            itemBuilder: (context, item) {
              _builds[item.key] = (_builds[item.key] ?? 0) + 1;
              return ColoredBox(
                key: _itemKey(item.key),
                color: const Color(0xFF4CAF50),
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// Two items on row 2, `a` sorting first.
void _addPair(BoardController<String, _Item> controller) {
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 2, colStart: 1),
  );
  controller.addItem(
    const _Item("b"),
    const BoardSpan(rowStart: 2, colStart: 3),
  );
}

const Rect _bRect = Rect.fromLTWH(120.0, 100.0, 40.0, 50.0);

void main() {
  setUp(_builds.clear);

  // Test 1.
  testWidgets("a synchronous removal builds the item that shifts into its "
      "place", (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    _addPair(controller);
    await tester.pumpWidget(_board(controller));
    final idB = controller.idOfKey("b");
    // Setup sanity: a sorts before b.
    expect(controller.vicinityOrdinalOfId(idB), 1);

    controller.removeItem("a");
    await tester.pump();
    // Setup sanity: b took the ordinal a held.
    expect(controller.vicinityOrdinalOfId(idB), 0);
    // TARGET: a's content is gone and b's stands where b is.
    expect(find.byKey(_itemKey("a")), findsNothing);
    expect(tester.getRect(find.byKey(_itemKey("b"))), _bRect);
  });

  // Test 2.
  testWidgets("an exit's settle builds the item that shifts into its place",
      (tester) async {
    final controller = _controller(tester, style: const BoardAnimationStyle());
    _unmountFirst(tester);
    _addPair(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final idB = controller.idOfKey("b");

    controller.removeItem("a");
    await tester.pump();
    // Setup sanity: the exit runs, so the ordinals have not moved yet.
    expect(controller.vicinityOrdinalOfId(idB), 1);
    expect(find.byKey(_itemKey("a")), findsOneWidget);
    await tester.pumpAndSettle();
    expect(controller.vicinityOrdinalOfId(idB), 0);
    // TARGET.
    expect(find.byKey(_itemKey("a")), findsNothing);
    expect(tester.getRect(find.byKey(_itemKey("b"))), _bRect);
  });

  // Test 3.
  testWidgets("setItems dropping an earlier item builds the one that shifts",
      (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    _addPair(controller);
    await tester.pumpWidget(_board(controller));
    final idB = controller.idOfKey("b");

    controller.setItems(const <BoardPlacement<_Item>>[
      BoardPlacement<_Item>(_Item("b"), BoardSpan(rowStart: 2, colStart: 3)),
    ]);
    await tester.pump();
    expect(controller.vicinityOrdinalOfId(idB), 0);
    // TARGET.
    expect(find.byKey(_itemKey("a")), findsNothing);
    expect(tester.getRect(find.byKey(_itemKey("b"))), _bRect);
  });

  // Test 4 (A9).
  testWidgets("removing an earlier item on the dragged item's row keeps the "
      "drag", (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    _addPair(controller);
    final moves = <String>[];
    await tester.pumpWidget(
      _board(
        controller,
        drag: BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moves.add(key);
            controller.moveItem(key, span);
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("b"))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0.0, 50.0));
    await tester.pump();
    // Setup sanity: b is being dragged.
    expect(controller.isDragging("b"), isTrue);

    controller.removeItem("a");
    await tester.pump();
    await tester.pump();
    // TARGET: the drag of b is still live ...
    expect(controller.isDragging("b"), isTrue);
    await gesture.moveBy(const Offset(0.0, 50.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // ... and its release commits.
    expect(moves, <String>["b"]);
  });

  // Test 5. The cheap route stays cheap: an empty key set whose removal
  // leaves every built vicinity with the item it was built for, or with
  // none, re-runs no builder.
  testWidgets("a removal that remaps no built vicinity rebuilds no builder",
      (tester) async {
    final controller = _controller(tester, style: const BoardAnimationStyle());
    _unmountFirst(tester);
    _addPair(controller);
    controller.addItem(
      const _Item("c"),
      const BoardSpan(rowStart: 4, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    // Setup sanity: every item built.
    expect(_builds, <String, int>{"a": 1, "b": 1, "c": 1});

    // An exit START deregisters nothing.
    controller.removeItem("c");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: c is mid-exit.
    expect(find.byKey(_itemKey("c")), findsOneWidget);
    // TARGET: no item was built again.
    expect(_builds, <String, int>{"a": 1, "b": 1, "c": 1});

    // c's settle deregisters it, but it was alone on row 4: its vicinity
    // resolves to nothing, and nothing is reused there.
    await tester.pumpAndSettle();
    expect(find.byKey(_itemKey("c")), findsNothing);
    // TARGET.
    expect(_builds, <String, int>{"a": 1, "b": 1, "c": 1});
  });
}
