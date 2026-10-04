/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 10 with the scroll orchestrator.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

Key _cellKey(int row, int col) {
  return ValueKey<String>("c${row}_$col");
}

Widget _board(BoardController<String, _Item> controller) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: _frameKey,
          width: 300.0,
          height: 200.0,
          child: Board<String, _Item>(
            controller: controller,
            cellBuilder: (context, cell) {
              return SizedBox(
                key: _cellKey(cell.row, cell.col),
                width: 100.0,
                height: 20.0,
              );
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  // AC9 frozen-aware landing.
  // Asserts: the target cell's painted top is at least
  // frozenInsetOf(Axis.vertical), and the returned future completes true.
  // Falsification: the avoidFrozenTracks: false arm lands it under the
  // band.
  testWidgets(
    "animateScrollToCell with avoidFrozenTracks lands below the frozen "
    "band",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
        columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_board(controller));
      // Setup sanity: the band is one 50-tall row.
      expect(controller.frozenInsetOf(Axis.vertical), 50.0);

      final landed = controller.animateScrollToCell(10, 0);
      await tester.pumpAndSettle();
      expect(await landed, isTrue);
      final frame = tester.getRect(find.byKey(_frameKey));
      final avoided = tester.getRect(find.byKey(_cellKey(10, 0)));
      expect(avoided.top - frame.top, 50.0);

      // The falsification arm: without the inset the same target lands
      // UNDER the band.
      final under = controller.animateScrollToCell(
        10,
        0,
        avoidFrozenTracks: false,
      );
      await tester.pumpAndSettle();
      expect(await under, isTrue);
      expect(
        tester.getRect(find.byKey(_cellKey(10, 0))).top - frame.top,
        0.0,
      );
    },
  );

  // DERIVED name. No AC; the settle snap's INTENT guard: a newer scroll
  // intent issued between the legs landing and the post-frame snap must
  // win, and the stale snap must not yank the position back.
  // Falsification: an unguarded snap re-derives the OLD call's target
  // and jumps to it, overriding the newer jumpToCell.
  testWidgets(
    "a jumpToCell issued before the settle snap fires wins over the "
    "stale snap",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(60, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_board(controller));
      final frame = tester.getRect(find.byKey(_frameKey));

      final landed = controller.animateScrollToCell(
        40,
        0,
        duration: const Duration(milliseconds: 60),
      );
      // Chained on the composite, the newer intent runs in the same
      // microtask turn the legs complete in, BEFORE the pending snap's
      // post-frame callback fires.
      unawaited(
        landed.then((_) {
          controller.jumpToCell(5, 0);
        }),
      );
      await tester.pumpAndSettle();
      expect(await landed, isTrue);
      expect(
        tester.getRect(find.byKey(_cellKey(5, 0))).top - frame.top,
        0.0,
      );
    },
  );

  // DERIVED name. No AC; the snap's USER guard: a drag in progress when
  // the pending snap fires must not have the position yanked from under
  // it.
  // Falsification: the snap's jumpTo runs goIdle first, which kills the
  // user's drag activity and teleports to the stale target.
  testWidgets(
    "a user drag in progress when the settle snap fires is not yanked",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(60, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_board(controller));
      final frame = tester.getRect(find.byKey(_frameKey));

      final landed = controller.animateScrollToCell(
        40,
        0,
        duration: const Duration(milliseconds: 300),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // A user drag INTERRUPTS the flight: the down disposes the driven
      // activity, whose future completes the legs, so the pending snap
      // fires at this very frame's end while the drag holds the
      // position.
      final gesture = await tester.startGesture(frame.center);
      await gesture.moveBy(const Offset(0.0, -30.0));
      await tester.pump();
      final duringDrag = tester.getRect(
        find.byKey(_cellKey(20, 0), skipOffstage: false),
      ).top;
      await gesture.moveBy(const Offset(0.0, -10.0));
      await tester.pump();
      // The position moved WITH the drag rather than being yanked to the
      // re-derived target with the drag activity killed under the
      // finger: another 10 down exactly.
      expect(
        tester.getRect(find.byKey(_cellKey(20, 0), skipOffstage: false)).top,
        duringDrag - 10.0,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      // The composite's value is a documented residual here (an
      // interrupted flight can report true through the dispose path);
      // the guard's job is the position, not the bool.
      await landed;
    },
  );

  // DERIVED name. No AC; the out-of-lattice degradation: a target track
  // outside either axis completes false and jumps nothing, instead of
  // dying on the axis's domain assert.
  testWidgets(
    "a scroll target outside the lattice completes false without "
    "throwing",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_board(controller));

      final landed = controller.animateScrollToCell(999, 0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(await landed, isFalse);
      controller.jumpToCell(0, -1);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  // DERIVED name. No AC; the trailing inset under an over-large
  // frozenEnd, which every sibling frozen-band consumer tolerates by
  // clamping.
  testWidgets(
    "an over-large frozenEnd degrades the trailing inset instead of "
    "throwing",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenEnd: 99),
        columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_board(controller));

      final landed = controller.animateScrollToCell(
        10,
        0,
        rowAlignment: 1.0,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(await landed, isTrue);
    },
  );

  // Bands that overlap: `frozenStart` and `frozenEnd` of 3 on 5 rows. The
  // leading band keeps rows 0 to 2 and the trailing band only rows 3 and
  // 4, so the trailing inset `animateScrollToCell` aligns against is those
  // two rows, 200, and not the 300 that `frozenEnd` alone would count. An
  // alignment of 0.5 is what makes the inset matter: an alignment of 0.0
  // multiplies it by zero.
  testWidgets(
    "overlapping frozen bands inset animateScrollToCell by the trailing "
    "band's own tracks",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(
          axis: UniformAxis(5, 100.0),
          frozenStart: 3,
          frozenEnd: 3,
        ),
        columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300.0,
                height: 300.0,
                child: Board<String, _Item>(
                  controller: controller,
                  verticalDetails: ScrollableDetails.vertical(
                    controller: vertical,
                  ),
                  cellBuilder: (context, cell) {
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Setup sanity: the leading band is the three leading rows, and the
      // scroll range is the rows' total less the 300 px viewport.
      expect(controller.frozenInsetOf(Axis.vertical), 300.0);
      expect(vertical.position.maxScrollExtent, 200.0);

      final landed = controller.animateScrollToCell(
        2,
        0,
        rowAlignment: 0.5,
        duration: Duration.zero,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(await landed, isTrue);
      // The painted target is 300 + 0.5 * (300 - 300 - 200 - 100) = 150,
      // so row 2's offset of 200 lands at 200 - 150.
      expect(vertical.position.pixels, 50.0);
    },
  );

  // AC9's correction-versus-driven-scroll pairing.
  // Asserts: a LazyContentAxis whose estimate is deliberately wrong, so
  // tracks measured DURING the scroll keep correcting pixels while the
  // driven activity overwrites them with absolute values. After
  // pumpAndSettle the target's painted top is the aligned one AND
  // debugCorrectionCount grew across the scroll.
  // Falsification: suppressing corrections for the length of the scroll
  // fails the count half; no post-frame settle snap fails the landing.
  testWidgets(
    "a scroll across unmeasured tracks still lands on the target cell",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: LazyContentAxis(60, 100.0)),
        columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      final viewport = tester.allRenderObjects
          .whereType<RenderBoardViewport<String>>()
          .single;

      final frame = tester.getRect(find.byKey(_frameKey));

      // SCRIPT 1, the settle snap: a FAST flight whose coarse frames are
      // disjoint far jumps. Each window anchors on nothing, so the
      // flight itself corrects nothing, the stale estimate-derived
      // target overshoots the settled lattice, and only the post-frame
      // snap can land row 40 at the top.
      final fast = controller.animateScrollToCell(
        40,
        0,
        duration: const Duration(milliseconds: 60),
      );
      await tester.pumpAndSettle();
      expect(await fast, isTrue);
      expect(
        tester.getRect(find.byKey(_cellKey(40, 0))).top - frame.top,
        0.0,
      );

      // SCRIPT 2, the corrections: jump far down, then a SLOW sweep back
      // up in frame-sized steps. The overlapping windows keep revealing
      // unmeasured tracks at the TOP edge, the side whose measurements
      // move the anchor, so pixels keep being corrected while the driven
      // activity overwrites them with absolute values.
      controller.jumpToCell(55, 0);
      await tester.pumpAndSettle();
      final correctionsBefore = viewport.debugCorrectionCount;
      final landed = controller.animateScrollToCell(10, 0);
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(await landed, isTrue);
      expect(viewport.debugCorrectionCount, greaterThan(correctionsBefore));
      expect(
        tester.getRect(find.byKey(_cellKey(10, 0))).top - frame.top,
        0.0,
      );
    },
  );
}
