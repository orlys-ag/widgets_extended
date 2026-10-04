/// Tests for item 6B of the board audit fixes: the board takes focus and
/// moves its selection with the keyboard, and Escape cancels a drag.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 6B", the
/// Tests list. Case numbers in the comments are that list's.
///
/// Every TARGET was red on the tree item 6A left, or is a DESIGN PIN
/// whose red was shown by the mutation its comment names.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

/// [rows] rows of 50 by seven columns of 40, animations off.
BoardController<String, _Item> _controller(
  WidgetTester tester, {
  int rows = 6,
  int frozenRows = 0,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(rows, 50.0), frozenStart: frozenRows),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Unmounts the board before the controller's own tear-down disposes it.
void _unmountFirst(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _app(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  );
}

Widget _board(
  BoardController<String, _Item> controller, {
  BoardSelectionConfig? selection,
  BoardDragConfig<String>? drag,
  ScrollableDetails verticalDetails = const ScrollableDetails.vertical(),
}) {
  return SizedBox(
    key: _frameKey,
    width: 280.0,
    height: 300.0,
    child: Board<String, _Item>(
      controller: controller,
      selection: selection,
      drag: drag,
      verticalDetails: verticalDetails,
      cellBuilder: (context, cell) {
        return const SizedBox(width: 40.0, height: 50.0);
      },
      itemBuilder: (context, item) {
        return ColoredBox(
          key: ValueKey<String>("i${item.key}"),
          color: const Color(0xFF4CAF50),
        );
      },
    ),
  );
}

BoardSelectionConfig _cells() {
  return BoardSelectionConfig(
    onChanged: (_) {},
    mode: BoardSelectionMode.cell,
  );
}

({int row, int col})? _focusCell(BoardController<String, _Item> controller) {
  return controller.selection.value.focus;
}

Offset _global(WidgetTester tester, Offset local) {
  return tester.getRect(find.byKey(_frameKey)).topLeft + local;
}

/// Whether the primary focus sits inside a [Board].
bool _boardHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context?.findAncestorWidgetOfExactType<Board<String, _Item>>() !=
      null;
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey? modifier,
}) async {
  if (modifier != null) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyEvent(key);
  if (modifier != null) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
}

