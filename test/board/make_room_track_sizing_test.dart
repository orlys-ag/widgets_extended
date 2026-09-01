/// Tests for the make-room track sizing plan.
///
/// Source: `plans/2026-09-01-make-room-track-sizing-plan.md`, the Testing
/// Plan section (anchor `testing-plan`). Case names are the plan's names
/// VERBATIM.
///
/// The three cases below were the audit's repros: each failed on the
/// unfixed tree at the assertion marked TARGET, with every setup sanity
/// assertion before it passing. They are SKIPPED until the plan lands;
/// remove the skip with the landing step that makes each green.
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

const BoardAnimationSpec _ms300 = BoardAnimationSpec(
  duration: Duration(milliseconds: 300),
  curve: Curves.linear,
);

const BoardAnimationSpec _ms200 = BoardAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

const BoardAnimationSpec _ms400 = BoardAnimationSpec(
  duration: Duration(milliseconds: 400),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

BoardController<String, _Item> _controller(
  WidgetTester tester,
  BoardAnimationStyle style,
) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(6, 80.0),
      laneExtent: 18.0,
      lanePadding: 4.0,
    ),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
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
              return const SizedBox(width: 40.0, height: 20.0);
            },
            itemBuilder: (context, item) {
              return ColoredBox(
                key: ValueKey<String>("i${item.key}"),
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

void main() {
  // T7. Independent of the sizing change: an exit ramp on the TOP lane of
  // the row above the pointer shrinks that row continuously through the
  // ramp latch (a bottom-lane exit would instead re-lane the survivor at
  // settle and shrink through a trackResize, whose axis holds the target
  // at once). The pointer's x sits outside the 48px autoscroll edge zone.
  testWidgets("the target follows the row under a stationary pointer while "
      "a row above it shrinks", (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(trackResize: _ms300, itemSlide: _zero),
    );
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
    );
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
    );
    controller.addItem(
      const _Item("d"),
      const BoardSpan(rowStart: 5, colStart: 0, colSpan: 3),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    // Setup sanity: b sits in the top lane, row 0 is two lanes tall.
    expect(controller.laneOf("b"), 1);
    expect(viewport.rectOfCell(0, 0)!.height, 40.0);
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(onItemMoved: (key, span) {}),
    );
    addTearDown(drag.dispose);
    final lift = viewport.rectOfItem("d")!.center;
    expect(
      drag.startDrag(
        key: "d",
        renderPort: viewport,
        pointerGlobal: _global(tester, lift),
      ),
      isTrue,
    );
    const pointer = Offset(140.0, 55.0);
    drag.updateDrag(_global(tester, pointer));
    await tester.pump();
    expect(drag.currentTarget!.span.rowStart, 1);

    controller.removeItem("b");
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    // Setup sanity: the recorded axis moved row 2 under the pointer.
    expect(viewport.rectOfCell(0, 0)!.height, 22.0);
    expect(viewport.trackSpaceAt(pointer)!.row.floor(), 2);
    // TARGET, PAIR 4: the target names the cell under the pointer.
    expect(drag.currentTarget!.span.rowStart, 2);
    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
  }, skip: true); // Until plan 2026-09-01-make-room-track-sizing lands.

  // T5. The slot-only hover: nothing is displaced, so no held offset exists
  // and no existing router arm lays out; the audit verified on the unfixed
  // tree that debugPerformLayoutCount stays flat across the hover.
  testWidgets("under BoardAnimationStyle.disabled a slot-only hover lands "
      "the row on the next frame", (tester) async {
    final controller = _controller(tester, BoardAnimationStyle.disabled);
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
    );
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
    );
    controller.addItem(
      const _Item("d"),
      const BoardSpan(rowStart: 2, colStart: 2, colSpan: 4),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
      lifted: true,
    );
    await tester.pump();
    // Setup sanity: nothing displaced.
    expect(controller.anim.offsetOfItem(controller.idOfKey("a")), Offset.zero);
    expect(controller.anim.offsetOfItem(controller.idOfKey("b")), Offset.zero);
    // TARGET: three lanes, on the next frame.
    expect(viewport.rectOfCell(0, 0)!.height, 58.0);
    controller.releaseMakeRoomPreview();
    await tester.pump();
    expect(viewport.rectOfCell(0, 0)!.height, 40.0);
  }, skip: true); // Until plan 2026-09-01-make-room-track-sizing lands.

  // T1. Distinct family durations: makeRoom (through itemSlide) 200ms,
  // trackResize 400ms. At 100ms the gap is half open; a row that follows
  // the gap reads 49, a row driven by a trackResize installed at the hover
  // would read 44.5, and the unfixed row reads 40.
  testWidgets("a displaced neighbour's row grows with the gap",
      (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(trackResize: _ms400, itemSlide: _ms200),
    );
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
    );
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
    );
    controller.addItem(
      const _Item("d"),
      const BoardSpan(rowStart: 2, colStart: 0, colSpan: 3),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final restingTop = tester.getRect(find.byKey(const ValueKey<String>("ia"))).top;
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: const BoardSpan(rowStart: 0, colStart: 0, colSpan: 3),
      lifted: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: mid-gap, a is displaced by half a lane.
    expect(
      tester.getRect(find.byKey(const ValueKey<String>("ia"))).top,
      closeTo(restingTop + 9.0, 0.5),
    );
    // TARGET: b's painted ceiling plus padding.
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(49.0, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(58.0, 0.5));
    controller.releaseMakeRoomPreview();
    await tester.pumpAndSettle();
  }, skip: true); // Until plan 2026-09-01-make-room-track-sizing lands.
}
