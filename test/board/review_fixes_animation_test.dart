/// Promoted repros for the animation-source sections of the 2026-09-06
/// board review fixes plan: F4 (an overshooting itemEnterExit curve on a
/// laned board), F9 (a make-room curve tail interrupted mid-overshoot)
/// and F10 (a make-room gap's clock ignoring the session's captured
/// duration).
///
/// Every case failed at the assertion marked TARGET on the unfixed tree
/// with every setup sanity assertion before it passing; the exact
/// pre-fix output is recorded in the trial report, not here.
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

/// A LANED board on a CONTENT-SIZED lane axis: rows carry a lane extent,
/// so an item's extent on the lane axis is the lane band scaled by its
/// enter/exit ramp, and a row's extent is what its lanes need.
BoardController<String, _Item> _controller(
  WidgetTester tester,
  BoardAnimationStyle style,
) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(6, 80.0),
      laneExtent: 20.0,
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

/// Row 0 holds `a` and `b` on lanes 0 and 1. Dragging `d` (row 2,
/// column 0) over row 0 lanes it FIRST and displaces both neighbours
/// one lane down. The same fixture `make_room_commit_handoff_test.dart`
/// drives, on a lazy row axis there and a uniform one here.
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
  group("F4", () {
    // An enter under easeInBack: the curve is NEGATIVE for early t
    // (Cubic(0.6, -0.28, 0.735, 0.045)), and on a laned board the lane
    // band times that ramp is the child's tight extent.
    testWidgets("an overshooting enter curve never hands layout a "
        "negative extent", (tester) async {
      final controller = _controller(
        tester,
        const BoardAnimationStyle(
          itemEnterExit: BoardAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInBack,
          ),
        ),
      );
      controller.addItem(
        const _Item("s"),
        const BoardSpan(rowStart: 0, colStart: 1, colSpan: 2),
      );
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      // Setup sanity: the board is LANED. A settled item's height is the
      // lane extent, not the axis's 80px estimate.
      expect(_probe(tester, "s").height, 20.0);

      controller.addItem(
        const _Item("e"),
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
      );
      await tester.pump();
      // Setup sanity: the enter ramp is live, so the frame below reads a
      // curve value rather than the settled 1.
      expect(controller.anim.isEnteringItem(controller.idOfKey("e")), isTrue);
      await tester.pump(const Duration(milliseconds: 30));
      // TARGET: no negative constraint reached layout.
      expect(tester.takeException(), isNull);
      expect(_probe(tester, "e").height, greaterThanOrEqualTo(0.0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_probe(tester, "e").height, 20.0);
    });

    // The exit twin under easeOutBack: the curve is ABOVE 1 late in the
    // ramp (Cubic(0.175, 0.885, 0.32, 1.275)), so `from * (1 - eased)`
    // is negative there.
    testWidgets("an overshooting exit curve never hands layout a "
        "negative extent", (tester) async {
      final controller = _controller(
        tester,
        const BoardAnimationStyle(
          itemEnterExit: BoardAnimationSpec(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
          ),
        ),
      );
      controller.addItem(
        const _Item("x"),
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
      );
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      // Setup sanity: laned, and settled at one lane.
      expect(_probe(tester, "x").height, 20.0);

      controller.removeItem("x");
      await tester.pump();
      // Setup sanity: the exit ramp is live.
      expect(controller.anim.isExitingItem(controller.idOfKey("x")), isTrue);
      // Late in the exit: at 240 of 300ms easeOutBack is 1.0676, so the
      // unclamped ramp is -0.0676.
      await tester.pump(const Duration(milliseconds: 240));
      // TARGET.
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.contains("x"), isFalse);
    });
  });

  group("F9", () {
    // A commit while the make-room curve stands ABOVE 1. The published
    // tail must renormalise the overshoot back down to 1, so the
    // neighbour eases back from where it painted; a collapsed tail
    // reports 1 at every clock above 0 and the neighbour steps to rest
    // on its first tick. `Curve.transform` returns 0 at clock 0 without
    // consulting the tail, so the FIRST frame after the commit paints
    // the held position on either tree; the first tick after it is the
    // discriminating one.
    testWidgets("a hand-off interrupted mid-overshoot eases back rather "
        "than stepping", (tester) async {
      const overshoot = BoardAnimationSpec(
        duration: Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
      );
      final controller = _controller(
        tester,
        const BoardAnimationStyle(
          trackResize: _ms400,
          itemSlide: _ms200,
          makeRoom: overshoot,
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
      final atHalf = Curves.easeOutBack.transform(0.5);
      final atThreeQuarters = Curves.easeOutBack.transform(0.75);
      // Setup sanity: the commit lands PAST the overshoot, and the gap
      // is painted at the overshot value.
      expect(atHalf, greaterThan(1.0));
      expect(atThreeQuarters, greaterThan(1.0));
      expect(
        _probe(tester, "b").top,
        closeTo(restingTopB + 20.0 * atHalf, 0.5),
      );
      drag.endDrag(cancel: false);
      await tester.pump();
      expect(controller.laneOf("b"), 2);
      expect(
        _probe(tester, "b").top,
        closeTo(restingTopB + 20.0 * atHalf, 0.5),
      );
      await tester.pump(const Duration(milliseconds: 50));
      // TARGET: the uninterrupted ramp's value at 150ms, still past
      // rest, not rest itself.
      expect(
        _probe(tester, "b").top,
        closeTo(restingTopB + 20.0 * atThreeQuarters, 0.5),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(_probe(tester, "b").top, closeTo(restingTopB + 20.0, 0.01));
      await tester.pumpAndSettle();
    });
  });
}
