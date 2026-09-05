/// Tests for the lane span expansion plan: a laned item occupies every
/// consecutive lane above its own that no overlapping cluster member
/// holds, both geometry rules measure that whole BAND, and the
/// content-sized cluster term holds a band an exiting member is still
/// blocking.
///
/// Source: `plans/2026-09-05-lane-span-expansion-plan.md`, the Testing
/// Plan section (anchor `testing-plan`). Case names are the plan's names
/// VERBATIM.
///
/// Every case failed at the assertion marked TARGET against Landing
/// Order step 1's tree, the pure restructuring where the store carries a
/// span array and every span in it is 1, with every setup sanity
/// assertion before it passing.
///
/// Clock cadence: a case installs, pumps once with no duration (the
/// install frame; a ticker's first tick reports elapsed zero), then pumps
/// durations, so "at 100ms" means that second pump.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const Key _frameKey = ValueKey<String>("board-frame");

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

Key _cellKey(int row, int col) {
  return ValueKey<String>("c${row}_$col");
}

const BoardAnimationSpec _ms200 = BoardAnimationSpec(
  duration: Duration(milliseconds: 200),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// itemEnterExit alone. trackResize is ZERO on purpose: a content-sized
/// row then measures the cluster term ITSELF on every frame rather than a
/// trackResize interpolation toward it, which is what lets T13 read the
/// term's own value mid-ramp.
const BoardAnimationStyle _exitOnly = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _zero,
  itemEnterExit: _ms200,
  makeRoom: _zero,
);

/// FIXED-LANE: eight 20px rows (the SWEEP axis), seven 40px columns
/// carrying the lane extent (the LANE axis, fixed). A four-lane cluster
/// slices a column into `(40 - 4) / 4 = 9`, so one slice is 9, three are
/// 27 and lane 1's origin is `4 + 9 = 13` from the column's leading edge.
BoardController<String, _Item> _fixedLane(
  WidgetTester tester, {
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(8, 20.0)),
    columns: BoardAxisConfig(
      axis: UniformAxis(7, 40.0),
      laneExtent: 18.0,
      lanePadding: 4.0,
    ),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// CONTENT-LANE: six content-sized rows carrying the lane extent (the
/// LANE axis), seven 40px columns (the SWEEP axis). The 80.0 is
/// `LazyContentAxis`'s ESTIMATE for an unmeasured track and not a floor,
/// so it never enters the numbers below; the cellBuilder's 20 is what a
/// row measures with no cluster in it.
BoardController<String, _Item> _contentLane(
  WidgetTester tester, {
  BoardAnimationStyle style = BoardAnimationStyle.disabled,
}) {
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
              return SizedBox(
                key: _cellKey(cell.row, cell.col),
                width: 40.0,
                height: 20.0,
              );
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
  );
}

/// THE AC1 SET as ROW intervals in column 2, for the FIXED-LANE fixture:
/// A [0, 7), B [1, 4), C [2, 4), D [2, 4), E [4, 6). The resolve assigns
/// A 0, B 1, C 2, D 3, E 1 with laneCount 4 for all five; C and D share
/// an interval and are separated by the sort's id tie-break, which is why
/// they are added in that order.
void _addAc1Rows(BoardController<String, _Item> controller) {
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 0, colStart: 2, rowSpan: 7),
  );
  controller.addItem(
    const _Item("b"),
    const BoardSpan(rowStart: 1, colStart: 2, rowSpan: 3),
  );
  controller.addItem(
    const _Item("c"),
    const BoardSpan(rowStart: 2, colStart: 2, rowSpan: 2),
  );
  controller.addItem(
    const _Item("d"),
    const BoardSpan(rowStart: 2, colStart: 2, rowSpan: 2),
  );
  controller.addItem(
    const _Item("e"),
    const BoardSpan(rowStart: 4, colStart: 2, rowSpan: 2),
  );
}

/// THE AC1 SET as COLUMN intervals in row 2, for the CONTENT-LANE
/// fixture. Same five intervals, same assignment; the sweep axis is the
/// columns there.
void _addAc1Cols(BoardController<String, _Item> controller) {
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 2, colStart: 0, colSpan: 7),
  );
  controller.addItem(
    const _Item("b"),
    const BoardSpan(rowStart: 2, colStart: 1, colSpan: 3),
  );
  controller.addItem(
    const _Item("c"),
    const BoardSpan(rowStart: 2, colStart: 2, colSpan: 2),
  );
  controller.addItem(
    const _Item("d"),
    const BoardSpan(rowStart: 2, colStart: 2, colSpan: 2),
  );
  controller.addItem(
    const _Item("e"),
    const BoardSpan(rowStart: 2, colStart: 4, colSpan: 2),
  );
}

double _rowExtent(WidgetTester tester, int row) {
  return tester.getRect(find.byKey(_cellKey(row, 0))).height;
}

