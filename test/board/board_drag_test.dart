/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 11 with the interaction layer. Scripted
/// cases drive a standalone [BoardDragController] against the pumped
/// board's render port; handle cases drive the Board-owned controller
/// through real gestures.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_views.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_drag_handle.dart';
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

BoardController<String, _Item> _plainController(WidgetTester tester) {
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
  return controller;
}

BoardController<String, _Item> _lanedController(WidgetTester tester) {
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
  addTearDown(controller.dispose);
  return controller;
}

Widget _board(
  BoardController<String, _Item> controller, {
  BoardDragConfig<String>? drag,
  Widget Function(BuildContext, BoardItemView<String, _Item>)? itemBuilder,
  ScrollController? vertical,
  ScrollController? horizontal,
  double width = 280.0,
  double height = 300.0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: _frameKey,
          width: width,
          height: height,
          child: Board<String, _Item>(
            controller: controller,
            drag: drag,
            verticalDetails: vertical == null
                ? const ScrollableDetails.vertical()
                : ScrollableDetails.vertical(controller: vertical),
            horizontalDetails: horizontal == null
                ? const ScrollableDetails.horizontal()
                : ScrollableDetails.horizontal(controller: horizontal),
            cellBuilder: (context, cell) {
              return const SizedBox(width: 40.0, height: 50.0);
            },
            itemBuilder:
                itemBuilder ??
                (context, item) {
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

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

class _ClampingBehavior extends ScrollBehavior {
  const _ClampingBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

class _BouncingBehavior extends ScrollBehavior {
  const _BouncingBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics();
  }
}

void main() {

  // The GESTURE'S ITEM is the one the pointer went down on, not the one
  // its element happens to host when the gesture is accepted.
  //
  // The host is deliberately un-keyed, so a rank shift re-keys its
  // widget in place and its `State`, which owns the armed recognizer,
  // survives (`board_widget.dart`, the `_ownedKey` note). A recognizer
  // therefore outlives the identity it was armed for: anything that
  // changes which item occupies a vicinity between the pointer going
  // down and the gesture being accepted used to hand the session a
  // different item, and the app's report then mutated an item the user
  // never touched.
  //
  // The window is `kLongPressTimeout` for the default move wrap and the
  // touch slop for an immediate strip, and the trigger is any add,
  // remove or re-span on the same primary track, which a live board does
  // on its own.
  //
  // Asserts: the pressed item is the dragged one, and the report names
  // it. On unfixed code both cases drag and report the OTHER item.
  testWidgets(
    "a rank shift during the long-press delay keeps the drag on the "
    "pressed item",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("b"),
        const BoardSpan(rowStart: 2, colStart: 3),
      );
      final moves = <String>[];
      await tester.pumpWidget(
        _board(
          controller,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {
              moves.add(key);
              controller.moveItem(key, span);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_itemKey("b"))),
      );
      // Mid-delay, an item that sorts EARLIER on the same row arrives,
      // which shifts b's ordinal and re-keys the element whose `State`
      // holds the armed recognizer.
      await tester.pump(const Duration(milliseconds: 100));
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pump();
      // Setup sanity: the shift really happened.
      expect(controller.vicinityOrdinalOfId(controller.idOfKey("a")), 0);
      expect(controller.vicinityOrdinalOfId(controller.idOfKey("b")), 1);

      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      // TARGET.
      expect(controller.isDragging("b"), isTrue);
      expect(controller.isDragging("a"), isFalse);

      await gesture.moveBy(const Offset(40.0, 0.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(moves, <String>["b"]);
      expect(controller.spanOf("a")!.colStart, 1);
      expect(controller.spanOf("b")!.colStart, 4);
    },
  );

  // The same defect through an IMMEDIATE strip. Its window exists only
  // where the arena is CONTESTED: on a board that scrolls, the strip's
  // recognizer shares the arena with the scrollable's and is accepted on
  // the first move past the slop, so a shift in between lands inside the
  // window. On a board that fits its viewport the strip wins at pointer
  // down and there is no window at all, which is why this case scrolls.
  testWidgets(
    "a rank shift before an immediate strip is accepted keeps the resize "
    "on the pressed item",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("b"),
        const BoardSpan(rowStart: 2, colStart: 3),
      );
      final resizes = <String>[];
      await tester.pumpWidget(
        _board(
          controller,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {},
            onItemResized: (key, span) {
              resizes.add(key);
              controller.resizeItem(key, span);
            },
            resizeEdges: BoardResizeEdges.trailing,
          ),
          // Shorter than its content, so the vertical scrollable
          // contends for the arena.
          height: 200.0,
        ),
      );
      await tester.pumpAndSettle();
      final viewport = _viewport(tester);
      expect(viewport.verticalPosition!.maxScrollExtent, greaterThan(0.0));
      final rect = viewport.rectOfItem("b")!;

      final gesture = await tester.startGesture(
        _global(tester, Offset(rect.right - 3.0, rect.center.dy)),
      );
      await tester.pump();
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pump();
      // Setup sanity: the shift really happened, and it lands before the
      // arena resolves this strip's recognizer, which is what puts the
      // re-key inside the window.
      expect(controller.vicinityOrdinalOfId(controller.idOfKey("b")), 1);

      await gesture.moveBy(const Offset(60.0, 0.0));
      await tester.pump();
      // TARGET.
      expect(controller.isDragging("b"), isTrue);
      expect(controller.isDragging("a"), isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(resizes, <String>["b"]);
    },
  );
  // AC18 drag move.
  // Asserts: onItemMoved called exactly once with the expected BoardSpan;
  // after pumpAndSettle, rectOfItem equals rectOfCell(2, 4).
  testWidgets(
    "dragging an item from (2,1) to (2,4) reports one move and paints at "
    "the new span",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      final moves = <BoardSpan>[];
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moves.add(span);
            controller.moveItem(key, span);
          },
        ),
      );
      final viewport = _viewport(tester);

      // Lift at (2,1)'s center, drop at (2,4)'s center.
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, const Offset(60.0, 125.0)),
        ),
        isTrue,
      );
      drag.updateDrag(_global(tester, const Offset(180.0, 125.0)));
      await tester.pump();
      drag.endDrag(cancel: false);
      await tester.pumpAndSettle();

      expect(moves, hasLength(1));
      expect(moves.single, const BoardSpan(rowStart: 2, colStart: 4));
      expect(
        viewport.rectOfItem("m"),
        viewport.rectOfCell(2, 4),
      );
    },
  );

  // AC19 drag resize.
  // Asserts: onItemResized carries the widened span.
  testWidgets(
    "dragging the trailing edge two tracks outward reports colSpan plus "
    "two",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
      );
      await tester.pumpWidget(_board(controller));
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
          resizeEdges: BoardResizeEdges.trailing,
        ),
      );
      final viewport = _viewport(tester);

      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, const Offset(119.0, 125.0)),
          edge: BoardResizeEdges.trailing,
        ),
        isTrue,
      );
      // The pointer at content x 200 is track-space column 5.0: the new
      // trailing edge, two tracks outward.
      drag.updateDrag(_global(tester, const Offset(200.0, 125.0)));
      await tester.pump();
      drag.endDrag(cancel: false);
      await tester.pumpAndSettle();

      expect(resizes, hasLength(1));
      expect(
        resizes.single,
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 4),
      );
    },
  );

  // AC19 drag resize, the refusal arm.
  // Asserts: no callback fired and the painted rect is unchanged.
  testWidgets("a canDropAt refusal reverts the resize", (tester) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    var reported = 0;
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {
          reported++;
        },
        onItemResized: (key, span) {
          reported++;
        },
        canDropAt: (key, span) {
          return false;
        },
        resizeEdges: BoardResizeEdges.trailing,
      ),
    );
    final viewport = _viewport(tester);
    final before = viewport.rectOfItem("m");

    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(119.0, 125.0)),
        edge: BoardResizeEdges.trailing,
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(200.0, 125.0)));
    await tester.pump();
    drag.endDrag(cancel: false);
    await tester.pumpAndSettle();

    expect(reported, 0);
    expect(viewport.rectOfItem("m"), before);
  });

  // AC21 drop resolves to a cell.
  // Asserts: the committed span's row and column are the cell under the
  // pointer, the new item's laneOf is 3, and every existing lane is
  // unchanged. That no public API asks for a lane is enforced by the
  // surface, not by a runtime assertion.
  testWidgets(
    "a release over a cell holding three items resolves to that cell and "
    "auto-assigns a lane",
    (tester) async {
      final controller = _lanedController(tester);
      for (final key in <String>["a", "b", "c"]) {
        controller.addItem(
          _Item(key),
          const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
        );
      }
      controller.addItem(
        const _Item("n"),
        const BoardSpan(rowStart: 3, colStart: 0, colSpan: 2),
      );
      await tester.pumpWidget(_board(controller));
      final moves = <BoardSpan>[];
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moves.add(span);
            controller.moveItem(key, span);
          },
        ),
      );
      final viewport = _viewport(tester);

      final lift = viewport.rectOfItem("n")!.center;
      expect(
        drag.startDrag(
          key: "n",
          renderPort: viewport,
          pointerGlobal: _global(tester, lift),
        ),
        isTrue,
      );
      // Drop over row 0 column 0, the cluster's cell.
      final target = viewport.rectOfCell(0, 0)!;
      drag.updateDrag(
        _global(
          tester,
          Offset(lift.dx - viewport.rectOfItem("n")!.center.dx + 20.0,
              target.center.dy) +
              (viewport.rectOfItem("n")!.center - lift),
        ),
      );
      // Anchor the item's corner inside cell (0, 0): pointer = grab
      // point translated by the corner delta.
      drag.updateDrag(_global(tester, Offset(lift.dx, target.top + 10.0)));
      await tester.pump();
      drag.endDrag(cancel: false);
      await tester.pumpAndSettle();

      expect(moves, hasLength(1));
      expect(moves.single.rowStart, 0);
      expect(moves.single.colStart, 0);
      expect(controller.laneOf("n"), 3);
      expect(controller.laneOf("a"), 0);
      expect(controller.laneOf("b"), 1);
      expect(controller.laneOf("c"), 2);
    },
  );

  // AC12 a zero makeRoom INSTALLS the gap, the DRAG door: AC18's script
  // with the style zeroed.
  // Asserts: the neighbour's probe is displaced on the frame after the
  // hover and back after the release.
  // Falsification: applying the TRANSIENT refuse rule to makeRoom leaves
  // it at its structural position, which is the whole drop feedback.
  testWidgets("a drag under BoardAnimationStyle.disabled still opens a gap", (
    tester,
  ) async {
    final controller = _lanedController(tester);
    // The cluster's spans are LONGER than the dragged item's, so the
    // second hover's same-start ordering (end descending, then id) can
    // rank d below both.
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
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(onItemMoved: (key, span) {}),
    );
    final viewport = _viewport(tester);
    final restingTop = tester.getRect(find.byKey(_itemKey("a"))).top;

    final lift = viewport.rectOfItem("d")!.center;
    expect(
      drag.startDrag(
        key: "d",
        renderPort: viewport,
        pointerGlobal: _global(tester, lift),
      ),
      isTrue,
    );
    // Hover d over the cluster's row: its span starts EARLIER on the
    // sweep axis, so the dry run hands it lane 0 and displaces both.
    final target = viewport.rectOfCell(0, 0)!;
    drag.updateDrag(_global(tester, Offset(lift.dx, target.top + 10.0)));
    await tester.pump();
    expect(
      tester.getRect(find.byKey(_itemKey("a"))).top,
      restingTop + 18.0,
    );
    // The LIFTED skip arm needs the dry run to hand the dragged item a
    // NON-ZERO lane, which the first hover cannot (an earlier-starting
    // span always takes lane 0, whose content-mode origin never moves):
    // re-target so d's prospective shares the cluster's exact columns,
    // where the id tie-break ranks it last, into lane 2. A MOVE's
    // dragged item paints as the proxy, never as a gap, so its own held
    // offset stays zero regardless.
    drag.updateDrag(
      _global(tester, Offset(lift.dx + 80.0, target.top + 10.0)),
    );
    await tester.pump();
    expect(
      controller.anim.offsetOfItem(controller.idOfKey("d")),
      Offset.zero,
    );

    drag.endDrag(cancel: true);
    await tester.pump();
    expect(tester.getRect(find.byKey(_itemKey("a"))).top, restingTop);
  });

  // DERIVED name. I24's canDropAt-at-RESOLUTION half: a refused target
  // leaves currentTarget null, so no gap previews a drop the commit
  // would refuse. The commit-side re-validation has its own case above.
  // Asserts: hovering an allowed cell sets a target and displaces a
  // neighbour; hovering a refused cell nulls the target and releases
  // the gap.
  testWidgets(
    "hovering a canDropAt-refused cell leaves currentTarget null and no "
    "gap",
    (tester) async {
      final controller = _lanedController(tester);
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
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {},
          canDropAt: (key, span) {
            return span.colStart < 4;
          },
        ),
      );
      final viewport = _viewport(tester);
      final restingTop = tester.getRect(find.byKey(_itemKey("a"))).top;

      final lift = viewport.rectOfItem("d")!.center;
      expect(
        drag.startDrag(
          key: "d",
          renderPort: viewport,
          pointerGlobal: _global(tester, lift),
        ),
        isTrue,
      );
      final target = viewport.rectOfCell(0, 0)!;
      // Allowed hover: corner at (0,0), a displaced.
      drag.updateDrag(_global(tester, Offset(lift.dx, target.top + 10.0)));
      await tester.pump();
      expect(drag.currentTarget, isNotNull);
      expect(
        tester.getRect(find.byKey(_itemKey("a"))).top,
        restingTop + 18.0,
      );
      // Refused hover: corner at (0,4).
      drag.updateDrag(
        _global(tester, Offset(lift.dx + 160.0, target.top + 10.0)),
      );
      await tester.pump();
      expect(drag.currentTarget, isNull);
      expect(tester.getRect(find.byKey(_itemKey("a"))).top, restingTop);

      drag.endDrag(cancel: false);
      await tester.pump();
    },
  );

  // DERIVED name. resolveDropCell's own contract: NEAREST cell by the
  // same rounding as BoardSnap.track's quantize, kept as a public port
  // query now that the move arm resolves from the pointer instead.
  // Asserts: a point at track-space (2.0, 2.6) resolves cell (2, 3),
  // not the containing column 2.
  testWidgets(
    "resolveDropCell answers the nearest cell at track-space 2.6",
    (tester) async {
      final controller = _plainController(tester);
      await tester.pumpWidget(_board(controller));
      expect(
        _viewport(tester).resolveDropCell(const Offset(104.0, 100.0)),
        (row: 2, col: 3),
      );
    },
  );

  // DERIVED name. The track-snap move arm is POINTER-CELL containment: a
  // lane-thin chip dropped low inside a tall cell stays in the cell
  // under the finger, instead of its top corner rounding into the next
  // track.
  // Asserts: with the pointer in row 4's lower half, the commit is
  // row 4.
  testWidgets(
    "a chip dropped low in a cell commits the cell under the pointer",
    (tester) async {
      final controller = _lanedController(tester);
      controller.addItem(
        const _Item("d"),
        const BoardSpan(rowStart: 2, colStart: 0, colSpan: 3),
      );
      await tester.pumpWidget(_board(controller));
      final moves = <BoardSpan>[];
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moves.add(span);
          },
        ),
      );
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
      // Rows measure 50 high; row 4 spans y 200..250. The pointer lands
      // at its 80 percent line, where the chip's thin top corner would
      // round into row 5.
      drag.updateDrag(_global(tester, Offset(lift.dx, 240.0)));
      await tester.pump();
      drag.endDrag(cancel: false);
      await tester.pump();

      expect(moves, hasLength(1));
      expect(moves.single.rowStart, 4);
      expect(moves.single.colStart, 0);
    },
  );

  // DERIVED name. THE RULE REVERSED HERE. This case pinned the old
  // whole-cell grab offset, where the start committed the pointer's
  // cell minus the grabbed cell and item geometry never entered it. A
  // multi-cell item is the shape that made the two rules disagree
  // most, and the coverage below is why the corner now wins: the item
  // paints across x 90 to 210, of which columns 2 to 4 hold 110 pixels
  // and columns 3 to 5 hold 90. What is given up is the grabbed cell
  // staying pinned under the finger; what is bought is a commit the
  // user can see before releasing.
  // Asserts: grabbed in its second column and dragged 50 pixels, the
  // item's start commits column 2.
  testWidgets(
    "a multi-column move commits the placement the item covers",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 3),
      );
      await tester.pumpWidget(_board(controller));
      final moves = <BoardSpan>[];
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moves.add(span);
          },
        ),
      );
      final viewport = _viewport(tester);

      // Lift at (112, 125): inside column 2 (the item's second cell),
      // 32 px past that cell's left edge.
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, const Offset(112.0, 125.0)),
        ),
        isTrue,
      );
      // Pointer to (162, 125), just inside column 4. The corner is at
      // 90, which rounds to column 2; each rejected rule lands on a
      // different in-lattice answer, so this discriminates all three
      // (the old pointer rule gives 3, and a grab offset dropped to
      // zero gives 4).
      drag.updateDrag(_global(tester, const Offset(162.0, 125.0)));
      await tester.pump();
      drag.endDrag(cancel: false);
      await tester.pump();

      expect(moves, hasLength(1));
      expect(
        moves.single,
        const BoardSpan(rowStart: 2, colStart: 2, colSpan: 3),
      );
    },
  );

  // DERIVED name. The fraction route keeps the CORNER rule: continuous
  // snaps place the item's edge, so the anchor stays pointer minus grab
  // and quantizes to the half-track, pointer cell notwithstanding.
  // Asserts: the commit carries colStart 1 with colFraction 0.5.
  testWidgets(
    "a fraction-snap move still places by the quantized corner",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      final moves = <BoardSpan>[];
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moves.add(span);
          },
          snap: const BoardSnap.fraction(0.5),
        ),
      );
      final viewport = _viewport(tester);

      // Lift at the center: grab (20, 25).
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, const Offset(60.0, 125.0)),
        ),
        isTrue,
      );
      // Pointer (84, 125): the corner sits at track-space 1.6, which
      // quantizes to 1.5; the pointer itself is in column 2.
      drag.updateDrag(_global(tester, const Offset(84.0, 125.0)));
      await tester.pump();
      drag.endDrag(cancel: false);
      await tester.pump();

      expect(moves, hasLength(1));
      expect(
        moves.single,
        const BoardSpan(rowStart: 2, colStart: 1, colFraction: 0.5),
      );
    },
  );

  // DERIVED name. The drop-settle glide's CANCEL arm: the proxy was the
  // moved visual, so a cancelled drag glides the item from the proxy's
  // release position back to its resting rect, on the dropSettle family.
  // Asserts: the offset right after endDrag equals proxy minus resting,
  // decays mid-flight, and settles to zero.
  testWidgets(
    "a cancelled move glides back from the proxy's release position",
    (tester) async {
      final controller = _plainController(tester);
      controller.animationStyle = const BoardAnimationStyle(
        trackResize: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
        itemSlide: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
        itemEnterExit: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
        dropSettle: BoardAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      );
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(onItemMoved: (key, span) {}),
      );
      final viewport = _viewport(tester);

      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, const Offset(60.0, 125.0)),
        ),
        isTrue,
      );
      // Proxy top-left at release: (120, 125) minus grab (20, 25) is
      // (100, 100); resting top-left is (40, 100): glide from (60, 0).
      drag.updateDrag(_global(tester, const Offset(120.0, 125.0)));
      await tester.pump();
      drag.endDrag(cancel: true);
      final id = controller.idOfKey("m");
      expect(controller.anim.offsetOfItem(id), const Offset(60.0, 0.0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final mid = controller.anim.offsetOfItem(id).dx;
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(60.0));
      await tester.pumpAndSettle();
      expect(controller.anim.offsetOfItem(id), Offset.zero);
    },
  );

  // DERIVED name. The glide's COMMIT arm: installed AFTER the report, so
  // it OVERRIDES the slide the handler's own moveItem installed, and the
  // item appears to travel from the proxy, not from its old span.
  // Asserts: the offset right after endDrag is proxy minus the NEW rect,
  // not oldRect minus newRect.
  testWidgets(
    "a committed move glides from the proxy, overriding the mutator's "
    "slide",
    (tester) async {
      final controller = _plainController(tester);
      controller.animationStyle = const BoardAnimationStyle(
        trackResize: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
        itemSlide: BoardAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
        itemEnterExit: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
        dropSettle: BoardAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      );
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            controller.moveItem(key, span);
          },
        ),
      );
      final viewport = _viewport(tester);

      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, const Offset(60.0, 125.0)),
        ),
        isTrue,
      );
      // Pointer (150, 125): anchor (130, 100), column track-space 3.25,
      // target (2, 3). New rect top-left (120, 100); proxy (130, 100):
      // the override start is (10, 0), where the mutator's own slide
      // would start at (-80, 0).
      drag.updateDrag(_global(tester, const Offset(150.0, 125.0)));
      await tester.pump();
      drag.endDrag(cancel: false);
      final id = controller.idOfKey("m");
      expect(controller.anim.offsetOfItem(id), const Offset(10.0, 0.0));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(controller.anim.offsetOfItem(id), Offset.zero);
      expect(controller.spanOf("m"), const BoardSpan(rowStart: 2, colStart: 3));
    },
  );

  // AC19 drag resize, the FRACTION case: under BoardSnap.fraction(0.25)
  // a quarter-track trailing drag reports colSpan UNCHANGED with
  // colSpanFraction 0.25; an implementation that rounds the extent up to
  // a whole track fails only here.
  testWidgets(
    "a quarter-track trailing drag under BoardSnap.fraction reports a "
    "fractional extent",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("f"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      final resizes = <BoardSpan>[];
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {},
          onItemResized: (key, span) {
            resizes.add(span);
          },
          resizeEdges: BoardResizeEdges.trailing,
          snap: const BoardSnap.fraction(0.25),
        ),
      );
      final viewport = _viewport(tester);

      expect(
        drag.startDrag(
          key: "f",
          renderPort: viewport,
          pointerGlobal: _global(tester, const Offset(80.0, 125.0)),
          edge: BoardResizeEdges.trailing,
        ),
        isTrue,
      );
      // Edge to content x 90: track-space 2.25, a quarter past the
      // item's whole-track end.
      drag.updateDrag(_global(tester, const Offset(90.0, 125.0)));
      await tester.pump();
      drag.endDrag(cancel: false);
      await tester.pump();

      expect(resizes, hasLength(1));
      expect(
        resizes.single,
        const BoardSpan(
          rowStart: 2,
          colStart: 1,
          colSpanFraction: 0.25,
        ),
      );
    },
  );

  // The resize-driven make-room gap: a trailing-edge resize hovered into
  // overlap displaces the neighbour by one laneExtent, and releasing
  // snaps it clear. One falsification per implementation: a gap
  // installed only for BoardDragKind.move leaves the probe unmoved, and
  // one derived from the hovered CELL displaces nothing, because a
  // trailing-edge resize does not change the hovered cell.
  testWidgets(
    "a trailing-edge resize opens a make-room gap and releasing snaps "
    "it clear",
    (tester) async {
      final controller = _lanedController(tester);
      controller.addItem(
        const _Item("one"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
      );
      controller.addItem(
        const _Item("two"),
        const BoardSpan(rowStart: 0, colStart: 3, colSpan: 2),
      );
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {},
          onItemResized: (key, span) {},
          resizeEdges: BoardResizeEdges.trailing,
        ),
      );
      final viewport = _viewport(tester);
      final restingTop = tester.getRect(find.byKey(_itemKey("two"))).top;
      final edge = viewport.rectOfItem("one")!;

      expect(
        drag.startDrag(
          key: "one",
          renderPort: viewport,
          pointerGlobal: _global(
            tester,
            Offset(edge.right, edge.top + 5.0),
          ),
          edge: BoardResizeEdges.trailing,
        ),
        isTrue,
      );
      // Edge to content x 200: prospective columns [0, 5), overlapping
      // the neighbour's [3, 5). The dry run ranks the earlier start
      // first, so the neighbour takes lane 1.
      drag.updateDrag(
        _global(tester, Offset(200.0, edge.top + 5.0)),
      );
      await tester.pump();
      expect(
        tester.getRect(find.byKey(_itemKey("two"))).top,
        restingTop + 18.0,
      );

      drag.endDrag(cancel: true);
      await tester.pump();
      expect(
        tester.getRect(find.byKey(_itemKey("two"))).top,
        restingTop,
      );
    },
  );

  // The refusal that separates start from commit: a resize this config
  // could not report must refuse at startDrag, not discover the null
  // callback at endDrag.
  testWidgets(
    "a resize with a null onItemResized refuses at startDrag",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      var moved = 0;
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moved++;
          },
          resizeEdges: BoardResizeEdges.trailing,
        ),
      );
      final viewport = _viewport(tester);

      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, const Offset(80.0, 125.0)),
          edge: BoardResizeEdges.trailing,
        ),
        isFalse,
      );
      expect(controller.isDragging("m"), isFalse);
      expect(tester.takeException(), isNull);
      drag.endDrag(cancel: false);
      await tester.pump();
      expect(moved, 0);
    },
  );

  // DERIVED name. The autoscroll EVALUATION at startDrag: a drag that
  // begins with the finger already inside an edge zone must scroll
  // without waiting for the first move event.
  // Asserts: the vertical offset advances across pumped frames with no
  // updateDrag issued.
  testWidgets(
    "a drag started inside the edge zone autoscrolls before any move",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(20, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(_board(controller, vertical: vertical));
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(onItemMoved: (key, span) {}),
      );
      final viewport = _viewport(tester);

      // The finger starts 10 px above the bottom edge, deep inside the
      // 48 px zone.
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, const Offset(60.0, 290.0)),
        ),
        isTrue,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(vertical.offset, greaterThan(0.0));

      drag.endDrag(cancel: true);
      await tester.pumpAndSettle();
    },
  );

  // DERIVED name. The COMMIT handoff: the make-room preview already
  // holds displaced neighbours at their post-drop positions, and the
  // commit's mutation reassigns their structure by the same amounts, so
  // the held offsets must vanish in the same synchronous sequence
  // (snapForCommit) or the two double-count for the length of the
  // release and the neighbour overshoots a lane and glides back.
  // Asserts: the displaced neighbour's painted position is IDENTICAL on
  // the frame after the drop, mid-release-window, and at settle.
  testWidgets(
    "a committed drop leaves displaced neighbours where the preview held "
    "them",
    (tester) async {
      final controller = _lanedController(tester);
      controller.animationStyle = const BoardAnimationStyle(
        trackResize: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
        itemSlide: BoardAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
        itemEnterExit: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
      );
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 2, colSpan: 4),
      );
      controller.addItem(
        const _Item("d"),
        const BoardSpan(rowStart: 2, colStart: 0, colSpan: 3),
      );
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            controller.moveItem(key, span);
          },
        ),
      );
      final viewport = _viewport(tester);
      final resting = tester.getRect(find.byKey(_itemKey("a"))).top;

      final lift = viewport.rectOfItem("d")!.center;
      expect(
        drag.startDrag(
          key: "d",
          renderPort: viewport,
          pointerGlobal: _global(tester, lift),
        ),
        isTrue,
      );
      final target = viewport.rectOfCell(0, 0)!;
      drag.updateDrag(_global(tester, Offset(lift.dx, target.top + 10.0)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final gapHeld = tester.getRect(find.byKey(_itemKey("a"))).top;
      // Setup sanity: the preview displaced the neighbour one lane.
      expect(gapHeld, resting + 18.0);

      drag.endDrag(cancel: false);
      await tester.pump();
      expect(tester.getRect(find.byKey(_itemKey("a"))).top, gapHeld);
      // Mid-release-window: jointly reddened with the frame above by the
      // snap revert (37.0 there). No settled assertion: the settled
      // position is structurally determined and cannot fail.
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getRect(find.byKey(_itemKey("a"))).top, gapHeld);
      await tester.pumpAndSettle();
    },
  );

  // DERIVED name. The commit handoff's RESIZE sibling: the de-lane arm
  // holds the RESIZED item itself at its prospective lane, and the
  // commit's own FLIP slide starts from its old lane origin, so without
  // a painted-truth correction the item jumps back a lane and re-slides
  // to where the preview already had it.
  // Asserts: the resized item's painted position is IDENTICAL on the
  // frame after the drop, mid-window, and at settle.
  testWidgets(
    "a committed resize leaves the de-laned item where the preview held "
    "it",
    (tester) async {
      final controller = _lanedController(tester);
      controller.animationStyle = const BoardAnimationStyle(
        trackResize: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
        itemSlide: BoardAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
        itemEnterExit: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
      );
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 2, colSpan: 2),
      );
      controller.addItem(
        const _Item("b"),
        const BoardSpan(rowStart: 0, colStart: 2, colSpan: 2),
      );
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {},
          onItemResized: (key, span) {
            controller.resizeItem(key, span);
          },
          resizeEdges: BoardResizeEdges.trailing,
        ),
      );
      final viewport = _viewport(tester);

      // Growing b past a re-ranks it into lane 0: the de-lane hold
      // paints b at lane 0 and displaces a to lane 1.
      final edge = viewport.rectOfItem("b")!;
      expect(
        drag.startDrag(
          key: "b",
          renderPort: viewport,
          pointerGlobal: _global(tester, Offset(edge.right, edge.top + 2.0)),
          edge: BoardResizeEdges.trailing,
        ),
        isTrue,
      );
      drag.updateDrag(_global(tester, Offset(240.0, edge.top + 2.0)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final bHeld = tester.getRect(find.byKey(_itemKey("b"))).top;
      final aHeld = tester.getRect(find.byKey(_itemKey("a"))).top;
      // Setup sanity: the two swapped lanes under the hold.
      expect(bHeld, aHeld - 18.0);

      drag.endDrag(cancel: false);
      await tester.pump();
      expect(tester.getRect(find.byKey(_itemKey("b"))).top, bHeld);
      expect(tester.getRect(find.byKey(_itemKey("a"))).top, aHeld);
      // Mid-window: jointly reddened with the frame above by the
      // painted-truth revert (13.0 there). No settled assertion: the
      // settled position is structurally determined and cannot fail.
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getRect(find.byKey(_itemKey("b"))).top, bHeld);
      await tester.pumpAndSettle();
    },
  );

  // DERIVED name. No AC; the first of I24's two halves.
  // Asserts: itemAt over the lifted item's own rect returns null while
  // the drag is live and returns the key again after endDrag.
  testWidgets(
    "itemAt over the lifted item's rect returns null while the drag is "
    "live and the key again after endDrag",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(onItemMoved: (key, span) {}),
      );
      final viewport = _viewport(tester);
      final center = viewport.rectOfItem("m")!.center;
      // Setup sanity.
      expect(viewport.itemAt(center), "m");

      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, center),
        ),
        isTrue,
      );
      await tester.pump();
      expect(viewport.itemAt(center), isNull);

      drag.endDrag(cancel: true);
      await tester.pump();
      expect(viewport.itemAt(center), "m");
    },
  );

  // DERIVED name. No AC; the second of I24's two halves.
  // Asserts: the session is cancelled at the mutation, firing no
  // onItemMoved and throwing nothing.
  testWidgets(
    "a removeItem of the dragged key mid-drag cancels the session at the "
    "mutation",
    (tester) async {
      final controller = _lanedController(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 2, colSpan: 2),
      );
      controller.addItem(
        const _Item("d"),
        const BoardSpan(rowStart: 2, colStart: 0, colSpan: 3),
      );
      await tester.pumpWidget(_board(controller));
      var moved = 0;
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moved++;
          },
        ),
      );
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
      final target = viewport.rectOfCell(0, 0)!;
      drag.updateDrag(_global(tester, Offset(lift.dx, target.top + 10.0)));
      await tester.pump();
      // Setup sanity: the session holds a gap.
      expect(controller.anim.hasActiveOffsets, isTrue);

      controller.removeItem("d");
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(moved, 0);
      expect(drag.draggedKey, isNull);
      expect(controller.anim.hasActiveOffsets, isFalse);
    },
  );

  // DERIVED name. No AC; the first of the handle cases.
  // Asserts: a BoardDragHandle lifts on the pointer-down frame while a
  // BoardDelayedDragHandle in the same board does NOT, and lifts only
  // after kLongPressTimeout.
  testWidgets(
    "a BoardDragHandle lifts on the pointer-down frame while a "
    "BoardDelayedDragHandle does not",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("fast"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
      );
      controller.addItem(
        const _Item("slow"),
        const BoardSpan(rowStart: 3, colStart: 0, colSpan: 2),
      );
      await tester.pumpWidget(
        _board(
          controller,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {},
            buildDefaultDragHandles: false,
          ),
          itemBuilder: (context, item) {
            final child = ColoredBox(
              key: _itemKey(item.key),
              color: const Color(0xFF4CAF50),
            );
            return item.item.key == "fast"
                ? BoardDragHandle(child: child)
                : BoardDelayedDragHandle(child: child);
          },
        ),
      );

      final fastGesture = await tester.startGesture(
        tester.getCenter(find.byKey(_itemKey("fast"))),
      );
      await tester.pump();
      expect(controller.isDragging("fast"), isTrue);
      await fastGesture.up();
      await tester.pumpAndSettle();
      expect(controller.isDragging("fast"), isFalse);

      final slowGesture = await tester.startGesture(
        tester.getCenter(find.byKey(_itemKey("slow"))),
      );
      await tester.pump();
      expect(controller.isDragging("slow"), isFalse);
      await tester.pump(kLongPressTimeout + kPressTimeout);
      expect(controller.isDragging("slow"), isTrue);
      await slowGesture.up();
      await tester.pumpAndSettle();
    },
  );

  // DERIVED name. No AC; the second handle case: the handle-to-updateDrag
  // route end to end.
  // Asserts: pointer down on the handle, moves, up, and onItemMoved
  // reports the span the scripted drag in AC18 reports.
  // DERIVED name. The default resize strips as an INPUT PATH: the plan's
  // handle block requires one resize handle per accepted kind, and every
  // other AC19 case drives startDrag(edge:) directly, so only this case
  // fails if the strips never enter a hit test.
  // Asserts: a plain pointer drag on the trailing strip reports exactly
  // one resize with the grown span.
  testWidgets(
    "a pointer drag on the default trailing strip reports a resize",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("r"),
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
      );
      final resizes = <BoardSpan>[];
      await tester.pumpWidget(
        _board(
          controller,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {},
            onItemResized: (key, span) {
              resizes.add(span);
            },
            resizeEdges: BoardResizeEdges.trailing,
          ),
        ),
      );

      // The item spans columns 1..3: x 40..120, y 100..150. The trailing
      // strip is the right-edge band, 12 wide.
      final gesture = await tester.startGesture(
        _global(tester, const Offset(114.0, 125.0)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(40.0, 0.0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(resizes, hasLength(1));
      expect(
        resizes.single,
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 3),
      );
    },
  );

  testWidgets("a full move driven through the handle reports the same span", (
    tester,
  ) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    final moves = <BoardSpan>[];
    await tester.pumpWidget(
      _board(
        controller,
        drag: BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moves.add(span);
            controller.moveItem(key, span);
          },
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_itemKey("m"))),
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    // Setup sanity: the default delayed handle lifted.
    expect(controller.isDragging("m"), isTrue);
    await gesture.moveTo(_global(tester, const Offset(180.0, 125.0)));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(moves, hasLength(1));
    expect(moves.single, const BoardSpan(rowStart: 2, colStart: 4));
  });

  // DERIVED name. No AC; the recognizer's replacement leg, which the
  // board needs because resizeEdges plus buildDefaultDragHandles makes
  // two handles on one item the DEFAULT.
  // Asserts: pressing the move handle and then, without releasing,
  // pressing a resize handle on the same item fires no onItemMoved and
  // leaves isDragging false after both pointers lift.
  testWidgets(
    "pressing a resize handle without releasing the move handle fires no "
    "onItemMoved",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
      );
      var moved = 0;
      await tester.pumpWidget(
        _board(
          controller,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {
              moved++;
            },
            onItemResized: (key, span) {},
            resizeEdges: BoardResizeEdges.trailing,
          ),
        ),
      );

      final rect = tester.getRect(find.byKey(_itemKey("m")));
      final moveGesture = await tester.startGesture(rect.center);
      await tester.pump();
      // The second pointer, on the trailing resize strip.
      final resizeGesture = await tester.startGesture(
        Offset(rect.right - 4.0, rect.center.dy),
      );
      await tester.pump();
      await moveGesture.up();
      await resizeGesture.up();
      await tester.pumpAndSettle();

      expect(moved, 0);
      expect(controller.isDragging("m"), isFalse);
    },
  );

  // DERIVED name. Replacement leg ONE: the sibling case above replaces
  // the recognizer before any session exists; this one replaces it with a
  // session LIVE (the long press elapsed), which is the state that wedges
  // if the replacement only disposes.
  // Asserts: after the replacement and both lifts, the session is gone
  // (isDragging false) and nothing was reported.
  testWidgets(
    "replacing the recognizer mid-session cancels the session it owned",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
      );
      var moved = 0;
      await tester.pumpWidget(
        _board(
          controller,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {
              moved++;
            },
            onItemResized: (key, span) {},
            resizeEdges: BoardResizeEdges.trailing,
          ),
        ),
      );

      final rect = tester.getRect(find.byKey(_itemKey("m")));
      final moveGesture = await tester.startGesture(rect.center);
      // Past the delayed handle's long-press: the session is LIVE.
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      expect(controller.isDragging("m"), isTrue);

      final resizeGesture = await tester.startGesture(
        Offset(rect.right - 4.0, rect.center.dy),
      );
      await tester.pump();
      await moveGesture.up();
      await resizeGesture.up();
      await tester.pumpAndSettle();

      expect(moved, 0);
      expect(controller.isDragging("m"), isFalse);
    },
  );

  // DERIVED name. The deactivate backstop's DISCRIMINATING case: the
  // host state that owns the session leaves the tree while the Board
  // survives. The un-keyed host means an ordinal shift re-keys the
  // owner's widget in place, so the ownership record must be the key the
  // session STARTED with, not the widget's current one.
  // Asserts: after the owner unmounts, the session is cancelled rather
  // than wedged.
  testWidgets(
    "the session owner's host unmounting mid-drag cancels the session",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(20, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 0, colStart: 1),
      );
      var moved = 0;
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        _board(
          controller,
          vertical: vertical,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {
              moved++;
            },
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getRect(find.byKey(_itemKey("m"))).center,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      expect(controller.isDragging("m"), isTrue);

      // The rank insert re-keys the owner's vicinity: its element now
      // hosts the new item while the session stays on the dragged one.
      controller.addItem(
        const _Item("q"),
        const BoardSpan(rowStart: 0, colStart: 0),
      );
      await tester.pump();
      // Scrolling the new item's span out unmounts the owner's element;
      // the dragged item itself stays mounted through the pin.
      vertical.jumpTo(600.0);
      await tester.pump();
      await tester.pump();

      expect(controller.isDragging("m"), isFalse);
      expect(moved, 0);
      expect(tester.takeException(), isNull);
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  // DERIVED name. No AC; the recognizer's null-return leg.
  // Asserts: a canDrag that refuses leaves takeException null and fires
  // nothing on the subsequent pointer-up.
  testWidgets(
    "a canDrag refusal throws nothing and fires nothing on the "
    "pointer-up",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      var fired = 0;
      await tester.pumpWidget(
        _board(
          controller,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {
              fired++;
            },
            canDrag: (key) {
              return false;
            },
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_itemKey("m"))),
      );
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await gesture.moveBy(const Offset(60.0, 0.0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(fired, 0);
      expect(controller.isDragging("m"), isFalse);
    },
  );

  // DERIVED name. No AC; THE PIN, the first half of the mid-drag unmount
  // rule.
  // Asserts: start a drag, scroll BOTH axes until the item's span is well
  // outside the built window, and the item's probe is still findable,
  // draggedKey still the key, and a subsequent updateDrag plus endDrag
  // still reports onItemMoved exactly once.
  // Falsification: without pinItem the child is unmounted by the
  // ordinary window check, its State goes with it, and the report never
  // happens.
  testWidgets(
    "a dragged item stays findable after both axes scroll its span out "
    "of the window",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(60, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(30, 40.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 0, colStart: 0),
      );
      final vertical = ScrollController();
      final horizontal = ScrollController();
      addTearDown(vertical.dispose);
      addTearDown(horizontal.dispose);
      final moves = <BoardSpan>[];
      await tester.pumpWidget(
        _board(
          controller,
          vertical: vertical,
          horizontal: horizontal,
          height: 200.0,
        ),
      );
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moves.add(span);
          },
        ),
      );
      final viewport = _viewport(tester);
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, const Offset(20.0, 25.0)),
        ),
        isTrue,
      );
      await tester.pump();

      vertical.jumpTo(2000.0);
      horizontal.jumpTo(600.0);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(_itemKey("m"), skipOffstage: false),
        findsOneWidget,
      );
      expect(drag.draggedKey, "m");

      // The finger is still inside the (scrolled) viewport; a resolve
      // and a commit still work.
      drag.updateDrag(_global(tester, const Offset(100.0, 100.0)));
      await tester.pump();
      drag.endDrag(cancel: false);
      await tester.pumpAndSettle();
      expect(moves, hasLength(1));
    },
  );

  // DERIVED name. No AC; THE BACKSTOP, where the pin cannot help because
  // there is no render object left.
  // Asserts: after one further pump, isDragging is false, no onItemMoved
  // fired, takeException is null, and hasActiveOffsets is false, which
  // is the make-room gap having been released.
  testWidgets(
    "replacing the Board with a SizedBox mid-drag cancels the session "
    "and releases the gap",
    (tester) async {
      final controller = _lanedController(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 2, colSpan: 2),
      );
      controller.addItem(
        const _Item("d"),
        const BoardSpan(rowStart: 2, colStart: 0, colSpan: 3),
      );
      var moved = 0;
      await tester.pumpWidget(
        _board(
          controller,
          drag: BoardDragConfig<String>(
            onItemMoved: (key, span) {
              moved++;
            },
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_itemKey("d"))),
      );
      await tester.pump(kLongPressTimeout + kPressTimeout);
      expect(controller.isDragging("d"), isTrue);
      final target = _viewport(tester).rectOfCell(0, 0)!;
      await gesture.moveTo(_global(tester, Offset(60.0, target.top + 10.0)));
      await tester.pump();
      expect(controller.anim.hasActiveOffsets, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.isDragging("d"), isFalse);
      expect(moved, 0);
      expect(controller.anim.hasActiveOffsets, isFalse);
      await gesture.up();
    },
  );

  // DERIVED name. No AC; the BIND leg of the scroll-subscription triple.
  // Asserts: one updateDrag parks the pointer inside the vertical
  // autoscroll edge zone, then pump frames with NO further pointer
  // event; currentTarget advances by at least one row across those pumps
  // and endDrag reports the cell now under the stationary finger.
  // Falsification: an autoscroll tick with no subscription scrolls the
  // lattice and leaves both on the pre-scroll cell.
  testWidgets(
    "a pointer parked in the autoscroll edge zone advances currentTarget "
    "with no further pointer event",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(60, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 0, colStart: 0),
      );
      final moves = <BoardSpan>[];
      await tester.pumpWidget(_board(controller, height: 200.0));
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {
            moves.add(span);
          },
        ),
      );
      final viewport = _viewport(tester);
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, const Offset(20.0, 25.0)),
        ),
        isTrue,
      );
      // Park inside the bottom edge zone (48 of 200).
      drag.updateDrag(_global(tester, const Offset(20.0, 190.0)));
      await tester.pump();
      final parked = drag.currentTarget!.span.rowStart;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final advanced = drag.currentTarget!.span.rowStart;
      expect(advanced, greaterThan(parked));

      drag.endDrag(cancel: false);
      await tester.pumpAndSettle();
      expect(moves, hasLength(1));
      expect(moves.single.rowStart, advanced);
    },
  );

  // DERIVED name. No AC; the RE-POINT leg.
  // Asserts: the BIND script, with a ScrollConfiguration whose behavior
  // has a different runtimeType swapped in between two batches of pumps,
  // which is what replaces both ScrollPositions; currentTarget keeps
  // advancing across the SECOND batch.
  // Falsification: a bind-only implementation holds its listener on the
  // disposed position and freezes from the swap onward.
  testWidgets("a swapped ScrollPosition keeps currentTarget advancing", (
    tester,
  ) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(120, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 0, colStart: 0),
    );
    // Two behaviors whose PHYSICS differ, which is what actually makes
    // the scrollable recreate its positions, and the configuration sits
    // INSIDE the MaterialApp, whose own scroll configuration otherwise
    // overrides it; two earlier versions of this fixture swapped
    // nothing, one for each of those reasons.
    Widget wrapped(ScrollBehavior behavior) {
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: _frameKey,
              width: 280.0,
              height: 200.0,
              child: ScrollConfiguration(
                behavior: behavior,
                child: Board<String, _Item>(
                  controller: controller,
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
        ),
      );
    }

    await tester.pumpWidget(wrapped(const _ClampingBehavior()));
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(onItemMoved: (key, span) {}),
    );
    final viewport = _viewport(tester);
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(20.0, 25.0)),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(20.0, 190.0)));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final beforeSwap = drag.currentTarget!.span.rowStart;

    await tester.pumpWidget(wrapped(const _BouncingBehavior()));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final afterSwap = drag.currentTarget!.span.rowStart;
    expect(afterSwap, greaterThan(beforeSwap));

    drag.endDrag(cancel: true);
    await tester.pumpAndSettle();
  });

  // DERIVED name. No AC; the UNBIND leg. One exit reason is enough
  // because the unbind lives in the SINGLE teardown with no branch on
  // the reason.
  // Asserts: after endDrag and settling, a direct jumpTo far enough that
  // a different row sits under the last reported position drives no
  // resolve: takeException null, currentTarget null, hasActiveOffsets
  // false, and an animation-channel counter registered before the jump
  // counted zero fires.
  testWidgets("a jumpTo after the drag ended drives no resolve", (
    tester,
  ) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(60, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 0, colStart: 0),
    );
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      _board(controller, vertical: vertical, height: 200.0),
    );
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(onItemMoved: (key, span) {}),
    );
    final viewport = _viewport(tester);
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(20.0, 25.0)),
      ),
      isTrue,
    );
    // Parked OUTSIDE both edge zones.
    drag.updateDrag(_global(tester, const Offset(100.0, 100.0)));
    await tester.pump();
    drag.endDrag(cancel: false);
    await tester.pumpAndSettle();

    var animationFires = 0;
    void counter() {
      animationFires++;
    }

    controller.addAnimationListener(counter);
    addTearDown(() {
      controller.removeAnimationListener(counter);
    });
    vertical.jumpTo(1500.0);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(drag.currentTarget, isNull);
    expect(controller.anim.hasActiveOffsets, isFalse);
    expect(animationFires, 0);
  });

  // DERIVED name. No AC; the COMMIT SCRIPT's order, which the AC18 case
  // cannot see because its handler's mutation succeeding is already the
  // point there.
  // Asserts: an onItemMoved handler that calls moveItem on the dragged
  // key ran exactly once, takeException is null and the item ends at the
  // new span.
  // Falsification: reporting BEFORE clearing the dragging bit fires the
  // mutation-cancel hook from inside the commit and tears the session
  // down twice.
  testWidgets("an onItemMoved handler that mutates the dragged key runs "
      "exactly once", (tester) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    await tester.pumpWidget(_board(controller));
    var handlerRuns = 0;
    late BoardDragController<String> drag;
    drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {
          handlerRuns++;
          controller.moveItem(key, span);
        },
      ),
    );
    final viewport = _viewport(tester);
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(60.0, 125.0)),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(180.0, 125.0)));
    await tester.pump();
    drag.endDrag(cancel: false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(handlerRuns, 1);
    expect(
      controller.spanOf("m"),
      const BoardSpan(rowStart: 2, colStart: 4),
    );
  });

  // Source: plans/2026-09-04-board-drag-policy-and-proxy-plan.md, T7.
  // The proxy is the moved visual for a MOVE session and must follow the
  // pointer whether or not a target exists; a canDropAt refusal nulls the
  // target while the session stays live.
  // Asserts: two widgets carry the item's key over an allowed cell (in
  // place plus proxy, the setup sanity) and still two over a refused one.
  // On unfixed code the second count is one.
  testWidgets("the proxy follows the pointer across a canDropAt-refused cell", (
    tester,
  ) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("d"),
      const BoardSpan(rowStart: 2, colStart: 0),
    );
    await tester.pumpWidget(
      _board(
        controller,
        drag: BoardDragConfig<String>(
          onItemMoved: (key, span) {},
          canDropAt: (key, span) {
            return span.colStart < 4;
          },
        ),
      ),
    );
    final item = find.byKey(_itemKey("d"));
    final center = tester.getCenter(item);
    final gesture = await tester.startGesture(center);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    // Allowed: col 1.
    await gesture.moveTo(center + const Offset(40.0, 0.0));
    await tester.pump();
    expect(item, findsNWidgets(2));
    // Refused: col 5.
    await gesture.moveTo(center + const Offset(200.0, 0.0));
    await tester.pump();
    expect(item, findsNWidgets(2));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  // Source: plans/2026-09-04-board-drag-policy-and-proxy-plan.md, T8.
  // Asserts: draggedKind is null between sessions, names a move session
  // and a trailing-edge resize session, and is null again after endDrag.
  // On unfixed code this does not compile.
  testWidgets("draggedKind is null between sessions and names the session's kind", (
    tester,
  ) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {},
        onItemResized: (key, span) {},
        resizeEdges: BoardResizeEdges.trailing,
      ),
    );
    final viewport = _viewport(tester);
    expect(drag.draggedKind, isNull);
    final rect = viewport.rectOfItem("m")!;
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, rect.center),
      ),
      isTrue,
    );
    expect(drag.draggedKind, BoardDragKind.move);
    drag.endDrag(cancel: true);
    await tester.pump();
    expect(drag.draggedKind, isNull);
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, Offset(rect.right - 1.0, rect.center.dy)),
        edge: BoardResizeEdges.trailing,
      ),
      isTrue,
    );
    expect(drag.draggedKind, BoardDragKind.resizeColEnd);
    drag.endDrag(cancel: true);
    await tester.pump();
    expect(drag.draggedKind, isNull);
  });

  // THE COMMITTED PLACEMENT IS THE ONE THE ITEM COVERS, not the one the
  // pointer's cell names.
  //
  // A whole-track move used to floor the pointer's track and subtract a
  // grab cell floored at lift. Two floors of the same continuous
  // quantity differ by one depending on where inside a cell the item was
  // grabbed, so the placement flipped when the POINTER crossed a cell
  // boundary while the item itself had barely moved.
  //
  // Columns are 40 wide, so column 2 spans x 80 to 120 and the item
  // below spans columns 2 and 3, x 80 to 160. Grabbing at x 115 puts the
  // finger 35 into the item and 5 short of column 3's boundary.
  //
  // Asserts: a 10 pixel drag, which leaves the item covering 70 of its
  // 80 pixels over columns 2 and 3, commits columns 2 and 3. On unfixed
  // code it commits columns 3 and 4, which cover 50.
  testWidgets(
    "a whole-track move commits the columns the item covers, not the "
    "pointer's",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 2, colSpan: 2),
      );
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(onItemMoved: (key, span) {}),
      );
      final viewport = _viewport(tester);
      // Setup sanity: the item is where the arithmetic above assumes.
      expect(viewport.rectOfItem("m")!.left, 80.0);
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, const Offset(115.0, 125.0)),
        ),
        isTrue,
      );
      drag.updateDrag(_global(tester, const Offset(125.0, 125.0)));
      await tester.pump();
      // TARGET: the corner sits at 90, which rounds to track 2.
      expect(drag.currentTarget!.span.colStart, 2);

      // And it DOES advance once the item's body passes the halfway
      // line: a corner at 110 rounds to track 3. This fails for a rule
      // that pins the placement to the lift column.
      drag.updateDrag(_global(tester, const Offset(145.0, 125.0)));
      await tester.pump();
      expect(drag.currentTarget!.span.colStart, 3);

      drag.endDrag(cancel: true);
      await tester.pump();
    },
  );

  // THE NUDGE. A refused move whose box mostly misses the occupant it
  // meets slides onto the nearest placement that holds the whole box.
  //
  // The item spans columns 0 and 1 of row 2; an occupant sits at column
  // 3; the predicate refuses any span meeting another item. Dropping the
  // item's corner on column 2 leaves it covering columns 2 and 3, half
  // of it free, so the gate admits and the scan takes the nearest
  // placement that fits, columns 1 and 2, one column away at 40 pixels
  // against the 50 a row step would cost.
  //
  // Asserts: with the policy the commit is column 1, and the same drag
  // with a null policy reports nothing at all, which is where G2 is
  // pinned.
  testWidgets(
    "a move mostly over free cells slides clear of the occupant",
    (tester) async {
      Future<List<BoardSpan>> runDrag({required bool withPolicy}) async {
        final controller = _plainController(tester);
        controller.addItem(
          const _Item("m"),
          const BoardSpan(rowStart: 2, colStart: 0, colSpan: 2),
        );
        controller.addItem(
          const _Item("o"),
          const BoardSpan(rowStart: 2, colStart: 3),
        );
        await tester.pumpWidget(_board(controller));
        final moves = <BoardSpan>[];
        final drag = _drag(
          tester,
          controller,
          BoardDragConfig<String>(
            onItemMoved: (key, span) {
              moves.add(span);
            },
            canDropAt: (key, span) {
              for (final other in controller.itemsIn(
                span.rowStart,
                span.rowStart + span.rowSpan,
                span.colStart,
                span.colStart + span.colSpan,
              )) {
                if (other != key) {
                  return false;
                }
              }
              return true;
            },
            dropFit: withPolicy ? const BoardDropFit() : null,
          ),
        );
        final viewport = _viewport(tester);
        expect(
          drag.startDrag(
            key: "m",
            renderPort: viewport,
            pointerGlobal: _global(tester, const Offset(40.0, 125.0)),
          ),
          isTrue,
        );
        drag.updateDrag(_global(tester, const Offset(120.0, 125.0)));
        await tester.pump();
        drag.endDrag(cancel: false);
        await tester.pump();
        return moves;
      }

      final nudged = await runDrag(withPolicy: true);
      expect(nudged, hasLength(1));
      expect(nudged.single.colStart, 1);
      expect(nudged.single.rowStart, 2);

      final refused = await runDrag(withPolicy: false);
      expect(refused, isEmpty);
    },
  );

  // The GATE's second term, which measures the REGION rather than the
  // box: a drop into a crowded neighbourhood gets no help, because the
  // free share of the area around it is a third and the policy asks for
  // a half. The occupant covers six of the nine cells the search region
  // spans, and it covers the box's own cell, so the first term holds and
  // the second is what refuses.
  //
  // It fails for an implementation that drops the second term, and it
  // fails for the box-share measure this replaced, which saw a wholly
  // covered box and refused for the wrong reason.
  testWidgets("a move into a crowded region is still refused", (
    tester,
  ) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 0),
    );
    controller.addItem(
      const _Item("o"),
      const BoardSpan(rowStart: 1, colStart: 1, rowSpan: 3, colSpan: 2),
    );
    await tester.pumpWidget(_board(controller));
    final moves = <BoardSpan>[];
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {
          moves.add(span);
        },
        canDropAt: (key, span) {
          for (final other in controller.itemsIn(
            span.rowStart,
            span.rowStart + span.rowSpan,
            span.colStart,
            span.colStart + span.colSpan,
          )) {
            if (other != key) {
              return false;
            }
          }
          return true;
        },
        dropFit: const BoardDropFit(),
      ),
    );
    final viewport = _viewport(tester);
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(20.0, 125.0)),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(100.0, 125.0)));
    await tester.pump();
    expect(drag.currentTarget, isNull);
    drag.endDrag(cancel: false);
    await tester.pump();
    expect(moves, isEmpty);
  });

  // THE SHAPE THE FEATURE SHIPPED BROKEN FOR. A single-cell item on a
  // whole-track board is either entirely on an occupant or entirely off
  // it, so the box-share measure this replaced could never land between
  // its threshold and 1 and the nudge was unreachable for the commonest
  // board there is. The region's free share is eight ninths here, so the
  // gate admits and the scan takes the nearer of the two free columns
  // beside the occupant, which the total order settles as the left one.
  //
  // Asserts: the drop commits column 1. On the box-share measure nothing
  // is reported at all.
  testWidgets("a single-cell move onto an occupied cell slides beside it", (
    tester,
  ) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 0),
    );
    controller.addItem(
      const _Item("o"),
      const BoardSpan(rowStart: 2, colStart: 2),
    );
    await tester.pumpWidget(_board(controller));
    final moves = <BoardSpan>[];
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {
          moves.add(span);
        },
        canDropAt: (key, span) {
          for (final other in controller.itemsIn(
            span.rowStart,
            span.rowStart + span.rowSpan,
            span.colStart,
            span.colStart + span.colSpan,
          )) {
            if (other != key) {
              return false;
            }
          }
          return true;
        },
        dropFit: const BoardDropFit(),
      ),
    );
    final viewport = _viewport(tester);
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(20.0, 125.0)),
      ),
      isTrue,
    );
    // Corner onto column 2, which "o" occupies outright.
    drag.updateDrag(_global(tester, const Offset(100.0, 125.0)));
    await tester.pump();
    expect(drag.currentTarget!.span.colStart, 1);
    drag.endDrag(cancel: false);
    await tester.pump();
    expect(moves, hasLength(1));
    expect(moves.single.colStart, 1);
    expect(moves.single.rowStart, 2);
  });

  // The nudged placement is the TARGET, not just the commit, so the gap
  // previews where the item will land before the finger lifts.
  testWidgets("the preview shows the nudged placement", (tester) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 0, colSpan: 2),
    );
    controller.addItem(
      const _Item("o"),
      const BoardSpan(rowStart: 2, colStart: 3),
    );
    await tester.pumpWidget(_board(controller));
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {},
        canDropAt: (key, span) {
          for (final other in controller.itemsIn(
            span.rowStart,
            span.rowStart + span.rowSpan,
            span.colStart,
            span.colStart + span.colSpan,
          )) {
            if (other != key) {
              return false;
            }
          }
          return true;
        },
        dropFit: const BoardDropFit(),
      ),
    );
    final viewport = _viewport(tester);
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(40.0, 125.0)),
      ),
      isTrue,
    );
    drag.updateDrag(_global(tester, const Offset(120.0, 125.0)));
    await tester.pump();
    // TARGET: the nudged span, not the resolved column 2.
    expect(drag.currentTarget, isNotNull);
    expect(drag.currentTarget!.span.colStart, 1);
    drag.endDrag(cancel: true);
    await tester.pump();
  });

  // The GATE's FIRST term, which no other case reaches. The predicate
  // blocks column 2 for a reason of its own, with nothing occupying it,
  // and admits column 1 and column 3. A one-term gate would see a box
  // that is entirely free, scan, and report a neighbour; the first term
  // is what keeps this feature to overlaps.
  testWidgets("a refusal that is not an overlap moves nothing", (
    tester,
  ) async {
    final controller = _plainController(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 0),
    );
    await tester.pumpWidget(_board(controller));
    final moves = <BoardSpan>[];
    final drag = _drag(
      tester,
      controller,
      BoardDragConfig<String>(
        onItemMoved: (key, span) {
          moves.add(span);
        },
        canDropAt: (key, span) {
          return span.colStart != 2;
        },
        dropFit: const BoardDropFit(),
      ),
    );
    final viewport = _viewport(tester);
    expect(
      drag.startDrag(
        key: "m",
        renderPort: viewport,
        pointerGlobal: _global(tester, const Offset(20.0, 125.0)),
      ),
      isTrue,
    );
    // Corner on column 2, which is empty and which the predicate blocks.
    drag.updateDrag(_global(tester, const Offset(100.0, 125.0)));
    await tester.pump();
    expect(drag.currentTarget, isNull);
    drag.endDrag(cancel: false);
    await tester.pump();
    expect(moves, isEmpty);
  });

  // The early-out field. With a nudge standing, the resolver's answer
  // and the current target are different spans by construction, so
  // without the field every later move would re-run the gate, the scan
  // and a notification for a pointer that has not left its placement.
  // The seam is the controller's own ChangeNotifier.
  testWidgets(
    "a pointer that has not left its resolved placement re-resolves "
    "nothing",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 0, colSpan: 2),
      );
      controller.addItem(
        const _Item("o"),
        const BoardSpan(rowStart: 2, colStart: 3),
      );
      await tester.pumpWidget(_board(controller));
      final drag = _drag(
        tester,
        controller,
        BoardDragConfig<String>(
          onItemMoved: (key, span) {},
          canDropAt: (key, span) {
            for (final other in controller.itemsIn(
              span.rowStart,
              span.rowStart + span.rowSpan,
              span.colStart,
              span.colStart + span.colSpan,
            )) {
              if (other != key) {
                return false;
              }
            }
            return true;
          },
          dropFit: const BoardDropFit(),
        ),
      );
      final viewport = _viewport(tester);
      expect(
        drag.startDrag(
          key: "m",
          renderPort: viewport,
          pointerGlobal: _global(tester, const Offset(40.0, 125.0)),
        ),
        isTrue,
      );
      drag.updateDrag(_global(tester, const Offset(120.0, 125.0)));
      await tester.pump();
      // Setup sanity: the nudge is standing, so the target and the
      // resolver's answer are different spans.
      expect(drag.currentTarget!.span.colStart, 1);

      var notifications = 0;
      void count() {
        notifications += 1;
      }

      drag.addListener(count);
      // Three moves that all round to the same column and row.
      for (final dx in <double>[5.0, 10.0, 15.0]) {
        drag.updateDrag(_global(tester, Offset(120.0 + dx, 125.0)));
        await tester.pump();
      }
      drag.removeListener(count);
      expect(notifications, 0);

      drag.endDrag(cancel: true);
      await tester.pump();
    },
  );

  // Performance plan 2 T8 (plans/2026-09-09-board-performance-2-plan.md).
  // Asserts: pointer moves inside one session do not rebuild `Board`,
  // and the two session EDGES do.
  //
  // The probe is the scrollable's widget instance:
  // `TwoDimensionalScrollView.build` constructs a new
  // `TwoDimensionalScrollable` on every build
  // (`widgets/two_dimensional_scroll_view.dart:197`), so an unchanged
  // instance is a build that did not happen. A FREE snap is the input
  // that makes this bite: it quantizes nothing, so every move resolves a
  // new span and notifies.
  // Falsification: the unconditional setState on every drag
  // notification replaces the instance on the first move.
  testWidgets(
    "pointer moves inside a free-snap session keep the scrollable widget "
    "instance",
    (tester) async {
      final controller = _plainController(tester);
      controller.addItem(
        const _Item("m"),
        const BoardSpan(rowStart: 2, colStart: 1),
      );
      await tester.pumpWidget(
        _board(
          controller,
          drag: BoardDragConfig<String>(
            snap: const BoardSnap.free(),
            onItemMoved: (key, span) {},
          ),
        ),
      );
      TwoDimensionalScrollable scrollable() {
        return tester.widget<TwoDimensionalScrollable>(
          find.byType(TwoDimensionalScrollable),
        );
      }

      final beforeLift = scrollable();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_itemKey("m"))),
      );
      await tester.pump(kLongPressTimeout + kPressTimeout);
      // Setup sanity: the session started, and starting it DID rebuild,
      // which is what makes the unchanged instance below meaningful.
      expect(controller.isDragging("m"), isTrue);
      final afterLift = scrollable();
      expect(identical(afterLift, beforeLift), isFalse);

      // Three moves, each resolving a different span under a free snap.
      final drag = tester.state<State<Board<String, _Item>>>(
        find.byType(Board<String, _Item>),
      );
      expect(drag.mounted, isTrue);
      for (final dx in <double>[6.0, 13.0, 21.0]) {
        await gesture.moveTo(
          _global(tester, Offset(150.0 + dx, 125.0 + dx)),
        );
        await tester.pump();
      }
      expect(identical(scrollable(), afterLift), isTrue);

      // The other edge rebuilds.
      await gesture.up();
      await tester.pumpAndSettle();
      expect(identical(scrollable(), afterLift), isFalse);
    },
  );

  // Performance plan 2 T12.
  // Asserts: a frame in which the slide engine and the make-room engine
  // BOTH tick dispatches the animation channel once, not once per
  // engine. Their per-tick notify used to be the uncoalesced one, which
  // the settle protocol needs and an ordinary tick does not, so every
  // listener ran twice a frame and the render object re-ran its router
  // scans twice.
  // Falsification: the uncoalesced per-tick dispatch reports 2.
  testWidgets(
    "a frame in which a slide and the make-room gap both tick dispatches "
    "once",
    (tester) async {
      final controller = _lanedController(tester);
      controller
        ..addItem(
          const _Item("m"),
          const BoardSpan(rowStart: 1, colStart: 0, colSpan: 2),
        )
        ..addItem(
          const _Item("n"),
          const BoardSpan(rowStart: 1, colStart: 2, colSpan: 2),
        )
        ..addItem(
          const _Item("far"),
          const BoardSpan(rowStart: 4, colStart: 0, colSpan: 2),
        );
      await tester.pumpWidget(
        _board(
          controller,
          drag: BoardDragConfig<String>(onItemMoved: (key, span) {}),
        ),
      );
      // Both families live, so both engines can hold a record at once.
      controller.animationStyle = const BoardAnimationStyle(
        itemSlide: BoardAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
        makeRoom: BoardAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
        trackResize: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
        itemEnterExit: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
      );

      // A gap, opened by a live session hovering over the other chip.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_itemKey("m"))),
      );
      await tester.pump(kLongPressTimeout + kPressTimeout);
      expect(controller.isDragging("m"), isTrue);
      await gesture.moveTo(_global(tester, const Offset(110.0, 95.0)));
      await tester.pump();

      // And a slide, installed on an item the session does not hold.
      controller.moveItem(
        "far",
        const BoardSpan(rowStart: 5, colStart: 0, colSpan: 2),
      );
      await tester.pump(const Duration(milliseconds: 16));

      // Setup sanity: BOTH engines really are mid-flight, so the frame
      // measured below is one in which both tick.
      expect(controller.anim.hasActiveOffsets, isTrue);
      expect(controller.anim.hasMakeRoomMotion, isTrue);

      var dispatches = 0;
      void counter() {
        dispatches += 1;
      }

      controller.addAnimationListener(counter);
      await tester.pump(const Duration(milliseconds: 16));
      controller.removeAnimationListener(counter);

      expect(dispatches, 1);

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );
}
