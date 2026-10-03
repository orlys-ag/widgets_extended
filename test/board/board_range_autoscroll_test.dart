/// Tests for item 7O of the board audit fixes: a range drag held at the
/// viewport's edge scrolls the board and extends the selection.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7O", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Case 1 was red at its TARGET on the tree item 7N left, with every
/// setup sanity assertion before it passing; case 2 pins the stop.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

/// Forty 50 px rows under a 300 px frame: rows 0 to 5 in view. The
/// returned `rebuild` pumps the same board with range selection on or off.
Future<
  ({
    BoardController<String, _Item> controller,
    ScrollController vertical,
    Future<void> Function({required bool selecting}) rebuild,
  })
>
_pump(WidgetTester tester) async {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(40, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  final vertical = ScrollController();
  addTearDown(vertical.dispose);
  // Registered after the disposes, so it runs before them.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  Widget board({required bool selecting}) {
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
              verticalDetails: ScrollableDetails.vertical(
                controller: vertical,
              ),
              cellBuilder: (context, cell) {
                return const SizedBox.expand();
              },
              selection: BoardSelectionConfig(
                enabled: selecting,
                onChanged: (selection) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  await tester.pumpWidget(board(selecting: true));
  return (
    controller: controller,
    vertical: vertical,
    rebuild: ({required bool selecting}) {
      return tester.pumpWidget(board(selecting: selecting));
    },
  );
}

Offset _at(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

void main() {
  // Test 1.
  testWidgets("a range dragged to the bottom edge scrolls and extends",
      (tester) async {
    final board = await _pump(tester);
    final gesture = await tester.startGesture(
      _at(tester, const Offset(60.0, 75.0)),
      kind: PointerDeviceKind.mouse,
    );
    // Into the bottom edge zone, and held there.
    await gesture.moveTo(_at(tester, const Offset(60.0, 296.0)));
    await tester.pump();
    // Setup sanity: a range is being dragged from row 1.
    expect(board.controller.selection.value.anchor, (row: 1, col: 1));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // TARGET: the board scrolled ...
    expect(board.vertical.offset, greaterThan(0.0));
    // ... and the range reaches the rows it scrolled to, past row 5.
    expect(board.controller.selection.value.focus!.row, greaterThan(5));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  // Test 2.
  testWidgets("the release stops the scroll", (tester) async {
    final board = await _pump(tester);
    final gesture = await tester.startGesture(
      _at(tester, const Offset(60.0, 75.0)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(_at(tester, const Offset(60.0, 296.0)));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    final stopped = board.vertical.offset;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // TARGET: nothing moves after the release, and nothing asks for a
    // frame.
    expect(board.vertical.offset, stopped);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  // Test 3. Turning selection off disposes the range's recognizer, which
  // never ends the drag it handed out, so the layer ends the range itself.
  testWidgets("turning selection off mid-range stops its scroll",
      (tester) async {
    final board = await _pump(tester);
    final gesture = await tester.startGesture(
      _at(tester, const Offset(60.0, 75.0)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(_at(tester, const Offset(60.0, 296.0)));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Setup sanity: the range is scrolling.
    expect(board.vertical.offset, greaterThan(0.0));

    await board.rebuild(selecting: false);
    final stopped = board.vertical.offset;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // TARGET: the scroll stopped, and nothing asks for a frame.
    expect(board.vertical.offset, stopped);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
