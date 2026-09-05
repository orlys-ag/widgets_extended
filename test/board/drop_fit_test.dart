/// Tests for the drop fit plan.
///
/// Source: `plans/2026-09-04-drop-fit-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM.
///
/// A UNIT file rather than widget cases: the gate and the scan are pure
/// functions over rectangles and two axes, so driving them through a
/// pumped board would test the wiring instead of the rule, need a gesture
/// per case, and hide which of the two halves failed. Same seam as
/// `span_index_test.dart`, `overlap_lanes_test.dart` and
/// `fenwick_test.dart`, each of which reaches an unexported component by
/// importing its library directly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_drop_fit.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_config.dart';

bool _always(BoardSpan span) {
  return true;
}

void main() {
  test("an empty box is entirely free", () {
    expect(
      BoardDropFitter.freeFractionOf(
        box: const BoardSpan(rowStart: 0, colStart: 0),
        obstacles: const <BoardSpan>[],
        rowAxis: UniformAxis(4, 10.0),
        colAxis: UniformAxis(4, 10.0),
      ),
      1.0,
    );
  });

  test("a box its occupant covers is entirely occupied", () {
    expect(
      BoardDropFitter.freeFractionOf(
        box: const BoardSpan(rowStart: 1, colStart: 1),
        obstacles: const <BoardSpan>[BoardSpan(rowStart: 1, colStart: 1)],
        rowAxis: UniformAxis(4, 10.0),
        colAxis: UniformAxis(4, 10.0),
      ),
      0.0,
    );
  });

  // The union case. Two occupants overlapping EACH OTHER inside the box
  // cover 300 of its 400 square pixels, so a quarter survives; summing
  // their areas instead reports 400 covered and no free area at all.
  test("two overlapping occupants are counted once", () {
    expect(
      BoardDropFitter.freeFractionOf(
        box: const BoardSpan(rowStart: 0, colStart: 0, rowSpan: 2, colSpan: 2),
        obstacles: const <BoardSpan>[
          BoardSpan(rowStart: 0, colStart: 0, rowSpan: 2, colSpan: 1),
          BoardSpan(rowStart: 0, colStart: 0, rowSpan: 1, colSpan: 2),
        ],
        rowAxis: UniformAxis(4, 10.0),
        colAxis: UniformAxis(4, 10.0),
      ),
      0.25,
    );
  });

  // Columns 10 and 90 wide: an occupant over the narrow one leaves nine
  // tenths of the box, where counting cells would say a half.
  test("the free share is measured in pixels, not in cells", () {
    expect(
      BoardDropFitter.freeFractionOf(
        box: const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
        obstacles: const <BoardSpan>[BoardSpan(rowStart: 0, colStart: 0)],
        rowAxis: UniformAxis(1, 10.0),
        colAxis: ExplicitAxis(<double>[10.0, 90.0]),
      ),
      0.9,
    );
  });

  test("a fractional occupant covers exactly its fraction", () {
    expect(
      BoardDropFitter.freeFractionOf(
        box: const BoardSpan(rowStart: 0, colStart: 0),
        obstacles: const <BoardSpan>[
          BoardSpan(rowStart: 0, colStart: 0, colSpan: 0, colSpanFraction: 0.5),
        ],
        rowAxis: UniformAxis(2, 10.0),
        colAxis: UniformAxis(2, 10.0),
      ),
      0.5,
    );
  });

  // Columns 10, 10, 10, 200, 10, with the box on the wide one. Stepping
  // one column forward costs 200 pixels; stepping two back costs 20. A
  // scan ordered by track COUNT takes the forward one, which is what
  // this rejects. Column 2 is occupied so the one-step-back candidate,
  // nearer than both, is not available.
  test("the nearest fit is nearest in pixels", () {
    final answer = BoardDropFitter.nearestFit(
      box: const BoardSpan(rowStart: 0, colStart: 3),
      policy: const BoardDropFit(rowRadius: 0.0, colRadius: 2.0),
      snap: const BoardSnap.track(),
      rowAxis: UniformAxis(1, 10.0),
      colAxis: ExplicitAxis(<double>[10.0, 10.0, 10.0, 200.0, 10.0]),
      obstacles: const <BoardSpan>[BoardSpan(rowStart: 0, colStart: 2)],
      accepts: _always,
    );
    expect(answer, isNotNull);
    expect(answer!.colStart, 1);
  });

  test("nothing within the radius returns null", () {
    expect(
      BoardDropFitter.nearestFit(
        box: const BoardSpan(rowStart: 0, colStart: 1),
        policy: const BoardDropFit(rowRadius: 0.0, colRadius: 1.0),
        snap: const BoardSnap.track(),
        rowAxis: UniformAxis(1, 10.0),
        colAxis: UniformAxis(3, 10.0),
        obstacles: const <BoardSpan>[
          BoardSpan(rowStart: 0, colStart: 0),
          BoardSpan(rowStart: 0, colStart: 2),
        ],
        accepts: _always,
      ),
      isNull,
    );
  });

  // The nearest free candidate is column 0 and the predicate refuses it,
  // so the answer is column 2, which it admits.
  test("a candidate the predicate refuses is skipped", () {
    final answer = BoardDropFitter.nearestFit(
      box: const BoardSpan(rowStart: 0, colStart: 1),
      policy: const BoardDropFit(rowRadius: 0.0, colRadius: 1.0),
      snap: const BoardSnap.track(),
      rowAxis: UniformAxis(1, 10.0),
      colAxis: UniformAxis(3, 10.0),
      obstacles: const <BoardSpan>[],
      accepts: (span) {
        return span.colStart != 0;
      },
    );
    expect(answer, isNotNull);
    expect(answer!.colStart, 2);
  });

  // The box sits at column 2 plus three quarters and steps by a quarter
  // track, so its forward candidate lands exactly on column 3. The
  // backward one is blocked, which is what forces the forward answer.
  // An implementation that adds the step to the fraction field produces
  // a leading fraction of 1.0 and throws on BoardSpan's own assert.
  test("a fractional step that crosses a track boundary re-splits", () {
    final answer = BoardDropFitter.nearestFit(
      box: const BoardSpan(rowStart: 0, colStart: 2, colFraction: 0.75),
      policy: const BoardDropFit(rowRadius: 0.0, colRadius: 0.25),
      snap: const BoardSnap.fraction(0.25),
      rowAxis: UniformAxis(1, 10.0),
      colAxis: UniformAxis(5, 10.0),
      obstacles: const <BoardSpan>[
        BoardSpan(
          rowStart: 0,
          colStart: 2,
          colFraction: 0.5,
          colSpan: 0,
          colSpanFraction: 0.5,
        ),
      ],
      accepts: _always,
    );
    expect(answer, isNotNull);
    expect(answer!.colStart, 3);
    expect(answer.colFraction, 0.0);
  });
}
