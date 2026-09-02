/// Tests for the make-room track sizing plan.
///
/// Source: `plans/2026-09-01-make-room-track-sizing-plan.md`, the Testing
/// Plan section (anchor `testing-plan`). Case names are the plan's names
/// VERBATIM.
///
/// Every case failed at the assertion marked TARGET before its landing
/// step, on the unfixed tree or against the scratch variant its comment
/// names, with every setup sanity assertion before it passing.
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

const BoardAnimationSpec _ms600 = BoardAnimationSpec(
  duration: Duration(milliseconds: 600),
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

/// A FIXED lane axis: uniform rows carrying a lane extent, so the router
/// never classifies make-room motion as layout-driving.
BoardController<String, _Item> _fixedController(
  WidgetTester tester,
  BoardAnimationStyle style,
) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: UniformAxis(6, 50.0),
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

/// A standalone drag controller for the scripted cases.
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

/// T2's cluster: two items sharing columns 2 to 5 in row 0, and the
/// dragged one sharing them in row 2, so a hover over row 0 ranks it
/// LAST by the id tie-break and displaces nobody.
void _addSlotOnlyCluster(BoardController<String, _Item> controller) {
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
}

/// The RE-LANING recipe: row 2 holds sweep-axis intervals [0, 5), [1, 4)
/// (the dragged b) and [2, 6) on lanes 0, 1, 2; f sits in row 0 at
/// [1, 4), added BEFORE b so the dry run lanes b after it there.
void _addRelaningFixture(BoardController<String, _Item> controller) {
  controller.addItem(
    const _Item("f"),
    const BoardSpan(rowStart: 0, colStart: 1, colSpan: 3),
  );
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 2, colStart: 0, colSpan: 5),
  );
  controller.addItem(
    const _Item("b"),
    const BoardSpan(rowStart: 2, colStart: 1, colSpan: 3),
  );
  controller.addItem(
    const _Item("c"),
    const BoardSpan(rowStart: 2, colStart: 2, colSpan: 4),
  );
}

Rect _probe(WidgetTester tester, String key) {
  return tester.getRect(find.byKey(ValueKey<String>("i$key")));
}

