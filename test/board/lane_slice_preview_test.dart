/// Tests for the lane slice preview plan: on a FIXED lane axis, a
/// neighbour whose lane count the drop would change takes its
/// prospective slice DURING the make-room preview, on the make-room
/// clock beside its lead shift, and the commit is continuous.
///
/// Source: `plans/2026-09-05-lane-slice-preview-plan.md`, the Testing
/// Plan section (anchor `testing-plan`). Case names are the plan's names
/// VERBATIM.
///
/// Every case failed at the assertion marked TARGET before its landing
/// step, on the tree the case names or against the scratch variant its
/// comment names, with every setup sanity assertion before it passing.
///
/// Clock cadence: a case installs, pumps once with no duration (the
/// install frame; a ticker's first tick reports elapsed zero,
/// `scheduler/ticker.dart:276`), then pumps durations, so "at 100ms"
/// means that second pump.
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

/// The preview style with the drop-settle glide REFUSED, so that after
/// a no-op report nothing ticks and only the router's own settle latch
/// can lay the board out.
const BoardAnimationStyle _noGlideStyle = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _ms200,
  itemEnterExit: _zero,
  makeRoom: _ms200,
  dropSettle: _zero,
);

/// FIXED-LANE: six 50px rows, seven 40px columns carrying a lane extent
/// with no padding, so a column slices to 40 alone, 20 shared by two
/// and 13.33 shared by three.
BoardController<String, _Item> _fixedLane(
  WidgetTester tester, {
  BoardAnimationStyle style = _previewStyle,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
    columns: BoardAxisConfig(
      axis: UniformAxis(7, 40.0),
      laneExtent: 18.0,
      lanePadding: 0.0,
    ),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// CONTENT-LANE: the lattice of `make_room_track_sizing_test.dart`, rows
/// content-sized and carrying the lanes.
BoardController<String, _Item> _contentLane(WidgetTester tester) {
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
    animationStyle: _previewStyle,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _board(
  BoardController<String, _Item> controller, {
  double cellHeight = 50.0,
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
            cellBuilder: (context, cell) {
              return SizedBox(width: 40.0, height: cellHeight);
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

/// A move session whose report mutates NOTHING.
BoardDragController<String> _noOpMoveDrag(
  WidgetTester tester,
  BoardController<String, _Item> controller,
) {
  return _drag(
    tester,
    controller,
    BoardDragConfig<String>(
      autoScrollEdgeZone: 0.0,
      onItemMoved: (key, span) {},
    ),
  );
}

/// A trailing-edge resize session that commits through `resizeItem`.
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

double _left(WidgetTester tester, String key) {
  return tester.getRect(find.byKey(_itemKey(key))).left -
      tester.getRect(find.byKey(_frameKey)).left;
}

/// T1's fixture: `a` alone in column 2, `d` in column 5, both three rows.
void _addTargetFixture(BoardController<String, _Item> controller) {
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 3),
  );
  controller.addItem(
    const _Item("d"),
    const BoardSpan(rowStart: 0, colStart: 5, rowSpan: 3),
  );
}

/// Lifts `d` at its centre and hovers it over column [col] on the same
/// rows. On the lane axis a laned item's target is the cell under the
/// POINTER, so the pointer goes to that column's centre.
Future<BoardDragController<String>> _hoverD(
  WidgetTester tester,
  BoardController<String, _Item> controller,
  BoardDragController<String> drag,
  int col,
) async {
  final viewport = _viewport(tester);
  final lift = viewport.rectOfItem("d")!.center;
  expect(
    drag.startDrag(
      key: "d",
      renderPort: viewport,
      pointerGlobal: _global(tester, lift),
    ),
    isTrue,
  );
  drag.updateDrag(_global(tester, Offset(col * 40.0 + 20.0, lift.dy)));
  await tester.pump();
  return drag;
}

void main() {
  // T1. Falsification: on the baseline the width reads 40 at every
  // frame of the hover, the neighbour's slice being its STORED lane
  // count's.
  testWidgets(
    "a target neighbour shrinks to its prospective slice on the makeRoom "
    "clock",
    (tester) async {
      final controller = _fixedLane(tester);
      _addTargetFixture(controller);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      final drag = _moveDrag(tester, controller);
      expect(_width(tester, "a"), 40.0);
      await _hoverD(tester, controller, drag, 2);
      // Setup sanity: the target resolved to column 2 and the MODEL is
      // untouched.
      expect(drag.currentTarget!.span.colStart, 2);
      expect(controller.laneCountOf("a"), 1);
      // TARGET: the painted width animates onto the prospective slice.
      expect(_width(tester, "a"), closeTo(40.0, 0.01));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_width(tester, "a"), closeTo(30.0, 0.01));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_width(tester, "a"), closeTo(20.0, 0.01));
      expect(controller.laneCountOf("a"), 1);
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle();
    },
  );

  // T2. The width is the discriminator; the left edge pins the offset
  // the baseline already animates, so a width off the shared clock
  // cannot pass by matching a stale lead. Falsification: red on the
  // baseline at 20, and red against an extent installed on a fresh
  // clock one frame late.
  testWidgets(
    "a neighbour in a non-zero lane shifts and shrinks on one clock",
    (tester) async {
      final controller = _fixedLane(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 3),
      );
      controller.addItem(
        const _Item("b"),
        const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 3),
      );
      controller.addItem(
        const _Item("d"),
        const BoardSpan(rowStart: 0, colStart: 5, rowSpan: 3),
      );
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      // Setup sanity: two lanes of 20, b in lane 1.
      expect(controller.laneOf("b"), 1);
      expect(_left(tester, "b"), closeTo(100.0, 0.01));
      expect(_width(tester, "b"), closeTo(20.0, 0.01));
      final drag = _moveDrag(tester, controller);
      await _hoverD(tester, controller, drag, 2);
      await tester.pump(const Duration(milliseconds: 100));
      // Setup sanity: the lead is halfway from 20 to 13.33 inside the
      // column, which the baseline's offset already does.
      expect(_left(tester, "b"), closeTo(80.0 + 16.67, 0.05));
      // TARGET: the width is halfway from 20 to 13.33 on the SAME clock.
      expect(_width(tester, "b"), closeTo(16.67, 0.05));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_left(tester, "b"), closeTo(80.0 + 13.33, 0.05));
      expect(_width(tester, "b"), closeTo(13.33, 0.05));
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle();
    },
  );

  // T3. The symmetric case: the dragged item leaves a shared column and
  // its neighbour widens back to the whole slice while it hovers away.
  // Falsification: red on the baseline, where a stays 20 until the
  // commit.
  testWidgets("a source neighbour widens while the dragged item hovers "
      "away", (tester) async {
    final controller = _fixedLane(tester);
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 3),
    );
    controller.addItem(
      const _Item("d"),
      const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 3),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    // Setup sanity: shared, 20 each, a in lane 0.
    expect(_width(tester, "a"), closeTo(20.0, 0.01));
    expect(controller.laneOf("a"), 0);
    final drag = _moveDrag(tester, controller);
    await _hoverD(tester, controller, drag, 5);
    expect(drag.currentTarget!.span.colStart, 5);
    expect(controller.laneCountOf("a"), 2);
    // TARGET: a widens onto the whole column.
    expect(_width(tester, "a"), closeTo(20.0, 0.01));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_width(tester, "a"), closeTo(30.0, 0.01));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_width(tester, "a"), closeTo(40.0, 0.01));
    expect(_left(tester, "a"), closeTo(80.0, 0.01));
    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
  });

  // T4. Falsification: against a variant that omits the close rule for
  // extents (an entry absent from the install's targets is not
  // re-targeted to zero), a holds 20 through the second hover and until
  // the cancel.
  testWidgets(
    "a neighbour that leaves the dry run closes by animation, and a "
    "cancel closes the rest",
    (tester) async {
      final controller = _fixedLane(tester);
      _addTargetFixture(controller);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      final drag = _moveDrag(tester, controller);
      await _hoverD(tester, controller, drag, 2);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 16));
      // Setup sanity: settled at the shared slice.
      expect(_width(tester, "a"), closeTo(20.0, 0.01));
      // Hover column 4: a is no longer in the dry run and closes.
      drag.updateDrag(_global(tester, const Offset(4 * 40.0 + 20.0, 75.0)));
      await tester.pump();
      expect(drag.currentTarget!.span.colStart, 4);
      // TARGET: back to 40 on the makeRoom clock.
      await tester.pump(const Duration(milliseconds: 100));
      expect(_width(tester, "a"), closeTo(30.0, 0.01));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_width(tester, "a"), closeTo(40.0, 0.01));
      // Hover column 2 again, cancel mid-ramp: closes from where it
      // painted.
      drag.updateDrag(_global(tester, const Offset(2 * 40.0 + 20.0, 75.0)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_width(tester, "a"), closeTo(30.0, 0.01));
      drag.endDrag(cancel: true);
      await tester.pump();
      expect(_width(tester, "a"), closeTo(30.0, 0.5));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_width(tester, "a"), closeTo(35.0, 0.5));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_width(tester, "a"), closeTo(40.0, 0.01));
      expect(controller.laneCountOf("a"), 1);
      await tester.pumpAndSettle();
    },
  );

  // T5. Falsification: red on the baseline (40 at the drop frame, then
  // the FLIP replays the shrink), and red against a variant that leaves
  // the neighbour's extent FLIP unsuppressed in the report, which
  // restarts the shrink from 40.
  testWidgets(
    "a commit on a settled preview lands the neighbour without a step",
    (tester) async {
      final controller = _fixedLane(tester);
      _addTargetFixture(controller);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      final drag = _moveDrag(tester, controller);
      await _hoverD(tester, controller, drag, 2);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_width(tester, "a"), closeTo(20.0, 0.01));
      drag.endDrag(cancel: false);
      await tester.pump();
      // TARGET: no step at the drop frame and none after.
      expect(controller.laneCountOf("a"), 2);
      expect(_width(tester, "a"), closeTo(20.0, 0.01));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_width(tester, "a"), closeTo(20.0, 0.01));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_width(tester, "a"), closeTo(20.0, 0.01));
      await tester.pumpAndSettle();
      expect(_width(tester, "a"), closeTo(20.0, 0.01));
    },
  );

  // T6. Falsification: against a variant that drops the hand-off's
  // extent argument, a steps to 20 at the drop frame; against a variant
  // that keeps activeIds as the offset keys alone, a (lane 0, no
  // offset) is never captured and steps the same way.
  testWidgets(
    "a commit mid-preview finishes the neighbour on the hand-off clock",
    (tester) async {
      final controller = _fixedLane(tester);
      _addTargetFixture(controller);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      final drag = _moveDrag(tester, controller);
      await _hoverD(tester, controller, drag, 2);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_width(tester, "a"), closeTo(30.0, 0.01));
      drag.endDrag(cancel: false);
      await tester.pump();
      // TARGET: the drop frame paints what the preview painted, then
      // the remaining 100ms finish the shrink.
      expect(controller.laneCountOf("a"), 2);
      expect(_width(tester, "a"), closeTo(30.0, 0.01));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_width(tester, "a"), closeTo(25.0, 0.5));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_width(tester, "a"), closeTo(20.0, 0.01));
      await tester.pumpAndSettle();
      expect(_width(tester, "a"), closeTo(20.0, 0.01));
    },
  );

  // T7. G5: the resized item's own lane-axis slice previews when it is
  // laned under both spans, and its neighbour's with it. Falsification:
  // red on the baseline, where the both-laned arm answers zero for m
  // and nothing holds n's extent.
  testWidgets("a resize into a neighbour previews both slices", (
    tester,
  ) async {
    final controller = _fixedLane(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 3),
    );
    controller.addItem(
      const _Item("n"),
      const BoardSpan(rowStart: 4, colStart: 2, rowSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final drag = _resizeDrag(tester, controller);
    expect(_width(tester, "m"), 40.0);
    expect(_width(tester, "n"), 40.0);
    final edge = viewport.rectOfItem("m")!;
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, Offset(edge.center.dx, edge.bottom)),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      ),
      isTrue,
    );
    // Two rows outward: rows 0 to 5, overlapping n.
    drag.updateDrag(_global(tester, Offset(edge.center.dx, 250.0)));
    await tester.pump();
    // Setup sanity: the target resolved and the MODEL is untouched.
    expect(drag.currentTarget!.span.rowSpan, 5);
    expect(controller.spanOf("m")!.rowSpan, 3);
    expect(controller.laneCountOf("n"), 1);
    // TARGET: both slices animate onto 20.
    await tester.pump(const Duration(milliseconds: 100));
    expect(_width(tester, "m"), closeTo(30.0, 0.01));
    expect(_width(tester, "n"), closeTo(30.0, 0.01));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_width(tester, "m"), closeTo(20.0, 0.01));
    expect(_width(tester, "n"), closeTo(20.0, 0.01));
    expect(_left(tester, "n"), closeTo(100.0, 0.01));
    // The commit: both read 20 with no step.
    await tester.pump(const Duration(milliseconds: 16));
    drag.endDrag(cancel: false);
    await tester.pump();
    expect(controller.spanOf("m")!.rowSpan, 5);
    expect(controller.laneCountOf("n"), 2);
    expect(_width(tester, "m"), closeTo(20.0, 0.01));
    expect(_width(tester, "n"), closeTo(20.0, 0.01));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_width(tester, "m"), closeTo(20.0, 0.01));
    expect(_width(tester, "n"), closeTo(20.0, 0.01));
    await tester.pumpAndSettle();
  });

  // T8. G6 and P4: on a content-sized lane axis a lane change moves no
  // slice, so no extent entry is created. Falsification: against a
  // variant that installs a zero-target entry (drops the "nothing to
  // hold" arm), hasMakeRoomExtent reads true on the install frame.
  testWidgets("a lane change on a content-sized lane axis holds no extent",
      (tester) async {
    final controller = _contentLane(tester);
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
    await tester.pumpWidget(_board(controller, cellHeight: 20.0));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final drag = _moveDrag(tester, controller);
    final lift = viewport.rectOfItem("d")!.center;
    expect(
      drag.startDrag(
        key: "d",
        renderPort: viewport,
        pointerGlobal: _global(tester, lift),
      ),
      isTrue,
    );
    final target = viewport.rectOfCell(0, 2)!;
    drag.updateDrag(_global(tester, Offset(lift.dx, target.top + 10.0)));
    await tester.pump();
    // Setup sanity: the dry run ran and handed d a slot on row 0.
    expect(drag.currentTarget!.span.rowStart, 0);
    expect(controller.anim.makeRoomSlotsOn(0).toList(), hasLength(1));
    // TARGET: no extent is held for the lane change.
    expect(controller.anim.hasMakeRoomExtent, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.anim.hasMakeRoomExtent, isFalse);
    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
  });

  // T9. Falsification: against a variant that puts hasHeldExtent in the
  // layout-driving union, every tick of the slide beside the settled
  // preview lays out and the count advances.
  testWidgets(
    "a neighbour's slice preview lays out per tick while it moves and "
    "not once settled",
    (tester) async {
      final controller = _fixedLane(tester);
      _addTargetFixture(controller);
      controller.addItem(
        const _Item("e"),
        const BoardSpan(rowStart: 4, colStart: 0),
      );
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      final viewport = _viewport(tester);
      final drag = _moveDrag(tester, controller);
      await _hoverD(tester, controller, drag, 2);
      final moving = viewport.debugPerformLayoutCount;
      await tester.pump(const Duration(milliseconds: 100));
      // TARGET: laying out while it moves.
      expect(viewport.debugPerformLayoutCount, greaterThan(moving));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_width(tester, "a"), closeTo(20.0, 0.01));
      // A lead-only slide on ANOTHER item, between columns that touch
      // neither a's nor d's, so something ticks while the preview
      // stands settled. The pump that absorbs the mutation also absorbs
      // the one admitted-bound layout its 40px lead forces; the count is
      // read after it.
      controller.moveItem("e", const BoardSpan(rowStart: 4, colStart: 1));
      await tester.pump();
      final settled = viewport.debugPerformLayoutCount;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      // TARGET: the settled preview adds no layout, though a paint-only
      // slide is ticking beside it.
      expect(controller.anim.hasActiveOffsets, isTrue);
      expect(viewport.debugPerformLayoutCount, settled);
      expect(_width(tester, "a"), closeTo(20.0, 0.01));
      drag.endDrag(cancel: true);
      await tester.pumpAndSettle();
    },
  );

  // T10. The router's settle latch for a held extent that vanishes
  // without motion. Under a zero dropSettle the glide is refused, so
  // after a no-op report nothing ticks. Falsification: against a variant
  // without the latch, a holds its laid-out 20 with structure 40
  // underneath until something else lays out.
  testWidgets(
    "a no-op report after a settled extent-only preview restores the "
    "neighbour's slice",
    (tester) async {
      final controller = _fixedLane(tester, style: _noGlideStyle);
      _addTargetFixture(controller);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      final drag = _noOpMoveDrag(tester, controller);
      await _hoverD(tester, controller, drag, 2);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 16));
      // Setup sanity: settled at the shared slice, red on the baseline.
      expect(_width(tester, "a"), closeTo(20.0, 0.01));
      drag.endDrag(cancel: false);
      await tester.pump();
      // Setup sanity: the report mutated nothing and no glide stands.
      expect(controller.laneCountOf("a"), 1);
      expect(controller.spanOf("d")!.colStart, 5);
      expect(controller.anim.hasActiveOffsets, isFalse);
      expect(controller.anim.hasMakeRoomExtent, isFalse);
      // TARGET: laid out at its structural slice again.
      expect(_width(tester, "a"), closeTo(40.0, 0.01));
      await tester.pumpAndSettle();
    },
  );
}
