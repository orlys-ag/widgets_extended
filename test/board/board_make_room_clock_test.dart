/// The make-room engine's clock. A gap's motion keeps its position when
/// the clock it runs on changes, a drag's close runs on the clock the
/// session captured, a commit's continuation never carries an item past
/// where it rests, and a second release leaves a gap or an extent that is
/// already closing on the schedule the first release started.
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

const BoardAnimationSpec _ms240 = BoardAnimationSpec(
  duration: Duration(milliseconds: 240),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// itemEnterExit inherits the zero trackResize, so an add installs no
/// enter.
const BoardAnimationStyle _gapStyle = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _ms240,
  makeRoom: _ms240,
);

/// The ticker's first frame, at zero elapsed, then one frame past the
/// end of a motion started on [_ms240].
Future<void> _settlePump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

/// Content-sized rows carrying an 18px lane, so a neighbour displaced one
/// lane moves exactly 18px (a fixed lane axis would slice its track
/// between the lanes instead).
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
          height: 360.0,
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

double _top(WidgetTester tester, String key) {
  return tester.getRect(find.byKey(ValueKey<String>("i$key"))).top;
}

/// Unmounts the board before the controller's own tear-down disposes it.
void _unmountFirst(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// Row 0 holds `a` (columns 2 and 3) and `b` (4 and 5), both on lane 0;
/// `d` (four columns) sits on row 3. Hovering `d` at column 0 of row 0
/// displaces `a` alone one lane down; at column 1 it displaces `a` to
/// the same lane and `b` as well, so `b`'s entry starts later than `a`'s.
void _addStaggerFixture(BoardController<String, _Item> controller) {
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 0, colStart: 2, colSpan: 2),
  );
  controller.addItem(
    const _Item("b"),
    const BoardSpan(rowStart: 0, colStart: 4, colSpan: 2),
  );
  controller.addItem(
    const _Item("d"),
    const BoardSpan(rowStart: 3, colStart: 0, colSpan: 4),
  );
}

/// Row 0 holds `a` and `b` on lanes 0 and 1; hovering `d` over row 0
/// laned first displaces both one lane down.
void _addTwoLaneFixture(BoardController<String, _Item> controller) {
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
    const BoardSpan(rowStart: 3, colStart: 0, colSpan: 3),
  );
}

