/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 5, L3 render plus the widget layer that
/// makes it pumpable. Every case here pumps a `Board`, because there is no
/// route to a `RenderBoardViewport` in a `testWidgets` body that does not
/// go through it, and both the probe counting and the per-column probes
/// are defined in terms of this file's own `cellBuilder`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_views.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

/// The caller payload. No case here puts an item on the board: step 5 is
/// cells only, and the item plane lands at step 7.
class _Item {
  const _Item(this.key);

  final String key;
}

/// The frame the board is sized by, and the origin every painted position
/// below is measured from.
const Key _frameKey = ValueKey<String>("board-frame");

/// One cell's probe. A widget class of its own rather than a bare
/// `SizedBox`, so counting built cells cannot pick up the harness's own
/// boxes.
class _Cell extends StatelessWidget {
  const _Cell({required this.height, super.key});

  /// What the cell ASKS for on the row axis. The track is wider than this
  /// in the alignment cases, and that difference is the surplus.
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 20.0, height: height);
  }
}

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

/// `Board` composes a `TwoDimensionalScrollView`, so it is its own
/// scrollable and goes under `MaterialApp > Scaffold` directly, sized by
/// the test. Wrapping it in a `CustomScrollView` the way the house tree
/// wrapper does would nest a scrollable in a scrollable.
Widget _board(
  BoardController<String, _Item> controller, {
  required BoardCellBuilder<String, _Item> cellBuilder,
  ScrollController? vertical,
  ScrollController? horizontal,
  double width = 300.0,
  double height = 200.0,
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
            cellBuilder: cellBuilder,
            verticalDetails: ScrollableDetails.vertical(controller: vertical),
            horizontalDetails: ScrollableDetails.horizontal(
              controller: horizontal,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pumps a board whose ROW tracks are 100 long and whose cells ask for 20,
/// so every row track carries 80 of surplus for [alignment] to place, and
/// returns cell (0, 0)'s rect relative to the board's own top-left.
///
/// A FIXED axis, so the surplus exists with no item plane and no
/// content-sized track: `UniformAxis(4, 100.0)` against a 20px cell.
Future<Rect> _alignedCellRect(
  WidgetTester tester,
  TrackAlignment alignment,
) async {
  final controller = _controller(
    tester,
    rows: BoardAxisConfig(axis: UniformAxis(4, 100.0), alignment: alignment),
    columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
  );
  await tester.pumpWidget(
    _board(
      controller,
      cellBuilder: (context, cell) {
        return _Cell(key: _cellKey(cell.row, cell.col), height: 20.0);
      },
    ),
  );
  final frame = tester.getRect(find.byKey(_frameKey));
  final cell = tester.getRect(find.byKey(_cellKey(0, 0)));
  return cell.translate(-frame.left, -frame.top);
}

void main() {
  // The booked convergence fence for the measurement floor: a zero-content
  // track floors at minTrackExtent ONCE, and an idle frame re-records
  // nothing. The counter is the only observable: a re-record writes the
  // value already stored, so every extent read stays identical while the
  // work repeats every frame.
  // Falsification: comparing the RAW measurement against the floored
  // stored extent re-records the empty track on every pump.
  testWidgets("a zero-content track is measured once and not on every "
      "layout", (tester) async {
    final lazy = LazyContentAxis(6, 40.0, minTrackExtent: 10.0);
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: lazy),
      columns: BoardAxisConfig(axis: UniformAxis(3, 100.0)),
    );
    await tester.pumpWidget(
      _board(
        controller,
        cellBuilder: (context, cell) {
          // Row 2 is EMPTY: its cells measure zero on the content axis.
          return _Cell(
            key: _cellKey(cell.row, cell.col),
            height: cell.row == 2 ? 0.0 : 20.0,
          );
        },
      ),
    );
    // The empty track floored at the axis minimum, not at zero.
    expect(lazy.extentOf(2), 10.0);
    expect(lazy.isMeasured(2), isTrue);

    final recordsAfterFirstFrame = lazy.debugRecordCount;
    controller.setSelection(
      const BoardSelection(anchor: (row: 0, col: 0), focus: (row: 0, col: 0)),
    );
    await tester.pump();
    await tester.pump();
    // Relayouts happened (the selection change forces one), and nothing
    // re-recorded: the convergence test compares what the axis STORES.
    expect(lazy.debugRecordCount, recordsAfterFirstFrame);
    expect(lazy.extentOf(2), 10.0);
  });

  // Nothing else in the inventory exercises AxisDirection.up or left, and
  // the normalized-space rule is load-bearing: layoutOffset is written
  // WITHOUT reversal and the base applies it downstream, while the port
  // members apply it themselves.
  // Falsification: writing layoutOffset in viewport-paint space (reversal
  // applied twice), or a port that subtracts pixels without inverting.
  testWidgets("reversed axis directions place cell (0, 0) at the trailing "
      "corner", (tester) async {
    final controller = _controller(
      tester,
      rows: BoardAxisConfig(axis: UniformAxis(20, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(20, 50.0)),
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
                horizontalDetails: const ScrollableDetails(
                  direction: AxisDirection.left,
                ),
                cellBuilder: (context, cell) {
                  return _Cell(
                    key: _cellKey(cell.row, cell.col),
                    height: 20.0,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    final frame = tester.getRect(find.byKey(_frameKey));
    final viewport = tester.allRenderObjects
        .whereType<RenderBoardViewport<String>>()
        .single;

    // The port's geometry: track (0, 0) occupies content [0, 50) on both
    // axes, which under up and left is the BOTTOM-RIGHT corner.
    expect(viewport.rectOfCell(0, 0), const Rect.fromLTWH(250.0, 150.0, 50.0, 50.0));

    // The painted child agrees with the port.
    final painted = tester.getRect(find.byKey(_cellKey(0, 0)));
    expect(painted.left - frame.left, 250.0);
    expect(painted.top - frame.top, 150.0);

    // And the pointer inverse agrees with both.
    expect(viewport.cellAt(const Offset(260.0, 160.0)), (row: 0, col: 0));
  });

  // AC17 horizontal virtualization.
  // Asserts: after scrolling x past the initial window, the newly visible
  // column's probes exist, the departed ones do not, and the total stays
  // inside a bound.
  // Falsification: an implementation that virtualizes only y passes every
  // other test here and fails this.
  testWidgets(
    "scrolling the horizontal axis builds new columns and releases the ones that left",
    (tester) async {
      final horizontal = ScrollController();
      addTearDown(horizontal.dispose);
      final controller = _controller(
        tester,
        rows: BoardAxisConfig(axis: UniformAxis(4, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(40, 100.0)),
      );
      await tester.pumpWidget(
        _board(
          controller,
          horizontal: horizontal,
          cellBuilder: (context, cell) {
            return _Cell(key: _cellKey(cell.row, cell.col), height: 50.0);
          },
        ),
      );

      // SETUP SANITY. Column 0 is on screen before the scroll, so the
      // "departed" assertion below is about a column that was genuinely
      // there and not about one that never built.
      expect(
        find.byKey(_cellKey(0, 0)),
        findsOneWidget,
        reason:
            "The board must build the leading column before the "
            "scroll, or nothing below is about columns leaving.",
      );

      // 2000 content-space pixels is 20 columns, well past the initial
      // window and its cache band.
      horizontal.jumpTo(2000.0);
      await tester.pumpAndSettle();

      expect(
        find.byKey(_cellKey(0, 20)),
        findsOneWidget,
        reason:
            "The column under the new x offset must be built. An "
            "implementation that virtualizes only y never builds it.",
      );
      expect(
        find.byKey(_cellKey(0, 0)),
        findsNothing,
        reason:
            "The column the scroll left behind must be released. An "
            "implementation that widens the window rather than moving it "
            "keeps it built.",
      );
      // Nine columns of four rows is 36. An implementation that builds
      // every column builds 160.
      expect(
        find.byType(_Cell).evaluate().length,
        lessThan(60),
        reason:
            "The built set must stay bounded by the window, not by "
            "the column count.",
      );
    },
  );

  // DERIVED name. No AC; one of the four TrackAlignment cases on a FIXED
  // axis whose track extent exceeds what the cell asks for: a UniformAxis
  // of extent 100 with a cellBuilder returning a 20px widget.
  // Asserts: stretch gives the cell the whole 100.
  // Falsification: stretch versus start is the pair that fails if alignment
  // is read but not applied.
  testWidgets("TrackAlignment.stretch gives the cell the whole track extent", (
    tester,
  ) async {
    final rect = await _alignedCellRect(tester, TrackAlignment.stretch);

    expect(
      rect.height,
      100.0,
      reason:
          "stretch lays the cell out TIGHT at the resolved track "
          "extent, so it takes the whole track and leaves no surplus.",
    );
    expect(
      rect.top,
      0.0,
      reason: "With no surplus there is nothing to shift the cell by.",
    );
  });

  // DERIVED name. No AC; one of the four TrackAlignment cases.
  // Asserts: start leaves the cell at 20 with its painted top at 0.
  // Falsification: stretch versus start is the pair that fails if alignment
  // is read but not applied.
  testWidgets(
    "TrackAlignment.start leaves the cell at its own extent with its painted top at 0",
    (tester) async {
      final rect = await _alignedCellRect(tester, TrackAlignment.start);

      expect(
        rect.height,
        20.0,
        reason:
            "start lays the cell out LOOSE, so it keeps the extent it "
            "asked for. An implementation that ignores alignment and "
            "always stretches reports 100.",
      );
      expect(
        rect.top,
        0.0,
        reason: "start leaves the cell at the track's leading edge.",
      );
    },
  );

  // DERIVED name. No AC; one of the four TrackAlignment cases.
  // Asserts: center leaves the cell at 20 with its painted top at 40.
  // Falsification: center versus end is the pair that fails if alignment is
  // applied with a fixed factor.
  testWidgets(
    "TrackAlignment.center leaves the cell at its own extent with its painted top at 40",
    (tester) async {
      final rect = await _alignedCellRect(tester, TrackAlignment.center);

      expect(
        rect.height,
        20.0,
        reason:
            "center lays the cell out LOOSE, so it keeps its own "
            "extent.",
      );
      expect(
        rect.top,
        40.0,
        reason:
            "Half of the 80 surplus. An implementation applying a "
            "fixed factor reports 0 or 80 here.",
      );
    },
  );

  // DERIVED name. No AC; one of the four TrackAlignment cases.
  // Asserts: end leaves the cell at 20 with its painted top at 80.
  // Falsification: center versus end is the pair that fails if alignment is
  // applied with a fixed factor.
  testWidgets(
    "TrackAlignment.end leaves the cell at its own extent with its painted top at 80",
    (tester) async {
      final rect = await _alignedCellRect(tester, TrackAlignment.end);

      expect(
        rect.height,
        20.0,
        reason: "end lays the cell out LOOSE, so it keeps its own extent.",
      );
      expect(
        rect.top,
        80.0,
        reason:
            "The whole 80 surplus. An implementation applying a fixed "
            "factor reports 0 or 40 here.",
      );
    },
  );
}
