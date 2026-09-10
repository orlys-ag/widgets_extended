/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 12.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_drag_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  required BoardAxis rows,
  required BoardAxis columns,
  double? rowLaneExtent,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: rows,
      laneExtent: rowLaneExtent,
      lanePadding: rowLaneExtent == null ? 0.0 : 4.0,
    ),
    columns: BoardAxisConfig(axis: columns),
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
  ScrollController? vertical,
  double Function(int row)? cellHeight,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280.0,
          height: 300.0,
          child: Board<String, _Item>(
            controller: controller,
            verticalDetails: vertical == null
                ? const ScrollableDetails.vertical()
                : ScrollableDetails.vertical(controller: vertical),
            cellBuilder: (context, cell) {
              return SizedBox(
                width: 40.0,
                height: cellHeight == null ? 50.0 : cellHeight(cell.row),
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

RenderBoardViewport<String> _viewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

void main() {
  // AC7 zero track counts.
  // Asserts: both axes at 0, then each at 0 separately;
  // tester.takeException() is null and a tap in the middle resolves to
  // nothing.
  // Falsification: none stated separately in the plan; the assertions above
  // are the check.
  testWidgets(
    "a board with trackCount 0 lays out, paints and hit-tests",
    (tester) async {
      Future<void> pumpAndProbe(BoardAxis rows, BoardAxis columns) async {
        final controller = _controller(tester, rows: rows, columns: columns);
        await tester.pumpWidget(_board(controller));
        expect(tester.takeException(), isNull);
        final viewport = _viewport(tester);
        expect(viewport.cellAt(const Offset(140.0, 150.0)), isNull);
        expect(viewport.itemAt(const Offset(140.0, 150.0)), isNull);
        await tester.tapAt(const Offset(140.0, 150.0));
        await tester.pump();
        expect(tester.takeException(), isNull);
        // A fresh subtree per arm, so the next arm builds its own.
        await tester.pumpWidget(const SizedBox());
      }

      await pumpAndProbe(UniformAxis(0, 50.0), UniformAxis(0, 40.0));
      await pumpAndProbe(UniformAxis(0, 50.0), UniformAxis(7, 40.0));
      await pumpAndProbe(UniformAxis(6, 50.0), UniformAxis(0, 40.0));
    },
  );

  // DERIVED name. I19's shrinking maxScrollExtent: with EVERY track
  // already measured, re-measuring only the visible ones smaller leaves
  // the honored false return of applyContentDimensions as the ONLY
  // driver of a second pass; nothing measures a new track.
  // Asserts: no exception, the shrink frame ran a second pass, and the
  // position ends clamped inside the new extent.
  testWidgets("an axis whose maxScrollExtent shrinks mid-scroll", (
    tester,
  ) async {
    var shrunk = false;
    final controller = _controller(
      tester,
      rows: LazyContentAxis(30, 100.0),
      columns: UniformAxis(7, 40.0),
      rowLaneExtent: 18.0,
    );
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(
      _board(
        controller,
        vertical: vertical,
        cellHeight: (row) {
          return shrunk && row >= 27 ? 20.0 : 100.0;
        },
      ),
    );
    // Measure every track with a stepped sweep to the bottom.
    for (var offset = 250.0; offset <= 2700.0; offset += 250.0) {
      vertical.jumpTo(offset);
      await tester.pump();
    }
    vertical.jumpTo(2700.0);
    await tester.pump();
    // Setup sanity: nothing left to measure, and the scroll is deep.
    expect((controller.rows.axis as LazyContentAxis).isProvisional, isFalse);
    expect(vertical.offset, 2700.0);

    // Any structural change rebuilds every mounted cell, so the three
    // visible tracks re-measure at a fifth of their extent this frame.
    shrunk = true;
    controller.addItem(
      const _Item("x"),
      const BoardSpan(rowStart: 0, colStart: 0),
    );
    await tester.pump();
    // Read on the SHRINK frame: the pass count is per layout.
    final viewport = _viewport(tester);
    expect(viewport.debugLastCorrectionPassCount, greaterThanOrEqualTo(2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      vertical.offset,
      lessThanOrEqualTo(vertical.position.maxScrollExtent),
    );
    expect(vertical.offset, lessThan(2700.0));
  });

  // DERIVED name. R-9's mitigation: the axis asserts the documented
  // totalExtent ceiling rather than silently losing pixels past it.
  // Asserts: a total AT the ceiling constructs and scrolls without
  // exception; one past it dies on the documented assert, in every
  // implementation whose total is known at construction.
  testWidgets("an axis at the documented totalExtent ceiling", (
    tester,
  ) async {
    // 1e6 tracks of 1e6 px: exactly the 1e12 ceiling.
    final controller = _controller(
      tester,
      rows: UniformAxis(1000000, 1000000.0),
      columns: UniformAxis(3, 40.0),
    );
    final vertical = ScrollController();
    addTearDown(vertical.dispose);
    await tester.pumpWidget(_board(controller, vertical: vertical));
    vertical.jumpTo(vertical.position.maxScrollExtent);
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(() {
      UniformAxis(1000001, 1000000.0);
    }, throwsAssertionError);
    expect(() {
      ExplicitAxis(<double>[BoardAxis.maxTotalExtent, 1.0]);
    }, throwsAssertionError);
    expect(() {
      DerivedAxis(2, (track) {
        return BoardAxis.maxTotalExtent / 2.0 + 1.0;
      });
    }, throwsAssertionError);
    expect(() {
      LazyContentAxis(2, BoardAxis.maxTotalExtent / 2.0 + 1.0);
    }, throwsAssertionError);
  });

  // DERIVED name. I21's axis swap.
  // Asserts: no exception, the measured set is dropped (the new
  // LazyContentAxis reports isProvisional true), and an item whose span
  // names a track past the new count stays in the store and is simply
  // unbuilt.
  testWidgets(
    "assigning a BoardAxisConfig with a smaller trackCount mid-scroll "
    "leaves no exception",
    (tester) async {
      final controller = _controller(
        tester,
        rows: LazyContentAxis(30, 100.0),
        columns: UniformAxis(7, 40.0),
        rowLaneExtent: 18.0,
      );
      controller.addItem(
        const _Item("deep"),
        const BoardSpan(rowStart: 20, colStart: 1),
      );
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        _board(
          controller,
          vertical: vertical,
          cellHeight: (row) {
            return 100.0;
          },
        ),
      );
      vertical.jumpTo(1800.0);
      await tester.pump();
      // Setup sanity: the deep item is built.
      expect(
        find.byKey(_itemKey("deep"), skipOffstage: false),
        findsOneWidget,
      );

      final original = controller.rows.axis as LazyContentAxis;
      final replacement = LazyContentAxis(10, 100.0);
      controller.rows = BoardAxisConfig(
        axis: replacement,
        laneExtent: 18.0,
        lanePadding: 4.0,
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(controller.contains("deep"), isTrue);
      expect(
        controller.spanOf("deep"),
        const BoardSpan(rowStart: 20, colStart: 1),
      );
      expect(
        find.byKey(_itemKey("deep"), skipOffstage: false),
        findsNothing,
      );
      expect(
        vertical.offset,
        lessThanOrEqualTo(vertical.position.maxScrollExtent),
      );

      // The measured-set drop, discriminated on a REWRAPPED instance: a
      // fresh replacement is provisional whether or not any reset runs,
      // so the pin is the original axis, measured at the first pump and
      // reassigned inside a new config.
      expect(original.isMeasured(0), isTrue);
      controller.rows = BoardAxisConfig(
        axis: original,
        laneExtent: 18.0,
        lanePadding: 4.0,
      );
      await tester.pump();
      expect(original.isMeasured(0), isFalse);
    },
  );

  // DERIVED name. The axis-swap resize snap is scoped to the SWAPPED
  // axis: a column swap invalidates nothing a row resize is animating
  // against, so the row's in-flight extent survives it.
  // Asserts: the mid-flight track extent right after the column swap is
  // still above the settled target it lands on.
  testWidgets(
    "a column swap leaves a row trackResize in flight",
    (tester) async {
      final controller = _controller(
        tester,
        rows: LazyContentAxis(3, 60.0),
        columns: UniformAxis(7, 40.0),
        rowLaneExtent: 18.0,
      );
      controller.animationStyle = const BoardAnimationStyle(
        trackResize: BoardAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
        itemSlide: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
        itemEnterExit: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
      );
      controller.addItem(
        const _Item("a"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
      );
      controller.addItem(
        const _Item("b"),
        const BoardSpan(rowStart: 0, colStart: 0, colSpan: 2),
      );
      // Short cells, so the lane cluster is what sizes the track and the
      // de-lane shrink genuinely animates.
      await tester.pumpWidget(
        _board(
          controller,
          cellHeight: (row) {
            return 20.0;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Dropping one lane shrinks the track; catch it mid-flight.
      controller.removeItem("b");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final viewport = _viewport(tester);
      final midFlight = viewport.rectOfCell(0, 0)!.height;

      controller.columns = BoardAxisConfig(axis: UniformAxis(8, 40.0));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final afterSwap = viewport.rectOfCell(0, 0)!.height;

      await tester.pumpAndSettle();
      final settled = viewport.rectOfCell(0, 0)!.height;
      // Setup sanity: the resize was genuinely mid-flight.
      expect(midFlight, greaterThan(settled));
      // The surviving flight: still above the settled target after the
      // swap, not snapped to it.
      expect(afterSwap, greaterThan(settled));
    },
  );

  // DERIVED name. I21's axis-swap arm against RETENTION: the window rule
  // never queries an out-of-lattice span, but the retained obtain does
  // not go through the window, and the laned geometry arm reads the raw
  // start track. A lattice shrunk under a retained exit must RELEASE the
  // entry, not lay it out.
  // Asserts: no exception on the swap frame, the retained probe is gone,
  // and the board settles clean.
  testWidgets(
    "an axis swap smaller than a retained exit's span releases it",
    (tester) async {
      final controller = _controller(
        tester,
        rows: LazyContentAxis(30, 100.0),
        columns: UniformAxis(7, 40.0),
        rowLaneExtent: 18.0,
      );
      controller.animationStyle = const BoardAnimationStyle(
        trackResize: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
        itemSlide: BoardAnimationSpec(
          duration: Duration.zero,
          curve: Curves.linear,
        ),
        itemEnterExit: BoardAnimationSpec(
          duration: Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      );
      controller.addItem(
        const _Item("deep"),
        const BoardSpan(rowStart: 20, colStart: 1),
      );
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        _board(
          controller,
          vertical: vertical,
          cellHeight: (row) {
            return 100.0;
          },
        ),
      );
      vertical.jumpTo(1800.0);
      await tester.pumpAndSettle();
      controller.removeItem("deep");
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Setup sanity: the exit is retained.
      expect(
        find.byKey(_itemKey("deep"), skipOffstage: false),
        findsOneWidget,
      );

      controller.rows = BoardAxisConfig(
        axis: LazyContentAxis(10, 100.0),
        laneExtent: 18.0,
        lanePadding: 4.0,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(_itemKey("deep"), skipOffstage: false),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  // DERIVED name. The drag pin's sibling of the case above: the pin
  // obtain re-derives the dragged item's vicinity every layout, and a
  // lattice shrunk under it must skip the obtain rather than lay the
  // item out past the axis.
  // Asserts: no exception on the swap frame, and the session still ends
  // cleanly.
  testWidgets(
    "an axis swap smaller than the dragged item's span throws nothing",
    (tester) async {
      final controller = _controller(
        tester,
        rows: LazyContentAxis(30, 100.0),
        columns: UniformAxis(7, 40.0),
        rowLaneExtent: 18.0,
      );
      controller.addItem(
        const _Item("deep"),
        const BoardSpan(rowStart: 20, colStart: 1),
      );
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        _board(
          controller,
          vertical: vertical,
          cellHeight: (row) {
            return 100.0;
          },
        ),
      );
      vertical.jumpTo(1800.0);
      await tester.pump();
      final drag = BoardDragController<String>(
        boardController: controller,
        vsync: tester,
        config: BoardDragConfig<String>(onItemMoved: (key, span) {}),
      );
      addTearDown(drag.dispose);
      expect(
        drag.startDrag(
          key: "deep",
          renderPort: _viewport(tester),
          pointerGlobal: const Offset(60.0, 250.0),
        ),
        isTrue,
      );
      await tester.pump();

      controller.rows = BoardAxisConfig(
        axis: LazyContentAxis(10, 100.0),
        laneExtent: 18.0,
        lanePadding: 4.0,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      drag.endDrag(cancel: true);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.isDragging("deep"), isFalse);
    },
  );

  // Cell measurement invalidation plan, T2 (D1).
  // Asserts: the door is a no-op before any board is mounted and again
  // after the board is pumped away, with the controller LIVE both times.
  // Falsification: red against an implementation that dereferences the
  // null port.
  testWidgets(
    "invalidateCellMeasurements is a no-op with no board mounted",
    (tester) async {
      final controller = _controller(
        tester,
        rows: LazyContentAxis(6, 50.0),
        columns: UniformAxis(7, 40.0),
      );
      controller.invalidateCellMeasurements();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_board(controller));
      expect(controller.rows.axis.extentOf(0), 50.0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.allRenderObjects.whereType<RenderBoardViewport<String>>(),
          isEmpty);
      controller.invalidateCellMeasurements();
      expect(tester.takeException(), isNull);
    },
  );
}
