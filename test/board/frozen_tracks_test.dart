/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 6: frozen bands, the paint override, and
/// the hit-test override that mirrors it.
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

Key _cellKey(int row, int col) {
  return ValueKey<String>("c${row}_$col");
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  required BoardAxisConfig rows,
  required BoardAxisConfig columns,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: rows,
    columns: columns,
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  // AC5 frozen hit-test precedence.
  // Asserts: scroll until a content cell lies under the header band, tap,
  // assert the frozen cell's callback fired and the content cell's did
  // not. Falsification: plain vicinity order fails.
  testWidgets("a pointer inside the frozen band hits the frozen cell", (
    tester,
  ) async {
    final controller = _controller(
      tester,
      // Row 0 is a frozen header band 50 tall; 30 rows of 50 give enough
      // content to scroll a distinct row under it.
      rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
      columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    );
    final taps = <String>[];
    // STARTS scrolled, deliberately: at an initial offset the header row is
    // outside the first frame's window, so the content cells enter the
    // child map before the frozen ones do. Scrolling there after a pump at
    // offset 0 instead would insert the header first, and the base
    // insertion-order hit test would then pass this case by accident of
    // history, which was observed rather than reasoned.
    final vertical = ScrollController(initialScrollOffset: 500.0);
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: _frameKey,
              width: 300.0,
              height: 200.0,
              child: Board<String, _Item>(
                controller: controller,
                verticalDetails: ScrollableDetails.vertical(
                  controller: vertical,
                ),
                cellBuilder: (context, cell) {
                  return GestureDetector(
                    key: _cellKey(cell.row, cell.col),
                    onTap: () {
                      taps.add("${cell.row},${cell.col}");
                    },
                    child: ColoredBox(
                      color: cell.isFrozen
                          ? const Color(0xFF2196F3)
                          : const Color(0xFFE0E0E0),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    // At pixels 500, content y 525 is row 10: a content cell sits under
    // the header band from the first frame.
    expect(vertical.offset, 500.0);

    final frame = tester.getRect(find.byKey(_frameKey));

    // Setup sanity, and the placement half of the band: the frozen header
    // cell stays PINNED to the viewport's leading edge after the scroll.
    // An implementation that writes a frozen track's position with the
    // scroll term keeps this cell 500 above the frame and goes red here.
    final headerRect = tester.getRect(find.byKey(_cellKey(0, 1)));
    expect(headerRect.top - frame.top, 0.0);

    // The tap point: 25 into the 50-tall band, over column 1.
    final tapPoint = frame.topLeft + const Offset(150.0, 25.0);

    // The content cell under the band did NOT take the pointer. Red when
    // the hit-test walk skips the frozen plane: the cell plane then wins
    // and taps records "10,1".
    await tester.tapAt(tapPoint);
    await tester.pump();
    expect(taps, isNot(contains("10,1")));

    // The frozen cell DID take it. Red when nothing is hit at all (an
    // override that walks no plane), where the previous assertion stays
    // green.
    expect(taps, contains("0,1"));

    // The port's frozen probe resolves the same cell, and resolves
    // nothing below the band.
    final viewport = tester.allRenderObjects
        .whereType<RenderBoardViewport<String>>()
        .single;
    expect(
      viewport.frozenCellAt(const Offset(150.0, 25.0)),
      (row: 0, col: 1),
    );
    expect(viewport.frozenCellAt(const Offset(150.0, 125.0)), isNull);
    expect(viewport.frozenInsetOf(Axis.vertical), 50.0);
    expect(viewport.frozenInsetOf(Axis.horizontal), 0.0);
  });

  // Trailing bands had zero behavioral coverage; the formulas were
  // verified by probe during the steps-5-and-6 audit and are fenced here.
  // Falsification: placing a trailing frozen track from content space
  // (the leading formula) paints it 1000-plus pixels away; dropping
  // frozenCellAt's trailing arm resolves null inside the band.
  testWidgets("a trailing frozen band pins to the trailing edge and "
      "resolves its own cells", (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenEnd: 1),
      columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    );
    final vertical = ScrollController(initialScrollOffset: 400.0);
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: _frameKey,
              width: 300.0,
              height: 200.0,
              child: Board<String, _Item>(
                controller: controller,
                verticalDetails: ScrollableDetails.vertical(
                  controller: vertical,
                ),
                cellBuilder: (context, cell) {
                  return ColoredBox(
                    key: _cellKey(cell.row, cell.col),
                    color: const Color(0xFFE0E0E0),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    final frame = tester.getRect(find.byKey(_frameKey));
    // Row 29's band occupies the viewport's last 50 pixels whatever the
    // scroll offset is.
    final footer = tester.getRect(find.byKey(_cellKey(29, 1)));
    expect(footer.top - frame.top, 150.0);
    final viewport = tester.allRenderObjects
        .whereType<RenderBoardViewport<String>>()
        .single;
    expect(
      viewport.frozenCellAt(const Offset(150.0, 175.0)),
      (row: 29, col: 1),
    );
    expect(viewport.frozenCellAt(const Offset(150.0, 125.0)), isNull);
  });

  // Falsification: a _normalizedFromPaint that ignores the axis direction
  // resolves the band at the top and paints the header at the top; under
  // AxisDirection.up the LEADING edge is the bottom.
  testWidgets("frozen bands pin to the reversed leading edge under "
      "AxisDirection.up", (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
      columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: _frameKey,
              width: 300.0,
              height: 200.0,
              child: Board<String, _Item>(
                controller: controller,
                verticalDetails: const ScrollableDetails(
                  direction: AxisDirection.up,
                ),
                cellBuilder: (context, cell) {
                  return ColoredBox(
                    key: _cellKey(cell.row, cell.col),
                    color: const Color(0xFFE0E0E0),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    final frame = tester.getRect(find.byKey(_frameKey));
    // The leading band sits at the BOTTOM: row 0's header paints in the
    // viewport's last 50 pixels.
    final header = tester.getRect(find.byKey(_cellKey(0, 1)));
    expect(header.top - frame.top, 150.0);
    final viewport = tester.allRenderObjects
        .whereType<RenderBoardViewport<String>>()
        .single;
    expect(
      viewport.frozenCellAt(const Offset(150.0, 175.0)),
      (row: 0, col: 1),
    );
  });

  // Falsification: appending the corner into plane 3 in encounter order
  // instead of last lets a band cell scrolled into the corner rectangle
  // take the tap.
  testWidgets("the corner outpaints and out-hits both bands after a "
      "two-axis scroll", (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(30, 50.0), frozenStart: 1),
      columns: BoardAxisConfig(axis: UniformAxis(30, 100.0), frozenStart: 1),
    );
    final taps = <String>[];
    final vertical = ScrollController(initialScrollOffset: 500.0);
    final horizontal = ScrollController(initialScrollOffset: 700.0);
    addTearDown(vertical.dispose);
    addTearDown(horizontal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: _frameKey,
              width: 300.0,
              height: 200.0,
              child: Board<String, _Item>(
                controller: controller,
                verticalDetails: ScrollableDetails.vertical(
                  controller: vertical,
                ),
                horizontalDetails: ScrollableDetails.horizontal(
                  controller: horizontal,
                ),
                cellBuilder: (context, cell) {
                  return GestureDetector(
                    key: _cellKey(cell.row, cell.col),
                    onTap: () {
                      taps.add("${cell.row},${cell.col}");
                    },
                    child: const ColoredBox(color: Color(0xFFE0E0E0)),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    final frame = tester.getRect(find.byKey(_frameKey));
    // The corner rectangle is the top-left 100 x 50. Tap inside it.
    await tester.tapAt(frame.topLeft + const Offset(50.0, 25.0));
    await tester.pump();
    expect(taps, <String>["0,0"]);
  });
}
