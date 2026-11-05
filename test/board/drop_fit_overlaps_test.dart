/// Tests for [BoardDropFit.offersOverlaps] through a pumped board: where
/// a refused move lands and a refused resize stops when the fit asks the
/// drop gate about placements that meet other items, and how often a drag
/// asks about each placement.
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

/// Whether [span] meets the item [other] of [controller], half-open on
/// both axes.
bool _meets(
  BoardController<String, _Item> controller,
  String other,
  BoardSpan span,
) {
  final o = controller.spanOf(other);
  if (o == null) {
    return false;
  }
  return span.startTrackOn(Axis.vertical) < o.endTrackOn(Axis.vertical) &&
      o.startTrackOn(Axis.vertical) < span.endTrackOn(Axis.vertical) &&
      span.startTrackOn(Axis.horizontal) < o.endTrackOn(Axis.horizontal) &&
      o.startTrackOn(Axis.horizontal) < span.endTrackOn(Axis.horizontal);
}

/// A row-axis span of one column from [row], [rows] rows long.
BoardSpan _rows(int row, [int rows = 1]) {
  return BoardSpan(rowStart: row, colStart: 0, rowSpan: rows);
}

/// A pumped board of one 40px column of [rowCount] 40px rows holding
/// [items], and a drag controller over it under [fit] whose drop gate is
/// [canDropAt], given the board's controller, recording each span it is
/// asked about in [asked].
class _Run {
  _Run._(
    this.controller,
    this.viewport,
    this.drag,
    this.origin,
    this.asked,
    this.moves,
    this.resizes,
  );

  final BoardController<String, _Item> controller;
  final RenderBoardViewport<String> viewport;
  final BoardDragController<String> drag;

  /// The board's global top-left.
  final Offset origin;

  /// Every span the drop gate was asked about.
  final List<BoardSpan> asked;

  /// Every span a committed move reported.
  final List<BoardSpan> moves;

  /// Every span a committed resize reported.
  final List<BoardSpan> resizes;

