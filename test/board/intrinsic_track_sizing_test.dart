/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 7 with the item-cluster contributor term.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_config.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_views.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key, [this.height = 40.0]);

  final String key;

  /// Cells covered by this item size themselves to it, which is what
  /// makes an `updateItem` a re-measurement trigger.
  final double height;
}

/// Cell layouts since the last reset, counted by [_CountingCell]'s render
/// object.
///
/// A TEST-LOCAL seam. It is the highest one that can observe the fact
/// under test: whether a cell's subtree was laid out is not visible from
/// the widget surface at all, and a counter in `lib/` on the render
/// object could only report layouts of the viewport, which is the number
/// that stays 1 while the cell count is the one that moves.
int cellLayouts = 0;

/// Every mounted [_CountingCell] render object, so a case can dirty one
/// without rebuilding its host.
final List<RenderCountingCell> liveCells = <RenderCountingCell>[];

/// A cell of a fixed height that counts its own layouts.
class _CountingCell extends LeafRenderObjectWidget {
  const _CountingCell(this.height, {super.key});

  final double height;

  @override
  RenderCountingCell createRenderObject(BuildContext context) {
    return RenderCountingCell(height);
  }

  @override
  void updateRenderObject(BuildContext context, RenderCountingCell render) {
    render.height = height;
  }
}

/// Public only so [liveCells] can name it; the file is a test.
class RenderCountingCell extends RenderBox {
  RenderCountingCell(this._height);

  double _height;

  /// Writing a DIFFERENT height marks this box alone dirty, which is the
  /// untracked-size-change shape T4 needs.
  set height(double value) {
    if (value == _height) {
      return;
    }
    _height = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    liveCells.add(this);
  }

  @override
  void detach() {
    liveCells.remove(this);
    super.detach();
  }

  @override
  void performLayout() {
    cellLayouts += 1;
    size = constraints.constrain(Size(60.0, _height));
  }
}

/// A cell whose height depends on its WIDTH, the way wrapped text does:
/// narrower means more lines means taller.
class _WrappingCell extends LeafRenderObjectWidget {
  const _WrappingCell();

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderWrappingCell();
  }
}

class _RenderWrappingCell extends RenderBox {
  @override
  void performLayout() {
    const contentWidth = 200.0;
    const lineHeight = 12.0;
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : contentWidth;
    final lines = (contentWidth / width).ceil();
    size = constraints.constrain(Size(width, lines * lineHeight));
  }
}

RenderBoardViewport<String> _viewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
}

Key _cellKey(int row, int col) {
  return ValueKey<String>("c${row}_$col");
}

