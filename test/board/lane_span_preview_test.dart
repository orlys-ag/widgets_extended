/// Tests for the lane span expansion plan's DRAG cases: a make-room
/// preview cuts a neighbour's band on the makeRoom clock, a commit hands
/// the cut off with nothing stepping at release, and a resize that
/// de-lanes an expanded item previews from the width it PAINTS rather
/// than from one slice.
///
/// Source: `plans/2026-09-05-lane-span-expansion-plan.md`, the Testing
/// Plan section (anchor `testing-plan`). Case names are the plan's names
/// VERBATIM.
///
/// The fixtures and drag helpers are `lane_slice_preview_test.dart`'s,
/// COPIED rather than shared: that file's lattice has six 50px rows and
/// no lane padding, and the AC1 set below needs eight 20px rows and a
/// padded four-lane column.
///
/// Clock cadence: a case installs, pumps once with no duration (the
/// install frame; a ticker's first tick reports elapsed zero), then pumps
/// durations, so "at 100ms" means that second pump.
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

const BoardAnimationSpec _ms200 = BoardAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// itemSlide and makeRoom live, every other family off; dropSettle
/// inherits itemSlide.
const BoardAnimationStyle _previewStyle = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _ms200,
  itemEnterExit: _zero,
  makeRoom: _ms200,
);

/// FIXED-LANE: eight 20px rows (the SWEEP axis), seven 40px columns
/// carrying the lane extent (the LANE axis, fixed). A four-lane cluster
/// slices a column into `(40 - 4) / 4 = 9`, so one slice is 9, three are
/// 27 and lane 1's origin is `4 + 9 = 13` from the column's leading edge.
BoardController<String, _Item> _fixedLane(WidgetTester tester) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(8, 20.0)),
    columns: BoardAxisConfig(
      axis: UniformAxis(7, 40.0),
      laneExtent: 18.0,
      lanePadding: 4.0,
    ),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: _previewStyle,
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

/// A move session that commits through `moveItem`.
BoardDragController<String> _moveDrag(
  WidgetTester tester,
  BoardController<String, _Item> controller,
) {
  return _drag(
    tester,
    controller,
    BoardDragConfig<String>(
      autoScrollEdgeZone: 0.0,
      onItemMoved: (key, span) {
        controller.moveItem(key, span);
      },
    ),
  );
}

/// A trailing-edge resize session, both axes, that commits through
/// `resizeItem`.
BoardDragController<String> _resizeDrag(
  WidgetTester tester,
  BoardController<String, _Item> controller,
) {
  return _drag(
    tester,
    controller,
    BoardDragConfig<String>(
      autoScrollEdgeZone: 0.0,
      onItemMoved: (key, span) {},
      onItemResized: (key, span) {
        controller.resizeItem(key, span);
      },
      resizeEdges: BoardResizeEdges.trailing,
      primaryResizeEdges: BoardResizeEdges.trailing,
    ),
  );
}

double _width(WidgetTester tester, String key) {
  return tester.getSize(find.byKey(_itemKey(key))).width;
}

/// THE AC1 SET as ROW intervals in column 2: A [0, 7), B [1, 4),
/// C [2, 4), D [2, 4), E [4, 6). The resolve assigns A 0, B 1, C 2, D 3,
/// E 1 with laneCount 4 for all five, and E's band is lanes 1 to 3.
void _addAc1Rows(BoardController<String, _Item> controller) {
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 7),
  );
  controller.addItem(
    const _Item("b"),
    const BoardSpan(rowStart: 1, colStart: 2, rowSpan: 3),
  );
  controller.addItem(
    const _Item("c"),
    const BoardSpan(rowStart: 2, colStart: 2, rowSpan: 2),
  );
  controller.addItem(
    const _Item("d"),
    const BoardSpan(rowStart: 2, colStart: 2, rowSpan: 2),
  );
  controller.addItem(
    const _Item("e"),
    const BoardSpan(rowStart: 4, colStart: 2, rowSpan: 2),
  );
}

/// Lifts `g` at its centre and hovers it over column [col] on the same
/// rows. On the lane axis a laned item's target is the cell under the
/// POINTER, so the pointer goes to that column's centre.
Future<void> _hoverG(
  WidgetTester tester,
  BoardDragController<String> drag,
  int col,
) async {
  final viewport = _viewport(tester);
  final lift = viewport.rectOfItem("g")!.center;
  expect(
    drag.startDrag(
      key: "g",
      renderPort: viewport,
      pointerGlobal: _global(tester, lift),
    ),
    isTrue,
  );
  drag.updateDrag(_global(tester, Offset(col * 40.0 + 20.0, lift.dy)));
  await tester.pump();
}