void main() {
  // Test 1.
  testWidgets("a tap focuses the board and the arrow keys move a cell "
      "selection", (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    await tester.pumpWidget(_app(_board(controller, selection: _cells())));
    // Cell (1, 1)'s centre is (60, 75).
    await tester.tapAt(_global(tester, const Offset(60.0, 75.0)));
    await tester.pump();
    // Setup sanity: the tap selected (1, 1).
    expect(_focusCell(controller), (row: 1, col: 1));
    // TARGET: the board holds focus ...
    expect(_boardHasFocus(), isTrue);
    // ... and each arrow moves the selection one cell that way.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusCell(controller), (row: 1, col: 2));
    // A cell selection is one cell: the anchor moved with it.
    expect(controller.selection.value.anchor, (row: 1, col: 2));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusCell(controller), (row: 2, col: 2));
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focusCell(controller), (row: 2, col: 1));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focusCell(controller), (row: 1, col: 1));
  });

  // Test 2. Up on the screen is the NEXT content row when the vertical
  // axis grows upward.
  testWidgets("the up arrow moves up the screen on a reversed vertical "
      "axis", (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    await tester.pumpWidget(
      _app(
        _board(
          controller,
          selection: _cells(),
          verticalDetails: const ScrollableDetails(
            direction: AxisDirection.up,
          ),
        ),
      ),
    );
    // Rows paint bottom up: row 1 is 200 to 250.
    await tester.tapAt(_global(tester, const Offset(60.0, 225.0)));
    await tester.pump();
    expect(_focusCell(controller), (row: 1, col: 1));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    // TARGET.
    expect(_focusCell(controller), (row: 2, col: 1));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusCell(controller), (row: 1, col: 1));
  });

  // Test 3.
  testWidgets("Shift with an arrow extends a range selection and an arrow "
      "alone collapses it", (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    await tester.pumpWidget(
      _app(
        _board(
          controller,
          selection: BoardSelectionConfig(onChanged: (_) {}),
        ),
      ),
    );
    // A range press from (1, 1) to (2, 3).
    // A mouse, which starts a range at once (item 7I).
    final gesture = await tester.startGesture(
      _global(tester, const Offset(60.0, 75.0)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(_global(tester, const Offset(140.0, 125.0)));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.selection.value.anchor, (row: 1, col: 1));
    expect(_focusCell(controller), (row: 2, col: 3));

    await _press(
      tester,
      LogicalKeyboardKey.arrowRight,
      modifier: LogicalKeyboardKey.shiftLeft,
    );
    // TARGET: the focus corner moved and the anchor stayed ...
    expect(controller.selection.value.anchor, (row: 1, col: 1));
    expect(_focusCell(controller), (row: 2, col: 4));
    await _press(tester, LogicalKeyboardKey.arrowRight);
    // ... and a plain arrow collapses onto the moved focus.
    expect(controller.selection.value.anchor, (row: 2, col: 5));
    expect(_focusCell(controller), (row: 2, col: 5));
  });

  // Test 4.
  testWidgets("Home, End and Control with End reach the row's and the "
      "lattice's ends", (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    await tester.pumpWidget(_app(_board(controller, selection: _cells())));
    // Cell (2, 2)'s centre is (100, 125).
    await tester.tapAt(_global(tester, const Offset(100.0, 125.0)));
    await tester.pump();
    expect(_focusCell(controller), (row: 2, col: 2));
    await _press(tester, LogicalKeyboardKey.end);
    expect(_focusCell(controller), (row: 2, col: 6));
    await _press(tester, LogicalKeyboardKey.home);
    expect(_focusCell(controller), (row: 2, col: 0));
    await _press(
      tester,
      LogicalKeyboardKey.end,
      modifier: LogicalKeyboardKey.controlLeft,
    );
    expect(_focusCell(controller), (row: 5, col: 6));
    await _press(
      tester,
      LogicalKeyboardKey.home,
      modifier: LogicalKeyboardKey.controlLeft,
    );
    expect(_focusCell(controller), (row: 0, col: 0));
  });

  // Test 5. Rows 0 to 5 are in view, partly or wholly, so a page is five
  // rows; the move reveals row 6 by scrolling just enough.
  testWidgets("Page Down moves by the scrolled rows in view",
      (tester) async {
    final controller = _controller(tester, rows: 30);
    _unmountFirst(tester);
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      _app(
        _board(
          controller,
          selection: _cells(),
          verticalDetails: ScrollableDetails.vertical(controller: vertical),
        ),
      ),
    );
    await tester.tapAt(_global(tester, const Offset(60.0, 75.0)));
    await tester.pump();
    expect(_focusCell(controller), (row: 1, col: 1));
    await _press(tester, LogicalKeyboardKey.pageDown);
    // TARGET.
    expect(_focusCell(controller), (row: 6, col: 1));
    expect(vertical.offset, 50.0);
    await _press(tester, LogicalKeyboardKey.pageUp);
    expect(_focusCell(controller), (row: 1, col: 1));
  });

  // Test 6. Nothing selected: a key selects where the user is looking,
  // and moves nothing further.
  testWidgets("an arrow with nothing selected selects the first scrolled "
      "cell in view", (tester) async {
    final controller = _controller(tester, rows: 30);
    _unmountFirst(tester);
    final vertical = ScrollController(initialScrollOffset: 120.0);
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      _app(
        _board(
          controller,
          selection: _cells(),
          verticalDetails: ScrollableDetails.vertical(controller: vertical),
        ),
      ),
    );
    // Focus the board with a tap, then clear the selection it made.
    await tester.tapAt(_global(tester, const Offset(60.0, 75.0)));
    await tester.pump();
    controller.setSelection(const BoardSelection.none());
    await tester.pump();
    expect(controller.selection.value.isEmpty, isTrue);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    // TARGET: row 2, 100 to 150, is the first in view at offset 120, and
    // the ArrowDown selected it without moving on to row 3 ...
    expect(_focusCell(controller), (row: 2, col: 0));
    // ... and revealed it whole, as every keyboard selection is.
    expect(vertical.offset, 100.0);
  });

  // Test 7. A reveal scrolls the least that shows the cell, and below a
  // frozen band; a cell already in view does not scroll; a frozen row
  // never scrolls its axis.
  testWidgets("a keyboard move scrolls just enough to show the focus cell, "
      "below a frozen band", (tester) async {
    final controller = _controller(tester, rows: 30, frozenRows: 1);
    _unmountFirst(tester);
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      _app(
        _board(
          controller,
          selection: _cells(),
          verticalDetails: ScrollableDetails.vertical(controller: vertical),
        ),
      ),
    );
    // Cell (4, 1) paints 200 to 250.
    await tester.tapAt(_global(tester, const Offset(60.0, 225.0)));
    await tester.pump();
    expect(_focusCell(controller), (row: 4, col: 1));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    // Row 5 ends at 300, the viewport's end: no scroll.
    expect(vertical.offset, 0.0);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    // TARGET: row 6 ends at 350, so 50 of scroll and no more.
    expect(_focusCell(controller), (row: 6, col: 1));
    expect(vertical.offset, 50.0);
    for (var i = 0; i < 4; i++) {
      await _press(tester, LogicalKeyboardKey.arrowUp);
    }
    // Row 2 starts at 100, which at offset 50 paints at 50, just below
    // the 50-tall band: no scroll.
    expect(_focusCell(controller), (row: 2, col: 1));
    expect(vertical.offset, 50.0);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    // Row 1 is under the band at offset 50: back to 0, its top at the
    // band's bottom.
    expect(_focusCell(controller), (row: 1, col: 1));
    expect(vertical.offset, 0.0);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    // Row 0 is the frozen header.
    expect(_focusCell(controller), (row: 0, col: 1));
    expect(vertical.offset, 0.0);
  });

  // Test 8. With selection off the board does not take focus, and with
  // it on a key the board has no use for reaches the app.
  testWidgets("the keys are left to the app when selection is off",
      (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    final outer = FocusNode(debugLabel: "outer");
    addTearDown(outer.dispose);
    final seen = <LogicalKeyboardKey>[];
    Widget app(BoardSelectionConfig selection) {
      return _app(
        Focus(
          focusNode: outer,
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              seen.add(event.logicalKey);
            }
            return KeyEventResult.handled;
          },
          child: _board(controller, selection: selection),
        ),
      );
    }

    await tester.pumpWidget(
      app(
        BoardSelectionConfig(
          onChanged: (_) {},
          mode: BoardSelectionMode.cell,
          enabled: false,
        ),
      ),
    );
    await tester.pump();
    expect(outer.hasPrimaryFocus, isTrue);
    await tester.tapAt(_global(tester, const Offset(60.0, 75.0)));
    await tester.pump();
    // DESIGN PIN: the tap did not take focus (red under a tap that
    // requests focus whatever the selection says).
    expect(outer.hasPrimaryFocus, isTrue);

    await tester.pumpWidget(app(_cells()));
    await tester.tapAt(_global(tester, const Offset(60.0, 75.0)));
    await tester.pump();
    expect(_boardHasFocus(), isTrue);
    await _press(tester, LogicalKeyboardKey.keyA);
    // DESIGN PIN: a key the board has no use for propagates (red under
    // a handler that claims every key).
    expect(seen, contains(LogicalKeyboardKey.keyA));
    // The arrow is the board's.
    seen.clear();
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(seen, isEmpty);
  });

  // Test 9.
  testWidgets("Tab stops on a selecting board and not on a board that only "
      "drags", (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    final before = FocusNode(debugLabel: "before");
    final after = FocusNode(debugLabel: "after");
    addTearDown(before.dispose);
    addTearDown(after.dispose);
    Widget app({BoardSelectionConfig? selection, BoardDragConfig<String>? drag}) {
      return _app(
        Column(
          children: <Widget>[
            Focus(focusNode: before, child: const SizedBox(width: 10.0, height: 10.0)),
            _board(controller, selection: selection, drag: drag),
            Focus(focusNode: after, child: const SizedBox(width: 10.0, height: 10.0)),
          ],
        ),
      );
    }

    await tester.pumpWidget(app(selection: _cells()));
    before.requestFocus();
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.tab);
    // TARGET: the selecting board is a Tab stop.
    expect(_boardHasFocus(), isTrue);

    await tester.pumpWidget(
      app(drag: BoardDragConfig<String>(onItemMoved: (key, span) {})),
    );
    before.requestFocus();
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.tab);
    // TARGET: a board that only drags is skipped.
    expect(after.hasPrimaryFocus, isTrue);
  });

  // Test 10.
  testWidgets("Escape cancels a live drag and is consumed", (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    controller.addItem(
      const _Item("m"),
      const BoardSpan(rowStart: 2, colStart: 1),
    );
    final moves = <BoardSpan>[];
    final escapes = <KeyEvent>[];
    await tester.pumpWidget(
      _app(
        Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              escapes.add(event);
            }
            return KeyEventResult.ignored;
          },
          child: _board(
            controller,
            drag: BoardDragConfig<String>(
              onItemMoved: (key, span) {
                moves.add(span);
                controller.moveItem(key, span);
              },
            ),
          ),
        ),
      ),
    );
    // Item m paints (40, 100) to (80, 150); a long press lifts it.
    final gesture = await tester.startGesture(
      _global(tester, const Offset(60.0, 125.0)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0.0, 60.0));
    await tester.pump();
    // Setup sanity: a live session.
    expect(controller.isDragging("m"), isTrue);

    await _press(tester, LogicalKeyboardKey.escape);
    // TARGET: the session is gone ...
    expect(controller.isDragging("m"), isFalse);
    // ... Escape went no further ...
    expect(escapes, isEmpty);
    // ... and the release reports nothing.
    await gesture.moveBy(const Offset(0.0, 60.0));
    await gesture.up();
    await tester.pump();
    expect(moves, isEmpty);
    expect(controller.spanOf("m"), const BoardSpan(rowStart: 2, colStart: 1));

    // With no session Escape is not the board's.
    await _press(tester, LogicalKeyboardKey.escape);
    expect(escapes, hasLength(1));
  });

  // Test 11.
  testWidgets("revealCell does not scroll a visible cell and leaves a "
      "frozen axis alone", (tester) async {
    final controller = _controller(tester, rows: 30, frozenRows: 1);
    _unmountFirst(tester);
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      _app(
        _board(
          controller,
          verticalDetails: ScrollableDetails.vertical(controller: vertical),
        ),
      ),
    );
    // Row 3 shows: no scroll.
    controller.revealCell(3, 1);
    await tester.pump();
    expect(vertical.offset, 0.0);
    // Row 10, 500 to 550: just enough to bring its end to the viewport's.
    controller.revealCell(10, 1);
    await tester.pump();
    expect(vertical.offset, 250.0);
    // Row 5, 250 to 300, is under the band at 250: its top to the band's
    // bottom.
    controller.revealCell(5, 1);
    await tester.pump();
    expect(vertical.offset, 200.0);
    // Row 0 is frozen, always shown: the axis stays where it is.
    controller.revealCell(0, 1);
    await tester.pump();
    expect(vertical.offset, 200.0);
  });

  // Test 12.
  testWidgets("a given focus node is the one the board uses, and autofocus "
      "takes focus", (tester) async {
    final controller = _controller(tester);
    _unmountFirst(tester);
    final node = FocusNode(debugLabel: "app");
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _app(
        SizedBox(
          key: _frameKey,
          width: 280.0,
          height: 300.0,
          child: Board<String, _Item>(
            controller: controller,
            selection: _cells(),
            focusNode: node,
            autofocus: true,
            cellBuilder: (context, cell) {
              return const SizedBox(width: 40.0, height: 50.0);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    // TARGET: autofocus took focus, with the node given.
    expect(node.hasPrimaryFocus, isTrue);
    node.unfocus();
    await tester.pump();
    expect(node.hasPrimaryFocus, isFalse);
    await tester.tapAt(_global(tester, const Offset(60.0, 75.0)));
    await tester.pump();
    // TARGET: a tap focuses the same node.
    expect(node.hasPrimaryFocus, isTrue);
  });
}
