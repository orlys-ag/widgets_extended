/// Tests for item 7G of the board audit fixes: the scroll alignment
/// follows Flutter's convention, and an animated scroll another call or
/// the user takes over completes false.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7G", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Every TARGET was red on the tree item 7F left, with every setup sanity
/// assertion before it passing.
library;

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

/// 50 px rows under a 200 px frame, and seven 40 px columns that fill
/// its 280 px width, so only the rows scroll.
BoardController<String, _Item> _controller(
  WidgetTester tester, {
  int rows = 60,
  int frozenEnd = 0,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(rows, 50.0), frozenEnd: frozenEnd),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  // Registered after the dispose, so it runs before it: the board
  // unsubscribes when it unmounts.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
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
          height: 200.0,
          child: Board<String, _Item>(
            controller: controller,
            cellBuilder: (context, cell) {
              return const SizedBox.expand();
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

void main() {
  // Test 1 (S1).
  testWidgets("alignment 1.0 lands the cell's trailing edge on the "
      "viewport's", (tester) async {
    final controller = _controller(tester, rows: 30);
    await tester.pumpWidget(_board(controller));
    final viewport = _viewport(tester);
    final landed = controller.animateScrollToCell(
      10,
      0,
      rowAlignment: 1.0,
      avoidFrozenTracks: false,
    );
    await tester.pumpAndSettle();
    // Setup sanity: the scroll ran and landed.
    expect(await landed, isTrue);
    expect(viewport.verticalPosition!.pixels, greaterThan(0.0));
    // TARGET: the whole cell shows, its bottom on the viewport's.
    expect(viewport.rectOfCell(10, 0)!.bottom, 200.0);
  });

  // Test 2 (S1).
  testWidgets("alignment 0.5 centres the cell", (tester) async {
    final controller = _controller(tester, rows: 30);
    await tester.pumpWidget(_board(controller));
    final viewport = _viewport(tester);
    final landed = controller.animateScrollToCell(
      10,
      0,
      rowAlignment: 0.5,
      avoidFrozenTracks: false,
    );
    await tester.pumpAndSettle();
    expect(await landed, isTrue);
    // TARGET.
    expect(viewport.rectOfCell(10, 0)!.center.dy, 100.0);
  });

  // Test 3 (S1). The trailing band is the last row, 50 px, so the region
  // the alignment runs over ends at 150.
  testWidgets("alignment 1.0 lands on the trailing band's start",
      (tester) async {
    final controller = _controller(tester, rows: 30, frozenEnd: 1);
    await tester.pumpWidget(_board(controller));
    final viewport = _viewport(tester);
    final landed = controller.animateScrollToCell(10, 0, rowAlignment: 1.0);
    await tester.pumpAndSettle();
    expect(await landed, isTrue);
    // Setup sanity: the band paints where the region ends.
    expect(viewport.rectOfCell(29, 0)!.top, 150.0);
    // TARGET.
    expect(viewport.rectOfCell(10, 0)!.bottom, 150.0);
  });

  // Test 4 (S2). The jump lands on the very offset the animation was
  // heading for, so only the supersession, and not where the position
  // ends, can tell the call it was taken over.
  testWidgets("an animation superseded by jumpToCell completes false",
      (tester) async {
    final controller = _controller(tester);
    await tester.pumpWidget(_board(controller));
    final viewport = _viewport(tester);
    final landed = controller.animateScrollToCell(
      40,
      0,
      duration: const Duration(milliseconds: 300),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Setup sanity: in flight, short of row 40's offset.
    expect(viewport.verticalPosition!.pixels, greaterThan(0.0));
    expect(viewport.verticalPosition!.pixels, lessThan(2000.0));
    controller.jumpToCell(40, 0);
    await tester.pumpAndSettle();
    // Setup sanity: the jump took the position, to the same offset.
    expect(viewport.verticalPosition!.pixels, 2000.0);
    // TARGET.
    expect(await landed, isFalse);
  });

  // Test 5 (S2). Alignment 1.0 on row 40 is the offset that shows its
  // bottom on the viewport's, which is also the least jump that reveals
  // it from above.
  testWidgets("an animation superseded by revealCell completes false",
      (tester) async {
    final controller = _controller(tester);
    await tester.pumpWidget(_board(controller));
    final viewport = _viewport(tester);
    final landed = controller.animateScrollToCell(
      40,
      0,
      rowAlignment: 1.0,
      duration: const Duration(milliseconds: 300),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(viewport.verticalPosition!.pixels, lessThan(1850.0));
    controller.revealCell(40, 0);
    await tester.pumpAndSettle();
    // Setup sanity: the reveal took the position, to the same offset.
    expect(viewport.verticalPosition!.pixels, 1850.0);
    // TARGET.
    expect(await landed, isFalse);
  });

  // Test 6 (S2).
  testWidgets("an animation a user drag interrupts completes false",
      (tester) async {
    final controller = _controller(tester);
    await tester.pumpWidget(_board(controller));
    final viewport = _viewport(tester);
    final landed = controller.animateScrollToCell(
      40,
      0,
      duration: const Duration(milliseconds: 300),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final frame = tester.getRect(find.byKey(_frameKey));
    final gesture = await tester.startGesture(frame.center);
    await gesture.moveBy(const Offset(0.0, -40.0));
    await tester.pump();
    await gesture.moveBy(const Offset(0.0, -40.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    // Setup sanity: the finger, not the animation, decided where it
    // stopped.
    expect(viewport.verticalPosition!.pixels, lessThan(2000.0));
    // TARGET.
    expect(await landed, isFalse);
  });
}
