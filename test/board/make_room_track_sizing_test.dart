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
}