void main() {
  // T4 (AC2). Falsification: red against step 1's tree, where E measures
  // one slice of 9 rather than the three its band covers.
  testWidgets("a laned item paints its whole band on a fixed lane axis", (
    tester,
  ) async {
    final controller = _fixedLane(tester);
    _addAc1Rows(controller);
    await tester.pumpWidget(_board(controller));
    await tester.pumpAndSettle();

    // Setup sanity, each falsifiable: the band arithmetic below is
    // written against THIS assignment. Perturbing E's interval to rows
    // [3, 6) moves it to lane 4 and takes laneCount to 5, which is the
    // perturbation that reddens these three.
    expect(controller.laneOf("a"), 0);
    expect(controller.laneOf("e"), 1);
    expect(controller.laneCountOf("e"), 4);

    // TARGET: E's band is lanes 1 to 3, three slices of 9.
    expect(controller.laneSpanOf("e"), 3);
    final e = tester.getRect(find.byKey(_itemKey("e")));
    final frame = tester.getRect(find.byKey(_frameKey));
    expect(e.width, closeTo(27.0, 0.01));
    // P4's ORIGIN half: the span enters the extent and NOT the lead, so
    // an expanded item still starts at its own lane's origin,
    // `4 + 1 * 9` past column 2's leading edge. Green before the change
    // as well as after, which is exactly what it is here to pin: a span
    // leaked into the origin would move this to 80 + 4 and leave the
    // width right.
    expect(e.left - frame.left, closeTo(93.0, 0.01));

    // A is blocked by B one lane up and keeps one slice.
    expect(controller.laneSpanOf("a"), 1);
    expect(
      tester.getSize(find.byKey(_itemKey("a"))).width,
      closeTo(9.0, 0.01),
    );
  });

  // T5 (AC3). Falsification: the first two TARGET assertions are red
  // against step 1's tree, where E measures one lane extent of 18. The
  // third is GREEN there, which is the point of asserting it: G7 says a
  // settled content-sized track measures exactly what it measured
  // before, and the C7 rewrite has to leave it alone.
  testWidgets(
    "a laned item paints its whole band on a content-sized lane axis and "
    "the track measures the same",
    (tester) async {
      final controller = _contentLane(tester);
      _addAc1Cols(controller);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();

      // Setup sanity: the cluster is the four-lane one the 76 below is
      // an accident of otherwise.
      expect(controller.laneOf("e"), 1);
      expect(controller.laneCountOf("e"), 4);

      // TARGET: three lane extents for E, one for A.
      expect(controller.laneSpanOf("e"), 3);
      expect(
        tester.getSize(find.byKey(_itemKey("e"))).height,
        closeTo(54.0, 0.01),
      );
      expect(
        tester.getSize(find.byKey(_itemKey("a"))).height,
        closeTo(18.0, 0.01),
      );
      // G7: lanePadding + laneCount * laneExtent, unchanged.
      expect(_rowExtent(tester, 2), closeTo(76.0, 0.01));
      // A row with no cluster keeps its cells-only measurement, so the
      // 76 is the term and not the frame.
      expect(_rowExtent(tester, 0), closeTo(20.0, 0.01));
    },
  );

  // T13 (C7). The DISCRIMINATING assertion is the one at 100ms: the
  // install-frame 76 and the settled 58 hold with or without C7's span
  // factor. Against a scratch variant of C7 that keeps
  // `progress * laneExtent` with no span factor, E contributes 36
  // instead of 72, the term is `54 + 18p`, and the 100ms reading is
  // `4 + 63 = 67`.
  testWidgets(
    "an exiting top-lane member does not shrink a track under an "
    "expanded band",
    (tester) async {
      final controller = _contentLane(tester, style: _exitOnly);
      _addAc1Cols(controller);
      await tester.pumpWidget(_board(controller));
      await tester.pumpAndSettle();
      expect(_rowExtent(tester, 2), closeTo(76.0, 0.01));

      controller.removeItem("d");
      await tester.pump();

      // Setup sanity, each falsifiable: D is EXITING rather than gone
      // (an itemEnterExit of zero would retire it in this pump and
      // redden this), D's assignment is held whole so the cluster is
      // still four lanes deep, and E's band is the three lanes the term
      // has to hold.
      expect(controller.anim.isExitingItem(controller.idOfKey("d")), isTrue);
      expect(controller.laneCountOf("e"), 4);
      expect(controller.laneSpanOf("e"), 3);

      // TARGET: the row holds 76 for the whole ramp. D's ceiling decays
      // from 72 to 54 while E's stays at `1 * 18 + 3 * 18 = 72`.
      expect(_rowExtent(tester, 2), closeTo(76.0, 0.01));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_rowExtent(tester, 2), closeTo(76.0, 0.01));

      // After the settle the cluster is three lanes deep, E's band is
      // two, and the deepest ceiling is `1 * 18 + 2 * 18 = 54`.
      await tester.pumpAndSettle();
      expect(controller.laneCountOf("e"), 3);
      expect(controller.laneSpanOf("e"), 2);
      expect(_rowExtent(tester, 2), closeTo(58.0, 0.01));
    },
  );
}
