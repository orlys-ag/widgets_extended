/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 8: the background painter, the geometry
/// view, and the paint override's first pass.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_background.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

/// Records every [paint] call and the bounds the geometry reported.
class _ProbePainter extends BoardBackgroundPainter {
  const _ProbePainter(this.log);

  final List<({int firstRow, int lastRow, int firstCol, int lastCol})> log;

  @override
  void paint(Canvas canvas, BoardGeometryView geometry) {
    log.add((
      firstRow: geometry.firstVisibleRow,
      lastRow: geometry.lastVisibleRow,
      firstCol: geometry.firstVisibleCol,
      lastCol: geometry.lastVisibleCol,
    ));
  }

  @override
  bool shouldRepaint(_ProbePainter old) {
    return !identical(old.log, log);
  }
}

/// Counts canvas calls by member name; every other behavior is a no-op.
class _RecordingCanvas implements Canvas {
  final Map<Symbol, int> calls = <Symbol, int>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls[invocation.memberName] = (calls[invocation.memberName] ?? 0) + 1;
    return null;
  }
}

/// A fixed lattice for the grid painter's unit case: 4 visible rows of 50
/// by 3 visible columns of 100, anchored at the origin.
class _FakeGeometry implements BoardGeometryView {
  const _FakeGeometry();

  @override
  int get firstVisibleRow {
    return 0;
  }

  @override
  int get lastVisibleRow {
    return 3;
  }

  @override
  int get firstVisibleCol {
    return 0;
  }

  @override
  int get lastVisibleCol {
    return 2;
  }

  @override
  Rect visibleCellRect(int row, int col) {
    return Rect.fromLTWH(col * 100.0, row * 50.0, 100.0, 50.0);
  }

  @override
  Size get viewportDimension {
    return const Size(300.0, 200.0);
  }

  @override
  double frozenInsetOf(Axis axis) {
    return 0.0;
  }
}

/// Four rows of extent 51.3 shifted by 137.7, three columns of 100: the
/// row rects reproduce the render object's two-expression edges (top from
/// the offset, bottom as top plus extent), and the boundary between rows
/// 2 and 3 does not compare equal across those two expressions.
class _FractionalGeometry implements BoardGeometryView {
  const _FractionalGeometry();

  @override
  int get firstVisibleRow {
    return 0;
  }

  @override
  int get lastVisibleRow {
    return 3;
  }

  @override
  int get firstVisibleCol {
    return 0;
  }

  @override
  int get lastVisibleCol {
    return 2;
  }

  @override
  Rect visibleCellRect(int row, int col) {
    return Rect.fromLTWH(col * 100.0, row * 51.3 - 137.7, 100.0, 51.3);
  }

  @override
  Size get viewportDimension {
    return const Size(300.0, 200.0);
  }

  @override
  double frozenInsetOf(Axis axis) {
    return 0.0;
  }
}

BoardController<String, _Item> _controller(WidgetTester tester) {
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
  return controller;
}

