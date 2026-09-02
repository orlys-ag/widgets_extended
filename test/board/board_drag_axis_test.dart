/// Tests for the resize AXIS on the drag layer: a handle, and
/// `startDrag`, can name the axis a resize edge is on, so a board whose
/// rows are primary (a time grid) can drag an item's bottom edge, and the
/// config's `primaryResizeEdges` policy gates that axis as `resizeEdges`
/// gates the span axis.
///
/// Every case failed at the assertion marked TARGET before the axis
/// landed (the parameters did not exist), and again against the scratch
/// variant its comment names, with every setup sanity assertion before
/// it passing.
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

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

/// Six 50px rows by seven 40px columns, both uniform, so the ROW axis is
/// primary and the column axis is the span axis.
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
  // Rows 2 and 3, column 1: y 100 to 200, x 40 to 80.
  controller.addItem(
    const _Item("m"),
    const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 2),
  );
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
            cellBuilder: (context, cell) {
              return const SizedBox(width: 40.0, height: 50.0);
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

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

void main() {
  // A1. Scripted: the trailing edge on the VERTICAL axis of a row-primary
  // board drags the item's bottom, two tracks outward. Went red against
  // the scratch variant that ignored the axis (the span-axis policy is
  // `none` here, so the session refused to start).
  testWidgets("startDrag with a vertical axis on a row-primary board "
      "resizes the row span", (tester) async {
    final controller = _controller(tester);
    await tester.pumpWidget(_board(controller));
    final viewport = _viewport(tester);
    final resizes = <BoardSpan>[];
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {},
        onItemResized: (key, span) {
          resizes.add(span);
          controller.resizeItem(key, span);
        },
        primaryResizeEdges: BoardResizeEdges.trailing,
      ),
    );
    // Setup sanity: the row axis is primary.
    expect(controller.primaryAxis, Axis.vertical);
    // TARGET.
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(60.0, 195.0)),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      ),
      isTrue,
    );
    // Content y 299 is track-space row 5.98, which rounds to 6: the new
    // bottom edge, two tracks outward.
    drag.updateDrag(_global(tester, const Offset(60.0, 299.0)));
    await tester.pump();
    drag.endDrag(cancel: false);
    await tester.pumpAndSettle();
    expect(resizes, hasLength(1));
    expect(
      resizes.single,
      const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 4),
    );
    expect(viewport.rectOfItem("m")!.height, 200.0);
  });

  // A2. The policy split, one arm per case: `primaryResizeEdges` gates
  // the primary axis and `resizeEdges` the span axis, each on its own,
  // and a move ignores the axis. Each case names the scratch variant it
  // went red against: "one policy" read `resizeEdges` for both axes,
  // "primary policy" read `primaryResizeEdges` for both, "any edge"
  // accepted every edge under a non-none policy, and "no explicit axis"
  // refused every non-null axis.
  Future<bool> startsWith(
    WidgetTester tester,
    BoardDragConfig<String> config, {
    required BoardResizeEdges edge,
    required Axis? axis,
    Offset local = const Offset(60.0, 195.0),
  }) async {
    final controller = _controller(tester);
    await tester.pumpWidget(_board(controller));
    final drag = _drag(tester, controller, config);
    final started = drag.startDrag(
      key: "m",
      renderPort: _viewport(tester),
      pointerGlobal: _global(tester, local),
      edge: edge,
      axis: axis,
    );
    if (started) {
      drag.endDrag(cancel: true);
    }
    return started;
  }

  BoardDragConfig<String> spanTrailing() {
    return BoardDragConfig<String>(
      onItemMoved: (key, span) {},
      onItemResized: (key, span) {},
      resizeEdges: BoardResizeEdges.trailing,
    );
  }

  BoardDragConfig<String> primaryOnly(BoardResizeEdges edges) {
    return BoardDragConfig<String>(
      onItemMoved: (key, span) {},
      onItemResized: (key, span) {},
      primaryResizeEdges: edges,
    );
  }

  // Red against "one policy".
  testWidgets("the span policy alone refuses a vertical resize",
      (tester) async {
    expect(
      await startsWith(
        tester,
        spanTrailing(),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      ),
      isFalse,
    );
  });

  // Red against "no explicit axis".
  testWidgets("the span policy admits the horizontal axis named explicitly",
      (tester) async {
    expect(
      await startsWith(
        tester,
        spanTrailing(),
        edge: BoardResizeEdges.trailing,
        axis: Axis.horizontal,
      ),
      isTrue,
    );
  });

  // Red against "any edge".
  testWidgets("the primary policy's leading edge refuses a trailing "
      "vertical resize", (tester) async {
    expect(
      await startsWith(
        tester,
        primaryOnly(BoardResizeEdges.leading),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      ),
      isFalse,
    );
  });

  // Red against "one policy".
  testWidgets("the primary policy's leading edge admits a leading vertical "
      "resize", (tester) async {
    expect(
      await startsWith(
        tester,
        primaryOnly(BoardResizeEdges.leading),
        edge: BoardResizeEdges.leading,
        axis: Axis.vertical,
        local: const Offset(60.0, 105.0),
      ),
      isTrue,
    );
  });

  // Red against "primary policy".
  testWidgets("the primary policy leaves the span axis closed",
      (tester) async {
    expect(
      await startsWith(
        tester,
        primaryOnly(BoardResizeEdges.trailing),
        edge: BoardResizeEdges.trailing,
        axis: Axis.horizontal,
      ),
      isFalse,
    );
  });

  // Red against "no explicit axis".
  testWidgets("a move ignores the axis", (tester) async {
    expect(
      await startsWith(
        tester,
        primaryOnly(BoardResizeEdges.trailing),
        edge: BoardResizeEdges.none,
        axis: Axis.vertical,
      ),
      isTrue,
    );
  });

  // A3. The default handles: `primaryResizeEdges: trailing` builds a strip
  // along the item's bottom, and an immediate drag from it grows the row
  // span by one. Went red against the scratch variant that built the
  // primary strips without an axis (they then resized the span axis,
  // whose policy is `none` here, and refused).
  testWidgets("the default handles build a primary-axis strip that resizes "
      "the row span", (tester) async {
    final controller = _controller(tester);
    final resizes = <BoardSpan>[];
    await tester.pumpWidget(
      _board(
        controller,
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
    final viewport = _viewport(tester);
    final rect = viewport.rectOfItem("m")!;
    // Setup sanity: the item paints where the strip geometry assumes.
    expect(rect, const Rect.fromLTWH(40.0, 100.0, 40.0, 100.0));
    // The bottom strip is the item's last 12px.
    final gesture = await tester.startGesture(
      _global(tester, Offset(rect.center.dx, rect.bottom - 4.0)),
    );
    await gesture.moveBy(const Offset(0.0, 50.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // TARGET.
    expect(resizes, hasLength(1));
    expect(
      resizes.single,
      const BoardSpan(rowStart: 2, colStart: 1, rowSpan: 3),
    );
    expect(viewport.rectOfItem("m")!.height, 150.0);
  });
}
