/// Promoted repros from the 2026-09-06 board review, widget-layer
/// sections (`plans/2026-09-06-board-review-fixes-plan.md`, F3 and F8).
///
/// F3 needs TOP-LEVEL builder functions: every other board widget test
/// passes inline closures, whose identity changes per pump and forces a
/// delegate rebuild, which is exactly what masks the defect.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

const Key _frameKey = ValueKey<String>("board-frame");

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

/// Identity-stable builders: a top-level function is the same object on
/// every pump, so `didUpdateWidget`'s builder-identity check stays false.
Widget _cellBuilder(BuildContext context, BoardCellView<String, _Item> cell) {
  return const SizedBox(width: 40.0, height: 50.0);
}

Widget _itemBuilder(BuildContext context, BoardItemView<String, _Item> item) {
  return ColoredBox(key: _itemKey(item.item.key), color: const Color(0xFF4CAF50));
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

Widget _board(
  BoardController<String, _Item> controller, {
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
            drag: drag,
            cellBuilder: _cellBuilder,
            itemBuilder: _itemBuilder,
          ),
        ),
      ),
    ),
  );
}

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

/// The LATTICE occurrence of [key]'s item: during a move the proxy builds
/// the same `itemBuilder` output under the same value key, and only the
/// lattice one sits under a [BoardItemDragScope].
Finder _inPlace(String key) {
  return find.descendant(
    of: find.byType(BoardItemDragScope),
    matching: find.byKey(_itemKey(key)),
  );
}

void main() {
  // F3. Replacing `Board.drag` rebuilds the drag controller but, with
  // identity-stable builders, nothing rebuilt the mounted item hosts,
  // which kept the DISPOSED controller captured in their widgets.
  testWidgets("F3 a new drag config rehosts every mounted item", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    final oldMoves = <BoardSpan>[];
    final newMoves = <BoardSpan>[];
    await tester.pumpWidget(
      _board(
        controller,
        drag: BoardDragConfig<String>(
          onItemMoved: (key, span) {
            oldMoves.add(span);
          },
        ),
      ),
    );
    // Setup sanity: the host is mounted under the first config, so the
    // second pump is a config SWAP on a live host rather than a first
    // build.
    expect(_inPlace("m"), findsOneWidget);

    await tester.pumpWidget(
      _board(
        controller,
        drag: BoardDragConfig<String>(
          onItemMoved: (key, span) {
            newMoves.add(span);
          },
        ),
      ),
    );

    // The item covers x 40..80, y 100..150.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m"))),
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveTo(_global(tester, const Offset(180.0, 225.0)));
    await tester.pump();
    // TARGET: the lift ran against a live controller.
    expect(tester.takeException(), isNull);
    // Setup sanity: the session started, so the release below has a
    // session to commit.
    expect(controller.isDragging("m"), isTrue);

    await gesture.up();
    await tester.pumpAndSettle();
    // TARGET: the session ended, and the NEW config got the report.
    expect(tester.takeException(), isNull);
    expect(controller.isDragging("m"), isFalse);
    expect(oldMoves, isEmpty);
    expect(newMoves, hasLength(1));
  });

  // F8. A host whose session was cancelled by a span mutator keeps
  // `_ownsSession`; its pointer's later moves and lift must not reach a
  // session another host started.
}
