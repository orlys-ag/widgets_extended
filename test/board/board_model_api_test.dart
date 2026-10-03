/// Tests for item 7J of the board audit fixes: the model API's semantics,
/// a duplicate in `setItems`' argument, the lane reads for a key not on
/// the board, and listing and counting the items.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7J", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Cases 1 and 2 were red at their TARGETs on the tree item 7I left; case
/// 3 tests members that did not exist there, and every assertion in it
/// was shown red against a mutation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/_board_store.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0), laneExtent: 12.0),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  // Registered after the dispose, so it runs before it: the board
  // unsubscribes when it unmounts.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  return controller;
}

Widget _board(BoardController<String, _Item> controller) {
  return MaterialApp(
    home: Align(
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
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
}

void main() {
  // Test 1.
  testWidgets("a key repeated in setItems' argument is refused with its "
      "own message", (tester) async {
    final controller = _controller(tester);
    Object? error;
    try {
      controller.setItems(const <BoardPlacement<_Item>>[
        BoardPlacement<_Item>(_Item("p"), BoardSpan(rowStart: 0, colStart: 1)),
        BoardPlacement<_Item>(_Item("p"), BoardSpan(rowStart: 1, colStart: 1)),
      ]);
    } catch (e) {
      error = e;
    }
    // Setup sanity: refused, as before, and the board untouched.
    expect(error, isA<StateError>());
    expect(controller.contains("p"), isFalse);
    final message = (error! as StateError).message;
    // TARGET: the message is about the argument ...
    expect(message, contains("more than once"));
    // ... and gives no live-set advice.
    expect(message, isNot(contains("updateItem")));
  });

  // Test 2.
  testWidgets("the lane reads answer null for a key not on the board",
      (tester) async {
    final controller = _controller(
      tester,
      style: const BoardAnimationStyle(),
    );
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 1, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    // Setup sanity: a live laned item's values.
    expect(controller.laneOf("a"), 0);
    expect(controller.laneCountOf("a"), 1);
    expect(controller.laneSpanOf("a"), 1);

    // TARGET: a key never added ...
    expect(controller.laneOf("nobody"), isNull);
    expect(controller.laneCountOf("nobody"), isNull);
    expect(controller.laneSpanOf("nobody"), isNull);

    controller.removeItem("a");
    await tester.pump();
    // Setup sanity: a is exiting, so no longer in the live set.
    expect(controller.contains("a"), isFalse);
    // TARGET: ... and a key whose only incarnation is exiting.
    expect(controller.laneOf("a"), isNull);
    expect(controller.laneCountOf("a"), isNull);
    expect(controller.laneSpanOf("a"), isNull);
    await tester.pumpAndSettle();
  });

  // Test 3.
  testWidgets("itemCount and keys follow the live set", (tester) async {
    final controller = _controller(
      tester,
      style: const BoardAnimationStyle(),
    );
    await tester.pumpWidget(_board(controller));
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 0, colStart: 0),
    );
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 1, colStart: 0),
    );
    controller.addItem(
      const _Item("c"),
      const BoardSpan(rowStart: 2, colStart: 0),
    );
    await tester.pumpAndSettle();
    // Setup sanity: three items.
    expect(controller.itemCount, 3);
    expect(controller.keys.toSet(), <String>{"a", "b", "c"});

    // TARGET: an animated exit leaves the live set at once.
    controller.removeItem("b");
    await tester.pump();
    expect(controller.itemCount, 2);
    expect(controller.keys.toSet(), <String>{"a", "c"});

    // TARGET: a resurrection brings it back.
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 1, colStart: 0),
    );
    expect(controller.itemCount, 3);
    expect(controller.keys.toSet(), <String>{"a", "b", "c"});
    await tester.pumpAndSettle();

    // TARGET: a synchronous removal releases its key at once.
    controller.animationStyle = BoardAnimationStyle.disabled;
    controller.removeItem("c");
    expect(controller.itemCount, 2);

    // TARGET: an exit that settles is counted once, not twice.
    controller.animationStyle = const BoardAnimationStyle();
    controller.removeItem("a");
    await tester.pumpAndSettle();
    expect(controller.itemCount, 1);

    // TARGET: setItems' own exits and enters.
    controller.setItems(const <BoardPlacement<_Item>>[
      BoardPlacement<_Item>(_Item("d"), BoardSpan(rowStart: 3, colStart: 0)),
    ]);
    expect(controller.itemCount, 1);
    expect(controller.keys, <String>["d"]);
    await tester.pumpAndSettle();
  });

  // Test 4. The store's count for a caller that releases an id without
  // clearing its exiting bit first, which the controller never does and
  // the span index's fuzz does.
  test("the live count survives a release of an exiting id", () {
    final store = BoardStore<String, String>();
    store.allocate("a");
    final b = store.allocate("b");
    store.setFlag(b, BoardStore.exitingBit, true);
    // Setup sanity: b is exiting, so one live key.
    expect(store.liveCount, 1);
    store.release("b");
    // TARGET.
    expect(store.liveCount, 1);
    store.allocate("c");
    expect(store.liveCount, 2);
  });
}
