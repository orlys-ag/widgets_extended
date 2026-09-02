/// Tests for the make-room COMMIT HAND-OFF.
///
/// A commit mid-gap snaps the preview's structure into place and hands
/// its MOTION on: every displaced neighbour keeps painting where it was
/// and slides the remainder of its lane on the make-room clock it was
/// already on, and a content-sized track's residue resizes on that same
/// clock. Nothing that was moving steps at release.
///
/// Every case failed at the assertion marked TARGET before the hand-off
/// landed, on the unfixed tree or against the scratch variant its comment
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

const BoardAnimationSpec _ms200 = BoardAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

const BoardAnimationSpec _ms400 = BoardAnimationSpec(
  duration: Duration(milliseconds: 400),
  curve: Curves.linear,
);

/// trackResize 400ms so a residue riding THAT family would visibly lag
/// the 200ms make-room clock the hand-off has to follow.
const BoardAnimationStyle _style = BoardAnimationStyle(
  trackResize: _ms400,
  itemSlide: _ms200,
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

Rect _probe(WidgetTester tester, String key) {
  return tester.getRect(find.byKey(ValueKey<String>("i$key")));
}

BoardDragController<String> _drag(
  WidgetTester tester,
  BoardController<String, _Item> controller, {
  required void Function(String key, BoardSpan span) onItemMoved,
}) {
  final drag = BoardDragController<String>(
    boardController: controller,
    vsync: tester,
    config: BoardDragConfig<String>(
      onItemMoved: onItemMoved,
      autoScrollEdgeZone: 0.0,
    ),
  );
  addTearDown(drag.dispose);
  return drag;
}

/// Row 0 holds `a` and `b` on lanes 0 and 1 (40px). Dragging `d` (row 2,
/// starting at column 0) over row 0 lanes it FIRST, displaces both
/// neighbours one lane down and grows the row to 58.
void _addTargetRowFixture(BoardController<String, _Item> controller) {
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
}

/// Row 2 holds `a`, `b`, `c` on lanes 0, 1, 2 (58px); row 0 holds `f`
/// (22px). Dragging `b` to row 0 re-lanes `c` onto lane 1, shrinking the
/// source row to 40, and takes lane 1 beside `f`, growing the target row
/// to 40 with NO displaced neighbour there.
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

/// Lifts [key] at its centre and moves the pointer to [local], pumping
/// the install frame.
Future<void> _liftTo(
  WidgetTester tester,
  BoardDragController<String> drag,
  RenderBoardViewport<String> viewport,
  String key,
  Offset local,
) async {
  final lift = viewport.rectOfItem(key)!.center;
  expect(
    drag.startDrag(
      key: key,
      renderPort: viewport,
      pointerGlobal: _global(tester, lift),
    ),
    isTrue,
  );
  drag.updateDrag(_global(tester, local));
  await tester.pump();
}

void main() {
  // H1. The target row, with displaced neighbours. Mid-gap at half a
  // lane, the commit lands the structure (b on lane 2, d on row 0) in
  // the drop frame while the painted row and neighbour stay put, then
  // finish the remaining half lane over the remaining 100ms of the
  // 200ms make-room clock, together.
  testWidgets("a commit mid-gap keeps the target row and its displaced "
      "neighbours where they painted", (tester) async {
    final controller = _controller(tester, _style);
    _addTargetRowFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final bId = controller.idOfKey("b");
    final restingTopB = _probe(tester, "b").top;
    final drag = _drag(
      tester,
      controller,
      onItemMoved: (key, span) {
        controller.moveItem(key, span);
      },
    );
    await _liftTo(tester, drag, viewport, "d", const Offset(20.0, 10.0));
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: mid-gap, half a lane open.
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(49.0, 0.5));
    expect(_probe(tester, "b").top, closeTo(restingTopB + 9.0, 0.5));
    expect(controller.laneOf("b"), 1);
    drag.endDrag(cancel: false);
    await tester.pump();
    // The structure landed in the drop frame.
    expect(controller.spanOf("d")!.rowStart, 0);
    expect(controller.laneOf("b"), 2);
    // TARGET: nothing painted moved.
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(49.0, 0.5));
    expect(_probe(tester, "b").top, closeTo(restingTopB + 9.0, 0.5));
    await tester.pump(const Duration(milliseconds: 50));
    // Half the remainder, row and neighbour on one clock.
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(53.5, 0.5));
    expect(_probe(tester, "b").top, closeTo(restingTopB + 13.5, 0.5));
    await tester.pump(const Duration(milliseconds: 50));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(58.0, 0.01));
    expect(_probe(tester, "b").top, closeTo(restingTopB + 18.0, 0.01));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    expect(controller.anim.offsetOfItem(bId), Offset.zero);
    await tester.pumpAndSettle();
  });

  // H2. The source row shrinks and its re-laned neighbour rises; the
  // target row grows with NO displaced neighbour (the calendar's
  // "append a chip to a full day" shape, where only the slot carried the
  // growth). Both rows and the neighbour finish on the one clock.
  testWidgets("a commit mid-gap hands the source row's shrink and the "
      "slot-only target row's growth off on the same clock", (tester) async {
    final controller = _controller(tester, _style);
    _addRelaningFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final cId = controller.idOfKey("c");
    expect(viewport.rectOfCell(2, 0)!.height, 58.0);
    expect(viewport.rectOfCell(0, 0)!.height, 22.0);
    final drag = _drag(
      tester,
      controller,
      onItemMoved: (key, span) {
        controller.moveItem(key, span);
      },
    );
    final liftB = viewport.rectOfItem("b")!.center;
    await _liftTo(tester, drag, viewport, "b", Offset(liftB.dx, 11.0));
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: the source row is half a lane shorter, c half a lane
    // up, the target row half a lane taller, and c's painted top is the
    // source row's top plus the padding plus one and a half lanes.
    expect(controller.anim.makeRoomSlotsOn(0).toList(), hasLength(1));
    expect(controller.anim.offsetOfItem(cId).dy, closeTo(-9.0, 0.5));
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(49.0, 0.5));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(31.0, 0.5));
    expect(
      _probe(tester, "c").top,
      closeTo(viewport.rectOfCell(2, 0)!.top + 31.0, 0.5),
    );
    drag.endDrag(cancel: false);
    await tester.pump();
    expect(controller.laneOf("c"), 1);
    expect(controller.laneOf("b"), 1);
    expect(controller.spanOf("b")!.rowStart, 0);
    // TARGET: nothing painted moved.
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(49.0, 0.5));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(31.0, 0.5));
    expect(
      _probe(tester, "c").top,
      closeTo(viewport.rectOfCell(2, 0)!.top + 31.0, 0.5),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(44.5, 0.5));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(35.5, 0.5));
    expect(
      _probe(tester, "c").top,
      closeTo(viewport.rectOfCell(2, 0)!.top + 26.5, 0.5),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(viewport.rectOfCell(2, 0)!.height, closeTo(40.0, 0.01));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(40.0, 0.01));
    expect(
      _probe(tester, "c").top,
      closeTo(viewport.rectOfCell(2, 0)!.top + 22.0, 0.01),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.anim.hasActiveTrackResize, isFalse);
    expect(controller.anim.offsetOfItem(cId), Offset.zero);
    await tester.pumpAndSettle();
  });

  // H3. The remainder runs as the TAIL of the make-room curve, so the
  // painted position after the commit is the position the uninterrupted
  // ramp would have reached: no velocity kink at release. A scratch
  // variant that re-ran the plain curve over the remaining time put b
  // 9.6 below rest at the 150ms mark against the 11.2 pinned here.
  testWidgets("a hand-off continues the make-room curve without a "
      "velocity kink", (tester) async {
    const eased = BoardAnimationSpec(
      duration: Duration(milliseconds: 200),
      curve: Curves.easeIn,
    );
    final controller = _controller(
      tester,
      const BoardAnimationStyle(
        trackResize: _ms400,
        itemSlide: _ms200,
        makeRoom: eased,
      ),
    );
    _addTargetRowFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final restingTopB = _probe(tester, "b").top;
    final drag = _drag(
      tester,
      controller,
      onItemMoved: (key, span) {
        controller.moveItem(key, span);
      },
    );
    await _liftTo(tester, drag, viewport, "d", const Offset(20.0, 10.0));
    await tester.pump(const Duration(milliseconds: 100));
    final atHalf = 18.0 * Curves.easeIn.transform(0.5);
    final atThreeQuarters = 18.0 * Curves.easeIn.transform(0.75);
    // Setup sanity: the eased ramp governs the gap.
    expect(_probe(tester, "b").top, closeTo(restingTopB + atHalf, 0.5));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(40.0 + atHalf, 0.5));
    drag.endDrag(cancel: false);
    await tester.pump();
    expect(_probe(tester, "b").top, closeTo(restingTopB + atHalf, 0.5));
    await tester.pump(const Duration(milliseconds: 50));
    // TARGET: the uninterrupted ramp's value at 150ms.
    expect(
      _probe(tester, "b").top,
      closeTo(restingTopB + atThreeQuarters, 0.5),
    );
    expect(
      viewport.rectOfCell(0, 0)!.height,
      closeTo(40.0 + atThreeQuarters, 0.5),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(_probe(tester, "b").top, closeTo(restingTopB + 18.0, 0.01));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(58.0, 0.01));
    await tester.pumpAndSettle();
  });

  // H4. The app declines the report (it mutates nothing). The structure
  // is unchanged, so the hand-off closes the gap from where it painted,
  // over the remaining clock, instead of stepping it shut.
  testWidgets("a report the app declines closes the gap from painted "
      "truth", (tester) async {
    final controller = _controller(tester, _style);
    _addTargetRowFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final restingTopB = _probe(tester, "b").top;
    var reports = 0;
    final drag = _drag(
      tester,
      controller,
      onItemMoved: (key, span) {
        reports += 1;
      },
    );
    await _liftTo(tester, drag, viewport, "d", const Offset(20.0, 10.0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_probe(tester, "b").top, closeTo(restingTopB + 9.0, 0.5));
    drag.endDrag(cancel: false);
    await tester.pump();
    // Setup sanity: reported, declined, structure untouched.
    expect(reports, 1);
    expect(controller.spanOf("d")!.rowStart, 2);
    expect(controller.laneOf("b"), 1);
    // TARGET: nothing painted moved.
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(49.0, 0.5));
    expect(_probe(tester, "b").top, closeTo(restingTopB + 9.0, 0.5));
    await tester.pump(const Duration(milliseconds: 50));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(44.5, 0.5));
    expect(_probe(tester, "b").top, closeTo(restingTopB + 4.5, 0.5));
    await tester.pump(const Duration(milliseconds: 50));
    expect(viewport.rectOfCell(0, 0)!.height, closeTo(40.0, 0.01));
    expect(_probe(tester, "b").top, closeTo(restingTopB, 0.01));
    await tester.pumpAndSettle();
  });

  // H5. A SETTLED gap has no motion to hand on: the snap publishes no
  // record and no neighbour slides. The null pin went red against a
  // scratch variant that folded settled entries into the hand-off; the
  // painted pin went red against one that captured structure instead of
  // painted truth and skipped the null guard, which slid b a lane back.
  testWidgets("a commit on a settled gap hands nothing off", (tester) async {
    final controller = _controller(tester, _style);
    _addTargetRowFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final restingTopB = _probe(tester, "b").top;
    final drag = _drag(
      tester,
      controller,
      onItemMoved: (key, span) {
        controller.moveItem(key, span);
      },
    );
    await _liftTo(tester, drag, viewport, "d", const Offset(20.0, 10.0));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    // Setup sanity: settled.
    expect(controller.anim.hasMakeRoomMotion, isFalse);
    expect(_probe(tester, "b").top, closeTo(restingTopB + 18.0, 0.01));
    drag.endDrag(cancel: false);
    await tester.pump();
    // TARGET: no motion was handed on. Row 2, which d emptied, shrinks
    // through an ordinary trackResize that is not the subject here, so
    // the global resize flag is not read.
    expect(controller.anim.makeRoomHandOff, isNull);
    expect(_probe(tester, "b").top, closeTo(restingTopB + 18.0, 0.01));
    await tester.pumpAndSettle();
  });

  // H6. Under the disabled style the gap snapped open at install, so a
  // commit finds nothing unsnapped and publishes nothing. Went red
  // against a scratch variant that folded snapped entries too. Every
  // kill switch refuses the continuation anyway, so the painted outcome
  // is not pinned here; `board_animation_zero_test.dart` owns that.
  testWidgets("a commit under BoardAnimationStyle.disabled hands nothing "
      "off", (tester) async {
    final controller = _controller(tester, BoardAnimationStyle.disabled);
    _addTargetRowFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final restingTopB = _probe(tester, "b").top;
    final drag = _drag(
      tester,
      controller,
      onItemMoved: (key, span) {
        controller.moveItem(key, span);
      },
    );
    await _liftTo(tester, drag, viewport, "d", const Offset(20.0, 10.0));
    // Setup sanity: the gap is open in full with no motion.
    expect(_probe(tester, "b").top, closeTo(restingTopB + 18.0, 0.01));
    expect(controller.anim.hasMakeRoomMotion, isFalse);
    drag.endDrag(cancel: false);
    await tester.pump();
    expect(controller.laneOf("b"), 2);
    // TARGET.
    expect(controller.anim.makeRoomHandOff, isNull);
  });

  // H7. The engine's record: a snap that discards unsnapped motion
  // publishes the remaining clock and the curve's tail; a snap that
  // discards none publishes nothing. The tail maps `[0, 1]` onto the
  // curve's `[t, 1]` segment, renormalised.
  testWidgets("a snap publishes the discarded motion's remaining clock "
      "and curve tail", (tester) async {
    const eased = BoardAnimationSpec(
      duration: Duration(milliseconds: 200),
      curve: Curves.easeIn,
    );
    final controller = _controller(
      tester,
      const BoardAnimationStyle(itemSlide: _ms200, makeRoom: eased),
    );
    _addTargetRowFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    expect(controller.anim.makeRoomHandOff, isNull);
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: const BoardSpan(rowStart: 0, colStart: 0, colSpan: 3),
      lifted: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    controller.releaseMakeRoomPreview(duration: Duration.zero);
    final handOff = controller.anim.makeRoomHandOff;
    // TARGET.
    expect(handOff, isNotNull);
    expect(handOff!.remaining, const Duration(milliseconds: 150));
    final at = Curves.easeIn.transform(0.25);
    expect(handOff.curve.transform(0.0), closeTo(0.0, 1e-9));
    expect(handOff.curve.transform(1.0), closeTo(1.0, 1e-9));
    expect(
      handOff.curve.transform(0.5),
      closeTo((Curves.easeIn.transform(0.625) - at) / (1.0 - at), 1e-9),
    );
    await tester.pumpAndSettle();
    // A settled gap: a snap that discards nothing publishes null, so a
    // stale record never outlives the snap that produced it.
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: const BoardSpan(rowStart: 0, colStart: 0, colSpan: 3),
      lifted: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.anim.hasMakeRoomMotion, isFalse);
    controller.releaseMakeRoomPreview(duration: Duration.zero);
    expect(controller.anim.makeRoomHandOff, isNull);
    await tester.pumpAndSettle();
  });
}