void main() {
  // AC1 intrinsic sizing over item clusters.
  // Asserts: the row measures 4 * laneExtent + lanePadding while its
  // cellBuilder returns a 20px widget, read through tester.getRect of a
  // keyed cell probe.
  // Falsification: a cells-only rule returns 20 and fails.
  testWidgets("a week row of EMPTY cells is sized by four overlapping items", (
    tester,
  ) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(
        axis: LazyContentAxis(4, 30.0),
        laneExtent: 18.0,
        lanePadding: 4.0,
      ),
      columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    // Four MUTUALLY overlapping chips in week row 1: one cluster of four
    // lanes.
    for (var i = 0; i < 4; i++) {
      controller.addItem(
        _Item("chip$i"),
        const BoardSpan(rowStart: 1, colStart: 2, colSpan: 3),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280.0,
              height: 400.0,
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
                  return const ColoredBox(color: Color(0xFF4CAF50));
                },
              ),
            ),
          ),
        ),
      ),
    );

    // Setup sanity: the cluster really is four deep.
    expect(controller.laneCountOf("chip0"), 4);

    // The row holds its cluster: 4 * 18 + 4 = 76, not the cells' 20.
    final cell = tester.getRect(find.byKey(_cellKey(1, 0)));
    expect(cell.height, 76.0);
    // A row with no items keeps the cells-only measurement.
    final plain = tester.getRect(find.byKey(_cellKey(0, 0)));
    expect(plain.height, 20.0);
  });

  // The I15 content-axis assert, step 7's obligation: it needs both facts
  // in hand (a contributing cluster AND a null laneExtent), which only the
  // sizing step ever has together.
  // Falsification: the same board with laneExtent set pumps clean, and
  // with the items removed pumps clean too, so the case fails on the
  // conjunction and not on the config alone; an implementation asserting
  // on the CONFIG rather than a contributing cluster reddens the
  // no-items arm.
  testWidgets(
    "a content-sized axis with contributing item clusters and no "
    "laneExtent asserts",
    (tester) async {
      Widget boardFor(BoardController<String, _Item> controller) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280.0,
              height: 400.0,
              child: Board<String, _Item>(
                controller: controller,
                cellBuilder: (context, cell) {
                  return const SizedBox(width: 40.0, height: 20.0);
                },
                itemBuilder: (context, item) {
                  return const ColoredBox(color: Color(0xFF4CAF50));
                },
              ),
            ),
          ),
        );
      }

      BoardController<String, _Item> controllerWith({double? laneExtent}) {
        final controller = BoardController<String, _Item>(
          vsync: tester,
          rows: BoardAxisConfig(
            axis: LazyContentAxis(4, 30.0),
            laneExtent: laneExtent,
          ),
          columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
          keyOf: (item) {
            return item.key;
          },
          animationStyle: BoardAnimationStyle.disabled,
        );
        addTearDown(controller.dispose);
        return controller;
      }

      // The clean arms run FIRST. The check used to THROW from inside
      // layout, which poisoned the element tree for every later pump in
      // the same body; since item 7H of the 2026-09-23 audit fixes it
      // reports instead, and the order is kept as it was.
      // Arm 1: the SAME shape with laneExtent set pumps clean.
      final laned = controllerWith(laneExtent: 18.0);
      laned.addItem(
        const _Item("chip"),
        const BoardSpan(rowStart: 1, colStart: 2, colSpan: 3),
      );
      await tester.pumpWidget(boardFor(laned));
      expect(tester.takeException(), isNull);

      // Arm 2: null laneExtent with NO items pumps clean, which is what
      // reddens an assert written against the config alone.
      final empty = controllerWith();
      await tester.pumpWidget(boardFor(empty));
      expect(tester.takeException(), isNull);

      // Arm 2b: laneExtent on the OTHER axis, none on the content axis,
      // plus a single-track item. LEGAL: the lanes stack along the
      // columns, no contributor term exists for the rows, and the assert
      // must not fire. Reddens a predicate that tests only the content
      // config's laneExtent.
      final crossLaned = BoardController<String, _Item>(
        vsync: tester,
        rows: BoardAxisConfig(axis: LazyContentAxis(4, 30.0)),
        columns: BoardAxisConfig(
          axis: UniformAxis(7, 40.0),
          laneExtent: 18.0,
        ),
        keyOf: (item) {
          return item.key;
        },
        animationStyle: BoardAnimationStyle.disabled,
      );
      addTearDown(crossLaned.dispose);
      crossLaned.addItem(
        const _Item("chip"),
        const BoardSpan(rowStart: 1, colStart: 2, colSpan: 3),
      );
      await tester.pumpWidget(boardFor(crossLaned));
      expect(tester.takeException(), isNull);

      // Arm 3, LAST: null laneExtent AND a contributing single-track
      // item: the pump reports the error.
      final broken = controllerWith();
      broken.addItem(
        const _Item("chip"),
        const BoardSpan(rowStart: 1, colStart: 2, colSpan: 3),
      );
      await tester.pumpWidget(boardFor(broken));
      expect(tester.takeException(), isA<AssertionError>());
    },
  );

  // ------------------------------------------------------------------
  // Performance plan 2, C1: a cell is measured when it changes, not on
  // every layout (plans/2026-09-09-board-performance-2-plan.md).
  // ------------------------------------------------------------------

  /// The plan's Performance fixture: a 240 by 200 viewport over 4 uniform
  /// columns and 40 rows on a content-sized axis, with one item so the
  /// lane axis carries a cluster.
  ///
  /// [cellFor] builds each cell; the default counts its layouts at a
  /// fixed height.
  Future<BoardController<String, _Item>> pumpFixture(
    WidgetTester tester, {
    required bool contentSized,
    Widget Function(BoardCellView<String, _Item> cell)? cellFor,
    BoardAxisConfig? columns,
    bool addRepaintBoundaries = true,
  }) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(
        axis: contentSized
            ? LazyContentAxis(40, 40.0)
            : UniformAxis(40, 40.0),
        laneExtent: 12.0,
      ),
      columns: columns ?? BoardAxisConfig(axis: UniformAxis(4, 60.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.addItem(
      const _Item("a"),
      const BoardSpan(rowStart: 1, colStart: 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240.0,
              height: 200.0,
              child: Board<String, _Item>(
                controller: controller,
                addRepaintBoundaries: addRepaintBoundaries,
                cellBuilder: (context, cell) {
                  return cellFor == null
                      ? const _CountingCell(40.0)
                      : cellFor(cell);
                },
                itemBuilder: (context, item) {
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  // Performance plan 2 T1.
  // Asserts: a scroll that obtains no new vicinity lays out NO cell.
  // Falsification: measuring every obtained cell on every layout, which
  // is what the baseline did, reports 96 for this fixture's 48 mounted
  // cells: one measuring layout each under loose content-axis
  // constraints and one placement layout each under tight ones, which
  // never meet the framework's equal-constraints early return.
  testWidgets("a scroll runs no cell layout on a measured content-sized "
      "board", (tester) async {
    final controller = await pumpFixture(tester, contentSized: true);
    final viewport = _viewport(tester);
    // Setup sanity: the rows really were measured from the cells, so the
    // measuring path this case is about ran at least once.
    expect(controller.rows.axis.extentOf(0), 40.0);
    var mounted = 0;
    viewport.visitChildren((child) {
      mounted += 1;
    });
    expect(mounted, greaterThan(40));

    cellLayouts = 0;
    final layoutsBefore = viewport.debugPerformLayoutCount;
    (viewport.verticalOffset as ScrollPosition).jumpTo(1.0);
    await tester.pump();

    // Setup sanity: the scroll DID lay the viewport out, so a zero cell
    // count is a cheap layout and not an absent one.
    expect(viewport.debugPerformLayoutCount, layoutsBefore + 1);
    expect(cellLayouts, 0);
  });

  // Performance plan 2 T2.
  // Asserts: a payload write that changes a covering cell's height
  // re-measures its track, on a board holding no null-built cell, and so
  // through the cell host's own rebuild rather than through the render
  // object's data-channel relayout.
  // Falsification: C2's gate without C1's poke leaves nothing to
  // schedule the layout, and the track keeps its old extent.
  testWidgets("a relay rebuild that changes a cell's height re-measures "
      "its track with no null cell on the board", (tester) async {
    final controller = await pumpFixture(
      tester,
      contentSized: true,
      cellFor: (cell) {
        // The item's cell takes its height from the payload; every other
        // cell is fixed. Read through the VIEW's own controller, not a
        // captured one: the builder runs during the pump that produces
        // the local below.
        //
        // `cell.items` is the same rule a payload write rebuilds this
        // cell by, so what the builder reads and what re-runs it agree
        // by construction.
        for (final key in cell.items) {
          return _CountingCell(cell.controller.itemOf(key)!.height);
        }
        return const _CountingCell(40.0);
      },
    );
    final viewport = _viewport(tester);
    // Setup sanity: the covered cell drove its track, and the board
    // holds no null-built cell, which is what makes the render object's
    // gate inert here.
    expect(controller.rows.axis.extentOf(1), 40.0);

    cellLayouts = 0;
    final layoutsBefore = viewport.debugPerformLayoutCount;
    controller.updateItem("a", const _Item("a", 70.0));
    await tester.pump();

    expect(controller.rows.axis.extentOf(1), 70.0);
    expect(viewport.debugPerformLayoutCount, layoutsBefore + 1);
    // And the layout it scheduled measured the rebuilt cell alone: two
    // layouts for it, one measuring and one placing, plus a placement
    // layout for the other three cells of the row it grew.
    expect(cellLayouts, lessThanOrEqualTo(5));
  });

  // Performance plan 2 T4, the N1 contract.
  // Asserts: a cell that changes its own size without its host
  // rebuilding does NOT reach its track on the next layout, and does
  // reach it on the layout after a rebuild.
  // Falsification: the baseline re-measures on every layout, so the
  // scroll below picks the new height up and the first assertion reads
  // 70 instead of 40.
  testWidgets("an untracked size change applies at the cell's next "
      "rebuild", (tester) async {
    var height = 40.0;
    final controller = await pumpFixture(
      tester,
      contentSized: true,
      cellFor: (cell) {
        return cell.row == 0 && cell.col == 0
            ? _CountingCell(height, key: const ValueKey<String>("probe"))
            : const _CountingCell(40.0);
      },
    );
    final viewport = _viewport(tester);
    expect(controller.rows.axis.extentOf(0), 40.0);

    // The untracked change: the render object alone is told, and it is
    // laid out tight by the sweep, so it is its own relayout boundary
    // and nothing above it is dirtied.
    final probe = tester.renderObject<RenderCountingCell>(
      find.byKey(const ValueKey<String>("probe")),
    );
    probe.height = 70.0;
    (viewport.verticalOffset as ScrollPosition).jumpTo(1.0);
    await tester.pump();

    expect(controller.rows.axis.extentOf(0), 40.0);

    // A rebuild of that cell's host is what applies it. A selection
    // change reaching the cell is one; the height the builder returns
    // now agrees with what the render object already holds.
    height = 70.0;
    controller.setSelection(
      const BoardSelection(anchor: (row: 0, col: 0), focus: (row: 0, col: 0)),
    );
    await tester.pump();

    expect(controller.rows.axis.extentOf(0), 70.0);
  });

  // Performance plan 2 C1, the poke's WALK.
  // Asserts: a cell host's poke reaches the viewport under both settings
  // of `addRepaintBoundaries`, which is what decides whether the walk is
  // one hop or two. The delegate wraps every child in a `RepaintBoundary`
  // when the flag is true, so the surface is the viewport's grandchild
  // then and its child otherwise, and the walk has to find the render
  // object the viewport actually holds either way.
  // Falsification: a poke that assumed a fixed depth, or that read its
  // own parent data rather than the viewport's child's, leaves the track
  // at 40 for one of the two settings.
  for (final boundaries in <bool>[true, false]) {
    testWidgets(
      "a cell host's poke reaches the viewport with addRepaintBoundaries "
      "$boundaries",
      (tester) async {
        final controller = await pumpFixture(
          tester,
          contentSized: true,
          addRepaintBoundaries: boundaries,
          cellFor: (cell) {
            for (final key in cell.items) {
              return _CountingCell(cell.controller.itemOf(key)!.height);
            }
            return const _CountingCell(40.0);
          },
        );
        // Setup sanity: the covered cell drove its track before the write.
        expect(controller.rows.axis.extentOf(1), 40.0);

        controller.updateItem("a", const _Item("a", 90.0));
        await tester.pump();

        expect(controller.rows.axis.extentOf(1), 90.0);
      },
    );
  }

  // Performance plan 2 T5, the measuring-constraints guard.
  // Asserts: cells whose height depends on their WIDTH re-measure when
  // the column axis is swapped for a narrower one.
  // NOT INDEPENDENTLY RED on the baseline or after C1: the swap fires a
  // full structural notification and so a delegate rebuild, which pokes
  // every cell. Its subject is the second guard behind that route, the
  // constraints comparison, and the Implementation Log records the
  // scratch tree that showed it red with both the guard and the poke
  // removed.
  testWidgets("a column axis swap re-measures cells whose width changed", (
    tester,
  ) async {
    final controller = await pumpFixture(
      tester,
      contentSized: true,
      cellFor: (cell) {
        return const _WrappingCell();
      },
    );
    // Setup sanity: 4 columns of 60 wrap 200 of content to 4 lines of
    // 12.
    expect(controller.rows.axis.extentOf(0), 48.0);

    // The SAME track count, narrower. A swap that also changed the count
    // would add vicinities that have never been measured, and those
    // would grow the row whether or not the cells already mounted
    // re-measured, which is the defect an earlier version of this case
    // had.
    controller.columns = BoardAxisConfig(axis: UniformAxis(4, 30.0));
    await tester.pump();

    // 30 a column is 7 lines.
    expect(controller.rows.axis.extentOf(0), 84.0);
  });

  // ------------------------------------------------------------------
  // Cell measurement invalidation plan
  // (plans/2026-09-09-cell-measurement-invalidation-plan.md).
  // ------------------------------------------------------------------

  tearDown(() {
    RenderBoardViewport.debugCheckCellMeasurements = false;
  });

  /// The STALENESS FIXTURE: a content-sized row axis, builders hoisted to
  /// a stable identity so no delegate rebuild can heal anything, and cell
  /// content that reads its height from an inherited widget the test
  /// owns. Pumping a new value rebuilds the content and not the host.
  Future<BoardController<String, _Item>> pumpStaleness(
    WidgetTester tester, {
    required double height,
    BoardController<String, _Item>? controller,
  }) async {
    final c =
        controller ??
        BoardController<String, _Item>(
          vsync: tester,
          rows: BoardAxisConfig(
            axis: LazyContentAxis(40, 40.0),
            laneExtent: 12.0,
          ),
          columns: BoardAxisConfig(axis: UniformAxis(4, 60.0)),
          keyOf: (item) {
            return item.key;
          },
          animationStyle: BoardAnimationStyle.disabled,
        );
    if (controller == null) {
      addTearDown(c.dispose);
      c.addItem(const _Item("a"), const BoardSpan(rowStart: 1, colStart: 1));
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240.0,
              height: 200.0,
              child: _HeightScope(
                height: height,
                child: Board<String, _Item>(
                  controller: c,
                  cellBuilder: _inheritedCell,
                  itemBuilder: _emptyItem,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  // T1 (D1).
  // Asserts: after the inherited height changes, the track is UNCHANGED
  // (the documented contract, and the setup sanity for what follows);
  // after invalidateCellMeasurements the next layout takes the new
  // extent, at one measuring and one placement layout per mounted cell.
  // Falsification: red before D1 (does not compile); red after D1 with
  // the visitChildren walk replaced by a no-op (the track stays 40).
  testWidgets("invalidateCellMeasurements re-measures a cell its host "
      "never rebuilt", (tester) async {
    final controller = await pumpStaleness(tester, height: 40.0);
    final viewport = _viewport(tester);
    expect(controller.rows.axis.extentOf(0), 40.0);
    var mounted = 0;
    viewport.visitChildren((child) {
      mounted += 1;
    });
    // 48 cells and one item.
    expect(mounted, 49);

    await pumpStaleness(tester, height: 70.0, controller: controller);
    (viewport.verticalOffset as ScrollPosition).jumpTo(1.0);
    await tester.pump();
    // Setup sanity: the content rebuilt and the host did not, so the
    // track kept its extent.
    expect(controller.rows.axis.extentOf(0), 40.0);

    cellLayouts = 0;
    final layoutsBefore = viewport.debugPerformLayoutCount;
    controller.invalidateCellMeasurements();
    await tester.pump();

    expect(controller.rows.axis.extentOf(0), 70.0);
    expect(viewport.debugPerformLayoutCount, layoutsBefore + 1);
    // One measuring layout and one placement layout per mounted cell.
    expect(cellLayouts, 2 * 48);
  });

  // T3 (D1).
  // Asserts: a call from inside a cell builder asserts, and the message
  // names the door.
  // Falsification: an implementation with no _inLayout guard throws
  // NOTHING: the framework permits the mutation inside a layout callback
  // and markNeedsLayout returns early, so the pump completes clean and
  // takeException() is null.
  testWidgets("invalidateCellMeasurements from inside a cell builder "
      "asserts", (tester) async {
    var called = false;
    await pumpFixture(
      tester,
      contentSized: true,
      cellFor: (cell) {
        if (!called) {
          called = true;
          cell.controller.invalidateCellMeasurements();
        }
        return const _CountingCell(40.0);
      },
    );
    // Setup sanity: the builder ran and made the call.
    expect(called, isTrue);
    final exception = tester.takeException();
    expect(exception, isA<AssertionError>());
    expect(
      (exception as AssertionError).message.toString(),
      contains("invalidateCellMeasurements"),
    );
  });

  // T4 (D2).
  // Asserts: with the flag on, the first layout after the staleness
  // throws a FlutterError naming the cached and the fresh extent.
  // Falsification: red with the flag off, which is T5.
  testWidgets("the measurement check names a stale cell", (tester) async {
    final controller = await pumpStaleness(tester, height: 40.0);
    final viewport = _viewport(tester);
    expect(controller.rows.axis.extentOf(0), 40.0);

    RenderBoardViewport.debugCheckCellMeasurements = true;
    final layoutsBeforeStaleness = viewport.debugPerformLayoutCount;
    await pumpStaleness(tester, height: 70.0, controller: controller);
    // Setup sanity: the staleness pump laid the viewport out NOT AT ALL,
    // so the error below is the scroll's layout's and not a second one.
    expect(viewport.debugPerformLayoutCount, layoutsBeforeStaleness);
    final layoutsBefore = viewport.debugPerformLayoutCount;
    (viewport.verticalOffset as ScrollPosition).jumpTo(1.0);
    await tester.pump();

    // Setup sanity: the scroll DID lay the viewport out.
    expect(viewport.debugPerformLayoutCount, layoutsBefore + 1);
    final exception = tester.takeException();
    expect(exception, isA<FlutterError>());
    final message = (exception as FlutterError).toString();
    expect(message, contains("70.0"));
    expect(message, contains("40.0"));
    expect(message, contains("invalidateCellMeasurements"));
    // I2: the check read and did not write; the track is still stale.
    expect(controller.rows.axis.extentOf(0), 40.0);
  });

  // T5 (D2).
  // Asserts: with the flag at its default, the same layout throws
  // nothing, lays no cell out, and leaves the track stale.
  // Falsification: red against a check that runs unconditionally.
  testWidgets("the measurement check is off by default", (tester) async {
    final controller = await pumpStaleness(tester, height: 40.0);
    final viewport = _viewport(tester);
    expect(controller.rows.axis.extentOf(0), 40.0);
    expect(RenderBoardViewport.debugCheckCellMeasurements, isFalse);

    await pumpStaleness(tester, height: 70.0, controller: controller);
    cellLayouts = 0;
    final layoutsBefore = viewport.debugPerformLayoutCount;
    (viewport.verticalOffset as ScrollPosition).jumpTo(1.0);
    await tester.pump();

    expect(viewport.debugPerformLayoutCount, layoutsBefore + 1);
    expect(tester.takeException(), isNull);
    expect(cellLayouts, 0);
    expect(controller.rows.axis.extentOf(0), 40.0);
  });
}

/// Hoisted builders: identity-stable across pumps, so the Board's
/// delegate is never rebuilt and no host is poked by the fixture itself.
Widget? _inheritedCell(BuildContext context, BoardCellView<String, _Item> cell) {
  return const _InheritedHeightCell();
}

Widget _emptyItem(BuildContext context, BoardItemView<String, _Item> item) {
  return const SizedBox();
}

/// The inherited value the cell CONTENT reads, in its own build.
class _HeightScope extends InheritedWidget {
  const _HeightScope({required this.height, required super.child});

  final double height;

  static double of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_HeightScope>()!
        .height;
  }

  @override
  bool updateShouldNotify(_HeightScope oldWidget) {
    return oldWidget.height != height;
  }
}

/// Cell content whose size comes from the inherited value: a rebuild of
/// THIS widget, not of the cell host, is what a new value produces.
class _InheritedHeightCell extends StatelessWidget {
  const _InheritedHeightCell();

  @override
  Widget build(BuildContext context) {
    return _CountingCell(_HeightScope.of(context));
  }
}