Widget _board(
  BoardController<String, _Item> controller, {
  BoardBackgroundPainter? background,
  ScrollController? vertical,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300.0,
          height: 200.0,
          child: Board<String, _Item>(
            controller: controller,
            background: background,
            verticalDetails: vertical == null
                ? const ScrollableDetails.vertical()
                : ScrollableDetails.vertical(controller: vertical),
            cellBuilder: (context, cell) {
              return const SizedBox(width: 100.0, height: 50.0);
            },
            itemBuilder: (context, item) {
              return const ColoredBox(color: Color(0xFF4CAF50));
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

int _childCount(WidgetTester tester) {
  var count = 0;
  _viewport(tester).visitChildren((child) {
    count++;
  });
  return count;
}

void main() {
  // AC4 background costs no children.
  // Asserts: the same board built with and without a background, counted by
  // walking RenderBoardViewport.visitChildren, which covers the paint chain
  // and the keep-alive bucket and needs no new seam.
  // Falsification: a widget-per-cell layer doubles that count. The count is
  // NOT taken from cellBuilder probes, because a widget-per-cell background
  // would not change the number of probes and so could not fail in the
  // direction the case claims to check.
  testWidgets(
    "adding a background painter leaves the render child count identical",
    (tester) async {
      final controller = _controller(tester);
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
      );
      await tester.pumpWidget(_board(controller));
      final without = _childCount(tester);
      // Setup sanity: cells plus the one item child.
      expect(without, greaterThan(1));

      final log =
          <({int firstRow, int lastRow, int firstCol, int lastCol})>[];
      await tester.pumpWidget(
        _board(controller, background: _ProbePainter(log)),
      );
      expect(_childCount(tester), without);
      // The painter genuinely ran: without this, a paint override that
      // drops the background pass would pass the count assertion above.
      expect(log, isNotEmpty);
    },
  );

  // DERIVED name. No AC.
  // Asserts: the geometry view reports the SCROLLED visible window, and
  // visibleCellRect agrees with rectOfCell for a cell inside it.
  // Falsification: bounds computed from the unscrolled origin report rows
  // 0..3; a visibleCellRect that skips the reversal-and-scroll helper
  // reports the content-space rect, 500 pixels off.
  testWidgets(
    "the geometry view reports the scrolled window and visibleCellRect "
    "matches rectOfCell",
    (tester) async {
      final controller = _controller(tester);
      final vertical = ScrollController(initialScrollOffset: 500.0);
      addTearDown(vertical.dispose);
      final log =
          <({int firstRow, int lastRow, int firstCol, int lastCol})>[];
      await tester.pumpWidget(
        _board(
          controller,
          background: _ProbePainter(log),
          vertical: vertical,
        ),
      );
      // Pixels 500..700 over 50-tall rows: rows 10 through 13.
      expect(log.last.firstRow, 10);
      expect(log.last.lastRow, 13);
      expect(log.last.firstCol, 0);
      expect(log.last.lastCol, 2);

      final viewport = _viewport(tester);
      expect(
        viewport.visibleCellRect(10, 1),
        viewport.rectOfCell(10, 1),
      );
      expect(
        viewport.visibleCellRect(10, 1),
        const Rect.fromLTWH(100.0, 0.0, 100.0, 50.0),
      );
    },
  );

  // DERIVED name. No AC; pins BoardGridPainter's boundary dedup and its
  // tint pass on a fake lattice of 4 rows by 3 columns.
  // Asserts: 5 row edges plus 4 column edges give exactly 9 drawLine
  // calls, and a tint on one row and one column gives exactly 2 drawRect
  // calls.
  // Falsification: drawing both edges of every track doubles the shared
  // boundaries, 14 lines; tinting every track draws 7 rects.
  test("BoardGridPainter draws each shared boundary once and tints the "
      "tracks that ask", () {
    final canvas = _RecordingCanvas();
    const painter = BoardGridPainter(
      trackTint: _tintRow1Col2,
    );
    painter.paint(canvas, const _FakeGeometry());
    expect(canvas.calls[#drawLine], 9);
    expect(canvas.calls[#drawRect], 2);
  });

  // DERIVED name. No AC; the boundary derivation under FRACTIONAL
  // geometry, where a track's bottom (top + extent) and the next track's
  // top (its own offset) are two float expressions that need not compare
  // equal. Rows 0..3 at extent 51.3 shifted by 137.7 carry one such
  // boundary (rows 2 to 3) in binary64.
  // Falsification: deduplicating by collecting BOTH edges of every track
  // into a set draws the mismatching boundary twice, 10 lines instead
  // of 9.
  test("BoardGridPainter draws one line per boundary under fractional "
      "track geometry", () {
    final canvas = _RecordingCanvas();
    const painter = BoardGridPainter();
    painter.paint(canvas, const _FractionalGeometry());
    expect(canvas.calls[#drawLine], 9);
  });

  // DERIVED name. No AC; the empty-board arm: the background still
  // paints when no child exists, and the stock painter's empty-bounds
  // guard keeps it clean of the visibleCellRect assert.
  // Falsification: a paint override that skips the background on the
  // childless early return leaves the log empty; a grid painter without
  // the guard asks for cell (0, 0) of an empty lattice and throws.
  testWidgets("an empty board still runs the background painter and the "
      "grid painter stays clean on it", (tester) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(0, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(0, 100.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    final log = <({int firstRow, int lastRow, int firstCol, int lastCol})>[];
    await tester.pumpWidget(_board(controller, background: _ProbePainter(log)));
    expect(log, isNotEmpty);
    expect(log.last.firstRow, greaterThan(log.last.lastRow));

    await tester.pumpWidget(
      _board(controller, background: const BoardGridPainter()),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  // DERIVED name. No AC; the setter's repaint routing.
  // Asserts: an equal-config painter does not dirty paint, a changed one
  // does, and null-ness changes do.
  // Falsification: a setter that always repaints fails the first arm; one
  // that only checks identity fails the second.
  testWidgets(
    "swapping the background painter repaints only when shouldRepaint "
    "says so",
    (tester) async {
      final controller = _controller(tester);
      await tester.pumpWidget(
        _board(controller, background: const BoardGridPainter()),
      );
      final viewport = _viewport(tester);

      // Same config, DISTINCT instance: no repaint. Non-const on purpose:
      // a const constructor here would canonicalize to the instance the
      // board already holds and the identical() early-return would decide
      // instead of shouldRepaint, which an earlier version of this arm
      // did not notice. The pump above left paint clean, so a false read
      // here is attributable to the setter.
      // ignore: prefer_const_constructors
      viewport.background = BoardGridPainter();
      expect(viewport.debugNeedsPaint, isFalse);

      // Changed line width: repaint.
      // ignore: prefer_const_constructors
      viewport.background = BoardGridPainter(gridLineWidth: 2.0);
      expect(viewport.debugNeedsPaint, isTrue);
      await tester.pump();

      // Different painter TYPE: repaint, decided by the runtimeType arm
      // before shouldRepaint's covariant parameter can mismatch.
      viewport.background = _ProbePainter(
        <({int firstRow, int lastRow, int firstCol, int lastCol})>[],
      );
      expect(viewport.debugNeedsPaint, isTrue);
      await tester.pump();

      // Painter removed: repaint.
      viewport.background = null;
      expect(viewport.debugNeedsPaint, isTrue);
      await tester.pump();
    },
  );
}

Color? _tintRow1Col2(Axis axis, int track) {
  if (axis == Axis.vertical && track == 1) {
    return const Color(0x11000000);
  }
  if (axis == Axis.horizontal && track == 2) {
    return const Color(0x22000000);
  }
  return null;
}
