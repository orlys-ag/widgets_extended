/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 9 with the animation sources.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const BoardAnimationSpec _ms300 = BoardAnimationSpec(
  duration: Duration(milliseconds: 300),
  curve: Curves.linear,
);

const BoardAnimationSpec _zero = BoardAnimationSpec(
  duration: Duration.zero,
  curve: Curves.linear,
);

/// Slides animate; everything else is off.
const BoardAnimationStyle _slideOnly = BoardAnimationStyle(
  trackResize: _zero,
  itemSlide: _ms300,
);

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

Widget _board(
  BoardController<String, _Item> controller, {
  double width = 280.0,
  double height = 400.0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: height,
          child: Board<String, _Item>(
            controller: controller,
            cellBuilder: (context, cell) {
              return const SizedBox(width: 40.0, height: 20.0);
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

RenderBoardViewport<String> _viewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

BoardSpan _chip(int row, int colStart, int colSpan) {
  return BoardSpan(rowStart: row, colStart: colStart, colSpan: colSpan);
}

void main() {
  // AC15 paint-only tick.
  // Asserts: debugPerformLayoutCount unchanged across a mid-slide pump,
  // and debugCorrectionCount unchanged with it, which is the second
  // half: no layout means no correction loop.
  testWidgets("a frame with only itemSlide active repaints without laying "
      "out", (tester) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: _slideOnly,
    );
    addTearDown(controller.dispose);
    controller.addItem(const _Item("m"), _chip(0, 0, 2));
    await tester.pumpWidget(_board(controller));

    controller.moveItem("m", _chip(3, 0, 2));
    // The install frame lays out (the mutation is structural); the
    // mid-slide ticks after it are what AC15 is about.
    await tester.pump();
    final viewport = _viewport(tester);
    final layouts = viewport.debugPerformLayoutCount;
    final corrections = viewport.debugCorrectionCount;
    // Setup sanity: genuinely mid-slide.
    final id = controller.idOfKey("m");
    await tester.pump(const Duration(milliseconds: 60));
    expect(controller.anim.offsetOfItem(id), isNot(Offset.zero));
    await tester.pump(const Duration(milliseconds: 60));
    expect(viewport.debugPerformLayoutCount, layouts);
    expect(viewport.debugCorrectionCount, corrections);
    await tester.pumpAndSettle();
  });

  // DERIVED name. No AC; the ONLY assertion for the applyPaintTransform
  // pair, whose green signal step 6 deferred to this step.
  // Asserts: mid-slide, with a known non-zero offsetOfItem, tester.getRect
  // of the item's probe (which goes through applyPaintTransform) equals
  // the structural rect displaced by exactly that offset.
  // Falsification: the base implementation translates by paintOffset
  // alone and is off by exactly the animation offset.
  testWidgets("a mid-slide item's localToGlobal matches where it paints", (
    tester,
  ) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: _slideOnly,
    );
    addTearDown(controller.dispose);
    controller.addItem(const _Item("m"), _chip(0, 0, 2));
    await tester.pumpWidget(_board(controller));

    controller.moveItem("m", _chip(0, 4, 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final id = controller.idOfKey("m");
    final offset = controller.anim.offsetOfItem(id);
    // Setup sanity: a known non-zero mid-slide offset.
    expect(offset.dx, lessThan(0.0));
    final rect = tester.getRect(find.byKey(_itemKey("m")));
    // Structural: column 4 of 40s; painted: displaced by the offset.
    expect(rect.left, closeTo(160.0 + offset.dx, 1e-6));
    expect(rect.top, closeTo(0.0 + offset.dy, 1e-6));
    await tester.pumpAndSettle();
  });

  // DERIVED name. No AC; the falsifiable check for the per-axis offset
  // bound, and the only place the plan asserts a built-child bound under
  // an active offset.
  // Asserts: with a held makeRoom offset whose dy is several track
  // extents and whose dx is 0, the built columns are IDENTICAL to the
  // no-offset baseline while the built rows grew.
  // Falsification: a single scalar bound admits dy worth of columns as
  // well and widens the column set.
  testWidgets(
    "a large vertical make-room offset does not widen the horizontal "
    "window",
    (tester) async {
      final controller = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(
          axis: LazyContentAxis(30, 22.0),
          laneExtent: 100.0,
          lanePadding: 4.0,
        ),
        // Enough columns that the cache band does NOT already admit them
        // all, or the column set cannot grow and the equality is inert.
        columns: BoardAxisConfig(axis: UniformAxis(30, 40.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(controller.dispose);
      controller.addItem(const _Item("a"), _chip(0, 2, 2));
      controller.addItem(const _Item("b"), _chip(0, 2, 2));
      controller.addItem(const _Item("d"), _chip(3, 0, 2));
      await tester.pumpWidget(_board(controller, height: 200.0));
      // One more layout, so the children the first frame over-obtained
      // under the raw estimates are released before the baseline count.
      await tester.pumpWidget(_board(controller, height: 200.0));
      final viewport = _viewport(tester);

      ({Set<int> rows, Set<int> cols}) built() {
        final rows = <int>{};
        final cols = <int>{};
        viewport.visitChildren((child) {
          final vicinity =
              (child.parentData! as TwoDimensionalViewportParentData)
                  .vicinity;
          if (vicinity.xIndex < 30) {
            rows.add(vicinity.yIndex);
            cols.add(vicinity.xIndex);
          }
        });
        return (rows: rows, cols: cols);
      }

      final before = built();
      controller.previewMakeRoomGap(
        draggedKey: "d",
        prospective: _chip(0, 0, 3),
      );
      await tester.pump();
      // Setup sanity: the held offset is one full lane extent, vertical.
      expect(
        controller.anim.offsetOfItem(controller.idOfKey("a")),
        const Offset(0.0, 100.0),
      );
      final after = built();
      expect(after.cols, before.cols);
      expect(after.rows.length, greaterThan(before.rows.length));

      controller.releaseMakeRoomPreview();
      await tester.pump();
    },
  );

  // DERIVED name. No AC; the falsifiable case for the slide delta's
  // derivation and its capture ordering, which nothing else reaches.
  // Asserts: moveItem a settled item to a different primary track under
  // a non-zero itemSlide and assert on the frame of the call, with no
  // pump, that offsetOfItem is non-zero and equals the old content-space
  // corner minus the new one on both axes. A second arm moves an item
  // whose LANE changes but whose track does not.
  // Falsification: a mutator that writes the span before capturing the
  // old corner produces exactly zero and fails the first half; one that
  // reads the new corner's lane term from the raw arrays instead of
  // through the read API produces the PRE-mutation lane and fails the
  // second half while passing the first.
  testWidgets(
    "a moveItem across tracks installs a slide whose delta is the "
    "position change",
    (tester) async {
      final plain = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
        columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: _slideOnly,
      );
      addTearDown(plain.dispose);
      plain.addItem(const _Item("m"), _chip(0, 0, 2));
      await tester.pumpWidget(_board(plain));

      // Arm 1: a cross-track move. Old corner (0, 0), new (160, 150).
      plain.moveItem("m", _chip(3, 4, 2));
      expect(
        plain.anim.offsetOfItem(plain.idOfKey("m")),
        const Offset(-160.0, -150.0),
      );
      await tester.pumpAndSettle();

      // Arm 2: a lane change with an unchanged track. Moving b onto a
      // re-lanes it into lane 1, so the delta's lane-axis half is one
      // POST-mutation lane extent.
      final laned = BoardController<String, _Item>(
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
        animationStyle: _slideOnly,
      );
      addTearDown(laned.dispose);
      laned.addItem(const _Item("a"), _chip(0, 0, 3));
      laned.addItem(const _Item("b"), _chip(0, 3, 3));
      await tester.pumpWidget(_board(laned));
      // Setup sanity: disjoint chips, both lane 0.
      expect(laned.laneOf("b"), 0);

      laned.moveItem("b", _chip(0, 0, 3));
      expect(laned.laneOf("b"), 1);
      // dx: from column 3 (120) to column 0; dy: from lane 0 to lane 1,
      // one lane extent DOWN, so the old-minus-new difference is -18.
      expect(
        laned.anim.offsetOfItem(laned.idOfKey("b")),
        const Offset(120.0, -18.0),
      );
      await tester.pumpAndSettle();
    },
  );
}
