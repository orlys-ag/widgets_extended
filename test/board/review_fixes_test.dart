/// Promoted repros from the 2026-09-06 board review
/// (`plans/2026-09-06-board-review-fixes-plan.md`). Each case carries the
/// section it pins in its title; the setup sanity assertions are ones that
/// can fail, and the TARGET assertion is the one shown red on the tree
/// before its section landed.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
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

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

const BoardAnimationSpec _slide = BoardAnimationSpec(
  duration: Duration(milliseconds: 300),
  curve: Curves.linear,
);

/// Slides on, everything extent-driving off: the FLIP and the drop-settle
/// glide are the subjects here, and a track resize would move the cells
/// under them.
const BoardAnimationStyle _slidesOnly = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _slide,
);

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  required int rows,
  required int cols,
  BoardAnimationStyle animationStyle = _slidesOnly,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(rows, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(cols, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: animationStyle,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _board(
  BoardController<String, _Item> controller, {
  required Size frame,
  bool reverseVertical = false,
  BoardDragConfig<String>? drag,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: _frameKey,
          width: frame.width,
          height: frame.height,
          child: Board<String, _Item>(
            controller: controller,
            drag: drag,
            verticalDetails: ScrollableDetails.vertical(
              reverse: reverseVertical,
            ),
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

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

RenderBoardViewport<String> _viewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

int _clipRectLayerCount(WidgetTester tester) {
  return tester.layers.whereType<ClipRectLayer>().length;
}

void main() {
  testWidgets(
    "F2 an item sliding out of the viewport paints and hit-tests until it leaves",
    (tester) async {
      final controller = _controller(tester, rows: 30, cols: 7);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 1, colStart: 0),
      );
      await tester.pumpWidget(
        _board(controller, frame: const Size(280.0, 200.0)),
      );
      final viewport = _viewport(tester);

      // Setup sanity: at rest the item paints at row 1 and is reachable by
      // both probes, so a miss below is the slide's.
      expect(
        tester.getTopLeft(find.byKey(_itemKey("a"))),
        const Offset(0.0, 50.0),
      );
      expect(find.byKey(_itemKey("a")).hitTestable(), findsOneWidget);
      expect(viewport.itemAt(const Offset(20.0, 75.0)), "a");

      // Row 10 starts at y=500, beyond the 200px viewport: the structural
      // rect leaves, the FLIP lead holds the item where it was.
      controller.moveItem("a", const BoardSpan(rowStart: 10, colStart: 0));
      await tester.pump();

      // Setup sanity: the install frame reports the item where it was, so
      // the lead is applied and the child is mounted.
      expect(
        tester.getTopLeft(find.byKey(_itemKey("a"))),
        const Offset(0.0, 50.0),
      );
      // TARGET. The item is hit-testable where it reports itself, and the
      // probe agrees.
      expect(find.byKey(_itemKey("a")).hitTestable(), findsOneWidget);
      expect(viewport.itemAt(const Offset(20.0, 75.0)), "a");

      await tester.pump(const Duration(milliseconds: 100));
      // One third in: y = 50 + 450 / 3 = 200, the viewport's bottom edge,
      // where the item is exactly gone.
      expect(
        tester.getTopLeft(find.byKey(_itemKey("a"))).dy,
        moreOrLessEquals(200.0),
      );
      expect(viewport.itemAt(const Offset(20.0, 199.0)), isNull);
      await tester.pumpAndSettle();
    },
  );

}