void main() {
  // T7. C4 and PAIR 4. An exit ramp on the TOP lane of the row above the
  // pointer shrinks that row continuously through the ramp latch (a
  // bottom-lane exit would instead re-lane the survivor at settle and
  // shrink through a trackResize, whose axis holds the target at once).
  // The pointer's x sits outside the 48px autoscroll edge zone. TARGET
  // arm: the target follows the cell under the stationary pointer, and
  // changes exactly once. CLEANUP arm: the hover's slot and key exist,
  // and nothing of them survives the cancel.
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
    final dId = controller.idOfKey("d");
    // Setup sanity: b sits in the top lane, row 0 is two lanes tall.
    expect(controller.laneOf("b"), 1);
    expect(viewport.rectOfCell(0, 0)!.height, 40.0);
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(onItemMoved: (key, span) {}),
    );
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
    // CLEANUP sanity: there is a state to reject.
    expect(controller.anim.makeRoomSlotsOn(1).toList(), hasLength(1));
    expect(controller.debugMakeRoomLiftedId, dId);

    var changes = 0;
    var last = drag.currentTarget!.span.rowStart;
    void check() {
      final row = drag.currentTarget!.span.rowStart;
      // Per frame: the target names the cell under the pointer in the
      // geometry this frame recorded.
      expect(row, viewport.trackSpaceAt(pointer)!.row.floor());
      if (row != last) {
        changes += 1;
        last = row;
      }
    }

    controller.removeItem("b");
    await tester.pump();
    check();
    final rowAfterRemoval = last;
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      check();
    }
    await tester.pumpAndSettle();
    check();
    // Setup sanity: the recorded axis moved row 2 under the pointer.
    expect(viewport.rectOfCell(0, 0)!.height, 22.0);
    expect(viewport.trackSpaceAt(pointer)!.row.floor(), 2);
    // TARGET, PAIR 4: the target names the cell under the pointer, and
    // it got there in exactly one change.
    expect(drag.currentTarget!.span.rowStart, 2);
    expect(rowAfterRemoval, isNot(2));
    expect(changes, 1);
    expect(tester.takeException(), isNull);

    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
    // CLEANUP: nothing of the hover survives the cancel.
    expect(tester.takeException(), isNull);
    expect(controller.anim.offsetOfItem(controller.idOfKey("a")), Offset.zero);
    expect(controller.anim.offsetOfItem(dId), Offset.zero);
    for (var row = 0; row < 6; row++) {
      expect(controller.anim.makeRoomSlotsOn(row), isEmpty);
    }
    expect(controller.debugMakeRoomLiftedId, isNull);
  });

  // T8. C4's subscription is unbound at teardown, and a post-frame
  // resolve pending across the dispose finds no session. The zero
  // makeRoom family is what makes the second half writable: a snapped
  // install dispatches synchronously, so `startDrag` leaves exactly one
  // post-frame resolve pending with no pump in between.
  testWidgets("disposing a drag controller mid-session leaves no "
      "animation listener", (tester) async {
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
      animationStyle: BoardAnimationStyle.disabled,
    );
    _addSlotOnlyCluster(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(onItemMoved: (key, span) {}),
    );
    final lift = viewport.rectOfItem("d")!.center;
    expect(
      drag.startDrag(
        key: "d",
        renderPort: viewport,
        pointerGlobal: _global(tester, lift),
      ),
      isTrue,
    );
    drag.dispose();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    expect(tester.takeException(), isNull);
  });

  // T-free. C1's idempotence rule on the one snap mode that defeats
  // `_resolve`'s early-out: under a free snap the resolved span carries a
  // lane-axis fraction read off the recorded axis, which the latch
  // re-records every tick, so `previewMakeRoomGap` is re-entered on every
  // frame of the resize. An install that restarted every clock there
  // would never let the gap settle.
  testWidgets("a free-snap hover settles instead of restarting the gap "
      "every frame", (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(trackResize: _ms400, itemSlide: _ms200),
    );
    _addRelaningFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final cId = controller.idOfKey("c");
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {},
        snap: const BoardSnap.free(),
        autoScrollEdgeZone: 0.0,
      ),
    );
    final lift = viewport.rectOfItem("b")!.center;
    expect(
      drag.startDrag(
        key: "b",
        renderPort: viewport,
        pointerGlobal: _global(tester, lift),
      ),
      isTrue,
    );
    // A point in a row BELOW the source row, so the source row's shrink
    // moves that row's offset and with it the anchor's fraction.
    final pointer = Offset(lift.dx, viewport.rectOfCell(3, 0)!.center.dy);
    drag.updateDrag(_global(tester, pointer));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // Setup sanity: the source bucket really re-laned, a term really
    // moves, and the resolve really is re-entering on every frame.
    expect(controller.anim.offsetOfItem(cId).dy, isNot(0.0));
    final fractionA = drag.currentTarget!.span.rowFraction;
    await tester.pump(const Duration(milliseconds: 16));
    final fractionB = drag.currentTarget!.span.rowFraction;
    expect(fractionA, isNot(fractionB));
    await tester.pump(const Duration(milliseconds: 200));
    // TARGET: one make-room duration plus a frame after the lift the gap
    // has settled and nothing else is in flight.
    expect(controller.anim.hasMakeRoomMotion, isFalse);
    expect(controller.anim.hasActiveTrackResize, isFalse);
    final layouts = viewport.debugPerformLayoutCount;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(viewport.debugPerformLayoutCount, layouts);
    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
  });

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
  });

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
  });

  // T2. Slot-only. The prospective span shares the cluster's exact
  // columns, so the dry run ranks the dragged id LAST by the id tie-break
  // and displaces nobody: the row grows only because the engine holds a
  // prospective lane SLOT for the lifted item.
  testWidgets("the lifted item's slot grows a target row with no "
      "displaced neighbour", (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(trackResize: _ms300, itemSlide: _ms300),
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
      const BoardSpan(rowStart: 2, colStart: 2, colSpan: 4),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    expect(viewport.rectOfCell(0, 0)!.height, 40.0);
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
      lifted: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // Setup sanity: nothing is displaced, so no held offset exists and
    // the slot is the only make-room contribution on this row.
    expect(controller.anim.offsetOfItem(controller.idOfKey("a")), Offset.zero);
    expect(controller.anim.offsetOfItem(controller.idOfKey("b")), Offset.zero);
    // TARGET: half the slot's lane, on the make-room clock.
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(49.0, 0.5));
    await tester.pump(const Duration(milliseconds: 150));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(58.0, 0.5));
    controller.releaseMakeRoomPreview();
    await tester.pumpAndSettle();
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(40.0, 0.5));
  });

  // T3b. The SOURCE bucket re-lanes when the dragged item leaves it. Row
  // 2 holds sweep-axis intervals [0, 5), [1, 4) (the dragged one) and
  // [2, 6) on lanes 0, 1, 2; the dry run drops the dragged id, re-sweeps
  // the survivors, and the third takes lane 1. Its held offset carries
  // the source row's term down on the make-room clock.
  testWidgets("a source neighbour that re-lanes shrinks the source row "
      "with the gap", (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(trackResize: _ms400, itemSlide: _ms200),
    );
    // f is ADDED BEFORE b, so the id tie-break ranks b after it in row 0
    // and the dry run lanes b at 1 there.
    controller.addItem(
      const _Item("f"),
      const BoardSpan(rowStart: 0, colStart: 1, colSpan: 3),
    );
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 2, colStart: 0, colSpan: 5),
    );
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 3),
    );
    controller.addItem(
      const _Item("c"),
      const BoardSpan(rowStart: 2, colStart: 2, colSpan: 4),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final cId = controller.idOfKey("c");
    // Setup sanity: three lanes on the source row, one on the target row.
    expect(controller.laneOf("c"), 2);
    expect(viewport.rectOfCell(2, 0)!.height, 58.0);
    expect(viewport.rectOfCell(0, 0)!.height, 22.0);
    expect(controller.anim.offsetOfItem(cId), Offset.zero);
    controller.previewMakeRoomGap(
      draggedKey: "b",
      prospective: const BoardSpan(rowStart: 0, colStart: 1, colSpan: 3),
      lifted: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: the dry run re-laned a SOURCE-bucket member, which is
    // what the height assertions below measure the term against.
    expect(controller.anim.offsetOfItem(cId).dy, closeTo(-9.0, 0.5));
    // TARGET: the source row follows that offset, on the make-room clock.
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(49.0, 0.5));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.anim.offsetOfItem(cId).dy, closeTo(-18.0, 0.5));
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(40.0, 0.5));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    controller.releaseMakeRoomPreview();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(49.0, 0.5));
    await tester.pumpAndSettle();
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(58.0, 0.5));
  });

  // T-settle. T2's script, whose slot IS the row's deepest ceiling, so on
  // the frame the tick retires it the term steps by the fraction of a
  // lane the slot still held. A NATURAL settle bumps no snap generation,
  // so the hand-off RECORDS that residue instead of installing a resize.
  //
  // THE CADENCE IS LOAD-BEARING and is 50ms steps into a 400ms close, not
  // the plan's 50ms into 300ms. A ticker's first callback after `start`
  // reports elapsed 0 (`scheduler/ticker.dart`, `_startTime ??=
  // timeStamp`), so the close's clock runs 0, 1/6, ... and its seventh
  // step sums to 0.9999999999999999 rather than 1.0. The slot is
  // therefore retired one frame LATER than the frame whose value was a
  // sixth of a lane, and the term the previous frame recorded is already
  // the settled one: no residue survives to the hand-off, and the case
  // stops discriminating against the scratch it names. 50ms into 400ms
  // divides exactly, so the retirement lands on the tick that first
  // reaches 1.0 and the residue is the eighth of a lane the frame before
  // it recorded.
  testWidgets("a gap that settles installs no trackResize", (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(trackResize: _ms300, itemSlide: _ms400),
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
    await tester.pump(const Duration(milliseconds: 400));
    // Setup sanity: the slot is fully open and owns the row's ceiling.
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(58.0, 0.5));
    controller.releaseMakeRoomPreview();
    final heights = <double>[];
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      heights.add(viewport.rectOfCell(0, 0)!.height);
      // TARGET: no frame of the close installs a resize.
      expect(controller.anim.hasActiveTrackResize, isFalse);
    }
    expect(heights.first, closeTo(58.0, 0.5));
    // The frame before the settle still held an eighth of a lane, which
    // is the residue the hand-off has to route.
    expect(heights[7], closeTo(42.25, 0.01));
    // TARGET: the residue is RECORDED, so the settle frame already sits
    // at the settled term rather than animating toward it.
    expect(heights.last, closeTo(40.0, 0.01));
    final laidOut = viewport.debugPerformLayoutCount;
    await tester.pump(const Duration(milliseconds: 100));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(40.0, 0.5));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    expect(viewport.debugPerformLayoutCount, laidOut);
  });

  // T5b. `effectiveMakeRoom` is `_makeRoom ?? itemSlide`, so a zero
  // itemSlide with a LIVE trackResize snaps every make-room install. The
  // latch reads the CONTRIBUTION and not its motion, so the snapped term
  // is recorded on the frame it appears instead of being handed to a
  // trackResize that animates behind the painted gap.
  testWidgets("a zero makeRoom family with a live trackResize lands the "
      "row without installing a resize", (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(trackResize: _ms400, itemSlide: _zero),
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
    // TARGET: the snapped term lands whole, on the next frame.
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(58.0, 0.5));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    await tester.pump(const Duration(milliseconds: 16));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(58.0, 0.5));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    controller.releaseMakeRoomPreview();
    await tester.pump();
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(40.0, 0.5));
    expect(controller.anim.hasActiveTrackResize, isFalse);
  });

  // T-handin. C2 arm 2's TRACK-RESIZE HAND-IN. A track whose extent is
  // about to become TERM-DRIVEN cannot leave a trackResize state in
  // flight: paint would read the animator's captured from/to pair, so
  // every recorded term would be invisible until the state is dropped and
  // would then pop. The in-flight state is CONSTRUCTED through the
  // existing internal-use channel rather than raced for.
  testWidgets("a gap opening on a resizing row hands that resize in "
      "rather than painting behind it", (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(trackResize: _ms600, itemSlide: _ms300),
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
      const BoardSpan(rowStart: 2, colStart: 2, colSpan: 4),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    expect(viewport.rectOfCell(0, 0)!.height, 40.0);
    controller.animateTrackResize(Axis.vertical, 0, 76.0, 40.0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: row 0 genuinely paints from the ANIMATOR, not from
    // the stored 40, and the state does not touch the axis.
    expect(controller.anim.hasActiveTrackResize, isTrue);
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(70.0, 0.5));
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
      lifted: true,
    );
    await tester.pump();
    // TARGET: the latch EDGE handed the state in, so the row paints the
    // recorded term from this frame on.
    expect(controller.anim.hasActiveTrackResize, isFalse);
    expect(viewport.rectOfCell(0, 0)!.height, inInclusiveRange(40.0, 41.5));
    await tester.pump(const Duration(milliseconds: 150));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(49.0, 0.5));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    await tester.pump(const Duration(milliseconds: 150));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(58.0, 0.5));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    controller.releaseMakeRoomPreview();
    await tester.pumpAndSettle();
  });
  // T0. Controller-only: the slot half of a lifted install. The source
  // track holds NO slot, which is the no-vacating-slot guard at the
  // engine level (a source neighbour's held OFFSET is a different
  // mechanism, pinned by T3b).
  testWidgets("previewMakeRoomGap records an occupying slot on the "
      "prospective track and none on the source", (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(trackResize: _ms300, itemSlide: _ms300),
    );
    _addSlotOnlyCluster(controller);
    final dId = controller.idOfKey("d");
    expect(controller.debugMakeRoomLiftedId, isNull);
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
      lifted: true,
    );
    final target = controller.anim.makeRoomSlotsOn(0).toList();
    expect(target, hasLength(1));
    expect(target.single.lane, 2);
    expect(target.single.value, 0.0);
    expect(controller.anim.makeRoomSlotsOn(2), isEmpty);
    expect(controller.debugMakeRoomLiftedId, dId);
    controller.releaseMakeRoomPreview();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.anim.makeRoomSlotsOn(0), isEmpty);
    expect(controller.anim.makeRoomSlotsOn(2), isEmpty);
    expect(controller.debugMakeRoomLiftedId, isNull);
  });

  // T-unlaned. The third lifecycle arm: an item spanning two lane-axis
  // rows is unlaned, its prospective span is unlaned too, so the dry run
  // holds nothing for it and no slot is ever created. The key must not
  // be claimed on a slotless install, and nothing must wait on a tick
  // that never comes.
  testWidgets("a lifted install that lanes nothing claims no lifecycle key",
      (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(trackResize: _ms300, itemSlide: _ms300),
    );
    controller.addItem(
      const _Item("h"),
      const BoardSpan(rowStart: 4, colStart: 1, colSpan: 2, rowSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final before = viewport.rectOfCell(1, 0)!.height;
    controller.previewMakeRoomGap(
      draggedKey: "h",
      prospective: const BoardSpan(
        rowStart: 1,
        colStart: 1,
        colSpan: 2,
        rowSpan: 2,
      ),
      lifted: true,
    );
    await tester.pump();
    // Setup sanity: the hover genuinely created nothing.
    expect(controller.anim.hasMakeRoomMotion, isFalse);
    expect(viewport.rectOfCell(1, 0)!.height, before);
    expect(controller.debugMakeRoomLiftedId, isNull);
    for (var row = 0; row < 6; row++) {
      expect(controller.anim.makeRoomSlotsOn(row), isEmpty);
    }
    controller.releaseMakeRoomPreview();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.debugMakeRoomLiftedId, isNull);
    for (var row = 0; row < 6; row++) {
      expect(controller.anim.makeRoomSlotsOn(row), isEmpty);
    }
  });

  // T3. Option A in the term: the lifted item's OWN ceiling stays in its
  // source row while it is lifted. This fixture's source bucket re-lanes
  // nothing (e is alone at lane 0 once d leaves), so row 2's stillness is
  // d's own ceiling and not a claim about source tracks in general.
  testWidgets("the lifted item keeps its band in its source row",
      (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(trackResize: _ms300, itemSlide: _ms300),
    );
    controller.addItem(
      const _Item("f"),
      const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
    );
    controller.addItem(
      const _Item("e"),
      const BoardSpan(rowStart: 2, colStart: 2, colSpan: 4),
    );
    controller.addItem(
      const _Item("d"),
      const BoardSpan(rowStart: 2, colStart: 2, colSpan: 4),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final fId = controller.idOfKey("f");
    final eId = controller.idOfKey("e");
    // Setup sanity: one lane in row 0, two in row 2, d on the top one.
    expect(controller.laneOf("d"), 1);
    expect(viewport.rectOfCell(0, 0)!.height, 22.0);
    expect(viewport.rectOfCell(2, 0)!.height, 40.0);
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
      lifted: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.anim.offsetOfItem(fId), Offset.zero);
    expect(controller.anim.offsetOfItem(eId), Offset.zero);
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(31.0, 0.5));
    expect(viewport.rectOfCell(2, 0)!.height, 40.0);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.anim.offsetOfItem(fId), Offset.zero);
    expect(controller.anim.offsetOfItem(eId), Offset.zero);
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(40.0, 0.5));
    expect(viewport.rectOfCell(2, 0)!.height, 40.0);
    controller.releaseMakeRoomPreview();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(31.0, 0.5));
    expect(viewport.rectOfCell(2, 0)!.height, 40.0);
    await tester.pumpAndSettle();
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(22.0, 0.5));
    expect(viewport.rectOfCell(2, 0)!.height, 40.0);
  });

  // T3c. DERIVED name: the plan's T3c pinned the pre-hand-off contract,
  // where the source row RECORDED its shrink because c's paint stepped in
  // the same frame. The commit hand-off inverted that: a snap that
  // discards motion publishes its remaining clock, and the hand-off arm
  // continues the residue on it for an OFFSET's discard as much as a
  // slot's. CONTROLLER-ONLY, so this pins the render arm alone: by hand
  // there is no painted-truth capture and c steps to lane 1, while the
  // row's edge continues; the drag path's coherent version is
  // `make_room_commit_handoff_test.dart`.
  testWidgets("a commit mid-gap continues the source row's shrink on the "
      "published clock", (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(trackResize: _ms400, itemSlide: _ms200),
    );
    _addRelaningFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final cId = controller.idOfKey("c");
    expect(controller.laneOf("c"), 2);
    expect(viewport.rectOfCell(2, 0)!.height, 58.0);
    expect(viewport.rectOfCell(0, 0)!.height, 22.0);
    expect(controller.anim.offsetOfItem(cId), Offset.zero);
    controller.previewMakeRoomGap(
      draggedKey: "b",
      prospective: const BoardSpan(rowStart: 0, colStart: 1, colSpan: 3),
      lifted: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: no slot on the source row, one on the target row, and
    // a residue to route.
    expect(controller.anim.makeRoomSlotsOn(2), isEmpty);
    expect(controller.anim.makeRoomSlotsOn(0).toList(), hasLength(1));
    expect(controller.anim.makeRoomSlotsOn(0).single.lane, 1);
    expect(controller.anim.offsetOfItem(cId).dy, closeTo(-9.0, 0.5));
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(49.0, 0.5));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(31.0, 0.5));
    // The commit's synchronous sequence, by hand: snap, then mutate, no
    // pump between.
    controller.releaseMakeRoomPreview(duration: Duration.zero);
    controller.moveItem(
      "b",
      const BoardSpan(rowStart: 0, colStart: 1, colSpan: 3),
    );
    await tester.pump();
    // TARGET: the source row keeps its painted extent in the drop frame
    // and continues to the committed term over the 100ms the gap had
    // left, not over the 400ms trackResize family.
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(49.0, 0.01));
    expect(controller.anim.hasActiveTrackResize, isTrue);
    expect(controller.anim.makeRoomHandOff!.remaining,
        const Duration(milliseconds: 100));
    expect(controller.anim.offsetOfItem(cId), Offset.zero);
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(31.0, 0.01));
    await tester.pump(const Duration(milliseconds: 50));
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(44.5, 0.01));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(35.5, 0.01));
    await tester.pump(const Duration(milliseconds: 50));
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(40.0, 0.01));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(40.0, 0.01));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    await tester.pumpAndSettle();
  });

  // T4. DERIVED name: the plan's T4 pinned the pre-hand-off contract,
  // where the neighbours stepped their unheld remainder in the drop
  // frame and the target row's GROWTH recorded there. The commit
  // hand-off keeps the snap generation bump but continues both on the
  // gap's remaining clock: 49 and half a lane in the drop frame, 58 and
  // a full lane 100ms later. Row 2 empties and shrinks 22 to 20 through
  // a trackResize, which is correct and not asserted away.
  testWidgets("a commit mid-gap continues the target row and its "
      "neighbours on the published clock", (tester) async {
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
    final restingTopB = _probe(tester, "b").top;
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {
          controller.moveItem(key, span);
        },
        autoScrollEdgeZone: 0.0,
      ),
    );
    final lift = viewport.rectOfItem("d")!.center;
    expect(
      drag.startDrag(
        key: "d",
        renderPort: viewport,
        pointerGlobal: _global(tester, lift),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, Offset(lift.dx, 10.0)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: mid-gap, the deepest neighbour is half a lane down.
    expect(_probe(tester, "b").top, closeTo(restingTopB + 9.0, 0.5));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(49.0, 0.5));
    final snapBefore = controller.anim.makeRoomSnapGeneration;
    drag.endDrag(cancel: false);
    await tester.pump();
    // TARGET: nothing painted moved in the drop frame.
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(49.0, 0.01));
    expect(_probe(tester, "b").top, closeTo(restingTopB + 9.0, 0.5));
    expect(controller.anim.makeRoomSnapGeneration, greaterThan(snapBefore));
    await tester.pump(const Duration(milliseconds: 100));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(58.0, 0.01));
    expect(_probe(tester, "b").top, closeTo(restingTopB + 18.0, 0.01));
    await tester.pumpAndSettle();
  });

  // T6. G7: on a FIXED lane axis the router never classifies make-room
  // motion as layout-driving. Slot-only by construction, because a gap
  // that displaces a neighbour lays out through the admitted-bound arm
  // on any code. On a FIXED axis a hover INTO a cluster is never
  // slot-only: the lane slices are the track's extent divided by the
  // lane count, so a third occupant moves both neighbours' origins and
  // hands them held offsets. The hover therefore lands on an EMPTY row.
  testWidgets("a slot-only make-room tick lays out nothing on a fixed "
      "lane axis", (tester) async {
    final controller = _fixedController(
      tester,
      const BoardAnimationStyle(trackResize: _ms300, itemSlide: _ms200),
    );
    _addSlotOnlyCluster(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: const BoardSpan(rowStart: 1, colStart: 2, colSpan: 4),
      lifted: true,
    );
    await tester.pump();
    // Setup sanity: genuinely slot-only, and genuinely in motion.
    expect(controller.anim.hasMakeRoomMotion, isTrue);
    expect(controller.anim.hasActiveOffsets, isFalse);
    expect(controller.anim.makeRoomSlotsOn(1).toList(), hasLength(1));
    expect(controller.anim.offsetOfItem(controller.idOfKey("a")), Offset.zero);
    expect(controller.anim.offsetOfItem(controller.idOfKey("b")), Offset.zero);
    final layouts = viewport.debugPerformLayoutCount;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    // TARGET: no layout on a mid-gap tick.
    expect(viewport.debugPerformLayoutCount, layouts);
    controller.releaseMakeRoomPreview();
    await tester.pumpAndSettle();
  });

  // T-retarget. A closing slot keeps the schedule it started on: the
  // first script watches it decay, the second re-installs INSIDE the
  // close and asserts the close was left alone (C1's idempotence rule on
  // the slot side).
  testWidgets("a re-targeted gap closes its previous slot on its own clock",
      (tester) async {
    Future<BoardController<String, _Item>> hover() async {
      final controller = _controller(
        tester,
        const BoardAnimationStyle(trackResize: _ms300, itemSlide: _ms300),
      );
      controller.addItem(
        const _Item("g"),
        const BoardSpan(rowStart: 1, colStart: 2, colSpan: 3),
      );
      controller.addItem(
        const _Item("d"),
        const BoardSpan(rowStart: 5, colStart: 2, colSpan: 3),
      );
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      final viewport = _viewport(tester);
      expect(viewport.rectOfCell(1, 0)!.height, 22.0);
      controller.previewMakeRoomGap(
        draggedKey: "d",
        prospective: const BoardSpan(rowStart: 1, colStart: 2, colSpan: 3),
        lifted: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 16));
      // Setup sanity: the slot is open and owns the row.
      expect(viewport.rectOfCell(1, 0)!.height, closeTo(40.0, 0.01));
      final slots = controller.anim.makeRoomSlotsOn(1).toList();
      expect(slots, hasLength(1));
      expect(slots.single.lane, 1);
      expect(slots.single.value, 1.0);
      // Re-target to empty row 3: the row 1 slot closes, (3, 0) opens.
      controller.previewMakeRoomGap(
        draggedKey: "d",
        prospective: const BoardSpan(rowStart: 3, colStart: 2, colSpan: 3),
        lifted: true,
      );
      await tester.pump();
      return controller;
    }

    var controller = await hover();
    var viewport = _viewport(tester);
    await tester.pump(const Duration(milliseconds: 150));
    expect(viewport.rectOfCell(1, 0)!.height, closeTo(31.0, 0.5));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 16));
    expect(viewport.rectOfCell(1, 0)!.height, closeTo(22.0, 0.01));
    expect(controller.anim.makeRoomSlotsOn(1), isEmpty);
    controller.releaseMakeRoomPreview();
    await tester.pumpAndSettle();

    // The exemption: a second install inside the close leaves the closing
    // slot on its own clock.
    controller = await hover();
    viewport = _viewport(tester);
    await tester.pump(const Duration(milliseconds: 100));
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: const BoardSpan(rowStart: 2, colStart: 2, colSpan: 3),
      lifted: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    // TARGET: 300ms after the close began the slot is gone; a restarted
    // clock would still hold a fifth of a lane here.
    expect(viewport.rectOfCell(1, 0)!.height, closeTo(22.0, 0.01));
    expect(controller.anim.makeRoomSlotsOn(1), isEmpty);
    controller.releaseMakeRoomPreview();
    await tester.pumpAndSettle();
  });

  // T-session. The three multi-session arms in one script: a LIFTED
  // first install for a DIFFERENT id snap-drops the previous session's
  // closing slot and hands its residue to a trackResize; a NON-lifted
  // (resize) install inside a close window leaves the closing slot and
  // the key alone.
  testWidgets("a second session inside the first release's close window "
      "drops the first's slots", (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(trackResize: _ms400, itemSlide: _ms300),
    );
    controller.addItem(
      const _Item("g"),
      const BoardSpan(rowStart: 1, colStart: 2, colSpan: 3),
    );
    controller.addItem(
      const _Item("d"),
      const BoardSpan(rowStart: 5, colStart: 2, colSpan: 3),
    );
    controller.addItem(
      const _Item("e"),
      const BoardSpan(rowStart: 4, colStart: 2, colSpan: 3),
    );
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final dId = controller.idOfKey("d");
    final eId = controller.idOfKey("e");
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {},
        onItemResized: (key, span) {},
        resizeEdges: BoardResizeEdges.trailing,
        autoScrollEdgeZone: 0.0,
      ),
    );
    // Session 1: d over row 1, settled.
    final liftD = viewport.rectOfItem("d")!.center;
    expect(
      drag.startDrag(
        key: "d",
        renderPort: viewport,
        pointerGlobal: _global(tester, liftD),
      ),
      isTrue,
    );
    drag.updateDrag(
      _global(tester, Offset(liftD.dx, viewport.rectOfCell(1, 0)!.center.dy)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 16));
    expect(viewport.rectOfCell(1, 0)!.height, closeTo(40.0, 0.01));
    drag.endDrag(cancel: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: the close window is real.
    expect(viewport.rectOfCell(1, 0)!.height, closeTo(34.0, 0.5));
    expect(controller.debugMakeRoomLiftedId, dId);
    final snapBefore = controller.anim.makeRoomSnapGeneration;
    // Session 2, with no further pump: a lifted first install for e.
    final liftE = viewport.rectOfItem("e")!.center;
    expect(
      drag.startDrag(
        key: "e",
        renderPort: viewport,
        pointerGlobal: _global(tester, liftE),
      ),
      isTrue,
    );
    // Row 3's rect is read NOW, while row 1 still stands at its last
    // recorded 34, and the pointer sits 4px into it: the trackResize this
    // install triggers on row 1 shrinks it by 12, moving row 3 up by 12
    // under the stationary pointer, and C4 re-resolves against that. A
    // pointer deeper in row 3 would correctly re-target to row 4.
    drag.updateDrag(
      _global(tester, Offset(liftE.dx, viewport.rectOfCell(3, 0)!.top + 4.0)),
    );
    expect(controller.anim.makeRoomSlotsOn(1), isEmpty);
    final slots3 = controller.anim.makeRoomSlotsOn(3).toList();
    expect(slots3, hasLength(1));
    expect(slots3.single.lane, 0);
    expect(slots3.single.value, 0.0);
    expect(controller.debugMakeRoomLiftedId, eId);
    expect(controller.anim.makeRoomSnapGeneration, greaterThan(snapBefore));
    await tester.pump();
    // TARGET: the dropped slot's residue is ANIMATED, from where the row
    // painted, because nothing paints in a slot.
    expect(viewport.rectOfCell(1, 0)!.height, inInclusiveRange(33.0, 34.5));
    expect(controller.anim.hasActiveTrackResize, isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 16));
    expect(viewport.rectOfCell(1, 0)!.height, closeTo(22.0, 0.01));
    // The NON-lifted arm: a resize session inside e's close window.
    drag.endDrag(cancel: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.debugMakeRoomLiftedId, eId);
    final gRect = viewport.rectOfItem("g")!;
    expect(
      drag.startDrag(
        key: "g",
        renderPort: viewport,
        pointerGlobal: _global(
          tester,
          Offset(gRect.right - 2.0, gRect.center.dy),
        ),
        edge: BoardResizeEdges.trailing,
      ),
      isTrue,
    );
    drag.updateDrag(
      _global(tester, Offset(gRect.right + 40.0, gRect.center.dy)),
    );
    expect(controller.debugMakeRoomLiftedId, eId);
    final closing = controller.anim.makeRoomSlotsOn(3).toList();
    expect(closing, hasLength(1));
    expect(closing.single.value, lessThan(1.0));
    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
  });
}