  static Future<_Run> pump(
    WidgetTester tester, {
    required int rowCount,
    required Map<String, BoardSpan> items,
    required BoardDropFit fit,
    required bool Function(
      BoardController<String, _Item> controller,
      String key,
      BoardSpan span,
    )
    canDropAt,
  }) async {
    final controller = BoardController<String, _Item>(
      vsync: tester,
      rows: BoardAxisConfig(axis: UniformAxis(rowCount, 40.0)),
      columns: BoardAxisConfig(axis: UniformAxis(1, 40.0)),
      keyOf: (item) {
        return item.key;
      },
      animationStyle: BoardAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    for (final MapEntry(:key, :value) in items.entries) {
      controller.addItem(_Item(key), value);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 40.0,
              height: rowCount * 40.0,
              child: Board<String, _Item>(
                controller: controller,
                cellBuilder: (context, cell) {
                  return const SizedBox.expand();
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
    final viewport = tester.allRenderObjects
        .whereType<RenderBoardViewport<String>>()
        .single;
    final asked = <BoardSpan>[];
    final moves = <BoardSpan>[];
    final resizes = <BoardSpan>[];
    final drag = BoardDragController<String>(
      boardController: controller,
      vsync: tester,
      config: BoardDragConfig<String>(
        onItemMoved: (key, span) {
          moves.add(span);
        },
        onItemResized: (key, span) {
          resizes.add(span);
        },
        primaryResizeEdges: BoardResizeEdges.trailing,
        canDropAt: (key, span) {
          asked.add(span);
          return canDropAt(controller, key, span);
        },
        dropFit: fit,
      ),
    );
    addTearDown(drag.dispose);
    final origin = tester.getTopLeft(find.byType(Board<String, _Item>));
    return _Run._(controller, viewport, drag, origin, asked, moves, resizes);
  }

  /// Lifts "m" at [local] on the board.
  void lift(Offset local) {
    drag.startDrag(
      key: "m",
      renderPort: viewport,
      pointerGlobal: origin + local,
    );
  }

  /// Moves the finger to [local] on the board and pumps a frame.
  Future<void> moveTo(WidgetTester tester, Offset local) async {
    drag.updateDrag(origin + local);
    await tester.pump();
  }
}

/// The fit BO1 to BO4 search with: every row of the one column, whatever
/// the region's free share.
BoardDropFit _fit({required bool offersOverlaps, bool clampResizes = false}) {
  return BoardDropFit(
    minFreeFraction: 0.0,
    rowRadius: double.infinity,
    colRadius: 0.0,
    clampResizes: clampResizes,
    offersOverlaps: offersOverlaps,
  );
}

void main() {
  // "m" lifted at its centre lands with its top a quarter row above row
  // 5, which it meets "b" on; row 4, over "a", is nearer than row 6.
  testWidgets("BO1 a refused move lands on the nearest placement the app "
      "admits, meeting an item it allows, under offersOverlaps, and on the "
      "nearest free one without it", (tester) async {
    for (final offers in const <bool>[true, false]) {
      final run = await _Run.pump(
        tester,
        rowCount: 8,
        items: <String, BoardSpan>{"m": _rows(0), "a": _rows(4), "b": _rows(5)},
        fit: _fit(offersOverlaps: offers),
        canDropAt: (controller, key, span) {
          return !_meets(controller, "b", span);
        },
      );
      run.lift(const Offset(20.0, 20.0));
      await run.moveTo(tester, const Offset(20.0, 210.0));
      // Setup sanity: the placement under the finger was refused.
      expect(run.asked, contains(_rows(5)), reason: "offers: $offers");
      run.drag.endDrag(cancel: false);
      await tester.pump();
      expect(run.moves, <BoardSpan>[
        offers ? _rows(4) : _rows(6),
      ], reason: "offers: $offers");
    }
  });

  // "m" over rows 0 and 1 has its bottom edge dragged into row 7, past
  // "a" at row 3 and into "b" at row 5.
  testWidgets("BO2 a refused resize stops at the first item in its way "
      "the app refuses under offersOverlaps, and at the first item in its "
      "way without it", (tester) async {
    for (final offers in const <bool>[true, false]) {
      final run = await _Run.pump(
        tester,
        rowCount: 8,
        items: <String, BoardSpan>{
          "m": _rows(0, 2),
          "a": _rows(3),
          "b": _rows(5),
        },
        fit: _fit(offersOverlaps: offers, clampResizes: true),
        canDropAt: (controller, key, span) {
          return !_meets(controller, "b", span);
        },
      );
      run.drag.startDrag(
        key: "m",
        renderPort: run.viewport,
        pointerGlobal: run.origin + const Offset(20.0, 78.0),
        edge: BoardResizeEdges.trailing,
        axis: Axis.vertical,
      );
      await run.moveTo(tester, const Offset(20.0, 300.0));
      // Setup sanity: the edge dragged to row 7 was refused.
      expect(run.asked, contains(_rows(0, 8)), reason: "offers: $offers");
      run.drag.endDrag(cancel: false);
      await tester.pump();
      expect(run.resizes, <BoardSpan>[
        offers ? _rows(0, 5) : _rows(0, 3),
      ], reason: "offers: $offers");
    }
  });

  // "o" covers rows 3 to 6; rows 2 and 7 are the nearest free ones.
  testWidgets("BO3 under offersOverlaps a drag asks about each placement "
      "once until the board or the config changes, where without it a new "
      "lean and a new refused placement ask again", (tester) async {
    for (final offers in const <bool>[true, false]) {
      final reason = "offers: $offers";
      final run = await _Run.pump(
        tester,
        rowCount: 10,
        items: <String, BoardSpan>{"m": _rows(0), "o": _rows(3, 4)},
        fit: _fit(offersOverlaps: offers),
        canDropAt: (controller, key, span) {
          return !_meets(controller, "o", span);
        },
      );
      run.lift(const Offset(20.0, 20.0));
      final landings = <BoardSpan?>[];
      await run.moveTo(tester, const Offset(20.0, 180.0));
      final first = run.asked.indexOf(_rows(4));
      landings.add(run.drag.currentTarget?.span);
      for (var i = 0; i < 4; i++) {
        await run.moveTo(tester, Offset(20.0, i.isEven ? 170.0 : 180.0));
        landings.add(run.drag.currentTarget?.span);
      }
      await run.moveTo(tester, const Offset(20.0, 220.0));
      landings.add(run.drag.currentTarget?.span);
      await run.moveTo(tester, const Offset(20.0, 260.0));
      landings.add(run.drag.currentTarget?.span);
      // Setup sanity: rows 4, 5 and 6 were each asked and refused, and
      // each fit landed on row 2 or row 7.
      for (final row in const <int>[4, 5, 6]) {
        expect(run.asked, contains(_rows(row)), reason: "$reason, row $row");
      }
      expect(first, isNot(-1), reason: reason);
      expect(landings, everyElement(anyOf(_rows(2), _rows(7))));
      final asks = run.asked.sublist(first);
      if (offers) {
        expect(asks.toSet(), hasLength(asks.length), reason: reason);
        final structural = run.asked.length;
        run.controller.addItem(const _Item("n"), _rows(9));
        await tester.pump();
        expect(
          run.asked.sublist(structural),
          contains(_rows(6)),
          reason: "$reason, a structural change",
        );
        final config = run.drag.config;
        final renewed = run.asked.length;
        run.drag.config = BoardDragConfig<String>(
          onItemMoved: config.onItemMoved,
          onItemResized: config.onItemResized,
          primaryResizeEdges: config.primaryResizeEdges,
          canDropAt: config.canDropAt,
          dropFit: config.dropFit,
        );
        // The resolve the setter schedules joins one already queued while
        // the last frame ran its post-frame callbacks, and the drag
        // controller asks for a frame only from an idle scheduler, so no
        // frame is scheduled for it here.
        tester.binding.scheduleFrame();
        await tester.pump();
        expect(
          run.asked.sublist(renewed),
          contains(_rows(6)),
          reason: "$reason, a new config",
        );
        expect(
          run.asked.where((span) {
            return span == _rows(6);
          }),
          hasLength(3),
          reason: reason,
        );
      } else {
        expect(
          asks.where((span) {
            return span == _rows(2);
          }).length,
          greaterThan(1),
          reason: "$reason, row 2",
        );
        expect(
          asks.where((span) {
            return span == _rows(7);
          }).length,
          greaterThan(1),
          reason: "$reason, row 7",
        );
      }
      run.drag.endDrag(cancel: true);
      await tester.pump();
    }
  });

  testWidgets("BO4 under offersOverlaps an answer whose ask ends the drag "
      "or changes the board is not kept: the next drag, or the re-resolve "
      "the change schedules, asks about that placement again", (tester) async {
    // The predicate writes "m"'s own span at its first ask about row 4,
    // which ends the session through the mutation cancel.
    var wrote = false;
    var run = await _Run.pump(
      tester,
      rowCount: 10,
      items: <String, BoardSpan>{"m": _rows(0), "o": _rows(3, 4)},
      fit: _fit(offersOverlaps: true),
      canDropAt: (controller, key, span) {
        if (!wrote && span == _rows(4)) {
          wrote = true;
          controller.moveItem("m", controller.spanOf("m")!);
        }
        return !_meets(controller, "o", span);
      },
    );
    run.lift(const Offset(20.0, 20.0));
    await run.moveTo(tester, const Offset(20.0, 180.0));
    // Setup sanity: the predicate wrote, which ended the drag.
    expect(wrote, isTrue);
    expect(run.controller.isDragging("m"), isFalse);
    expect(run.asked.last, _rows(4), reason: "nothing asked after the write");
    expect(run.drag.currentTarget, isNull);
    final asked = run.asked.length;
    run.lift(const Offset(20.0, 20.0));
    await run.moveTo(tester, const Offset(20.0, 180.0));
    expect(run.asked.sublist(asked), contains(_rows(4)), reason: "part 1");
    run.drag.endDrag(cancel: true);
    await tester.pump();

    // The predicate adds an item at row 9 at its first ask about row 4, a
    // structural change.
    var added = false;
    run = await _Run.pump(
      tester,
      rowCount: 10,
      items: <String, BoardSpan>{"m": _rows(0), "o": _rows(3, 4)},
      fit: _fit(offersOverlaps: true),
      canDropAt: (controller, key, span) {
        if (!added && span == _rows(4)) {
          added = true;
          controller.addItem(const _Item("n"), _rows(9));
        }
        return !_meets(controller, "o", span);
      },
    );
    run.lift(const Offset(20.0, 20.0));
    run.drag.updateDrag(run.origin + const Offset(20.0, 180.0));
    // Setup sanity: the predicate added the item.
    expect(added, isTrue);
    final before = run.asked.length;
    await tester.pump();
    expect(run.asked.sublist(before), contains(_rows(4)), reason: "part 2");
    run.drag.endDrag(cancel: true);
    await tester.pump();
  });
}
