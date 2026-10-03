/// Item 1 of `plans/2026-09-23-board-audit-fixes-plan.md`, the controller
/// half: `BoardDragController.config` is assigned in place, and a live
/// session carries on under the new config's policies.
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

const Key _frameKey = ValueKey<String>("board-frame");

BoardController<String, _Item> _controller(WidgetTester tester, int rows) {
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
  return controller;
}

Widget _board(BoardController<String, _Item> controller) {
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
            cellBuilder: (context, cell) {
              return null;
            },
            itemBuilder: (context, item) {
              return const ColoredBox(color: Color(0xFF4CAF50));
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

void main() {
  testWidgets(
    "a new canDropAt that refuses the current target clears it within a "
    "frame while the session stays live",
    (tester) async {
      final controller = _controller(tester, 6);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      final viewport = _viewport(tester);
      void onItemMoved(String key, BoardSpan span) {}
      final drag = BoardDragController<String>(
        boardController: controller,
        vsync: tester,
        config: BoardDragConfig<String>(
          onItemMoved: onItemMoved,
          autoScrollEdgeZone: 0.0,
        ),
      );
      addTearDown(drag.dispose);
      final rect = viewport.rectOfItem("m")!;
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, rect.center),
        ),
        isTrue,
      );
      drag.updateDrag(_global(tester, rect.center + const Offset(80.0, 0.0)));
      // Setup sanity: an admitted target three columns over.
      expect(drag.currentTarget!.span.colStart, 3);

      drag.config = BoardDragConfig<String>(
        onItemMoved: onItemMoved,
        autoScrollEdgeZone: 0.0,
        canDropAt: (key, span) {
          return false;
        },
      );
      await tester.pump();
      // TARGET: the session survived and the refused target is gone.
      expect(drag.draggedKey, "m");
      expect(drag.currentTarget, isNull);
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle();
    },
  );

  testWidgets("a new autoscroll edge zone takes effect mid-session", (
    tester,
  ) async {
    final controller = _controller(tester, 30);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 1, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    final viewport = _viewport(tester);
    void onItemMoved(String key, BoardSpan span) {}
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(
        onItemMoved: onItemMoved,
        autoScrollEdgeZone: 0.0,
      ),
    );
    addTearDown(drag.dispose);
    final position = viewport.verticalPosition!;
    final rect = viewport.rectOfItem("m")!;
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, rect.center),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(60.0, 295.0)));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Setup sanity: with no edge zone, nothing scrolls.
    expect(position.pixels, 0.0);

    drag.config = BoardDragConfig<String>(
      onItemMoved: onItemMoved,
      autoScrollEdgeZone: 48.0,
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // TARGET: the new zone scrolls the finger's edge into view.
    expect(position.pixels, greaterThan(0.0));
    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
  });

  testWidgets("assigning the identical config is a no-op for a live session", (
    tester,
  ) async {
    final controller = _controller(tester, 6);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    final viewport = _viewport(tester);
    var notifications = 0;
    final config = BoardDragConfig<String>(
      onItemMoved: (key, span) {},
      autoScrollEdgeZone: 0.0,
    );
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: config,
    )..addListener(() {
        notifications += 1;
      });
    addTearDown(drag.dispose);
    final rect = viewport.rectOfItem("m")!;
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, rect.center),
      ),
      isTrue,
    );
    await tester.pump();
    final before = notifications;
    drag.config = config;
    await tester.pump();
    // TARGET: no re-resolve, so no notification.
    expect(notifications, before);
    expect(drag.draggedKey, "m");
    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
  });
}