void main() {
  // T8 (AC7). G lands in lane 2 of column 2's prospective cluster, which
  // is the lane E's band reaches into, so E's prospective span is 1 and
  // its band is cut from three slices to one. Falsification: red on the
  // baseline and against Landing Order step 1's tree, where E is 9
  // before, during and after the hover and the held delta is zero. The
  // 200ms reading is red against P2's OTHER half instead, a variant
  // whose `next` reads the stored span rather than the dry run's: there
  // the delta is zero and E holds 27 through the hover.
  testWidgets("a preview cuts a neighbour's band on the makeRoom clock", (
    tester,
  ) async {
    final controller = _fixedLane(tester);
    _addAc1Rows(controller);
    controller.addItem(
      const _Item("g"),
      const BoardSpan(rowStart: 4, colStart: 5, rowSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    expect(_width(tester, "e"), closeTo(27.0, 0.01));

    final drag = _moveDrag(tester, controller);
    await _hoverG(tester, drag, 2);

    // Setup sanity, each falsifiable: the target resolved to column 2
    // (hovering column 4 instead leaves E's cluster alone and reddens
    // every TARGET below), and the MODEL is untouched, so what follows is
    // the preview and not a mutation.
    expect(drag.currentTarget!.span.colStart, 2);
    expect(controller.laneOf("e"), 1);
    expect(controller.laneCountOf("e"), 4);
    expect(controller.laneSpanOf("e"), 3);

    // TARGET: E's band closes onto one slice over the makeRoom clock.
    expect(_width(tester, "e"), closeTo(27.0, 0.01));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_width(tester, "e"), closeTo(18.0, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_width(tester, "e"), closeTo(9.0, 0.01));
    expect(
      controller.anim.extentDeltaOf(controller.idOfKey("e")).dx,
      closeTo(-18.0, 0.01),
    );

    // The cancel closes the gap by animation, on the same clock.
    await tester.pump(const Duration(milliseconds: 16));
    drag.endDrag(cancel: true);
    await tester.pump();
    expect(_width(tester, "e"), closeTo(9.0, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_width(tester, "e"), closeTo(18.0, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_width(tester, "e"), closeTo(27.0, 0.01));
    expect(controller.laneSpanOf("e"), 3);
    await tester.pumpAndSettle();
  });

  // T9 (AC8). Falsification: the pre-commit 18 is red on the baseline,
  // where E paints 9 at every frame of the hover, and it is what makes
  // the continuity assertion non-vacuous.
  testWidgets("a commit hands the cut off with no step at release", (
    tester,
  ) async {
    final controller = _fixedLane(tester);
    _addAc1Rows(controller);
    controller.addItem(
      const _Item("g"),
      const BoardSpan(rowStart: 4, colStart: 5, rowSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();

    final drag = _moveDrag(tester, controller);
    await _hoverG(tester, drag, 2);
    await tester.pump(const Duration(milliseconds: 100));

    // Setup sanity: halfway through the cut, which is red on the
    // baseline at 9.
    final before = _width(tester, "e");
    expect(before, closeTo(18.0, 0.5));

    drag.endDrag(cancel: false);
    await tester.pump();

    // TARGET: the mutation lands the span and nothing steps at release.
    expect(controller.spanOf("g")!.colStart, 2);
    expect(controller.laneSpanOf("e"), 1);
    expect(_width(tester, "e"), closeTo(before, 0.5));

    // The published clock is the make-room time the gap had left.
    await tester.pump(const Duration(milliseconds: 50));
    expect(_width(tester, "e"), closeTo(13.5, 0.5));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_width(tester, "e"), closeTo(9.0, 0.01));
    await tester.pumpAndSettle();
    expect(_width(tester, "e"), closeTo(9.0, 0.01));
  });

  // T14 (C5, P2). E is prospectively UNLANED, two lane-axis tracks wide,
  // so `next` is the two-column extent 80 and `now` is the width E
  // PAINTS, `lanedExtent(4, 3) = 27`, giving a held target of 53.
  // Falsification: red against the scratch variant that lands C4 but
  // leaves C5's `now` span-free, where `now` is one slice of 9, the held
  // target is 71, the 100ms reading is 62.5 and the settled preview
  // reads 98, which is 18 past the width the item must reach and 18 it
  // would step down by at the commit.
  testWidgets("a resize that de-lanes an expanded item previews from the "
      "width it paints", (tester) async {
    final controller = _fixedLane(tester);
    _addAc1Rows(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();

    // Setup sanity, each falsifiable: E's band is three of column 2's
    // four slices, and that is what it paints.
    expect(controller.laneCountOf("e"), 4);
    expect(controller.laneSpanOf("e"), 3);
    expect(_width(tester, "e"), closeTo(27.0, 0.01));

    final viewport = _viewport(tester);
    final drag = _resizeDrag(tester, controller);
    final rect = viewport.rectOfItem("e")!;
    expect(
      drag.startDrag(
        key: "e",
        renderPort: viewport,
        pointerGlobal: _global(
          tester,
          Offset(3 * 40.0, rect.center.dy),
        ),
        edge: BoardResizeEdges.trailing,
        axis: Axis.horizontal,
      ),
      isTrue,
    );
    // One column outward: columns 2 and 3, which is two lane-axis
    // tracks and therefore unlaned.
    drag.updateDrag(_global(tester, Offset(4 * 40.0, rect.center.dy)));
    await tester.pump();

    // Setup sanity: the target resolved to two columns and the MODEL is
    // untouched.
    expect(drag.currentTarget!.span.colSpan, 2);
    expect(controller.spanOf("e")!.colSpan, 1);

    // TARGET: the preview runs from the 27 E paints to the 80 two whole
    // columns give it.
    await tester.pump(const Duration(milliseconds: 100));
    expect(_width(tester, "e"), closeTo(53.5, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_width(tester, "e"), closeTo(80.0, 0.01));
    expect(
      controller.anim.extentDeltaOf(controller.idOfKey("e")).dx,
      closeTo(53.0, 0.01),
    );

    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
  });
}