void main() {
  // Test 1. A commit's continuation runs every discarded motion on ONE
  // clock, the earliest, and on that clock's curve tail renormalised by
  // `1 - curve(t)`. Under an overshooting curve with the earliest clock
  // just short of where the curve crosses 1, that divisor is small, and a
  // neighbour whose own motion was past the curve's peak, settling back
  // onto its rest, is carried several times its residual past rest the
  // other way.
  testWidgets("a commit's continuation never carries a neighbour past its "
      "rest", (tester) async {
    const overshoot = BoardAnimationSpec(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
    );
    final controller = _controller(
      tester,
      const BoardAnimationStyle(itemSlide: _ms300, makeRoom: overshoot),
    );
    _unmountFirst(tester);
    _addStaggerFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final restingA = _top(tester, "a");
    final restingB = _top(tester, "b");
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(
        onItemMoved: (key, span) {
          controller.moveItem(key, span);
        },
        autoScrollEdgeZone: 0.0,
      ),
    );
    addTearDown(drag.dispose);
    // Lift d at its leading cell so the grab offset is one cell's worth,
    // and hover it at column 0 of row 0: a is displaced.
    final lift = viewport.rectOfItem("d")!.topLeft + const Offset(20.0, 10.0);
    expect(
      drag.startDrag(
        key: "d",
        renderPort: viewport,
        pointerGlobal: _global(tester, lift),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(20.0, 10.0)));
    await tester.pump();
    // Setup sanity: a is displaced, b is not.
    expect(drag.currentTarget!.span.colStart, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_top(tester, "a"), greaterThan(restingA));
    expect(_top(tester, "b"), restingB);

    // Column 1: a keeps its target, and b's entry starts now.
    drag.updateDrag(_global(tester, const Offset(60.0, 10.0)));
    await tester.pump();
    expect(drag.currentTarget!.span.colStart, 1);
    // 105ms on: a is at 205 of 300ms, past the curve's peak and settling
    // back; b is at 105 of 300ms, just short of the crossing.
    await tester.pump(const Duration(milliseconds: 105));
    final heldA = _top(tester, "a");
    // Setup sanity: a overshoots its displaced rest and is on its way
    // back; b has not reached its displaced rest.
    expect(heldA, greaterThan(restingA + 18.0));
    expect(_top(tester, "b"), lessThan(restingB + 18.0));

    drag.endDrag(cancel: false);
    await tester.pump();
    // Setup sanity: both rest one lane down now.
    expect(controller.laneOf("a"), 1);
    expect(controller.laneOf("b"), 1);
    final restA = restingA + 18.0;
    var worst = 0.0;
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      // How far a has gone past its rest, away from where it was.
      final past = restA - _top(tester, "a");
      if (past > worst) {
        worst = past;
      }
    }
    // TARGET: a approaches its rest from where it painted and never
    // passes it.
    expect(worst, lessThan(0.01));
    await tester.pumpAndSettle();
  });

  // Test 2. A mid-session restyle of the makeRoom CURVE, then a cancel.
  // The gap ran on the curve the session captured; the close must start
  // where the gap painted. Two mechanisms hold this, the close on the
  // session's pair and the engine's re-base on a changed pair, and the
  // case is red only with both removed: it pins the property, and tests
  // 3 and 4 pin each mechanism.
  testWidgets("a cancel after a mid-session curve restyle closes from "
      "where the gap painted", (tester) async {
    const style = BoardAnimationStyle(itemSlide: _ms300, makeRoom: _ms300);
    final controller = _controller(tester, style);
    _unmountFirst(tester);
    _addTwoLaneFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final restingB = _top(tester, "b");
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(
        onItemMoved: (key, span) {},
        autoScrollEdgeZone: 0.0,
      ),
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
    drag.updateDrag(_global(tester, const Offset(20.0, 10.0)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // Setup sanity: half open, on the session's linear clock.
    expect(_top(tester, "b"), closeTo(restingB + 9.0, 0.5));

    controller.animationStyle = style.copyWith(
      makeRoom: const BoardAnimationSpec(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeIn,
      ),
    );
    drag.endDrag(cancel: true);
    await tester.pump();
    // TARGET: the close starts where the gap painted.
    expect(_top(tester, "b"), closeTo(restingB + 9.0, 0.5));
    await tester.pumpAndSettle();
  });

  // Test 3. A mid-session restyle of the makeRoom DURATION, then a cancel.
  // The session captured 300ms so the gap's clock ignores a restyle; the
  // close is the same gap's, and runs on the same clock.
  testWidgets("a cancel after a mid-session duration restyle closes on "
      "the session's clock", (tester) async {
    const style = BoardAnimationStyle(itemSlide: _ms300, makeRoom: _ms300);
    final controller = _controller(tester, style);
    _unmountFirst(tester);
    _addTwoLaneFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final restingB = _top(tester, "b");
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(
        onItemMoved: (key, span) {},
        autoScrollEdgeZone: 0.0,
      ),
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
    drag.updateDrag(_global(tester, const Offset(20.0, 10.0)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 16));
    // Setup sanity: fully open.
    expect(_top(tester, "b"), closeTo(restingB + 18.0, 0.01));

    controller.animationStyle = style.copyWith(
      makeRoom: const BoardAnimationSpec(
        duration: Duration(milliseconds: 3000),
        curve: Curves.linear,
      ),
    );
    drag.endDrag(cancel: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // TARGET: half closed on the session's 300ms, not a twentieth on the
    // restyled 3000ms.
    expect(_top(tester, "b"), closeTo(restingB + 9.0, 0.5));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_top(tester, "b"), closeTo(restingB, 0.01));
  });

  // Test 4. The engine holds ONE clock, a duration and a curve, for every
  // entry; an install whose pair differs from it used to swap it under
  // the entries it leaves alone, so each jumped to the value the new
  // curve gives at its old clock.
  testWidgets("an install with a new clock keeps every entry where it "
      "painted", (tester) async {
    final controller = _controller(
      tester,
      const BoardAnimationStyle(itemSlide: _ms300, makeRoom: _ms300),
    );
    _unmountFirst(tester);
    _addTwoLaneFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final restingB = _top(tester, "b");
    const prospective = BoardSpan(rowStart: 0, colStart: 0, colSpan: 3);
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: prospective,
      lifted: true,
      duration: const Duration(milliseconds: 300),
      curve: Curves.linear,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // Setup sanity: half open.
    expect(_top(tester, "b"), closeTo(restingB + 9.0, 0.5));

    // The same target, so b's entry is left alone, on a new clock.
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: prospective,
      lifted: true,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeIn,
    );
    await tester.pump();
    // TARGET: b paints where it did ...
    expect(_top(tester, "b"), closeTo(restingB + 9.0, 0.5));
    await tester.pump(const Duration(milliseconds: 300));
    // ... and runs the rest on the new clock from there: half of the
    // 600ms, eased in, from 9 toward 18.
    expect(
      _top(tester, "b"),
      closeTo(restingB + 9.0 + 9.0 * Curves.easeIn.transform(0.5), 0.5),
    );
    controller.releaseMakeRoomPreview();
    await tester.pumpAndSettle();
  });

  testWidgets("a second release leaves a closing gap on its schedule", (
    tester,
  ) async {
    final controller = _controller(tester, _gapStyle);
    _addTwoLaneFixture(controller);
    await _settlePump(tester);
    final idA = controller.idOfKey("a");
    final anim = controller.anim;
    final half = _ms240.duration ~/ 2;
    controller.previewMakeRoomGap(
      draggedKey: "d",
      prospective: const BoardSpan(rowStart: 0, colStart: 0, colSpan: 3),
      lifted: true,
      duration: _ms240.duration,
      curve: _ms240.curve,
    );
    await _settlePump(tester);
    // Setup sanity: the preview displaces `a` one lane.
    expect(anim.offsetOfItem(idA).dy, 18.0);

    controller.releaseMakeRoomPreview(
      duration: _ms240.duration,
      curve: _ms240.curve,
    );
    await tester.pump();
    await tester.pump(half);
    // Setup sanity: the first release closes on the configured clock.
    expect(anim.offsetOfItem(idA).dy, closeTo(9.0, 0.01));

    controller.releaseMakeRoomPreview(
      duration: _ms240.duration,
      curve: _ms240.curve,
    );
    await tester.pump(half);
    // TARGET a: `a` is at rest when the first release's close ends.
    expect(anim.offsetOfItem(idA), Offset.zero);
    // TARGET b: no held offset is left to close.
    expect(anim.hasActiveOffsets, isFalse);
  });

  testWidgets("a second release leaves a closing extent on its schedule", (
    tester,
  ) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: _gapStyle,
    );
    addTearDown(controller.dispose);
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 0, colStart: 0),
    );
    final idA = controller.idOfKey("a");
    final anim = controller.anim;
    final half = _ms240.duration ~/ 2;
    // A resize preview of `a` over three columns, which holds the two
    // columns it adds as `a`'s extent.
    controller.previewMakeRoomGap(
      draggedKey: "a",
      prospective: const BoardSpan(rowStart: 0, colStart: 0, colSpan: 3),
      duration: _ms240.duration,
      curve: _ms240.curve,
    );
    await _settlePump(tester);
    // Setup sanity: the preview holds the extent of two columns.
    expect(anim.extentDeltaOf(idA), const Offset(80.0, 0.0));

    controller.releaseMakeRoomPreview(
      duration: _ms240.duration,
      curve: _ms240.curve,
    );
    await tester.pump();
    await tester.pump(half);
    // Setup sanity: the first release closes on the configured clock.
    expect(anim.extentDeltaOf(idA), const Offset(40.0, 0.0));

    controller.releaseMakeRoomPreview(
      duration: _ms240.duration,
      curve: _ms240.curve,
    );
    await tester.pump(half);
    // TARGET a: `a` is at its extent when the first release's close ends.
    expect(anim.extentDeltaOf(idA), Offset.zero);
    // TARGET b: no held extent is left to close.
    expect(anim.hasMakeRoomExtent, isFalse);
  });

  testWidgets("a refused hover then a cancel closes the gap on the "
      "refusal's schedule", (tester) async {
    final controller = _controller(tester, _gapStyle);
    _unmountFirst(tester);
    _addTwoLaneFixture(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();
    final viewport = _viewport(tester);
    final restingB = _top(tester, "b");
    final half = _ms240.duration ~/ 2;
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(
        onItemMoved: (key, span) {},
        canDropAt: (key, span) {
          return span.colStart == 0;
        },
        autoScrollEdgeZone: 0.0,
      ),
    );
    addTearDown(drag.dispose);
    // Lift d at its leading cell so the grab offset is one cell's worth.
    final lift = viewport.rectOfItem("d")!.topLeft + const Offset(20.0, 10.0);
    expect(
      drag.startDrag(
        key: "d",
        renderPort: viewport,
        pointerGlobal: _global(tester, lift),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(20.0, 10.0)));
    await _settlePump(tester);
    // Setup sanity: column 0 is admitted and its gap is open.
    expect(drag.currentTarget, isNotNull);
    expect(_top(tester, "b"), closeTo(restingB + 18.0, 0.01));

    drag.updateDrag(_global(tester, const Offset(60.0, 10.0)));
    // Setup sanity: column 1 is refused, and the refusal releases the gap.
    expect(drag.currentTarget, isNull);
    await tester.pump();
    await tester.pump(half);
    // Setup sanity: the gap is half closed on the refusal's release.
    expect(_top(tester, "b"), closeTo(restingB + 9.0, 0.5));

    drag.endDrag(cancel: true);
    await tester.pump(half);
    await tester.pump(const Duration(milliseconds: 16));
    // TARGET: the cancel's release left the close on the refusal's
    // schedule, so `b` is at rest.
    expect(_top(tester, "b"), closeTo(restingB, 0.01));
    await tester.pumpAndSettle();
  });
}
