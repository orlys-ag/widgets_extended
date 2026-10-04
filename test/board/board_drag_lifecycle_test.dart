/// Tests for item 7M of the board audit fixes: the widget's scroll
/// pass-throughs, the drag's delay and strip knobs, and the drag's
/// lifecycle callbacks.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7M", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Every case tests members that did not exist on the tree item 7L left;
/// each assertion was shown red against a mutation of its own.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_handle.dart';
import 'package:widgets_extended/board/board_views.dart';
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
  int rows = 6,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(rows, 50.0)),
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

Widget _host(Widget board) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 280.0, height: 300.0, child: board),
      ),
    ),
  );
}

Widget _itemBox(BuildContext context, BoardItemView<String, _Item> item) {
  return ColoredBox(key: _itemKey(item.key), color: const Color(0xFF4CAF50));
}

void main() {
  // Test 1.
  testWidgets("scrollCacheExtent reaches the viewport", (tester) async {
    final controller = _controller(tester, rows: 40);
    final built = <int>{};
    await tester.pumpWidget(
      _host(
        Board<String, _Item>(
          controller: controller,
          scrollCacheExtent: const ScrollCacheExtent.pixels(0.0),
          cellBuilder: (context, cell) {
            built.add(cell.row);
            return const SizedBox.expand();
          },
        ),
      ),
    );
    // TARGET: with no cache region, only the six rows in view build.
    expect(built.reduce((a, b) => a > b ? a : b), lessThan(6));
  });

  // Test 2.
  testWidgets("dragStartBehavior, keyboardDismissBehavior and "
      "hitTestBehavior reach the scrollables", (tester) async {
    final controller = _controller(tester);
    await tester.pumpWidget(
      _host(
        Board<String, _Item>(
          controller: controller,
          dragStartBehavior: DragStartBehavior.down,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          hitTestBehavior: HitTestBehavior.translucent,
          cellBuilder: (context, cell) {
            return null;
          },
        ),
      ),
    );
    final scrollable = tester.widget<TwoDimensionalScrollable>(
      find.byType(TwoDimensionalScrollable),
    );
    // TARGET.
    expect(scrollable.dragStartBehavior, DragStartBehavior.down);
    expect(scrollable.hitTestBehavior, HitTestBehavior.translucent);
    expect(
      find.descendant(
        of: find.byType(Board<String, _Item>),
        matching: find.byWidgetPredicate((widget) {
          return widget is NotificationListener<ScrollUpdateNotification>;
        }),
      ),
      findsOneWidget,
    );
  });

  // Test 3.
  testWidgets("dragStartDelay shortens the long press", (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(
      _host(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return null;
          },
          itemBuilder: _itemBox,
          drag: BoardDragConfig<String>(
            dragStartDelay: const Duration(milliseconds: 100),
            onItemMoved: (key, span) {},
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m"))),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.moveBy(const Offset(40.0, 0.0));
    await tester.pump();
    // TARGET: lifted at 150 ms, well before the default long press.
    expect(controller.isDragging("m"), isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  // Test 4.
  testWidgets("BoardDelayedDragHandle takes its own delay", (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(
      _host(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return null;
          },
          itemBuilder: (context, item) {
            return BoardDelayedDragHandle(
              delay: const Duration(milliseconds: 100),
              child: ColoredBox(
                key: _itemKey(item.key),
                color: const Color(0xFF4CAF50),
              ),
            );
          },
          drag: BoardDragConfig<String>(
            buildDefaultDragHandles: false,
            onItemMoved: (key, span) {},
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m"))),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.moveBy(const Offset(40.0, 0.0));
    await tester.pump();
    // TARGET.
    expect(controller.isDragging("m"), isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  // Test 5. A two-row item, 100 px tall, whose strip a 20 px cap makes
  // 20 px deep: a press 16 px inside its bottom edge resizes it.
  testWidgets("resizeHandleExtent deepens the resize strip", (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 2),
    );
    final resizes = <BoardSpan>[];
    await tester.pumpWidget(
      _host(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return null;
          },
          itemBuilder: _itemBox,
          drag: BoardDragConfig<String>(
            resizeHandleExtent: 20.0,
            primaryResizeEdges: BoardResizeEdges.trailing,
            onItemMoved: (key, span) {},
            onItemResized: (key, span) {
              resizes.add(span);
            },
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byKey(_itemKey("m")));
    final gesture = await tester.startGesture(
      Offset(rect.center.dx, rect.bottom - 16.0),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0.0, 50.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // TARGET: the press was a resize, one row longer.
    expect(resizes, <BoardSpan>[
      const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 3),
    ]);
  });

  // Test 6.
  testWidgets("the drag reports its start, its targets and its end",
      (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    final events = <String>[];
    await tester.pumpWidget(
      _host(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return null;
          },
          itemBuilder: _itemBox,
          drag: BoardDragConfig<String>(
            onDragStart: (key, kind) {
              events.add("start $key ${kind.name}");
            },
            onDragTargetChanged: (key, target) {
              final span = target?.span;
              events.add(
                "target $key ${span?.rowStart},${span?.colStart}",
              );
            },
            onItemMoved: (key, span) {
              events.add("moved $key ${span.rowStart},${span.colStart}");
              controller.moveItem(key, span);
            },
            onDragEnd: (key, committed) {
              events.add("end $key $committed");
            },
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m"))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    // Setup sanity: lifted.
    expect(controller.isDragging("m"), isTrue);
    // Small moves inside the first cell change no target, nor does a
    // re-resolve an unrelated change forces, which lands on the same one
    // ...
    await gesture.moveBy(const Offset(3.0, 0.0));
    await tester.pump();
    await gesture.moveBy(const Offset(3.0, 0.0));
    await tester.pump();
    controller.addItem(
      const _Item("x"),
      const BoardSpan(rowStart: 5, colStart: 5),
    );
    await tester.pump();
    await tester.pump();
    // ... and one column over does.
    await gesture.moveBy(const Offset(40.0, 0.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // TARGET: the whole lifecycle, in order, once each.
    expect(events, <String>[
      "start m move",
      "target m 2,1",
      "target m 2,2",
      "moved m 2,2",
      "end m true",
    ]);
  });

  // Test 7.
  testWidgets("a cancelled drag ends uncommitted", (tester) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    final ends = <String>[];
    var moves = 0;
    await tester.pumpWidget(
      _host(
        Board<String, _Item>(
          controller: controller,
          cellBuilder: (context, cell) {
            return null;
          },
          itemBuilder: _itemBox,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {
              moves += 1;
            },
            onDragEnd: (key, committed) {
              ends.add("$key $committed");
            },
          ),
        ),
      ),
    );
    // Escape cancels a live drag.
    var gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m"))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    expect(controller.isDragging("m"), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // TARGET: one end, uncommitted, and no drop.
    expect(ends, <String>["m false"]);
    expect(moves, 0);

    // So does a mutation of the dragged key.
    gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m"))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    expect(controller.isDragging("m"), isTrue);
    controller.moveItem("m", const BoardSpan(rowStart: 4, colStart: 1));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // TARGET.
    expect(ends, <String>["m false", "m false"]);
    expect(moves, 0);
  });
}
