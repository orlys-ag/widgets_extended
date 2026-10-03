/// Item 2 of `plans/2026-09-23-board-audit-fixes-plan.md`: the drag layer
/// on an axis whose direction is `up` or `left`, where an item's
/// content-LEADING corner paints at its far edge.
///
/// Scripted cases drive a standalone [BoardDragController] against the
/// pumped board's render port; handle and semantics cases drive the
/// board's own through real gestures and actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

const Key _frameKey = ValueKey<String>("board-frame");

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

const BoardAnimationSpec _ms200 = BoardAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// Slides, the gap and the glides live; tracks and enter/exit off.
const BoardAnimationStyle _motion = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _ms200,
  itemEnterExit: _zero,
  makeRoom: _ms200,
);

const ScrollableDetails _up = ScrollableDetails(direction: AxisDirection.up);
const ScrollableDetails _left = ScrollableDetails(
  direction: AxisDirection.left,
);

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  int rows = 6,
  double? columnLaneExtent,
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(rows, 50.0)),
    columns: BoardAxisConfig(
      axis: UniformAxis(7, 40.0),
      laneExtent: columnLaneExtent,
    ),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _board(
  BoardController<String, _Item> controller, {
  ScrollableDetails vertical = const ScrollableDetails.vertical(),
  ScrollableDetails horizontal = const ScrollableDetails.horizontal(),
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
            verticalDetails: vertical,
            horizontalDetails: horizontal,
            drag: drag,
            cellBuilder: (context, cell) {
              return null;
            },
            itemBuilder: (context, item) {
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

RenderBoardViewport<String> _viewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

Rect _painted(WidgetTester tester, String key) {
  return tester
      .getRect(find.byKey(_itemKey(key)))
      .shift(-tester.getRect(find.byKey(_frameKey)).topLeft);
}

BoardDragController<String> _drag(
  WidgetTester tester,
  BoardController<String, _Item> controller,
  BoardDragConfig<String> config,
) {
  final drag = BoardDragController<String>(
    boardController: controller,
    vsync: tester,
    config: config,
  );
  addTearDown(drag.dispose);
  return drag;
}

/// Lifts [key] at its painted centre, moves the pointer by [by] and
/// commits, returning every span the config was handed.
Future<List<BoardSpan>> _scriptedMove(
  WidgetTester tester,
  BoardController<String, _Item> controller, {
  required String key,
  Offset by = Offset.zero,
  BoardSnap snap = const BoardSnap.track(),
}) async {
  final viewport = _viewport(tester);
  final moves = <BoardSpan>[];
  final drag = _drag(
    tester,
    controller,
    BoardDragConfig<String>(
      snap: snap,
      autoScrollEdgeZone: 0.0,
      onItemMoved: (key, span) {
        moves.add(span);
      },
    ),
  );
  final centre = viewport.rectOfItem(key)!.center;
  expect(
    drag.startDrag(
      key: key,
      renderPort: viewport,
      pointerGlobal: _global(tester, centre),
    ),
    isTrue,
  );
  if (by != Offset.zero) {
    drag.updateDrag(_global(tester, centre + by));
  }
  drag.endDrag(cancel: false);
  await tester.pump();
  return moves;
}

Future<void> _performAction(
  WidgetTester tester,
  String key,
  String label,
) async {
  final node = tester.getSemantics(find.byKey(_itemKey(key)));
  final id = CustomSemanticsAction.getIdentifier(
    CustomSemanticsAction(label: label),
  );
  // Setup sanity: the action is advertised.
  expect(node.getSemanticsData().customSemanticsActionIds, contains(id));
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

void main() {
  testWidgets("a zero-motion move keeps the row under AxisDirection.up", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 1, colStart: 1),
    );
    await tester.pumpWidget(_board(controller, vertical: _up));
    // Setup sanity: row 1 paints second from the bottom.
    expect(_viewport(tester).rectOfItem("m"), const Rect.fromLTWH(40.0, 200.0, 40.0, 50.0));
    final moves = await _scriptedMove(tester, controller, key: "m");
    // TARGET.
    expect(moves.single, const BoardSpan(rowStart: 1, colStart: 1));
  });

  testWidgets("a zero-motion move keeps the column under AxisDirection.left", (
    tester,
  ) async {
    final controller = _controller(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 1, colStart: 1),
    );
    await tester.pumpWidget(_board(controller, horizontal: _left));
    expect(_viewport(tester).rectOfItem("m"), const Rect.fromLTWH(200.0, 50.0, 40.0, 50.0));
    final moves = await _scriptedMove(tester, controller, key: "m");
    // TARGET.
    expect(moves.single, const BoardSpan(rowStart: 1, colStart: 1));
  });

  testWidgets(
    "a move one row down the screen under AxisDirection.up lands one "
    "content row lower",
    (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(_board(controller, vertical: _up));
      final moves = await _scriptedMove(
        tester,
        controller,
        key: "m",
        by: const Offset(0.0, 50.0),
      );
      // TARGET: down the screen is toward row 0 on this axis.
      expect(moves.single, const BoardSpan(rowStart: 1, colStart: 1));
    },
  );

  testWidgets(
    "a zero-motion move under a fraction snap keeps the start under "
    "AxisDirection.up",
    (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 2),
      );
      await tester.pumpWidget(_board(controller, vertical: _up));
      final moves = await _scriptedMove(
        tester,
        controller,
        key: "m",
        snap: const BoardSnap.fraction(0.25),
      );
      // TARGET.
      expect(
        moves.single,
        const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 2),
      );
    },
  );

  testWidgets(
    "the trailing band paints on the item's top edge under "
    "AxisDirection.up",
    (tester) async {
      final controller = _controller(tester);
      const original = BoardSpan(rowStart: 1, colStart: 1, rowSpan: 2);
      controller.addItem(const _Item("m"), original);
      final resizes = <BoardSpan>[];
      await tester.pumpWidget(
        _board(
          controller,
          vertical: _up,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {},
            onItemResized: (key, span) {
              resizes.add(span);
              controller.resizeItem(key, span);
            },
            primaryResizeEdges: BoardResizeEdges.trailing,
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(_itemKey("m")));
      // Setup sanity: rows [1, 3) paint at y 150 to 250, row 3's edge
      // on top.
      expect(_painted(tester, "m"), const Rect.fromLTWH(40.0, 150.0, 40.0, 100.0));

      var gesture = await tester.startGesture(
        Offset(rect.center.dx, rect.top + 4.0),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0.0, -1.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      // Setup sanity: the top band started a resize.
      expect(resizes, isNotEmpty);
      // TARGET: a one-pixel nudge of the trailing edge changes nothing.
      expect(resizes.last, original);

      gesture = await tester.startGesture(
        Offset(rect.center.dx, rect.top + 4.0),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0.0, -50.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      // TARGET: dragging the top edge up grows the item one row there.
      expect(
        resizes.last,
        const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 3),
      );
      expect(_painted(tester, "m"), const Rect.fromLTWH(40.0, 100.0, 40.0, 150.0));
    },
  );

  testWidgets(
    "holding a drag at the top edge of an AxisDirection.up board reveals "
    "the content above",
    (tester) async {
      final controller = _controller(tester, rows: 30);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 1, colStart: 1),
      );
      await tester.pumpWidget(_board(controller, vertical: _up));
      final viewport = _viewport(tester);
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(onItemMoved: (key, span) {}),
      );
      final position = viewport.verticalPosition!;
      // Setup sanity: at the leading (bottom) end, content above.
      expect(position.pixels, 0.0);
      expect(position.maxScrollExtent, greaterThan(0.0));
      final rect = viewport.rectOfItem("m")!;
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, rect.center),
        ),
        isTrue,
      );
      drag.updateDrag(_global(tester, const Offset(60.0, 5.0)));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // TARGET.
      expect(position.pixels, greaterThan(0.0));
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    "the Move up and Move left actions move the item that way on screen "
    "on reversed axes",
    (tester) async {
      final handle = tester.ensureSemantics();
      final controller = _controller(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 2),
      );
      await tester.pumpWidget(
        _board(
          controller,
          vertical: _up,
          horizontal: _left,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {
              controller.moveItem(key, span);
            },
          ),
        ),
      );
      final before = _painted(tester, "m");
      await _performAction(tester, "m", "Move up");
      final afterUp = _painted(tester, "m");
      // TARGET: up the screen by one row.
      expect(afterUp.top, before.top - 50.0);
      expect(afterUp.left, before.left);
      await _performAction(tester, "m", "Move left");
      final afterLeft = _painted(tester, "m");
      // TARGET: left on the screen by one column.
      expect(afterLeft.left, afterUp.left - 40.0);
      expect(afterLeft.top, afterUp.top);
      handle.dispose();
    },
  );

  testWidgets(
    "a committed trailing resize under AxisDirection.left does not step "
    "at release",
    (tester) async {
      final controller = _controller(tester, style: _motion);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
      );
      await tester.pumpWidget(_board(controller, horizontal: _left));
      await tester.pumpAndSettle();
      final viewport = _viewport(tester);
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          autoScrollEdgeZone: 0.0,
          onItemMoved: (key, span) {},
          onItemResized: (key, span) {
            controller.resizeItem(key, span);
          },
          resizeEdges: BoardResizeEdges.trailing,
        ),
      );
      final rect = viewport.rectOfItem("m")!;
      // Setup sanity: content 40..120 paints at 160..240, the trailing
      // edge on the left.
      expect(rect.left, 160.0);
      expect(rect.right, 240.0);
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, Offset(rect.left, rect.center.dy)),
          edge: BoardResizeEdges.trailing,
        ),
        isTrue,
      );
      drag.updateDrag(_global(tester, Offset(40.0, rect.center.dy)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 16));
      // Setup sanity: a settled preview of five columns.
      expect(drag.currentTarget!.span.colSpan, 5);
      final held = _painted(tester, "m");
      expect(held.left, closeTo(40.0, 0.01));
      expect(held.right, closeTo(240.0, 0.01));

      drag.endDrag(cancel: false);
      await tester.pump();
      expect(controller.spanOf("m")!.colSpan, 5);
      final dropped = _painted(tester, "m");
      // TARGET: the drop frame paints what the preview showed.
      expect(dropped.left, closeTo(held.left, 0.5));
      expect(dropped.right, closeTo(held.right, 0.5));
      await tester.pumpAndSettle();
      expect(_painted(tester, "m").left, closeTo(40.0, 0.01));
    },
  );

  testWidgets(
    "a commit mid-gap under AxisDirection.left hands a shrinking neighbour "
    "off without a step",
    (tester) async {
      final controller = _controller(
        tester,
        columnLaneExtent: 18.0,
        style: _motion,
      );
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 3),
      );
      controller.addItem(
        const _Item("d"),
        const BoardSpan(rowStart: 0, colStart: 5, rowSpan: 3),
      );
      await tester.pumpWidget(_board(controller, horizontal: _left));
      await tester.pumpAndSettle();
      final viewport = _viewport(tester);
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          autoScrollEdgeZone: 0.0,
          onItemMoved: (key, span) {
            controller.moveItem(key, span);
          },
        ),
      );
      // Setup sanity: a alone in column 2, which paints at 160..200.
      expect(_painted(tester, "a").left, closeTo(160.0, 0.01));
      expect(_painted(tester, "a").width, closeTo(40.0, 0.01));
      final lift = viewport.rectOfItem("d")!.center;
      expect(
        drag.startDrag(
          key: "d",
          renderPort: viewport,
          pointerGlobal: _global(tester, lift),
        ),
        isTrue,
      );
      drag.updateDrag(
        _global(tester, Offset(viewport.rectOfCell(0, 2)!.center.dx, lift.dy)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Setup sanity: the target is column 2 and a is mid-shrink.
      expect(drag.currentTarget!.span.colStart, 2);
      final held = _painted(tester, "a");
      expect(held.width, greaterThan(21.0));
      expect(held.width, lessThan(39.0));

      drag.endDrag(cancel: false);
      await tester.pump();
      // Setup sanity: d landed beside a.
      expect(controller.spanOf("d")!.colStart, 2);
      final handed = _painted(tester, "a");
      // TARGET: the commit frame paints a where the gap held it.
      expect(handed.left, closeTo(held.left, 0.5));
      expect(handed.width, closeTo(held.width, 0.5));
      await tester.pumpAndSettle();
      expect(_painted(tester, "a").width, closeTo(20.0, 0.01));
    },
  );
}
